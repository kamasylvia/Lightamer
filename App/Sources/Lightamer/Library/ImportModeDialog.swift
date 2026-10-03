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

struct ImportModeDialog: View {
    let request: ImportFlowRequest
    let initial: ImportModeChoice
    let onConfirm: (ImportModeChoice) -> Void
    let onCancel: () -> Void

    @State private var mode: ImportMode
    @State private var remember: Bool

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
                    onConfirm(ImportModeChoice(mode: mode, remember: remember))
                } label: {
                    Text(String(localized: "import_dialog_confirm",
                                defaultValue: "Import"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
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
