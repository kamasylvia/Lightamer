import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ExportQueueFaceView (Plan M2-9-04 T3, KD-2 节 5) — the Export page's queue
// section: the Alcedo QML:1077-1318 face over the EXISTING queue snapshots
// (no new state, no queue-engine awareness — the four-state map is a pure
// projection, the 36-row preview cap is a UI-layer slice, and the progress
// rides the two-layer snapshot the legacy panel already renders).
//
//   • add (the batch enqueue — the page's run face) + clear (cancel all);
//   • four-state rows: Queued / Exporting / Done / Failed — the
//     `ExportJobState` projection (pending→Queued; rendering+encoding→
//     Exporting; done→Done; failed+cancelled→Failed — the cancellation
//     folds into the FAILED tier per the plan ruling, DECISIONS);
//   • the 36-row preview cap + the `…(N more)` summary row (QML:47/129);
//   • the completed/total progress bar + the failed-count red summary +
//     the per-job retry (the failed tier's only escape — the dt posture).
// ─────────────────────────────────────────────────────────────────────────────

/// The page's four-state projection (KD-2 节 5 / the 已定裁决 四态映射).
enum ExportQueueFaceState: Equatable, Sendable {
    case queued
    case exporting
    case done
    case failed

    static func map(_ state: ExportJobState) -> ExportQueueFaceState {
        switch state {
        case .pending: return .queued
        case .rendering, .encoding: return .exporting
        case .done: return .done
        case .failed, .cancelled: return .failed
        }
    }

    var icon: String {
        switch self {
        case .queued: return "clock"
        case .exporting: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        }
    }

    var color: Color {
        switch self {
        case .queued, .exporting: return .accentColor
        case .done: return .green
        case .failed: return .red
        }
    }

    var labelKey: String {
        switch self {
        case .queued: return "export_face_state_queued"
        case .exporting: return "export_face_state_exporting"
        case .done: return "export_face_state_done"
        case .failed: return "export_face_state_failed"
        }
    }
}

struct ExportQueueFaceView: View {

    let jobRows: [ExportJobSnapshot]
    let progress: ExportProgress
    let canRun: Bool
    let targetsCount: Int
    let onRun: () -> Void
    let onClear: () -> Void
    let onRetry: (UUID) -> Void
    let onCancel: (UUID) -> Void

    /// The preview cap (the Alcedo QML:47 face — 36 rows + the summary).
    nonisolated static let previewCap = 36

    /// The preview slice face (state-layer test target): the first 36 rows
    /// + how many more (0 = no summary row).
    nonisolated static func previewSlice(
        _ rows: [ExportJobSnapshot]
    ) -> (preview: [ExportJobSnapshot], more: Int) {
        guard rows.count > previewCap else { return (rows, 0) }
        return (Array(rows.prefix(previewCap)), rows.count - previewCap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "export_queue_section"))
                .font(.subheadline.weight(.semibold))

            if jobRows.isEmpty && progress.total == 0 {
                ContentUnavailableView {
                    Label("export_queue_idle", systemImage: "tray")
                } description: {
                    Text("export_queue_idle_body")
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("export.queue.empty")
            } else {
                progressRow
            }

            HStack {
                Button {
                    onRun()
                } label: {
                    Label(
                        String(localized: "export_face_add_selected \(targetsCount)"),
                        systemImage: "square.and.arrow.up")
                }
                .disabled(!canRun)
                .accessibilityIdentifier("export.queue.add")
                Spacer()
                Button(String(localized: "export_face_clear")) {
                    onClear()
                }
                .disabled(jobRows.isEmpty && progress.total == 0)
                .accessibilityIdentifier("export.queue.clear")
            }

            errorSummary

            ForEach(preview.preview, id: \.id) { row in
                faceRow(row)
            }
            if preview.more > 0 {
                Text(String(localized: "export_face_more \(preview.more)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("export.queue.more")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.section.queue")
    }

    private var preview: (preview: [ExportJobSnapshot], more: Int) {
        Self.previewSlice(jobRows)
    }

    private var progressRow: some View {
        HStack {
            ProgressView(
                value: Double(progress.done),
                total: Double(max(progress.total, 1)))
            Text("\(progress.done)/\(progress.total)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let phase = progress.activePhase {
                Text(
                    phase == .rendering
                        ? String(localized: "export_job_state_rendering")
                        : String(localized: "export_job_state_encoding"))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("export.queue.progress")
    }

    /// The failed-count red summary (the Alcedo QML:1259-1318 error face).
    @ViewBuilder
    private var errorSummary: some View {
        let failed = jobRows.filter { ExportQueueFaceState.map($0.state) == .failed }
        if !failed.isEmpty {
            Label {
                Text(String(localized: "export_face_failed_summary \(failed.count)"))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)
            .font(.caption)
            .accessibilityIdentifier("export.queue.error_summary")
        }
    }

    private func faceRow(_ row: ExportJobSnapshot) -> some View {
        let face = ExportQueueFaceState.map(row.state)
        return HStack(spacing: 8) {
            Image(systemName: face.icon)
                .foregroundStyle(face.color)
                .accessibilityIdentifier("export.queue.row_icon")
            Text(row.relPath)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if case .failed(let error) = row.state {
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(error.localizedDescription)
                Button(String(localized: "export_retry")) {
                    onRetry(row.id)
                }
                .accessibilityIdentifier("export.queue.retry")
            } else if !row.state.isTerminal {
                Button(String(localized: "export_cancel_one")) {
                    onCancel(row.id)
                }
                .accessibilityIdentifier("export.queue.cancel_one")
            }
            Text(String(localized: String.LocalizationValue(face.labelKey)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("export.queue.row_state")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.queue.row")
    }
}
