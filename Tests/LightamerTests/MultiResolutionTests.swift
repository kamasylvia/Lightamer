@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// FOUND-04 multi-resolution semantics (Plan 02-03-05): scale-at-entry
/// sizes the input plane to the requested long edge; PREVIEW and THUMBNAIL
/// NEVER share cache lines even at the same 360px size (Risk #8); THUMBNAIL
/// renders lazily (dirty lifecycle); FULL is scale-1.0 on-demand with the
/// no-intermediate-cache policy; EXPORT is a typed `.notImplemented` stub.
///
/// Synthetic CIImages only — the suite runs anywhere, no RAW dependency.
/// GPU-dependent tests guard per the VALIDATION "Metal compute requires a
/// GPU context" rule.
final class MultiResolutionTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    /// Synthetic flat-gray image (no RAW dependency).
    private func makeImage(width: Int, height: Int) -> DecodedImage {
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return DecodedImage(
            ciImage: ci,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    private func makeChain() async -> [any ModuleBoxing] {
        // Minimal enabled chain: one gain + one pass-through (iopOrder from
        // the modules; multiPriority disambiguates). Exercises the module
        // legs so per-resolution caching policy is actually observable.
        let gain = ModuleBox(module: TestGainModule(), multiPriority: 0, multiName: "g")
        let pass = ModuleBox(module: PassthroughModule(), multiPriority: 1, multiName: "p")
        await gain.setParams(TestGainModule.Params(gain: 1.0))
        await pass.setParams(PassthroughModule.Params())
        return [gain, pass]
    }

    // ── 1. Scale-at-entry: the input plane lands ON the target long edge ──

    func testScaledInputPlaneLongEdge() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        // 60MP-extent synthetic (the plan's acceptance wording) — the
        // scaled render must produce 2560px on the long edge, never a
        // 60MP plane.
        let image = makeImage(width: 9504, height: 6336)
        let texture = try await metal.renderToTexture(image.ciImage, longEdge: 2560)
        XCTAssertEqual(
            max(texture.width, texture.height), 2560,
            "long edge must be the requested target (±1px rounding)"
        )
        XCTAssertEqual(
            min(texture.width, texture.height), 1707,
            "aspect preserved (6336 × 2560/9504 ≈ 1706.7 → 1707)"
        )
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat, "FOUND-02 format")

        // Degenerate inputs type-throw, never crash.
        do {
            _ = try await metal.renderToTexture(image.ciImage, longEdge: 0)
            XCTFail("longEdge 0 must throw")
        } catch let error as AppError {
            guard case .decodeFailed = error else {
                return XCTFail("expected .decodeFailed, got \(error)")
            }
        }
    }

    // ── 2. PREVIEW/THUMBNAIL keys never collide (Risk #8) ────────────────

    func testPreviewAndThumbnailKeysDoNotCollide() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let instances = await makeChain()
        let image = makeImage(width: 4000, height: 3000)
        let imageID = UUID()

        func run(_ resolution: PipeResolution, longEdge: Int?) async throws
            -> RenderPipeline.PipeRunStats
        {
            try await RenderPipeline.process(
                image: image, instances: instances, imageID: imageID,
                resolution: resolution, cache: cache, metal: metal, longEdge: longEdge
            ).1
        }

        // PREVIEW at the ladder FLOOR (360 — the same pixel size a
        // THUMBNAIL produces) must NOT satisfy THUMBNAIL keys: pipeType
        // namespaces the cache (Darktable mipmap-vs-preview parity,
        // Risk #8). First run: input + 2 module planes, all miss.
        let previewStats = try await run(.preview, longEdge: 360)
        XCTAssertEqual(previewStats.hits, 0)
        XCTAssertEqual(previewStats.misses, 3, "input plane + gain + pass-through")

        let thumbnailStats = try await run(.thumbnail, longEdge: nil)
        XCTAssertEqual(thumbnailStats.hits, 0, "THUMBNAIL must MISS — the 360px PREVIEW lines are invisible to it")
        XCTAssertEqual(thumbnailStats.misses, 3, "THUMBNAIL renders its own full set")

        // Both sets now coexist (2 namespaces × 3 lines each).
        let planeBytes = 360 * 270 * WorkingSpace.bytesPerPixel // 360-long-edge plane of the 4000×3000 source
        let total = await cache.totalBytes
        XCTAssertEqual(total, 6 * planeBytes, "two distinct 360px line sets, byte-accounted")

        // And the PREVIEW set is still intact: a repeat run hits through.
        let previewAgain = try await run(.preview, longEdge: 360)
        XCTAssertEqual(previewAgain.hits, 1, "top PREVIEW line hit")
        XCTAssertEqual(previewAgain.misses, 0)
    }

    // ── 3. THUMBNAIL lazy lifecycle ──────────────────────────────────────

    func testThumbnailLazyLifecycle() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let instances = await makeChain()
        let image = makeImage(width: 4000, height: 3000)
        let pipe = PixelPipe(resolution: .thumbnail, cache: cache)
        pipe.imageID = UUID()

        // First fetch: a fresh pipe is DIRTY (first run counts) → renders.
        let stats1 = try await pipe.runIfDirty(
            image: image, instances: instances, metal: metal
        )
        XCTAssertNotNil(stats1, "first fetch must render")
        XCTAssertEqual(stats1?.stats.misses, 3)
        XCTAssertFalse(pipe.isDirty, "render disarms the dirty flag")
        XCTAssertLessThan(pipe.roi.scale, 1.0, "THUMBNAIL runs at roi.scale < 1.0 (scale-at-entry)")
        XCTAssertEqual(max(pipe.roi.width, pipe.roi.height), 360, "THUMBNAIL roi is the fixed 360px defaultLongEdge")

        // A clean fetch renders NOTHING (the lazy point of the lifecycle).
        let statsBefore = await cache.stats
        let planesBefore = pipe.planesRendered
        let stats2 = try await pipe.runIfDirty(
            image: image, instances: instances, metal: metal
        )
        XCTAssertNil(stats2, "clean pipe fetches nil — no render")
        let statsAfter = await cache.stats
        XCTAssertEqual(statsAfter.hits - statsBefore.hits, 0)
        XCTAssertEqual(statsAfter.misses - statsBefore.misses, 0)
        XCTAssertEqual(pipe.planesRendered, planesBefore, "stats unchanged — nothing rendered")

        // `paramsDidChange` marks dirty WITHOUT rendering (what the
        // coordinator does; 02-05 wires real history through it).
        pipe.isDirty = true
        let statsBetween = await cache.stats
        let statsMarked = await cache.stats
        XCTAssertEqual(
            statsMarked.misses - statsBetween.misses, 0,
            "marking dirty renders nothing"
        )

        // Next fetch renders exactly once more.
        let stats3 = try await pipe.runIfDirty(
            image: image, instances: instances, metal: metal
        )
        XCTAssertNotNil(stats3, "dirty pipe fetches render once")
        XCTAssertEqual(stats3?.stats.misses, 0, "second render at identical params is all cache HITS (lazy ≠ uncached)")
        XCTAssertFalse(pipe.isDirty)
    }

    // ── 4. FULL: scale 1.0, on-demand, no intermediate caching ───────────

    func testFullRunIsScaleOne() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let instances = await makeChain()
        let image = makeImage(width: 64, height: 48)
        let imageID = UUID()
        let pipe = PixelPipe(resolution: .full, cache: cache)
        pipe.imageID = imageID

        // runOnce: the on-demand FULL entry — scale 1.0, dims == extent.
        let (output, stats1) = try await pipe.runOnce(
            image: image, instances: instances, metal: metal
        )
        XCTAssertEqual(output.width, 64, "FULL output == input extent (scale 1.0)")
        XCTAssertEqual(output.height, 48)
        XCTAssertEqual(pipe.roi.scale, 1.0)
        XCTAssertEqual(stats1.misses, 2, "FULL caches ONLY input + final (02-02 lock #4 per-resolution)")
        XCTAssertEqual(stats1.planesRendered, 3, "all modules still execute")

        // The pipe holds no reference policy detail: runOnce's returned
        // plane is the caller's; a second identical run hits the final
        // line without rendering.
        let (output2, stats2) = try await pipe.runOnce(
            image: image, instances: instances, metal: metal
        )
        XCTAssertEqual(output2.width, 64)
        XCTAssertEqual(stats2.hits, 1)
        XCTAssertEqual(stats2.misses, 0, "identical FULL re-run = final-line hit, zero work")
    }

    // ── 5. EXPORT: typed placeholder, never a crash ──────────────────────

    func testExportThrowsTyped() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let instances = await makeChain()
        let image = makeImage(width: 32, height: 32)

        // Through the public RenderPipeline entry (what Phase 11 replaces).
        do {
            _ = try await RenderPipeline.process(
                image: image, instances: instances, imageID: UUID(),
                resolution: .export, cache: cache, metal: metal, longEdge: nil
            )
            XCTFail("EXPORT must throw until Phase 11")
        } catch let error as AppError {
            guard case let .notImplemented(phase) = error, phase == "Phase 11" else {
                return XCTFail("expected .notImplemented(\"Phase 11\"), got \(error)")
            }
        }

        // And through the internal pipe walk directly (@testable surface).
        let pipe = PixelPipe(resolution: .export, cache: cache)
        do {
            _ = try await pipe.run(
                image: image, instances: instances, metal: metal, longEdge: nil
            )
            XCTFail("EXPORT run must throw")
        } catch let error as AppError {
            guard case .notImplemented = error else {
                return XCTFail("expected .notImplemented, got \(error)")
            }
        }
        let total = await cache.totalBytes
        XCTAssertEqual(total, 0, "an EXPORT attempt caches nothing")
    }

    // ── 6. PREVIEW roi.scale is sub-unit at a ladder bucket ──────────────

    func testPreviewPipeRunsAtSubUnitScale() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let cache = PipeCache()
        let instances = await makeChain()
        let image = makeImage(width: 4000, height: 3000)
        let pipe = PixelPipe(resolution: .preview, cache: cache)
        pipe.imageID = UUID()

        let (output, _) = try await pipe.run(
            image: image, instances: instances, metal: metal, longEdge: 2560
        )
        XCTAssertLessThan(pipe.roi.scale, 1.0, "PREVIEW at a ladder bucket is scale-at-entry < 1.0")
        XCTAssertEqual(max(output.width, output.height), 2560, "final plane carries the bucket long edge")
        XCTAssertEqual(pipe.roi.scale, Float(0.64), "4000→2560 = exact 0.64 scale")
    }
}
