@testable import LightamerCore
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// ColorWheelsLegacyConvertTests (Plan M9-4 T1, X2; B-1 repair round) — the
// conversion anchor golden face: the exact lift→offset leg, the gamma/gain
// Gauss-Newton fit against OUR frozen v1 truth model (common domain ≤0.035
// stops / extreme domain ≈0.13 stops — the re-measured H-SP3 bands), the
// semantic regression (a gamma-non-neutral legacy document must keep its
// look AND its brightness direction at upgrade — acceptance-2ND B-1), the
// no-truncation promise (what renders IS the fitted value), the fit-K
// mean/zero-mean split with the unit-circle clamped disc inversion, the
// neutral passthrough, and the v3 JSON shape round trip.
//
// Upstream anchors: `VersionOneLiftLoadsAsTheSameOffsetInStops` (0.06·B
// form) and `VersionOneValuesRenderWithinFiveHundredthsOfAStop` (the 25
// sample render parity at 0.05 stops) from
// git show e1effd8:alcedo_studio/tests/edit/graph/color_wheel_tone_test.cpp
// — ADAPTED by the B-1 repair: the truth model is OUR frozen v1 arm
// (`|c+lift|^(1/γ_store)·gain`, ColorWheelsModule.reference / the frozen
// kernel), NOT the upstream direct exponent (upstream v1 stores γ as the
// direct exponent; our M2-5 port stores the reciprocal form). The lift
// anchor carries over verbatim (the lift leg is the offset exactly on
// both readings).
// ─────────────────────────────────────────────────────────────────────────

final class ColorWheelsLegacyConvertTests: XCTestCase {

    /// The v1 legacy operation on one ACEScc value — OUR FROZEN form
    /// (acceptance-2ND B-1 repair): `|c + lift|^(1/γ_store)·gain`. This is
    /// the independent Float64 truth model (the lane-2 probe form,
    /// formalized); it matches ColorWheelsModule.reference and the frozen
    /// `grade_color_wheels` kernel body and is intentionally written
    /// inline (independent of the production code paths under test).
    private func legacyApply(
        _ c: Double, lift: Double, gamma: Double, gain: Double
    ) -> Double {
        copysign(
            pow(abs(c + lift), 1.0 / max(gamma, 1.0e-4)), c
        ) * gain
    }

    private func acesccOfEv(_ ev: Double) -> Double {
        Double(ColorWheelsModule.acesccMiddleGrey)
            + ev / Double(ColorWheelsModule.acesccB)
    }

    /// Max render parity error IN STOPS between the legacy operation and
    /// the converted quad over the ±6 EV fit range (25 samples, per
    /// channel; the upstream anchor rides this exact grid).
    private func renderParityStops(
        legacy: (lift: SIMD3<Double>, gamma: SIMD3<Double>, gain: SIMD3<Double>),
        converted: ColorWheelsModule.Params
    ) -> Double {
        let b = Double(ColorWheelsModule.acesccB)
        let resolved = ColorWheelsModule.resolveToneWheelKernelParams(of: converted)
        var worst = 0.0
        for i in 0..<25 {
            let ev = -6.0 + 12.0 * Double(i) / 24.0
            let input = acesccOfEv(ev)
            for ch in 0..<3 {
                let expected = legacyApply(
                    input, lift: legacy.lift[ch], gamma: legacy.gamma[ch],
                    gain: legacy.gain[ch])
                let actual = Double(
                    ColorWheelsModule.applyToneWheels(
                        Float(input), channel: ch, params: resolved))
                worst = max(worst, abs(actual - expected) * b)
            }
        }
        return worst
    }

    // MARK: - Exact leg: lift → offset

