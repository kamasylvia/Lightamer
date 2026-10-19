import AppKit
import OSLog
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// NSMenuBridge (F0P-01 T3 — the F0-prime shell handover's menu half).
//
// The SwiftUI `Commands` main-menu family is replaced by ONE statically built
// `NSApp.mainMenu` tree, consumed from the same `MenuCommandSet` pure
// function (MenuCommandID → NSMenuItem 1:1). The menu updates ride explicit
// `menuNeedsUpdate` / observation-driven enablement refreshes instead of the
// declarative re-eval graph.
//
// INERT until the shell handover flips the entry (F0P-01 T6): the view-side
// note modifiers reference this type (a compile dependency), but nothing
// installs the tree while the SwiftUI App/Scene lifecycle owns the menu bar.
//
// Production deltas vs the F0' spike form (the plan's three reform points):
//   ① the export-presence note API is two-state — the spike's onAppear
//     once-true call shape never ships (the sheet-dismissed state must
//     reach the bridge too; ContentView notes through onChange);
//   ② Deps carries `inspectorState` (review m6) and the export enabler
//     reads `inspectorState.exportPageActive` directly (B18: the M2 export
//     PAGE leg's truth) — the observation read-set tracks BOTH the note box
//     (the legacy sheet leg) and the page switch (19 reads, DECISIONS);
//   ③ menu_open_session (⇧⌘O) routes through the `openSessionPicker` seam
//     (the FileOpener.openSessionFolder picker form — review M4; the
//     spike's first-recent-session direct-open shape is retired).
//
// SCOPE: the main-menu family only; context menus / in-panel `Menu { }`
// stay SwiftUI. Selector dispatch routes into the app root's existing
// command seams (the closures captured at install — the command bodies are
// NOT rewritten; they call the same methods the SwiftUI Buttons call).
// ─────────────────────────────────────────────────────────────────────────────

// Chained registration: `enabled(item(...) { ... }) { predicate }`.
@MainActor
private func laEnabled(
    _ item: NSMenuItem, _ controller: NSMenuBridgeController,
    _ enabler: @escaping () -> Bool
) -> NSMenuItem {
    controller.register(enabled: enabler, for: item)
    return item
}

@MainActor
private func laState(
    _ item: NSMenuItem, _ controller: NSMenuBridgeController,
    _ state: @escaping () -> NSControl.StateValue
) -> NSMenuItem {
    controller.register(state: state, for: item)
    return item
}

/// The AppKit side of the bridge: builds the menu tree once, refreshes
/// enablement/toggle states through explicit observation (the AppKit-side
/// observation adapter) and dispatches actions into the existing seams.
@MainActor
final class NSMenuBridgeController: NSObject, NSMenuDelegate, NSMenuItemValidation {

    static let shared = NSMenuBridgeController()

    private let appName: String = {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Lightamer"
    }()
    private let stompLog = Logger(subsystem: "com.kamasylvia.lightamer", category: "probe")

    // MARK: - Dependencies (installed once, from the shell face assembly)

    struct Deps {
        // State objects — enablement READS (class refs, live properties).
        let editorState: EditorState
        let sessionState: SessionState
        let libraryProjects: LibraryProjectController
        let agentControl: AgentControlCoordinator
        let pasteboard: AdjustmentsPasteboard
        let softProofState: SoftProofState
        // F0P-01 T3 (review m6): the export PAGE leg's truth — the enabler
        // reads `exportPageActive` directly (B18; the note box below carries
        // the legacy sheet leg).
        let inspectorState: InspectorState
        let legacyLibraryEnabled: Bool

