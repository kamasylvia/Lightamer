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
}
