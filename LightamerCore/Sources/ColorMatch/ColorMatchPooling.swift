import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// ColorMatchPooling (Plan M5-1-02 T2, KD-2; OQ-5) — the multi-reference
// statistics-level weighted pooling: N reference ColorMatchStats collapse
// into ONE pooled ColorMatchStats that feeds the solver family unchanged.
//
// FORMULAS (the adjudicated second-moment mixture):
//     μ_pool = Σ w_i μ_i
//     Σ_pool = Σ w_i (Σ_i + (μ_i − μ_pool)(μ_i − μ_pool)ᵀ)
// (the mixture covariance: within-reference scatter + the between-reference
// mean spread — algebraically Σ w_i·E[xxᵀ]_i − μ_pool μ_poolᵀ).
//
// ORDER NORMALIZATION (the determinism KEY, G1): the sum runs in the
// entries sorted by `statsHash` ASCENDING — the same reference SET in any
// list order produces BYTE-IDENTICAL pools (float addition is
// order-sensitive; the sort removes the input order from the identity).
// The pooled statsHash is recomputed by `ColorMatchStats.init`, so the
// same pool → same hash → the same solve-cache reference term (the KD-2
// cache-key face).
//
// HISTOGRAMS (the S2 arm): `h_pool[b] = round(Σ w_i·h_i[b])` — summed in
// the SAME sorted order, then rounded back to INTEGER counts (the P1
// integer-rank discipline has no break: the ladder consumes integers).
// The sample count pools the same way (round(Σ w_i·N_i)).
//
// SUPPORT: lo = min(lo_i), hi = max(hi_i) — the pooled support is the
// UNION (order-independent min/max), the honest face for a mixture.
//
// WEIGHTS: normalized (Σw = 1) at the pool entry; the DEFAULT is equal
// split (the caller may omit weights — the panel's fresh rows); N = 1
// degrades to the IDENTITY pool (the single entry verbatim).
// ─────────────────────────────────────────────────────────────────────────────

/// The pooling input face — one reference's statistics + its list weight.
/// `weight` ≤ 0 is typed-rejected (a zero-weight reference would silently
/// vanish from the mean while still occupying a list row).
public struct ColorMatchPoolEntry: Sendable, Equatable {
    public let stats: ColorMatchStats
    public let weight: Double

    public init(stats: ColorMatchStats, weight: Double = 1) {
        precondition(weight > 0, "pool entry weight must be positive")
        self.stats = stats
        self.weight = weight
    }
}

public enum ColorMatchPoolingError: Error, Equatable, Sendable {
    /// `pool` on an empty entry list — statistics are undefined; the typed
    /// error is the contract (the P1 emptySampleSet 体例).
    case emptyInput
}

public enum ColorMatchPooling {

    /// Pool N reference statistics into one. Deterministic under any input
    /// permutation (the sorted-order fold); N = 1 returns the entry's stats
    /// verbatim.
    public static func pool(_ entries: [ColorMatchPoolEntry]) throws -> ColorMatchStats {
        guard !entries.isEmpty else { throw ColorMatchPoolingError.emptyInput }
        // N = 1: the identity pool (the single-reference main flow).
        if entries.count == 1 { return entries[0].stats }

        // ORDER NORMALIZATION: hash-ascending; ties (impossible for
        // distinct references — equal bytes would BE the same stats) keep
        // a stable index order.
        let sorted = entries.enumerated().sorted {
            $0.element.stats.statsHash != $1.element.stats.statsHash
                ? $0.element.stats.statsHash < $1.element.stats.statsHash
                : $0.offset < $1.offset
        }.map(\.element)

        // Weight normalization (Σw = 1).
        let weightSum = sorted.reduce(0) { $0 + $1.weight }
        let weights = sorted.map { $0.weight / weightSum }

        // μ_pool (sorted-order Float64 accumulation).
        var muPool = SIMD3<Double>.zero
        for (entry, weight) in zip(sorted, weights) {
            muPool += SIMD3<Double>(entry.stats.mu) * weight
        }

        // Σ_pool = Σ w (Σ_i + (μ_i − μ_pool)(μ_i − μ_pool)ᵀ) — Float64,
        // the symmetric six-tuple face (σxx σxy σxz σyy σyz σzz).
        var sigma = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        for (entry, weight) in zip(sorted, weights) {
            let s = entry.stats.sigma
            let d = SIMD3<Double>(entry.stats.mu) - muPool
            let xx = Double(s.0) + d.x * d.x
            let xy = Double(s.1) + d.x * d.y
            let xz = Double(s.2) + d.x * d.z
            let yy = Double(s.3) + d.y * d.y
            let yz = Double(s.4) + d.y * d.z
            let zz = Double(s.5) + d.z * d.z
            sigma.0 += weight * xx
            sigma.1 += weight * xy
            sigma.2 += weight * xz
            sigma.3 += weight * yy
            sigma.4 += weight * yz
            sigma.5 += weight * zz
        }

        // The histograms: integer counts back (sorted-order sum + round).
        var histograms = [[UInt32]](
            repeating: [UInt32](repeating: 0, count: ColorMatchStats.binCount), count: 3)
        for channel in 0..<3 {
            for bin in 0..<ColorMatchStats.binCount {
                var sum = 0.0
                for (entry, weight) in zip(sorted, weights) {
                    sum += weight * Double(entry.stats.histograms[channel][bin])
                }
                histograms[channel][bin] = UInt32(max(0, sum.rounded()))
            }
        }

        // The sample count + the union support.
        var sampleCount = 0.0
        var supportLo = SIMD3<Float>(.infinity, .infinity, .infinity)
        var supportHi = SIMD3<Float>(-.infinity, -.infinity, -.infinity)
        for entry in sorted {
            sampleCount += weightSum > 0
                ? entry.weight / weightSum * Double(entry.stats.sampleCount) : 0
            supportLo = min(supportLo, entry.stats.supportLo)
            supportHi = max(supportHi, entry.stats.supportHi)
        }

        return ColorMatchStats(
            mu: SIMD3<Float>(muPool),
            sigma: (
                Float(sigma.0), Float(sigma.1), Float(sigma.2),
                Float(sigma.3), Float(sigma.4), Float(sigma.5)),
            histograms: histograms,
            supportLo: supportLo, supportHi: supportHi,
            sampleCount: Int(sampleCount.rounded()))
    }
}
