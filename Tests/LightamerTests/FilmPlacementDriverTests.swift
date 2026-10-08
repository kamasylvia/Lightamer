@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmPlacementDriverTests (Plan M3-3-02 T4, KD-5 — LAYERS bundle) — the op's
// DRIVER face:
//
//   1. ACEScc ENVELOPE 包夹: a layer chain carrying filmPlacement gets the
//      acesccIn/acesccOut wrap (the ≥1-catalog-op boxing condition — 20.8
//      sorts inside [20.5, 69.9] by construction).
//   2. MASK LEGALITY: the op is a scene-referred exposure op
//      (.supportsBlending) — a masked adjustment layer carrying it renders
//      through the composite.
//   3. 层链禁面不受扰: the D-06-CONTEXT-5 geometry rejection is untouched
//      by the new row (the forbidden set derives from the slot table's
//      13/15/16/17 — filmPlacement's 20.8 is not in it).
//   4. IDENTITY composite smoke: an identity-op layer composites to the
//      base plane within the acescc round-trip tolerance (not byte-exact —
//      the envelope domain conversion is the accepted noise floor).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmPlacementDriverTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeRegistry() async throws -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    private func makeImage(width: Int = 32, height: Int = 24) -> DecodedImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                pixels[o + 0] = 0.05 + 0.6 * Float(x) / Float(width - 1)
                pixels[o + 1] = 0.1 + 0.5 * Float(y) / Float(height - 1)
                pixels[o + 2] = 0.15
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
            decoderVersionUsed: .v8
        )
    }

    /// A layer whose chain carries exactly one committed filmPlacement op.
    private func makePlacementLayer(
        registry: ModuleRegistry, params: FilmPlacementModule.Params
    ) async throws -> AdjustmentLayer {
        let layer = AdjustmentLayer(name: "placement")
        layer.chain.append(
            ModuleInstance(module: FilmPlacementModule.self, params: params))
        return layer
    }

    // MARK: - 1: the envelope 包夹

    func testPlacementLayerChainGetsTheACESccEnvelope() async {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let (boxes, _) = await registry.materializeBoxes(for: [
            ModuleInstance(module: FilmPlacementModule.self, params: .init())
        ])
        XCTAssertEqual(boxes.count, 1)
        XCTAssertTrue(
            ACESccEnvelope.needsEnvelope(boxes),
            "filmPlacement is a catalog op — the ≥1-catalog-op boxing fires")
        let wrapped = LayerCompositeSeam.acesccEnvelope(boxes)
        XCTAssertEqual(wrapped.count, 3, "acesccIn + the op + acesccOut")
        XCTAssertEqual(wrapped.first?.opName, "acesccIn")
        XCTAssertEqual(wrapped.last?.opName, "acesccOut")
        // The op sorts INSIDE the envelope by v50 (20.5 < 20.8 < 69.9).
        XCTAssertLessThan(wrapped.first!.iopOrder, FilmPlacementModule.iopOrder)
        XCTAssertLessThan(FilmPlacementModule.iopOrder, wrapped.last!.iopOrder)
        // A pure non-catalog chain stays unwrapped (the checker-E2 narrowing
        // — colisa answers through the default arm, NOT a catalog row).
        let (plainBoxes, _) = await registry.materializeBoxes(for: [
            ModuleInstance(module: ColisaModule.self, params: .init())
        ])
        XCTAssertFalse(ACESccEnvelope.needsEnvelope(plainBoxes))
    }

    // MARK: - 2 + 4: masked composite render + identity smoke

    func testMaskedIdentityPlacementLayerCompositesNearBase() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let layer = try await makePlacementLayer(registry: registry, params: .init())
        // A drawn BRUSH form (the 06-03 payload — one stroke across the
        // frame; the effective plane is partial → the masked blend leg).
        let stroke = BrushStroke(
            points: [
                BrushPoint(
                    corner: MaskPoint(x: 4.0, y: 4.0), ctrl1: MaskPoint(x: 8.0, y: 6.0),
                    ctrl2: MaskPoint(x: 12.0, y: 9.0)),
                BrushPoint(
                    corner: MaskPoint(x: 20.0, y: 14.0), ctrl1: MaskPoint(x: 16.0, y: 12.0),
                    ctrl2: MaskPoint(x: 14.0, y: 10.0)),
            ],
            radius: 8, hardness: 0.5, density: 1.0, opacity: 1.0)
        layer.mask = MaskSpec(
            drawn: DrawnMaskSpec(
                forms: [MaskForm(id: UUID(), kind: .brush(stroke))]))
        stack.addAdjustment(layer)

        let cache = PipeCache()
        // The BASE face (no layers): RenderPipeline.process.
        let (base, _) = try await RenderPipeline.process(
            image: image, instances: [], imageID: UUID(), resolution: .preview,
            cache: PipeCache(), metal: metal)
        // The composite: base + the identity placement layer (masked).
        let (composite, _) = try await RenderPipeline.processComposite(
            image: image, instances: [], layerStack: stack, registry: registry,
            imageID: UUID(), resolution: .preview, cache: cache, metal: metal,
            policy: .preview)
        // L014: never read a plane across in-flight encoders.
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        XCTAssertEqual(base.pixelFormat, composite.pixelFormat)
        // Compare as FLOATS (the planes are float32 — a byte-wise compare
        // of raw float bits is meaningless).
        let baseFloats = Self.readAllFloats(base)
        let compositeFloats = Self.readAllFloats(composite)
        XCTAssertEqual(baseFloats.count, compositeFloats.count)
        // The identity op through the envelope: the acescc round trip is
        // the accepted noise floor (NOT byte-exact — the draw face is).
        var maxDiff: Float = 0
        for (a, b) in zip(baseFloats, compositeFloats) {
            maxDiff = max(maxDiff, abs(a - b))
        }
        XCTAssertLessThanOrEqual(
            maxDiff, 1e-4,
            "an identity placement layer composites to the base within the acescc round-trip noise")
    }

    // MARK: - 3: the geometry rejection is untouched

    func testGeometryRejectionStillFiresAndPlacementIsLegal() async {
        // The placement op is layer-legal (20.8 ∉ {13, 15, 16, 17}).
        let placementChain = [ModuleInstance(
            module: FilmPlacementModule.self, params: .init())]
        XCTAssertNil(LayerCompositeDriver.layerGeometryViolation(placementChain))
        // The forbidden set still fires (the slot-table derivation moved
        // with the new row, not against it — lens 13.0 is a forbidden slot;
        // crop 24.5 is layer-legal by the same table).
        let lensChain = [ModuleInstance(module: LensModule.self, params: .init())]
        XCTAssertEqual(
            LayerCompositeDriver.layerGeometryViolation(lensChain), LensModule.opName)
    }

    private static func readAllFloats(_ texture: any MTLTexture) -> [Float] {
        let w = texture.width, h = texture.height
        let rowBytes = w * 16
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
    }
}
