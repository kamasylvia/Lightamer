import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// CatalogBrowserView (Plan 16-2 T3; mounted by the T2 org axis) — the
// CROSS-SESSION grid over `CatalogBrowserModel`.
//
// Cell four-piece contract (the 09-3/12-1 mirror): thumbnail (the T5 router
// routes (session_id, rel_path) into the per-session provider pool;
// placeholder gradient until a thumb lands), the edited badge, the flag
// badge, and the metadata overlay (rating stars + the color-label dot —
// the 12-1 layout and the C1 seven-color mapping verbatim).
//
// L010: `catalog.cell.<pathhash>` is the stable row id (FNV-1a over the
// composite identity — never an index).
//
// SCROLL LOADING (execution decision): when a near-end cell appears the
// model appends the next keyset page — no page numbers in v1.
// ─────────────────────────────────────────────────────────────────────────────

internal struct CatalogBrowserView: View {

    internal enum CatalogBrowserIdentifiers {
        static let grid = "catalog.grid"

        /// Stable per-row id (the composite-identity hex — L010).
        static func cell(_ pathHash: String) -> String { "catalog.cell.\(pathHash)" }
    }

    let model: CatalogBrowserModel

    /// Plan 16-2 T5: the cross-session thumbnail router (nil = not wired —
    /// cells stay placeholders; the pool teardown rides the org-mode
    /// switch in ContentView).
    let thumbnailRouter: CatalogThumbnailRouter?

    /// Double-click: open the row's session through the SAME `openSession`
    /// flow and load the clicked image into the editor (D-16-CONTEXT-5⑤ —
    /// the editor is mode-blind). The mode flip is the caller's.
    let onOpenInEditor: (_ sessionRoot: URL, _ relPath: String) -> Void

    // Session-id → root lookup (the cell URL assembly; refreshed on
    // appear from the shared store's registry read).
    @State private var sessionRoots: [String: URL] = [:]

    // Plan 16-3 T3: the organization faces (the classify menus ride the
    // tree/collections model — the SAME instance the sidebar consumes).
    @Environment(CatalogTreeModel.self) private var catalogTree

    // Plan 16-4 T2: the rebuild-in-flight face — while a two-mode rebuild
    // runs the grid clears (空网格 + 进度, RQ-16-14 推荐态; Smart Albums
    // stay visible — only the photographs grid clears).
    @Environment(CatalogPreferencesModel.self) private var catalogPreferences

    /// Scroll-load threshold (cells before the end that trigger the next
    /// keyset page).
    private static let loadAhead = 12

    private static let columns = [GridItem(.adaptive(minimum: 168, maximum: 260), spacing: 10)]

