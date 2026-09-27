import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 16-1 T1 — the `.lcat` freeze contract:
//
//   • seven tables + meta, created fresh; `catalog_images` = 31 columns
//     VERBATIM (order pinned; `rel_path` rename; the five non-mirrored
//     session columns absent)
//   • the composite identity UNIQUE(session_id, rel_path) + the six
//     ordering/tail indexes (shape (k IS NULL, k [DESC], rel_path), F6)
//   • the three link tables are WITHOUT ROWID (F11 clustered PK shape)
//   • pragma baseline VERBATIM: WAL / synchronous=NORMAL /
//     cache_size=-64000 / busy_timeout=5000 / case_sensitive_like=ON
//   • v99 + unparsable meta REFUSALS; a refused open leaves the original
//     file BYTE-UNTOUCHED (L020 content-level)
//   • second apply is idempotent (zero harm); the migrate slot is a no-op
//     at v1
//
// Fixtures in FileManager.temporaryDirectory (L009: never external-volume).
// ─────────────────────────────────────────────────────────────────────────────

final class CatalogIndexSchemaTests: XCTestCase {

    private var tempDirectory: URL!
    private var databaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-schema-\(UUID().uuidString)", isDirectory: true)
        databaseURL = tempDirectory.appendingPathComponent("catalog.lcat")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// Open, apply the schema, run the body, close (deterministic — the
    /// byte-identity assertions need the -wal checkpointed away).
    private func withFreshHandle(
        _ body: (SQLiteHandle) throws -> Void
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: databaseURL.path)
        defer { handle.close() }
        try CatalogIndexSchema.apply(to: handle)
        try body(handle)
        return databaseURL
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

    private func indexNames(_ handle: SQLiteHandle, _ table: String) throws -> [String] {
        let statement = try handle.prepare("PRAGMA index_list(\(table))")
        var names: [String] = []
        while try statement.step() {
            if let name = statement.columnText(1) { names.append(name) }
        }
        return names
    }

    /// PRAGMA index_info rows; expression columns report a NULL name (the
    /// expression is NOT a plain column) — the shape assertion keys on the
    /// nil placeholders.
    private func indexColumns(
        _ handle: SQLiteHandle, _ index: String
    ) throws -> [String?] {
        let statement = try handle.prepare("PRAGMA index_info(\(index))")
        var names: [String?] = []
        while try statement.step() {
            names.append(statement.columnText(2))
        }
        return names
    }

    private func readMeta(_ handle: SQLiteHandle) throws -> String? {
        let statement = try handle.prepare(
            "SELECT value FROM meta WHERE key = 'schemaVersion'")
        return try statement.step() ? statement.columnText(0) : nil
    }

    // MARK: - Seven tables + the 31-column freeze

