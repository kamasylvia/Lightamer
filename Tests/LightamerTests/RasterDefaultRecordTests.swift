@testable import LightamerCore
import Foundation
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RasterDefaultRecordTests (Plan M4-1-01 T10, KD-9 — LAYERS bundle, the
// Core-level suite precedent) — the default-record derivation face:
//
//   • the mapping table row by row, with the JOINT RULE asserted per row:
//     every derived (encodingSpace, encodingEotf) ∈ legalEOTFs(space);
//   • the two-table separation (ProPhoto: limitingSpace=proPhoto BUT
//     encodingSpace=rec709);
//   • the pinned gamma fits (2.6/2.4/2.2 direct; 1.8 → gamma22 + reason —
//     gamma18 is never produced);
//   • the linear special case (the LUT arm and the ② arm → (rec709,
//     srgbPiecewise) + reason; the Rec2020-primary SDR face falls back to
//     rec709);
//   • the scene-linear probe branches (probe > 1.0 → (rec2020, st2084);
//     ≤ 1.0 → the SDR default) and the ①′ default pair;
//   • the HDR flag three branches (TRC flag / float probe / double no);
//   • the RGC policy pure function;
//   • the stableHash ZERO-DRIFT negative: the derivation's records hash
//     identically to hand-built records (DrtRecord is field-frozen — the
//     derivation invents no state).
// ─────────────────────────────────────────────────────────────────────────────

final class RasterDefaultRecordTests: XCTestCase {

    private func description(
        primaries: SIMD8<Float>? = nil,
        transfer: RasterTransfer,
        referral: RasterReferral = .displayReferred,
        peak: Float = 100
    ) -> RasterColorDescription {
        RasterColorDescription(
            referral: referral,
            primariesXY: primaries ?? RasterColorResolver.sRGBPrimaries,
            transfer: transfer,
            peakLuminanceNits: peak,
            origin: .iccMatrixShaper)
    }

    // MARK: - The mapping table (row by row + the joint rule)

    private func assertJointRule(
        _ derivation: RasterDefaultRecord.Derivation,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let legal = legalEOTFs(for: derivation.record.encodingSpace)
        XCTAssertTrue(
            legal.contains(derivation.record.encodingEotf),
            "the derived pair (\(derivation.record.encodingSpace.rawValue), "
                + "\(derivation.record.encodingEotf.rawValue)) violates the joint rule "
                + "(legal: \(legal.map { $0.rawValue }))",
            file: file, line: line)
    }

    func testSrgbSourceMapsToRec709SrgbPiecewise() {
        let d = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.sRGBPrimaries,
                transfer: .srgbPiecewise, peakLuminanceNits: 100,
                origin: .iccMatrixShaper),
            contentProbeMax: 0.5)
        XCTAssertEqual(d.record.method, .aces20)
        XCTAssertEqual(d.record.encodingSpace, .rec709)
        XCTAssertEqual(d.record.encodingEotf, .srgbPiecewise)
        XCTAssertEqual(d.record.limitingSpace, .rec709)
        XCTAssertEqual(d.record.peakLuminance, 100)
        XCTAssertNil(d.defaultReason)
        assertJointRule(d)
    }

    func testP3SourceMapsToP3D65Gamma22ChainHead() {
        // The p3d65 fallback chain head is gamma22 (KD-9) — a piecewise
        // SOURCE TRC snaps to the nearest LEGAL member (srgbPiecewise IS
        // legal for p3d65 now — KD-8).
        let d = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.displayP3Primaries,
                transfer: .srgbPiecewise, peakLuminanceNits: 100,
                origin: .iccMatrixShaper),
            contentProbeMax: 0.5)
        XCTAssertEqual(d.record.encodingSpace, .p3d65)
        XCTAssertEqual(d.record.encodingEotf, .srgbPiecewise)
        XCTAssertEqual(d.record.limitingSpace, .p3d65)
        XCTAssertNil(d.defaultReason)
        assertJointRule(d)
    }

    func testAdobeRGBTwoTableSeparation() {
        let d = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.adobeRGBPrimaries,
                transfer: .gamma(563.0 / 256.0), peakLuminanceNits: 100,
                origin: .iccMatrixShaper),
            contentProbeMax: 0.5)
        // limitingSpace KEEPS the source domain; encodingSpace falls to rec709.
        XCTAssertEqual(d.record.limitingSpace, .adobeRGB)
        XCTAssertEqual(d.record.encodingSpace, .rec709)
        assertJointRule(d)
        // gamma 563/256 = 2.199 → gamma22 (legal for rec709).
        XCTAssertEqual(d.record.encodingEotf, .gamma22)
        XCTAssertTrue(d.defaultReason?.contains("AdobeRGB") == true)
    }

    func testProPhotoTwoTableSeparation() {
        let d = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.proPhotoPrimaries,
                transfer: .gamma(1.8), peakLuminanceNits: 100,
                origin: .iccMatrixShaper),
            contentProbeMax: 0.5)
        XCTAssertEqual(d.record.limitingSpace, .proPhoto)
        XCTAssertEqual(d.record.encodingSpace, .rec709)
        XCTAssertEqual(d.record.encodingEotf, .gamma22,
                       "gamma 1.8 snaps to gamma22 — gamma18 is never offered")
        XCTAssertTrue(d.defaultReason?.contains("gamma18") == true)
        assertJointRule(d)
    }

    func testRec2020SourceWithPQStaysRec2020() {
        let d = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.rec2020Primaries,
                transfer: .st2084, peakLuminanceNits: 1000,
                origin: .iccCicp),
            contentProbeMax: 0.5)
        XCTAssertEqual(d.record.encodingSpace, .rec2020)
        XCTAssertEqual(d.record.encodingEotf, .st2084)
        XCTAssertEqual(d.record.limitingSpace, .rec2020)
        XCTAssertEqual(d.record.peakLuminance, 1000)
        XCTAssertNil(d.defaultReason)
        assertJointRule(d)
    }

    func testRec2020SourceWithSDRLinearFallsBackToRec709() {
        // rec2020's legal set is all-HDR — an SDR linear source must not
        // ride it (the KD-9 explicit face).
        let d = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.rec2020Primaries,
                transfer: .linear, peakLuminanceNits: 100,
                origin: .iccMatrixShaper),
            contentProbeMax: 0.5)
        XCTAssertEqual(d.record.encodingSpace, .rec709)
        XCTAssertEqual(d.record.encodingEotf, .srgbPiecewise)
        XCTAssertEqual(d.record.limitingSpace, .rec2020)
        XCTAssertTrue(d.defaultReason?.contains("all-HDR") == true)
        assertJointRule(d)
    }

    func testUnknownPrimariesFallToRec2020Limiting() {
        // Arbitrary synthetic primaries → the limiting rec2020 + reason.
        var primaries = RasterColorResolver.sRGBPrimaries
        primaries[0] = 0.55
        primaries[2] = 0.45
        let d = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .displayReferred, primariesXY: primaries,
                transfer: .srgbPiecewise, peakLuminanceNits: 100,
                origin: .iccMatrixShaper),
            contentProbeMax: 0.5)
        XCTAssertEqual(d.record.limitingSpace, .rec2020)
        XCTAssertTrue(d.defaultReason?.contains("no known space") == true)
        assertJointRule(d)
    }

    // MARK: - The pinned gamma fits

    func testGammaFits() {
        func deriveGamma(_ g: Double) -> RasterDefaultRecord.Derivation {
            RasterDefaultRecord.derive(
                from: RasterColorDescription(
                    referral: .displayReferred,
                    primariesXY: RasterColorResolver.sRGBPrimaries,
                    transfer: .gamma(g), peakLuminanceNits: 100,
                    origin: .iccMatrixShaper),
                contentProbeMax: 0.5)
        }
        // The rec709 encoding's legal set has no gamma26 — the pinned 2.6
        // fit falls to the nearest LEGAL member (bt1886, Δ0.2); the
        // joint rule holds (this is the "nearest legal" face, not a miss).
        XCTAssertEqual(deriveGamma(2.6).record.encodingEotf, .bt1886)
        XCTAssertEqual(deriveGamma(2.4).record.encodingEotf, .bt1886)
        XCTAssertEqual(deriveGamma(2.2).record.encodingEotf, .gamma22)
        // The 1.8 → gamma22 snap with the reason (gamma18 never produced).
        let g18 = deriveGamma(1.8)
        XCTAssertEqual(g18.record.encodingEotf, .gamma22)
        XCTAssertTrue(g18.defaultReason?.contains("gamma18") == true)
        // An off-grid gamma → the nearest legal member + reason.
        let g20 = deriveGamma(2.0)
        XCTAssertEqual(g20.record.encodingEotf, .gamma22)
        XCTAssertTrue(g20.defaultReason?.contains("nearest legal") == true)
        assertJointRule(g20)
        assertJointRule(deriveGamma(2.6))
        assertJointRule(deriveGamma(2.4))
        assertJointRule(deriveGamma(2.2))
    }

    // MARK: - The linear special case + the probe branches

    func testLinearDisplayReferredSpecialCase() {
        // The LUT-ICC arm (display-referred linear).
        let d = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.rec2020Primaries,
                transfer: .linear, peakLuminanceNits: 100,
                origin: .iccLutConverted),
            contentProbeMax: 0.5)
        XCTAssertEqual(d.record.encodingSpace, .rec709)
        XCTAssertEqual(d.record.encodingEotf, .srgbPiecewise)
        XCTAssertTrue(d.defaultReason?.contains("no SDR-legal near neighbor") == true)
        assertJointRule(d)
    }

    func testSceneLinearProbeBranches() {
        // probe > 1.0 → the DRT-HDR pair.
        let hdr = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .sceneLinear, primariesXY: RasterColorResolver.rec2020Primaries,
                transfer: .linear, peakLuminanceNits: 100,
                origin: .tiffNoIccFloatLinear),
            contentProbeMax: 2.0)
        XCTAssertEqual(hdr.record.encodingSpace, .rec2020)
        XCTAssertEqual(hdr.record.encodingEotf, .st2084)
        assertJointRule(hdr)
        XCTAssertTrue(hdr.defaultReason?.contains("DRT-HDR") == true)

        // probe ≤ 1.0 → the SDR default (rec709, srgbPiecewise).
        let sdr = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .sceneLinear, primariesXY: RasterColorResolver.rec2020Primaries,
                transfer: .linear, peakLuminanceNits: 100,
                origin: .tiffNoIccFloatLinear),
            contentProbeMax: 1.0)
        XCTAssertEqual(sdr.record.encodingSpace, .rec709)
        XCTAssertEqual(sdr.record.encodingEotf, .srgbPiecewise)
        assertJointRule(sdr)
    }

    /// The ①′ half-edge's default pair: linear-ICC float32 with SDR content.
    func testLinearICCFloat32DefaultPair() {
        let d = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .sceneLinear, primariesXY: RasterColorResolver.rec2020Primaries,
                transfer: .linear, peakLuminanceNits: 100,
                origin: .iccMatrixShaper),
            contentProbeMax: 0.9)
        XCTAssertEqual(d.record.encodingSpace, .rec709)
        XCTAssertEqual(d.record.encodingEotf, .srgbPiecewise)
        XCTAssertEqual(d.record.limitingSpace, .rec2020)
        assertJointRule(d)
    }

    // MARK: - The HDR flag (three branches)

    func testHdrFlagThreeBranches() {
        // 1. The TRC flag (display-referred PQ, probe ≤ 1).
        XCTAssertTrue(RasterDefaultRecord.isHdrRaster(
            RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.rec2020Primaries,
                transfer: .st2084, peakLuminanceNits: 1000, origin: .iccCicp),
            contentProbeMax: 0.5))
        XCTAssertTrue(RasterDefaultRecord.isHdrRaster(
            RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.rec2020Primaries,
                transfer: .hlg, peakLuminanceNits: 1000, origin: .iccCicp),
            contentProbeMax: 0.5))
        // 2. The float probe (scene-linear, probe > 1).
        XCTAssertTrue(RasterDefaultRecord.isHdrRaster(
            RasterColorDescription(
                referral: .sceneLinear, primariesXY: RasterColorResolver.rec2020Primaries,
                transfer: .linear, peakLuminanceNits: 100,
                origin: .tiffNoIccFloatLinear),
            contentProbeMax: 1.5))
        // 3. The double no (SDR display-referred, probe ≤ 1).
        XCTAssertFalse(RasterDefaultRecord.isHdrRaster(
            RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.sRGBPrimaries,
                transfer: .srgbPiecewise, peakLuminanceNits: 100,
                origin: .defaultSrgb),
            contentProbeMax: 1.0))
    }

    // MARK: - The RGC policy

    func testRgcPolicySingleSource() {
        // raster documents: RGC OFF both directions.
        XCTAssertFalse(RasterDefaultRecord.rgcOn(
            rasterColor: RasterColorResolver.resolve(
                iccData: nil, colorSpaceName: nil, isFloat: false)))
        // RAW documents (nil description): the forward default ON.
        XCTAssertTrue(RasterDefaultRecord.rgcOn(rasterColor: nil))
        XCTAssertTrue(RasterDefaultRecord.isRasterDocument(
            RasterColorResolver.resolve(
                iccData: nil, colorSpaceName: nil, isFloat: false)))
        XCTAssertFalse(RasterDefaultRecord.isRasterDocument(nil))
    }

    // MARK: - The stableHash zero-drift negative

    func testDerivedRecordHashMatchesHandBuiltBaseline() {
        // DrtRecord is field-frozen: the derivation must produce records
        // whose canonical-JSON hash equals the hand-built equivalent (the
        // M2-6 baseline hash face — no invented state, no field drift).
        var hand = DrtRecord()
        hand.method = .aces20
        hand.encodingSpace = .rec709
        hand.encodingEotf = .srgbPiecewise
        hand.limitingSpace = .rec709
        hand.peakLuminance = 100
        let derived = RasterDefaultRecord.derive(
            from: RasterColorDescription(
                referral: .displayReferred, primariesXY: RasterColorResolver.sRGBPrimaries,
                transfer: .srgbPiecewise, peakLuminanceNits: 100,
                origin: .iccMatrixShaper),
            contentProbeMax: 0.5)
        XCTAssertEqual(derived.record, hand)
        XCTAssertEqual(derived.record.stableHash(), hand.stableHash())
        // And the pre-M4-1 default record hash is untouched by this plan.
        XCTAssertEqual(DrtRecord().stableHash(), DrtRecord().stableHash())
    }
}
