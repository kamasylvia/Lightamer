import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// DepthMaskPipelineTests (M4-3-01 T2, KD-4) — the four-stage pure core.
//
// ANCHORING: `percentile` is pinned against uv/numpy-computed reference
// values (independent derivation; L048 discipline — never re-typed from
// the production body). The full pipeline is compared against a
// Double-precision reference implementation of Lumen selection.py:71-74
// applied to the same F32 input.
//
// TOLERANCE DERIVATION (L048): inputs are raw F32 planes, compared through
// `Double(Float(x))`. The smoothstep stage bounds dα/dp ≤ 1.5/windowSpan
// ≈ 6.8 per unit relative; the F32 noise floor is ~1e-6 (percentile lerp +
// input rounding), so 1e-4 absorbs both with >100× headroom. The window-
// band brackets use one CELL of slack (the ramp's v-spacing mapped through
// the normalize stage) — the assertion pins the BAND, not sub-cell phase.
// ─────────────────────────────────────────────────────────────────────────────

final class DepthMaskPipelineTests: XCTestCase {

    // MARK: percentile — numpy anchors (uv run numpy, 2026-10-10)

    /// Hard-coded numpy references:
    ///   [1..10]        q10 → 1.9    q95 → 9.55
    ///   [10,20,30,40]  q10 → 13.0   q95 → 38.5    (even length)
    ///   [5,5,5,5,9,9,9] q10 → 5.0   q95 → 9.0     (duplicates)
    ///   [0,10]         q25 → 2.5    q50 → 5.0     (rank between elements)
    ///   [7]            q10 → 7.0    q95 → 7.0     (single)
    func testPercentileNumpyAnchors() {
        let seq = (1...10).map(Float.init)
        XCTAssertEqual(DepthMaskPipeline.percentile(seq, 10) ?? -1, 1.9, accuracy: 1e-6)
        XCTAssertEqual(DepthMaskPipeline.percentile(seq, 95) ?? -1, 9.55, accuracy: 1e-6)

        let even: [Float] = [10, 20, 30, 40]
        XCTAssertEqual(DepthMaskPipeline.percentile(even, 10) ?? -1, 13.0, accuracy: 1e-6)
        XCTAssertEqual(DepthMaskPipeline.percentile(even, 95) ?? -1, 38.5, accuracy: 1e-6)

        let dups: [Float] = [5, 5, 5, 5, 9, 9, 9]
        XCTAssertEqual(DepthMaskPipeline.percentile(dups, 10) ?? -1, 5.0, accuracy: 1e-6)
        XCTAssertEqual(DepthMaskPipeline.percentile(dups, 95) ?? -1, 9.0, accuracy: 1e-6)

        let pair: [Float] = [0, 10]
        XCTAssertEqual(DepthMaskPipeline.percentile(pair, 25) ?? -1, 2.5, accuracy: 1e-6)
        XCTAssertEqual(DepthMaskPipeline.percentile(pair, 50) ?? -1, 5.0, accuracy: 1e-6)

        let single: [Float] = [7]
        XCTAssertEqual(DepthMaskPipeline.percentile(single, 10) ?? -1, 7.0, accuracy: 1e-6)
        XCTAssertEqual(DepthMaskPipeline.percentile(single, 95) ?? -1, 7.0, accuracy: 1e-6)

        XCTAssertNil(DepthMaskPipeline.percentile([], 10), "empty = nil, never a trap")
    }

    // MARK: The two-level synthetic target (checker m6 form: near ≥ 10%)

