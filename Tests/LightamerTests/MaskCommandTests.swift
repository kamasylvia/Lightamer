@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import XCTest

// MaskCommandTests (Plan 13-3 T5, D-13-CONTEXT-9) — the mask COMMAND face
// pins:
//
//   五命令语义        — duplicate (fresh identity + mask value), duplicate-
//                      and-invert (all payload invert bits flip), fill
//                      (the EMPTY spec = the constant-1 passthrough),
//                      clear (mask nil), reset edits (chain empty, mask
//                      KEPT).
//   内核零改对照      — commands mutate RECORDS only; the composite
//                      contract bits they rely on (hasAnyPayload=false ⇔
//                      constant-1; group-item inverted bits) are the
//                      Phase 6 verified surface, untouched.
//   每步 history 可退 — every command lands history and performUndo
//                      restores the prior state (the compound
//                      duplicate-and-invert = TWO items, TWO undos).
//   enable 勾选       — the row checkbox face is the `enabled` field's
//                      commit round-trip.
//
// GUI-19 (checker E1 勘误): closed 2026-09-24 (commit 7562a9e); this
// batch's regression leg = rerunning
// `testAddModuleToLayerTripsLayerStackObservation` (in
// LayerUIWiringTests) after the command-surface assembly.
@MainActor
final class MaskCommandTests: XCTestCase {

    private var editorState: EditorState!
    private var editingState: LayerEditingState!
    private var layer: AdjustmentLayer!

