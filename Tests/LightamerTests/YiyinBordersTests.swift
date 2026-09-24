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
}
