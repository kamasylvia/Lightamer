@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

/// AIMaskTaskPanelTests (M9-1 T1, M9AIM-01) — the task-mask panel pins:
/// ① the four-entry assembly (Subject / Background / Sky / People, the SM9
/// icon-row order) with the Sky slot PERMANENTLY disabled (charter
/// OQ-M9-2A — no live code path); ② the Background identity: the SAME
/// subject leg, the 1−x semantics riding the per-ref invert bit (same
/// plane → same bake bytes → only `RasterMaskRef.invert` differs); ③ the
/// invert bit round-trip through bake/load (the load applies 1−x — the
/// ref bit is the semantics carrier); ④ the People subset union
/// consumption (unionSelection's max-fold math over synthetic planes +
/// the typed no-subject face for an empty selection); ⑤ the panel-entry
/// face the buttons consume (identifier spelling — the walkthrough's AX
/// contract).
@MainActor
final class AIMaskTaskPanelTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!
    private var editingState: LayerEditingState!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("aimasktask-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: ① the four-entry assembly + the Sky slot

    /// The panel enumerates exactly the four SM9 entries in order; Sky is
    /// the ONLY disabled face (the slot never carries a live path); every
    /// entry carries a stable AX identifier under the `ai.mask.task.`
    /// stem (the walkthrough contract).
    func testTaskPanelFourEntriesAndSkySlotDisabled() {
        XCTAssertEqual(
            AIMaskTask.allCases, [.subject, .background, .sky, .people],
            "the panel = the SM9 icon-row order")
        XCTAssertFalse(AIMaskTask.sky.isEnabled, "Sky = the charter-disabled slot (OQ-M9-2A)")
        XCTAssertTrue(AIMaskTask.subject.isEnabled)
        XCTAssertTrue(AIMaskTask.background.isEnabled)
        XCTAssertTrue(AIMaskTask.people.isEnabled)
        for task in AIMaskTask.allCases {
            XCTAssertEqual(
                task.identifier, "ai.mask.task.\(task.rawValue)",
                "stable AX id stem for \(task.rawValue)")
            XCTAssertFalse(task.systemImage.isEmpty)
        }
    }

    // MARK: ② Background = the SAME subject leg + the invert bit

    /// The Background identity: committing the SAME synthetic plane
    /// through the subject channel with invert false/true produces the
    /// SAME bake file (same name, same hash — the generation leg is
    /// shared, no second implementation) and ONLY the per-ref invert bit
    /// differs. The 1−x semantics live in the ref bit, not in a re-baked
    /// complementary plane.
    func testBackgroundRidesSubjectLegWithInvertBit() async throws {
        try await loadSynthetic()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        let plane = halfPlane(left: true)

        let plain = try await AIMaskEditing.commitRasterMask(
            plane: plane, source: .subject, invert: false,
            imageURL: tempDirectory, label: "task panel",
            activateTool: nil,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)
        let inverted = try await AIMaskEditing.commitRasterMask(
            plane: plane, source: .subject, invert: true,
            imageURL: tempDirectory, label: "task panel",
            activateTool: nil,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)

        XCTAssertEqual(
            inverted.fileName, plain.fileName,
            "same layer+source ⇒ the same mask file (the legs are one)")
        XCTAssertEqual(
            inverted.maskHash, plain.maskHash,
            "the SAME plane bakes the SAME bytes — the invert rides the ref bit, not a re-bake")
        XCTAssertFalse(plain.invert)
        XCTAssertTrue(inverted.invert, "Background's face = the per-ref invert bit")

        // The layer's slot carries the inverted reference.
        let slot = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)?.mask?.raster)
        XCTAssertEqual(slot.invert, true)
        XCTAssertEqual(slot.fileName, inverted.fileName)
    }

    // MARK: ③ the invert bit round-trip (bake → load = 1−x)

    /// The ref bit is the SEMANTICS carrier: loading the inverted
    /// reference yields the point-wise 1−x of the plain load (the store's
    /// `MaskCombiner.invert` leg). Baked bytes stay identical — only the
    /// interpretation flips.
    func testInvertBitRoundTripsThroughLoad() async throws {
        let directory = tempDirectory.appendingPathComponent("masks", isDirectory: true)
        let plane = try AIMaskResample.texture(from: halfPlane(left: true), metal: metal)
        let plain = try await RasterMaskStore.bake(
            plane: plane, directory: directory,
            fileName: "plain.png", invert: false, metal: metal)
        let inverted = try await RasterMaskStore.bake(
            plane: plane, directory: directory,
            fileName: "inverted.png", invert: true, metal: metal)
        XCTAssertTrue(inverted.invert)

        let plainBytes = try Data(contentsOf: directory.appendingPathComponent("plain.png"))
        let invertedBytes = try Data(contentsOf: directory.appendingPathComponent("inverted.png"))
        XCTAssertEqual(plainBytes, invertedBytes, "the bit never re-bakes the pixels")

        let plainResult = try await RasterMaskStore.load(
            ref: plain, directory: directory,
            windowWidth: 16, windowHeight: 16, metal: metal)
        let invertedResult = try await RasterMaskStore.load(
            ref: inverted, directory: directory,
            windowWidth: 16, windowHeight: 16, metal: metal)
        guard case .plane(let loadedPlain) = plainResult else {
            return XCTFail("plain load degraded")
        }
        guard case .plane(let loadedInverted) = invertedResult else {
            return XCTFail("inverted load degraded")
        }
        let a = Self.readFloats(loadedPlain, metal: metal)
        let b = Self.readFloats(loadedInverted, metal: metal)
        XCTAssertEqual(a.count, b.count)
        for i in 0..<a.count {
            XCTAssertEqual(b[i], 1 - a[i], accuracy: 1e-3,
                           "load(invert) = 1 − load(plain), point-wise")
        }
    }

    // MARK: ④ the People subset union consumption

    /// unionSelection's math over synthetic planes: `.all` = the max over
    /// every instance; `.subset` = the max over the picked ones only; an
    /// EMPTY subset = the typed noSubject (the panel's empty state —
    /// nothing was asked for, never an all-ones plane); an unknown index
    /// = the typed invalidInput.
    func testPeopleSubsetUnionConsumption() throws {
        let width = 4, height = 4
        func planeWithValue(_ value: Float, at index: Int) -> AIMaskPlane {
            var floats = [Float](repeating: 0, count: width * height)
            floats[index] = value
            return AIMaskPlane(width: width, height: height, floats: floats)
        }
        // Instance planes with disjoint non-zero cells (deterministic max).
        let planes = [
            planeWithValue(0.8, at: 0),
            planeWithValue(0.5, at: 5),
            planeWithValue(1.0, at: 10),
        ]
        let instances = [0, 1, 2]

        let all = try AIMaskService.unionSelection(
            .all, instances: instances, extract: { planes[$0] })
        XCTAssertEqual(all.floats[0], 0.8, accuracy: 1e-6)
        XCTAssertEqual(all.floats[5], 0.5, accuracy: 1e-6)
        XCTAssertEqual(all.floats[10], 1.0, accuracy: 1e-6)

        let subset = try AIMaskService.unionSelection(
            .subset([0, 2]), instances: instances, extract: { planes[$0] })
        XCTAssertEqual(subset.floats[0], 0.8, accuracy: 1e-6)
        XCTAssertEqual(subset.floats[5], 0, accuracy: 1e-6, "instance 1 not picked")
        XCTAssertEqual(subset.floats[10], 1.0, accuracy: 1e-6)

        XCTAssertThrowsError(try AIMaskService.unionSelection(
            .subset([]), instances: instances, extract: { planes[$0] })) { error in
            XCTAssertEqual(error as? AIMaskError, .noSubject,
                           "empty subset = the typed no-subject empty state")
        }
        XCTAssertThrowsError(try AIMaskService.unionSelection(
            .subset([7]), instances: instances, extract: { planes[$0] })) { error in
            XCTAssertEqual(
                (error as? AIMaskError)?.isInvalidInput ?? false, true,
                "unknown index = typed invalidInput")
        }
    }

    // MARK: ⑤ the entry source face (the buttons consume the enum)

    /// The production buttons render `taskIcon(_:)` from the enum and key
    /// their identifiers off it — the enum IS the panel's single source
    /// (the grep acceptance pins the button bodies; this pins the face
    /// they consume, so the two cannot drift).
    func testPanelEntryFaceStability() {
        XCTAssertEqual(AIMaskTask.subject.identifier, "ai.mask.task.subject")
        XCTAssertEqual(AIMaskTask.background.identifier, "ai.mask.task.background")
        XCTAssertEqual(AIMaskTask.sky.identifier, "ai.mask.task.sky")
        XCTAssertEqual(AIMaskTask.people.identifier, "ai.mask.task.people")
    }

    // MARK: fixtures

    private func loadSynthetic() async throws {
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
    }

    private func halfPlane(left: Bool) -> AIMaskPlane {
        AIMaskPlane(
            width: 16, height: 16,
            floats: (0..<256).map { (($0 % 16 < 8) == left) ? Float(1.0) : Float(0.0) })
    }

    /// Fence + read-back (L014 — never read an in-flight encoder).
    private static func readFloats(
        _ texture: any MTLTexture, metal: MetalContext
    ) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        let w = texture.width, h = texture.height
        var floats = [Float](repeating: 0, count: w * h)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: w * 4,
                from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return floats
    }
}

/// The invalid-input discriminator for the typed-error assertions above
/// (the case carries a payload — Equatable cannot synthesize across it).
private extension AIMaskError {
    var isInvalidInput: Bool {
        if case .invalidInput = self { return true }
        return false
    }
}