        // Action closures — the app root's EXISTING command seams (thin
        // wrappers around the same methods the SwiftUI Buttons call). Every
        // closure Task-hops its async bodies (the L057 discipline).
        let openImage: () -> Void
        let openSession: (URL) -> Void
        // F0P-01 T3 (review M4): the ⇧⌘O production body — the
        // FileOpener.openSessionFolder picker seam (the same shape the
        // SwiftUI command runs). The recent-sessions submenu rows keep the
        // direct `openSession(url)` route. Never the spike's
        // first-recent-session direct-open shortcut.
        let openSessionPicker: () -> Void
        let newProject: () -> Void
        let openProject: () -> Void
        let openRecentProject: (URL) -> Void
        let importFolder: () -> Void
        let backupProject: () -> Void
        let moveProject: () -> Void
        let enterEditor: () -> Void
        let backToLibrary: () -> Void
        let searchLibrary: () -> Void
        let export: () -> Void
        let undo: () -> Void
        let redo: () -> Void
        let copyAdjustments: () -> Void
        let pasteAdjustments: () -> Void
        let pastePartial: () -> Void
        let copyAdjustmentsDialog: () -> Void
        let presetManager: () -> Void
        let mcpLauncher: () -> Void
        // F0P-01 T3: the Settings… (⌘,) production seam — the real window
        // controller's showWindow (D-F0P-1; the spike's private
        // `showSettingsWindow:` selector never ships).
        let settings: () -> Void
        let filmPanel: () -> Void
        let showSidebar: () -> Void
        let showInspector: () -> Void
        let toggleSoftProof: () -> Void
        let setGamutCheck: () -> Void
        let actualSize: () -> Void
        let fitToScreen: () -> Void
        let expandAllStacks: () -> Void
        let collapseAllStacks: () -> Void
        let toggleToolRail: () -> Void
        let toggleScopes: () -> Void
        let toggleAdjustmentStack: () -> Void
        let applyRating: (Int?) -> Void
        let applyFlag: (Int?) -> Void
        let toggleFlag: (Int) -> Void
        let applyColor: (Int?) -> Void
        let aiUpscale: () -> Void
        let aiDenoise: () -> Void
    }

    // The window-scoped focused-value box (the @FocusedValue family has no
    // AppKit read face — the publish sites note their values here; the app
    // is single-window so the focused workspace IS the noted workspace).
    // READS ONLY — every WRITE still routes through the shell closures.
    private(set) var workspace: WorkspaceModel?
    var exportPanelRequestPresent: Bool = false
    var metadataFieldFocusedState: Bool = false

    func noteWorkspace(_ model: WorkspaceModel) { workspace = model }
    func noteExportPanelRequestPresent(_ present: Bool) {
        exportPanelRequestPresent = present
    }
    func noteMetadataFieldFocused(_ focused: Bool) {
        metadataFieldFocusedState = focused
    }

    // Registration faces for the chained helpers above.
    func register(enabled enabler: @escaping () -> Bool, for item: NSMenuItem) {
        itemEnablers[ObjectIdentifier(item)] = enabler
        item.isEnabled = enabler()
    }
    func register(state: @escaping () -> NSControl.StateValue, for item: NSMenuItem) {
        itemStates[ObjectIdentifier(item)] = state
        item.state = state()
    }

    private var deps: Deps?
    private var rootMenu: NSMenu?
    private var installed = false
    /// Passive counter: how often something else re-asserted its own
    /// mainMenu over ours after install (diagnostic — no fight is mounted;
    /// the sample evidence reads the truth).
    private(set) var mainMenuStomps = 0

    // Per-item action/enablement/state registries (ObjectIdentifier keyed —
    // the menu tree is static; the recent-submenu items rebuild in
    // menuNeedsUpdate and re-register).
    private var itemActions: [ObjectIdentifier: () -> Void] = [:]
    private var itemEnablers: [ObjectIdentifier: () -> Bool] = [:]
    private var itemStates: [ObjectIdentifier: () -> NSControl.StateValue] = [:]
    private var recentProjectsItem: NSMenuItem?
    private var recentSessionsItem: NSMenuItem?

    // MARK: - Install

    func install(deps: Deps) {
        guard !installed else { return }
        installed = true
        self.deps = deps

        let root = NSMenu()
        root.autoenablesItems = false
        root.delegate = self

        buildAppMenu(into: root)
        buildFileMenu(into: root)
        buildEditMenu(into: root)
        buildViewMenu(into: root)
        buildMetadataMenu(into: root)
        buildImageMenu(into: root)
        buildWindowMenu(into: root)
        buildHelpMenu(into: root)

        rootMenu = root
        NSApp.mainMenu = root
        refreshAll()
        armObservation()
    }

    // MARK: - Menu tree (the Commands IA mirrored 1:1)

    private func menu(_ title: String, attachedTo parent: NSMenu) -> NSMenu {
        let m = NSMenu(title: title)
        m.autoenablesItems = false
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = m
        parent.addItem(holder)
        return m
    }

