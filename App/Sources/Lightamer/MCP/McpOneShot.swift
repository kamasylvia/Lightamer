// Copyright (c) 2026 the Lightamer authors (GPL-3.0). Shape derived from
// SpektraLab RFC-026 (c) Hanze Qiu and contributors (GPL-3.0), upstream
// commit 85c9c16 — see NOTICE §V.
import Foundation
import MCP

// ─────────────────────────────────────────────────────────────────────────────
// UQ-S3 (MCP-UQ batch): the one-shot CLI gate — `Lightamer mcp call <tool>
// '<json>'` / `Lightamer mcp list`. Read the discovery file → SDK HTTP
// client handshake → tools/call (or tools/list) → print → exit. Protocol
// reuse only: the SDK client + discovery faces, zero new tool surface.
//
// ENTRY: LightamerEntryPoint probes `tailIfRequested()` BEFORE the
// GUI fork (the --mcp-stdio precedent: never constructs the SwiftUI App).
// Exit codes mirror the upstream AgentError shape: 0 = done, 1 = failed
// (ours — render/decode/server-side), 2 = refused (caller's to fix:
// app off / MCP off / unknown tool / bad JSON / control not held).
// Stdout carries ONLY the result JSON on success (pipe-safe); every
// diagnostic rides stderr (the LightCraft docs/mcp.md discipline).
// ─────────────────────────────────────────────────────────────────────────────

/// Why a one-shot call did not do what it asked.
enum McpOneShotError: Error, Sendable, Equatable {
    case refused(String)
    case failed(String)

    var exitCode: Int32 {
        switch self {
        case .refused: 2
        case .failed: 1
        }
    }

    var message: String {
        switch self {
        case .refused(let s), .failed(let s): s
        }
    }
}

enum McpOneShot {

    static let usage = """
    usage: Lightamer mcp <command>

      list [--list]             list the MCP tools of the running app
      call <tool> '<json>'    call one tool (args default '{}'), print the result JSON

    Reads the MCP discovery file, handshakes the app's HTTP endpoint, runs
    one call and exits. Start the app with MCP enabled first (Settings ▸ MCP).
    """

    // MARK: - Entry fork (the LightamerEntryPoint probe)

    /// argv probe: `mcp` as the first token selects this gate. Returns the
    /// tail argv (after `mcp`) when selected, nil for a normal launch.
    static func tailIfRequested(
        arguments: [String] = CommandLine.arguments
    ) -> [String]? {
        guard arguments.count >= 2, arguments[1] == "mcp" else { return nil }
        return Array(arguments.dropFirst(2))
    }

    /// Parse + run; returns the exit code. Never returns without exiting
    /// the caller's process — the entry point calls `exit(run(tail))`.
    static func run(_ tail: [String]) async -> Int32 {
        do {
            let command = try parse(tail)
            switch command {
            case .list:
                try await runList()
            case .call(let tool, let args):
                try await runCall(tool: tool, args: args)
            }
            return 0
        } catch let error as McpOneShotError {
            Self.stderr(error.message + "\n")
            return error.exitCode
        } catch {
            Self.stderr("mcp: \(error)\n")
            return 1
        }
    }

    // MARK: - Parsing (pure — testable without a server)

    enum Command: Equatable {
        case list
        case call(tool: String, args: String)
    }

    static func parse(_ tail: [String]) throws -> Command {
        // M-10: bare `mcp` / help exits 2 (the refused arm — a conscious
        // choice: usage rides stderr, stdout stays result-pure).
        guard let verb = tail.first else {
            throw McpOneShotError.refused(usage)
        }
        switch verb {
        case "list", "--list":
            guard tail.count == 1 else {
                throw McpOneShotError.refused("mcp list takes no arguments")
            }
            return .list
        case "call":
            guard tail.count >= 2 else {
                throw McpOneShotError.refused(
                    "mcp call needs a tool name — `Lightamer mcp list` shows them")
            }
            guard tail.count <= 3 else {
                throw McpOneShotError.refused(
                    "mcp call takes <tool> and one JSON argument object")
            }
            let args = tail.count == 3 ? tail[2] : "{}"
            guard args.data(using: .utf8).flatMap({
                try? JSONSerialization.jsonObject(with: $0, options: [])
                    as? [String: Any]
            }) != nil else {
                throw McpOneShotError.refused(
                    "mcp call arguments must be a JSON object, got: \(args)")
            }
            return .call(tool: tail[1], args: args)
        case "help", "-h", "--help":
            throw McpOneShotError.refused(usage)
        default:
            throw McpOneShotError.refused(
                "unknown mcp command '\(verb)' — \(usage)")
        }
    }

    // MARK: - Execution (discovery → handshake → call → print)

    /// Resolve the live endpoint or throw the typed refused face (app off
    /// vs MCP off distinguished by the discovery outcome). The default
    /// paths ride `headlessEndpointPaths` (DEBUG test-domain env override
    /// + release default — the L036 discipline, same as the headless arms).
    static func resolveEndpoint(
        in paths: McpEndpointPaths = McpServerController.headlessEndpointPaths
    ) throws -> McpEndpointInfo {
        switch McpEndpointDiscovery.discover(in: paths) {
        case .alive(let info):
            return info
        case .noEndpointFile, .staleResidueRemoved:
            throw McpOneShotError.refused(
                "no live Lightamer MCP endpoint — start the app with MCP "
                    + "enabled (Settings ▸ MCP), then retry")
        }
    }

