import AppKit
import LightamerCore
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// MenuBridgeObservationTests (F0P-02 T3) — the bridge's observation adapter:
// tracked-read mutations schedule enablement refreshes with NO manual
// refresh pass, consecutive mutations each re-arm (the re-arm reform), and
// the dispatch path carries the stale-enablement backstop.
//
// Seam reality (recorded in DECISIONS): in the direct-launch test host the
// app main runs BEFORE the tests — the production face already installed
// `NSMenuBridgeController.shared` with the production Deps, and the
// production Deps' state objects are shell-controller-internal (no test
// seam). The reachable tracked surfaces split in two:
//   • the metadata note box is a PLAIN (untracked) property BY DESIGN — its
//     production refresh driver is the menuNeedsUpdate delegate call, so its
//     leg drives that exact face;
//   • the workspace legs ARE @Observable-tracked — but only an arm cycle
//     that ran AFTER the note registers them, so the tests PRIME the arm
//     with a fresh-controller install (armObservation reads the SHARED
//     workspace box) and then observe the adapter's onChange dispatch
//     through `mainMenuStomps` (the shared's refreshAll re-asserts its own
//     tree while the fresh tree owns NSApp.mainMenu — one stomp per
//     delivered mutation). Consecutive deliveries = the re-arm reform's
//     indirect face (armObservation is private and uncounted).
// The backstop test needs an ACTION SPY, so it mounts its own fresh
// controller (install/deps is internal; the dispatch target is
// per-instance) and restores the global mainMenu around itself.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class MenuBridgeObservationTests: XCTestCase {

    /// Per-test harness (a tearDown override is nonisolated and cannot
    /// touch main-actor faces — the work rides a `defer` in each test).
    private func armHarness() -> NSMenu? {
        // Defensive: a bare test process (no GUI launch) must still have a
        // bridge tree — the stub install is the fallback.
        if NSApp.mainMenu == nil {
            NSMenuBridgeController.shared.install(deps: Self.makeDeps(sink: .init()))
        }
        return NSApp.mainMenu
    }

    private func disarmHarness(_ saved: NSMenu?) {
        NSApp.mainMenu = saved
        NSMenuBridgeController.shared.noteMetadataFieldFocused(false)
    }

    // MARK: - Helpers

    final class ActionSink: @unchecked Sendable {
        var undoCalls = 0
    }

    private static func makeDeps(
        sink: ActionSink,
        editorState: EditorState = EditorState()
    ) -> NSMenuBridgeController.Deps {
        .init(
            editorState: editorState,
            sessionState: SessionState(),
            libraryProjects: LibraryProjectController(),
            agentControl: AgentControlCoordinator(),
            pasteboard: AdjustmentsPasteboard(),
            softProofState: SoftProofState(),
            inspectorState: InspectorState(),
            legacyLibraryEnabled: false,
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
            undo: { sink.undoCalls += 1 },
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

    private func title(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    private func flatten(_ menu: NSMenu) -> [NSMenuItem] {
        var result: [NSMenuItem] = []
        for item in menu.items {
            result.append(item)
            if let sub = item.submenu { result.append(contentsOf: flatten(sub)) }
        }
        return result
    }

    private func metadataItems() -> [NSMenuItem] {
        guard let root = NSApp.mainMenu else { return [] }
        guard let metadataMenu = root.items
            .first(where: { $0.title == title("menu_metadata") })?
            .submenu else { return [] }
        return flatten(metadataMenu).filter { !$0.isSeparatorItem }
    }

    private func aiItem(_ localizedKey: String) -> NSMenuItem? {
        guard let root = NSApp.mainMenu else { return nil }
        guard let imageMenu = root.items
            .first(where: { $0.title == title("menu_image") })?
            .submenu else { return nil }
        return flatten(imageMenu).first { $0.title == title(localizedKey) }
    }

    /// Services the main queue (the onChange dispatch rides
    /// DispatchQueue.main.async) and lets SwiftUI/AppKit settle.
    private func pump(_ seconds: TimeInterval = 1.5) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    // MARK: - 1: the note-box read's mutation → refresh full flow

    func testMetadataFocusMutationTriggersEnablementRefresh() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        // The note box is untracked by design; its production refresh
        // driver is the menuNeedsUpdate delegate call (a user opening the
        // menu). Drive that exact face — no manual refreshAll anywhere.
        let items = metadataItems()
        XCTAssertEqual(items.count, 16, "the metadata family shape drifted")
        for entry in items {
            XCTAssertTrue(entry.isEnabled, "pre state: \(entry.title)")
        }

        NSMenuBridgeController.shared.noteMetadataFieldFocused(true)
        NSMenuBridgeController.shared.menuNeedsUpdate(savedMenu!)
        for entry in items {
            XCTAssertFalse(
                entry.isEnabled,
                "the note-box disarm missed: \(entry.title)")
        }

        NSMenuBridgeController.shared.noteMetadataFieldFocused(false)
        NSMenuBridgeController.shared.menuNeedsUpdate(savedMenu!)
        for entry in items {
            XCTAssertTrue(entry.isEnabled, "post state: \(entry.title)")
        }
    }

    // MARK: - 2: the workspace legs (primed re-arm → phase mutation)

    /// The observation adapter's arm primer: a fresh controller's install
    /// runs armObservation against the SHARED workspace box — noting OUR
    /// workspace first means the fresh arm registers its tracked legs. The
    /// adapter's onChange dispatch is observed through `mainMenuStomps`
    /// (the shared's refreshAll re-asserts its own tree while the fresh
    /// tree owns NSApp.mainMenu — one stomp per delivered mutation).
    private func primeArmWithFreshInstall() -> (NSMenu, Int) {
        guard let saved = armHarness() else {
            return (NSMenu(), 0)  // unreachable in the direct-launch host
        }
        let workspace = WorkspaceModel()
        NSMenuBridgeController.shared.noteWorkspace(workspace)
        let primer = NSMenuBridgeController()
        primer.install(deps: Self.makeDeps(sink: .init()))
        pump(0.5)
        let stompBase = NSMenuBridgeController.shared.mainMenuStomps
        return (saved, stompBase)
    }

    func testWorkspacePhaseMutationTriggersAIEnablementRefresh() {
        let (savedMenu, stompBase) = primeArmWithFreshInstall()
        defer { disarmHarness(savedMenu) }
        // NO manual refresh anywhere: the tracked workspace mutation must
        // reach the adapter's onChange → refreshAll purely through the
        // tracked-read invalidation. The stomp counter is the shared's
        // refreshAll receipt (its own tree re-asserted against the fresh
        // tree that now owns NSApp.mainMenu).
        let workspace = NSMenuBridgeController.shared.workspace
        XCTAssertNotNil(workspace, "the noted workspace must be readable")
        guard let workspace else { return }

        workspace.openEditor(imageID: 42)
        pump()
        XCTAssertGreaterThan(
            NSMenuBridgeController.shared.mainMenuStomps, stompBase,
            "the tracked workspace mutation never dispatched the adapter's refresh")
    }

    func testConsecutiveMutationsEachScheduleRefresh() {
        let (savedMenu, stompBase) = primeArmWithFreshInstall()
        defer { disarmHarness(savedMenu) }
        // The re-arm reform (plan option (a)): `armObservation` is private
        // and carries no counter, so arm-idempotence has no direct
        // observable. The indirect face: EVERY mutation in a consecutive
        // chain lands its refresh receipt — if the adapter did not re-arm
        // after an onChange, only the FIRST mutation would deliver (the
        // first rides the fresh arm; the later ones ride the shared's
        // re-arm, which re-registers the noted workspace's legs each
        // cycle).
        guard let workspace = NSMenuBridgeController.shared.workspace else {
            return XCTFail("the noted workspace must be readable")
        }
        let shared = NSMenuBridgeController.shared

        workspace.openEditor(imageID: 42)
        pump()
        XCTAssertGreaterThan(shared.mainMenuStomps, stompBase,
                             "mutation 1 (enter editor) not delivered")

        let afterFirst = shared.mainMenuStomps
        workspace.closeEditor()
        pump()
        XCTAssertGreaterThan(shared.mainMenuStomps, afterFirst,
                             "mutation 2 (close editor) not delivered — the re-arm died")

        let afterSecond = shared.mainMenuStomps
        workspace.openEditor(imageID: 43)
        pump()
        XCTAssertGreaterThan(shared.mainMenuStomps, afterSecond,
                             "mutation 3 (re-enter with a new image) not delivered")
    }

    // MARK: - 4: the stale-enablement backstop blocks dispatch

    func testStaleEnablementBackstopBlocksDispatch() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        // The dispatch spy needs an OWN controller: the production tree's
        // closures are shell-internal. A fresh instance registers the same
        // handleMenu/enabler mechanics per instance.
        let sink = ActionSink()
        let controller = NSMenuBridgeController()
        controller.install(deps: Self.makeDeps(sink: sink))

        guard let root = NSApp.mainMenu else {
            return XCTFail("install did not mount a main menu")
        }
        let editItems = flatten(
            root.items.first { $0.title == "Edit" }?.submenu ?? NSMenu())
        let undoItem = editItems.first { $0.title == title("menu_undo") }
        XCTAssertNotNil(undoItem)

        // canUndo = false → the enabler says no. The shortcut racing a
        // state flip must NOT fire the command (the backstop).
        XCTAssertTrue(sink.undoCalls == 0)
        _ = NSApp.sendAction(undoItem!.action!, to: undoItem!.target,
                             from: undoItem!)
        XCTAssertEqual(
            sink.undoCalls, 0,
            "the stale-enablement backstop let a disabled command fire")

        // State flip → the enabler says yes → the dispatch lands. The
        // second controller carries THIS editorState (one committed item).
        let editorState = EditorState()
        var pasted = HistoryStack()
        pasted.commit(
            ModuleInstance(
                id: UUID(), opName: "probe", multiPriority: 0,
                multiName: "", iopOrder: 50, version: 1, enabled: true,
                paramsData: Data("{}".utf8), paramsHash: 0),
            label: "history_test")
        editorState.installMergePaste(history: pasted)
        let controller2 = NSMenuBridgeController()
        controller2.install(deps: Self.makeDeps(sink: sink, editorState: editorState))
        guard let root2 = NSApp.mainMenu else {
            return XCTFail("second install did not mount a main menu")
        }
        let undoItem2 = flatten(
            root2.items.first { $0.title == "Edit" }?.submenu ?? NSMenu())
            .first { $0.title == title("menu_undo") }
        XCTAssertNotNil(undoItem2)
        XCTAssertEqual(undoItem2?.isEnabled, true,
                       "canUndo=true must enable undo on the second controller")
        _ = NSApp.sendAction(undoItem2!.action!, to: undoItem2!.target,
                             from: undoItem2!)
        XCTAssertEqual(
            sink.undoCalls, 1,
            "the enabled command's dispatch never reached the action")
    }
}