    private func item(_ parent: NSMenu, title: String,
                      key: String? = nil, mask: NSEvent.ModifierFlags = [.command],
                      action: (() -> Void)? = nil) -> NSMenuItem {
        let it = NSMenuItem(
            title: title,
            action: action != nil ? #selector(handleMenu(_:)) : nil,
            keyEquivalent: "")
        if let key { it.keyEquivalent = key; it.keyEquivalentModifierMask = mask }
        parent.addItem(it)
        if let action {
            itemActions[ObjectIdentifier(it)] = action
            it.target = self
        }
        return it
    }

    private func separator(_ parent: NSMenu) {
        parent.addItem(NSMenuItem.separator())
    }

    /// Whole-literal keys only (the keys already live in the catalog — the
    /// F-2 interpolated-prefix trap family stays avoided; the extractor
    /// cannot see these call sites but NO new keys are introduced).
    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    /// The gate=false command family (MenuCommandSet — consumed verbatim).
    private var visibleCommands: Set<MenuCommandID> {
        MenuCommandSet.visibleCommandIDs(
            gate: deps?.legacyLibraryEnabled ?? false, phase: .library)
    }

    // ── App menu ────────────────────────────────────────────────────────
    private func buildAppMenu(into root: NSMenu) {
        let m = menu(appName, attachedTo: root)
        item(m, title: "About \(appName)") {
            NSApp.orderFrontStandardAboutPanel()
        }
        separator(m)
        // D-F0P-1: the REAL settings window controller (the spike's private
        // `showSettingsWindow:` selector never ships — no API promise).
        item(m, title: "Settings…", key: ",") { [weak self] in
            self?.deps?.settings()
        }
        separator(m)
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesMenu.autoenablesItems = true
        services.submenu = servicesMenu
        m.addItem(services)
        NSApp.servicesMenu = servicesMenu
        separator(m)
        let hide = item(m, title: "Hide \(appName)", key: "h")
        hide.action = #selector(NSApplication.hide(_:))
        hide.target = nil
        let hideOthers = item(m, title: "Hide Others",
                              key: "h", mask: [.command, .option])
        hideOthers.action = #selector(NSApplication.hideOtherApplications(_:))
        hideOthers.target = nil
        let showAll = item(m, title: "Show All")
        showAll.action = #selector(NSApplication.unhideAllApplications(_:))
        showAll.target = nil
        separator(m)
        let quit = item(m, title: "Quit \(appName)", key: "q")
        quit.action = #selector(NSApplication.terminate(_:))
        quit.target = nil
    }

