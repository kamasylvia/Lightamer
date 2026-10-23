import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// CullingAnalysisGoldenTests (Plan LUMEN-A T3, review B-1) — the sharpness /
// signature golden face:
//
//   ① Lumen-pipeline parity: the Swift SharpnessAnalyzer/Signature16 vs the
//      NumPy REFERENCE implementation (Scripts/gen-culling-golden.py wrote
//      Tests/Fixtures/culling_golden.json) on deterministic synthetic
//      content the test regenerates step-for-step (the integer LCG makes
//      the planes bit-identical; doubles everywhere until the Float entry).
//      Covers the base plane, the RESIZE path (2000×1500 → 1600), the
//      signature hex, and the two branches (flat → 0.0, tiny → nil).
//   ② the Lumen calibration anchors: 1.2-px Gaussian blur ≈ 55, 2 px ≈ 30,
//      band ±5 (D-LU-10) — the anchor blur rides the cv2 auto-ksize rule
//      (radius = round(4*sigma), probed 2026-10-22 against
//      opencv-python-headless; DECISIONS carries the record).
//   ③ min-of-4 directionality: a horizontal box smear collapses the score
//      while a vertical smear of the same anisotropic content survives —
//      the motion-blur detection the four-direction kernels exist for.
// ─────────────────────────────────────────────────────────────────────────────

final class CullingAnalysisGoldenTests: XCTestCase {

    // MARK: - Golden JSON

    private struct CullingGolden: Decodable {
        struct Case: Decodable {
            let w: Int
            let h: Int
            let sharpness: Double?
            let signatureHex: String?

            enum CodingKeys: String, CodingKey {
                case w, h, sharpness
                case signatureHex = "signature_hex"
            }
        }
        struct Anchors: Decodable {
            let sigma12: Double
            let sigma20: Double

            enum CodingKeys: String, CodingKey {
                case sigma12 = "sigma_1_2_sharpness"
                case sigma20 = "sigma_2_0_sharpness"
            }
        }
        let base: Case
        let resized: Case
        let anchors: Anchors
        let flatSharpness: Double
        let tiny: Case

        enum CodingKeys: String, CodingKey {
            case base, resized, anchors, tiny
            case flatSharpness = "flat_sharpness"
        }
    }

    private func loadGolden() throws -> CullingGolden {
        // Repo-relative via #filePath (the TiffRaster fixture precedent).
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests/LightamerTests/
            .deletingLastPathComponent()      // Tests/
            .appendingPathComponent("Fixtures/culling_golden.json")
        return try JSONDecoder().decode(
            CullingGolden.self, from: Data(contentsOf: url))
    }

    // MARK: - Deterministic content (mirrors content_image in the generator)

    private struct Plane {
        var data: [Double]
        let width: Int
        let height: Int
    }

