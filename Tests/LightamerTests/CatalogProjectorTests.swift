import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 16-1 T2 — the watermark projector:
//
//   • PARITY: catalog row vs source lindex row — all 29 mirrored columns
//     asserted INDIVIDUALLY (L020 content-level) + session_id (the 34→31
//     contextualization: the five non-mirrored columns never appear)
//   • KEY-SET RECONCILE (research correction ①): deleted lindex rows close
//     in the catalog (row + tags)
//   • WATERMARK: incremental add / change / idempotent re-project — no row
//     lost, no double apply
//   • TAG GOLDEN: the five materialized-string forms (NULL / '' / flat /
//     hierarchical / mixed) + the CROSS-DOMAIN DIRECTIONAL comparison
//     (catalog row set ⊆ session four-clause row set — research §6's
//     same-source-superset ruling replaces the CONTEXT equality check)
//   • UPSERT KEEPS the id (R1: organization references never dangle)
//   • OFFLINE marking + recovery; the enable guard = ZERO .lcat handle
//   • ROLLBACK: an injected failure leaves the catalog exactly as before
//   • the App-side openAndSync hook: disabled → zero handles end-to-end
//
// Fixtures are RAW lindex databases (SessionIndexMigrationTests' direct-
// handle style — the tests own every column value; L009: never external-volume).
// ─────────────────────────────────────────────────────────────────────────────