    func testSevenTablesCreated() throws {
        try withFreshHandle { handle in
            let statement = try handle.prepare(
                "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
            var names: [String] = []
            while try statement.step() {
                if let name = statement.columnText(0) { names.append(name) }
            }
            XCTAssertEqual(
                Set(names),
                [
                    "catalog_images", "catalog_sessions", "categories",
                    "collections", "image_categories", "image_collections",
                    "image_tags", "meta",
                ])
        }
    }

    func testCatalogImagesThirtyOneColumnsVerbatim() throws {
        try withFreshHandle { handle in
            let columns = try self.tableColumns(handle, "catalog_images")
            XCTAssertEqual(columns.count, 31)
            for (actual, expected) in zip(columns, CatalogIndexSchema.catalogImageColumns) {
                XCTAssertEqual(actual.name, expected.name, "column ORDER is the freeze")
                XCTAssertEqual(actual.type, expected.type)
            }
            // The rename + the non-mirrored five, spelled out (L020):
            XCTAssertEqual(columns[2].name, "rel_path")
            XCTAssertFalse(columns.contains { $0.name == "path" })
            for banned in ["scan_epoch", "thumb_state", "thumb_path",
                           "thumb_params_hash", "dirty"] {
                XCTAssertFalse(
                    columns.contains { $0.name == banned },
                    "\(banned) must NOT be mirrored")
            }
            // Source list parity: 29 mirrored = 31 − id − session_id.
            XCTAssertEqual(CatalogIndexSchema.mirroredSourceColumns.count, 29)
            XCTAssertEqual(CatalogIndexSchema.mirroredSourceColumns.count,
                           CatalogIndexSchema.catalogImageColumns.count - 2)
        }
    }

    func testCatalogSessionsRegistryColumns() throws {
        try withFreshHandle { handle in
            let columns = try self.tableColumns(handle, "catalog_sessions")
            XCTAssertEqual(
                columns.map(\.name),
                ["session_id", "root_path", "display_name",
                 "last_projected_epoch", "last_seen", "offline"])
            XCTAssertEqual(columns[0].type, "TEXT")
            XCTAssertEqual(columns[3].type, "INTEGER")
        }
    }

    func testCategoriesCollectionsShapes() throws {
        try withFreshHandle { handle in
            XCTAssertEqual(
                try self.tableColumns(handle, "categories").map(\.name),
                ["id", "parent_id", "name", "sort_order", "created_at"])
            XCTAssertEqual(
                try self.tableColumns(handle, "collections").map(\.name),
                ["id", "name", "sort_order", "created_at"])
        }
    }

    func testLinkTablesAreWithoutRowid() throws {
        try withFreshHandle { handle in
            for table in ["image_categories", "image_collections", "image_tags"] {
                let statement = try handle.prepare(
                    "SELECT sql FROM sqlite_master WHERE name = ?")
                try statement.bindText(1, table)
                guard try statement.step(), let sql = statement.columnText(0) else {
                    return XCTFail("\(table) missing")
                }
                XCTAssertTrue(
                    sql.localizedCaseInsensitiveContains("WITHOUT ROWID"),
                    "\(table) must be WITHOUT ROWID (F11)")
            }
            // Link-table column pairs (2 columns each; the PK IS the table).
            XCTAssertEqual(
                try self.tableColumns(handle, "image_tags").map(\.name),
                ["tag", "catalog_image_id"])
            XCTAssertEqual(
                try self.tableColumns(handle, "image_categories").map(\.name),
                ["category_id", "catalog_image_id"])
            XCTAssertEqual(
                try self.tableColumns(handle, "image_collections").map(\.name),
                ["collection_id", "catalog_image_id"])
            // The per-image DELETE seam's index (Plan 16-1 T5 first-run
            // finding: the projector's R6 re-materialization needs the
            // reverse direction; the clustered PK only serves (tag, id)).
            XCTAssertTrue(
                try self.indexNames(handle, "image_tags").contains("idx_tags_image"),
                "idx_tags_image must back the projector's per-image delete")
        }
    }

    // MARK: - Indexes

    func testCompositeIdentityUniqueIndex() throws {
        try withFreshHandle { handle in
            let names = try self.indexNames(handle, "catalog_images")
            let autoindex = names.first { $0.hasPrefix("sqlite_autoindex") }
            let auto = try XCTUnwrap(autoindex, "UNIQUE(session_id, rel_path) autoindex")
            XCTAssertEqual(
                try self.indexColumns(handle, auto), ["session_id", "rel_path"])
        }
    }

    func testSixOrderingIndexesVerbatimShape() throws {
        try withFreshHandle { handle in
            let names = try self.indexNames(handle, "catalog_images")
            for expected in CatalogIndexSchema.orderingIndexNames {
                XCTAssertTrue(names.contains(expected), "missing \(expected)")
            }
            XCTAssertEqual(names.count, 7, "6 ordering + 1 UNIQUE autoindex")
            // The (k IS NULL, k [DESC], rel_path) shape — expression
            // columns come back as their SQL text from index_info.
            XCTAssertEqual(
                try self.indexColumns(handle, "idx_cat_cd_desc"),
                [nil, "capture_date", "rel_path"])
            XCTAssertEqual(
                try self.indexColumns(handle, "idx_cat_cd_asc"),
                [nil, "capture_date", "rel_path"])
            XCTAssertEqual(
                try self.indexColumns(handle, "idx_cat_rt_desc"),
                [nil, "rating", "rel_path"])
            XCTAssertEqual(
                try self.indexColumns(handle, "idx_cat_rt_asc"),
                [nil, "rating", "rel_path"])
            XCTAssertEqual(
                try self.indexColumns(handle, "idx_cat_fn"),
                [nil, "filename", "rel_path"])
            XCTAssertEqual(
                try self.indexColumns(handle, "idx_cat_rel"), ["rel_path"])
            // DESC directions live in the index XInfo (index_info reports
            // the expression name; the DESC keyword is asserted via the
            // master SQL text — the F6 verbatim-shape lock).
            let statement = try handle.prepare(
                "SELECT sql FROM sqlite_master WHERE name = 'idx_cat_cd_desc'")
            guard try statement.step(), let sql = statement.columnText(0) else {
                return XCTFail("idx_cat_cd_desc missing")
            }
            XCTAssertTrue(sql.contains("capture_date DESC"), sql)
        }
    }

    // MARK: - Pragma baseline (VERBATIM)

    func testPragmaBaselineVerbatim() throws {
        try withFreshHandle { handle in
            func pragma(_ sql: String) throws -> String? {
                let statement = try handle.prepare(sql)
                return try statement.step() ? statement.columnText(0) : nil
            }
            XCTAssertEqual(try pragma("PRAGMA journal_mode"), "wal")
            XCTAssertEqual(try pragma("PRAGMA synchronous"), "1") // NORMAL
            XCTAssertEqual(try pragma("PRAGMA cache_size"), "-64000")
            XCTAssertEqual(try pragma("PRAGMA busy_timeout"), "5000")
            // case_sensitive_like is WRITE-ONLY (no query form in SQLite) —
            // assert it BEHAVIORALLY: LIKE must distinguish case now.
            let probe = try handle.prepare("SELECT LIKE('ABC%', 'abc')")
            if try probe.step() {
                XCTAssertEqual(probe.columnInt(0), 0, "LIKE must be case-sensitive")
            }
        }
    }

    // MARK: - Version dispatch / refusals / idempotence

    func testFreshCreateStampsVersionOne() throws {
        try withFreshHandle { handle in
            XCTAssertEqual(try self.readMeta(handle), "1")
        }
    }

    func testReapplyIdempotentZeroHarm() throws {
        try withFreshHandle { handle in
            try CatalogIndexSchema.apply(to: handle)
            try CatalogIndexSchema.apply(to: handle)
            XCTAssertEqual(try self.readMeta(handle), "1")
            let columns = try self.tableColumns(handle, "catalog_images")
            XCTAssertEqual(columns.count, 31)
        }
    }

    func testV99Refused() throws {
        try withFreshHandle { handle in }  // create v1 file first
        // Reopen and poison the stamp.
        let handle = try SQLiteHandle(path: databaseURL.path)
        try handle.execute("UPDATE meta SET value = '99' WHERE key = 'schemaVersion'")
        handle.close()
        let reopened = try SQLiteHandle(path: databaseURL.path)
        defer { reopened.close() }
        XCTAssertThrowsError(try CatalogIndexSchema.apply(to: reopened)) { error in
            guard case SessionIndexError.schemaFailed(let detail, _, _) = error else {
                return XCTFail("expected schemaFailed, got \(error)")
            }
            XCTAssertTrue(detail.contains("v99"), detail)
        }
        // The refusal must NOT rewrite the stamp (the file is left for the
        // user / the rebuild flow, never "fixed" silently).
        let check = try SQLiteHandle(path: databaseURL.path)
        defer { check.close() }
        XCTAssertEqual(try self.readMeta(check), "99")
    }

    func testUnparsableVersionRefused() throws {
        try withFreshHandle { handle in }
        let handle = try SQLiteHandle(path: databaseURL.path)
        try handle.execute("UPDATE meta SET value = 'not-a-version'")
        handle.close()
        let reopened = try SQLiteHandle(path: databaseURL.path)
        defer { reopened.close() }
        XCTAssertThrowsError(try CatalogIndexSchema.apply(to: reopened)) { error in
            guard case SessionIndexError.schemaFailed(_, _, let message) = error else {
                return XCTFail("expected schemaFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("unparsable"), message)
        }
    }

    /// L020 content-level: a REFUSED open leaves the database file
    /// BYTE-IDENTICAL (the destructive red line — the open path never
    /// rewrites a file it cannot understand).
    func testRefusedOpenLeavesFileBytesUntouched() throws {
        try withFreshHandle { handle in
            try handle.execute(
                "UPDATE meta SET value = '99' WHERE key = 'schemaVersion'")
        }
        let before = try Data(contentsOf: databaseURL)
        let reopened = try SQLiteHandle(path: databaseURL.path)
        XCTAssertThrowsError(try CatalogIndexSchema.apply(to: reopened))
        reopened.close()
        let after = try Data(contentsOf: databaseURL)
        XCTAssertEqual(before, after, "refused open rewrote the file")
    }

    // MARK: - Migration slot (v1: no-op)

    func testMigrateSlotIsNoOpAtV1() throws {
        try withFreshHandle { handle in
            try CatalogIndexSchema.migrate(from: 0, to: 1, on: handle)
            XCTAssertEqual(try self.readMeta(handle), "1")
            XCTAssertEqual(try self.tableColumns(handle, "catalog_images").count, 31)
        }
    }

    // MARK: - Location constant

    func testDefaultLocationConvention() {
        let url = CatalogIndexSchema.defaultDatabaseURL()
        XCTAssertTrue(url.path.contains("Lightamer/Catalog"))
        XCTAssertTrue(url.lastPathComponent == "catalog.lcat")
        XCTAssertTrue(
            url.path.contains("Application Support"),
            "SmartAlbumStore.swift:78-85 same-directory convention")
    }
}
