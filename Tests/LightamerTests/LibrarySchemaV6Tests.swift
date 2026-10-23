import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySchemaV6Tests (Plan LUMEN-A T1, X1) — the v6 culling-analysis
// migration contract (the LibrarySchemaV5Tests family, one generation on):
//
//   ① fresh create: the seven analysis columns born on the images tail;
//      user_version == 6; the imagesColumns freeze face pins all 36
//      (the review M-1 double-registration: DDL + the frozen array)
//   ② a v5 package (built through the REAL 1→5 slots, stamped 5) opens →
//      the dispatch snapshot 5-6 → migrate → 6, pre-existing row values
//      zero-drift, the seven new columns read NULL (zero backfill — the
//      analysis pass fills lazily)
//   ③ idempotent: migrate(5→6) twice — zero error; a HALF-migrated body
//      (one column hand-ALTERed, snapshot-replay simulation) completes
//      the remaining six clean
//   ④ the ProjectFileStore pre-migrate snapshot hook consumed on the
//      5→6 leg (generation-named) — the existing hook, zero new mechanism
//
// Fixtures in NSTemporaryDirectory (L009: never external volume).
// ─────────────────────────────────────────────────────────────────────────────

final class LibrarySchemaV6Tests: XCTestCase {

    /// The seven v6 additive columns IN ORDER (the DDL tail — the same
    /// spelling the frozen array carries; the review M-1 double face).
    static let cullingColumns: [(name: String, type: String)] = [
        ("analysis_version", "INTEGER"),
        ("sharpness", "REAL"),
        ("faces", "INTEGER"),
        ("eyes_closed", "INTEGER"),
        ("signature", "BLOB"),
        ("face_boxes", "TEXT"),
        ("camera_serial", "TEXT"),
    ]

    private var tempDirectory: URL!
    private var databaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-schema-v6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        databaseURL = tempDirectory.appendingPathComponent("CullProj.lalb")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// Open, apply the schema (fresh create leg), run the body, close.
    private func withFreshHandle(
        projectName: String? = "CullProj",
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

    private func readUserVersion(_ url: URL) throws -> Int {
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        return try LibrarySchema.readUserVersion(from: handle)
    }

    /// A REAL v5 package: the full v1 DDL (the frozen history) walked
    /// through the actual migration slots 1→5, then stamped 5, with one
    /// populated row (the zero-drift witness).
    private func makeV5Package(at url: URL) throws {
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
        try handle.execute(
            "INSERT INTO images (image_path, path_kind, camera_make,"
                + " capture_date, rating) VALUES"
                + " ('Media/legacy.ARW', 0, 'Canon', 1730000000.25, 3)")
        try LibrarySchema.writeUserVersion(1, to: handle)
        // The v2→v5 body through the REAL slots (the V5Tests fixture
        // precedent — hand-writing four DDL families would drift from the
        // slots it must match).
        try LibrarySchema.migrate(from: 1, to: 5, on: handle)
    }

    /// The seven-tail presence pin (the DDL face).
    private func assertCullingColumnsPresent(_ handle: SQLiteHandle) throws {
        let columns = try tableColumns(handle, "images")
        for column in Self.cullingColumns {
            let found = columns.first { $0.name == column.name }
            XCTAssertNotNil(found, "column \(column.name) must exist post-migration")
            XCTAssertEqual(found?.type, column.type)
        }
        // The tail position: the last seven names ARE the family, IN ORDER.
        XCTAssertEqual(
            columns.suffix(7).map(\.name),
            Self.cullingColumns.map(\.name),
            "the additive family rides the DDL/array tail, in order")
    }

    // MARK: - ① Fresh create

    func testFreshCreateCarriesCullingColumnsFromBirth() throws {
        try withFreshHandle { handle in
            try assertCullingColumnsPresent(handle)
            // The review M-1 freeze face: the frozen array (36 entries,
            // seven-appended) matches PRAGMA table_info VERBATIM.
            let columns = try tableColumns(handle, "images")
            XCTAssertEqual(columns.count, LibrarySchema.imagesColumns.count)
            XCTAssertEqual(LibrarySchema.imagesColumns.count, 36)
            for (actual, expected) in zip(columns, LibrarySchema.imagesColumns) {
                XCTAssertEqual(actual.name, expected.name)
                XCTAssertEqual(actual.type, expected.type)
            }
            XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 6)
        }
    }

