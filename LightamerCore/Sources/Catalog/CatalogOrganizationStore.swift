import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// CatalogOrganizationStore (Plan 16-3 T1/T2) — the organization data's ONLY
// read/write face: categories (adjacency tree), collections (flat), and the
// image_categories/image_collections memberships.
//
// ORGANIZATION TRUTH = THE CATALOG ITSELF (D-16-CONTEXT specifics, taught):
// metadata mirrors are re-derivable from the session side, but the
// category tree / collections / memberships exist NOWHERE else — a session
// never learns of them. A destructive rebuild loses them; a reconciling
// rebuild (UPSERT-keeps-id) preserves the membership rows because the
// referenced `catalog_images.id` never changes (16-1 R1).
//
// SEAM a (L031/D-16-CONTEXT-8): every SQL string in this file is a Core
// Catalog face — DDL comes from `CatalogIndexSchema` (already applied by
// the open path), the scope/filter faces stay in FilterSQL/CatalogIndexStore
// (consumed, never duplicated here). App-side code sees typed values only —
// zero SQL in the App layer.
//
// TREE SHAPE (D-16-CONTEXT-4): `categories` adjacency table
// (parent_id NULL = root; NO foreign key declared — the orphan defense is a
// WRITE-FACE discipline, executed here):
//   • create   — parent existence verified; sort_order appends after the
//                sibling tail.
//   • move     — cycle defense FIRST: the target parent must not be the
//                node itself nor inside its subtree (`subtreeIDs`, the
//                WITH RECURSIVE walk reused for reads); executed as ONE
//                transaction = the parent_id UPDATE + BOTH sibling sets'
//                integer re-numbering (0…n-1, no holes — RQ-16-8).
//   • delete   — LEAF ONLY (a non-empty parent is a typed refusal; the UI
//                must dispose of the subtree first); the node's membership
//                rows are cascaded in the SAME transaction (no FK — the
//                write face owns referential cleanup).
//   • readTree — ONE WITH RECURSIVE walk from the roots into memory
//                (v1 trees are ≤ thousands of nodes; lazy loading is
//                over-engineering — RQ-16-8). The recursive spelling uses
//                UNION (not UNION ALL) so a hypothetical corrupt cycle
//                TERMINATES (SQLite drops duplicate queue rows) instead of
//                looping forever — unreachable by construction, defended
//                anyway.
//
// TRANSACTION DISCIPLINE (the red line, not relaxed): every mutation is
// ONE `BEGIN IMMEDIATE` … COMMIT; any failure ROLLS BACK to the exact
// prior state (the T4 injection tests byte-verify this). `INSERT OR IGNORE`
// makes re-classification idempotent (the PK pair). The classifying bulk
// write = one bulk change = one transaction (claimMetadataApply form,
// SessionIndexStore.swift:1177); a 10k-row assignment stays sub-second and
// renders ZERO pixels (PERF-07 semantics: the classification path touches
// ONLY the catalog — never the session side, never thumbnails).
//
// CONCURRENCY: this store owns ITS OWN connection over the same `.lcat`
// WAL database (the projector writes rows, this store writes organization —
// two writers serialize on SQLite's write lock with the 5s busy timeout;
// RQ-16-17's explicit-BEGIN IMMEDIATE form makes contention loud instead
// of deadlocky). All mutation is serialized within the actor.
// ─────────────────────────────────────────────────────────────────────────────

/// One node of the category tree (`readTree` product — children assembled,
/// sibling order = sort_order, id).
public struct CatalogTreeNode: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let parentID: Int64?
    public var name: String
    public var sortOrder: Int
    public var children: [CatalogTreeNode]

    public init(
        id: Int64, parentID: Int64?, name: String, sortOrder: Int,
        children: [CatalogTreeNode] = []
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.sortOrder = sortOrder
        self.children = children
    }
}

/// One flat collection row (`readCollections` product).
public struct CatalogCollectionEntry: Sendable, Equatable, Identifiable {
    public let id: Int64
    public var name: String
    public var sortOrder: Int

