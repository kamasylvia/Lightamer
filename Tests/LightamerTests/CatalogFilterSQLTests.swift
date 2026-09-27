import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 16-1 T3 (+T4 store keyset suite in the later segment) — the FilterSQL
// domain dispatch:
//
//   • SESSION REGRESSION LOCK: the default-parameter call sites translate
//     BYTE-IDENTICALLY to the frozen 12-2 output (four-clause keywords,
//     baseline, conjoining) — zero drift allowed in the existing domain
//   • CATALOG SHAPES: keywords → the equality EXISTS over image_tags (one
//     bind per tag, alias `i` contract), every non-sorting term carries the
//     `+` unary prefix (F10), the baseline becomes (+i.orphan_sidecar = 0),
//     filename/dir contains downgrade to startsWith (RQ-16-16①)
//   • bind-count/order alignment for both keywords shapes
//   • orderBySQL(domain:) — catalog ties off with rel_path ASC, spelled
//     verbatim like the expression indexes (F6)
//   • scopeClause: session/category/collection anchors, AND-combined,
//     all-nil → (1=1)
//   • EXPLAIN QUERY PLAN on a 10k fixture: the keyset main segment walks
//     the ordering index with ZERO TEMP B-TREE (F6/F10 shape lock)
//
// Fixtures in FileManager.temporaryDirectory (L009: never external volume).
// ─────────────────────────────────────────────────────────────────────────────

final class CatalogFilterSQLTests: XCTestCase {

    private var tempDirectory: URL!
    private var catalogURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-filter-\(UUID().uuidString)", isDirectory: true)
        catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Session regression lock (byte-identical to 12-2)

