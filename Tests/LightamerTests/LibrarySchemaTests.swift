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
//   • fresh create: user_version == 3 + project_meta seeded (name/created_at)
//     (M2-8-1: fresh creates stamp 3 — the version_ref projection table
//     joins the fresh DDL)
//   • images_fts: external-content over images, content_rowid='id',
//     tokenize='unicode61' (ZERO custom tokenchars), FTS column name ==
//     `exif_search_words` (KD-5 rebuild dependency); the three sync
//     triggers registered with the `new.exif_search_words` mapping
//   • the two frozen indexes (idx_images_capture / idx_album_content_image)
//   • version_ref EXISTS with the reduced-DDL column order (M2-8-1 KD-3
//     activated the projection — the negative pin FLIPPED for this one
//     name); the other three reserved mini-git tables DO NOT exist
//   • foreign_keys pragma is ON after apply (the CASCADE semantics are
//     declared DDL, KD-4); second apply is idempotent
//   • user_version >3 → typed `.futureSchema` REFUSE
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
            // The six package tables (the FTS5 virtual table counts as one;
            // version_ref joined in M2-8-1 as the projection table).
            for required in ["album_content", "albums", "images", "images_fts",
                             "project_meta", "version_ref"] {
                XCTAssertTrue(tables.contains(required), "\(required) must exist")
            }
            // Everything else may only be the FTS5 shadow-table family
            // (images_fts_data/docsize/config/idx — fts5 implementation
            // detail, not a package table).
            let extras = tables.subtracting([
                "album_content", "albums", "images", "images_fts", "project_meta",
                "version_ref",
            ])
            XCTAssertTrue(
                extras.allSatisfy { $0.hasPrefix("images_fts_") },
                "unexpected tables: \(extras)")
        }
    }

    // MARK: - Fresh create: user_version + project_meta

    func testFreshCreateStampsUserVersionThreeAndSeedsProjectMeta() throws {
        try withFreshHandle { handle in
            // The truth read (raw PRAGMA) and the helper agree. (M2-8-1
            // KD-3: v2→v3 = the second migration — fresh creates stamp 3.)
            let statement = try handle.prepare("PRAGMA user_version")
            try XCTAssertTrue(statement.step())
            XCTAssertEqual(statement.columnInt(0), 3)
            XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 3)

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
            // already 3), so the seed stays the ORIGINAL name.
            XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 3)
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
            // on delete legs — never a renamed shadow).
            for trigger in triggers where LibrarySchema.triggerNames.contains(trigger.name) {
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
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 3)
    }

    func testFutureVersionRefused() throws {
        try withFreshHandle { handle in
            try LibrarySchema.writeUserVersion(4, to: handle)
        }
        let handle = try SQLiteHandle(path: databaseURL.path)
        defer { handle.close() }
        XCTAssertThrowsError(try LibrarySchema.apply(to: handle)) { error in
            XCTAssertEqual(error as? LibraryError, .futureSchema(version: 4))
        }
    }

    // MARK: - Migrations (KD-2/KD-3): v2→v3 + the chained two-generation
    // rotation (checker E2 — the second-migration deadlock stays dead)

    /// A hand-rolled v2 package: the full v2 DDL (29-column images +
    /// default_look_pending) + one row + one album, user_version 2.
    private func makeV2Package(at url: URL) throws {
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
              added_time REAL, modified_time REAL,
              default_look_pending INTEGER DEFAULT 0
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
        try LibrarySchema.writeUserVersion(2, to: handle)
    }

    func testV2ToV3MigrationCreatesVersionRefAndSnapshots() async throws {
        let v2URL = tempDirectory.appendingPathComponent("legacy-v2.lalb")
        try makeV2Package(at: v2URL)

        // Open through the REAL dispatch: snapshot first (the pre-migrate
        // hook's first v2→v3 consumer — the rotated generation name), then
        // the idempotent CREATE.
        let store = ProjectFileStore(at: v2URL)
        _ = try await store.open()
        let snapshotURL = v2URL.deletingPathExtension()
            .appendingPathExtension("pre-migrate.2-3.bak")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "the pre-migration snapshot hook consumed (generation-named)")
        try await store.close()

        // Read back on a DETACHED handle AFTER the close (the
        // DefaultLookTests shape — a second connection held while the
        // store is open pins the WAL and the forced TRUNCATE checkpoint
        // fails busy).
        let handle = try SQLiteHandle(path: v2URL.path)
        defer { handle.close() }
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 3)
        // The pre-existing row survived; the projection table exists.
        let count = try handle.prepare("SELECT COUNT(*) FROM images")
        try XCTAssertTrue(count.step())
        XCTAssertEqual(count.columnInt(0), 1)
        let columns = try tableColumns(handle, "version_ref")
        XCTAssertEqual(
            columns.map(\.name), LibrarySchema.versionRefColumns.map(\.name))
    }

    func testChainedTwoGenerationMigrationRotatesSnapshots() async throws {
        // The E2 deadlock scenario: a package migrated 1→3 by the FIRST
        // generation binary (snapshot 1-3 on disk), then its user_version
        // rewound to 2 (the上一代在线产物 simulation) — reopening under the
        // current binary must migrate 2→3 WITHOUT hitting the old
        // destination-exists refusal.
        let url = tempDirectory.appendingPathComponent("legacy-chain.lalb")
        try makeV2Package(at: url)
        // Rewind to a v1 shape: drop the v2 column and stamp 1 (the
        // original-generation fixture).
        let v1 = try SQLiteHandle(path: url.path)
        try v1.exec("ALTER TABLE images DROP COLUMN default_look_pending")
        try LibrarySchema.writeUserVersion(1, to: v1)
        v1.close()

        // Generation 1: open → migrate 1→3, snapshot 1-3 born.
        let first = ProjectFileStore(at: url)
        _ = try await first.open()
        let snapshot13 = url.deletingPathExtension()
            .appendingPathExtension("pre-migrate.1-3.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot13.path))
        try await first.close()

        // The rewind: user_version 2 (the previous binary's online
        // artifact — its OWN snapshot would sit beside ours in the wild).
        let rewind = try SQLiteHandle(path: url.path)
        try LibrarySchema.writeUserVersion(2, to: rewind)
        rewind.close()

        // Generation 2: reopen → migrate 2→3 through the ROTATION path
        // (snapshot 2-3 born beside 1-3; no destination-exists death).
        let second = ProjectFileStore(at: url)
        _ = try await second.open()
        let snapshot23 = url.deletingPathExtension()
            .appendingPathExtension("pre-migrate.2-3.bak")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshot23.path),
            "the second-generation snapshot was taken (rotation, not refusal)")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshot13.path),
            "the first generation's snapshot is preserved (generations coexist)")
        try await second.close()

        // The version read lands AFTER the close (the WAL reader rule).
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        XCTAssertEqual(
            try LibrarySchema.readUserVersion(from: handle), 3,
            "the chained migration lands at v3 — the deadlock is dead")
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
