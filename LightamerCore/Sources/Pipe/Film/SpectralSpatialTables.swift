import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SpectralSpatialTables (Plan M8-3+ T5) — the halation still baseline +
// the diffusion family bank (GPL-3.0 transcription, (C) darktable
// developers — dt spektrafilm `4d1fb6a95b`, verbatim values):
//
//   HALATION (src/common/spektra_sim.c:100-122 + src/common/
//   spektra_core.c:780-900):
//     still/strong-antihalation baseline — strength (0.05/0.015/0.0),
//     first σ 65 µm, scatter core (2.2/2.0/1.6), tail (9.3/9.7/9.1),
//     tail weights (0.78/0.65/0.67); tail amps
//     (0.1633/0.6496/0.1870) × radius ratios (0.536/1.5236/2.7684);
//     3 bounces, σ_k = σ_1·√k, decay (1/0.5/0.25)/1.75.
//   DIFFUSION (src/common/spektra_core.c:936-1000):
//     the four families (black-pro-mist/glimmerglass/pro-mist/
//     cinebloom) — core (2 comps) + halo (3 comps, warmth axis
//     (1.30/0.15/−1.45)) + bloom (4 comps, α-weighted); the
//     strength→p_s log2 table (breaks 0.125/0.25/0.5/1/2 → frac
//     0.10/0.20/0.35/0.55/0.75, family total_gain scaled, ≤ 0.99).
//
// The per-component exponential exp(−r/λ) rides the σ = λ√3 Gaussian
// proxy (the second-moment match — the upstream approximation, same
// here). pixel_um converts µm → px at the CONSUMER (the T5 leg).
// ─────────────────────────────────────────────────────────────────────────────

public enum SpectralSpatialTables {

    // MARK: - Halation (the still baseline)

    /// The scatter tail mixture (amps × radius ratios — verbatim).
    public static let tailAmps = [0.1633, 0.6496, 0.1870]
    public static let tailRatios = [0.5360, 1.5236, 2.7684]

    /// The still/strong-antihalation baseline (verbatim).
    public struct HalationBaseline: Sendable, Equatable {
        /// Per-channel strength at amount == 1.0.
        public let strength: SIMD3<Double>
        /// The first-bounce radius (µm).
        public let firstSigmaUm: Double
        /// The scatter core/tail radii (µm) + the tail weights.
        public let scatterCore: SIMD3<Double>
        public let scatterTail: SIMD3<Double>
        public let scatterTailWeight: SIMD3<Double>
    }

    public static let stillBaseline = HalationBaseline(
        strength: SIMD3<Double>(0.05, 0.015, 0.0),
        firstSigmaUm: 65.0,
        scatterCore: SIMD3<Double>(2.2, 2.0, 1.6),
        scatterTail: SIMD3<Double>(9.3, 9.7, 9.1),
        scatterTailWeight: SIMD3<Double>(0.78, 0.65, 0.67))

    /// The bounce weights (1/0.5/0.25)/1.75 (verbatim literals).
    public static let bounceDecay: [Float] =
        [1.0 / 1.75, 0.5 / 1.75, 0.25 / 1.75]

    /// The k-th bounce σ (σ_1 · √k — k = 1-based).
    public static func bounceSigma(
        firstSigma: Double, bounce: Int
    ) -> Double {
        firstSigma * (Double(bounce)).squareRoot()
    }

    // MARK: - Diffusion (the four families)

    /// One group's (λ µm, spread, n, α) row (verbatim).
    public struct DiffGroup: Sendable, Equatable {
        public let lambdaUm: Double
        public let spread: Double
        public let n: Int
        public let alpha: Double
    }

    /// One family (verbatim — core/halo/bloom groups + the three
    /// group weights + the total gain + the halo warmth base).
    public struct DiffFamily: Sendable, Equatable {
        public let id: String
        public let core: DiffGroup
        public let halo: DiffGroup
        public let bloom: DiffGroup
        public let weightCore: Double
        public let weightHalo: Double
        public let weightBloom: Double
        public let totalGain: Double
        public let haloWarmthBase: Double
    }

