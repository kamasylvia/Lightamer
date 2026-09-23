@testable import LightamerCore
@testable import Lightamer
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

/// Plan 06-05 T6.1 — the E2E round-trip over a REAL RAW (LAYER-07/SC#5
/// 前半): decode → history-driven layer build (3 layers, different
/// blend/opacity, brush + gradient masks, layer-scoped param edit, reorder)
/// → undo×2 → sidecar write → RELOAD through the real coordinator restore
/// path → params byte-equal + UUID identity + RENDER byte-identity (L014
/// fence). The full persistence seam the 前半签核 pins.
@MainActor
final class LayerE2ERoundTripTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("layer-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func makeStack() async throws -> (PipeCoordinator, EditorState, MetalContext) {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)
        return (coordinator, editorState, metal)
    }

    private func readDisplayBytes(_ texture: any MTLTexture) -> [UInt8] {
        let rowBytes = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * texture.height)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: rowBytes,
                             from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                             mipmapLevel: 0)
        }
        return bytes
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// THE E2E (plan T6.1 verbatim shape).
    func testRealRAWRoundTripThroughHistoryAndSidecar() async throws {
        try Fixtures.require(Fixtures.dng)
        // The sidecar writes BESIDE the image — the fixture mirror is the
        // workable location; the sidecar + masks dir are removed after.
        let imageURL = Fixtures.dng
        let sidecarURL = imageURL.appendingPathExtension("lra")
        func removeIfExists(_ path: String) {
            if FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        defer {
            removeIfExists(sidecarURL.path)
            removeIfExists(imageURL.path + ".lra.masks")
        }

        // ── Decode once (the decode is shared by both legs).
        let decoder = RAWDecoder()
        let decoded = try await decoder.decode(imageURL)

        // ── Session 1: the REAL app objects, pristine seed, layer build.
        let (coordinator, editorState, metal) = try await makeStack()
        try await coordinator.load(url: imageURL, decoded: decoded, instances: [], metal: metal)
        try await Task.sleep(for: .milliseconds(50))

        // The layer chain module: a CONSTRUCTED TestGain record (the
        // pristine seed does not carry testgain; constructed records are
        // the established test shape — PanelWiring does the same).
        let globalGain = ModuleInstance(
            module: TestGainModule.self, multiName: "layer gain",
            params: .init(gain: 1.0))

        // 3 layers, distinct blend/opacity.
        let l1 = try XCTUnwrap(editorState.addAdjustmentLayer(), "L1")
        let l2 = try XCTUnwrap(editorState.addAdjustmentLayer(), "L2")
        _ = try XCTUnwrap(editorState.addAdjustmentLayer(), "L3")
        var p1 = l1
        p1.opacity = 0.7
        editorState.commitLayerEdit(p1, label: "L1 opacity")
        var p2 = l2
        p2.blendMode = .multiply
        p2.opacity = 0.85
        editorState.commitLayerEdit(p2, label: "L2 blend+opacity")

        // L1: a brush mask. L2: a gradient mask (one commit each).
        var m1 = l1
        m1.mask = MaskSpec(drawn: DrawnMaskSpec(forms: [MaskForm(kind: .brush(BrushStroke(
            points: [BrushPoint(
                corner: MaskPoint(x: 0.5, y: 0.5), ctrl1: MaskPoint(x: 0.5, y: 0.5),
                ctrl2: MaskPoint(x: 0.5, y: 0.5))],
            radius: 0.2, hardness: 0.7, density: 1.0, opacity: 1.0)))]))
        editorState.commitLayerEdit(m1, label: "L1 brush")
        var m2 = l2
        m2.mask = MaskSpec(drawn: DrawnMaskSpec(forms: [MaskForm(kind: .gradient(GradientForm(
            anchor: MaskPoint(x: 0.3, y: 0.6), rotationDegrees: 25,
            compression: 0.3, state: .sigmoidal)))]))
        editorState.commitLayerEdit(m2, label: "L2 gradient")

        // L3: a layer-scoped module param edit (the layerScope-型 track).
        let l3 = try XCTUnwrap(editorState.layerStack?.compositeLayers[2])
        let record = try XCTUnwrap(
            editorState.addModuleToLayer(layerID: l3.id, template: globalGain))
        var edited = record
        let gainParams = try edited.params(of: TestGainModule.self)
        var nextGain = gainParams
        nextGain.gain = 1.6
        try edited.setParams(nextGain, as: TestGainModule.self)
        await coordinator.setLiveParams(edited, layerID: l3.id)
        await coordinator.commitContinuousEdit(label: "L3 gain", layerScope: l3.id)

        // Reorder L3 to the bottom (ONE structure item).
        editorState.reorderLayer(id: l3.id, to: 0)
        let stackBeforeUndo = try XCTUnwrap(editorState.layerStack)
        XCTAssertEqual(stackBeforeUndo.compositeLayers.map(\.name), [l3.name, l1.name, l2.name])

        // Render the FULL state (L014 fence; bgra8 display plane).
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let baseChain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        let imageID = try XCTUnwrap(coordinator.currentImageID)

        func renderCurrent(_ stack: LayerStack) async throws -> [UInt8] {
            let result = try await LayerCompositeDriver.composite(
                image: decoded, imageID: imageID, baseInstances: baseChain,
                layerStack: stack, registry: registry, resolution: .preview,
                cache: PipeCache(), metal: metal, longEdge: 1024, policy: .preview)
            drain(metal)
            return readDisplayBytes(result.output)
        }
        _ = try await renderCurrent(stackBeforeUndo) // the pre-undo render evidence

        // ── undo×2 (drops the reorder + the L3 gain commit).
        await coordinator.undo()
        await coordinator.undo()
        let undoneStack = try XCTUnwrap(editorState.layerStack)
        XCTAssertEqual(undoneStack.compositeLayers.count, 3)
        XCTAssertEqual(undoneStack.compositeLayers.map(\.name), [l1.name, l2.name, l3.name],
                       "undo drops the reorder")

        // Render A at the UNDONE position — the state being persisted.
        let renderA = try await renderCurrent(undoneStack)
        XCTAssertGreaterThan(renderA.count, 100_000, "防空转: the plane is rendered")

        // ── Sidecar write (the real throttle store, forced).
        await coordinator.flushSidecar()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
        let document = try XCTUnwrap(JSONDecoder().decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL)))
        XCTAssertNotNil(document.layerStack, "the document carries the layer stack")
        XCTAssertFalse(document.driftDetected, "the freshly written document is not drift")

        // ── Session 2: the REAL restore path (fresh objects, same url).
        let (coordinator2, editorState2, _) = try await makeStack()
        try await coordinator2.load(url: imageURL, decoded: decoded, instances: [], metal: metal)
        try await Task.sleep(for: .milliseconds(100))
        let restoredStack = try XCTUnwrap(editorState2.layerStack, "the restore installs the stack")

        // UUID identity (NDE-1) + params bytes.
        XCTAssertEqual(restoredStack.compositeLayers.map(\.id), undoneStack.compositeLayers.map(\.id),
                       "layer identities survive the round-trip")
        for (restored, original) in zip(restoredStack.compositeLayers, undoneStack.compositeLayers) {
            XCTAssertEqual(restored.name, original.name)
            XCTAssertEqual(restored.opacity, original.opacity, accuracy: 1e-6)
            XCTAssertEqual(restored.blendMode, original.blendMode)
            XCTAssertEqual(restored.mask?.stableHash(), original.mask?.stableHash(),
                           "\(original.name): mask identity")
            XCTAssertEqual(restored.chain.count, original.chain.count)
            for (r, o) in zip(restored.chain, original.chain) {
                XCTAssertEqual(r.id, o.id, "chain record identity")
                XCTAssertEqual(r.paramsData, o.paramsData, "chain params bytes")
            }
        }
        XCTAssertEqual(editorState2.history.position, editorState.history.position,
                       "the history position survives (the undone state)")
        XCTAssertEqual(editorState2.history.items.count, editorState.history.items.count)

        // RENDER byte-identity: original-undone vs restored (L014 fence).
        let renderB = try await renderCurrent(restoredStack)
        XCTAssertEqual(renderB.count, renderA.count)
        if renderA != renderB {
            var differing = 0
            for (a, b) in zip(renderA, renderB) where a != b { differing += 1 }
            XCTFail("render round-trip must be byte-identical; differing bytes = \(differing)")
        }
    }
}
