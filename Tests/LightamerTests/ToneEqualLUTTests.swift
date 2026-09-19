@testable import LightamerCore
import Foundation
@testable import LightamerIOP
import XCTest

// ToneEqualLUTTests (Plan 03-05-T1) — the CPU correction-LUT surface:
// dt `compute_correction_lut` semantics through `CorrectionLUT`.
//
// REFERENCE SEMANTICS (dt toneequal.c:1225-1651): user bands (EV) → exp2 →
// 9×8 least-squares projection (Float Cholesky, choleski.h verbatim) →
// 80001-entry LUT clamped [0.25, 4]. All-zero bands are a ~1-ripple
// approximation of identity (the RBF fit of the constant 1 — NOT exact;
// dt behaves identically, the ripple envelope is what the test pins).
final class ToneEqualLUTTests: XCTestCase {

    private static let sigma = Float(1.414_213_5) // dt smoothing default √2

    // MARK: - Identity ripple (all-zero bands)

    /// All-zero band params → the LUT fits the constant gain 1; the
    /// residual ripple stays within ~2e-2 across the whole [−8, 0] EV
    /// range (measured envelope of dt's own fit; the RBF approximation
    /// withholds one degree of freedom, and the float Cholesky
    /// conditioning adds ~1e-4 asymmetry — dt carries the same).
    func testAllZeroBandsNearIdentity() throws {
        let weights = try XCTUnwrap(
            CorrectionLUT.weights(bands: [Float](repeating: 0, count: 9), sigma: Self.sigma))
        let lut = CorrectionLUT.lut(weights: weights, sigma: Self.sigma)
        XCTAssertEqual(lut.count, CorrectionLUT.lutCount) // 80001
        var maxDeviation: Float = 0
        for v in lut {
            maxDeviation = max(maxDeviation, abs(v - 1))
        }
        XCTAssertLessThan(maxDeviation, 2e-2,
                          "all-zero ripple envelope exceeded: \(maxDeviation)")
    }

    // MARK: - Single-band response

    /// shadows = +1 EV → the correction peaks at the shadows band center
    /// (−4 EV) with the gain near 2 (= 2^+1), falling off by ~±2 EV.
    func testSingleBandPeakAtBandCenter() throws {
        var bands = [Float](repeating: 0, count: 9)
        bands[4] = 1.0 // shadows, center −4 EV
        let weights = try XCTUnwrap(CorrectionLUT.weights(bands: bands, sigma: Self.sigma))
        let lut = CorrectionLUT.lut(weights: weights, sigma: Self.sigma)

        let centerIndex = 4 * CorrectionLUT.lutResolution // −4 EV
        // The least-squares fit SMOOTHES the +1EV band impulse: the peak
        // lands at ~1.75 (the RBF approximation's undershoot — dt's own
        // behavior with the same fit), still clearly above the 1.0 base.
        XCTAssertGreaterThan(lut[centerIndex], 1.7, "peak gain at −4 EV (smoothed 2^+1)")

        // argmax within ±0.3 EV of the band center.
        var argmax = 0
        for (i, v) in lut.enumerated() where v > lut[argmax] { argmax = i }
        let argmaxEV = Float(argmax) / Float(CorrectionLUT.lutResolution) - 8.0
        XCTAssertEqual(Double(argmaxEV), -4.0, accuracy: 0.3)

        // Two EV away the response decays well below the peak.
        let twoEVAway = lut[2 * CorrectionLUT.lutResolution] // −6 EV
        XCTAssertLessThan(twoEVAway, lut[centerIndex] - 0.5)
    }

    // MARK: - Clamping

    /// +2 EV on EVERY band → the raw RBF overshoots above 4 OFF-center
    /// (the least-squares smoothing keeps the −4 EV midpoint at ~3.97);
    /// every LUT entry stays ≤ 4 and the clamp is verifiably load-bearing.
    func testUpperClampAtFullPlus2() throws {
        let weights = try XCTUnwrap(
            CorrectionLUT.weights(bands: [Float](repeating: 2, count: 9), sigma: Self.sigma))
        let lut = CorrectionLUT.lut(weights: weights, sigma: Self.sigma)
        for v in lut {
            XCTAssertLessThanOrEqual(v, 4.0 + 1e-6)
            XCTAssertGreaterThanOrEqual(v, 0.25 - 1e-6)
        }
        // The clamp is ACTIVE: the same evaluation WITHOUT the clamp
        // exceeds 4 away from the midpoint.
        let denom = CorrectionLUT.gaussianDenom(sigma: Self.sigma)
        var rawMax: Float = 0
        for j in stride(from: 0, to: CorrectionLUT.lutCount, by: 97) {
            let exposure = Float(j) / Float(CorrectionLUT.lutResolution) - 8.0
            var raw: Float = 0
            for i in 0..<8 {
                raw += CorrectionLUT.gaussianFunc(radius: exposure - CorrectionLUT.centersOps[i], denom: denom) * weights[i]
            }
            rawMax = max(rawMax, raw)
        }
        XCTAssertGreaterThan(rawMax, 4.0, "test setup: the clamp must be load-bearing")
    }

