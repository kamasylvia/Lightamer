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
        // Plan 05-02-T4: colorbalancergb joins the seed DISABLED (D1).
        XCTAssertTrue(ops.contains("colorbalancergb"), "pristine seed must include colorbalancergb")
        // Plan 05-03-T5: the mixer trio joins the seed (channelmixerrgb
        // DISABLED like colorbalancergb; legacy + contrast ENABLED-neutral).
        XCTAssertTrue(ops.contains("channelmixerrgb"), "pristine seed must include channelmixerrgb")
        XCTAssertTrue(ops.contains("channelmixer"), "pristine seed must include channelmixer")
        XCTAssertTrue(ops.contains("colorcontrast"), "pristine seed must include colorcontrast")
        // Plan 05-04-T1/T2: vibrance + velvia + colorzones join the seed
        // ENABLED-neutral (amount/strength 0 + flat-0.5 curves ⇒ identity).
        XCTAssertTrue(ops.contains("vibrance"), "pristine seed must include vibrance")
        XCTAssertTrue(ops.contains("velvia"), "pristine seed must include velvia")
        XCTAssertTrue(ops.contains("colorzones"), "pristine seed must include colorzones")
        // Plan 05-05-T1: monochrome joins the seed DISABLED (D2: default
        // size=2 red filter is not pixel-identity).
        XCTAssertTrue(ops.contains("monochrome"), "pristine seed must include monochrome")
        // Plan 05-06-T2: nlmeans joins the seed DISABLED (D-05-06-T2-1:
        // dt ships it disabled; no zero-param identity exists).
        XCTAssertTrue(ops.contains("nlmeans"), "pristine seed must include nlmeans")
        // Plan 06-06-T2: liquify joins the seed ENABLED-neutral (empty
        // paths = the blit identity).
        XCTAssertTrue(ops.contains("liquify"), "pristine seed must include liquify")
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
        try box.apply(record)
        let madeColorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorin = try XCTUnwrap(madeColorin as? ModuleBox<ColorInModule>)
        colorin.setParams(.init())
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
        // Plan 12-5 T5: the lut3d panel (library picker + color space +
        // interpolation + hints).
        XCTAssertTrue(state.panelOpNames.contains("lut3d"), "lut3d panel registered")
        let lutRecord = ModuleInstance(module: Lut3dModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: lutRecord, edit: session),
                        "lut3d must dispatch a panel")

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

    /// GUI-13 (05-06 立案，05-07 修复) + GUI-10 同根回归：启用 commit 与
    /// 紧随的拖动 live tick 并发。旧实现 `ModuleBox.apply` 是 nonisolated
    /// async —— rematerialize 在 await 处放开 MainActor，commit 链
    /// （recordChange → fire Task → historyDidChange）与 live 链
    /// （update → setLiveParams → historyDidChange）两条链的 box 突变在
    /// cooperative 池上并发执行，同一 box 的 `paramsData`/`committedPiece`
    /// 被并发写（Data over-release → SIGSEGV/SIGABRT；取证
    /// `.work/gui-acceptance/gui10-forensics.md`）。修复 = apply/
    /// setParams/commitParams 全同步 + 物化循环零挂起点（两段式）。
    /// 本测试用 TaskGroup 把「启用 commit 链 + 变参 live tick 链」交错发射
    /// 100 轮（与崩溃报告双栈同构：recordChange 腿 + setLiveParams 腿同发），
    /// 防空转 + 断言：不崩、commit 计数精确、终态一致（修复前该序列在重复
    /// 运行/TSan 下踩窗口崩）。
    func testEnableCommitRacingLiveTicksHundredRounds() async throws {
        try await loadSynthetic()
        let seed = try instance("nlmeans")
        XCTAssertFalse(seed.enabled, "seed DISABLED — GUI-13 的原始发射形态")
        let baseCount = historyCount()

        // 预备 100 对快照（group 外构造，group 内只发射）。
        var enables: [ModuleInstance] = []
        var ticks: [ModuleInstance] = []
        enables.reserveCapacity(100)
        ticks.reserveCapacity(100)
        for tick in 0..<100 {
            var enable = seed
            enable.enabled = true
            try enable.setParams(NLMeansModule.Params(strength: 1), as: NLMeansModule.self)
            enables.append(enable)
            var dragged = seed
            dragged.enabled = true
            try dragged.setParams(
                NLMeansModule.Params(strength: 1 + Float(tick) * 0.01), as: NLMeansModule.self)
            ticks.append(dragged)
        }

        // 交错发射：每轮 = commit 链（recordChange，sync upsert + 内部
        // fire Task 渲染）+ 紧随的 live tick（setLiveParams，渲染 await 处
        // 放开 MainActor）—— 正是崩溃窗口的交错面。
        let coordinator = self.coordinator!
        let editorState = self.editorState!
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                let enable = enables[i]
                let tick = ticks[i]
                group.addTask { [coordinator, editorState] in
                    await editorState.recordChange(enable, label: "enable")
                    await coordinator.setLiveParams(tick)
                }
            }
        }

        XCTAssertEqual(historyCount() - baseCount, 100, "每轮恰 1 commit；live tick 零入史")

        // 有序终态（group 已收干，本次提交严格最后执行）。
        let final = try withParams(try instance("nlmeans"), { $0.strength = 2 }, as: NLMeansModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(final)
        await coordinator.commitContinuousEdit(label: "final")

        XCTAssertEqual(historyCount() - baseCount, 101, "终态提交恰 +1")
        let record = try instance("nlmeans")
        XCTAssertTrue(record.enabled, "终态启用保持")
        XCTAssertEqual(
            try record.params(of: NLMeansModule.self).strength, 2, accuracy: 1e-6,
            "终态参数 = 最后一次有序 tick（box/record 一致性未撕裂）")
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
    // MARK: - Plan 05-02-T4: colorbalancergb panel wiring

    /// colorbalancergb seed is DISABLED (05-02-DECISIONS D1: default
    /// params not pixel-identity); a Y-slider drag = exactly ONE item +
    /// auto-enable at commit (GUI-7); reset restores paramsHash.
    func testColorBalanceRGBPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let cb = try instance("colorbalancergb")
        XCTAssertFalse(cb.enabled, "colorbalancergb seed is disabled (D1)")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(cb, { $0.globalY = Float(tick) * 0.05 }, as: ColorBalanceRGBModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_colorbalancergb"))

        XCTAssertEqual(historyCount(), 1, "colorbalancergb drag = exactly ONE item")
        let committed = try instance("colorbalancergb")
        XCTAssertEqual(try committed.params(of: ColorBalanceRGBModule.self).globalY, 0.3, accuracy: 1e-6)
        XCTAssertTrue(committed.enabled, "editing a disabled module auto-enables at commit (GUI-7)")

        // Reset to default restores the pristine paramsHash (cache all-hit).
        let pristineHash = cb.paramsHash
        let current = try instance("colorbalancergb")
        let resetRecord = try withParams(current, { $0.globalY = 0 }, as: ColorBalanceRGBModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(resetRecord)
        await coordinator.commitContinuousEdit(label: String(localized: "history_colorbalancergb"))
        XCTAssertEqual(try instance("colorbalancergb").paramsHash, pristineHash,
                       "reset to default restores the pristine paramsHash")
    }

    /// Hue-disc drag (H+C discrete pair) = exactly ONE item; the committed
    /// (H, C) equal the last tick (discretized params assertion).
    func testColorBalanceRGBHueDiscCommitsOnce() async throws {
        try await loadSynthetic()
        let cb = try instance("colorbalancergb")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(cb, {
                $0.globalH = Float(tick) * 10
                $0.globalC = Float(tick) * 0.1
            }, as: ColorBalanceRGBModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_colorbalancergb"))

        XCTAssertEqual(historyCount(), 1, "hue-disc drag = exactly ONE item")
        let committed = try instance("colorbalancergb")
        XCTAssertEqual(try committed.params(of: ColorBalanceRGBModule.self).globalH, 60.0, accuracy: 1e-6)
        XCTAssertEqual(try committed.params(of: ColorBalanceRGBModule.self).globalC, 0.6, accuracy: 1e-6)
    }

    /// Panel dispatch: colorbalancergb resolves a panel.
    func testColorBalanceRGBPanelDispatch() async throws {
        try await loadSynthetic()
        XCTAssertTrue(
            editorState.instances.map(\.opName).contains("colorbalancergb"),
            "pristine seed must include colorbalancergb (disabled)")
        let state = InspectorState()
        state.registerDefaultProviders()
        let session = InspectorEditSession(coordinator: coordinator)
        XCTAssertTrue(state.panelOpNames.contains("colorbalancergb"), "colorbalancergb must dispatch a panel")
        XCTAssertNotNil(
            state.panelView(for: ModuleInstance(module: ColorBalanceRGBModule.self, params: .init()), edit: session),
            "colorbalancergb must dispatch a panel")
    }

        // MARK: - 05-03 mixer trio panel wiring (T5)

    /// ChannelMixerRGB red-gain drag = exactly ONE history item (D-H1 trio).
    func testChannelMixerRGBPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let cmr = try instance("channelmixerrgb")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(cmr, {
                $0.red = SIMD4<Float>(1 + Float(tick) * 0.05, 0, 0, 0)
            }, as: ChannelMixerRGBModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: "Color calibration")

        XCTAssertEqual(historyCount(), 1, "channelmixerrgb drag = exactly ONE item")
        let committed = try instance("channelmixerrgb")
        XCTAssertEqual(
            try committed.params(of: ChannelMixerRGBModule.self).red.x, 1.3, accuracy: 1e-6)
    }

    /// Legacy channelmixer green-gain drag = exactly ONE history item.
    func testChannelMixerPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let cm = try instance("channelmixer")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(cm, {
                $0.green = [0, 0, 0, 0, 1 + Float(tick) * 0.05, 0, 0]
            }, as: ChannelMixerModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: "Channel mixer")

        XCTAssertEqual(historyCount(), 1, "channelmixer drag = exactly ONE item")
        let committed = try instance("channelmixer")
        XCTAssertEqual(
            try committed.params(of: ChannelMixerModule.self).green[4], 1.3, accuracy: 1e-6)
    }

    /// ColorContrast steepness drag = exactly ONE history item.
    func testColorContrastPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let cc = try instance("colorcontrast")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(cc, {
                $0.aSteepness = 1 + Float(tick) * 0.1
            }, as: ColorContrastModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: "Color contrast")

        XCTAssertEqual(historyCount(), 1, "colorcontrast drag = exactly ONE item")
        let committed = try instance("colorcontrast")
        XCTAssertEqual(
            try committed.params(of: ColorContrastModule.self).aSteepness, 1.6, accuracy: 1e-6)
    }

    /// The three 05-03 panels dispatch by opName (D-T6 provider registry).
    func testMixerPanelsDispatch() throws {
        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("channelmixerrgb"))
        XCTAssertTrue(state.panelOpNames.contains("channelmixer"))
        XCTAssertTrue(state.panelOpNames.contains("colorcontrast"))

        let session = InspectorEditSession(coordinator: coordinator)
        let cmrRecord = ModuleInstance(module: ChannelMixerRGBModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: cmrRecord, edit: session),
                        "channelmixerrgb must dispatch a panel")
        let cmRecord = ModuleInstance(module: ChannelMixerModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: cmRecord, edit: session),
                        "channelmixer must dispatch a panel")
        let ccRecord = ModuleInstance(module: ColorContrastModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: ccRecord, edit: session),
                        "colorcontrast must dispatch a panel")
    }

    // MARK: - 05-04 panels (vibrance + velvia + colorzones)

    /// Vibrance amount drag = exactly ONE history item.
    func testVibrancePanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let vib = try instance("vibrance")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(vib, {
                $0.amount = Float(tick) * 10
            }, as: VibranceModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: "Vibrance")

        XCTAssertEqual(historyCount(), 1, "vibrance drag = exactly ONE item")
        let committed = try instance("vibrance")
        XCTAssertEqual(
            try committed.params(of: VibranceModule.self).amount, 60, accuracy: 1e-6)
    }

    /// Velvia strength drag = exactly ONE history item.
    func testVelviaPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let vel = try instance("velvia")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(vel, {
                $0.strength = Float(tick) * 10
            }, as: VelviaModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: "Velvia")

        XCTAssertEqual(historyCount(), 1, "velvia drag = exactly ONE item")
        let committed = try instance("velvia")
        XCTAssertEqual(
            try committed.params(of: VelviaModule.self).strength, 60, accuracy: 1e-6)
    }

    /// ColorZones hue-node drag = exactly ONE history item (curve
    /// discretization into params — the node set change must flow through
    /// the same D-H1 trio as sliders).
    func testColorZonesPanelDragCommitsOnce() async throws {
        try await loadSynthetic()
        let cz = try instance("colorzones")
        let baseHash = cz.paramsHash

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            var params = try cz.params(of: ColorZonesModule.self)
            params.curveH = [
                .init(x: 0.25, y: 0.5),
                .init(x: 0.5, y: 0.5 + Float(tick) * 0.05),
            ]
            var record = cz
            try record.setParams(params, as: ColorZonesModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: "Color zones")

        XCTAssertEqual(historyCount(), 1, "colorzones drag = exactly ONE item")
        let committed = try instance("colorzones")
        XCTAssertNotEqual(committed.paramsHash, baseHash, "curve drag must change params")
        XCTAssertEqual(
            try committed.params(of: ColorZonesModule.self).curveH[1].y,
            0.8, accuracy: 1e-6)
    }

    /// Vibrance reset-to-zero reproduces the seed paramsHash (cache all-hit).
    func testVibranceResetRestoresSeedHash() async throws {
        try await loadSynthetic()
        let vib = try instance("vibrance")
        let seedHash = vib.paramsHash

        let up = try withParams(vib, { $0.amount = 60 }, as: VibranceModule.self)
        await coordinator.setLiveParams(up)
        await coordinator.commitContinuousEdit(label: "Vibrance up")
        XCTAssertNotEqual(try instance("vibrance").paramsHash, seedHash)

        let current = try instance("vibrance")
        let reset = try withParams(current, { $0.amount = 0 }, as: VibranceModule.self)
        await coordinator.setLiveParams(reset)
        await coordinator.commitContinuousEdit(label: "Vibrance reset")
        XCTAssertEqual(try instance("vibrance").paramsHash, seedHash,
            "reset to zero must reproduce the SEED paramsHash (cache all-hit)")
    }

    // MARK: - 06-06-T4 liquify panel wiring

    /// Liquify node edit (the overlay's params flow — the same D-H1 trio):
    /// a warp-type switch + strength drag land as exactly ONE commit with
    /// the last tick's values.
    func testLiquifyPanelNodeEditCommitsOnce() async throws {
        try await loadSynthetic()
        let liquify = try instance("liquify")
        XCTAssertTrue(liquify.enabled, "liquify seed is ENABLED-neutral")
        XCTAssertEqual(try liquify.params(of: LiquifyModule.self).paths.count, 0,
                       "empty paths = the cache-neutral seed")

        // A node edit (the overlay/panel both produce this record shape):
        // radial-grow stamp + a 6-tick strength drag → exactly ONE item.
        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            var params = try liquify.params(of: LiquifyModule.self)
            params.paths = [LiquifyPathData(
                type: .moveTo, warpType: .radialGrow,
                point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.5 + Float(tick) * 0.01, 0.5),
                radius: SIMD2(0.6, 0.5))]
            var record = liquify
            try record.setParams(params, as: LiquifyModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_liquify"))

        XCTAssertEqual(historyCount(), 1, "liquify drag = exactly ONE item")
        let committed = try instance("liquify")
        let committedParams = try committed.params(of: LiquifyModule.self)
        XCTAssertEqual(committedParams.paths.count, 1)
        XCTAssertEqual(committedParams.paths[0].strength.x, 0.56, accuracy: 1e-6,
                       "newest tick wins")
        XCTAssertTrue(committedParams.paths[0].strength != committedParams.paths[0].point,
                      "the node is a real (non-neutral) warp")
    }

    /// Panel dispatch: liquify resolves a panel (the seed instance's empty
    /// paths keep the pristine render cache-neutral).
    func testLiquifyPanelDispatch() throws {
        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("liquify"),
                      "liquify must dispatch a panel")
        let session = InspectorEditSession(coordinator: coordinator)
        XCTAssertNotNil(
            state.panelView(for: ModuleInstance(module: LiquifyModule.self, params: .init()),
                            edit: session),
            "liquify must dispatch a panel view")
    }

    /// The three 05-04 panels dispatch by opName (D-T6 provider registry).
    func testColorZonesPanelsDispatch() throws {
        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("vibrance"))
        XCTAssertTrue(state.panelOpNames.contains("velvia"))
        XCTAssertTrue(state.panelOpNames.contains("colorzones"))

        let session = InspectorEditSession(coordinator: coordinator)
        let vibRecord = ModuleInstance(module: VibranceModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: vibRecord, edit: session),
                        "vibrance must dispatch a panel")
        let velRecord = ModuleInstance(module: VelviaModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: velRecord, edit: session),
                        "velvia must dispatch a panel")
        let czRecord = ModuleInstance(module: ColorZonesModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: czRecord, edit: session),
                        "colorzones must dispatch a panel")
    }

    /// Monochrome wheel click (a/b pair) = exactly ONE history item; the
    /// committed (a, b) equal the last tick (discretized params assertion —
    /// plan T4 色轮点击=恰 1 commit).
    func testMonochromeWheelCommitsOnce() async throws {
        try await loadSynthetic()
        let mono = try instance("monochrome")
        XCTAssertFalse(mono.enabled, "monochrome seed is disabled (D2)")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(mono, {
                $0.a = Float(tick) * 10
                $0.b = Float(tick) * -10
            }, as: MonochromeModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_monochrome"))

        XCTAssertEqual(historyCount(), 1, "wheel drag = exactly ONE item")
        let committed = try instance("monochrome")
        XCTAssertEqual(try committed.params(of: MonochromeModule.self).a, 60.0, accuracy: 1e-6)
        XCTAssertEqual(try committed.params(of: MonochromeModule.self).b, -60.0, accuracy: 1e-6)
        XCTAssertTrue(committed.enabled, "editing a disabled module auto-enables at commit (GUI-7)")

        // Reset to default restores the pristine paramsHash (cache all-hit).
        let pristineHash = mono.paramsHash
        let current = try instance("monochrome")
        let resetRecord = try withParams(current, {
            $0.a = 0; $0.b = 0; $0.size = 2; $0.highlights = 0
        }, as: MonochromeModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(resetRecord)
        await coordinator.commitContinuousEdit(label: String(localized: "history_monochrome"))
        XCTAssertEqual(try instance("monochrome").paramsHash, pristineHash,
                       "reset to default restores the pristine paramsHash")
    }

    /// Monochrome size-slider drag = exactly ONE history item.
    func testMonochromeSizeSliderCommitsOnce() async throws {
        try await loadSynthetic()
        let mono = try instance("monochrome")

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(mono, {
                $0.size = 0.5 + Float(tick) * 0.1
            }, as: MonochromeModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_monochrome"))

        XCTAssertEqual(historyCount(), 1, "size drag = exactly ONE item")
        let committed = try instance("monochrome")
        XCTAssertEqual(try committed.params(of: MonochromeModule.self).size, 1.1, accuracy: 1e-6)
    }

    /// Monochrome panel dispatches by opName (D-T6 provider registry).
    func testMonochromePanelDispatch() throws {
        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("monochrome"))
        let session = InspectorEditSession(coordinator: coordinator)
        let record = ModuleInstance(module: MonochromeModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: record, edit: session),
                        "monochrome must dispatch a panel")
    }

    /// Plan 05-06-T5: nlmeans panel dispatches by opName (D-T6).
    func testNLMeansPanelDispatch() throws {
        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("nlmeans"))
        let session = InspectorEditSession(coordinator: coordinator)
        let record = ModuleInstance(module: NLMeansModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: record, edit: session),
                        "nlmeans must dispatch a panel")
    }

    /// Plan 05-06-T5: nlmeans strength-slider drag = exactly ONE history
    /// item; reset to default restores the pristine paramsHash (cache
    /// all-hit); editing the disabled seed auto-enables at commit (GUI-7).
    func testNLMeansStrengthSliderCommitsOnce() async throws {
        try await loadSynthetic()
        let nl = try instance("nlmeans")
        XCTAssertFalse(nl.enabled, "nlmeans seed is disabled (D-05-06-T2-1)")
        let pristineHash = nl.paramsHash

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(nl, {
                $0.strength = Float(tick) * 10
            }, as: NLMeansModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_nlmeans"))

        XCTAssertEqual(historyCount(), 1, "strength drag = exactly ONE item")
        let committed = try instance("nlmeans")
        XCTAssertEqual(try committed.params(of: NLMeansModule.self).strength, 60.0, accuracy: 1e-6)
        XCTAssertTrue(committed.enabled, "editing a disabled module auto-enables at commit (GUI-7)")

        // Reset to default restores the pristine paramsHash (cache all-hit).
        let current = try instance("nlmeans")
        let resetRecord = try withParams(current, {
            $0.radius = 2; $0.strength = 50; $0.luma = 0.5; $0.chroma = 1
        }, as: NLMeansModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(resetRecord)
        await coordinator.commitContinuousEdit(label: String(localized: "history_nlmeans"))
        XCTAssertEqual(try instance("nlmeans").paramsHash, pristineHash,
                       "reset to default restores the pristine paramsHash")
    }

    // MARK: - 05-08 bilateral panel wiring (T4)

    /// InspectorState dispatches the bilateral panel by opName.
    func testBilateralPanelDispatch() throws {
        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("bilateral"))
        let session = InspectorEditSession(coordinator: coordinator)
        let record = ModuleInstance(module: BilateralModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: record, edit: session),
                        "bilateral must dispatch a panel")
    }

    /// Plan 05-08-T4: bilateral radius-slider drag = exactly ONE history
    /// item; reset to default restores the pristine paramsHash (cache
    /// all-hit); editing the disabled seed auto-enables at commit (GUI-7).
    func testBilateralRadiusSliderCommitsOnce() async throws {
        try await loadSynthetic()
        let bl = try instance("bilateral")
        XCTAssertFalse(bl.enabled, "bilateral seed is disabled (D-05-08-T1-3)")
        let pristineHash = bl.paramsHash

        coordinator.beginContinuousEdit()
        for tick in 1...6 {
            let record = try withParams(bl, {
                $0.radius = 1 + Float(tick) * 2
            }, as: BilateralModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(label: String(localized: "history_bilateral"))

        XCTAssertEqual(historyCount(), 1, "radius drag = exactly ONE item")
        let committed = try instance("bilateral")
        XCTAssertEqual(try committed.params(of: BilateralModule.self).radius, 13.0, accuracy: 1e-6)
        XCTAssertTrue(committed.enabled, "editing a disabled module auto-enables at commit (GUI-7)")

        // Reset to default restores the pristine paramsHash (cache all-hit).
        let current = try instance("bilateral")
        let resetRecord = try withParams(current, {
            $0.radius = 15; $0.reserved = 15; $0.red = 0.005; $0.green = 0.005; $0.blue = 0.005
        }, as: BilateralModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(resetRecord)
        await coordinator.commitContinuousEdit(label: String(localized: "history_bilateral"))
        XCTAssertEqual(try instance("bilateral").paramsHash, pristineHash,
                       "reset to default restores the pristine paramsHash")
    }

    // MARK: - 05-07 denoiseprofile panel wiring (T6)

    /// DenoiseProfile: seeded DISABLED (D-05-07-T2-2); a slider drag = ONE
    /// commit (auto-enable at commit per GUI-7); the mode Picker and the
    /// profile-row source flip are DISCRETE single commits; reset restores
    /// the pristine paramsHash (cache all-hit).
    func testDenoiseProfilePanelDragAndDiscreteCommits() async throws {
        try await loadSynthetic()
        let dp = try instance("denoiseprofile")
        XCTAssertFalse(dp.enabled, "denoiseprofile seed is disabled (D-05-07-T2-2)")
        let pristineHash = dp.paramsHash

        // Slider drag (strength): 4 ticks → exactly ONE commit.
        coordinator.beginContinuousEdit()
        for tick in 1...4 {
            let record = try withParams(dp, {
                $0.strength = 1 + Float(tick) * 0.25
            }, as: DenoiseProfileModule.self)
            await coordinator.setLiveParams(record)
        }
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_denoiseprofile"))
        XCTAssertEqual(historyCount(), 1, "strength drag = exactly ONE item")
        let dragged = try instance("denoiseprofile")
        XCTAssertEqual(
            try dragged.params(of: DenoiseProfileModule.self).strength,
            2.0, accuracy: 1e-6)
        XCTAssertTrue(dragged.enabled, "editing auto-enables at commit (GUI-7)")

        // Mode Picker flip = ONE discrete commit.
        let afterDrag = try instance("denoiseprofile")
        let modeRecord = try withParams(afterDrag, {
            $0.mode = .nlmeans
        }, as: DenoiseProfileModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(modeRecord)
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_denoiseprofile"))
        XCTAssertEqual(historyCount(), 2, "mode flip = exactly ONE more item")
        XCTAssertEqual(
            try instance("denoiseprofile").params(of: DenoiseProfileModule.self).mode,
            .nlmeans)

        // Profile-row source flip (Auto → generic concrete) = ONE commit.
        let afterMode = try instance("denoiseprofile")
        let genericRecord = try withParams(afterMode, {
            $0.a = SIMD3(repeating: 1e-4)
            $0.b = SIMD3(repeating: 0)
            $0.isoOverride = nil
        }, as: DenoiseProfileModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(genericRecord)
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_denoiseprofile"))
        XCTAssertEqual(historyCount(), 3, "profile flip = exactly ONE more item")
        XCTAssertEqual(
            try instance("denoiseprofile").params(of: DenoiseProfileModule.self).a.x,
            1e-4, accuracy: 1e-12)

        // Reset to defaults restores the pristine paramsHash.
        let current = try instance("denoiseprofile")
        let resetRecord = try withParams(current, {
            $0 = DenoiseProfileModule.Params()
        }, as: DenoiseProfileModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(resetRecord)
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_denoiseprofile"))
        XCTAssertEqual(try instance("denoiseprofile").paramsHash, pristineHash,
                       "reset restores the pristine paramsHash")
    }
    // MARK: - Helpers
    private func historyCount() -> Int { editorState.history.items.count }

    // MARK: - 07-3 T3: the skinSmooth panel (the 25TH panel)

    /// InspectorState dispatches the skinSmooth panel by opName.
    func testSkinSmoothPanelDispatch() throws {
        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("skinSmooth"), "the 25TH panel registered")
        let session = InspectorEditSession(coordinator: coordinator)
        let record = ModuleInstance(module: SkinSmoothModule.self, params: .init())
        XCTAssertNotNil(state.panelView(for: record, edit: session),
                        "skinSmooth must dispatch a panel")
    }

    /// The layer-scope D-H1 drag: N live ticks + ONE `layerScope`-型
    /// commit; undo restores the neutral seed strength (cache all-hit).
    func testSkinSmoothLayerScopeDragCommitsOnceAndUndoRestores() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        let template = try instance("skinSmooth")
        let record = try XCTUnwrap(
            editorState.addModuleToLayer(layerID: layer.id, template: template))
        let afterAdd = editorState.history.items.count

        // The panel trio in the LAYER scope (the sliders' session shape).
        coordinator.beginContinuousEdit()
        for tick in 1...5 {
            let edited = try withParams(record, {
                $0.strength = Float(tick) * 0.2
            }, as: SkinSmoothModule.self)
            await coordinator.setLiveParams(edited, layerID: layer.id)
        }
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_skinsmooth"), layerScope: layer.id)

        XCTAssertEqual(editorState.history.items.count - afterAdd, 1,
                       "the strength drag = exactly ONE layerScope item")
        let chainRecord = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)?.chain.first)
        XCTAssertEqual(
            try chainRecord.params(of: SkinSmoothModule.self).strength, 1.0, accuracy: 1e-6)
        XCTAssertTrue(chainRecord.enabled, "editing auto-enables at commit (GUI-7)")

        // Undo restores the neutral seed (strength 0).
        await coordinator.undo()
        let reverted = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)?.chain.first)
        XCTAssertEqual(
            try reverted.params(of: SkinSmoothModule.self).strength, 0.0, accuracy: 1e-6,
            "undo restores the neutral strength")
    }

    /// The「定位皮肤」commit channel: the skin mask bakes to the SELECTED
    /// layer's mask slot as exactly ONE stackSnapshot item with the
    /// ai-skin file identity (the inference itself is GUI-round Manual-
    /// Only — this pins the state-level commit leg both paths share).
    func testSkinLocateCommitWritesMaskSlotOneCommit() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        let editing = LayerEditingState()
        editing.select(layer.id)
        let afterAdd = editorState.history.items.count

        let plane = AIMaskPlane(
            width: 16, height: 16,
            floats: (0..<256).map { $0 % 16 < 10 ? Float(1.0) : Float(0.0) })
        let ref = try await AIMaskEditing.commitRasterMask(
            plane: plane, source: .skin,
            imageURL: tempDirectory,
            label: String(localized: "history_ai_mask"),
            coordinator: coordinator, editorState: editorState,
            editingState: editing, metal: metal)

        XCTAssertEqual(editorState.history.items.count - afterAdd, 1,
                       "the locate bake = exactly ONE stackSnapshot item")
        let mask = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)?.mask)
        XCTAssertEqual(mask.raster?.fileName, ref.fileName)
        XCTAssertTrue(ref.fileName.hasPrefix("ai-skin-"), "the ai-skin identity prefix")
    }

    /// The enablement-chain CONTENT direction (防空转): an ENABLED
    /// skinSmooth (strength > 0) on a high-frequency plate must render
    /// DIFFERENT bytes from the disabled chain — the 07-2 轨 B pinned the
    /// identity leg (a=0 byte-identical); this pins the enabled leg > 0.
    func testSkinSmoothEnabledCompositeDiffersFromDisabled() async throws {
        // The skinSmooth KERNEL (not the blit) — register the IOP metallib.
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let image = try makeStripedSyntheticImage()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        func run(_ enabled: Bool) async throws -> [UInt8] {
            let record = ModuleInstance(
                module: SkinSmoothModule.self,
                params: SkinSmoothModule.Params(
                    radius: 8, strength: 0.9, detailPreserve: 0.02))
            var enabledRecord = record
            enabledRecord.enabled = enabled
            let layer = AdjustmentLayer(name: "skin", chain: [enabledRecord])
            var stack = LayerStack(baseLayer: BackgroundLayer())
            stack.addAdjustment(layer)
            let run = try await LayerCompositeDriver.composite(
                image: image, imageID: UUID(), baseInstances: base,
                layerStack: stack, registry: registry,
                resolution: .preview, cache: PipeCache(), metal: metal,
                longEdge: nil, policy: .preview)
            return Self.readDisplayBytes(run.output, metal: metal)
        }

        let disabled = try await run(false)
        let enabled = try await run(true)
        let differing = zip(disabled, enabled).filter { $0 != $1 }.count
        XCTAssertGreaterThan(differing, 0,
                             "enabled skinSmooth must change the render (content-level, 防空转)")
    }

    /// GUI-21 (07-3 acceptance round): skinSmooth on the GLOBAL (base)
    /// chain — the panel trio (live ticks + one commit) must CHANGE the
    /// rendered display. The acceptance round observed viewport max|Δ|=0
    /// with the commits present in history/sidecar (data in, pixels
    /// frozen). Root cause (fixed in LayerCompositeDriver): the terminal
    /// segment's cache lines seeded on the bare decode hash — blind to
    /// the composite accumulator — so any upstream content edit stale-HIT
    /// and the render returned the OLD display plane. This repro drives
    /// the coordinator legs end-to-end (load → composite stack → trio →
    /// display bytes).
    func testSkinSmoothGlobalChainCommitChangesDisplay() async throws {
        // The striped plate (low-amplitude high-frequency — the enabled
        // leg's visible surface; a flat plate is identity #3's no-op).
        let url = tempDirectory.appendingPathComponent("skin-global.exr")
        try await coordinator.load(
            url: url, decoded: makeStripedSyntheticImage(), instances: [], metal: metal
        )

        // Force the COMPOSITE branch (the acceptance stack carried
        // adjustment layers): one layer, no mask.
        _ = editorState.addAdjustmentLayer()
        await coordinator.layerStackDidChange(persist: false)

        let before = try XCTUnwrap(editorState.displayTexture, "display exists after load")
        let beforeBytes = Self.readDisplayBytes(before, metal: metal)

        // The panel trio on the GLOBAL record (layerScope nil — the base
        // row selected, the skinSmooth panel sliders).
        let skin = try instance("skinSmooth")
        coordinator.beginContinuousEdit()
        let edited = try withParams(skin, {
            $0.strength = 0.8
            $0.radius = 32
        }, as: SkinSmoothModule.self)
        await coordinator.setLiveParams(edited)
        await coordinator.commitContinuousEdit(label: String(localized: "history_skinsmooth"))
        // recordChange's notify is a fire-and-forget Task; drive the same
        // post-commit pass deterministically, then settle for the Task's
        // own duplicate pass to land before the read.
        await coordinator.historyDidChange()
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<10 { await Task.yield() }

        let committed = try instance("skinSmooth")
        XCTAssertEqual(
            try committed.params(of: SkinSmoothModule.self).strength, 0.8, accuracy: 1e-6,
            "the commit landed in the live record")

        let after = try XCTUnwrap(editorState.displayTexture, "display survives the commit")
        let afterBytes = Self.readDisplayBytes(after, metal: metal)
        XCTAssertEqual(beforeBytes.count, afterBytes.count, "same plane geometry")
        let differing = zip(beforeBytes, afterBytes).filter { $0 != $1 }.count
        XCTAssertGreaterThan(
            differing, 0,
            "GUI-21: the global-chain skinSmooth commit must change the display pixels")
    }

    /// GUI-21 control twin: a GLOBAL exposure commit under the same
    /// layered stack — the same terminal-staleness seam (the acceptance
    /// round only caught it via skinSmooth; ANY base-chain param edit
    /// froze the viewport while adjustment layers existed).
    func testGlobalExposureCommitUnderLayersChangesDisplay() async throws {
        let url = tempDirectory.appendingPathComponent("exposure-global.exr")
        try await coordinator.load(
            url: url, decoded: makeStripedSyntheticImage(), instances: [], metal: metal
        )
        _ = editorState.addAdjustmentLayer()
        await coordinator.layerStackDidChange(persist: false)

        let before = try XCTUnwrap(editorState.displayTexture)
        let beforeBytes = Self.readDisplayBytes(before, metal: metal)

        let exposure = try instance("exposure")
        coordinator.beginContinuousEdit()
        let edited = try withParams(exposure, { $0.exposure = 1.0 }, as: ExposureModule.self)
        await coordinator.setLiveParams(edited)
        await coordinator.commitContinuousEdit(label: "Exposure")
        await coordinator.historyDidChange()
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<10 { await Task.yield() }

        let after = try XCTUnwrap(editorState.displayTexture)
        let afterBytes = Self.readDisplayBytes(after, metal: metal)
        let differing = zip(beforeBytes, afterBytes).filter { $0 != $1 }.count
        XCTAssertGreaterThan(
            differing, 0,
            "GUI-21 twin: a global exposure commit under layers must change the display")
    }

    /// GUI-19 (07-3 acceptance round): `addModuleToLayer` must INVALIDATE
    /// `layerStack` observers. `AdjustmentLayer` is a class — the in-place
    /// chain append updated the data (sidecar/history carried the module)
    /// but never tripped @Observable, so the Inspector's layer-chain list
    /// never re-rendered and the row was missing. Pinned with
    /// `withObservationTracking` (the same mechanism SwiftUI reads through).
    func testAddModuleToLayerTripsLayerStackObservation() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())

        // A class box — the onChange closure is @Sendable (Swift 6 rejects
        // direct var capture mutation).
        final class FlagBox: @unchecked Sendable { var value = false }
        let flag = FlagBox()
        withObservationTracking {
            _ = editorState.adjustmentLayer(id: layer.id)?.chain.count
        } onChange: {
            flag.value = true
        }

        let template = try instance("skinSmooth")
        let record = try XCTUnwrap(
            editorState.addModuleToLayer(layerID: layer.id, template: template))
        XCTAssertTrue(
            flag.value,
            "GUI-19: the chain append must reassign layerStack (the @Observable atom)")
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.chain.first?.id, record.id,
            "the record landed in the live chain")
    }

    /// GUI-20 (07-3 acceptance, 2026-09-24): a download that returns
    /// WITHOUT an error but leaves the assets not-ready must surface the
    /// explanatory notice (the acceptance round fell back to the silent
    /// needsDownload guidance state — the user pressed「下载模型」and
    /// nothing was said). Pinned at the App model layer with a scripted
    /// no-error downloader + notReady probe (the exact 07-1 test-
    /// entitlement signature).
    @MainActor
    func testNoErrorNotReadyDownloadSurfacesNotice() async throws {
        let store = AIAssetStore(
            statusProbe: { .notReady },
            downloader: { _ in }) // "succeeds" without provisioning
        let model = AIDownloadModel(store: store)
        model.accept() // the guided download entry's action
        // Let the poll task run to completion (the notReady loop exits
        // immediately — no downloading phase to poll).
        for _ in 0..<50 {
            if model.downloadError != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotNil(
            model.downloadError,
            "GUI-20: the no-error-not-provisioned download must NOT be silent")
    }

    /// L014-fenced display read-back (SYNC helper — waitUntilCompleted is
    /// unavailable from async contexts; the RasterMaskStore pattern).
    nonisolated private static func readDisplayBytes(
        _ texture: any MTLTexture, metal: MetalContext
    ) -> [UInt8] {
        let fenceBuffer = metal.commandQueue.makeCommandBuffer()
        fenceBuffer?.commit()
        fenceBuffer?.waitUntilCompleted()
        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: w * 4,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return bytes
    }

    /// A LOW-amplitude high-frequency plate (blemish-scale: ±0.01 ripple
    /// well below the t=0.02 preserve threshold — the attenuation leg the
    /// enabled module must show; a large-amplitude plate would be ANOTHER
    /// vacuous check, the preserve leg passes strong highs by design, and
    /// a flat field is identity triple #3's no-op).
    private func makeStripedSyntheticImage() throws -> DecodedImage {
        let width = 64, height = 64
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let v: Float = 0.4 + ((x + y) % 4 < 2 ? 0.01 : -0.01)
                rgba[i * 4 + 0] = v
                rgba[i * 4 + 1] = v
                rgba[i * 4 + 2] = v
                rgba[i * 4 + 3] = 1.0
            }
        }
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

    // ── Plan 08-2 T6: the watermark panel section ──

    func testYiyinPanelDispatch() throws {
        let state = InspectorState()
        state.registerDefaultProviders()
        XCTAssertTrue(state.panelOpNames.contains("watermark"),
                      "the 印框/水印 panel registered")
        // Plan 08-3 T1: the SAME dual-section panel dispatches for the
        // borders row too (one provider pair, one view).
        XCTAssertTrue(state.panelOpNames.contains("borders"),
                      "the borders row dispatches the dual-section panel")
        let session = InspectorEditSession(coordinator: coordinator)
        let record = ModuleInstance(module: WatermarkModule.self, params: .neutralSeed)
        XCTAssertNotNil(state.panelView(for: record, edit: session),
                        "watermark must dispatch a panel")
        let bordersRecord = ModuleInstance(module: BordersModule.self, params: .neutralSeed)
        XCTAssertNotNil(state.panelView(for: bordersRecord, edit: session),
                        "borders must dispatch the same panel")
        // L010: the stable identifiers — the panel row ids address template
        // KEYS, never indices (asserted at the params level: the seed
        // carries the system catalog keys the panel rows address).
        let seed = WatermarkModule.Params.neutralSeed
        XCTAssertTrue(seed.templates.contains { $0.key == "make-model" })
        XCTAssertTrue(seed.templates.allSatisfy { !$0.key.isEmpty })
    }

    // ── Plan 08-3 T1: the borders section + dual-instance coordination ──

    func testYiyinBordersSliderCommitsOnceAndUndoRestores() async throws {
        try await loadSynthetic()
        let record = try instance("borders")
        let afterLoad = editorState.history.items.count
        let seedRate = try record.params(of: BordersModule.self).mainImageWidthRate

        // The mainImageWidthRate drag trio (the LightamerSlider mapping —
        // the panel's yiyin.main_img_w_rate slider): N live ticks + exactly
        // ONE commit at drag end (D-H1), landing on the BORDERS record.
        coordinator.beginContinuousEdit()
        for tick in 1...5 {
            let edited = try withParams(record, {
                $0.mainImageWidthRate = 90 + Double(tick)
            }, as: BordersModule.self)
            await coordinator.setLiveParams(edited)
        }
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_yiyin_borders"))

        XCTAssertEqual(editorState.history.items.count - afterLoad, 1,
                       "the rate drag = exactly ONE commit")
        let committed = try instance("borders")
        XCTAssertEqual(
            try committed.params(of: BordersModule.self).mainImageWidthRate, 95,
            accuracy: 1e-6)

        // Undo restores the neutral seed face.
        await coordinator.undo()
        let reverted = try instance("borders")
        XCTAssertEqual(
            try reverted.params(of: BordersModule.self).mainImageWidthRate, seedRate,
            accuracy: 1e-6, "undo restores the seed rate")
    }

    func testYiyinBordersDiscreteAspectToggleCommitsOnce() async throws {
        try await loadSynthetic()
        let record = try instance("borders")
        let afterLoad = editorState.history.items.count

        // The landscape toggle (discrete face): ONE commit.
        var params = try record.params(of: BordersModule.self)
        params.landscapeOutput = true
        var withLandscape = record
        try withLandscape.setParams(params, as: BordersModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(withLandscape)
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_yiyin_borders"))
        XCTAssertEqual(editorState.history.items.count - afterLoad, 1)

        // The aspect picker (discrete face): ONE commit — the PANEL mirrors
        // the yiyin onBGRateChange mutual exclusion (aspect + landscape are
        // never sent together; the render-side backstop is the module
        // clamp, asserted below).
        params = try instance("borders").params(of: BordersModule.self)
        params.aspectRatio = BordersModule.AspectRatio(w: 3, h: 2)
        params.landscapeOutput = false
        var withAspect = try instance("borders")
        try withAspect.setParams(params, as: BordersModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(withAspect)
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_yiyin_borders"))
        XCTAssertEqual(editorState.history.items.count - afterLoad, 2)

        let after = try instance("borders")
        let committed = try after.params(of: BordersModule.self)
        XCTAssertNotNil(committed.aspectRatio)
        XCTAssertFalse(committed.landscapeOutput)
        // The module-level backstop: the commit clamp force-clears
        // landscape whenever an aspect is set (render defense).
        var inconsistent = committed
        inconsistent.landscapeOutput = true
        XCTAssertFalse(BordersModule.clamp(inconsistent).landscapeOutput,
                       "the clamp force-clears landscape under an aspect")
    }

    /// The dual-instance interleaving contract (D-08-3-T1-1): a borders
    /// edit and a watermark edit land as TWO separate commits (one per
    /// touched instance), and ⌘Z reverts them one at a time — each
    /// instance's params restore independently.
    func testYiyinDualInstanceInterleavedCommitsAndUndo() async throws {
        try await loadSynthetic()
        let bordersRecord = try instance("borders")
        let watermarkRecord = try instance("watermark")
        let afterLoad = editorState.history.items.count
        let seedRate = try bordersRecord.params(of: BordersModule.self).mainImageWidthRate
        let seedSpacing = try watermarkRecord.params(of: WatermarkModule.self).lineSpacing

        // A: edit borders (rate 95) — exactly ONE commit.
        var edited = try withParams(bordersRecord, {
            $0.mainImageWidthRate = 95
        }, as: BordersModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(edited)
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_yiyin_borders"))
        XCTAssertEqual(editorState.history.items.count - afterLoad, 1,
                       "the borders edit = its own commit")

        // B: edit watermark (lineSpacing 1.2) — ANOTHER commit.
        edited = try withParams(watermarkRecord, {
            $0.lineSpacing = 1.2
        }, as: WatermarkModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(edited)
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_yiyin_watermark"))
        XCTAssertEqual(editorState.history.items.count - afterLoad, 2,
                       "the watermark edit = its own commit")

        // Sanity: BOTH instances carry their edits simultaneously.
        XCTAssertEqual(
            try instance("borders").params(of: BordersModule.self).mainImageWidthRate,
            95, accuracy: 1e-6)
        XCTAssertEqual(
            try instance("watermark").params(of: WatermarkModule.self).lineSpacing,
            1.2, accuracy: 1e-6)

        // ⌘Z #1 reverts the LAST edit (watermark); borders stays edited.
        await coordinator.undo()
        XCTAssertEqual(
            try instance("watermark").params(of: WatermarkModule.self).lineSpacing,
            seedSpacing, accuracy: 1e-6, "undo #1 reverts the watermark tick")
        XCTAssertEqual(
            try instance("borders").params(of: BordersModule.self).mainImageWidthRate,
            95, accuracy: 1e-6, "undo #1 leaves the borders edit intact")

        // ⌘Z #2 reverts the borders edit.
        await coordinator.undo()
        XCTAssertEqual(
            try instance("borders").params(of: BordersModule.self).mainImageWidthRate,
            seedRate, accuracy: 1e-6, "undo #2 reverts the borders tick")
    }

    func testYiyinWatermarkSliderCommitsOnceAndUndoRestores() async throws {
        try await loadSynthetic()
        let record = try instance("watermark")
        let afterLoad = editorState.history.items.count
        let seedOpacity = try record.params(of: WatermarkModule.self).logoOpacity

        // The logoOpacity drag trio (the LightamerSlider mapping): N live
        // ticks + exactly ONE commit at drag end (D-H1).
        coordinator.beginContinuousEdit()
        for tick in 1...5 {
            let edited = try withParams(record, {
                $0.logoOpacity = Double(tick) * 0.2
            }, as: WatermarkModule.self)
            await coordinator.setLiveParams(edited)
        }
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_yiyin_watermark"))

        XCTAssertEqual(editorState.history.items.count - afterLoad, 1,
                       "the opacity drag = exactly ONE commit")
        let committed = try instance("watermark")
        XCTAssertEqual(
            try committed.params(of: WatermarkModule.self).logoOpacity, 1.0, accuracy: 1e-6)

        // Undo restores the seed face.
        await coordinator.undo()
        let reverted = try instance("watermark")
        XCTAssertEqual(
            try reverted.params(of: WatermarkModule.self).logoOpacity, seedOpacity,
            accuracy: 1e-6, "undo restores the seed opacity")
    }

    func testYiyinTemplateToggleAndDeleteCommitDiscretely() async throws {
        try await loadSynthetic()
        var record = try instance("watermark")
        let afterLoad = editorState.history.items.count

        // A template use-toggle = ONE discrete commit (the compressed trio).
        var params = try record.params(of: WatermarkModule.self)
        params.templates[0].use = true
        try record.setParams(params, as: WatermarkModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(record)
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_yiyin_watermark"))
        XCTAssertEqual(editorState.history.items.count - afterLoad, 1,
                       "the toggle = exactly ONE commit")

        // A template DELETE = another single commit (the stable key is
        // gone from the params, the row identity never indexed).
        record = try instance("watermark")
        params = try record.params(of: WatermarkModule.self)
        params.templates.removeFirst()
        try record.setParams(params, as: WatermarkModule.self)
        coordinator.beginContinuousEdit()
        await coordinator.setLiveParams(record)
        await coordinator.commitContinuousEdit(
            label: String(localized: "history_yiyin_template_delete"))
        XCTAssertEqual(editorState.history.items.count - afterLoad, 2)
        let after = try instance("watermark")
        XCTAssertEqual(
            try after.params(of: WatermarkModule.self).templates.count,
            WatermarkModule.Params.neutralSeed.templates.count - 1)
    }

    /// L025 catalog smoke (08-2 T6): every watermark-panel key carries BOTH
    /// the en and the zh localization in the String Catalog (the zh labels
    /// convention; a missing face degrades the whole runtime language).
    func testYiyinCatalogSmoke() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LightamerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let yiyinKeys = strings.keys.filter {
            $0.hasPrefix("panel_yiyin_") || $0.hasPrefix("history_yiyin_")
        }
        XCTAssertGreaterThanOrEqual(yiyinKeys.count, 37, "the 08-2 keys landed")
        for key in yiyinKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any], key)
            XCTAssertNotNil(localizations["en"], "\(key) missing en")
            let zh = try XCTUnwrap(localizations["zh"] as? [String: Any], "\(key) missing zh")
            let unit = try XCTUnwrap(zh["stringUnit"] as? [String: Any], key)
            XCTAssertEqual(unit["state"] as? String, "translated", key)
            XCTAssertFalse(
                (unit["value"] as? String ?? "").isEmpty, "\(key) empty zh value")
        }
    }
}