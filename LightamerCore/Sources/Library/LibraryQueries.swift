import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LibraryQueries (Plan M2-2-3 T2) — the Inspector/query DATA face over the
// opened `.lalb` package. M2-3's shells (grid / Album Inspector panel /
// search dialog) render from THIS face and carry ZERO SQL (OQ-11).
//
// THE ONE MIXED-QUERY SHAPE (KD-2) — a single statement, three ANDed legs:
//
//   SELECT i.* FROM images i
//    WHERE <FilterSQL.translate(.library)(group + plan-structured rules)>
//      [AND i.id IN (SELECT rowid FROM images_fts WHERE images_fts MATCH ?)]
//      AND <keyset seek>
//    ORDER BY <whitelist sort, image_path ASC tiebreaker> LIMIT ?
//
//   • structured leg — the filter group AND the parser's structured/date
//     terms translate through FilterSQL's `.library` domain (M2-2-1 T4 arms;
//     the alias contract `FROM images i` is pinned THERE). Zero new SQL
//     shapes: plan terms become FilterPredicateGroup rules.
//   • lexical leg — each `ftsTerms` entry expands through
//     `ExifFold.matchQueryToken` (the SAME folded vocabulary the indexer
//     materialized) into a quoted-variant OR group; groups AND. The leg is
//     OMITTED when no terms; the structured leg degrades to `(1=1)` when
//     the filter is empty. Both legs can hit independently because the FTS
//     external-content rowid == images.id (M2-2-1 KD-5 DDL).
//   • sort leg — keyset-only (KD-3, the CatalogIndexStore port): row-value
//     seek `(k, image_path)` + the NULL tier as its own second segment
//     (`k IS NULL AND image_path > ?` — every library sort key is a
//     nullable column, unlike catalog's never-NULL filename). OFFSET is
//     banned (16-x keyset discipline).
//
// SORT WHITELIST (KD-3): the library-legal subset of FilterSortKey —
// filename / rating / captureDate / iso / focalLength. `scanEpoch` is
// EXPLICITLY EXCLUDED (a Session-domain concept; library `images` has no
// `scan_epoch` column — allowing it would sort on an all-NULL key and
// gesture at a non-existent column). The guard lives HERE, at the entry.
//
// AGGREGATES (KD-4): overviewCount / groupCounts(by:)/ activitySeries —
// pre-aggregated single statements over the same filter WHERE; the
// dayFilter projection folds a clicked activity day back into the SAME
// FilterPredicateGroup model. currentFilterDescription is the typed
// filter-state projection the M2-3 SEARCH FILTER area renders from.
//
// SINGLE CONNECTION: every read rides ProjectFileStore.withHandle (the
// WAL one-writer discipline; LibraryStore same seam).
// ─────────────────────────────────────────────────────────────────────────────

/// The combined filter input: the structured predicate group (smart-album /
/// filter-bar semantics) + the parser's lexical plan (KD-1). Both optional —
/// the empty filter lists the whole library.
public struct ExifSearchFilter: Sendable, Equatable {
    public var group: FilterPredicateGroup
    public var plan: ExifSearchPlan

    public init(
        group: FilterPredicateGroup = FilterPredicateGroup(rules: []),
        plan: ExifSearchPlan = ExifSearchPlan()
    ) {
        self.group = group
        self.plan = plan
    }
}

/// The keyset anchor: the LAST row of the previous page (its sort-key value
/// + its `image_path` tiebreaker). `nil` = the first page.
public struct LibraryPageAnchor: Sendable, Equatable {
    public let keyValue: FilterSQLBind
    public let imagePath: String

    public init(keyValue: FilterSQLBind, imagePath: String) {
        self.keyValue = keyValue
        self.imagePath = imagePath
    }

