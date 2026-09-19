import Foundation

// ─────────────────────────────────────────────────────────────────────────
// CorrectionLUT (Plan 03-05-T1) — the CPU half of the tone equalizer iop
// (IOP-TONE-07): the 9 user EV bands → 8 radial-basis weights least-squares
// projection → the correction LUT the apply kernel looks up.
//
// Darktable reference (tree dc58cf0ba1, `src/iop/toneequal.c`):
//   - :131-158        CONTRAST_FULCRUM / gaussian_denom / centers tables
//                     (centers_ops = 8 control points evenly splitting the
//                     [-8; 0] EV range into 7 segments; centers_params = the
//                     9 integer band centers)
//   - :844-870        pixel_correction (the RBF evaluation, clamped
//                     [0.25, 4])
//   - :1225-1243      compute_correction_lut — 80001 entries
//                     (PIXEL_CHAN × LUT_RESOLUTION + 1; the plan text said
//                     10001 — erratum: the LUT spans 8 EV at 10k entries/EV,
//                     per the source)
//   - :1246-1275      get_channels_gains / get_channels_factors (EV →
//                     linear via exp2)
//   - :1380-1392      build_interpolation_matrix (9×8, row-major)
//   - :1382+/:289-358 pseudo_solve (choleski.h) — the least-squares
//                     projection of the 9 band gains onto the 8 RBF weights
//                     through the normal equations + Cholesky (FLOAT
//                     arithmetic throughout — verbatim Float port, the same
//                     rounding path dt takes; Double here would drift from
//                     dt's published weights)
//   - :1489-1512      compute_lut_correction (the UI curve sampling — the
//                     SAME interpolation the kernel LUT uses; one code path
//                     two consumers, plan T1 action 2)
//   - :1596-1651      commit_params (the exact derivation order this file's
//                     `ToneEqualDerived` mirrors)
//
// ERRATUM (source-checked, recorded for the plan): the plan's T1 said
// "9 estimators" for the luma masks (T2's surface — actually SEVEN,
// `DT_TONEEQ_LAST = 7`) and a "10001-point LUT" (actually 80001). The
// decision semantics (9 BANDS of user params, global multi-band, RBF
// approximation) are unchanged.
//
// NOTE on identity: all-zero band params are NOT an exact-identity LUT.
// The least-squares fit of the constant gain 1 through the 8 gaussians
// leaves a small ripple (|LUT − 1| up to ~1e-2 at the extreme bands) —
// dt behaves identically (same fit), so parity is unaffected; tests pin
// the ripple envelope, not an exact 1.0.
// ─────────────────────────────────────────────────────────────────────────

public enum CorrectionLUT {

    /// dt `CHANNELS` (:137) — the 9 user EV bands.
    public static let channelCount = 9
    /// dt `PIXEL_CHAN` (:138) — the 8 RBF control points.
    public static let controlPointCount = 8
    /// dt `LUT_RESOLUTION` (:139) — LUT entries per EV.
    public static let lutResolution = 10_000
    /// Total LUT entries: 8 EV × 10k/EV + 1 (dt `PIXEL_CHAN *
    /// LUT_RESOLUTION + 1`, the `dt_iop_toneequalizer_data_t` LUT size).
    public static let lutCount = controlPointCount * lutResolution + 1

    /// dt `DT_TONEEQ_MIN_EV` / `DT_TONEEQ_MAX_EV` (:742-743).
    public static let minEV: Float = -8.0
    public static let maxEV: Float = 0.0
    /// The user-set correction range clamp (apply + LUT build, :836/:1241).
    public static let correctionClampMin: Float = 0.25
    public static let correctionClampMax: Float = 4.0

    /// dt `centers_params` (:147-150) — the 9 band centers.
    public static let centersParams: [Float] = [-8, -7, -6, -5, -4, -3, -2, -1, 0]

    /// dt `centers_ops` (:141-146) — the 8 control points: [-8; 0] split
    /// into 7 even segments (float division exactly as written).
    public static let centersOps: [Float] = [
        -56.0 / 7.0, -48.0 / 7.0, -40.0 / 7.0, -32.0 / 7.0,
        -24.0 / 7.0, -16.0 / 7.0, -8.0 / 7.0, 0.0 / 7.0,
    ]

    // MARK: - RBF core (toneequal.c:751-768)

