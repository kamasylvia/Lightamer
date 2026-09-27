import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// CatalogProjector (Plan 16-1 T2) — the lindex → catalog watermark projector.
//
// The two-level derivation chain (sidecar TRUTH → session.lindex → catalog)
// ends here: every catalog_images row is a re-derivable mirror, the registry
// rows in catalog_sessions are the projection state, and the organization
// tables (categories/collections) are NEVER touched by projection (they are
// the catalog's own asset — D-16-CONTEXT specifics).
//
// ONE projection = ONE `BEGIN IMMEDIATE` transaction over the session
// (RQ-16-17: busy is made explicit immediately; no mid-transaction upgrade):
//
//   ① registry  — catalog_sessions row by realpath(3)-normalized root_path
//                 (L027: the "same shape" path illusion is real; the FIRST
//                 registration mints a UUIDv4 session_id and re-adds reuse
//                 it — SessionState.promoteRecent's URL-exact-dedupe twin).
//   ② reconcile — the KEY-SET audit (research correction ①): a pure
//                 watermark diff cannot see DELETED rows, so every
//                 projection reads the full rel_path key sets on both sides
//                 (light single column — ~6ms/100k rows, F12) and DELETEs
//                 the catalog-side stragglers WITH their image_tags rows
//                 (the SessionIndexStore.sync three-leg discipline, cross-
//                 library twin).
//   ③ watermark — `WHERE scan_epoch > last_projected_epoch` → the 29
//                 mirrored columns → `INSERT … ON CONFLICT(session_id,
//                 rel_path) DO UPDATE SET … RETURNING id` (F12 shape; the
//                 conflict path KEEPS the existing id — organization
//                 references never dangle, R1) → the row's image_tags are
//                 deleted and re-inserted from the expanded tag set
//                 (per-image idempotent, R6).
//   ④ tags      — the materialized keywords string expands by the PREFIX-
//                 CHAIN algorithm (research §6 verbatim — see tagRows):
//                 split tokens each become a row PLUS every positional
//                 prefix. "A|B|C" → {A, B, C, A|B, A|B|C} — a deliberate
//                 SUPERSET of the session face's four-clause matches (the
//                 `|` separator ambiguity is shared by both domains, so
//                 parity holds directionally: catalog ⊆ session).
//   ⑤ offline   — `<root>/.lightamer/session.lindex` stat failure marks
//                 offline=1, skips the session, leaves the watermark alone
//                 (the sweep re-checks; recovery clears the flag).
//   ⑥ watermark bump + last_seen + offline=0, COMMIT.
//
// Lindex reads run on a READ-ONLY connection (projection never writes the
// lindex) opened and closed inside this actor — the non-Sendable handles
// never cross an isolation boundary.
//
// GUARD: `CatalogPreferences.catalogsEnabled == false` → `project` returns
// before ANY handle exists (Sessions-only users get ZERO .lcat file — the
// literal CATALOG-01 execution; the App-side hook guards too, defense in
// depth).
//
// The catalog write handle lives HERE (the projector is the single writer);
// CatalogIndexStore opens its own connection for the READ face — two
// connections over one WAL database, one writer, standard SQLite. After a
// committed projection the COUNT memo must die: `countsInvalidator` is
// invoked (CatalogIndexStore.invalidateCounts — wired by the consumer).
// ─────────────────────────────────────────────────────────────────────────────

/// The enable preference (Plan 16-1 T2 — the UserDefaults key + read face;
/// the UI switch lands in 16-2). Suite-NAME based so the seam stays
/// Sendable (UserDefaults itself is not; the suite instance is built where
/// it is consumed).
public enum CatalogPreferences {

    public static let catalogsEnabledKey = "catalogs.enabled"

