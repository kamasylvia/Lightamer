import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FilterSQL (Plan 12-2 T2; META-05; D-12-CONTEXT-7) — the ONE translation
// layer: FilterPredicateGroup → (SQL WHERE fragment, binds). The filter bar
// (transient), Smart Albums (persisted) and Phase 14's MCP filter tools all
// consume THIS function — no second SQL face may exist.
//
// SQL red lines (plan 纪律):
//   • BIND-ONLY: every user-carried value rides a `?` placeholder — ZERO
//     string-interpolated values (the injection face is closed; a `'`- or
//     `DROP TABLE`-shaped filter value is literal data).
//   • LIKE wildcards in VALUES are ESCAPED (`%`/`_`/`\` → literal, via
//     `ESCAPE '\'`) — bind alone does NOT neutralize LIKE metacharacters.
//     Execution decision recorded in 12-2-DECISIONS: every LIKE that binds
//     user text carries the ESCAPE clause.
//   • ORDER BY keys never eat binds (SQLite ignores a bound ORDER BY) —
//     `FilterSortKey` is a whitelist enum whose column spelling is a frozen
//     literal (the plan's sanctioned direct translation).
//   • The baseline predicate `orphan_sidecar = 0` is ALWAYS appended — a
//     filtered collection never lists the orphan classification rows.
//
// The keywords ancestor predicate = the FOUR-CLAUSE form (12-RESEARCH §3.2,
// F3 — the RESEARCH amendment of CONTEXT D-3's bare `LIKE '%T%'`, which
// mis-hits substring-sibling tags like `NatureHolics`; pinned by the
// NatureHolics control-group test in FilterSQLTests):
//
//   (keywords = ? OR keywords LIKE ? || '|%' ESCAPE '\'
//              OR keywords LIKE '%|' || ? || '|%' ESCAPE '\'
//              OR keywords LIKE '%|' || ? ESCAPE '\')
//
// = dt's 打子隐含父 re-stated over the `|`-joined materialized column; the
// same bind value appears 4× (per-placeholder expansion, bind indices
// aligned — T3's query face keeps the same array order).
// ─────────────────────────────────────────────────────────────────────────────

/// One bind slot (position = the `?` order in the WHERE fragment).
public enum FilterSQLBind: Equatable, Sendable {
    case text(String?)
    case int(Int64?)
    case double(Double?)
}

/// The translation product: a WHERE fragment WITHOUT the leading keyword
/// (`orphan_sidecar = 0` baseline included) + the aligned bind array.
public struct FilterSQLQuery: Equatable, Sendable {
    public let whereClause: String
    public let binds: [FilterSQLBind]

    public init(whereClause: String, binds: [FilterSQLBind]) {
        self.whereClause = whereClause
        self.binds = binds
    }
}

/// The sort key whitelist (RESEARCH §4.2: ORDER BY cannot bind — six
/// frozen keys × direction, persisted by the App layer in UserDefaults).
public enum FilterSortKey: String, Codable, Sendable, CaseIterable {
    case filename
    case rating
    case captureDate
    case iso
    case focalLength
    case scanEpoch

    /// The frozen column spelling (the v2 schema's literal names — the
    /// whitelist IS the injection guard for the ORDER BY position).
    public var column: String {
        switch self {
        case .filename: "filename"
        case .rating: "rating"
        case .captureDate: "capture_date"
        case .iso: "iso"
        case .focalLength: "focal_length"
        case .scanEpoch: "scan_epoch"
        }
    }

    /// The ORDER BY term for this key: NULLs sort LAST in both directions
    /// (execution decision, 12-2-DECISIONS — unrated/unshot rows never
    /// lead a reverse-sorted collection), then the column itself.
    public func orderByTerm(ascending: Bool) -> String {
        let direction = ascending ? "ASC" : "DESC"
        return "(\(column) IS NULL), \(column) \(direction)"
    }
}

/// The sort value type (key × direction).
public struct FilterSort: Codable, Equatable, Sendable {
    public var key: FilterSortKey
    public var ascending: Bool

    public init(key: FilterSortKey, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    /// The full ORDER BY list (with the `path ASC` tiebreaker the query
    /// face appends — deterministic row sets over equal keys).
    public var orderBySQL: String {
        "\(key.orderByTerm(ascending: ascending)), path ASC"
    }
}

public enum FilterSQL {

    /// The ONE translation function. Throws the predicate model's typed
    /// errors for any illegal field × op × value combination (it validates
    /// defensively — the UI/store gate first, but never trust).
    public static func translate(group: FilterPredicateGroup) throws -> FilterSQLQuery {
        try translate(group: group, appendsBaseline: true)
    }

