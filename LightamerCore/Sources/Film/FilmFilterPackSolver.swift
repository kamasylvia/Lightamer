import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FilmFilterPackSolver — the bake-time neutral filter-pack closed-form
// solve (Plan M3-3-01 T5, KD-5).
//
// MODEL DOMAIN (this plan's reference chain; DECISIONS is the registration
// authority):
//   1. mid-gray scene (0.184 scene-linear, all channels) through the
//      NEGATIVE segment: D_c = interp(film.density_curves[c],
//      log10(0.184)) + base_c, where base_c is the E2-registered
//      three-point projection of base_density (650/550/450 nm nearest
//      neighbour — FilmProfile.baseDensityProjection). Identity crosstalk
//      (the 3×3 matrix arrives with the M3-3-02 kernel; this reference is
//      its CPU twin and gets the matrix back-filled then — the sanity
//      bands move with the model BY DESIGN).
//   2. The print receives log-exposure x_c = −D_c + gain_c (the negative
//      density attenuates; the dial constants restore per-channel
//      exposure). Filter gain (the E3-CORRECTED vectors): a Magenta dial
//      acts on GREEN only, a Yellow dial on BLUE only:
//         gain = k_m·s_m·[0,1,0] + k_y·s_y·[0,0,1]   (C fixed neutral 0)
//      with s_m = 0.0085 / s_y = 0.017 log10-exposure units per CC point
//      (the classic 2:1 dichroic dial ratio; calibrated at execution
//      against the vendored measurement table — DECISIONS §solver).
//   3. paperOut_c = interp(paper.density_curves[c], x_c).
//   Neutrality = the three paper outputs equal. R has no filter term →
//   constant anchor; G is strictly monotone in k_m and B in k_y → the
//   SEQUENTIAL two-step 1-D bounded bisection below (cleaner than a 2-D
//   joint bisection and equally deterministic; with a non-identity
//   crosstalk the two steps keep their monotonicity and this
//   initialization still converges — DECISIONS registers the 02
//   back-fill duty).
//
// DETERMINISM GATE (FSIM-01b, math half): Float64 channel math, fixed
// iteration budget + fixed epsilon (no adaptive stepping), no randomness,
// no initial-value dependence (pure bisection over the fixed [0, 100] CC
// domain), no shared mutable state — `solve` called twice on the same
// inputs is BIT-IDENTICAL (test-pinned).
//
// LICENSING: math only. The vendored measurement table
// (neutral_print_filters.json) is a SANITY-BAND reference for the two
// named material pairs — never a value-level replica (different
// head/paper/process domain; the table is TH-KG3, our solve domain is
// wider). No GPL code informed this file.
// ─────────────────────────────────────────────────────────────────────────────

/// The solved neutral filter pack, in CC points (0-100 dial domain).
public struct FilmFilterPackSolution: Equatable, Sendable {
    /// The Magenta dial's neutral value M0 (CC points).
    public let magentaCC: Double
    /// The Yellow dial's neutral value Y0 (CC points).
    public let yellowCC: Double

    public init(magentaCC: Double, yellowCC: Double) {
        self.magentaCC = magentaCC
        self.yellowCC = yellowCC
    }
}

public enum FilmFilterPackSolver {

    // MARK: - Registered constants (KD-5; DECISIONS §solver is the record)

    /// The mid-gray scene value the negative segment probes (the SpektraLab
    /// mid-gray probe's RGB-domain seat, printing.cpp's 0.184).
    public static let midGraySceneLinear = 0.184

    /// Magenta dial calibration: log10-exposure units per CC point
    /// (100 CC ≡ 0.85).
    public static let magentaExposurePerCC = 0.0085

    /// Yellow dial calibration: log10-exposure units per CC point
    /// (100 CC ≡ 1.7 — the 2:1 dichroic dial ratio vs Magenta).
    public static let yellowExposurePerCC = 0.017

    /// The CC-point dial domain (both dials).
    public static let ccLowerBound = 0.0
    public static let ccUpperBound = 100.0

    /// Fixed iteration budget of each bisection ladder (60 halvings of a
    /// 100-wide interval — far past Double64 resolution; the count is
    /// FIXED so the trajectory is input-determined).
    public static let maxIterations = 60

    /// Fixed convergence epsilon (interval width); the ladder stops early
    /// ONLY on this fixed threshold — no adaptive step, no randomness.
    public static let convergenceEpsilon = 1e-12

    // MARK: - The negative-segment reference (KD-5)

    /// The mid-gray negative-segment densities: log10(0.184) through the
    /// film's density curves (linear interpolation, edge-clamped) plus
    /// the E2-registered base-density projection constants. The CPU twin
    /// of the M3-3-02 negative-segment kernel — the crosstalk matrix is
    /// IDENTITY in this plan and gets back-filled when the kernel lands.
    public static func midGrayDensities(
        film: FilmProfile
    ) throws -> (r: Double, g: Double, b: Double) {
        let base = try film.baseDensityProjection()
        let x = Foundation.log10(midGraySceneLinear)
        return (
            r: curveValue(film, channel: 0, at: x) + base.r,
            g: curveValue(film, channel: 1, at: x) + base.g,
            b: curveValue(film, channel: 2, at: x) + base.b
        )
    }

    // MARK: - The solve (KD-5)

