import Foundation

// ─────────────────────────────────────────────────────────────────────────
// FilmicSpline (Plan 03-06-T1, F0) — the CPU half of filmicrgb: dt's
// `dt_iop_filmic_rgb_compute_spline` (filmicrgb.c:2732-3046), the
// `_compute_output_power` autotuner (:2571-2581) and the log-domain norm
// bounds (`exp_tonemapping_v2(0/1, …)`, process_cl :2400-2401) —
// transliterated from `src/iop/filmicrgb.c` (tree dc58cf0ba1).
//
// STRUCTURE (the D-T1 sub-stage decomposition, RESEARCH §2.1): filmicrgb
// is "CPU spline derivation + per-pixel pipeline" — everything with a
// derivative lives here and is unit-testable against hand-computed
// vectors; the GPU kernel (FilmicRGBKernels.metal) consumes the published
// float32 coefficients verbatim.
//
// PRECISION: derived in Double (the spline fit matrices are double in dt
// too — gauss_solve over ORDER_3/ORDER_4), published float32 to the
// kernel. The Gaussian elimination is a standard partial-pivot solver —
// mathematically identical to dt's `gaussian_elimination.h`
// (column-major Späth Fortran port) for these small well-conditioned
// systems (cross-checked at 1e-12 in CPUDerivationTests).
//
// SCOPE (T0 checkpoint decisions, 03-06-DECISIONS.md):
//   - spline_version v1/v2/v3 derivations ALL implemented (T1 requires
//     the three params-path branches covered by tests); the module pins
//     v3 at runtime (dt's default).
//   - highlight reconstruction is OUT (F5 TODO): only the mask-kernel
//     params ride along.
// ─────────────────────────────────────────────────────────────────────────

public enum FilmicSpline {

    /// filmicrgb.c:71 — the display-range safety margin.
    public static let safetyMargin: Double = 0.01

    /// dt `dt_iop_filmicrgb_curve_type_t` (filmicrgb.c:105-110).
    public enum CurveType: Int, Codable, Hashable, CaseIterable, Sendable {
        case poly4 = 0    // "hard"
        case poly3 = 1    // "soft"
        case rational = 2 // "safe"
    }

    /// dt `dt_iop_filmicrgb_spline_version_type_t` (filmicrgb.c:123-128).
    public enum SplineVersion: Int, Codable, Hashable, CaseIterable, Sendable {
        case v1 = 0 // 2019 (buggy black/white display)
        case v2 = 1 // 2020 (fixed display targets)
        case v3 = 2 // 2021 (slope from contrast only) — dt default
    }

    /// The derived spline (dt `dt_iop_filmic_rgb_spline_t`): per-segment
    /// poly4 Horner coefficients M1..M5 (toe, shoulder, linear — index 0/1/2
    /// of each float4 lane, `.w` unused) + the linear-segment bounds.
    public struct Spline: Equatable, Sendable {
        /// Coefficient lane: [toe, shoulder, linear] (dt's float4 lanes 0/1/2).
        public struct Lane: Equatable, Sendable {
            public var toe: Float
            public var shoulder: Float
            public var linear: Float
            public init(toe: Float, shoulder: Float, linear: Float) {
                self.toe = toe
                self.shoulder = shoulder
                self.linear = linear
            }
        }
        public var M1: Lane
        public var M2: Lane
        public var M3: Lane
        public var M4: Lane
        public var M5: Lane
        /// Bounds of the latitude == linear part by design.
        public var latitudeMin: Float
        public var latitudeMax: Float
        /// The five control nodes (log-domain x, display-domain y).
        public var x: [Float]
        public var y: [Float]
        /// Curve types per segment [shadows/toe, highlights/shoulder].
        public var types: [CurveType]
        /// dt returns this from compute_spline (GUI contrast-clamp flag).
        public var contrastClamped: Bool
    }

