import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// HistoryRowJumpTests (Plan M2-8-2 T2, KD-2; AC#2/#3 — APP bundle, the
// VersionSwapTests real-chain precedent) — the history-panel row upgrade:
//
//   • the row INDEX conversion (newest-first display → the ORIGINAL stack
//     index the jump consumes) + the scope-kind mapping (the closed enum's
//     FOUR marker states + the layer-UUID fallthrough);
//   • the UNDO SEMANTICS QUAD (D-M2-8-CONTEXT-8: already-implemented
//     behavior — these four are the acceptance FREEZE, 立此存照):
//     ① jump back keeps the redo tail (canRedo);
//     ② an edit after the jump truncates it;
//     ③ the panel buttons and ⌘Z/⇧⌘Z share ONE coordinator face
//        (`performUndo/performRedo` through PipeCoordinator — both entry
//        points land identical state);
//     ④ a 500-item chain round-trips its .lra BYTE-FAITHFUL and undoes
//        all the way to position −1 (the M2VER-04 "permanent undo" face;
//        the 500-chain acceptance script, OQ-8/10 悬决销账).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class HistoryRowJumpTests: XCTestCase {

    // MARK: - Assembly (the production-minus-window shape)

    private func makeAssembly() async throws -> (
        editorState: EditorState, coordinator: PipeCoordinator, metal: MetalContext
    ) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry, defaultFace: false)
        return (editorState, coordinator, metal)
    }

    private nonisolated static func decodedFlat(size: Int = 96) -> DecodedImage {
        let image = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: image,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }

    private func commitEdit(
        _ editorState: EditorState, ev: Float, label: String
    ) {
        var params = ExposureModule.Params()
        params.exposure = ev
        editorState.recordChange(
            ModuleInstance(module: ExposureModule.self, params: params), label: label)
    }

    /// Bounded flush-until-persisted (the VersionSwapTests shape — the
    /// out-of-order schedule Tasks make a single flush racy).
    private func flushUntilPersisted(
        _ sidecarURL: URL, _ coordinator: PipeCoordinator, timeout: TimeInterval = 10
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if FileManager.default.fileExists(atPath: sidecarURL.path) {
                try await Task.sleep(for: .milliseconds(100))
                return
            }
            try await Task.sleep(for: .milliseconds(100))
            await coordinator.flushSidecar()
        }
        XCTFail("the sidecar file never appeared: \(sidecarURL.lastPathComponent)")
    }

    private func tempURL(_ prefix: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).tif")
    }

    // MARK: - The row index conversion (the tap→jump seam)

    func testHistoryRowsReverseDisplayWithOriginalIndices() {
        var stack = HistoryStack()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        stack.commit(seed, label: "e0")
        stack.commit(seed, label: "e1")
        stack.commit(seed, label: "e2")

        let rows = EditorToolRailView.historyRows(items: stack.items)
        // NEWEST first, each carrying its ORIGINAL stack index.
        XCTAssertEqual(rows.map(\.item.label), ["e2", "e1", "e0"])
        XCTAssertEqual(rows.map(\.originalIndex), [2, 1, 0])
    }

    // MARK: - The scope-kind mapping (the closed enum, four states)

    func testRowKindMappingAnswersAllFourMarkerStates() {
        // nil → global (no icon).
        XCTAssertEqual(.global, EditorToolRailView.HistoryRowKind.kind(of: nil))
        // The three marker family members.
        XCTAssertEqual(
            .structure,
            EditorToolRailView.HistoryRowKind.kind(of: EditorStructureScope.marker))
        XCTAssertEqual(
            .paste,
            EditorToolRailView.HistoryRowKind.kind(of: HistoryStack.pasteEpochScope))
        XCTAssertEqual(
            .drt,
            EditorToolRailView.HistoryRowKind.kind(of: HistoryStack.drtDocumentScope))
        // A layer-UUID scope is NOT a marker — no icon (the .global arm).
        XCTAssertEqual(
            .global,
            EditorToolRailView.HistoryRowKind.kind(of: UUID().uuidString))

        // The icon + AX faces are total over the enum (the render switch's
        // source): only .global renders nothing.
        let kinds: [EditorToolRailView.HistoryRowKind] =
            [.global, .structure, .paste, .drt]
        XCTAssertEqual(kinds.filter { $0.symbol.isEmpty }, [.global])
        for kind in kinds {
            XCTAssertFalse(kind.accessibilityLabel.isEmpty)
        }
    }

    // MARK: - Undo quad ①: jump back keeps the redo tail

    func testJumpBackKeepsTheRedoTail() {
        let editorState = EditorState()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        commitEdit(editorState, ev: 0.5, label: "e1")
        commitEdit(editorState, ev: 1.0, label: "e2")
        commitEdit(editorState, ev: 1.5, label: "e3")

        editorState.performJump(to: 0)
        XCTAssertTrue(editorState.canRedo, "the redo tail SURVIVES the jump")
        XCTAssertEqual(editorState.history.items.count, 3, "items never rewrite")
        // The live projection at position 0 = the e1 tuple only.
        let exposure = editorState.instances.filter {
            $0.opName == ExposureModule.opName
        }
        XCTAssertEqual(exposure.count, 1)
        XCTAssertEqual(exposure.first?.multiPriority, 0)

        // Redo walks the preserved tail forward.
        XCTAssertTrue(editorState.performRedo())
        XCTAssertTrue(editorState.canRedo)
        XCTAssertTrue(editorState.performRedo())
        XCTAssertFalse(editorState.canRedo, "back at the chain end")
    }

    // MARK: - Undo quad ②: an edit after the jump truncates the tail

    func testEditAfterJumpTruncatesTheRedoTail() {
        let editorState = EditorState()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        commitEdit(editorState, ev: 0.5, label: "e1")
        commitEdit(editorState, ev: 1.0, label: "e2")
        commitEdit(editorState, ev: 1.5, label: "e3")

        editorState.performJump(to: 0)
        XCTAssertTrue(editorState.canRedo)
        commitEdit(editorState, ev: -1.0, label: "fork")

        XCTAssertFalse(editorState.canRedo, "the edit KILLED the redo tail")
        XCTAssertEqual(
            editorState.history.items.map(\.label), ["e1", "fork"],
            "the chain shrank to the jump point + the new edit")
        XCTAssertEqual(editorState.history.position, 1)
    }

    // MARK: - Undo quad ③: panel buttons and ⌘Z/⇧⌘Z share one face

    func testPanelButtonsAndMenuShortcutsLandIdenticalState() async throws {
        let (editorState, coordinator, metal) = try await makeAssembly()
        let url = tempURL("jump-menu")
        defer { try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url)) }
        try await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)

        commitEdit(editorState, ev: 0.5, label: "e1")
        commitEdit(editorState, ev: 1.0, label: "e2")

        // Entry A: the PANEL button (the rail's undo calls the coordinator).
        await coordinator.undo()
        let afterPanel = editorState.history
        XCTAssertTrue(editorState.canUndo, "one step back is still undoable")

        // Redo forward, then entry B: the MENU shortcut — ⌘Z binds
        // `pipeCoordinator.undo()` too, whose body is EditorState's
        // `performUndo` + the shared render/persist tail. The direct
        // `performUndo` face must land the SAME state shape.
        await coordinator.redo()
        let before = editorState.history
        XCTAssertTrue(editorState.performUndo())
        let afterDirect = editorState.history

        XCTAssertEqual(afterPanel.position, afterDirect.position)
        XCTAssertEqual(afterPanel.items, afterDirect.items)
        XCTAssertEqual(before.items, afterDirect.items, "items never rewrite")
        XCTAssertEqual(editorState.history.position, before.position - 1)

        // ⇧⌘Z (redo) — the same single-face symmetry forward.
        XCTAssertTrue(editorState.performRedo())
        XCTAssertEqual(editorState.history.position, before.position)
    }

    // MARK: - Undo quad ④: the 500-chain .lra reload (byte-faithful) +
    // the all-the-way-down undo (the M2VER-04 permanent face)

    func testFiveHundredItemChainReloadsByteFaithfulAndUndoesToEnd() async throws {
        let (editorState, coordinator, metal) = try await makeAssembly()
        let url = tempURL("jump-500")
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        try await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)

        // Programmatic chain ×500 (the acceptance script — 真实 EditorState
        // 链，程序化 commit).
        let count = 500
        for step in 0..<count {
            commitEdit(
                editorState, ev: Float(step % 7) * 0.25 - 0.75, label: "e\(step)")
        }
        XCTAssertEqual(editorState.history.items.count, count)
        XCTAssertEqual(editorState.history.position, count - 1)

        // The PERSIST trigger: `recordChange` deliberately does NOT
        // schedule the write (D-S3 — the interactive faces own the
        // throttle); the programmatic script triggers the coordinator's
        // committed-move face once (re-render + scheduleSidecarWrite).
        await coordinator.pasteDidChange()

        // Flush + file-state check (the bounded poll — a single flush can
        // race the out-of-order schedule Tasks).
        try await flushUntilPersisted(sidecarURL, coordinator)
        let data = try Data(contentsOf: sidecarURL)
        let document = try JSONDecoder().decode(LightamerSidecar.self, from: data)
        XCTAssertEqual(document.history.items.count, count)
        XCTAssertEqual(document.history.position, count - 1)

        // COLD reload: a FRESH assembly reads the same .lra (the same-url
        // load keeps the in-memory session — the second coordinator is the
        // cold path).
        let (reloaded, reloadedCoordinator, _) = try await makeAssembly()
        try await reloadedCoordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)

        // BYTE-FAITHFUL: items and position exactly the original.
        XCTAssertEqual(reloaded.history.items.count, count)
        XCTAssertEqual(reloaded.history.position, count - 1)
        XCTAssertEqual(reloaded.history.items, editorState.history.items)

        // All the way down: every undo lands, ending pristine (−1).
        var undos = 0
        while reloaded.performUndo() { undos += 1 }
        XCTAssertEqual(undos, count, "the WHOLE chain is undoable")
        XCTAssertEqual(reloaded.history.position, -1)
        XCTAssertFalse(reloaded.canUndo)

        // And the walk-down projection is the pristine seed (exposure gone).
        XCTAssertEqual(
            reloaded.instances.filter { $0.opName == ExposureModule.opName }.count, 0)
    }

    // MARK: - The row-tap jump face (the effective-instances projection)

    func testRowTapJumpReprojectsTheEffectiveInstances() async throws {
        let (editorState, coordinator, metal) = try await makeAssembly()
        try await coordinator.load(
            url: tempURL("jump-row"), decoded: Self.decodedFlat(), instances: [],
            metal: metal)

        commitEdit(editorState, ev: 0.5, label: "e1")
        commitEdit(editorState, ev: 1.0, label: "e2")

        // The panel's display row for "e1" carries originalIndex 0 — the
        // tap consumes THAT index (the conversion test above pins it).
        let rows = EditorToolRailView.historyRows(items: editorState.history.items)
        let e1Row = try XCTUnwrap(rows.first { $0.item.label == "e1" })
        XCTAssertEqual(e1Row.originalIndex, 0)

        await coordinator.jumpToHistory(e1Row.originalIndex)
        XCTAssertEqual(editorState.history.position, 0)
        let exposure = editorState.instances.filter {
            $0.opName == ExposureModule.opName
        }
        XCTAssertEqual(exposure.count, 1, "the jump reprojected to the e1 state")
    }
}
