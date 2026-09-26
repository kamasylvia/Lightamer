import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SessionIndexSchema (Plan 09-01 T4) — the FROZEN v1 spelling; v2 since
// Plan 12-1 T2 (the FIRST real migration, D-12-CONTEXT-1's explicit
// exception to the "later plans CONSUME, never migrate" freeze).
//
// FREEZE CONTRACT (09-CONTEXT specifics → 12-1 amendment): the column
// names/types/order below are the v2 contract. `schemaVersion` dispatch:
// absent → fresh create (v2); 1 → migrate to 2; 2 → ok; >2 → REFUSE (this
// binary predates the file; never guess at a future schema). The v1→v2
// migration is table-driven and idempotent per column (existing columns
// are skipped) — ALTER TABLE ADD COLUMN can only append tail columns with
// NULL defaults, which is exactly the v2 shape.
//
// L013 hash discipline: `params_hash` / `thumb_params_hash` are DECIMAL
// TEXT (the `UInt64String` semantics — FNV-1a 64 exceeds 2^53 and JSON /
// INTEGER round-trips through non-Swift tools lose precision). NEVER
// INTEGER.
//
// D-09-CONTEXT-7: `rating` / `color_label` / `keywords` are built NOW,
// Phase 12 (META-05) fills them — zero ALTER migration later.
// `dirty` (9-4 batch apply: sidecar write pending — crash self-heal reads
// the sidecar back over the row) and `orphan_sidecar` (9-2 reconcile) are
// the other forward consumers.
//
// v2 (Plan 12-1 T2, D-12-CONTEXT-1): nine tail columns join — `flag` /
// `note` (the MCP-06 write face) + the seven EXIF light columns
// (`camera_make`/`camera_model`/`lens_model`/`iso`/`focal_length`/
// `aperture`/`exposure` — the META-05 filter keys, dt collection.h
// property enumeration). All start NULL; the EXIF columns fill via
// `backfillExifMetadata`'s NULL-class sweep.
//
// NO NEW INDEXES (12-1 execution decision, recorded in DECISIONS): the
// 12-RESEARCH §3.4 measured 10k-row full scans at <1ms for every v2
// predicate shape — index write-amplification buys nothing at session
// scale. `idx_images_dir` stays the only secondary index.
//
// synchronous=NORMAL is pinned (NOT OFF — D-09-CONTEXT-1): the index is
// rebuildable, but losing the dirty markers turns 9-4's crash self-heal
// into a full rescan. WAL + NORMAL keeps read/write concurrency while
// keeping committed transactions crash-safe.
// ─────────────────────────────────────────────────────────────────────────────

public enum SessionIndexSchema {

    /// The frozen on-disk schema version (D-S1-style migration anchor).
    /// v2 since Plan 12-1 T2 (25 → 34 images columns).
    public static let schemaVersion = 2

    /// Database file inside the session's derived-cache directory
    /// (D-09-CONTEXT-2: `<sessionRoot>/.lightamer/session.lindex`).
    public static let derivedCacheDirectoryName = ".lightamer"
    public static let databaseFileName = "session.lindex"

    public static func databaseURL(forSessionRoot root: URL) -> URL {
        root
            .appendingPathComponent(derivedCacheDirectoryName, isDirectory: true)
            .appendingPathComponent(databaseFileName, isDirectory: false)
    }

    // MARK: - Frozen column spelling (name, declared type) — IN ORDER

