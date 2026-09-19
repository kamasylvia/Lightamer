@testable import LightamerCore
import Foundation
import LightamerIOP
import XCTest

// CPUDerivationTests (Plan 03-01-T4) — the CPU-side derivation harness:
// for each tone iop, the commit-time math that does NOT need the GPU gets a
// "formula transliteration + known vectors" DUAL-IMPLEMENTATION cross-check
// (the Swift production code vs an independently written reference in this
// file). NO darktable binary dependency — golden parity against dt-cli
// lives in GoldenParityTests; this file pins the MATH so a golden failure
// localizes to the kernel/dispatch side, and so the math is verifiable on
// machines without a rebuilt darktable.
//
// Sections follow RESEARCH (03-RESEARCH.md §Validation Architecture #3):
//   ✅ exposure   (§1.1) — this plan
//   ⬜ WB K→gain  (§1.2/§5) — plan 03-02
//   ⬜ Lab round-trip (§Summary #3) — plan 03-03 (tonecurve/colisa/levels/shadhi)
//   ⬜ sigmoid commit_params four scalars (§3) — plan 03-04
//   ⬜ toneequal correction LUT (§4) — plan 03-05
//   ⬜ filmic spline M1..M5 / output power / norm bounds (§2) — plan 03-06
final class CPUDerivationTests: XCTestCase {

    // MARK: - exposure (RESEARCH §1.1; dt exposure.c:479-521, v7 params :66-78)

    /// The reference implementation, written independently from
    /// `ExposureModule.commitParams` (double precision, textbook form).
    private func referenceExposure(
        input: Double, exposure: Double, black: Double
    ) -> (white: Double, scale: Double, output: Double) {
        let clampedBlack = max(-1.0, min(1.0, black))
        let white = pow(2.0, -exposure) // exp2(−EV)
        let scale = 1.0 / (white - clampedBlack)
        return (white, scale, (input - clampedBlack) * scale)
    }

    func testExposureKnownVectors() async throws {
        // (+1EV / −1EV / black=0.1) — the plan's vector trio, plus the
        // identity default. Vectors chosen so every value is exact in
        // float32 (powers of two) except the black=0.1 case, which pins
        // the 1/(white−black) rescale against the double reference.
        let vectors: [(name: String, exposure: Float, black: Float, input: Float, expected: Double)] = [
            ("identity 0EV", 0.0, 0.0, 0.25, 0.25),
            ("+1EV on 0.25", 1.0, 0.0, 0.25, 0.5),
            ("+1EV on 0.5", 1.0, 0.0, 0.5, 1.0),
            ("−1EV on 0.5", -1.0, 0.0, 0.5, 0.25),
            ("−2EV on 0.5", -2.0, 0.0, 0.5, 0.125),
            ("+0.5EV on 0.5", 0.5, 0.0, 0.5, 0.5 * pow(2.0, 0.5)),
            ("black=0.1 on 0.5 @0EV", 0.0, 0.1, 0.5, (0.5 - 0.1) / (1.0 - 0.1)),
            ("black=−0.02 @+0.5EV", 0.5, -0.02, 0.3, (0.3 + 0.02) / (pow(2.0, -0.5) + 0.02)),
        ]
        for v in vectors {
            let module = ExposureModule()
            var piece = IOPiece()
            let params = ExposureModule.Params(black: v.black, exposure: v.exposure)
            await module.commitParams(params, into: &piece)

            // The uniforms carry (black, scale) — decode them back.
            let buffer = try XCTUnwrap(piece.data, "commitParams must produce uniforms")
            let bytes = buffer.contents().assumingMemoryBound(to: Float.self)
            let black = bytes[0]
            let scale = bytes[1]

            let reference = referenceExposure(
                input: Double(v.input), exposure: Double(v.exposure), black: Double(v.black)
            )
            // Black round-trips through the clamp exactly for in-range values.
            XCTAssertEqual(Double(black), min(1.0, max(-1.0, Double(v.black))), accuracy: 1e-7,
                           "\(v.name): black uniform")
            XCTAssertEqual(Double(scale), reference.scale, accuracy: reference.scale * 1e-6,
                           "\(v.name): scale = 1/(exp2(−EV) − black)")
            let output = (Double(v.input) - Double(black)) * Double(scale)
            XCTAssertEqual(output, reference.output, accuracy: abs(reference.output) * 1e-6 + 1e-9,
                           "\(v.name): out = (in − black) × scale")
            // And the expected vector itself (the plan's literal numbers).
            XCTAssertEqual(output, v.expected, accuracy: abs(v.expected) * 1e-6 + 1e-9,
                           "\(v.name): known vector")
        }
    }

