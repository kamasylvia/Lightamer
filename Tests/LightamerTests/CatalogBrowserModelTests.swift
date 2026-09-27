import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// CatalogBrowserModelTests (Plan 16-2 T3) — the cross-session grid's DATA
// face over the 16-1 keyset store:
//
//   • SCROLL LOADING = the keyset two-segment consumption: the model's full
//     drain (loadMore until endReached) is asserted EQUAL, identity by
//     identity and in order, to the one-shot store reference (main segment
//     LIMIT N) — for EVERY catalog sort shape (3 keys × 2 directions; the
//     6-shape matrix, L020 content level).
//   • NULL TAIL SEAM: rating/date shapes carry NULL tiers — the drain must
//     equal main ∪ tail with an EMPTY intersection (无重无漏).
//   • CHIPS: the model's drained row set == the store's direct query with
//     the same groups (the translation rides FilterDomain.catalog inside
//     the store — the model adds no SQL, seam a).
//   • QUICK FILTER: the catalog-domain filename startsWith is case-
//     sensitive (RQ-16-16①) — the UI hint rides the bar.
//   • SORT SWITCH: changing the key resets the cursors (no stale rows from
//     the previous shape survive).
//
// Fixtures are RAW catalog databases (the CatalogFilterSQLTests direct-
// handle style; L009: never external-volume).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CatalogBrowserModelTests: XCTestCase {

    private var tempDirectory: URL!
    private var catalogURL: URL!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-browser-\(UUID().uuidString)", isDirectory: true)
        catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
        defaultsSuiteName = "catalog-browser-tests-\(UUID().uuidString)"
        CatalogPreferences.setCatalogsEnabled(true, defaultsSuiteName: defaultsSuiteName)
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixture (10 sessions × 40 dirs; the harness NULL profile)

    private func seedCatalog(n: Int) throws {
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: catalogURL.path)
        defer { handle.close() }
        try CatalogIndexSchema.apply(to: handle)
        let insert = try handle.prepare("""
            INSERT INTO catalog_images (
              session_id, rel_path, dir, filename, file_size, file_mtime,
              imageID, sidecar_present, sidecar_mtime, has_edits,
              params_hash, layer_count, layer_summary, orientation,
              width, height, capture_date, rating, color_label, keywords,
              orphan_sidecar, flag, note, camera_make, camera_model,
              lens_model, iso, focal_length, aperture, exposure
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        try handle.exec("BEGIN IMMEDIATE")
        for i in 0..<n {
            let rel = String(format: "dir%04d/img%06d.arw", i % 40, i)
            try insert.bindText(1, "sess-\(i % 10)")
            try insert.bindText(2, rel)
            try insert.bindText(3, "dir\(String(format: "%04d", i % 40))")
            try insert.bindText(4, "img\(String(format: "%06d", i)).arw")
            try insert.bindInt(5, 4096)
            try insert.bindDouble(6, 1_700_000_000 + Double(i))
            try insert.bindText(7, "id-\(i)")
            try insert.bindInt(8, 0)
            try insert.bindDouble(9, 0)
            try insert.bindInt(10, i % 3 == 0 ? 1 : 0)
            try insert.bindText(11, nil)
            try insert.bindInt(12, nil)
            try insert.bindText(13, nil)
            try insert.bindInt(14, 1)
            try insert.bindInt(15, 100)
            try insert.bindInt(16, 100)
            if i % 10 == 0 {
                try insert.bindDouble(17, nil)
            } else {
                try insert.bindDouble(17, 1_700_000_000 + Double(i % 86_400))
            }
            if i % 5 == 0 { try insert.bindInt(18, nil) }
            else { try insert.bindInt(18, Int64(i % 6)) }
            try insert.bindInt(19, nil)
            try insert.bindText(20, nil)
            try insert.bindInt(21, 0)
            try insert.bindInt(22, nil)
            try insert.bindText(23, nil)
            try insert.bindText(24, "Make")
            try insert.bindText(25, i % 5 == 0 ? nil : "Model\(i % 7)")
            try insert.bindText(26, nil)
            try insert.bindInt(27, nil)
            try insert.bindDouble(28, nil)
            try insert.bindDouble(29, nil)
            try insert.bindDouble(30, nil)
            _ = try insert.step()
            try insert.reset()
            if i % 2000 == 1999 {
                try handle.exec("COMMIT")
                try handle.exec("BEGIN IMMEDIATE")
            }
        }
        try handle.exec("COMMIT")
    }

    /// A small case-sensitivity fixture (Quick Filter startsWith).
    private func seedCaseFixture() throws {
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: catalogURL.path)
        defer { handle.close() }
        try CatalogIndexSchema.apply(to: handle)
        for rel in ["Apple.arw", "apple2.arw", "banana.arw"] {
            let insert = try handle.prepare(
                "INSERT INTO catalog_images (session_id, rel_path, filename, "
                    + "orphan_sidecar) VALUES ('s', ?, ?, 0)")
            try insert.bindText(1, rel)
            try insert.bindText(2, rel)
            _ = try insert.step()
        }
    }

    private func makeModel() -> CatalogBrowserModel {
        let model = CatalogBrowserModel()
        model.configure(store: CatalogIndexStore(databaseURL: catalogURL))
        return model
    }

    /// Drive the model's scroll loading to the end; return the identities.
    private func drain(_ model: CatalogBrowserModel) async -> [String] {
        await model.reload()
        var guardCounter = 0
        while !model.endReached, guardCounter < 500 {
            await model.loadMore()
            guardCounter += 1
        }
        XCTAssertTrue(model.endReached, "the drain must reach the end")
        return model.rows.map(\.id)
    }

    // MARK: - The 6-shape scroll matrix (3 keys × 2 directions)

    func testScrollDrainMatchesOneShotReferenceAcrossShapes() async throws {
        try seedCatalog(n: 10_000)
        let store = CatalogIndexStore(databaseURL: catalogURL)
        let keys: [FilterSortKey] = [.captureDate, .rating, .filename]
        for key in keys {
            for ascending in [true, false] {
                let sort = FilterSort(key: key, ascending: ascending)
                let model = makeModel()
                await model.apply(sort: sort)
                let drained = await drain(model)
                // The one-shot reference: a single big-LIMIT keyset query
                // (the main segment's ORDER BY already interleaves the NULL
                // tier at its end — the two-segment drain must reproduce
                // EXACTLY this sequence).
                let reference = try await store.queryPage(
                    groups: [], sort: sort, limit: 10_000)
                XCTAssertEqual(
                    drained,
                    reference.map { "\($0.sessionID)/\($0.relPath)" },
                    "\(key.rawValue) asc=\(ascending): the scroll drain must "
                        + "reproduce the one-shot keyset order exactly")
                XCTAssertEqual(drained.count, 10_000)
                XCTAssertEqual(
                    Set(drained).count, drained.count,
                    "no duplicate identities across pages")
            }
        }
    }

    // MARK: - NULL tail seam (main ∪ tail, empty intersection)

    func testNullTailSeamRatingDescNoOverlapNoGap() async throws {
        try seedCatalog(n: 10_000)
        let store = CatalogIndexStore(databaseURL: catalogURL)
        let sort = FilterSort(key: .rating, ascending: false)

        let model = makeModel()
        await model.apply(sort: sort)
        let drained = try await drain(model)

        // The one-shot reference (the two-segment drain = the same total
        // order; 无重无漏 shows up as exact equality with no duplicates).
        let reference = try await store.queryPage(groups: [], sort: sort, limit: 10_000)
        XCTAssertEqual(
            drained, reference.map { "\($0.sessionID)/\($0.relPath)" },
            "the drain equals the full keyset order (main then NULL tail)")
        XCTAssertEqual(drained.count, 10_000)
        XCTAssertEqual(Set(drained).count, drained.count, "无重: no duplicates")
        // The fixture's NULL-rating tier actually exercised the tail (the
        // last 2000 rows of the order carry NULL ratings).
        let tailRows = try await store.queryNullTail(groups: [], sort: sort, limit: 10_000)
        XCTAssertFalse(tailRows.isEmpty, "the 20%-NULL fixture must fill the tail")
        let drainedTail = Array(drained[(drained.count - tailRows.count)...])
        XCTAssertEqual(
            Set(drainedTail), Set(tailRows.map { "\($0.sessionID)/\($0.relPath)" }),
            "the drain's tail segment is exactly the NULL tier")
    }

    // MARK: - Chips: the model rides the store's translation (seam a)

    func testChipCombinationRowSetEqualsStoreDirectQuery() async throws {
        try seedCatalog(n: 10_000)
        let store = CatalogIndexStore(databaseURL: catalogURL)
        let chips: [FilterPredicateGroup.Rule] = [
            .init(field: .rating, op: .gte, value: .int(4)),
            .init(field: .cameraModel, op: .contains, value: .text("Model3")),
        ]
        let model = makeModel()
        model.setFilterChips(chips)
        let drained = await drain(model)

        let reference = try await store.queryPage(
            groups: [FilterPredicateGroup(match: .all, rules: chips)],
            sort: CatalogBrowserModel.defaultSort, limit: 10_000)
        XCTAssertEqual(
            drained,
            reference.map { "\($0.sessionID)/\($0.relPath)" },
            "the chips combination must match the store's direct query")
    }

    // MARK: - Quick Filter: catalog startsWith is case-sensitive

    func testQuickFilterStartsWithIsCaseSensitive() async throws {
        try seedCaseFixture()
        let model = makeModel()
        model.setQuickFilterText("Apple")
        let drained = await drain(model)
        XCTAssertEqual(
            drained, ["s/Apple.arw"],
            "case-sensitive startsWith: 'Apple' hits Apple.arw only "
                + "(apple2.arw and banana.arw are out)")

        // The lowercase query hits the lowercase filename.
        let lower = makeModel()
        lower.setQuickFilterText("apple")
        let drainedLower = await drain(lower)
        XCTAssertEqual(drainedLower, ["s/apple2.arw"])
    }

    // MARK: - Sort switch resets the cursors

    func testSortSwitchResetsCursorsNoStaleRows() async throws {
        try seedCatalog(n: 10_000)
        let model = makeModel()
        await model.reload() // date DESC default — the first page
        XCTAssertEqual(model.rows.count, CatalogBrowserModel.pageSize)
        await model.loadMore()
        XCTAssertEqual(model.rows.count, 2 * CatalogBrowserModel.pageSize)

        // Switch the sort key: the window resets to the NEW shape's first
        // page — no stale rows from the previous shape.
        model.setSort(FilterSort(key: .rating, ascending: true))
        await model.reload()
        XCTAssertEqual(model.rows.count, CatalogBrowserModel.pageSize)
        let store = CatalogIndexStore(databaseURL: catalogURL)
        let reference = try await store.queryPage(
            groups: [], sort: FilterSort(key: .rating, ascending: true),
            limit: CatalogBrowserModel.pageSize)
        XCTAssertEqual(
            model.rows.map(\.id), reference.map { "\($0.sessionID)/\($0.relPath)" },
            "the post-switch window equals the new shape's first page")
    }

    // MARK: - End reached stops loading (idempotent tail)

    func testLoadMoreAfterEndReachedIsNoOp() async throws {
        try seedCatalog(n: 150)
        let model = makeModel()
        let drained = await drain(model)
        XCTAssertEqual(drained.count, 150)
        let before = model.rows
        await model.loadMore()
        XCTAssertEqual(model.rows, before, "the end is sticky")
        XCTAssertTrue(model.endReached)
    }

    // MARK: - Scroll pagination page order (the visible-window face)

    func testPaginationPageOrderDateDesc() async throws {
        try seedCatalog(n: 300)
        let store = CatalogIndexStore(databaseURL: catalogURL)
        let model = makeModel()
        await model.reload()
        XCTAssertEqual(model.rows.count, 60)
        let page1 = model.rows
        await model.loadMore()
        XCTAssertEqual(model.rows.count, 120)
        // Page 2 continues EXACTLY where page 1 ended (no gap, no overlap).
        let reference = try await store.queryPage(
            groups: [], sort: CatalogBrowserModel.defaultSort, limit: 120)
        XCTAssertEqual(
            model.rows.map(\.id), reference.map { "\($0.sessionID)/\($0.relPath)" })
        XCTAssertEqual(
            page1.map(\.id),
            Array(reference.map { "\($0.sessionID)/\($0.relPath)" }[0..<60]))
    }

    // MARK: - T6: the edit loop (lindex change → project → grid refresh)

    /// The edit loop's DATA chain at model level: the session's lindex
    /// changes (an edit wrote the sidecar + bumped the epoch — simulated
    /// with a direct row update, the projector's input contract), the
    /// projector catches the catalog up, and `refreshAfterProjection`
    /// re-derives the loaded window from the committed state.
    func testEditProjectionRefreshChainUpdatesRows() async throws {
        // A one-session catalog with one rated row (raw lindex fixture).
        let sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        let lindexURL = SessionIndexSchema.databaseURL(forSessionRoot: sessionRoot)
        try FileManager.default.createDirectory(
            at: lindexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: lindexURL.path)
        try SessionIndexSchema.apply(to: handle)
        let stamp = try handle.prepare(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('scan_epoch', '1')")
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
            ) VALUES ('IMG_0001.ARW', NULL, 'IMG_0001.ARW', ?, ?, 1,
                      '11111111-2222-3333-4444-555555555555', 0, 0, 0,
                      NULL, NULL, NULL, 1, 100, 100, 1700000100, 2, NULL,
                      NULL, 0, 0, NULL, NULL, 'Sony', NULL, NULL, NULL,
                      NULL, NULL, NULL)
            """)
        try insert.bindInt(1, 4096)
        try insert.bindDouble(2, 1_700_000_000)
        _ = try insert.step()
        handle.close()

        // Project (rating 2 lands in the catalog) and load the model.
        let projector = CatalogProjector(
            databaseURL: catalogURL,
            defaultsSuiteName: defaultsSuiteName)
        _ = try await projector.project(sessionRoot: sessionRoot)

        let model = makeModel()
        await model.reload()
        XCTAssertEqual(model.rows.first?.rating, 2)

        // THE EDIT: the rating changes + the epoch bumps (the MetadataService
        // leg-2 output, simulated at the input contract).
        let mutation = try SQLiteHandle(path: lindexURL.path)
        _ = try mutation.exec(
            "UPDATE images SET rating = 5, scan_epoch = 2 WHERE path = 'IMG_0001.ARW'")
        _ = try mutation.exec(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('scan_epoch', '2')")
        mutation.close()
        _ = try await projector.project(sessionRoot: sessionRoot)

        // The RETURN-TO-GRID face: the loaded window re-derives (水位追平).
        await model.refreshAfterProjection()
        XCTAssertEqual(model.rows.first?.rating, 5, "the grid caught up")
    }
}