    public init(id: Int64, name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

/// The classification write's ledger (resolved = identities that mapped to
/// live catalog rows; inserted = rows the INSERT OR IGNORE actually added;
/// elapsedSeconds = the segment-2 transaction's wall time — the T2 perf
/// evidence; skipped = identities with no catalog row, dropped silently —
/// an execution decision, 16-3-DECISIONS).
public struct CatalogAssignResult: Sendable, Equatable {
    public var resolved = 0
    public var inserted = 0
    public var skipped = 0
    public var elapsedSeconds = 0.0

    public init() {}
}

/// The typed failure face of the organization write face.
public enum CatalogOrganizationError: Error, Equatable, Sendable {
    /// The mutated node is gone (already deleted, or never existed).
    case notFound(kind: String, id: Int64)
    /// A declared parent does not exist.
    case parentNotFound(id: Int64)
    /// Blank (or whitespace-only) name.
    case invalidName
    /// Move target = the node itself or inside its subtree.
    case cycleDetected(id: Int64)
    /// Delete refused: the category still has children.
    case categoryHasChildren(id: Int64, count: Int)
}

/// Failure-injection seams for the T4 transaction-atomicity tests (the
/// L010 red-line pattern: a test-owned enum, checked inside the open
/// transaction — an injected throw must ROLL BACK, never half-commit).
public enum CatalogOrganizationFailureInjection: Sendable, Equatable {
    case none
    /// Throw AFTER the sibling rewrites, before COMMIT (the reorder leg).
    case afterSiblingRewrites
    /// Throw AFTER the membership inserts, before COMMIT (the assign leg).
    case beforeAssignCommit
}

/// The injected failure itself (a distinct type so a ROLLBACK test matches
/// on the error kind, never on a borrowed production case).
public struct CatalogOrganizationInjectedFailure: Error, Equatable, Sendable {
    public let leg: CatalogOrganizationFailureInjection
    public init(leg: CatalogOrganizationFailureInjection) {
        self.leg = leg
    }
}

public actor CatalogOrganizationStore {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "catalog-organization")

    private var handle: SQLiteHandle?
    private let databaseURL: URL

    /// The COUNT-memo hook: invoked after every membership-affecting COMMIT
    /// (assign/revoke/cascading deletes) so the CatalogIndexStore badge
    /// memo dies with the write (the projector's countsInvalidator twin).
    public var countsInvalidator: (@Sendable () async -> Void)?

    /// The T4 injection seam (actor-isolated; tests set it explicitly).
    public var failureInjection: CatalogOrganizationFailureInjection = .none

    public init() {
        self.databaseURL = CatalogIndexSchema.defaultDatabaseURL()
    }

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public var isClosed: Bool { handle == nil }

    public func close() {
        handle?.close()
        handle = nil
    }

    /// Wire the COUNT-memo killer (tests + the App's shared runtime).
    public func setCountsInvalidator(
        _ invalidator: (@Sendable () async -> Void)?
    ) {
        countsInvalidator = invalidator
    }

    /// Wire the T4 injection seam (actor-isolated setter for tests).
    public func setFailureInjection(_ injection: CatalogOrganizationFailureInjection) {
        failureInjection = injection
    }

    // MARK: - Categories CRUD

    /// Create a category (parent nil = root). The sort_order appends after
    /// the sibling tail (execution decision: tail-append, gap-free —
    /// 16-3-DECISIONS). ONE transaction.
    @discardableResult
    public func createCategory(
        name: String, parentID: Int64? = nil
    ) throws -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CatalogOrganizationError.invalidName }
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "store", id: -1) }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            if let parentID {
                try Self.assertParentExists(handle, parentID)
            }
            let tail = try Self.siblingIDs(handle, parentID: parentID).count
            let insert = try handle.prepare(
                "INSERT INTO categories (parent_id, name, sort_order, created_at) "
                    + "VALUES (?, ?, ?, ?)")
            if let parentID {
                try insert.bindInt(1, parentID)
            } else {
                try insert.bindNull(1)
            }
            try insert.bindText(2, trimmed)
            try insert.bindInt(3, Int64(tail))
            try insert.bindDouble(4, Date().timeIntervalSince1970)
            _ = try insert.step()
            let id = handle.lastInsertRowID()
            try handle.exec("COMMIT")
            return id
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// Rename a category. Missing id = typed error (the target cannot be
    /// located); a same-value rename is a harmless no-op write (idempotent
    /// end state — 16-3-DECISIONS). ONE transaction.
    public func renameCategory(id: Int64, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CatalogOrganizationError.invalidName }
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "category", id: id) }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            try Self.assertCategoryExists(handle, id)
            let update = try handle.prepare(
                "UPDATE categories SET name = ? WHERE id = ?")
            try update.bindText(1, trimmed)
            try update.bindInt(2, id)
            _ = try update.step()
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// Move a category to `newParentID` (nil = root) at sibling position
    /// `index` (nil = append). Same-parent moves are a pure re-order;
    /// cross-parent moves rewrite BOTH sibling sets — all in ONE
    /// transaction. The cycle defense runs FIRST: the target parent must
    /// not be the node nor inside its subtree.
    public func moveCategory(
        id: Int64, newParentID: Int64?, index: Int? = nil
    ) throws {
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "category", id: id) }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            // The node must exist (and, moving under a parent, that parent
            // must exist).
            try Self.assertCategoryExists(handle, id)
            if let newParentID {
                if newParentID == id {
                    throw CatalogOrganizationError.cycleDetected(id: id)
                }
                try Self.assertParentExists(handle, newParentID)
                // Cycle defense: the target must not be inside the moving
                // node's subtree (WITH RECURSIVE walk, UNION-terminated).
                let subtree = try Self.subtreeIDs(handle, of: id)
                if subtree.contains(newParentID) {
                    throw CatalogOrganizationError.cycleDetected(id: id)
                }
            }

            // The OLD parent's siblings (read BEFORE the parent flip).
            let currentParent = try Self.categoryParentID(handle, id: id)
            let oldSiblings = try Self.siblingIDs(handle, parentID: currentParent)
                .filter { $0 != id }

            if currentParent != newParentID {
                // Cross-parent: rewrite the old sibling set (gap-free).
                try Self.rewriteOrder(handle, ids: oldSiblings)
            }

            // Flip the parent + slot into the new sibling set.
            let update = try handle.prepare(
                "UPDATE categories SET parent_id = ? WHERE id = ?")
            if let newParentID {
                try update.bindInt(1, newParentID)
            } else {
                try update.bindNull(1)
            }
            try update.bindInt(2, id)
            _ = try update.step()

            var newSiblings: [Int64]
            if currentParent == newParentID {
                // Same-parent reorder: the set without the node, in
                // existing order, then re-insert at the index.
                newSiblings = oldSiblings
            } else {
                newSiblings = try Self.siblingIDs(handle, parentID: newParentID)
                    .filter { $0 != id }
            }
            let insertion = min(index ?? newSiblings.count, newSiblings.count)
            newSiblings.insert(id, at: max(0, insertion))
            try Self.rewriteOrder(handle, ids: newSiblings)

            try checkInjection(.afterSiblingRewrites)
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// Delete a LEAF category. A non-empty parent is a typed refusal (the
    /// UI disposes of the subtree first — the no-FK orphan defense).
    /// The node's image memberships cascade in the SAME transaction.
    /// Returns false when the node was already gone (idempotent no-op —
    /// 16-3-DECISIONS); true when actually deleted.
    @discardableResult
    public func deleteCategory(id: Int64) async throws -> Bool {
        try ensureOpen()
        guard let handle else { return false }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            guard try Self.categoryExists(handle, id) else {
                try handle.exec("COMMIT")
                return false
            }
            let childCount = try Self.childCount(handle, of: id)
            guard childCount == 0 else {
                throw CatalogOrganizationError.categoryHasChildren(
                    id: id, count: childCount)
            }
            // Membership cascade (no FK — the write face owns it).
            let cascade = try handle.prepare(
                "DELETE FROM image_categories WHERE category_id = ?")
            try cascade.bindInt(1, id)
            _ = try cascade.step()

            let delete = try handle.prepare("DELETE FROM categories WHERE id = ?")
            try delete.bindInt(1, id)
            _ = try delete.step()
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
        await invalidateCountsHook()
        return true
    }

    // MARK: - Categories reads

    /// The WHOLE tree in one WITH RECURSIVE walk (roots first, then each
    /// level in sibling order), assembled into value nodes. Orphans (a
    /// parent_id pointing nowhere — unreachable by the write face) are
    /// EXCLUDED by the recursion itself: only root-reachable nodes come
    /// back. UNION (not UNION ALL) terminates even on a corrupt cycle.
    public func readTree() throws -> [CatalogTreeNode] {
        try ensureOpen()
        guard let handle else { return [] }
        let rows = try Self.readTreeRows(handle)
        return Self.assembleTree(rows)
    }

    /// The node's subtree ids INCLUDING itself (the cycle-defense and
    /// subtree-disposal primitive; WITH RECURSIVE + UNION termination).
    public func subtreeIDs(of id: Int64) throws -> Set<Int64> {
        try ensureOpen()
        guard let handle else { return [] }
        return try Self.subtreeIDs(handle, of: id)
    }

    // MARK: - Collections CRUD

    @discardableResult
    public func createCollection(name: String) throws -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CatalogOrganizationError.invalidName }
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "store", id: -1) }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            let tail = try Self.collectionIDs(handle).count
            let insert = try handle.prepare(
                "INSERT INTO collections (name, sort_order, created_at) "
                    + "VALUES (?, ?, ?)")
            try insert.bindText(1, trimmed)
            try insert.bindInt(2, Int64(tail))
            try insert.bindDouble(3, Date().timeIntervalSince1970)
            _ = try insert.step()
            let id = handle.lastInsertRowID()
            try handle.exec("COMMIT")
            return id
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    public func renameCollection(id: Int64, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CatalogOrganizationError.invalidName }
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "collection", id: id) }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            try Self.assertCollectionExists(handle, id)
            let update = try handle.prepare(
                "UPDATE collections SET name = ? WHERE id = ?")
            try update.bindText(1, trimmed)
            try update.bindInt(2, id)
            _ = try update.step()
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// Delete a collection — the flat row AND its membership rows go in
    /// ONE transaction (the collection itself is the organization asset;
    /// the images are untouched). Returns false when already gone.
    @discardableResult
    public func deleteCollection(id: Int64) async throws -> Bool {
        try ensureOpen()
        guard let handle else { return false }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            guard try Self.collectionExists(handle, id) else {
                try handle.exec("COMMIT")
                return false
            }
            let cascade = try handle.prepare(
                "DELETE FROM image_collections WHERE collection_id = ?")
            try cascade.bindInt(1, id)
            _ = try cascade.step()
            let delete = try handle.prepare("DELETE FROM collections WHERE id = ?")
            try delete.bindInt(1, id)
            _ = try delete.step()
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
        await invalidateCountsHook()
        return true
    }

    /// Flat-list reorder: move the collection to position `index` of the
    /// (gap-free re-numbered) list. ONE transaction.
    public func moveCollection(id: Int64, index: Int) throws {
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "collection", id: id) }

        try handle.exec("BEGIN IMMEDIATE")
        do {
            try Self.assertCollectionExists(handle, id)
            var ids = try Self.collectionIDs(handle).filter { $0 != id }
            ids.insert(id, at: min(max(0, index), ids.count))
            try Self.rewriteCollectionOrder(handle, ids: ids)
            try checkInjection(.afterSiblingRewrites)
            try handle.exec("COMMIT")
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// The flat list (sibling order = sort_order, id).
    public func readCollections() throws -> [CatalogCollectionEntry] {
        try ensureOpen()
        guard let handle else { return [] }
        let statement = try handle.prepare(
            "SELECT id, name, sort_order FROM collections "
                + "ORDER BY sort_order, id")
        var rows: [CatalogCollectionEntry] = []
        while try statement.step() {
            rows.append(CatalogCollectionEntry(
                id: statement.columnInt(0) ?? 0,
                name: statement.columnText(1) ?? "",
                sortOrder: Int(statement.columnInt(2) ?? 0)))
        }
        return rows
    }

    // MARK: - Classification writes (Plan 16-3 T2)

    /// Assign images to a category — MULTI-MEMBERSHIP (one image may sit in
    /// many categories; the PK pair makes repeats no-ops). Segment 1 =
    /// in-memory identity resolution (per-session prepared loop, dedup);
    /// Segment 2 = ONE transaction of prepared `INSERT OR IGNORE` (the
    /// claimMetadataApply shape — one bulk change = one transaction). ZERO
    /// pixel work, ZERO session-side contact (PERF-07 across domains).
    @discardableResult
    public func assign(
        images: [CatalogImageIdentity], toCategoryID: Int64
    ) async throws -> CatalogAssignResult {
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "category", id: toCategoryID) }

        // Segment 1 — resolve identities to stable ids (in memory, dedup).
        let resolved = try Self.resolveImageIDs(handle, images: images)

        try handle.exec("BEGIN IMMEDIATE")
        do {
            try Self.assertCategoryExists(handle, toCategoryID)
            var result = try Self.insertMemberships(
                handle, sql: "INSERT OR IGNORE INTO image_categories "
                    + "(category_id, catalog_image_id) VALUES (?, ?)",
                firstBind: toCategoryID, imageIDs: resolved.ids)
            result.skipped = resolved.skipped
            try checkInjection(.beforeAssignCommit)
            try handle.exec("COMMIT")
            await invalidateCountsHook()
            Self.logAssign(result, target: "category", targetID: toCategoryID)
            return result
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// Assign images to a collection (the same shape, image_collections).
    @discardableResult
    public func assign(
        images: [CatalogImageIdentity], toCollectionID: Int64
    ) async throws -> CatalogAssignResult {
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "collection", id: toCollectionID) }

        let resolved = try Self.resolveImageIDs(handle, images: images)

        try handle.exec("BEGIN IMMEDIATE")
        do {
            try Self.assertCollectionExists(handle, toCollectionID)
            var result = try Self.insertMemberships(
                handle, sql: "INSERT OR IGNORE INTO image_collections "
                    + "(collection_id, catalog_image_id) VALUES (?, ?)",
                firstBind: toCollectionID, imageIDs: resolved.ids)
            result.skipped = resolved.skipped
            try checkInjection(.beforeAssignCommit)
            try handle.exec("COMMIT")
            await invalidateCountsHook()
            Self.logAssign(result, target: "collection", targetID: toCollectionID)
            return result
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// Revoke images from a category (the mirrored DELETE; missing
    /// memberships are silent no-ops — the end state is what matters).
    @discardableResult
    public func revoke(
        images: [CatalogImageIdentity], fromCategoryID: Int64
    ) async throws -> CatalogAssignResult {
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "category", id: fromCategoryID) }

        let resolved = try Self.resolveImageIDs(handle, images: images)
        try handle.exec("BEGIN IMMEDIATE")
        do {
            var result = try Self.deleteMemberships(
                handle, sql: "DELETE FROM image_categories "
                    + "WHERE category_id = ? AND catalog_image_id = ?",
                firstBind: fromCategoryID, imageIDs: resolved.ids)
            result.skipped = resolved.skipped
            try handle.exec("COMMIT")
            await invalidateCountsHook()
            return result
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// Revoke images from a collection.
    @discardableResult
    public func revoke(
        images: [CatalogImageIdentity], fromCollectionID: Int64
    ) async throws -> CatalogAssignResult {
        try ensureOpen()
        guard let handle else { throw CatalogOrganizationError.notFound(kind: "collection", id: fromCollectionID) }

        let resolved = try Self.resolveImageIDs(handle, images: images)
        try handle.exec("BEGIN IMMEDIATE")
        do {
            var result = try Self.deleteMemberships(
                handle, sql: "DELETE FROM image_collections "
                    + "WHERE collection_id = ? AND catalog_image_id = ?",
                firstBind: fromCollectionID, imageIDs: resolved.ids)
            result.skipped = resolved.skipped
            try handle.exec("COMMIT")
            await invalidateCountsHook()
            return result
        } catch {
            try? handle.exec("ROLLBACK")
            throw error
        }
    }

    /// The membership read face (the tree model's badge + the tests): how
    /// many images sit in the category / collection. Explicit id column —
    /// never a rowid.
    public func memberCount(categoryID: Int64) throws -> Int {
        try ensureOpen()
        guard let handle else { return 0 }
        return try Self.memberCount(
            handle, sql: "SELECT COUNT(*) FROM image_categories WHERE category_id = ?",
            id: categoryID)
    }

    public func memberCount(collectionID: Int64) throws -> Int {
        try ensureOpen()
        guard let handle else { return 0 }
        return try Self.memberCount(
            handle, sql: "SELECT COUNT(*) FROM image_collections WHERE collection_id = ?",
            id: collectionID)
    }

    // MARK: - Test seams

    /// Direct-handle fixture seeding + verification (the CatalogIndexStore
    /// pattern — the non-Sendable handle never leaves the actor).
    public func withHandleForTesting<T: Sendable>(
        _ body: (SQLiteHandle) throws -> T
    ) throws -> T {
        try ensureOpen()
        guard let handle else {
            throw CatalogOrganizationError.notFound(kind: "store", id: -1)
        }
        return try body(handle)
    }

    // MARK: - Internals

    private func ensureOpen() throws {
        guard handle == nil else { return }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let opened = try SQLiteHandle(path: databaseURL.path)
        handle = opened
        try CatalogIndexSchema.apply(to: opened)
    }

    private func invalidateCountsHook() async {
        if let invalidator = countsInvalidator {
            await invalidator()
        }
    }

    /// The T4 seam probe — throws INSIDE the open transaction when the
    /// injected leg matches (the ROLLBACK path's trigger).
    private func checkInjection(
        _ leg: CatalogOrganizationFailureInjection
    ) throws {
        if failureInjection == leg, failureInjection != .none {
            throw CatalogOrganizationInjectedFailure(leg: leg)
        }
    }

    private nonisolated static func logAssign(
        _ result: CatalogAssignResult, target: String, targetID: Int64
    ) {
        let message = "assign to \(target) \(targetID): "
            + "resolved=\(result.resolved) inserted=\(result.inserted) "
            + "skipped=\(result.skipped) "
            + "in \(String(format: "%.3f", result.elapsedSeconds))s"
        Self.logger.info("\(message, privacy: .public)")
    }

    // MARK: Static SQL helpers (handle-confined, no freehand translation —
    // every string here is a Core Catalog face per seam a)

    private static func assertCategoryExists(
        _ handle: SQLiteHandle, _ id: Int64
    ) throws {
        guard try categoryExists(handle, id) else {
            throw CatalogOrganizationError.notFound(kind: "category", id: id)
        }
    }

    /// A declared PARENT is missing (a different face from the mutated node
    /// itself being gone — the parent's existence is a precondition, the
    /// node's absence is a stale-target situation).
    private static func assertParentExists(
        _ handle: SQLiteHandle, _ id: Int64
    ) throws {
        guard try categoryExists(handle, id) else {
            throw CatalogOrganizationError.parentNotFound(id: id)
        }
    }

    private static func categoryExists(
        _ handle: SQLiteHandle, _ id: Int64
    ) throws -> Bool {
        let statement = try handle.prepare(
            "SELECT 1 FROM categories WHERE id = ?")
        try statement.bindInt(1, id)
        return try statement.step()
    }

    private static func assertCollectionExists(
        _ handle: SQLiteHandle, _ id: Int64
    ) throws {
        guard try collectionExists(handle, id) else {
            throw CatalogOrganizationError.notFound(kind: "collection", id: id)
        }
    }

    private static func collectionExists(
        _ handle: SQLiteHandle, _ id: Int64
    ) throws -> Bool {
        let statement = try handle.prepare(
            "SELECT 1 FROM collections WHERE id = ?")
        try statement.bindInt(1, id)
        return try statement.step()
    }

    private static func categoryParentID(
        _ handle: SQLiteHandle, id: Int64
    ) throws -> Int64? {
        let statement = try handle.prepare(
            "SELECT parent_id FROM categories WHERE id = ?")
        try statement.bindInt(1, id)
        guard try statement.step() else { return nil }
        return statement.columnInt(0)
    }

    private static func childCount(
        _ handle: SQLiteHandle, of id: Int64
    ) throws -> Int {
        let statement = try handle.prepare(
            "SELECT COUNT(*) FROM categories WHERE parent_id = ?")
        try statement.bindInt(1, id)
        if try statement.step() {
            return Int(statement.columnInt(0) ?? 0)
        }
        return 0
    }

    /// The sibling id set in display order (sort_order, id). The NULL
    /// parent branch uses `IS NULL` spelling (the `= NULL` trap).
    private static func siblingIDs(
        _ handle: SQLiteHandle, parentID: Int64?
    ) throws -> [Int64] {
        let statement: SQLiteStatement
        if let parentID {
            statement = try handle.prepare(
                "SELECT id FROM categories WHERE parent_id = ? "
                    + "ORDER BY sort_order, id")
            try statement.bindInt(1, parentID)
        } else {
            statement = try handle.prepare(
                "SELECT id FROM categories WHERE parent_id IS NULL "
                    + "ORDER BY sort_order, id")
        }
        var ids: [Int64] = []
        while try statement.step() {
            if let id = statement.columnInt(0) { ids.append(id) }
        }
        return ids
    }

    private static func collectionIDs(
        _ handle: SQLiteHandle
    ) throws -> [Int64] {
        let statement = try handle.prepare(
            "SELECT id FROM collections ORDER BY sort_order, id")
        var ids: [Int64] = []
        while try statement.step() {
            if let id = statement.columnInt(0) { ids.append(id) }
        }
        return ids
    }

    /// The INTEGER RE-NUMBERING: 0…n-1, gap-free, one prepared UPDATE per
    /// row inside the CALLER's transaction (sibling sets are <100 rows —
    /// sub-millisecond, RQ-16-8).
    private static func rewriteOrder(
        _ handle: SQLiteHandle, ids: [Int64]
    ) throws {
        let update = try handle.prepare(
            "UPDATE categories SET sort_order = ? WHERE id = ?")
        for (position, id) in ids.enumerated() {
            try update.bindInt(1, Int64(position))
            try update.bindInt(2, id)
            _ = try update.step()
            try update.reset()
        }
    }

    private static func rewriteCollectionOrder(
        _ handle: SQLiteHandle, ids: [Int64]
    ) throws {
        let update = try handle.prepare(
            "UPDATE collections SET sort_order = ? WHERE id = ?")
        for (position, id) in ids.enumerated() {
            try update.bindInt(1, Int64(position))
            try update.bindInt(2, id)
            _ = try update.step()
            try update.reset()
        }
    }

    /// The subtree walk INCLUDING the root — the cycle-defense primitive.
    /// UNION (not ALL) drops duplicate queue rows so a corrupt cycle
    /// terminates instead of looping (unreachable by construction; cheap
    /// insurance).
    private static func subtreeIDs(
        _ handle: SQLiteHandle, of id: Int64
    ) throws -> Set<Int64> {
        let statement = try handle.prepare("""
            WITH RECURSIVE sub(id) AS (
              SELECT id FROM categories WHERE id = ?
              UNION
              SELECT c.id FROM categories c JOIN sub s ON c.parent_id = s.id
            )
            SELECT id FROM sub
            """)
        try statement.bindInt(1, id)
        var ids = Set<Int64>()
        while try statement.step() {
            if let found = statement.columnInt(0) { ids.insert(found) }
        }
        return ids
    }

    /// One tree row (the recursive SELECT's projection, in walk order).
    private struct TreeRow {
        var id: Int64
        var parentID: Int64?
        var name: String
        var sortOrder: Int
    }

    private static func readTreeRows(
        _ handle: SQLiteHandle
    ) throws -> [TreeRow] {
        let statement = try handle.prepare("""
            WITH RECURSIVE tree(id, parent_id, name, sort_order, depth) AS (
              SELECT id, parent_id, name, sort_order, 0
                FROM categories WHERE parent_id IS NULL
              UNION
              SELECT c.id, c.parent_id, c.name, c.sort_order, tree.depth + 1
                FROM categories c JOIN tree ON c.parent_id = tree.id
            )
            SELECT id, parent_id, name, sort_order
              FROM tree ORDER BY depth, sort_order, id
            """)
        var rows: [TreeRow] = []
        while try statement.step() {
            rows.append(TreeRow(
                id: statement.columnInt(0) ?? 0,
                parentID: statement.columnInt(1),
                name: statement.columnText(2) ?? "",
                sortOrder: Int(statement.columnInt(3) ?? 0)))
        }
        return rows
    }

    /// Assemble the walked rows into the value tree. Rows arrive ordered
    /// (depth, sort_order, id), so appending preserves each parent's
    /// sibling order.
    private static func assembleTree(
        _ rows: [TreeRow]
    ) -> [CatalogTreeNode] {
        var childrenByParent: [Int64?: [TreeRow]] = [:]
        for row in rows {
            childrenByParent[row.parentID, default: []].append(row)
        }
        func build(_ row: TreeRow) -> CatalogTreeNode {
            let kids = (childrenByParent[row.id] ?? []).map(build)
            return CatalogTreeNode(
                id: row.id, parentID: row.parentID, name: row.name,
                sortOrder: row.sortOrder, children: kids)
        }
        return (childrenByParent[nil] ?? []).map(build)
    }

    /// Segment 1: the identity → stable-id resolution (per-session prepared
    /// loop — the `imageIDs` shape; duplicated identities collapse). Skipped
    /// = identities with no live catalog row (dropped — an execution
    /// decision, 16-3-DECISIONS).
    private static func resolveImageIDs(
        _ handle: SQLiteHandle, images: [CatalogImageIdentity]
    ) throws -> (ids: [Int64], skipped: Int) {
        var bySession: [String: [String]] = [:]
        // Dedup on a string key (CatalogImageIdentity is Equatable-only in
        // its 16-2 spelling; a Set of structs would need a Hashable widening
        // — not worth touching the frozen face).
        var seen = Set<String>()
        for image in images {
            let key = image.sessionID + "\u{1}" + image.relPath
            if seen.insert(key).inserted {
                bySession[image.sessionID, default: []].append(image.relPath)
            }
        }
        let statement = try handle.prepare(
            "SELECT id FROM catalog_images WHERE session_id = ? AND rel_path = ?")
        var ids: [Int64] = []
        var skipped = 0
        for (sessionID, relPaths) in bySession {
            for relPath in relPaths {
                try statement.bindText(1, sessionID)
                try statement.bindText(2, relPath)
                if try statement.step(), let id = statement.columnInt(0) {
                    ids.append(id)
                } else {
                    skipped += 1
                }
                try statement.reset()
            }
        }
        return (ids, skipped)
    }

    /// Segment 2: the prepared INSERT OR IGNORE loop inside the CALLER's
    /// transaction (claimMetadataApply form). Returns the ledger with the
    /// wall time of THIS leg.
    private static func insertMemberships(
        _ handle: SQLiteHandle, sql: String, firstBind: Int64, imageIDs: [Int64]
    ) throws -> CatalogAssignResult {
        var result = CatalogAssignResult()
        result.resolved = imageIDs.count
        let started = Date()
        let insert = try handle.prepare(sql)
        for id in imageIDs {
            try insert.bindInt(1, firstBind)
            try insert.bindInt(2, id)
            _ = try insert.step()
            result.inserted += handle.changes()
            try insert.reset()
        }
        result.elapsedSeconds = Date().timeIntervalSince(started)
        return result
    }

    private static func deleteMemberships(
        _ handle: SQLiteHandle, sql: String, firstBind: Int64, imageIDs: [Int64]
    ) throws -> CatalogAssignResult {
        var result = CatalogAssignResult()
        result.resolved = imageIDs.count
        let started = Date()
        let delete = try handle.prepare(sql)
        for id in imageIDs {
            try delete.bindInt(1, firstBind)
            try delete.bindInt(2, id)
            _ = try delete.step()
            result.inserted += handle.changes()  // deleted rows ride the same counter
            try delete.reset()
        }
        result.elapsedSeconds = Date().timeIntervalSince(started)
        return result
    }

    private static func memberCount(
        _ handle: SQLiteHandle, sql: String, id: Int64
    ) throws -> Int {
        let statement = try handle.prepare(sql)
        try statement.bindInt(1, id)
        if try statement.step() {
            return Int(statement.columnInt(0) ?? 0)
        }
        return 0
    }
}
