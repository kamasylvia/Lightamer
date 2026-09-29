import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundTaskBarView (Plan M2-3-1 T6, M2UIW-06) — the background-task
// faces of the new shell: the BOTTOM BAR (compact rows inside the workspace
// host) and the TASK DIALOG (the expanded sheet). BOTH render from the SAME
// registry through the SAME descriptor projection — the dual-presentation
// same-source guarantee (the AC's 同源断言) by construction.
//
// P1 mounts the bar in WorkspaceHostView (above the safe-area bottom edge);
// the dialog hosts the M2-2 ImportProgressView-family detail faces per leg —
// the import leg's compact rows + cancel ride the adapter through the
// registry, so the M2-2 dialog/progress view FILES themselves stay untouched
// (checker E3).
// ─────────────────────────────────────────────────────────────────────────────

/// The neutral row projection both faces render (the same-source seam: one
/// function, two consumers, identical rows).
struct BackgroundTaskDescriptor: Identifiable, Equatable {
    let id: UUID
    let title: String
    let progress: Double?
    let detail: String
}

enum BackgroundTaskProjection {

    /// The registry → rows projection (the ONLY rendering source). Both
    /// faces are main-actor state readers, so the projection is too.
    @MainActor
    static func descriptors(in registry: BackgroundTaskRegistry) -> [BackgroundTaskDescriptor] {
        registry.handles.map { handle in
            BackgroundTaskDescriptor(
                id: handle.id,
                title: handle.title,
                progress: handle.snapshot.progress,
                detail: handle.snapshot.detail)
        }
    }
}

struct BackgroundTaskBarView: View {

    let registry: BackgroundTaskRegistry
    /// The dialog presentation binding (the bar's expander drives it; the
    /// host may also raise it).
    @Binding var isDialogPresented: Bool

    var body: some View {
        let rows = BackgroundTaskProjection.descriptors(in: registry)
        Group {
            if !rows.isEmpty {
                HStack(spacing: 10) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                    Spacer()
                    Button {
                        isDialogPresented = true
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("tasks.bar.expand")
                    .accessibilityLabel(Text(String(localized: "tasks_show_details",
                                                    defaultValue: "Show task details")))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ThemeTokens.cardSurface)
                .overlay(
                    Rectangle()
                        .fill(ThemeTokens.cardBorder)
                        .frame(height: 1),
                    alignment: .top
                )
                .accessibilityIdentifier("tasks.bar")
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: BackgroundTaskDescriptor) -> some View {
        HStack(spacing: 6) {
            if let progress = row.progress {
                ProgressView(value: progress)
                    .frame(width: 90)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(row.title)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .lineLimit(1)
            Button {
                Task {
                    await registry.cancel(id: row.id)
                }
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("tasks.bar.cancel.\(row.id)")
            .accessibilityLabel(Text(String(localized: "tasks_cancel", defaultValue: "Cancel task")))
        }
    }
}

/// The task DIALOG host: the expanded face over the same registry (same
/// descriptors, roomier layout). P2/P3 legs land their detail views here.
struct BackgroundTaskDialogHost: View {

    let registry: BackgroundTaskRegistry
    @Binding var isPresented: Bool

    var body: some View {
        let rows = BackgroundTaskProjection.descriptors(in: registry)
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "tasks_dialog_title", defaultValue: "Background Tasks"))
                .font(.headline)
            if rows.isEmpty {
                Text(String(localized: "tasks_dialog_empty", defaultValue: "No background tasks running."))
                    .font(.callout)
                    .foregroundStyle(ThemeTokens.textSecondary)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.title)
                                .font(.callout)
                            Spacer()
                            if let progress = row.progress {
                                Text(row.detail)
                                    .font(.caption)
                                    .foregroundStyle(ThemeTokens.textSecondary)
                            }
                        }
                        if let progress = row.progress {
                            ProgressView(value: progress)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        HStack {
                            Spacer()
                            Button(String(localized: "tasks_cancel", defaultValue: "Cancel")) {
                                Task {
                                    await registry.cancel(id: row.id)
                                }
                            }
                            .accessibilityIdentifier("tasks.dialog.cancel.\(row.id)")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Spacer()
                Button(String(localized: "tasks_dialog_close", defaultValue: "Close")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("tasks.dialog.close")
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(ThemeTokens.cardSurface)
        .accessibilityIdentifier("tasks.dialog")
    }
}
