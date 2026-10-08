import AppKit
import ApplicationServices
import LightamerCore
import LightamerIOP
import SwiftUI
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ExportCollisionPickerTests (Plan M3-1-03 T1, KD-1) — the collision-tier
// Picker's state layer (the M2-9-VALIDATION 挂账#4 close-out):
//
//   1. the model face: Increment default + all three tiers settable
//      (session state — zero persistence, the DECISIONS 会话态裁定);
//   2. the run assembly: the picked tier lands in the assembly bundle the
//      run face hands `enqueueExportM2` (the picker→queue path; the state
//      layer's passthrough consumption is ExportAssemblyTests' face);
//   3. the AX face: the Picker mounts inside the naming section of the
//      armed Export page (the ExportInspectorFaceTests in-process walk).
//
// The ENGINE stays zero-diff: `ExportNamer` is referenced read-only, the
// existing tier tests (testDefaultOverloadEqualsIncrementTier family) are
// untouched — this file adds the UI exposure half only.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ExportCollisionPickerTests: XCTestCase {

    // MARK: - 1: the model face (KD-1)

    func testCollisionPolicyDefaultsToIncrement() {
        let model = ExportM2PanelModel()
        XCTAssertEqual(
            model.collisionPolicy, .increment,
            "the seeded tier = the historical increment behavior byte-identical")
    }

    func testPickerWriteFaceCyclesAllThreeTiers() {
        let model = ExportM2PanelModel()
        // The Picker binding writes the model directly ($model.collisionPolicy).
        model.collisionPolicy = .fail
        XCTAssertEqual(model.collisionPolicy, .fail)
        model.collisionPolicy = .replace
        XCTAssertEqual(model.collisionPolicy, .replace)
        model.collisionPolicy = .increment
        XCTAssertEqual(model.collisionPolicy, .increment)
        // Session state: the rawValues stay the engine's pinned spellings.
        XCTAssertEqual(ExportNamer.ExportCollisionPolicy.increment.rawValue, "increment")
        XCTAssertEqual(ExportNamer.ExportCollisionPolicy.fail.rawValue, "fail")
        XCTAssertEqual(ExportNamer.ExportCollisionPolicy.replace.rawValue, "replace")
    }

    // MARK: - 2: the run assembly (the picker→queue path, KD-1)

    private let targetA = URL(fileURLWithPath: "/tmp/shots/IMG_0001.ARW")
    private let targetB = URL(fileURLWithPath: "/tmp/shots/IMG_0002.ARW")
    private let destination = URL(fileURLWithPath: "/tmp/shots/out")

    func testRunAssemblyCarriesPickerValueToTheQueueFace() {
        let model = ExportM2PanelModel()
        let loaded = targetA
        for tier in [ExportNamer.ExportCollisionPolicy.fail,
                     .replace, .increment] {
            model.collisionPolicy = tier
            let assembly = model.makeRunAssembly(
                targets: [targetA, targetB],
                loadedImageURL: loaded,
                instances: [],
                effectiveDrtRecord: nil,
                destination: destination)
            XCTAssertEqual(
                assembly?.collisionPolicy, tier,
                "the picked tier must reach the assembly the run face enqueues")
        }
    }

    func testRunAssemblyGateAndProjectionFacesUnchanged() {
        let model = ExportM2PanelModel()
        // The run gate: empty targets or nil destination → nil assembly.
        XCTAssertNil(model.makeRunAssembly(
            targets: [], loadedImageURL: nil, instances: [],
            effectiveDrtRecord: nil, destination: destination))
        XCTAssertNil(model.makeRunAssembly(
            targets: [targetA], loadedImageURL: nil, instances: [],
            effectiveDrtRecord: nil, destination: nil))

        // The projection override rides the OPEN image only (KD-4).
        let openRecord = ModuleInstance(module: NLMeansModule.self, params: .init())
        let assembly = model.makeRunAssembly(
            targets: [targetA, targetB],
            loadedImageURL: targetA,
            instances: [openRecord],
            effectiveDrtRecord: nil,
            destination: destination)
        XCTAssertNotNil(assembly)
        XCTAssertEqual(assembly?.batch, [targetA, targetB])
        XCTAssertEqual(assembly?.overrides.count, 2)
        XCTAssertEqual(assembly?.overrides[0]?.count, 1, "the open image rides the live set")
        XCTAssertNil(assembly?.overrides[1], "the others keep the disk sidecar truth")
        XCTAssertEqual(
            assembly?.drtRecord, DrtRecord(),
            "nil history record = the default record face (KD-4)")
        XCTAssertEqual(assembly?.subfolder, nil, "subfolder OFF → nil")
        XCTAssertEqual(assembly?.pattern, model.pattern)
    }

    // MARK: - 3: the AX face (the naming-section mount, KD-1)

    /// Depth-first AX walk collecting `AXIdentifier` values (the
    /// ExportInspectorFaceTests in-process read of the same tree).
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

    func testCollisionPickerMountsInTheNamingSection() {
        let state = InspectorState()
        state.openExportPage()
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
            identifiers.contains("export.section.naming"),
            "the naming section mounts with the page")
        XCTAssertTrue(
            identifiers.contains("export.page.collision"),
            "the collision Picker mounts in the naming section (挂账#4 close-out); "
                + "saw: \(identifiers.sorted())")
    }
}
