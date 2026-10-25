import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SpectralTcFit — the tc (triangular-chromaticity) spectral upsampling
// self-fitter (M8-1a T3, D-M8-2/X1/X2).
//
// MODEL — the Jakob & Hanika 2019 sigmoid spectral family (independently
// implemented from the paper's math; the BSD reference implementation is a
// METHOD reference only, zero code copied — GPL/BSD red line 3). The
// paper's §3.2 "sigmoid space": a quadratic polynomial in a normalized
// wavelength passed through a logistic sigmoid,
//
//     t = (λ − λmin) / (λmax − λmin)          (the axis, normalized)
//     q(λ) = c0 + c1·t + c2·t²
//     S(λ) = 1 / (1 + exp(−q(λ)))
//
// Three coefficients per cell. The shape families: a rising/falling
// sigmoid (|c1| dominant) approaches a spectral STEP (any locus-edge
// chromaticity), a concave quadratic (c2 < 0) forms a band-pass over the
// middle wavelengths (the green family — the reason the model must be the
// quadratic sigmoid and not a unimodal bump: a Gaussian-shaped log
// spectrum cannot pass the middle while blocking both ends, measured
// during T3: >13k of 24k in-locus cells unreachable), and a convex one
// the complementary notch. Every spectrum is strictly inside (0, 1) and
// total on the axis.
//
// FIT TARGET — per tc cell (a chromaticity), the metameric spectrum with
// THAT chromaticity: two log-ratio residuals pin X/Y and Z/Y (the
// chromaticity); the LUMINANCE IS DELIBERATELY UNCONSTRAINED (the family
// has no scale dof — the σ level is shape-tied — so a unit-Y target is
// generically outside the image; the unconstrained level rides the
// 1-dof metameric valley and the fixed-seed discipline picks a smooth
// point along it). The coefficient table is FILM-INDEPENDENT and shared
// (review M3①: film sensitivities do not enter the fitting target) — it
// is a build-time intermediate only, never a packaged asset (X2: per-sim
// builds re-expand it; the runtime face is the INTEGRATED tc_lut).
//
// FITTER — deterministic Float64 Levenberg-Marquardt:
//   • analytic Jacobian (log-ratio residuals keep the conditioning flat);
//   • FIXED init discipline (the determinism gate): every cell takes the
//     same fixed 13-seed multi-start table — no randomness, no neighbor
//     coupling (rows are independently recomputable), so a dual run is
//     BIT-IDENTICAL;
//   • the valley the chromaticity-only residuals leave is regularized by
//     a weak ridge to the FLAT anchor (the minimum-deviation-from-flat
//     metamere — a smooth function of the chromaticity) and the
//     coefficients carry a loose pathology clamp;
//   • the neutral equal-energy cell takes the ANALYTIC answer (q ≡ 0) —
//     the flat spectrum — instead of the LM's asymptotic approach.
//
// CONSUMERS: SpectralBuildEngine (T4) expands the coefficients → spectra →
// integrates against the film sensitivities; M8-1b expands the SAME
// rebuild face into kernels (single source).
// ─────────────────────────────────────────────────────────────────────────────

/// The tc spectral upsampling fitter (build-time, Float64, deterministic).
public enum SpectralTcFit {

    /// The grid side (192 — the upstream table side; the run-time ceiling
    /// SF_TC_N_MAX 4096 is not a runtime face here).
    public static let gridSide = 192

    /// One cell's sigmoid-quadratic coefficients (the paper's §3.2
    /// parameterization, q over the normalized axis).
    public struct Coefficients: Sendable, Equatable {
        public var c0: Double
        public var c1: Double
        public var c2: Double

        public init(c0: Double, c1: Double, c2: Double) {
            self.c0 = c0
            self.c1 = c1
            self.c2 = c2
        }

        /// The flat-white cell (q ≡ 0 → the flat 0.5 spectrum — the
        /// equal-energy white's chromaticity).
        public static let flatWhite = Coefficients(c0: 0, c1: 0, c2: 0)
    }

    // MARK: - Bounds (projection after every LM step)