    /// dt `gaussian_denom` — the constant factor of exp(−r²/denom).
    @inline(__always)
    public static func gaussianDenom(sigma: Float) -> Float {
        2.0 * sigma * sigma
    }

    /// dt `gaussian_func` — unnormalized gaussian.
    @inline(__always)
    public static func gaussianFunc(radius: Float, denom: Float) -> Float {
        Foundation.exp(-radius * radius / denom)
    }

    /// dt `pixel_correction` (:844-870) — the correction at one exposure,
    /// from the 8 RBF WEIGHTS (the pseudo-solve output, NOT the user bands).
    public static func pixelCorrection(exposure: Float, weights: [Float], sigma: Float) -> Float {
        precondition(weights.count == controlPointCount)
        let denom = gaussianDenom(sigma: sigma)
        let expo = min(max(exposure, minEV), maxEV)
        var result: Float = 0
        for i in 0..<controlPointCount {
            result += gaussianFunc(radius: expo - centersOps[i], denom: denom) * weights[i]
        }
        return min(max(result, correctionClampMin), correctionClampMax)
    }

    /// dt `get_channels_gains` + `get_channels_factors` (:1246-1275) — the
    /// 9 user EV offsets → LINEAR gains (exp2), band order
    /// noise…speculars.
    public static func linearGains(bands: [Float]) -> [Float] {
        precondition(bands.count == channelCount)
        return bands.map { Foundation.exp2($0) }
    }

    // MARK: - Least-squares projection (build_interpolation_matrix + choleski.h)

    /// dt `build_interpolation_matrix` (:1380-1392) — the 9×8 row-major
    /// RBF design matrix A[i*8+j] = gaussian(centers_params[i] −
    /// centers_ops[j]).
    public static func interpolationMatrix(sigma: Float) -> [Float] {
        let denom = gaussianDenom(sigma: sigma)
        var a = [Float](repeating: 0, count: channelCount * controlPointCount)
        for i in 0..<channelCount {
            for j in 0..<controlPointCount {
                a[i * controlPointCount + j] =
                    gaussianFunc(radius: centersParams[i] - centersOps[j], denom: denom)
            }
        }
        return a
    }

    /// dt `_choleski_decompose` (choleski.h:107-158) — Float verbatim.
    static func choleskiDecompose(_ a: [Float], n: Int) -> [Float]? {
        if a[0] <= 0.0 { return nil }
        var l = [Float](repeating: 0, count: n * n)
        var valid = true
        for i in 0..<n {
            for j in 0..<(i + 1) {
                var sum: Float = 0
                for k in 0..<j {
                    sum += l[i * n + k] * l[j * n + k]
                }
                if i == j {
                    let temp = a[i * n + i] - sum
                    if temp < 0 {
                        valid = false
                        l[i * n + j] = Float.nan
                    } else {
                        l[i * n + j] = Foundation.sqrt(temp)
                    }
                } else {
                    let temp = l[j * n + j]
                    if temp == 0 {
                        valid = false
                        l[i * n + j] = Float.nan
                    } else {
                        l[i * n + j] = (a[i * n + j] - sum) / temp
                    }
                }
            }
        }
        return valid ? l : nil
    }

