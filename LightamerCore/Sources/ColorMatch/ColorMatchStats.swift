import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// ColorMatchStats (Plan M5-1-01 T2, KD-2; OQ-M5-1-4 trim half) — the Oklab-
// domain distribution statistics for the color-match solvers, plus the
// deterministic sample-set extraction.
//
// FIELDS (the KD-2 face): mean μ (3), covariance Σ (symmetric 3×3, row-major
// six-tuple σxx σxy σxz σyy σyz σzz), per-channel 256-bin integer histograms
// (3×256 counts), the 1%/99% trimmed support bounds (per channel), the
// sample count, and the FNV-1a statsHash.
//
// HISTOGRAM DOMAIN MAP (pinned): L ∈ [0, 1] linear over 256 bins; a/b ∈
// [−0.5, +0.5] symmetric over 256 bins; out-of-domain values CLAMP to the
// end bins (counts are never dropped — Rec2020 gamut hulls reach a ≈
// ±0.55/−0.64 at HDR luminance, the DECISIONS domain-width note). The
// integer bin index is `Int((v − lo)/(hi − lo)·255)` TRUNCATED — the Film
// stats' integer-rank discipline (float interpolation banned). The bin's
// domain value is the forward map's exact inverse, `lo + bin·(hi−lo)/255`.
//
// TRIM (OQ-M5-1-4): per-channel 1%/99% percentiles are INTEGER-RANK ladder
// walks (cumulative count ≥ ⌈f·N⌉'s first bin), the support bounds are the
// trimmed bins' domain values, and the MOMENTS accumulate Float64 over the
// samples inside the support box only (all three channels in bounds — the
// outliers the trim exists for leave the moments; the histograms keep all
// counts by construction).
//
// statsHash COVERAGE (checker 回注 E4, 2026-10-09): the hash folds the
// UNION of both solvers' complete inputs — the histograms (S2's complete
// input) AND the μ/Σ Float32 bit patterns (S1/S3's complete input — the
// moments are NOT a function of the 256-bin histograms, so folding the
// histogram alone would let two moment-differing sample sets collide on
// one solve-cache key) AND the support bounds (they change the moments by
// changing the trim). Canonical fold order below; the "histogram is a
// sufficient statistic" wording is RETIRED (E4's false-premise correction).
// ─────────────────────────────────────────────────────────────────────────────

/// Typed extraction failure (the empty-sample-set face).
public enum ColorMatchStatsError: Error, Equatable, Sendable {
    /// `extract` on an empty sample set — statistics are undefined and the
    /// typed error is the contract (never a zero-filled stats value).
    case emptySampleSet
}

public struct ColorMatchStats: Equatable, Sendable {

    /// Channel domains: L ∈ [0, 1], a/b ∈ [−0.5, +0.5] (the pinned map).
    public static let domainLo = SIMD3<Float>(0.0, -0.5, -0.5)
    public static let domainHi = SIMD3<Float>(1.0, 0.5, 0.5)
    /// The bin count (3×256 — the Film/SiteReduce histogram shape).
    public static let binCount = 256

    /// Mean (Oklab domain, Float32 storage — Float64 accumulation upstream).
    public let mu: SIMD3<Float>
    /// Symmetric covariance, row-major six-tuple σxx σxy σxz σyy σyz σzz.
    public let sigma: (Float, Float, Float, Float, Float, Float)
    /// Per-channel 256-bin integer count histograms (channel order L, a, b).
    public let histograms: [[UInt32]]
    /// The 1%/99% trimmed support bounds (per channel, Oklab domain).
    public let supportLo: SIMD3<Float>
    public let supportHi: SIMD3<Float>
    /// The extracted sample count (pre-trim — the histogram population).
    public let sampleCount: Int
    /// FNV-1a over the canonical field fold (see the header note). Stored —
    /// identical bytes → identical hash across processes (L013 discipline;
    /// Float32 BIT PATTERNS, never Float64 re-derivation).
    public let statsHash: UInt64