    /// Near rect 20×21 of 4,096 (10.25% — m6: BELOW 5% would drag the p95
    /// back into the far grays and turn this golden into the negative
    /// branch). far 0.2 / near 0.9 → α exactly 0 / 1 through the pipeline.
    func testTwoLevelTargetForegroundBackgroundCoverage() throws {
        let size = 64
        let nearRect = (x: 0..<20, y: 0..<21)  // 420 px = 10.25%
        var floats = [Float](repeating: 0.2, count: size * size)
        for y in nearRect.y where y < size {
            for x in nearRect.x where x < size {
                floats[y * size + x] = 0.9
            }
        }
        let alpha = try DepthMaskPipeline.nearMask(
            depth: AIMaskPlane(width: size, height: size, floats: floats))

        // ① foreground hit: every near-rect pixel ≈ 1.
        for y in 0..<21 where y < size {
            for x in 0..<20 {
                XCTAssertEqual(
                    Double(Float(alpha.floats[y * size + x])), 1.0, accuracy: 0.01,
                    "near pixel (\(x),\(y)) must be foreground")
            }
        }
        // ② background zero-damage: every far pixel ≈ 0.
        for (index, value) in alpha.floats.enumerated() {
            let x = index % size, y = index / size
            if y < 21 && x < 20 { continue }
            XCTAssertLessThanOrEqual(
                Double(Float(value)), 0.01,
                "far pixel (\(x),\(y)) must be untouched")
        }
        // ③ (m6: the window-transition assertion is carried by the ramp
        // fixture below — a two-level plane has no in-band pixels.)
        XCTAssertEqual(alpha.width, size)
        XCTAssertEqual(alpha.height, size)
    }

    // MARK: Ramp — monotonicity, window band position, full-pipeline golden

    /// A sorted 0…1 ramp (v_i = i/999): monotonic α; the α∈(0,1) band sits
    /// inside relative [0.48−cell, 0.70+cell]; every pixel matches the
    /// Double reference within the L048 tolerance.
    func testRampMonotonicBandAndDoubleReferenceGolden() throws {
        let n = 1000
        let v = (0..<n).map { Float($0) / 999 }
        let alpha = try DepthMaskPipeline.nearMask(
            depth: AIMaskPlane(width: n, height: 1, floats: v))

        // Monotonic along the ascending ramp (F32 noise headroom).
        for i in 1..<n {
            XCTAssertGreaterThanOrEqual(
                alpha.floats[i], alpha.floats[i - 1] - 1e-7,
                "α must not decrease at i=\(i)")
        }

        // Double reference (independent re-derivation of :71-74).
        func percentileRef(_ q: Double) -> Double {
            let rank = q / 100 * Double(n - 1)
            let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
            if lo == hi { return Double(v[lo]) }
            let f = rank - Double(lo)
            return Double(v[lo]) * (1 - f) + Double(v[hi]) * f
        }
        let low = percentileRef(10), high = percentileRef(95)
        let range = max(high - low, 1e-6)
        // One v-cell through the normalize stage = relative slack.
        let cellRelative = (1.0 / 999.0) / range

        var inBandSeen = false
        for i in 0..<n {
            let relative = (Double(v[i]) - low) / range
            let windowed = min(max((relative - 0.48) / 0.22, 0), 1)
            let expected = windowed * windowed * (3 - 2 * windowed)
            XCTAssertEqual(
                Double(Float(alpha.floats[i])), expected, accuracy: 1e-4,
                "pipeline α at i=\(i)")
            // Band position: outside [0.48−cell, 0.70+cell] the mask must
            // be saturated; inside the inner band it must be soft.
            if relative < 0.48 - cellRelative {
                XCTAssertLessThanOrEqual(Double(Float(alpha.floats[i])), 1e-6)
            }
            if relative > 0.70 + cellRelative {
                XCTAssertGreaterThanOrEqual(Double(Float(alpha.floats[i])), 1 - 1e-6)
            }
            if relative > 0.48 + cellRelative && relative < 0.70 - cellRelative {
                inBandSeen = true
                XCTAssertGreaterThan(Double(Float(alpha.floats[i])), 0)
                XCTAssertLessThan(Double(Float(alpha.floats[i])), 1)
            }
        }
        XCTAssertTrue(inBandSeen, "the ramp must cross the (0.48, 0.70) window")
    }

    /// Parameter scan (OQ-4 seam): shifting `windowStart` shifts the
    /// transition band — pure-function replay, zero re-inference.
    func testWindowStartShiftMovesTheBand() throws {
        let n = 1000
        let v = (0..<n).map { Float($0) / 999 }
        let base = try DepthMaskPipeline.nearMask(
            depth: AIMaskPlane(width: n, height: 1, floats: v))
        let shifted = try DepthMaskPipeline.nearMask(
            depth: AIMaskPlane(width: n, height: 1, floats: v), windowStart: 0.60)
        // Every saturated-pixel boundary moves RIGHT (fewer/nearer pixels).
        let firstNear = { (plane: AIMaskPlane) in plane.floats.firstIndex { $0 > 0.5 } }
        XCTAssertGreaterThan(
            firstNear(shifted) ?? n, firstNear(base) ?? 0,
            "higher windowStart must move the near boundary toward far pixels")
        XCTAssertNotEqual(base.byteIdentity, shifted.byteIdentity)
    }

