@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-01 T3/T5 — the layer dimension of the pipe cache: `layerID`
/// namespace isolation, the reserved plane classes (composite prefix / mask),
/// the enforceBudget layer-tier eviction order, and (T5) the composite
/// hit/miss accounting scenarios.
///
/// All scenarios are REAL comparison/accounting loops with `compared > 0`
/// guards (L020 ③): survival is proven by a make-closure that must NOT run
/// (hit) or MUST run (miss) — never by re-reading our own bookkeeping.
final class LayerCacheTests: XCTestCase {

    // ── Fixtures ──

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    /// 1×1 float32 texture (byteCount drives the accounting, not the size).
    private static func tinyTexture(_ metal: MetalContext) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: 1, height: 1,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return metal.device.makeTexture(descriptor: d)!
    }

    private final class BuildCounter: @unchecked Sendable {
        var value = 0
    }

    private let roi = ROI(x: 0, y: 0, width: 1, height: 1, scale: 1.0)
    private let imageID = UUID()
    private let layerA = UUID()
    private let layerB = UUID()

    private func key(
        _ layer: UUID, position: Int, upstream: UInt64 = 1
    ) -> PipeCacheKey {
        PipeCacheKey(
            imageID: imageID, pipeType: .preview, position: position,
            upstreamHash: upstream, roi: roi, layerID: layer
        )
    }

    /// Insert one plane; `builds` bumps ONLY on a miss (the make closure).
    private func insert(
        _ cache: PipeCache, _ key: PipeCacheKey, megabytes: Int = 1,
        metal: MetalContext, builds: BuildCounter
    ) async throws {
        _ = try await cache.plane(for: key, byteCount: megabytes * 1024 * 1024) {
            [metal, builds] in
            builds.value += 1
            return LayerCacheTests.tinyTexture(metal)
        }
    }

    /// Survival probe: the plane must be a HIT (make never runs).
    private func assertSurvives(
        _ cache: PipeCache, _ key: PipeCacheKey, metal: MetalContext,
        builds: BuildCounter, _ label: String
    ) async throws {
        let before = builds.value
        _ = try await cache.plane(for: key, byteCount: 1024 * 1024) {
            [metal, builds] in
            builds.value += 1
            return LayerCacheTests.tinyTexture(metal)
        }
        XCTAssertEqual(builds.value, before, "\(label): plane must survive (hit, no rebuild)")
    }

    /// Eviction probe: the plane must be a MISS (make runs).
    private func assertEvicted(
        _ cache: PipeCache, _ key: PipeCacheKey, metal: MetalContext,
        builds: BuildCounter, _ label: String
    ) async throws {
        let before = builds.value
        _ = try await cache.plane(for: key, byteCount: 1024 * 1024) {
            [metal, builds] in
            builds.value += 1
            return LayerCacheTests.tinyTexture(metal)
        }
        XCTAssertEqual(builds.value, before + 1, "\(label): plane must be gone (miss)")
    }

    // ── T3: layerID namespace isolation ──

    func testLayerIDIsolatesCacheLines() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let builds = BuildCounter()

        // Layer A's chain output line…
        try await insert(cache, key(layerA, position: 3, upstream: 100), metal: metal, builds: builds)
        XCTAssertEqual(builds.value, 1)
        // …is INVISIBLE to layer B at the identical (position, hash, roi):
        // different layerID = different key = miss.
        try await assertEvicted(cache, key(layerB, position: 3, upstream: 100), metal: metal, builds: builds, "other layer same shape")
        // …and still a hit for layer A afterwards (B's miss did not touch it).
        try await assertSurvives(cache, key(layerA, position: 3, upstream: 100), metal: metal, builds: builds, "layer A line")
        XCTAssertEqual(builds.value, 2, "compared > 0 guard: exactly one rebuild happened")
    }

    /// Pure key-shape classification (no GPU): the reserved positions map
    /// onto the three layer tiers; the base sentinel is tierless.
    func testLayerTierClassification() {
        XCTAssertNil(PipeCacheKey(
            imageID: imageID, pipeType: .preview, position: 0,
            upstreamHash: 1, roi: roi
        ).layerTier, "base sentinel namespace is NOT a layer plane")
        XCTAssertNil(PipeCacheKey(
            imageID: imageID, pipeType: .preview, position: 5,
            upstreamHash: 1, roi: roi, layerID: PipeCacheKey.baseLayerSentinelID
        ).layerTier)
        XCTAssertEqual(
            PipeCacheKey(imageID: imageID, pipeType: .preview, position: 2,
                         upstreamHash: 1, roi: roi, layerID: layerA).layerTier,
            .layerChainOutput)
        XCTAssertEqual(
            PipeCacheKey(imageID: imageID, pipeType: .preview,
                         position: PipeCacheKey.compositePosition,
                         upstreamHash: 1, roi: roi, layerID: layerA).layerTier,
            .compositePrefix)
        XCTAssertEqual(
            PipeCacheKey(imageID: imageID, pipeType: .preview,
                         position: PipeCacheKey.maskPosition,
                         upstreamHash: 1, roi: roi, layerID: layerA).layerTier,
            .maskPlane)
        // Reserved positions never collide with chain positions.
        XCTAssertLessThan(PipeCacheKey.compositePosition, 0)
        XCTAssertLessThan(PipeCacheKey.maskPosition, PipeCacheKey.compositePosition)
    }

    // ── T3: enforceBudget layer-tier eviction order ──

    /// Tier order (06-RESEARCH §7): layer chain outputs → composite
    /// prefixes → mask planes; the base/terminal sentinel namespace is
    /// never touched by the layer sweep (D-06-01-T3-1).
    func testEnforceBudgetEvictsLayerTiersInOrder() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        // 3 MB budget → hysteresis floor = min(2MB, 3MB×2/3) = 2 MB.
        let cache = PipeCache(byteBudget: 3 * 1024 * 1024)
        let builds = BuildCounter()

        let chainA = key(layerA, position: 4, upstream: 10)
        let chainB = key(layerB, position: 4, upstream: 20)
        let prefixA = key(layerA, position: PipeCacheKey.compositePosition, upstream: 30)
        let maskA = key(layerA, position: PipeCacheKey.maskPosition, upstream: 40)
        let basePlane = PipeCacheKey(
            imageID: imageID, pipeType: .preview, position: 1,
            upstreamHash: 50, roi: roi) // sentinel namespace

        // 4 MB across the layer tiers + 1 MB base plane = 5 MB.
        for k in [chainA, chainB, prefixA, maskA, basePlane] {
            try await insert(cache, k, metal: metal, builds: builds)
        }
        XCTAssertEqual(builds.value, 5, "compared > 0 guard: five inserts were misses")

        // Sweep 1 (threshold 3 MB): evict to the 2 MB floor — the two
        // chain outputs go first (lowest tier), prefix + mask + base stay.
        _ = await cache.enforceBudget(now: 3 * 1024 * 1024, keeping: .init(
            currentImageID: imageID, previousImageID: nil))
        try await assertEvicted(cache, chainA, metal: metal, builds: builds, "chain output A")
        try await assertEvicted(cache, chainB, metal: metal, builds: builds, "chain output B")
        try await assertSurvives(cache, prefixA, metal: metal, builds: builds, "prefix before mask")
        try await assertSurvives(cache, maskA, metal: metal, builds: builds, "mask tier last resort")
        try await assertSurvives(cache, basePlane, metal: metal, builds: builds, "base sentinel untouched by layer tiers")

        // Sweep 2: refill chains + a second prefix (5 MB total again) —
        // the sweep eats both chains AND both prefixes before the mask.
        let chainC = key(layerA, position: 5, upstream: 60)
        let chainD = key(layerB, position: 5, upstream: 70)
        let prefixB = key(layerB, position: PipeCacheKey.compositePosition, upstream: 80)
        for k in [chainC, chainD, prefixB] {
            try await insert(cache, k, metal: metal, builds: builds)
        }
        _ = await cache.enforceBudget(now: 3 * 1024 * 1024, keeping: .init(
            currentImageID: imageID, previousImageID: nil))
        try await assertEvicted(cache, chainC, metal: metal, builds: builds, "refilled chain C")
        try await assertEvicted(cache, chainD, metal: metal, builds: builds, "refilled chain D")
        try await assertEvicted(cache, prefixA, metal: metal, builds: builds, "prefix A after chains")
        try await assertEvicted(cache, prefixB, metal: metal, builds: builds, "prefix B after chains")
        try await assertSurvives(cache, maskA, metal: metal, builds: builds, "mask plane outlives every layer tier")
        try await assertSurvives(cache, basePlane, metal: metal, builds: builds, "base sentinel outlives the whole layer sweep")
    }

    // ── T3: FULL cold-layer policy constants (D-06-CONTEXT-8) ──

    func testLayerCachePolicyConstants() {
        XCTAssertEqual(LayerCachePolicy.preview, .init(
            cachesAllPrefixes: true, cachesAllLayerOutputs: true))
        XCTAssertEqual(LayerCachePolicy.fullCacheAll, LayerCachePolicy.preview)
        // The D-06-CONTEXT-8 shape: prefixes kept (windowed = small), cold
        // layer chain outputs composite-and-discard.
        XCTAssertEqual(LayerCachePolicy.fullColdLayer, .init(
            cachesAllPrefixes: true, cachesAllLayerOutputs: false))
        XCTAssertNotEqual(LayerCachePolicy.fullColdLayer, LayerCachePolicy.fullCacheAll)
    }

    /// `invalidateLayer` drops the layer's chain-output lines but keeps its
    /// composite prefixes (the cold-blend cleanup must not thrash prefixes).
    func testInvalidateLayerKeepsPrefixes() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let builds = BuildCounter()

        let chain = key(layerA, position: 2, upstream: 11)
        let prefix = key(layerA, position: PipeCacheKey.compositePosition, upstream: 12)
        try await insert(cache, chain, metal: metal, builds: builds)
        try await insert(cache, prefix, metal: metal, builds: builds)
        XCTAssertEqual(builds.value, 2)

        await cache.invalidateLayer(imageID: imageID, layerID: layerA)
        try await assertEvicted(cache, chain, metal: metal, builds: builds, "chain line swept")
        try await assertSurvives(cache, prefix, metal: metal, builds: builds, "prefix survives the chain sweep")
        // Other layers untouched.
        let other = key(layerB, position: 2, upstream: 13)
        try await insert(cache, other, metal: metal, builds: builds)
        await cache.invalidateLayer(imageID: imageID, layerID: layerA)
        try await assertSurvives(cache, other, metal: metal, builds: builds, "layer B untouched by layer A's sweep")
    }
}
