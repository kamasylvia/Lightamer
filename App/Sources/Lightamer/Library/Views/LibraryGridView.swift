import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// LibraryGridView (Plan M2-3-2 T1, KD-1) — the thumbnail grid: a LazyVGrid
// over the LibraryGridModel cursor (the P1 collection single-source — ZERO
// collection state copied here) with keyset infinite scroll.
//
// PAGING GLUE (LibraryGridPager): LazyVGrid materializes cells on viewport
// entry, so each cell's onAppear is the scroll signal. A signal inside the
// tail-arming window (the last `tailArmingDistance` loaded rows) issues ONE
// `loadNextPage()`; the keyset cursor is idempotent, so a slightly early
// signal (the plan's window-estimate risk note) can only fetch one extra
// page — never a gap or an overlap. `isExhausted` floors the walk (zero
// further calls), and the model's own `isLoading` guard collapses
// duplicate signals onto the running fetch.
//
// ENTRY (KD-1 / D2): double-click = the editor entry — the host routes the
// id through `WorkspaceModel.openEditor(imageID:)` (the P1 骨架槽位 this
// plan lights). Single click selects, ⌘-click toggles (the model's state
// machine; the filmstrip highlights from the same selection).
//
// THUMBNAILS ride the P1 `LibraryThumbnailBridge` (tier A = the ImageIO
// embedded preview; tier B = the injected render leg). A row the bridge
// cannot resolve (stale link / render leg not wired) renders the honest
// placeholder tile — never a fake image.
// ─────────────────────────────────────────────────────────────────────────────

/// The scroll-signal → pagination glue (the KD-1 testable face: the view's
/// onAppear signals route through here; the counter makes the "infinite
/// scroll issues bounded calls" assertion machine-checkable).
@MainActor
@Observable
final class LibraryGridPager {

    /// How many rows from the loaded tail arm the next fetch (the
    /// LazyVGrid window estimate is approximate — the keyset cursor makes
    /// an early arming harmless).
    var tailArmingDistance: Int

    let grid: LibraryGridModel

    /// The number of `loadNextPage()` invocations ISSUED through the signal
    /// face (the test observability counter; guarded-away signals do not
    /// count — they issued nothing).
    private(set) var loadCallCount = 0

    init(grid: LibraryGridModel, tailArmingDistance: Int = 12) {
        self.grid = grid
        self.tailArmingDistance = tailArmingDistance
    }

