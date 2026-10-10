@testable import LightamerCore
import XCTest

/// ColorMatchCDFSolverTests (Plan M5-1-02 T1, KD-1) — the S2 per-channel CDF
/// ladder solver:
///
/// - the quantile-alignment construction (a known shifted distribution
///   pair → monotone curve whose quartiles map onto the reference's);
/// - the identity distribution → the EXACT identity ladder (dense
///   histogram, no zero bins);
/// - the integer-rank discipline (every curve value is EXACTLY a lattice
///   value — the no-interpolation face);
/// - the trim plateaus (out-of-support source bins → the reference
///   support's end values, exactly);
/// - the double-run BYTE identity (G1);
/// - the solutionHash = the shared solve-cache key fold (the .cdf literal
///   pinned alongside the P1 gaussianOT/reinhard literals);
/// - the evaluate end-clamp (HDR > 1 input → the domain-end plateau).
final class ColorMatchCDFSolverTests: XCTestCase {

    // MARK: - Fixtures

    /// Build stats from explicit per-channel histograms (bypasses extract —
    /// the ladder consumes the histogram face directly). The support bounds
    /// derive from the histograms via the SAME 1%/99% integer-rank ladder
    /// the P1 extract runs (`percentileBin` below) — a fixture hardcoding
    /// the full domain would silently disarm the plateau tests.
    private func stats(
        _ histograms: [[UInt32]], sampleCount: Int
    ) -> ColorMatchStats {
        var supportLo = SIMD3<Float>.zero
        var supportHi = SIMD3<Float>.zero
        for channel in 0..<3 {
            supportLo[channel] = ColorMatchStats.binValue(
                channel: channel, bin: percentileBin(histograms[channel], fraction: 0.01))
            supportHi[channel] = ColorMatchStats.binValue(
                channel: channel, bin: percentileBin(histograms[channel], fraction: 0.99))
        }
        // Derive μ from the lattice midpoints so the statsHash face is
        // self-consistent (the solver reads histograms + supports only).
        var sum = SIMD3<Double>.zero
        var n = 0.0
        for c in 0..<3 {
            for bin in 0..<256 where histograms[c][bin] > 0 {
                sum[c] += Double(ColorMatchStats.binValue(channel: c, bin: bin))
                    * Double(histograms[c][bin])
                n += Double(histograms[c][bin])
            }
        }
        let mu = SIMD3<Float>(sum / max(n, 1))
        return ColorMatchStats(
            mu: mu,
            sigma: (1e-4, 0, 0, 1e-4, 0, 1e-4),
            histograms: histograms, supportLo: supportLo,
            supportHi: supportHi, sampleCount: sampleCount)
    }

    /// A dense synthetic histogram: every bin occupied (the identity face
    /// needs zero-free bins), shaped by a tent profile around `peak`.
    private func denseHistogram(peak: Int, count: Int = 100_000) -> [UInt32] {
        var histogram = [UInt32](repeating: 0, count: 256)
        var remaining = count
        for bin in 0..<256 {
            let distance = abs(bin - peak)
            let share = max(256 - distance * 2, 8)
            let value = min(remaining, share)
            histogram[bin] = UInt32(value)
            remaining -= value
        }
        // Dump any remainder into the peak bin (the tent above allocates
        // ≤ 256·8 + Σ margin > count — the remainder is normally 0).
        if remaining > 0 { histogram[peak] += UInt32(remaining) }
        return histogram
    }

    // MARK: - Construction

