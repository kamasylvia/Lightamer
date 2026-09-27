import Foundation
import LightamerCore
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// CatalogTreeModel (Plan 16-3 T3) — the WHOLE organization tree in memory.
//
// The store's `readTree()` is ONE WITH RECURSIVE walk (sub-millisecond at
// v1 scale); the model re-runs it after every mutation (execution decision:
// full re-read, no in-place patching — a thousand-node tree re-derives far
// below perception, and one refresh path can never drift from the store).
// The sidebar sections and the grid's classify menus consume THIS model —
// zero SQL outside Core (seam a).
//
// DRAG/DROP face: the view hands the model a dragged id + a BEFORE-target
// id; the model locates the target's parent + sibling index IN THE TREE and
// computes the post-removal insertion index the store's move API expects
// (target's position after the dragged id is removed from that sibling
// set). Same semantics for the flat collection list.
//
// The classify faces (assign/revoke) take composite identity STRINGS — the
// grid's `Row.id` spelling `sessionID/relPath` — split here, resolved by
// the store.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class CatalogTreeModel {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "catalog-tree")

    // MARK: - State

    private(set) var tree: [CatalogTreeNode] = []
    private(set) var collections: [CatalogCollectionEntry] = []

    /// The last operation's failure text (the sidebar shows it as a caption
    /// line; nil clears it). Typed errors are localized HERE, at the App
    /// edge — Core throws values.
    private(set) var lastErrorText: String?

    /// Bumped after every committed mutation (the views' onChange anchor).
    private(set) var revision = 0

    private var store: CatalogOrganizationStore?

    // MARK: - Wiring

    func configure(store: CatalogOrganizationStore) {
        self.store = store
    }

    /// Re-derive both faces from the store (the startup + post-mutation
    /// + post-projection refresh entry).
    func refresh() async {
        guard let store else { return }
        do {
            tree = try await store.readTree()
            collections = try await store.readCollections()
            revision += 1
        } catch {
            Self.logger.error(
                "readTree failed: \(error.localizedDescription, privacy: .public)")
            lastErrorText = error.localizedDescription
        }
    }

    // MARK: - Tree flattening (the move-to menu + classify menus)

    /// Depth-first flatten (sibling order preserved) — the menus' source.
    func flatCategories() -> [CatalogTreeNode] {
        var result: [CatalogTreeNode] = []
        func walk(_ nodes: [CatalogTreeNode]) {
            for node in nodes {
                result.append(node)
                walk(node.children)
            }
        }
        walk(tree)
        return result
    }

    /// The sidebar's flat row face: (node, depth) pairs in walk order —
    /// always expanded (execution decision: v1 renders the whole tree
    /// indented; collapse/expand is additive — the store walk is already
    /// sub-ms and v1 trees are small).
    func flatRows() -> [(node: CatalogTreeNode, depth: Int)] {
        var result: [(node: CatalogTreeNode, depth: Int)] = []
        func walk(_ nodes: [CatalogTreeNode], _ depth: Int) {
            for node in nodes {
                result.append((node, depth))
                walk(node.children, depth + 1)
            }
        }
        walk(tree, 0)
        return result
    }

    // MARK: - Category mutations (each: store call → full refresh)

    @discardableResult
    func createCategory(name: String, parentID: Int64?) async -> Bool {
        guard let store else { return false }
        do {
            _ = try await store.createCategory(name: name, parentID: parentID)
            await refresh()
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    func renameCategory(id: Int64, to name: String) async {
        guard let store else { return }
        do {
            try await store.renameCategory(id: id, to: name)
            await refresh()
        } catch {
            recordFailure(error)
        }
    }

    func deleteCategory(id: Int64) async {
        guard let store else { return }
        do {
            try await store.deleteCategory(id: id)
            await refresh()
        } catch {
            recordFailure(error)
        }
    }

    /// The drag/drop face: move `draggedID` to sit BEFORE `targetID`
    /// (same parent as the target). A drop on the dragged node itself or
    /// on its own subtree is rejected here AND in the store (cycle).
    func moveCategory(dragged draggedID: Int64, before targetID: Int64) async {
        guard let store else { return }
        guard draggedID != targetID else { return }
        // Locate the target in the tree.
        guard let (parentID, siblings) = locate(targetID) else { return }
        guard siblings.contains(targetID) else { return }
        // Cycle: the target must not be the dragged node nor inside its
        // subtree (a drop INSIDE the dragged subtree has no before-slot).
        if node(draggedID)?.contains(id: targetID) == true { return }
        // Post-removal index: the target's position once the dragged node
        // is out of THIS sibling set (a same-parent drag shifts it).
        var effective = siblings
        effective.removeAll { $0 == draggedID }
        guard let index = effective.firstIndex(of: targetID) else { return }
        do {
            try await store.moveCategory(
                id: draggedID, newParentID: parentID, index: index)
            await refresh()
        } catch {
            recordFailure(error)
        }
    }

    // MARK: - Collection mutations

    @discardableResult
    func createCollection(name: String) async -> Bool {
        guard let store else { return false }
        do {
            _ = try await store.createCollection(name: name)
            await refresh()
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    func renameCollection(id: Int64, to name: String) async {
        guard let store else { return }
        do {
            try await store.renameCollection(id: id, to: name)
            await refresh()
        } catch {
            recordFailure(error)
        }
    }

    func deleteCollection(id: Int64) async {
        guard let store else { return }
        do {
            try await store.deleteCollection(id: id)
            await refresh()
        } catch {
            recordFailure(error)
        }
    }

    /// The flat-list drag/drop face (before-target semantics).
    func moveCollection(dragged draggedID: Int64, before targetID: Int64) async {
        guard let store, draggedID != targetID else { return }
        guard let index = collections.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        var effective = collections.map(\.id)
        effective.removeAll { $0 == draggedID }
        guard let adjusted = effective.firstIndex(of: targetID) else { return }
        do {
            try await store.moveCollection(id: draggedID, index: adjusted)
            await refresh()
        } catch {
            recordFailure(error)
        }
    }

    // MARK: - Classification (the grid's context-menu faces)

    /// Split the grid's composite identities and classify them. Returns
    /// false when the store threw (the view logs/reports).
    private func splitIdentities(
        _ identities: [String]
    ) -> [CatalogImageIdentity] {
        identities.compactMap { identity in
            guard let split = identity.firstIndex(of: "/") else { return nil }
            return CatalogImageIdentity(
                sessionID: String(identity[..<split]),
                relPath: String(identity[identity.index(after: split)...]))
        }
    }

    func assign(identities: [String], toCategoryID: Int64) async {
        guard let store else { return }
        do {
            _ = try await store.assign(
                images: splitIdentities(identities), toCategoryID: toCategoryID)
            await refresh()
        } catch {
            recordFailure(error)
        }
    }

    func assign(identities: [String], toCollectionID: Int64) async {
        guard let store else { return }
        do {
            _ = try await store.assign(
                images: splitIdentities(identities), toCollectionID: toCollectionID)
            await refresh()
        } catch {
            recordFailure(error)
        }
    }

    func revoke(identities: [String], fromCategoryID: Int64) async {
        guard let store else { return }
        do {
            _ = try await store.revoke(
                images: splitIdentities(identities), fromCategoryID: fromCategoryID)
            await refresh()
        } catch {
            recordFailure(error)
        }
    }

    // MARK: - Internals

    private func recordFailure(_ error: Error) {
        Self.logger.error(
            "organization mutation failed: \(error.localizedDescription, privacy: .public)")
        lastErrorText = error.localizedDescription
    }

    /// The target's (parentID, sibling id list) as the tree currently sees
    /// it. Root targets report nil parent.
    private func locate(
        _ id: Int64
    ) -> (parentID: Int64?, siblings: [Int64])? {
        if tree.contains(where: { $0.id == id }) {
            return (nil, tree.map(\.id))
        }
        var queue = tree
        while !queue.isEmpty {
            let node = queue.removeFirst()
            if node.children.contains(where: { $0.id == id }) {
                return (node.id, node.children.map(\.id))
            }
            queue.append(contentsOf: node.children)
        }
        return nil
    }

    private func node(_ id: Int64) -> CatalogTreeNode? {
        flatCategories().first { $0.id == id }
    }
}

extension CatalogTreeNode {
    /// True when `id` is this node or one of its descendants (the drop
    /// rejection on the view side; the store re-checks in-transaction).
    func contains(id: Int64) -> Bool {
        self.id == id || children.contains { $0.contains(id: id) }
    }
}
