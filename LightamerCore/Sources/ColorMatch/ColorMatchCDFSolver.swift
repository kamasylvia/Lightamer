import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ColorMatchCDFSolver (Plan M5-1-02 T1, KD-1; OQ-1①/OQ-2) — the S2
// per-channel CDF matching solver: three INDEPENDENT 256-entry mapping
// curves (L, a, b), one per Oklab channel, over the ColorMatchStats
// histograms.
//
// CONSTRUCTION (the pinned quantile-alignment form): for each channel the
// source bin i's cumulative fraction p = cumSrc[i]/totalSrc maps to the
// FIRST reference bin j whose cumulative fraction reaches p — and the
// curve's value at i is the reference lattice value of j:
//
//     curve[i] = binValue(channel, j)   where j = min{ j : cumRef[j]·totalSrc ≥ cumSrc[i]·totalRef }
//
// The comparison is EXACT INTEGER CROSS-MULTIPLICATION (UInt64 — the
// products of two UInt32 counts fit exactly) — the P1 integer-rank
// discipline (no float compares, no interpolation anywhere; the curve is
// a STEP LADDER). Both histograms share the SAME 256-bin domain lattice
// (ColorMatchStats' pinned L∈[0,1] / a,b∈[−0.5,+0.5] map), so the lattice
// value is the shared map's exact inverse at integer bins.
//
// TRIM PLATEAUS (KD-1, the P1 trim's one-body face): bins BELOW the source
// support's low bin take the REFERENCE support's low lattice value; bins
// ABOVE the source support's high bin take the reference support's high
// value. The ladder between the support ends is additionally CLAMPED into
// the reference support — every curve output stays inside the reference
// 1%..99% support (the ≥98% coverage ruling, OQ-4). Input clamping rides
// `ColorMatchStats.binIndex` (its end-clamp IS the HDR >1 policy — the
// domain-end plateau face).
//
// KNOWN WEAKNESS (OQ-1①, disclosed): channel independence breaks hue —
// the panel discloses it and strength blending mitigates; the default
// solver stays S1 (gaussianOT).
//
// NON-PERSISTENCE (the adjudicated carrier split): the curves live ONLY
// on the solve→bake chain. Params persist `{assetRef, assetHash}` (the
// baked .cube), never the curves — a re-solve re-extracts the statistics
// and re-runs this pure function (G1's re-solve closure).
//
// DETERMINISM (G1): pure integer ladders + Float64 lattice values — same
// stats bytes → same curve bytes, every process, every machine. The
// solution identity (`solutionHash`) = the shared solve-cache key fold
// (sourceStatsHash ⊕ referenceStatsHash ⊕ the .cdf tag) — the same key
// the S1/S3 cache uses, so the bake key `fnv(solutionHash ⊕ α bits)`
// inherits the fold-order pin.
// ─────────────────────────────────────────────────────────────────────────────

/// One solved S2 color match: the three 256-entry Float64 step ladders plus
/// the stats identities behind the solve.
public struct ColorMatchCDFSolution: Sendable, Equatable {

    /// The channel-major curve table: 3 × 256 Float64 values, each EXACTLY
    /// a lattice value of the shared domain map (the ladder/plateau face —
    /// `curve[c][ColorMatchStats.binIndex(channel: c, value: v)]`).
    public let curves: [[Double]]

    /// The stats identities behind the solve (the G1 input face).
    public let sourceStatsHash: UInt64
    public let referenceStatsHash: UInt64

    /// The solve identity — the SAME fold the solve cache uses
    /// (`ColorMatchSolveCache.cacheKey(source:reference:solver: .cdf)`),
    /// the bake key's first term (KD-3).
    public let solutionHash: UInt64

    public init(
        curves: [[Double]], sourceStatsHash: UInt64, referenceStatsHash: UInt64
    ) {
        precondition(curves.count == 3)
        for curve in curves { precondition(curve.count == ColorMatchStats.binCount) }
        self.curves = curves
        self.sourceStatsHash = sourceStatsHash
        self.referenceStatsHash = referenceStatsHash
        self.solutionHash = ColorMatchSolveCache.cacheKey(
            sourceStatsHash: sourceStatsHash, referenceStatsHash: referenceStatsHash,
            solver: .cdf)
    }

    /// Evaluate one channel's ladder at an Oklab value: the stats domain
    /// map's bin index (end-clamping — the domain-end plateau) picks the
    /// step. NO interpolation — a ladder read.
    @inline(__always)
    public func evaluate(channel: Int, value: Float) -> Double {
        curves[channel][ColorMatchStats.binIndex(channel: channel, value: value)]
    }

