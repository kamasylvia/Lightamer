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

        let exposureRecord = ModuleInstance(module: ExposureModule.self, params: .init())
        let session = InspectorEditSession(coordinator: coordinator)
        let view = state.panelView(for: exposureRecord, edit: session)
        XCTAssertNotNil(view, "exposure must dispatch a panel")

        let colorinRecord = ModuleInstance(module: ColorInModule.self, params: .init())
        XCTAssertNil(state.panelView(for: colorinRecord, edit: session),
                     "terminal infrastructure has no panel")

        state.selectPanel(instanceID: exposureRecord.id)
        XCTAssertEqual(state.selectedPanel, exposureRecord.id.uuidString)
    }

    // MARK: - Helpers

    private func historyCount() -> Int { editorState.history.items.count }
}
