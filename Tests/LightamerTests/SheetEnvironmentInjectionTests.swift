import AppKit
import LightamerCore
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// SheetEnvironmentInjectionTests (M2-8-3 acceptance, FINDING-A regression) —
// the Copy Adjustments dialog crashed deterministically on open: the app-root
// sheet closure sat OUTSIDE the root's `.environment(...)` writes, so the
// sheet content's environment snapshot carried neither `VersionCoordinator`
// nor `EditorState` and the first content update trapped ("No Observable
// object of type VersionCoordinator found", EXC_BREAKPOINT 2/2 on the
// walkthrough + 1/1 on the acceptance round).
//
// The M2-8-2 tests stayed green through all of it because they exercised the
// transfer MODEL outside any sheet — the "mounted at a non-sheet level" blind
// spot. This suite mounts the PRODUCTION sheet content face
// (`AdjustmentTransferSheetContent`) through a REAL `.sheet` presentation on a
// real window: the exact layer the crash lived in.
//
// Pass contract: the sheet presents and the content's first environment update
// completes (onAppear fires). A regression that drops an injection traps the
// process at that same update — the bundle run then fails hard, which IS the
// shipped crash signature (fatalError is not catchable; a trap is a failed
// run, by design here).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SheetEnvironmentInjectionTests: XCTestCase {

    /// The recorder box (the NodeCanvasGeometryTests FrameBox precedent —
    /// a reference box the preference/onAppear side effect writes into).
    private final class ProbeBox: @unchecked Sendable {
        var sheetContentAppeared = false
    }

    /// The hosting root: a plain view presenting the PRODUCTION face through
    /// a real `.sheet` — no re-injection here beyond what the production face
    /// itself carries (that self-sufficiency is the contract under test).
    private struct SheetHost: View {
        let probe: ProbeBox
        let versions: VersionCoordinator
        let editorState: EditorState
        @State private var presented = true

        var body: some View {
            Color.clear
                .frame(width: 240, height: 160)
                .sheet(isPresented: $presented) {
                    AdjustmentTransferSheetContent(
                        versions: versions, editorState: editorState)
                        .onAppear { probe.sheetContentAppeared = true }
                }
        }
    }

    @MainActor
    func testCopyAdjustmentsSheetContentResolvesItsEnvironmentInTheSheetHierarchy() {
        let probe = ProbeBox()
        let versions = VersionCoordinator()
        let editorState = EditorState()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        let host = NSHostingView(rootView: SheetHost(
            probe: probe, versions: versions, editorState: editorState))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        // Pump the run loop until the sheet content's onAppear fires (the
        // NodeCanvasGeometryTests pump shape). The first environment update of
        // the content — where the shipped dialog trapped — happens on this
        // path; reaching onAppear proves every @Environment(Type.self) read
        // in the production face resolved.
        let deadline = Date().addingTimeInterval(8)
        while !probe.sheetContentAppeared && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertTrue(
            probe.sheetContentAppeared,
            "the sheet content never appeared — presentation or environment resolution failed")

        // A few settled update passes post-presentation: the sheet stays up
        // with the production content alive inside it (no trap on re-update).
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertNotNil(window.childWindows, "the sheet window must remain attached")
    }

    /// R3 F2-1 regression (the M2-8-3 FINDING-A twin): the Import Folder
    /// dialog crashed deterministically on open — the M7-5-01 face ⑧ gate
    /// added an `@Environment(AgentControlCoordinator.self)` read INSIDE the
    /// dialog while its app-root sheet closure stayed OUTSIDE the root's
    /// `.environment(...)` writes (the R12 real-machine ips:
    /// _assertionFailure ← EnvironmentValues.subscript.getter ←
    /// EnvironmentBox.update, EXC_BREAKPOINT on mount). The production face
    /// under test is `ImportModeDialogSheetContent` — the dialog's own
    /// re-injection carrier; a regression that drops the injection traps the
    /// process at the same first content update (the shipped crash signature,
    /// the same by-design hard-fail contract as the Copy Adjustments leg
    /// above).
    @MainActor
    func testImportFolderSheetContentResolvesItsEnvironmentInTheSheetHierarchy() throws {
        let probe = ProbeBox()
        let agentControl = AgentControlCoordinator()
        // A REAL (empty) folder: the dialog's `.task` scans it and lands the
        // zero-count summary — the full mount → scan → settle path.
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sheet-env-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        let host = NSHostingView(rootView: ImportSheetHost(
            onSheetAppear: { probe.sheetContentAppeared = true },
            agentControl: agentControl, folder: folder))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        // The pump reaches PAST the first environment update (where the
        // shipped dialog trapped) into the dialog's async scan leg.
        let deadline = Date().addingTimeInterval(8)
        while !probe.sheetContentAppeared && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertTrue(
            probe.sheetContentAppeared,
            "the import sheet content never appeared — presentation or environment resolution failed")

        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertNotNil(window.childWindows, "the sheet window must remain attached")
    }
}

/// The import-leg hosting root: the PRODUCTION content face through a real
/// `.sheet`, no re-injection beyond what the face itself carries. The probe
/// rides a closure (the ProbeBox box stays private to the test class above).
private struct ImportSheetHost: View {
    let onSheetAppear: @MainActor () -> Void
    let agentControl: AgentControlCoordinator
    let folder: URL
    @State private var presented = true

    var body: some View {
        Color.clear
            .frame(width: 240, height: 160)
            .sheet(isPresented: $presented) {
                ImportModeDialogSheetContent(
                    agentControl: agentControl,
                    request: ImportFlowRequest(folder: folder),
                    initial: ImportModeChoice(mode: .copy, remember: false),
                    onConfirm: { _ in }, onCancel: {})
                    .onAppear { onSheetAppear() }
            }
    }
}