    /// The baseline-free form for the MULTI-GROUP combinator (which
    /// attaches `orphan_sidecar = 0` exactly ONCE for the whole join —
    /// per-group baselines would AND-duplicate).
    static func translate(
        group: FilterPredicateGroup, appendsBaseline: Bool
    ) throws -> FilterSQLQuery {
        try group.validating()
        var binds: [FilterSQLBind] = []
        let parts = try group.rules.map { try condition(for: $0, binds: &binds) }
        // Every condition is already parenthesized (the four-clause, the
        // IN list, the simple shapes). A MULTI-rule group gets ONE extra
        // wrapper so an OR group cannot bind the baseline's AND at a lower
        // precedence (`a OR b AND baseline` would be wrong); a single rule
        // stays single-parenthesized; the empty group is the `1=1`
        // always-true literal.
        let joined: String
        switch parts.count {
        case 0:
            joined = "(1=1)"
        case 1:
            joined = parts[0]
        default:
            joined = "(" + parts.joined(
                separator: group.match == .all ? " AND " : " OR ") + ")"
        }
        // The baseline predicate rides EVERY single-group product (plan
        // 纪律 — orphan classification rows never surface in a filtered
        // collection); the combinator form defers it.
        return FilterSQLQuery(
            whereClause: appendsBaseline
                ? "\(joined) AND (orphan_sidecar = 0)" : joined,
            binds: binds)
    }

    // MARK: - LIKE escaping (bind-only complement)

