import Foundation
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ImportModeDialog (Plan M2-2-2 T4, KD-4 / OQ-4) — the three-transport import
// dialog: a STATELESS binding shell (segmented Move/Copy/Link + the remember
// toggle + a folder summary). All state lives in Core-testable faces:
// the initial choice arrives pre-resolved from ImportDefaults (the caller
// seeds `libraryImportChoice` OUTSIDE any view body — the M2-1 D-EXEC-1
// no-static-defaults-in-body discipline), and the confirm lands as a plain
// ImportModeChoice value the caller persists through ImportDefaults.
// zh localization landed with M2-3-4 T1 (the P4 backfill batch): the static
// verbatim copy moved onto String(localized:) keys; dynamic data (folder
// names, per-mode labels/hints resolve through the catalog) stays verbatim.
// ─────────────────────────────────────────────────────────────────────────────

/// The sheet item: one pending import-folder request.
struct ImportFlowRequest: Identifiable, Equatable {
    let id = UUID()
    let folder: URL
}

/// The import type selector's state face (M4-1-02 T5, KD-4 — the M2-1
/// D-EXEC-1 discipline: all state lives in a testable model, the view only
/// renders it). The mask persists on every toggle (记忆 = 选择即写
/// `library.import.categories`); the summary lands once the folder scan
/// completes; the import gate = 扫描完成 && 允许数 > 0.
@MainActor
@Observable
final class ImportTypeSelectionModel {

    private let defaults: ImportDefaults
    private(set) var categories: ImportCategory
    private(set) var summary: ImportTypeSummary?

    init(defaults: ImportDefaults) {
        self.defaults = defaults
        self.categories = defaults.resolvedCategories()
    }

    /// The scan-completion face (the dialog's `.task` drives it once).
    func scanCompleted(_ summary: ImportTypeSummary) {
        self.summary = summary
    }

    var scanned: Bool { summary != nil }

    /// The per-family checkbox write: toggle + persist immediately.
    func setFamily(_ family: ImportCategory, on: Bool) {
        if on {
            categories.insert(family)
        } else {
            categories.remove(family)
        }
        defaults.setCategories(categories)
    }

    func isOn(_ family: ImportCategory) -> Bool {
        categories.contains(family)
    }

    /// The import button's gate: the scan must have completed AND at least
    /// one allowed file must exist under the current mask.
    var importEnabled: Bool {
        guard let summary else { return false }
        return summary.allowedCount(categories: categories) > 0
    }
}

struct ImportModeDialog: View {
    let request: ImportFlowRequest
    let initial: ImportModeChoice
    let onConfirm: (ImportModeChoice) -> Void
    let onCancel: () -> Void

    @State private var mode: ImportMode
    @State private var remember: Bool
    /// The M4-1-02 selector model (fresh per presentation; the mask seed
    /// reads the persisted key through the injected defaults host).
    @State private var selection: ImportTypeSelectionModel

    // M7-5-01 (D-M7-5-4 face ⑧): the import confirm gate — the agent-held
    // clause joins the merge. R3 F2-1: this read is why the dialog now rides
    // the ImportModeDialogSheetContent content face — the app-root sheet
    // closure sits OUTSIDE the root's `.environment(...)` writes, so a bare
    // presentation traps here on the first content update (the M2-8-3
    // FINDING-A family; the R12 real-machine ips signature).
    @Environment(AgentControlCoordinator.self) private var agentControl

