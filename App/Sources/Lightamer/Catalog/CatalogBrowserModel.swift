import Foundation
import LightamerCore
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// CatalogBrowserModel (Plan 16-2 T3, fed by the T2 sidebar) — the CROSS-
// SESSION grid's data face.
//
// SEAM a red line: ZERO SQL here. The data source is the 16-1
// `CatalogIndexStore` keyset face ONLY (queryPage / queryNullTail) — the
// 12-2 filter bar's predicate groups ride `FilterDomain.catalog`
// translation inside the store; the scope anchors (session grouping click,
// the 16-3 category/collection slots) ride `FilterScope`.
//
// PAGINATION = the keyset TWO-SEGMENT shape consumed for UI:
//   main segment (the ordering index walk) → exhausted → the NULL tail
//   segment continues (nullable keys only: capture_date / rating; filename
//   is never NULL). No overlap, no gap — the store's keyset suite pins the
//   seam; the model adds the SCROLL face: pages append until `endReached`.
//   v1 = scroll loading (no page numbers; execution decision).
//
// SORT: the catalog-serviceable whitelist ONLY (captureDate / rating /
// filename — 16-1 pins the typed error for the rest; scan_epoch is not
// mirrored and never sorts). Default = date DESC (research §1.5).
//
// FILTER STATE: the catalog face of the 12-2 filter bar (chips + Quick
// Filter + the active smart album). Mutual exclusion matches the session
// face: an active smart album REPLACES the chip set. The state is
// CATALOG-LOCAL — the session grid's SessionState is never touched (the
// Sessions-mode byte-equivalence red line).
//
// REFRESH (the T6 edit loop): a projection committed under the grid means
// the loaded window may be stale; `refreshAfterProjection` re-runs the
// ACTIVE query over the window (watermark-catch-up semantics — the row
// set and overlay values re-derive from the committed catalog; execution
// decision: full window re-query, no in-place merge). Selection repairs
// onto surviving identities.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class CatalogBrowserModel {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "catalog-browser")

    // MARK: - Row model (the (session_id, rel_path) composite identity)

    struct Row: Identifiable, Hashable {
        let sessionID: String
        let relPath: String
        /// Stable 16-hex hash over the composite identity (L013 primitive;
        /// L010 cell ids derive from it — never an index).
        let pathHash: String
        let dir: String?
        let filename: String?
        let hasEdits: Bool
        let rating: Int64?
        let colorLabel: Int64?
        let flag: Int64?
        let captureDate: Double?
        let width: Int64?
        let height: Int64?

        /// The composite identity string (session_id is a UUID — no `/`).
        var id: String { sessionID + "/" + relPath }
    }

    /// The loaded window (keyset order — query order IS the display order).
    private(set) var rows: [Row] = []

    // MARK: - Query state (the catalog filter bar's face)

    private(set) var activeGroups: [FilterPredicateGroup] = []
    private(set) var activeSort: FilterSort = CatalogBrowserModel.defaultSort
    private(set) var activeScope = FilterScope()

    /// The active smart album (nil = the plain chip face; activation
    /// REPLACES the chips — the 12-2 mutual-exclusion decision, catalog
    /// face). The GROUP rides the id so re-queries need no store lookup.
    private(set) var activeSmartAlbumID: String?
    private(set) var activeSmartAlbumGroup: FilterPredicateGroup?

    /// The catalog-local chips (never the session grid's SessionState).
    private(set) var filterChips: [FilterPredicateGroup.Rule] = []

    /// The Quick Filter text (raw; the group folds on read). Catalog-domain
    /// filename/dir contains = case-sensitive startsWith (16-1 downgrade).
    private(set) var quickFilterText: String = ""

    /// Revision bump — the View layer's onChange anchor.
    private(set) var queryRevision = 0

    nonisolated static let defaultSort = FilterSort(key: .captureDate, ascending: false)

    // MARK: - Pagination state (keyset cursors)

    private(set) var isLoadingPage = false
    private(set) var endReached = false
    private var mainAnchor: CatalogPageAnchor?
    private var tailAnchor: CatalogPageAnchor?
    private var mainExhausted = false

    nonisolated static let pageSize = CatalogIndexStore.defaultPageSize

    // MARK: - Selection (data face; ⌘/⇧ semantics — the 09-3 mirror)

    private(set) var selectedIdentities: Set<String> = []
    private(set) var selectionAnchorID: String?

    /// The selection projected onto the collection order (batch targets).
    var selectedOrderedIdentities: [String] {
        rows.map(\.id).filter { selectedIdentities.contains($0) }
    }

    private var store: CatalogIndexStore?

    // MARK: - Wiring

    func configure(store: CatalogIndexStore) {
        self.store = store
    }

    // MARK: - Query composition (the SessionState.queryGroups mirror)

    /// The active groups (smart album replaces the chip face; the Quick
    /// Filter folds as its own group — the 12-2 composition verbatim).
    var queryGroups: [FilterPredicateGroup] {
        if let group = activeSmartAlbumGroup { return [group] }
        var groups: [FilterPredicateGroup] = []
        if !filterChips.isEmpty {
            groups.append(FilterPredicateGroup(match: .all, rules: filterChips))
        }
        let trimmed = quickFilterText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            groups.append(.quickFilter(text: trimmed))
        }
        return groups
    }

    var hasActiveFilter: Bool {
        !filterChips.isEmpty || !quickFilterText.isEmpty || activeSmartAlbumID != nil
    }

    // MARK: - The filter bar's state entries

    func setFilterChips(_ chips: [FilterPredicateGroup.Rule]) {
        filterChips = chips
        requery()
    }

    func toggleChip(_ chip: FilterPredicateGroup.Rule) {
        if let index = filterChips.firstIndex(of: chip) {
            filterChips.remove(at: index)
        } else {
            filterChips.append(chip)
        }
        requery()
    }

    func removeChip(_ chip: FilterPredicateGroup.Rule) {
        filterChips.removeAll { $0 == chip }
        requery()
    }

    func setQuickFilterText(_ text: String) {
        quickFilterText = text
        requery()
    }

    func setSort(_ sort: FilterSort) {
        activeSort = sort
        requery()
    }

    /// Smart-album activation (the D-12-CONTEXT-4 semantics, catalog face:
    /// the album's group replaces the chips; re-click deactivates).
    func activateSmartAlbum(id: String?, group: FilterPredicateGroup?) {
        activeSmartAlbumID = id
        activeSmartAlbumGroup = group
        if id != nil { filterChips = [] }
        requery()
    }

    /// Clear every filter face (the ⓫ in the filter bar).
    func clearFilters() {
        guard hasActiveFilter else { return }
        filterChips = []
        quickFilterText = ""
        activeSmartAlbumID = nil
        activeSmartAlbumGroup = nil
        requery()
    }

    /// The scope anchor (the sidebar's click face): All Photographs = the
    /// default scope; a session-grouping click = the sessionID anchor; the
    /// category/collection slots stay nil until 16-3 wires them.
    func setScope(_ scope: FilterScope) {
        activeScope = scope
        requery()
    }

    private func requery() {
        queryRevision += 1
    }

    // MARK: - Query execution (keyset two-segment, scroll-loaded)

    /// Install the ACTIVE query state and reload from the top (the sidebar
    /// and filter-bar entries all land here; requery bumps drive the
    /// View-layer call).
    func apply(groups: [FilterPredicateGroup]? = nil, sort: FilterSort? = nil,
               scope: FilterScope? = nil) async {
        if let groups { activeGroups = groups }
        if let sort { activeSort = sort }
        if let scope { activeScope = scope }
        await reload()
    }

    /// Reset the cursors and load the first page(s).
    func reload() async {
        resetCursors()
        await loadMore()
    }

    /// Scroll loading: append the next page — main segment first, then the
    /// NULL tail continues (nullable keys). Idempotent at the end.
    func loadMore() async {
        guard !isLoadingPage, !endReached, let store else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        let groups = queryGroups
        if !mainExhausted {
            let page = (try? await store.queryPage(
                groups: groups, sort: activeSort, scope: activeScope,
                anchor: mainAnchor, limit: Self.pageSize)) ?? []
            if let last = page.last {
                mainAnchor = anchor(of: last)
                // NULL rows sort LAST within the main ORDER BY: a page that
                // ENDS on a NULL-keyed row has already emitted the tier's
                // head (the one-shot order and the seek pages diverge only
                // here — the seek itself cannot re-enter the NULL tier).
                // Seed the tail anchor so the tier CONTINUES, never
                // re-emits (无重).
                if tailAnchor == nil, Self.isNullKeyRow(last, key: activeSort.key) {
                    tailAnchor = CatalogPageAnchor(
                        keyValue: .text(last.relPath), relPath: last.relPath)
                }
            }
            append(page)
            if page.count < Self.pageSize {
                mainExhausted = true
                if !Self.isNullableKey(activeSort.key) { endReached = true }
            }
        }
        if mainExhausted, !endReached, Self.isNullableKey(activeSort.key) {
            let page = (try? await store.queryNullTail(
                groups: groups, sort: activeSort, scope: activeScope,
                anchor: tailAnchor, limit: Self.pageSize)) ?? []
            if let last = page.last {
                tailAnchor = CatalogPageAnchor(keyValue: .text(last.relPath), relPath: last.relPath)
            }
            append(page)
            if page.count < Self.pageSize { endReached = true }
        }
    }

    /// The T6 edit loop's refresh face: re-run the ACTIVE query over the
    /// window (watermark catch-up — a committed projection changes row
    /// values/rows; the grid re-derives from the catalog). Selection
    /// repairs onto surviving identities.
    func refreshAfterProjection() async {
        let count = rows.count
        resetCursors()
        while rows.count < count || (!endReached && rows.isEmpty) {
            let before = rows.count
            await loadMore()
            if rows.count == before { break }
        }
        let alive = Set(rows.map(\.id))
        selectedIdentities.formIntersection(alive)
        if let anchor = selectionAnchorID, !alive.contains(anchor) {
            selectionAnchorID = nil
        }
    }

    // MARK: - Batch metadata (Plan 16-2 T6; RQ-16-10)

    /// The cross-session batch rating. NO new write path: the selection is
    /// grouped by session and each session's slice rides the EXISTING
    /// three-leg semantics (MetadataService → the leg-2 index transaction +
    /// the leg-3 sidecar queue) over that session's OWN lindex; the
    /// projector then catches the session up (the COUNT memo dies with
    /// every commit) and the grid refreshes (watermark catch-up).
    func batchSetRating(_ value: Int?, identities: [String]) async {
        await batchApply(identities: identities) { service, relPaths in
            try await service.setRating(value, relPaths: relPaths)
        }
    }

    /// The cross-session batch flag (Pick/Reject/clear).
    func batchSetFlag(_ value: Int?, identities: [String]) async {
        await batchApply(identities: identities) { service, relPaths in
            try await service.setFlag(value, relPaths: relPaths)
        }
    }

    /// The cross-session batch color label.
    func batchSetColorLabel(_ value: Int?, identities: [String]) async {
        await batchApply(identities: identities) { service, relPaths in
            try await service.setColorLabel(value, relPaths: relPaths)
        }
    }

    /// The grouped batch leg (see the faces above). Per session: open the
    /// lindex (the real open+sync), one MetadataService slice, flush the
    /// sidecar queue BEFORE the index closes, then the immediate
    /// projection. A failing session logs and continues (SC#2 — the other
    /// sessions' slices still land).
    private func batchApply(
        identities: [String],
        _ body: @escaping (MetadataService, [String]) async throws -> Void
    ) async {
        // Group the composite identities per session.
        var bySession: [String: [String]] = [:]
        for identity in identities {
            guard let split = identity.firstIndex(of: "/") else { continue }
            bySession[String(identity[..<split]), default: []]
                .append(String(identity[identity.index(after: split)...]))
        }
        guard !bySession.isEmpty, let catalogStore = store else { return }

        // The roots (the registry read; unknown sessions are skipped).
        let registry = (try? await catalogStore.fetchSessions()) ?? []
        let roots = Dictionary(
            registry.map { ($0.sessionID, URL(fileURLWithPath: $0.rootPath, isDirectory: true)) },
            uniquingKeysWith: { first, _ in first })

        for (sessionID, relPaths) in bySession {
            guard let root = roots[sessionID] else { continue }
            let lindexStore = SessionIndexStore(sessionRoot: root)
            let writer = BatchSidecarWriter(root: root, store: lindexStore)
            do {
                _ = try await lindexStore.openSession(
                    root: root, scan: SessionTreeScanner.scan(root: root))
                let service = MetadataService(
                    root: root, store: lindexStore, writer: writer, seed: [])
                try await body(service, relPaths)
                // The leg-3 queue lands BEFORE the index closes.
                await writer.flushForTeardown()
            } catch {
                Self.logger.error(
                    "catalog batch slice failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            await lindexStore.close()
            // 投影追平 (the enable guard lives inside the projector).
            _ = try? await SessionIndexController.sharedCatalogProjector
                .project(sessionRoot: root)
        }
        await refreshAfterProjection()
    }

    private func resetCursors() {
        rows = []
        mainAnchor = nil
        tailAnchor = nil
        mainExhausted = false
        endReached = false
    }

    private func append(_ page: [CatalogIndexRow]) {
        rows.append(contentsOf: page.map(Self.project))
    }

    private func anchor(of row: CatalogIndexRow) -> CatalogPageAnchor {
        switch activeSort.key {
        case .captureDate:
            CatalogPageAnchor(keyValue: .double(row.captureDate), relPath: row.relPath)
        case .rating:
            CatalogPageAnchor(keyValue: .int(row.rating), relPath: row.relPath)
        case .filename:
            CatalogPageAnchor(keyValue: .text(row.filename), relPath: row.relPath)
        case .iso, .focalLength, .scanEpoch:
            // The store throws the typed error first; this arm only keeps
            // the switch exhaustive (never reachable through the UI — the
            // sort menu whitelists the three catalog keys).
            CatalogPageAnchor(keyValue: .text(row.relPath), relPath: row.relPath)
        }
    }

    nonisolated private static func isNullableKey(_ key: FilterSortKey) -> Bool {
        key == .captureDate || key == .rating
    }

    /// True when the row's sort-key value is NULL (the tier-boundary probe
    /// for the tail-anchor seeding above).
    nonisolated private static func isNullKeyRow(
        _ row: CatalogIndexRow, key: FilterSortKey
    ) -> Bool {
        switch key {
        case .captureDate: row.captureDate == nil
        case .rating: row.rating == nil
        case .filename: false
        case .iso, .focalLength, .scanEpoch: false
        }
    }

    private static func project(_ row: CatalogIndexRow) -> Row {
        Row(
            sessionID: row.sessionID,
            relPath: row.relPath,
            pathHash: ThumbnailPath.hash(row.sessionID + "/" + row.relPath),
            dir: row.dir,
            filename: row.filename,
            hasEdits: row.hasEdits == 1,
            rating: row.rating,
            colorLabel: row.colorLabel,
            flag: row.flag,
            captureDate: row.captureDate,
            width: row.width,
            height: row.height
        )
    }

    // MARK: - Selection (the 09-3 handleClick mirror over identities)

    func handleClick(
        _ identity: String, commandPressed: Bool, shiftPressed: Bool
    ) {
        guard rows.contains(where: { $0.id == identity }) else { return }
        if shiftPressed, let anchor = selectionAnchorID,
           let from = rows.firstIndex(where: { $0.id == anchor }),
           let to = rows.firstIndex(where: { $0.id == identity }) {
            let range = min(from, to)...max(from, to)
            selectedIdentities.formUnion(rows[range].map(\.id))
            return // ⇧ never moves the anchor
        }
        if commandPressed {
            if selectedIdentities.contains(identity) {
                selectedIdentities.remove(identity)
            } else {
                selectedIdentities.insert(identity)
            }
        } else {
            selectedIdentities = [identity]
        }
        selectionAnchorID = identity
    }
}
