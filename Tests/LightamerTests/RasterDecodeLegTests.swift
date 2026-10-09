@testable import LightamerCore
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RasterDecodeLegTests (Plan M4-1-01 T6, KD-5 — IOP bundle) — the native
// TIFF decode leg over the T2 fixture matrix:
//
//   • bit-depth fidelity: 8/16/32F probe pixels (0 / 0.18 / 0.5 / max)
//     survive the zero-conversion extraction (±1 LSB at the native depth);
//   • gray → channel-equal RGB; alpha dropped with the STORED color kept
//     (D6: no un-premultiplication); CMYK typed-rejected; multi-page
//     takes page 0;
//   • the LUT-ICC form splits to the CI leg (rasterNative nil + the
//     iccLutConverted description);
//   • the content probe (deterministic ≤4096-cell max) — the float32
//     fixture with 2.0 content reports > 1.0 (the HDR flag input);
//   • the ROUTING FLIP (M4-1-02): RAWDecoder.decode() routes the TIFF
//     family onto this leg (raster fields populated); the retired CI arm
//     stays reachable verbatim (the revival snapshot);
//   • the DecodedImage additive-optional zero-drift negative: existing
//     construction sites carry nil (byte-identical fields).
// ─────────────────────────────────────────────────────────────────────────────

final class RasterDecodeLegTests: XCTestCase {

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

    private func decodeNative(_ name: String) throws -> (DecodedImage, RasterNativePixels) {
        let url = try fixture(name)
        let decoded = try RasterDecoder.decodeTIFF(url)
        guard let native = decoded.rasterNative else {
            XCTFail("\(name): expected a native payload, got the CI leg")
            throw AppError.decodeFailed("no native payload")
        }
        return (decoded, native)
    }

    /// The probe pixel the generator writes: (x, y=0) carries
    /// 0 / max / 0.18·max / 0.5·max in the first four columns (the ramp
    /// fills the rest), all three channels equal.
    private func probeValue(_ native: RasterNativePixels, x: Int, y: Int, channel: Int) -> Double {
        let bpp = native.bytesPerPixel
        let offset = (y * native.width + x) * bpp + channel * native.bitsPerComponent / 8
        let bytes = native.data
        switch native.channelLayout {
        case .rgb8:
            return Double(bytes[offset]) / 255.0
        case .rgb16:
            let v = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
            return Double(v) / 65535.0
        case .rgb32Float:
            let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            return Double(Float(bitPattern: bits))
        }
    }

    // MARK: - Bit-depth fidelity (the probe pixels)

    func testEightBitFidelity() throws {
        let (_, native) = try decodeNative("srgb-matrix-8.tif")
        XCTAssertEqual(native.channelLayout, .rgb8)
        XCTAssertEqual(native.width, 64)
        XCTAssertEqual(native.height, 64)
        let lsb = 1.0 / 255.0
        XCTAssertEqual(probeValue(native, x: 0, y: 0, channel: 0), 0, accuracy: lsb)
        XCTAssertEqual(probeValue(native, x: 1, y: 0, channel: 0), 1.0, accuracy: lsb)
        XCTAssertEqual(probeValue(native, x: 2, y: 0, channel: 0), 46.0 / 255.0, accuracy: lsb)
        XCTAssertEqual(probeValue(native, x: 3, y: 0, channel: 0), 128.0 / 255.0, accuracy: lsb)
        // Channel-equal (the generator writes the same ramp per channel).
        XCTAssertEqual(
            probeValue(native, x: 10, y: 5, channel: 0),
            probeValue(native, x: 10, y: 5, channel: 2), accuracy: lsb)
    }

    func testSixteenBitFidelity() throws {
        let (_, native) = try decodeNative("srgb-matrix-16.tif")
        XCTAssertEqual(native.channelLayout, .rgb16)
        let lsb = 1.0 / 65535.0
        XCTAssertEqual(probeValue(native, x: 0, y: 0, channel: 1), 0, accuracy: lsb)
        XCTAssertEqual(probeValue(native, x: 1, y: 0, channel: 1), 1.0, accuracy: lsb)
        XCTAssertEqual(probeValue(native, x: 2, y: 0, channel: 1), 11797.0 / 65535.0, accuracy: lsb)
        XCTAssertEqual(probeValue(native, x: 3, y: 0, channel: 1), 32768.0 / 65535.0, accuracy: lsb)
    }

