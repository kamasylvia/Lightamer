@testable import LightamerCore
@testable import Lightamer
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

/// Plan 06-05 — the layer UI wiring suite (T1/T2/T4): the LayersPanel
/// semantics driven PROGRAMMATICALLY through EditorState/Coordinator (the
/// same shape the panel's buttons/sliders produce), the history 全粒度
/// commit counts, the layer-scope routing isolation, and the T3 state
/// machine's mutex contract.
///
/// History model under test (D-06-05-T4-1):
///   structure ops (add/remove/duplicate/merge/reorder/property/mask) →
///   ONE stackSnapshot item each (`layerScope == "__layerStack__"` —
///   excluded from every projection); layer-scoped param edits → ONE
///   `layerScope`-型 item per drag end. Undo re-derives BOTH tracks.
@MainActor
final class LayerUIWiringTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!
    private var editingState: LayerEditingState!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("layerui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)

        editorState = EditorState()
        coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)
        editingState = LayerEditingState()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func makeSyntheticImage() throws -> DecodedImage {
        let width = 32, height = 32
        var rgba = [Float](repeating: 0.25, count: width * height * 4)
        for i in 0..<(width * height) { rgba[i * 4 + 3] = 1.0 }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    /// Load with the pristine editing seed (the app's real load path).
    private func loadSynthetic() async throws {
        let url = tempDirectory.appendingPathComponent("image.exr")
        try await coordinator.load(
            url: url, decoded: makeSyntheticImage(), instances: [], metal: metal
        )
        try await Task.sleep(for: .milliseconds(20)) // let the render Task land
    }

    private func globalInstance(_ opName: String) throws -> ModuleInstance {
        try XCTUnwrap(editorState.instances.first { $0.opName == opName })
    }

    /// L014: getBytes does not wait for in-flight encoders — fence first.
    private func fence() {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - T1: structure operations (exactly ONE commit each)

    func testAddLayerCommitsExactlyOneStructureItem() async throws {
        try await loadSynthetic()
        let before = editorState.history.items.count
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())

        XCTAssertEqual(editorState.history.items.count - before, 1, "add = exactly ONE item")
        let item = editorState.history.items.last
        XCTAssertEqual(item?.layerScope, EditorState.layerStructureScope)
        XCTAssertNotNil(item?.stackSnapshot, "structure items carry the stack snapshot")
        XCTAssertEqual(item?.stackSnapshot?.layers.count, 1)
        XCTAssertEqual(item?.stackSnapshot?.layers[0].id, layer.id, "post-edit snapshot")
        XCTAssertEqual(editorState.layerStack?.compositeLayers.count, 1)
        XCTAssertEqual(layer.chain.count, 0, "a new layer ships an EMPTY chain")
        XCTAssertEqual(layer.blendMode, .normal)
        XCTAssertEqual(layer.opacity, 1.0)
        XCTAssertNil(layer.mask, "no mask = the full passthrough")
    }

    func testLayerPropertyDragCommitsOnceAndUndoRestores() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        let afterAdd = editorState.history.items.count

        // The D-H1 drag shape the opacity slider produces: N live legs
        // (zero history) + ONE commit at drag end.
        for opacity in [Float(0.9), 0.8, 0.7] {
            var copy = AdjustmentLayer(
                id: layer.id, name: layer.name, isVisible: layer.isVisible,
                opacity: opacity, blendMode: layer.blendMode,
                blendOptions: layer.blendOptions, enabled: layer.enabled,
                chain: layer.chain, mask: layer.mask)
            copy.opacity = opacity
            editorState.applyLiveLayer(copy)
            XCTAssertEqual(
                editorState.history.items.count, afterAdd,
                "live ticks must not create history")
        }
        // The commit reads the LIVE layer (the slider's onEditingChanged(false)).
        let live = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        editorState.commitLayerEdit(live, label: String(localized: "history_layer_opacity"))

        XCTAssertEqual(
            editorState.history.items.count - afterAdd, 1,
            "the whole opacity drag = exactly ONE item")
        XCTAssertEqual(editorState.adjustmentLayer(id: layer.id)?.opacity ?? 0, 0.7, accuracy: 1e-6)

        // Undo restores the property.
        await coordinator.undo()
        XCTAssertEqual(editorState.adjustmentLayer(id: layer.id)?.opacity ?? 0, 1.0, accuracy: 1e-6,
                       "undo restores opacity 1.0")
        XCTAssertNotNil(editorState.adjustmentLayer(id: layer.id),
                        "the layer itself survives a property undo")
    }

    func testReorderOneCommitAndUndoRestoresOrder() async throws {
        try await loadSynthetic()
        let a = try XCTUnwrap(editorState.addAdjustmentLayer())
        let b = try XCTUnwrap(editorState.addAdjustmentLayer())
        let c = try XCTUnwrap(editorState.addAdjustmentLayer())
        let afterAdd = editorState.history.items.count

        XCTAssertEqual(
            editorState.layerStack?.compositeLayers.map(\.id),
            [a.id, b.id, c.id], "bottom-to-top append order")

        editorState.reorderLayer(id: c.id, to: 0) // c to the bottom
        XCTAssertEqual(
            editorState.history.items.count - afterAdd, 1, "reorder = exactly ONE item")
        XCTAssertEqual(
            editorState.layerStack?.compositeLayers.map(\.id),
            [c.id, a.id, b.id])

        await coordinator.undo()
        XCTAssertEqual(
            editorState.layerStack?.compositeLayers.map(\.id),
            [a.id, b.id, c.id], "undo restores the order (identities untouched)")
    }

    func testDuplicateMintsFreshIdentityOneCommit() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        layer.chain = [try globalInstance("exposure")]
        let afterAdd = editorState.history.items.count

        let copy = try XCTUnwrap(editorState.duplicateLayer(id: layer.id) as? AdjustmentLayer)
        XCTAssertEqual(editorState.history.items.count - afterAdd, 1, "duplicate = exactly ONE item")
        XCTAssertNotEqual(copy.id, layer.id, "NEW layer identity (NDE-1)")
        XCTAssertEqual(copy.chain.count, 1)
        XCTAssertNotEqual(copy.chain[0].id, layer.chain[0].id, "NEW chain-record identity")
        XCTAssertEqual(copy.chain[0].paramsData, layer.chain[0].paramsData, "params bytes verbatim")
        // Lands directly ABOVE the original.
        XCTAssertEqual(
            editorState.layerStack?.compositeLayers.map(\.id),
            [layer.id, copy.id])
    }

    func testMergeDownIntoLayerOneCommitChainCombined() async throws {
        try await loadSynthetic()
        let bottom = try XCTUnwrap(editorState.addAdjustmentLayer())
        let top = try XCTUnwrap(editorState.addAdjustmentLayer())
        top.chain = [try globalInstance("exposure").clonedWithFreshIdentity()]
        // Commit the setup so the undo target carries the chain.
        editorState.commitLayerEdit(top, label: "setup chain")
        let afterAdd = editorState.history.items.count

        editorState.mergeLayerDown(id: top.id)
        XCTAssertEqual(editorState.history.items.count - afterAdd, 1, "merge = exactly ONE item")
        XCTAssertNil(editorState.adjustmentLayer(id: top.id), "the merged layer is gone")
        let lower = try XCTUnwrap(editorState.adjustmentLayer(id: bottom.id))
        XCTAssertEqual(lower.chain.count, 1, "the chain folded into the lower layer")
        XCTAssertEqual(lower.chain[0].opName, "exposure")

        // Undo resurrects the merged layer with its chain (stack snapshot).
        await coordinator.undo()
        let restoredTop = editorState.adjustmentLayer(id: top.id)
        XCTAssertEqual(restoredTop?.chain.count, 1, "undo restores the merged layer's chain")
        XCTAssertEqual(editorState.layerStack?.compositeLayers.count, 2)
    }

    func testRemoveLayerUndoRestoresIdentityAndParams() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        layer.opacity = 0.4
        layer.name = "dose"
        editorState.commitLayerEdit(layer, label: "props")
        editorState.removeLayer(id: layer.id)
        XCTAssertNil(editorState.adjustmentLayer(id: layer.id))

        await coordinator.undo()
        let restored = try XCTUnwrap(
            editorState.adjustmentLayer(id: layer.id),
            "undo restores the layer by IDENTITY (NDE-1)")
        XCTAssertEqual(restored.name, "dose")
        XCTAssertEqual(restored.opacity, 0.4, accuracy: 1e-6)
    }

    // MARK: - T2: layer-scope routing isolation

    /// Editing layer K's exposure must NOT touch the base/global exposure
    /// record (the LAYER-02 isolation, UI-face: `layerScope`-型 commits).
    func testLayerParamEditIsolatedFromBase() async throws {
        try await loadSynthetic()
        let baseExposure = try globalInstance("exposure")
        let baseHash = baseExposure.paramsHash

        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        let record = try XCTUnwrap(
            editorState.addModuleToLayer(
                layerID: layer.id, template: try globalInstance("exposure")),
            "add-module clones the global template into the layer chain")
        XCTAssertNotEqual(record.id, baseExposure.id, "fresh identity in the layer")

        // The panel trio in the LAYER scope (InspectorEditSession semantics).
        coordinator.beginContinuousEdit()
        var edited = record
        let params = try edited.params(of: ExposureModule.self)
        var newParams = params
        newParams.exposure = 1.5
        try edited.setParams(newParams, as: ExposureModule.self)
        await coordinator.setLiveParams(edited, layerID: layer.id)
        await coordinator.commitContinuousEdit(label: "layer exposure", layerScope: layer.id)

        // Isolation: the base record is UNTOUCHED.
        XCTAssertEqual(
            try globalInstance("exposure").paramsHash, baseHash,
            "layer K exposure must not affect the base instance hash")
        // The layer chain holds the edit.
        let chainRecord = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)?.chain.first)
        XCTAssertEqual(
            try chainRecord.params(of: ExposureModule.self).exposure, 1.5, accuracy: 1e-6)
        // Exactly ONE layerScope item (the add-module was one structure item).
        let scopeItems = editorState.history.items.filter { $0.layerScope == layer.id.uuidString }
        XCTAssertEqual(scopeItems.count, 1)
        XCTAssertEqual(scopeItems[0].snapshot.id, edited.id)

        // Undo the param edit: the chain reverts, the base stays untouched.
        await coordinator.undo()
        let reverted = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)?.chain.first)
        XCTAssertEqual(
            try reverted.params(of: ExposureModule.self).exposure, 0.0, accuracy: 1e-6,
            "undo restores the layer chain param")
        XCTAssertEqual(try globalInstance("exposure").paramsHash, baseHash)
    }

    /// 24-panel zero-modification regression: EVERY registered provider
    /// resolves a panel for a layer-scoped record through the SAME
    /// dispatch (the session carries the scope; panels are unchanged).
    func testAllProvidersResolveUnderLayerScope() async throws {
        try await loadSynthetic()
        let state = InspectorState()
        state.registerDefaultProviders()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())

        let session = InspectorEditSession(coordinator: coordinator, layerScope: layer.id)
        for opName in state.panelOpNames {
            guard let template = editorState.instances.first(where: { $0.opName == opName })
            else { continue }
            let record = template.clonedWithFreshIdentity()
            let view = state.panelView(for: record, edit: session)
            XCTAssertNotNil(view, "panel \(opName) must dispatch under a layer scope")
        }
    }

    // MARK: - T4: mask stroke history

    func testMaskStrokeCommitsOnceAndUndoRestores() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        let afterAdd = editorState.history.items.count

        // The overlay host's stroke shape: press installs the form (live),
        // ticks append points (live), stroke end = ONE commit.
        let stroke = BrushStroke(
            points: [
                BrushPoint(corner: MaskPoint(x: 0.2, y: 0.2), ctrl1: MaskPoint(x: 0.2, y: 0.2), ctrl2: MaskPoint(x: 0.2, y: 0.2)),
                BrushPoint(corner: MaskPoint(x: 0.5, y: 0.5), ctrl1: MaskPoint(x: 0.5, y: 0.5), ctrl2: MaskPoint(x: 0.5, y: 0.5)),
            ],
            radius: 0.06, hardness: 0.7, density: 1.0, opacity: 1.0)
        var live = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        live.mask = MaskSpec(drawn: DrawnMaskSpec(forms: [MaskForm(kind: .brush(stroke))]))
        editorState.applyLiveLayer(live)
        XCTAssertEqual(editorState.history.items.count, afterAdd, "live stroke = zero items")

        let committed = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        editorState.commitLayerEdit(committed, label: String(localized: "history_mask_brush"))
        XCTAssertEqual(editorState.history.items.count - afterAdd, 1, "stroke end = exactly ONE item")
        XCTAssertNotNil(editorState.adjustmentLayer(id: layer.id)?.mask)

        await coordinator.undo()
        XCTAssertNil(editorState.adjustmentLayer(id: layer.id)?.mask,
                     "undo removes the stroke")
    }

    // MARK: - T3: the editing-mode state machine (gesture mutex)

    func testEditingStateMutexRoutes() {
        let state = LayerEditingState()
        let layer = AdjustmentLayer(name: "L")

        // No selection, no tool → crop owns the viewport.
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: false, retouchPanelSelected: false),
            .crop)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: true, retouchPanelSelected: false),
            .liquify)

        // Tool WITHOUT selection → still not mask editing (disabled state).
        state.setTool(.brush)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: true, retouchPanelSelected: false),
            .liquify,
            "no layer selected → the mask tools stay disarmed")

        // Selection + tool → the mask host owns the viewport (and beats
        // the liquify route — the machine's if/else-if order).
        state.select(layer.id)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: true, retouchPanelSelected: false),
            .maskEditing)
        XCTAssertTrue(state.maskEditingActive)

        // Disarm → back to the underlying route.
        state.setTool(nil)
        XCTAssertFalse(state.maskEditingActive)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: true, retouchPanelSelected: false),
            .liquify)

        // Dangling selection self-heals once stack info is available.
        state.setTool(.gradient)
        state.select(UUID()) // not in any stack
        _ = state.selectedLayer(in: LayerStack(baseLayer: BackgroundLayer()))
        XCTAssertNil(state.selectedLayerID, "a dangling id clears")
    }

    // MARK: - 06-07 T4: the retouch surface wiring

    /// The retouch route: a selected RETOUCH layer routes the viewport to
    /// the stroke editor (below liquify in the machine order), and the
    /// route clears when the retouch selection goes away.
    func testRetouchRouteOwnershipAndMutex() {
        let state = LayerEditingState()
        let retouch = RetouchLayer(name: "Fix")
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(retouch)

        // Selected adjustment → crop (retouch panel not selected).
        state.select(UUID())
        XCTAssertNil(state.selectedRetouchLayer(in: stack))
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: false, retouchPanelSelected: false),
            .crop)

        // Selected retouch → the retouch host owns the viewport.
        state.select(retouch.id)
        let selected = state.selectedRetouchLayer(in: stack)
        XCTAssertEqual(selected?.id, retouch.id)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: false, retouchPanelSelected: true),
            .retouch)
        // Liquify still beats retouch (the machine order)…
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: true, retouchPanelSelected: true),
            .liquify)
        // …and an armed mask tool beats both.
        state.setTool(.brush)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: true, retouchPanelSelected: true),
            .maskEditing)
        state.setTool(nil)

        // The dangling retouch selection self-heals (a structural undo).
        state.select(UUID())
        _ = state.selectedRetouchLayer(in: stack)
        XCTAssertNil(state.selectedLayerID, "a dangling retouch id clears")
    }

    /// The retouch stroke commit path: addRetouchLayer / commitRetouchEdit
    /// each land EXACTLY ONE structure item, and undo restores the
    /// previous stroke list byte-for-byte (the frozen snapshot spelling).
    func testRetouchStrokeCommitsOnceAndUndoRestores() async throws {
        try await loadSynthetic()
        let undoCountBefore = editorState.history.items.count

        let layer = try XCTUnwrap(editorState.addRetouchLayer())
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(
            editorState.history.items.count - undoCountBefore, 1,
            "addRetouchLayer = exactly ONE structure item")

        let stroke = RetouchStroke(
            algorithm: .heal,
            form: MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.08, radiusY: 0.08,
                rotationDegrees: 0, border: 0.2))),
            source: MaskPoint(x: 0.3, y: 0.5))
        var updated = layer
        updated.append(stroke: stroke)
        editorState.commitRetouchEdit(updated, label: "retouch stroke")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(
            editorState.history.items.count - undoCountBefore, 2,
            "stroke commit = exactly ONE structure item")

        // The live stack carries the stroke.
        let live = try XCTUnwrap(editorState.retouchLayer(id: layer.id))
        XCTAssertEqual(live.strokes.count, 1)
        XCTAssertEqual(live.strokes[0], stroke)

        // Undo restores the empty stroke list (identity preserved).
        await coordinator.undo()
        try await Task.sleep(for: .milliseconds(20))
        let restored = try XCTUnwrap(editorState.retouchLayer(id: layer.id))
        XCTAssertTrue(restored.strokes.isEmpty, "undo removes the stroke")
        XCTAssertEqual(restored.id, layer.id, "NDE-1: the layer survives")
    }

    func testMaskToolIdentifiersAreStableAndComplete() {
        // L010: stable AX ids, not indexes; the five tools all registered.
        XCTAssertEqual(Set(MaskTool.allCases.map(\.identifier)), [
            "mask.tool.brush", "mask.tool.eraser", "mask.tool.gradient",
            "mask.tool.ellipse", "mask.tool.path",
        ])
    }

    // MARK: - 07-3 T1: the AI-mask commit channel

    /// The AI generation lands as EXACTLY ONE stackSnapshot item per
    /// confirm, the PNG exists in the masks directory, the AI-06 landing
    /// form arms the mask edit mode + tint, and the ⌘Z chain walks the
    /// generations level by level back to the empty slot. A refine re-bake
    /// overwrites the SAME maskID (D-07-CONTEXT-5) with a new hash.
    func testAIMaskCommitOneSnapshotUndoAndRefineOverwrite() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        let afterAdd = editorState.history.items.count

        func makePlane(_ pattern: UInt64) -> AIMaskPlane {
            AIMaskPlane(
                width: 16, height: 16,
                floats: (0..<256).map { ($0 % 16 < 8) == (pattern & 1 == 0) ? Float(1.0) : Float(0.0) })
        }

        // ── Generation 1: exactly ONE stackSnapshot item ──
        let ref1 = try await AIMaskEditing.commitRasterMask(
            plane: makePlane(0), source: .segment,
            imageURL: tempDirectory,
            label: String(localized: "history_ai_mask"),
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)
        XCTAssertEqual(
            editorState.history.items.count - afterAdd, 1,
            "AI mask commit = exactly ONE stackSnapshot item")
        let item = editorState.history.items.last
        XCTAssertEqual(item?.layerScope, EditorState.layerStructureScope)
        let mask = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)?.mask)
        XCTAssertEqual(mask.raster?.fileName, ref1.fileName)
        XCTAssertEqual(mask.raster?.maskHash, ref1.maskHash)
        // The PNG is on disk beside the image.
        let png = RasterMaskStore.masksDirectory(forImageURL: tempDirectory)
            .appendingPathComponent(ref1.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path))
        // The AI-06 landing form: the mask edit mode armed + tint issued.
        XCTAssertEqual(editingState.activeTool, .brush, "the mask edit mode auto-activates")
        XCTAssertEqual(coordinator.maskOverlayRequest?.layerID, layer.id)

        // ── Refine #1: SAME fileName, NEW hash, ONE more item ──
        let ref2 = try await AIMaskEditing.commitRasterMask(
            plane: makePlane(1), source: .segment,
            imageURL: tempDirectory,
            label: String(localized: "history_ai_mask"),
            activateTool: nil,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)
        XCTAssertEqual(editorState.history.items.count - (afterAdd + 1), 1, "refine = ONE item")
        XCTAssertEqual(ref2.fileName, ref1.fileName, "same maskID overwrite")
        XCTAssertNotEqual(ref2.maskHash, ref1.maskHash, "the hash flips → caches invalidate")

        // ── Refine #2: the chain grows one level per confirm ──
        let ref3 = try await AIMaskEditing.commitRasterMask(
            plane: makePlane(2), source: .segment,
            imageURL: tempDirectory,
            label: String(localized: "history_ai_mask"),
            activateTool: nil,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)
        XCTAssertEqual(editorState.history.items.count - (afterAdd + 2), 1, "refine #2 = ONE item")
        XCTAssertEqual(ref3.fileName, ref1.fileName)
        XCTAssertNotEqual(ref3.maskHash, ref2.maskHash)

        // ── The ⌘Z chain: level-by-level hash restoration ──
        await coordinator.undo()
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask?.raster?.maskHash, ref2.maskHash,
            "undo #1 → refine #1's pixels-by-reference")
        await coordinator.undo()
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask?.raster?.maskHash, ref1.maskHash,
            "undo #2 → the first generation")
        await coordinator.undo()
        XCTAssertNil(editorState.adjustmentLayer(id: layer.id)?.mask, "undo #3 → empty slot")
    }

    /// The mask-file identity: stable per (source, layer), and the source
    /// prefix round-trips (the T2 refine re-entry marker).
    func testAIMaskSourceFileIdentity() {
        let id = UUID()
        for source in [AIMaskSource.subject, .segment, .skin] {
            let name = source.fileName(forLayerID: id)
            XCTAssertEqual(name, source.fileName(forLayerID: id), "stable per layer")
            XCTAssertEqual(AIMaskSource.source(ofFileName: name), source)
            XCTAssertTrue(name.hasSuffix(".png"))
        }
        XCTAssertNil(AIMaskSource.source(ofFileName: "hand-drawn-\(id).png"))
    }

    /// The layer-B entry gate — the pure three-state + failure matrix
    /// (D-07-CONTEXT-1: only `.ready` opens the entry; layer A is never
    /// consulted).
    func testLayerBEntryGateStates() {
        XCTAssertEqual(AIMaskEntryGate.layerBEntry(for: .ready), .ready)
        XCTAssertEqual(AIMaskEntryGate.layerBEntry(for: .downloading(progress: 0.5)), .downloading)
        XCTAssertEqual(AIMaskEntryGate.layerBEntry(for: .downloading(progress: -1)), .downloading)
        XCTAssertEqual(AIMaskEntryGate.layerBEntry(for: .notReady), .needsDownload)
        XCTAssertEqual(AIMaskEntryGate.layerBEntry(for: .unknown), .needsDownload)
        XCTAssertEqual(
            AIMaskEntryGate.layerBEntry(for: .failed("network")),
            .failed("network"))
    }

    // MARK: - 07-3 T2: the tap-to-segment mode (the 4th route)

    /// The mutex truth table is EXHAUSTIVE: segment sits below liquify/
    /// retouch and above crop; arming a mask tool disarms segment and vice
    /// versa — exactly one route answers at all times.
    func testSegmentRouteMutexExhaustive() {
        let state = LayerEditingState()
        let layer = AdjustmentLayer(name: "L")

        // Bare: crop.
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: false, retouchPanelSelected: false),
            .crop)

        // Segment armed (with a selection) → segment owns; liquify/retouch
        // still outrank it; the mask tool outranks everything.
        state.select(layer.id)
        state.setSegmentActive(true)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: false, retouchPanelSelected: false),
            .segment)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: true, retouchPanelSelected: false),
            .liquify)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: false, retouchPanelSelected: true),
            .retouch)
        state.setTool(.brush)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: false, retouchPanelSelected: false),
            .maskEditing)
        XCTAssertFalse(state.segmentActive, "arming a mask tool disarms the segment mode")

        // Re-arming the segment mode disarms the mask tool.
        state.setSegmentActive(true)
        XCTAssertNil(state.activeTool)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: false, retouchPanelSelected: false),
            .segment)

        // Disarming returns to crop (no other surface selected).
        state.setSegmentActive(false)
        XCTAssertEqual(
            state.viewportRoute(liquifyPanelSelected: false, retouchPanelSelected: false),
            .crop)
    }

    /// The point-budget counter (13 point-seeded / 11 box-seeded) + the
    /// Y-flip WIRING: the recorded view points leave the session through
    /// `visionPoint` with the exact flip (the service-side seam is pinned
    /// in 07-1; this pins the UI-state leg).
    func testSegmentSessionBudgetAndYFlipWiring() throws {
        let session = SegmentSession()

        // No seed: the first tap BECOMES the seed (counts itself).
        XCTAssertFalse(session.hasSeed)
        try session.addIncluded(AIMaskPoint(x: 0.25, y: 0.75))
        XCTAssertTrue(session.hasSeed)
        XCTAssertEqual(session.usedPoints, 1)
        XCTAssertEqual(session.pointBudget, AIPointBudget.pointSeeded)

        // Fill to the point-seeded budget (the seed counted itself →
        // 12 refine points of capacity).
        for i in 0..<(AIPointBudget.pointSeeded - 1) {
            try session.addIncluded(AIMaskPoint(x: Float(i) * 0.01, y: 0.5))
        }
        XCTAssertTrue(session.budgetFull)
        XCTAssertThrowsError(try session.addIncluded(AIMaskPoint(x: 0.1, y: 0.1))) { error in
            XCTAssertEqual(
                error as? AIMaskError, .pointLimitExceeded(limit: AIPointBudget.pointSeeded))
        }
        XCTAssertThrowsError(try session.addExcluded(AIMaskPoint(x: 0.1, y: 0.1)))

        // The Y-flip wiring: every stored view point maps to
        // vision.y = 1 − view.y (vector check), and the SEED flips too.
        let flips = session.refinePoints.map { point -> Float in
            let visionY = Float(point.point.visionPoint.y)
            return visionY - (1 - point.point.y)
        }
        XCTAssertEqual(Set(flips.map { $0 }), [0.0], "vision y == 1 − view y for EVERY point")
        guard case let .point(seedPoint) = session.seed else {
            return XCTFail("the seed must survive")
        }
        XCTAssertEqual(Float(seedPoint.visionPoint.x), 0.25, accuracy: 1e-6)
        XCTAssertEqual(
            Float(seedPoint.visionPoint.y), 1 - 0.75, accuracy: 1e-6,
            "the seed point passed through the single Y-flip seam")

        // Box seed: the budget drops to 11 and the seed does NOT count.
        session.recordSeed(.box(AIMaskRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)))
        XCTAssertEqual(session.pointBudget, AIPointBudget.boxSeeded)
        XCTAssertEqual(session.usedPoints, 0, "box seeds carry no seed point")
        for i in 0..<AIPointBudget.boxSeeded {
            try session.addExcluded(AIMaskPoint(x: Float(i) * 0.01, y: 0.2))
        }
        XCTAssertTrue(session.budgetFull)
        XCTAssertThrowsError(try session.addIncluded(AIMaskPoint(x: 0.9, y: 0.9)))

        // The scribble seam: the case is constructed NOWHERE in v1 — a
        // fresh session refuses it at the record leg (typed at the service
        // leg; D-07-CONTEXT-4).
        let fresh = SegmentSession()
        fresh.recordSeed(.scribble)
        XCTAssertNil(fresh.seed, "the v1 scribble seam stays unwired")
    }

    // MARK: - content-level: a layer with a mask + params renders

    /// The full composite difference (LAYER-02 + LAYER-03 content check):
    /// a layer carrying an exposure + a brush mask must change the render
    /// INSIDE the mask and leave OUTSIDE byte-identical to the base render
    /// (L014 fence).
    func testMaskedLayerRenderChangesInsideMaskOnly() async throws {
        try await loadSynthetic()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let image = try makeSyntheticImage()
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        // The layer's chain: one testgain record (drives the pixels; the
        // LayerCompositeTests staple module — zero state deps).
        let gain = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params(gain: 2.0))

        let mask = MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .brush(BrushStroke(
                points: [BrushPoint(
                    corner: MaskPoint(x: 0.5, y: 0.5), ctrl1: MaskPoint(x: 0.5, y: 0.5),
                    ctrl2: MaskPoint(x: 0.5, y: 0.5))],
                radius: 0.25, hardness: 1.0, density: 0.8, opacity: 1.0))),
        ]))
        let layer = AdjustmentLayer(
            name: "local", opacity: 1.0, chain: [gain], mask: mask)
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layer)

        let baseRun = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: LayerStack(baseLayer: BackgroundLayer()), registry: registry,
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil,
            policy: .preview)
        let maskedRun = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: stack, registry: registry,
            resolution: .preview, cache: cache, metal: metal, longEdge: nil,
            policy: .preview)

        let w = baseRun.output.width, h = baseRun.output.height
        // The terminal gamma tail renders bgra8 — compare BYTES.
        let bpx = baseRun.output.pixelFormat == WorkingSpace.pixelFormat ? 16 : 4
        precondition(bpx == 4, "the default chain's display tail is bgra8")
        var baseBytes = [UInt8](repeating: 0, count: w * h * 4)
        var maskedBytes = [UInt8](repeating: 0, count: w * h * 4)
        fence()
        baseBytes.withUnsafeMutableBytes {
            baseRun.output.getBytes($0.baseAddress!, bytesPerRow: w * 4,
                                    from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        maskedBytes.withUnsafeMutableBytes {
            maskedRun.output.getBytes($0.baseAddress!, bytesPerRow: w * 4,
                                      from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        // 防空转 + content-level: the masked-in region CHANGED, the far
        // corner is byte-identical to the no-layer render.
        let center = (h / 2 * w + w / 2) * 4
        let corner = ((h - 2) * w + 1) * 4 // far bottom-left, first channel
        XCTAssertNotEqual(baseBytes[center], maskedBytes[center],
                          "the gain must apply inside the mask")
        XCTAssertEqual(baseBytes[corner], maskedBytes[corner],
                       "outside the mask the render is byte-identical")
    }
}

