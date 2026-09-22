import simd

// ─────────────────────────────────────────────────────────────────────────
// ColorZonesLUT (Plan 05-04-T2) — the CPU half of the colorzones iop
// (IOP-COLOR-05): the three V2-spline interpolators, the 0x10000-point
// table build per select channel, and the strength-folded commit.
//
// Darktable reference (tree dc58cf0ba1):
//   - `src/iop/colorzones.c:2871-2892`  V2 commit branch (no wrap nodes —
//     nodes verbatim + strength-folded y):
//       V2-nonperiodic for select L/C, V2-PERIODIC for select h
//       (`p->channel == DT_IOP_COLORZONES_h`, :2889-2891)
//   - `src/common/splines.h/.cpp`      V2 interpolators (the `interpol`
//     namespace: Catmull_Rom_spline / monotone_hermite_spline /
//     monotone_hermite_spline_variant / smooth_cubic_spline +
//     spline_base::operator() + CurveDataSampleV2/V2Periodic)
//   - `src/common/curve_tools.c:393-558` V1 interpolators (ported already
//     as ToneCurveLUT — the V2 comparison base)
//
// V2-vs-V1 VERDICT (plan-level decision point, full record in
// 05-04-DECISIONS.md D-05-04-T2-1): REUSE the ToneCurveLUT interpolators
// for the NONPERIODIC leg, parameterized by two deltas:
//   (a) MONOTONE_HERMITE V2 = the Fritsch–Carlson VARIANT
//       (`monotone_hermite_spline_variant`: G(S1,S2,h1,h2) weighted
//       harmonic tangents, splines.cpp:371-422), NOT V1's
//       `monotone_hermite_set` (arithmetic-mean + Fritsch–Carlson clamp,
//       curve_tools.c:393-452). CUBIC_SPLINE and CATMULL_ROM V2 tangents
//       are IDENTICAL to V1 (natural-spline tridiagonal, resp. central
//       differences — verified term-by-term against curve_tools.c).
//   (b) endpoint handling: V2 fills [0,firstX)/[lastX,1] with the
//       ENDPOINT VALUES (firstPointY/lastPointY, CurveDataSampleV2), same
//       as V1's flat fill — no difference.
//   (c) sampling: V2-nonperiodic indexes `i·res` with res = 1/(N−1)
//       (splines.cpp V2 body), V1 indexes the same `i·res` — identical
//       grid. V2 quantizes with round() to uint16 (kept dt-side only);
//       Lightamer stores raw Double (same deviation as ToneCurveLUT).
// The PERIODIC leg (select h) is NEW: wraparound tangents per type
// (Catmull-Rom / Fritsch–Carlson / G-variant / natural cyclic spline via
// the N×N Gauss solve) + wrap evaluation `fmod(x, period)` with the
// upper-bound segment search. y is UNCLAMPED in the periodic leg (dt
// passes infinity() y-limits — only the 0x10000 int cast clips).
//
// PERIODIC TYPE MAP (CurveDataSampleV2Periodic, splines.cpp:855-893):
//   CUBIC_SPLINE → smooth_cubic_spline, CATMULL_ROM → Catmull_Rom_spline,
//   MONOTONE_HERMITE → monotone_hermite_spline_variant (!! — the VARIANT,
//   not monotone_hermite_spline).
//
// All interpolation math uses only +−×÷√ (IEEE-deterministic), computed
// in Double — the synthesized float64 references (gen_fixtures.py)
// replicate the same op order.
// ─────────────────────────────────────────────────────────────────────────

public enum ColorZonesLUT {

    /// LUT resolution (dt `DT_IOP_COLORZONES_LUT_RES = 0x10000`).
    public static let resolution = 0x10000

    /// Max nodes per curve (dt `DT_IOP_COLORZONES_MAXNODES = 20`).
    public static let maxNodes = 20

    /// dt select-by channel (colorzones.c:59-64 raw values).
    public enum SelectChannel: Int, Codable, Hashable, Sendable, CaseIterable {
        case lightness = 0
        case chroma = 1
        case hue = 2
    }

    /// dt process mode (colorzones.c:47-51 raw values).
    public enum ProcessMode: Int, Codable, Hashable, Sendable {
        case smooth = 0
        case strong = 1
    }

    // MARK: - V2 tangent solvers

