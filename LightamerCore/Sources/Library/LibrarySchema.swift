import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySchema (Plan M2-2-1 T1; OQ-2/3/6/7/10/12 rulings) — the FROZEN v1
// `.lalb` spelling: the single-SQLite-file project package's DDL face.
//
// FREEZE CONTRACT: `schemaVersion = 1`, truth = `PRAGMA user_version` (OQ-2
// 字面 — the manifest double-write goes to `project_meta` but the READ side
// dispatches on user_version). Dispatch: absent/0 → fresh create (v1) +
// seed `project_meta` + stamp 1; 1 → ok; >1 → typed REFUSE
// (`LibraryError.futureSchema` — this binary predates the file; never guess
// at a future schema). The migrate slot is EMPTY at v1 but its SHAPE is
// pinned now (SessionIndexSchema.swift:234 template): any future N→N+1
// migration runs inside ONE BEGIN IMMEDIATE after the ProjectFileStore
// takes an automatic `sqlite3_backup` snapshot (KD-2's pre-migration backup
// hook — M2-8/M2-10 reserved-table activation walks THIS seam, and only
// after M2-4 (node model) is the schema truly stable).
//
// TRUTH BOUNDARY (OQ-3, the phase's architecture red line): the `.lalb` is
// an ORGANIZATION + RETRIEVAL-PROJECTION + REFERENCE container. The `.lra`
// sidecar stays the EDIT-STATE truth — `has_edits`/`params_hash` are
// projection columns (session.lindex same shape, L013 DECIMAL TEXT). The
// Alcedo mini-git table family is reserved as COMMENTS ONLY (file tail) —
// NO empty entity tables (negative-pinned by LibrarySchemaTests).
//
// L013 hash discipline: `params_hash` is DECIMAL TEXT (UInt64String
// semantics — FNV-1a 64 exceeds 2^53; JSON/INTEGER round-trips through
// non-Swift tools lose precision). NEVER INTEGER.
//
// D-09-CONTEXT-7 NULL-reservation pattern continues: `rating`/`color_label`/
// `keywords`/`filename`/`dir`/`flag`/`note` exist NOW so the session
// four-clause predicate shapes serve the library domain with ZERO ALTER
// migration later (`FilterSQL` .library domain, KD-7).
//
// PACKAGE LAYOUT (KD-1 — OQ-2 ruled the DB is ONE file, but copied/moved
// photos and the thumbnail cache need homes):
//
//   <project directory>/
//     <stem>.lalb            SQLite truth (manifest lives in project_meta)
//     Media/                 copy/move imports (visible, source subtree kept)
//     .<stem>.lathumbs/      thumbnail cache (rebuildable derivative; OQ-10)
//
// "Move the project" = move the WHOLE directory + the DB-level backup API
// (ProjectFileStore.backup). `image_path` stores three forms discriminated
// by `path_kind`: 0 = project-relative (under Media/, immune to mount-point
// renames) / 1 = volume-relative + volume_uuid (same-volume symlink import,
// the L009 scenario) / 2 = absolute + volume_uuid (cross-volume fallback).
// Resolve rules + stale detection = P2's ImageLinker; THIS plan only
// freezes the columns.
//
// WAL discipline (OQ-2/P3): journal_mode=WAL + synchronous=NORMAL (NOT OFF
// — the D-09-CONTEXT-1 rationale carries over) + throttled TRUNCATE
// checkpoints after write batches + forced checkpoint on close (KD-6
// constants live in ProjectFileStore). "Single file" semantics = one data
// file + an EMPTY companion under checkpoint discipline (probe P3: even a
// clean close leaves a 0-byte `-wal` on 3.54.0) — backups MUST go through
// the sqlite3_backup API, never a bare main-file copy.
//
// FTS5 (OQ-7/KD-5): `images_fts` = EXTERNAL-CONTENT over images with the
// DEFAULT unicode61 tokenizer — ZERO custom tokenchars (probe P2: folding
// `/`/`.` into tokens makes `f/2.8` one token and the `f2.8` query MISS;
// ALL normalization belongs to the ExifFold materialized columns). The FTS
// column name is `exif_search_words`, IDENTICAL to the images column —
// external-content rebuild reads same-named columns; an alias would make
// `VALUES('rebuild')` fail with "no such column".
//
// PRAGMA foreign_keys=ON is part of the schema baseline: album_content
// cascades (album delete → content delete; image delete → membership
// delete) are DECLARED DDL semantics (KD-4), enforced per connection.
// ─────────────────────────────────────────────────────────────────────────────

