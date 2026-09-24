@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// AIMaskGeometryTests (Plan 07-1 T3/T4) — the geometry pins:
/// - bilinear upsample weights (analytic values)
/// - row-0 = image-top alignment (no flip on the mask-buffer path)
/// - the VIEW→VISION Y-flip seam (AIMaskPoint / AIMaskRect vectors)
/// - the bake feather profile (a Gaussian step-edge transition) + the
///   featherRadius default's zero-behavior-change regression.
final class AIMaskGeometryTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lra-ai-geo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Bilinear weights

    /// [0, 1] (2×1) upsampled to 4×1 = [0, 0.25, 0.75, 1] — the analytic
    /// PIXEL-CENTER bilinear values (src = (dst + 0.5)·srcW/dstW − 0.5,
    /// the CoreImage/Vision resample convention; endpoint interpolation
    /// [0, 1/3, 2/3, 1] is a DIFFERENT kernel and must NOT appear).
    func testBilinearUpsampleWeights() {
        let plane = AIMaskPlane(width: 2, height: 1, floats: [0, 1])
        let out = AIMaskResample.bilinear(plane, toWidth: 4, toHeight: 1)
        XCTAssertEqual(out.width, 4)
        XCTAssertEqual(out.floats[0], 0, accuracy: 1e-6)
        XCTAssertEqual(out.floats[1], 0.25, accuracy: 1e-6)
        XCTAssertEqual(out.floats[2], 0.75, accuracy: 1e-6)
        XCTAssertEqual(out.floats[3], 1, accuracy: 1e-6)
        // Identity sizes pass through byte-identical.
        let same = AIMaskResample.bilinear(plane, toWidth: 2, toHeight: 1)
        XCTAssertEqual(same.floats, plane.floats)
    }

    /// Row 0 = IMAGE TOP on both sides: a top-half-ones mask stays
    /// top-half after a 2× upsample (a flipped kernel fails loudly).
    func testUpsampleAlignmentTopRowIsImageTop() {
        let w = 4, h = 4
        var floats = [Float](repeating: 0, count: w * h)
        for y in 0..<2 { for x in 0..<w { floats[y * w + x] = 1 } }
        let plane = AIMaskPlane(width: w, height: h, floats: floats)
        let out = AIMaskResample.bilinear(plane, toWidth: 8, toHeight: 8)
        // Top row fully lit, bottom row fully dark.
        XCTAssertEqual(out.floats[0], 1, accuracy: 1e-6, "row 0 (image top) must stay lit")
        XCTAssertEqual(
            out.floats[7 * 8], 0, accuracy: 1e-6, "last row (image bottom) must stay dark")
        // The 2× mid-band: pixel-center convention puts the edge blend at
        // rows 3 (0.75) and 4 (0.25) — symmetric about the half line.
        XCTAssertEqual(out.floats[3 * 8], 0.75, accuracy: 0.02)
        XCTAssertEqual(out.floats[4 * 8], 0.25, accuracy: 0.02)
        XCTAssertEqual(out.floats[2 * 8], 1, accuracy: 1e-6)
        XCTAssertEqual(out.floats[5 * 8], 0, accuracy: 1e-6)
    }

    /// `upsampleToDecodeFrame` only ever GROWS a smaller mask; equal or
    /// larger planes pass through untouched (layer A's full-res scaled
    /// mask and layer B's balanced/accurate full-res output skip the
    /// reshape — benchmark finding).
    func testUpsampleOnlyWhenSmaller() {
        let plane = AIMaskPlane(width: 512, height: 512, floats: .init(repeating: 0.5, count: 512 * 512))
        let same = AIMaskResample.upsampleToDecodeFrame(plane, decodeWidth: 512, decodeHeight: 512)
        XCTAssertEqual(same.floats, plane.floats, "equal size = identity")
        let bigger = AIMaskResample.upsampleToDecodeFrame(plane, decodeWidth: 256, decodeHeight: 256)
        XCTAssertEqual(bigger.floats, plane.floats, "mask larger than decode frame = identity")
        let grown = AIMaskResample.upsampleToDecodeFrame(
            AIMaskPlane(width: 256, height: 256, floats: .init(repeating: 1, count: 256 * 256)),
            decodeWidth: 512, decodeHeight: 512)
        XCTAssertEqual(grown.width, 512, "smaller mask must grow to the decode frame")
    }

    // MARK: - Y-flip seam (the permanent pin)

    /// `y_vision = 1 − y_view_norm` for points AND boxes (the single
    /// conversion seam in AIMaskTypes — every interactive coordinate MUST
    /// pass through it; 07-CONTEXT 継承定案).
    func testViewToVisionYFlipVectors() {
        // View top edge (y=0) = Vision y 1.0 (top of image at the MAX).
        let top = AIMaskPoint(x: 0.5, y: 0.0).visionPoint
        XCTAssertEqual(Double(top.y), 1.0, accuracy: 1e-6)
        XCTAssertEqual(Double(top.x), 0.5, accuracy: 1e-6)
        // View bottom edge = Vision 0.
        let bottom = AIMaskPoint(x: 0.25, y: 1.0).visionPoint
        XCTAssertEqual(Double(bottom.y), 0.0, accuracy: 1e-6)
        // Quarter lines.
        XCTAssertEqual(Double(AIMaskPoint(x: 0, y: 0.25).visionPoint.y), 0.75, accuracy: 1e-6)
        XCTAssertEqual(Double(AIMaskPoint(x: 0, y: 0.75).visionPoint.y), 0.25, accuracy: 1e-6)
        // Boxes: the view-space min-y corner becomes Vision's max-y corner.
        let box = AIMaskRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4).visionRect
        XCTAssertEqual(Double(box.origin.x), 0.1, accuracy: 1e-6)
        XCTAssertEqual(Double(box.origin.y), 0.4, accuracy: 1e-6,
                       "vision y = 1 − y_view − height")
        XCTAssertEqual(Double(box.width), 0.3, accuracy: 1e-6)
        XCTAssertEqual(Double(box.height), 0.4, accuracy: 1e-6)
        // The full-frame box is flip-invariant (sanity anchor).
        let full = AIMaskRect(x: 0, y: 0, width: 1, height: 1).visionRect
        XCTAssertEqual(Double(full.origin.y), 0.0, accuracy: 1e-6)
    }

    /// L014: sync fence + readback (waitUntilCompleted is unavailable
    /// from async contexts — the RasterMaskRoundTripTests helper shape).
    nonisolated private static func readMaskSync(
        _ t: any MTLTexture, metal: MetalContext
    ) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var out = [Float](repeating: 0, count: t.width * t.height)
        out.withUnsafeMutableBytes {
            t.getBytes(
                $0.baseAddress!, bytesPerRow: t.width * 4,
                from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        }
        return out
    }

    // MARK: - Bake feather

    /// A step edge (left half 1, right half 0) baked with featherRadius:
    /// the edge midpoint lands at ≈0.5 and the profile decays
    /// monotonically away from the edge (the Gaussian transition — the
    /// DrawnMaskRasterTests profile pattern).
    func testBakeFeatherProfileOnStepEdge() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 64, h = 64
        var floats = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w / 2 { floats[y * w + x] = 1 } }
        let plane = try AIMaskResample.texture(
            from: AIMaskPlane(width: w, height: h, floats: floats), metal: metal)
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let ref = try await RasterMaskStore.bake(
            plane: plane, directory: dir, fileName: "feather.png",
            invert: false, featherRadius: 8, metal: metal)
        // Read back through load (uint16-quantized floats).
        guard case let .plane(loaded) = try await RasterMaskStore.load(
            ref: ref, directory: dir, windowWidth: w, windowHeight: h, metal: metal)
        else { return XCTFail("feathered bake must load intact") }
        let got = Self.readMaskSync(loaded, metal: metal)
        let mid = got[32 * w + 32] // the edge midpoint row
        XCTAssertEqual(mid, 0.5, accuracy: 0.1, "edge midpoint must sit at ~0.5 (got \(mid))")
        var monotone = true
        var compared = 0
        let row = 32
        var prev = got[row * w + 8]
        for x in 9..<56 {
            let v = got[row * w + x]
            if v > prev + 1.0 / 65535.0 { monotone = false }
            prev = v
            compared += 1
        }
        XCTAssertTrue(monotone, "profile must be non-increasing left→right across the edge")
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
        XCTAssertGreaterThan(got[row * w + 8], 0.9, "far from the edge the mask stays ~1")
        XCTAssertLessThan(got[row * w + 55], 0.1, "far from the edge the mask stays ~0")
    }

    /// featherRadius DEFAULT (0) = the EXACT pre-07-1 behavior: the
    /// written PNG bytes are identical to an explicit 0 (zero regression).
    func testBakeDefaultFeatherZeroIsByteIdentical() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 37, h = 23
        var floats = [Float](repeating: 0, count: w * h)
        for i in 0..<floats.count { floats[i] = Float(i % 17) / 16.0 }
        let plane = try AIMaskResample.texture(
            from: AIMaskPlane(width: w, height: h, floats: floats), metal: metal)
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Default parameter (no feather argument at all).
        let refDefault = try await RasterMaskStore.bake(
            plane: plane, directory: dir, fileName: "default.png",
            invert: false, metal: metal)
        let refZero = try await RasterMaskStore.bake(
            plane: plane, directory: dir, fileName: "zero.png",
            invert: false, featherRadius: 0, metal: metal)
        let bytesDefault = try Data(contentsOf: dir.appendingPathComponent("default.png"))
        let bytesZero = try Data(contentsOf: dir.appendingPathComponent("zero.png"))
        XCTAssertEqual(bytesDefault, bytesZero,
                       "featherRadius default must be byte-identical to explicit 0")
        XCTAssertEqual(refDefault.maskHash, refZero.maskHash)
    }
}
