import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySchemaTests (Plan M2-2-1 T1) — the `.lalb` freeze contract:
//
//   • three entity tables + project_meta + the FTS5 virtual table, fresh;
//     `images` 29 columns / `albums` 7 / `album_content` 2 — VERBATIM
//     (order IS the freeze, KD-3's complete enumeration; M2-5-2 KD-6
//     appended default_look_pending at the tail — v2, the first migration)
//   • fresh create: user_version == 4 + project_meta seeded (name/created_at)
//     (M2-8-1: the version_ref projection joins the fresh DDL; M2-10-02:
//     the AI-library seven-table family joins it too)
//   • images_fts: external-content over images, content_rowid='id',
//     tokenize='unicode61' (ZERO custom tokenchars), FTS column name ==
//     `exif_search_words` (KD-5 rebuild dependency); the three sync
//     triggers registered with the `new.exif_search_words` mapping
//   • the frozen indexes (idx_images_capture / idx_album_content_image +
//     the four v4 semantic indexes)
//   • version_ref EXISTS with the reduced-DDL column order (M2-8-1 KD-3
//     activated the projection — the negative pin FLIPPED for this one
//     name); the other three reserved mini-git tables DO NOT exist
//   • the seven v4 semantic tables exist with the KD-1 column order, the
//     understanding FTS carries its three triggers, and the OQ-9-A single
//     active model is DB-enforced (partial UNIQUE at 1) (M2-10-02 KD-1)
//   • foreign_keys pragma is ON after apply (the CASCADE semantics are
//     declared DDL, KD-4); second apply is idempotent
//   • user_version >4 → typed `.futureSchema` REFUSE
//   • the OQ-12 import constants: 14-extension RAW whitelist (exact set),
//     the five hardcoded sidecar exclusions
//
// Fixtures in NSTemporaryDirectory (L009: never external volume).
// ─────────────────────────────────────────────────────────────────────────────

final class LibrarySchemaTests: XCTestCase {

    private var tempDirectory: URL!
    private var databaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        databaseURL = tempDirectory.appendingPathComponent("TestProj.lalb")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// Open, apply the schema (fresh create leg), run the body, close.
    private func withFreshHandle(
        projectName: String? = "TestProj",
        _ body: (SQLiteHandle) throws -> Void
    ) throws {
        let handle = try SQLiteHandle(path: databaseURL.path)
        defer { handle.close() }
        try LibrarySchema.apply(to: handle, projectName: projectName)
        try body(handle)
    }

    private func tableColumns(
        _ handle: SQLiteHandle, _ table: String
    ) throws -> [(name: String, type: String)] {
        let statement = try handle.prepare("PRAGMA table_info(\(table))")
        var columns: [(name: String, type: String)] = []
        while try statement.step() {
            columns.append(
                (name: statement.columnText(1) ?? "", type: statement.columnText(2) ?? ""))
        }
        return columns
    }

    private func assertColumns(
        _ handle: SQLiteHandle, table: String,
        frozen: [(name: String, type: String)]
    ) throws {
        let columns = try tableColumns(handle, table)
        XCTAssertEqual(
            columns.count, frozen.count,
            "\(table) column COUNT is part of the freeze")
        for (actual, expected) in zip(columns, frozen) {
            XCTAssertEqual(
                actual.name, expected.name,
                "\(table) column ORDER is the freeze")
            XCTAssertEqual(actual.type, expected.type)
        }
    }

    private func sqliteMasterRows(
        _ handle: SQLiteHandle, type: String
    ) throws -> [(name: String, sql: String?)] {
        let statement = try handle.prepare(
            "SELECT name, sql FROM sqlite_master WHERE type = ? ORDER BY name")
        try statement.bindText(1, type)
        var rows: [(name: String, sql: String?)] = []
        while try statement.step() {
            rows.append((name: statement.columnText(0) ?? "", sql: statement.columnText(1)))
        }
        return rows
    }

