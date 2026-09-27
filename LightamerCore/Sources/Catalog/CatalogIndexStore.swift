import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// CatalogIndexStore (Plan 16-1 T4) — the catalog READ face (actor, handle
// confined; the CatalogProjector owns the WRITE connection — two
// connections over one WAL database, one writer).
//
// SEAM DISCIPLINE (D-16-CONTEXT-8): this file has ZERO lindex contact
// (projection flows one way, up) and ZERO freehand SQL translation — every
// WHERE fragment comes from FilterSQL's catalog-domain products (seam a);
// the query face's constant spelling is `FROM catalog_images i`, the alias
// contract pinned in the FilterSQL templates.
//
// PAGINATION = KEYSET ONLY (research §1.1: OFFSET is dead — 113-359ms at
// 1M rows vs 0.01-27ms keyset). The two-segment shape per sortable key:
//
//   main segment — row-value seek over the ordering index:
//     WHERE <filter> AND <scope> AND (k, rel_path) < (?, ?)   [DESC]
//     WHERE <filter> AND <scope> AND (k, rel_path) > (?, ?)   [ASC]
//     ORDER BY (k IS NULL), k [DESC|ASC], rel_path ASC LIMIT n
//     A NULL k makes the row-value comparison NULL → the NULL tier is
//     skipped by the seek itself; the ORDER BY spelling is VERBATIM the
//     expression index (F6 — zero TEMP B-TREE).
//   null tail — the NULL tier as its own index walk (F15, 0.36ms@1M):
//     WHERE <filter> AND <scope> AND k IS NULL AND rel_path > ?
//     ORDER BY rel_path ASC LIMIT n     (only for nullable keys:
//     capture_date / rating; filename is never NULL — one segment).
//
//   The UI data source = BOTH segments per sort key (main exhausted → the
//   tail continues; no overlap, no gap — the keyset suite pins the seam).
//   anchor = nil means the FIRST page: no seek, straight to the index head.
//
// COUNT FACE (research §1.4): simple predicates compute on request
// (5-18ms at 1M); combo/tag predicates ride a session-level memo keyed by
// the TRANSLATED whereClause (exact — same predicate, same SQL, same
// count; no hash collisions by construction). The memo dies on
// invalidateCounts() — called by the projector after every commit
// (countsInvalidator hook) and by 16-3's classify writes. Tag badges use
// the batch shape: SELECT tag, COUNT(*) … GROUP BY (one index sweep, into
// an in-memory dictionary).
//
// v1 sortable keys = captureDate / rating / filename (the six session keys
// minus iso/focalLength/scanEpoch: scan_epoch is NOT mirrored and the
// other two have no expression index — asking for them is a typed error,
// never a silent TEMP B-TREE slow path; 16-1-DECISIONS).
// ─────────────────────────────────────────────────────────────────────────────

/// The keyset anchor: the LAST row of the previous page (its sort-key value
/// + its rel_path tiebreaker). `nil` = the first page.
public struct CatalogPageAnchor: Sendable, Equatable {
    public let keyValue: FilterSQLBind
    public let relPath: String

    public init(keyValue: FilterSQLBind, relPath: String) {
        self.keyValue = keyValue
        self.relPath = relPath
    }
}

/// The domain-constraint anchors (the scopeClause inputs; v1 UI = clicks,
/// no chips fields).
public struct FilterScope: Sendable, Equatable {
    public var sessionID: String?
    public var categoryID: Int64?
    public var collectionID: Int64?

    public init(
        sessionID: String? = nil, categoryID: Int64? = nil,
        collectionID: Int64? = nil
    ) {
        self.sessionID = sessionID
        self.categoryID = categoryID
        self.collectionID = collectionID
    }

    public var isDefault: Bool {
        sessionID == nil && categoryID == nil && collectionID == nil
    }}

