import Foundation
import LightamerCore
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// SessionBrowserModel (Plan 09-03 T1) — the grid's DATA face.
//
// RESEARCH §5.1: the browse collection is an INDEX-DRIVEN projection — a
// `SessionIndexStore` ordered read into an in-memory array (dt collection.c
// model: one assembled query, 10k rows in memory is zero pressure). The row
// carries NO image data: the thumbnail tier (LRU/disk/render queue) lives in
// the Core `SessionThumbnailProvider`; cells resolve their CGImage through
// it. No MTLTexture is ever held here (the D-C1 contract — the shared session cache only
// ever serves the CURRENTLY EDITED image).
//
// Selection is the DATA face only (⌘ toggle / ⇧ range); the View layer
// (T5) maps keyboard modifiers onto `handleClick`. Progressive ingest: the
// model upserts scanner pages as PLACEHOLDER rows while the walk runs (the
// grid renders while scanning — 9-1's stream seam), then the authoritative
// reload lands when the sync transaction commits.
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class SessionBrowserModel {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "session-browser"
    )

    // MARK: - Row model (index projection — no image data)

    struct Row: Identifiable, Equatable {
        /// Relative path vs session root — the row identity (L010: cell ids
        /// are `browser.cell.<pathhash>`, derived via `ThumbnailPath.hash`).
        let relPath: String
        /// Stable 16-hex path hash (L013 primitive — identifier + file name).
        let pathHash: String
        let dir: String
        let filename: String
        /// The DOUBLE-TIER ruling input (RESEARCH §5.2: tier = has_edits
        /// ONLY). Placeholder rows (progressive ingest) carry false until
        /// the authoritative reload.
        let hasEdits: Bool
        let orphanSidecar: Bool
        /// Raw `thumb_state` (0 none / 1 embedded / 2 rendered / 3 stale;
        /// nil = placeholder).
        let thumbState: Int64?
        let thumbParamsHash: String?
        /// 09-04: the batch-apply claim window (sidecar not yet written) —
        /// the cell's「进行中」badge source (the window is NEVER silent,
        /// D-09-CONTEXT-4).
        let dirty: Bool
        /// 12-1 T6 (META-01/05): the metadata overlay face — real star
        /// fills, the color-label dot and the flag badge render from
        /// these (nil = not set).
        let rating: Int64?
        let colorLabel: Int64?
        let flag: Int64?

        var id: String { relPath }
    }

    /// The ordered collection (ORDER BY path — the schema's frozen sort).
    private(set) var rows: [Row] = []

    // MARK: - Selection (data face; ⌘/⇧ semantics)

    /// Selected relPaths (unordered set; `selectedOrderedPaths` projects
    /// onto the collection order).
    private(set) var selectedPaths: Set<String> = []

    /// The ⇧ range anchor (last non-shift click).
    private(set) var selectionAnchor: String?

    // MARK: - Progressive ingest (9-1 stream seam)

    /// True between the first scanner page and the authoritative reload.
    private(set) var progressiveIngestActive = false

    /// The ingest timing record (test assertion face — T5's "first cells
    /// BEFORE the walk finishes"): when the first page landed and how many
    /// placeholder rows it contributed.
    struct IngestTrace: Equatable {
        var firstPageRows = 0
        var placeholderUpserts = 0
        var pagesConsumed = 0
    }
    private(set) var lastIngestTrace = IngestTrace()

    // MARK: - Collection load

    /// The ACTIVE query state (Plan 12-2 T4): the filter bar sets these
    /// through `applyFilter`; the LEGACY reload callers (progressive-ingest
    /// finish, metadata-write refresh, batch paste) then automatically ride
    /// the user's chosen filter/sort instead of resetting it — the
    /// metadata-write refresh must not drop the user's sort.
    private(set) var activeFilterGroups: [FilterPredicateGroup] = []
    private(set) var activeSort: FilterSort?

    /// Authoritative reload from the index store (filter-aware: the ACTIVE
    /// query state rides the store's query face; empty groups + nil sort =
    /// the legacy ORDER-BY-path read). `includeOrphans` (the grid passes
    /// true): orphan rows ride the grid as placeholder cells with the
    /// orphan badge (9-2's sidebar actions own the disposition; SC#2 — the
    /// orphan is VISIBLE, never a hard failure). WITH an active filter the
    /// query's `orphan_sidecar = 0` baseline excludes orphans by design.
    func reload(store: SessionIndexStore, includeOrphans: Bool = false) async {
        var allRows: [SessionIndexRow]
        if activeFilterGroups.isEmpty && activeSort == nil {
            allRows = (try? await store.fetchAllRows()) ?? []
        } else {
            allRows = (try? await store.query(
                groups: activeFilterGroups, sort: activeSort)) ?? []
        }
        rows = allRows
            .filter { includeOrphans || $0.orphanSidecar != 1 }
            .map(Self.project)
        // Selection repair: drop selections whose row vanished (reconcile
        // removed the file; a stale selection must never drive a paste).
        let alive = Set(rows.map(\.relPath))
        selectedPaths.formIntersection(alive)
        if let anchor = selectionAnchor, !alive.contains(anchor) {
            selectionAnchor = nil
        }
    }

    /// The filter bar's re-query entry (Plan 12-2 T4): install the ACTIVE
    /// query state, then reload. Empty groups + nil sort restores the
    /// legacy read.
    func applyFilter(
        store: SessionIndexStore,
        groups: [FilterPredicateGroup],
        sort: FilterSort?,
        includeOrphans: Bool = false
    ) async {
        activeFilterGroups = groups
        activeSort = sort
        await reload(store: store, includeOrphans: includeOrphans)
    }

    /// Install the ACTIVE query state WITHOUT reloading (the session-open
    /// path: the app root installs the persisted sort/filter from
    /// SessionState BEFORE the authoritative reload, so the first grid
    /// paint of a (re)launched app already rides the user's sort — the
    /// filter PICKER restores from UserDefaults, the model must match it).
    func installQueryState(groups: [FilterPredicateGroup], sort: FilterSort?) {
        activeFilterGroups = groups
        activeSort = sort
    }

    /// A progressive-ingest placeholder page (scanner stream, T5 wiring):
    /// upsert rows the authoritative collection does not have YET. The
    /// placeholder carries hasEdits=false + thumbState=nil — cells render
    /// the placeholder gradient and DO NOT enqueue thumbnail work until the
    /// authoritative reload lands (the double-tier ruling must never run on
    /// a guess; execution decision D5). 12-2: SUPPRESSED while a filter is
    /// active (placeholder rows cannot be matched against the query — the
    /// authoritative reload lands when the sync commits anyway).
    func ingestPlaceholderPage(entries: [SessionScanEntry]) {
        guard !entries.isEmpty else { return }
        guard activeFilterGroups.isEmpty else { return }
        progressiveIngestActive = true
        lastIngestTrace.pagesConsumed += 1
        if lastIngestTrace.firstPageRows == 0 {
            lastIngestTrace.firstPageRows = entries.count
        }
        let known = Set(rows.map(\.relPath))
        var appended = 0
        for entry in entries where !known.contains(entry.relPath) {
            rows.append(
                Row(
                    relPath: entry.relPath,
                    pathHash: ThumbnailPath.hash(entry.relPath),
                    dir: Self.directory(of: entry.relPath),
                    filename: (entry.relPath as NSString).lastPathComponent,
                    hasEdits: false,
                    orphanSidecar: false,
                    thumbState: nil,
                    thumbParamsHash: nil,
                    dirty: false,
                    rating: nil,
                    colorLabel: nil,
                    flag: nil
                )
            )
            appended += 1
        }
        lastIngestTrace.placeholderUpserts += appended
    }

    /// The authoritative reload AFTER a progressive sync — clears the
    /// placeholder flag (the trace persists for the T5 timing assertion).
    /// `includeOrphans` passes through (the grid shows orphan placeholder
    /// cells; the sidebar owns their disposition actions).
    func finishProgressiveIngest(store: SessionIndexStore, includeOrphans: Bool = false) async {
        await reload(store: store, includeOrphans: includeOrphans)
        progressiveIngestActive = false
    }

    /// Session teardown: rows + selection reset (leak-assertion face:
    /// `rows.isEmpty && selectedPaths.isEmpty` after a switch).
    func reset() {
        rows = []
        selectedPaths = []
        selectionAnchor = nil
        progressiveIngestActive = false
        lastIngestTrace = IngestTrace()
    }

    // MARK: - Selection semantics (⌘ toggle / ⇧ range / plain single)

    /// Click handling (the View layer passes modifier state verbatim).
    /// - ⇧ with an anchor → the anchor..path range (collection order) ALL
    ///   select; the anchor does NOT move.
    /// - ⌘ → toggle the one row; the anchor moves to it.
    /// - plain → single select; the anchor moves to it.
    func handleClick(_ relPath: String, commandPressed: Bool, shiftPressed: Bool) {
        guard rows.contains(where: { $0.relPath == relPath }) else { return }
        if shiftPressed, let anchor = selectionAnchor,
           let from = rows.firstIndex(where: { $0.relPath == anchor }),
           let to = rows.firstIndex(where: { $0.relPath == relPath }) {
            let range = min(from, to)...max(from, to)
            selectedPaths.formUnion(rows[range].map(\.relPath))
            return // ⇧ never moves the anchor
        }
        if commandPressed {
            if selectedPaths.contains(relPath) {
                selectedPaths.remove(relPath)
            } else {
                selectedPaths.insert(relPath)
            }
        } else {
            selectedPaths = [relPath]
        }
        selectionAnchor = relPath
    }

    /// Extend a range without a click (keyboard ⇧⌘A-style extensions in
    /// later phases) — currently the menu-driven "select all" leg.
    func selectAll() {
        selectedPaths = Set(rows.map(\.relPath))
        selectionAnchor = rows.last?.relPath
    }

    func clearSelection() {
        selectedPaths = []
        selectionAnchor = nil
    }

    /// The selection in COLLECTION order (paste/batch apply consume this —
    /// order-stable vectors, not set iteration).
    var selectedOrderedPaths: [String] {
        rows.map(\.relPath).filter { selectedPaths.contains($0) }
    }

    // MARK: - Projection

    private static func project(_ row: SessionIndexRow) -> Row {
        Row(
            relPath: row.path,
            pathHash: ThumbnailPath.hash(row.path),
            dir: row.dir ?? directory(of: row.path),
            filename: row.filename ?? (row.path as NSString).lastPathComponent,
            hasEdits: row.hasEdits == 1,
            orphanSidecar: row.orphanSidecar == 1,
            thumbState: row.thumbState,
            thumbParamsHash: row.thumbParamsHash,
            dirty: row.dirty == 1,
            rating: row.rating,
            colorLabel: row.colorLabel,
            flag: row.flag
        )
    }

    private static func directory(of relPath: String) -> String {
        let ns = relPath as NSString
        let dir = ns.deletingLastPathComponent
        return dir.isEmpty ? "." : dir
    }
}