    /// V2 CUBIC_SPLINE nonperiodic tangents == V1 natural spline:
    /// delegation keeps one implementation (verdict (a)).
    public static func cubicTangents(x: [Double], y: [Double]) -> [Double]? {
        guard let ypp = ToneCurveLUT.cubicSplineSecondDerivatives(x: x, y: y) else {
            return nil
        }
        // Convert ypp → first derivatives (splines.cpp smooth init):
        //   c_i = Δy_i/Δx_i − Δx_i/6·(b[i+1] − b[i])
        //   dy_i = −Δx_i·b[i]/2 + c_i (last: dy[N−1] = c_{N−2}).
        let n = x.count
        var dy = [Double](repeating: 0, count: n)
        var cLast = 0.0
        for i in 0..<(n - 1) {
            let dx = x[i + 1] - x[i]
            let c = (y[i + 1] - y[i]) / dx - dx / 6.0 * (ypp[i + 1] - ypp[i])
            dy[i] = -dx * ypp[i] / 2.0 + c
            cLast = c
        }
        dy[n - 1] = cLast
        return dy
    }

    /// V2 CATMULL_ROM nonperiodic tangents == V1 central differences:
    /// delegation keeps one implementation (verdict (a)).
    public static func catmullRomTangents(x: [Double], y: [Double]) -> [Double]? {
        ToneCurveLUT.catmullRomTangents(x: x, y: y)
    }