final class CatalogProjectorTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!
    private var catalogURL: URL!
    private var defaultsSuiteName: String!

    private var lindexURL: URL {
        SessionIndexSchema.databaseURL(forSessionRoot: sessionRoot)
    }

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-proj-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot, withIntermediateDirectories: true)
        catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
        defaultsSuiteName = "catalog-proj-tests-\(UUID().uuidString)"
        CatalogPreferences.setCatalogsEnabled(true, defaultsSuiteName: defaultsSuiteName)
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func makeProjector() -> CatalogProjector {
        CatalogProjector(databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
    }

    // MARK: - lindex fixture (direct handle — full column control)

    @discardableResult
    private func makeLindex(
        rows: [String], keywords: [String: String?], epoch: Int64 = 1
    ) throws -> Int64 {
        try FileManager.default.createDirectory(
            at: lindexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: lindexURL.path)
        defer { handle.close() }
        try SessionIndexSchema.apply(to: handle)
        let stampEpoch = try handle.prepare(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('scan_epoch', ?)")
        try stampEpoch.bindText(1, String(epoch))
        _ = try stampEpoch.step()
        for relPath in rows {
            try insertFixtureRow(
                handle, relPath: relPath, keywords: keywords[relPath] ?? nil,
                epoch: epoch)
        }
        return epoch
    }

    private func insertFixtureRow(
        _ handle: SQLiteHandle, relPath: String, keywords: String?, epoch: Int64
    ) throws {
        let dir = (relPath as NSString).deletingLastPathComponent
        let insert = try handle.prepare("""
            INSERT INTO images (
              path, dir, filename, file_size, file_mtime, scan_epoch,
              imageID, sidecar_present, sidecar_mtime, has_edits,
              params_hash, layer_count, layer_summary, orientation,
              width, height, capture_date, rating, color_label, keywords,
              orphan_sidecar, dirty, flag, note,
              camera_make, camera_model, lens_model, iso, focal_length,
              aperture, exposure
            ) VALUES (?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?,
                      ?, ?, ?, ?,
                      ?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?,
                      ?, ?, ?, ?, ?,
                      ?, ?)
            """)
        try insert.bindText(1, relPath)
        try insert.bindText(2, dir.isEmpty ? nil : dir)
        try insert.bindText(3, (relPath as NSString).lastPathComponent)
        try insert.bindInt(4, 987654321)
        try insert.bindDouble(5, -12_345.678)
        try insert.bindInt(6, epoch)
        try insert.bindText(7, "11111111-2222-3333-4444-555555555555")
        try insert.bindInt(8, 1)
        try insert.bindDouble(9, 1234.5)
        try insert.bindInt(10, 1)
        try insert.bindText(11, "18446744073709551615")  // L013 decimal TEXT
        try insert.bindInt(12, 3)
        try insert.bindText(
            13, "[{\"blend\":0,\"name\":\"x\",\"visible\":true}]")
        try insert.bindInt(14, 6)
        try insert.bindInt(15, 8256)
        try insert.bindInt(16, 5504)
        try insert.bindDouble(17, 1_700_000_123.25)
        try insert.bindInt(18, 4)
        try insert.bindInt(19, 2)
        try insert.bindText(20, keywords)
        try insert.bindInt(21, 0)
        try insert.bindInt(22, 0)
        try insert.bindInt(23, 1)
        try insert.bindText(24, "keep this ✂ text")
        try insert.bindText(25, "Sony")
        try insert.bindText(26, "A7R V")
        try insert.bindText(27, "FE 24-70 F2.8 GM II")
        try insert.bindInt(28, 6400)
        try insert.bindDouble(29, 68.0)
        try insert.bindDouble(30, 2.8)
        try insert.bindDouble(31, 0.008)
        _ = try insert.step()
    }

    /// Open the fixture lindex for a mutation (a new epoch stamp included).
    private func withLindex(_ body: (SQLiteHandle) throws -> Void) throws {
        let handle = try SQLiteHandle(path: lindexURL.path)
        defer { handle.close() }
        try body(handle)
    }

    // MARK: - catalog-side reads (independent read-only connections)

    private func openCatalogReadonly() throws -> SQLiteHandle {
        try SQLiteHandle(
            path: catalogURL.path,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
    }

    /// All catalog_images rows: the 29 mirror columns (rel_path first, the
    /// lindex SELECT order) + id. Sorted by rel_path.
    private func readCatalogRows()
        throws -> (columnsByRow: [[String?]], ids: [Int64], sessionID: String)
    {
        let handle = try openCatalogReadonly()
        defer { handle.close() }
        let sessionStatement = try handle.prepare(
            "SELECT session_id FROM catalog_sessions")
        let sid = try sessionStatement.step()
            ? sessionStatement.columnText(0) ?? "" : ""
        let selectList = ["rel_path"] + CatalogProjector.mirrorTailColumns
        let statement = try handle.prepare(
            "SELECT \(selectList.joined(separator: ", ")), id "
                + "FROM catalog_images ORDER BY rel_path")
        var rows: [[String?]] = []
        var ids: [Int64] = []
        while try statement.step() {
            var columns: [String?] = []
            for i: Int32 in 0..<29 { columns.append(statement.columnText(i)) }
            rows.append(columns)
            ids.append(statement.columnInt(29) ?? 0)
        }
        return (rows, ids, sid)
    }

    private func scalar(_ sql: String) throws -> (text: String?, int: Int64?) {
        let handle = try openCatalogReadonly()
        defer { handle.close() }
        let statement = try handle.prepare(sql)
        guard try statement.step() else { return (nil, nil) }
        return (statement.columnText(0), statement.columnInt(0))
    }

    private func tagSet(of relPath: String) throws -> Set<String> {
        let handle = try openCatalogReadonly()
        defer { handle.close() }
        let s = try handle.prepare("""
            SELECT t.tag FROM image_tags t
            JOIN catalog_images i ON i.id = t.catalog_image_id
            WHERE i.rel_path = ?
            """)
        try s.bindText(1, relPath)
        var rows = Set<String>()
        while try s.step() { rows.insert(s.columnText(0) ?? "") }
        return rows
    }

    // MARK: - Tag golden (pure, §6 verbatim)

    func testTagRowsGoldenFiveForms() {
        // ① NULL = never tagged
        XCTAssertEqual(CatalogProjector.tagRows(fromMaterialized: nil), [])
        // ② empty string = cleared
        XCTAssertEqual(CatalogProjector.tagRows(fromMaterialized: ""), [])
        // ③ flat multi-tag
        XCTAssertEqual(
            CatalogProjector.tagRows(fromMaterialized: "X|Y"),
            ["X", "Y", "X|Y"])
        // ④ hierarchical
        XCTAssertEqual(
            CatalogProjector.tagRows(fromMaterialized: "A|B|C"),
            ["A", "B", "C", "A|B", "A|B|C"])
        // ⑤ mixed (hierarchy + an extra flat tag in one string)
        XCTAssertEqual(
            CatalogProjector.tagRows(fromMaterialized: "A|B|C|X"),
            ["A", "B", "C", "X", "A|B", "A|B|C", "A|B|C|X"])
    }

    // MARK: - Parity (29 mirrored columns, individually)

    func testParityTwentyNineMirroredColumns() async throws {
        try makeLindex(rows: ["a.arw", "sub/nested.arw"], keywords: ["a.arw": "Nature"])
        let projector = makeProjector()
        let result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.removed, 0)
        XCTAssertNotEqual(result.sessionID, "")

        let read = try readCatalogRows()
        XCTAssertEqual(read.sessionID, result.sessionID)
        XCTAssertEqual(read.columnsByRow.count, 2)

        // The lindex source values (an independent read; same SELECT list).
        let lindex = try SQLiteHandle(
            path: lindexURL.path, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
        defer { lindex.close() }
        let source = try lindex.prepare(
            "SELECT \(CatalogProjector.lindexSelectColumns) FROM images WHERE path = 'a.arw'")
        try source.step()

        // a.arw sorts first.
        let catalogColumns = read.columnsByRow[0]
        XCTAssertEqual(catalogColumns[0], "a.arw", "rel_path carries the lindex path")
        for (mirrorIndex, name) in CatalogIndexSchema.mirroredSourceColumns.enumerated() {
            guard name != "path" else { continue }
            let sourceText = source.columnText(Int32(mirrorIndex))
            let catalogText = catalogColumns[mirrorIndex]
            switch name {
            case "file_size", "sidecar_present", "has_edits", "layer_count",
                "orientation", "width", "height", "rating", "color_label",
                "orphan_sidecar", "flag", "iso":
                XCTAssertEqual(
                    catalogText.flatMap(Int64.init), sourceText.flatMap(Int64.init),
                    "mirror column \(name) parity")
            case "file_mtime", "sidecar_mtime", "capture_date", "focal_length",
                "aperture", "exposure":
                XCTAssertEqual(
                    catalogText.flatMap(Double.init), sourceText.flatMap(Double.init),
                    "mirror column \(name) parity")
            default:
                XCTAssertEqual(catalogText, sourceText, "mirror column \(name) parity")
            }
        }
        // The five non-mirrored columns: provably absent from the table.
        let probe = try openCatalogReadonly()
        defer { probe.close() }
        XCTAssertThrowsError(
            try probe.execute("SELECT scan_epoch FROM catalog_images LIMIT 1"))
        XCTAssertThrowsError(
            try probe.execute("SELECT thumb_path FROM catalog_images LIMIT 1"))
    }

    // MARK: - Key-set reconcile (correction ①)

    func testKeysetReconcileClosesDeletions() async throws {
        try makeLindex(
            rows: ["a.arw", "b.arw"],
            keywords: ["a.arw": "Keep", "b.arw": "Doomed"])
        let projector = makeProjector()
        var result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.added, 2)

        // b.arw vanishes on the lindex side (the pure watermark diff cannot
        // see this — the reconcile leg must).
        try withLindex { handle in
            try handle.execute("DELETE FROM images WHERE path = 'b.arw'")
        }
        result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.removed, 1, "the deleted row must close")
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(try readCatalogRows().columnsByRow.count, 1)
        XCTAssertEqual(try readCatalogRows().columnsByRow[0][0], "a.arw")
        XCTAssertEqual(
            try scalar("SELECT COUNT(*) FROM image_tags WHERE tag = 'Doomed'").int, 0,
            "no orphan tag rows survive the deleted image")
    }

    // MARK: - Watermark (increment + idempotence)

    func testWatermarkIncrementalIdempotentNoLoss() async throws {
        try makeLindex(rows: ["a.arw"], keywords: ["a.arw": nil], epoch: 1)
        let projector = makeProjector()
        var result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(
            try scalar("SELECT last_projected_epoch FROM catalog_sessions").int, 1)

        // NEW row at a HIGHER epoch → only the increment projects.
        try withLindex { handle in
            try self.insertFixtureRow(
                handle, relPath: "b.arw", keywords: "Fresh", epoch: 2)
            try handle.execute(
                "UPDATE meta SET value = '2' WHERE key = 'scan_epoch'")
        }
        result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.added, 1, "only the new row")
        XCTAssertEqual(result.changed, 0)
        XCTAssertEqual(
            try scalar("SELECT last_projected_epoch FROM catalog_sessions").int, 2)

        // Re-project: idempotent (nothing new).
        result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.changed, 0)
        XCTAssertEqual(try readCatalogRows().columnsByRow.count, 2)

        // CHANGE an existing row (new epoch) → the changed leg.
        try withLindex { handle in
            try handle.execute(
                "UPDATE images SET rating = 5, scan_epoch = 3 WHERE path = 'a.arw'")
            try handle.execute(
                "UPDATE meta SET value = '3' WHERE key = 'scan_epoch'")
        }
        result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.changed, 1)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(
            try scalar("SELECT rating FROM catalog_images WHERE rel_path = 'a.arw'").int, 5)
    }

    // MARK: - Tag materialization (integration) + cross-domain direction

    func testTagMaterializationAndCrossDomainDirection() async throws {
        try makeLindex(
            rows: ["k1.arw", "k2.arw", "k3.arw", "k4.arw"],
            keywords: ["k1.arw": "A|B|C", "k2.arw": "X|Y",
                       "k3.arw": nil, "k4.arw": ""],
            epoch: 1)
        _ = try await makeProjector().project(sessionRoot: sessionRoot)

        // image_tags row set per image (integration golden — all forms).
        XCTAssertEqual(
            try tagSet(of: "k1.arw"), ["A", "B", "C", "A|B", "A|B|C"])
        XCTAssertEqual(try tagSet(of: "k2.arw"), ["X", "Y", "X|Y"])
        XCTAssertEqual(try tagSet(of: "k3.arw"), [], "NULL keywords → ∅ rows")
        XCTAssertEqual(try tagSet(of: "k4.arw"), [], "empty-string keywords → ∅ rows")

        // CROSS-DOMAIN DIRECTIONALITY (research §6 裁决 — catalog ⊆ session
        // for the SAME tag): the mid-path 'B|C' hits the session four-clause
        // (the '%|' || tag tail clause) but has NO image_tags row.
        let handle = try openCatalogReadonly()
        defer { handle.close() }
        let sessionQuery = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .keywords, op: .contains, value: .text("B|C")),
            ]))
        let sessionStatement = try handle.prepare(
            "SELECT rel_path FROM catalog_images WHERE \(sessionQuery.whereClause)")
        try FilterSQL.apply(sessionQuery.binds, to: sessionStatement)
        var sessionSet = Set<String>()
        while try sessionStatement.step() {
            sessionSet.insert(sessionStatement.columnText(0) ?? "")
        }
        let catalogStatement = try handle.prepare("""
            SELECT i.rel_path FROM catalog_images i
            WHERE EXISTS (SELECT 1 FROM image_tags t
                          WHERE t.tag = 'B|C' AND t.catalog_image_id = i.id)
            """)
        var catalogSet = Set<String>()
        while try catalogStatement.step() {
            catalogSet.insert(catalogStatement.columnText(0) ?? "")
        }
        XCTAssertTrue(sessionSet.contains("k1.arw"), "session four-clause hits B|C")
        XCTAssertTrue(catalogSet.isEmpty, "no materialized B|C row — by design")
        XCTAssertTrue(
            catalogSet.isSubset(of: sessionSet),
            "catalog row set ⊆ session row set (same-source superset)")
    }

    // MARK: - UPSERT keeps the id (R1)

    func testUpsertPreservesIDAndTagsReference() async throws {
        try makeLindex(rows: ["a.arw"], keywords: ["a.arw": "Old|Path"], epoch: 1)
        let projector = makeProjector()
        _ = try await projector.project(sessionRoot: sessionRoot)
        let originalID = try readCatalogRows().ids[0]

        // Change the keywords, new epoch, re-project.
        try withLindex { handle in
            try handle.execute(
                "UPDATE images SET keywords = 'New' WHERE path = 'a.arw'")
            try handle.execute("UPDATE images SET scan_epoch = 2")
            try handle.execute(
                "UPDATE meta SET value = '2' WHERE key = 'scan_epoch'")
        }
        _ = try await projector.project(sessionRoot: sessionRoot)
        let second = try readCatalogRows()
        XCTAssertEqual(second.ids[0], originalID, "UPSERT conflict keeps the id")
        XCTAssertEqual(try tagSet(of: "a.arw"), ["New"],
                       "old tags gone; new tags reference the kept id")
    }

    // MARK: - Offline marking

    func testOfflineMarkAndRecovery() async throws {
        try makeLindex(rows: ["a.arw"], keywords: ["a.arw": nil], epoch: 7)
        let projector = makeProjector()
        _ = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(try scalar("SELECT offline FROM catalog_sessions").int, 0)
        let watermark = try scalar("SELECT last_projected_epoch FROM catalog_sessions").int

        // Remove the lindex → offline=1, watermark UNTOUCHED.
        let parked = tempDirectory.appendingPathComponent("parked.lindex")
        try FileManager.default.moveItem(at: lindexURL, to: parked)
        let result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.offline, true)
        XCTAssertEqual(try scalar("SELECT offline FROM catalog_sessions").int, 1)
        XCTAssertEqual(
            try scalar("SELECT last_projected_epoch FROM catalog_sessions").int,
            watermark, "offline projection must not move the watermark")

        // Restore → online again.
        try FileManager.default.moveItem(at: parked, to: lindexURL)
        _ = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(try scalar("SELECT offline FROM catalog_sessions").int, 0)
    }

    // MARK: - Registry (UUIDv4 / reuse / display name)

    func testRegistryMintReuseAndDisplay() async throws {
        try makeLindex(rows: ["a.arw"], keywords: ["a.arw": nil])
        let projector = makeProjector()
        let first = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertNotNil(UUID(uuidString: first.sessionID),
                        "UUIDv4-shaped session_id")
        let second = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(second.sessionID, first.sessionID, "same folder → reuse")
        XCTAssertEqual(
            try scalar("SELECT display_name FROM catalog_sessions").text,
            sessionRoot.lastPathComponent)
    }

    // MARK: - Enable guard (zero-handle isolation)

    func testDisabledGuardCreatesNoCatalogFile() async throws {
        try makeLindex(rows: ["a.arw"], keywords: ["a.arw": nil])
        CatalogPreferences.setCatalogsEnabled(false, defaultsSuiteName: defaultsSuiteName)
        let projector = makeProjector()
        let result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.skippedByGuard, true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: catalogURL.path),
            "disabled Catalogs mode must not create the .lcat file")

        CatalogPreferences.setCatalogsEnabled(true, defaultsSuiteName: defaultsSuiteName)
        _ = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: catalogURL.path))
    }

    // MARK: - ROLLBACK atomicity

    func testInjectedFailureRollsBack() async throws {
        try makeLindex(rows: ["a.arw"], keywords: ["a.arw": nil], epoch: 1)
        let projector = makeProjector()
        _ = try await projector.project(sessionRoot: sessionRoot)
        let before = try readCatalogRows()

        // lindex gains a row; the projector dies before COMMIT.
        try withLindex { handle in
            try self.insertFixtureRow(
                handle, relPath: "b.arw", keywords: nil, epoch: 2)
            try handle.execute(
                "UPDATE meta SET value = '2' WHERE key = 'scan_epoch'")
        }
        await projector.setFailureInjection(.beforeCommit)
        do {
            _ = try await projector.project(sessionRoot: sessionRoot)
            XCTFail("expected the injected failure")
        } catch {
            // the typed SQL failure is the expected path
        }
        await projector.setFailureInjection(.none)
        let after = try readCatalogRows()
        XCTAssertEqual(after.columnsByRow.count, before.columnsByRow.count,
                       "ROLLBACK: the row set is exactly as before")
        XCTAssertEqual(after.columnsByRow[0][0], "a.arw")
    }

    // MARK: - Sweep (serial + recent backfill)

    func testSweepAllSerialAndRecentBackfill() async throws {
        try makeLindex(rows: ["a.arw"], keywords: ["a.arw": nil])
        let projector = makeProjector()
        _ = try await projector.project(sessionRoot: sessionRoot)

        // A second, never-projected session root with its own lindex.
        let secondRoot = tempDirectory.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(
            at: secondRoot, withIntermediateDirectories: true)
        let secondLindex = SessionIndexSchema.databaseURL(forSessionRoot: secondRoot)
        try FileManager.default.createDirectory(
            at: secondLindex.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let secondHandle = try SQLiteHandle(path: secondLindex.path)
        try SessionIndexSchema.apply(to: secondHandle)
        try insertFixtureRow(secondHandle, relPath: "s.arw", keywords: nil, epoch: 1)
        secondHandle.close()

        let results = await projector.sweepAll(recentRoots: [secondRoot])
        XCTAssertEqual(results.count, 2, "registered sweep + recent backfill")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM catalog_sessions").int, 2)
    }

    // MARK: - App-side hook (double-mode isolation)

    /// The SessionIndexController hook: disabled → openAndSync runs the
    /// FULL session flow with the projector never constructed (zero .lcat
    /// handle end-to-end); enabled → the temp catalog gets the projection.
    /// (The hook path uses the REAL scanner, so the fixture includes a real
    /// file on disk.)
    func testOpenAndSyncHookRespectsGuard() async throws {
        let rootURL = try XCTUnwrap(sessionRoot)
        let tempCatalogURL = try XCTUnwrap(catalogURL)
        try makeLindex(rows: ["a.arw"], keywords: ["a.arw": "Hook"])
        try Data("x".utf8).write(
            to: rootURL.appendingPathComponent("a.arw"), options: .atomic)

        // Disabled: the full open flow, zero .lcat handle.
        CatalogPreferences.setCatalogsEnabled(false, defaultsSuiteName: defaultsSuiteName)
        try await runOpenAndSyncExpectingSuccess(root: rootURL)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempCatalogURL.path),
            "disabled: the hook must not open any .lcat handle")

        // Enabled: the detached hook projects (poll for its commit — the
        // task is fire-and-forget by design).
        CatalogPreferences.setCatalogsEnabled(true, defaultsSuiteName: defaultsSuiteName)
        try await runOpenAndSyncExpectingSuccess(root: rootURL)
        var exists = FileManager.default.fileExists(atPath: tempCatalogURL.path)
        var attempts = 0
        while !exists, attempts < 200 {
            try await Task.sleep(nanoseconds: 50_000_000)
            exists = FileManager.default.fileExists(atPath: tempCatalogURL.path)
            attempts += 1
        }
        XCTAssertTrue(exists, "enabled: the hook projects")
        var rowCount = 0
        if let counted = try? readCatalogRows() { rowCount = counted.columnsByRow.count }
        attempts = 0
        while rowCount != 1, attempts < 200 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if let counted = try? readCatalogRows() {
                rowCount = counted.columnsByRow.count
            }
            attempts += 1
        }
        XCTAssertEqual(rowCount, 1)
    }

    // MARK: - MainActor bridge (SessionIndexController is @MainActor)

    private func runOpenAndSyncExpectingSuccess(root: URL) async throws {
        let controller = await SessionIndexController()
        let suiteName = self.defaultsSuiteName!
        let catalogURL = self.catalogURL!
        await MainActor.run {
            controller.catalogProjectorProvider = {
                CatalogProjector(databaseURL: catalogURL, defaultsSuiteName: suiteName)
            }
        }
        let result = await controller.openAndSync(root: root)
        XCTAssertFalse(result.failed)
    }
}
