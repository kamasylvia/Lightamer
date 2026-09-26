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
// Fixtures in FileManager.temporaryDirectory (L009: never UNITEK).
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
}
