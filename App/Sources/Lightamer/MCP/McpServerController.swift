import Darwin
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
// tool face is now the closed 20-tool set exactly (6 editing + 14 culling;
// D-14-CONTEXT-3, research §A; + match_color, M5-1-03). The old StoreProvider
// seam retired with the probe (count_images was its only consumer).
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

    // MARK: - M6-1-01 T6: the headless `--project` arbitration (KD-4)

    /// The project-arbitration CLI flag (the token whose NEXT argv slot
    /// carries the `.lalb` path).
    static let projectFlag = "--project"

    /// The machine-read guidance event name (the frozen v1 schema).
    static let connectGuidanceEvent = "connect-guidance"

    /// The `--project` assembly parameter: the flag token's neighbor slot.
    /// Flag present but path missing, or a non-`.lalb` suffix → stderr
    /// error + exit 1 (the KD-4 validation shape).
    static func headlessProjectPathIfRequested() -> URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: projectFlag) else { return nil }
        guard arguments.count > index + 1 else {
            FileHandle.standardError.write(Data(
                "\(projectFlag): a .\(LibrarySchema.fileExtension) package path is required\n".utf8))
            exit(1)
        }
        let path = arguments[index + 1]
        guard path.lowercased().hasSuffix("." + LibrarySchema.fileExtension) else {
            FileHandle.standardError.write(Data(
                "\(projectFlag): not a .\(LibrarySchema.fileExtension) package path: \(path)\n".utf8))
            exit(1)
        }
        return URL(fileURLWithPath: path)
    }

    /// The connect-guidance payload (schema v1 FROZEN: event / endpoint |
    /// null / holderPid). The endpoint mirrors the holder's discovery json
    /// (`McpEndpointDiscovery` single source — the Core lock payload never
    /// carries it, KD-1).
    struct McpConnectGuidance: Codable, Equatable, Sendable {
        struct Endpoint: Codable, Equatable, Sendable {
            var transport: String
            var host: String
            var port: Int
            var auth: String
        }
        var event: String
        var endpoint: Endpoint?
        var holderPid: Int32
    }

    /// The guidance channel fork (KD-4, the LightCraft docs/mcp.md
    /// discipline: stdout carries ONLY protocol messages on a stdio host —
    /// an HTTP host owns its stdout, so its guidance rides stdout; a stdio
    /// host's guidance goes to stderr, both the machine JSON and the human
    /// line).
    static func connectGuidanceChannel(for mode: LaunchMode) -> FileHandle {
        switch mode {
        case .http: FileHandle.standardOutput
        case .stdio: FileHandle.standardError
        }
    }

    /// The endpoint paths the headless arms use. DEBUG tests spawn THIS
    /// binary and cannot inject constructor parameters — the env override
    /// (read ONCE at this assembly root, the L036 discipline) redirects the
    /// discovery machinery into a per-test temp directory. Release builds
    /// never see the branch.
    static var headlessEndpointPaths: McpEndpointPaths {
        #if DEBUG
        if let directory = ProcessInfo.processInfo
            .environment["LIGHTAMER_MCP_ENDPOINT_DIR"] {
            return McpEndpointPaths(
                directory: URL(fileURLWithPath: directory, isDirectory: true))
        }
        #endif
        return McpEndpointPaths.makeDefault()
    }

    /// The connect-guidance text for a probe `.held` verdict (KD-5 — the
    /// copy rides the typed error; the discovery file is the single source
    /// for the alive endpoint, absence = the fallback line). Bilingual
    /// mixed per the existing McpToolError message convention.
    static func connectGuidanceText() -> String {
        if case .alive(let info) = McpEndpointDiscovery.discover(
            in: headlessEndpointPaths) {
            return "请连接其 MCP 端点 \(info.host):\(info.port) 后重试 / connect to "
                + "the live instance's MCP endpoint at \(info.host):\(info.port)"
        }
        return "请关闭另一实例或在其上开启 MCP server 后重试 / close the other "
            + "instance or enable its MCP server"
    }

    /// The project probe closure for the headless arms (KD-5): the writer
    /// arm returns `.writable` outright (the SELF-HELD exemption — its own
    /// fd would EWOULDBLOCK the probe); the read-only arm really probes
    /// (the holder exiting = natural recovery, OQ-5's per-call semantics).
    static func makeProjectWriteProbe(
        selfHeld: Bool, lockURL: URL
    ) -> @Sendable () async -> McpProjectLockVerdict {
        { [selfHeld, lockURL] in
            if selfHeld { return .writable }
            if SingleWriterLock.probeLockAvailable(at: lockURL) { return .writable }
            return .held(
                holderSummary: SingleWriterLock.holderSummary(at: lockURL),
                guidance: Self.connectGuidanceText())
        }
    }

    /// The current-project box (M7-3 T4): the RUNTIME-mutable carrier for
    /// the headless arms — a lock-guarded (store, url, readOnly) triple
    /// above the M6-1 launch carrier. Writers: the arbitration seeding
    /// (launch), the runtime open/create providers (the writer-gate
    /// -serialized tool face, apply 同款) and the EOF watcher's close leg.
    /// Readers: the search/state seams (library / semantic / fulltext /
    /// liveState) and the project context's library seam — every read is
    /// per-call, so a runtime switch is visible to the NEXT call.
    /// Internal (the box-sensitive tests reset it directly).
    final class HeadlessProjectBox: @unchecked Sendable {
        struct Snapshot: Sendable {
            var store: ProjectFileStore?
            var url: URL?
            var readOnly: Bool
        }

        private let lock = NSLock()
        private var snapshot = Snapshot(store: nil, url: nil, readOnly: false)

        func set(_ snapshot: Snapshot) {
            lock.lock()
            defer { lock.unlock() }
            self.snapshot = snapshot
        }

        var current: Snapshot {
            lock.lock()
            defer { lock.unlock() }
            return snapshot
        }

        /// Pops the store (the EOF close leg + the switch leg) — the box
        /// goes storeless so a close can never double-fire.
        func takeStore() -> ProjectFileStore? {
            lock.lock()
            defer { lock.unlock() }
            let store = snapshot.store
            snapshot.store = nil
            return store
        }
    }

    /// Internal (not private): the box is PROCESS-global — the in-process
    /// arbitration tests reset it at start (order independence).
    nonisolated(unsafe) static let headlessProjectBox = HeadlessProjectBox()

    /// M7-5-01 (TURN-04, D-M7-5-2/10): the headless ALWAYS-HELD control
    /// face — the null-owner semantics (the agent always holds; the
    /// state-changing commands pass because the registry's admit seam stays
    /// nil here — the writerCheck-nil same shape). Constant closures, zero
    /// cost. The control tools register on EVERY host that passes this (the
    /// union single-value discipline — OQ-10: the read-only host lists the
    /// control face and the write tools still answer serverReadOnly at the
    /// writer gate — control state and write right are orthogonal).
    static func makeHeadlessControlContext() -> McpControlContext {
        McpControlContext(
            acquire: { _ in McpControlState.headlessConstant },
            release: { McpControlState.headlessConstant },
            state: { McpControlState.headlessConstant })
    }

    /// The headless search/state context (M7-2-01 T1 action 5 + T3; M7-3 T4
    /// box form): every data face reads the CURRENT-PROJECT BOX per call —
    /// the launch-captured projectURL/isWriter spellings are RETIRED (the
    /// runtime open/create must be visible to the next call; the box-empty
    /// face is the byte-identical bare-context nulls). The H2 fix rides the
    /// library seam: the path-kind anchor is the BOX's url (a runtime A→B
    /// switch re-anchors projectRelative resolution to B — fix `20997721`
    /// same-family second instance closed). F-AC-2: the probe rides through
    /// so `get_state.control.lock` reports the verdict truth.
    static func makeHeadlessSearchState(
        mode: LaunchMode,
        projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)? = nil,
        agentControl: (@Sendable () async -> McpControlState?)? = nil
    ) -> McpSearchStateContext {
        McpSearchStateContext(
            library: {
                let snapshot = McpServerController.headlessProjectBox.current
                guard let store = snapshot.store, let url = snapshot.url
                else { return nil }
                // The path-kind anchor is the directory holding the
                // package (projectRelative rows append to it — the
                // WorkspaceHostView urlResolver 形).
                return (store: store,
                        projectDirectory: url.deletingLastPathComponent())
            },
            semanticStore: {
                guard let store = McpServerController.headlessProjectBox
                    .current.store
                else { return nil }
                return SemanticStore(store: store)
            },
            semantic: {
                await AIInferenceService.shared.semanticSearcher()
            },
            fulltext: { query in
                // N2-3 (M7-3): the narrow race (the carrier drained between
                // the library gate and this seam) is the TYPED honest arm —
                // never a silent empty result (the headnote discipline).
                guard let store = McpServerController.headlessProjectBox
                    .current.store
                else {
                    throw McpToolError.notSessionMember(
                        McpSearchStateToolset.noOpenProjectMessage)
                }
                return try await AIDescriptionService.imageIDs(
                    matching: query, store: store)
            },
            liveState: { [mode] in
                // Per-call box read: an empty box answers nil = the
                // bare-context no-project null face byte-identical; a
                // holding box answers the arbitration-outcome truth
                // (path/readOnly/heldByOther derived from the box).
                let snapshot = McpServerController.headlessProjectBox.current
                guard let url = snapshot.url else { return nil }
                return McpSearchStateLiveSnapshot(
                    project: .object([
                        "path": .string(url.path),
                        "heldByOther": .bool(snapshot.readOnly),
                        "readOnly": .bool(snapshot.readOnly),
                    ]),
                    server: .object([
                        "name": .string(McpServerController.serverName),
                        "version": .string(McpServerController.serverVersion),
                        "hostMode": .string(
                            mode == .stdio ? "stdio" : "http"),
                        "readOnly": .bool(snapshot.readOnly),
                    ]))
            },
            projectWriteProbe: projectWriteProbe,
            // M7-5-01 (D-M7-5-8): the headless agent face rides the
            // constant provider (the always-held truth).
            agentControl: agentControl)
    }

    /// The headless project context (M7-3 T4, D-M7-3-1 headless arm): the
    /// Core-direct runtime open/create providers — close-then-open (the
    /// checkpoint rides close); a failure after a successful close leaves
    /// the box EMPTY (the honest no-project state, never a half-open — the
    /// agent retries); a held target is the typed `projectReadOnly`
    /// carrying the holder summary (`SingleWriterLock.holderSummary`).
    /// The mode is captured INSIDE the provider closures (M1 — the provider
    /// signature carries no mode) so the runtime EOF arm's internal
    /// self-guard can see it.
    static func makeHeadlessProjectContext(
        mode: LaunchMode
    ) -> McpProjectContext {
        McpProjectContext(
            openProject: { [mode] url in
                try await McpServerController.headlessRuntimeOpen(
                    url, mode: mode)
            },
            createProject: { [mode] url, name in
                try await McpServerController.headlessRuntimeCreate(
                    url, name, mode: mode)
            },
            library: {
                let snapshot = McpServerController.headlessProjectBox.current
                guard let store = snapshot.store, let url = snapshot.url
                else { return nil }
                return (store: store,
                        projectDirectory: url.deletingLastPathComponent())
            })
        // sessionPair stays nil (the headless face has no open session —
        // the relPath addressing arm answers the typed notSessionMember,
        // the same honesty as the search/state face). projectWriteProbe
        // stays nil (the search/state context carries the real probe; this
        // is the symmetry face and list_versions never consumes it).
    }

    /// The runtime-store park + EOF arm tail (the open AND create legs
    /// share this ONE call site — the launch path is the other arm site;
    /// the once guard makes the multiplicity harmless).
    private static func parkRuntimeStore(
        _ store: ProjectFileStore, at url: URL, mode: LaunchMode
    ) {
        headlessProjectBox.set(HeadlessProjectBox.Snapshot(
            store: store, url: url, readOnly: false))
        armStdioEOFReleaseOnce(mode: mode)
    }

    /// The close-then-open leg (D-M7-3-1): the current store's checkpoint
    /// rides close BEFORE the target opens; a failure leaves the box empty.
    static func headlessRuntimeOpen(
        _ url: URL, mode: LaunchMode
    ) async throws -> ProjectOpenOutcome {
        await closeCurrentHeadlessProject()
        let store = ProjectFileStore(at: url)
        do {
            _ = try await store.open(role: .headless)
        } catch let error as LibraryError {
            if case .projectHeldByOther(let detail) = error {
                throw McpToolError.projectReadOnly(detail)
            }
            // OQ-M7-3-10: the migrate leg rides open(role:) verbatim — a
            // migrate failure is the internalError bail-out with the
            // LibraryError detail.
            throw McpToolError.internalError("\(error)")
        } catch {
            throw McpToolError.internalError("\(error)")
        }
        parkRuntimeStore(store, at: url, mode: mode)
        return ProjectOpenOutcome(url: url)
    }

    /// The create leg: same close-then-open discipline; `create(name:role:)`
    /// acquires the lock BEFORE any write leg (a held target = the typed
    /// projectReadOnly; the fresh file is removed by the store on a failed
    /// fresh-create).
    static func headlessRuntimeCreate(
        _ url: URL, _ name: String, mode: LaunchMode
    ) async throws -> ProjectOpenOutcome {
        await closeCurrentHeadlessProject()
        let store = ProjectFileStore(at: url)
        do {
            _ = try await store.create(name: name, role: .headless)
        } catch let error as LibraryError {
            if case .projectHeldByOther(let detail) = error {
                throw McpToolError.projectReadOnly(detail)
            }
            throw McpToolError.internalError("\(error)")
        } catch {
            throw McpToolError.internalError("\(error)")
        }
        parkRuntimeStore(store, at: url, mode: mode)
        return ProjectOpenOutcome(url: url)
    }

    /// The current store's graceful close (the checkpoint rides close).
    private static func closeCurrentHeadlessProject() async {
        if let store = headlessProjectBox.takeStore() {
            try? await store.close()
        }
    }

    /// The stdio EOF graceful-release watcher (M7-3 OQ-7 extraction of the
    /// M6-1 launch leg): IDEMPOTENT (the static once guard — multiple
    /// runtime opens arm nothing twice) with the INTERNAL mode self-guard
    /// (M1 double insurance — the launch path keeps its `if mode ==
    /// .stdio` gate AND the arm re-checks, so an http daemon whose stdin
    /// may already be closed can never trip an unguarded poll's instant
    /// POLLHUP → close + exit on the first runtime open). The watcher body
    /// reads the CURRENT project box at HUP time — close + exit(0)
    /// semantics unchanged (the M6-1 checkpoint-graceful face carried to
    /// the runtime-open path).
    static func armStdioEOFReleaseOnce(mode: LaunchMode) {
        // The M1 internal self-guard (http arms never arm).
        guard mode == .stdio else { return }
        eofArmLock.lock()
        defer { eofArmLock.unlock() }
        guard !eofArmDone else { return }
        eofArmDone = true
        Task.detached(priority: .utility) {
            // POLLIN must be REQUESTED (events): a macOS pipe write-end
            // close never wakes an events:0 poll, so the pre-M7-4 form
            // never fired. The timeout only bounds the blocked phase —
            // on an always-readable fd poll returns immediately — so the
            // rate limiter lives in the pure-POLLIN arm's sleep below.
            var fds = [pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)]
            while true {
                let count = poll(&fds, 1, 250)
                if count > 0,
                    fds[0].revents & (Int16(POLLHUP) | Int16(POLLERR)) != 0 {
                    break
                }
                // Clearing only revents (never the events request bit):
                // the watcher watches HUP without stealing bytes — the
                // request-read thread owns consumption.
                fds[0].revents = 0
                if count > 0 {
                    // Pure POLLIN on an always-readable fd (dup2'd
                    // /dev/null in test hosts): poll returns ready on
                    // every iteration, so sleep to cap this watcher at
                    // ~4 Hz instead of a syscall spin. A real pipe with
                    // readable data also lands here and merely delays
                    // the next HUP check by ≤250ms — zero bytes are
                    // consumed and the request thread is unaffected.
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                // count == 0: the 250ms wait was already paid — loop.
            }
            try? await McpServerController.headlessProjectBox.takeStore()?.close()
            exit(0)
        }
    }

    private static let eofArmLock = NSLock()
    /// The once-guard state (internal for the M1 executable judgment: the
    /// http-mode runtime-open test asserts this NEVER flips).
    nonisolated(unsafe) static var eofArmDone = false

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
    ///
    /// M6-1-01 T6 (KD-4/OQ-3): with `--project <path>` armed, the project
    /// lock arbitrates FIRST — acquire → writer arm (open + serve, the
    /// `.lalb` write right lives here); heldByOther → read-only arm
    /// (guidance emitted, serve continues). Without the flag the body
    /// below is byte-identical legacy (the zero-regression surface).
    static func runHeadless(mode: LaunchMode) {
        let stderr = FileHandle.standardError
        Task<Void, Never> {
            do {
                if let projectURL = headlessProjectPathIfRequested() {
                    await runHeadlessArbitrated(mode: mode, projectURL: projectURL)
                    return
                }
                switch mode {
                case .stdio:
                    await startHeadlessStdioHost(
                        paths: McpEndpointPaths.makeDefault(),
                        searchState: makeHeadlessSearchState(mode: mode),
                        project: makeHeadlessProjectContext(mode: mode),
                        // M7-5-01 (F1 形 B production point 1): the headless
                        // always-held face.
                        control: makeHeadlessControlContext())
                case .http:
                    // The headless HTTP daemon: same binding discipline as
                    // the GUI host (writer lock → bind 127.0.0.1 → write the
                    // discovery json → serve), a random port, the discovery
                    // file is THE consumer contract (launchers read it).
                    do {
                        let handle = try await startHTTPHost(
                            paths: McpEndpointPaths.makeDefault(),
                            editing: await makeEditingSeams(session: { nil }),
                            culling: makeCullingContext(session: { nil }),
                            searchState: makeHeadlessSearchState(mode: mode),
                            project: makeHeadlessProjectContext(mode: mode),
                            // M7-5-01 (F1 形 B production point 2).
                            control: makeHeadlessControlContext())
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

    /// The `--project` two-arm body (KD-4). The STORE is the single
    /// acquisition point (KD-2): `open(role: .headless)` arbitrating held =
    /// the READ-ONLY arm (guidance + serve-on), success = the WRITER arm
    /// (the store owns the lock; the legacy serve assembly, `SessionProvider`
    /// stays `{ nil }` — m1: v1 positioning is the lock carrier + open
    /// validation; the tool service face is unchanged, project-level tooling
    /// is M6-2's). An external acquire here would double-lock (flock per
    /// open file description: the store's own second fd would EWOULDBLOCK
    /// against the arm's first — the T6 execution fix).
    private static func runHeadlessArbitrated(mode: LaunchMode, projectURL: URL) async {
        let stderr = FileHandle.standardError
        let lockURL = projectURL.deletingPathExtension()
            .appendingPathExtension("lalb.lock")
        var isWriter = false
        let store = ProjectFileStore(at: projectURL)
        do {
            _ = try await store.open(role: .headless)
            headlessProjectBox.set(HeadlessProjectBox.Snapshot(
                store: store, url: projectURL, readOnly: false))
            isWriter = true
            await log("headless project writer arm: \(projectURL.path)")
        } catch let error as LibraryError {
            if case .projectHeldByOther = error {
                emitConnectGuidance(mode: mode, lockURL: lockURL)
                await log("headless project read-only arm: held by another instance")
                // M7-2-01 T4 (D-M7-2-7): serve the read faces from the held
                // package — openReadOnly takes NO lock (flock semantics
                // untouched), guards the schema (stored == current) and
                // typed-rejects every write leg at withWriteBatch. Failure
                // = the honest nil-seam degrade (the three search/state
                // tools answer notSessionMember) + this log — NEVER an
                // exit (the guidance already pointed the agent at the
                // holder's live endpoint).
                do {
                    let readOnlyStore = try await store.openReadOnly()
                    headlessProjectBox.set(HeadlessProjectBox.Snapshot(
                        store: readOnlyStore, url: projectURL, readOnly: true))
                    await log(
                        "headless project read-only arm: serving read faces "
                            + "from \(projectURL.path)")
                } catch {
                    // The url/readOnly faces stay seeded (the arbitration
                    // outcome IS the project truth — the liveState face
                    // keeps today's shape), the STORE stays empty (the
                    // data seams answer the typed errors).
                    headlessProjectBox.set(HeadlessProjectBox.Snapshot(
                        store: nil, url: projectURL, readOnly: true))
                    await log(
                        "headless project read-only arm: read-only open "
                            + "failed (\(error)) — the search/state tools "
                            + "answer notSessionMember")
                }
            } else {
                stderr.write(Data(
                    "--project: package open failed: \(error)\n".utf8))
                exit(1)
            }
        } catch {
            stderr.write(Data(
                "--project: package open failed: \(error)\n".utf8))
            exit(1)
        }
        // The stdio EOF graceful leg (KD-4, armed only with --project): the
        // agent disconnecting releases the project right best-effort
        // (checkpoint → unlock → exit; process death is the kernel floor).
        // M7-3: the extracted shared arm (once guard + the internal mode
        // self-guard) — the launch behavior is byte-identical and the
        // runtime-open path arms the SAME leg through the same function.
        armStdioEOFReleaseOnce(mode: mode)
        // M6-1-01 T7 (KD-5): the write-face probe — self-held on the writer
        // arm, the real non-holding probe on the read-only arm.
        let probe = makeProjectWriteProbe(selfHeld: isWriter, lockURL: lockURL)
        // M7-2-01: the search/state context rides every arm (the closed
        // face is identical across hosts). M7-3: the project context rides
        // every host call site too (H3 — tools never disappear; the
        // read-only host's open/create answer serverReadOnly at the gate).
        let searchState = makeHeadlessSearchState(
            mode: mode, projectWriteProbe: probe,
            // M7-5-01 (D-M7-5-8): the headless agent face = the constant.
            agentControl: { McpControlState.headlessConstant })
        let project = makeHeadlessProjectContext(mode: mode)
        // M7-5-01 (F1 形 B production points 3-5): the arbitrated arms share
        // ONE const (the searchState/project shared-const same shape) — the
        // stdio arm, the http writer arm AND the read-only arm all pass it
        // (the read-only host registers the control face too — OQ-10).
        let control = makeHeadlessControlContext()
        switch mode {
        case .stdio:
            await startHeadlessStdioHost(
                paths: headlessEndpointPaths, projectWriteProbe: probe,
                searchState: searchState, project: project, control: control)
        case .http:
            if isWriter {
                // Writer arm: the full legacy http daemon (endpoint lock →
                // bind → discovery json → serve).
                do {
                    var editing = await makeEditingSeams(session: { nil })
                    editing.projectWriteProbe = probe
                    var culling = makeCullingContext(session: { nil })
                    culling.projectWriteProbe = probe
                    let handle = try await startHTTPHost(
                        paths: headlessEndpointPaths,
                        editing: editing,
                        culling: culling,
                        searchState: searchState,
                        project: project,
                        control: control)
                    await log(
                        "headless MCP server up (http) on 127.0.0.1:\(handle.port)"
                            + " — endpoint file \(handle.paths.jsonURL.path)")
                } catch {
                    stderr.write(Data(
                        "--project http: host start failed: \(error)\n".utf8))
                    exit(1)
                }
            } else {
                // Read-only arm: serve WITHOUT the endpoint writer right —
                // no discovery json (that file belongs to the writer; the
                // guidance already pointed the agent at the holder's real
                // endpoint), no lock steal. The startHTTPHost contract
                // (writer-less daemons don't fake-liven the network) keeps
                // its shape; this is the separate honest read-only face.
                await startReadOnlyHTTPHost(
                    paths: headlessEndpointPaths, projectWriteProbe: probe,
                    searchState: searchState, project: project,
                    // OQ-10: the read-only host registers the control face
                    // too (tools never disappear; the write tools still
                    // answer serverReadOnly at the writer gate).
                    control: control)
            }
        }
    }

    /// The connect-guidance emission (KD-4 ②③): one machine-readable JSON
    /// line on the mode's channel + one human line on stderr. Endpoint
    /// absent (noEndpointFile / staleResidueRemoved) = the DEGRADED form
    /// (`endpoint: null` — close it or turn on its MCP server).
    private static func emitConnectGuidance(mode: LaunchMode, lockURL: URL) {
        let payload = SingleWriterLock.readPayload(at: lockURL)
        let holderPid = payload?.pid ?? -1
        var endpoint: McpConnectGuidance.Endpoint?
        if case .alive(let info) = McpEndpointDiscovery.discover(
            in: headlessEndpointPaths) {
            endpoint = McpConnectGuidance.Endpoint(
                transport: info.transport, host: info.host,
                port: info.port, auth: info.auth)
        }
        let guidance = McpConnectGuidance(
            event: connectGuidanceEvent, endpoint: endpoint, holderPid: holderPid)
        do {
            var data = try JSONEncoder().encode(guidance)
            data.append(0x0A)
            connectGuidanceChannel(for: mode).write(data)
        } catch {
            // The machine face failed to encode — impossible for this
            // struct, but the human face still fires below.
        }
        if let endpoint {
            // The interpolated args ride the STRING-CATALOG table when the
            // key exists — %@ requires String arguments (an Int32 through
            // the table format crashes the host); stringify explicitly.
            let line = String(
                localized: "mcp_connect_guidance_stderr",
                defaultValue: "项目已由另一实例持有（pid \(String(holderPid))）——请连接其 MCP 端点 \(endpoint.host):\(endpoint.port)，或关闭该实例后重试。\n")
            FileHandle.standardError.write(Data(line.utf8))
        } else {
            let line = String(
                localized: "mcp_connect_guidance_stderr_noendpoint",
                defaultValue: "项目由另一实例持有（pid \(String(holderPid))）——关闭它或在其上开启 MCP server。\n")
            FileHandle.standardError.write(Data(line.utf8))
        }
        if mode == .http {
            syncStdoutBestEffort()
        }
    }

    /// S2 (D-M7-4-8): the launch-time LUT library preheat. The FIRST
    /// `LutLibraryStore.shared` access runs the swift_once store init
    /// (built-in seeding + the ~50s full-library parse); detaching it at
    /// .utility from every host start moves that cost off the agent's
    /// first `list_luts` call. The env gate is the TEST-context opt-out
    /// (M7-4-01 F14): the e2e/arbitration spawn fixtures inject
    /// LIGHTAMER_SKIP_LUT_PREHEAT so a spawned real host pays neither the
    /// parse CPU nor the real-user LUT-root seeding inside the assertion
    /// windows. swift_once makes the multiple assembly points idempotent.
    static func warmLutLibrary() {
        guard ProcessInfo.processInfo
            .environment["LIGHTAMER_SKIP_LUT_PREHEAT"] == nil else { return }
        Task.detached(priority: .utility) { _ = LutLibraryStore.shared }
    }

    /// The read-only HTTP serve face (the project read-only arm): binds
    /// loopback ephemeral WITHOUT the endpoint writer right and writes NO
    /// discovery json; every write-face tool fails at call time (the
    /// writerCheck false + the T7 project probe when wired).
    private static func startReadOnlyHTTPHost(
        paths: McpEndpointPaths,
        projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)? = nil,
        searchState: McpSearchStateContext? = nil,
        project: McpProjectContext? = nil,
        control: McpControlContext? = nil
    ) async {
        warmLutLibrary()
        var editing = await makeEditingSeams(session: { nil })
        editing.projectWriteProbe = projectWriteProbe
        var culling = makeCullingContext(session: { nil })
        culling.projectWriteProbe = projectWriteProbe
        let registry = await makeRegistry(
            editing: editing, culling: culling, searchState: searchState,
            project: project, control: control)
        await registry.setWriterCheck { false }
        let host = McpHTTPHost(
            configuration: .init(host: McpHTTPHost.loopbackHost, port: 0),
            validationPipeline: nil
        ) { _ in
            await McpAdapters.makeServer(registry: registry)
        }
        do {
            try await host.start()
            if let bound = await host.boundPort {
                await log(
                    "headless MCP read-only http face up on 127.0.0.1:\(bound)"
                        + " (no discovery file — the writer owns it)")
                // M7-2-01 T4 (F-2 甲): the SC judgment channel — in the
                // DEBUG per-test endpoint domain the read-only face writes
                // its OWN discovery file (`mcp-endpoint-readonly.json`,
                // never the writer's `mcp-endpoint.json`), so the test
                // parent can find the bound port and call tools for real
                // (the arbitration A/B fixtures only assert guidance +
                // residency; this is the over-the-wire judgment). Release
                // compiles NONE of this branch — the read-only face keeps
                // its "no discovery json" release semantics.
                #if DEBUG
                if ProcessInfo.processInfo
                    .environment["LIGHTAMER_MCP_ENDPOINT_DIR"] != nil {
                    let info = McpEndpointInfo(
                        schemaVersion: McpEndpointInfo.schemaVersionV1,
                        transport: McpEndpointInfo.transportStreamableHTTP,
                        host: McpHTTPHost.loopbackHost,
                        port: bound,
                        pid: getpid(),
                        startedAt: McpEndpointInfo.nowISO8601(),
                        serverName: serverName,
                        serverVersion: serverVersion,
                        auth: McpEndpointInfo.authNone)
                    try? McpEndpointFile.writeReadOnly(info, in: paths)
                }
                #endif
            }
        } catch {
            FileHandle.standardError.write(Data(
                "--project read-only http face failed: \(error)\n".utf8))
        }
    }

    /// The legacy stdio body (endpoint lock acquire → registry → serve),
    /// extracted verbatim so the `--project` arms and the no-project path
    /// share ONE implementation (the M6-1 diff moved, not changed — the
    /// McpHostTests stdio fixtures pin the behavior).
    private static func startHeadlessStdioHost(
        paths: McpEndpointPaths,
        projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)? = nil,
        searchState: McpSearchStateContext? = nil,
        project: McpProjectContext? = nil,
        control: McpControlContext? = nil
    ) async {
        warmLutLibrary()
        let stderr = FileHandle.standardError
        do {
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
            var editing = await makeEditingSeams(session: { nil })
            editing.projectWriteProbe = projectWriteProbe
            var culling = makeCullingContext(session: { nil })
            culling.projectWriteProbe = projectWriteProbe
            let registry = await makeRegistry(
                editing: editing, culling: culling, searchState: searchState,
                project: project, control: control)
            await registry.setWriterCheck { @Sendable in lock != nil }
            let server = await McpAdapters.makeServer(registry: registry)
            try await server.start(transport: StdioTransport())
            await log("headless MCP server up (stdio)")
        } catch {
            stderr.write(
                "headless MCP server failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    // MARK: - The single kernel (registry assembly)

    /// The CLOSED tool face: 6 editing tools (Plan 14-2 + match_color,
    /// M5-1-03) + 14 culling tools (Plan 14-3) + 3 search/state tools
    /// (M7-2-01 — all read-only) = the 23-tool set (research §A;
    /// D-14-CONTEXT-3 + the M7-2 union snapshot conscious change).
    /// The 14-1 probe pair (ping/count_images) retired at 14-4 T1 — a host
    /// with NO face assembled yields an EMPTY registry (tests assert
    /// the retirement; the whitelist negative rides the snapshot tests).
    /// The closed face is identical across hosts — the dual-host red line:
    /// even a read-only host lists every tool and fails writes at CALL time
    /// (searchState non-nil on EVERY host assembly — data-face absence
    /// answers the typed errors, the tools never disappear).
    /// `searchState` defaults nil so every existing call site and test
    /// compiles zero-diff (the 20-tool face).
    static func makeRegistry(
        editing: EditingToolset.Seams? = nil,
        culling: McpCullingContext? = nil,
        searchState: McpSearchStateContext? = nil,
        project: McpProjectContext? = nil,
        control: McpControlContext? = nil
    ) async -> McpToolRegistry {
        let registry = McpToolRegistry()
        if let editing {
            await EditingToolset.register(into: registry, seams: editing)
        }
        if let culling {
            await McpCullingToolset.registerAll(on: registry, context: culling)
        }
        if let searchState {
            await McpSearchStateToolset.registerAll(on: registry, context: searchState)
        }
        if let project {
            // M7-3 T4: the fourth domain — nil default keeps every existing
            // construction and test at its pre-M7-3 count (zero-diff).
            await McpProjectToolset.registerAll(on: registry, context: project)
        }
        if let control {
            // M7-5-01 (D-M7-5-2): the fifth domain — nil default keeps every
            // existing construction and test at its pre-M7-5 count; hosts
            // that pass a context (headless constant / GUI coordinator)
            // register the three control tools (the union single-value
            // discipline — tools never disappear).
            await McpControlToolset.registerAll(on: registry, context: control)
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
        culling: McpCullingContext? = nil,
        searchState: McpSearchStateContext? = nil,
        project: McpProjectContext? = nil,
        control: McpControlContext? = nil
    ) async throws -> HttpHostHandle {
        warmLutLibrary()
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
            let registry = await makeRegistry(
                editing: editing, culling: culling, searchState: searchState,
                project: project, control: control)
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
    /// M7-2-01: `searchState` rides the SAME box (the F-4① fifth seam) —
    /// a preference off→on toggle re-assembles from the box, so the three
    /// search/state tools cannot silently vanish when the user flips MCP
    /// off and back on within one GUI session.
    static func startEmbeddedIfPreferenceEnabled(
        editing: EditingToolset.Seams?,
        culling: McpCullingContext?,
        searchState: McpSearchStateContext? = nil,
        project: McpProjectContext? = nil,
        control: McpControlContext? = nil
    ) async {
        withEmbeddedState { state in
            state.editing = editing
            state.culling = culling
            state.searchState = searchState
            state.project = project
            // M7-5-01 (the sixth seam, the F-4① fifth-seam lineage
            // numbering — NOT the box field order): the control face rides
            // the same box so an off→on preference toggle re-assembles the
            // three control tools (they cannot silently vanish).
            state.control = control
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
            let (editing, culling, searchState, project, control) =
                withEmbeddedState { state in
                    (state.editing, state.culling, state.searchState,
                     state.project, state.control)
                }
            let exposure: McpExposure =
                UserDefaults.standard.bool(forKey: lanExposureEnabledKey)
                ? .lan : .loopback
            let handle = try await startHTTPHost(
                paths: McpEndpointPaths.makeDefault(),
                exposure: exposure,
                editing: editing,
                culling: culling,
                searchState: searchState,
                project: project,
                control: control)
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
        var searchState: McpSearchStateContext?
        /// M7-3 T4 (the F-4① fifth-seam shape, project face): the box
        /// carries the project context too so an off→on preference toggle
        /// re-assembles the three project tools (they cannot silently
        /// vanish across a toggle).
        var project: McpProjectContext?
        /// M7-5-01 T1 (the SIXTH seam — the F-4① lineage numbering, NOT the
        /// field order; D-M7-5-10): the control face rides the same box for
        /// the same toggle-visibility guarantee.
        var control: McpControlContext?
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

    /// Best-effort stdout flush for the lock fixture. `fsync(2)` is only
    /// meaningful on regular files — on a pipe (the McpHostTests spawn shape)
    /// it returns EINVAL and Foundation raises an uncatchable ObjC exception
    /// (SIGABRT at app startup, observed 2026-09-29). `print` has already
    /// delivered the bytes ON A REGULAR FILE — on a pipe the C stdio stream
    /// is FULL-buffered and the bytes sit in the buffer until exit, which
    /// the park-until-EOF fixture never reaches; the McpHostTests handshake
    /// deadline is on the PIPE, so flush the stream explicitly first (the
    /// M2-3-3 acceptance rerun: the three flock tests hung deterministically
    /// without this line — the sampled child was parked in read() with the
    /// LOCKED line still buffered).
    private static func syncStdoutBestEffort() {
        // fflush moves the C-stdio user-space buffer into the fd (pipe-safe);
        // the raw fsync(2) then flushes the fd with the errno merely ignored.
        // Foundation's FileHandle.synchronizeFile is banned here — it raises
        // an uncatchable ObjC exception on ANY error (EINVAL on pipes
        // 21:16, still raised on the fstat-guarded regular-file path
        // 21:38 — likely a read-only/special fd) and took the host down
        // twice on 2026-09-29. print's bytes live in the fd either way.
        fflush(stdout)
        fsync(STDOUT_FILENO)
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
            syncStdoutBestEffort()
        case .failure(let error):
            print("LOCK-FAIL \(error)")
            syncStdoutBestEffort()
            exit(3)
        }
        // Park until stdin EOF (the test harness closes the pipe), then
        // exit cleanly — releasing the lock through the kernel.
        let _ = FileHandle.standardInput.readDataToEndOfFile()
        exit(0)
    }

    /// The `-la_project_hold_lock <lalb路径>` fixture mode (M6-1-01 T6,
    /// KD-4 — the `-la_mcp_hold_lock` shape on the PROJECT lock): acquire
    /// the `<stem>.lalb.lock` writer right, write the headless payload,
    /// print PROJECT-LOCKED, then park until stdin closes (EOF = the
    /// parent is done with us). The arbitration tests spawn THIS HOST
    /// BINARY with the flag to exercise the real two-process project-lock
    /// states. Never ships: #if DEBUG.
    static func holdProjectLockFixtureIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-la_project_hold_lock"),
            arguments.count > index + 1
        else { return false }
        let packageURL = URL(fileURLWithPath: arguments[index + 1])
        let lockURL = packageURL.deletingPathExtension()
            .appendingPathExtension("lalb.lock")
        switch SingleWriterLock.acquire(at: lockURL) {
        case .success(let lock):
            lock.writePayload(
                SingleWriterLockPayload(
                    role: .headless, pid: getpid(),
                    startedAt: SingleWriterLockPayload.nowISO8601()))
            print("PROJECT-LOCKED \(lockURL.path)")
            syncStdoutBestEffort()
        case .failure(let error):
            print("PROJECT-LOCK-FAIL \(error)")
            syncStdoutBestEffort()
            exit(3)
        }
        // Park until stdin EOF, then exit cleanly (kernel release).
        let _ = FileHandle.standardInput.readDataToEndOfFile()
        exit(0)
    }
    #endif
}
