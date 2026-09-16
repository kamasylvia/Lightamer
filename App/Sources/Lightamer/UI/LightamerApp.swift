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

/// App entry point.
///
/// Owns the four D-03b state objects at the root via `@State` (D-35:
/// `@Observable` objects are owned with `@State`, never `@StateObject`) and
/// injects them into the environment. Forces dark mode (D-10).
@main
internal struct LightamerApp: App {

    // D-03b: four isolated state objects — no god-object.
    @State private var sessionState = SessionState()
    @State private var editorState = EditorState()
    @State private var exportState = ExportState()
    @State private var inspectorState = InspectorState()

    /// Column visibility, as seen from the menu commands (View menu toggles).
    @FocusedBinding(\.lightamerColumnVisibility)
    private var focusedColumnVisibility: NavigationSplitViewVisibility?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionState)
                .environment(editorState)
                .environment(exportState)
                .environment(inspectorState)
                .preferredColorScheme(.dark) // D-10: v1 forced dark
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
                // Phase 1 active: file picker → EditorState.load (integration
                // point Plan 02 replaces with the real decode).
                Button(String(localized: "menu_open")) {
                    FileOpener.openImage { editorState.load(url: $0) }
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
