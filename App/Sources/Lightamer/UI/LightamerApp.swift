import CoreImage
import ImageIO
import LightamerCore
import LightamerIOP
import SwiftUI
import os

// ─────────────────────────────────────────────────────────────────────────────
// Focused-value plumbing: the split-view column visibility lives in
// ContentView (it owns the NavigationSplitView), but the View menu commands
// run in the App scene. `focusedSceneValue` + `@FocusedBinding` bridge the
// two without shared mutable globals.
// ─────────────────────────────────────────────────────────────────────────────

internal struct LightamerColumnVisibilityKey: FocusedValueKey {
    typealias Value = Binding<NavigationSplitViewVisibility>
}

internal extension FocusedValues {
    var lightamerColumnVisibility: Binding<NavigationSplitViewVisibility>? {
        get { self[LightamerColumnVisibilityKey.self] }
        set { self[LightamerColumnVisibilityKey.self] = newValue }
    }
}

/// Handles the open-document Apple Event (Finder double-click, `open` CLI,
/// drag onto the Dock icon) so declared CFBundleDocumentTypes actually route
/// into `EditorState.load`. Opens that arrive before the scene is ready are
/// buffered and flushed on first appearance. Also bridges
/// `applicationWillTerminate` into the coordinator's sidecar flush (02-06,
/// D-S3) — the AppKit callback is synchronous and chosen over
/// `scenePhase`/notification observers because it is the ONLY termination
/// signal delivered deterministically on the main thread before exit.
internal final class AppDelegate: NSObject, NSApplicationDelegate {
    var openHandler: (([URL]) -> Void)?
    private var buffered: [URL] = []

    /// 02-06: the synchronous flush bridge, installed by the app root once
    /// the state graph is wired. NSApplicationDelegate callbacks arrive on
    /// the main thread; `@MainActor @Sendable` is the sanctioned closure
    /// shape for main-thread state capture, and the call site proves the
    /// thread via `MainActor.assumeIsolated`.
    var terminateHandler: (@MainActor @Sendable () -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        if let openHandler {
            openHandler(urls)
        } else {
            buffered.append(contentsOf: urls)
        }
    }

    /// D-S3: force the pending sidecar write before the process exits
    /// (bounded wait inside the handler; a hung volume must not block
    /// termination forever).
    func applicationWillTerminate(_ application: NSApplication) {
        guard let handler = terminateHandler else { return }
        MainActor.assumeIsolated {
            handler()
        }
    }

    /// Drains opens that arrived before the handler was installed.
    func flushBuffered() -> [URL] {
        let pending = buffered
        buffered = []
        return pending
    }
}

/// D-COL2 window capture (Plan 02-04-05): an invisible accessory view that
/// reports its hosting `NSWindow` the moment SwiftUI places it
/// (`viewDidMoveToWindow` also fires on window changes). The least-invasive
/// window source — no invasive scene introspection, no AppKit window
/// subclassing; the app root forwards the window to
/// `PipeCoordinator.configure(window:)`.
private struct WindowCapture: NSViewRepresentable {

    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> CaptureView {
        CaptureView(onWindow: onWindow)
    }

    func updateNSView(_ view: CaptureView, context: Context) {}

    final class CaptureView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}