    // MARK: - ② v5 → v6 through the real dispatch (+ snapshot + zero drift)

    func testV5PackageMigratesToSixPreservesDataAndSnapshots() async throws {
        let v5URL = tempDirectory.appendingPathComponent("legacy-v5.lalb")
        try makeV5Package(at: v5URL)
        XCTAssertEqual(try readUserVersion(v5URL), 5)

        let store = ProjectFileStore(at: v5URL)
        _ = try await store.open()
        // ④ The snapshot hook consumed — the EXISTING generation-named
        // hook, zero new mechanism (X1).
        let snapshotURL = v5URL.deletingPathExtension()
            .appendingPathExtension("pre-migrate.5-6.bak")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "the pre-migration snapshot hook consumed (generation 5-6)")
        try await store.close()

        let handle = try SQLiteHandle(path: v5URL.path)
        defer { handle.close() }
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 6)
        try assertCullingColumnsPresent(handle)

        // Zero drift: the pre-existing row's values stand byte-intact.
        let row = try handle.prepare(
            "SELECT image_path, camera_make, capture_date, rating"
                + " FROM images WHERE id = 1")
        try XCTAssertTrue(row.step())
        XCTAssertEqual(row.columnText(0), "Media/legacy.ARW")
        XCTAssertEqual(row.columnText(1), "Canon")
        XCTAssertEqual(row.columnDouble(2) ?? 0, 1730000000.25, accuracy: 1e-9)
        XCTAssertEqual(row.columnInt(3), 3)

        // Zero backfill: every analysis column reads NULL (the lazy-fill
        // red line — an un-analysed row IS a NULL row).
        let nulls = try handle.prepare(
            "SELECT analysis_version, sharpness, faces, eyes_closed,"
                + " signature, face_boxes, camera_serial FROM images WHERE id = 1")
        try XCTAssertTrue(nulls.step())
        for index in 0..<7 {
            XCTAssertNil(
                nulls.columnText(Int32(index)),
                "analysis column \(index) must read NULL on a legacy row")
        }
    }

    // MARK: - ③ Idempotent + half-migrated re-run

    func testCullingMigrationIdempotentAndHalfMigratedRerun() throws {
        // Double call: the probe skips every landed ALTER (zero dupes).
        let url = tempDirectory.appendingPathComponent("idempotent-v6.lalb")
        try makeV5Package(at: url)
        let handle = try SQLiteHandle(path: url.path)
        try LibrarySchema.migrate(from: 5, to: 6, on: handle)
        try LibrarySchema.migrate(from: 5, to: 6, on: handle) // re-run
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 6)
        try assertCullingColumnsPresent(handle)
        // The master holds exactly one registration per column (PRAGMA
        // table_info count pins it — a duplicate ALTER would throw, a
        // duplicate DDL row cannot exist).
        let columns = try tableColumns(handle, "images")
        for column in Self.cullingColumns {
            XCTAssertEqual(
                columns.filter { $0.name == column.name }.count, 1,
                "\(column.name) registered exactly once")
        }
        handle.close()

        // Half-migrated snapshot replay: one column hand-ALTERed (the
        // batch list's FIRST — a faithful in-order partial), then migrate —
        // the probe lands the missing six, skips the present one. Presence
        // + types only here: a hand-ALTERed column need not sit at the
        // array tail position (the ORDER pin belongs to the fresh-create
        // face above; the probe's contract is presence).
        let halfURL = tempDirectory.appendingPathComponent("half-v6.lalb")
        try makeV5Package(at: halfURL)
        let half = try SQLiteHandle(path: halfURL.path)
        try half.exec("ALTER TABLE images ADD COLUMN analysis_version INTEGER")
        try LibrarySchema.migrate(from: 5, to: 6, on: half)
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: half), 6)
        let halfColumns = try tableColumns(half, "images")
        for column in Self.cullingColumns {
            let found = halfColumns.first { $0.name == column.name }
            XCTAssertNotNil(found, "\(column.name) present after the replay")
            XCTAssertEqual(found?.type, column.type)
        }
        half.close()
    }
}
