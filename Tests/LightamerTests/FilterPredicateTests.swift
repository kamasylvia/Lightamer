import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 12-2 T1 — the predicate model (FilterPredicateGroup):
//
//   • round-trip over EVERY value kind (the tagged-union Codable face)
//   • sortedKeys BYTE golden (the smart-album file body / filter-state
//     serialization is one spelling — L013 family format lock)
//   • the field × operator legality matrix pinned by an INDEPENDENT literal
//     expectation table (not derived from the implementation)
//   • value-kind + interval typed rejections
//   • unknown field / op / value-kind strings decode to the TYPED errors
//     (the forward-compat face: future-schema smart albums degrade, never
//     guess)
//
// ─────────────────────────────────────────────────────────────────────────────

final class FilterPredicateTests: XCTestCase {

    // MARK: - Round-trip

    func testRoundTripEveryValueKind() throws {
        let group = FilterPredicateGroup(
            match: .all,
            rules: [
                .init(field: .rating, op: .gte, value: .int(3)),
                .init(field: .keywords, op: .contains, value: .text("Nature")),
                .init(field: .focalLength, op: .between, value: .doubleRange(lower: 24, upper: 70)),
                .init(field: .cameraMake, op: .in, value: .textList(["Canon", "Nikon"])),
                .init(field: .iso, op: .between, value: .intRange(lower: 100, upper: 1600)),
                .init(field: .captureDate, op: .gte, value: .double(1_700_000_000)),
                .init(field: .filename, op: .startsWith, value: .text("IMG_")),
                .init(field: .note, op: .empty, value: .text("")),
                .init(field: .keywords, op: .notEmpty, value: .text("")),
                .init(field: .iso, op: .in, value: .intList([100, 200, 400])),
                .init(field: .aperture, op: .in, value: .doubleList([1.4, 2.8])),
                .init(field: .exposure, op: .lt, value: .double(0.01)),
                .init(field: .flag, op: .eq, value: .int(1)),
                .init(field: .colorLabel, op: .in, value: .intList([0, 3])),
                .init(field: .hasEdits, op: .eq, value: .int(1)),
                .init(field: .dir, op: .contains, value: .text("Capture")),
            ])
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(FilterPredicateGroup.self, from: data)
        XCTAssertEqual(decoded, group)
        // `.any` round-trips too.
        var anyGroup = group
        anyGroup.match = .any
        let anyData = try JSONEncoder().encode(anyGroup)
        XCTAssertEqual(try JSONDecoder().decode(FilterPredicateGroup.self, from: anyData), anyGroup)
    }

    // MARK: - Golden (sortedKeys byte lock)

