@testable import LightamerCore
import CoreImage
@testable import LightamerIOP
import Metal
import XCTest

/// Plan 08-2 — the yiyin watermark (水印) suite.
///
/// T3 sections: the 77.0 registration + neutral seed (byte-exact through
/// the real pipe — 空模板/全字段关直通逐字节, 轨 B 中性插链零增量), the
/// template ENGINE table (matchFields / interleave / forceUse / Make-logo
/// dispatch / skip rules), and the JOINT LAYOUT rows leg (canvas reserve,
/// horizontal + portrait, the watermark-only face, the nine-grid anchor).
///
/// T4 adds the CoreText renderer sections (formulas + golden + cache) in
/// the same file; T5 the Logo/FontStore sections.
final class YiyinWatermarkTests: XCTestCase {

    /// Injectable temp root for the store faces (T5).
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yiyin-watermark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // ── Fixtures (YiyinBordersTests twins) ──

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

    // ── T3: registration + seed ──

    func testWatermarkRegisteredAtV50Slot() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: WatermarkModule.opName)
        let watermarkBox = try XCTUnwrap(box as? ModuleBox<WatermarkModule>)
        XCTAssertEqual(watermarkBox.opName, "watermark")
        XCTAssertEqual(watermarkBox.iopOrder, 77.0, "verbatim V50Order slot — zero rows inserted")
        XCTAssertEqual(WatermarkModule.defaultColorspace, .RGB)
        XCTAssertEqual(
            WatermarkModule.iopOrder, V50Order.order(for: "watermark"),
            "the table row and the module agree")
        let id = UUID()
        let restored = await registry.makeBox(opName: WatermarkModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
    }

    func testWatermarkJoinsEditingSeedAsNeutral() throws {
        let seed = LightamerIOPRegistry.editingDefaultInstances()
        let watermark = seed.filter { $0.opName == WatermarkModule.opName }
        XCTAssertEqual(watermark.count, 1, "exactly one watermark instance in the seed")
        XCTAssertEqual(watermark.first?.enabled, true, "seed is enabled-neutral")
        let decoded = try JSONDecoder().decode(
            WatermarkModule.Params.self, from: watermark.first!.paramsData)
        XCTAssertEqual(decoded, WatermarkModule.Params.neutralSeed, "seed params = identity face")
        // The seed carries the system catalog but EVERY row OFF
        // (D-08-CONTEXT-4 — 新图不自动挂水印).
        XCTAssertTrue(decoded.templates.contains { $0.key == "make-model" })
        XCTAssertTrue(decoded.templates.allSatisfy { !$0.use })
    }

    func testCommitHashesRawParamsViaParamsCoding() {
        let box = ModuleBox(module: WatermarkModule())
        var params = WatermarkModule.Params.neutralSeed
        params.templates[0].use = true
        params.logoOpacity = 0.5
        box.setParams(params)
        XCTAssertEqual(
            box.paramsHash, StableHash.hash(ParamsCoding.encode(params)),
            "L013: the committed hash digests the ParamsCoding bytes")
    }

    // ── T3: seed identity through the real pipe (byte-exact) ──

    func testSeedIdentityIsByteExactThroughPipe() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 64, height: 48)
        let trio = await committedTrio()
        let withWatermark = (trio + [neutralWatermarkBox() as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (plain, plainStats) = try await RenderPipeline.process(
            image: image, instances: trio, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let (watermarked, watermarkStats) = try await RenderPipeline.process(
            image: image, instances: withWatermark, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)

        XCTAssertEqual(watermarked.width, plain.width)
        XCTAssertEqual(watermarked.height, plain.height)
        let a = readBytes(plain, metal: metal)
        let b = readBytes(watermarked, metal: metal)
        XCTAssertEqual(a.count, b.count)
        XCTAssertGreaterThan(a.count, 0, "防空转: bytes compared")
        XCTAssertEqual(a, b, "neutral watermark insertion == no-instance baseline, byte-exact")
        XCTAssertEqual(
            plainStats.planesRendered + 1, watermarkStats.planesRendered,
            "exactly one extra plane (the watermark blit) — no hidden walk growth")
    }

    func testAllFieldConfigsHiddenIsByteIdentity() async throws {
        // 全字段关直通: an ACTIVE template whose every field is hidden →
        // the row skips → byte-identical (the resolve-drop face through
        // the pipe, not just the engine).
        let metal = try await makeMetal()
        let image = gradientImage(width: 48, height: 64)
        let trio = await committedTrio()

        var params = WatermarkModule.Params.neutralSeed
        params.templates[0].use = true // {Make} {Model} ON
        for index in params.fields.indices {
            params.fields[index].show = false
        }
        let hiddenFieldsBox = ModuleBox(module: WatermarkModule())
        hiddenFieldsBox.setParams(params)

        let instances = (trio + [hiddenFieldsBox as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (plain, _) = try await RenderPipeline.process(
            image: image, instances: trio, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let (watermarked, _) = try await RenderPipeline.process(
            image: image, instances: instances, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(readBytes(plain, metal: metal), readBytes(watermarked, metal: metal))
    }

    func testDisabledInstanceEqualsNoInstance() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 32, height: 32)
        let trio = await committedTrio()
        var params = WatermarkModule.Params.neutralSeed
        params.templates[0].use = true
        let disabledBox = ModuleBox(module: WatermarkModule())
        disabledBox.setParams(params)
        disabledBox.enabled = false
        let instances = (trio + [disabledBox as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let (plain, _) = try await RenderPipeline.process(
            image: image, instances: trio, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let (processed, _) = try await RenderPipeline.process(
            image: image, instances: instances, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        XCTAssertEqual(readBytes(plain, metal: metal), readBytes(processed, metal: metal))
    }

    private func neutralWatermarkBox() -> ModuleBox<WatermarkModule> {
        let box = ModuleBox(module: WatermarkModule())
        box.setParams(WatermarkModule.Params.neutralSeed)
        return box
    }

    // ── T3: the template engine (yiyin genTextImg string face) ──

    private func engineInputs(
        fields: [YiyinExifField: String] = [:],
        configs: [String: YiyinField] = defaultConfigs,
        backdropIsBlur: Bool = false,
        bgHeight: Double = 2000,
        logoExists: YiyinTemplateEngine.LogoExists? = nil
    ) -> YiyinTemplateEngine.Inputs {
        YiyinTemplateEngine.Inputs(
            fields: fields, fieldConfigs: configs,
            defaultFont: YiyinFont(), backdropIsBlur: backdropIsBlur,
            bgHeight: bgHeight, logoExists: logoExists)
    }

    static let defaultConfigs: [String: YiyinField] = Dictionary(
        uniqueKeysWithValues: YiyinExifField.allCases.map { ($0.rawValue, YiyinField(key: $0.rawValue)) }
    )

    func testMatchFieldsOrderDedupAndCase() {
        let matches = YiyinTemplateEngine.matchFields("{Make} {Model} — {Make}")
        XCTAssertEqual(matches.map(\.field), ["Make", "Model"], "first-occurrence order + dedup")
        XCTAssertEqual(matches[0].temp, "{Make}")
        // The gi face: lowercase letters match too.
        XCTAssertEqual(
            YiyinTemplateEngine.matchFields("{focalLength}").map(\.field), ["focalLength"])
        // No fields → empty.
        XCTAssertTrue(YiyinTemplateEngine.matchFields("plain text").isEmpty)
        XCTAssertTrue(YiyinTemplateEngine.matchFields("").isEmpty)
        // Braces without a name or with separators don't match ([A-Z0-9]+).
        XCTAssertTrue(YiyinTemplateEngine.matchFields("{} {A-B}").isEmpty)
    }

    func testResolveLiteralOnlyRowAppliesRowCase() {
        var template = YiyinTemplate(key: "k", name: "n", pattern: "  Custom  Text  ", use: true)
        template.font.caseType = .upcase
        let row = YiyinTemplateEngine.resolve(template: template, inputs: engineInputs())
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.items, [.literal("CUSTOM  TEXT")], "trim + the row caseType")
        XCTAssertEqual(row?.fontPx ?? 0, 2000 * 0.022, accuracy: 1e-9,
            "row font px = bgHeight × size% (JS float)")
    }

    func testResolveEmptyPatternSkipsRow() {
        var template = YiyinTemplate(key: "k", name: "n", pattern: "   ", use: true)
        template.font.caseType = .default
        XCTAssertNil(YiyinTemplateEngine.resolve(template: template, inputs: engineInputs()))
    }

    func testResolveInterleaveAndSlotTrim() {
        // The yiyin fill: Make = "Nikon" (no logo asset → TEXT degrade),
        // Model = the normalization quirk " ℤ 6 II" → the slot TRIM makes
        // "ℤ 6 II".
        var fields = engineInputs(fields: [
            .make: "Nikon", .model: " ℤ 6 II",
        ])
        fields.logoExists = nil
        let template = YiyinTemplate(
            key: "k", name: "n", pattern: "{Make} {Model}", use: true)
        let row = YiyinTemplateEngine.resolve(template: template, inputs: fields)
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.items.count, 3, "slot, literal(' '), slot")
        guard case .slot(.text("Nikon"), _, _) = row?.items[0] else {
            return XCTFail("items[0] should be the Make text slot (no logo asset)")
        }
        guard case .literal(" ") = row?.items[1] else {
            return XCTFail("items[1] should be the interleaved space literal")
        }
        guard case .slot(.text("ℤ 6 II"), _, _) = row?.items[2] else {
            return XCTFail("items[2] should be the TRIMMED Model slot")
        }
    }

    func testResolveRowColorFallsBackToBackdrop() {
        // getTextTempList: color = template color || (blur ? #fff : #000).
        let blurRow = YiyinTemplateEngine.resolve(
            template: YiyinTemplate(key: "k", name: "n", pattern: "x", use: true),
            inputs: engineInputs(backdropIsBlur: true))
        XCTAssertEqual(blurRow?.color, "#ffffff")
        let solidRow = YiyinTemplateEngine.resolve(
            template: YiyinTemplate(key: "k", name: "n", pattern: "x", use: true),
            inputs: engineInputs(backdropIsBlur: false))
        XCTAssertEqual(solidRow?.color, "#000000")
        var colored = YiyinTemplate(key: "k", name: "n", pattern: "x", use: true)
        colored.font.color = "#336699"
        let custom = YiyinTemplateEngine.resolve(
            template: colored, inputs: engineInputs(backdropIsBlur: false))
        XCTAssertEqual(custom?.color, "#336699", "the template color wins")
    }

    func testForceUseOverrideAndEmptyValueFallback() {
        // use + forceUse: the custom value overrides a NON-empty EXIF.
        var configs = Self.defaultConfigs
        configs["Model"] = YiyinField(
            key: "Model", show: true, use: true, forceUse: true,
            customValue: "My Camera")
        let row = YiyinTemplateEngine.resolve(
            template: YiyinTemplate(key: "k", name: "n", pattern: "{Model}", use: true),
            inputs: engineInputs(fields: [.model: "ℤ 8"], configs: configs))
        guard case .slot(.text("My Camera"), _, _) = row?.items[0] else {
            return XCTFail("forceUse replaces the EXIF value")
        }

        // use + !forceUse: the custom value fills only an EMPTY EXIF.
        var configs2 = Self.defaultConfigs
        configs2["PersonalSign"] = YiyinField(
            key: "PersonalSign", show: true, use: true, forceUse: false,
            customValue: "by Sylvia")
        let filled = YiyinTemplateEngine.resolve(
            template: YiyinTemplate(key: "k", name: "n", pattern: "{PersonalSign}", use: true),
            inputs: engineInputs(fields: [:], configs: configs2))
        guard case .slot(.text("by Sylvia"), _, _) = filled?.items[0] else {
            return XCTFail("the custom value fills the empty EXIF slot")
        }
        // …and a NON-empty EXIF value wins over the non-forced custom.
        let exifWins = YiyinTemplateEngine.resolve(
            template: YiyinTemplate(key: "k", name: "n", pattern: "{PersonalSign}", use: true),
            inputs: engineInputs(fields: [.personalSign: "EXIF"], configs: configs2))
        guard case .slot(.text("EXIF"), _, _) = exifWins?.items[0] else {
            return XCTFail("without forceUse the EXIF value wins")
        }
    }

    func testMakeLogoDispatchMatrix() {
        let template = YiyinTemplate(key: "k", name: "n", pattern: "{Make}", use: true)

        // auto × blur → white; auto × solid → black; borders absent counts
        // as solid (backdropIsBlur false).
        var blur = engineInputs(fields: [.make: "Sony"], backdropIsBlur: true)
        blur.logoExists = { _, _ in true }
        guard case .slot(.logo("sony", .white), _, _) =
            YiyinTemplateEngine.resolve(template: template, inputs: blur)?.items[0]
        else { return XCTFail("auto on a blurred backdrop → the white logo") }

        var solid = engineInputs(fields: [.make: "Sony"], backdropIsBlur: false)
        solid.logoExists = { _, _ in true }
        guard case .slot(.logo("sony", .black), _, _) =
            YiyinTemplateEngine.resolve(template: template, inputs: solid)?.items[0]
        else { return XCTFail("auto on a solid backdrop → the black logo") }

        // Manual pins win over the backdrop.
        var pinned = YiyinTemplate(key: "k", name: "n", pattern: "{Make}", use: true)
        pinned.use = true
        var configs = Self.defaultConfigs
        configs["Make"]?.logoVariant = .white
        var blurPinned = engineInputs(
            fields: [.make: "Sony"], configs: configs, backdropIsBlur: true)
        blurPinned.logoExists = { _, variant in variant == .white }
        let pinnedRow = YiyinTemplateEngine.resolve(template: pinned, inputs: blurPinned)
        guard case .slot(.logo("sony", .white), _, _) = pinnedRow?.items[0] else {
            return XCTFail("the manual white pin stays white")
        }

        // No asset → the TEXT degrade (the normalized make string).
        var noAsset = engineInputs(fields: [.make: "Nikon"])
        noAsset.logoExists = nil
        guard case .slot(.text("Nikon"), _, _) =
            YiyinTemplateEngine.resolve(template: template, inputs: noAsset)?.items[0]
        else { return XCTFail("no logo asset → the Make text slot") }
    }

    func testHiddenFieldPlaceholderRemovedAndRowSkips() {
        // A hidden field: the placeholder is REMOVED (no marker, no slot).
        var configs = Self.defaultConfigs
        configs["Model"]?.show = false
        let row = YiyinTemplateEngine.resolve(
            template: YiyinTemplate(key: "k", name: "n", pattern: "{Make} {Model}", use: true),
            inputs: engineInputs(fields: [.make: "Nikon", .model: "z8"], configs: configs))
        // The hidden slot vanishes from the text; the surviving face is
        // the Make slot (the empty literal segments drop — yiyin's
        // filter(Boolean) face).
        XCTAssertEqual(
            row?.items,
            [.slot(.text("Nikon"), font: YiyinFontOverride(), sizePx: 0)])

        // EVERYTHING hidden → the row skips (the single-empty-segment rule).
        var allHidden = configs
        for (key, _) in allHidden { allHidden[key]?.show = false }
        let empty = YiyinTemplateEngine.resolve(
            template: YiyinTemplate(key: "k", name: "n", pattern: "{Make} {Model}", use: true),
            inputs: engineInputs(fields: [:], configs: allHidden))
        XCTAssertNil(empty, "all placeholders hidden → the row skips")
    }

    func testFieldedRowWithAllSlotsDroppedSkips() {
        // Slots exist (fields shown) but every VALUE is empty → the row
        // skips (the `_arr.length > 1 && no valid slots` rule).
        let row = YiyinTemplateEngine.resolve(
            template: YiyinTemplate(
                key: "k", name: "n",
                pattern: "{FocalLength}mm f/{FNumber}", use: true),
            inputs: engineInputs(fields: [:]))
        XCTAssertNil(row)
    }

    func testFieldFontOverrideScalesRounded() {
        // Field fonts ROUND to px (temp-field :26); the row font stays a
        // JS float — both recorded on the resolved items.
        var configs = Self.defaultConfigs
        configs["Make"]?.font = YiyinFontOverride(
            use: true, sizePercent: 1.234)
        let row = YiyinTemplateEngine.resolve(
            template: YiyinTemplate(key: "k", name: "n", pattern: "{Make}", use: true),
            inputs: engineInputs(fields: [.make: "Nikon"], configs: configs, bgHeight: 1000))
        guard case .slot(.text("Nikon"), let font, let sizePx) = row?.items[0] else {
            return XCTFail("the Make slot")
        }
        XCTAssertTrue(font.use)
        XCTAssertEqual(sizePx, (1000 * 0.01234).rounded(), "the override size, rounded to px")
        XCTAssertEqual(row?.fontPx ?? 0, 22.0, accuracy: 1e-9, "the ROW font stays unrounded")
    }

    // ── T3: the joint layout rows leg ──

    /// The borders params the rows cases share (rate 90 grows the canvas).
    private var rowsBorders: BordersModule.Params {
        var p = BordersModule.Params.neutralSeed
        p.mainImageWidthRate = 90
        return p
    }

    func testRowsLegCanvasReserveLandscape() {
        // 600×400 + one 300×40 row, rate 90 (hand-derived, yiyin formulas):
        // bg1 = 667×445 → offset 445×0.027 = 12.015 → contentH =
        // ceil(40+400+12.015) = 453 → bg2 = 680×453.
        let record = YiyinLayout.layout(
            imageSize: SIMD2(600, 400), borders: rowsBorders,
            rows: [YiyinLayout.TextRowMetrics(width: 300, height: 40)])
        XCTAssertEqual(record.canvasSize, SIMD2(680, 453), "the canvas RESERVES the text block")
        XCTAssertEqual(record.contentHeight, 453)
        XCTAssertEqual(record.mainImageOrigin, SIMD2(40, 0))
        XCTAssertEqual(record.rows.count, 1)
        XCTAssertEqual(record.rows[0].left, 190, "round((680−300)/2)")
        XCTAssertEqual(record.rows[0].top, 401, "round(453 − (40+12.015)) — the last-row slot")
        XCTAssertEqual(record.rows[0].width, 300)
        XCTAssertEqual(record.rows[0].height, 40, "the PLACED height is the UNinflated one")
    }

    func testRowsLegCanvasReservePortrait() {
        // 400×600 + one 300×40 row (hand-derived): bg1 = 445×668 →
        // offset 18.036 → contentH 659 → bg2 = 445×668 (the rate branch
        // regrows).
        let record = YiyinLayout.layout(
            imageSize: SIMD2(400, 600), borders: rowsBorders,
            rows: [YiyinLayout.TextRowMetrics(width: 300, height: 40)])
        XCTAssertEqual(record.canvasSize, SIMD2(445, 668))
        XCTAssertEqual(record.rows[0].top, 610, "round(668 − 58.036)")
        XCTAssertEqual(record.rows[0].left, 73, "round(72.5) half-up — JS Math.round")
    }

    func testStackingOrderLastRowNearestBottom() {
        // Two rows: list order [A, B] → B lands bottom-most (the yiyin
        // reversed loop), A sits exactly one row above.
        let record = YiyinLayout.layout(
            imageSize: SIMD2(600, 400), borders: rowsBorders,
            rows: [
                YiyinLayout.TextRowMetrics(width: 200, height: 30),
                YiyinLayout.TextRowMetrics(width: 300, height: 40),
            ])
        XCTAssertEqual(record.rows.count, 2)
        // The offset basis is the PASS-1 canvas (445), not the final one:
        // 445 × 0.027 = 12.015; contentH = ceil(70 + 400 + 12.015) = 483;
        // bg2 = 725×483. placed[0] = the list-LAST row (B).
        XCTAssertEqual(record.canvasSize, SIMD2(725, 483))
        XCTAssertEqual(record.rows[0].top, 431, "B (the list-last) at round(483 − 52.015)")
        // A's top = round(B.top − A.h) = round(431 − 30) = 401.
        XCTAssertEqual(record.rows[1].top, 401)
    }

    func testFirstPassCanvasMatchesNoRowsCanvas() {
        // bgSize(contentHeight: h) — pass 1 == pass 2 exactly when the
        // rows are empty AND margin/shadow are zero (the same function
        // then). Cross-checks the new pure function against the shipped
        // layout.
        for size in [SIMD2(600, 400), SIMD2(400, 600), SIMD2(1024, 768)] {
            let record = YiyinLayout.layout(
                imageSize: size, borders: .neutralSeed, rows: [])
            let pass1 = YiyinLayout.firstPassCanvasSize(
                imageSize: size, borders: .neutralSeed)
            XCTAssertEqual(record.canvasSize, pass1, "size \(size)")
        }
        // With a margin they diverge (contentH > h) — the pass-1 canvas is
        // the SMALLER one (row-height independent).
        var margin = BordersModule.Params.neutralSeed
        margin.miniTopBottomMargin = 5
        let pass1 = YiyinLayout.firstPassCanvasSize(
            imageSize: SIMD2(600, 400), borders: margin)
        let record = YiyinLayout.layout(
            imageSize: SIMD2(600, 400), borders: margin, rows: [])
        XCTAssertLessThan(pass1.y, record.canvasSize.y)
    }

    func testWatermarkOnlyPlacementStacksOnImage() {
        // The watermark-only face: canvas == image; the last row's visible
        // bottom margin = the offset fraction of the IMAGE height.
        let module = WatermarkModule()
        module.jointContext = nil
        let (rows, canvas) = module.placedRows(
            mainImageSize: SIMD2(600, 400),
            metrics: [YiyinLayout.TextRowMetrics(width: 300, height: 40)])
        XCTAssertEqual(canvas, SIMD2(600, 400), "画布即原图")
        XCTAssertEqual(rows.count, 1)
        let offset = Double(400) * 0.027 // 10.8
        XCTAssertEqual(rows[0].top, Int((400.0 - (40.0 + offset)).rounded()))
        XCTAssertEqual(rows[0].left, 150)
        // The visible bottom edge (top + height) sits offset above 400.
        XCTAssertEqual(rows[0].top + rows[0].height, 400 - Int(offset.rounded()))
    }

    func testNeutralBordersParamsAlsoUseWatermarkOnlyFace() {
        // A borders instance present but NEUTRAL: the yiyin formula's
        // ceil-quirk must never size a canvas that is in fact identity
        // (D-08-1-2) — the watermark stacks on the image directly.
        let module = WatermarkModule()
        module.jointContext = WatermarkModule.JointContext(
            mainImageSize: SIMD2(58, 7), bordersParams: .neutralSeed)
        let (rows, canvas) = module.placedRows(
            mainImageSize: SIMD2(58, 7),
            metrics: [YiyinLayout.TextRowMetrics(width: 20, height: 2)])
        XCTAssertEqual(canvas, SIMD2(58, 7), "neutral borders ⇒ no formula growth")
        XCTAssertEqual(rows.count, 1)
    }

    func testJointBordersActiveGrowsCanvas() {
        let module = WatermarkModule()
        module.jointContext = WatermarkModule.JointContext(
            mainImageSize: SIMD2(600, 400), bordersParams: rowsBorders)
        let (rows, canvas) = module.placedRows(
            mainImageSize: SIMD2(600, 400),
            metrics: [YiyinLayout.TextRowMetrics(width: 300, height: 40)])
        XCTAssertEqual(canvas, SIMD2(680, 453), "the active borders canvas with the rows leg")
        XCTAssertEqual(rows[0].top, 401)
    }

    func testNineGridAnchorTranslatesBlock() {
        // .bottomCenter is the identity; other anchors translate the BLOCK
        // with the slot margin from each anchored edge.
        let rows = [
            YiyinLayoutRecord.PlacedRow(left: 190, top: 401, width: 300, height: 40),
            YiyinLayoutRecord.PlacedRow(left: 210, top: 361, width: 260, height: 30),
        ]
        let canvas = SIMD2(680, 453)
        let margin: Double = 12.015

        let identity = YiyinLayout.applyAnchor(.bottomCenter, rows: rows, canvas: canvas, marginPx: margin)
        XCTAssertEqual(identity, rows, "yiyin parity — the default anchor never moves")

        let topLeft = YiyinLayout.applyAnchor(.topLeft, rows: rows, canvas: canvas, marginPx: margin)
        XCTAssertEqual(topLeft.map(\.left).min(), 12, "the block's left edge at the margin")
        XCTAssertEqual(topLeft.map(\.top).min(), 12, "the block's top edge at the margin")
        // Relative geometry preserved.
        XCTAssertEqual(topLeft[1].top - topLeft[0].top, rows[1].top - rows[0].top)

        let topCenter = YiyinLayout.applyAnchor(.topCenter, rows: rows, canvas: canvas, marginPx: margin)
        XCTAssertEqual(topCenter.map(\.left).min(), 190, "centered horizontally (the yiyin face)")
        XCTAssertEqual(topCenter.map(\.top).min(), 12)

        let bottomRight = YiyinLayout.applyAnchor(.bottomRight, rows: rows, canvas: canvas, marginPx: margin)
        XCTAssertEqual(
            bottomRight.map { $0.left + $0.width }.max()!, 680 - 12,
            "the block's right edge at (canvas − margin)")
        XCTAssertEqual(
            bottomRight.map { $0.top + $0.height }.max()!, 453 - 12,
            "the block's bottom edge at (canvas − margin)")
    }

    // ── T4: the CoreText renderer (formula-same-shape + cache + composite) ──

    /// A fixed template row for the renderer faces (no logo — deterministic).
    private func literalRow(_ text: String, caseType: YiyinCaseType = .default)
        -> YiyinTemplateEngine.ResolvedRow
    {
        YiyinTemplateEngine.ResolvedRow(
            items: [.literal(text)],
            font: YiyinFont(bold: true, sizePercent: 3, caseType: caseType),
            fontPx: 60, color: "#ffffff", verticalAlign: .baseline)
    }

    private let renderer = YiyinTextRenderer()

    func testRowLayoutFormulaSameShape() {
        // The createTextImg faces against an INDEPENDENT CoreText measure
        // in the test (the formula wiring, not the rasterizer).
        let row = literalRow("NIKON ℤ 9")
        let (_, layout) = renderer.layoutRow(
            row: row, bgHeight: 2000, lineSpacingPercent: 0.4, logoProvider: nil)

        // Independent measure at the row font.
        let font = YiyinTextRenderer.ctFont(name: "", size: 60, bold: true, italic: false)
        let m = Self.measureHelper("NIKON ℤ 9", font: font)
        // baseline = ceil(ascent of the whole-text measure).
        XCTAssertEqual(layout.baseline, m.ascent.rounded(.up))
        // height = ceil(max(asc+desc+2×margin, maxFontPx)).
        let margin = 2000 * (0.4 / 100)
        let expectedH = Int(max(m.ascent + m.descent + margin * 2, 60).rounded(.up))
        XCTAssertEqual(layout.height, expectedH)
        // width = 30 + slot + 30.
        XCTAssertEqual(layout.width, 30 + Int(m.width.rounded(.up)) + 30)
        // The slot's baseline-face y = round2(baseline + (H − baseline)/2).
        XCTAssertEqual(
            layout.slots[0].y,
            ((layout.baseline + (Double(layout.height) - layout.baseline) / 2) * 100)
                .rounded() / 100)
        XCTAssertEqual(layout.slots[0].w, Int(m.width.rounded(.up)))
        var compared = 0
        XCTAssertGreaterThan(layout.width, 60)
        XCTAssertGreaterThanOrEqual(layout.height, 60)
        compared += 1
        XCTAssertGreaterThan(compared, 0, "防空转")
    }

    func testRowHeightDrivenByMaxSlotFont() {
        // getMaxFontParam: a USED slot override with a LARGER px drives the
        // canvas height (bold ORs too).
        var row = literalRow("x")
        row.items = [
            .slot(.text("big"), font: YiyinFontOverride(use: true, bold: true, sizePercent: 5), sizePx: 100),
        ]
        let (_, layout) = renderer.layoutRow(
            row: row, bgHeight: 1000, lineSpacingPercent: 0, logoProvider: nil)
        // maxFontPx = 100 → height ≥ 100 even though the row font is 22px.
        XCTAssertGreaterThanOrEqual(layout.height, 100)
        // UNUSED overrides don't count (the yiyin `if (font.use)` gate).
        var row2 = literalRow("x")
        row2.items = [
            .slot(.text("big"), font: YiyinFontOverride(use: false, sizePercent: 5), sizePx: 100),
        ]
        let (_, layout2) = renderer.layoutRow(
            row: row2, bgHeight: 1000, lineSpacingPercent: 0, logoProvider: nil)
        XCTAssertLessThan(layout2.height, 100)
    }

    private static func measureHelper(_ s: String, font: CTFont)
        -> (ascent: Double, descent: Double, width: Double)
    {
        let attributed = NSMutableAttributedString(string: s)
        attributed.addAttribute(
            kCTFontAttributeName as NSAttributedString.Key, value: font,
            range: NSRange(location: 0, length: attributed.length))
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (Double(ascent), Double(descent), Double(width))
    }

    func testRowBitmapInk() {
        let row = literalRow("LIGHTAMER")
        let bitmap = renderer.renderRow(
            row: row, bgHeight: 2000, lineSpacingPercent: 0.4,
            logoOpacity: 1, logoProvider: nil)
        // Ink exists, stays inside the box, and is white (premultiplied
        // white: r≈g≈b≈a).
        var minX = bitmap.width, minY = bitmap.height, maxX = 0, maxY = 0
        var inkPixels = 0
        var compared = 0
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let o = (y * bitmap.width + x) * 4
                let a = bitmap.pixels[o + 3]
                if a > 32 {
                    inkPixels += 1
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                    let (r, g, b) = (bitmap.pixels[o], bitmap.pixels[o + 1], bitmap.pixels[o + 2])
                    // GRAY ink face: r == g == b (no subpixel color
                    // fringing). ENCODED-DOMAIN premultiply face (probe-
                    // proven 08-3 T0): stored rgb = a × encode(color),
                    // a = linear coverage — white ink has encode(1) = 1,
                    // so r == a exactly (the −8 is byte rounding); the
                    // composite kernel recovers encode(color) via r/a and
                    // applies the EOTF ONCE (08-3 T0 fix).
                    XCTAssertTrue(
                        abs(Int(r) - Int(g)) <= 8 && abs(Int(g) - Int(b)) <= 8,
                        "white text must stay gray (r=g=b) at (\(x),\(y))")
                    XCTAssertGreaterThanOrEqual(Int(r), Int(a) - 8)
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThan(inkPixels, 50, "防空转: ink pixels")
        XCTAssertGreaterThanOrEqual(minX, 30, "the 30px leading pad")
        XCTAssertLessThanOrEqual(minX, 40, "glyph side bearing lands within the pad")
        XCTAssertLessThanOrEqual(maxX, bitmap.width - 30 + 2, "the trailing pad bounds")
        XCTAssertLessThanOrEqual(maxY, bitmap.height)
    }

    func testRenderCacheMissHitAccounting() {
        let r = YiyinTextRenderer()
        let a = literalRow("row-a")
        let b = literalRow("row-b")
        _ = r.renderRow(row: a, bgHeight: 1000, lineSpacingPercent: 0.4, logoOpacity: 1, logoProvider: nil)
        XCTAssertEqual(r.cacheMisses, 1)
        XCTAssertEqual(r.cacheHits, 0)
        // The same determinants → HIT (a borders-blur param edit's face).
        _ = r.renderRow(row: a, bgHeight: 1000, lineSpacingPercent: 0.4, logoOpacity: 1, logoProvider: nil)
        XCTAssertEqual(r.cacheMisses, 1)
        XCTAssertEqual(r.cacheHits, 1)
        // A changed determinant (the row's slots) → MISS.
        _ = r.renderRow(row: b, bgHeight: 1000, lineSpacingPercent: 0.4, logoOpacity: 1, logoProvider: nil)
        XCTAssertEqual(r.cacheMisses, 2)
        // A changed bgHeight (resolution switch) → MISS.
        _ = r.renderRow(row: a, bgHeight: 4000, lineSpacingPercent: 0.4, logoOpacity: 1, logoProvider: nil)
        XCTAssertEqual(r.cacheMisses, 3)
        // clearCache wipes.
        r.clearCache()
        _ = r.renderRow(row: a, bgHeight: 1000, lineSpacingPercent: 0.4, logoOpacity: 1, logoProvider: nil)
        XCTAssertEqual(r.cacheMisses, 4)
        XCTAssertEqual(r.cacheHits, 1)
    }

    func testRenderCacheBudgetEviction() {
        let r = YiyinTextRenderer()
        for i in 0..<60 {
            _ = r.renderRow(
                row: literalRow("evict-\(i)"), bgHeight: 200, lineSpacingPercent: 0,
                logoOpacity: 1, logoProvider: nil)
        }
        XCTAssertLessThanOrEqual(r.cacheKeysCount, YiyinTextRenderer.cacheBudget)
    }

    func testLogoOpacityBakesIntoAlpha() {
        // A 2:1 red logo fixture; opacity halves the premultiplied alpha.
        let fixture = Self.logoFixture(width: 8, height: 4)
        let provider: YiyinLogoProvider = { _ in fixture }
        var row = literalRow("x")
        row.items = [.slot(.logo(make: "test", variant: .white), font: YiyinFontOverride(), sizePx: 0)]
        let full = renderer.renderRow(
            row: row, bgHeight: 1000, lineSpacingPercent: 0.4,
            logoOpacity: 1, logoProvider: provider)
        let half = renderer.renderRow(
            row: row, bgHeight: 1000, lineSpacingPercent: 0.4,
            logoOpacity: 0.5, logoProvider: provider)
        func maxAlpha(_ bmp: YiyinRowBitmap) -> Int {
            var m = 0
            for i in stride(from: 3, to: bmp.pixels.count, by: 4) {
                m = max(m, Int(bmp.pixels[i]))
            }
            return m
        }
        let aFull = maxAlpha(full)
        let aHalf = maxAlpha(half)
        XCTAssertGreaterThan(aFull, 200)
        XCTAssertGreaterThan(aHalf, 60)
        XCTAssertLessThanOrEqual(aHalf, aFull / 2 + 8)
        // Text rows ignore the logo opacity (the row is text-only → identical).
        let textFull = renderer.renderRow(
            row: literalRow("txt"), bgHeight: 1000, lineSpacingPercent: 0.4,
            logoOpacity: 1, logoProvider: nil)
        let textHalf = renderer.renderRow(
            row: literalRow("txt"), bgHeight: 1000, lineSpacingPercent: 0.4,
            logoOpacity: 0.5, logoProvider: nil)
        XCTAssertEqual(textFull.pixels, textHalf.pixels)
    }

    private static func logoFixture(width: Int, height: Int) -> YiyinLogoImage {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = 255
            rgba[i * 4 + 3] = 255
        }
        let ctx = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        return YiyinLogoImage(image: image, aspect: Double(width) / Double(height))
    }

    func testResolutionIndependentNormalizedRowBox() {
        // PREVIEW(2560-derived) vs FULL(全幅-derived): the normalized row
        // box is constant within the integer-rounding band — the 8-3
        // 全幅断言's 前置 (08-CONTEXT 版式分辨率无关). The rows come from
        // the ENGINE at each scale (the row fontPx = bgHeight × size% —
        // the resolution-independence lives exactly there).
        let template = YiyinTemplate(
            key: "row", name: "n", pattern: "NIKON ℤ 9 · 1/250s", use: true,
            font: YiyinFont(sizePercent: 3))
        let smallRow = YiyinTemplateEngine.resolve(
            template: template, inputs: engineInputs(bgHeight: 1334))!
        let largeRow = YiyinTemplateEngine.resolve(
            template: template, inputs: engineInputs(bgHeight: 5336))!
        let small = renderer.layoutRow(
            row: smallRow, bgHeight: 1334, lineSpacingPercent: 0.4, logoProvider: nil).metrics
        let large = renderer.layoutRow(
            row: largeRow, bgHeight: 5336, lineSpacingPercent: 0.4, logoProvider: nil).metrics
        let scale = Double(large.height) / Double(small.height)
        XCTAssertEqual(scale, 4.0, accuracy: 0.1, "the row height scales with bgHeight")
        // The yiyin 30px pads are ABSOLUTE pixels (their own quirk) — they
        // dilute the width ratio below 4.0 (upper-bounded by it).
        let widthRatio = Double(large.width) / Double(small.width)
        XCTAssertGreaterThan(widthRatio, 3.4)
        XCTAssertLessThanOrEqual(widthRatio, 4.0)
        // The TEXT portion (pads removed) scales at the bgHeight rate.
        let textSmall = Double(small.width - 60)
        let textLarge = Double(large.width - 60)
        XCTAssertEqual(textLarge / textSmall, 4.0, accuracy: 0.08)
    }

    // ── T4: the Metal composite leg through the real pipe ──

    func testWatermarkCompositeChangesBottomBandThroughPipe() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 64, height: 48)
        let trio = await committedTrio()
        // Drop gamma → the sampled plane stays linear float32.
        let base = trio.filter { $0.opName != GammaModule.opName }

        var params = WatermarkModule.Params.neutralSeed
        params.templates = [YiyinTemplate(
            key: "row", name: "n", pattern: "LIGHTAMER TEST", use: true,
            font: YiyinFont(sizePercent: 8, color: "#ffffff"))]
        params.fields = [] // no fields — a pure literal row
        let box = ModuleBox(module: WatermarkModule())
        box.setParams(params)
        let chain = (base + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (baseline, _) = try await RenderPipeline.process(
            image: image, instances: base, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        // Watermark-only face: canvas == image.
        XCTAssertEqual(output.width, baseline.width)
        XCTAssertEqual(output.height, baseline.height)

        let baseFloats = readFloats(baseline, metal: metal)
        let outFloats = readFloats(output, metal: metal)
        // The BOTTOM band carries ink (differences); the TOP band is
        // untouched (identical) — the bottom-center placement contract.
        var topDiffs = 0
        var bottomDiffs = 0
        var compared = 0
        for y in 0..<output.height {
            for x in 0..<output.width {
                let o = (y * output.width + x) * 4
                let d = abs(outFloats[o] - baseFloats[o]) + abs(outFloats[o + 1] - baseFloats[o + 1])
                if d > 0.01 {
                    if y < output.height / 2 { topDiffs += 1 } else { bottomDiffs += 1 }
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: pixels compared")
        XCTAssertGreaterThan(bottomDiffs, 20, "the text band differs")
        XCTAssertEqual(topDiffs, 0, "the top half is byte-stable (bottom-center anchor)")
    }

    // ── T4: the CoreText self-baseline golden (D-08-CONTEXT-8) ──

    private static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/golden/yiyin-watermark", isDirectory: true)

    /// SYSTEM DEPENDENCY (D-08-CONTEXT-8): the bitmaps freeze the CURRENT
    /// system font rasterization — OS/font updates legitimately drift and
    /// RE-FREEZE (regenerate with `LA_REGEN_YIYIN_GOLDEN=1`).
    private func golden(_ name: String, bitmap: YiyinRowBitmap) throws {
        let url = Self.goldenDir.appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["LA_REGEN_YIYIN_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: Self.goldenDir, withIntermediateDirectories: true)
            let image = try XCTUnwrap(Self.makeCGImage(bitmap: bitmap))
            Self.writePNG(image, url: url)
            return // regeneration pass — no assertion
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip(
                "golden artifact missing: input/golden/yiyin-watermark/\(name) — run "
                    + "`LA_REGEN_YIYIN_GOLDEN=1 Scripts/test-direct.sh 'YiyinWatermarkTests'`")
        }
        let data = try XCTUnwrap(Data(contentsOf: url))
        let expected = try XCTUnwrap(Self.readPNG(data))
        let got = try XCTUnwrap(Self.makeCGImage(bitmap: bitmap))
        XCTAssertEqual(got.width, expected.width, "\(name): width")
        XCTAssertEqual(got.height, expected.height, "\(name): height")
        // Exact self-baseline compare (same-OS determinism; any drift is a
        // RE-FREEZE event recorded in DECISIONS, not a failure to hide).
        let gotBytes = try XCTUnwrap(Self.rgbaBytes(got))
        let expectedBytes = try XCTUnwrap(Self.rgbaBytes(expected))
        XCTAssertEqual(gotBytes.count, expectedBytes.count)
        var diff = 0
        for (a, b) in zip(gotBytes, expectedBytes) where a != b {
            diff += 1
        }
        XCTAssertEqual(diff, 0, "\(name): \(diff) bytes drifted — re-freeze the golden (OS font update?)")
    }

    func testGoldenTextRowSelfBaseline() throws {
        // The literal row (white text) — the CoreText self-basis.
        let row = literalRow("LIGHTAMER · 1/250s")
        let bitmap = renderer.renderRow(
            row: row, bgHeight: 2000, lineSpacingPercent: 0.4,
            logoOpacity: 1, logoProvider: nil)
        try golden("text-row-baseline.png", bitmap: bitmap)
    }

    func testGoldenFieldedRowWithLogo() throws {
        // The fielded row with a logo slot (the red 2:1 fixture stands in
        // for the brand PDF — the LOGO BITMAP face, T5 PDFs render via the
        // same draw path).
        var row = YiyinTemplateEngine.ResolvedRow(
            items: [],
            font: YiyinFont(bold: true, sizePercent: 3),
            fontPx: 60, color: "#000000", verticalAlign: .baseline)
        row.items = [
            YiyinTemplateEngine.ResolvedItem.slot(
                .logo(make: "testbrand", variant: .black), font: YiyinFontOverride(), sizePx: 0),
            .literal(" ℤ 9 · "),
            .slot(.text("f/2.8"), font: YiyinFontOverride(), sizePx: 0),
        ]
        let provider: YiyinLogoProvider = { request in
            guard case .logo(let make, _) = request, make == "testbrand" else { return nil }
            return Self.logoFixture(width: 16, height: 8)
        }
        let bitmap = renderer.renderRow(
            row: row, bgHeight: 2000, lineSpacingPercent: 0.4,
            logoOpacity: 1, logoProvider: provider)
        try golden("fielded-row-logo.png", bitmap: bitmap)
    }

    // PNG plumbing (ImageIO round trip — the committed artifacts).
    private static func makeCGImage(bitmap: YiyinRowBitmap) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: bitmap.width, height: bitmap.height,
            bitsPerComponent: 8, bytesPerRow: bitmap.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.pixels.withUnsafeBytes {
            _ = ctx.data?.copyMemory(from: $0.baseAddress!, byteCount: bitmap.width * bitmap.height * 4)
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    private static func writePNG(_ image: CGImage, url: URL) {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func readPNG(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private static func rgbaBytes(_ image: CGImage) throws -> [UInt8] {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = ctx.data else { return [] }
        let buffer = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let bytes = [UInt8](UnsafeBufferPointer(start: buffer, count: image.width * image.height * 4))
        return bytes
    }

    // ── T5: the Logo double channel end-to-end (real brand PDFs) ──

    func testEmbeddedBrandLogoRendersThroughPipe() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 64, height: 48)
        let trio = await committedTrio()
        let base = trio.filter { $0.opName != GammaModule.opName }
        let store = YiyinLogoStore(userDirectory: tempSubdirectory("logos"))

        var params = WatermarkModule.Params.neutralSeed
        params.templates = [YiyinTemplate(
            key: "row", name: "n", pattern: "{Make}", use: true,
            font: YiyinFont(sizePercent: 6, color: "#000000"))]
        // Configure the Make field explicitly (unconfigured placeholders
        // are treated as hidden — D-08-2-5).
        params.fields = [YiyinField(key: "Make", show: true)]
        let box = ModuleBox(module: WatermarkModule())
        box.setParams(params)
        box.module.captureExif = CaptureMetadata(
            cameraMake: "SONY", cameraModel: "ILCE-7M4")
        box.module.logoExists = { make, variant in
            store.embeddedExists(make: make, variant: variant)
        }
        box.module.logoProvider = store.provider()
        let chain = (base + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (baseline, _) = try await RenderPipeline.process(
            image: image, instances: base, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let baseFloats = readFloats(baseline, metal: metal)
        let outFloats = readFloats(output, metal: metal)
        // The black Sony wordmark darkens pixels in the bottom band.
        var darkened = 0
        var compared = 0
        for y in output.height / 2..<output.height {
            for x in 0..<output.width {
                let o = (y * output.width + x) * 4
                if outFloats[o] < baseFloats[o] - 0.02 { darkened += 1 }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转")
        XCTAssertGreaterThan(darkened, 20, "the black brand logo ink lands in the bottom band")
    }

    private func tempSubdirectory(_ name: String) -> URL {
        let dir = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // ── T7: the PREVIEW drag initial timing (只记不设门 — the formal
    // benchmark lands in 08-3 perf.md) ──

    func testWatermarkPreviewDragInitialTimingRecorded() async throws {
        let metal = try await makeMetal()
        let image = gradientImage(width: 1706, height: 2560) // ~PREVIEW portrait
        let trio = await committedTrio(outputProfile: .sRGB)
        let base = trio.filter { $0.opName != GammaModule.opName }

        var params = WatermarkModule.Params.neutralSeed
        params.templates = [
            YiyinTemplate(
                key: "row1", name: "n", pattern: "{Make} {Model}", use: true,
                font: YiyinFont(bold: true, sizePercent: 3)),
            YiyinTemplate(
                key: "row2", name: "n",
                pattern: "{FocalLengthIn35mmFormat}mm f/{FNumber} {ExposureTime}s ISO{ISO}",
                use: true, font: YiyinFont(bold: true, sizePercent: 2.2)),
        ]
        let store = YiyinLogoStore(userDirectory: tempSubdirectory("logos"))
        let box = ModuleBox(module: WatermarkModule())
        box.setParams(params)
        box.module.displayProfileOverride = .sRGB
        box.module.captureExif = CaptureMetadata(
            cameraMake: "SONY", cameraModel: "ILCE-7M4",
            lensModel: "FE 24-70mm F2.8 GM", focalLength: 35, aperture: 2.8,
            shutterSpeed: 1.0 / 250.0, iso: 400, focalLength35mm: 52,
            exposureProgram: 3, meteringMode: 5, whiteBalance: 0)
        box.module.logoExists = { make, variant in
            store.embeddedExists(make: make, variant: variant)
        }
        box.module.logoProvider = store.provider()
        let chain = (base + [box as any ModuleBoxing])
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let cache = PipeCache()
        _ = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal, longEdge: 2560)

        // The drag-hot path: a logoOpacity edit only (all rows cached).
        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<5 {
            var edited = params
            edited.logoOpacity += 0.01
            box.setParams(edited)
            let start = clock.now
            _ = try await RenderPipeline.process(
                image: image, instances: chain, imageID: UUID(),
                resolution: .preview, cache: cache, metal: metal, longEdge: 2560)
            let elapsed = clock.now - start
            samples.append(Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e12)
        }
        let median = samples.sorted()[samples.count / 2]
        print("WATERMARK-PREVIEW-DRAG: median \(String(format: "%.1f", median))ms of \(samples.map { String(format: "%.0f", $0) }) (Debug, PSO-cold caveats — 只记不设门)")
        XCTAssertGreaterThan(median, 0)
    }
}