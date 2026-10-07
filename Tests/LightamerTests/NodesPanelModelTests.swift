import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// NodesPanelModelTests (Plan M2-4-3 T1/T3, AC2/AC4) — the panel's view model
// over REAL EditorState/LayerEditingState instances (the App-level machine
// check; the checker E2 registration discipline):
//
//   T1: the projection follows stack changes · the selection write side
//       (grade → the selectedLayerID seam; develop/drt/nil → nil) · the
//       command router (one commit per command, through the REAL
//       EditorState.apply) · the lock matrix
//   T3: the drag sequence → reconnect command parameters (the
//       insertionIndex injection) · locked drags refuse to move the stack ·
//       the mix legs (live = ZERO history, commit = EXACTLY one item) ·
//       pruneSelection · the lock-hint toasts
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class NodesPanelModelTests: XCTestCase {

    // MARK: - Fixtures

    /// A REAL EditorState seeded with `gradeCount` grades (the production
    /// add face — each add lands its own structure history item).
    private func makeModel(
        gradeCount: Int = 0
    ) -> (NodesPanelModel, EditorState, LayerEditingState) {
        let editorState = EditorState()
        let editingState = LayerEditingState()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        for _ in 0..<gradeCount {
            _ = editorState.addAdjustmentLayer()
        }
        let model = NodesPanelModel(editorState: editorState, editingState: editingState)
        return (model, editorState, editingState)
    }

    private func firstGradeID(_ editorState: EditorState) -> UUID {
        editorState.layerStack!.compositeLayers[0].id
    }

    // MARK: - T3: the KD-3 interaction face (action set + lock trio)

    func testCardActionSetFollowsTheKD3Table() throws {
        let editorState = EditorState()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        _ = editorState.addAdjustmentLayer()
        let doc = try XCTUnwrap(editorState.layerStack.map(PipelineDocument.init))

        // Grades carry all four actions (the Delete row present).
        let grade = doc.grades[0]
        XCTAssertEqual(
            EditorNodesPanelView.availableActions(for: grade),
            [.rename, .toggleEnabled, .delete, .insertGradeBefore])

        // The LOCKED ENDPOINTS carry NONE — no Delete, nothing to rename.
        XCTAssertTrue(
            EditorNodesPanelView.availableActions(for: doc.develop).isEmpty)
        XCTAssertTrue(
            EditorNodesPanelView.availableActions(
                for: doc.displayTransform).isEmpty)
    }

    func testLockTrioMarkerAndCardMarkersAreStable() {
        XCTAssertEqual(NodeLockedBadge.marker, "editor.nodes.locked")

        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(AdjustmentLayer(name: "G"))
        let doc = PipelineDocument(stack)
        XCTAssertEqual(
            EditorNodesPanelView.cardMarker(for: doc.develop),
            "editor.nodes.develop")
        XCTAssertEqual(
            EditorNodesPanelView.cardMarker(for: doc.grades[0]),
            "editor.nodes.grade.\(doc.grades[0].id.uuidString)")
        XCTAssertEqual(
            EditorNodesPanelView.cardMarker(for: doc.displayTransform),
            "editor.nodes.drt")
    }

    // MARK: - T1: the projection

    func testDocumentProjectsAndFollowsStackChanges() {
        let (model, editorState, _) = makeModel(gradeCount: 2)

        let initial = model.document
        XCTAssertNotNil(initial)
        XCTAssertEqual(initial?.nodes.count, 4, "develop + 2 grades + drt")
        XCTAssertEqual(initial?.grades.count, 2)

        // A stack change re-derives the document (no manual refresh).
        editorState.apply(.addCleanGrade(before: nil))
        XCTAssertEqual(model.document?.grades.count, 3)
        XCTAssertEqual(model.document?.nodes.count, 5)

        // Projection parity with the P1 face (order + ids).
        XCTAssertEqual(
            model.document?.grades.map(\.id),
            editorState.layerStack?.compositeLayers.map(\.id))
    }

    // MARK: - T1: the selection write side (the P2 seam)

    func testSelectGradeWritesTheLayerScope() {
        let (model, editorState, editingState) = makeModel(gradeCount: 1)
        let gradeID = firstGradeID(editorState)

        model.select(gradeID)
        XCTAssertEqual(model.selectedNodeID, gradeID)
        XCTAssertEqual(editingState.selectedLayerID, gradeID,
            "a grade selection routes the tab scope (D-M2-4-CONTEXT-9)")
    }

    func testSelectEndpointsAndNilKeepTheGlobalChainFace() {
        let (model, editorState, editingState) = makeModel(gradeCount: 1)
        let stack = editorState.layerStack!
        let gradeID = firstGradeID(editorState)

        // Seed a grade selection first, then walk the non-grade faces: each
        // must CLEAR the layer scope (the unselected behavior verbatim).
        model.select(gradeID)
        XCTAssertEqual(editingState.selectedLayerID, gradeID)

        model.select(stack.baseLayer.id)
        XCTAssertNil(editingState.selectedLayerID, "develop → the global chain")
        XCTAssertEqual(model.selectedNodeID, stack.baseLayer.id,
            "the highlight still tracks the develop card")

        model.select(gradeID)
        model.select(PipelineDocument.displayTransformNodeID)
        XCTAssertNil(editingState.selectedLayerID, "drt → the global chain")

        model.select(gradeID)
        model.select(nil)
        XCTAssertNil(editingState.selectedLayerID)
        XCTAssertNil(model.selectedNodeID)
    }

    // MARK: - T1: the command router

    func testApplyRoutesThroughTheEditorState() {
        let (model, editorState, _) = makeModel(gradeCount: 1)
        let preCount = editorState.history.items.count

        model.apply(.addCleanGrade(before: nil))

        XCTAssertEqual(
            editorState.layerStack?.compositeLayers.count, 2, "the stack grew")
        XCTAssertEqual(
            editorState.history.items.count, preCount + 1,
            "EXACTLY ONE structure commit per command (through the real shell)")
    }

    func testIsLockedMatrix() {
        let (model, editorState, _) = makeModel(gradeCount: 1)
        let stack = editorState.layerStack!

        XCTAssertTrue(model.isLocked(stack.baseLayer.id), "develop is locked")
        XCTAssertTrue(
            model.isLocked(PipelineDocument.displayTransformNodeID), "drt is locked")
        XCTAssertFalse(model.isLocked(firstGradeID(editorState)), "grades are free")
        XCTAssertFalse(model.isLocked(UUID()), "unknown ids are not locked")
    }

    // MARK: - T3: the drag sequence → reconnect parameters

    func testDragSequenceProducesTheReconnectParameters() {
        let (model, editorState, _) = makeModel(gradeCount: 3)
        let ids = editorState.layerStack!.compositeLayers.map(\.id)
        let draggedID = ids[2] // the top grade

        // The view-side sequence: the drag Y resolves through the PURE
        // geometry (the insertionIndex injection point), the model routes
        // the resolved position.
        let layout = NodeCanvasGeometry.layout(
            for: model.document!.nodes, width: 248)
        let dropY = layout.center(of: ids[0]).y - 1 // the bottom grade's zone
        let index = NodeCanvasGeometry.insertionIndex(dragY: dropY, in: layout)
        XCTAssertEqual(index, 0, "above the bottom grade's midpoint → its slot")

        model.apply(.reconnectGrade(id: draggedID, toPosition: index))

        XCTAssertEqual(
            editorState.layerStack?.compositeLayers.map(\.id),
            [ids[2], ids[0], ids[1]],
            "the top grade moved to the bottom, identity preserved")
    }

    func testLockedDragRefusesToMoveTheStack() throws {
        let (model, editorState, _) = makeModel(gradeCount: 1)
        let stack = editorState.layerStack!
        let preCount = editorState.history.items.count

        // The locked face: the model refuses nothing (panels are pure
        // producers) — the SHELL silently intercepts (no item, no toast,
        // no stack movement).
        model.apply(.reconnectGrade(id: stack.baseLayer.id, toPosition: 0))
        model.apply(.removeGradeAndBridge(id: PipelineDocument.displayTransformNodeID))

        XCTAssertEqual(editorState.history.items.count, preCount)
        XCTAssertEqual(editorState.layerStack?.compositeLayers.count, 1)
        XCTAssertNil(editorState.toast, "locked endpoints never toast")
    }

    // MARK: - T3: the mix legs (live zero / commit one)

    func testMixLiveLegLandsZeroHistoryItems() {
        let (model, editorState, _) = makeModel(gradeCount: 1)
        let gradeID = firstGradeID(editorState)
        let preCount = editorState.history.items.count

        model.setMixLive(0.3, nodeID: gradeID)

        XCTAssertEqual(editorState.history.items.count, preCount,
            "the live leg renders without touching history")
        XCTAssertEqual(
            editorState.layerStack?.compositeLayers[0].opacity ?? -1, 0.3,
            accuracy: 0.0001)
    }

    func testMixCommitLegLandsExactlyOneHistoryItem() throws {
        let (model, editorState, _) = makeModel(gradeCount: 1)
        let gradeID = firstGradeID(editorState)
        let preCount = editorState.history.items.count

        model.setMixLive(0.3, nodeID: gradeID)
        model.commitMix(0.3, nodeID: gradeID)

        XCTAssertEqual(
            editorState.history.items.count, preCount + 1,
            "the whole drag lands EXACTLY one history item (KD-2)")
        XCTAssertEqual(
            try XCTUnwrap(editorState.history.items.last).label,
            String(localized: "history_graph_mix",
                defaultValue: "Adjust color grade mix"),
            "the same localization key as the command face")
        XCTAssertEqual(
            editorState.layerStack?.compositeLayers[0].opacity ?? -1, 0.3,
            accuracy: 0.0001)
    }

    func testMixClampsIntoTheUnitRange() {
        let (model, editorState, _) = makeModel(gradeCount: 1)
        let gradeID = firstGradeID(editorState)

        model.setMixLive(5, nodeID: gradeID)
        XCTAssertEqual(
            editorState.layerStack?.compositeLayers[0].opacity ?? -1, 1,
            accuracy: 0.0001)
        model.setMixLive(-3, nodeID: gradeID)
        XCTAssertEqual(
            editorState.layerStack?.compositeLayers[0].opacity ?? -1, 0,
            accuracy: 0.0001)
    }

    // MARK: - T3: pruneSelection + the lock hints

    func testPruneSelectionClearsARemovedNode() {
        let (model, editorState, _) = makeModel(gradeCount: 1)
        let gradeID = firstGradeID(editorState)
        model.select(gradeID)
        XCTAssertEqual(model.selectedNodeID, gradeID)

        editorState.apply(.removeGradeAndBridge(id: gradeID))
        XCTAssertNotNil(model.selectedNodeID, "pre-prune: the highlight lingers")
        model.pruneSelection()
        XCTAssertNil(model.selectedNodeID, "the removed node's highlight prunes")

        // A live selection survives the prune.
        model.select(gradeID)
        model.select(editorState.layerStack!.baseLayer.id)
        model.pruneSelection()
        XCTAssertEqual(
            model.selectedNodeID, editorState.layerStack!.baseLayer.id,
            "a present node's selection is untouched")
    }

    func testLockHintsToastOnlyTheEndpoints() {
        let (model, editorState, _) = makeModel(gradeCount: 1)
        let stack = editorState.layerStack!

        model.lockHint(stack.baseLayer.id)
        XCTAssertEqual(
            editorState.toast,
            String(localized: "node_lock_develop",
                defaultValue: "The Develop node is locked"),
            "develop hints")

        model.lockHint(PipelineDocument.displayTransformNodeID)
        XCTAssertEqual(
            editorState.toast,
            String(localized: "node_lock_drt",
                defaultValue: "Display Transform is a fixed endpoint"),
            "drt hints")

        // The unlocked faces never raise a NEW toast (the sentinel stays —
        // the toast auto-clears after 4s, far beyond this test's span).
        let sentinel = "lock-hint-sentinel"
        editorState.presentToast(sentinel)
        model.lockHint(firstGradeID(editorState))
        model.lockHint(UUID())
        XCTAssertEqual(
            editorState.toast, sentinel,
            "grades/unknown must not hint (they are not locked)")
    }
}
