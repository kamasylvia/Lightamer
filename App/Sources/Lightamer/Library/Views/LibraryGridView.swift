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

    // LUMEN-A T7: the culling hint badges (empty map = the default-neutral
    // face — every cell renders byte-identically to the pre-plan grid).
    var cullingBadges: [Int64: LibraryCullingBadge] = [:]
    /// The 转为堆栈 one-key route for a burst group (nil = the menu entry
    /// stays hidden — the test skeleton state).
    var onCreateBurstStack: (([Int64]) -> Void)?
    // LUMEN-B T4 (X7/D-LU-1): the cull entry (the context-menu 快速选片 seam
    // — the clicked row anchors the cull table; nil = the entry stays hidden,
    // the test skeleton state). Declared AFTER cullingBadges to keep the
    // memberwise-argument order the host's call site already uses.
    var onCull: ((Int64?) -> Void)?

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
                // AR-01 T4 (audit M3 / m6): the enumerated form carries the
                // row's position to the pager signal — the cell onAppear no
                // longer runs the O(n) firstIndex reverse-lookup (identity
                // stays row.id; pager.cellAppeared(at:) stays index-keyed —
                // paging by index is design-intended).
                ForEach(Array(grid.rows.enumerated()), id: \.element.id) { index, row in
                    cell(row, pager: pager, index: index)
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

    private func cell(
        _ row: LibraryImageRow, pager: LibraryGridPager, index: Int
    ) -> some View {
        let stackBadge = grid.stackBadge(for: row.id)
        let cullingBadge = cullingBadges[row.id]
        return LibraryGridCellView(
            row: row,
            isSelected: grid.selectedIDs.contains(row.id),
            isCurrent: grid.currentImageID == row.id,
            bridge: bridge,
            stackBadge: stackBadge,
            onToggleCollapse: stackBadge == nil ? nil : { stackID in
                Task { await grid.toggleCollapse(stackID: stackID) }
            },
            cullingBadge: cullingBadge,
            onCreateBurstStack: onCreateBurstStack)
            .accessibilityIdentifier("library.grid.cell.\(row.id)")
            .onAppear {
                Task { await pager.cellAppeared(at: index) }
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
                // M9-4 T4 (X6): the Show in Finder door — the FinderReveal
                // seam (acceptance-2ND M-1: existence-checked, non-modal;
                // the AX id is the production constant the tests pin).
                Button {
                    FinderReveal.revealIfPresent(row.imagePath)
                } label: {
                    Label(
                        String(localized: "action_show_in_finder"),
                        systemImage: "folder")
                }
                .accessibilityIdentifier(FinderReveal.gridActionID)
                // LUMEN-B T4: the cull entry (the clicked row anchors the
                // cull table's current position).
                if let onCull {
                    Button {
                        grid.selectSingle(row.id)
                        onCull(row.id)
                    } label: {
                        Label(String(
                            localized: "library_grid_cull",
                            defaultValue: "快速选片"),
                            systemImage: "checkmark.circle.stack")
                    }
                    .accessibilityIdentifier("library.grid.cell.cull")
                }
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
                // LUMEN-A T7 (review m-6): the 转为堆栈 one-key — the burst
                // annotation's explicit materialization route (the group's
                // members stack through LibraryStore.createStack; the
                // annotation itself stays query-time).
                if let onCreateBurstStack, let cullingBadge,
                   cullingBadge.hasBurst, !cullingBadge.burstMembers.isEmpty {
                    Button {
                        onCreateBurstStack(cullingBadge.burstMembers)
                    } label: {
                        Label(String(
                            localized: "library_hint_make_stack",
                            defaultValue: "转为堆栈"),
                            systemImage: "square.stack.3d.up.badge.plus")
                    }
                    .accessibilityIdentifier("library.grid.cell.makeBurstStack")
                    Divider()
                }
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

/// The culling badge payload (LUMEN-A T7): one analysed row's hint face.
/// Zero-annotation rows never appear in the map — the default-neutral red
/// line (the grid renders byte-identically when nothing is analysed).
struct LibraryCullingBadge: Equatable, Sendable {
    /// Lumen annotate_hints: sharpness < 22 or far below the burst best.
    var blurry: Bool
    /// The T4 wider-open-eye verdict (max(right,left) < threshold).
    var eyesClosed: Bool
    /// 1-based position inside the burst (0 = not in one).
    var burstIndex: Int
    var burstSize: Int
    /// The frame to keep.
    var best: Bool
    /// The FULL group's member ids (the 转为堆栈 one-key payload).
    var burstMembers: [Int64]

    var hasBurst: Bool { burstIndex > 0 && burstSize > 1 }
}

/// The annotation → badge mapper (the plan's 表驱动 model; the tests pin it).
enum CullingBadgeMapper {
    static func map(
        rows: [BurstRow], annotations: [Int64: BurstAnnotation]
    ) -> [Int64: LibraryCullingBadge] {
        var out: [Int64: LibraryCullingBadge] = [:]
        for row in rows {
            guard let annotation = annotations[row.imageID] else { continue }
            let eyesClosed = row.eyesClosed == true
            let inBurst = annotation.burstIndex > 0 && annotation.burstSize > 1
            guard annotation.blurry || eyesClosed || inBurst || annotation.best
            else { continue }
            out[row.imageID] = LibraryCullingBadge(
                blurry: annotation.blurry,
                eyesClosed: eyesClosed,
                burstIndex: annotation.burstIndex,
                burstSize: annotation.burstSize,
                best: annotation.best,
                burstMembers: inBurst
                    ? badgeMembers(rows, annotations, annotation) : [])
        }
        return out
    }

    /// The full member list of the annotation's group (from the annotations
    /// table's burst number).
    private static func badgeMembers(
        _ rows: [BurstRow], _ annotations: [Int64: BurstAnnotation],
        _ annotation: BurstAnnotation
    ) -> [Int64] {
        rows.compactMap { row -> Int64? in
            guard let a = annotations[row.imageID],
                  a.burst == annotation.burst else { return nil }
            return row.imageID
        }
    }
}

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
    /// LUMEN-A T7: the culling hint badge (nil = zero-annotation — the
    /// overlay stays hidden and the cell renders byte-identically).
    var cullingBadge: LibraryCullingBadge?
    /// The 转为堆栈 one-key route (nil = the menu entry stays hidden).
    var onCreateBurstStack: (([Int64]) -> Void)?

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
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(ThemeTokens.cardBorder)
                                .frame(height: 1)
                        }
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
        .overlay(alignment: .topLeading) {
            // LUMEN-A T7: the culling hint badges (可能模糊 / 可能闭眼 /
            // burst n/m + best). Zero-annotation rows never reach here.
            if let cullingBadge {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        if cullingBadge.blurry {
                            Text(String(
                                localized: "library_hint_blurry",
                                defaultValue: "可能模糊"))
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        if cullingBadge.eyesClosed {
                            Text(String(
                                localized: "library_hint_eyes_closed",
                                defaultValue: "可能闭眼"))
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    if cullingBadge.hasBurst {
                        HStack(spacing: 3) {
                            Text(String(
                                format: String(
                                    localized: "library_hint_burst_index %lld %lld"),
                                cullingBadge.burstIndex, cullingBadge.burstSize))
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                            if cullingBadge.best {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .accessibilityIdentifier(
                                        "library.grid.cell.burstBest.\(row.id)")
                            }
                        }
                    }
                }
                .foregroundStyle(ThemeTokens.textPrimary)
                .padding(6)
                .accessibilityIdentifier("library.grid.cell.culling.\(row.id)")
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
                    format: String(localized: "library_stack_members_hint %lld"),
                    stackBadge.size)))
                .accessibilityIdentifier("library.grid.cell.stackBadge.\(row.id)")
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected ? ThemeTokens.selectedRing : Color.clear,
                    lineWidth: 2)
        }
        .overlay {
            // The current-image accent edge (the editor holds THIS one).
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isCurrent ? ThemeTokens.accent : Color.clear,
                    lineWidth: 1)
                .padding(1)
        }
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
