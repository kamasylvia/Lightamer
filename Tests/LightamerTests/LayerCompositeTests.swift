@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-01 T4 — the degenerate composite (`LayerCompositeDriver`):
/// identity triples BYTE-EXACT in both PREVIEW and FULL (L014 fence, L020 ③
/// content-level), cross-layer ROI consistency under `roiHint`, per-layer
/// geometry rejection (D-06-CONTEXT-5), and the LAYER-02 independent-params
/// proof (a layer's output == its chain spliced into the base chain).
final class LayerCompositeTests: XCTestCase {

    // ── Fixtures ──

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    /// A spatially-varying synthetic image (diagonal gradient — L020 ③:
    /// coordinate/geometry errors are invisible on flat fields). Built as a
    /// raw RGBA float32 bitmap — no CI filter parameter bridging quirks.
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

    private func makeRegistry() async throws -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    /// The base chain: trio + one base gain (committed params).
    private func makeBaseInstances(
        registry: ModuleRegistry, baseGain: Float
    ) async throws -> [any ModuleBoxing] {
        var chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        let gainMade = await registry.makeBox(opName: TestGainModule.opName)
        let gain = try XCTUnwrap(gainMade as? ModuleBox<TestGainModule>)
        gain.setParams(TestGainModule.Params(gain: baseGain))
        chain.append(gain)
        return chain.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    private func layerWithGain(
        _ gain: Float, priority: Int = 5, opacity: Float = 1.0,
        name: String = "L"
    ) -> AdjustmentLayer {
        let record = ModuleInstance(
            module: TestGainModule.self, multiPriority: priority,
            params: TestGainModule.Params(gain: gain))
        return AdjustmentLayer(name: name, opacity: opacity, chain: [record])
    }

    private func composite(
        _ image: DecodedImage, _ base: [any ModuleBoxing], _ stack: LayerStack,
        registry: ModuleRegistry, metal: MetalContext,
        resolution: PipeResolution, cache: PipeCache,
        roiHint: ROI? = nil
    ) async throws -> LayerCompositeResult {
        try await LayerCompositeDriver.composite(
            image: image, imageID: Self.fixtureImageID, baseInstances: base,
            layerStack: stack, registry: registry, resolution: resolution,
            cache: cache, metal: metal, longEdge: nil, roiHint: roiHint,
            policy: resolution == .full ? .fullColdLayer : .preview)
    }

    private static let fixtureImageID = UUID()

    /// L014 fence + full raw read (float32 RGBA planes and the display
    /// tail alike — the byte comparisons are format-aware via byteCount).
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

    /// Byte-exact plane comparison with a compared > 0 guard (L020 ③).
    private func assertBytesEqual(
        _ a: [UInt8], _ b: [UInt8], _ label: String
    ) {
        XCTAssertEqual(a.count, b.count, "\(label): plane sizes differ")
        guard a.count == b.count, !a.isEmpty else {
            XCTFail("\(label): nothing compared (empty planes) —防空转")
            return
        }
        var firstDiff = -1
        for index in 0..<a.count where a[index] != b[index] {
            firstDiff = index
            break
        }
        if firstDiff >= 0 {
            XCTFail(
                "\(label): planes diverge at byte \(firstDiff) of \(a.count) " +
                "(\(a[firstDiff]) vs \(b[firstDiff]))")
        }
    }

    private func assertBytesDiffer(
        _ a: [UInt8], _ b: [UInt8], _ label: String
    ) {
        guard a.count == b.count, !a.isEmpty else {
            XCTFail("\(label): nothing compared —防空转")
            return
        }
        let differing = zip(a, b).filter { $0.0 != $0.1 }.count
        XCTAssertGreaterThan(
            differing, 0, "\(label): planes must differ (independent params)")
    }

    // ── 1. Identity triples (byte-exact, PREVIEW + FULL) ──

    /// op = 1.0 (normal, full passthrough mask) ⇒ composite == the layer's
    /// chain spliced into the base chain as ONE flat pipe run. The LAYER-02
    /// content proof and the op=1 identity triple in one gate.
    func testOpacityOneEqualsFlatMergedChain() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let cache = PipeCache()

        for resolution in [PipeResolution.preview, .full] {
            let base = try await makeBaseInstances(registry: registry, baseGain: 1.2)
            var stack = LayerStack(baseLayer: BackgroundLayer())
            let layer = layerWithGain(2.0, opacity: 1.0)
            stack.addAdjustment(layer)

            let result = try await composite(
                image, base, stack, registry: registry, metal: metal,
                resolution: resolution, cache: cache)

            // The flat reference: the SAME chains as ONE pipe run (the
            // layer's records materialized into the same flat array).
            let flatBase = try await makeBaseInstances(registry: registry, baseGain: 1.2)
            let layerRecord = ModuleInstance(
                module: TestGainModule.self, multiPriority: 5,
                params: TestGainModule.Params(gain: 2.0))
            let layerBoxMade = await registry.makeBox(
                opName: layerRecord.opName, instanceID: layerRecord.id)
            let layerBox = try XCTUnwrap(layerBoxMade as? ModuleBox<TestGainModule>)
            try layerBox.apply(layerRecord)
            let flat = (flatBase + [layerBox]).sorted {
                ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
            }
            let (flatTexture, _) = try await RenderPipeline.process(
                image: image, instances: flat, imageID: UUID(),
                resolution: resolution, cache: PipeCache(), metal: metal,
                longEdge: nil)

            assertBytesEqual(
                rawBytes(result.output, metal: metal),
                rawBytes(flatTexture, metal: metal),
                "op=1.0 composite vs flat merged chain (\(resolution))")
        }
    }

