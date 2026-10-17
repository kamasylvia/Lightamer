import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FilmstripModelTests (Plan M2-3-1 T4, AC #6) — the filmstrip windowing
// contract at MODEL level (the KD-5 machine check; the List itself is the
// lazy container, the model is the request governor):
//
//   • a 10,000-row mount issues requests ONLY for the visible window ± the
//     prefetch constant — ZERO requests outside the window (count + set
//     assertions)
//   • a window jump requests only the NEW window's ids
//   • warm ids are never re-requested while still warm
//   • the scroll anchor follows the selected row
//   • an empty collection produces zero requests and an empty warm window
//   • AR-01 T4 (audit M3): the bookkeeping is ID-keyed — a mid-collection
//     insert (the stackAdjacencyFixup anchor+1 semantics) leaves the warm
//     window correct with NO stale ids and NO request inflation, and rows
//     vanishing from the collection prune out of the visible set
//   • BENCH| observation row (non-gate → SUMMARY): the 10k-row mount's
//     request total + model-level timing
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class FilmstripModelTests: XCTestCase {

    // MARK: - Fixture (a 10k-row real `.lalb` — the virtualization scale)

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var grid: LibraryGridModel!
    private var model: FilmstripModel!

    /// The mount size the virtualization test runs at.
    private let mountCount = 10_000
    /// The simulated visible window height (rows on screen).
    private let visibleWindow = 12

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("filmstrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Strip.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Strip")
        try await seed(mountCount)
        let queries = LibraryQueries(store: fileStore)
        grid = LibraryGridModel(queries: queries, pageSize: 1_000)
        try await grid.apply(sort: FilterSort(key: .filename, ascending: true))
        while !grid.isExhausted {
            _ = try await grid.loadNextPage()
        }
        model = FilmstripModel(grid: grid, bridge: nil)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        model = nil
        grid = nil
        fileStore = nil
        try await super.tearDown()
    }

    private func seed(_ count: Int) async throws {
        try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, file_stem, filename)
                VALUES (?, 2, ?, ?)
                """)
            for index in 0..<count {
                let stem = String(format: "B%06d", index)
                try insert.reset()
                try insert.bindText(1, "Media/\(stem).arw")
                try insert.bindText(2, stem)
                try insert.bindText(3, stem + ".arw")
                _ = try insert.step()
            }
            return true
        }
    }

    /// Simulate the List's mount signal: the visible window's rows appear
    /// (by IDENTITY — the AR-01 T4 id API; the cell hands its own row.id).
    private func mountWindow(startingAt start: Int) {
        for index in start..<(start + visibleWindow) {
            model.rowAppeared(id: grid.rows[index].id)
        }
    }

    /// Simulate the List's teardown signal for the same rows.
    private func unmountWindow(startingAt start: Int) {
        for index in start..<(start + visibleWindow) {
            model.rowDisappeared(id: grid.rows[index].id)
        }
    }

    // MARK: - AC #6: the 10k mount requests ONLY the visible window

    func testTenThousandRowMountIssuesOnlyWindowPlusPrefetchRequests() async throws {
        XCTAssertEqual(grid.rows.count, mountCount, "the full 10k collection is loaded")

        let start = Date()
        mountWindow(startingAt: 0)

        // Visible 0..11 ± prefetch 4 → ids of rows 0..15, EXACTLY.
        let expected = Set((0..<16).map { grid.rows[$0].id })
        XCTAssertEqual(model.requestedIDs, expected, "the warm set is window-clamped")
        XCTAssertEqual(model.requestCount, 16, "one request per window id")

        // The 10k mount means 9,984 rows OFF window — none of them requested.
        let offWindowIDs = Set(grid.rows[16...].map(\.id))
        XCTAssertTrue(
            model.requestedIDs.isDisjoint(with: offWindowIDs),
            "zero requests outside the window ± prefetch")

        // A far jump: unmount everything, mount around row 5000.
        unmountWindow(startingAt: 0)
        XCTAssertTrue(model.requestedIDs.isEmpty, "the disappear face clears the warm set")
        mountWindow(startingAt: 5000)
        let jumped = Set((4996..<5016).map { grid.rows[$0].id })
        XCTAssertEqual(model.requestedIDs, jumped, "the new window requested, nothing else")
        XCTAssertEqual(model.requestCount, 16 + 20, "only the new window's ids were issued")

        let elapsed = Date().timeIntervalSince(start)
        print(
            "BENCH| filmstrip 10k-row mount: \(model.requestCount) requests for two windows " +
            "(12 visible + 4 prefetch each), model-level simulation \(String(format: "%.1f", elapsed * 1000))ms — non-gate, lands in SUMMARY")
    }

    func testWarmIDsAreNeverReRequested() async throws {
        mountWindow(startingAt: 0)
        XCTAssertEqual(model.requestCount, 16)

        // Scroll by 5: rows 5..16 visible — the window slides to 1..20, so
        // exactly rows 16..20 are NEW; the warm 1..15 are not re-issued.
        // (The warm set keeps the previous leading edge until a FULL
        // disappear clears it — stale-warm, never stale-requested.)
        for index in 0..<5 { model.rowDisappeared(id: grid.rows[index].id) }
        for index in 12..<17 { model.rowAppeared(id: grid.rows[index].id) }
        XCTAssertEqual(model.requestCount, 16 + 5, "only the newly-warmed tail requested")
        XCTAssertTrue(
            Set((1..<21).map { grid.rows[$0].id }).isSubset(of: model.requestedIDs),
            "the slid window is fully warm")
    }

    // MARK: - AC #6: the scroll anchor follows the selection

    func testScrollAnchorFollowsTheSelectedRow() {
        let target = grid.rows[42].id
        model.select(target)
        XCTAssertEqual(grid.selectedIDs, [target], "selection routes through the grid")
        XCTAssertEqual(model.scrollAnchorID, target, "the anchor follows the selection")
    }

    func testExternalAnchorUpdatesWithoutTouchingSelection() {
        let selected = grid.rows[7].id
        model.select(selected)
        let other = grid.rows[9].id
        model.anchor(on: other)
        XCTAssertEqual(model.scrollAnchorID, other)
        XCTAssertEqual(grid.selectedIDs, [selected], "the external anchor never re-selects")
    }

    // MARK: - AC #6: the empty collection

    func testEmptyCollectionProducesZeroRequests() async throws {
        let emptyPackage = tempDirectory.appendingPathComponent("Empty.lalb")
        let emptyStore = ProjectFileStore(at: emptyPackage)
        _ = try await emptyStore.create(name: "Empty")
        defer { Task { try? await emptyStore.close() } }
        let emptyGrid = LibraryGridModel(queries: LibraryQueries(store: emptyStore))
        try await emptyGrid.apply(sort: FilterSort(key: .filename, ascending: true))
        XCTAssertTrue(emptyGrid.rows.isEmpty)

        let emptyModel = FilmstripModel(grid: emptyGrid, bridge: nil)
        emptyModel.rowAppeared(id: 0)
        XCTAssertEqual(emptyModel.requestCount, 0)
        XCTAssertTrue(emptyModel.warmWindow.isEmpty)
        emptyModel.select(1)
        XCTAssertNil(emptyModel.scrollAnchorID, "nothing to anchor on")
    }

    // MARK: - AC #6: the window clamps at the collection edges

    func testWarmWindowClampsAtCollectionEdges() {
        model.rowAppeared(id: grid.rows[0].id)
        // One visible row ± prefetch 4 → rows 0..4 (the head clamps at zero).
        XCTAssertEqual(model.warmWindow, 0..<5, "the head edge clamps at zero")

        let last = grid.rows.count - 1
        model.rowDisappeared(id: grid.rows[0].id)
        model.rowAppeared(id: grid.rows[last].id)
        XCTAssertEqual(
            model.warmWindow, (last - 4)..<grid.rows.count,
            "the tail edge clamps at the collection end")
    }

    // MARK: - AR-01 T4: the fixup mid-insert stale-window regressions

    /// The stackAdjacencyFixup anchor+1 semantics at model level: rows
    /// GROW by a mid-collection insert while the visible cells stay
    /// mounted (List identity = row.id — no onDisappear fires). The visible
    /// id set must produce the correct post-insert warm window, issue
    /// exactly ONE new request (the inserted row — no inflation from the
    /// shifted positions), and carry no stale id.
    func testMidCollectionInsertKeepsTheWindowCorrectWithoutStaleIDsOrInflation() async throws {
        mountWindow(startingAt: 0)
        XCTAssertEqual(model.requestCount, 16)
        let visibleIDsBefore = Set((0..<visibleWindow).map { grid.rows[$0].id })

        // The insert: a new image sorting BEFORE the whole seeded collection
        // (filenames A* vs B*), then a first-page reload + full re-walk —
        // grid.rows grows 10_000 → 10_001 with every old row shifted +1
        // (the insert-at-anchor shape; the strongest shift case).
        try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, file_stem, filename)
                VALUES ('Media/A000000.arw', 2, 'A000000', 'A000000.arw')
                """)
            _ = try insert.step()
            return true
        }
        try await grid.reloadFirstPage()
        while !grid.isExhausted {
            _ = try await grid.loadNextPage()
        }
        XCTAssertEqual(grid.rows.count, mountCount + 1, "the insert landed")
        XCTAssertEqual(grid.rows[0].fileStem, "A000000", "the new row sorts first")

        // The signal-less face: NO appear/disappear fired (identity-stable
        // cells stay mounted) — yet the window computation is already
        // correct, because ids cannot go stale against an insert (the
        // index era inflated here with stale+fresh positions).
        XCTAssertEqual(
            model.warmWindow, 0..<17,
            "the post-insert window is correct before any signal fires")

        // The next scroll signal re-books the still-mounted ids and the
        // refresh promotes exactly the inserted row.
        for index in 1..<(1 + visibleWindow) {
            model.rowAppeared(id: grid.rows[index].id)
        }
        XCTAssertEqual(
            model.warmWindow, 0..<17,
            "the post-insert window is exact against the shifted positions")
        // No inflation: exactly the inserted row was NEW to the warm set —
        // the 16 shifted-but-already-warm ids were not re-issued.
        XCTAssertEqual(
            model.requestCount, 17,
            "one request for the inserted row, zero for the shifted ones")
        // No stale id: everything requested still resolves in the rows.
        let liveIDs = Set(grid.rows.map(\.id))
        XCTAssertTrue(
            model.requestedIDs.isSubset(of: liveIDs),
            "no stale id survives in the warm set")
        XCTAssertTrue(
            visibleIDsBefore.isSubset(of: model.requestedIDs),
            "the pre-insert visible ids stayed warm through the shift")
    }

    /// The delete face: visible rows VANISH from the collection (a foreign
    /// delete + reload — the same observable shape as a fixup removal).
    /// The vanished ids must prune out of the visible set (no window math
    /// against dead ids) and the survivors re-book without inflation.
    func testRowsVanishingFromTheCollectionPruneTheVisibleSet() async throws {
        mountWindow(startingAt: 0)
        XCTAssertEqual(model.requestCount, 16)
        let vanishing = Set((0..<4).map { grid.rows[$0].id })
        let vanishingStems = vanishing.compactMap { id in
            grid.rows.first { $0.id == id }?.fileStem
        }
        XCTAssertEqual(vanishingStems.count, 4)

        // Delete the first four visible rows, reload + re-walk: the former
        // rows 4.. sit at 0.. now, the collection is 9_996 rows.
        try await fileStore.withWriteBatch { handle -> Bool in
            let statement = try handle.prepare("DELETE FROM images WHERE file_stem = ?")
            for stem in vanishingStems {
                try statement.reset()
                try statement.bindText(1, stem)
                _ = try statement.step()
            }
            return true
        }
        try await grid.reloadFirstPage()
        while !grid.isExhausted {
            _ = try await grid.loadNextPage()
        }
        XCTAssertEqual(grid.rows.count, mountCount - 4, "the delete landed")
        let liveIDs = Set(grid.rows.map(\.id))
        for id in vanishing {
            XCTAssertFalse(liveIDs.contains(id), "the deleted id left the collection")
        }

        // The still-mounted survivors (the old rows 4..11, now 0..7)
        // re-book; the vanished ids prune out of the visible set.
        for index in 0..<8 {
            model.rowAppeared(id: grid.rows[index].id)
        }

        // The window: visible 0..7 ± prefetch 4 → 0..<12 — computed from
        // LIVE ids only (the dead ids contributed nothing).
        XCTAssertEqual(
            model.warmWindow, 0..<12,
            "the post-delete window is computed from the survivors")
        // Zero inflation: the post-delete window (old rows 4..15 at the new
        // 0..11) was ENTIRELY warm from the pre-delete mount — the refresh
        // issued nothing new.
        XCTAssertEqual(
            model.requestCount, 16,
            "zero inflation: the post-delete window was already warm")
        // The warm-set cancel contract is unchanged (full disappear clears;
        // the vanish face does not rewrite history).
        XCTAssertTrue(
            vanishing.isSubset(of: model.requestedIDs),
            "the vanish face does not rewrite history (warm-set cancel stays the full-disappear contract)")
    }
}
