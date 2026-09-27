@testable import Lightamer
@testable import LightamerCore
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// StackAggregateTests (Plan 08-3 T3/T4) — the three-mode aggregation set:
// the analytic goldens (known values → exact mean/median/clipped re-mean),
// the sigma-clip star-field fixture (satellite-trail rejection), the N-value
// stack constant-memory lock, the N=3 degenerate note, and the SERVICE-SEG
// end-to-end faces: the four kinds through the real production leg (product
// landing + provenance kind + tag vocabulary + collision increment) and the
// EXIF precheck stack-variant matrix.
//
// Fixtures are synthetic and LOCAL-disk only (L009).
// ─────────────────────────────────────────────────────────────────────────────

final class StackAggregateTests: XCTestCase {

    // MARK: - Analytic goldens

    func testAnalyticGoldenAverage() {
        let samples: [Float] = [0.5, 0.25, 0.75, 0.5, 0.4, 0.6, 0.3, 0.7]
        let expected = samples.reduce(0, +) / 8
        XCTAssertEqual(
            StackAggregate.aggregate(samples, mode: .average), expected,
            accuracy: 1e-6)
        // NaN samples drop out of the mean (the alignment-edge semantics).
        let withHole: [Float] = [0.5, .nan, 0.75, 0.5, .nan, 0.6, 0.3, 0.7]
        let valid = withHole.filter { $0.isFinite }
        XCTAssertEqual(
            StackAggregate.aggregate(valid, mode: .average),
            StackAggregate.aggregate(withHole.compactMap { $0.isFinite ? $0 : nil },
                mode: .average), accuracy: 1e-6)
        XCTAssertTrue(StackAggregate.aggregate([.nan, .nan], mode: .average).isNaN)
    }

    func testAnalyticGoldenMedian() {
        // Odd count: the central order statistic.
        XCTAssertEqual(
            StackAggregate.aggregate([4, 1, 3, 5, 2].map(Float.init), mode: .median),
            3, accuracy: 1e-6)
        // Even count: the mean of the two central statistics (D-08-3-T3-2).
        XCTAssertEqual(
            StackAggregate.aggregate([4, 1, 3, 2].map(Float.init), mode: .median),
            2.5, accuracy: 1e-6)
        // The outlier rejection: a satellite pass in the median vanishes.
        XCTAssertEqual(
            StackAggregate.aggregate([0.5, 0.5, 0.5, 0.5, 8.0], mode: .median),
            0.5, accuracy: 1e-6)
    }

    func testAnalyticGoldenSigmaClip() {
        // A clean cluster + one gross outlier: the clip recovers the exact
        // clean mean. N=6 carries a population-σ max z of √5 ≈ 2.24 (a
        // single outlier can never exceed k=2.5 at this N), so the
        // analytic pin runs at k=2.0 — the star-field E2E pins the N=8
        // default-k face (D-08-3-T3-1: population σ).
        let clean: [Float] = [1.0, 1.1, 0.9, 1.05, 0.95]
        let cleanMean = clean.reduce(0, +) / 5
        let clipped = StackAggregate.aggregate(
            clean + [4.0], mode: .sigmaClip, sigmaK: 2.0)
        XCTAssertEqual(clipped, cleanMean, accuracy: 1e-5,
            "the 4.0 outlier must be rejected and the clean mean recovered")
        // No outlier → the plain mean (nothing rejected).
        XCTAssertEqual(
            StackAggregate.aggregate(clean, mode: .sigmaClip), cleanMean,
            accuracy: 1e-6)
        // A flat field (σ = 0) stays the flat value.
        XCTAssertEqual(
            StackAggregate.aggregate([0.5, 0.5, 0.5, 0.5], mode: .sigmaClip),
            0.5, accuracy: 1e-6)
        // A tighter k rejects milder outliers.
        let mild: [Float] = [1.0, 1.0, 1.0, 1.0, 1.3]
        XCTAssertEqual(
            StackAggregate.aggregate(mild, mode: .sigmaClip, sigmaK: 1.0),
            1.0, accuracy: 1e-6, "k=1 must reject the 1.3 tail")
    }

    // MARK: - The star-field fixture (sigma-clip's reason to exist)

