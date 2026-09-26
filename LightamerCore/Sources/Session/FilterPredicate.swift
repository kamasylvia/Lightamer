import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FilterPredicate (Plan 12-2 T1; META-05/META-06; D-12-CONTEXT-4/7) — the ONE
// predicate model for BOTH consumers: the grid filter bar (a transient group)
// and Smart Albums (a persisted group — same type, same bytes). Phase 14's
// MCP filter tools consume the same model + the same translation layer
// (GUI/MCP 同源前置, D-12-CONTEXT-7).
//
// Schema (12-RESEARCH §4.1 verbatim): `{ schemaVersion = 1, match, rules }`.
// NO nested groups in v1 — a flat AND (`.all`) / OR (`.any`) over rules.
//
// Backing columns: the SessionIndexSchema v2 34-column face — `FilterField`
// is its filter-facing projection (the dt `collection.h:74-136` property
// enumeration aligned).
//
// keywords semantics (D-12-CONTEXT-3 + 12-RESEARCH §3.2 F3): a keywords rule
// carries the INTENT (tag / path sub-match); the FOUR-CLAUSE ancestor
// expansion lives in FilterSQL — the model never encodes SQL.
//
// Forward compatibility: an unknown field/op/value-kind string throws the
// TYPED error at DECODE time — a smart-album file written by a future
// binary degrades honestly (the store skips it, never guesses, never
// crashes).
//
// sortedKeys byte stability: smart-album files and filter-state round-trips
// pin a golden (FilterPredicateTests) — the one-way format lock discipline
// (L013 family; no UInt64 hashes in this schema, plain JSON numbers are
// exact for the Int/Double value domain).
// ─────────────────────────────────────────────────────────────────────────────

/// The typed failure face of the predicate model (decode degradation +
/// validation rejections — never a silent guess).
public enum FilterPredicateError: Error, Equatable, Sendable {
    /// Decode hit a `field` spelling this binary does not know (future
    /// schema — the smart-album store skips the file).
    case unknownField(String)
    /// Decode hit an unknown `op` spelling.
    case unknownOp(String)
    /// Decode hit an unknown `value.kind` discriminator.
    case unknownValueKind(String)
    /// The field × operator combination is not legal (e.g. `rating
    /// contains`).
    case illegalFieldOperator(field: FilterField, op: FilterOp)
    /// The value's kind does not fit the field/op (e.g. a text value on
    /// `iso gte`).
    case illegalValueKind(field: FilterField, op: FilterOp, valueKind: String)
    /// A `between` interval with lower > upper.
    case invalidInterval(field: FilterField)
}

/// The filter-facing projection of the v2 index columns (the META-05 key
/// face; dt collection.h property enumeration aligned).
public enum FilterField: String, Sendable, CaseIterable {
    case rating
    case colorLabel
    case keywords
    case flag
    case note
    case cameraMake
    case cameraModel
    case lensModel
    case iso
    case focalLength
    case aperture
    case exposure
    case captureDate
    case hasEdits
    case filename
    case dir
}

/// The rule operator set (RESEARCH §4.1). `in` = membership over a list
/// value; `empty`/`notEmpty` = the NULL-or-empty-string class (the v2
/// '' sentinel semantics).
public enum FilterOp: String, Sendable, CaseIterable {
    case eq
    case neq
    case gt
    case gte
    case lt
    case lte
    case between
    case `in`
    case contains
    case startsWith
    case empty
    case notEmpty
}

/// The tagged-union rule value (RESEARCH §4.1: String | Int | Double |
/// [String] | closed interval). EXECUTION DECISION (recorded in
/// 12-2-DECISIONS): `intList`/`doubleList` join the union so the `in`
/// operator can carry numeric memberships — a pure additive extension of
/// the plan's union; `captureDate` values are epoch Doubles (the UI date
/// pickers fold to this at rule-build time).
public enum FilterValue: Equatable, Sendable {
    case text(String)
    case int(Int)
    case double(Double)
    case textList([String])
    case intRange(lower: Int, upper: Int)
    case doubleRange(lower: Double, upper: Double)
    case intList([Int])
    case doubleList([Double])

