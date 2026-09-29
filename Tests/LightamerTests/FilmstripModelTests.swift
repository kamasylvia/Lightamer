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

    /// Simulate the List's mount signal: the visible window's rows appear.
    private func mountWindow(startingAt start: Int) {
        for index in start..<(start + visibleWindow) {
            model.rowAppeared(index)
        }
    }

    /// Simulate the List's teardown signal for the same rows.
    private func unmountWindow(startingAt start: Int) {
        for index in start..<(start + visibleWindow) {
            model.rowDisappeared(index)
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
        for index in 0..<5 { model.rowDisappeared(index) }
        for index in 12..<17 { model.rowAppeared(index) }
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
        emptyModel.rowAppeared(0)
        XCTAssertEqual(emptyModel.requestCount, 0)
        XCTAssertTrue(emptyModel.warmWindow.isEmpty)
        emptyModel.select(1)
        XCTAssertNil(emptyModel.scrollAnchorID, "nothing to anchor on")
    }

    // MARK: - AC #6: the window clamps at the collection edges

    func testWarmWindowClampsAtCollectionEdges() {
        model.rowAppeared(0)
        // One visible row ± prefetch 4 → rows 0..4 (the head clamps at zero).
        XCTAssertEqual(model.warmWindow, 0..<5, "the head edge clamps at zero")

        let last = grid.rows.count - 1
        model.rowDisappeared(0)
        model.rowAppeared(last)
        XCTAssertEqual(
            model.warmWindow, (last - 4)..<grid.rows.count,
            "the tail edge clamps at the collection end")
    }
}
