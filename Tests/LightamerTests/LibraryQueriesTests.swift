import Foundation
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryQueriesTests (Plan M2-2-3 T2) — the Inspector/query data face over a
// REAL `.lalb` package:
//
//   • keyset pagination (KD-3): anchor-advance walks every row exactly once
//     (ASC + DESC), the NULL tail is its own second segment, no gap no
//     overlap (the CatalogIndexStore suite's shapes)
//   • the KD-3 sort whitelist: `scanEpoch` is a typed rejection at the entry
//   • four groups (KD-4): exact counts + Unknown normalization + typed
//     payloads; Activity day series + the dayFilter projection round-trip
//   • the mixed query (KD-2): group ∩ FTS MATCH ∩ structured terms — three
//     ANDed legs, each strictly larger alone
//   • lexical exactness (KD-6): `iso800` never hits the iso==8000 row —
//     pinned on BOTH legs (structured eq + FTS exact token)
//   • the M2-2-1 T4 seam closure: SmartAlbumStore.evaluate(.library) hits
//     the SAME set as the direct LibraryQueries walk
//   • the typed filter description (AC #6): field assertions, no strings
// ─────────────────────────────────────────────────────────────────────────────

final class LibraryQueriesTests: XCTestCase {

    // MARK: - Fixture (12 rows: 5/4/3 day split, 5 cameras, 6 lenses,
    // 5 rating tiers, one iso==8000 row for the KD-6 negative pin)

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: LibraryStore!
    private var queries: LibraryQueries!

    /// day epochs: 2024-06-01/02/03 12:00:00 UTC (+ hour offsets).
    private let day1: Double = 1_717_224_000  // 2024-06-01 12:00 UTC
    private let day2: Double = 1_717_310_400  // 2024-06-02 12:00 UTC
    private let day3: Double = 1_717_396_800  // 2024-06-03 12:00 UTC

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-queries-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Queries.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Queries")
        store = LibraryStore(store: fileStore)
        queries = LibraryQueries(store: fileStore)
        try await seed(Self.twelveRows)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    struct SeedRow {
        var path: String
        var make: String?
        var model: String?
        var lens: String?
        var iso: Int64?
        var focal: Double?
        var aperture: Double?
        var date: Double?
        var rating: Int64?
    }

    static let twelveRows: [SeedRow] = [
        .init(path: "Media/00.arw", make: "Sony", model: "A7R V",
              lens: "FE 24-70 F2.8 GM", iso: 800, focal: 24, aperture: 2.8,
              date: 1_717_224_000, rating: 5),
        .init(path: "Media/01.arw", make: "Sony", model: "A7R V",
              lens: "FE 24-70 F2.8 GM", iso: 800, focal: 35, aperture: 2.8,
              date: 1_717_224_000, rating: 4),
        .init(path: "Media/02.arw", make: "Sony", model: "A7R V",
              lens: "FE 85 F1.8", iso: 1600, focal: 85, aperture: 1.8,
              date: 1_717_227_600, rating: 4),
        .init(path: "Media/03.arw", make: "Sony", model: "A7R V",
              lens: "FE 85 F1.8", iso: 8000, focal: 85, aperture: 1.8,
              date: 1_717_231_200, rating: 0),
        .init(path: "Media/04.arw", make: "Canon", model: "EOS R5",
              lens: "RF 50 F1.2 L", iso: 100, focal: 50, aperture: 1.2,
              date: 1_717_310_400, rating: 5),
        .init(path: "Media/05.arw", make: "Canon", model: "EOS R5",
              lens: "RF 50 F1.2 L", iso: 200, focal: 50, aperture: 4,
              date: 1_717_314_000, rating: nil),
        .init(path: "Media/06.arw", make: "Canon", model: "EOS R5",
              lens: nil, iso: 400, focal: nil, aperture: nil,
              date: 1_717_317_600, rating: nil),
        .init(path: "Media/07.nef", make: nil, model: nil,
              lens: "NIKKOR Z 24-70", iso: 800, focal: 24, aperture: 2.8,
              date: 1_717_321_200, rating: 3),
        .init(path: "Media/08.raf", make: "", model: "X-T5",
              lens: "XF 35 F1.4", iso: 1600, focal: 35, aperture: 1.4,
              date: 1_717_396_800, rating: 3),
        .init(path: "Media/09.raf", make: "Fujifilm", model: nil,
              lens: "XF 35 F1.4", iso: 3200, focal: 35, aperture: 4,
              date: 1_717_400_400, rating: nil),
        .init(path: "Media/10.arw", make: nil, model: nil,
              lens: nil, iso: 6400, focal: nil, aperture: nil,
              date: nil, rating: nil),
        .init(path: "Media/11.arw", make: "Sony", model: "A7R V",
              lens: "FE 24-70 F2.8 GM", iso: 800, focal: 200, aperture: 2.8,
              date: 1_717_224_000, rating: 4),
    ]