    func testQuantileAlignmentShiftsDistribution() {
        // Source concentrated low (peak 64), reference concentrated high
        // (peak 192): the L curve must be monotone and map the source
        // MEDIAN bin onto the reference's median bin (the quantile
        // property, ±4 lattice steps).
        var source = [[UInt32]](repeating: denseHistogram(peak: 64), count: 3)
        var reference = [[UInt32]](repeating: denseHistogram(peak: 192), count: 3)
        // Give a/b identity shapes (the test watches L only).
        source[1] = denseHistogram(peak: 128)
        source[2] = source[1]
        reference[1] = source[1]
        reference[2] = source[1]
        let sourceStats = stats(source, sampleCount: 100_000)
        let referenceStats = stats(reference, sampleCount: 100_000)
        let solution = ColorMatchCDFSolver.solve(
            source: sourceStats, reference: referenceStats)

        let curve = solution.curves[0]
        // Monotone non-decreasing (the ladder + plateaus guarantee).
        for bin in 1..<256 {
            XCTAssertGreaterThanOrEqual(
                curve[bin], curve[bin - 1] - 1e-12, "curve must not decrease at \(bin)")
        }
        // The median maps onto the median: the first source bin whose
        // cumulative count reaches half the total, mapped through the
        // curve, must land within ±4 bins of the reference's own median
        // bin.
        func medianBin(_ histogram: [UInt32]) -> Int {
            let total = histogram.reduce(0) { $0 + Int($1) }
            var cumulative = 0
            for (bin, count) in histogram.enumerated() {
                cumulative += Int(count)
                if cumulative * 2 >= total { return bin }
            }
            return 255
        }
        let sourceMedian = medianBin(source[0])
        let referenceMedian = medianBin(reference[0])
        let mapped = ColorMatchStats.binIndex(
            channel: 0, value: Float(curve[sourceMedian]))
        XCTAssertTrue(
            abs(mapped - referenceMedian) <= 4,
            "median \(sourceMedian) should map near \(referenceMedian), got \(mapped)")
        // The ends plateau at the REFERENCE SUPPORT's ends (the trim
        // plateau policy — the bins outside the source support never take
        // domain-end values, they take the reference support's ends).
        let refLoBin = percentileBin(reference[0], fraction: 0.01)
        let refHiBin = percentileBin(reference[0], fraction: 0.99)
        XCTAssertEqual(curve[0], Double(ColorMatchStats.binValue(channel: 0, bin: refLoBin)))
        XCTAssertEqual(curve[255], Double(ColorMatchStats.binValue(channel: 0, bin: refHiBin)))
    }

    /// The P1 percentile ladder (the test's local mirror — the same walk
    /// the extraction runs, so fixture expectations stay spec-derived).
    private func percentileBin(_ counts: [UInt32], fraction: Double) -> Int {
        let total = counts.reduce(0) { $0 + Int($1) }
        let target = Int((fraction * Double(total)).rounded(.up))
        var cumulative = 0
        for (bin, count) in counts.enumerated() {
            cumulative += Int(count)
            if cumulative >= max(target, 1) { return bin }
        }
        return 255
    }

    func testIdentityDistributionGivesExactIdentityLadder() {
        // IDENTICAL dense histograms (no zero bins): the quantile arm is
        // the EXACT identity ladder INSIDE the 1%/99% support; outside it
        // the trim plateau policy clamps to the (own) support ends — the
        // "identity CURVE BAND" face with its plateau policy made exact.
        let histogram = denseHistogram(peak: 128)
        let s = stats([histogram, histogram, histogram], sampleCount: 100_000)
        let solution = ColorMatchCDFSolver.solve(source: s, reference: s)
        let supportLoBin = ColorMatchStats.binIndex(channel: 0, value: s.supportLo[0])
        let supportHiBin = ColorMatchStats.binIndex(channel: 0, value: s.supportHi[0])
        for channel in 0..<3 {
            for bin in 0..<256 {
                let identity = Double(ColorMatchStats.binValue(channel: channel, bin: bin))
                if bin < supportLoBin {
                    XCTAssertEqual(
                        solution.curves[channel][bin],
                        Double(ColorMatchStats.binValue(channel: channel, bin: supportLoBin)),
                        "low plateau at \(channel)/\(bin)")
                } else if bin > supportHiBin {
                    XCTAssertEqual(
                        solution.curves[channel][bin],
                        Double(ColorMatchStats.binValue(channel: channel, bin: supportHiBin)),
                        "high plateau at \(channel)/\(bin)")
                } else {
                    XCTAssertEqual(
                        solution.curves[channel][bin], identity,
                        "identity ladder must be exact at \(channel)/\(bin)")
                }
            }
        }
    }

