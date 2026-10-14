@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

/// AIMaskPatchFlowTests (Plan M6-4-02 T4, KD-1/KD-3) — the App-side flow
/// pins: ① the patch debounce merge (a burst of interactions collapses
/// into ONE pass, the last one wins), ② the feather legs' parameter face
/// at the WIRE (positive → the GPU bake radius = sigma; negative → the CPU
/// logit-gain plane AND the bake radius FORCED 0 — the double-feather pin;
/// 0 → byte-identical to the plain path), ③ the person menu-entry routing
/// face (the .person source family disjoint from the segment re-entry
/// discriminant), ④ the same-maskID overwrite across a patch-style rebake.
@MainActor
final class AIMaskPatchFlowTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!
    private var editingState: LayerEditingState!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("aimaskpatch-\(UUID().uuidString)", isDirectory: true)
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
        editingState?.segmentSession.patchDebounceTask?.cancel()
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

    private func loadSynthetic() async throws {
        let url = tempDirectory.appendingPathComponent("image.exr")
        try await coordinator.load(
            url: url, decoded: makeSyntheticImage(), instances: [], metal: metal
        )
        try await Task.sleep(for: .milliseconds(20))
    }

    /// A left-half-ones (or right-half) plane.
    private func halfPlane(left: Bool) -> AIMaskPlane {
        AIMaskPlane(
            width: 16, height: 16,
            floats: (0..<256).map { (($0 % 16 < 8) == left) ? Float(1.0) : Float(0.0) })
    }

    /// A horizontal sigmoid ramp — the SOFT edge a real generation leaves
    /// (the negative leg's logit gain is a fixed point at exact 0/1, so the
    /// feather pins need a soft transition to act on).
    private func softPlane() -> AIMaskPlane {
        AIMaskPlane(width: 32, height: 16, floats: (0..<512).map { i in
            let x = Double(i % 32)
            return Float(1.0 / (1.0 + Foundation.exp(-(x - 16.0) / 3.0)))
        })
    }

    private func commit(
        _ plane: AIMaskPlane, layer: AdjustmentLayer, featherPercent: Float
    ) async throws -> RasterMaskRef {
        editingState.segmentSession.featherPercent = featherPercent
        return try await AIMaskEditing.commitRasterMask(
            plane: plane, source: .segment,
            imageURL: tempDirectory, label: "ai patch flow",
            activateTool: nil,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)
    }

    // MARK: ① debounce merge

    /// Five schedules inside the window → exactly ONE operation runs and
    /// it is the LAST one (each schedule cancels the previous — KD-1's
    /// merge). The injected `delay` is the clock seam.
    func testPatchDebounceMergesBurstIntoSingleRun() async throws {
        let session = editingState.segmentSession
        var runs = 0
        var lastTag = 0
        for tag in 1...5 {
            AIMaskEditing.schedulePatchRefine(session: session, delay: .milliseconds(60)) {
                runs += 1
                lastTag = tag
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(runs, 1, "a burst of interactions collapses into ONE pass")
        XCTAssertEqual(lastTag, 5, "the LAST scheduled operation is the one that runs")
        session.patchDebounceTask?.cancel()
    }

    // MARK: ② feather legs at the wire (double-feather pin)

    /// The resolution face + the wire bytes: percent > 0 → the bake radius
    /// is sigma (GPU leg, the plane untouched); percent < 0 → the CPU
    /// logit-gain plane AND the bake radius FORCED 0 (the double-feather
    /// pin: one feather, one primitive — verified byte-level by baking the
    /// manually-negatived plane at radius 0 and matching the wire's file);
    /// percent 0 → byte-identical to the plain path.
    func testFeatherLegsResolveAndDoubleFeatherPin() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        let plane = softPlane()

        // The resolution face.
        let positive = AIMaskEditing.resolveFeather(plane: plane, percent: 40)
        XCTAssertEqual(positive.plane.floats, plane.floats, "positive = the plane untouched")
        XCTAssertEqual(
            positive.radius,
            AIMaskFeather.sigma(percent: 40, longEdgePixels: 32), accuracy: 1e-6)
        let negative = AIMaskEditing.resolveFeather(plane: plane, percent: -40)
        XCTAssertNotEqual(negative.plane.floats, plane.floats, "negative = the CPU remap")
        XCTAssertEqual(negative.radius, 0, accuracy: 1e-9,
                       "DOUBLE-FEATHER PIN: the negative leg's bake radius is 0")
        let zero = AIMaskEditing.resolveFeather(plane: plane, percent: 0)
        XCTAssertEqual(zero.plane.floats, plane.floats)
        XCTAssertEqual(zero.radius, 0, accuracy: 1e-9)

        // The wire: percent 0 vs the plain bake → byte-identical files.
        let refZero = try await commit(plane, layer: layer, featherPercent: 0)
        let zeroBytes = try Data(
            contentsOf: RasterMaskStore.masksDirectory(forImageURL: tempDirectory)
                .appendingPathComponent(refZero.fileName))

        // Positive: a NEW hash (the feathered bake) — the GPU leg at work.
        let refPositive = try await commit(plane, layer: layer, featherPercent: 40)
        XCTAssertEqual(refPositive.fileName, refZero.fileName, "same maskID")
        XCTAssertNotEqual(refPositive.maskHash, refZero.maskHash,
                          "the positive leg feathers through the bake radius")
        // …and the wire file equals a manual bake at radius == sigma.
        let manualPositive = try await RasterMaskStore.bake(
            plane: AIMaskResample.texture(from: plane, metal: metal),
            directory: RasterMaskStore.masksDirectory(forImageURL: tempDirectory),
            fileName: "manual-positive.png", invert: false,
            featherRadius: AIMaskFeather.sigma(percent: 40, longEdgePixels: 32),
            metal: metal)
        let positiveBytes = try Data(
            contentsOf: RasterMaskStore.masksDirectory(forImageURL: tempDirectory)
                .appendingPathComponent(refPositive.fileName))
        let manualPositiveBytes = try Data(
            contentsOf: RasterMaskStore.masksDirectory(forImageURL: tempDirectory)
                .appendingPathComponent("manual-positive.png"))
        XCTAssertEqual(positiveBytes, manualPositiveBytes,
                       "the wire's positive leg == bake(radius = sigma)")

        // Negative: the CPU plane at radius 0 — the double-write pin.
        let refNegative = try await commit(plane, layer: layer, featherPercent: -40)
        let negativeBytes = try Data(
            contentsOf: RasterMaskStore.masksDirectory(forImageURL: tempDirectory)
                .appendingPathComponent(refNegative.fileName))
        XCTAssertNotEqual(negativeBytes, zeroBytes, "the negative leg changes the pixels")
        let manualNegative = try await RasterMaskStore.bake(
            plane: AIMaskResample.texture(
                from: AIMaskFeather.applyFeatherNegative(plane: plane, percent: -40),
                metal: metal),
            directory: RasterMaskStore.masksDirectory(forImageURL: tempDirectory),
            fileName: "manual-negative.png", invert: false,
            featherRadius: 0, metal: metal)
        let manualNegativeBytes = try Data(
            contentsOf: RasterMaskStore.masksDirectory(forImageURL: tempDirectory)
                .appendingPathComponent("manual-negative.png"))
        XCTAssertEqual(negativeBytes, manualNegativeBytes,
                       "the wire's negative leg == bake(CPU-negative plane, radius 0)")
        XCTAssertNotEqual(negativeBytes, manualPositiveBytes,
                          "the two legs are different primitives")
        editingState.segmentSession.patchDebounceTask?.cancel()
    }

    // MARK: ③ person menu-entry routing face

    /// The `.person` source family: the file round-trips through
    /// `source(ofFileName:)`, and the segment re-entry discriminant is
    /// UNTOUCHED — a person raster file must NOT seed a segment refine
    /// session (only `.segment` files do), while a segment file still does.
    func testPersonMenuRoutingSourceFace() throws {
        let personLayer = AdjustmentLayer(name: "P", opacity: 1)
        let personName = AIMaskSource.person.fileName(forLayerID: personLayer.id)
        XCTAssertTrue(personName.hasPrefix("ai-person-"))
        XCTAssertEqual(AIMaskSource.source(ofFileName: personName), .person)

        // A person file never seeds a segment refine session.
        editingState.armSegmentSession(for: AdjustmentLayer(
            id: personLayer.id, name: "P", opacity: 1,
            mask: MaskSpec(raster: RasterMaskRef(fileName: personName, maskHash: 7))))
        XCTAssertNil(editingState.segmentSession.rebakeFileName,
                     "the person family must not enter the segment re-entry path")

        // A segment file still does (the 07-3 semantics preserved).
        let segmentName = AIMaskSource.segment.fileName(forLayerID: personLayer.id)
        editingState.armSegmentSession(for: AdjustmentLayer(
            id: personLayer.id, name: "P", opacity: 1,
            mask: MaskSpec(raster: RasterMaskRef(fileName: segmentName, maskHash: 7))))
        XCTAssertEqual(editingState.segmentSession.rebakeFileName, segmentName)
    }

    // MARK: ④ same-maskID overwrite across rebakes

    /// Two commits on the same layer+source: the SAME file name, the hash
    /// flips, the disk bytes are replaced (D-07-CONTEXT-5 through the patch
    /// flow's re-bake), and the session live plane is captured at the first
    /// success (M6's hold).
    func testPatchRebakeOverwritesSameMaskID() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)

        let ref1 = try await commit(halfPlane(left: true), layer: layer, featherPercent: 0)
        XCTAssertNotNil(editingState.segmentSession.livePlane,
                        "the first successful segment commit captures the live plane")
        let bytes1 = try Data(
            contentsOf: RasterMaskStore.masksDirectory(forImageURL: tempDirectory)
                .appendingPathComponent(ref1.fileName))

        let ref2 = try await commit(halfPlane(left: false), layer: layer, featherPercent: 0)
        XCTAssertEqual(ref2.fileName, ref1.fileName, "same maskID overwrite")
        XCTAssertNotEqual(ref2.maskHash, ref1.maskHash, "the hash flips → caches invalidate")
        let bytes2 = try Data(
            contentsOf: RasterMaskStore.masksDirectory(forImageURL: tempDirectory)
                .appendingPathComponent(ref2.fileName))
        XCTAssertNotEqual(bytes1, bytes2, "the old pixels are replaced on disk")
        editingState.segmentSession.patchDebounceTask?.cancel()
    }
}
