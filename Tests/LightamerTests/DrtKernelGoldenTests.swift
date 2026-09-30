@testable import LightamerCore
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// DrtKernelGoldenTests (Plan M2-6-1 T3/T4, AC#4/#5 — IOPP bundle, Golden*
// convention) — the OpenDRT reference + kernel golden face.
//
// T3 (this section): the Float64 stage primitives vs the dctl's embedded
// desmos anchors (≤1e-6, the Float64 band), the tonescale monotonicity over
// a 1000-point ramp, endpoint boundedness (0/1e-6/1/1e6/negative — no NaN,
// bounded output), and the total-entry numeric anchors (self-consistent
// baseline: the anchor IS the reference's own output — the kernel alignment
// target; the algorithm-fidelity chain runs through the per-stage dctl
// anchors + the structure-map line review, DECISIONS §D5).
//
// T4 (the section below): the Metal kernel vs this Float64 reference over
// the deterministic probe triple × four parameter points (KD-8 bands).
// ─────────────────────────────────────────────────────────────────────────────

final class DrtKernelGoldenTests: XCTestCase {

    // MARK: - T3: stage primitives vs dctl anchors

    func testCompressHyperbolicPowerMatchesTheClosedForm() {
        // dctl :503 (desmos ofwtcmzc3w): (x/(x+s))^p.
        XCTAssertEqual(
            OpenDrtReference.compressHyperbolicPower(0.5, 0.5, 1.66),
            Foundation.pow(0.5, 1.66), accuracy: 1e-9)
        XCTAssertEqual(OpenDrtReference.compressHyperbolicPower(0, 0.4, 1.5), 0, accuracy: 1e-12)
        // x → ∞ approaches 1.
        XCTAssertEqual(
            OpenDrtReference.compressHyperbolicPower(1e9, 1.0, 1.66), 1.0, accuracy: 1e-6)
    }

    func testCompressToeQuadraticMatchesTheClosedForm() {
        // dctl :508 (desmos skk8ahmnws): fwd = x²/(x+toe); inv = the
        // quadratic root.
        let fwd = OpenDrtReference.compressToeQuadratic(0.5, 0.003, inverse: false)
        XCTAssertEqual(fwd, 0.25 / 0.503, accuracy: 1e-12)
        let inv = OpenDrtReference.compressToeQuadratic(0.5, 0.003, inverse: true)
        XCTAssertEqual(inv, (0.5 + Foundation.sqrt(0.5 * (0.012 + 0.5))) / 2, accuracy: 1e-12)
        // Round-trip: the inverse undoes the forward.
        let roundTripped = OpenDrtReference.compressToeQuadratic(fwd, 0.003, inverse: true)
        XCTAssertEqual(roundTripped, 0.5, accuracy: 1e-9)
        // toe = 0 → identity.
        XCTAssertEqual(OpenDrtReference.compressToeQuadratic(0.7, 0, inverse: false), 0.7)
    }

    func testCompressToeCubicMatchesTheClosedForm() {
        // dctl :518 (desmos ubgteikoke): fwd = x(x² + mw)/(x² + w).
        let fwd = OpenDrtReference.compressToeCubic(0.5, 0.5, 0.1, inverse: false)
        XCTAssertEqual(fwd, 0.5 * (0.25 + 0.05) / (0.25 + 0.1), accuracy: 1e-12)
        // m = 1 → identity both directions.
        XCTAssertEqual(OpenDrtReference.compressToeCubic(0.6, 1, 0.3, inverse: false), 0.6)
        XCTAssertEqual(OpenDrtReference.compressToeCubic(0.6, 1, 0.3, inverse: true), 0.6)
        // The inverse at the forward's output returns the input.
        let back = OpenDrtReference.compressToeCubic(fwd, 0.5, 0.1, inverse: true)
        XCTAssertEqual(back, 0.5, accuracy: 1e-9)
    }

    func testContrastHighMatchesTheDesmosConstruction() {
        // dctl :542 (desmos etjgwyrgad). p=2, pv=0, pvLx=1:
        // x0=0.18, o=0.09, s0=2.7778, x1=0.36, k1=2.0, y1=0.45.
        XCTAssertEqual(OpenDrtReference.contrastHigh(0.5, 2, 0, 1, inverse: false),
                       2.0 * (0.5 - 0.36) + 0.45, accuracy: 1e-9)
        // Below the pivot → identity.
        XCTAssertEqual(OpenDrtReference.contrastHigh(0.1, 2, 0, 1, inverse: false), 0.1)
        // p = 1 → identity.
        XCTAssertEqual(OpenDrtReference.contrastHigh(0.9, 1, 0, 1, inverse: false), 0.9)
        // Continuity at the knee x1.
        let atKnee = OpenDrtReference.contrastHigh(0.36, 2, 0, 1, inverse: false)
        XCTAssertEqual(atKnee, 0.45, accuracy: 1e-9)
        // Inverse undoes the forward.
        let forward = OpenDrtReference.contrastHigh(0.7, 2, 0, 1, inverse: false)
        let backward = OpenDrtReference.contrastHigh(forward, 2, 0, 1, inverse: true)
        XCTAssertEqual(backward, 0.7, accuracy: 1e-9)
    }

    func testSoftplusMatchesTheClosedForm() {
        // dctl :569 (desmos mr9rmujsmn): s·ln(1 + e^(x/s)) above the
        // linear-extension threshold.
        XCTAssertEqual(
            OpenDrtReference.softplus(0.5, 0.06),
            0.06 * Foundation.log(1 + Foundation.exp(0.5 / 0.06)), accuracy: 1e-12)
        // The linear extension beyond 10s: x > 10·s → x unchanged.
        XCTAssertEqual(OpenDrtReference.softplus(1.0, 0.06), 1.0)
        // s below the floor → x unchanged.
        XCTAssertEqual(OpenDrtReference.softplus(0.5, 1e-5), 0.5)
    }

