import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySchema (Plan M2-2-1 T1; OQ-2/3/6/7/10/12 rulings) — the FROZEN v1
// `.lalb` spelling: the single-SQLite-file project package's DDL face.
//
// FREEZE CONTRACT: `schemaVersion` (now 4; v1-born, additive through
// v2/v3/v4 — see `schemaVersion`'s notes), truth = `PRAGMA user_version`
// (OQ-2 字面 — the manifest double-write goes to `project_meta` but the READ side
// dispatches on user_version). Dispatch: absent/0 → fresh create (current
// version) + seed `project_meta` + stamp N; 0 < stored ≤ N → ok (stored < N
// migrates, ONE `migrate(from:to:)` walking every leg); >N → typed REFUSE
// (`LibraryError.futureSchema` — this binary predates the file; never guess
// at a future schema). The migrate slot is SHAPE-pinned (the v1 note below): any future N→N+1
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
    ///
    /// M2-8-1 (KD-3): v2 → v3 = the SECOND migration — the `version_ref`
    /// PROJECTION table activates (D-M2-8-CONTEXT-1-A: the `.lra` sidecar
    /// stays the version TRUTH; this table is a rebuildable mirror written
    /// through `LibraryStore.replaceVersionRefs` whole-table reconcile).
    /// The DDL is the REDUCED spelling — the reserved sketch's
    /// `head_commit_hash` column is NOT activated (OQ-2-A: no DAG, no commit
    /// hash to write; the reserved comment block at the file tail carries the
    /// deviation note). Idempotent `CREATE IF NOT EXISTS` twice over (table +
    /// index), so a partially-migrated snapshot re-runs clean.
    ///
    /// M2-10-02 (KD-1): v3 → v4 = the THIRD migration — the AI-library
    /// SEVEN-TABLE family activates (D-M2-10-CONTEXT-2: `semantic_model` /
    /// `image_embedding` / `image_label` / `label_query` / `ai_understanding`
    /// + `ai_understanding_fts` / `ai_rating`). PURE ADDITIVE — zero column
    /// changes on any existing table, CASCADE follows `images`. The single
    /// active semantic model is a DB-level invariant (OQ-9-A: partial UNIQUE
    /// index on `active WHERE active = 1`). Embeddings ride fp16 BLOBs
    /// (`dim*2` bytes, native endian); retrieval scans them through the
    /// SemanticEngine's vDSP full sweep (D-M2-10-CONTEXT-1: sqlite-vec stays
    /// the escape hatch, the SCHEMA never changes for it).
    ///
    /// M6-4-01 (KD-1): v4 → v5 = the FOURTH migration — the photo STACK
    /// family activates (OQ-M6-4-1 = A): `stacks` + `stack_content` (the
    /// WITHOUT ROWID join, album_content/version_ref precedent form) + the
    /// UNIQUE `idx_stack_content_image` (the one-image-one-stack invariant
    /// is DB-LEVEL — LightCraft validate rule 3 SQL-ized). PURE ADDITIVE —
    /// zero column changes on any existing table, zero backfill (stacks
    /// start EMPTY), CASCADE follows both `stacks` and `images`. The cover
    /// is NOT a column: cover = the position-0 member (LightCraft
    /// `photos[0]` isomorph — single truth). `stacks` is an ACTIVATED
    /// entity table — it never enters `reservedTableNames` (that sketch
    /// stays the three mini-git names). Old packages open through the
    /// ProjectFileStore dispatch (pre-migration `sqlite3_backup` snapshot →
    /// the v4→v5 slot below).
    ///
    /// LUMEN-A T1 (X1): v5 → v6 = the FIFTH migration — the CULLING
    /// ANALYSIS seven-column family activates on `images`
    /// (D-LU-5/D-LU-10, RESEARCH §UQ-LU2 seam 1): `analysis_version`
    /// (the ANAYLSIS stamp — `LibraryAnalysisService.analysisVersion`,
    /// older results recompute) + `sharpness` + `faces` + `eyes_closed` +
    /// `signature` (16×16 BLOB) + `face_boxes` (JSON) + `camera_serial`
    /// (LU1 burst grouping key). PURE ADDITIVE — frozen column
    /// positions/spellings untouched, ZERO backfill (the analysis pass
    /// fills lazily; rows read NULL = un-analysed = the default-neutral
    /// face), zero new tables/indexes/triggers (the futureSchema refuse
    /// enumeration stays undisturbed — no column was changed, only added).
    /// Old packages open through the ProjectFileStore dispatch
    /// (pre-migration `sqlite3_backup` snapshot → the v5→v6 slot below →
    /// the idempotent per-column probe ALTER — the `default_look_pending`
    /// :899 precedent, seven columns wide).
    public static let schemaVersion = 6

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
        ("analysis_version", "INTEGER"),     // LUMEN-A T1 (X1): culling-analysis stamp (NULL = un-analysed; < current → recompute)
        ("sharpness", "REAL"),               // SharpnessAnalyzer 0-100 (NULL = un-analysed)
        ("faces", "INTEGER"),                // counted face boxes (NULL = un-analysed)
        ("eyes_closed", "INTEGER"),          // faces with max(right,left) eye opening below threshold (NULL = un-analysed)
        ("signature", "BLOB"),               // Signature16: 16x16 greyscale, 256 bytes (NULL = un-analysed)
        ("face_boxes", "TEXT"),              // JSON [[x,y,w,h,closed]] normalized 0-1 (NULL = un-analysed)
        ("camera_serial", "TEXT"),           // EXIF BodySerialNumber (LU1 burst grouping key; NULL = unindexed/absent)
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

    /// The TIFF-family import extensions (M4-1-02 T5, OQ-5): hardcoded and
    /// ORTHOGONAL to the RAW whitelist — never mixed into
    /// `defaultRawExtensions` (the RAW whitelist semantics stay
    /// byte-identical; the category mask is the TIFF family's only gate).
    public static let tiffRasterExtensions: Set<String> = ["tif", "tiff"]

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
          default_look_pending INTEGER DEFAULT 0,
          analysis_version INTEGER,
          sharpness REAL,
          faces INTEGER,
          eyes_closed INTEGER,
          signature BLOB,
          face_boxes TEXT,
          camera_serial TEXT
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

    /// The `version_ref` PROJECTION table (Plan M2-8-1 KD-3; activated from
    /// the M2-2 reserved sketch with a REDUCED column set — see
    /// `schemaVersion`'s v3 note). `version_id` is the `.lra` version UUID
    /// STRING (the `.lra`↔`.lalb` join key — L013's decimal rule does not
    /// apply: no hash columns). Both foreign legs cascade with the images
    /// row (the KD-4 DDL-declared semantics). The version TRUTH stays in
    /// the `.lra`; this table is rebuilt wholesale through
    /// `LibraryStore.replaceVersionRefs` (idempotent, no incremental
    /// drift face).
    static let createVersionRefTableSQL = """
        CREATE TABLE IF NOT EXISTS version_ref (
          version_id TEXT PRIMARY KEY,
          element_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
          display_name TEXT NOT NULL,
          created_at_unix INTEGER NOT NULL,
          updated_at_unix INTEGER NOT NULL
        )
        """

    /// The version_ref reverse lookup (per-image version list).
    static let createVersionRefIndexSQL =
        "CREATE INDEX IF NOT EXISTS idx_version_ref_element ON version_ref(element_id)"

    /// The version_ref columns IN ORDER (the reduced-DDL freeze face; the
    /// LibrarySchemaTests column pin reads this).
    public static let versionRefColumns: [(name: String, type: String)] = [
        ("version_id", "TEXT"),              // PK — the .lra version UUID string
        ("element_id", "INTEGER"),           // FK → images.id ON DELETE CASCADE
        ("display_name", "TEXT"),            // "版本 1" … (the .lra record's name)
        ("created_at_unix", "INTEGER"),      // epoch seconds (the .lra record's)
        ("updated_at_unix", "INTEGER"),      // epoch seconds (the .lra record's)
    ]

    // MARK: - Photo stacks (M6-4-01 KD-1; OQ-M6-4-1 = A)

    /// The `stacks` table (v5): one row per photo stack. `collapsed` is the
    /// per-stack display flag (the grid's collapsed predicate folds it
    /// through the join); `added_time`/`modified_time` = epoch REAL (the
    /// albums-row convention) — every write path stamps `modified_time`.
    static let createStacksTableSQL = """
        CREATE TABLE IF NOT EXISTS stacks (
          id INTEGER PRIMARY KEY,
          collapsed INTEGER NOT NULL DEFAULT 0,
          added_time REAL,
          modified_time REAL
        )
        """

    /// The `stack_content` membership join (v5 — the album_content
    /// WITHOUT-ROWID precedent form). `position` is DENSE 0..n−1 (the store
    /// renumbers on every write path, ONE transaction); **position 0 IS the
    /// cover** — no cover column (LightCraft `photos[0]` isomorph, single
    /// truth). Both FK legs CASCADE: stack delete → memberships gone;
    /// image delete → memberships gone (the store sweeps the <2 remainder
    /// in the SAME transaction, KD-2).
    static let createStackContentTableSQL = """
        CREATE TABLE IF NOT EXISTS stack_content (
          stack_id INTEGER REFERENCES stacks(id) ON DELETE CASCADE,
          image_id INTEGER REFERENCES images(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          PRIMARY KEY (stack_id, image_id)
        ) WITHOUT ROWID
        """

    /// The one-image-one-stack invariant, DB-LEVEL (OQ-M6-4-1: LightCraft
    /// validate rule 3 SQL-ized) + the stack-of reverse lookup seat. The
    /// store's pre-checks give READABLE typed errors; this index is the
    /// race-proof backstop.
    static let createStackContentImageIndexSQL =
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_stack_content_image"
            + " ON stack_content(image_id)"

    /// The `stacks` columns IN ORDER (the v5 freeze face; the
    /// LibrarySchemaV5Tests column pin reads this).
    public static let stacksColumns: [(name: String, type: String)] = [
        ("id", "INTEGER"),                   // PK — rowid alias
        ("collapsed", "INTEGER"),            // 0/1 per-stack display flag
        ("added_time", "REAL"),              // epoch REAL (albums convention)
        ("modified_time", "REAL"),           // stamped on every write path
    ]

    /// The `stack_content` columns IN ORDER (the v5 freeze face).
    public static let stackContentColumns: [(name: String, type: String)] = [
        ("stack_id", "INTEGER"),             // PK half — FK → stacks.id CASCADE
        ("image_id", "INTEGER"),             // PK half — FK → images.id CASCADE
        ("position", "INTEGER"),             // dense 0..n−1; 0 = the cover
    ]

    /// The v5 family's three CREATE statements (KD-1 spelling VERBATIM; the
    /// migrate slot AND the fresh-create path share them — both idempotent).
    static let createStackTableSQL: [String] = [
        createStacksTableSQL, createStackContentTableSQL,
        createStackContentImageIndexSQL,
    ]

    // MARK: - AI-library semantic tables (M2-10-02 KD-1; D-M2-10-CONTEXT-2)

    /// The `semantic_model` columns IN ORDER (the v4 freeze face). One row
    /// per model asset profile that ever produced embeddings in THIS package
    /// (`model_key` = the `ModelAssetManifest.profileID` spelling); `active`
    /// = the OQ-9-A single-activation invariant, DB-enforced by the partial
    /// unique index below. `prompt_config_hash` is CLIP-family NULL (no
    /// rubric) — the column position is reserved verbatim from D-2.
    public static let semanticModelColumns: [(name: String, type: String)] = [
        ("model_key", "TEXT"),               // PK — asset profileID (01 Catalog)
        ("model_id", "TEXT"),                // upstream model repo id
        ("revision", "TEXT"),                // upstream revision pin
        ("embedding_dim", "INTEGER"),        // 512/768 (manifest source)
        ("image_size", "INTEGER"),           // vision-tower input edge (224)
        ("prompt_config_hash", "TEXT"),      // CLIP NULL; column position = D-2 literal
        ("active", "INTEGER"),               // 0/1 — partial UNIQUE at 1
    ]

    /// The `image_embedding` columns IN ORDER. BLOB = fp16 bytes, NATIVE
    /// endian, `dim*2` long (single-machine app — no cross-endian exchange
    /// semantics; DECISIONS pins the posture). PK (image_id, model_key) keeps
    /// the换档重算 coexistence space; `dim` is stamped per row so a scan can
    /// validate before converting.
    public static let imageEmbeddingColumns: [(name: String, type: String)] = [
        ("image_id", "INTEGER"),             // PK half — FK → images.id CASCADE
        ("model_key", "TEXT"),               // PK half — semantic_model.model_key
        ("dim", "INTEGER"),                  // vector width (== semantic_model.embedding_dim)
        ("embedding", "BLOB"),               // fp16 native-endian, dim*2 bytes
        ("computed_time", "INTEGER"),        // epoch seconds (recompute stamp)
    ]

    /// The `image_label` columns IN ORDER (Alcedo `SemanticImageLabel`
    /// same-shape; M2-10-03 writes, this plan freezes the face).
    public static let imageLabelColumns: [(name: String, type: String)] = [
        ("image_id", "INTEGER"),             // PK half — FK → images.id CASCADE
        ("model_key", "TEXT"),               // PK half
        ("label", "TEXT"),                   // PK half
        ("score", "REAL"),                   // prototype cosine of THIS label
        ("second_label", "TEXT"),            // runner-up (margin source)
        ("second_score", "REAL"),
        ("margin", "REAL"),                  // score − second_score
        ("confident", "INTEGER"),            // 0/1 threshold flag
        ("top_scores", "TEXT"),              // JSON [{"label":…,"score":…}] top 8
    ]

    /// The `label_query` columns IN ORDER (the factory zh/en query text;
    /// prototype EMBEDDINGS never enter the DB — D-M2-10-CONTEXT-7).
    public static let labelQueryColumns: [(name: String, type: String)] = [
        ("model_key", "TEXT"),               // PK half
        ("label", "TEXT"),                   // PK half
        ("query_text", "TEXT"),              // the factory query
        ("lang", "TEXT"),                    // PK half — "zh"/"en"
    ]

    /// The `ai_understanding` columns IN ORDER. `id INTEGER PRIMARY KEY` is
    /// the FTS external-content `content_rowid` carrier (`images_fts` same
    /// mechanism); `UNIQUE(image_id, task_id)` carries the reconcile upsert
    /// (re-run = old row active=0, new row active=1, in ONE transaction).
    public static let aiUnderstandingColumns: [(name: String, type: String)] = [
        ("id", "INTEGER"),                   // PK — FTS content_rowid carrier
        ("image_id", "INTEGER"),             // FK → images.id ON DELETE CASCADE
        ("task_id", "TEXT"),                 // registry task (M2AI-07)
        ("provider_id", "TEXT"),             // M2AI-06 provider
        ("model_id", "TEXT"),                // remote model name
        ("prompt_profile_id", "TEXT"),       // FNV-1a DECIMAL String (L013)
        ("rendition_kind", "TEXT"),          // 'edited' default (D-2)
        ("caption", "TEXT"),                 // FTS document column
        ("tags", "TEXT"),                    // JSON array — FTS document column
        ("scene", "TEXT"),
        ("confidence", "REAL"),
        ("active", "INTEGER"),               // re-run flips old rows to 0
        ("computed_time", "INTEGER"),
    ]

    /// The `ai_rating` columns IN ORDER (append-only history; `rating` 0 =
    /// the reasons-only sentinel, 1-5 = real stars — D-M2-10-CONTEXT-4).
    public static let aiRatingColumns: [(name: String, type: String)] = [
        ("id", "INTEGER"),                   // PK — rowid
        ("image_id", "INTEGER"),             // FK → images.id ON DELETE CASCADE
        ("task_id", "TEXT"),
        ("provider_id", "TEXT"),
        ("model_id", "TEXT"),
        ("prompt_profile_id", "TEXT"),
        ("rating", "INTEGER"),               // 0 sentinel / 1-5 stars
        ("reasons", "TEXT"),                 // JSON array
        ("computed_time", "INTEGER"),
    ]

    /// The seven CREATE TABLE statements (KD-1 spelling VERBATIM; the
    /// migrate slot AND the fresh-create path share them — both idempotent).
    static let createSemanticTableSQL: [String] = [
        // OQ-9-A: the single active model, DB-level (partial unique index).
        """
        CREATE TABLE IF NOT EXISTS semantic_model (
          model_key TEXT PRIMARY KEY,
          model_id TEXT NOT NULL,
          revision TEXT NOT NULL,
          embedding_dim INTEGER NOT NULL,
          image_size INTEGER NOT NULL,
          prompt_config_hash TEXT,
          active INTEGER NOT NULL DEFAULT 0
        )
        """,
        // M10: idx_image_embedding_model (below) covers the loadScanRows
        // modelKey-prefix full sweep — the PK (image_id, model_key) does NOT.
        """
        CREATE TABLE IF NOT EXISTS image_embedding (
          image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
          model_key TEXT NOT NULL,
          dim INTEGER NOT NULL,
          embedding BLOB NOT NULL,
          computed_time INTEGER NOT NULL,
          PRIMARY KEY(image_id, model_key)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS image_label (
          image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
          model_key TEXT NOT NULL,
          label TEXT NOT NULL,
          score REAL NOT NULL,
          second_label TEXT,
          second_score REAL,
          margin REAL,
          confident INTEGER NOT NULL,
          top_scores TEXT,
          PRIMARY KEY(image_id, model_key, label)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS label_query (
          model_key TEXT NOT NULL,
          label TEXT NOT NULL,
          query_text TEXT NOT NULL,
          lang TEXT NOT NULL,
          PRIMARY KEY(model_key, label, lang)
        )
        """,
        // `id INTEGER PRIMARY KEY` = the FTS content_rowid carrier; the
        // UNIQUE pair carries the reconcile upsert (KD-2).
        """
        CREATE TABLE IF NOT EXISTS ai_understanding (
          id INTEGER PRIMARY KEY,
          image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
          task_id TEXT NOT NULL,
          provider_id TEXT NOT NULL,
          model_id TEXT NOT NULL,
          prompt_profile_id TEXT NOT NULL,
          rendition_kind TEXT NOT NULL DEFAULT 'edited',
          caption TEXT,
          tags TEXT,
          scene TEXT,
          confidence REAL,
          active INTEGER NOT NULL DEFAULT 1,
          computed_time INTEGER NOT NULL,
          UNIQUE(image_id, task_id)
        )
        """,
        // Append-only rating history (D-4: 0 = reasons-only sentinel).
        """
        CREATE TABLE IF NOT EXISTS ai_rating (
          id INTEGER PRIMARY KEY,
          image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
          task_id TEXT NOT NULL,
          provider_id TEXT NOT NULL,
          model_id TEXT NOT NULL,
          prompt_profile_id TEXT NOT NULL,
          rating INTEGER NOT NULL,
          reasons TEXT,
          computed_time INTEGER NOT NULL
        )
        """,
    ]

    /// The `ai_understanding_fts` external-content virtual table (the
    /// `images_fts` :306 precedent, two document columns). Checker E5
    /// contract: the index is row-synchronous with NO active concept — with
    /// multiple rows per image, active=0 history rows REMAIN in the index;
    /// MATCH consumers (M2-10-04 fulltext leg) MUST JOIN `ai_understanding`
    /// and filter `active = 1`.
    static let createUnderstandingFTSSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS ai_understanding_fts USING fts5(
          caption, tags, content='ai_understanding', content_rowid='id',
          tokenize='unicode61')
        """

    /// The three external-content sync triggers (the images_fts :316 shape,
    /// two-column mapping). The UPDATE leg fires on the DOCUMENT columns
    /// only — an `active=0` flip (the reconcile's stage leg) never touches
    /// the index.
    static let createUnderstandingTriggerSQL: [String] = [
        """
        CREATE TRIGGER IF NOT EXISTS ai_understanding_fts_ai
        AFTER INSERT ON ai_understanding BEGIN
          INSERT INTO ai_understanding_fts(rowid, caption, tags)
          VALUES (new.id, new.caption, new.tags);
        END
        """,
        """
        CREATE TRIGGER IF NOT EXISTS ai_understanding_fts_ad
        AFTER DELETE ON ai_understanding BEGIN
          INSERT INTO ai_understanding_fts(ai_understanding_fts, rowid, caption, tags)
          VALUES ('delete', old.id, old.caption, old.tags);
        END
        """,
        """
        CREATE TRIGGER IF NOT EXISTS ai_understanding_fts_au
        AFTER UPDATE OF caption, tags ON ai_understanding BEGIN
          INSERT INTO ai_understanding_fts(ai_understanding_fts, rowid, caption, tags)
          VALUES ('delete', old.id, old.caption, old.tags);
          INSERT INTO ai_understanding_fts(rowid, caption, tags)
          VALUES (new.id, new.caption, new.tags);
        END
        """,
    ]

    /// The four v4 indexes: the OQ-9-A single-activation invariant (partial
    /// UNIQUE at 1), the M10 scan-sweep prefix, and the two per-image
    /// latest-lookup legs.
    static let createSemanticIndexSQL: [String] = [
        """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_semantic_model_active
          ON semantic_model(active) WHERE active = 1
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_image_embedding_model
          ON image_embedding(model_key)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_ai_understanding_image
          ON ai_understanding(image_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_ai_rating_image
          ON ai_rating(image_id)
        """,
    ]

    public static let triggerNames = [
        "images_fts_ai", "images_fts_ad", "images_fts_au",
        "ai_understanding_fts_ai", "ai_understanding_fts_ad",
        "ai_understanding_fts_au",
    ]
    public static let indexNames = [
        "idx_images_capture", "idx_album_content_image",
        "idx_semantic_model_active", "idx_image_embedding_model",
        "idx_ai_understanding_image", "idx_ai_rating_image",
        "idx_stack_content_image",
    ]

    /// The still-RESERVED mini-git table names (OQ-2-A: comment placeholder
    /// ONLY — the negative test pins their ABSENCE). `version_ref` LEFT the
    /// set in M2-8-1 (activated as a projection table); `edit_commit`/
    /// `image_edit_state`/`pipeline_root` stay reserved (no DAG, no
    /// materialization — D-M2-8-CONTEXT-2/5).
    public static let reservedTableNames = [
        "edit_commit", "image_edit_state", "pipeline_root",
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
    /// 0 → fresh create (seed `project_meta` + stamp N); 0 < stored ≤ N →
    /// ok; >N → typed REFUSE BEFORE ANY WRITE (the future file stays
    /// byte-untouched — the destructive red line). Version check FIRST:
    /// unlike the session/catalog metas (absence detected via their meta
    /// tables), the user_version dispatch can refuse without touching a
    /// single page.
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
        // M2-8-1 (KD-3): the version_ref projection joins the fresh DDL —
        // a v3 fresh create carries the table from birth.
        try handle.execute(createVersionRefTableSQL)
        try handle.execute(createVersionRefIndexSQL)
        // M2-10-02 (KD-1): the AI-library seven-table family joins the fresh
        // DDL — a v4 fresh create carries all of it from birth (tables +
        // the understanding FTS + its three triggers + the four indexes).
        for sql in createSemanticTableSQL { try handle.execute(sql) }
        try handle.execute(createUnderstandingFTSSQL)
        for sql in createUnderstandingTriggerSQL { try handle.execute(sql) }
        for sql in createSemanticIndexSQL { try handle.execute(sql) }
        // M6-4-01 (KD-1): the stack family joins the fresh DDL — a v5 fresh
        // create carries both tables + the UNIQUE index from birth.
        for sql in createStackTableSQL { try handle.execute(sql) }

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
    /// adds the `images.default_look_pending` column — IDEMPOTENT
    /// (`ALTER TABLE ADD COLUMN` guarded by a column-existence probe; a
    /// partially-migrated snapshot re-runs clean). The v2→v3 slot (M2-8-1
    /// KD-3) creates the `version_ref` projection table + index —
    /// IDEMPOTENT twice over (`CREATE IF NOT EXISTS`; the same partial-
    /// snapshot re-run guarantee). The v3→v4 slot (M2-10-02 KD-1) creates
    /// the seven AI-library tables + FTS + triggers + indexes — IDEMPOTENT
    /// three times over (every statement `CREATE IF NOT EXISTS`); the
    /// ProjectFileStore dispatch issues ONE `migrate(from:stored, to:)` per
    /// open, so a v1 package walks ALL legs (1→2→3→4→5) inside this single
    /// call and a single transaction. The v4→v5 slot (M6-4-01 KD-1) creates
    /// the two stack tables + the UNIQUE image index — IDEMPOTENT four
    /// times over. The v5→v6 slot (LUMEN-A T1, X1) adds the seven culling
    /// analysis columns — IDEMPOTENT five times over (a per-column
    /// `PRAGMA table_info` probe skips existing ALTERs; a partially-migrated
    /// snapshot re-runs clean). The PRE-migration automatic
    /// `sqlite3_backup` snapshot lives at the ProjectFileStore dispatch
    /// (the hook's consumers: the v1→v2 first migration, the v2 packages
    /// since M2-8-1, and — since M2-10-02 — every ≤v3 package opening under
    /// a v4 binary; the hook ROTATES its snapshots, see ProjectFileStore).
    public static func migrate(
        from: Int, to: Int, on handle: SQLiteHandle
    ) throws {
        try handle.exec("BEGIN IMMEDIATE")
        do {
            if from <= 1 && to >= 2 {
                try addImagesDefaultLookPendingColumn(on: handle)
            }
            if from <= 2 && to >= 3 {
                try createVersionRefTable(on: handle)
            }
            if from <= 3 && to >= 4 {
                try createSemanticTables(on: handle)
            }
            if from <= 4 && to >= 5 {
                try createStackTables(on: handle)
            }
            if from <= 5 && to >= 6 {
                try addCullingAnalysisColumns(on: handle)
            }
            try writeUserVersion(to, to: handle)
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw LibraryError.migrationFailed(
                detail: "library schema migration \(from)→\(to) failed")
        }
    }

    /// The v3→v4 additive AI-library family (M2-10-02 KD-1). Idempotent:
    /// every DDL statement is `CREATE IF NOT EXISTS` (tables, the FTS
    /// virtual table, its three triggers, the four indexes), so a
    /// partially-migrated snapshot re-runs clean (the v2→v3 slot's same
    /// discipline, one generation on).
    static func createSemanticTables(on handle: SQLiteHandle) throws {
        for sql in createSemanticTableSQL { try handle.execute(sql) }
        try handle.execute(createUnderstandingFTSSQL)
        for sql in createUnderstandingTriggerSQL { try handle.execute(sql) }
        for sql in createSemanticIndexSQL { try handle.execute(sql) }
    }

    /// The v2→v3 additive projection table (M2-8-1 KD-3). Idempotent: the
    /// DDL is `CREATE IF NOT EXISTS` on both the table and the index, so a
    /// partially-migrated snapshot re-runs clean (the default_look_pending
    /// probe slot's same discipline).
    static func createVersionRefTable(on handle: SQLiteHandle) throws {
        try handle.execute(createVersionRefTableSQL)
        try handle.execute(createVersionRefIndexSQL)
    }

    /// The v4→v5 additive stack family (M6-4-01 KD-1). Idempotent FOUR
    /// times over: every statement (two tables + the UNIQUE index) is
    /// `CREATE IF NOT EXISTS`, so a partially-migrated snapshot re-runs
    /// clean (the v2→v3 slot's same discipline, two generations on).
    static func createStackTables(on handle: SQLiteHandle) throws {
        for sql in createStackTableSQL { try handle.execute(sql) }
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

    /// The v5→v6 additive culling-analysis family (LUMEN-A T1, X1). Every
    /// column gets its OWN `PRAGMA table_info` probe — a partially-migrated
    /// snapshot (some columns landed, then the process died) re-runs the
    /// missing ones and skips the landed ones clean. No DEFAULT, no NOT
    /// NULL: the analysis pass fills lazily, so NULL IS the un-analysed
    /// semantic (the zero-backfill red line).
    static func addCullingAnalysisColumns(on handle: SQLiteHandle) throws {
        let additive: [(name: String, ddl: String)] = [
            ("analysis_version", "ALTER TABLE images ADD COLUMN analysis_version INTEGER"),
            ("sharpness", "ALTER TABLE images ADD COLUMN sharpness REAL"),
            ("faces", "ALTER TABLE images ADD COLUMN faces INTEGER"),
            ("eyes_closed", "ALTER TABLE images ADD COLUMN eyes_closed INTEGER"),
            ("signature", "ALTER TABLE images ADD COLUMN signature BLOB"),
            ("face_boxes", "ALTER TABLE images ADD COLUMN face_boxes TEXT"),
            ("camera_serial", "ALTER TABLE images ADD COLUMN camera_serial TEXT"),
        ]
        var present: Set<String> = []
        let probe = try handle.prepare("PRAGMA table_info(images)")
        while try probe.step() {
            if let name = probe.columnText(1) { present.insert(name) }
        }
        for column in additive where !present.contains(column.name) {
            try handle.exec(column.ddl)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESERVED FOR M2-8/M2-10 (OQ-2/3 A — comment placeholder, NO entity tables
// EXCEPT version_ref, ACTIVATED in M2-8-1):
//
// The Alcedo mini-git history family, transcribed for schema-stability
// planning. M2-4 (node model) stabilized the edit pipeline; M2-8-1 then
// activated version_ref through the KD-2 migrate seam (pre-migration
// automatic `sqlite3_backup` snapshot → table-driven migration). The
// `.lalb` still carries only PROJECTION/RESERVATION state — the `.lra`
// sidecar stays the edit-state truth (the phase's architecture red line).
//
//   version_ref — ACTIVATED M2-8 (REDUCED DDL; see createVersionRefTableSQL):
//     version_id TEXT PRIMARY KEY,         -- the .lra version UUID STRING
//     element_id INTEGER NOT NULL,         // → images.id CASCADE
//     display_name TEXT NOT NULL,
//     created_at_unix INTEGER NOT NULL,
//     updated_at_unix INTEGER NOT NULL
//   DEVIATION vs the sketch below: `head_commit_hash` is NOT a column —
//   OQ-2-A ruled v1 versions = independent linear chains, NO commit DAG,
//   so there is no hash to write. The column may join additively if a
//   future OQ reopens the DAG world.
//
//   edit_commit(                          -- still RESERVED (no DAG in v1)
//     commit_hash TEXT PRIMARY KEY,        -- immutable commit graph node
//     root_id INTEGER,                     // → pipeline_root
//     first_parent_hash TEXT,              -- NULL = root commit
//     second_parent_hash TEXT,             -- non-NULL = branch/merge point
//     created_at_ns INTEGER,
//     kind TEXT,                           -- adjust / version-create / …
//     edit_payload TEXT)                   -- JSON
//
//   image_edit_state(                     -- still RESERVED (D5: no落库
//     element_id INTEGER PRIMARY KEY,      //   materialization — the active
//     root_id INTEGER,                     //   chain lives in memory + the
//     active_version_id INTEGER,           //   .lra; param replay is the
//     materialized_head_commit_hash TEXT,  //   switch-immediacy answer)
//     materialized_transaction_chain_hash TEXT,
//     serialized_pipeline_state TEXT)      -- JSON; materialization cache,
//                                          -- NOT a user concept
//
//   pipeline_root(                        -- still RESERVED
//     root_id INTEGER PRIMARY KEY,
//     element_id INTEGER UNIQUE,           // → images.id
//     serialized_pipeline_state TEXT)      -- JSON (Develop → Color Grade×N
//                                          -- → Display Transform node graph)
// ─────────────────────────────────────────────────────────────────────────────
