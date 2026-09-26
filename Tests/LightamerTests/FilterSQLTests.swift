import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 12-2 T2 — the ONE translation layer (FilterSQL):
//
//   • SQL/binds SNAPSHOT per field × operator shape (exact string equality)
//   • the FOUR-CLAUSE keywords ancestor predicate (F3 正本) — spelled once,
//     pinned verbatim
//   • group joins (AND/OR) + the `orphan_sidecar = 0` baseline riding EVERY
//     product + the empty group's `1=1`
//   • injection vectors: `'` (bind-literal), `%`/`_`/`\` (LIKE-escaped)
//   • fixture row sets (L020 — CONTENT-level, exact path sets, never
//     "non-empty"): the NatureHolics CONTROL GROUP (bare `LIKE '%Nature%'`
//     WOULD hit it; the four-clause must not), sub-tag hits, empty-class
//     rows, wildcard-literal filenames, quote filenames, AND/OR combos
//
// The fixture is a raw SQLiteHandle + the frozen schema apply (the query
// FACE on SessionIndexStore re-proves the same semantics in its own
// segment — translation SQL ↔ query row sets cross-validate).
// ─────────────────────────────────────────────────────────────────────────────

final class FilterSQLTests: XCTestCase {

    // MARK: - Snapshots (SQL + binds)

