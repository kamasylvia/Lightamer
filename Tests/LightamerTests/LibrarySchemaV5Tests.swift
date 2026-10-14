import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySchemaV5Tests (Plan M6-4-01 T1, KD-1) — the v5 stack-family migration
// contract (OQ-M6-4-1 = A):
//
//   ① fresh create: `stacks` + `stack_content` + the UNIQUE
//      `idx_stack_content_image` born on a v5 package; user_version == 5;
//      the WITHOUT ROWID + double-CASCADE DDL spelling verbatim
//   ② a v4 package (built through the REAL 1→4 slots, stamped 4) opens →
//      the dispatch snapshot 4-5 → migrate → 5, data preserved
//   ③ idempotent: migrate(4→5) twice — CREATE IF NOT EXISTS, zero dupes
//   ④ full chain: a stamped-1 package walks ALL legs 1→…→5 in ONE dispatch
//   ⑤ futureSchema: user_version = 6 → typed refuse, the file untouched
//   ⑥ the freeze faces: images/albums/album_content/version_ref columns
//      PRAGMA-verbatim unchanged; triggerNames unchanged; the three
//      reserved mini-git names still ABSENT (stacks is an ACTIVATED entity
//      table, never reserved); cover = position 0 — no cover column exists
//   ⑦ the one-image-one-stack invariant is DB-LEVEL: a second
//      stack_content row with the same image_id violates the UNIQUE index
//   ⑧ image delete cascades the membership rows (the ≥2 remainder's rows
//      survive; the store-level <2 dissolution sweep is pinned by
//      LibraryStackStoreTests — the sweep is store code, this file pins
//      the DECLARED DDL semantics)
//
// Fixtures in NSTemporaryDirectory (L009: never external volume).
// ─────────────────────────────────────────────────────────────────────────────

final class LibrarySchemaV5Tests: XCTestCase {

