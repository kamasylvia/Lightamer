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
//   - the cross-domain union (the frozen 27-tool closed set) → 14-4 T3
//
// The InMemoryTransport leg (research §RQ-14-1③ test dividend) is the third
// host form: the SAME registry kernel asserted end-to-end inside one process.
// ─────────────────────────────────────────────────────────────────────────────

final class McpRegistrySnapshotTests: XCTestCase {

    // MARK: - Snapshot framework (shared by 14-2/14-3/14-4)

    /// Asserts one domain's snapshot: the name set, each descriptor's schema
    /// (verbatim JSON) and the annotations hints. `expected` is the full
    /// expected list for the registry under test (domain-scoped registries
    /// assert their own list; the 14-4 union asserts all 27).
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
        await McpServerController.makeRegistry()
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
                    // M7-4-01: apply_params gains the item-level note
                    // property (MCP2-09 — this domain snapshot edits
                    // consciously, the same batch the union layer edits).
                    name: "apply_params",
                    description: "apply",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"ops":{"type":"array","minItems":1,"description":"Module-level upserts","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer","default":0},"params":{"type":"object","description":"Partial params JSON overlaid on the instance (keys per list_iops)"},"enabled":{"type":"boolean"},"remove":{"type":"boolean","default":false}},"required":["opName"]}},"note":{"type":"string","minLength":1,"description":"ITEM-level edit note attached to the history commit (distinct from the document-level note set via append_note)"}},"required":["relPath","ops"]}"#,
                    destructiveHint: true),
                McpToolDescriptor(
                    // M7-4-01 (MCP2-08): copy_adjustments joins the
                    // editing domain (7→9, the O4 pair — this domain
                    // snapshot edits consciously).
                    name: "copy_adjustments",
                    description: "copy",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"source":{"type":"string","description":"A library image id (digits) or an open-session relPath"}},"required":["source"]}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    // M7-4-01 (MCP2-08): paste_adjustments joins the
                    // editing domain (the O4 pair's write face).
                    name: "paste_adjustments",
                    description: "paste",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"source":{"type":"string","description":"A library image id (digits) or an open-session relPath (the copy_adjustments addressing)"},"targets":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":1000,"description":"Open-session relPaths to paste onto"},"note":{"type":"string","minLength":1,"description":"ITEM-level edit note attached to each history commit (distinct from the document-level note set via append_note)"},"include":{"type":"array","items":{"type":"string","format":"uuid"},"description":"instanceId subset from copy_adjustments (default: every transferable instance)"},"includeDrt":{"type":"boolean","default":true,"description":"false drops the source's DRT row"},"version":{"type":"string","description":"A copy_adjustments versions[] id (default: the active chain)"}},"required":["source","targets"]}"#,
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
                        #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"longEdge":{"type":"integer","minimum":1,"maximum":2048,"default":1024,"description":"Output long edge in px (rendered in-pipe at this size)"},"quality":{"type":"integer","minimum":1,"maximum":90,"default":85,"description":"JPEG quality (percent)"},"region":{"type":"object","properties":{"x":{"type":"number","minimum":0,"maximum":1},"y":{"type":"number","minimum":0,"maximum":1},"w":{"type":"number","exclusiveMinimum":0,"maximum":1},"h":{"type":"number","exclusiveMinimum":0,"maximum":1}},"required":["x","y","w","h"],"description":"Normalized 0..1 ROI {x,y,w,h} relative to the RENDERED output frame (orientation already normalized); cropped after the render, decoupled from longEdge"},"compare":{"type":"string","enum":["none","root"],"default":"root","description":"none = the edited image only; root (default) = the pristine (edit-free) image rides along for the before/after loop"}},"required":["relPath"]}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    // M7-3 (MCP2-05): list_luts joins the editing domain
                    // (6→7, D-M7-3-4) — this domain snapshot edits consciously,
                    // the same batch the union layer edits (M5-1-03 形).
                    name: "list_luts",
                    description: "list",
                    inputSchemaJSON: #"{"type":"object","properties":{},"required":[]}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "export_image",
                    description: "export",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"format":{"type":"string","enum":["jpeg","png","tiff","heic","avif","webp"],"default":"jpeg"},"quality":{"type":"integer","minimum":1,"maximum":100,"default":90,"description":"Lossy formats only"},"sizing":{"type":"object","properties":{"mode":{"type":"string","enum":["original","longEdge","shortEdge"],"default":"original"},"px":{"type":"integer","minimum":1,"description":"Required for longEdge/shortEdge"}}},"colorSpace":{"type":"string","enum":["sRGB","displayP3","adobeRGB","proPhoto","rec2020"],"default":"sRGB"},"yiyin":{"type":"boolean","default":false,"description":"Render through the image's existing yiyin frame/watermark configuration"}},"required":["relPath"]}"#,
                    destructiveHint: true),
                McpToolDescriptor(
                    // M5-1-03 (checker E3): match_color joins the editing
                    // domain — this domain snapshot edits consciously.
                    name: "match_color",
                    description: "match",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"reference":{"type":"string","description":"Reference image: a library image id (digits) or an open-session relPath"},"targets":{"oneOf":[{"type":"string"},{"type":"array","items":{"type":"string"}}],"maxItems":30,"description":"Target relPath(s) relative to the session root; default = the editor's current image"},"strength":{"type":"number","minimum":0,"maximum":1,"default":1,"description":"The solve/identity blend"},"solver":{"type":"string","enum":["gaussian-ot","reinhard","cdf"],"default":"gaussian-ot"},"attach":{"type":"boolean","default":true,"description":"false = return the params for apply_params instead of writing"}},"required":["reference"]}"#,
                    destructiveHint: true),
            ])
    }

    // MARK: - Probe face RETIREMENT (Plan 14-4 T1)

    /// The 14-1 probe pair (ping/count_images) is retired: a bare kernel
    /// (no editing/culling seams) must expose NO tools at all — the tool
    /// face is exactly the closed closed-set count, never a probe residue.
    func testProbeFaceRetiredFromBareRegistry() async throws {
        let registry = await makeProbeRegistry()
        let descriptors = await registry.descriptors()
        XCTAssertTrue(
            descriptors.isEmpty,
            "a bare registry must be empty after the probe retirement, got: "
                + "\(descriptors.map(\.name))")
        let registryWithFaces = await McpServerController.makeRegistry(
            editing: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }),
            culling: McpServerController.makeCullingContext(session: { nil }))
        let names = await registryWithFaces.descriptors().map(\.name)
        XCTAssertFalse(names.contains("ping"), "ping is retired")
        XCTAssertFalse(names.contains("count_images"), "count_images is retired")
        XCTAssertEqual(
            names.count, 23,
            "the editing+culling closed face is exactly 23 tools "
                + "(M7-4 copy/paste joined the editing domain): \(names.sorted())")
    }

    /// A minimal LOCAL double for the transport-echo tests (the registry
    /// seam registers any descriptor; no probe tools involved).
    private func makeSyntheticRegistry() async -> McpToolRegistry {
        let registry = McpToolRegistry()
        await registry.register(
            McpToolDescriptor(
                name: "synthetic_echo",
                description: "test double: echoes its `echo` argument",
                inputSchemaJSON:
                    #"{"type":"object","properties":{"echo":{"type":"string","description":"Text to echo back"}}}"#,
                readOnlyHint: true),
            handler: { arguments in
                .text(arguments["echo"]?.stringValue ?? "pong")
            })
        return registry
    }

    // MARK: - InMemoryTransport: the third host form, end-to-end in-process

    /// Server (kernel) ↔ client over InMemoryTransport: connect (auto
    /// initialize) → tools/list echoes descriptors COMPLETE
    /// (name/description/inputSchema/annotations).
    func testInMemoryToolsListEchoesRegistry() async throws {
        let registry = await makeSyntheticRegistry()
        let descriptors = await registry.descriptors()
        try await withServer(registry: registry) { client in
            let (tools, nextCursor) = try await client.listTools()
            XCTAssertNil(nextCursor, "the closed face fits one page")
            XCTAssertEqual(Set(tools.map(\.name)), ["synthetic_echo"])

            let echo = try XCTUnwrap(tools.first { $0.name == "synthetic_echo" })
            XCTAssertEqual(
                echo.description,
                descriptors.first { $0.name == "synthetic_echo" }?.description,
                "tools/list echoes the description verbatim")
            XCTAssertTrue(echo.annotations.readOnlyHint == true)
            XCTAssertNil(echo.annotations.destructiveHint)

            // inputSchema: the echoed Value must equal the snapshot's schema
            // VALUE (semantic equality — the SDK's Value encoder does not
            // preserve key order, so text equality lives at the registry
            // layer, pinned by assertSnapshot above).
            let wantSchema = descriptors.first { $0.name == "synthetic_echo" }?
                .inputSchemaJSON ?? ""
            let wantValue = try JSONDecoder().decode(
                Value.self, from: Data(wantSchema.utf8))
            XCTAssertEqual(
                echo.inputSchema, wantValue,
                "tools/list echoes inputSchema semantically (Value equality)")
        }
    }

    func testInMemoryCallToolEcho() async throws {
        let registry = await makeSyntheticRegistry()
        try await withServer(registry: registry) { client in
            let (content, isError) = try await client.callTool(
                name: "synthetic_echo", arguments: ["echo": .string("hello")])
            XCTAssertNil(isError)
            XCTAssertEqual(content.count, 1)
            XCTAssertEqual(McpAdapters.outputContent(from: content[0]), .text("hello"))
        }
    }

    // MARK: - Write-call counter (Plan 14-4 T2: the launcher panel's
    // no-write-back face counts requiresWriter CALLS)

    func testWriteCallCounterCountsOnlyTheWriteFace() async throws {
        let registry = McpToolRegistry()
        await registry.register(
            McpToolDescriptor(
                name: "counter_read",
                description: "read-face double",
                inputSchemaJSON: #"{"type":"object","properties":{}}"#,
                readOnlyHint: true),
            handler: { _ in .text("r") })
        await registry.register(
            McpToolDescriptor(
                name: "counter_write",
                description: "write-face double",
                inputSchemaJSON: #"{"type":"object","properties":{}}"#,
                destructiveHint: true),
            requiresWriter: true,
            handler: { _ in .text("w") })

        let before = await registry.writeCallCount
        _ = try await registry.call(name: "counter_read", arguments: [:])
        _ = try await registry.call(name: "counter_read", arguments: [:])
        let afterReads = await registry.writeCallCount
        _ = try await registry.call(name: "counter_write", arguments: [:])
        let afterWrite = await registry.writeCallCount
        // A writer-gated REJECTION (read-only mode) must NOT count — the
        // counter tracks completed write-face calls.
        await registry.setWriterCheck { false }
        do { _ = try await registry.call(name: "counter_write", arguments: [:]) }
        catch let error as McpToolError {
            XCTAssertEqual(error.code, "serverReadOnly")
        }
        let afterRejection = await registry.writeCallCount

        XCTAssertEqual(before, 0)
        XCTAssertEqual(afterReads, 0, "read-face calls never count")
        XCTAssertEqual(afterWrite, 1, "one write-face call counted")
        XCTAssertEqual(afterRejection, 1, "a gated-out write is not a write-back")
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
