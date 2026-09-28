import CoreGraphics
import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-3 — the culling-domain toolset tests.
//
// Segments (per plan task, one file — the snapshot rides every commit):
//   T1  snapshot(list_photos) + 25-column projection freeze + predicate
//       round-trip (GUI chips ↔ MCP filter, ONE translation layer) + keyset
//       cursor paging + invalidFilter matrix + no-session shape
//   T2  write-five parity (sidecar真身 + lindex row + GUI-visible face) +
//       live soft-skip / claim-不动 negatives + preset trio + snapshot 9
//   T3  image trio + base64 budget table (McpCullingImageBudgetTests) +
//       snapshot 12
//   T4  list_bursts golden + get_face_regions conversion + snapshot 14
//   T5  SC#5/SC#6 end-to-end over InMemoryTransport
// ─────────────────────────────────────────────────────────────────────────────

final class McpCullingToolsetTests: XCTestCase {

    // MARK: - Fixture plumbing (shared by every segment)

    /// A real SessionIndexStore over a temp session root, opened with an
    /// empty scan; rows are seeded through the store's own handle (the
    /// FilterSQLTests pattern).
    struct Fixture {
        let store: SessionIndexStore
        let root: URL
        let sessionRoot: URL

        func cleanup() {
            Task { await store.close() }
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// Seed one row with the full v2 column face the tests touch.
    func seedRow(
        _ store: SessionIndexStore,
        path: String,
        dir: String? = "Capture",
        rating: Int64? = nil,
        colorLabel: Int64? = nil,
        keywords: String? = nil,
        flag: Int64? = nil,
        note: String? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        iso: Int64? = nil,
        focalLength: Double? = nil,
        aperture: Double? = nil,
        exposure: Double? = nil,
        captureDate: Double? = nil,
        hasEdits: Int64 = 0,
        width: Int64? = 1000,
        height: Int64? = 750,
        thumbState: Int64 = 0
    ) async throws {
        try await store.withHandleForTesting { handle in
            let filename = (path as NSString).lastPathComponent
            let insert = try handle.prepare("""
                INSERT INTO images (
                  path, dir, filename, rating, color_label, keywords, flag, note,
                  camera_make, camera_model, iso, focal_length, aperture, exposure,
                  capture_date, has_edits, width, height, thumb_state, orphan_sidecar
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                """)
            try insert.bindText(1, path)
            try insert.bindText(2, dir)
            try insert.bindText(3, filename)
            try insert.bindInt(4, rating)
            try insert.bindInt(5, colorLabel)
            try insert.bindText(6, keywords)
            try insert.bindInt(7, flag)
            try insert.bindText(8, note)
            try insert.bindText(9, cameraMake)
            try insert.bindText(10, cameraModel)
            try insert.bindInt(11, iso)
            try insert.bindDouble(12, focalLength)
            try insert.bindDouble(13, aperture)
            try insert.bindDouble(14, exposure)
            try insert.bindDouble(15, captureDate)
            try insert.bindInt(16, hasEdits)
            try insert.bindInt(17, width)
            try insert.bindInt(18, height)
            try insert.bindInt(19, thumbState)
            _ = try insert.step()
        }
    }

    /// The 12-2 translation-layer row set (FilterSQLTests.seedFixture's
    /// paths) — the predicate round-trip reuses the SAME content so the
    /// GUI-side and MCP-side hits cross-validate on known ground truth.
    func seedFilterFixture(_ store: SessionIndexStore) async throws {
        try await seedRow(store, path: "nature-rose.arw", rating: 3, keywords: "Nature|Flower|Rose")
        try await seedRow(store, path: "nature-tree.arw", rating: 2, keywords: "Nature|Tree")
        try await seedRow(store, path: "natureholics.arw", rating: 4, keywords: "NatureHolics")
        try await seedRow(store, path: "nature.arw", rating: 1, keywords: "Nature")
        try await seedRow(store, path: "cleared.arw", keywords: "", flag: 1)
        try await seedRow(store, path: "untagged.arw")
        try await seedRow(store, path: "Capture/100%_shot.ARW")
        try await seedRow(store, path: "Capture/it's a photo.ARW")
        try await seedRow(
            store, path: "iso400.arw", cameraMake: "Canon", iso: 400,
            focalLength: 50, captureDate: 1_700_000_000)
    }

    func makeFixture(
        seed: (SessionIndexStore) async throws -> Void
    ) async throws -> Fixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-culling-\(UUID().uuidString)", isDirectory: true)
        let sessionRoot = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot, withIntermediateDirectories: true)
        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.reconcile(
            root: sessionRoot, scan: AsyncStream { $0.finish() })
        try await seed(store)
        return Fixture(store: store, root: root, sessionRoot: sessionRoot)
    }

