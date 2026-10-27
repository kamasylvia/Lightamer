@testable import LightamerCore
import XCTest

/// AIMaskPathSamplingTests (M9-1 T3, D-M9A-6) — the Path tool's stroke
/// math: the equal-arc-length 24px resample (start included, the tail
/// under one interval dropped), the min(16, headroom) fold over our
/// 13/11 budgets, and the short-stroke degenerate (a single point).
final class AIMaskPathSamplingTests: XCTestCase {

    /// A straight 240px stroke at 24px spacing → exactly 11 samples at
    /// 0, 24, …, 240 (equal arc length, endpoints at the interval
    /// lattice; the 12th interval would need 264px).
    func testStraightStrokeSamplesAt24PxLattice() {
        let stroke = (0...10).map { SIMD2<Float>(Float($0) * 24.0, 40.0) }
        let samples = AIMaskPathSampling.sampleStroke(
            stroke: stroke, count: 16, imageWidth: 480, imageHeight: 320)
        XCTAssertEqual(samples.count, 11)
        for (index, sample) in samples.enumerated() {
            XCTAssertEqual(
                Double(sample.x), Double(Float(index) * 24.0 / 480),
                accuracy: 1e-5,
                "sample \(index) sits on the 24px lattice")
            XCTAssertEqual(Double(sample.y), Double(40.0 / 320), accuracy: 1e-5)
        }
    }

    /// The normalized output: pixel → view-normalized top-left (the
    /// division by the image size; y grows downward).
    func testSamplesNormalizeAgainstImageSize() {
        let stroke: [SIMD2<Float>] = [
            SIMD2(100, 200), SIMD2(124, 200) // one exact interval
        ]
        let samples = AIMaskPathSampling.sampleStroke(
            stroke: stroke, count: 4, imageWidth: 200, imageHeight: 400)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(Double(samples[0].x), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(samples[0].y), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(samples[1].x), 0.62, accuracy: 1e-6)
    }

    /// A polyline: the arc length accumulates ACROSS segments — two
    /// 12px perpendicular legs sample at the 24px corner point exactly.
    func testArcLengthAccumulatesAcrossSegments() {
        let stroke: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(12, 0), SIMD2(12, 12), SIMD2(24, 12), SIMD2(24, 24)
        ]
        let samples = AIMaskPathSampling.sampleStroke(
            stroke: stroke, count: 4, imageWidth: 100, imageHeight: 100)
        // 0 → (12,0) → (12,12) = 24px arc → sample at the corner; then
        // (24,12) = 36, (24,24) = 48 → samples at arc 24 and 48.
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(Double(samples[1].x), 0.12, accuracy: 1e-5)
        XCTAssertEqual(Double(samples[1].y), 0.12, accuracy: 1e-5)
        XCTAssertEqual(Double(samples[2].x), 0.24, accuracy: 1e-5)
        XCTAssertEqual(Double(samples[2].y), 0.24, accuracy: 1e-5)
    }

    /// A short stroke (< 24px) yields exactly ONE point (the start) —
    /// never zero, never a forced end point.
    func testShortStrokeYieldsSingleStartPoint() {
        let stroke: [SIMD2<Float>] = [SIMD2(10, 10), SIMD2(20, 10)]
        let samples = AIMaskPathSampling.sampleStroke(
            stroke: stroke, count: 16, imageWidth: 100, imageHeight: 100)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(Double(samples[0].x), 0.1, accuracy: 1e-6)

        // The count cap: a degenerate one-point stroke is the same face.
        let single = AIMaskPathSampling.sampleStroke(
            stroke: [SIMD2(50, 50)], count: 16,
            imageWidth: 100, imageHeight: 100)
        XCTAssertEqual(single.count, 1)
    }

    /// The budget fold (D-M9A-6): min(16, headroom) — the upstream
    /// 16-point ceiling folded into our 13/11 Vision budgets. A
    /// point-seeded session's stroke (seed rides the first sample) has
    /// headroom 12; a box-seeded stroke has 11; a rich headroom (fresh
    /// box session) caps at 16.
    func testSampleCountFold() {
        XCTAssertEqual(AIMaskPathSampling.sampleCount(budgetHeadroom: 12), 12)
        XCTAssertEqual(AIMaskPathSampling.sampleCount(budgetHeadroom: 11), 11)
        XCTAssertEqual(AIMaskPathSampling.sampleCount(budgetHeadroom: 16), 16)
        XCTAssertEqual(AIMaskPathSampling.sampleCount(budgetHeadroom: 20), 16)
        XCTAssertEqual(AIMaskPathSampling.sampleCount(budgetHeadroom: 0), 0)
        // The constants in册 (the upstream behavior facts).
        XCTAssertEqual(AIMaskPathSampling.spacingPx, 24)
        XCTAssertEqual(AIMaskPathSampling.maxStrokePoints, 16)
    }

    /// The count cap TRUNCATES the tail (the resample respects the cap
    /// even when the stroke is long enough to fill 16 intervals).
    func testCountCapTruncates() {
        let stroke = (0...20).map { SIMD2<Float>(Float($0) * 24.0, 10.0) }
        let samples = AIMaskPathSampling.sampleStroke(
            stroke: stroke, count: 5, imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(samples.count, 5)
        XCTAssertEqual(Double(samples[4].x), Double(4 * 24) / 1000, accuracy: 1e-5)
    }
}
