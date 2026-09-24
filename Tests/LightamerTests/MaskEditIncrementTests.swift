@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-03 T6 — the masked-composite incremental semantics: the
/// maskVersion hash folds into the composite prefix key INDEPENDENTLY of
/// the chain hash (METAL-8 double insurance), so a MASK edit re-rasterizes
/// ONLY the mask plane + re-blends the prefixes while the layer's chain
/// planes stay fully cached, and a PARAM edit leaves the mask plane cached.
/// Plus the content-level masked-blend check (L020 ③).
final class MaskEditIncrementTests: XCTestCase {

    private let imageID = UUID()

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

    private func gainLayer(_ gain: Float, name: String, mask: MaskSpec? = nil) -> AdjustmentLayer {
        AdjustmentLayer(
            name: name, opacity: 1.0,
            chain: [ModuleInstance(
                module: TestGainModule.self,
                params: TestGainModule.Params(gain: gain))],
            mask: mask)
    }

    private func ellipseMask(cx: Float, cy: Float) -> MaskSpec {
        MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: cx, y: cy), radiusX: 0.12, radiusY: 0.12,
                rotationDegrees: 0, border: 0))),
        ]))
    }

    private func compositeRun(
        _ image: DecodedImage, base: [any ModuleBoxing], stack: LayerStack,
        registry: ModuleRegistry, metal: MetalContext, cache: PipeCache
    ) async throws -> LayerCompositeResult {
        try await LayerCompositeDriver.composite(
            image: image, imageID: imageID, baseInstances: base,
            layerStack: stack, registry: registry, resolution: .preview,
            cache: cache, metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview)
    }

    /// THE accounting scenario (plan T6 evidence): mask edit → B chain all
    /// HIT + B mask plane MISS + B prefix MISS; param edit → the inverse.
    func testMaskEditDoesNotRecomputeChain() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeGradientImage()
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = gainLayer(1.5, name: "A")
        let b = gainLayer(2.0, name: "B", mask: ellipseMask(cx: 0.5, cy: 0.5))
        stack.addAdjustment(a)
        stack.addAdjustment(b)

        // Cold: base input + colorin + A chain + A prefix + B chain
        // + B MASK plane + B prefix + colorout + gamma = 9 misses.
        _ = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let cold = await cache.stats
        XCTAssertEqual(cold.hits, 0)
        XCTAssertEqual(cold.misses, 9, "cold composite = 9 cache lines (B carries a mask plane)")

        // ── THE MASK EDIT: move the ellipse. ONLY the mask plane + B's
        // prefix re-key; B's CHAIN stays cached (zero chain recompute).
        if case var .ellipse(e) = b.mask!.drawn!.forms[0].kind {
            e.center = MaskPoint(x: 0.35, y: 0.35)
            b.mask!.drawn!.forms[0].kind = .ellipse(e)
        }
        let run2 = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let delta2 = (await cache.stats) - cold
        // (LayerCacheTests scenario-1 calibration: a no-op B run hits 4
        // lines — colorin + A chain + A prefix + gamma. A MASK edit turns
        // B's chain miss into a HIT (+1) and adds the mask-plane MISS;
        // GUI-21 semantics: the flipped final prefix also re-runs the
        // terminal colorout+gamma — gamma leaves the hit set.)
        XCTAssertEqual(delta2.hits, 4,
                       "calibrated 3 base hits + B CHAIN hit (zero chain recompute)")
        XCTAssertEqual(delta2.misses, 4, "B's mask plane + B's prefix + colorout + gamma re-key")
        XCTAssertEqual(run2.blendPasses, 1)
        XCTAssertEqual(run2.layerStats.first { $0.layerID == a.id }?.prefixHit, true)
        XCTAssertEqual(run2.layerStats.first { $0.layerID == b.id }?.prefixHit, false)

        // ── THE PARAM EDIT: B's gain. The chain re-renders + prefix
        // re-blends; the MASK PLANE STAYS CACHED (the other independence
        // direction — same single-blend incremental shape).
        var edited = b.chain[0]
        try edited.setParams(TestGainModule.Params(gain: 3.0), as: TestGainModule.self)
        b.chain[0] = edited
        let run3 = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let delta = (await cache.stats) - (cold + delta2)
        // (calibration: the param-edit run = LayerCache scenario-1's 3 hits.
        // The MASK PLANE re-rasterizes here: its key folds the composite
        // prefix (GUI-21 — the parametric leg SAMPLES the layer output),
        // and B's chainHash is part of that prefix. Correctness-first; a
        // drawn-only payload could later split its key out of the fold.)
        XCTAssertEqual(delta.hits, 3,
                       "calibrated 3 base hits (mask rides the prefix fold)")
        XCTAssertEqual(delta.misses, 5, "B's chain + B's prefix + B's mask plane + colorout + gamma")
        XCTAssertEqual(run3.blendPasses, 1)
        XCTAssertEqual(run3.layerStats.first { $0.layerID == b.id }?.prefixHit, false)
    }

    /// Plan 06-04 T5 — the THREE-payload class extension of the
    /// independence semantics: B's mask carries drawn ⊗ parametric ⊓
    /// raster; editing the PARAMETRIC curve re-assembles ONLY the mask
    /// plane + prefix while the chain (and every other layer) stays fully
    /// cached; editing B's chain param leaves the mask plane HIT.
    func testThreePayloadMaskEditAccounting() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeGradientImage()
        let cache = PipeCache()
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = gainLayer(1.5, name: "A")
        var spec = MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.2, radiusY: 0.2,
                rotationDegrees: 0, border: 0))),
        ]))
        spec.parametric = ParametricMask(
            domain: .luma,
            channels: [.init(channel: 0, curve: .init(points: [0.1, 0.2, 0.5, 0.6]))])
        let b = gainLayer(2.0, name: "B", mask: spec)
        stack.addAdjustment(a)
        stack.addAdjustment(b)

        let coldRun = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let cold = await cache.stats
        XCTAssertEqual(cold.misses, 9, "cold composite = 9 lines (B's assembled mask plane included)")
        XCTAssertEqual(coldRun.blendPasses, 2)

        // ── THE PARAMETRIC EDIT: flip the curve. maskVersion hash flips
        // → the mask plane re-assembles + B's prefix re-blends; B's CHAIN
        // (and A entirely) stay cached — the METAL-8 independence now
        // covering all three payload classes.
        b.mask!.parametric!.channels[0].curve.points = [0.2, 0.3, 0.4, 0.5]
        let run2 = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let delta2 = (await cache.stats) - cold
        // (GUI-21 semantics: the flipped final prefix also re-runs the
        // terminal colorout+gamma — gamma leaves the hit set.)
        XCTAssertEqual(delta2.hits, 4,
                       "calibrated: A legs + colorin + B CHAIN all hit")
        XCTAssertEqual(delta2.misses, 4, "B's assembled mask plane + prefix + colorout + gamma re-key")
        XCTAssertEqual(run2.blendPasses, 1)
        XCTAssertEqual(run2.layerStats.first { $0.layerID == b.id }?.prefixHit, false)

        // ── THE CHAIN EDIT: B's gain. The mask plane re-assembles too —
        // its key folds the composite prefix (GUI-21: the parametric leg
        // SAMPLES the layer output, and B's chainHash is in that prefix).
        var edited = b.chain[0]
        try edited.setParams(TestGainModule.Params(gain: 3.0), as: TestGainModule.self)
        b.chain[0] = edited
        _ = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: cache)
        let delta3 = (await cache.stats) - (cold + delta2)
        XCTAssertEqual(delta3.hits, 3,
                       "calibrated: 3 base hits (mask rides the prefix fold)")
        XCTAssertEqual(delta3.misses, 5, "B's chain + B's prefix + B's mask plane + colorout + gamma")
    }

    /// Content-level masked blend (L020 ③): with a NORMAL layer over the
    /// base, pixels OUTSIDE the mask equal the mask-less composite
    /// byte-identically; pixels INSIDE differ (the layer shows through).
    func testMaskedCompositeContentMatchesOutsideMask() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeGradientImage(width: 64, height: 64)
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        // Reference = the BASE-ONLY composite (no adjustment layers):
        // outside the mask the masked layer is fully transparent, so the
        // composite must equal the base byte-identically; inside, the
        // gain layer shows through.
        var refStack = LayerStack(baseLayer: BackgroundLayer())
        let ref = try await compositeRun(image, base: base, stack: refStack, registry: registry, metal: metal, cache: PipeCache())

        // Masked stack: A carries an ellipse mask over the center.
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = gainLayer(2.0, name: "A", mask: ellipseMask(cx: 0.5, cy: 0.5))
        stack.addAdjustment(a)
        let masked = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: PipeCache())

        let refBytes = Self.planeBytes(ref.output, metal: metal)
        let maskedBytes = Self.planeBytes(masked.output, metal: metal)
        XCTAssertEqual(refBytes.count, maskedBytes.count)
        XCTAssertGreaterThan(refBytes.count, 0, "防空转 guard")

        let w = masked.output.width, h = masked.output.height
        let inside = (w / 2) + (h / 2) * w
        var outsideDiffs = 0
        var comparedOutside = 0
        for y in stride(from: 2, to: h - 2, by: 4) {
            for x in stride(from: 2, to: w - 2, by: 4) {
                let i = x + y * w
                // corners far from the centered ellipse mask
                if abs(x - w / 2) > w / 4 || abs(y - h / 2) > h / 4 {
                    for c in 0..<4 where refBytes[i * 4 + c] != maskedBytes[i * 4 + c] {
                        outsideDiffs += 1
                    }
                    comparedOutside += 4
                }
            }
        }
        XCTAssertEqual(outsideDiffs, 0,
                       "outside the mask the composite must equal the mask-less blend byte-identically")
        XCTAssertGreaterThan(comparedOutside, 0, "防空转 guard")
        // Inside: the masked layer must show through (gain 2.0 differs).
        let insideDiff = (0..<4).contains { c in
            refBytes[inside * 4 + c] != maskedBytes[inside * 4 + c]
        }
        XCTAssertTrue(insideDiff, "inside the mask the layer must show through")
    }

    /// The masked layer's blend consumes the PREMULTIPLIED mask plane
    /// (D-06-02-T5-3): with opacity 0.5 the effective outside-mask
    /// opacity is 0.5·0 = 0 → identical to the reference even for a
    /// NON-normal mode. (Multiply @ opacity 1 outside mask == base.)
    func testMaskZeroRegionKeepsBaseAcrossModes() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeGradientImage(width: 64, height: 64)
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        // Reference = base-only (outside the mask the multiply layer is
        // fully transparent → equals the base; inside, multiply applies).
        var refStack = LayerStack(baseLayer: BackgroundLayer())
        let ref = try await compositeRun(image, base: base, stack: refStack, registry: registry, metal: metal, cache: PipeCache())

        var stack = LayerStack(baseLayer: BackgroundLayer())
        let a = gainLayer(1.0, name: "A", mask: ellipseMask(cx: 0.3, cy: 0.3))
        a.blendMode = .multiply
        stack.addAdjustment(a)
        let masked = try await compositeRun(image, base: base, stack: stack, registry: registry, metal: metal, cache: PipeCache())

        let refBytes = Self.planeBytes(ref.output, metal: metal)
        let maskedBytes = Self.planeBytes(masked.output, metal: metal)
        let w = masked.output.width
        let corner = 2 + 2 * w
        XCTAssertEqual(refBytes[corner * 4 + 0], maskedBytes[corner * 4 + 0])
        XCTAssertEqual(refBytes[corner * 4 + 1], maskedBytes[corner * 4 + 1])
        XCTAssertEqual(refBytes[corner * 4 + 2], maskedBytes[corner * 4 + 2],
                       "multiply at mask 0 must leave the base untouched (not the multiply formula)")
    }

    private static func planeBytes(
        _ texture: any MTLTexture, metal: MetalContext
    ) -> [UInt8] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted() // L014
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return bytes
    }
}
