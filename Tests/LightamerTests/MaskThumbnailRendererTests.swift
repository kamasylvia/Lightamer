@testable import LightamerCore
@testable import LightamerIOP
import CoreGraphics
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MaskThumbnailRendererTests (Plan M2-7-2 T1, KD-1; AC1) — the GPU thumbnail
// pass over the UNCHANGED assembleUnmasked entry: the drawn / parametric /
// raster legs + the mixed combine + the cache contract (stableHash ⊕ bucket
// ⊕ dims keying, invalidation on edit, LRU bound) + the aspect-preserving
// window rule (checker M4) + the empty-payload nil degrade.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class MaskThumbnailRendererTests: XCTestCase {

    private var metal: MetalContext!
    private var maskDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        // The blendif/blur kernels live in the IOP metallib (the soft
        // dependency MaskCombiner documents).
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        maskDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("thumbrend-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: maskDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: maskDirectory)
        try await super.tearDown()
    }

    // MARK: harness

    /// The 2:1 identity mapper at thumbnail scale (the caller-side compose
    /// precedent for a no-geometry chain).
    private func mapper(width: Int = 112, height: Int = 56) -> GeometryPointMapper {
        let size = SIMD2<Double>(Double(width), Double(height))
        return GeometryPointMapper(frameSize: size, segments: [], outputSize: size)
    }

    private func render(
        _ spec: MaskSpec, cache: inout MaskThumbnailCache,
        width: Int = 112, height: Int = 56
    ) async throws -> CGImage? {
        try await MaskThumbnailRenderer.render(
            spec: spec, size: MaskThumbnailRenderer.thumbLongEdge,
            metal: metal, mapper: mapper(width: width, height: height),
            maskDirectory: maskDirectory, cache: &cache)
    }

    private func grayBytes(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else { return [] }
        return [UInt8](UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data)))
    }

    private func sample(_ image: CGImage, xNorm: Double, yNorm: Double) -> UInt8 {
        let bytes = grayBytes(image)
        let width = image.width, height = image.height
        let x = min(width - 1, max(0, Int(xNorm * Double(width))))
        let y = min(height - 1, max(0, Int(yNorm * Double(height))))
        return bytes[y * width + x]
    }

    private func ellipseSpec(radius: Float) -> MaskSpec {
        MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5), radiusX: radius, radiusY: radius,
                rotationDegrees: 0, border: 0)))
        ]))
    }

    // MARK: the window rule (checker M4)

    func testThumbnailWindowIsAspectPreserving() {
        XCTAssertEqual(
            MaskThumbnailRenderer.thumbnailSize(forLayerWindow: SIMD2(200, 100)),
            SIMD2(112, 56), "2:1 layer window → 2:1 thumbnail (never a square)")
        XCTAssertEqual(
            MaskThumbnailRenderer.thumbnailSize(forLayerWindow: SIMD2(100, 200)),
            SIMD2(56, 112), "1:2 portrait keeps its aspect")
        XCTAssertEqual(
            MaskThumbnailRenderer.thumbnailSize(forLayerWindow: SIMD2(48, 24)),
            SIMD2(48, 24), "a window below the bucket renders 1:1 (no upscale)")
        XCTAssertEqual(
            MaskThumbnailRenderer.thumbnailSize(forLayerWindow: SIMD2(1, 1)),
            SIMD2(2, 2), "the degenerate window floors at 2×2")
    }

    // MARK: the drawn leg

    func testDrawnEllipseThumbnailShowsTheSolidShape() async throws {
        var cache = MaskThumbnailCache()
        guard let image = try await render(ellipseSpec(radius: 0.25), cache: &cache)
        else { return XCTFail("drawn thumbnail must render") }
        XCTAssertEqual(image.width, 112)
        XCTAssertEqual(image.height, 56)
        XCTAssertGreaterThan(
            Int(sample(image, xNorm: 0.5, yNorm: 0.5)), 200, "the shape center is solid")
        XCTAssertLessThan(
            Int(sample(image, xNorm: 0.03, yNorm: 0.03)), 25, "the far corner is empty")
    }

    // MARK: the parametric leg (the ramp window visualization)

    func testParametricLumaCurveVisualizesOnTheRamp() async throws {
        var cache = MaskThumbnailCache()
        var spec = MaskSpec()
        spec.parametric = ParametricMask(
            domain: .luma,
            channels: [ParametricMask.ChannelEntry(
                channel: 0, curve: ParametricMask.ChannelCurve(points: [0, 0, 0.4, 0.6]))])
        guard let image = try await render(spec, cache: &cache)
        else { return XCTFail("parametric thumbnail must render") }
        // The ramp luma = x: the [0..0.4] plateau reads bright, the region
        // past the [0.4..0.6] ramp-down reads dark.
        XCTAssertGreaterThan(Int(sample(image, xNorm: 0.15, yNorm: 0.5)), 200)
        XCTAssertLessThan(Int(sample(image, xNorm: 0.85, yNorm: 0.5)), 25)
    }

    // MARK: the raster leg (+ the window resample)

    func testRasterRefThumbnailLoadsAndResamplesThePNG() async throws {
        let ref = try await Self.bakeRasterPng(
            directory: maskDirectory, metal: metal, fileName: "thumb-raster.png")
        XCTAssertEqual(RasterMaskStore.verify(ref: ref, directory: maskDirectory), nil)

        var cache = MaskThumbnailCache()
        var spec = MaskSpec()
        spec.raster = ref
        guard let image = try await render(spec, cache: &cache)
        else { return XCTFail("raster thumbnail must render") }
        XCTAssertGreaterThan(
            Int(sample(image, xNorm: 0.5, yNorm: 0.5)), 200,
            "the baked rectangle's center survives the window resample")
        XCTAssertLessThan(Int(sample(image, xNorm: 0.02, yNorm: 0.02)), 25)
    }

    /// The bake boundary (nonisolated STATIC — no `self` in the region):
    /// the texture's whole life stays in one isolation region, so the plane
    /// may cross into `bake` (the FollowEdgesTests non-MainActor shape).
    private nonisolated static func bakeRasterPng(
        directory: URL, metal: MetalContext, fileName: String
    ) async throws -> RasterMaskRef {
        let plane = try makeR32(32, 16, metal: metal) { x, y in
            (4..<12).contains(y) && (8..<24).contains(x) ? 1.0 : 0.0
        }
        return try await RasterMaskStore.bake(
            plane: plane, directory: directory, fileName: fileName,
            invert: false, metal: metal)
    }

    /// A non-async builder: the texture borrow region ENDS at the return,
    /// so the returned plane may cross the await into `bake` (region
    /// isolation — the FollowEdgesTests.makeRGBA precedent).
    private nonisolated static func makeR32(
        _ w: Int, _ h: Int, metal: MetalContext, fill: (Int, Int) -> Float
    ) throws -> any MTLTexture {
        var floats = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { floats[y * w + x] = fill(x, y) }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let plane = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        try floats.withUnsafeBytes {
            plane.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 4)
        }
        return plane
    }

    // MARK: the mixed combine (form ⊗ conditional)

    func testMixedPayloadIntersectsFormWithConditional() async throws {
        var cache = MaskThumbnailCache()
        var spec = ellipseSpec(radius: 0.25)
        spec.parametric = ParametricMask(
            domain: .luma,
            channels: [ParametricMask.ChannelEntry(
                channel: 0, curve: ParametricMask.ChannelCurve(points: [0, 0, 0.45, 0.55]))])
        guard let image = try await render(spec, cache: &cache)
        else { return XCTFail("mixed thumbnail must render") }
        // x=0.35: inside the ellipse AND on the luma plateau → bright.
        // x=0.65: inside the ellipse but past the ramp-down → dark.
        XCTAssertGreaterThan(Int(sample(image, xNorm: 0.35, yNorm: 0.5)), 200)
        XCTAssertLessThan(Int(sample(image, xNorm: 0.65, yNorm: 0.5)), 25)
    }

    // MARK: the cache contract (KD-1)

    func testCacheHitReturnsTheSameBitmap() async throws {
        var cache = MaskThumbnailCache()
        let spec = ellipseSpec(radius: 0.25) // ONE spec — the form UUID is part of the hash
        let firstImage = try await render(spec, cache: &cache)
        let secondImage = try await render(spec, cache: &cache)
        let first = try XCTUnwrap(firstImage)
        let second = try XCTUnwrap(secondImage)
        XCTAssertTrue(first === second, "the hit path hands back the cached bitmap")
        XCTAssertEqual(cache.count, 1, "one key, one entry")
    }

    func testEditingOneFieldFlipsTheKeyAndRerenders() async throws {
        var cache = MaskThumbnailCache()
        let beforeImage = try await render(ellipseSpec(radius: 0.2), cache: &cache)
        let afterImage = try await render(ellipseSpec(radius: 0.4), cache: &cache)
        XCTAssertEqual(cache.count, 2, "the edit produced a NEW key (old entry LRU-held)")
        let beforeBytes = grayBytes(try XCTUnwrap(beforeImage))
        let afterBytes = grayBytes(try XCTUnwrap(afterImage))
        XCTAssertNotEqual(beforeBytes, afterBytes, "the larger radius renders more ink")
    }

    func testEmptyPayloadReturnsNil() async throws {
        var cache = MaskThumbnailCache()
        let image = try await render(MaskSpec(), cache: &cache)
        XCTAssertNil(image, "no payload → the panel's placeholder degrade")
        XCTAssertEqual(cache.count, 0, "nil renders cache nothing")
    }

    func testLRUEvictionBoundHolds() {
        var cache = MaskThumbnailCache()
        cache.limit = 4
        func key(_ n: UInt64) -> MaskThumbnailCacheKey {
            MaskThumbnailCacheKey(specHash: n, sizeBucket: 1, width: 8, height: 8)
        }
        func image(_ v: UInt8) -> CGImage {
            var pixels = [UInt8](repeating: v, count: 8 * 8)
            let context = CGContext(
                data: &pixels, width: 8, height: 8, bitsPerComponent: 8,
                bytesPerRow: 8, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            return context.makeImage()!
        }
        for n: UInt64 in 1...6 { cache.insert(image(UInt8(n)), for: key(n)) }
        XCTAssertEqual(cache.count, 4, "the bound holds")
        XCTAssertNil(cache.image(for: key(1)), "the oldest entry evicted")
        XCTAssertNil(cache.image(for: key(2)), "the second-oldest evicted")
        XCTAssertNotNil(cache.image(for: key(3)))
        XCTAssertNotNil(cache.image(for: key(6)))
        // A touch refreshes recency: 3 survives the next eviction, 4 goes.
        _ = cache.image(for: key(3))
        cache.insert(image(9), for: key(7))
        XCTAssertNotNil(cache.image(for: key(3)), "the touched entry survives")
        XCTAssertNil(cache.image(for: key(4)), "the untouched tail evicted first")
    }
}