    /// The anchor of a page's last row for the given sort key.
    public static func anchor(
        of row: LibraryImageRow, key: FilterSortKey
    ) -> LibraryPageAnchor? {
        let value: FilterSQLBind?
        switch key {
        case .captureDate: value = row.captureDate.map { .double($0) }
        case .rating: value = row.rating.map { .int($0) }
        case .filename: value = row.filename.map { .text($0) }
        case .iso: value = row.iso.map { .int($0) }
        case .focalLength: value = row.focalLength.map { .double($0) }
        case .scanEpoch: value = nil
        }
        guard let value else { return nil }
        return LibraryPageAnchor(keyValue: value, imagePath: row.imagePath)
    }
}

/// One images row as the query face projects it (the frozen 28-column
/// order — `LibrarySchema.imagesColumns`).
public struct LibraryImageRow: Sendable, Equatable {
    public let id: Int64
    public let imagePath: String
    public let pathKind: Int64
    public let volumeUUID: String?
    public let cameraMake: String?
    public let cameraModel: String?
    public let lensModel: String?
    public let iso: Int64?
    public let focalLength: Double?
    public let aperture: Double?
    public let exposure: Double?
    public let captureDate: Double?
    public let fileStem: String?
    public let fileExt: String?
    public let exifSearchText: String?
    public let exifSearchWords: String?
    public let rating: Int64?
    public let colorLabel: Int64?
    public let keywords: String?
    public let filename: String?
    public let dir: String?
    public let flag: Int64?
    public let note: String?
    public let hasEdits: Int64?
    public let paramsHash: String?
    public let refCount: Int64
    public let addedTime: Double?
    public let modifiedTime: Double?
}

/// The four Inspector grouping keys (KD-4).
public enum LibraryGroupKey: String, Sendable, CaseIterable {
    case captureDate
    case camera
    case labels
    case lens
}

/// One group row: the display label + count + the KEY-TYPED click-filter
/// payload (M2-3 consumes the field matching the grouping key — never a
/// string re-parse).
public struct LibraryGroupCount: Sendable, Equatable {
    public let label: String
    public let count: Int
    /// `.captureDate` payload: the `YYYY-MM-DD` day (dayFilter input).
    public let day: String?
    /// `.camera` payload (nil when normalized to Unknown).
    public let cameraMake: String?
    public let cameraModel: String?
    /// `.labels` payload (nil = the Unrated tier).
    public let rating: Int?
    /// `.lens` payload (nil when normalized to Unknown).
    public let lensModel: String?
}

/// The typed filter-state projection (KD-4): what the M2-3 SEARCH FILTER
/// area renders — field-structured, never a string to re-parse.
public struct LibraryFilterDescription: Sendable, Equatable {
    /// The flattened structured AND-face: the group's rules followed by the
    /// plan's structured/date terms translated into the same rule model.
    public let rules: [FilterPredicateGroup.Rule]
    /// The lexical terms (FTS leg, verbatim plan spelling).
    public let ftsTerms: [String]
    /// The parser's structured terms (typed).
    public let structuredTerms: [StructuredTerm]
    /// The date window (typed).
    public let dateRange: ClosedRange<Date>?

    public var isEmpty: Bool {
        rules.isEmpty && ftsTerms.isEmpty && structuredTerms.isEmpty
            && dateRange == nil
    }
}