    /// The bake-time neutral pack (M0, Y0) for one film×paper pair: the
    /// sequential two-step 1-D bounded bisection —
    ///   k_m: paper_G(−f_G + k_m·s_m) = paper_R(−f_R)   (R = constant anchor)
    ///   k_y: paper_B(−f_B + k_y·s_y) = paper_G(−f_G + k_m*·s_m)
    /// Deterministic by construction (see the header). A dial whose
    /// residual never crosses zero inside [0, 100] clamps to the bound —
    /// the named sanity pairs converge strictly inside (test-pinned).
    public static func solveNeutralPack(
        film: FilmProfile, paper: FilmProfile
    ) throws -> FilmFilterPackSolution {
        let f = try midGrayDensities(film: film)

        // Step 1 — Magenta: equalize G against the R anchor.
        let anchor = paperCurveValue(paper, channel: 0, at: -f.r)
        let magenta = bisect { k in
            paperCurveValue(paper, channel: 1, at: -f.g + k * magentaExposurePerCC)
                - anchor
        }

        // Step 2 — Yellow: equalize B against the solved G output.
        let gOutput = paperCurveValue(
            paper, channel: 1, at: -f.g + magenta * magentaExposurePerCC)
        let yellow = bisect { k in
            paperCurveValue(paper, channel: 2, at: -f.b + k * yellowExposurePerCC)
                - gOutput
        }

        return FilmFilterPackSolution(magentaCC: magenta, yellowCC: yellow)
    }

    /// The E3 discrimination probe: re-solving with the PHYSICALLY WRONG
    /// Magenta vector `k_m·[0,1,1]` (magenta wrongly absorbing blue too —
    /// the pre-review typo). The G equation is unchanged (the M solution
    /// is invariant), but the B equation inherits the magenta term and the
    /// Y solution shifts far out of the sanity band — the discrimination
    /// self-check in FilmFilterPackSolverTests pins this so a regression
    /// to the wrong vector can never pass silently.
    public static func solveNeutralPackWrongMagentaVector(
        film: FilmProfile, paper: FilmProfile
    ) throws -> FilmFilterPackSolution {
        let f = try midGrayDensities(film: film)
        let anchor = paperCurveValue(paper, channel: 0, at: -f.r)
        let magenta = bisect { k in
            paperCurveValue(paper, channel: 1, at: -f.g + k * magentaExposurePerCC)
                - anchor
        }
        let gOutput = paperCurveValue(
            paper, channel: 1, at: -f.g + magenta * magentaExposurePerCC)
        // WRONG: the magenta dial also moves the blue exposure.
        let yellow = bisect { k in
            paperCurveValue(
                paper, channel: 2,
                at: -f.b + magenta * magentaExposurePerCC + k * yellowExposurePerCC)
                - gOutput
        }
        return FilmFilterPackSolution(magentaCC: magenta, yellowCC: yellow)
    }

    // MARK: - Internals (internal for the test suite's self-checks)

    /// The three paper outputs under a (M, Y) pack — the monotone-bracket
    /// self-check face (tests assert the bracketing and the solved
    /// residuals).
    static func paperOutputs(
        paper: FilmProfile, film: FilmProfile,
        magentaCC: Double, yellowCC: Double
    ) throws -> (r: Double, g: Double, b: Double) {
        let f = try midGrayDensities(film: film)
        return (
            r: paperCurveValue(paper, channel: 0, at: -f.r),
            g: paperCurveValue(
                paper, channel: 1, at: -f.g + magentaCC * magentaExposurePerCC),
            b: paperCurveValue(
                paper, channel: 2, at: -f.b + yellowCC * yellowExposurePerCC)
        )
    }

    /// The fixed-ladder bounded bisection over [ccLowerBound, ccUpperBound]
    /// (the residual must be ASCENDING in k for the returned root to be
    /// the neutrality point — both steps satisfy this by construction).
    static func bisect(_ residual: (Double) -> Double) -> Double {
        let lower = residual(ccLowerBound)
        let upper = residual(ccUpperBound)
        if lower >= 0 { return ccLowerBound }
        if upper <= 0 { return ccUpperBound }
        var lo = ccLowerBound
        var hi = ccUpperBound
        for _ in 0..<maxIterations {
            let mid = (lo + hi) / 2
            if residual(mid) < 0 {
                lo = mid
            } else {
                hi = mid
            }
            if hi - lo < convergenceEpsilon { break }
        }
        return (lo + hi) / 2
    }

    /// Linear interpolation over a profile curve (channel `channel` of
    /// density_curves against log_exposure), edge-clamped. Float32
    /// storage widened to Double BEFORE arithmetic (exact widening — the
    /// determinism gate survives the storage precision).
    static func curveValue(
        _ profile: FilmProfile, channel: Int, at x: Double
    ) -> Double {
        let logExposure = profile.logExposure
        let count = logExposure.count
        let first = Double(logExposure[0])
        let last = Double(logExposure[count - 1])
        if x <= first {
            return Double(profile.densityCurves[0][channel])
        }
        if x >= last {
            return Double(profile.densityCurves[count - 1][channel])
        }
        var lo = 0
        var hi = count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if Double(logExposure[mid]) <= x {
                lo = mid
            } else {
                hi = mid
            }
        }
        let a = Double(profile.densityCurves[lo][channel])
        let b = Double(profile.densityCurves[hi][channel])
        let xa = Double(logExposure[lo])
        let xb = Double(logExposure[hi])
        let t = (x - xa) / (xb - xa)
        return a + t * (b - a)
    }

    private static func paperCurveValue(
        _ profile: FilmProfile, channel: Int, at x: Double
    ) -> Double {
        curveValue(profile, channel: channel, at: x)
    }
}
