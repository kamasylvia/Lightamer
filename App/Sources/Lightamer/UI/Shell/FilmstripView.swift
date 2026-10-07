import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// FilmstripView + FilmstripModel (Plan M2-3-1 T4, KD-5) — the VERTICAL
// filmstrip (the user-revision signature: the strip rides the EDITOR'S LEFT
// edge, NOT Alcedo's bottom; the P3 three-section layout mounts it there).
//
// VIRTUALIZATION (the first constraint — 10k-row scroll): SwiftUI `List` is
// the lazy container (macOS list cells materialize on viewport entry), rows
// carry a FIXED height (stable scroll math, no auto-height measurement), and
// the per-row onAppear/onDisappear signals drive the FilmstripModel's
// visible-window tracking. The model converts the window into bridge work:
// visible span ± `prefetchSpan` rows get requested (once — same-id requests
// MERGE in the bridge), the bridge gets `prioritize` for the visible ids,
// and a full-list disappear clears the window (the cancel face — in-flight
// productions finish into bounded windows, the provider-twin semantics).
//
// DATA SOURCE (KD-3, zero collection-state copying): the strip renders
// `LibraryGridModel.rows` — the SAME filtered/keyset cursor as the P2 grid.
// Selection routes through the grid's state machine; the scroll anchor
// follows the selected row (the editor's filmstrip-scroll restoration).
//
// PERF OBSERVATION (BENCH|, non-gate): the 10k-row mount window stats land
// in the plan SUMMARY; real-machine 60fps scroll = P4 T2 checklist ① (E4).
// ─────────────────────────────────────────────────────────────────────────────

/// The filmstrip's windowing model: which rows are on screen, which ids the
/// bridge should hold warm, and where the scroll anchor sits. Pure logic —
/// fully unit-testable without a List (the KD-5 machine-check face).
@MainActor
@Observable
final class FilmstripModel {

    /// The fixed row height (virtualization math constant).
    static let rowHeight: CGFloat = 64

    /// Rows requested beyond the visible window on EACH side.
    static let prefetchSpan = 4

    private let grid: LibraryGridModel
    private let bridge: LibraryThumbnailBridge?

    /// The currently-visible row indices (List onAppear/onDisappear book).
    private var visibleIndices: Set<Int> = []

    /// The ids a bridge request was ISSUED for (the window union; requests
    /// are never re-issued for an id still inside the warm set — the merge
    /// guarantee keeps this bounded by window × constant).
    private(set) var requestedIDs: Set<Int64> = []

    /// Total thumbnail requests issued (the counter assertion face).
    private(set) var requestCount = 0

    /// The scroll anchor (the topmost row the List should settle on) —
    /// follows the selected row (KD-5: 滚动锚随选中行更新).
    private(set) var scrollAnchorID: Int64?

    init(grid: LibraryGridModel, bridge: LibraryThumbnailBridge?) {
        self.grid = grid
        self.bridge = bridge
    }

    /// The warm window for the current visible span: visible ± prefetch,
    /// clamped to the loaded rows.
    var warmWindow: Range<Int> {
        guard let first = visibleIndices.min(),
            let last = visibleIndices.max() else {
            return 0..<0
        }
        let lower = max(0, first - Self.prefetchSpan)
        let upper = min(grid.rows.count, last + Self.prefetchSpan + 1)
        return lower..<upper
    }

    // MARK: - The List signal face

    func rowAppeared(_ index: Int) {
        guard grid.rows.indices.contains(index) else { return }
        visibleIndices.insert(index)
        refreshWindow()
    }

    func rowDisappeared(_ index: Int) {
        visibleIndices.remove(index)
        if visibleIndices.isEmpty {
            // The strip scrolled away / torn down: drop the warm set (the
            // cancel face). In-flight productions complete into the void.
            requestedIDs.removeAll()
            return
        }
        refreshWindow()
    }

    /// The whole-list disappear (the view's `.onDisappear`) — a stricter
    /// cancel than per-row bookkeeping alone.
    func listDisappeared() {
        visibleIndices.removeAll()
        requestedIDs.removeAll()
    }

    /// Selection entry (single click on a row): routes through the grid's
    /// state machine and moves the scroll anchor (a row that is not loaded
    /// neither selects nor anchors).
    func select(_ id: Int64) {
        guard grid.rows.contains(where: { $0.id == id }) else { return }
        grid.selectSingle(id)
        scrollAnchorID = id
    }

