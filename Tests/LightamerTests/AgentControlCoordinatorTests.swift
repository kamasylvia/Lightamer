import Foundation
import LightamerCore
import SwiftUI
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// AgentControlCoordinatorTests (Plan M7-5-01 T6) — the coordinator state
// machine + the GUI-face structural judgments:
//
//   • the FULL machine sequence: acquire → the admit activity entry → Stop
//     → the revoked refusal → the SAME-holder resume (the SAME task id +
//     the activity history continuity) → the release terminal → the user
//     dismiss;
//   • the boundary-driven activity closure (D-M7-5-6): the next
//     admit/release/stop closes the open entry (a user Stop marks it
//     interrupted);
//   • the busy face (a different live holder carries the holder) + the
//     stoppedByUser clearing on any successful acquire;
//   • the F8 negative: the Stop leaves the pinned handle IN the registry
//     (the agent row never routes registry.cancel's finish-removal arm);
//     the three legacy legs ride the extension default (isPinned == false,
//     finish-removes unchanged) and the pinned agent handle removes ONLY
//     through dismiss;
//   • the禁编辑 face manifest (the 12-face Alcedo table → our 11 landing
//     points + the delete absence): the source-level merge-form scan (the
//     MultiDisplayProfileTests precedent) + the conditional-unmount
//     negative (the `if !agentControl` shape must NOT exist);
//   • the scopes preservation negatives: the coordinator carries ZERO
//     scope references (the source scan) — the disable-not-unmount faces
//     keep the panels mounted (the structural precondition).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class AgentControlCoordinatorTests: XCTestCase {

    // MARK: - The state machine full sequence

    func testFullSequenceAcquireAdmitStopResumeReleaseDismiss() async throws {
        let coordinator = AgentControlCoordinator(
            acquireTimeout: .seconds(2), pollInterval: .milliseconds(20))
        let registry = BackgroundTaskRegistry()

        // acquire → the card row registers (the bar/dialog faces have a
        // row), holdsControl flips.
        coordinator.attachTaskRegistry(registry)
        let state = try await coordinator.acquire("cc")
        XCTAssertEqual(state.held, true)
        XCTAssertEqual(coordinator.holdsControl, true)
        XCTAssertEqual(registry.count, 1, "the pinned row is up")
        let handle = try XCTUnwrap(
            registry.handles.first as? AgentTaskHandle, "the row is the agent handle")
        XCTAssertEqual(handle.id, coordinator.taskId)
        XCTAssertEqual(handle.isPinned, true)

        // admit (held) → the activity entry opens in-flight.
        try await coordinator.admit(toolName: "apply_params")
        XCTAssertEqual(coordinator.activity.count, 1)
        XCTAssertEqual(coordinator.activity[0].summary, "apply_params")
        XCTAssertEqual(coordinator.activity[0].result, .pending)

        // The next boundary (Stop) closes it INTERRUPTED + the control
        // returns to the user + the stopped holder is remembered.
        coordinator.stop()
        XCTAssertEqual(coordinator.activity[0].result, .interrupted)
        XCTAssertEqual(coordinator.holdsControl, false)
        XCTAssertEqual(coordinator.currentState().revokedByUser, true)
        XCTAssertEqual(coordinator.stoppedHolderName, "cc")
        // F8: the Stop leaves the pinned handle IN the registry (the row
        // stays for the resume; the dismiss button is reachable).
        XCTAssertEqual(registry.count, 1, "the pinned row survives the Stop")
        XCTAssertEqual(handle.isRunning, false)

        // admit (stopped) → controlRevokedByUser.
        do {
            try await coordinator.admit(toolName: "apply_params")
            XCTFail("the stopped face must refuse")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "controlRevokedByUser")
        }

        // The SAME holder re-acquires → the SAME task id, the SAME row, the
        // activity history CONTINUES (the resume-continuity carrier).
        let resumed = try await coordinator.acquire("cc")
        XCTAssertEqual(resumed.held, true)
        XCTAssertEqual(coordinator.taskId, handle.id, "the resume keeps the id")
        XCTAssertEqual(registry.count, 1, "the resume re-registers idempotently")
        XCTAssertEqual(handle.isRunning, true)
        XCTAssertEqual(coordinator.activity.count, 1,
                       "the history continues across the Stop")
        XCTAssertEqual(coordinator.currentState().revokedByUser, false,
                       "any successful acquire clears the flag")

        // admit again → the SECOND entry opens; the FIRST entry stays
        // INTERRUPTED (the Stop closure is final — the boundary form never
        // re-closes a closed entry).
        try await coordinator.admit(toolName: "export_image")
        XCTAssertEqual(coordinator.activity.count, 2)
        XCTAssertEqual(coordinator.activity[0].result, .interrupted,
                       "the Stop closure is final")
        XCTAssertEqual(coordinator.activity[1].summary, "export_image")
        XCTAssertEqual(coordinator.activity[1].result, .pending)

        // release → the terminal Succeeded face (row pinned, gate closed,
        // the pending entry closes ok).
        let released = coordinator.release()
        XCTAssertEqual(released.held, false)
        XCTAssertEqual(coordinator.holdsControl, false)
        XCTAssertEqual(coordinator.activity[1].result, .ok)
        XCTAssertEqual(registry.count, 1, "the terminal row stays pinned")
        XCTAssertEqual(handle.isRunning, false)

        // The user dismisses → the row leaves the registry AND the
        // coordinator drops the task (the continuity is deliberately
        // broken by the user — the next acquire mints a FRESH task).
        registry.dismiss(id: handle.id)
        coordinator.dismissCard()
        XCTAssertEqual(registry.count, 0)
        XCTAssertNil(coordinator.taskId)
        XCTAssertEqual(coordinator.activity.count, 0)
        let fresh = try await coordinator.acquire("cc")
        XCTAssertEqual(fresh.held, true)
        XCTAssertNotEqual(coordinator.taskId, handle.id, "a fresh task id")
        XCTAssertEqual(registry.count, 1)
    }

    func testDifferentHolderAfterStopMintsNewTask() async throws {
        let coordinator = AgentControlCoordinator(
            acquireTimeout: .seconds(2), pollInterval: .milliseconds(20))
        _ = try await coordinator.acquire("holder-a")
        let firstId = coordinator.taskId
        coordinator.stop()
        // A different holder may acquire after the Stop (a legal fresh
        // start); the old Canceled row stays for the user's manual dismiss.
        let state = try await coordinator.acquire("holder-b")
        XCTAssertEqual(state.held, true)
        XCTAssertNotEqual(coordinator.taskId, firstId, "a new task id")
        XCTAssertEqual(coordinator.stoppedByUser == false
                       && coordinator.currentState().revokedByUser == false, true)
    }

    func testReleaseIsIdempotent() async throws {
        let coordinator = AgentControlCoordinator()
        let first = coordinator.release()
        XCTAssertEqual(first.held, false, "release without holding = no-op")
        _ = try await coordinator.acquire("cc")
        let second = coordinator.release()
        XCTAssertEqual(second.held, false)
        let third = coordinator.release()
        XCTAssertEqual(third.held, false, "still a no-op")
        XCTAssertEqual(coordinator.currentState().holder, "")
    }

    func testStopWithoutAnyTaskIsANoOp() {
        let coordinator = AgentControlCoordinator()
        coordinator.stop()
        XCTAssertEqual(coordinator.holdsControl, false)
        XCTAssertEqual(coordinator.stoppedByUser, false,
                       "no task ever existed — Stop must not arm the revoked flag")
    }

    // MARK: - The pinned/dismiss legs (the three legacy legs' negative)

    /// A minimal legacy-leg handle (rides the protocol EXTENSION default —
    /// the ImportTaskAdapter/Export/AI trio compile zero-diff, all three
    /// answer isPinned == false and finish removes them).
    private final class LegacyLegHandle: BackgroundTaskHandle {
        let id = UUID()
        var title = "legacy"
        var snapshot = BackgroundTaskSnapshot.indeterminate("working")
        var cancelled = false
        func cancel() async { cancelled = true }
    }

    func testLegacyLegsFinishRemovesWhileAgentRowStaysPinned() async throws {
        let registry = BackgroundTaskRegistry()
        let coordinator = AgentControlCoordinator()
        coordinator.attachTaskRegistry(registry)

        let legacy = LegacyLegHandle()
        registry.register(legacy)
        XCTAssertEqual(legacy.isPinned, false,
                       "the extension default — the three pre-M7-5 legs")
        _ = try await coordinator.acquire("cc")
        let agent = try XCTUnwrap(
            registry.handles.compactMap { $0 as? AgentTaskHandle }.first,
            "the agent row is up beside the legacy row")
        registry.register(agent)
        XCTAssertEqual(registry.count, 2)

        // The legacy finish route: the row leaves (finish-removes
        // unchanged by the M7-5 evolution).
        registry.finish(id: legacy.id)
        XCTAssertEqual(registry.count, 1)

        // The pinned agent row: finish-by-hand COULD remove it (the thin
        // wrapper), but the AGENT stop path never calls it — the row only
        // leaves through the user's dismiss.
        coordinator.stop()
        XCTAssertEqual(registry.count, 1, "Stop keeps the pinned row")
        registry.dismiss(id: agent.id)
        coordinator.dismissCard()
        XCTAssertEqual(registry.count, 0, "dismiss removes the pinned row")
    }

    // MARK: - The禁编辑 face manifest (the source-level merge-form scan)

    /// The 11 landing points (the Alcedo 12-face table minus the delete
    /// face — OUR semantics carry NO delete tool and NO delete route; F5).
    /// Each row: (file, the exact merge-form token that must exist).
    static let disableFaceManifest: [(file: String, token: String, why: String)] = [
        ("UI/Shell/WorkspaceHostView.swift",
         ".disabled(isReadOnly || holdsControl)",
         "face ⑪ export/yiyin topbar entries (both buttons share the form; AR-01 T1 moved the reads into the WorkspaceTopBar struct's narrow inputs — the merge form itself is unchanged)"),
        ("UI/Shell/EditorWorkspaceShellView.swift",
         ".disabled(agentControl.holdsControl)",
         "face ① the adjustment-stack host column"),
        ("UI/Shell/EditorAdjustmentStackView.swift",
         ".disabled(agentControl.holdsControl)",
         "face ② the stack container"),
        ("UI/Shell/EditorToolRailView.swift",
         ".disabled(agentControl.holdsControl)",
         "face ③ the rail panel bodies (history/versions/nodes)"),
        ("UI/Shell/Nodes/EditorNodesPanelView.swift",
         ".disabled(agentControl?.holdsControl ?? false)",
         "face ④ the node canvas"),
        ("UI/Shell/LightamerShell.swift",
         "guard !agentControl.holdsControl else { return }",
         "face ⑤ the shell's undo/redo + project command closures (the bridge enabler's live source) — repointed off the retired App struct (F0P-03 T1)"),
        ("UI/Shell/VersionsPanelView.swift",
         ".disabled(agentControl.holdsControl)",
         "face ⑥ the versions mutation/checkout container"),
        ("UI/Shell/FilmstripView.swift",
         ".disabled(agentControl.holdsControl)",
         "face ⑦ the editor image switching"),
        ("Library/ImportModeDialog.swift",
         "|| agentControl.holdsControl)",
         "face ⑧ the import confirm"),
        ("Library/Views/LibraryInspectorView.swift",
         ".disabled(agentControl.holdsControl)",
         "face ⑩ the rating (AI-analysis) command area"),
    ]

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LightamerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private static func sourceData(_ relative: String) -> Data {
        FileManager.default.contents(
            atPath: repoRoot()
                .appendingPathComponent("App/Sources/Lightamer/\(relative)")
                .path) ?? Data()
    }

    func testDisableFaceManifestLandsTheMergeForm() {
        for (file, token, why) in Self.disableFaceManifest {
            let source = String(decoding: Self.sourceData(file), as: UTF8.self)
            XCTAssertTrue(
                source.contains(token),
                "\(file) must carry the agent merge form (\(why))")
        }
    }

    func testDisableFacesNeverConditionallyUnmount() {
        // The Alcedo c7ba784 disease shape: a conditional unmount fires
        // onDisappear → the scope taps close. The `if !` + gate-name
        // composition must not exist ANYWHERE in the UI face (the guard-!
        // closure early-return form is the sanctioned closure-gate
        // spelling and does not match).
        let uiRoot = Self.repoRoot().appendingPathComponent("App/Sources/Lightamer")
        let enumerator = FileManager.default.enumerator(
            at: uiRoot, includingPropertiesForKeys: nil)
        var scanned = 0
        for case let url as URL in enumerator! where url.pathExtension == "swift" {
            let source = String(decoding: (try? Data(contentsOf: url)) ?? Data(),
                                as: UTF8.self)
            XCTAssertFalse(
                source.contains("if !agentControl"),
                "\(url.lastPathComponent) must not conditionally unmount on the gate")
            XCTAssertFalse(
                source.contains("if agentControl.holdsControl"),
                "\(url.lastPathComponent) must not conditionally mount on the gate")
            scanned += 1
        }
        XCTAssertGreaterThan(scanned, 50, "the UI face must have been scanned")
    }

    // MARK: - The scopes preservation negatives

    func testCoordinatorCarriesZeroScopeReferences() {
        let source = String(decoding: Self.sourceData("State/AgentControlCoordinator.swift"),
                            as: UTF8.self)
        for banned in ["setScopeTapEnabled", "scopesVisible", "ScopeThrottle"] {
            XCTAssertFalse(
                source.contains(banned),
                "the coordinator must not touch the \(banned) face (the "
                    + "preservation red line — the scope panel is a preserved face)")
        }
        // The disable-not-unmount structural precondition: the face scan
        // above proves the gate rides .disabled containers; this negative
        // pins the coordinator's own surface: NO scope-mutation API exists
        // to call from a control-state flip.
        XCTAssertFalse(
            source.contains("PipeCoordinator"),
            "the coordinator reads the live-edit window through the INJECTED "
                + "provider closure, never a hard PipeCoordinator reference (F-6)")
    }

    // MARK: - The hold-flag derivation + the snapshot face

    func testCurrentStateMirrorsTheControlFace() async throws {
        let coordinator = AgentControlCoordinator()
        XCTAssertEqual(coordinator.currentState(),
                       McpControlState(held: false, revokedByUser: false, holder: ""))
        _ = try await coordinator.acquire("cc")
        XCTAssertEqual(coordinator.currentState(),
                       McpControlState(held: true, revokedByUser: false, holder: "cc"))
        coordinator.stop()
        XCTAssertEqual(coordinator.currentState(),
                       McpControlState(held: false, revokedByUser: true, holder: ""))
    }

    func testCardRowTitleAndWaitingCopy() async throws {
        let coordinator = AgentControlCoordinator()
        let registry = BackgroundTaskRegistry()
        coordinator.attachTaskRegistry(registry)
        _ = try await coordinator.acquire("claude-code")
        let handle = try XCTUnwrap(registry.handles.first as? AgentTaskHandle)
        XCTAssertEqual(handle.title, "Agent · claude-code")
        XCTAssertTrue(handle.snapshot.isIndeterminate,
                      "the agent row is always indeterminate")
        XCTAssertFalse(handle.snapshot.detail.isEmpty)
        // admit updates the detail to the in-flight command.
        try await coordinator.admit(toolName: "render_preview")
        XCTAssertEqual(handle.snapshot.detail, "render_preview")
    }

    // MARK: - The post-loop rechecks (M7-6-01 obs-3; the provider-trigger
    // sequencing — deterministic interleave, never a real-poll wait)

    /// The serial poll counter the provider closures drive: the acquire
    /// wait polls it; a chosen poll number performs the interleaved action
    /// INLINE (hopping back to the MainActor) before answering false — the
    /// loop then exits through its CONDITION (never observing the flip
    /// inside the body), which is exactly the final-window shape the
    /// recheck must catch.
    private final class PollTriggerBox: @unchecked Sendable {
        private let lock = NSLock()
        private var polls = 0
        private var triggered = false
        /// The serial poll number (starts at 1).
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            polls += 1
            return polls
        }
        /// Arms the trigger exactly once — true on the arming call itself.
        func armTrigger() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if triggered { return false }
            triggered = true
            return true
        }
        /// True once the trigger has fired (the nested polls answer false).
        func isTriggered() -> Bool {
            lock.withLock { triggered }
        }
    }

    /// obs-3 variant ①: the Stop lands in the SAME poll window the editor
    /// input seals — the wait loop exits through its condition (the body
    /// never observes stoppedByUser) and the POST-LOOP recheck must refuse
    /// with the typed controlRevokedByUser (the pre-fix shape fell through
    /// into the success path and silently swallowed the Stop).
    func testAcquireRefusesRevokedWhenStopLandsInFinalPollWindow() async throws {
        let coordinator = AgentControlCoordinator(
            acquireTimeout: .seconds(5), pollInterval: .milliseconds(20))
        coordinator.configureLiveEditProbe { false }
        // A prior acquire mints the task — Stop is reachable (the guard
        // needs held or taskId) while stoppedByUser stays false at the
        // second acquire's ENTRY (release keeps the stopped flag clear).
        _ = try await coordinator.acquire("cc")
        coordinator.release()
        let box = PollTriggerBox()
        coordinator.configureLiveEditProbe { [weak coordinator] in
            guard let coordinator else { return false }
            let poll = box.next()
            if poll == 3, box.armTrigger() {
                // The user Stop lands inside this poll window; the seal
                // rides the same window — the loop exits via the condition.
                await MainActor.run { coordinator.stop() }
                return false
            }
            return true
        }
        do {
            _ = try await coordinator.acquire("cc")
            XCTFail("the in-window Stop must refuse the acquire")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "controlRevokedByUser")
        }
        XCTAssertEqual(coordinator.holdsControl, false)
        XCTAssertEqual(coordinator.currentState().revokedByUser, true,
                       "the Stop stays armed — the agent must re-acquire")
    }

    /// obs-3 variant ②: a competing holder completes ITS acquire inside
    /// the waiter's poll window (the entry busy pre-check saw held ==
    /// false) — the waiter's post-loop recheck must refuse with the typed
    /// controlBusy (the pre-fix shape granted a DOUBLE HOLD).
    func testAcquireRefusesBusyWhenCompetingHolderWinsInWindow() async throws {
        let coordinator = AgentControlCoordinator(
            acquireTimeout: .seconds(5), pollInterval: .milliseconds(20))
        coordinator.configureLiveEditProbe { false }
        let box = PollTriggerBox()
        coordinator.configureLiveEditProbe { [weak coordinator] in
            guard let coordinator else { return false }
            let poll = box.next()
            if poll == 3, box.armTrigger() {
                // The competing holder wins INSIDE this poll window (its
                // own nested polls answer false through the armed flag).
                _ = try? await coordinator.acquire("winner")
                return false
            }
            return !box.isTriggered()
        }
        do {
            _ = try await coordinator.acquire("waiter")
            XCTFail("the post-loop recheck must refuse the double hold")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "controlBusy")
            XCTAssertTrue(error.message.contains("winner"),
                          "the busy face carries the winning holder")
        }
        XCTAssertEqual(coordinator.holdsControl, true)
        XCTAssertEqual(coordinator.currentState().holder, "winner",
                       "exactly one holder — the waiter lost cleanly")
    }

    /// obs-3 negative (the review-B1 pathology guard): the entry-stopped
    /// face is the TURN-03 resume semantics — the same-holder re-acquire
    /// after a Stop must still SUCCEED (an unconditional stoppedByUser
    /// refusal in the recheck would strand the agent permanently).
    func testAcquireAfterStopStillResumesForSameHolder() async throws {
        let coordinator = AgentControlCoordinator(
            acquireTimeout: .seconds(2), pollInterval: .milliseconds(20))
        coordinator.configureLiveEditProbe { false }
        _ = try await coordinator.acquire("cc")
        let id = coordinator.taskId
        coordinator.stop()
        XCTAssertEqual(coordinator.currentState().revokedByUser, true)
        let resumed = try await coordinator.acquire("cc")
        XCTAssertEqual(resumed.held, true)
        XCTAssertEqual(coordinator.taskId, id, "the resume keeps the task id")
        XCTAssertEqual(coordinator.currentState().revokedByUser, false,
                       "the successful resume clears the stopped flag")
    }
}
