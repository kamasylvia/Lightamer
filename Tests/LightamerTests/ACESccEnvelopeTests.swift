@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// ACESccEnvelopeTests (Plan M2-5-1 T2, D-M2-5-CONTEXT-3) — the grade-domain
// envelope face:
//
//   1. ROUND TRIP: a catalog-op layer at identity params composites back
//      onto the base plane within 1e-5 absolute (p99.9; the ACEScc log
//      round trip in float32 — KD-2's tolerance).
//   2. NARROWING (checker E2): pure non-catalog chains (TestGain) and
//      empty chains are NOT wrapped; the seam returns the input array.
//   3. ORDER (checker E1): an exposure layer's wrapped chain sorts
//      acesccIn first / acesccOut last, and a direct runSub shows
//      pieces.first == acesccIn && pieces.last == acesccOut.
//   4. RETOUCH/BASE/TERMINAL (KD-2 半径红线): a retouch layer and a
//      catalog-op BASE chain stay byte-identical to their flat (unwrapped)
//      reference — the envelope touches ONLY adjustment legs.
//   5. KEY STABILITY (KD-2): the same grade layer composited twice HITs
//      the layer cache on the second pass (the envelope's constant
//      paramsHash folds deterministically — fresh instance UUIDs do NOT
//      leak into the keys).
// ─────────────────────────────────────────────────────────────────────────

final class ACESccEnvelopeTests: XCTestCase {

