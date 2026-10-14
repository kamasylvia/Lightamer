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

    init(queries: LibraryQueries, pageSize: Int = LibraryQueries.defaultPageSize) {
        self.queries = queries
        self.pageSize = pageSize
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
    /// drop out. `nil` = leave semantic mode and reload normally.
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
                filter: filter, sort: sort, anchor: anchor, limit: pageSize)
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
                filter: filter, sort: sort, anchor: tailAnchor, limit: pageSize)
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
                filter: filter, sort: sort, anchor: mainAnchor, limit: pageSize)
            append(page)
            if page.count == pageSize, let last = page.last {
                mainAnchor = LibraryPageAnchor.anchor(of: last, key: sort.key)
                return true
            }
            // Short page = the main segment is done; the NULL tier follows.
            segment = .nullTail
            let remaining = pageSize - page.count
            guard remaining > 0 else { return true }
            let tail = try await queries.searchNullTail(
                filter: filter, sort: sort, anchor: tailAnchor, limit: remaining)
            append(tail)
            advanceTail(after: tail)
            return !tail.isEmpty

        case .nullTail:
            let tail = try await queries.searchNullTail(
                filter: filter, sort: sort, anchor: tailAnchor, limit: pageSize)
            append(tail)
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

    private func append(_ page: [LibraryImageRow]) {
        rows.append(contentsOf: page)
    }

    private func resetCursor() {
        rows.removeAll()
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
}