    /// Upstream VersionOneLiftLoadsAsTheSameOffsetInStops — the v1 lift
    /// (color+luma in ACEScc codes) becomes the Offset stops exactly:
    /// K = (color_offset + luminance_offset) × B.
    func testLegacyLiftBecomesOffsetExactly() {
        var legacy = ColorWheelsModule.Params()
        legacy.lift = ColorWheelControl(
            colorOffset: SIMD3(0.05, -0.02, 0.01), luminanceOffset: 0.01)
        let converted = ColorWheelsLegacyConvert.convertLegacyColorWheel(legacy)
        let b = ColorWheelsModule.acesccB
        let offsetStops = ColorWheelsModule.controlChannelStops(converted.offset!)
        XCTAssertEqual(Double(offsetStops.x), 0.06 * Double(b), accuracy: 1.0e-4)
        XCTAssertEqual(Double(offsetStops.y), -0.01 * Double(b), accuracy: 1.0e-4)
        XCTAssertEqual(Double(offsetStops.z), 0.02 * Double(b), accuracy: 1.0e-4)
        // Neutral gamma/gain short-circuit → the fitted wheels are all-zero;
        // the fitted lift stays all-zero (v1 lift HAS no lift leg).
        XCTAssertTrue(converted.lift.colorOffset == .zero && converted.lift.luminanceOffset == 0)
        XCTAssertTrue(converted.gamma.colorOffset == .zero && converted.gamma.luminanceOffset == 0)
        XCTAssertTrue(converted.gain.colorOffset == .zero && converted.gain.luminanceOffset == 0)
    }

    // MARK: - Fit parity

    /// The conversion anchor's render parity (adapted from upstream
    /// VersionOneValuesRenderWithinFiveHundredthsOfAStop): the common-domain
    /// conversion renders within the 0.035-stop band of OUR frozen v1 look
    /// (the truth model is `legacyApply` above — the reciprocal form).
    /// Re-pinned by the B-1 repair: measured 0.0313 stops on the reciprocal
    /// target (was 0.0308 on the upstream direct-exponent target — the band
    /// holds; the near-neutral domain note lives in M9-4-DECISIONS §5/§13).
    func testCommonDomainFitParity() {
        let lift = SIMD3<Double>(0.02, -0.01, 0.0)
        let gamma = SIMD3(0.92, 1.0, 1.06)
        let gain = SIMD3(1.06, 1.0, 0.95)
        var legacy = ColorWheelsModule.Params()
        legacy.lift = ColorWheelControl(colorOffset: SIMD3(Float(lift.x), Float(lift.y), Float(lift.z)))
        legacy.gamma = ColorWheelControl(colorOffset: SIMD3(Float(gamma.x), Float(gamma.y), Float(gamma.z)))
        legacy.gain = ColorWheelControl(colorOffset: SIMD3(Float(gain.x), Float(gain.y), Float(gain.z)))
        let converted = ColorWheelsLegacyConvert.convertLegacyColorWheel(legacy)
        let parity = renderParityStops(
            legacy: (lift: lift, gamma: gamma, gain: gain), converted: converted)
        print("M9-4 convert anchor: common-domain parity = \(String(format: "%.4f", parity)) stops")
        // The common-domain band: ≤0.035 stops (re-pinned; H-SP3).
        XCTAssertLessThanOrEqual(parity, 0.035, "common-domain fit band (H-SP3, re-pinned)")
    }

