import Foundation
import LightamerCore
import MCP

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-1 (D-14-CONTEXT-2): one MCP server kernel × two hosts, orchestrated
// here. The headless fork (--mcp-stdio / --mcp-http) arrives from
// LightamerEntryPoint (the custom @main in LightamerApp.swift) and NEVER
// constructs the SwiftUI App struct nor enters NSApplication.run — the host
// difference is assembly-only, the registry kernel is single-implementation.
//
// T1 scope: the stdio leg (the agent-CLI default transport, zero network
// face) + the --mcp-http route stub (the NIO adapter leg lands in T4). The
// flock writer lock, the endpoint discovery file and the GUI-embedded host
// land in T3/T4 on this same type.
// ─────────────────────────────────────────────────────────────────────────────

/// Host orchestration for the Lightamer MCP server.
enum McpServerController {

    /// The launch modes, spelled exactly as the CLI flags that select them.
    enum LaunchMode: String, CaseIterable {
        case stdio = "--mcp-stdio"
        case http = "--mcp-http"
    }

    /// The server identity reported in `initialize` (serverInfo).
    static let serverName = "lightamer"
    static let serverVersion =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String) ?? "0.1.0"

    /// The LightamerEntryPoint fork probe: scans argv for a headless MCP
    /// flag. Returns false for a normal GUI launch.
    static func headlessModeIfRequested() -> LaunchMode? {
        let arguments = CommandLine.arguments
        return LaunchMode.allCases.first { arguments.contains($0.rawValue) }
    }

    /// Runs the headless server for `mode` and parks the process forever
    /// (stdio: the transport reads stdin from its own task; the entry point
    /// parks via `dispatchMain`). Errors are fatal by design — the failure
    /// semantics inherited decision: the server never swallows exceptions
    /// (a dead process = a closed connection = the client reconnects).
    static func runHeadless(mode: LaunchMode) {
        let stderr = FileHandle.standardError
        Task<Void, Never> {
            do {
                switch mode {
                case .stdio:
                    let server = makeServer()
                    try await server.start(transport: StdioTransport())
                    // Parked: start() returns after the handshake wiring; the
                    // transport's receive loop runs on its own task. The
                    // process stays alive through dispatchMain() below.
                    await Self.log("headless MCP server up (stdio)")
                case .http:
                    // T4 delivers the NIO adapter leg; until then the flag is
                    // an explicit, non-silent rejection (L020: no silent
                    // degradation).
                    stderr.write(
                        "--mcp-http: the NIO Streamable HTTP leg lands in Plan 14-1 T4\n"
                            .data(using: .utf8)!)
                    exit(2)
                }
            } catch {
                stderr.write(
                    "headless MCP server failed: \(error)\n".data(using: .utf8)!)
                exit(1)
            }
        }
        // Never returns — keeps the process alive while the transport tasks
        // pump stdin/stdout (the research §RQ-14-1④ parked shape).
        dispatchMain()
    }

    /// The single kernel: one Server actor over the tool registry. T2 replaces
    /// this placeholder with the McpAdapters assembly over McpToolRegistry
    /// (the probe tools ping/count_images land there).
    private static func makeServer() -> Server {
        Server(
            name: serverName,
            version: serverVersion,
            capabilities: Server.Capabilities(tools: .init(listChanged: false)))
    }

    /// Unified os_log face for the host legs (the GUI side watches the
    /// unified log; headless mirrors stderr where useful).
    static func log(_ message: String) async {
        await MainActor.run {
            AppError.logger.info("mcp: \(message, privacy: .public)")
        }
    }
}