    func testSessionDomainRegressionLock() throws {
        // The DEFAULT parameters must reproduce the frozen 12-2 output.
        let q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .rating, op: .gte, value: .int(3))]))
        XCTAssertEqual(q.whereClause, "(rating >= ?) AND (orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.int(3)])

        let four = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .keywords, op: .contains, value: .text("Nature")),
            ]))
        XCTAssertEqual(
            four.whereClause,
            "(keywords = ? OR keywords LIKE ? || '|%' ESCAPE '\\' "
                + "OR keywords LIKE '%|' || ? || '|%' ESCAPE '\\' "
                + "OR keywords LIKE '%|' || ? ESCAPE '\\') AND (orphan_sidecar = 0)")
        XCTAssertEqual(four.binds.count, 4)

        let conjoined = try FilterSQL.translateConjoining([
            .init(rules: [.init(field: .rating, op: .gte, value: .int(3))]),
            .init(rules: [.init(field: .filename, op: .contains, value: .text("a"))]),
        ])
        XCTAssertEqual(
            conjoined.whereClause,
            "((rating >= ?)) AND ((filename LIKE '%' || ? || '%' ESCAPE '\\')) "
                + "AND (orphan_sidecar = 0)")
        // The explicit .session form is the SAME product.
        let explicit = try FilterSQL.translateConjoining(
            [.init(rules: [.init(field: .rating, op: .gte, value: .int(3))])],
            domain: .session)
        XCTAssertEqual(
            explicit.whereClause, "((rating >= ?)) AND (orphan_sidecar = 0)")
    }

    // MARK: - Catalog shapes (+ prefix, EXISTS, baseline)

    func testCatalogNumericAndTextShapes() throws {
        // rating gte — the `+` prefix + `i` alias + catalog baseline.
        let q = try FilterSQL.translate(
            group: .init(rules: [.init(field: .rating, op: .gte, value: .int(4))]),
            domain: .catalog)
        XCTAssertEqual(
            q.whereClause, "(+i.rating >= ?) AND (+i.orphan_sidecar = 0)")
        XCTAssertEqual(q.binds, [.int(4)])

        // IN list / BETWEEN ride the prefix too.
        let inList = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .colorLabel, op: .in, value: .intList([0, 3])),
            ]), domain: .catalog)
        XCTAssertEqual(
            inList.whereClause,
            "(+i.color_label IN (?, ?)) AND (+i.orphan_sidecar = 0)")
        let between = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .captureDate, op: .between,
                      value: .doubleRange(lower: 1, upper: 2)),
            ]), domain: .catalog)
        XCTAssertEqual(
            between.whereClause,
            "(+i.capture_date BETWEEN ? AND ?) AND (+i.orphan_sidecar = 0)")

        // Text eq keeps its shape with the prefix; note keeps CONTAINS
        // (only filename/dir downgrade — execution decision).
        let camera = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .cameraModel, op: .eq, value: .text("A7R V")),
            ]), domain: .catalog)
        XCTAssertEqual(
            camera.whereClause, "(+i.camera_model = ?) AND (+i.orphan_sidecar = 0)")
        let note = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .note, op: .contains, value: .text("keep")),
            ]), domain: .catalog)
        XCTAssertEqual(
            note.whereClause,
            "(+i.note LIKE '%' || ? || '%' ESCAPE '\\') AND (+i.orphan_sidecar = 0)")
    }

    func testCatalogFilenameDirContainsDowngradesToStartsWith() throws {
        for field in [FilterField.filename, .dir] {
            let q = try FilterSQL.translate(
                group: .init(rules: [
                    .init(field: field, op: .contains, value: .text("2026%good")),
                ]), domain: .catalog)
            XCTAssertEqual(
                q.whereClause,
                "(+i.\(field == .filename ? "filename" : "dir") LIKE ? || '%' ESCAPE '\\') "
                    + "AND (+i.orphan_sidecar = 0)",
                "\(field) contains must downgrade to startsWith")
            XCTAssertEqual(q.binds, [.text("2026\\%good")], "LIKE metachars escaped")
        }
    }

    func testCatalogKeywordsExistsTemplate() throws {
        // contains → ONE equality EXISTS (no ESCAPE/LIKE — materialized).
        let contains = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .keywords, op: .contains, value: .text("Nature")),
            ]), domain: .catalog)
        XCTAssertEqual(
            contains.whereClause,
            "((EXISTS (SELECT 1 FROM image_tags t WHERE t.tag = ? "
                + "AND t.catalog_image_id = i.id))) AND (+i.orphan_sidecar = 0)")
        XCTAssertEqual(contains.binds, [.text("Nature")],
                       "one bind per tag — raw equality, no escapeLike")

        // in → any-of EXISTS; eq → the SAME EXISTS shape (the materialized
        // full path IS a tag row).
        let any = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .keywords, op: .in, value: .textList(["A", "B|C"])),
            ]), domain: .catalog)
        XCTAssertEqual(
            any.whereClause,
            "((EXISTS (SELECT 1 FROM image_tags t WHERE t.tag = ? "
                + "AND t.catalog_image_id = i.id)) "
                + "OR (EXISTS (SELECT 1 FROM image_tags t WHERE t.tag = ? "
                + "AND t.catalog_image_id = i.id))) AND (+i.orphan_sidecar = 0)")
        XCTAssertEqual(any.binds, [.text("A"), .text("B|C")])

        let eq = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .keywords, op: .eq, value: .text("A|B|C")),
            ]), domain: .catalog)
        XCTAssertEqual(
            eq.whereClause,
            "((EXISTS (SELECT 1 FROM image_tags t WHERE t.tag = ? "
                + "AND t.catalog_image_id = i.id))) AND (+i.orphan_sidecar = 0)")

        // empty/notEmpty consume the mirrored keywords column.
        let empty = try FilterSQL.translate(
            group: .init(rules: [
                .init(field: .keywords, op: .empty, value: .text("")),
            ]), domain: .catalog)
        XCTAssertEqual(
            empty.whereClause,
            "(+i.keywords IS NULL OR +i.keywords = '') AND (+i.orphan_sidecar = 0)")
    }

    // MARK: - orderBySQL domain dispatch

    func testOrderBySQLDomainDispatch() {
        let desc = FilterSort(key: .captureDate, ascending: false)
        XCTAssertEqual(
            desc.orderBySQL(domain: .session),
            "(capture_date IS NULL), capture_date DESC, path ASC")
        // VERBATIM index alignment (idx_cat_cd_desc: capture_date IS NULL,
        // capture_date DESC, rel_path).
        XCTAssertEqual(
            desc.orderBySQL(domain: .catalog),
            "(capture_date IS NULL), capture_date DESC, rel_path ASC")
        let asc = FilterSort(key: .captureDate, ascending: true)
        XCTAssertEqual(
            asc.orderBySQL(domain: .catalog),
            "(capture_date IS NULL), capture_date ASC, rel_path ASC")
        XCTAssertEqual(
            FilterSort(key: .rating, ascending: false).orderBySQL(domain: .catalog),
            "(rating IS NULL), rating DESC, rel_path ASC")
        XCTAssertEqual(
            FilterSort(key: .filename, ascending: true).orderBySQL(domain: .catalog),
            "(filename IS NULL), filename ASC, rel_path ASC")
    }

    // MARK: - scopeClause anchors

    func testScopeClauseAnchors() {
        let all = FilterSQL.scopeClause()
        XCTAssertEqual(all.sql, "(1=1)")
        XCTAssertTrue(all.binds.isEmpty)

        let session = FilterSQL.scopeClause(sessionID: "sid-1")
        XCTAssertEqual(session.sql, "((i.session_id = ?))")
        XCTAssertEqual(session.binds, [.text("sid-1")])

        let category = FilterSQL.scopeClause(categoryID: 42)
        XCTAssertEqual(
            category.sql,
            "((EXISTS (SELECT 1 FROM image_categories ic "
                + "WHERE ic.category_id = ? AND ic.catalog_image_id = i.id)))")
        XCTAssertEqual(category.binds, [.int(42)])

        let collection = FilterSQL.scopeClause(collectionID: 7)
        XCTAssertEqual(
            collection.sql,
            "((EXISTS (SELECT 1 FROM image_collections co "
                + "WHERE co.collection_id = ? AND co.catalog_image_id = i.id)))")
        XCTAssertEqual(collection.binds, [.int(7)])

        // Multiple anchors AND-combine, binds in clause order.
        let combo = FilterSQL.scopeClause(sessionID: "s", categoryID: 3)
        XCTAssertEqual(combo.sql, "((i.session_id = ?) AND (EXISTS (SELECT 1 "
            + "FROM image_categories ic WHERE ic.category_id = ? "
            + "AND ic.catalog_image_id = i.id)))")
        XCTAssertEqual(combo.binds, [.text("s"), .int(3)])
    }

    // MARK: - EXPLAIN plan (10k fixture, F6/F10 shape lock)

    /// Bulk-seed `n` rows (batched prepared loop — the PERF-07 shape).
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
            try insert.bindInt(10, 0)
            try insert.bindText(11, nil)
            try insert.bindInt(12, nil)
            try insert.bindText(13, nil)
            try insert.bindInt(14, 1)
            try insert.bindInt(15, 100)
            try insert.bindInt(16, 100)
            // 10% NULL capture_date (the harness NULL profile).
            if i % 10 == 0 {
                try insert.bindDouble(17, nil)
            } else {
                try insert.bindDouble(17, 1_700_000_000 + Double(i % 86_400))
            }
            // 60% NULL rating.
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

    /// EXPLAIN QUERY PLAN details for a fully-spelled keyset main segment.
    private func explain(_ sql: String, _ binds: [FilterSQLBind]) throws -> [String] {
        try seedCatalog(n: 10_000)
        let handle = try SQLiteHandle(path: catalogURL.path)
        defer { handle.close() }
        let statement = try handle.prepare("EXPLAIN QUERY PLAN \(sql)")
        try FilterSQL.apply(binds, to: statement)
        var details: [String] = []
        while try statement.step() {
            details.append(statement.columnText(3) ?? "")
        }
        return details
    }

    private func keysetMainSQL(sort: FilterSort) -> (sql: String, binds: [FilterSQLBind]) {
        let filtered = try! FilterSQL.translate(
            group: .init(rules: [
                .init(field: .rating, op: .gte, value: .int(4)),
            ]), domain: .catalog)
        let scope = FilterSQL.scopeClause()
        let sql = """
            SELECT id FROM catalog_images i
            WHERE \(filtered.whereClause) AND \(scope.sql)
              AND (+i.capture_date, +i.rel_path) < (?, ?)
            ORDER BY \(sort.orderBySQL(domain: .catalog)) LIMIT 60
            """
        var binds = filtered.binds
        binds.append(contentsOf: scope.binds)
        binds.append(contentsOf: [.double(1_700_086_400), .text("dir0030/img000700.arw")])
        return (sql, binds)
    }

    func testExplainKeysetDateDescZeroTempBTree() throws {
        let (sql, binds) = keysetMainSQL(
            sort: FilterSort(key: .captureDate, ascending: false))
        let details = try explain(sql, binds)
        for detail in details {
            XCTAssertFalse(
                detail.contains("TEMP B-TREE"),
                "F10/F6 shape regression: \(details)")
        }
        XCTAssertTrue(
            details.contains { $0.contains("idx_cat_cd_desc") },
            "the DESC ordering index must lead: \(details)")
    }

    func testExplainUntaggedQueryLeavesTagsTableOut() throws {
        // EXISTS short-circuit: a query WITHOUT a keywords predicate never
        // mentions image_tags (the shape dispatch injects per need).
        let (sql, _) = keysetMainSQL(
            sort: FilterSort(key: .captureDate, ascending: false))
        let details = try explain(sql, [])
        XCTAssertFalse(
            details.joined().contains("image_tags"),
            "no tags join without a keywords predicate: \(details)")
    }

    func testExplainDescExpandedSeekZeroTempBTree() throws {
        // The DESC keyset seek expands over the ASC tiebreak — the plan
        // must still walk idx_cat_rt_desc with ZERO TEMP B-TREE.
        try seedCatalog(n: 10_000)
        let handle = try SQLiteHandle(path: catalogURL.path)
        defer { handle.close() }
        let sql = """
            SELECT id FROM catalog_images i
            WHERE (+i.orphan_sidecar = 0)
              AND (i.rating < ? OR (i.rating = ? AND i.rel_path > ?))
            ORDER BY (rating IS NULL), rating DESC, rel_path ASC LIMIT 60
            """
        let statement = try handle.prepare("EXPLAIN QUERY PLAN \(sql)")
        try statement.bindInt(1, 3)
        try statement.bindInt(2, 3)
        try statement.bindText(3, "dir0000/img000500.arw")
        var details: [String] = []
        while try statement.step() {
            details.append(statement.columnText(3) ?? "")
        }
        for detail in details {
            XCTAssertFalse(detail.contains("TEMP B-TREE"), "\(details)")
        }
        XCTAssertTrue(
            details.contains { $0.contains("idx_cat_rt_desc") },
            "the DESC ordering index must serve the expanded seek: \(details)")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plan 16-1 T4 segment — the CatalogIndexStore keyset face:
//
//   • keyset pages across ALL shapes (4 sort keys × directions × 3 depths,
//     10k fixture) match a single big LIMIT query ROW FOR ROW — no gap, no
//     overlap, no drift at the page boundaries
//   • the NULL tail continues the main segment seamlessly (disjoint sets,
//     together == the whole library)
//   • COUNT: simple predicates recompute EVERY time (§1.4 on-request
//     class), combo predicates memoize after the first computation, and
//     invalidateCounts() kills the memo
//   • tagCounts() = the one-sweep batch dictionary; fetchRow/imageIDs
//   • unsupported sort keys are a typed error (never a silent slow plan)
// ─────────────────────────────────────────────────────────────────────────────

extension CatalogFilterSQLTests {

    private func makeStore() -> CatalogIndexStore {
        CatalogIndexStore(databaseURL: catalogURL)
    }

    private func anchorValue(
        _ row: CatalogIndexRow, key: FilterSortKey
    ) -> FilterSQLBind? {
        switch key {
        case .captureDate: row.captureDate.map { FilterSQLBind.double($0) }
        case .rating: row.rating.map { .int($0) }
        case .filename: row.filename.map { .text($0) }
        default: nil
        }
    }

    /// Walk `pages` keyset pages, returning the visited rel_paths IN ORDER
    /// plus the anchor at the walk's end.
    private func walkMain(
        _ store: CatalogIndexStore, groups: [FilterPredicateGroup],
        sort: FilterSort, pages: Int
    ) async throws -> (visited: [String], lastAnchor: CatalogPageAnchor?) {
        var visited: [String] = []
        var anchor: CatalogPageAnchor?
        for _ in 0..<max(pages, 1) {
            let rows = try await store.queryPage(
                groups: groups, sort: sort, anchor: anchor)
            guard let last = rows.last else { break }
            visited.append(contentsOf: rows.map(\.relPath))
            guard let kv = anchorValue(last, key: sort.key) else { break }
            anchor = CatalogPageAnchor(keyValue: kv, relPath: last.relPath)
            if rows.count < CatalogIndexStore.defaultPageSize { break }
        }
        return (visited, anchor)
    }

    private func referenceOrder(
        _ sort: FilterSort, limit: Int
    ) async throws -> [String] {
        let store = makeStore()
        var paths: [String] = []
        try await store.withHandleForTesting { handle in
            let statement = try handle.prepare(
                "SELECT rel_path FROM catalog_images i WHERE +i.orphan_sidecar = 0 "
                    + "ORDER BY \(sort.orderBySQL(domain: .catalog)) LIMIT ?")
            try statement.bindInt(1, Int64(limit))
            while try statement.step() {
                paths.append(statement.columnText(0) ?? "")
            }
        }
        return paths
    }

    private func seedTagsForSuite() async throws {
        let store = makeStore()
        try await store.withHandleForTesting { handle in
            try handle.execute(
                "INSERT OR IGNORE INTO image_tags (tag, catalog_image_id) "
                    + "SELECT 'Nature', id FROM catalog_images WHERE id % 10 = 0")
            try handle.execute(
                "INSERT OR IGNORE INTO image_tags (tag, catalog_image_id) "
                    + "SELECT 'City', id FROM catalog_images WHERE id % 25 = 0")
        }
    }

    // MARK: - Keyset ordering, all shapes × depths (row-for-row vs reference)

    func testKeysetPagesMatchReferenceAcrossShapesAndDepths() async throws {
        try seedCatalog(n: 10_000)
        let store = makeStore()
        let noGroups: [FilterPredicateGroup] = []

        let shapes: [FilterSort] = [
            FilterSort(key: .captureDate, ascending: false),
            FilterSort(key: .captureDate, ascending: true),
            FilterSort(key: .rating, ascending: false),
            FilterSort(key: .rating, ascending: true),
            FilterSort(key: .filename, ascending: true),
        ]
        // Depths 0 (head), 4000 (40%), 8000 (80%) of the 10k fixture.
        for sort in shapes {
            for depth in [0, 4000, 8000] {
                let pages = max(1, depth / CatalogIndexStore.defaultPageSize)
                let walk = try await walkMain(
                    store, groups: noGroups, sort: sort, pages: pages)
                XCTAssertGreaterThanOrEqual(
                    walk.visited.count, min(10_000, pages * 60),
                    "anti-vacuous: the walk must actually visit rows")
                let expected = try await referenceOrder(
                    sort, limit: min(walk.visited.count, 60 * pages + 60))
                XCTAssertEqual(
                    walk.visited, Array(expected.prefix(walk.visited.count)),
                    "\(sort.key) \(sort.ascending ? "ASC" : "DESC") @d\(depth): "
                        + "keyset pages must equal the single-query order")
                // Strictly no duplicates across page boundaries.
                XCTAssertEqual(
                    Set(walk.visited).count, walk.visited.count,
                    "duplicate rows across pages")
            }
        }
    }

    func testKeysetWithFilterAndTagPredicates() async throws {
        try seedCatalog(n: 10_000)
        try await seedTagsForSuite()
        let store = makeStore()
        let tagGroup = FilterPredicateGroup(rules: [
            .init(field: .keywords, op: .contains, value: .text("Nature")),
        ])
        let sort = FilterSort(key: .captureDate, ascending: false)
        // Walk 5 pages of the tag-filtered set — page boundaries hold.
        let walk = try await walkMain(store, groups: [tagGroup], sort: sort, pages: 5)
        XCTAssertFalse(walk.visited.isEmpty)
        XCTAssertEqual(Set(walk.visited).count, walk.visited.count)
        // The filtered reference must match row-for-row.
        var expected: [String] = []
        try await store.withHandleForTesting { handle in
            let q = try FilterSQL.translateConjoining([tagGroup], domain: .catalog)
            let scope = FilterSQL.scopeClause()
            let statement = try handle.prepare(
                "SELECT rel_path FROM catalog_images i WHERE \(q.whereClause) "
                    + "AND \(scope.sql) ORDER BY \(sort.orderBySQL(domain: .catalog)) LIMIT 300")
            try FilterSQL.apply(q.binds, to: statement)
            while try statement.step() {
                expected.append(statement.columnText(0) ?? "")
            }
        }
        XCTAssertEqual(walk.visited, Array(expected.prefix(walk.visited.count)))
    }

    // MARK: - NULL tail seam

    func testNullTailContinuesMainSeamlessly() async throws {
        try seedCatalog(n: 10_000)  // 10% NULL capture_date, 20% NULL rating
        let store = makeStore()
        let sort = FilterSort(key: .rating, ascending: false)

        // Exhaust the main segment.
        var mainRows: [String] = []
        var anchor: CatalogPageAnchor?
        while true {
            let rows = try await store.queryPage(
                groups: [], sort: sort, anchor: anchor)
            guard !rows.isEmpty else { break }
            mainRows.append(contentsOf: rows.map(\.relPath))
            guard let last = rows.last, let kv = anchorValue(last, key: sort.key) else {
                break
            }
            anchor = CatalogPageAnchor(keyValue: kv, relPath: last.relPath)
            if rows.count < CatalogIndexStore.defaultPageSize { break }
        }

        // Walk the NULL tail from its head.
        var tailRows: [String] = []
        var tailAnchor: CatalogPageAnchor?
        while true {
            let rows = try await store.queryNullTail(
                groups: [], sort: sort, anchor: tailAnchor)
            guard !rows.isEmpty else { break }
            tailRows.append(contentsOf: rows.map(\.relPath))
            guard let last = rows.last else { break }
            tailAnchor = CatalogPageAnchor(keyValue: .int(nil), relPath: last.relPath)
            if rows.count < CatalogIndexStore.defaultPageSize { break }
        }

        // Disjoint halves; together they are the whole library.
        let overlap = Set(mainRows).intersection(tailRows)
        XCTAssertTrue(overlap.isEmpty, "main and tail must not overlap")
        var total = 0
        try await store.withHandleForTesting { handle in
            let statement = try handle.prepare("SELECT COUNT(*) FROM catalog_images")
            if try statement.step() { total = Int(statement.columnInt(0) ?? 0) }
        }
        XCTAssertEqual(mainRows.count + tailRows.count, total)
        // Every main-segment row HAS a rating; every tail row is NULL.
        let firstTail = try await store.queryNullTail(groups: [], sort: sort)
        XCTAssertTrue(firstTail.allSatisfy { $0.rating == nil })
        let firstMain = try await store.queryPage(groups: [], sort: sort)
        XCTAssertTrue(firstMain.allSatisfy { $0.rating != nil })
    }

    // MARK: - COUNT face (§1.4)

    func testCountSimpleRecomputesAndComboMemoizes() async throws {
        try seedCatalog(n: 10_000)
        let store = makeStore()
        let counter = CounterBox()
        await store.setCountObserver { counter.increment() }

        // Simple (single field, no tag): every call recomputes.
        let simple = [FilterPredicateGroup(rules: [
            .init(field: .rating, op: .gte, value: .int(4)),
        ])]
        _ = try await store.count(groups: simple)
        _ = try await store.count(groups: simple)
        XCTAssertEqual(counter.value, 2, "simple predicates recompute on request")

        // Combo (two rules): first computes, second hits the memo.
        let combo = [FilterPredicateGroup(rules: [
            .init(field: .rating, op: .gte, value: .int(4)),
            .init(field: .captureDate, op: .gte, value: .double(1_700_000_000)),
        ])]
        _ = try await store.count(groups: combo)
        _ = try await store.count(groups: combo)
        XCTAssertEqual(counter.value, 3, "combo predicate memoizes after one compute")

        // invalidateCounts() kills the memo.
        await store.invalidateCounts()
        _ = try await store.count(groups: combo)
        XCTAssertEqual(counter.value, 4, "invalidation forces a recompute")

        // The empty group (all-library COUNT(*)) is the simple class.
        _ = try await store.count(groups: [])
        XCTAssertEqual(counter.value, 5)
    }

    func testTagCountsBatchAndRowReads() async throws {
        try seedCatalog(n: 10_000)
        try await seedTagsForSuite()
        let store = makeStore()
        let counts = try await store.tagCounts()
        XCTAssertEqual(counts["Nature"], 1000)
        XCTAssertEqual(counts["City"], 400)

        // i = 1000: dir 1000 % 40 = 0, session 1000 % 10 = 0.
        let row = try await store.fetchRow(
            sessionID: "sess-0", relPath: "dir0000/img001000.arw")
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.sessionID, "sess-0")
        XCTAssertEqual(row?.relPath, "dir0000/img001000.arw")
        let ids = try await store.imageIDs(
            sessionID: "sess-0",
            relPaths: ["dir0000/img001000.arw", "missing.arw"])
        XCTAssertEqual(ids.count, 1)
        XCTAssertGreaterThan(ids["dir0000/img001000.arw"] ?? 0, 0)
    }

    func testUnsupportedSortKeyThrowsTypedError() async throws {
        try seedCatalog(n: 100)
        let store = makeStore()
        do {
            _ = try await store.queryPage(
                groups: [], sort: FilterSort(key: .iso, ascending: true))
            XCTFail("expected the typed unsupported-sort error")
        } catch let error as SessionIndexError {
            guard case .execFailed(_, _, let message) = error else {
                return XCTFail("expected execFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("no catalog ordering index"), message)
        }
        // scan_epoch is not even mirrored.
        do {
            _ = try await store.queryPage(
                groups: [], sort: FilterSort(key: .scanEpoch, ascending: true))
            XCTFail("expected the typed unsupported-sort error")
        } catch { /* expected */ }
    }
}

/// A tiny Sendable counter for the count-observer assertions.
private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock(); count += 1; lock.unlock()
    }
}
