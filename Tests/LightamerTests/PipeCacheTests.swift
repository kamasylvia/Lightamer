@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// FOUND-04 SC#2 cache semantics (Plan 02-02-06): run1 all-miss → param
/// change → partial hit (upstream survives) → undo → full hit; disabled
/// skip; FULL no-intermediate-cache policy; LRU byte-budget eviction;
/// decodeParamsHash total invalidation; the hash-chain composition itself.
///
/// Cache-line model under test (02-02 implementation): position 0 = the
/// input plane (keyed on decodeParamsHash only), module i's output = line
/// i+1. A 4-module chain therefore reports run1 misses == 5 (input + 4) —
/// matching the plan — and a mid-chain param change splits hits/misses
/// exactly at the changed module's line.
///
/// Synthetic CIImages only — the suite runs anywhere, no RAW dependency.
/// GPU-dependent tests guard per the VALIDATION "Metal compute requires a
/// GPU context" rule.
final class PipeCacheTests: XCTestCase {

    // ── SC#2 instrumentation: per-module process-call counter ──

    /// Sendable call counter (bumped inside `process`, read from the test).
    private actor CallCounter {
        private var values: [String: Int] = [:]
        func bump(_ tag: String) { values[tag, default: 0] += 1 }
        func value(_ tag: String) -> Int { values[tag] ?? 0 }
    }

    /// Mutable-int box for @Sendable closures (build counters at the
    /// PipeCache unit level).
    private final class IntBox: @unchecked Sendable {
        var value = 0
    }

    /// Generic wrapper that counts `process` invocations per module tag and
    /// delegates the real work (gain / pass-through kernel) to the inner
    /// module. Forwarded statics keep the v50 order + op identity intact.
    private final class Instrumented<Inner: IOPModule>: IOPModule {

        typealias Params = Inner.Params

        let tag: String
        let counter: CallCounter
        let inner: Inner

        init(tag: String, counter: CallCounter, inner: Inner) {
            self.tag = tag
            self.counter = counter
            self.inner = inner
        }

        static var opName: String { Inner.opName }
        static var iopOrder: Float { Inner.iopOrder }
        static var flags: IOPFlags { Inner.flags }
        static var defaultColorspace: IOPColorspace { Inner.defaultColorspace }

        func reloadDefaults(image: DecodedImage) async -> Params {
            await inner.reloadDefaults(image: image)
        }

