import LightamerCore
import MCP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-1 T2: the tools/list snapshot framework + the PROBE domain.
//
// D-14-CONTEXT-3③: the tool face IS a security face — the tool name set and
// every inputSchema are asserted VERBATIM, so adding/removing/changing a tool
// must consciously edit the snapshot. Domains (checker M-1 分域落点):
//   - probe    → this file (retires at 14-4 T1 together with the tools)
//   - editing  → 14-2 fills this file with its expected list
//   - culling  → 14-3's own McpCullingToolsetTests
//   - the cross-domain union (the frozen 19-tool closed set) → 14-4 T3
//
// The InMemoryTransport leg (research §RQ-14-1③ test dividend) is the third
// host form: the SAME registry kernel asserted end-to-end inside one process.
// ─────────────────────────────────────────────────────────────────────────────

final class McpRegistrySnapshotTests: XCTestCase {

    // MARK: - Snapshot framework (shared by 14-2/14-3/14-4)

    /// Asserts one domain's snapshot: the name set, each descriptor's schema
    /// (verbatim JSON) and the annotations hints. `expected` is the full
    /// expected list for the registry under test (domain-scoped registries
    /// assert their own list; the 14-4 union asserts all 19).
    static func assertSnapshot(
        registry: McpToolRegistry,
        expected: [McpToolDescriptor],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let actual = await registry.descriptors()
        XCTAssertEqual(
            Set(actual.map(\.name)), Set(expected.map(\.name)),
            "TOOL SET CHANGED — edit this snapshot consciously (security face)",
            file: file, line: line)
        for want in expected {
            guard let got = actual.first(where: { $0.name == want.name }) else { continue }
            XCTAssertEqual(
                got.inputSchemaJSON, want.inputSchemaJSON,
                "inputSchema of '\(want.name)' drifted from the snapshot",
                file: file, line: line)
            XCTAssertEqual(
                got.readOnlyHint, want.readOnlyHint, "readOnlyHint of '\(want.name)'",
                file: file, line: line)
            XCTAssertEqual(
                got.destructiveHint, want.destructiveHint,
                "destructiveHint of '\(want.name)'", file: file, line: line)
            XCTAssertEqual(
                got.idempotentHint, want.idempotentHint, "idempotentHint of '\(want.name)'",
                file: file, line: line)
            XCTAssertFalse(
                want.description.isEmpty, "tool description must not be empty",
                file: file, line: line)
        }
    }

