import AppKit
import LightamerCore
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// NSMenuParityTests (F0P-02 T1) — the shell-handover menu bridge's parity
// suite: the installed NSApp.mainMenu tree mirrors the MenuCommandSet pure
// function's two gate arms, the enabler predicates evaluate the state-object
// truths, the custom shortcuts pin the DefaultKeymap table / the menu
// declarations, and every title resolves beyond its catalog key literal.
//
// Tree-traversal seam (the omp plan-review prescription): build*Menu and
// rootMenu/itemActions/itemEnablers are private, so every test drives the
// INTERNAL seams — a fresh `NSMenuBridgeController()` + stub `Deps` + the
// internal `install(deps:)` (which writes the global `NSApp.mainMenu`) —
// then traverses `NSApp.mainMenu` and probes enablement through the
// refreshed `item.isEnabled` / `item.state` values (the registered closures'
// outputs).
//
// Isolation (the same prescription): install writes the global mainMenu, so
// every test saves/restores `NSApp.mainMenu` around itself; the singleton's
// note boxes are not touched here (fresh instances only — the observation
// suite owns the singleton slot).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class NSMenuParityTests: XCTestCase {

    // MARK: - Stub Deps

    private func makeDeps(
        gate: Bool,
        editorState: EditorState = EditorState(),
        projects: LibraryProjectController = LibraryProjectController(),
        agent: AgentControlCoordinator = AgentControlCoordinator(),
        pasteboard: AdjustmentsPasteboard = AdjustmentsPasteboard(),
        softProof: SoftProofState = SoftProofState()
    ) -> NSMenuBridgeController.Deps {
        .init(
            editorState: editorState,
            sessionState: SessionState(),
            libraryProjects: projects,
            agentControl: agent,
            pasteboard: pasteboard,
            softProofState: softProof,
            inspectorState: InspectorState(),
            legacyLibraryEnabled: gate,
            openImage: {},
            openSession: { _ in },
            openSessionPicker: {},
            newProject: {},
            openProject: {},
            openRecentProject: { _ in },
            importFolder: {},
            backupProject: {},
            moveProject: {},
            enterEditor: {},
            backToLibrary: {},
            searchLibrary: {},
            export: {},
            undo: {},
            redo: {},
            copyAdjustments: {},
            pasteAdjustments: {},
            pastePartial: {},
            copyAdjustmentsDialog: {},
            presetManager: {},
            mcpLauncher: {},
            settings: {},
            filmPanel: {},
            showSidebar: {},
            showInspector: {},
            toggleSoftProof: {},
            setGamutCheck: {},
            actualSize: {},
            fitToScreen: {},
            expandAllStacks: {},
            collapseAllStacks: {},
            toggleToolRail: {},
            toggleScopes: {},
            toggleAdjustmentStack: {},
            applyRating: { _ in },
            applyFlag: { _ in },
            toggleFlag: { _ in },
            applyColor: { _ in },
            aiUpscale: {},
            aiDenoise: {}
        )
    }

    /// Per-test harness (a tearDown override is nonisolated and cannot
    /// touch main-actor faces — the work rides a `defer` in each test).
    private func armHarness() -> NSMenu? { NSApp.mainMenu }

    private func disarmHarness(_ saved: NSMenu?) {
        NSApp.mainMenu = saved
    }

    /// The fresh controller that installed the CURRENT tree — the explicit
    /// refresh pass (`refreshAll()`, internal) re-reads its registries.
    private var lastInstaller: NSMenuBridgeController?

    // MARK: - Tree helpers

    private func installFresh(gate: Bool, deps: NSMenuBridgeController.Deps? = nil)
        -> NSMenuBridgeController {
        let controller = NSMenuBridgeController()
        controller.install(deps: deps ?? makeDeps(gate: gate))
        return controller
    }

    private func flatten(_ menu: NSMenu) -> [NSMenuItem] {
        var result: [NSMenuItem] = []
        for item in menu.items {
            result.append(item)
            if let sub = item.submenu { result.append(contentsOf: flatten(sub)) }
        }
        return result
    }

    /// Titles are resolved through the same call the bridge uses, so every
    /// lookup is locale-independent (the test host's bundle carries the
    /// catalog).
    private func title(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    private func topMenu(_ root: NSMenu, _ expectedTitle: String) -> NSMenu? {
        root.items.first { $0.title == expectedTitle }?.submenu
    }

    private func item(_ items: [NSMenuItem], titled expectedTitle: String) -> NSMenuItem? {
        items.first { $0.title == expectedTitle }
    }

    private func probeInstance(
        opName: String = "probe"
    ) -> ModuleInstance {
        ModuleInstance(
            id: UUID(), opName: opName, multiPriority: 0,
            multiName: "", iopOrder: 50, version: 1, enabled: true,
            paramsData: Data("{}".utf8), paramsHash: 0)
    }

    // MARK: - 1: the gate=false tree mirror

    func testGateFalseTreeMirrorsNewShellCommandSet() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        _ = installFresh(gate: false)
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        // Top-level shape: [app, File, Edit, View, Metadata, Image, Window, Help].
        XCTAssertEqual(root.items.count, 8, "the top-level menu set drifted")
        // items[0] is the app-menu HOLDER (titled with the bundle name);
        // its submenu opens with the About item.
        XCTAssertTrue(
            root.items[0].submenu?.items.first?.title.hasPrefix("About ") ?? false,
            "the first menu must be the app menu (got \(root.items[0].title))")
        XCTAssertNotNil(topMenu(root, "File"))
        XCTAssertNotNil(topMenu(root, "Edit"))
        XCTAssertNotNil(topMenu(root, title("menu_view")))
        XCTAssertNotNil(topMenu(root, title("menu_metadata")))
        XCTAssertNotNil(topMenu(root, title("menu_image")))
        XCTAssertNotNil(topMenu(root, "Window"))
        XCTAssertNotNil(topMenu(root, "Help"))

        // Gate=false: the session dead routes are ABSENT.
        let fileItems = flatten(topMenu(root, "File") ?? NSMenu())
        XCTAssertNil(item(fileItems, titled: title("menu_new_session")))
        XCTAssertNil(item(fileItems, titled: title("menu_open_session")))
        XCTAssertNil(item(fileItems, titled: title("menu_close_session")))

        // The new-shell workspace circuit is PRESENT.
        XCTAssertNotNil(item(fileItems, titled: title("menu_enter_editor")))
        XCTAssertNotNil(item(fileItems, titled: title("menu_back_to_library")))
        XCTAssertNotNil(item(fileItems, titled: title("menu_library_search")))

        // The project face (unconditional in the Commands IA — mirrored).
        XCTAssertNotNil(item(fileItems, titled: "New Project…"))
        XCTAssertNotNil(item(fileItems, titled: "Open Project…"))
        XCTAssertNotNil(item(fileItems, titled: "Open Recent Project"))
        XCTAssertNotNil(item(fileItems, titled: "Import Folder…"))
        XCTAssertNotNil(item(fileItems, titled: "Backup Project…"))
        XCTAssertNotNil(item(fileItems, titled: "Move Project…"))

        // The pure function's gate=false arm the tree consumed (the phase
        // independence contract).
        let visible = MenuCommandSet.visibleCommandIDs(gate: false, phase: .library)
        XCTAssertTrue(visible.contains(.workspaceEnterEditor))
        XCTAssertFalse(visible.contains(.sessionNew))
    }

    // MARK: - 2: the gate=true tree mirror

    func testGateTrueTreeMirrorsSessionRoutes() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        _ = installFresh(gate: true)
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let fileItems = flatten(topMenu(root, "File") ?? NSMenu())

        // Gate=true: the M1 session routes stand (statically disabled ones
        // stay dead; ⇧⌘O is the live picker route).
        let newSession = item(fileItems, titled: title("menu_new_session"))
        let openSession = item(fileItems, titled: title("menu_open_session"))
        let closeSession = item(fileItems, titled: title("menu_close_session"))
        XCTAssertNotNil(newSession)
        XCTAssertNotNil(openSession)
        XCTAssertNotNil(closeSession)
        XCTAssertEqual(newSession?.isEnabled, false, "the dead route stays disabled")
        XCTAssertEqual(openSession?.isEnabled, true, "⇧⌘O picker route is live")
        XCTAssertEqual(closeSession?.isEnabled, false, "the dead route stays disabled")
        XCTAssertNotNil(item(fileItems, titled: title("menu_open_recent")))

        // The pure function's M1 arm the tree consumed.
        let visible = MenuCommandSet.visibleCommandIDs(gate: true, phase: .library)
        XCTAssertTrue(visible.contains(.sessionOpen))
        XCTAssertFalse(visible.contains(.workspaceEnterEditor))
    }

    // MARK: - 3: system-family anchors

    func testSystemFamilyAnchorsPresent() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        _ = installFresh(gate: false)
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let editItems = flatten(topMenu(root, "Edit") ?? NSMenu())
        XCTAssertNotNil(item(editItems, titled: "Cut"))
        XCTAssertNotNil(item(editItems, titled: "Copy"))
        XCTAssertNotNil(item(editItems, titled: "Paste"))
        XCTAssertNotNil(item(editItems, titled: "Select All"))

        let windowItems = flatten(topMenu(root, "Window") ?? NSMenu())
        XCTAssertNotNil(item(windowItems, titled: "Minimize"))
        XCTAssertNotNil(item(windowItems, titled: "Zoom"))
        XCTAssertNotNil(item(windowItems, titled: "Bring All to Front"))

        // The AppKit role outlets are wired (services/help/windows).
        XCTAssertNotNil(NSApp.servicesMenu)
        XCTAssertNotNil(NSApp.helpMenu)
        XCTAssertNotNil(NSApp.windowsMenu)

        // The App menu anchors: Settings… (the real window-controller
        // seam — never the private selector) and Quit.
        let appItems = flatten(root)
        XCTAssertNotNil(item(appItems, titled: "Settings…"))
        XCTAssertTrue(
            appItems.contains { $0.title.hasPrefix("Quit ") },
            "the Quit item went missing")
    }

    // MARK: - 4: the AX identifier migration set

    func testAXIdentifierMigrationSetPinned() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        _ = installFresh(gate: false)
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let all = flatten(root)
        let byAX = Dictionary(
            all.compactMap { entry -> (String, NSMenuItem)? in
                let ax = entry.accessibilityIdentifier()
guard !ax.isEmpty else {
                    return nil
                }
                return (ax, entry)
            },
            uniquingKeysWith: { first, _ in first })

        // The migrated set (D-F0P-01-3) — the production `menu.*` spellings.
        let expected = [
            "menu.workspace.enterEditor",
            "menu.workspace.backToLibrary",
            "menu.library.search",
            "menu.edit.copyAdjustments",
            "menu.view.stacks.expandAll",
            "menu.view.stacks.collapseAll",
            AIEntryPointCoordinator.Marker.menuUpscale,
            AIEntryPointCoordinator.Marker.menuDenoise,
        ]
        for identifier in expected {
            XCTAssertNotNil(
                byAX[identifier],
                "AX identifier \(identifier) missing from the installed tree")
        }
        // The AI pair carries the exact production marker constants.
        XCTAssertEqual(byAX[AIEntryPointCoordinator.Marker.menuUpscale]?.title,
                       title("menu_image_ai_upscale"))
        XCTAssertEqual(byAX[AIEntryPointCoordinator.Marker.menuDenoise]?.title,
                       title("menu_image_ai_denoise"))
    }

    // MARK: - 5: softproof Toggle state legs (laState × SoftProofState)

    func testSoftProofToggleStateLegsAndGamutGate() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        // The state object is constructed FIRST and handed into the Deps —
        // the registered laState closures read the SAME instance.
        let softProof = SoftProofState()
        lastInstaller = installFresh(
            gate: false, deps: makeDeps(gate: false, softProof: softProof))
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let viewItems = flatten(topMenu(root, title("menu_view")) ?? NSMenu())
        let softproofItem = item(viewItems, titled: title("softproof_toggle"))
        let gamutItem = item(viewItems, titled: title("softproof_gamut_check"))
        XCTAssertNotNil(softproofItem)
        XCTAssertNotNil(gamutItem)

        // OFF leg: no profile → both toggles read off; the gamut check is
        // gated on an active proof (disabled).
        XCTAssertEqual(softproofItem?.state, .off)
        XCTAssertEqual(gamutItem?.state, .off)
        XCTAssertEqual(gamutItem?.isEnabled, false)
        XCTAssertEqual(softproofItem?.isEnabled, true,
                       "the softproof toggle has no enabler (always clickable)")

        // The gamut STATE leg flips through the production setter (an
        // inactive proof remembers the flag without activating) — the
        // registered laState closure re-evaluates on the explicit refresh.
        softProof.setGamutCheck(true, coordinator: PipeCoordinator())
        lastInstaller?.refreshAll()
        XCTAssertEqual(gamutItem?.state, .on,
                       "the laState closure must read the live SoftProofState")
        XCTAssertEqual(gamutItem?.isEnabled, false,
                       "the gamut enabler gates on isActive, not the flag")

        softProof.setGamutCheck(false, coordinator: PipeCoordinator())
        lastInstaller?.refreshAll()
        XCTAssertEqual(gamutItem?.state, .off)
    }

    // MARK: - 6: undo/redo enabler predicate

    func testUndoRedoEnablerPredicateLegs() async throws {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        let editorState = EditorState()
        let agent = AgentControlCoordinator()
        lastInstaller = installFresh(gate: false, deps: makeDeps(
            gate: false, editorState: editorState, agent: agent))
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let editItems = flatten(topMenu(root, "Edit") ?? NSMenu())
        let undoItem = item(editItems, titled: title("menu_undo"))
        let redoItem = item(editItems, titled: title("menu_redo"))
        XCTAssertNotNil(undoItem)
        XCTAssertNotNil(redoItem)

        // No history → both disabled.
        XCTAssertEqual(undoItem?.isEnabled, false)
        XCTAssertEqual(redoItem?.isEnabled, false)

        // canUndo leg: one committed item (the paste-install precedent)
        // flips undo ON; redo stays off (no redo tail).
        var pasted = HistoryStack()
        pasted.commit(probeInstance(), label: "history_test")
        editorState.installMergePaste(history: pasted)
        XCTAssertEqual(editorState.canUndo, true)
        lastInstaller?.refreshAll()
        XCTAssertEqual(undoItem?.isEnabled, true,
                       "the enabler must read the live state object truth")
        XCTAssertEqual(redoItem?.isEnabled, false)

        // holdsControl leg: an agent holding control disables undo
        // (disable-not-unmount's NSMenu-side face).
        _ = try await agent.acquire("parity-test")
        lastInstaller?.refreshAll()
        XCTAssertEqual(undoItem?.isEnabled, false,
                       "holdsControl must gate undo")
        agent.release()
        lastInstaller?.refreshAll()
        XCTAssertEqual(undoItem?.isEnabled, true)
    }

    // MARK: - 7: the paste family's BINARY enabler (no holdsControl)

    func testPasteFamilyBinaryEnablerWithoutHoldsControl() async throws {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        let pasteboard = AdjustmentsPasteboard()
        let agent = AgentControlCoordinator()
        lastInstaller = installFresh(gate: false, deps: makeDeps(
            gate: false, agent: agent, pasteboard: pasteboard))
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let editItems = flatten(topMenu(root, "Edit") ?? NSMenu())
        let paste = item(editItems, titled: title("menu_paste_adjustments"))
        let pastePartial = item(editItems, titled: title("menu_paste_partial"))
        XCTAssertNotNil(paste)
        XCTAssertNotNil(pastePartial)

        // No payload → disabled.
        XCTAssertEqual(paste?.isEnabled, false)
        XCTAssertEqual(pastePartial?.isEnabled, false)

        // Payload → enabled (the clipboard is a frozen payload, not an
        // editor fact — no loaded image required).
        pasteboard.copy(
            PastePayload(
                sourceImageID: UUID(), sourceURL: nil,
                instances: [probeInstance()], layerStack: nil))
        lastInstaller?.refreshAll()
        XCTAssertEqual(paste?.isEnabled, true)
        XCTAssertEqual(pastePartial?.isEnabled, true)

        // THE BINARY PIN (CONTEXT 勘误③/⑦): with the payload present, an
        // agent holding control does NOT disable the paste family — the
        // production enabler is hasPayload × isReadOnly only (the Swift-UI
        // face's exact form, LightamerApp.swift :2003/:2008 family).
        _ = try await agent.acquire("parity-test")
        lastInstaller?.refreshAll()
        XCTAssertEqual(
            paste?.isEnabled, true,
            "paste must stay binary (hasPayload × isReadOnly — no holdsControl)")
        XCTAssertEqual(pastePartial?.isEnabled, true)
        agent.release()

        // Payload cleared → disabled again.
        pasteboard.clear()
        lastInstaller?.refreshAll()
        XCTAssertEqual(paste?.isEnabled, false)
    }

    // MARK: - 8: project commands + export + AI enablers

    func testProjectExportAndAIEnablers() async throws {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        let agent = AgentControlCoordinator()
        lastInstaller = installFresh(gate: false, deps: makeDeps(gate: false, agent: agent))
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let all = flatten(root)
        let newProject = item(all, titled: "New Project…")
        let openProject = item(all, titled: "Open Project…")
        let exportItem = item(all, titled: title("menu_export"))
        let importItem = item(all, titled: "Import Folder…")
        let backupItem = item(all, titled: "Backup Project…")
        let moveItem = item(all, titled: "Move Project…")
        let upscale = item(all, titled: title("menu_image_ai_upscale"))
        let denoise = item(all, titled: title("menu_image_ai_denoise"))
        XCTAssertNotNil(newProject)
        XCTAssertNotNil(openProject)
        XCTAssertNotNil(exportItem)
        XCTAssertNotNil(upscale)
        XCTAssertNotNil(denoise)

        // Fresh install, nothing held, no project store, no workspace.
        XCTAssertEqual(newProject?.isEnabled, true)
        XCTAssertEqual(openProject?.isEnabled, true)
        XCTAssertEqual(importItem?.isEnabled, false)
        XCTAssertEqual(backupItem?.isEnabled, false)
        XCTAssertEqual(moveItem?.isEnabled, false)
        XCTAssertEqual(upscale?.isEnabled, false)
        XCTAssertEqual(denoise?.isEnabled, false)

        // THE CONSTANT-ENABLED PIN (D-F0P-01-5.2): export is enabled in
        // every state — the pre-flip AX ground truth (the focused value is
        // the ACTION payload, not an enablement signal).
        XCTAssertEqual(exportItem?.isEnabled, true)

        // holdsControl family: New/Open Project (and the recent rows).
        _ = try await agent.acquire("parity-test")
        lastInstaller?.refreshAll()
        XCTAssertEqual(newProject?.isEnabled, false,
                       "holdsControl must gate the project commands")
        XCTAssertEqual(openProject?.isEnabled, false)
        XCTAssertEqual(exportItem?.isEnabled, true,
                       "export stays constant-enabled even under agent control")
        agent.release()
        lastInstaller?.refreshAll()
        XCTAssertEqual(newProject?.isEnabled, true)

        // The AI family's phase × currentImageID legs (the noted workspace
        // is this fresh controller's own box). Editor without an image
        // first (openEditor(nil) never CLEARS a set id — the image-less
        // editor state only exists before the first image lands).
        let workspace = WorkspaceModel()
        lastInstaller?.noteWorkspace(workspace)
        workspace.openEditor(imageID: nil)
        lastInstaller?.refreshAll()
        XCTAssertEqual(upscale?.isEnabled, false,
                       "editor phase without an image must disable the AI family")

        workspace.openEditor(imageID: 42)
        lastInstaller?.refreshAll()
        XCTAssertEqual(upscale?.isEnabled, true)
        XCTAssertEqual(denoise?.isEnabled, true)

        workspace.closeEditor()
        lastInstaller?.refreshAll()
        XCTAssertEqual(upscale?.isEnabled, false,
                       "library phase must disable the AI family")
    }

    // MARK: - 9: the metadata family (16 items) + text-entry disarm

    func testMetadataFamilySixteenItemsAndFocusDisarm() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        lastInstaller = installFresh(gate: false)
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let metadataItems = flatten(topMenu(root, title("menu_metadata")) ?? NSMenu())
            .filter { !$0.isSeparatorItem }
        // review m2's real count: rating clear+1-5 = 6, flag ×3,
        // color clear+0-5 = 7 → 16 items (separators excluded).
        XCTAssertEqual(metadataItems.count, 16,
                       "the metadata family count drifted")
        for entry in metadataItems {
            XCTAssertEqual(entry.isEnabled, true,
                           "unfocused metadata item must be enabled: \(entry.title)")
        }

        // The disarm face: a focused metadata text field disables the WHOLE
        // family (bare-key shortcuts must reach the text field, not the
        // menu — the metadataFieldFocusedState note box).
        lastInstaller?.noteMetadataFieldFocused(true)
        lastInstaller?.refreshAll()
        for entry in metadataItems {
            XCTAssertEqual(entry.isEnabled, false,
                           "focused disarm missed: \(entry.title)")
        }
        lastInstaller?.noteMetadataFieldFocused(false)
        lastInstaller?.refreshAll()
        for entry in metadataItems {
            XCTAssertEqual(entry.isEnabled, true)
        }
    }

    // MARK: - 10: DefaultKeymap-mapped shortcut pins

    func testShortcutsPinDefaultKeymapMappedCommands() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        _ = installFresh(gate: false)
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let all = flatten(root)

        let pins: [(String, MenuCommandID)] = [
            ("New Project…", .projectNew),
            ("Open Project…", .projectOpen),
            ("Import Folder…", .projectImportFolder),
            (title("menu_enter_editor"), .workspaceEnterEditor),
            (title("menu_back_to_library"), .workspaceBackToLibrary),
            (title("menu_library_search"), .librarySearch),
        ]
        for (expectedTitle, id) in pins {
            guard let found = item(all, titled: expectedTitle) else {
                return XCTFail("item \(expectedTitle) missing")
            }
            guard let combo = DefaultKeymap.combo(for: id) else {
                return XCTFail("DefaultKeymap lost the combo for \(id)")
            }
            XCTAssertEqual(found.keyEquivalent.lowercased(), combo.key.lowercased(),
                           "\(id): key drift")
            XCTAssertEqual(
                found.keyEquivalentModifierMask.contains(.command), combo.command,
                "\(id): ⌘ drift")
            XCTAssertEqual(
                found.keyEquivalentModifierMask.contains(.shift), combo.shift,
                "\(id): ⇧ drift")
            XCTAssertEqual(
                found.keyEquivalentModifierMask.contains(.option), combo.option,
                "\(id): ⌥ drift")
            XCTAssertEqual(
                found.keyEquivalentModifierMask.contains(.control), combo.control,
                "\(id): ⌃ drift")
        }
    }

    // MARK: - 11: the custom declaration shortcut family

    func testShortcutsPinCustomDeclarationFamily() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        _ = installFresh(gate: false)
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let all = flatten(root)

        func assertKey(
            _ expectedTitle: String, _ key: String,
            _ mask: NSEvent.ModifierFlags, file: StaticString = #filePath,
            line: UInt = #line
        ) {
            guard let found = item(all, titled: expectedTitle) else {
                XCTFail("item \(expectedTitle) missing", file: file, line: line)
                return
            }
            XCTAssertEqual(found.keyEquivalent.lowercased(), key.lowercased(),
                           "\(expectedTitle): key drift", file: file, line: line)
            XCTAssertTrue(
                found.keyEquivalentModifierMask == mask,
                "\(expectedTitle): modifier drift (\(found.keyEquivalentModifierMask.rawValue) ≠ \(mask.rawValue))",
                file: file, line: line)
        }

        assertKey(title("menu_back_to_library"), "w", [.command])
        assertKey(title("menu_enter_editor"), "e", [.command])
        assertKey(title("menu_export"), "E", [.command, .shift])
        assertKey(title("menu_show_sidebar"), "s", [.command, .option])
        assertKey(title("menu_show_inspector"), "i", [.command, .option])
        assertKey(title("menu_actual_size"), "z", [])
        assertKey(title("menu_fit_to_screen"), "f", [])
        assertKey(title("menu_undo"), "z", [.command])
        assertKey(title("menu_redo"), "Z", [.command, .shift])
        assertKey(title("menu_copy_adjustments"), "C", [.command, .shift])
        assertKey(title("menu_paste_adjustments"), "V", [.command, .shift])
        assertKey("Settings…", ",", [.command])
        assertKey(title("softproof_toggle"), "p", [.command, .option])
        // The metadata spot: the bare 0-5/p/x rating-flag family + the
        // ⌘0-6 color family.
        assertKey(title("metadata_rating_clear"), "0", [])
        assertKey(title("metadata_rating_5"), "5", [])
        assertKey(title("metadata_flag_pick"), "p", [])
        assertKey(title("metadata_flag_reject"), "x", [])
        // The color family's keys are the SLOT numbers (clear=⌘0,
        // color_0=⌘1 … color_5=⌘6) — the localized titles carry the same
        // "(⌘N)" hint.
        assertKey(title("metadata_color_clear"), "0", [.command])
        assertKey(title("metadata_color_0"), "1", [.command])
        assertKey(title("metadata_color_5"), "6", [.command])
    }

    // MARK: - 12: titles resolve beyond the key literal

    func testTitlesResolveBeyondBareKeys() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        _ = installFresh(gate: false)
        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        // The F-2 trap face: a title equal to its snake_case catalog key
        // renders the raw key in the menu bar. No installed title may look
        // like a key literal.
        let keyPattern = "^[a-z][a-z0-9_]+_[a-z0-9_]+$"
        for entry in flatten(root) where !entry.isSeparatorItem {
            if entry.title.range(of: keyPattern, options: .regularExpression) != nil {
                XCTFail("bare-key title leaked into the tree: \(entry.title)")
            }
        }

        // The strings-table spot check: the family's keys resolve to real
        // copy (the resolved value differs from the key).
        for key in ["menu_export", "menu_undo", "menu_enter_editor",
                    "menu_metadata", "metadata_rating_clear"] {
            XCTAssertNotEqual(
                String(localized: String.LocalizationValue(key)), key,
                "key \(key) did not resolve — the catalog row is missing")
        }
    }
}
