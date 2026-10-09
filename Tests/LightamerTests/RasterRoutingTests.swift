@testable import LightamerCore
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RasterRoutingTests (Plan M4-1-02 T1, KD-1 — IOP bundle) — the decode()
// UTI-split FLIP machine anchor:
//
//   • tiff → the native leg (raster fields populated through PRODUCTION
//     decode — the flipped routing);
//   • lut-icc tiff → the CI arm OF the raster leg (rasterNative nil +
//     iccLutConverted);
//   • jpeg/png/heic → the retained CI decodeRaster arm, ZERO regression
//     (raster fields nil) — the per-UTI arm shapes the plan pins as the
//     future-routing-regression anchor;
//   • the TIFF family predicate forms;
//   • the CMYK typed reject surfacing through production decode;
//   • the E1 product re-entry: a BandStreamer float32 product (linear-ICC
//     tagged) re-enters through decode() as sceneLinear — the matrix
//     branch the IOP/IOPParity bit baselines ride (self-consistency).
// ─────────────────────────────────────────────────────────────────────────────

final class RasterRoutingTests: XCTestCase {

    private static let fixtureDirectory: URL = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/TiffRaster", isDirectory: true)
    }()

    private func fixture(_ name: String) throws -> URL {
        let url = Self.fixtureDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("fixture missing: \(name) — run Scripts/gen-tiff-fixtures.py")
        }
        return url
    }

    /// A small opaque 8-bit sRGB CGImage (the synthetic raster source).
    private func makeCGImage() -> CGImage {
        let width = 8, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = UInt8((i * 37) % 256)
            pixels[i * 4 + 1] = UInt8((i * 59) % 256)
            pixels[i * 4 + 2] = UInt8((i * 11) % 256)
            pixels[i * 4 + 3] = 255
        }
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// Encode the synthetic image into a temp file of `uti`.
    private func encodeRaster(_ uti: UTType) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routing-\(UUID().uuidString).\(uti.preferredFilenameExtension ?? "bin")")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, uti.identifier as CFString, 1, nil) else {
            throw XCTSkip("encoder unavailable: \(uti.identifier)")
        }
        CGImageDestinationAddImage(destination, makeCGImage(), nil)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("encode failed: \(uti.identifier)")
        }
        return url
    }

    // MARK: - The flipped routing

    func testTiffRoutesToTheNativeLeg() async throws {
        let url = try fixture("srgb-matrix-8.tif")
        let decoded = try await RAWDecoder().decode(url)
        XCTAssertNotNil(decoded.rasterColor, "tiff must ride the native leg")
        XCTAssertNotNil(decoded.rasterNative, "tiff must ride the native leg")
    }

    func testLutIccTiffRoutesToTheRasterCIArm() async throws {
        // The ONLY TIFF form that stays on a CI face: the LUT-profile arm
        // of the raster leg — rasterNative nil + iccLutConverted.
        let url = try fixture("lut-a2b0-8.tif")
        let decoded = try await RAWDecoder().decode(url)
        XCTAssertNotNil(decoded.rasterColor)
        XCTAssertNil(decoded.rasterNative, "the LUT-ICC form carries no native payload")
        XCTAssertEqual(decoded.rasterColor?.origin, .iccLutConverted)
        XCTAssertNotNil(decoded.ciImage)
    }

    // MARK: - The retained CI arm (zero regression)

    func testJpegRoutesToTheCIArm() async throws {
        let url = try encodeRaster(.jpeg)
        let decoded = try await RAWDecoder().decode(url)
        XCTAssertNil(decoded.rasterColor, "jpeg must stay on the CI arm")
        XCTAssertNil(decoded.rasterNative, "jpeg must stay on the CI arm")
        XCTAssertNotNil(decoded.ciImage)
    }

    func testPngRoutesToTheCIArm() async throws {
        let url = try encodeRaster(.png)
        let decoded = try await RAWDecoder().decode(url)
        XCTAssertNil(decoded.rasterColor, "png must stay on the CI arm")
        XCTAssertNil(decoded.rasterNative, "png must stay on the CI arm")
        XCTAssertNotNil(decoded.ciImage)
    }

    func testHeicRoutesToTheCIArm() async throws {
        guard UTType.heic.conforms(to: .heic),
              (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(
                UTType.heic.identifier) == true
        else { throw XCTSkip("HEIC encode unavailable on this host") }
        let url = try encodeRaster(.heic)
        let decoded = try await RAWDecoder().decode(url)
        XCTAssertNil(decoded.rasterColor, "heic must stay on the CI arm")
        XCTAssertNil(decoded.rasterNative, "heic must stay on the CI arm")
        XCTAssertNotNil(decoded.ciImage)
    }

    // MARK: - The TIFF family predicate

    func testTiffFamilyPredicateForms() {
        XCTAssertTrue(RAWDecoder.isTIFFUTI(UTType.tiff.identifier))
        // The extension-spelled UTI (the .tif tag resolution).
        let ext = UTType(tag: "tif", tagClass: .filenameExtension, conformingTo: nil)
        XCTAssertTrue(ext.map { RAWDecoder.isTIFFUTI($0.identifier) } ?? false)
        // Non-TIFF raster UTIs stay off the family.
        XCTAssertFalse(RAWDecoder.isTIFFUTI(UTType.jpeg.identifier))
        XCTAssertFalse(RAWDecoder.isTIFFUTI(UTType.png.identifier))
        XCTAssertFalse(RAWDecoder.isTIFFUTI("public.data"))
    }

    // MARK: - Typed rejects through the production entry

    func testCmykTiffTypedRejectSurfacesThroughDecode() async throws {
        let url = try fixture("cmyk-8.tif")
        do {
            _ = try await RAWDecoder().decode(url)
            XCTFail("CMYK must be typed-rejected")
        } catch let error as AppError {
            guard case .decodeFailed = error else {
                return XCTFail("unexpected error case: \(error)")
            }
        }
    }

    func testMultipageTiffTakesPageZeroThroughDecode() async throws {
        let url = try fixture("multipage-16.tif")
        let decoded = try await RAWDecoder().decode(url)
        XCTAssertEqual(decoded.rasterNative?.width, 64)
        XCTAssertEqual(decoded.rasterNative?.height, 64)
    }

    // MARK: - T2: the folded dedupe key + the pipe dispatch

    func testFoldedDedupeKeyZeroDriftWithoutDescription() {
        // nil descriptionHash = the pre-M4-1 two-input fold BYTE-IDENTICAL.
        let folded = PixelPipe.foldedInputPlaneDedupeKey(
            content: 0xAABB, descriptionHash: nil, decodeParams: 0x1122)
        var expected = UInt64(0xAABB)
        var params = UInt64(0x1122)
        withUnsafeBytes(of: &params) { expected = StableHash.combine(expected, $0) }
        XCTAssertEqual(folded, expected)
    }

    func testFoldedDedupeKeyFlipsOnDescriptionFingerprint() {
        let base = PixelPipe.foldedInputPlaneDedupeKey(
            content: 0xAABB, descriptionHash: nil, decodeParams: 0x1122)
        let withA = PixelPipe.foldedInputPlaneDedupeKey(
            content: 0xAABB, descriptionHash: 1, decodeParams: 0x1122)
        let withB = PixelPipe.foldedInputPlaneDedupeKey(
            content: 0xAABB, descriptionHash: 2, decodeParams: 0x1122)
        XCTAssertNotEqual(base, withA, "the fingerprint fold must flip the key")
        XCTAssertNotEqual(withA, withB, "a different fingerprint is a different key")
    }

    /// The dispatch machine anchor: a u8 sRGB TIFF through the PIPE rides
    /// the raster leg — the mid-gray plane value is the INVERSE-DRT scene
    /// value, NOT the CI leg's sRGB linearization (~0.216 for code 128).
    func testPipeDispatchRidesTheRasterLeg() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        let url = try fixture("srgb-matrix-8.tif")
        let decoded = try await RAWDecoder().decode(url)
        let (plane, _) = try await RenderPipeline.process(
            image: decoded,
            instances: [],
            imageID: UUID(),
            resolution: .preview,
            cache: PipeCache(),
            metal: metal,
            longEdge: 64)
        XCTAssertEqual(plane.pixelFormat, WorkingSpace.pixelFormat)
        // The L014 fence before the readback.
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        var pixels = [Float](repeating: 0, count: plane.width * plane.height * 4)
        plane.getBytes(
            &pixels, bytesPerRow: plane.width * 16,
            from: MTLRegionMake2D(0, 0, plane.width, plane.height), mipmapLevel: 0)
        let center = pixels[((plane.height / 2) * plane.width + plane.width / 2) * 4]
        XCTAssertTrue(center.isFinite, "the raster-leg plane must be finite")
        XCTAssertGreaterThan(abs(center - 0.2159), 0.02,
            "code-128 through the raster leg must NOT read as the CI leg's sRGB "
                + "linearization (~0.216) — the dispatch rode the inverse-DRT leg")
        XCTAssertGreaterThan(center, 0.0, "the scene value must survive the leg")
    }

    // MARK: - E1: the product re-entry (the matrix branch)

    func testLinearICCFloat32ProductReentersSceneLinear() async throws {
        // The E1 self-consistency anchor: a BandStreamer product (float32,
        // linear-Rec2020 TAGGED) re-enters through decode() as sceneLinear
        // — the matrix branch (no inverse ODT) the stack/HDR products and
        // their IOPParity baselines ride.
        let width = 16, height = 16
        var plane = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            plane[i * 4] = Float(i % 255) / 255.0 * 2.0
            plane[i * 4 + 1] = plane[i * 4]
            plane[i * 4 + 2] = plane[i * 4]
            plane[i * 4 + 3] = 1
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routing-product-\(UUID().uuidString).tif")
        try BandStreamer.writeFloatTIFF(plane, width: width, height: height, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try await RAWDecoder().decode(url)
        let description = try XCTUnwrap(decoded.rasterColor)
        XCTAssertEqual(description.referral, .sceneLinear, "①′ must route the product")
        XCTAssertEqual(description.transfer, .linear)
        let native = try XCTUnwrap(decoded.rasterNative)
        XCTAssertEqual(native.channelLayout, .rgb32Float)
    }
}