    /// The Bearer header value for the endpoint (nil = auth "none" — the
    /// loopback default needs no token).
    static func bearerToken(for info: McpEndpointInfo) throws -> String? {
        guard info.auth == McpEndpointInfo.authBearer else { return nil }
        guard let token = McpBearerToken.load() else {
            throw McpOneShotError.refused(
                "the endpoint requires Bearer auth but no token is stored — "
                    + "re-enable MCP in Settings ▸ MCP to mint one")
        }
        return token
    }

    static func endpointURL(for info: McpEndpointInfo) -> URL? {
        URL(string: "http://\(info.host):\(info.port)/mcp")
    }

    private static func runList() async throws {
        let info = try resolveEndpoint()
        let token = try bearerToken(for: info)
        guard let url = endpointURL(for: info) else {
            throw McpOneShotError.failed("malformed endpoint in discovery file")
        }
        let transport = HTTPClientTransport(
            endpoint: url,
            requestModifier: Self.authorize(token))
        let client = MCP.Client(name: "lightamer-mcp-oneshot", version: "0.0.1")
        do {
            try await client.connect(transport: transport)
            let (tools, _) = try await client.listTools()
            let names = tools.map(\.name).sorted()
            Self.stdout(names.joined(separator: "\n") + "\n")
            await client.disconnect()
        } catch {
            await client.disconnect()
            throw Self.clientError(error)
        }
    }

    private static func runCall(tool: String, args: String) async throws {
        let info = try resolveEndpoint()
        let token = try bearerToken(for: info)
        guard let url = endpointURL(for: info) else {
            throw McpOneShotError.failed("malformed endpoint in discovery file")
        }
        let arguments = try Self.sdkArguments(from: args)
        let transport = HTTPClientTransport(
            endpoint: url,
            requestModifier: Self.authorize(token))
        let client = MCP.Client(name: "lightamer-mcp-oneshot", version: "0.0.1")
        do {
            try await client.connect(transport: transport)
            let (content, isError) = try await client.callTool(
                name: tool, arguments: arguments)
            await client.disconnect()
            Self.stdout(try Self.resultJSON(content: content, isError: isError))
        } catch {
            await client.disconnect()
            throw Self.clientError(error)
        }
    }

    /// The Bearer request modifier (nil token = identity).
    static func authorize(
        _ token: String?
    ) -> (URLRequest) -> URLRequest {
        return { request in
            guard let token else { return request }
            var modified = request
            modified.setValue(
                "Bearer \(token)", forHTTPHeaderField: "Authorization")
            return modified
        }
    }

    /// The JSON-object args string → SDK Value arguments.
    static func sdkArguments(from args: String) throws -> [String: Value] {
        guard let data = args.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(
                  Value.self, from: data),
              case .object(let object) = decoded
        else {
            throw McpOneShotError.refused(
                "mcp call arguments must be a JSON object, got: \(args)")
        }
        return object
    }

    /// Tool content → the stdout JSON document.
    static func resultJSON(
        content: [Tool.Content], isError: Bool?
    ) throws -> String {
        let payloads = content.map { element -> [String: Any] in
            switch McpAdapters.outputContent(from: element) {
            case .text(let text):
                return ["type": "text", "text": text]
            case .imageBase64(let base64, let mimeType):
                return [
                    "type": "image", "mimeType": mimeType, "data": base64,
                ]
            }
        }
        let document: [String: Any] = [
            "content": payloads,
            "isError": isError ?? false,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: document, options: [.sortedKeys, .prettyPrinted])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// Map a client/transport throw onto the typed faces. Tool-level typed
    /// errors ([code] message) ride the JSON-RPC error text — surface them
    /// with the refused exit (they are the caller's to fix). M-7: the
    /// caller-fault codes (unknown op/preset, bad filter/params/roi,
    /// keyword separator, preset mismatch, live-image conflict) refuse;
    /// render/export/model/internal failures + transport throws fail (ours
    /// to report). R2-M2: `imageLiveInEditor` refuses (close the image in
    /// the GUI and retry — the caller dissolves it, the serverReadOnly
    /// sibling precedent); `renderTimeout` stays failed (a server-side
    /// 30s budget breach, not a caller fault).
    static func clientError(_ error: Error) -> McpOneShotError {
        let text = String(describing: error)
        if text.contains("unknownTool")
            || text.contains("[unknownOp]")
            || text.contains("[unknownPreset]")
            || text.contains("[invalidParams]")
            || text.contains("[invalidFilter]")
            || text.contains("[notSessionMember]")
            || text.contains("[imageLiveInEditor]")
            || text.contains("[roiOutOfBounds]")
            || text.contains("[keywordContainsSeparator]")
            || text.contains("[exportPresetNotApplicable]")
            || text.contains("[controlNotHeld]")
            || text.contains("[controlRevokedByUser]")
            || text.contains("[controlBusy]")
            || text.contains("[serverReadOnly]")
            || text.contains("[projectReadOnly]")
        {
            return .refused(text)
        }
        return .failed(text)
    }

    // MARK: - Output (stdout = result only; diagnostics = stderr)

    /// Test-injectable sinks (nonisolated(unsafe): the one-shot gate is a
    /// single-flight CLI process — no concurrent mutation exists).
    nonisolated(unsafe) static var stdoutSink: (String) -> Void = {
        FileHandle.standardOutput.write(Data($0.utf8))
    }
    nonisolated(unsafe) static var stderrSink: (String) -> Void = {
        FileHandle.standardError.write(Data($0.utf8))
    }

    static func stdout(_ text: String) { stdoutSink(text) }
    static func stderr(_ text: String) { stderrSink(text) }
}
