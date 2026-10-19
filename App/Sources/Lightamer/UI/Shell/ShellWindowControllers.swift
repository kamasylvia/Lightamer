import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ShellWindowControllers (F0P-01 T4 — the untracked-read gap 3's three
// secondary windows productionized).
//
// The three SwiftUI `Window`/`Settings` scenes become AppKit window
// controllers (NSWindow + NSHostingView + the standard `showWindow` seam),
// each injecting the SAME environment objects its scene did (the HEAD
// scene shapes, translated verbatim — the plan's env-injection alignment):
//   - PresetManagerWindowController: PresetManagerWindow + presetsStore +
//     presetController + dark, 520×480;
//   - McpLauncherWindowController: McpLauncherPanelView, 720×480 (the
//     launcher core is the process-wide McpLauncher.shared — untouched);
//   - SettingsWindowController: SettingsView(legacyLibraryEnabled:) +
//     catalogPreferences + pipeCoordinator + libraryProjects + dark (the
//     D-F0P-1 REAL window controller — the spike-only private settings
//     selector never ships).
//
// INERT until the shell handover flips the entry (F0P-01 T6 wires the menu
// closures + the ContentView toolbar seam); the HEAD scenes stay untouched
// (P3's retirement scope).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class PresetManagerWindowController: NSWindowController {

    private let presetsStore: PresetsStore
    private let presetController: PresetController

    init(presetsStore: PresetsStore, presetController: PresetController) {
        self.presetsStore = presetsStore
        self.presetController = presetController
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = String(localized: String.LocalizationValue("window_preset_manager"))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func showWindow(_ sender: Any?) {
        guard let window else { return }
        if window.contentView == nil {
            window.contentView = NSHostingView(rootView:
                PresetManagerWindow()
                    .environment(presetsStore)
                    .environment(presetController)
                    .preferredColorScheme(.dark) // D-10: v1 forced dark
            )
        }
        window.center()
        window.makeKeyAndOrderFront(sender)
    }
}

@MainActor
final class McpLauncherWindowController: NSWindowController {

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = String(localized: String.LocalizationValue("window_mcp_launcher"))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func showWindow(_ sender: Any?) {
        guard let window else { return }
        if window.contentView == nil {
            window.contentView = NSHostingView(rootView: McpLauncherPanelView())
        }
        window.center()
        window.makeKeyAndOrderFront(sender)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {

    private let legacyLibraryEnabled: Bool
    private let catalogPreferences: CatalogPreferencesModel
    private let pipeCoordinator: PipeCoordinator
    private let libraryProjects: LibraryProjectController

    init(legacyLibraryEnabled: Bool,
         catalogPreferences: CatalogPreferencesModel,
         pipeCoordinator: PipeCoordinator,
         libraryProjects: LibraryProjectController) {
        self.legacyLibraryEnabled = legacyLibraryEnabled
        self.catalogPreferences = catalogPreferences
        self.pipeCoordinator = pipeCoordinator
        self.libraryProjects = libraryProjects
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func showWindow(_ sender: Any?) {
        guard let window else { return }
        if window.contentView == nil {
            window.contentView = NSHostingView(rootView:
                SettingsView(legacyLibraryEnabled: legacyLibraryEnabled)
                    .environment(catalogPreferences)
                    .environment(pipeCoordinator)
                    // Plan M2-10-07: the LCR page's registry + active-model
                    // reads ride the OPEN project controller (the scene's
                    // third injection, verbatim).
                    .environment(libraryProjects)
                    .preferredColorScheme(.dark) // D-10: v1 forced dark
            )
        }
        window.center()
        window.makeKeyAndOrderFront(sender)
    }
}