    /// op = 0.0 ⇒ composite == the base-only run (both resolutions).
    func testOpacityZeroEqualsBaseOnly() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let cache = PipeCache()

        for resolution in [PipeResolution.preview, .full] {
            let base = try await makeBaseInstances(registry: registry, baseGain: 1.2)
            var stack = LayerStack(baseLayer: BackgroundLayer())
            stack.addAdjustment(layerWithGain(3.0, opacity: 0.0))

            let result = try await composite(
                image, base, stack, registry: registry, metal: metal,
                resolution: resolution, cache: cache)
            let (baseOnly, _) = try await RenderPipeline.process(
                image: image, instances: base, imageID: UUID(),
                resolution: resolution, cache: PipeCache(), metal: metal,
                longEdge: nil)

            assertBytesEqual(
                rawBytes(result.output, metal: metal),
                rawBytes(baseOnly, metal: metal),
                "op=0.0 composite vs base-only (\(resolution))")
        }
    }

    /// Empty-chain layer (op=1.0 ⇒ L ≡ S, exact) and disabled/hidden layers
    /// are content no-ops; enabled vs visible semantics differ structurally
    /// (disabled = no sub-run at all).
    func testEmptyDisabledHiddenLayersAreNoOps() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let cache = PipeCache()
        let base = try await makeBaseInstances(registry: registry, baseGain: 1.2)
        let (baseOnly, _) = try await RenderPipeline.process(
            image: image, instances: base, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let baseBytes = rawBytes(baseOnly, metal: metal)

        // Empty chain, op 1.0 → L ≡ S ⇒ composite == base, byte-exact.
        do {
            var stack = LayerStack(baseLayer: BackgroundLayer())
            stack.addAdjustment(AdjustmentLayer(name: "empty", opacity: 1.0))
            let result = try await composite(
                image, base, stack, registry: registry, metal: metal,
                resolution: .preview, cache: PipeCache())
            assertBytesEqual(
                rawBytes(result.output, metal: metal), baseBytes,
                "empty-chain layer (op=1) is a no-op")
        }

        // Disabled layer: blend skipped — exact no-op at ANY opacity.
        do {
            var stack = LayerStack(baseLayer: BackgroundLayer())
            let layer = layerWithGain(3.0, opacity: 0.8)
            layer.enabled = false
            stack.addAdjustment(layer)
            let result = try await composite(
                image, base, stack, registry: registry, metal: metal,
                resolution: .preview, cache: PipeCache())
            XCTAssertEqual(result.layerStats.count, 0,
                           "disabled layer produces NO composite leg")
            assertBytesEqual(
                rawBytes(result.output, metal: metal), baseBytes,
                "disabled layer is a no-op")
        }

        // Hidden (visible=false) layer: PROCESSED but not blended.
        do {
            var stack = LayerStack(baseLayer: BackgroundLayer())
            let layer = layerWithGain(3.0, opacity: 1.0)
            layer.isVisible = false
            stack.addAdjustment(layer)
            let cache2 = PipeCache()
            let result = try await composite(
                image, base, stack, registry: registry, metal: metal,
                resolution: .preview, cache: cache2)
            XCTAssertEqual(result.layerStats.count, 1,
                           "hidden layer still runs its sub-run")
            XCTAssertGreaterThan(result.layerStats[0].run.misses, 0,
                                 "hidden layer's chain planes were rendered")
            XCTAssertFalse(result.layerStats[0].prefixHit,
                           "hidden layer performs NO blend/prefix probe")
            assertBytesEqual(
                rawBytes(result.output, metal: metal), baseBytes,
                "hidden layer is a composite no-op")
        }
    }

    // ── 2. Independent params (LAYER-02) — content differs from base ──

    /// A layer's gain ACTUALLY shows: composite(op=1, gain 2.5) differs
    /// from base-only (compared > 0 divergent bytes) AND matches the flat
    /// merged chain (covered by the op=1 gate above).
    func testLayerParamsChangeTheComposite() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let base = try await makeBaseInstances(registry: registry, baseGain: 1.0)

        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layerWithGain(2.5, opacity: 1.0))
        let result = try await composite(
            image, base, stack, registry: registry, metal: metal,
            resolution: .preview, cache: PipeCache())
        let (baseOnly, _) = try await RenderPipeline.process(
            image: image, instances: base, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)

        assertBytesDiffer(
            rawBytes(result.output, metal: metal),
            rawBytes(baseOnly, metal: metal),
            "layer gain 2.5 must change the composite vs base-only")
    }

    // ── 3. Cross-layer ROI (L021 layer dimension) ──

    /// The composite window follows the negotiated ROI: with `roiHint`,
    /// every leg consumes exactly the hinted window and the windowed
    /// composite (op=1) equals the flat merged chain AT THE SAME window —
    /// per-layer dscIn/iscale stamps are the sub-runs' own (the resident
    /// driver preconditions held; this is the content-level corroboration).
    func testWindowedCompositeMatchesFlatRunAtSameWindow() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage(width: 96, height: 64)
        let base = try await makeBaseInstances(registry: registry, baseGain: 1.2)

        let hint = ROI(x: 8, y: 6, width: 64, height: 40, scale: 1.0)
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layerWithGain(2.0, opacity: 1.0))

        let result = try await composite(
            image, base, stack, registry: registry, metal: metal,
            resolution: .full, cache: PipeCache(), roiHint: hint)
        XCTAssertEqual(result.window.x, hint.x)
        XCTAssertEqual(result.window.y, hint.y)
        XCTAssertEqual(result.window.width, hint.width)
        XCTAssertEqual(result.window.height, hint.height)
        XCTAssertEqual(result.output.width, hint.width, "FULL windowed plane == window (D-06-CONTEXT-8 shape)")
        XCTAssertEqual(result.output.height, hint.height)

        let layerRecord = ModuleInstance(
            module: TestGainModule.self, multiPriority: 5,
            params: TestGainModule.Params(gain: 2.0))
        let layerBoxMade = await registry.makeBox(
            opName: layerRecord.opName, instanceID: layerRecord.id)
        let layerBox = try XCTUnwrap(layerBoxMade as? ModuleBox<TestGainModule>)
        try layerBox.apply(layerRecord)
        let flat = (base + [layerBox]).sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
        let (flatWindowed, _) = try await RenderPipeline.process(
            image: image, instances: flat, imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal,
            longEdge: nil, roiHint: hint)
        XCTAssertEqual(flatWindowed.width, hint.width)
        assertBytesEqual(
            rawBytes(result.output, metal: metal),
            rawBytes(flatWindowed, metal: metal),
            "windowed composite vs windowed flat merged chain")
    }

    // ── 4. Geometry rejection (D-06-CONTEXT-5) ──

    /// The pure detector: every forbidden slot (lens 13 / ashift 15 /
    /// flip 16 / clipping 17) is caught by op name; identity chains pass.
    /// The driver enforces this with fatal semantics BEFORE any GPU work
    /// (fatalError is untestable in-process — the detector is the testable
    /// face; D-06-01-T4-1).
    func testLayerGeometryDetectorCatchesAllForbiddenSlots() {
        let forbiddenOps = V50Order.entries
            .filter { [13.0, 15.0, 16.0, 17.0].contains($0.order) }
            .map(\.opName)
        XCTAssertGreaterThanOrEqual(forbiddenOps.count, 4,
                                    "the four geometry slots must exist in the table")
        XCTAssertGreaterThan(forbiddenOps.count, 0, "防空转 guard")

        for op in forbiddenOps {
            let record = ModuleInstance(
                id: UUID(), opName: op, multiPriority: 0, multiName: "",
                iopOrder: V50Order.order(for: op) ?? 0, version: 1,
                enabled: true, paramsData: Data("{}".utf8), paramsHash: 1)
            let violation = LayerCompositeDriver.layerGeometryViolation([record])
            XCTAssertEqual(violation, op, "geometric op \(op) must be detected in a layer chain")
        }

        let identity = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        XCTAssertNil(
            LayerCompositeDriver.layerGeometryViolation([identity]),
            "identity chains pass the detector")
    }

    // ── 5. Blend attribute support (6-1 scope) ──

    /// REVERSE flag: swaps a/b — at op=1 with reverse the composite equals
    /// the BELOW plane (a/b swapped ⇒ below·1 + layer·0). Non-normal MODES
    /// are rejected by the driver's precondition (fatal semantics — the
    /// untestable-in-process face is documented in D-06-01-T4-1; the
    /// 6-2 engine owns the mode table).
    func testReverseFlagSwapsAB() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let base = try await makeBaseInstances(registry: registry, baseGain: 1.2)
        let (baseOnly, _) = try await RenderPipeline.process(
            image: image, instances: base, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)

        var stack = LayerStack(baseLayer: BackgroundLayer())
        let layer = layerWithGain(3.0, opacity: 1.0)
        layer.blendOptions = [.reverse]
        stack.addAdjustment(layer)
        let result = try await composite(
            image, base, stack, registry: registry, metal: metal,
            resolution: .preview, cache: PipeCache())

        assertBytesEqual(
            rawBytes(result.output, metal: metal),
            rawBytes(baseOnly, metal: metal),
            "REVERSE at op=1 ⇒ the composite equals the below (base) plane")
    }

    // ── 6. Track B zero-increment baseline (Plan 06-01 T7) ──

    /// The FULL track-B chain (Phase 3+4+5 EVERY module — crop/flip/lens +
    /// the detail/color/denoise neutrals, GeometryGoldenTests harness) with
    /// a SINGLE degenerate layer (identity gain, op=1.0) composited on top
    /// must be BYTE-IDENTICAL to the layerless baseline: the layer core is
    /// a pure zero-increment for the Phase 2-5 pipeline (L020 ③ content
    /// level — real RAW through the real chain).
    func testTrackBFullChainWithIdentityLayerIsZeroIncrement() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let chain = try await GeometryGoldenTests().makeChainWithCropFlip(
            registry: registry, outputProfile: .displayP3)

        // Baseline: the track-B chain alone.
        let (baseline, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)

        // Layered: ONE identity layer (gain 1.0 ⇒ L ≡ S; op 1.0 ⇒ out = L).
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let identity = ModuleInstance(
            module: TestGainModule.self, multiPriority: 5,
            params: TestGainModule.Params(gain: 1.0))
        stack.addAdjustment(
            AdjustmentLayer(name: "identity", opacity: 1.0, chain: [identity]))

        let result = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: chain,
            layerStack: stack, registry: registry, resolution: .preview,
            cache: PipeCache(), metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview)

        // Terminal-segment output is .bgra8Unorm on both legs — compare
        // the raw RGBA bytes exactly (a REAL comparison loop with a
        // compared > 0 guard via assertBytesEqual).
        assertBytesEqual(
            rawBytes(result.output, metal: metal),
            rawBytes(baseline, metal: metal),
            "track-B full chain + identity layer == layerless baseline")
    }
}