    init(
        request: ImportFlowRequest, initial: ImportModeChoice,
        onConfirm: @escaping (ImportModeChoice) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.initial = initial
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _mode = State(initialValue: initial.mode)
        _remember = State(initialValue: initial.remember)
        _selection = State(initialValue: ImportTypeSelectionModel(
            defaults: ImportDefaults()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // zh backfill (M2-3-4 T1): the M2-2 verbatim debts land here.
            Text(String(localized: "import_dialog_title_folder",
                        defaultValue: "Import “\(request.folder.lastPathComponent)”"))
                .font(.headline)
            Picker(selection: $mode) {
                ForEach(ImportMode.allCases, id: \.self) { candidate in
                    Text(verbatim: Self.label(for: candidate))
                        .tag(candidate)
                }
            } label: {
                Text(String(localized: "import_dialog_transport",
                            defaultValue: "Transport"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(verbatim: Self.hint(for: mode))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            fileTypeSection
            Toggle(isOn: $remember) {
                Text(String(localized: "import_dialog_remember",
                            defaultValue: "Remember my choice"))
            }
            HStack {
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Text(String(localized: "import_dialog_cancel",
                                defaultValue: "Cancel"))
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    onConfirm(ImportModeChoice(
                        mode: mode, remember: remember,
                        categories: selection.categories))
                } label: {
                    Text(String(localized: "import_dialog_confirm",
                                defaultValue: "Import"))
                }
                .keyboardShortcut(.defaultAction)
                // M7-5-01 face ⑧: the agent-held clause joins the merge
                // (import is an Alcedo forbidden face while the agent
                // drives; ImportTaskAdapter/ImportService stay untouched).
                .disabled(!selection.importEnabled || agentControl.holdsControl)
            }
        }
        .padding(24)
        .frame(width: 440)
        .task { await scanFolder() }
    }

    // MARK: - The file-type selector section (KD-4, the upstream §9.3
    // narrowed shape: two checkable families with counts; every other
    // type shows its count UNCHECKABLE).

    @ViewBuilder private var fileTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "import_dialog_types",
                        defaultValue: "File types"))
                .font(.subheadline)
            if let summary = selection.summary {
                typeRow(
                    id: "raw",
                    label: String(localized: "import_type_raw",
                                  defaultValue: "Camera raw"),
                    count: summary.rawCount,
                    on: Binding(
                        get: { selection.isOn(.raw) },
                        set: { selection.setFamily(.raw, on: $0) }))
                typeRow(
                    id: "tiff",
                    label: String(localized: "import_type_tiff",
                                  defaultValue: "TIFF images"),
                    count: summary.tiffCount,
                    on: Binding(
                        get: { selection.isOn(.tiff) },
                        set: { selection.setFamily(.tiff, on: $0) }))
                otherTypesRow(count: summary.otherCount)
            } else {
                Text(String(localized: "import_types_scanning",
                            defaultValue: "Scanning…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.type.selector")
    }

    @ViewBuilder private func typeRow(
        id: String, label: String, count: Int, on: Binding<Bool>
    ) -> some View {
        Toggle(isOn: on) {
            HStack {
                Text(label)
                Spacer()
                Text(verbatim: Self.countText(count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("import.type.\(id)")
    }

    @ViewBuilder private func otherTypesRow(count: Int) -> some View {
        HStack {
            Text(String(localized: "import_type_other",
                        defaultValue: "Other types"))
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: Self.countText(count))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "lock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.type.other")
    }

    /// V14: explicit switch returning STATIC localization keys — the
    /// interpolated-key form is scanner-invisible (the M2-9-05 F-2 ban).
    private static func countText(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "import_type_count_one", defaultValue: "1 file")
        }
        return String(
            localized: "import_type_count_many",
            defaultValue: "\(count) files")
    }

    /// The one-shot scan (the dialog's only async work): the SHARED walker
    /// + the aggregate fold — no second scan logic. (Module-qualified: the
    /// App module carries its own Session-domain `ImportService` enum.)
    private func scanFolder() async {
        let urls = await Task.detached(priority: .userInitiated) { () -> [URL] in
            LightamerCore.ImportService.recursiveFiles(in: request.folder).map(\.url)
        }.value
        selection.scanCompleted(ImportTypeSummary.aggregate(urls))
    }

    private static func label(for mode: ImportMode) -> String {
        switch mode {
        case .move: String(localized: "import_mode_move", defaultValue: "Move")
        case .copy: String(localized: "import_mode_copy", defaultValue: "Copy")
        case .link: String(localized: "import_mode_link", defaultValue: "Link")
        }
    }

    private static func hint(for mode: ImportMode) -> String {
        switch mode {
        case .move:
            String(localized: "import_hint_move",
                   defaultValue: "Move photos into the project (same-volume renames, verified cross-volume copies; sources removed only after verification).")
        case .copy:
            String(localized: "import_hint_copy",
                   defaultValue: "Copy photos into the project Media folder, verifying every file; identical duplicates are skipped.")
        case .link:
            String(localized: "import_hint_link",
                   defaultValue: "Reference photos in place (no bytes move; the project records volume-relative paths and the original stays put).")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ImportModeDialogSheetContent (R3 F2-1 fix — the M2-8-3 FINDING-A twin) — the
// Import Folder sheet CONTENT face. The dialog's Observable dependency
// (`AgentControlCoordinator`, the M7-5-01 face ⑧ gate) is re-injected HERE,
// inside the presented content: the app-root sheet closure sits OUTSIDE the
// root's `.environment(...)` writes on the modifier chain, so the sheet's
// environment snapshot carried no coordinator and the first content update
// trapped ("No Observable object of type AgentControlCoordinator found",
// EXC_BREAKPOINT — the R12 real-machine ips: _assertionFailure ←
// EnvironmentValues.subscript.getter ← EnvironmentBox.update, deterministic
// on open). Same family, same fix shape as AdjustmentTransferSheetContent;
// `SheetEnvironmentInjectionTests` mounts this face through a real `.sheet`
// presentation.
// ─────────────────────────────────────────────────────────────────────────────

struct ImportModeDialogSheetContent: View {

    let agentControl: AgentControlCoordinator
    let request: ImportFlowRequest
    let initial: ImportModeChoice
    let onConfirm: (ImportModeChoice) -> Void
    let onCancel: () -> Void

    var body: some View {
        ImportModeDialog(
            request: request, initial: initial,
            onConfirm: onConfirm, onCancel: onCancel)
            .environment(agentControl)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LabelingAskDialog (Plan M2-10-03 KD-3 / OQ-6-A) — the auto-labeling ask,
// the Alcedo `SemanticGenerationDialog` interaction shape (GPL read-only
// reference — copy not reused): one question, 是/否, and the Remember-my-
// choice checkbox. Same stateless-binding shell as the transport dialog: the
// buttons hand (accepted, remember) straight back — all state lives in the
// LabelingPromptController + LabelingPreferences faces.
// ─────────────────────────────────────────────────────────────────────────────

struct LabelingAskDialog: View {
    let request: LabelingPromptController.Request
    let onDecide: (_ accepted: Bool, _ remember: Bool) -> Void

    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "labeling_ask_title",
                        defaultValue: "Analyze photo content with AI?"))
                .font(.headline)
            Text(String(localized: "labeling_ask_body",
                        defaultValue: "Lightamer can compute local labels for the \(request.imageCount) newly imported photos — keywords like “mountain” or “sunset”, computed entirely on this Mac. No photos leave the machine."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $remember) {
                Text(String(localized: "labeling_ask_remember",
                            defaultValue: "Remember my choice"))
            }
            HStack {
                Spacer()
                Button {
                    onDecide(false, remember)
                } label: {
                    Text(String(localized: "labeling_ask_decline",
                                defaultValue: "Not Now"))
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    onDecide(true, remember)
                } label: {
                    Text(String(localized: "labeling_ask_accept",
                                defaultValue: "Analyze"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
