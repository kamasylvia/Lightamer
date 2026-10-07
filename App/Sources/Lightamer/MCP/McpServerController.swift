import Foundation
import LightamerCore
import LightamerIOP
import MCP

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-1 (D-14-CONTEXT-2): one MCP server kernel × two hosts, orchestrated
// here. The headless fork (--mcp-stdio / --mcp-http) arrives from
// LightamerEntryPoint (the custom @main in LightamerApp.swift) and NEVER
// constructs the SwiftUI App struct nor enters NSApplication.run — the host
// difference is assembly-only, the registry kernel is single-implementation.
//
// Plan 14-4 T1: the 14-1 PROBE toolset (ping/count_images) is RETIRED — the
// tool face is now the closed 19-tool set exactly (5 editing + 14 culling;
// D-14-CONTEXT-3, research §A). The old StoreProvider seam retired with the
// probe (count_images was its only consumer).
// ─────────────────────────────────────────────────────────────────────────────

/// Host orchestration for the Lightamer MCP server.
enum McpServerController {

    /// Host-assembly failures (distinct from tool-face typed errors).
    enum McpHostError: Error {
        case writerLockHeld
        case underlying(String)
    }

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

    /// The open-session seam for the EDITING face (Plan 14-2): the index
    /// store AND its root URL (the tools build absolute image URLs and the
    /// Output landing zone from the pair). Same nil-for-nil honesty.
    typealias SessionProvider =
        @Sendable () async -> (store: SessionIndexStore, root: URL)?

    /// The ONE render gate per server kernel (Plan 14-2): every render-class
    /// tool across the editing (14-2) and culling (14-3) faces serializes on
    /// THIS instance — concurrency 1, FIFO.
    static let sharedRenderGate = McpRenderGate()

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
                    let registry = await makeRegistry(
                        editing: await makeEditingSeams(session: { nil }),
                        culling: makeCullingContext(session: { nil }))
                    await registry.setWriterCheck { @Sendable in lock != nil }
                    let server = await McpAdapters.makeServer(registry: registry)
                    try await server.start(transport: StdioTransport())
                    await log("headless MCP server up (stdio)")
                case .http:
                    // The headless HTTP daemon: same binding discipline as
                    // the GUI host (writer lock → bind 127.0.0.1 → write the
                    // discovery json → serve), a random port, the discovery
                    // file is THE consumer contract (launchers read it).
                    do {
                        let handle = try await startHTTPHost(
                            paths: McpEndpointPaths.makeDefault(),
                            editing: await makeEditingSeams(session: { nil }),
                            culling: makeCullingContext(session: { nil }))
                        await log(
                            "headless MCP server up (http) on 127.0.0.1:\(handle.port)"
                                + " — endpoint file \(handle.paths.jsonURL.path)")
                    } catch McpHostError.writerLockHeld {
                        let message =
                            "--mcp-http: another Lightamer instance holds the writer "
                            + "lock; HTTP daemon not started\n"
                        stderr.write(Data(message.utf8))
                        exit(4)
                    } catch {
                        stderr.write(
                            "headless MCP server failed: \(error)\n".data(using: .utf8)!)
                        exit(1)
                    }
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

    /// The CLOSED tool face: 5 editing tools (Plan 14-2) + 14 culling tools
    /// (Plan 14-3) = the frozen 19-tool set (research §A; D-14-CONTEXT-3).
    /// The 14-1 probe pair (ping/count_images) retired at 14-4 T1 — a host
    /// with NEITHER face assembled yields an EMPTY registry (tests assert
    /// the retirement; the whitelist negative rides the snapshot tests).
    /// The closed face is identical across hosts — the dual-host red line:
    /// even a read-only host lists every tool and fails writes at CALL time.
    static func makeRegistry(
        editing: EditingToolset.Seams? = nil,
        culling: McpCullingContext? = nil
    ) async -> McpToolRegistry {
        let registry = McpToolRegistry()
        if let editing {
            await EditingToolset.register(into: registry, seams: editing)
        }
        if let culling {
            await McpCullingToolset.registerAll(on: registry, context: culling)
        }
        return registry
    }

