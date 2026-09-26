import CoreGraphics
import CoreImage
import ImageIO
import LightamerCore
import Metal
@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// Plan 11-03 T4/T5 — the headless `ExportRenderer` E2E suite: decode →
/// render (.export, routed queue) → exit (R8 fence + E3 identity) → encode →
/// atomic promote, plus the yiyin export face (dual-size normalized layout
/// equality, the four-state matrix, and a bordered full-chain round-trip).
final class ExportRendererE2ETests: XCTestCase {

    private var tempDirectory: URL!
    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("export-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        metal = try MetalContext()
        registry = ModuleRegistry.makeDefault()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - T4: full-chain round-trip

    /// 合成小图全链：disk sidecar → instances（sidecar 被消费的证据 = 与
    /// pristine 导出逐字节不同）→ render → exit → encode → 落盘 round-trip
    /// 逐断言（尺寸/ICC/DPI/非空像素）。
    func testFullChainRoundTripDecodeRenderExitEncode() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let source = try writePNG(width: 96, height: 64, stem: "SRC_0001")

        // A sidecar with a +1EV exposure edit — the disk truth.
        var records = await seedRecords()
        let exposureRecord = try XCTUnwrap(records.first { $0.opName == ExposureModule.opName })
        var exposureParams = try exposureRecord.params(of: ExposureModule.self)
        exposureParams.exposure = 1.0
        var edited = exposureRecord
        try edited.setParams(exposureParams, as: ExposureModule.self)
        let editedIndex = try XCTUnwrap(records.firstIndex { $0.id == exposureRecord.id })
        records[editedIndex] = edited
        try await writeSidecar(imageURL: source, records: records)

        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48), dpi: 300),
            format: .jpeg(quality: 0.9),
            colorSpace: .sRGB)
        let outcome = try await ExportRenderer.render(
            request: ExportRenderer.Request(
                imageURL: source,
                destinationDirectory: tempDirectory,
                occupiedNames: [source.lastPathComponent],
                variant: variant),
            metal: metal, registry: registry)

        // The outcome + the landed file.
        XCTAssertEqual(outcome.outputWidth, 48, "longEdge 48 of 96×64")
        XCTAssertEqual(outcome.outputHeight, 32)
        XCTAssertEqual(outcome.mainImageSize.x, 48)
        XCTAssertEqual(outcome.mainImageSize.y, 32)
        XCTAssertEqual(outcome.destination.lastPathComponent, "SRC_0001.jpg")
        let values = try decodedPNGValues(outcome.destination)
        XCTAssertEqual(values.width, 48)
        XCTAssertEqual(values.height, 32)
        XCTAssertGreaterThan(values.bytes.count, 0)
        XCTAssertTrue(
            values.profile.contains("sRGB"),
            "the ICC embed rides the target space, got \(values.profile)")
        XCTAssertEqual(values.dpi, 300, "the yiyin DPI metadata landed")

        // The sidecar was CONSUMED: the pristine export (override []) of
        // the same source renders different bytes.
        let pristine = try await ExportRenderer.render(
            request: ExportRenderer.Request(
                imageURL: source,
                destinationDirectory: tempDirectory,
                occupiedNames: [source.lastPathComponent, outcome.destination.lastPathComponent],
                variant: variant,
                instancesOverride: []),
            metal: metal, registry: registry)
        let sidecarBytes = try Data(contentsOf: outcome.destination)
        let pristineBytes = try Data(contentsOf: pristine.destination)
        XCTAssertNotEqual(sidecarBytes, pristineBytes,
                          "the +1EV sidecar edit must reach the exported pixels")
    }

    /// resize 向量（checker E2）：长边 / 短边 / 百分比 / 原尺寸 / 永不放大。
    func testResizeVectorsFourModes() async throws {
        let source = try writePNG(width: 96, height: 64, stem: "RSZ_0001")
        func renderDims(_ variant: ExportVariant) async throws -> (Int, Int) {
            let outcome = try await ExportRenderer.render(
                request: ExportRenderer.Request(
                    imageURL: source,
                    destinationDirectory: tempDirectory,
                    occupiedNames: [source.lastPathComponent],
                    variant: variant),
                metal: metal, registry: registry)
            return (outcome.outputWidth, outcome.outputHeight)
        }
        let srgbPNG: (YiyinExportSettings, Double?) -> ExportVariant = { sizing, percent in
            ExportVariant(sizing: sizing, scalePercent: percent,
                          format: .png(bitDepth: .eight), colorSpace: .sRGB)
        }

        // 长边 48 → 48×32.
        let long = try await renderDims(srgbPNG(.init(mode: .longEdge(px: 48)), nil))
        XCTAssertEqual(long.0, 48); XCTAssertEqual(long.1, 32)
        // 短边 32 → 48×32.
        let short = try await renderDims(srgbPNG(.init(mode: .shortEdge(px: 32)), nil))
        XCTAssertEqual(short.0, 48); XCTAssertEqual(short.1, 32)
        // 百分比 50 → 48×32（variant 层换算进同一 longEdge 数学）.
        let percent = try await renderDims(srgbPNG(.init(mode: .original), 50))
        XCTAssertEqual(percent.0, 48); XCTAssertEqual(percent.1, 32)
        // 原尺寸 → 96×64.
        let original = try await renderDims(srgbPNG(.init(mode: .original), nil))
        XCTAssertEqual(original.0, 96); XCTAssertEqual(original.1, 64)
        // 永不放大：99999 长边钳回源尺寸.
        let neverUpscale = try await renderDims(srgbPNG(.init(mode: .longEdge(px: 99_999)), nil))
        XCTAssertEqual(neverUpscale.0, 96); XCTAssertEqual(neverUpscale.1, 64)
    }

    /// 取消删净：cancel 后 render 抛 .cancelled，目录无半成品。
    func testCancellationLeavesNoFile() async throws {
        let source = try writePNG(width: 32, height: 32, stem: "CXL_0001")
        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 16)),
            format: .png(bitDepth: .eight), colorSpace: .sRGB)
        // Locals (the @Sendable Task op cannot touch self).
        let temp: URL = tempDirectory
        let metal = self.metal!
        let registry = self.registry!
        let task = Task {
            try await ExportRenderer.render(
                request: ExportRenderer.Request(
                    imageURL: source,
                    destinationDirectory: temp,
                    occupiedNames: [source.lastPathComponent],
                    variant: variant),
                metal: metal, registry: registry)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled export must throw")
        } catch let error as AppError {
            guard case .cancelled = error else {
                return XCTFail("expected .cancelled, got \(error)")
            }
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(
            Set(leftovers), Set([source.lastPathComponent]),
            "no half-written export artifact survives a cancellation")
    }

    /// R8：出口腿 fence 必须挂 exportCommandQueue——身份断言（pool seam）。
    func testR8FenceQueueIdentity() async throws {
        let exportPool = CIContextPool(
            device: metal.device, commandQueue: metal.exportCommandQueue)
        let fenceQueue = await exportPool.debugFenceQueue()
        XCTAssertTrue(
            fenceQueue === metal.exportCommandQueue,
            "the export pool's fence rides exportCommandQueue (a fence on the "
                + "editor queue is the R8 false-green shape)")
        XCTAssertFalse(fenceQueue === metal.commandQueue)
    }

    /// E3 消费面：出口腿双态锚——同一 plane，sourceColorSpace == toSpace ==
    /// sRGB 时为恒等（字节保持），sourceColorSpace == working（线性）时
    /// 才做转换（0.5 → sRGB 0.7354…）。导出链消费的是恒等态。
    func testExitLegIdentityDualState() async throws {
        let exportPool = CIContextPool(
            device: metal.device, commandQueue: metal.exportCommandQueue)
        let width = 8, height = 8
        let srgb = ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)

        // The EXPORT-chain consumption: the plane is ALREADY target-encoded
        // (the in-pipe colorout override did primaries+TRC) — identity.
        let identity = try await exportPool.renderToEncodedBitmap(
            TextureBox(texture: try Self.makeConstantTexture(
                r: 0.5, g: 0.5, b: 0.5, width: width, height: height, metal: metal)),
            sourceColorSpace: srgb,
            toSpace: srgb)
        let identitySamples = identity.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(3))
        }
        for sample in identitySamples {
            XCTAssertEqual(Double(sample), 0.5, accuracy: 1e-6,
                           "identity pass keeps the encoded bytes")
        }

        // The dual-state anchor: tagging the SAME plane as the working
        // space CONVERTS (linear 0.5 → sRGB-encoded 0.7354…) — the reverse
        // assertion that catches a wrong consumption choice (a double
        // conversion is a systematic color cast).
        let converted = try await exportPool.renderToEncodedBitmap(
            TextureBox(texture: try Self.makeConstantTexture(
                r: 0.5, g: 0.5, b: 0.5, width: width, height: height, metal: metal)),
            sourceColorSpace: WorkingSpace.colorSpace,
            toSpace: srgb)
        let convertedSamples = converted.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(3))
        }
        for sample in convertedSamples {
            XCTAssertEqual(Double(sample), 0.735_357, accuracy: 0.002,
                           "linear 0.5 encodes to sRGB 187-188/255")
        }
        XCTAssertNotEqual(identitySamples[0], convertedSamples[0])
    }

    // MARK: - T5: yiyin export face (EXP-05)

    /// 双尺寸（2560/4096）同 recipe：归一化布局记录相等——版式分辨率无关
    /// 在 EXPORT 成立（08-3 断言的渲染腿复用，20+ 字段真比较 + 舍入容差）。
    func testYiyinDualSizeNormalizedLayoutEquality() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let configured = try await yiyinRecords()
        let recorder = LayoutRecorder()
        var sizes: [SIMD2<Int>] = []
        var records: [YiyinLayoutRecord?] = []

        for longEdge in [2560, 4096] {
            let outcome = try await ExportRenderer.render(
                request: ExportRenderer.Request(
                    imageURL: tempDirectory.appendingPathComponent("synthetic.ARW"),
                    destinationDirectory: tempDirectory,
                    occupiedNames: [],
                    variant: ExportVariant(
                        sizing: YiyinExportSettings(mode: .longEdge(px: longEdge)),
                        format: .png(bitDepth: .eight), colorSpace: .sRGB,
                        yiyin: true),
                    instancesOverride: configured),
                metal: metal, registry: registry,
                decodeLeg: { _ in Self.largeSyntheticImage(width: 4320, height: 2880) },
                yiyinInjector: ExportYiyinInjector { boxes, records, mainImageSize, capture in
                    _ = ExportRendererE2ETests.inject(
                        boxes: boxes, records: records, mainImageSize: mainImageSize,
                        capture: capture, recorder: recorder)
                })
            sizes.append(outcome.mainImageSize)
            records.append(recorder.snapshot().last?.record ?? nil)
        }

        let small = try XCTUnwrap(records[0], "the 2560 run produced a joint record")
        let large = try XCTUnwrap(records[1], "the 4096 run produced a joint record")
        let smallSize = sizes[0]
        let largeSize = sizes[1]
        XCTAssertEqual(smallSize, SIMD2(2560, 1707), "the entry plane mirrors the target size")

        // Normalize by the main-image size (the layout input) — the
        // resolution-independent face (the 08-3 test's normalization).
        func normalized(_ r: YiyinLayoutRecord, size: SIMD2<Int>) -> (Double, Double, Double, Double, Double, [(Double, Double, Double, Double)]) {
            let sw = Double(size.x), sh = Double(size.y)
            let cw = Double(r.canvasSize.x), ch = Double(r.canvasSize.y)
            return (
                Double(r.canvasSize.x) / sw,
                Double(r.canvasSize.y) / sh,
                Double(r.mainImageOrigin.x) / cw,
                Double(r.mainImageOrigin.y) / ch,
                r.textBottomOffsetPx / ch,
                r.rows.map { row in
                    (Double(row.left) / cw, Double(row.top) / ch,
                     Double(row.width) / cw, Double(row.height) / ch)
                })
        }
        let nSmall = normalized(small, size: smallSize)
        let nLarge = normalized(large, size: largeSize)
        var compared = 0
        let tol = 2.0 / Double(smallSize.y) // ~2 small-scale px of rounding band
        // The row band carries the renderer's ABSOLUTE 30px pad quirk
        // (08-3 on record: it does not scale with the canvas) — row fields
        // get their own pad-aware tolerance, everything else stays at the
        // 2px rounding band.
        let rowTol = 32.0 / Double(small.canvasSize.x)
        XCTAssertLessThan(abs(nSmall.0 - nLarge.0), tol, "canvas width fraction")
        compared += 1
        XCTAssertLessThan(abs(nSmall.1 - nLarge.1), tol, "canvas height fraction")
        compared += 1
        XCTAssertLessThan(abs(nSmall.2 - nLarge.2), tol, "main origin x fraction")
        compared += 1
        XCTAssertLessThan(abs(nSmall.3 - nLarge.3), tol, "main origin y fraction")
        compared += 1
        XCTAssertLessThan(abs(nSmall.4 - nLarge.4), tol, "text offset fraction")
        compared += 1
        // The main-image size itself scales with the target (the entry
        // plane mirror).
        XCTAssertLessThan(
            abs(Double(smallSize.x) / Double(smallSize.y)
                - Double(largeSize.x) / Double(largeSize.y)), 0.01,
            "main aspect constant across sizes")
        compared += 1
        // The canvas/main ratio (the band reserve proportion) matches.
        let ratioS = Double(small.canvasSize.x) / Double(smallSize.x)
        let ratioL = Double(large.canvasSize.x) / Double(largeSize.x)
        XCTAssertLessThan(abs(ratioS - ratioL), tol, "canvas/main width ratio")
        compared += 1
        XCTAssertEqual(nSmall.5.count, nLarge.5.count, "row count")
        compared += 1
        XCTAssertFalse(nSmall.5.isEmpty, "the row band reserved rows")
        for (s, l) in zip(nSmall.5, nLarge.5) {
            XCTAssertLessThan(abs(s.0 - l.0), rowTol, "row left fraction")
            XCTAssertLessThan(abs(s.1 - l.1), rowTol, "row top fraction")
            XCTAssertLessThan(abs(s.2 - l.2), rowTol, "row width fraction")
            XCTAssertLessThan(abs(s.3 - l.3), rowTol, "row height fraction")
            compared += 4
        }
        // The content height (the band's text leg) fraction matches.
        let contentS = Double(small.contentHeight) / Double(smallSize.y)
        let contentL = Double(large.contentHeight) / Double(largeSize.y)
        XCTAssertLessThan(abs(contentS - contentL), rowTol, "content height fraction")
        compared += 1
        // The canvas/main HEIGHT ratio (the vertical band reserve).
        let vratioS = Double(small.canvasSize.y) / Double(smallSize.y)
        let vratioL = Double(large.canvasSize.y) / Double(largeSize.y)
        XCTAssertLessThan(abs(vratioS - vratioL), tol, "canvas/main height ratio")
        compared += 1
        // The text bottom offset is a px value that scales with the
        // canvas (4096/2560 = 1.6).
        XCTAssertEqual(
            Double(large.textBottomOffsetPx) / Double(small.textBottomOffsetPx), 1.6,
            accuracy: 0.02, "textBottomOffsetPx scales with the canvas")
        compared += 1
        // The entry-plane scale between the two runs (4096/2560 = 1.6) on
        // both axes — the layout INPUTS scaled proportionally.
        let scaleX = Double(largeSize.x) / Double(smallSize.x)
        let scaleY = Double(largeSize.y) / Double(smallSize.y)
        XCTAssertEqual(scaleX, 1.6, accuracy: 0.01, "width scale = target ratio")
        XCTAssertEqual(scaleY, 1.6, accuracy: 0.01, "height scale = target ratio")
        compared += 2
        XCTAssertGreaterThan(compared, 20, "防空转: 20+ normalized fields compared")
    }

    /// 4 态矩阵（仅框/仅水印/双开/双关）+ 有印框全链 round-trip：双关 ==
    /// 基线（解码后像素容差 1/255——GPU 渲染非确定，11-04 法证；sanity
    /// 断言钉住真回归可检性）；仅框 band（暗底）+ 双开水印行（亮字）经
    /// 编码→解码存在。
    func testYiyinFourStateMatrixAndBorderedRoundTrip() async throws {
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        // A source LARGER than the target: the never-upscale clamp lands the
        // main image at exactly the target long edge (256), where the 4%
        // watermark font is legible (≈7px rows).
        let source = try writePNG(width: 1024, height: 683, stem: "YIY_0001")
        let recipe = YiyinExportSettings(mode: .longEdge(px: 256), dpi: 72)
        func variant(yiyin: Bool) -> ExportVariant {
            ExportVariant(sizing: recipe, format: .png(bitDepth: .eight),
                          colorSpace: .sRGB, yiyin: yiyin)
        }

        // Each state renders into its OWN landing zone — the renderer's
        // collision face (occupiedNames) is the caller's business, and five
        // same-stem outputs in one directory would overwrite each other.
        func render(_ records: [ModuleInstance], _ yiyin: Bool) async throws -> URL {
            let landing = tempDirectory.appendingPathComponent(
                "landing-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: landing, withIntermediateDirectories: true)
            return try await ExportRenderer.render(
                request: ExportRenderer.Request(
                    imageURL: source, destinationDirectory: landing,
                    occupiedNames: [], variant: variant(yiyin: yiyin),
                    instancesOverride: records),
                metal: metal, registry: registry,
                yiyinInjector: yiyin
                    ? ExportYiyinInjector { boxes, records, mainImageSize, capture in
                        _ = ExportRendererE2ETests.inject(
                            boxes: boxes, records: records, mainImageSize: mainImageSize,
                            capture: capture, recorder: nil)
                    } : nil).destination
        }

        let base = await seedRecords()
        let (bordersOn, watermarkOn) = try yiyinPair()
        func withStates(bordersEnabled: Bool, watermarkEnabled: Bool) -> [ModuleInstance] {
            var records = base
            for (template, enabled) in [(bordersOn, bordersEnabled), (watermarkOn, watermarkEnabled)] {
                var record = template
                record.enabled = enabled
                if let index = records.firstIndex(where: { $0.opName == record.opName }) {
                    records[index] = record
                } else {
                    records.append(record)
                }
            }
            return records
        }

        let baselineURL = try await render(base, false)
        let bothOffURL = try await render(withStates(bordersEnabled: false, watermarkEnabled: false), true)
        let onlyBordersURL = try await render(withStates(bordersEnabled: true, watermarkEnabled: false), true)
        let onlyWatermarkURL = try await render(withStates(bordersEnabled: false, watermarkEnabled: true), true)
        let bothURL = try await render(withStates(bordersEnabled: true, watermarkEnabled: true), true)

        // 双关 == 基线 — PIXEL tolerance（禁用 == 无实例，导出面）。GPU
        // 渲染非确定（1-LSB 级漂移，11-04 SUMMARY 法证：两侧字节都漂、
        // 同代码 fail/pass 交替），PNG 容器字节比对过敏——解码后逐样本
        // 容差 1/255 + 尺寸相等才是「禁用 == 无实例」的真不变量。
        let bothOffValues = try decodedPNGValues(bothOffURL)
        let baselineValues = try decodedPNGValues(baselineURL)
        XCTAssertEqual(bothOffValues.width, baselineValues.width,
                       "both disabled == no-yiyin baseline: width")
        XCTAssertEqual(bothOffValues.height, baselineValues.height,
                       "both disabled == no-yiyin baseline: height")
        let bothOffDiff = maxChannelDiff(bothOffValues.bytes, baselineValues.bytes)
        XCTAssertLessThanOrEqual(
            bothOffDiff, 1,
            "both disabled == no-yiyin baseline within 1/255 (max diff \(bothOffDiff))")
        // Sanity: the relaxation must stay a REAL regression detector — a
        // synthetic 2-level misalignment IS red against this comparator.
        var misaligned = baselineValues.bytes
        misaligned[0] &+= 2
        XCTAssertGreaterThanOrEqual(
            maxChannelDiff(misaligned, baselineValues.bytes), 2,
            "comparator sanity: a 2/255 offset is detected")

        // 仅框：画布扩展（> 256 长边）+ band 暗底存在 + 无白字。
        let bordersValues = try decodedPNGValues(onlyBordersURL)
        XCTAssertGreaterThan(max(bordersValues.width, bordersValues.height), 256,
                             "borders extend the canvas beyond the target size")
        let bordersAnalysis = analyze(values: bordersValues)
        XCTAssertGreaterThan(bordersAnalysis.darkFraction, 0.04, "the border band exists (dark pixels)")
        XCTAssertLessThan(bordersAnalysis.brightCount, 50, "borders-only has no white text")

        // 仅水印：主图 == targetSize（无框），渲染内容与基线不同。
        let watermarkValues = try decodedPNGValues(onlyWatermarkURL)
        XCTAssertEqual(max(watermarkValues.width, watermarkValues.height), 256)
        XCTAssertNotEqual(try Data(contentsOf: onlyWatermarkURL), try Data(contentsOf: baselineURL),
                          "the watermark row changed the pixels")

        // 双开：band 上的水印行 = 亮像素显著存在（round-trip 渲染→出口→
        // 编码→解码）。
        let bothValues = try decodedPNGValues(bothURL)
        let bothAnalysis = analyze(values: bothValues)
        XCTAssertEqual(bothValues.width, bordersValues.width, "the canvas matches borders-only")
        XCTAssertGreaterThan(bothAnalysis.brightCount, 30,
                             "the white watermark rows survive the full chain")
        XCTAssertGreaterThan(bothAnalysis.darkFraction, 0.04, "the band is there under the row")
    }

    // MARK: - harness: records

    /// The full editing seed (trio + editing defaults — the coordinator's
    /// live-set face, incl. the neutral borders/watermark carriers).
    private func seedRecords() async -> [ModuleInstance] {
        let trio = await registry.makeDefaultInstances()
        return (trio + LightamerIOPRegistry.editingDefaultInstances())
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    /// The configured yiyin pair (borders solid band + one white literal
    /// row) as replacement records for the seed.
    private func yiyinPair() throws -> (borders: ModuleInstance, watermark: ModuleInstance) {
        var bordersParams = BordersModule.Params.neutralSeed
        bordersParams.mode = .solid(color: "#101010")
        bordersParams.mainImageWidthRate = 85
        bordersParams.cornerRadius = 2.0
        var watermarkParams = WatermarkModule.Params.neutralSeed
        watermarkParams.templates = [
            YiyinTemplate(
                key: "row1", name: "n1", pattern: "LIGHTAMER EXPORT", use: true,
                font: YiyinFont(sizePercent: 4, color: "#ffffff")),
            YiyinTemplate(
                key: "row2", name: "n2", pattern: "PHASE 11 PIPELINE", use: true,
                font: YiyinFont(sizePercent: 3, color: "#ffffff")),
        ]
        watermarkParams.fields = []
        watermarkParams.anchor = .center
        return (
            ModuleInstance(module: BordersModule.self, params: bordersParams),
            ModuleInstance(module: WatermarkModule.self, params: watermarkParams))
    }

    /// The seed with the yiyin pair replacing the neutral carriers (for the
    /// dual-size test).
    private func yiyinRecords() async throws -> [ModuleInstance] {
        var records = await seedRecords().filter {
            $0.opName != BordersModule.opName && $0.opName != WatermarkModule.opName
        }
        let pair = try yiyinPair()
        records.append(pair.borders)
        records.append(pair.watermark)
        return records.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    /// The injection body (the YiyinE2ETests.wireYiyinContext shape): sets
    /// captureExif / jointContext and rides the joint record into the
    /// borders override; the recorder (when present) captures the record
    /// for the dual-size equality.
    private static func inject(
        boxes: [any ModuleBoxing], records: [ModuleInstance],
        mainImageSize: SIMD2<Int>, capture: CaptureMetadata,
        recorder: LayoutRecorder?
    ) -> YiyinLayoutRecord? {
        guard let watermarkBox = boxes.first(where: { $0.opName == WatermarkModule.opName })
            as? ModuleBox<WatermarkModule>
        else { return nil }
        let bordersParams = try? records
            .first { $0.opName == BordersModule.opName }?
            .params(of: BordersModule.self)
        let watermark = watermarkBox.module
        watermark.captureExif = capture
        watermark.jointContext = WatermarkModule.JointContext(
            mainImageSize: mainImageSize, bordersParams: bordersParams)
        let record = watermark.makeJointLayoutRecord(
            mainImageSize: mainImageSize, bordersParams: bordersParams)
        recorder?.record(size: mainImageSize, layout: record)
        guard let bordersBox = boxes.first(where: { $0.opName == BordersModule.opName })
            as? ModuleBox<BordersModule>
        else { return record }
        bordersBox.module.jointLayoutOverride = record
        return record
    }

    /// Thread-safe (size, record) capture for the dual-size comparison.
    final class LayoutRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var pairs: [(size: SIMD2<Int>, record: YiyinLayoutRecord?)] = []
        func record(size: SIMD2<Int>, layout: YiyinLayoutRecord?) {
            lock.lock(); defer { lock.unlock() }
            pairs.append((size, layout))
        }
        func snapshot() -> [(size: SIMD2<Int>, record: YiyinLayoutRecord?)] {
            lock.lock(); defer { lock.unlock() }
            return pairs
        }
    }

    // MARK: - harness: files + decode

    /// A synthetic gradient PNG, capped at 0.6 linear headroom so only the
    /// white watermark text can count as "bright" in the band analysis.
    private func writePNG(width: Int, height: Int, stem: String) throws -> URL {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i] = UInt8(Double(x) / Double(max(width - 1, 1)) * 153)
                rgba[i + 1] = UInt8(Double(y) / Double(max(height - 1, 1)) * 153)
                rgba[i + 2] = 64
            }
        }
        let plane = ExportQuantizedPlane(
            data: Data(rgba), width: width, height: height, layout: .rgba8)
        let url = tempDirectory.appendingPathComponent("\(stem).png")
        _ = try PNGEncoder().encode(ExportEncodeRequest(
            plane: plane, spec: .png(bitDepth: .eight),
            colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            destination: url))
        return url
    }

    /// Persist a sidecar beside the source (the flushNow semantics).
    private func writeSidecar(imageURL: URL, records: [ModuleInstance]) async throws {
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: 0,
            instances: records,
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 0),
            appVersion: "0.3.0-e2e")
        let store = SidecarStore(destination: LightamerSidecar.sidecarURL(for: imageURL))
        await store.scheduleWrite(document)
        try await store.flushNow()
    }

    /// Decode an encoded image: pixel bytes (RGBA8), size, ICC name, DPI.
    private func decodedPNGValues(_ url: URL) throws -> (
        width: Int, height: Int, bytes: [UInt8], profile: String, dpi: Int
    ) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var bytes = [UInt8]()
        if let data = context.data {
            let count = cg.width * cg.height * 4
            bytes = Array(
                UnsafeBufferPointer(
                    start: data.assumingMemoryBound(to: UInt8.self), count: count))
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let profile = (props?[kCGImagePropertyProfileName] as? String) ?? ""
        let dpi = (props?[kCGImagePropertyDPIHeight] as? Int) ?? 0
        return (cg.width, cg.height, bytes, profile, dpi)
    }

    private struct Analysis {
        var darkFraction: Double
        var brightCount: Int
    }

    /// Max absolute per-sample difference of two equally sized RGBA8 planes
    /// (the pixel-tolerance comparator for the four-state matrix).
    private func maxChannelDiff(_ a: [UInt8], _ b: [UInt8]) -> Int {
        precondition(a.count == b.count, "pixel planes must be equally sized")
        var maxDiff = 0
        for index in 0..<a.count {
            maxDiff = max(maxDiff, abs(Int(a[index]) - Int(b[index])))
        }
        return maxDiff
    }

    /// Band/row presence: the fraction of near-black pixels (the #101010
    /// band) and the count of near-white pixels (the white text row).
    private func analyze(
        values: (width: Int, height: Int, bytes: [UInt8], profile: String, dpi: Int)
    ) -> Analysis {
        var dark = 0, bright = 0
        let count = values.width * values.height
        for index in 0..<count {
            let r = Double(values.bytes[index * 4]) / 255.0
            if r < 0.1 { dark += 1 }
            if r > 0.8 { bright += 1 }
        }
        return Analysis(darkFraction: Double(dark) / Double(max(count, 1)), brightCount: bright)
    }

    // MARK: - harness: synthetic decodes

    private nonisolated static func largeSyntheticImage(width: Int, height: Int) -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i + 0] = Float(x) / Float(max(width - 1, 1)) * 0.6
                rgba[i + 1] = Float(y) / Float(max(height - 1, 1)) * 0.6
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

    /// A float32 linear-Rec2020 constant texture (the exit-leg dual-state
    /// fixture).
    private static func makeConstantTexture(
        r: Float, g: Float, b: Float, width: Int, height: Int, metal: MetalContext
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: width, height: height,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(width * height * WorkingSpace.bytesPerPixel)
        }
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = r
            rgba[index + 1] = g
            rgba[index + 2] = b
            rgba[index + 3] = 1.0
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: rgba, bytesPerRow: width * WorkingSpace.bytesPerPixel)
        return texture
    }
}
