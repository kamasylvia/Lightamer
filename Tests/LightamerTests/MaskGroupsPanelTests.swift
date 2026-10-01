@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MaskGroupsPanelTests (Plan M2-7-2 T2, KD-3; AC2/AC3) — the Mask Groups
// panel's data/command face driven through the REAL EditorState chain
// (checker ①: no test back door into storage — every assertion goes through
// the same EditorState/LayerEditingState entries the panel views call):
// the grade-order projection, the exactly-one-item property commits with
// undo round-trips, the add/remove command UUID preservation across undo,
// the orphan-form sweep, the deletion-lock interception (zero history +
// toast), the Locate linkage, and the panelMenuCases whitelist (checker M5).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class MaskGroupsPanelTests: XCTestCase {

    private var editorState: EditorState!
    private var editingState: LayerEditingState!

    override func setUp() async throws {
        try await super.setUp()
        editorState = EditorState()
        editingState = LayerEditingState()
        // The structure-commit placeholder needs a non-empty instance set.
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: TestGainModule.self, multiName: "seed",
                           params: .init(gain: 1.0))
        ])
    }

    // MARK: harness

    @discardableResult
    private func addLayer(name: String) -> AdjustmentLayer {
        let layer = editorState.addAdjustmentLayer()!
        var renamed = layer
        renamed.name = name
        editorState.commitLayerEdit(renamed, label: "test rename")
        return editorState.adjustmentLayer(id: layer.id)!
    }

    private func installMask(_ mask: MaskSpec, on layer: AdjustmentLayer) {
        var copy = layer
        copy.mask = mask
        editorState.commitLayerEdit(copy, label: "test install")
    }

    private func strokeForm(x: Float, y: Float) -> MaskForm {
        MaskForm(kind: .brush(BrushStroke(
            points: [BrushPoint(
                corner: MaskPoint(x: x, y: y), ctrl1: MaskPoint(x: x, y: y),
                ctrl2: MaskPoint(x: x, y: y))],
            radius: 0.02, hardness: 0.8, density: 0.9, opacity: 1)))
    }

    private func groupedMask() -> MaskSpec {
        let form1 = strokeForm(x: 0.2, y: 0.2)
        let form2 = strokeForm(x: 0.6, y: 0.6)
        return MaskSpec(drawn: DrawnMaskSpec(
            forms: [form1, form2],
            group: MaskGroupSpec(items: [
                MaskGroupItem(formID: form1.id, op: .union, inverted: false, opacity: 1),
                MaskGroupItem(formID: form2.id, op: .union, inverted: false, opacity: 1),
            ])))
    }

    private var document: PipelineDocument? {
        editorState.layerStack.map(PipelineDocument.init)
    }

    // MARK: AC2 — the grade-order projection

    func testProjectionFollowsGradeOrder() {
        let bottom = addLayer(name: "bottom")
        let middle = addLayer(name: "middle")
        let _ = addLayer(name: "top")
        installMask(groupedMask(), on: middle)

        let groups = try! XCTUnwrap(document?.maskGroups)
        // Every grade projects exactly one group, in layer order.
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].gradeNode.name, "bottom")
        XCTAssertEqual(groups[1].gradeNode.name, "middle")
        XCTAssertEqual(groups[2].gradeNode.name, "top")
        // The middle group carries the installed items in group order.
        XCTAssertEqual(groups[1].masks.count, 2)
        let liveItems = editorState.adjustmentLayer(id: middle.id)!.mask!.maskItems
        XCTAssertEqual(groups[1].masks.map(\.id), liveItems.map(\.id))
    }

    // MARK: AC2 — property edit = exactly one item + undo round-trip

    func testPropertyEditIsOneItemAndRoundTrips() {
        let layer = addLayer(name: "props")
        installMask(groupedMask(), on: layer)
        let id = layer.mask!.maskItems[0].id
        let items = editorState.history.items.count

        // The unified commit seam: exactly ONE history item + the
        // write-point-⑤ bump (nil → 1).
        editorState.commitMaskEdit(
            layerID: layer.id, label: String(localized: "history_mask_item_opacity")
        ) { mask in
            mask.setItemOpacity(id, 0.4)
        }
        XCTAssertEqual(editorState.history.items.count, items + 1)
        XCTAssertEqual(editorState.adjustmentLayer(id: layer.id)?.mask?.contentRevision, 1)

        // Undo restores the value AND the revision (the snapshot-restore
        // semantics — 期望行为, the cross-write gate refuses stale writers).
        XCTAssertTrue(editorState.performUndo())
        let undone = editorState.adjustmentLayer(id: layer.id)!.mask!
        XCTAssertEqual(undone.maskItems.first { $0.id == id }?.opacity, 1)
        XCTAssertNil(undone.contentRevision)
        // Redo brings the edit back (the SAME UUID — NDE-1).
        XCTAssertTrue(editorState.performRedo())
        let redone = editorState.adjustmentLayer(id: layer.id)!.mask!
        XCTAssertEqual(redone.maskItems.first { $0.id == id }?.opacity, 0.4)
        XCTAssertEqual(redone.drawn?.forms.first?.id, layer.mask?.drawn?.forms.first?.id)
    }

    func testLiveMaskEditNeverBumpsOrCommits() {
        let layer = addLayer(name: "live")
        installMask(groupedMask(), on: layer)
        let id = layer.mask!.maskItems[0].id
        let items = editorState.history.items.count

        editorState.applyLiveMaskEdit(layerID: layer.id) { mask in
            mask.setItemOpacity(id, 0.7)
        }
        XCTAssertEqual(editorState.history.items.count, items, "live leg: zero history")
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask?.contentRevision, nil,
            "live leg: zero bump")
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask?.maskItems
                .first { $0.id == id }?.opacity, 0.7,
            "the live value IS visible")
    }

    // MARK: AC2 — add/remove undo preserves UUIDs

    func testAddMaskItemUndoRedoPreservesUUIDs() {
        let layer = addLayer(name: "add")
        editingState.select(layer.id)
        let items = editorState.history.items.count

        editingState.performMaskCommand(.addMaskItem, editorState: editorState)
        XCTAssertEqual(editorState.history.items.count, items + 1, "one item")
        let added = editorState.adjustmentLayer(id: layer.id)!.mask!
        XCTAssertEqual(added.drawn?.forms.count, 1)
        XCTAssertEqual(added.drawn?.group?.items.count, 1)
        XCTAssertEqual(added.contentRevision, 1, "the write-point bump")
        XCTAssertEqual(
            added.drawn?.group?.items.first?.formID, added.drawn?.forms.first?.id,
            "the item anchors its form id")
        XCTAssertEqual(added.drawn?.forms.first?.id, added.drawn?.forms.first?.id)

        // Undo removes BOTH the form and the item; redo restores the SAME
        // identities (NDE-1 — the structure snapshots keep UUIDs).
        XCTAssertTrue(editorState.performUndo())
        XCTAssertNil(editorState.adjustmentLayer(id: layer.id)?.mask?.drawn)
        XCTAssertTrue(editorState.performRedo())
        let redone = editorState.adjustmentLayer(id: layer.id)!.mask!
        XCTAssertEqual(redone.drawn?.forms.first?.id, added.drawn?.forms.first?.id)
        XCTAssertEqual(
            redone.drawn?.group?.items.first?.formID,
            added.drawn?.group?.items.first?.formID)
    }

    func testRemoveMaskItemSweepsTheOrphanForm() {
        let layer = addLayer(name: "remove")
        installMask(groupedMask(), on: layer)
        let first = layer.mask!.maskItems[0].id
        let form1 = layer.mask!.drawn!.forms[0].id
        let form2 = layer.mask!.drawn!.forms[1].id
        editingState.select(layer.id)

        editingState.performMaskCommand(
            .removeMaskItem, itemID: first, editorState: editorState)
        let mask = editorState.adjustmentLayer(id: layer.id)!.mask!
        XCTAssertEqual(mask.drawn?.group?.items.count, 1, "the item left")
        XCTAssertEqual(mask.drawn?.group?.items.first?.formID, form2)
        XCTAssertEqual(
            mask.drawn?.forms.map(\.id), [form2],
            "the orphaned form swept, the referenced form stayed")
        XCTAssertEqual(mask.contentRevision, 1, "remove = a content write")

        // A miss (unknown id) is a silent no-op: zero history beyond the
        // removal, zero state change.
        let items = editorState.history.items.count
        editingState.performMaskCommand(
            .removeMaskItem, itemID: UUID(), editorState: editorState)
        XCTAssertEqual(editorState.history.items.count, items)
    }

    // MARK: AC3 — the deletion-lock interception

    func testRemoveLockedItemInterceptsWithZeroHistory() {
        let layer = addLayer(name: "locked")
        var mask = groupedMask()
        mask.deletionProtected = true
        installMask(mask, on: layer)
        let first = layer.mask!.maskItems[0].id
        editingState.select(layer.id)
        let items = editorState.history.items.count

        editingState.performMaskCommand(
            .removeMaskItem, itemID: first, editorState: editorState)
        // The double-leg interception: the toast + ZERO history + the mask
        // survives byte-identically.
        XCTAssertNotNil(editorState.toast)
        XCTAssertEqual(editorState.history.items.count, items)
        XCTAssertEqual(editorState.adjustmentLayer(id: layer.id)?.mask?.drawn?.forms.count, 2)
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask?.drawn?.group?.items.count, 2)
        XCTAssertTrue(editorState.adjustmentLayer(id: layer.id)!.mask!.deletionProtected!)
    }

    // MARK: the Locate linkage

    func testLocateSelectsDisarmsAndRoutesToMask() {
        let layer = addLayer(name: "locate")
        editingState.setTool(.brush)
        editingState.select(UUID()) // a decoy selection

        editingState.locateMask(layerID: layer.id)
        XCTAssertEqual(editingState.selectedLayerID, layer.id)
        XCTAssertNil(editingState.activeTool, "the tool disarms (联动选中)")
        XCTAssertEqual(editingState.pendingTabRoute, .mask, "the tab route is pending")
    }

    // MARK: checker M5 — the panelMenuCases whitelist

    func testPanelMenuCasesWhitelistExcludesItemCommands() {
        XCTAssertEqual(
            MaskCommand.panelMenuCases,
            [.duplicate, .duplicateAndInvert, .fill, .clear, .resetEdits])
        XCTAssertFalse(MaskCommand.panelMenuCases.contains(.addMaskItem))
        XCTAssertFalse(MaskCommand.panelMenuCases.contains(.removeMaskItem))
        // The CaseIterable synthesis survived (payload-free cases).
        XCTAssertEqual(MaskCommand.allCases.count, 7)
        XCTAssertTrue(MaskCommand.allCases.contains(.addMaskItem))
    }
}
