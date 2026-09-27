import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 16-3 T3 — the App-layer CatalogTreeModel (the whole tree in memory):
//
//   • configure + refresh = the WITH RECURSIVE walk landed in @Observable
//     state (tree + collections; revision bump per refresh)
//   • every mutation re-derives BOTH faces (the increment granularity =
//     full re-read — execution decision)
//   • the drag/drop BEFORE-target semantics (same-parent index adjust +
//     cross-parent relocation; the model refuses drops into the dragged
//     subtree before the store's cycle defense ever runs)
//   • the grid's classify faces: composite identity STRINGS split into
//     structured pairs
//
// Fixtures ride a real CatalogOrganizationStore over a temp .lcat (L009).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CatalogTreeModelTests: XCTestCase {

    private var tempDirectory: URL!
    private var catalogURL: URL!
    private var store: CatalogOrganizationStore!
    private var model: CatalogTreeModel!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-tree-\(UUID().uuidString)", isDirectory: true)
        catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
        store = CatalogOrganizationStore(databaseURL: catalogURL)
        model = CatalogTreeModel()
        model.configure(store: store)
    }

    override func tearDown() async throws {
        await store.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        model = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func seedImage(
        sessionID: String = "sess-a", relPath: String
    ) async throws {
        // A short-lived handle on the MainActor test context (no cross-
        // actor closure over the non-Sendable handle). The schema apply is
        // idempotent; the store opens the SAME file lazily afterwards.
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: catalogURL.path)
        defer { handle.close() }
        try CatalogIndexSchema.apply(to: handle)
        let insert = try handle.prepare(
            "INSERT INTO catalog_images (id, session_id, rel_path, filename) "
                + "VALUES (NULL, ?, ?, ?)")
        try insert.bindText(1, sessionID)
        try insert.bindText(2, relPath)
        try insert.bindText(3, relPath)
        _ = try insert.step()
    }

    // MARK: - Refresh (the whole-tree read)

    func testRefreshLoadsTreeAndCollections() async throws {
        let a = try await store.createCategory(name: "A")
        _ = try await store.createCategory(name: "A1", parentID: a)
        _ = try await store.createCollection(name: "Set")

        await model.refresh()
        let revisionAfterFirst = model.revision

        XCTAssertEqual(model.tree.map(\.name), ["A"])
        XCTAssertEqual(model.tree[0].children.map(\.name), ["A1"])
        XCTAssertEqual(model.collections.map(\.name), ["Set"])
        XCTAssertNil(model.lastErrorText)
        XCTAssertEqual(revisionAfterFirst, 1)

        // A second refresh bumps the revision (the views' onChange anchor).
        await model.refresh()
        XCTAssertEqual(model.revision, 2)
    }

    // MARK: - Mutations through the model (refresh rides each call)

    func testCreateRenameDeleteThroughModel() async throws {
        let created = await model.createCategory(name: "Root", parentID: nil)
        XCTAssertTrue(created)
        XCTAssertEqual(model.tree.map(\.name), ["Root"])

        // Child under the created node (via the model face).
        let childID = model.tree[0].id
        _ = await model.createCategory(name: "Child", parentID: childID)
        XCTAssertEqual(model.tree[0].children.map(\.name), ["Child"])

        await model.renameCategory(id: childID, to: "Renamed")
        XCTAssertEqual(model.tree.map(\.name), ["Renamed"])

        // Leaf-only delete passes through the model (the child first).
        await model.deleteCategory(id: model.tree[0].children[0].id)
        XCTAssertEqual(model.tree[0].children.count, 0)
        await model.deleteCategory(id: model.tree[0].id)
        XCTAssertTrue(model.tree.isEmpty)

        // A failed mutation surfaces the typed error text (non-empty parent).
        let parent = try await store.createCategory(name: "P")
        _ = try await store.createCategory(name: "C", parentID: parent)
        await model.deleteCategory(id: parent)
        XCTAssertNotNil(model.lastErrorText)
    }

    // MARK: - Drag/drop BEFORE-target semantics

    func testSameParentBeforeMove() async throws {
        let parent = try await store.createCategory(name: "P")
        var ids: [Int64] = []
        for name in ["N1", "N2", "N3", "N4"] {
            ids.append(try await store.createCategory(name: name, parentID: parent))
        }
        await model.refresh()

        // Drag N4 (index 3) before N2 (index 1): post-removal index of N2
        // is 1 → the result is N1, N4, N2, N3.
        await model.moveCategory(dragged: ids[3], before: ids[1])
        XCTAssertEqual(model.tree[0].children.map(\.name), ["N1", "N4", "N2", "N3"])

        // Drag N1 (index 0 now) before N3 (index 3): post-removal index of
        // N3 is 2 → N4, N2, N1, N3.
        await model.moveCategory(dragged: ids[0], before: ids[2])
        XCTAssertEqual(model.tree[0].children.map(\.name), ["N4", "N2", "N1", "N3"])
    }

    func testCrossParentBeforeMove() async throws {
        let a = try await store.createCategory(name: "A")
        let b = try await store.createCategory(name: "B")
        let a1 = try await store.createCategory(name: "A1", parentID: a)
        let a2 = try await store.createCategory(name: "A2", parentID: a)
        let b1 = try await store.createCategory(name: "B1", parentID: b)
        await model.refresh()

        // Drag A2 before B1 (cross-parent): A keeps [A1], B is [A2, B1].
        await model.moveCategory(dragged: a2, before: b1)
        XCTAssertEqual(model.tree[0].children.map(\.name), ["A1"])
        XCTAssertEqual(model.tree[1].children.map(\.name), ["A2", "B1"])

        // Drag B1 before A1 (cross-parent, back the other way).
        await model.moveCategory(dragged: b1, before: a1)
        XCTAssertEqual(model.tree[0].children.map(\.name), ["B1", "A1"])
        XCTAssertEqual(model.tree[1].children.map(\.name), ["A2"])
    }

    func testDropIntoOwnSubtreeRejectedByModel() async throws {
        let a = try await store.createCategory(name: "A")
        let a1 = try await store.createCategory(name: "A1", parentID: a)
        _ = try await store.createCategory(name: "A1a", parentID: a1)
        await model.refresh()

        // Drag A onto A1a — no call, no change, no error.
        await model.moveCategory(dragged: a, before: a1)
        XCTAssertEqual(model.tree.map(\.name), ["A"])
        XCTAssertEqual(model.tree[0].children.map(\.name), ["A1"])
        XCTAssertNil(model.lastErrorText)
    }

    // MARK: - Collections (the flat drag face)

    func testCollectionBeforeMove() async throws {
        let c1 = try await store.createCollection(name: "C1")
        let c2 = try await store.createCollection(name: "C2")
        let c3 = try await store.createCollection(name: "C3")
        await model.refresh()
        XCTAssertEqual(model.collections.map(\.name), ["C1", "C2", "C3"])

        // Drag C3 before C1.
        await model.moveCollection(dragged: c3, before: c1)
        XCTAssertEqual(model.collections.map(\.name), ["C3", "C1", "C2"])
        // Drag C2 before C1 (now index 1).
        await model.moveCollection(dragged: c2, before: c1)
        XCTAssertEqual(model.collections.map(\.name), ["C3", "C2", "C1"])
    }

    // MARK: - Classify faces (identity-string splitting)

    func testAssignAndRevokeFromIdentityStrings() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        try await seedImage(relPath: "IMG_0002.arw")
        let a = try await store.createCategory(name: "A")
        await model.refresh()

        // The grid's `sessionID/relPath` spelling, verbatim.
        let identities = [
            "sess-a/IMG_0001.arw", "sess-a/IMG_0002.arw",
        ]
        await model.assign(identities: identities, toCategoryID: a)

        let count = try await store.memberCount(categoryID: a)
        XCTAssertEqual(count, 2)

        await model.revoke(
            identities: ["sess-a/IMG_0002.arw"], fromCategoryID: a)
        let after = try await store.memberCount(categoryID: a)
        XCTAssertEqual(after, 1)
    }

    func testCollectionAssignThroughModel() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        let c = try await store.createCollection(name: "Set")
        await model.refresh()
        await model.assign(
            identities: ["sess-a/IMG_0001.arw"], toCollectionID: c)
        let count = try await store.memberCount(collectionID: c)
        XCTAssertEqual(count, 1)
    }
}
