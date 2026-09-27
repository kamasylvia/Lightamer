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
        orderBySQL(domain: .session)
    }

    /// The domain-dispatched form (Plan 16-1 T3, F6 alignment): the catalog
    /// domain's tiebreaker is `rel_path ASC` and the whole list — NULL-flag
    /// expression included — is spelled VERBATIM like the expression
    /// indexes `(k IS NULL, k [DESC], rel_path)` from
    /// CatalogIndexSchema.orderingIndexSQL, so the planner picks the
    /// covering index with zero TEMP B-TREE (F6). The session domain is
    /// byte-identical to the pre-16-1 spelling.
    public func orderBySQL(domain: FilterDomain) -> String {
        switch domain {
        case .session:
            "\(key.orderByTerm(ascending: ascending)), path ASC"
        case .catalog:
            "\(key.orderByTerm(ascending: ascending)), rel_path ASC"
        }
    }
}

/// The SQL evaluation domain (Plan 16-1 T3, D-16-CONTEXT-3②): ONE
/// translation face, TWO shapes. `.session` = the frozen 12-2 shapes over
/// the current `session.lindex`; `.catalog` = the same predicate model over
/// `catalog_images` — keywords ride the materialized `image_tags` table
/// (EXISTS equality, F11), every non-sorting filter term carries the `+`
/// unary prefix (F10: keep the planner on the ordering index — a
/// low-selectivity filter index + TEMP B-TREE materialization measured
/// 201-525ms vs 1.46-4.93ms), and filename/dir `contains` downgrades to
/// `startsWith` under `case_sensitive_like=ON` (RQ-16-16①: the BINARY
/// index is otherwise unreachable by a case-insensitive LIKE).
///
/// The catalog templates reference the OUTER ALIAS `i` — the catalog query
/// face (CatalogIndexStore) ALWAYS spells `FROM catalog_images i`; that
/// convention is pinned HERE, in the template comments, not at call sites.
public enum FilterDomain: Sendable {
    case session
    case catalog
}

public enum FilterSQL {

    /// The ONE translation function. Throws the predicate model's typed
    /// errors for any illegal field × op × value combination (it validates
    /// defensively — the UI/store gate first, but never trust). The
    /// `domain` selects the SQL shape (Plan 16-1 T3): `.session` (the
    /// default — every pre-16-1 caller compiles and translates
    /// byte-identically) or `.catalog` (EXISTS keywords / `+` prefixes /
    /// startsWith downgrade).
    public static func translate(
        group: FilterPredicateGroup, domain: FilterDomain = .session
    ) throws -> FilterSQLQuery {
        try translate(group: group, appendsBaseline: true, domain: domain)
    }