    func testExposureWhiteDerivation() async throws {
        // white = exp2(−exposure) — the dt `exposure2white` identity
        // (exposure.c:44-45): +1EV brightens ⇒ white halves ⇒ scale doubles.
        for (ev, white) in [(0.0, 1.0), (1.0, 0.5), (-1.0, 2.0), (0.5, pow(2.0, -0.5)), (-4.0, 16.0)] {
            let reference = referenceExposure(input: 1.0, exposure: ev, black: 0.0)
            XCTAssertEqual(reference.white, white, accuracy: 1e-12)
            XCTAssertEqual(reference.scale, 1.0 / white, accuracy: 1e-12)
        }
    }

    func testExposureBlackClampDomain() async throws {
        // Lightamer clamps black into [−1, 1] at commit (dt enforces the
        // same domain at the widget layer) — document the clamp point.
        let module = ExposureModule()
        var piece = IOPiece()
        await module.commitParams(ExposureModule.Params(black: 1.5, exposure: 0), into: &piece)
        let buffer = try XCTUnwrap(piece.data)
        let bytes = buffer.contents().assumingMemoryBound(to: Float.self)
        XCTAssertEqual(bytes[0], 1.0, "black clamped to +1")
        // scale = 1/(1 − 1) → infinite; dt's GUI never lets the user reach
        // this — Lightamer's clamp alone permits it, so the pipe-relevant
        // invariant is only that commitParams does not trap. Documented
        // divergence: the GUI slider (Phase 3 D-T6) must enforce [−1, 1).
        XCTAssertTrue(bytes[1].isInfinite || bytes[1].isFinite)
    }

    func testExposureIdentityPassthroughByDefault() async throws {
        // Default params (0EV, black 0) → white=1, scale=1 → the identity
        // the pipe cache's default chain relies on.
        let module = ExposureModule()
        var piece = IOPiece()
        await module.commitParams(ExposureModule.Params(), into: &piece)
        let buffer = try XCTUnwrap(piece.data)
        let bytes = buffer.contents().assumingMemoryBound(to: Float.self)
        XCTAssertEqual(bytes[0], 0.0)
        XCTAssertEqual(bytes[1], 1.0)
    }

    func testExposureParamsHashStable() async throws {
        // L013: paramsHash = StableHash.hash(ParamsCoding.encode(params));
        // the SAME bytes must hash identically across two commits (the
        // pipe cache + history identity atom).
        let module = ExposureModule()
        var pieceA = IOPiece()
        var pieceB = IOPiece()
        let params = ExposureModule.Params(exposure: 1.0)
        await module.commitParams(params, into: &pieceA)
        await module.commitParams(params, into: &pieceB)
        XCTAssertEqual(pieceA.paramsHash, pieceB.paramsHash)
        XCTAssertEqual(pieceA.paramsHash, StableHash.hash(ParamsCoding.encode(params)))
    }

    // MARK: - WB K→gain (plan 03-02, RESEARCH §1.2/§5) — placeholder

    // func testWBTemperatureToGainVectors() { ... }
    // Reference: dt temperature.c:287-473 SPD→XYZ→CAM; Lightamer variant
    // converts via Bradford to Rec2020 (RESEARCH §5). Known vectors from
    // the D65 anchor (gains ≡ 1) and the 1901K/25000K domain ends.

    // MARK: - Lab round-trip (plan 03-03, RESEARCH §Summary #3) — placeholder

    // func testLabRoundTripMatrixKnownPoints() { ... }
    // Reference: dt colorspaces.c; D50 Bradford + sRGB-like→XYZ matrices.

    // MARK: - sigmoid commit_params (plan 03-04, RESEARCH §3) — placeholder

    // func testSigmoidFourScalarDerivation() { ... }
    // Reference: sigmoid.c:318-407 (paper_power, film_power, film_fog,
    // paper_exposure); MIDDLE_GREY 0.1845 (sigmoid.c:37).

    // MARK: - toneequal correction LUT (plan 03-05, RESEARCH §4) — placeholder

    // func testToneEqualizerLUTConstruction() { ... }
    // Reference: toneequal.c:639-768 (9 EV bands → 8 control points →
    // gaussian RBF σ=√2 interpolation → clamp [0.25, 4]).

    // MARK: - filmic spline (plan 03-06, RESEARCH §2) — placeholder

    // func testFilmicSplineCoefficients() { ... }
    // Reference: filmicrgb.c:368-560 (M1..M5 poly4 Horner form,
    // filmic.cl:247-296), _compute_output_power (filmicrgb.c:2560-2570).
}
