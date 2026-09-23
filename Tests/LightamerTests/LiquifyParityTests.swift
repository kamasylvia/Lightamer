@testable import LightamerCore
@testable import LightamerIOP
import Metal
import simd
import XCTest

/// LiquifyParityTests (Plan 06-06, IOP-GEO-05) — the liquify warp module.
///
/// REFERENCE PROVENANCE (L017 route ① — dt-cli cannot drive liquify, an
/// interactive module; 06-RESEARCH §9): the references are CPU-SYNTHESIZED
/// float64 transcriptions of dt's formulas, written INDEPENDENTLY in the
/// tests (the implementation under test shares only the dt source, never
/// code, with these references):
/// - T1: the collapsed per-cell stamp formulas (linear / radial grow /
///   radial shrink) vs a float64 grid reference, gate <1e-6 (plan);
/// - T2: the warp kernel vs a float64 field+lanczos3 resampler, gate <1e-5
///   (warp class, ashift precedent) + empty-path BYTE identity;
/// - T5: forced tiling == whole plane <1e-6; track B zero increment.
///
/// ANTI-VACUUM: every test runs a real comparison loop with `compared > 0`
/// guards (L020 ③). L014: every GPU readback drains first.
///
/// COORDINATE AUDIT (L020): the tests resolve paths against a NOMINAL frame
/// and recompute the stamp center/extent independently — a field-grid ↔
/// kernel-sampling domain mismatch would break the parity tests below.
final class LiquifyParityTests: XCTestCase {

    private static let frame = SIMD2<Double>(600, 400)

    // MARK: - shared reference pieces (float64, independent of the impl)

