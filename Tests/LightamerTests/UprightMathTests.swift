@testable import LightamerCore
import XCTest

/// UprightMathTests (Plan M9-3-T1) — the Guided Upright golden gates
/// (RESEARCH §5 direct port; upstream `tests_geometry.rs` reference faces).
///
/// HAND VALUES (every gate below carries an independent red-line argument —
/// the plan's ΔN over-band note):
/// - gate 1 (synthetic keystone inverse): a known shot homography S distorts
///   true verticals; guides drawn along the distorted lines must recover
///   them (x-trace spread < 1.5 px on a 720×480 face) AND equal S within
///   < 0.01 centred units at the four corners (the solve reproduces the
///   shot transform, not merely straightens — probed numerically before the
///   gate was pinned: worst 8e-16).
/// - gate 2 (single-guide exactness): one near-vertical guide can only
///   determine a pure rotation, and the level solve is exact — endpoint
///   x-trace difference < 1e-9 (a sign slip in `levelAngleWithin`'s dev
///   fold breaks this at O(0.1)).
/// - gate 3 (resolution independence): the centred-normalized coordinate
///   system makes the solve scale-blind; the same scene at 1200×800 vs
///   600×400 agrees to < 0.006 centred units.
/// - gate 4 (sign convention): a right-drooping horizon (y grows with x in
///   image coordinates) must read NEGATIVE straighten degrees (−6° ± 0.5) —
///   the user-visible direction lock (R-2).
/// - gate 5 (pathological defenses): coincident guides → identity (bitwise),
///   a VP inside the frame → rejected as a scene feature (consensus failure
///   → identity), an out-of-range orthogonal focal → DEFAULT_FOCAL=1.5 (the
///   solve must equal the hand-composed default-focal homography bitwise).
///
/// COMPARISON SPACE (L048): the whole math domain here is Double end-to-end
/// (no float32 storage plane exists in T1), so the decode-back-to-linear
/// clause has no surface in this file; the f32 leg enters at the T2 kernel
/// parity tests (UprightModuleParityTests, L006/L048 there).
final class UprightMathTests: XCTestCase {

    // MARK: - helpers

    /// A point through `S` (the shot transform).
    private static func project(_ h: Mat3D, _ p: SIMD2<Double>) -> SIMD2<Double> {
        let q = h.project(p.x, p.y)
        return SIMD2(q.x, q.y)
    }

    /// The three true verticals in the corrected domain, mapped through
    /// `S.inverted()` into the distorted (shot) domain — the guides a user
    /// would draw along the converging building lines.
    private static func keystoneGuides(shot: Mat3D) -> [UprightMath.Segment] {
        let inv = shot.inverted()!
        var guides: [UprightMath.Segment] = []
        for x in [-0.6, 0.0, 0.6] {
            let t0 = SIMD2(x, -0.55)
            let t1 = SIMD2(x, 0.55)
            guides.append(UprightMath.Segment(
                a: project(inv, t0),
                b: project(inv, t1)))
        }
        return guides
    }

    /// The known shot homography: a virtual camera rotation sending the
    /// vertical VP (0.4, −2.5) to the y axis, recentred (the solve's own
    /// closed form — the shape solveGuided must rediscover).
    private static func makeShotHomography() -> Mat3D {
        let r = UprightMath.solveVertical([0.4, -2.5, 1], UprightMath.defaultFocal)
        return UprightMath.recentre(UprightMath.rotationHomography(r, UprightMath.defaultFocal))
    }

    // MARK: - gate 1: synthetic keystone inverse (spread + shot equality)

    func testSyntheticKeystoneRecoveryMatchesShotHomography() {
        let shot = Self.makeShotHomography()
        let guides = Self.keystoneGuides(shot: shot)
        let solved = UprightMath.solveGuided(guides)

        // (a) x-trace spread of every recovered vertical, in px on a
        // 720×480 face (half-long = 360 px per centred unit).
        var worstSpread = 0.0
        for guide in guides {
            var xs: [Double] = []
            for t in stride(from: -0.55, through: 0.55, by: 0.055) {
                let u = (t - guide.a.y) / (guide.b.y - guide.a.y)
                let p = SIMD2(guide.a.x + u * (guide.b.x - guide.a.x), t)
                xs.append(Self.project(solved, p).x)
            }
            let spread = (xs.max()! - xs.min()!) * 360.0
            XCTAssertLessThan(spread, 1.5, "recovered vertical x-trace spread must stay under 1.5 px")
            worstSpread = max(worstSpread, spread)
        }
        // (b) the solve reproduces the SHOT homography (not just any
        // straightener): four-corner displacement < 0.01 centred units.
        var worstCorner = 0.0
        for (x, y) in [(-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5)] {
            let a = Self.project(solved, SIMD2(Double(x), Double(y)))
            let b = Self.project(shot, SIMD2(Double(x), Double(y)))
            let d = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
            worstCorner = max(worstCorner, d)
        }
        XCTAssertLessThan(worstCorner, 0.01, "the solve must equal the shot homography within 0.01 centred units")
        // (c) determinism: the closed form carries no RNG — a second run is
        // bitwise identical.
        let second = UprightMath.solveGuided(guides)
        XCTAssertEqual(solved, second, "solveGuided must be bitwise deterministic")
    }

