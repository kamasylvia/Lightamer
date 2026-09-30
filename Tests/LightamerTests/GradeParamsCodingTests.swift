import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// GradeParamsCodingTests (Plan M2-5-1 T3-T7) — the new grade ops' Params
// coding face: JSON keys照抄 the Alcedo model spellings, clamped ranges,
// and the sidecar round-trip (the ParamsCoding bytes are the sidecar
// paramsData atom, D-H4).
// ─────────────────────────────────────────────────────────────────────────

final class GradeParamsCodingTests: XCTestCase {

    /// The canonical encode → decode round trip (sorted-keys compact JSON —
    /// the same bytes the sidecar carries).
    private func roundTrip<T: Codable & Hashable>(_ params: T) throws -> T {
        let data = ParamsCoding.encode(params)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func jsonString<T: Codable>(_ params: T) throws -> String {
        String(data: ParamsCoding.encode(params), encoding: .utf8)!
    }

    // MARK: - T3: CAT02 white balance

    func testCat02JSONKeysAndDefaults() throws {
        let json = try jsonString(Cat02WBModule.Params())
        XCTAssertTrue(json.contains("\"temperature\""), "Alcedo key spelling")
        XCTAssertTrue(json.contains("\"tint\""), "Alcedo key spelling")
        let decoded = try roundTrip(Cat02WBModule.Params())
        XCTAssertEqual(decoded, Cat02WBModule.Params())
        XCTAssertEqual(decoded.temperature, 5999.9934)
        XCTAssertEqual(decoded.tint, 9.7112783)
    }

    func testCat02ClampRanges() {
        // temperature 2000–15000, tint ±150 (Alcedo ApplyUpdate clamps).
        let hot = Cat02WBModule.clamped(Cat02WBModule.Params(temperature: 99_999, tint: 999))
        XCTAssertEqual(hot.temperature, 15000)
        XCTAssertEqual(hot.tint, 150)
        let cold = Cat02WBModule.clamped(Cat02WBModule.Params(temperature: 10, tint: -999))
        XCTAssertEqual(cold.temperature, 2000)
        XCTAssertEqual(cold.tint, -150)
    }

    func testCat02CodingRoundTripAtCorners() throws {
        let corner = Cat02WBModule.Params(temperature: 2000, tint: -150)
        XCTAssertEqual(try roundTrip(corner), corner)
        let far = Cat02WBModule.Params(temperature: 15000, tint: 150)
        XCTAssertEqual(try roundTrip(far), far)
    }

    // MARK: - T4: contrast / white / black

    func testContrastJSONKeyAndClamp() throws {
        let json = try jsonString(ContrastModule.Params())
        XCTAssertTrue(json.contains("\"contrast\""), "Alcedo key spelling")
        XCTAssertEqual(try roundTrip(ContrastModule.Params()), ContrastModule.Params())
        let high = ContrastModule.clamped(ContrastModule.Params(contrast: 999))
        XCTAssertEqual(high.contrast, 100)
        let low = ContrastModule.clamped(ContrastModule.Params(contrast: -999))
        XCTAssertEqual(low.contrast, -100)
    }

    func testWhiteBlackJSONKeysAndClamps() throws {
        XCTAssertTrue(try jsonString(WhiteModule.Params()).contains("\"white\""))
        XCTAssertTrue(try jsonString(BlackModule.Params()).contains("\"black\""))
        XCTAssertEqual(try roundTrip(WhiteModule.Params()), WhiteModule.Params())
        XCTAssertEqual(try roundTrip(BlackModule.Params()), BlackModule.Params())
        XCTAssertEqual(
            WhiteModule.clamped(WhiteModule.Params(white: 999)).white, 100)
        XCTAssertEqual(
            WhiteModule.clamped(WhiteModule.Params(white: -999)).white, -100)
        XCTAssertEqual(
            BlackModule.clamped(BlackModule.Params(black: 999)).black, 100)
        XCTAssertEqual(
            BlackModule.clamped(BlackModule.Params(black: -999)).black, -100)
    }

    // MARK: - T5: saturation / tint

    func testSaturationJSONKeyAndClamp() throws {
        XCTAssertTrue(try jsonString(SaturationModule.Params()).contains("\"saturation\""))
        XCTAssertEqual(try roundTrip(SaturationModule.Params()), SaturationModule.Params())
        XCTAssertEqual(
            SaturationModule.clamped(SaturationModule.Params(saturation: 99)).saturation, 4)
        XCTAssertEqual(
            SaturationModule.clamped(SaturationModule.Params(saturation: -1)).saturation, 0)
    }

    func testTintJSONKeyAndClamp() throws {
        XCTAssertTrue(try jsonString(TintModule.Params()).contains("\"tint\""))
        XCTAssertEqual(try roundTrip(TintModule.Params()), TintModule.Params())
        XCTAssertEqual(TintModule.clamped(TintModule.Params(tint: 999)).tint, 100)
        XCTAssertEqual(TintModule.clamped(TintModule.Params(tint: -999)).tint, -100)
    }

    // MARK: - T6: colorWheels

    func testColorWheelsJSONKeysAndRoundTrip() throws {
        let json = try jsonString(ColorWheelsModule.Params())
        // The Alcedo spellings: lift/gamma/gain × disc.x/y, strength,
        // color_offset.x/y/z, luminance_offset.
        for key in ["\"lift\"", "\"gamma\"", "\"gain\"", "\"disc\"", "\"strength\"",
                    "\"color_offset\"", "\"luminance_offset\""] {
            XCTAssertTrue(json.contains(key), "missing key \(key)")
        }
        let params = ColorWheelsModule.Params(
            lift: ColorWheelControl(
                disc: SIMD2(0.25, -0.5), strength: 1.5,
                colorOffset: SIMD3(0.1, 0.2, 0.3), luminanceOffset: 0.05),
            gamma: ColorWheelControl(colorOffset: SIMD3(1.1, 0.95, 1.2)),
            gain: ColorWheelControl(colorOffset: SIMD3(0.9, 1.05, 1.1)))
        XCTAssertEqual(try roundTrip(params), params)
    }

    /// The IsIdentity judgment mirrors the Alcedo .cpp VERBATIM: lift all
    /// zero (disc/colorOffset/luminanceOffset) AND gamma/gain colorOffset
    /// == (1,1,1); disc/strength and gamma/gain luminanceOffset do NOT
    /// participate (each line cites the .cpp term it mirrors).
    func testColorWheelsIsIdentityJudgment() {
        // The default IS the identity.
        XCTAssertTrue(ColorWheelsModule.isIdentity(ColorWheelsModule.Params()))
        // lift: ANY non-zero lift field breaks it (color, disc, luma).
        XCTAssertFalse(ColorWheelsModule.isIdentity(ColorWheelsModule.Params(
            lift: ColorWheelControl(colorOffset: SIMD3(0.1, 0, 0)))))
        XCTAssertFalse(ColorWheelsModule.isIdentity(ColorWheelsModule.Params(
            lift: ColorWheelControl(disc: SIMD2(0.1, 0)))))
        XCTAssertFalse(ColorWheelsModule.isIdentity(ColorWheelsModule.Params(
            lift: ColorWheelControl(luminanceOffset: 0.1))))
        // gamma/gain: only colorOffset participates — a non-default disc/
        // strength/luminanceOffset keeps the identity TRUE (the .cpp skips
        // them for gamma/gain).
        XCTAssertTrue(ColorWheelsModule.isIdentity(ColorWheelsModule.Params(
            gamma: ColorWheelControl(
                disc: SIMD2(0.4, 0.4), strength: 2.0, colorOffset: SIMD3(1, 1, 1)))),
            "gamma disc/strength do not participate (the .cpp checks colorOffset only)")
        XCTAssertTrue(ColorWheelsModule.isIdentity(ColorWheelsModule.Params(
            gain: ColorWheelControl(colorOffset: SIMD3(1, 1, 1), luminanceOffset: 0.2))),
            "gain luminanceOffset does not participate")
        XCTAssertFalse(ColorWheelsModule.isIdentity(ColorWheelsModule.Params(
            gamma: ColorWheelControl(colorOffset: SIMD3(1.0, 1.0, 1.1)))))
        XCTAssertFalse(ColorWheelsModule.isIdentity(ColorWheelsModule.Params(
            gain: ColorWheelControl(colorOffset: SIMD3(0.9, 1.0, 1.0)))))
    }
}