    // MARK: - Freeze contract (PRAGMA table_info verbatim)

    func testImagesTwentyNineColumnsVerbatim() throws {
        try withFreshHandle { handle in
            try self.assertColumns(
                handle, table: "images", frozen: LibrarySchema.imagesColumns)
            // Spot pins (L020): the PK lead, the path carrier trio, the
            // L013 DECIMAL TEXT projection hash.
            XCTAssertEqual(try self.tableColumns(handle, "images")[0].name, "id")
            XCTAssertEqual(
                try self.tableColumns(handle, "images").first { $0.name == "params_hash" }?
                    .type, "TEXT")
            XCTAssertEqual(
                try self.tableColumns(handle, "images").first { $0.name == "ref_count" }?
                    .type, "INTEGER")
        }
    }

    func testAlbumsSevenColumnsVerbatim() throws {
        try withFreshHandle { handle in
            try self.assertColumns(
                handle, table: "albums", frozen: LibrarySchema.albumsColumns)
        }
    }

    func testAlbumContentTwoColumnsVerbatim() throws {
        try withFreshHandle { handle in
            try self.assertColumns(
                handle, table: "album_content", frozen: LibrarySchema.albumContentColumns)
            // WITHOUT ROWID shape (the catalog link-table precedent).
            let statement = try handle.prepare(
                "SELECT sql FROM sqlite_master WHERE name = 'album_content'")
            try XCTAssertTrue(statement.step())
            let sql = statement.columnText(0) ?? ""
            XCTAssertTrue(sql.contains("WITHOUT ROWID"))
            XCTAssertTrue(sql.contains("REFERENCES images(id) ON DELETE CASCADE"))
            XCTAssertTrue(sql.contains("REFERENCES albums(id) ON DELETE CASCADE"))
        }
    }

    func testPackageTablesCreated() throws {
        try withFreshHandle { handle in
            let tables = Set(try self.sqliteMasterRows(handle, type: "table").map(\.name))
            // The package tables: the v1 core six, the v3 version_ref
            // projection, and the v4 AI-library seven (both FTS5 virtual
            // tables count).
            for required in ["album_content", "albums", "images", "images_fts",
                             "project_meta", "version_ref",
                             "semantic_model", "image_embedding", "image_label",
                             "label_query", "ai_understanding",
                             "ai_understanding_fts", "ai_rating"] {
                XCTAssertTrue(tables.contains(required), "\(required) must exist")
            }
            // Everything else may only be the FTS5 shadow-table family
            // (images_fts_* / ai_understanding_fts_* — fts5 implementation
            // detail, not a package table).
            let extras = tables.subtracting([
                "album_content", "albums", "images", "images_fts", "project_meta",
                "version_ref", "semantic_model", "image_embedding", "image_label",
                "label_query", "ai_understanding", "ai_understanding_fts",
                "ai_rating",
            ])
            XCTAssertTrue(
                extras.allSatisfy {
                    $0.hasPrefix("images_fts_") || $0.hasPrefix("ai_understanding_fts_")
                },
                "unexpected tables: \(extras)")
        }
    }

    // MARK: - Fresh create: user_version + project_meta