    override func setUp() {
        super.setUp()
        editorState = EditorState()
        // The structure-commit placeholder needs a NON-EMPTY base/instance
        // set (the decode leg seeds it in production — here one explicit
        // record plays that role; without it commitLayerStructure is a
        // documented silent no-op).
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(
                module: TestGainModule.self, multiName: "seed",
                params: .init(gain: 1.0))
        ])
        editingState = LayerEditingState()
        layer = editorState.addAdjustmentLayer()
        editingState.select(layer?.id)
    }

    override func tearDownWithError() throws {
        editorState = nil
        editingState = nil
        layer = nil
        try super.tearDownWithError()
    }

    // MARK: fixtures

    /// A drawn mask: two forms, NO group (the 06-03 single-form path).
    private func drawnMaskWithoutGroup() -> MaskSpec {
        let brush = MaskForm(kind: .brush(BrushStroke(
            points: [BrushPoint(
                corner: MaskPoint(x: 0.3, y: 0.3),
                ctrl1: MaskPoint(x: 0.3, y: 0.3),
                ctrl2: MaskPoint(x: 0.3, y: 0.3))],
            radius: 0.05, hardness: 0.7, density: 1.0, opacity: 1.0)))
        let ellipse = MaskForm(kind: .ellipse(EllipseForm(
            center: MaskPoint(x: 0.6, y: 0.6), radiusX: 0.1, radiusY: 0.1,
            rotationDegrees: 0, border: 0)))
        return MaskSpec(drawn: DrawnMaskSpec(forms: [brush, ellipse]))
    }

    /// A drawn mask WITH a group (one inverted item + one not).
    private func drawnMaskWithGroup() -> MaskSpec {
        var spec = drawnMaskWithoutGroup()
        let forms = spec.drawn!.forms
        spec.drawn!.group = MaskGroupSpec(items: [
            MaskGroupItem(
                formID: forms[0].id, op: .union, inverted: false, opacity: 1),
            MaskGroupItem(
                formID: forms[1].id, op: .intersect, inverted: true, opacity: 1),
        ])
        return spec
    }

    /// Commit the mask onto the live layer (ONE structure item).
    private func installMask(_ mask: MaskSpec?) {
        let live = editorState.adjustmentLayer(id: layer.id)!
        live.mask = mask
        editorState.commitLayerEdit(live, label: "test install mask")
    }

    /// A chain record so `resetEdits` has something to clear.
    private func installOneChainRecord() {
        let record = ModuleInstance(
            module: TestGainModule.self, multiName: "cmdtest",
            params: .init(gain: 1.5))
        editorState.addModuleToLayer(layerID: layer.id, template: record)
    }

    private var liveLayer: AdjustmentLayer? {
        editorState.adjustmentLayer(id: layer.id)
    }

    // MARK: - Duplicate

    func testDuplicateClonesLayerWithFreshIdentityAndMask() throws {
        installMask(drawnMaskWithGroup())
        let before = try XCTUnwrap(liveLayer)
        let itemsBefore = editorState.history.items.count

        editingState.performMaskCommand(.duplicate, editorState: editorState)

        let stack = try XCTUnwrap(editorState.layerStack)
        XCTAssertEqual(stack.adjustmentLayers.count, 2)
        let copy = try XCTUnwrap(
            stack.adjustmentLayers.first { $0.id != layer.id } as? AdjustmentLayer)
        XCTAssertNotEqual(copy.id, layer.id)
        // The mask value-copies along; the chain records re-identify.
        XCTAssertEqual(copy.mask, before.mask)
        // The ORIGINAL is untouched.
        XCTAssertEqual(try XCTUnwrap(liveLayer).mask, before.mask)
        // Exactly ONE history item.
        XCTAssertEqual(editorState.history.items.count, itemsBefore + 1)
    }

    // MARK: - Duplicate-and-Invert

    func testInvertFlipsGroupItemBits() {
        let spec = drawnMaskWithGroup()
        let inverted = LayerEditingState.inverted(spec)
        let items = inverted?.drawn?.group?.items ?? []
        XCTAssertEqual(items.map(\.inverted), [true, false], "each bit flips")
        // The forms themselves are untouched (record-level flip only).
        XCTAssertEqual(
            inverted?.drawn?.forms.map(\.id),
            spec.drawn?.forms.map(\.id))
    }

    func testInvertWrapsGrouplessDrawnInInvertedGroup() {
        let inverted = LayerEditingState.inverted(drawnMaskWithoutGroup())
        let group = inverted?.drawn?.group
        XCTAssertNotNil(group, "group-less drawn gains a group")
        XCTAssertEqual(group?.items.count, 2)
        XCTAssertTrue(group?.items.allSatisfy(\.inverted) ?? false)
    }

    func testInvertFlipsParametricAndRasterBits() {
        var spec = drawnMaskWithGroup()
        spec.parametric = ParametricMask(domain: .luma, channels: [])
        spec.raster = RasterMaskRef(fileName: "m.png", maskHash: 42, invert: false)
        let inverted = LayerEditingState.inverted(spec)
        XCTAssertEqual(inverted?.parametric?.invert, true)
        XCTAssertEqual(inverted?.raster?.invert, true)
    }

    func testDuplicateAndInvertEndToEnd() throws {
        installMask(drawnMaskWithoutGroup())
        let before = try XCTUnwrap(liveLayer)

        editingState.performMaskCommand(.duplicateAndInvert, editorState: editorState)

        let stack = try XCTUnwrap(editorState.layerStack)
        XCTAssertEqual(stack.adjustmentLayers.count, 2)
        let copy = try XCTUnwrap(
            stack.adjustmentLayers.first { $0.id != layer.id } as? AdjustmentLayer)
        // The copy's mask is INVERTED (group items all flipped); the
        // original keeps the plain mask.
        let copyItems = try XCTUnwrap(copy.mask?.drawn?.group?.items)
        XCTAssertTrue(copyItems.allSatisfy(\.inverted))
        XCTAssertEqual(try XCTUnwrap(liveLayer).mask, before.mask)
    }

    // MARK: - Fill (the constant-1 passthrough, kernel zero-change)

    func testFillProducesEmptySpecConstantOneContract() throws {
        installMask(drawnMaskWithoutGroup())

        editingState.performMaskCommand(.fill, editorState: editorState)

        let live = try XCTUnwrap(liveLayer)
        let mask = try XCTUnwrap(live.mask, "fill KEEPS a mask record")
        // The Phase 6 contract: NO payload = the constant-1 passthrough
        // (composite-identical to MaskCombiner.fill(1) without any GPU
        // call — the kernel-zero-change form of "fill").
        XCTAssertFalse(mask.hasAnyPayload)
        XCTAssertFalse(mask.hasDrawnForms)
        XCTAssertFalse(mask.hasParametric)
        XCTAssertFalse(mask.hasRaster)
    }

    // MARK: - Clear

    func testClearRemovesTheMaskRecord() throws {
        installMask(drawnMaskWithoutGroup())

        editingState.performMaskCommand(.clear, editorState: editorState)

        let live = try XCTUnwrap(liveLayer)
        XCTAssertNil(live.mask, "clear removes the record entirely")
    }

    // MARK: - Reset Edits

    func testResetEditsClearsChainKeepsMask() throws {
        let mask = drawnMaskWithGroup()
        installMask(mask)
        installOneChainRecord()
        XCTAssertNotNil(try XCTUnwrap(liveLayer).chain.first)

        editingState.performMaskCommand(.resetEdits, editorState: editorState)

        let live = try XCTUnwrap(liveLayer)
        XCTAssertTrue(live.chain.isEmpty, "the iop edits reset")
        XCTAssertNotNil(live.mask, "the mask is PRESERVED")
        XCTAssertEqual(live.mask, mask)
    }

    // MARK: - 每步 history 可退

    func testEveryCommandIsUndoableStepByStep() throws {
        installMask(drawnMaskWithoutGroup())
        installOneChainRecord()
        let baseCount = editorState.history.items.count
        let maskBefore = try XCTUnwrap(liveLayer).mask
        let chainBefore = try XCTUnwrap(liveLayer).chain

        // fill: one item, one undo restores the drawn mask.
        editingState.performMaskCommand(.fill, editorState: editorState)
        XCTAssertEqual(editorState.history.items.count, baseCount + 1)
        XCTAssertTrue(performUndo())
        XCTAssertEqual(try XCTUnwrap(liveLayer).mask, maskBefore)

        // clear: one item, one undo.
        editingState.performMaskCommand(.clear, editorState: editorState)
        XCTAssertEqual(editorState.history.items.count, baseCount + 1)
        XCTAssertTrue(performUndo())
        XCTAssertEqual(try XCTUnwrap(liveLayer).mask, maskBefore)

        // resetEdits: one item, one undo restores the chain.
        editingState.performMaskCommand(.resetEdits, editorState: editorState)
        XCTAssertEqual(editorState.history.items.count, baseCount + 1)
        XCTAssertTrue(performUndo())
        XCTAssertEqual(try XCTUnwrap(liveLayer).chain, chainBefore)

        // duplicate: one item, one undo removes the clone.
        editingState.performMaskCommand(.duplicate, editorState: editorState)
        XCTAssertEqual(editorState.history.items.count, baseCount + 1)
        XCTAssertTrue(performUndo())
        XCTAssertEqual(editorState.layerStack?.adjustmentLayers.count, 1)

        // duplicateAndInvert: the DOCUMENTED compound — two items, two
        // undos (clone + inversion), each restoring one step.
        editingState.performMaskCommand(.duplicateAndInvert, editorState: editorState)
        XCTAssertEqual(editorState.history.items.count, baseCount + 2)
        XCTAssertTrue(performUndo()) // undo the inversion commit
        XCTAssertTrue(performUndo()) // undo the clone
        XCTAssertEqual(editorState.layerStack?.adjustmentLayers.count, 1)
        XCTAssertEqual(try XCTUnwrap(liveLayer).mask, maskBefore)
    }

    /// The undo leg (restores + re-renders through the coordinator seam;
    /// without one attached the state restore is the asserted face).
    private func performUndo() -> Bool {
        editorState.performUndo()
    }

    // MARK: - enable 勾选（既有字段的 commit 往返）

    func testEnabledToggleCommitRoundTrip() throws {
        let live = try XCTUnwrap(liveLayer)
        XCTAssertTrue(live.enabled, "the default is enabled")
        let items = editorState.history.items.count

        // The row checkbox face: flip the field on a VALUE snapshot +
        // the same commit entry the eye/rename/blend rows use.
        var copy = AdjustmentLayer(
            id: live.id, name: live.name, isVisible: live.isVisible,
            opacity: live.opacity, blendMode: live.blendMode,
            blendOptions: live.blendOptions, enabled: live.enabled,
            chain: live.chain, mask: live.mask)
        copy.enabled.toggle()
        editorState.commitLayerEdit(
            copy, label: String(localized: "history_layer_enable"))

        XCTAssertFalse(try XCTUnwrap(liveLayer).enabled)
        XCTAssertEqual(editorState.history.items.count, items + 1)
        XCTAssertTrue(performUndo())
        XCTAssertTrue(try XCTUnwrap(liveLayer).enabled, "⌘Z restores enabled")
    }

    // MARK: - no-selection no-op

    func testCommandWithoutSelectionIsANoOp() {
        editingState.select(nil)
        let items = editorState.history.items.count
        editingState.performMaskCommand(.fill, editorState: editorState)
        XCTAssertEqual(editorState.history.items.count, items)
    }
}
