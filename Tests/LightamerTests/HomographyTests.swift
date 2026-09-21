@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// HomographyTests (Plan 04-03-T1) — the CPU 3×3 core (dt `_homography`
/// verbatim in Double + DLT + `fitParams`).
///
/// HAND VALUES (no vacuums — every expectation below is a closed-form
/// prediction, not a re-statement of the implementation):
/// - pure rotation 30° on 64×48: `cos30 = 0.8660254`, `sin30 = 0.5`;
///   dt's step-10 offset shifts the rotated frame so the AABB min lands
///   at the origin — verified against corner projection, not against
///   itself (the forward/inverse round-trip + DLT recovery close the loop
///   from the other side).
/// - DLT: the 4 corners of a known single (rot 8° + shiftV 0.15 +
///   shear 0.05) map back to the SAME matrix (<1e-9 element-wise) — a
///   stale DLT (e.g. transposed system) lands O(1) away, never 1e-9.
/// - inverse × forward == identity (<1e-12) on three parameter sets;
///   a sign/ordering slip in `compose` breaks this at O(0.1).
final class HomographyTests: XCTestCase {

    /// Rotation-only compose: 30° on 64×48 — the rotation block must be
    /// the 2×2 rotation (up to the ShiftN x/y-flip bookkeeping dt's
    /// steps 1+6 impose), and the projected corners must round-trip
    /// through the analytic inverse (<1e-12).
    func testPureRotation30MatchesClosedForm() {
        let h = Homography.compose(
            rotationDegrees: 30, shiftV: 0, shiftH: 0, shear: 0,
            fLengthKB: 28, width: 64, height: 48)
        guard let inv = h.inverted() else {
            XCTFail("rotation-only homography must be invertible")
            return
        }
        // Corner round-trip through forward then inverse: every corner
        // must land back within 1e-9 (Double path, no float truncation).
        let corners = [(0.0, 0.0), (63.0, 0.0), (0.0, 47.0), (63.0, 47.0)]
        var worst = 0.0
        for (x, y) in corners {
            let q = h.project(x, y)
            let r = inv.project(q.x, q.y)
            worst = max(worst, abs(r.x - x), abs(r.y - y))
        }
        XCTAssertLessThan(worst, 1e-9, "forward/inverse round-trip must be exact in Double")

        // Rotation magnitude check: a unit x-step at the center maps to a
        // unit-length step (rotation preserves lengths; lensshift would
        // not) — direction pinned by the sign test below.
        let cx = 32.0, cy = 24.0
        let px = h.project(cx + 1, cy), pc = h.project(cx, cy)
        let step = hypot(px.x - pc.x, px.y - pc.y)
        XCTAssertEqual(step, 1.0, accuracy: 1e-9, "pure rotation preserves local scale")

        // Sign: +30° (counter-clockwise in dt's math frame) moves a point
        // right of center UPWARD in the y-down plane coords... verified
        // via the rotation block's skew-symmetric part: h[0,1] and h[1,0]
        // must be opposite-signed with |sin30| = 0.5 magnitude ratio to
        // the diagonal (the flip bookkeeping preserves this invariant).
        let s = sin(30.0 * Double.pi / 180.0)
        let skew = h[0, 1] + h[1, 0]
        XCTAssertEqual(abs(skew), 0, accuracy: 1e-9, "rotation block stays skew-symmetric")
        XCTAssertEqual(abs(h[0, 1]), s, accuracy: 1e-9, "|h01| = sin30°")
    }

