@testable import LightamerCore
import CoreGraphics
import Foundation
import ImageIO
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RasterIccSemanticsTests (Plan M4-1-01 T3, RESEARCH §4.2 — IOP bundle) —
// the ICC semantics golden over the T2 fixture matrix:
//
//   • per-fixture description assertions (referral/primaries/transfer/
//     peak/origin/defaultReason) through the REAL presentation chain:
//     TIFF IFD tag 34675 (RasterIccParser.tiffEmbeddedICCData) → the
//     resolver. The IFD route is the golden's backbone (host-probed
//     2026-10-09): ImageIO synthesizes colorspaces for untagged files and
//     REDUCES close-matching embedded profiles to system spaces, so the
//     cgImage.colorSpace face lies for exactly the fixtures this matrix
//     exists to pin;
//   • TRC host-Float64 double anchors — the public-standard values
//     hardcoded (IEC 61966-2-1 sRGB piecewise; the ITU BT.2100 PQ/HLG
//     formulas) — the Core twins the kernels re-state in T7;
//   • the usable-check negatives through fixtures (degenerate primaries →
//     the sRGB default + reason);
//   • platform-behavior pins: the no-ICC presentation (synthesized sRGB),
//     the float32 presentation (extendedLinearSRGB), multi-page count.
// ─────────────────────────────────────────────────────────────────────────────

final class RasterIccSemanticsTests: XCTestCase {

    // MARK: - Fixture access (the FilmProfileTests #filePath walk precedent)

