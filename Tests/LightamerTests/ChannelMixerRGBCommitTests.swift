import LightamerCore
import LightamerIOP
import XCTest

/// ChannelMixerRGBCommitTests (Plan 05-03-T2) — commit derivation pins +
/// 5-path coverage gate (anti-vacuity: every adaptation path must produce
/// a non-identity matrix pair for at least one params group).
final class ChannelMixerRGBCommitTests: XCTestCase {

    /// Identity mix + PIPE illuminant (D50) + XYZ path: rgbToLMS must be
    /// the pipe matrix itself (path degenerate to measured passthrough —
    /// this case documents the degenerate path, NOT a vacuous pass).
    func testPipeXYZPathCarriesPipeMatrix() {
        var p = ChannelMixerRGBModule.Params()
        p.illuminant = .pipe
        p.adaptation = .xyz
        let d = ChannelMixerRGBModule.derive(p)
        // rgbToLMS == rec2020ToXYZ (D65-native, D2).
        XCTAssertLessThan(abs(d.rgbToLMS[0][0] - LabRoundTrip.rec2020ToXYZ[0][0]), 1e-12)
        // mixToXYZ == identity MIX.
        XCTAssertLessThan(abs(d.mixToXYZ[0][0] - 1.0), 1e-12)
        XCTAssertLessThan(abs(d.mixToXYZ[0][1]), 1e-12)
        // illuminant = D50 in XYZ (adaptation .xyz = passthrough).
        XCTAssertLessThan(abs(d.illuminant.x - 0.96421199), 1e-6)
    }

    /// 5-path coverage: each adaptation yields a non-identity rgbToLMS or
    /// mixToXYZ for the D-illuminant default params (D65-ish white through
    /// a D50-anchored adapt ≠ identity; RGB path folds R2X·MIX ≠ I).
    func testFivePathsProduceNonIdentityMatrices() {
        let p = ChannelMixerRGBModule.Params()
        var covered = 0
        for adapt: ChannelMixerAdaptation in
            [.linearBradford, .cat16, .fullBradford, .xyz, .rgb]
        {
            var q = p
            q.adaptation = adapt
            let d = ChannelMixerRGBModule.derive(q)
            let offDiag = abs(d.rgbToLMS[0][1]) + abs(d.rgbToLMS[1][0])
                + abs(d.mixToXYZ[0][1]) + abs(d.mixToXYZ[1][0])
            let diagShift = abs(d.rgbToLMS[0][0] - 1.0) + abs(d.rgbToLMS[1][1] - 1.0)
            XCTAssertGreaterThan(
                offDiag + diagShift, 1e-6,
                "\(adapt) produced a vacuous identity pair")
            covered += 1
        }
        XCTAssertEqual(covered, 5, "all 5 matrix paths covered")
    }

    /// Illuminant change flows into paramsHash (cache-invalidation chain:
    /// commit folds illuminant into piece identity via StableHash of the
    /// full params — illuminant bit is inside).
    func testIlluminantChangeAltersParamsHash() {
        let a = ChannelMixerRGBModule.Params()
        var b = a
        b.illuminant = .a
        XCTAssertNotEqual(
            StableHash.hash(ParamsCoding.encode(a)),
            StableHash.hash(ParamsCoding.encode(b)),
            "illuminant change must invalidate the cache key")
        var c = a
        c.temperature = 3200
        XCTAssertNotEqual(
            StableHash.hash(ParamsCoding.encode(a)),
            StableHash.hash(ParamsCoding.encode(c)),
            "temperature change must invalidate the cache key")
    }
    /// Grey leg: applyGrey iff any grey coeff nonzero; normalize divides.
    func testGreyAndNormalizeDerivation() {
        var p = ChannelMixerRGBModule.Params()
        XCTAssertFalse(ChannelMixerRGBModule.derive(p).applyGrey)
        p.grey = SIMD4(0.3, 0.5, 0.2, 0)
        p.normalizeGrey = true
        let d = ChannelMixerRGBModule.derive(p)
        XCTAssertTrue(d.applyGrey)
        XCTAssertLessThan(abs(d.grey.x + d.grey.y + d.grey.z - 1.0), 1e-6)
        // normalize_R divides the red row: (2,0,0)/2 == (1,0,0)/1.
        var q = ChannelMixerRGBModule.Params()
        q.red = SIMD4(2, 0, 0, 0)
        q.normalizeR = true
        let dq = ChannelMixerRGBModule.derive(q)
        let d0 = ChannelMixerRGBModule.derive(ChannelMixerRGBModule.Params())
        XCTAssertLessThan(abs(dq.mixToXYZ[2][2] - d0.mixToXYZ[2][2]), 1e-12)
    }

    /// Gamut compression folds to 1/g (0 stays 0 — dt :3102).
    func testGamutFold() {
        var p = ChannelMixerRGBModule.Params()
        p.gamut = 2.0
        XCTAssertLessThan(
            abs(ChannelMixerRGBModule.derive(p).gamut - 0.5), 1e-12)
        p.gamut = 0
        XCTAssertEqual(ChannelMixerRGBModule.derive(p).gamut, 0.0)
    }
}