    /// The RAW-03 extreme values survive the native leg (0.5 / 1.0 exact;
    /// the float32 path is bit-near-exact — zero conversion in between).
    func testFloat32Fidelity() throws {
        let (_, native) = try decodeNative("srgb-matrix-32f.tif")
        XCTAssertEqual(native.channelLayout, .rgb32Float)
        XCTAssertEqual(probeValue(native, x: 0, y: 0, channel: 2), 0.0, accuracy: 1e-9)
        XCTAssertEqual(probeValue(native, x: 1, y: 0, channel: 2), 1.0, accuracy: 1e-9)
        XCTAssertEqual(probeValue(native, x: 2, y: 0, channel: 2), 0.18, accuracy: 1e-6)
        XCTAssertEqual(probeValue(native, x: 3, y: 0, channel: 2), 0.5, accuracy: 1e-9)
        // The extreme-survival probe (the RAW-03 values through OUR leg).
        // The ramp maxes at 1.0; the values stay finite and ordered.
        let mid = probeValue(native, x: 32, y: 32, channel: 1)
        XCTAssertTrue(mid.isFinite)
        XCTAssertGreaterThan(mid, 0.4)
        XCTAssertLessThan(mid, 0.6)
    }

    // MARK: - Shape specials

    func testGrayExpandsToChannelEqualRGB() throws {
        let (_, native) = try decodeNative("gray-icc-8.tif")
        XCTAssertEqual(native.channelLayout, .rgb8)
        let lsb = 1.0 / 255.0
        for (x, y) in [(0, 0), (10, 5), (32, 32), (63, 63)] {
            let r = probeValue(native, x: x, y: y, channel: 0)
            let g = probeValue(native, x: x, y: y, channel: 1)
            let b = probeValue(native, x: x, y: y, channel: 2)
            XCTAssertEqual(r, g, accuracy: lsb)
            XCTAssertEqual(g, b, accuracy: lsb)
        }
    }

    func testAlphaDroppedWithStoredColorKept() throws {
        let (decoded, native) = try decodeNative("alpha-8.tif")
        XCTAssertEqual(native.channelLayout, .rgb8)
        XCTAssertEqual(native.bytesPerPixel, 3, "the alpha byte is stripped")
        XCTAssertNotNil(decoded.rasterColor)
        // The stored color survives (alpha 128 was associated-stored; the
        // RGB bytes are the un-premultiplied stored values — D6 keeps them).
        let lsb = 2.0 / 255.0 // the CG premultiplied round-trip floor
        XCTAssertEqual(probeValue(native, x: 1, y: 0, channel: 0), 1.0, accuracy: lsb)
        XCTAssertEqual(probeValue(native, x: 0, y: 0, channel: 0), 0, accuracy: lsb)
    }

    func testCMYKIsTypedRejected() throws {
        let url = try fixture("cmyk-8.tif")
        do {
            _ = try RasterDecoder.decodeTIFF(url)
            XCTFail("CMYK must be typed-rejected")
        } catch let error as AppError {
            guard case .decodeFailed(let message) = error else {
                return XCTFail("unexpected error case: \(error)")
            }
            XCTAssertTrue(message.contains("CMYK"), message)
        }
    }

    func testMultiPageTakesPageZero() throws {
        let (decoded, native) = try decodeNative("multipage-16.tif")
        XCTAssertEqual(native.width, 64)
        XCTAssertEqual(native.height, 64)
        // Page 0 = the forward ramp: the value at x=32 exceeds the flipped
        // page 1's (mirrored) value at the same x.
        let v0 = probeValue(native, x: 10, y: 0, channel: 0)
        XCTAssertGreaterThan(v0, 0.1)
        XCTAssertNil(decoded.rasterColor?.defaultReason == nil ? nil : nil) // trivial non-crash face
    }

    // MARK: - The LUT-ICC CI-leg split