    private var tempDirectory: URL!
    private var databaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-schema-v5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        databaseURL = tempDirectory.appendingPathComponent("StackProj.lalb")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// Open, apply the schema (fresh create leg), run the body, close.
    private func withFreshHandle(
        projectName: String? = "StackProj",
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

    private func readUserVersion(_ url: URL) throws -> Int {
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        return try LibrarySchema.readUserVersion(from: handle)
    }

    /// A hand-rolled v1 package (the LibrarySchemaTests fixture shape: the
    /// 29-column images, albums, project_meta, one row) stamped
    /// `stampVersion`. The v4 body for ② is built by running the REAL
    /// migration slots 1→4 over this.
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
            "INSERT INTO images (image_path, path_kind) VALUES ('Media/v5.ARW', 0)")
        _ = try insert.step()
        try LibrarySchema.writeUserVersion(stampVersion, to: handle)
    }

    /// The stack-family presence pins (tables + the UNIQUE index + the
    /// WITHOUT ROWID / double-CASCADE DDL spelling).
    private func assertStackFamilyPresent(_ handle: SQLiteHandle) throws {
        let tables = Set(try self.sqliteMasterRows(handle, type: "table").map(\.name))
        XCTAssertTrue(tables.contains("stacks"), "stacks must exist")
        XCTAssertTrue(tables.contains("stack_content"), "stack_content must exist")
        let indexes = Set(try self.sqliteMasterRows(handle, type: "index").map(\.name))
        XCTAssertTrue(
            indexes.contains("idx_stack_content_image"),
            "the UNIQUE one-image-one-stack index must exist")
        let contentSQL = try self.sqliteMasterRows(handle, type: "table")
            .first { $0.name == "stack_content" }?.sql ?? ""
        XCTAssertTrue(contentSQL.contains("WITHOUT ROWID"))
        XCTAssertTrue(contentSQL.contains("REFERENCES images(id) ON DELETE CASCADE"))
        XCTAssertTrue(contentSQL.contains("REFERENCES stacks(id) ON DELETE CASCADE"))
        // Cover = position 0 — single truth, NO cover column (KD-1).
        XCTAssertFalse(
            contentSQL.contains("cover"),
            "the cover is the position-0 member, never a column")
    }

    // MARK: - ① Fresh create

    func testFreshCreateCarriesStackFamilyFromBirth() throws {
        try withFreshHandle { handle in
            try assertStackFamilyPresent(handle)
            try self.assertColumns(
                handle, table: "stacks", frozen: LibrarySchema.stacksColumns)
            try self.assertColumns(
                handle, table: "stack_content",
                frozen: LibrarySchema.stackContentColumns)
            XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 5)
        }
    }

    // MARK: - ② v4 → v5 migration through the real dispatch

    func testV4PackageMigratesToFiveAndPreservesData() async throws {
        let v4URL = tempDirectory.appendingPathComponent("legacy-v4.lalb")
        try makeV1Package(at: v4URL, stampVersion: 1)
        // Build the v4 body through the REAL slots (1→4), then stamp 4 —
        // the honest v4 fixture (hand-writing seven DDL families would
        // drift from the slots it must match).
        do {
            let handle = try SQLiteHandle(path: v4URL.path)
            defer { handle.close() }
            try handle.exec("PRAGMA foreign_keys=ON")
            try LibrarySchema.migrate(from: 1, to: 4, on: handle)
            try handle.execute(
                "INSERT INTO version_ref (version_id, element_id, display_name,"
                    + " created_at_unix, updated_at_unix)"
                    + " VALUES ('v-1', 1, '版本 1', 1, 2)")
        }
        XCTAssertEqual(try readUserVersion(v4URL), 4)

        // Open through the REAL dispatch: the pre-migrate snapshot rotates
        // (generation 4-5), the idempotent family lands, the version is 5.
        let store = ProjectFileStore(at: v4URL)
        _ = try await store.open()
        let snapshotURL = v4URL.deletingPathExtension()
            .appendingPathExtension("pre-migrate.4-5.bak")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "the pre-migration snapshot hook consumed (generation-named)")
        try await store.close()

        let handle = try SQLiteHandle(path: v4URL.path)
        defer { handle.close() }
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 5)
        // Pre-existing rows survived (the additive red line).
        let imageCount = try handle.prepare("SELECT COUNT(*) FROM images")
        try XCTAssertTrue(imageCount.step())
        XCTAssertEqual(imageCount.columnInt(0), 1)
        let refCount = try handle.prepare("SELECT COUNT(*) FROM version_ref")
        try XCTAssertTrue(refCount.step())
        XCTAssertEqual(refCount.columnInt(0), 1)
        try assertStackFamilyPresent(handle)
        // The stack family starts EMPTY (zero backfill — KD-1).
        let stackCount = try handle.prepare("SELECT COUNT(*) FROM stacks")
        try XCTAssertTrue(stackCount.step())
        XCTAssertEqual(stackCount.columnInt(0), 0)
    }

    // MARK: - ③ Idempotent re-run

    func testStackMigrationIdempotentOnRerun() throws {
        let url = tempDirectory.appendingPathComponent("idempotent-v5.lalb")
        try makeV1Package(at: url, stampVersion: 1)
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        try LibrarySchema.migrate(from: 4, to: 5, on: handle)
        try LibrarySchema.migrate(from: 4, to: 5, on: handle) // re-run
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 5)
        try assertStackFamilyPresent(handle)
        // No duplicate table registrations (the master holds ONE entry).
        let stackTables = try sqliteMasterRows(handle, type: "table")
            .filter { $0.name == "stacks" || $0.name == "stack_content" }
        XCTAssertEqual(stackTables.count, 2)
    }

    // MARK: - ④ Full chain 1→5

    func testFullChainV1ToV5Migration() async throws {
        let url = tempDirectory.appendingPathComponent("legacy-chain-v5.lalb")
        try makeV1Package(at: url, stampVersion: 1)
        let store = ProjectFileStore(at: url)
        _ = try await store.open()
        try await store.close()
        // One dispatch call walked ALL legs: the original row + the v2
        // column + the v3 projection + the v4 family + the v5 stacks.
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        XCTAssertEqual(
            try LibrarySchema.readUserVersion(from: handle), 5,
            "the chained migration lands at v5")
        let columns = try tableColumns(handle, "images")
        XCTAssertNotNil(
            columns.first(where: { $0.name == "default_look_pending" }),
            "leg v1→v2 product missing")
        let tables = Set(try sqliteMasterRows(handle, type: "table").map(\.name))
        XCTAssertTrue(tables.contains("version_ref"), "leg v2→v3 product missing")
        XCTAssertTrue(tables.contains("ai_rating"), "leg v3→v4 product missing")
        try assertStackFamilyPresent(handle)
    }

    // MARK: - ⑤ futureSchema refusal

    func testFutureVersionSixRefusedAndUntouched() throws {
        try withFreshHandle { handle in
            try handle.execute(
                "INSERT INTO stacks (collapsed) VALUES (1)")
            try LibrarySchema.writeUserVersion(6, to: handle)
        }
        let handle = try SQLiteHandle(path: databaseURL.path)
        XCTAssertThrowsError(try LibrarySchema.apply(to: handle)) { error in
            XCTAssertEqual(error as? LibraryError, .futureSchema(version: 6))
        }
        handle.close()
        // The destructive red line: the refuse path wrote NOTHING — the
        // stamped version and the seeded row stand byte-intact.
        XCTAssertEqual(try readUserVersion(databaseURL), 6)
        let verify = try SQLiteHandle(path: databaseURL.path)
        defer { verify.close() }
        let rows = try verify.prepare("SELECT COUNT(*) FROM stacks")
        try XCTAssertTrue(rows.step())
        XCTAssertEqual(rows.columnInt(0), 1)
    }

    // MARK: - ⑥ Freeze faces verbatim + reserved names negative

    func testFrozenFacesUnchangedAndReservedNamesNegative() throws {
        try withFreshHandle { handle in
            try self.assertColumns(
                handle, table: "images", frozen: LibrarySchema.imagesColumns)
            try self.assertColumns(
                handle, table: "albums", frozen: LibrarySchema.albumsColumns)
            try self.assertColumns(
                handle, table: "album_content",
                frozen: LibrarySchema.albumContentColumns)
            try self.assertColumns(
                handle, table: "version_ref",
                frozen: LibrarySchema.versionRefColumns)
            // The v5 face adds exactly ONE index — the triggers stay six.
            let triggers = try sqliteMasterRows(handle, type: "trigger").map(\.name)
            XCTAssertEqual(Set(triggers), Set(LibrarySchema.triggerNames))
            XCTAssertEqual(LibrarySchema.indexNames.count, 7)
            // The three reserved mini-git names stay COMMENT placeholders
            // (stacks is an ACTIVATED entity table, never reserved).
            let tables = try sqliteMasterRows(handle, type: "table").map(\.name)
            for reserved in LibrarySchema.reservedTableNames {
                XCTAssertFalse(tables.contains(reserved))
            }
            XCTAssertEqual(LibrarySchema.reservedTableNames.count, 3)
            XCTAssertFalse(LibrarySchema.reservedTableNames.contains("stacks"))
        }
    }

    // MARK: - ⑦ The UNIQUE one-image-one-stack invariant (DB level)

    func testUniqueIndexEnforcesOneImageOneStack() throws {
        try withFreshHandle { handle in
            try handle.execute(
                "INSERT INTO images (image_path, path_kind) VALUES ('Media/a.ARW', 0)")
            try handle.execute("INSERT INTO stacks (collapsed) VALUES (0)")
            try handle.execute("INSERT INTO stacks (collapsed) VALUES (0)")
            try handle.execute(
                "INSERT INTO stack_content (stack_id, image_id, position)"
                    + " VALUES (1, 1, 0)")
            // The same image in a SECOND stack violates the UNIQUE index —
            // the invariant is DB-level (LightCraft validate rule 3).
            XCTAssertThrowsError(
                try handle.execute(
                    "INSERT INTO stack_content (stack_id, image_id, position)"
                        + " VALUES (2, 1, 0)")
            )
        }
    }

    // MARK: - ⑧ Image delete cascades memberships

    func testImageDeleteCascadesMemberships() throws {
        try withFreshHandle { handle in
            // Stack A: images 1/2/3 (cover 1); stack B: images 4/5.
            for index in 1...5 {
                try handle.execute(
                    "INSERT INTO images (image_path, path_kind)"
                        + " VALUES ('Media/i\(index).ARW', 0)")
            }
            try handle.execute("INSERT INTO stacks (collapsed) VALUES (0)")
            try handle.execute("INSERT INTO stacks (collapsed) VALUES (0)")
            for (stack, image, position) in [(1, 1, 0), (1, 2, 1), (1, 3, 2), (2, 4, 0), (2, 5, 1)] {
                try handle.execute(
                    "INSERT INTO stack_content (stack_id, image_id, position)"
                        + " VALUES (\(stack), \(image), \(position))")
            }
            // Delete image 1 (stack A's cover): its membership row
            // cascades away; A keeps its ≥2 remainder; B is untouched.
            try handle.execute("DELETE FROM images WHERE id = 1")
            let orphans = try handle.prepare(
                "SELECT COUNT(*) FROM stack_content WHERE image_id = 1")
            try XCTAssertTrue(orphans.step())
            XCTAssertEqual(orphans.columnInt(0), 0, "the membership row cascaded")
            let aRows = try handle.prepare(
                "SELECT COUNT(*) FROM stack_content WHERE stack_id = 1")
            try XCTAssertTrue(aRows.step())
            XCTAssertEqual(aRows.columnInt(0), 2, "the ≥2 remainder survives")
            let bRows = try handle.prepare(
                "SELECT COUNT(*) FROM stack_content WHERE stack_id = 2")
            try XCTAssertTrue(bRows.step())
            XCTAssertEqual(bRows.columnInt(0), 2)
            // The stacks rows stand at the DDL level (the <2 dissolution
            // sweep is the store's same-transaction duty — pinned by
            // LibraryStackStoreTests).
            let stackRows = try handle.prepare("SELECT COUNT(*) FROM stacks")
            try XCTAssertTrue(stackRows.step())
            XCTAssertEqual(stackRows.columnInt(0), 2)
        }
    }
}
