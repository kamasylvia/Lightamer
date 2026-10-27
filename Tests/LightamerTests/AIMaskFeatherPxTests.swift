@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// AIMaskFeatherPxTests (M9-1 T2, D-M9A-7) — the absolute-px feather face:
/// ① σ_px↔percent 双向换算 (the SINGLE conversion source — the exact
///    identity σ == px in the ≥2500px long-edge domain);
/// ② clamp boundaries (0 / 50 / beyond / negative → 0);
/// ③ the bake-seam ORDER (expand → feather → quantize): baking with both
///    parameters equals the manual chain (morphology first, blur second);
/// ④ the negative logit-gain leg stays untouched (the superset regression
///    — the percent<0 path resolves exactly as before).
final class AIMaskFeatherPxTests: XCTestCase {

    // MARK: ① the two-way fold

    /// In the exact domain (longEdge ≥ 2500 ⇒ 2% ≥ 50px) sigmaFromPx is
    /// the identity σ == px; pxFromPercent is the σ fold's inverse (the
    /// round trip stays inside the ≤50px panel domain).
    func testSigmaPxFoldIsExactAndInverts() {
        for longEdge in [2500, 4000, 6000, 11688] {
            for px: Float in [0, 1, 7.5, 24, 50] {
                XCTAssertEqual(
                    AIMaskFeather.sigmaFromPx(px: px, longEdgePixels: longEdge),
                    px, accuracy: 1e-4,
                    "σ == px in the ≥2500px domain (longEdge=\(longEdge))")
            }
            // The round trip stays INSIDE the ≤50px panel domain: percent
            // samples whose σ ≤ 50 (the panel's px ceiling).
            let ceiling: Float = 100
            let hundred: Float = 100
            let fold: Float = AIMaskFeather.maxFeatherPx * hundred
                / (AIMaskFeather.maxRadiusFraction * Float(longEdge))
            let maxPercent = min(ceiling, fold)
            for fraction: Float in [0.02, 0.5, 1.0] {
                let percent = maxPercent * fraction
                let px = AIMaskFeather.pxFromPercent(
                    percent: percent, longEdgePixels: longEdge)
                XCTAssertEqual(
                    AIMaskFeather.sigmaFromPx(px: px, longEdgePixels: longEdge),
                    px, accuracy: 1e-3,
                    "round trip px→σ==px (longEdge=\(longEdge), percent=\(percent))")
            }
        }
    }

    // MARK: ② clamp boundaries

    /// px clamps into [0,50]: negative → 0, beyond 50 → 50; below the
    /// exact domain the percent leg's own ±100 clamp caps σ at 2% of the
    /// long edge (the pre-existing red-line behavior, kept).
    func testPxClampBoundaries() {
        XCTAssertEqual(AIMaskFeather.sigmaFromPx(px: -5, longEdgePixels: 4000), 0)
        XCTAssertEqual(
            AIMaskFeather.sigmaFromPx(px: 75, longEdgePixels: 4000), 50, accuracy: 1e-4)
        XCTAssertEqual(
            AIMaskFeather.sigmaFromPx(px: 50, longEdgePixels: 4000), 50, accuracy: 1e-4)
        // Small planes: the percent clamp caps σ at 2% of the long edge.
        XCTAssertEqual(
            AIMaskFeather.sigmaFromPx(px: 50, longEdgePixels: 32),
            0.02 * 32, accuracy: 1e-6,
            "the percent leg's ±100 clamp stays authoritative on small planes")
        // The negative percent face maps to the px panel's zero.
        XCTAssertEqual(AIMaskFeather.pxFromPercent(percent: -40, longEdgePixels: 4000), 0)
        XCTAssertEqual(AIMaskFeather.pxFromPercent(percent: 0, longEdgePixels: 4000), 0)
    }

    // MARK: ③ the bake-seam order (expand → feather → quantize)

