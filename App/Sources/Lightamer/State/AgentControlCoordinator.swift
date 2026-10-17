import Foundation
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// AgentControlCoordinator (M7-5-01 T2/T3, D-M7-5-4..9) — the GUI-session
// turn-taking single writer (the Alcedo AgentControlOwner semantics anchor;
// state machine and card fields only — the code and copy are self-written).
//
// SINGLE-WRITER RED LINE: the control state (held / stoppedByUser /
// holderName / taskId / activity) is written ONLY here. The GUI disable
// faces, the activity card and get_state's control.agent face are read-only
// projections. Orthogonal to M6-1 (the cross-process project write right —
// SingleWriterLock / LibraryProjectController are never touched: two
// layers, two owners).
//
// ISOLATION: @MainActor — acquire/release/stop/admit are GUI-session facts.
// The MCP tool handlers reach the state through @Sendable provider closures
// that MainActor.run-hop into this coordinator (the liveState discipline);
// the coordinator type never leaks into a tool implementation.
//
// The activity log is BOUNDARY-DRIVEN (D-M7-5-6, the declared simplified
// form): admit success opens an in-flight entry; the NEXT boundary (the
// next admit / release / stop) closes it (a user Stop marks the in-flight
// command `interrupted`). There is no per-command end hook — the admit seam
// carries admit only.
// ─────────────────────────────────────────────────────────────────────────────

/// One activity-log row (the card's dialog list face). `result` closes on
/// the boundary rules above.
struct AgentActivityEntry: Identifiable, Equatable, Sendable {
    enum Result: Sendable, Equatable {
        /// Open — the command is in flight.
        case pending
        /// Closed at the next boundary (the command returned).
        case ok
        /// Closed by a user Stop while the command was in flight.
        case interrupted
    }

    let id: UUID
    var summary: String
    var result: Result

    init(summary: String, result: Result = .pending) {
        self.id = UUID()
        self.summary = summary
        self.result = result
    }
}

/// The registry handle for the agent's own task (the activity card row).
/// PINNED: terminal states stay in the list until the user dismisses (the
/// resume-continuity carrier — the same id returns to Running).
@MainActor
@Observable
final class AgentTaskHandle: BackgroundTaskHandle {
    let id: UUID
    var title: String
    var snapshot: BackgroundTaskSnapshot
    /// M7-5-01 (OQ-6): THE pinned handle — terminal states stay in the
    /// registry until the user dismisses (the resume-continuity carrier).
    /// The three pre-M7-5 legs ride the extension default (false).
    let isPinned = true
    /// The activity log mirror (the dialog's per-command rows).
    var activity: [AgentActivityEntry] = []
    /// True while the control is held OR a resume is possible (terminal
    /// states keep the row pinned but not running).
    private(set) var isRunning: Bool = true

    private weak var coordinator: AgentControlCoordinator?

    init(id: UUID, holderName: String, coordinator: AgentControlCoordinator) {
        self.id = id
        self.title = "Agent · \(holderName)"
        self.snapshot = .indeterminate(
            String(localized: "agent_card_waiting",
                   defaultValue: "Waiting for the next command"))
        self.coordinator = coordinator
    }

    /// Stop — the card cancel button's ONLY route (D-M7-5-9 single entry).
    /// Never routes through registry.cancel (its finish-removal arm would
    /// strip the pinned row and break resume continuity).
    func cancel() async {
        coordinator?.stop()
    }

    // MARK: Coordinator-only mutation faces (single-writer: the coordinator
    // is the only caller — the projections below are @MainActor internal).

    func setRunning(_ running: Bool) { isRunning = running }

    func setTitle(_ title: String) { self.title = title }

    func setDetail(_ detail: String) {
        snapshot = .indeterminate(detail)
    }

    func setActivity(_ entries: [AgentActivityEntry]) {
        activity = entries
    }
}

@MainActor
@Observable
final class AgentControlCoordinator {

    // MARK: The control state (single-writer: mutations live in THIS class)