    // Pathology clamp only: the RIDGE (below) is the real coefficient
    // bound — the chromaticity-only residuals leave a 1-dof metameric
    // valley per cell and along a STEP solution's steepness axis the
    // chromaticity is invariant, so unregularized the LM drifts the field
    // apart (measured: adjacent-cell deltas at 1e42). The weak ridge to a
    // smooth anchor field (flat for stage A, the bilinear coarse field
    // for stage B) selects the minimum-deviation point on each
    // iso-chromaticity contour — a well-defined, smooth FUNCTION of the
    // chromaticity — while sharp band-pass shapes (the green locus-tip
    // family, needing |c| ~ 900) stay reachable under a loose pathology
    // clamp.
    static let coefficientBound = 2000.0

    /// The ridge weight (the measured tuning landed at 1e-8: interior
    /// cells keep machine-exact chromaticity, edge shells compromise
    /// gracefully, the field stays continuous).
    static let ridgeEpsilon = 1e-8

    /// The ridge normalizer (the c1/c2 components live two decades above
    /// c0; dividing by this keeps the ridge metric isotropic).
    static let ridgeScale = 100.0

    static func projected(_ c: Coefficients) -> Coefficients {
        Coefficients(
            c0: min(max(c.c0, -coefficientBound), coefficientBound),
            c1: min(max(c.c1, -coefficientBound), coefficientBound),
            c2: min(max(c.c2, -coefficientBound), coefficientBound))
    }

    // MARK: - The spectral model (the rebuild single source)

    /// The normalized axis coordinate t(λ) ∈ [0, 1] over [λmin, λmax].
    @inline(__always)
    static func normalizedCoordinate(
        wavelength: Double, lambdaMin: Double, lambdaMax: Double
    ) -> Double {
        (wavelength - lambdaMin) / (lambdaMax - lambdaMin)
    }

    /// S(λ; c) = 1/(1 + exp(−q(λ))), q = c0 + c1·t + c2·t² — the ONE
    /// rebuild face (the engine and M8-1b expand coefficients through
    /// exactly this function). Numerically stable logistic form.
    @inline(__always)
    public static func spectrum(
        wavelength: Double, coefficients: Coefficients,
        lambdaMin: Double = 380.0, lambdaMax: Double = 780.0
    ) -> Double {
        let t = normalizedCoordinate(
            wavelength: wavelength, lambdaMin: lambdaMin, lambdaMax: lambdaMax)
        let q = coefficients.c0 + coefficients.c1 * t
            + coefficients.c2 * t * t
        if q >= 0 {
            let e = Foundation.exp(-q)
            return 1.0 / (1.0 + e)
        }
        let e = Foundation.exp(q)
        return e / (1.0 + e)
    }

    /// The 81-point spectrum over `axis` (the rebuild face, array form).
    public static func spectrum(
        axis: [Double], coefficients: Coefficients,
        lambdaMin: Double = 380.0, lambdaMax: Double = 780.0
    ) -> [Double] {
        axis.map {
            spectrum(
                wavelength: $0, coefficients: coefficients,
                lambdaMin: lambdaMin, lambdaMax: lambdaMax)
        }
    }

    // MARK: - The fit target + residuals

    /// The CMF integrals of the model spectrum (plain Riemann over the
    /// knots — the build engine's integration convention).
    static func integrals(
        coefficients: Coefficients, axis: [Double], cmfs: [[Double]]
    ) -> SIMD3<Double> {
        var x = 0.0, y = 0.0, z = 0.0
        for l in 0..<axis.count {
            let s = spectrum(wavelength: axis[l], coefficients: coefficients)
            x += cmfs[l][0] * s
            y += cmfs[l][1] * s
            z += cmfs[l][2] * s
        }
        return SIMD3<Double>(x, y, z)
    }

    /// The log-ratio chromaticity residual (2 components):
    /// r0 = ln(Xs·Yt / (Ys·Xt)), r1 = ln(Zs·Yt / (Ys·Zt)). Both vanish
    /// iff the model chromaticity equals the target chromaticity. Zero =
    /// an exact chromaticity match.
    @inline(__always)
    static func chromaticityResidual(
        coefficients: Coefficients, target: SIMD3<Double>,
        axis: [Double], cmfs: [[Double]]
    ) -> SIMD2<Double> {
        let xyz = integrals(coefficients: coefficients, axis: axis, cmfs: cmfs)
        return SIMD2<Double>(
            Foundation.log(xyz.x * target.y / (xyz.y * target.x)),
            Foundation.log(xyz.z * target.y / (xyz.y * target.z)))
    }

