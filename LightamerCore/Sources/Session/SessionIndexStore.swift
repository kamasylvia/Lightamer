import Foundation
import ImageIO
import os

// ─────────────────────────────────────────────────────────────────────────────
// SessionIndexStore (Plan 09-01 T4; SESS-07 CORE).
//
// The session-level DERIVED CACHE index (the C1 `.cosessiondb` ROLE twin —
// the black-letter SESS-07 contract is "真身恒 sidecar": every row here is
// re-derivable from the filesystem + sidecars; deleting `session.lindex` is
// lossless and triggers a full rebuild on the next open). NOTHING may treat
// a row as parameter authority — 9-3/9-4 consumption re-checks that.
//
// Open-session sync = scan ⊕ DB in ONE transaction (§2.4):
//   added   = scan − db  → INSERT lightweight rows
//   removed = db − scan  → DELETE (+ thumb file cleanup seam)
//   changed = mtime/size drift → UPDATE light columns, stale the thumb,
//             clear the sidecar-summary columns (T5's backfill re-reads)
// then `meta.scan_epoch++` and COMMIT. One bulk change = one transaction —
// the SAME discipline 9-4's batch apply follows.
//
// Orphan-sidecar rows (`.lra` without its original) ride the same
// transaction, keyed by the `.lra` relPath with `orphan_sidecar = 1` —
// classification only, never a hard failure (SC#2; reconcile is 9-2).
// ─────────────────────────────────────────────────────────────────────────────

/// One scanned stat triple (the scanner's output unit; relPath is relative
/// to the session root with POSIX separators — moves with the folder).
public struct SessionScanEntry: Sendable, Equatable {
    public var relPath: String
    public var mtime: TimeInterval
    public var size: Int64

    public init(relPath: String, mtime: TimeInterval, size: Int64) {
        self.relPath = relPath
        self.mtime = mtime
        self.size = size
    }
}

/// One streamed chunk of the walk.
public struct SessionScanPage: Sendable, Equatable {
    public var entries: [SessionScanEntry] = []
    public var orphanSidecarRelPaths: [String] = []

    public init(entries: [SessionScanEntry] = [], orphanSidecarRelPaths: [String] = []) {
        self.entries = entries
        self.orphanSidecarRelPaths = orphanSidecarRelPaths
    }

    public var isEmpty: Bool { entries.isEmpty && orphanSidecarRelPaths.isEmpty }
}

/// Post-sync counts (the App-layer `SessionBrowseCounts` source).
public struct SessionIndexCounts: Sendable, Equatable {
    public var total: Int = 0
    public var edited: Int = 0
    public var orphans: Int = 0

    public init(total: Int = 0, edited: Int = 0, orphans: Int = 0) {
        self.total = total
        self.edited = edited
        self.orphans = orphans
    }
}

/// The `openSession` diff summary + counts + deterministic first image.
public struct SessionIndexOpenResult: Sendable, Equatable {
    public var added = 0
    public var removed = 0
    public var changed = 0
    public var orphanAdded = 0
    public var orphanRemoved = 0
    public var counts = SessionIndexCounts()
    /// Lexicographically-first browsable relPath (the App routes it into
    /// the editor; 9-3's sort UI supersedes the ordering).
    public var firstImageRelPath: String?

    public init() {}
}

/// A full row projection (parity tests + 9-3 queries).
public struct SessionIndexRow: Sendable, Equatable {

    /// Convenience init (the memberwise 25-field form stays internal —
    /// reads construct from SQL; everyone else starts at path).
    public init(path: String) {
        self.path = path
    }

    public var path: String
    public var dir: String?
    public var filename: String?
    public var fileSize: Int64?
    public var fileMtime: Double?
    public var scanEpoch: Int64?
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
    public var thumbState: Int64?
    public var thumbPath: String?
    public var thumbParamsHash: String?
    public var rating: Int64?
    public var colorLabel: Int64?
    public var keywords: String?
    public var orphanSidecar: Int64?
    public var dirty: Int64?
}

/// Failure-injection points for the transaction-atomicity test.
public enum SessionIndexSyncFailureInjection: String, Sendable, CaseIterable {
    case none
    /// Throw AFTER the added INSERTs, before the removed DELETEs.
    case afterAdded
    /// Throw AFTER all mutations, before COMMIT.
    case beforeCommit
}