    func testNumericSnapshots() throws {
        // rating gte
        var q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .rating, op: .gte, value: .int(3))]))
        XCTAssertEqual(q.whereClause, "(rating >= ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.int(3)])

        // rating between (intRange)
        q = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .rating, op: .between, value: .intRange(lower: 1, upper: 5)),
            ]))
        XCTAssertEqual(q.whereClause, "(rating BETWEEN ? AND ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.int(1), .int(5)])

        // colorLabel in (intList)
        q = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .colorLabel, op: .in, value: .intList([0, 3])),
            ]))
        XCTAssertEqual(q.whereClause, "(color_label IN (?, ?)) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.int(0), .int(3)])

        // flag eq
        q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .flag, op: .eq, value: .int(1))]))
        XCTAssertEqual(q.whereClause, "(flag = ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.int(1)])

        // hasEdits eq
        q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .hasEdits, op: .eq, value: .int(1))]))
        XCTAssertEqual(q.whereClause, "(has_edits = ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.int(1)])

        // iso lt
        q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .iso, op: .lt, value: .int(800))]))
        XCTAssertEqual(q.whereClause, "(iso < ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.int(800)])

        // focalLength between (doubleRange)
        q = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .focalLength, op: .between, value: .doubleRange(lower: 24, upper: 70)),
            ]))
        XCTAssertEqual(q.whereClause, "(focal_length BETWEEN ? AND ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.double(24), .double(70)])

        // captureDate gte (epoch double)
        q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .captureDate, op: .gte, value: .double(1_700_000_000))]))
        XCTAssertEqual(q.whereClause, "(capture_date >= ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.double(1_700_000_000)])

        // aperture eq (double)
        q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .aperture, op: .eq, value: .double(2.8))]))
        XCTAssertEqual(q.whereClause, "(aperture = ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.double(2.8)])
    }

    func testKeywordsFourClauseSnapshot() throws {
        // THE four-clause (F3) — verbatim snapshot.
        let q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .keywords, op: .contains, value: .text("Nature"))]))
        XCTAssertEqual(
            q.whereClause,
            "(keywords = ? OR keywords LIKE ? || '|%' ESCAPE '\\' "
                + "OR keywords LIKE '%|' || ? || '|%' ESCAPE '\\' "
                + "OR keywords LIKE '%|' || ? ESCAPE '\\') AND (orphan_sidecar = 0)")
        // The same tag rides FOUR placeholders, in order.
        XCTAssertEqual(
            q.binds, [.text("Nature"), .text("Nature"), .text("Nature"), .text("Nature")])

        // keywords eq = exact whole-column (no LIKE, no escaping needed).
        let eq = try FilterSQL.translate(
            group: .init(rules: [.init(field: .keywords, op: .eq, value: .text("Nature"))]))
        XCTAssertEqual(eq.whereClause, "(keywords = ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(eq.binds, [.text("Nature")])
    }

    func testKeywordsInSnapshot() throws {
        let q = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .keywords, op: .in, value: .textList(["Nature", "Street"])),
            ]))
        // Any-of = per-tag four-clauses OR'd; 2 tags → 8 binds.
        XCTAssertEqual(
            q.whereClause,
            "((keywords = ? OR keywords LIKE ? || '|%' ESCAPE '\\' "
                + "OR keywords LIKE '%|' || ? || '|%' ESCAPE '\\' "
                + "OR keywords LIKE '%|' || ? ESCAPE '\\') "
                + "OR (keywords = ? OR keywords LIKE ? || '|%' ESCAPE '\\' "
                + "OR keywords LIKE '%|' || ? || '|%' ESCAPE '\\' "
                + "OR keywords LIKE '%|' || ? ESCAPE '\\')) AND (orphan_sidecar = 0)")
        XCTAssertEqual(
            q.binds,
            [.text("Nature"), .text("Nature"), .text("Nature"), .text("Nature"),
             .text("Street"), .text("Street"), .text("Street"), .text("Street")])
    }

    func testKeywordsEmptyClassSnapshots() throws {
        let empty = try FilterSQL.translate(
            group: .init(rules: [.init(field: .keywords, op: .empty, value: .text(""))]))
        XCTAssertEqual(
            empty.whereClause, "(keywords IS NULL OR keywords = '') AND (orphan_sidecar = 0)")
        XCTAssertEqual(empty.binds, [])

        let notEmpty = try FilterSQL.translate(
            group: .init(rules: [.init(field: .keywords, op: .notEmpty, value: .text(""))]))
        XCTAssertEqual(
            notEmpty.whereClause,
            "(keywords IS NOT NULL AND keywords != '') AND (orphan_sidecar = 0)")
        XCTAssertEqual(notEmpty.binds, [])

        // The text face shares the NULL/'' class shapes (the v2 '' sentinel).
        let noteEmpty = try FilterSQL.translate(
            group: .init(rules: [.init(field: .note, op: .empty, value: .text(""))]))
        XCTAssertEqual(noteEmpty.whereClause, "(note IS NULL OR note = '') AND (orphan_sidecar = 0)")
    }

    func testTextSnapshots() throws {
        var q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .filename, op: .contains, value: .text("IMG"))]))
        XCTAssertEqual(
            q.whereClause, "(filename LIKE '%' || ? || '%' ESCAPE '\\') AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.text("IMG")])

        q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .filename, op: .startsWith, value: .text("IMG_"))]))
        XCTAssertEqual(
            q.whereClause, "(filename LIKE ? || '%' ESCAPE '\\') AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.text("IMG\\_")])

        q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .cameraMake, op: .in, value: .textList(["Canon", "Nikon"]))]))
        XCTAssertEqual(q.whereClause, "(camera_make IN (?, ?)) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.text("Canon"), .text("Nikon")])

        q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .dir, op: .eq, value: .text("Capture"))]))
        XCTAssertEqual(q.whereClause, "(dir = ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.text("Capture")])

        q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .note, op: .neq, value: .text("draft"))]))
        XCTAssertEqual(q.whereClause, "(note != ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.text("draft")])
    }

    // MARK: - Groups + baseline

    func testGroupJoinsAndBaseline() throws {
        let and = try FilterSQL.translate(
            group: .init(
                match: .all,
                rules: [
                    .init(field: .rating, op: .gte, value: .int(3)),
                    .init(field: .keywords, op: .contains, value: .text("Nature")),
                ]))
        XCTAssertEqual(and.whereClause, "((rating >= ?) AND (keywords = ? OR keywords LIKE ? || '|%' ESCAPE '\\' OR keywords LIKE '%|' || ? || '|%' ESCAPE '\\' OR keywords LIKE '%|' || ? ESCAPE '\\')) AND (orphan_sidecar = 0)")
        XCTAssertEqual(and.binds.count, 5)
        XCTAssertEqual(and.binds[0], .int(3))

        let or = try FilterSQL.translate(
            group: .init(
                match: .any,
                rules: [
                    .init(field: .rating, op: .gte, value: .int(4)),
                    .init(field: .flag, op: .eq, value: .int(1)),
                ]))
        XCTAssertEqual(or.whereClause, "((rating >= ?) OR (flag = ?)) AND (orphan_sidecar = 0)")
        XCTAssertEqual(or.binds, [.int(4), .int(1)])

        // Empty group → 1=1 + the baseline (the "no filter" shape still
        // never lists orphan rows).
        let empty = try FilterSQL.translate(group: .init(rules: []))
        XCTAssertEqual(empty.whereClause, "(1=1) AND (orphan_sidecar = 0)")
        XCTAssertEqual(empty.binds, [])
    }

    // MARK: - Injection vectors

    func testQuoteIsBindLiteral() throws {
        let q = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .filename, op: .contains, value: .text("it's")),
            ]))
        // The template is unchanged and the quote rides the bind — zero
        // string interpolation anywhere.
        XCTAssertEqual(
            q.whereClause, "(filename LIKE '%' || ? || '%' ESCAPE '\\') AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.text("it's")])
    }

    func testLikeWildcardsAreEscaped() throws {
        // `%` and `_` in the VALUE must match literally (bind alone does not
        // neutralize LIKE metacharacters — the ESCAPE clause does).
        let q = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .filename, op: .contains, value: .text("100%_shot")),
            ]))
        XCTAssertEqual(q.binds, [.text("100\\%\\_shot")])

        // A backslash in the value is itself escaped (the escape char is
        // literal-safe).
        let kw = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .keywords, op: .contains, value: .text("a\\b%c")),
            ]))
        XCTAssertEqual(kw.binds[0], .text("a\\\\b\\%c"))
    }

    func testTranslateRejectsIllegalCombos() {
        // The translation layer re-validates defensively.
        XCTAssertThrowsError(
            try FilterSQL.translate(
                group: .init(rules: [
                    .init(field: .rating, op: .contains, value: .int(3)),
                ]))
        ) { error in
            XCTAssertEqual(
                error as? FilterPredicateError,
                .illegalFieldOperator(field: .rating, op: .contains))
        }
        XCTAssertThrowsError(
            try FilterSQL.translate(
                group: .init(rules: [
                    .init(field: .filename, op: .gte, value: .text("x")),
                ]))
        ) { error in
            XCTAssertEqual(
                error as? FilterPredicateError,
                .illegalFieldOperator(field: .filename, op: .gte))
        }
    }

    // MARK: - Sort whitelist

    func testSortWhitelistColumns() {
        XCTAssertEqual(FilterSortKey.filename.column, "filename")
        XCTAssertEqual(FilterSortKey.rating.column, "rating")
        XCTAssertEqual(FilterSortKey.captureDate.column, "capture_date")
        XCTAssertEqual(FilterSortKey.iso.column, "iso")
        XCTAssertEqual(FilterSortKey.focalLength.column, "focal_length")
        XCTAssertEqual(FilterSortKey.scanEpoch.column, "scan_epoch")
        XCTAssertEqual(FilterSortKey.allCases.count, 6)

        // NULLs last in BOTH directions + the path tiebreaker.
        XCTAssertEqual(
            FilterSort(key: .rating, ascending: true).orderBySQL,
            "(rating IS NULL), rating ASC, path ASC")
        XCTAssertEqual(
            FilterSort(key: .rating, ascending: false).orderBySQL,
            "(rating IS NULL), rating DESC, path ASC")
        XCTAssertEqual(
            FilterSort(key: .captureDate, ascending: false).orderBySQL,
            "(capture_date IS NULL), capture_date DESC, path ASC")
    }

    // MARK: - Fixture row sets (L020)

    private var handle: SQLiteHandle!

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("filtersql-\(UUID().uuidString).lindex")
        handle = try SQLiteHandle(path: url.path)
        try SessionIndexSchema.apply(to: handle)
        try Self.seedFixture(on: handle)
    }

    override func tearDown() {
        handle?.close()
        handle = nil
        super.tearDown()
    }

    /// The keyword/numeric fixture (exact, hand-enumerated):
    ///
    ///   nature-rose.arw   keywords `Nature|Flower|Rose`  rating 3
    ///   nature-tree.arw   keywords `Nature|Tree`         rating 2
    ///   natureholics.arw  keywords `NatureHolics`        rating 4  ← trap
    ///   nature.arw        keywords `Nature`              rating 1
    ///   cleared.arw       keywords `` (cleared)          flag 1
    ///   untagged.arw      keywords NULL
    ///   pct.arw           filename `100%_shot.ARW`
    ///   quote.arw         filename `it's a photo.ARW`
    ///   iso400.arw        iso 400, focal 50, capture 1.7e9, make Canon
    private static func seedFixture(on handle: SQLiteHandle) throws {
        let insert = try handle.prepare("""
            INSERT INTO images (
              path, dir, filename, rating, color_label, keywords, flag,
              camera_make, iso, focal_length, capture_date, has_edits,
              orphan_sidecar
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """)
        struct Row {
            var path: String
            var dir = ""
            var filename: String { (path as NSString).lastPathComponent }
            var rating: Int64?
            var colorLabel: Int64?
            var keywords: String?
            var flag: Int64?
            var make: String?
            var iso: Int64?
            var focal: Double?
            var capture: Double?
        }
        let rows: [Row] = [
            Row(path: "nature-rose.arw", dir: "Capture", rating: 3,
                keywords: "Nature|Flower|Rose"),
            Row(path: "nature-tree.arw", dir: "Capture", rating: 2,
                keywords: "Nature|Tree"),
            Row(path: "natureholics.arw", dir: "Capture", rating: 4,
                keywords: "NatureHolics"),
            Row(path: "nature.arw", dir: "Capture", rating: 1, keywords: "Nature"),
            Row(path: "cleared.arw", dir: "Capture", keywords: "", flag: 1),
            Row(path: "untagged.arw", dir: "Capture"),
            Row(path: "Capture/100%_shot.ARW", dir: "Capture"),
            Row(path: "Capture/it's a photo.ARW", dir: "Capture"),
            Row(path: "iso400.arw", dir: "Capture", make: "Canon", iso: 400,
                focal: 50, capture: 1_700_000_000),
        ]
        for row in rows {
            try insert.bindText(1, row.path)
            try insert.bindText(2, row.dir.isEmpty ? nil : row.dir)
            try insert.bindText(3, row.filename)
            try insert.bindInt(4, row.rating)
            try insert.bindInt(5, row.colorLabel)
            try insert.bindText(6, row.keywords)
            try insert.bindInt(7, row.flag)
            try insert.bindText(8, row.make)
            try insert.bindInt(9, row.iso)
            try insert.bindDouble(10, row.focal)
            try insert.bindDouble(11, row.capture)
            try insert.bindInt(12, 0)
            _ = try insert.step()
            try insert.reset()
        }
    }

    /// Run a translated query against the fixture, return the sorted path
    /// set (the L020 face — exact, content-level).
    private func fixturePaths(_ group: FilterPredicateGroup) throws -> [String] {
        let q = try FilterSQL.translate(group: group)
        let statement = try handle.prepare("SELECT path FROM images WHERE \(q.whereClause)")
        for (index, bind) in q.binds.enumerated() {
            let i = Int32(index + 1)
            switch bind {
            case .text(let value): try statement.bindText(i, value)
            case .int(let value): try statement.bindInt(i, value)
            case .double(let value): try statement.bindDouble(i, value)
            }
        }
        var paths: [String] = []
        while try statement.step() {
            paths.append(statement.columnText(0) ?? "")
        }
        return paths.sorted()
    }

    func testFourClauseExactHitSet() throws {
        // Bare `LIKE '%Nature%'` WOULD hit natureholics.arw (the substring
        // sibling — the F3 mis-hit); the four-clause must return EXACTLY
        // the ancestor-closure set.
        let hits = try fixturePaths(
            .init(rules: [.init(field: .keywords, op: .contains, value: .text("Nature"))]))
        XCTAssertEqual(hits, ["nature-rose.arw", "nature-tree.arw", "nature.arw"])
    }

    /// The CONTROL GROUP the plan pins by name: the BARE substring LIKE
    /// (CONTEXT D-3's original form) DOES hit the `NatureHolics` sibling on
    /// this same fixture — the four-clause is the amendment that must not.
    func testBareLikeControlGroupMisHit() throws {
        let statement = try handle.prepare(
            "SELECT path FROM images WHERE keywords LIKE '%' || ? || '%'")
        try statement.bindText(1, "Nature")
        var bare: [String] = []
        while try statement.step() {
            bare.append(statement.columnText(0) ?? "")
        }
        XCTAssertEqual(
            bare.sorted(),
            ["nature-rose.arw", "nature-tree.arw", "nature.arw", "natureholics.arw"])
        // The four-clause excludes exactly the mis-hit row.
        let four = try fixturePaths(
            .init(rules: [.init(field: .keywords, op: .contains, value: .text("Nature"))]))
        XCTAssertFalse(four.contains("natureholics.arw"))
        XCTAssertEqual(Set(bare).subtracting(four), ["natureholics.arw"])
    }

    func testFourClauseSubTagHit() throws {
        // 打子隐含父: filtering the mid-path tag finds the leaf-tagged row.
        let hits = try fixturePaths(
            .init(rules: [.init(field: .keywords, op: .contains, value: .text("Nature|Flower"))]))
        XCTAssertEqual(hits, ["nature-rose.arw"])
        // And the leaf tag likewise.
        let leaf = try fixturePaths(
            .init(rules: [.init(field: .keywords, op: .contains, value: .text("Rose"))]))
        XCTAssertEqual(leaf, ["nature-rose.arw"])
    }

    func testKeywordsExactPath() throws {
        let hits = try fixturePaths(
            .init(rules: [.init(field: .keywords, op: .eq, value: .text("Nature"))]))
        XCTAssertEqual(hits, ["nature.arw"])
    }

    func testKeywordsEmptyClassRows() throws {
        let empty = try fixturePaths(
            .init(rules: [.init(field: .keywords, op: .empty, value: .text(""))]))
        // NULL (never tagged) AND '' (cleared) are BOTH the empty class —
        // pct/quote/iso400 ride NULL keywords too (never tagged).
        XCTAssertEqual(
            empty,
            ["cleared.arw", "iso400.arw", "untagged.arw",
             "Capture/100%_shot.ARW", "Capture/it's a photo.ARW"].sorted())

        let notEmpty = try fixturePaths(
            .init(rules: [.init(field: .keywords, op: .notEmpty, value: .text(""))]))
        XCTAssertEqual(
            notEmpty,
            ["nature-rose.arw", "nature-tree.arw", "nature.arw", "natureholics.arw"])
    }

    func testWildcardLiteralFilenameRows() throws {
        // `100%_shot` must match ONLY the literal filename — with LIKE
        // semantics an unescaped `%` would match `100Xshot`, `_` any char.
        let hits = try fixturePaths(
            .init(rules: [.init(field: .filename, op: .contains, value: .text("100%_shot"))]))
        XCTAssertEqual(hits, ["Capture/100%_shot.ARW"])

        // The `_` alone: escaped → literal; the quote filename does not fit.
        let underscore = try fixturePaths(
            .init(rules: [.init(field: .filename, op: .contains, value: .text("%_"))]))
        XCTAssertEqual(underscore, ["Capture/100%_shot.ARW"])
    }

    func testQuoteLiteralFilenameRows() throws {
        let hits = try fixturePaths(
            .init(rules: [.init(field: .filename, op: .contains, value: .text("it's"))]))
        XCTAssertEqual(hits, ["Capture/it's a photo.ARW"])
    }

    func testAndCombinationRows() throws {
        let hits = try fixturePaths(
            .init(
                match: .all,
                rules: [
                    .init(field: .keywords, op: .contains, value: .text("Nature")),
                    .init(field: .rating, op: .gte, value: .int(2)),
                ]))
        XCTAssertEqual(hits, ["nature-rose.arw", "nature-tree.arw"])
    }

    func testAnyCombinationRows() throws {
        let hits = try fixturePaths(
            .init(
                match: .any,
                rules: [
                    .init(field: .rating, op: .gte, value: .int(4)),
                    .init(field: .flag, op: .eq, value: .int(1)),
                ]))
        XCTAssertEqual(hits, ["cleared.arw", "natureholics.arw"])
    }

    func testNullNumericRowsExcluded() throws {
        // Three-valued logic: NULL-rating rows never match `rating >= 1`
        // (the empty-value exclusion face).
        let hits = try fixturePaths(
            .init(rules: [.init(field: .rating, op: .gte, value: .int(1))]))
        XCTAssertEqual(
            hits,
            ["nature-rose.arw", "nature-tree.arw", "nature.arw", "natureholics.arw"].sorted())
    }

    func testExifNumericRows() throws {
        let iso = try fixturePaths(
            .init(rules: [.init(field: .iso, op: .eq, value: .int(400))]))
        XCTAssertEqual(iso, ["iso400.arw"])

        let focal = try fixturePaths(
            .init(rules: [
                .init(field: .focalLength, op: .between, value: .doubleRange(lower: 40, upper: 60)),
            ]))
        XCTAssertEqual(focal, ["iso400.arw"])

        let make = try fixturePaths(
            .init(rules: [.init(field: .cameraMake, op: .contains, value: .text("ano"))]))
        XCTAssertEqual(make, ["iso400.arw"])
    }

    func testEmptyGroupReturnsAllNonOrphanRows() throws {
        let hits = try fixturePaths(.init(rules: []))
        XCTAssertEqual(
            hits,
            [
                "Capture/100%_shot.ARW", "Capture/it's a photo.ARW",
                "cleared.arw", "iso400.arw", "nature-rose.arw", "nature-tree.arw",
                "nature.arw", "natureholics.arw", "untagged.arw",
            ].sorted())
    }
}

