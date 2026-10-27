@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

/// AIMaskSessionCommandsTests (M9-1 T4, M9AIM-03) — the session-command
/// face:
/// ① the re-entry route: the user's EXPLICIT re-open seeds a refine
///    session for the .segment/.subject/.person THREE sources (the m-4
///    design-intent reversal — automatic seeding stays forbidden);
///    depth/skin/hand-drawn never route;
/// ② the paste exclusion (D-M9A-8, the declared SEMANTIC REVERSAL): an
///    AI-baked raster reference drops out of the payload (the skip list
///    carries its name), an AI-ONLY mask drops entirely, drawn/
///    parametric payloads survive, and a hand-drawn raster rides the
///    payload untouched (the conservative arm);
/// ③ the undo boundary (R-5): the candidate session writes ZERO history
///    items (a failed solve included — the typed toast only); commit is
///    the only writer (exactly one item — the AI-06 form).
@MainActor
final class AIMaskSessionCommandsTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!
    private var editingState: LayerEditingState!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("aimaskcmd-\(UUID().uuidString)", isDirectory: true)
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
        editingState?.segmentSession.candidateDebounceTask?.cancel()
        editingState?.segmentSession.patchDebounceTask?.cancel()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: ① the re-entry three-source route

    /// armSegmentSession routes .segment/.subject/.person (the explicit
    /// user re-open — regenerate-and-overwrite pointing at the same file)
    /// and NOTHING else.
    func testReentryRoutesTheThreeSources() {
        let layerID = UUID()
        func layer(carrying fileName: String?) -> AdjustmentLayer {
            AdjustmentLayer(
                id: layerID, name: "L", opacity: 1,
                mask: fileName.map {
                    MaskSpec(raster: RasterMaskRef(fileName: $0, maskHash: 7))
                })
        }
        for source in [AIMaskSource.segment, .subject, .person] {
            let name = source.fileName(forLayerID: layerID)
            editingState.armSegmentSession(for: layer(carrying: name))
            XCTAssertEqual(
                editingState.segmentSession.rebakeFileName, name,
                "the explicit re-entry routes \(source.rawValue)")
        }
        for outside in [
            AIMaskSource.depth.fileName(forLayerID: layerID),
            AIMaskSource.skin.fileName(forLayerID: layerID),
            "hand-drawn-\(layerID.uuidString).png",
            "some-mask.png",
        ] {
            editingState.armSegmentSession(for: layer(carrying: outside))
            XCTAssertNil(
                editingState.segmentSession.rebakeFileName,
                "outside the route: \(outside)")
        }
        // No mask at all: a fresh session (the 07-3 default).
        editingState.armSegmentSession(for: layer(carrying: nil))
        XCTAssertNil(editingState.segmentSession.rebakeFileName)
    }

    // MARK: ② the paste exclusion (the declared reversal)

    /// One snapshot layer with a mask + one transferable record.
    private func snapshotLayer(
        id: UUID = UUID(), mask: MaskSpec?
    ) -> LayerStackSnapshot.Layer {
        LayerStackSnapshot.Layer(
            id: id, name: "Grade", isVisible: true, opacity: 1,
            blendMode: 0, blendOptions: 0, enabled: true,
            chain: [ModuleInstance(
                id: UUID(), opName: "exposure", multiPriority: 0,
                multiName: "", iopOrder: 50, version: 1, enabled: true,
                paramsData: Data("{}".utf8), paramsHash: 0)],
            mask: mask)
    }

    private func items(for snapshot: LayerStackSnapshot.Layer)
        -> [UUID: [TransferItem]]
    {
        [snapshot.id: snapshot.chain.map {
            TransferItem(instance: $0, transferable: true, checked: true)
        }]
    }

    /// An AI-baked raster drops from the pasted layer's mask and its
    /// name lands in the skip list; an AI-ONLY mask drops entirely.
    func testPasteExcludesAIBakedRasterAndListsNames() throws {
        let layerID = UUID()
        let aiMask = MaskSpec(raster: RasterMaskRef(
            fileName: AIMaskSource.segment.fileName(forLayerID: layerID),
            maskHash: 11))
        let snapshot = snapshotLayer(id: layerID, mask: aiMask)

        let payload = AdjustmentTransferCatalog.buildPayload(
            layerSnapshots: [snapshot], items: items(for: snapshot),
            drtRecord: nil, includeDrt: false)
        let pasted = try XCTUnwrap(payload)
        XCTAssertEqual(
            pasted.excludedAIMasks,
            [AIMaskSource.segment.fileName(forLayerID: layerID)],
            "the skip list names the excluded AI mask")
        let pastedLayer = try XCTUnwrap(pasted.snapshot?.layers.first)
        XCTAssertNil(pastedLayer.mask, "an AI-ONLY mask drops entirely")
        XCTAssertEqual(pasted.records.count, 1, "the chain records ride on")
    }

    /// A hand-drawn raster (no AI prefix) rides the payload untouched —
    /// the conservative arm (only RECOGNIZABLE AI files are excluded).
    func testPasteKeepsHandDrawnRaster() throws {
        let layerID = UUID()
        let handDrawn = MaskSpec(raster: RasterMaskRef(
            fileName: "hand-\(layerID.uuidString).png", maskHash: 5))
        let snapshot = snapshotLayer(id: layerID, mask: handDrawn)
        let payload = AdjustmentTransferCatalog.buildPayload(
            layerSnapshots: [snapshot], items: items(for: snapshot),
            drtRecord: nil, includeDrt: false)
        let pasted = try XCTUnwrap(payload)
        XCTAssertTrue(pasted.excludedAIMasks.isEmpty, "no AI exclusion")
        let pastedLayer = try XCTUnwrap(pasted.snapshot?.layers.first)
        XCTAssertEqual(
            pastedLayer.mask?.raster?.fileName, handDrawn.raster?.fileName,
            "the hand-drawn mask rides the payload")
        XCTAssertNil(pastedLayer.mask?.contentRevision,
                     "KD-3's epoch reset still applies to the carried mask")
    }

    /// A MIXED mask (AI raster + drawn payload): the raster drops, the
    /// drawn payload survives, the mask stays (not emptied).
    func testPasteStripsAIRasterButKeepsOtherPayloads() throws {
        let layerID = UUID()
        var mixed = MaskSpec()
        mixed.raster = RasterMaskRef(
            fileName: AIMaskSource.person.fileName(forLayerID: layerID),
            maskHash: 3)
        mixed.drawn = DrawnMaskSpec(forms: [
            MaskForm(kind: .brush(BrushStroke(
                points: [BrushPoint(
                    corner: MaskPoint(x: 0.5, y: 0.5),
                    ctrl1: MaskPoint(x: 0.5, y: 0.5),
                    ctrl2: MaskPoint(x: 0.5, y: 0.5))], radius: 0.05,
                hardness: 0.7, density: 1, opacity: 1)))
        ])
        let snapshot = snapshotLayer(id: layerID, mask: mixed)
        let payload = AdjustmentTransferCatalog.buildPayload(
            layerSnapshots: [snapshot], items: items(for: snapshot),
            drtRecord: nil, includeDrt: false)
        let pasted = try XCTUnwrap(payload)
        XCTAssertEqual(pasted.excludedAIMasks.count, 1)
        let pastedLayer = try XCTUnwrap(pasted.snapshot?.layers.first)
        XCTAssertNil(pastedLayer.mask?.raster, "the AI raster drops")
        XCTAssertNotNil(pastedLayer.mask?.drawn, "the drawn payload survives")
    }

    // MARK: ③ the undo boundary (R-5)

    /// The candidate session writes ZERO history: a seeded session with
    /// a held candidate, a failed solve (the scripted not-ready store) —
    /// the history count never moves (the typed toast only). Commit
    /// remains the only writer (exactly one item — pinned in the T3
    /// suite; this pins the session-side silence).
    func testCandidateSessionWritesZeroHistory() async throws {
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
        try await coordinator.load(
            url: tempDirectory.appendingPathComponent("image.exr"),
            decoded: DecodedImage(
                ciImage: CIImage(cgImage: cg),
                rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
                segmentationSkyMatte: nil, decoderVersionUsed: .v8),
            instances: [], metal: metal)
        try await Task.sleep(for: .milliseconds(20))
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        let session = editingState.segmentSession
        session.recordSeed(.point(AIMaskPoint(x: 0.5, y: 0.5)))
        session.candidatePlane = AIMaskPlane(
            width: 4, height: 4, floats: [Float](repeating: 1, count: 16))
        session.candidateState = .ready
        let historyBefore = editorState.history.items.count

        let notReady = AIAssetStore(
            statusProbe: { .notReady }, downloader: { _ in })
        await AIMaskEditing.runCandidateResolve(
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal, assets: notReady)

        XCTAssertEqual(
            editorState.history.items.count, historyBefore,
            "the candidate session (solve included) writes ZERO history")
        // A second arm/seed cycle is equally silent.
        editingState.armSegmentSession(for: layer)
        XCTAssertEqual(
            editorState.history.items.count, historyBefore,
            "re-entry writes ZERO history (regenerate happens at confirm)")
    }
}
