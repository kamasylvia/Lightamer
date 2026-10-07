import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryFilterDomainTests (Plan M2-2-1 T4, KD-7) — the `.library` domain of
// the ONE translation face:
//
//   • SHAPE: `+i.` alias refs (the F10 discipline), the `(1=1)` baseline,
//     the `image_path ASC` tiebreaker, the materialized-keywords
//     four-clause with `+i.keywords` — exact string + bind-order pins
//   • SNAPSHOT: `.session` / `.catalog` spellings are byte-identical to
//     their pre-M2-2-1 output (the regression lock — no other test file
//     needed changes to prove it, this is the explicit reconciliation)
//   • FULL CHAIN: FilterPredicateGroup → LibraryStore filter album JSON →
//     read back → translate(.library) → a REAL query over `FROM images i`
//     with applied binds hits exactly the right rows (the smart-album
//     semantics end to end)
//   • PLACEHOLDER: SmartAlbumStore.evaluate(.library) is the typed
//     missingStore refusal (M2-2-3 fills the real face)
// ─────────────────────────────────────────────────────────────────────────────

final class LibraryFilterDomainTests: XCTestCase {

    // MARK: - Shape pins

    func testLibraryBaselineIsAlwaysTrue() throws {
        let empty = FilterPredicateGroup(rules: [])
        let query = try FilterSQL.translate(group: empty, domain: .library)
        XCTAssertEqual(query.whereClause, "(1=1) AND (1=1)")
        XCTAssertEqual(query.binds, [])
    }

    func testLibraryColumnRefCarriesPlusAliasAndBindOrder() throws {
        let group = FilterPredicateGroup(
            match: .all,
            rules: [
                .init(field: .rating, op: .gte, value: .int(4)),
                .init(field: .iso, op: .between, value: .intRange(lower: 100, upper: 1600)),
            ])
        let query = try FilterSQL.translate(group: group, domain: .library)
        XCTAssertEqual(
            query.whereClause,
            "((+i.rating >= ?) AND (+i.iso BETWEEN ? AND ?)) AND (1=1)")
        XCTAssertEqual(
            query.binds, [.int(4), .int(100), .int(1600)],
            "bind order = rule order — the array IS the contract")
    }

    func testLibraryKeywordsHitMaterializedColumnWithFourClauses() throws {
        let group = FilterPredicateGroup(
            match: .all,
            rules: [.init(field: .keywords, op: .contains, value: .text("Nature"))])
        let query = try FilterSQL.translate(group: group, domain: .library)
        // The session four-clause shape over the `+i.` materialized column.
        XCTAssertEqual(
            query.whereClause,
            "(+i.keywords = ? OR +i.keywords LIKE ? || '|%' ESCAPE '\\'"
                + " OR +i.keywords LIKE '%|' || ? || '|%' ESCAPE '\\'"
                + " OR +i.keywords LIKE '%|' || ? ESCAPE '\\') AND (1=1)")
        XCTAssertEqual(query.binds.count, 4)
        // "Nature" carries no LIKE metacharacters — the bound value is the
        // raw tag (the ESCAPE clause is SQL text, not part of the bind).
        XCTAssertEqual(query.binds.first, .text("Nature"))
    }

    func testLibraryEmptyNotEmptyKeywordsTwoState() throws {
        let empty = FilterPredicateGroup(
            match: .all,
            rules: [.init(field: .keywords, op: .empty, value: .text(""))])
        let query = try FilterSQL.translate(group: empty, domain: .library)
        XCTAssertEqual(
            query.whereClause, "(+i.keywords IS NULL OR +i.keywords = '') AND (1=1)")
        let notEmpty = FilterPredicateGroup(
            match: .all,
            rules: [.init(field: .keywords, op: .notEmpty, value: .text(""))])
        let notQuery = try FilterSQL.translate(group: notEmpty, domain: .library)
        XCTAssertEqual(
            notQuery.whereClause,
            "(+i.keywords IS NOT NULL AND +i.keywords != '') AND (1=1)")
    }

    func testLibraryOrderTiebreakerIsImagePath() {
        let sort = FilterSort(key: .captureDate, ascending: true)
        XCTAssertEqual(
            sort.orderBySQL(domain: .library),
            "(capture_date IS NULL), capture_date ASC, image_path ASC")
        let descending = FilterSort(key: .rating, ascending: false)
        XCTAssertEqual(
            descending.orderBySQL(domain: .library),
            "(rating IS NULL), rating DESC, image_path ASC",
            "the tiebreaker stays ASC — deterministic row sets over equal keys")
    }

    // MARK: - Domain snapshots (byte-identical regressions)

    func testSessionDomainSnapshotUnchanged() throws {
        let group = FilterPredicateGroup(
            match: .all,
            rules: [.init(field: .rating, op: .gte, value: .int(4))])
        let query = try FilterSQL.translate(group: group, domain: .session)
        XCTAssertEqual(
            query.whereClause, "(rating >= ?) AND (orphan_sidecar = 0)",
            "the session shape is byte-identical to the pre-M2-2-1 output")
        XCTAssertEqual(
            FilterSort(key: .captureDate, ascending: true).orderBySQL(domain: .session),
            "(capture_date IS NULL), capture_date ASC, path ASC")
        let conjoined = try FilterSQL.translateConjoining(
            [group], domain: .session)
        XCTAssertEqual(
            conjoined.whereClause, "((rating >= ?)) AND (orphan_sidecar = 0)")
    }