    // ── File ────────────────────────────────────────────────────────────
    private func buildFileMenu(into root: NSMenu) {
        let m = menu("File", attachedTo: root)
        let visible = visibleCommands

        if visible.contains(.sessionNew) {
            _ = laEnabled(item(m, title: localized("menu_new_session"),
                               key: "N", mask: [.command, .shift]), self) { false }
        }
        item(m, title: localized("menu_open"), key: "o") { [weak self] in
            self?.deps?.openImage()
        }
        if visible.contains(.sessionOpen) {
            // F0P-01 T3 (review M4): the ⇧⌘O production body — the picker
            // seam (never the spike's first-recent-session direct-open).
            item(m, title: localized("menu_open_session"),
                 key: "O", mask: [.command, .shift]) { [weak self] in
                self?.deps?.openSessionPicker()
            }
            recentSessionsItem = item(m, title: localized("menu_open_recent"))
            recentSessionsItem?.isEnabled = false
            if visible.contains(.sessionClose) {
                separator(m)
                _ = laEnabled(item(m, title: localized("menu_close_session"),
                                   key: "W", mask: [.command, .shift]), self) { false }
            }
        }
        separator(m)
        _ = laEnabled(item(m, title: "New Project…", key: "n") { [weak self] in
            self?.deps?.newProject()
        }, self) { [weak self] in
            self?.deps.map { !$0.agentControl.holdsControl } ?? false
        }
        _ = laEnabled(item(m, title: "Open Project…", key: "o",
                           mask: [.command, .option]) { [weak self] in
            self?.deps?.openProject()
        }, self) { [weak self] in
            self?.deps.map { !$0.agentControl.holdsControl } ?? false
        }
        recentProjectsItem = item(m, title: "Open Recent Project")
        recentProjectsItem?.isEnabled = false
        separator(m)
        _ = laEnabled(item(m, title: "Import Folder…", key: "I",
                           mask: [.command, .shift]) { [weak self] in
            self?.deps?.importFolder()
        }, self) { [weak self] in self?.deps?.libraryProjects.projectStore != nil }
        separator(m)
        _ = laEnabled(item(m, title: "Backup Project…") { [weak self] in
            self?.deps?.backupProject()
        }, self) { [weak self] in self?.deps?.libraryProjects.projectStore != nil }
        _ = laEnabled(item(m, title: "Move Project…") { [weak self] in
            self?.deps?.moveProject()
        }, self) { [weak self] in self?.deps?.libraryProjects.projectStore != nil }
        if visible.contains(.workspaceEnterEditor) {
            separator(m)
            let enter = item(m, title: localized("menu_enter_editor"),
                             key: "e") { [weak self] in
                self?.deps?.enterEditor()
            }
            enter.setAccessibilityIdentifier("menu.workspace.enterEditor")
            _ = laEnabled(enter, self) { [weak self] in
                self?.workspace?.phase == .library
            }
            let back = item(m, title: localized("menu_back_to_library"),
                            key: "w") { [weak self] in
                self?.deps?.backToLibrary()
            }
            back.setAccessibilityIdentifier("menu.workspace.backToLibrary")
            _ = laEnabled(back, self) { [weak self] in
                self?.workspace?.phase == .editor
            }
            separator(m)
            let search = item(m, title: localized("menu_library_search"),
                              key: "f") { [weak self] in
                self?.deps?.searchLibrary()
            }
            search.setAccessibilityIdentifier("menu.library.search")
            _ = laEnabled(search, self) { [weak self] in self?.workspace != nil }
        }
        separator(m)
        _ = laEnabled(item(m, title: localized("menu_save_sidecar"), key: "s"),
                      self) { false }
        // F0P-01 T3 (B18): the export enabler reads BOTH legs — the note box
        // (the legacy sheet leg, two-state) OR the M2 export PAGE switch
        // (the direct read; the page leg publishes the same focused key
        // pre-flip). The union is the exact pre-flip enablement across both
        // faces (each face publishes exactly one site).
        _ = laEnabled(item(m, title: localized("menu_export"), key: "E",
                           mask: [.command, .shift]) { [weak self] in
            self?.deps?.export()
        }, self) { [weak self] in
            guard let self else { return false }
            return self.exportPanelRequestPresent
                || (self.deps?.inspectorState.exportPageActive ?? false)
        }
    }

    // ── Edit ────────────────────────────────────────────────────────────
    private func buildEditMenu(into root: NSMenu) {
        let m = menu("Edit", attachedTo: root)
        _ = laEnabled(item(m, title: localized("menu_undo"), key: "z") { [weak self] in
            self?.deps?.undo()
        }, self) { [weak self] in
            guard let d = self?.deps else { return false }
            return d.editorState.canUndo && !d.libraryProjects.isReadOnly
                && !d.agentControl.holdsControl
        }
        _ = laEnabled(item(m, title: localized("menu_redo"), key: "Z",
                           mask: [.command, .shift]) { [weak self] in
            self?.deps?.redo()
        }, self) { [weak self] in
            guard let d = self?.deps else { return false }
            return d.editorState.canRedo && !d.libraryProjects.isReadOnly
                && !d.agentControl.holdsControl
        }
        separator(m)
        _ = laEnabled(item(m, title: localized("menu_copy_adjustments"), key: "C",
                           mask: [.command, .shift]) { [weak self] in
            self?.deps?.copyAdjustments()
        }, self) { [weak self] in self?.deps?.editorState.loadedImageURL != nil }
        _ = laEnabled(item(m, title: localized("menu_paste_adjustments"), key: "V",
                           mask: [.command, .shift]) { [weak self] in
            self?.deps?.pasteAdjustments()
        }, self) { [weak self] in
            guard let d = self?.deps else { return false }
            return d.pasteboard.hasPayload && !d.libraryProjects.isReadOnly
        }
        _ = laEnabled(item(m, title: localized("menu_paste_partial")) { [weak self] in
            self?.deps?.pastePartial()
        }, self) { [weak self] in
            guard let d = self?.deps else { return false }
            return d.pasteboard.hasPayload && !d.libraryProjects.isReadOnly
        }
        separator(m)
        let copyDialog = item(m, title: localized("menu_copy_adjustments_dialog")) {
            [weak self] in self?.deps?.copyAdjustmentsDialog()
        }
        copyDialog.setAccessibilityIdentifier("menu.edit.copyAdjustments")
        _ = laEnabled(copyDialog, self) { [weak self] in
            self?.deps?.editorState.loadedImageURL != nil
        }
        separator(m)
        item(m, title: localized("menu_preset_manager")) { [weak self] in
            self?.deps?.presetManager()
        }
        item(m, title: localized("menu_mcp_launcher")) { [weak self] in
            self?.deps?.mcpLauncher()
        }
        separator(m)
        // The standard text-editing family (the SwiftUI default Edit face).
        let cut = item(m, title: "Cut", key: "x")
        cut.action = #selector(NSText.cut(_:)); cut.target = nil
        let copy = item(m, title: "Copy", key: "c")
        copy.action = #selector(NSText.copy(_:)); copy.target = nil
        let paste = item(m, title: "Paste", key: "v")
        paste.action = #selector(NSText.paste(_:)); paste.target = nil
        let selectAll = item(m, title: "Select All", key: "a")
        selectAll.action = #selector(NSText.selectAll(_:)); selectAll.target = nil
    }

