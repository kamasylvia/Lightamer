@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoGainTests (Plan M5-3-02 T2; KD-11 G3③) — the exposure-gain segment's
// gates:
//
// G3③ synthetic equation-system recovery: known gains synthesized into the
// sample planes → the joint solve recovers them (exact ratios → the band is
// machine-precision; the measured value pins), the reference anchor holds,
// the clip ceiling clamps ±0.6-demands to e^±0.5 with the warning flag, the
// disconnected image keeps identity (the checker-O2 min-norm semantics),
// the <80-sample and value-gate exclusions hold, and the whole face runs
// bit-identical twice.
// ─────────────────────────────────────────────────────────────────────────────

final class PanoGainTests: XCTestCase {

    // MARK: - Fixtures

    private let canvas = (width: 40, height: 40)

    /// A deterministic base luma pattern strictly inside the value gates
    /// (0.2 ..< 0.7) — the gain synthesis multiplies it per image.
    private func baseLuma(_ pixel: Int) -> Double {
        0.2 + 0.5 * Double((pixel &* 7919) % 1024) / 1024.0
    }

    private func plane(
        gain: Double, valid: (Int) -> Bool
    ) -> PanoGainSamplePlane {
        let count = canvas.width * canvas.height
        var luma = [Float](repeating: 0, count: count)
        var mask = [Bool](repeating: false, count: count)
        for pixel in 0..<count {
            guard valid(pixel) else { continue }
            mask[pixel] = true
            luma[pixel] = Float(baseLuma(pixel) * gain)
        }
        return PanoGainSamplePlane(
            width: canvas.width, height: canvas.height, luma: luma,
            valid: mask)
    }

    // MARK: - G3③: synthetic recovery

    func testSyntheticEquationSystemRecovery() {
        // Four images, one shared gain field: luma_i = base·g_i on the
        // common valid region → every pairwise ratio is exactly g_j/g_i.
        let truth = [1.0, 1.25, 0.8, 1.1]
        let planes = (0..<4).map { index in
            plane(gain: truth[index], valid: { _ in true })
        }
        let (gains, clipped) = PanoGain.gains(planes: planes, reference: 0)
        XCTAssertFalse(clipped)
        // The Lumen gains are COMPENSATION multipliers: a brighter image
        // (g_i > 1) fuses with gain 1/g_i (merge.py:274 accum += warped ×
        // (α·gain) normalizes brightness). The solve recovers 1/g_i.
        for index in truth.indices {
            XCTAssertEqual(
                gains[index], 1 / truth[index], accuracy: 1e-6,
                "gain \(index): \(gains[index]) vs 1/\(truth[index])")
        }
        // The reference pin: the anchor row holds the reference at 1.
        XCTAssertEqual(gains[0], 1.0, accuracy: 1e-12)
    }

    func testReferenceAnchorPin() {
        // The equations' last row is the anchor (weight 10 at reference,
        // value 0) — inspected directly.
        let planes = (0..<3).map { index in
            plane(gain: 1.0 + 0.1 * Double(index), valid: { _ in true })
        }
        let (matrix, values) = PanoGain.equations(
            from: planes, reference: 1)
        let anchor = matrix.last!
        XCTAssertEqual(anchor[1], PanoGain.anchorWeight)
        XCTAssertEqual(anchor[0], 0)
        XCTAssertEqual(anchor[2], 0)
        XCTAssertEqual(values.last!, 0)
        // Pairwise rows carry the +1/−1 form.
        let firstRow = matrix[0]
        let signs = firstRow.filter { $0 != 0 }
        XCTAssertEqual(signs, [1, -1])
    }

    // MARK: - Gate floors (KD-6)

    func testBelowSampleFloorYieldsNoEquation() {
        // 79 valid overlap samples (< 80): the pair must not enter the
        // system — only the anchor row remains.
        var admitted = 0
        let planes: [PanoGainSamplePlane] = [
            plane(gain: 1.0, valid: { _ in true }),
            plane(gain: 1.3, valid: { _ in
                admitted += 1
                return admitted <= 79
            }),
        ]
        let (matrix, _) = PanoGain.equations(from: planes, reference: 0)
        XCTAssertEqual(matrix.count, 1, "the anchor only")
        // Min-norm on the anchor alone → the free variable resolves to 0.
        let (gains, clipped) = PanoGain.gains(planes: planes, reference: 0)
        XCTAssertFalse(clipped)
        XCTAssertEqual(gains[1], 1.0, accuracy: 1e-12)
    }

    func testAtSampleFloorYieldsEquation() {
        // Exactly 80 valid in-gate overlap samples: the pair enters.
        var admitted = 0
        let planes: [PanoGainSamplePlane] = [
            plane(gain: 1.0, valid: { _ in true }),
            plane(gain: 1.2, valid: { _ in
                admitted += 1
                return admitted <= 80
            }),
        ]
        let (matrix, _) = PanoGain.equations(from: planes, reference: 0)
        XCTAssertEqual(matrix.count, 2, "one pairwise row + the anchor")
    }