    /// The stable `kind` discriminator (the persisted spelling).
    var kind: String {
        switch self {
        case .text: "text"
        case .int: "int"
        case .double: "double"
        case .textList: "textList"
        case .intRange: "intRange"
        case .doubleRange: "doubleRange"
        case .intList: "intList"
        case .doubleList: "doubleList"
        }
    }

    /// Human-facing kind name for the typed value-kind errors.
    var kindName: String { kind }
}

// MARK: - Codable (typed-degradation decode + stable spelling)

extension FilterField: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let field = FilterField(rawValue: raw) else {
            throw FilterPredicateError.unknownField(raw)
        }
        self = field
    }
}

extension FilterOp: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let op = FilterOp(rawValue: raw) else {
            throw FilterPredicateError.unknownOp(raw)
        }
        self = op
    }
}

extension FilterValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case items
        case lower
        case upper
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .value))
        case "int":
            self = .int(try container.decode(Int.self, forKey: .value))
        case "double":
            self = .double(try container.decode(Double.self, forKey: .value))
        case "textList":
            self = .textList(try container.decode([String].self, forKey: .items))
        case "intRange":
            self = .intRange(
                lower: try container.decode(Int.self, forKey: .lower),
                upper: try container.decode(Int.self, forKey: .upper))
        case "doubleRange":
            self = .doubleRange(
                lower: try container.decode(Double.self, forKey: .lower),
                upper: try container.decode(Double.self, forKey: .upper))
        case "intList":
            self = .intList(try container.decode([Int].self, forKey: .items))
        case "doubleList":
            self = .doubleList(try container.decode([Double].self, forKey: .items))
        case let raw:
            throw FilterPredicateError.unknownValueKind(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .text(let value):
            try container.encode(value, forKey: .value)
        case .int(let value):
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(value, forKey: .value)
        case .textList(let items):
            try container.encode(items, forKey: .items)
        case .intRange(let lower, let upper):
            try container.encode(lower, forKey: .lower)
            try container.encode(upper, forKey: .upper)
        case .doubleRange(let lower, let upper):
            try container.encode(lower, forKey: .lower)
            try container.encode(upper, forKey: .upper)
        case .intList(let items):
            try container.encode(items, forKey: .items)
        case .doubleList(let items):
            try container.encode(items, forKey: .items)
        }
    }
}

// MARK: - The group (RESEARCH §4.1 schema verbatim)

public struct FilterPredicateGroup: Codable, Equatable, Sendable {
    /// AND (`.all`) / OR (`.any`) over the rules — v1 has NO nested groups.
    public enum Match: String, Codable, Sendable {
        case all
        case any
    }

    public struct Rule: Codable, Equatable, Sendable {
        public var field: FilterField
        public var op: FilterOp
        public var value: FilterValue

        public init(field: FilterField, op: FilterOp, value: FilterValue) {
            self.field = field
            self.op = op
            self.value = value
        }
    }

    public static let schemaVersionCurrent = 1

    public var schemaVersion: Int = FilterPredicateGroup.schemaVersionCurrent
    public var match: Match = .all
    public var rules: [Rule]

    public init(match: Match = .all, rules: [Rule]) {
        schemaVersion = FilterPredicateGroup.schemaVersionCurrent
        self.match = match
        self.rules = rules
    }

    // MARK: Validation (field × op × value legality — typed rejections)

    /// Validate the WHOLE group (every rule). `FilterSQL.translate` runs
    /// this defensively; UI / SmartAlbumStore call it at build/persist
    /// time so an illegal group never reaches the disk or the query face.
    public func validating() throws {
        for rule in rules { try rule.validating() }
    }

    /// True when this group carries no rules (the always-true face).
    public var isEmpty: Bool { rules.isEmpty }