    // MARK: Typed guards (D-2: throw, NEVER an all-ones plane)

    func testFlatDepthThrowsDegenerateTyped() {
        let floats = [Float](repeating: 0.5, count: 64 * 64)
        XCTAssertThrowsError(
            try DepthMaskPipeline.nearMask(
                depth: AIMaskPlane(width: 64, height: 64, floats: floats))
        ) { error in
            guard case AIMaskError.noDepthStructure(let message) = error else {
                return XCTFail("expected noDepthStructure, got \(error)")
            }
            XCTAssertTrue(message.contains("degenerate"), "guard (a) message: \(message)")
        }
    }

    /// Guard (b) — the coverage floor, exercised deterministically through
    /// the parameter seam. MATH NOTE (verified in-suite, DECISIONS §3): for
    /// any plane that passes guard (a), mass at v ≥ p95 is ≥ ~5% and those
    /// pixels saturate α=1 — so with the DEFAULT 3e-4 floor the (b) branch
    /// is a NaN backstop only (Lumen's guard is reachable because its
    /// guided-filter refine runs BEFORE the count; ours counts the raw
    /// smoothstep plane). The seam parameter is the testable face.
    func testNearEmptyCoverageThrowsTyped() throws {
        let n = 4096
        let v = (0..<n).map { Float($0) / Float(n - 1) }  // full ramp, coverage ≈ 41%
        XCTAssertThrowsError(
            try DepthMaskPipeline.nearMask(
                depth: AIMaskPlane(width: n, height: 1, floats: v),
                coverageFloor: 0.9)
        ) { error in
            guard case AIMaskError.noDepthStructure(let message) = error else {
                return XCTFail("expected noDepthStructure, got \(error)")
            }
            XCTAssertTrue(message.contains("covers"), "guard (b) message: \(message)")
        }
        // The default floor lands the same plane (real-world face).
        let alpha = try DepthMaskPipeline.nearMask(
            depth: AIMaskPlane(width: n, height: 1, floats: v))
        XCTAssertGreaterThan(alpha.floats[n - 1], 0.99)
    }

    /// NaN inputs: percentile propagates, every (α>0.5) comparison is
    /// false → guard (b) throws — the pipeline NEVER returns an all-NaN
    /// plane. (The worker's isfinite gate attributes NaN to
    /// inferenceFailed BEFORE this face — m3; the two are orthogonal.)
    func testNaNInputThrowsTypedNeverReturnsPlane() {
        var floats = [Float](repeating: 0.3, count: 256)
        floats[128] = Float.nan
        XCTAssertThrowsError(
            try DepthMaskPipeline.nearMask(
                depth: AIMaskPlane(width: 16, height: 16, floats: floats))
        ) { error in
            guard case AIMaskError.noDepthStructure = error else {
                return XCTFail("expected noDepthStructure, got \(error)")
            }
        }
    }

    // MARK: Purity (D-3)

    func testByteIdentityDeterminismAndPurity() throws {
        let size = 48
        let floats = (0..<(size * size)).map {
            Float(($0 * 2654435761) % 1000) / 1000  // deterministic hash scatter
        }
        let plane = AIMaskPlane(width: size, height: size, floats: floats)
        let first = try DepthMaskPipeline.nearMask(depth: plane)
        let second = try DepthMaskPipeline.nearMask(depth: plane)
        XCTAssertEqual(first.byteIdentity, second.byteIdentity, "same input → byte identity")
        XCTAssertNotEqual(first.byteIdentity, plane.byteIdentity)
        // Empty plane → typed invalidInput (not a trap).
        XCTAssertThrowsError(
            try DepthMaskPipeline.nearMask(
                depth: AIMaskPlane(width: 0, height: 0, floats: []))
        ) { error in
            XCTAssertEqual(error as? AIMaskError, .invalidInput("empty depth plane"))
        }
    }
}