    /// The host-side culling context assembly (the 14-4 union). `session`
    /// is the same nil-for-nil seam the editing face takes (the shipped
    /// headless hosts pass `{ nil }` — every culling tool answers the typed
    /// `notSessionMember`). The metadata/leg writers build per call against
    /// the session pair (the shipped v1 hosts have no session, so the leg
    /// is dormant there; the GUI host builds its OWN context against the
    /// LIVE shared writer — see LightamerApp's embedded assembly).
    /// `presets` defaults to a fresh self-healing store per call (the
    /// PresetsStore init rescans — an honest fresh view per agent call).
    static func makeCullingContext(
        session: @escaping SessionProvider,
        presets: @escaping @Sendable () async -> PresetsStore? = { PresetsStore() },
        liveRelPaths: @escaping @Sendable () async -> Set<String> = { [] },
        thumbnailProvider: (@Sendable () async -> SessionThumbnailProvider?)? = nil
    ) -> McpCullingContext {
        McpCullingContext(
            store: { await session()?.store },
            sessionRoot: { await session()?.root },
            metadata: {
                guard let pair = await session() else { return nil }
                return MetadataService(
                    root: pair.root, store: pair.store,
                    writer: BatchSidecarWriter(root: pair.root, store: pair.store),
                    seed: [])
            },
            sidecarWriter: {
                guard let pair = await session() else { return nil }
                return BatchSidecarWriter(root: pair.root, store: pair.store)
            },
            presets: presets,
            liveRelPaths: liveRelPaths,
            thumbnailProvider: thumbnailProvider ?? { nil },
            decodeImage: McpCullingContext.defaultDecodeImage())
    }

    // MARK: - The editing seams assembly (Plan 14-2)

    /// Lazy `MetalContext` box (an actor: first render-class call pays the
    /// one-time context build; a failed build retries NOTHING — the typed
    /// `renderFailed` face answers instead).
    private actor LazyMetalContext {
        private var cached: MetalContext?
        func get() -> MetalContext? {
            if let cached { return cached }
            guard let context = try? MetalContext() else { return nil }
            cached = context
            return context
        }
    }

    /// Builds the production editing seams: a POPULATED module registry
    /// (terminal trio + LightamerIOP), a lazy GPU context, the shared render
    /// gate, the host's session pair and the GUI-live judge.
    ///
    /// - Parameters:
    ///   - session: the (store, root) pair provider (headless: `{ nil }` —
    ///     the tools answer `notSessionMember`).
    ///   - liveImageURL: the GUI-live judge (headless: `{ nil }` — nothing
    ///     is open in an editor, everything is writable).
    ///   - yiyinInjector: the export_image production injector (the GUI host
    ///     passes `ExportState.makeYiyinInjector(logoStore:)`; headless nil).
    static func makeEditingSeams(
        session: @escaping SessionProvider,
        liveImageURL: @escaping @Sendable () async -> URL? = { nil },
        yiyinInjector: (@Sendable () async -> ExportYiyinInjector?)? = nil
    ) async -> EditingToolset.Seams {
        let modules = ModuleRegistry()
        // M2-1 (D1/D2 + KD-1/KD-3): the PRODUCTION editing face — the
        // default face unless LIGHTAMER_FULL_IOP_FACE=1 opts back in. The
        // SAME read populates the registry and stamps `seams.defaultFace`
        // (one switch, same source), so list_iops and the apply_params
        // pristine seed narrow with the registry.
        let defaultFace = !LightamerIOPRegistry.isFullFaceRequested
        await LightamerIOPRegistry.populate(modules, defaultFace: defaultFace)
        let metal = LazyMetalContext()
        var seams = EditingToolset.Seams(
            session: session,
            metal: { await metal.get() },
            modules: { modules },
            gate: sharedRenderGate,
            liveImageURL: liveImageURL,
            defaultFace: defaultFace)
        seams.writeGate = McpRenderGate()
        seams.yiyinInjector = yiyinInjector
        return seams
    }

    // MARK: - The HTTP host assembly (headless daemon + GUI-embedded share it)

    /// A running Streamable HTTP host: the listener, its REAL port and the
    /// writer lock it holds. `stop` drains in-flight work, deletes the
    /// discovery json, then releases the lock (§RQ-14-14 ordering). The
    /// registry rides along so the GUI can read the write-call counter
    /// (Plan 14-4 T2: the launcher panel's no-write-back face).
    struct HttpHostHandle: Sendable {
        let host: McpHTTPHost
        let port: Int
        let lock: McpEndpointLock
        let paths: McpEndpointPaths
        let registry: McpToolRegistry

        func writeCallCount() async -> Int {
            await registry.writeCallCount
        }

        func stop(drainTimeout: Duration = McpTimeouts.shutdownDrain) async {
            await host.stop(drainTimeout: drainTimeout)
            McpEndpointFile.remove(in: paths)
            lock.unlock()
        }
    }

