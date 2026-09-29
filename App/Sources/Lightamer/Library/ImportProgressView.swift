import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ImportProgressView (Plan M2-2-2 T4, KD-4) — the minimal import-progress
// overlay: a pure snapshot renderer over ImportProgress (counts / failures /
// duplicate skips + the cancel button). All state lives in the Core value;
// cancel routes back to the controller's per-file checkpoint. Verbatim
// strings: zh localization lands with the M2-3 shell. No UI tests (stateless
// shell; the state face is Core-tested).
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
                Text(verbatim: "Cancel")
            }
            .disabled(progress.phase == .completed || progress.phase == .cancelled)
        }
        .padding(24)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private static func title(for phase: ImportProgress.Phase) -> String {
        switch phase {
        case .scanning: "Scanning…"
        case .importing: "Importing…"
        case .completed: "Import complete"
        case .cancelled: "Import cancelled"
        }
    }

    private static func summary(for progress: ImportProgress) -> String {
        var summary = "\(progress.processed) of \(progress.total)"
        if progress.failed > 0 { summary += " — failed \(progress.failed)" }
        if progress.skippedDuplicates > 0 {
            summary += " — duplicates skipped \(progress.skippedDuplicates)"
        }
        return summary
    }
}