    // ── View ────────────────────────────────────────────────────────────
    private func buildViewMenu(into root: NSMenu) {
        let m = menu(localized("menu_view"), attachedTo: root)
        item(m, title: localized("menu_show_sidebar"), key: "s",
             mask: [.command, .option]) { [weak self] in self?.deps?.showSidebar() }
        item(m, title: localized("menu_show_inspector"), key: "i",
             mask: [.command, .option]) { [weak self] in self?.deps?.showInspector() }
        item(m, title: localized("menu_show_film_panel")) { [weak self] in
            self?.deps?.filmPanel()
        }
        separator(m)
        _ = laState(item(m, title: localized("softproof_toggle"), key: "p",
                         mask: [.command, .option]) { [weak self] in
            self?.deps?.toggleSoftProof()
        }, self) { [weak self] in
            self?.deps?.softProofState.isActive == true ? .on : .off
        }
        _ = laEnabled(laState(item(m, title: localized("softproof_gamut_check")) {
            [weak self] in self?.deps?.setGamutCheck()
        }, self) { [weak self] in
            self?.deps?.softProofState.gamutCheck == true ? .on : .off
        }, self) { [weak self] in self?.deps?.softProofState.isActive == true }
        separator(m)
        item(m, title: localized("menu_actual_size"), key: "z", mask: []) {
            [weak self] in self?.deps?.actualSize()
        }
        item(m, title: localized("menu_fit_to_screen"), key: "f", mask: []) {
            [weak self] in self?.deps?.fitToScreen()
        }
        separator(m)
        let expandAll = item(m, title: localized("menu_view_stacks_expand_all")) {
            [weak self] in self?.deps?.expandAllStacks()
        }
        expandAll.setAccessibilityIdentifier("menu.view.stacks.expandAll")
        let collapseAll = item(m, title: localized("menu_view_stacks_collapse_all")) {
            [weak self] in self?.deps?.collapseAllStacks()
        }
        collapseAll.setAccessibilityIdentifier("menu.view.stacks.collapseAll")
        if visibleCommands.contains(.viewToolRail) {
            separator(m)
            _ = laState(item(m, title: localized("menu_view_tool_rail")) {
                [weak self] in self?.deps?.toggleToolRail()
            }, self) { [weak self] in
                (self?.workspace?.toolRailVisible ?? false) ? .on : .off
            }
            _ = laState(item(m, title: localized("menu_view_scopes")) {
                [weak self] in self?.deps?.toggleScopes()
            }, self) { [weak self] in
                (self?.workspace?.scopesVisible ?? false) ? .on : .off
            }
            _ = laState(item(m, title: localized("menu_view_adjustment_stack")) {
                [weak self] in self?.deps?.toggleAdjustmentStack()
            }, self) { [weak self] in
                (self?.workspace?.adjustmentStackVisible ?? false) ? .on : .off
            }
        }
    }

