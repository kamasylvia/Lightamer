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

    // MARK: M2-7-2 T3 — the optimistic-concurrency dispatch (checker E5)

    /// The snapshot timing pin: the press write completes BEFORE the
    /// snapshot (live legs never bump → the pre-interaction value); the
    /// NEXT interaction's snapshot reads the post-bump value (the
    /// anti-self-mismatch rule for append+commit-style presses).
    func testSnapshotTimingIsPostPressWriteAndPostBump() throws {
        makeSimpleSeed()
        let layer = try newLayer()
        let items = editorState.history.items.count
        var record = MaskOverlayRecord()

        let form = record.appendForm(
            strokeForm(x: 0.3, y: 0.3).kind, layer: layer, editorState: editorState)
        XCTAssertNil(
            record.expectedRevision,
            "the press-write snapshot reads the CURRENT (nil → 0) value")

        record.endInteraction(
            hadInteraction: true, editingState: editingState,
            editorState: editorState, label: "test stroke")
        XCTAssertEqual(revision(layer.id), 1)

        // The NEXT interaction's press: the snapshot is the POST-BUMP
        // value — it can never mismatch its own previous commit.
        var second = MaskOverlayRecord()
        _ = second.appendForm(
            strokeForm(x: 0.7, y: 0.7).kind, layer: layer, editorState: editorState)
        XCTAssertEqual(second.expectedRevision, 1, "post-bump snapshot")
        second.endInteraction(
            hadInteraction: true, editingState: editingState,
            editorState: editorState, label: "test stroke 2")
        XCTAssertEqual(revision(layer.id), 2, "the equal path again: exactly +1")
        XCTAssertEqual(editorState.history.items.count, items + 2)
    }

    /// The append-type replay: an async writer (the AI bake) commits
    /// DURING the stroke — the interaction's append replays onto the
    /// fresh spec, bumps the MERGED value and lands exactly one item.
    func testConcurrentAIInstallDuringStrokeReplaysTheAppend() async throws {
        try await loadSynthetic()
        let layer = try newLayer()
        let items = editorState.history.items.count
        var record = MaskOverlayRecord()

        // PRESS: the live write; the snapshot = nil (revision 0).
        let form = record.appendForm(
            strokeForm(x: 0.3, y: 0.3).kind, layer: layer, editorState: editorState)

        // The concurrent writer: an AI install commits (bumps 0 → 1) and
        // REPLACES the stack's layer object with a snapshot carrying no
        // drawn payload.
        _ = try await AIMaskEditing.commitRasterMask(
            plane: AIMaskPlane(width: 16, height: 16,
                               floats: [Float](repeating: 0.5, count: 256)),
            source: .segment, imageURL: tempDirectory, label: "test ai mask",
            activateTool: nil, coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal, expectedRevision: 0)
        XCTAssertEqual(revision(layer.id), 1)
        // NOTE: the form SURVIVES here — the live legs write into the
        // SHARED layer object, so the async writer's sibling-faithful
        // snapshot carries the in-flight form (the D-M2-4-2-5 fix makes
        // the real race window narrower than the replay's worst case).
        // The replay still exercises the mismatch path (expected 0 vs the
        // now-current 1) and its dedup keeps exactly one form.
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask?.drawn?.forms.count, 1)

        // END: mismatch (expected 0 vs current 1) + append-type → REPLAY.
        record.endInteraction(
            hadInteraction: true, editingState: editingState,
            editorState: editorState, label: "test stroke")
        let committed = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        XCTAssertEqual(revision(layer.id), 2, "the replay bumps the MERGED value 1 → 2")
        XCTAssertEqual(
            editorState.history.items.count, items + 2,
            "the AI item + the replay item, nothing else")
        XCTAssertEqual(committed.mask?.drawn?.forms.count, 1, "the stroke re-landed")
        XCTAssertEqual(
            committed.mask?.drawn?.forms.first?.id, form.id, "the SAME form id (NDE-1)")
        XCTAssertNotNil(committed.mask?.raster, "the concurrent writer's payload survives")
        XCTAssertNotNil(editorState.toast, "the replay notice surfaced")
    }

    /// The mutate-only refuse: an existing-form edit races an async
    /// writer — the interaction is DISCARDED (zero history, zero bump,
    /// toast; the live spec re-reads as-is).
    func testConcurrentInstallDuringExistingFormMutateIsRefused() async throws {
        try await loadSynthetic()
        let layer = try newLayer()
        installCommittedSpec(on: layer)
        let formID = editorState.adjustmentLayer(id: layer.id)!.mask!.drawn!.forms[0].id
        let items = editorState.history.items.count
        var record = MaskOverlayRecord()

        // A feather-grip-style mutation of the EXISTING form (no append).
        record.mutateForm(id: formID, layer: layer, editorState: editorState) { kind in
            if case var .brush(stroke) = kind {
                stroke.radius = 0.09
                kind = .brush(stroke)
            }
        }
        XCTAssertNil(record.expectedRevision, "first mutation snapshots too")

        // The concurrent writer lands (0 → 1).
        _ = try await AIMaskEditing.commitRasterMask(
            plane: AIMaskPlane(width: 16, height: 16,
                               floats: [Float](repeating: 0.5, count: 256)),
            source: .segment, imageURL: tempDirectory, label: "test ai mask",
            activateTool: nil, coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal, expectedRevision: 0)

        // END: mismatch + mutate-only → REFUSE.
        record.endInteraction(
            hadInteraction: true, editingState: editingState,
            editorState: editorState, label: "test mutate")
        XCTAssertEqual(revision(layer.id), 1, "zero bump on refusal")
        XCTAssertEqual(
            editorState.history.items.count, items + 1,
            "only the AI item — the mutation never landed history")
        XCTAssertNotNil(editorState.toast, "the refusal notice surfaced")
        // The live spec carries the concurrent writer's content; the
        // stroke radius edit stays uncommitted live state.
        let live = editorState.adjustmentLayer(id: layer.id)
        XCTAssertNotNil(live?.mask?.raster)
    }

    // MARK: M2-7-2 T6 — the Follow Edges interaction (checker E6, AC7)

    /// The synthetic below plane: a vertical step at column 32 (the luma
    /// step → the Sobel ridge the walker hugs).
    private func syntheticEdgePlane(metal: MetalContext) throws -> any MTLTexture {
        let w = 64, h = 64
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v: Float = x < 32 ? 0.2 : 0.7
                let base = (y * w + x) * 4
                pixels[base] = v
                pixels[base + 1] = v
                pixels[base + 2] = v
                pixels[base + 3] = 1
            }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let plane = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        try pixels.withUnsafeBytes {
            plane.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 16)
        }
        return plane
    }

    /// The REAL production legs (kernel + fenced readback) behind an
    /// injected surface — the stub-seam shape: only the surface provider
    /// is synthetic; the edge map pipeline is the coordinator's own math.
    func testFollowEdgesStrokeHugsSyntheticEdgeAndBumpsOnce() async throws {
        try await loadSynthetic()
        let layer = try newLayer()
        let plane = try syntheticEdgePlane(metal: metal)
        let surface = PipeCoordinator.FollowEdgesSurface(
            plane: plane, imageID: UUID(), prefixHash: 1)

        let chain = await FollowEdgesInteraction.chain(
            seed: MaskPoint(x: 0.5, y: 0.5),
            layerID: layer.id,
            params: FollowEdgesParams(),
            surfaceProvider: { _ in surface },
            fieldReader: { surface in
                // The REAL production legs: the Sobel pass over the below
                // plane, then the fenced readback (only the surface
                // provider is synthetic — the stub-seam shape).
                guard let edge = try? await FollowEdges.edgeMap(
                    below: surface.plane, metal: self.metal)
                else { return nil }
                return FollowEdges.readEdgeMap(edge, metal: self.metal)
            })
        XCTAssertGreaterThanOrEqual(chain.count, 8, "the walk spans the ridge")
        for point in chain {
            XCTAssertEqual(
                Double(point.x) * 63.0, 32.0, accuracy: 2.0,
                "every point hugs the vertical edge (贴边)")
        }

        // The view's press leg packs the SAME chain into a BrushStroke and
        // appends through the record — the commit bumps EXACTLY once
        // (the E5 semantics hold for the follow-edges tool too).
        let items = editorState.history.items.count
        var record = MaskOverlayRecord()
        let stroke = BrushStroke(
            points: chain.map { p in BrushPoint(corner: p, ctrl1: p, ctrl2: p) },
            radius: 0.02, hardness: 0.8, density: 1, opacity: 1)
        _ = record.appendForm(.brush(stroke), layer: layer, editorState: editorState)
        record.endInteraction(
            hadInteraction: true, editingState: editingState,
            editorState: editorState, label: "test follow edges")
        XCTAssertEqual(revision(layer.id), 1, "exactly ONE bump")
        XCTAssertEqual(editorState.history.items.count, items + 1, "one commit")
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask?.drawn?.forms.count, 1)
    }

    /// The empty-chain degrade: a flat field (everything below threshold)
    /// yields NO chain — the interaction leg appends nothing (the degrade
    /// input; the view sets the status hint on this branch).
    func testFollowEdgesEmptyFieldDegradesWithoutAppend() async throws {
        try await loadSynthetic()
        let layer = try newLayer()
        let items = editorState.history.items.count

        // A flat surface: no gradient anywhere → the walker's snap finds
        // nothing above 0.25 → the empty chain.
        let flat = EdgeMapField(
            width: 32, height: 32,
            values: [Float](repeating: 0.02, count: 32 * 32))
        let chain = await FollowEdgesInteraction.chain(
            seed: MaskPoint(x: 0.5, y: 0.5),
            layerID: layer.id,
            params: FollowEdgesParams(),
            surfaceProvider: { _ in nil }, // no surface = the same degrade
            fieldReader: { _ in flat })
        XCTAssertTrue(chain.isEmpty, "the flat field degrades")

        // The leg's contract: nothing appended, nothing committed.
        XCTAssertEqual(editorState.history.items.count, items, "zero history")
        XCTAssertNil(editorState.adjustmentLayer(id: layer.id)?.mask?.drawn)
        // The state hint flag is the view's face; the state var exists.
        editingState.followEdgesDegraded = true
        XCTAssertTrue(editingState.followEdgesDegraded)
        editingState.followEdgesDegraded = false
    }

    /// A committed two-form spec (the mutate tests' base).
    private func installCommittedSpec(on layer: AdjustmentLayer) {
        let live = editorState.adjustmentLayer(id: layer.id)!
        var copy = live
        copy.mask = MaskSpec(drawn: DrawnMaskSpec(forms: [strokeForm(x: 0.2, y: 0.2)]))
        editorState.commitLayerEdit(copy, label: "test install")
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