    /// The `images` table columns IN ORDER (the freeze contract; tests
    /// assert this list against `PRAGMA table_info` VERBATIM).
    public static let imagesColumns: [(name: String, type: String)] = [
        ("path", "TEXT"),                    // PRIMARY KEY — rel to session root
        ("dir", "TEXT"),                     // redundant: sort/filter
        ("filename", "TEXT"),                // redundant: sort/filter
        ("file_size", "INTEGER"),
        ("file_mtime", "REAL"),
        ("scan_epoch", "INTEGER"),
        ("imageID", "TEXT"),                 // sidecar truth (nil = pristine)
        ("sidecar_present", "INTEGER"),
        ("sidecar_mtime", "REAL"),
        ("has_edits", "INTEGER"),            // history.position >= 0 (yiyin instances included)
        ("params_hash", "TEXT"),             // L013: DECIMAL TEXT (sidecar historyHash)
        ("layer_count", "INTEGER"),
        ("layer_summary", "TEXT"),           // JSON: name/blend/visible per layer
        ("orientation", "INTEGER"),          // ImageIO light columns (delayed fill)
        ("width", "INTEGER"),
        ("height", "INTEGER"),
        ("capture_date", "REAL"),
        ("thumb_state", "INTEGER"),          // 0 none / 1 embedded / 2 rendered / 3 stale
        ("thumb_path", "TEXT"),
        ("thumb_params_hash", "TEXT"),       // L013: DECIMAL TEXT
        ("rating", "INTEGER"),               // Phase 12 reservation (D-09-CONTEXT-7)
        ("color_label", "INTEGER"),          // Phase 12 reservation
        ("keywords", "TEXT"),                // Phase 12 reservation
        ("orphan_sidecar", "INTEGER"),       // row IS an orphan .lra record (path = .lra rel)
        ("dirty", "INTEGER"),                // 9-4: sidecar write pending (DEFAULT 0)
        // ── v2 tail (Plan 12-1 T2 — ORDER IS PART OF THE FREEZE) ──────────
        ("flag", "INTEGER"),                 // 0 none / 1 pick / 2 reject (MCP-06)
        ("note", "TEXT"),                    // MCP-06 append_note
        ("camera_make", "TEXT"),             // EXIF light columns (TIFF Make)
        ("camera_model", "TEXT"),            // TIFF Model
        ("lens_model", "TEXT"),              // Exif LensModel
        ("iso", "INTEGER"),                  // Exif ISOSpeedRatings
        ("focal_length", "REAL"),            // Exif FocalLength (mm)
        ("aperture", "REAL"),                // Exif FNumber
        ("exposure", "REAL"),                // Exif ExposureTime (s)
    ]

    /// `thumb_state` enumeration (§5 double-tier pipeline; 9-3 consumes).
    public enum ThumbState: Int64, Sendable {
        case none = 0
        case embedded = 1
        case rendered = 2
        case stale = 3
    }

    // MARK: - DDL (frozen)

    static let createImagesTableSQL = """
        CREATE TABLE IF NOT EXISTS images (
          path TEXT PRIMARY KEY,
          dir TEXT,
          filename TEXT,
          file_size INTEGER,
          file_mtime REAL,
          scan_epoch INTEGER,
          imageID TEXT,
          sidecar_present INTEGER,
          sidecar_mtime REAL,
          has_edits INTEGER,
          params_hash TEXT,
          layer_count INTEGER,
          layer_summary TEXT,
          orientation INTEGER,
          width INTEGER,
          height INTEGER,
          capture_date REAL,
          thumb_state INTEGER,
          thumb_path TEXT,
          thumb_params_hash TEXT,
          rating INTEGER,
          color_label INTEGER,
          keywords TEXT,
          orphan_sidecar INTEGER,
          dirty INTEGER DEFAULT 0,
          flag INTEGER,
          note TEXT,
          camera_make TEXT,
          camera_model TEXT,
          lens_model TEXT,
          iso INTEGER,
          focal_length REAL,
          aperture REAL,
          exposure REAL
        )
        """

    static let createMetaTableSQL = """
        CREATE TABLE IF NOT EXISTS meta (
          key TEXT PRIMARY KEY,
          value TEXT
        )
        """

    static let createDirIndexSQL = "CREATE INDEX IF NOT EXISTS idx_images_dir ON images(dir)"

    public enum MetaKey {
        public static let schemaVersion = "schemaVersion"
        public static let scanEpoch = "scan_epoch"
        public static let lastFullScan = "last_full_scan"
    }

    // MARK: - Open / verify / migrate

