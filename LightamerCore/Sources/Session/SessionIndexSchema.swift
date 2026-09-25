import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SessionIndexSchema (Plan 09-01 T4) — the FROZEN v1 spelling.
//
// FREEZE CONTRACT (09-CONTEXT specifics): the column names/types/order below
// are the v1 contract — later plans CONSUME, never migrate. `schemaVersion`
// dispatch exists from day one: absent → fresh create (v1); 1 → ok; >1 →
// REFUSE (this binary predates the file; never guess at a future schema).
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
// synchronous=NORMAL is pinned (NOT OFF — D-09-CONTEXT-1): the index is
// rebuildable, but losing the dirty markers turns 9-4's crash self-heal
// into a full rescan. WAL + NORMAL keeps read/write concurrency while
// keeping committed transactions crash-safe.
// ─────────────────────────────────────────────────────────────────────────────

public enum SessionIndexSchema {

    /// The frozen on-disk schema version (D-S1-style migration anchor).
    public static let schemaVersion = 1

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
          dirty INTEGER DEFAULT 0
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

    // MARK: - Open / verify

    /// Apply the pragmas + DDL. Refuses a FUTURE schema version.
    public static func apply(to handle: SQLiteHandle) throws {
        // WAL first (persistent journal mode) — UI queries and write
        // transactions must not block each other.
        try handle.execute("PRAGMA journal_mode=WAL")
        // synchronous=NORMAL pinned — see header (dirty-marker crash safety).
        try handle.execute("PRAGMA synchronous=NORMAL")

        try handle.execute(createImagesTableSQL)
        try handle.execute(createMetaTableSQL)
        try handle.execute(createDirIndexSQL)

        // Version dispatch: absent → stamp v1; 1 → ok; >1 → refuse.
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
        } else {
            let insert = try handle.prepare(
                "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)"
            )
            try insert.bindText(1, MetaKey.schemaVersion)
            try insert.bindText(2, String(schemaVersion))
            _ = try insert.step()
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