    /// Baking with BOTH parameters equals the manual chain: the CPU
    /// morphology pre-pass first, then the Gaussian blur bake — byte-for-
    /// byte on the written PNG.
    func testBakeAppliesExpandBeforeFeather() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory(), isDirectory: true
        ).appendingPathComponent("featherpx-\(UUID().uuidString)", isDirectory: true)

        // A NON-symmetric random plane: on symmetric linear ramps the
        // blur/shift pair commutes (a linear segment convolved with a
        // positive kernel stays linear — the shift commutes there), so
        // the ORDER pin needs an irregular surface to be discriminative.
        let width = 64, height = 32
        var state: UInt64 = 0xAB12_CD34_EF56_0789
        var rampFloats = [Float](repeating: 0, count: width * height)
        for i in 0..<rampFloats.count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            rampFloats[i] = Float((state >> 40) % 4096) / 4095 * 0.7
        }
        // Carve a solid plateau (the dilate/erode mover).
        for y in 8..<24 {
            for x in 24..<44 { rampFloats[y * width + x] = 1.0 }
        }
        let ramp = AIMaskPlane(width: width, height: height, floats: rampFloats)

        let composed = try await RasterMaskStore.bake(
            plane: AIMaskResample.texture(from: ramp, metal: metal),
            directory: directory, fileName: "composed.png",
            invert: false,
            featherRadius: 4, expandPx: -3, metal: metal)
        let manualChain = try await RasterMaskStore.bake(
            plane: AIMaskResample.texture(
                from: AIMaskMorphology.expand(plane: ramp, px: -3), metal: metal),
            directory: directory, fileName: "manual.png",
            invert: false, featherRadius: 4, expandPx: 0, metal: metal)
        let composedBytes = try Data(
            contentsOf: directory.appendingPathComponent(composed.fileName))
        let manualBytes = try Data(
            contentsOf: directory.appendingPathComponent(manualChain.fileName))
        XCTAssertEqual(
            composedBytes, manualBytes,
            "bake(expandPx, featherRadius) == bake(bake-pre-expanded, featherRadius)")

        // And the order is NOT symmetric — reversing it (feather first)
        // genuinely differs (the pin that the declared order is real).
        let featherFirst = try await RasterMaskStore.bake(
            plane: try await MaskCombiner.blur(
                mask: AIMaskResample.texture(from: ramp, metal: metal),
                sigma: 4, metal: metal),
            directory: directory, fileName: "featherfirst.png",
            invert: false, featherRadius: 0, expandPx: -3, metal: metal)
        let featherFirstBytes = try Data(
            contentsOf: directory.appendingPathComponent(featherFirst.fileName))
        XCTAssertNotEqual(
            composedBytes, featherFirstBytes,
            "expand→feather ≠ feather→expand on a soft-edge plane")

        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: ④ the negative leg regression (the kept superset)

    /// percent < 0 keeps the logit-gain CPU face untouched: same fixed
    /// points (0/0.5/1), same narrowing direction, zero at percent ≥ 0.
    func testNegativeLogitGainLegUnchanged() {
        let width = 32, height = 16
        let ramp = AIMaskPlane(width: width, height: height, floats: (0..<(width * height)).map { i in
            let x = Double(i % width)
            return Float(1.0 / (1.0 + Foundation.exp(-(x - 16.0) / 3.0)))
        })
        let sharpened = AIMaskFeather.applyFeatherNegative(plane: ramp, percent: -40)
        XCTAssertEqual(sharpened.width, width)
        for (index, (source, target)) in zip(ramp.floats, sharpened.floats).enumerated() {
            if source <= 0 || source >= 1 || source == 0.5 {
                XCTAssertEqual(
                    target, source,
                    "fixed points survive at index \(index)")
            }
        }
        // The transition narrows: the sharpened plane crosses 0.5 at the
        // same place but with a steeper slope.
        let midRow = 8
        func slope(_ floats: [Float]) -> Float {
            floats[midRow * width + 17] - floats[midRow * width + 15]
        }
        XCTAssertGreaterThan(
            slope(sharpened.floats), slope(ramp.floats),
            "the logit-gain leg narrows the transition (the kept superset)")
        // percent ≥ 0 returns the plane unchanged (the short-circuit).
        XCTAssertEqual(
            AIMaskFeather.applyFeatherNegative(plane: ramp, percent: 40).floats,
            ramp.floats)
    }


}