    /// The extreme-domain residual band (H-SP3 / X2): a legacy lift of
    /// ≈1.4 stops TOGETHER with a co-tuned gamma shift can only be
    /// approximated — the band sits at the range ends (the new Gamma
    /// cannot act at ±6 EV). Hard cap 0.15 (f64 fit noise margin).
    /// Re-pinned by the B-1 repair: measured 0.1317 stops on the
    /// reciprocal target (was 0.143 on the direct-exponent target — the
    /// 0.145 band holds).
    func testExtremeDomainFitParity() {
        // 1.4 stops ≈ 0.0799 ACEScc codes (1.4/17.52), co-tuned with a
        // mild gamma lift and a proportional gain (the "lift ≈1.4 stops
        // with co-tuned gamma" extreme family — push-bright on ch0,
        // moderate on the others).
        let liftLuma = Float(1.4 / Double(ColorWheelsModule.acesccB))
        let lift = SIMD3<Double>(0.022, 0.004, -0.011)
            + SIMD3<Double>(repeating: Double(liftLuma))
        let gamma = SIMD3<Double>(0.9, 0.95, 1.0)
        let gain = SIMD3<Double>(1.08, 1.03, 1.0)
        var legacy = ColorWheelsModule.Params()
        legacy.lift = ColorWheelControl(colorOffset: SIMD3(Float(lift.x), Float(lift.y), Float(lift.z)))
        legacy.gamma = ColorWheelControl(colorOffset: SIMD3(Float(gamma.x), Float(gamma.y), Float(gamma.z)))
        legacy.gain = ColorWheelControl(colorOffset: SIMD3(Float(gain.x), Float(gain.y), Float(gain.z)))
        let converted = ColorWheelsLegacyConvert.convertLegacyColorWheel(legacy)
        let parity = renderParityStops(
            legacy: (lift: lift, gamma: gamma, gain: gain), converted: converted)
        XCTAssertLessThanOrEqual(
            parity, 0.15, "extreme-domain hard cap (fit noise margin)")
        // The declared band (re-pinned 0.1317; the 0.10..0.15 stop regime)
        // holds for this representative set.
        XCTAssertLessThanOrEqual(parity, 0.145, "extreme-domain band (H-SP3, re-pinned)")
    }

    // MARK: - Semantic regression (acceptance-2ND B-1): migration keeps the look

    /// The B-1 semantic regression (the lane-2 probe formalized): a
    /// gamma-NON-NEUTRAL legacy document must keep BOTH the brightness
    /// direction AND the magnitude of its look when the document upgrades
    /// to the v3 process. The independent Float64 truth model
    /// (`legacyApply` — the frozen v1 reciprocal form) is compared against
    /// the PRODUCTION migrated render (convertLegacyColorWheel →
    /// resolveToneWheelKernelParams → applyToneWheels — the real
    /// pre-resolve path) over the ±6 EV fit grid.
    ///
    /// Determinism: on the pre-repair direct-exponent target this exact
    /// scenario measured 1.17–2.34 stops WITH the mid-grey direction
    /// inverted (γ_s=1.2: mid grey 0.479 → 0.347); the reciprocal target
    /// re-pins it to ≤0.03 stops with the direction preserved (measured
    /// 0.0253 / 0.0285 / 0.0196 — M9-4-DECISIONS §13 before/after table).
    func testGammaNonNeutralLegacyKeepsLookAndDirectionAtUpgrade() {
        let b = Double(ColorWheelsModule.acesccB)
        let mid = acesccOfEv(0)
        let scenarios: [(name: String, gamma: Double, gain: Double)] = [
            ("gamma-bright", 1.2, 1.0),
            ("gamma-dark", 0.9, 1.0),
            ("gamma+gain", 1.1, 0.95),
        ]
        for scenario in scenarios {
            let gammaS = scenario.gamma
            let gainS = scenario.gain
            var legacy = ColorWheelsModule.Params()
            legacy.gamma = ColorWheelControl(colorOffset: SIMD3(
                Float(gammaS), Float(gammaS), Float(gammaS)))
            legacy.gain = ColorWheelControl(colorOffset: SIMD3(
                Float(gainS), Float(gainS), Float(gainS)))
            let converted = ColorWheelsLegacyConvert.convertLegacyColorWheel(legacy)
            let resolved = ColorWheelsModule.resolveToneWheelKernelParams(of: converted)
            var worst = 0.0
            for i in 0..<25 {
                let ev = -6.0 + 12.0 * Double(i) / 24.0
                let input = acesccOfEv(ev)
                for ch in 0..<3 {
                    let truth = legacyApply(
                        input, lift: 0, gamma: gammaS, gain: gainS)
                    let migrated = Double(ColorWheelsModule.applyToneWheels(
                        Float(input), channel: ch, params: resolved))
                    worst = max(worst, abs(migrated - truth) * b)
                    // The direction sentinel at mid grey: the migrated
                    // render must sit on the SAME side of neutral as the
                    // frozen look (the B-1 inversion tripwire — the
                    // pre-repair target flips this for every scenario).
                    if ev == 0 {
                        XCTAssertEqual(
                            migrated > Double(mid), truth > Double(mid),
                            "\(scenario.name) ch\(ch): mid-grey brightness direction inverted")
                    }
                }
            }
            print("M9-4 semantic regression [\(scenario.name)]: migration delta = \(String(format: "%.4f", worst)) stops, direction preserved")
            XCTAssertLessThanOrEqual(
                worst, 0.035,
                "\(scenario.name): migration delta exceeds the common-domain band")
        }
    }