public actor LibraryQueries {

    /// The KD-3 library sort whitelist (the five legal keys — `scanEpoch`
    /// EXCLUDED; the entry guard rejects everything else typed).
    public static let sortableKeys: [FilterSortKey] = [
        .filename, .rating, .captureDate, .iso, .focalLength,
    ]

    /// Grid-viewport page size (the catalog default's twin).
    public static let defaultPageSize = 60

    private let store: ProjectFileStore

    public init(store: ProjectFileStore) {
        self.store = store
    }

    // MARK: - The mixed query (KD-2 + KD-3)

    /// One keyset page over the ordering index. `anchor = nil` = the first
    /// page. A sort key outside the library whitelist is a typed rejection.
    public func searchPage(
        filter: ExifSearchFilter = ExifSearchFilter(),
        sort: FilterSort,
        anchor: LibraryPageAnchor? = nil,
        limit: Int = LibraryQueries.defaultPageSize
    ) async throws -> [LibraryImageRow] {
        try Self.validateSortKey(sort.key)
        return try await store.withHandle { handle in
            try Self.runPage(
                handle, filter: filter, sort: sort, anchor: anchor,
                limit: limit, nullTail: false)
        }
    }

    /// The NULL tier of the sort key (rows whose key IS NULL), walked by
    /// `image_path`. The main segment exhausts first; this continues the
    /// collection (every library sort key is nullable — unlike catalog's
    /// filename — so the tail face is legal for ALL five keys).
    public func searchNullTail(
        filter: ExifSearchFilter = ExifSearchFilter(),
        sort: FilterSort,
        anchor: LibraryPageAnchor? = nil,
        limit: Int = LibraryQueries.defaultPageSize
    ) async throws -> [LibraryImageRow] {
        try Self.validateSortKey(sort.key)
        return try await store.withHandle { handle in
            try Self.runPage(
                handle, filter: filter, sort: sort, anchor: anchor,
                limit: limit, nullTail: true)
        }
    }

    private static func runPage(
        _ handle: SQLiteHandle, filter: ExifSearchFilter, sort: FilterSort,
        anchor: LibraryPageAnchor?, limit: Int, nullTail: Bool
    ) throws -> [LibraryImageRow] {
        var sql = "SELECT \(rowSelectColumns) FROM images i "
        var binds = try Self.appendFilterLeg(&sql, filter)
        if nullTail {
            sql += " AND i.\(sort.key.column) IS NULL"
            if let anchor {
                sql += " AND i.image_path > ?"
                binds.append(.text(anchor.imagePath))
            }
            sql += " ORDER BY i.image_path ASC LIMIT ?"
        } else {
            if let anchor {
                if sort.ascending {
                    // All-ASC row-value seek; a NULL key value makes the
                    // comparison NULL → the NULL tier is skipped here and
                    // waits for the tail segment.
                    sql += " AND (i.\(sort.key.column), i.image_path) > (?, ?)"
                    binds.append(anchor.keyValue)
                    binds.append(.text(anchor.imagePath))
                } else {
                    // DESC over the ASC tiebreak: the seek EXPANDS (the
                    // 16-1 execution correction — a single row-value <
                    // would re-wind inside a tier).
                    sql += """
                         AND (i.\(sort.key.column) < ? \
                        OR (i.\(sort.key.column) = ? AND i.image_path > ?))
                        """
                    binds.append(anchor.keyValue)
                    binds.append(anchor.keyValue)
                    binds.append(.text(anchor.imagePath))
                }
            }
            sql += " ORDER BY \(sort.orderBySQL(domain: .library)) LIMIT ?"
        }
        binds.append(.int(Int64(limit)))

        let statement = try handle.prepare(sql)
        try FilterSQL.apply(binds, to: statement)
        var rows: [LibraryImageRow] = []
        while try statement.step() {
            rows.append(readRow(statement))
        }
        return rows
    }

    // MARK: - Counts and aggregates (KD-4)

    /// The filtered total (the Overview card's 总数).
    public func overviewCount(
        filter: ExifSearchFilter = ExifSearchFilter()
    ) async throws -> Int {
        try await store.withHandle { handle -> Int in
            var sql = "SELECT COUNT(*) FROM images i "
            let binds = try Self.appendFilterLeg(&sql, filter)
            let statement = try handle.prepare(sql)
            try FilterSQL.apply(binds, to: statement)
            guard try statement.step() else { return 0 }
            return Int(statement.columnInt(0) ?? 0)
        }
    }

    /// One grouping sweep (the four Album Inspector group cards). Each key
    /// is ONE GROUP BY over the filter WHERE; Unknown normalization rides
    /// the SQL CASE (KD-4's camera/lens 归一).
    public func groupCounts(
        by key: LibraryGroupKey,
        filter: ExifSearchFilter = ExifSearchFilter()
    ) async throws -> [LibraryGroupCount] {
        try await store.withHandle { handle -> [LibraryGroupCount] in
            var sql: String
            var binds: [FilterSQLBind]
            switch key {
            case .captureDate:
                sql = """
                    SELECT strftime('%Y-%m-%d', i.capture_date, 'unixepoch') AS day, \
                    COUNT(*) FROM images i
                    """
                binds = try Self.appendFilterLeg(&sql, filter)
                sql += " AND i.capture_date IS NOT NULL GROUP BY day ORDER BY day ASC"
            case .camera:
                sql = """
                    SELECT COALESCE(NULLIF(TRIM(i.camera_make), ''), 'Unknown') AS mk, \
                    COALESCE(NULLIF(TRIM(i.camera_model), ''), 'Unknown') AS md, \
                    COUNT(*) FROM images i
                    """
                binds = try Self.appendFilterLeg(&sql, filter)
                sql += " GROUP BY mk, md ORDER BY mk ASC, md ASC"
            case .labels:
                sql = "SELECT COALESCE(i.rating, -1) AS r, COUNT(*) FROM images i "
                binds = try Self.appendFilterLeg(&sql, filter)
                sql += " GROUP BY r ORDER BY r ASC"
            case .lens:
                sql = """
                    SELECT COALESCE(NULLIF(TRIM(i.lens_model), ''), 'Unknown') AS lens, \
                    COUNT(*) FROM images i
                    """
                binds = try Self.appendFilterLeg(&sql, filter)
                sql += " GROUP BY lens ORDER BY lens ASC"
            }
            let statement = try handle.prepare(sql)
            try FilterSQL.apply(binds, to: statement)
            var counts: [LibraryGroupCount] = []
            while try statement.step() {
                switch key {
                case .captureDate:
                    counts.append(LibraryGroupCount(
                        label: statement.columnText(0) ?? "",
                        count: Int(statement.columnInt(1) ?? 0),
                        day: statement.columnText(0),
                        cameraMake: nil, cameraModel: nil,
                        rating: nil, lensModel: nil))
                case .camera:
                    let make = statement.columnText(0)
                    let model = statement.columnText(1)
                    let unknown = make == "Unknown" && model == "Unknown"
                    let label = unknown
                        ? "Unknown"
                        : [make, model]
                            .filter { $0 != nil && $0 != "Unknown" }
                            .compactMap { $0 }
                            .joined(separator: " ")
                    counts.append(LibraryGroupCount(
                        label: label,
                        count: Int(statement.columnInt(2) ?? 0),
                        day: nil,
                        cameraMake: make == "Unknown" ? nil : make,
                        cameraModel: model == "Unknown" ? nil : model,
                        rating: nil, lensModel: nil))
                case .labels:
                    let raw = statement.columnInt(0) ?? -1
                    let rating: Int? = raw >= 0 ? Int(raw) : nil
                    let label: String
                    switch raw {
                    case -1: label = "Unrated"
                    case 0: label = "No stars"
                    default:
                        label = String(repeating: "★", count: Int(raw))
                    }
                    counts.append(LibraryGroupCount(
                        label: label,
                        count: Int(statement.columnInt(1) ?? 0),
                        day: nil, cameraMake: nil, cameraModel: nil,
                        rating: rating, lensModel: nil))
                case .lens:
                    let lens = statement.columnText(0)
                    counts.append(LibraryGroupCount(
                        label: lens ?? "Unknown",
                        count: Int(statement.columnInt(1) ?? 0),
                        day: nil, cameraMake: nil, cameraModel: nil,
                        rating: nil,
                        lensModel: lens == "Unknown" ? nil : lens))
                }
            }
            return counts
        }
    }

    /// The Activity view's per-day count series (KD-4's data 正本), ASC by
    /// day. The optional range bounds the sweep (the visible calendar
    /// window); the filter legs still apply.
    public func activitySeries(
        range: ClosedRange<Date>? = nil,
        filter: ExifSearchFilter = ExifSearchFilter()
    ) async throws -> [(day: String, count: Int)] {
        try await store.withHandle { handle -> [(day: String, count: Int)] in
            var sql = """
                SELECT strftime('%Y-%m-%d', i.capture_date, 'unixepoch') AS day, \
                COUNT(*) FROM images i
                """
            let binds = try Self.appendFilterLeg(&sql, filter)
            var allBinds = binds
            if let range {
                sql += " AND i.capture_date BETWEEN ? AND ?"
                allBinds.append(.double(range.lowerBound.timeIntervalSince1970))
                allBinds.append(.double(range.upperBound.timeIntervalSince1970))
            }
            sql += " AND i.capture_date IS NOT NULL GROUP BY day ORDER BY day ASC"
            let statement = try handle.prepare(sql)
            try FilterSQL.apply(allBinds, to: statement)
            var series: [(day: String, count: Int)] = []
            while try statement.step() {
                if let day = statement.columnText(0) {
                    series.append(
                        (day: day, count: Int(statement.columnInt(1) ?? 0)))
                }
            }
            return series
        }
    }

    /// The clicked-day projection (KD-4): an activity day folds back into
    /// the SAME predicate model — a `capture_date` between covering the
    /// whole UTC day at whole-second closure (EXIF carries no sub-second).
    public static func dayFilter(_ day: String) throws -> FilterPredicateGroup {
        let parts = day.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]),
              let dayNumber = Int(parts[2])
        else {
            throw LibraryError.constraintViolation(
                detail: "activity day must be YYYY-MM-DD: \(day)")
        }
        var components = DateComponents(
            year: year, month: month, day: dayNumber,
            hour: 0, minute: 0, second: 0)
        components.timeZone = TimeZone(identifier: "UTC")
        guard let start = Calendar(identifier: .iso8601).date(from: components)
        else {
            throw LibraryError.constraintViolation(
                detail: "not a calendar day: \(day)")
        }
        return FilterPredicateGroup(
            rules: [
                .init(
                    field: .captureDate, op: .between,
                    value: .doubleRange(
                        lower: start.timeIntervalSince1970,
                        upper: start.timeIntervalSince1970 + 86_399)),
            ])
    }

    /// The typed filter-state projection (KD-4): the M2-3 SEARCH FILTER
    /// rendering source. Pure — no store round-trip.
    public func currentFilterDescription(
        filter: ExifSearchFilter
    ) -> LibraryFilterDescription {
        let structuredRules = (try? Self.structuredRules(filter.plan)) ?? []
        return LibraryFilterDescription(
            rules: filter.group.rules + structuredRules,
            ftsTerms: filter.plan.ftsTerms,
            structuredTerms: filter.plan.structured,
            dateRange: filter.plan.dateRange)
    }

    // MARK: - Smart-album evaluation support (the M2-2-1 T4 seam closure)

    /// The FULL member set of one predicate group over the library domain,
    /// collected by an `id`-keyset walk (the rowid PK: never NULL, no tie
    /// tier, no NULL-tail segment — the honest full-collection sweep for
    /// the SmartAlbumStore .library arm, mirroring the catalog arm's
    /// page-walk shape).
    public func memberIDs(
        matching group: FilterPredicateGroup, pageSize: Int = 1_000
    ) async throws -> [Int64] {
        try await store.withHandle { handle -> [Int64] in
            var ids: [Int64] = []
            var cursor: Int64 = 0
            while true {
                let translated = try FilterSQL.translate(
                    group: group, domain: .library)
                let sql = "SELECT i.id FROM images i"
                    + " WHERE \(translated.whereClause)"
                    + " AND i.id > ? ORDER BY i.id ASC LIMIT ?"
                var binds = translated.binds
                binds.append(.int(cursor))
                binds.append(.int(Int64(pageSize)))
                let statement = try handle.prepare(sql)
                try FilterSQL.apply(binds, to: statement)
                var page: [Int64] = []
                while try statement.step() {
                    if let id = statement.columnInt(0) { page.append(id) }
                }
                ids.append(contentsOf: page)
                if page.count < pageSize { break }
                cursor = page.last ?? cursor
            }
            return ids
        }
    }

    // MARK: - The shared WHERE assembly (KD-2's legs)

    /// Append the filter legs (structured + lexical) to a `FROM images i`
    /// SELECT — the ONE shape every query face reuses. Returns the aligned
    /// binds. Empty structured degrades to the `(1=1)` baseline (the
    /// `.library` domain's own baseline face); empty lexical omits the
    /// MATCH leg entirely.
    private static func appendFilterLeg(
        _ sql: inout String, _ filter: ExifSearchFilter
    ) throws -> [FilterSQLBind] {
        // The WHERE clause concatenates onto whatever SELECT header the
        // caller spelled — normalize the join point (multiline templates
        // strip their trailing indentation, so a bare `FROM images i`
        // arrives with no trailing space).
        if !sql.hasSuffix(" ") { sql += " " }
        var rules = filter.group.rules
        rules.append(contentsOf: try structuredRules(filter.plan))
        let effective = FilterPredicateGroup(match: .all, rules: rules)
        let translated = try FilterSQL.translate(
            group: effective, domain: .library)
        sql += "WHERE \(translated.whereClause)"
        var binds = translated.binds
        if !filter.plan.ftsTerms.isEmpty {
            sql += " AND i.id IN (SELECT rowid FROM images_fts"
                + " WHERE images_fts MATCH ?)"
            binds.append(.text(try matchQueryString(filter.plan.ftsTerms)))
        }
        return binds
    }

    /// The plan's structured/date terms → FilterPredicateGroup rules (the
    /// ONE translation face consumes them — zero new SQL shapes). ISO
    /// values ride `.int` (the column is INTEGER); focal/aperture ride
    /// `.double`; the date window rides `capture_date BETWEEN`.
    static func structuredRules(
        _ plan: ExifSearchPlan
    ) throws -> [FilterPredicateGroup.Rule] {
        var rules: [FilterPredicateGroup.Rule] = []
        for term in plan.structured {
            let op: FilterOp
            switch term.constraint {
            case .equals: op = .eq
            case .greaterThan: op = .gt
            case .greaterThanOrEqual: op = .gte
            case .lessThan: op = .lt
            case .lessThanOrEqual: op = .lte
            case .between: op = .between
            }
            let field: FilterField
            let value: FilterValue
            switch term.field {
            case .iso:
                field = .iso
                value = try intValue(term.constraint)
            case .focalLength:
                field = .focalLength
                value = try doubleValue(term.constraint)
            case .aperture:
                field = .aperture
                value = try doubleValue(term.constraint)
            }
            rules.append(.init(field: field, op: op, value: value))
        }
        if let range = plan.dateRange {
            rules.append(.init(
                field: .captureDate, op: .between,
                value: .doubleRange(
                    lower: range.lowerBound.timeIntervalSince1970,
                    upper: range.upperBound.timeIntervalSince1970)))
        }
        return rules
    }

    private static func intValue(
        _ constraint: StructuredTerm.Constraint
    ) throws -> FilterValue {
        func int(_ v: Double) -> Int { Int(v.rounded()) }
        switch constraint {
        case .equals(let v): return .int(int(v))
        case .greaterThan(let v): return .int(int(v))
        case .greaterThanOrEqual(let v): return .int(int(v))
        case .lessThan(let v): return .int(int(v))
        case .lessThanOrEqual(let v): return .int(int(v))
        case .between(let lower, let upper):
            return .intRange(lower: int(lower), upper: int(upper))
        }
    }

    private static func doubleValue(
        _ constraint: StructuredTerm.Constraint
    ) throws -> FilterValue {
        switch constraint {
        case .equals(let v): return .double(v)
        case .greaterThan(let v): return .double(v)
        case .greaterThanOrEqual(let v): return .double(v)
        case .lessThan(let v): return .double(v)
        case .lessThanOrEqual(let v): return .double(v)
        case .between(let lower, let upper):
            return .doubleRange(lower: lower, upper: upper)
        }
    }

    /// The FTS MATCH query string for the lexical leg: per term, the folded
    /// variant set as quoted alternatives (prefix terms keep the trailing
    /// `*` as the FTS5 phrase-prefix marker); terms AND. Quoting closes
    /// the injection face (variants are folded alphanumerics + spaces, but
    /// the doubling defense is structural).
    static func matchQueryString(_ terms: [String]) throws -> String {
        let groups: [String] = try terms.map { term in
            let isPrefix = term.hasSuffix("*")
            let base = isPrefix ? String(term.dropLast()) : term
            let variants = ExifFold.matchQueryToken(base)
            guard !variants.isEmpty else {
                throw LibraryError.constraintViolation(
                    detail: "lexical term folds to no FTS token: \(term)")
            }
            let quoted = variants.map { variant -> String in
                let escaped = variant
                    .replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"\(isPrefix ? "*" : "")"
            }
            return "(" + quoted.joined(separator: " OR ") + ")"
        }
        return groups.joined(separator: " AND ")
    }

    // MARK: - Guards and projection (ONE spelling)

    /// The KD-3 entry guard: a sort key outside the library five-key
    /// whitelist is a typed rejection — `scanEpoch` especially (the
    /// Session-domain key would order on a non-existent column).
    static func validateSortKey(_ key: FilterSortKey) throws {
        guard sortableKeys.contains(key) else {
            throw LibraryError.constraintViolation(
                detail: "sort key '\(key.rawValue)' is outside the library "
                    + "domain whitelist (KD-3): "
                    + sortableKeys.map(\.rawValue).joined(separator: "/"))
        }
    }

    /// The 28-column frozen projection (order == LibrarySchema.imagesColumns).
    static let rowSelectColumns = """
        id, image_path, path_kind, volume_uuid, camera_make, camera_model,
        lens_model, iso, focal_length, aperture, exposure, capture_date,
        file_stem, file_ext, exif_search_text, exif_search_words, rating,
        color_label, keywords, filename, dir, flag, note, has_edits,
        params_hash, ref_count, added_time, modified_time
        """

    private static func readRow(_ statement: SQLiteStatement) -> LibraryImageRow {
        LibraryImageRow(
            id: statement.columnInt(0) ?? 0,
            imagePath: statement.columnText(1) ?? "",
            pathKind: statement.columnInt(2) ?? 0,
            volumeUUID: statement.columnText(3),
            cameraMake: statement.columnText(4),
            cameraModel: statement.columnText(5),
            lensModel: statement.columnText(6),
            iso: statement.columnInt(7),
            focalLength: statement.columnDouble(8),
            aperture: statement.columnDouble(9),
            exposure: statement.columnDouble(10),
            captureDate: statement.columnDouble(11),
            fileStem: statement.columnText(12),
            fileExt: statement.columnText(13),
            exifSearchText: statement.columnText(14),
            exifSearchWords: statement.columnText(15),
            rating: statement.columnInt(16),
            colorLabel: statement.columnInt(17),
            keywords: statement.columnText(18),
            filename: statement.columnText(19),
            dir: statement.columnText(20),
            flag: statement.columnInt(21),
            note: statement.columnText(22),
            hasEdits: statement.columnInt(23),
            paramsHash: statement.columnText(24),
            refCount: statement.columnInt(25) ?? 0,
            addedTime: statement.columnDouble(26),
            modifiedTime: statement.columnDouble(27))
    }
}
