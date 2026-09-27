import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// CatalogRebuildTests (Plan 16-4 T2) — the off-library rebuild specialization
// (RQ-16-14 两档 + the 损坏处置 entry).
//
//   reconcile  — clear watermarks → full re-projection: row-set parity,
//                IDs KEPT (the UPSERT conflict leg), organization data
//                (categories/collections/memberships) FULLY ALIVE, and the
//                session-boundary cancellation + idempotent resume.
//   destructive— fresh `catalog.lcat.tmp` → verify → same-directory rename
//                promotion (L009; NO in-database mass DELETE — F12):
//                metadata parity + the HONEST organization-data boundary
//                (empty organization tables in the new file) + the `.bak`
//                one-step retention + the rollback leg (an injected
//                after-backup-move failure leaves the original byte-
//                identical).
//   损坏处置   — v99 schemaFailed: the typed error surfaces, the destructive
//                repair recovers the file, Sessions mode sees ZERO impact.
//
// Fixtures are RAW lindex databases (the CatalogProjectorTests direct-handle
// style; L009: never external volume; throwaway /tmp state only).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CatalogRebuildTests: XCTestCase {

    private var tempDirectory: URL!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-rebuild-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        defaultsSuiteName = "catalog-rebuild-tests-\(UUID().uuidString)"
        CatalogPreferences.setCatalogsEnabled(true, defaultsSuiteName: defaultsSuiteName)
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// A session root with a RAW lindex of `n` rows (rating = i%6, keywords
    /// "Nature|Flower" on every 2nd row → 3 tag rows per tagged image).
    @discardableResult
    private func makeSession(name: String, rows: Int, epoch: Int64 = 1) throws -> URL {
        let root = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        let lindexURL = SessionIndexSchema.databaseURL(forSessionRoot: root)
        try FileManager.default.createDirectory(
            at: lindexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: lindexURL.path)
        defer { handle.close() }
        try SessionIndexSchema.apply(to: handle)
        let stamp = try handle.prepare(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('scan_epoch', ?)")
        try stamp.bindText(1, String(epoch))
        _ = try stamp.step()
        let insert = try handle.prepare("""
            INSERT INTO images (
              path, dir, filename, file_size, file_mtime, scan_epoch,
              imageID, sidecar_present, sidecar_mtime, has_edits,
              params_hash, layer_count, layer_summary, orientation,
              width, height, capture_date, rating, color_label, keywords,
              orphan_sidecar, dirty, flag, note,
              camera_make, camera_model, lens_model, iso, focal_length,
              aperture, exposure
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        try handle.exec("BEGIN IMMEDIATE")
        for i in 0..<rows {
            let rel = String(format: "img%03d.arw", i)
            try insert.bindText(1, rel)
            try insert.bindText(2, nil)
            try insert.bindText(3, rel)
            try insert.bindInt(4, 4096)
            try insert.bindDouble(5, 1_700_000_000)
            try insert.bindInt(6, epoch)
            try insert.bindText(7, "\(name)-id-\(i)")
            try insert.bindInt(8, 0)
            try insert.bindDouble(9, 0)
            try insert.bindInt(10, 0)
            try insert.bindText(11, nil)
            try insert.bindInt(12, nil)
            try insert.bindText(13, nil)
            try insert.bindInt(14, 1)
            try insert.bindInt(15, 100)
            try insert.bindInt(16, 100)
            try insert.bindDouble(17, 1_700_000_000 + Double(i))
            try insert.bindInt(18, Int64(i % 6))
            try insert.bindInt(19, nil)
            if i % 2 == 0 { try insert.bindText(20, "Nature|Flower") }
            else { try insert.bindText(20, nil) }
            try insert.bindInt(21, 0)
            try insert.bindInt(22, 0)
            try insert.bindInt(23, nil)
            try insert.bindText(24, nil)
            try insert.bindText(25, "Sony")
            try insert.bindText(26, "A7R V")
            try insert.bindText(27, nil)
            try insert.bindInt(28, nil)
            try insert.bindDouble(29, nil)
            try insert.bindDouble(30, nil)
            try insert.bindDouble(31, nil)
            _ = try insert.step()
            try insert.reset()
        }
        try handle.exec("COMMIT")
        return root
    }

    private var catalogURL: URL {
        tempDirectory.appendingPathComponent("catalog.lcat")
    }

    private func makeRebuilder() -> CatalogRebuilder {
        CatalogRebuilder(databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
    }

    /// Raw peek (the test-side direct handle for drift/corruption asserts).
    /// `columns` = the SELECT list width (SQLiteStatement has no columnCount
    /// face — the width is a call-site fact here).
    private func queryRows(
        _ url: URL, _ sql: String, columns: Int
    ) throws -> [[String?]] {
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        let statement = try handle.prepare(sql)
        var rows: [[String?]] = []
        while try statement.step() {
            var row: [String?] = []
            for i in 0..<Int32(columns) {
                row.append(statement.columnText(i))
            }
            rows.append(row)
        }
        return rows
    }

    private func executeRaw(_ url: URL, _ sql: String) throws {
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        try handle.execute(sql)
    }

    // MARK: - Mode 1: the reconcile rebuild (the DEFAULT)

    /// Row drift (a corrupted mirrored column) + a lindex-side deletion:
    /// reconcile restores parity, KEEPS the surviving ids (the UPSERT
    /// conflict leg — R1), and the organization data survives untouched.
    func testReconcileRestoresDriftKeepingIDsAndOrganizations() async throws {
        let root = try makeSession(name: "session-a", rows: 6)
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        let projected = try await projector.project(sessionRoot: root)
        await projector.close()

        // The organization data: a category + a collection; memberships on a
        // SURVIVING row (img000) via the store's identity face.
        let organization = CatalogOrganizationStore(databaseURL: catalogURL)
        let categoryID = try await organization.createCategory(name: "Travel")
        let collectionID = try await organization.createCollection(name: "Picks")
        _ = try await organization.assign(
            images: [CatalogImageIdentity(
                sessionID: projected.sessionID, relPath: "img000.arw")],
            toCategoryID: categoryID)
        _ = try await organization.assign(
            images: [CatalogImageIdentity(
                sessionID: projected.sessionID, relPath: "img000.arw")],
            toCollectionID: collectionID)

        let idsBefore = try queryRows(
            catalogURL, "SELECT rel_path, id FROM catalog_images ORDER BY rel_path", columns: 2)
        XCTAssertEqual(idsBefore.count, 6)

        // Drift ①: corrupt a mirrored column on a surviving row.
        try executeRaw(
            catalogURL, "UPDATE catalog_images SET rating = NULL "
                + "WHERE rel_path = 'img003.arw'")
        // Drift ②: the lindex loses a row (the reconcile DELETE leg closes it).
        let lindexURL = SessionIndexSchema.databaseURL(forSessionRoot: root)
        let lindex = try SQLiteHandle(path: lindexURL.path)
        try lindex.execute("DELETE FROM images WHERE path = 'img005.arw'")
        lindex.close()

        let reconciled = try await makeRebuilder().reconcileRebuild()
        XCTAssertEqual(reconciled, 1, "one session reconciled")

        // Parity: the drifted rating restored, the deleted row closed out.
        let after = try queryRows(
            catalogURL, "SELECT rel_path, id, rating FROM catalog_images "
                + "ORDER BY rel_path", columns: 3)
        XCTAssertEqual(after.count, 5, "img005 left with its lindex deletion")
        XCTAssertFalse(after.contains { $0[0] == "img005.arw" })
        let drifted = after.first { $0[0] == "img003.arw" }
        XCTAssertEqual(drifted?[2], "3", "the corrupted rating re-projected")

        // IDs of the SURVIVING rows are unchanged (R1 — the conflict leg).
        for before in idsBefore where before[0] != "img005.arw" {
            let match = after.first { $0[0] == before[0] }
            XCTAssertEqual(match?[1], before[1], "id kept for \(before[0] ?? "?")")
        }

        // The organization data is FULLY ALIVE: one category, one collection,
        // and the survivor's memberships intact.
        let orgAfter = CatalogOrganizationStore(databaseURL: catalogURL)
        let tree = try await orgAfter.readTree()
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree.first?.name, "Travel")
        let collections = try await orgAfter.readCollections()
        XCTAssertEqual(collections.count, 1)
        let memberCount = try await orgAfter.memberCount(collectionID: collectionID)
        XCTAssertEqual(memberCount, 1, "the survivor's membership survived")
        await orgAfter.close()
    }

    /// Cancellation at a SESSION boundary keeps the completed sessions; a
    /// rerun is idempotent and converges (the plan's 可取消/可续跑 clause).
    func testReconcileCancellationKeepsCompletedSessionsAndResumes() async throws {
        let rootA = try makeSession(name: "session-a", rows: 4)
        let rootB = try makeSession(name: "session-b", rows: 4)
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        _ = try await projector.project(sessionRoot: rootA)
        _ = try await projector.project(sessionRoot: rootB)
        await projector.close()

        final class CancelBox: @unchecked Sendable {
            var task: Task<Int, Error>?
            var completedEvents: [Int] = []
        }
        let box = CancelBox()
        let rebuilder = makeRebuilder()
        await rebuilder.setProgressHandler { progress in
            box.completedEvents.append(progress.completedSessions)
            if progress.completedSessions >= 1 {
                box.task?.cancel()
            }
        }
        let task = Task { try await rebuilder.reconcileRebuild() }
        box.task = task
        do {
            _ = try await task.value
            XCTFail("the cancellation must surface")
        } catch is CancellationError {
            // the session-boundary abort
        }

        // Session A's watermark advanced (it re-projected); session B's is
        // still zeroed — its ROWS are intact (reconcile never mass-deletes).
        // (Registry root_path is the realpath-normalized form — L027.)
        let normalizedA = rootA.resolvingSymlinksInPath().path
        let normalizedB = rootB.resolvingSymlinksInPath().path
        let watermarks = try queryRows(
            catalogURL, "SELECT root_path, last_projected_epoch FROM catalog_sessions "
                + "ORDER BY root_path", columns: 2)
        XCTAssertEqual(watermarks.count, 2)
        let byRoot = Dictionary(
            watermarks.map { ($0[0] ?? "", $0[1] ?? "") }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byRoot[normalizedA], "1", "completed session retained")
        XCTAssertEqual(byRoot[normalizedB], "0", "pending session watermark still zero")
        let rowsMid = try queryRows(catalogURL, "SELECT COUNT(*) FROM catalog_images", columns: 1)
        XCTAssertEqual(rowsMid[0][0], "8", "no mass delete at any point")

        // The idempotent resume converges.
        await rebuilder.setProgressHandler(nil)
        let sessions = try await rebuilder.reconcileRebuild()
        XCTAssertEqual(sessions, 2)
        let total = try queryRows(catalogURL, "SELECT COUNT(*) FROM catalog_images", columns: 1)
        XCTAssertEqual(total[0][0], "8")
        let events = box.completedEvents
        XCTAssertEqual(events.first, 1, "progress fired per completed session")
    }

    // MARK: - Mode 2: the destructive rebuild (file-level recovery)

    /// The fresh file replaces the old one by RENAME (L009): metadata parity,
    /// the HONEST organization boundary (empty organization tables), NEW
    /// session ids, and the `.bak` one-step retention holding the OLD file's
    /// organization data (the single-file backup story, RQ-16-15).
    func testDestructiveRebuildReplacesFileOrganizationLostBackupKept() async throws {
        let rootA = try makeSession(name: "session-a", rows: 4)
        let rootB = try makeSession(name: "session-b", rows: 4)
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        let projectedA = try await projector.project(sessionRoot: rootA)
        let projectedB = try await projector.project(sessionRoot: rootB)
        await projector.close()

        let organization = CatalogOrganizationStore(databaseURL: catalogURL)
        let categoryID = try await organization.createCategory(name: "Travel")
        _ = try await organization.assign(
            images: [CatalogImageIdentity(
                sessionID: projectedA.sessionID, relPath: "img000.arw")],
            toCategoryID: categoryID)
        await organization.close()

        let oldIDs = Set(
            try queryRows(catalogURL, "SELECT session_id FROM catalog_sessions", columns: 1)
                .compactMap { $0[0] })

        let sessions = try await makeRebuilder()
            .destructiveRebuild(recentRoots: [rootA, rootB])
        XCTAssertEqual(sessions, 2, "both sessions restored")

        // Metadata parity through the read faces (grid / count / tags smoke).
        let store = CatalogIndexStore(databaseURL: catalogURL)
        let page = try await store.queryPage(
            groups: [], sort: .init(key: .filename, ascending: true))
        XCTAssertEqual(page.count, 8)
        let total = try await store.count(groups: [])
        XCTAssertEqual(total, 8)
        let tags = try await store.tagCounts()
        XCTAssertEqual(tags["Nature"], 4, "tag materialization re-projected")
        await store.close()

        // The HONEST boundary: the new file's organization tables are EMPTY.
        let newIDs = Set(
            try queryRows(catalogURL, "SELECT session_id FROM catalog_sessions", columns: 1)
                .compactMap { $0[0] })
        XCTAssertEqual(newIDs.count, 2)
        XCTAssertTrue(newIDs.isDisjoint(with: oldIDs), "fresh session ids minted")
        XCTAssertEqual(
            try queryRows(catalogURL, "SELECT COUNT(*) FROM categories", columns: 1)[0][0], "0")
        XCTAssertEqual(
            try queryRows(catalogURL, "SELECT COUNT(*) FROM collections", columns: 1)[0][0], "0")
        XCTAssertEqual(
            try queryRows(catalogURL, "SELECT COUNT(*) FROM image_categories", columns: 1)[0][0],
            "0")
        XCTAssertEqual(
            try queryRows(catalogURL, "SELECT COUNT(*) FROM image_collections", columns: 1)[0][0],
            "0")
        XCTAssertEqual(
            (try queryRows(
                catalogURL,
                "SELECT value FROM meta WHERE key = 'schemaVersion'",
                columns: 1))[0][0],
            "1")

        // The `.bak` retention: the OLD file's organization data lives there
        // (the single-file backup is the only organization recovery source).
        let bakURL = tempDirectory.appendingPathComponent("catalog.lcat.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path))
        let bakCategories = try queryRows(
            bakURL, "SELECT COUNT(*) FROM categories", columns: 1)
        XCTAssertEqual(bakCategories[0][0], "1", "the backup holds the old data")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("catalog.lcat.tmp").path),
            "the tmp is gone after the promotion")
    }

    /// The rollback leg: an injected failure AFTER the backup move leaves the
    /// ORIGINAL file byte-identical (the discipline: 晋升失败回退后原文件可用).
    func testDestructiveRollbackKeepsOriginalUntouched() async throws {
        let rootA = try makeSession(name: "session-a", rows: 4)
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        _ = try await projector.project(sessionRoot: rootA)
        await projector.close()

        let rebuilder = makeRebuilder()
        await rebuilder.setPromotionFailureInjection(.afterBackupMove)
        let original = try Data(contentsOf: catalogURL)

        do {
            _ = try await rebuilder.destructiveRebuild(recentRoots: [rootA])
            XCTFail("the injected promotion failure must surface")
        } catch let error as CatalogRebuilder.RebuildError {
            guard case .promotionFailed = error else {
                return XCTFail("expected .promotionFailed, got \(error)")
            }
        }

        XCTAssertEqual(
            try Data(contentsOf: catalogURL), original,
            "the original file came back byte-identical")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("catalog.lcat.bak").path),
            "the .bak rolled back into place")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("catalog.lcat.tmp").path),
            "the failed tmp was cleaned")
        // And the original still answers (可用).
        let rows = try queryRows(catalogURL, "SELECT COUNT(*) FROM catalog_images", columns: 1)
        XCTAssertEqual(rows[0][0], "4")
    }

    // MARK: - 损坏处置: the schemaFailed state

    /// v99 fixture → the reconcile path refuses with the TYPED error; the
    /// Sessions-mode full flow is untouched (zero impact); the destructive
    /// rebuild (which EXPECTS an unreadable old file) repairs the library.
    func testSchemaFailedRefusesThenDestructiveRepairsSessionsUntouched() async throws {
        let rootA = try makeSession(name: "session-a", rows: 4)
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        _ = try await projector.project(sessionRoot: rootA)
        await projector.close()

        // Corrupt the version stamp (the v99 shape — a FUTURE schema).
        try executeRaw(
            catalogURL,
            "UPDATE meta SET value = '99' WHERE key = 'schemaVersion'")

        // The openAndSync leg below runs the REAL scanner — the fixture's
        // lindex rows must have their files on disk (or sync deletes them
        // as removed; the isolation suite's dummy-file pattern).
        for i in 0..<4 {
            try Data("x".utf8).write(
                to: rootA.appendingPathComponent(String(format: "img%03d.arw", i)))
        }

        // The reconcile path refuses with the typed error (the schema gate).
        do {
            _ = try await makeRebuilder().reconcileRebuild()
            XCTFail("schemaFailed must refuse the reconcile")
        } catch let error as SessionIndexError {
            guard case .schemaFailed = error else {
                return XCTFail("expected .schemaFailed, got \(error)")
            }
        }

        // Sessions mode ZERO impact: the full open flow succeeds against the
        // broken catalog (the projector hook swallows the typed error; the
        // file is untouched at v99).
        let controller = SessionIndexController()
        let suiteName = defaultsSuiteName!
        let isolatedURL = catalogURL
        controller.catalogProjectorProvider = {
            CatalogProjector(databaseURL: isolatedURL, defaultsSuiteName: suiteName)
        }
        let flow = await controller.openAndSync(root: rootA)
        XCTAssertFalse(flow.failed, "the SESSIONS flow succeeds untouched")
        let stillBroken = try queryRows(
            catalogURL, "SELECT value FROM meta WHERE key = 'schemaVersion'",
            columns: 1)
        XCTAssertEqual(stillBroken[0][0], "99", "no guess-upgrade on the v99 file")

        // The destructive rebuild EXPECTS the unreadable old file: the old
        // registry cannot answer, the caller's roots carry the rebuild.
        let sessions = try await makeRebuilder()
            .destructiveRebuild(recentRoots: [rootA])
        XCTAssertEqual(sessions, 1)
        let version = try queryRows(
            catalogURL, "SELECT value FROM meta WHERE key = 'schemaVersion'",
            columns: 1)
        XCTAssertEqual(version[0][0], "1", "the fresh library is v1")
        let rows = try queryRows(catalogURL, "SELECT COUNT(*) FROM catalog_images", columns: 1)
        XCTAssertEqual(rows[0][0], "4", "metadata restored from the session face")
    }
}