// MARK: - 06-02 T5 extensions (blend engine in the driver path)

extension LayerCompositeTests {

    /// A flat-gray image (the perceptual neutral gate's fixture).
    private func makeGrayImage(width: Int = 32, height: Int = 24) -> DecodedImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<width * height {
            pixels[i * 4 + 0] = 0.42
            pixels[i * 4 + 1] = 0.42
            pixels[i * 4 + 2] = 0.42
            pixels[i * 4 + 3] = 1.0
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

    /// 灰轴不偏色 (plan 06-02-T5): a perceptual-mode layer over a NEUTRAL
    /// image must not introduce chroma — every output channel stays equal
    /// (the achromatic zero-radius invariant: hue rotations of neutrals are
    /// no-ops, Jz/Cz mixes of equal chromas keep the axis).
    func testPerceptualModesOnNeutralStayNeutral() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let gray = makeGrayImage()
        let base = try await makeBaseInstances(registry: registry, baseGain: 1.1)

        for mode in [BlendMode.luminosity, .saturation, .hue, .color, .colorAdjust] {
            var stack = LayerStack(baseLayer: BackgroundLayer())
            stack.addAdjustment(layerWithGain(2.0, opacity: 0.6))
            stack.compositeLayers[0].blendMode = mode
            let result = try await composite(
                gray, base, stack, registry: registry, metal: metal,
                resolution: .preview, cache: PipeCache())
            let bytes = rawBytes(result.output, metal: metal)
            var compared = 0
            var maxChannelDev: Float = 0
            for i in stride(from: 0, to: bytes.count, by: 4) {
                // Display tail is 8-bit RGBA: the channel equality gate is
                // one display step.
                let r = Float(bytes[i]), g = Float(bytes[i + 1]), b = Float(bytes[i + 2])
                maxChannelDev = max(maxChannelDev, abs(r - g), abs(r - b))
                compared += 1
            }
            XCTAssertGreaterThan(compared, 0, "防空转 \(mode)")
            XCTAssertLessThanOrEqual(
                maxChannelDev, 1.0,
                "\(mode): neutral input must stay neutral (max channel dev \(maxChannelDev))")
        }
    }

