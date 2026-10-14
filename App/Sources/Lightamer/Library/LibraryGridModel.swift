import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// LibraryGridModel (Plan M2-3-1 T3, KD-3) — the ONE collection-state consumer
// for every library surface (the P2 grid AND the editor filmstrip — the
// Alcedo "filmstrip and grid share the filtered collection" semantics).
//
// ZERO SQL (the M2-2-3 seam discipline): pagination walks
// `LibraryQueries.searchPage` (the forward keyset) then `searchNullTail`
// (the NULL tier), anchored through `LibraryPageAnchor.anchor(of:key:)`.
// The five-key sort whitelist is the query face's OWN guard (KD-3: never
// re-implemented here — an illegal key surfaces as the typed
// `LibraryError.constraintViolation` through the plain `await`).
//
// FILTER/SORT CHANGES RESET THE CURSOR (KD-3): applying a new filter or sort
// drops the rows, resets both segment anchors and refetches the first page.
// Selection and the current image are model fields that SURVIVE a refetch
// (the Alcedo behavior — selection is user intent, not a pagination
// artifact).
//
// PURE-LOGIC TESTABILITY: every operation is an `async` method over an
// injected `LibraryQueries` actor against a real `.lalb` fixture — no
// dispatch queues, no private schedulers (the plan's Task-injection note:
// awaiting the model's own async face IS the determinism seam).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class LibraryGridModel {

    /// The expanded-mode stack gather (KD-7 ③④, the forward-only fixup) —
    /// the PURE transform the async append wrapper feeds (T4⑦'s Core-side
    /// testable shape; the stateful wiring lives in the pagination legs).
    /// Members of the page's ≥2 stacks are pulled FORWARD to just after the
    /// earliest displayed member of their stack, in stack position order;
    /// members already displayed are NEVER re-pulled (forward-only — the
    /// DECISIONS deviation vs LightCraft's gather-to-first-member), and the
    /// inserted set joins the displayed set.
    static func stackAdjacencyFixup(
        rows: [LibraryImageRow],
        memberships: [Int64: StackMembership],
        memberLists: [Int64: [Int64]],
        supplemental: [Int64: LibraryImageRow],
        displayed: Set<Int64>
    ) -> (rows: [LibraryImageRow], inserted: [Int64], displayed: Set<Int64>) {
        var result = rows
        var shown = displayed
        var rowIndex: [Int64: Int] = [:]
        for (index, row) in result.enumerated() { rowIndex[row.id] = index }
        // Collect per-stack insertions with their anchor (the earliest
        // displayed member index).
        struct Pending {
            let anchor: Int
            let inserts: [LibraryImageRow]
        }
        var pending: [Pending] = []
        for (stackID, members) in memberLists {
            guard members.count >= 2 else { continue }
            // Only stacks the page actually surfaced participate (the
            // memberships gate keeps stray memberLists inert).
            guard memberships.values.contains(where: { $0.stackID == stackID })
            else { continue }
            var anchor: Int?
            var inserts: [LibraryImageRow] = []
            for member in members {
                if let index = rowIndex[member] {
                    anchor = min(anchor ?? index, index)
                } else if !shown.contains(member), let row = supplemental[member] {
                    inserts.append(row)
                }
            }
            guard let anchor, !inserts.isEmpty else { continue }
            pending.append(Pending(anchor: anchor, inserts: inserts))
        }
        // Insert descending by anchor so earlier indices stay valid.
        for item in pending.sorted(by: { $0.anchor > $1.anchor }) {
            result.insert(contentsOf: item.inserts, at: item.anchor + 1)
        }
        for item in pending {
            for row in item.inserts { shown.insert(row.id) }
        }
        return (result, pending.flatMap { $0.inserts.map(\.id) }, shown)
    }

    /// Which keyset segment the cursor is walking. The main segment holds
    /// every row whose sort key is non-NULL; the NULL tier waits in its own
    /// `searchNullTail` walk (every library sort key is nullable).
    private enum Segment {
        case main
        case nullTail
    }

    // MARK: - Collection state (the fields the grid / filmstrip render)

    private(set) var filter = ExifSearchFilter()
    private(set) var sort = FilterSort(key: .filename, ascending: true)

    /// The M2-10-02 semantic overlay (KD-6): the score-ordered hit IDs of
    /// the active CLIP search. Non-nil = the collection IS the semantic
    /// result set (rows render in HIT order, non-hits hidden, the walk is
    /// a finite full sweep); nil = the ordinary keyset collection. Cleared
    /// by every EXIF filter/sort application (the two legs never mix).
    private(set) var semanticHits: [Int64]?

    /// The loaded rows, in walk order (keyset order — already the display
    /// order).
    private(set) var rows: [LibraryImageRow] = []

    /// True when BOTH segments are walked to exhaustion — the collection is
    /// fully loaded; further `loadNextPage` calls are no-ops.
    private(set) var isExhausted = false

    /// The multi-select set (library rowids).
    private(set) var selectedIDs: Set<Int64> = []

    /// The stack display mode (KD-7, M6-4-01): `.collapsed` is the BIRTH
    /// state (with no stacks both modes render identically — the Lightroom
    /// convention); session-scoped, ZERO persistence (no UserDefaults key).
    /// Collapsed mode = the query-face predicate (flag-aware); expanded
    /// mode = the flat walk + the forward-only fixup.
    private(set) var stackDisplayMode: StackDisplayMode = .collapsed

    /// The memberships of the loaded rows (one JOIN per page append) — the
    /// badge projection's single source (T6④).
    private(set) var stackMemberships: [Int64: StackMembership] = [:]

    /// The stack WRITE face (KD-7's command routing). Optional so every
    /// pre-stacks construction site compiles unchanged; the commands
    /// no-op without a store (the shell always passes one).
    private(set) var store: LibraryStore?

    /// The current image (the one the editor is/would be opened on).
    private(set) var currentImageID: Int64?

    /// True while a page fetch is in flight (the shell may show a busy
    /// footer; concurrent page calls collapse onto the running one).
    private(set) var isLoading = false

    // MARK: - Cursor internals

    private var segment: Segment = .main
    private var mainAnchor: LibraryPageAnchor?
    private var tailAnchor: LibraryPageAnchor?

    private let queries: LibraryQueries
    let pageSize: Int

    init(
        queries: LibraryQueries,
        pageSize: Int = LibraryQueries.defaultPageSize,
        store: LibraryStore? = nil
    ) {
        self.queries = queries
        self.pageSize = pageSize
        self.store = store
    }

    // MARK: - Filter / sort application (KD-3: reset + refetch)

    /// Apply a new filter (keeping the sort), reset the cursor and refetch
    /// the first page. Throws when the query face rejects the input (the
    /// whitelist guard is the query face's, passed straight through).
    /// An EXIF filter application EXITS the semantic overlay (the legs are
    /// exclusive — the search model's empty-input clear rides this too).
    func apply(filter newFilter: ExifSearchFilter) async throws {
        semanticHits = nil
        filter = newFilter
        try await reloadFirstPage()
    }

    /// Apply a new sort (keeping the filter), reset the cursor and refetch.
    /// An illegal key throws the query face's typed violation AFTER the
    /// reset (the collection stays empty until a legal sort is applied).
    /// Exits the semantic overlay (hit order is score order — a re-sort is
    /// not a semantic query).
    func apply(sort newSort: FilterSort) async throws {
        semanticHits = nil
        sort = newSort
        try await reloadFirstPage()
    }

    /// The semantic result set (KD-6): a FULL keyset walk of the current
    /// filter/sort (the existing pagination faces — zero new SQL), then the
    /// loaded rows filtered to the hit set IN HIT ORDER (有序表保序过滤).
    /// Hit IDs missing from the walk (deleted rows / other-project ids)
    /// drop out. `nil` = leave semantic mode and reload normally. The walk
    /// carries the stack display mode (the collapsed predicate is a set
    /// filter, orthogonal to ordering — the overlay still bypasses the
    /// FIXUP; hit order IS the display order, the two legs never mix).
    func apply(semanticHits newHits: [Int64]?) async throws {
        semanticHits = newHits
        guard let hits = newHits else {
            try await reloadFirstPage()
            return
        }
        let pageSize = 500
        let hitSet = Set(hits)
        var byID: [Int64: LibraryImageRow] = [:]
        byID.reserveCapacity(hits.count)
        // Segment 1: the main keyset walk (non-NULL sort keys).
        var anchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchPage(
                filter: filter, sort: sort, anchor: anchor, limit: pageSize,
                stackMode: stackDisplayMode)
            for row in page where hitSet.contains(row.id) { byID[row.id] = row }
            guard page.count == pageSize,
                  let last = page.last, let next = LibraryPageAnchor.anchor(of: last, key: sort.key)
            else { break }
            anchor = next
        }
        // Segment 2: the NULL tier (rows whose sort key IS NULL).
        var tailAnchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchNullTail(
                filter: filter, sort: sort, anchor: tailAnchor, limit: pageSize,
                stackMode: stackDisplayMode)
            for row in page where hitSet.contains(row.id) { byID[row.id] = row }
            guard page.count == pageSize, let last = page.last else { break }
            tailAnchor = LibraryPageAnchor(
                keyValue: .int(nil), imagePath: last.imagePath)
        }
        // The hit-ordered projection (score order — the engine's contract).
        rows = hits.compactMap { byID[$0] }
        // A finite result set: the pager's further walks are no-ops.
        isExhausted = true
        segment = .main
        mainAnchor = nil
        tailAnchor = nil
        selectedIDs = selectedIDs.filter { byID[$0] != nil }
        await refreshStackMemberships(for: rows)
    }

    /// Apply filter AND sort in one reset + refetch.
    func apply(
        filter newFilter: ExifSearchFilter, sort newSort: FilterSort
    ) async throws {
        filter = newFilter
        sort = newSort
        try await reloadFirstPage()
    }

    /// Drop every row + both anchors, then fetch the first page.
    func reloadFirstPage() async throws {
        resetCursor()
        try await loadNextPage()
    }

    // MARK: - Keyset pagination (KD-3: no gap, no overlap, NULL tail last)

    /// Walk the next page (main segment first, then the NULL tail). Returns
    /// true when rows were appended; false = exhausted (or a fetch already
    /// running).
    @discardableResult
    func loadNextPage() async throws -> Bool {
        guard !isExhausted, !isLoading else { return false }
        isLoading = true
        defer { isLoading = false }

        switch segment {
        case .main:
            let page = try await queries.searchPage(
                filter: filter, sort: sort, anchor: mainAnchor, limit: pageSize,
                stackMode: stackDisplayMode)
            await append(page)
            if page.count == pageSize, let last = page.last {
                mainAnchor = LibraryPageAnchor.anchor(of: last, key: sort.key)
                return true
            }
            // Short page = the main segment is done; the NULL tier follows.
            segment = .nullTail
            let remaining = pageSize - page.count
            guard remaining > 0 else { return true }
            let tail = try await queries.searchNullTail(
                filter: filter, sort: sort, anchor: tailAnchor, limit: remaining,
                stackMode: stackDisplayMode)
            await append(tail)
            advanceTail(after: tail)
            return !tail.isEmpty

        case .nullTail:
            let tail = try await queries.searchNullTail(
                filter: filter, sort: sort, anchor: tailAnchor, limit: pageSize,
                stackMode: stackDisplayMode)
            await append(tail)
            advanceTail(after: tail)
            return !tail.isEmpty
        }
    }

    /// The NULL-tier cursor: `.anchor(of:key:)` answers nil for NULL-key
    /// rows (that is WHY the tail exists), so the tail anchor is built by
    /// hand — key value unused, `image_path` is the only seek.
    private func advanceTail(after page: [LibraryImageRow]) {
        guard let last = page.last else {
            isExhausted = true
            return
        }
        if page.count < pageSize {
            isExhausted = true
            return
        }
        tailAnchor = LibraryPageAnchor(
            keyValue: .int(nil), imagePath: last.imagePath)
    }

    /// The page-landing leg (KD-7): raw keyset append + the expanded-mode
    /// fixup + the badge-membership refresh. In collapsed mode (or under
    /// the semantic overlay) the page rows ARE the display order — the raw
    /// append only.
    private func append(_ page: [LibraryImageRow]) async {
        guard !page.isEmpty else { return }
        if stackDisplayMode == .collapsed || semanticHits != nil {
            rows.append(contentsOf: page)
        } else {
            // The displayed-set guard (S2): a keyset row already pulled
            // forward by an earlier page's fixup NEVER lands twice — the
            // anchor advance below still rides the RAW page's last row.
            let displayed = Set(rows.map(\.id))
            rows.append(contentsOf: page.filter { !displayed.contains($0.id) })
            await runFixup(for: page)
        }
        await refreshStackMemberships(for: page)
    }

    /// The forward-only fixup's async wrapper (KD-7 ①②→③④): discover the
    /// page's stacks, pull the missing members, then the pure transform.
    private func runFixup(for page: [LibraryImageRow]) async {
        let pageIDs = page.map(\.id)
        guard let pageMemberships = try? await queries.stackMemberships(
            ids: pageIDs), !pageMemberships.isEmpty else { return }
        let stackIDs = Set(
            pageMemberships.values.filter { $0.size >= 2 }.map(\.stackID))
        guard !stackIDs.isEmpty,
            let memberLists = try? await queries.stackMembers(
                ofStacks: Array(stackIDs))
        else { return }
        let shown = Set(rows.map(\.id))
        let missing = memberLists.values.flatMap { $0 }
            .filter { !shown.contains($0) }
        guard !missing.isEmpty,
            let supplementalRows = try? await queries.rows(byIDs: missing)
        else { return }
        let supplemental = Dictionary(
            uniqueKeysWithValues: supplementalRows.map { ($0.id, $0) })
        let outcome = Self.stackAdjacencyFixup(
            rows: rows,
            memberships: pageMemberships,
            memberLists: memberLists,
            supplemental: supplemental,
            displayed: shown)
        rows = outcome.rows
    }

    /// Merge the memberships of the given rows into the badge map (one
    /// JOIN per page — bounded by the page size).
    private func refreshStackMemberships(for page: [LibraryImageRow]) async {
        guard !page.isEmpty,
            let fetched = try? await queries.stackMemberships(ids: page.map(\.id))
        else { return }
        stackMemberships.merge(fetched) { _, new in new }
    }

    private func resetCursor() {
        rows.removeAll()
        stackMemberships.removeAll()
        segment = .main
        mainAnchor = nil
        tailAnchor = nil
        isExhausted = false
    }

    // MARK: - Selection / current image state machine

    /// Plain click: the selection collapses onto one row. The row must be
    /// loaded (selection is a visible-row gesture).
    func selectSingle(_ id: Int64) {
        guard rows.contains(where: { $0.id == id }) else { return }
        selectedIDs = [id]
    }

    /// Cmd-click toggle: add to / remove from the multi-select.
    func toggleSelection(_ id: Int64) {
        guard rows.contains(where: { $0.id == id }) else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Replace the whole selection (rubber-band / select-all faces).
    func setSelection(_ ids: Set<Int64>) {
        selectedIDs = ids.filter { id in
            rows.contains(where: { $0.id == id })
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    /// The editor entry (double-click / filmstrip activate): sets the
    /// current image and selects it (opening focuses the row).
    func openCurrent(_ id: Int64) {
        guard rows.contains(where: { $0.id == id }) else { return }
        currentImageID = id
        selectedIDs = [id]
    }

    /// Clear the current image (project close / row removal faces).
    func clearCurrentImage() {
        currentImageID = nil
    }

    // MARK: - Stack commands (KD-7, M6-4-01)

    /// The badge projection (T6④): the row's stack membership when the
    /// stack is real (≥2 members). The view decides cover/member rendering
    /// from `position` and `collapsed`.
    func stackBadge(for imageID: Int64) -> StackMembership? {
        guard let membership = stackMemberships[imageID], membership.size >= 2
        else { return nil }
        return membership
    }

    /// Switch the display mode (the collapsed predicate ↔ the flat walk +
    /// fixup) and reload. Zero stacks ⇒ both modes render identically.
    func setStackDisplayMode(_ mode: StackDisplayMode) async throws {
        guard mode != stackDisplayMode else { return }
        stackDisplayMode = mode
        try await reloadFirstPage()
    }

    /// The per-stack collapse toggle (the badge chevron): flip the stack's
    /// flag, reload. In collapsed mode the expanded stack's members then
    /// appear at their keyset positions (the gather is a global-expanded
    /// property — the DECISIONS-registered v1 semantics).
    func toggleCollapse(stackID: Int64) async {
        guard let store else { return }
        let current = stackMemberships.values
            .first { $0.stackID == stackID }?.collapsed ?? true
        try? await store.setCollapsed(stackID: stackID, collapsed: !current)
        await reloadShrinkingSelection()
    }

    /// Expand every stack (unfold all flags + the gathered expanded view).
    func expandAll() async {
        guard let store else { return }
        try? await store.setAllCollapsed(false)
        stackDisplayMode = .flat
        await reloadShrinkingSelection()
    }

    /// Collapse every stack (fold all flags + the cover-only view).
    func collapseAll() async {
        guard let store else { return }
        try? await store.setAllCollapsed(true)
        stackDisplayMode = .collapsed
        await reloadShrinkingSelection()
    }

    /// Group the selection (LightCraft group union; ≥2 members gate — a
    /// smaller selection is a no-op). Reload + selection shrink after.
    func groupSelection() async {
        guard let store else { return }
        let ordered = rows.map(\.id).filter { selectedIDs.contains($0) }
        guard ordered.count >= 2 else { return }
        _ = try? await store.group(memberIDs: ordered)
        await reloadShrinkingSelection()
    }

    /// Dissolve the stack (ungroup — the ONLY reverse move; the KD-3
    /// no-undo posture).
    func ungroup(stackID: Int64) async {
        guard let store else { return }
        try? await store.ungroup(stackID: stackID)
        await reloadShrinkingSelection()
    }

    /// Make the image its stack's cover (setTop). No-op for unstacked rows.
    func setCover(imageID: Int64) async {
        guard let store else { return }
        let containing = try? await store.stackContaining(imageID: imageID)
        guard let stack = containing else { return }
        try? await store.setTop(stackID: stack.id, imageID: imageID)
        await reloadShrinkingSelection()
    }

    /// Remove the image from its stack (the <2 remainder dissolves store-
    /// side). No-op for unstacked rows.
    func removeFromStack(imageID: Int64) async {
        guard let store else { return }
        try? await store.removeFromStacks(imageID: imageID)
        await reloadShrinkingSelection()
    }

    /// The auto-stack entry (KD-7): the pool is the selection when it holds
    /// ≥2 rows, otherwise the FULL current-collection walk (the semantic
    /// overlay's finite hit set, else both keyset segments). `preview`
    /// returns the cluster count and touches NOTHING.
    @discardableResult
    func autoStack(
        gap: Double = StackClustering.defaultGapSeconds, preview: Bool
    ) async throws -> Int {
        let pool: [Int64]
        let selectedOrder = rows.map(\.id).filter { selectedIDs.contains($0) }
        if selectedOrder.count >= 2 {
            pool = selectedOrder
        } else if let hits = semanticHits {
            pool = hits
        } else {
            pool = try await collectAllIDs()
        }
        guard let store else { return 0 }
        let count = try await store.autoStack(ids: pool, gap: gap, preview: preview)
        if !preview {
            await reloadShrinkingSelection()
        }
        return count
    }

    /// Reload + shrink the selection to the rows that survived (KD-7's
    /// post-write face — v1 keeps no scroll position, DECISIONS-registered).
    private func reloadShrinkingSelection() async {
        try? await reloadFirstPage()
        selectedIDs = selectedIDs.filter { id in
            rows.contains(where: { $0.id == id })
        }
    }

    /// The full-collection id walk (the apply(semanticHits:) shape, ids
    /// only — the autoStack pool's default face).
    private func collectAllIDs() async throws -> [Int64] {
        var ids: [Int64] = []
        let pageSize = 500
        var anchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchPage(
                filter: filter, sort: sort, anchor: anchor, limit: pageSize)
            ids.append(contentsOf: page.map(\.id))
            guard page.count == pageSize,
                let last = page.last,
                let next = LibraryPageAnchor.anchor(of: last, key: sort.key)
            else { break }
            anchor = next
        }
        var tailAnchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchNullTail(
                filter: filter, sort: sort, anchor: tailAnchor, limit: pageSize)
            ids.append(contentsOf: page.map(\.id))
            guard page.count == pageSize, let last = page.last else { break }
            tailAnchor = LibraryPageAnchor(
                keyValue: .int(nil), imagePath: last.imagePath)
        }
        return ids
    }
}