    // ── Metadata ────────────────────────────────────────────────────────
    private func buildMetadataMenu(into root: NSMenu) {
        let m = menu(localized("menu_metadata"), attachedTo: root)
        func bare(_ title: String, key: String? = nil,
                  mask: NSEvent.ModifierFlags = [],
                  _ action: @escaping () -> Void) {
            let it = item(m, title: title, key: key, mask: mask, action: action)
            register(enabled: { [weak self] in
                self?.metadataFieldFocusedState == false
            }, for: it)
        }
        bare(localized("metadata_rating_clear"), key: "0") { [weak self] in
            self?.deps?.applyRating(nil) }
        bare(localized("metadata_rating_1"), key: "1") { [weak self] in
            self?.deps?.applyRating(1) }
        bare(localized("metadata_rating_2"), key: "2") { [weak self] in
            self?.deps?.applyRating(2) }
        bare(localized("metadata_rating_3"), key: "3") { [weak self] in
            self?.deps?.applyRating(3) }
        bare(localized("metadata_rating_4"), key: "4") { [weak self] in
            self?.deps?.applyRating(4) }
        bare(localized("metadata_rating_5"), key: "5") { [weak self] in
            self?.deps?.applyRating(5) }
        separator(m)
        bare(localized("metadata_flag_pick"), key: "p") { [weak self] in
            self?.deps?.toggleFlag(1) }
        bare(localized("metadata_flag_reject"), key: "x") { [weak self] in
            self?.deps?.toggleFlag(2) }
        bare(localized("metadata_flag_clear")) { [weak self] in
            self?.deps?.applyFlag(nil) }
        separator(m)
        bare(localized("metadata_color_clear"), key: "0",
             mask: [.command]) { [weak self] in self?.deps?.applyColor(nil) }
        bare(localized("metadata_color_0"), key: "1",
             mask: [.command]) { [weak self] in self?.deps?.applyColor(0) }
        bare(localized("metadata_color_1"), key: "2",
             mask: [.command]) { [weak self] in self?.deps?.applyColor(1) }
        bare(localized("metadata_color_2"), key: "3",
             mask: [.command]) { [weak self] in self?.deps?.applyColor(2) }
        bare(localized("metadata_color_3"), key: "4",
             mask: [.command]) { [weak self] in self?.deps?.applyColor(3) }
        bare(localized("metadata_color_4"), key: "5",
             mask: [.command]) { [weak self] in self?.deps?.applyColor(4) }
        bare(localized("metadata_color_5"), key: "6",
             mask: [.command]) { [weak self] in self?.deps?.applyColor(5) }
    }

    // ── Image ───────────────────────────────────────────────────────────
    private func buildImageMenu(into root: NSMenu) {
        let m = menu(localized("menu_image"), attachedTo: root)
        let aiEnabled = { [weak self] in
            self?.workspace?.phase == .editor
                && self?.workspace?.editorPhase.currentImageID != nil
        }
        let upscale = item(m, title: localized("menu_image_ai_upscale")) {
            [weak self] in self?.deps?.aiUpscale()
        }
        upscale.setAccessibilityIdentifier(AIEntryPointCoordinator.Marker.menuUpscale)
        _ = laEnabled(upscale, self, aiEnabled)
        let denoise = item(m, title: localized("menu_image_ai_denoise")) {
            [weak self] in self?.deps?.aiDenoise()
        }
        denoise.setAccessibilityIdentifier(AIEntryPointCoordinator.Marker.menuDenoise)
        _ = laEnabled(denoise, self, aiEnabled)
    }

    // ── Window ──────────────────────────────────────────────────────────
    private func buildWindowMenu(into root: NSMenu) {
        let m = menu("Window", attachedTo: root)
        let mini = item(m, title: "Minimize", key: "m")
        mini.action = #selector(NSWindow.miniaturize(_:)); mini.target = nil
        let zoom = item(m, title: "Zoom")
        zoom.action = #selector(NSWindow.zoom(_:)); zoom.target = nil
        separator(m)
        let front = item(m, title: "Bring All to Front")
        front.action = #selector(NSApplication.arrangeInFront(_:)); front.target = nil
        NSApp.windowsMenu = m
    }

    // ── Help ────────────────────────────────────────────────────────────
    private func buildHelpMenu(into root: NSMenu) {
        let m = menu("Help", attachedTo: root)
        _ = laEnabled(item(m, title: localized("menu_help"), key: "?"), self) { false }
        NSApp.helpMenu = m
    }

    // MARK: - Recent submenus (menuNeedsUpdate — the delegate-time rebuild)

