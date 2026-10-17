import LightamerCore
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
    @Environment(InspectorState.self) private var inspectorState

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
                // M3-3-03 T4: the coordinator + inspector feed the read-only
                // Film card (the tap opens the Film page).
                EditorNodesPanelView(
                    editorState: editorState, editingState: editingState,
                    pipeCoordinator: pipeCoordinator,
                    inspectorState: inspectorState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.leading, 8)
    }

    /// The LIVE history stack (D3 活体壳): undo/redo header + one row per
    /// real edit transaction (operation name + wall time), newest first.
    /// M2-8-2 T2 (KD-2): rows are CLICKABLE (`jumpToHistory` — HIST-02's
    /// jump-to-any-point face), the row at `history.position` highlights
    /// (a pure derivation — no second state source), and each row carries
    /// a scope-kind icon (the closed `HistoryRowKind` enum — new scope
    /// markers are forced to answer at the ONE mapping site).
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

            let rows = Self.historyRows(items: editorState.history.items)
            let selectedID = editorState.history.position >= 0
                ? editorState.history.items[editorState.history.position].id
                : nil
            List(rows) { row in
                historyRow(row, selected: row.item.id == selectedID)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    /// One history row: label + time + the scope-kind icon, tap = jump.
    /// M7-4-01 (MCP2-09): an item note rides a single-line caption
    /// subtitle and a non-nil author renders the attribution badge (nil =
    /// the implicit user, no badge).
    private func historyRow(
        _ row: HistoryRowData, selected: Bool
    ) -> some View {
        let kind = HistoryRowKind.kind(of: row.item.layerScope)
        return HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.item.label)
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .lineLimit(1)
                Text(row.item.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                if let note = row.item.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            if let author = row.item.author, !author.isEmpty {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(ThemeTokens.textSecondary.opacity(0.14)))
                    .accessibilityLabel(Text(
                        String(localized: "editor_history_author_badge",
                               defaultValue: "Author \(author)")))
            }
            // The scope kind icon (global rows carry none — KD-2).
            if kind != .global {
                Image(systemName: kind.symbol)
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .accessibilityLabel(Text(kind.accessibilityLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(selected ? ThemeTokens.accent.opacity(0.14) : .clear)
        .onTapGesture {
            // The display order is reversed; the jump takes the ORIGINAL
            // index (the stack clamps — −1..count−1).
            Task { await pipeCoordinator.jumpToHistory(row.originalIndex) }
        }
        .accessibilityIdentifier("editor.rail.history.item.\(row.item.id)")
        .accessibilityLabel(Text(row.item.label))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - KD-2: the history-row data + scope-kind faces

    struct HistoryRowData: Identifiable {
        let item: HistoryStack.HistoryItem
        let originalIndex: Int
        var id: UUID { item.id }
    }

    /// The display rows: NEWEST FIRST (the panel convention), each carrying
    /// its ORIGINAL stack index (the jump target — the index conversion
    /// lives here, the view layer, per KD-2).
    static func historyRows(items: [HistoryStack.HistoryItem]) -> [HistoryRowData] {
        items.enumerated().reversed().map {
            HistoryRowData(item: $1, originalIndex: $0)
        }
    }

    /// The CLOSED scope-kind enum (KD-2, checker m2): `layerScope` is a
    /// `String?` — switching it directly would force a `default` arm with
    /// zero compile-time enforcement. The kind mapping is the ONE site a
    /// new scope marker must answer; the render switch below is exhaustive
    /// over the enum (the compiler forces the icon + AX faces).
    enum HistoryRowKind: Equatable {
        /// `layerScope == nil` — an image-global param edit (no icon).
        case global
        /// `EditorStructureScope.marker` — a layer-structure commit.
        case structure
        /// `HistoryStack.pasteEpochScope` — an overwrite-paste epoch.
        case paste
        /// `HistoryStack.drtDocumentScope` — a document-level DRT edit.
        case drt

        static func kind(of layerScope: String?) -> HistoryRowKind {
            switch layerScope {
            case nil: .global
            case EditorStructureScope.marker: .structure
            case HistoryStack.pasteEpochScope: .paste
            case HistoryStack.drtDocumentScope: .drt
            // A layer UUID string (the 06-05 layer-chain scope) is not a
            // member of the marker family — no icon, same as global.
            default: .global
            }
        }

        /// The SF Symbol (KD-2's icon table; `.global` renders nothing).
        var symbol: String {
            switch self {
            case .global: ""
            case .structure: "square.on.square"
            case .paste: "doc.on.doc"
            case .drt: "circle.lefthalf.filled"
            }
        }

        /// The AX label (the four `history_row_kind_*` keys).
        var accessibilityLabel: String {
            switch self {
            case .global:
                String(
                    localized: "history_row_kind_global",
                    defaultValue: "Global adjustment")
            case .structure:
                String(
                    localized: "history_row_kind_structure",
                    defaultValue: "Layer structure change")
            case .paste:
                String(
                    localized: "history_row_kind_paste",
                    defaultValue: "Pasted adjustments")
            case .drt:
                String(
                    localized: "history_row_kind_drt",
                    defaultValue: "Display transform edit")
            }
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