    /// The scalar derivation trace for the CPUDerivationTests cross-check.
    public struct Trace: Equatable, Sendable {
        public var greyDisplay: Double
        public var dynamicRange: Double
        public var blackLog: Double
        public var greyLog: Double
        public var whiteLog: Double
        public var blackDisplay: Double
        public var whiteDisplay: Double
        public var toeLog: Double
        public var shoulderLog: Double
        public var toeDisplay: Double
        public var shoulderDisplay: Double
        public var contrast: Double
        public var linearIntercept: Double
    }

    // MARK: - Curve evaluation (the CPU reference for the F1 three-way)

    /// dt `filmic_spline` (filmic.cl:230-292 / filmicrgb.c:866-930) — the
    /// Horner/rational segment evaluation in Double. `x` is the log-encoded
    /// value; the lane tuples are (toe, shoulder, linear, _).
    public static func evaluate(
        _ x: Double, spline: Spline
    ) -> Double {
        let latMin = Double(spline.latitudeMin)
        let latMax = Double(spline.latitudeMax)
        let toeType = spline.types[0]
        let shoulderType = spline.types[1]

        if x < latMin {
            switch toeType {
            case .poly4:
                return horner4(
                    x, m1: Double(spline.M1.toe), m2: Double(spline.M2.toe), m3: Double(spline.M3.toe),
                    m4: Double(spline.M4.toe), m5: Double(spline.M5.toe)
                )
            case .poly3:
                return horner3(
                    x, m1: Double(spline.M1.toe), m2: Double(spline.M2.toe),
                    m3: Double(spline.M3.toe), m4: Double(spline.M4.toe)
                )
            case .rational:
                let xi = latMin - x
                let rat = xi * (xi * Double(spline.M2.toe) + 1.0)
                return Double(spline.M4.toe) - Double(spline.M1.toe) * rat / (rat + Double(spline.M3.toe))
            }
        } else if x > latMax {
            switch shoulderType {
            case .poly4:
                return horner4(
                    x, m1: Double(spline.M1.shoulder), m2: Double(spline.M2.shoulder), m3: Double(spline.M3.shoulder),
                    m4: Double(spline.M4.shoulder), m5: Double(spline.M5.shoulder)
                )
            case .poly3:
                return horner3(
                    x, m1: Double(spline.M1.shoulder), m2: Double(spline.M2.shoulder),
                    m3: Double(spline.M3.shoulder), m4: Double(spline.M4.shoulder)
                )
            case .rational:
                let xi = x - latMax
                let rat = xi * (xi * Double(spline.M2.shoulder) + 1.0)
                return Double(spline.M4.shoulder) + Double(spline.M1.shoulder) * rat / (rat + Double(spline.M3.shoulder))
            }
        } else {
            return Double(spline.M1.linear) + x * Double(spline.M2.linear)
        }
    }

    /// y = M1 + x·(M2 + x·(M3 + x·(M4 + x·M5))).
    static func horner4(_ x: Double, m1: Double, m2: Double, m3: Double, m4: Double, m5: Double) -> Double {
        m1 + x * (m2 + x * (m3 + x * (m4 + x * m5)))
    }

    /// y = M1 + x·(M2 + x·(M3 + x·M4)).
    static func horner3(_ x: Double, m1: Double, m2: Double, m3: Double, m4: Double) -> Double {
        m1 + x * (m2 + x * (m3 + x * m4))
    }

    // MARK: - dt helpers

    /// dt `log_tonemapping_v2_1ch` / CL `log_tonemapping_v2` scalar:
    /// clamp_simd((log2(x/grey) − black)/dynamic_range). IEEE fmin/fmax
    /// NaN semantics: fmin(NaN, 1) = 1 → fmax(1, 0) = 1 (dt's clamp_simd
    /// = fmaxf(fminf(x, 1), 0)).
    public static func logTonemapping(
        _ x: Double, grey: Double, black: Double, dynamicRange: Double
    ) -> Double {
        let v = (log2(x / grey) - black) / dynamicRange
        return clampSIMD(v)
    }

