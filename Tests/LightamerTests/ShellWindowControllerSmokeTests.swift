import AppKit
import LightamerCore
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ShellWindowControllerSmokeTests (F0P-02 T4) — the three secondary-window
// controllers (the F0P-01 T4 productionization of the SwiftUI Window/Settings
// scenes) construct, mount their hosting content, and survive a settle pass.
//
// The mount IS the M2-8-3 FINDING-A regression face: a missing environment
// injection traps the content's first update (uncatchable fatalError — the
// bundle run fails hard, by design here, exactly like
// SheetEnvironmentInjectionTests). Reaching the settle pass proves the
// injections are wired.
//
// The main-window autosave seam is not reachable without presenting the full
// face (presentMainWindow mounts ContentView + the whole state graph) — the
// autosave assertion stays at the GUI-walkthrough layer (DECISIONS).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ShellWindowControllerSmokeTests: XCTestCase {

    /// The repo-precedent cleanup shape: window work rides a `defer`
    /// INSIDE the @MainActor test methods (a tearDown override is
    /// nonisolated and cannot touch AppKit main-actor faces).
    private func dismiss(_ window: NSWindow?) {
        window?.orderOut(nil)
        window?.contentView = nil
    }

    private func pump(_ seconds: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    // MARK: - 1: Settings (the three-environment injection face)

    func testSettingsWindowInjectsTheThreeEnvironmentFaces() {
        let controller = SettingsWindowController(
            legacyLibraryEnabled: false,
            catalogPreferences: CatalogPreferencesModel(),
            pipeCoordinator: PipeCoordinator(),
            libraryProjects: LibraryProjectController())
        controller.showWindow(nil)
        guard let window = controller.window else {
            return XCTFail("the settings window never materialized")
        }
        defer { dismiss(window) }

        XCTAssertEqual(window.title, "Settings")
        // type(of:) on the NSView! IUO always prints Optional<NSView> —
        // bind first, then inspect the concrete type name.
        if let content = window.contentView as NSView? {
            XCTAssertTrue(
                String(describing: type(of: content)).contains("NSHostingView"),
                "the settings content must mount through NSHostingView (got \(type(of: content)))")
        } else {
            XCTFail("the settings window has no content view")
        }
        // The settle pass: the content's first environment update runs here
        // — a missing injection traps (the shipped M2-8-3 signature).
        pump()
        XCTAssertTrue(window.isVisible)
    }

    // MARK: - 2: preset-manager + MCP launcher (the remaining two scenes)

    func testPresetManagerAndMcpLauncherControllersMountHostingContent() {
        let presetController = PresetManagerWindowController(
            presetsStore: PresetsStore(),
            presetController: PresetController())
        presetController.showWindow(nil)
        guard let presetWindow = presetController.window else {
            return XCTFail("the preset-manager window never materialized")
        }
        defer { dismiss(presetWindow) }
        XCTAssertEqual(
            presetWindow.title,
            String(localized: String.LocalizationValue("window_preset_manager")))
        if let content = presetWindow.contentView as NSView? {
            XCTAssertTrue(
                String(describing: type(of: content)).contains("NSHostingView"),
                "the preset-manager content must mount through NSHostingView")
        } else {
            XCTFail("the preset-manager window has no content view")
        }
        XCTAssertEqual(
            presetWindow.frame.width, 520, accuracy: 0.5,
            "the preset-manager default size drifted")
        pump()

        let mcpController = McpLauncherWindowController()
        mcpController.showWindow(nil)
        guard let mcpWindow = mcpController.window else {
            return XCTFail("the MCP-launcher window never materialized")
        }
        defer { dismiss(mcpWindow) }
        XCTAssertEqual(
            mcpWindow.title,
            String(localized: String.LocalizationValue("window_mcp_launcher")))
        if let content = mcpWindow.contentView as NSView? {
            XCTAssertTrue(
                String(describing: type(of: content)).contains("NSHostingView"),
                "the MCP-launcher content must mount through NSHostingView")
        } else {
            XCTFail("the MCP-launcher window has no content view")
        }
        XCTAssertEqual(
            mcpWindow.frame.width, 720, accuracy: 0.5,
            "the MCP-launcher default size drifted")

        // The re-show leg: showWindow must re-mount cleanly (the
        // unconditional NSHostingView assignment — the blocking-1 fix).
        presetController.showWindow(nil)
        mcpController.showWindow(nil)
        pump()
        if let content = presetWindow.contentView as NSView? {
            XCTAssertTrue(
                String(describing: type(of: content)).contains("NSHostingView"))
        } else {
            XCTFail("the preset-manager re-show lost the content view")
        }
        if let content = mcpWindow.contentView as NSView? {
            XCTAssertTrue(
                String(describing: type(of: content)).contains("NSHostingView"))
        } else {
            XCTFail("the MCP-launcher re-show lost the content view")
        }
    }
}
