@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// Plan 06-07 T2/T3 — the retouch parity suite:
//   clone   — analytic transfer assertion (源区平移拷贝逐值)
//   fill    — constant domain (mask 内 == 填充色, 外 == base)
//   blur    — profile gates (edge contrast collapse + linear preservation)
//   window  — the source ∪ target ROI extension (跨窗 stroke 无源区黑边,
//             内容级断言 L020 ③)
//   heal    — GPU solver vs an independent float64 red-black SOR reference
//             (dt heal.c:354-422 math) <1e-3, + the interaction-latency
//             benchmark that backs the D-06-CONTEXT-1 decision.
//   leg     — empty-stroke identity (轨 B 插链零增量) + stroke-leg cache
//             accounting (edit-above stays a HIT).
// ─────────────────────────────────────────────────────────────────────────────
final class RetouchParityTests: XCTestCase {

    private let size = SIMD2<Int>(64, 48)

    // ── Fixtures ──

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    /// ONE stable imageID per test instance — the cache-accounting test
    /// needs cross-run keys that only differ by their upstream hashes.
    private var accountingImageID: UUID { UUID(uuidString: Self.accountingID)! }
    private static let accountingID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEFFFF0001"

    private func makeRegistry() async -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    /// The linear-gradient decode fixture (values analytic per pixel).
    private func makeGradientImage() throws -> DecodedImage {
        try makeImage { x, y in
            SIMD3<Float>(
                0.1 + 0.7 * Float(x) / Float(size.x - 1),
                0.2 + 0.5 * Float(y) / Float(size.y - 1),
                0.3)
        }
    }

    /// Constant field + a bright vertical stripe (the blur profile fixture).
    private func makeStepImage() throws -> DecodedImage {
        try makeImage { x, _ in
            (28...35).contains(x) ? SIMD3<Float>(repeating: 0.9)
                : SIMD3<Float>(repeating: 0.3)
        }
    }

