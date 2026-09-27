import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 16-3 — the organization face (CatalogOrganizationStore):
//
//   T1  categories CRUD + drag re-order (ONE transaction, integer renumber
//       0…n-1 gap-free) + cycle defense (self / subtree) + leaf-only delete
//       + WITH RECURSIVE tree reads + collections CRUD/reorder/cascade
//   T2  classification (single + 10k bulk, one transaction, multi-membership,
//       INSERT OR IGNORE idempotence) + COUNT-memo invalidation + the
//       projection interaction (UPSERT keeps id → membership survives;
//       reconcile-delete removes the row AND its memberships) + PERF-07
//       zero-pixel semantics
//   T4  transaction atomicity (injected failure ROLLS BACK byte-exact) +
//       the no-orphan exhaustive proof + the read/write concurrency smoke
//
// L020: content-level assertions everywhere (exact sequences, exact trees —
// never just counts). L009: fixtures on /tmp only. Fixtures seed
// catalog_images rows through the store's own handle (withHandleForTesting)
// so the classification faces can resolve identities without a projector.
// ─────────────────────────────────────────────────────────────────────────────

final class CatalogOrganizationTests: XCTestCase {

    private var tempDirectory: URL!
    private var catalogURL: URL!
    private var store: CatalogOrganizationStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-org-\(UUID().uuidString)", isDirectory: true)
        catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
        store = CatalogOrganizationStore(databaseURL: catalogURL)
    }

    override func tearDown() async throws {
        await store.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        try await super.tearDown()
    }

    // MARK: - Assertion helpers (XCTAssertThrowsError cannot host `await`)

    private func expectOrganizationError<T>(
        _ expected: CatalogOrganizationError,
        file: StaticString = #filePath, line: UInt = #line,
        _ body: () async throws -> T
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected), got success", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? CatalogOrganizationError, expected,
                "unexpected error: \(error)", file: file, line: line)
        }
    }

    // MARK: - Fixture helpers

    /// Seed one catalog_images row (the classification faces' resolution
    /// target; direct handle — full column control).
    private func seedImage(
        sessionID: String = "sess-a", relPath: String
    ) async throws {
        try await store.withHandleForTesting { handle in
            let insert = try handle.prepare("""
                INSERT INTO catalog_images (
                  id, session_id, rel_path, filename, capture_date, rating
                ) VALUES (NULL, ?, ?, ?, ?, ?)
                """)
            try insert.bindText(1, sessionID)
            try insert.bindText(2, relPath)
            try insert.bindText(3, (relPath as NSString).lastPathComponent)
            try insert.bindDouble(4, 1_700_000_000)
            try insert.bindInt(5, 3)
            _ = try insert.step()
        }
    }

    private func img(
        _ relPath: String, _ sessionID: String = "sess-a"
    ) -> CatalogImageIdentity {
        CatalogImageIdentity(sessionID: sessionID, relPath: relPath)
    }

    /// Count rows through the store's own handle.
    private func countRows(_ sql: String, bind id: Int64? = nil) async throws -> Int {
        try await store.withHandleForTesting { handle -> Int in
            let statement = try handle.prepare(sql)
            if let id { try statement.bindInt(1, id) }
            _ = try statement.step()
            return Int(statement.columnInt(0) ?? -1)
        }
    }

    /// Build the canonical three-level tree:
    ///   A            B
    ///   ├─ A1        └─ B1
    ///   │  └─ A1a
    ///   └─ A2
    private func buildCanonicalTree() async throws
        -> (a: Int64, b: Int64, a1: Int64, a2: Int64, a1a: Int64, b1: Int64) {
        let a = try await store.createCategory(name: "A")
        let b = try await store.createCategory(name: "B")
        let a1 = try await store.createCategory(name: "A1", parentID: a)
        let a2 = try await store.createCategory(name: "A2", parentID: a)
        let a1a = try await store.createCategory(name: "A1a", parentID: a1)
        let b1 = try await store.createCategory(name: "B1", parentID: b)
        return (a, b, a1, a2, a1a, b1)
    }

    // MARK: - T1: tree CRUD + reads

    func testCreateAndReadTreeAssemblesThreeLevels() async throws {
        let ids = try await buildCanonicalTree()

        let tree = try await store.readTree()
        // Two roots, sibling order = insertion.
        XCTAssertEqual(tree.map(\.name), ["A", "B"])
        XCTAssertEqual(tree.map(\.id), [ids.a, ids.b])
        // A's children in order; A1's child nested.
        let a = tree[0]
        XCTAssertEqual(a.children.map(\.name), ["A1", "A2"])
        XCTAssertEqual(a.children[0].children.map(\.name), ["A1a"])
        XCTAssertEqual(a.children[0].children[0].id, ids.a1a)
        // sort_order gap-free within each sibling set (L020).
        XCTAssertEqual(a.children.map(\.sortOrder), [0, 1])
        XCTAssertEqual(a.children[0].children.map(\.sortOrder), [0])
        XCTAssertEqual(tree[1].children.map(\.sortOrder), [0])
    }

    func testCreateUnderMissingParentThrows() async throws {
        await expectOrganizationError(.parentNotFound(id: 999_999)) {
            try await self.store.createCategory(name: "X", parentID: 999_999)
        }
        // Nothing was created.
        let tree = try await store.readTree()
        XCTAssertEqual(tree.count, 0)
    }

    func testCreateBlankNameThrows() async throws {
        await expectOrganizationError(.invalidName) {
            try await self.store.createCategory(name: "   ")
        }
        await expectOrganizationError(.invalidName) {
            try await self.store.createCategory(name: "")
        }
        let tree = try await store.readTree()
        XCTAssertEqual(tree.count, 0)
    }

    func testRenameCategory() async throws {
        _ = try await store.createCategory(name: "A")
        try await store.renameCategory(id: 1, to: "  Alpha  ")
        let tree = try await store.readTree()
        XCTAssertEqual(tree.map(\.name), ["Alpha"])  // trimmed
    }

    func testRenameMissingCategoryThrows() async throws {
        await expectOrganizationError(.notFound(kind: "category", id: 42)) {
            try await self.store.renameCategory(id: 42, to: "Nope")
        }
    }

    func testRenameBlankThrows() async throws {
        _ = try await store.createCategory(name: "A")
        await expectOrganizationError(.invalidName) {
            try await self.store.renameCategory(id: 1, to: "  ")
        }
        let tree = try await store.readTree()
        XCTAssertEqual(tree.map(\.name), ["A"])  // unchanged
    }

    // MARK: - T1: drag re-order (same-parent + cross-parent, ONE transaction)

    func testSameParentReorderExactSequence() async throws {
        let a = try await store.createCategory(name: "A")
        var ids: [Int64] = []
        for name in ["N1", "N2", "N3", "N4", "N5"] {
            ids.append(try await store.createCategory(name: name, parentID: a))
        }

        // Drag N4 to the front.
        try await store.moveCategory(id: ids[3], newParentID: a, index: 0)
        var tree = try await store.readTree()
        XCTAssertEqual(tree[0].children.map(\.name), ["N4", "N1", "N2", "N3", "N5"])
        // Integer renumber: 0…n-1, NO holes (L020 exact).
        XCTAssertEqual(tree[0].children.map(\.sortOrder), [0, 1, 2, 3, 4])

        // Drag N4 between N2 and N3 (index 2).
        try await store.moveCategory(id: ids[3], newParentID: a, index: 2)
        tree = try await store.readTree()
        XCTAssertEqual(tree[0].children.map(\.name), ["N1", "N2", "N4", "N3", "N5"])
        XCTAssertEqual(tree[0].children.map(\.sortOrder), [0, 1, 2, 3, 4])
    }

    func testCrossParentMoveRewritesBothSiblingSets() async throws {
        let ids = try await buildCanonicalTree()

        // Move A2 (A's second child) under B1, appended.
        try await store.moveCategory(id: ids.a2, newParentID: ids.b1, index: nil)
        let tree = try await store.readTree()
        // A's set renumbered gap-free: [A1].
        XCTAssertEqual(tree[0].children.map(\.name), ["A1"])
        XCTAssertEqual(tree[0].children.map(\.sortOrder), [0])
        // B's set unchanged: [B1]; B1 now has A2.
        XCTAssertEqual(tree[1].children.map(\.name), ["B1"])
        let b1 = tree[1].children[0]
        XCTAssertEqual(b1.children.map(\.name), ["A2"])
        XCTAssertEqual(b1.children.map(\.sortOrder), [0])
        // The moved node's parent link is right.
        XCTAssertEqual(b1.children[0].parentID, ids.b1)
        XCTAssertEqual(b1.children[0].children.map(\.name), [])  // A2 is a leaf here
    }

    func testCrossParentMoveAtIndex() async throws {
        let ids = try await buildCanonicalTree()
        _ = try await store.createCategory(name: "B2", parentID: ids.b)

        // Move A1 (with its subtree A1a) between B1 and B2.
        try await store.moveCategory(id: ids.a1, newParentID: ids.b, index: 1)
        let tree = try await store.readTree()
        let b = tree[1]
        XCTAssertEqual(b.children.map(\.name), ["B1", "A1", "B2"])
        XCTAssertEqual(b.children.map(\.sortOrder), [0, 1, 2])
        // The subtree moved WITH the node (A1a still under A1).
        XCTAssertEqual(b.children[1].children.map(\.name), ["A1a"])
        // A's remaining set renumbered.
        XCTAssertEqual(tree[0].children.map(\.name), ["A2"])
        XCTAssertEqual(tree[0].children.map(\.sortOrder), [0])
    }

    func testMoveWithoutIndexAppends() async throws {
        let ids = try await buildCanonicalTree()
        try await store.moveCategory(id: ids.a1, newParentID: ids.b)  // append
        let tree = try await store.readTree()
        XCTAssertEqual(tree[1].children.map(\.name), ["B1", "A1"])
        XCTAssertEqual(tree[1].children.map(\.sortOrder), [0, 1])
    }

    // MARK: - T1: cycle defense

    func testMoveToSelfThrows() async throws {
        let a = try await store.createCategory(name: "A")
        await expectOrganizationError(.cycleDetected(id: a)) {
            try await self.store.moveCategory(id: a, newParentID: a)
        }
    }

    func testMoveIntoOwnSubtreeThrows() async throws {
        let ids = try await buildCanonicalTree()
        // A1 → under its own child A1a: refused.
        await expectOrganizationError(.cycleDetected(id: ids.a1)) {
            try await self.store.moveCategory(id: ids.a1, newParentID: ids.a1a)
        }
        // Deeper: A → under A1a (grandchild): refused too.
        await expectOrganizationError(.cycleDetected(id: ids.a)) {
            try await self.store.moveCategory(id: ids.a, newParentID: ids.a1a)
        }
        // The tree is untouched by the refused moves.
        let tree = try await store.readTree()
        XCTAssertEqual(tree.map(\.name), ["A", "B"])
        XCTAssertEqual(tree[0].children.map(\.name), ["A1", "A2"])
    }

    func testMoveMissingNodeThrows() async throws {
        await expectOrganizationError(.notFound(kind: "category", id: 1234)) {
            try await self.store.moveCategory(id: 1234, newParentID: nil)
        }
    }

    // MARK: - T1: delete (leaf-only + idempotence + cascade)

    func testDeleteNonEmptyParentRefused() async throws {
        let ids = try await buildCanonicalTree()
        // A has children — refused.
        do {
            _ = try await store.deleteCategory(id: ids.a)
            XCTFail("expected categoryHasChildren")
        } catch let error as CatalogOrganizationError {
            guard case let .categoryHasChildren(id, count) = error else {
                return XCTFail("unexpected error kind: \(error)")
            }
            XCTAssertEqual(id, ids.a)
            XCTAssertEqual(count, 2)
        }
        // A1a is a leaf — deletable.
        let deleted = try await store.deleteCategory(id: ids.a1a)
        XCTAssertEqual(deleted, true)
        // A1 is now a leaf — deletable.
        let removedA1 = try await store.deleteCategory(id: ids.a1)
        XCTAssertEqual(removedA1, true)
        // A2 is a leaf too.
        let removedA2 = try await store.deleteCategory(id: ids.a2)
        XCTAssertEqual(removedA2, true)
        // Now A — deletable (top-down disposal works).
        let removedA = try await store.deleteCategory(id: ids.a)
        XCTAssertEqual(removedA, true)
        let tree = try await store.readTree()
        XCTAssertEqual(tree.map(\.name), ["B"])
    }

    func testDeleteLeafCascadesMemberships() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        let a = try await store.createCategory(name: "A")
        _ = try await store.assign(images: [img("IMG_0001.arw")], toCategoryID: a)
        let before = try await countRows(
            "SELECT COUNT(*) FROM image_categories WHERE category_id = ?", bind: a)
        XCTAssertEqual(before, 1)

        let removed = try await store.deleteCategory(id: a)
        XCTAssertEqual(removed, true)
        let after = try await countRows(
            "SELECT COUNT(*) FROM image_categories WHERE category_id = ?", bind: a)
        XCTAssertEqual(after, 0)  // no orphan membership rows
    }

    func testDeleteMissingIdempotentNoOp() async throws {
        let a = try await store.createCategory(name: "A")
        let removed = try await store.deleteCategory(id: a)
        XCTAssertEqual(removed, true)
        // Second delete: a no-op (false), NOT an error — idempotent.
        let removedAgain = try await store.deleteCategory(id: a)
        XCTAssertEqual(removedAgain, false)
        let removedMissing = try await store.deleteCategory(id: 987_654)
        XCTAssertEqual(removedMissing, false)
    }

    func testDeleteThenTreeReadConsistent() async throws {
        let ids = try await buildCanonicalTree()
        try await store.deleteCategory(id: ids.a1a)
        try await store.deleteCategory(id: ids.a2)
        let tree = try await store.readTree()
        // The walked tree contains EXACTLY the live nodes, in order.
        XCTAssertEqual(tree.map(\.name), ["A", "B"])
        XCTAssertEqual(tree[0].children.map(\.name), ["A1"])
        XCTAssertEqual(tree[1].children.map(\.name), ["B1"])
        // And the recursion saw everything (no orphans dropped silently).
        let liveCount = try await countRows("SELECT COUNT(*) FROM categories")
        func countNodes(_ nodes: [CatalogTreeNode]) -> Int {
            nodes.reduce(0) { $0 + 1 + countNodes($1.children) }
        }
        XCTAssertEqual(liveCount, countNodes(tree))
    }

    // MARK: - T1: subtree reads

    func testSubtreeIDsIncludeSelfAndDescendants() async throws {
        let ids = try await buildCanonicalTree()
        let subtree = try await store.subtreeIDs(of: ids.a)
        XCTAssertEqual(subtree, Set([ids.a, ids.a1, ids.a2, ids.a1a]))
        let leaf = try await store.subtreeIDs(of: ids.a1a)
        XCTAssertEqual(leaf, Set([ids.a1a]))
    }

    // MARK: - T1: collections CRUD + reorder + cascade

    func testCollectionsCRUD() async throws {
        let c1 = try await store.createCollection(name: "Trip 2026")
        let c2 = try await store.createCollection(name: "Selects")
        var rows = try await store.readCollections()
        XCTAssertEqual(rows.map(\.name), ["Trip 2026", "Selects"])
        XCTAssertEqual(rows.map(\.sortOrder), [0, 1])

        try await store.renameCollection(id: c1, to: "Trip 2027")
        rows = try await store.readCollections()
        XCTAssertEqual(rows.map(\.name), ["Trip 2027", "Selects"])

        await expectOrganizationError(.invalidName) {
            try await self.store.createCollection(name: " ")
        }
        await expectOrganizationError(.invalidName) {
            try await self.store.renameCollection(id: c2, to: "")
        }

        // Missing rename = typed error; missing delete = idempotent no-op.
        await expectOrganizationError(.notFound(kind: "collection", id: 555)) {
            try await self.store.renameCollection(id: 555, to: "X")
        }
        let removedC2 = try await store.deleteCollection(id: c2)
        XCTAssertEqual(removedC2, true)
        let removedC2Again = try await store.deleteCollection(id: c2)
        XCTAssertEqual(removedC2Again, false)
        rows = try await store.readCollections()
        XCTAssertEqual(rows.map(\.name), ["Trip 2027"])
        XCTAssertEqual(rows.map(\.sortOrder), [0])
    }

    func testCollectionDeleteCascadesMemberships() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        try await seedImage(relPath: "IMG_0002.arw")
        let c = try await store.createCollection(name: "Set")
        _ = try await store.assign(
            images: [img("IMG_0001.arw"), img("IMG_0002.arw")],
            toCollectionID: c)
        let before = try await countRows(
            "SELECT COUNT(*) FROM image_collections WHERE collection_id = ?", bind: c)
        XCTAssertEqual(before, 2)

        let removed = try await store.deleteCollection(id: c)
        XCTAssertEqual(removed, true)
        let after = try await countRows(
            "SELECT COUNT(*) FROM image_collections WHERE collection_id = ?", bind: c)
        XCTAssertEqual(after, 0)
        // The images themselves are untouched (the collection is the asset).
        let imageCount = try await countRows("SELECT COUNT(*) FROM catalog_images")
        XCTAssertEqual(imageCount, 2)
    }

    func testCollectionReorderExactSequence() async throws {
        let c1 = try await store.createCollection(name: "C1")
        let c2 = try await store.createCollection(name: "C2")
        let c3 = try await store.createCollection(name: "C3")
        let c4 = try await store.createCollection(name: "C4")

        try await store.moveCollection(id: c4, index: 0)
        var rows = try await store.readCollections()
        XCTAssertEqual(rows.map(\.name), ["C4", "C1", "C2", "C3"])
        XCTAssertEqual(rows.map(\.sortOrder), [0, 1, 2, 3])

        try await store.moveCollection(id: c1, index: 3)
        rows = try await store.readCollections()
        XCTAssertEqual(rows.map(\.name), ["C4", "C2", "C3", "C1"])
        XCTAssertEqual(rows.map(\.sortOrder), [0, 1, 2, 3])
    }

    // MARK: - T1: reopen persistence

    func testReopenPreservesTree() async throws {
        _ = try await buildCanonicalTree()
        await store.close()
        let reopened = CatalogOrganizationStore(databaseURL: catalogURL)
        let tree = try await reopened.readTree()
        XCTAssertEqual(tree.map(\.name), ["A", "B"])
        XCTAssertEqual(tree[0].children.count, 2)
        await reopened.close()
    }
}