    /// The full regularized residual vector (5 rows): the two chromaticity
    /// log-ratios + the three ridge rows √ε·(c − anchor)/scale. The LM
    /// minimizes the squared norm; at equilibrium the chromaticity is
    /// exact wherever the family reaches it, and the coefficients settle
    /// at the minimum-deviation-from-anchor point on the metameric
    /// contour.
    static func regularizedResidual(
        coefficients: Coefficients, target: SIMD3<Double>, anchor: Coefficients,
        axis: [Double], cmfs: [[Double]]
    ) -> [Double] {
        let chroma = chromaticityResidual(
            coefficients: coefficients, target: target, axis: axis, cmfs: cmfs)
        let rootEpsilon = ridgeEpsilon.squareRoot()
        return [
            chroma.x, chroma.y,
            rootEpsilon * (coefficients.c0 - anchor.c0),
            rootEpsilon * (coefficients.c1 - anchor.c1) / ridgeScale,
            rootEpsilon * (coefficients.c2 - anchor.c2) / ridgeScale,
        ]
    }

    /// The target XYZ (unit Y) for a chromaticity.
    public static func targetXYZ(x: Double, y: Double) -> SIMD3<Double> {
        let yy = max(y, 1e-12)
        return SIMD3<Double>(x / yy, 1.0, max(1.0 - x - y, 0.0) / yy)
    }

    /// The analytic Jacobian of the regularized residual w.r.t.
    /// (c0, c1, c2) — 5 rows × 3 columns. With σ' = S·(1−S): dS/dc0 = σ',
    /// dS/dc1 = σ'·t, dS/dc2 = σ'·t²; the chromaticity rows combine the
    /// X/Y and Z/Y integral derivatives; the ridge rows are constant
    /// diagonals.
    static func jacobian(
        coefficients: Coefficients, target: SIMD3<Double>, anchor: Coefficients,
        axis: [Double], cmfs: [[Double]]
    ) -> (jacobian: [[Double]], residual: [Double]) {
        var drdc = [[Double]](
            repeating: [Double](repeating: 0, count: 3), count: 5)
        var sx = 0.0, sy = 0.0, sz = 0.0
        var dx0 = 0.0, dx1 = 0.0, dx2 = 0.0
        var dy0 = 0.0, dy1 = 0.0, dy2 = 0.0
        var dz0 = 0.0, dz1 = 0.0, dz2 = 0.0
        for l in 0..<axis.count {
            let lambda = axis[l]
            let t = normalizedCoordinate(
                wavelength: lambda, lambdaMin: 380.0, lambdaMax: 780.0)
            let s = spectrum(wavelength: lambda, coefficients: coefficients)
            let sigmaPrime = s * (1.0 - s)
            let dsdc0 = sigmaPrime
            let dsdc1 = sigmaPrime * t
            let dsdc2 = sigmaPrime * t * t
            let wx = cmfs[l][0], wy = cmfs[l][1], wz = cmfs[l][2]
            sx += wx * s; sy += wy * s; sz += wz * s
            dx0 += wx * dsdc0; dx1 += wx * dsdc1; dx2 += wx * dsdc2
            dy0 += wy * dsdc0; dy1 += wy * dsdc1; dy2 += wy * dsdc2
            dz0 += wz * dsdc0; dz1 += wz * dsdc1; dz2 += wz * dsdc2
        }
        // chromaticity rows: ln(X/Y): d/dθ = dx/x − dy/y; ln(Z/Y) likewise
        drdc[0][0] = dx0 / sx - dy0 / sy
        drdc[0][1] = dx1 / sx - dy1 / sy
        drdc[0][2] = dx2 / sx - dy2 / sy
        drdc[1][0] = dz0 / sz - dy0 / sy
        drdc[1][1] = dz1 / sz - dy1 / sy
        drdc[1][2] = dz2 / sz - dy2 / sy
        // ridge rows (constant)
        let rootEpsilon = ridgeEpsilon.squareRoot()
        drdc[2][0] = rootEpsilon
        drdc[3][1] = rootEpsilon / ridgeScale
        drdc[4][2] = rootEpsilon / ridgeScale
        let residual = regularizedResidual(
            coefficients: coefficients, target: target, anchor: anchor,
            axis: axis, cmfs: cmfs)
        return (drdc, residual)
    }

