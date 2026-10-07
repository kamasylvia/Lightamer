@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// EffectsWiringTests (Plan 08-2 T4) — the effect-cluster wiring face:
///
/// 1. LAYER-MASK LOCALIZATION ×3 (vignette/grain/bloom): an adjustment
///    layer carrying the effect instance + an ellipse mask — the masked
///    interior shows the effect (L020 content-level difference) and the
///    mask exterior is BYTE-identical to the base composite (the normal
///    blend `a·(1−op) + b·op` at op == mask.r == 0.0 reduces to `a`
///    bitwise for non-negative channels).
/// 2. IDENTITY THROUGH THE PIPE: vignette/grain ENABLED-neutral instances
///    (the routed-blit fast paths) and the bloom DISABLED seed keep the
///    chain byte-identical (exposure-0EV style cache neutrality).
/// 3. PREVIEW PERF PROBE (只记不设门): one preview-chain render timing per
///    module, recorded into perf.md — no duration assertions.
///
/// L031: the modules' GPU submissions were grepped to
/// `makeEncoder`/`makeRoutedCommandBuffer`/`dispatch2DTexture` only (the
/// SUMMARY carries the grep output).
final class EffectsWiringTests: XCTestCase {

    // ── Fixtures (the LayerCompositeTests shape) ──

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeImage(width: Int = 64, height: Int = 48) -> DecodedImage {
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

    /// The ellipse mask: centered, soft border (the localization probes
    /// stay inside the solid core).
    private func ellipseMask() -> MaskSpec {
        MaskSpec(
            version: 1,
            drawn: DrawnMaskSpec(
                forms: [
                    MaskForm(
                        kind: .ellipse(
                            EllipseForm(
                                center: MaskPoint(x: 0.5, y: 0.5),
                                radiusX: 0.3, radiusY: 0.3,
                                rotationDegrees: 0, border: 0.1)))
                ],
                group: nil))
    }

    private struct ComposedPlane {
        let bytes: [UInt8]
        let width: Int
        let height: Int

        /// The display-tail output is `.bgra8Unorm` — R = byte 2.
        func red(_ x: Int, _ y: Int) -> Float {
            Float(bytes[(y * width + x) * 4 + 2]) / 255.0
        }

        func pixelBytes(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
            let o = (y * width + x) * 4
            return bytes[o..<o + 4]
        }
    }

    /// Compose through the LayerCompositeDriver (the same driver shape for
    /// base and layered so the byte comparisons stay same-code-path).
    private func composite(
        _ image: DecodedImage,
        base: [any ModuleBoxing],
        stack: LayerStack?,
        registry: ModuleRegistry,
        metal: MetalContext
    ) async throws -> ComposedPlane {
        let empty = stack ?? LayerStack(baseLayer: BackgroundLayer())
        let result = try await LayerCompositeDriver.composite(
            image: image, imageID: Self.fixtureImageID, baseInstances: base,
            layerStack: empty, registry: registry, resolution: .preview,
            cache: PipeCache(), metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview)
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        let texture = result.output
        // The terminal tail encodes to the display format (.bgra8Unorm).
        let bytesPerPixel = 4
        var bytes = [UInt8](
            repeating: 0, count: texture.width * texture.height * bytesPerPixel)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * bytesPerPixel,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return ComposedPlane(bytes: bytes, width: texture.width, height: texture.height)
    }

    private static let fixtureImageID = UUID()

    /// The shared localization leg: an effect layer + ellipse mask must
    /// move the masked interior and leave the far corner byte-identical.
    /// `samplePoint` picks the interior probe (vignette passes an
    /// OFF-CENTER point — its own center is weight-0 by design).
    private func runLocalization(
        opName: String,
        setParams: (any ModuleBoxing) -> Void,
        interiorChanged: (Float, Float) -> Bool,
        label: String,
        samplePoint: ((Int, Int) -> (x: Int, y: Int))? = nil
    ) async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let base = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        // The effect layer: one record of the effect instance + the mask.
        let recordID = UUID()
        let made = await registry.makeBox(opName: opName, instanceID: recordID)
        let box = try XCTUnwrap(made, "\(label): must register")
        setParams(box)
        let record = ModuleInstance(
            id: recordID, opName: opName, multiPriority: 5, multiName: label,
            iopOrder: box.iopOrder, version: 1, enabled: true,
            paramsData: box.paramsData, paramsHash: box.paramsHash)
        let layer = AdjustmentLayer(name: label, opacity: 1.0, chain: [record])
        layer.mask = ellipseMask()
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layer)

        let basePlane = try await composite(
            image, base: base, stack: nil, registry: registry, metal: metal)
        let layeredPlane = try await composite(
            image, base: base, stack: stack, registry: registry, metal: metal)

        XCTAssertEqual(basePlane.width, layeredPlane.width, "\(label): width mismatch")
        XCTAssertEqual(basePlane.height, layeredPlane.height, "\(label): height mismatch")
        XCTAssertEqual(basePlane.bytes.count, layeredPlane.bytes.count, "\(label): size mismatch")
        XCTAssertGreaterThan(basePlane.bytes.count, 0, "\(label): anti-vacuum")

        // Sample points (bgra8 display planes): the mask interior is the
        // image center (the ellipse center); the far corner is outside.
        let interior = samplePoint?(basePlane.width, basePlane.height)
            ?? (x: basePlane.width / 2, y: basePlane.height / 2)
        let corner = (x: 2, y: 2)

        // INTERIOR: the effect must be visible (content-level difference).
        let baseR = basePlane.red(interior.x, interior.y)
        let layeredR = layeredPlane.red(interior.x, interior.y)
        XCTAssertTrue(
            interiorChanged(baseR, layeredR),
            "\(label): the masked interior must show the effect at "
                + "(\(interior.x),\(interior.y)) "
                + "(base r=\(baseR) → layered r=\(layeredR))")

