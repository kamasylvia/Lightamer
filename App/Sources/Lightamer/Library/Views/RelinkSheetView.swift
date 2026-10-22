import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// RelinkSheetView (Plan M2-3-2 T4, KD-4) — the batch-relink sheet over the
// selected stale rows: the TWO stale forms render as separate sections
// (pathMissing = a concrete path with the file gone; volumeAbsent = no
// mounted volume carries the recorded UUID — "know WHY it broke"), each
// with its own "choose new location" picker, then the batch runs with the
// monotonic progress bar + cancel, and the three-way result counts land.
//
// The orchestration lives in LibraryRelinkModel; the sheet is presentation
// only. `library.relink.*` markers.
// ─────────────────────────────────────────────────────────────────────────────

struct RelinkSheetView: View {

    /// The relink logic face (classification + the batch loop).
    let model: LibraryRelinkModel
    /// The rows the batch acts on (the Inspector's stale selection).
    let rows: [LibraryImageRow]
    /// The open package (classification + relink reference).
    let projectDirectory: URL
    /// The store write seam (the default persist leg).
    let store: ProjectFileStore
    let onDismiss: () -> Void

    @State private var classification: LibraryRelinkModel.Classification?
    @State private var handle: RelinkTaskHandle?
    @State private var result: LibraryRelinkModel.BatchResult?
    @State private var pickedDirectory: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(
                localized: "relink_title",
                defaultValue: "Relink Missing Photos"))
                .font(.headline)
                .foregroundStyle(ThemeTokens.textPrimary)

            if let result {
                resultSection(result)
            } else {
                if let classification {
                    section(
                        title: String(
                            localized: "relink_section_path_missing",
                            defaultValue: "Missing Path"),
                        marker: "library.relink.section.pathmissing",
                        rows: classification.pathMissing,
                        why: String(
                            localized: "relink_why_path_missing",
                            defaultValue: "The file is gone from its recorded path."))
                    section(
                        title: String(
                            localized: "relink_section_volume_absent",
                            defaultValue: "Volume Absent"),
                        marker: "library.relink.section.volumeabsent",
                        rows: classification.volumeAbsent,
                        why: String(
                            localized: "relink_why_volume_absent",
                            defaultValue: "No mounted volume carries the recorded disk."))
                    pickerRow
                }
                if let handle {
                    progressSection(handle)
                }
            }
            HStack {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Text(String(
                        localized: "relink_done", defaultValue: "Done"))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("library.relink.done")
            }
        }
        .padding(18)
        .frame(width: 430)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(ThemeTokens.cardSurface)
                .shadow(radius: 18)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(ThemeTokens.cardBorder, lineWidth: 1)
        }
        .padding(30)
        .background(ThemeTokens.busyDim)
        .onAppear {
            if classification == nil {
                classification = LibraryRelinkModel.classify(
                    rows: rows, projectDirectory: projectDirectory)
            }
        }
        .accessibilityIdentifier("library.relink.sheet")
    }

    // MARK: - One stale section

    private func section(
        title: String, marker: String, rows: [LibraryImageRow], why: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ThemeTokens.textSecondary)
                .textCase(.uppercase)
            Text(verbatim: why)
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
            if rows.isEmpty {
                Text(String(
                    localized: "relink_section_empty",
                    defaultValue: "None in the selection"))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            ForEach(rows, id: \.id) { row in
                Text(verbatim: row.filename ?? row.imagePath)
                    .font(.callout)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(ThemeTokens.cardBorder.opacity(0.25))
        }
        .accessibilityIdentifier(marker)
    }

    // MARK: - The picker + batch trigger

    private var pickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                // L057 (fix(l057)): async panel via the begin seam.
                Task { await pickDirectory() }
            } label: {
                Label(
                    String(
                        localized: "relink_pick",
                        defaultValue: "Choose New Location…"),
                    systemImage: "folder")
            }
            .accessibilityIdentifier("library.relink.pick")
            if let pickedDirectory {
                Text(verbatim: pickedDirectory.path)
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .lineLimit(1)
            }
            if model.canPersist {
                Button {
                    runBatch()
                } label: {
                    Text(String(
                        localized: "relink_run",
                        defaultValue: "Relink to This Location"))
                }
                .disabled(pickedDirectory == nil)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("library.relink.run")
            } else {
                // The honest gate (the Core write face pending — the model's
                // D-note): the classification and the records are real, the
                // run waits for the persistence seam.
                Text(String(
                    localized: "relink_persistence_pending",
                    defaultValue:
                        "Relinking lands with the project-file write face — classification is live, the batch waits."))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .accessibilityIdentifier("library.relink.pending")
            }
        }
    }

    /// L057 (fix(l057)): async via the begin seam — a sync runModal here
    /// nested inside the button-action dispatch (the crash family shape).
    private func pickDirectory() async {
        let panel = NSOpenPanel()
        panel.title = String(
            localized: "relink_pick_title",
            defaultValue: "Choose the folder holding the moved files")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard let url = await PanelPresentation.present(panel) else { return }
        pickedDirectory = url
    }

    private func runBatch() {
        guard let pickedDirectory else { return }
        let batchHandle = RelinkTaskHandle(count: rows.count) {
            model.cancel()
        }
        handle = batchHandle
        Task {
            let outcome = await model.runBatch(
                rows: rows,
                sourceDirectory: pickedDirectory,
                projectDirectory: projectDirectory,
                store: store,
                handle: batchHandle)
            result = outcome
        }
    }

    // MARK: - Progress / result

    private func progressSection(_ handle: RelinkTaskHandle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: handle.title)
                .font(.callout)
                .foregroundStyle(ThemeTokens.textPrimary)
            if let fraction = handle.snapshot.progress {
                ProgressView(value: fraction)
                    .accessibilityIdentifier("library.relink.progress")
            } else {
                ProgressView()
                    .accessibilityIdentifier("library.relink.progress")
            }
            Text(verbatim: handle.snapshot.detail)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
            Button {
                Task { await model.cancel() }
            } label: {
                Text(String(
                    localized: "relink_cancel", defaultValue: "Cancel"))
            }
            .accessibilityIdentifier("library.relink.cancel")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultSection(_ result: LibraryRelinkModel.BatchResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(
                localized: "relink_result_title",
                defaultValue: "Batch finished"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(ThemeTokens.textPrimary)
            resultLine(
                String(localized: "relink_result_relived",
                       defaultValue: "Relinked"),
                count: result.relived,
                marker: "library.relink.result.relived")
            resultLine(
                String(localized: "relink_result_stillstale",
                       defaultValue: "Still missing"),
                count: result.stillStale,
                marker: "library.relink.result.stillstale")
            resultLine(
                String(localized: "relink_result_cancelled",
                       defaultValue: "Cancelled"),
                count: result.cancelled,
                marker: "library.relink.result.cancelled")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultLine(_ title: String, count: Int, marker: String) -> some View {
        HStack {
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
            Spacer()
            Text(verbatim: "\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(ThemeTokens.textPrimary)
        }
        .accessibilityIdentifier(marker)
    }
}
