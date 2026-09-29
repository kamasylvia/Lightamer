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
    func apply(filter newFilter: ExifSearchFilter) async throws {
        filter = newFilter
        try await reloadFirstPage()
    }

    /// Apply a new sort (keeping the filter), reset the cursor and refetch.
    /// An illegal key throws the query face's typed violation AFTER the
    /// reset (the collection stays empty until a legal sort is applied).
    func apply(sort newSort: FilterSort) async throws {
        sort = newSort
        try await reloadFirstPage()
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