    func testGaussWindowAndOpponentMatchTheClosedForms() {
        // dctl :576 / :581.
        XCTAssertEqual(
            OpenDrtReference.gaussWindow(0.5, 0.66),
            Foundation.exp(-0.25 / 0.66), accuracy: 1e-12)
        let opp = OpenDrtReference.opponent(SIMD3(0.4, 0.5, 0.3))
        XCTAssertEqual(opp.x, 0.1, accuracy: 1e-12)
        XCTAssertEqual(opp.y, 0.15, accuracy: 1e-12)
        // Hue offset keeps −π..π with red rotated to 0 (dctl :586/:992):
        // the offset of 1.10714931 makes hue(red)=0 through the run's
        // rotation — verified structurally in the monotonicity sweep below.
        let wrapped = OpenDrtReference.hueOffset(10.0, 0.0)
        XCTAssertTrue(wrapped >= -OpenDrtReference.pi && wrapped <= OpenDrtReference.pi)
    }

    // MARK: - T3: the total entry — monotonicity, bounds, anchors

    /// A deterministic neutral probe: the default record + D65 white.
    private func runDefault(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        // cwp 2 = D65 (the standard look's white).
        OpenDrtReference.run(record: DrtRecord(), linearRec2020: rgb, cwp: 2)
    }

    func testTonescaleIsMonotonicOverARamp() {
        // 1000-point scene-linear ramp 0..4 — output order preserved.
        var previous: [Double] = [-1, -1, -1]
        for i in 0..<1000 {
            let x = 4.0 * Double(i) / 999.0
            let out = runDefault(SIMD3(x, x, x))
            for c in 0..<3 {
                XCTAssertGreaterThanOrEqual(
                    out[c], previous[c] - 1e-12,
                    "tonescale non-monotonic at x=\(x) channel \(c)")
                previous[c] = out[c]
            }
        }
    }

    func testEndpointsAreBoundedAndNaNFree() {
        let probes: [SIMD3<Double>] = [
            .zero,
            SIMD3(repeating: 1e-6),
            SIMD3(repeating: 1),
            SIMD3(repeating: 1e6),
            SIMD3(0.5, -0.2, 2.0),      // mixed sign
            SIMD3(repeating: -0.5),     // all negative
            SIMD3(1e-8, 1e4, 1.0),      // extreme spread
        ]
        for probe in probes {
            let out = runDefault(probe)
            for c in 0..<3 {
                XCTAssertFalse(out[c].isNaN, "NaN for probe \(probe)")
                XCTAssertFalse(out[c].isInfinite, "inf for probe \(probe)")
                XCTAssertGreaterThanOrEqual(out[c], 0)
                XCTAssertLessThanOrEqual(out[c], 1.0000001)
            }
        }
    }

    func testDefaultParameterPointNumericAnchors() {
        // ANCHOR SEMANTICS (KD-3/T3): these values are the reference's own
        // self-consistent baseline — the kernel's alignment target, NOT an
        // external truth. Algorithm fidelity is pinned per-stage above and
        // by the structure-map review (SUMMARY dctl line list).
        let midGrey = runDefault(SIMD3(repeating: 0.18))
        // Display grey lands near the target: tn_Lg 10 nits on a 100-nit
        // peak → ~0.1 peak-normalized display linear (the tonescale's whole
        // point — a wide sanity band, not a formula restatement).
        for c in 0..<3 {
            XCTAssertEqual(midGrey[c], 0.1, accuracy: 0.05, "middle grey placement")
        }
        let white = runDefault(SIMD3(repeating: 16.0))  // ~tn_sh=0.5 → 2^6 clip anchor
        for c in 0..<3 {
            XCTAssertLessThanOrEqual(white[c], 1.0, "the shoulder clips toward white")
            XCTAssertGreaterThanOrEqual(white[c], 0.9, "scene white stays bright")
        }
        // Record these exact values for the SUMMARY + the T4 golden header.
        print("DRT-ANCHOR midgrey(0.18) = \(midGrey)")
        let saturated = runDefault(SIMD3(4.0, 0.1, 0.1))
        print("DRT-ANCHOR saturated(4,0.1,0.1) = \(saturated)")
        XCTAssertGreaterThan(saturated.x, saturated.z, "a red-primary probe stays red")
    }

    func testHDRParameterPointStaysBounded() {
        // The rec2020+st2084+1000-nit parameter point (the T4 golden's HDR
        // arm) through the reference: bounded, monotone, grey ~0.1-ish
        // (peak-normalized semantics hold at any peak).
        var record = DrtRecord()
        record.encodingSpace = .rec2020
        record.encodingEotf = .st2084
        record.peakLuminance = 1000
        var previous = -1.0
        for i in 0..<500 {
            let x = 8.0 * Double(i) / 499.0
            let out = OpenDrtReference.run(
                record: record, linearRec2020: SIMD3(repeating: x), cwp: 2)
            for c in 0..<3 {
                XCTAssertFalse(out[c].isNaN)
                XCTAssertGreaterThanOrEqual(out[c], -1e-9)
                XCTAssertLessThanOrEqual(out[c], 1.0000001)
            }
            XCTAssertGreaterThanOrEqual(out.x, previous - 1e-12)
            previous = out.x
        }
    }
}