    func testValueGatesExcludeOutOfBandSamples() {
        // The overlap holds 600 valid samples but only 100 of them keep
        // BOTH luma values inside (0.04, 0.9): the equation counts 100.
        let count = canvas.width * canvas.height
        func mixedPlane(gain: Double, inBandLimit: Int)
            -> PanoGainSamplePlane
        {
            var luma = [Float](repeating: 0, count: count)
            var mask = [Bool](repeating: false, count: count)
            for pixel in 0..<count {
                mask[pixel] = true
                var value = baseLuma(pixel) * gain
                if pixel >= inBandLimit {
                    // Out-of-band (≥ gateHigh) — excluded by the gates.
                    value = 0.95
                }
                luma[pixel] = Float(value)
            }
            return PanoGainSamplePlane(
                width: canvas.width, height: canvas.height, luma: luma,
                valid: mask)
        }
        let planes = [
            mixedPlane(gain: 1.0, inBandLimit: Int.max),
            mixedPlane(gain: 1.2, inBandLimit: 100),
        ]
        let (matrix, _) = PanoGain.equations(from: planes, reference: 0)
        XCTAssertEqual(matrix.count, 2, "100 in-gate samples ≥ 80 → enters")
        // The recovered ratio rides ONLY the in-band samples.
        let (gains, _) = PanoGain.gains(planes: planes, reference: 0)
        XCTAssertEqual(gains[1], 1 / 1.2, accuracy: 1e-6)
    }

    func testStrictGateBoundariesExcluded() {
        // Values exactly AT 0.04 / 0.9 are excluded (open interval).
        let count = 4
        func boundaryPlane(_ value: Float) -> PanoGainSamplePlane {
            PanoGainSamplePlane(
                width: 2, height: 2,
                luma: [Float](repeating: value, count: count),
                valid: [Bool](repeating: true, count: count))
        }
        let planes = [boundaryPlane(0.5), boundaryPlane(0.9)]
        let (matrix, _) = PanoGain.equations(from: planes, reference: 0)
        XCTAssertEqual(matrix.count, 1, "all samples at the high gate → no row")
        let lowPlanes = [boundaryPlane(0.5), boundaryPlane(0.04)]
        let (lowMatrix, _) = PanoGain.equations(
            from: lowPlanes, reference: 0)
        XCTAssertEqual(lowMatrix.count, 1, "the low gate is strict too")
    }

    // MARK: - The clip ceiling (KD-6)

    func testClipCeilingAndWarningFlag() {
        // A pair demanding log-gain 0.6 (> 0.5): the solution clamps and
        // the warning flag rises. g = [1, e^0.6] → the anchor + the ratio
        // row → x = [0, 0.6] → clamped to [0, 0.5].
        let demanding = exp(0.6)
        let planes = [
            plane(gain: 1.0, valid: { _ in true }),
            plane(gain: demanding, valid: { _ in true }),
        ]
        let (gains, clipped) = PanoGain.gains(planes: planes, reference: 0)
        XCTAssertTrue(clipped)
        XCTAssertEqual(gains[0], 1.0, accuracy: 1e-12)
        // The brighter image's COMPENSATION clamps at e^−0.5.
        XCTAssertEqual(gains[1], exp(-PanoGain.clipLimit), accuracy: 1e-12)
    }

    func testNegativeSideClipCeiling() {
        // The mirror: log-gain −0.6 → clamped to −0.5 (e^−0.5 ≈ 0.6065).
        let demanding = exp(-0.6)
        let planes = [
            plane(gain: 1.0, valid: { _ in true }),
            plane(gain: demanding, valid: { _ in true }),
        ]
        let (gains, clipped) = PanoGain.gains(planes: planes, reference: 0)
        XCTAssertTrue(clipped)
        // The darker image's compensation clamps at e^+0.5.
        XCTAssertEqual(gains[1], exp(PanoGain.clipLimit), accuracy: 1e-12)
    }

    // MARK: - The disconnected image (checker O2)

    func testDisconnectedImageKeepsIdentityGain() {
        // Image 2's valid samples share NO pixel with the others (its mask
        // covers the region the others leave invalid): its column is
        // all-zero → the min-norm solve resolves it to gain 1 — the
        // merge.py:257-258 no-silent-loss semantics.
        let count = canvas.width * canvas.height
        let planes: [PanoGainSamplePlane] = [
            plane(gain: 1.0, valid: { $0 < count / 2 }),
            plane(gain: 1.2, valid: { $0 < count / 2 }),
            plane(gain: 1.4, valid: { $0 >= count / 2 }),
        ]
        let (gains, clipped) = PanoGain.gains(planes: planes, reference: 0)
        XCTAssertFalse(clipped)
        XCTAssertEqual(gains[0], 1.0, accuracy: 1e-12)
        XCTAssertEqual(gains[1], 1 / 1.2, accuracy: 1e-6)
        XCTAssertEqual(gains[2], 1.0, accuracy: 1e-12)
    }

    // MARK: - Determinism

