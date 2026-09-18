import LightamerCore
import LightamerIOP
import SwiftUI

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

    // D-03b: four isolated state objects — no god-object.
    @State private var sessionState = SessionState()
    @State private var editorState = EditorState()
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
        WindowGroup {
            ContentView(decoder: decoder, metalContext: metalContext)
                .environment(sessionState)
                .environment(editorState)
                .environment(exportState)
                .environment(inspectorState)
                .preferredColorScheme(.dark) // D-10: v1 forced dark
                .task {
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
