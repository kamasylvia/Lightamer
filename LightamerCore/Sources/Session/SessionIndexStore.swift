import Foundation
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
            rootPath: root.path, handle: opened
        )
        result.counts = try computeCounts(handle: opened)
        result.firstImageRelPath = try firstBrowsableRelPath(handle: opened)
        return result
    }

    /// The diff + single transaction. Internal so tests can drive it.
    func sync(
        scanEntries: [String: SessionScanEntry],
        scanOrphans: Set<String>,
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

    public func counts() throws -> SessionIndexCounts {
        guard let handle else { return SessionIndexCounts() }
        return try computeCounts(handle: handle)
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