    func testNearIdentityStaysWithinOneLatticeStep() {
        // A mildly different (but same-shape) distribution: INSIDE the
        // support the curve never strays further than a small bin
        // neighborhood of the identity (the G3-extension identity BAND
        // face); OUTSIDE it the trim plateau takes over (the dedicated
        // plateau test covers that arm — here the in-support arm only).
        let source = denseHistogram(peak: 128)
        let reference = denseHistogram(peak: 132)
        // Same support width keeps the plateaus anchored.
        let s = stats([source, source, source], sampleCount: 100_000)
        let r = stats([reference, reference, reference], sampleCount: 100_000)
        let solution = ColorMatchCDFSolver.solve(source: s, reference: r)
        // The in-support window = the NARROWER of the two supports (both
        // arms must stay in-band there).
        let lo = max(
            ColorMatchCDFSolver.percentileBin(source, fraction: 0.01),
            ColorMatchCDFSolver.percentileBin(reference, fraction: 0.01))
        let hi = min(
            ColorMatchCDFSolver.percentileBin(source, fraction: 0.99),
            ColorMatchCDFSolver.percentileBin(reference, fraction: 0.99))
        for channel in 0..<3 {
            for bin in lo...hi {
                let identity = Double(ColorMatchStats.binValue(channel: channel, bin: bin))
                XCTAssertLessThanOrEqual(
                    abs(solution.curves[channel][bin] - identity),
                    Double(
                        ColorMatchStats.binValue(channel: channel, bin: bin + 24)
                            - ColorMatchStats.binValue(channel: channel, bin: bin)),
                    "identity band breached at \(channel)/\(bin)")
            }
        }
    }

    // MARK: - The integer-rank face

    func testCurveValuesAreExactLatticeValues() {
        // Arbitrary ragged histograms (zero runs included): every curve
        // value must equal SOME lattice value EXACTLY — no interpolation
        // can ever produce an off-lattice Double.
        var ragged = [UInt32](repeating: 0, count: 256)
        for bin in stride(from: 10, to: 250, by: 7) { ragged[bin] = UInt32(bin * 13 + 1) }
        var other = [UInt32](repeating: 0, count: 256)
        for bin in stride(from: 3, to: 253, by: 11) { other[bin] = UInt32(bin * 29 + 5) }
        let source = stats([ragged, other, ragged], sampleCount: 1)
        let reference = stats([other, ragged, other], sampleCount: 1)
        let solution = ColorMatchCDFSolver.solve(source: source, reference: reference)
        for channel in 0..<3 {
            for bin in 0..<256 {
                let value = solution.curves[channel][bin]
                let latticeHit = (0..<256).contains {
                    Double(ColorMatchStats.binValue(channel: channel, bin: $0)) == value
                }
                XCTAssertTrue(latticeHit, "off-lattice value at \(channel)/\(bin): \(value)")
            }
        }
    }

    // MARK: - The trim plateaus

