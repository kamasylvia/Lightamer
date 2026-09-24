@testable import LightamerCore
import CoreImage
@testable import LightamerIOP
import Metal
import XCTest

/// Plan 08-01 — the yiyin borders (印框) module suite.
///
/// T1 sections: registration at the verbatim v50 slot 76.0, the
/// enabled-neutral seed identity (byte-exact through the real pipe —
/// 轨 B 中性插链 == 无实例), the disabled-instance equivalence, the
/// WIDENED terminal tail window (`iopOrder ≥ 70.0` — the plan's ONLY
/// pipeline change), and the gamma-tail format policy (borders planes
/// stay float32; gamma remains the display handoff).
///
/// Later sections (same file): T2 layout parity, T3 solid/color/ROI,
/// T4 radius/shadow, T5 blur/adaptive overlay.
final class YiyinBordersTests: XCTestCase {

    // ── Fixtures (CropParityTests/LayerCompositeTests twins) ──

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// Unique-value gradient (every pixel distinct — offset/geometry errors
    /// fail loudly).
    private func gradientImage(width: Int, height: Int) -> DecodedImage {
        var rgba = [Float](repeating: 1.0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = Float(x * height + y) / Float(width * height)
                rgba[(y * width + x) * 4] = v
                rgba[(y * width + x) * 4 + 1] = v
                rgba[(y * width + x) * 4 + 2] = v
            }
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    private func committedTrio(
        outputProfile: ColorOutModule.OutputProfile = .sRGB
    ) async -> [any ModuleBoxing] {
        await TerminalTrioTests.makeCommittedDefaultChain(
            registry: ModuleRegistry.makeDefault(), outputProfile: outputProfile)
    }

    private func neutralBordersBox() -> ModuleBox<BordersModule> {
        let box = ModuleBox(module: BordersModule())
        box.setParams(BordersModule.Params.neutralSeed)
        return box
    }

    private func readBytes(_ texture: any MTLTexture, metal: MetalContext) -> [UInt8] {
        drain(metal)
        let bpp = texture.pixelFormat == GammaModule.outputPixelFormat ? 4 : 16
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * bpp)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * bpp,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return bytes
    }

    // ── T1: registration ──