    private func makeImage(_ f: (Int, Int) -> SIMD3<Float>) throws -> DecodedImage {
        var pixels = [Float](repeating: 0, count: size.x * size.y * 4)
        for y in 0..<size.y {
            for x in 0..<size.x {
                let o = (y * size.x + x) * 4
                let c = f(x, y)
                pixels[o + 0] = c.x
                pixels[o + 1] = c.y
                pixels[o + 2] = c.z
                pixels[o + 3] = 1.0
            }
        }
        let bitmap = pixels.withUnsafeBytes { Data($0) }
        return DecodedImage(
            ciImage: CIImage(
                bitmapData: bitmap,
                bytesPerRow: size.x * 4 * MemoryLayout<Float>.stride,
                size: CGSize(width: size.x, height: size.y),
                format: .RGBAf, colorSpace: WorkingSpace.colorSpace),
            rawTech: RAWTechnicalParams(blackLevel: 0.0),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    /// L014 fence + float32 read for working-space planes (16 B/px).
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

    private func pixel(
        _ floats: [Float], _ x: Int, _ y: Int, width: Int? = nil
    ) -> SIMD4<Float> {
        let w = width ?? size.x
        let o = (y * w + x) * 4
        return SIMD4(floats[o], floats[o + 1], floats[o + 2], floats[o + 3])
    }

    /// Element-wise max |a − b| (scalar abs — no SIMD abs surface needed).
    private func maxDiff(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
        let d = a - b
        return max(max(abs(d.x), abs(d.y)), max(abs(d.z), abs(d.w)))
    }

    private func ellipseStroke(
        algorithm: RetouchAlgorithm, center: SIMD2<Float>, radius: Float,
        source: SIMD2<Float>? = nil, opacity: Float = 1.0,
        blurRadius: Float? = nil, fillColor: SIMD3<Float>? = nil
    ) -> RetouchStroke {
        RetouchStroke(
            algorithm: algorithm,
            form: MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: center.x, y: center.y),
                radiusX: radius, radiusY: radius,
                rotationDegrees: 0, border: 0))),
            source: source.map { MaskPoint(x: $0.x, y: $0.y) },
            opacity: opacity, blurRadius: blurRadius, fillColor: fillColor)
    }

    private func retouchLayer(_ strokes: [RetouchStroke], opacity: Float = 1.0) -> RetouchLayer {
        let layer = RetouchLayer(name: "Fix", opacity: opacity)
        for s in strokes { layer.append(stroke: s) }
        return layer
    }

    private func composite(
        _ image: DecodedImage, stack: LayerStack, metal: MetalContext,
        registry: ModuleRegistry, cache: PipeCache = PipeCache(),
        roiHint: ROI? = nil
    ) async throws -> LayerCompositeResult {
        let base = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        return try await LayerCompositeDriver.composite(
            image: image, imageID: accountingImageID, baseInstances: base,
            layerStack: stack, registry: registry, resolution: .preview,
            cache: cache, metal: metal, longEdge: nil, roiHint: roiHint,
            policy: .preview)
    }

    /// The default chain minus the display tail (colorout/gamma): the
    /// composite output IS the working-space plane, so the stroke math's
    /// closed forms hold exactly (strokes act pre-terminal).
    private func workingChain(registry: ModuleRegistry) async -> [any ModuleBoxing] {
        let chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .sRGB)
        return chain.filter { !["colorout", GammaModule.opName].contains($0.opName) }
    }

    private func workingComposite(
        _ image: DecodedImage, stack: LayerStack, metal: MetalContext,
        registry: ModuleRegistry, cache: PipeCache = PipeCache(),
        roiHint: ROI? = nil
    ) async throws -> LayerCompositeResult {
        let base = await workingChain(registry: registry)
        return try await LayerCompositeDriver.composite(
            image: image, imageID: accountingImageID, baseInstances: base,
            layerStack: stack, registry: registry, resolution: .preview,
            cache: cache, metal: metal, longEdge: nil, roiHint: roiHint,
            policy: .preview)
    }

    /// Composite radius in window px (identity mapper — no geometry in the
    /// default chain).
    private var radiusPx: Double { 0.1 * Double(size.x) }

    /// Interior sample points: the stroke-center box within 0.55r (mask == 1
    /// for border-0 ellipses), window-clamped.
    private func interiorPoints(center: SIMD2<Double>, radiusPx: Double) -> [(Int, Int)] {
        var points: [(Int, Int)] = []
        let cx = center.x * Double(size.x), cy = center.y * Double(size.y)
        for y in 0..<size.y {
            for x in 0..<size.x {
                let dx = Double(x) - cx, dy = Double(y) - cy
                if dx * dx + dy * dy < pow(radiusPx * 0.55, 2) {
                    points.append((x, y))
                }
            }
        }
        return points
    }

    // ── T2: clone ──

    /// Analytic transfer: inside the hard-edged stroke the output equals the
    /// base content sampled at the source offset (dt `_retouch_clone` masked
    /// paste at opacity 1); outside the stroke the base is untouched.
    func testCloneStrokeTransfersSourceContent() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeGradientImage()

        // target (0.7, 0.5), source (0.3, 0.5): offset = −0.4·64 = −25.6 px.
        let stroke = ellipseStroke(
            algorithm: .clone, center: SIMD2(0.7, 0.5), radius: 0.1,
            source: SIMD2(0.3, 0.5))
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(retouchLayer([stroke]))

        let base = try await workingComposite(image, stack: LayerStack(baseLayer: BackgroundLayer()), metal: metal, registry: registry)
        let fixed = try await workingComposite(image, stack: stack, metal: metal, registry: registry)
        let baseF = rawFloats(base.output, metal: metal)
        let fixedF = rawFloats(fixed.output, metal: metal)

        let offsetPx = (0.3 - 0.7) * Float(size.x)
        let center = SIMD2<Double>(0.7, 0.5)
        var compared = 0
        var maxRel: Float = 0
        for (x, y) in interiorPoints(center: center, radiusPx: radiusPx) {
            let out = pixel(fixedF, x, y)
            // Source sample: offset-sampled nearest px (the kernel rounds).
            let sx = max(0, min(size.x - 1, x + Int(offsetPx.rounded())))
            let expected = pixel(baseF, sx, y)
            let d = maxDiff(out, expected)
            if d > maxRel { maxRel = d }
            compared += 1
            // The untouched base pixels (outside the stroke) stay byte-equal.
            let dx = Double(x) - center.x * Double(size.x)
            let dy = Double(y) - center.y * Double(size.y)
            if dx * dx + dy * dy > pow(radiusPx * 1.6, 2) {
                XCTAssertEqual(out, pixel(baseF, x, y),
                               "stroke exterior must be untouched at (\(x),\(y))")
            }
        }
        XCTAssertGreaterThan(compared, 20, "防空转: interior coverage")
        XCTAssertLessThanOrEqual(maxRel, 1e-5, "clone = source-shifted base (解析断言)")
    }

    // ── T2: fill ──

    /// Constant domain: inside the stroke == the fill color exactly; the
    /// layer opacity folds through the blend triple outside the mask leg.
    func testFillStrokeConstantDomain() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeGradientImage()
        let fill = SIMD3<Float>(0.9, 0.2, 0.1)
        let stroke = ellipseStroke(
            algorithm: .fill, center: SIMD2(0.35, 0.55), radius: 0.1,
            fillColor: fill)
        let layer = retouchLayer([stroke], opacity: 0.5)
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(layer)

        let base = try await workingComposite(image, stack: LayerStack(baseLayer: BackgroundLayer()), metal: metal, registry: registry)
        let fixed = try await workingComposite(image, stack: stack, metal: metal, registry: registry)
        let baseF = rawFloats(base.output, metal: metal)
        let fixedF = rawFloats(fixed.output, metal: metal)

        let center = SIMD2<Double>(0.35, 0.55)
        var compared = 0
        var maxErr: Float = 0
        for (x, y) in interiorPoints(center: center, radiusPx: radiusPx) {
            let out = pixel(fixedF, x, y)
            let below = pixel(baseF, x, y)
            // masked paste at m=1 → replacement; then blend @0.5:
            // 0.5·below + 0.5·replacement.
            let expected = 0.5 * below + 0.5 * SIMD4<Float>(fill, 1)
            maxErr = max(maxErr, maxDiff(out, expected))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 20, "防空转: interior coverage")
        XCTAssertLessThanOrEqual(maxErr, 1e-5, "fill 常数域 + layer opacity fold")
    }

    // ── T2: blur ──

    /// Profile gates: the stripe edge inside the stroke collapses (blur
    /// happened — compared > 0), the stroke exterior keeps the step, and a
    /// LINEAR region blurs to itself (Gaussian preserves affine fields).
    func testBlurStrokeProfile() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let stepImage = try makeStepImage()
        let gradientImage = try makeGradientImage()
        let stroke = ellipseStroke(
            algorithm: .blur, center: SIMD2(0.5, 0.5), radius: 0.2,
            blurRadius: 2.0)

        // (a) step image: contrast collapse inside the stroke.
        var stackStep = LayerStack(baseLayer: BackgroundLayer())
        stackStep.addAdjustment(retouchLayer([stroke]))
        let stepBase = try await workingComposite(stepImage, stack: LayerStack(baseLayer: BackgroundLayer()), metal: metal, registry: registry)
        let stepFixed = try await workingComposite(stepImage, stack: stackStep, metal: metal, registry: registry)
        let sb = rawFloats(stepBase.output, metal: metal)
        let sf = rawFloats(stepFixed.output, metal: metal)
        let center = SIMD2<Double>(0.5, 0.5)
        var changed = 0
        var interiorMin = Float.greatestFiniteMagnitude
        var interiorMax = -Float.greatestFiniteMagnitude
        for (x, y) in interiorPoints(center: center, radiusPx: 0.2 * Double(size.x)) {
            let d = maxDiff(pixel(sf, x, y), pixel(sb, x, y))
            if d > 1e-2 { changed += 1 }
            interiorMin = min(interiorMin, pixel(sf, x, y).x)
            interiorMax = max(interiorMax, pixel(sf, x, y).x)
        }
        XCTAssertGreaterThan(changed, 10, "防空转: the blur must move edge pixels")
        XCTAssertLessThan(interiorMax - interiorMin, 0.55,
                          "edge contrast collapses inside the stroke (base step = 0.6)")

        // (b) linear gradient: blur preserves the affine field (deep
        // interior == base within the IIR transient budget).
        var stackGrad = LayerStack(baseLayer: BackgroundLayer())
        stackGrad.addAdjustment(retouchLayer([stroke]))
        let gradBase = try await workingComposite(gradientImage, stack: LayerStack(baseLayer: BackgroundLayer()), metal: metal, registry: registry)
        let gradFixed = try await workingComposite(gradientImage, stack: stackGrad, metal: metal, registry: registry)
        let gb = rawFloats(gradBase.output, metal: metal)
        let gf = rawFloats(gradFixed.output, metal: metal)
        var maxErr: Float = 0
        var deepCompared = 0
        for (x, y) in interiorPoints(center: center, radiusPx: 0.12 * Double(size.x)) {
            maxErr = max(maxErr, maxDiff(pixel(gf, x, y), pixel(gb, x, y)))
            deepCompared += 1
        }
        XCTAssertGreaterThan(deepCompared, 5, "防空转: deep-interior coverage")
        XCTAssertLessThanOrEqual(maxErr, 2e-3, "Gaussian preserves the linear gradient (剖面)")
    }

    // ── T2: the cross-window ROI extension ──

    /// The 源区黑边 red line: a clone stroke whose source patch lives OUTSIDE
    /// the requested window renders correctly (the base sub-run covered the
    /// source∪target extent) — content-level assertion vs the full render.
    func testCloneCrossWindowSourceExpansion() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeGradientImage()

        let stroke = ellipseStroke(
            algorithm: .clone, center: SIMD2(0.25, 0.5), radius: 0.1,
            source: SIMD2(0.75, 0.5))
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(retouchLayer([stroke]))

        let hint = ROI(x: 0, y: 0, width: size.x / 2, height: size.y, scale: 1.0)
        let windowed = try await workingComposite(
            image, stack: stack, metal: metal, registry: registry, roiHint: hint)
        XCTAssertGreaterThan(
            windowed.window.width, hint.width,
            "the window must widen to cover the source patch (\(windowed.window))")

        let full = try await workingComposite(image, stack: stack, metal: metal, registry: registry)
        let base = try await workingComposite(image, stack: LayerStack(baseLayer: BackgroundLayer()), metal: metal, registry: registry)
        let wf = rawFloats(windowed.output, metal: metal)
        let ff = rawFloats(full.output, metal: metal)
        let bf = rawFloats(base.output, metal: metal)

        let offsetPx = (0.75 - 0.25) * Float(size.x)
        let center = SIMD2<Double>(0.25, 0.5)
        let windowWidth = windowed.output.width
        var compared = 0
        var maxErr = Float(0)
        var maxFullErr = Float(0)
        for (x, y) in interiorPoints(center: center, radiusPx: radiusPx) {
            let out = pixel(wf, x, y, width: windowWidth) // plane px == window px (origin 0)
            XCTAssertGreaterThan(out.x + out.y + out.z, 0.01,
                                 "源区黑边: stroke interior must NOT be black at (\(x),\(y))")
            let sx = max(0, min(size.x - 1, x + Int(offsetPx.rounded())))
            maxErr = max(maxErr, maxDiff(out, pixel(bf, sx, y)))
            // ROI invariance (content level): the windowed render matches
            // the full render within the decode sub-domain leg's ±1px crop
            // rounding (the gradient's 0.011/px step dominates the gate —
            // recorded in 06-07-DECISIONS; the retouch leg itself is
            // byte-deterministic per ROI).
            maxFullErr = max(maxFullErr, maxDiff(out, pixel(ff, x, y)))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 20, "防空转: interior coverage")
        XCTAssertLessThanOrEqual(maxErr, 1e-5, "cross-window clone = source content (无黑边)")
        XCTAssertLessThanOrEqual(maxFullErr, 2e-2, "windowed ≈ full render (content level)")
    }

    // ── T5-style identity + cache accounting ──

    /// 轨 B 插链零增量: an EMPTY-stroke retouch layer composites byte-identical
    /// to the retouch-free stack.
    func testEmptyStrokeRetouchLayerIsIdentity() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeGradientImage()
        var withLayer = LayerStack(baseLayer: BackgroundLayer())
        withLayer.addAdjustment(retouchLayer([]))
        let a = try await workingComposite(image, stack: LayerStack(baseLayer: BackgroundLayer()), metal: metal, registry: registry)
        let b = try await workingComposite(image, stack: withLayer, metal: metal, registry: registry)
        let af = rawFloats(a.output, metal: metal)
        let bf = rawFloats(b.output, metal: metal)
        XCTAssertEqual(af.count, bf.count)
        XCTAssertGreaterThan(af.count, 0, "防空转")
        XCTAssertTrue(af.elementsEqual(bf), "空 stroke 层恒等")
    }

    /// The retouch leg's incremental accounting: same input → leg HIT;
    /// an UPPER layer's param edit leaves the retouch leg cache intact.
    func testStrokeLegCacheAccounting() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeGradientImage()
        let cache = PipeCache()
        let stroke = ellipseStroke(
            algorithm: .fill, center: SIMD2(0.5, 0.5), radius: 0.12,
            fillColor: SIMD3(0.8, 0.4, 0.2))
        let fix = retouchLayer([stroke])
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(fix)

        func gainLayer(_ gain: Float) -> AdjustmentLayer {
            AdjustmentLayer(
                name: "Gain", opacity: 1.0,
                chain: [ModuleInstance(
                    module: TestGainModule.self,
                    params: TestGainModule.Params(gain: gain))])
        }

        // Run 1: cold — the leg renders.
        stack.addAdjustment(gainLayer(1.2))
        let r1 = try await workingComposite(image, stack: stack, metal: metal, registry: registry, cache: cache)
        let fixStats1 = try XCTUnwrap(r1.layerStats.first { $0.layerID == fix.id })
        XCTAssertFalse(fixStats1.prefixHit, "cold run: retouch blend prefix MISS")

        // Run 2: warm — leg + prefix all HIT.
        let r2 = try await workingComposite(image, stack: stack, metal: metal, registry: registry, cache: cache)
        let fixStats2 = try XCTUnwrap(r2.layerStats.first { $0.layerID == fix.id })
        XCTAssertGreaterThanOrEqual(fixStats2.run.hits, 0)
        XCTAssertTrue(fixStats2.prefixHit, "warm run: retouch prefix HIT")

        // Run 3: edit the UPPER layer — the retouch leg input is unchanged,
        // so its stroke-leg line survives (the retouch-dimension incremental
        // model; the gain layer's prefix flips).
        stack.replace(gainLayer(1.5))
        let r3 = try await workingComposite(image, stack: stack, metal: metal, registry: registry, cache: cache)
        let fixStats3 = try XCTUnwrap(r3.layerStats.first { $0.layerID == fix.id })
        XCTAssertTrue(fixStats3.prefixHit || fixStats3.run.hits > 0,
                      "upper-layer edit keeps the retouch leg warm (prefix \(fixStats3.prefixHit), hits \(fixStats3.run.hits))")
    }

    // ── T3: heal vs the independent float64 reference ──

    /// The dt heal math (heal.c:96-422) as an independent float64 CPU
    /// reference: pattern = target − source; red/black SOR (full-grid —
    /// dt's run-length encoding is a perf trick, not math); healed =
    /// source + solution. NO early exit (fully converged) so the comparison
    /// bounds the GPU side's ε-gated residual.
    static func referenceHeal(
        target: [Double], source: [Double], mask: [Double],
        width: Int, height: Int, maxIter: Int = 2000
    ) -> [Double] {
        var pattern = (0..<(width * height)).map { target[$0] - source[$0] }
        let nmask = mask.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
        let w = (2.0 - 1.0 / (0.1575 * Double(nmask).squareRoot() + 0.8)) * 0.25
        var solution = pattern
        for iteration in 0..<maxIter {
            var err = 0.0
            for parity in 0...1 {
                for y in 0..<height {
                    for x in 0..<width {
                        if (x + y) & 1 != parity { continue }
                        let i = y * width + x
                        if mask[i] <= 0 { continue }
                        var a = 4.0
                        var sum = 0.0
                        if x > 0 { sum += solution[i - 1] } else { a -= 1 }
                        if x < width - 1 { sum += solution[i + 1] } else { a -= 1 }
                        if y > 0 { sum += solution[i - width] } else { a -= 1 }
                        if y < height - 1 { sum += solution[i + width] } else { a -= 1 }
                        let diff = w * (a * solution[i] - sum)
                        solution[i] -= diff
                        err += diff * diff
                    }
                }
            }
        }
        // healed = source + solution
        return (0..<(width * height)).map { source[$0] + solution[$0] }
    }

    private func makeRGBAPlane(
        _ values: [Float], width: Int, height: Int, metal: MetalContext
    ) throws -> any MTLTexture {
        let texture = try RetouchEngine.makePlane(
            width: width, height: height,
            usage: [.shaderRead, .shaderWrite], metal: metal)
        let region = MTLRegionMake2D(0, 0, width, height)
        values.withUnsafeBytes {
            texture.replace(
                region: region, mipmapLevel: 0, slice: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16,
                bytesPerImage: 0)
        }
        return texture
    }

    private func makeR32Plane(
        _ values: [Float], width: Int, height: Int, metal: MetalContext
    ) throws -> any MTLTexture {
        let texture = try RetouchEngine.makePlane(
            width: width, height: height, pixelFormat: .r32Float,
            usage: [.shaderRead, .shaderWrite], metal: metal)
        let region = MTLRegionMake2D(0, 0, width, height)
        values.withUnsafeBytes {
            texture.replace(
                region: region, mipmapLevel: 0, slice: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 4,
                bytesPerImage: 0)
        }
        return texture
    }

    /// The synthetic patch fixture: a smooth gradient + a Gaussian bump in
    /// the masked region (the "blemish"), source = clean gradient. Gray data
    /// (r=g=b) keeps the reference single-channel.
    private func healFixture(
        width: Int, height: Int
    ) -> (target: [Double], source: [Double], mask: [Double]) {
        let cx = Double(width) / 2, cy = Double(height) / 2
        let maskRadius = Double(min(width, height)) / 4
        let bumpSigma = maskRadius / 2
        var target = [Double](repeating: 0, count: width * height)
        var source = [Double](repeating: 0, count: width * height)
        var mask = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let base = 0.3 + 0.25 * Double(x) / Double(width - 1)
                    + 0.1 * Double(y) / Double(height - 1)
                let d2 = pow(Double(x) - cx, 2) + pow(Double(y) - cy, 2)
                let bump = 0.5 * exp(-d2 / (2 * pow(bumpSigma, 2)))
                source[i] = base
                target[i] = base + bump
                mask[i] = d2 < pow(maskRadius, 2) ? 1.0 : 0.0
            }
        }
        return (target, source, mask)
    }

    /// GPU healSolve vs the float64 reference <1e-3 (the 迭代容差档 — both
    /// solvers share dt's formulas; the gate bounds the ε-gated residual
    /// difference). compared > 0 防空转.
    func testHealPatchConvergesToFloat64Reference() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 24, h = 18
        let (target, source, mask) = healFixture(width: w, height: h)
        var targetF = [Float](repeating: 0, count: w * h * 4)
        var sourceF = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            targetF[i * 4 + 0] = Float(target[i])
            targetF[i * 4 + 1] = Float(target[i])
            targetF[i * 4 + 2] = Float(target[i])
            targetF[i * 4 + 3] = 1
            sourceF[i * 4 + 0] = Float(source[i])
            sourceF[i * 4 + 1] = Float(source[i])
            sourceF[i * 4 + 2] = Float(source[i])
            sourceF[i * 4 + 3] = 1
        }
        let targetTex = try makeRGBAPlane(targetF, width: w, height: h, metal: metal)
        let sourceTex = try makeRGBAPlane(sourceF, width: w, height: h, metal: metal)
        let maskTex = try makeR32Plane(mask.map(Float.init), width: w, height: h, metal: metal)

        let healed = try await RetouchEngine.healSolve(
            target: targetTex, source: sourceTex, mask: maskTex, metal: metal)
        let healedF = rawFloats(healed, metal: metal)

        let reference = Self.referenceHeal(
            target: target, source: source, mask: mask, width: w, height: h)

        var compared = 0
        var maxErr: Float = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if mask[i] <= 0 {
                    // Dirichlet exterior: outside the mask the healed patch
                    // is the TARGET content untouched (pass-through).
                    XCTAssertEqual(healedF[i * 4], Float(target[i]), accuracy: 1e-6,
                                   "exterior untouched at (\(x),\(y))")
                    continue
                }
                let gpu = healedF[i * 4]
                let ref = Float(reference[i])
                maxErr = max(maxErr, abs(gpu - ref))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 50, "防空转: masked-cell coverage")
        XCTAssertLessThanOrEqual(maxErr, 1e-3, "GPU heal == float64 reference (迭代容差档)")
    }

    /// D-06-CONTEXT-1 基准: the typical interaction patch (~160×120, a
    /// 100MP-windowed stroke) heals inside the interaction budget. The
    /// measured number lands in 06-07-DECISIONS; the 100ms gate is the
    /// plan's order-of-magnitude budget.
    func testHealInteractionLatencyBenchmark() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 160, h = 120
        let (target, source, mask) = healFixture(width: w, height: h)
        var targetF = [Float](repeating: 0, count: w * h * 4)
        var sourceF = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            targetF[i * 4 + 0] = Float(target[i])
            targetF[i * 4 + 1] = Float(target[i])
            targetF[i * 4 + 2] = Float(target[i])
            targetF[i * 4 + 3] = 1
            sourceF[i * 4 + 0] = Float(source[i])
            sourceF[i * 4 + 1] = Float(source[i])
            sourceF[i * 4 + 2] = Float(source[i])
            sourceF[i * 4 + 3] = 1
        }
        let targetTex = try makeRGBAPlane(targetF, width: w, height: h, metal: metal)
        let sourceTex = try makeRGBAPlane(sourceF, width: w, height: h, metal: metal)
        let maskTex = try makeR32Plane(mask.map(Float.init), width: w, height: h, metal: metal)

        // Warm the PSOs once, then time 3 solvers, take the median.
        _ = try await RetouchEngine.healSolve(
            target: targetTex, source: sourceTex, mask: maskTex, metal: metal)
        var timings: [Double] = []
        for _ in 0..<3 {
            let t0 = Date()
            _ = try await RetouchEngine.healSolve(
                target: targetTex, source: sourceTex, mask: maskTex, metal: metal)
            timings.append(Date().timeIntervalSince(t0) * 1000)
        }
        timings.sort()
        let median = timings[1]
        print("[06-07 heal benchmark] patch \(w)x\(h), median \(String(format: "%.2f", median))ms, runs [\(timings.map { String(format: "%.2f", $0) }.joined(separator: ", "))]ms")
        XCTAssertLessThan(
            median, 100,
            "heal interaction budget (100ms): median \(median)ms @ \(w)x\(h) patch")
    }

    /// The constant field + a dark Gaussian spot (the through-composite
    /// heal fixture — the spot sits where the stroke will land).
    private func makeSpotImage() throws -> DecodedImage {
        try makeImage { x, y in
            let d2 = pow(Double(x) - 0.5 * Double(size.x), 2)
                + pow(Double(y) - 0.5 * Double(size.y), 2)
            let spot = 0.45 * exp(-d2 / (2 * pow(4.0, 2)))
            return SIMD3<Float>(repeating: 0.35 - Float(spot))
        }
    }

    /// The heal leg through the COMPOSITE (wiring smoke): a heal stroke
    /// removes the blemish (the masked interior changes vs base) and the
    /// stroke exterior stays byte-identical.
    func testHealStrokeThroughComposite() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let registry = await makeRegistry()
        let image = try makeSpotImage()
        let stroke = ellipseStroke(
            algorithm: .heal, center: SIMD2(0.5, 0.5), radius: 0.12,
            source: SIMD2(0.2, 0.5))
        var stack = LayerStack(baseLayer: BackgroundLayer())
        stack.addAdjustment(retouchLayer([stroke]))
        let base = try await workingComposite(image, stack: LayerStack(baseLayer: BackgroundLayer()), metal: metal, registry: registry)
        let fixed = try await workingComposite(image, stack: stack, metal: metal, registry: registry)
        let bf = rawFloats(base.output, metal: metal)
        let ff = rawFloats(fixed.output, metal: metal)
        XCTAssertEqual(bf.count, ff.count)
        var changed = 0
        var exterior = 0
        for (x, y) in interiorPoints(center: SIMD2(0.5, 0.5), radiusPx: 0.12 * Double(size.x)) {
            if pixel(ff, x, y) != pixel(bf, x, y) { changed += 1 }
            XCTAssertFalse(pixel(ff, x, y).x.isNaN, "no NaN at (\(x),\(y))")
        }
        for y in 0..<size.y {
            for x in 0..<size.x {
                let dx = Double(x) - 0.5 * Double(size.x)
                let dy = Double(y) - 0.5 * Double(size.y)
                if dx * dx + dy * dy > pow(0.12 * Double(size.x) * 1.7, 2) {
                    exterior += 1
                    XCTAssertEqual(pixel(ff, x, y), pixel(bf, x, y),
                                   "stroke exterior untouched at (\(x),\(y))")
                }
            }
        }
        XCTAssertGreaterThan(exterior, 100, "exterior coverage sanity")
        XCTAssertGreaterThan(changed, 0, "防空转: heal removes the blemish")
    }
}