        // EXTERIOR: byte-identical to the base composite (mask weight 0 →
        // a·(1−0) + b·0 == a bitwise for non-negative channels).
        XCTAssertEqual(
            Array(basePlane.pixelBytes(corner.x, corner.y)),
            Array(layeredPlane.pixelBytes(corner.x, corner.y)),
            "\(label): the mask exterior must be byte-identical")
    }

    func testVignetteLayerMaskLocalization() async throws {
        try await runLocalization(
            opName: VignetteModule.opName,
            setParams: { box in
                (box as? ModuleBox<VignetteModule>)?.setParams(
                    VignetteModule.Params(scale: 0, falloffScale: 200, brightness: -1.0))
            },
            interiorChanged: { baseR, layeredR in
                // The fall-off darkens the off-center interior (weight > 0
                // there — the exact vignette center stays weight-0 BY
                // DESIGN, so the sample point is offset from the center).
                layeredR < baseR - 0.03
            },
            label: "vignette-mask",
            samplePoint: { width, height in (x: width * 3 / 4, y: height / 2) })
    }

    func testGrainLayerMaskLocalization() async throws {
        try await runLocalization(
            opName: GrainModule.opName,
            setParams: { box in
                (box as? ModuleBox<GrainModule>)?.setParams(
                    GrainModule.Params(strength: 100))
            },
            interiorChanged: { baseR, layeredR in
                // Strong grain injects luma noise — the interior pixel
                // must MOVE (either direction).
                abs(layeredR - baseR) > 1e-4
            },
            label: "grain-mask")
    }

    func testBloomLayerMaskLocalization() async throws {
        try await runLocalization(
            opName: BloomModule.opName,
            setParams: { box in
                (box as? ModuleBox<BloomModule>)?.setParams(
                    BloomModule.Params(size: 10, threshold: 0, strength: 40))
            },
            interiorChanged: { baseR, layeredR in
                // threshold 0 → everything extracts → screen brightens.
                layeredR > baseR + 1e-4
            },
            label: "bloom-mask")
    }

    // MARK: - Identity through the pipe (L031 neutral fast paths)

    func testNeutralAndDisabledSeedsByteIdentity() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let base = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        let basePlane = try await composite(
            image, base: base, stack: nil, registry: registry, metal: metal)

        func appended(_ opName: String, _ configure: (any ModuleBoxing) -> Void)
            async throws -> ComposedPlane {
            let made = await registry.makeBox(opName: opName)
            let box = try XCTUnwrap(made)
            configure(box)
            var chain = base
            chain.append(box)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            return try await composite(
                image, base: chain, stack: nil, registry: registry, metal: metal)
        }

        // vignette ENABLED-neutral (brightness 0 + saturation 0 → the
        // routed-blit value identity).
        let vignettePlane = try await appended(VignetteModule.opName) { box in
            (box as? ModuleBox<VignetteModule>)?.setParams(
                VignetteModule.Params(brightness: 0, saturation: 0))
        }
        XCTAssertEqual(
            basePlane.bytes, vignettePlane.bytes,
            "the enabled-neutral vignette must stay byte-identical")

        // grain ENABLED-neutral (strength 0 → the routed-blit identity).
        let grainPlane = try await appended(GrainModule.opName) { box in
            (box as? ModuleBox<GrainModule>)?.setParams(
                GrainModule.Params(strength: 0))
        }
        XCTAssertEqual(
            basePlane.bytes, grainPlane.bytes,
            "the enabled-neutral grain must stay byte-identical")

        // bloom DISABLED (no zero-param identity — the creative
        // disposition; the disabled piece is skipped by the pipe walk).
        let bloomPlane = try await appended(BloomModule.opName) { box in
            (box as? ModuleBox<BloomModule>)?.enabled = false
        }
        XCTAssertEqual(
            basePlane.bytes, bloomPlane.bytes,
            "the disabled bloom seed must stay byte-identical")
    }

    // MARK: - Preview perf probe (只记不设门 — recorded into perf.md)

    func testEffectsPreviewPerfProbe() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage(width: 2560, height: 1707)
        let base = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        let probes: [(String, (any ModuleBoxing) -> Void)] = [
            ("vignette", { box in
                (box as? ModuleBox<VignetteModule>)?.setParams(
                    VignetteModule.Params()) // dt defaults
            }),
            ("grain", { box in
                (box as? ModuleBox<GrainModule>)?.setParams(
                    GrainModule.Params()) // dt defaults
            }),
            ("bloom", { box in
                (box as? ModuleBox<BloomModule>)?.setParams(
                    BloomModule.Params()) // dt defaults
            }),
        ]

        var lines: [String] = []
        for (opName, configure) in probes {
            let made = await registry.makeBox(opName: opName)
            let box = try XCTUnwrap(made)
            configure(box)
            var chain = base
            chain.append(box)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            // Warm-up (PSO + caches), then 10 timed preview renders.
            _ = try await composite(
                image, base: chain, stack: nil, registry: registry, metal: metal)
            var samples: [Double] = []
            for _ in 0..<10 {
                let start = DispatchTime.now()
                _ = try await composite(
                    image, base: chain, stack: nil, registry: registry, metal: metal)
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds)
                    / 1_000_000
                samples.append(ms)
            }
            samples.sort()
            let median = samples[samples.count / 2]
            lines.append("\(opName): median \(String(format: "%.1f", median)) ms")
        }
        // 只记不设门：the numbers land in perf.md (no duration assertion).
        print("PERF8-EFFECTS preview-chain (2560px, Debug) — " + lines.joined(separator: " | "))
    }
}
