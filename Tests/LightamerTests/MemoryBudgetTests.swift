@testable import Lightamer
@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// Session memory budget enforcement (Plan 02-06-05/07; D-C1/D-C2, spike-b
/// 4.3-5.4 GB cross-decode accumulation evidence — the header citation the
/// plan requires lives at `PipeCoordinator`'s load-entry trigger).
///
/// `enforceBudget(now:keeping:)` is the PURE policy executor (research Open
/// Question #7): every test here injects a tiny threshold + byte budget, so
/// CI never allocates gigabytes. The production 3 GB constant is exercised
/// only as the default parameter.
///
/// Locked policy (checkpoint 02-06-01 lock #6), tiers in eviction order:
/// other-image THUMBNAIL/EXPORT → other-image FULL → other-image PREVIEW
/// (except `previousImageID`) → current-image non-PREVIEW; current-image
/// PREVIEW planes are never touched. LRU-oldest-first within a tier; stops
/// at the hysteresis floor (`min(evictTarget, budget × 2/3)`).
final class MemoryBudgetTests: XCTestCase {

    /// 1×1 float32 texture (the byteCount drives accounting, not the size).
    private func tinyTexture(_ metal: MetalContext) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: 1, height: 1,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return metal.device.makeTexture(descriptor: d)!
    }

    private static func makeDescriptor() -> MTLTextureDescriptor {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: 1, height: 1,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return d
    }

    private func insert(
        _ cache: PipeCache, metal: MetalContext,
        imageID: UUID, _ resolution: PipeResolution, position: Int = 1,
        bytes: Int, upstream: UInt64 = 1
    ) async throws {
        let key = PipeCacheKey(
            imageID: imageID, pipeType: resolution, position: position,
            upstreamHash: upstream,
            roi: ROI(width: 1, height: 1, scale: 1)
        )
        _ = try await cache.plane(for: key, byteCount: bytes) { [metal] in
            metal.device.makeTexture(descriptor: Self.makeDescriptor())!
        }
    }

    /// Probe survival: a hit means the plane survived the sweep.
    private func survives(
        _ cache: PipeCache, metal: MetalContext,
        imageID: UUID, _ resolution: PipeResolution, position: Int = 1,
        bytes: Int, upstream: UInt64 = 1
    ) async throws -> Bool {
        let before = await cache.stats
        let key = PipeCacheKey(
            imageID: imageID, pipeType: resolution, position: position,
            upstreamHash: upstream,
            roi: ROI(width: 1, height: 1, scale: 1)
        )
        _ = try await cache.plane(for: key, byteCount: bytes) { [metal] in
            metal.device.makeTexture(descriptor: Self.makeDescriptor())!
        }
        let after = await cache.stats
        return after.hits > before.hits
    }

    // ── Plan 05-06: nlmeans FULL Δfootprint gate (tiling 承重) ──────────

    /// nlmeans 启用的 FULL 渲染（强制分块 budget 32MB → 2048×1536@80B/px
    /// ≈ 252MB > 32MB → 多 tile）：Δfootprint < 3GB（D-C1 门；halo 记账 +
    /// 80 B/px 摊销的实跑上界）。grid>1 断言 = TilingPlan 同参纯函数
    /// （驱动用同一函数）。防空转：footprint delta 断言 + grid 断言。
    func testNLMeansFullFootprintBudget() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: NLMeansKernel.metalBundle)

        let width = 2048, height = 1536
        var data = Data(capacity: width * height * 16)
        for y in 0..<height {
            for x in 0..<width {
                let v = Float(exp2(-6.0 + 5.0 * Double(x) / Double(width - 1)))
                for _ in 0..<3 {
                    var le = v.bitPattern.littleEndian
                    data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
                }
                var one = Float(1.0).bitPattern.littleEndian
                data.append(contentsOf: withUnsafeBytes(of: &one) { Data($0) })
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let image = DecodedImage(
            ciImage: CIImage(cgImage: cg), rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil, decoderVersionUsed: .v8)

        // grid 记账：与 tile 驱动同参（80 B/px, halo 9）→ grid >1。
        let tiles = TilingPlan.tiles(
            forWidth: width, height: height, maxTileBytes: 32 << 20,
            bytesPerPixel: 80, overlap: 9)
        XCTAssertGreaterThan(tiles.count, 1, "分块真的发生（grid \(tiles.count) >1）")

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: NLMeansModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<NLMeansModule>)
        box.setParams(NLMeansModule.Params(strength: 120))

        let before = mach_footprint()
        _ = try await RenderPipeline.process(
            image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal,
            longEdge: nil, maxTileWorkingBytes: 32 << 20)
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        let delta = mach_footprint() - before
        print(String(format: "MEMORY nlmeans FULL tiled footprint delta: %.0f MB", Double(delta) / 1048576))
        XCTAssertLessThan(Double(delta), 3.0 * 1024 * 1024 * 1024, "D-C1 FULL budget")
    }

    // ── 1. The keep/evict matrix (one row per locked tier) ──────────────

    func testEnforceBudgetKeepEvictMatrix() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // Budget 1200 → floor = min(2 GB, 1200 × 2/3) = 800. Total exactly
        // 1200 (the insert-time LRU never fires at ≤ budget); the sweep
        // entry at 1199 evicts the 400 oldest tier-1..3 bytes and STOPS at
        // the floor — deep enough to prove tiers 1-3 + the keeps, without
        // tier 4 (covered by the dedicated scenario below).
        let cache = PipeCache(byteBudget: 1200)
        let current = UUID()
        let previous = UUID()
        let other = UUID()

        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 400)
        try await insert(cache, metal: metal, imageID: current, .thumbnail, bytes: 100)
        try await insert(cache, metal: metal, imageID: current, .full, bytes: 100)
        try await insert(cache, metal: metal, imageID: previous, .preview, bytes: 100)
        try await insert(cache, metal: metal, imageID: previous, .thumbnail, bytes: 100)
        try await insert(cache, metal: metal, imageID: previous, .full, bytes: 100)
        try await insert(cache, metal: metal, imageID: other, .preview, bytes: 100)
        try await insert(cache, metal: metal, imageID: other, .thumbnail, bytes: 100)
        try await insert(cache, metal: metal, imageID: other, .full, bytes: 100)
        let total = await cache.totalBytes
        XCTAssertEqual(total, 1200)

        let freed = await cache.enforceBudget(
            now: 1199,
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: previous)
        )
        XCTAssertEqual(freed.planesEvicted, 4, "tier 1×2 + tier 2 + tier 3")
        XCTAssertEqual(freed.bytesFreed, 400)

        // SURVIVORS (the locked keep set): current PREVIEW + previous
        // PREVIEW — everything else falls in tiers 1-4.
        // (survives() is async — XCTest autoclosures are not; hoist first.)
        let totalAfterSweep = await cache.totalBytes
        XCTAssertEqual(totalAfterSweep, 800, "1200 − the four tier-1/2 planes = the floor")

        let curPreview = try await survives(cache, metal: metal, imageID: current, .preview, bytes: 400)
        let prevPreview = try await survives(cache, metal: metal, imageID: previous, .preview, bytes: 100)
        let otherPreview = try await survives(cache, metal: metal, imageID: other, .preview, bytes: 100)
        let otherThumb = try await survives(cache, metal: metal, imageID: other, .thumbnail, bytes: 100)
        let otherFull = try await survives(cache, metal: metal, imageID: other, .full, bytes: 100)
        let prevThumb = try await survives(cache, metal: metal, imageID: previous, .thumbnail, bytes: 100)
        let prevFull = try await survives(cache, metal: metal, imageID: previous, .full, bytes: 100)
        let curThumb = try await survives(cache, metal: metal, imageID: current, .thumbnail, bytes: 100)
        let curFull = try await survives(cache, metal: metal, imageID: current, .full, bytes: 100)
        let totalAfter = await cache.totalBytes

        XCTAssertTrue(curPreview, "current-image PREVIEW planes are never evicted")
        XCTAssertTrue(prevPreview, "the previous image's PREVIEW plane survives (D-C1 keep)")
        XCTAssertTrue(otherPreview,
                      "the floor stopped the sweep BEFORE tier 3 (scenario 3c covers tier 3)")
        XCTAssertFalse(otherThumb, "other images' THUMBNAIL planes evict (tier 1)")
        XCTAssertFalse(otherFull, "other images' FULL planes evict (tier 2)")
        XCTAssertFalse(prevThumb, "the previous image's THUMBNAIL is NOT protected (tier 1)")
        XCTAssertFalse(prevFull, "the previous image's FULL is NOT protected (tier 2)")
        XCTAssertTrue(curThumb, "the sweep stopped at the floor BEFORE tier 3/4")
        XCTAssertTrue(curFull, "the floor protected every deeper tier in this scenario")
    }

    // ── 2. Tier ORDER within one sweep (LRU-oldest first per tier) ─────

    func testEnforceBudgetEvictionOrderWithinTiers() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // Floor = min(2 GB, 300 × 2/3) = 200; total exactly 300 (no
        // insert-time eviction), trigger 299: the sweep evicts exactly ONE
        // 100-byte plane — the tier-1 LRU-OLDEST one.
        let cache = PipeCache(byteBudget: 300)
        let current = UUID()
        let otherA = UUID()
        let otherB = UUID()

        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 100)
        // Tier 1 candidates, oldest FIRST (insertion order = lastHit order).
        try await insert(cache, metal: metal, imageID: otherA, .thumbnail, bytes: 100)
        try await insert(cache, metal: metal, imageID: otherB, .thumbnail, bytes: 100)

        let freed = await cache.enforceBudget(
            now: 299,
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: nil)
        )
        XCTAssertEqual(freed.planesEvicted, 1, "evict to the floor, no further")
        XCTAssertEqual(freed.bytesFreed, 100)
        let otherBThumb = try await survives(cache, metal: metal, imageID: otherB, .thumbnail, bytes: 100)
        let curPreview2 = try await survives(cache, metal: metal, imageID: current, .preview, bytes: 100)
        let otherAThumb = try await survives(cache, metal: metal, imageID: otherA, .thumbnail, bytes: 100)
        XCTAssertTrue(otherBThumb, "the OLDEST tier-1 plane (otherA) evicts first")
        XCTAssertTrue(curPreview2, "current PREVIEW untouched")
        XCTAssertFalse(otherAThumb, "oldest-first: otherA's thumbnail went first")
    }

    // ── 3. Tier 4: the current image's inactive resolutions ────────────

    func testEnforceBudgetEvictsCurrentInactiveResolutions() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // No other-image planes at all: budget 1000 → floor 666; total
        // 1000, trigger 999 → the sweep must take the tier-4 planes
        // (thumbnail, then full) and stop only when the PREVIEW remains.
        let cache = PipeCache(byteBudget: 1000)
        let current = UUID()
        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 400)
        try await insert(cache, metal: metal, imageID: current, .thumbnail, bytes: 300)
        try await insert(cache, metal: metal, imageID: current, .full, bytes: 300)
        let totalBefore = await cache.totalBytes
        XCTAssertEqual(totalBefore, 1000)

        let freed = await cache.enforceBudget(
            now: 999,
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: nil)
        )
        XCTAssertEqual(freed.planesEvicted, 2)
        XCTAssertEqual(freed.bytesFreed, 600)
        let curPreview = try await survives(cache, metal: metal, imageID: current, .preview, bytes: 400)
        let curThumb = try await survives(cache, metal: metal, imageID: current, .thumbnail, bytes: 300)
        let curFull = try await survives(cache, metal: metal, imageID: current, .full, bytes: 300)
        XCTAssertTrue(curPreview, "current PREVIEW survives the tier-4 sweep")
        XCTAssertFalse(curThumb, "current THUMBNAIL is an inactive resolution (tier 4)")
        XCTAssertFalse(curFull, "current FULL is an inactive resolution (tier 4)")
    }

    // ── 3c. Tier 3: other images' PREVIEW except the previous image's ──

    func testEnforceBudgetEvictsOtherImagePreviewsButKeepsPrevious() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // Only PREVIEW planes: budget 600 → floor 400; total 600, trigger
        // 599 → the sweep must take OTHER images' previews (tier 3) while
        // the previous image's PREVIEW survives (the D-C1 keep).
        let cache = PipeCache(byteBudget: 600)
        let current = UUID()
        let previous = UUID()
        let other = UUID()
        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 400)
        try await insert(cache, metal: metal, imageID: previous, .preview, bytes: 100)
        try await insert(cache, metal: metal, imageID: other, .preview, bytes: 100)

        let freed = await cache.enforceBudget(
            now: 599,
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: previous)
        )
        XCTAssertEqual(freed.planesEvicted, 1)
        XCTAssertEqual(freed.bytesFreed, 100)

        let curPreview = try await survives(cache, metal: metal, imageID: current, .preview, bytes: 400)
        let prevPreview = try await survives(cache, metal: metal, imageID: previous, .preview, bytes: 100)
        let otherPreview = try await survives(cache, metal: metal, imageID: other, .preview, bytes: 100)
        XCTAssertTrue(curPreview, "current PREVIEW untouched")
        XCTAssertTrue(prevPreview, "previous PREVIEW kept (D-C1)")
        XCTAssertFalse(otherPreview, "other images' PREVIEW planes evict (tier 3)")
    }

    // ── 3b. No-op under threshold ───────────────────────────────────────

    func testEnforceBudgetNoOpUnderThreshold() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        let cache = PipeCache(byteBudget: 300)
        let current = UUID()
        try await insert(cache, metal: metal, imageID: current, .preview, bytes: 50)

        let freed = await cache.enforceBudget(
            now: PipeCache.defaultBudget, // 3 GB trigger, 50 bytes cached
            keeping: PipeCache.KeepingPolicy(currentImageID: current, previousImageID: nil)
        )
        XCTAssertEqual(freed.bytesFreed, 0)
        XCTAssertEqual(freed.planesEvicted, 0)
        let total = await cache.totalBytes
        XCTAssertEqual(total, 50, "under threshold the sweep is a no-op")
    }

    // ── 4. Load-loop scenario (the D-C1/C2 regression harness) ──────────

    func testSequentialLoadLoopStaysUnderBudget() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // Budget 1000 → floor 666. Per load: preview 150 + thumbnail 90 +
        // full 90 = 330 ≤ (budget − floor) = 334, so the INSERT-time LRU
        // never fires and the ENFORCE sweep does all the work (the real
        // coordinator shape). Six sequential loads; the enforce threshold
        // (900) fires from the second load on, evicting the previous
        // loads' planes (LRU-oldest) down to the floor.
        let cache = PipeCache(byteBudget: 1000)
        var previous: UUID?
        var evictedOnce = false
        var peakBytes = 0

        for _ in 0..<6 {
            let current = UUID()
            try await insert(cache, metal: metal, imageID: current, .preview, bytes: 150)
            try await insert(cache, metal: metal, imageID: current, .thumbnail, bytes: 90)
            try await insert(cache, metal: metal, imageID: current, .full, bytes: 90)

            let freed = await cache.enforceBudget(
                now: 900,
                keeping: PipeCache.KeepingPolicy(
                    currentImageID: current, previousImageID: previous
                )
            )
            if freed.planesEvicted > 0 { evictedOnce = true }

            let total = await cache.totalBytes
            XCTAssertLessThanOrEqual(total, 666, "each sweep lands at or under the floor")
            peakBytes = max(peakBytes, total)
            previous = current
        }
        XCTAssertTrue(evictedOnce, "at least one load-entry sweep must have evicted")
        XCTAssertLessThanOrEqual(peakBytes, 1000, "the budget itself is never crossed")
    }

    // ── 5. CI clear smoke (D-C1 layer 2) ────────────────────────────────

    func testClearCICachesCallableWithoutCorruption() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        // The clear itself: callable with no state to corrupt.
        await metal.clearCICaches()
        // Smoke: the render path still works right after the clear (the
        // lazily created pool is reusable, not invalidated by the clear).
        let gradient = CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = DecodedImage(
            ciImage: gradient, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
        let texture = try await metal.renderToTexture(image.ciImage)
        XCTAssertEqual(texture.width, 16)
        XCTAssertEqual(texture.height, 16)
        await metal.clearCICaches() // idempotent
    }
    // ── 6. ROI negotiation accounting (04-01-T5, D-C1/C2 前置) ──────────

    /// File-local crop probe (dt `crop.c:517-531` forward / `:576-592`
    /// backward, minus the Phase-11 export aligner; params parked on the
    /// module — modifyROI hooks only receive `piece`).
    private final class ROICropProbe: IOPModule {
        struct Params: Codable, Hashable {
            var cx: Float
            var cy: Float
            var cw: Float
            var ch: Float
        }
        static var opName: String { "crop_roi_probe" }
        static var iopOrder: Float { 24.5 }
        static var flags: IOPFlags { [] }
        static var defaultColorspace: IOPColorspace { .RGB }
        private var rect = Params(cx: 0.25, cy: 0.25, cw: 0.75, ch: 0.75)
        func reloadDefaults(image: DecodedImage) async -> Params { rect }
        func commitParams(_ params: Params, into piece: inout IOPiece) {
            rect = params
            piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        }
        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
            roi = input
            roi.x = max(0, Int(Float(input.width) * rect.cx))
            roi.y = max(0, Int(Float(input.height) * rect.cy))
            roi.width = max(4, Int(Float(input.width) * (rect.cw - rect.cx)))
            roi.height = max(4, Int(Float(input.height) * (rect.ch - rect.cy)))
        }
        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
            input = roi
            let iw = Double(piece.dscIn.width) * Double(roi.scale)
            let ih = Double(piece.dscIn.height) * Double(roi.scale)
            input.x += Int(iw * Double(rect.cx))
            input.y += Int(ih * Double(rect.cy))
            input.x = min(max(input.x, 0), Int(iw.rounded(.down)))
            input.y = min(max(input.y, 0), Int(ih.rounded(.down)))
            input.width = min(input.width, max(1, Int(iw.rounded(.down)) - input.x))
            input.height = min(input.height, max(1, Int(ih.rounded(.down)) - input.y))
        }
        func process(
            input: any MTLTexture, output: any MTLTexture,
            roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext
        ) async throws {
            guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
                  let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw AppError.decodeFailed("ROICropProbe blit: no command buffer")
            }
            blit.copy(
                from: input, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: roiOut.x - roiIn.x, y: roiOut.y - roiIn.y, z: 0),
                sourceSize: MTLSize(width: roiOut.width, height: roiOut.height, depth: 1),
                to: output, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding() // L008
            commandBuffer.commit()
        }
    }

    /// File-local halo probe (identity forward, halo-pixel backward
    /// expansion; center-sample process).
    private final class ROIHaloProbe: IOPModule {
        struct Params: Codable, Hashable {
            var halo: Int
        }
        static var opName: String { "sharpen_roi_probe" }
        static var iopOrder: Float { 35.0 }
        static var flags: IOPFlags { [] }
        static var defaultColorspace: IOPColorspace { .RGB }
        private var haloValue = 3
        func reloadDefaults(image: DecodedImage) async -> Params { Params(halo: haloValue) }
        func commitParams(_ params: Params, into piece: inout IOPiece) {
            haloValue = params.halo
            piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        }
        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
            roi = input
        }
        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
            input = roi
            input.x -= haloValue
            input.y -= haloValue
            input.width += 2 * haloValue
            input.height += 2 * haloValue
        }
        func process(
            input: any MTLTexture, output: any MTLTexture,
            roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext
        ) async throws {
            guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
                  let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw AppError.decodeFailed("ROIHaloProbe blit: no command buffer")
            }
            blit.copy(
                from: input, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(
                    x: roiOut.x - roiIn.x + haloValue,
                    y: roiOut.y - roiIn.y + haloValue, z: 0),
                sourceSize: MTLSize(width: roiOut.width, height: roiOut.height, depth: 1),
                to: output, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding() // L008
            commandBuffer.commit()
        }
    }

    /// Crop 50% 后记账下降：裁切窗口 run 的缓存总字节 ≈ 全幅 run 的 1/4
    ///（输入平面同样窗口化 — 端到端子域渲染）。
    func testCropHalvesMemoryAccounting() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)

        func runWithCrop(cx: Float, cy: Float, cw: Float, ch: Float) async throws -> Int {
            let crop = ModuleBox(module: ROICropProbe(), multiPriority: 0, multiName: "crop")
            crop.setParams(ROICropProbe.Params(cx: cx, cy: cy, cw: cw, ch: ch))
            let cache = PipeCache()
            _ = try await RenderPipeline.process(
                image: image, instances: [crop], imageID: UUID(),
                resolution: .preview, cache: cache, metal: metal, longEdge: nil)
            return await cache.totalBytes
        }

        let fullBytes = try await runWithCrop(cx: 0, cy: 0, cw: 1, ch: 1)
        let cropBytes = try await runWithCrop(cx: 0.25, cy: 0.25, cw: 0.75, ch: 0.75)
        XCTAssertLessThan(cropBytes, fullBytes, "crop window must account fewer bytes than full frame")
        XCTAssertEqual(cropBytes * 4, fullBytes, "50% crop ≈ 1/4 bytes (window planes vs full planes)")
    }

    /// Halo 外扩类请求的上游平面 < 全图：roiHint 子窗口 + halo 后向扩展
    /// 的输入平面记账 == 扩展窗口（30×30 ≪ 128×128 全图）。
    func testHaloExpansionStaysBelowFullFrame() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
        let image = DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
        let haloBox = ModuleBox(module: ROIHaloProbe(), multiPriority: 0, multiName: "halo")
        haloBox.setParams(ROIHaloProbe.Params(halo: 3))
        let cache = PipeCache()
        _ = try await RenderPipeline.process(
            image: image, instances: [haloBox], imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal, longEdge: nil,
            roiHint: ROI(x: 40, y: 40, width: 24, height: 24, scale: 1.0))
        let total = await cache.totalBytes
        let fullFrame = 128 * 128 * WorkingSpace.bytesPerPixel
        XCTAssertLessThan(total, fullFrame, "expanded-window accounting must stay below one full frame")
        XCTAssertEqual(
            total,
            (30 * 30 + 24 * 24) * WorkingSpace.bytesPerPixel,
            "input (30×30 expanded) + halo-out (24×24 window)")
    }
    private func mach_footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    // MARK: - Layer dimension (Plan 06-01 T7)

    /// Spatially-varying synthetic image (L020 ③).
    private func makeLayerImage(width: Int = 48, height: Int = 32) -> DecodedImage {
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
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    private func makePopulatedRegistry() async -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    private func gainLayerForBudget(_ gain: Float, name: String) -> AdjustmentLayer {
        AdjustmentLayer(
            name: name, opacity: 1.0,
            chain: [ModuleInstance(
                module: TestGainModule.self,
                params: TestGainModule.Params(gain: gain))])
    }

    /// N=5 layer composite (PREVIEW): the cache footprint is BOUNDED and
    /// LINEAR — exactly base(2) + per-layer(2) + terminal(2) planes; a warm
    /// re-composite grows it by ZERO bytes (the incremental ladder's floor).
    func testCompositeLayeredPreviewFootprintBounded() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let registry = await makePopulatedRegistry()
        let image = makeLayerImage()
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        var stack = LayerStack(baseLayer: BackgroundLayer())
        for index in 0..<5 {
            stack.addAdjustment(gainLayerForBudget(1.0 + 0.1 * Float(index), name: "L\(index)"))
        }

        let imageID = UUID()
        let composite = { (stack: LayerStack) async throws -> LayerCompositeResult in
            try await LayerCompositeDriver.composite(
                image: image, imageID: imageID, baseInstances: base,
                layerStack: stack, registry: registry, resolution: .preview,
                cache: cache, metal: metal, longEdge: nil, roiHint: nil,
                policy: .preview)
        }
        _ = try await composite(stack)
        let planeBytes = 48 * 32 * WorkingSpace.bytesPerPixel
        // base input + colorin + 5×(chain + prefix) + colorout = 13 float32
        // planes + the gamma display tail (bgra8, 4 B/px).
        let total = await cache.totalBytes
        XCTAssertEqual(total, 13 * planeBytes + 48 * 32 * 4,
                       "5-layer PREVIEW footprint = 13 float32 planes + 1 display tail")

        // Warm re-composite: ZERO additional bytes (everything hits).
        _ = try await composite(stack)
        let totalAfterWarm = await cache.totalBytes
        XCTAssertEqual(totalAfterWarm, total, "warm composite adds no footprint")
    }

    /// FULL windowed composite (D-06-CONTEXT-8实证): with a 96×64 image and
    /// a 64×40 `roiHint`, EVERY cached plane is window-sized — the whole
    /// cache stays BELOW one full-frame float32 plane (98304 B). The cold
    /// layer's chain output is dropped after the blend (policy), the hot
    /// layer's is retained.
    func testCompositeFullWindowedPlaneSizes() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let registry = await makePopulatedRegistry()
        let image = makeLayerImage(width: 96, height: 64)
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let cold = gainLayerForBudget(1.4, name: "cold")
        let hot = gainLayerForBudget(2.2, name: "hot")
        stack.addAdjustment(cold)
        stack.addAdjustment(hot)

        let hint = ROI(x: 8, y: 6, width: 64, height: 40, scale: 1.0)
        let result = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: stack, registry: registry, resolution: .full,
            cache: cache, metal: metal, longEdge: nil, roiHint: hint,
            policy: .fullColdLayer, hotLayerID: hot.id)

        // The output plane is the WINDOW, not the full frame.
        XCTAssertEqual(result.window.width, 64)
        XCTAssertEqual(result.output.width, 64, "FULL output plane == window (O(视窗))")
        XCTAssertEqual(result.output.height, 40)

        // Footprint ledger (window planes, float32 64×40 = 40960 B):
        // base input + colorin + cold prefix + hot prefix + HOT chain
        // output (retained; the COLD one was dropped by the policy) =
        // 5 float32 planes + the gamma display tail (bgra8, 4 B/px).
        // The UNGATED alternative (full-frame planes) would be 98304 B per
        // plane — the exact ledger proves O(视窗), not O(全图).
        let total = await cache.totalBytes
        let windowFloat = 64 * 40 * WorkingSpace.bytesPerPixel
        XCTAssertGreaterThan(total, 0, "防空转 guard")
        XCTAssertEqual(total, 5 * windowFloat + 64 * 40 * 4,
                       "exact windowed ledger: no cold chain plane retained")
    }
}