    /// The embedded host's write-call counter (nil = no host running). The
    /// launcher panel reads the delta across one agent session (the honest
    /// 「本次会话无写回」clause — what the SERVER saw, Plan 14-4 T2).
    static func embeddedWriteCallCount() async -> Int? {
        guard let handle = withEmbeddedState({ $0.handle }) else { return nil }
        return await handle.writeCallCount()
    }

    /// Assembles and starts one HTTP host: writer lock → bind (loopback
    /// hardcoded, ephemeral port by default — the ACTUAL port rides the
    /// handle and the discovery file) → write discovery json → serve. Throws
    /// `McpHostError.writerLockHeld` when another instance is the writer —
    /// an HTTP host without the writer right is NOT started read-only
    /// (read-only makes sense for a stdio agent session; a daemon whose
    /// entire purpose is being discovered must not fake-liven the network).
    ///
    /// Exposure (D-14-CONTEXT-6①): the loopback default carries NO token
    /// (auth "none"). The `.lan` branch binds 0.0.0.0 and MANDATES the
    /// Bearer valve (generate+keychain-store on first start); the 14-4
    /// Settings UI will be the only user-facing way to reach it.
    enum McpExposure {
        case loopback
        case lan
    }

    /// The LAN binding constant (the non-loopback branch; 14-4 UI gate).
    static let lanHost = "0.0.0.0"

    /// The SDK default pipeline (Origin → Accept → Content-Type →
    /// Protocol-Version → Session) + the Bearer valve APPENDED — the plan's
    /// assertion order, spelled out so the Bearer valve can never preempt a
    /// transport-level validation.
    static func validationPipelineWithBearer(
        token: String
    ) -> any HTTPRequestValidationPipeline {
        StandardValidationPipeline(validators: [
            OriginValidator.localhost(),
            AcceptHeaderValidator(mode: .sseRequired),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
            SessionValidator(),
            McpBearerValidator(token: token),
        ])
    }

    static func startHTTPHost(
        paths: McpEndpointPaths,
        port: Int = 0,
        exposure: McpExposure = .loopback,
        editing: EditingToolset.Seams? = nil,
        culling: McpCullingContext? = nil
    ) async throws -> HttpHostHandle {
        // The Bearer valve exists ONLY on the non-loopback branch (the
        // loopback default is zero-token by design — the smallest surface).
        let bearerToken: String?
        let bindHost: String
        switch exposure {
        case .loopback:
            bearerToken = nil
            bindHost = McpHTTPHost.loopbackHost
        case .lan:
            bindHost = lanHost
            if let existing = McpBearerToken.load() {
                bearerToken = existing
            } else {
                guard let fresh = McpBearerToken.generate() else {
                    throw McpHostError.underlying("bearer token generation failed")
                }
                try McpBearerToken.store(fresh)
                bearerToken = fresh
            }
        }

        let lock: McpEndpointLock
        switch McpEndpointLock.acquire(in: paths) {
        case .success(let acquired):
            lock = acquired
        case .failure(.heldByOther):
            throw McpHostError.writerLockHeld
        case .failure(.ioError(let reason)):
            throw McpHostError.underlying("writer-lock acquire failed: \(reason)")
        }
        do {
            let registry = await makeRegistry(editing: editing, culling: culling)
            // The host holds the writer right by construction.
            await registry.setWriterCheck { true }
            let pipeline = bearerToken.map { validationPipelineWithBearer(token: $0) }
            let host = McpHTTPHost(
                configuration: .init(host: bindHost, port: port),
                validationPipeline: pipeline
            ) { transport in
                // One Server actor per SESSION, the SAME kernel.
                await McpAdapters.makeServer(registry: registry)
            }
            try await host.start()
            guard let bound = await host.boundPort else {
                try await host.stop()
                throw McpHostError.underlying("bound port unreadable after bind")
            }
            let info = McpEndpointInfo(
                schemaVersion: McpEndpointInfo.schemaVersionV1,
                transport: McpEndpointInfo.transportStreamableHTTP,
                host: bindHost,
                port: bound,
                pid: getpid(),
                startedAt: McpEndpointInfo.nowISO8601(),
                serverName: serverName,
                serverVersion: serverVersion,
                auth: bearerToken == nil ? McpEndpointInfo.authNone : McpEndpointInfo.authBearer)
            try McpEndpointFile.write(info, in: paths)
            return HttpHostHandle(
                host: host, port: bound, lock: lock, paths: paths,
                registry: registry)
        } catch {
            lock.unlock()
            throw error
        }
    }