    /// −2 EV on every band → clamped at 0.25 somewhere in the deep end.
    func testLowerClampAtFullMinus2() throws {
        let weights = try XCTUnwrap(
            CorrectionLUT.weights(bands: [Float](repeating: -2, count: 9), sigma: Self.sigma))
        let lut = CorrectionLUT.lut(weights: weights, sigma: Self.sigma)
        XCTAssertGreaterThanOrEqual(lut.min() ?? 1, 0.25 - 1e-6)
        XCTAssertLessThanOrEqual(lut.min() ?? 1, 0.26)
    }

    // MARK: - The lookup semantics (apply side)

    /// lutIndex reproduces dt's `roundf((clamp(log2(luma), −8, 0) + 8) ×
    /// 10000)` — the full [0, 80000] domain.
    func testLutIndexSemantics() {
        XCTAssertEqual(CorrectionLUT.lutIndex(luma: 1.0), 80_000)      // 0 EV
        XCTAssertEqual(CorrectionLUT.lutIndex(luma: 1.0 / 256.0), 0)   // −8 EV
        XCTAssertEqual(CorrectionLUT.lutIndex(luma: 1.0 / 65536.0), 0) // clamped
        XCTAssertEqual(CorrectionLUT.lutIndex(luma: 1000.0), 80_000)   // clamped
        // −4 EV = 1/16: index 40000 (exact rounding on the grid point).
        XCTAssertEqual(CorrectionLUT.lutIndex(luma: 1.0 / 16.0), 40_000)
    }

    // MARK: - UI surface (one interpolation, two consumers)

    /// The UI curve samples and the kernel LUT agree EXACTLY (same
    /// pixelCorrection evaluation — the plan's "one code path, two
    /// consumers" acceptance).
    func testUICurveMatchesLUT() throws {
        var bands = [Float](repeating: 0, count: 9)
        bands[4] = 0.7
        bands[6] = -0.5
        let weights = try XCTUnwrap(CorrectionLUT.weights(bands: bands, sigma: Self.sigma))
        let lut = CorrectionLUT.lut(weights: weights, sigma: Self.sigma)
        let samples = CorrectionLUT.uiCurveSamples(weights: weights, sigma: Self.sigma, samples: 256)
        for (ev, gain) in samples {
            // The LUT grid quantizes the EV axis at 1e-4 EV; the curve
            // changes ~2e-5 per grid step mid-range, so the same-source
            // agreement gate sits just above the quantization step.
            let idx = Int(((ev + 8.0) * Float(CorrectionLUT.lutResolution)).rounded())
            XCTAssertEqual(gain, lut[idx], accuracy: 5e-5, "EV \(ev)")
        }
        // The band-center handles: gains equal the UI curve at the same EV.
        let gainsEV = CorrectionLUT.channelGainsEV(weights: weights, sigma: Self.sigma)
        for (i, ev) in CorrectionLUT.centersParams.enumerated() {
            let idx = Int(((ev + 8.0) * Float(CorrectionLUT.lutResolution)).rounded())
            XCTAssertEqual(exp2(gainsEV[i]), lut[idx], accuracy: 2e-3,
                           "band \(i) handle vs curve (RBF ripple)")
        }
    }

    // MARK: - Derivation commit half

    /// commit_params scalar derivations (:1596-1620): blending %, the
    /// feathering INVERSION, the exp2 boosts.
    func testDerivedScalars() {
        let d = ToneEqualModule.derive(ToneEqualModule.Params(
            blending: 5, feathering: 4, contrastBoost: 2, exposureBoost: -3))
        XCTAssertEqual(d.blending, 0.05, accuracy: 1e-6)
        XCTAssertEqual(d.feathering, 0.25, accuracy: 1e-6, "dt inverts the UI feathering")
        XCTAssertEqual(d.contrastBoost, 4.0, accuracy: 1e-5)
        XCTAssertEqual(d.exposureBoost, 0.125, accuracy: 1e-5)
        XCTAssertEqual(d.iterations, 1)
        XCTAssertEqual(d.details, Int32(ToneEqualDetails.eigf.rawValue))
        XCTAssertEqual(d.method, Int32(ToneEqualMethod.norm2.rawValue))
    }
}
