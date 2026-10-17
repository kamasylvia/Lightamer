import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-4 T1 (MCP-10 launcher): the template placeholder discipline, the
// app-side serial gate, the launch-failure face and the probe retirement.
//
// T2 adds the sentinel trio (injection verbatim end-to-end, serial in
// flight, termination-only-our-own) and the log-buffer faces.
//
// The sentinel files live in NSTemporaryDirectory (per-process tmp — the
// L009/fixture discipline: nothing lands on the repo volume).
// ─────────────────────────────────────────────────────────────────────────────

final class McpLauncherTests: XCTestCase {

    // MARK: - Template rendering (the placeholder discipline)

    /// {{LIGHTAMER_MCP}} expands to the endpoint file path VERBATIM (paths
    /// with spaces and quotes are data — the placeholder is replaced as a
    /// whole token, no shell interpretation at render time).
    func testEndpointPlaceholderReplacesVerbatim() {
        let path = "/tmp/weird dir/mcp-end point.json"
        let rendered = McpLauncherTemplate.render(
            command: "agent --endpoint {{LIGHTAMER_MCP}}",
            prompt: nil, endpointPath: path)
        XCTAssertEqual(rendered.command, "agent --endpoint \(path)")
        XCTAssertFalse(rendered.hasPromptPlaceholder)
        XCTAssertFalse(rendered.promptInlined)
    }

    /// {{PROMPT}} inlines as a single-quoted word; the escape spelling is
    /// the shell single-quote wrapping (`'` → `'\''`).
    func testPromptPlaceholderEscapesSingleQuotes() {
        let rendered = McpLauncherTemplate.render(
            command: "agent {{PROMPT}}", prompt: "it's alive",
            endpointPath: "/e.json")
        XCTAssertEqual(rendered.command, "agent 'it'\\''s alive'")
        XCTAssertTrue(rendered.hasPromptPlaceholder)
        XCTAssertTrue(rendered.promptInlined)
    }

    /// An empty/whitespace prompt collapses to `''` (an empty shell word)
    /// and reports NOT inlined — the honest hint face (§RQ-14-12).
    func testEmptyPromptCollapsesToEmptyShellWord() {
        for prompt in [nil, "", "   \n "] {
            let rendered = McpLauncherTemplate.render(
                command: "agent {{PROMPT}}", prompt: prompt, endpointPath: "/e.json")
            XCTAssertEqual(rendered.command, "agent ''")
            XCTAssertTrue(rendered.hasPromptPlaceholder)
            XCTAssertFalse(rendered.promptInlined)
        }
    }

    /// A template with no placeholders runs unchanged (the backward
    /// compatibility face, D-14-CONTEXT-10⑤).
    func testTemplateWithoutPlaceholdersRunsUnchanged() {
        let rendered = McpLauncherTemplate.render(
            command: "agent --plain", prompt: "unused", endpointPath: "/e.json")
        XCTAssertEqual(rendered.command, "agent --plain")
        XCTAssertFalse(rendered.hasPromptPlaceholder)
        XCTAssertFalse(rendered.promptInlined)
    }

    // MARK: - The zsh round trip (meta characters arrive as DATA)

    /// The full escape round trip through REAL zsh: a prompt full of shell
    /// meta characters (single quotes, backticks, `$()`, `$VAR`, newlines,
    /// double quotes) must reach the child byte-for-byte — the sentinel
    /// file written by the command carries exactly the prompt text.
    func testPromptMetaCharactersSurviveZshRoundTrip() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sentinel = dir.appendingPathComponent("sentinel.txt")

        let prompt = """
        pick 'the best' shots; run `whoami` and $(rm -rf /dry/run 2>/dev/null); \
        $HOME ${HOME} "quoted" | pipe > redirect; it's meta
        """
        let rendered = McpLauncherTemplate.render(
            command: "printf '%s' {{PROMPT}} > '\(sentinel.path)'",
            prompt: prompt, endpointPath: "/e.json")