    func testFreshCreateStampsUserVersionFourAndSeedsProjectMeta() throws {
        try withFreshHandle { handle in
            // The truth read (raw PRAGMA) and the helper agree. (M2-10-02
            // KD-1: v3→v4 = the third migration — fresh creates stamp 4.)
            let statement = try handle.prepare("PRAGMA user_version")
            try XCTAssertTrue(statement.step())
            XCTAssertEqual(statement.columnInt(0), 4)
            XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 4)

            let meta = try self.projectMeta(handle)
            XCTAssertEqual(meta[LibrarySchema.ProjectMetaKey.projectName], "TestProj")
            XCTAssertNotNil(meta[LibrarySchema.ProjectMetaKey.createdAt])
            XCTAssertNotNil(meta[LibrarySchema.ProjectMetaKey.displayState])
        }
    }

    func testForeignKeysEnabledAfterApply() throws {
        try withFreshHandle { handle in
            let statement = try handle.prepare("PRAGMA foreign_keys")
            try XCTAssertTrue(statement.step())
            XCTAssertEqual(statement.columnInt(0), 1)
        }
    }

    func testSecondApplyIsIdempotent() throws {
        try withFreshHandle { handle in
            try LibrarySchema.apply(to: handle, projectName: "Renamed")
            // Idempotent: the fresh leg does NOT re-run (user_version
            // already 4), so the seed stays the ORIGINAL name.
            XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 4)
            let meta = try self.projectMeta(handle)
            XCTAssertEqual(meta[LibrarySchema.ProjectMetaKey.projectName], "TestProj")
        }
    }

    // MARK: - FTS5 freeze (KD-5)

    func testFTSVirtualTableExternalContentUnicode61() throws {
        try withFreshHandle { handle in
            let tables = try self.sqliteMasterRows(handle, type: "table")
            let fts = tables.first { $0.name == "images_fts" }
            XCTAssertNotNil(fts)
            let sql = fts?.sql ?? ""
            XCTAssertTrue(sql.contains("CREATE VIRTUAL TABLE"))
            XCTAssertTrue(sql.contains("content='images'"))
            XCTAssertTrue(sql.contains("content_rowid='id'"))
            XCTAssertTrue(sql.contains("tokenize='unicode61'"))
            // ZERO custom tokenchars (probe P2 risk note — the DDL comment
            // carries it; the SQL itself must not register any).
            XCTAssertFalse(sql.contains("tokenchars"))

            // The FTS column name == the images materialized column
            // (external-content rebuild reads same-named columns — an
            // alias makes VALUES('rebuild') fail with "no such column").
            let ftsColumns = try self.tableColumns(handle, "images_fts")
            XCTAssertEqual(ftsColumns.map(\.name), ["exif_search_words"])
        }
    }

    func testThreeSyncTriggersRegisteredWithMapping() throws {
        try withFreshHandle { handle in
            let triggers = try self.sqliteMasterRows(handle, type: "trigger")
            let names = Set(triggers.map(\.name))
            for name in LibrarySchema.triggerNames {
                XCTAssertTrue(names.contains(name), "trigger \(name) must be registered")
            }
            // The KD-5 mapping pin: the sync legs reference the SAME
            // materialized column (`new.` on insert/update legs, `old.`
            // on delete legs — never a renamed shadow). The v4
            // ai_understanding triggers map caption/tags instead — only the
            // images_fts trio pins exif_search_words.
            for trigger in triggers where trigger.name.hasPrefix("images_fts_") {
                XCTAssertTrue(
                    trigger.sql?.contains("exif_search_words") == true,
                    "\(trigger.name) must map exif_search_words")
            }
            let insertTrigger = triggers.first { $0.name == "images_fts_ai" }?.sql ?? ""
            XCTAssertTrue(insertTrigger.contains("new.exif_search_words"))
            let deleteTrigger = triggers.first { $0.name == "images_fts_ad" }?.sql ?? ""
            XCTAssertTrue(deleteTrigger.contains("old.exif_search_words"))
        }
    }

    func testFrozenIndexesRegistered() throws {
        try withFreshHandle { handle in
            let indexes = try self.sqliteMasterRows(handle, type: "index").map(\.name)
            for name in LibrarySchema.indexNames {
                XCTAssertTrue(indexes.contains(name), "index \(name) must be registered")
            }
        }
    }

    // MARK: - version_ref projection (M2-8-1 KD-3): EXISTS + the other
    // three mini-git names stay NEGATIVE (the flipped pin)

    func testVersionRefTableExistsWithReducedDDLColumnOrder() throws {
        try withFreshHandle { handle in
            // The activated projection: exact column ORDER against the
            // reduced-DDL freeze face (order IS the DDL order).
            try self.assertColumns(
                handle, table: "version_ref",
                frozen: LibrarySchema.versionRefColumns)
            // The index registered (the per-image reverse lookup).
            let indexes = try self.sqliteMasterRows(handle, type: "index").map(\.name)
            XCTAssertTrue(indexes.contains("idx_version_ref_element"))
            // The DDL spells the cascade (KD-4's declared semantics).
            let tables = try self.sqliteMasterRows(handle, type: "table")
            let sql = tables.first { $0.name == "version_ref" }?.sql ?? ""
            XCTAssertTrue(sql.contains("REFERENCES images(id) ON DELETE CASCADE"))
            // The reduced-DDL deviation: NO head_commit_hash column
            // (OQ-2-A — no DAG, no commit hash to write).
            XCTAssertFalse(
                sql.contains("head_commit_hash"),
                "the reserved sketch's hash column is NOT activated")
        }
    }

    func testReservedMiniGitTablesDoNotExist() throws {
        try withFreshHandle { handle in
            let tables = try self.sqliteMasterRows(handle, type: "table").map(\.name)
            for reserved in LibrarySchema.reservedTableNames {
                XCTAssertFalse(
                    tables.contains(reserved),
                    "\(reserved) is a COMMENT placeholder until its activation — no entity table")
            }
            // The flipped pin: version_ref left the reserved set.
            XCTAssertFalse(
                LibrarySchema.reservedTableNames.contains("version_ref"),
                "version_ref activated in M2-8-1 — it must not regress into the set")
        }
    }

    // MARK: - Version dispatch (KD-2)

    func testCurrentVersionReopensOK() throws {
        try withFreshHandle { handle in } // fresh create + close
        let handle = try SQLiteHandle(path: databaseURL.path)
        defer { handle.close() }
        try LibrarySchema.apply(to: handle, projectName: "Ignored")
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 4)
    }

    func testFutureVersionRefused() throws {
        try withFreshHandle { handle in
            try LibrarySchema.writeUserVersion(5, to: handle)
        }
        let handle = try SQLiteHandle(path: databaseURL.path)
        defer { handle.close() }
        XCTAssertThrowsError(try LibrarySchema.apply(to: handle)) { error in
            XCTAssertEqual(error as? LibraryError, .futureSchema(version: 5))
        }
    }

    // MARK: - Migrations (KD-2/KD-3/KD-1): v3→v4 + the chained FULL-CHAIN
    // v1→v4 rotation (checker E2 — the second-migration deadlock stays
    // dead; M2: the dispatch issues ONE `migrate(from:stored, to:)` that
    // walks ALL legs v1→v2→v3→v4 — the test pins every leg's product so a
    // regression that only covers two legs cannot pass)

    /// A hand-rolled v2 package: the full v2 DDL (29-column images +
    /// default_look_pending) + one row + one album, user_version 2.
    private func makeV2Package(at url: URL) throws {
        try makeV1Package(at: url, stampVersion: 2)
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        try handle.exec(
            "ALTER TABLE images ADD COLUMN default_look_pending INTEGER DEFAULT 0")
    }

    /// A hand-rolled v1 package: the 29-column images (NO
    /// default_look_pending), albums, project_meta, one row; user_version
    /// = `stampVersion` (1 = the original-generation fixture, 2 = the v2
    /// body above).
    private func makeV1Package(at url: URL, stampVersion: Int) throws {
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        try handle.execute("PRAGMA journal_mode=WAL")
        try handle.execute("""
            CREATE TABLE images (
              id INTEGER PRIMARY KEY,
              image_path TEXT NOT NULL,
              path_kind INTEGER NOT NULL DEFAULT 0,
              volume_uuid TEXT,
              camera_make TEXT, camera_model TEXT, lens_model TEXT,
              iso INTEGER, focal_length REAL, aperture REAL, exposure REAL,
              capture_date REAL,
              file_stem TEXT, file_ext TEXT, exif_search_text TEXT,
              exif_search_words TEXT,
              rating INTEGER, color_label INTEGER, keywords TEXT,
              filename TEXT, dir TEXT, flag INTEGER, note TEXT,
              has_edits INTEGER, params_hash TEXT,
              ref_count INTEGER NOT NULL DEFAULT 0,
              added_time REAL, modified_time REAL
            )
            """)
        try handle.execute("""
            CREATE TABLE albums (
              id INTEGER PRIMARY KEY,
              type TEXT NOT NULL,
              name TEXT NOT NULL,
              parent_id INTEGER REFERENCES albums(id) ON DELETE CASCADE,
              filter_data TEXT,
              added_time REAL,
              modified_time REAL
            )
            """)
        try handle.execute(
            "CREATE TABLE project_meta (key TEXT PRIMARY KEY, value TEXT)")
        let insert = try handle.prepare(
            "INSERT INTO images (image_path, path_kind) VALUES ('Media/v2.ARW', 0)")
        _ = try insert.step()
        try LibrarySchema.writeUserVersion(stampVersion, to: handle)
    }

    /// A hand-rolled v3 package: the v2 body + the `version_ref` projection
    /// table (with one row) — the M2-8-1 end state, user_version 3.
    private func makeV3Package(at url: URL) throws {
        try makeV2Package(at: url)
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        try handle.execute("""
            CREATE TABLE version_ref (
              version_id TEXT PRIMARY KEY,
              element_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
              display_name TEXT NOT NULL,
              created_at_unix INTEGER NOT NULL,
              updated_at_unix INTEGER NOT NULL
            )
            """)
        let insert = try handle.prepare("""
            INSERT INTO version_ref (version_id, element_id, display_name,
                created_at_unix, updated_at_unix)
            VALUES ('v-1', 1, '版本 1', 1700000000, 1700000001)
            """)
        _ = try insert.step()
        try LibrarySchema.writeUserVersion(3, to: handle)
    }

    /// The seven v4 semantic tables + the understanding FTS + the three
    /// extra triggers + the FOUR SEMANTIC indexes exist. (Hand-rolled v3
    /// fixtures lack the v1-era indexes, so the index assertion covers only
    /// the v4 additions — the full-index pin runs on fresh packages where
    /// `LibrarySchema.indexNames` is complete.)
    private func assertSemanticFamilyPresent(_ handle: SQLiteHandle) throws {
        let tables = Set(try self.sqliteMasterRows(handle, type: "table").map(\.name))
        for required in ["semantic_model", "image_embedding", "image_label",
                         "label_query", "ai_understanding",
                         "ai_understanding_fts", "ai_rating"] {
            XCTAssertTrue(tables.contains(required), "\(required) must exist")
        }
        let triggers = Set(try self.sqliteMasterRows(handle, type: "trigger").map(\.name))
        // Hand-rolled fixtures predate images_fts — only the v4 trigger trio
        // is required here (the full triggerNames pin runs on fresh packages).
        for name in ["ai_understanding_fts_ai", "ai_understanding_fts_ad",
                     "ai_understanding_fts_au"] {
            XCTAssertTrue(triggers.contains(name), "trigger \(name) must exist")
        }
        let indexes = Set(try self.sqliteMasterRows(handle, type: "index").map(\.name))
        for name in ["idx_semantic_model_active", "idx_image_embedding_model",
                     "idx_ai_understanding_image", "idx_ai_rating_image"] {
            XCTAssertTrue(indexes.contains(name), "index \(name) must exist")
        }
    }

    /// The v4 column-order pins, table by table (the KD-1 enumeration —
    /// order IS the DDL order).
    private func assertSemanticColumnPins(_ handle: SQLiteHandle) throws {
        try self.assertColumns(
            handle, table: "semantic_model",
            frozen: LibrarySchema.semanticModelColumns)
        try self.assertColumns(
            handle, table: "image_embedding",
            frozen: LibrarySchema.imageEmbeddingColumns)
        try self.assertColumns(
            handle, table: "image_label",
            frozen: LibrarySchema.imageLabelColumns)
        try self.assertColumns(
            handle, table: "label_query",
            frozen: LibrarySchema.labelQueryColumns)
        try self.assertColumns(
            handle, table: "ai_understanding",
            frozen: LibrarySchema.aiUnderstandingColumns)
        try self.assertColumns(
            handle, table: "ai_rating",
            frozen: LibrarySchema.aiRatingColumns)
    }

    func testV3ToV4MigrationCreatesSemanticFamilyAndSnapshots() async throws {
        let v3URL = tempDirectory.appendingPathComponent("legacy-v3.lalb")
        try makeV3Package(at: v3URL)

        // Open through the REAL dispatch: snapshot first (the pre-migrate
        // hook's v3→v4 consumer — the rotated generation name), then the
        // idempotent CREATE family.
        let store = ProjectFileStore(at: v3URL)
        _ = try await store.open()
        let snapshotURL = v3URL.deletingPathExtension()
            .appendingPathExtension("pre-migrate.3-4.bak")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "the pre-migration snapshot hook consumed (generation-named)")
        try await store.close()

        // Read back on a DETACHED handle AFTER the close (the
        // DefaultLookTests shape — a second connection held while the
        // store is open pins the WAL and the forced TRUNCATE checkpoint
        // fails busy).
        let handle = try SQLiteHandle(path: v3URL.path)
        defer { handle.close() }
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 4)
        // The pre-existing rows survived (the additive red line).
        let count = try handle.prepare("SELECT COUNT(*) FROM images")
        try XCTAssertTrue(count.step())
        XCTAssertEqual(count.columnInt(0), 1)
        let versionCount = try handle.prepare("SELECT COUNT(*) FROM version_ref")
        try XCTAssertTrue(versionCount.step())
        XCTAssertEqual(versionCount.columnInt(0), 1)
        // The semantic family arrived complete, columns in the KD-1 order.
        try assertSemanticFamilyPresent(handle)
        try assertSemanticColumnPins(handle)
    }

    func testSemanticMigrationIdempotentOnRerun() throws {
        // A partially-migrated snapshot (or a double-open race) re-runs the
        // v3→v4 slot clean: every statement is CREATE IF NOT EXISTS.
        let url = tempDirectory.appendingPathComponent("idempotent-v4.lalb")
        try makeV3Package(at: url)
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        try LibrarySchema.migrate(from: 3, to: 4, on: handle)
        try LibrarySchema.migrate(from: 3, to: 4, on: handle) // re-run
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 4)
        try assertSemanticFamilyPresent(handle)
    }

    func testFullChainV1ToV4MigrationRotatesSnapshots() async throws {
        // The E2 deadlock scenario, one generation on: a package migrated
        // 1→4 by the FIRST generation binary (snapshot 1-4 on disk), then
        // its user_version rewound to 2 (the上一代在线产物 simulation) —
        // reopening under the current binary must migrate 2→4 WITHOUT
        // hitting the old destination-exists refusal. The dispatch issues
        // ONE migrate call walking ALL legs — the test asserts each leg's
        // product (the M2 anti-two-legs-only pin).
        let url = tempDirectory.appendingPathComponent("legacy-chain.lalb")
        try makeV1Package(at: url, stampVersion: 1)

        // Generation 1: open → migrate 1→4, snapshot 1-4 born.
        let first = ProjectFileStore(at: url)
        _ = try await first.open()
        let snapshot14 = url.deletingPathExtension()
            .appendingPathExtension("pre-migrate.1-4.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot14.path))
        try await first.close()

        // The rewind: user_version 2 (the previous binary's online
        // artifact — its OWN snapshot would sit beside ours in the wild).
        let rewind = try SQLiteHandle(path: url.path)
        try LibrarySchema.writeUserVersion(2, to: rewind)
        rewind.close()

        // Generation 2: reopen → migrate 2→4 through the ROTATION path
        // (snapshot 2-4 born beside 1-4; no destination-exists death).
        let second = ProjectFileStore(at: url)
        _ = try await second.open()
        let snapshot24 = url.deletingPathExtension()
            .appendingPathExtension("pre-migrate.2-4.bak")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshot24.path),
            "the second-generation snapshot was taken (rotation, not refusal)")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshot14.path),
            "the first generation's snapshot is preserved (generations coexist)")
        try await second.close()

        // The version read lands AFTER the close (the WAL reader rule).
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        XCTAssertEqual(
            try LibrarySchema.readUserVersion(from: handle), 4,
            "the chained migration lands at v4 — the deadlock is dead")
        // Leg products: 1→2 (the additive column), 2→3 (version_ref), and
        // 3→4 (the semantic family) — ALL present after the single call.
        let columns = try tableColumns(handle, "images")
        XCTAssertNotNil(
            columns.first(where: { $0.name == "default_look_pending" }),
            "leg v1→v2 product missing")
        let tables = Set(try self.sqliteMasterRows(handle, type: "table").map(\.name))
        XCTAssertTrue(
            tables.contains("version_ref"), "leg v2→v3 product missing")
        try assertSemanticFamilyPresent(handle)
        try assertSemanticColumnPins(handle)
    }

    // MARK: - v4 family semantics (KD-1): fresh-carried + the OQ-9-A
    // single-activation invariant + the declared CASCADE across all four
    // AI domains

    func testFreshV4CarriesSemanticFamilyFromBirth() throws {
        try withFreshHandle { handle in
            try assertSemanticFamilyPresent(handle)
            try assertSemanticColumnPins(handle)
            // The FTS virtual table shape (the images_fts :206 pin, two
            // document columns this time).
            let fts = try self.sqliteMasterRows(handle, type: "table")
                .first { $0.name == "ai_understanding_fts" }
            let sql = fts?.sql ?? ""
            XCTAssertTrue(sql.contains("content='ai_understanding'"))
            XCTAssertTrue(sql.contains("content_rowid='id'"))
            XCTAssertTrue(sql.contains("tokenize='unicode61'"))
            XCTAssertFalse(sql.contains("tokenchars"))
        }
    }

    func testActiveModelSingleActivationEnforced() throws {
        try withFreshHandle { handle in
            let insert = try handle.prepare("""
                INSERT INTO semantic_model (model_key, model_id, revision,
                    embedding_dim, image_size, prompt_config_hash, active)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """)
            func seed(_ key: String, _ active: Int64) throws {
                try insert.reset()
                try insert.bindText(1, key)
                try insert.bindText(2, "OFA-Sys/chinese-clip-vit-base-patch16")
                try insert.bindText(3, "36e679e6")
                try insert.bindInt(4, 512)
                try insert.bindInt(5, 224)
                try insert.bindNull(6)
                try insert.bindInt(7, active)
                _ = try insert.step()
            }
            try seed("a-profile", 1)
            try seed("b-profile", 0) // inactive siblings are fine
            // A SECOND active=1 row violates the partial unique index —
            // the OQ-9-A invariant is DB-level, not store-discipline.
            XCTAssertThrowsError(try seed("c-profile", 1))
        }
    }

    func testSemanticTablesCascadeWithImageRow() throws {
        try withFreshHandle { handle in
            // One image + one row in EACH AI domain + an understanding row
            // the FTS index picked up through the trigger.
            let image = try handle.prepare(
                "INSERT INTO images (image_path, path_kind) VALUES ('Media/c.ARW', 0)")
            _ = try image.step()
            try handle.execute("""
                INSERT INTO semantic_model (model_key, model_id, revision,
                    embedding_dim, image_size, prompt_config_hash, active)
                VALUES ('k', 'm', 'r', 4, 224, NULL, 1)
                """)
            try handle.execute("""
                INSERT INTO image_embedding (image_id, model_key, dim,
                    embedding, computed_time)
                VALUES (1, 'k', 4, x'00003c0040003f00', 1)
                """)
            try handle.execute("""
                INSERT INTO image_label (image_id, model_key, label, score,
                    confident) VALUES (1, 'k', 'sunset', 0.9, 1)
                """)
            try handle.execute("""
                INSERT INTO label_query (model_key, label, query_text, lang)
                VALUES ('k', 'sunset', 'a sunset photo', 'en')
                """)
            try handle.execute("""
                INSERT INTO ai_understanding (image_id, task_id, provider_id,
                    model_id, prompt_profile_id, caption, tags, computed_time)
                VALUES (1, 't1', 'p', 'm', '123', 'a golden sunset', '["x"]', 1)
                """)
            try handle.execute("""
                INSERT INTO ai_rating (image_id, task_id, provider_id, model_id,
                    prompt_profile_id, rating, reasons, computed_time)
                VALUES (1, 't1', 'p', 'm', '123', 4, '["r"]', 1)
                """)
            // The trigger indexed the caption (pre-delete sanity).
            let match = try handle.prepare(
                "SELECT rowid FROM ai_understanding_fts WHERE ai_understanding_fts MATCH 'sunset'")
            try XCTAssertTrue(match.step())
            // The CASCADE: deleting the image row annihilates all four AI
            // domains (label_query has NO image FK — it survives).
            try handle.execute("DELETE FROM images WHERE id = 1")
            for table in ["image_embedding", "image_label",
                          "ai_understanding", "ai_rating"] {
                let count = try handle.prepare("SELECT COUNT(*) FROM \(table)")
                try XCTAssertTrue(count.step())
                XCTAssertEqual(
                    count.columnInt(0), 0, "\(table) rows must cascade away")
            }
            // The FTS index unstaged the deleted row through the trigger.
            let afterMatch = try handle.prepare(
                "SELECT COUNT(*) FROM ai_understanding_fts WHERE ai_understanding_fts MATCH 'sunset'")
            try XCTAssertTrue(afterMatch.step())
            XCTAssertEqual(afterMatch.columnInt(0), 0)
            let queryCount = try handle.prepare("SELECT COUNT(*) FROM label_query")
            try XCTAssertTrue(queryCount.step())
            XCTAssertEqual(queryCount.columnInt(0), 1)
        }
    }

    // MARK: - Import filter constants (OQ-12)

    func testDefaultRawWhitelistExactFourteen() throws {
        XCTAssertEqual(
            LibrarySchema.defaultRawExtensions,
            [
                "3fr", "arw", "cr2", "cr3", "dng", "fff",
                "nef", "raf", "raw", "rw2",       // Alcedo 0.3.0 ten
                "pef", "orf", "rwl", "iiq",       // Apple CIRAW additions
            ])
        XCTAssertEqual(LibrarySchema.defaultRawExtensions.count, 14)
    }

    func testHardcodedSidecarExclusions() throws {
        XCTAssertEqual(
            LibrarySchema.hardcodedSidecarExclusions,
            ["xmp", "lra", "lightamer-preset", "pp3", "opc"])
    }

    // MARK: - Package layout constants (KD-1)

    func testPackageLayoutConstants() {
        XCTAssertEqual(LibrarySchema.fileExtension, "lalb")
        XCTAssertEqual(LibrarySchema.mediaDirectoryName, "Media")
        XCTAssertEqual(
            LibrarySchema.thumbsDirectoryName(stem: "Trip2026"), ".Trip2026.lathumbs")
    }

    // MARK: - Helpers

    private func projectMeta(
        _ handle: SQLiteHandle
    ) throws -> [String: String] {
        let statement = try handle.prepare("SELECT key, value FROM project_meta")
        var meta: [String: String] = [:]
        while try statement.step() {
            if let key = statement.columnText(0), let value = statement.columnText(1) {
                meta[key] = value
            }
        }
        return meta
    }
}
