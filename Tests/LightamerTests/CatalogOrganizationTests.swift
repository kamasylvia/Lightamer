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
    private var sessionRoot: URL!
    private var defaultsSuiteName: String!
    private var store: CatalogOrganizationStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-org-\(UUID().uuidString)", isDirectory: true)
        catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot, withIntermediateDirectories: true)
        defaultsSuiteName = "catalog-org-tests-\(UUID().uuidString)"
        // The projector's enable guard rides this suite (the projection-
        // interaction legs use a REAL CatalogProjector).
        CatalogPreferences.setCatalogsEnabled(true, defaultsSuiteName: defaultsSuiteName)
        store = CatalogOrganizationStore(databaseURL: catalogURL)
    }

    override func tearDown() async throws {
        await store.close()
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
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

    /// Bulk seed in ONE transaction (the 10k shape needs a fast fixture).
    private func bulkSeedImages(count: Int, sessionID: String) async throws {
        try await store.withHandleForTesting { handle in
            try handle.exec("BEGIN IMMEDIATE")
            let insert = try handle.prepare("""
                INSERT INTO catalog_images (
                  id, session_id, rel_path, filename, capture_date, rating
                ) VALUES (NULL, ?, ?, ?, ?, ?)
                """)
            for index in 0..<count {
                let relPath = String(format: "IMG_%05d.arw", index)
                try insert.bindText(1, sessionID)
                try insert.bindText(2, relPath)
                try insert.bindText(3, relPath)
                try insert.bindDouble(4, 1_700_000_000)
                try insert.bindInt(5, 3)
                _ = try insert.step()
                try insert.reset()
            }
            try handle.exec("COMMIT")
        }
    }

    /// A stable catalog row id (the reference key the memberships point at).
    private func imageID(sessionID: String, relPath: String) async throws -> Int64? {
        try await store.withHandleForTesting { handle -> Int64? in
            let statement = try handle.prepare(
                "SELECT id FROM catalog_images WHERE session_id = ? AND rel_path = ?")
            try statement.bindText(1, sessionID)
            try statement.bindText(2, relPath)
            guard try statement.step() else { return nil }
            return statement.columnInt(0)
        }
    }

    // MARK: - lindex fixtures (the projection-interaction legs)

    private var lindexURL: URL {
        SessionIndexSchema.databaseURL(forSessionRoot: sessionRoot)
    }

    /// A minimal lindex fixture (path/epoch essentials only — the projector
    /// reads the full mirror set; NULLs are fine for this plan's view).
    private func makeLindex(rows: [String], epoch: Int64) async throws {
        try FileManager.default.createDirectory(
            at: lindexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: lindexURL.path)
        defer { handle.close() }
        try SessionIndexSchema.apply(to: handle)
        let stamp = try handle.prepare(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('scan_epoch', ?)")
        try stamp.bindText(1, String(epoch))
        _ = try stamp.step()
        for relPath in rows {
            let insert = try handle.prepare("""
                INSERT INTO images (
                  path, dir, filename, file_size, file_mtime, scan_epoch,
                  sidecar_present, rating, orphan_sidecar
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            try insert.bindText(1, relPath)
            try insert.bindText(2, "")
            try insert.bindText(3, (relPath as NSString).lastPathComponent)
            try insert.bindInt(4, 1000)
            try insert.bindDouble(5, 1_700_000_000)
            try insert.bindInt(6, epoch)
            try insert.bindInt(7, 1)
            try insert.bindInt(8, 3)
            try insert.bindInt(9, 0)
            _ = try insert.step()
        }
    }

    private func updateLindexRow(_ relPath: String, rating: Int64, epoch: Int64) async throws {
        let handle = try SQLiteHandle(path: lindexURL.path)
        defer { handle.close() }
        let update = try handle.prepare(
            "UPDATE images SET rating = ?, scan_epoch = ? WHERE path = ?")
        try update.bindInt(1, rating)
        try update.bindInt(2, epoch)
        try update.bindText(3, relPath)
        _ = try update.step()
        try stampLindexEpoch(handle, epoch)
    }

    private func deleteLindexRow(_ relPath: String, epoch: Int64) async throws {
        let handle = try SQLiteHandle(path: lindexURL.path)
        defer { handle.close() }
        let delete = try handle.prepare("DELETE FROM images WHERE path = ?")
        try delete.bindText(1, relPath)
        _ = try delete.step()
        try stampLindexEpoch(handle, epoch)
    }

    private func stampLindexEpoch(_ handle: SQLiteHandle, _ epoch: Int64) throws {
        let stamp = try handle.prepare(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('scan_epoch', ?)")
        try stamp.bindText(1, String(epoch))
        _ = try stamp.step()
    }

    /// The session_id the projector minted for the fixture root.
    private var projectedSessionID: String? {
        get async throws {
            try await store.withHandleForTesting { handle -> String? in
                let statement = try handle.prepare(
                    "SELECT session_id FROM catalog_sessions LIMIT 1")
                guard try statement.step() else { return nil }
                return statement.columnText(0)
            }
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

    // MARK: - T2: classification (single + bulk + multi-membership)

    func testSingleAssignAndRevoke() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        let a = try await store.createCategory(name: "A")

        let result = try await store.assign(
            images: [img("IMG_0001.arw")], toCategoryID: a)
        XCTAssertEqual(result.resolved, 1)
        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.skipped, 0)
        var count = try await store.memberCount(categoryID: a)
        XCTAssertEqual(count, 1)

        let revoked = try await store.revoke(
            images: [img("IMG_0001.arw")], fromCategoryID: a)
        XCTAssertEqual(revoked.inserted, 1)  // one row deleted
        count = try await store.memberCount(categoryID: a)
        XCTAssertEqual(count, 0)
    }

    func testMultiMembershipThreeCategoriesTwoCollectionsOneTransaction() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        var categoryIDs: [Int64] = []
        var collectionIDs: [Int64] = []
        for name in ["C1", "C2", "C3"] {
            categoryIDs.append(try await store.createCategory(name: name))
        }
        for name in ["S1", "S2"] {
            collectionIDs.append(try await store.createCollection(name: name))
        }

        // One image into THREE categories and TWO collections.
        let image = [img("IMG_0001.arw")]
        for id in categoryIDs {
            let r = try await store.assign(images: image, toCategoryID: id)
            XCTAssertEqual(r.inserted, 1)
        }
        for id in collectionIDs {
            let r = try await store.assign(images: image, toCollectionID: id)
            XCTAssertEqual(r.inserted, 1)
        }
        for id in categoryIDs {
            let count612 = try await store.memberCount(categoryID: id)
            XCTAssertEqual(count612, 1)
        }
        for id in collectionIDs {
            let count615 = try await store.memberCount(collectionID: id)
            XCTAssertEqual(count615, 1)
        }
    }

    func testAssignIdempotentInsertOrIgnore() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        let a = try await store.createCategory(name: "A")
        let image = [img("IMG_0001.arw")]

        let first = try await store.assign(images: image, toCategoryID: a)
        XCTAssertEqual(first.inserted, 1)
        // The repeat is a NO-OP on the row set (INSERT OR IGNORE).
        let second = try await store.assign(images: image, toCategoryID: a)
        XCTAssertEqual(second.inserted, 0)
        let count629 = try await store.memberCount(categoryID: a)
        XCTAssertEqual(count629, 1)
    }

    func testAssignUnknownIdentityIsSkipped() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        let a = try await store.createCategory(name: "A")
        let result = try await store.assign(
            images: [img("IMG_0001.arw"), img("MISSING.arw")], toCategoryID: a)
        XCTAssertEqual(result.resolved, 1)
        XCTAssertEqual(result.skipped, 1)
        let count639 = try await store.memberCount(categoryID: a)
        XCTAssertEqual(count639, 1)
    }

    /// The 10k bulk shape: ONE transaction of prepared INSERT OR IGNORE.
    /// Budget ≤5s (the PERF-07 semantic continuation); the real number is
    /// ledgered in perf.md. ZERO pixels: the classification path holds ONLY
    /// the catalog handle — the fixture directory gains no session-side
    /// artifact and the API signature carries no image data at all.
    func testBulkTenThousandAssignUnderFiveSeconds() async throws {
        let total = 10_000
        try await bulkSeedImages(count: total, sessionID: "sess-bulk")
        let a = try await store.createCategory(name: "Bulk")

        let images = (0..<total).map {
            CatalogImageIdentity(sessionID: "sess-bulk", relPath: String(format: "IMG_%05d.arw", $0))
        }
        let started = Date()
        let result = try await store.assign(images: images, toCategoryID: a)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(result.resolved, total)
        XCTAssertEqual(result.inserted, total)
        XCTAssertLessThan(elapsed, 5.0, "10k assign took \(elapsed)s")
        let totalMembers = try await store.memberCount(categoryID: a)
        XCTAssertEqual(totalMembers, total)

        // Zero-pixel probe: no session-side artifacts appeared next to the
        // catalog file (the write path touched ONLY the catalog).
        let sidecars = try FileManager.default.contentsOfDirectory(
            at: tempDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "catalog.lcat"
                && !$0.lastPathComponent.hasPrefix("catalog.lcat-")
                && $0.lastPathComponent != "session" }  // setUp's fixture root
        XCTAssertTrue(sidecars.isEmpty, "unexpected artifacts: \(sidecars.map(\.lastPathComponent))")

        print("PERF-16-3 10k assign seconds=\(String(format: "%.3f", elapsed))")
    }

    /// The COUNT-memo dies with a classify COMMIT: combo counts ride the
    /// memo (compute once), the invalidator hook fires after the assign,
    /// and the next count RE-computes.
    func testCountMemoInvalidatedAfterClassifyCommit() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        let counter = LockedCounter()
        let catalogStore = CatalogIndexStore(databaseURL: catalogURL)
        await catalogStore.setCountObserver { counter.bump() }
        await store.setCountsInvalidator { await catalogStore.invalidateCounts() }

        let combo = FilterPredicateGroup(match: .all, rules: [
            FilterPredicateGroup.Rule(field: .rating, op: .gte, value: .int(1)),
            FilterPredicateGroup.Rule(field: .rating, op: .lte, value: .int(5)),
        ])
        _ = try await catalogStore.count(groups: [combo])
        XCTAssertEqual(counter.value, 1, "first combo count computes")
        _ = try await catalogStore.count(groups: [combo])
        XCTAssertEqual(counter.value, 1, "second rides the memo")

        // The classify write kills the memo through the hook.
        let a = try await store.createCategory(name: "A")
        _ = try await store.assign(images: [img("IMG_0001.arw")], toCategoryID: a)
        _ = try await catalogStore.count(groups: [combo])
        XCTAssertEqual(counter.value, 2, "memo re-computed after classify COMMIT")
        await catalogStore.close()
    }

    // MARK: - T2: projection interaction (the organization-data view)

    /// The projection UPSERT KEEPS the row id (16-1 R1) → memberships
    /// keyed on that id SURVIVE a changed-row re-projection.
    func testProjectionUpsertKeepsIdMembershipSurvives() async throws {
        try await makeLindex(
            rows: ["IMG_0001.arw", "IMG_0002.arw"], epoch: 1)
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        var result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.added, 2)

        let sessionID = try await projectedSessionID!
        let a = try await store.createCategory(name: "A")
        _ = try await store.assign(
            images: [img("IMG_0001.arw", sessionID)], toCategoryID: a)

        let idBefore = try await imageID(sessionID: sessionID, relPath: "IMG_0001.arw")

        // The lindex row CHANGES (rating) + the watermark bumps → the
        // changed-row UPSERT must keep the id.
        try await updateLindexRow("IMG_0001.arw", rating: 5, epoch: 2)
        result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.changed, 1)

        let idAfter = try await imageID(sessionID: projectedSessionID!, relPath: "IMG_0001.arw")
        XCTAssertEqual(idAfter, idBefore, "UPSERT kept the id")
        let count729 = try await store.memberCount(categoryID: a)
        XCTAssertEqual(count729, 1,
                       "membership survived the re-projection")
        await projector.close()
    }

    /// The reconcile DELETE closes a removed lindex row AND its membership
    /// rows (no dangling organization references to deleted images).
    func testReconcileDeleteRemovesMemberships() async throws {
        try await makeLindex(
            rows: ["IMG_0001.arw", "IMG_0002.arw"], epoch: 1)
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        _ = try await projector.project(sessionRoot: sessionRoot)

        let sessionID = try await projectedSessionID!
        let a = try await store.createCategory(name: "A")
        _ = try await store.assign(
            images: [img("IMG_0001.arw", sessionID), img("IMG_0002.arw", sessionID)],
            toCategoryID: a)
        let assignedCount = try await store.memberCount(categoryID: a)
        XCTAssertEqual(assignedCount, 2)

        // The lindex side loses IMG_0002; the reconcile closes the catalog
        // row and the membership rides along.
        try await deleteLindexRow("IMG_0002.arw", epoch: 2)
        let result = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(result.removed, 1)

        let count754 = try await store.memberCount(categoryID: a)
        XCTAssertEqual(count754, 1)
        let orphans = try await countRows(
            """
            SELECT COUNT(*) FROM image_categories WHERE category_id = ?
              AND catalog_image_id NOT IN (SELECT id FROM catalog_images)
            """, bind: a)
        XCTAssertEqual(orphans, 0)
        await projector.close()
    }

    // MARK: - T4: transaction atomicity (injected ROLLBACK, L010 pattern)

    /// An injected failure INSIDE the reorder transaction (after the
    /// sibling rewrites, before COMMIT) must ROLL BACK to the EXACT prior
    /// tree — every sort_order and every parent link byte-identical.
    func testReorderInjectionRollsBackByteExact() async throws {
        let a = try await store.createCategory(name: "A")
        var ids: [Int64] = []
        for name in ["N1", "N2", "N3", "N4"] {
            ids.append(try await store.createCategory(name: name, parentID: a))
        }
        let before = try await store.readTree()

        await store.setFailureInjection(.afterSiblingRewrites)
        do {
            try await store.moveCategory(id: ids[3], newParentID: nil)
            XCTFail("expected the injected failure")
        } catch is CatalogOrganizationInjectedFailure {
            // expected
        }
        await store.setFailureInjection(.none)

        let after = try await store.readTree()
        XCTAssertEqual(after, before, "tree byte-identical after ROLLBACK")

        // The reopened file agrees (the rollback persisted, not just the
        // in-memory snapshot).
        await store.close()
        let reopened = CatalogOrganizationStore(databaseURL: catalogURL)
        let treeAfterReopen = try await reopened.readTree()
        XCTAssertEqual(treeAfterReopen, before)
        await reopened.close()
    }

    /// A cross-parent move interrupted mid-transaction leaves NEITHER
    /// sibling set half-rewritten (the parent_id flip included).
    func testCrossParentMoveInjectionRollsBackFully() async throws {
        let ids = try await buildCanonicalTree()
        let before = try await store.readTree()

        await store.setFailureInjection(.afterSiblingRewrites)
        do {
            try await store.moveCategory(id: ids.a2, newParentID: ids.b1)
            XCTFail("expected the injected failure")
        } catch is CatalogOrganizationInjectedFailure {
            // expected
        }
        await store.setFailureInjection(.none)

        let after = try await store.readTree()
        XCTAssertEqual(after, before)
        // A2's parent is still A (the UPDATE rolled back too).
        let tree = after
        XCTAssertEqual(tree[0].children.map(\.name), ["A1", "A2"])
        XCTAssertEqual(tree[1].children[0].children.map(\.name), [])
    }

    /// An injected failure after the membership inserts (before COMMIT)
    /// leaves ZERO half-committed rows.
    func testAssignInjectionRollsBackZeroHalfCommitted() async throws {
        try await seedImage(relPath: "IMG_0001.arw")
        try await seedImage(relPath: "IMG_0002.arw")
        let a = try await store.createCategory(name: "A")
        let before = try await countRows("SELECT COUNT(*) FROM image_categories")
        XCTAssertEqual(before, 0)

        await store.setFailureInjection(.beforeAssignCommit)
        do {
            _ = try await store.assign(
                images: [img("IMG_0001.arw"), img("IMG_0002.arw")],
                toCategoryID: a)
            XCTFail("expected the injected failure")
        } catch is CatalogOrganizationInjectedFailure {
            // expected
        }
        await store.setFailureInjection(.none)

        let after = try await countRows("SELECT COUNT(*) FROM image_categories")
        XCTAssertEqual(after, 0, "zero half-committed memberships")

        // Reopen: the database agrees (no WAL-recovered ghosts).
        await store.close()
        let reopened = CatalogOrganizationStore(databaseURL: catalogURL)
        let reopenedCount = try await reopened.memberCount(categoryID: a)
        XCTAssertEqual(reopenedCount, 0)
        await reopened.close()
    }

    // MARK: - T4: the no-orphan exhaustive proof

    /// A deterministic (LCG) 120-step CRUD gauntlet — creates, renames,
    /// moves (some refused by the cycle defense), leaf deletes (some
    /// refused by the non-empty guard) — asserting after EVERY step that
    /// every parent_id points at a LIVE node and no membership row points
    /// at a dead image (the store-level equivalent of
    /// PRAGMA foreign_key_check, which cannot run — the DDL declares no
    /// FKs by discipline).
    func testNoOrphanExhaustiveCRUDGauntlet() async throws {
        var rng: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Int((rng >> 33) % UInt64(max(1, bound)))
        }

        var live: [Int64] = []
        for step in 0..<120 {
            switch next(5) {
            case 0, 1:  // create (root or under a random live node)
                let parent = live.isEmpty || next(3) == 0 ? nil : live[next(live.count)]
                let id = try await store.createCategory(
                    name: "N\(step)", parentID: parent)
                live.append(id)
            case 2:  // rename
                if let id = live.randomElementUsing(next) {
                    try await store.renameCategory(id: id, to: "R\(step)")
                }
            case 3:  // move (cycle refusals land here and are FINE)
                guard live.count > 1 else { continue }
                let id = live[next(live.count)]
                let parent = next(4) == 0 ? nil : live[next(live.count)]
                try? await store.moveCategory(id: id, newParentID: parent)
            default:  // delete (non-empty refusals land here and are FINE)
                if let id = live.randomElementUsing(next) {
                    let deleted = try? await store.deleteCategory(id: id)
                    if deleted == true {
                        live.removeAll { $0 == id }
                    }
                }
            }

            // THE INVARIANT, after every step:
            let orphanParents = try await countRows(
                """
                SELECT COUNT(*) FROM categories c
                WHERE c.parent_id IS NOT NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM categories p WHERE p.id = c.parent_id)
                """)
            XCTAssertEqual(orphanParents, 0, "step \(step): dangling parent_id")
        }

        // Terminal coherence: the walked tree contains exactly the live
        // rows (no hidden orphans, no phantom nodes).
        let tree = try await store.readTree()
        let liveCount = try await countRows("SELECT COUNT(*) FROM categories")
        func countNodes(_ nodes: [CatalogTreeNode]) -> Int {
            nodes.reduce(0) { $0 + 1 + countNodes($1.children) }
        }
        XCTAssertEqual(liveCount, countNodes(tree))
    }

    /// The membership-orphans variant: memberships always point at live
    /// images and live targets through a classify → delete-target /
    /// delete-image gauntlet.
    func testNoMembershipOrphansThroughDeletes() async throws {
        for index in 0..<8 {
            try await seedImage(relPath: String(format: "IMG_%04d.arw", index))
        }
        let a = try await store.createCategory(name: "A")
        let c = try await store.createCollection(name: "C")
        _ = try await store.assign(
            images: (0..<8).map { img(String(format: "IMG_%04d.arw", $0)) },
            toCategoryID: a)
        _ = try await store.assign(
            images: (0..<8).map { img(String(format: "IMG_%04d.arw", $0)) },
            toCollectionID: c)

        // Delete half the images (the reconcile leg's effect, driven through
        // the store's handle here) — memberships must go with them (the D2
        // reconcile cascade; no FK exists, the write face owns the cleanup).
        // GLOB, not LIKE: SQLite LIKE has no [0-3] character class (the
        // pattern would match ZERO rows and the gauntlet would assert a
        // no-op — L020).
        try await store.withHandleForTesting { handle in
            try handle.exec("BEGIN IMMEDIATE")
            let cascadeCategories = try handle.prepare(
                "DELETE FROM image_categories WHERE catalog_image_id IN "
                    + "(SELECT id FROM catalog_images WHERE rel_path GLOB 'IMG_000[0-3].arw')")
            _ = try cascadeCategories.step()
            let cascadeCollections = try handle.prepare(
                "DELETE FROM image_collections WHERE catalog_image_id IN "
                    + "(SELECT id FROM catalog_images WHERE rel_path GLOB 'IMG_000[0-3].arw')")
            _ = try cascadeCollections.step()
            let delete = try handle.prepare(
                "DELETE FROM catalog_images WHERE rel_path GLOB 'IMG_000[0-3].arw'")
            _ = try delete.step()
            // Negative control: the pattern MUST have removed exactly four
            // rows — a zero-match regression must fail here, not pass.
            XCTAssertEqual(handle.changes(), 4, "the GLOB must match four rows")
            try handle.exec("COMMIT")
        }

        let orphanMembers = try await countRows(
            """
            SELECT COUNT(*) FROM image_categories
            WHERE catalog_image_id NOT IN (SELECT id FROM catalog_images)
            """)
        let orphanCollectionMembers = try await countRows(
            """
            SELECT COUNT(*) FROM image_collections
            WHERE catalog_image_id NOT IN (SELECT id FROM catalog_images)
            """)
        // The residual counts must be ZERO — and the surviving memberships
        // are exactly the four live images' rows (content-level, L020).
        XCTAssertEqual(orphanMembers, 0)
        XCTAssertEqual(orphanCollectionMembers, 0)
        // (awaits hoisted out of the XCTAssertEqual autoclosures — the actor
        // calls stopped resolving through the async overload under a full
        // rebuild; same assertion, plain locals)
        let memberCountA = try await store.memberCount(categoryID: a)
        let memberCountC = try await store.memberCount(collectionID: c)
        XCTAssertEqual(memberCountA, 4)
        XCTAssertEqual(memberCountC, 4)
    }

    // MARK: - T4: read/write concurrency smoke (WAL, R4 cross-domain)

    /// Concurrent tree edits vs. grid reads: the writer's transactions and
    /// the reader's keyset pages interleave under WAL (reads never block,
    /// writes serialize on the store actor + SQLite write lock). Zero
    /// errors, and the terminal tree matches the single-threaded outcome.
    func testConcurrentEditsAndReadsSmoke() async throws {
        let parent = try await store.createCategory(name: "P")
        var ids: [Int64] = []
        for index in 0..<10 {
            ids.append(try await store.createCategory(
                name: String(format: "N%02d", index), parentID: parent))
        }
        try await bulkSeedImages(count: 500, sessionID: "sess-conc")
        let catalogStore = CatalogIndexStore(databaseURL: catalogURL)
        let groups: [FilterPredicateGroup] = []
        // Local Sendable captures only (actors + value arrays) — the task
        // closures must not capture the non-Sendable test instance.
        guard let orgStore = store else { return XCTFail("store missing") }
        let siblingIDs = ids
        let parentNode = parent

        try await withThrowingTaskGroup(of: Void.self) { group in
            // The writer: churn the sibling order.
            group.addTask {
                for round in 0..<20 {
                    let id = siblingIDs[round % siblingIDs.count]
                    try? await orgStore.moveCategory(
                        id: id, newParentID: parentNode, index: round % siblingIDs.count)
                    try? await orgStore.renameCategory(
                        id: id, to: String(format: "R%02d", round))
                }
            }
            // Reader 1: the tree walk.
            group.addTask {
                for _ in 0..<20 { _ = try await orgStore.readTree() }
            }
            // Reader 2: the keyset grid pages (the store's own face).
            group.addTask {
                for _ in 0..<10 {
                    _ = try? await catalogStore.queryPage(
                        groups: groups,
                        sort: FilterSort(key: .captureDate, ascending: false),
                        anchor: nil, limit: 60)
                }
            }
            while try await group.next() != nil {}
        }

        // Terminal coherence: gap-free sibling set, all ten alive.
        let tree = try await store.readTree()
        XCTAssertEqual(tree.count, 1)
        let siblings = tree[0].children
        XCTAssertEqual(siblings.count, 10)
        XCTAssertEqual(siblings.map(\.sortOrder), Array(0..<10))
        await catalogStore.close()
    }
}

extension Array where Element == Int64 {
    /// Deterministic element pick with the gauntlet's LCG (no Int.random —
    /// the sequence must be reproducible).
    func randomElementUsing(_ next: (Int) -> Int) -> Int64? {
        isEmpty ? nil : self[next(count)]
    }
}

/// A thread-safe bump counter (the memo-computation observer).
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func bump() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}