/// One catalog row (the 31-column projection: id + session_id + the 29
/// mirrored columns — order matches `CatalogIndexStore.rowSelectColumns`).
public struct CatalogIndexRow: Sendable, Equatable {
    public var id: Int64 = 0
    public var sessionID: String = ""
    public var relPath: String = ""
    public var dir: String?
    public var filename: String?
    public var fileSize: Int64?
    public var fileMtime: Double?
    public var imageID: String?
    public var sidecarPresent: Int64?
    public var sidecarMtime: Double?
    public var hasEdits: Int64?
    public var paramsHash: String?
    public var layerCount: Int64?
    public var layerSummary: String?
    public var orientation: Int64?
    public var width: Int64?
    public var height: Int64?
    public var captureDate: Double?
    public var rating: Int64?
    public var colorLabel: Int64?
    public var keywords: String?
    public var orphanSidecar: Int64?
    public var flag: Int64?
    public var note: String?
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var iso: Int64?
    public var focalLength: Double?
    public var aperture: Double?
    public var exposure: Double?

    public init() {}
}

public actor CatalogIndexStore {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "catalog-index"
    )

    /// The page size (execution decision, 16-1-DECISIONS: the research
    /// probe's 60-row page — grid-viewport-sized, small enough that a
    /// keyset hop stays sub-millisecond at the index level).
    public static let defaultPageSize = 60

    private var handle: SQLiteHandle?
    private let databaseURL: URL

    /// The COUNT memo: keyed by the translated whereClause (exact — no
    /// collisions by construction). NSCache = thread-safe, auto-evicting.
    private let countMemo = NSCache<NSString, NSNumber>()

    /// Test seam: invoked on EVERY on-request count computation (the memo
    /// assertions observe this — memo hits never call it).
    public var countComputationObserver: (@Sendable () -> Void)?

    /// Actor-isolated setter (tests; keeps the property itself isolated).
    public func setCountObserver(_ observer: (@Sendable () -> Void)?) {
        countComputationObserver = observer
    }

    /// Default location (`CatalogIndexSchema.defaultDatabaseURL`).
    public init() {
        self.databaseURL = CatalogIndexSchema.defaultDatabaseURL()
    }

    /// Injected-location init (tests + a future location preference).
    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public var isClosed: Bool { handle == nil }

    public func close() {
        handle?.close()
        handle = nil
        countMemo.removeAllObjects()
    }

    /// The COUNT-memo kill switch (the projector's countsInvalidator
    /// target; 16-3's classify writes call it directly).
    public func invalidateCounts() {
        countMemo.removeAllObjects()
    }

    // MARK: - Keyset pagination (main segment)

    /// One keyset page over the ordering index. `anchor = nil` = the first
    /// page (no seek — straight to the index head). Sort keys outside the
    /// v1 catalog set are a typed error.
    public func queryPage(
        groups: [FilterPredicateGroup],
        sort: FilterSort,
        scope: FilterScope = FilterScope(),
        anchor: CatalogPageAnchor? = nil,
        limit: Int = CatalogIndexStore.defaultPageSize
    ) throws -> [CatalogIndexRow] {
        try ensureOpen()
        guard let handle else { return [] }
        let orderColumn = try Self.catalogOrderColumn(sort.key)

        let filtered = try FilterSQL.translateConjoining(groups, domain: .catalog)
        let scopeClause = FilterSQL.scopeClause(
            domain: .catalog, sessionID: scope.sessionID,
            categoryID: scope.categoryID, collectionID: scope.collectionID)

        var sql = "SELECT \(Self.rowSelectColumns) FROM catalog_images i "
            + "WHERE \(filtered.whereClause)"
        var binds = filtered.binds
        if !scope.isDefault {
            sql += " AND \(scopeClause.sql)"
            binds.append(contentsOf: scopeClause.binds)
        }
        if let anchor {
            if sort.ascending {
                // All-ASC row-value seek; a NULL key value makes the
                // comparison NULL → the NULL tier is skipped.
                sql += " AND (i.\(orderColumn), i.rel_path) > (?, ?)"
                binds.append(anchor.keyValue)
                binds.append(.text(anchor.relPath))
            } else {
                // DESC over the ASC tiebreak: a single row-value < would
                // RE-WIND inside a tier ((k, a) < (k, c) is true although
                // (k, a) was already visited) — the seek EXPANDS instead
                // (execution correction, 16-1-DECISIONS). NULL keys stay
                // excluded: k < ? and k = ? are both NULL-false.
                sql += " AND (i.\(orderColumn) < ? "
                    + "OR (i.\(orderColumn) = ? AND i.rel_path > ?))"
                binds.append(anchor.keyValue)
                binds.append(anchor.keyValue)
                binds.append(.text(anchor.relPath))
            }
        }
        sql += " ORDER BY \(sort.orderBySQL(domain: .catalog)) LIMIT ?"
        binds.append(.int(Int64(limit)))

        let statement = try handle.prepare(sql)
        try FilterSQL.apply(binds, to: statement)
        var rows: [CatalogIndexRow] = []
        while try statement.step() {
            rows.append(Self.readRow(statement))
        }
        return rows
    }

    // MARK: - Keyset pagination (NULL tail segment)

    /// The NULL tier of a nullable sort key (capture_date / rating), walked
    /// by rel_path (idx_cat_rel, F15). `anchor = nil` = the tail's first
    /// page. A filename sort throws (filename is never NULL — the main
    /// segment is the whole set).
    public func queryNullTail(
        groups: [FilterPredicateGroup],
        sort: FilterSort,
        scope: FilterScope = FilterScope(),
        anchor: CatalogPageAnchor? = nil,
        limit: Int = CatalogIndexStore.defaultPageSize
    ) throws -> [CatalogIndexRow] {
        try ensureOpen()
        guard let handle else { return [] }
        let orderColumn = try Self.nullableOrderColumn(sort.key)

        let filtered = try FilterSQL.translateConjoining(groups, domain: .catalog)
        let scopeClause = FilterSQL.scopeClause(
            domain: .catalog, sessionID: scope.sessionID,
            categoryID: scope.categoryID, collectionID: scope.collectionID)

        var sql = "SELECT \(Self.rowSelectColumns) FROM catalog_images i "
            + "WHERE \(filtered.whereClause)"
        var binds = filtered.binds
        if !scope.isDefault {
            sql += " AND \(scopeClause.sql)"
            binds.append(contentsOf: scopeClause.binds)
        }
        sql += " AND i.\(orderColumn) IS NULL"
        if let anchor {
            sql += " AND i.rel_path > ?"
            binds.append(.text(anchor.relPath))
        }
        sql += " ORDER BY i.rel_path ASC LIMIT ?"
        binds.append(.int(Int64(limit)))

        let statement = try handle.prepare(sql)
        try FilterSQL.apply(binds, to: statement)
        var rows: [CatalogIndexRow] = []
        while try statement.step() {
            rows.append(Self.readRow(statement))
        }
        return rows
    }

    // MARK: - COUNT face

    /// The badge count. Research §1.4 ruling: SIMPLE predicates (all-
    /// library, single-field, non-tag) compute ON REQUEST — every time
    /// (5-18ms at 1M rows beats cache bookkeeping); combos and tag
    /// predicates ride the memo keyed by the translated whereClause. The
    /// memo dies on invalidateCounts().
    public func count(groups: [FilterPredicateGroup]) throws -> Int {
        try ensureOpen()
        guard let handle else { return 0 }
        let translated = try FilterSQL.translateConjoining(groups, domain: .catalog)
        if !Self.isSimpleCount(groups) {
            let key = translated.whereClause as NSString
            if let memoed = countMemo.object(forKey: key) {
                return memoed.intValue
            }
            countComputationObserver?()
            let computed = try Self.executeCount(handle, translated)
            countMemo.setObject(NSNumber(value: computed), forKey: key)
            return computed
        }
        countComputationObserver?()
        return try Self.executeCount(handle, translated)
    }

    private static func executeCount(
        _ handle: SQLiteHandle, _ translated: FilterSQLQuery
    ) throws -> Int {
        let statement = try handle.prepare(
            "SELECT COUNT(*) FROM catalog_images i WHERE \(translated.whereClause)")
        try FilterSQL.apply(translated.binds, to: statement)
        var count = 0
        if try statement.step() {
            count = Int(statement.columnInt(0) ?? 0)
        }
        return count
    }

    /// Simple = zero-or-one rule, AND-matched, non-keywords (the §1.4
    /// on-request class: COUNT(*) 5ms, rating>=4 18ms, camera 4.7ms).
    private static func isSimpleCount(_ groups: [FilterPredicateGroup]) -> Bool {
        guard groups.count <= 1 else { return false }
        guard let only = groups.first else { return true }
        guard only.match == .all, only.rules.count == 1 else { return false }
        return only.rules[0].field != .keywords
    }

    /// Every tag's badge count in ONE index sweep (the tag-tree refresh;
    /// callers hold the dictionary in memory — never a per-badge query).
    public func tagCounts() throws -> [String: Int] {
        try ensureOpen()
        guard let handle else { return [:] }
        let statement = try handle.prepare(
            "SELECT tag, COUNT(*) FROM image_tags GROUP BY tag")
        var counts: [String: Int] = [:]
        while try statement.step() {
            if let tag = statement.columnText(0) {
                counts[tag] = Int(statement.columnInt(1) ?? 0)
            }
        }
        return counts
    }

    // MARK: - Sessions registry reads (Plan 16-2)

    /// One `catalog_sessions` registry row + its image count (the sidebar
    /// Sessions 从属节's row face: display name + 图计数角标 + offline
    /// gray-out). ONE LEFT-JOIN sweep — never a per-session count query.
    public struct CatalogSessionRow: Sendable, Equatable {
        public var sessionID: String = ""
        public var rootPath: String = ""
        public var displayName: String?
        public var offline: Int64 = 0
        public var imageCount: Int = 0

        public init() {}
    }

    /// The registry read (the 16-2 UI's sessions-grouping source; also the
    /// shared-runtime's empty-library touch — ensureOpen creates the file).
    public func fetchSessions() throws -> [CatalogSessionRow] {
        try ensureOpen()
        guard let handle else { return [] }
        let statement = try handle.prepare("""
            SELECT s.session_id, s.root_path, s.display_name, s.offline,
                   COUNT(i.id)
            FROM catalog_sessions s
            LEFT JOIN catalog_images i ON i.session_id = s.session_id
            GROUP BY s.session_id
            ORDER BY s.session_id
            """)
        var rows: [CatalogSessionRow] = []
        while try statement.step() {
            var row = CatalogSessionRow()
            row.sessionID = statement.columnText(0) ?? ""
            row.rootPath = statement.columnText(1) ?? ""
            row.displayName = statement.columnText(2)
            row.offline = statement.columnInt(3) ?? 0
            row.imageCount = Int(statement.columnInt(4) ?? 0)
            rows.append(row)
        }
        return rows
    }

    // MARK: - Row reads (ONE spelling)

    /// Single-row read by the composite identity.
    public func fetchRow(sessionID: String, relPath: String) throws -> CatalogIndexRow? {
        try ensureOpen()
        guard let handle else { return nil }
        let statement = try handle.prepare(
            "SELECT \(Self.rowSelectColumns) FROM catalog_images i "
                + "WHERE i.session_id = ? AND i.rel_path = ?")
        try statement.bindText(1, sessionID)
        try statement.bindText(2, relPath)
        guard try statement.step() else { return nil }
        return Self.readRow(statement)
    }

    /// The reference-key lookup for the tag/classify write faces:
    /// rel_path → the STABLE id (never a rowid) for one session's rows.
    public func imageIDs(
        sessionID: String, relPaths: [String]
    ) throws -> [String: Int64] {
        try ensureOpen()
        guard let handle, !relPaths.isEmpty else { return [:] }
        let statement = try handle.prepare(
            "SELECT rel_path, id FROM catalog_images WHERE session_id = ? AND rel_path = ?")
        var result: [String: Int64] = [:]
        for rel in relPaths {
            try statement.bindText(1, sessionID)
            try statement.bindText(2, rel)
            if try statement.step(), let id = statement.columnInt(1) {
                result[rel] = id
            }
            try statement.reset()
        }
        return result
    }

    /// Test seam: run a synchronous body against the store's OWN handle
    /// (fixture seeding for the keyset suite — the non-Sendable handle
    /// never leaves the isolation domain).
    public func withHandleForTesting(
        _ body: (SQLiteHandle) throws -> Void
    ) throws {
        try ensureOpen()
        guard let handle else { return }
        try body(handle)
    }

    // MARK: - Internals

    /// Open (creating the directory + file on demand) and apply the frozen
    /// schema. Idempotent. A failure here propagates typed — Catalogs mode
    /// degrades to disabled, Sessions mode never notices.
    private func ensureOpen() throws {
        guard handle == nil else { return }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let opened = try SQLiteHandle(path: databaseURL.path)
        handle = opened
        try CatalogIndexSchema.apply(to: opened)
    }

    /// The v1 sortable set (DECISIONS: the six session keys minus the
    /// un-mirrored / un-indexed ones — an unsupported key is a typed
    /// error, never a silent slow plan).
    private static func catalogOrderColumn(_ key: FilterSortKey) throws -> String {
        switch key {
        case .captureDate: "capture_date"
        case .rating: "rating"
        case .filename: "filename"
        case .iso, .focalLength, .scanEpoch:
            throw SessionIndexError.execFailed(
                sql: "catalog sort", code: 0,
                message: "sort key '\(key.rawValue)' has no catalog ordering "
                    + "index (v1 pin) — refusing a TEMP B-TREE plan")
        }
    }

    private static func nullableOrderColumn(_ key: FilterSortKey) throws -> String {
        switch key {
        case .captureDate: "capture_date"
        case .rating: "rating"
        case .filename, .iso, .focalLength, .scanEpoch:
            throw SessionIndexError.execFailed(
                sql: "catalog null tail", code: 0,
                message: "sort key '\(key.rawValue)' has no NULL tail segment "
                    + "(filename is never NULL; the others are not sortable)")
        }
    }

    /// The full row projection's SELECT list (the 31-column frozen order —
    /// id, session_id, then the 29 mirrors with rel_path first; ONE shared
    /// spelling so both fetch paths can never drift).
    private static let rowSelectColumns = """
        id, session_id, rel_path, dir, filename, file_size, file_mtime,
        imageID, sidecar_present, sidecar_mtime, has_edits,
        params_hash, layer_count, layer_summary, orientation,
        width, height, capture_date, rating, color_label, keywords,
        orphan_sidecar, flag, note, camera_make, camera_model, lens_model,
        iso, focal_length, aperture, exposure
        """

    /// The shared column→row projection (indices match rowSelectColumns).
    private static func readRow(_ statement: SQLiteStatement) -> CatalogIndexRow {
        var row = CatalogIndexRow()
        row.id = statement.columnInt(0) ?? 0
        row.sessionID = statement.columnText(1) ?? ""
        row.relPath = statement.columnText(2) ?? ""
        row.dir = statement.columnText(3)
        row.filename = statement.columnText(4)
        row.fileSize = statement.columnInt(5)
        row.fileMtime = statement.columnDouble(6)
        row.imageID = statement.columnText(7)
        row.sidecarPresent = statement.columnInt(8)
        row.sidecarMtime = statement.columnDouble(9)
        row.hasEdits = statement.columnInt(10)
        row.paramsHash = statement.columnText(11)
        row.layerCount = statement.columnInt(12)
        row.layerSummary = statement.columnText(13)
        row.orientation = statement.columnInt(14)
        row.width = statement.columnInt(15)
        row.height = statement.columnInt(16)
        row.captureDate = statement.columnDouble(17)
        row.rating = statement.columnInt(18)
        row.colorLabel = statement.columnInt(19)
        row.keywords = statement.columnText(20)
        row.orphanSidecar = statement.columnInt(21)
        row.flag = statement.columnInt(22)
        row.note = statement.columnText(23)
        row.cameraMake = statement.columnText(24)
        row.cameraModel = statement.columnText(25)
        row.lensModel = statement.columnText(26)
        row.iso = statement.columnInt(27)
        row.focalLength = statement.columnDouble(28)
        row.aperture = statement.columnDouble(29)
        row.exposure = statement.columnDouble(30)
        return row
    }
}
