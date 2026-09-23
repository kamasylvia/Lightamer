@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-01 T6 — sidecar v2: the typed layer stack (frozen spelling),
/// v1 document compatibility, the layer-aware drift anchor, the history
/// `stackSnapshot` payload, and the per-layer unknown-op degrade.
///
/// Round-trip contract: 3-layer stack → write → read → params byte-equal +
/// UUID identity + RENDER byte-identity (L014 fence, L020 ③).
final class Phase6SidecarTests: XCTestCase {

    // ── Fixtures ──

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeRegistry() async -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    private func gainRecord(_ gain: Float, priority: Int = 0) -> ModuleInstance {
        ModuleInstance(
            module: TestGainModule.self, multiPriority: priority,
            params: TestGainModule.Params(gain: gain))
    }

    /// Three layers: non-default gain chains, distinct opacities, one with
    /// a non-normal… no — normal blend only (the degenerate composite's
    /// precondition); one carries the mask shell.
    private func makeStack() -> LayerStack {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = AdjustmentLayer(name: "Lift", opacity: 1.0, chain: [gainRecord(1.5)])
        let b = AdjustmentLayer(name: "Cut", opacity: 0.7, chain: [gainRecord(0.6)])
        b.mask = MaskSpec()
        let c = AdjustmentLayer(name: "Push", opacity: 1.0, chain: [
            gainRecord(2.0), gainRecord(0.9, priority: 1),
        ])
        c.blendOptions = [.reverse]
        stack.addAdjustment(a)
        stack.addAdjustment(b)
        stack.addAdjustment(c)
        return stack
    }

    private func makeSidecar(stack: LayerStack) -> LightamerSidecar {
        let decodeHash: UInt64 = 0x1234_5678_9ABC_DEF0
        let hash = HistoryHash.hash(
            stack: HistoryStack(), decodeParamsHash: decodeHash,
            layerSnapshot: LayerStackSnapshot(stack))
        return LightamerSidecar(
            imageID: Self.imageID, decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash, instances: [],
            history: HistoryStack(), historyHash: hash, appVersion: "0.1.0",
            layerStack: SidecarLayerStackRecord(stack))
    }

    private static let imageID = UUID()