    /// dt `exp_tonemapping_v2` — the inverse of logTonemapping.
    public static func expTonemapping(
        _ x: Double, grey: Double, black: Double, dynamicRange: Double
    ) -> Double {
        grey * exp2(dynamicRange * x + black)
    }

    /// dt `clamp_simd` (dttypes.h): fmaxf(fminf(x, 1), 0) with IEEE NaN
    /// passthrough of fmin/fmax (fmin(NaN, 1) = 1).
    public static func clampSIMD(_ x: Double) -> Double {
        if x.isNaN { return 1.0 }
        return min(max(x, 0.0), 1.0)
    }

    // MARK: - _compute_output_power (filmicrgb.c:2571-2581)

    /// `output_power = log(grey_target/100) / log(−black_source /
    /// (white_source − black_source))`, clamped to the slider range [1, 10]
    /// (the param's $MIN/$MAX — dt reads them from introspection).
    public static func computeOutputPower(
        greyPointTarget: Double, blackPointSource: Double, whitePointSource: Double
    ) -> Double {
        let min: Double = 1.0
        let max: Double = 10.0
        let raw = log(greyPointTarget / 100.0)
            / log(-blackPointSource / (whitePointSource - blackPointSource))
        return Swift.min(Swift.max(raw, min), max)
    }

    // MARK: - norm bounds (process_cl filmicrgb.c:2399-2401)

    /// `norm_min/max = exp_tonemapping_v2(0/1, grey_source, black_source,
    /// dynamic_range)` — the log-encoding clamps for the norm.
    public static func normBounds(
        greySource: Double, blackSource: Double, dynamicRange: Double
    ) -> (min: Double, max: Double) {
        (
            expTonemapping(0.0, grey: greySource, black: blackSource, dynamicRange: dynamicRange),
            expTonemapping(1.0, grey: greySource, black: blackSource, dynamicRange: dynamicRange)
        )
    }

    // MARK: - compute_spline (filmicrgb.c:2732-3046)