    /// Decodes a descriptor's schema JSON (the snapshot asserts the literal
    /// string; this decodes for key-level assertions).
    private static func schemaKeys(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - InMemory harness (connect → body → clean teardown)

    /// Runs `body` against a freshly assembled kernel over InMemoryTransport:
    /// the client's `connect` performs the automatic initialize handshake
    /// (0.12.1 behavior, D4①). Teardown runs on BOTH paths.
    private func withServer(
        registry: McpToolRegistry,
        _ body: (Client) async throws -> Void
    ) async throws {
        let pair = await InMemoryTransport.createConnectedPair()
        let server = await McpAdapters.makeServer(registry: registry)
        try await server.start(transport: pair.server)
        let client = Client(name: "snapshot-tests", version: "0.0.1")
        try await client.connect(transport: pair.client)
        do {
            try await body(client)
        } catch {
            await client.disconnect()
            await server.stop()
            throw error
        }
        await client.disconnect()
        await server.stop()
    }

    private func makeProbeRegistry() async -> McpToolRegistry {
        await McpServerController.makeRegistry(storeProvider: { nil })
    }

    // MARK: - Editing domain snapshot (Plan 14-2; atomic per-task evolution)

    /// The editing face as the hosts assemble it (probe registry + editing
    /// tools). T1 pinned render_preview; T2 adds load_image + apply_params;
    /// T3/T4 extend — each task edits THIS snapshot in its own commit.
    func testEditingDomainSnapshot() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-snap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let capture = temp.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        let image = capture.appendingPathComponent("snap.ARW")
        try Data(repeating: 0xCD, count: 8).write(to: image)
        let store = SessionIndexStore(sessionRoot: temp)
        _ = try await store.openSession(
            root: temp,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: [
                    SessionScanEntry(relPath: "Capture/snap.ARW", mtime: 0, size: 8),
                ]))
                continuation.finish()
            })

        let seams = EditingToolset.Seams(
            session: { (store, temp) },
            metal: { nil },
            modules: { ModuleRegistry() },
            gate: McpRenderGate(),
            liveImageURL: { nil })
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: seams)
        try await Self.assertSnapshot(
            registry: registry,
            expected: [
                McpToolDescriptor(
                    name: "apply_params",
                    description: "apply",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"ops":{"type":"array","minItems":1,"description":"Module-level upserts","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer","default":0},"params":{"type":"object","description":"Partial params JSON overlaid on the instance (keys per list_iops)"},"enabled":{"type":"boolean"},"remove":{"type":"boolean","default":false}},"required":["opName"]}}},"required":["relPath","ops"]}"#,
                    destructiveHint: true),
                McpToolDescriptor(
                    name: "list_iops",
                    description: "list",
                    inputSchemaJSON: #"{"type":"object","properties":{},"required":[]}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "load_image",
                    description: "load",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"}},"required":["relPath"]}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "render_preview",
                    description: "rendered",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"longEdge":{"type":"integer","minimum":1,"maximum":2048,"default":1024,"description":"Output long edge in px (rendered in-pipe at this size)"},"quality":{"type":"integer","minimum":1,"maximum":90,"default":85,"description":"JPEG quality (percent)"}},"required":["relPath"]}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "export_image",
                    description: "export",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"format":{"type":"string","enum":["jpeg","png","tiff","heic","avif","webp"],"default":"jpeg"},"quality":{"type":"integer","minimum":1,"maximum":100,"default":90,"description":"Lossy formats only"},"sizing":{"type":"object","properties":{"mode":{"type":"string","enum":["original","longEdge","shortEdge"],"default":"original"},"px":{"type":"integer","minimum":1,"description":"Required for longEdge/shortEdge"}}},"colorSpace":{"type":"string","enum":["sRGB","displayP3","adobeRGB","proPhoto","rec2020"],"default":"sRGB"},"yiyin":{"type":"boolean","default":false,"description":"Render through the image's existing yiyin frame/watermark configuration"}},"required":["relPath"]}"#,
                    destructiveHint: true),
            ])
    }

    // MARK: - Probe domain snapshot

    func testProbeDomainSnapshot() async throws {
        let registry = await makeProbeRegistry()
        // The expected side mirrors the registration source verbatim (a
        // schema edit must change BOTH — that's the snapshot's point). Only
        // the name/schema/hints face is pinned here; descriptions assert
        // non-empty in the framework.
        try await Self.assertSnapshot(
            registry: registry,
            expected: [
                McpToolDescriptor(
                    name: "ping",
                    description: "probe",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"echo":{"type":"string","description":"Text to echo back"}}}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "count_images",
                    description: "probe",
                    inputSchemaJSON: #"{"type":"object","properties":{}}"#,
                    readOnlyHint: true),
            ])
    }

    func testProbeSchemaKeyShape() async throws {
        let registry = await makeProbeRegistry()
        let descriptors = await registry.descriptors()
        let ping = try XCTUnwrap(descriptors.first { $0.name == "ping" })
        let pingSchema = try Self.schemaKeys(ping.inputSchemaJSON)
        XCTAssertEqual(
            Set(pingSchema.keys), ["type", "properties"],
            "ping schema top-level keys pinned")
        let pingProperties = try XCTUnwrap(pingSchema["properties"] as? [String: Any])
        XCTAssertEqual(Set(pingProperties.keys), ["echo"])
        XCTAssertEqual(pingSchema["type"] as? String, "object")

        let count = try XCTUnwrap(descriptors.first { $0.name == "count_images" })
        let countSchema = try Self.schemaKeys(count.inputSchemaJSON)
        XCTAssertEqual(
            (countSchema["properties"] as? [String: Any])?.keys.count, 0,
            "count_images takes no parameters")
    }

    // MARK: - InMemoryTransport: the third host form, end-to-end in-process

    /// Server (kernel) ↔ client over InMemoryTransport: connect (auto
    /// initialize) → tools/list echoes descriptors COMPLETE
    /// (name/description/inputSchema/annotations).
    func testInMemoryToolsListEchoesRegistry() async throws {
        let registry = await makeProbeRegistry()
        let descriptors = await registry.descriptors()
        try await withServer(registry: registry) { client in
            let (tools, nextCursor) = try await client.listTools()
            XCTAssertNil(nextCursor, "closed probe set fits one page")
            XCTAssertEqual(Set(tools.map(\.name)), ["ping", "count_images"])

            let ping = try XCTUnwrap(tools.first { $0.name == "ping" })
            XCTAssertEqual(
                ping.description,
                descriptors.first { $0.name == "ping" }?.description,
                "tools/list echoes the description verbatim")
            XCTAssertTrue(ping.annotations.readOnlyHint == true)
            XCTAssertNil(ping.annotations.destructiveHint)

            // inputSchema: the echoed Value must equal the snapshot's schema
            // VALUE (semantic equality — the SDK's Value encoder does not
            // preserve key order, so text equality lives at the registry
            // layer, pinned by assertSnapshot above).
            let wantSchema = descriptors.first { $0.name == "ping" }?
                .inputSchemaJSON ?? ""
            let wantValue = try JSONDecoder().decode(
                Value.self, from: Data(wantSchema.utf8))
            XCTAssertEqual(
                ping.inputSchema, wantValue,
                "tools/list echoes inputSchema semantically (Value equality)")
        }
    }

    func testInMemoryCallToolPingEcho() async throws {
        let registry = await makeProbeRegistry()
        try await withServer(registry: registry) { client in
            let (content, isError) = try await client.callTool(
                name: "ping", arguments: ["echo": .string("hello")])
            XCTAssertNil(isError)
            XCTAssertEqual(content.count, 1)
            XCTAssertEqual(McpAdapters.outputContent(from: content[0]), .text("hello"))
        }
    }

    func testInMemoryCountImagesWithFixtureStore() async throws {
        // The count_images read leg against a REAL SessionIndexStore
        // (2-row fixture) and the no-session path — the honest shapes.
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-probe-\(UUID().uuidString)", isDirectory: true)
        let sessionRoot = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func write(_ rel: String) throws {
            try Data(repeating: 0xAB, count: 8).write(
                to: sessionRoot.appendingPathComponent(rel))
        }
        func entry(_ rel: String) throws -> SessionScanEntry {
            let values = try sessionRoot.appendingPathComponent(rel).resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            return SessionScanEntry(
                relPath: rel,
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: Int64(values.fileSize ?? 0))
        }

        let store = SessionIndexStore(sessionRoot: sessionRoot)
        try write("a.arw")
        try write("b.arw")
        let entries = try [entry("a.arw"), entry("b.arw")]
        _ = try await store.openSession(
            root: sessionRoot,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: entries))
                continuation.finish()
            })
        defer { Task { await store.close() } }

        let registry = await McpServerController.makeRegistry(storeProvider: { store })
        try await withServer(registry: registry) { client in
            let (content, _) = try await client.callTool(name: "count_images")
            XCTAssertEqual(McpAdapters.outputContent(from: content[0]), .text("rows=2"))
        }

        // The no-session shape (the headless host default).
        let empty = await McpServerController.makeRegistry(storeProvider: { nil })
        try await withServer(registry: empty) { client in
            let (content, _) = try await client.callTool(name: "count_images")
            XCTAssertEqual(McpAdapters.outputContent(from: content[0]), .text("no-session"))
        }
    }

    // MARK: - Typed error mapping + unknown tool

    func testUnknownToolIsTypedInternalError() async throws {
        let registry = await makeProbeRegistry()
        try await withServer(registry: registry) { client in
            // The SDK surfaces the server's MCPError through the client call.
            do {
                _ = try await client.callTool(name: "definitely_not_a_tool")
                XCTFail("expected a JSON-RPC error for an unknown tool")
            } catch let error as MCPError {
                let text = String(describing: error)
                XCTAssertTrue(
                    text.contains("[internalError]"),
                    "typed code must ride the JSON-RPC error text, got: \(text)")
                XCTAssertTrue(text.contains("unknownTool"), "got: \(text)")
            }
        }
    }

    // MARK: - Value ↔ McpJSON conversion (the seam's correctness)

    func testValueToMcpJSONConversion() {
        let value: Value = .object([
            "s": .string("x"),
            "i": .int(3),
            "d": .double(1.5),
            "b": .bool(true),
            "n": .null,
            "a": .array([.int(1), .string("y")]),
            "o": .object(["k": .string("v")]),
        ])
        let json = McpAdapters.mcpJSON(from: value)
        guard case .object(let members) = json else {
            return XCTFail("expected object")
        }
        XCTAssertEqual(members["s"], .string("x"))
        XCTAssertEqual(members["i"], .int(3))
        XCTAssertEqual(members["d"], .double(1.5))
        XCTAssertEqual(members["b"], .bool(true))
        XCTAssertEqual(members["n"], .null)
        XCTAssertEqual(members["a"], .array([.int(1), .string("y")]))
        XCTAssertEqual(members["o"], .object(["k": .string("v")]))
    }

    // MARK: - Render gate (the 14-2/14-3 shared base)

    func testRenderGateSerializesConcurrentBodies() async throws {
        let gate = McpRenderGate()
        let probe = ConcurrencyProbe()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await gate.withRenderGate {
                        await probe.enter()
                        try await Task.sleep(for: .milliseconds(10))
                        await probe.exit()
                    }
                }
            }
            try await group.waitForAll()
        }
        let max = await probe.maxSeen
        XCTAssertEqual(
            max, 1, "render gate is concurrency-1: bodies must never overlap")
    }

    private actor ConcurrencyProbe {
        private var current = 0
        private(set) var maxSeen = 0
        func enter() {
            current += 1
            maxSeen = max(maxSeen, current)
        }
        func exit() { current -= 1 }
    }
}