    public static func catalogsEnabled(defaultsSuiteName: String? = nil) -> Bool {
        let defaults = defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) }
            ?? .standard
        return defaults.bool(forKey: catalogsEnabledKey)
    }

    public static func setCatalogsEnabled(
        _ enabled: Bool, defaultsSuiteName: String? = nil
    ) {
        let defaults = defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) }
            ?? .standard
        defaults.set(enabled, forKey: catalogsEnabledKey)
    }
}

/// One projection's diff summary (the App logs it; tests assert the legs).
public struct CatalogProjectionResult: Sendable, Equatable {
    public var sessionID: String = ""
    public var added = 0
    public var removed = 0
    public var changed = 0
    public var offline = false
    /// True when the enable guard short-circuited (zero handles opened).
    public var skippedByGuard = false

    public init() {}
}

/// Failure-injection points for the transaction-atomicity test (the
/// SessionIndexStore.sync seam, cross-library twin).
public enum CatalogProjectionFailureInjection: String, Sendable, CaseIterable {
    case none
    /// Throw AFTER the reconcile deletes, before the watermark upserts.
    case afterReconcile
    /// Throw AFTER all mutations, before COMMIT.
    case beforeCommit
}

public actor CatalogProjector {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "catalog-projector"
    )

    private var handle: SQLiteHandle?
    private let databaseURL: URL
    /// Suite-NAME storage (Sendable) — the UserDefaults instance is built
    /// on access, inside this actor.
    private let defaultsSuiteName: String?

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Test seam: mid-projection failure injection (the ROLLBACK test).
    private var failureInjection: CatalogProjectionFailureInjection = .none

    /// The COUNT-memo invalidation hook — invoked after every COMMITTED
    /// projection (CatalogIndexStore.invalidateCounts; 16-3's classify
    /// writes call the store face directly).
    public var countsInvalidator: (@Sendable () async -> Void)?

    /// Isolated setter seam (16-2 T1: the shared-runtime wiring assigns
    /// the hook from outside the actor — the `setCountObserver` pattern).
    public func setCountsInvalidator(_ invalidator: (@Sendable () async -> Void)?) {
        countsInvalidator = invalidator
    }

    /// Default location (`CatalogIndexSchema.defaultDatabaseURL`).
    public init(defaultsSuiteName: String? = nil) {
        self.databaseURL = CatalogIndexSchema.defaultDatabaseURL()
        self.defaultsSuiteName = defaultsSuiteName
    }

    /// Injected-location init (tests + a future location preference).
    public init(databaseURL: URL, defaultsSuiteName: String? = nil) {
        self.databaseURL = databaseURL
        self.defaultsSuiteName = defaultsSuiteName
    }

    public func setFailureInjection(_ mode: CatalogProjectionFailureInjection) {
        failureInjection = mode
    }

    public var isClosed: Bool { handle == nil }

    public func close() {
        handle?.close()
        handle = nil
    }

    /// The project tags row set for ONE materialized keywords string —
    /// research §6's serial-domain prefix expansion, VERBATIM:
    ///
    ///   nil    -> ∅                (NULL = never tagged)
    ///   ""     -> ∅                (empty string = cleared; the two states
    ///                               stay distinguishable in the MIRROR
    ///                               keywords column, not here)
    ///   tokens = materialized.split("|")
    ///   rows   = Set(tokens)                            (each token, a row)
    ///   rows  += { tokens[0..<i].joined("|") for i in 1...tokens.count }
    ///
    /// "A|B|C" → {A, B, C, A|B, A|B|C} — the deliberate superset of the
    /// session face's four-clause matches (research §6 裁决).
    /// Execution refinement (16-1-DECISIONS): split omits empty
    /// subsequences ("A||B" cannot mint an empty-tag row).
    public static func tagRows(fromMaterialized materialized: String?) -> Set<String> {
        guard let materialized, !materialized.isEmpty else { return [] }
        let tokens = materialized
            .split(separator: "|", omittingEmptySubsequences: true)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }
        var rows = Set(tokens)
        for i in 1...tokens.count {
            rows.insert(tokens[0..<i].joined(separator: "|"))
        }
        return rows
    }

    // MARK: - Projection

    /// Project one session root into the catalog. Guarded, idempotent,
    /// single-transaction. Never throws for "nothing to do" — only for
    /// real failures (which ROLLBACK; Sessions mode is untouched by any of
    /// this — the projector does not even exist on that path).
    @discardableResult
    public func project(sessionRoot root: URL) async throws -> CatalogProjectionResult {
        var result = CatalogProjectionResult()

        // ⑦ the enable guard — BEFORE any handle: a disabled Catalogs mode
        // never creates the .lcat file (the double-mode isolation probe).
        guard CatalogPreferences.catalogsEnabled(defaultsSuiteName: defaultsSuiteName) else {
            result.skippedByGuard = true
            return result
        }

        try ensureOpen()

        // ⑤ lindex presence FIRST (stat): a missing index = the session is
        // offline — mark it, leave the watermark alone, return.
        let normalizedRoot = root.resolvingSymlinksInPath().path
        let lindexURL = SessionIndexSchema.databaseURL(forSessionRoot: root)
        guard FileManager.default.fileExists(atPath: lindexURL.path) else {
            try markOffline(normalizedRoot: normalizedRoot, offline: true)
            result.offline = true
            return result
        }

        // The read-only lindex connection lives and dies inside this actor.
        let lindex = try SQLiteHandle(
            path: lindexURL.path,
            flags: SQLiteHandle.readOnlyFlags)
        defer { lindex.close() }

        result = try projectTransaction(
            normalizedRoot: normalizedRoot, lindex: lindex, root: root)
        // The COUNT memo dies with the new data (CatalogIndexStore's
        // invalidateCounts — the consumer wires this hook).
        if let invalidator = countsInvalidator {
            await invalidator()
        }
        return result
    }

    /// The single-transaction core (internal so the tests can drive the
    /// failure injections and so `sweepAll` reuses the exact same path).
    func projectTransaction(
        normalizedRoot: String, lindex: SQLiteHandle, root: URL
    ) throws -> CatalogProjectionResult {
        guard let handle else {
            throw SessionIndexError.execFailed(
                sql: "project", code: 0, message: "catalog handle unavailable")
        }
        var result = CatalogProjectionResult()

        try handle.exec("BEGIN IMMEDIATE")
        do {
            // ── ① registry: mint or reuse the session_id (realpath-
            // normalized exact string compare — L027).
            let sessionID = try registerSession(
                normalizedRoot: normalizedRoot, root: root, handle: handle)
            result.sessionID = sessionID

            let currentWatermark = try readWatermark(
                sessionID: sessionID, handle: handle)

            // ── ② key-set reconcile: full rel_path sets on both sides.
            let lindexKeys = try readLindexKeys(lindex: lindex)
            var catalogKeys = Set<String>()
            var keyToID: [String: Int64] = [:]
            let catalogRows = try handle.prepare(
                "SELECT rel_path, id FROM catalog_images WHERE session_id = ?")
            try catalogRows.bindText(1, sessionID)
            while try catalogRows.step() {
                guard let rel = catalogRows.columnText(0) else { continue }
                catalogKeys.insert(rel)
                keyToID[rel] = catalogRows.columnInt(1)
            }

            let removedKeys = catalogKeys.subtracting(lindexKeys)
            let deleteRow = try handle.prepare(
                "DELETE FROM catalog_images WHERE session_id = ? AND rel_path = ?")
            let deleteTags = try handle.prepare(
                "DELETE FROM image_tags WHERE catalog_image_id = ?")
            // Plan 16-3 (the organization-data view): the membership rows
            // cascade WITH the image row — a dangling category/collection
            // reference to a deleted image is unreachable by construction
            // (the removeSession leg already cascaded all three; the
            // reconcile leg had only tags because 16-1 shipped before the
            // organization write face existed).
            let deleteCategoryMembership = try handle.prepare(
                "DELETE FROM image_categories WHERE catalog_image_id = ?")
            let deleteCollectionMembership = try handle.prepare(
                "DELETE FROM image_collections WHERE catalog_image_id = ?")
            for rel in removedKeys {
                if let id = keyToID[rel] {
                    try deleteTags.bindInt(1, id)
                    _ = try deleteTags.step()
                    try deleteTags.reset()
                    try deleteCategoryMembership.bindInt(1, id)
                    _ = try deleteCategoryMembership.step()
                    try deleteCategoryMembership.reset()
                    try deleteCollectionMembership.bindInt(1, id)
                    _ = try deleteCollectionMembership.step()
                    try deleteCollectionMembership.reset()
                }
                try deleteRow.bindText(1, sessionID)
                try deleteRow.bindText(2, rel)
                _ = try deleteRow.step()
                try deleteRow.reset()
                result.removed += 1
            }

            if failureInjection == .afterReconcile {
                throw SessionIndexError.execFailed(
                    sql: "test-injection(afterReconcile)", code: 1, message: "injected")
            }

            // ── ③ watermark increment: the mirrored columns of every row
            // newer than the watermark → UPSERT (id PRESERVED on conflict)
            // + tags re-materialized per row (④).
            let upsert = try handle.prepare(Self.upsertSQL)
            let clearTags = deleteTags // same statement shape, reused
            let insertTag = try handle.prepare(
                "INSERT INTO image_tags (tag, catalog_image_id) VALUES (?, ?)")
            let increment = try lindex.prepare(
                "SELECT \(Self.lindexSelectColumns) FROM images WHERE scan_epoch > ?")
            try increment.bindInt(1, currentWatermark)
            while try increment.step() {
                let relPath = increment.columnText(0) ?? ""
                let wasExisting = catalogKeys.contains(relPath)
                // binds: 1 session_id, 2 rel_path, 3… the other 28 mirrors.
                try upsert.bindText(1, sessionID)
                try upsert.bindText(2, relPath)
                for (index, column) in Self.mirrorTailColumns.enumerated() {
                    let columnIdx = Int32(index + 1)  // lindex SELECT: path at 0, tail at 1…
                    let bindIdx = Int32(index + 3)
                    switch Self.mirrorColumnTypes[column] ?? .text {
                    case .text: try upsert.bindText(bindIdx, increment.columnText(columnIdx))
                    case .integer: try upsert.bindInt(bindIdx, increment.columnInt(columnIdx))
                    case .real: try upsert.bindDouble(bindIdx, increment.columnDouble(columnIdx))
                    }
                }
                guard try upsert.step(), let rowID = upsert.columnInt(0) else {
                    throw SessionIndexError.execFailed(
                        sql: "upsert RETURNING id", code: 0,
                        message: "UPSERT … RETURNING returned no row")
                }
                try upsert.reset()

                // ④ tags: delete-then-insert (per-image idempotent, R6).
                try clearTags.bindInt(1, rowID)
                _ = try clearTags.step()
                try clearTags.reset()
                let materialized = increment.columnText(
                    Int32(Self.keywordsTailIndex))
                for tag in Self.tagRows(fromMaterialized: materialized).sorted() {
                    try insertTag.bindText(1, tag)
                    try insertTag.bindInt(2, rowID)
                    _ = try insertTag.step()
                    try insertTag.reset()
                }

                if wasExisting { result.changed += 1 } else { result.added += 1 }
            }

            if failureInjection == .beforeCommit {
                throw SessionIndexError.execFailed(
                    sql: "test-injection(beforeCommit)", code: 1, message: "injected")
            }

            // ── ⑥ watermark bump + last_seen + online.
            let newWatermark = try SessionIndexSchema.readScanEpoch(from: lindex)
            let update = try handle.prepare("""
                UPDATE catalog_sessions
                SET last_projected_epoch = ?, last_seen = ?, offline = 0
                WHERE session_id = ?
                """)
            try update.bindInt(1, newWatermark)
            try update.bindDouble(2, Date().timeIntervalSince1970)
            try update.bindText(3, sessionID)
            _ = try update.step()

            try handle.exec("COMMIT")
        } catch {
            // ONE bulk change = ONE transaction: any failure rolls the
            // whole projection back — the catalog row set is exactly as
            // before; Sessions mode never knew this happened.
            try? handle.exec("ROLLBACK")
            throw error
        }
        return result
    }

    // MARK: - Sweep (RQ-16-4 trigger face b)

    /// Catalogs-mode startup sweep: every registered session, SERIALLY
    /// (one .lcat, one writer — concurrent projections contend for no
    /// benefit), Task.yield between sessions. `recentRoots` = the recent
    /// list's still-existing sessions that are NOT yet registered (the
    /// "opened but never projected" backfill — 16-2 wires the UI timing;
    /// this plan ships the API + the test seam).
    @discardableResult
    public func sweepAll(recentRoots: [URL] = []) async -> [CatalogProjectionResult] {
        var results: [CatalogProjectionResult] = []
        guard CatalogPreferences.catalogsEnabled(defaultsSuiteName: defaultsSuiteName) else { return results }
        try? ensureOpen()
        guard let handle else { return results }

        var roots: [String] = []
        let statement = try? handle.prepare(
            "SELECT root_path FROM catalog_sessions ORDER BY root_path")
        if let statement {
            while (try? statement.step()) == true {
                if let path = statement.columnText(0) { roots.append(path) }
            }
        }

        for path in roots {
            await Task.yield()
            if let result = try? await project(sessionRoot: URL(fileURLWithPath: path)) {
                results.append(result)
            }
        }
        // The recent list's unregistered sessions register on project.
        let registered = Set(roots)
        for recent in recentRoots {
            let normalized = recent.resolvingSymlinksInPath().path
            guard !registered.contains(normalized) else { continue }
            guard FileManager.default.fileExists(atPath: normalized) else { continue }
            await Task.yield()
            if let result = try? await project(sessionRoot: recent) {
                results.append(result)
            }
        }
        return results
    }

    // MARK: - Session management (Plan 16-2 T2, D-16-CONTEXT-7②④)

    /// The typed failure of the session-management faces.
    public enum SessionManagementError: Error, Equatable {
        /// No registered session with this id.
        case notFound(sessionID: String)
        /// The re-link target is already registered under ANOTHER session
        /// (removing that one first is the user's explicit action).
        case rootAlreadyRegistered(rootPath: String)
    }

    /// 「从 Catalog 移除会话」(D-16-CONTEXT-7④) — the EXPLICIT user action:
    /// the session's row set, its tags, and its ORGANIZATION memberships
    /// (categories/collections rows ride the image rows' deletion) are
    /// cleared in ONE transaction, then the registry row itself goes.
    /// The files on disk are NEVER touched (reference mode). After a
    /// commit the COUNT memo dies via the same hook projection uses.
    public func removeSession(sessionID: String) async throws {
        guard CatalogPreferences.catalogsEnabled(defaultsSuiteName: defaultsSuiteName) else {
            throw SessionManagementError.notFound(sessionID: sessionID)
        }
        try ensureOpen()
        guard let handle else { return }

        let exists = try handle.prepare(
            "SELECT 1 FROM catalog_sessions WHERE session_id = ?")
        try exists.bindText(1, sessionID)
        guard try exists.step() else {
            throw SessionManagementError.notFound(sessionID: sessionID)
        }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            let statements: [String] = [
                "DELETE FROM image_tags WHERE catalog_image_id IN "
                    + "(SELECT id FROM catalog_images WHERE session_id = ?)",
                "DELETE FROM image_categories WHERE catalog_image_id IN "
                    + "(SELECT id FROM catalog_images WHERE session_id = ?)",
                "DELETE FROM image_collections WHERE catalog_image_id IN "
                    + "(SELECT id FROM catalog_images WHERE session_id = ?)",
                "DELETE FROM catalog_images WHERE session_id = ?",
                "DELETE FROM catalog_sessions WHERE session_id = ?",
            ]
            for sql in statements {
                let statement = try handle.prepare(sql)
                try statement.bindText(1, sessionID)
                _ = try statement.step()
            }
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
        if let invalidator = countsInvalidator {
            await invalidator()
        }
    }

    /// 「Re-link 会话文件夹」(D-16-CONTEXT-7②) — the folder moved: update
    /// `root_path` to the new location (realpath-normalized, the registry
    /// key), clear `offline`, then run an IMMEDIATE re-projection (the
    /// watermark rides the moved lindex; no automatic path search — the
    /// user picked the folder). The registry reuse semantics make the
    /// projection land on the SAME session_id.
    public func relinkSession(
        sessionID: String, newRoot: URL
    ) async throws -> CatalogProjectionResult {
        guard CatalogPreferences.catalogsEnabled(defaultsSuiteName: defaultsSuiteName) else {
            throw SessionManagementError.notFound(sessionID: sessionID)
        }
        try ensureOpen()
        guard let handle else {
            throw SessionManagementError.notFound(sessionID: sessionID)
        }
        let normalized = newRoot.resolvingSymlinksInPath().path

        // The target must not be ANOTHER session's registered root.
        let clash = try handle.prepare(
            "SELECT session_id FROM catalog_sessions WHERE root_path = ?")
        try clash.bindText(1, normalized)
        if try clash.step(), let owner = clash.columnText(0), owner != sessionID {
            throw SessionManagementError.rootAlreadyRegistered(rootPath: normalized)
        }

        let update = try handle.prepare(
            "UPDATE catalog_sessions SET root_path = ?, offline = 0 "
                + "WHERE session_id = ?")
        try update.bindText(1, normalized)
        try update.bindText(2, sessionID)
        _ = try update.step()

        // The immediate re-projection (the watermark follows the moved
        // lindex; a still-missing lindex marks offline again honestly).
        return try await project(sessionRoot: newRoot)
    }

    // MARK: - Internals (handle-confined)

    /// Open (creating the directory + file on demand) and apply the frozen
    /// schema. Idempotent; ONLY reachable past the enable guard.
    private func ensureOpen() throws {
        guard handle == nil else { return }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let opened = try SQLiteHandle(path: databaseURL.path)
        handle = opened
        try CatalogIndexSchema.apply(to: opened)
    }

    private func registerSession(
        normalizedRoot: String, root: URL, handle: SQLiteHandle
    ) throws -> String {
        let find = try handle.prepare(
            "SELECT session_id FROM catalog_sessions WHERE root_path = ?")
        try find.bindText(1, normalizedRoot)
        if try find.step(), let existing = find.columnText(0) {
            // Reuse: touch last_seen (the exact-URL-dedupe twin).
            let touch = try handle.prepare(
                "UPDATE catalog_sessions SET last_seen = ? WHERE session_id = ?")
            try touch.bindDouble(1, Date().timeIntervalSince1970)
            try touch.bindText(2, existing)
            _ = try touch.step()
            return existing
        }
        let sessionID = UUID().uuidString
        let insert = try handle.prepare("""
            INSERT INTO catalog_sessions
              (session_id, root_path, display_name, last_projected_epoch,
               last_seen, offline)
            VALUES (?, ?, ?, 0, ?, 0)
            """)
        try insert.bindText(1, sessionID)
        try insert.bindText(2, normalizedRoot)
        try insert.bindText(3, root.lastPathComponent)
        try insert.bindDouble(4, Date().timeIntervalSince1970)
        _ = try insert.step()
        return sessionID
    }

    private func readWatermark(sessionID: String, handle: SQLiteHandle) throws -> Int64 {
        let statement = try handle.prepare(
            "SELECT last_projected_epoch FROM catalog_sessions WHERE session_id = ?")
        try statement.bindText(1, sessionID)
        guard try statement.step() else { return 0 }
        return statement.columnInt(0) ?? 0
    }

    private func readLindexKeys(lindex: SQLiteHandle) throws -> Set<String> {
        let statement = try lindex.prepare("SELECT path FROM images")
        var keys = Set<String>()
        while try statement.step() {
            if let path = statement.columnText(0) { keys.insert(path) }
        }
        return keys
    }

    private func markOffline(normalizedRoot: String, offline: Bool) throws {
        guard let handle else { return }
        let update = try handle.prepare(
            "UPDATE catalog_sessions SET offline = ? WHERE root_path = ?")
        try update.bindInt(1, offline ? 1 : 0)
        try update.bindText(2, normalizedRoot)
        _ = try update.step()
    }

    // MARK: - Frozen spellings

    private enum MirrorColumnType { case text, integer, real }

    /// The 28 mirrored columns AFTER rel_path (the lindex SELECT tail from
    /// offset 2; the UPSERT bind tail from placeholder 3).
    static let mirrorTailColumns: [String] = Array(
        CatalogIndexSchema.mirroredSourceColumns.dropFirst())

    private static let mirrorColumnTypes: [String: MirrorColumnType] = [
        "dir": .text, "filename": .text, "file_size": .integer,
        "file_mtime": .real, "imageID": .text, "sidecar_present": .integer,
        "sidecar_mtime": .real, "has_edits": .integer, "params_hash": .text,
        "layer_count": .integer, "layer_summary": .text, "orientation": .integer,
        "width": .integer, "height": .integer, "capture_date": .real,
        "rating": .integer, "color_label": .integer, "keywords": .text,
        "orphan_sidecar": .integer, "flag": .integer, "note": .text,
        "camera_make": .text, "camera_model": .text, "lens_model": .text,
        "iso": .integer, "focal_length": .real, "aperture": .real,
        "exposure": .real,
    ]

    /// The lindex SELECT list = the 29 mirrored source columns IN ORDER
    /// (path first — mirrors CatalogIndexSchema.mirroredSourceColumns; ONE
    /// spelling shared with the parity test).
    static let lindexSelectColumns = CatalogIndexSchema.mirroredSourceColumns
        .joined(separator: ", ")

    /// The keywords column's position within the lindex SELECT list (the
    /// plain mirroredSourceColumns index — path rides offset 0).
    static let keywordsTailIndex =
        CatalogIndexSchema.mirroredSourceColumns.firstIndex(of: "keywords") ?? 0

    /// The UPSERT (F12 shape): conflict on the composite identity KEEPS the
    /// existing `id` (organization references never dangle, R1) and rewrites
    /// only the mirrored payload. `RETURNING id` feeds the tag re-
    /// materialization without a second round-trip.
    static let upsertSQL: String = {
        // The rename lives HERE (the one `path` -> `rel_path` spelling in
        // the whole projection): identity = session_id + rel_path.
        let insertColumns =
            ["session_id", "rel_path"]
            + CatalogIndexSchema.mirroredSourceColumns.dropFirst()
        let placeholders = Array(repeating: "?", count: insertColumns.count)
            .joined(separator: ", ")
        let updateSet = mirrorTailColumns
            .map { "\($0) = excluded.\($0)" }
            .joined(separator: ", ")
        return """
            INSERT INTO catalog_images (\(insertColumns.joined(separator: ", ")))
            VALUES (\(placeholders))
            ON CONFLICT(session_id, rel_path) DO UPDATE SET \(updateSet)
            RETURNING id
            """
    }()
}