        func commitParams(_ params: Params, into piece: inout IOPiece) {
            inner.commitParams(params, into: &piece)
        }

        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
            roi = input
        }

        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
            input = roi
        }

        func process(
            input: any MTLTexture,
            output: any MTLTexture,
            roiIn: ROI,
            roiOut: ROI,
            piece: inout IOPiece,
            metal: MetalContext
        ) async throws {
            await counter.bump(tag)
            try await inner.process(
                input: input, output: output, roiIn: roiIn, roiOut: roiOut,
                piece: &piece, metal: metal
            )
        }
    }

    // ── Fixtures ──

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    /// Synthetic flat-gray image (no RAW dependency). `blackLevel` varies
    /// `decodeParamsHash` for the total-invalidation test.
    private func makeImage(width: Int, height: Int, blackLevel: Double = 0.0) -> DecodedImage {
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return DecodedImage(
            ciImage: ci,
            rawTech: RAWTechnicalParams(blackLevel: blackLevel),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    private func makeGainBox(
        _ tag: String, priority: Int, _ counter: CallCounter, gain: Float
    ) async -> ModuleBox<Instrumented<TestGainModule>> {
        let box = ModuleBox(
            module: Instrumented(tag: tag, counter: counter, inner: TestGainModule()),
            multiPriority: priority, multiName: tag
        )
        box.setParams(TestGainModule.Params(gain: gain))
        return box
    }

    private func makePassBox(
        _ tag: String, priority: Int, _ counter: CallCounter
    ) async -> ModuleBox<Instrumented<PassthroughModule>> {
        let box = ModuleBox(
            module: Instrumented(tag: tag, counter: counter, inner: PassthroughModule()),
            multiPriority: priority, multiName: tag
        )
        box.setParams(PassthroughModule.Params())
        return box
    }

    /// [G1, P1, G2, P2] — all iopOrder 50.5, disambiguated by multiPriority
    /// (the same (order, priority) sort the pipe runs). Returns the gain
    /// boxes typed so tests can `setParams` them.
    private func makeChain(
        _ counter: CallCounter, gain2: Float = 1.0
    ) async -> (instances: [any ModuleBoxing], g1: ModuleBox<Instrumented<TestGainModule>>, g2: ModuleBox<Instrumented<TestGainModule>>) {
        let g1 = await makeGainBox("g1", priority: 0, counter, gain: 1.0)
        let p1 = await makePassBox("p1", priority: 1, counter)
        let g2 = await makeGainBox("g2", priority: 2, counter, gain: gain2)
        let p2 = await makePassBox("p2", priority: 3, counter)
        return ([g1, p1, g2, p2], g1, g2)
    }

    private func run(
        _ image: DecodedImage,
        _ instances: [any ModuleBoxing],
        _ imageID: UUID,
        _ resolution: PipeResolution,
        _ cache: PipeCache,
        _ metal: MetalContext
    ) async throws -> RenderPipeline.PipeRunStats {
        let result = try await RenderPipeline.process(
            image: image, instances: instances, imageID: imageID,
            resolution: resolution, cache: cache, metal: metal, longEdge: nil
        )
        return result.1
    }

    /// 1×1 float32 texture for unit-level cache tests (byteCount drives the
    /// accounting, not the texture size).
    private static func tinyTexture(_ metal: MetalContext) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: 1, height: 1,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return metal.device.makeTexture(descriptor: d)!
    }

    // ── 1. SC#2 canonical: param change invalidates only downstream ──

    func testParamChangeInvalidatesOnlyDownstream() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let counter = CallCounter()
        let image = makeImage(width: 32, height: 32)
        let imageID = UUID()
        let (instances, _, g2) = await makeChain(counter)

        // run1: all miss — input + 4 module positions, zero hits.
        let stats1 = try await run(image, instances, imageID, .preview, cache, metal)
        XCTAssertEqual(stats1.hits, 0)
        XCTAssertEqual(stats1.misses, 5, "run1 = input plane + 4 module outputs, all miss")
        XCTAssertEqual(stats1.planesRendered, 5)

        // run2: identical everything — FULL hit, ZERO work (the fast path).
        // The walk probes TOP-DOWN and stops at the FIRST hit: only p2's
        // line (the top) is probed, the upstream lines aren't even touched —
        // upstream zero-computation is the entire point of the fast path.
        let stats2 = try await run(image, instances, imageID, .preview, cache, metal)
        XCTAssertEqual(stats2.hits, 1)
        XCTAssertEqual(stats2.misses, 0)
        XCTAssertEqual(stats2.planesRendered, 0, "cache hit path must skip every dispatch")

        // run3: change G2's params (mid-chain) — p2's line key changes
        // (g2's hash is folded into every line at or above g2), so p2 miss
        // → g2 miss → p1's line (params below g2 unchanged) HIT → return.
        // NOTE: the plan sketched hits == 2 / misses == 3 here, which is
        // arithmetically inconsistent with its own run1 (5 = input + 4) and
        // run3 (5 hits) — it requires the input plane to be uncached. The
        // implemented model caches the input at position 0 (Darktable's
        // pipe->input cacheline); with the top-down short-circuit the exact
        // probe split is 1 hit (p1's cached plane feeds g2) / 2 misses.
        g2.setParams(TestGainModule.Params(gain: 1.5))
        let stats3 = try await run(image, instances, imageID, .preview, cache, metal)
        XCTAssertEqual(stats3.hits, 1, "p1's line survived the mid-chain change and feeds g2")
        XCTAssertEqual(stats3.misses, 2, "g2 and everything above it recompute")
        XCTAssertEqual(stats3.planesRendered, 2)

        // run4: revert (undo) — p2's OLD key matches the line cached in
        // run1/run2 → immediate hit, zero work (old planes still cached).
        g2.setParams(TestGainModule.Params(gain: 1.0))
        let stats4 = try await run(image, instances, imageID, .preview, cache, metal)
        XCTAssertEqual(stats4.hits, 1)
        XCTAssertEqual(stats4.misses, 0)
        XCTAssertEqual(stats4.planesRendered, 0)

        // The terminal-chain variant [colorin, testgain, colorout, gamma]
        // re-asserts the same semantics in Plan 02-04's GoldenColorTests
        // once the terminal trio exists.
    }

    // ── 2. Disabled piece behaves as removed ──

    func testDisabledPieceBehavesAsRemoved() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let counter = CallCounter()
        let image = makeImage(width: 32, height: 32)
        let imageID = UUID()
        let (instances, g1, _) = await makeChain(counter)

        g1.enabled = false
        let stats1 = try await run(image, instances, imageID, .preview, cache, metal)
        let g1Calls1 = await counter.value("g1")
        XCTAssertEqual(g1Calls1, 0, "disabled piece must not process")
        XCTAssertEqual(stats1.misses, 4, "input + 3 enabled outputs; the disabled slot contributes no key step")
        XCTAssertEqual(stats1.hits, 0)
        XCTAssertEqual(stats1.planesRendered, 4)

        // Re-enable: g1's params re-enter the chain, so every line at or
        // above g1 flips → p2/g2/p1/g1 all miss; only the input plane
        // (position 0, keyed on decodeParamsHash alone) hits.
        g1.enabled = true
        let stats2 = try await run(image, instances, imageID, .preview, cache, metal)
        let g1Calls2 = await counter.value("g1")
        XCTAssertEqual(g1Calls2, 1, "re-enabled piece processes exactly once")
        XCTAssertEqual(stats2.hits, 1, "the input plane is untouched by g1's state")
        XCTAssertEqual(stats2.misses, 4)
        XCTAssertEqual(stats2.planesRendered, 4)
    }

    // ── 3. FULL policy: intermediates never cached ──

    func testFullPipeSkipsIntermediateCaching() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let counter = CallCounter()
        let image = makeImage(width: 64, height: 64)
        let imageID = UUID()
        let (instances, _, _) = await makeChain(counter)

        let stats1 = try await run(image, instances, imageID, .full, cache, metal)
        let planeBytes = 64 * 64 * WorkingSpace.bytesPerPixel
        XCTAssertEqual(stats1.misses, 2, "FULL caches only the input plane + the final output")
        XCTAssertLessThanOrEqual(stats1.misses, 2)
        XCTAssertEqual(stats1.hits, 0)
        XCTAssertEqual(stats1.planesRendered, 5, "all modules still execute on the first FULL run")
        let bytes = await cache.totalBytes
        XCTAssertEqual(bytes, 2 * planeBytes, "exactly two planes are held despite 4 pieces")

        // Second identical FULL run: the top (final-output) line hits
        // immediately — short-circuit, zero work, upstream never probed.
        let stats2 = try await run(image, instances, imageID, .full, cache, metal)
        XCTAssertEqual(stats2.hits, 1)
        XCTAssertEqual(stats2.misses, 0)
        XCTAssertEqual(stats2.planesRendered, 0)
    }

    // ── 4. LRU byte-budget eviction ──

    func testLRUEvictionRespectsBudget() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let megabyte = 1024 * 1024
        let cache = PipeCache(byteBudget: 8 * megabyte) // effective floor ≈ 5.33MB
        let imageID = UUID()
        let roi = ROI(x: 0, y: 0, width: 1, height: 1, scale: 1.0)

        for position in 0..<9 {
            _ = try await cache.plane(
                for: PipeCacheKey(
                    imageID: imageID, pipeType: .preview, position: position,
                    upstreamHash: UInt64(position), roi: roi
                ),
                byteCount: megabyte
            ) { [metal] in PipeCacheTests.tinyTexture(metal) }
        }
        // 9MB inserted > 8MB budget → evicted down to ≤ 5.33MB (5 planes).
        let total = await cache.totalBytes
        XCTAssertLessThanOrEqual(total, 8 * megabyte, "totalBytes ≤ budget after eviction")
        XCTAssertGreaterThanOrEqual(total, 5 * megabyte, "eviction stops at the hysteresis floor, not at zero")
        let stats = await cache.stats
        XCTAssertGreaterThanOrEqual(stats.misses, 9)
    }

    func testLRUEvictionKeepsRecentlyTouchedPlanes() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let megabyte = 1024 * 1024
        let cache = PipeCache(byteBudget: 8 * megabyte)
        let imageID = UUID()
        let roi = ROI(x: 0, y: 0, width: 1, height: 1, scale: 1.0)
        let builds = IntBox()

        func key(_ position: Int) -> PipeCacheKey {
            PipeCacheKey(
                imageID: imageID, pipeType: .preview, position: position,
                upstreamHash: UInt64(position), roi: roi
            )
        }

        func insert(_ position: Int) async throws {
            _ = try await cache.plane(for: key(position), byteCount: megabyte)  { [metal, builds] in
                builds.value += 1
                return PipeCacheTests.tinyTexture(metal)
            }
        }

        for position in 0..<5 { try await insert(position) } // 5MB — under budget
        XCTAssertEqual(builds.value, 5)

        // LRU touch: re-request position 0 (the oldest) → becomes newest.
        _ = try await cache.plane(for: key(0), byteCount: megabyte)  { [metal, builds] in
            builds.value += 1
            return PipeCacheTests.tinyTexture(metal)
        }
        XCTAssertEqual(builds.value, 5, "the touch must be a HIT — make never called")

        for position in 5..<9 { try await insert(position) } // → 9MB > 8MB → evict to ≤ 5.33MB
        XCTAssertEqual(builds.value, 9, "the 4 new keys each built once")

        let total = await cache.totalBytes
        XCTAssertLessThanOrEqual(total, 8 * megabyte, "totalBytes ≤ budget after eviction")

        // Recently-touched position 0 survives; stale position 1 is gone.
        let statsBefore = await cache.stats
        _ = try await cache.plane(for: key(0), byteCount: megabyte)  { [metal, builds] in
            builds.value += 1
            return PipeCacheTests.tinyTexture(metal)
        }
        let statsAfter = await cache.stats
        XCTAssertEqual(statsAfter.hits - statsBefore.hits, 1, "touched plane survived eviction")
        XCTAssertEqual(builds.value, 9, "surviving plane was NOT rebuilt")

        _ = try await cache.plane(for: key(1), byteCount: megabyte)  { [metal, builds] in
            builds.value += 1
            return PipeCacheTests.tinyTexture(metal)
        }
        XCTAssertEqual(builds.value, 10, "oldest untouched plane was evicted first (LRU, not key order)")
    }

    func testHitPathSkipsMakeAndCountsExactlyOnce() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let imageID = UUID()
        let roi = ROI(x: 0, y: 0, width: 1, height: 1, scale: 1.0)
        let key = PipeCacheKey(
            imageID: imageID, pipeType: .preview, position: 7,
            upstreamHash: 42, roi: roi
        )
        let builds = IntBox()

        _ = try await cache.plane(for: key, byteCount: 16)  { [metal, builds] in
            builds.value += 1
            return PipeCacheTests.tinyTexture(metal)
        }
        _ = try await cache.plane(for: key, byteCount: 16)  { [metal, builds] in
            builds.value += 1
            return PipeCacheTests.tinyTexture(metal)
        }

        XCTAssertEqual(builds.value, 1, "hit path must NOT invoke make; miss path calls it exactly once")
        let stats = await cache.stats
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.misses, 1)
        let total = await cache.totalBytes
        XCTAssertEqual(total, 16, "byte accounting is incremental, not walked")
    }

    // ── 5. decodeParamsHash: a re-decode invalidates EVERYTHING ──

    func testDecodeParamsChangeInvalidatesAll() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let counter = CallCounter()
        let imageID = UUID()
        let (instances, _, _) = await makeChain(counter)
        let image1 = makeImage(width: 32, height: 32, blackLevel: 0.0)
        let image2 = makeImage(width: 32, height: 32, blackLevel: 0.25) // different rawTech → different decode hash

        let stats1 = try await run(image1, instances, imageID, .preview, cache, metal)
        XCTAssertEqual(stats1.hits, 0)
        XCTAssertEqual(stats1.misses, 5)

        // Same chain, same params, different decodeParamsHash → ALL miss
        // (the §1.3 gotcha: a Phase 3 WB change must not serve stale planes).
        let stats2 = try await run(image2, instances, imageID, .preview, cache, metal)
        XCTAssertEqual(stats2.hits, 0)
        XCTAssertEqual(stats2.misses, 5)
    }

    // ── 6. Hash-chain composition (PipeHash) ──

    func testPipeHashChainComposition() {
        let seed: UInt64 = 0xdeadbeefc0ffee
        // Unsorted input — upstream() sorts by position before folding.
        let entries: [(position: Int, hash: UInt64)] = [
            (2, 33), (0, 11), (1, 22)
        ]

        func fold(_ acc: UInt64, _ value: UInt64) -> UInt64 {
            var v = value
            return withUnsafeBytes(of: &v) { StableHash.combine(acc, $0) }
        }

        // upTo 3 = everything: fold ascending 11, 22, 33.
        let all = PipeHash.upstream(seed: seed, entries, upTo: 3)
        let manualAll = fold(fold(fold(seed, 11), 22), 33)
        XCTAssertEqual(all, manualAll, "unsorted input folds in ascending position order")

        // upTo 2 excludes position 2.
        let belowTwo = PipeHash.upstream(seed: seed, entries, upTo: 2)
        XCTAssertEqual(belowTwo, fold(fold(seed, 11), 22))

        // upTo 1 excludes positions 1, 2.
        XCTAssertEqual(PipeHash.upstream(seed: seed, entries, upTo: 1), fold(seed, 11))

        // Empty prefix = the seed unchanged (the position-0 decode seed).
        XCTAssertEqual(PipeHash.upstream(seed: seed, [], upTo: 5), seed)
    }

    // ── 7. invalidate(imageID:) sweep (02-03's load-entry anchor) ──

    func testInvalidateImageIDSweepsOnlyThatImage() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let roi = ROI(x: 0, y: 0, width: 1, height: 1, scale: 1.0)

        func insert(_ imageID: UUID, position: Int) async throws {
            _ = try await cache.plane(
                for: PipeCacheKey(
                    imageID: imageID, pipeType: .preview, position: position,
                    upstreamHash: UInt64(position), roi: roi
                ),
                byteCount: 1024
            ) { [metal] in PipeCacheTests.tinyTexture(metal) }
        }

        let victim = UUID()
        let survivor = UUID()
        try await insert(victim, position: 0)
        try await insert(victim, position: 1)
        try await insert(survivor, position: 0)
        var total = await cache.totalBytes
        XCTAssertEqual(total, 3 * 1024)

        await cache.invalidate(imageID: victim)
        total = await cache.totalBytes
        XCTAssertEqual(total, 1024, "only the victim image's lines are swept")
    }

    // ── 8. ROI axis identity (04-01-T1 regression net, pre-negotiation) ──

    /// ROI 轴恒等（现码全绿）：同 params、不同入口 longEdge → 不同键
    /// （scale 进 roi）；同键二次 run 命中。T3 协商后仍须绿（恒等默认下
    /// 行为逐字节不变）：不同 scale 的 roi 字段天然分离缓存行。
    func testSameParamsDifferentEntryScaleMiss() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let counter = CallCounter()
        let image = makeImage(width: 128, height: 96)
        let imageID = UUID()
        let (instances, _, _) = await makeChain(counter)

        func runAt(_ longEdge: Int?) async throws -> RenderPipeline.PipeRunStats {
            let result = try await RenderPipeline.process(
                image: image, instances: instances, imageID: imageID,
                resolution: .preview, cache: cache, metal: metal, longEdge: longEdge
            )
            return result.1
        }

        let stats64 = try await runAt(64)
        XCTAssertEqual(stats64.hits, 0)
        XCTAssertEqual(stats64.misses, 5, "input + 4 outputs at the 64px entry scale")
        let bytes64 = await cache.totalBytes
        let stats64Again = try await runAt(64)
        XCTAssertEqual(stats64Again.hits, 1)
        XCTAssertEqual(stats64Again.misses, 0, "same key reruns must hit")
        let bytesAfterHit = await cache.totalBytes
        XCTAssertEqual(bytesAfterHit, bytes64, "hit builds nothing")

        let stats32 = try await runAt(32)
        XCTAssertEqual(stats32.hits, 0, "different entry scale = different roi = different keys")
        XCTAssertEqual(stats32.misses, 5)
        let bytesAfter32 = await cache.totalBytes
        XCTAssertGreaterThan(bytesAfter32, bytes64, "both scale groups retained")

        let stats64Back = try await runAt(64)
        XCTAssertEqual(stats64Back.hits, 1, "the 64px key group survived the 32px run")
        XCTAssertEqual(stats64Back.misses, 0)
    }
}