public actor SessionIndexStore {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "session-index"
    )

    private var handle: SQLiteHandle?
    private let databaseURL: URL

    /// Test seam: mid-sync failure injection (the ROLLBACK atomicity test).
    private var failureInjection: SessionIndexSyncFailureInjection = .none

    /// Open a store against a session root WITHOUT syncing (tests /
    /// re-open paths). `openSession(root:scan:)` is the full flow.
    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    /// Canonical `<root>/.lightamer/session.lindex` positioning.
    public init(sessionRoot: URL) {
        self.databaseURL = SessionIndexSchema.databaseURL(forSessionRoot: sessionRoot)
    }

    public func setFailureInjection(_ mode: SessionIndexSyncFailureInjection) {
        failureInjection = mode
    }

    public var isClosed: Bool { handle == nil }

    // MARK: - Open + incremental sync (SESS-07)

    /// Open (creating `.lightamer/session.lindex` on demand), apply the
    /// frozen schema, consume the scan stream, apply the diff in ONE
    /// transaction, bump the epoch, and publish counts + first image.
    public func openSession(
        root: URL, scan: AsyncStream<SessionScanPage>
    ) async throws -> SessionIndexOpenResult {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let opened = try SQLiteHandle(path: databaseURL.path)
        handle = opened
        try SessionIndexSchema.apply(to: opened)

        // Consume the scan stream (progressive ingest seam — 9-3 observes
        // pages for the grid while the sync collects).
        var scanEntries: [String: SessionScanEntry] = [:]
        var scanOrphans = Set<String>()
        for await page in scan {
            for entry in page.entries {
                scanEntries[entry.relPath] = entry
            }
            for orphan in page.orphanSidecarRelPaths {
                scanOrphans.insert(orphan)
            }
        }

        var result = try sync(
            scanEntries: scanEntries, scanOrphans: scanOrphans,
            renames: [], rootPath: root.path, handle: opened
        )

        // ⑤ sidecar summary backfill (T5): every row pending a sidecar
        // read (added + drift-cleared + degraded-retry) gets its
        // imageID/has_edits/params_hash/layer summary — the SIDECAR is the
        // authority; the row is a cache. Then the EXIF light columns
        // (ImageIO properties — metadata only, never a full decode).
        // Execution decision: both legs run here (deterministic for the
        // sidebar counts); 9-3 may decouple them to background for the
        // grid's first paint.
        try await backfillSidecarSummaries(rootPath: root.path)
        try await backfillExifMetadata(rootPath: root.path)
        // 09-04 T4 crash-self-heal leg: dirty rows re-read their DISK
        // sidecars and the index is overwritten from them (真身恒 sidecar;
        // the D-09-CONTEXT-4 contract's recovery half).
        try await healDirtyRows(rootPath: root.path)

        result.counts = try computeCounts(handle: opened)
        result.firstImageRelPath = try firstBrowsableRelPath(handle: opened)
        return result
    }

    /// The reconcile apply leg (Plan 09-02 T1/T3): the SAME single-
    /// transaction incremental sync as `openSession` (⑨-① discipline — one
    /// bulk change = one transaction) plus the pure diff's rename-survival
    /// rulings, WITHOUT the reopen side effects. Reopens the handle
    /// idempotently when the session was closed (a reconcile after a
    /// teardown must not crash — it reopens and re-syncs).
    ///
    /// The sidecar/EXIF backfills re-run afterwards (NULL-class targeted —
    /// only pending rows pay I/O), so drift-cleared rows and rename
    /// destinations re-read their sidecars (真身恒 sidecar).
    @discardableResult
    public func reconcile(
        root: URL,
        scan: AsyncStream<SessionScanPage>,
        renames: [SessionReconcileRename] = []
    ) async throws -> SessionIndexOpenResult {
        if handle == nil {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let reopened = try SQLiteHandle(path: databaseURL.path)
            handle = reopened
            try SessionIndexSchema.apply(to: reopened)
        }
        guard let opened = handle else {
            throw SessionIndexError.execFailed(
                sql: "reconcile", code: 0, message: "store handle unavailable"
            )
        }

        var scanEntries: [String: SessionScanEntry] = [:]
        var scanOrphans = Set<String>()
        for await page in scan {
            for entry in page.entries {
                scanEntries[entry.relPath] = entry
            }
            for orphan in page.orphanSidecarRelPaths {
                scanOrphans.insert(orphan)
            }
        }

        var result = try sync(
            scanEntries: scanEntries, scanOrphans: scanOrphans,
            renames: renames, rootPath: root.path, handle: opened
        )
        try await backfillSidecarSummaries(rootPath: root.path)
        try await backfillExifMetadata(rootPath: root.path)
        result.counts = try computeCounts(handle: opened)
        return result
    }

    /// The diff + single transaction. Internal so tests can drive it.
    /// `renames` (Plan 09-02) carries the pure diff's rename-survival
    /// rulings: each pair UPDATES the row's path columns in place — the row
    /// and every backfilled column SURVIVE the move (delete+insert would
    /// discard them) — before the added/removed/changed legs run against the
    /// adjusted map.
    func sync(
        scanEntries: [String: SessionScanEntry],
        scanOrphans: Set<String>,
        renames: [SessionReconcileRename] = [],
        rootPath: String,
        handle: SQLiteHandle
    ) throws -> SessionIndexOpenResult {
        var result = SessionIndexOpenResult()
        result.counts = SessionIndexCounts()

        try handle.exec("BEGIN IMMEDIATE")
        do {
            let epoch = try SessionIndexSchema.readScanEpoch(from: handle) + 1

            // ── Read the DB side: path → (mtime, size), split by orphan flag.
            var dbImages: [String: (mtime: Double, size: Int64)] = [:]
            var dbOrphans = Set<String>()
            let rows = try handle.prepare(
                "SELECT path, file_mtime, file_size, orphan_sidecar FROM images"
            )
            while try rows.step() {
                guard let path = rows.columnText(0) else { continue }
                let orphan = rows.columnInt(3) ?? 0
                if orphan == 1 {
                    dbOrphans.insert(path)
                } else {
                    dbImages[path] = (rows.columnDouble(1) ?? 0, rows.columnInt(2) ?? 0)
                }
            }

            // ── Rename-survival pre-pass (Plan 09-02 T1): each ruled pair
            // becomes a path UPDATE — the row's backfilled columns
            // (imageID/has_edits/params_hash/layer summary/rating) SURVIVE
            // the move. The in-memory map is adjusted so the legs below do
            // NOT re-add the destination or re-delete the source. The pure
            // diff guarantees `toPath` is not already indexed; the guard is
            // defensive only. thumb_path intentionally stays the OLD
            // pathhash (the thumb content is unchanged; the 9-3 cache
            // regenerates on its own path-keyed miss — 09-02-DECISIONS).
            if !renames.isEmpty {
                let renameUpdate = try handle.prepare("""
                    UPDATE images SET
                      path = ?, dir = ?, filename = ?, file_size = ?,
                      file_mtime = ?, scan_epoch = ?, sidecar_present = ?
                    WHERE path = ?
                    """)
                for rename in renames {
                    guard
                        let stat = scanEntries[rename.toPath],
                        dbImages[rename.fromPath] != nil,
                        dbImages[rename.toPath] == nil
                    else { continue }
                    let sidecarPresent = FileManager.default.fileExists(
                        atPath: rootPath + "/" + rename.toPath + ".lra"
                    )
                    let directory = (rename.toPath as NSString).deletingLastPathComponent
                    try renameUpdate.bindText(1, rename.toPath)
                    try renameUpdate.bindText(2, directory.isEmpty ? nil : directory)
                    try renameUpdate.bindText(
                        3, (rename.toPath as NSString).lastPathComponent
                    )
                    try renameUpdate.bindInt(4, stat.size)
                    try renameUpdate.bindDouble(5, stat.mtime)
                    try renameUpdate.bindInt(6, epoch)
                    try renameUpdate.bindInt(7, sidecarPresent ? 1 : 0)
                    try renameUpdate.bindText(8, rename.fromPath)
                    _ = try renameUpdate.step()
                    try renameUpdate.reset()
                    // The destination row is exactly what a fresh scan says.
                    dbImages[rename.toPath] = (stat.mtime, stat.size)
                    dbImages[rename.fromPath] = nil
                }
            }

            // ── added (INSERT lightweight rows)
            let insert = try handle.prepare("""
                INSERT INTO images (
                  path, dir, filename, file_size, file_mtime, scan_epoch,
                  sidecar_present, orphan_sidecar, dirty
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0)
                """)
            for (rel, entry) in scanEntries where dbImages[rel] == nil {
                let dir = (rel as NSString).deletingLastPathComponent
                let filename = (rel as NSString).lastPathComponent
                try insert.bindText(1, rel)
                try insert.bindText(2, dir.isEmpty ? nil : dir)
                try insert.bindText(3, filename)
                try insert.bindInt(4, entry.size)
                try insert.bindDouble(5, entry.mtime)
                try insert.bindInt(6, epoch)
                // sidecar presence is a cheap stat at insert time (the T5
                // backfill reads the CONTENT later).
                let sidecarPresent = FileManager.default.fileExists(
                    atPath: rootPath + "/" + rel + ".lra"
                )
                try insert.bindInt(7, sidecarPresent ? 1 : 0)
                _ = try insert.step()
                try insert.reset()
                result.added += 1
            }

            if failureInjection == .afterAdded {
                throw SessionIndexError.execFailed(
                    sql: "test-injection(afterAdded)", code: 1, message: "injected"
                )
            }

            // ── removed (thumb cleanup seam FIRST — the thumb_path must be
            // read before the rows are gone — then DELETE)
            let removedKeys = dbImages.keys.filter { scanEntries[$0] == nil }
            cleanupThumbFiles(for: removedKeys, handle: handle)
            let delete = try handle.prepare("DELETE FROM images WHERE path = ?")
            for rel in removedKeys {
                try delete.bindText(1, rel)
                _ = try delete.step()
                try delete.reset()
                result.removed += 1
            }

            // ── changed (mtime/size drift → UPDATE + stale + sidecar re-read)
            let changeUpdate = try handle.prepare("""
                UPDATE images SET
                  file_size = ?, file_mtime = ?, scan_epoch = ?,
                  sidecar_present = ?, sidecar_mtime = NULL,
                  imageID = NULL, has_edits = NULL, params_hash = NULL,
                  layer_count = NULL, layer_summary = NULL,
                  thumb_state = CASE WHEN thumb_state = 0 THEN 0 ELSE ? END
                WHERE path = ?
                """)
            for (rel, entry) in scanEntries {
                guard let existing = dbImages[rel] else { continue }
                guard existing.mtime != entry.mtime || existing.size != entry.size else {
                    continue
                }
                let sidecarExists = FileManager.default.fileExists(
                    atPath: rootPath + "/" + rel + ".lra"
                )
                try changeUpdate.bindInt(1, entry.size)
                try changeUpdate.bindDouble(2, entry.mtime)
                try changeUpdate.bindInt(3, epoch)
                try changeUpdate.bindInt(4, sidecarExists ? 1 : 0)
                try changeUpdate.bindInt(
                    5, SessionIndexSchema.ThumbState.stale.rawValue
                )
                try changeUpdate.bindText(6, rel)
                _ = try changeUpdate.step()
                try changeUpdate.reset()
                result.changed += 1
            }

            // Touch every surviving row's epoch (cheapest form: bulk UPDATE).
            let epochUpdate = try handle.prepare(
                "UPDATE images SET scan_epoch = ? WHERE scan_epoch < ?"
            )
            try epochUpdate.bindInt(1, epoch)
            try epochUpdate.bindInt(2, epoch)
            _ = try epochUpdate.step()

            // ── orphan rows (classification rows keyed by the .lra relPath)
            let insertOrphan = try handle.prepare("""
                INSERT OR REPLACE INTO images (
                  path, filename, scan_epoch, orphan_sidecar, dirty
                ) VALUES (?, ?, ?, 1, 0)
                """)
            for orphan in scanOrphans where !dbOrphans.contains(orphan) {
                let filename = (orphan as NSString).lastPathComponent
                try insertOrphan.bindText(1, orphan)
                try insertOrphan.bindText(2, filename)
                try insertOrphan.bindInt(3, epoch)
                _ = try insertOrphan.step()
                try insertOrphan.reset()
                result.orphanAdded += 1
            }
            let deleteOrphan = try handle.prepare(
                "DELETE FROM images WHERE path = ? AND orphan_sidecar = 1"
            )
            for orphan in dbOrphans where !scanOrphans.contains(orphan) {
                try deleteOrphan.bindText(1, orphan)
                _ = try deleteOrphan.step()
                try deleteOrphan.reset()
                result.orphanRemoved += 1
            }

            // ── epoch bump (meta)
            let metaUpdate = try handle.prepare(
                "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)"
            )
            try metaUpdate.bindText(1, SessionIndexSchema.MetaKey.scanEpoch)
            try metaUpdate.bindText(2, String(epoch))
            _ = try metaUpdate.step()

            if failureInjection == .beforeCommit {
                throw SessionIndexError.execFailed(
                    sql: "test-injection(beforeCommit)", code: 1, message: "injected"
                )
            }

            try handle.exec("COMMIT")
        } catch {
            // ONE bulk change = ONE transaction: any failure rolls the
            // whole diff back — the row set is exactly as before.
            try? handle.exec("ROLLBACK")
            result.counts = SessionIndexCounts()
            throw error
        }
        return result
    }

    /// Delete thumb files of removed rows (the 9-3 disk cache lands later;
    /// the seam already honors `thumb_path` so deletions never leak files).
    private func cleanupThumbFiles(for relPaths: [String], handle: SQLiteHandle) {
        guard !relPaths.isEmpty else { return }
        let statement = try? handle.prepare(
            "SELECT thumb_path FROM images WHERE path = ? AND thumb_path IS NOT NULL"
        )
        guard let statement else { return }
        for rel in relPaths {
            try? statement.bindText(1, rel)
            if (try? statement.step()) == true,
               let thumbPath = statement.columnText(0) {
                try? FileManager.default.removeItem(atPath: thumbPath)
            }
            try? statement.reset()
        }
    }

    // MARK: - Queries

    private func computeCounts(handle: SQLiteHandle) throws -> SessionIndexCounts {
        let statement = try handle.prepare("""
            SELECT
              COALESCE(SUM(orphan_sidecar = 0), 0),
              COALESCE(SUM(orphan_sidecar = 0 AND has_edits = 1), 0),
              COALESCE(SUM(orphan_sidecar = 1), 0)
            FROM images
            """)
        var counts = SessionIndexCounts()
        if try statement.step() {
            counts.total = Int(statement.columnInt(0) ?? 0)
            counts.edited = Int(statement.columnInt(1) ?? 0)
            counts.orphans = Int(statement.columnInt(2) ?? 0)
        }
        return counts
    }

    private func firstBrowsableRelPath(handle: SQLiteHandle) throws -> String? {
        let statement = try handle.prepare(
            "SELECT path FROM images WHERE orphan_sidecar = 0 ORDER BY path LIMIT 1"
        )
        return try statement.step() ? statement.columnText(0) : nil
    }

    /// Full row read (tests + parity).
    public func fetchAllRows() throws -> [SessionIndexRow] {
        guard let handle else { return [] }
        let statement = try handle.prepare("""
            SELECT path, dir, filename, file_size, file_mtime, scan_epoch,
                   imageID, sidecar_present, sidecar_mtime, has_edits,
                   params_hash, layer_count, layer_summary, orientation,
                   width, height, capture_date, thumb_state, thumb_path,
                   thumb_params_hash, rating, color_label, keywords,
                   orphan_sidecar, dirty
            FROM images ORDER BY path
            """)
        var rows: [SessionIndexRow] = []
        while try statement.step() {
            var row = SessionIndexRow(path: statement.columnText(0) ?? "")
            row.dir = statement.columnText(1)
            row.filename = statement.columnText(2)
            row.fileSize = statement.columnInt(3)
            row.fileMtime = statement.columnDouble(4)
            row.scanEpoch = statement.columnInt(5)
            row.imageID = statement.columnText(6)
            row.sidecarPresent = statement.columnInt(7)
            row.sidecarMtime = statement.columnDouble(8)
            row.hasEdits = statement.columnInt(9)
            row.paramsHash = statement.columnText(10)
            row.layerCount = statement.columnInt(11)
            row.layerSummary = statement.columnText(12)
            row.orientation = statement.columnInt(13)
            row.width = statement.columnInt(14)
            row.height = statement.columnInt(15)
            row.captureDate = statement.columnDouble(16)
            row.thumbState = statement.columnInt(17)
            row.thumbPath = statement.columnText(18)
            row.thumbParamsHash = statement.columnText(19)
            row.rating = statement.columnInt(20)
            row.colorLabel = statement.columnInt(21)
            row.keywords = statement.columnText(22)
            row.orphanSidecar = statement.columnInt(23)
            row.dirty = statement.columnInt(24)
            rows.append(row)
        }
        return rows
    }

    /// Single-row read (Plan 09-03 T3 — the provider's fetch path).
    public func fetchRow(relPath: String) throws -> SessionIndexRow? {
        guard let handle else { return nil }
        let statement = try handle.prepare("""
            SELECT path, dir, filename, file_size, file_mtime, scan_epoch,
                   imageID, sidecar_present, sidecar_mtime, has_edits,
                   params_hash, layer_count, layer_summary, orientation,
                   width, height, capture_date, thumb_state, thumb_path,
                   thumb_params_hash, rating, color_label, keywords,
                   orphan_sidecar, dirty
            FROM images WHERE path = ?
            """)
        try statement.bindText(1, relPath)
        guard try statement.step() else { return nil }
        var row = SessionIndexRow(path: statement.columnText(0) ?? "")
        row.dir = statement.columnText(1)
        row.filename = statement.columnText(2)
        row.fileSize = statement.columnInt(3)
        row.fileMtime = statement.columnDouble(4)
        row.scanEpoch = statement.columnInt(5)
        row.imageID = statement.columnText(6)
        row.sidecarPresent = statement.columnInt(7)
        row.sidecarMtime = statement.columnDouble(8)
        row.hasEdits = statement.columnInt(9)
        row.paramsHash = statement.columnText(10)
        row.layerCount = statement.columnInt(11)
        row.layerSummary = statement.columnText(12)
        row.orientation = statement.columnInt(13)
        row.width = statement.columnInt(14)
        row.height = statement.columnInt(15)
        row.captureDate = statement.columnDouble(16)
        row.thumbState = statement.columnInt(17)
        row.thumbPath = statement.columnText(18)
        row.thumbParamsHash = statement.columnText(19)
        row.rating = statement.columnInt(20)
        row.colorLabel = statement.columnInt(21)
        row.keywords = statement.columnText(22)
        row.orphanSidecar = statement.columnInt(23)
        row.dirty = statement.columnInt(24)
        return row
    }

    public func counts() throws -> SessionIndexCounts {
        guard let handle else { return SessionIndexCounts() }
        return try computeCounts(handle: handle)
    }

    // MARK: - Sidecar summary backfill (T5)

    /// Pending sidecar rows = sidecar_present = 1 AND a NULL summary column
    /// (added pristine-with-sidecar rows, drift-cleared rows, and degraded
    /// rows from earlier passes — the NULL class is ALSO the retry class).
    /// Decodes each `.lra` (the AUTHORITY), then applies ALL updates in ONE
    /// transaction. Decode failures are logged and left NULL (degraded,
    /// retried next open) — never a hard failure.
    ///
    /// `has_edits` = `history.position >= 0` (the Phase 8 handoff-④
    /// semantic: yiyin borders/watermark instances are history items, so
    /// they flow through has_edits/params_hash with ZERO special-casing).
    @discardableResult
    public func backfillSidecarSummaries(rootPath: String) async throws -> Int {
        guard let handle else { return 0 }
        // TWO pending classes: ① NULL summary columns (added / drift-cleared
        // / degraded-retry), ② sidecar MTIME DRIFT — the image's stat triple
        // is unchanged but the `.lra` was (re)written underneath us; the
        // sidecar is the AUTHORITY, so the row re-reads (真身恒 sidecar).
        var work: [(path: String, sidecar: String)] = []
        let nullPending = try handle.prepare("""
            SELECT path FROM images
            WHERE orphan_sidecar = 0 AND sidecar_present = 1
              AND (params_hash IS NULL OR imageID IS NULL OR has_edits IS NULL)
            """)
        var seen = Set<String>()
        while try nullPending.step() {
            guard let rel = nullPending.columnText(0) else { continue }
            work.append((rel, rootPath + "/" + rel + ".lra"))
            seen.insert(rel)
        }
        let allWithSidecar = try handle.prepare(
            "SELECT path, sidecar_mtime FROM images WHERE orphan_sidecar = 0 AND sidecar_present = 1"
        )
        while try allWithSidecar.step() {
            guard let rel = allWithSidecar.columnText(0) else { continue }
            guard !seen.contains(rel) else { continue }
            let sidecar = rootPath + "/" + rel + ".lra"
            let currentMtime = (try? FileManager.default.attributesOfItem(
                atPath: sidecar
            ))?[.modificationDate] as? Date
            if currentMtime?.timeIntervalSince1970
                != allWithSidecar.columnDouble(1) {
                work.append((rel, sidecar))
                seen.insert(rel)
            }
        }
        guard !work.isEmpty else { return 0 }

        // Decode OUTSIDE the transaction (file I/O must not hold the write
        // lock); batch the updates into ONE transaction afterwards.
        struct Summary {
            var imageID: String
            var hasEdits: Int64
            var paramsHash: String
            var layerCount: Int64?
            var layerSummary: String?
            var sidecarMtime: Double
        }
        var summaries: [String: Summary] = [:]
        let decoder = JSONDecoder()
        for item in work {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: item.sidecar)) else {
                Self.logger.warning(
                    "sidecar unreadable mid-flight: \(item.sidecar, privacy: .public)"
                )
                continue
            }
            do {
                let document = try decoder.decode(LightamerSidecar.self, from: data)
                let mtime = (try? FileManager.default.attributesOfItem(
                    atPath: item.sidecar
                ))?[.modificationDate] as? Date
                let layerSummary = document.layerStack.map(Self.layerSummaryJSON)
                summaries[item.path] = Summary(
                    imageID: document.imageID.uuidString,
                    hasEdits: document.history.position >= 0 ? 1 : 0,
                    paramsHash: String(document.historyHash), // L013 decimal TEXT
                    layerCount: document.layerStack.map { Int64($0.layers.count) },
                    layerSummary: layerSummary,
                    sidecarMtime: mtime?.timeIntervalSince1970 ?? 0
                )
            } catch {
                // DEGRADED: leave the row in the NULL class (retried next
                // open); log only — SC#2 gracefully.
                Self.logger.error(
                    "sidecar decode failed (degraded): \(item.sidecar, privacy: .public) — \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        guard !summaries.isEmpty else { return 0 }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            let update = try handle.prepare("""
                UPDATE images SET
                  imageID = ?, has_edits = ?, params_hash = ?,
                  layer_count = ?, layer_summary = ?, sidecar_mtime = ?
                WHERE path = ?
                """)
            for (rel, summary) in summaries {
                try update.bindText(1, summary.imageID)
                try update.bindInt(2, summary.hasEdits)
                try update.bindText(3, summary.paramsHash)
                try update.bindInt(4, summary.layerCount)
                try update.bindText(5, summary.layerSummary)
                try update.bindDouble(6, summary.sidecarMtime)
                try update.bindText(7, rel)
                _ = try update.step()
                try update.reset()
            }
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
        return summaries.count
    }

    /// The frozen layer-summary JSON spelling (execution decision, recorded
    /// in 09-01-DECISIONS): `[{"blend":Int,"name":String,"visible":Bool}]`
    /// — sortedKeys for stability.
    static func layerSummaryJSON(_ stack: SidecarLayerStackRecord) -> String {
        struct Entry: Codable, Sendable {
            var name: String
            var blend: Int
            var visible: Bool
        }
        let entries = stack.layers.map {
            Entry(name: $0.name, blend: $0.blendMode, visible: $0.isVisible)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entries) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - EXIF light columns (T5)

    /// Orientation/width/height/capture_date via ImageIO PROPERTIES only
    /// (`CGImageSourceCopyPropertiesAtIndex` — metadata read, never a full
    /// decode). One batched transaction for all filled rows.
    @discardableResult
    public func backfillExifMetadata(rootPath: String) async throws -> Int {
        guard let handle else { return 0 }
        let pending = try handle.prepare("""
            SELECT path FROM images
            WHERE orphan_sidecar = 0 AND orientation IS NULL
            """)
        var work: [(path: String, absolute: String)] = []
        while try pending.step() {
            guard let rel = pending.columnText(0) else { continue }
            work.append((rel, rootPath + "/" + rel))
        }
        guard !work.isEmpty else { return 0 }

        struct Exif {
            var orientation: Int64
            var width: Int64
            var height: Int64
            var captureDate: Double?
        }
        var filled: [String: Exif] = [:]
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        for item in work {
            guard let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: item.absolute) as CFURL, sourceOptions
            ) else { continue }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(
                source, 0, sourceOptions
            ) as? [CFString: Any] else { continue }
            let width = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
            let height = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
            guard width > 0, height > 0 else { continue }
            let orientation = (properties[kCGImagePropertyOrientation] as? Int) ?? 1

            var captureDate: Double?
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                captureDate = Self.parseEXIFDate(raw)?.timeIntervalSince1970
            }
            if captureDate == nil,
               let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let raw = tiff[kCGImagePropertyTIFFDateTime] as? String {
                captureDate = Self.parseEXIFDate(raw)?.timeIntervalSince1970
            }

            filled[item.path] = Exif(
                orientation: Int64(orientation),
                width: Int64(width), height: Int64(height),
                captureDate: captureDate
            )
        }
        guard !filled.isEmpty else { return 0 }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            let update = try handle.prepare("""
                UPDATE images SET orientation = ?, width = ?, height = ?, capture_date = ?
                WHERE path = ?
                """)
            for (rel, exif) in filled {
                try update.bindInt(1, exif.orientation)
                try update.bindInt(2, exif.width)
                try update.bindInt(3, exif.height)
                try update.bindDouble(4, exif.captureDate)
                try update.bindText(5, rel)
                _ = try update.step()
                try update.reset()
            }
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
        return filled.count
    }

    /// EXIF datetime format `yyyy:MM:dd HH:mm:ss` (strict) — nil otherwise.
    static func parseEXIFDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC") // EXIF has no zone; pin UTC deterministically
        return formatter.date(from: raw)
    }

    // MARK: - Bulk stale-mark (the 9-4 segment-2 shape; T6 timing)

    /// PERF-07 segment-2 REHEARSAL: 10k-row single-transaction UPDATE via
    /// a temp-table join (mark everything thumb-stale + dirty). Returns
    /// the wall-clock seconds of the whole transaction — the number the
    /// 万张 ≤5s gate premise rests on (recorded in .work/09/perf.md).
    public func bulkApplyStaleMarkForTesting() async throws -> Double {
        guard let handle else { return 0 }
        let clock = ContinuousClock()
        let start = clock.now
        try handle.exec("BEGIN IMMEDIATE")
        do {
            try handle.exec(
                "CREATE TEMP TABLE IF NOT EXISTS bulk_paths (path TEXT PRIMARY KEY)"
            )
            try handle.exec("DELETE FROM bulk_paths")
            let insert = try handle.prepare("INSERT INTO bulk_paths (path) VALUES (?)")
            let rows = try handle.prepare("SELECT path FROM images WHERE orphan_sidecar = 0")
            while try rows.step() {
                if let path = rows.columnText(0) {
                    try insert.bindText(1, path)
                    _ = try insert.step()
                    try insert.reset()
                }
            }
            let update = try handle.prepare(
                "UPDATE images SET thumb_state = ?, dirty = 1 "
                    + "WHERE path IN (SELECT path FROM bulk_paths)"
            )
            try update.bindInt(1, SessionIndexSchema.ThumbState.stale.rawValue)
            _ = try update.step()
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
    }

    // MARK: - Batch apply (Plan 09-04 T3/T4; PERF-07 segment 2)

    /// One segment-2 claim row (the composed document's index projection).
    public struct BatchApplyClaim: Sendable {
        public var relPath: String
        /// The NEW history hash (L013 decimal TEXT) —「待生效」until the
        /// writer clears the dirty flag (the row's parameters are claimed,
        /// the disk sidecar lags behind).
        public var paramsHash: String
        public var hasEdits: Int64
        public var layerCount: Int64?
        public var layerSummary: String?

        public init(
            relPath: String, paramsHash: String, hasEdits: Int64,
            layerCount: Int64?, layerSummary: String?
        ) {
            self.relPath = relPath
            self.paramsHash = paramsHash
            self.hasEdits = hasEdits
            self.layerCount = layerCount
            self.layerSummary = layerSummary
        }
    }

    /// 段2 (the PERF-07 gate body): claim the new state for ALL targets in
    /// ONE transaction — params_hash / has_edits / layer summary / dirty=1
    /// + thumb stale (state 0 stays 0: nothing rendered yet, nothing to
    /// stale — the markRowsStale guard). 10k rows = one txn (the 9-1
    /// discipline). Any failure rolls the WHOLE claim back.
    ///
    /// PERF-07 probe finding (09-04 T5): the values are PER-ROW, so the
    /// write is a prepared `WHERE path = ?` PK-seek executed 10k× inside
    /// the one txn (~10ms) — NOT a `WHERE path IN (SELECT …)` bulk form
    /// re-executed per row (that re-scans `images` per execution: O(n²),
    /// measured 77s @10k).
    public func claimBatchApply(claims: [BatchApplyClaim]) async throws {
        guard let handle, !claims.isEmpty else { return }
        try handle.exec("BEGIN IMMEDIATE")
        do {
            let update = try handle.prepare("""
                UPDATE images SET
                  params_hash = ?, has_edits = ?, layer_count = ?,
                  layer_summary = ?,
                  thumb_state = CASE WHEN thumb_state = 0 THEN 0 ELSE ? END,
                  dirty = 1
                WHERE path = ? AND orphan_sidecar = 0
                """)
            for claim in claims {
                try update.bindText(1, claim.paramsHash)
                try update.bindInt(2, claim.hasEdits)
                try update.bindInt(3, claim.layerCount)
                try update.bindText(4, claim.layerSummary)
                try update.bindInt(5, SessionIndexSchema.ThumbState.stale.rawValue)
                try update.bindText(6, claim.relPath)
                _ = try update.step()
                try update.reset()
            }
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// 段3's write-back: clear ONE row's dirty flag after its sidecar
    /// promotion (an independent small transaction — the badge lifts per
    /// image as the drain proceeds).
    public func clearBatchDirty(relPath: String) async throws {
        guard let handle else { return }
        try handle.exec("BEGIN IMMEDIATE")
        do {
            let update = try handle.prepare(
                "UPDATE images SET dirty = 0 WHERE path = ?")
            try update.bindText(1, relPath)
            _ = try update.step()
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// The crash-self-heal leg (D-09-CONTEXT-4; rides the 9-1 open sync):
    /// every DIRTY row re-reads its DISK SIDECAR (the truth) and the index
    /// columns are overwritten from it; readable → dirty=0 + the full
    /// summary refresh; unreadable/absent → the row stays dirty (the badge
    /// keeps telling the truth; the next reconcile rules). ALL updates in
    /// ONE transaction. Returns the healed count.
    @discardableResult
    public func healDirtyRows(rootPath: String) async throws -> Int {
        guard let handle else { return 0 }
        var work: [(relPath: String, sidecar: String)] = []
        let pending = try handle.prepare(
            "SELECT path FROM images WHERE dirty = 1 AND orphan_sidecar = 0")
        while try pending.step() {
            guard let rel = pending.columnText(0) else { continue }
            work.append((rel, rootPath + "/" + rel + ".lra"))
        }
        guard !work.isEmpty else { return 0 }

        struct Healed {
            var imageID: String
            var hasEdits: Int64
            var paramsHash: String
            var layerCount: Int64?
            var layerSummary: String?
            var sidecarMtime: Double
        }
        var healed: [String: Healed] = [:]
        let decoder = JSONDecoder()
        for item in work {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: item.sidecar)),
                  let document = try? decoder.decode(LightamerSidecar.self, from: data)
            else {
                // Unreadable/absent sidecar: leave the row dirty (the badge
                // stays honest); the reconcile sweep rules eventually.
                continue
            }
            let mtime = (try? FileManager.default.attributesOfItem(
                atPath: item.sidecar))?[.modificationDate] as? Date
            healed[item.relPath] = Healed(
                imageID: document.imageID.uuidString,
                hasEdits: document.history.position >= 0 ? 1 : 0,
                paramsHash: String(document.historyHash),
                layerCount: document.layerStack.map { Int64($0.layers.count) },
                layerSummary: document.layerStack.map(Self.layerSummaryJSON),
                sidecarMtime: mtime?.timeIntervalSince1970 ?? 0)
        }
        guard !healed.isEmpty else { return 0 }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            let update = try handle.prepare("""
                UPDATE images SET
                  imageID = ?, has_edits = ?, params_hash = ?,
                  layer_count = ?, layer_summary = ?, sidecar_mtime = ?,
                  dirty = 0
                WHERE path = ?
                """)
            for (rel, summary) in healed {
                try update.bindText(1, summary.imageID)
                try update.bindInt(2, summary.hasEdits)
                try update.bindText(3, summary.paramsHash)
                try update.bindInt(4, summary.layerCount)
                try update.bindText(5, summary.layerSummary)
                try update.bindDouble(6, summary.sidecarMtime)
                try update.bindText(7, rel)
                _ = try update.step()
                try update.reset()
            }
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
        return healed.count
    }

    // MARK: - Orphan sidecar actions (Plan 09-02 T4; SC#2 "gracefully")

    /// The meta-table key prefix for IGNORED orphan rows. The v1 image
    /// schema is FROZEN (09-01) — the ignore flag persists WITHOUT a
    /// migration through the meta KV store (`orphanIgnore/<relPath>`).
    public static let orphanIgnoreKeyPrefix = "orphanIgnore/"

    /// REMOVE: delete the `.lra` file FIRST (the disk truth leads), then
    /// clear the classification row in one transaction. If the file
    /// removal fails, the row stays — the state never lies. Returns false
    /// on any failure instead of throwing (orphan handling NEVER hard-fails
    /// into the UI; SC#2).
    @discardableResult
    public func removeOrphanSidecar(root: URL, relPath: String) async -> Bool {
        guard relPath.hasSuffix(".lra") else { return false }
        let sidecarURL = root.appendingPathComponent(relPath)
        guard (try? FileManager.default.removeItem(at: sidecarURL)) != nil,
              !FileManager.default.fileExists(atPath: sidecarURL.path)
        else { return false }

        if let handle {
            do {
                try handle.exec("BEGIN IMMEDIATE")
                let delete = try handle.prepare(
                    "DELETE FROM images WHERE path = ? AND orphan_sidecar = 1"
                )
                try delete.bindText(1, relPath)
                _ = try delete.step()
                let forget = try handle.prepare("DELETE FROM meta WHERE key = ?")
                try forget.bindText(1, Self.orphanIgnoreKeyPrefix + relPath)
                _ = try forget.step()
                try handle.exec("COMMIT")
            } catch {
                try? handle.exec("ROLLBACK")
                // The file is gone; the row is swept by the next reconcile's
                // orphan leg — never a hard failure.
                return true
            }
        }
        return true
    }

    /// IGNORE: persist the row-level ignore flag (meta KV — no schema
    /// migration). The row itself STAYS (a stable classification record);
    /// the UI filters it out of the actionable list.
    public func setOrphanIgnored(relPath: String, ignored: Bool) async {
        guard let handle else { return }
        do {
            try handle.exec("BEGIN IMMEDIATE")
            if ignored {
                let insert = try handle.prepare(
                    "INSERT OR REPLACE INTO meta (key, value) VALUES (?, '1')"
                )
                try insert.bindText(1, Self.orphanIgnoreKeyPrefix + relPath)
                _ = try insert.step()
            } else {
                let delete = try handle.prepare("DELETE FROM meta WHERE key = ?")
                try delete.bindText(1, Self.orphanIgnoreKeyPrefix + relPath)
                _ = try delete.step()
            }
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
        }
    }

    /// The ignored orphan relPaths (the UI filter input).
    public func ignoredOrphanRelPaths() async -> Set<String> {
        guard let handle else { return [] }
        do {
            let statement = try handle.prepare(
                "SELECT key FROM meta WHERE key LIKE ?"
            )
            try statement.bindText(
                1, Self.orphanIgnoreKeyPrefix + "%"
            )
            var ignored = Set<String>()
            while try statement.step() {
                guard let key = statement.columnText(0) else { continue }
                ignored.insert(String(key.dropFirst(Self.orphanIgnoreKeyPrefix.count)))
            }
            return ignored
        } catch {
            return []
        }
    }

    /// The current orphan relPaths MINUS the ignored ones (the App
    /// snapshot's source; sorted for stable UI ids).
    public func actionableOrphanRelPaths() async -> [String] {
        guard let handle else { return [] }
        let ignored = await ignoredOrphanRelPaths()
        do {
            let statement = try handle.prepare(
                "SELECT path FROM images WHERE orphan_sidecar = 1 ORDER BY path"
            )
            var orphans: [String] = []
            while try statement.step() {
                guard let rel = statement.columnText(0), !ignored.contains(rel)
                else { continue }
                orphans.append(rel)
            }
            return orphans
        } catch {
            return []
        }
    }

    // MARK: - Row-level stale hint (Plan 09-02 T3)

    /// Mark the named rows thumb-stale (the FSEvents hint leg). Rows are
    /// NEVER deleted here — a rename's old-path event is untrustworthy;
    /// the reconcile diff's stat ruling decides removals. `thumb_state = 0`
    /// rows stay 0 (nothing rendered yet → nothing to stale). One
    /// transaction; returns the number of rows actually flipped.
    @discardableResult
    public func markRowsStale(relPaths: Set<String>) async throws -> Int {
        guard let handle, !relPaths.isEmpty else { return 0 }
        try handle.exec("BEGIN IMMEDIATE")
        do {
            let update = try handle.prepare("""
                UPDATE images
                SET thumb_state = CASE WHEN thumb_state = 0 THEN 0 ELSE ? END
                WHERE path = ? AND orphan_sidecar = 0
                """)
            var flipped = 0
            for rel in relPaths {
                try update.bindInt(1, SessionIndexSchema.ThumbState.stale.rawValue)
                try update.bindText(2, rel)
                _ = try update.step()
                flipped += handle.changes()
                try update.reset()
            }
            try handle.exec("COMMIT")
            return flipped
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// The thumbnail-record binding leg (Plan 09-03 T2): after the provider
    /// produces/regenerates a thumb it binds `thumb_state` + `thumb_path`
    /// (absolute — a session move just misses and regenerates) +
    /// `thumb_params_hash` (L013 decimal TEXT — the params identity the
    /// thumb was produced from; a mismatch later = stale). `thumbPath`/
    /// `paramsHash` nil writes NULL (state reset).
    public func updateThumbnailRecord(
        relPath: String,
        state: SessionIndexSchema.ThumbState,
        thumbPath: String?,
        paramsHash: String?
    ) async throws {
        guard let handle else { return }
        try handle.exec("BEGIN IMMEDIATE")
        do {
            let update = try handle.prepare("""
                UPDATE images
                SET thumb_state = ?, thumb_path = ?, thumb_params_hash = ?
                WHERE path = ?
                """)
            try update.bindInt(1, state.rawValue)
            try update.bindText(2, thumbPath)
            try update.bindText(3, paramsHash)
            try update.bindText(4, relPath)
            _ = try update.step()
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    // MARK: - Lifecycle (teardown ②-d)

    /// Close the DB handle deterministically. Idempotent.
    public func close() {
        handle?.close()
        handle = nil
    }

    /// Schema/pragma verification INSIDE the actor (the handle never
    /// crosses isolation; tests assert against this projection).
    public struct SchemaVerification: Sendable, Equatable {
        public var columnNames: [String] = []
        public var columnTypes: [String] = []
        public var primaryKeyColumns: [String] = []
        public var schemaVersionMeta: String?
        public var hasDirIndex = false
        public var journalMode: String?
        public var synchronous: Int64?
        public var scanEpoch: Int64 = 0
    }

    public func schemaVerification() throws -> SchemaVerification {
        guard let handle else {
            throw SessionIndexError.execFailed(
                sql: "schemaVerification", code: 0, message: "store closed"
            )
        }
        var verification = SchemaVerification()
        let tableInfo = try handle.prepare("PRAGMA table_info(images)")
        while try tableInfo.step() {
            verification.columnNames.append(tableInfo.columnText(1) ?? "")
            verification.columnTypes.append(tableInfo.columnText(2) ?? "")
        }
        let pk = try handle.prepare(
            "SELECT name FROM pragma_table_info('images') WHERE pk = 1"
        )
        while try pk.step() {
            verification.primaryKeyColumns.append(pk.columnText(0) ?? "")
        }
        let meta = try handle.prepare(
            "SELECT value FROM meta WHERE key = 'schemaVersion'"
        )
        if try meta.step() {
            verification.schemaVersionMeta = meta.columnText(0)
        }
        let index = try handle.prepare(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_images_dir'"
        )
        verification.hasDirIndex = (try index.step())
        let journal = try handle.prepare("PRAGMA journal_mode")
        if try journal.step() {
            verification.journalMode = journal.columnText(0)
        }
        let sync = try handle.prepare("PRAGMA synchronous")
        if try sync.step() {
            verification.synchronous = sync.columnInt(0)
        }
        verification.scanEpoch = try SessionIndexSchema.readScanEpoch(from: handle)
        return verification
    }
}
