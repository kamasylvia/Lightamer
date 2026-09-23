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

    /// Survival probe: the plane must be a HIT (make never runs). Probe
    /// byteCount matches the insert size so rebuilds never trip the
    /// insert-time LRU mid-assertion.
    private func assertSurvives(
        _ cache: PipeCache, _ key: PipeCacheKey, metal: MetalContext,
        builds: BuildCounter, _ label: String
    ) async throws {
        let before = builds.value
        _ = try await cache.plane(for: key, byteCount: 512 * 1024) {
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
        _ = try await cache.plane(for: key, byteCount: 512 * 1024) {
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

    /// Tier order (06-RESEARCH §7) — ONE sweep crossing two tiers: with a
    /// 12 MB budget (floor 8 MB) and 23 × 512 KB planes (11.5 MB total),
    /// the sweep's eviction window (total − floor = 3.5 MB = 7 planes)
    /// exhausts the 3 chain outputs FIRST, then peels the 4 OLDEST
    /// prefixes — masks and the base sentinel survive. Probes rebuild the
    /// 7 evicted planes (+3.5 MB ≤ budget), so no insert-time LRU ever
    /// interferes (D-06-01-T3-1 for the sentinel exemption).
    func testEnforceBudgetEvictsLayerTiersInOrder() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache(byteBudget: 12 * 1024 * 1024)
        let builds = BuildCounter()
        let half = 512 * 1024

        var chainKeys: [PipeCacheKey] = []
        for (index, layer) in [layerA, layerB, layerA].enumerated() {
            chainKeys.append(key(layer, position: 4 + index, upstream: UInt64(10 + index)))
        }
        var prefixKeys: [PipeCacheKey] = []
        for index in 0..<16 {
            prefixKeys.append(key(
                index.isMultiple(of: 2) ? layerA : layerB,
                position: PipeCacheKey.compositePosition,
                upstream: UInt64(100 + index)))
        }
        var maskKeys: [PipeCacheKey] = []
        for index in 0..<3 {
            maskKeys.append(key(layerA, position: PipeCacheKey.maskPosition, upstream: UInt64(200 + index)))
        }
        let basePlane = PipeCacheKey(
            imageID: imageID, pipeType: .preview, position: 1,
            upstreamHash: 300, roi: roi) // sentinel namespace

        let all = chainKeys + prefixKeys + maskKeys + [basePlane]
        XCTAssertEqual(all.count, 23)
        for k in all {
            _ = try await cache.plane(for: k, byteCount: half) { [metal, builds] in
                builds.value += 1
                return LayerCacheTests.tinyTexture(metal)
            }
        }
        XCTAssertEqual(builds.value, 23, "compared > 0 guard: every insert was a miss")
        var total = await cache.totalBytes
        XCTAssertEqual(total, 23 * half, "no insert-time LRU fired")

        // THE sweep: threshold 6.5 MB → evict to the 8 MB floor.
        _ = await cache.enforceBudget(now: 6500 * 1024, keeping: .init(
            currentImageID: imageID, previousImageID: nil))
        total = await cache.totalBytes
        XCTAssertEqual(total, 16 * half, "exactly 7 planes evicted (all chains + 4 oldest prefixes)")

        // Tier 0: every chain output is gone.
        for (index, k) in chainKeys.enumerated() {
            try await assertEvicted(cache, k, metal: metal, builds: builds, "chain \(index)")
        }
        // Tier 1: the four OLDEST prefixes went with them, newer survive.
        for index in 0..<4 {
            try await assertEvicted(cache, prefixKeys[index], metal: metal, builds: builds, "oldest prefix \(index)")
        }
        for index in 4..<16 {
            try await assertSurvives(cache, prefixKeys[index], metal: metal, builds: builds, "newer prefix \(index)")
        }
        // Tier 2: every mask plane outlives the sweep.
        for (index, k) in maskKeys.enumerated() {
            try await assertSurvives(cache, k, metal: metal, builds: builds, "mask \(index)")
        }
        // The base sentinel namespace is not a layer plane at all.
        try await assertSurvives(cache, basePlane, metal: metal, builds: builds,
                                 "base sentinel outlives the layer sweep")
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

    // ═══════════════════════════════════════════════════════════════════
    // Plan 06-01 T5 — composite incremental accounting (PipeCacheTests
    // style). Every scenario asserts EXACT hit/miss deltas + blend-pass
    // counts through the driver's stats channel. Chain shape: base =
    // terminal trio (base leg = [colorin], terminal leg = [colorout,
    // gamma]) + two layers A (bottom) / B (top), each one gain module.
    //
    // Cold run line-count reference (7 cache probes/misses):
    //   base:1 + A-chain:1 + A-prefix:1 + B-chain:1 + B-prefix:1
    //   + terminal:2 (colorout, gamma) = 7.
    // ═══════════════════════════════════════════════════════════════════

    private func compositeRun(
        _ image: DecodedImage, base: [any ModuleBoxing], stack: LayerStack,
        registry: ModuleRegistry, metal: MetalContext, cache: PipeCache
    ) async throws -> LayerCompositeResult {
        try await LayerCompositeDriver.composite(
            image: image, imageID: imageID, baseInstances: base,
            layerStack: stack, registry: registry, resolution: .preview,
            cache: cache, metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview)
    }

    private func gainLayer(
        _ gain: Float, name: String
    ) -> AdjustmentLayer {
        AdjustmentLayer(
            name: name, opacity: 1.0,
            chain: [ModuleInstance(
                module: TestGainModule.self,
                params: TestGainModule.Params(gain: gain))])
    }

    /// Scenario 1 — edit layer B's gain (top layer, N=2, K=2):
    ///   run1 cold: 0 hits / 8 misses. Reference line count:
    ///     base input + colorin (2: the BASE leg caches its input, unlike
    ///     sub-run legs) + A-chain + A-prefix + B-chain + B-prefix
    ///     + colorout + gamma = 8.
    ///   run2:      4 hits (base colorin + A chain + A prefix + terminal
    ///              gamma) / 2 misses (B chain from B onward + B prefix) /
    ///              1 blend pass. A's prefixHit = true, B's = false.
    func testEditTopLayerIncrementalAccounting() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = try makeGradientImage()
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = gainLayer(1.5, name: "A")
        let b = gainLayer(2.0, name: "B")
        stack.addAdjustment(a)
        stack.addAdjustment(b)

        let run1 = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let stats1 = await cache.stats
        XCTAssertEqual(stats1.hits, 0)
        XCTAssertEqual(stats1.misses, 8, "cold composite = 8 cache lines (see reference)")
        XCTAssertEqual(run1.blendPasses, 2)

        // Edit B's params (records are the live surface; boxes re-materialize).
        var edited = b.chain[0]
        try edited.setParams(TestGainModule.Params(gain: 3.0), as: TestGainModule.self)
        b.chain[0] = edited

        let run2 = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let delta = (await cache.stats) - stats1
        XCTAssertEqual(delta.hits, 4, "<K chain + <K prefix + base + terminal all hit")
        XCTAssertEqual(delta.misses, 2, "B chain self-B-miss + B prefix miss")
        XCTAssertEqual(run2.blendPasses, 1, "exactly one blend pass (N−K = 1)")
        XCTAssertEqual(run2.layerStats.first { $0.layerID == a.id }?.prefixHit, true)
        XCTAssertEqual(run2.layerStats.first { $0.layerID == b.id }?.prefixHit, false)
    }

    /// Scenario 1b — edit the BOTTOM layer (K=1): the K..N prefixes chain-
    /// invalidate (correct C1 semantics) while B's chain output survives.
    ///   run deltas: 3 hits (base colorin + B chain + terminal) / 3 misses
    ///   (A chain + A prefix + B prefix 连锁失配) / 2 blend passes.
    func testEditBottomLayerChainsPrefixMisses() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = try makeGradientImage()
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = gainLayer(1.5, name: "A")
        let b = gainLayer(2.0, name: "B")
        stack.addAdjustment(a)
        stack.addAdjustment(b)
        _ = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let stats1 = await cache.stats

        var edited = a.chain[0]
        try edited.setParams(TestGainModule.Params(gain: 2.5), as: TestGainModule.self)
        a.chain[0] = edited

        let run2 = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let delta = (await cache.stats) - stats1
        XCTAssertEqual(delta.hits, 3, "base colorin + B chain + terminal survive")
        XCTAssertEqual(delta.misses, 3, "A chain + A prefix + B prefix (chained-invalidate)")
        XCTAssertEqual(run2.blendPasses, 2, "N−K = 2 blend passes")
        XCTAssertEqual(run2.layerStats.first { $0.layerID == b.id }?.prefixHit, false,
                       "B's prefix chain-invalidates through A's new prefix hash")
    }

    /// Scenario 2 — REORDER A/B after a warm run: every chain-output key is
    /// order-free (layerID namespaces) so both chains + base + terminal hit
    /// (4 hits / 0 chain misses); BOTH prefixes miss (the fold is
    /// order-dependent — C1 recomposites) → exactly 2 blend passes.
    func testReorderKeepsChainCachesAlive() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = try makeGradientImage()
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = gainLayer(1.5, name: "A")
        let b = gainLayer(2.0, name: "B")
        stack.addAdjustment(a)
        stack.addAdjustment(b)
        _ = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let stats1 = await cache.stats

        stack.reorder(id: a.id, to: 1) // A was bottom (0) → now top

        let run2 = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let delta = (await cache.stats) - stats1
        XCTAssertEqual(delta.hits, 4, "both chains + base + terminal fully survive the reorder")
        XCTAssertEqual(delta.misses, 2, "only the two composite prefixes re-key")
        XCTAssertEqual(run2.blendPasses, 2, "re-blend only — zero chain re-renders")
        // Content-level corroboration (L020 ③): the reordered composite is
        // byte-identical to a fresh composite of a stack built bottom-to-
        // top as [B, A] (same composition order).
        var reference = LayerStack(baseLayer: BackgroundLayer())
        reference.addAdjustment(b)
        reference.addAdjustment(a)
        let fresh = try await compositeRun(image, base: base, stack: reference, registry: registry, metal: metal, cache: PipeCache())
        let reordered = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let reorderedBytes = Self.planeBytes(reordered.output, metal: metal)
        let freshBytes = Self.planeBytes(fresh.output, metal: metal)
        XCTAssertEqual(reorderedBytes.count, freshBytes.count)
        XCTAssertGreaterThan(reorderedBytes.count, 0, "防空转 guard")
        XCTAssertTrue(reorderedBytes.elementsEqual(freshBytes), "reorder must recomposite to identical bytes")
    }

    /// L014 fence + full raw read of a float32 RGBA plane.
    private static func planeBytes(
        _ texture: any MTLTexture, metal: MetalContext
    ) -> [UInt8] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return bytes
    }

    /// Scenario 3 — visibility vs enable (semantics differ structurally):
    /// hidden B → its sub-run still probes (chain hit — cache survives),
    /// NO prefix probe, zero blends; disabled B → no sub-run AT ALL.
    func testHiddenAndDisabledLayerAccounting() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = try makeGradientImage()
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = gainLayer(1.5, name: "A")
        let b = gainLayer(2.0, name: "B")
        stack.addAdjustment(a)
        stack.addAdjustment(b)
        _ = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let stats1 = await cache.stats

        // Hidden B.
        b.isVisible = false
        let hidden = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        var delta = (await cache.stats) - stats1
        XCTAssertEqual(delta.hits, 5, "base + A chain + A prefix + B chain (cache survives) + terminal")
        XCTAssertEqual(delta.misses, 0, "hiding never invalidates anything")
        XCTAssertEqual(hidden.blendPasses, 0, "hidden layer performs no blend")
        XCTAssertEqual(hidden.layerStats.count, 2, "B still reports a (sub-run) leg")

        // Disabled B: removed from processing entirely.
        let statsHidden = await cache.stats
        b.enabled = false
        let disabled = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        delta = (await cache.stats) - statsHidden
        XCTAssertEqual(delta.hits, 4, "base + A chain + A prefix + terminal (no B probes at all)")
        XCTAssertEqual(delta.misses, 0)
        XCTAssertEqual(disabled.blendPasses, 0)
        XCTAssertEqual(disabled.layerStats.count, 1, "disabled layer produces no composite leg")
    }

    /// Scenario 4 — blend-attribute edit (opacity; the mask-version
    /// placeholder rides the same triple): ONLY the layer's own prefix
    /// misses; its chain, everything below, and the terminal all hit.
    func testOpacityEditInvalidatesOnlyOwnPrefix() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = try makeGradientImage()
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = gainLayer(1.5, name: "A")
        let b = gainLayer(2.0, name: "B")
        stack.addAdjustment(a)
        stack.addAdjustment(b)
        _ = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let stats1 = await cache.stats

        b.opacity = 0.5

        let run2 = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let delta = (await cache.stats) - stats1
        XCTAssertEqual(delta.hits, 5, "base + A chain + A prefix + B chain + terminal")
        XCTAssertEqual(delta.misses, 1, "only B's own prefix (blend triple folded)")
        XCTAssertEqual(run2.blendPasses, 1)
        XCTAssertEqual(run2.layerStats.first { $0.layerID == b.id }?.prefixHit, false)
    }

    // ── shared T5 fixture ──

    private func makeRegistry() async -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    private func makeGradientImage(width: Int = 48, height: Int = 32) throws -> DecodedImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                pixels[o + 0] = 0.1 + 0.7 * Float(x) / Float(width - 1)
                pixels[o + 1] = 0.2 + 0.5 * Float(y) / Float(height - 1)
                pixels[o + 2] = 0.3
                pixels[o + 3] = 1.0
            }
        }
        let bitmap = pixels.withUnsafeBytes { Data($0) }
        return DecodedImage(
            ciImage: CIImage(
                bitmapData: bitmap,
                bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
                size: CGSize(width: width, height: height),
                format: .RGBAf, colorSpace: WorkingSpace.colorSpace),
            rawTech: RAWTechnicalParams(blackLevel: 0.0),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }
}
