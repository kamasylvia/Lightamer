import Foundation
import MCP

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-1 T2 (D-14-CONTEXT-1③④): the SDK adapter layer — the ONLY
// SDK-type conversion site (Server actor, Tool, Content, Value convert here
// into the pure-Swift registry seam (McpToolRegistry.swift) and back; an SDK
// upgrade (0.x churn, R1) rewrites this file and nothing else). The other
// MCP/ files import MCP only to WIRE this seam to hosts: the NIO leg
// (McpHTTPTransport), the Bearer valve (McpBearerValidator) and the host
// orchestration (McpServerController) — LightamerCore keeps ZERO import.
// ─────────────────────────────────────────────────────────────────────────────

/// The Server assembly + the bidirectional SDK ↔ registry conversions.
enum McpAdapters {

    /// Assembles ONE Server actor over the shared registry kernel. The HTTP
    /// host calls this once per client session (single transport = single
    /// session — §RQ-14-1③), the stdio host once per process, the InMemory
    /// test leg once per test. All three see the same handlers — the
    /// dual-host behavior-consistency red line is structural here.
    static func makeServer(registry: McpToolRegistry) async -> Server {
        let server = Server(
            name: McpServerController.serverName,
            version: McpServerController.serverVersion,
            capabilities: Server.Capabilities(tools: .init(listChanged: false)))

        await server.withMethodHandler(ListTools.self) { _ in
            let descriptors = await registry.descriptors()
            return ListTools.Result(tools: descriptors.map(tool(from:)))
        }

        await server.withMethodHandler(CallTool.self) { params in
            let arguments = (params.arguments ?? [:]).mapValues(mcpJSON(from:))
            do {
                let output = try await registry.call(name: params.name, arguments: arguments)
                return CallTool.Result(
                    content: output.content.map(content(from:)),
                    isError: output.isError ? true : nil)
            } catch let error as McpToolError {
                // The inherited failure semantics: typed errors surface as
                // JSON-RPC errors carrying the stable code, never silent
                // degradation.
                throw MCPError.internalError("[\(error.code)] \(error.message)")
            }
        }
        return server
    }

    // MARK: - Conversions (the entire SDK surface of Phase 14)

    /// Registry descriptor → SDK Tool. The input schema travels as verbatim
    /// JSON (the snapshot's literal face); a malformed schema string would be
    /// a developer error pinned by the snapshot tests, so the fallback keeps
    /// the shape valid rather than crashing the server.
    static func tool(from descriptor: McpToolDescriptor) -> Tool {
        let schema: Value
        if let decoded = try? JSONDecoder().decode(
            Value.self, from: Data(descriptor.inputSchemaJSON.utf8))
        {
            schema = decoded
        } else {
            schema = .object(["type": .string("object")])
        }
        var annotations = Tool.Annotations()
        annotations.readOnlyHint = descriptor.readOnlyHint
        annotations.destructiveHint = descriptor.destructiveHint
        annotations.idempotentHint = descriptor.idempotentHint
        return Tool(
            name: descriptor.name,
            description: descriptor.description,
            inputSchema: schema,
            annotations: annotations)
    }

    /// SDK `Value` (arguments) → pure-Swift `McpJSON`.
    static func mcpJSON(from value: Value) -> McpJSON {
        switch value {
        case .null: .null
        case .bool(let b): .bool(b)
        case .int(let i): .int(i)
        case .double(let d): .double(d)
        case .string(let s): .string(s)
        case .data(_, let data): .string(data.base64EncodedString())
        case .array(let items): .array(items.map(mcpJSON(from:)))
        case .object(let members): .object(members.mapValues(mcpJSON(from:)))
        }
    }

    /// Registry output content → SDK `Tool.Content`. The NEW `.text(text:)`
    /// shape (the old `.text(_:)` is deprecated in 0.12.1 — D4②, warnings
    /// are not tolerated in the app build).
    static func content(from content: McpToolOutput.Content) -> Tool.Content {
        switch content {
        case .text(let text): .text(text: text, annotations: nil, _meta: nil)
        case .imageBase64(let base64, let mimeType):
            .image(data: base64, mimeType: mimeType, annotations: nil, _meta: nil)
        }
    }

    /// SDK `Tool.Content` → registry output (the InMemory/HTTP test legs
    /// assert through this). Resource/resource-link/audio shapes are not
    /// Phase 14 forms — they degrade to a descriptive text rather than
    /// crashing the test harness.
    static func outputContent(from content: Tool.Content) -> McpToolOutput.Content {
        switch content {
        case .text(let text, _, _): .text(text)
        case .image(let data, let mimeType, _, _):
            .imageBase64(data, mimeType: mimeType)
        case .audio(let data, let mimeType, _, _):
            .text("<audio content \(mimeType), \(data.count) b64 chars — not a Phase 14 shape>")
        case .resource(let resource, _, _):
            .text("<embedded resource \(resource.uri) — not a Phase 14 shape>")
        case .resourceLink(let uri, _, _, _, _, _):
            .text("<resource link \(uri) — not a Phase 14 shape>")
        }
    }
}