    /// Re-anchor after an external selection change (the editor's current
    /// image, P3) without touching the grid selection.
    func anchor(on id: Int64) {
        scrollAnchorID = id
    }

    // MARK: - Window refresh (the request issuer)

    private func refreshWindow() {
        let window = warmWindow
        let rows = grid.rows
        var promoted: [Int64] = []
        for index in window {
            let id = rows[index].id
            if requestedIDs.insert(id).inserted {
                requestCount += 1
                if let bridge {
                    Task { _ = await bridge.thumbnail(for: rows[index]) }
                }
            }
            promoted.append(id)
        }
        if let bridge, !promoted.isEmpty {
            Task { await bridge.prioritize(promoted) }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The view: a vertical List of fixed-height rows. Selection ring = the glass
// selectedRing; the current image carries an accent edge. P3 mounts this in
// the editor's left rail; the P2 grid reuses the same model + bridge.
// ─────────────────────────────────────────────────────────────────────────────

struct FilmstripView: View {

    let grid: LibraryGridModel
    let bridge: LibraryThumbnailBridge?
    /// The editor-entry face (double-click / activate) — P3 wires the open.
    var onOpen: (Int64) -> Void = { _ in }

    @State private var model: FilmstripModel?

    var body: some View {
        Group {
            if let model, !grid.rows.isEmpty {
                filmstrip(model)
            } else {
                emptyState
            }
        }
        .onAppear {
            if model == nil {
                model = FilmstripModel(grid: grid, bridge: bridge)
            }
        }
        .onDisappear {
            model?.listDisappeared()
        }
    }

    private func filmstrip(_ model: FilmstripModel) -> some View {
        List {
            ForEach(grid.rows, id: \.id) { row in
                FilmstripRowView(
                    row: row,
                    isSelected: grid.selectedIDs.contains(row.id),
                    isCurrent: grid.currentImageID == row.id,
                    bridge: bridge
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .frame(height: FilmstripModel.rowHeight)
                .accessibilityIdentifier("filmstrip.row.\(row.id)")
                .onAppear {
                    if let index = grid.rows.firstIndex(where: { $0.id == row.id }) {
                        model.rowAppeared(index)
                    }
                }
                .onDisappear {
                    if let index = grid.rows.firstIndex(where: { $0.id == row.id }) {
                        model.rowDisappeared(index)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    model.select(row.id)
                }
                .onTapGesture(count: 2) {
                    model.select(row.id)
                    onOpen(row.id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(ThemeTokens.cardSurface)
        .accessibilityIdentifier("filmstrip.list")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(String(localized: "filmstrip_empty", defaultValue: "No images in this collection"))
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeTokens.cardSurface)
        .accessibilityIdentifier("filmstrip.empty")
    }
}

/// One strip row: the thumbnail (async through the bridge) + the filename
/// caption, with the selection ring and the current-image accent edge.
private struct FilmstripRowView: View {

    let row: LibraryImageRow
    let isSelected: Bool
    let isCurrent: Bool
    let bridge: LibraryThumbnailBridge?

    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(ThemeTokens.cardBorder)
                }
            }
            .frame(width: FilmstripModel.rowHeight - 12, height: FilmstripModel.rowHeight - 12)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(row.filename ?? row.imagePath)
                .font(.caption2)
                .foregroundStyle(
                    isSelected ? ThemeTokens.textPrimary : ThemeTokens.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isCurrent {
                Circle()
                    .fill(ThemeTokens.accent)
                    .frame(width: 6, height: 6)
                    .padding(.trailing, 6)
                    .accessibilityIdentifier("filmstrip.current.dot")
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? ThemeTokens.cardSurface : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isSelected ? ThemeTokens.selectedRing : Color.clear,
                    lineWidth: 2)
        )
        .overlay(
            // The current-image accent edge (the Alcedo语义: the strip marks
            // which image the EDITOR holds).
            Rectangle()
                .fill(isCurrent ? ThemeTokens.accent : Color.clear)
                .frame(width: 2),
            alignment: .leading
        )
        .task(id: row.id) {
            guard let bridge else { return }
            thumbnail = await bridge.thumbnail(for: row)
        }
    }
}