    /// The four families (the upstream index order:
    /// black-pro-mist/glimmerglass/pro-mist/cinebloom).
    public static let families: [DiffFamily] = [
        DiffFamily(
            id: "black-pro-mist",
            core: DiffGroup(lambdaUm: 16.0, spread: 1.5, n: 2, alpha: 0.0),
            halo: DiffGroup(lambdaUm: 95.0, spread: 2.0, n: 3, alpha: 0.0),
            bloom: DiffGroup(lambdaUm: 380.0, spread: 2.5, n: 4, alpha: 3.5),
            weightCore: 0.40, weightHalo: 0.47, weightBloom: 0.13,
            totalGain: 0.75, haloWarmthBase: 0.65),
        DiffFamily(
            id: "glimmerglass",
            core: DiffGroup(lambdaUm: 10.0, spread: 1.5, n: 2, alpha: 0.0),
            halo: DiffGroup(lambdaUm: 50.0, spread: 2.0, n: 3, alpha: 0.0),
            bloom: DiffGroup(lambdaUm: 260.0, spread: 2.5, n: 4, alpha: 3.2),
            weightCore: 0.60, weightHalo: 0.30, weightBloom: 0.10,
            totalGain: 0.65, haloWarmthBase: 0.0),
        DiffFamily(
            id: "pro-mist",
            core: DiffGroup(lambdaUm: 14.0, spread: 1.5, n: 2, alpha: 0.0),
            halo: DiffGroup(lambdaUm: 150.0, spread: 2.0, n: 3, alpha: 0.0),
            bloom: DiffGroup(lambdaUm: 650.0, spread: 2.5, n: 4, alpha: 2.9),
            weightCore: 0.28, weightHalo: 0.42, weightBloom: 0.30,
            totalGain: 1.05, haloWarmthBase: 0.40),
        DiffFamily(
            id: "cinebloom",
            core: DiffGroup(lambdaUm: 20.0, spread: 1.5, n: 2, alpha: 0.0),
            halo: DiffGroup(lambdaUm: 200.0, spread: 2.0, n: 3, alpha: 0.0),
            bloom: DiffGroup(lambdaUm: 1000.0, spread: 2.5, n: 4, alpha: 2.5),
            weightCore: 0.22, weightHalo: 0.30, weightBloom: 0.48,
            totalGain: 1.00, haloWarmthBase: 0.85),
    ]

    /// The strength→p_s table (verbatim breaks/fracs) + the warmth axis.
    public static let strengthBreaks = [0.125, 0.25, 0.5, 1.0, 2.0]
    public static let strengthFracs = [0.10, 0.20, 0.35, 0.55, 0.75]
    public static let haloWarmthAxis = [1.30, 0.15, -1.45]

    /// The family lookup by id (nil = unknown — the typed degrade).
    public static func family(id: String) -> DiffFamily? {
        families.first { $0.id == id }
    }

    /// The strength→p_s map (the log2-interpolated table × family
    /// gain, ≤ 0.99 — the upstream `sf_diff_strength_to_ps` verbatim,
    /// Double intermediates).
    public static func scatterFraction(
        strength: Double, family: DiffFamily
    ) -> Double {
        guard strength > 0 else { return 0.0 }
        let ls = log2(max(strength, 1e-6))
        let breaks = strengthBreaks
        let fracs = strengthFracs
        let base: Double
        if ls <= log2(breaks[0]) {
            base = fracs[0] * strength / breaks[0]
        } else if ls >= log2(breaks[4]) {
            base = fracs[4]
        } else {
            var found = fracs[4]
            for i in 0..<4 {
                let lo = log2(breaks[i]), hi = log2(breaks[i + 1])
                if ls >= lo && ls <= hi {
                    let t = (ls - lo) / (hi - lo)
                    found = fracs[i] + t * (fracs[i + 1] - fracs[i])
                    break
                }
            }
            base = found
        }
        return min(max(base * family.totalGain, 0.0), 0.99)
    }

    /// One bank component (the Gaussian proxy σ in µm + the weight).
    public struct BankComponent: Sendable, Equatable {
        /// The Gaussian σ (µm — λ√3, the moment match).
        public let sigmaUm: Double
        /// The component weight (the group weight folded).
        public let weight: Double
        /// The per-channel weights (halo warmth redistributed).
        public let channelWeight: SIMD3<Double>
    }

