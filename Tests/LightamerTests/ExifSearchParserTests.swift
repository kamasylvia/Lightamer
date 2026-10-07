import Foundation
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ExifSearchParserTests (Plan M2-2-3 T1) — the KD-1 recognition MATRIX, the
// AND-composition semantics, and the typed degradation face:
//
//   • recognition matrix: iso800 / iso 800 / ISO-800 → eq; iso>1600 → gt;
//     iso:800-1600 → between; f/2.8 / f2.8 / f 2.8 → the ±0.05 tolerance
//     RANGE; 35mm / 35 mm → focal eq; five date spellings → exact ranges
//     (year / month / day boundaries inclusive at whole seconds)
//   • AND composition: `sony iso800 f/2.8 2024-06` → fts 1 + structured 2
//     + dateRange 1 — all three segments coexist
//   • degradation: `isoabc` → typed error; empty string → the empty
//     (always-true) plan; trailing `*` passes through for FTS prefixes
// ─────────────────────────────────────────────────────────────────────────────

final class ExifSearchParserTests: XCTestCase {

    // MARK: - Helpers

    private func utcDate(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) -> Date {
        var components = DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .iso8601).date(from: components)!
    }

    private func assertISO(
        _ input: String, _ constraint: StructuredTerm.Constraint,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let plan = try ExifSearchParser.parse(input)
        XCTAssertEqual(
            plan.structured,
            [StructuredTerm(field: .iso, constraint: constraint)],
            "input: \(input)", file: file, line: line)
        XCTAssertTrue(plan.ftsTerms.isEmpty, file: file, line: line)
        XCTAssertNil(plan.dateRange, file: file, line: line)
    }

    // MARK: - ISO family (recognition matrix)

    func testISOSpellingVariantsAllMeanEquals() throws {
        try assertISO("iso800", .equals(800))
        try assertISO("iso 800", .equals(800))
        try assertISO("ISO-800", .equals(800))
        try assertISO("Iso 6400", .equals(6400))
    }

    func testISORangeGrammar() throws {
        try assertISO("iso>1600", .greaterThan(1600))
        try assertISO("iso>=1600", .greaterThanOrEqual(1600))
        try assertISO("iso<400", .lessThan(400))
        try assertISO("iso<=400", .lessThanOrEqual(400))
        try assertISO("iso:800-1600", .between(lower: 800, upper: 1600))
    }

    // MARK: - Aperture family (the KD tolerance range, never REAL equality)

    func testApertureSpellingVariantsAllMeanToleranceRange() throws {
        let expected = StructuredTerm(
            field: .aperture, constraint: .between(lower: 2.75, upper: 2.85))
        for input in ["f/2.8", "f2.8", "f 2.8", "F/2.8"] {
            let plan = try ExifSearchParser.parse(input)
            XCTAssertEqual(
                plan.structured, [expected], "input: \(input)")
        }
    }

    func testApertureF14Band() throws {
        let plan = try ExifSearchParser.parse("f1.4")
        XCTAssertEqual(
            plan.structured,
            [StructuredTerm(
                field: .aperture, constraint: .between(lower: 1.35, upper: 1.45))])
    }

    // MARK: - Focal family

    func testFocalSpellingVariantsAllMeanEquals() throws {
        let expected = StructuredTerm(
            field: .focalLength, constraint: .equals(35))
        for input in ["35mm", "35 mm"] {
            let plan = try ExifSearchParser.parse(input)
            XCTAssertEqual(
                plan.structured, [expected], "input: \(input)")
        }
    }

    // MARK: - Date family (five spellings, boundary-exact)

    func testYearSpellingCoversTheWholeYear() throws {
        let plan = try ExifSearchParser.parse("2024")
        XCTAssertEqual(
            plan.dateRange,
            utcDate(2024, 1, 1)...utcDate(2024, 12, 31, 23, 59, 59),
            "the year range closes at the last whole second — EXIF dates "
                + "carry no sub-second precision")
    }

    func testMonthSpellingCoversTheWholeMonth() throws {
        let plan = try ExifSearchParser.parse("2024-06")
        XCTAssertEqual(
            plan.dateRange,
            utcDate(2024, 6, 1)...utcDate(2024, 6, 30, 23, 59, 59),
            "June has 30 days — the month boundary is calendar-derived")
    }

    func testDaySpellingsAllAgree() throws {
        let expected = utcDate(2024, 6, 1)...utcDate(2024, 6, 1, 23, 59, 59)
        for input in ["2024-06-01", "2024/06/01", "20240601"] {
            let plan = try ExifSearchParser.parse(input)
            XCTAssertEqual(
                plan.dateRange, expected,
                "the three day spellings must agree — input: \(input)")
        }
    }

    func testSixDigitSpellingIsYearMonth() throws {
        let plan = try ExifSearchParser.parse("202406")
        XCTAssertEqual(
            plan.dateRange, utcDate(2024, 6, 1)...utcDate(2024, 6, 30, 23, 59, 59))
    }

    func testDateBoundaryInclusivity() throws {
        // A capture at the range's exact lower bound is INSIDE.
        let plan = try ExifSearchParser.parse("2024-06")
        let range = try XCTUnwrap(plan.dateRange)
        XCTAssertTrue(range.contains(utcDate(2024, 6, 1)))
        XCTAssertTrue(range.contains(utcDate(2024, 6, 30, 23, 59, 59)))
        XCTAssertFalse(range.contains(utcDate(2024, 7, 1)))
    }

    func testInvalidCalendarDatesAreTypedErrors() {
        XCTAssertThrowsError(try ExifSearchParser.parse("2024-13")) { error in
            XCTAssertEqual(
                error as? ExifSearchParserError,
                .unrecognizedToken("2024-13"))
        }
        XCTAssertThrowsError(try ExifSearchParser.parse("2024-02-30")) { error in
            XCTAssertEqual(
                error as? ExifSearchParserError,
                .unrecognizedToken("2024-02-30"))
        }
    }

    // MARK: - AND composition (KD-1's headline example)

    func testMixedQueryComposesAllThreeSegments() throws {
        let plan = try ExifSearchParser.parse("sony iso800 f/2.8 2024-06")
        XCTAssertEqual(plan.ftsTerms, ["sony"], "the plain word folds lowercase")
        XCTAssertEqual(
            plan.structured,
            [
                StructuredTerm(field: .iso, constraint: .equals(800)),
                StructuredTerm(
                    field: .aperture,
                    constraint: .between(lower: 2.75, upper: 2.85)),
            ],
            "structured 2 — iso eq + aperture tolerance band")
        XCTAssertEqual(
            plan.dateRange, utcDate(2024, 6, 1)...utcDate(2024, 6, 30, 23, 59, 59))
        XCTAssertFalse(plan.isEmpty)
    }

    func testTwoStructuredISOsCoexistAsANDTerms() throws {
        // `iso>400 iso<800` = the range spelled as two ANDed terms.
        let plan = try ExifSearchParser.parse("iso>400 iso<800")
        XCTAssertEqual(
            plan.structured,
            [
                StructuredTerm(field: .iso, constraint: .greaterThan(400)),
                StructuredTerm(field: .iso, constraint: .lessThan(800)),
            ])
    }

    func testOverlappingDatesIntersect() throws {
        let plan = try ExifSearchParser.parse("2024-06 20240615")
        XCTAssertEqual(
            plan.dateRange,
            utcDate(2024, 6, 15)...utcDate(2024, 6, 15, 23, 59, 59),
            "two date tokens AND-intersect to the tighter range")
    }

    // MARK: - Typed degradation

    func testUnrecognizedISOTokenIsATypedError() {
        XCTAssertThrowsError(try ExifSearchParser.parse("isoabc")) { error in
            XCTAssertEqual(
                error as? ExifSearchParserError, .unrecognizedToken("isoabc"))
        }
        XCTAssertThrowsError(try ExifSearchParser.parse("sony iso:abc"))
        XCTAssertThrowsError(try ExifSearchParser.parse("iso:800-abc"))
    }

    func testBrokenApertureTokenIsATypedError() {
        XCTAssertThrowsError(try ExifSearchParser.parse("f/2.8.5")) { error in
            XCTAssertEqual(
                error as? ExifSearchParserError, .unrecognizedToken("f/2.8.5"))
        }
    }

    func testDisjointDatePairIsATypedError() {
        XCTAssertThrowsError(
            try ExifSearchParser.parse("2024-06 2025-01")
        ) { error in
            XCTAssertEqual(
                error as? ExifSearchParserError, .disjointDateRanges)
        }
    }

    func testEmptyInputIsTheAlwaysTruePlan() throws {
        for input in ["", "   ", "\n\t"] {
            let plan = try ExifSearchParser.parse(input)
            XCTAssertTrue(plan.isEmpty)
            XCTAssertEqual(plan, ExifSearchPlan())
        }
    }

    // MARK: - FTS passthrough

    func testTrailingStarPassesThroughForPrefixMatching() throws {
        let plan = try ExifSearchParser.parse("son*")
        XCTAssertEqual(plan.ftsTerms, ["son*"])
        XCTAssertTrue(plan.structured.isEmpty)
    }

    func testPlainWordsFoldLowercaseIntoFTSTerms() throws {
        let plan = try ExifSearchParser.parse("Sony   A7 IV")
        XCTAssertEqual(plan.ftsTerms, ["sony", "a7", "iv"])
    }

    func testThreeDigitNumberIsNotADate() throws {
        // `800` (bare) stays a plain FTS term — only the 4/6/8-digit
        // spellings are date-shaped (KD-1's matrix).
        let plan = try ExifSearchParser.parse("800")
        XCTAssertEqual(plan.ftsTerms, ["800"])
        XCTAssertNil(plan.dateRange)
    }
}