    public init(
        mu: SIMD3<Float>, sigma: (Float, Float, Float, Float, Float, Float),
        histograms: [[UInt32]], supportLo: SIMD3<Float>, supportHi: SIMD3<Float>,
        sampleCount: Int
    ) {
        self.mu = mu
        self.sigma = sigma
        self.histograms = histograms
        self.supportLo = supportLo
        self.supportHi = supportHi
        self.sampleCount = sampleCount
        self.statsHash = ColorMatchStats.computeHash(
            histograms: histograms, sampleCount: sampleCount, mu: mu, sigma: sigma,
            supportLo: supportLo, supportHi: supportHi)
    }

    /// Manual Equatable — the tuple field blocks synthesis (tuples carry no
    /// protocol conformance).
    public static func == (lhs: ColorMatchStats, rhs: ColorMatchStats) -> Bool {
        lhs.mu == rhs.mu
            && lhs.sigma.0 == rhs.sigma.0 && lhs.sigma.1 == rhs.sigma.1
            && lhs.sigma.2 == rhs.sigma.2 && lhs.sigma.3 == rhs.sigma.3
            && lhs.sigma.4 == rhs.sigma.4 && lhs.sigma.5 == rhs.sigma.5
            && lhs.histograms == rhs.histograms
            && lhs.supportLo == rhs.supportLo && lhs.supportHi == rhs.supportHi
            && lhs.sampleCount == rhs.sampleCount
    }