    // MARK: - No truncation + the mean/zero-mean split

    /// The wheelControlFromStops split: the fit-K mean rides luminance,
    /// the zero-mean part rides colorOffset UNCLAMPED (what renders is the
    /// fitted value), and only the disc inversion clamps onto the unit
    /// circle (UI state).
    func testFitKSplitKeepsUnclampedStopsAndClampsDisc() {
        // {2, −1, −1} stops (upstream's out-of-disc set): mean 0 → the
        // colorOffset stores the RAW stops, the disc clamps to radius 1.
        let b = Double(ColorWheelsModule.acesccB)
        var legacy = ColorWheelsModule.Params()
        legacy.lift = ColorWheelControl(
            colorOffset: SIMD3(
                Float(2.0 / b + 1.0 / b), 0, 0),
            luminanceOffset: Float(-1.0 / b))
        let converted = ColorWheelsLegacyConvert.convertLegacyColorWheel(legacy)
        let offsetStops = ColorWheelsModule.controlChannelStops(converted.offset!)
        XCTAssertEqual(Double(offsetStops.x), 2.0, accuracy: 1.0e-4)
        XCTAssertEqual(Double(offsetStops.y), -1.0, accuracy: 1.0e-4)
        XCTAssertEqual(Double(offsetStops.z), -1.0, accuracy: 1.0e-4)
        let disc = converted.offset!.disc
        XCTAssertEqual(
            Double(sqrt(disc.x * disc.x + disc.y * disc.y)), 1.0, accuracy: 1.0e-5)
        // A nonzero-mean set splits: mean → luminance, zero-mean → color.
        let stops = SIMD3<Double>(0.4, -0.1, 0.3)
        let control = ColorWheelsLegacyConvert.wheelControlFromStops(stops)
        XCTAssertEqual(control.luminanceOffset, Float(0.2), accuracy: 1.0e-6)
        let zeroMean = ColorWheelsModule.controlChannelStops(control)
            - SIMD3<Float>(repeating: control.luminanceOffset)
        XCTAssertEqual(Double(zeroMean.x), 0.2, accuracy: 1.0e-6)
        XCTAssertEqual(Double(zeroMean.y), -0.3, accuracy: 1.0e-6)
        XCTAssertEqual(Double(zeroMean.z), 0.1, accuracy: 1.0e-6)
    }

    // MARK: - Neutral passthrough + v3 shape round trip

    /// The neutral legacy Params converts to the all-zero quad WITH the
    /// offset present (the v2 discriminator), and stays identity-v3.
    func testNeutralLegacyConvertsToNeutralQuad() {
        let converted = ColorWheelsLegacyConvert.convertLegacyColorWheel(
            ColorWheelsModule.Params())
        XCTAssertNotNil(converted.offset)
        XCTAssertTrue(ColorWheelsModule.isIdentityV3(converted))
        for wheel in [converted.lift, converted.gamma, converted.gain, converted.offset!] {
            XCTAssertTrue(wheel.colorOffset == .zero && wheel.luminanceOffset == 0)
        }
    }

    /// The v3 JSON shape (offset present) survives the canonical
    /// encode/decode round trip unchanged.
    func testV3ShapeRoundTrip() throws {
        let converted = ColorWheelsLegacyConvert.convertLegacyColorWheel(
            ColorWheelsModule.Params())
        let data = ParamsCoding.encode(converted)
        let decoded = try JSONDecoder().decode(
            ColorWheelsModule.Params.self, from: data)
        XCTAssertEqual(decoded, converted)
        XCTAssertNotNil(decoded.offset)
    }
}
