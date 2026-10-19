import AppKit
import LightamerCore
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ShellGraphMigrationTests (F0P-02 T2) — the value-type state migration's
// regression pins: the menu closures write ShellGraph.shared (the ONE shared
// instance, review M2), the ContentView binding bridge reads the same
// instance, tree-external writes are visible inside hosted bodies (the
// F0PRIME §4.4 migration constraint — @State storage does not survive a
// struct copy; the observed class instance is the only legal shape), and the
// per-session rebuilt optionals ride the same box.
//
// Reachability note (recorded in DECISIONS): the production menu closures
// live in the Deps handed to `NSMenuBridgeController.shared.install` — the
// process-singleton install slot the observation suite owns — so the toggle
// legs here exercise the translated closure semantics against the shared
// instance while a source-content guard pins the production closure bodies
// to the same expression (the double-instance silent failure is guarded both
// at runtime by the identity assertions and at source level by the guard).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ShellGraphMigrationTests: XCTestCase {

    // MARK: - Hosted-probe harness (the SheetEnvironmentInjectionTests form)

    private final class ProbeBox: @unchecked Sendable {
        var visibility: [NavigationSplitViewVisibility] = []
        var transferPresented: [Bool] = []
        var writerSeen: [ObjectIdentifier?] = []
    }

    /// Reads the graph's fields INSIDE a hosted body — the `onChange`
    /// registrations and the direct body read are tracked reads, so the
    /// tree-external writes below must re-evaluate this view.
    private struct GraphProbeView: View {
        let graph: ShellGraph
        let box: ProbeBox

        var body: some View {
            // The per-session optional rides the body read path (the
            // rebuilt optionals are re-read per body evaluation post-flip).
            let writer = graph.batchSidecarWriter
            box.writerSeen.append(writer.map(ObjectIdentifier.init))
            return Color.clear
                .frame(width: 40, height: 40)
                .onChange(of: graph.columnVisibility) { _, value in
                    box.visibility.append(value)
                }
                .onChange(of: graph.adjustmentTransferPresented) { _, value in
                    box.transferPresented.append(value)
                }
                .onAppear {
                    box.visibility.append(graph.columnVisibility)
                    box.transferPresented.append(graph.adjustmentTransferPresented)
                }
        }
    }

    private var window: NSWindow?
    private var host: NSHostingView<GraphProbeView>?

    private func mountProbe() -> ProbeBox {
        let box = ProbeBox()
        let probe = GraphProbeView(graph: ShellGraph.shared, box: box)
        let hosting = NSHostingView(rootView: probe)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        self.window = window
        self.host = hosting
        return box
    }

    /// The repo-precedent cleanup shape: window + shared-graph work rides a
    /// `defer` INSIDE the @MainActor test methods (a tearDown override is
    /// nonisolated and cannot touch main-actor faces).
    private func resetGraph() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        host = nil
        ShellGraph.shared.columnVisibility = .all
        ShellGraph.shared.adjustmentTransferPresented = false
        ShellGraph.shared.batchSidecarWriter = nil
    }

    /// One runloop settle per state write — synchronous writes inside a
    /// single transaction coalesce (an all→…→all round trip would deliver
    /// no onChange at all), so each leg needs its own pass.
    private func pump(_ seconds: TimeInterval = 1.5) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host?.layoutSubtreeIfNeeded()
        }
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(_ relative: String) -> String {
        let url = repoRoot().appendingPathComponent(relative)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return source
    }

    // MARK: - 1: the shared-instance identity (menu write side ↔ view read side)

    func testSharedGraphIdentityAcrossFaceAssembly() {
        // The production assembly consumes THE shared instance (review M2's
        // double-instance silent-failure guard, runtime face).
        let controller = LightamerShellController()
        let face = controller.makeFace()
        XCTAssertEqual(
            ObjectIdentifier(controller.graph), ObjectIdentifier(ShellGraph.shared),
            "the shell controller must own the shared graph")
        XCTAssertEqual(
            ObjectIdentifier(face.graph), ObjectIdentifier(ShellGraph.shared),
            "the face assembly must consume the shared graph")

        // The source-content face: the menu closures (⌥⌘S/⌥⌘I write side)
        // and the ContentView binding (read side) both reference
        // ShellGraph.shared with the exact translated toggle expressions —
        // a second instance (or a divergent toggle body) introduced by
        // drift fails this guard.
        let shell = Self.source("App/Sources/Lightamer/UI/Shell/LightamerShell.swift")
        XCTAssertTrue(
            shell.contains("let graph = ShellGraph.shared"),
            "the controller must own ShellGraph.shared as its graph")
        let writeOccurrences = shell
            .components(separatedBy: "ShellGraph.shared.columnVisibility")
            .count - 1
        XCTAssertGreaterThanOrEqual(
            writeOccurrences, 2,
            "the showSidebar/showInspector closures must write ShellGraph.shared")
        XCTAssertTrue(
            shell.contains("(visibility == .doubleColumn) ? .all : .doubleColumn"),
            "the sidebar toggle body drifted from the translated semantics")
        XCTAssertTrue(
            shell.contains("(visibility == .detailOnly) ? .all : .detailOnly"),
            "the inspector toggle body drifted from the translated semantics")
        let contentView =
            Self.source("App/Sources/Lightamer/UI/ContentView.swift")
        XCTAssertTrue(
            contentView.contains("ShellGraph.shared.columnVisibility"),
            "the ContentView binding bridge must read ShellGraph.shared")
    }

    // MARK: - 2: the columnVisibility bridge (default + toggle semantics)

    func testColumnVisibilityDefaultAndToggleSemanticsBridge() {
        let box = mountProbe()
        defer { resetGraph() }
        pump()
        // Default alignment: the lifted field's initial value is the exact
        // pre-lift `.all` (the behavior-equivalence clause).
        XCTAssertEqual(ShellGraph.shared.columnVisibility, .all)
        XCTAssertEqual(box.visibility.first, .all,
                       "the hosted body must see the lifted default")

        // The toggle semantics as translated from the App face's
        // toggleSidebar/toggleInspector (:2692-2702 verbatim mapping):
        //   sidebar: doubleColumn ↔ all; inspector: detailOnly ↔ all.
        // (The closure bodies are source-pinned in test 1; these legs pin
        // the translated expressions the closures apply.)
        func toggleSidebar() {
            let visibility = ShellGraph.shared.columnVisibility
            ShellGraph.shared.columnVisibility =
                (visibility == .doubleColumn) ? .all : .doubleColumn
        }
        func toggleInspector() {
            let visibility = ShellGraph.shared.columnVisibility
            ShellGraph.shared.columnVisibility =
                (visibility == .detailOnly) ? .all : .detailOnly
        }

        toggleSidebar()
        XCTAssertEqual(ShellGraph.shared.columnVisibility, .doubleColumn)
        pump()
        toggleSidebar()
        XCTAssertEqual(ShellGraph.shared.columnVisibility, .all)
        pump()
        toggleInspector()
        XCTAssertEqual(ShellGraph.shared.columnVisibility, .detailOnly)
        pump()
        toggleInspector()
        XCTAssertEqual(ShellGraph.shared.columnVisibility, .all)
        pump()
        // The hosted body observed the whole transition chain (the
        // write→read bridge is live, not just the value flip): the onAppear
        // default plus one onChange leg per pump.
        XCTAssertEqual(
            box.visibility,
            [.all, .doubleColumn, .all, .detailOnly, .all],
            "the hosted body must observe every graph write")
    }

    // MARK: - 3: the value-type tree-external write (the F0PRIME §4.4 pin)

    func testValueTypeTreeExternalWriteVisibleInHostedBody() {
        let box = mountProbe()
        defer { resetGraph() }
        pump()
        XCTAssertEqual(box.transferPresented.first, false,
                       "the lifted default must be false (the pre-lift @State initial)")

        // A tree-external writer (the menu closure / delegate shape) writes
        // the box; the hosted body sees the new value through observation.
        ShellGraph.shared.adjustmentTransferPresented = true
        pump()
        XCTAssertTrue(
            box.transferPresented.contains(true),
            "the tree-external write never reached the hosted body — the box is not observed")

        ShellGraph.shared.adjustmentTransferPresented = false
        pump()
        XCTAssertEqual(box.transferPresented.last, false)
    }

    // MARK: - 4: the per-session optional rebuild rides the same box

    func testPerSessionOptionalSwapRidesTheSameBox() {
        let box = mountProbe()
        defer { resetGraph() }
        pump()
        XCTAssertEqual(box.writerSeen.first, nil,
                       "the pre-open optional starts nil")

        // The per-session rebuild: a fresh writer instance lands in the
        // box; the hosted body re-reads it (identity change visible).
        let writer = BatchSidecarWriter(
            root: FileManager.default.temporaryDirectory,
            store: SessionIndexStore(
                sessionRoot: FileManager.default.temporaryDirectory))
        ShellGraph.shared.batchSidecarWriter = writer
        pump()
        XCTAssertEqual(
            box.writerSeen.last ?? nil,
            ObjectIdentifier(writer),
            "the rebuilt optional swap never reached the hosted body")
        XCTAssertNotEqual(box.writerSeen.first ?? nil, ObjectIdentifier(writer))
    }
}