    func testBordersRegisteredAtV50Slot() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: BordersModule.opName)
        let bordersBox = try XCTUnwrap(box as? ModuleBox<BordersModule>)
        XCTAssertEqual(bordersBox.opName, "borders")
        XCTAssertEqual(bordersBox.iopOrder, 76.0, "verbatim V50Order slot — zero rows inserted")
        XCTAssertEqual(BordersModule.defaultColorspace, .RGB)
        let id = UUID()
        let restored = await registry.makeBox(opName: BordersModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
        // Single registration: the op resolves to ONE factory (re-register
        // would be last-wins; assert the slot is present exactly once by
        // resolving twice with stable identity fields).
        let again = await registry.makeBox(opName: BordersModule.opName)
        XCTAssertEqual(again?.opName, BordersModule.opName)
        XCTAssertEqual(again?.iopOrder, 76.0)
    }

    func testBordersJoinsEditingSeedAsNeutral() async {
        let seed = LightamerIOPRegistry.editingDefaultInstances()
        let borders = seed.filter { $0.opName == BordersModule.opName }
        XCTAssertEqual(borders.count, 1, "exactly one borders instance in the seed")
        XCTAssertEqual(borders.first?.enabled, true, "seed is enabled-neutral")
        let decoded = try? JSONDecoder().decode(
            BordersModule.Params.self, from: borders.first!.paramsData)
        XCTAssertEqual(decoded, BordersModule.Params.neutralSeed, "seed params = identity face")
    }

    // ── T1: seed identity (轨 B 中性插链 == 无实例, byte-exact) ──

    func testSeedIdentityIsByteExactThroughPipe() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 64, height: 48)
        let trio = await committedTrio()
        let withBorders = (trio + [neutralBordersBox() as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (plain, plainStats) = try await RenderPipeline.process(
            image: image, instances: trio, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let (bordered, borderedStats) = try await RenderPipeline.process(
            image: image, instances: withBorders, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)

        XCTAssertEqual(bordered.width, plain.width, "neutral canvas == image")
        XCTAssertEqual(bordered.height, plain.height)
        XCTAssertEqual(
            bordered.pixelFormat, plain.pixelFormat,
            "gamma stays the tail — the display format policy is unchanged")
        let a = readBytes(plain, metal: metal)
        let b = readBytes(bordered, metal: metal)
        XCTAssertEqual(a.count, b.count)
        XCTAssertGreaterThan(a.count, 0, "防空转: bytes compared")
        XCTAssertEqual(a, b, "neutral borders insertion == no-instance baseline, byte-exact")
        XCTAssertEqual(
            plainStats.planesRendered + 1, borderedStats.planesRendered,
            "exactly one extra plane (the borders blit) — no hidden walk growth")
    }

    func testDisabledBordersEqualsNoInstance() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 48, height: 64)
        let trio = await committedTrio()
        let box = neutralBordersBox()
        box.enabled = false
        let withBorders = (trio + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (plain, plainStats) = try await RenderPipeline.process(
            image: image, instances: trio, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let (bordered, borderedStats) = try await RenderPipeline.process(
            image: image, instances: withBorders, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(borderedStats.misses, plainStats.misses, "disabled piece folds no key step")
        let a = readBytes(plain, metal: metal)
        let b = readBytes(bordered, metal: metal)
        XCTAssertGreaterThan(a.count, 0, "防空转")
        XCTAssertEqual(a, b, "disabled instance == no instance, byte-exact")
    }

    // ── T1: the widened terminal tail window ──

    func testTailWindowExtraction() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let trio = await committedTrio()
        let skin = await registry.makeBox(opName: SkinSmoothModule.opName)
        let borders = neutralBordersBox()

        let all = (trio + [skin!, borders as any ModuleBoxing])
        let (base, terminal) = LayerCompositeDriver.splitTerminal(all)
        // Terminal tail: colorout 70.0 → borders 76.0 → gamma 78.0, v50-sorted.
        XCTAssertEqual(terminal.map(\.opName), ["colorout", "borders", "gamma"])
        // Base keeps everything below the floor — skinSmooth 66.5 and
        // colorin 28.0 stay base (zero legacy behavior change).
        XCTAssertEqual(base.map(\.opName), ["colorin", "skinSmooth"])
    }

    func testTailWindowRoutesBordersToTerminalSegmentWithLayers() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let image = gradientImage(width: 48, height: 32)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        chain.append(neutralBordersBox())
        // An identity adjustment layer: the layer legs composite BEFORE the
        // terminal segment — borders must ride the terminal sub-run, never
        // a layer leg (the 层内纪律: the extraction removes borders from
        // every layer-facing chain by construction).
        let layer = AdjustmentLayer(
            name: "L", opacity: 1.0,
            chain: [ModuleInstance(
                module: TestGainModule.self, multiPriority: 5,
                params: TestGainModule.Params(gain: 1.0))])
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layer)

        let result = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: chain, layerStack: stack,
            registry: registry, resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil, roiHint: nil, policy: .preview)
        XCTAssertEqual(result.window.width, 48, "the composite window stays image-sized")
        XCTAssertEqual(result.window.height, 32)
        XCTAssertEqual(result.output.width, 48)
        XCTAssertEqual(result.output.height, 32, "neutral borders keeps the output image-sized")
        XCTAssertNotNil(result.terminalStats, "the terminal segment ran")
    }

    // ── T1: tail format policy (borders planes stay float32) ──

    func testTailPolicyGammaTopUnchanged() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 40, height: 30)
        let trio = await committedTrio()
        let withBorders = (trio + [neutralBordersBox() as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (output, _) = try await RenderPipeline.process(
            image: image, instances: withBorders, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(
            output.pixelFormat, GammaModule.outputPixelFormat,
            "gamma remains the tail — borders/watermark planes stay float32 interior")
    }

    // ── T1: Params discipline (L013) + clamps ──

    func testCommitHashesRawParamsViaParamsCoding() {
        let box = ModuleBox(module: BordersModule())
        let params = BordersModule.Params.neutralSeed
        box.setParams(params)
        XCTAssertEqual(box.paramsData, ParamsCoding.encode(params))
        XCTAssertEqual(box.paramsHash, StableHash.hash(ParamsCoding.encode(params)))
        // D-H4: the record face carries the same atom.
        let record = ModuleInstance(
            module: BordersModule.self, params: params)
        XCTAssertEqual(record.paramsHash, box.paramsHash)
    }

    func testCommitClamps() {
        var p = BordersModule.Params.neutralSeed
        p.mainImageWidthRate = -5
        p.miniTopBottomMargin = 300
        p.cornerRadius = 99
        p.shadow = -1
        p.aspectRatio = BordersModule.AspectRatio(w: 0, h: 3)
        p.landscapeOutput = true
        p.mode = .blur(amount: 400)
        let c = BordersModule.clamp(p)
        XCTAssertEqual(c.mainImageWidthRate, 1)
        XCTAssertEqual(c.miniTopBottomMargin, 100)
        XCTAssertEqual(c.cornerRadius, 50, "yiyin input cap 50")
        XCTAssertEqual(c.shadow, 0)
        XCTAssertEqual(c.landscapeOutput, false, "aspect ⇒ landscape force-clear (onBGRateChange)")
        XCTAssertEqual(c.aspectRatio?.w, 1)
        if case .blur(let amount) = c.mode {
            XCTAssertEqual(amount, 100)
        } else {
            XCTFail("mode must round-trip")
        }
    }

    func testNeutralPredicate() {
        XCTAssertTrue(BordersModule().isNeutral(.neutralSeed))
        var notNeutral = BordersModule.Params.neutralSeed
        notNeutral.mainImageWidthRate = 90
        XCTAssertFalse(BordersModule().isNeutral(notNeutral))
        var margin = BordersModule.Params.neutralSeed
        margin.miniTopBottomMargin = 5
        XCTAssertFalse(BordersModule().isNeutral(margin))
        var aspect = BordersModule.Params.neutralSeed
        aspect.aspectRatio = .init(w: 3, h: 2)
        XCTAssertFalse(BordersModule().isNeutral(aspect))
        var radius = BordersModule.Params.neutralSeed
        radius.cornerRadius = 2.1
        XCTAssertFalse(BordersModule().isNeutral(radius))
    }
}