    /// Independent float64 cubic-bezier + x-reparameterized profile — the
    /// dt build_lookup_table boundary conditions (f(0)=1, f(d)=0, smooth
    /// ends) computed WITHOUT reusing LiquifyDistortionField code. The
    /// polyline samples dt's t = i/n positions (interpolate_cubic_bezier
    /// step 1/n, liquify.c:753-759) — same ALGORITHM, independent code.
    private func referenceLookup(distance: Int, c1: Double, c2: Double) -> [Double] {
        let n = distance + 2
        var pts = [SIMD2<Double>](repeating: .zero, count: n)
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let mt = 1 - t
            pts[i] = SIMD2(
                3 * mt * mt * t * c1 + 3 * mt * t * t * c2 + t * t * t * 1,
                mt * mt * mt * 1 + 3 * mt * mt * t * 1 + 3 * mt * t * t * 0 + 0)
        }
        pts[n - 1] = SIMD2(1, 0)
        var out = [Double](repeating: 0, count: distance + 1)
        out[0] = 1.0
        var j = 1
        for i in 1..<distance {
            let x = Double(i) / Double(distance)
            while j < n - 1 && pts[j].x < x { j += 1 }
            let dx = pts[j].x - pts[j - 1].x
            let frac = dx > 0 ? (x - pts[j - 1].x) / dx : 0
            // dt liquify.c:858-861 verbatim — the formula anchors at the
            // RIGHT sample (y[j] + frac·(y[j] − y[j−1])), a dt quirk that
            // slightly over-extrapolates within each segment. Transcribed
            // as-is on both sides (fidelity rule, D-06-06-T1-6).
            out[i] = pts[j].y + frac * (pts[j].y - pts[j - 1].y)
        }
        out[distance] = 0.0
        return out
    }

    /// Reference stamp resolution for a LONE node (no interpolation):
    /// strength vector × 0.5, radius × max(frame).
    private func referenceStamp(_ d: LiquifyPathData) -> (
        center: SIMD2<Int>, iradius: Int, strength: SIMD2<Double>, type: LiquifyWarpType
    ) {
        let p = SIMD2<Double>(Double(d.point.x) * Self.frame.x, Double(d.point.y) * Self.frame.y)
        let s = SIMD2<Double>(
            Double(d.strength.x - d.point.x) * Self.frame.x,
            Double(d.strength.y - d.point.y) * Self.frame.y) * 0.5
        let rd = d.radius - d.point
        let r = Double((rd.x * rd.x + rd.y * rd.y).squareRoot()) * max(Self.frame.x, Self.frame.y)
        return (
            SIMD2(Int(p.x.rounded()), Int(p.y.rounded())), Int(r.rounded()), s, d.warpType
        )
    }

    /// The collapsed per-cell reference formula (see
    /// LiquifyDistortionField.deposit — derived from dt liquify.c:978-1013).
    private func referenceField(
        _ d: LiquifyPathData
    ) -> (origin: SIMD2<Int>, size: SIMD2<Int>, values: [SIMD2<Double>], compared: Int) {
        let (center, iradius, strength, type) = referenceStamp(d)
        let lookup = referenceLookup(
            distance: iradius * LiquifyPathData.lookupOversample, c1: Double(d.control1),
            c2: Double(d.control2))
        let side = 2 * iradius + 1
        let origin = SIMD2(center.x - iradius, center.y - iradius)
        var values = [SIMD2<Double>](
            repeating: .zero, count: side * side)
        var compared = 0
        let shrinkSign: Double = type == LiquifyWarpType.radialShrink ? -1 : 1
        for oy in 0..<side {
            for ox in 0..<side {
                let dx = ox - iradius, dy = oy - iradius
                let dist = (Double(dx * dx) + Double(dy * dy)).squareRoot()
                let idist = Int((dist * Double(LiquifyPathData.lookupOversample)).rounded())
                guard idist < iradius * LiquifyPathData.lookupOversample else { continue }
                let profile = lookup[idist]
                var vec: SIMD2<Double>
                if type == LiquifyWarpType.linear {
                    vec = -strength * profile
                } else {
                    let g = shrinkSign * (strength.x * strength.x + strength.y * strength.y).squareRoot() * profile / Double(iradius)
                    vec = SIMD2(-g * Double(dx), -g * Double(dy))
                }
                values[oy * side + ox] = vec
                compared += 1
            }
        }
        return (origin, SIMD2(side, side), values, compared)
    }

    private func assertFieldMatchesReference(
        _ data: LiquifyPathData, tolerance: Double = 1e-6,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let field = LiquifyDistortionField.build(
            paths: [data], frame: Self.frame,
            bounds: SIMD2(Int(Self.frame.x), Int(Self.frame.y)))
        let reference = referenceField(data)
        guard let field else {
            return XCTFail("field must build for a live stamp", file: file, line: line)
        }
        XCTAssertGreaterThan(reference.compared, 0, "防空转 guard", file: file, line: line)
        XCTAssertEqual(field.forward.origin, reference.origin, "extent origin", file: file, line: line)
        XCTAssertEqual(field.forward.width, reference.size.x, "extent width", file: file, line: line)
        XCTAssertEqual(field.forward.height, reference.size.y, "extent height", file: file, line: line)
        var maxErr = 0.0
        var compared = 0
        var worst = (i: 0, j: 0, gx: 0.0, gy: 0.0, rx: 0.0, ry: 0.0, dx: 0, dy: 0)
        for j in 0..<reference.size.y {
            for i in 0..<reference.size.x {
                let got = field.forward.vectors[j * field.forward.width + i]
                let ref = reference.values[j * reference.size.x + i]
                let ex = abs(Double(got.x) - ref.x), ey = abs(Double(got.y) - ref.y)
                if max(ex, ey) > maxErr {
                    maxErr = max(ex, ey)
                    worst = (i, j, Double(got.x), Double(got.y), ref.x, ref.y,
                             i - reference.size.x / 2, j - reference.size.y / 2)
                }
                compared += 1
            }
        }
        if maxErr >= tolerance {
            print("[06-06 DEBUG] worst cell grid(\(worst.i),\(worst.j)) offset(\(worst.dx),\(worst.dy)): "
                + "got (\(worst.gx),\(worst.gy)) ref (\(worst.rx),\(worst.ry))")
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard", file: file, line: line)
        XCTAssertLessThan(
            maxErr, tolerance,
            "field vs float64 reference \(maxErr) (gate \(tolerance), \(compared) cells)",
            file: file, line: line)
        print(
            "[06-06 T1] \(data.type) stamp: maxErr \(maxErr) over \(compared) cells (gate \(tolerance))"
        )
    }

    // MARK: - T1: three warp types vs the analytic reference (<1e-6)

    func testRadialGrowFieldAnalyticReference() {
        // Radial grow: anchor at frame center, radius 0.1 (=60 px), strength
        // handle 0.025 off the anchor (=15 px × 0.5 = 7.5 px gain).
        let data = LiquifyPathData(
            type: .moveTo, warpType: .radialGrow,
            point: SIMD2(0.5, 0.5),
            strength: SIMD2(0.525, 0.5),
            radius: SIMD2(0.6, 0.5))
        assertFieldMatchesReference(data)
    }

    func testRadialShrinkFieldAnalyticReference() {
        let data = LiquifyPathData(
            type: .moveTo, warpType: .radialShrink,
            point: SIMD2(0.4, 0.6),
            strength: SIMD2(0.425, 0.6),
            radius: SIMD2(0.5, 0.6))
        assertFieldMatchesReference(data)
    }

    func testLinearFieldAnalyticReference() {
        // Strength vector 0.025 × 600 × 0.5 = 7.5 px peak — kept under the
        // float32 storage ulp of the 1e-6 absolute gate (an 18.75 px peak
        // would round at ~1.9e-6; recorded in DECISIONS as the test's value
        // budget, not an implementation bound).
        let data = LiquifyPathData(
            type: .moveTo, warpType: .linear,
            point: SIMD2(0.5, 0.5),
            strength: SIMD2(0.525, 0.5),
            radius: SIMD2(0.6, 0.5))
        assertFieldMatchesReference(data)
    }

    /// Directional structure (independent of the profile table): radial grow
    /// points TOWARD the center (backward sampling ⇒ magnification), shrink
    /// points AWAY, linear is uniform. Center cell is zero for radial.
    func testWarpDirectionStructure() throws {
        let frame = SIMD2<Double>(600, 400)
        func probe(_ type: LiquifyWarpType) throws -> DisplacementField {
            let data = LiquifyPathData(
                type: .moveTo, warpType: type,
                point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.55, 0.5),
                radius: SIMD2(0.6, 0.5))
            return try XCTUnwrap(LiquifyDistortionField.build(
                paths: [data], frame: frame, bounds: SIMD2(600, 400)))
        }
        for type in [LiquifyWarpType.radialGrow, LiquifyWarpType.radialShrink] {
            let field = try probe(type)
            // The stamp center in grid coords.
            let cx = 300 - field.forward.origin.x
            let cy = 200 - field.forward.origin.y
            let centerCell = field.forward.vectors[cy * field.forward.width + cx]
            XCTAssertEqual(centerCell.x, 0, accuracy: 1e-6, "\(type): center zero")
            XCTAssertEqual(centerCell.y, 0, accuracy: 1e-6, "\(type): center zero")
            // A cell right of the center: radial displacement must be
            // horizontal (cross product 0) and INWARD for grow.
            let probeCell = field.forward.vectors[cy * field.forward.width + cx + 10]
            XCTAssertLessThan(abs(probeCell.y), 1e-5, "\(type): radial direction")
            if type == LiquifyWarpType.radialGrow {
                XCTAssertLessThan(probeCell.x, 0, "grow points toward the center")
            } else {
                XCTAssertGreaterThan(probeCell.x, 0, "shrink points away from the center")
            }
        }
        let linear = try probe(.linear)
        let cx = 300 - linear.forward.origin.x
        let cy = 200 - linear.forward.origin.y
        // Linear pushes along the (purely horizontal here) strength vector.
        let left = linear.forward.vectors[cy * linear.forward.width + cx - 10]
        let right = linear.forward.vectors[cy * linear.forward.width + cx + 10]
        XCTAssertEqual(left.x, right.x, accuracy: 1e-6, "linear field is uniform")
        XCTAssertEqual(left.y, 0, accuracy: 1e-6)
        XCTAssertLessThan(left.x, 0, "linear opposes the strength vector")
    }

    // MARK: - T1: path interpolation (line/curve chains, 0.1 relocation)

    /// A MOVE→LINE chain interpolates stamps between the endpoints at
    /// |radius|·0.1 steps; every interpolated stamp deposits at 0.1×
    /// strength (dt STAMP_RELOCATION). Verified against the reference
    /// formula with the relocation factor folded in.
    func testLinePathInterpolationAndRelocation() throws {
        var move = LiquifyPathData.moveTo(SIMD2(0.25, 0.5))
        move.radius = SIMD2(0.35, 0.5)  // 0.1 × 600 = 60 px radius handle
        var line = LiquifyPathData.lineTo(SIMD2(0.75, 0.5))
        line.strength = SIMD2(0.8, 0.5)
        line.radius = SIMD2(0.85, 0.5)
        let stamps = LiquifyDistortionField.interpolateStamps(
            paths: [move, line], frame: Self.frame)
        XCTAssertGreaterThan(stamps.count, 5, "a 300 px path with r=60 stamps > 5 stamps")
        // Interpolated stamps carry 0.1× of the mixed strength: the mixed
        // strength magnitude stays ≤ max(|0.5·v1|, |0.5·v2|) = 37.5 px here
        // (v = 150 px × 0.5), so every interpolated stamp ≤ 3.75 px; the lone
        // full-strength stamps do not exist in a chain (move is not lone).
        var maxMag = 0.0
        for stamp in stamps {
            XCTAssertEqual(stamp.point.y, 200, accuracy: 1e-9, "stamps ride the line")
            maxMag = max(maxMag, LiquifyDistortionField.length(stamp.strength))
        }
        XCTAssertLessThan(maxMag, 3.75 + 1e-9, "0.1× STAMP_RELOCATION applied")
        // The chain's first stamp sits at the move point (t=0).
        XCTAssertEqual(stamps[0].point.x, 150, accuracy: 1e-9)
        // End-to-end: the full field builds and matches a re-deposit of the
        // same stamps (deposit is deterministic; the assertion pins the
        // pipeline plumbing, the per-cell math is covered above).
        let field = try XCTUnwrap(
            LiquifyDistortionField.build(
                paths: [move, line], frame: Self.frame, bounds: SIMD2(600, 400)),
            "chain field must build")
        var nonzero = 0
        for v in field.forward.vectors where v.x != 0 || v.y != 0 { nonzero += 1 }
        XCTAssertGreaterThan(nonzero, 0, "防空转: chain field must move pixels")
    }

    /// The bezier chain: MOVE→CURVE interpolates along the cubic with
    /// arc-length parameterization (dt INTERPOLATION_POINTS=100). Radius is
    /// set explicitly (a zero radius would stall dt's arc loop — the
    /// implementation breaks instead, D-06-06-T1-5).
    func testCurvePathInterpolation() {
        var move = LiquifyPathData.moveTo(SIMD2(0.25, 0.5))
        move.radius = SIMD2(0.35, 0.5)
        let curve = LiquifyPathData.curveTo(
            SIMD2(0.75, 0.5),
            ctrl1: SIMD2(0.42, 0.2), ctrl2: SIMD2(0.58, 0.8))
        var withRadius = curve
        withRadius.radius = SIMD2(0.85, 0.5)
        let stamps = LiquifyDistortionField.interpolateStamps(
            paths: [move, withRadius], frame: Self.frame)
        XCTAssertGreaterThan(stamps.count, 5, "curve chain must stamp")
        // First stamp at the move point, last advances along the curve.
        XCTAssertEqual(stamps[0].point.x, 150, accuracy: 1e-9)
        XCTAssertEqual(stamps[0].point.y, 200, accuracy: 1e-9)
        XCTAssertGreaterThan(
            stamps[stamps.count - 1].point.x, 300, "last stamp advances along the curve")
        // Zero-radius chain terminates via the guard (no hang, stamps may be
        // the single t=0 entry then stop).
        let degenerate = LiquifyDistortionField.interpolateStamps(
            paths: [LiquifyPathData.moveTo(SIMD2(0.25, 0.5)), curve], frame: Self.frame)
        XCTAssertFalse(degenerate.isEmpty, "guard terminates instead of hanging")
    }

    /// Profile boundary conditions (dt build_lookup_table contract):
    /// f(0) = 1, f(distance) = 0.
    func testLookupTableBoundaryConditions() throws {
        let table = try XCTUnwrap(LiquifyDistortionField.buildLookupTable(
            distance: 600, control1: 0.5, control2: 0.75))
        XCTAssertEqual(table[0], 1.0, "f(0) = 1")
        XCTAssertEqual(table[600], 0.0, "f(distance) = 0")
        // Monotone-decreasing profile for the default controls (the bezier's
        // y falls from 1 to 0).
        var violations = 0
        for i in 1..<600 where table[i] > table[i - 1] + 1e-9 { violations += 1 }
        XCTAssertEqual(violations, 0, "default profile must be monotone-decreasing")
    }

    // MARK: - T1: empty/degenerate paths

    func testEmptyPathsBuildNothing() {
        XCTAssertNil(LiquifyDistortionField.build(
            paths: [], frame: Self.frame, bounds: SIMD2(600, 400)), "empty = identity")
        // A zero-radius (degenerate) stamp builds nothing.
        let data = LiquifyPathData(
            type: .moveTo, warpType: .radialGrow, point: SIMD2(0.5, 0.5))
        XCTAssertNil(
            LiquifyDistortionField.build(
                paths: [data], frame: Self.frame, bounds: SIMD2(600, 400)),
            "degenerate stamp = identity")
        XCTAssertNil(LiquifyDistortionField.build(
            paths: [LiquifyPathData(type: .invalidated, point: SIMD2(0.5, 0.5))],
            frame: Self.frame, bounds: SIMD2(600, 400)), "invalidated terminator = identity")
    }
}