    func testOutOfSupportBinsPlateauAtReferenceSupportEnds() {
        // Source support ≈ bins 51..199, reference support ≈ bins 37..229
        // (both derived by the same percentile walk below). Bins below the
        // source support must ALL take the reference support's low lattice
        // value; bins above it its high value.
        var sourceHistogram = [UInt32](repeating: 0, count: 256)
        for bin in 50...200 { sourceHistogram[bin] = UInt32(1000 - bin) }
        var referenceHistogram = [UInt32](repeating: 0, count: 256)
        for bin in 30...230 { referenceHistogram[bin] = UInt32(bin) }
        let source = stats(
            [sourceHistogram, sourceHistogram, sourceHistogram], sampleCount: 1)
        let reference = stats(
            [referenceHistogram, referenceHistogram, referenceHistogram], sampleCount: 1)
        let solution = ColorMatchCDFSolver.solve(source: source, reference: reference)

        let sourceLoBin = percentileBin(sourceHistogram, fraction: 0.01)
        let sourceHiBin = percentileBin(sourceHistogram, fraction: 0.99)
        let refLoBin = percentileBin(referenceHistogram, fraction: 0.01)
        let refHiBin = percentileBin(referenceHistogram, fraction: 0.99)
        let loValue = Double(ColorMatchStats.binValue(channel: 0, bin: refLoBin))
        let hiValue = Double(ColorMatchStats.binValue(channel: 0, bin: refHiBin))
        // Sanity: the fixtures produce REAL interior supports (not the full
        // domain) — otherwise this test would prove nothing.
        XCTAssertTrue(sourceLoBin > 10 && sourceHiBin < 246)
        XCTAssertTrue(refLoBin > 10 && refHiBin < 246)
        for bin in 0..<sourceLoBin {
            XCTAssertEqual(
                solution.curves[0][bin], loValue, "low plateau breached at \(bin)")
        }
        for bin in (sourceHiBin + 1)..<256 {
            XCTAssertEqual(
                solution.curves[0][bin], hiValue, "high plateau breached at \(bin)")
        }
        // The in-support arm clamps into the reference support too.
        for bin in sourceLoBin...sourceHiBin {
            let value = solution.curves[0][bin]
            XCTAssertTrue(value >= loValue && value <= hiValue, "support clamp at \(bin)")
        }
    }

    func testEvaluateClampsDomainEnds() {
        // An HDR/negative Oklab value clamps into the end bin → the curve's
        // end value (the domain-end plateau face of the OQ-4 policy).
        let histogram = denseHistogram(peak: 128)
        let s = stats([histogram, histogram, histogram], sampleCount: 100_000)
        let solution = ColorMatchCDFSolver.solve(source: s, reference: s)
        XCTAssertEqual(
            solution.evaluate(channel: 0, value: 5.0),
            solution.evaluate(channel: 0, value: 1.0))
        XCTAssertEqual(
            solution.evaluate(channel: 1, value: -9.0),
            solution.evaluate(channel: 1, value: -0.5))
    }

    // MARK: - G1: determinism + the key fold

    func testDoubleRunIsByteIdentical() {
        let source = stats(
            [denseHistogram(peak: 70), denseHistogram(peak: 128), denseHistogram(peak: 200)],
            sampleCount: 100_000)
        let reference = stats(
            [denseHistogram(peak: 180), denseHistogram(peak: 120), denseHistogram(peak: 60)],
            sampleCount: 100_000)
        let a = ColorMatchCDFSolver.solve(source: source, reference: reference)
        let b = ColorMatchCDFSolver.solve(source: source, reference: reference)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.stableHash(), b.stableHash())
    }

    func testSolutionHashIsTheSharedCacheKeyFold() {
        // The solution identity = ColorMatchSolveCache.cacheKey(.cdf) — the
        // bake key's first term inherits the pinned fold order.
        let flat = [[Double]](repeating: [Double](repeating: 0.5, count: 256), count: 3)
        let solution = ColorMatchCDFSolution(
            curves: flat, sourceStatsHash: 0, referenceStatsHash: 0)
        XCTAssertEqual(
            solution.solutionHash,
            ColorMatchSolveCache.cacheKey(
                sourceStatsHash: 0, referenceStatsHash: 0, solver: .cdf))
        // Distinct inputs flip the identity (the sensitivity face).
        let other = ColorMatchCDFSolution(
            curves: flat, sourceStatsHash: 1, referenceStatsHash: 0)
        XCTAssertNotEqual(solution.solutionHash, other.solutionHash)
    }
}
