import LightamerCore
import LightamerIOP
import MCP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// UQ-S1 (MCP-UQ batch): the get_schema face — synthesis coverage, row
// closure over the catalog, encoded-default honesty, the default-face
// narrowing, and the production-seam round trips (registry call +
// InMemory SDK client + HTTP SDK client).
// ─────────────────────────────────────────────────────────────────────────────

final class McpGetSchemaTests: XCTestCase {

    private func populatedSeed() async -> [ModuleInstance] {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return await registry.makeDefaultInstances()
            + LightamerIOPRegistry.editingDefaultInstances()
    }

    private func makeRegistry() async -> McpToolRegistry {
        let modules = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(modules)
        let registry = McpToolRegistry()
        await EditingToolset.register(
            into: registry,
            seams: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { modules },
                gate: McpRenderGate(), liveImageURL: { nil }))
        return registry
    }

    private func schemaDocument(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8), options: [])
                as? [String: Any])
    }

    // MARK: - 1: coverage = the catalog roster exactly

    func testGetSchemaCoversExactlyTheCatalogRoster() async throws {
        let schemas = McpSchemaCatalog.synthesize(
            ops: IopCatalog.ops, seed: await populatedSeed())
        XCTAssertEqual(schemas.count, IopCatalog.ops.count)
        XCTAssertEqual(
            Set(schemas.map(\.opName)),
            Set(IopCatalog.ops.map(\.opName)))
        XCTAssertEqual(schemas.count, 19, "catalog coverage pins at 19 ops")
    }

    // MARK: - 2: every catalog key has an annotated row (no silent fallback)

    func testEveryCatalogKeyHasAnAnnotationRow() async throws {
        var missing: [String] = []
        for op in IopCatalog.ops {
            let rows = McpSchemaCatalog.annotations[op.opName] ?? [:]
            for param in op.params where rows[param.name] == nil {
                missing.append("\(op.opName).\(param.name)")
            }
        }
        XCTAssertTrue(
            missing.isEmpty,
            "annotation rows missing (silent fallback hides them): \(missing)")
    }

    // MARK: - 3: defaults are the encoded wire truth


    /// M-5: every cataloged op resolves encoded defaults (seed record or
    /// the GradeCatalog fallback — no null-default holes by absence).
    func testEveryCatalogedOpResolvesEncodedDefaults() async throws {
        let seed = await populatedSeed()
        var missing: [String] = []
        for op in IopCatalog.ops
            where McpSchemaCatalog.encodedDefaults(
                for: op.opName, seed: seed) == nil
        {
            missing.append(op.opName)
        }
        XCTAssertTrue(
            missing.isEmpty,
            "ops without encoded defaults: \(missing)")
    }

    /// E-3 (zcode MCP-UQ review): the OLD M-6 "independent decode" passed
    /// the wire value back through the SAME polluted jsonValue() and
    /// mirrored itself green (`bool(false) == bool(false)`). The defaults
    /// below are INDEPENDENT literals transcribed from the five modules'
    /// Params inits — if a module default ever changes, this test must go
    /// red and the literal updated (honest coupling, not a mirror).
    func testDefaultsEqualTheEncodedDefaults() async throws {
        let seed = await populatedSeed()
        let schemas = McpSchemaCatalog.synthesize(
            ops: IopCatalog.ops, seed: seed)
        let byPath = Dictionary(
            uniqueKeysWithValues: schemas.flatMap(\.fields).map {
                ($0.path, $0)
            })
        // temperature: 1.0 gains are NUMBERS, preset .user is 2.
        let red = try XCTUnwrap(byPath["temperature.red"])
        XCTAssertEqual(red.type, "range:[0,8]")
        XCTAssertEqual(red.defaultValue, .int(1))
        XCTAssertEqual(
            try XCTUnwrap(byPath["temperature.green"]).defaultValue, .int(1))
        XCTAssertEqual(
            try XCTUnwrap(byPath["temperature.blue"]).defaultValue, .int(1))
        XCTAssertEqual(
            try XCTUnwrap(byPath["temperature.preset"]).defaultValue, .int(2))
        // exposure: 0.0 scalars are NUMBERS (not false); the two real
        // booleans stay booleans.
        let exposure = try XCTUnwrap(byPath["exposure.exposure"])
        XCTAssertEqual(exposure.type, "range:[-18,18] (EV)")
        XCTAssertEqual(exposure.range, "[-18,18] EV")
        XCTAssertEqual(exposure.defaultValue, .int(0))
        XCTAssertEqual(
            try XCTUnwrap(byPath["exposure.black"]).defaultValue, .int(0))
        XCTAssertEqual(
            try XCTUnwrap(byPath["exposure.mode"]).defaultValue, .int(0))
        XCTAssertEqual(
            try XCTUnwrap(byPath["exposure.compensateExposureBias"]).defaultValue,
            .bool(false))
        XCTAssertEqual(
            try XCTUnwrap(byPath["exposure.compensateHilitePres"]).defaultValue,
            .bool(true))
        // colisa: 0.0 is a NUMBER (not false).
        let colisa = try XCTUnwrap(byPath["colisa.contrast"])
        XCTAssertEqual(colisa.range, "[-1,1]")
        XCTAssertEqual(colisa.defaultValue, .int(0))
        XCTAssertEqual(
            try XCTUnwrap(byPath["colisa.brightness"]).defaultValue, .int(0))
        XCTAssertEqual(
            try XCTUnwrap(byPath["colisa.saturation"]).defaultValue, .int(0))
        // toneequal: ten 0.0 bands are NUMBERS; non-0/1 neighbors pin the
        // shape (blending 5 / smoothing √2 / method .norm2=4 / details
        // .eigf=4 / iterations 1).
        for band in [
            "ultraDeepBlacks", "deepBlacks", "blacks", "shadows",
            "midtones", "highlights", "whites", "speculars",
            "contrastBoost", "exposureBoost",
        ] {
            XCTAssertEqual(
                try XCTUnwrap(byPath["toneequal.\(band)"]).defaultValue,
                .int(0), "toneequal.\(band)")
        }
        XCTAssertEqual(
            try XCTUnwrap(byPath["toneequal.blending"]).defaultValue, .int(5))
        XCTAssertEqual(
            try XCTUnwrap(byPath["toneequal.method"]).defaultValue, .int(4))
        XCTAssertEqual(
            try XCTUnwrap(byPath["toneequal.details"]).defaultValue, .int(4))
        XCTAssertEqual(
            try XCTUnwrap(byPath["toneequal.iterations"]).defaultValue, .int(1))
        // equalizer: g0-g5 are 0.0 NUMBERS (not false).
        for index in 0...5 {
            XCTAssertEqual(
                try XCTUnwrap(byPath["equalizer.g\(index)"]).defaultValue,
                .int(0), "equalizer.g\(index)")
        }
        // Unrelated faces keep their shape (enum range, null optional).
        let matchStrength = try XCTUnwrap(byPath["colormatch.strength"])
        XCTAssertEqual(matchStrength.range, "[0,1]")
        let matchNull = try XCTUnwrap(byPath["colormatch.sourceStatsHash"])
        XCTAssertEqual(matchNull.defaultValue, .null)
    }

    /// E-3 direct: jsonValue discriminates by CFBoolean identity — 0/1 in
    /// every numeric dress stay numbers, JSON true/false stay booleans.
    func testJsonValueTreatsZeroAndOneAsNumbers() throws {
        for value: Any in [
            NSNumber(value: 0), NSNumber(value: 1),
            NSNumber(value: 0.0), NSNumber(value: 1.0),
            0, 1,
        ] {
            let got = McpSchemaCatalog.jsonValue(value)
            XCTAssertTrue(
                got == .int(0) || got == .int(1),
                "\(type(of: value)) \(value) must be numeric, got \(got)")
        }
        // Genuine JSON booleans (the kCFBoolean face) still land boolean.
        let bools = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(#"{"t":true,"f":false}"#.utf8), options: [])
                as? [String: Any])
        XCTAssertEqual(McpSchemaCatalog.jsonValue(bools["t"]), .bool(true))
        XCTAssertEqual(McpSchemaCatalog.jsonValue(bools["f"]), .bool(false))
    }

    // MARK: - 4: the tool answers through the registry seam

    func testGetSchemaAnswersThroughTheRegistry() async throws {
        let registry = await makeRegistry()
        let output = try await registry.call(name: "get_schema", arguments: [:])
        guard case .text(let text) = output.content.first else {
            return XCTFail("expected text")
        }
        let document = try schemaDocument(text)
        XCTAssertEqual(document["count"] as? Int, 19)
        let ops = try XCTUnwrap(document["ops"] as? [[String: Any]])
        XCTAssertEqual(ops.count, 19)
        let exposure = try XCTUnwrap(
            ops.first { ($0["opName"] as? String) == "exposure" })
        let fields = try XCTUnwrap(exposure["fields"] as? [[String: Any]])
        XCTAssertTrue(fields.contains {
            ($0["path"] as? String) == "exposure.exposure"
                && ($0["range"] as? String) == "[-18,18] EV"
                && !($0["meaning"] as? String ?? "").isEmpty
                && $0["default"] != nil
        })
    }

    // MARK: - 5: the default face narrows with list_iops

    func testGetSchemaNarrowsOnTheDefaultFace() async throws {
        let modules = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(modules, defaultFace: true)
        let registry = McpToolRegistry()
        await EditingToolset.register(
            into: registry,
            seams: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { modules },
                gate: McpRenderGate(), liveImageURL: { nil },
                defaultFace: true))
        let output = try await registry.call(name: "get_schema", arguments: [:])
        guard case .text(let text) = output.content.first else {
            return XCTFail("expected text")
        }
        let document = try schemaDocument(text)
        XCTAssertEqual(document["count"] as? Int, 16)
        let ops = try XCTUnwrap(document["ops"] as? [[String: Any]])
        let names = Set(ops.compactMap { $0["opName"] as? String })
        XCTAssertFalse(names.contains("filmicrgb"))
        XCTAssertFalse(names.contains("sigmoid"))
        XCTAssertFalse(names.contains("agx"))
    }

    // MARK: - 6: the SDK-client round trip (InMemory + HTTP)

    func testGetSchemaRoundTripsOverInMemoryAndHTTP() async throws {
        // InMemory leg.
        let registry = await makeRegistry()
        let pair = await InMemoryTransport.createConnectedPair()
        let server = await McpAdapters.makeServer(registry: registry)
        try await server.start(transport: pair.server)
        let client = MCP.Client(name: "get-schema", version: "0.0.1")
        try await client.connect(transport: pair.client)
        let (content, isError) = try await client.callTool(name: "get_schema")
        XCTAssertNil(isError)
        guard case .text(let text) = McpAdapters.outputContent(
            from: content[0])
        else {
            await client.disconnect()
            await server.stop()
            return XCTFail("get_schema must answer text")
        }
        XCTAssertTrue(text.contains("exposure.exposure"))
        await client.disconnect()
        await server.stop()

        // HTTP leg (the NIO host — the production transport).
        let seams = EditingToolset.Seams(
            session: { nil }, metal: { nil },
            modules: {
                let modules = ModuleRegistry.makeDefault()
                await LightamerIOPRegistry.populate(modules)
                return modules
            },
            gate: McpRenderGate(), liveImageURL: { nil })
        let paths = McpEndpointPaths(
            directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(
                    "mcp-getschema-\(UUID().uuidString)"))
        let handle = try await McpServerController.startHTTPHost(
            paths: paths, editing: seams,
            culling: McpServerController.makeCullingContext(session: { nil }))
        let endpoint = URL(string: "http://127.0.0.1:\(handle.port)/mcp")!
        let httpClient = MCP.Client(name: "get-schema-http", version: "0.0.1")
        try await httpClient.connect(
            transport: HTTPClientTransport(endpoint: endpoint))
        let (httpContent, httpIsError) = try await httpClient.callTool(
            name: "get_schema")
        XCTAssertNil(httpIsError)
        guard case .text(let httpText) = McpAdapters.outputContent(
            from: httpContent[0])
        else {
            await httpClient.disconnect()
            await handle.stop()
            return XCTFail("get_schema must answer text over HTTP")
        }
        XCTAssertTrue(httpText.contains("exposure.exposure"))
        await httpClient.disconnect()
        await handle.stop()
    }
}
