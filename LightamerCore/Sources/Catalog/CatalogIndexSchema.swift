import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// CatalogIndexSchema (Plan 16-1 T1) — the FROZEN v1 `.lcat` spelling; the
// SessionIndexSchema template applied to the cross-session domain.
//
// FREEZE CONTRACT: `schemaVersion = 1`. Dispatch: absent → fresh create
// (stamp 1); 1 → ok; >1 or unparsable → REFUSE (typed `schemaFailed` — this
// binary predates the file; never guess at a future schema). A future v2
// goes through the SAME table-driven idempotent `migrate` slot the session
// side pinned (SessionIndexSchema.swift:234-262 template — empty at v1,
// semantics nailed now). ONE-WAY FORMAT LOCK: `.lcat` never round-trips
// with Darktable/XMP; `schemaVersion=1` is the anchor
// (LightamerPreset.swift:38 semantics).
//
// SEVEN TABLES (16-RESEARCH §1.2/§RQ-16-2/§RQ-16-3):
//   catalog_images   — the 31-column contextual mirror: 29 mirrored session
//                      columns (`path`→`rel_path` RENAMED; `scan_epoch`/
//                      `thumb_state`/`thumb_path`/`thumb_params_hash`/`dirty`
//                      NOT mirrored) + `session_id` + stable `id`.
//                      `id INTEGER PRIMARY KEY` = rowid ALIAS — VACUUM never
//                      renumbers it; image_tags/categories/collections
//                      references MUST use this column, never a bare rowid.
//   catalog_sessions — the registry (watermark lives HERE, row-level; there
//                      is no meta scan_epoch on the catalog side).
//   categories / collections — organization truth (catalog's OWN asset;
//                      rebuildable only from backup, never from sessions).
//                      `parent_id` declares NO foreign key (orphan defense
//                      is a UI discipline — RQ-16-8), pinned as DDL policy.
//   image_categories / image_collections / image_tags — WITHOUT ROWID
//                      (single clustered structure IS the covering index;
//                      equality EXISTS plan = PK seek, F11).
//
// SEVEN INDEXES: six ordering/tail indexes sharing ONE shape
// `(k IS NULL, k [DESC], rel_path)` — VERBATIM match for the NULLs-last
// ORDER BY (F6; zero TEMP B-TREE) — plus the UNIQUE(session_id, rel_path)
// composite identity (the implicit seventh). NO filter-column indexes:
// idx_cat_cam/idx_cat_cl were REMOVED by the F10 ruling — a low-selectivity
// filter column lures the planner into filter-index + TEMP B-TREE
// materialization (201-525ms); the `+` prefix discipline in FilterSQL's
// catalog domain replaces them (recorded in 16-1-DECISIONS).
//
// PRAGMA BASELINE (F13, all centralized HERE — seam b): WAL +
// synchronous=NORMAL + cache_size=-64000 (−25% measured) +
// busy_timeout=5000 (RQ-16-17 dual-instance) + case_sensitive_like=ON
// (the catalog-domain filename/dir contains→startsWith downgrade needs
// LIKE to match the BINARY index collation — RQ-16-16①). mmap_size stays
// OUT of the baseline (<2% measured gain — optional knob, 16-1-DECISIONS).
//
// L013: `params_hash` mirrors the session side's DECIMAL TEXT spelling.
//
// Failure semantics: any apply error propagates (open path refuses);
// `migrate` runs in ONE BEGIN IMMEDIATE and ROLLS BACK on failure — the
// ORIGINAL file is left byte-untouched. A catalog that cannot open NEVER
// touches Sessions mode (catalog failure = Catalogs disabled, sessions
// untouched — the inherited failure semantics).
// ─────────────────────────────────────────────────────────────────────────────

public enum CatalogIndexSchema {

    /// The frozen on-disk schema version (one-way format lock anchor).
    public static let schemaVersion = 1

    // MARK: - Location (ONE constant place; SmartAlbumStore.swift:78-85 same
    // directory convention)

    public static let catalogDirectoryName = "Catalog"
    public static let databaseFileName = "catalog.lcat"