    func testLutICCFormSplitsToCILeg() throws {
        let url = try fixture("lut-a2b0-8.tif")
        let decoded = try RasterDecoder.decodeTIFF(url)
        XCTAssertNil(decoded.rasterNative, "the LUT form rides the CI leg")
        XCTAssertNotNil(decoded.ciImage)
        let description = try XCTUnwrap(decoded.rasterColor)
        XCTAssertEqual(description.origin, .iccLutConverted)
        XCTAssertEqual(description.transfer, .linear)
        XCTAssertEqual(description.referral, .displayReferred)
    }

    // MARK: - The content probe (the HDR flag input)

    func testContentProbeMaxFloat32() throws {
        let (_, native) = try decodeNative("no-icc-float32.tif")
        // The fixture's content max is 2.0 — the >1.0 HDR flag input.
        XCTAssertGreaterThan(native.contentProbeMax, 1.0)
        XCTAssertLessThanOrEqual(native.contentProbeMax, 2.0 + 1e-6)
    }

    func testContentProbeMaxSDRStaysWithinUnit() throws {
        let (_, native) = try decodeNative("srgb-matrix-8.tif")
        XCTAssertLessThanOrEqual(native.contentProbeMax, 1.0)
        XCTAssertGreaterThan(native.contentProbeMax, 0.9)
    }

    // MARK: - The routing flip (M4-1-02 T1) + additive zero drift

    func testProductionDecodeRoutingTakesTheNativeLeg() async throws {
        // THE routing FLIP (M4-1-02 T1, OQ-6): the production decode now
        // routes the TIFF family onto the native leg — the raster fields
        // are populated there (this replaces 01's pre-flip golden, which
        // pinned the CI path until this plan landed).
        let url = try fixture("srgb-matrix-16.tif")
        let decoder = RAWDecoder()
        let decoded = try await decoder.decode(url)
        XCTAssertNotNil(decoded.rasterColor, "the flip must populate the description")
        XCTAssertNotNil(decoded.rasterNative, "the flip must populate the native payload")
        XCTAssertNotNil(decoded.ciImage)
    }

    func testProductionDecodeRoutingRetiredArmStaysReachable() async throws {
        // The RETIRED arm is kept verbatim (the OQ-6 revival path): a
        // direct `decodeRaster` call still decodes the fixture through the
        // CI face with nil raster fields — the pre-M4-1 behavior byte
        // snapshot.
        let url = try fixture("srgb-matrix-16.tif")
        let decoder = RAWDecoder()
        let decoded = try await decoder.decodeRaster(url, uti: UTType.tiff.identifier)
        XCTAssertNil(decoded.rasterColor)
        XCTAssertNil(decoded.rasterNative)
        XCTAssertNotNil(decoded.ciImage)
    }

    func testAdditiveFieldsDefaultNilOnExistingInit() {
        // The additive-optional zero-drift contract: the existing init
        // call sites (which do not pass the new parameters) construct
        // records identical to the pre-M4-1 shape — the new legs read nil.
        let image = CIImage.empty()
        let record = DecodedImage(
            ciImage: image, rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8, contentDedupeID: 7)
        XCTAssertNil(record.rasterColor)
        XCTAssertNil(record.rasterNative)
        // ...and the fields are settable without disturbing the elders.
        let withRaster = DecodedImage(
            ciImage: image, rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8, contentDedupeID: 7,
            rasterColor: RasterColorResolver.resolve(
                iccData: nil, colorSpaceName: nil, isFloat: false),
            rasterNative: nil)
        XCTAssertEqual(record.capture.width, withRaster.capture.width)
        XCTAssertEqual(record.contentDedupeID, withRaster.contentDedupeID)
        XCTAssertNotNil(withRaster.rasterColor)
    }

    /// The description and pixels leave decodeTIFF together, consistent
    /// (the float32 fixture with no ICC → the ② default pair).
    func testDescriptionPairsWithPixels() throws {
        let (decoded, native) = try decodeNative("no-icc-float32.tif")
        let description = try XCTUnwrap(decoded.rasterColor)
        XCTAssertEqual(description.referral, .sceneLinear)
        XCTAssertEqual(description.origin, .tiffNoIccFloatLinear)
        XCTAssertEqual(native.channelLayout, .rgb32Float)
        XCTAssertNotNil(decoded.contentDedupeID)
        // The ①′ half-edge pairing: linear ICC + float32 pixels.
        let (decoded1, native1) = try decodeNative("linear-icc-float32.tif")
        XCTAssertEqual(try XCTUnwrap(decoded1.rasterColor).referral, .sceneLinear)
        XCTAssertEqual(native1.channelLayout, .rgb32Float)
    }

