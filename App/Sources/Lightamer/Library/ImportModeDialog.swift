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
// Verbatim strings: zh localization lands with the M2-3 shell.
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
            Text(verbatim: "Import “\(request.folder.lastPathComponent)”")
                .font(.headline)
            Picker(selection: $mode) {
                ForEach(ImportMode.allCases, id: \.self) { candidate in
                    Text(verbatim: Self.label(for: candidate))
                        .tag(candidate)
                }
            } label: {
                Text(verbatim: "Transport")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(verbatim: Self.hint(for: mode))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: $remember) {
                Text(verbatim: "Remember my choice")
            }
            HStack {
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Text(verbatim: "Cancel")
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    onConfirm(ImportModeChoice(mode: mode, remember: remember))
                } label: {
                    Text(verbatim: "Import")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private static func label(for mode: ImportMode) -> String {
        switch mode {
        case .move: "Move"
        case .copy: "Copy"
        case .link: "Link"
        }
    }

    private static func hint(for mode: ImportMode) -> String {
        switch mode {
        case .move:
            "Move photos into the project (same-volume renames, verified cross-volume copies; sources removed only after verification)."
        case .copy:
            "Copy photos into the project Media folder, verifying every file; identical duplicates are skipped."
        case .link:
            "Reference photos in place (no bytes move; the project records volume-relative paths and the original stays put)."
        }
    }
}
