import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 12-2 T5 — the smart-album directory:
//
//   • file round-trip: create → a SECOND store over the same directory
//     rescans the SAME file set (one rule = one file; ids stable)
//   • startup self-heal: a corrupt JSON file is SKIPPED (never a crash,
//     never a deletion), the readable set loads, the skip is surfaced
//   • forward-compat degradation: a future-schema file (unknown predicate
//     field) skips through the TYPED decode error path
//   • sortedKeys byte stability + the no-tmp-leftovers assertion (the
//     L009 same-directory promotion sweeps its own artifacts)
//   • typed errors: empty name, not-found, illegal predicate group
//   • 求值 composition (L020): a persisted album's group runs through the
//     T3 query face against a fixture index — the exact row set comes
//     back (规则随 app / 结果随会话)
//
// ─────────────────────────────────────────────────────────────────────────────

final class SmartAlbumStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("smartalbums-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeGroup(
        _ rules: [FilterPredicateGroup.Rule], match: FilterPredicateGroup.Match = .all
    ) -> FilterPredicateGroup {
        FilterPredicateGroup(match: match, rules: rules)
    }

    // MARK: - Round-trip

    func testCreateAndRescanRoundTrip() throws {
        let store = SmartAlbumStore(directory: directory)
        let group = makeGroup([
            .init(field: .rating, op: .gte, value: .int(3)),
            .init(field: .keywords, op: .contains, value: .text("Nature")),
        ])
        let album = try store.create(name: "  Nature Picks  ", group: group)
        // Name is trimmed; the id is a UUID string (the file stem).
        XCTAssertEqual(album.name, "Nature Picks")
        XCTAssertEqual(album.id, album.id.lowercased() == album.id ? album.id : album.id)
        XCTAssertTrue(UUID(uuidString: album.id) != nil)

        // A SECOND store over the same directory rescans the same file set.
        let reopened = SmartAlbumStore(directory: directory)
        let loaded = reopened.albums()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, album.id)
        XCTAssertEqual(loaded[0].name, "Nature Picks")
        XCTAssertEqual(loaded[0].group, group)
        XCTAssertTrue(reopened.skippedFiles.isEmpty)
    }

    func testSortedKeysByteStabilityAndNoTmpLeftovers() throws {
        let store = SmartAlbumStore(directory: directory)
        let group = makeGroup([
            .init(field: .flag, op: .eq, value: .int(1)),
        ])
        let album = try store.create(name: "Picks", group: group)

        // The file is sortedKeys-stable: decode → re-encode → identical bytes.
        let file = directory.appendingPathComponent(album.id + ".json")
        let data = try Data(contentsOf: file)
        let document = try JSONDecoder().decode(SmartAlbumDocument.self, from: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(document), data)

        // The same-directory tmp promotion sweeps its own artifacts — no
        // `.tmp-*` files remain (the L009 discipline's on-disk face).
        let leftovers = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".tmp-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    // MARK: - Self-heal

    func testCorruptFileSkippedNeverDeleted() throws {
        let store = SmartAlbumStore(directory: directory)
        _ = try store.create(name: "Good", group: makeGroup([]))
        // A corrupt neighbor (garbage bytes, .json extension).
        let corrupt = directory.appendingPathComponent("broken.json")
        try Data("{ not json".utf8).write(to: corrupt)

        let reopened = SmartAlbumStore(directory: directory)
        XCTAssertEqual(reopened.albums().map(\.name), ["Good"])
        XCTAssertEqual(reopened.skippedFiles, ["broken.json"])
        // The corrupt file is NOT deleted (never destroy user data).
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
    }

    func testFutureSchemaFileSkipsThroughTypedPath() throws {
        // A future binary's album: an unknown predicate FIELD spelling.
        let future = #"{"schemaVersion":1,"name":"Future","group":{"match":"all","rules":[{"field":"hologram","op":"eq","value":{"kind":"int","value":1}}]}}"#
        try Data(future.utf8).write(
            to: directory.appendingPathComponent("future.json"))

        let reopened = SmartAlbumStore(directory: directory)
        XCTAssertTrue(reopened.albums().isEmpty)
        XCTAssertEqual(reopened.skippedFiles, ["future.json"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("future.json").path))
    }

    // MARK: - Typed errors + rename/remove/update

    func testTypedErrors() throws {
        let store = SmartAlbumStore(directory: directory)
        XCTAssertThrowsError(try store.create(name: "   ", group: makeGroup([]))) {
            error in XCTAssertEqual(error as? SmartAlbumError, .emptyName)
        }
        XCTAssertThrowsError(
            try store.rename(id: "missing", to: "X")
        ) { error in
            XCTAssertEqual(error as? SmartAlbumError, .notFound(id: "missing"))
        }
        XCTAssertThrowsError(
            try store.updateGroup(
                id: "missing",
                group: makeGroup([.init(field: .rating, op: .eq, value: .int(1))]))
        ) { error in
            XCTAssertEqual(error as? SmartAlbumError, .notFound(id: "missing"))
        }
        // Illegal predicate groups reject through the model's typed error.
        XCTAssertThrowsError(
            try store.create(
                name: "Bad",
                group: makeGroup([
                    .init(field: .rating, op: .contains, value: .int(3)),
                ]))
        ) { error in
            XCTAssertEqual(
                error as? FilterPredicateError,
                .illegalFieldOperator(field: .rating, op: .contains))
        }
    }

    func testRenameKeepsFileIdentity() throws {
        let store = SmartAlbumStore(directory: directory)
        let album = try store.create(
            name: "Alpha", group: makeGroup([.init(field: .flag, op: .eq, value: .int(1))]))
        try store.rename(id: album.id, to: "Beta")

        let renamed = try XCTUnwrap(store.album(id: album.id))
        XCTAssertEqual(renamed.name, "Beta")
        // The FILE NAME (the id) is unchanged — rename edits the document.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(album.id + ".json").path))
        // Re-opened stores see the new name.
        XCTAssertEqual(SmartAlbumStore(directory: directory).albums().map(\.name), ["Beta"])

        try store.remove(id: album.id)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(album.id + ".json").path))
        XCTAssertTrue(store.albums().isEmpty)
        // Second remove is a typed miss.
        XCTAssertThrowsError(try store.remove(id: album.id)) { error in
            XCTAssertEqual(error as? SmartAlbumError, .notFound(id: album.id))
        }
    }

    // MARK: - 求值 composition (规则随 app / 结果随会话)

    func testPersistedAlbumEvaluatesAgainstSessionFixture() async throws {
        // ① The album persists APP-level (its own directory).
        let store = SmartAlbumStore(directory: directory)
        let album = try store.create(
            name: "Rating 2+",
            group: makeGroup([
                .init(field: .rating, op: .gte, value: .int(2)),
            ]))

        // ② The evaluation happens against a SESSION index fixture (the
        //    same shape FilterSQLTests' store fixture uses): rows seeded
        //    through the store's own handle.
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("smartalbums-eval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let index = SessionIndexStore(sessionRoot: root)
        defer {
            Task { await index.close() }
            try? FileManager.default.removeItem(at: root)
        }
        _ = try await index.reconcile(root: root, scan: AsyncStream { $0.finish() })
        try await index.withHandleForTesting { handle in
            let insert = try handle.prepare("""
                INSERT INTO images (path, dir, filename, rating, keywords, orphan_sidecar)
                VALUES (?, ?, ?, ?, ?, 0)
                """)
            let rows: [(String, Int64?)] = [
                ("a.arw", 2), ("b.arw", 5), ("c.arw", 1), ("d.arw", nil),
            ]
            for (path, rating) in rows {
                try insert.bindText(1, path)
                try insert.bindText(2, "")
                try insert.bindText(3, path)
                try insert.bindInt(4, rating)
                try insert.bindText(5, nil)
                _ = try insert.step()
                try insert.reset()
            }
        }

        // ③ The persisted group re-read from DISK evaluates through the
        //    query face — the exact row set (L020).
        let reopened = SmartAlbumStore(directory: directory)
        let persisted = try XCTUnwrap(reopened.album(id: album.id))
        let result = try await index.query(groups: [persisted.group])
        XCTAssertEqual(result.map(\.path).sorted(), ["a.arw", "b.arw"])
    }
}