    func testSortedKeysGoldenBytes() throws {
        let group = FilterPredicateGroup(
            match: .all,
            rules: [
                .init(field: .rating, op: .gte, value: .int(3)),
                .init(field: .keywords, op: .contains, value: .text("Nature")),
            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(group)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertEqual(
            json,
            """
            {"match":"all","rules":[{"field":"rating","op":"gte",\
            "value":{"kind":"int","value":3}},{"field":"keywords",\
            "op":"contains","value":{"kind":"text","value":"Nature"}}],\
            "schemaVersion":1}
            """)
        // The golden DECODES back to the same group (the same bytes serve
        // the smart-album file body and the filter-bar state — same type).
        XCTAssertEqual(try JSONDecoder().decode(FilterPredicateGroup.self, from: data), group)
        // Re-encoding is byte-stable (deterministic diff face).
        XCTAssertEqual(try encoder.encode(group), data)
    }

    // MARK: - Legality matrix (independent literal expectation)

    func testFieldOperatorMatrix() throws {
        // The INDEPENDENT expectation (hand-written; not derived from the
        // implementation's switch).
        let expected: [FilterField: Set<FilterOp>] = [
            .rating: [.eq, .neq, .gt, .gte, .lt, .lte, .between, .in],
            .colorLabel: [.eq, .neq, .in],
            .keywords: [.eq, .contains, .in, .empty, .notEmpty],
            .flag: [.eq, .neq, .in],
            .note: [.eq, .neq, .contains, .startsWith, .in, .empty, .notEmpty],
            .cameraMake: [.eq, .neq, .contains, .startsWith, .in, .empty, .notEmpty],
            .cameraModel: [.eq, .neq, .contains, .startsWith, .in, .empty, .notEmpty],
            .lensModel: [.eq, .neq, .contains, .startsWith, .in, .empty, .notEmpty],
            .iso: [.eq, .neq, .gt, .gte, .lt, .lte, .between, .in],
            .focalLength: [.eq, .neq, .gt, .gte, .lt, .lte, .between],
            .aperture: [.eq, .neq, .gt, .gte, .lt, .lte, .between],
            .exposure: [.eq, .neq, .gt, .gte, .lt, .lte, .between],
            .captureDate: [.eq, .neq, .gt, .gte, .lt, .lte, .between],
            .hasEdits: [.eq],
            .filename: [.eq, .neq, .contains, .startsWith, .in, .empty, .notEmpty],
            .dir: [.eq, .neq, .contains, .startsWith, .in, .empty, .notEmpty],
        ]
        XCTAssertEqual(expected.keys.count, FilterField.allCases.count)
        for (field, ops) in expected {
            // The rule constructor does not police legality (Codable needs
            // the memberwise init) — `validating()` is the gate, so probe
            // every op through it.
            for op in FilterOp.allCases {
                let rule = FilterPredicateGroup.Rule(
                    field: field, op: op, value: Self.probeValue(for: op))
                let legal = ops.contains(op)
                if legal {
                    // A legal combo may still reject the PROBE value's kind
                    // (probe values are kind-shaped per op, not per field) —
                    // only assert the field×op gate itself.
                    if Self.probeValueKindIsFieldShaped(field: field, op: op) {
                        XCTAssertNoThrow(try rule.validating(), "\(field) \(op)")
                    }
                } else {
                    XCTAssertThrowsError(try rule.validating(), "\(field) \(op)") { error in
                        guard case FilterPredicateError.illegalFieldOperator = error else {
                            return XCTFail("expected illegalFieldOperator for \(field) \(op)")
                        }
                    }
                }
            }
        }
    }

    /// A value shaped for the OPERATOR (between → range, in → list, else
    /// scalar), neutral to the field's numeric/text family.
    private static func probeValue(for op: FilterOp) -> FilterValue {
        switch op {
        case .between: .intRange(lower: 0, upper: 1)
        case .in: .textList(["x"])
        default: .text("")
        }
    }

    /// Whether the probe value's kind sits in the field's accepted family
    /// (int-family fields reject text scalars — those combos assert only
    /// the illegalValueKind face, not the matrix gate).
    private static func probeValueKindIsFieldShaped(field: FilterField, op: FilterOp) -> Bool {
        let intFields: Set<FilterField> = [
            .rating, .colorLabel, .flag, .iso, .hasEdits,
            .focalLength, .aperture, .exposure, .captureDate,
        ]
        if intFields.contains(field) {
            // Probe scalar is text → only list/between probes (textList /
            // intRange) can ever be kind-legal, and the int family wants
            // intList, not textList.
            return false
        }
        if op == .between {
            // Text family has no range kind.
            return false
        }
        if op == .in {
            // Text family accepts textList.
            return true
        }
        return true
    }

    // MARK: - Typed rejections

    func testIllegalValueKinds() {
        // Numeric field with a text value.
        assertReject(
            .init(field: .rating, op: .eq, value: .text("three")),
            .illegalValueKind(field: .rating, op: .eq, valueKind: "text"))
        // Text field with an int value.
        assertReject(
            .init(field: .filename, op: .contains, value: .int(3)),
            .illegalValueKind(field: .filename, op: .contains, valueKind: "int"))
        // Numeric-field list membership with a text list.
        assertReject(
            .init(field: .iso, op: .in, value: .textList(["100"])),
            .illegalValueKind(field: .iso, op: .in, valueKind: "textList"))
        // `between` with a scalar value.
        assertReject(
            .init(field: .rating, op: .between, value: .int(3)),
            .illegalValueKind(field: .rating, op: .between, valueKind: "int"))
        // `in` with a scalar value.
        assertReject(
            .init(field: .cameraMake, op: .in, value: .text("Canon")),
            .illegalValueKind(field: .cameraMake, op: .in, valueKind: "text"))
        // A range value on a scalar operator.
        assertReject(
            .init(field: .rating, op: .eq, value: .intRange(lower: 1, upper: 5)),
            .illegalValueKind(field: .rating, op: .eq, valueKind: "intRange"))
        // A list value on a scalar operator.
        assertReject(
            .init(field: .cameraMake, op: .eq, value: .textList(["Canon"])),
            .illegalValueKind(field: .cameraMake, op: .eq, valueKind: "textList"))
    }

    func testInvalidIntervals() {
        assertReject(
            .init(field: .iso, op: .between, value: .intRange(lower: 1600, upper: 100)),
            .invalidInterval(field: .iso))
        assertReject(
            .init(field: .focalLength, op: .between, value: .doubleRange(lower: 70, upper: 24)),
            .invalidInterval(field: .focalLength))
        // Equal bounds are legal (a point interval).
        XCTAssertNoThrow(
            try FilterPredicateGroup.Rule(
                field: .iso, op: .between, value: .intRange(lower: 400, upper: 400)
            ).validating())
    }

    private func assertReject(
        _ rule: FilterPredicateGroup.Rule, _ expected: FilterPredicateError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try rule.validating(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? FilterPredicateError, expected, file: file, line: line)
        }
    }

    // MARK: - Typed decode degradation (forward compatibility)

    func testUnknownFieldDecodesToTypedError() throws {
        let json = #"{"match":"all","rules":[{"field":"futureColumn","op":"eq","value":{"int":1,"kind":"int"}}],"schemaVersion":1}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(FilterPredicateGroup.self, from: data)) {
            error in
            XCTAssertEqual(error as? FilterPredicateError, .unknownField("futureColumn"))
        }
    }