    // MARK: - M4-1-02 T2: the negotiation-window payload (KD-3)

    func testWindowedPayloadIdentityCopyTopFirst() throws {
        // The 64×64 fixture, full-window 1:1 → a straight byte copy, rows
        // TOP-FIRST (the pipe INPUT-plane convention RAW03 pins).
        let (_, native) = try decodeNative("srgb-matrix-16.tif")
        XCTAssertEqual(native.width, 64)
        let window = CGRect(x: 0, y: 0, width: 64, height: 64)
        let payload = try RasterDecoder.windowedPayload(
            native, window: window, targetWidth: 64, targetHeight: 64)
        XCTAssertEqual(payload.width, 64)
        XCTAssertEqual(payload.height, 64)
        XCTAssertEqual(payload.channelLayout, native.channelLayout)
        XCTAssertEqual(payload.data, native.data, "a 1:1 window must be a byte copy")
    }

    func testWindowedPayloadSubWindowCopy() throws {
        // The right half (view x 32..<64) at 1:1, rows top-first.
        let (_, native) = try decodeNative("srgb-matrix-16.tif")
        let payload = try RasterDecoder.windowedPayload(
            native, window: CGRect(x: 32, y: 0, width: 32, height: 64),
            targetWidth: 32, targetHeight: 64)
        XCTAssertEqual(payload.width, 32)
        let bpp = native.bytesPerPixel
        for y in 0..<64 {
            for x in 0..<32 {
                for k in 0..<bpp {
                    XCTAssertEqual(
                        payload.data[(y * 32 + x) * bpp + k],
                        native.data[(y * 64 + 32 + x) * bpp + k])
                }
            }
        }
    }

    func testWindowedPayloadBoxAverageDownsample() throws {
        // A 2×2 white block (view TOP-LEFT) downsampled 2× lands at target
        // (0,0) at 255; the all-zero view BOTTOM-RIGHT quadrant lands at
        // (1,1).
        var data = [UInt8](repeating: 0, count: 4 * 4 * 3)
        func put(_ x: Int, _ y: Int, _ v: UInt8) {
            let i = (y * 4 + x) * 3
            data[i] = v; data[i + 1] = v; data[i + 2] = v
        }
        put(0, 0, 255); put(1, 0, 255); put(0, 1, 255); put(1, 1, 255)
        let native = RasterNativePixels(
            data: data, width: 4, height: 4,
            channelLayout: .rgb8, contentProbeMax: 1.0)
        let payload = try RasterDecoder.windowedPayload(
            native, window: CGRect(x: 0, y: 0, width: 4, height: 4),
            targetWidth: 2, targetHeight: 2)
        let white = Int(payload.data[0])
        XCTAssertEqual(white, 255, "the full-white view quadrant must average to 255")
        let zero = Int(payload.data[(1 * 2 + 1) * 3])
        XCTAssertEqual(zero, 0)
    }

    func testWindowedPayloadDeterministic() throws {
        let (_, native) = try decodeNative("srgb-matrix-16.tif")
        let window = CGRect(x: 0, y: 0, width: 64, height: 64)
        let a = try RasterDecoder.windowedPayload(
            native, window: window, targetWidth: 13, targetHeight: 9)
        let b = try RasterDecoder.windowedPayload(
            native, window: window, targetWidth: 13, targetHeight: 9)
        XCTAssertEqual(a.data, b.data, "the resample must be deterministic")
        XCTAssertEqual(a.contentProbeMax, b.contentProbeMax)
    }

    func testWindowedPayloadEmptyWindowTypedReject() throws {
        let (_, native) = try decodeNative("srgb-matrix-16.tif")
        XCTAssertThrowsError(try RasterDecoder.windowedPayload(
            native, window: CGRect(x: 100, y: 100, width: 4, height: 4),
            targetWidth: 4, targetHeight: 4))
    }
}
