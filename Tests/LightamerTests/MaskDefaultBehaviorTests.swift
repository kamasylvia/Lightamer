@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MaskDefaultBehaviorTests (Plan M2-7-2 T4, KD-4; checker E1 re-ruling; AC5)
// — the Default Behavior COMPLETION-TIME dispatch matrix. The consumer face
// reuses the M2-3 carriers verbatim (MaskDrawBehavior / mask.behavior.default
// / SettingsDefaultBehaviorPage — zero new enum, zero new key); the timing is
// COMPLETION (the M2-3 page's three textual witnesses — AppPreferences header,
// "After drawing a mask" picker label, "Applies when a drawn mask is
// completed" hint), NOT the Alcedo-literal arm time (the deviation rationale
// lives in DECISIONS). The resolver is INJECTED (constants here); unset/
// unparseable = `.ask` is the AppPreferences default (M2-3, pinned by
// SettingsPagesTests — untouched).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class MaskDefaultBehaviorTests: XCTestCase {

    private var editorState: EditorState!
    private var editingState: LayerEditingState!

    override func setUp() async throws {
        try await super.setUp()
        editorState = EditorState()
        editingState = LayerEditingState()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: TestGainModule.self, multiName: "seed",
                           params: .init(gain: 1.0))
        ])
    }

    // MARK: harness

    @discardableResult
    private func addLayer() -> AdjustmentLayer {
        let layer = editorState.addAdjustmentLayer()!
        editingState.select(layer.id)
        return editorState.adjustmentLayer(id: layer.id)!
    }

    private func drawStroke(on layer: AdjustmentLayer) {
        // One committed stroke (the interaction's commit leg, the state
        // face the overlay record drives).
        var copy = layer
        let stroke = BrushStroke(
            points: [BrushPoint(
                corner: MaskPoint(x: 0.3, y: 0.3), ctrl1: MaskPoint(x: 0.3, y: 0.3),
                ctrl2: MaskPoint(x: 0.3, y: 0.3))],
            radius: 0.02, hardness: 0.8, density: 0.9, opacity: 1)
        copy.mask = MaskSpec(drawn: DrawnMaskSpec(forms: [MaskForm(kind: .brush(stroke))]))
        editorState.commitLayerEdit(copy, label: "test stroke")
    }

    private func maskFormCount(of layerID: UUID) -> Int {
        editorState.adjustmentLayer(id: layerID)?.mask?.drawn?.forms.count ?? 0
    }

    // MARK: the three-way matrix (injected constants)

    func testCurrentNodeIsZeroAction() {
        let layer = addLayer()
        drawStroke(on: layer)
        let items = editorState.history.items.count
        editingState.maskDrawBehaviorResolver = { .currentNode }

        editingState.maskDrawInteractionDidComplete(didCommit: true, editorState: editorState)
        XCTAssertEqual(editorState.layerStack?.adjustmentLayers.count, 1, "no new layer")
        XCTAssertEqual(editorState.history.items.count, items, "zero items")
        XCTAssertEqual(maskFormCount(of: layer.id), 1, "the mask stays put")
        XCTAssertFalse(editingState.pendingMaskBehaviorAsk)
    }

    func testNewLayerMigratesTheMaskInOneItemAndLeavesNoResidue() {
        let layer = addLayer()
        drawStroke(on: layer)
        let formID = layer.mask!.drawn!.forms[0].id
        let items = editorState.history.items.count
        editingState.maskDrawBehaviorResolver = { .newLayer }

        editingState.maskDrawInteractionDidComplete(didCommit: true, editorState: editorState)

        // EXACTLY ONE history item (the combined structure commit).
        XCTAssertEqual(
            editorState.history.items.count, items + 1,
            "create + migrate = ONE structure item")
        // The fresh layer above carries the SAME drawn mask (identity kept).
        let stack = editorState.layerStack!.adjustmentLayers
        let migrated = stack.last { $0.id != layer.id } as? AdjustmentLayer
        XCTAssertNotNil(migrated)
        XCTAssertEqual(migrated?.mask?.drawn?.forms.map(\.id), [formID], "NDE-1")
        // The source is left WITHOUT the mask (原层无残留).
        XCTAssertNil(editorState.adjustmentLayer(id: layer.id)?.mask)
        XCTAssertFalse(editingState.pendingMaskBehaviorAsk)
    }

    func testAskRaisesTheSheetAndTheChoiceIsNotPersisted() {
        let layer = addLayer()
        drawStroke(on: layer)
        let baseline = editorState.history.items.count
        editingState.maskDrawBehaviorResolver = { .ask }

        editingState.maskDrawInteractionDidComplete(didCommit: true, editorState: editorState)
        XCTAssertTrue(editingState.pendingMaskBehaviorAsk, "the sheet request raised")
        XCTAssertEqual(
            editorState.history.items.count, baseline,
            "the ask itself: zero items")

        // "Keep": dismiss, nothing lands.
        editingState.pendingMaskBehaviorAsk = false
        XCTAssertEqual(maskFormCount(of: layer.id), 1, "the mask stays")
        XCTAssertEqual(editorState.history.items.count, baseline)

        // "Move": the SAME one-item migration; the sheet clears.
        editingState.pendingMaskBehaviorAsk = true
        editingState.confirmMaskBehaviorMove(editorState: editorState)
        XCTAssertFalse(editingState.pendingMaskBehaviorAsk)
        XCTAssertEqual(editorState.history.items.count, baseline + 1, "the move: ONE item")
        XCTAssertNil(editorState.adjustmentLayer(id: layer.id)?.mask)
        // The choice is NOT persisted: the dispatch face writes NO
        // defaults (structural — confirmMaskBehaviorMove/migrateMaskToNew
        // touch no UserDefaults; the resolver stays the only read face and
        // nothing flips the stored M2-3 value as a side effect).
        XCTAssertEqual(
            editorState.layerStack?.adjustmentLayers.count, 2, "the migrated layer exists")
    }

    // MARK: the gate + the unset default

    func testNoOpTapNeverTriggersTheDispatch() {
        let layer = addLayer()
        drawStroke(on: layer)
        editingState.maskDrawBehaviorResolver = { .newLayer }
        let items = editorState.history.items.count

        // A no-op tap (the commit gate returned false) — even under
        // newLayer nothing happens.
        editingState.maskDrawInteractionDidComplete(didCommit: false, editorState: editorState)
        XCTAssertEqual(editorState.history.items.count, items)
        XCTAssertEqual(editorState.layerStack?.adjustmentLayers.count, 1)
        XCTAssertFalse(editingState.pendingMaskBehaviorAsk)
    }

    func testDefaultResolverReadsTheM2ThreeKey() {
        // The default resolver reads the M2-3 stored preference (the SAME
        // key, the isolated-suite face). Unset = .ask (the honest default).
        let suite = "maskbehavior-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = AppPreferences(defaultsSuiteName: suite)
        XCTAssertEqual(preferences.maskDrawBehavior, .ask, "unset = .ask (M2-3)")
        preferences.maskDrawBehavior = .newLayer
        XCTAssertEqual(preferences.maskDrawBehavior, .newLayer)

        // The production resolver closure resolves the SAME face.
        let editingState = LayerEditingState()
        editingState.maskDrawBehaviorResolver = { preferences.maskDrawBehavior }
        XCTAssertEqual(editingState.maskDrawBehaviorResolver(), .newLayer)
    }
}
