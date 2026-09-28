import CoreGraphics
import Foundation
import LightamerCore
import LightamerIOP
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
    static func seedRow(
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
    static func seedFilterFixture(_ store: SessionIndexStore) async throws {
        try await Self.seedRow(store, path: "nature-rose.arw", rating: 3, keywords: "Nature|Flower|Rose")
        try await Self.seedRow(store, path: "nature-tree.arw", rating: 2, keywords: "Nature|Tree")
        try await Self.seedRow(store, path: "natureholics.arw", rating: 4, keywords: "NatureHolics")
        try await Self.seedRow(store, path: "nature.arw", rating: 1, keywords: "Nature")
        try await Self.seedRow(store, path: "cleared.arw", keywords: "", flag: 1)
        try await Self.seedRow(store, path: "untagged.arw")
        try await Self.seedRow(store, path: "Capture/100%_shot.ARW")
        try await Self.seedRow(store, path: "Capture/it's a photo.ARW")
        try await Self.seedRow(
            store, path: "iso400.arw", cameraMake: "Canon", iso: 400,
            focalLength: 50, captureDate: 1_700_000_000)
    }

    static func makeFixture(
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
    static func makeRegistry(
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
    static func callJSON(
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

    func testCullingSnapshotThroughImageTrio() async throws {
        let fixture = try await Self.makeFixture { _ in }
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(fixture)
        try await McpRegistrySnapshotTests.assertSnapshot(
            registry: registry,
            expected: [
                McpToolDescriptor(
                    name: "append_note",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["relPaths","note"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"note":{"type":"string","minLength":1,"description":"Appended as one line (a newline is inserted after an existing note)"}}}"#,
                    destructiveHint: true),
                McpToolDescriptor(
                    name: "apply_preset",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["presetID","relPaths"],"properties":{"presetID":{"type":"string"},"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"mode":{"enum":["overwrite","merge"],"description":"Paste mode (default merge)"},"selection":{"type":"array","description":"Partial-apply subset of instances","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer"},"multiName":{"type":"string"}},"required":["opName","multiPriority","multiName"]}}}}"#,
                    destructiveHint: true),
                McpToolDescriptor(
                    name: "get_face_regions",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["relPaths"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":20},"includeLandmarks":{"type":"boolean","description":"Also return per-face landmark point sets (default false)"}}}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "get_contact_sheet",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":30},"filter":{"type":"object","description":"FilterPredicateGroup JSON (same shape as list_photos.filter)"},"sort":{"type":"object","description":"Row order when filter is used (same shape as list_photos.sort)"},"cols":{"type":"integer","minimum":1,"maximum":6},"rows":{"type":"integer","minimum":1,"maximum":5}},"oneOf":[{"required":["relPaths"]},{"required":["filter"]}]}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "list_bursts",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"gapSeconds":{"type":"number","exclusiveMinimum":0,"description":"Max gap between consecutive shots of one burst (default 2.0)"}}}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "get_detail_crop",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["relPath","roi"],"properties":{"relPath":{"type":"string"},"roi":{"type":"object","properties":{"x":{"type":"integer","minimum":0},"y":{"type":"integer","minimum":0},"w":{"type":"integer","exclusiveMinimum":0},"h":{"type":"integer","exclusiveMinimum":0}},"required":["x","y","w","h"]},"longEdge":{"type":"integer","minimum":64,"maximum":1536,"description":"Output long edge (default 1024)"}}}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "get_thumbnails",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["relPaths"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":20},"regenerate":{"type":"boolean","description":"Re-render stale thumbnails before returning (default false — stale rows are only marked)"}}}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "diff_presets",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["presetIDA","presetIDB"],"properties":{"presetIDA":{"type":"string"},"presetIDB":{"type":"string"}}}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "list_photos",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"cursor":{"type":"string","description":"Opaque nextCursor token from the previous page"},"filter":{"type":"object","description":"FilterPredicateGroup JSON: {schemaVersion:1, match:"all"|"any", rules:[{field, op, value:{kind, ...}}]}"},"limit":{"type":"integer","minimum":1,"maximum":1000,"description":"Rows per page (default 200)"},"sort":{"type":"object","description":"{key: filename|rating|captureDate|iso|focalLength|scanEpoch, ascending: bool}"}}}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "list_presets",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"kind":{"enum":["develop","export"],"description":"Filter by preset kind"}}}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "set_color_label",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["relPaths","color"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"color":{"type":["integer","null"],"minimum":0,"maximum":6,"description":"0-6, or null to clear"}}}"#,
                    destructiveHint: true),
                McpToolDescriptor(
                    name: "set_flag",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["relPaths","flag"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"flag":{"type":["integer","null"],"minimum":0,"maximum":2,"description":"0 none / 1 pick / 2 reject, or null to clear"}}}"#,
                    destructiveHint: true),
                McpToolDescriptor(
                    name: "set_keywords",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["relPaths","keywords"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"keywords":{"type":["array","null"],"items":{"type":"string"},"description":"Whole-group replacement; empty array = cleared state, null = never-tagged; entries must not contain '|'"}}}"#,
                    destructiveHint: true),
                McpToolDescriptor(
                    name: "set_rating",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","required":["relPaths","rating"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"rating":{"type":["integer","null"],"minimum":0,"maximum":5,"description":"0-5, or null to clear"}}}"#,
                    destructiveHint: true),
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

        let fixture = try await Self.makeFixture { store in
            try await Self.seedRow(
                store, path: "full.arw", rating: 3, colorLabel: 2,
                keywords: "Nature", flag: 1, note: "hello",
                cameraMake: "Canon", cameraModel: "EOS R5", iso: 400,
                focalLength: 50, aperture: 1.8, exposure: 0.01,
                captureDate: 1_700_000_000, hasEdits: 1)
        }
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(fixture)
        let payload = try await Self.callJSON(registry, name: "list_photos")
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
        let fixture = try await Self.makeFixture { store in
            try await Self.seedFilterFixture(store)
        }
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(fixture)
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
        let fixture = try await Self.makeFixture { store in
            try await Self.seedFilterFixture(store)
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
        let registry = await Self.makeRegistry(fixture)
        let payload = try await Self.callJSON(
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
        let fixture = try await Self.makeFixture { store in
            for index in 0..<12 {
                try await Self.seedRow(
                    store, path: String(format: "img-%02d.arw", index),
                    captureDate: Double(index) * 10)
            }
        }
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(fixture)
        let sort: McpJSON = .object([
            "key": .string("captureDate"), "ascending": .bool(true),
        ])

        // First page.
        let page1 = try await Self.callJSON(
            registry, name: "list_photos",
            arguments: ["sort": sort, "limit": .int(5)])
        let rows1 = try XCTUnwrap(page1["rows"] as? [[String: Any]])
        XCTAssertEqual(rows1.map { $0["path"] as? String }, (0..<5).map { String(format: "img-%02d.arw", $0) })
        let cursor1 = try XCTUnwrap(page1["nextCursor"] as? String)

        // Next page.
        let page2 = try await Self.callJSON(
            registry, name: "list_photos",
            arguments: ["sort": sort, "limit": .int(5), "cursor": .string(cursor1)])
        let rows2 = try XCTUnwrap(page2["rows"] as? [[String: Any]])
        XCTAssertEqual(
            rows2.map { $0["path"] as? String },
            (5..<10).map { String(format: "img-%02d.arw", $0) })
        let cursor2 = try XCTUnwrap(page2["nextCursor"] as? String)

        // Exhaustion: a short page carries NO nextCursor.
        let page3 = try await Self.callJSON(
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
        let fixture = try await Self.makeFixture { store in
            // rating 1...5 + three NULL-rating rows (the NULL class sorts
            // last in both directions).
            for index in 1...5 {
                try await Self.seedRow(
                    store, path: String(format: "rated-%02d.arw", index),
                    rating: Int64(index), captureDate: Double(index))
            }
            try await Self.seedRow(store, path: "null-a.arw", captureDate: 100)
            try await Self.seedRow(store, path: "null-b.arw", captureDate: 101)
            try await Self.seedRow(store, path: "null-c.arw", captureDate: 102)
        }
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(fixture)
        let sort: McpJSON = .object([
            "key": .string("rating"), "ascending": .bool(false),
        ])

        // DESC page 1: ratings 5,4,3,2,1 + the first NULL row (NULLs sort
        // last, LIMIT 6 cuts into the NULL class); the NULL-class
        // continuation cursor pages the rest by path.
        let page1 = try await Self.callJSON(
            registry, name: "list_photos",
            arguments: ["sort": sort, "limit": .int(6)])
        let rows1 = try XCTUnwrap(page1["rows"] as? [[String: Any]])
        XCTAssertEqual(rows1.first?["path"] as? String, "rated-05.arw")
        XCTAssertEqual(rows1.last?["path"] as? String, "null-a.arw")
        let cursor = try XCTUnwrap(page1["nextCursor"] as? String)
        let page2 = try await Self.callJSON(
            registry, name: "list_photos",
            arguments: ["sort": sort, "limit": .int(6), "cursor": .string(cursor)])
        let rows2 = try XCTUnwrap(page2["rows"] as? [[String: Any]])
        XCTAssertEqual(rows2.map { $0["path"] as? String }, ["null-b.arw", "null-c.arw"])
    }

    func testCursorInvalidatedBySortKeyChange() async throws {
        let fixture = try await Self.makeFixture { store in
            for index in 0..<6 {
                try await Self.seedRow(
                    store, path: String(format: "img-%02d.arw", index),
                    rating: Int64(index % 3 + 1), captureDate: Double(index))
            }
        }
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(fixture)
        let captureSort: McpJSON = .object([
            "key": .string("captureDate"), "ascending": .bool(true),
        ])
        let page1 = try await Self.callJSON(
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
        let page2 = try await Self.callJSON(
            registry, name: "list_photos",
            arguments: ["sort": captureSort, "limit": .int(3), "cursor": .string(cursor)])
        XCTAssertEqual((page2["rows"] as? [[String: Any]])?.count, 3)
    }

    // MARK: - T1: invalidFilter matrix + limit/sort guards

    func testInvalidFilterMatrixNegatives() async throws {
        let fixture = try await Self.makeFixture { store in
            try await Self.seedFilterFixture(store)
        }
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(fixture)

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
        let fixture = try await Self.makeFixture { store in
            try await Self.seedFilterFixture(store)
        }
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(fixture)

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
        let payload = try await Self.callJSON(registry, name: "list_photos")
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
    // MARK: - T2: write five (MetadataService single source)

    /// Fixture with REAL image files on disk (metadata writes compose the
    /// sidecar next to each file — the MetadataServiceTests pattern).
    func makeFileFixture() async throws -> Fixture {
        let fixture = try await Self.makeFixture { store in
            try await Self.seedFilterFixture(store)
        }
        for rel in ["nature-rose.arw", "nature-tree.arw", "natureholics.arw"] {
            try Data(repeating: 0xAB, count: 16).write(
                to: fixture.sessionRoot.appendingPathComponent(rel))
        }
        return fixture
    }

    /// The write-five registry wiring: a REAL MetadataService over the
    /// REAL BatchSidecarWriter (all three segments — the parity red line).
    func makeWriteRegistry(_ fixture: Fixture) async -> McpToolRegistry {
        let writer = BatchSidecarWriter(root: fixture.sessionRoot, store: fixture.store)
        let metadata = MetadataService(root: fixture.sessionRoot, store: fixture.store, writer: writer)
        return await Self.makeRegistry(fixture, metadata: metadata, sidecarWriter: writer)
    }

    /// The write-back联动 parity: MCP set_rating → ① sidecar真身 bytes,
    /// ② the lindex row (claim transaction), ③ the GUI-visible face (the
    /// query rows the grid/filter reads). One path, three assertions.
    func testSetRatingWriteBackThreeAssertions() async throws {
        let fixture = try await makeFileFixture()
        defer { fixture.cleanup() }
        let registry = await makeWriteRegistry(fixture)
        let output = try await registry.call(
            name: "set_rating",
            arguments: [
                "relPaths": .array([.string("nature-rose.arw")]),
                "rating": .int(4),
            ])
        guard case .text(let text) = output.content.first else {
            return XCTFail("expected text")
        }
        XCTAssertTrue(text.contains("nature-rose.arw"))

        // ① sidecar truth.
        let sidecarURL = LightamerSidecar.sidecarURL(
            for: fixture.sessionRoot.appendingPathComponent("nature-rose.arw"))
        let document = try JSONDecoder().decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(document.rating, 4)
        // ② the index row (segment 3's enqueue awaits its own drain).
        let row = try await fixture.store.fetchRow(relPath: "nature-rose.arw")
        XCTAssertEqual(row?.rating, 4)
        // ③ the GUI-visible face: the filter query sees the new rating.
        let rows = try await fixture.store.query(
            groups: [FilterPredicateGroup(
                rules: [.init(field: .rating, op: .eq, value: .int(4))])])
        // natureholics.arw rides the fixture at rating 4 already; the
        // written row JOINS the set (the filter face sees the write).
        XCTAssertTrue(rows.map(\.path).contains("nature-rose.arw"))
    }

    func testBatchMetadataOneOutcomeTwoRows() async throws {
        let fixture = try await makeFileFixture()
        defer { fixture.cleanup() }
        let registry = await makeWriteRegistry(fixture)
        let payload = try await Self.callJSON(
            registry, name: "set_flag",
            arguments: [
                "relPaths": .array([.string("nature-rose.arw"), .string("nature-tree.arw")]),
                "flag": .int(1),
            ])
        XCTAssertEqual(
            Set((payload["appliedRelPaths"] as? [String]) ?? []),
            ["nature-rose.arw", "nature-tree.arw"])
        XCTAssertEqual((payload["skippedRelPaths"] as? [String])?.count, 0)
        // Both rows flipped together (one bulk change).
        for rel in ["nature-rose.arw", "nature-tree.arw"] {
            let row = try await fixture.store.fetchRow(relPath: rel)
            XCTAssertEqual(row?.flag, 1)
        }
    }

    func testKeywordSeparatorTypedNegative() async throws {
        let fixture = try await makeFileFixture()
        defer { fixture.cleanup() }
        let registry = await makeWriteRegistry(fixture)
        do {
            _ = try await registry.call(
                name: "set_keywords",
                arguments: [
                    "relPaths": .array([.string("nature-rose.arw")]),
                    "keywords": .array([.string("Nature|Flower")]),
                ])
            XCTFail("expected keywordContainsSeparator")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "keywordContainsSeparator")
            XCTAssertTrue(error.message.contains("|"))
        }
        // Whole-group replacement + null clear both round-trip.
        _ = try await registry.call(
            name: "set_keywords",
            arguments: [
                "relPaths": .array([.string("nature-rose.arw")]),
                "keywords": .array([.string("Landscape"), .string("Sunset")]),
            ])
        var row = try await fixture.store.fetchRow(relPath: "nature-rose.arw")
        XCTAssertEqual(row?.keywords, "Landscape|Sunset")
        _ = try await registry.call(
            name: "set_keywords",
            arguments: [
                "relPaths": .array([.string("nature-rose.arw")]),
                "keywords": .null,
            ])
        row = try await fixture.store.fetchRow(relPath: "nature-rose.arw")
        XCTAssertNil(row?.keywords)
    }

    func testWriteFiveServerReadOnlyAndNotSessionMember() async throws {
        let fixture = try await makeFileFixture()
        defer { fixture.cleanup() }
        let registry = await makeWriteRegistry(fixture)
        // The只读降级 hook (14-1's seam consumed by REAL write tools now).
        await registry.setWriterCheck { false }
        do {
            _ = try await registry.call(
                name: "set_rating",
                arguments: [
                    "relPaths": .array([.string("nature-rose.arw")]),
                    "rating": .int(3),
                ])
            XCTFail("expected serverReadOnly")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "serverReadOnly")
        }
        // Membership pre-check.
        await registry.setWriterCheck { true }
        do {
            _ = try await registry.call(
                name: "set_rating",
                arguments: [
                    "relPaths": .array([.string("outside.arw")]),
                    "rating": .int(3),
                ])
            XCTFail("expected notSessionMember")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
        }
    }

    /// The claim-不动 negative (CONTEXT 验证红线字面): a GUI-live target's
    /// METADATA write behaves exactly like a non-live one — no rejection,
    /// no skip (the asymmetry vs apply_params' hard reject).
    func testMetadataWriteOnLiveTargetClaimFaceUnchanged() async throws {
        let fixture = try await makeFileFixture()
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(
            fixture,
            metadata: MetadataService(
                root: fixture.sessionRoot, store: fixture.store,
                writer: BatchSidecarWriter(
                    root: fixture.sessionRoot, store: fixture.store)),
            sidecarWriter: BatchSidecarWriter(
                root: fixture.sessionRoot, store: fixture.store),
            liveRelPaths: ["nature-rose.arw"])
        let payload = try await Self.callJSON(
            registry, name: "set_rating",
            arguments: [
                "relPaths": .array([.string("nature-rose.arw")]),
                "rating": .int(5),
            ])
        XCTAssertEqual(
            (payload["appliedRelPaths"] as? [String]) ?? [], ["nature-rose.arw"])
        XCTAssertEqual((payload["skippedRelPaths"] as? [String])?.count, 0)
        let row = try await fixture.store.fetchRow(relPath: "nature-rose.arw")
        XCTAssertEqual(row?.rating, 5)
    }

    // MARK: - T2: preset trio (D8 soft-skip half)

    func makePresetFixture(live: Set<String>) async throws -> (Fixture, McpToolRegistry) {
        let fixture = try await makeFileFixture()
        let presets = PresetsStore(
            directory: fixture.root.appendingPathComponent("presets", isDirectory: true))
        _ = try presets.create(
            name: "Warm", kind: .develop,
            instances: [
                ModuleInstance(
                    module: ExposureModule.self, multiName: "warm",
                    params: ExposureModule.Params(exposure: 0.4)),
            ])
        _ = try presets.create(
            name: "Print-150", kind: .export,
            exportRecipe: [
                ExportVariant(format: .jpeg(quality: 0.9), colorSpace: .sRGB),
            ])
        _ = try presets.create(
            name: "Cold", kind: .develop,
            instances: [
                ModuleInstance(
                    module: ExposureModule.self, multiName: "cold",
                    params: ExposureModule.Params(exposure: -0.4)),
                ModuleInstance(
                    module: ExposureModule.self, multiPriority: 1,
                    multiName: "colder",
                    params: ExposureModule.Params(exposure: -0.8)),
            ])
        let writer = BatchSidecarWriter(root: fixture.sessionRoot, store: fixture.store)
        let metadata = MetadataService(
            root: fixture.sessionRoot, store: fixture.store, writer: writer)
        let registry = await Self.makeRegistry(
            fixture, metadata: metadata, sidecarWriter: writer,
            presets: presets, liveRelPaths: live)
        return (fixture, registry)
    }

    func testApplyPresetLiveSoftSkipVersusApplied() async throws {
        let (fixture, registry) = try await makePresetFixture(live: ["nature-rose.arw"])
        defer { fixture.cleanup() }
        let warm = try await Self.presetID(registry, named: "Warm")
        let payload = try await Self.callJSON(
            registry, name: "apply_preset",
            arguments: [
                "presetID": .string(warm),
                "relPaths": .array([
                    .string("nature-rose.arw"), .string("nature-tree.arw"),
                ]),
            ])
        // D8: the live photo soft-skips into the report face; the other
        // photo applies. No error, no batch blockage.
        XCTAssertEqual(
            (payload["skippedRelPaths"] as? [String]) ?? [], ["nature-rose.arw"])
        XCTAssertEqual(
            (payload["appliedRelPaths"] as? [String]) ?? [], ["nature-tree.arw"])
        // The applied photo's sidecar carries the preset instance.
        let sidecarURL = LightamerSidecar.sidecarURL(
            for: fixture.sessionRoot.appendingPathComponent("nature-tree.arw"))
        let document = try JSONDecoder().decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(document.instances.first?.opName, ExposureModule.opName)
        // The skipped live photo has NO sidecar bytes written.
        let liveSidecar = LightamerSidecar.sidecarURL(
            for: fixture.sessionRoot.appendingPathComponent("nature-rose.arw"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveSidecar.path))
    }

    func testApplyPresetExportNotApplicableAndUnknown() async throws {
        let (fixture, registry) = try await makePresetFixture(live: [])
        defer { fixture.cleanup() }
        let export = try await Self.presetID(registry, named: "Print-150")
        do {
            _ = try await registry.call(
                name: "apply_preset",
                arguments: [
                    "presetID": .string(export),
                    "relPaths": .array([.string("nature-rose.arw")]),
                ])
            XCTFail("expected exportPresetNotApplicable")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "exportPresetNotApplicable")
        }
        do {
            _ = try await registry.call(
                name: "apply_preset",
                arguments: [
                    "presetID": .string("no-such-id"),
                    "relPaths": .array([.string("nature-rose.arw")]),
                ])
            XCTFail("expected unknownPreset")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "unknownPreset")
        }
    }

    func testListPresetsKindFilter() async throws {
        let (fixture, registry) = try await makePresetFixture(live: [])
        defer { fixture.cleanup() }
        let all = try await Self.callJSON(registry, name: "list_presets")
        XCTAssertEqual((all["presets"] as? [[String: Any]])?.count, 3)
        let develop = try await Self.callJSON(
            registry, name: "list_presets", arguments: ["kind": .string("develop")])
        let rows = try XCTUnwrap(develop["presets"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertEqual(row["kind"] as? String, "develop")
        }
        do {
            _ = try await registry.call(
                name: "list_presets", arguments: ["kind": .string("bogus")])
            XCTFail("expected invalidParams")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
    }

    func testDiffPresetsKeySets() async throws {
        let (fixture, registry) = try await makePresetFixture(live: [])
        defer { fixture.cleanup() }
        let warm = try await Self.presetID(registry, named: "Warm")
        let cold = try await Self.presetID(registry, named: "Cold")
        let payload = try await Self.callJSON(
            registry, name: "diff_presets",
            arguments: ["presetIDA": .string(warm), "presetIDB": .string(cold)])
        // Warm: exposure#0 (0.4). Cold: exposure#0 (-0.4, DIFFERS) +
        // exposure#1 (only in B).
        XCTAssertEqual((payload["onlyInA"] as? [String]) ?? [], [])
        XCTAssertEqual((payload["onlyInB"] as? [String]) ?? [], ["exposure#1"])
        XCTAssertEqual((payload["differing"] as? [String]) ?? [], ["exposure#0"])
        // Unknown id → unknownPreset.
        do {
            _ = try await registry.call(
                name: "diff_presets",
                arguments: ["presetIDA": .string(warm), "presetIDB": .string("nope")])
            XCTFail("expected unknownPreset")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "unknownPreset")
        }
    }


    // MARK: - T4: list_bursts

    func testBurstClusteringGolden() async throws {
        // Burst A (Canon, 1s gaps): b1..b3. Burst B (Sony, camera switch):
        // s1..s2. Boundary: a 2.0s gap stays, a 2.1s gap splits. Singles:
        // one isolated photo + one NULL capture_date row.
        let fixture = try await Self.makeFixture { store in
            try await Self.seedRow(store, path: "b1.arw", cameraModel: "Canon", captureDate: 1_700_000_000)
            try await Self.seedRow(store, path: "b2.arw", cameraModel: "Canon", captureDate: 1_700_000_001)
            try await Self.seedRow(store, path: "b3.arw", cameraModel: "Canon", captureDate: 1_700_000_002)
            try await Self.seedRow(store, path: "s1.arw", cameraModel: "Sony", captureDate: 1_700_000_003)
            try await Self.seedRow(store, path: "s2.arw", cameraModel: "Sony", captureDate: 1_700_000_004)
            try await Self.seedRow(store, path: "gap-ok.arw", cameraModel: "Canon", captureDate: 1_700_000_006)
            try await Self.seedRow(store, path: "gap-cut.arw", cameraModel: "Canon", captureDate: 1_700_000_008.1)
            try await Self.seedRow(store, path: "lonely.arw", cameraModel: "Canon", captureDate: 1_700_100_000)
            try await Self.seedRow(store, path: "nodate.arw", cameraModel: "Canon", captureDate: nil)
        }
        defer { fixture.cleanup() }
        let registry = await Self.makeRegistry(fixture)
        let payload = try await Self.callJSON(registry, name: "list_bursts")
        let bursts = try XCTUnwrap(payload["bursts"] as? [[String: Any]])
        let singles = try XCTUnwrap(payload["singles"] as? [String])

        // Expect: [b1..b3 Canon] [s1..s2 Sony] — the camera switch splits,
        // 1s gaps stay; every 1-photo group falls to singles (a burst needs
        // ≥2 members).
        XCTAssertEqual(bursts.count, 2)
        let members0 = try XCTUnwrap(bursts[0]["members"] as? [[String: Any]])
        XCTAssertEqual(
            members0.map { $0["relPath"] as? String },
            ["b1.arw", "b2.arw", "b3.arw"])
        XCTAssertEqual(bursts[0]["count"] as? Int, 3)
        let members1 = try XCTUnwrap(bursts[1]["members"] as? [[String: Any]])
        XCTAssertEqual(members1.map { $0["relPath"] as? String }, ["s1.arw", "s2.arw"])
        // Singles: the three 1-photo groups + the never-dated row
        // (sorted spelling).
        XCTAssertEqual(
            singles, ["gap-cut.arw", "gap-ok.arw", "lonely.arw", "nodate.arw"])

        // The L013 id: "burst-" + StableHash FULL decimal of the first
        // member's path — stable across processes.
        let id = try XCTUnwrap(bursts[0]["id"] as? String)
        XCTAssertEqual(
            id, "burst-\(StableHash.hash("b1.arw"))",
            "burst id = StableHash(path) decimal string (L013)")
        // id stability: recomputing changes nothing.
        XCTAssertEqual(id, "burst-\(StableHash.hash("b1.arw"))")
    }

    // MARK: - T4: get_face_regions

    func testFacePixelRectConversionPerValue() {
        // Vision normalized bottom-left → pixel top-left, rounded.
        let rect = McpCullingToolset.facePixelRect(
            boundingBox: CGRect(x: 0.25, y: 0.5, width: 0.2, height: 0.25),
            imageWidth: 800, imageHeight: 600)
        XCTAssertEqual(rect.x, 200)
        // y = (1 - 0.5 - 0.25) * 600 = 150.
        XCTAssertEqual(rect.y, 150)
        XCTAssertEqual(rect.w, 160)
        XCTAssertEqual(rect.h, 150)

        // The landmark point: face-box-relative, Y flipped.
        let point = McpCullingToolset.landmarkPixelPoint(
            point: CGPoint(x: 0.5, y: 0.5),
            faceBox: CGRect(x: 0.25, y: 0.5, width: 0.2, height: 0.25),
            imageWidth: 800, imageHeight: 600)
        // x = (0.25 + 0.5*0.2) * 800 = 280; y = (1 - (0.5 + 0.5*0.25)) * 600 = 225.
        XCTAssertEqual(point.x, 280)
        XCTAssertEqual(point.y, 225)
    }

    func testFaceRegionsEmptyFacesOnNonFaceImage() async throws {
        // The semantic钉板: a real Vision run on a synthetic gradient (no
        // faces) returns an EMPTY faces array — NOT an error.
        let fixture = try await Self.makeFixture { store in
            try await Self.seedRow(store, path: "noface.arw")
        }
        defer { fixture.cleanup() }
        try Data(repeating: 0xAB, count: 16).write(
            to: fixture.sessionRoot.appendingPathComponent("noface.arw"))
        let registry = await Self.makeRegistry(
            fixture,
            decodeImage: { _ in McpCullingImageBudgetTests.makeGradientCGImage(width: 640, height: 480) })
        let payload = try await Self.callJSON(
            registry, name: "get_face_regions",
            arguments: ["relPaths": .array([.string("noface.arw")])])
        let results = try XCTUnwrap(payload["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["relPath"] as? String, "noface.arw")
        XCTAssertEqual((results[0]["faces"] as? [Any])?.count, 0)

        // relPaths > 20 → invalidParams (the batch cap).
        do {
            let paths: [McpJSON] = (0..<21).map { .string("p\($0).arw") }
            _ = try await registry.call(
                name: "get_face_regions", arguments: ["relPaths": .array(paths)])
            XCTFail("expected invalidParams for 21 relPaths")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
    }

    private static func presetID(
        _ registry: McpToolRegistry, named name: String
    ) async throws -> String {
        let payload = try await Self.callJSON(registry, name: "list_presets")
        let rows = try XCTUnwrap(payload["presets"] as? [[String: Any]])
        return try XCTUnwrap(
            rows.first { ($0["name"] as? String) == name }?["id"] as? String)
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