    /// dt `_triangular_descent` (choleski.h:164-197).
    static func triangularDescent(_ l: [Float], _ y: [Float], n: Int) -> [Float]? {
        var b = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var sum = y[i]
            for j in 0..<i {
                sum -= l[i * n + j] * b[j]
            }
            let temp = l[i * n + i]
            if temp != 0 {
                b[i] = sum / temp
            } else {
                return nil
            }
        }
        return b
    }

    /// dt `_triangular_ascent` (choleski.h:202-235).
    static func triangularAscent(_ l: [Float], _ b: [Float], n: Int) -> [Float]? {
        var x = [Float](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[i]
            for j in stride(from: n - 1, through: i + 1, by: -1) {
                sum -= l[j * n + i] * x[j]
            }
            let temp = l[i * n + i]
            if temp != 0 {
                x[i] = sum / temp
            } else {
                return nil
            }
        }
        return x
    }

    /// dt `_solve_hermitian` (choleski.h:241-283).
    static func solveHermitian(_ a: [Float], _ y: [Float], n: Int) -> [Float]? {
        guard let l = choleskiDecompose(a, n: n),
              let b = triangularDescent(l, y, n: n),
              let x = triangularAscent(l, b, n: n)
        else { return nil }
        return x
    }

    /// dt `pseudo_solve` (choleski.h:289-358) — least squares for the
    /// over-constrained m×n system through the normal equations
    /// (AᵀA)x = Aᵀy. Float arithmetic verbatim (see the header note).
    public static func pseudoSolve(_ a: [Float], _ y: [Float], m: Int, n: Int) -> [Float]? {
        precondition(a.count == m * n && y.count == m)
        if m < n || n < 2 || m < 2 { return nil }
        var aSquare = [Float](repeating: 0, count: n * n)
        var ySquare = [Float](repeating: 0, count: n)
        // _transpose_dot_matrix — lower triangle only.
        for i in 0..<n {
            for j in 0...i {
                var sum: Float = 0
                for k in 0..<m {
                    sum += a[k * n + i] * a[k * n + j]
                }
                aSquare[i * n + j] = sum
            }
        }
        // _transpose_dot_vector.
        for i in 0..<n {
            var sum: Float = 0
            for k in 0..<m {
                sum += a[k * n + i] * y[k]
            }
            ySquare[i] = sum
        }
        guard let x = solveHermitian(aSquare, ySquare, n: n) else { return nil }
        return x
    }

    /// The commit pipeline first half: 9 band EV offsets → 8 RBF weights
    /// (dt commit_params :1638-1648: linear gains → matrix → pseudo-solve).
    /// Returns nil when Cholesky fails (non-positive-definite — dt leaves
    /// the LUT stale; callers keep the previous weights).
    public static func weights(bands: [Float], sigma: Float) -> [Float]? {
        precondition(bands.count == channelCount)
        let a = interpolationMatrix(sigma: sigma)
        return pseudoSolve(a, linearGains(bands: bands), m: channelCount, n: controlPointCount)
    }

    // MARK: - The LUT (compute_correction_lut :1225-1243)

    /// dt `compute_correction_lut` — 80001 entries; entry j covers
    /// exposure = j/10000 − 8 EV; values clamped [0.25, 4].
    public static func lut(weights: [Float], sigma: Float) -> [Float] {
        precondition(weights.count == controlPointCount)
        let denom = gaussianDenom(sigma: sigma)
        var lut = [Float](repeating: 0, count: lutCount)
        for j in 0..<lutCount {
            let exposure = Float(j) / Float(lutResolution) + minEV
            var result: Float = 0
            for i in 0..<controlPointCount {
                result += gaussianFunc(radius: exposure - centersOps[i], denom: denom) * weights[i]
            }
            lut[j] = min(max(result, correctionClampMin), correctionClampMax)
        }
        return lut
    }

    /// The apply-kernel lookup semantics (toneequal.c:791-795): index =
    /// roundf((clamp(log2(luma), −8, 0) + 8) × 10000).
    @inline(__always)
    public static func lutIndex(luma: Float) -> Int {
        let exposure = min(max(log2f(luma), minEV), maxEV)
        return Int(((exposure - minEV) * Float(lutResolution)).rounded())
    }

    // MARK: - UI surface (one interpolation, two consumers)

    /// dt `compute_channels_factors` + `compute_channels_gains` — the
    /// gains at the 9 BAND centers (EV, log2) for the UI node handles.
    /// Same weights, same pixel_correction as the LUT.
    public static func channelGainsEV(weights: [Float], sigma: Float) -> [Float] {
        centersParams.map { log2f(pixelCorrection(exposure: $0, weights: weights, sigma: sigma)) }
    }

    /// dt `compute_lut_correction` (:1489-1512) — the UI graph curve:
    /// `samples` evenly spaced x in [−8, 0] EV, y = the correction gain
    /// (linear; the view applies dt's −log2/2 display mapping itself).
    /// The SAME interpolation as the kernel LUT — sample k equals
    /// `lut[round((x + 8) × 10000)]` up to the shared rounding.
    public static func uiCurveSamples(
        weights: [Float], sigma: Float, samples: Int
    ) -> [(ev: Float, gain: Float)] {
        precondition(samples >= 2)
        return (0..<samples).map { k in
            let ev = 8.0 * Float(k) / Float(samples - 1) + minEV
            return (ev, pixelCorrection(exposure: ev, weights: weights, sigma: sigma))
        }
    }
}