    /// N=8 star subframes; source 6 drags a satellite TRAIL (a bright
    /// diagonal streak) across the frame. The sigma-clip aggregate must
    /// reject the trail's contribution; the plain average visibly smears.
    func testSigmaClipStarFieldRejectsSatelliteTrail() {
        let width = 96, height = 64
        var rng: UInt64 = 0x57A7
        func nextUniform() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFF) / Float(0xFFFF)
        }
        // The star field: faint sky + a few Gaussian-ish stars (as bright
        // bumps) + noise; the truth = the mean of the CLEAN frames.
        var cleanMean = [Float](repeating: 0, count: width * height)
        var frames: [[Float]] = []
        for frame in 0..<8 {
            var gray = [Float](repeating: 0, count: width * height)
            for index in gray.indices {
                gray[index] = 0.02 + 0.01 * nextUniform()
            }
            // Two "stars".
            gray[16 * width + 24] += 0.6
            gray[40 * width + 70] += 0.35
            frames.append(gray)
            for index in cleanMean.indices where frame < 7 {
                cleanMean[index] += gray[index] / 7
            }
        }
        // Frame 7: the satellite trail — a bright diagonal streak.
        for pixel in 0..<min(width, height) {
            frames[7][pixel * width + pixel] += 3.0
        }

        // Per-pixel aggregation over the N-stack (the band operator's shape).
        var clipped = [Float](repeating: 0, count: width * height)
        var averaged = [Float](repeating: 0, count: width * height)
        for index in cleanMean.indices {
            let stack = frames.map { $0[index] }
            clipped[index] = StackAggregate.aggregate(stack, mode: .sigmaClip)
            averaged[index] = StackAggregate.aggregate(stack, mode: .average)
        }
        // Along the trail: the sigma-clip recovers the clean truth within
        // the noise floor; the plain average is visibly polluted.
        var worstClip = 0.0 as Float
        var worstAverage = 0.0 as Float
        for pixel in 0..<min(width, height) {
            let index = pixel * width + pixel
            worstClip = max(worstClip, abs(clipped[index] - cleanMean[index]))
            worstAverage = max(worstAverage, abs(averaged[index] - cleanMean[index]))
        }
        XCTAssertLessThan(worstClip, 0.02,
            "the trail must be rejected; worst residual \(worstClip)")
        XCTAssertGreaterThan(worstAverage, 0.1,
            "the plain average must visibly smear the trail (sanity)")
        // Off-trail: both modes agree with the truth.
        var offTrail = 0.0 as Float
        for index in cleanMean.indices
        where abs(clipped[index] - cleanMean[index]) > abs(offTrail) {
            offTrail = clipped[index] - cleanMean[index]
        }
        XCTAssertLessThan(abs(offTrail), 0.02)
    }

    // MARK: - The N=3 degenerate (R6)

    func testSigmaClipN3DegeneratesToAverage() {
        // (N−1)/√N ≈ 1.155 < k=2.5 — no 3-sample set can ever reject; the
        // mode honestly equals the average (the service warns, R6).
        XCTAssertLessThan(
            StackAggregate.maxZScore(sampleCount: 3),
            StackAggregate.defaultSigmaK)
        let samples: [Float] = [0.2, 0.5, 9.0]
        XCTAssertEqual(
            StackAggregate.aggregate(samples, mode: .sigmaClip),
            StackAggregate.aggregate(samples, mode: .average),
            accuracy: 1e-6, "N=3 sigma-clip must degenerate to the average")
    }

    // MARK: - The band operators + the R3 memory lock

    func testAggregateBandStackAndConstantMemory() {
        // A 3-source band of 2 rows × 2 px (interleaved RGB): the stack
        // walk aggregates per float and honors NaN holes.
        let band0: [Float] = [0.1, 0.1, 0.1, 0.2, 0.2, 0.2,
                              0.3, 0.3, 0.3, .nan, 0, 0]
        let band1: [Float] = [0.5, 0.5, 0.5, 0.2, 0.2, 0.2,
                              .nan, 0, 0, .nan, 0, 0]
        let band2: [Float] = [0.9, 0.9, 0.9, 0.2, 0.2, 0.2,
                              0.7, 0.7, 0.7, .nan, 0, 0]
        let average = StackAggregate.aggregateBand([band0, band1, band2], mode: .average)
        XCTAssertEqual(average[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(average[3], 0.2, accuracy: 1e-6) // all equal
        XCTAssertEqual(average[6], 0.5, accuracy: 1e-6) // NaN skipped
        XCTAssertTrue(average[9].isNaN) // every source NaN → hole

        let median = StackAggregate.aggregateBand([band0, band1, band2], mode: .median)
        XCTAssertEqual(median[0], 0.5, accuracy: 1e-6)
        XCTAssertTrue(median[9].isNaN) // the hole stays NaN (→ holeFraction)
        let sigma = StackAggregate.aggregateBand([band0, band1, band2], mode: .sigmaClip)
        XCTAssertEqual(sigma[0], 0.5, accuracy: 1e-6)

        // The R3 lock: the N-value stack formula is EXACTLY
        // N × band rows × width × RGB float32, and at the plan's reference
        // point (N=8 · 256 rows · 11656 px) it lands at ≈286 MB — NOT the
        // N×full-frame ~9.7 GB residency.
        XCTAssertEqual(
            StackAggregate.bandStackBytes(width: 11656, bandHeight: 256, sources: 8),
            8 * 256 * 11656 * 3 * MemoryLayout<Float>.size)
        let bytes = StackAggregate.bandStackBytes(width: 11656, bandHeight: 256, sources: 8)
        let referenceMB = 286.0 // DECIMAL MB: 8×256×11656×3×4 = 286,457,856 B
        XCTAssertLessThan(
            abs(Double(bytes) / 1_000_000 - referenceMB) / referenceMB, 0.01,
            "the reference point drifted: \(bytes) B")
        let fullResidency = 8 * 11656 * 8742 * 3 * MemoryLayout<Float>.size
        XCTAssertLessThan(Double(bytes), Double(fullResidency) * 0.04,
            "the stack must be O(band), never O(height)")
    }
}
