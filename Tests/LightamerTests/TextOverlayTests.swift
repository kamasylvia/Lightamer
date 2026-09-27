@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// TextOverlayTests (Plan 08-5 T2, IOP-FX-05 — textOverlay 66.7).
//
// The analytic face rides the FULL BLOCK glyph ("█" U+2588 — a filled
// rectangle by definition): the coverage bitmap has a known solid core, so
// position / rotation / opacity sampling asserts are exact rather than
// "looks drawn" (L020). The wiring face reuses the EffectsWiringTests
// composite shape (the same driver for base and layered — byte-identical
// comparisons).
//
// ANTI-VACUUM (L020): every comparison carries a compared>0 gate. L014:
// every readback drains first.
// ─────────────────────────────────────────────────────────────────────────────

final class TextOverlayTests: XCTestCase {

    // MARK: - direct-drive fixtures

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: TextOverlayKernel.metalBundle)
        return metal
    }

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int, value: Float = 0.25
    ) -> (any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        var pixels = [Float](repeating: value, count: width * height * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 1 }
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    private func read(_ texture: any MTLTexture) -> [Float] {
        var pixels = [Float](
            repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return pixels
    }

    @discardableResult
    private func runOverlay(
        _ module: TextOverlayModule, _ params: TextOverlayModule.Params,
        input: (any MTLTexture), metal: MetalContext
    ) async throws -> [Float] {
        let output = makeTexture(metal, width: input.width, height: input.height, value: 0.25)
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: input.width, height: input.height)
        piece.dscOut = piece.dscIn
        piece.iscale = 1.0
        module.commitParams(params, into: &piece)
        let roi = ROI(x: 0, y: 0, width: input.width, height: input.height, scale: 1.0)
        try await module.process(
            input: input, output: output, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed() // L014
        return read(output)
    }

    /// The solid coverage probe glyph.
    private static let blockGlyph = "███"

    // MARK: - position / rotation / opacity analytic asserts

    func testPositionRotationOpacityAnalytic() async throws {
        let metal = try await makeMetal()
        let width = 200, height = 160
        let store = YiyinFontStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("textoverlay-fonts-\(UUID().uuidString)"))
        let module = TextOverlayModule(fontStore: store)
        let input = makeTexture(metal, width: width, height: height, value: 0.25)

        // The rasterized block geometry (needed for the analytic probes).
        let extent = try XCTUnwrap(TextRasterizer.blockExtent(
            content: Self.blockGlyph, fontName: "Helvetica", fontSize: 60,
            lineSpacing: 0, longEdge: max(width, height), store: store))
        XCTAssertGreaterThan(extent.w, 0)
        XCTAssertGreaterThan(extent.h, 0)

        // ── position: the block center lands at (posX·W, posY·H) ──
        let params = TextOverlayModule.Params(
            content: Self.blockGlyph, fontName: "Helvetica", fontSize: 60,
            colorR: 1, colorG: 0, colorB: 0,
            posX: 0.5, posY: 0.5, rotationDegrees: 0, opacity: 1)
        let drawn = try await runOverlay(module, params, input: input, metal: metal)
        let centerIndex = ((height / 2) * width + width / 2) * 4
        // Source-over at solid coverage, opacity 1: out = color exactly.
        XCTAssertEqual(drawn[centerIndex], 1.0, accuracy: 1e-6, "center = text color")
        XCTAssertEqual(drawn[centerIndex + 1], 0.0, accuracy: 1e-6)
        // A far corner keeps the base value (outside the block).
        let cornerIndex = (2 * width + 2) * 4
        XCTAssertEqual(drawn[cornerIndex], 0.25, accuracy: 1e-6, "corner untouched")
        // Off-center position moves the covered center.
        let offParams = TextOverlayModule.Params(
            content: Self.blockGlyph, fontName: "Helvetica", fontSize: 60,
            colorR: 1, colorG: 0, colorB: 0,
            posX: 0.9, posY: 0.1, rotationDegrees: 0, opacity: 1)
        let offDrawn = try await runOverlay(module, offParams, input: input, metal: metal)
        let movedIndex = ((height / 10) * width + (width * 9 / 10)) * 4
        XCTAssertEqual(
            offDrawn[movedIndex], 1.0, accuracy: 1e-6,
            "the block follows the normalized position")
        XCTAssertEqual(offDrawn[centerIndex], 0.25, accuracy: 0.05,
            "the old center is (mostly) clear at the new position")

        // ── rotation: a wide single-line block becomes a vertical strip
        // under 90° (the analytic kernel mapping: u = dy + W/2, v = −dx + H/2)
        let rotatedParams = TextOverlayModule.Params(
            content: Self.blockGlyph, fontName: "Helvetica", fontSize: 60,
            colorR: 1, colorG: 0, colorB: 0,
            posX: 0.5, posY: 0.5, rotationDegrees: 90, opacity: 1)
        let rotated = try await runOverlay(module, rotatedParams, input: input, metal: metal)
        // Horizontal offset ≈ half the block width: covered unrotated,
        // clear rotated (|dx| > blockH/2 there).
        let sideOffset = max(extent.w / 2 - 2, 1)
        let leftIndex = ((height / 2) * width + (width / 2 - sideOffset)) * 4
        XCTAssertEqual(drawn[leftIndex], 1.0, accuracy: 1e-6,
            "unrotated: the horizontal offset is inside the wide block")
        XCTAssertEqual(
            rotated[leftIndex], 0.25, accuracy: 1e-4,
            "rotated 90°: the horizontal offset leaves the (now vertical) strip")
        // Vertical offset ≈ quarter block width: clear unrotated, covered
        // rotated.
        let vertOffset = max(extent.w / 4, 1)
        let belowIndex = ((height / 2 + vertOffset) * width + width / 2) * 4
        if vertOffset > extent.h / 2 {
            XCTAssertEqual(drawn[belowIndex], 0.25, accuracy: 1e-4,
                "unrotated: below the short block")
            XCTAssertEqual(rotated[belowIndex], 1.0, accuracy: 1e-4,
                "rotated 90°: the vertical offset enters the strip")
        }

        // ── opacity: 0 = the base; 0.5 = the exact source-over blend ──
        let transparent = TextOverlayModule.Params(
            content: Self.blockGlyph, fontName: "Helvetica", fontSize: 60,
            colorR: 1, colorG: 0, colorB: 0,
            posX: 0.5, posY: 0.5, rotationDegrees: 0, opacity: 0)
        let transparentDrawn = try await runOverlay(module, transparent, input: input, metal: metal)
        XCTAssertEqual(
            transparentDrawn[centerIndex], 0.25, accuracy: 1e-7,
            "opacity 0 must be the base plane at the covered point")
        let half = TextOverlayModule.Params(
            content: Self.blockGlyph, fontName: "Helvetica", fontSize: 60,
            colorR: 1, colorG: 0, colorB: 0,
            posX: 0.5, posY: 0.5, rotationDegrees: 0, opacity: 0.5)
        let halfDrawn = try await runOverlay(module, half, input: input, metal: metal)
        XCTAssertEqual(
            halfDrawn[centerIndex], 0.25 * 0.5 + 1.0 * 0.5, accuracy: 1e-6,
            "opacity 0.5 = the exact source-over blend at solid coverage")
    }

    func testMultiLineBlockExtentGrowsWithLines() throws {
        let store = YiyinFontStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("textoverlay-fonts-\(UUID().uuidString)"))
        let one = TextRasterizer.blockExtent(
            content: "AB", fontName: "Helvetica", fontSize: 60, lineSpacing: 0,
            longEdge: 1000, store: store)
        let two = TextRasterizer.blockExtent(
            content: "AB\nCD", fontName: "Helvetica", fontSize: 60, lineSpacing: 0,
            longEdge: 1000, store: store)
        let oneUnwrapped = try XCTUnwrap(one)
        let twoUnwrapped = try XCTUnwrap(two)
        XCTAssertGreaterThan(
            twoUnwrapped.h, oneUnwrapped.h,
            "the second line must add a line height")
        XCTAssertNil(TextRasterizer.blockExtent(
            content: "  \n ", fontName: "Helvetica", fontSize: 60,
            lineSpacing: 0, longEdge: 1000, store: store),
            "whitespace-only content is the neutral face")
    }

    // MARK: - the coverage-texture cache (StableHash key, MISS/HIT)

    func testCoverageCacheMissHit() async throws {
        let metal = try await makeMetal()
        let store = YiyinFontStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("textoverlay-fonts-\(UUID().uuidString)"))
        let module = TextOverlayModule(fontStore: store)
        let input = makeTexture(metal, width: 120, height: 90)
        let base = TextOverlayModule.Params(
            content: Self.blockGlyph, fontName: "Helvetica", fontSize: 50)

        _ = try await runOverlay(module, base, input: input, metal: metal)
        XCTAssertEqual(module.cacheMissesForTesting, 1, "the first run rasterizes")
        XCTAssertEqual(module.cacheHitsForTesting, 0)
        XCTAssertNotNil(module.coverageTextureForTesting)

        _ = try await runOverlay(module, base, input: input, metal: metal)
        XCTAssertEqual(
            module.cacheHitsForTesting, 1,
            "the same params + long edge must HIT the coverage cache")

        let changed = TextOverlayModule.Params(
            content: Self.blockGlyph, fontName: "Helvetica", fontSize: 80)
        _ = try await runOverlay(module, changed, input: input, metal: metal)
        XCTAssertEqual(
            module.cacheMissesForTesting, 2,
            "a params change must MISS (re-rasterize)")
        // The key is a pure (params, longEdge) function — L013.
        XCTAssertEqual(
            TextOverlayModule.cacheKey(base, longEdge: 120),
            TextOverlayModule.cacheKey(base, longEdge: 120))
        XCTAssertNotEqual(
            TextOverlayModule.cacheKey(base, longEdge: 120),
            TextOverlayModule.cacheKey(base, longEdge: 240),
            "the long edge rides the key (the raster size follows the plane)")
    }

    // MARK: - the neutral face (empty content = the routed-blit identity)

    func testEmptyContentIsByteIdentity() async throws {
        let metal = try await makeMetal()
        let module = TextOverlayModule(
            fontStore: YiyinFontStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("textoverlay-fonts-\(UUID().uuidString)")))
        let input = makeTexture(metal, width: 48, height: 40, value: 0.3)
        let output = try await runOverlay(
            module, TextOverlayModule.Params(), input: input, metal: metal)
        let inBytes = read(input)
        XCTAssertEqual(module.cacheMissesForTesting, 0, "the neutral face never rasterizes")
        var compared = 0
        for (index, value) in inBytes.enumerated() {
            XCTAssertEqual(
                output[index].bitPattern, value.bitPattern,
                "empty content must be the byte identity at \(index)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertTrue(module.isNeutral(TextOverlayModule.Params(content: "")))
        XCTAssertTrue(module.isNeutral(TextOverlayModule.Params(content: " \n ")))
        XCTAssertFalse(module.isNeutral(TextOverlayModule.Params(content: "LA")))
    }

    // MARK: - layer-mask localization (the EffectsWiringTests shape)

    private func makeMetalWiring() async throws -> MetalContext {
        let metal = try await makeMetal()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    func testLayerMaskLocalization() async throws {
        let metal = try await makeMetalWiring()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let image = EffectsFixture.image()
        let base = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        let recordID = UUID()
        let made = await registry.makeBox(
            opName: TextOverlayModule.opName, instanceID: recordID)
        let box = try XCTUnwrap(made, "textOverlay must register")
        (box as? ModuleBox<TextOverlayModule>)?.setParams(TextOverlayModule.Params(
            content: "███", fontName: "Helvetica", fontSize: 80,
            colorR: 1, colorG: 0, colorB: 0,
            posX: 0.5, posY: 0.5, rotationDegrees: 0, opacity: 1))
        let record = ModuleInstance(
            id: recordID, opName: TextOverlayModule.opName, multiPriority: 5,
            multiName: "text-mask", iopOrder: box.iopOrder, version: 1,
            enabled: true, paramsData: box.paramsData, paramsHash: box.paramsHash)
        let layer = AdjustmentLayer(name: "text-mask", opacity: 1.0, chain: [record])
        layer.mask = MaskSpec(
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
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layer)

        let basePlane = try await Self.composite(
            image, base: base, stack: nil, registry: registry, metal: metal)
        let layeredPlane = try await Self.composite(
            image, base: base, stack: stack, registry: registry, metal: metal)

        let center = (basePlane.height / 2, basePlane.width / 2)
        let baseR = basePlane.red(center.1, center.0)
        let layeredR = layeredPlane.red(center.1, center.0)
        // The masked interior shows the red text (L020 content-level).
        XCTAssertGreaterThan(
            layeredR - baseR, 0.05,
            "the masked interior must show the text (base r=\(baseR) → \(layeredR))")
        // The far corner (outside the ellipse) stays byte-identical.
        XCTAssertEqual(
            Array(basePlane.pixelBytes(2, 2)),
            Array(layeredPlane.pixelBytes(2, 2)),
            "the mask exterior must be byte-identical")
    }

    // MARK: - the yiyin coexistence face (66.7 non-terminal + 77.0 terminal)

    func testYiyinCoexistenceAndZeroChangeBoundary() async throws {
        // The slot relations: the text layer is BELOW the terminal tail
        // floor (layer-mask eligible); the watermark stays the terminal
        // 77.0 — untouched by this plan (V50OrderTests pins the table).
        XCTAssertEqual(TextOverlayModule.iopOrder, 66.7)
        XCTAssertEqual(WatermarkModule.iopOrder, 77.0)
        XCTAssertLessThan(TextOverlayModule.iopOrder, 70.0)
        // Both register; a chain carrying BOTH runs (the text overlay in
        // the non-terminal segment, the neutral watermark riding through
        // the terminal segment) and equals the text-overlay-only output
        // (the watermark's neutral seed is the byte identity).
        let metal = try await makeMetalWiring()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let image = EffectsFixture.image()
        let base = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)

        func textOverlayBox() async throws -> (any ModuleBoxing) {
            let made = await registry.makeBox(opName: TextOverlayModule.opName)
            let box = try XCTUnwrap(made)
            (box as? ModuleBox<TextOverlayModule>)?.setParams(TextOverlayModule.Params(
                content: "LA", fontName: "Helvetica", fontSize: 60,
                colorR: 1, colorG: 1, colorB: 1))
            return box
        }
        let withText = try await Self.composite(
            image, base: base + [try await textOverlayBox()], stack: nil,
            registry: registry, metal: metal)
        let watermarkMade = await registry.makeBox(opName: WatermarkModule.opName)
        let watermarkBox = try XCTUnwrap(watermarkMade)
        let both = try await Self.composite(
            image, base: base + [try await textOverlayBox(), watermarkBox],
            stack: nil, registry: registry, metal: metal)
        XCTAssertEqual(withText.bytes, both.bytes,
            "the neutral watermark must ride through the text-overlay chain untouched")
    }

    // MARK: - the shared composite helpers (the EffectsWiringTests shape)

    private enum EffectsFixture {
        static func image(width: Int = 64, height: Int = 48) -> DecodedImage {
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

    private static func composite(
        _ image: DecodedImage,
        base: [any ModuleBoxing],
        stack: LayerStack?,
        registry: ModuleRegistry,
        metal: MetalContext
    ) async throws -> ComposedPlane {
        let empty = stack ?? LayerStack(baseLayer: BackgroundLayer())
        let result = try await LayerCompositeDriver.composite(
            image: image, imageID: UUID(), baseInstances: base,
            layerStack: empty, registry: registry, resolution: .preview,
            cache: PipeCache(), metal: metal, longEdge: nil, roiHint: nil,
            policy: .preview)
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
        let texture = result.output
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
}