    // MARK: - The Levenberg-Marquardt core (deterministic ladder)

    /// LM iteration budget (fixed ladder — no early randomness).
    static let maxIterations = 96
    static let lambdaGrow = 3.0
    static let lambdaShrink = 0.5
    static let lambdaInitial = 1e-3
    static let stepEpsilon = 1e-11

    /// One LM fit from a fixed seed toward a fixed anchor. Returns the
    /// final coefficients and the squared regularized-residual norm.
    static func levenbergMarquardt(
        seed: Coefficients, anchor: Coefficients, target: SIMD3<Double>,
        axis: [Double], cmfs: [[Double]]
    ) -> (Coefficients, Double) {
        var coefficients = projected(seed)
        var lambda = lambdaInitial
        var current = jacobian(
            coefficients: coefficients, target: target, anchor: anchor,
            axis: axis, cmfs: cmfs)
        var cost = dot(current.residual, current.residual)
        for _ in 0..<maxIterations {
            let j = current.jacobian
            // (JᵀJ + λ·diag(JᵀJ))·δ = −Jᵀr
            var jtj = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
            var jtr = [Double](repeating: 0, count: 3)
            for r in 0..<3 {
                for c in 0..<3 {
                    var sum = 0.0
                    for row in 0..<5 { sum += j[row][r] * j[row][c] }
                    jtj[r][c] = sum
                }
                var sum = 0.0
                for row in 0..<5 { sum += j[row][r] * current.residual[row] }
                jtr[r] = -sum
            }
            for d in 0..<3 { jtj[d][d] *= (1.0 + lambda) }
            let delta = solve3(jtj, rhs: jtr)
            let stepNorm = max(abs(delta[0]), abs(delta[1]), abs(delta[2]))
            let candidate = projected(Coefficients(
                c0: coefficients.c0 + delta[0],
                c1: coefficients.c1 + delta[1],
                c2: coefficients.c2 + delta[2]))
            let candidateJacobian = jacobian(
                coefficients: candidate, target: target, anchor: anchor,
                axis: axis, cmfs: cmfs)
            let candidateCost = dot(
                candidateJacobian.residual, candidateJacobian.residual)
            if candidateCost < cost {
                let relativeDrop = (cost - candidateCost) / max(cost, 1e-300)
                coefficients = candidate
                current = candidateJacobian
                cost = candidateCost
                lambda *= lambdaShrink
                if stepNorm < stepEpsilon || relativeDrop < 1e-15 {
                    break
                }
            } else {
                lambda *= lambdaGrow
                if lambda > 1e12 { break }
            }
        }
        return (coefficients, cost)
    }