    /// The baseline-free form for the MULTI-GROUP combinator (which
    /// attaches the baseline exactly ONCE for the whole join — per-group
    /// baselines would AND-duplicate).
    static func translate(
        group: FilterPredicateGroup, appendsBaseline: Bool,
        domain: FilterDomain = .session
    ) throws -> FilterSQLQuery {
        try group.validating()
        var binds: [FilterSQLBind] = []
        let parts = try group.rules.map {
            try condition(for: $0, domain: domain, binds: &binds)
        }
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
                ? "\(joined) AND \(baselineClause(domain))" : joined,
            binds: binds)
    }

    /// The baseline in both domains (catalog carries the `+` prefix + the
    /// `i` alias — the F10 discipline covers EVERY non-sorting term).
    private static func baselineClause(_ domain: FilterDomain) -> String {
        switch domain {
        case .session: "(orphan_sidecar = 0)"
        case .catalog: "(+i.orphan_sidecar = 0)"
        }
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

    /// The column reference for a domain: the bare frozen name on the
    /// session side; the `+`-prefixed `i`-aliased spelling on the catalog
    /// side (F10 — `+` bans the term from driving an index, keeping the
    /// ordering index in the lead; `i` is the catalog query face's pinned
    /// `FROM catalog_images i` alias).
    private static func columnRef(
        _ column: String, _ domain: FilterDomain
    ) -> String {
        switch domain {
        case .session: column
        case .catalog: "+i.\(column)"
        }
    }

    private static func condition(
        for rule: FilterPredicateGroup.Rule, domain: FilterDomain,
        binds: inout [FilterSQLBind]
    ) throws -> String {
        let column = columnRef(try Self.column(for: rule.field), domain)
        switch rule.field {
        case .keywords:
            return try keywordsCondition(
                for: rule, column: column, domain: domain, binds: &binds)
        case .rating, .colorLabel, .flag, .iso, .hasEdits,
            .focalLength, .aperture, .exposure, .captureDate:
            return try numericCondition(for: rule, column: column, binds: &binds)
        case .note, .filename, .dir, .cameraMake, .cameraModel, .lensModel:
            return try textCondition(
                for: rule, column: column, field: rule.field,
                domain: domain, binds: &binds)
        }
    }

    /// The keywords face. SESSION domain: `contains` = the FOUR-CLAUSE
    /// ancestor predicate (F3 正本); `in` = any-of four-clauses; `eq` =
    /// exact whole-column path. CATALOG domain (Plan 16-1 T3): the tags are
    /// MATERIALIZED (prefix-expanded at projection), so contains/in/eq all
    /// collapse to the equality EXISTS over `image_tags` — one bind per
    /// tag, NO LIKE and NO ESCAPE (the projection already expanded the
    /// ancestors; the sub-query walks the WITHOUT ROWID PK, F11).
    /// `empty`/`notEmpty` consume the mirrored keywords column (the
    /// NULL/'' two-state distinction lives THERE in both domains).
    private static func keywordsCondition(
        for rule: FilterPredicateGroup.Rule, column: String,
        domain: FilterDomain, binds: inout [FilterSQLBind]
    ) throws -> String {
        switch domain {
        case .session:
            return try sessionKeywordsCondition(
                for: rule, column: column, binds: &binds)
        case .catalog:
            switch rule.op {
            case .contains, .eq, .in:
                let tags: [String]
                switch rule.value {
                case .text(let tag): tags = [tag]
                case .textList(let list): tags = list
                default:
                    throw FilterPredicateError.illegalValueKind(
                        field: rule.field, op: rule.op, valueKind: rule.value.kind)
                }
                let parts = tags.map { tag -> String in
                    binds.append(.text(tag))
                    return """
                        (EXISTS (SELECT 1 FROM image_tags t \
                        WHERE t.tag = ? AND t.catalog_image_id = i.id))
                        """
                }
                return "(" + parts.joined(separator: " OR ") + ")"
            case .empty:
                return "(\(column) IS NULL OR \(column) = '')"
            case .notEmpty:
                return "(\(column) IS NOT NULL AND \(column) != '')"
            default:
                throw FilterPredicateError.illegalFieldOperator(
                    field: rule.field, op: rule.op)
            }
        }
    }

    /// The frozen 12-2 session keywords face (byte-identical to the
    /// pre-16-1 output — the regression lock).
    private static func sessionKeywordsCondition(
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
    ///
    /// Catalog domain (Plan 16-1 T3, RQ-16-16①): filename/dir `contains`
    /// DOWNGRADES to `startsWith` (`LIKE ? || '%' ESCAPE '\'` under
    /// `case_sensitive_like=ON`) so the predicate walks the idx_cat_fn /
    /// rel-path BINARY index prefix instead of a full scan (F14). The
    /// semantic loss — case-sensitivity — was pinned at plan time. Other
    /// text fields keep the contains shape (slow-path, recorded).
    private static func textCondition(
        for rule: FilterPredicateGroup.Rule, column: String, field: FilterField,
        domain: FilterDomain, binds: inout [FilterSQLBind]
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
            if domain == .catalog, field == .filename || field == .dir {
                // The startsWith downgrade (RQ-16-16①).
                return "(\(column) LIKE ? || '%' ESCAPE '\\')"
            }
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

    /// The domain-constraint ANCHOR (Plan 16-1 T3 落点 d, RQ-16-11③):
    /// what the catalog query face ANDs into every page query. A session
    /// grouping click = `i.session_id = ?`; a category-tree click =
    /// EXISTS over `image_categories`; a collection click = EXISTS over
    /// `image_collections`. Multiple anchors AND-combine; ALL-nil
    /// collapses to `(1=1)` (the All Photographs shape). v1 chips add NO
    /// organization predicate fields — the click IS the anchor (the
    /// additive slot stays open).
    ///
    /// The `i`/`t` alias spellings are the SAME contract as the keywords
    /// EXISTS template (the catalog query face's `FROM catalog_images i`).
    public static func scopeClause(
        domain: FilterDomain = .catalog,
        sessionID: String? = nil,
        categoryID: Int64? = nil,
        collectionID: Int64? = nil
    ) -> (sql: String, binds: [FilterSQLBind]) {
        var clauses: [String] = []
        var binds: [FilterSQLBind] = []
        if let sessionID {
            clauses.append("(i.session_id = ?)")
            binds.append(.text(sessionID))
        }
        if let categoryID {
            clauses.append(
                """
                (EXISTS (SELECT 1 FROM image_categories ic \
                WHERE ic.category_id = ? AND ic.catalog_image_id = i.id))
                """)
            binds.append(.int(categoryID))
        }
        if let collectionID {
            clauses.append(
                """
                (EXISTS (SELECT 1 FROM image_collections co \
                WHERE co.collection_id = ? AND co.catalog_image_id = i.id))
                """)
            binds.append(.int(collectionID))
        }
        guard !clauses.isEmpty else { return ("(1=1)", []) }
        return ("(" + clauses.joined(separator: " AND ") + ")", binds)
    }

    /// The MULTI-GROUP combinator (Plan 12-2 T4 execution decision,
    /// recorded in 12-2-DECISIONS): the v1 schema has NO nested groups, but
    /// the filter bar needs `chips AND (quickFilter's filename OR
    /// keywords)` — two flat groups AND-joined. This re-consumes the ONE
    /// translation function per group (zero new SQL shapes), wraps each
    /// product in one paren pair, and appends the `orphan_sidecar = 0`
    /// baseline EXACTLY ONCE (a per-group baseline would AND-duplicate).
    /// An empty array collapses to the baseline-only shape.
    public static func translateConjoining(
        _ groups: [FilterPredicateGroup], domain: FilterDomain = .session
    ) throws -> FilterSQLQuery {
        var clauses: [String] = []
        var binds: [FilterSQLBind] = []
        for group in groups {
            let product = try translate(
                group: group, appendsBaseline: false, domain: domain)
            clauses.append("(" + product.whereClause + ")")
            binds.append(contentsOf: product.binds)
        }
        // The baseline rides the JOIN exactly once.
        clauses.append(baselineClause(domain))
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