    /// The context + registry over a fixture (the tests' own assembly — the
    /// same registerAll the 14-4 union will call).
    func makeRegistry(
        _ fixture: Fixture,
        metadata: MetadataService? = nil,
        sidecarWriter: BatchSidecarWriter? = nil,
        presets: PresetsStore? = nil,
        liveRelPaths: Set<String> = [],
        thumbnailProvider: SessionThumbnailProvider? = nil,
        decodeImage: @escaping @Sendable (URL) async throws -> CGImage = { _ in
            XCTFail("decode leg not wired in this test")
            throw McpToolError.renderFailed("no decode leg")
        },
        gate: McpRenderGate = McpRenderGate()
    ) async -> McpToolRegistry {
        let context = McpCullingContext(
            store: { [store = fixture.store] in store },
            sessionRoot: { [sessionRoot = fixture.sessionRoot] in sessionRoot },
            metadata: { metadata },
            sidecarWriter: { sidecarWriter },
            presets: { presets },
            liveRelPaths: { liveRelPaths },
            thumbnailProvider: { thumbnailProvider },
            decodeImage: decodeImage,
            renderGate: gate)
        let registry = McpToolRegistry()
        await McpCullingToolset.registerAll(on: registry, context: context)
        return registry
    }

    /// Call a tool and decode its text output as JSON.
    func callJSON(
        _ registry: McpToolRegistry, name: String,
        arguments: [String: McpJSON] = [:], file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [String: Any] {
        let output = try await registry.call(name: name, arguments: arguments)
        guard case .text(let text) = output.content.first else {
            XCTFail("expected a text payload", file: file, line: line)
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(object as? [String: Any], file: file, line: line)
    }

    // MARK: - T1: culling-domain snapshot (grows per task)

    func testCullingSnapshotListPhotos() async throws {
        let fixture = try await makeFixture { _ in }
        defer { fixture.cleanup() }
        let registry = await makeRegistry(fixture)
        try await McpRegistrySnapshotTests.assertSnapshot(
            registry: registry,
            expected: [
                McpToolDescriptor(
                    name: "list_photos",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"cursor":{"type":"string","description":"Opaque nextCursor token from the previous page"},"filter":{"type":"object","description":"FilterPredicateGroup JSON: {schemaVersion:1, match:"all"|"any", rules:[{field, op, value:{kind, ...}}]}"},"limit":{"type":"integer","minimum":1,"maximum":1000,"description":"Rows per page (default 200)"},"sort":{"type":"object","description":"{key: filename|rating|captureDate|iso|focalLength|scanEpoch, ascending: bool}"}}}"#,
                    readOnlyHint: true),
            ])
    }

    // MARK: - T1: 25-column projection freeze

