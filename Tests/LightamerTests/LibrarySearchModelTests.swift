import Foundation
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySearchModelTests (Plan M2-3-2 T3, AC #5) — the global search's
// EXIF lexical leg over a REAL `.lalb` fixture:
//
//   • the parser's typed errors map to the four presentation families
//     (iso / aperture / date-disjoint / unrecognized) — pure classification
//   • a legal query assembles the plan into the SHARED filter (the grid's
//     rows and the typed description move together — the double linkage)
//   • empty input installs the empty plan (清过滤; the group arms stay)
//   • the placeholder modes never touch the collection (no fake results)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibrarySearchModelTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var queries: LibraryQueries!
    private var grid: LibraryGridModel!
    private var model: LibrarySearchModel!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Search.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Search")
        queries = LibraryQueries(store: fileStore)
        grid = LibraryGridModel(queries: queries, pageSize: 5)
        try await seed()
        try await grid.reloadFirstPage()
        model = LibrarySearchModel(grid: grid)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        model = nil
        grid = nil
        queries = nil
        fileStore = nil
        try await super.tearDown()
    }

    /// 12 rows, ISO spread 100..8000 (the M2-2-3 fixture shape).
    private func seed() async throws {
        try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, capture_date,
                    rating, iso, file_stem, filename)
                VALUES (?, 2, ?, ?, ?, ?, ?)
                """)
            let isos: [Int64?] = [
                800, 800, 1600, 8000, 100, 200,
                400, 800, 1600, 3200, 6400, 800,
            ]
            for (index, iso) in isos.enumerated() {
                let stem = String(format: "DSC%05d", index)
                try insert.reset()
                try insert.bindText(1, "Media/\(stem).arw")
                try insert.bindDouble(2, 1_717_200_000 + Double(index) * 3_600)
                try insert.bindInt(3, Int64(index % 6))
                try insert.bindInt(4, iso)
                try insert.bindText(5, stem)
                try insert.bindText(6, stem + ".arw")
                _ = try insert.step()
            }
            return true
        }
    }

    // MARK: - The four typed error families (pure classification)

    func testTypedErrorFamiliesMapForTheDialog() {
        // iso 非法: an `iso…` head that parses nowhere.
        XCTAssertEqual(
            LibrarySearchModel.family(for: .unrecognizedToken("isoabc")),
            .isoToken("isoabc"))
        // 光圈非法: the `f` head + numeric-looking junk.
        XCTAssertEqual(
            LibrarySearchModel.family(for: .unrecognizedToken("f/2.8.5")),
            .apertureToken("f/2.8.5"))
        // 日期 disjoint.
        XCTAssertEqual(
            LibrarySearchModel.family(for: .disjointDateRanges),
            .dateDisjoint)
        // unrecognized 词: a date-shaped typo that parses nowhere.
        XCTAssertEqual(
            LibrarySearchModel.family(for: .unrecognizedToken("2024-02-30")),
            .unrecognizedToken("2024-02-30"))
    }

    func testSubmitSurfacesEachFamilyInlineWithoutTouchingTheGrid() async throws {
        try await grid.apply(sort: FilterSort(key: .filename, ascending: true))
        let rowsBefore = grid.rows

        for (input, expected) in [
            ("isoabc", LibrarySearchModel.ErrorFamily.isoToken("isoabc")),
            ("f/2.8.5", .apertureToken("f/2.8.5")),
            ("2024-06 2023-01", .dateDisjoint),
            ("2024-02-30", .unrecognizedToken("2024-02-30")),
        ] {
            let outcome = await model.submit(input)
            XCTAssertEqual(
                outcome, .failed(expected), "input \(input) → its family")
        }

        // A failed submit never mutates the collection.
        XCTAssertEqual(grid.rows.count, rowsBefore.count)
        XCTAssertTrue(grid.filter.plan.isEmpty)
    }

    // MARK: - The plan assembly (KD-3: parse → filter fold)

    func testLegalQueryFoldsThePlanIntoTheSharedFilter() async throws {
        try await grid.apply(sort: FilterSort(key: .filename, ascending: true))
        XCTAssertEqual(grid.rows.count, 5, "the first page is preloaded")

        let outcome = await model.submit("iso800 35mm 2024-06")
        guard case .applied(let termCount) = outcome else {
            XCTFail("expected an applied outcome, got \(outcome)")
            return
        }
        XCTAssertEqual(termCount, 3, "one iso term + one focal term + one date window")

        // The plan lands on the SHARED cursor (typed fields, no re-parse).
        XCTAssertEqual(grid.filter.plan.ftsTerms, [])
        XCTAssertEqual(grid.filter.plan.structured.count, 2)
        XCTAssertEqual(grid.filter.plan.structured.first?.field, .iso)
        XCTAssertEqual(grid.filter.plan.structured.first?.constraint, .equals(800))
        XCTAssertNotNil(grid.filter.plan.dateRange)

        // The grid moved with the filter (double linkage, grid side): no
        // seeded row carries 35mm, so the whole collection filters out.
        XCTAssertEqual(grid.rows.count, 0)

        // …and the Inspector's typed rendering source reads the same plan
        // (the SEARCH FILTER area's verbatim face).
        let description = await queries.currentFilterDescription(filter: grid.filter)
        XCTAssertEqual(description.structuredTerms.count, 2)
        XCTAssertNotNil(description.dateRange)
        XCTAssertFalse(description.isEmpty)
    }

    // MARK: - Empty input = 清过滤 (the parser's 恒真 semantics)

    func testEmptySubmitInstallsTheAlwaysTruePlan() async throws {
        try await grid.apply(sort: FilterSort(key: .iso, ascending: true))
        _ = await model.submit("iso800")
        XCTAssertEqual(grid.rows.count, 4, "iso 800 rows only")

        // An empty/whitespace submit installs the EMPTY plan — the lexical
        // leg drops, the collection refetches, the group arms stay.
        _ = await model.submit("   ")
        XCTAssertTrue(grid.filter.plan.isEmpty)
        XCTAssertEqual(grid.rows.count, 5, "the first page refetched, unfiltered")

        let outcome = await model.submit("")
        XCTAssertEqual(outcome, .applied(termCount: 0))
    }

    // MARK: - The placeholder modes never fabricate results (D8)

    func testPlaceholderModesRefuseWithoutFakeResults() async throws {
        try await grid.apply(sort: FilterSort(key: .filename, ascending: true))
        let rowsBefore = grid.rows.count

        model.select(mode: .clip)
        let outcome = await model.submit("a red bicycle at dusk")
        guard case .failed = outcome else {
            XCTFail("the CLIP placeholder must refuse, not fabricate")
            return
        }
        XCTAssertEqual(grid.rows.count, rowsBefore, "the collection is untouched")
        XCTAssertTrue(grid.filter.plan.isEmpty)

        model.select(mode: .fullText)
        let fullTextOutcome = await model.submit("sunset portrait")
        guard case .failed = fullTextOutcome else {
            XCTFail("the full-text placeholder must refuse, not fabricate")
            return
        }
        XCTAssertTrue(grid.filter.plan.isEmpty)
    }
}