    private func seed(_ rows: [SeedRow]) async throws {
        try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, camera_make,
                    camera_model, lens_model, iso, focal_length, aperture,
                    capture_date, rating, file_stem, exif_search_text,
                    exif_search_words, filename)
                VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for (index, row) in rows.enumerated() {
                let stem = String(format: "DSC%05d", index)
                let facts = ExifFold.Facts(
                    fileStem: stem, cameraMake: row.make,
                    cameraModel: row.model, lensModel: row.lens,
                    iso: row.iso.map(Int.init), focalLength: row.focal,
                    aperture: row.aperture,
                    captureDate: row.date.map { Date(timeIntervalSince1970: $0) })
                let folded = ExifFold.foldedVariants(for: facts)
                try insert.reset()
                try insert.bindText(1, row.path)
                try insert.bindText(2, row.make)
                try insert.bindText(3, row.model)
                try insert.bindText(4, row.lens)
                try insert.bindInt(5, row.iso)
                try insert.bindDouble(6, row.focal)
                try insert.bindDouble(7, row.aperture)
                try insert.bindDouble(8, row.date)
                try insert.bindInt(9, row.rating)
                try insert.bindText(10, stem)
                try insert.bindText(11, folded.text)
                try insert.bindText(12, folded.words)
                try insert.bindText(13, stem + ".arw")
                _ = try insert.step()
            }
            return true
        }
    }

    // MARK: - Keyset pagination (KD-3): no gap, no overlap, to exhaustion

    private func walkAll(
        sort: FilterSort, limit: Int = 5
    ) async throws -> [LibraryImageRow] {
        var collected: [LibraryImageRow] = []
        var anchor: LibraryPageAnchor?
        var tailAnchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchPage(
                sort: sort, anchor: anchor, limit: limit)
            if page.isEmpty {
                let tail = try await queries.searchNullTail(
                    sort: sort, anchor: tailAnchor, limit: limit)
                if tail.isEmpty { break }
                collected.append(contentsOf: tail)
                guard let last = tail.last else { break }
                tailAnchor = LibraryPageAnchor(
                    keyValue: .int(nil), imagePath: last.imagePath)
            } else {
                collected.append(contentsOf: page)
                guard let last = page.last else { break }
                anchor = LibraryPageAnchor(
                    keyValue: Self.keyValue(of: last, key: sort.key),
                    imagePath: last.imagePath)
            }
        }
        return collected
    }

    private static func keyValue(
        of row: LibraryImageRow, key: FilterSortKey
    ) -> FilterSQLBind {
        switch key {
        case .captureDate: .double(row.captureDate ?? 0)
        case .rating: .int(row.rating ?? 0)
        case .filename: .text(row.filename ?? "")
        case .iso: .int(row.iso ?? 0)
        case .focalLength: .double(row.focalLength ?? 0)
        case .scanEpoch: .int(0)
        }
    }

    func testKeysetAscendingWalkCoversEveryRowExactlyOnce() async throws {
        // Rows 1 and 11 share the SAME capture epoch — the tiebreaker tier
        // is exercised inside the walk.
        let sort = FilterSort(key: .captureDate, ascending: true)
        let walked = try await walkAll(sort: sort)
        XCTAssertEqual(walked.count, 12)
        XCTAssertEqual(Set(walked.map(\.id)).count, 12, "no duplicates")
        // The dated rows arrive in non-decreasing date order; the NULL row
        // (id of Media/10) rides the tail LAST.
        let dated = walked.filter { $0.captureDate != nil }
        let dates: [Double] = dated.compactMap(\.captureDate)
        XCTAssertEqual(
            dates, dates.sorted(),
            "the seek yields the tier order")
        XCTAssertEqual(walked.last?.imagePath, "Media/10.arw",
                       "the NULL-date row arrives via the tail segment")
    }

    func testKeysetDescendingWalkCoversEveryRowExactlyOnce() async throws {
        let sort = FilterSort(key: .captureDate, ascending: false)
        let walked = try await walkAll(sort: sort)
        XCTAssertEqual(walked.count, 12)
        XCTAssertEqual(Set(walked.map(\.id)).count, 12)
        let dated = walked.filter { $0.captureDate != nil }
        let descending: [Double] = dated.compactMap(\.captureDate)
        XCTAssertEqual(
            descending, descending.sorted(by: >),
            "DESC seek: dates non-increasing")
    }

    func testNullTailSegmentReturnsExactlyTheNullRows() async throws {
        let sort = FilterSort(key: .captureDate, ascending: true)
        let tail = try await queries.searchNullTail(sort: sort, limit: 60)
        XCTAssertEqual(tail.map(\.imagePath), ["Media/10.arw"])
        XCTAssertNil(tail.first?.captureDate)

        let ratingTail = try await queries.searchNullTail(
            sort: FilterSort(key: .rating, ascending: true), limit: 60)
        XCTAssertEqual(
            Set(ratingTail.map(\.imagePath)),
            Set(["Media/05.arw", "Media/06.arw", "Media/09.raf", "Media/10.arw"]),
            "the four unrated rows ride the rating NULL tier")
    }

    func testRatingSortWalkUsesBothSegments() async throws {
        let sort = FilterSort(key: .rating, ascending: true)
        let walked = try await walkAll(sort: sort)
        XCTAssertEqual(walked.count, 12)
        XCTAssertEqual(Set(walked.map(\.id)).count, 12)
        let rated = walked.filter { $0.rating != nil }
        let ratings: [Int64] = rated.compactMap(\.rating)
        XCTAssertEqual(
            ratings, ratings.sorted(),
            "NULLs last, then ascending tiers")
    }

    // MARK: - KD-3 whitelist guard (scanEpoch excluded)

    func testScanEpochSortIsATypedRejection() async throws {
        do {
            _ = try await queries.searchPage(
                sort: FilterSort(key: .scanEpoch, ascending: true))
            XCTFail("scanEpoch must be rejected at the library entry")
        } catch let error as LibraryError {
            guard case .constraintViolation(let detail) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(
                detail.contains("whitelist"),
                "the guard names the KD-3 whitelist: \(detail)")
        }
        do {
            _ = try await queries.searchNullTail(
                sort: FilterSort(key: .scanEpoch, ascending: true))
            XCTFail("the tail face shares the guard")
        } catch { /* typed rejection expected */ }
    }

    // MARK: - Four groups (KD-4): exact counts + Unknown + typed payloads

    func testGroupCountsCaptureDateKey() async throws {
        let counts = try await queries.groupCounts(by: .captureDate)
        XCTAssertEqual(
            counts.map(\.day), ["2024-06-01", "2024-06-02", "2024-06-03"])
        XCTAssertEqual(counts.map(\.count), [5, 4, 2], "row 10 carries the NULL date and rides the tail")
    }

    func testGroupCountsCameraKeyNormalizesUnknown() async throws {
        let counts = try await queries.groupCounts(by: .camera)
        XCTAssertEqual(
            counts.map(\.label),
            ["Canon EOS R5", "Fujifilm", "Sony A7R V", "Unknown", "X-T5"])
        XCTAssertEqual(counts.map(\.count), [3, 1, 5, 2, 1])
        // Typed payloads: Unknown carries nil; the make-less row labels by
        // model alone and carries it as the model payload.
        XCTAssertEqual(
            counts.first { $0.label == "Unknown" }?.cameraMake, nil)
        XCTAssertEqual(
            counts.first { $0.label == "X-T5" }?.cameraModel, "X-T5")
    }

    func testGroupCountsLabelsKeyTiers() async throws {
        let counts = try await queries.groupCounts(by: .labels)
        XCTAssertEqual(
            counts.map(\.label),
            ["Unrated", "No stars", "★★★", "★★★★", "★★★★★"])
        XCTAssertEqual(counts.map(\.count), [4, 1, 2, 3, 2])
        XCTAssertEqual(
            counts.map(\.rating), [nil, 0, 3, 4, 5],
            "the rating payload is typed (nil = the Unrated tier)")
    }

    func testGroupCountsLensKey() async throws {
        let counts = try await queries.groupCounts(by: .lens)
        XCTAssertEqual(
            counts.map(\.label),
            ["FE 24-70 F2.8 GM", "FE 85 F1.8", "NIKKOR Z 24-70",
             "RF 50 F1.2 L", "Unknown", "XF 35 F1.4"])
        XCTAssertEqual(counts.map(\.count), [3, 2, 1, 2, 2, 2])
    }

    // MARK: - Activity series + the dayFilter projection (KD-4)

    func testActivitySeriesIsThePerDayCountSource() async throws {
        let series = try await queries.activitySeries()
        XCTAssertEqual(
            series.map(\.day), ["2024-06-01", "2024-06-02", "2024-06-03"])
        XCTAssertEqual(series.map(\.count), [5, 4, 2])
    }

    func testActivitySeriesRespectsTheCalendarWindow() async throws {
        // June 1 11:59:59 → June 2 22:00 — covers all day-2 rows, excludes
        // every day-3 row.
        let window = Date(timeIntervalSince1970: day1 - 1)
            ... Date(timeIntervalSince1970: day2 + 36_000)
        let series = try await queries.activitySeries(range: window)
        XCTAssertEqual(series.map(\.day), ["2024-06-01", "2024-06-02"])
        XCTAssertEqual(series.map(\.count), [5, 4])
    }

    func testDayFilterProjectionHitsExactlyThatDay() async throws {
        let group = try LibraryQueries.dayFilter("2024-06-02")
        let rows = try await queries.searchPage(
            filter: ExifSearchFilter(group: group),
            sort: FilterSort(key: .captureDate, ascending: true), limit: 60)
        XCTAssertEqual(
            Set(rows.map(\.imagePath)),
            ["Media/04.arw", "Media/05.arw", "Media/06.arw", "Media/07.nef"])
        XCTAssertThrowsError(try LibraryQueries.dayFilter("June"))
    }

    // MARK: - The mixed query (KD-2): three ANDed legs

    func testMixedQueryThreeLegsAND() async throws {
        let group = FilterPredicateGroup(
            rules: [.init(
                field: .cameraModel, op: .eq, value: .text("A7R V"))])
        let plan = try ExifSearchParser.parse("fe iso:400-1600")

        // Each leg ALONE is strictly larger than the three-leg intersection.
        let groupAlone = try await queries.searchPage(
            filter: ExifSearchFilter(group: group),
            sort: FilterSort(key: .captureDate, ascending: true), limit: 60)
        XCTAssertEqual(groupAlone.count, 5, "rows 0,1,2,3,11")
        let lexicalAlone = try await queries.searchPage(
            filter: ExifSearchFilter(plan: try ExifSearchParser.parse("fe")),
            sort: FilterSort(key: .captureDate, ascending: true), limit: 60)
        XCTAssertEqual(lexicalAlone.count, 5, "the FE-lens token alone")
        let structuredAlone = try await queries.searchPage(
            filter: ExifSearchFilter(
                plan: try ExifSearchParser.parse("iso:400-1600")),
            sort: FilterSort(key: .captureDate, ascending: true), limit: 60)
        XCTAssertEqual(
            structuredAlone.count, 7,
            "the iso range alone: rows 0,1,2,6,7,8,11")

        let mixed = try await queries.searchPage(
            filter: ExifSearchFilter(group: group, plan: plan),
            sort: FilterSort(key: .captureDate, ascending: true), limit: 60)
        XCTAssertEqual(
            Set(mixed.map(\.imagePath)),
            ["Media/00.arw", "Media/01.arw", "Media/02.arw", "Media/11.arw"],
            "group ∩ FTS ∩ structured — the three legs AND (row 3's iso "
                + "8000 drops out; every single leg was strictly larger)")
    }

    func testEmptyFilterListsTheWholeLibraryAndEmptyLegsOmit() async throws {
        let all = try await queries.searchPage(
            sort: FilterSort(key: .captureDate, ascending: true), limit: 60)
        XCTAssertEqual(all.count, 12, "the (1=1) baseline face")
        let count = try await queries.overviewCount()
        XCTAssertEqual(count, 12)
    }

    func testOverviewCountRespectsTheFilter() async throws {
        let filter = ExifSearchFilter(
            group: FilterPredicateGroup(
                rules: [.init(
                    field: .cameraModel, op: .eq, value: .text("A7R V"))]),
            plan: try ExifSearchParser.parse("gm"))
        let count = try await queries.overviewCount(filter: filter)
        XCTAssertEqual(count, 3, "the count face rides the same mixed WHERE")
    }

    // MARK: - KD-6 lexical exactness: iso800 never hits iso8000

    func testISO800DoesNotHitISO8000RowViaStructuredLeg() async throws {
        let plan = try ExifSearchParser.parse("iso800")
        let rows = try await queries.searchPage(
            filter: ExifSearchFilter(plan: plan),
            sort: FilterSort(key: .captureDate, ascending: true), limit: 60)
        XCTAssertEqual(
            Set(rows.map(\.imagePath)),
            ["Media/00.arw", "Media/01.arw", "Media/07.nef", "Media/11.arw"])
        XCTAssertFalse(
            rows.contains { $0.iso == 8000 },
            "the structured eq is exact — the 8000 row never leaks")
    }

    func testISO800DoesNotHitISO8000RowViaFTSLeg() async throws {
        // The FTS face of the same negative: the folded index tokenizes
        // `iso 8000` as iso+8000 — the exact token `iso800` cannot hit it.
        let plan = ExifSearchPlan(ftsTerms: ["iso800"])
        let rows = try await queries.searchPage(
            filter: ExifSearchFilter(plan: plan),
            sort: FilterSort(key: .captureDate, ascending: true), limit: 60)
        XCTAssertEqual(
            Set(rows.map(\.imagePath)),
            ["Media/00.arw", "Media/01.arw", "Media/07.nef", "Media/11.arw"])
    }

    // MARK: - The M2-2-1 T4 seam closure: evaluate(.library)

    func testEvaluateLibraryHitsTheSameSetAsTheDirectWalk() async throws {
        let smartAlbums = SmartAlbumStore(
            directory: tempDirectory.appendingPathComponent("SmartAlbums"))
        let album = try smartAlbums.create(
            name: "Four Plus",
            group: FilterPredicateGroup(
                rules: [.init(field: .rating, op: .gte, value: .int(4))]))

        let evaluation = try await smartAlbums.evaluate(
            id: album.id, domain: .library,
            sessionStore: nil, catalogStore: nil, libraryQueries: queries)
        guard case .library(let imageIDs) = evaluation else {
            return XCTFail("expected the .library case, got \(evaluation)")
        }
        let direct = try await queries.memberIDs(
            matching: FilterPredicateGroup(
                rules: [.init(field: .rating, op: .gte, value: .int(4))]))
        XCTAssertEqual(Set(imageIDs), Set(direct))
        XCTAssertEqual(imageIDs.count, 5, "rows 0,1,2,4,11 carry rating >= 4")

        // The no-store injection keeps the typed refusal (the M2-2-1
        // placeholder semantics degrade honestly, never silently empty).
        do {
            _ = try await smartAlbums.evaluate(
                id: album.id, domain: .library,
                sessionStore: nil, catalogStore: nil, libraryQueries: nil)
            XCTFail("nil libraryQueries must stay a typed refusal")
        } catch let error as SmartAlbumError {
            XCTAssertEqual(error, .missingStore)
        }
    }

    // MARK: - The typed filter description (AC #6)

    func testFilterDescriptionIsTypedAndFlattened() async throws {
        let filter = ExifSearchFilter(
            group: FilterPredicateGroup(
                rules: [.init(
                    field: .cameraModel, op: .eq, value: .text("A7R V"))]),
            plan: try ExifSearchParser.parse("sony iso800 2024-06"))
        let description = await queries.currentFilterDescription(filter: filter)
        // Field-level assertions — the M2-3 render source, no string soup.
        XCTAssertEqual(description.ftsTerms, ["sony"])
        XCTAssertEqual(
            description.structuredTerms,
            [StructuredTerm(field: .iso, constraint: .equals(800))])
        XCTAssertEqual(
            description.dateRange,
            try ExifSearchParser.parse("2024-06").dateRange)
        XCTAssertEqual(description.rules.count, 3,
                       "group rule + iso rule + date rule, in order")
        XCTAssertEqual(description.rules[0].field, .cameraModel)
        XCTAssertEqual(description.rules[1].field, .iso)
        XCTAssertEqual(description.rules[2].field, .captureDate)
        XCTAssertFalse(description.isEmpty)
    }

    func testEmptyFilterDescriptionIsEmpty() async throws {
        let description = await queries.currentFilterDescription(
            filter: ExifSearchFilter())
        XCTAssertTrue(description.isEmpty)
        XCTAssertTrue(description.rules.isEmpty)
    }
}
