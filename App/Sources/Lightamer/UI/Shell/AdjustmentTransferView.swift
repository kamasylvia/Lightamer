import LightamerCore
import SwiftUI
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// AdjustmentTransferView (Plan M2-8-2 T3, KD-3; D-M2-8-CONTEXT-7) — the Copy
// Adjustments three-pane modal sheet (the Alcedo AdjustmentTransferDialog
// semantics, Node→Item→Version order):
//
//   • SOURCE SEGMENT: 「当前图」 (the active chain) / 「外部 .lra 文件…」
//     (NSOpenPanel → the model's decode) + the second-level version rows;
//   • NODE pane: one row per source Grade (name + chain count);
//   • ITEM pane: the selected node's chain — checkable transferable rows
//     (default ALL), non-transferable rows GREYED with the exclusion note
//     (the KD-3 exclusion face is visible, never silent);
//   • VERSION pane: the materialized summary + the Paste/Cancel tail.
//
// Paste lands through `VersionCoordinator.pasteChain` (the KD-4
// OVERWRITE-paste epoch reuse — zero new projection semantics). The
// exclusion predicate is the model's ONE function — this view never
// re-derives it.
// ─────────────────────────────────────────────────────────────────────────────

struct AdjustmentTransferView: View {

    @Environment(VersionCoordinator.self) private var versions
    @Environment(EditorState.self) private var editorState
    @Environment(\.dismiss) private var dismiss

    @State private var model = AdjustmentTransferModel()

    /// The external `.lra` open panel (lazy — only the external entry).
    @State private var openPanelShown = false