    private func rebuildRecentSubmenus() {
        guard let deps else { return }
        if let holder = recentProjectsItem {
            let sub = NSMenu(title: holder.title)
            sub.autoenablesItems = false
            for url in deps.libraryProjects.recentProjects {
                let it = NSMenuItem(
                    title: url.lastPathComponent,
                    action: #selector(handleMenu(_:)), keyEquivalent: "")
                it.target = self
                sub.addItem(it)
                itemActions[ObjectIdentifier(it)] = { [weak self] in
                    self?.deps?.openRecentProject(url)
                }
                itemEnablers[ObjectIdentifier(it)] = { [weak self] in
                    self?.deps.map { !$0.agentControl.holdsControl } ?? false
                }
            }
            holder.submenu = sub
            holder.isEnabled = !deps.libraryProjects.recentProjects.isEmpty
                && !deps.agentControl.holdsControl
        }
        if let holder = recentSessionsItem {
            let sub = NSMenu(title: holder.title)
            sub.autoenablesItems = false
            for url in deps.sessionState.recentSessions {
                let it = NSMenuItem(
                    title: url.lastPathComponent,
                    action: #selector(handleMenu(_:)), keyEquivalent: "")
                it.target = self
                sub.addItem(it)
                itemActions[ObjectIdentifier(it)] = { [weak self] in
                    self?.deps?.openSession(url)
                }
            }
            holder.submenu = sub
            holder.isEnabled = !deps.sessionState.recentSessions.isEmpty
        }
    }

    // MARK: - Enablement / state refresh

    /// One explicit refresh pass — cheap O(items) pointer writes on the
    /// static tree (NOT the SwiftUI rebuild; this is the AppKit-side
    /// observation adapter).
    func refreshAll() {
        guard let root = rootMenu else { return }
        if NSApp.mainMenu !== root {
            mainMenuStomps += 1
            if mainMenuStomps <= 10 {
                stompLog.info("nsmenu-bridge: mainMenu re-stomped (\(self.mainMenuStomps))")
            }
        }
        processItems(in: root)
        rebuildRecentSubmenus()
    }

    private func processItems(in menu: NSMenu) {
        for item in menu.items {
            if let enabler = itemEnablers[ObjectIdentifier(item)] {
                item.isEnabled = enabler()
            }
            if let state = itemStates[ObjectIdentifier(item)] {
                item.state = state()
            }
            if let sub = item.submenu { processItems(in: sub) }
        }
    }

    /// The observation adapter: ONE tracked read-set (19 reads — review m1's
    /// 18 fields plus the B18 `exportPageActive` page-leg direct read, the
    /// DECISIONS dual-track form); every tracked state change schedules a
    /// refresh + re-arm (no polling timer, no AttributeGraph).
    private func armObservation() {
        guard let deps else { return }
        withObservationTracking {
            _ = deps.editorState.canUndo
            _ = deps.editorState.canRedo
            _ = deps.editorState.loadedImageURL
            _ = deps.pasteboard.hasPayload
            _ = deps.libraryProjects.isReadOnly
            _ = deps.libraryProjects.projectStore
            _ = deps.libraryProjects.recentProjects
            _ = deps.agentControl.holdsControl
            _ = deps.softProofState.isActive
            _ = deps.softProofState.gamutCheck
            _ = deps.sessionState.recentSessions
            _ = deps.inspectorState.exportPageActive
            if let ws = Self.shared.workspace {
                _ = ws.phase
                _ = ws.editorPhase.currentImageID
                _ = ws.toolRailVisible
                _ = ws.scopesVisible
                _ = ws.adjustmentStackVisible
            }
            _ = Self.shared.metadataFieldFocusedState
            _ = Self.shared.exportPanelRequestPresent
        } onChange: {
            DispatchQueue.main.async {
                Self.shared.refreshAll()
                Self.shared.armObservation()
            }
        }
    }

    // MARK: - NSMenuDelegate / NSMenuItemValidation / dispatch

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshAll()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let enabler = itemEnablers[ObjectIdentifier(menuItem)] {
            return enabler()
        }
        return menuItem.isEnabled
    }

    @objc private func handleMenu(_ sender: NSMenuItem) {
        // Stale-enablement backstop: a shortcut racing a state flip must not
        // fire a command whose enablement predicate now says no.
        if let enabler = itemEnablers[ObjectIdentifier(sender)], !enabler() {
            return
        }
        itemActions[ObjectIdentifier(sender)]?()
    }
}