    /// The agent currently holds the GUI control.
    private(set) var held = false
    /// The user stopped the agent (the card's Stop) — any state-changing
    /// command is refused until the agent re-acquires.
    private(set) var stoppedByUser = false
    /// The CURRENT holder's label ("" when not held).
    private(set) var holderName = ""
    /// The holder the user stopped (the resume credential — an acquire with
    /// the same label continues that task; recorded for the card face).
    private(set) var stoppedHolderName: String?
    /// The pinned card's task id (nil = no agent task yet; same-holder
    /// resume keeps this id).
    private(set) var taskId: UUID?
    /// The boundary-driven activity log (the dialog rows).
    private(set) var activity: [AgentActivityEntry] = []

    /// The GUI disable faces' single source (the .disabled gates read this).
    var holdsControl: Bool { held }

    // MARK: Injected deps (F12: the registry reference + the live-edit probe)

    /// The live-edit probe — the THREE-window OR (D-H1 continuous drag /
    /// DRT drag / film drag; the PipeCoordinator.liveEditActive computed
    /// property feeds this at the assembly point). Settable, never a hard
    /// reference (the F-6 testability seam): the App root cannot reference
    /// its other @State objects at declaration time, so the probe lands via
    /// `configureLiveEditProbe` in the launch task (the
    /// pipeCoordinator.configure(window:) cross-attach precedent). The
    /// default answers false (no edit window) — tests inject their own.
    private var liveEditActive: @Sendable () async -> Bool = { false }
    /// The acquire wait budget (D-M7-5-7). Production default =
    /// McpTimeouts.controlAcquire; tests inject a short window.
    private let acquireTimeout: Duration
    /// The poll cadence for the unsealed-input wait.
    private let pollInterval: Duration
    /// The task registry the card row registers into (weak — the shell
    /// window owns the aggregate registry; attached at the host's .task).
    private weak var taskRegistry: BackgroundTaskRegistry?
    /// The pinned card handle (nil until the first acquire).
    private var handle: AgentTaskHandle?

    init(
        acquireTimeout: Duration = McpTimeouts.controlAcquire,
        pollInterval: Duration = .milliseconds(250)
    ) {
        self.acquireTimeout = acquireTimeout
        self.pollInterval = pollInterval
    }

    /// Installs the live-edit probe (the assembly point's cross-attach leg;
    /// idempotent — the launch task may run per window).
    func configureLiveEditProbe(
        _ provider: @escaping @Sendable () async -> Bool
    ) {
        liveEditActive = provider
    }

    /// The shell's cross-attach leg (the pipeCoordinator.configure(window:)
    /// precedent): the App-level coordinator cannot reach the window-scoped
    /// @State registry, so the host hands it over here. Weak on this side.
    func attachTaskRegistry(_ registry: BackgroundTaskRegistry) {
        taskRegistry = registry
        // A pinned row from a previous session of this coordinator instance
        // (window teardown survivor) re-registers idempotently.
        if let handle { registry.register(handle) }
    }

    // MARK: - admit (the registry's third gate — the MCP face)

    /// The control-admit rule (D-M7-5-1/D-M7-5-3): held → pass (and open
    /// the activity entry); user-stopped → `controlRevokedByUser`; never
    /// held / released → `controlNotHeld`. The boundary rule closes the
    /// previous in-flight entry here (it returned — the next admit proves
    /// that).
    func admit(toolName: String) async throws {
        if stoppedByUser {
            throw McpToolError.controlRevokedByUser(String(
                localized: "mcp_error_control_revoked_by_user",
                defaultValue: "用户已停止 agent——请停止工作并询问用户如何继续；征得用户同意后再 control_acquire。"))
        }
        guard held else {
            throw McpToolError.controlNotHeld(String(
                localized: "mcp_error_control_not_held",
                defaultValue: "此命令会更改会话状态，需要 agent 控制权——请先调用 control_acquire。"))
        }
        closeInFlight(with: .ok)
        let entry = AgentActivityEntry(summary: toolName)
        activity.append(entry)
        handle?.setActivity(activity)
        handle?.setDetail(toolName)
    }

    // MARK: - acquire (the turn-taking entry — the MCP face)