        let launcher = McpLauncher()
        let pid = try launcher.start(renderedCommand: rendered.command)
        let exited = try await Self.waitForExit(launcher, pid: pid, timeout: 15)
        XCTAssertTrue(exited, "the zsh child must exit on its own")
        let written = try String(contentsOf: sentinel, encoding: .utf8)
        XCTAssertEqual(written, prompt, "the prompt text must arrive byte-for-byte")
    }

    /// The environment injection route: `LIGHTAMER_MCP` reaches the child
    /// even when the template itself never mentions the placeholder (the
    /// discovery path rides BOTH channels by design).
    func testEndpointPathRidesTheEnvironment() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sentinel = dir.appendingPathComponent("env.txt")

        let launcher = McpLauncher()
        let pid = try launcher.start(
            renderedCommand: "printf '%s' \"$LIGHTAMER_MCP\" > '\(sentinel.path)'",
            environment: ["LIGHTAMER_MCP": "/discovered/endpoint.json"])
        _ = try await Self.waitForExit(launcher, pid: pid, timeout: 15)
        let written = try String(contentsOf: sentinel, encoding: .utf8)
        XCTAssertEqual(written, "/discovered/endpoint.json")
    }

    // MARK: - The serial gate + the launch-failure face

    /// A second start while one agent is in flight is REFUSED
    /// (`alreadyRunning`) — the app-side serial: at most ONE agent process
    /// (research item A precondition). After the child exits, the slot
    /// frees and a new start succeeds.
    func testSerialGateRejectsSecondStartWhileInFlight() async throws {
        let launcher = McpLauncher()
        let first = try launcher.start(renderedCommand: "sleep 30")
        defer { launcher.stop() }
        XCTAssertEqual(launcher.runningPID, first, "the child is registered")

        XCTAssertThrowsError(
            try launcher.start(renderedCommand: "sleep 30")
        ) { error in
            XCTAssertEqual(
                error as? McpLauncher.LaunchFailure, .alreadyRunning,
                "the second start must hit the serial gate")
        }

        // The registered child is still the FIRST one (the refused start
        // must not have replaced the registration).
        XCTAssertEqual(launcher.runningPID, first)

        launcher.stop()
        try await Self.waitForGone(launcher, pid: first, timeout: 10)
        XCTAssertNil(launcher.runningPID, "the slot frees on exit")

        let third = try launcher.start(renderedCommand: "true")
        XCTAssertEqual(launcher.runningPID, third)
        _ = try await Self.waitForExit(launcher, pid: third, timeout: 10)
    }

    /// A spawn whose executable does not exist throws `launchFailed`, the
    /// registration stays EMPTY (the serial slot is free again) — the face
    /// the panel maps to the toast + log line (§RQ-14-12).
    func testMissingExecutableFailsLaunchAndKeepsSlotFree() {
        let launcher = McpLauncher()
        XCTAssertThrowsError(
            try launcher.start(
                renderedCommand: "echo hi",
                shellPath: "/nonexistent/zsh-should-never-exist")
        ) { error in
            guard case McpLauncher.LaunchFailure.launchFailed = error else {
                return XCTFail("expected launchFailed, got \(error)")
            }
        }
        XCTAssertNil(launcher.runningPID, "no child registered on a failed spawn")
        XCTAssertFalse(launcher.isRunning)
        // The serial slot is demonstrably free.
        XCTAssertNoThrow(try launcher.start(renderedCommand: "true"))
    }

    /// A nonzero child exit surfaces through `onExit` with its status (the
    /// red exit-code face) — 127 is the shell's "command not found" code,
    /// the production shape of a missing agent binary.
    func testNonZeroExitSurfacesThroughOnExit() async throws {
        let launcher = McpLauncher()
        let box = ExitBox()
        launcher.onExit = { status in box.set(status) }
        let pid = try launcher.start(renderedCommand: "exit 127")
        let deadline = Date().addingTimeInterval(15)
        while box.value == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(box.value, 127, "the exit status rides onExit")
        _ = try await Self.waitForGone(launcher, pid: pid, timeout: 10)
    }

    // MARK: - Probe retirement (Plan 14-4 T1, launcher-plan angle)

    /// The tool face contains no probe residue: a bare kernel is empty and
    /// the assembled face carries neither probe name (the full closed-set
    /// snapshot lives in McpRegistrySnapshotTests/McpFinalSnapshotTests).
    func testProbeFaceRetiredFromEveryRegistry() async throws {
        let bare = await McpServerController.makeRegistry()
        let bareNames = await bare.descriptors().map(\.name)
        XCTAssertTrue(bareNames.isEmpty, "bare registry must be empty: \(bareNames)")

        let assembled = await McpServerController.makeRegistry(
            editing: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }),
            culling: McpServerController.makeCullingContext(session: { nil }))
        let names = await assembled.descriptors().map(\.name)
        XCTAssertEqual(names.count, 23, "the closed face (M7-4 copy/paste joined): \(names.sorted())")
        XCTAssertFalse(names.contains("ping"))
        XCTAssertFalse(names.contains("count_images"))
    }

    // MARK: - Bounded-wait helpers (poll-based; no unbounded blocking)

    /// Waits until the registered child exited; returns `true` when it did
    /// within the timeout.
    private static func waitForExit(
        _ launcher: McpLauncher, pid: Int32, timeout: TimeInterval
    ) async throws -> Bool {
        try await waitUntil(timeout: timeout) { !launcher.isRunning }
    }

    /// Waits until the registration slot is empty (the termination handler
    /// ran — the process object was reaped, no zombie).
    private static func waitForGone(
        _ launcher: McpLauncher, pid: Int32, timeout: TimeInterval
    ) async throws -> Bool {
        try await waitUntil(timeout: timeout) { launcher.runningPID != pid }
    }

    private static func waitUntil(
        timeout: TimeInterval, _ condition: @Sendable () -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// A tiny thread-safe exit-status box (the onExit callback's capture).
    private final class ExitBox: @unchecked Sendable {
        private let lock = NSLock()
        private var status: Int32?
        var value: Int32? {
            lock.lock(); defer { lock.unlock() }
            return status
        }
        func set(_ status: Int32) {
            lock.lock()
            self.status = status
            lock.unlock()
        }
    }
}