    /// Build the Quick Filter group (filename OR keywords-ancestor hit —
    /// RESEARCH §4.3: a single contains-rule group, pure translation-layer
    /// consumption, no new SQL face).
    public static func quickFilter(text: String) -> FilterPredicateGroup {
        FilterPredicateGroup(
            match: .any,
            rules: [
                Rule(field: .filename, op: .contains, value: .text(text)),
                Rule(field: .keywords, op: .contains, value: .text(text)),
            ])
    }
}

extension FilterPredicateGroup.Rule {

    /// The field × operator legality matrix (12-2 execution decision,
    /// recorded in DECISIONS — the plan pins "数值字段禁 contains、文本字段禁
    /// gte 等" and this table IS the spelling; FilterPredicateTests pins it
    /// with an independent literal expectation table).
    static func legalOps(for field: FilterField) -> [FilterOp] {
        switch field {
        case .rating, .iso:
            // Full numeric face.
            [.eq, .neq, .gt, .gte, .lt, .lte, .between, .in]
        case .colorLabel:
            // Categorical: membership / equality only.
            [.eq, .neq, .in]
        case .flag:
            // 0/1/2 categorical.
            [.eq, .neq, .in]
        case .hasEdits:
            // 0/1 boolean — equality is the only meaningful face.
            [.eq]
        case .focalLength, .aperture, .exposure, .captureDate:
            // Continuous numerics: order + interval (no list membership —
            // a focal-length IN list is not a filtering workflow).
            [.eq, .neq, .gt, .gte, .lt, .lte, .between]
        case .keywords:
            // Tag semantics: exact path / ancestor expansion / any-of /
            // the tagged-vs-cleared classes. `neq` is deliberately absent
            // (NOT-ancestor is not a v1 filtering workflow).
            [.eq, .contains, .in, .empty, .notEmpty]
        case .note, .filename, .dir, .cameraMake, .cameraModel, .lensModel:
            // Text face.
            [.eq, .neq, .contains, .startsWith, .in, .empty, .notEmpty]
        }
    }

    /// The value kinds each field accepts (kind-spelling level; `between`
    /// additionally demands a range kind, `in` demands a list kind).
    static func legalValueKinds(for field: FilterField) -> Set<String> {
        switch field {
        case .rating, .colorLabel, .flag, .iso, .hasEdits:
            ["int", "intRange", "intList"]
        case .focalLength, .aperture, .exposure, .captureDate:
            ["double", "doubleRange"]
        case .keywords, .note, .filename, .dir, .cameraMake, .cameraModel, .lensModel:
            ["text", "textList"]
        }
    }

    public func validating() throws {
        guard FilterPredicateGroup.Rule.legalOps(for: field).contains(op) else {
            throw FilterPredicateError.illegalFieldOperator(field: field, op: op)
        }
        let kinds = FilterPredicateGroup.Rule.legalValueKinds(for: field)
        guard kinds.contains(value.kind) else {
            throw FilterPredicateError.illegalValueKind(
                field: field, op: op, valueKind: value.kind)
        }
        // Operator-shaped value kinds.
        switch op {
        case .between:
            switch value {
            case .intRange(let lower, let upper):
                if lower > upper { throw FilterPredicateError.invalidInterval(field: field) }
            case .doubleRange(let lower, let upper):
                if lower > upper { throw FilterPredicateError.invalidInterval(field: field) }
            default:
                throw FilterPredicateError.illegalValueKind(
                    field: field, op: op, valueKind: value.kind)
            }
        case .in:
            switch value {
            case .textList, .intList, .doubleList:
                break
            default:
                throw FilterPredicateError.illegalValueKind(
                    field: field, op: op, valueKind: value.kind)
            }
        default:
            // A range/list value on a scalar operator is nonsense.
            switch value {
            case .intRange, .doubleRange:
                throw FilterPredicateError.illegalValueKind(
                    field: field, op: op, valueKind: value.kind)
            case .textList, .intList, .doubleList:
                if op != .in {
                    throw FilterPredicateError.illegalValueKind(
                        field: field, op: op, valueKind: value.kind)
                }
            case .text, .int, .double:
                break
            }
        }
    }
}
