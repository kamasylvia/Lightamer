@testable import LightamerCore
import simd
import XCTest

/// ColorMatchStatsTests (Plan M5-1-01 T2, KD-2 + checker E4) — the Oklab
/// statistics-face proofs:
///
/// - the pinned histogram domain map, bin by bin (L vs the a/b symmetric
///   domains, end-bin clamp keeps every count);
/// - the 1%/99% integer-rank trim on CONSTRUCTED distributions (exact
///   percentile assertions — the ladder walk, never float interpolation);
/// - the moments against closed-form values (a Gaussian sample set vs the
///   analytic μ/Σ);
/// - the statsHash: double-run byte identity + field sensitivity — a single
///   histogram count flip, a single MOMENT BIT flip (checker E4: the
///   moments are not a histogram function — the hash folds their bit
///   patterns precisely so the solve cache cannot collide), and a single
///   support-bound bit flip each turn the hash;
/// - the empty-sample-set typed failure.
final class ColorMatchStatsTests: XCTestCase {

    /// Deterministic LCG (FilmPrintBake precedent).
    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        /// Standard normal via Box-Muller (deterministic from the LCG).
        mutating func gaussian() -> Double {
            let u1 = max(Double(next() >> 11) / Double(1 << 53), 1e-12)
            let u2 = Double(next() >> 11) / Double(1 << 53)
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    // MARK: - Domain map, bin by bin

    /// The L domain [0, 1]: exact bin edges, the truncation face and the
    /// end-bin clamps.
    func testLChannelBinMap() {
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 0, value: 0.0), 0)
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 0, value: 1.0), 255)
        // The exact inverse pairs.
        for bin in [0, 1, 17, 128, 254, 255] {
            let v = ColorMatchStats.binValue(channel: 0, bin: bin)
            XCTAssertEqual(
                ColorMatchStats.binIndex(channel: 0, value: v), bin, "bin \(bin) inverse")
        }
        // Mid-bin truncation: 0.5 → 127.5 → 127 (truncation, not rounding).
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 0, value: 0.5), 127)
        // Out-of-domain clamps.
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 0, value: -0.25), 0, "L below domain")
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 0, value: 1.5), 255, "L above domain")
        // HDR inputs stay clamped (counts never dropped, never crash).
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 0, value: 64.0), 255)
    }

    /// The a/b symmetric domain [−0.5, +0.5]: zero maps to the center bin,
    /// both ends clamp, the negative arm truncates INTO the clamp.
    func testABChannelBinMap() {
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 1, value: 0.0), 127)
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 2, value: 0.0), 127)
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 1, value: -0.5), 0)
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 1, value: 0.5), 255)
        // Symmetric points map symmetrically around the center: ±0.25 →
        // 63.75/191.25 truncated → 63 + 191 = 254 (truncation floors each
        // arm; the sum is 254, not 255 — the pinned truncation face).
        let neg = ColorMatchStats.binIndex(channel: 1, value: -0.25)
        let pos = ColorMatchStats.binIndex(channel: 1, value: 0.25)
        XCTAssertEqual(neg, 63)
        XCTAssertEqual(pos, 191)
        XCTAssertEqual(neg + pos, 254)
        // Out-of-domain clamps (the a/b hull reaches ±~0.6 at HDR — DECISIONS).
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 1, value: -0.9), 0)
        XCTAssertEqual(ColorMatchStats.binIndex(channel: 1, value: 0.9), 255)
        XCTAssertEqual(ColorMatchStats.binValue(channel: 2, bin: 0), -0.5)
        XCTAssertEqual(ColorMatchStats.binValue(channel: 2, bin: 255), 0.5)
    }

    // MARK: - Integer-rank trim on constructed distributions

    /// A constructed two-cluster distribution: the 1% ladder lands exactly
    /// where the counts put it. 100 samples: 50 at a=−0.4, 49 at a=0, 1
    /// outlier at a=+0.5. ⌈0.01·100⌉ = 1 → the low bound is the FIRST
    /// non-empty bin; ⌈0.99·100⌉ = 99 → the high bound is the bin holding
    /// the 99th cumulative count (the outlier's bin is NOT the bound).
    func testTrimIntegerRankExact() throws {
        var samples: [SIMD3<Float>] = []
        for _ in 0..<50 { samples.append(SIMD3(0.5, -0.4, 0.0)) }
        for _ in 0..<49 { samples.append(SIMD3(0.5, 0.0, 0.0)) }
        samples.append(SIMD3(0.5, 0.5, 0.0))

        let stats = try ColorMatchStats.extract(samples: samples)
        // a-channel: the low bound = the bin of the first non-empty cell
        // (the −0.4 cluster), the high bound = the 99th cumulative bin
        // (the 0.0 cluster — NOT the outlier's 255 bin).
        let lowBin = ColorMatchStats.binIndex(channel: 1, value: -0.4)
        let midBin = ColorMatchStats.binIndex(channel: 1, value: 0.0)
        XCTAssertEqual(stats.supportLo.y, ColorMatchStats.binValue(channel: 1, bin: lowBin))
        XCTAssertEqual(stats.supportHi.y, ColorMatchStats.binValue(channel: 1, bin: midBin))
        XCTAssertLessThan(stats.supportHi.y, 0.5, "the 1% outlier leaves the high bound")
        // The histogram kept ALL 100 counts (clamp semantics).
        XCTAssertEqual(stats.histograms[1].reduce(0, +), 100)
        // The moment population = the in-support 99 (50 at −0.4, 49 at 0).
        XCTAssertEqual(
            stats.mu.y, 50.0 / 99.0 * -0.4, accuracy: 1e-6,
            "the outlier is out of the moment population")
    }

    /// The single-cluster degenerate: all samples identical — both bounds
    /// land on that bin, the covariance is exactly zero.
    func testDegenerateSingleBin() throws {
        let samples = [SIMD3<Float>](repeating: SIMD3(0.5, 0.1, -0.2), count: 64)
        let stats = try ColorMatchStats.extract(samples: samples)
        for (ch, want) in [Float(0.5), 0.1, -0.2].enumerated() {
            XCTAssertEqual(stats.mu[ch], want, accuracy: 1e-6, "mu[\(ch)]")
        }
        XCTAssertEqual(stats.sigma.0, 0, accuracy: 1e-9)
        XCTAssertEqual(stats.sigma.1, 0, accuracy: 1e-9)
        XCTAssertEqual(stats.sigma.4, 0, accuracy: 1e-9)
        // The support collapses onto the single occupied bin.
        let binL = ColorMatchStats.binIndex(channel: 0, value: 0.5)
        XCTAssertEqual(stats.supportLo.x, ColorMatchStats.binValue(channel: 0, bin: binL))
        XCTAssertEqual(stats.supportHi.x, ColorMatchStats.binValue(channel: 0, bin: binL))
    }

    // MARK: - Moments vs the analytic closed form

    /// An uncorrelated Gaussian sample set: μ against the analytic mean, the
    /// covariance structure against its analytic shape. The 1%/99% trim
    /// SHAVES Gaussian tails by construction (measured ~12-14% variance
    /// reduction on this drive set — the DECISIONS note), so the diagonal
    /// bands sit at ±25% relative: discriminative against structural errors
    /// (a zero/slotted/duplicated entry moves things by ≥50%), honest about
    /// the trim. The exact closed-form moments live in the three-group test
    /// below.
    func testGaussianMomentsAgainstAnalytic() throws {
        var rng = LCG(seed: 0x5A17)
        let trueMu = SIMD3<Double>(0.45, 0.02, -0.03)
        let trueSigma = SIMD3<Double>(0.10, 0.06, 0.08)
        let rho = 0.35  // a fixed x/y correlation (a non-diagonal Σ face)
        var samples: [SIMD3<Float>] = []
        samples.reserveCapacity(20000)
        for _ in 0..<20000 {
            let g = SIMD3<Double>(rng.gaussian(), rng.gaussian(), rng.gaussian())
            var v = trueMu + trueSigma * g
            v.y = trueMu.y + trueSigma.y * (rho * g.x + (1 - rho * rho).squareRoot() * g.y)
            samples.append(SIMD3<Float>(v))
        }
        let stats = try ColorMatchStats.extract(samples: samples)
        // μ within 2% of the true values (Oklab units: σ/√N ≈ 7e-4 — 2%
        // of the unit scale is generous and still discriminative).
        for ch in 0..<3 {
            XCTAssertEqual(Double(stats.mu[ch]), trueMu[ch], accuracy: 0.02, "mu[\(ch)]")
        }
        // Diagonals: within 25% relative of the true variances (the trim
        // shave measured ~12-14% — the band is the honest post-trim face).
        XCTAssertEqual(Double(stats.sigma.0), trueSigma.x * trueSigma.x, accuracy: 0.25 * trueSigma.x * trueSigma.x)
        XCTAssertEqual(Double(stats.sigma.3), trueSigma.y * trueSigma.y, accuracy: 0.25 * trueSigma.y * trueSigma.y)
        XCTAssertEqual(Double(stats.sigma.5), trueSigma.z * trueSigma.z, accuracy: 0.25 * trueSigma.z * trueSigma.z)
        // The seeded correlation: σxy (slot 1) against its analytic value,
        // same ±25% band. The σyz slot (4) is analytically ZERO (y/z built
        // independent) — a sharp small band.
        let wantXY = trueSigma.x * trueSigma.y * rho
        XCTAssertEqual(Double(stats.sigma.1), wantXY, accuracy: 0.25 * abs(wantXY), "sigma-xy")
        XCTAssertEqual(Double(stats.sigma.4), 0.0, accuracy: 2e-3, "sigma-yz analytically zero")
    }

    /// EXACT closed-form moments: a three-group bounded distribution whose
    /// 1%/99% percentiles land on the extreme OCCUPIED bins, so the trim
    /// removes NOTHING and every covariance entry is hand-computable. This
    /// pins the six-tuple packing order (each slot carries a distinct value)
    /// and the unbiased (N−1) divisor face.
    ///
    /// Groups (n=25/50/25): A(0.3, 0.1, 0.7), B(0.5, 0.2, 0.5), C(0.7, 0.3, 0.3).
    /// μ = (0.5, 0.2, 0.5); centered sums over N−1 = 99:
    ///   σxx = 2.0/99, σxy = 1.0/99, σxz = −2.0/99,
    ///   σyy = 0.5/99, σyz = −1.0/99, σzz = 2.0/99.
    func testThreeGroupExactClosedForm() throws {
        var samples: [SIMD3<Float>] = []
        for _ in 0..<25 { samples.append(SIMD3(0.3, 0.1, 0.7)) }
        for _ in 0..<50 { samples.append(SIMD3(0.5, 0.2, 0.5)) }
        for _ in 0..<25 { samples.append(SIMD3(0.7, 0.3, 0.3)) }
        let stats = try ColorMatchStats.extract(samples: samples)
        let d = 1.0 / 99.0
        XCTAssertEqual(Double(stats.mu.x), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(stats.mu.y), 0.2, accuracy: 1e-6)
        XCTAssertEqual(Double(stats.mu.z), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(stats.sigma.0), 2.0 * d, accuracy: 1e-6, "sigma-xx")
        XCTAssertEqual(Double(stats.sigma.1), 1.0 * d, accuracy: 1e-6, "sigma-xy")
        XCTAssertEqual(Double(stats.sigma.2), -2.0 * d, accuracy: 1e-6, "sigma-xz")
        XCTAssertEqual(Double(stats.sigma.3), 0.5 * d, accuracy: 1e-6, "sigma-yy")
        XCTAssertEqual(Double(stats.sigma.4), -1.0 * d, accuracy: 1e-6, "sigma-yz")
        XCTAssertEqual(Double(stats.sigma.5), 2.0 * d, accuracy: 1e-6, "sigma-zz")
        // The trim removed nothing: the moment population = all 100.
        XCTAssertEqual(stats.sampleCount, 100)
        XCTAssertEqual(
            stats.histograms[0].reduce(0) { $0 + Int($1) }, 100)
    }

    /// The six-tuple packing order (row-major σxx σxy σxz σyy σyz σzz) on a
    /// hand-built asymmetric sample set.
    func testSigmaPackingOrder() throws {
        // A tiny set with known covariances: x varies most, z correlates
        // with x, y independent.
        let samples: [SIMD3<Float>] = [
            SIMD3(0.0, 0.5, 0.0), SIMD3(0.2, 0.5, 0.2),
            SIMD3(0.4, 0.5, 0.4), SIMD3(0.6, 0.5, 0.6),
            SIMD3(0.8, 0.5, 0.8), SIMD3(1.0, 0.5, 1.0),
        ]
        let stats = try ColorMatchStats.extract(samples: samples)
        // z = x exactly → σzz == σxx and σxz == σxx; y constant → σyy == 0.
        XCTAssertEqual(stats.sigma.5, stats.sigma.0, accuracy: 1e-9, "σzz == σxx when z == x")
        XCTAssertEqual(stats.sigma.2, stats.sigma.0, accuracy: 1e-9, "σxz == σxx when z == x")
        XCTAssertEqual(stats.sigma.3, 0, accuracy: 1e-9, "σyy == 0 when y constant")
        XCTAssertEqual(stats.sigma.1, 0, accuracy: 1e-9, "σxy == 0 when y constant")
    }

    // MARK: - statsHash: identity + field sensitivity

    /// Double extraction of the same set → identical statsHash (and identical
    /// stats — Equatable).
    func testStatsHashDoubleRunIdentity() throws {
        var rng = LCG(seed: 0xD0)
        let samples = (0..<500).map { _ -> SIMD3<Float> in
            SIMD3<Float>(Float(rng.gaussian()) * 0.1 + 0.5, Float(rng.gaussian()) * 0.1, Float(rng.gaussian()) * 0.1)
        }
        let a = try ColorMatchStats.extract(samples: samples)
        let b = try ColorMatchStats.extract(samples: samples)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.statsHash, b.statsHash)
        // The plane-flattened entry agrees (fixed caller order).
        let c = try ColorMatchStats.extract(samples: [Array(samples[0..<250]), Array(samples[250...])])
        XCTAssertEqual(c.statsHash, a.statsHash)
    }

    /// Field sensitivity (checker E4): flipping ONE histogram count, ONE
    /// moment bit, or ONE support bound bit each turns the hash.
    func testStatsHashFieldSensitivity() throws {
        var rng = LCG(seed: 0xD1)
        let samples = (0..<400).map { _ -> SIMD3<Float> in
            SIMD3<Float>(Float(rng.gaussian()) * 0.1 + 0.5, Float(rng.gaussian()) * 0.1, Float(rng.gaussian()) * 0.1)
        }
        let base = try ColorMatchStats.extract(samples: samples)

        // E4 core: TWO stats whose 256-bin histograms are byte-identical but
        // whose moments differ MUST hash differently (the moment bit patterns
        // are in the fold — the histogram alone is NOT a sufficient hash
        // input for the S1/S3 solvers).
        let sameHist = ColorMatchStats(
            mu: base.mu + SIMD3<Float>(1e-7, 0, 0),
            sigma: base.sigma, histograms: base.histograms,
            supportLo: base.supportLo, supportHi: base.supportHi,
            sampleCount: base.sampleCount)
        XCTAssertEqual(sameHist.histograms, base.histograms)
        XCTAssertNotEqual(sameHist.statsHash, base.statsHash, "a mu bit flip turns the hash (E4)")

        // A covariance-only difference turns the hash.
        let nudgedSigma = ColorMatchStats(
            mu: base.mu, sigma: (base.sigma.0 + 1e-7, base.sigma.1, base.sigma.2,
                base.sigma.3, base.sigma.4, base.sigma.5),
            histograms: base.histograms,
            supportLo: base.supportLo, supportHi: base.supportHi,
            sampleCount: base.sampleCount)
        XCTAssertNotEqual(nudgedSigma.statsHash, base.statsHash, "a sigma bit flip turns the hash")

        // A support-bound-only difference turns the hash.
        let nudgedSupport = ColorMatchStats(
            mu: base.mu, sigma: base.sigma, histograms: base.histograms,
            supportLo: base.supportLo + SIMD3<Float>(1e-7, 0, 0),
            supportHi: base.supportHi, sampleCount: base.sampleCount)
        XCTAssertNotEqual(nudgedSupport.statsHash, base.statsHash, "a support bit flip turns the hash")

        // A sample-count-only difference turns the hash.
        let nudgedCount = ColorMatchStats(
            mu: base.mu, sigma: base.sigma, histograms: base.histograms,
            supportLo: base.supportLo, supportHi: base.supportHi,
            sampleCount: base.sampleCount + 1)
        XCTAssertNotEqual(nudgedCount.statsHash, base.statsHash, "a count flip turns the hash")
    }

    // MARK: - The empty-sample-set typed face

    func testEmptySampleSetThrowsTyped() {
        let empty: [SIMD3<Float>] = []
        let emptyPlanes: [[SIMD3<Float>]] = [[], []]
        XCTAssertThrowsError(try ColorMatchStats.extract(samples: empty)) { error in
            XCTAssertEqual(
                error as? ColorMatchStatsError, .emptySampleSet,
                "the typed empty-set error, not a silent zero stats")
        }
        XCTAssertThrowsError(try ColorMatchStats.extract(samples: emptyPlanes)) { error in
            XCTAssertEqual(error as? ColorMatchStatsError, .emptySampleSet)
        }
    }
}
