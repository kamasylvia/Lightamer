import Foundation
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryGridModelTests (Plan M2-3-1 T3, AC #4) — the collection-state model
// over a REAL `.lalb` package (the M2-2-3 LibraryQueriesTests fixture
// pattern):
//
//   • keyset pagination walks every row EXACTLY once (no gap, no overlap)
//   • the NULL tier is its own last segment (rows with a NULL sort key land
//     after every keyed row, exactly once)
//   • a filter/sort change resets the cursor and refetches the first page
//   • the selection / current-image state machine (single / toggle /
//     set-clamped / open-selects / clear)
//   • the five-key whitelist is passed STRAIGHT THROUGH to the query face's
//     guard — `scanEpoch` surfaces the typed violation (never re-implemented)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryGridModelTests: XCTestCase {

    // MARK: - Fixture (12 rows: 5/4/3 day split, four unrated rows, one
    // NULL-date row — the same shape as the M2-2-3 suite)

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var queries: LibraryQueries!
    private var model: LibraryGridModel!

    private struct SeedRow {
        var path: String
        var iso: Int64?
        var date: Double?
        var rating: Int64?
    }

    private static let twelveRows: [SeedRow] = [
        .init(path: "Media/00.arw", iso: 800, date: 1_717_224_000, rating: 5),
        .init(path: "Media/01.arw", iso: 800, date: 1_717_224_000, rating: 4),
        .init(path: "Media/02.arw", iso: 1600, date: 1_717_227_600, rating: 4),
        .init(path: "Media/03.arw", iso: 8000, date: 1_717_231_200, rating: 0),
        .init(path: "Media/04.arw", iso: 100, date: 1_717_310_400, rating: 5),
        .init(path: "Media/05.arw", iso: 200, date: 1_717_314_000, rating: nil),
        .init(path: "Media/06.arw", iso: 400, date: 1_717_317_600, rating: nil),
        .init(path: "Media/07.nef", iso: 800, date: 1_717_321_200, rating: 3),
        .init(path: "Media/08.raf", iso: 1600, date: 1_717_396_800, rating: 3),
        .init(path: "Media/09.raf", iso: 3200, date: 1_717_400_400, rating: nil),
        .init(path: "Media/10.arw", iso: 6400, date: nil, rating: nil),
        .init(path: "Media/11.arw", iso: 800, date: 1_717_224_000, rating: 4),
    ]

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-grid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Grid.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Grid")
        queries = LibraryQueries(store: fileStore)
        try await seed(Self.twelveRows)
        model = LibraryGridModel(queries: queries, pageSize: 5)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        model = nil
        queries = nil
        fileStore = nil
        try await super.tearDown()
    }

    private func seed(_ rows: [SeedRow]) async throws {
        try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, capture_date,
                    rating, iso, file_stem, filename)
                VALUES (?, 2, ?, ?, ?, ?, ?)
                """)
            for (index, row) in rows.enumerated() {
                let stem = String(format: "DSC%05d", index)
                try insert.reset()
                try insert.bindText(1, row.path)
                try insert.bindDouble(2, row.date)
                try insert.bindInt(3, row.rating)
                try insert.bindInt(4, row.iso)
                try insert.bindText(5, stem)
                try insert.bindText(6, stem + ".arw")
                _ = try insert.step()
            }
            return true
        }
    }

    // MARK: - AC #4: keyset pagination — no gap, no overlap, exhaustion

    func testKeysetWalkCoversEveryRowExactlyOnce() async throws {
        try await model.apply(sort: FilterSort(key: .filename, ascending: true))
        var seen: [Int64] = []
        while !model.isExhausted {
            _ = try await model.loadNextPage()
            seen = model.rows.map(\.id)
        }
        XCTAssertEqual(seen.count, 12, "every seeded row walks exactly once")
        XCTAssertEqual(Set(seen).count, 12, "no duplicates across pages")
        // filename ASC: seeded stems are insert-ordered, so the walk is the
        // rowid order (the pagination is order-faithful).
        XCTAssertEqual(seen, Array(seen).sorted())
    }

    func testNullTailSegmentWalksLastAndExactlyOnce() async throws {
        // captureDate ASC: the one NULL-date row must come AFTER every
        // keyed row, as the tail segment's only member.
        try await model.apply(sort: FilterSort(key: .captureDate, ascending: true))
        var walk: [LibraryImageRow] = []
        while !model.isExhausted {
            _ = try await model.loadNextPage()
            walk = model.rows
        }
        XCTAssertEqual(walk.count, 12)
        XCTAssertEqual(Set(walk.map(\.id)).count, 12, "the NULL row appears once")
        let nullDateRows = walk.filter { $0.captureDate == nil }
        XCTAssertEqual(nullDateRows.count, 1)
        XCTAssertEqual(walk.last?.id, nullDateRows.first?.id, "the NULL tier is last")
        // Every keyed row precedes it, in key order.
        let keyed = walk.dropLast().map { $0.captureDate ?? -1 }
        XCTAssertEqual(keyed, keyed.sorted(), "the keyed segment walks in capture-date order")
    }

    // MARK: - AC #4: filter / sort change resets the cursor + refetches

    func testFilterChangeResetsCursorAndRefetches() async throws {
        try await model.apply(sort: FilterSort(key: .filename, ascending: true))
        XCTAssertEqual(model.rows.count, 5, "apply fetches the first page")

        // rating >= 3 → seven rows survive (5,4,4,5,3,3,4).
        let filtered = ExifSearchFilter(
            group: FilterPredicateGroup(
                match: .all,
                rules: [
                    FilterPredicateGroup.Rule(
                        field: .rating, op: .gte, value: .int(3))
                ]))
        try await model.apply(filter: filtered)

        XCTAssertEqual(model.rows.count, 5, "the first page REFETCHED after reset")
        XCTAssertFalse(model.isExhausted)
        var walk: [Int64] = []
        while !model.isExhausted {
            _ = try await model.loadNextPage()
            walk = model.rows.map(\.id)
        }
        XCTAssertEqual(walk.count, 7, "no pre-filter rows leak into the new walk")
        XCTAssertEqual(Set(walk).count, 7, "no duplicates after the reset")
        // Every surviving row satisfies the new filter.
        for row in model.rows {
            XCTAssertGreaterThanOrEqual(row.rating ?? -1, 3)
        }
    }

    func testSortChangeResetsCursorAndRefetchesInNewOrder() async throws {
        try await model.apply(sort: FilterSort(key: .filename, ascending: true))
        try await model.apply(sort: FilterSort(key: .captureDate, ascending: false))

        // The newest row leads the DESC walk (09 @ 2024-06-03 13:40 UTC).
        XCTAssertEqual(model.rows.first?.filename, "DSC00009.arw")
        var walk: [Int64] = []
        while !model.isExhausted {
            _ = try await model.loadNextPage()
            walk = model.rows.map(\.id)
        }
        XCTAssertEqual(Set(walk).count, 12, "the reset walk still covers everything")
    }

    // MARK: - AC #4: the five-key whitelist passes straight through

    func testScanEpochSortSurfacesTheQueryFaceViolation() async throws {
        // The model does NOT duplicate the whitelist — the illegal key rides
        // to LibraryQueries.validateSortKey and comes back typed.
        do {
            try await model.apply(sort: FilterSort(key: .scanEpoch, ascending: true))
            XCTFail("scanEpoch must throw the typed constraint violation")
        } catch {
            guard case LibraryError.constraintViolation(let detail) = error else {
                XCTFail("unexpected error type: \(error)")
                return
            }
            XCTAssertTrue(
                detail.contains("outside the library"),
                "the violation names the KD-3 whitelist: \(detail)")
        }
        // The collection is left reset-but-empty (the documented face).
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(model.isExhausted)
    }

    // MARK: - AC #4: the selection / current-image state machine

    private func loadAll() async throws {
        while !model.isExhausted {
            _ = try await model.loadNextPage()
        }
    }

    func testSelectSingleReplacesTheSelection() async throws {
        try await loadAll()
        model.selectSingle(3)
        XCTAssertEqual(model.selectedIDs, [3])
        model.selectSingle(5)
        XCTAssertEqual(model.selectedIDs, [5])
    }

    func testToggleSelectionAddsAndRemoves() async throws {
        try await loadAll()
        model.toggleSelection(3)
        model.toggleSelection(5)
        XCTAssertEqual(model.selectedIDs, [3, 5])
        model.toggleSelection(3)
        XCTAssertEqual(model.selectedIDs, [5])
    }

    func testSelectionIgnoresUnloadedRowIDs() async throws {
        try await loadAll()
        model.selectSingle(9_999)
        XCTAssertTrue(model.selectedIDs.isEmpty, "selection is a loaded-row gesture")
        model.setSelection([1, 2, 9_999])
        XCTAssertEqual(model.selectedIDs, [1, 2], "setSelection clamps to loaded rows")
    }

    func testOpenCurrentSetsAndSelectsThenClears() async throws {
        try await loadAll()
        model.openCurrent(4)
        XCTAssertEqual(model.currentImageID, 4)
        XCTAssertEqual(model.selectedIDs, [4], "opening focuses the row")
        model.clearCurrentImage()
        XCTAssertNil(model.currentImageID)
    }

    func testSelectionSurvivesRefetch() async throws {
        try await loadAll()
        model.selectSingle(3)
        try await model.apply(sort: FilterSort(key: .rating, ascending: true))
        XCTAssertEqual(
            model.selectedIDs, [3],
            "selection is user intent — a refetch never clears it")
    }

    func testClearSelection() async throws {
        try await loadAll()
        model.toggleSelection(1)
        model.toggleSelection(2)
        model.clearSelection()
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    // MARK: - Plan M2-3-2 T1 (KD-1): the scroll-signal → pagination glue

    /// The LibraryGridPager the WorkspaceHostView mounts behind the grid.
    private func makePager(arming: Int = 12) -> LibraryGridPager {
        LibraryGridPager(grid: model, tailArmingDistance: arming)
    }

    func testScrollSignalIssuesBoundedLoadNextPageCalls() async throws {
        try await model.apply(sort: FilterSort(key: .filename, ascending: true))
        XCTAssertEqual(model.rows.count, 5, "the first page is preloaded")
        let pager = makePager(arming: 12)

        // Every cell of a 12-row collection sits inside a 12-row arming
        // window; each signal issues exactly ONE page attempt (the keyset
        // walk), and the isExhausted floor ends the sequence.
        await pager.cellAppeared(at: 4)
        XCTAssertEqual(pager.loadCallCount, 1, "the tail signal issued ONE call")
        XCTAssertEqual(model.rows.count, 10, "the next keyset page landed")

        await pager.cellAppeared(at: 9)
        XCTAssertEqual(pager.loadCallCount, 2)
        XCTAssertEqual(model.rows.count, 12, "the walk completed")
        XCTAssertTrue(model.isExhausted)

        // Further signals (any index) are floored by isExhausted — zero
        // further loadNextPage invocations.
        await pager.cellAppeared(at: 0)
        await pager.cellAppeared(at: 11)
        XCTAssertEqual(
            pager.loadCallCount, 2,
            "isExhausted floors the pager: no further calls after the walk")
    }

    func testSignalAwayFromTailIssuesNoCall() async throws {
        try await model.apply(sort: FilterSort(key: .filename, ascending: true))
        let pager = makePager(arming: 2)

        // With 5 loaded rows and a 2-row arming window, indices 0..2 are
        // away from the tail — the signal issues nothing.
        await pager.cellAppeared(at: 0)
        await pager.cellAppeared(at: 2)
        XCTAssertEqual(pager.loadCallCount, 0)
        XCTAssertEqual(model.rows.count, 5, "no page was fetched")

        // A signal INSIDE the window (index 3 = the second-to-last row)
        // issues exactly one call.
        await pager.cellAppeared(at: 3)
        XCTAssertEqual(pager.loadCallCount, 1)
        XCTAssertEqual(model.rows.count, 10, "the next keyset page landed")
    }

    func testExhaustedPagerIgnoresEverySignal() async throws {
        try await loadAll()
        XCTAssertTrue(model.isExhausted)
        let pager = makePager(arming: 12)
        for index in 0..<12 {
            await pager.cellAppeared(at: index)
        }
        XCTAssertEqual(
            pager.loadCallCount, 0,
            "a fully-walked collection issues zero pagination calls")
    }

    // MARK: - Plan M2-3-2 T1 (KD-1/D2): the double-click → EditorPhaseState
    // wiring (the composition WorkspaceHostView performs on a double-click)

    func testDoubleClickWiresEditorPhaseState() async throws {
        try await loadAll()
        let workspace = WorkspaceModel()
        XCTAssertEqual(workspace.phase, .library)

        let id = model.rows[3].id
        // The host's onOpen composition: the grid's current-image state
        // machine + the WorkspaceModel routing transition.
        model.openCurrent(id)
        workspace.openEditor(imageID: id)

        XCTAssertEqual(workspace.phase, .editor)
        XCTAssertEqual(workspace.editorPhase.currentImageID, id)
        XCTAssertEqual(workspace.editorPhase.filmstripScrollAnchor, id)
        XCTAssertEqual(model.currentImageID, id)
        XCTAssertEqual(model.selectedIDs, [id], "opening focuses the row")

        // The lossless round trip (D2): back to the library, the editor
        // face survives; the grid's collection state was never touched.
        workspace.closeEditor()
        XCTAssertEqual(workspace.phase, .library)
        XCTAssertEqual(workspace.editorPhase.currentImageID, id)
        XCTAssertEqual(model.rows.count, 12)
    }

    // MARK: - Plan M2-3-2 T5: the thumbnail first-screen observation
    // (BENCH|, MANUAL-ONLY — the LibraryBenchmarkHarness seam discipline)

    /// The M2-2-3 perf.md §A.4 挂账 measurement: a REAL `.lalb` whose rows
    /// point at REAL camera files (the repo's input/RAW corpus hardlinked
    /// N ways — zero copy cost), the P2 bridge producing the first screen
    /// COLD (empty thumbs dir, empty LRU). Prints `BENCH|` lines:
    /// total + per-image production cost, tier A (embedded preview).
    ///
    ///   LA_THUMB_BENCH=1 Scripts/test-direct.sh 'LibraryGridModelTests'
    ///   (override the screen size: LA_THUMB_BENCH_N, default 24; the
    ///   Release column rides the CatalogBenchmarkHarness direct-launch
    ///   recipe)
    @MainActor
    func testThumbnailFirstScreenProductionObservation() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LA_THUMB_BENCH"] == "1",
            "manual-only benchmark (LA_THUMB_BENCH=1)")

        // The corpus: the repo's input/RAW real files.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let rawDir = repoRoot.appendingPathComponent("input/RAW", isDirectory: true)
        let corpusFiles = ["DSC00012.ARW", "DSC09991.ARW", "DSC00012.jpg"]
            .map { rawDir.appendingPathComponent($0) }
        for file in corpusFiles {
            try XCTSkipUnless(
                FileManager.default.fileExists(atPath: file.path),
                "the input/RAW corpus is absent on this machine")
        }

        let screen = Int(ProcessInfo.processInfo.environment["LA_THUMB_BENCH_N"] ?? "24")
            ?? 24

        // A FRESH package + Media/ of symlinks (cross-volume: the repo
        // sits on an external volume — hardlinks are impossible; symlinks
        // cost nothing and ImageIO follows them).
        let benchRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("la-thumb-bench-\(UUID().uuidString)", isDirectory: true)
        let mediaDir = benchRoot.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(
            at: mediaDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: benchRoot) }

        let packageURL = benchRoot.appendingPathComponent("Bench.lalb")
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "Bench")
        let benchQueries = LibraryQueries(store: store)
        try await store.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, has_edits,
                    file_stem, filename)
                VALUES (?, 0, 0, ?, ?)
                """)
            for index in 0..<screen {
                let source = corpusFiles[index % corpusFiles.count]
                let name = "Bench\(String(format: "%03d", index))_"
                    + source.lastPathComponent
                let destination = mediaDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.createSymbolicLink(
                    at: destination, withDestinationURL: source)
                try insert.reset()
                try insert.bindText(1, "Media/" + name)
                try insert.bindText(2, String(format: "BENCH%03d", index))
                try insert.bindText(3, name)
                _ = try insert.step()
            }
            return true
        }

        // The P2 composition exactly as the host wires it (tier A —
        // has_edits = 0 everywhere; the thumbs dir starts EMPTY = cold).
        let thumbs = benchRoot.appendingPathComponent(
            LibrarySchema.thumbsDirectoryName(stem: "Bench"))
        let directory = packageURL.deletingLastPathComponent()
        let resolve: LibraryThumbnailBridge.URLResolver = { row in
            guard let kind = LibrarySchema.PathKind(rawValue: row.pathKind) else {
                return nil
            }
            if case .resolved(let url) = ImageLinker.resolve(
                imagePath: row.imagePath,
                pathKind: kind,
                volumeUUID: row.volumeUUID,
                projectDirectory: directory) {
                return url
            }
            return nil
        }
        let bridge = LibraryThumbnailBridge(
            thumbsDirectory: thumbs, renderLeg: nil, resolveURL: resolve)

        let benchModel = LibraryGridModel(queries: benchQueries, pageSize: screen)
        try await benchModel.apply(
            filter: ExifSearchFilter(),
            sort: FilterSort(key: .filename, ascending: true))
        let rows = Array(benchModel.rows.prefix(screen))
        XCTAssertEqual(rows.count, screen)

        // The first screen COLD: one production per row (the gate merges —
        // a sequential walk keeps the per-image attribution honest).
        func ms(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1_000
                + Double(duration.components.attoseconds) / 1e15
        }
        let clock = ContinuousClock()
        var perImage: [Double] = []
        let start = clock.now
        for row in rows {
            let imageStart = clock.now
            let image = await bridge.thumbnail(for: row)
            perImage.append(ms(clock.now - imageStart))
            XCTAssertNotNil(image, "tier A must produce for \(row.filename ?? "?")")
        }
        let totalMs = ms(clock.now - start)
        let sorted = perImage.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, (sorted.count * 95 + 99) / 100)]

        let productions = await bridge.productionCount
        print("BENCH| thumbnail first-screen tier-A (cold): N=\(screen) "
            + String(format: "total=%.1fms", totalMs)
            + String(format: " median=%.1fms", median)
            + String(format: " p95=%.1fms", p95)
            + String(format: " max=%.1fms", sorted[sorted.count - 1])
            + " corpus=2x86MP-ARW+1x12MP-JPG hardlinked, productions=\(productions)")
        try await store.close()
    }
}