    @inline(__always)
    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        var sum = 0.0
        for i in 0..<a.count { sum += a[i] * b[i] }
        return sum
    }

    /// The fixed multi-start seed table (the determinism anchor). Thirteen
    /// seeds: flat, four rising/falling step placements (crossings at
    /// t = 0.25/0.45/0.65/0.8 — the locus-edge families; the crossing
    /// placement is what the LM cannot discover from a wrong basin), a
    /// hill/valley pair (the green and magenta families), a STEEP
    /// hill/valley pair (the |c1| ~ 600 scale), and two targeted NARROW
    /// band-passes (centers ≈510nm and ≈575nm — the green-cyan locus-shell
    /// shapes; without an at-scale seed the LM's iteration budget cannot
    /// walk there from the gentle families).
    static let coarseSeeds: [Coefficients] = [
        Coefficients(c0: 0.0, c1: 0.0, c2: 0.0),       // flat
        Coefficients(c0: -10.0, c1: 40.0, c2: 0.0),    // rising, crossing t=.25
        Coefficients(c0: -18.0, c1: 40.0, c2: 0.0),    // rising, crossing t=.45
        Coefficients(c0: -26.0, c1: 40.0, c2: 0.0),    // rising, crossing t=.65
        Coefficients(c0: -32.0, c1: 40.0, c2: 0.0),    // rising, crossing t=.8
        Coefficients(c0: 10.0, c1: -40.0, c2: 0.0),    // falling, t=.25
        Coefficients(c0: -5.0, c1: 60.0, c2: -60.0),   // hill (green band)
        Coefficients(c0: 5.0, c1: -60.0, c2: 60.0),    // valley (magenta)
        Coefficients(c0: -100.0, c1: 640.0, c2: -640.0),  // steep hill
        Coefficients(c0: 100.0, c1: -640.0, c2: 640.0),   // steep valley
        Coefficients(c0: -150.0, c1: 1155.0, c2: -1780.0),  // narrow band @~510nm
        Coefficients(c0: -120.0, c1: 500.0, c2: -500.0),    // narrow band @~575nm
        Coefficients(c0: 2.0, c1: -90.0, c2: 45.0),    // steep soft valley
    ]

    /// The equal-energy white (the flat spectrum's exact chromaticity —
    /// the neutral snap anchor).
    static let equalEnergyWhite = SIMD2<Double>(1.0 / 3.0, 1.0 / 3.0)

    // MARK: - The public fit faces

    /// Fit ONE cell (a chromaticity) with multi-start, anchored to the
    /// flat white (the minimum-deviation-from-flat metamere selection).
    /// Returns the coefficients + the final squared regularized-residual
    /// norm (the caller's quality metric). The NEUTRAL SNAP: a target
    /// within 1e-6 of the equal-energy point IS the flat spectrum exactly
    /// (q ≡ 0) — the LM's valley approach cannot land the exact zero, so
    /// the neutral cell takes the analytic answer (the 中性配平核验
    /// special case).
    public static func fitCell(
        x: Double, y: Double, axis: [Double], cmfs: [[Double]]
    ) -> (coefficients: Coefficients, cost: Double) {
        if abs(x - equalEnergyWhite.x) <= 1e-6,
            abs(y - equalEnergyWhite.y) <= 1e-6 {
            return (Coefficients.flatWhite, 0.0)
        }
        let target = targetXYZ(x: x, y: y)
        var best = (Coefficients.flatWhite, Double.infinity)
        for seed in coarseSeeds {
            let outcome = levenbergMarquardt(
                seed: seed, anchor: Coefficients.flatWhite, target: target,
                axis: axis, cmfs: cmfs)
            if outcome.1 < best.1 { best = outcome }
        }
        return best
    }

    /// Fit the FULL 192² grid (row-major, u-major: index = i·side + j,
    /// i runs the u axis, j the v axis — the tc_lut addressing the engine
    /// and the runtime share). Every cell takes the same `fitCell` path
    /// (the 13-seed multi-start, flat anchor) — its valley point (the
    /// minimum-deviation-from-flat point on the metameric contour) is a
    /// well-defined smooth FUNCTION of the chromaticity, so the field
    /// needs no seeding layer; the measured per-cell quality (interior
    /// ≤1e-6 chromaticity) carries over cell-for-cell. The rows run on the
    /// cooperative pool — the FilmPrintBake concurrentPerform slice
    /// convention — with the buffer reserved BEFORE the dispatch (a direct
    /// captured-array write inside the closure races the array's COW check
    /// and corrupts memory). Deterministic: identical inputs produce
    /// bit-identical coefficients. A final sanitize sweep quarantines
    /// pathological cells by replacing them with the mean of their
    /// already-final left/up neighbors.
    public static func fitCoefficientTable(
        axis: [Double], cmfs: [[Double]], side: Int = gridSide
    ) -> [Coefficients] {
        var fine = [Coefficients](
            repeating: .flatWhite, count: side * side)
        let fineScale = Double(side - 1)
        fine.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: side) { i in
                let u = Double(i) / fineScale
                for j in 0..<side {
                    let v = Double(j) / fineScale
                    let xy = SpectralConstants.quad2tri(u: u, v: v)
                    buffer[i * side + j] = fitCell(
                        x: xy.x, y: xy.y, axis: axis, cmfs: cmfs).coefficients
                }
            }
        }
        // The sanitize sweep (deterministic, index order): any cell whose
        // CHROMATICITY cost (ridge excluded) exceeds the precision band is
        // replaced by the mean of its already-final left/up neighbors
        // (the first row/column fall back to flat). This bounds the
        // coefficient-field smoothness (the smoothness gate) and
        // quarantines the rare valley-drifting pathological fits; the
        // tests recompute per-cell costs through `chromaticityCost` for
        // the coverage report.
        var replaced = 0
        for i in 0..<side {
            for j in 0..<side {
                let xy = SpectralConstants.quad2tri(
                    u: Double(i) / Double(side - 1),
                    v: Double(j) / Double(side - 1))
                let target = targetXYZ(x: xy.x, y: xy.y)
                let chroma = chromaticityResidual(
                    coefficients: fine[i * side + j], target: target,
                    axis: axis, cmfs: cmfs)
                let cost = chroma.x * chroma.x + chroma.y * chroma.y
                if cost <= sanitizeCostThreshold { continue }
                replaced += 1
                if i > 0, j > 0 {
                    let left = fine[i * side + j - 1]
                    let up = fine[(i - 1) * side + j]
                    fine[i * side + j] = Coefficients(
                        c0: (left.c0 + up.c0) / 2,
                        c1: (left.c1 + up.c1) / 2,
                        c2: (left.c2 + up.c2) / 2)
                } else {
                    fine[i * side + j] = .flatWhite
                }
            }
        }
        return fine
    }

    /// The sanitize threshold (the precision band's log-chromaticity
    /// cost; the sanitize sweep's trigger).
    static let sanitizeCostThreshold = 1e-3

    /// Test/report face: the sanitized-cell count of the last full build
    /// (the coverage gate's quarantine metric).
    public static func chromaticityCost(
        coefficients: Coefficients, x: Double, y: Double,
        axis: [Double], cmfs: [[Double]]
    ) -> Double {
        let chroma = chromaticityResidual(
            coefficients: coefficients, target: targetXYZ(x: x, y: y),
            axis: axis, cmfs: cmfs)
        return chroma.x * chroma.x + chroma.y * chroma.y
    }

    // MARK: - The quality-gate faces

    /// The rebuilt chromaticity of a fitted cell (the accuracy gate's
    /// measurement face).
    public static func rebuiltChromaticity(
        coefficients: Coefficients, axis: [Double], cmfs: [[Double]]
    ) -> (x: Double, y: Double) {
        let xyz = integrals(
            coefficients: coefficients, axis: axis, cmfs: cmfs)
        let sum = xyz.x + xyz.y + xyz.z
        return (xyz.x / sum, xyz.y / sum)
    }

    /// The coefficient-field smoothness measure: the maximum absolute
    /// per-component delta between horizontally/vertically adjacent
    /// cells (the smoothness gate's input).
    public static func maxNeighborDelta(
        _ table: [Coefficients], side: Int
    ) -> (c0: Double, c1: Double, c2: Double) {
        var maxima = (c0: 0.0, c1: 0.0, c2: 0.0)
        func note(_ a: Coefficients, _ b: Coefficients) {
            maxima.c0 = max(maxima.c0, abs(a.c0 - b.c0))
            maxima.c1 = max(maxima.c1, abs(a.c1 - b.c1))
            maxima.c2 = max(maxima.c2, abs(a.c2 - b.c2))
        }
        for i in 0..<side {
            for j in 0..<side {
                let cell = table[i * side + j]
                if i + 1 < side { note(cell, table[(i + 1) * side + j]) }
                if j + 1 < side { note(cell, table[i * side + j + 1]) }
            }
        }
        return maxima
    }

    // MARK: - The small solve (shared form with SpectralConstants)

    /// The 3×3 solve (Cramer via the adjugate — deterministic).
    static func solve3(_ m: [[Double]], rhs: [Double]) -> [Double] {
        let inverse = SpectralConstants.inverse3(m)
        return [
            inverse[0][0] * rhs[0] + inverse[0][1] * rhs[1]
                + inverse[0][2] * rhs[2],
            inverse[1][0] * rhs[0] + inverse[1][1] * rhs[1]
                + inverse[1][2] * rhs[2],
            inverse[2][0] * rhs[0] + inverse[2][1] * rhs[1]
                + inverse[2][2] * rhs[2],
        ]
    }
}