    /// The full derivation. `params` mirrors the dt slider domain
    /// (percent units, EV sources) — see `FilmicRGBModule.Params`.
    public static func derive(
        greyPointSource: Double,
        blackPointSource: Double,
        whitePointSource: Double,
        securityFactor: Double,
        greyPointTarget: Double,
        blackPointTarget: Double,
        whitePointTarget: Double,
        outputPower: Double,
        latitude: Double,
        contrast: Double,
        balance: Double,
        shadows: CurveType,
        highlights: CurveType,
        splineVersion: SplineVersion,
        customGrey: Bool
    ) -> (spline: Spline, trace: Trace) {
        var clamping = false

        // grey_display (filmicrgb.c:2738-2750).
        let greyDisplay: Double
        if customGrey {
            greyDisplay = pow(
                Swift.min(Swift.max(greyPointTarget, blackPointTarget), whitePointTarget) / 100.0,
                1.0 / outputPower
            )
        } else {
            greyDisplay = pow(0.1845, 1.0 / outputPower)
        }

        let dynamicRange = whitePointSource - blackPointSource

        // Luminance after log encoding (:2756-2759).
        let blackLog = 0.0
        let greyLog = abs(blackPointSource) / dynamicRange
        let whiteLog = 1.0

        // Target luminance after the filmic curve (:2762-2782).
        let blackDisplay: Double
        let whiteDisplay: Double
        if splineVersion == .v1 {
            // The buggy version: no output-power folding.
            blackDisplay = Swift.min(Swift.max(blackPointTarget, 0.0), greyPointTarget) / 100.0
            whiteDisplay = Swift.max(whitePointTarget, greyPointTarget) / 100.0
        } else {
            blackDisplay = pow(
                Swift.min(Swift.max(blackPointTarget, 0.0), greyPointTarget) / 100.0,
                1.0 / outputPower
            )
            whiteDisplay = pow(
                Swift.max(whitePointTarget, greyPointTarget) / 100.0,
                1.0 / outputPower
            )
        }

        // Toe/shoulder nodes (:2784-2874).
        let balanceFraction = Swift.min(Swift.max(balance, -50.0), 50.0) / 100.0
        var toeLog: Double
        var shoulderLog: Double
        var toeDisplay: Double
        var shoulderDisplay: Double
        var contrast_: Double

        if splineVersion.rawValue < SplineVersion.v3.rawValue {
            let latitudeRange = Swift.min(Swift.max(latitude, 0.0), 100.0) / 100.0 * dynamicRange
            contrast_ = Swift.min(Swift.max(contrast, 1.00001), 6.0)

            toeLog = greyLog - latitudeRange / dynamicRange * abs(blackPointSource / dynamicRange)
            shoulderLog = greyLog + latitudeRange / dynamicRange * abs(whitePointSource / dynamicRange)

            let linearIntercept = greyDisplay - (contrast_ * greyLog)
            toeDisplay = toeLog * contrast_ + linearIntercept
            shoulderDisplay = shoulderLog * contrast_ + linearIntercept

            // Balance as a shift along the contrast slope.
            let norm = (contrast_ * contrast_ + 1.0).squareRoot()
            let coeff = -((2.0 * latitudeRange) / dynamicRange) * balanceFraction
            toeDisplay += coeff * contrast_ / norm
            shoulderDisplay += coeff * contrast_ / norm
            toeLog += coeff / norm
            shoulderLog += coeff / norm
        } else {
            let hardness = outputPower
            let latitudeFraction = Swift.min(Swift.max(latitude, 0.0), 100.0) / 100.0
            let slope = contrast * dynamicRange / 8.0
            var minContrast = 1.0
            minContrast = Swift.max(minContrast, (whiteDisplay - greyDisplay) / (whiteLog - greyLog))
            minContrast = Swift.max(minContrast, (greyDisplay - blackDisplay) / (greyLog - blackLog))
            minContrast += safetyMargin

            contrast_ = slope / (hardness * pow(greyDisplay, hardness - 1.0))
            let clampedContrast = Swift.min(Swift.max(contrast_, minContrast), 100.0)
            clamping = (clampedContrast != contrast_)
            contrast_ = clampedContrast

            let linearIntercept = greyDisplay - (contrast_ * greyLog)

            let xmin = (blackDisplay + safetyMargin * (whiteDisplay - blackDisplay) - linearIntercept) / contrast_
            let xmax = (whiteDisplay - safetyMargin * (whiteDisplay - blackDisplay) - linearIntercept) / contrast_

            toeLog = (1.0 - latitudeFraction) * greyLog + latitudeFraction * xmin
            shoulderLog = (1.0 - latitudeFraction) * greyLog + latitudeFraction * xmax

            let balanceCorrection = balanceFraction > 0.0
                ? 2.0 * balanceFraction * (shoulderLog - greyLog)
                : 2.0 * balanceFraction * (greyLog - toeLog)
            toeLog -= balanceCorrection
            shoulderLog -= balanceCorrection
            toeLog = Swift.max(toeLog, xmin)
            shoulderLog = Swift.min(shoulderLog, xmax)

            toeDisplay = toeLog * contrast_ + linearIntercept
            shoulderDisplay = shoulderLog * contrast_ + linearIntercept
        }

        // Build the curve from the nodes (:2884-2907).
        let x = [blackLog, toeLog, greyLog, shoulderLog, whiteLog]
        let y = [blackDisplay, toeDisplay, greyDisplay, shoulderDisplay, whiteDisplay]
        let latitudeMin = toeLog
        let latitudeMax = shoulderLog

        // Linear central segment (:2937-2941).
        var M1: [Double] = [0, 0, 0, 0]
        var M2: [Double] = [0, 0, 0, 0]
        var M3: [Double] = [0, 0, 0, 0]
        var M4: [Double] = [0, 0, 0, 0]
        var M5: [Double] = [0, 0, 0, 0]
        M2[2] = contrast_
        M1[2] = y[1] - M2[2] * x[1]

        // Toe (:2943-2986).
        switch shadows {
        case .poly4:
            // Rows (position at 0, derivative at 0, position at toe,
            // derivative at toe, second derivative at toe) against the
            // unknowns [x⁴, x³, x², x¹, x⁰].
            let tl = x[1]
            let a: [[Double]] = [
                [0, 0, 0, 0, 1],
                [0, 0, 0, 1, 0],
                [tl * tl * tl * tl, tl * tl * tl, tl * tl, tl, 1],
                [4 * tl * tl * tl, 3 * tl * tl, 2 * tl, 1, 0],
                [12 * tl * tl, 6 * tl, 2, 0, 0],
            ]
            let b: [Double] = [y[0], 0, y[1], M2[2], 0]
            let s = gaussSolve(a, b)
            M5[0] = s[0]; M4[0] = s[1]; M3[0] = s[2]; M2[0] = s[3]; M1[0] = s[4]
        case .poly3:
            let tl = x[1]
            let a: [[Double]] = [
                [0, 0, 0, 1],
                [tl * tl * tl, tl * tl, tl, 1],
                [3 * tl * tl, 2 * tl, 1, 0],
                [6 * tl, 2, 0, 0],
            ]
            let b: [Double] = [y[0], y[1], M2[2], 0]
            let s = gaussSolve(a, b)
            M5[0] = 0; M4[0] = s[0]; M3[0] = s[1]; M2[0] = s[2]; M1[0] = s[3]
        case .rational:
            // filmicrgb.c:2972-2985 — the closed form.
            let p1x = x[0], p1y = y[0]
            let p0x = x[1], p0y = y[1]
            let xx = p0x - p1x
            let yy = p0y - p1y
            let g = contrast_
            // dt: (sqrtf(sqf(x·g/y + 1) − 4) − 1) / (2x) — the −1 is part
            // of the closed form.
            let bq = g / (2.0 * yy) + (((xx * g / yy + 1.0) * (xx * g / yy + 1.0) - 4.0).squareRoot() - 1.0) / (2.0 * xx)
            let cq = yy / g * (bq * xx * xx + xx) / (bq * xx * xx + xx - (yy / g))
            M1[0] = cq * g
            M2[0] = bq
            M3[0] = cq
            M4[0] = y[1]
        }

        // Shoulder (:2988-3043).
        switch highlights {
        case .poly3:
            let sl = x[3]
            let a: [[Double]] = [
                [1, 1, 1, 1],
                [sl * sl * sl, sl * sl, sl, 1],
                [3 * sl * sl, 2 * sl, 1, 0],
                [6 * sl, 2, 0, 0],
            ]
            let b: [Double] = [y[4], y[3], M2[2], 0]
            let s = gaussSolve(a, b)
            M5[1] = 0; M4[1] = s[0]; M3[1] = s[1]; M2[1] = s[2]; M1[1] = s[3]
        case .poly4:
            let sl = x[3]
            let a: [[Double]] = [
                [1, 1, 1, 1, 1],
                [4, 3, 2, 1, 0],
                [sl * sl * sl * sl, sl * sl * sl, sl * sl, sl, 1],
                [4 * sl * sl * sl, 3 * sl * sl, 2 * sl, 1, 0],
                [12 * sl * sl, 6 * sl, 2, 0, 0],
            ]
            let b: [Double] = [y[4], 0, y[3], M2[2], 0]
            let s = gaussSolve(a, b)
            M5[1] = s[0]; M4[1] = s[1]; M3[1] = s[2]; M2[1] = s[3]; M1[1] = s[4]
        case .rational:
            // filmicrgb.c:3031-3042 (P1 = white node, P0 = shoulder node).
            let p1x = x[4], p1y = y[4]
            let p0x = x[3], p0y = y[3]
            let xx = p1x - p0x
            let yy = p1y - p0y
            let g = contrast_
            // dt: (sqrtf(sqf(x·g/y + 1) − 4) − 1) / (2x) — the −1 is part
            // of the closed form.
            let bq = g / (2.0 * yy) + (((xx * g / yy + 1.0) * (xx * g / yy + 1.0) - 4.0).squareRoot() - 1.0) / (2.0 * xx)
            let cq = yy / g * (bq * xx * xx + xx) / (bq * xx * xx + xx - (yy / g))
            M1[1] = cq * g
            M2[1] = bq
            M3[1] = cq
            M4[1] = y[3]
        }

        let spline = Spline(
            M1: Spline.Lane(toe: Float(M1[0]), shoulder: Float(M1[1]), linear: Float(M1[2])),
            M2: Spline.Lane(toe: Float(M2[0]), shoulder: Float(M2[1]), linear: Float(M2[2])),
            M3: Spline.Lane(toe: Float(M3[0]), shoulder: Float(M3[1]), linear: Float(M3[2])),
            M4: Spline.Lane(toe: Float(M4[0]), shoulder: Float(M4[1]), linear: Float(M4[2])),
            M5: Spline.Lane(toe: Float(M5[0]), shoulder: Float(M5[1]), linear: Float(M5[2])),
            latitudeMin: Float(latitudeMin),
            latitudeMax: Float(latitudeMax),
            x: x.map { Float($0) },
            y: y.map { Float($0) },
            types: [shadows, highlights],
            contrastClamped: clamping
        )
        let trace = Trace(
            greyDisplay: greyDisplay,
            dynamicRange: dynamicRange,
            blackLog: blackLog,
            greyLog: greyLog,
            whiteLog: whiteLog,
            blackDisplay: blackDisplay,
            whiteDisplay: whiteDisplay,
            toeLog: toeLog,
            shoulderLog: shoulderLog,
            toeDisplay: toeDisplay,
            shoulderDisplay: shoulderDisplay,
            contrast: contrast_,
            linearIntercept: greyDisplay - contrast_ * greyLog
        )
        return (spline, trace)
    }