    /// Escape the three LIKE metacharacters so the BOUND value matches
    /// literally (`ESCAPE '\'` clauses in the templates above consume the
    /// backslashes). `'` needs no escaping — a bound quote is literal data
    /// by construction.
    public static func escapeLike(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - Rule → condition

    private static func condition(
        for rule: FilterPredicateGroup.Rule, binds: inout [FilterSQLBind]
    ) throws -> String {
        let column = try Self.column(for: rule.field)
        switch rule.field {
        case .keywords:
            return try keywordsCondition(for: rule, column: column, binds: &binds)
        case .rating, .colorLabel, .flag, .iso, .hasEdits,
            .focalLength, .aperture, .exposure, .captureDate:
            return try numericCondition(for: rule, column: column, binds: &binds)
        case .note, .filename, .dir, .cameraMake, .cameraModel, .lensModel:
            return try textCondition(for: rule, column: column, binds: &binds)
        }
    }

    /// The keywords face: `contains` = the FOUR-CLAUSE ancestor predicate
    /// (F3); `in` = any-of four-clauses; `eq` = exact whole-column path.
    private static func keywordsCondition(
        for rule: FilterPredicateGroup.Rule, column: String,
        binds: inout [FilterSQLBind]
    ) throws -> String {
        switch rule.op {
        case .contains:
            // The four-clause template × one tag.
            guard case .text(let tag) = rule.value else {
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            return fourClause(column: column, bind: .text(Self.escapeLike(tag)), binds: &binds)
        case .in:
            guard case .textList(let tags) = rule.value else {
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            let parts = tags.map { tag in
                fourClause(
                    column: column, bind: .text(Self.escapeLike(tag)), binds: &binds)
            }
            return "(" + parts.joined(separator: " OR ") + ")"
        case .eq:
            guard case .text(let tag) = rule.value else {
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            binds.append(.text(tag)) // exact equality: no LIKE metacharacters involved
            return "(\(column) = ?)"
        case .empty:
            return "(\(column) IS NULL OR \(column) = '')"
        case .notEmpty:
            return "(\(column) IS NOT NULL AND \(column) != '')"
        default:
            throw FilterPredicateError.illegalFieldOperator(field: rule.field, op: rule.op)
        }
    }

    /// The FOUR-CLAUSE ancestor predicate, spelled once (F3 正本). The SAME
    /// tag rides four placeholders (per-placeholder expansion; the binds
    /// array grows by exactly four in order).
    private static func fourClause(
        column: String, bind: FilterSQLBind, binds: inout [FilterSQLBind]
    ) -> String {
        binds.append(contentsOf: [bind, bind, bind, bind])
        return """
            (\(column) = ? OR \(column) LIKE ? || '|%' ESCAPE '\\' \
            OR \(column) LIKE '%|' || ? || '|%' ESCAPE '\\' \
            OR \(column) LIKE '%|' || ? ESCAPE '\\')
            """
    }

    /// The numeric face (int and double columns share the SQL shapes; the
    /// bind CASE carries the storage type).
    private static func numericCondition(
        for rule: FilterPredicateGroup.Rule, column: String,
        binds: inout [FilterSQLBind]
    ) throws -> String {
        func intBind(_ value: Int) -> FilterSQLBind { .int(Int64(value)) }
        switch rule.op {
        case .eq, .neq, .gt, .gte, .lt, .lte:
            let sqlOp: String
            switch rule.op {
            case .eq: sqlOp = "="
            case .neq: sqlOp = "!="
            case .gt: sqlOp = ">"
            case .gte: sqlOp = ">="
            case .lt: sqlOp = "<"
            default: sqlOp = "<="
            }
            switch rule.value {
            case .int(let value):
                binds.append(intBind(value))
            case .double(let value):
                binds.append(.double(value))
            default:
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            return "(\(column) \(sqlOp) ?)"
        case .between:
            switch rule.value {
            case .intRange(let lower, let upper):
                binds.append(intBind(lower))
                binds.append(intBind(upper))
            case .doubleRange(let lower, let upper):
                binds.append(.double(lower))
                binds.append(.double(upper))
            default:
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            return "(\(column) BETWEEN ? AND ?)"
        case .in:
            switch rule.value {
            case .intList(let values):
                binds.append(contentsOf: values.map(intBind))
                return "(\(column) IN (\(placeholders(values.count))))"
            case .doubleList(let values):
                binds.append(contentsOf: values.map { FilterSQLBind.double($0) })
                return "(\(column) IN (\(placeholders(values.count))))"
            default:
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
        default:
            throw FilterPredicateError.illegalFieldOperator(field: rule.field, op: rule.op)
        }
    }

    /// The text face. NULL/'' semantics: the v2 EXIF text columns carry the
    /// '' sentinel for "attempted, absent" (12-1), so `empty` matches BOTH
    /// NULL (never swept) and '' (swept-empty) — the honest "no value"
    /// class; `notEmpty` is its complement.
    private static func textCondition(
        for rule: FilterPredicateGroup.Rule, column: String,
        binds: inout [FilterSQLBind]
    ) throws -> String {
        switch rule.op {
        case .eq:
            guard case .text(let value) = rule.value else {
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            binds.append(.text(value))
            return "(\(column) = ?)"
        case .neq:
            guard case .text(let value) = rule.value else {
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            binds.append(.text(value))
            return "(\(column) != ?)"
        case .contains:
            guard case .text(let value) = rule.value else {
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            binds.append(.text(Self.escapeLike(value)))
            return "(\(column) LIKE '%' || ? || '%' ESCAPE '\\')"
        case .startsWith:
            guard case .text(let value) = rule.value else {
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            binds.append(.text(Self.escapeLike(value)))
            return "(\(column) LIKE ? || '%' ESCAPE '\\')"
        case .in:
            guard case .textList(let values) = rule.value else {
                throw FilterPredicateError.illegalValueKind(
                    field: rule.field, op: rule.op, valueKind: rule.value.kind)
            }
            binds.append(contentsOf: values.map { FilterSQLBind.text($0) })
            return "(\(column) IN (\(placeholders(values.count))))"
        case .empty:
            return "(\(column) IS NULL OR \(column) = '')"
        case .notEmpty:
            return "(\(column) IS NOT NULL AND \(column) != '')"
        default:
            throw FilterPredicateError.illegalFieldOperator(field: rule.field, op: rule.op)
        }
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    /// The field → column mapping (the v2 frozen spellings — a static
    /// whitelist, never user-carried).
    private static func column(for field: FilterField) throws -> String {
        switch field {
        case .rating: "rating"
        case .colorLabel: "color_label"
        case .keywords: "keywords"
        case .flag: "flag"
        case .note: "note"
        case .cameraMake: "camera_make"
        case .cameraModel: "camera_model"
        case .lensModel: "lens_model"
        case .iso: "iso"
        case .focalLength: "focal_length"
        case .aperture: "aperture"
        case .exposure: "exposure"
        case .captureDate: "capture_date"
        case .hasEdits: "has_edits"
        case .filename: "filename"
        case .dir: "dir"
        }
    }
}

extension FilterSQL {

    /// The MULTI-GROUP combinator (Plan 12-2 T4 execution decision,
    /// recorded in 12-2-DECISIONS): the v1 schema has NO nested groups, but
    /// the filter bar needs `chips AND (quickFilter's filename OR
    /// keywords)` — two flat groups AND-joined. This re-consumes the ONE
    /// translation function per group (zero new SQL shapes), wraps each
    /// product in one paren pair, and appends the `orphan_sidecar = 0`
    /// baseline EXACTLY ONCE (a per-group baseline would AND-duplicate).
    /// An empty array collapses to the baseline-only shape.
    public static func translateConjoining(
        _ groups: [FilterPredicateGroup]
    ) throws -> FilterSQLQuery {
        var clauses: [String] = []
        var binds: [FilterSQLBind] = []
        for group in groups {
            let product = try translate(group: group, appendsBaseline: false)
            clauses.append("(" + product.whereClause + ")")
            binds.append(contentsOf: product.binds)
        }
        // The baseline rides the JOIN exactly once.
        clauses.append("(orphan_sidecar = 0)")
        return FilterSQLQuery(
            whereClause: clauses.joined(separator: " AND "), binds: binds)
    }

    /// Bind a translated array to a prepared statement (1-based, array
    /// order) — the shared tail of every consumer face (the store's query
    /// and the translation-layer fixtures).
    public static func apply(
        _ binds: [FilterSQLBind], to statement: SQLiteStatement
    ) throws {
        for (index, bind) in binds.enumerated() {
            let i = Int32(index + 1)
            switch bind {
            case .text(let value): try statement.bindText(i, value)
            case .int(let value): try statement.bindInt(i, value)
            case .double(let value): try statement.bindDouble(i, value)
            }
        }
    }
}