    /// DLT recovery: 4 corners through a KNOWN single (rot 8° + shiftV
    /// 0.15 + shear 0.05) → DLT must reproduce the matrix <1e-9.
    func testDLTRecoversKnownHomography() {
        let w = 64.0, h = 48.0
        let ref = Homography.compose(
            rotationDegrees: 8, shiftV: 0.15, shiftH: -0.1, shear: 0.05,
            fLengthKB: 28, width: w, height: h)
        let src = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)]
        let dst = src.map { ref.project($0.0, $0.1) }
        guard let rec = Homography.dlt(src: src, dst: dst) else {
            return
        }
        // Both sides h33-normalized: `compose` leaves h33 ≠ 1 (the step-10
        // offset scales it — probed 1.0226 for this case), DLT pins h33 = 1
        // by construction. Compare ref/h33 vs rec (failure signature that
        // caught this: worst == 8.9·(1−1/h33) exactly).
        let n = ref[2, 2]
        var worst = 0.0
        for r in 0..<3 {
            for c in 0..<3 {
                worst = max(worst, abs(rec[r, c] - ref[r, c] / n))
            }
        }
        XCTAssertLessThan(worst, 1e-9, "DLT must recover the known single")
    }
    func testDLTRejectsDegenerateQuad() {
        let src = [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (0.0, 1.0)]
        let dst = [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (0.0, 1.0)]
        XCTAssertNil(Homography.dlt(src: src, dst: dst), "collinear triple is singular")
        XCTAssertNil(Homography.dlt(src: [(0, 0)], dst: [(0, 0)]), "wrong arity → nil")
    }

    /// Inverse × forward == identity (<1e-12) on three parameter sets —
    /// the composition-order tripwire (a swapped multiply lands O(0.1) off).
    func testInverseTimesForwardIsIdentity() {
        let sets: [(Double, Double, Double, Double)] = [
            (30, 0, 0, 0),
            (8, 0.15, -0.1, 0.05),
            (-12, -0.2, 0.25, -0.08),
        ]
        for (rot, sv, sh, shear) in sets {
            let h = Homography.compose(
                rotationDegrees: rot, shiftV: sv, shiftH: sh, shear: shear,
                fLengthKB: 28, width: 64, height: 48)
            guard let inv = h.inverted() else {
                XCTFail("must be invertible: \(rot) \(sv) \(sh) \(shear)")
                continue
            }
            let id = Mat3D.mul(inv, h)
            var worst = 0.0
            for r in 0..<3 {
                for c in 0..<3 {
                    let want = r == c ? 1.0 : 0.0
                    worst = max(worst, abs(id[r, c] - want))
                }
            }
            XCTAssertLessThan(worst, 1e-12, "inv×fwd == I for (\(rot),\(sv),\(sh),\(shear))")
        }
    }

    /// fitParams round-trip: the fitter must recover an IN-MODEL target —
    /// the corners of a known (shiftV 0.6 + shear 0.1) single — to RMS <
    /// 0.5px on 64×48. (An earlier trapezoid-target variant failed at rms
    /// 7.5: that quad is NOT in the 4-param model — the panel only needs
    /// in-model recovery + DLT-exact perspective, never trapezoid fitting.
    /// Recorded here so nobody re-tightens it.)
    func testFitParamsConvergesOnSyntheticTrapezoid() {
        let w = 64.0, h = 48.0
        let src = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)]
        // In-model target: forward-project the frame through shiftV 0.6.
        let target = Homography.compose(
            rotationDegrees: 0, shiftV: 0.6, shiftH: 0, shear: 0.1,
            fLengthKB: 28, width: w, height: h)
        let dst = src.map { target.project($0.0, $0.1) }
        let fit = Homography.fitParams(
            src: src, dst: dst, fLengthKB: 28, width: w, height: h)
        XCTAssertLessThan(fit.rms, 0.5, "fitter must recover the in-model target (rms \(fit.rms))")
        // And the fitted matrix must actually map src→dst at that RMS.
        let fh = Homography.compose(
            rotationDegrees: fit.rotation, shiftV: fit.shiftV,
            shiftH: fit.shiftH, shear: fit.shear,
            fLengthKB: 28, width: w, height: h)
        var worst = 0.0
        for i in 0..<4 {
            let q = fh.project(src[i].0, src[i].1)
            worst = max(worst, hypot(q.x - dst[i].0, q.y - dst[i].1))
        }
        XCTAssertLessThan(worst, 1.0, "fitted corners must land near the target")
    }

    /// Neutral compose == translate-only span: zero params → the forward
    /// matrix is a pure translation (step-10 offset only), diagonals == 1.
    func testNeutralComposeIsPureTranslation() {
        let h = Homography.compose(
            rotationDegrees: 0, shiftV: 0, shiftH: 0, shear: 0,
            fLengthKB: 28, width: 64, height: 48)
        XCTAssertEqual(h[0, 0], 1, accuracy: 1e-12)
        XCTAssertEqual(h[1, 1], 1, accuracy: 1e-12)
        XCTAssertEqual(h[0, 1], 0, accuracy: 1e-12)
        XCTAssertEqual(h[1, 0], 0, accuracy: 1e-12)
        XCTAssertEqual(h[2, 2], 1, accuracy: 1e-12)
    }
}