    private static let fixtureDirectory: URL = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/LightamerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        return root.appendingPathComponent("Tests/Fixtures/TiffRaster", isDirectory: true)
    }()

    private func fixture(_ name: String) throws -> URL {
        let url = Self.fixtureDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("fixture missing: \(name) — run Scripts/gen-tiff-fixtures.py")
        }
        return url
    }

    /// The description a fixture yields through the production chain:
    /// IFD0 tag 34675 → RasterIccParser.parse → RasterColorResolver.resolve,
    /// with the float32 verdict from the CGImage bit depth.
    private func describe(_ name: String) throws -> RasterColorDescription {
        let url = try fixture(name)
        let isFloat = try Self.isFloatFixture(url)
        let icc = RasterIccParser.tiffEmbeddedICCData(at: url)
        return RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: isFloat)
    }

    private static func isFloatFixture(_ url: URL) throws -> Bool {
        guard let src = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            XCTFail("fixture failed to decode: \(url.lastPathComponent)")
            throw AppError.decodeFailed("fixture failed to decode: \(url.lastPathComponent)")
        }
        return img.bitsPerComponent == 32
    }

    private func assertPrimaries(
        _ d: RasterColorDescription, _ expected: SIMD8<Float>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for i in 0..<8 {
            XCTAssertEqual(
                d.primariesXY[i], expected[i], accuracy: 2e-3,
                "primaries[\(i)]", file: file, line: line)
        }
    }

    // MARK: - Per-fixture description golden (the matrix walk)

    func testSrgbMatrixFixturesAcrossBitDepths() throws {
        for name in ["srgb-matrix-8.tif", "srgb-matrix-16.tif", "srgb-matrix-32f.tif"] {
            let d = try describe(name)
            XCTAssertEqual(d.referral, .displayReferred, name)
            XCTAssertEqual(d.transfer, .gamma(563.0 / 256.0), name)
            XCTAssertEqual(d.origin, .iccMatrixShaper, name)
            assertPrimaries(d, RasterColorResolver.sRGBPrimaries)
            XCTAssertEqual(d.peakLuminanceNits, 100.0, name)
            XCTAssertNil(d.defaultReason, name)
            XCTAssertNotNil(d.profileHash, name)
        }
    }

    /// The 32F row carries the sRGB ICC (NOT linear) — display-referred, so
    /// the ①′ rule does NOT fire (only linear ICCs demote to scene-linear).
    func testSrgbFloat32StaysDisplayReferred() throws {
        let d = try describe("srgb-matrix-32f.tif")
        XCTAssertEqual(d.referral, .displayReferred)
        XCTAssertEqual(d.transfer, .gamma(563.0 / 256.0))
    }

    func testGamutMatrixFixtures() throws {
        let p3 = try describe("p3-matrix-16.tif")
        XCTAssertEqual(p3.transfer, .gamma(563.0 / 256.0))
        assertPrimaries(p3, RasterColorResolver.displayP3Primaries)

        let adobe = try describe("adobergb-matrix-16.tif")
        assertPrimaries(adobe, RasterColorResolver.adobeRGBPrimaries)

        let rec2020 = try describe("rec2020-matrix-16.tif")
        assertPrimaries(rec2020, RasterColorResolver.rec2020Primaries)

        // ProPhoto: D50 white, the AP1-out limiting branch's source.
        let pro = try describe("prophoto-matrix-16.tif")
        assertPrimaries(pro, RasterColorResolver.proPhotoPrimaries)
        XCTAssertEqual(Double(pro.primariesXY[6]), 0.3457, accuracy: 2e-3)
        XCTAssertEqual(Double(pro.primariesXY[7]), 0.3585, accuracy: 2e-3)
    }

    func testLutOnlyFixtureBecomesIccLutConverted() throws {
        let d = try describe("lut-a2b0-8.tif")
        XCTAssertEqual(d.origin, .iccLutConverted)
        XCTAssertEqual(d.referral, .displayReferred)
        XCTAssertEqual(d.transfer, .linear)
        assertPrimaries(d, RasterColorResolver.rec2020Primaries)
        XCTAssertNotNil(d.profileHash)
    }

    func testDualTagFixturePrefersMatrixShaper() throws {
        let d = try describe("dual-tag-matrix-a2b0-16.tif")
        // Through the IFD route the ORIGINAL bytes survive (the platform's
        // system-sRGB reduction is exactly what this route dodges).
        XCTAssertEqual(d.origin, .iccMatrixShaper)
        XCTAssertEqual(d.transfer, .gamma(563.0 / 256.0))
        assertPrimaries(d, RasterColorResolver.sRGBPrimaries)
    }

    func testPQSampledTableFixtureCanonicalizesWithMdcvPeak() throws {
        let d = try describe("pq-sampled-table-16.tif")
        XCTAssertEqual(d.transfer, .st2084, "the 1024-point PQ table must canonicalize (the upstream R1 misread-back regression)")
        XCTAssertEqual(d.referral, .displayReferred)
        XCTAssertEqual(d.peakLuminanceNits, 4000.0, "the mDCv max luminance")
        assertPrimaries(d, RasterColorResolver.rec2020Primaries)
    }

    func testCicpFixtures() throws {
        let pq = try describe("pq-cicp-16.tif")
        XCTAssertEqual(pq.transfer, .st2084)
        XCTAssertEqual(pq.origin, .iccCicp)
        XCTAssertEqual(pq.peakLuminanceNits, 1000.0, "no mDCv → the ladder terminal")
        assertPrimaries(pq, RasterColorResolver.rec2020Primaries)

        let hlg = try describe("hlg-cicp-16.tif")
        XCTAssertEqual(hlg.transfer, .hlg)
        XCTAssertEqual(hlg.peakLuminanceNits, 1000.0)
    }

    func testDegeneratePrimariesFixtureFallsToDefault() throws {
        let d = try describe("degenerate-primaries-8.tif")
        XCTAssertEqual(d.origin, .defaultSrgb)
        XCTAssertEqual(d.transfer, .srgbPiecewise)
        XCTAssertTrue(d.defaultReason?.contains("usable") == true)
        XCTAssertNotNil(d.profileHash, "the demoted profile still hashes")
    }

    func testNoICCFixturesDefaultByStorage() throws {
        for name in ["no-icc-8.tif", "no-icc-16.tif"] {
            let d = try describe(name)
            XCTAssertEqual(d.origin, .defaultSrgb, name)
            XCTAssertEqual(d.transfer, .srgbPiecewise, name)
            XCTAssertEqual(d.referral, .displayReferred, name)
            XCTAssertNil(d.profileHash, name)
        }
    }

    /// ② the no-ICC float32 half → scene-linear Rec.709.
    func testNoICCFloat32FixtureIsSceneLinear() throws {
        let d = try describe("no-icc-float32.tif")
        XCTAssertEqual(d.referral, .sceneLinear)
        XCTAssertEqual(d.transfer, .linear)
        XCTAssertEqual(d.origin, .tiffNoIccFloatLinear)
        assertPrimaries(d, RasterColorResolver.rec2020Primaries)
        XCTAssertNil(d.profileHash)
    }

    /// ①′ the linear-ICC float32 half-edge (checker E1).
    func testLinearICCFloat32FixtureIsSceneLinear() throws {
        let d = try describe("linear-icc-float32.tif")
        XCTAssertEqual(d.referral, .sceneLinear)
        XCTAssertEqual(d.transfer, .linear)
        XCTAssertEqual(d.origin, .iccMatrixShaper)
        XCTAssertEqual(d.defaultReason, "linear-ICC float32 → scene-linear")
        assertPrimaries(d, RasterColorResolver.rec2020Primaries)
        XCTAssertEqual(Double(d.primariesXY[6]), 0.3127, accuracy: 2e-3)
    }

    func testGrayICCFixtureCarriesSRGBPrimaries() throws {
        let d = try describe("gray-icc-8.tif")
        XCTAssertEqual(d.origin, .iccMatrixShaper)
        XCTAssertEqual(d.transfer, .gamma(563.0 / 256.0))
        assertPrimaries(d, RasterColorResolver.sRGBPrimaries)
    }

    // MARK: - Platform-behavior pins (the presentation facts the IFD route
    // is justified against)

    func testNoICCFixturePresentsSynthesizedSystemSRGB() throws {
        // The host-probed fact: an untagged 16-bit TIFF presents the SYSTEM
        // sRGB profile through the colorspace face (3144 bytes) with NO
        // ProfileName — the synthesized-profile ambiguity that forces the
        // IFD route for 8/16-bit.
        let url = try fixture("no-icc-16.tif")
        let src = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        XCTAssertNil(props?[kCGImagePropertyProfileName])
        let name = img.colorSpace?.name as String?
        XCTAssertEqual(name, "kCGColorSpaceSRGB")
    }

    func testUntaggedFloat32PresentsExtendedLinearSRGB() throws {
        // The RAW-03 presentation fact: float32 TIFF arrives as
        // extendedLinearSRGB (bit-depth-faithful, no CLUT conversion).
        let url = try fixture("no-icc-float32.tif")
        let src = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        XCTAssertEqual(img.bitsPerComponent, 32)
        XCTAssertEqual(img.colorSpace?.name as String?, "kCGColorSpaceExtendedLinearSRGB")
    }

    func testMultipageFixtureReportsTwoPages() throws {
        let url = try fixture("multipage-16.tif")
        let src = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
        XCTAssertEqual(CGImageSourceGetCount(src), 2)
    }

    func testCMYKFixturePresentsCMYKModel() throws {
        // The typed-reject input face: the CGImage colorspace model is
        // .cmyk (the T6 decoder's reject predicate).
        let url = try fixture("cmyk-8.tif")
        let src = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        XCTAssertEqual(img.colorSpace?.model, .cmyk)
    }

    // MARK: - TRC host Float64 double anchors (public standard values)

    func testSRGBPiecewiseAnchors() {
        // IEC 61966-2-1: the knee 0.04045 ↔ 0.0031308 both directions.
        XCTAssertEqual(RasterTRC.srgbPiecewiseDecode(0.5), 0.21404114048223255, accuracy: 1e-12)
        XCTAssertEqual(RasterTRC.srgbPiecewiseDecode(0.04045), 0.0031308049535603713, accuracy: 1e-12)
        XCTAssertEqual(RasterTRC.srgbPiecewiseDecode(0.04044), 0.0031300309597523217, accuracy: 1e-12)
        XCTAssertEqual(RasterTRC.srgbPiecewiseEncode(0.0031308), 0.04045, accuracy: 1e-6)
        XCTAssertEqual(RasterTRC.srgbPiecewiseEncode(0.5), 0.7353569830524495, accuracy: 1e-12)
        // Round-trip across the ramp (the exact-inverse contract).
        for i in 0...20 {
            let linear = Double(i) / 20.0
            XCTAssertEqual(
                RasterTRC.srgbPiecewiseDecode(RasterTRC.srgbPiecewiseEncode(linear)),
                linear, accuracy: 1e-12)
        }
    }

    func testPQRelativeShapeAnchors() {
        // BT.2100 PQ: code 0.25 / 0.5 on the relative (0..1 = 0..10000 nits)
        // domain, and the 100-nit anchor agrees with the pinned DrtEotfMath.
        XCTAssertEqual(RasterTRC.pqDecodeRelative(0.25), 0.0005154176009833007, accuracy: 1e-12)
        XCTAssertEqual(RasterTRC.pqDecodeRelative(0.5), 0.009224570899406526, accuracy: 1e-12)
        XCTAssertEqual(RasterTRC.pqDecodeRelative(1.0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(RasterTRC.pqDecodeRelative(0.0), 0.0, accuracy: 1e-12)
        // Cross-anchor against the EOTF face: the 100-nit point.
        XCTAssertEqual(
            RasterTRC.pqDecodeRelative(DrtEotfMath.st2084EncodeY(1.0, peak: 100)),
            100.0 / 10000.0, accuracy: 1e-12)
    }

    func testHLGDisplayShapeAnchors() {
        // The 1000-nit reference display curve (OOTF γ=1.2 of the OETF).
        XCTAssertEqual(RasterTRC.hlgDisplayDecode(0.75), 0.2031521453536661, accuracy: 1e-12)
        XCTAssertEqual(RasterTRC.hlgDisplayDecode(0.25), 0.009605290744601333, accuracy: 1e-12)
        XCTAssertEqual(RasterTRC.hlgDisplayDecode(0.0), 0.0, accuracy: 1e-12)
        // The reference HLG system identity: 0.75 signal = 75% display at
        // the reference peak (the BT.2100 anchor already pinned in
        // DrtEotfTests through the encode face).
        let display = RasterTRC.hlgDisplayDecode(0.75)
        XCTAssertEqual(Foundation.pow(display, 1 / 1.2), 0.26496, accuracy: 1e-4)
    }

    // MARK: - Usable checks through fixtures (the negative face)

    func testUsableCheckGatesDirect() {
        // The barycentric white-inside test over the canonical gamuts.
        XCTAssertTrue(RasterColorResolver.triangleUsable(primaries: RasterColorResolver.sRGBPrimaries))
        XCTAssertTrue(RasterColorResolver.triangleUsable(primaries: RasterColorResolver.proPhotoPrimaries))
        // The white far outside the triangle.
        var outside = RasterColorResolver.sRGBPrimaries
        outside[6] = 0.05
        outside[7] = 0.9
        XCTAssertFalse(RasterColorResolver.triangleUsable(primaries: outside))
        // Degenerate (B primary collapsed onto R).
        var degenerate = RasterColorResolver.sRGBPrimaries
        degenerate[4] = degenerate[0]
        degenerate[5] = degenerate[1]
        XCTAssertFalse(RasterColorResolver.triangleUsable(primaries: degenerate))
        // Monotonic gate.
        XCTAssertTrue(RasterColorResolver.isMonotonic([0.0, 0.1, 0.2, 0.4]))
        XCTAssertFalse(RasterColorResolver.isMonotonic([0.0, 0.2, 0.1, 0.4]))
    }
}
