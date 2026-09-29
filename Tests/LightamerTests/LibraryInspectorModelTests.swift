import Foundation
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryInspectorModelTests (Plan M2-3-2 T2, AC #2/#3/#4) — the Album
// Inspector's logic face over a REAL `.lalb` fixture:
//
//   • the four group clicks fold typed arms (dayFilter between / camera
//     eq + empty / rating eq / lens eq) into the ONE filter group
//   • a same-arm re-click removes it (反选); the breadcrumb retreats per arm
//   • the overview card rides the filter (总数卡联动)
//   • an Activity bar click folds the same date leg
//   • the smart-album leg evaluates the member set (KD-5 closed loop) and
//     folds the album's own predicate; nil query face = the typed
//     missingStore empty state
//   • currentFilterDescription renders the folded state verbatim
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryInspectorModelTests: XCTestCase {

    private var tempDirectory: URL!
    private var albumDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var queries: LibraryQueries!
    private var grid: LibraryGridModel!
    private var model: LibraryInspectorModel!
    private var smartAlbumStore: SmartAlbumStore!

    private struct SeedRow {
        var path: String
        var date: Double?
        var rating: Int64?
        var make: String?
        var model: String?
        var lens: String?
    }

    // 12 rows / 3 days (06-01×4, 06-02×3, 06-03×3, NULL×2):
    //   Sony A7R5 ×5 (1,2,5,6,11) / Canon R5 ×2 / Nikon Z8 ×2 / Unknown ×3
    //   lens FE24-70 ×4 / FE85 ×2 / RF24-70 ×2 / FE24-70-Nikon ×1 / Unknown ×3
    //   ratings: 5×2, 4×3, 3×1, 2×1, 0×1, nil×4
    private static let twelveRows: [SeedRow] = [
        .init(path: "Media/00.arw", date: 1_717_200_000, rating: 5,
              make: "Sony", model: "A7R5", lens: "FE 24-70"),
        .init(path: "Media/01.arw", date: 1_717_203_600, rating: 4,
              make: "Sony", model: "A7R5", lens: "FE 24-70"),
        .init(path: "Media/02.arw", date: 1_717_207_200, rating: 4,
              make: "Canon", model: "R5", lens: "RF 24-70"),
        .init(path: "Media/03.arw", date: 1_717_210_800, rating: nil,
              make: "Canon", model: "R5", lens: "RF 24-70"),
        .init(path: "Media/04.arw", date: 1_717_286_400, rating: 3,
              make: "Sony", model: "A7R5", lens: "FE 85"),
        .init(path: "Media/05.arw", date: 1_717_290_000, rating: 5,
              make: "Sony", model: "A7R5", lens: "FE 85"),
        .init(path: "Media/06.arw", date: 1_717_293_600, rating: nil,
              make: nil, model: nil, lens: nil),
        .init(path: "Media/07.arw", date: 1_717_372_800, rating: 0,
              make: nil, model: nil, lens: nil),
        .init(path: "Media/08.nef", date: 1_717_376_400, rating: nil,
              make: "Nikon", model: "Z8", lens: nil),
        .init(path: "Media/09.nef", date: 1_717_380_000, rating: 2,
              make: "Nikon", model: "Z8", lens: "FE 24-70"),
        .init(path: "Media/10.arw", date: nil, rating: 4,
              make: "Sony", model: "A7R5", lens: "FE 24-70"),
        .init(path: "Media/11.arw", date: nil, rating: nil,
              make: nil, model: nil, lens: nil),
    ]

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-inspector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        albumDirectory = tempDirectory.appendingPathComponent("SmartAlbums", isDirectory: true)
        packageURL = tempDirectory.appendingPathComponent("Inspector.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Inspector")
        queries = LibraryQueries(store: fileStore)
        try await seed(Self.twelveRows)
        grid = LibraryGridModel(queries: queries, pageSize: 5)
        try await grid.reloadFirstPage()
        smartAlbumStore = SmartAlbumStore(directory: albumDirectory)
        model = LibraryInspectorModel(
            grid: grid,
            queries: queries,
            smartAlbums: smartAlbumStore)
        await model.refresh()
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        model = nil
        smartAlbumStore = nil
        grid = nil
        queries = nil
        fileStore = nil
        try await super.tearDown()
    }

    private func seed(_ rows: [SeedRow]) async throws {
        try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, capture_date,
                    rating, camera_make, camera_model, lens_model,
                    file_stem, filename)
                VALUES (?, 2, ?, ?, ?, ?, ?, ?, ?)
                """)
            for (index, row) in rows.enumerated() {
                let stem = String(format: "DSC%05d", index)
                try insert.reset()
                try insert.bindText(1, row.path)
                try insert.bindDouble(2, row.date)
                try insert.bindInt(3, row.rating)
                try insert.bindText(4, row.make)
                try insert.bindText(5, row.model)
                try insert.bindText(6, row.lens)
                try insert.bindText(7, stem)
                try insert.bindText(8, stem + ".arw")
                _ = try insert.step()
            }
            return true
        }
    }

    // MARK: - AC #2: the four group clicks fold typed arms

    func testDayClickFoldsDayFilterArm() async throws {
        let day = try XCTUnwrap(model.groups[.captureDate]?.first { $0.day == "2024-06-01" })
        XCTAssertEqual(day.count, 4)

        await model.toggle(group: .captureDate, payload: day)

        let arm = try XCTUnwrap(model.arms.first)
        guard case .day(let foldedDay) = arm.source else {
            XCTFail("expected a day arm")
            return
        }
        XCTAssertEqual(foldedDay, "2024-06-01")
        // The day projection rides LibraryQueries.dayFilter verbatim — a
        // captureDate BETWEEN covering the UTC day.
        let expected = try LibraryQueries.dayFilter("2024-06-01")
        XCTAssertEqual(arm.rules, expected.rules)
        XCTAssertTrue(arm.rules.contains {
            $0.field == .captureDate && $0.op == .between
        })
        // The grid filter carries the arm; the overview card followed.
        XCTAssertEqual(grid.filter.group.rules, arm.rules)
        XCTAssertEqual(model.overviewCount, 4)
    }

    func testCameraClickFoldsTypedEqRulesAndUnknownFoldsEmpty() async throws {
        let sony = try XCTUnwrap(model.groups[.camera]?.first { $0.label == "Sony A7R5" })
        XCTAssertEqual(sony.count, 5)
        XCTAssertNotNil(sony.cameraMake)
        XCTAssertNotNil(sony.cameraModel)

        await model.toggle(group: .camera, payload: sony)
        let arm = try XCTUnwrap(model.arms.first)
        XCTAssertEqual(
            arm.rules,
            [
                FilterPredicateGroup.Rule(
                    field: .cameraMake, op: .eq, value: .text("Sony")),
                FilterPredicateGroup.Rule(
                    field: .cameraModel, op: .eq, value: .text("A7R5")),
            ])
        XCTAssertEqual(model.overviewCount, 5)

        // Drop the arm: the group listing refreshes UNDER the current
        // filter, so the Unknown tier only lists while the filter allows it.
        await model.clearFilter()
        // The Unknown tier (both payload halves nil after the query face's
        // normalization) folds as the two `.empty` arms — no new rule shape.
        let unknown = try XCTUnwrap(model.groups[.camera]?.first { $0.label == "Unknown" })
        XCTAssertEqual(unknown.count, 3)
        XCTAssertNil(unknown.cameraMake)
        XCTAssertNil(unknown.cameraModel)
        await model.toggle(group: .camera, payload: unknown)
        let unknownArm = try XCTUnwrap(model.arms.last)
        XCTAssertEqual(unknownArm.rules.map(\.op), [.empty, .empty])
        XCTAssertEqual(Set(unknownArm.rules.map(\.field)), [.cameraMake, .cameraModel])
        XCTAssertEqual(model.overviewCount, 3)
    }

    func testRatingClickFoldsRatingArmAndUnratedIsRefused() async throws {
        let fiveStar = try XCTUnwrap(model.groups[.labels]?.first { $0.rating == 5 })
        XCTAssertEqual(fiveStar.count, 2)

        await model.toggle(group: .labels, payload: fiveStar)
        let arm = try XCTUnwrap(model.arms.first)
        XCTAssertEqual(
            arm.rules,
            [FilterPredicateGroup.Rule(field: .rating, op: .eq, value: .int(5))])
        XCTAssertEqual(model.overviewCount, 2)

        // Drop the arm (the listing refreshes under the filter).
        await model.clearFilter()
        // The Unrated tier (nil rating payload) has NO legal rule shape —
        // the click is refused (the view renders it inert), the filter is
        // untouched.
        let unrated = try XCTUnwrap(model.groups[.labels]?.first { $0.rating == nil })
        XCTAssertEqual(unrated.label, "Unrated")
        let armsBefore = model.arms
        await model.toggle(group: .labels, payload: unrated)
        XCTAssertEqual(model.arms, armsBefore)
    }

    func testLensClickFoldsLensArm() async throws {
        let lensGroup = try XCTUnwrap(model.groups[.lens]?.first { $0.lensModel == "FE 85" })
        XCTAssertEqual(lensGroup.count, 2)

        await model.toggle(group: .lens, payload: lensGroup)
        XCTAssertEqual(
            model.arms.first?.rules,
            [FilterPredicateGroup.Rule(
                field: .lensModel, op: .eq, value: .text("FE 85"))])
        XCTAssertEqual(model.overviewCount, 2)

        // Drop the arm (the listing refreshes under the filter).
        await model.clearFilter()
        // The Unknown lens tier folds as `.empty` (the NULL-or-empty class).
        let unknownLens = try XCTUnwrap(model.groups[.lens]?.first { $0.lensModel == nil })
        XCTAssertEqual(unknownLens.count, 4)
        await model.toggle(group: .lens, payload: unknownLens)
        XCTAssertEqual(model.arms.last?.rules.first?.op, .empty)
        XCTAssertEqual(model.arms.last?.rules.first?.field, .lensModel)
    }

    // MARK: - AC #2: re-click 反选 + breadcrumb retreat

    func testReClickRemovesTheArm() async throws {
        let sony = try XCTUnwrap(model.groups[.camera]?.first { $0.label == "Sony A7R5" })
        await model.toggle(group: .camera, payload: sony)
        XCTAssertEqual(model.arms.count, 1)
        await model.toggle(group: .camera, payload: sony)
        XCTAssertTrue(model.arms.isEmpty, "a same-arm re-click deselects")
        XCTAssertEqual(model.overviewCount, 12, "the filter is gone")
        XCTAssertTrue(grid.filter.group.rules.isEmpty)
    }

    func testBreadcrumbRetreatsArmByArm() async throws {
        let day = try XCTUnwrap(model.groups[.captureDate]?.first { $0.day == "2024-06-01" })
        let sony = try XCTUnwrap(model.groups[.camera]?.first { $0.label == "Sony A7R5" })
        await model.toggle(group: .captureDate, payload: day)
        await model.toggle(group: .camera, payload: sony)
        XCTAssertEqual(model.overviewCount, 2, "day 06-01 AND Sony")
        XCTAssertEqual(grid.filter.group.rules.count, 3)  // between + 2 eq

        await model.removeArm(at: 0)  // the day arm leaves first (FIFO order)
        XCTAssertEqual(model.arms.count, 1)
        XCTAssertEqual(model.overviewCount, 5, "Sony alone")

        await model.removeArm(at: 0)
        XCTAssertTrue(model.arms.isEmpty)
        XCTAssertEqual(model.overviewCount, 12)
    }

    func testClearFilterDropsArmsAndPlan() async throws {
        let day = try XCTUnwrap(model.groups[.captureDate]?.first { $0.day == "2024-06-01" })
        await model.toggle(group: .captureDate, payload: day)
        // A lexical plan rides beside the arms (the search dialog's leg);
        // the whole-June plan intersects the 06-01 arm to the same 4 rows.
        try await grid.apply(
            filter: ExifSearchFilter(
                group: grid.filter.group,
                plan: try ExifSearchParser.parse("2024-06")))
        await model.refresh()
        XCTAssertEqual(model.overviewCount, 4)

        await model.clearFilter()
        XCTAssertTrue(model.arms.isEmpty)
        XCTAssertTrue(grid.filter.plan.isEmpty, "clear drops the plan too")
        XCTAssertEqual(model.overviewCount, 12)
    }

    // MARK: - AC #3: Activity click = the date leg; the typed description

    func testActivityBarClickFoldsTheDateLeg() async throws {
        let days = model.activity.map(\.day)
        XCTAssertEqual(days, ["2024-06-01", "2024-06-02", "2024-06-03"])

        await model.toggleActivityDay("2024-06-02")
        guard case .day(let day) = model.arms.first?.source else {
            XCTFail("expected a day arm from the activity click")
            return
        }
        XCTAssertEqual(day, "2024-06-02")
        XCTAssertEqual(model.overviewCount, 3)
        // The same projection the capture-date row folds.
        let expected = try LibraryQueries.dayFilter("2024-06-02")
        XCTAssertEqual(model.arms.first?.rules, expected.rules)
    }

    func testFilterDescriptionRendersTheFoldedState() async throws {
        let day = try XCTUnwrap(model.groups[.captureDate]?.first { $0.day == "2024-06-01" })
        await model.toggle(group: .captureDate, payload: day)
        try await grid.apply(
            filter: ExifSearchFilter(
                group: grid.filter.group,
                plan: try ExifSearchParser.parse("sony iso800")))
        await model.refresh()

        let description = try XCTUnwrap(model.filterDescription)
        XCTAssertFalse(description.isEmpty)
        // The group rules come first, the plan's structured terms translate
        // behind them (the typed projection's documented order).
        XCTAssertEqual(description.rules.count, 2)  // between + iso eq
        XCTAssertEqual(description.rules.first?.field, .captureDate)
        XCTAssertEqual(description.rules.last?.field, .iso)
        XCTAssertEqual(description.ftsTerms, ["sony"])
        XCTAssertEqual(description.structuredTerms.count, 1)
        XCTAssertNil(description.dateRange)
    }

    // MARK: - AC #4: the smart-album leg (KD-5)

    private func makeSmartAlbum() async throws -> SmartAlbum {
        return try smartAlbumStore.create(
            name: "Top Rated",
            group: FilterPredicateGroup(
                match: .all,
                rules: [
                    FilterPredicateGroup.Rule(
                        field: .rating, op: .gte, value: .int(4))
                ]))
    }

    func testSmartAlbumClickFoldsAlbumPredicateWithMemberCount() async throws {
        let album = try await makeSmartAlbum()
        await model.refresh()

        XCTAssertEqual(model.smartAlbumMemberCounts[album.id], 5, "rating ≥ 4")

        await model.toggleSmartAlbum(album)
        let arm = try XCTUnwrap(model.arms.first)
        guard case .smartAlbum(let id) = arm.source else {
            XCTFail("expected a smart-album arm")
            return
        }
        XCTAssertEqual(id, album.id)
        // The ALBUM'S OWN predicate folds (成员集 → 相册谓词).
        XCTAssertEqual(arm.rules, album.group.rules)
        XCTAssertEqual(model.overviewCount, 5, "the grid shows the member set")

        // Re-click = 反选.
        await model.toggleSmartAlbum(album)
        XCTAssertTrue(model.arms.isEmpty)
        XCTAssertEqual(model.overviewCount, 12)
    }

    func testNilQueryFaceSurfacesTypedMissingStoreEmptyState() async throws {
        let album = try await makeSmartAlbum()
        let defense = LibraryInspectorModel(
            grid: grid, queries: nil,
            smartAlbums: smartAlbumStore)
        await defense.refresh()

        XCTAssertFalse(defense.smartAlbumsUnavailable, "refresh stays quiet")
        XCTAssertTrue(defense.smartAlbumRows.isEmpty, "no rows without a store")
        // The click faces the typed refusal — the empty-state flag.
        await defense.toggleSmartAlbum(album)
        XCTAssertTrue(defense.smartAlbumsUnavailable)
        XCTAssertTrue(defense.arms.isEmpty)
    }
}
