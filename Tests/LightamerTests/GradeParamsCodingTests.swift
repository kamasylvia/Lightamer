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
}