    func testCatalogDomainSnapshotUnchanged() throws {
        let group = FilterPredicateGroup(
            match: .all,
            rules: [.init(field: .rating, op: .gte, value: .int(4))])
        let query = try FilterSQL.translate(group: group, domain: .catalog)
        XCTAssertEqual(
            query.whereClause, "(+i.rating >= ?) AND (+i.orphan_sidecar = 0)",
            "the catalog shape is byte-identical to the pre-M2-2-1 output")
        XCTAssertEqual(
            FilterSort(key: .captureDate, ascending: true).orderBySQL(domain: .catalog),
            "(capture_date IS NULL), capture_date ASC, rel_path ASC")
    }

    // MARK: - Smart-album full chain over the REAL package

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: LibraryStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-filter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("FilterProj.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "FilterProj")
        store = LibraryStore(store: fileStore)

        // a.arw: rating 5, "Nature" — HITS both rules.
        // b.arw: rating 2, no keywords — hits neither.
        // c.arw: rating 4, "Nature|Landscape" — the ancestor four-clause hit.
        let rows: [(String, Int64, String?)] = [
            ("Media/a.arw", 5, "Nature"),
            ("Media/b.arw", 2, nil),
            ("Media/c.arw", 4, "Nature|Landscape"),
        ]
        for (path, rating, keywords) in rows {
            let id = try await store.insertImage(
                record: LibraryImageRecord(
                    imagePath: path, pathKind: .projectRelative))
            _ = try await fileStore.withHandle { handle -> Bool in
                let update = try handle.prepare(
                    "UPDATE images SET rating = ?, keywords = ? WHERE id = ?")
                try update.bindInt(1, rating)
                try update.bindText(2, keywords)
                try update.bindInt(3, id)
                _ = try update.step()
                return true
            }
            _ = id
        }
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// The M2-2-3-shaped query face: translate(.library) over `FROM images i`
    /// with the KD-7 tiebreaker, binds applied in array order.
    private func runLibraryQuery(
        _ group: FilterPredicateGroup, sort: FilterSort
    ) async throws -> [String] {
        let query = try FilterSQL.translate(group: group, domain: .library)
        let sql = "SELECT i.image_path FROM images i WHERE "
            + query.whereClause + " ORDER BY " + sort.orderBySQL(domain: .library)
        return try await fileStore.withHandle { handle -> [String] in
            let statement = try handle.prepare(sql)
            try FilterSQL.apply(query.binds, to: statement)
            var paths: [String] = []
            while try statement.step() {
                if let path = statement.columnText(0) { paths.append(path) }
            }
            return paths
        }
    }

    func testSmartAlbumGroupFullChainHitsRealRows() async throws {
        // The smart album: rating >= 4 AND keywords contains Nature.
        let group = FilterPredicateGroup(
            match: .all,
            rules: [
                .init(field: .rating, op: .gte, value: .int(4)),
                .init(field: .keywords, op: .contains, value: .text("Nature")),
            ])
        let album = try await store.createAlbum(
            kind: .filter, name: "Top Nature", filterGroup: group)

        // Read the persisted JSON back (the M2-2-3 evaluation's entry).
        let persisted = try await store.album(id: album.id)
        let restored = try XCTUnwrap(persisted.filterGroup)

        let hits = try await runLibraryQuery(
            restored, sort: FilterSort(key: .captureDate, ascending: true))
        XCTAssertEqual(hits, ["Media/a.arw", "Media/c.arw"])
    }

    func testKeywordsAncestorChainViaMaterializedColumn() async throws {
        // keywords contains "Nature" alone — the four-clause ancestor
        // semantics over the | -joined materialized string.
        let group = FilterPredicateGroup(
            match: .all,
            rules: [.init(field: .keywords, op: .contains, value: .text("Nature"))])
        let hits = try await runLibraryQuery(
            group, sort: FilterSort(key: .filename, ascending: true))
        XCTAssertEqual(hits, ["Media/a.arw", "Media/c.arw"])
    }

    func testEvaluateLibraryIsTheTypedPlaceholder() async throws {
        let smartAlbums = SmartAlbumStore(
            directory: tempDirectory.appendingPathComponent("SmartAlbums"))
        let album = try smartAlbums.create(
            name: "Rated",
            group: FilterPredicateGroup(
                rules: [.init(field: .rating, op: .gte, value: .int(4))]))
        do {
            _ = try await smartAlbums.evaluate(
                id: album.id, domain: .library,
                sessionStore: nil, catalogStore: nil)
            XCTFail("expected missingStore (the M2-2-1 placeholder)")
        } catch let error as SmartAlbumError {
            XCTAssertEqual(error, .missingStore)
        }
    }
}