/// App entry point.
///
/// Owns the four D-03b state objects at the root via `@State` (D-35:
/// `@Observable` objects are owned with `@State`, never `@StateObject`) and
/// injects them into the environment. Forces dark mode (D-10).
@main
internal struct LightamerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // D-03b: isolated state objects — no god-object. PipeCoordinator
    // (Plan 02-03-04) owns the multi-resolution pipes and is the ONLY
    // writer of `editorState.displayTexture`; the app root owns both
    // strongly and each holds a single weak back-reference to the other.
    @State private var sessionState = SessionState()
    @State private var editorState = EditorState()
    @State private var pipeCoordinator = PipeCoordinator()
    @State private var exportState = ExportState()
    @State private var inspectorState = InspectorState()
    // Plan 06-05 T3: the layer-selection + editing-mode state machine
    // (viewport gesture arbitration归口 — D-03b isolated state object).
    @State private var layerEditingState = LayerEditingState()

    /// Plan 09-01 T1: the session open/switch/teardown orchestrator.
    /// Closure seams are wired in the scene `.task` (D-03b: no state
    /// references at construction).
    @State private var sessionCoordinator = SessionCoordinator()

    /// Plan 09-01 T4: the session-index owner (the real ④ sync and ②-d
    /// close legs of the session coordinator).
    @State private var sessionIndexController = SessionIndexController()

    /// Plan 09-02 T3: the four-schedule reconcile owner (focus / event
    /// batch / forced legs; the open leg is the coordinator's own sync).
    /// Lifecycle is composed into the coordinator's closure seams below —
    /// start after a successful open sync, stop at the teardown's index
    /// close (no Step-enum change, the 09-01 stepLog order stays pinned).
    @State private var sessionReconciler = SessionReconciler()

    /// Plan 07-3: the layer-B download model — app-root owned so the
    /// AIDownloadPrompt surfaces AND the MaskToolbar's layer-B entry gate
    /// observe ONE instance (the AIAssetStore actor stays the truth).
    @State private var aiDownloadModel = AIDownloadModel()

    /// Plan 09-3: the browser collection model (rows + selection), the
    /// thumbnail memory LRU (a session switch drains it — teardown ②) and
    /// the thumbnail pipeline (REBUILT per session on the new store; nil
    /// before the first open).
    @State private var browserModel = SessionBrowserModel()
    @State private var thumbnailMemoryCache = ThumbnailMemoryCache()
    @State private var thumbnailProvider: SessionThumbnailProvider?

    /// Plan 09-04 (HIST-05): the adjustments clipboard, the batch sidecar
    /// write queue (rebuilt per session beside the thumbnail provider) and
    /// the partial-paste dialog request flag (the menu sets it; ContentView
    /// presents the sheet).
    @State private var pasteboard = AdjustmentsPasteboard()
    @State private var batchSidecarWriter: BatchSidecarWriter?
    @State private var pastePartialRequested = false

    /// 09-04 T7 (HIST-06): the before/after presentation state (split /
    /// peek / hold) — reset on image and session switches.
    @State private var beforeAfterState = BeforeAfterState()

    /// The yiyin logo-face source for the thumbnail run-context injector
    /// (a stateless file-probe instance — the coordinator keeps its own).
    @State private var browserLogoStore = YiyinLogoStore()

    /// The decode actor (D-21) — one app-wide instance, injected into
    /// `ContentView` so every Open path feeds `EditorState.load`.
    @State private var decoder = RAWDecoder()

    /// The module registry (Plan 02-04-05): terminal trio self-registered
    /// in `ModuleRegistry.init()`; LightamerIOP's modules join via
    /// `LightamerIOPRegistry.populate` in the scene `.task`. One registry
    /// per app; the coordinator resolves default chains from it.
    @State private var moduleRegistry = ModuleRegistry.makeDefault()

    /// The app-owned Metal dispatch context (D-14/15; RESEARCH Open Question
    /// #2 — owned via `@State` and injected, never a singleton). nil = no
    /// Metal GPU → the fatal `.metalDeviceUnavailable` alert (UI-SPEC).
    @State private var metalContext: MetalContext? = (try? MetalContext())

    init() {
        #if DEBUG
        // 07-1 T2: the headless cross-process determinism probe — runs at
        // INIT (pre-scene, pre-window; environment-independent) and exits
        // the process when its verdict lands.
        Self.runAIDeterminismProbeIfRequested()
        #endif
    }

    /// Column visibility, as seen from the menu commands (View menu toggles).
    @FocusedBinding(\.lightamerColumnVisibility)
    private var focusedColumnVisibility: NavigationSplitViewVisibility?

    var body: some Scene {
        // SINGLE WINDOW (Plan 02-01, UAT issue #1 ROOT CAUSE): SwiftUI's
        // WindowGroup opens a NEW WINDOW per incoming odoc Apple Event on
        // macOS 27. Every `open` of a second image spawned an extra window
        // whose fresh EditorMTKView raced the shared state (created while
        // `displayTexture` was still nil during the decode) and covered the
        // window that actually displayed — the "black viewport on reopen".
        // The first open worked because opens arriving during launch are
        // buffered by AppDelegate and flushed into the FIRST window.
        // 10 windows / 10 MTKViews were created across the 9-open UAT
        // sequence (view-identity probes). One editor = one window until
        // Phase 9 revisits multi-window Session management.
        Window("Lightamer", id: "main") {
            ContentView(
                decoder: decoder, metalContext: metalContext,
                browserModel: browserModel, thumbnailProvider: thumbnailProvider,
                pasteboard: pasteboard,
                onPartialPasteRequested: { pastePartialRequested = true },
                onPartialPaste: { selection, mode in
                    await pasteToSelection(selection: selection, mode: mode)
                },
                pastePartialRequested: $pastePartialRequested
            )
                .environment(sessionState)
                .environment(sessionCoordinator)
                .environment(editorState)
                .environment(pipeCoordinator)
                .environment(beforeAfterState)
                .environment(exportState)
                .environment(inspectorState)
                .environment(layerEditingState)
                .environment(aiDownloadModel)
                .preferredColorScheme(.dark) // D-10: v1 forced dark
                // D-COL2 (Plan 02-04-05): capture the editor window the
                // moment SwiftUI places it — the coordinator follows THE
                // WINDOW's screen (multi-display: window's screen wins).
                .background(WindowCapture { window in
                    pipeCoordinator.configure(window: window)
                })
                .task {
                    // Wire the pipe owner ↔ editor state pair (both weakly
                    // linked, root-owned strongly). Runs before any open is
                    // drained below, so the first decode already has its
                    // render path.
                    editorState.attach(pipeCoordinator: pipeCoordinator)
                    pipeCoordinator.attach(editorState: editorState)

                    // Plan 09-01 T1: wire the session orchestrator's
                    // closure seams (flush/teardown/route/toast — all
                    // closures, D-03b). ensureDirectories/closeIndex/sync
                    // land with T2/T4; the defaults are inert no-ops.
                    sessionCoordinator.configure(
                        appState: sessionState,
                        flushCurrentImage: {
                            await pipeCoordinator.flushSidecar()
                        },
                        teardownRenderer: {
                            await pipeCoordinator.prepareForSessionSwitch()
                        },
                        closeIndexHandler: {
                            // 09-02 T3: disarm the watcher BEFORE the index
                            // closes (no events into a closed store).
                            sessionReconciler.stopSession()
                            // 09-04 T4: flush the batch sidecar queue's
                            // remainder BEFORE the index closes (the
                            // teardown seam — pending writes must land or
                            // stay honestly dirty before reopen heals).
                            if let writer = batchSidecarWriter {
                                await writer.flushForTeardown()
                                batchSidecarWriter = nil
                            }
                            await sessionIndexController.close()
                        },
                        ensureDirectoriesHandler: { url in
                            try SessionLayout.ensureDirectories(at: url)
                        },
                        syncIndexHandler: { url in
                            let result = await sessionIndexController.openAndSync(root: url)
                            // 09-02 T3 ①: arm the watcher AFTER the full
                            // open sync (a failed sync leaves it disarmed).
                            if !result.failed {
                                sessionReconciler.startSession(root: url)
                                // 09-02 T4: the open-time orphan snapshot.
                                sessionState.setOrphanSidecarRelPaths(
                                    await sessionIndexController.actionableOrphans()
                                )
                                // 09-3: REBUILD the thumbnail pipeline on
                                // the NEW store (the old provider's queue
                                // was cancelled by the teardown ② above)
                                // and land the authoritative collection
                                // (orphans included as placeholder cells).
                                if let store = sessionIndexController.currentStore {
                                    thumbnailProvider = SessionThumbnailProvider(
                                        sessionRoot: url,
                                        store: store,
                                        disk: ThumbnailDiskStore(sessionRoot: url),
                                        memory: thumbnailMemoryCache,
                                        registry: moduleRegistry,
                                        decoder: decoder,
                                        renderLeg: metalContext.map {
                                            SessionThumbnailRenderer.renderLeg(metal: $0)
                                        },
                                        runContextInjector:
                                            SessionThumbnailRenderer.runContextInjector(
                                                yiyinLogoStore: browserLogoStore
                                            )
                                    )
                                    // 09-04 T4: the segment-3 serial write
                                    // queue, rebuilt on the NEW store.
                                    batchSidecarWriter = BatchSidecarWriter(
                                        root: url, store: store)
                                }
                                if let store = sessionIndexController.currentStore {
                                    await browserModel.finishProgressiveIngest(
                                        store: store, includeOrphans: true
                                    )
                                }
                            }
                            return result
                        },
                        routeImage: { url in
                            editorState.load(
                                url: url,
                                decoder: decoder,
                                metal: metalContext,
                                logger: EditorState.decodeLogger
                            )
                        },
                        reportError: { editorState.presentToast($0) }
                    )

                    // Plan 09-3: the progressive-ingest seam — scanner
                    // pages land as placeholder grid rows BEFORE the sync
                    // transaction commits (边扫边出).
                    sessionIndexController.scanPageObserver = { page in
                        browserModel.ingestPlaceholderPage(entries: page.entries)
                    }

                    // Plan 09-02 T3: wire the reconciler's seams (state +
                    // the real index legs; the same D-03b closure shape).
                    sessionReconciler.appState = sessionState
                    sessionReconciler.reconcileHandler = { url in
                        let outcome = await sessionIndexController.reconcile(root: url)
                        if let counts = outcome?.counts {
                            sessionState.setBrowseCounts(counts)
                        }
                        if let orphans = outcome?.orphanRelPaths {
                            sessionState.setOrphanSidecarRelPaths(orphans)
                        }
                        return outcome?.plan
                    }
                    sessionReconciler.staleMarkHandler = { paths in
                        await sessionIndexController.markStale(relPaths: paths)
                    }

                    // Plan 09-02 T4: the orphan actions (never hard-fail —
                    // a failed remove surfaces as a no-op) + the snapshot
                    // refresh each action trails with.
                    sessionCoordinator.removeOrphanSidecar = { rel in
                        guard let root = sessionState.currentSessionURL else {
                            return false
                        }
                        let removed = await sessionIndexController.removeOrphanSidecar(
                            root: root, relPath: rel
                        )
                        if removed {
                            sessionState.setOrphanSidecarRelPaths(
                                await sessionIndexController.actionableOrphans()
                            )
                        }
                        return removed
                    }
                    sessionCoordinator.ignoreOrphanSidecar = { rel in
                        await sessionIndexController.setOrphanIgnored(
                            relPath: rel, ignored: true
                        )
                        sessionState.setOrphanSidecarRelPaths(
                            await sessionIndexController.actionableOrphans()
                        )
                    }

                    // 02-04: register LightamerIOP's modules into the
                    // registry (testgain in DEBUG; Phase 3+ joins here),
                    // then hand the registry to the coordinator so loads
                    // resolve the terminal-trio default chain.
                    await LightamerIOPRegistry.populate(moduleRegistry)
                    pipeCoordinator.attach(registry: moduleRegistry)

                    // Plan 03-02-T3 (D-T6): register the Inspector panel
                    // providers (exposure + temperature are the first two).
                    inspectorState.registerDefaultProviders()

                    // Plan 04-04-T3: resolve the Lensfun database (custom
                    // path > downloaded copy > absent-downgrade; sync,
                    // no network at launch — first download is panel-driven).
                    _ = LensfunDownloadService.resolveAndInstall()

                    // Register the IOP framework's default.metallib (which
                    // carries the pass_through kernel) with the dispatch
                    // context. Plan 04's pixelpipe dispatches through it;
                    // registering at the app root keeps the pipeline ready.
                    // Core's own metallib (terminal trio kernels) resolves
                    // automatically inside MetalContext.
                    if let metalContext {
                        try? await metalContext.registerDefaultLibrary(
                            in: PassthroughKernel.metalBundle
                        )
                    }
                    // Wire the open-document Apple Event (Finder / `open` /
                    // Dock drops) into the same load path as File → Open,
                    // then drain any opens that arrived during launch.
                    // Plan 09-01: a DIRECTORY open routes to the session
                    // path (same-window L012 — never a new window).
                    let routeOpen: @MainActor (URL) -> Void = { url in
                        let isDirectory = (try? url.resourceValues(
                            forKeys: [.isDirectoryKey]
                        ))?.isDirectory ?? false
                        if isDirectory {
                            Task { await sessionCoordinator.openSession(url: url) }
                        } else {
                            editorState.load(
                                url: url,
                                decoder: decoder,
                                metal: metalContext,
                                logger: EditorState.decodeLogger
                            )
                        }
                    }
                    appDelegate.openHandler = { urls in
                        for url in urls {
                            routeOpen(url)
                        }
                    }
                    for url in appDelegate.flushBuffered() {
                        routeOpen(url)
                    }
                    // 02-06 (D-S3): quit/termination forces the pending
                    // sidecar write through the AppDelegate's synchronous
                    // willTerminate callback.
                    appDelegate.terminateHandler = {
                        pipeCoordinator.flushForTermination()
                    }
                    #if DEBUG
                    resizeProbeIfRequested()
                    sidecarProbeIfRequested()
                    #endif
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified) // UI-SPEC: unified toolbar
        .commands {
            // ── File ────────────────────────────────────────────────
            CommandGroup(replacing: .newItem) {
                // Phase 9 — disabled in Phase 1 (UI-SPEC Menu Bar table).
                Button(String(localized: "menu_new_session")) {}
                    .disabled(true)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                // Phase 1 active: file picker → EditorState.load (real
                // RAWDecoder decode since Plan 02).
                Button(String(localized: "menu_open")) {
                    FileOpener.openImage {
                        editorState.load(
                            url: $0,
                            decoder: decoder,
                            metal: metalContext,
                            logger: EditorState.decodeLogger
                        )
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                // Plan 09-01 (SESS-01): pick a folder → the session path
                // (same-window routing; FileOpener.openFolder's panel
                // wrapper reused).
                Button(String(localized: "menu_open_session")) {
                    FileOpener.openSessionFolder { url in
                        Task { await sessionCoordinator.openSession(url: url) }
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                // Plan 09-01 fills the recent-sessions list (SESS-04); the
                // rows route into the SAME openSession path (L012).
                Menu(String(localized: "menu_open_recent")) {
                    ForEach(sessionState.recentSessions, id: \.absoluteString) { url in
                        Button(url.lastPathComponent) {
                            Task { await sessionCoordinator.openSession(url: url) }
                        }
                    }
                }
                .disabled(sessionState.recentSessions.isEmpty)
                Divider()
                // Phase 9 — disabled. (No .closeItem placement in SwiftUI's
                // CommandGroupPlacement, so it sits with the File items.)
                Button(String(localized: "menu_close_session")) {}
                    .disabled(true)
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                // Phase 2 (sidecar) — disabled.
                Button(String(localized: "menu_save_sidecar")) {}
                    .disabled(true)
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                // Phase 11 — disabled.
                Button(String(localized: "menu_export")) {}
                    .disabled(true)
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // ── Edit ────────────────────────────────────────────────
            // 04-08-F2 (GUI-9 闭环): Undo/Redo 接 Phase 2 HistoryStack 真
            // 栈语义 —— EditorState.performUndo/performRedo + coordinator
            // 重渲染（historyDidChange），不再是 Phase 1 的 disabled 占位.
            // enabled 跟随 canUndo/canRedo（@Observable 绑定，commit 后
            // 自动点亮，无需手动刷新）.
            CommandGroup(replacing: .undoRedo) {
                Button(String(localized: "menu_undo")) {
                    Task { await pipeCoordinator.undo() }
                }
                .disabled(!editorState.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                Button(String(localized: "menu_redo")) {
                    Task { await pipeCoordinator.redo() }
                }
                .disabled(!editorState.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                Divider()
                // 09-04 HIST-05 (was the Phase 9 disabled placeholder):
                // copy freezes the CURRENT image's effective adjustments;
                // paste routes the frozen payload onto the browser
                // selection (batch) or the current image (live).
                Button(String(localized: "menu_copy_adjustments")) {
                    Task { await copyAdjustments() }
                }
                .disabled(editorState.loadedImageURL == nil)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button(String(localized: "menu_paste_adjustments")) {
                    Task { await pasteToSelection(selection: nil, mode: .merge) }
                }
                .disabled(!pasteboard.hasPayload)
                .keyboardShortcut("v", modifiers: [.command, .shift])
                Button(String(localized: "menu_paste_partial")) {
                    pastePartialRequested = true
                }
                .disabled(!pasteboard.hasPayload)
            }

            // ── View ────────────────────────────────────────────────
            CommandMenu(String(localized: "menu_view")) {
                Button(String(localized: "menu_show_sidebar")) { toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button(String(localized: "menu_show_inspector")) { toggleInspector() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
                // D-13: no zoom/pan in Phase 1 — disabled.
                Button(String(localized: "menu_actual_size")) {}
                    .disabled(true)
                    .keyboardShortcut("z", modifiers: [])
                Button(String(localized: "menu_fit_to_screen")) {}
                    .disabled(true)
                    .keyboardShortcut("f", modifiers: [])
            }

            // ── Help ────────────────────────────────────────────────
            CommandGroup(replacing: .help) {
                // Phase 13 fills; placeholder in Phase 1.
                Button(String(localized: "menu_help")) {}
                    .disabled(true)
                    .keyboardShortcut("?", modifiers: .command)
            }
        }

        // Settings… (Cmd+,) — empty placeholder window; Phase 13 fills.
        Settings {
            Text("settings_placeholder")
                .frame(width: 360, height: 120)
        }
    }

    // MARK: - View menu actions (via focused binding into ContentView)

    /// D-X2 probe (Plan 02-03 manual resize verification — RETIRE after
    /// verification per the D-X2 probe policy): osascript/AX window
    /// resizing is unavailable to headless drivers (no Accessibility grant
    /// for the CLI), so `-la_resize_probe` drives the REAL window-geometry
    /// chain (NSWindow.setFrame → drawable resize → GeometryReader →
    /// `PipeCoordinator.drawableDidChange`) through a scripted sequence
    /// sized for this 1504×846pt display (viewport ≈ window − 260pt, long
    /// edge height-capped): t+6s within-bucket grow (2200 stays 2200),
    /// t+14s aggressive shrink crossing down to the 1120 bucket (exactly
    /// one re-render), t+22s within-bucket jitter (no re-render).
    /// `#if DEBUG`: never ships.
    #if DEBUG
    private nonisolated(unsafe) static var resizeProbeArmed = false
    private func resizeProbeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-la_resize_probe") else { return }
        guard !Self.resizeProbeArmed else { return } // .task can re-run on scene re-activation
        Self.resizeProbeArmed = true
        let logger = Logger(subsystem: "com.kamasylvia.lightamer", category: "probe")
        logger.info("resize probe armed")
        let sequence: [(Double, CGFloat, CGFloat)] = [
            (6, 1460, 920), // grow within the current bucket → no re-render
            (14, 1000, 700), // cross DOWN a bucket boundary → exactly one re-render
            (22, 990, 695), // jitter within the new bucket → no re-render
        ]
        for (delay, width, height) in sequence {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                for window in NSApp.windows where window.isVisible {
                    var frame = window.frame
                    frame.origin.y += frame.height - height
                    frame.size = CGSize(width: width, height: height)
                    window.setFrame(frame, display: true)
                    logger.info("resize probe: window → \(Int(width))×\(Int(height))")
                }
            }
        }
    }
    #endif

    // ── 09-04 HIST-05: copy + paste routing (the app-root owns the whole
    // state graph — the menu commands orchestrate, the states never
    // reference each other, D-03b) ─────────────────────────────────────────

    /// ⌘⇧C: freeze the CURRENT image's effective adjustments into the
    /// clipboard (the skip set applies inside `compose`).
    private func copyAdjustments() async {
        guard editorState.loadedImageURL != nil else { return }
        let effective = editorState.history.effectiveInstances()
        let layerRecord = editorState.layerStack
            .map { SidecarLayerStackRecord($0) }
            .flatMap { $0.layers.isEmpty ? nil : $0 }
        let payload = PastePayload.compose(
            sourceImageID: pipeCoordinator.currentImageID ?? UUID(),
            sourceURL: editorState.loadedImageURL,
            sourceInstances: editorState.instances,
            sourceEffective: effective,
            seed: await seedInstances(),
            layerStack: layerRecord)
        pasteboard.copy(payload)
    }

    /// ⌘⇧V / the partial dialog's paste: route the payload onto the
    /// browser selection (batch, segments 1-3) with the CURRENT image's
    /// relPath carved out as the LIVE target (dt
    /// `_safe_history_job_on_imgid`: the edited image goes through the
    /// interactive layer, never the batch loop). Without a session
    /// selection, the current image alone is the live target.
    private func pasteToSelection(
        selection: Set<PastePayload.InstanceKey>?, mode: PasteMode
    ) async {
        guard let payload = pasteboard.peek(), !payload.instances.isEmpty else {
            return
        }
        let seed = await seedInstances()
        let targets = browserModel.selectedOrderedPaths
        let sessionRoot = sessionState.currentSessionURL
        let store = sessionIndexController.currentStore

        if let sessionRoot, let store, !targets.isEmpty {
            // The live relPath: the currently edited image, relative to the
            // session root (nil when nothing is loaded / outside the root).
            var liveRelPaths = Set<String>()
            if let loaded = editorState.loadedImageURL {
                let loadedPrefix = sessionRoot.path + "/"
                if loaded.path.hasPrefix(loadedPrefix) {
                    liveRelPaths.insert(String(loaded.path.dropFirst(loadedPrefix.count)))
                }
            }
            _ = await SessionBatchApplier.apply(
                root: sessionRoot,
                relPaths: targets,
                payload: payload,
                mode: mode,
                seed: seed,
                selection: selection,
                liveRelPaths: liveRelPaths,
                store: store,
                writer: batchSidecarWriter,
                label: String(localized: "history_paste_adjustments"))
            // The grid's hasEdits/dirty badges refresh from the claimed
            // rows (the thumbnails regenerate through the 9-3 queue).
            await browserModel.reload(store: store, includeOrphans: true)
            // The LIVE target pastes through the interactive layer (the
            // composed stack lands via EditorState; ONE ⌘Z undoes it).
            if let liveRel = liveRelPaths.first, targets.contains(liveRel) {
                await pasteLive(payload: payload, selection: selection, mode: mode, seed: seed)
            }
        } else if editorState.loadedImageURL != nil {
            // No session selection — the current image is the target.
            await pasteLive(payload: payload, selection: selection, mode: mode, seed: seed)
        }
    }

    /// The LIVE paste leg (the currently edited image): compose against
    /// EditorState's in-memory stack and install — ONE commit, ⌘Z-able.
    private func pasteLive(
        payload: PastePayload, selection: Set<PastePayload.InstanceKey>?,
        mode: PasteMode, seed: [ModuleInstance]
    ) async {
        let composed = PasteSemantics.paste(
            targetHistory: editorState.history,
            targetInstances: editorState.instances,
            payload: payload,
            mode: mode,
            seed: seed,
            selection: selection,
            label: String(localized: "history_paste_adjustments"))
        guard let composed else { return }
        switch mode {
        case .merge:
            editorState.installMergePaste(history: composed.history)
        case .overwrite:
            editorState.installOverwritePaste(
                history: composed.history, seed: seed)
        }
    }

    /// The identity-default seed (terminal trio + the editing defaults).
    private func seedInstances() async -> [ModuleInstance] {
        (
            await moduleRegistry.makeDefaultInstances()
                + LightamerIOPRegistry.editingDefaultInstances()
        )
        .sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    /// Toggle the sessions sidebar (`.all ↔ .doubleColumn` — content and
    /// detail stay visible).
    private func toggleSidebar() {
        guard let visibility = focusedColumnVisibility else { return }
        focusedColumnVisibility = (visibility == .doubleColumn) ? .all : .doubleColumn
    }

    /// Toggle the inspector column (`.all ↔ .detailOnly`, per UI-SPEC
    /// Three-Column Layout Dimensions).
    private func toggleInspector() {
        guard let visibility = focusedColumnVisibility else { return }
        focusedColumnVisibility = (visibility == .detailOnly) ? .all : .detailOnly
    }

    // MARK: - 02-06 headless sidecar round-trip probe (DEBUG only)

    #if DEBUG
    /// Headless round-trip driver for the SC#3 acceptance artifact
    /// (`.work/plans/02-06/roundtrip.md`) — `resizeProbeIfRequested`-style:
    /// AX/menus are unavailable to headless drivers, so the probe applies
    /// the edit and quits by itself. Launch via LaunchServices so window
    /// creation is deterministic (direct exec behind a fullscreen space is
    /// flaky): `open -a Lightamer.app <image> --args -la_sidecar_probe` —
    /// the image then arrives through the odoc open event (openHandler);
    /// direct-exec argv images are also covered. Every verdict is mirrored
    /// into the unified log (stdout is detached under `open`).
    ///
    /// Modes, decided by sidecar presence AFTER the first render:
    /// - **edit** (no `.lra` beside the image): commits one `testgain 1.5×`
    ///   history item via the REAL D-H1 trio, waits past the 2s throttle,
    ///   prints the rendered-plane hash, then terminates (the synchronous
    ///   willTerminate flush covers any straggler).
    /// - **verify** (`.lra` exists): logs the restored history/position/
    ///   paramsHash + the rendered-plane hash — run1 vs run2 hashes must
    ///   match for the round-trip to PASS.
    private nonisolated(unsafe) static var sidecarProbeArmed = false

    private func sidecarProbeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-la_sidecar_probe") else { return }
        guard !Self.sidecarProbeArmed else { return } // .task can re-run on re-activation
        Self.sidecarProbeArmed = true
        let probe = Logger(subsystem: "com.kamasylvia.lightamer", category: "probe")

        // argv[0] is the executable path — scan only real arguments. nil =
        // the image arrives through the odoc open event instead.
        let args = ProcessInfo.processInfo.arguments.dropFirst()
        let argImage = args.first(where: {
            !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
        }).map { URL(fileURLWithPath: $0) }

        Task {
            if let url = argImage {
                probe.info("probe armed — loading \(url.lastPathComponent, privacy: .public) from argv")
                editorState.load(
                    url: url, decoder: decoder, metal: metalContext,
                    logger: EditorState.decodeLogger
                )
            } else {
                probe.info("probe armed — waiting for the odoc open event")
                for _ in 0..<200 where editorState.loadedImageURL == nil {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard editorState.loadedImageURL != nil else {
                    print("[probe] FAIL: no image opened within 20s")
                    probe.error("probe FAIL: no image opened within 20s")
                    NSApp.terminate(nil)
                    return
                }
            }
            // Wait for the first rendered plane (decode + PREVIEW leg),
            // then let the GPU command buffer DRAIN before reading bytes —
            // getBytes on shared memory does not wait for in-flight
            // encoders (the verify leg reads ~40ms after the render push;
            // without the drain it hashes half-written memory).
            for _ in 0..<600 where editorState.displayTexture == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(800))
            pipeCoordinator.drainGPUForProbe()
            guard editorState.displayTexture != nil,
                  let url = editorState.loadedImageURL else {
                print("[probe] FAIL: no render within 60s")
                probe.error("probe FAIL: no render within 60s")
                NSApp.terminate(nil)
                return
            }
            let destination = LightamerSidecar.sidecarURL(for: url)

            if FileManager.default.fileExists(atPath: destination.path) {
                // ── VERIFY (run 2) ──
                if ProcessInfo.processInfo.arguments.contains("-la_sidecar_dump"),
                   let image = editorState.image, let metal = metalContext {
                    let inputPlaneOpt = try? await RenderPipeline.render(
                        image: image, layerStack: nil, metal: metal
                    )
                    if let inputPlane = inputPlaneOpt {
                        let rowBytes = inputPlane.width * 16
                        var f = [Float](repeating: 0, count: inputPlane.width * inputPlane.height * 4)
                        f.withUnsafeMutableBufferPointer { ptr in
                            inputPlane.getBytes(
                                ptr.baseAddress!, bytesPerRow: rowBytes,
                                from: MTLRegionMake2D(0, 0, inputPlane.width, inputPlane.height),
                                mipmapLevel: 0
                            )
                        }
                        pipeCoordinator.drainGPUForProbe()
                        let mid = (inputPlane.height / 2 * inputPlane.width + inputPlane.width / 2) * 4
                        AppError.logger.info(
                            "probe input-plane mid RGBA: \(f[mid], privacy: .public) \(f[mid+1], privacy: .public) \(f[mid+2], privacy: .public)"
                        )
                    }
                }
                let restored = editorState.history
                let labels = restored.items.map(\.label).joined(separator: " | ")
                let gainHash = restored.currentValue?.paramsHash ?? 0
                let displayHash = Self.displayPlaneHash(editorState.displayTexture) ?? 0
                print("[probe] mode=verify history=\(restored.position + 1)/\(restored.items.count) position=\(restored.position)")
                print("[probe] labels=\(labels)")
                print("[probe] topParamsHash=\(gainHash)")
                print("[probe] displayHash=\(displayHash)")
                print("[probe] instances=\(editorState.instances.count)")
                probe.info("probe mode=verify history=\(restored.position + 1, privacy: .public)/\(restored.items.count, privacy: .public) position=\(restored.position, privacy: .public) topParamsHash=\(String(gainHash, radix: 16), privacy: .public) displayHash=\(String(displayHash, radix: 16), privacy: .public) instances=\(editorState.instances.count, privacy: .public)")
            } else {
                // ── EDIT (run 1): apply one testgain commit via the trio ──
                let snapshot = ModuleInstance(
                    module: TestGainModule.self, multiName: "probe",
                    params: .init(gain: 1.5)
                )
                pipeCoordinator.beginContinuousEdit()
                await pipeCoordinator.setLiveParams(snapshot)
                await pipeCoordinator.commitContinuousEdit(label: "probe testgain 1.5×")
                probe.info("probe edit committed — waiting for the 2s throttled flush")
                for _ in 0..<200 where !FileManager.default.fileExists(atPath: destination.path) {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard FileManager.default.fileExists(atPath: destination.path) else {
                    print("[probe] FAIL: sidecar not written within 10s")
                    NSApp.terminate(nil)
                    return
                }
                let displayHash = Self.displayPlaneHash(editorState.displayTexture) ?? 0
                print("[probe] mode=edit sidecar flushed: \(destination.lastPathComponent)")
                print("[probe] displayHash=\(displayHash)")
                probe.info("probe mode=edit sidecar flushed, displayHash=\(String(displayHash, radix: 16), privacy: .public)")
            }
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.terminate(nil) // triggers willTerminate → flushForTermination
        }
    }

    /// FNV hash of the display-plane bytes (`.bgra8Unorm` handoff plane;
    /// NOT a drawable — readback is legal). Same-hash run1 vs run2 proves
    /// the restored state re-renders identically (SC#3). With
    /// `-la_sidecar_dump`, the raw bytes also land in /tmp for byte-level
    /// diffing (probe diagnostics only).
    static func displayPlaneHash(_ texture: (any MTLTexture)?) -> UInt64? {
        guard let texture else { return nil }
        let rowBytes = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * texture.height)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
        )
        if ProcessInfo.processInfo.arguments.contains("-la_sidecar_dump") {
            let url = URL(fileURLWithPath: "/tmp/lra-display-dump.bin")
            try? Data(bytes).write(to: url)
            AppError.logger.info(
                "probe dump: \(texture.width, privacy: .public)x\(texture.height, privacy: .public) → /tmp/lra-display-dump.bin"
            )
        }
        return StableHash.hash(bytes)
    }

    // MARK: - 07-1 AI determinism cross-process probe (DEBUG only)

    /// Headless driver for the layer-A determinism gate's CROSS-PROCESS
    /// leg (Plan 07-1 T2): `Lightamer -la_ai_determinism_probe <image>
    /// <output.txt>` — runs ONE gpuPinned layer-A inference over the
    /// image, writes "width height byteIdentity" into `<output.txt>`, and
    /// exits. The test compares this against its own in-process run
    /// (same synthetic PNG fixture both sides). `#if DEBUG`: never ships.
    /// App-INIT-time driver (deterministic: runs before any scene/window
    /// lifecycle — the .task variant proved environment-sensitive).
    static func runAIDeterminismProbeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-la_ai_determinism_probe") else { return }
        let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
        guard let imageIdx = args.firstIndex(of: "-la_ai_determinism_probe"),
              args.count > imageIdx + 2
        else { return }
        let image = URL(fileURLWithPath: args[imageIdx + 1])
        let output = URL(fileURLWithPath: args[imageIdx + 2])
        Task<Void, Never> {
            let probe = Logger(subsystem: "com.kamasylvia.lightamer", category: "probe")
            do {
                guard let data = FileManager.default.contents(atPath: image.path) as CFData?,
                      let source = CGImageSourceCreateWithData(data, nil),
                      let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else {
                    try? "ERROR unreadable-image".write(
                        to: output, atomically: true, encoding: .utf8)
                    exit(0)
                }
                let input = AIMaskInput(ciImage: CIImage(cgImage: cg))
                let plane = try await AIMaskService.subjectMask(
                    input: input, selection: .all, device: .gpuPinned)
                let line = "\(plane.width) \(plane.height) \(plane.byteIdentity)"
                try line.write(to: output, atomically: true, encoding: .utf8)
                probe.info("ai determinism probe: \(line, privacy: .public)")
            } catch {
                try? "ERROR \(error)".write(to: output, atomically: true, encoding: .utf8)
                probe.error("ai determinism probe FAILED: \(String(describing: error), privacy: .public)")
            }
            exit(0)
        }
    }
    #endif
}
