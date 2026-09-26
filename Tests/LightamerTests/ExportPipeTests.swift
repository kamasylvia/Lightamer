import CoreImage
import LightamerCore
import Metal
@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// Plan 11-03 — the EXPORT pipe-leg suite.
///
/// T1 queue infrastructure (this file, `testQueueInfrastructure*`):
/// `exportCommandQueue` is a NEW property (D-15's letter — never a
/// reassignment) and the TaskLocal route (`MetalContext.$routesToExportQueue`)
/// flips the single acquisition point (`makeCommandBuffer`) to it, with the
/// editor path byte-identical when unwrapped.
///
/// T2 (export chain assembly), T3 (.export activation) and the renderer E2E
/// live in the later sections / `ExportRendererE2ETests`.
final class ExportPipeTests: XCTestCase {

    private var metal: MetalContext!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
    }

    // MARK: - T1: queue infrastructure (SC#2 基建)

    /// D-15's letter: the export queue is a NEW property — a distinct
    /// instance, never a reassignment of the editor queue.
    func testQueueInfrastructureExportQueueIsNewProperty() throws {
        XCTAssertFalse(
            metal.commandQueue === metal.exportCommandQueue,
            "exportCommandQueue must be a distinct queue instance (D-15: NEW property)")
        // Both queues are live: each can mint a buffer.
        XCTAssertNotNil(metal.commandQueue.makeCommandBuffer())
        XCTAssertNotNil(metal.exportCommandQueue.makeCommandBuffer())
    }

    /// The TaskLocal route flips the single acquisition point: wrapped, the
    /// acquired buffer's queue IS the export queue (R8's precondition — the
    /// exit leg's fence only orders export writes if it hangs on the queue
    /// the pipe wrote through).
    func testQueueInfrastructureTaskLocalRoutesToExportQueue() throws {
        // Unwrapped: the editor queue (today's behavior, byte-identical).
        let editorBuffer = try metal.makeRoutedCommandBuffer()
        XCTAssertTrue(editorBuffer.commandQueue === metal.commandQueue)

        // Wrapped: the export queue.
        let exportBuffer = try MetalContext.$routesToExportQueue.withValue(true) {
            try metal.makeRoutedCommandBuffer()
        }
        XCTAssertTrue(
            exportBuffer.commandQueue === metal.exportCommandQueue,
            "a routed acquisition must come from exportCommandQueue")

        // After the scope exits the route is off again (no leakage).
        let afterBuffer = try metal.makeRoutedCommandBuffer()
        XCTAssertTrue(afterBuffer.commandQueue === metal.commandQueue)
    }

    /// The route propagates down the STRUCTURED task tree — the 11-04 export
    /// job runner wraps its whole render task in `withValue(true)`, and iop
    /// dispatches inside child tasks must land on the export queue without
    /// touching a single iop call site. (`Task {}` inherits task-locals;
    /// `Task.detached` deliberately does not — the render tree is structured.)
    func testQueueInfrastructureRoutePropagatesIntoChildTasks() async throws {
        let metal = self.metal!
        let routed: Bool = await MetalContext.$routesToExportQueue.withValue(true) {
            await Task(priority: .utility) {
                MetalContext.routesToExportQueue
            }.value
        }
        XCTAssertTrue(routed, "TaskLocal route must cross structured child tasks")

        // And a child-task acquisition inside the wrap lands on the export
        // queue (the exact shape the export render uses).
        let isExport = try await MetalContext.$routesToExportQueue.withValue(true) {
            try await Task(priority: .utility) {
                let buffer = try metal.makeRoutedCommandBuffer()
                return buffer.commandQueue === metal.exportCommandQueue
            }.value
        }
        XCTAssertTrue(isExport)

        // The editor's unwrapped tree stays on the editor queue.
        let editorIsEditor = try await Task(priority: .userInitiated) {
            let buffer = try metal.makeRoutedCommandBuffer()
            return buffer.commandQueue === metal.commandQueue
        }.value
        XCTAssertTrue(editorIsEditor, "the unwrapped path must stay on the editor queue")
    }

    // MARK: - T2: export chain assembly (OQ-11-2 — gamma stripped + colorout target override)

    private let registry = ModuleRegistry.makeDefault()

    /// gamma 必剔（每条 gamma record，含禁用）+ colorout record 目标改写 +
    /// 其余 record 一字不动 + override 空间的 display-TRC/linear 双态。
    func testChainBuilderStripsGammaAndRewritesColorout() async throws {
        var records = await registry.makeDefaultInstances() // colorin, colorout(.display), gamma
        // A disabled gamma record must ALSO vanish.
        var secondGamma = ModuleInstance(module: GammaModule.self, params: GammaModule.Params())
        secondGamma.enabled = false
        records.append(secondGamma)
        records.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let coloroutBefore = records.first { $0.opName == ColorOutModule.opName }!

        let built = try ExportChainBuilder.exportChain(
            from: records, target: .proPhoto, linearVariant: false)

        XCTAssertFalse(
            built.instances.contains { $0.opName == GammaModule.opName },
            "gamma 必剔 — the export chain never carries the display handoff")
        XCTAssertEqual(
            built.instances.filter { $0.opName != ColorOutModule.opName }.map(\.opName),
            records.filter { $0.opName != GammaModule.opName && $0.opName != ColorOutModule.opName }.map(\.opName),
            "non-colorout records pass through verbatim")
        let coloroutAfter = try XCTUnwrap(built.instances.first { $0.opName == ColorOutModule.opName })
        XCTAssertEqual(coloroutAfter.id, coloroutBefore.id, "identity is preserved")
        let params = try coloroutAfter.params(of: ColorOutModule.self)
        XCTAssertEqual(params.outputProfile, .proPhoto, "the record target is rewritten")
        XCTAssertEqual(params.intent, .relativeColorimetric, "the intent face stays verbatim")

        // The override socket face: display TRC by default; the linear
        // variant face is a typed ERROR for the gamuts the system ships no
        // linear ICC for (D-11-02-2) — a 32f pairing bug surfaces, never
        // silently bends.
        XCTAssertEqual(
            built.exportTargetOverride.name as String?, "kCGColorSpaceROMMRGB",
            "ProPhoto display-TRC override = ROMM RGB")
        XCTAssertThrowsError(
            try ExportChainBuilder.exportChain(
                from: records, target: .proPhoto, linearVariant: true),
            "no linear ROMM exists — the 32f pairing is a typed error")
    }

    /// 五色域覆写已知点：in-pipe colorout 一次完成 primaries+TRC（sRGB 编码
    /// 值直接落在管平面）+ 五色域中性恒中性 + 32f 线性变体不弯值。
    func testColoroutOverrideKnownPointsAndNeutrality() async throws {
        let imageID = UUID()

        // (a) primaries + TRC known point: linear Rec2020 (0.4, 0.3, 0.2)
        // → the documented Rec2020→sRGB matrix (ColorOutModule derivation
        // header) → sRGB TRC, compared against test-side math.
        let colorImage = constantImage(r: 0.4, g: 0.3, b: 0.2, width: 32, height: 24)
        let srgbBuilt = try ExportChainBuilder.exportChain(
            from: await registry.makeDefaultInstances(), target: .sRGB, linearVariant: false)
        let srgbBoxes = try await materialize(srgbBuilt, registry: registry, override: srgbBuilt.exportTargetOverride)
        let srgbPixels = try await runAndReadFloats(srgbBoxes, image: colorImage, imageID: imageID)
        let expected = Self.rec2020ToSRGBEncoded(0.4, 0.3, 0.2)
        let tolerance = 2.5 / 255.0 // ColorSync ICC matrices vs the doc matrix
        for channel in 0..<3 {
            let got = Double(srgbPixels[channel])
            XCTAssertLessThan(
                abs(got - expected[channel]), tolerance,
                "sRGB encoded channel \(channel): got \(got), want \(expected[channel])")
        }
        // The encoded value pins the E3 consumption face: 0.5 linear would
        // be 187-188 in 8-bit; the plane carries ENCODED floats (≥ 0.4),
        // not working-space linear.
        let encoded8 = Int((Double(srgbPixels[0]) * 255.0).rounded())
        XCTAssertGreaterThanOrEqual(encoded8, 180, "the plane is target-ENCODED (no second conversion)")

        // (b) neutrality across all five gamuts: linear gray stays gray.
        let gray = constantImage(r: 0.5, g: 0.5, b: 0.5, width: 32, height: 24)
        for target in ExportColorSpace.allCases {
            let built = try ExportChainBuilder.exportChain(
                from: await registry.makeDefaultInstances(), target: target, linearVariant: false)
            let boxes = try await materialize(built, registry: registry, override: built.exportTargetOverride)
            let pixels = try await runAndReadFloats(boxes, image: gray, imageID: imageID)
            let r = Double(pixels[0]), g = Double(pixels[1]), b = Double(pixels[2])
            XCTAssertLessThan(abs(r - g), 1.0 / 255.0, "\(target): gray neutrality r≈g")
            XCTAssertLessThan(abs(g - b), 1.0 / 255.0, "\(target): gray neutrality g≈b")
            for value in [r, g, b] {
                XCTAssertGreaterThanOrEqual(value, 0.0, "\(target): in-domain floor")
                XCTAssertLessThanOrEqual(value, 1.0, "\(target): in-domain ceiling")
            }
            XCTAssertGreaterThan(r, 0.5, "\(target): gray is TRC-encoded above its linear value")
        }

        // (c) the 32f LINEAR variant never bends values: Rec2020 target +
        // linear variant = the working space itself — identity pass.
        let linearBuilt = try ExportChainBuilder.exportChain(
            from: await registry.makeDefaultInstances(), target: .rec2020, linearVariant: true)
        XCTAssertEqual(
            linearBuilt.exportTargetOverride.name as String?, "kCGColorSpaceLinearITUR_2020",
            "the 32f override is the linear Rec2020 variant")
        let linearBoxes = try await materialize(
            linearBuilt, registry: registry, override: linearBuilt.exportTargetOverride)
        let linearPixels = try await runAndReadFloats(linearBoxes, image: colorImage, imageID: imageID)
        for channel in 0..<3 {
            let input = [Float(0.4), Float(0.3), Float(0.2)][channel]
            XCTAssertLessThan(
                abs(linearPixels[channel] - input), 1e-5,
                "linear variant keeps channel \(channel) unbent")
        }
    }

    /// 管尾格式策略：export 链（gamma 已剔）尾平面保持 float32；编辑链
    /// （gamma 在尾）尾平面仍 .bgra8Unorm——策略不被导出面触发，编辑面零回归。
    func testExportChainTailStaysFloat32WhileEditingTailStaysBgra8() async throws {
        let image = constantImage(r: 0.4, g: 0.3, b: 0.2, width: 32, height: 24)
        let imageID = UUID()

        // The export-built chain: float32 tail (the tail policy never fires
        // — no gamma at the top enabled position).
        let built = try ExportChainBuilder.exportChain(
            from: await registry.makeDefaultInstances(), target: .sRGB, linearVariant: false)
        let exportBoxes = try await materialize(built, registry: registry, override: built.exportTargetOverride)
        let (exportTexture, _) = try await RenderPipeline.process(
            image: image, instances: exportBoxes, imageID: imageID,
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(exportTexture.pixelFormat, WorkingSpace.pixelFormat)

        // The editing chain (records verbatim — gamma in place): the tail
        // is still the display handoff format.
        let editingRecords = await registry.makeDefaultInstances()
        var editingBoxes: [any ModuleBoxing] = []
        for record in editingRecords {
            guard let box = await registry.makeBox(opName: record.opName, instanceID: record.id) else { continue }
            try box.apply(record)
            editingBoxes.append(box)
        }
        let (editingTexture, _) = try await RenderPipeline.process(
            image: image, instances: editingBoxes, imageID: imageID,
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(editingTexture.pixelFormat, GammaModule.outputPixelFormat)
    }

    // MARK: - T3: .export activation (entry scale + total no-caching)

    /// .export run 走既有 process/processComposite 路径：entry longEdge =
    /// targetSize 长边（永不放大钳制），四尺寸向量 + 管缓存 totalBytes 恒 0
    /// （输入面也不存——红线 TOTAL）+ FULL 输入面仍入缓存（零回归对照）。
    func testExportRunSizeVectorsAndTotalNoCaching() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let image = constantImage(r: 0.4, g: 0.3, b: 0.2, width: 96, height: 64)
        let imageID = UUID()
        let records = await registry.makeDefaultInstances()
        // The production export chain face: builder-assembled (gamma
        // stripped) so the tail stays float32.
        let built = try ExportChainBuilder.exportChain(
            from: records, target: .sRGB, linearVariant: false)
        var boxes: [any ModuleBoxing] = []
        for record in built.instances {
            guard let box = await registry.makeBox(opName: record.opName, instanceID: record.id) else { continue }
            try box.apply(record)
            boxes.append(box)
        }

        // The shared cache across EVERY export run proves the isolation.
        let sharedCache = PipeCache()
        func exportSize(_ longEdge: Int?) async throws -> (Int, Int) {
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: boxes, imageID: imageID,
                resolution: .export, cache: sharedCache, metal: metal, longEdge: longEdge)
            return (texture.width, texture.height)
        }

        // 长边 48 → 48×32（aspect preserved）。
        let longEdge = try await exportSize(48)
        XCTAssertEqual(longEdge.0, 48)
        XCTAssertEqual(longEdge.1, 32)
        // 短边模式的 targetSize 数学（复验 11-01 golden 的接线）：
        // shortEdge 32 of 96×64 → (48, 32) → entry long edge 48。
        let short = YiyinExportSettings(mode: .shortEdge(px: 32), dpi: 300)
            .targetSize(canvasWidth: 96, canvasHeight: 64)
        XCTAssertEqual(max(short.width, short.height), 48, "short-edge sizing folds to the same entry long edge")
        // 原尺寸 → entry long edge = 96 → scale 1.0 → 96×64。
        let original = try await exportSize(96)
        XCTAssertEqual(original.0, 96)
        XCTAssertEqual(original.1, 64)
        // 永不放大：9999 的长边钳回源尺寸。
        let neverUpscale = try await exportSize(9999)
        XCTAssertEqual(neverUpscale.0, 96)
        XCTAssertEqual(neverUpscale.1, 64)
        // nil longEdge（原尺寸 mode 的 renderer 面）→ 96×64。
        let nilEdge = try await exportSize(nil)
        XCTAssertEqual(nilEdge.0, 96)
        XCTAssertEqual(nilEdge.1, 64)

        // 管缓存 totalBytes 恒 0 — 输入面（line 0）与所有中间面都不存。
        let bytes = await sharedCache.totalBytes
        XCTAssertEqual(bytes, 0, "an export run leaves the pipe cache EMPTY (input plane included)")
        let stats = await sharedCache.stats
        XCTAssertEqual(stats.misses, 0, "the export walk never even probes the cache")

        // FULL 对照（同一 cache）：输入面 + final 仍入缓存（lock #4 未动）。
        let (_, _) = try await RenderPipeline.process(
            image: image, instances: boxes, imageID: imageID,
            resolution: .full, cache: sharedCache, metal: metal, longEdge: nil)
        let fullBytes = await sharedCache.totalBytes
        XCTAssertGreaterThan(fullBytes, 0, "FULL keeps its input+final cache lines (zero regression)")

        // Content sanity: the 48×32 plane carries the scaled gradient
        // corners (scale-at-entry semantics unchanged).
        let (texture, _) = try await RenderPipeline.process(
            image: gradientImage(width: 96, height: 64), instances: boxes, imageID: UUID(),
            resolution: .export, cache: PipeCache(), metal: metal, longEdge: 48)
        drain(metal)
        var floats = [Float](repeating: 0, count: 48 * 32 * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: 48 * 16,
                from: MTLRegionMake2D(0, 0, 48, 32), mipmapLevel: 0)
        }
        XCTAssertLessThan(Double(floats[0]), 0.05, "left edge of the x-gradient")
        XCTAssertGreaterThan(Double(floats[(47) * 4]), 0.9, "right edge of the x-gradient")
    }

    /// 双 stub 之二：processComposite at .export（runSub 激活）——一个调整
    /// 图层（exposure +1EV）经图层合成在导出分辨率生效，输出 = targetSize
    /// 尺寸的 float32 平面，缓存仍恒 0。
    func testExportCompositeActivatesRunSubStub() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let image = gradientImage(width: 96, height: 64)
        let imageID = UUID()
        let records = await registry.makeDefaultInstances()
        let built = try ExportChainBuilder.exportChain(
            from: records, target: .sRGB, linearVariant: false)
        var boxes: [any ModuleBoxing] = []
        for record in built.instances {
            guard let box = await registry.makeBox(opName: record.opName, instanceID: record.id) else { continue }
            try box.apply(record)
            boxes.append(box)
        }
        var exposureParams = ExposureModule.Params()
        exposureParams.exposure = 1.0 // +1EV
        let layer = AdjustmentLayer(
            name: "lift", chain: [ModuleInstance(module: ExposureModule.self, params: exposureParams)])
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layer)

        let cache = PipeCache()
        let (texture, _) = try await RenderPipeline.processComposite(
            image: image, instances: boxes, layerStack: stack, registry: registry,
            imageID: imageID, resolution: .export, cache: cache, metal: metal,
            longEdge: 48, roiHint: nil, policy: .export)
        XCTAssertEqual(texture.width, 48)
        XCTAssertEqual(texture.height, 32)
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat)
        let bytes = await cache.totalBytes
        XCTAssertEqual(bytes, 0, "composite export also leaves the pipe cache empty")
    }

    // MARK: - T2 harness

    private func materialize(
        _ built: ExportChainBuilder.Built,
        registry: ModuleRegistry,
        override target: CGColorSpace
    ) async throws -> [any ModuleBoxing] {
        var boxes: [any ModuleBoxing] = []
        for record in built.instances {
            guard let box = await registry.makeBox(opName: record.opName, instanceID: record.id) else {
                continue
            }
            try box.apply(record)
            if let colorout = box as? ModuleBox<ColorOutModule> {
                // The socket set BEFORE the apply would be folded at
                // setParams; set it after apply and re-commit so the hash
                // carries it (the renderer's shape).
                colorout.module.exportTargetOverride = target
                let params = try record.params(of: ColorOutModule.self)
                colorout.setParams(params)
            }
            boxes.append(box)
        }
        return boxes.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    private func runAndReadFloats(
        _ boxes: [any ModuleBoxing], image: DecodedImage, imageID: UUID
    ) async throws -> [Float] {
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: boxes, imageID: imageID,
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        drain(metal)
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        // First pixel, first three channels.
        return Array(floats.prefix(3))
    }

    /// L014 fence before readback (sync body — `waitUntilCompleted` is
    /// unavailable from async contexts, the YiyinE2ETests drain shape).
    private nonisolated func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// A constant-color float32 linear-Rec2020 synthetic (the
    /// `gradientImage` CGImage construction, constant).
    private func constantImage(r: Float, g: Float, b: Float, width: Int, height: Int) -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = r
            rgba[index + 1] = g
            rgba[index + 2] = b
            rgba[index + 3] = 1.0
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
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }


    /// An x/y gradient float32 linear-Rec2020 synthetic (the YiyinE2ETests
    /// fixture shape — corner-value assertions read it directly).
    private func gradientImage(width: Int, height: Int) -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i + 0] = Float(x) / Float(max(width - 1, 1))
                rgba[i + 1] = Float(y) / Float(max(height - 1, 1))
                rgba[i + 2] = 0.25
                rgba[i + 3] = 1.0
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
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    /// Test-side reference math: the documented Rec2020→sRGB LINEAR matrix
    /// (ColorOutModule derivation header) + the exact sRGB segmented TRC.
    private static func rec2020ToSRGBEncoded(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
        let linear = (
            1.661272640 * r - 0.588487320 * g - 0.072785321 * b,
            -0.126189204 * r + 1.134531230 * g - 0.008342025 * b,
            -0.017014775 * r - 0.100723728 * g + 1.117738502 * b)
        func encode(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return [encode(linear.0), encode(linear.1), encode(linear.2)]
    }
}