// MARK: - Query face (Plan 12-2 T3)

extension FilterSQLTests {

    /// The store-backed fixture: a REAL SessionIndexStore opened over a
    /// session root; the same rows are seeded through the store's own
    /// handle (the test seam) — the query face then runs against them.
    private func makeStoreFixture() async throws -> (SessionIndexStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("filtersql-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        let store = SessionIndexStore(sessionRoot: root)
        // Open with an EMPTY scan (opens the handle + applies the schema
        // idempotently); rows are seeded directly below.
        _ = try await store.reconcile(root: root, scan: Self.emptyStream())
        try await store.withHandleForTesting { handle in
            try Self.seedFixture(on: handle)
        }
        return (store, root)
    }

    private static func emptyStream() -> AsyncStream<SessionScanPage> {
        AsyncStream { $0.finish() }
    }

    func testConjoinedGroupsAndBaselineOnce() async throws {
        // The combinator: chips group AND Quick Filter group, baseline
        // EXACTLY once (no AND-duplication).
        let chips = FilterPredicateGroup(match: .all, rules: [
            .init(field: .rating, op: .gte, value: .int(2)),
        ])
        let quick = FilterPredicateGroup.quickFilter(text: "Nature")
        let combined = try FilterSQL.translateConjoining([chips, quick])
        XCTAssertTrue(combined.whereClause.hasSuffix("AND (orphan_sidecar = 0)"))
        XCTAssertEqual(
            combined.whereClause.components(separatedBy: "orphan_sidecar").count - 1, 1)
        // Semantics on the fixture store: rating>=2 AND (filename OR
        // keywords hits Nature) → nature-rose(3), nature-tree(2),
        // natureholics(4); nature.arw has rating 1 (excluded).
        let (store, root) = try await makeStoreFixture()
        defer {
            Task { await store.close() }
            try? FileManager.default.removeItem(at: root)
        }
        let rows = try await store.query(groups: [chips, quick])
        XCTAssertEqual(
            rows.map(\.path).sorted(),
            ["nature-rose.arw", "nature-tree.arw", "natureholics.arw"])
    }

    func testQueryFaceExactRowSet() async throws {
        let (store, root) = try await makeStoreFixture()
        defer {
            Task { await store.close() }
            try? FileManager.default.removeItem(at: root)
        }
        // The query face must agree with the translation-layer row set on
        // the SAME fixture (SQL snapshot ↔ query cross-validation).
        let rows = try await store.query(
            groups: [.init(rules: [.init(field: .keywords, op: .contains, value: .text("Nature"))])])
        XCTAssertEqual(
            rows.map(\.path),
            ["nature-rose.arw", "nature-tree.arw", "nature.arw"])
        // Orphan rows never surface (the baseline rides the query too).
        let all = try await store.query(groups: [.init(rules: [])])
        XCTAssertTrue(all.allSatisfy { $0.orphanSidecar == 0 })
    }

    func testQuerySortAscDescNullsLast() async throws {
        let (store, root) = try await makeStoreFixture()
        defer {
            Task { await store.close() }
            try? FileManager.default.removeItem(at: root)
        }
        // Ratings: nature 1 / nature-tree 2 / nature-rose 3 / natureholics
        // 4; EVERYTHING else NULL (pct/quote/iso400/cleared/untagged).
        let asc = try await store.query(
            groups: [.init(rules: [])],
            sort: FilterSort(key: .rating, ascending: true))
        XCTAssertEqual(
            asc.prefix(4).map(\.path),
            ["nature.arw", "nature-tree.arw", "nature-rose.arw", "natureholics.arw"])
        XCTAssertEqual(asc.count, 9)
        // NULLs ride LAST in ascending.
        XCTAssertNil(asc.suffix(5).allSatisfy { $0.rating == nil } ? nil : "nonnull-in-tail")

        let desc = try await store.query(
            groups: [.init(rules: [])],
            sort: FilterSort(key: .rating, ascending: false))
        XCTAssertEqual(
            desc.prefix(4).map(\.path),
            ["natureholics.arw", "nature-rose.arw", "nature-tree.arw", "nature.arw"])
        // NULLs ride LAST in DESCENDING too.
        XCTAssertTrue(desc.suffix(5).allSatisfy { $0.rating == nil })

        // capture_date: only iso400.arw carries one — it leads ascending.
        let dates = try await store.query(
            groups: [.init(rules: [])],
            sort: FilterSort(key: .captureDate, ascending: true))
        XCTAssertEqual(dates.first?.path, "iso400.arw")
        XCTAssertTrue(dates.suffix(8).allSatisfy { $0.captureDate == nil })
    }

    func testQueryLimitPagination() async throws {
        let (store, root) = try await makeStoreFixture()
        defer {
            Task { await store.close() }
            try? FileManager.default.removeItem(at: root)
        }
        // LIMIT is bound; the path tiebreaker makes the page deterministic.
        let page = try await store.query(
            groups: [.init(rules: [])],
            sort: FilterSort(key: .filename, ascending: true), limit: 3)
        XCTAssertEqual(page.count, 3)
        XCTAssertEqual(
            page.map(\.path),
            ["Capture/100%_shot.ARW", "cleared.arw", "iso400.arw"])
    }

    func testQueryCoexistsWithWriteTransactions() async throws {
        let (store, root) = try await makeStoreFixture()
        defer {
            Task { await store.close() }
            try? FileManager.default.removeItem(at: root)
        }
        // Concurrency smoke: the read face and the metadata/write faces
        // share the actor's handle — the group runs them interleaved and
        // every leg must succeed (WAL + actor serialization; zero new
        // locking face).
        let group = FilterPredicateGroup(rules: [
            .init(field: .rating, op: .gte, value: .int(1)),
        ])
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask {
                for _ in 0..<20 {
                    _ = try await store.query(groups: [group])
                }
            }
            tasks.addTask {
                let claim = SessionIndexStore.MetadataClaim(
                    relPath: "nature.arw", rating: 5, colorLabel: nil,
                    keywords: nil, flag: nil, note: nil, sidecarMtime: 1)
                for _ in 0..<5 {
                    try await store.claimMetadataApply(claims: [claim])
                }
            }
            tasks.addTask {
                for _ in 0..<5 {
                    _ = try await store.markRowsStale(relPaths: ["nature-tree.arw"])
                }
            }
            try await tasks.waitForAll()
        }
        // The query still answers after the interleaving.
        let rows = try await store.query(groups: [group])
        XCTAssertEqual(rows.count, 4)
    }
}