    func testSolveRunsBitIdenticalTwice() {
        let truth = [1.0, 0.85, 1.3, 1.05, 0.92]
        let planes = (0..<5).map { index in
            plane(gain: truth[index], valid: { $0 % 3 != 2 })
        }
        let first = PanoGain.gains(planes: planes, reference: 0)
        let second = PanoGain.gains(planes: planes, reference: 0)
        XCTAssertEqual(first.clipped, second.clipped)
        for index in first.gains.indices {
            XCTAssertEqual(
                first.gains[index].bitPattern,
                second.gains[index].bitPattern, "gain \(index) diverged")
        }
    }

    // MARK: - The sample canvas (merge.py:259-260)

    func testSampleCanvasSizeCappedAt900() {
        let capped = PanoGain.sampleCanvasSize(
            canvasWidth: 20000, canvasHeight: 10000)
        XCTAssertEqual(capped.width, 900)
        XCTAssertEqual(capped.height, 450)
        let small = PanoGain.sampleCanvasSize(canvasWidth: 800, canvasHeight: 600)
        XCTAssertEqual(small.width, 800)
        XCTAssertEqual(small.height, 600)
        let tiny = PanoGain.sampleCanvasSize(canvasWidth: 1, canvasHeight: 1)
        XCTAssertEqual(tiny.width, 1)
        XCTAssertEqual(tiny.height, 1)
    }

    func testSamplePlaneGatherMatchesManualBilinear() throws {
        // A small synthetic source; the sampled luma must equal a manual
        // bilinear Rec709 gather at the same mapped coordinates, and the
        // validity mask must match the Lumen gate (1 ≤ mx < w−2).
        let sourceWidth = 32
        let sourceHeight = 24
        var source = [Float](repeating: 0, count: sourceWidth * sourceHeight * 4)
        for pixel in 0..<(sourceWidth * sourceHeight) {
            let value = Float(baseLuma(pixel))
            source[pixel * 4] = value
            source[pixel * 4 + 1] = value
            source[pixel * 4 + 2] = value
            source[pixel * 4 + 3] = 1
        }
        let geometry = PanoSourceGeometry(
            width: sourceWidth, height: sourceHeight, focal: 40,
            rotation: Mat3D.identity)
        let sampleWidth = 10
        let sampleHeight = 8
        let plane = try PanoGain.samplePlane(
            rectX: 3, rectY: 2, width: sampleWidth, height: sampleHeight,
            scale: 40, source: geometry,
            rowReader: { first, count in
                let start = first * sourceWidth * 4
                return Array(
                    source[start..<(start + count * sourceWidth * 4)])
            })
        // Manual check at a handful of points.
        let (mx, my) = PanoWarp.sphericalMap(
            rectX: 3, rectY: 2, width: sampleWidth, height: sampleHeight,
            scale: 40, source: geometry)
        let cr = MertensFusion.grayCoefficients.r
        let cg = MertensFusion.grayCoefficients.g
        let cb = MertensFusion.grayCoefficients.b
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let index = y * sampleWidth + x
                let gate = mx[index] >= 1 && my[index] >= 1
                    && mx[index] < Float(sourceWidth - 2)
                    && my[index] < Float(sourceHeight - 2)
                XCTAssertEqual(plane.valid[index], gate, "(\(x),\(y)) gate")
                guard gate else { continue }
                let ix = min(Int(mx[index]), sourceWidth - 2)
                let fx = mx[index] - Float(ix)
                let iy = min(Int(my[index]), sourceHeight - 2)
                let fy = my[index] - Float(iy)
                func gray(_ px: Int, _ py: Int) -> Float {
                    let base = (py * sourceWidth + px) * 4
                    return cr * source[base] + cg * source[base + 1]
                        + cb * source[base + 2]
                }
                let top = gray(ix, iy) * (1 - fx) + gray(ix + 1, iy) * fx
                let bottom = gray(ix, iy + 1) * (1 - fx)
                    + gray(ix + 1, iy + 1) * fx
                let expected = top * (1 - fy) + bottom * fy
                XCTAssertEqual(
                    plane.luma[index], expected, accuracy: 1e-6,
                    "(\(x),\(y)) luma")
            }
        }
    }

    func testSamplePlaneRunsBitIdenticalTwice() throws {
        let sourceWidth = 48
        let sourceHeight = 36
        var source = [Float](repeating: 0, count: sourceWidth * sourceHeight * 4)
        var state: UInt64 = 7
        for index in source.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            source[index] = Float(Double(state >> 11) / 9_007_199_254_740_992.0)
                * 0.6 + 0.2
        }
        let geometry = PanoSourceGeometry(
            width: sourceWidth, height: sourceHeight, focal: 50,
            rotation: PanoCamera.rotation(fromAxisAngle: SIMD3(0, 0.2, 0)))
        func run() throws -> PanoGainSamplePlane {
            try PanoGain.samplePlane(
                rectX: -2, rectY: 1, width: 12, height: 9, scale: 50,
                source: geometry, rowReader: { first, count in
                    let start = first * sourceWidth * 4
                    return Array(
                        source[start..<(start + count * sourceWidth * 4)])
                })
        }
        let first = try run()
        let second = try run()
        for index in first.luma.indices {
            XCTAssertEqual(
                first.luma[index].bitPattern, second.luma[index].bitPattern)
        }
        XCTAssertEqual(first.valid, second.valid)
    }
}
