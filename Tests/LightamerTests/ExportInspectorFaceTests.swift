import AppKit
import ApplicationServices
import LightamerCore
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ExportInspectorFaceTests (Plan M2-9-04 T1, KD-5) — the Inspector Export
// page's mount + naming-editor state layer:
//
//   1. the page switch: session state, both routes (KD-1);
//   2. the AX face: the armed switch renders the Export page in the
//      Inspector column; the unarmed face is the standard body (the剥离门
//      single-direction half that is renderable in-process — the legacy
//      face's page-unreachable half is a SOURCE fact pinned by the git
//      diff: no legacy-body call site arms the switch);
//   3. the naming editor's static faces: the typed parse gate (invalid →
//      run disabled), the live preview sample context, the eleven Alcedo
//      token inserts, the built-in deletability (KD-3/OQ-4/OQ-9);
//   4. the destination memory faces over an ISOLATED defaults suite
//      (OQ-3; the quality-key round-trips land with T2 in
//      ExportMemoryKeysTests).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ExportInspectorFaceTests: XCTestCase {

    // MARK: - 1: the page switch (KD-1)

    func testExportPageSwitchDefaultsOffAndRoutesBothWays() {
        let state = InspectorState()
        XCTAssertFalse(state.exportPageActive, "fresh state = the standard face")
        state.openExportPage()
        XCTAssertTrue(state.exportPageActive, "the entry route raises the page")
        state.closeExportPage()
        XCTAssertFalse(state.exportPageActive, "the page's close face lowers it")
    }

    // MARK: - 2: the AX face (the mount + the branch)

    /// Depth-first AX walk collecting `AXIdentifier` values (the
    /// ToastFaceTests in-process read of the same tree).
    private func collectIdentifiers(
        _ element: AXUIElement, into set: inout Set<String>, depth: Int = 0
    ) {
        guard depth < 48 else { return }
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

    /// The Inspector's injections at its depth (the page branch reads
    /// export/editor/pipe/inspector; the unarmed branch additionally needs
    /// the layer scope + the metadata rows' session faces).
    private struct InspectorHost: View {
        let inspectorState: InspectorState
        let exportState: ExportState
        let editorState: EditorState
        let pipeCoordinator: PipeCoordinator
        let editingState: LayerEditingState
        let sessionState: SessionState
        let metadataController: MetadataController

        var body: some View {
            InspectorView()
                .environment(inspectorState)
                .environment(exportState)
                .environment(editorState)
                .environment(pipeCoordinator)
                .environment(editingState)
                .environment(sessionState)
                .environment(metadataController)
        }
    }

    private func mountInspector(_ state: InspectorState) -> (NSWindow, NSHostingView<InspectorHost>) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        let host = NSHostingView(rootView: InspectorHost(
            inspectorState: state,
            exportState: ExportState(),
            editorState: EditorState(),
            pipeCoordinator: PipeCoordinator(),
            editingState: LayerEditingState(),
            sessionState: SessionState(),
            metadataController: MetadataController()))
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 640)
        window.contentView = host
        window.orderFrontRegardless()
        return (window, host)
    }

    func testArmedSwitchRendersTheExportPageInTheAccessibilityTree() {
        let state = InspectorState()
        state.openExportPage()
        let (window, host) = mountInspector(state)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let deadline = Date().addingTimeInterval(3)
        var identifiers = Set<String>()
        let axWindow = AXUIElementCreateApplication(
            ProcessInfo.processInfo.processIdentifier)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            identifiers = []
            collectIdentifiers(axWindow, into: &identifiers)
            if identifiers.contains("export.page.root") { break }
        }
        XCTAssertTrue(
            identifiers.contains("export.section.destination"),
            "the armed switch must surface the Export page's Destination "
                + "section (the OQ-1 A face); saw: \(identifiers.sorted())")
        XCTAssertTrue(
            identifiers.contains("export.section.naming"),
            "section 2 (File Naming) mounts with the page")
        XCTAssertTrue(
            identifiers.contains("export.page.choose_directory"),
            "the destination row's Browse control is reachable")
        XCTAssertFalse(
            identifiers.contains("layers.addmodule"),
            "the standard module list yields while the page is up (KD-1)")
    }

    func testUnarmedSwitchRendersTheStandardFaceOnly() {
        let state = InspectorState()
        let (window, host) = mountInspector(state)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let deadline = Date().addingTimeInterval(3)
        var identifiers = Set<String>()
        let axWindow = AXUIElementCreateApplication(
            ProcessInfo.processInfo.processIdentifier)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            identifiers = []
            collectIdentifiers(axWindow, into: &identifiers)
            if identifiers.contains("Inspector") { break }
        }
        XCTAssertTrue(identifiers.contains("Inspector"), "the standard column face")
        XCTAssertFalse(
            identifiers.contains("export.page.root"),
            "the unarmed face NEVER renders the Export page (the switch is the only arm)")
    }

    // MARK: - 3: the naming editor's state-layer faces (KD-3/KD-5)

    func testParseFeedbackGatesTheRunFace() {
        // Valid patterns: the built-in three + a hand mix. A whitespace-only
        // pattern is a literal that renders empty → the engine's fallback
        // stem keeps the name non-empty (the sanitize face), so it PARSES.
        for pattern in [
            "{source}",
            "{date:yyyy MM dd}-{sequence:0000}",
            "Export-{sequence:0000}",
            "Export-{{literal}}-{iso}",
            "   ",
        ] {
            XCTAssertNil(
                ExportNamingEditor.parseFeedback(pattern),
                "\(pattern.debugDescription) must parse clean")
        }
        // Typed failures (the OQ-4 no-silent-tolerance face).
        for pattern in [
            "",
            "{unclosed",
            "bad}brace",
            "{unknownfield}",
            "{sequence:0001}", // non-zero digit arg
            "{date:yyyy;mm}",  // ';' off the date alphabet
        ] {
            XCTAssertNotNil(
                ExportNamingEditor.parseFeedback(pattern),
                "\(pattern.debugDescription) must be a typed parse failure")
        }
        // The model gate mirrors the parse face (KD-3: startExport 禁用).
        let model = ExportM2PanelModel()
        XCTAssertTrue(model.canRun, "the seeded built-in pattern is valid")
        model.pattern = "{unclosed"
        XCTAssertNotNil(model.namingError)
        XCTAssertFalse(model.canRun, "an invalid pattern disables run/add")
    }

    func testLivePreviewRendersTheSampleContext() {
        XCTAssertEqual(
            ExportNamingEditor.livePreview("{source}-{sequence:0000}", sampleStem: "DSC0001"),
            "DSC0001-0001",
            "the sample stem + sequence=1 zero-padded")
        XCTAssertEqual(
            ExportNamingEditor.livePreview("{source}", sampleStem: nil),
            "image",
            "no sample → the engine's fallback stem")
        XCTAssertEqual(
            ExportNamingEditor.livePreview("Export-{sequence:000}", sampleStem: "IMG_0001"),
            "Export-001")
        // Absent capture faces render empty — LITERALS pass through (the
        // dash is a literal, the date face contributes nothing).
        XCTAssertEqual(
            ExportNamingEditor.livePreview("{date:yyyy}-{source}", sampleStem: "A"),
            "-A",
            "the date face contributes nothing without a capture date")
    }

    func testTokenInsertsCoverTheElevenAlcedoFields() {
        let inserts = ExportNamingEditor.tokenInserts
        XCTAssertEqual(inserts.count, 11, "the Alcedo QML:56-67 set")
        for insert in inserts {
            XCTAssertNil(
                ExportNamingEditor.parseFeedback("{source}+" + insert.token),
                "insert \(insert.token) must parse (the tokens are valid patterns)")
        }
        // The exact Alcedo spellings (RESEARCH §1.4).
        XCTAssertEqual(inserts[0].token, "{source}")
        XCTAssertEqual(inserts[1].token, "{date:yyyy MM dd}")
        XCTAssertEqual(inserts[2].token, "{cameramake}")
        XCTAssertEqual(inserts[3].token, "{cameramodel}")
        XCTAssertEqual(inserts[4].token, "{lens}")
        XCTAssertEqual(inserts[5].token, "{iso}")
        XCTAssertEqual(inserts[6].token, "{aperture}")
        XCTAssertEqual(inserts[7].token, "{shutter}")
        XCTAssertEqual(inserts[8].token, "{focal}")
        XCTAssertEqual(inserts[9].token, "{rating}")
        XCTAssertEqual(inserts[10].token, "{sequence:0000}")
    }

    func testBuiltInPresetsAreNeverDeletable() {
        for builtIn in NamingTemplateStore.builtIns {
            XCTAssertFalse(
                ExportNamingEditor.isDeletable(builtIn),
                "\(builtIn.name) is a built-in — never deletable")
        }
        XCTAssertTrue(
            ExportNamingEditor.isDeletable(
                NamingTemplate(name: "mine", pattern: "{source}")),
            "a user preset is deletable")
    }

    // MARK: - 4: the destination memory faces (OQ-3; isolated suite)

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "m2904-inspector-face-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDestinationMemoryRoundTripAndFirstUseFallback() {
        let state = ExportState(defaults: defaults)
        XCTAssertNil(state.loadM2LastDirectory(), "fresh suite = first use")

        // First-use fallback: nil memory → the first target's directory
        // (URL keeps the trailing slash on deletingLastPathComponent —
        // compare the resolved value identity, not a re-typed literal).
        let target = URL(fileURLWithPath: "/tmp/shots/IMG_0001.ARW")
        let targetDirectory = target.deletingLastPathComponent()
        XCTAssertEqual(
            state.m2EffectiveDestination(firstTargetDirectory: targetDirectory),
            targetDirectory,
            "首用回落 = 当前选中首图所在目录 (OQ-3)")

        // The picker write-back wins over the fallback.
        let picked = URL(fileURLWithPath: "/tmp/exports")
        state.storeM2LastDirectory(picked)
        XCTAssertEqual(state.loadM2LastDirectory(), picked)
        XCTAssertEqual(
            state.m2EffectiveDestination(firstTargetDirectory: targetDirectory),
            picked,
            "the memory key beats the first-use fallback")
    }

    func testDestinationMemoryDegradesOnGarbage() {
        defaults.set("", forKey: ExportState.lastDirectoryKey)
        XCTAssertNil(
            ExportState(defaults: defaults).loadM2LastDirectory(),
            "an empty path degrades to the first-use face")
    }
}