    // MARK: - gate 2: single vertical guide = pure rotation, exact

    func testSingleVerticalGuideIsPureRotationExactTo1e9() {
        // one near-vertical guide (tilt ~ atan(0.05/0.8) ≈ 3.58°)
        let guide = UprightMath.Segment(a: SIMD2(0.10, -0.40), b: SIMD2(0.15, 0.40))
        let h = UprightMath.solveGuided([guide])
        // the guide's endpoints AND midpoint map to the same x (exact)
        var xs: [Double] = []
        for t in [-0.40, 0.0, 0.40] {
            let u = (t - guide.a.y) / (guide.b.y - guide.a.y)
            let p = SIMD2(guide.a.x + u * (guide.b.x - guide.a.x), t)
            xs.append(Self.project(h, p).x)
        }
        let spread = xs.max()! - xs.min()!
        XCTAssertLessThan(spread, 1e-9, "a single vertical guide must yield an EXACT pure rotation")
    }

    // MARK: - gate 3: resolution independence

    func testSolutionIsResolutionIndependent() {
        // the same scene drawn at 1200×800 and 600×400: pixel points on the
        // (proportionally identical) building lines, converted to centred
        // normalization per face ((p − centre) / (long edge / 2)).
        func guides(longEdge: Double) -> [UprightMath.Segment] {
            let halfLong = longEdge / 2
            func centre(_ px: SIMD2<Double>, w: Double, h: Double) -> SIMD2<Double> {
                SIMD2((px.x - w / 2) / halfLong, (px.y - h / 2) / halfLong)
            }
            var out: [UprightMath.Segment] = []
            // three verticals at 20% / 50% / 80% of the width
            for fx in [0.2, 0.5, 0.8] {
                let w = longEdge
                let h = longEdge * (2.0 / 3.0)
                let a = centre(SIMD2(fx * w, 0.05 * h), w: w, h: h)
                let b = centre(SIMD2(fx * w + 0.01 * w, 0.95 * h), w: w, h: h)
                out.append(UprightMath.Segment(a: a, b: b))
            }
            return out
        }
        let h1 = UprightMath.solveGuided(guides(longEdge: 1200))
        let h2 = UprightMath.solveGuided(guides(longEdge: 600))
        var worst = 0.0
        for (x, y) in [(-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5)] {
            let a = Self.project(h1, SIMD2(Double(x), Double(y)))
            let b = Self.project(h2, SIMD2(Double(x), Double(y)))
            worst = max(worst, ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot())
        }
        XCTAssertLessThan(worst, 0.006, "the centred-normalized solve must be resolution independent")
    }

    // MARK: - gate 4: sign convention

    func testRightDroopingHorizonReadsNegativeDegrees() {
        // three horizontal lines drooping to the right: y grows with x in
        // image coordinates (y-down), tilt 6° over the FULL segment — the
        // level solve must read NEGATIVE degrees (undo the droop).
        var horiz: [UprightMath.Segment] = []
        for y0 in [-0.3, 0.0, 0.3] {
            let dy = 1.2 * tan(6.0 * .pi / 180)
            horiz.append(UprightMath.Segment(
                a: SIMD2(-0.6, y0 - dy / 2),
                b: SIMD2(0.6, y0 + dy / 2)))
        }
        let angle = UprightMath.levelAngle(vert: [], horiz: horiz)
        guard let a = angle else {
            XCTFail("a three-line horizon must produce a level answer")
            return
        }
        XCTAssertEqual(a, -6.0, accuracy: 0.5, "a right-drooping horizon reads −6°±0.5 (sign lock)")
        // and through the guided solve the same: a pure-Z correction
        // (nil-nil path → levelAngle → rotZH) — no keystone may creep in
        let h = UprightMath.solveGuided(horiz)
        XCTAssertEqual(h[2, 0], 0, accuracy: 1e-12)
        XCTAssertEqual(h[2, 1], 0, accuracy: 1e-12)
    }

    // MARK: - gate 5: pathological defenses (three in one family)