    /// Default location:
    /// `~/Library/Application Support/Lightamer/Catalog/catalog.lcat`.
    public static func defaultDatabaseURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                "Lightamer/\(catalogDirectoryName)", isDirectory: true
            )
            .appendingPathComponent(databaseFileName, isDirectory: false)
    }

    // MARK: - Frozen column spelling (name, declared type) — IN ORDER
    //
    // 31 columns = 29 mirrored (index 2…30 in this array, `rel_path` first)
    // + `session_id` + stable `id`. The five NON-mirrored session columns
    // (`scan_epoch`, `thumb_state`, `thumb_path`, `thumb_params_hash`,
    // `dirty`) have NO row here — tests assert the full 31 VERBATIM.

    public static let catalogImageColumns: [(name: String, type: String)] = [
        ("id", "INTEGER"),                   // PRIMARY KEY — stable internal key (rowid alias)
        ("session_id", "TEXT"),              // NOT NULL — composite identity half
        ("rel_path", "TEXT"),                // NOT NULL — session `path` renamed (contextual)
        ("dir", "TEXT"),                     // mirrored: sort/filter
        ("filename", "TEXT"),                // mirrored: sort/filter
        ("file_size", "INTEGER"),
        ("file_mtime", "REAL"),
        ("imageID", "TEXT"),                 // sidecar truth (camelCase per session freeze)
        ("sidecar_present", "INTEGER"),
        ("sidecar_mtime", "REAL"),
        ("has_edits", "INTEGER"),
        ("params_hash", "TEXT"),             // L013: DECIMAL TEXT
        ("layer_count", "INTEGER"),
        ("layer_summary", "TEXT"),
        ("orientation", "INTEGER"),
        ("width", "INTEGER"),
        ("height", "INTEGER"),
        ("capture_date", "REAL"),            // NULLs-last ordering keys live here
        ("rating", "INTEGER"),
        ("color_label", "INTEGER"),
        ("keywords", "TEXT"),                // tag materialization SOURCE (prefix expansion)
        ("orphan_sidecar", "INTEGER"),       // baseline predicate (both domains)
        ("flag", "INTEGER"),
        ("note", "TEXT"),
        ("camera_make", "TEXT"),
        ("camera_model", "TEXT"),
        ("lens_model", "TEXT"),
        ("iso", "INTEGER"),
        ("focal_length", "REAL"),
        ("aperture", "REAL"),
        ("exposure", "REAL"),
    ]

    /// The session-side source columns mirrored by `catalogImageColumns`
    /// (IN THE SAME ORDER — the projector's SELECT list on the lindex side).
    /// `path` appears where `rel_path` lands; the five non-mirrored columns
    /// are absent BY DESIGN.
    public static let mirroredSourceColumns: [String] = [
        "path",                              // → rel_path (the ONE rename)
        "dir", "filename", "file_size", "file_mtime",
        "imageID", "sidecar_present", "sidecar_mtime", "has_edits",
        "params_hash", "layer_count", "layer_summary",
        "orientation", "width", "height", "capture_date",
        "rating", "color_label", "keywords", "orphan_sidecar",
        "flag", "note",
        "camera_make", "camera_model", "lens_model",
        "iso", "focal_length", "aperture", "exposure",
    ]

    // MARK: - DDL (frozen, 16-RESEARCH §1.2 verbatim shapes)

    static let createCatalogImagesTableSQL = """
        CREATE TABLE IF NOT EXISTS catalog_images (
          id INTEGER PRIMARY KEY,
          session_id TEXT NOT NULL,
          rel_path TEXT NOT NULL,
          dir TEXT,
          filename TEXT,
          file_size INTEGER,
          file_mtime REAL,
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
          rating INTEGER,
          color_label INTEGER,
          keywords TEXT,
          orphan_sidecar INTEGER,
          flag INTEGER,
          note TEXT,
          camera_make TEXT,
          camera_model TEXT,
          lens_model TEXT,
          iso INTEGER,
          focal_length REAL,
          aperture REAL,
          exposure REAL,
          UNIQUE(session_id, rel_path)
        )
        """

    static let createCatalogSessionsTableSQL = """
        CREATE TABLE IF NOT EXISTS catalog_sessions (
          session_id TEXT PRIMARY KEY,
          root_path TEXT NOT NULL,
          display_name TEXT,
          last_projected_epoch INTEGER NOT NULL DEFAULT 0,
          last_seen REAL,
          offline INTEGER NOT NULL DEFAULT 0
        )
        """

    static let createCategoriesTableSQL = """
        CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY,
          parent_id INTEGER,
          name TEXT,
          sort_order INTEGER,
          created_at REAL
        )
        """

    static let createCollectionsTableSQL = """
        CREATE TABLE IF NOT EXISTS collections (
          id INTEGER PRIMARY KEY,
          name TEXT,
          sort_order INTEGER,
          created_at REAL
        )
        """

    static let createImageCategoriesTableSQL = """
        CREATE TABLE IF NOT EXISTS image_categories (
          category_id INTEGER,
          catalog_image_id INTEGER,
          PRIMARY KEY (category_id, catalog_image_id)
        ) WITHOUT ROWID
        """

    static let createImageCollectionsTableSQL = """
        CREATE TABLE IF NOT EXISTS image_collections (
          collection_id INTEGER,
          catalog_image_id INTEGER,
          PRIMARY KEY (collection_id, catalog_image_id)
        ) WITHOUT ROWID
        """

    static let createImageTagsTableSQL = """
        CREATE TABLE IF NOT EXISTS image_tags (
          tag TEXT,
          catalog_image_id INTEGER,
          PRIMARY KEY (tag, catalog_image_id)
        ) WITHOUT ROWID
        """

    /// The PER-IMAGE delete seam's index (Plan 16-1 T5 first-run finding):
    /// the projector re-materializes a row's tags EVERY projection
    /// (`DELETE … WHERE catalog_image_id = ?` — R6 idempotence), and the
    /// clustered PK only serves the (tag, id) direction — without this
    /// index every per-image delete is a FULL tags-table scan (measured:
    /// 100k-row projection 148s → the index brings the delete to a seek;
    /// the EXISTS query direction is unaffected — it still walks the PK).
    static let createImageTagsDeleteIndexSQL =
        "CREATE INDEX IF NOT EXISTS idx_tags_image ON image_tags(catalog_image_id)"

    static let createMetaTableSQL = """
        CREATE TABLE IF NOT EXISTS meta (
          key TEXT PRIMARY KEY,
          value TEXT
        )
        """

    // The six ordering/tail indexes — shape `(k IS NULL, k [DESC],
    // rel_path)`, VERBATIM aligned with FilterSQL's catalog-domain
    // orderBySQL (seam a ↔ seam b spelling contract; F6).
    static let orderingIndexSQL: [String] = [
        "CREATE INDEX IF NOT EXISTS idx_cat_cd_desc ON catalog_images"
            + "(capture_date IS NULL, capture_date DESC, rel_path)",
        "CREATE INDEX IF NOT EXISTS idx_cat_cd_asc ON catalog_images"
            + "(capture_date IS NULL, capture_date, rel_path)",
        "CREATE INDEX IF NOT EXISTS idx_cat_rt_desc ON catalog_images"
            + "(rating IS NULL, rating DESC, rel_path)",
        "CREATE INDEX IF NOT EXISTS idx_cat_rt_asc ON catalog_images"
            + "(rating IS NULL, rating, rel_path)",
        "CREATE INDEX IF NOT EXISTS idx_cat_fn ON catalog_images"
            + "(filename IS NULL, filename, rel_path)",
        "CREATE INDEX IF NOT EXISTS idx_cat_rel ON catalog_images(rel_path)",
    ]

    /// The six named ordering/tail indexes (the implicit seventh =
    /// the UNIQUE(session_id, rel_path) autoindex).
    public static let orderingIndexNames: [String] = [
        "idx_cat_cd_desc", "idx_cat_cd_asc", "idx_cat_rt_desc",
        "idx_cat_rt_asc", "idx_cat_fn", "idx_cat_rel",
    ]

    public enum MetaKey {
        public static let schemaVersion = "schemaVersion"
    }

    // MARK: - Open / verify (migration slot reserved)

    /// Apply the pragmas + the seven-table DDL, then dispatch on the stored
    /// schema version: absent → fresh v1 (stamp 1); 1 → ok; >1 or
    /// unparsable → REFUSE (never guess at an unknown/future schema — a
    /// `schemaFailed` here means Catalogs mode degrades to disabled while
    /// Sessions mode is untouched).
    public static func apply(to handle: SQLiteHandle) throws {
        // WAL first (persistent journal mode) — the grid reads and the
        // projector's write transaction must not block each other (R4).
        try handle.execute("PRAGMA journal_mode=WAL")
        // synchronous=NORMAL — the catalog is rebuildable; NORMAL keeps
        // committed transactions crash-safe at WAL speed.
        try handle.execute("PRAGMA synchronous=NORMAL")
        // F13 baseline: 64MB page cache (−25% measured).
        try handle.execute("PRAGMA cache_size=-64000")
        // RQ-16-17: dual-instance write contention waits 5s instead of
        // instant SQLITE_BUSY (mirrors the handle's 5s busy timeout).
        try handle.execute("PRAGMA busy_timeout=5000")
        // RQ-16-16①: the filename/dir startsWith downgrade walks the BINARY
        // index only when LIKE is case-sensitive (connection-level pragma).
        try handle.execute("PRAGMA case_sensitive_like=ON")

        try handle.execute(createCatalogImagesTableSQL)
        try handle.execute(createCatalogSessionsTableSQL)
        try handle.execute(createCategoriesTableSQL)
        try handle.execute(createCollectionsTableSQL)
        try handle.execute(createImageCategoriesTableSQL)
        try handle.execute(createImageCollectionsTableSQL)
        try handle.execute(createImageTagsTableSQL)
        try handle.execute(createMetaTableSQL)
        for sql in orderingIndexSQL {
            try handle.execute(sql)
        }
        try handle.execute(createImageTagsDeleteIndexSQL)

        // Version dispatch.
        let statement = try handle.prepare("SELECT value FROM meta WHERE key = ?")
        try statement.bindText(1, MetaKey.schemaVersion)
        let existing: String? = try statement.step() ? statement.columnText(0) : nil

        if let existing, let stored = Int(existing) {
            guard stored <= schemaVersion else {
                throw SessionIndexError.schemaFailed(
                    detail: "catalog schema v\(stored) is NEWER than this binary's "
                        + "v\(schemaVersion) — refusing to open",
                    code: 0, message: "schemaVersion mismatch"
                )
            }
            if stored < schemaVersion {
                try migrate(from: stored, to: schemaVersion, on: handle)
            }
        } else if existing != nil {
            // Present-but-unparsable meta value: the schema state is
            // unknown — fail closed (SessionIndexSchema.swift:202-211
            // semantics; stamping over an unreadable value could silently
            // skip a missing migration).
            throw SessionIndexError.schemaFailed(
                detail: "catalog schemaVersion value '\(existing ?? "<nil>")' is "
                    + "not a supported version — refusing to open",
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

    /// The future-version migration slot — TABLE-DRIVEN and idempotent,
    /// pinned to the SessionIndexSchema.swift:234-262 semantics NOW so v2
    /// work cannot invent a second shape. At v1 there is nothing to
    /// migrate: the body is deliberately empty (the version stamp update
    /// below is the only work). Failure ROLLS BACK — the original file is
    /// left untouched.
    public static func migrate(from: Int, to: Int, on handle: SQLiteHandle) throws {
        try handle.exec("BEGIN IMMEDIATE")
        do {
            // v1: no prior versions exist — nothing to ALTER. The v2 shape
            // (tail-append ALTER per missing column, per-column idempotent)
            // fills this slot following SessionIndexSchema.migrate.
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

    /// Plan 16-4: the deterministic TRUNCATE checkpoint (the destructive
    /// rebuild's promotion precondition — every committed page must be IN
    /// the main file before the rename). The PRAGMA spelling lives HERE
    /// (seam b: all pragma faces centralized in the schema enum).
    public static func checkpointTruncate(on handle: SQLiteHandle) throws {
        try handle.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }
}
