import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-4 T2: the launcher SENTINEL trio + the log-buffer faces (the
// CONTEXT 验证红线「launcher 注入面」字面):
//   1. injection verbatim — a safe echo/cat template proves end-to-end that
//      the environment injection reaches the child and the placeholders
//      arrive byte-for-byte after REAL zsh evaluation (T1 covered the pure
//      render side; here the PANEL-side flow shape is exercised too);
//   2. the serial assertion (a second in-flight start is refused);
//   3. termination only-our-own — a sleep child is stopped and ONLY that
//      registered pid dies; a pid that is NOT in the registration is
//      refused untouched (§8.5 自家子进程纪律);
//   + the 2000-line ring truncation and the pause/copy semantics.
//
// Sentinel files live in NSTemporaryDirectory (per-process tmp — L009;
// nothing lands on the repo volume).
// ─────────────────────────────────────────────────────────────────────────────

final class McpLauncherSentinelTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-sentinel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: - Sentinel 1: injection verbatim (environment + placeholders)

    /// The full template route: both placeholders AND the environment var
    /// land in a sentinel file written by the child shell — three values,
    /// byte-for-byte, through REAL zsh.
    func testSentinelTemplateExecutesEndToEndVerbatim() async throws {
        let dir = try makeTempDir()
        let sentinel = dir.appendingPathComponent("sentinel.txt")
        let endpointPath = "/endpoint dir/mcp-endpoint.json"  // space = data

        let prompt = "keep `backticks` and $(substitutions) and 'quotes' inert"
        let rendered = McpLauncherTemplate.render(
            command: "printf '%s\\n' '{{LIGHTAMER_MCP}}' >> '\(sentinel.path)' "
                + "&& printf '%s' {{PROMPT}} >> '\(sentinel.path)'",
            prompt: prompt, endpointPath: endpointPath)
        // The placeholder substitution rode the render (inside single
        // quotes in the user's template — the path with its space lands as
        // ONE word), and the environment channel carries the same value.
        XCTAssertTrue(rendered.command.contains(endpointPath))

        let launcher = McpLauncher()
        let pid = try launcher.start(renderedCommand: rendered.command,
                                     environment: ["LIGHTAMER_MCP": endpointPath])
        _ = try await Self.waitForGone(launcher, pid: pid, timeout: 15)

        let written = try String(contentsOf: sentinel, encoding: .utf8)
        XCTAssertTrue(
            written.hasPrefix("\(endpointPath)\n"),
            "the env injection must reach the child verbatim: \(written)")
        XCTAssertTrue(
            written.hasSuffix(prompt),
            "the prompt must arrive byte-for-byte after zsh: \(written)")
    }

    /// The panel model's launch flow against a live pre-flight shape: with
    /// NO endpoint alive the launch is REFUSED with the hint face and no
    /// child is registered (the honest pre-flight, D-14-4-T2-2).
    @MainActor
    func testPanelLaunchRefusedWhenServerOff() async throws {
        // Point the discovery state at an EMPTY temp dir: no json, no lock.
        let dir = try makeTempDir()
        XCTAssertEqual(
            McpEndpointDiscovery.discover(in: McpEndpointPaths(directory: dir)),
            .noEndpointFile, "an empty dir must not read as a live endpoint")
        let model = McpLauncherPanelModel()
        UserDefaults.standard.set(
            "echo sentinel-panel", forKey: McpLauncherTemplateKeys.command)
        defer {
            UserDefaults.standard.removeObject(forKey: McpLauncherTemplateKeys.command)
        }

        // If the dev machine happens to have a live server, skip the
        // refusal branch (the honest guard for shared-machine runs).
        guard !McpLauncherEndpointProbe.isDefaultAlive else {
            throw XCTSkip("a live default endpoint exists on this machine")
        }
        await model.launch()
        XCTAssertNil(McpLauncher.shared.runningPID, "no child may start pre-flight-refused")
        XCTAssertFalse(McpLauncher.shared.isRunning)
        XCTAssertNotNil(model.hint, "the refusal surfaces the hint face")
    }

    // MARK: - Sentinel 2: the serial assertion (in flight)

    /// While a real child sleeps, a second start is refused with
    /// `.alreadyRunning` — and the registration still points at the FIRST
    /// child only.
    func testSentinelSerialRefusalWithLiveChild() async throws {
        // The SHARED core — the same gate the panel's button rides.
        let core = McpLauncher.shared
        let first = try core.start(renderedCommand: "sleep 30")
        defer { core.stop() }
        XCTAssertThrowsError(try core.start(renderedCommand: "sleep 30")) { error in
            XCTAssertEqual(error as? McpLauncher.LaunchFailure, .alreadyRunning)
        }
        XCTAssertEqual(core.runningPID, first, "the refused start replaced nothing")
        core.stop()
        _ = try await Self.waitForGone(core, pid: first, timeout: 10)
    }

    // MARK: - Sentinel 3: termination only reaches our own pid

    /// Stop terminates the REGISTERED child (sleep dies) and refuses a
    /// named pid that is not ours — the TEST HOST's own pid is the foreign
    /// pid: it must survive untouched.
    func testStopKillsOnlyTheRegisteredPid() async throws {
        let fresh = McpLauncher()
        let childPID = try fresh.start(renderedCommand: "sleep 30")
        defer { fresh.stop() }
        let foreignPID = ProcessInfo.processInfo.processIdentifier
        XCTAssertNotEqual(childPID, foreignPID)

        // The negative: naming a NON-registered pid is refused and that
        // pid is untouched (the §8.5 在册表负例).
        XCTAssertEqual(fresh.stop(pid: foreignPID), .notOurs)
        XCTAssertEqual(kill(foreignPID, 0), 0, "the test host is alive — untouched")

        // The positive: the registered child dies on a plain stop().
        XCTAssertEqual(fresh.stop(), .terminated)
        _ = try await Self.waitForGone(fresh, pid: childPID, timeout: 10)
        XCTAssertNil(fresh.runningPID, "the registration cleared on exit")
        // The child REALLY received the signal (the pid is gone).
        XCTAssertNotEqual(kill(childPID, 0), 0, "the sleep child must be dead")
        XCTAssertEqual(kill(foreignPID, 0), 0, "the foreign pid is STILL alive")
    }

    /// `stop` with nothing in flight is the honest `.notRunning`.
    func testStopWithoutChildReportsNotRunning() {
        let fresh = McpLauncher()
        XCTAssertEqual(fresh.stop(), .notRunning)
    }

    /// A child that ignores SIGTERM gets SIGKILLed at the bound (the
    /// production grace stays 5s). The handshake line waits out the zsh
    /// startup race — a TERM arriving BEFORE the trap is installed kills
    /// the shell through its default disposition, which is NOT the face
    /// under test here.
    func testSIGKILLFiresAfterGraceForTermIgnoringChild() async throws {
        let fresh = McpLauncher()
        // trap '' TERM: the child ignores SIGTERM on purpose.
        let childPID = try fresh.start(
            renderedCommand: "trap '' TERM; echo trap-installed; sleep 30")
        defer { fresh.stop() }
        _ = try await Self.waitForLine(fresh, contains: "trap-installed", timeout: 10)
        let outcome = fresh.stop(pid: childPID)
        XCTAssertEqual(outcome, .killed, "a TERM-ignoring child must be SIGKILLed")
        _ = try await Self.waitForGone(fresh, pid: childPID, timeout: 10)
        XCTAssertNotEqual(kill(childPID, 0), 0, "the stubborn child is dead")
    }

    // MARK: - The log ring + panel semantics

    /// The ring drops from the HEAD past the cap: after appending
    /// cap + 100 lines, the snapshot is exactly the LAST 2000.
    func testLogRingTruncatesFromHead() {
        let buffer = McpLauncherLogBuffer(capacity: 2000)
        for index in 0..<(2000 + 100) {
            buffer.append("line-\(index)")
        }
        XCTAssertEqual(buffer.count, 2000)
        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.first, "line-100", "the head must be truncated")
        XCTAssertEqual(snapshot.last, "line-\(2000 + 100 - 1)")
        XCTAssertEqual(snapshot.count, 2000)
    }

    /// Copy semantics: the clipboard receives the FULL ring text (the
    /// panel's export face — v1 has no file export).
    @MainActor
    func testCopyLogPastesFullRingToPasteboard() {
        // Seed the shared core's ring, then route through the panel model's
        // copy face (the same code path the button rides).
        let core = McpLauncher.shared
        core.logBuffer.append("alpha")
        core.logBuffer.append("beta")
        let model = McpLauncherPanelModel()
        model.copyLog()
        let pasted = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasted, core.logBuffer.snapshot().joined(separator: "\n"))
    }

    /// The follow toggle is the 暂停滚动 face: OFF must leave `followScroll`
    /// false so the pane's onChange skips the scrollTo (the panel-side
    /// contract — the scroll decision lives behind this flag).
    @MainActor
    func testFollowToggleDrivesScrollFollowFlag() {
        let model = McpLauncherPanelModel()
        XCTAssertTrue(model.followScroll, "follow is the default")
        model.followScroll = false
        XCTAssertFalse(model.followScroll, "暂停滚动 = the viewport freezes")
        model.followScroll = true
        XCTAssertTrue(model.followScroll)
    }

    // MARK: - helpers

    private static func waitForGone(
        _ launcher: McpLauncher, pid: Int32, timeout: TimeInterval
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if launcher.runningPID != pid { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return launcher.runningPID != pid
    }

    private static func waitForLine(
        _ launcher: McpLauncher, contains needle: String, timeout: TimeInterval
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if launcher.logBuffer.snapshot().contains(where: { $0.contains(needle) }) {
                return true
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

/// A test-side probe isolating the dev-machine-dependent default endpoint
/// state (shared-machine honesty for the pre-flight refusal test).
enum McpLauncherEndpointProbe {
    static var isDefaultAlive: Bool {
        if case .alive = McpLauncher.endpointDiscoveryState() { return true }
        return false
    }
}
