import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-4 T2 (MCP-10): the launcher panel — one-click agent launch, the
// merged agent log (ring render, follow toggle, copy-all), the stop button
// and the honest completion faces.
//
// Faces (research §RQ-14-12 / D-14-CONTEXT-10):
//   • pre-flight: the template must exist and the embedded server must be
//     serving (the discovery file alive) — otherwise a hint line + log
//     entry, never a fake launch;
//   • the launch button renders the template (placeholder substitution in
//     McpLauncherTemplate) and starts the SHARED launcher core;
//   • the serial gate surfaces as a disabled button + the already-running
//     hint (the app-side ONE agent session rule);
//   • the stop button SIGTERMs the registered child (5s → SIGKILL inside
//     the core — only ever the registered own pid);
//   • non-zero exit = a red exit-code face; a finished session with ZERO
//     write-face tool calls shows「本次会话无写回」— the honest clause: the
//     count is what the SERVER saw (the registry write-call counter delta),
//     not a claim about what the agent intended;
//   • APP-ZERO-AI: no model call lives here — the app starts a process and
//     displays its bytes.
// ─────────────────────────────────────────────────────────────────────────────

/// The panel's observable state over the shared launcher core. One instance
/// per open panel window; the core (and the log ring) outlives it, so the
/// model re-syncs from the ring on appear.
@Observable
@MainActor
final class McpLauncherPanelModel {

    var lines: [String] = []
    var followScroll = true
    var isRunning = false
    var runningPID: Int32?
    /// The completion face of the last observed session: `.done(writeCalls:)`
    /// = exited cleanly with the server-side write-call delta;
    /// `.failed(code:)` = a non-zero exit (the red face).
    var lastOutcome: Outcome?
    var hint: String?

    enum Outcome: Equatable {
        case done(writeCalls: Int)
        case failed(code: Int32)
    }

    /// The write-call counter when THIS session launched (the delta is the
    /// session's write face). nil = not tracking (e.g. the server restarted
    /// mid-flight) — the completion face then reports the honest zero.
    private var writeCallsAtStart: Int?
    private var tapsInstalled = false

    init() {
        syncFromCore()
    }

    /// Re-reads the shared core (the ring + the registration) — the panel
    /// may be reopened AFTER a session started, so the view catches up.
    func syncFromCore() {
        let core = McpLauncher.shared
        lines = core.logBuffer.snapshot()
        isRunning = core.isRunning
        runningPID = core.runningPID
        installTaps()
    }

    /// The core exposes single-slot taps; this panel owns them (there is
    /// only ever one panel window). Lines land here AND in the ring.
    private func installTaps() {
        guard !tapsInstalled else { return }
        tapsInstalled = true
        McpLauncher.shared.onLogLine = { [weak self] line in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lines.append(line)
                // Mirror the core's ring cap so the display never grows
                // past what the buffer still holds.
                if self.lines.count > McpLauncherLogBuffer.defaultCapacity {
                    self.lines.removeFirst(
                        self.lines.count - McpLauncherLogBuffer.defaultCapacity)
                }
            }
        }
        McpLauncher.shared.onExit = { [weak self] status in
            Task { @MainActor [weak self] in
                await self?.handleExit(status)
            }
        }
    }

    /// The launch action (async: the pre-flight counter read hops to the
    /// registry actor). Failures surface as hints + log lines — never an
    /// assertion, never a silent no-op.
    func launch() async {
        installTaps()
        let defaults = UserDefaults.standard
        let template = defaults.string(forKey: McpLauncherTemplateKeys.command) ?? ""
        let prompt = defaults.string(forKey: McpLauncherTemplateKeys.prompt)
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hint = String(localized: "mcp_launcher_template_missing_hint")
            return
        }
        // Pre-flight: the agent will be pointed at the discovery file — if
        // no live endpoint serves it, the session would connect to nothing.
        guard case .alive = McpLauncher.endpointDiscoveryState() else {
            let message = String(localized: "mcp_launcher_server_off_hint")
            hint = message
            McpLauncher.shared.logBuffer.append("[launcher] \(message)")
            return
        }
        let rendered = McpLauncherTemplate.render(
            command: trimmed, prompt: prompt,
            endpointPath: McpEndpointPaths.makeDefault().jsonURL.path)
        hint = rendered.hasPromptPlaceholder && !rendered.promptInlined
            ? String(localized: "mcp_launcher_prompt_empty_hint")
            : nil
        writeCallsAtStart = await McpServerController.embeddedWriteCallCount()
        do {
            _ = try McpLauncher.shared.start(renderedCommand: rendered.command)
            isRunning = McpLauncher.shared.isRunning
            runningPID = McpLauncher.shared.runningPID
        } catch McpLauncher.LaunchFailure.alreadyRunning {
            hint = String(localized: "mcp_launcher_already_running")
        } catch McpLauncher.LaunchFailure.launchFailed(let reason) {
            let message = String(
                localized: "mcp_launcher_launch_failed \(reason)")
            hint = message
            McpLauncher.shared.logBuffer.append("[launcher] \(message)")
        } catch {
            let message = String(
                localized: "mcp_launcher_launch_failed \(error.localizedDescription)")
            hint = message
        }
    }

    func stop() {
        McpLauncher.shared.stop()
    }

    /// The export face: the FULL ring to the clipboard (v1 does no file
    /// export — research §RQ-14-12).
    func copyLog() {
        let text = McpLauncher.shared.logBuffer.snapshot().joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func handleExit(_ status: Int32) async {
        isRunning = false
        runningPID = nil
        let startCount = writeCallsAtStart
        writeCallsAtStart = nil
        let now = await McpServerController.embeddedWriteCallCount()
        if status == 0 {
            lastOutcome = .done(
                writeCalls: max(0, (now ?? 0) - (startCount ?? (now ?? 0))))
        } else {
            lastOutcome = .failed(code: status)
        }
    }
}