    // MARK: - GUI-embedded host (the preference read face; the UI switch is
    // Plan 14-4 — this is the machinery the switch will drive)

    /// The UserDefaults keys the 14-4 Settings section binds; read at
    /// launch and on toggle.
    static let embeddedServerEnabledKey = "mcp_server_enabled"
    /// The explicit non-loopback exposure gate (D-14-CONTEXT-6①: ON binds
    /// 0.0.0.0 AND mandates the Bearer valve — startHTTPHost's `.lan`
    /// branch; the risk text rides the Settings row).
    static let lanExposureEnabledKey = "mcp_lan_exposure_enabled"

    /// Launch-time hook (the app root's .task): records the session store
    /// seam and starts the embedded host when the preference is on.
    /// Plan 14-2: `editing` non-nil registers the editing tools on the
    /// embedded kernel (the GUI host builds the seams via
    /// `makeEditingSeams` with its live session + GUI-live judge).
    /// Plan 14-4: the culling face rides the same kernel (`culling`), and
    /// the old probe-only StoreProvider seam is retired.
    static func startEmbeddedIfPreferenceEnabled(
        editing: EditingToolset.Seams?,
        culling: McpCullingContext?
    ) async {
        withEmbeddedState { state in
            state.editing = editing
            state.culling = culling
        }
        guard UserDefaults.standard.bool(forKey: embeddedServerEnabledKey) else { return }
        await startEmbeddedServer()
    }

    /// Starts the embedded host now (the preference toggle's on-leg).
    /// No-op when already running; a held writer lock is logged and ignored
    /// (another instance is the writer — the GUI shows no fake endpoint).
    /// The exposure branch rides the Settings gate: loopback by default,
    /// `.lan` (0.0.0.0 + mandated Bearer) only when the explicit toggle is
    /// on — the D-14-CONTEXT-6① face.
    static func startEmbeddedServer() async {
        if withEmbeddedState({ $0.handle != nil }) { return }
        do {
            let (editing, culling) = withEmbeddedState { state in
                (state.editing, state.culling)
            }
            let exposure: McpExposure =
                UserDefaults.standard.bool(forKey: lanExposureEnabledKey)
                ? .lan : .loopback
            let handle = try await startHTTPHost(
                paths: McpEndpointPaths.makeDefault(),
                exposure: exposure,
                editing: editing,
                culling: culling)
            let wonRace = withEmbeddedState { state -> Bool in
                if state.handle == nil {
                    state.handle = handle
                    return true
                }
                return false
            }
            if !wonRace {
                await handle.stop()  // a concurrent start got in first
                return
            }
            await log("embedded MCP host up on 127.0.0.1:\(handle.port)")
        } catch McpHostError.writerLockHeld {
            await log(
                "embedded MCP host not started: another instance holds the writer lock")
        } catch {
            await log("embedded MCP host failed: \(error)")
        }
    }

    /// Stops the embedded host (the preference off-leg).
    static func stopEmbeddedServer() async {
        let handle = takeEmbeddedHandleLocked()
        guard let handle else { return }
        await handle.stop()
        await log("embedded MCP host stopped")
    }

    /// The applicationWillTerminate leg: a SYNCHRONOUS bounded wait (5s —
    /// the same shape as the 02-06 sidecar flush), because the AppKit
    /// termination callback cannot await. After the bound, the process exit
    /// is the cleanup: the kernel releases the lock, and any json residue is
    /// healed by the discovery probe on next start.
    static func stopEmbeddedForTermination() {
        guard let handle = takeEmbeddedHandleLocked() else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await handle.stop()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
    }

    // The embedded-runtime box (NSLock-guarded; all mutations scoped through
    // the sync helpers below so no async context ever touches the lock
    // primitives directly).
    private static let embeddedStateLock = NSLock()
    private struct EmbeddedState {
        var handle: HttpHostHandle?
        var editing: EditingToolset.Seams?
        var culling: McpCullingContext?
    }
    nonisolated(unsafe) private static var embeddedState = EmbeddedState()

    private static func withEmbeddedState<T>(_ body: (inout EmbeddedState) -> T) -> T {
        embeddedStateLock.lock()
        defer { embeddedStateLock.unlock() }
        return body(&embeddedState)
    }

    private static func takeEmbeddedHandleLocked() -> HttpHostHandle? {
        withEmbeddedState { state in
            let handle = state.handle
            state.handle = nil
            return handle
        }
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
