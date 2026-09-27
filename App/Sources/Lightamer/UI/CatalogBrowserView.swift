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

    /// Session-id → root lookup (the cell URL assembly; refreshed on
    /// appear from the shared store's registry read).
    @State private var sessionRoots: [String: URL] = [:]

    /// Scroll-load threshold (cells before the end that trigger the next
    /// keyset page).
    private static let loadAhead = 12

    private static let columns = [GridItem(.adaptive(minimum: 168, maximum: 260), spacing: 10)]

    var body: some View {
        ScrollView {
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
                    .onAppear {
                        if index >= model.rows.count - Self.loadAhead {
                            Task { await model.loadMore() }
                        }
                    }
                }
            }
            .padding(12)
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
            if model.rows.isEmpty, model.endReached {
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
            }
        }
        .onChange(of: model.queryRevision) { _, _ in
            Task { await model.reload() }
        }
    }

    /// The session-id → root map (the shared store's registry read; the
    /// sidebar's session-management actions and sweeps change it).
    func refreshSessionRoots() async {
        let rows = (try? await SessionIndexController.sharedCatalogStore.fetchSessions()) ?? []
        sessionRoots = Dictionary(
            rows.map { ($0.sessionID, URL(fileURLWithPath: $0.rootPath, isDirectory: true)) },
            uniquingKeysWith: { first, _ in first })
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
