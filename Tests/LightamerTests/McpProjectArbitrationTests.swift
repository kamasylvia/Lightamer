import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan M6-1-01 T6 (KD-8 golden gates 2/3): the headless `--project`
// arbitration against REAL processes (the McpHostTests spawn shape — every
// child is THIS host binary). Gate 2 = the symmetric read-only fallback with
// bidirectional determinism (sequences A/A'/B, each conclusion stable across
// two runs, the five-state ③ window re-run); gate 3 = the connect-guidance
// machine face (JSON schema per key, the HTTP=stdout / STDIO=stderr fork
// with the stdout zero-pollution negative, the degraded endpoint-null
// variant).
//
// Hermeticity: every child runs with LIGHTAMER_MCP_ENDPOINT_DIR pointing at
// a per-test temp directory (the DEBUG assembly-root env read — the spawned
// child cannot take constructor parameters), so the discovery machinery and
// the endpoint json never touch the user's Application Support.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class McpProjectArbitrationTests: XCTestCase {

    private var tempDirectory: URL!
    private var endpointDirectory: URL!
    private var packageURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-arb-\(UUID().uuidString)", isDirectory: true)
        endpointDirectory = tempDirectory.appendingPathComponent("mcp", isDirectory: true)
        try FileManager.default.createDirectory(
            at: endpointDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Widget.lalb")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    private var lockURL: URL {
        packageURL.deletingPathExtension().appendingPathExtension("lalb.lock")
    }

    private var endpointPaths: McpEndpointPaths {
        McpEndpointPaths(directory: endpointDirectory)
    }

    /// The package under arbitration (a real v4 store; per test — the
    /// actor calls need the async context).
    private func makePackage() async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "Widget")
        try await store.close()
    }

    // MARK: - Spawn harness

    private func makeChild(
        arguments: [String]
    ) throws -> (Process, LineReader, LineReader) {
        let process = Process()
        process.executableURL = try XCTUnwrap(
            Bundle.main.executableURL, "test host binary missing")
        var environment = ProcessInfo.processInfo.environment
        environment["LIGHTAMER_MCP_ENDPOINT_DIR"] = endpointDirectory.path
        // F14 (M7-4-01): spawn-time LUT preheat opt-out — the real-host
        // fixture must not pay the ~50s .utility parse (nor seed the real
        // user LUT root) inside the e2e windows.
        environment["LIGHTAMER_SKIP_LUT_PREHEAT"] = "1"
        process.environment = environment
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        try process.run()
        return (
            process,
            LineReader(handle: stdout.fileHandleForReading),
            LineReader(handle: stderr.fileHandleForReading)
        )
    }

    /// Bounded pipe reader: every read is gated by a poll(2) so a parked
    /// child never blocks the test (the McpHostTests LockedHandshake
    /// discipline, minus the hand-built thread — poll gives the deadline).
    final class LineReader: @unchecked Sendable {
        private let handle: FileHandle

        init(handle: FileHandle) { self.handle = handle }

        /// One ready-gated read; nil = not ready within `timeoutMs`, empty
        /// = EOF.
        private func readChunk(timeoutMs: Int32) -> Data? {
            var fds = [pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)]
            let ready = poll(&fds, 1, timeoutMs)
            guard ready > 0, fds[0].revents & Int16(POLLIN) != 0 else { return nil }
            return handle.availableData
        }

        /// The first complete line (deadline-bounded).
        func firstLine(timeout: TimeInterval = 8.0) -> String? {
            var data = Data()
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let remaining = Int32(
                    max(50, deadline.timeIntervalSinceNow * 1000))
                guard let chunk = readChunk(timeoutMs: remaining) else {
                    if Date() >= deadline { return nil }
                    continue
                }
                if chunk.isEmpty { break }  // EOF
                data.append(chunk)
                if let text = String(data: data, encoding: .utf8),
                    text.contains("\n")
                {
                    return text.components(separatedBy: "\n").first
                }
            }
            return nil
        }

        /// Everything arriving within `maxWait` (the zero-byte negatives).
        func drainAvailable(maxWait: TimeInterval = 0.5) -> Data {
            var data = Data()
            let deadline = Date().addingTimeInterval(maxWait)
            while Date() < deadline {
                let remaining = Int32(max(20, deadline.timeIntervalSinceNow * 1000))
                guard let chunk = readChunk(timeoutMs: remaining) else { continue }
                if chunk.isEmpty { break }
                data.append(chunk)
            }
            return data
        }
    }

    /// The holder-side live endpoint fixture (json + endpoint lock held by
    /// THIS test process — the child's discovery answers `.alive`
    /// deterministically).
    private func installLiveEndpoint(port: Int = 59999) throws -> McpEndpointLock {
        let info = McpEndpointInfo(
            schemaVersion: McpEndpointInfo.schemaVersionV1,
            transport: McpEndpointInfo.transportStreamableHTTP,
            host: "127.0.0.1", port: port,
            pid: getpid(),
            startedAt: McpEndpointInfo.nowISO8601(),
            serverName: McpServerController.serverName,
            serverVersion: McpServerController.serverVersion,
            auth: McpEndpointInfo.authNone)
        try McpEndpointFile.write(info, in: endpointPaths)
        return try XCTUnwrap(McpEndpointLock.acquire(in: endpointPaths).get())
    }

    /// The project-lock holder payload (the diagnostics face the guidance
    /// reads its holderPid from).
    private func holdProjectLock(pid: Int32) throws -> SingleWriterLock {
        let holder = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        holder.writePayload(
            SingleWriterLockPayload(
                role: .gui, pid: pid,
                startedAt: SingleWriterLockPayload.nowISO8601()))
        return holder
    }

    // MARK: - Sequence A (parent holds → child read-only arm)

    /// 序 A, alive endpoint: the child's stdout FIRST line is the guidance
    /// JSON with the frozen schema (event / holderPid / endpoint
    /// transport+host+port+auth) and the process STAYS ALIVE (the read-only
    /// 常驻 arm — the negative against the rejected immediate-exit shape).
    func testSequenceAHttpGuidanceAliveEndpoint() async throws {
        try await makePackage()
        let holder = try holdProjectLock(pid: getpid())
        let endpointLock = try installLiveEndpoint(port: 59999)
        defer {
            endpointLock.unlock()
            holder.unlock()
        }
        let (child, stdout, _) = try makeChild(arguments: [
            "--mcp-http", McpServerController.projectFlag, packageURL.path,
        ])
        defer {
            child.terminate()
            child.waitUntilExit()
        }
        let line = try XCTUnwrap(stdout.firstLine(), "guidance JSON on stdout")
        let data = try XCTUnwrap(line.data(using: .utf8))
        let guidance = try JSONDecoder().decode(
            McpServerController.McpConnectGuidance.self, from: data)
        XCTAssertEqual(
            guidance.event, McpServerController.connectGuidanceEvent)
        XCTAssertEqual(guidance.holderPid, getpid())
        let endpoint = try XCTUnwrap(guidance.endpoint)
        XCTAssertEqual(endpoint.transport, "streamable-http")
        XCTAssertEqual(endpoint.host, "127.0.0.1")
        XCTAssertEqual(endpoint.auth, "none")
        // The read-only 常驻 negative: the process survives well past the
        // guidance emission.
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertTrue(child.isRunning, "the read-only arm must stay resident")
    }

    /// 序 A, degraded variant: no endpoint file → `endpoint: null` (the
    ///「关闭它或在其上开启 MCP server」face).
    func testSequenceADegradedGuidance() async throws {
        try await makePackage()
        let holder = try holdProjectLock(pid: 32121)
        defer { holder.unlock() }
        let (child, stdout, _) = try makeChild(arguments: [
            "--mcp-http", McpServerController.projectFlag, packageURL.path,
        ])
        defer {
            child.terminate()
            child.waitUntilExit()
        }
        let line = try XCTUnwrap(stdout.firstLine())
        let guidance = try JSONDecoder().decode(
            McpServerController.McpConnectGuidance.self,
            from: XCTUnwrap(line.data(using: .utf8)))
        XCTAssertEqual(guidance.event, McpServerController.connectGuidanceEvent)
        XCTAssertNil(guidance.endpoint, "no endpoint file → the degraded null")
        XCTAssertEqual(guidance.holderPid, 32121)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertTrue(child.isRunning)
    }

    /// 序 A' (stdio variant): BOTH the guidance JSON and the human line ride
    /// STDERR, and stdout stays at ZERO bytes before any initialize — the
    /// protocol channel is unpolluted (the KD-4 negative).
    func testSequenceAStdioStdoutZeroPollution() async throws {
        try await makePackage()
        let holder = try holdProjectLock(pid: getpid())
        defer { holder.unlock() }
        let (child, stdout, stderr) = try makeChild(arguments: [
            "--mcp-stdio", McpServerController.projectFlag, packageURL.path,
        ])
        defer {
            child.terminate()
            child.waitUntilExit()
        }
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(child.isRunning, "the stdio read-only arm stays resident")
        let stdoutBytes = stdout.drainAvailable(maxWait: 0.5)
        XCTAssertTrue(
            stdoutBytes.isEmpty,
            "stdio stdout must stay a pure protocol channel — got "
                + (String(data: stdoutBytes, encoding: .utf8)?.debugDescription ?? "nil"))
        let stderrText = String(
            data: stderr.drainAvailable(maxWait: 0.5), encoding: .utf8) ?? ""
        // The machine line: parseable JSON with the frozen event.
        let jsonLine = try XCTUnwrap(
            stderrText.components(separatedBy: "\n").first {
                $0.contains("connect-guidance")
            }, "the guidance JSON rides stderr: \(stderrText)")
        let guidance = try JSONDecoder().decode(
            McpServerController.McpConnectGuidance.self,
            from: XCTUnwrap(jsonLine.data(using: .utf8)))
        XCTAssertEqual(guidance.event, McpServerController.connectGuidanceEvent)
        // The human line: contains the pid (locale-independent token).
        XCTAssertTrue(
            stderrText.contains("pid"),
            "the human line names the holder pid: \(stderrText)")
    }

    // MARK: - Sequence B (child holds → the open face refuses)

    /// 序 B: the child holds the project lock (the real fixture binary) →
    /// the parent's typed open face refuses with the holder summary in the
    /// detail.
    func testSequenceBTypedConflictWithHolderDetail() async throws {
        try await makePackage()
        let (child, stdout, _) = try makeChild(arguments: [
            "-la_project_hold_lock", packageURL.path,
        ])
        defer {
            child.terminate()
            child.waitUntilExit()
        }
        let handshake = try XCTUnwrap(stdout.firstLine())
        XCTAssertTrue(handshake.hasPrefix("PROJECT-LOCKED"), handshake)
        let store = ProjectFileStore(at: packageURL)
        do {
            _ = try await store.open(role: .headless)
            XCTFail("the open must refuse the held project lock")
        } catch let error as LibraryError {
            guard case .projectHeldByOther(let detail) = error else {
                return XCTFail("wrong typed error: \(error)")
            }
            XCTAssertTrue(detail.contains("pid="), "detail: \(detail)")
        }
    }

    // MARK: - Determinism (each sequence twice, conclusion-identical)

    /// 序 A double-run: both children reach the SAME read-only conclusion
    /// (same winner, same holder pid, same endpoint — decode-level equality;
    /// the encoder's JSON key order is not contractual).
    func testDeterminismSequenceADoubleRun() async throws {
        try await makePackage()
        let holder = try holdProjectLock(pid: getpid())
        let endpointLock = try installLiveEndpoint(port: 59999)
        defer {
            endpointLock.unlock()
            holder.unlock()
        }
        var conclusions: [McpServerController.McpConnectGuidance] = []
        for _ in 0..<2 {
            let (child, stdout, _) = try makeChild(arguments: [
                "--mcp-http", McpServerController.projectFlag, packageURL.path,
            ])
            let line = try XCTUnwrap(stdout.firstLine())
            conclusions.append(
                try JSONDecoder().decode(
                    McpServerController.McpConnectGuidance.self,
                    from: XCTUnwrap(line.data(using: .utf8))))
            child.terminate()
            child.waitUntilExit()
        }
        XCTAssertEqual(
            conclusions[0], conclusions[1],
            "double-run conclusions must match")
        XCTAssertEqual(
            conclusions[0].event, McpServerController.connectGuidanceEvent)
    }

    /// 序 B double-run: the typed conflict fires on both runs.
    func testDeterminismSequenceBDoubleRun() async throws {
        try await makePackage()
        for _ in 0..<2 {
            let (child, stdout, _) = try makeChild(arguments: [
                "-la_project_hold_lock", packageURL.path,
            ])
            defer {
                child.terminate()
                child.waitUntilExit()
            }
            let handshake = try XCTUnwrap(stdout.firstLine())
            XCTAssertTrue(handshake.hasPrefix("PROJECT-LOCKED"), handshake)
            let store = ProjectFileStore(at: packageURL)
            do {
                _ = try await store.open(role: .headless)
                XCTFail("the open must refuse the held project lock")
            } catch let error as LibraryError {
                guard case .projectHeldByOther = error else {
                    return XCTFail("wrong typed error: \(error)")
                }
            }
        }
    }

    // MARK: - The five-state ③ window (writer arm after the holder exits)

    /// The holder exits → the child re-run wins the WRITER arm: the endpoint
    /// json lands in the (temp) discovery directory and the child holds the
    /// project lock (the probe answers false), with NO guidance on stdout.
    func testWriterArmAfterHolderExit() async throws {
        try await makePackage()
        // Hold → release (the holder's exit; the kernel window).
        let holder = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        holder.unlock()
        let (child, stdout, _) = try makeChild(arguments: [
            "--mcp-http", McpServerController.projectFlag, packageURL.path,
        ])
        defer {
            child.terminate()
            child.waitUntilExit()
        }
        // Writer arm evidence: the discovery json lands (the http daemon's
        // assembly product) and no guidance line ever hits stdout.
        let jsonURL = endpointPaths.jsonURL
        var landed = false
        for _ in 0..<40 {
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                landed = true
                break
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTAssertTrue(landed, "the writer arm's http daemon writes the json")
        try await Task.sleep(for: .milliseconds(300))
        let stdoutBytes = stdout.drainAvailable(maxWait: 0.3)
        XCTAssertTrue(
            stdoutBytes.isEmpty,
            "the writer arm emits no guidance — got "
                + (String(data: stdoutBytes, encoding: .utf8)?.debugDescription ?? "nil"))
        guard case .failure(.heldByOther) = SingleWriterLock.acquire(at: lockURL)
        else {
            return XCTFail("the child writer arm must hold the project lock")
        }
    }

    // MARK: - The `--project` flag validation + the no-project smoke

    /// The flag with no path (and a non-`.lalb` path) = stderr error +
    /// exit 1 (the KD-4 validation legs — the flag rides WITH a mode flag,
    /// one method both legs).
    func testProjectFlagValidationExitsOne() throws {
        for arguments in [
            ["--mcp-stdio", McpServerController.projectFlag],
            ["--mcp-http", McpServerController.projectFlag, "/tmp/not-a-package.bar"],
        ] {
            let (child, _, stderr) = try makeChild(arguments: arguments)
            let exited = DispatchSemaphore(value: 0)
            child.terminationHandler = { _ in exited.signal() }
            XCTAssertEqual(
                exited.wait(timeout: .now() + 15), .success,
                "the validation exit must be prompt: \(arguments)")
            XCTAssertEqual(child.terminationStatus, 1, "arguments: \(arguments)")
            let message = String(
                data: stderr.drainAvailable(maxWait: 1), encoding: .utf8) ?? ""
            XCTAssertTrue(
                message.contains(McpServerController.projectFlag),
                "the stderr names the flag: \(message)")
        }
    }

    /// The no-`--project` smoke: the legacy headless stdio body starts and
    /// parks with ZERO stdout bytes before any initialize (byte-identical
    /// legacy behavior — the zero-regression surface).
    func testNoProjectStdioSmoke() async throws {
        let (child, stdout, _) = try makeChild(arguments: ["--mcp-stdio"])
        defer {
            child.terminate()
            child.waitUntilExit()
        }
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(child.isRunning, "the legacy stdio host parks")
        let stdoutBytes = stdout.drainAvailable(maxWait: 0.3)
        XCTAssertTrue(
            stdoutBytes.isEmpty,
            "the legacy body emits nothing unprompted on stdout")
    }

    // MARK: - S1 e2e (M7-4-01 T1): the REAL EOF disconnect face

    /// The first REAL stdin-EOF disconnect leg (the arbitration spawns use
    /// SIGTERM — `child.terminate()` — which never drives the watcher's
    /// POLLHUP path). Drive: spawn the production host `--mcp-stdio` →
    /// initialize → `project_create` (the runtime open arms the EOF
    /// watcher) → close the pipe's WRITE end (the agent-disconnect face)
    /// → the host must exit ≤12s (the pre-fix events:0 form never woke —
    /// the process parked forever holding the flock) and the close-riding
    /// TRUNCATE checkpoint must leave `.lalb-wal` EMPTY (size == 0 — a
    /// killed process cannot produce this state, so it is the graceful
    /// checkpoint face's positive evidence).
    func testStdioDisconnectReleasesProjectGracefullyE2E() async throws {
        let packageName = "EofRelease"
        let packageURL = tempDirectory.appendingPathComponent(
            packageName + ".lalb")
        let (child, stdout, _) = try makeChild(arguments: ["--mcp-stdio"])

        // The handshake (line-delimited JSON-RPC over the stdin/stdout
        // pipes — the same face the real agents drive).
        let stdin = try XCTUnwrap(
            child.standardInput as? Pipe, "the child stdin must be a pipe")
        func send(_ line: String) {
            stdin.fileHandleForWriting.write(Data((line + "\n").utf8))
        }
        send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"m74-e2e","version":"0"}}}"#)
        _ = try XCTUnwrap(stdout.firstLine(), "the initialize reply")
        send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        send(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"project_create","arguments":{"folder":"\#(tempDirectory.path)","name":"\#(packageName)"}}}"#)

        // Wait (bounded) for the create reply: the runtime open is done
        // and the EOF watcher is armed once this returns.
        var createReplied = false
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !createReplied {
            let chunk = stdout.drainAvailable(maxWait: 0.5)
            guard let text = String(data: chunk, encoding: .utf8) else { break }
            for line in text.components(separatedBy: "\n") {
                guard let object = try? JSONSerialization.jsonObject(
                    with: Data(line.utf8)) as? [String: Any]
                else { continue }
                if (object["id"] as? Int) == 2 {
                    XCTAssertNil(
                        object["error"], "project_create must succeed: \(line)")
                    createReplied = true
                }
            }
        }
        XCTAssertTrue(
            createReplied, "the project_create reply never arrived (10s)")

        // The lock-semantics side note (the optional leg): while the child
        // holds the freshly created package, a second open from HERE is
        // the typed heldByOther refusal.
        let sidecar = ProjectFileStore(at: packageURL)
        do {
            _ = try await sidecar.open(role: .headless)
            XCTFail("the child must hold the project lock after create")
        } catch let error as LibraryError {
            guard case .projectHeldByOther = error else {
                return XCTFail("wrong typed error: \(error)")
            }
        }

        // THE DISCONNECT: close the sole write end = the real EOF face
        // (the watcher's poll must wake POLLHUP → close + exit(0)).
        stdin.fileHandleForWriting.closeFile()
        let disconnectAt = Date()
        while Date() < disconnectAt.addingTimeInterval(12), child.isRunning {
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertFalse(
            child.isRunning,
            "the stdio host must exit ≤12s after stdin EOF (the S1 fix — "
                + "the events:0 poll form never woke and the process parked "
                + "holding the flock)")
        child.waitUntilExit()
        XCTAssertEqual(
            child.terminationStatus, 0,
            "the graceful-release exit is exit(0) (not a crash)")

        // The checkpoint face: the watcher's close rides the FORCED TRUNCATE
        // checkpoint — the WAL must be empty (a killed process leaves pages
        // behind, so size == 0 is positive evidence of the graceful face).
        let walURL = packageURL.deletingPathExtension()
            .appendingPathExtension("lalb-wal")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: walURL.path),
            "the WAL file must survive the clean close on this platform")
        let walSize = try FileManager.default.attributesOfItem(
            atPath: walURL.path)[.size] as? Int
        XCTAssertEqual(
            walSize, 0,
            "the graceful checkpoint must leave .lalb-wal EMPTY (size == 0) — "
                + "a killed process cannot produce this state")
    }
}
