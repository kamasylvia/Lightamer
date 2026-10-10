@testable import LightamerCore
import simd
import XCTest

/// ColorMatchPoolingTests (Plan M5-1-02 T2, KD-2) — the multi-reference
/// weighted pooling:
///
/// - the second-moment formula anchor (two references, weights 1:3, the
///   mixture covariance hand-computed — μ, all six Σ slots);
/// - weight normalization (scalar-scaled weights → identical pools);
/// - ORDER NORMALIZATION (the same set in every permutation → the same
///   pool BYTES — the G1 determinism face);
/// - the N=1 identity degradation;
/// - the histogram rounding back to integer counts (the S2 arm's
///   integer-rank continuity);
/// - the empty-input typed error.
final class ColorMatchPoolingTests: XCTestCase {

    // MARK: - Fixtures

    private func stats(
        mu: SIMD3<Float>, sigma: (Float, Float, Float, Float, Float, Float),
        histograms: [[UInt32]]? = nil, sampleCount: Int
    ) -> ColorMatchStats {
        ColorMatchStats(
            mu: mu, sigma: sigma,
            histograms: histograms ?? {
                // A minimal deterministic histogram: one spike per channel
                // (distinct bins so pooled-histogram assertions can tell
                // the references apart).
                var h = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 3)
                for channel in 0..<3 { h[channel][100 + channel] = 40 }
                return h
            }(),
            supportLo: SIMD3(0.05, -0.1, -0.2), supportHi: SIMD3(0.9, 0.3, 0.4),
            sampleCount: sampleCount)
    }

    // MARK: - The formula anchor

    func testSecondMomentFormulaAnchor() throws {
        // Hand-computed mixture (weights 1:3 → 0.25/0.75):
        //   μ_pool = (0.25, 0.15, −0.075)
        //   σxx = 0.25(0.04+0.0225) + 0.75(0.16+0.0025) = 0.1375
        //   σxy = 0.25(0.0225) + 0.75(0.0025)           = 0.0075
        //   σxz = 0.25(−0.01125) + 0.75(−0.00125)        = −0.00375
        //   σyy = 0.25(0.0325) + 0.75(0.0925)            = 0.0775
        //   σyz = −0.00375
        //   σzz = 0.25(0.045625) + 0.75(0.010625)        = 0.019375
        let a = stats(
            mu: SIMD3(0.1, 0, 0), sigma: (0.04, 0, 0, 0.01, 0, 0.04), sampleCount: 10)
        let b = stats(
            mu: SIMD3(0.3, 0.2, -0.1), sigma: (0.16, 0, 0, 0.09, 0, 0.01), sampleCount: 30)
        let pooled = try ColorMatchPooling.pool([
            ColorMatchPoolEntry(stats: a, weight: 1),
            ColorMatchPoolEntry(stats: b, weight: 3),
        ])
        let mu = SIMD3<Double>(pooled.mu)
        XCTAssertEqual(mu.x, 0.25, accuracy: 1e-6)
        XCTAssertEqual(mu.y, 0.15, accuracy: 1e-6)
        XCTAssertEqual(mu.z, -0.075, accuracy: 1e-6)
        let s = pooled.sigma
        XCTAssertEqual(Double(s.0), 0.1375, accuracy: 1e-6)
        XCTAssertEqual(Double(s.1), 0.0075, accuracy: 1e-6)
        XCTAssertEqual(Double(s.2), -0.00375, accuracy: 1e-6)
        XCTAssertEqual(Double(s.3), 0.0775, accuracy: 1e-6)
        XCTAssertEqual(Double(s.4), -0.00375, accuracy: 1e-6)
        XCTAssertEqual(Double(s.5), 0.019375, accuracy: 1e-6)
        // The pooled sample count pools the same way (round(0.25·10 + 0.75·30)).
        XCTAssertEqual(pooled.sampleCount, 25)
        // The support is the UNION (per-component min/max).
        XCTAssertEqual(pooled.supportLo, simd_min(a.supportLo, b.supportLo))
        XCTAssertEqual(pooled.supportHi, simd_max(a.supportHi, b.supportHi))
    }

    // MARK: - Weight normalization

    func testScalarScaledWeightsGiveIdenticalPools() throws {
        let a = stats(mu: SIMD3(0.1, 0, 0), sigma: (0.04, 0, 0, 0.01, 0, 0.04), sampleCount: 10)
        let b = stats(mu: SIMD3(0.3, 0.2, -0.1), sigma: (0.16, 0, 0, 0.09, 0, 0.01), sampleCount: 30)
        let small = try ColorMatchPooling.pool([
            ColorMatchPoolEntry(stats: a, weight: 1), ColorMatchPoolEntry(stats: b, weight: 3),
        ])
        let large = try ColorMatchPooling.pool([
            ColorMatchPoolEntry(stats: a, weight: 100), ColorMatchPoolEntry(stats: b, weight: 300),
        ])
        XCTAssertEqual(small, large, "weight normalization: only the RATIOS matter")
        XCTAssertEqual(small.statsHash, large.statsHash)
    }

    // MARK: - Order normalization (the G1 determinism face)

    func testAnyPermutationGivesByteIdenticalPool() throws {
        // Three distinct references; every permutation of the list must
        // produce the SAME pool (Equatable + the recomputed statsHash).
        var references: [ColorMatchStats] = []
        for seed in 0..<3 {
            let s = Double(seed)
            var histograms = [[UInt32]](
                repeating: [UInt32](repeating: 0, count: 256), count: 3)
            for channel in 0..<3 {
                for bin in stride(from: seed * 11 + 3, to: 250, by: 13) {
                    histograms[channel][bin] = UInt32(bin * (seed + 2) + 7)
                }
            }
            references.append(stats(
                mu: SIMD3(Float(0.1 + 0.2 * s), Float(-0.05 * s), Float(0.02 * s)),
                sigma: (0.04 + Float(s) * 0.01, 0.001, 0, 0.02, 0.002, 0.03),
                histograms: histograms, sampleCount: 500 + seed))
        }
        let poolFrom = { (order: [Int]) throws -> ColorMatchStats in
            try ColorMatchPooling.pool(order.map { ColorMatchPoolEntry(stats: references[$0]) })
        }
        let baseline = try poolFrom([0, 1, 2])
        for permutation in [[2, 1, 0], [1, 0, 2], [1, 2, 0], [2, 0, 1], [0, 2, 1]] {
            let pooled = try poolFrom(permutation)
            XCTAssertEqual(pooled, baseline, "permutation \(permutation) diverged")
            XCTAssertEqual(pooled.statsHash, baseline.statsHash)
        }
    }

    // MARK: - The N=1 degradation

    func testSingleEntryIsTheIdentityPool() throws {
        let reference = stats(
            mu: SIMD3(0.2, -0.1, 0.3), sigma: (0.05, 0.001, 0.002, 0.02, 0.003, 0.01),
            sampleCount: 77)
        let pooled = try ColorMatchPooling.pool([
            ColorMatchPoolEntry(stats: reference, weight: 0.37)
        ])
        XCTAssertEqual(pooled, reference, "N=1 must pass the entry through verbatim")
        XCTAssertEqual(pooled.statsHash, reference.statsHash)
    }

    // MARK: - The histogram arm

    func testHistogramsRoundBackToIntegerCounts() throws {
        // Weighted counts 2.5 / 22.5 round to 3 / 23 (the integer-rank
        // continuity — the S2 ladder consumes integers only).
        var first = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 3)
        var second = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 3)
        for channel in 0..<3 {
            first[channel][5] = 10
            second[channel][200] = 30
        }
        let a = stats(mu: SIMD3(0.1, 0, 0), sigma: (0.04, 0, 0, 0.01, 0, 0.04),
                      histograms: first, sampleCount: 10)
        let b = stats(mu: SIMD3(0.3, 0.2, -0.1), sigma: (0.16, 0, 0, 0.09, 0, 0.01),
                      histograms: second, sampleCount: 30)
        let pooled = try ColorMatchPooling.pool([
            ColorMatchPoolEntry(stats: a, weight: 1), ColorMatchPoolEntry(stats: b, weight: 3),
        ])
        for channel in 0..<3 {
            XCTAssertEqual(pooled.histograms[channel][5], 3, "round(2.5) = 3")
            XCTAssertEqual(pooled.histograms[channel][200], 23, "round(22.5) = 23")
            XCTAssertEqual(pooled.histograms[channel].reduce(0, +), 26, "total counts")
        }
        // The pooled stats feed the S2 solver directly (the integration
        // face — the ladder constructs over pooled integer counts).
        XCTAssertNoThrow(ColorMatchCDFSolver.solve(source: pooled, reference: pooled))
    }

    // MARK: - The empty-input typed error

    func testEmptyInputThrowsTypedError() {
        XCTAssertThrowsError(try ColorMatchPooling.pool([])) { error in
            XCTAssertEqual(error as? ColorMatchPoolingError, .emptyInput)
        }
    }
}
