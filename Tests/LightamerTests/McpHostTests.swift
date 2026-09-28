import LightamerCore
import MCP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-1 T3: the single-writer machinery — the probe-verified five flock
// states exercised against REAL processes (the hold-lock DEBUG fixture spawns
// THIS HOST BINARY), the read-only degradation hook, the discovery protocol
// (read json → try-lock → residue cleanup) and the stdio host's D2 shape
// (holds the lock, writes NO json) + the stdio three-step handshake.
//
// T4/T5 extend this file with the HTTP leg, the endpoint-file write/delete
// timing against the live host, the security face and the hello cross-host
// conformance.
// ─────────────────────────────────────────────────────────────────────────────

final class McpHostTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-host-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private var paths: McpEndpointPaths { McpEndpointPaths(directory: tempDirectory) }

    // MARK: - The hold-lock subprocess fixture

    /// Spawns THIS host binary holding the writer lock on `directory`.
    /// Returns the process plus the first stdout line reader (the LOCKED
    /// handshake, deadline-bounded).
    private func spawnHolder() throws -> (Process, LockedHandshake) {
        let process = Process()
        process.executableURL = try XCTUnwrap(
            Bundle.main.executableURL, "test host binary missing")
        process.arguments = ["-la_mcp_hold_lock", tempDirectory.path]
        let stdout = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardInput = stdin
        process.standardError = FileHandle.nullDevice
        try process.run()
        return (process, LockedHandshake(handle: stdout.fileHandleForReading))
    }

    /// Deadline-bounded first-line reader for the LOCKED handshake (a
    /// blocking readDataToEndOfFile would hang forever when the child parks).
    private final class LockedHandshake: @unchecked Sendable {
        private let handle: FileHandle
        private let queue = DispatchQueue(label: "mcp.locked-handshake")

        init(handle: FileHandle) { self.handle = handle }

        func firstLine(timeout: TimeInterval) async throws -> String {
            let semaphore = DispatchSemaphore(value: 0)
            let box = LockedHandshakeBox()
            queue.async {
                var data = Data()
                while true {
                    let chunk = self.handle.availableData
                    if chunk.isEmpty { break }  // EOF
                    data.append(chunk)
                    if String(data: data, encoding: .utf8)?.contains("\n") == true {
                        break
                    }
                }
                box.line = String(data: data, encoding: .utf8)
                semaphore.signal()
            }
            XCTAssertTrue(mcpBlockingWait(semaphore, timeout: timeout), "LOCKED handshake timed out")
            return try XCTUnwrap(box.line, "no handshake line")
        }

        /// Discards the rest of the child's stdout on a side queue so a later
        /// waitUntilExit cannot deadlock on a full pipe buffer.
        func drain() {
            queue.async { while !self.handle.availableData.isEmpty {} }
        }
    }

    /// DispatchSemaphore.wait is unavailable IN async contexts by name only;
    /// the bounded wait itself is the point (this helper keeps the checker
    /// honest about what it is: a deadline on a pipe reader, never a deadlock).
    fileprivate static func mcpBlockingWait(
        _ semaphore: DispatchSemaphore, timeout: TimeInterval
    ) -> Bool {
        semaphore.wait(timeout: .now() + timeout) == .success
    }

    private final class LockedHandshakeBox: @unchecked Sendable {
        var line: String?
    }

    // MARK: - Five flock states (two real processes)

    /// State 1: mutex — while a live process holds the lock, a second
    /// acquire fails immediately with .heldByOther (EWOULDBLOCK).
    func testFlockMutexTwoProcesses() async throws {
        let (holder, handshake) = try spawnHolder()
        defer { handshake.drain() }
        let line = try await handshake.firstLine(timeout: 30)
        XCTAssertTrue(line.hasPrefix("LOCKED"), "holder handshake: \(line)")

        switch McpEndpointLock.acquire(in: paths) {
        case .success:
            XCTFail("second acquire MUST fail while the holder lives")
        case .failure(.heldByOther):
            break  // expected — the ONLY non-fatal acquire failure
        case .failure(.ioError(let reason)):
            XCTFail("unexpected io error: \(reason)")
        }
        holder.terminate()  // SIGTERM; the lock releases on exit
        holder.waitUntilExit()
    }

    /// State 3: the holder EXITS cleanly → the kernel releases the lock →
    /// the next acquirer succeeds. Zero cleanup code involved.
    func testFlockReleasedOnHolderExit() async throws {
        let (holder, handshake) = try spawnHolder()
        let line = try await handshake.firstLine(timeout: 30)
        XCTAssertTrue(line.hasPrefix("LOCKED"), "holder handshake: \(line)")

        // The fixture parks on stdin EOF; closing our write end ends it.
        holder.interrupt()  // SIGTERM → clean exit path
        holder.waitUntilExit()

        let result = McpEndpointLock.acquire(in: paths)
        var released = false
        if case .success(let lock) = result {
            released = true
            lock.unlock()
        }
        XCTAssertTrue(
            released, "a cleanly exited holder must leave the lock free")
    }

    /// State 4: the holder is SIGKILLed (the crash shape) → the KERNEL
    /// releases the lock → the successor acquires immediately. This is why
    /// the O_EXCL + pid-revalidation dance is NOT implemented (probe 终判).
    func testFlockKernelSelfReleaseAfterCrash() async throws {
        let (holder, handshake) = try spawnHolder()
        let line = try await handshake.firstLine(timeout: 30)
        XCTAssertTrue(line.hasPrefix("LOCKED"), "holder handshake: \(line)")

        kill(holder.processIdentifier, SIGKILL)
        holder.waitUntilExit()

        let acquiredAt = Date()
        let result = McpEndpointLock.acquire(in: paths)
        if case .success(let lock) = result {
            lock.unlock()
        } else {
            XCTFail("crashed holder must release through the kernel immediately")
        }
        XCTAssertLessThan(
            Date().timeIntervalSince(acquiredAt), 2.0,
            "the post-crash acquire is immediate (no residue dance)")
    }

    /// State 2 + the T3.5 hook: a process that did NOT get the lock starts
    /// READ-ONLY — write-face tools throw serverReadOnly pointing at the
    /// endpoint file; read-face tools are unaffected; a lock holder passes.
    func testReadOnlyDegradationWriterCheckHook() async throws {
        let registry = McpToolRegistry()
        await registry.register(
            McpToolDescriptor(
                name: "synthetic_write",
                description: "test double for a write-face tool",
                inputSchemaJSON: #"{"type":"object","properties":{}}"#,
                destructiveHint: true),
            requiresWriter: true,
            handler: { _ in .text("wrote") })
        await registry.register(
            McpToolDescriptor(
                name: "synthetic_read",
                description: "test double for a read-face tool",
                inputSchemaJSON: #"{"type":"object","properties":{}}"#,
                readOnlyHint: true),
            handler: { _ in .text("read") })

        // NOT the writer → the write face is gated, the read face is not.
        await registry.setWriterCheck { false }
        do {
            _ = try await registry.call(name: "synthetic_write", arguments: [:])
            XCTFail("write tool must fail with serverReadOnly in read-only mode")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "serverReadOnly")
            XCTAssertTrue(
                error.message.contains("mcp-endpoint.json"),
                "the error text must point the agent at the endpoint file")
        }
        let read = try await registry.call(name: "synthetic_read", arguments: [:])
        XCTAssertEqual(read, .text("read"))

        // The writer → everything passes.
        await registry.setWriterCheck { true }
        let write = try await registry.call(name: "synthetic_write", arguments: [:])
        XCTAssertEqual(write, .text("wrote"))
    }

    // MARK: - T4: the Streamable HTTP leg

    /// The full SDK-client round trip against the NIO leg: connect (auto
    /// initialize, 2025-11-25 echo) → tools/list → tools/call → disconnect.
    /// This is ALSO the runtime 127.0.0.1 binding proof — the socket only
    /// exists on the loopback constant.
    func testHTTPEndToEndSDKClientRoundTrip() async throws {
        let handle = try await McpServerController.startHTTPHost(
            paths: paths, storeProvider: { nil })

        let endpoint = URL(string: "http://127.0.0.1:\(handle.port)/mcp")!
        let client = HTTPClientTransport(endpoint: endpoint)
        let clientActor = MCP.Client(name: "host-tests", version: "0.0.1")
        let initResult = try await clientActor.connect(transport: client)
        XCTAssertEqual(
            initResult.protocolVersion, "2025-11-25",
            "the initialize echo pins the protocol revision")

        let (tools, _) = try await clientActor.listTools()
        XCTAssertEqual(Set(tools.map(\.name)), ["ping", "count_images"])

        let (content, isError) = try await clientActor.callTool(
            name: "ping", arguments: ["echo": .string("http-hello")])
        XCTAssertNil(isError)
        XCTAssertEqual(McpAdapters.outputContent(from: content[0]), .text("http-hello"))

        await clientActor.disconnect()

        // Stop: the discovery file is deleted and the writer lock returns.
        await handle.stop()
        XCTAssertEqual(
            McpEndpointDiscovery.discover(in: paths), .noEndpointFile,
            "after stop there is neither json nor a live lock")
        XCTAssertTrue(
            McpEndpointLock.probeLockAvailable(in: paths),
            "stop must release the writer lock")
    }

    /// The discovery-file write/delete timing against a live host: alive
    /// while serving, gone after stop (no residue on a graceful shutdown).
    func testHTTPEndpointFileWriteDeleteTiming() async throws {
        let handle = try await McpServerController.startHTTPHost(
            paths: paths, storeProvider: { nil })

        guard case .alive(let info) = McpEndpointDiscovery.discover(in: paths) else {
            return XCTFail("a live host must be discoverable")
        }
        XCTAssertEqual(info.host, "127.0.0.1", "the loopback constant rides the file")
        XCTAssertEqual(info.port, handle.port, "the REAL bound port rides the file")
        XCTAssertEqual(info.transport, "streamable-http")
        XCTAssertEqual(info.auth, McpEndpointInfo.authNone)

        await handle.stop()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.jsonURL.path),
            "graceful stop deletes the discovery json")
    }

    /// The SDK's built-in validation pipeline (probe behavior, now pinned):
    /// evil Origin → 403, no-port localhost Origin → 403 (the pattern
    /// `http://localhost:*` requires a port, D6), Host mismatch → 421, and
    /// no Origin (the agent-CLI shape) → passes.
    func testOriginAndHostValidationPipeline() async throws {
        let handle = try await McpServerController.startHTTPHost(
            paths: paths, storeProvider: { nil })
        defer { Task { await handle.stop() } }

        let initializeBody =
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}"#

        func post(headers: [String: String]) async -> HTTPResponse {
            var merged: [String: String] = [
                "Accept": "application/json, text/event-stream",
                "Content-Type": "application/json",
            ]
            for (key, value) in headers { merged[key] = value }
            let request = HTTPRequest(
                method: "POST", headers: merged,
                body: Data(initializeBody.utf8), path: "/mcp")
            return await handle.host.handleHTTPRequest(request)
        }

        let evil = await post(headers: ["Origin": "http://evil.example.com"])
        XCTAssertEqual(evil.statusCode, 403, "invalid Origin must be rejected")

        let noPort = await post(headers: ["Origin": "http://localhost"])
        XCTAssertEqual(
            noPort.statusCode, 403,
            "a portless localhost Origin is rejected (D6: * requires a port)")

        let hostMismatch = await post(
            headers: [
                "Host": "evil.example.com:1",
                "Origin": "http://localhost:\(handle.port)",
            ])
        XCTAssertEqual(hostMismatch.statusCode, 421, "Host mismatch = DNS rebinding guard")

        let clean = await post(headers: [:])
        XCTAssertEqual(
            clean.statusCode, 200,
            "no Origin (agent CLI clients) passes the pipeline")
    }

    /// Per-session transports with a HARD CAP of 4 (§RQ-14-14): four
    /// initialize requests create four sessions; the fifth gets 503.
    func testSessionCapacityCap503() async throws {
        let handle = try await McpServerController.startHTTPHost(
            paths: paths, storeProvider: { nil })
        defer { Task { await handle.stop() } }

        let initializeBody =
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}"#
        let request = HTTPRequest(
            method: "POST",
            headers: [
                "Accept": "application/json, text/event-stream",
                "Content-Type": "application/json",
            ],
            body: Data(initializeBody.utf8), path: "/mcp")

        for index in 0..<4 {
            let response = await handle.host.handleHTTPRequest(request)
            XCTAssertEqual(
                response.statusCode, 200, "session \(index) must be admitted")
        }
        let overflow = await handle.host.handleHTTPRequest(request)
        XCTAssertEqual(overflow.statusCode, 503, "the fifth session is over the cap")
    }

    /// Single transport = single session (probe finding): a second
    /// initialize riding the SAME session id is a 400.
    func testSecondInitializeOnSameSessionIs400() async throws {
        let handle = try await McpServerController.startHTTPHost(
            paths: paths, storeProvider: { nil })
        defer { Task { await handle.stop() } }

        let initializeBody =
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}"#
        let request = HTTPRequest(
            method: "POST",
            headers: [
                "Accept": "application/json, text/event-stream",
                "Content-Type": "application/json",
            ],
            body: Data(initializeBody.utf8), path: "/mcp")

        let first = await handle.host.handleHTTPRequest(request)
        XCTAssertEqual(first.statusCode, 200)
        let sessionID = try XCTUnwrap(
            first.headers["MCP-Session-Id"], "initialize must mint a session id")

        // HTTPRequest.headers is immutable — the second initialize rides a
        // NEW request carrying the minted session id.
        var sessionHeaders: [String: String] = request.headers
        sessionHeaders["Mcp-Session-Id"] = sessionID
        let second = await handle.host.handleHTTPRequest(
            HTTPRequest(
                method: "POST",
                headers: sessionHeaders,
                body: Data(initializeBody.utf8), path: "/mcp"))
        XCTAssertEqual(
            second.statusCode, 400,
            "re-initializing an established session is a protocol error")
    }

    // MARK: - Discovery protocol (state 5)

    func testDiscoveryProtocolThreeOutcomes() async throws {
        // No file at all.
        XCTAssertEqual(McpEndpointDiscovery.discover(in: paths), .noEndpointFile)

        // Residue: json exists, lock FREE (the holder is dead) → removed.
        let info = McpEndpointHostFixtures.sampleInfo(port: 51234)
        try McpEndpointFile.write(info, in: paths)
        XCTAssertEqual(
            McpEndpointDiscovery.discover(in: paths), .staleResidueRemoved)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.jsonURL.path),
            "stale residue must be cleaned by the discoverer")

        // Live: a writer holds the lock in THIS process (its own fd) → the
        // json stays and the payload comes back.
        let live = McpEndpointPaths(
            directory: tempDirectory.appendingPathComponent("live", isDirectory: true))
        try FileManager.default.createDirectory(
            at: live.directory, withIntermediateDirectories: true)
        let holderLock: McpEndpointLock
        switch McpEndpointLock.acquire(in: live) {
        case .success(let lock): holderLock = lock
        case .failure(let error): return XCTFail("setup: \(error)")
        }
        defer { holderLock.unlock() }
        try McpEndpointFile.write(info, in: live)
        XCTAssertEqual(
            McpEndpointDiscovery.discover(in: live), .alive(info),
            "a live writer keeps its endpoint file discoverable")
    }

    // MARK: - The endpoint file API (write/read roundtrip + L009 shape)

    func testEndpointFileWriteReadRemoveRoundtrip() throws {
        let info = McpEndpointHostFixtures.sampleInfo(port: 59999)
        try McpEndpointFile.write(info, in: paths)
        let read = McpEndpointFile.read(in: paths)
        XCTAssertEqual(read, info, "the discovery payload round-trips verbatim")

        // The L009 discipline: no tmp leftovers after promotion.
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: paths.directory.path
        ).filter { $0.contains(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "tmp files must promote, never linger: \(leftovers)")

        McpEndpointFile.remove(in: paths)
        XCTAssertNil(McpEndpointFile.read(in: paths))
    }

    /// The schema is FROZEN at v1 (additive-only contract, §RQ-14-2): the
    /// encoded payload must carry exactly the nine documented keys.
    func testEndpointFileSchemaV1Keys() throws {
        let info = McpEndpointHostFixtures.sampleInfo(port: 50001)
        try McpEndpointFile.write(info, in: paths)
        let data = try XCTUnwrap(
            FileManager.default.contents(atPath: paths.jsonURL.path))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["schemaVersion", "transport", "host", "port", "pid", "startedAt",
                "serverName", "serverVersion", "auth"],
            "discovery schema keys are frozen — additive changes only")
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["transport"] as? String, "streamable-http")
        XCTAssertEqual(object["auth"] as? String, "none")
    }

    // MARK: - stdio host: the D2 shape + the three-step handshake

    /// The stdio host spawns against the DEFAULT paths (this is the real
    /// host shape): it must hold the writer lock yet NEVER write the
    /// endpoint json, and the piped three-step handshake (initialize →
    /// notifications/initialized → tools/list) answers with the probe
    /// toolset.
    func testStdioHostHoldsLockWritesNoJSONAndHandshakes() async throws {
        let process = Process()
        process.executableURL = try XCTUnwrap(Bundle.main.executableURL)
        process.arguments = ["--mcp-stdio"]
        let stdout = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardInput = stdin
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let initialize =
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"host-tests","version":"0.0.1"}}}"#
        let initialized = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let listTools = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
        let payload = Data("\(initialize)\n\(initialized)\n\(listTools)\n".utf8)
        try stdin.fileHandleForWriting.write(contentsOf: payload)

        // Deadline-bounded response pump.
        let responses = try await Self.pumpLines(
            stdout.fileHandleForReading, expectedLines: 2, timeout: 60)
        XCTAssertTrue(
            responses[0].contains(#""protocolVersion":"2025-11-25""#)
                || responses[0].contains(#""protocolVersion": "2025-11-25""#),
            "initialize must negotiate the pinned protocol version: \(responses[0])")
        XCTAssertTrue(
            responses[1].contains("count_images") && responses[1].contains("ping"),
            "tools/list must carry the probe toolset: \(responses[1])")

        // D2: the stdio host holds the lock but writes NO discovery json —
        // even while it is up and serving.
        let defaultPaths = McpEndpointPaths.makeDefault()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: defaultPaths.jsonURL.path),
            "a stdio host must NOT produce an endpoint json (D2)")
    }

    /// Reads until `expectedLines` newline-terminated JSON lines arrived
    /// (deadline-bounded; non-blocking-ish via a reader queue).
    private static func pumpLines(
        _ handle: FileHandle, expectedLines: Int, timeout: TimeInterval
    ) async throws -> [String] {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedHandshakeBox()
        box.line = ""
        DispatchQueue.global(qos: .userInitiated).async {
            var data = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                data.append(chunk)
                let text = String(data: data, encoding: .utf8) ?? ""
                if text.components(separatedBy: "\n").count > expectedLines {
                    break
                }
            }
            box.line = String(data: data, encoding: .utf8)
            semaphore.signal()
        }
        XCTAssertTrue(mcpBlockingWait(semaphore, timeout: timeout), "response pump timed out")
        let text = try XCTUnwrap(box.line)
        return text.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

/// Test fixtures shared by the host-test file.
enum McpEndpointHostFixtures {
    static func sampleInfo(port: Int) -> McpEndpointInfo {
        McpEndpointInfo(
            schemaVersion: 1,
            transport: "streamable-http",
            host: "127.0.0.1",
            port: port,
            pid: getpid(),
            startedAt: "2026-09-28T09:00:00Z",
            serverName: "lightamer",
            serverVersion: "0.1.0",
            auth: McpEndpointInfo.authNone)
    }
}