    /// The cell-appear signal: a signal at or inside the tail-arming window
    /// issues the next page (awaited — the caller's Task is the determinism
    /// seam, the LibraryGridModel precedent).
    func cellAppeared(at index: Int) async {
        guard !grid.isExhausted, !grid.isLoading else { return }
        guard index >= grid.rows.count - tailArmingDistance else { return }
        loadCallCount += 1
        _ = try? await grid.loadNextPage()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The grid view.
// ─────────────────────────────────────────────────────────────────────────────

struct LibraryGridView: View {

    /// The collection cursor (the ONE source — filter/sort/rows/selection).
    let grid: LibraryGridModel
    /// The dual-tier thumbnail supply (nil = placeholders everywhere — the
    /// test skeleton state).
    let bridge: LibraryThumbnailBridge?
    /// The editor entry (double-click). The host routes this through the
    /// WorkspaceModel (D2 真缝).
    var onOpen: (Int64) -> Void = { _ in }

    // Plan M2-10-07 (KD-3, minimal radius): the AI enhancement context-menu
    // commands. The callbacks carry the RIGHT-CLICKED row id (the host
    // resolves the acted-on set = the clicked row's selection). nil = the
    // commands stay hidden (the test skeleton state).
    var onAIUpscale: ((Int64) -> Void)?
    var onAIDenoise: ((Int64) -> Void)?

    // M6-4-01 (KD-8): the auto-stack confirm dialog (the SwiftUI sheet seam
    // — L057's runModal ban).
    @State private var autoStackPresented = false

    @State private var pager: LibraryGridPager?

    /// The adaptive cell width (the Alcedo thumbnail-grid density intent:
    /// ~4-6 columns on a typical window, growing on wider ones).
    static let cellMinimumSize: CGFloat = 156

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(minimum: Self.cellMinimumSize),
            spacing: 12)]
    }

    var body: some View {
        Group {
            if let pager, !grid.rows.isEmpty {
                gridBody(pager)
            } else if grid.isLoading {
                // The first page in flight — an honest blank, not an empty
                // collection (the empty-state copy is only for a REAL
                // empty walk).
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ThemeTokens.windowBackground)
                    .accessibilityIdentifier("library.grid.loading")
            } else {
                emptyState
            }
        }
        .onAppear {
            if pager == nil {
                pager = LibraryGridPager(grid: grid)
            }
        }
        // M6-4-01 (KD-8): the auto-stack confirm dialog — the sheet seam.
        .sheet(isPresented: $autoStackPresented) {
            LibraryAutoStackDialog(
                model: grid, isPresented: $autoStackPresented)
        }
    }

    private func gridBody(_ pager: LibraryGridPager) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(grid.rows, id: \.id) { row in
                    cell(row, pager: pager)
                }
            }
            .padding(14)
            // The exhausted footer (the honest end of the collection walk).
            if grid.isExhausted {
                Text(String(
                    localized: "library_grid_end",
                    defaultValue: "End of collection — \(grid.rows.count) photos"))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("library.grid.end")
            }
        }
        .background(ThemeTokens.windowBackground)
        .accessibilityIdentifier("library.grid")
    }

    private func cell(_ row: LibraryImageRow, pager: LibraryGridPager) -> some View {
        let stackBadge = grid.stackBadge(for: row.id)
        return LibraryGridCellView(
            row: row,
            isSelected: grid.selectedIDs.contains(row.id),
            isCurrent: grid.currentImageID == row.id,
            bridge: bridge,
            stackBadge: stackBadge,
            onToggleCollapse: stackBadge == nil ? nil : { stackID in
                Task { await grid.toggleCollapse(stackID: stackID) }
            })
            .accessibilityIdentifier("library.grid.cell.\(row.id)")
            .onAppear {
                if let index = grid.rows.firstIndex(where: { $0.id == row.id }) {
                    Task { await pager.cellAppeared(at: index) }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.command) {
                    grid.toggleSelection(row.id)
                } else {
                    grid.selectSingle(row.id)
                }
            }
            .onTapGesture(count: 2) {
                grid.selectSingle(row.id)
                onOpen(row.id)
            }
            // Plan M2-10-07 (KD-3): the two AI enhancement entries — the
            // right-click acts on the clicked row (selected first, so the
            // host's selection resolution sees it). M6-4-01 (KD-8): the
            // stack face joins the menu (成栈 needs a ≥2 selection; the
            // per-row stack routes need a membership).
            .contextMenu {
                if let onAIUpscale {
                    Button {
                        grid.selectSingle(row.id)
                        onAIUpscale(row.id)
                    } label: {
                        Label(String(
                            localized: "library_grid_ai_upscale",
                            defaultValue: "AI Super Resolution…"),
                            systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityIdentifier("library.grid.cell.aiUpscale")
                }
                if let onAIDenoise {
                    Button {
                        grid.selectSingle(row.id)
                        onAIDenoise(row.id)
                    } label: {
                        Label(String(
                            localized: "library_grid_ai_denoise",
                            defaultValue: "AI Denoise…"),
                            systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("library.grid.cell.aiDenoise")
                }
                Divider()
                if grid.selectedIDs.count >= 2 {
                    Button {
                        Task { await grid.groupSelection() }
                    } label: {
                        Label(String(
                            localized: "library_stack_group",
                            defaultValue: "Group into Stack"),
                            systemImage: "square.stack.3d.up")
                    }
                    .accessibilityIdentifier("library.grid.cell.group")
                }
                if let badge = stackBadge {
                    Button {
                        Task { await grid.ungroup(stackID: badge.stackID) }
                    } label: {
                        Label(String(
                            localized: "library_stack_ungroup",
                            defaultValue: "Ungroup"),
                            systemImage: "square.stack.3d.up.slash")
                    }
                    .accessibilityIdentifier("library.grid.cell.ungroup")
                    if badge.position != 0 {
                        Button {
                            Task { await grid.setCover(imageID: row.id) }
                        } label: {
                            Label(String(
                                localized: "library_stack_set_cover",
                                defaultValue: "Make Cover"),
                                systemImage: "star.square.on.square")
                        }
                        .accessibilityIdentifier("library.grid.cell.setCover")
                    }
                    Button {
                        Task { await grid.removeFromStack(imageID: row.id) }
                    } label: {
                        Label(String(
                            localized: "library_stack_remove_from_stack",
                            defaultValue: "Remove from Stack"),
                            systemImage: "minus.square.on.square")
                    }
                    .accessibilityIdentifier("library.grid.cell.removeFromStack")
                }
                Button {
                    autoStackPresented = true
                } label: {
                    Label(String(
                        localized: "library_stack_auto_menu",
                        defaultValue: "Auto-Stack…"),
                        systemImage: "timer")
                }
                .accessibilityIdentifier("library.grid.cell.autoStack")
            }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(String(
                localized: "library_grid_empty",
                defaultValue: "No photos in this collection"))
                .font(.callout)
                .foregroundStyle(ThemeTokens.textSecondary)
            Text(String(
                localized: "library_grid_empty_hint",
                defaultValue: "Import a folder or clear the search filter."))
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeTokens.windowBackground)
        .accessibilityIdentifier("library.grid.empty")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// One grid cell: the bridged thumbnail + the star-rating badge + the
// selection glass ring (KD-1's three-piece cell).
// ─────────────────────────────────────────────────────────────────────────────

private struct LibraryGridCellView: View {

    let row: LibraryImageRow
    let isSelected: Bool
    let isCurrent: Bool
    let bridge: LibraryThumbnailBridge?
    /// M6-4-01 (KD-8): the stack badge payload (nil = an unstacked row —
    /// the badge overlay stays hidden).
    var stackBadge: StackMembership?
    /// The badge chevron's tap route (nil = badge-only, no control).
    var onToggleCollapse: ((Int64) -> Void)?

    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(ThemeTokens.cardSurface)
                        .overlay(
                            Rectangle()
                                .fill(ThemeTokens.cardBorder)
                                .frame(height: 1),
                            alignment: .top)
                }
            }
            .frame(
                minWidth: LibraryGridView.cellMinimumSize,
                minHeight: LibraryGridView.cellMinimumSize)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let rating = row.rating {
                Text(verbatim: ratingBadge(rating))
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .padding(6)
                    .accessibilityIdentifier("library.grid.cell.rating.\(row.id)")
            }
        }
        .overlay(alignment: .topTrailing) {
            // The stack badge (KD-8): member count + the collapse chevron —
            // the Lightroom/LightCraft convention (A2: Alcedo has no stacks).
            if let stackBadge {
                HStack(spacing: 3) {
                    Text(verbatim: "\(stackBadge.size)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                    if let onToggleCollapse {
                        Button {
                            onToggleCollapse(stackBadge.stackID)
                        } label: {
                            Image(systemName: stackBadge.collapsed
                                ? "chevron.down" : "chevron.up")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "library.grid.cell.chevron.\(row.id)")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(ThemeTokens.textPrimary)
                .padding(6)
                // The S4 format-key spelling (%lld suffix) — the count is
                // the badge's accessibility announcement.
                .accessibilityLabel(Text(String(
                    localized: "library_stack_members_hint \(stackBadge.size)")))
                .accessibilityIdentifier("library.grid.cell.stackBadge.\(row.id)")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected ? ThemeTokens.selectedRing : Color.clear,
                    lineWidth: 2)
        )
        .overlay(
            // The current-image accent edge (the editor holds THIS one).
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isCurrent ? ThemeTokens.accent : Color.clear,
                    lineWidth: 1)
                .padding(1)
        )
        .task(id: row.id) {
            guard let bridge else { return }
            thumbnail = await bridge.thumbnail(for: row)
        }
    }

    /// `★★★` for 1…5; the 0-star tier reads as its own badge.
    private func ratingBadge(_ rating: Int64) -> String {
        rating > 0
            ? String(repeating: "★", count: Int(min(rating, 5)))
            : String(localized: "library_grid_rating_none", defaultValue: "–")
    }
}
