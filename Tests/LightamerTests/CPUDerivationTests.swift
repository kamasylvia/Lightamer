@testable import LightamerCore
import Foundation
@testable import LightamerIOP
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
            module.commitParams(params, into: &piece)

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
        module.commitParams(ExposureModule.Params(black: 1.5, exposure: 0), into: &piece)
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
        module.commitParams(ExposureModule.Params(), into: &piece)
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
        module.commitParams(params, into: &pieceA)
        module.commitParams(params, into: &pieceB)
        XCTAssertEqual(pieceA.paramsHash, pieceB.paramsHash)
        XCTAssertEqual(pieceA.paramsHash, StableHash.hash(ParamsCoding.encode(params)))
    }

    // MARK: - WB K→gain (plan 03-02-T1, RESEARCH §1.2/§5)

    // Reference values computed by `.work/plans/03-02/wb_reference.c` — a harness
    // that #includes darktable's OWN `src/external/cie_colorimetric_tables.c`
    // + verbatim copies of temperature.c:287-401's four helpers, linked
    // against the same lcms2 dt uses. The Swift side (WhiteBalanceMath) is
    // an independent transliteration; agreement <1e-4 (table quantization).
    private let wbXYZReferenceVectors: [(kelvin: Double, xyz: SIMD3<Double>)] = [
        // blackbody branch (< 4000K)
        (3200, SIMD3(1.0, 0.942360437068977, 0.419677826284935)),
        // daylight branch (≥ 4000K)
        (5000, SIMD3(0.964245565128246, 1.0, 0.824679094091967)),
        (6500, SIMD3(0.873271505962583, 0.918810224834716, 1.0)),
    ]

    /// K→XYZ cross-check vs the dt reference (RESEARCH §5: "XYZ 之前两侧
    /// 同源") at the plan's three temperatures, <1e-4.
    func testWBTemperatureToXYZMatchesDarktable() {
        for v in wbXYZReferenceVectors {
            let xyz = WhiteBalanceMath.temperatureToXYZ(v.kelvin)
            XCTAssertLessThan(
                abs(xyz.x - v.xyz.x), 1e-4, "K=\(v.kelvin) X"
            )
            XCTAssertLessThan(
                abs(xyz.y - v.xyz.y), 1e-4, "K=\(v.kelvin) Y"
            )
            XCTAssertLessThan(
                abs(xyz.z - v.xyz.z), 1e-4, "K=\(v.kelvin) Z"
            )
        }
    }

    /// The max-normalization is part of the dt-shared semantics
    /// (`_spectrum_to_XYZ`, temperature.c:376-381).
    func testWBTemperatureToXYZMaxNormalized() {
        for kelvin in [1901.0, 3200.0, 5000.0, 6504.0, 25000.0] {
            let xyz = WhiteBalanceMath.temperatureToXYZ(kelvin)
            XCTAssertEqual(
                max(xyz.x, max(xyz.y, xyz.z)), 1.0, accuracy: 1e-12,
                "K=\(kelvin): max component normalized to 1"
            )
        }
    }

    /// The D65 anchor: `gains(6504K, tint=1) ≡ (1,1,1)` — W and T go through
    /// the IDENTICAL conversion path, so the identity is exact; the anchor
    /// chromaticity matches Rec2020's white to ~1e-5 (harness-verified), so
    /// even 6500K sits within 1e-3 of the identity.
    func testWBD65AnchorIdentity() {
        let anchor = WhiteBalanceMath.kelvinTintToGains(
            kelvin: WhiteBalanceMath.d65Kelvin, tint: 1.0
        )
        XCTAssertEqual(anchor.x, 1.0, accuracy: 1e-12)
        XCTAssertEqual(anchor.y, 1.0, accuracy: 1e-12)
        XCTAssertEqual(anchor.z, 1.0, accuracy: 1e-12)

        let nearD65 = WhiteBalanceMath.kelvinTintToGains(kelvin: 6500, tint: 1.0)
        XCTAssertLessThan(abs(nearD65.x - 1.0), 1e-3, "6500K red ≈ 1")
        XCTAssertLessThan(abs(nearD65.y - 1.0), 1e-3, "6500K green ≈ 1")
        XCTAssertLessThan(abs(nearD65.z - 1.0), 1e-3, "6500K blue ≈ 1")
    }

    /// Direction assertions (plan T1 acceptance ②): raising K lowers the
    /// blue gain and raises the red gain (cooler light ⇒ redder gains); the
    /// tint Y-hack raises the green gain (dt semantics preserved).
    func testWBGainsDirection() {
        var previous = WhiteBalanceMath.kelvinTintToGains(kelvin: 1901, tint: 1.0)
        for kelvin in stride(from: 2500.0, through: 25000.0, by: 500.0) {
            let gains = WhiteBalanceMath.kelvinTintToGains(kelvin: kelvin, tint: 1.0)
            XCTAssertLessThanOrEqual(
                gains.z, previous.z + 1e-12,
                "K=\(kelvin): blue gain must not rise with K"
            )
            XCTAssertGreaterThanOrEqual(
                gains.x, previous.x - 1e-12,
                "K=\(kelvin): red gain must not fall with K"
            )
            XCTAssertGreaterThan(gains.x, 0)
            XCTAssertGreaterThan(gains.y, 0)
            XCTAssertGreaterThan(gains.z, 0)
            previous = gains
        }
        let tintUp = WhiteBalanceMath.kelvinTintToGains(kelvin: 5000, tint: 1.4)
        let tint1 = WhiteBalanceMath.kelvinTintToGains(kelvin: 5000, tint: 1.0)
        XCTAssertGreaterThan(tintUp.y, tint1.y, "tint > 1 raises the green gain (dt Y-hack)")
        XCTAssertLessThan(tintUp.y, 8.0, "tint gain stays in the [0,8] domain")
    }

    /// K↔gains round trip <1e-3 K (plan T2 acceptance; the bisection runs
    /// at 1e-4K — divergence #5). Tint round trip is algebraically exact
    /// (same path both directions) — pinned at 1e-9.
    func testWBKelvinGainsRoundTrip() {
        // NOTE: the 4000K blackbody/daylight branch point is EXCLUDED —
        // dt's bisection (which this inverts) converges across the tiny
        // locus gap there (a ~100K jump), by design of the shared algorithm
        // shape; within-branch round trips close to the bisection epsilon.
        var kelvins: [Double] = [1901, 2000, 2500, 3200, 3900, 4100, 5000, 6504, 10000, 18000, 25000]
        kelvins.append(contentsOf: stride(from: 2100.0, through: 24000.0, by: 1733.0))
        for kelvin in kelvins {
            for tint in [1.0, 0.8, 1.25] {
                let gains = WhiteBalanceMath.kelvinTintToGains(kelvin: kelvin, tint: tint)
                let roundTrip = WhiteBalanceMath.gainsToKelvinTint(gains: gains)
                XCTAssertEqual(
                    roundTrip.kelvin, kelvin, accuracy: 1e-3,
                    "K=\(kelvin) tint=\(tint): kelvin round trip"
                )
                XCTAssertEqual(
                    roundTrip.tint, tint, accuracy: 1e-6,
                    "K=\(kelvin) tint=\(tint): tint round trip"
                )
            }
        }
    }

    /// The eyedropper math (dt temperature.c:1933-1955 verbatim):
    /// `gains = clamp(1/picked, 0, 8)` green-normalized. A neutral pick is
    /// the (1,1,1) identity; a biased pick maps the bias channel up; the
    /// dt degenerate-channel and clamp behaviors are pinned.
    func testWBEyedropperNeutralSolve() {
        // Neutral pick → identity gains (the plan's 中性灰 criterion).
        let neutral = WhiteBalanceMath.gainsFromPicked(SIMD3(0.5, 0.5, 0.5))
        XCTAssertEqual(neutral.x, 1.0, accuracy: 1e-6)
        XCTAssertEqual(neutral.y, 1.0, accuracy: 1e-6)
        XCTAssertEqual(neutral.z, 1.0, accuracy: 1e-6)

        // Blue-biased pick (the T6 blue-cast flat scenario at 0.25 green):
        // 1/picked green-normalized ⇒ blue gain < 1, red gain > 1.
        let blueCast = WhiteBalanceMath.gainsFromPicked(SIMD3(0.2, 0.25, 0.3))
        XCTAssertEqual(blueCast.y, 1.0, accuracy: 1e-6)
        XCTAssertEqual(blueCast.x, 0.25 / 0.2, accuracy: 1e-6) // 1.25
        XCTAssertEqual(blueCast.z, 0.25 / 0.3, accuracy: 1e-6) // ~0.8333

        // dt's degenerate-channel guard: values ≤ 0.001 fall back to 1.0
        // (temperature.c:1946-1948). With green ≤ 0.001 the gnormal is 1.0,
        // so the other channels normalize against 1.0 (and green is then
        // unconditionally 1).
        let dark = WhiteBalanceMath.gainsFromPicked(SIMD3(0.0005, 0.0008, 0.4))
        XCTAssertEqual(dark.x, 1.0, "channel ≤ 0.001 ⇒ gain 1.0")
        XCTAssertEqual(dark.z, min(1.0 / 0.4, 8.0), accuracy: 1e-6)

        // Clamp at 8 (a near-black pick must not explode).
        let tiny = WhiteBalanceMath.gainsFromPicked(SIMD3(0.0011, 0.0012, 0.0011))
        XCTAssertLessThanOrEqual(tiny.x, 8.0)
        XCTAssertLessThanOrEqual(tiny.z, 8.0)

        // Applying the solve to the picked color neutralizes it exactly:
        // picked ∘ gains ≙ equal channels (gray-world closure).
        let picked = SIMD3<Float>(0.31, 0.44, 0.52)
        let gains = WhiteBalanceMath.gainsFromPicked(picked)
        let neutralized = picked * gains
        XCTAssertEqual(neutralized.x, neutralized.y, accuracy: 1e-5)
        XCTAssertEqual(neutralized.y, neutralized.z, accuracy: 1e-5)
    }

    // MARK: - shadhi derived params (plan 03-04-T2, RESEARCH §1.4;
    // dt shadhi.c:353-368 + :428-487) — formula transliteration + the
    // hand-computed overlay vectors. The kernel/GPU side is pinned by
    // ShadhiParityTests against the gen_fixtures float64 reference.

    /// Independent Double transliteration of the overlay loop (the golden
    /// reference's `shadhi_overlay` shape, unbound path).
    private func referenceOverlay(
        _ ta0: Double, _ ta1: Double, _ ta2: Double,
        tb0: Double, opacity: Double, xform: Double, ccorrect: Double,
        lowApprox: Double = 1e-6
    ) -> (Double, Double, Double) {
        var ta = [ta0, ta1, ta2]
        let tb = [tb0, 0.0, 0.0]
        let (lmin, lmax, halfmax, doublemax) = (0.0, 1.0, 0.5, 2.0)
        func sign(_ x: Double) -> Double { x < 0 ? -1 : 1 }
        var strength2 = opacity * opacity
        while strength2 > 0.0 {
            let la = ta[0] // unbound: no clamp (flags 127)
            let lb = (tb[0] - halfmax) * sign(opacity) * sign(lmax - la) + halfmax
            let lref = copysign(abs(la) > lowApprox ? 1 / abs(la) : 1 / lowApprox, la)
            let href = copysign(abs(1 - la) > lowApprox ? 1 / abs(1 - la) : 1 / lowApprox, 1 - la)
            let chunk = strength2 > 1.0 ? 1.0 : strength2
            let optrans = chunk * xform
            strength2 -= 1.0
            ta[0] = la * (1.0 - optrans)
                + (la > halfmax
                    ? lmax - (lmax - doublemax * (la - halfmax)) * (lmax - lb)
                    : doublemax * la * lb) * optrans
            let chroma = ta[0] * lref * ccorrect + (1.0 - ta[0]) * href * (1.0 - ccorrect)
            ta[1] = ta[1] * (1.0 - optrans) + (ta[1] + tb[1]) * chroma * optrans
            ta[2] = ta[2] * (1.0 - optrans) + (ta[2] + tb[2]) * chroma * optrans
        }
        return (ta[0], ta[1], ta[2])
    }

    /// The commit-time rescales and sign folds (shadhi.c:353-368).
    func testShadhiDerivedParams() {
        // defaults: shadows +50 → +1, highlights −50 → −1, compress 0.5,
        // whitepoint 1, scc = 1.0 (sign(shadows)=+1 folds 0.5→1.0 offset),
        // hcc = 0.5 (sign(−highlights)=+1 folds 0 → 0.5).
        let d = ShadhiModule.derive(ShadhiModule.Params())
        XCTAssertEqual(d.shadows, 1.0, accuracy: 1e-7)
        XCTAssertEqual(d.highlights, -1.0, accuracy: 1e-7)
        XCTAssertEqual(d.whitepoint, 1.0, accuracy: 1e-7)
        XCTAssertEqual(d.compress, 0.5, accuracy: 1e-7)
        XCTAssertEqual(d.shadowsCCorrect, 1.0, accuracy: 1e-7)
        XCTAssertEqual(d.highlightsCCorrect, 0.5, accuracy: 1e-7)
        XCTAssertEqual(d.unboundMask, 1)
        XCTAssertEqual(d.flags, ShadhiModule.unboundFlags)

        // rescale clamps: shadows=150 → 2×clamp(1.5)=2; highlights=−150 → −2.
        let clamped = ShadhiModule.derive(
            ShadhiModule.Params(shadows: 150, highlights: -150)
        )
        XCTAssertEqual(clamped.shadows, 2.0, accuracy: 1e-7)
        XCTAssertEqual(clamped.highlights, -2.0, accuracy: 1e-7)

        // compress upper clamp 0.99 (shadhi.c:359-360) and whitepoint
        // floor 0.01 (shadhi.c:358).
        let c99 = ShadhiModule.derive(ShadhiModule.Params(whitepoint: 100, compress: 100))
        XCTAssertEqual(c99.compress, 0.99, accuracy: 1e-7)
        XCTAssertEqual(c99.whitepoint, 0.01, accuracy: 1e-7)

        // sign folds flip with the strength sign (shadhi.c:361-364):
        // shadows=−50 → scc = (1−0.5)×(−1)+0.5 = 0; highlights=+50 →
        // hcc = (0.5−0.5)×sign(−1)+0.5 = 0.5.
        let flipped = ShadhiModule.derive(
            ShadhiModule.Params(shadows: -50, highlights: 50)
        )
        XCTAssertEqual(flipped.shadowsCCorrect, 0.0, accuracy: 1e-7)
        XCTAssertEqual(flipped.highlightsCCorrect, 0.5, accuracy: 1e-7)

        // radius clamp (shadhi.c:354): < 0.1 → 0.1.
        XCTAssertEqual(
            ShadhiModule.derive(ShadhiModule.Params(radius: 0.01)).radius, 0.1, accuracy: 1e-7
        )
    }

    /// Hand-computed overlay vectors (the plan's 标量公式已知向量):
    /// highlights single chunk + shadows multi-chunk (strength² > 1
    /// applies the overlay twice).
    func testShadhiOverlayKnownVectors() {
        // Vector A — highlights, strength 1 (one chunk), xform 0.5,
        // ccorrect 0.5: lb = (0.25−0.5)(−1)(1)+0.5 = 0.75 == la;
        // la > 0.5 branch: 1 − 0.5·0.25 = 0.875; ta0 = 0.8125;
        // lref = 4/3, href = 4 → chroma = 0.8125·(2/3)·0.5 + 0.1875·2
        // = 0.916666…; ta1 = 0.5·0.02 + 0.02·0.916666·0.5 = 0.0191666…;
        // ta2 = −0.015 − 0.03·0.916666·0.5 = −0.02875.
        let a = referenceOverlay(
            0.75, 0.02, -0.03, tb0: 0.25, opacity: -1.0, xform: 0.5, ccorrect: 0.5
        )
        XCTAssertEqual(a.0, 0.8125, accuracy: 1e-12)
        XCTAssertEqual(a.1, 0.01916666666666667, accuracy: 1e-12)
        XCTAssertEqual(a.2, -0.02875, accuracy: 1e-12)

        // Vector B — shadows, strength 1.5 (strength² = 2.25 → THREE
        // chunks 1+1+0.25), xform 0.5, ccorrect 0.75. Hand trace:
        // chunk1 la=0.25→0.3125, chunk2 →0.390625, chunk3 (0.25 weight)
        // → 0.4150390625.
        let b = referenceOverlay(
            0.25, 0.0, 0.0, tb0: 0.75, opacity: 1.5, xform: 0.5, ccorrect: 0.75
        )
        XCTAssertEqual(b.0, 0.4150390625, accuracy: 1e-12)

        // Zero strength → identity (the identity-params acceptance).
        let z = referenceOverlay(
            0.75, 0.02, -0.03, tb0: 0.25, opacity: 0.0, xform: 0.5, ccorrect: 0.5
        )
        XCTAssertEqual(z.0, 0.75, accuracy: 1e-15)
        XCTAssertEqual(z.1, 0.02, accuracy: 1e-15)
        XCTAssertEqual(z.2, -0.03, accuracy: 1e-15)

        // xform = 0 → the pass is a no-op even at full strength (the
        // compress threshold semantics — tb below the shadow window).
        let n = referenceOverlay(
            0.75, 0.02, -0.03, tb0: 0.25, opacity: 1.0, xform: 0.0, ccorrect: 0.5
        )
        XCTAssertEqual(n.0, 0.75, accuracy: 1e-15)
    }

    // MARK: - Lab round-trip (plan 03-03, RESEARCH §Summary #3) — covered
    // by LabRoundTripTests (Plan 03-03-T1); placeholder retired 03-03.

    // MARK: - sigmoid commit_params (plan 03-04-T3/T4, RESEARCH §3)

    /// Independent Double transliteration of sigmoid.c:318-407 (kept
    /// separate from SigmoidDerivation on purpose — dual implementation).
    private func referenceSigmoidDerive(
        contrast: Double, skew: Double, white: Double, black: Double
    ) -> (paperPower: Double, filmPower: Double, filmFog: Double, paperExposure: Double, whiteTarget: Double, blackTarget: Double) {
        let grey = 0.1845
        func f(_ v: Double, magnitude: Double, paperExp: Double, fog: Double, filmPower: Double, paperPower: Double) -> Double {
            let clamped = max(v, 0)
            let fr = pow(fog + clamped, filmPower)
            let pr = magnitude * pow(fr / (paperExp + fr), paperPower)
            return pr.isNaN ? magnitude : pr
        }
        let refPaperExposure = pow(grey, contrast) * (1.0 / grey - 1.0)
        func slope(_ magnitude: Double, _ paperExp: Double, _ fog: Double, _ fp: Double, _ pp: Double) -> Double {
            (f(grey + 1e-6, magnitude: magnitude, paperExp: paperExp, fog: fog, filmPower: fp, paperPower: pp)
                - f(grey - 1e-6, magnitude: magnitude, paperExp: paperExp, fog: fog, filmPower: fp, paperPower: pp)) / 2e-6
        }
        let refSlope = slope(1.0, refPaperExposure, 0.0, contrast, 1.0)
        let paperPower = pow(5.0, -skew)
        let tempWhite = 0.01 * white
        let tempWgr = pow(tempWhite / grey, 1.0 / paperPower) - 1.0
        let tempPaperExposure = grey * tempWgr
        let tempSlope = slope(tempWhite, tempPaperExposure, 0.0, 1.0, paperPower)
        let filmPower = refSlope / tempSlope
        let whiteTarget = 0.01 * white
        let blackTarget = 0.01 * black
        let wgr = pow(whiteTarget / grey, 1.0 / paperPower) - 1.0
        let wbr = pow(blackTarget / whiteTarget, -1.0 / paperPower) - 1.0
        let filmFog = grey * pow(wgr, 1.0 / filmPower) / (pow(wbr, 1.0 / filmPower) - pow(wgr, 1.0 / filmPower))
        let paperExposure = pow(filmFog + grey, filmPower) * wgr
        return (paperPower, filmPower, filmFog, paperExposure, whiteTarget, blackTarget)
    }

    /// The four scalars vs the independent Double mirror — default params
    /// plus the pinned preset groups (neutral gray / ACES-like / rgb_ratio
    /// / smooth), <1e-9 (Double internals; published Float quantizes at
    /// ~6e-8, asserted separately).
    func testSigmoidFourScalarDerivation() {
        let groups: [(String, Double, Double, Double, Double)] = [
            ("default", 1.5, 0.0, 100.0, 0.0152),
            ("neutral gray preset", 1.22, 0.65, 100.0, 0.0152),
            ("ACES-like preset", 1.6, -0.2, 100.0, 0.0152),
            ("reinhard rgb_ratio", 1.0, 0.0, 100.0, 0.0152),
            ("smooth preset", 1.5, -0.2, 100.0, 0.0152),
        ]
        for (name, contrast, skew, white, black) in groups {
            let (_, trace) = SigmoidDerivation.derive(
                middleGreyContrast: contrast, contrastSkewness: skew,
                displayWhiteTarget: white, displayBlackTarget: black,
                huePreservationPercent: 100
            )
            let ref = referenceSigmoidDerive(contrast: contrast, skew: skew, white: white, black: black)
            XCTAssertEqual(trace.paperPower, ref.paperPower, accuracy: 1e-12, "\(name) paper_power")
            XCTAssertEqual(trace.filmPower, ref.filmPower, accuracy: 1e-9, "\(name) film_power")
            XCTAssertEqual(trace.filmFog, ref.filmFog, accuracy: 1e-9, "\(name) film_fog")
            XCTAssertEqual(trace.paperExposure, ref.paperExposure, accuracy: 1e-9, "\(name) paper_exposure")
            XCTAssertEqual(trace.whiteTarget, ref.whiteTarget, accuracy: 1e-12, "\(name) white_target")
            XCTAssertEqual(trace.blackTarget, ref.blackTarget, accuracy: 1e-12, "\(name) black_target")

            // Published float32 scalars sit on the float grid of the Double
            // values (the kernel sees exactly these).
            let s = SigmoidDerivation.derive(
                middleGreyContrast: contrast, contrastSkewness: skew,
                displayWhiteTarget: white, displayBlackTarget: black,
                huePreservationPercent: 100
            ).scalars
            XCTAssertEqual(Float(trace.paperPower), s.paperPower)
            XCTAssertEqual(Float(trace.filmPower), s.filmPower)
            XCTAssertEqual(Float(trace.filmFog), s.filmFog)
            XCTAssertEqual(Float(trace.paperExposure), s.paperExposure)
        }
    }

    /// The constraint set the derivation exists to fulfill: f(0) = black,
    /// f(MIDDLE_GREY) = 0.1845, f(∞) = white — evaluated through the
    /// production curve at the derived scalars.
    func testSigmoidCurveConstraints() {
        let groups: [(String, Double, Double)] = [
            ("default", 1.5, 0.0),
            ("neutral", 1.22, 0.65),
            ("aces", 1.6, -0.2),
        ]
        for (name, contrast, skew) in groups {
            let (s, trace) = SigmoidDerivation.derive(
                middleGreyContrast: contrast, contrastSkewness: skew,
                displayWhiteTarget: 100, displayBlackTarget: 0.0152,
                huePreservationPercent: 100
            )
            // Constraint gate at the derivation's native precision (the
            // Double trace) — exact by construction.
            func fD(_ v: Double) -> Double {
                SigmoidDerivation.generalizedLoglogisticSigmoid(
                    value: v, magnitude: trace.whiteTarget,
                    paperExposure: trace.paperExposure, filmFog: trace.filmFog,
                    filmPower: trace.filmPower, paperPower: trace.paperPower
                )
            }
            // And through the float32-published scalars the kernel consumes
            // (the publish quantizes onto the float32 grid — ~1e-8 absolute
            // here, a float32-grid effect, NOT a derivation error).
            func fF(_ v: Double) -> Double {
                SigmoidDerivation.generalizedLoglogisticSigmoid(
                    value: v, magnitude: Double(s.whiteTarget),
                    paperExposure: Double(s.paperExposure), filmFog: Double(s.filmFog),
                    filmPower: Double(s.filmPower), paperPower: Double(s.paperPower)
                )
            }
            XCTAssertEqual(fD(0.0), 0.000152, accuracy: 1e-12, "\(name) f(0) = black (Double)")
            XCTAssertEqual(
                fD(SigmoidDerivation.middleGrey), SigmoidDerivation.middleGrey,
                accuracy: 1e-12, "\(name) f(grey) = MIDDLE_GREY (Double)"
            )
            XCTAssertEqual(fD(1e8), 1.0, accuracy: 1e-9, "\(name) f(∞) = white (Double)")
            XCTAssertEqual(fF(0.0), 0.000152, accuracy: 1e-8, "\(name) f(0) = black (float32 grid)")
            XCTAssertEqual(
                fF(SigmoidDerivation.middleGrey), SigmoidDerivation.middleGrey,
                accuracy: 1e-7, "\(name) f(grey) = MIDDLE_GREY (float32 grid)"
            )
            XCTAssertEqual(fF(1e8), 1.0, accuracy: 1e-7, "\(name) f(∞) = white (float32 grid)")
            // And the grey anchor is the dt constant.
            XCTAssertEqual(SigmoidDerivation.middleGrey, 0.1845, accuracy: 0)
            XCTAssertEqual(trace.huePreservation, 1.0, accuracy: 1e-12)
        }
    }

    /// Domain-edge safety: skew = ±1 and the parameter extremes must not
    /// produce NaN/Inf scalars (the kernel would poison the pipe).
    func testSigmoidExtremeParamsNoNaN() {
        for skew: Double in [-1.0, -0.999, 0.999, 1.0] {
            for contrast: Double in [0.1, 1.0, 10.0] {
                let s = SigmoidDerivation.derive(
                    middleGreyContrast: contrast, contrastSkewness: skew,
                    displayWhiteTarget: 100, displayBlackTarget: 0.0152,
                    huePreservationPercent: 100
                ).scalars
                XCTAssertFalse(s.paperPower.isNaN, "skew \(skew) contrast \(contrast)")
                XCTAssertFalse(s.paperPower.isInfinite)
                XCTAssertFalse(s.filmPower.isNaN, "skew \(skew) contrast \(contrast)")
                XCTAssertFalse(s.filmPower.isInfinite)
                XCTAssertFalse(s.filmFog.isNaN, "skew \(skew) contrast \(contrast)")
                XCTAssertFalse(s.paperExposure.isNaN, "skew \(skew) contrast \(contrast)")
                XCTAssertFalse(s.paperExposure.isInfinite)
                XCTAssertGreaterThan(s.paperPower, 0)
            }
        }
        // paper_power = 5^(−skew) known vectors.
        XCTAssertEqual(
            SigmoidDerivation.derive(middleGreyContrast: 1.5, contrastSkewness: 0,
                                     displayWhiteTarget: 100, displayBlackTarget: 0.0152,
                                     huePreservationPercent: 100).trace.paperPower,
            1.0, accuracy: 1e-12
        )
        XCTAssertEqual(
            SigmoidDerivation.derive(middleGreyContrast: 1.5, contrastSkewness: 1,
                                     displayWhiteTarget: 100, displayBlackTarget: 0.0152,
                                     huePreservationPercent: 100).trace.paperPower,
            0.2, accuracy: 1e-12
        )
        XCTAssertEqual(
            SigmoidDerivation.derive(middleGreyContrast: 1.5, contrastSkewness: -1,
                                     displayWhiteTarget: 100, displayBlackTarget: 0.0152,
                                     huePreservationPercent: 100).trace.paperPower,
            5.0, accuracy: 1e-12
        )
    }

    // MARK: - toneequal correction LUT (plan 03-05, RESEARCH §4) — placeholder

    // func testToneEqualizerLUTConstruction() { ... }
    // Reference: toneequal.c:639-768 (9 EV bands → 8 control points →
    // gaussian RBF σ=√2 interpolation → clamp [0.25, 4]).

    // MARK: - filmicrgb F0 (plan 03-06-T1, RESEARCH §2.1 CPU 段八步)
    //
    // Reference: filmicrgb.c:2732-3046 (compute_spline v1→v3),
    // :2571-2581 (_compute_output_power), :2399-2401 (norm bounds) —
    // dual implementation (textbook, in-file) + hand-computed anchors.

    /// Independent textbook V3 spline (the production `FilmicSpline.derive`
    /// is a dt-source transliteration; this is the same math re-derived).
    private func referenceSplineV3(
        blackSource: Double, whiteSource: Double, outputPower: Double,
        latitudePercent: Double, contrast: Double, balance: Double,
        blackTarget: Double, whiteTarget: Double, greyTarget: Double
    ) -> (greyDisplay: Double, latMin: Double, latMax: Double, contrast: Double,
          toeLog: Double, shoulderLog: Double, intercept: Double) {
        let greyDisplay = pow(0.1845, 1.0 / outputPower)
        let dr = whiteSource - blackSource
        let greyLog = abs(blackSource) / dr
        let blackDisplay = pow(max(min(blackTarget, greyTarget), 0.0) / 100.0, 1.0 / outputPower)
        let whiteDisplay = pow(max(whiteTarget, greyTarget) / 100.0, 1.0 / outputPower)
        let bal = max(-50.0, min(50.0, balance)) / 100.0
        let lat = max(0.0, min(100.0, latitudePercent)) / 100.0
        let slope = contrast * dr / 8.0
        let minContrast = max(
            max(1.0, (whiteDisplay - greyDisplay) / (1.0 - greyLog)),
            (greyDisplay - blackDisplay) / (greyLog - 0.0)
        ) + 0.01
        let raw = slope / (outputPower * pow(greyDisplay, outputPower - 1.0))
        let c = min(max(raw, minContrast), 100.0)
        let intercept = greyDisplay - c * greyLog
        let xmin = (blackDisplay + 0.01 * (whiteDisplay - blackDisplay) - intercept) / c
        let xmax = (whiteDisplay - 0.01 * (whiteDisplay - blackDisplay) - intercept) / c
        var toeLog = (1.0 - lat) * greyLog + lat * xmin
        var shoulderLog = (1.0 - lat) * greyLog + lat * xmax
        let bc = bal > 0 ? 2.0 * bal * (shoulderLog - greyLog) : 2.0 * bal * (greyLog - toeLog)
        toeLog -= bc
        shoulderLog -= bc
        toeLog = max(toeLog, xmin)
        shoulderLog = min(shoulderLog, xmax)
        return (greyDisplay, toeLog, shoulderLog, c, toeLog, shoulderLog, intercept)
    }

    func testFilmicOutputPowerAndNormBounds() {
        // The hand-computed default anchors (black −8EV / white +4EV /
        // grey target 18.45%): output_power = log(0.1845)/log(−8/12),
        // grey_display = 0.1845^(1/op) = 2/3 exactly, norm bounds =
        // 0.1845·2^(0−8) and 0.1845·2^(12−8).
        let op = FilmicSpline.computeOutputPower(
            greyPointTarget: 18.45, blackPointSource: -8, whitePointSource: 4
        )
        XCTAssertEqual(op, 4.168313824554027, accuracy: 1e-12)
        XCTAssertEqual(
            FilmicSpline.computeOutputPower(
                greyPointTarget: 12.0, blackPointSource: -8, whitePointSource: 4
            ),
            log(0.12) / log(8.0 / 12.0), accuracy: 1e-12
        )

        let bounds = FilmicSpline.normBounds(greySource: 0.1845, blackSource: -8, dynamicRange: 12)
        XCTAssertEqual(bounds.min, 0.1845 * pow(2, -8), accuracy: 1e-12) // 0.000720703125
        XCTAssertEqual(bounds.max, 0.1845 * pow(2, 4), accuracy: 1e-12)  // 2.952
        XCTAssertEqual(bounds.min, 0.000720703125, accuracy: 1e-15)
        XCTAssertEqual(bounds.max, 2.952, accuracy: 1e-12)

        // clamp_simd NaN semantics (IEEE fmin/fmax passthrough).
        XCTAssertEqual(FilmicSpline.clampSIMD(.nan), 1.0)
        XCTAssertEqual(FilmicSpline.clampSIMD(-3), 0.0)
        XCTAssertEqual(FilmicSpline.clampSIMD(1.5), 1.0)

        // log/exp tonemapping round-trip.
        let encoded = FilmicSpline.logTonemapping(0.738, grey: 0.1845, black: -8, dynamicRange: 12)
        XCTAssertEqual(
            FilmicSpline.expTonemapping(encoded, grey: 0.1845, black: -8, dynamicRange: 12),
            0.738, accuracy: 1e-12
        )
    }

    func testFilmicSplineDefaultCoefficients() throws {
        // Defaults: the grey node sits exactly on the diagonal
        // (grey_log = grey_display = 2/3), latitude 0.01% → a razor-thin
        // linear segment, poly4 toe/shoulder.
        let effective = FilmicRGBModule.effectiveParams(FilmicRGBModule.Params())
        let (spline, trace) = FilmicSpline.derive(params: effective)
        let ref = referenceSplineV3(
            blackSource: -8, whiteSource: 4, outputPower: Double(effective.outputPower),
            latitudePercent: 0.01, contrast: 1.0, balance: 0,
            blackTarget: 0.01517634, whiteTarget: 100, greyTarget: 18.45
        )
        // The auto output power anchor itself (hand value 4.168313824554027
        // through the Float32 publication).
        XCTAssertEqual(Double(effective.outputPower), 4.168313824554027, accuracy: 1e-6)

        // grey_display = 0.1845^(1/power) sits exactly on the 2/3 diagonal
        // at the exact hand power; through the Float32-published power it
        // lands within ~3e-8.
        XCTAssertEqual(trace.greyDisplay, 2.0 / 3.0, accuracy: 1e-7)
        XCTAssertEqual(trace.greyLog, 2.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(trace.dynamicRange, 12, accuracy: 1e-12)
        // (float32-published grid: latitudeMin/Max/intercept ride through
        // Float — ~6e-8 relative; the Double TRACE fields stay exact.)
        XCTAssertEqual(trace.toeLog, ref.latMin, accuracy: 1e-12)
        XCTAssertEqual(trace.shoulderLog, ref.latMax, accuracy: 1e-12)
        XCTAssertEqual(trace.contrast, ref.contrast, accuracy: 1e-6,
                       "trace contrast through the Float32 output power")
        XCTAssertEqual(trace.linearIntercept, ref.intercept, accuracy: 1e-6)
        XCTAssertEqual(Double(spline.latitudeMin), ref.latMin, accuracy: 1e-6)
        XCTAssertEqual(Double(spline.latitudeMax), ref.latMax, accuracy: 1e-6)
        XCTAssertFalse(spline.contrastClamped, "default contrast must not clamp")

        // The curve passes through the grey node by construction and is
        // continuous at the toe/shoulder nodes.
        let greyLog = 2.0 / 3.0
        // (accuracy = the float32 coefficient grid the kernel consumes —
        // the published M/latitude values are Float, ~1e-7 relative.)
        XCTAssertEqual(
            FilmicSpline.evaluate(greyLog, spline: spline),
            2.0 / 3.0, accuracy: 1e-6
        )
        XCTAssertEqual(
            FilmicSpline.evaluate(Double(spline.latitudeMin), spline: spline),
            Double(spline.y[1]), accuracy: 1e-6
        )
        XCTAssertEqual(
            FilmicSpline.evaluate(Double(spline.latitudeMax), spline: spline),
            Double(spline.y[3]), accuracy: 1e-6
        )
        // Endpoint pinning: f(0) = black_display, f(1) = white_display.
        XCTAssertEqual(FilmicSpline.evaluate(0, spline: spline), Double(spline.y[0]), accuracy: 1e-6)
        XCTAssertEqual(FilmicSpline.evaluate(1, spline: spline), Double(spline.y[4]), accuracy: 1e-5)
    }

    func testFilmicSplineVariedParamsAgainstReference() {
        // latitude/balance/contrast 变参组 against the independent
        // reference (10 param points spanning the slider ranges).
        let points: [(lat: Double, contrast: Double, balance: Double)] = [
            (0.01, 1.0, 0), (10, 1.0, 0), (50, 1.5, 0), (99, 1.0, 0),
            (20, 2.5, 0), (20, 1.0, 25), (20, 1.0, -40), (35, 3.0, 12),
            (5, 0.5, -10), (80, 4.0, 30),
        ]
        for p in points {
            let params = FilmicRGBModule.effectiveParams(FilmicRGBModule.Params(
                latitude: Float(p.lat), contrast: Float(p.contrast), balance: Float(p.balance)
            ))
            let (spline, trace) = FilmicSpline.derive(params: params)
            let ref = referenceSplineV3(
                blackSource: -8, whiteSource: 4, outputPower: Double(params.outputPower),
                latitudePercent: p.lat, contrast: p.contrast, balance: p.balance,
                blackTarget: 0.01517634, whiteTarget: 100, greyTarget: 18.45
            )
            XCTAssertEqual(Double(spline.latitudeMin), ref.latMin, accuracy: 1e-6,
                           "lat \(p.lat) contrast \(p.contrast) balance \(p.balance)")
            XCTAssertEqual(Double(spline.latitudeMax), ref.latMax, accuracy: 1e-6,
                           "lat \(p.lat) contrast \(p.contrast) balance \(p.balance)")
            XCTAssertEqual(trace.contrast, ref.contrast, accuracy: 1e-6,
                           "contrast at lat \(p.lat) c \(p.contrast) b \(p.balance)")
            // Node continuity + grey anchor for every variation.
            XCTAssertEqual(
                FilmicSpline.evaluate(2.0 / 3.0, spline: spline), trace.greyDisplay,
                accuracy: 1e-6
            )
            XCTAssertFalse(trace.toeLog.isNaN)
            XCTAssertFalse(trace.shoulderDisplay.isNaN)
        }
    }

    func testFilmicSplineVersionBranches() {
        // v1: black/white display NOT power-folded (the buggy legacy path).
        let v1 = FilmicSpline.derive(
            greyPointSource: 18.45, blackPointSource: -8, whitePointSource: 4,
            securityFactor: 0, greyPointTarget: 18.45, blackPointTarget: 2, whitePointTarget: 90,
            outputPower: 4, latitude: 10, contrast: 1, balance: 0,
            shadows: .poly4, highlights: .poly4, splineVersion: .v1, customGrey: false
        ).spline
        XCTAssertEqual(v1.y[0], 2.0 / 100.0, accuracy: 1e-12, "v1: raw % target")
        XCTAssertEqual(v1.y[4], 90.0 / 100.0, accuracy: 1e-12, "v1: raw % target")

        // v2: the fixed power-folded targets.
        let v2 = FilmicSpline.derive(
            greyPointSource: 18.45, blackPointSource: -8, whitePointSource: 4,
            securityFactor: 0, greyPointTarget: 18.45, blackPointTarget: 2, whitePointTarget: 90,
            outputPower: 4, latitude: 10, contrast: 1, balance: 0,
            shadows: .poly4, highlights: .poly4, splineVersion: .v2, customGrey: false
        )
        XCTAssertEqual(v2.spline.y[0], pow(0.02, 0.25), accuracy: 1e-12, "v2: ^(1/power)")
        XCTAssertEqual(v2.spline.y[4], pow(0.90, 0.25), accuracy: 1e-12, "v2: ^(1/power)")
        // v2 uses the log-domain latitude model (contrast clamp [1.00001, 6]
        // lifts contrast=1 to the clamp floor).
        XCTAssertEqual(v2.trace.contrast, 1.00001, accuracy: 1e-6)

        // v3: slope from contrast only (covered by the other tests).
        let v3 = FilmicSpline.derive(
            greyPointSource: 18.45, blackPointSource: -8, whitePointSource: 4,
            securityFactor: 0, greyPointTarget: 18.45, blackPointTarget: 2, whitePointTarget: 90,
            outputPower: 4, latitude: 10, contrast: 1, balance: 0,
            shadows: .poly4, highlights: .poly4, splineVersion: .v3, customGrey: false
        )
        XCTAssertEqual(v3.spline.y[0], pow(0.02, 0.25), accuracy: 1e-12)
        XCTAssertNotEqual(v3.trace.contrast, 1.0, accuracy: 1e-6, "v3 contrast re-derived")
    }

    func testFilmicSplineCurveTypes() {
        // rational/poly3/poly4 × toe/shoulder: node continuity everywhere.
        for toe in FilmicSpline.CurveType.allCases {
            for shoulder in FilmicSpline.CurveType.allCases {
                let params = FilmicRGBModule.effectiveParams(FilmicRGBModule.Params(
                    latitude: 25, contrast: 1.8,
                    shadows: toe, highlights: shoulder
                ))
                let (spline, _) = FilmicSpline.derive(params: params)
                let atToe = FilmicSpline.evaluate(Double(spline.latitudeMin) - 1e-9, spline: spline)
                let atToePlus = FilmicSpline.evaluate(Double(spline.latitudeMin) + 1e-9, spline: spline)
                XCTAssertEqual(atToe, atToePlus, accuracy: 1e-4,
                               "toe/linear continuity \(toe)/\(shoulder)")
                let atSh = FilmicSpline.evaluate(Double(spline.latitudeMax) - 1e-9, spline: spline)
                let atShPlus = FilmicSpline.evaluate(Double(spline.latitudeMax) + 1e-9, spline: spline)
                XCTAssertEqual(atSh, atShPlus, accuracy: 1e-4,
                               "linear/shoulder continuity \(toe)/\(shoulder)")
            }
        }
    }

    func testFilmicIllegalCombinationsNoNaN() {
        // latitude > 100 / negative contrast / extreme balance — clamped,
        // never NaN (T1 acceptance).
        let combos: [FilmicRGBModule.Params] = [
            FilmicRGBModule.Params(latitude: 250, contrast: -3, balance: -80),
            FilmicRGBModule.Params(latitude: -5, contrast: 50, balance: 120),
            FilmicRGBModule.Params(blackPointSource: -0.1, whitePointSource: 0.1),
            FilmicRGBModule.Params(blackPointSource: -16, whitePointSource: 16, latitude: 99, contrast: 5),
            FilmicRGBModule.Params(
                greyPointSource: 18.45, blackPointSource: -8, whitePointSource: 4,
                securityFactor: 0, greyPointTarget: 1, blackPointTarget: 20, whitePointTarget: 0.5,
                outputPower: 4, latitude: 10, contrast: 1, balance: 0, noiseLevel: 0.2,
                preserveColor: .powerNorm, version: .v5, autoHardness: true, customGrey: true
            ),
        ]
        for params in combos {
            let (spline, trace) = FilmicSpline.derive(params: FilmicRGBModule.effectiveParams(params))
            for x in stride(from: 0.0, through: 1.0, by: 0.05) {
                let y = FilmicSpline.evaluate(x, spline: spline)
                XCTAssertFalse(y.isNaN, "NaN at x=\(x) for \(params)")
            }
            XCTAssertFalse(trace.contrast.isNaN)
            // NOTE: dt does NOT reorder overlapping toe/shoulder nodes under
            // extreme balance (the "nodes overlap" comment at filmicrgb.c
            // :2876-2881 only documents the intent); no ordering assert.
        }
    }

}