    // Stable markers (the registration/test contract — the panels' seam).
    static let sheetMarker = "editor.transfer.sheet"
    static let sourceCurrentMarker = "editor.transfer.source.current"
    static let sourceExternalMarker = "editor.transfer.source.external"
    static let pasteButtonMarker = "editor.transfer.paste"
    static func nodeRowMarker(id: UUID) -> String {
        "editor.transfer.node.\(id.uuidString)"
    }
    static func itemRowMarker(id: UUID) -> String {
        "editor.transfer.item.\(id.uuidString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            sourceSegment
            Divider()
            HStack(spacing: 0) {
                nodePane
                Divider()
                itemPane
                Divider()
                versionPane
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 620, height: 420)
        .accessibilityIdentifier(Self.sheetMarker)
        .onAppear { model.loadCurrentImage(editorState: editorState) }
        .fileImporter(
            isPresented: $openPanelShown,
            allowedContentTypes: [UTType(filenameExtension: "lra") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.loadExternalFile(at: url)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(String(
                localized: "transfer_title",
                defaultValue: "Copy Adjustments"))
                .font(.headline)
            Spacer()
        }
        .padding(10)
    }

    // MARK: - The source segment

    private var sourceSegment: some View {
        HStack(spacing: 10) {
            Picker(String(
                localized: "transfer_source_label",
                defaultValue: "Source"), selection: sourceBinding)
            {
                Text(String(
                    localized: "transfer_source_current",
                    defaultValue: "Current image"))
                    .tag(Self.sourceCurrentTag)
                Text(String(
                    localized: "transfer_source_external",
                    defaultValue: "External .lra file…"))
                    .tag(Self.sourceExternalTag)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            if case .externalFile(let url) = model.source {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// The segmented picker's tag space (the external tag routes to the
    /// file importer — a real picked URL replaces the sentinel).
    private enum SourceTag: Hashable {
        case current
        case external
        case file(URL)
    }
    private static let sourceCurrentTag = SourceTag.current
    private static let sourceExternalTag = SourceTag.external

    private var sourceBinding: Binding<SourceTag> {
        Binding(
            get: {
                switch model.source {
                case .currentImage: .current
                case .externalFile(let url): .file(url)
                }
            },
            set: { tag in
                switch tag {
                case .current:
                    model.loadCurrentImage(editorState: editorState)
                case .external:
                    openPanelShown = true
                case .file(let url):
                    // Re-picking the same file re-loads; nothing to do.
                    _ = url
                }
            })
    }

    // MARK: - The Node pane

    private var nodePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle(String(
                localized: "transfer_node_title",
                defaultValue: "Grades"))
            if let error = model.loadError {
                Text(error.localizedCopy)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            } else if model.nodes.isEmpty {
                Text(String(
                    localized: "transfer_node_empty",
                    defaultValue: "No color grades in this source."))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(8)
            } else {
                List(model.nodes, selection: $model.selectedNodeID) { node in
                    nodeRow(node)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 190)
    }

    private func nodeRow(_ node: TransferNode) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(String(
                    localized: "transfer_node_count",
                    defaultValue:
                        "\(node.transferableCount) of \(node.chainCount) adjustable"))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier(Self.nodeRowMarker(id: node.id))
    }

    // MARK: - The Item pane

    private var itemPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle(String(
                localized: "transfer_item_title",
                defaultValue: "Adjustments"))
            let rows = model.selectedNodeItems
            if rows.isEmpty {
                Text(String(
                    localized: "transfer_item_empty",
                    defaultValue: "Select a grade."))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(8)
            } else {
                List(rows) { item in
                    itemRow(item)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func itemRow(_ item: TransferItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.checked ? "checkmark.square" : "square")
                .font(.caption)
                .foregroundStyle(item.transferable ? ThemeTokens.accent : ThemeTokens.textSecondary)
                .onTapGesture {
                    guard item.transferable, let nodeID = model.selectedNodeID else { return }
                    model.setChecked(
                        instanceID: item.id, checked: !item.checked, in: nodeID)
                }
            Text(item.instance.multiName.isEmpty
                ? item.instance.opName : item.instance.multiName)
                .font(.caption)
                .lineLimit(1)
                .strikethrough(!item.transferable)
            Spacer(minLength: 2)
            if !item.transferable {
                // The greyed exclusion note (visible, not swallowed).
                Text(String(
                    localized: "transfer_item_excluded",
                    defaultValue: "Not transferable"))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .opacity(item.transferable ? 1 : 0.5)
        .accessibilityIdentifier(Self.itemRowMarker(id: item.id))
    }

    // MARK: - The Version pane (summary + tail)

    private var versionPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneTitle(String(
                localized: "transfer_version_title",
                defaultValue: "Paste as new version"))
            Text(String(
                localized: "transfer_version_note",
                defaultValue:
                    "The selection lands as a NEW version on this image — the current edits stay in their own version."))
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.leading)
            Spacer()
            Text(model.summaryCopy)
                .font(.caption)
            HStack {
                Spacer()
                Button(String(
                    localized: "transfer_cancel", defaultValue: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(
                    localized: "transfer_paste", defaultValue: "Paste")) {
                    guard let payload = model.pastePayload() else { return }
                    versions.pasteChain(
                        records: payload.records,
                        layerSnapshot: payload.snapshot,
                        drtRecord: payload.drtRecord,
                        name: String(
                            localized: "transfer_pasted_version_name",
                            defaultValue: "Pasted adjustments"))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.pastePayload() == nil)
                .accessibilityIdentifier(Self.pasteButtonMarker)
            }
        }
        .padding(10)
        .frame(width: 190)
    }

    private func paneTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(ThemeTokens.textSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.top, 8)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// AdjustmentTransferSheetContent (M2-8-3 acceptance FINDING-A fix) — the Copy
// Adjustments sheet CONTENT face. The dialog's two Observable dependencies
// (`VersionCoordinator` / `EditorState`) are re-injected HERE, inside the
// presented content: the app-root sheet closure sits OUTSIDE the root's
// `.environment(...)` writes on the modifier chain, so the sheet's
// environment snapshot carried neither object and the first content update
// trapped ("No Observable object of type VersionCoordinator found",
// EXC_BREAKPOINT — deterministic on open). The explicit re-injection follows
// the repo's own convention for out-of-tree presentations (the preset-manager
// Window re-injects at the scene; LibraryWelcomeView / ImportModeDialog take
// init parameters). `SheetEnvironmentInjectionTests` mounts THIS face through
// a real `.sheet` presentation — the layer the M2-8-2 model tests skipped
// (they exercised the transfer outside any sheet, so the shipped crash never
// surfaced).
// ─────────────────────────────────────────────────────────────────────────────

struct AdjustmentTransferSheetContent: View {

    let versions: VersionCoordinator
    let editorState: EditorState

    var body: some View {
        AdjustmentTransferView()
            .environment(versions)
            .environment(editorState)
    }
}