    /// Acquire the control for `holderName`. The three refusal faces:
    /// another holder → `controlBusy` carrying the holder; an unsealed
    /// editor input (the live-edit probe) → WAIT (bounded by the injected
    /// timeout) then `controlBusy` carrying the unsealed semantics; a user
    /// Stop while waiting → `controlRevokedByUser`. Success = same holder
    /// resumes the SAME task id (activity history continues across a Stop),
    /// a different holder mints a new task; any success clears
    /// stoppedByUser.
    func acquire(_ holderName: String) async throws -> McpControlState {
        // Another live holder refuses immediately (no wait — the editor
        // input cannot seal while a different agent drives anyway).
        if held, self.holderName != holderName {
            throw McpToolError.controlBusy(String(
                localized: "mcp_error_control_busy",
                defaultValue: "另一持有者已持有控制权：\(self.holderName)。"))
        }
        let alreadyHeldBySelf = held && self.holderName == holderName
        if !alreadyHeldBySelf {
            // Wait for the unsealed editor input to seal (the user drag is
            // a seconds-scale norm — an instant refusal would put the agent
            // into a pointless retry loop; D-M7-5-7).
            let deadline = ContinuousClock.now + acquireTimeout
            while await liveEditActive() {
                if stoppedByUser {
                    throw McpToolError.controlRevokedByUser(String(
                        localized: "mcp_error_control_revoked_by_user",
                        defaultValue: "用户已停止 agent——请停止工作并询问用户如何继续；征得用户同意后再 control_acquire。"))
                }
                if ContinuousClock.now >= deadline {
                    throw McpToolError.controlBusy(
                        "control acquisition timed out — the editor input is "
                            + "not sealed (the user is still dragging in the "
                            + "GUI); retry after the input settles")
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
        // Success. The resume routing: a re-acquire with the holder the
        // user stopped (the remembered credential) resumes the SAME task id
        // (activity history continues across the Stop); any other fresh
        // acquisition mints a new task — the old row stays pinned until the
        // user dismisses it. A post-release acquire is a NEW task (release
        // is terminal Succeeded).
        if !alreadyHeldBySelf {
            let resumeSameTask =
                stoppedHolderName == holderName && taskId != nil && handle != nil
            if !resumeSameTask {
                taskId = UUID()
                handle = AgentTaskHandle(
                    id: taskId!, holderName: holderName, coordinator: self)
            }
        }
        held = true
        self.holderName = holderName
        stoppedByUser = false
        stoppedHolderName = nil
        if let handle {
            handle.setRunning(true)
            handle.setTitle("Agent · \(holderName)")
            handle.setActivity(activity)
            taskRegistry?.register(handle)  // id dedup = resume re-register idempotent
        }
        return currentState()
    }

    // MARK: - release / stop / state (the MCP + card faces)

    /// Release the control (idempotent — no control = no change). The
    /// pinned card row stays (terminal Succeeded), the activity closes.
    func release() -> McpControlState {
        closeInFlight(with: .ok)
        if held {
            held = false
            holderName = ""
            handle?.setRunning(false)
        }
        return currentState()
    }

    /// Stop (the card cancel button's single entry — D-M7-5-9): the control
    /// returns to the user IMMEDIATELY, the stopped holder is remembered
    /// (the resume credential), the in-flight command closes `interrupted`,
    /// the task lands Canceled and stays pinned.
    func stop() {
        guard held || taskId != nil else { return }
        closeInFlight(with: .interrupted)
        stoppedHolderName = held ? holderName : stoppedHolderName
        held = false
        holderName = ""
        stoppedByUser = true
        handle?.setRunning(false)
    }

    /// The state snapshot (get_state's control.agent face + the tools'
    /// answers).
    func currentState() -> McpControlState {
        McpControlState(
            held: held, revokedByUser: stoppedByUser,
            holder: held ? holderName : "")
    }

    // MARK: - dismiss (the pinned-row removal — the user's manual route)

    /// The user dismissed the pinned card row (T3's registry.dismiss
    /// route). The coordinator drops its own handle reference; a later
    /// acquire with the same holder mints a FRESH task (the continuity is
    /// broken deliberately by the user).
    func dismissCard() {
        handle = nil
        taskId = nil
        activity = []
    }

    // MARK: - Internals

    /// The boundary closure rule: the open (pending) entry closes with the
    /// boundary's result.
    private func closeInFlight(with result: AgentActivityEntry.Result) {
        if let index = activity.firstIndex(where: { $0.result == .pending }) {
            activity[index].result = result
            handle?.setActivity(activity)
        }
    }
}
