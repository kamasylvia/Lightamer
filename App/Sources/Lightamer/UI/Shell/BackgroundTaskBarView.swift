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

    // M7-5-01 (OQ-5/D-M7-5-9): the agent activity card rides THIS bar — the
    // Stop button routes the coordinator (the single Stop entry); the
    // terminal pinned row's dismiss routes registry.dismiss + the
    // coordinator's card reset.
    @Environment(AgentControlCoordinator.self) private var agentControl

    var body: some View {
        let rows = BackgroundTaskProjection.descriptors(in: registry)
        Group {
            if !rows.isEmpty {
                HStack(spacing: 10) {
                    ForEach(rows) { row in
                        if let handle = registry.handle(id: row.id)
                            as? AgentTaskHandle {
                            agentRowView(row, handle)
                        } else {
                            rowView(row)
                        }
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

    // MARK: - The agent activity row (M7-5-01 TURN-02; OQ-5: bar row, no
    // banner, no new presentation face)

    @ViewBuilder
    private func agentRowView(
        _ row: BackgroundTaskDescriptor, _ handle: AgentTaskHandle
    ) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "tasks_agent_kind", defaultValue: "Agent"))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
            Text(row.title)
                .font(.caption)
                .foregroundStyle(
                    handle.isRunning ? ThemeTokens.textPrimary : ThemeTokens.textSecondary)
                .lineLimit(1)
            if handle.isRunning {
                // THE Stop entry (D-M7-5-9 single route): handle.cancel()
                // → coordinator.stop(). NEVER registry.cancel here — its
                // finish-removal arm would strip the pinned row and break
                // the resume continuity (F8).
                Button {
                    Task { await handle.cancel() }
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("tasks.bar.agent.stop")
                .accessibilityLabel(Text(String(
                    localized: "tasks_agent_stop", defaultValue: "Stop agent")))
            } else {
                // The terminal pinned row: the user's manual removal.
                Button {
                    registry.dismiss(id: row.id)
                    agentControl.dismissCard()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("tasks.bar.agent.dismiss")
                .accessibilityLabel(Text(String(
                    localized: "tasks_dismiss", defaultValue: "Dismiss")))
            }
        }
        .accessibilityIdentifier("tasks.bar.agent")
    }
}

/// The task DIALOG host: the expanded face over the same registry (same
/// descriptors, roomier layout). P2/P3 legs land their detail views here.
struct BackgroundTaskDialogHost: View {

    let registry: BackgroundTaskRegistry
    @Binding var isPresented: Bool

    // M7-5-01: the agent rows' Stop/dismiss routing (the bar's twin).
    @Environment(AgentControlCoordinator.self) private var agentControl

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
                        // M7-5-01: the indeterminate rows' detail (the
                        // agent's in-flight command / waiting copy — the
                        // title-row detail slot only renders with a
                        // fraction).
                        if row.progress == nil {
                            Text(row.detail)
                                .font(.caption)
                                .foregroundStyle(ThemeTokens.textSecondary)
                        }
                        // M7-5-01: the agent rows carry the per-command
                        // activity list (the resume-continuity carrier).
                        if let handle = registry.handle(id: row.id)
                            as? AgentTaskHandle {
                            agentActivityList(handle)
                        }
                        HStack {
                            Spacer()
                            if let handle = registry.handle(id: row.id)
                                as? AgentTaskHandle {
                                if handle.isRunning {
                                    Button(String(
                                        localized: "tasks_agent_stop",
                                        defaultValue: "Stop agent")) {
                                        Task { await handle.cancel() }
                                    }
                                    .accessibilityIdentifier(
                                        "tasks.dialog.agent.stop.\(row.id)")
                                } else {
                                    Button(String(
                                        localized: "tasks_dismiss",
                                        defaultValue: "Dismiss")) {
                                        registry.dismiss(id: row.id)
                                        agentControl.dismissCard()
                                    }
                                    .accessibilityIdentifier(
                                        "tasks.dialog.agent.dismiss.\(row.id)")
                                }
                            } else {
                                Button(String(localized: "tasks_cancel", defaultValue: "Cancel")) {
                                    Task {
                                        await registry.cancel(id: row.id)
                                    }
                                }
                                .accessibilityIdentifier("tasks.dialog.cancel.\(row.id)")
                            }
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

    // MARK: - The agent activity list (M7-5-01 TURN-02; D-M7-5-6)

    /// The per-command rows (summary + result symbol — no text badge keys;
    /// the symbol carries the state: pending ellipsis / ok checkmark /
    /// interrupted xmark).
    @ViewBuilder
    private func agentActivityList(_ handle: AgentTaskHandle) -> some View {
        if !handle.activity.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(handle.activity) { entry in
                    HStack(spacing: 6) {
                        switch entry.result {
                        case .pending:
                            ProgressView()
                                .controlSize(.mini)
                        case .ok:
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundStyle(ThemeTokens.accent)
                        case .interrupted:
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(ThemeTokens.textSecondary)
                        }
                        Text(entry.summary)
                            .font(.caption)
                            .foregroundStyle(ThemeTokens.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }
            .padding(.top, 2)
            .accessibilityIdentifier(
                "tasks.dialog.agent.activity.\(handle.id)")
        }
    }
}
