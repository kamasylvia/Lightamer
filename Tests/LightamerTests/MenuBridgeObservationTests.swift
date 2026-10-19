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
// `NSMenuBridgeController.shared` with the production Deps — so the
// observation legs drive the PRODUCTION tree through the reachable tracked
// surfaces (the shared note box + the noted workspace's phase/currentImage
// legs; the plan's "sample subset drives the full flow" clause): a field
// mutation reaches the enabler closures purely through
// mutation → tracked-read invalidation → onChange → refreshAll. The
// deps-group reads ride the same mechanism (the same armObservation block);
// the production Deps' state objects are shell-controller-internal and have
// no test seam — the unreachability is declared, not papered over.
//
// The backstop test needs an ACTION SPY, so it mounts its OWN fresh
// controller (install/deps is internal; the dispatch target is per-instance)
// and restores the global mainMenu around itself.
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
        // No manual refresh anywhere in this test: the note-box write must
        // reach the enablers purely through the observation adapter.
        let items = metadataItems()
        XCTAssertEqual(items.count, 16, "the metadata family shape drifted")
        for entry in items {
            XCTAssertTrue(entry.isEnabled, "pre state: \(entry.title)")
        }

        NSMenuBridgeController.shared.noteMetadataFieldFocused(true)
        pump()
        for entry in items {
            XCTAssertFalse(
                entry.isEnabled,
                "the note-box mutation never refreshed the enablers: \(entry.title)")
        }

        NSMenuBridgeController.shared.noteMetadataFieldFocused(false)
        pump()
        for entry in items {
            XCTAssertTrue(entry.isEnabled, "post state: \(entry.title)")
        }
    }

    // MARK: - 2: the workspace legs (primed re-arm → phase mutation)

    func testWorkspacePhaseMutationTriggersAIEnablementRefresh() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        // Prime: note OUR workspace first, then drive one note-box change —
        // the refresh it schedules re-arms the read set WITH the workspace
        // legs (the arm-time workspace is captured per cycle).
        let workspace = WorkspaceModel()
        NSMenuBridgeController.shared.noteWorkspace(workspace)
        NSMenuBridgeController.shared.noteMetadataFieldFocused(true)
        pump()
        NSMenuBridgeController.shared.noteMetadataFieldFocused(false)
        pump()

        let upscale = aiItem("menu_image_ai_upscale")
        let denoise = aiItem("menu_image_ai_denoise")
        XCTAssertNotNil(upscale)
        XCTAssertNotNil(denoise)
        XCTAssertEqual(upscale?.isEnabled, false,
                       "library phase must start the AI family disabled")

        // The tracked mutation: library → editor with an image. NO manual
        // refresh — the adapter must deliver it.
        workspace.openEditor(imageID: 42)
        pump()
        XCTAssertEqual(upscale?.isEnabled, true,
                       "the workspace phase mutation never refreshed the AI enablers")
        XCTAssertEqual(denoise?.isEnabled, true)

        // The inverse leg: editor without an image disables.
        workspace.closeEditor()
        pump()
        XCTAssertEqual(upscale?.isEnabled, false)
        workspace.openEditor(imageID: nil)
        pump()
        XCTAssertEqual(upscale?.isEnabled, false,
                       "editor without a current image must keep the AI family disabled")
    }

    // MARK: - 3: consecutive mutations each schedule a refresh (re-arm)

    func testConsecutiveMutationsEachScheduleRefresh() {
        let savedMenu = armHarness()
        defer { disarmHarness(savedMenu) }
        // The re-arm reform (plan option (a)): `armObservation` is private
        // and carries no counter (the only counter, mainMenuStomps, is
        // stomp diagnostics), so arm-idempotence has no direct observable.
        // The sanctioned indirect face: EVERY mutation in a consecutive
        // chain lands its refresh consequence — if the adapter did not
        // re-arm after an onChange, only the FIRST mutation would land.
        let items = metadataItems()
        XCTAssertEqual(items.count, 16)

        NSMenuBridgeController.shared.noteMetadataFieldFocused(true)
        pump()
        XCTAssertTrue(items.allSatisfy { !$0.isEnabled },
                      "mutation 1 (focus on) not delivered")

        NSMenuBridgeController.shared.noteMetadataFieldFocused(false)
        pump()
        XCTAssertTrue(items.allSatisfy { $0.isEnabled },
                      "mutation 2 (focus off) not delivered — the re-arm died")

        NSMenuBridgeController.shared.noteMetadataFieldFocused(true)
        pump()
        XCTAssertTrue(items.allSatisfy { !$0.isEnabled },
                      "mutation 3 (focus on again) not delivered — the re-arm died")
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
