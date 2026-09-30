@testable import Lightamer
import CoreImage
@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// NodeGraphCommandTests (Plan M2-4-1 T2, AC2) — the seven graph commands:
//
//   Core pure-transform faces (per command, the lock/clamp/payload matrix):
//     • addCleanGrade — append + before-anchor + single-source name
//     • removeGradeAndBridge — removal IS the bridge
//     • reconnectGrade — reorder + clamp (negative / past-end)
//     • renameGrade / setGradeEnabled / setGradeMix — field writes
//     • setGradeMix clamp 0...1 (D5)
//     • insertGradeFromJSON — BYTE restoration (id/paramsData/mask) + the
//       retouch-payload refusal (badPayload)
//     • endpoint locks (develop / drt) = typed lockedNode; retouch ids =
//       notAGrade; unknown ids = nodeNotFound
//     • purity: apply never mutates the input stack
//
//   App shell faces (EditorState instance — checker E2 → LightamerTestsApp):
//     • apply lands EXACTLY ONE history item per command; undo restores the
//       pre-command stack layer-for-layer; redo preserves UUIDs (M2NODE-02)
//     • lockedNode is silently intercepted (no toast, stack unchanged)
//
//   E4 pixel gate: setGradeMix(0) composite output == the same layer
//   disabled (bypass) composite output, tolerance 0 (−0/+0 fold identically
//   through the 8-bit display tail — 0x00 both sides; the LayerComposite
//   CPU-comparison precedent).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class NodeGraphCommandTests: XCTestCase {

    // ── Fixtures ──

    /// Canonical JSON for byte comparisons (sortedKeys): the modern
    /// Foundation JSONEncoder emits keyed-container properties in
    /// dictionary order (unstable across encode calls), so byte-equality
    /// faces MUST pin the ordering (the sidecar's own D-S2 convention).
    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private func makeStack(layers: [AdjustmentLayer] = []) -> LayerStack {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        for layer in layers { stack.addAdjustment(layer) }
        return stack
    }

    private func grade(
        name: String, opacity: Float = 1.0, enabled: Bool = true,
        chain: [ModuleInstance] = []
    ) -> AdjustmentLayer {
        AdjustmentLayer(name: name, opacity: opacity, enabled: enabled, chain: chain)
    }

    /// The three-grade working stack (A bottom → C top).
    private func threeGrades() -> (LayerStack, [UUID]) {
        let a = grade(name: "A")
        let b = grade(name: "B")
        let c = grade(name: "C")
        let stack = makeStack(layers: [a, b, c])
        return (stack, [a.id, b.id, c.id])
    }

    /// Value-face layer comparison (Layer is a class — compare content).
    private func assertLayersEqual(
        _ lhs: AdjustmentLayer, _ rhs: AdjustmentLayer, _ label: String
    ) {
        XCTAssertEqual(lhs.id, rhs.id, "\(label): id")
        XCTAssertEqual(lhs.name, rhs.name, "\(label): name")
        XCTAssertEqual(lhs.enabled, rhs.enabled, "\(label): enabled")
        XCTAssertEqual(lhs.opacity, rhs.opacity, "\(label): opacity")
        XCTAssertEqual(lhs.blendMode, rhs.blendMode, "\(label): blendMode")
        XCTAssertEqual(lhs.chain, rhs.chain, "\(label): chain records")
        XCTAssertEqual(lhs.mask, rhs.mask, "\(label): mask")
    }

    private func assertStacksEqual(
        _ lhs: LayerStack, _ rhs: LayerStack, _ label: String
    ) {
        let left = lhs.compositeLayers
        let right = rhs.compositeLayers
        XCTAssertEqual(left.count, right.count, "\(label): grade count")
        for (a, b) in zip(left, right) {
            assertLayersEqual(a, b, label)
        }
    }

    // ── 1: addCleanGrade ──

    func testAddCleanGradeAppendsIdentityGradeOnTop() throws {
        let (stack, ids) = threeGrades()
        let result = try NodeGraphCommand.addCleanGrade(before: nil).apply(to: stack)

        XCTAssertEqual(result.compositeLayers.count, 4)
        XCTAssertEqual(
            result.compositeLayers.prefix(3).map(\.id), ids,
            "existing grades untouched")
        let added = try XCTUnwrap(result.compositeLayers.last)
        XCTAssertEqual(added.name, "Color Grade 4", "single-source ordinal name")
        XCTAssertTrue(added.chain.isEmpty, "the M2-4 identity = EMPTY chain")
        XCTAssertTrue(added.enabled)
        XCTAssertEqual(added.opacity, 1)
        XCTAssertEqual(added.blendMode, .normal)
    }

    func testAddCleanGradeInsertsBelowTheAnchor() throws {
        let (stack, ids) = threeGrades()
        let result = try NodeGraphCommand.addCleanGrade(before: ids[1]).apply(to: stack)

        XCTAssertEqual(result.compositeLayers.map(\.name), ["A", "Color Grade 4", "B", "C"])
        // The develop anchor = bottom; the drt anchor = top.
        let bottom = try NodeGraphCommand.addCleanGrade(
            before: stack.baseLayer.id).apply(to: stack)
        XCTAssertEqual(bottom.compositeLayers.first?.name, "Color Grade 4")
        let top = try NodeGraphCommand.addCleanGrade(
            before: PipelineDocument.displayTransformNodeID).apply(to: stack)
        XCTAssertEqual(top.compositeLayers.last?.name, "Color Grade 4")
        // The default-name sweep never reuses an existing name.
        let swept = try NodeGraphCommand.addCleanGrade(before: nil).apply(to: bottom)
        XCTAssertEqual(swept.compositeLayers.last?.name, "Color Grade 5")
    }

    func testAddCleanGradeUnknownAnchorIsTypedNotFound() {
        let (stack, _) = threeGrades()
        let unknown = UUID()
        XCTAssertThrowsError(
            try NodeGraphCommand.addCleanGrade(before: unknown).apply(to: stack)
        ) { error in
            XCTAssertEqual(error as? NodeGraphError, .nodeNotFound(unknown))
        }
    }

    // ── 2: removeGradeAndBridge ──

    func testRemoveGradeAndBridgeRemovesOnlyTheTarget() throws {
        let (stack, ids) = threeGrades()
        let result = try NodeGraphCommand.removeGradeAndBridge(id: ids[1]).apply(to: stack)
        XCTAssertEqual(result.compositeLayers.map(\.name), ["A", "C"])
        XCTAssertEqual(
            result.compositeLayers.map(\.id), [ids[0], ids[2]],
            "survivors keep their identities (the linear bridge is free)")
    }

    // ── 3: reconnectGrade ──

    func testReconnectGradeMovesWithinTheChain() throws {
        let (stack, ids) = threeGrades()
        // C (top) → position 0 (bottom).
        let result = try NodeGraphCommand.reconnectGrade(id: ids[2], toPosition: 0)
            .apply(to: stack)
        XCTAssertEqual(result.compositeLayers.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(
            result.compositeLayers[0].id, ids[2],
            "reconnect preserves the layer UUID (M2NODE-02)")
    }

    func testReconnectGradeClampsOutOfRangePositions() throws {
        let (stack, ids) = threeGrades()
        // Negative → clamps to bottom; past-end → clamps to top.
        let low = try NodeGraphCommand.reconnectGrade(id: ids[2], toPosition: -7)
            .apply(to: stack)
        XCTAssertEqual(low.compositeLayers.map(\.name), ["C", "A", "B"])
        let high = try NodeGraphCommand.reconnectGrade(id: ids[0], toPosition: 99)
            .apply(to: stack)
        XCTAssertEqual(high.compositeLayers.map(\.name), ["B", "C", "A"])
    }

    // ── 4: rename / enable / mix ──

    func testRenameEnableMixWriteTheirFields() throws {
        let (stack, ids) = threeGrades()
        let renamed = try NodeGraphCommand.renameGrade(id: ids[0], to: "Teal")
            .apply(to: stack)
        XCTAssertEqual(renamed.compositeLayers[0].name, "Teal")

        let disabled = try NodeGraphCommand.setGradeEnabled(id: ids[1], enabled: false)
            .apply(to: stack)
        XCTAssertEqual(disabled.compositeLayers[1].enabled, false)

        let mixed = try NodeGraphCommand.setGradeMix(id: ids[2], mix: 0.4)
            .apply(to: stack)
        XCTAssertEqual(mixed.compositeLayers[2].opacity, 0.4)
    }

    func testSetGradeMixClampsToUnitRange() throws {
        let (stack, ids) = threeGrades()
        let low = try NodeGraphCommand.setGradeMix(id: ids[0], mix: -0.7).apply(to: stack)
        XCTAssertEqual(low.compositeLayers[0].opacity, 0)
        let high = try NodeGraphCommand.setGradeMix(id: ids[1], mix: 3.5).apply(to: stack)
        XCTAssertEqual(high.compositeLayers[1].opacity, 1)
    }

    // ── 5: insertGradeFromJSON ──

    /// A grade with chain bytes + a drawn mask — the byte-restoration probe.
    private func payloadGrade() -> AdjustmentLayer {
        let record = ModuleInstance(
            module: TestGainModule.self, multiPriority: 5,
            params: TestGainModule.Params(gain: 1.7))
        var spec = MaskSpec()
        spec.drawn = DrawnMaskSpec(forms: [
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5),
                radiusX: 0.2, radiusY: 0.3,
                rotationDegrees: 15, border: 0.1))),
        ])
        let layer = grade(name: "Payload", opacity: 0.8, chain: [record])
        layer.mask = spec
        return layer
    }

    func testInsertFromJSONRestoresBytesVerbatim() throws {
        let (stack, _) = threeGrades()
        let payload = payloadGrade()
        let data = try Self.canonicalEncoder.encode(SidecarLayerRecord(payload))

        let result = try NodeGraphCommand.insertGradeFromJSON(data: data, position: 1)
            .apply(to: stack)
        XCTAssertEqual(result.compositeLayers.count, 4)
        let restored = try XCTUnwrap(result.compositeLayers.first { $0.id == payload.id })

        // BYTE restoration: the same record re-encodes to the SAME JSON
        // bytes (id + paramsData + mask ride verbatim — no re-minting).
        let restoredData = try Self.canonicalEncoder.encode(SidecarLayerRecord(restored))
        XCTAssertEqual(restoredData, data, "round-tripped record bytes identical")
        XCTAssertEqual(restored.id, payload.id)
        XCTAssertEqual(restored.chain, payload.chain)
        XCTAssertEqual(restored.chain.first?.paramsData, payload.chain.first?.paramsData)
        XCTAssertEqual(restored.mask, payload.mask)
        XCTAssertEqual(restored.opacity, 0.8)
        // Position honored (inserted at composite index 1).
        XCTAssertEqual(
            result.compositeLayers.map(\.name), ["A", "Payload", "B", "C"])
    }

    func testRetouchPayloadIsRefusedAsBadPayload() throws {
        let (stack, _) = threeGrades()
        let retouch = RetouchLayer(name: "Heal")
        let data = try Self.canonicalEncoder.encode(SidecarLayerRecord(retouch))
        XCTAssertThrowsError(
            try NodeGraphCommand.insertGradeFromJSON(data: data, position: 0)
                .apply(to: stack)
        ) { error in
            XCTAssertEqual(error as? NodeGraphError, .badPayload)
        }
        // Garbage bytes refuse with the same typed case.
        XCTAssertThrowsError(
            try NodeGraphCommand.insertGradeFromJSON(
                data: Data("not json".utf8), position: 0).apply(to: stack)
        ) { error in
            XCTAssertEqual(error as? NodeGraphError, .badPayload)
        }
        // Negative positions are malformed (typed), not clamped.
        XCTAssertThrowsError(
            try NodeGraphCommand.insertGradeFromJSON(data: data, position: -1)
                .apply(to: stack)
        ) { error in
            XCTAssertEqual(error as? NodeGraphError, .badPosition(-1))
        }
    }

    // ── 6: the lock matrix ──

    func testEndpointLocksInterceptRemoveAndReconnect() {
        let (stack, _) = threeGrades()
        let locked = [stack.baseLayer.id, PipelineDocument.displayTransformNodeID]
        for id in locked {
            XCTAssertThrowsError(
                try NodeGraphCommand.removeGradeAndBridge(id: id).apply(to: stack)
            ) { error in
                XCTAssertEqual(error as? NodeGraphError, .lockedNode(id))
            }
            XCTAssertThrowsError(
                try NodeGraphCommand.reconnectGrade(id: id, toPosition: 0).apply(to: stack)
            ) { error in
                XCTAssertEqual(error as? NodeGraphError, .lockedNode(id))
            }
        }
        // The stack is untouched by the refused commands (value semantics).
        XCTAssertEqual(stack.compositeLayers.count, 3)
    }

    func testRetouchLayerIdIsNotAGrade() {
        var stack = threeGrades().0
        let retouch = RetouchLayer(name: "Heal")
        stack.addAdjustment(retouch)
        XCTAssertThrowsError(
            try NodeGraphCommand.removeGradeAndBridge(id: retouch.id).apply(to: stack)
        ) { error in
            XCTAssertEqual(error as? NodeGraphError, .notAGrade(retouch.id))
        }
    }

    func testUnknownIdsAreTypedNotFound() {
        let (stack, _) = threeGrades()
        let unknown = UUID()
        for command in [
            NodeGraphCommand.removeGradeAndBridge(id: unknown),
            .renameGrade(id: unknown, to: "X"),
            .setGradeEnabled(id: unknown, enabled: false),
            .setGradeMix(id: unknown, mix: 0.5),
        ] {
            XCTAssertThrowsError(try command.apply(to: stack)) { error in
                XCTAssertEqual(error as? NodeGraphError, .nodeNotFound(unknown))
            }
        }
    }

    // ── 7: purity (value semantics) ──

    func testApplyIsPureOverTheInputStack() throws {
        let (stack, ids) = threeGrades()
        let before = try Self.canonicalEncoder.encode(SidecarLayerStackRecord(stack))
        _ = try NodeGraphCommand.addCleanGrade(before: nil).apply(to: stack)
        _ = try NodeGraphCommand.setGradeMix(id: ids[0], mix: 0.1).apply(to: stack)
        _ = try NodeGraphCommand.removeGradeAndBridge(id: ids[1]).apply(to: stack)
        let after = try Self.canonicalEncoder.encode(SidecarLayerStackRecord(stack))
        XCTAssertEqual(before, after, "apply must never mutate the input stack")
    }

    // ── 8: the App shell (EditorState) — one commit + undo/redo round-trip ──

    /// An EditorState with a committed-instance seed (the structure-commit
    /// placeholder) + a three-grade stack built through the REAL App face
    /// (`addAdjustmentLayer` — each add lands its own structure history
    /// item, so the undo/redo snapshot chain is the production shape).
    private func makeEditorState() -> (EditorState, [UUID]) {
        let editorState = EditorState()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        _ = editorState.addAdjustmentLayer()
        _ = editorState.addAdjustmentLayer()
        _ = editorState.addAdjustmentLayer()
        let ids = (editorState.layerStack?.compositeLayers ?? []).map(\.id)
        return (editorState, ids)
    }

    /// The seven command builders — each receives the row's OWN stack ids
    /// (fresh per row; ids never cross states).
    private func commandMatrix(
        ids: [UUID], payloadData: Data
    ) -> [NodeGraphCommand] {
        [
            .addCleanGrade(before: nil),
            .removeGradeAndBridge(id: ids[1]),
            .reconnectGrade(id: ids[2], toPosition: 0),
            .renameGrade(id: ids[0], to: "Renamed"),
            .setGradeEnabled(id: ids[1], enabled: false),
            .setGradeMix(id: ids[2], mix: 0.3),
            .insertGradeFromJSON(data: payloadData, position: 1),
        ]
    }

    func testApplyCommitsOneItemAndUndoRedoPreservesIdentity() throws {
        let payload = payloadGrade()
        let payloadData = try Self.canonicalEncoder.encode(SidecarLayerRecord(payload))

        // One FRESH editor state per row, ids from THAT state (the
        // structure history truncates the redo tail on commit, so a shared
        // state would make the item-count delta row-dependent; a clean
        // state keeps the D-H1 count assertion exact: 3 seeded adds → +1
        // per command).
        for index in 0..<7 {
            let (editorState, ids) = makeEditorState()
            let stack = try XCTUnwrap(editorState.layerStack)
            let command = commandMatrix(ids: ids, payloadData: payloadData)[index]
            let preCount = editorState.history.items.count
            let preStack = try XCTUnwrap(editorState.layerStack)
            let preEncoded = try Self.canonicalEncoder.encode(SidecarLayerStackRecord(preStack))

            editorState.apply(command)

            // EXACTLY ONE new history item per command (D-H1 discipline).
            XCTAssertEqual(
                editorState.history.items.count, preCount + 1,
                "\(command): one structure commit per command")
            let postStack = try XCTUnwrap(editorState.layerStack)
            let postEncoded = try Self.canonicalEncoder.encode(SidecarLayerStackRecord(postStack))
            XCTAssertNotEqual(
                postEncoded, preEncoded, "\(command): the stack must move")

            // UNDO: the stack returns to the pre-command state, layer for
            // layer (structure + fields).
            XCTAssertTrue(editorState.performUndo(), "\(command): undo must step back")
            let undone = try XCTUnwrap(editorState.layerStack)
            assertStacksEqual(undone, preStack, "\(command): undo restores the stack")

            // REDO: the UUIDs ride the snapshot verbatim (M2NODE-02 保
            // NodeId) — the redo state equals the post-command state.
            XCTAssertTrue(editorState.performRedo(), "\(command): redo must step forward")
            let redone = try XCTUnwrap(editorState.layerStack)
            let redoneEncoded = try Self.canonicalEncoder.encode(SidecarLayerStackRecord(redone))
            if redoneEncoded != postEncoded {
                print("DEBUG-REDIFF post=\(String(decoding: postEncoded, as: UTF8.self))")
                print("DEBUG-REDIFF redo=\(String(decoding: redoneEncoded, as: UTF8.self))")
            }
            XCTAssertEqual(
                redoneEncoded, postEncoded,
                "\(command): redo restores the post-command stack byte-for-byte")

            if case .insertGradeFromJSON = command {
                let inserted = redone.compositeLayers.first { $0.id == payload.id }
                XCTAssertNotNil(inserted, "\(command): the inserted identity survives")
            }
        }
    }

    func testLockedNodeApplyIsSilentlyIntercepted() throws {
        let (editorState, _) = makeEditorState()
        let stack = try XCTUnwrap(editorState.layerStack)
        let preEncoded = try Self.canonicalEncoder.encode(SidecarLayerStackRecord(stack))
        let preCount = editorState.history.items.count

        // Both endpoint locks — no crash, no toast, no history item, no
        // stack movement (the silent-interception face).
        for id in [stack.baseLayer.id, PipelineDocument.displayTransformNodeID] {
            editorState.apply(.removeGradeAndBridge(id: id))
            editorState.apply(.reconnectGrade(id: id, toPosition: 0))
        }
        XCTAssertEqual(editorState.history.items.count, preCount)
        XCTAssertEqual(
            try Self.canonicalEncoder.encode(SidecarLayerStackRecord(try XCTUnwrap(
                editorState.layerStack))),
            preEncoded)
        XCTAssertNil(editorState.toast, "lockedNode must NOT toast")
    }

    // ── 9: E4 — setGradeMix(0) ≡ bypass (pixel-level, tolerance 0) ──

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeRegistry() async throws -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    /// A spatially-varying synthetic image (the LayerComposite precedent).
    private func makeImage(width: Int = 48, height: Int = 32) -> DecodedImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                pixels[o + 0] = 0.1 + 0.7 * Float(x) / Float(width - 1)
                pixels[o + 1] = 0.2 + 0.5 * Float(y) / Float(height - 1)
                pixels[o + 2] = 0.3 + 0.3 * Float(x + y) / Float(width + height - 2)
                pixels[o + 3] = 1.0
            }
        }
        let bitmap = pixels.withUnsafeBytes { Data($0) }
        let ci = CIImage(
            bitmapData: bitmap,
            bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
            size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: WorkingSpace.colorSpace)
        return DecodedImage(
            ciImage: ci,
            rawTech: RAWTechnicalParams(blackLevel: 0.0),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    /// L014 fence + raw readback (the LayerCompositeTests CPU probe).
    private func rawBytes(_ texture: any MTLTexture, metal: MetalContext) -> [UInt8] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var bytes = [UInt8](
            repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return bytes
    }

    private func composite(
        _ image: DecodedImage, stack: LayerStack, registry: ModuleRegistry,
        metal: MetalContext
    ) async throws -> (any MTLTexture) {
        let base = await makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        return try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: stack, registry: registry, resolution: .preview,
            cache: PipeCache(), metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview).output
    }

    func testSetGradeMixZeroIsPixelIdenticalToBypass() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()

        // The SAME stack twice: once with the layer's mix commanded to 0
        // through the graph command, once with the layer disabled — the
        // driver must see identical composites (mix 0 ≡ bypass, checker E4).
        let gainLayer = { AdjustmentLayer(
            name: "Gain",
            opacity: 1,
            chain: [ModuleInstance(
                module: TestGainModule.self, multiPriority: 5,
                params: TestGainModule.Params(gain: 2.0))])
        }

        let mixZeroStack = makeStack(layers: [gainLayer()])
        let mixZeroID = mixZeroStack.compositeLayers[0].id
        let mixZero = try NodeGraphCommand.setGradeMix(id: mixZeroID, mix: 0)
            .apply(to: mixZeroStack)

        let bypassStack = makeStack(layers: [gainLayer()])
        let bypassID = bypassStack.compositeLayers[0].id
        let bypass = try NodeGraphCommand.setGradeEnabled(id: bypassID, enabled: false)
            .apply(to: bypassStack)

        let mixZeroBytes = rawBytes(
            try await composite(image, stack: mixZero, registry: registry, metal: metal),
            metal: metal)
        let bypassBytes = rawBytes(
            try await composite(image, stack: bypass, registry: registry, metal: metal),
            metal: metal)
        XCTAssertEqual(
            mixZeroBytes, bypassBytes,
            "setGradeMix(0) composite == disabled-layer bypass composite (tolerance 0)")

        // Sanity (防空转): the UNMODIFIED layer at mix 1 must actually move
        // pixels — the equality above is not two no-ops comparing.
        let plainStack = makeStack(layers: [gainLayer()])
        let plainBytes = rawBytes(
            try await composite(image, stack: plainStack, registry: registry, metal: metal),
            metal: metal)
        XCTAssertNotEqual(plainBytes, bypassBytes, "the gain layer at mix 1 is visible")
    }
}