/// The preference key spellings the panel reads (SettingsView writes the
/// SAME keys via @AppStorage — one storage face, two views).
enum McpLauncherTemplateKeys {
    static let command = "mcp_agent_command_template"
    static let prompt = "mcp_agent_prompt_template"
}

/// The panel view (the `mcp-launcher` window scene).
struct McpLauncherPanelView: View {
    @State private var model = McpLauncherPanelModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            logPane
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 420)
        .preferredColorScheme(.dark)
        .task { model.syncFromCore() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(String(localized: "mcp_launcher_start")) {
                    Task { await model.launch() }
                }
                .disabled(model.isRunning)
                .accessibilityIdentifier("mcp.launcher.start")

                Button(String(localized: "mcp_launcher_stop"), role: .destructive) {
                    model.stop()
                }
                .disabled(!model.isRunning)
                .accessibilityIdentifier("mcp.launcher.stop")

                Spacer()

                Toggle(
                    String(localized: "mcp_launcher_follow_scroll"),
                    isOn: $model.followScroll)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("mcp.launcher.follow")

                Button(String(localized: "mcp_launcher_copy_log")) {
                    model.copyLog()
                }
                .accessibilityIdentifier("mcp.launcher.copy")
            }

            statusLine
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 8) {
            if model.isRunning {
                if let pid = model.runningPID {
                    Text("mcp_launcher_status_running \(pid)")
                        .foregroundStyle(.green)
                } else {
                    Text("mcp_launcher_status_running_generic")
                        .foregroundStyle(.green)
                }
            } else {
                Text("mcp_launcher_status_idle")
                    .foregroundStyle(.secondary)
            }
            switch model.lastOutcome {
            case .done(let writes):
                if writes == 0 {
                    // The honest clause: zero write-face calls this session.
                    Text("mcp_launcher_no_writeback")
                        .foregroundStyle(.secondary)
                } else {
                    Text("mcp_launcher_done_writes \(writes)")
                        .foregroundStyle(.green)
                }
            case .failed(let code):
                Text("mcp_launcher_exit_code \(code)")
                    .foregroundStyle(.red)
            case nil:
                EmptyView()
            }
            if let hint = model.hint {
                Text(hint)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .font(.callout)
    }

    private var logPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.lines.isEmpty {
                        Text("mcp_launcher_log_empty")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(model.lines.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("mcp.launcher.bottom")
                }
                .padding(8)
            }
            .background(LightamerColors.canvas)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(LightamerColors.textSecondary.opacity(0.25))
            }
            .onChange(of: model.lines.count) { _, _ in
                // 暂停滚动 = the follow toggle: OFF freezes the viewport.
                guard model.followScroll else { return }
                proxy.scrollTo("mcp.launcher.bottom", anchor: .bottom)
            }
        }
    }
}