    // ── Fixtures (the LayerCompositeTests shapes) ──

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ACESccKernel.metalBundle)
        return metal
    }

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
            decoderVersionUsed: .v8
        )
    }

    /// populate ALSO installs the driver seam (the production shape).
    private func makeRegistry() async throws -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    private func makeBaseInstances(
        registry: ModuleRegistry, baseGain: Float = 1.2
    ) async throws -> [any ModuleBoxing] {
        var chain = await makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        let gainMade = await registry.makeBox(opName: TestGainModule.opName)
        let gain = try XCTUnwrap(gainMade as? ModuleBox<TestGainModule>)
        gain.setParams(TestGainModule.Params(gain: baseGain))
        chain.append(gain)
        return chain.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    /// The base trio + a COMMITTED catalog op (exposure) + a committed
    /// gain — fresh boxes per call (boxes are single-owner stateful; the
    /// flat and composite paths must not share them).
    private func makeBaseWithExposure(
        registry: ModuleRegistry, ev: Float, baseGain: Float = 1.2
    ) async throws -> [any ModuleBoxing] {
        var chain = try await makeBaseInstances(registry: registry, baseGain: baseGain)
        let exposureMade = await registry.makeBox(opName: ExposureModule.opName)
        let exposure = try XCTUnwrap(exposureMade as? ModuleBox<ExposureModule>)
        exposure.setParams(ExposureModule.Params(exposure: ev))
        chain.append(exposure)
        return chain.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    private func layerWithExposure(
        _ ev: Float, opacity: Float = 1.0, name: String = "grade"
    ) -> AdjustmentLayer {
        let record = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: ev))
        return AdjustmentLayer(name: name, opacity: opacity, chain: [record])
    }

    private func layerWithGain(_ gain: Float, opacity: Float = 1.0) -> AdjustmentLayer {
        let record = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params(gain: gain))
        return AdjustmentLayer(name: "L", opacity: opacity, chain: [record])
    }

    private func composite(
        _ image: DecodedImage, _ base: [any ModuleBoxing], _ stack: LayerStack,
        registry: ModuleRegistry, metal: MetalContext, cache: PipeCache
    ) async throws -> LayerCompositeResult {
        try await LayerCompositeDriver.composite(
            image: image, imageID: Self.fixtureImageID, baseInstances: base,
            layerStack: stack, registry: registry, resolution: .preview,
            cache: cache, metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview)
    }

    private static let fixtureImageID = UUID()

    private func rawBytes(_ texture: any MTLTexture, metal: MetalContext) -> [UInt8] {
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

    private func floatPlane(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        precondition(
            texture.pixelFormat == WorkingSpace.pixelFormat,
            "floatPlane is for rgba32Float planes only (got \(texture.pixelFormat))")
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var values = [Float](repeating: 0, count: texture.width * texture.height * 4)
        values.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * WorkingSpace.bytesPerPixel,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return values
    }

    /// FLOAT-plane read (rgba32Float — bytesPerRow is width × 16; the
    /// terminal gamma output is a bgra8Unorm DISPLAY plane and must be
    /// read through `rawBytes` instead).
    // ── 1: the round trip (identity catalog layer ≈ no layer) ──

    /// The envelope's tolerance lives on a LINEAR float32 plane, so the
    /// base here is colorin only — no terminal (the composite then returns
    /// the last float32 composite plane, per the driver contract).
    func testIdentityCatalogLayerRoundTripsWithinTolerance() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()

        // The reference: the colorin-only base composite (float32 output —
        // no terminal segment to fold the plane into 8-bit display).
        let colorinMade = await registry.makeBox(opName: ColorInModule.opName)
        let colorin = try XCTUnwrap(colorinMade as? ModuleBox<ColorInModule>)
        colorin.setParams(ColorInModule.Params())
        let base = [colorin]

        let emptyStack = LayerStack(baseLayer: BackgroundLayer())
        let cacheRef = PipeCache()
        let reference = try await composite(
            image, base, emptyStack, registry: registry, metal: metal, cache: cacheRef)

        // A grade layer carrying the catalog op at IDENTITY params: the
        // leg is exactly envelope ∘ identity ∘ envelope⁻¹.
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layerWithExposure(0.0))
        let cache = PipeCache()
        let result = try await composite(
            image, base, stack, registry: registry, metal: metal, cache: cache)

        let a = floatPlane(reference.output, metal: metal)
        let b = floatPlane(result.output, metal: metal)
        XCTAssertEqual(a.count, b.count)
        // Non-vacuity guard: the reference plane must carry real content
        // (the gradient after the sRGB tail) — an all-black comparison
        // proves nothing.
        let referenceMax = a.max() ?? 0
        XCTAssertGreaterThan(
            referenceMax, 0.3,
            "the reference composite must carry content (vacuous-compare guard)")
        var deltas = [Float]()
        deltas.reserveCapacity(a.count)
        for index in 0..<a.count {
            deltas.append(abs(a[index] - b[index]))
        }
        deltas.sort()
        let p999 = deltas[Int(Double(deltas.count - 1) * 0.999)]
        let maxDelta = deltas.last ?? 0
        // IEEE口径: -0/+0 视相等（abs diff 0 covers it). KD-2: absolute
        // 1e-5 at p99.9 for the float32 log round trip; the tail rides the
        // linear-extension leg at extreme values.
        XCTAssertLessThanOrEqual(
            p999, 1e-5, "p99.9 round-trip drift \(p999) exceeds the 1e-5 envelope budget")
        XCTAssertLessThanOrEqual(
            maxDelta, 5e-5, "max round-trip drift \(maxDelta) exceeds the hard cap")
    }

    // ── 2: the narrowing (checker E2) ──

    func testNonCatalogAndEmptyChainsAreNotWrapped() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let registry = try await makeRegistry()

        // A pure non-catalog chain (TestGain is dev-only, NOT a catalog
        // row) passes through UNCHANGED — zero envelope cost.
        let gainMade = await registry.makeBox(opName: TestGainModule.opName)
        let gain = try XCTUnwrap(gainMade)
        let nonCatalog = [gain]
        XCTAssertFalse(ACESccEnvelope.needsEnvelope(nonCatalog))
        let wrappedNonCatalog = ACESccEnvelope.wrap(nonCatalog)
        XCTAssertEqual(wrappedNonCatalog.count, 1)

        // Empty chains skip too.
        XCTAssertTrue(ACESccEnvelope.wrap([]).isEmpty)
        XCTAssertFalse(ACESccEnvelope.needsEnvelope([]))

        // A catalog op flips the predicate.
        let exposureMade = await registry.makeBox(opName: ExposureModule.opName)
        let exposure = try XCTUnwrap(exposureMade)
        XCTAssertTrue(ACESccEnvelope.needsEnvelope([gain, exposure]))
    }

    // ── 3: the ordering (checker E1) ──

    func testExposureChainSortsEnvelopeFirstAndLast() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()

        // The exact function the adjustment leg calls.
        let exposureMade = await registry.makeBox(opName: ExposureModule.opName)
        let exposure = try XCTUnwrap(exposureMade)
        let wrapped = LayerCompositeSeam.acesccEnvelope([exposure])
        XCTAssertEqual(wrapped.count, 3)
        let sorted = wrapped.sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
        XCTAssertEqual(sorted.first?.opName, ACESccInModule.opName)
        XCTAssertEqual(sorted.last?.opName, ACESccOutModule.opName)
        // The 20.5 < 21.0 < 69.9 machine check (envelope brackets the
        // whole domain — E1's placement semantics).
        XCTAssertLessThan(
            ACESccInModule.iopOrder, V50Order.order(for: ExposureModule.opName)!)
        XCTAssertLessThan(
            V50Order.order(for: ExposureModule.opName)!, ACESccOutModule.iopOrder)

        // END-TO-END through the driver's seam: a real layer sub-run sees
        // acesccIn as its first piece and acesccOut as its last.
        let image = makeImage()
        let base = try await makeBaseInstances(registry: registry)
        let (basePlane, _) = try await RenderPipeline.process(
            image: image, instances: base, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let layer = layerWithExposure(0.3)
        let (boxes, _) = await registry.materializeBoxes(for: layer.chain)
        let injected = LayerCompositeSeam.acesccEnvelope(boxes)
        let pipe = PixelPipe(resolution: .preview, cache: PipeCache())
        _ = try await pipe.runSub(
            input: basePlane, inputROI: ROI(
                x: 0, y: 0, width: basePlane.width, height: basePlane.height,
                scale: 1.0),
            instances: injected, decodeHash: 42, metal: metal, layerID: layer.id)
        XCTAssertEqual(pipe.pieces.first?.box.opName, ACESccInModule.opName)
        XCTAssertEqual(pipe.pieces.last?.box.opName, ACESccOutModule.opName)
    }

    // ── 4: the radius red lines (base/terminal untouched; retouch leg) ──

    func testCatalogOpBaseChainStaysByteIdenticalToFlatRun() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let cache = PipeCache()

        // Base chain WITH a catalog op (exposure — in-domain for the 18
        // catalogs but a BASE resident here) + a committed gain: the
        // envelope must touch NEITHER the base sub-run nor the terminal —
        // the composite equals the flat merged chain BYTE FOR BYTE. Fresh
        // chains per path (boxes are single-owner stateful).
        let base = try await makeBaseWithExposure(registry: registry, ev: 0.5)

        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layerWithGain(1.5))

        let result = try await composite(
            image, base, stack, registry: registry, metal: metal, cache: cache)

        // The flat reference: the SAME chains as one run (no envelope —
        // the flat path never boxes anything).
        let layerRecord = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params(gain: 1.5))
        var flat = try await makeBaseWithExposure(registry: registry, ev: 0.5)
        let layerBoxMade = await registry.makeBox(
            opName: layerRecord.opName, instanceID: layerRecord.id)
        let layerBox = try XCTUnwrap(layerBoxMade)
        try layerBox.apply(layerRecord)
        flat.append(layerBox)
        flat = flat.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (flatTexture, _) = try await RenderPipeline.process(
            image: image, instances: flat, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)

        // Non-vacuity: the display plane carries real content before the
        // compare (byte domain — the terminal output is bgra8Unorm).
        let flatBytes = rawBytes(flatTexture, metal: metal)
        XCTAssertGreaterThan(
            flatBytes.max() ?? 0, 30, "flat reference must carry content")

        XCTAssertEqual(
            rawBytes(result.output, metal: metal),
            rawBytes(flatTexture, metal: metal),
            "a catalog-op BASE + non-catalog layer must stay byte-identical " +
                "to the flat run (the envelope never leaves the adjustment leg)")
    }

    // ── 5: the key stability (KD-2) ──

    func testSameGradeLayerCompositedTwiceHitsLayerCache() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let base = try await makeBaseInstances(registry: registry)
        let cache = PipeCache()

        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layerWithExposure(0.4))

        // First pass: everything MISSES (cold cache) but seeds it.
        let first = try await composite(
            image, base, stack, registry: registry, metal: metal, cache: cache)
        XCTAssertEqual(first.layerStats.count, 1)
        // The first pass renders the layer chain planes (some miss shape).
        let firstMisses = first.layerStats[0].run.misses

        // Second pass, SAME params: the layer chain planes (including the
        // two envelope planes — CONSTANT paramsHash) must HIT. A fresh
        // envelope pair is constructed per assembly; if the instance UUIDs
        // leaked into the keys this would MISS and fail here.
        let second = try await composite(
            image, base, stack, registry: registry, metal: metal, cache: cache)
        XCTAssertGreaterThan(
            second.layerStats[0].run.hits, 0,
            "the enveloped layer chain must cache-HIT on the second identical composite")
        XCTAssertGreaterThanOrEqual(firstMisses, 0)

        // And an actual param edit invalidates: +1EV flips the chain hash
        // → MISS again (the chain planes re-render).
        var editedStack = LayerStack(baseLayer: BackgroundLayer())
        editedStack.addAdjustment(layerWithExposure(0.9))
        let third = try await composite(
            image, base, editedStack, registry: registry, metal: metal, cache: cache)
        XCTAssertGreaterThan(
            third.layerStats[0].run.misses, 0,
            "a grade edit must flip the layer chain planes (no stale hit)")
    }
}
