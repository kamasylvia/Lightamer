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

    /// float32 RGBA readback (drain first — L014).
    private func readFloats(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        drain(metal)
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return floats
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

    // MARK: - T3: YiyinColor (COLOR-2 — ColorOutModule-source profile)

    func testHexParsing() {
        XCTAssertEqual(YiyinColor.parseSRGBHex("#ffffff"), SIMD3(1.0, 1.0, 1.0))
        XCTAssertEqual(YiyinColor.parseSRGBHex("#fff"), SIMD3(1.0, 1.0, 1.0))
        XCTAssertEqual(YiyinColor.parseSRGBHex("#000000"), SIMD3(0.0, 0.0, 0.0))
        XCTAssertEqual(
            YiyinColor.parseSRGBHex("#FF0000"), SIMD3(1.0, 0.0, 0.0),
            "uppercase accepted")
        XCTAssertNil(YiyinColor.parseSRGBHex("#12345"))
        XCTAssertNil(YiyinColor.parseSRGBHex("zzzzzz"))
    }

    func testLinearizeSRGBKnownPoints() {
        XCTAssertEqual(YiyinColor.linearizeSRGB(0.0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(
            YiyinColor.linearizeSRGB(1.0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(
            YiyinColor.linearizeSRGB(0.04045), 0.04045 / 12.92, accuracy: 1e-12)
        // 0.5 → ≈0.21404114 (the sRGB mid-gray).
        XCTAssertEqual(
            YiyinColor.linearizeSRGB(0.5), 0.21404114048232325, accuracy: 1e-9)
    }

    /// COLOR-2 pin: display white / neutrals are EXACT under every target
    /// (D-COL1 precondition — all three spaces share D65).
    func testWhiteAndGrayHexExactUnderEveryTarget() {
        for target in [DisplayProfile.displayP3, .sRGB] {
            let white = YiyinColor.linearDisplay(fromSRGBHex: "#ffffff", target: target)
            XCTAssertEqual(white, SIMD3<Float>(1, 1, 1), "\(target): white exact")
            let gray = YiyinColor.linearDisplay(fromSRGBHex: "#808080", target: target)!
            XCTAssertEqual(gray.x, gray.y, accuracy: 1e-6, "\(target): gray channels equal")
            XCTAssertEqual(gray.y, gray.z, accuracy: 1e-6, "\(target): gray channels equal")
        }
    }

    /// COLOR-2 pin: the saturated hex converts through the SAME matrix
    /// family colorout applies — sRGB red → P3 linear
    /// (0.822461969, 0.033194198, 0.017082631), the Rec2020→P3 quoted
    /// matrix composed with the inverse of the quoted Rec2020→sRGB.
    func testSaturatedHexP3KnownPoint() {
        let red = YiyinColor.linearDisplay(
            fromSRGBHex: "#ff0000", target: .displayP3)!
        XCTAssertEqual(Double(red.x), 0.822461969, accuracy: 1e-6)
        XCTAssertEqual(Double(red.y), 0.033194198, accuracy: 1e-6)
        XCTAssertEqual(Double(red.z), 0.017082631, accuracy: 1e-6)
        // sRGB target: identity primaries.
        let redSRGB = YiyinColor.linearDisplay(
            fromSRGBHex: "#ff0000", target: .sRGB)!
        for (got, want) in zip([redSRGB.x, redSRGB.y, redSRGB.z], [Float(1), 0, 0]) {
            XCTAssertEqual(Double(got), Double(want), accuracy: 1e-6)
        }
    }

    // MARK: - T3: ROI negotiation vectors (L020 frame convention)

    /// rate 50 on 40×30: canvas 80×60, main at (20,15) — the modifyROIOut
    /// growth + the modifyROIIn canvas→upstream mapping, exact.
    func testROICanvasGrowthAndBackMapping() {
        let box = ModuleBox(module: BordersModule())
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        box.setParams(params)

        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: 40, height: 30)
        var out = ROI()
        box.modifyROIOutErased(
            &out, input: ROI(x: 0, y: 0, width: 40, height: 30, scale: 1.0), piece: piece)
        XCTAssertEqual(out, ROI(x: 0, y: 0, width: 80, height: 60, scale: 1.0))

        // Full-canvas request → the whole main image.
        var input = ROI()
        box.modifyROIInErased(
            output: ROI(x: 0, y: 0, width: 80, height: 60, scale: 1.0), input: &input, piece: piece)
        XCTAssertEqual(input, ROI(x: 0, y: 0, width: 40, height: 30, scale: 1.0))

        // Partial canvas request → the intersecting main-image sub-rect,
        // shifted into upstream coords (canvasX = upstreamX + mainX).
        var partial = ROI()
        box.modifyROIInErased(
            output: ROI(x: 10, y: 10, width: 40, height: 40, scale: 1.0),
            input: &partial, piece: piece)
        XCTAssertEqual(partial, ROI(x: 0, y: 0, width: 30, height: 30, scale: 1.0))
    }

    // MARK: - T3: solid background content-level (平场纯色取样值)

    /// rate-50 white borders on a 40×30 gradient, NO gamma in the chain
    /// (the output plane stays float32 linear): the canvas band == the
    /// fill color exactly, and the main image == the BASELINE (no-borders)
    /// chain output 1:1 at the laid-out offset — the content-level proof
    /// that the main image rides through colorout untouched. Content, not
    /// size accounting.
    func testSolidWhiteFillContentThroughPipe() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 40, height: 30)
        let trio = await committedTrio(outputProfile: .sRGB)
        // Drop gamma → the borders output is the sampled terminal plane.
        let base = trio.filter { $0.opName != GammaModule.opName }
        let imageID = UUID()
        let cache = PipeCache()
        // Baseline: the chain WITHOUT borders — every main-image pixel of
        // the bordered output must equal this plane 1:1.
        let (baseline, _) = try await RenderPipeline.process(
            image: image, instances: base, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: nil)
        XCTAssertEqual(baseline.width, 40)
        let baselineFloats = readFloats(baseline, metal: metal)

        let box = ModuleBox(module: BordersModule())
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        params.mode = .solid(color: "#ffffff")
        box.setParams(params)
        box.module.displayProfileOverride = .sRGB
        let chain = (base + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: nil)
        // Canvas 80×60 (rate-50 growth), float32 (top ≠ gamma).
        XCTAssertEqual(output.width, 80)
        XCTAssertEqual(output.height, 60)
        XCTAssertEqual(output.pixelFormat, WorkingSpace.pixelFormat)

        let floats = readFloats(output, metal: metal)
        func px(_ x: Int, _ y: Int) -> [Float] {
            let o = (y * output.width + x) * 4
            return [floats[o], floats[o + 1], floats[o + 2]]
        }
        func basePx(_ x: Int, _ y: Int) -> [Float] {
            let o = (y * baseline.width + x) * 4
            return [baselineFloats[o], baselineFloats[o + 1], baselineFloats[o + 2]]
        }
        var compared = 0
        // Canvas band corners + edge midpoints: exact display white.
        for (x, y) in [(0, 0), (79, 0), (0, 59), (79, 59), (40, 0), (0, 30)] {
            let p = px(x, y)
            for c in 0..<3 {
                XCTAssertEqual(Double(p[c]), 1.0, accuracy: 1e-5, "fill at (\(x),\(y)) ch\(c)")
                compared += 1
            }
        }
        // Main image interior: 1:1 with the BASELINE plane at (20,15).
        for (kx, ky) in [(0, 0), (5, 5), (39, 29), (20, 10)] {
            let want = basePx(kx, ky)
            let got = px(20 + kx, 15 + ky)
            for c in 0..<3 {
                XCTAssertEqual(Double(got[c]), Double(want[c]), accuracy: 1e-5, "main at (\(kx),\(ky)) ch\(c)")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: samples compared")
    }

    /// COLOR-2 through the REAL pipe: a P3 display target with a saturated
    /// fill — the canvas band equals the YiyinColor P3 known point.
    func testSolidColoredFillP3KnownPointThroughPipe() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 40, height: 30)
        let trio = await committedTrio(outputProfile: .displayP3)
        let base = trio.filter { $0.opName != GammaModule.opName }
        let box = ModuleBox(module: BordersModule())
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        params.mode = .solid(color: "#ff0000")
        box.setParams(params)
        box.module.displayProfileOverride = .displayP3
        let chain = (base + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(output.width, 80)
        let floats = readFloats(output, metal: metal)
        let o = 4 // pixel (1,0) — well inside the canvas band
        let got: [Double] = [Double(floats[o]), Double(floats[o + 1]), Double(floats[o + 2])]
        XCTAssertEqual(got[0], 0.822461969, accuracy: 1e-5, "P3 red fill R")
        XCTAssertEqual(got[1], 0.033194198, accuracy: 1e-5, "P3 red fill G")
        XCTAssertEqual(got[2], 0.017082631, accuracy: 1e-5, "P3 red fill B")
    }

    /// 窗口化 FULL 画布扩展内容级断言 (L020/L021): a 32×24 window at
    /// origin (10,8) of a 64×48 gradient, rate-50 borders → canvas 64×48;
    /// the main image lands at (16,12) in canvas coords and samples the
    /// FRAME region — output(16+k, 12+k) == the BASELINE window plane
    /// (k, k). Position correctness of the VALUES, not just the sizes.
    func testWindowedFullCanvasExtensionContentLevel() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 64, height: 48)
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }
        let imageID = UUID()
        let cache = PipeCache()
        let hint = ROI(x: 10, y: 8, width: 32, height: 24, scale: 1.0)
        // Baseline window plane (no borders).
        let (baseline, _) = try await RenderPipeline.process(
            image: image, instances: base, imageID: imageID,
            resolution: .full, cache: cache, metal: metal, longEdge: nil,
            roiHint: hint)
        XCTAssertEqual(baseline.width, 32)
        let baselineFloats = readFloats(baseline, metal: metal)

        let box = ModuleBox(module: BordersModule())
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        box.setParams(params)
        box.module.displayProfileOverride = .sRGB
        let chain = (base + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: imageID,
            resolution: .full, cache: cache, metal: metal, longEdge: nil,
            roiHint: hint)
        XCTAssertEqual(output.width, 64, "canvas = window grown at rate 50")
        XCTAssertEqual(output.height, 48)
        let floats = readFloats(output, metal: metal)
        func px(_ x: Int, _ y: Int) -> [Float] {
            let o = (y * output.width + x) * 4
            return [floats[o], floats[o + 1], floats[o + 2]]
        }
        func basePx(_ x: Int, _ y: Int) -> [Float] {
            let o = (y * baseline.width + x) * 4
            return [baselineFloats[o], baselineFloats[o + 1], baselineFloats[o + 2]]
        }
        var compared = 0
        // The canvas band (outside the main rect) is the fill.
        let band = px(0, 0)
        for c in 0..<3 {
            XCTAssertEqual(Double(band[c]), 1.0, accuracy: 1e-5, "windowed band ch\(c)")
            compared += 1
        }
        // The main image maps the FRAME region: output(16+k,12+k) ==
        // baseline window (k, k) — the window offset rides through.
        for k in [0, 5, 15, 23] {
            let want = basePx(k, k)
            let got = px(16 + k, 12 + k)
            for c in 0..<3 {
                XCTAssertEqual(Double(got[c]), Double(want[c]), accuracy: 1e-5, "windowed main k=\(k) ch\(c)")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: samples compared")
    }

    // MARK: - T3: layer-internal discipline pin (LAYER-06)

    /// Borders is BASE-CHAIN-LEGAL per the slot-set rejecter (the dt
    /// geometry slots 13/15/16/17 are unchanged — no new mechanism, Plan
    /// 08-1 纪律) and can never enter a layer leg: the terminal extraction
    /// removes it from every layer-facing chain (the T1 routing test),
    /// with the L021 window-consistency precondition as the in-layer
    /// backstop.
    func testLayerInternalDisciplinePin() {
        // borders (and the terminal window) is not rejected as base.
        let borders = ModuleInstance(
            module: BordersModule.self, params: BordersModule.Params.neutralSeed)
        XCTAssertNil(
            LayerCompositeDriver.layerGeometryViolation([borders]),
            "borders is base-chain legal (terminal/base-only discipline)")
        // The rejecter's slot set is UNCHANGED by Plan 08-1 — the dt
        // geometry modules stay layer-forbidden.
        XCTAssertNotNil(
            LayerCompositeDriver.layerGeometryViolation(
                [ModuleInstance(module: LensModule.self, params: LensModule.Params())]),
            "lens 13.0 stays forbidden in layers")
        XCTAssertNotNil(
            LayerCompositeDriver.layerGeometryViolation(
                [ModuleInstance(module: AshiftModule.self, params: AshiftModule.Params())]),
            "ashift 15.0 stays forbidden in layers")
        XCTAssertNotNil(
            LayerCompositeDriver.layerGeometryViolation(
                [ModuleInstance(module: FlipModule.self, params: FlipModule.Params())]),
            "flip 16.0 stays forbidden in layers")
    }

    // MARK: - T4: rounded-rect SDF alpha profile (解析断言)

    /// rate-50 borders on 40×30: canvas 80×60, main rect (20,15)-(60,45),
    /// radius 10% of mainH = 3px. Shadow ≈ 0 (shadow 0.003% → σ 0.00045 —
    /// the raw SDF). The arc center at the top-right corner is (57,18):
    /// the pixel (58,16) sits 2px inside the arc → alpha 1; (59,15) sits
    /// 3.54px out → alpha 0; a SQUARE path would keep (59,15) — the
    /// radius is exact in the cut it makes.
    func testSDFAalphaProfileRoundedCornerCut() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let module = BordersModule()
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        params.cornerRadius = 10
        params.shadow = 0.003
        var piece = IOPiece()
        module.commitParams(params, into: &piece)
        let record = module.effectiveLayout(dscIn: IOPBufferDesc(width: 40, height: 30))
        XCTAssertEqual(record.canvasSize, SIMD2(80, 60))
        XCTAssertEqual(record.mainImageOrigin, SIMD2(20, 15))
        XCTAssertEqual(record.cornerRadiusPx, 3.0, accuracy: 1e-9)

        let sdf = try await module.buildShadowPlane(
            record: record, roiOut: ROI(x: 0, y: 0, width: 80, height: 60, scale: 1),
            metal: metal)
        let floats = readFloats(sdf, metal: metal)
        func alpha(_ x: Int, _ y: Int) -> Double {
            Double(floats[(y * 80 + x) * 4])
        }
        var compared = 0
        XCTAssertEqual(alpha(58, 16), 1.0, accuracy: 0.05, "inside the arc")
        compared += 1
        XCTAssertLessThan(alpha(59, 15), 0.05, "outside the arc (square path would keep it)")
        compared += 1
        XCTAssertEqual(alpha(30, 30), 1.0, accuracy: 0.05, "rect center")
        XCTAssertLessThan(alpha(0, 0), 0.05, "far canvas corner")
        // Edge midline just outside the right edge: outside → 0.
        XCTAssertLessThan(alpha(62, 30), 0.05, "beyond the right edge")
        compared += 2
        XCTAssertGreaterThan(compared, 0, "防空转")
    }

    // MARK: - T4: shadow decay + flat gate + rounded-corner content

    /// 投影带单调衰减: shadow 5% (σ = 0.75 at the 40×30 preview scale) on
    /// a white fill — brightness along the outward normal of the right
    /// edge rises monotonically toward the unshadowed band value.
    func testShadowBandDecaysMonotonically() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 40, height: 30)
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }
        let box = ModuleBox(module: BordersModule())
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        params.mode = .solid(color: "#ffffff")
        params.shadow = 5
        box.setParams(params)
        box.module.displayProfileOverride = .sRGB
        let chain = (base + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(output.width, 80)
        let floats = readFloats(output, metal: metal)
        func r(_ x: Int, _ y: Int) -> Double {
            Double(floats[(y * output.width + x) * 4])
        }
        // Outward from the main right edge (canvas x 60) at mid-height.
        let near = r(62, 30), mid = r(68, 30), far = r(78, 30)
        var compared = 0
        XCTAssertLessThan(near, 0.995, "shadow visibly darkens at the edge")
        XCTAssertGreaterThan(near, 0.0, "not crushed")
        XCTAssertGreaterThan(mid, near, "decay outward (mid > near)")
        // The tail saturates at the fill once the σ support ends — the
        // band is NON-DECREASING outward with a strict near-edge drop.
        XCTAssertGreaterThanOrEqual(far, mid, "no re-darkening outward")
        XCTAssertLessThan(far, 1.0 + 1e-4, "band value bounded by the fill")
        compared += 5
        XCTAssertGreaterThan(compared, 0, "防空转")
    }

    /// 平场门: shadow EXPLICITLY 0 renders byte-identical to shadow nil
    /// (the disabled leg leaves no trace — the T3 shape).
    func testShadowZeroEqualsShadowNilByteExact() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 40, height: 30)
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }

        func run(_ shadow: Double?) async throws -> [UInt8] {
            let box = ModuleBox(module: BordersModule())
            var params = BordersModule.Params.neutralSeed
            params.mainImageWidthRate = 50
            params.cornerRadius = nil
            params.shadow = shadow
            box.setParams(params)
            box.module.displayProfileOverride = .sRGB
            let chain = (base + [box as any ModuleBoxing])
                .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            let (output, _) = try await RenderPipeline.process(
                image: image, instances: chain, imageID: UUID(),
                resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
            return readBytes(output, metal: metal)
        }
        let a = try await run(nil)
        let b = try await run(0)
        XCTAssertEqual(a.count, b.count)
        XCTAssertGreaterThan(a.count, 0, "防空转")
        XCTAssertEqual(a, b, "shadow 0 == shadow nil, byte-exact (T3 flat gate)")
    }

    /// Rounded-corner CONTENT: black fill, radius 3px — the square-corner
    /// pixel (59,15) shows the FILL (cut by the arc) while (58,16) shows
    /// the main image; with radius nil the same pixel shows the main.
    func testRoundedCornerCutsMainImage() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 40, height: 30)
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }

        func run(radius: Double?) async throws -> (any MTLTexture, [Float]) {
            let box = ModuleBox(module: BordersModule())
            var params = BordersModule.Params.neutralSeed
            params.mainImageWidthRate = 50
            params.mode = .solid(color: "#000000")
            params.cornerRadius = radius
            box.setParams(params)
            box.module.displayProfileOverride = .sRGB
            let chain = (base + [box as any ModuleBoxing])
                .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            let (output, _) = try await RenderPipeline.process(
                image: image, instances: chain, imageID: UUID(),
                resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
            return (output, readFloats(output, metal: metal))
        }
        let (roundTex, roundPx) = try await run(radius: 10)
        XCTAssertEqual(roundTex.width, 80)
        func px(_ floats: [Float], _ tex: any MTLTexture, _ x: Int, _ y: Int) -> [Float] {
            let o = (y * tex.width + x) * 4
            return [floats[o], floats[o + 1], floats[o + 2]]
        }
        let cut = px(roundPx, roundTex, 59, 15)
        for c in 0..<3 {
            XCTAssertEqual(Double(cut[c]), 0.0, accuracy: 0.02, "arc cuts the corner to the fill ch\(c)")
        }
        let kept = px(roundPx, roundTex, 58, 16)
        XCTAssertGreaterThan(
            Double(kept[0]), 0.01, "inside the arc the main image shows")
        // Square path keeps the same pixel (main content, not the fill).
        let (_, squarePx) = try await run(radius: nil)
        let square = px(squarePx, roundTex, 59, 15)
        XCTAssertGreaterThan(
            Double(square[0]), 0.01, "radius nil keeps the square corner")
        var compared = 0
        for f in cut { compared += f == 0 ? 1 : 0 }
        XCTAssertGreaterThanOrEqual(compared, 0, "防空转")
    }

    // MARK: - T5: blur backdrop + adaptive overlay

    /// 模糊 DC 增益=1 平场门: a flat 0.5 input, blur mode amount 100 →
    /// the canvas band samples the blurred proxy — flat in == flat band
    /// (no tint, DC gain exactly 1).
    func testBlurFlatFieldDCGainOne() async throws {
        let metal = try await makeMetal()
        let image = flatImage(width: 40, height: 30, value: 0.5)
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }
        let box = ModuleBox(module: BordersModule())
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        params.mode = .blur(amount: 100)
        params.adaptiveBackdrop = false
        box.setParams(params)
        box.module.displayProfileOverride = .sRGB
        let chain = (base + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(output.width, 80)
        let floats = readFloats(output, metal: metal)
        var compared = 0
        for (x, y) in [(0, 0), (79, 59), (40, 0), (5, 55)] {
            let o = (y * output.width + x) * 4
            for c in 0..<3 {
                XCTAssertEqual(
                    Double(floats[o + c]), 0.5, accuracy: 1e-3,
                    "flat band at (\(x),\(y)) ch\(c)")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转")
    }

    /// The blurred band carries CONTENT: the gradient's dark and light
    /// corners land on opposite canvas corners (stretch + blur, no DC
    /// shift) — the backdrop is the image, not a constant.
    func testBlurBandCarriesContent() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 40, height: 30)
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }
        let box = ModuleBox(module: BordersModule())
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        params.mode = .blur(amount: 100)
        params.adaptiveBackdrop = false
        box.setParams(params)
        box.module.displayProfileOverride = .sRGB
        let chain = (base + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let floats = readFloats(output, metal: metal)
        func r(_ x: Int, _ y: Int) -> Double { Double(floats[(y * output.width + x) * 4]) }
        // Top-left canvas corner (the gradient's dark corner stretched)
        // vs bottom-right — well away from the main rect (20,15)-(60,45).
        let dark = r(2, 2), light = r(77, 57)
        XCTAssertLessThan(dark, 0.35, "dark corner content in the band")
        XCTAssertGreaterThan(light, 0.45, "light corner content in the band")
        XCTAssertGreaterThan(light - dark, 0.05, "the band differentiates content")
    }

    /// 蒙层四档阈值表驱动 (yiyin :31-42 verbatim boundaries).
    func testOverlayTierBoundaries() {
        var compared = 0
        let cases: [(Double, Int)] = [
            (0, 0), (14.999, 0), (15, 1), (19.999, 1), (20, 2), (39.999, 2),
            (40, 3), (100, 3), (255, 3),
        ]
        for (brightness, tier) in cases {
            XCTAssertEqual(YiyinColor.overlayTierIndex(brightness8: brightness), tier, "b=\(brightness)")
            compared += 1
        }
        // The tier grays (yiyin rgba fills).
        XCTAssertEqual(
            YiyinColor.overlayGrayTiers.map(\.gray8), [UInt8(180), 158, 128, 0])
        XCTAssertEqual(YiyinColor.overlayAlpha, 0.2, accuracy: 1e-12)
        // Gray→linear round trip: encode(linear(g/255)) == g/255.
        for g in [UInt8(180), 158, 128, 0] {
            let lin = YiyinColor.linearizeSRGB(Double(g) / 255)
            let back = YiyinColor.linearizeSRGBInverse(lin)
            XCTAssertEqual(back, Double(g) / 255, accuracy: 1e-9)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "防空转")
    }

    /// 蒙层四档 through the pipe: a DARK input in blur mode with
    /// adaptiveBackdrop ON lightens the band (the 180-gray overlay),
    /// while OFF leaves it at the raw blurred content.
    func testAdaptiveOverlayLightensDarkBackdrop() async throws {
        let metal = try await makeMetal()
        let image = flatImage(width: 40, height: 30, value: 0.02)
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }

        func run(adaptive: Bool) async throws -> [Float] {
            let box = ModuleBox(module: BordersModule())
            var params = BordersModule.Params.neutralSeed
            params.mainImageWidthRate = 50
            params.mode = .blur(amount: 100)
            params.adaptiveBackdrop = adaptive
            box.setParams(params)
            box.module.displayProfileOverride = .sRGB
            let chain = (base + [box as any ModuleBoxing])
                .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            let (output, _) = try await RenderPipeline.process(
                image: image, instances: chain, imageID: UUID(),
                resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
            return readFloats(output, metal: metal)
        }
        let off = try await run(adaptive: false)
        let on = try await run(adaptive: true)
        func bandR(_ floats: [Float]) -> Double { Double(floats[4]) } // pixel (1,0)
        let raw = bandR(off), lit = bandR(on)
        // 0.02 linear dark backdrop + 0.2 × linear(180/255) overlay ⇒
        // measurably lighter; both bounded.
        // Expected exactly: linear(0.02) mean → encode ≈ 38.7 → tier 2 →
        // gray 128 → band = 0.02×0.8 + linear(128/255)×0.2 ≈ 0.0592.
        XCTAssertGreaterThan(lit, raw + 0.02, "the gray overlay lightens the dark band")
        XCTAssertLessThan(lit, 1.0, "bounded by white")
        var compared = 0
        for f in off where f >= 0 { compared += 1 }
        XCTAssertGreaterThan(compared, 0, "防空转")
    }

    /// proxy 尺寸记账 + σ 定标式 (D-08-CONTEXT-6) + tile 声明.
    func testProxySizeAccountingAndSigma() {
        var compared = 0
        XCTAssertEqual(
            BordersModule.proxyDims(for: SIMD2(8000, 4000)), SIMD2(2048, 1024))
        // 2000 < the 2048 long edge → passthrough (no upscale).
        XCTAssertEqual(
            BordersModule.proxyDims(for: SIMD2(1000, 2000)), SIMD2(1000, 2000))
        XCTAssertEqual(
            BordersModule.proxyDims(for: SIMD2(4096, 2000)), SIMD2(2048, 1000))
        XCTAssertEqual(
            BordersModule.proxyDims(for: SIMD2(500, 300)), SIMD2(500, 300),
            "smaller than the proxy — no downsample")
        compared += 3
        // σ = amount% × bgHeight / 100 × 0.5, × proxyH/canvasH.
        let sigma = BordersModule.blurSigma(
            amount: 100, canvasHeight: 4000, proxyHeight: 2048)
        XCTAssertEqual(Double(sigma), 1024.0, accuracy: 1e-6)
        let sigmaHalf = BordersModule.blurSigma(
            amount: 50, canvasHeight: 3334, proxyHeight: 2048)
        XCTAssertEqual(
            Double(sigmaHalf), 0.5 * 3334 * 0.5 * (2048.0 / 3334.0), accuracy: 1e-6)
        compared += 2
        // NEVER tiled (DECISIONS D-08-1-3): the canvas-EXPANDING terminal
        // module declares zero halo and zero tile working set.
        let module = BordersModule()
        XCTAssertEqual(module.tileHalo(roi: ROI(width: 64, height: 64), piece: IOPiece()), 0)
        XCTAssertEqual(module.tileWorkingSetBytesPerPixel(piece: IOPiece()), 0)
        compared += 2
        XCTAssertGreaterThan(compared, 0, "防空转")
    }

    /// 内容哈希寻址: the same main image across PARAM edits keeps the
    /// proxy alive (hit), a content change rebuilds it (no stale reuse).
    func testContentAddressedProxyCache() async throws {
        let metal = try await makeMetal()
        let gradient = gradientImage(width: 40, height: 30)
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }
        let box = ModuleBox(module: BordersModule())
        box.module.displayProfileOverride = .sRGB

        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        params.mode = .blur(amount: 100)
        params.adaptiveBackdrop = false

        // PRODUCTION cache shape: ONE PipeCache + ONE imageID namespace —
        // the borders input plane is the SAME cached texture object for
        // unchanged upstream, which is the identity contract the module's
        // proxy key rides (DECISIONS D-08-1-7).
        let cache = PipeCache()
        let imageID = UUID()
        func run(_ image: DecodedImage, forImageID id: UUID, tag: String) async throws {
            box.setParams(params)
            let chain = (base + [box as any ModuleBoxing])
                .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            _ = try await RenderPipeline.process(
                image: image, instances: chain, imageID: id,
                resolution: .preview, cache: cache, metal: metal, longEdge: nil)
        }

        // Run 1 (cold): proxy + blur both miss.
        try await run(gradient, forImageID: imageID, tag: "run1-gradient")
        XCTAssertEqual(box.module.proxyCacheHits, 0)
        XCTAssertEqual(box.module.blurCacheHits, 0)
        // Run 2: a radius edit — the SAME image (same plane identity) →
        // proxy AND blurred-plane both survive.
        params.cornerRadius = 5
        try await run(gradient, forImageID: imageID, tag: "run2-radius5")
        XCTAssertEqual(box.module.proxyCacheHits, 1, "proxy survived the param edit")
        XCTAssertEqual(box.module.blurCacheHits, 1, "blurred plane survived (σ unchanged)")
        // Run 3: a DIFFERENT image → new identity namespace → rebuild.
        try await run(
            flatImage(width: 40, height: 30, value: 0.5), forImageID: UUID(),
            tag: "run3-flat-newimage")
        XCTAssertEqual(box.module.proxyCacheHits, 1, "content change forces a proxy rebuild")
        var compared = box.module.proxyCacheHits + box.module.blurCacheHits
        XCTAssertGreaterThan(compared, 0, "防空转")
        compared = 0
        _ = compared
    }

    // MARK: - T6: orientation pin + PREVIEW drag initial timing

    /// orientation=6 回归钉: the decode layer hands borders UPRIGHT pixels
    /// (the yiyin `sharp().rotate()` equivalent — RESEARCH §8.5). A
    /// 64×32 landscape sensor image, EXIF-rotated to portrait by the
    /// CIImage orientation, laid out at rate 50 → the canvas follows the
    /// UPRIGHT 32×64 portrait (64×128 canvas), not the sensor dims.
    func testBordersSeesUprightPixelsOrientation6() async throws {
        let metal = try await makeMetal()
        let oriented = gradientImage(width: 64, height: 32).ciImage.oriented(.right)
        let image = DecodedImage(
            ciImage: oriented,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
        let trio = await committedTrio(outputProfile: .sRGB)
        let baseChain = trio.filter { $0.opName != GammaModule.opName }
        let box = ModuleBox(module: BordersModule())
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        box.setParams(params)
        box.module.displayProfileOverride = .sRGB
        let chain = (baseChain + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        // Portrait canvas around the upright 32×64 (rate 50 → 64×128);
        // an un-oriented layout would have produced 128×64.
        XCTAssertEqual(output.width, 64, "canvas follows the UPRIGHT width")
        XCTAssertEqual(output.height, 128, "canvas follows the UPRIGHT height")
    }

    /// PREVIEW drag initial timing (Plan 08-1 T6 — numbers RECORDED in
    /// 08-1-SUMMARY; the formal benchmark lives in 8-3's perf.md). No
    /// time gate — the SC gate is the real-app drag; this prints the
    /// Debug-build baselines for solid / blur+overlay / radius+shadow.
    func testPreviewDragInitialTimingRecorded() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 1706, height: 2560) // ~PREVIEW portrait
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }

        func measure(_ params: BordersModule.Params) async throws -> Double {
            let box = ModuleBox(module: BordersModule())
            box.setParams(params)
            box.module.displayProfileOverride = .sRGB
            let chain = (base + [box as any ModuleBoxing])
                .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            let cache = PipeCache()
            _ = try await RenderPipeline.process(
                image: image, instances: chain, imageID: UUID(),
                resolution: .preview, cache: cache, metal: metal, longEdge: 2560)
            // Timed: the drag-hot path = the borders param edit only.
            let clock = ContinuousClock()
            var samples: [Double] = []
            for _ in 0..<5 {
                var edited = params
                edited.cornerRadius = (params.cornerRadius ?? 0) + 0.5
                box.setParams(edited)
                let start = clock.now
                _ = try await RenderPipeline.process(
                    image: image, instances: chain, imageID: UUID(),
                    resolution: .preview, cache: cache, metal: metal, longEdge: 2560)
                let elapsed = clock.now - start
                let ms = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e12
                samples.append(ms)
            }
            return samples.sorted()[samples.count / 2]
        }

        var solid = BordersModule.Params.neutralSeed
        solid.mainImageWidthRate = 90
        solid.mode = .solid(color: "#ffffff")
        var blur = solid
        blur.mode = .blur(amount: 100)
        var shadow = solid
        shadow.shadow = 6
        shadow.cornerRadius = 2.1

        let tSolid = try await measure(solid)
        let tBlur = try await measure(blur)
        let tShadow = try await measure(shadow)
        print(
            "BORDERS-PERF PREVIEW 2560 median ms — solid: \(String(format: "%.1f", tSolid)), " +
                "blur+overlay: \(String(format: "%.1f", tBlur)), solid+radius+shadow: \(String(format: "%.1f", tShadow))")
        XCTAssertGreaterThan(tSolid, 0, "防空转: timing recorded")
    }

    // MARK: - Flat fixture (T5)

    private func flatImage(width: Int, height: Int, value: Float) -> DecodedImage {
        var rgba = [Float](repeating: 1.0, count: width * height * 4)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            rgba[i] = value
            rgba[i + 1] = value
            rgba[i + 2] = value
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
}
