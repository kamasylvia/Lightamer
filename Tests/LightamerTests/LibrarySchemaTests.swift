import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySchemaTests (Plan M2-2-1 T1) — the `.lalb` freeze contract:
//
//   • three entity tables + project_meta + the FTS5 virtual table, fresh;
//     `images` 28 columns / `albums` 7 / `album_content` 2 — VERBATIM
//     (order IS the freeze, KD-3's complete enumeration)
//   • fresh create: user_version == 1 + project_meta seeded (name/created_at)
//   • images_fts: external-content over images, content_rowid='id',
//     tokenize='unicode61' (ZERO custom tokenchars), FTS column name ==
//     `exif_search_words` (KD-5 rebuild dependency); the three sync
//     triggers registered with the `new.exif_search_words` mapping
//   • the two frozen indexes (idx_images_capture / idx_album_content_image)
//   • RESERVED mini-git tables DO NOT exist (OQ-3 A comment placeholder —
//     the negative pin)
//   • foreign_keys pragma is ON after apply (the CASCADE semantics are
//     declared DDL, KD-4); second apply is idempotent
//   • user_version >1 → typed `.futureSchema` REFUSE
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

    func testImagesTwentyEightColumnsVerbatim() throws {
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
            // The five package tables (the FTS5 virtual table counts as one).
            for required in ["album_content", "albums", "images", "images_fts",
                             "project_meta"] {
                XCTAssertTrue(tables.contains(required), "\(required) must exist")
            }
            // Everything else may only be the FTS5 shadow-table family
            // (images_fts_data/docsize/config/idx — fts5 implementation
            // detail, not a package table).
            let extras = tables.subtracting([
                "album_content", "albums", "images", "images_fts", "project_meta",
            ])
            XCTAssertTrue(
                extras.allSatisfy { $0.hasPrefix("images_fts_") },
                "unexpected tables: \(extras)")
        }
    }

    // MARK: - Fresh create: user_version + project_meta

    func testFreshCreateStampsUserVersionOneAndSeedsProjectMeta() throws {
        try withFreshHandle { handle in
            // The truth read (raw PRAGMA) and the helper agree.
            let statement = try handle.prepare("PRAGMA user_version")
            try XCTAssertTrue(statement.step())
            XCTAssertEqual(statement.columnInt(0), 1)
            XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 1)

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
            // already 1), so the seed stays the ORIGINAL name.
            XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 1)
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

    // MARK: - Reserved mini-git tables: NEGATIVE pin (OQ-3 A)

    func testReservedMiniGitTablesDoNotExist() throws {
        try withFreshHandle { handle in
            let tables = try self.sqliteMasterRows(handle, type: "table").map(\.name)
            for reserved in LibrarySchema.reservedTableNames {
                XCTAssertFalse(
                    tables.contains(reserved),
                    "\(reserved) is a COMMENT placeholder until M2-8 — no entity table")
            }
        }
    }

    // MARK: - Version dispatch (KD-2)

    func testVersionOneReopensOK() throws {
        try withFreshHandle { handle in } // fresh create + close
        let handle = try SQLiteHandle(path: databaseURL.path)
        defer { handle.close() }
        try LibrarySchema.apply(to: handle, projectName: "Ignored")
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 1)
    }

    func testFutureVersionRefused() throws {
        try withFreshHandle { handle in
            try LibrarySchema.writeUserVersion(2, to: handle)
        }
        let handle = try SQLiteHandle(path: databaseURL.path)
        defer { handle.close() }
        XCTAssertThrowsError(try LibrarySchema.apply(to: handle)) { error in
            XCTAssertEqual(error as? LibraryError, .futureSchema(version: 2))
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