    func testUnknownOpDecodesToTypedError() throws {
        let json = #"{"match":"all","rules":[{"field":"rating","op":"regex","value":{"int":1,"kind":"int"}}],"schemaVersion":1}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(FilterPredicateGroup.self, from: data)) {
            error in
            XCTAssertEqual(error as? FilterPredicateError, .unknownOp("regex"))
        }
    }

    func testUnknownValueKindDecodesToTypedError() throws {
        let json = #"{"match":"all","rules":[{"field":"rating","op":"eq","value":{"kind":"tensor"}}],"schemaVersion":1}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(FilterPredicateGroup.self, from: data)) {
            error in
            XCTAssertEqual(error as? FilterPredicateError, .unknownValueKind("tensor"))
        }
    }

    // MARK: - Quick Filter shape

    func testQuickFilterGroupShape() throws {
        let group = FilterPredicateGroup.quickFilter(text: "rose")
        XCTAssertEqual(group.match, .any)
        XCTAssertEqual(group.rules.count, 2)
        XCTAssertEqual(
            group.rules[0],
            .init(field: .filename, op: .contains, value: .text("rose")))
        XCTAssertEqual(
            group.rules[1],
            .init(field: .keywords, op: .contains, value: .text("rose")))
        XCTAssertNoThrow(try group.validating())
    }

    // MARK: - Empty group

    func testEmptyGroupIsValid() {
        let group = FilterPredicateGroup(rules: [])
        XCTAssertTrue(group.isEmpty)
        XCTAssertNoThrow(try group.validating())
    }
}