    /// The canonical FNV-1a fold (L013 field-explicit bytes; the ORDER is
    /// the identity of the hash — FilmPrintBake/FilmStatsSeam 体例):
    /// histograms (channel-major, bin order) → sampleCount (UInt64 LE) →
    /// μ (3 × Float32 bits) → Σ (6 × Float32 bits) → supportLo → supportHi.
    static func computeHash(
        histograms: [[UInt32]], sampleCount: Int, mu: SIMD3<Float>,
        sigma: (Float, Float, Float, Float, Float, Float),
        supportLo: SIMD3<Float>, supportHi: SIMD3<Float>
    ) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        for channel in histograms {
            for count in channel {
                var v = count
                h = withUnsafeBytes(of: &v) { StableHash.combine(h, $0) }
            }
        }
        var n = UInt64(sampleCount)
        h = withUnsafeBytes(of: &n) { StableHash.combine(h, $0) }
        for value in [mu.x, mu.y, mu.z, sigma.0, sigma.1, sigma.2, sigma.3, sigma.4, sigma.5] {
            var bits = value.bitPattern
            h = withUnsafeBytes(of: &bits) { StableHash.combine(h, $0) }
        }
        for value in [supportLo.x, supportLo.y, supportLo.z, supportHi.x, supportHi.y, supportHi.z] {
            var bits = value.bitPattern
            h = withUnsafeBytes(of: &bits) { StableHash.combine(h, $0) }
        }
        return h
    }

    // MARK: - The domain map (pinned formulas)

    /// The integer bin index of a channel value (truncation + end clamp —
    /// the forward map; Float32 order, no interpolation).
    @inline(__always)
    public static func binIndex(channel: Int, value: Float) -> Int {
        let lo = domainLo[channel], hi = domainHi[channel]
        let scaled = (value - lo) / (hi - lo) * Float(Self.binCount - 1)
        let index = Int(scaled)  // truncation toward zero
        return min(max(index, 0), Self.binCount - 1)
    }

    /// The bin's domain value (the forward map's exact inverse at integer
    /// bins — the support bound face).
    @inline(__always)
    public static func binValue(channel: Int, bin: Int) -> Float {
        let lo = domainLo[channel], hi = domainHi[channel]
        return lo + Float(bin) / Float(Self.binCount - 1) * (hi - lo)
    }

    // MARK: - Extraction (pure, deterministic, zero IO)

    /// Extract the statistics of an Oklab-domain sample set. `samples` are
    /// the planes/rows in CALLER order — the single pass walks them in that
    /// fixed order (histograms, then the trimmed moments), so identical
    /// sets → identical stats → identical statsHash (bit-identity input).
    /// The flat-array convenience below is the same single pass.
    public static func extract(samples: [[SIMD3<Float>]]) throws -> ColorMatchStats {
        var flat: [SIMD3<Float>] = []
        for plane in samples { flat.append(contentsOf: plane) }
        return try extract(samples: flat)
    }

    /// The single-pass extraction: histograms first (all counts), then the
    /// integer-rank trim, then the Float64 moment accumulation over the
    /// in-support samples (the second walk is required by the trim's
    /// data dependence; both walks are in fixed caller order).
    public static func extract(samples: [SIMD3<Float>]) throws -> ColorMatchStats {
        guard !samples.isEmpty else { throw ColorMatchStatsError.emptySampleSet }

        // Pass 1: the 3×256 histograms (clamped ends — no count dropped).
        var histograms = [[UInt32]](
            repeating: [UInt32](repeating: 0, count: Self.binCount), count: 3)
        for sample in samples {
            histograms[0][Self.binIndex(channel: 0, value: sample.x)] += 1
            histograms[1][Self.binIndex(channel: 1, value: sample.y)] += 1
            histograms[2][Self.binIndex(channel: 2, value: sample.z)] += 1
        }

        // The integer-rank percentile: the first bin whose cumulative count
        // reaches ⌈fraction·N⌉ (the ladder walk — never a float compare on
        // percentile values).
        func percentileBin(_ counts: [UInt32], fraction: Double) -> Int {
            let total = counts.reduce(0) { $0 + Int($1) }
            let target = Int((fraction * Double(total)).rounded(.up))
            var cumulative = 0
            for (bin, count) in counts.enumerated() {
                cumulative += Int(count)
                if cumulative >= max(target, 1) { return bin }
            }
            return Self.binCount - 1
        }

        var supportLo = SIMD3<Float>.zero
        var supportHi = SIMD3<Float>.zero
        var supportBinsLo = [Int](repeating: 0, count: 3)
        var supportBinsHi = [Int](repeating: 0, count: 3)
        for channel in 0..<3 {
            supportBinsLo[channel] = percentileBin(histograms[channel], fraction: 0.01)
            supportBinsHi[channel] = percentileBin(histograms[channel], fraction: 0.99)
            supportLo[channel] = Self.binValue(channel: channel, bin: supportBinsLo[channel])
            supportHi[channel] = Self.binValue(channel: channel, bin: supportBinsHi[channel])
        }

        // The in-support membership test is BIN-INDEX based (each channel's
        // histogram bin within [loBin, hiBin]) — the exact discrete face.
        // A value-compare against the bin VALUES would wrongly exclude the
        // single-bin support (the occupied bin's lattice value is its lower
        // edge; identical samples would fall outside [v_b, v_b]).
        @inline(__always)
        func insideSupport(_ sample: SIMD3<Float>) -> Bool {
            for channel in 0..<3 {
                let bin = Self.binIndex(channel: channel, value: sample[channel])
                if bin < supportBinsLo[channel] || bin > supportBinsHi[channel] {
                    return false
                }
            }
            return true
        }

        // Pass 2: the moments over the in-support samples (Float64
        // accumulation, centered second moment, fixed caller order).
        var sum = SIMD3<Double>.zero
        var kept = 0
        for sample in samples {
            if insideSupport(sample) { sum += SIMD3<Double>(sample); kept += 1 }
        }
        // The support box is non-degenerate by construction (the percentile
        // ladder always lands on non-empty bins), so kept > 0.
        let mean = sum / Double(kept)
        var cov = simd_double3x3(columns: (
            SIMD3<Double>.zero, SIMD3<Double>.zero, SIMD3<Double>.zero))
        for sample in samples {
            if insideSupport(sample) {
                let d = SIMD3<Double>(sample) - mean
                cov += simd_double3x3(columns: (d.x * d, d.y * d, d.z * d))
            }
        }
        // The unbiased sample covariance (scalar reciprocal multiply — the
        // simd module has no matrix-division operator).
        cov = cov * (1.0 / Double(max(kept - 1, 1)))
        let c = cov.columns
        let stats = ColorMatchStats(
            mu: SIMD3<Float>(mean),
            sigma: (
                Float(c.0.x), Float(c.0.y), Float(c.0.z),
                Float(c.1.y), Float(c.1.z), Float(c.2.z)),
            histograms: histograms,
            supportLo: supportLo, supportHi: supportHi,
            sampleCount: samples.count)
        return stats
    }
}