    /// The driver end-to-end with a NON-normal mode, numerically closed
    /// form: base = a single gain (NO terminal modules → the output plane
    /// is the working space), layer = EMPTY chain (L ≡ S), multiply at
    /// op=1 ⇒ composite = S². S = fixture × gain — fully determined, so
    /// the whole path (driver → runSub → compositeLayer → prefix hash) is
    /// pinned numerically outside the identity modes.
    func testDriverMultiplyCompositeClosedForm() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage(width: 32, height: 24)
        let cache = PipeCache()

        // Base: colorin+trio replaced by a bare gain (no terminal).
        let gainMade = await registry.makeBox(opName: TestGainModule.opName)
        let gain = try XCTUnwrap(gainMade as? ModuleBox<TestGainModule>)
        gain.setParams(TestGainModule.Params(gain: 1.2))

        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(AdjustmentLayer(
            name: "sq", opacity: 1.0, blendMode: .multiply))

        let result = try await LayerCompositeDriver.composite(
            image: image, imageID: Self.fixtureImageID, baseInstances: [gain],
            layerStack: stack, registry: registry, resolution: .preview,
            cache: cache, metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview)

        // The closed form: out = (fixture·1.2)². The output plane here is
        // the WORKING SPACE (no terminal) — read it as float32 (16 B/px),
        // not with the display-format rawBytes helper.
        let floats = rawFloats(result.output, metal: metal)
        var compared = 0
        var maxRel: Float = 0
        for y in 0..<24 {
            for x in 0..<32 {
                let p = Self.fixturePixelForDriver(x, y)
                for c in 0..<3 {
                    let sv = Double(p[c]) * 1.2
                    let expected = Float(sv * sv)
                    let gotv = floats[(y * 32 + x) * 4 + c]
                    maxRel = max(
                        maxRel, abs(gotv - expected) / max(expected, 1e-6))
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转")
        XCTAssertLessThanOrEqual(maxRel, 1e-5, "driver multiply closed form (S²)")
    }

    /// L014 fence + float32 read for working-space planes (16 B/px — the
    /// shared rawBytes helper assumes the 8-bit display format).
    private func rawFloats(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var out = [Float](repeating: 0, count: texture.width * texture.height * 4)
        out.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return out
    }

    /// The fixture pixel used by `makeImage` (kept in one place for the
    /// closed-form assertion above).
    private static func fixturePixelForDriver(_ x: Int, _ y: Int) -> SIMD3<Float> {
        SIMD3<Float>(
            0.1 + 0.7 * Float(x) / 31.0,
            0.2 + 0.5 * Float(y) / 23.0,
            0.3 + 0.3 * Float(x + y) / 54.0)
    }
}