    /// Apply all three ladders to an Oklab triple.
    @inline(__always)
    public func apply(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            Float(evaluate(channel: 0, value: lab.x)),
            Float(evaluate(channel: 1, value: lab.y)),
            Float(evaluate(channel: 2, value: lab.z)))
    }

    /// The G1 byte face: FNV-1a over the ladder bits + the input hashes
    /// (Float64 bit patterns, channel-major bin order — the statsHash
    /// fold 体例). Two solves with identical curves fold identically.
    public func stableHash() -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        h = withUnsafeBytes(of: sourceStatsHash) { StableHash.combine(h, $0) }
        h = withUnsafeBytes(of: referenceStatsHash) { StableHash.combine(h, $0) }
        for curve in curves {
            for value in curve {
                var bits = value.bitPattern
                h = withUnsafeBytes(of: &bits) { StableHash.combine(h, $0) }
            }
        }
        return h
    }
}

public enum ColorMatchCDFSolver {

    /// Solve the S2 curves from source → reference statistics. Total (no
    /// failure mode): a constant-color or empty-support channel still has
    /// well-defined histograms, so the ladder always constructs.
    ///
    /// The trim support BINS are re-derived here from the histograms via
    /// the SAME 1%/99% percentile ladder the extraction runs — NOT from
    /// the stored `supportLo/Hi` values: recovering a bin through
    /// `binIndex(binValue(bin))` is Float32-fragile (the round-trip can
    /// truncate one step low), and the histograms ARE the S2 solver's
    /// complete input (the E4 sufficiency note — the moments never feed
    /// the ladder).
    public static func solve(
        source: ColorMatchStats, reference: ColorMatchStats
    ) -> ColorMatchCDFSolution {
        var curves = [[Double]]()
        curves.reserveCapacity(3)
        for channel in 0..<3 {
            curves.append(
                buildCurve(
                    channel: channel,
                    source: source.histograms[channel],
                    reference: reference.histograms[channel]))
        }
        return ColorMatchCDFSolution(
            curves: curves, sourceStatsHash: source.statsHash,
            referenceStatsHash: reference.statsHash)
    }

    /// The P1 percentile ladder (the extraction's exact walk): the first
    /// bin whose cumulative count reaches ⌈fraction·N⌉.
    static func percentileBin(_ counts: [UInt32], fraction: Double) -> Int {
        let total = counts.reduce(0) { $0 + Int($1) }
        let target = Int((fraction * Double(total)).rounded(.up))
        var cumulative = 0
        for (bin, count) in counts.enumerated() {
            cumulative += Int(count)
            if cumulative >= max(target, 1) { return bin }
        }
        return ColorMatchStats.binCount - 1
    }

    /// One channel's ladder: the quantile alignment + the trim plateaus.
    static func buildCurve(
        channel: Int, source: [UInt32], reference: [UInt32]
    ) -> [Double] {
        let bins = ColorMatchStats.binCount
        var cumSource = [UInt64](repeating: 0, count: bins)
        var cumReference = [UInt64](repeating: 0, count: bins)
        var runS: UInt64 = 0
        var runR: UInt64 = 0
        for bin in 0..<bins {
            runS += UInt64(source[bin])
            runR += UInt64(reference[bin])
            cumSource[bin] = runS
            cumReference[bin] = runR
        }
        let totalSource = runS
        let totalReference = runR
        // The trim supports, re-derived (see solve's note).
        let sourceSupport = (
            lo: percentileBin(source, fraction: 0.01),
            hi: percentileBin(source, fraction: 0.99)
        )
        let referenceSupport = (
            lo: percentileBin(reference, fraction: 0.01),
            hi: percentileBin(reference, fraction: 0.99)
        )

        // The first reference bin whose cumulative count reaches the
        // source bin i's fraction — EXACT via cross-multiplication:
        // cumRef[j]/totalRef >= cumSrc[i]/totalSrc  ⇔
        // cumRef[j]·totalSrc >= cumSrc[i]·totalRef (both sides < 2^64:
        // counts are UInt32 totals, products of two ≤2^32 values).
        func firstReferenceBin(_ sourceCumulative: UInt64) -> Int {
            let scaled = sourceCumulative * totalReference
            for bin in 0..<bins where cumReference[bin] * totalSource >= scaled {
                return bin
            }
            return bins - 1
        }

        var curve = [Double](repeating: 0, count: bins)
        let refLoValue = Double(ColorMatchStats.binValue(channel: channel, bin: referenceSupport.lo))
        let refHiValue = Double(ColorMatchStats.binValue(channel: channel, bin: referenceSupport.hi))
        for bin in 0..<bins {
            if bin < sourceSupport.lo {
                // Below the source support: the reference support's floor.
                curve[bin] = refLoValue
                continue
            }
            if bin > sourceSupport.hi {
                // Above the source support: the reference support's ceil.
                curve[bin] = refHiValue
                continue
            }
            let j = firstReferenceBin(cumSource[bin])
            let clamped = min(max(j, referenceSupport.lo), referenceSupport.hi)
            curve[bin] = Double(ColorMatchStats.binValue(channel: channel, bin: clamped))
        }
        return curve
    }
}