    /// L014 fence + raw plane read.
    private static func planeBytes(
        _ texture: any MTLTexture, metal: MetalContext
    ) -> [UInt8] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return bytes
    }

    // ── 1. The 3-layer round trip ──

    /// write → read → (a) parameters byte-equal, UUID identity, blend/
    /// opacity/mask survive; (b) the restored stack's composite render is
    /// byte-identical to the original's.
    func testThreeLayerStackRoundTripAndRenderIdentity() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let stack = makeStack()
        let sidecar = makeSidecar(stack: stack)

        XCTAssertEqual(sidecar.schemaVersion, 2, "writers emit the current version")
        XCTAssertFalse(sidecar.driftDetected, "write-time hash must be self-consistent")

        let data = try JSONEncoder().encode(sidecar)
        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: data)

        // (a) Parameter-level fidelity.
        let originalLayers = stack.compositeLayers
        let restored = try XCTUnwrap(decoded.layerStack).adjustmentLayers
        XCTAssertEqual(restored.count, 3)
        for (original, back) in zip(originalLayers, restored) {
            XCTAssertEqual(back.id, original.id, "NDE-1: UUID identity survives")
            XCTAssertEqual(back.name, original.name)
            XCTAssertEqual(back.opacity, original.opacity)
            XCTAssertEqual(back.blendMode, original.blendMode)
            XCTAssertEqual(back.blendOptions, original.blendOptions)
            XCTAssertEqual(back.isVisible, original.isVisible)
            XCTAssertEqual(back.enabled, original.enabled)
            XCTAssertEqual(back.mask, original.mask, "mask shell survives")
            XCTAssertEqual(back.chain.count, original.chain.count)
            for (recordOriginal, recordBack) in zip(original.chain, back.chain) {
                XCTAssertEqual(recordBack.id, recordOriginal.id)
                XCTAssertEqual(recordBack.paramsData, recordOriginal.paramsData,
                               "params bytes byte-equal (ONE-WAY lock)")
                XCTAssertEqual(recordBack.paramsHash, recordOriginal.paramsHash,
                               "D-H4 atom verbatim")
            }
        }
        XCTAssertTrue(decoded.driftDetected == false, "restored document is not drift")

        // (b) Render-level fidelity: composite(original) == composite(restored).
        let image = try makeGradientImage()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        var restoredStack = LayerStack(baseLayer: BackgroundLayer())
        for layer in restored { restoredStack.addAdjustment(layer) }

        let originalRender = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: stack, registry: registry, resolution: .preview,
            cache: PipeCache(), metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview)
        let restoredRender = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: restoredStack, registry: registry, resolution: .preview,
            cache: PipeCache(), metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview)

        let originalBytes = Self.planeBytes(originalRender.output, metal: metal)
        let restoredBytes = Self.planeBytes(restoredRender.output, metal: metal)
        XCTAssertEqual(originalBytes.count, restoredBytes.count)
        XCTAssertGreaterThan(originalBytes.count, 0, "防空转 guard")
        XCTAssertTrue(originalBytes.elementsEqual(restoredBytes),
                      "round-trip render must be byte-identical")
    }

    // ── 1b. Plan 06-04 — the three-payload mask round trip ──

    /// A 3-layer stack where one layer's mask carries ALL THREE payload
    /// classes (drawn group ⊗ parametric ⊓ raster PNG): params byte-equal,
    /// UUID identity, the raster REF survives verbatim, and the restored
    /// stack's composite render is byte-identical (L014 fence; the raster
    /// leg loads through the REAL store from a temp masks directory).
    func testThreePayloadMaskRoundTripAndRenderIdentity() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()

        // Bake a small raster mask PNG into a temp masks directory.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lra-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let w, h: Int
        (w, h) = (24, 16)
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let rasterSource = metal.device.makeTexture(descriptor: d)!
        var floats = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { floats[y * w + x] = Float(x) / Float(w - 1) } }
        floats.withUnsafeBytes {
            rasterSource.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 4)
        }
        let ref = try await RasterMaskStore.bake(
            plane: rasterSource, directory: dir, fileName: "group-mask.png",
            invert: false, metal: metal)

        let ellipseID = UUID()
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = AdjustmentLayer(name: "Lift", opacity: 1.0, chain: [gainRecord(1.5)])
        let b = AdjustmentLayer(name: "Cut", opacity: 0.7, chain: [gainRecord(0.6)])
        b.mask = MaskSpec(drawn: DrawnMaskSpec(
            forms: [
                MaskForm(id: ellipseID, kind: .ellipse(EllipseForm(
                    center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.2, radiusY: 0.2,
                    rotationDegrees: 0, border: 0))),
            ],
            group: MaskGroupSpec(items: [
                MaskGroupItem(formID: ellipseID, op: .union, inverted: false, opacity: 1),
            ])))
        b.mask?.parametric = ParametricMask(
            domain: .jzczhz,
            channels: [.init(channel: 9, curve: .init(points: [0.05, 0.1, 0.5, 0.8]))])
        b.mask?.raster = ref
        let c = AdjustmentLayer(name: "Push", opacity: 1.0, chain: [gainRecord(2.0)])
        stack.addAdjustment(a)
        stack.addAdjustment(b)
        stack.addAdjustment(c)

        let sidecar = makeSidecar(stack: stack)
        let data = try JSONEncoder().encode(sidecar)
        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: data)
        let originalLayers = stack.compositeLayers
        let restored = try XCTUnwrap(decoded.layerStack).adjustmentLayers
        XCTAssertEqual(restored.count, 3)
        let restoredB = restored[1]
        XCTAssertEqual(restoredB.mask?.drawn?.group?.items.first?.op, .union)
        XCTAssertEqual(restoredB.mask?.parametric?.domain, .jzczhz)
        XCTAssertEqual(restoredB.mask?.raster, ref, "the raster REF survives verbatim")
        XCTAssertEqual(restoredB.mask, originalLayers[1].mask, "the full payload survives")

        // Render fidelity with the raster leg live (both runs load the
        // SAME PNG through the store).
        let image = try makeGradientImage()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        var restoredStack = LayerStack(baseLayer: BackgroundLayer())
        for layer in restored { restoredStack.addAdjustment(layer) }

        let originalRender = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: stack, registry: registry, resolution: .preview,
            cache: PipeCache(), metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview, maskDirectory: dir)
        let restoredRender = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: restoredStack, registry: registry, resolution: .preview,
            cache: PipeCache(), metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview, maskDirectory: dir)

        let originalBytes = Self.planeBytes(originalRender.output, metal: metal)
        let restoredBytes = Self.planeBytes(restoredRender.output, metal: metal)
        XCTAssertEqual(originalBytes.count, restoredBytes.count)
        XCTAssertGreaterThan(originalBytes.count, 0, "防空转 guard")
        XCTAssertTrue(originalBytes.elementsEqual(restoredBytes),
                      "three-payload round-trip render must be byte-identical")
    }

    // ── 2. v1 document compatibility ──

    /// A v1 document (the String layerStack reservation, always null) and
    /// a v1-shaped document with the key absent entirely both decode with
    /// `layerStack == nil` — the 02-06 reader contract is a strict prefix
    /// of the v2 shape.
    func testV1DocumentsDecodeWithNilLayerStack() throws {
        // The hash-consistent way to build a v1 sample: encode a REAL
        // v2 document without layers, then downgrade its schemaVersion —
        // byte-for-byte what a v1 writer produced (minus the null key).
        let decodeHash: UInt64 = 1311768467463790320
        let v2 = LightamerSidecar(
            imageID: Self.imageID, decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash, instances: [],
            history: HistoryStack(),
            historyHash: HistoryHash.hash(stack: HistoryStack(), decodeParamsHash: decodeHash),
            appVersion: "0.1.0")
        let downgraded = String(
            data: try JSONEncoder().encode(v2), encoding: .utf8)!
            .replacingOccurrences(of: "\"schemaVersion\":2", with: "\"schemaVersion\":1")
        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: Data(downgraded.utf8))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertNil(decoded.layerStack, "v1 String reservation decodes to nil")
        XCTAssertFalse(decoded.driftDetected,
                       "the downgraded v1 document stays drift-free")

        // A HAND-WRITTEN v1 sample (the null layerStack + arbitrary hash):
        // decode tolerance only — the drift verdict is meaningless for an
        // arbitrary hash, so it is deliberately not asserted here.
        let v1JSON = """
        {
          "schemaVersion" : 1,
          "appVersion" : "0.1.0",
          "decoderVersionUsed" : "v8",
          "decodeParamsHash" : "1311768467463790320",
          "imageID" : "\(Self.imageID.uuidString)",
          "instances" : [ ],
          "history" : { "items" : [ ], "position" : -1 },
          "historyHash" : "42",
          "layerStack" : null
        }
        """
        let handWritten = try JSONDecoder().decode(LightamerSidecar.self, from: Data(v1JSON.utf8))
        XCTAssertEqual(handWritten.schemaVersion, 1)
        XCTAssertNil(handWritten.layerStack)

        // The key absent entirely (hand-edited / minimized writers).
        let minimalJSON = """
        {
          "schemaVersion" : 1,
          "appVersion" : "0.1.0",
          "decoderVersionUsed" : "v8",
          "decodeParamsHash" : "1311768467463790320",
          "imageID" : "\(Self.imageID.uuidString)",
          "instances" : [ ],
          "history" : { "items" : [ ], "position" : -1 },
          "historyHash" : "42"
        }
        """
        let minimal = try JSONDecoder().decode(LightamerSidecar.self, from: Data(minimalJSON.utf8))
        XCTAssertNil(minimal.layerStack)
    }

    /// A v2 writer with NO layers omits the typed record — decode yields
    /// nil and the shape stays mutually readable with v1 consumers.
    func testV2DocumentWithoutLayersOmitsRecord() throws {
        let decodeHash: UInt64 = 42
        let sidecar = LightamerSidecar(
            imageID: Self.imageID, decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash, instances: [],
            history: HistoryStack(),
            historyHash: HistoryHash.hash(stack: HistoryStack(), decodeParamsHash: decodeHash),
            appVersion: "0.1.0")
        let data = try JSONEncoder().encode(sidecar)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("layers"), "no layer payload emitted when nil")
        let decoded = try JSONDecoder().decode(LightamerSidecar.self, from: data)
        XCTAssertNil(decoded.layerStack)
        XCTAssertFalse(decoded.driftDetected)
    }

    // ── 3. Layer-aware drift anchor ──

    /// Tampering with a layer chain byte flips the drift verdict even
    /// though the global instance set is untouched; and the tamper target
    /// is compared against REAL recomputation (compared > 0 analog: the
    /// verdicts differ between intact and tampered documents).
    func testLayerAwareDriftDetection() throws {
        let stack = makeStack()
        let sidecar = makeSidecar(stack: stack)
        XCTAssertFalse(sidecar.driftDetected)

        // Tamper 1: a LAYER PROP (opacity) — the explicit prop fold flips.
        var tampered = sidecar
        var tamperedLayers = tampered.layerStack?.layers ?? []
        XCTAssertGreaterThan(tamperedLayers.count, 0, "防空转 guard")
        tamperedLayers[0].opacity = 0.42
        tampered.layerStack = SidecarLayerStackRecord(layers: tamperedLayers)
        XCTAssertTrue(tampered.driftDetected,
                      "a layer-prop tamper IS drift under the layer-aware anchor")

        // Tamper 2: a layer chain's PARAM BYTES (the D-H4 fold source).
        var paramsTampered = sidecar
        var layers2 = paramsTampered.layerStack?.layers ?? []
        var mutatedRecord = layers2[0].chain[0].instance
        mutatedRecord.paramsData = Data("{\"gain\":9.0}".utf8)
        layers2[0].chain[0] = SidecarInstanceRecord(mutatedRecord)
        paramsTampered.layerStack = SidecarLayerStackRecord(layers: layers2)
        XCTAssertTrue(paramsTampered.driftDetected,
                      "a layer-params tamper IS drift")

        // Structural tamper: dropping a layer flips the verdict too.
        var structurallyTampered = sidecar
        structurallyTampered.layerStack = SidecarLayerStackRecord(
            layers: Array(sidecar.layerStack?.layers.dropFirst() ?? []))
        XCTAssertTrue(structurallyTampered.driftDetected,
                      "dropping a layer IS drift")
    }

    /// The history item payload: a structure edit's stackSnapshot survives
    /// the full sidecar round-trip through the SAME frozen layer spelling.
    func testHistoryStackSnapshotRoundTrip() throws {
        var stack = HistoryStack()
        let snapshot = LayerStackSnapshot(makeStack())
        stack.commit(
            gainRecord(1.0), label: "add layer A",
            layerScope: snapshot.layers.first?.id.uuidString,
            stackSnapshot: snapshot)

        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(HistoryStack.self, from: data)
        XCTAssertEqual(decoded, stack, "the runtime Codable path round-trips")
        XCTAssertEqual(decoded.items[0].stackSnapshot, snapshot)

        // The SIDECAR path: decimal-String hashes end to end. NOTE the
        // drift anchor folds the TOP-LEVEL layerStack (the live stack);
        // this document carries layers only inside the history snapshot,
        // so its write-time hash is the no-layer form — self-consistent.
        let decodeHash: UInt64 = 7
        let sidecar = LightamerSidecar(
            imageID: Self.imageID, decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash, instances: [], history: stack,
            historyHash: HistoryHash.hash(stack: stack, decodeParamsHash: decodeHash),
            appVersion: "0.1.0")
        let sidecarData = try JSONEncoder().encode(sidecar)
        let sidecarJSON = String(data: sidecarData, encoding: .utf8) ?? ""
        // Snapshot chain paramsHash values must serialize as decimal
        // Strings in the sidecar (ONE-WAY lock) — regex-level check for a
        // numeric (unquoted) hash anywhere in the document.
        let numericHashRanges = sidecarJSON.ranges(of: /"paramsHash":\d/)
        XCTAssertTrue(numericHashRanges.isEmpty,
                      "snapshot hashes must serialize as decimal Strings in the sidecar")
        XCTAssertFalse(sidecarJSON.isEmpty, "防空转 guard")
        let sidecarBack = try JSONDecoder().decode(LightamerSidecar.self, from: sidecarData)
        XCTAssertEqual(sidecarBack.history.items[0].stackSnapshot, snapshot,
                       "snapshot survives the sidecar projection verbatim")
        XCTAssertFalse(sidecarBack.driftDetected)
    }

    // ── 4. Unknown-op degrade, layer dimension ──

    /// A layer chain carrying an op the current binary cannot build: the
    /// LAYER flips enabled=false (drops out of the composite), its chain
    /// bytes stay verbatim (a future binary restores it), and the unknown
    /// op is reported for the toast.
    func testUnknownOpInLayerChainDegradesLayer() async throws {
        let registry = await makeRegistry()
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let good = AdjustmentLayer(name: "Good", opacity: 1.0, chain: [gainRecord(1.4)])
        let future = AdjustmentLayer(name: "Future", opacity: 1.0, chain: [
            gainRecord(2.0),
            ModuleInstance(
                id: UUID(), opName: "op_from_the_future", multiPriority: 0,
                multiName: "", iopOrder: 50.6, version: 1, enabled: true,
                paramsData: Data("{}".utf8), paramsHash: 42),
        ])
        stack.addAdjustment(good)
        stack.addAdjustment(future)

        let sidecar = makeSidecar(stack: stack)
        let (degraded, unknownOps) = await sidecar.degradedLayerStack(registry: registry)
        XCTAssertEqual(unknownOps, ["op_from_the_future"])
        let records = degraded?.layers ?? []
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records[0].enabled, "the healthy layer stays enabled")
        XCTAssertFalse(records[1].enabled, "the unknown-op layer is disabled")
        XCTAssertEqual(records[1].chain[1].instance.opName, "op_from_the_future")
        XCTAssertEqual(records[1].chain[1].instance.paramsData, Data("{}".utf8),
                       "unknown-op params kept verbatim (never dropped)")
        XCTAssertEqual(records[1].chain[0].instance.enabled, true,
                       "chain records keep their own enabled flags verbatim")
    }

    // ── fixture ──

    private func makeGradientImage(width: Int = 48, height: Int = 32) throws -> DecodedImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                pixels[o + 0] = 0.1 + 0.7 * Float(x) / Float(width - 1)
                pixels[o + 1] = 0.2 + 0.5 * Float(y) / Float(height - 1)
                pixels[o + 2] = 0.3
                pixels[o + 3] = 1.0
            }
        }
        let bitmap = pixels.withUnsafeBytes { Data($0) }
        return DecodedImage(
            ciImage: CIImage(
                bitmapData: bitmap,
                bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
                size: CGSize(width: width, height: height),
                format: .RGBAf, colorSpace: WorkingSpace.colorSpace),
            rawTech: RAWTechnicalParams(blackLevel: 0.0),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plan 06-07 T1 — the retouch kind's sidecar round trip (D-06-07-T1-2
// spelling freeze): `kind: "retouch"` + the OPTIONAL additive `strokes`
// payload (RetouchStroke verbatim; shape = the frozen 06-03 MaskForm
// spellings). Pre-06-07 documents carry neither — decode stays compatible.
// ─────────────────────────────────────────────────────────────────────────────
final class RetouchSidecarTests: XCTestCase {

    private func makeRetouchStack() -> LayerStack {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let fix = RetouchLayer(name: "修复", opacity: 0.8)
        fix.blendOptions = [.reverse]
        fix.append(stroke: RetouchStroke(
            algorithm: .clone,
            form: MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.05, radiusY: 0.04,
                rotationDegrees: 15, border: 0.2))),
            source: MaskPoint(x: 0.4, y: 0.5), opacity: 0.9))
        fix.append(stroke: RetouchStroke(
            algorithm: .heal,
            form: MaskForm(kind: .path(PathForm(
                nodes: [PathNode(
                    corner: MaskPoint(x: 0.2, y: 0.2),
                    ctrl1: MaskPoint(x: 0.21, y: 0.22),
                    ctrl2: MaskPoint(x: 0.19, y: 0.18))],
                border: 0.05))),
            source: MaskPoint(x: 0.3, y: 0.3)))
        fix.append(stroke: RetouchStroke(
            algorithm: .blur,
            form: MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.7, y: 0.7), radiusX: 0.03, radiusY: 0.03,
                rotationDegrees: 0, border: 0))),
            blurRadius: 4.5))
        fix.append(stroke: RetouchStroke(
            algorithm: .fill,
            form: MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.1, y: 0.9), radiusX: 0.02, radiusY: 0.02,
                rotationDegrees: 0, border: 0))),
            fillColor: SIMD3(0.25, 0.5, 0.75)))
        let lift = AdjustmentLayer(name: "Lift", chain: [])
        stack.addAdjustment(lift)
        stack.addAdjustment(fix)
        return stack
    }

    /// The FROZEN spelling table (D-06-07-T1-2): exact JSON keys and value
    /// shapes, asserted against the encoded bytes.
    func testRetouchRecordSpellingIsFrozen() throws {
        let stack = makeRetouchStack()
        let record = SidecarLayerStackRecord(stack)
        let data = try JSONEncoder().encode(record)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
        XCTAssertEqual(layers.count, 2)
        let retouchRecord = try XCTUnwrap(layers[1])
        XCTAssertEqual(retouchRecord["kind"] as? String, "retouch")
        let strokes = try XCTUnwrap(retouchRecord["strokes"] as? [[String: Any]])
        XCTAssertEqual(strokes.count, 4)
        // dt slots verbatim (retouch.c:66-71): clone=1 heal=2 blur=3 fill=4.
        XCTAssertEqual(strokes[0]["algorithm"] as? Int, 1)
        XCTAssertEqual(strokes[1]["algorithm"] as? Int, 2)
        XCTAssertEqual(strokes[2]["algorithm"] as? Int, 3)
        XCTAssertEqual(strokes[3]["algorithm"] as? Int, 4)
        // The shape rides the 06-03 frozen MaskForm spellings.
        XCTAssertNotNil(strokes[0]["form"] as? [String: Any])
        XCTAssertNotNil(strokes[0]["source"] as? [String: Any])
        XCTAssertEqual(strokes[0]["opacity"] as? Double, 0.9)
        XCTAssertEqual(strokes[2]["blurRadius"] as? Double, 4.5)
        XCTAssertEqual(strokes[3]["fillColor"] as? [Double], [0.25, 0.5, 0.75])
        // Retouch records carry NO chain/mask (NO_MASKS + no iop chain).
        let chain = try XCTUnwrap(retouchRecord["chain"] as? [Any])
        XCTAssertTrue(chain.isEmpty)
        XCTAssertNil(retouchRecord["mask"])
    }

    /// Round trip: write → read → kind + identity + every stroke payload
    /// verbatim (NDE-1 UUIDs; params byte-equal).
    func testRetouchLayerRoundTrip() throws {
        let stack = makeRetouchStack()
        let original = try XCTUnwrap(stack.adjustmentLayers[1] as? RetouchLayer)
        let sidecar = SidecarLayerStackRecord(stack)
        let data = try JSONEncoder().encode(sidecar)
        let decoded = try JSONDecoder().decode(SidecarLayerStackRecord.self, from: data)
        let restored = try XCTUnwrap(decoded.runtimeLayers[1] as? RetouchLayer)

        XCTAssertEqual(restored.id, original.id, "NDE-1: UUID identity survives")
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.kind, .retouch)
        XCTAssertEqual(restored.opacity, original.opacity)
        XCTAssertEqual(restored.blendOptions, original.blendOptions)
        XCTAssertEqual(restored.strokes, original.strokes, "stroke payloads verbatim")
        XCTAssertEqual(restored.strokes.count, 4)
    }

    /// History snapshot projection: kind + strokes survive
    /// snapshot → sidecar spelling → restore.
    func testRetouchHistorySnapshotRoundTrip() throws {
        let stack = makeRetouchStack()
        let snapshot = LayerStackSnapshot(stack)
        XCTAssertEqual(snapshot.layers[1].kind, "retouch")

        let sidecarRecord = SidecarLayerStackRecord(snapshot)
        let data = try JSONEncoder().encode(sidecarRecord)
        let decoded = try JSONDecoder().decode(SidecarLayerStackRecord.self, from: data)
        let rebuilt = decoded.snapshot
        let restored = try XCTUnwrap(rebuilt.layers[1].makeAnyLayer() as? RetouchLayer)
        let original = try XCTUnwrap(stack.adjustmentLayers[1] as? RetouchLayer)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.strokes, original.strokes)
    }

    /// Compatibility: a PRE-06-07 layer record (no `strokes` key, kind
    /// "adjustment") decodes unchanged; a retouch record without the
    /// strokes key degrades to an EMPTY stroke list (documented optional
    /// decodeIfPresent semantics — user data never dropped, absent data
    /// means absent strokes).
    func testPre06_07DocumentsDecodeCompatibly() throws {
        let json = """
        {"layers":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEFFFF0000","kind":"adjustment",
        "name":"Lift","isVisible":true,"enabled":true,"opacity":1.0,"blendMode":1,
        "blendOptions":0,"chain":[]}]}
        """
        let decoded = try JSONDecoder().decode(SidecarLayerStackRecord.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.runtimeLayers.count, 1)
        XCTAssertTrue(decoded.runtimeLayers[0] is AdjustmentLayer)

        let retouchJSON = """
        {"layers":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEFFFF0001","kind":"retouch",
        "name":"Fix","isVisible":true,"enabled":true,"opacity":1.0,"blendMode":1,
        "blendOptions":0,"chain":[]}]}
        """
        let decodedRetouch = try JSONDecoder().decode(
            SidecarLayerStackRecord.self, from: Data(retouchJSON.utf8))
        let restored = try XCTUnwrap(decodedRetouch.runtimeLayers[0] as? RetouchLayer)
        XCTAssertTrue(restored.strokes.isEmpty)
        XCTAssertEqual(restored.kind, .retouch)
    }
}