    var body: some View {
        ScrollView {
            if catalogPreferences.isRebuilding {
                // The rebuild face: an EMPTY grid + the X/N-会话 progress
                // (no stale rows read from a library being rebuilt).
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    if let progress = catalogPreferences.rebuildProgress {
                        Text("settings_catalogs_rebuild_progress \(progress.completed) \(progress.total)")
                    } else {
                        Text("settings_catalogs_rebuild_preparing")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .accessibilityIdentifier("catalog.rebuild_progress")
            } else {
                LazyVGrid(columns: Self.columns, spacing: 10) {
                    ForEach(Array(model.rows.enumerated()), id: \.element) { index, row in
                        CatalogBrowserCell(
                            row: row,
                            sessionRoot: sessionRoots[row.sessionID],
                            thumbnailRouter: thumbnailRouter,
                            isSelected: model.selectedIdentities.contains(row.id),
                            onClick: { command, shift in
                                model.handleClick(row.id, commandPressed: command, shiftPressed: shift)
                            },
                            onDoubleClick: {
                                if let root = sessionRoots[row.sessionID] {
                                    onOpenInEditor(root, row.relPath)
                                }
                            }
                        )
                        .accessibilityIdentifier(
                            CatalogBrowserIdentifiers.cell(row.pathHash))
                        .contextMenu {
                            self.batchMenus(for: row.id)
                        }
                        .onAppear {
                            if index >= model.rows.count - Self.loadAhead {
                                Task { await model.loadMore() }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .accessibilityIdentifier(CatalogBrowserIdentifiers.grid)
        // Plan 16-2 T3: the filter bar rides the grid's top inset (the 12-2
        // shape, bound to the catalog model).
        .safeAreaInset(edge: .top, spacing: 0) {
            CatalogFilterBarView(model: model)
        }
        // The empty faces: a fresh (empty) catalog guides the user into the
        // session flow (RQ-16-1③); a filtered empty result says WHY.
        .overlay {
            if !catalogPreferences.isRebuilding, model.rows.isEmpty, model.endReached {
                if model.hasActiveFilter {
                    ContentUnavailableView {
                        Label("filter_empty_results", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("filter_empty_results_body")
                    }
                } else {
                    ContentUnavailableView {
                        Label("catalog_empty_title", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("catalog_empty_hint")
                    }
                }
            }
        }
        .onAppear {
            Task {
                await refreshSessionRoots()
                await model.reload()
                await catalogTree.refresh()
            }
        }
        .onChange(of: model.queryRevision) { _, _ in
            Task { await model.reload() }
        }
        // Plan 16-4 T2: after a rebuild lands the grid reloads from the
        // fresh state (the rebuild flips this revision counter).
        .onChange(of: catalogPreferences.isRebuilding) { wasRebuilding, now in
            if wasRebuilding, !now {
                Task {
                    await refreshSessionRoots()
                    await model.reload()
                }
            }
        }
    }

    /// The registry map refresh (the shared store's registry read; the
    /// sidebar's session-management actions and sweeps change it).
    func refreshSessionRoots() async {
        let rows = (try? await SessionIndexController.sharedCatalogStore.fetchSessions()) ?? []
        sessionRoots = Dictionary(
            rows.map { ($0.sessionID, URL(fileURLWithPath: $0.rootPath, isDirectory: true)) },
            uniquingKeysWith: { first, _ in first })
    }

    /// The right-clicked cell joins the selection when outside it — the
    /// batch actions are batch actions (the 12-1 META-03 shape).
    private func batchTargets(for identity: String) -> [String] {
        model.selectedIdentities.contains(identity)
            ? model.selectedOrderedIdentities
            : [identity]
    }

    /// The batch menu (broken into sub-expressions for the type checker).
    @ViewBuilder
    private func batchMenus(for identity: String) -> some View {
        let targets = batchTargets(for: identity)
        ratingMenu(targets: targets)
        colorMenu(targets: targets)
        Button(String(localized: "browser_menu_flag_pick")) {
            Task { await model.batchSetFlag(1, identities: targets) }
        }
        Button(String(localized: "browser_menu_flag_reject")) {
            Task { await model.batchSetFlag(2, identities: targets) }
        }
        Button(String(localized: "browser_menu_flag_clear")) {
            Task { await model.batchSetFlag(nil, identities: targets) }
        }
        classifyMenu(targets: targets)
        if let anchorCategory = model.activeScope.categoryID {
            Button(String(localized: "catalog_menu_remove_from_category")) {
                Task { await catalogTree.revoke(
                    identities: targets, fromCategoryID: anchorCategory) }
            }
        }
    }

    // Plan 16-3 T3: the classify faces — one click writes the membership
    // into the catalog (multi-membership; across sessions natively — the
    // organization truth does not know about session boundaries).
    @ViewBuilder
    private func classifyMenu(targets: [String]) -> some View {
        Menu(String(localized: "catalog_menu_add_to_category")) {
            ForEach(catalogTree.flatCategories()) { node in
                Button(node.name) {
                    Task { await catalogTree.assign(
                        identities: targets, toCategoryID: node.id) }
                }
            }
        }
        Menu(String(localized: "catalog_menu_add_to_collection")) {
            ForEach(catalogTree.collections) { collection in
                Button(collection.name) {
                    Task { await catalogTree.assign(
                        identities: targets, toCollectionID: collection.id) }
                }
            }
        }
    }

    private func ratingMenu(targets: [String]) -> some View {
        Menu(String(localized: "catalog_batch_rating")) {
            ForEach(1...5, id: \.self) { n in
                Button("\(n)") {
                    Task { await model.batchSetRating(n, identities: targets) }
                }
            }
            Button(String(localized: "catalog_batch_clear")) {
                Task { await model.batchSetRating(nil, identities: targets) }
            }
        }
    }

    private func colorMenu(targets: [String]) -> some View {
        Menu(String(localized: "catalog_batch_color")) {
            ForEach(0...6, id: \.self) { n in
                Button("\(n)") {
                    Task { await model.batchSetColorLabel(n, identities: targets) }
                }
            }
            Button(String(localized: "catalog_batch_clear")) {
                Task { await model.batchSetColorLabel(nil, identities: targets) }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The cell — the 09-3 shape over the composite identity. Thumbnails ride the
// T5 router (placeholder gradient until then / when the session is offline).
// ─────────────────────────────────────────────────────────────────────────────

private struct CatalogBrowserCell: View {

    let row: CatalogBrowserModel.Row
    /// The session root (nil = unknown registry row — no open affordance).
    let sessionRoot: URL?
    let thumbnailRouter: CatalogThumbnailRouter?
    let isSelected: Bool
    let onClick: (_ command: Bool, _ shift: Bool) -> Void
    let onDoubleClick: () -> Void

    /// The resolved thumb (nil = placeholder gradient).
    @State private var thumbnail: CGImage?
    /// The identity this @State resolved for (LazyVGrid recycles cells —
    /// a stale answer must never paint the next row's tile).
    @State private var resolvedFor: String?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.18))
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .transition(.opacity)
                }
                VStack {
                    HStack(spacing: 4) {
                        if row.hasEdits {
                            badge("E", color: .blue)
                        }
                        if row.flag == 1 {
                            badge("P", color: .green)
                        } else if row.flag == 2 {
                            badge("X", color: .red)
                        }
                        Spacer()
                    }
                    Spacer()
                    // The metadata overlay (12-1 T6 face — same layout, same
                    // C1 seven-color mapping).
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { star in
                            Image(systemName: star < (row.rating.map(Int.init) ?? 0)
                                ? "star.fill" : "star")
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    star < (row.rating.map(Int.init) ?? 0)
                                        ? .white.opacity(0.95) : .white.opacity(0.35))
                        }
                        if let colorLabel = row.colorLabel {
                            Circle()
                                .fill(Self.colorLabelColor(colorLabel))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(6)
            }
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            // The offline gray-out (D-16-CONTEXT-7②): an offline session's
            // tiles dim and carry the marker — no thumbnail work was ever
            // enqueued for them.
            .opacity(thumbnailRouter?.isOffline(row.sessionID) == true ? 0.35 : 1.0)
            .overlay(alignment: .topTrailing) {
                if thumbnailRouter?.isOffline(row.sessionID) == true {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(4)
                        .accessibilityIdentifier("catalog.cell.offline")
                }
            }
            Text(row.filename ?? row.relPath)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            onClick(flags.contains(.command), flags.contains(.shift))
        }
        .task(id: row.id) {
            // The ROUTED fetch (visible: true — the visible cell jumps the
            // provider queue). Offline sessions return nil WITHOUT any
            // provider being created (零请求).
            if resolvedFor == row.id, thumbnail != nil { return }
            resolvedFor = row.id
            let image = await thumbnailRouter?.thumbnail(
                sessionID: row.sessionID, relPath: row.relPath, visible: true)
            if resolvedFor == row.id {
                withAnimation(.easeIn(duration: 0.15)) { thumbnail = image }
            }
        }
    }

    /// The C1 seven-color mapping (the 12-1 execution decision verbatim):
    /// 0 red / 1 orange / 2 yellow / 3 green / 4 blue / 5 purple / 6 gray.
    static func colorLabelColor(_ value: Int64) -> Color {
        switch value {
        case 0: .red
        case 1: .orange
        case 2: .yellow
        case 3: .green
        case 4: .blue
        case 5: .purple
        default: .gray
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(color))
    }
}
