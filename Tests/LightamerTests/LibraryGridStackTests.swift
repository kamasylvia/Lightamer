import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryGridStackTests (Plan M6-4-01 T6, KD-7) — the App collection model's
// stack face, over a REAL `.lalb` (the LibraryGridModelTests fixture pattern;
// LIB-domain聚拢 per the S3 ruling — this file lives beside
// LibraryGridModelTests, NOT in the App bundle):
//
//   ① the default .collapsed first query (predicate face)
//   ② the expanded-mode fixup across pages (no duplicates)
//   ③ the expanded full-walk union == the flat full-walk (R1 终测)
//   ④ the badge projection (memberships → counts/chevron state)
//   ⑤ toggleCollapse refresh · ⑥ expandAll/collapseAll
//   ⑦ groupSelection routing (≥2 gate + <2 no-op)
//   ⑧ ungroup/setCover/removeFromStack routing
//   ⑨ the autoStack pool selection (selection vs the full walk) + preview
//   ⑩ the post-command reload + selection shrink
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryGridStackTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: LibraryStore!
    private var queries: LibraryQueries!
    private var model: LibraryGridModel!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("grid-stack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("GridStack.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "GridStack")
        store = LibraryStore(store: fileStore)
        queries = LibraryQueries(store: fileStore)
        // Ten rows; filename ASC == rowid ASC; staggered capture dates.
        for index in 1...10 {
            try await fileStore.withWriteBatch { handle -> Bool in
                let insert = try handle.prepare(
                    "INSERT INTO images (image_path, path_kind, capture_date,"
                        + " file_stem, filename) VALUES (?, 0, ?, ?, ?)")
                try insert.bindText(1, "Media/g\(index).arw")
                try insert.bindDouble(2, Double(index))
                try insert.bindText(3, String(format: "g%02d", index))
                try insert.bindText(4, String(format: "g%02d.arw", index))
                _ = try insert.step()
                return true
            }
        }
        model = LibraryGridModel(queries: queries, pageSize: 3, store: store)
        try await model.apply(sort: FilterSort(key: .filename, ascending: true))
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        model = nil
        queries = nil
        store = nil
        fileStore = nil
        try await super.tearDown()
    }

    /// rowid of insertion index (1-based rowids).
    private func rid(_ index: Int) -> Int64 { Int64(index + 1) }

    private func walkToExhaustion() async throws {
        while !model.isExhausted {
            _ = try await model.loadNextPage()
        }
    }

    // MARK: - ① the default .collapsed first query

    func testDefaultCollapsedFirstQuery() async throws {
        XCTAssertEqual(model.stackDisplayMode, .collapsed)
        // A collapsed 3-stack: the first page shows covers only.
        _ = try await store.createStack(
            memberIDs: [rid(1), rid(2), rid(3)], collapsed: true)
        try await model.reloadFirstPage()
        let displayed = Set(model.rows.map(\.id))
        XCTAssertFalse(displayed.contains(rid(2)))
        XCTAssertFalse(displayed.contains(rid(3)))
        XCTAssertTrue(displayed.contains(rid(1)), "the cover shows")
        // With NO stacks both modes render identically (the zero-stack
        // byte-identical claim, behaviorally).
        let containingOne = try await store.stackContaining(imageID: rid(1))
        try await store.ungroup(stackID: try XCTUnwrap(containingOne).id)
        try await model.setStackDisplayMode(.flat)
        try await model.reloadFirstPage()
        try await walkToExhaustion()
        XCTAssertEqual(model.rows.count, 10)
    }

    // MARK: - ② the expanded fixup across pages

    func testExpandedFixupCrossPageNoDuplicates() async throws {
        // Cover g09 (page 1, pageSize 3), members g01/g05 (later pages).
        _ = try await store.createStack(
            memberIDs: [rid(8), rid(0), rid(4)], collapsed: false)
        try await model.setStackDisplayMode(.flat)
        try await walkToExhaustion()
        let ids = model.rows.map(\.id)
        XCTAssertEqual(Set(ids).count, 10, "every row exactly once — no duplicates")
        // The members gathered forward near the cover (position within 4).
        let positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let coverPosition = try XCTUnwrap(positions[rid(8)])
        for member in [rid(0), rid(4)] {
            XCTAssertLessThan(
                abs(try XCTUnwrap(positions[member]) - coverPosition), 4)
        }
    }

    // MARK: - ③ the expanded full-walk union == flat (R1 终测)

    func testExpandedFullWalkUnionEqualsFlatWalk() async throws {
        _ = try await store.createStack(
            memberIDs: [rid(9), rid(1), rid(6)], collapsed: false)
        _ = try await store.createStack(
            memberIDs: [rid(7), rid(2)], collapsed: false)
        try await model.setStackDisplayMode(.flat)
        try await walkToExhaustion()
        let expandedIDs = Set(model.rows.map(\.id))
        // The flat walk (a fresh model in collapsed... .flat semantics ride
        // the predicate; an all-expanded stack set makes the predicate a
        // no-op — the honest flat baseline is the direct query walk).
        var flatIDs: [Int64] = []
        var anchor: LibraryPageAnchor?
        let sort = FilterSort(key: .filename, ascending: true)
        while true {
            let page = try await queries.searchPage(
                sort: sort, anchor: anchor, limit: 3)
            flatIDs.append(contentsOf: page.map(\.id))
            guard page.count == 3, let last = page.last else { break }
            anchor = LibraryPageAnchor(
                keyValue: .text(last.filename ?? ""), imagePath: last.imagePath)
        }
        XCTAssertEqual(expandedIDs, Set(flatIDs), "the union golden (R1)")
        XCTAssertEqual(model.rows.count, flatIDs.count, "no duplicates")
    }

    // MARK: - ④ the badge projection

    func testStackBadgeProjection() async throws {
        let stack = try await store.createStack(
            memberIDs: [rid(0), rid(1), rid(2)], collapsed: true)
        try await model.reloadFirstPage()
        // The cover's badge: size 3, collapsed, position 0.
        let coverBadge = try XCTUnwrap(model.stackBadge(for: rid(0)))
        XCTAssertEqual(coverBadge.stackID, stack.id)
        XCTAssertEqual(coverBadge.size, 3)
        XCTAssertTrue(coverBadge.collapsed)
        XCTAssertEqual(coverBadge.position, 0)
        // An unstacked row has no badge.
        XCTAssertNil(model.stackBadge(for: rid(8)))
        // Unfold → the chevron state flips through the same projection.
        try await store.setCollapsed(stackID: stack.id, collapsed: false)
        try await model.reloadFirstPage()
        let expandedBadge = try XCTUnwrap(model.stackBadge(for: rid(1)))
        XCTAssertFalse(expandedBadge.collapsed)
        XCTAssertEqual(expandedBadge.position, 1, "member positions surface")
    }

    // MARK: - ⑤ toggleCollapse

    func testToggleCollapseRefreshes() async throws {
        let stack = try await store.createStack(
            memberIDs: [rid(0), rid(1), rid(2)], collapsed: true)
        try await model.reloadFirstPage()
        XCTAssertNil(model.stackBadge(for: rid(1)), "the member is hidden")
        // Toggle → the members appear at their keyset positions (the v1
        // semantics: the gather is a global-expanded property).
        try await model.toggleCollapse(stackID: stack.id)
        try await walkToExhaustion()
        let displayed = Set(model.rows.map(\.id))
        XCTAssertTrue(displayed.contains(rid(1)) && displayed.contains(rid(2)))
        XCTAssertFalse(model.stackBadge(for: rid(1))?.collapsed ?? true)
        // Toggle back → covers only again.
        try await model.toggleCollapse(stackID: stack.id)
        try await walkToExhaustion()
        XCTAssertFalse(Set(model.rows.map(\.id)).contains(rid(1)))
    }

    // MARK: - ⑥ expandAll / collapseAll

    func testExpandAllCollapseAll() async throws {
        _ = try await store.createStack(
            memberIDs: [rid(0), rid(1), rid(2)], collapsed: true)
        _ = try await store.createStack(
            memberIDs: [rid(4), rid(5)], collapsed: true)
        try await model.reloadFirstPage()
        try await walkToExhaustion()
        XCTAssertEqual(
            model.rows.count, 7,
            "ten rows minus the two hidden non-covers (3-stack) and one "
                + "(2-stack)")
        try await model.expandAll()
        try await walkToExhaustion()
        XCTAssertEqual(model.rows.count, 10, "everything visible")
        XCTAssertEqual(model.stackDisplayMode, .flat)
        for stack in try await store.stacks() {
            XCTAssertFalse(stack.collapsed, "all flags unfolded")
        }
        try await model.collapseAll()
        try await walkToExhaustion()
        XCTAssertEqual(model.rows.count, 7, "covers only")
        XCTAssertEqual(model.stackDisplayMode, .collapsed)
        for stack in try await store.stacks() {
            XCTAssertTrue(stack.collapsed, "all flags folded")
        }
    }

    // MARK: - ⑦ groupSelection routing

    func testGroupSelectionRouting() async throws {
        try await walkToExhaustion()
        // <2 selected: no-op (no stack lands).
        model.selectSingle(rid(0))
        await model.groupSelection()
        let stacksAfterSmall = try await store.stacks()
        XCTAssertTrue(stacksAfterSmall.isEmpty)
        // ≥2 selected: the union lands, born collapsed, and the view
        // refetches to the cover-only face.
        model.setSelection([rid(0), rid(4)])
        await model.groupSelection()
        let stacks = try await store.stacks()
        XCTAssertEqual(stacks.count, 1)
        let landed = try XCTUnwrap(stacks.first)
        XCTAssertEqual(Set(landed.memberIDs), Set([rid(0), rid(4)]))
        XCTAssertTrue(landed.collapsed)
        try await walkToExhaustion()
        XCTAssertEqual(model.rows.count, 9, "the grid refetched post-write")
    }

    // MARK: - ⑧ ungroup / setCover / removeFromStack routing

    func testUngroupSetCoverRemoveFromStackRouting() async throws {
        let stack = try await store.createStack(
            memberIDs: [rid(0), rid(1), rid(2)], collapsed: true)
        // setCover: rid(2) becomes the head.
        await model.setCover(imageID: rid(2))
        var members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(members.first, rid(2))
        // removeFromStack: the member leaves, positions tighten.
        await model.removeFromStack(imageID: rid(0))
        members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(members, [rid(2), rid(1)])
        // ungroup: the whole stack dissolves.
        await model.ungroup(stackID: stack.id)
        let stacksAfterUngroup = try await store.stacks()
        XCTAssertTrue(stacksAfterUngroup.isEmpty)
        // Unstacked ids: the routes are honest no-ops.
        await model.setCover(imageID: rid(8))
        await model.removeFromStack(imageID: rid(8))
        let stacksAfterNoOps = try await store.stacks()
        XCTAssertTrue(stacksAfterNoOps.isEmpty)
    }

    // MARK: - ⑨ autoStack pool selection + preview

    func testAutoStackPoolSelectionAndPreview() async throws {
        try await walkToExhaustion()
        // Preview: reports the count, writes NOTHING.
        let preview = try await model.autoStack(preview: true)
        XCTAssertEqual(preview, 1, "g01-g10 carry staggered dates — one cluster")
        let stacksAfterPreview = try await store.stacks()
        XCTAssertTrue(stacksAfterPreview.isEmpty, "preview wrote nothing")
        // The full walk is the pool when the selection is <2.
        model.selectSingle(rid(0))
        let created = try await model.autoStack(preview: false)
        XCTAssertEqual(created, 1)
        let stacksNow = try await store.stacks()
        let stack = try XCTUnwrap(stacksNow.first)
        XCTAssertEqual(stack.memberIDs.count, 10, "all ten rows cluster (≤60s steps)")
        try await store.ungroup(stackID: stack.id)
        // A ≥2 selection NARROWS the pool (gap 10 covers the 9s selection
        // spread — the cluster is exactly the two selected rows).
        try await model.reloadFirstPage()
        try await walkToExhaustion()
        model.setSelection([rid(0), rid(9)])
        _ = try await model.autoStack(gap: 10.0, preview: false)
        let pools = try await store.stacks()
        XCTAssertEqual(pools.count, 1)
        let pool = try XCTUnwrap(pools.first)
        XCTAssertEqual(Set(pool.memberIDs), Set([rid(0), rid(9)]))
    }

    // MARK: - ⑩ post-command reload + selection shrink

    func testPostCommandReloadAndSelectionShrink() async throws {
        try await walkToExhaustion()
        model.setSelection([rid(0), rid(4)])
        await model.groupSelection()
        // The reload shrank the selection to the rows still displayed.
        XCTAssertFalse(model.selectedIDs.isEmpty)
        XCTAssertTrue(model.selectedIDs.isSubset(of: Set(model.rows.map(\.id))))
        // ungroup keeps the members visible (the ids survive the shrink).
        let stacksNow = try await store.stacks()
        let stack = try XCTUnwrap(stacksNow.first)
        await model.ungroup(stackID: stack.id)
        try await walkToExhaustion()
        XCTAssertEqual(model.rows.count, 10, "the ungrouped members all returned")
        XCTAssertTrue(model.selectedIDs.isSubset(of: Set(model.rows.map(\.id))))
    }
}
