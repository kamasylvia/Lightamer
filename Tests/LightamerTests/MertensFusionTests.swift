@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MertensFusionTests (Plan M5-2-01 T1) — the MertensFusion pure-function
// family: the DrtEotf display-encode seam (KD-1), the three-factor weight
// family, the quantile brightness mapping, the deghost tier table + usable
// gate (KD-3 incl. the merge.py:146 static fallback — checker minor-1),
// the substitute LUTs, and the adaptiveLevels/haloRows truth tables (KD-2).
//
// Fixtures are synthetic, in-code planes only — zero disk assets, zero
// shared-fixture writes (L074 temp-domain discipline is trivially satisfied:
// nothing here touches the filesystem).
// ─────────────────────────────────────────────────────────────────────────────

final class MertensFusionTests: XCTestCase {

    // MARK: - Fixture machinery

    /// Fixed-seed LCG texture per channel (distinct seeds → S > 0
    /// everywhere; white-noise curvature → C > 0 everywhere).
    private static func texture(
        _ width: Int, _ height: Int, seeds: (r: UInt64, g: UInt64, b: UInt64),
        low: Float = 0.1, high: Float = 0.9
    ) -> [Float] {
        func channel(_ seed: UInt64) -> [Float] {
            var state = seed &* 6364136223846793005 &+ 1442695040888963407
            var pixels = [Float](repeating: 0, count: width * height)
            for index in pixels.indices {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let uniform = Float((state >> 33) & 0xFFFFF) / Float(0xFFFFF)
                pixels[index] = low + (high - low) * uniform
            }
            return pixels
        }
        let r = channel(seeds.r), g = channel(seeds.g), b = channel(seeds.b)
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            rgba[index * 4] = r[index]
            rgba[index * 4 + 1] = g[index]
            rgba[index * 4 + 2] = b[index]
            rgba[index * 4 + 3] = 1
        }
        return rgba
    }

    /// A solid-value RGBA plane.
    private static func solid(
        _ value: Float, width: Int, height: Int
    ) -> [Float] {
        [Float](repeating: value, count: width * height * 4)
    }

    // MARK: - KD-1: the display-encode seam

    func testDisplayEncodeRoundTripWithinBandAndClamps() {
        // Sweep the operating range [0.004, 1] (float32 planes): the
        // round-trip through DrtEotf's exact piecewise pair holds ≤ 1e-6.
        var worst: Double = 0
        for step in 0..<128 {
            let value = 0.004 + 0.996 * Double(step) / 127
            let code = Float(DrtEotfMath.srgbPiecewiseEncode(value))
            let back = DrtEotfMath.srgbPiecewiseDecode(Double(code))
            worst = max(worst, abs(back - value))
            XCTAssertLessThanOrEqual(abs(back - value), 1e-6, "at \(value)")
        }
        // The clamp convention (KD-1): negatives floor to the black code,
        // superwhite clips at 1 — and decode agrees.
        XCTAssertEqual(Float(DrtEotfMath.srgbPiecewiseEncode(-0.5)), 0)
        XCTAssertEqual(Float(DrtEotfMath.srgbPiecewiseEncode(1.5)), 1, accuracy: 1e-12)
        XCTAssertEqual(Float(DrtEotfMath.srgbPiecewiseDecode(-3)), 0)
        XCTAssertEqual(Float(DrtEotfMath.srgbPiecewiseDecode(2)), 1, accuracy: 1e-12)
        // The plane wrappers round-trip the same way.
        let plane: [Float] = [0.02, 0.25, 0.5, 0.75, 0.98]
        let round = MertensFusion.displayDecodePlane(MertensFusion.displayEncodePlane(plane))
        for (index, value) in plane.enumerated() {
            XCTAssertEqual(round[index], value, accuracy: 1e-6)
        }
        print("LA-MEASURE mertens display round-trip worst \(worst)")
    }

    /// The IEC piecewise junction hairline: for linear values in the
    /// ~2e-6-wide band where encode lands a hair BELOW the 0.04045 code
    /// boundary while v sits above the 0.0031308 linear boundary, decode
    /// takes the other branch and the round-trip picks up the standard's
    /// junction rounding (≈1.5e-6 absolute). Recorded (DECISIONS): the
    /// plan's ≤1e-6 band holds on the operating range (the test above);
    /// the hairline is a measure-zero artifact of the IEC constants, not a
    /// fusion defect — the weights never consume values there.
    func testDisplayEncodeJunctionHairlineDocumented() {
        let hairline = 0.0031297
        let code = DrtEotfMath.srgbPiecewiseEncode(hairline)
        let back = DrtEotfMath.srgbPiecewiseDecode(code)
        XCTAssertLessThan(abs(back - hairline), 3e-6)
    }

    // MARK: - The weight family (four properties)

    func testWeightFamilyGeometricProductAnchorsAndSymmetry() {
        let width = 24, height = 16
        let rgba = Self.texture(width, height, seeds: (0xA1, 0xB2, 0xC3))
        let gray = MertensFusion.grayPlane(rgba, width: width, height: height)
        let contrast = MertensFusion.contrastPlane(gray, width: width, height: height)
        let saturation = MertensFusion.saturationPlane(rgba, width: width, height: height)
        let exposure = MertensFusion.exposureFitPlane(rgba, width: width, height: height)
        let weight = MertensFusion.weightPlane(rgba, width: width, height: height)

        // ① The geometric product decomposition (exponents = 1.0): W == C·S·E.
        for index in weight.indices {
            let expected = contrast[index] * saturation[index] * exposure[index]
            XCTAssertEqual(weight[index], expected, accuracy: abs(expected) * 1e-5 + 1e-12)
        }
        // ② The σ-parameterized identity: a mid-gray pixel has E == 1.
        let mid = MertensFusion.exposureFitPlane(
            Self.solid(0.5, width: 2, height: 2), width: 2, height: 2)
        for value in mid where abs(value - 1) > 1e-7 {
            XCTFail("mid-gray exposure fit must be 1, got \(value)")
        }
        // ③ Saturation: a channel-equal (gray) pixel has S == 0 exactly.
        let grayPlaneSat = MertensFusion.saturationPlane(
            Self.solid(0.42, width: 2, height: 2), width: 2, height: 2)
        for value in grayPlaneSat {
            XCTAssertEqual(value, 0, accuracy: 1e-9)
        }
        // ④ Exposure-fit symmetry: E(0.5+d) == E(0.5−d) per channel.
        let left = MertensFusion.exposureFitPlane(
            Self.solid(0.3, width: 1, height: 1), width: 1, height: 1)[0]
        let right = MertensFusion.exposureFitPlane(
            Self.solid(0.7, width: 1, height: 1), width: 1, height: 1)[0]
        XCTAssertEqual(left, right, accuracy: 1e-6)
        // And the paper's σ=0.2 anchor, per channel (the factor is the
        // PRODUCT over the three channels — a flat white pixel cubes the
        // per-channel exp(−3.125) ≈ 0.0439; the KD-7③ correction basis:
        // no true zero, suppression semantics).
        let white = MertensFusion.exposureFitPlane(
            Self.solid(1.0, width: 1, height: 1), width: 1, height: 1)[0]
        let perChannel = Foundation.exp(-3.125)
        XCTAssertEqual(Double(white), perChannel * perChannel * perChannel, accuracy: 1e-9)
    }

    // MARK: - The quantile brightness mapping

    func testQuantileBrightnessMappingMonotoneAndClamps() {
        let width = 64, height = 48
        // Reference: mid-tones; frame: the same shape darkened (a monotone
        // tone shift) — the mapping must be monotone non-decreasing with
        // increasing xs, and interp must clamp at the ends.
        let referenceGray: [Float] = (0..<(width * height)).map {
            0.2 + 0.6 * Float($0 % width) / Float(width - 1)
        }
        let frameGray = referenceGray.map { $0 * 0.5 }
        let mapping = MertensFusion.brightnessMapping(
            frameGray: frameGray, referenceGray: referenceGray,
            width: width, height: height)
        XCTAssertEqual(mapping.xs.count, 33)
        XCTAssertEqual(mapping.ys.count, 33)
        for index in 1..<mapping.xs.count {
            XCTAssertGreaterThan(mapping.xs[index], mapping.xs[index - 1],
                "unique percentile xs must strictly increase")
            XCTAssertGreaterThanOrEqual(
                mapping.ys[index], mapping.ys[index - 1],
                "the reference targets must not decrease")
        }
        // A darkened frame maps its dark percentiles up to the reference's.
        XCTAssertGreaterThan(mapping.ys[16], mapping.xs[16],
            "darkening shifts percentiles up toward the reference")
        // interp clamps outside the table.
        let below = MertensFusion.interp(-1, xs: mapping.xs, ys: mapping.ys)
        let above = MertensFusion.interp(2, xs: mapping.xs, ys: mapping.ys)
        XCTAssertEqual(below, mapping.ys[0])
        XCTAssertEqual(above, mapping.ys[mapping.ys.count - 1])
    }

    // MARK: - The deghost tier table + usable gate (checker minor-1 tier)

    func testDeghostTierTableAndUsableGate() {
        // The three tiers transplanted verbatim (merge.py:122).
        XCTAssertEqual(MertensFusion.DeghostLevel.low.residualThreshold, 0.20)
        XCTAssertEqual(MertensFusion.DeghostLevel.low.baseDilateRadius, 2)
        XCTAssertEqual(MertensFusion.DeghostLevel.medium.residualThreshold, 0.12)
        XCTAssertEqual(MertensFusion.DeghostLevel.medium.baseDilateRadius, 5)
        XCTAssertEqual(MertensFusion.DeghostLevel.high.residualThreshold, 0.065, accuracy: 1e-7)
        XCTAssertEqual(MertensFusion.DeghostLevel.high.baseDilateRadius, 9)
        // off skips the whole segment (no mask, no substitution).
        let width = 32, height = 32
        let a = Self.texture(width, height, seeds: (1, 2, 3))
        let b = Self.texture(width, height, seeds: (4, 5, 6))
        XCTAssertNil(MertensFusion.ghostMask(
            frames: [a, b], reference: 0, level: .off, width: width, height: height))

        // The usable gate, on a TEXTURED pair (the quantile mapping is a
        // structural no-op against a constant-field reference — its whole
        // design; a solid fixture would prove nothing): a differing block
        // where the REFERENCE is clipped (>0.985) is NOT motion evidence;
        // the same block in-range IS.
        let reference = Self.texture(48, 48, seeds: (1, 2, 3), low: 0.2, high: 0.8)
        func withBlock(_ plane: [Float], _ value: (Float) -> Float) -> [Float] {
            var out = plane
            for y in 12..<24 {
                for x in 12..<24 {
                    for channel in 0..<3 {
                        let index = (y * 48 + x) * 4 + channel
                        out[index] = min(max(value(plane[index]), 0), 1)
                    }
                }
            }
            return out
        }
        // Positive: the frame's block shifts far up but stays in range.
        let frameShifted = withBlock(reference) { $0 > 0.9 ? $0 : min($0 + 0.35, 0.9) }
        // Negative: the same block shift, but the REFERENCE side is clipped.
        let clippedRef = withBlock(reference) { $0 > 0.9 ? $0 : 0.995 }
        let clippedMask = MertensFusion.ghostMask(
            frames: [clippedRef, frameShifted], reference: 0, level: .medium,
            width: 48, height: 48)!
        let motionMask = MertensFusion.ghostMask(
            frames: [reference, frameShifted], reference: 0, level: .medium,
            width: 48, height: 48)!
        func meanOverBlock(_ mask: [Float]) -> Float {
            var total: Float = 0
            for y in 12..<24 {
                for x in 12..<24 { total += mask[y * 48 + x] }
            }
            return total / 144
        }
        XCTAssertLessThan(meanOverBlock(clippedMask), 0.05,
            "a clipped reference block must NOT read as motion")
        XCTAssertGreaterThan(meanOverBlock(motionMask), 0.3,
            "an in-range differing block must read as motion")
    }

    // MARK: - The static-sample fallback (checker minor-1)

    func testStaticSampleFallbackCoversAllMotionDegenerate() {
        let width = 48, height = 48
        // Every cell in motion → the decimated static set is empty → the
        // merge.py:146 fallback must treat the WHOLE grid as static.
        let allMotion = [Float](repeating: 1, count: width * height)
        let (grid, gridWidth, gridHeight, fellBack) = MertensFusion.staticSampleMask(
            motion: allMotion, width: width, height: height)
        XCTAssertTrue(fellBack)
        XCTAssertTrue(grid.allSatisfy { $0 })
        XCTAssertGreaterThan(gridWidth * gridHeight, 0)
        // And the LUT estimation still yields a full 129-point table —
        // never evaluated on an empty sample set.
        let reference = Self.texture(width, height, seeds: (7, 8, 9))
        let frame = Self.texture(width, height, seeds: (10, 11, 12))
        let luts = MertensFusion.substituteLUTs(
            reference: reference, frame: frame, motion: allMotion,
            width: width, height: height)
        XCTAssertEqual(luts.count, 3)
        for lut in luts {
            XCTAssertEqual(lut.xs.count, 129)
            XCTAssertEqual(lut.ys.count, 129)
        }
        // A mostly-static mask does NOT fall back.
        let mostlyStatic = [Float](repeating: 0, count: width * height)
        let (_, _, _, fellBackStatic) = MertensFusion.staticSampleMask(
            motion: mostlyStatic, width: width, height: height)
        XCTAssertFalse(fellBackStatic)
    }

    // MARK: - The substitute LUTs

    func testSubstituteLUTIdentityWhenFramesMatch() {
        let width = 32, height = 32
        let reference = Self.texture(width, height, seeds: (21, 22, 23))
        // A high-motion mask so the substitution is fully active (α=1).
        let motion = [Float](repeating: 1, count: width * height)
        let luts = MertensFusion.substituteLUTs(
            reference: reference, frame: reference, motion: motion,
            width: width, height: height)
        // Identical frames → each LUT maps x to x exactly.
        for lut in luts {
            XCTAssertEqual(lut.xs, lut.ys)
        }
        let prepared = MertensFusion.applySubstitution(
            original: reference, reference: reference, motion: motion,
            luts: luts, width: width, height: height)
        for (index, value) in reference.enumerated() {
            // The interp round-trip carries ~1 ulp (a·(1−f)+b·f ≠ a in
            // float); the identity holds within 1e-6.
            XCTAssertEqual(prepared[index], value, accuracy: 1e-6)
        }
        // Endpoints clamp: a LUT applied below/above its range pins to the
        // end ys (the interp contract).
        XCTAssertEqual(
            MertensFusion.interp(-1, xs: luts[0].xs, ys: luts[0].ys), luts[0].ys[0])
        XCTAssertEqual(
            MertensFusion.interp(9, xs: luts[0].xs, ys: luts[0].ys),
            luts[0].ys[luts[0].ys.count - 1])
    }

    // MARK: - The KD-2 formulas

    func testAdaptiveLevelsTruthTable() {
        // The KD-2 six rows (checker minor-4: the plan's "八行" was a slip —
        // the binding table is these six) + the two boundary rows.
        XCTAssertEqual(MertensFusion.adaptiveLevels(minEdge: 32), 1)
        XCTAssertEqual(MertensFusion.adaptiveLevels(minEdge: 64), 2)
        XCTAssertEqual(MertensFusion.adaptiveLevels(minEdge: 256), 4)
        XCTAssertEqual(MertensFusion.adaptiveLevels(minEdge: 512), 5)
        XCTAssertEqual(MertensFusion.adaptiveLevels(minEdge: 1024), 6)
        XCTAssertEqual(MertensFusion.adaptiveLevels(minEdge: 8642), 9) // 100MP short edge
        // Boundaries: below the 32px floor clamps to 1; the 12-level cap.
        XCTAssertEqual(MertensFusion.adaptiveLevels(minEdge: 16), 1)
        XCTAssertEqual(MertensFusion.adaptiveLevels(minEdge: 65536), 12)
        XCTAssertEqual(MertensFusion.adaptiveLevels(minEdge: 131072), 12)
    }

    func testHaloRowsTruthTableWithFocusStackAnchor() {
        // L=5 lands EXACTLY on the focus-stack default halo (KD-2 anchor).
        XCTAssertEqual(MertensFusion.haloRows(levels: 5), FocusStackMerge.defaultHaloRows)
        XCTAssertEqual(MertensFusion.haloRows(levels: 5), 32)
        XCTAssertEqual(MertensFusion.haloRows(levels: 4), 32)
        XCTAssertEqual(MertensFusion.haloRows(levels: 6), 64)
        XCTAssertEqual(MertensFusion.haloRows(levels: 9), 512)
        XCTAssertEqual(MertensFusion.haloRows(levels: 1), 32)
    }

    // MARK: - The strip fusion smoke face

    func testFuseStripSmallFaceRunsFiniteAndHullBounded() {
        let width = 48, height = 40
        let bright = Self.texture(width, height, seeds: (31, 32, 33), low: 0.45, high: 0.85)
        let dark = Self.texture(width, height, seeds: (34, 35, 36), low: 0.15, high: 0.5)
        let fused = MertensFusion.fuseStrip(
            width: width, height: height, sources: 2, levels: 3) { $0 == 0 ? bright : dark }
        XCTAssertEqual(fused.count, width * height * 3)
        var min = Float.greatestFiniteMagnitude
        var max = -Float.greatestFiniteMagnitude
        for value in fused {
            XCTAssertFalse(value.isNaN, "fusion must not emit NaN on finite input")
            min = Swift.min(min, value)
            max = Swift.max(max, value)
        }
        // The multiband blend stays inside the sources' convex hull band
        // (a small overshoot beyond the exact hull is the expand's linear
        // interpolation domain — bound generously).
        XCTAssertGreaterThan(min, -0.05)
        XCTAssertLessThan(max, 1.05)
    }

    // MARK: - The blur / utility anchors

    func testGaussianBlurConstantFieldFixedPointAndNormalization() {
        let width = 32, height = 24
        // A constant field is a fixed point (normalized kernel).
        let constant = [Float](repeating: 0.37, count: width * height)
        let blurred = MertensFusion.gaussianBlurGray(
            constant, width: width, height: height, sigma: 1.2)
        for value in blurred {
            XCTAssertEqual(value, 0.37, accuracy: 1e-5)
        }
    }

    func testDecimationStepAndLinspaceAnchors() {
        // merge.py:124 — sampling = max(1, ceil(max(dim)/1000)).
        XCTAssertEqual(MertensFusion.decimationStep(width: 500, height: 300), 1)
        XCTAssertEqual(MertensFusion.decimationStep(width: 1800, height: 1200), 2)
        XCTAssertEqual(MertensFusion.decimationStep(width: 100, height: 8642), 9)
        // merge.py:124/:147 — the quantile ladders.
        let ladder33 = MertensFusion.linspace(2, 98, 33)
        XCTAssertEqual(ladder33.count, 33)
        XCTAssertEqual(ladder33.first ?? -1, 2, accuracy: 1e-12)
        XCTAssertEqual(ladder33.last ?? -1, 98, accuracy: 1e-12)
        XCTAssertEqual(ladder33[1] - ladder33[0], 3.0, accuracy: 1e-12)
        let ladder129 = MertensFusion.linspace(0, 100, 129)
        XCTAssertEqual(ladder129.count, 129)
        XCTAssertEqual(ladder129[64], 50, accuracy: 1e-12)
    }

    func testFuseWholeFrameDeghostMediumSmokeGreen() {
        let width = 48, height = 40
        // A coherent dark object moved between the frames (the shape the
        // blurred-residual detector actually fires on — see the G3② note).
        let background = Self.texture(width, height, seeds: (41, 42, 43), low: 0.45, high: 0.85)
        let object = Self.texture(12, 12, seeds: (44, 45, 46), low: 0.08, high: 0.15)
        func paste(_ plane: [Float], _ x0: Int, _ y0: Int) -> [Float] {
            var out = plane
            for y in 0..<12 {
                for x in 0..<12 {
                    for channel in 0..<3 {
                        out[((y0 + y) * width + x0 + x) * 4 + channel] =
                            object[(y * 12 + x) * 4 + channel]
                    }
                }
            }
            return out
        }
        let reference = paste(background, 4, 8)
        let frame = paste(background, 22, 8)
        let fused = MertensFusion.fuse(
            frames: [reference, frame], width: width, height: height, deghost: .medium)
        XCTAssertEqual(fused.count, width * height * 3)
        for value in fused {
            XCTAssertFalse(value.isNaN)
            XCTAssertGreaterThanOrEqual(value, -0.05)
            XCTAssertLessThanOrEqual(value, 1.05)
        }
    }
}
