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
            ContentView(decoder: decoder, metalContext: metalContext)
                .environment(sessionState)
                .environment(editorState)
                .environment(pipeCoordinator)
                .environment(exportState)
                .environment(inspectorState)
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

                    // 02-04: register LightamerIOP's modules into the
                    // registry (testgain in DEBUG; Phase 3+ joins here),
                    // then hand the registry to the coordinator so loads
                    // resolve the terminal-trio default chain.
                    await LightamerIOPRegistry.populate(moduleRegistry)
                    pipeCoordinator.attach(registry: moduleRegistry)

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
                    appDelegate.openHandler = { urls in
                        for url in urls {
                            editorState.load(
                                url: url,
                                decoder: decoder,
                                metal: metalContext,
                                logger: EditorState.decodeLogger
                            )
                        }
                    }
                    for url in appDelegate.flushBuffered() {
                        editorState.load(
                            url: url,
                            decoder: decoder,
                            metal: metalContext,
                            logger: EditorState.decodeLogger
                        )
                    }
                    // 02-06 (D-S3): quit/termination forces the pending
                    // sidecar write through the AppDelegate's synchronous
                    // willTerminate callback.
                    appDelegate.terminateHandler = {
                        pipeCoordinator.flushForTermination()
                    }
                    resizeProbeIfRequested()
                    sidecarProbeIfRequested()
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
                // Phase 9 fills the recent-sessions list; empty in Phase 1.
                Menu(String(localized: "menu_open_recent")) {}
                    .disabled(true)
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
            CommandGroup(replacing: .undoRedo) {
                // Phase 2 (history stack) — disabled in Phase 1.
                Button(String(localized: "menu_undo")) {}
                    .disabled(true)
                    .keyboardShortcut("z", modifiers: .command)
                Button(String(localized: "menu_redo")) {}
                    .disabled(true)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Divider()
                // Phase 9 (HIST-05) — disabled.
                Button(String(localized: "menu_copy_adjustments")) {}
                    .disabled(true)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button(String(localized: "menu_paste_adjustments")) {}
                    .disabled(true)
                    .keyboardShortcut("v", modifiers: [.command, .shift])
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
    /// (`.work/02-06/roundtrip.md`) — `resizeProbeIfRequested`-style:
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
    #endif
}