    /// Shorthand wrapper on the module params (the commit-time entry).
    public static func derive(params p: FilmicRGBModule.Params) -> (spline: Spline, trace: Trace) {
        derive(
            greyPointSource: Double(p.greyPointSource),
            blackPointSource: Double(p.blackPointSource),
            whitePointSource: Double(p.whitePointSource),
            securityFactor: Double(p.securityFactor),
            greyPointTarget: Double(p.greyPointTarget),
            blackPointTarget: Double(p.blackPointTarget),
            whitePointTarget: Double(p.whitePointTarget),
            outputPower: Double(p.outputPower),
            latitude: Double(p.latitude),
            contrast: Double(p.contrast),
            balance: Double(p.balance),
            shadows: p.shadows,
            highlights: p.highlights,
            splineVersion: p.splineVersion,
            customGrey: p.customGrey
        )
    }

    // MARK: - Gaussian elimination (partial pivoting, Double)

    /// Row-major Gaussian elimination with partial pivoting — the same
    /// solution as dt's `gaussian_elimination.h` for these small
    /// well-conditioned systems (agreement checked at 1e-12).
    static func gaussSolve(_ a: [[Double]], _ b: [Double]) -> [Double] {
        let n = a.count
        var m = a
        var x = b
        for col in 0..<n {
            var pivot = col
            for row in (col + 1)..<n where abs(m[row][col]) > abs(m[pivot][col]) {
                pivot = row
            }
            if pivot != col {
                m.swapAt(pivot, col)
                x.swapAt(pivot, col)
            }
            for row in (col + 1)..<n {
                let f = m[row][col] / m[col][col]
                for k in col..<n { m[row][k] -= f * m[col][k] }
                x[row] -= f * x[col]
            }
        }
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = x[row]
            for k in (row + 1)..<n { sum -= m[row][k] * x[k] }
            x[row] = sum / m[row][row]
        }
        return x
    }
}
