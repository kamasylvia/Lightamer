import AppKit
import ApplicationServices
import LightamerCore
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ToastFaceTests (M2-8-3 acceptance, FINDING-B regression) — every D-26 toast
// (`EditorState.presentToast`: the unclean-terminate sentinel, export
// failures, deletion locks, drift warnings) had NO render site on the default
// shell: the StatusBar toast slot mounts only in `legacyBody` (the env=1
// fallback face), so the M2-3-1 shell swap left the channel structurally
// invisible on the default project workspace. The walkthrough drove the real
// machine — sentinel armed, editor opened with an image, 9 frames across the
// 4 s toast window, zero render.
//
// The fix mounts `ToastBarView` on `WorkspaceHostView`'s bottom safe area
// inset. This suite pins the two faces of that contract:
//
//   1. the toast FACE: nil toast = zero chrome (the default face gains no
//      permanent bar — the always-on Ready/Decoding readout stays
//      legacy-only); a toast = the 22 pt StatusBar-language bar;
//   2. the WIRING: a real `WorkspaceHostView` mount exposes the toast in the
//      accessibility tree exactly while a D-26 toast is up — the structural
//      presence the default shell was missing (the same `status_toast`
//      identifier the legacy StatusBar slot carries).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ToastFaceTests: XCTestCase {

    // MARK: - 1: the toast face contract

    func testToastBarWithNoToastRendersNoChrome() {
        let host = NSHostingView(rootView: ToastBarView(toast: nil))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 40)
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(
            host.fittingSize.height, 0.5,
            "nil toast must contribute zero height — the default face gains no permanent chrome")
    }

    func testToastBarWithAToastRendersTheFace() {
        let host = NSHostingView(rootView: ToastBarView(toast: "M2-8-3 toast"))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 40)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(
            host.fittingSize.height, 22,
            "a raised toast must render the 22pt bar face")
    }

    // MARK: - 2: the default-shell wiring (the accessibility face)

    /// A hosting root carrying exactly the injections the host reads at
    /// its depth (the app root writes them; the test mirrors that). M2-9-04:
    /// the host gained the ExportState/InspectorState faces (the top-bar
    /// export entry + the grid-selection provider arm), so the mount
    /// carries those two beside the original pair.
    private struct HostRoot: View {
        let editorState: EditorState
        let pipeCoordinator: PipeCoordinator
        let exportState: ExportState
        let inspectorState: InspectorState

        var body: some View {
            WorkspaceHostView(projectController: nil, onImportFolder: { })
                .environment(editorState)
                .environment(pipeCoordinator)
                .environment(exportState)
                .environment(inspectorState)
                // M7-5-01: the turn-taking coordinator joined the host's
                // environment face (never held here — the faces stay
                // byte-identical).
                .environment(AgentControlCoordinator())
        }
    }

    /// Depth-first AX walk collecting `AXIdentifier` values (the drive-script
    /// walkthrough's read of the same tree, in-process — self AX needs no TCC
    /// grant).
    private func collectIdentifiers(
        _ element: AXUIElement, into set: inout Set<String>, depth: Int = 0
    ) {
        guard depth < 40 else { return }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &value) == .success,
            let identifier = value as? String {
            set.insert(identifier)
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
            let kids = children as? [AXUIElement] else { return }
        for kid in kids {
            collectIdentifiers(kid, into: &set, depth: depth + 1)
        }
    }

    func testWorkspaceHostViewExposesTheToastInTheAccessibilityTreeOnlyWhileItIsUp() {
        let editorState = EditorState()
        let pipeCoordinator = PipeCoordinator()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        let host = NSHostingView(rootView: HostRoot(
            editorState: editorState, pipeCoordinator: pipeCoordinator,
            exportState: ExportState(), inspectorState: InspectorState()))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        // windowNumber is the AX root handle for the on-screen window.
        let axWindow = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)

        // Settle the no-toast mount first (the attach legs pump the same run
        // loop), then pin the "no permanent chrome" half on the real face.
        let settle = Date().addingTimeInterval(2)
        while Date() < settle {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }
        var before = Set<String>()
        collectIdentifiers(axWindow, into: &before)
        XCTAssertFalse(
            before.contains("status_toast"),
            "no toast up → the default face must expose NO status_toast element (zero permanent chrome)")

        // Raise a D-26 toast exactly like the sentinel leg does, then pump
        // until the toast face shows up in the accessibility tree (the 4 s
        // auto-clear bounds the window; the first frames land well inside it).
        editorState.presentToast("toast-face-wiring-probe")
        let deadline = Date().addingTimeInterval(3)
        var after = Set<String>()
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            after = []
            collectIdentifiers(axWindow, into: &after)
            if after.contains("status_toast") { break }
        }
        XCTAssertTrue(
            after.contains("status_toast"),
            "a raised D-26 toast must surface as status_toast on the default face — the render site the shell swap lost")
    }
}