    func testPathologicalGuidesDegradeWithoutCrashing() {
        // Defense 1 — coincident guides (cross norm² < 1e-24): no VP evidence
        // → level path → the guides are exactly vertical → identity bitwise.
        let same = UprightMath.Segment(a: SIMD2(-0.2, -0.4), b: SIMD2(-0.2, 0.4))
        let h1 = UprightMath.solveGuided([same, same])
        XCTAssertEqual(h1, .identity, "coincident vertical guides degrade to the identity")

        // Defense 2 — a VP inside the frame is a scene feature, not camera
        // tilt: three verticals converging at (0, 0) with tilts −5/0/+5°.
        // Rejected → levelAngle consensus fails (deviations spread wider than
        // the ±2° gate over half the length) → identity, no crash.
        func converging(_ tiltDegrees: Double) -> UprightMath.Segment {
            let a = tiltDegrees * .pi / 180
            return UprightMath.Segment(
                a: SIMD2(0, 0),
                b: SIMD2(sin(a) * 0.8, cos(a) * 0.8))
        }
        let h2 = UprightMath.solveGuided([converging(-5), converging(0), converging(5)])
        XCTAssertEqual(h2, .identity, "an in-frame VP is rejected; the spread-out consensus fails to identity")

        // Defense 3 — the orthogonal focal estimate outside 0.5..6.0 falls
        // back to DEFAULT_FOCAL=1.5: verticals converging at (10, 3) +
        // horizontals converging at (2, −20) give f² = −(10·2 + 3·(−20)) =
        // 40 → f ≈ 6.32 > 6 → nil → 1.5. Both VPs sit far outside the frame
        // (radii ≈ 10.4 / 20.1, defense 2 passes) and OFF the y=0 line (a
        // non-degenerate virtual camera — see the finite net below). The
        // solve must equal the hand-composed default-focal homography.
        func through(_ vp: SIMD2<Double>, _ tiltFromVertical: Double, length: Double) -> UprightMath.Segment {
            let a = tiltFromVertical * .pi / 180
            // direction: tilt from vertical (small = near-vertical)
            return UprightMath.Segment(
                a: vp,
                b: SIMD2(vp.x + sin(a) * length, vp.y + cos(a) * length))
        }
        let vert = [
            through(SIMD2(10, 3), -3, length: 0.9),
            through(SIMD2(10, 3), 3, length: 0.9),
        ]
        let horiz = [
            through(SIMD2(2, -20), 86, length: 0.9),
            through(SIMD2(2, -20), 94, length: 0.9),
        ]
        let solved = UprightMath.solveGuided(vert + horiz)
        let vRef = UprightMath.refineVP(vert)
        let hRef = UprightMath.refineVP(horiz)
        XCTAssertNil(UprightMath.focalFromVPs(vRef, hRef), "f² = 40 → f ≈ 6.32 sits outside 0.5..6.0")
        let expected = UprightMath.recentre(
            UprightMath.rotationHomography(
                UprightMath.solveFull(vRef, hRef, UprightMath.defaultFocal),
                UprightMath.defaultFocal))
        XCTAssertEqual(solved, expected, "out-of-range focal must fall back to DEFAULT_FOCAL=1.5 (bitwise)")

        // Defense 3's sibling — the degenerate-geometry net: both VPs ON the
        // y=0 line (a virtual camera rotated near 90°) zero the projective w
        // row of K·R·K⁻¹; the finite net must degrade to the level rotation
        // instead of letting NaN reach the warp.
        let degenerate = [
            through(SIMD2(3, 0), -4, length: 0.9),
            through(SIMD2(3, 0), 4, length: 0.9),
            through(SIMD2(-100.0 / 3.0, 0), 86, length: 0.9),
            through(SIMD2(-100.0 / 3.0, 0), 94, length: 0.9),
        ]
        let hDeg = UprightMath.solveGuided(degenerate)
        for r in 0..<3 {
            for c in 0..<3 {
                XCTAssertTrue(hDeg[r, c].isFinite, "degenerate geometry must degrade, never NaN")
            }
        }

        // near-parallel (0.3°) guides neither crash nor produce non-finite
        // values (they legitimately point at a far VP → a pure correction)
        let np1 = through(SIMD2(0, 0), 0, length: 1.0)
        let np2 = through(SIMD2(-0.5, 0), 0.3, length: 1.0)
        let h3 = UprightMath.solveGuided([np1, np2])
        for r in 0..<3 {
            for c in 0..<3 {
                XCTAssertTrue(h3[r, c].isFinite, "near-parallel guides must not produce non-finite output")
            }
        }
    }
}
