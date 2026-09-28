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
// T1 delivered the stdio leg + the --mcp-http stub. T2 swaps the placeholder
// for the registry kernel (McpAdapters.makeServer over McpToolRegistry) and
// lands the PROBE toolset (ping/count_images — a non-final face, retired at
// 14-4 T1 per plan; the closed 19-tool set excludes it). The flock writer
// lock, the endpoint discovery file and the GUI-embedded host land in T3/T4.
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

    /// The open-session index seam for the read-only probe tool: the headless
    /// host has NO open session (returns nil → `no-session`); the GUI host
    /// (14-4) injects its live SessionIndexController store. Tests inject a
    /// fixture store. This stays nil-for-nil honest: the probe never opens
    /// a store by itself.
    typealias StoreProvider = @Sendable () async -> SessionIndexStore?

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
    ///
    /// T3: the stdio host now acquires the endpoint WRITER LOCK (write-right
    /// is transport-independent, §RQ-14-2) but writes NO endpoint json
    /// (D2 — nobody discovers a stdio host). Losing the lock is NOT fatal:
    /// the host starts READ-ONLY and write-face tools fail with
    /// `serverReadOnly` (the T2 registry writer-check hook).
    static func runHeadless(mode: LaunchMode) {
        let stderr = FileHandle.standardError
        Task<Void, Never> {
            do {
                switch mode {
                case .stdio:
                    let paths = McpEndpointPaths.makeDefault()
                    let lock: McpEndpointLock?
                    switch McpEndpointLock.acquire(in: paths) {
                    case .success(let acquired):
                        lock = acquired
                        await log("headless MCP stdio host: writer lock held")
                    case .failure(.heldByOther):
                        lock = nil
                        await log(
                            "headless MCP stdio host: writer lock held elsewhere — READ-ONLY mode"
                        )
                    case .failure(.ioError(let reason)):
                        stderr.write(
                            "headless MCP stdio host: lock acquire failed: \(reason)\n"
                                .data(using: .utf8)!)
                        exit(1)
                    }
                    let registry = await makeRegistry(storeProvider: { nil })
                    await registry.setWriterCheck { @Sendable in lock != nil }
                    let server = await McpAdapters.makeServer(registry: registry)
                    try await server.start(transport: StdioTransport())
                    await log("headless MCP server up (stdio)")
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

    // MARK: - The single kernel (registry assembly)

    /// The probe toolset (non-final face — retired at 14-4 T1, plan
    /// registered). `ping` echoes; `count_images` reads the open session's
    /// index row count through the read-only `SessionIndexStore.query` face
    /// (SessionIndexStore.swift:561-584, the same consumption point 14-3's
    /// list_photos formalizes). Both read-only.
    static func makeRegistry(
        storeProvider: @escaping StoreProvider
    ) async -> McpToolRegistry {
        let registry = McpToolRegistry()

        await registry.register(
            McpToolDescriptor(
                name: "ping",
                description: "Probe tool: echoes its `echo` argument back as text "
                    + "(defaults to \"pong\"). Non-final probe face; retires when the "
                    + "Phase 14 tool set freezes.",
                inputSchemaJSON:
                    #"{"type":"object","properties":{"echo":{"type":"string","description":"Text to echo back"}}}"#,
                readOnlyHint: true
            ),
            handler: { arguments in
                let echo = arguments["echo"]?.stringValue ?? "pong"
                return .text(echo)
            })

        await registry.register(
            McpToolDescriptor(
                name: "count_images",
                description: "Probe tool: number of indexed rows in the CURRENTLY OPEN "
                    + "Lightamer session (\"no-session\" when the host has no open "
                    + "session). Read-only. Non-final probe face; retires when the "
                    + "Phase 14 tool set freezes.",
                inputSchemaJSON: #"{"type":"object","properties":{}}"#,
                readOnlyHint: true
            ),
            handler: { _ in
                guard let store = await storeProvider() else {
                    return .text("no-session")
                }
                let rows = try await store.query(groups: [], sort: nil, limit: nil)
                return .text("rows=\(rows.count)")
            })

        return registry
    }

    /// Unified os_log face for the host legs (the GUI side watches the
    /// unified log; headless mirrors stderr where useful).
    static func log(_ message: String) async {
        await MainActor.run {
            AppError.logger.info("mcp: \(message, privacy: .public)")
        }
    }

    // MARK: - DEBUG: the two-process lock fixture (T3 tests)

    #if DEBUG
    /// The `-la_mcp_hold_lock <dir>` fixture mode: acquire the writer lock
    /// in `<dir>`, print LOCKED, then park until stdin closes (EOF = the
    /// parent is done with us) or the process is signaled. The McpHostTests
    /// spawn THIS HOST BINARY with the flag to exercise the real
    /// two-process flock states — mutex, exit-releases, crash-kernel-releases
    /// — against the very binary that ships (never ships: #if DEBUG).
    ///
    /// Shape mirrors the DEBUG probe precedent (`-la_sidecar_probe`).
    static func holdLockFixtureIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-la_mcp_hold_lock"),
            arguments.count > index + 1
        else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        let paths = McpEndpointPaths(directory: directory)
        switch McpEndpointLock.acquire(in: paths) {
        case .success:
            print("LOCKED \(paths.lockURL.path)")
            FileHandle.standardOutput.synchronizeFile()
        case .failure(let error):
            print("LOCK-FAIL \(error)")
            FileHandle.standardOutput.synchronizeFile()
            exit(3)
        }
        // Park until stdin EOF (the test harness closes the pipe), then
        // exit cleanly — releasing the lock through the kernel.
        let _ = FileHandle.standardInput.readDataToEndOfFile()
        exit(0)
    }
    #endif
}
