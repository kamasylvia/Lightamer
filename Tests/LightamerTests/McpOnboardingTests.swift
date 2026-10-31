import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// UQ-S2/UQ-S3 (MCP-UQ batch): the onboarding model + one-shot gate — config
// generation from the live discovery path, the CLI install-face honesty,
// parse purity, typed error mapping, and the entry-fork probe.
// ─────────────────────────────────────────────────────────────────────────────

final class McpOnboardingTests: XCTestCase {

    // MARK: - UQ-S2: the paste-ready configs

    func testClaudeCodeCommandNamesTheLiveExecutable() {
        let command = McpOnboarding.claudeCodeCommand
        XCTAssertTrue(command.hasPrefix("claude mcp add lightamer -- "))
        XCTAssertTrue(command.contains("--mcp-stdio"))
        XCTAssertTrue(command.contains(McpOnboarding.executablePath))
    }

    func testDesktopConfigIsValidJSONWithStdioArgs() throws {
        let text = McpOnboarding.desktopConfig
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8), options: [])
                as? [String: Any])
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: Any])
        let entry = try XCTUnwrap(servers["lightamer"] as? [String: Any])
        XCTAssertEqual(
            entry["command"] as? String, McpOnboarding.executablePath)
        XCTAssertEqual(entry["args"] as? [String], ["--mcp-stdio"])
    }

    func testDiscoveryPathIsTheLiveDefault() {
        XCTAssertEqual(
            McpOnboarding.discoveryPath,
            McpEndpointPaths.makeDefault().jsonURL.path)
        XCTAssertTrue(
            McpOnboarding.cliUsage.contains(
                McpOnboarding.discoveryDisplayPath))
    }

    func testInstallScriptExecutesTheLiveExecutable() {
        let script = McpOnboarding.script
        XCTAssertTrue(script.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(script.contains(McpOnboarding.installMarker))
        XCTAssertTrue(script.contains(McpOnboarding.executablePath))
        XCTAssertTrue(script.contains("exec '"))
        XCTAssertTrue(script.hasSuffix("\"$@\"\n"))
    }

    // MARK: - UQ-S3: parse purity (no server needed)

    func testParseListAndHelp() throws {
        XCTAssertEqual(try McpOneShot.parse(["list"]), .list)
        XCTAssertEqual(try McpOneShot.parse(["--list"]), .list)
        // B-2 (zcode MCP-UQ review): the usage line must carry the
        // `--list` alias the parser accepts.
        XCTAssertTrue(McpOneShot.usage.contains("--list"))
        XCTAssertThrowsError(try McpOneShot.parse([]))
        XCTAssertThrowsError(try McpOneShot.parse(["list", "extra"]))
        XCTAssertThrowsError(try McpOneShot.parse(["nope"]))
    }

    func testParseCallShapes() throws {
        XCTAssertEqual(
            try McpOneShot.parse(["call", "get_state"]),
            .call(tool: "get_state", args: "{}"))
        XCTAssertEqual(
            try McpOneShot.parse(["call", "list_photos", #"{"limit":5}"#]),
            .call(tool: "list_photos", args: #"{"limit":5}"#))
        XCTAssertThrowsError(try McpOneShot.parse(["call"]))
        XCTAssertThrowsError(
            try McpOneShot.parse(["call", "x", "{}", "extra"]))
        // Non-object JSON is refused (the caller's to fix).
        XCTAssertThrowsError(
            try McpOneShot.parse(["call", "x", "[1,2]"]))
        XCTAssertThrowsError(
            try McpOneShot.parse(["call", "x", "not-json"]))
    }

    func testTailProbeSelectsOnlyTheMcpToken() {
        XCTAssertEqual(
            McpOneShot.tailIfRequested(arguments: ["Lightamer", "mcp", "list"]),
            ["list"])
        XCTAssertNil(
            McpOneShot.tailIfRequested(arguments: ["Lightamer", "--mcp-stdio"]))
        XCTAssertNil(McpOneShot.tailIfRequested(arguments: ["Lightamer"]))
    }

    // MARK: - UQ-S3: typed error mapping

    func testClientErrorMapsToolErrorsToRefused() {
        for token in [
            "unknownTool", "[unknownOp]", "[unknownPreset]",
            "[invalidParams]", "[invalidFilter]", "[notSessionMember]",
            "[imageLiveInEditor]", "[roiOutOfBounds]",
            "[keywordContainsSeparator]",
            "[exportPresetNotApplicable]", "[controlNotHeld]",
            "[controlRevokedByUser]", "[controlBusy]",
            "[serverReadOnly]", "[projectReadOnly]",
        ] {
            let mapped = McpOneShot.clientError(
                NSError(
                    domain: "mcp", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: token]))
            XCTAssertEqual(mapped.exitCode, 2, token)
        }
        for token in ["[renderFailed]", "[renderTimeout]", "[exportFailed]",
            "[modelUnavailable]", "[internalError]"] {
            let mapped = McpOneShot.clientError(
                NSError(
                    domain: "mcp", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: token]))
            XCTAssertEqual(mapped.exitCode, 1, token)
        }
        let transport = McpOneShot.clientError(
            NSError(
                domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost,
                userInfo: nil))
        XCTAssertEqual(transport.exitCode, 1)
    }

    func testResolveEndpointRefusesWithoutAService() {
        let paths = McpEndpointPaths(
            directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(
                    "mcp-oneshot-\(UUID().uuidString)"))
        do {
            _ = try McpOneShot.resolveEndpoint(in: paths)
            XCTFail("no discovery file must refuse")
        } catch let error as McpOneShotError {
            XCTAssertEqual(error.exitCode, 2)
            XCTAssertTrue(error.message.contains("Settings"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testBearerTokenNilOnLoopback() throws {
        var info = McpEndpointInfo(
            schemaVersion: 1, transport: "streamable-http",
            host: "127.0.0.1", port: 1, pid: 0, startedAt: "",
            serverName: "x", serverVersion: "y", auth: "none")
        XCTAssertNil(try McpOneShot.bearerToken(for: info))
        info.auth = "bearer"
        // No stored token in the test sandbox → refused (exit 2), unless
        // the developer machine holds one (then the token loads — either
        // arm is honest; assert only that it does not crash).
        _ = try? McpOneShot.bearerToken(for: info)
    }

    // MARK: - UQ-S3: the live round trip through the real binary

    /// Spawns THIS host binary as `mcp list` against a live NIO host in a
    /// test endpoint domain: discovery → handshake → tools/list → print.
    /// (The child inherits LIGHTAMER_MCP_ENDPOINT_DIR so its discovery
    /// probe reads the test domain — the L036 discipline.)
    func testOneShotListRoundTripsThroughTheBinary() async throws {
        let domain = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "mcp-oneshot-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: domain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: domain) }
        let paths = McpEndpointPaths(directory: domain)
        let handle = try await McpServerController.startHTTPHost(
            paths: paths,
            editing: EditingToolset.Seams(
                session: { nil }, metal: { nil },
                modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }),
            culling: McpServerController.makeCullingContext(session: { nil }))
        defer { Task { await handle.stop() } }

        let child = Process()
        child.executableURL = try XCTUnwrap(Bundle.main.executableURL)
        child.arguments = ["mcp", "list"]
        var env = ProcessInfo.processInfo.environment
        // DEBUG-only hook the headless arms read; the one-shot gate
        // resolves the default paths — redirect via the same variable.
        env["LIGHTAMER_MCP_ENDPOINT_DIR"] = domain.path
        child.environment = env
        let stdout = Pipe()
        let stderr = Pipe()
        child.standardOutput = stdout
        child.standardError = stderr
        try child.run()
        // M-11: bounded wait (the spawnHolder deadline precedent) — an
        // unbounded waitUntilExit hangs the suite if the child stalls.
        let deadline = Date().addingTimeInterval(60)
        while child.isRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if child.isRunning {
            child.terminate()
            XCTFail("the one-shot child hung past 60s")
            return
        }
        XCTAssertEqual(child.terminationStatus, 0)
        let out = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8) ?? ""
        XCTAssertTrue(out.contains("get_schema"), "got: \(out)")
        XCTAssertTrue(out.contains("list_iops"), "got: \(out)")
    }
}