    func testProjectionExposesExactly25Columns() async throws {
        XCTAssertEqual(McpPhotoProjection.exposedColumns.count, 25)
        XCTAssertEqual(
            Set(McpPhotoProjection.exposedColumns).intersection(
                McpPhotoProjection.hiddenColumns), [])
        // 34-column total face: exposed 25 + hidden 9.
        XCTAssertEqual(
            McpPhotoProjection.exposedColumns.count
                + McpPhotoProjection.hiddenColumns.count, 34)

        let fixture = try await makeFixture { store in
            try await seedRow(
                store, path: "full.arw", rating: 3, colorLabel: 2,
                keywords: "Nature", flag: 1, note: "hello",
                cameraMake: "Canon", cameraModel: "EOS R5", iso: 400,
                focalLength: 50, aperture: 1.8, exposure: 0.01,
                captureDate: 1_700_000_000, hasEdits: 1)
        }
        defer { fixture.cleanup() }
        let registry = await makeRegistry(fixture)
        let payload = try await callJSON(registry, name: "list_photos")
        let rows = try XCTUnwrap(payload["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(
            Set(rows[0].keys), Set(McpPhotoProjection.exposedColumns),
            "row dict keys == the 25 exposed columns, no more no less")
        // Values flow through (spot columns incl. the geometry the crop
        // tool consumes).
        XCTAssertEqual(rows[0]["path"] as? String, "full.arw")
        XCTAssertEqual(rows[0]["rating"] as? Int, 3)
        XCTAssertEqual(rows[0]["has_edits"] as? Int, 1)
        XCTAssertEqual(rows[0]["width"] as? Int, 1000)
        XCTAssertEqual(rows[0]["capture_date"] as? Double, 1_700_000_000)
        // NULL columns ride as explicit nulls (stable row shape).
        XCTAssertNotNil(rows[0]["lens_model"])
        XCTAssertTrue(rows[0]["lens_model"] is NSNull)
    }

    func testProjectionNeverLeaksHiddenColumns() async throws {
        let fixture = try await makeFixture { store in
            try await seedFilterFixture(store)
        }
        defer { fixture.cleanup() }
        let registry = await makeRegistry(fixture)
        let output = try await registry.call(name: "list_photos", arguments: [:])
        guard case .text(let text) = output.content.first else {
            return XCTFail("expected text")
        }
        for hidden in McpPhotoProjection.hiddenColumns {
            XCTAssertTrue(
                text.contains("\"\(hidden)\"") == false,
                "hidden column '\(hidden)' leaked into the list_photos payload")
        }
    }

    // MARK: - T1: predicate round-trip (zero new translation layer)

    /// The SAME FilterPredicateGroup evaluated (a) through the GUI-side
    /// `store.query` face and (b) through the MCP list_photos handler must
    /// hit the identical path set — the FilterSQL single-translation-layer
    /// proof on the MCP entry.
    func testPredicateRoundTripGuiVsMcp() async throws {
        let fixture = try await makeFixture { store in
            try await seedFilterFixture(store)
        }
        defer { fixture.cleanup() }
        let group = FilterPredicateGroup(
            match: .all,
            rules: [
                .init(field: .keywords, op: .contains, value: .text("Nature")),
                .init(field: .rating, op: .gte, value: .int(2)),
            ])
        // (a) the GUI-side face.
        let guiRows = try await fixture.store.query(groups: [group])
        let guiPaths = Set(guiRows.map(\.path))

        // (b) the MCP entry with the group's persisted JSON spelling.
        let data = try JSONEncoder().encode(group)
        let json = try JSONSerialization.jsonObject(with: data)
        let filterJSON = try XCTUnwrap(McpJSONSerialization.anyJSON(from: json))
        let registry = await makeRegistry(fixture)
        let payload = try await callJSON(
            registry, name: "list_photos", arguments: ["filter": filterJSON])
        let rows = try XCTUnwrap(payload["rows"] as? [[String: Any]])
        let mcpPaths = Set(rows.compactMap { $0["path"] as? String })

        XCTAssertEqual(guiPaths, mcpPaths)
        XCTAssertEqual(
            mcpPaths, ["nature-rose.arw", "nature-tree.arw"],
            "known fixture ground truth: four-clause excludes NatureHolics; "
                + "rating>=2 excludes nature.arw (rating 1)")
    }

    // MARK: - T1: keyset cursor paging

    func testCursorPagingFirstNextExhaust() async throws {
        let fixture = try await makeFixture { store in
            for index in 0..<12 {
                try await seedRow(
                    store, path: String(format: "img-%02d.arw", index),
                    captureDate: Double(index) * 10)
            }
        }
        defer { fixture.cleanup() }
        let registry = await makeRegistry(fixture)
        let sort: McpJSON = .object([
            "key": .string("captureDate"), "ascending": .bool(true),
        ])

        // First page.
        let page1 = try await callJSON(
            registry, name: "list_photos",
            arguments: ["sort": sort, "limit": .int(5)])
        let rows1 = try XCTUnwrap(page1["rows"] as? [[String: Any]])
        XCTAssertEqual(rows1.map { $0["path"] as? String }, (0..<5).map { String(format: "img-%02d.arw", $0) })
        let cursor1 = try XCTUnwrap(page1["nextCursor"] as? String)

        // Next page.
        let page2 = try await callJSON(
            registry, name: "list_photos",
            arguments: ["sort": sort, "limit": .int(5), "cursor": .string(cursor1)])
        let rows2 = try XCTUnwrap(page2["rows"] as? [[String: Any]])
        XCTAssertEqual(
            rows2.map { $0["path"] as? String },
            (5..<10).map { String(format: "img-%02d.arw", $0) })
        let cursor2 = try XCTUnwrap(page2["nextCursor"] as? String)

        // Exhaustion: a short page carries NO nextCursor.
        let page3 = try await callJSON(
            registry, name: "list_photos",
            arguments: ["sort": sort, "limit": .int(5), "cursor": .string(cursor2)])
        let rows3 = try XCTUnwrap(page3["rows"] as? [[String: Any]])
        XCTAssertEqual(rows3.count, 2)
        XCTAssertNil(page3["nextCursor"] as? String)

        // No overlap, full coverage.
        let all = (rows1.compactMap { $0["path"] as? String })
            + (rows2.compactMap { $0["path"] as? String })
            + (rows3.compactMap { $0["path"] as? String })
        XCTAssertEqual(all.count, Set(all).count)
        XCTAssertEqual(all.count, 12)
    }

    func testCursorDescendingAndNullClassContinuation() async throws {
        let fixture = try await makeFixture { store in
            // rating 1...5 + three NULL-rating rows (the NULL class sorts
            // last in both directions).
            for index in 1...5 {
                try await seedRow(
                    store, path: String(format: "rated-%02d.arw", index),
                    rating: Int64(index), captureDate: Double(index))
            }
            try await seedRow(store, path: "null-a.arw", captureDate: 100)
            try await seedRow(store, path: "null-b.arw", captureDate: 101)
            try await seedRow(store, path: "null-c.arw", captureDate: 102)
        }
        defer { fixture.cleanup() }
        let registry = await makeRegistry(fixture)
        let sort: McpJSON = .object([
            "key": .string("rating"), "ascending": .bool(false),
        ])

        // DESC page 1: ratings 5,4,3,2,1 + the first NULL row (NULLs sort
        // last, LIMIT 6 cuts into the NULL class); the NULL-class
        // continuation cursor pages the rest by path.
        let page1 = try await callJSON(
            registry, name: "list_photos",
            arguments: ["sort": sort, "limit": .int(6)])
        let rows1 = try XCTUnwrap(page1["rows"] as? [[String: Any]])
        XCTAssertEqual(rows1.first?["path"] as? String, "rated-05.arw")
        XCTAssertEqual(rows1.last?["path"] as? String, "null-a.arw")
        let cursor = try XCTUnwrap(page1["nextCursor"] as? String)
        let page2 = try await callJSON(
            registry, name: "list_photos",
            arguments: ["sort": sort, "limit": .int(6), "cursor": .string(cursor)])
        let rows2 = try XCTUnwrap(page2["rows"] as? [[String: Any]])
        XCTAssertEqual(rows2.map { $0["path"] as? String }, ["null-b.arw", "null-c.arw"])
    }

    func testCursorInvalidatedBySortKeyChange() async throws {
        let fixture = try await makeFixture { store in
            for index in 0..<6 {
                try await seedRow(
                    store, path: String(format: "img-%02d.arw", index),
                    rating: Int64(index % 3 + 1), captureDate: Double(index))
            }
        }
        defer { fixture.cleanup() }
        let registry = await makeRegistry(fixture)
        let captureSort: McpJSON = .object([
            "key": .string("captureDate"), "ascending": .bool(true),
        ])
        let page1 = try await callJSON(
            registry, name: "list_photos",
            arguments: ["sort": captureSort, "limit": .int(3)])
        let cursor = try XCTUnwrap(page1["nextCursor"] as? String)

        // Reuse under a DIFFERENT sort key → typed invalidParams.
        let ratingSort: McpJSON = .object([
            "key": .string("rating"), "ascending": .bool(true),
        ])
        do {
            _ = try await registry.call(
                name: "list_photos",
                arguments: ["sort": ratingSort, "cursor": .string(cursor)])
            XCTFail("expected invalidParams for a mismatched sort")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
        // Same sort + cursor still works.
        let page2 = try await callJSON(
            registry, name: "list_photos",
            arguments: ["sort": captureSort, "limit": .int(3), "cursor": .string(cursor)])
        XCTAssertEqual((page2["rows"] as? [[String: Any]])?.count, 3)
    }

    // MARK: - T1: invalidFilter matrix + limit/sort guards

    func testInvalidFilterMatrixNegatives() async throws {
        let fixture = try await makeFixture { store in
            try await seedFilterFixture(store)
        }
        defer { fixture.cleanup() }
        let registry = await makeRegistry(fixture)

        func expectInvalidFilter(_ filter: McpJSON) async {
            do {
                _ = try await registry.call(
                    name: "list_photos", arguments: ["filter": filter])
                XCTFail("expected invalidFilter for \(filter)")
            } catch let error as McpToolError {
                XCTAssertEqual(error.code, "invalidFilter")
            } catch {
                XCTFail("expected McpToolError, got \(error)")
            }
        }

        // Unknown field.
        await expectInvalidFilter(.object([
            "schemaVersion": .int(1), "match": .string("all"),
            "rules": .array([.object([
                "field": .string("apertureKnobs"), "op": .string("eq"),
                "value": .object(["kind": .string("int"), "value": .int(1)]),
            ])]),
        ]))
        // Illegal field×op (rating contains).
        await expectInvalidFilter(.object([
            "schemaVersion": .int(1), "match": .string("all"),
            "rules": .array([.object([
                "field": .string("rating"), "op": .string("contains"),
                "value": .object(["kind": .string("int"), "value": .int(3)]),
            ])]),
        ]))
        // Illegal value kind (iso with a text value).
        await expectInvalidFilter(.object([
            "schemaVersion": .int(1), "match": .string("all"),
            "rules": .array([.object([
                "field": .string("iso"), "op": .string("gte"),
                "value": .object(["kind": .string("text"), "value": .string("400")]),
            ])]),
        ]))
        // Unparsable shape (rules missing).
        await expectInvalidFilter(.object(["schemaVersion": .int(1)]))
    }

    func testListPhotosLimitAndSortGuards() async throws {
        let fixture = try await makeFixture { store in
            try await seedFilterFixture(store)
        }
        defer { fixture.cleanup() }
        let registry = await makeRegistry(fixture)

        // limit > 1000 → invalidParams.
        do {
            _ = try await registry.call(
                name: "list_photos", arguments: ["limit": .int(1001)])
            XCTFail("expected invalidParams for limit 1001")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
        // Unknown sort key → invalidParams.
        do {
            _ = try await registry.call(
                name: "list_photos",
                arguments: ["sort": .object(["key": .string("aperture")])])
            XCTFail("expected invalidParams for unknown sort key")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
        // Default limit 200 without arguments → whole fixture, no cursor.
        let payload = try await callJSON(registry, name: "list_photos")
        XCTAssertEqual((payload["rows"] as? [[String: Any]])?.count, 9)
        XCTAssertNil(payload["nextCursor"] as? String)
    }

    // MARK: - T1: no-session shape

    func testListPhotosWithoutSessionIsTypedNotSessionMember() async throws {
        let context = McpCullingContext(
            store: { nil }, sessionRoot: { nil },
            decodeImage: { _ in
                throw McpToolError.renderFailed("unused")
            })
        let registry = McpToolRegistry()
        await McpCullingToolset.registerAll(on: registry, context: context)
        do {
            _ = try await registry.call(name: "list_photos", arguments: [:])
            XCTFail("expected notSessionMember without a session")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
            XCTAssertTrue(error.message.contains("no open session"))
        }
    }
}

// The test helper the round-trip needs: [String: Any] (JSONSerialization
// output) → McpJSON.
extension McpJSONSerialization {
    static func anyJSON(from any: Any) throws -> McpJSON {
        let data = try JSONSerialization.data(withJSONObject: any)
        let decoded = try JSONSerialization.jsonObject(with: data)
        return mcpJSONValue(from: decoded)
    }

    private static func mcpJSONValue(from any: Any) -> McpJSON {
        switch any {
        case is NSNull: return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let objCType = String(cString: number.objCType)
            switch objCType {
            case "d": return .double(number.doubleValue)
            case "B": return .bool(number.boolValue)
            default: return .int(number.intValue)
            }
        case let string as String: return .string(string)
        case let array as [Any]: return .array(array.map(mcpJSONValue(from:)))
        case let dict as [String: Any]:
            var members: [String: McpJSON] = [:]
            for (key, value) in dict { members[key] = mcpJSONValue(from: value) }
            return .object(members)
        default: return .null
        }
    }
}
