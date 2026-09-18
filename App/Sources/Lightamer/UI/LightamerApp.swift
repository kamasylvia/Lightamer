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
/// buffered and flushed on first appearance.
internal final class AppDelegate: NSObject, NSApplicationDelegate {
    var openHandler: (([URL]) -> Void)?
    private var buffered: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let openHandler {
            openHandler(urls)
        } else {
            buffered.append(contentsOf: urls)
        }
    }

    /// Drains opens that arrived before the handler was installed.
    func flushBuffered() -> [URL] {
        let pending = buffered
        buffered = []
        return pending
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
                .task {
                    // Wire the pipe owner ↔ editor state pair (both weakly
                    // linked, root-owned strongly). Runs before any open is
                    // drained below, so the first decode already has its
                    // render path.
                    editorState.attach(pipeCoordinator: pipeCoordinator)
                    pipeCoordinator.attach(editorState: editorState)

                    // Register the IOP framework's default.metallib (which
                    // carries the pass_through kernel) with the dispatch
                    // context. Plan 04's pixelpipe dispatches through it;
                    // registering at the app root keeps the pipeline ready.
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
                    resizeProbeIfRequested()
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
}
