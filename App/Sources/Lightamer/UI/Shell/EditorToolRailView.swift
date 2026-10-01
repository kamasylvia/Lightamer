import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// EditorToolRailView (Plan M2-3-3 T1, KD-1) — the editor's LEFT tool rail:
// the Alcedo `EditorWorkspaceRail` icon column (History / Versions / Nodes,
// 0.3.0 form: icon + text label) whose expanded panel PUSHES the central
// viewport (the shared collapse semantics — the filmstrip column keeps its
// width; only the viewport yields).
//
// 活体壳 (D3 A): History mounts the LIVE M1 history stack (one row per real
// edit transaction: operation name + time, undo/redo header buttons — the
// Alcedo `EditorHistoryTransactionsPanel` semantics over `EditorState
// .history` + `PipeCoordinator.undo/redo`); Versions is the LIVE versions
// panel since M2-8-2 (the placeholder retired); Nodes is the live M2-4-3
// node canvas (its own placeholder retired the same way).
// ─────────────────────────────────────────────────────────────────────────────

/// One rail section (the Alcedo rail button triplet).
enum EditorRailSection: String, CaseIterable, Identifiable {
    case history
    case versions
    case nodes

    var id: String { rawValue }

    /// The SF Symbol (the Alcedo rail icons' semantic twins).
    var symbol: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .versions: "square.stack.3d.up"
        case .nodes: "point.3.filled.connected.trianglepath.dotted"
        }
    }

    /// The localized button label.
    var label: String {
        switch self {
        case .history:
            String(localized: "editor_rail_history", defaultValue: "History")
        case .versions:
            String(localized: "editor_rail_versions", defaultValue: "Versions")
        case .nodes:
            String(localized: "editor_rail_nodes", defaultValue: "Nodes")
        }
    }

    /// The stable AX marker (`editor.rail.<name>` — the T1 contract).
    var marker: String { "editor.rail.\(rawValue)" }
}

struct EditorToolRailView: View {

    /// The shared collapse animation (the P1 phase-swap timing — ONE
    /// constant so the rail expansion and the shell transitions agree).
    static let collapseAnimation: Animation = .easeInOut(duration: 0.2)

    /// The collapsed rail width (the Alcedo narrow icon column).
    static let collapsedWidth: CGFloat = 56
    /// The expanded rail width (icon column + the panel body).
    static let expandedWidth: CGFloat = 248

    /// The section the rail's panel is expanded for (nil = collapsed).
    /// View-local (the rail owns its expansion; the shell only reserves
    /// the column).
    @State private var expanded: EditorRailSection?

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(LayerEditingState.self) private var editingState

    var body: some View {
        HStack(spacing: 0) {
            buttons
            if let expanded {
                panel(expanded)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .frame(width: expanded == nil ? Self.collapsedWidth : Self.expandedWidth)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background(ThemeTokens.cardSurface)
        .overlay(
            Rectangle()
                .fill(ThemeTokens.cardBorder)
                .frame(width: 1),
            alignment: .trailing
        )
        .animation(Self.collapseAnimation, value: expanded)
        .accessibilityIdentifier("editor.toolrail")
    }

    // MARK: - The icon column (Alcedo 0.3.0: icon above the text label)

    private var buttons: some View {
        VStack(spacing: 10) {
            ForEach(EditorRailSection.allCases) { section in
                Button {
                    expanded = expanded == section ? nil : section
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 15))
                        Text(section.label)
                            .font(.caption2)
                    }
                    .foregroundStyle(
                        expanded == section
                            ? ThemeTokens.accent
                            : ThemeTokens.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(section.marker)
                .accessibilityLabel(Text(section.label))
                .accessibilityAddTraits(expanded == section ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    // MARK: - The expanded panel (the push target)

    @ViewBuilder
    private func panel(_ section: EditorRailSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch section {
            case .history: historyPanel
            case .versions:
                // Plan M2-8-2 T1 (KD-1): the LIVE versions panel replaces
                // the M2-8 placeholder (the "Versions arrive in M2-8"
                // marker retires; the new panel marker =
                // `editor.versions.panel` — the M2-4-3 nodes precedent).
                VersionsPanelView()
            case .nodes:
                // Plan M2-4-3 T1: the LIVE node panel replaces the M2-4
                // placeholder (the "Nodes arrive in M2-4" marker retires;
                // the new panel marker = `editor.nodes.panel`).
                EditorNodesPanelView(
                    editorState: editorState, editingState: editingState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.leading, 8)
    }

    /// The LIVE history stack (D3 活体壳): undo/redo header + one row per
    /// real edit transaction (operation name + wall time), newest first.
    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    Task { await pipeCoordinator.undo() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .disabled(editorState.history.items.isEmpty)
                .accessibilityIdentifier("editor.rail.history.undo")

                Button {
                    Task { await pipeCoordinator.redo() }
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.borderless)
                .disabled(
                    editorState.history.position >= editorState.history.items.count - 1)
                .accessibilityIdentifier("editor.rail.history.redo")

                Spacer()
            }
            .padding(.vertical, 6)

            Divider()

            List(Array(editorState.history.items.reversed())) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.textPrimary)
                        .lineLimit(1)
                    Text(item.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityIdentifier("editor.rail.history.item.\(item.id)")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// The honest empty-state panel body (the "<Feature> arrives in M2-x"
/// family) with a stable marker.
struct EditorRailPlaceholder: View {
    let copy: String
    let marker: String

    var body: some View {
        VStack(spacing: 6) {
            Text(copy)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier(marker)
    }
}