    /// V2 MONOTONE_HERMITE nonperiodic = the Fritsch–Carlson VARIANT
    /// (`monotone_hermite_spline_variant::init` nonperiodic branch,
    /// splines.cpp:406-420): endpoint tangents = one-sided secants,
    /// interior = G(Δ−, Δ+, h−, h+) weighted harmonic mean; zero-crossing
    /// secants force dy = 0; near-zero secants (|Δ| < ε) zero the bracketing
    /// pair (mirrors V1's EPSILON handling with Double epsilon).
    public static func monotoneVariantTangents(x: [Double], y: [Double]) -> [Double]? {
        let n = x.count
        guard n >= 2 else { return nil }
        for i in 0..<(n - 1) where x[i + 1] <= x[i] { return nil }
        var h = [Double](repeating: 0, count: n - 1)
        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            h[i] = x[i + 1] - x[i]
            delta[i] = (y[i + 1] - y[i]) / h[i]
        }
        func g(_ s1: Double, _ s2: Double, _ h1: Double, _ h2: Double) -> Double {
            if s1 * s2 > 0 {
                let alpha = (h1 + 2.0 * h2) / (3.0 * (h1 + h2))
                return s1 * s2 / (alpha * s2 + (1.0 - alpha) * s1)
            }
            return 0
        }
        var dy = [Double](repeating: 0, count: n)
        dy[0] = delta[0]
        for i in 1..<(n - 1) {
            dy[i] = g(delta[i - 1], delta[i], h[i - 1], h[i])
        }
        dy[n - 1] = delta[n - 2]
        return dy
    }

    // MARK: - V2 periodic tangent solvers (select-h leg)

    /// Periodic CATMULL_ROM tangents (splines.cpp Catmull_Rom init,
    /// periodic branch): central differences across the wrap segment.
    public static func periodicCatmullRomTangents(x: [Double], y: [Double], period: Double = 1.0) -> [Double]? {
        let n = x.count
        guard n >= 1 else { return nil }
        if n == 1 { return [0] }
        for i in 0..<(n - 1) where x[i + 1] <= x[i] { return nil }
        var dy = [Double](repeating: 0, count: n)
        dy[0] = (y[1] - y[n - 1]) / (x[1] - x[n - 1] + period)
        for i in 1..<(n - 1) {
            dy[i] = (y[i + 1] - y[i - 1]) / (x[i + 1] - x[i - 1])
        }
        dy[n - 1] = (y[0] - y[n - 2]) / (x[0] - x[n - 2] + period)
        return dy
    }

    /// Periodic MONOTONE (VARIANT) tangents
    /// (`monotone_hermite_spline_variant::init` periodic branch,
    /// splines.cpp:390-404): wrap secant Delta[N−1] closes the loop.
    public static func periodicMonotoneVariantTangents(x: [Double], y: [Double], period: Double = 1.0) -> [Double]? {
        let n = x.count
        guard n >= 1 else { return nil }
        if n == 1 { return [0] }
        for i in 0..<(n - 1) where x[i + 1] <= x[i] { return nil }
        var h = [Double](repeating: 0, count: n)
        var delta = [Double](repeating: 0, count: n)
        for i in 0..<(n - 1) {
            h[i] = x[i + 1] - x[i]
            delta[i] = (y[i + 1] - y[i]) / (x[i + 1] - x[i])
        }
        h[n - 1] = x[0] - x[n - 1] + period
        delta[n - 1] = (y[0] - y[n - 1]) / (x[0] - x[n - 1] + period)
        func g(_ s1: Double, _ s2: Double, _ h1: Double, _ h2: Double) -> Double {
            if s1 * s2 > 0 {
                let alpha = (h1 + 2.0 * h2) / (3.0 * (h1 + h2))
                return s1 * s2 / (alpha * s2 + (1.0 - alpha) * s1)
            }
            return 0
        }
        var dy = [Double](repeating: 0, count: n)
        dy[0] = g(delta[n - 1], delta[0], h[n - 1], h[0])
        for i in 1..<n {
            dy[i] = g(delta[i - 1], delta[i], h[i - 1], h[i])
        }
        return dy
    }

    /// Periodic CUBIC (natural cyclic) tangents
    /// (`smooth_cubic_spline::init` periodic branch, splines.cpp:614-660):
    /// full N×N cyclic system solved by Gauss elimination (no pivoting —
    /// dt's `gauss_solve`; diagonal-dominant so no pivoting required).
    /// Returns the FIRST derivatives dy (converted from the solved second
    /// derivatives b via dt's c_i formula).
    public static func periodicCubicTangents(x: [Double], y: [Double], period: Double = 1.0) -> [Double]? {
        let n = x.count
        guard n >= 1 else { return nil }
        if n == 1 { return [0] }
        for i in 0..<(n - 1) where x[i + 1] <= x[i] { return nil }
        var dx = [Double](repeating: 0, count: n)
        var dyv = [Double](repeating: 0, count: n)
        for i in 0..<(n - 1) {
            dx[i] = x[i + 1] - x[i]
            dyv[i] = y[i + 1] - y[i]
        }
        dx[n - 1] = x[0] - x[n - 1] + period
        dyv[n - 1] = y[0] - y[n - 1]
        // Cyclic matrix A (dense N×N) + rhs b.
        var a = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        var b = [Double](repeating: 0, count: n)
        for i in 1..<(n - 1) {
            a[i][i - 1] = dx[i - 1] / 6.0
            a[i][i] = (dx[i - 1] + dx[i]) / 3.0
            a[i][i + 1] = dx[i] / 6.0
            b[i] = dyv[i] / dx[i] - dyv[i - 1] / dx[i - 1]
        }
        if n > 2 {
            a[0][0] = (dx[n - 1] + dx[0]) / 3.0
            a[n - 1][n - 1] = (dx[n - 2] + dx[n - 1]) / 3.0
            b[0] = dyv[0] / dx[0] - dyv[n - 1] / dx[n - 1]
            b[n - 1] = dyv[n - 1] / dx[n - 1] - dyv[n - 2] / dx[n - 2]
            a[0][1] = dx[0] / 6.0
            a[n - 1][n - 2] = dx[n - 2] / 6.0
            a[0][n - 1] = dx[n - 1] / 6.0
            a[n - 1][0] = dx[n - 1] / 6.0
        } else {
            // N == 2: dt's degenerate 2×2 (A(0,1) = A(1,0) =
            // (dx0+dx1)/6, diagonals (dx1+dx0)/3).
            a[0][0] = (dx[1] + dx[0]) / 3.0
            a[1][1] = (dx[0] + dx[1]) / 3.0
            a[0][1] = (dx[0] + dx[1]) / 6.0
            a[1][0] = (dx[0] + dx[1]) / 6.0
            b[0] = dyv[0] / dx[0] - dyv[1] / dx[1]
            b[1] = dyv[1] / dx[1] - dyv[0] / dx[0]
        }
        guard gaussSolve(a: &a, b: &b) else { return nil }
        // Second derivatives b solved → first derivatives (dt init tail).
        var dy = [Double](repeating: 0, count: n)
        var cLast = 0.0
        for i in 0..<(n - 1) {
            let c = dyv[i] / dx[i] - dx[i] / 6.0 * (b[i + 1] - b[i])
            dy[i] = -dx[i] * b[i] / 2.0 + c
            cLast = c
        }
        // dt periodic tail: points[N−1].dy = dx[N−2]·b[N−1]/2 + c_i
        // (c_i = the LAST segment's c — loop leaves cLast at i = N−2).
        dy[n - 1] = dx[n - 2] * b[n - 1] / 2.0 + cLast
        return dy
    }

    /// dt `gauss_solve` (LU without pivoting, splines.cpp:598-611).
    static func gaussSolve(a: inout [[Double]], b: inout [Double]) -> Bool {
        let n = b.count
        guard n >= 1 else { return false }
        // LU_factor (dense branch).
        for i in 0..<(n - 1) {
            let t = a[i][i]
            if t == 0 { return false }
            for k in (i + 1)..<n {
                a[k][i] /= t
                for j in (i + 1)..<n {
                    a[k][j] -= a[k][i] * a[i][j]
                }
            }
        }
        // LU_solve forward.
        for i in 0..<n {
            for k in 0..<i {
                b[i] -= a[i][k] * b[k]
            }
        }
        // LU_solve backward.
        for i in stride(from: n - 1, through: 0, by: -1) {
            for k in (i + 1)..<n {
                b[i] -= a[i][k] * b[k]
            }
            if a[i][i] == 0 { return false }
            b[i] /= a[i][i]
        }
        return true
    }

    // MARK: - Evaluation

    /// Nonperiodic Hermite evaluation = ToneCurveLUT.hermiteVal (same
    /// basis — verdict (a) reuse).
    public static func evaluateNonperiodic(
        x: [Double], y: [Double], tangents: [Double], xval: Double
    ) -> Double {
        ToneCurveLUT.hermiteVal(x: x, y: y, tangents: tangents, xval: xval)
    }

    /// Periodic evaluation (`spline_base::operator()` periodic branch,
    /// splines.cpp:123-140): fmod wrap + upper-bound segment search with
    /// wraparound (n1 = 0 when the segment crosses the period edge);
    /// y UNCLAMPED (infinity y-limits).
    public static func evaluatePeriodic(
        x: [Double], y: [Double], tangents: [Double], xval: Double, period: Double = 1.0
    ) -> Double {
        let n = x.count
        precondition(n >= 1)
        if n == 1 { return y[0] }
        var xv = xval.truncatingRemainder(dividingBy: period)
        if xv < x[0] { xv += period }
        // upper_bound(xv) − 1, wrapping to the last segment.
        var n0 = n - 1
        for i in 0..<n where xv < x[i] {
            n0 = i == 0 ? n - 1 : i - 1
            break
        }
        // If xv >= all knots, n0 stays n−1 (segment wraps to knot 0).
        let n1 = (n0 + 1) % n
        let h: Double
        if n1 > n0 {
            h = x[n1] - x[n0]
        } else {
            h = x[n1] - (x[n0] - period)
        }
        let dx = (xv - x[n0]) / h
        let dx2 = dx * dx
        let dx3 = dx2 * dx
        let h00 = 2.0 * dx3 - 3.0 * dx2 + 1.0
        let h10 = dx3 - 2.0 * dx2 + dx
        let h01 = -2.0 * dx3 + 3.0 * dx2
        let h11 = dx3 - dx2
        return h00 * y[n0] + h10 * h * tangents[n0]
            + h01 * y[n1] + h11 * h * tangents[n1]
    }

    // MARK: - Table build

    /// dt `strength()` fold (colorzones.c:421-425): y values are pulled
    /// toward 0.5 by strength/100 BEFORE spline sampling.
    public static func foldedY(_ y: Double, strength: Double) -> Double {
        y + (y - 0.5) * (strength / 100.0)
    }

    /// Build one curve's LUT. `periodic` selects the V2-periodic leg
    /// (select h) vs V2-nonperiodic (select L/C).
    ///
    /// Nonperiodic: flat endpoint fill + [0,1] clamp (dt box (0,0)-(1,1)).
    /// Periodic: wrap evaluation, y UNCLAMPED (dt infinity y-limits).
    /// < 2 nodes or non-increasing x degrades to identity (dt's
    /// interpolators fail and the curve stays fresh-identity).
    public static func buildTable(
        nodes: [(x: Double, y: Double)],
        type: ToneCurveLUT.CurveType,
        strength: Double,
        periodic: Bool
    ) -> [Double] {
        var table = [Double](repeating: 0, count: resolution)
        guard nodes.count >= 2 else {
            for k in 0..<resolution { table[k] = Double(k) / Double(resolution - 1) }
            return table
        }
        let xs = nodes.map(\.x)
        let ys = nodes.map { foldedY($0.y, strength: strength) }
        let tangents: [Double]?
        switch type {
        case .cubicSpline:
            tangents = periodic
                ? periodicCubicTangents(x: xs, y: ys)
                : cubicTangents(x: xs, y: ys)
        case .catmullRom:
            tangents = periodic
                ? periodicCatmullRomTangents(x: xs, y: ys)
                : catmullRomTangents(x: xs, y: ys)
        case .monotoneHermite:
            tangents = periodic
                ? periodicMonotoneVariantTangents(x: xs, y: ys)
                : monotoneVariantTangents(x: xs, y: ys)
        }
        guard let tangents else {
            for k in 0..<resolution { table[k] = Double(k) / Double(resolution - 1) }
            return table
        }
        // V1/V2 share the sampling grid: res = 1/(N−1), flat endpoint
        // values for the nonperiodic leg (verdict (b)).
        let res = 1.0 / Double(resolution - 1)
        let firstX = xs[0], lastX = xs[nodes.count - 1]
        let firstY = ys[0], lastY = ys[nodes.count - 1]
        for k in 0..<resolution {
            let xk = Double(k) * res
            if periodic {
                table[k] = evaluatePeriodic(x: xs, y: ys, tangents: tangents, xval: xk)
            } else if xk < firstX {
                table[k] = firstY
            } else if xk > lastX {
                table[k] = lastY
            } else {
                table[k] = min(max(
                    evaluateNonperiodic(x: xs, y: ys, tangents: tangents, xval: xk),
                    0.0), 1.0)
            }
        }
        return table
    }
}
