@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MaskRevisionTests (Plan M2-7-1 T5, KD-5; M2MASK-07/03) — the contentRevision
// write-point table driven through the APP real state: the overlay record's
// press → live ticks → commit path, the AI install seam, and the mask
// commands. The table (checker E3/E5):
//
//   bump (history commit legs, exactly once each):
//     ① overlay endInteraction (BEFORE the commit; live legs zero bump)
//     ② AI bake install   ③ MaskCommand.fill   ④ duplicateAndInvert
//     ⑤ the P2 panel item-property writes (lands with P2 — callers bump)
//   zero delta: duplicate (content MOVE), resetEdits (chain, mask kept),
//               clear (no record left — no producer target).
//
// The "normal stroke = the equal path, exactly +1, NO replay" assertion is
// the checker-E5 pin: press/live-ticks leave the revision untouched, the
// single commit bumps exactly once — a replay regression would double-bump
// or double-commit and fail these counts.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class MaskRevisionTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!
    private var editingState: LayerEditingState!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("maskrev-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        coordinator = PipeCoordinator()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: harness

    /// The simple editing seed (the MaskItemSemanticsTests pattern — the
    /// structure-commit placeholder needs a non-empty base/instance set).
    private func makeSimpleSeed() {
        editorState = EditorState()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        editingState = LayerEditingState()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(
                module: TestGainModule.self, multiName: "seed",
                params: .init(gain: 1.0))
        ])
    }

    /// The full load path (the LayerUIWiringTests pattern — the AI landing
    /// touches the coordinator's render/tint legs).
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
        editorState = EditorState()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)
        editingState = LayerEditingState()
        let url = tempDirectory.appendingPathComponent("image.exr")
        try await coordinator.load(
            url: url, decoded: try makeSyntheticImage(), instances: [], metal: metal)
        try await Task.sleep(for: .milliseconds(20))
    }

    private func newLayer() throws -> AdjustmentLayer {
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        return layer
    }

    private func strokeForm(x: Float, y: Float) -> MaskForm {
        MaskForm(kind: .brush(BrushStroke(
            points: [BrushPoint(
                corner: MaskPoint(x: x, y: y), ctrl1: MaskPoint(x: x, y: y),
                ctrl2: MaskPoint(x: x, y: y))],
            radius: 0.02, hardness: 0.8, density: 0.9, opacity: 1)))
    }

    private func revision(_ layerID: UUID) -> Int? {
        editorState.adjustmentLayer(id: layerID)?.mask?.contentRevision
    }

    private func strokePointCount(_ spec: MaskSpec?) -> Int {
        guard let first = spec?.drawn?.forms.first,
            case let .brush(stroke) = first.kind
        else { return 0 }
        return stroke.points.count
    }

    // MARK: ① the overlay legs — the equal path, exactly +1, no replay

    func testNormalStrokeIsOneBumpOnTheEqualPathNoReplay() throws {
        makeSimpleSeed()
        let layer = try newLayer()
        let items = editorState.history.items.count
        var record = MaskOverlayRecord()

        // PRESS: the live leg installs the form — zero history, ZERO bump
        // (the P2 grab would snapshot the revision HERE, post-press-write).
        let form = record.appendForm(
            strokeForm(x: 0.3, y: 0.3).kind, layer: layer, editorState: editorState)
        XCTAssertNil(revision(layer.id), "live leg: revision untouched")
        XCTAssertEqual(editorState.history.items.count, items, "live leg: zero history")

        // LIVE TICKS ×2: the stroke grows — revision stays put, no history.
        for offset in [Float(0.05), Float(0.05)] {
            record.mutateForm(
                id: form.id, layer: layer, editorState: editorState
            ) { kind in
                if case var .brush(stroke) = kind {
                    let last = stroke.points.last!
                    stroke.points.append(BrushPoint(
                        corner: MaskPoint(x: last.corner.x + offset, y: last.corner.y),
                        ctrl1: MaskPoint(x: last.corner.x + offset, y: last.corner.y),
                        ctrl2: MaskPoint(x: last.corner.x + offset, y: last.corner.y)))
                    kind = .brush(stroke)
                }
            }
        }
        XCTAssertNil(revision(layer.id), "live ticks never bump (checker E5)")
        XCTAssertEqual(editorState.history.items.count, items)
        XCTAssertEqual(
            strokePointCount(editorState.adjustmentLayer(id: layer.id)?.mask), 3,
            "the live payload carries every tick")

        // END: the commit leg — exactly ONE item and the revision moves
        // exactly 0 → 1. A replay regression (re-append + re-commit) would
        // double-bump or double-commit: this is the no-replay pin.
        record.endInteraction(
            hadInteraction: true, editingState: editingState,
            editorState: editorState, label: "test stroke")
        let committed = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        XCTAssertEqual(revision(layer.id), 1, "the equal path bumps exactly +1")
        XCTAssertEqual(editorState.history.items.count, items + 1, "exactly ONE commit")
        XCTAssertEqual(committed.mask?.drawn?.forms.count, 1, "no re-append replay")
        XCTAssertEqual(strokePointCount(committed.mask), 3, "the payload survives the commit")

        // A no-op tap (interaction without mutation) never lands history
        // and never bumps.
        var idle = MaskOverlayRecord()
        idle.endInteraction(
            hadInteraction: true, editingState: editingState,
            editorState: editorState, label: "test idle")
        XCTAssertEqual(revision(layer.id), 1, "no-op tap: zero bump")
        XCTAssertEqual(editorState.history.items.count, items + 1, "no-op tap: zero history")
    }

    // MARK: the D-M2-4-2-5 reveal — siblings survive the stroke legs

    /// Pre-fix this is RED: the old `MaskSpec(drawn:)` rebuild nils every
    /// sibling (parametric/raster/deletionProtected/contentRevision). The
    /// assertion survives ONLY on the sibling-faithful construction.
    func testSiblingPayloadsSurviveTheStrokeAppend() throws {
        makeSimpleSeed()
        let layer = try newLayer()
        var mask = MaskSpec(drawn: DrawnMaskSpec(forms: [strokeForm(x: 0.2, y: 0.2)]))
        mask.parametric = ParametricMask(
            domain: .luma,
            channels: [ParametricMask.ChannelEntry(
                channel: 0, curve: ParametricMask.ChannelCurve(points: [0, 0.4, 0.6, 1]))],
            invert: false)
        mask.raster = RasterMaskRef(fileName: "rev-test.png", maskHash: 42)
        mask.deletionProtected = true
        mask.contentRevision = 5
        let live = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        live.mask = mask
        editorState.commitLayerEdit(live, label: "test install")

        // One stroke append through the LIVE leg.
        var record = MaskOverlayRecord()
        _ = record.appendForm(
            strokeForm(x: 0.6, y: 0.6).kind, layer: layer, editorState: editorState)
        let spec = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)).mask
        XCTAssertNotNil(spec?.parametric, "parametric survives")
        XCTAssertEqual(spec?.raster?.fileName, "rev-test.png", "raster survives")
        XCTAssertEqual(spec?.deletionProtected, true, "the lock survives")
        XCTAssertEqual(spec?.contentRevision, 5, "the revision rides through untouched")
        XCTAssertEqual(spec?.drawn?.forms.count, 2, "the new form joined the drawn payload")
    }

    // MARK: ③④ the commands that bump; the three that do not

    func testFillBumpsForwardAndClearResetEditsStayAtZeroDelta() throws {
        makeSimpleSeed()
        let layer = try newLayer()
        var mask = MaskSpec(drawn: DrawnMaskSpec(forms: [strokeForm(x: 0.2, y: 0.2)]))
        mask.contentRevision = 3
        let live = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        live.mask = mask
        editorState.commitLayerEdit(live, label: "test install")

        // resetEdits: the CHAIN resets, the mask record is preserved —
        // zero revision delta.
        editingState.performMaskCommand(.resetEdits, editorState: editorState)
        XCTAssertEqual(revision(layer.id), 3, "resetEdits keeps the mask + revision")

        // fill: the mask record is REWRITTEN (empty spec) — the committed
        // value carries the revision FORWARD +1 (a stale in-flight writer's
        // expected 3 can never re-validate against the new record).
        editingState.performMaskCommand(.fill, editorState: editorState)
        let filled = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)).mask
        XCTAssertNotNil(filled, "fill keeps a record (the constant-1 passthrough)")
        XCTAssertEqual(filled?.contentRevision, 4, "fill bumps forward: 3 → 4")

        // clear: the record disappears — no producer target, no revision
        // artifact at all (the zero-delta ruling; a subsequent install
        // starts from the nil fold).
        editingState.performMaskCommand(.clear, editorState: editorState)
        XCTAssertNil(editorState.adjustmentLayer(id: layer.id)?.mask)
    }

    func testDuplicateCarriesRevisionAndInvertVariantBumps() throws {
        makeSimpleSeed()
        let layer = try newLayer()
        var mask = MaskSpec(drawn: DrawnMaskSpec(forms: [strokeForm(x: 0.2, y: 0.2)]))
        mask.contentRevision = 3
        let live = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        live.mask = mask
        editorState.commitLayerEdit(live, label: "test install")

        // Plain duplicate: a content MOVE (checker E3 ruling) — the copy's
        // mask is the source snapshot byte-for-byte, revision rides at 3.
        let copy = try XCTUnwrap(editorState.duplicateLayer(id: layer.id) as? AdjustmentLayer)
        XCTAssertEqual(copy.mask?.contentRevision, 3, "duplicate: revision 原值随迁")
        XCTAssertEqual(revision(layer.id), 3, "the source is untouched")

        // duplicateAndInvert: the invert variant is a CONTENT WRITE — the
        // copy's committed value bumps 3 → 4 (the source stays at 3).
        editingState.performMaskCommand(.duplicateAndInvert, editorState: editorState)
        let stack = editorState.layerStack
        let topmost = try XCTUnwrap(
            stack?.adjustmentLayers.compactMap { $0 as? AdjustmentLayer }
                .last(where: { $0.id != layer.id && $0.id != copy.id }))
        XCTAssertEqual(
            topmost.mask?.contentRevision, 4, "the invert variant bumps +1")
        XCTAssertTrue(topmost.mask?.drawn?.forms.isEmpty == false)
        XCTAssertEqual(revision(layer.id), 3, "the source stays at 3")
    }

    // MARK: ② the AI install seam — bump on the equal path, refuse on miss

    func testAIInstallBumpsOnEqualPathAndRefusesOnMismatch() async throws {
        try await loadSynthetic()
        let layer = try newLayer()
        let items = editorState.history.items.count

        func makePlane() -> AIMaskPlane {
            AIMaskPlane(width: 16, height: 16, floats: [Float](repeating: 0.5, count: 256))
        }

        // The equal path: expected = the current fold (nil → 0) — the
        // install proceeds and bumps the revision 0 → 1.
        let ref = try await AIMaskEditing.commitRasterMask(
            plane: makePlane(), source: .segment,
            imageURL: tempDirectory,
            label: "test ai mask",
            activateTool: nil,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal,
            expectedRevision: 0)
        XCTAssertEqual(revision(layer.id), 1, "install = one bump on the equal path")
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask?.raster?.fileName, ref.fileName)
        XCTAssertEqual(editorState.history.items.count, items + 1, "exactly ONE item")

        // The mismatch path: a stale in-flight snapshot (expected 1 vs the
        // now-current 1 would pass; expected 99 fails) — the install is
        // REFUSED: typed error, zero history, zero state change, no
        // auto-rebake.
        do {
            _ = try await AIMaskEditing.commitRasterMask(
                plane: makePlane(), source: .segment,
                imageURL: tempDirectory,
                label: "test ai mask stale",
                activateTool: nil,
                coordinator: coordinator, editorState: editorState,
                editingState: editingState, metal: metal,
                expectedRevision: 99)
            XCTFail("the stale install must be refused")
        } catch let error as AIMaskError {
            guard case .invalidInput = error else {
                return XCTFail("unexpected error face: \(error)")
            }
        }
        XCTAssertEqual(editorState.history.items.count, items + 1, "zero history on refusal")
        XCTAssertEqual(revision(layer.id), 1, "zero bump on refusal")
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask?.raster?.fileName,
            ref.fileName, "the installed raster is untouched")
    }

    // MARK: the undo cross-write refusal (KD-5's snapshot-restore semantics)

    func testUndoRestoredRevisionRefusesInFlightWrite() async throws {
        try await loadSynthetic()
        let layer = try newLayer()

        func makePlane() -> AIMaskPlane {
            AIMaskPlane(width: 16, height: 16, floats: [Float](repeating: 0.5, count: 256))
        }

        // Install #1 (expected 0 → revision 1), then ⌘Z: the snapshot
        // restore carries the revision BACK to the pre-install fold (nil).
        _ = try await AIMaskEditing.commitRasterMask(
            plane: makePlane(), source: .segment,
            imageURL: tempDirectory,
            label: "test ai mask",
            activateTool: nil,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal,
            expectedRevision: 0)
        XCTAssertTrue(editorState.performUndo())
        XCTAssertNil(revision(layer.id), "the restore carries the old revision (期望行为)")

        // The in-flight writer that grabbed expected = 1 BEFORE the undo now
        // faces revision 0 — the cross-write is REFUSED (the correct
        // behavior: a write must not land across its own undo).
        do {
            _ = try await AIMaskEditing.commitRasterMask(
                plane: makePlane(), source: .segment,
                imageURL: tempDirectory,
                label: "test ai mask cross",
                activateTool: nil,
                coordinator: coordinator, editorState: editorState,
                editingState: editingState, metal: metal,
                expectedRevision: 1)
            XCTFail("the cross-write must be refused")
        } catch let error as AIMaskError {
            guard case .invalidInput = error else {
                return XCTFail("unexpected error face: \(error)")
            }
        }
        XCTAssertNil(editorState.adjustmentLayer(id: layer.id)?.mask?.raster)
    }
}