public enum LibrarySchema {

    /// The frozen on-disk schema version (one-way format lock anchor).
    /// M2-5-2 (KD-6): v1 → v2 = the FIRST migration — the additive
    /// `images.default_look_pending` column (the M2GRADE-03 per-image
    /// pending marker); old v1 packages open through the ProjectFileStore
    /// dispatch (pre-migration `sqlite3_backup` snapshot → the v1→v2 slot
    /// below → idempotent `ALTER TABLE ADD COLUMN`).
    public static let schemaVersion = 2

    // MARK: - Package layout constants (KD-1; consumed by P2 import, M2-3 UI)

    /// The package file extension (`<stem>.lalb`).
    public static let fileExtension = "lalb"
    /// Copy/move-imported physical photos live here (visible directory,
    /// source subtree structure preserved).
    public static let mediaDirectoryName = "Media"
    /// Thumbnail cache directory for a package stem — a REBUILDABLE
    /// derivative that must never mix with the truth file (OQ-10 A1:
    /// `<project dir>/.<stem>.lathumbs/`; moves with the project, deleted
    /// with it; wiring = M2-3, this plan pins the constant only).
    public static func thumbsDirectoryName(stem: String) -> String {
        ".\(stem).lathumbs"
    }

    // MARK: - Frozen column spelling (name, declared type) — IN ORDER

    /// The `images` table columns IN ORDER (the freeze contract; tests
    /// assert this list against `PRAGMA table_info` VERBATIM — order IS the
    /// DDL order, KD-3's complete enumeration):
    ///   • `id INTEGER PRIMARY KEY` FIRST — FTS `content_rowid='id'`, the
    ///     album_content FK, and M2-2-3's keyset `(capture_date, id)` seek
    ///     all consume it.
    ///   • `image_path`/`path_kind`/`volume_uuid` — the KD-1 three-form
    ///     path carrier (`path_kind` 0/1/2, `volume_uuid` for forms 1/2).
    ///   • The eight EXIF light columns — same names/types as
    ///     SessionIndexSchema v2 (`FilterSQL` field→column mapping needs
    ///     ZERO changes to serve the library).
    ///   • `file_stem`/`file_ext`/`exif_search_text`/`exif_search_words` —
    ///     the M2LIB-04 materialized search quartet (Alcedo
    ///     image_search_columns.hpp same-name semantics).
    ///   • `rating`/`color_label`/`keywords`/`filename`/`dir` + `flag`/
    ///     `note` — the D-09-CONTEXT-7 NULL-reservation pattern (built
    ///     now, filled by import; the session predicate shapes ride them).
    ///   • `has_edits`/`params_hash` — the edit-STATE projection (`.lra`
    ///     stays the truth, OQ-3; L013 DECIMAL TEXT) + `ref_count` (KD-4
    ///     materialized membership counter) + `added_time`/`modified_time`.
    public static let imagesColumns: [(name: String, type: String)] = [
        ("id", "INTEGER"),                   // PRIMARY KEY — rowid alias (FTS/FK/keyset)
        ("image_path", "TEXT"),              // path_kind 0: Media/-relative / 1: volume-rel / 2: absolute
        ("path_kind", "INTEGER"),            // 0/1/2 (PathKind)
        ("volume_uuid", "TEXT"),             // forms 1/2 (the L009 "know WHY it broke" column)
        ("camera_make", "TEXT"),             // EXIF light columns (TIFF Make)
        ("camera_model", "TEXT"),            // TIFF Model
        ("lens_model", "TEXT"),              // Exif LensModel
        ("iso", "INTEGER"),                  // Exif ISOSpeedRatings
        ("focal_length", "REAL"),            // Exif FocalLength (mm)
        ("aperture", "REAL"),                // Exif FNumber
        ("exposure", "REAL"),                // Exif ExposureTime (s)
        ("capture_date", "REAL"),            // Exif DateTimeOriginal (epoch; keyset lead column)
        ("file_stem", "TEXT"),               // M2LIB-04 materialized search quartet
        ("file_ext", "TEXT"),                // lowercase extension (RAW whitelist match face)
        ("exif_search_text", "TEXT"),        // folded search text (LIKE leg)
        ("exif_search_words", "TEXT"),       // folded word variants (FTS leg — SAME name as the FTS column)
        ("rating", "INTEGER"),               // D-09-CONTEXT-7 reservation (filled by import)
        ("color_label", "INTEGER"),          // reservation
        ("keywords", "TEXT"),                // reservation (| -joined; .library domain hits THIS)
        ("filename", "TEXT"),                // reservation (sort/filter)
        ("dir", "TEXT"),                     // reservation (sort/filter)
        ("flag", "INTEGER"),                 // reservation (0 none / 1 pick / 2 reject)
        ("note", "TEXT"),                    // reservation
        ("has_edits", "INTEGER"),            // edit-state PROJECTION (.lra is the truth, OQ-3)
        ("params_hash", "TEXT"),             // L013: DECIMAL TEXT (projection)
        ("ref_count", "INTEGER"),            // KD-4: materialized album-membership counter
        ("added_time", "REAL"),              // import timestamp
        ("modified_time", "REAL"),           // last row mutation
        ("default_look_pending", "INTEGER"),  // M2-5-2 KD-5: new-import default-look marker (appended, v2; DDL default 0 — the freeze type rides the PRAGMA spelling)
    ]

