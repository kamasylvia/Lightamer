import Foundation
import LightamerCore
import LightamerIOP
import MCP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// McpControlToolsetTests (Plan M7-5-01 T6) — the FIFTH domain's snapshot
// layer + the turn-taking fixture legs (ROADMAP §M7-5 acceptance ①④):
//
//   • the domain snapshot layer: the three control tools verbatim + the
//     32 分账 + the whitelist negative + the annotation judgments
//     (control_get readOnlyHint; the three carry NO destructive hint and
//     register WITHOUT the admit-gate flag);
//   • the admit 三拒面 (D-M7-5-1): not-held → controlNotHeld / stopped →
//     controlRevokedByUser / a different live holder busy → controlBusy
//     carrying the holder;
//   • the requiresControl candidate set = EXACTLY the 13 names (the
//     behavioral judgment: admit armed → exactly the 13 die with
//     controlNotHeld; the 16 face-out tools answer their OWN errors — the
//     gate never fires for them; the control trio never gates);
//   • the acquire 三态 (D-M7-5-7, injected short windows — NEVER the 10s
//     production tier): the wait-for-seal leg (the three-window probe true
//     → suspends → seals → granted), the timeout leg (probe stuck true →
//     controlBusy carrying the unsealed semantics), the Stop-interrupt leg
//     (a stop while waiting → the acquire answers revoked quickly);
//   • the headless ALWAYS-HELD negative (TURN-04): the constant face + the
//     admit-nil pass-through (a requiresControl tool answers straight into
//     the handler when no admit is installed) + the read-only host arm
//     (the control face answers through a false writer gate; the write
//     face still dies serverReadOnly FIRST — the writer gate precedes);
//   • get_state's control.agent truth leg (the nil leg rides
//     McpSearchStateToolsetTests' contract test — F4).
//
// The coordinator state-machine full sequences live in
// AgentControlCoordinatorTests — this file owns the MCP-face judgments.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class McpControlToolsetTests: XCTestCase {

    // MARK: - The frozen domain table (registration source verbatim)

    /// Schemas byte-equal ControlToolset.swift; the descriptions live at
    /// the registration site + the zh catalog.
    static let controlTools: [McpToolDescriptor] = [
        McpToolDescriptor(
            name: "control_acquire",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"holder_name":{"type":"string","description":"Session label for this holder (default agent)"}}}"#),
        McpToolDescriptor(
            name: "control_get",
            description: "snapshot",
            inputSchemaJSON: #"{"type":"object","properties":{}}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "control_release",
            description: "snapshot",
            inputSchemaJSON: #"{"type":"object","properties":{}}"#),
    ]

    /// The requiresControl candidate set (D-M7-5-3 — the EXACT 13).
    static let controlCandidateTools: Set<String> = [
        "load_image", "apply_params", "paste_adjustments", "export_image",
        "set_rating", "set_flag", "set_color_label", "append_note",
        "set_keywords", "apply_preset", "match_color", "project_open",
        "project_create",
    ]

    /// The union registry with ONLY the control face (the domain snapshot
    /// layer) — the all-nil fixture context (registration consumes no
    /// provider).
    private func makeControlOnlyRegistry() async -> McpToolRegistry {
        await McpServerController.makeRegistry(control: McpControlContext())
    }

    /// The full 32-face union (the admit judgment needs every domain).
    private func makeUnionRegistry() async -> McpToolRegistry {
        await McpServerController.makeRegistry(
            editing: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }),
            culling: McpServerController.makeCullingContext(session: { nil }),
            searchState: McpSearchStateContext(),
            project: McpProjectContext(),
            control: McpControlContext())
    }

    private static func callJSON(
        _ registry: McpToolRegistry, name: String,
        arguments: [String: McpJSON] = [:], file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [String: Any] {
        let output = try await registry.call(name: name, arguments: arguments)
        guard case .text(let text) = output.content.first else {
            XCTFail("expected a text payload", file: file, line: line)
            return [:]
        }
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8))
                as? [String: Any],
            "the payload must be an object", file: file, line: line)
    }

    // MARK: - The domain snapshot layer

    func testControlDomainSnapshotVerbatim() async throws {
        let registry = await makeControlOnlyRegistry()
        await McpRegistrySnapshotTests.assertSnapshot(
            registry: registry, expected: Self.controlTools)
        let descriptors = await registry.descriptors()
        XCTAssertEqual(descriptors.map(\.name), [
            "control_acquire", "control_get", "control_release",
        ], "the domain count is 3 (the 32 分账's fifth row)")
    }

    func testControlAnnotationsAndNoAdmitFlag() async throws {
        // control_get carries the read-only hint; the mutating pair carries
        // nothing (control transfer is not a state change and not
        // destructive); NONE of the three registers into the admit
        // candidate set (changing the control IS the control).
        let annotations: [String: (Bool?, Bool?)] = [
            "control_acquire": (nil, nil),
            "control_get": (true, nil),
            "control_release": (nil, nil),
        ]
        for (name, (readOnly, destructive)) in annotations {
            let registry = await makeControlOnlyRegistry()
            let descriptors = await registry.descriptors()
            let descriptor = try XCTUnwrap(
                descriptors.first { $0.name == name })
            XCTAssertEqual(descriptor.readOnlyHint, readOnly, name)
            XCTAssertEqual(descriptor.destructiveHint, destructive, name)
            do {
                _ = try await registry.call(name: name, arguments: [:])
                XCTFail("\(name) has no provider here — the honest not-assembled error")
            } catch let error as McpToolError {
                XCTAssertEqual(error.code, "internalError", name)
            }
        }
    }

    func testControlWhitelistNegative() async throws {
        let registry = await makeControlOnlyRegistry()
        do {
            _ = try await registry.call(name: "control_steal", arguments: [:])
            XCTFail("no fourth control tool exists")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "internalError")
            XCTAssertTrue(error.message.contains("unknownTool"))
        }
    }

    // MARK: - The union 32 分账 (the fifth row) + the zh catalog keys

    func testUnionCarriesTheControlDomain() async throws {
        let registry = await makeUnionRegistry()
        let names = await registry.descriptors().map(\.name)
        XCTAssertEqual(names.count, 33, "the union is the 33-face (LUMEN-C T3)")
        for tool in Self.controlTools {
            XCTAssertTrue(names.contains(tool.name), tool.name)
        }
    }

    func testControlDescriptionsCarryZhCatalogKeys() async throws {
        let zhPath = try XCTUnwrap(
            Bundle.main.path(
                forResource: "Localizable", ofType: "strings",
                inDirectory: nil, forLocalization: "zh"))
        let zh = try XCTUnwrap(
            NSDictionary(contentsOfFile: zhPath) as? [String: String])
        for (tool, key) in [
            "control_acquire": "mcp_tool_desc_control_acquire",
            "control_release": "mcp_tool_desc_control_release",
            "control_get": "mcp_tool_desc_control_get",
        ] {
            let value = try XCTUnwrap(zh[key], "missing zh key \(key)")
            XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty)
            let registry = await makeControlOnlyRegistry()
            let descriptors = await registry.descriptors()
            let descriptor = try XCTUnwrap(
                descriptors.first { $0.name == tool })
            XCTAssertFalse(descriptor.description.isEmpty, tool)
        }
    }

    // MARK: - The requiresControl candidate set = EXACTLY 13 (behavioral)

    func testRequiresControlCandidateSetIsExactlyThirteen() async throws {
        let registry = await makeUnionRegistry()
        await registry.setControlAdmit { name in
            throw McpToolError.controlNotHeld("admit-fired:\(name)")
        }
        // The 13 candidates: the admit gate fires BEFORE any handler face.
        for name in Self.controlCandidateTools.sorted() {
            do {
                _ = try await registry.call(name: name, arguments: [:])
                XCTFail("\(name) must die at the admit gate")
            } catch let error as McpToolError {
                XCTAssertTrue(
                    error.message.hasPrefix("admit-fired:"),
                    "\(name) must die at the ADMIT gate, not a handler face: "
                        + "\(error.code) \(error.message)")
            }
        }
        // The 16 face-out tools (29 − 13 of the pre-M7-5 face) answer their
        // OWN errors — the gate never fires for them.
        let faceOut = Set([
            "copy_adjustments", "render_preview", "diff_presets",
            "list_iops", "list_luts", "list_photos", "list_presets",
            "list_bursts", "list_versions",
            "get_thumbnails", "get_contact_sheet", "get_detail_crop",
            "get_face_regions", "get_history", "get_state",
            "search_photos",
        ])
        XCTAssertEqual(faceOut.count, 16, "F7: the face-out set is 16")
        for name in faceOut.sorted() {
            // The read-only faces answer empty args SUCCESSFULLY
            // (list_iops/list_luts/get_state need no arguments) — the only
            // judgment: whatever answer comes back, it never rode the
            // admit gate.
            do {
                _ = try await registry.call(name: name, arguments: [:])
            } catch let error as McpToolError {
                XCTAssertNotEqual(
                    error.code, "controlNotHeld",
                    "\(name) must NOT ride the admit gate")
            }
        }
        // The control trio rides NO gate either (nil providers here → the
        // honest internalError, never the admit error).
        for name in ["control_acquire", "control_release", "control_get"] {
            do {
                _ = try await registry.call(name: name, arguments: [:])
                XCTFail("no provider → the honest error")
            } catch let error as McpToolError {
                XCTAssertNotEqual(error.code, "controlNotHeld", name)
            }
        }
    }

    // MARK: - The admit 三拒面 (D-M7-5-1; the coordinator-backed registry)

    /// Builds the coordinator-backed control face the GUI arm assembles,
    /// with the admit seam installed — the production shape in-process.
    private func makeAdmitArmedRegistry(
        coordinator: AgentControlCoordinator
    ) async -> McpToolRegistry {
        let registry = await makeUnionRegistry()
        await registry.setControlAdmit { [coordinator] name in
            try await coordinator.admit(toolName: name)
        }
        return registry
    }

    func testAdmitRefusalsThreeFaces() async throws {
        let coordinator = AgentControlCoordinator()
        let registry = await makeAdmitArmedRegistry(coordinator: coordinator)

        // ① Never held → controlNotHeld.
        do {
            _ = try await registry.call(name: "apply_params", arguments: [:])
            XCTFail("the not-held face must refuse")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "controlNotHeld")
            XCTAssertTrue(error.message.contains("control_acquire"))
        }

        // ② The user stopped the agent → controlRevokedByUser.
        _ = try await coordinator.acquire("cc")
        coordinator.stop()
        XCTAssertEqual(coordinator.currentState().revokedByUser, true)
        do {
            _ = try await registry.call(name: "apply_params", arguments: [:])
            XCTFail("the stopped face must refuse")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "controlRevokedByUser")
        }

        // ③ Held → the admit passes into the handler (the empty-args
        // invalidParams face proves the handler RAN — the gate passed).
        _ = try await coordinator.acquire("cc")
        do {
            _ = try await registry.call(name: "apply_params", arguments: [:])
            XCTFail("empty args must die in the handler (the gate passed)")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams", error.message)
        }
        // The held face opened an activity entry (the boundary form).
        XCTAssertEqual(coordinator.activity.last?.summary, "apply_params")
        XCTAssertEqual(coordinator.activity.last?.result, .pending)
    }

    func testAdmitDifferentHolderBusyCarriesHolder() async throws {
        let coordinator = AgentControlCoordinator()
        _ = try await coordinator.acquire("holder-a")
        do {
            _ = try await coordinator.acquire("holder-b")
            XCTFail("the busy face must refuse")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "controlBusy")
            XCTAssertTrue(
                error.message.contains("holder-a"),
                "the busy message carries the holder: \(error.message)")
        }
    }

    // MARK: - The acquire 三态 (D-M7-5-7; injected short windows)

    /// The probe stub (the three-window OR stand-in — no GUI dependency).
    private final class ProbeStub: @unchecked Sendable {
        private let lock = NSLock()
        private var active = false
        var value: Bool {
            get { lock.withLock { active } }
            set { lock.withLock { active = newValue } }
        }
    }

    /// The completion probe: Task has no isCompleted member and awaiting
    /// `task.value` inside a task group cannot be cancelled out of (the
    /// group's exit awaits it — a "race" would block on the acquire), so
    /// the acquire body marks a Sendable box and the sleep-based poll reads
    /// it.
    private final class DoneBox: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func mark() { lock.withLock { done = true } }
        var finished: Bool { lock.withLock { done } }
    }

    func testAcquireWaitsForSealThenGrants() async throws {
        let probe = ProbeStub()
        probe.value = true
        let coordinator = AgentControlCoordinator(
            acquireTimeout: .seconds(5), pollInterval: .milliseconds(20))
        coordinator.configureLiveEditProbe { [probe] in probe.value }
        // The wait leg: the acquire suspends while the probe holds true,
        // then grants the moment it seals (the D-H1/DRT/Film windows are
        // three providers of the SAME probe shape — one stub covers the
        // OR semantics).
        let box = DoneBox()
        let task = Task {
            let state = try await coordinator.acquire("cc")
            box.mark()
            return state
        }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(box.finished, "the unsealed input suspends acquire")
        probe.value = false
        let state = try await task.value
        XCTAssertEqual(state.held, true)
        XCTAssertEqual(state.holder, "cc")
    }

    func testAcquireTimeoutAnswersBusyWithUnsealedSemantics() async throws {
        let probe = ProbeStub()
        probe.value = true
        let coordinator = AgentControlCoordinator(
            acquireTimeout: .milliseconds(200), pollInterval: .milliseconds(20))
        coordinator.configureLiveEditProbe { [probe] in probe.value }
        let started = Date()
        do {
            _ = try await coordinator.acquire("cc")
            XCTFail("the stuck-unsealed face must time out busy")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "controlBusy")
            XCTAssertTrue(
                error.message.contains("not sealed"),
                "the unsealed semantics ride the message: \(error.message)")
        }
        XCTAssertTrue(
            Date().timeIntervalSince(started) < 2,
            "the injected short window governs — never the 10s production tier")
        XCTAssertEqual(coordinator.holdsControl, false)
    }

    func testAcquireStopInterruptAnswersRevokedQuickly() async throws {
        let probe = ProbeStub()
        probe.value = false
        let coordinator = AgentControlCoordinator(
            acquireTimeout: .seconds(5), pollInterval: .milliseconds(20))
        coordinator.configureLiveEditProbe { [probe] in probe.value }
        // A task already exists (first acquire + release) — the card row is
        // up, so Stop is reachable while a re-acquire waits.
        _ = try await coordinator.acquire("cc")
        coordinator.release()
        probe.value = true
        let box = DoneBox()
        let waiter = Task {
            let state = try await coordinator.acquire("cc")
            box.mark()
            return state
        }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(box.finished, "the re-acquire waits on the seal")
        coordinator.stop()
        let waitStarted = Date()
        do {
            _ = try await waiter.value
            XCTFail("the interrupted wait must answer revoked")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "controlRevokedByUser")
        }
        XCTAssertTrue(
            Date().timeIntervalSince(waitStarted) < 1,
            "the stop interrupts the wait quickly (no full-timeout ride)")
        XCTAssertEqual(coordinator.holdsControl, false)
        XCTAssertEqual(coordinator.currentState().revokedByUser, true)
    }

    // MARK: - The headless ALWAYS-HELD negative (TURN-04)

    func testHeadlessControlContextConstantFace() async throws {
        let context = McpServerController.makeHeadlessControlContext()
        let acquired = try await context.acquire?("anyone")
        XCTAssertEqual(acquired, McpControlState.headlessConstant)
        let released = try await context.release?()
        XCTAssertEqual(released, McpControlState.headlessConstant)
        let read = await context.state?()
        XCTAssertEqual(read, McpControlState.headlessConstant)
    }

    func testHeadlessAdmitNilWriteToolsAnswerStraightIntoHandler() async throws {
        // The stub handler records the call — a requiresControl tool with
        // NO admit installed passes straight through (the always-admit arm;
        // the writerCheck-nil same shape).
        let registry = McpToolRegistry()
        final class CallBox: @unchecked Sendable {
            private let lock = NSLock()
            private var calls = 0
            func bump() { lock.withLock { calls += 1 } }
            var count: Int { lock.withLock { calls } }
        }
        let box = CallBox()
        await registry.register(
            McpToolDescriptor(
                name: "stub_state_changer", description: "test",
                inputSchemaJSON: #"{"type":"object","properties":{}}"#),
            requiresControl: true,
            handler: { _ in box.bump(); return .text("ran") })
        let output = try await registry.call(name: "stub_state_changer", arguments: [:])
        XCTAssertEqual(box.count, 1, "no admit = pass-through")
        XCTAssertEqual(output.content.first,
                       .text("ran"))
        // The control_acquire face on the headless assembly answers the
        // constant (the always-held truth).
        let headless = await McpServerController.makeRegistry(
            editing: nil, control: McpServerController.makeHeadlessControlContext())
        let state = try await Self.callJSON(
            headless, name: "control_acquire",
            arguments: ["holder_name": .string("cc")])
        XCTAssertEqual(state["held"] as? Bool, true)
        XCTAssertEqual(state["revokedByUser"] as? Bool, false)
        XCTAssertEqual(state["holder"] as? String, "")
    }

    func testReadOnlyHostArmControlFaceRegisteredAndWriteGatePrecedes() async throws {
        // The read-only arm's in-process equivalent: the control face rides
        // the SAME registry while the writer gate answers false — the
        // control tools answer, the write face dies serverReadOnly FIRST
        // (the gate order: writer → control → handler), even with the
        // admit seam armed.
        let registry = await McpServerController.makeRegistry(
            editing: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }),
            control: McpServerController.makeHeadlessControlContext())
        await registry.setWriterCheck { false }
        await registry.setControlAdmit { _ in
            throw McpToolError.controlNotHeld("admit-armed")
        }
        // The control face answers through the false writer gate (the
        // always-held constant — the read-only host's honest face).
        let state = try await Self.callJSON(registry, name: "control_get", arguments: [:])
        XCTAssertEqual(state["held"] as? Bool, true)
        XCTAssertEqual(state["holder"] as? String, "")
        // The write face dies at the WRITER gate (serverReadOnly), never
        // reaching the admit seam (the serverReadOnly error carries the
        // connect-guidance copy — a substring judgment).
        do {
            _ = try await registry.call(name: "apply_params", arguments: [:])
            XCTFail("the read-only face must refuse the write face")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "serverReadOnly")
        }
    }

    // MARK: - get_state's control.agent truth leg (the nil leg = the
    // McpSearchStateToolsetTests contract)

    func testGetStateAgentTruthProviderSubObject() async throws {
        let registry = await McpServerController.makeRegistry(
            searchState: McpSearchStateContext(
                agentControl: {
                    McpControlState(held: true, revokedByUser: false, holder: "cc")
                }))
        let payload = try await Self.callJSON(registry, name: "get_state", arguments: [:])
        let control = try XCTUnwrap(payload["control"] as? [String: Any])
        let agent = try XCTUnwrap(control["agent"] as? [String: Any])
        XCTAssertEqual(agent["held"] as? Bool, true)
        XCTAssertEqual(agent["revokedByUser"] as? Bool, false)
        XCTAssertEqual(agent["holder"] as? String, "cc")
    }
}
