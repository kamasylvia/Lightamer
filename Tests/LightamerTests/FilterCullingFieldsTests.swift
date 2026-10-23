import CoreGraphics
import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FilterCullingFieldsTests (Plan LUMEN-A T7, X5/reviews m-6/m-11) — the smart
// album culling quartet + the badge model:
//
//   ① the .library direct-compare integration: createAlbum(filterGroup:)
//      over the灌注 analysed rows — sharpness/faces/eyesClosed hit and
//      miss, NULL rows never match (the un-analysed default-neutral face)
//   ② hasBurst = the typed not-SQL-queryable arm in EVERY domain
//   ③ the .session/.catalog domain typed-unsupported negative (review
//      m-11 — no SQL generates for the quartet outside .library)
//   ④ the FilterSQL whitelist stays closed (no new sort keys; the quartet's
//      column spellings == the DDL names)
//   ⑤ the badge mapper (review m-6): annotation+row → badge payload
//      (table-driven; zero annotations = the empty map) + the burst-stack
//      members payload
// ─────────────────────────────────────────────────────────────────────────────

final class FilterCullingFieldsTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: ProjectFileStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("filter-culling-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        store = ProjectFileStore(at: tempDirectory.appendingPathComponent("CullFilter.lalb"))
        _ = try await store.create(name: "CullFilter")
    }

    override func tearDown() async throws {
        try? await store.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// Insert one images row with the analysis products in place.
    private func insertAnalysed(
        path: String, sharpness: Double?, faces: Int?, eyesClosed: Int?
    ) async throws -> Int64 {
        try await store.withWriteBatch { handle in
            let insert = try handle.prepare(
                "INSERT INTO images (image_path, path_kind, analysis_version,"
                    + " sharpness, faces, eyes_closed) VALUES (?, 0, 1, ?, ?, ?)")
            try insert.bindText(1, path)
            try insert.bindDouble(2, sharpness)
            try insert.bindInt(3, faces.map(Int64.init))
            try insert.bindInt(4, eyesClosed.map(Int64.init))
            _ = try insert.step()
            return handle.lastInsertRowID()
        }
    }

    /// Evaluate the group against the library rows (the smart-album match
    /// semantics: translate + query, count the hits).
    private func evaluate(_ group: FilterPredicateGroup) async throws -> [Int64] {
        let query = try FilterSQL.translate(group: group, domain: .library)
        return try await store.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT id FROM images i WHERE "
                    + query.whereClause + " ORDER BY id")
            try FilterSQL.apply(query.binds, to: statement)
            var ids: [Int64] = []
            while try statement.step() {
                ids.append(statement.columnInt(0) ?? 0)
            }
            return ids
        }
    }

    // MARK: - ① The .library direct-compare integration

    func testLibraryDirectCompareHitMissAndNULLSemantics() async throws {
        // Rows: A = analysed (30.0/2/0 closed), B = analysed (80/0/1),
        // C = un-analysed (all NULL).
        let idA = try await insertAnalysed(
            path: "Media/a.jpg", sharpness: 30, faces: 2, eyesClosed: 0)
        let idB = try await insertAnalysed(
            path: "Media/b.jpg", sharpness: 80, faces: 0, eyesClosed: 1)
        _ = try await insertAnalysed(
            path: "Media/c.jpg", sharpness: nil, faces: nil, eyesClosed: nil)

        // createAlbum(filterGroup:) — the persisted smart-album face accepts
        // the three pure-SQL culling fields (the store validates first).
        let library = LibraryStore(store: store)
        _ = try await library.createAlbum(
            kind: .filter, name: "blurry",
            filterGroup: FilterPredicateGroup(rules: [
                .init(field: .sharpness, op: .lt, value: .double(50))
            ]))

        // sharpness lt 50: hits A only — B misses, C (NULL) never matches.
        var hits = try await evaluate(FilterPredicateGroup(rules: [
            .init(field: .sharpness, op: .lt, value: .double(50))
        ]))
        XCTAssertEqual(hits, [idA])
        hits = try await evaluate(FilterPredicateGroup(rules: [
            .init(field: .sharpness, op: .gte, value: .double(50))
        ]))
        XCTAssertEqual(hits, [idB], "NULL rows never hit a direct compare")

        // faces eq 2 / gt 0.
        hits = try await evaluate(FilterPredicateGroup(rules: [
            .init(field: .faces, op: .eq, value: .int(2))
        ]))
        XCTAssertEqual(hits, [idA])
        hits = try await evaluate(FilterPredicateGroup(rules: [
            .init(field: .faces, op: .gt, value: .int(0))
        ]))
        XCTAssertEqual(hits, [idA])

        // eyesClosed eq 1 (the absolute-hint bucket).
        hits = try await evaluate(FilterPredicateGroup(rules: [
            .init(field: .eyesClosed, op: .eq, value: .int(1))
        ]))
        XCTAssertEqual(hits, [idB])
    }

    // MARK: - ②③ The typed arms (hasBurst + the domain gate)

    func testHasBurstTypedNotSQLQueryableInEveryDomain() throws {
        let group = FilterPredicateGroup(rules: [
            .init(field: .hasBurst, op: .eq, value: .int(1))
        ])
        for domain in [FilterDomain.library, .session, .catalog] {
            XCTAssertThrowsError(
                try FilterSQL.translate(group: group, domain: domain)
            ) { error in
                guard case FilterPredicateError.cullingFieldNotSQLQueryable = error
                else {
                    return XCTFail("expected cullingFieldNotSQLQueryable for \(domain)")
                }
            }
        }
    }

    func testCullingFieldsTypedUnsupportedOutsideLibraryDomain() throws {
        let group = FilterPredicateGroup(rules: [
            .init(field: .sharpness, op: .lt, value: .double(50))
        ])
        for domain in [FilterDomain.session, .catalog] {
            XCTAssertThrowsError(
                try FilterSQL.translate(group: group, domain: domain)
            ) { error in
                guard case FilterPredicateError.cullingFieldUnsupportedInDomain(
                    let field, let thrownDomain) = error else {
                    return XCTFail("expected cullingFieldUnsupportedInDomain")
                }
                XCTAssertEqual(field, .sharpness)
                XCTAssertEqual(thrownDomain, domain)
            }
        }
        // The .library domain translates (the negative of the negative).
        XCTAssertNoThrow(try FilterSQL.translate(group: group, domain: .library))
    }

    // MARK: - ④ The whitelist faces stay closed

    func testSortWhitelistAndColumnSpellings() throws {
        // No new sort keys (the ORDER BY whitelist untouched — the batch
        // red line: the sort face is not in the four-case scope).
        XCTAssertEqual(FilterSortKey.allCases.count, 6)
        // The quartet's column spellings == the v6 DDL names.
        let sqlGroup = FilterPredicateGroup(rules: [
            .init(field: .sharpness, op: .eq, value: .double(50)),
            .init(field: .faces, op: .eq, value: .int(1)),
            .init(field: .eyesClosed, op: .eq, value: .int(0)),
        ])
        let product = try FilterSQL.translate(group: sqlGroup, domain: .library)
        XCTAssertTrue(product.whereClause.contains("+i.sharpness = ?"))
        XCTAssertTrue(product.whereClause.contains("+i.faces = ?"))
        XCTAssertTrue(product.whereClause.contains("+i.eyes_closed = ?"))
    }

    // MARK: - ⑤ The badge mapper (review m-6)

    func testCullingBadgeMapperTableDriven() {
        let s1 = Data(repeating: 7, count: 256)
        let rows: [BurstRow] = [
            BurstRow(
                imageID: 1, make: nil, model: nil, serial: nil,
                capturedTS: 100, signature: s1, eyesRatio: 0.3,
                eyesClosed: false, sharpness: 80, filename: "a.jpg"),
            BurstRow(
                imageID: 2, make: nil, model: nil, serial: nil,
                capturedTS: 100.5, signature: s1, eyesRatio: 0.05,
                eyesClosed: true, sharpness: 15, filename: "b.jpg"),
            // An un-analysed row (no ts, no products).
            BurstRow(
                imageID: 3, make: nil, model: nil, serial: nil,
                capturedTS: nil, signature: nil, eyesRatio: nil,
                eyesClosed: nil, sharpness: nil, filename: "c.jpg"),
        ]
        let annotations = BurstAnnotator.annotate(rows: rows)
        let badges = CullingBadgeMapper.map(rows: rows, annotations: annotations)

        // Row 1: in-burst + best → badge with the FULL member payload.
        let badge1 = try? XCTUnwrap(badges[1])
        XCTAssertEqual(badge1?.hasBurst, true)
        XCTAssertEqual(badge1?.burstIndex, 1)
        XCTAssertEqual(badge1?.burstSize, 2)
        XCTAssertEqual(badge1?.best, true)
        XCTAssertEqual(badge1?.burstMembers, [1, 2])
        XCTAssertFalse(badge1?.blurry ?? true)
        XCTAssertFalse(badge1?.eyesClosed ?? true)

        // Row 2: blurry (absolute 15 < 22 AND relative 80-15 > 14) + closed.
        let badge2 = try? XCTUnwrap(badges[2])
        XCTAssertEqual(badge2?.blurry, true)
        XCTAssertEqual(badge2?.eyesClosed, true)
        XCTAssertEqual(badge2?.burstIndex, 2)
        XCTAssertFalse(badge2?.best ?? true)

        // Row 3: no annotation of any kind → NO badge (default-neutral).
        XCTAssertNil(badges[3])

        // Zero annotations → the empty map (the byte-identical grid face).
        let empty = CullingBadgeMapper.map(rows: rows, annotations: [:])
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: - The 转为堆栈 one-key (review m-6: createStack consumes)

    func testBurstStackMaterialization() async throws {
        let library = LibraryStore(store: store)
        let idA = try await insertAnalysed(
            path: "Media/a.jpg", sharpness: 60, faces: 0, eyesClosed: 0)
        let idB = try await insertAnalysed(
            path: "Media/b.jpg", sharpness: 70, faces: 0, eyesClosed: 0)
        // The host's onCreateBurstStack route = createStack(memberIDs:).
        let stack = try await library.createStack(memberIDs: [idA, idB])
        XCTAssertEqual(stack.memberIDs, [idA, idB])
        // A repeat route re-fires typed (the one-image-one-stack invariant —
        // the user's stack entity is the single materialized truth).
        await XCTAssertThrowsErrorAsync(
            try await library.createStack(memberIDs: [idA, idB]))
    }
}

/// The async throws-assertion helper (XCTAssertThrowsError is sync-only).
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected a thrown error", file: file, line: line)
    } catch { /* expected */ }
}