    /// The `albums` table columns IN ORDER — the OQ-6 语义对齐 + 表形简化:
    /// three album kinds live in ONE table behind the `type` discriminator
    /// (Alcedo `SleeveRoot`/`ComboFolder` merge here); `filter_data`
    /// carries the smart album's `FilterPredicateGroup` Codable JSON (the
    /// EXISTING model — `FilterSQL` consumes it, ZERO format additions).
    public static let albumsColumns: [(name: String, type: String)] = [
        ("id", "INTEGER"),                   // PRIMARY KEY — rowid alias
        ("type", "TEXT"),                    // 'album' | 'folder' | 'filter' (AlbumKind)
        ("name", "TEXT"),                    // display name (non-empty; store re-checks)
        ("parent_id", "INTEGER"),            // folder tree root (NULL = root; FK → albums.id CASCADE)
        ("filter_data", "TEXT"),             // type 'filter' ONLY: FilterPredicateGroup JSON
        ("added_time", "REAL"),
        ("modified_time", "REAL"),
    ]

    /// The `album_content` membership columns IN ORDER — the KD-4
    /// reference-count model's join table (WITHOUT ROWID, the catalog
    /// link-table precedent: the clustered PK IS the covering index for
    /// the members-of direction; `idx_album_content_image` serves the
    /// reverse). Both FKs CASCADE: album delete → membership rows gone;
    /// image delete → membership rows gone (ref_count rides the images
    /// row itself, so the store decrements BEFORE the delete in ONE
    /// transaction).
    public static let albumContentColumns: [(name: String, type: String)] = [
        ("album_id", "INTEGER"),             // PK half — FK → albums.id ON DELETE CASCADE
        ("image_id", "INTEGER"),             // PK half — FK → images.id ON DELETE CASCADE
    ]

    /// The album kind discriminator (OQ-6: three kinds, one table).
    public enum AlbumKind: String, Sendable, CaseIterable {
        case album
        case folder
        case filter
    }

    /// The `path_kind` discriminator (KD-1: three stored path forms).
    public enum PathKind: Int64, Sendable {
        /// Under `Media/` — stored project-relative; whole-directory moves
        /// are immune to mount-point renames.
        case projectRelative = 0
        /// Same-volume symlink import — volume-relative + `volume_uuid`
        /// (the L009 scenario: mount rename survivable, cross-volume not).
        case volumeRelative = 1
        /// Cross-volume fallback — absolute path + `volume_uuid`.
        case absolute = 2
    }

    /// The `project_meta` keys (OQ-2: the in-file manifest; schema version
    /// truth stays in user_version — this is the double-write face).
    public enum ProjectMetaKey {
        public static let projectName = "project_name"
        public static let createdAt = "created_at"
        public static let displayState = "display_state"  // JSON; M2-3 consumes
    }

    // MARK: - Import filter constants (OQ-12; consumed by M2-2-2 import)