// MARK: - Plan 09-03 T8: the culling pane ledger (2×PREVIEW budget face)

@MainActor
extension MemoryBudgetTests {

    /// The culling panes' SELF-OWNED planes never enter PipeCache. The
    /// RESIDENT footprint is the pane ledger = the gamma tail's bgra8Unorm
    /// display plane (1480×987×4 B ≈ 5.8 MB/plane — TWO panes ≈ 12 MB).
    /// The D-09-CONTEXT-6 "~23 MB/plane" figure describes the TRANSIENT
    /// float32 working plane INSIDE the run (the throwaway per-run cache
    /// holds it only while the pipeline executes; it dies with the run) —
    /// so the honest steady-state budget is ~12 MB resident + ~46 MB
    /// transient at cap 2, and the 4-pane extension re-check is
    /// ~24 MB resident + ~92 MB transient.
    func testCullingDualPaneLedgerStaysOnTheBudgetFace() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)

        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cullingbudget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func makeLoadedPane(_ rel: String) async throws -> CullingPaneModel {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(rel))
            let pane = CullingPaneModel(
                relPath: rel, decoder: RAWDecoder(), metal: metal,
                decodeLeg: { _ in
                    DecodedImage(
                        ciImage: CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6))
                            .cropped(to: CGRect(x: 0, y: 0, width: 3000, height: 2000)),
                        rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
                        segmentationSkyMatte: nil, decoderVersionUsed: .v8
                    )
                },
                sessionRoot: root
            )
            await pane.load()
            return pane
        }

        let paneA = try await makeLoadedPane("A.ARW")
        let paneB = try await makeLoadedPane("B.ARW")
        XCTAssertEqual(paneA.state, .ready)
        XCTAssertEqual(paneB.state, .ready)
        // The RESIDENT 1480-rung display plane: 1480×987×4 B ≈ 5.8 MB
        // (bgra8Unorm — the gamma tail's output). The float32 ~23 MB/plane
        // from RESEARCH §5.4 is the TRANSIENT working plane inside the run
        // (throwaway cache) — see the ledger doc above.
        for pane in [paneA, paneB] {
            XCTAssertGreaterThan(pane.planeBytes, 4_000_000, "≥ 4 MB/plane resident (bgra8 1480)")
            XCTAssertLessThan(pane.planeBytes, 8_000_000, "≤ 8 MB/plane resident (bgra8 1480)")
        }
        let dual = paneA.planeBytes + paneB.planeBytes
        XCTAssertLessThan(dual, 16_000_000, "the DUAL-pane resident ledger stays ~12 MB (cap 2)")

        // The release leg zeroes BOTH ledgers (no PipeCache involvement —
        // the panes own their planes).
        paneA.release()
        paneB.release()
        XCTAssertEqual(paneA.planeBytes, 0)
        XCTAssertEqual(paneB.planeBytes, 0)
    }
}
