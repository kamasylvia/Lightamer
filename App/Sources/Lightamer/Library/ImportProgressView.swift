import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ImportProgressView (Plan M2-2-2 T4, KD-4) — the minimal import-progress
// overlay: a pure snapshot renderer over ImportProgress (counts / failures /
// duplicate skips + the cancel button). All state lives in the Core value;
// cancel routes back to the controller's per-file checkpoint. zh localization
// landed with M2-3-4 T1 (the P4 backfill batch): phase titles and the count
// summary moved onto String(localized:) keys (arguments ride the catalog
// format), so zh mirrors the BackgroundTaskBar wording. No UI tests
// (stateless shell; the state face is Core-tested).
// ─────────────────────────────────────────────────────────────────────────────

struct ImportProgressView: View {
    let progress: ImportProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: Self.title(for: progress.phase))
                .font(.headline)
            ProgressView(
                value: progress.total > 0
                    ? Double(progress.processed) / Double(progress.total)
                    : 0)
            Text(verbatim: Self.summary(for: progress))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onCancel()
            } label: {
                Text(String(localized: "import_progress_cancel",
                            defaultValue: "Cancel"))
            }
            .disabled(progress.phase == .completed || progress.phase == .cancelled)
        }
        .padding(24)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private static func title(for phase: ImportProgress.Phase) -> String {
        switch phase {
        case .scanning:
            String(localized: "import_phase_scanning", defaultValue: "Scanning…")
        case .importing:
            String(localized: "import_phase_importing", defaultValue: "Importing…")
        case .completed:
            String(localized: "import_phase_completed", defaultValue: "Import complete")
        case .cancelled:
            String(localized: "import_phase_cancelled", defaultValue: "Import cancelled")
        }
    }

    private static func summary(for progress: ImportProgress) -> String {
        var summary = String(localized: "import_progress_summary",
                             defaultValue: "\(progress.processed) of \(progress.total)")
        if progress.failed > 0 {
            summary += String(localized: "import_progress_failed",
                              defaultValue: " — failed \(progress.failed)")
        }
        if progress.skippedDuplicates > 0 {
            summary += String(localized: "import_progress_duplicates",
                              defaultValue: " — duplicates skipped \(progress.skippedDuplicates)")
        }
        return summary
    }
}