    /// The default RAW extension whitelist = Alcedo 0.3.0's ten
    /// (`.3fr/.arw/.cr2/.cr3/.dng/.fff/.nef/.raf/.raw/.rw2`) ∪ Apple's
    /// four CIRAW-covered additions (`.pef/.orf/.rwl/.iiq`). Stored
    /// lowercase WITHOUT the leading dot (the `pathExtension` match form);
    /// exact-match discipline + user-configurable host = M2-2-2.
    public static let defaultRawExtensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "dng", "fff", "nef", "raf", "raw", "rw2",
        "pef", "orf", "rwl", "iiq",
    ]

    /// The HARDCODED sidecar-exclusion table (M2LIB-03 加固 AC② — NOT
    /// user-configurable; the Alcedo zero-filter defect's hardened
    /// lesson: a configurable exclusion list would let `.xmp` back in).
    /// Same lowercase no-dot spelling as the whitelist.
    public static let hardcodedSidecarExclusions: Set<String> = [
        "xmp", "lra", "lightamer-preset", "pp3", "opc",
    ]

    // MARK: - DDL (frozen)

    static let createProjectMetaTableSQL = """
        CREATE TABLE IF NOT EXISTS project_meta (
          key TEXT PRIMARY KEY,
          value TEXT
        )
        """

    static let createImagesTableSQL = """
        CREATE TABLE IF NOT EXISTS images (
          id INTEGER PRIMARY KEY,
          image_path TEXT NOT NULL,
          path_kind INTEGER NOT NULL DEFAULT 0,
          volume_uuid TEXT,
          camera_make TEXT,
          camera_model TEXT,
          lens_model TEXT,
          iso INTEGER,
          focal_length REAL,
          aperture REAL,
          exposure REAL,
          capture_date REAL,
          file_stem TEXT,
          file_ext TEXT,
          exif_search_text TEXT,
          exif_search_words TEXT,
          rating INTEGER,
          color_label INTEGER,
          keywords TEXT,
          filename TEXT,
          dir TEXT,
          flag INTEGER,
          note TEXT,
          has_edits INTEGER,
          params_hash TEXT,
          ref_count INTEGER NOT NULL DEFAULT 0,
          added_time REAL,
          modified_time REAL,
          default_look_pending INTEGER DEFAULT 0
        )
        """

    static let createAlbumsTableSQL = """
        CREATE TABLE IF NOT EXISTS albums (
          id INTEGER PRIMARY KEY,
          type TEXT NOT NULL,
          name TEXT NOT NULL,
          parent_id INTEGER REFERENCES albums(id) ON DELETE CASCADE,
          filter_data TEXT,
          added_time REAL,
          modified_time REAL
        )
        """

    static let createAlbumContentTableSQL = """
        CREATE TABLE IF NOT EXISTS album_content (
          album_id INTEGER REFERENCES albums(id) ON DELETE CASCADE,
          image_id INTEGER REFERENCES images(id) ON DELETE CASCADE,
          PRIMARY KEY (album_id, image_id)
        ) WITHOUT ROWID
        """

    /// The FTS5 external-content virtual table (KD-5). The FTS column name
    /// MUST equal the images column (`exif_search_words`) — external-content
    /// rebuild SELECTs same-named columns from the content table; a rename
    /// breaks `VALUES('rebuild')` with "no such column". Tokenizer = the
    /// DEFAULT unicode61, ZERO custom tokenchars (probe P2: registering
    /// `.-/` turns `f/2.8` into one token and the folded `f2.8` query
    /// misses — all normalization lives in the ExifFold vocabulary).
    static let createImagesFTSSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS images_fts USING fts5(
          exif_search_words, content='images', content_rowid='id',
          tokenize='unicode61')
        """

    /// The three external-content sync triggers (KD-5): the INSERT/DELETE
    /// legs map `new.`/`old.exif_search_words` VERBATIM (NULL indexes as
    /// empty — symmetric on the delete leg), the UPDATE leg fires on the
    /// words column ONLY so unrelated row updates never touch the index.
    static let createTriggerSQL: [String] = [
        """
        CREATE TRIGGER IF NOT EXISTS images_fts_ai AFTER INSERT ON images BEGIN
          INSERT INTO images_fts(rowid, exif_search_words)
          VALUES (new.id, new.exif_search_words);
        END
        """,
        """
        CREATE TRIGGER IF NOT EXISTS images_fts_ad AFTER DELETE ON images BEGIN
          INSERT INTO images_fts(images_fts, rowid, exif_search_words)
          VALUES ('delete', old.id, old.exif_search_words);
        END
        """,
        """
        CREATE TRIGGER IF NOT EXISTS images_fts_au
        AFTER UPDATE OF exif_search_words ON images BEGIN
          INSERT INTO images_fts(images_fts, rowid, exif_search_words)
          VALUES ('delete', old.id, old.exif_search_words);
          INSERT INTO images_fts(rowid, exif_search_words)
          VALUES (new.id, new.exif_search_words);
        END
        """,
    ]

    /// The two frozen indexes: the M2-2-3 keyset seek lead
    /// `(capture_date, id)` and the reverse membership lookup.
    static let createIndexSQL: [String] = [
        "CREATE INDEX IF NOT EXISTS idx_images_capture ON images(capture_date, id)",
        "CREATE INDEX IF NOT EXISTS idx_album_content_image ON album_content(image_id)",
    ]

    public static let triggerNames = [
        "images_fts_ai", "images_fts_ad", "images_fts_au",
    ]
    public static let indexNames = ["idx_images_capture", "idx_album_content_image"]

    /// The RESERVED mini-git table names (OQ-3 A: comment placeholder ONLY
    /// — the negative test pins their ABSENCE until M2-8 activates them
    /// through the KD-2 migrate seam).
    public static let reservedTableNames = [
        "edit_commit", "version_ref", "image_edit_state", "pipeline_root",
    ]

    // MARK: - user_version helpers (the schema-version truth, OQ-2)

    /// Read `PRAGMA user_version` (0 = absent/fresh).
    public static func readUserVersion(from handle: SQLiteHandle) throws -> Int {
        let statement = try handle.prepare("PRAGMA user_version")
        guard try statement.step() else { return 0 }
        return Int(statement.columnInt(0) ?? 0)
    }

    /// Stamp `PRAGMA user_version` (internal constant — never user-carried).
    public static func writeUserVersion(
        _ version: Int, to handle: SQLiteHandle
    ) throws {
        try handle.exec("PRAGMA user_version = \(version)")
    }

    // MARK: - Open / dispatch (KD-2)

    /// Apply the pragmas + DDL, then dispatch on `PRAGMA user_version`:
    /// 0 → fresh create (seed `project_meta` + stamp 1); 1 → ok; >1 →
    /// typed REFUSE BEFORE ANY WRITE (the future file stays byte-untouched
    /// — the destructive red line). Version check FIRST: unlike the
    /// session/catalog metas (absence detected via their meta tables), the
    /// user_version dispatch can refuse without touching a single page.
    public static func apply(
        to handle: SQLiteHandle, projectName: String? = nil
    ) throws {
        // WAL first (persistent journal mode) + NORMAL (NOT OFF — the
        // dirty-marker crash-safety rationale carries over) + FK enforcement
        // (the CASCADE semantics above are per-connection).
        try handle.execute("PRAGMA journal_mode=WAL")
        try handle.execute("PRAGMA synchronous=NORMAL")
        try handle.execute("PRAGMA foreign_keys=ON")

        let stored = try readUserVersion(from: handle)
        guard stored <= schemaVersion else {
            throw LibraryError.futureSchema(version: stored)
        }

        try handle.execute(createProjectMetaTableSQL)
        try handle.execute(createImagesTableSQL)
        try handle.execute(createAlbumsTableSQL)
        try handle.execute(createAlbumContentTableSQL)
        try handle.execute(createImagesFTSSQL)
        for sql in createTriggerSQL { try handle.execute(sql) }
        for sql in createIndexSQL { try handle.execute(sql) }

        if stored == 0 {
            // Fresh create: seed the manifest (name when provided,
            // created_at always) + stamp the version.
            try seedProjectMeta(
                on: handle, projectName: projectName,
                createdAt: Date().timeIntervalSince1970)
            try writeUserVersion(schemaVersion, to: handle)
        }
    }

    /// Seed the `project_meta` manifest rows (fresh-create leg).
    static func seedProjectMeta(
        on handle: SQLiteHandle, projectName: String?, createdAt: Double
    ) throws {
        var rows: [(String, String)] = [
            (ProjectMetaKey.createdAt, String(createdAt)),
            (ProjectMetaKey.displayState, "{}"),
        ]
        if let projectName { rows.insert(
            (ProjectMetaKey.projectName, projectName), at: 0) }
        let insert = try handle.prepare(
            "INSERT OR REPLACE INTO project_meta (key, value) VALUES (?, ?)")
        for (key, value) in rows {
            try insert.reset()
            try insert.bindText(1, key)
            try insert.bindText(2, value)
            _ = try insert.step()
        }
    }

    /// The migration slots (KD-6, checker E6): ONE `BEGIN IMMEDIATE`,
    /// ROLLBACK on failure, the original file untouched. The v1→v2 slot
    /// (FIRST migration) adds the `images.default_look_pending` column —
    /// IDEMPOTENT (`ALTER TABLE ADD COLUMN` guarded by a column-existence
    /// probe; a partially-migrated snapshot re-runs clean). The
    /// PRE-migration automatic `sqlite3_backup` snapshot lives at the
    /// ProjectFileStore dispatch (its dead-at-v1 pin became LIVE with this
    /// migration — the hook's first consumer).
    public static func migrate(
        from: Int, to: Int, on handle: SQLiteHandle
    ) throws {
        try handle.exec("BEGIN IMMEDIATE")
        do {
            if from <= 1 && to >= 2 {
                try addImagesDefaultLookPendingColumn(on: handle)
            }
            try writeUserVersion(to, to: handle)
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw LibraryError.migrationFailed(
                detail: "library schema migration \(from)→\(to) failed")
        }
    }

    /// The v1→v2 additive column (append-only; every frozen column's
    /// position/DDL is untouched). Idempotent: a `PRAGMA table_info` probe
    /// skips the ALTER when the column already exists.
    static func addImagesDefaultLookPendingColumn(on handle: SQLiteHandle) throws {
        let probe = try handle.prepare("PRAGMA table_info(images)")
        while try probe.step() {
            if probe.columnText(1) == "default_look_pending" { return }
        }
        try handle.exec(
            "ALTER TABLE images ADD COLUMN default_look_pending INTEGER DEFAULT 0")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESERVED FOR M2-8 (OQ-3 A — comment placeholder, NO entity tables):
//
// The Alcedo mini-git history family, transcribed for schema-stability
// planning. Activation order: M2-4 (node model) must stabilize the edit
// pipeline FIRST; M2-8 then activates these through the KD-2 migrate seam
// (pre-migration automatic `sqlite3_backup` snapshot → table-driven
// migration). Until then the `.lalb` carries only the `has_edits`/
// `params_hash` PROJECTION columns — the `.lra` sidecar stays the
// edit-state truth (the phase's architecture red line).
//
//   edit_commit(
//     commit_hash TEXT PRIMARY KEY,        -- immutable commit graph node
//     root_id INTEGER,                     // → pipeline_root
//     first_parent_hash TEXT,              -- NULL = root commit
//     second_parent_hash TEXT,             -- non-NULL = branch/merge point
//     created_at_ns INTEGER,
//     kind TEXT,                           -- adjust / version-create / …
//     edit_payload TEXT)                   -- JSON
//
//   version_ref(
//     version_id INTEGER PRIMARY KEY,
//     element_id INTEGER,                  // → images.id
//     display_name TEXT,                   -- "暖调" / "黑白" …
//     head_commit_hash TEXT,
//     created_at_unix INTEGER,
//     updated_at_unix INTEGER)
//
//   image_edit_state(
//     element_id INTEGER PRIMARY KEY,      // → images.id
//     root_id INTEGER,
//     active_version_id INTEGER,
//     materialized_head_commit_hash TEXT,
//     materialized_transaction_chain_hash TEXT,
//     serialized_pipeline_state TEXT)      -- JSON; materialization cache,
//                                          -- NOT a user concept
//
//   pipeline_root(
//     root_id INTEGER PRIMARY KEY,
//     element_id INTEGER UNIQUE,           // → images.id
//     serialized_pipeline_state TEXT)      -- JSON (Develop → Color Grade×N
//                                          -- → Display Transform node graph)
// ─────────────────────────────────────────────────────────────────────────────