    /// Apply the pragmas + DDL, then dispatch on the stored schema version:
    /// absent → fresh v2 (stamp 2); 1 → migrate to 2; 2 → ok; >2 (or
    /// unparsable) → REFUSE (never guess at an unknown/future schema).
    public static func apply(to handle: SQLiteHandle) throws {
        // WAL first (persistent journal mode) — UI queries and write
        // transactions must not block each other.
        try handle.execute("PRAGMA journal_mode=WAL")
        // synchronous=NORMAL pinned — see header (dirty-marker crash safety).
        try handle.execute("PRAGMA synchronous=NORMAL")

        try handle.execute(createImagesTableSQL)
        try handle.execute(createMetaTableSQL)
        try handle.execute(createDirIndexSQL)

        // Version dispatch.
        let statement = try handle.prepare(
            "SELECT value FROM meta WHERE key = ?"
        )
        try statement.bindText(1, MetaKey.schemaVersion)
        let existing: String? = try statement.step() ? statement.columnText(0) : nil

        if let existing, let stored = Int(existing) {
            guard stored <= schemaVersion else {
                throw SessionIndexError.schemaFailed(
                    detail: "database schema v\(stored) is NEWER than this binary's "
                        + "v\(schemaVersion) — refusing to open",
                    code: 0, message: "schemaVersion mismatch"
                )
            }
            if stored < schemaVersion {
                try migrate(from: stored, to: schemaVersion, on: handle)
            }
        } else if existing != nil {
            // A present-but-unparsable meta value: the schema state is
            // unknown — fail closed (12-1 execution decision; stamping a
            // version over an unreadable value could silently skip a
            // missing column set).
            throw SessionIndexError.schemaFailed(
                detail: "database schemaVersion value \(existing) is not a "
                    + "supported version — refusing to open",
                code: 0, message: "schemaVersion unparsable"
            )
        } else {
            let insert = try handle.prepare(
                "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)"
            )
            try insert.bindText(1, MetaKey.schemaVersion)
            try insert.bindText(2, String(schemaVersion))
            _ = try insert.step()
        }
    }

    /// The v1→v2 (and any future stored < current) migration — TABLE-
    /// DRIVEN and per-column IDEMPOTENT (12-RESEARCH §2.2 verbatim
    /// sequence): read the existing column set, ALTER only the missing
    /// target columns inside ONE `BEGIN IMMEDIATE` transaction, then stamp
    /// the meta version. A second run finds every column present and is a
    /// no-op (zero harm). ALTER TABLE ADD COLUMN appends tail columns with
    /// NULL defaults — exactly the v2 shape; old rows keep every byte.
    ///
    /// Failure semantics: any error ROLLS BACK and propagates — the caller
    /// (open path) refuses to open and the ORIGINAL database file is left
    /// untouched on disk (the destructive red line: a failed migration
    /// never rewrites the user's library).
    public static func migrate(from: Int, to: Int, on handle: SQLiteHandle) throws {
        try handle.exec("BEGIN IMMEDIATE")
        do {
            // The existing column set (per-column idempotence defense).
            var existing = Set<String>()
            let info = try handle.prepare("PRAGMA table_info(images)")
            while try info.step() {
                if let name = info.columnText(1) {
                    existing.insert(name)
                }
            }
            // Add every missing target column (tail append; NULL default).
            for column in imagesColumns where !existing.contains(column.name) {
                try handle.execute(
                    "ALTER TABLE images ADD COLUMN \(column.name) \(column.type)"
                )
            }
            let stamp = try handle.prepare(
                "UPDATE meta SET value = ? WHERE key = ?"
            )
            try stamp.bindText(1, String(to))
            try stamp.bindText(2, MetaKey.schemaVersion)
            _ = try stamp.step()
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// Current `scan_epoch` (0 before the first sync).
    public static func readScanEpoch(from handle: SQLiteHandle) throws -> Int64 {
        let statement = try handle.prepare("SELECT value FROM meta WHERE key = ?")
        try statement.bindText(1, MetaKey.scanEpoch)
        guard try statement.step(), let value = statement.columnText(0) else {
            return 0
        }
        return Int64(value) ?? 0
    }
}
