@testable import LightamerCore
@testable import Lightamer
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

// PanelWiringTests (Plan 03-02-T3/T4) — the D-T6 Inspector panel framework's
// D-H1 wiring, exercised PROGRAMMATICALLY (no UI): the trio semantics the
// LightamerSlider maps onto, InspectorState's provider dispatch, and the
// drag-storm newest-wins regression.
//
// Per the plan: drag simulation = direct calls into the trio
// (beginContinuousEdit / setLiveParams / commitContinuousEdit — exactly what
// InspectorEditSession forwards), asserted against EditorState's history +
// instance records + the sidecar throttle.
@MainActor
final class PanelWiringTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("panelwiring-\(UUID().uuidString)", isDirectory: true)
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
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// A tiny synthetic image (the harness's float32 CGImage path — no
    /// ImageIO decode involved, L016).
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
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    /// Load with the pristine editing seed (trio + temperature + exposure).
    private func loadSynthetic() async throws {
        let url = tempDirectory.appendingPathComponent("image.exr")
        try await coordinator.load(
            url: url, decoded: makeSyntheticImage(), instances: [], metal: metal
        )
        // The load seeds pristine: terminal trio + IOP editing defaults.
        let ops = editorState.instances.map(\.opName)
        XCTAssertTrue(ops.contains("exposure"), "pristine seed must include exposure")
        XCTAssertTrue(ops.contains("temperature"), "pristine seed must include temperature")
        // Plan 03-03-T6: the Lab trio joins the editing seed
        XCTAssertTrue(ops.contains("colisa"), "pristine seed must include colisa")
        XCTAssertTrue(ops.contains("tonecurve"), "pristine seed must include tonecurve")
        XCTAssertTrue(ops.contains("levels"), "pristine seed must include levels")
        // Plan 04-02-T5: crop + flip join the seed (NONE-identity flip,
        // full-frame crop — cache-neutral records so their boxes exist;
        // crop additionally ships the T5 panel).
        XCTAssertTrue(ops.contains("crop"), "pristine seed must include crop")
        XCTAssertTrue(ops.contains("flip"), "pristine seed must include flip")
        XCTAssertTrue(ops.contains("lens"), "pristine seed must include lens")
        // Plan 04-05-T5: sharpen/bilat/equalizer join the seed
        // enabled-neutral; highpass/soften join DISABLED (D11).
        XCTAssertTrue(ops.contains("sharpen"), "pristine seed must include sharpen")
        XCTAssertTrue(ops.contains("bilat"), "pristine seed must include bilat")
        XCTAssertTrue(ops.contains("equalizer"), "pristine seed must include equalizer")
        XCTAssertTrue(ops.contains("highpass"), "pristine seed must include highpass")
        XCTAssertTrue(ops.contains("soften"), "pristine seed must include soften")
    }

    private func instance(_ opName: String) throws -> ModuleInstance {
        try XCTUnwrap(editorState.instances.first { $0.opName == opName })
    }

    private func withParams<M: IOPModule>(
        _ instance: ModuleInstance, _ mutate: (inout M.Params) -> Void, as type: M.Type
    ) throws -> ModuleInstance {
        var params = try instance.params(of: type)
        mutate(&params)
        var record = instance
        try record.setParams(params, as: type)
        return record
    }

    // MARK: - Trio semantics

    /// Drag lifecycle: begin → N ticks → commit ⇒ exactly ONE history item,
    /// live params applied WITHOUT history during the drag, sidecar write
    /// scheduled at the commit.
    func testDragTrioProducesExactlyOneHistoryItem() async throws {
        try await loadSynthetic()
        let exposure = try instance("exposure")
        let initialHash = exposure.paramsHash

        coordinator.beginContinuousEdit()
        for tick in 1...10 {
            let record = try withParams(exposure, { $0.exposure = Float(tick) * 0.1 }, as: ExposureModule.self)
            await coordinator.setLiveParams(record)
            // live leg: instances updated, ZERO history items
            XCTAssertEqual(historyCount(), 0, "tick \(tick): live params must not create history")
            let live = try instance("exposure")
            XCTAssertEqual(try live.params(of: ExposureModule.self).exposure, Float(tick) * 0.1, accuracy: 1e-6)
        }
        await coordinator.commitContinuousEdit(label: "Exposure")

        XCTAssertEqual(historyCount(), 1, "drag end must commit exactly ONE item")
        let committed = try instance("exposure")
        XCTAssertEqual(committed.paramsHash != initialHash, true, "params changed by the drag")
        XCTAssertEqual(try committed.params(of: ExposureModule.self).exposure, 1.0, accuracy: 1e-6)
        let item = try XCTUnwrap(editorState.history.items.last)
        XCTAssertEqual(item.snapshot.id, exposure.id, "history snapshot anchors the SAME instance UUID")
        XCTAssertEqual(item.label, "Exposure")
    }

    /// Drag STORM (generation newest-wins): 20 rapid ticks still collapse
    /// into exactly one item; the last tick wins in the instances.
    func testDragStormCollapsesToSingleCommit() async throws {
        try await loadSynthetic()
        let temperature = try instance("temperature")

        coordinator.beginContinuousEdit()
        for tick in 1...20 {
            let record = try withParams(temperature, { $0.red = Float(tick) * 0.2 }, as: TemperatureModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: "WB red")

        XCTAssertEqual(historyCount(), 1, "drag storm must collapse to ONE history item")
        let committed = try instance("temperature")
        XCTAssertEqual(try committed.params(of: TemperatureModule.self).red, 4.0, accuracy: 1e-6,
                       "newest tick wins")
    }

    /// Discrete semantics (double-click reset / preset / eyedropper): the
    /// compressed trio — begin + set + commit — still lands exactly one
    /// item, and resetting to the DEFAULT params restores the original
    /// paramsHash (byte-identical ⇒ cache-neutral, D-H1 归零 acceptance).
    func testDiscreteResetRestoresIdentityAndHash() async throws {
        try await loadSynthetic()
        let exposure = try instance("exposure")
        let defaultHash = exposure.paramsHash

        // one drag to +1EV
        coordinator.beginContinuousEdit()
        let up = try withParams(exposure, { $0.exposure = 1.0 }, as: ExposureModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: "Exposure")
        XCTAssertEqual(historyCount(), 1)

        // double-click reset (discrete)
        let current = try instance("exposure")
        let reset = try withParams(current, { $0.exposure = 0 }, as: ExposureModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(reset)
        await coordinator.commitContinuousEdit(label: "Exposure reset")

        XCTAssertEqual(historyCount(), 2, "discrete control = ONE additional item")
        let after = try instance("exposure")
        XCTAssertEqual(after.paramsHash, defaultHash,
                       "reset to default must reproduce the ORIGINAL paramsHash (cache all-hit)")
        XCTAssertEqual(
            try after.params(of: ExposureModule.self),
            try exposure.params(of: ExposureModule.self),
            "params equal the pristine defaults"
        )
    }

    /// Undo after a drag restores the pre-drag instance params.
    func testUndoAfterDragRestoresPreviousParams() async throws {
        try await loadSynthetic()
        let exposure = try instance("exposure")

        coordinator.beginContinuousEdit()
        let up = try withParams(exposure, { $0.exposure = 0.7 }, as: ExposureModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: "Exposure")

        await coordinator.undo()
        XCTAssertEqual(historyCount(), 1, "undo moves the pointer, truncation only on next commit")
        let reverted = try instance("exposure")
        XCTAssertEqual(try reverted.params(of: ExposureModule.self).exposure, 0.0, accuracy: 1e-6,
                       "undo restores the pre-drag params")
    }
    /// 04-08-F2 (GUI-9 闭环): commit → canUndo → undo → 渲染回退 +
    /// position 回退；redo → 前进. 菜单 enabled 跟随 canUndo/canRedo
    /// （CommandGroup 绑定源），⌘Z 走 coordinator.undo → historyDidChange
    /// 重渲染同一链 —— 回退后渲染与 pre-commit 逐分量一致.
    func testUndoRedoEntryRestoresRenderAndPosition() async throws {
        try await loadSynthetic()
        XCTAssertFalse(editorState.canUndo, "pristine: nothing to undo")
        XCTAssertFalse(editorState.canRedo, "pristine: nothing to redo")

        let exposure = try instance("exposure")
        let baseHash = try instance("exposure").paramsHash
        let basePlane = try await renderExposurePlane()

        coordinator.beginContinuousEdit()
        let up = try withParams(exposure, { $0.exposure = 0.7 }, as: ExposureModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: "Exposure")
        XCTAssertEqual(historyCount(), 1)
        XCTAssertTrue(editorState.canUndo, "commit lights the Undo entry")
        XCTAssertFalse(editorState.canRedo, "fresh commit: no redo tail")
        XCTAssertEqual(editorState.history.position, 0)
        let editedParamsHash = try instance("exposure").paramsHash
        XCTAssertNotEqual(editedParamsHash, baseHash, "commit changes params")

        await coordinator.undo()
        XCTAssertEqual(editorState.history.position, -1, "undo steps the pointer to pristine")
        XCTAssertEqual(historyCount(), 1, "items retained (pointer semantics)")
        XCTAssertFalse(editorState.canUndo, "pristine: Undo dims again")
        XCTAssertTrue(editorState.canRedo, "undo opens the redo tail")
        let reverted = try instance("exposure")
        XCTAssertEqual(reverted.paramsHash, baseHash, "position 回退 → params 回退")
        let revertedPlane = try await renderExposurePlane()
        XCTAssertEqual(revertedPlane, basePlane, "渲染回退：undo 后平面与 commit 前逐分量一致")

        await coordinator.redo()
        XCTAssertEqual(editorState.history.position, 0)
        XCTAssertTrue(editorState.canUndo)
        XCTAssertFalse(editorState.canRedo)
        XCTAssertEqual(try instance("exposure").paramsHash, editedParamsHash, "redo 恢复提交态")
    }

    /// Render the exposure-only chain at a fixed bucket and snapshot the
    /// PREVIEW plane bytes (fenced readback, L014). The exposure box is
    /// materialized from the CURRENT live record — the same path
    /// `historyDidChange` re-renders through after undo/redo. The registry
    /// is populated first (bare `makeDefault` only carries the terminal
    /// trio — exposure joins via the LightamerIOP hook, as in setUp).
    private func renderExposurePlane() async throws -> [UInt8] {
        let record = try instance("exposure")
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let madeExposure = await registry.makeBox(
            opName: ExposureModule.opName, instanceID: record.id)
        let box = try XCTUnwrap(madeExposure as? ModuleBox<ExposureModule>)
        try await box.apply(record)
        let madeColorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorin = try XCTUnwrap(madeColorin as? ModuleBox<ColorInModule>)
        await colorin.setParams(.init())
        let image = try makeSyntheticImage()
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [colorin, box], imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: 48)
        drainForUndo()
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 16)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return bytes
    }

    private func drainForUndo() {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// Sidecar: the commit schedules a throttled `.lra` write; flushing
    /// yields a document whose history hash matches the live stack.
    func testCommitSchedulesSidecarWrite() async throws {
        try await loadSynthetic()
        let exposure = try instance("exposure")
        coordinator.beginContinuousEdit()
        let up = try withParams(exposure, { $0.exposure = 0.3 }, as: ExposureModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: "Exposure")

        await coordinator.flushSidecar()
        // the throttle task races the flush — allow it to land, then re-flush
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.flushSidecar()
        // D-S2 naming: "<original FULL name>.lra" — image.exr → image.exr.lra
        let sidecarURL = tempDirectory.appendingPathComponent("image.exr.lra")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path),
                      "flush must produce the .lra sidecar")
        let data = try Data(contentsOf: sidecarURL)
        let document = try XCTUnwrap(JSONDecoder().decode(LightamerSidecar.self, from: data))
        XCTAssertEqual(document.history.items.count, 1)
        XCTAssertEqual(document.history.items.last?.label, "Exposure")
    }

    // MARK: - InspectorState provider dispatch

    func testInspectorStateDispatchesPanelsByOpName() throws {
        let state = InspectorState()
        state.registerDefaultProviders()

        XCTAssertTrue(state.panelOpNames.contains("exposure"))
        XCTAssertTrue(state.panelOpNames.contains("temperature"))
        // Plan 03-03-T6: the Lab trio panels
        XCTAssertTrue(state.panelOpNames.contains("colisa"))
        XCTAssertTrue(state.panelOpNames.contains("tonecurve"))
        XCTAssertTrue(state.panelOpNames.contains("levels"))
        // Plan 03-04-T5: the scene-referred pair
        XCTAssertTrue(state.panelOpNames.contains("sigmoid"))
        XCTAssertTrue(state.panelOpNames.contains("shadhi"))
        // Plan 03-05-T7: the tone equalizer panel
        XCTAssertTrue(state.panelOpNames.contains("toneequal"))

        let exposureRecord = ModuleInstance(module: ExposureModule.self, params: .init())
        let session = InspectorEditSession(coordinator: coordinator)
        let view = state.panelView(for: exposureRecord, edit: session)
        XCTAssertNotNil(view, "exposure must dispatch a panel")

        let sigmoidRecord = ModuleInstance(module: SigmoidModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: sigmoidRecord, edit: session),
                        "sigmoid must dispatch a panel")
        let shadhiRecord = ModuleInstance(module: ShadhiModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: shadhiRecord, edit: session),
                        "shadhi must dispatch a panel")
        let toneEqualRecord = ModuleInstance(module: ToneEqualModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: toneEqualRecord, edit: session),
                        "toneequal must dispatch a panel")

        let colorinRecord = ModuleInstance(module: ColorInModule.self, params: .init())
        XCTAssertNil(state.panelView(for: colorinRecord, edit: session),
                     "terminal infrastructure has no panel")

        state.selectPanel(instanceID: exposureRecord.id)
        XCTAssertEqual(state.selectedPanel, exposureRecord.id.uuidString)
    }

    // MARK: - 03-03 Lab trio panel wiring (T6)

    /// Colisa slider drag: 10 ticks → exactly ONE commit; the params hash
    /// flips (D-H4) and the committed value is the last tick.
    func testColisaPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let colisa = try instance("colisa")

        coordinator.beginContinuousEdit()
        for tick in 1...10 {
            let record = try withParams(colisa, { $0.contrast = Float(tick) * 0.05 }, as: ColisaModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_colisa"))

        XCTAssertEqual(historyCount(), 1, "colisa drag = exactly ONE item")
        let committed = try instance("colisa")
        XCTAssertEqual(try committed.params(of: ColisaModule.self).contrast, 0.5, accuracy: 1e-6)
    }

    /// Colisa double-click reset (discrete trio) restores the identity
    /// paramsHash — the cache-neutral acceptance.
    func testColisaResetRestoresIdentityHash() async throws {
        try await loadSynthetic()
        let colisa = try instance("colisa")
        let defaultHash = colisa.paramsHash

        coordinator.beginContinuousEdit()
        let up = try withParams(colisa, { $0.saturation = 0.5 }, as: ColisaModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: "colisa")

        let reset = try withParams(try instance("colisa"), { $0.saturation = 0 }, as: ColisaModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(reset)
        await coordinator.commitContinuousEdit(label: "colisa reset")

        let after = try instance("colisa")
        XCTAssertEqual(after.paramsHash, defaultHash, "reset restores the original hash")
    }

    /// Tonecurve node edit (the CurveEditorView payload = a node set): the
    /// trio lands exactly one item with the last node set.
    func testToneCurvePanelNodeEditCommitsOnce() async throws {
        try await loadSynthetic()
        let tonecurve = try instance("tonecurve")

        coordinator.beginContinuousEdit()
        for tick in 1...5 {
            let nodes = [
                ToneCurveModule.Node(x: 0, y: 0),
                ToneCurveModule.Node(x: 0.5, y: 0.5 + Float(tick) * 0.02),
                ToneCurveModule.Node(x: 1, y: 1),
            ]
            let record = try withParams(tonecurve, { $0.curveL = nodes }, as: ToneCurveModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_tonecurve"))

        XCTAssertEqual(historyCount(), 1, "tonecurve node drag = exactly ONE item")
        let committed = try instance("tonecurve")
        XCTAssertEqual(try committed.params(of: ToneCurveModule.self).curveL[1].y, 0.6, accuracy: 1e-6)
    }

    /// Levels point drag (manual mode) + mode switch (discrete).
    func testLevelsPanelDragAndModeSwitch() async throws {
        try await loadSynthetic()
        let levels = try instance("levels")

        coordinator.beginContinuousEdit()
        let dragged = try withParams(levels, { $0.levels = [0.2, 0.5, 0.8] }, as: LevelsModule.self)
        await coordinator.setLiveParams(dragged)
        await coordinator.commitContinuousEdit(label: String(localized: "history_levels"))
        XCTAssertEqual(historyCount(), 1, "levels drag = exactly ONE item")

        // mode switch = discrete one-commit edit
        let current = try instance("levels")
        let switched = try withParams(current, { $0.mode = .automatic }, as: LevelsModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(switched)
        await coordinator.commitContinuousEdit(label: "levels mode")
        XCTAssertEqual(historyCount(), 2, "mode switch adds exactly ONE item")
        XCTAssertEqual(try instance("levels").params(of: LevelsModule.self).mode, .automatic)
    }

    // MARK: - 03-04 sigmoid / shadhi panel wiring (T5)

    /// Sigmoid: append via one trio (1 item), then a 6-tick drag via a
    /// second trio (+1, the last tick wins) — the D-T2 baseline's panel
    /// wiring.
    func testSigmoidPanelDragCommitsOnce() async throws {
        try await loadSynthetic()

        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(
            ModuleInstance(module: SigmoidModule.self, params: .init()))
        await coordinator.commitContinuousEdit(label: "add sigmoid")
        XCTAssertEqual(historyCount(), 1, "append = exactly ONE item")

        let sigmoid = try instance("sigmoid")
        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(sigmoid, {
                $0.middleGreyContrast = 1.2 + Float(tick) * 0.05
            }, as: SigmoidModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_sigmoid"))

        XCTAssertEqual(historyCount(), 2, "drag adds exactly ONE more item")
        let committed = try instance("sigmoid")
        XCTAssertEqual(
            try committed.params(of: SigmoidModule.self).middleGreyContrast,
            1.5, accuracy: 1e-6
        )
    }

    /// Shadhi: same append+drag wiring; the algo picker keeps the Phase-5
    /// bilateral leg unreachable (gaussian stays the only live value).
    func testShadhiPanelDragCommitsOnce() async throws {
        try await loadSynthetic()

        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(
            ModuleInstance(module: ShadhiModule.self, params: .init()))
        await coordinator.commitContinuousEdit(label: "add shadhi")
        XCTAssertEqual(historyCount(), 1, "append = exactly ONE item")

        let shadhi = try instance("shadhi")
        coordinator.beginContinuousEdit()
        for tick in 1...4 {
            let record = try withParams(shadhi, {
                $0.shadows = 50 + Float(tick) * 5
            }, as: ShadhiModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_shadhi"))

        XCTAssertEqual(historyCount(), 2, "drag adds exactly ONE more item")
        let committed = try instance("shadhi")
        XCTAssertEqual(
            try committed.params(of: ShadhiModule.self).shadows, 70, accuracy: 1e-5
        )
        XCTAssertEqual(
            try committed.params(of: ShadhiModule.self).algo, .gaussian,
            "bilateral stays Phase 5 — the binding guards non-gaussian"
        )
    }

    // MARK: - 04-02 crop panel wiring (T5)

    /// Crop slider drag: 8 ticks → exactly ONE commit; the committed
    /// value is the last tick (D-H1 trio through the panel path).
    func testCropPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let crop = try instance("crop")

        coordinator.beginContinuousEdit()
        for tick in 1...8 {
            let record = try withParams(crop, { $0.left = 0.1 + Float(tick) * 0.01 }, as: CropModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_crop"))

        XCTAssertEqual(historyCount(), 1, "crop drag = exactly ONE item")
        let committed = try instance("crop")
        XCTAssertEqual(try committed.params(of: CropModule.self).left, 0.18, accuracy: 1e-6)
    }

    /// Crop double-click reset (discrete trio) restores full-frame and
    /// the paneled record decodes from the same source the overlay
    /// drives (panel/overlay同源 — the T5 acceptance).
    func testCropResetRestoresFullFrame() async throws {
        try await loadSynthetic()
        let crop = try instance("crop")

        coordinator.beginContinuousEdit()
        let up = try withParams(crop, { $0.left = 0.2; $0.top = 0.1 }, as: CropModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: String(localized: "history_crop"))
        XCTAssertEqual(historyCount(), 1)

        let current = try instance("crop")
        var reset = current
        try reset.setParams(CropModule.Params(), as: CropModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(reset)
        await coordinator.commitContinuousEdit(label: "crop reset")

        XCTAssertEqual(historyCount(), 2, "reset adds exactly ONE item")
        let after = try instance("crop")
        XCTAssertEqual(try after.params(of: CropModule.self).left, 0, accuracy: 1e-6)
        XCTAssertEqual(try after.params(of: CropModule.self).right, 1, accuracy: 1e-6)
    }

    /// Panel dispatch: crop + flip resolve a panel (flip joined in
    /// 04-08-T1 — the GUI-6 gap: parity 8/8 with no UI entry).
    func testCropPanelDispatch() throws {
        let state = InspectorState()
        state.registerDefaultProviders()

        XCTAssertTrue(state.panelOpNames.contains("crop"), "crop must dispatch a panel")
        let cropRecord = ModuleInstance(module: CropModule.self, params: .init())
        let session = InspectorEditSession(coordinator: coordinator)
        XCTAssertNotNil(state.panelView(for: cropRecord, edit: session),
                        "crop must dispatch a panel")
        XCTAssertTrue(state.panelOpNames.contains("flip"), "flip must dispatch a panel")
        let flipRecord = ModuleInstance(module: FlipModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: flipRecord, edit: session),
                        "flip must dispatch a panel")
    }

    /// Flip Picker select (discrete one-commit): none → flipH lands
    /// exactly ONE history item with the flipped orientation.
    func testFlipPanelSelectCommitsOnce() async throws {
        try await loadSynthetic()
        let flip = try instance("flip")
        XCTAssertEqual(try flip.params(of: FlipModule.self).orientation, .none)

        coordinator.beginContinuousEdit()
        let record = try withParams(flip, { $0.orientation = .flipH }, as: FlipModule.self)
        await coordinator.setLiveParams(record)
        await coordinator.commitContinuousEdit(label: String(localized: "history_flip"))

        XCTAssertEqual(historyCount(), 1, "flip select = exactly ONE item")
        let committed = try instance("flip")
        XCTAssertEqual(try committed.params(of: FlipModule.self).orientation, .flipH)
    }

    // MARK: - 04-03 ashift panel wiring (T5)

    /// Ashift slider drag: 6 ticks → exactly ONE commit; the committed
    /// value is the last tick (D-H1 trio through the panel path).
    func testAshiftPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let ashift = try instance("ashift")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(ashift, { $0.rotation = Float(tick) * 2.0 }, as: AshiftModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_ashift"))

        XCTAssertEqual(historyCount(), 1, "ashift drag = exactly ONE item")
        let committed = try instance("ashift")
        XCTAssertEqual(try committed.params(of: AshiftModule.self).rotation, 12.0, accuracy: 1e-6)
    }

    /// 04-08-T2 (GUI-8): the toast seam exists — coordinator forwards to
    /// EditorState.toast (the panel's nil/failure path calls this; the
    /// acceptance round watched the status bar, not the panel notice).
    func testToastForwardingReachesStatusBar() async throws {
        try await loadSynthetic()
        XCTAssertNil(editorState.toast, "no toast before the click")
        coordinator.presentToast("probe")
        XCTAssertEqual(editorState.toast, "probe", "toast must surface on EditorState")
    }

    /// Ashift discrete reset restores neutral + the panel dispatches.
    func testAshiftResetAndDispatch() async throws {
        try await loadSynthetic()
        XCTAssertTrue(
            editorState.instances.map(\.opName).contains("ashift"),
            "pristine seed must include ashift (neutral identity)")
        let ashift = try instance("ashift")
        XCTAssertEqual(try ashift.params(of: AshiftModule.self).rotation, 0, accuracy: 1e-6)

        coordinator.beginContinuousEdit()
        let up = try withParams(ashift, { $0.rotation = 8.0; $0.lensShiftV = 0.15 }, as: AshiftModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: String(localized: "history_ashift"))
        XCTAssertEqual(historyCount(), 1)

        let current = try instance("ashift")
        var reset = current
        try reset.setParams(AshiftModule.Params(), as: AshiftModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(reset)
        await coordinator.commitContinuousEdit(label: "ashift reset")

        XCTAssertEqual(historyCount(), 2, "reset adds exactly ONE item")
        let after = try instance("ashift")
        XCTAssertEqual(try after.params(of: AshiftModule.self).rotation, 0, accuracy: 1e-6)

        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("ashift"), "ashift must dispatch a panel")
        let session = InspectorEditSession(coordinator: coordinator)
        XCTAssertNotNil(
            state.panelView(for: ModuleInstance(module: AshiftModule.self, params: .init()), edit: session),
            "ashift must dispatch a panel")
    }
    /// 04-08-F4: perspective-fit no-change guard — a fit within epsilon of
    /// the stored params commits nothing (parity with autoLevel's 1e-4
    /// rotation guard; an empty HistoryItem would pollute stack + sidecar).
    func testPerspectiveFitNoChangeGuard() {
        let neutral = AshiftModule.Params()
        XCTAssertTrue(
            AshiftPanelView.fitIsNoChange(
                (rotation: 0, shiftV: 0, shiftH: 0, shear: 0, rms: 0), params: neutral),
            "identity fit on neutral params = no-change")
        XCTAssertFalse(
            AshiftPanelView.fitIsNoChange(
                (rotation: 0.5, shiftV: 0, shiftH: 0, shear: 0, rms: 1.2), params: neutral),
            "0.5° rotation vs neutral = change")
        var rotated = neutral
        rotated.rotation = 0.5
        XCTAssertTrue(
            AshiftPanelView.fitIsNoChange(
                (rotation: 0.50005, shiftV: 0, shiftH: 0, shear: 0, rms: 0.01), params: rotated),
            "fit within 1e-4 of stored params = no-change")
        XCTAssertFalse(
            AshiftPanelView.fitIsNoChange(
                (rotation: 0.5, shiftV: 0.01, shiftH: 0, shear: 0, rms: 0.01), params: rotated),
            "shiftV drift beyond epsilon = change")
    }

    // MARK: - 04-04 lens panel wiring (T3)

    func testLensPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let lens = try instance("lens")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(lens, { $0.distortionK1 = Float(tick) * 0.01 }, as: LensModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_lens"))

        XCTAssertEqual(historyCount(), 1, "lens drag = exactly ONE item")
        let committed = try instance("lens")
        XCTAssertEqual(try committed.params(of: LensModule.self).distortionK1, 0.06, accuracy: 1e-6)
    }

    /// Lens discrete reset + apply-match/clear source flips + dispatch.
    func testLensResetAndDispatch() async throws {
        try await loadSynthetic()
        XCTAssertTrue(
            editorState.instances.map(\.opName).contains("lens"),
            "pristine seed must include lens (neutral OFF)")
        let lens = try instance("lens")
        XCTAssertEqual(try lens.params(of: LensModule.self).distortionK1, 0, accuracy: 1e-6)

        coordinator.beginContinuousEdit()
        let up = try withParams(lens, { $0.distortionK1 = 0.05; $0.source = .manual }, as: LensModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: String(localized: "history_lens"))
        XCTAssertEqual(historyCount(), 1)

        // apply-match flips source to lensfun (resolve itself is pipe-side).
        let current = try instance("lens")
        let matched = try withParams(current, { $0.source = .lensfun }, as: LensModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(matched)
        await coordinator.commitContinuousEdit(label: "lens apply match")
        XCTAssertEqual(historyCount(), 2)
        XCTAssertEqual(try instance("lens").params(of: LensModule.self).source, .lensfun)

        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("lens"), "lens must dispatch a panel")
        let session = InspectorEditSession(coordinator: coordinator)
        XCTAssertNotNil(
            state.panelView(for: ModuleInstance(module: LensModule.self, params: .init()), edit: session),
            "lens must dispatch a panel")
    }
    // MARK: - 04-05 detail panel wiring (T5: five ops, one commit per drag)

    func testSharpenPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let sharpen = try instance("sharpen")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(sharpen, { $0.amount = Float(tick) * 0.1 }, as: SharpenModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_sharpen"))

        XCTAssertEqual(historyCount(), 1, "sharpen drag = exactly ONE item")
        let committed = try instance("sharpen")
        XCTAssertEqual(try committed.params(of: SharpenModule.self).amount, 0.6, accuracy: 1e-6)
    }

    func testLocalContrastPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let bilat = try instance("bilat")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(bilat, { $0.detail = Float(tick) * 0.2 }, as: LocalContrastModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_localcontrast"))

        XCTAssertEqual(historyCount(), 1, "local-contrast drag = exactly ONE item")
        let committed = try instance("bilat")
        XCTAssertEqual(try committed.params(of: LocalContrastModule.self).detail, 1.2, accuracy: 1e-6)
    }

    func testHighpassSoftenPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let highpass = try instance("highpass")
        XCTAssertFalse(highpass.enabled, "highpass seed is disabled (creative module)")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(highpass, { $0.contrast = 50 + Float(tick) }, as: HighpassModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_highpass"))

        XCTAssertEqual(historyCount(), 1, "highpass drag = exactly ONE item")
        let committedH = try instance("highpass")
        XCTAssertEqual(try committedH.params(of: HighpassModule.self).contrast, 56.0, accuracy: 1e-6)
        XCTAssertTrue(committedH.enabled, "04-08-T3 (GUI-7): editing a disabled module auto-enables at commit")

        let soften = try instance("soften")
        XCTAssertFalse(soften.enabled, "soften seed is disabled (creative module)")
        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let live = try withParams(soften, { $0.amount = 50 + Float(tick) * 2 }, as: SoftenModule.self)
            await coordinator.setLiveParams(live)
            // 04-08-T3 (GUI-7, D-08-T3-1): live ticks must NOT flip
            // enabled (commit-time flip only — no mid-drag cache storm).
            XCTAssertFalse(try instance("soften").enabled, "live preview keeps the stored disabled state")
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_soften"))

        XCTAssertEqual(historyCount(), 2, "soften drag = exactly ONE more item")
        let committedS = try instance("soften")
        XCTAssertEqual(try committedS.params(of: SoftenModule.self).amount, 62.0, accuracy: 1e-6)
        XCTAssertTrue(committedS.enabled, "04-08-T3 (GUI-7): editing a disabled module auto-enables at commit")
    }
    /// 04-08-T3 (GUI-7): an already-enabled module keeps enabled through
    /// the same path (no regression on the exposure round-trip).
    func testAutoEnableKeepsEnabledModuleEnabled() async throws {
        try await loadSynthetic()
        let exposure = try instance("exposure")
        XCTAssertTrue(exposure.enabled)
        coordinator.beginContinuousEdit()
        let up = try withParams(exposure, { $0.exposure = 0.7 }, as: ExposureModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: "Exposure")
        XCTAssertEqual(historyCount(), 1)
        XCTAssertTrue(try instance("exposure").enabled, "enabled module stays enabled")
    }

    /// 04-08-T4 (GUI-5): the row circle reflects the TRUE enabled state
    /// (filled = enabled, dashed = disabled), and the toggle flips it as
    /// exactly ONE history item.
    func testRowModelCircleBindsEnabled() async throws {
        try await loadSynthetic()
        let exposure = try instance("exposure")
        let highpass = try instance("highpass")
        XCTAssertEqual(
            InspectorRowModel(instance: exposure, isSelected: false).circleSymbol, "circle.fill",
            "enabled module shows the filled circle")
        XCTAssertEqual(
            InspectorRowModel(instance: highpass, isSelected: false).circleSymbol, "circle.dashed",
            "disabled module shows the hollow circle")
        // Selection must not mask the enabled shape (the GUI-5 bug).
        XCTAssertEqual(
            InspectorRowModel(instance: exposure, isSelected: true).circleSymbol, "circle.fill",
            "selected+enabled stays filled")
    }

    func testRowToggleCommitsOnce() async throws {
        try await loadSynthetic()
        let highpass = try instance("highpass")
        XCTAssertFalse(highpass.enabled)
        let toggled = InspectorRowModel.toggled(instance: highpass)
        XCTAssertTrue(toggled.enabled, "toggle flips the record")
        XCTAssertEqual(toggled.id, highpass.id, "toggle keeps instance identity")
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(toggled)
        await coordinator.commitContinuousEdit(label: String(localized: "history_toggle"))
        XCTAssertEqual(historyCount(), 1, "toggle = exactly ONE item")
        XCTAssertTrue(try instance("highpass").enabled, "toggle commit enables the module")
    }

    /// 04-08-T4 + D-08-T3-2: toggle-OFF survives the commit (the GUI-7
    /// auto-enable must not resurrect an explicit disable).
    func testRowToggleOffSurvivesCommit() async throws {
        try await loadSynthetic()
        let exposure = try instance("exposure")
        XCTAssertTrue(exposure.enabled)
        let toggled = InspectorRowModel.toggled(instance: exposure)
        XCTAssertFalse(toggled.enabled, "toggle flips the record off")
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(toggled)
        await coordinator.commitContinuousEdit(label: String(localized: "history_toggle"), autoEnable: false)
        XCTAssertEqual(historyCount(), 1, "toggle-off = exactly ONE item")
        XCTAssertFalse(try instance("exposure").enabled, "explicit toggle-off survives the commit")
    }
    /// 04-08-F3 (GUI-5 AX 通路)：AX Press 走的语义层 = toggle 纯函数 +
    /// discrete commit（autoEnable=false）。此测试钉住"按一次恰翻转一
    /// 次、恰 1 commit、render 跟随"——AX 层只负责把 Press 路由到同一
    /// onToggle（行视图侧 `.accessibilityAction(.default)` 显式绑定），
    /// 下层语义由此测试守住。
    func testRowToggleAXPressSemantics() async throws {
        try await loadSynthetic()
        // OFF → AX press → ON（恰 1 commit，render 跟随 enabled）。
        let highpass = try instance("highpass")
        XCTAssertFalse(highpass.enabled)
        XCTAssertEqual(
            InspectorRowModel(instance: highpass, isSelected: false).toggleValueKey,
            "toggle_off", "AX value announces off before the press")
        let pressed = InspectorRowModel.toggled(instance: highpass)
        let session = InspectorEditSession(coordinator: coordinator)
        await session.applyDiscreteForTest(pressed, label: String(localized: "history_toggle"))
        try await Task.sleep(for: .milliseconds(50))
        let on = try instance("highpass")
        XCTAssertTrue(on.enabled, "AX press enables the module")
        XCTAssertEqual(
            InspectorRowModel(instance: on, isSelected: false).toggleValueKey,
            "toggle_on", "AX value announces on after the press")
        XCTAssertEqual(historyCount(), 1, "one AX press = exactly ONE item")
        // ON → AX press → OFF（toggle-OFF 旁路，D-08-T3-2 不复活）。
        let pressedOff = InspectorRowModel.toggled(instance: on)
        await session.applyDiscreteForTest(pressedOff, label: String(localized: "history_toggle"), autoEnable: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(try instance("highpass").enabled, "second AX press disables again")
        XCTAssertEqual(historyCount(), 2, "second press = exactly ONE more item")
    }

    func testEqualizerPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let equalizer = try instance("equalizer")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(equalizer, { $0.g0 = Float(tick) * 0.1 }, as: EqualizerModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_equalizer"))

        XCTAssertEqual(historyCount(), 1, "equalizer drag = exactly ONE item")
        let committed = try instance("equalizer")
        XCTAssertEqual(try committed.params(of: EqualizerModule.self).g0, 0.6, accuracy: 1e-6)
    }

    /// Panel dispatch: all five detail ops resolve a panel; the seed
    /// contains sharpen/bilat/equalizer enabled-neutral + highpass/soften
    /// disabled (D11).
    func testDetailPanelDispatch() async throws {
        try await loadSynthetic()
        XCTAssertTrue(
            editorState.instances.map(\.opName).contains("sharpen"),
            "pristine seed must include sharpen (neutral)")
        XCTAssertTrue(
            editorState.instances.map(\.opName).contains("bilat"),
            "pristine seed must include bilat (neutral)")
        XCTAssertTrue(
            editorState.instances.map(\.opName).contains("equalizer"),
            "pristine seed must include equalizer (neutral)")
        let state = InspectorState()
        state.registerDefaultProviders()
        let session = InspectorEditSession(coordinator: coordinator)
        for op in ["sharpen", "bilat", "highpass", "soften", "equalizer"] {
            XCTAssertTrue(state.panelOpNames.contains(op), "\(op) must dispatch a panel")
        }
        XCTAssertNotNil(
            state.panelView(for: ModuleInstance(module: SharpenModule.self, params: .init()), edit: session),
            "sharpen must dispatch a panel")
        XCTAssertNotNil(
            state.panelView(for: ModuleInstance(module: LocalContrastModule.self, params: .init()), edit: session),
            "bilat must dispatch a panel")
        XCTAssertNotNil(
            state.panelView(for: ModuleInstance(module: HighpassModule.self, params: .init()), edit: session),
            "highpass must dispatch a panel")
        XCTAssertNotNil(
            state.panelView(for: ModuleInstance(module: SoftenModule.self, params: .init()), edit: session),
            "soften must dispatch a panel")
        XCTAssertNotNil(
            state.panelView(for: ModuleInstance(module: EqualizerModule.self, params: .init()), edit: session),
            "equalizer must dispatch a panel")
    }

    // MARK: - Helpers
    private func historyCount() -> Int { editorState.history.items.count }
}