    private func lcgNoise(width: Int, height: Int, seed: UInt64) -> [Double] {
        var state = seed
        var out = [Double](repeating: 0, count: width * height)
        for index in 0..<out.count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            out[index] = Double((state >> 33) % 4096) / 4096.0
        }
        return out
    }

    /// Separable Gaussian, reflect-101, explicit radius (the generator's
    /// `gaussian_blur` mirror — double precision, tap accumulation in the
    /// same order).
    private func gaussianBlur(
        _ plane: Plane, sigma: Double, radius: Int
    ) -> Plane {
        var kernel = (0..<(2 * radius + 1)).map { tap -> Double in
            let offset = Double(tap - radius)
            return exp(-(offset * offset) / (2 * sigma * sigma))
        }
        let sum = kernel.reduce(0, +)
        for index in 0..<kernel.count { kernel[index] /= sum }

        func reflect101(_ index: Int, _ extent: Int) -> Int {
            var i = index
            if i < 0 { i = -i }
            if i >= extent { i = 2 * (extent - 1) - i }
            return max(0, min(i, extent - 1))
        }

        var horizontal = [Double](repeating: 0, count: plane.data.count)
        for y in 0..<plane.height {
            let row = y * plane.width
            for x in 0..<plane.width {
                var acc = 0.0
                for tap in 0..<kernel.count {
                    let d = tap - radius
                    acc += kernel[tap] * plane.data[row + reflect101(x + d, plane.width)]
                }
                horizontal[row + x] = acc
            }
        }
        var output = [Double](repeating: 0, count: plane.data.count)
        for y in 0..<plane.height {
            for x in 0..<plane.width {
                var acc = 0.0
                for tap in 0..<kernel.count {
                    let d = tap - radius
                    acc += kernel[tap]
                        * horizontal[reflect101(y + d, plane.height) * plane.width + x]
                }
                output[y * plane.width + x] = acc
            }
        }
        return Plane(data: output, width: plane.width, height: plane.height)
    }

    /// The generator's `content_image` mirror (0.45 n + 0.25 gauss2(n) +
    /// 0.1 gauss4(n) + 0.15 bars32 + 0.1 x-gradient → normalize → clip →
    /// gauss 0.65 (content radius rule round(3σ) = 2) → clip).
    private func contentImage(width: Int, height: Int, seed: UInt64) -> Plane {
        let noise = lcgNoise(width: width, height: height, seed: seed)
        var plane = Plane(data: noise, width: width, height: height)
        let gauss2 = gaussianBlur(plane, sigma: 2.0, radius: 6)
        let gauss4 = gaussianBlur(plane, sigma: 4.0, radius: 12)
        var combined = [Double](repeating: 0, count: noise.count)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let bars: Double =
                    ((x / 32) % 2 == 0 && (y / 32) % 2 == 0) ? 0.15 : 0
                combined[index] = 0.45 * noise[index]
                    + 0.25 * gauss2.data[index]
                    + 0.1 * gauss4.data[index]
                    + bars + Double(x) / Double(width) * 0.1
            }
        }
        let peak = combined.max() ?? 1
        for index in 0..<combined.count {
            combined[index] = min(max(combined[index] / peak, 0), 1)
        }
        plane.data = combined
        var smoothed = gaussianBlur(plane, sigma: 0.65, radius: 2)
        for index in 0..<smoothed.data.count {
            smoothed.data[index] = min(max(smoothed.data[index], 0), 1)
        }
        return smoothed
    }

    private func floatPlane(_ plane: Plane) -> [Float] {
        plane.data.map(Float.init)
    }

    /// Box smear (the motion-blur synthesis for ③): `extent`-px horizontal
    /// or vertical box average, reflect-101.
    private func boxSmear(_ plane: Plane, extent: Int, horizontal: Bool) -> Plane {
        let half = extent / 2
        var output = [Double](repeating: 0, count: plane.data.count)
        for y in 0..<plane.height {
            for x in 0..<plane.width {
                var acc = 0.0
                for d in -half...half {
                    if horizontal {
                        let xx = min(max(x + d, 0), plane.width - 1)
                        acc += plane.data[y * plane.width + xx]
                    } else {
                        let yy = min(max(y + d, 0), plane.height - 1)
                        acc += plane.data[yy * plane.width + x]
                    }
                }
                output[y * plane.width + x] = acc / Double(extent)
            }
        }
        return Plane(data: output, width: plane.width, height: plane.height)
    }

    // MARK: - ① Golden parity + branches

    func testGoldenParitySignatureAndBranches() throws {
        let golden = try loadGolden()

        // Base plane: sharpness parity + the 256-byte signature.
        let base = contentImage(width: golden.base.w, height: golden.base.h, seed: 0x2A5F1B)
        let baseScore = try XCTUnwrap(SharpnessAnalyzer.analyze(
            gray: floatPlane(base), width: base.width, height: base.height))
        XCTAssertEqual(
            baseScore, try XCTUnwrap(golden.base.sharpness), accuracy: 0.05,
            "Swift sharpness must match the NumPy reference on the base plane")

        let signature = Signature16.bytes(
            gray: floatPlane(base), width: base.width, height: base.height)
        XCTAssertEqual(signature.count, 256)
        let expected = try XCTUnwrap(golden.base.signatureHex)
        XCTAssertEqual(expected.count, 512)
        for index in 0..<256 {
            let expectedByte = try XCTUnwrap(UInt8(
                expected.subString(from: index * 2, length: 2), radix: 16))
            XCTAssertLessThanOrEqual(
                abs(Int(signature[index]) - Int(expectedByte)), 1,
                "signature byte \(index) within one truncation step of reference")
        }

        // Resize path: the 2000×1500 input exercises the area downscale.
        // Tolerance 0.5: the production pipeline runs Float32 (the Lumen
        // float32-numpy convention) while the reference is Float64 — the
        // gap surfaces at the P75-selection boundary (recorded in
        // DECISIONS; the golden LOCK is the base-plane parity above).
        let resized = contentImage(
            width: golden.resized.w, height: golden.resized.h, seed: 0x51DE2C)
        let resizedScore = try XCTUnwrap(SharpnessAnalyzer.analyze(
            gray: floatPlane(resized), width: resized.width, height: resized.height))
        XCTAssertEqual(
            resizedScore, try XCTUnwrap(golden.resized.sharpness), accuracy: 0.5,
            "the resize leg matches the reference")

        // Branch (review B-1): flat plane → strong-empty → 0.0.
        let flat = Plane(
            data: [Double](repeating: 0.4, count: 640 * 512), width: 640, height: 512)
        XCTAssertEqual(
            try XCTUnwrap(SharpnessAnalyzer.analyze(
                gray: floatPlane(flat), width: 640, height: 512)), 0.0,
            accuracy: 1e-9)

        // Branch (review B-1): short edge < 64 → nil.
        let tiny = Plane(
            data: [Double](repeating: 0.4, count: 48 * 40), width: 48, height: 40)
        XCTAssertNil(SharpnessAnalyzer.analyze(
            gray: floatPlane(tiny), width: 48, height: 40))
    }

    // MARK: - ② Calibration anchors (D-LU-10 band ±5)

    func testCalibrationAnchorsInBand() throws {
        let golden = try loadGolden()
        let base = contentImage(width: golden.base.w, height: golden.base.h, seed: 0x2A5F1B)

        // Anchor blur = the cv2.GaussianBlur(img,(0,0),sigma) auto-ksize
        // rule: radius = round(4*sigma) (1.2 → 5, 2.0 → 8).
        let blurred12 = gaussianBlur(base, sigma: 1.2, radius: 5)
        let blurred20 = gaussianBlur(base, sigma: 2.0, radius: 8)
        let score12 = try XCTUnwrap(SharpnessAnalyzer.analyze(
            gray: floatPlane(blurred12), width: base.width, height: base.height))
        let score20 = try XCTUnwrap(SharpnessAnalyzer.analyze(
            gray: floatPlane(blurred20), width: base.width, height: base.height))

        // Swift vs the NumPy/cv2-measured reference values. The σ2.0 arm
        // gets a wider parity band (3.0): heavy blur drives the tile
        // energies toward the 2e-5 floor where the Float32 production
        // pipeline's P75 tile selection diverges from the Float64
        // reference (the SC face is the ±5 BAND assertion below, which
        // both arms meet).
        XCTAssertEqual(score12, golden.anchors.sigma12, accuracy: 0.2)
        XCTAssertEqual(score20, golden.anchors.sigma20, accuracy: 3.0)

        // THE Lumen calibration band (D-LU-10): 1.2 px ≈ 55, 2 px ≈ 30.
        XCTAssertEqual(Double(score12), 55, accuracy: 5)
        XCTAssertEqual(Double(score20), 30, accuracy: 5)
    }

    // MARK: - ③ min-of-4 directionality (motion blur detection)

    func testDirectionalMotionBlurDetection() throws {
        // A 45° diagonal grating carries structure on ALL four direction
        // kernels (a y-constant bar plane would trip the faithful
        // per-direction strong-empty branch instead — that branch is
        // pinned by the flat-plane case in ①). A horizontal box smear is
        // one-direction motion blur: the min-of-4 must collapse the score
        // against the un-smeared plane, and a second, wider smear must not
        // recover (the smearing only ever destroys).
        var grating = Plane(
            data: [Double](repeating: 0, count: 800 * 600), width: 800, height: 600)
        for y in 0..<grating.height {
            for x in 0..<grating.width {
                grating.data[y * grating.width + x] =
                    ((x + y) / 24) % 2 == 0 ? 0.9 : 0.1
            }
        }
        grating = gaussianBlur(grating, sigma: 0.65, radius: 2)

        let score0 = try XCTUnwrap(SharpnessAnalyzer.analyze(
            gray: floatPlane(grating), width: grating.width, height: grating.height))
        XCTAssertGreaterThan(score0, 45, "the pre-blurred grating is sharp content")

        let hSmeared = boxSmear(grating, extent: 9, horizontal: true)
        let hScore = try XCTUnwrap(SharpnessAnalyzer.analyze(
            gray: floatPlane(hSmeared), width: hSmeared.width, height: hSmeared.height))
        XCTAssertLessThan(
            hScore, score0 - 15,
            "one-direction motion blur must be detected via min-of-4")

        let wider = boxSmear(hSmeared, extent: 17, horizontal: true)
        let widerScore = try XCTUnwrap(SharpnessAnalyzer.analyze(
            gray: floatPlane(wider), width: wider.width, height: wider.height))
        XCTAssertLessThanOrEqual(widerScore, hScore)
    }

    // MARK: - Percentile + Signature16 range

    func testPercentileLinearAndSignatureRange() {
        // Linear interpolation between closest ranks (numpy 'linear').
        XCTAssertEqual(
            SharpnessAnalyzer.percentile([1, 2, 3, 4], quantile: 0.75), 3.25, accuracy: 1e-6)
        XCTAssertEqual(
            SharpnessAnalyzer.percentile([10, 20], quantile: 0.5), 15, accuracy: 1e-6)
        XCTAssertEqual(
            SharpnessAnalyzer.percentile([7], quantile: 0.9), 7, accuracy: 1e-6)

        // Signature: 256 bytes, range respected on a mixed-content plane.
        var plane = Plane(data: [Double](repeating: 0, count: 128 * 96), width: 128, height: 96)
        for y in 0..<plane.height {
            for x in 0..<plane.width {
                plane.data[y * plane.width + x] =
                    (x % 2 == 0) ? 1.0 : (Double(y % 97) / 97.0)
            }
        }
        let bytes = Signature16.bytes(
            gray: floatPlane(plane), width: plane.width, height: plane.height)
        XCTAssertEqual(bytes.count, 256)
        XCTAssertTrue(bytes.allSatisfy { $0 >= 0 && $0 <= 255 })
        // Deterministic + spatially varying (the mixed 1.0/noise content
        // must not fold to a constant cell).
        let again = Signature16.bytes(
            gray: floatPlane(plane), width: plane.width, height: plane.height)
        XCTAssertEqual(bytes, again)
        XCTAssertTrue(
            bytes.contains(where: { $0 > 200 }) && bytes.contains(where: { $0 < 150 }),
            "the signature cells track the mixed content")
    }
}

private extension String {
    /// A two-char hex slice (the golden hex walker).
    func subString(from: Int, length: Int) -> String {
        let start = index(startIndex, offsetBy: from)
        let end = index(start, offsetBy: length)
        return String(self[start..<end])
    }
}