    /// Expand one group into (λ, weight) pairs (the upstream
    /// `sf_diff_expand` verbatim — the geometric λ progression +
    /// the bloom α power law).
    public static func expandGroup(
        _ group: DiffGroup, isBloom: Bool
    ) -> [(lambdaUm: Double, weight: Double)] {
        let n = min(max(group.n, 1), 4)
        guard n > 1, group.spread > 1.0 else {
            return [(group.lambdaUm, 1.0)]
        }
        let llo = log(group.lambdaUm / group.spread)
        let lhi = log(group.lambdaUm * group.spread)
        var pairs: [(Double, Double)] = []
        var sum = 0.0
        for k in 0..<n {
            let lam = exp(llo + (lhi - llo) * Double(k) / Double(n - 1))
            let weight = isBloom ? pow(lam, 2.0 - group.alpha) : 1.0
            pairs.append((lam, weight))
            sum += weight
        }
        return pairs.map { ($0.0, $0.1 / sum) }
    }

    /// The halo warmth redistribution (the upstream
    /// `sf_diff_halo_warmth` verbatim — the negative clamp + the
    /// tt/s renormalization make it energy-conserving).
    public static func haloWarmth(
        weights: [Double], warmth: Double
    ) -> [SIMD3<Double>] {
        let n = weights.count
        guard n >= 2 else {
            return weights.map {
                SIMD3<Double>($0, $0, $0)
            }
        }
        let clamped = min(max(warmth, -1.5), 1.5)
        var g = (0..<n).map { -1.0 + 2.0 * Double($0) / Double(n - 1) }
        var gmean = 0.0
        var total = 0.0
        for k in 0..<n {
            gmean += weights[k] * g[k]
            total += weights[k]
        }
        gmean /= total
        for k in 0..<n { g[k] -= gmean }
        // The per-channel rows (out[c][k] — the bank() consumer
        // transposes to per-component channel triples).
        var rows: [SIMD3<Double>] = []
        for c in 0..<3 {
            let axis = haloWarmthAxis[c]
            var raw = (0..<n).map { k in
                max(weights[k] * (1.0 + clamped * axis * g[k]), 0.0)
            }
            let s = raw.reduce(0, +)
            if s > 0 {
                raw = raw.map { $0 * (total / s) }
            } else {
                raw = weights
            }
            rows.append(SIMD3<Double>(
                raw[0], n > 1 ? raw[1] : 0, n > 2 ? raw[2] : 0))
        }
        return rows
    }

    /// The full bank for one family (≤ 11 components — core 2 + halo 3
    /// + bloom 4, the group weights folded, halo warmth at the user's
    /// warmth + the family's base; σ in µm).
    public static func bank(
        family: DiffFamily, warmth: Double = 0.0
    ) -> [BankComponent] {
        var out: [BankComponent] = []
        let core = expandGroup(family.core, isBloom: false)
        for (lam, weight) in core {
            let w = weight * family.weightCore
            out.append(BankComponent(
                sigmaUm: lam * 3.0.squareRoot(), weight: w,
                channelWeight: SIMD3<Double>(w, w, w)))
        }
        let halo = expandGroup(family.halo, isBloom: false)
        let redistributed = haloWarmth(
            weights: halo.map(\.1),
            warmth: warmth + family.haloWarmthBase)
        for (k, (lam, _)) in halo.enumerated() {
            let cw = redistributed.map { row in
                [row.x, row.y, row.z][k] * family.weightHalo
            }
            out.append(BankComponent(
                sigmaUm: lam * 3.0.squareRoot(),
                weight: (cw[0] + cw[1] + cw[2]) / 3.0,
                channelWeight: SIMD3<Double>(cw[0], cw[1], cw[2])))
        }
        let bloom = expandGroup(family.bloom, isBloom: true)
        for (lam, weight) in bloom {
            let w = weight * family.weightBloom
            out.append(BankComponent(
                sigmaUm: lam * 3.0.squareRoot(), weight: w,
                channelWeight: SIMD3<Double>(w, w, w)))
        }
        return out
    }
}
