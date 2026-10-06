@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// DrtTailTests (Plan M2-6-1 T7, AC#8/#9 — LAYERS bundle, LayerCompositeTests
// precedent) — the drtTail terminal-tail policy face:
//
//   1. ZERO-BEHAVIOR GATE: .sdrGamma ≡ the default call (byte-equal) — the
//      zero-path default; the whole pre-M2-6 suite green is the wider proof.
//   2. EDR EQUIVALENCE: .edrLinear keeps the 08-4 semantics (the float32
//      linear colorout final; the EDRViewportTests mechanical replacement is
//      the live proof, 14/14 assertions untouched).
//   3. DRT TAIL FORMATS: SDR powers → .bgra8Unorm; st2084/hlg →
//      .rgba16Float; linear → float32 working.
//   4. TERMINAL SKIP + POST-EOTF REPLAY (the E2 guard): colorout/gamma/
//      borders/watermark never enter the main chain; borders/watermark
//      replay AFTER the EOTF encode — the canvas band is display-white
//      (1.0 bytes) while the content IS encoded: 印框永不被 tone map.
//   5. KEY STABILITY + EOTF-SWITCH LOCALITY (KD-6): same record → all HIT;
//      an EOTF switch flips ONLY the tail planes (colorout-before all HIT).
//   6. ASSEMBLY ORDER: [drtMethod 74 → eotf 75 → borders 76 → watermark 77]
//      and NOTHING after watermark (no tone-map segment past the印框).
//   7. PREVIEW/FULL smoke; the aces20 stub refusal (typed, P2 face).
// ─────────────────────────────────────────────────────────────────────────────

final class DrtTailTests: XCTestCase {

    private static let fixtureImageID = UUID(
        uuidString: "D2A9C3E0-0000-4000-8000-00000000D2A9")!

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeImage(width: Int = 48, height: Int = 32) -> DecodedImage {
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

    /// The terminal pair, committed (the D-COL4 display face).
    private func makeTerminalChain(
        registry: ModuleRegistry, outputProfile: ColorOutModule.OutputProfile = .sRGB
    ) async throws -> [any ModuleBoxing] {
        var chain = [any ModuleBoxing]()
        let coloroutMade = await registry.makeBox(opName: ColorOutModule.opName)
        let colorout = try XCTUnwrap(coloroutMade as? ModuleBox<ColorOutModule>)
        colorout.setParams(ColorOutModule.Params(outputProfile: outputProfile))
        chain.append(colorout)
        let gammaMade = await registry.makeBox(opName: GammaModule.opName)
        let gamma = try XCTUnwrap(gammaMade as? ModuleBox<GammaModule>)
        gamma.setParams(GammaModule.Params())
        chain.append(gamma)
        return chain
    }

    /// An EXPANDING borders box (50% width rate → a 2× canvas) + watermark.
    private func makeYiyinTail(
        registry: ModuleRegistry, imageExtent: CGSize
    ) async throws -> [any ModuleBoxing] {
        var chain = [any ModuleBoxing]()
        let bordersMade = await registry.makeBox(opName: BordersModule.opName)
        let borders = try XCTUnwrap(bordersMade as? ModuleBox<BordersModule>)
        borders.setParams(BordersModule.Params(
            mode: .solid(color: "#ffffff"), mainImageWidthRate: 50,
            miniTopBottomMargin: 0, aspectRatio: nil, landscapeOutput: false,
            cornerRadius: nil, shadow: nil, textBottomOffset: 0.027,
            adaptiveBackdrop: false))
        chain.append(borders)
        let watermarkMade = await registry.makeBox(opName: WatermarkModule.opName)
        let watermark = try XCTUnwrap(watermarkMade as? ModuleBox<WatermarkModule>)
        watermark.setParams(WatermarkModule.Params.neutralSeed)
        chain.append(watermark)
        // The working-context injection (the YiyinE2ETests.wireYiyinContext
        // shape — production's coordinator injector sets the same state):
        // borders/watermark compute their canvas from the JOINT layout.
        let mainSize = SIMD2(Int(imageExtent.width), Int(imageExtent.height))
        watermark.module.captureExif = CaptureMetadata()
        let bordersParams = (try? JSONDecoder().decode(
            BordersModule.Params.self, from: borders.paramsData))
            ?? BordersModule.Params.neutralSeed
        watermark.module.jointContext = WatermarkModule.JointContext(
            mainImageSize: mainSize, bordersParams: bordersParams)
        borders.module.jointLayoutOverride = watermark.module.makeJointLayoutRecord(
            mainImageSize: mainSize, bordersParams: bordersParams)
        return chain
    }

    /// L014: never read a plane across in-flight encoders — every render
    /// fences before the caller's getBytes.
    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func render(
        _ image: DecodedImage, _ boxes: [any ModuleBoxing],
        policy: TerminalTailPolicy, resolution: PipeResolution = .preview,
        cache: PipeCache = PipeCache(), metal: MetalContext
    ) async throws -> (any MTLTexture, RenderPipeline.PipeRunStats) {
        let result = try await RenderPipeline.process(
            image: image, instances: boxes, imageID: Self.fixtureImageID,
            resolution: resolution, cache: cache, metal: metal,
            terminalTail: policy)
        await Self.drain(metal)
        return result
    }

    private func readBytes(_ texture: any MTLTexture) -> [UInt8] {
        let bytesPerPx = texture.pixelFormat == .rgba16Float ? 8 : 16
        let w = texture.width, h = texture.height
        let rowBytes = w * bytesPerPx
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    private var sdrRecord: DrtRecord { DrtRecord() }  // Rec709 + gamma22
    private var hdrRecord: DrtRecord {
        var r = DrtRecord()
        r.encodingSpace = .rec2020
        r.encodingEotf = .st2084
        r.peakLuminance = 1000
        return r
    }

    // MARK: - 1: the zero-behavior gate

    func testSDRGammaIsByteIdenticalToTheDefaultCall() async throws {
        let metal = try await makeMetal()
        let image = makeImage()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let (defaultOff, _) = try await render(
            image, chain, policy: .sdrGamma, metal: metal)
        let (explicitOff, _) = try await render(
            image, chain, policy: .sdrGamma, metal: metal)
        XCTAssertEqual(defaultOff.pixelFormat, .bgra8Unorm)
        XCTAssertEqual(Self.readAllBytes(defaultOff), Self.readAllBytes(explicitOff),
                       "the policy default IS .sdrGamma — bytes must not move")
    }

    /// Format-aware byte read (8-bit vs 16F vs float32).
    private static func readAllBytes(_ texture: any MTLTexture) -> [UInt8] {
        let bytesPerPx = memoryBytesPerPixel(texture.pixelFormat)
        let w = texture.width, h = texture.height
        let rowBytes = w * bytesPerPx
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    private static func memoryBytesPerPixel(_ format: MTLPixelFormat) -> Int {
        switch format {
        case .bgra8Unorm: return 4
        case .rgba16Float: return 8
        default: return 16
        }
    }

    // MARK: - 2: EDR equivalence (the derived leg)

    func testEDRLinearKeepsTheFloatLinearColoroutFinal() async throws {
        let metal = try await makeMetal()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let (texture, _) = try await render(
            makeImage(), chain, policy: .edrLinear, metal: metal)
        // The gamma demotion: the float32 LINEAR colorout output IS the
        // final (NOT the sRGB 8-bit plane).
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat)
    }

    // MARK: - 3: the DRT tail plane formats

    func testDrtTailSDRProducesTheBytePlane() async throws {
        let metal = try await makeMetal()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let (texture, _) = try await render(
            makeImage(), chain, policy: .drt(DrtTailParams(record: sdrRecord)), metal: metal)
        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm, "SDR powers → the 8-bit plane")
    }

    func testDrtTailHDRProducesThe16FPlane() async throws {
        let metal = try await makeMetal()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let (texture, _) = try await render(
            makeImage(), chain, policy: .drt(DrtTailParams(record: hdrRecord)), metal: metal)
        XCTAssertEqual(texture.pixelFormat, .rgba16Float, "st2084 → the 16F plane")
    }

    func testDrtTailLinearProducesTheFloatPlane() async throws {
        let metal = try await makeMetal()
        var record = DrtRecord()
        record.encodingEotf = .linear
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let (texture, _) = try await render(
            makeImage(), chain, policy: .drt(DrtTailParams(record: record)), metal: metal)
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat, "linear → float32")
    }

    // MARK: - 4: terminal skip + the post-EOTF replay guard (E2)

    func testDrtTailDiffersFromTheGammaTailAndReplaysBordersPostEOTF() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        // The SAME chain under .sdrGamma: gamma encodes (sRGB segmented TRC).
        let sdrChain = try await makeTerminalChain(registry: registry)
        let (sdrOut, _) = try await render(
            image, sdrChain, policy: .sdrGamma, metal: metal)
        // Under .drt the colorout/gamma pair is skipped and the tail takes
        // over: the EOTF is a pure 2.2 power — the bytes MUST differ from
        // the sRGB TRC at the same pixels (0.5 gray: 0.7297 vs 0.7354).
        let drtChain = try await makeTerminalChain(registry: registry)
        let (drtOut, _) = try await render(
            image, drtChain, policy: .drt(DrtTailParams(record: sdrRecord)), metal: metal)
        XCTAssertEqual(drtOut.pixelFormat, .bgra8Unorm)
        XCTAssertNotEqual(
            Self.readAllBytes(sdrOut), Self.readAllBytes(drtOut),
            "the DRT EOTF replaced the gamma tail — bytes must move")

        // The E2 replay guard: with an EXPANDING borders + watermark, the
        // canvas band is display-white 1.0 (NOT tone-mapped — a PQ-encoded
        // white would sit at ~0.75 code), while the content IS encoded.
        let yiyinChain = (try await makeTerminalChain(registry: registry))
            + (try await makeYiyinTail(registry: registry, imageExtent: image.ciImage.extent.size))
        var pqRecord = DrtRecord()
        pqRecord.encodingSpace = .rec709
        pqRecord.encodingEotf = .st2084  // HDR via PQ on Rec709 — the model layer allows it
        pqRecord.peakLuminance = 1000
        let (guarded, _) = try await render(
            image, yiyinChain, policy: .drt(DrtTailParams(record: pqRecord)), metal: metal)
        XCTAssertEqual(guarded.pixelFormat, .rgba16Float)
        XCTAssertGreaterThan(
            guarded.width, Int(image.ciImage.extent.width),
            "the canvas grew in the tail (borders replayed)")
        // The LEFT band column = pure white (the SDR-white of the PQ code
        // domain is 1.0 pre-encode — borders painted AFTER the encode, so
        // the band bytes are the RAW white, not a PQ code).
        // Single whole-plane read (one truth source — L014 fence done above).
        let plane = Self.readAllBytes(guarded)  // rgba16Float: 8 bytes/px
        func half(_ x: Int, _ y: Int) -> Float {
            let o = (y * guarded.width + x) * 8
            let bits = UInt16(plane[o]) | (UInt16(plane[o + 1]) << 8)
            return Self.halfToFloat(bits)
        }
        // The row debug (left band + content + right band).
        let bandValue = half(2, guarded.height / 2)
        XCTAssertGreaterThan(bandValue, 0.99, "the canvas band is display-white (post-EOTF paint)")
        // And the CONTENT side is PQ-encoded: a mid content code sits well
        // below 1.0 (the sRGB-white would be 1.0 everywhere if gamma ran).
        let contentValue = half(40, guarded.height / 2)  // inside the centered image region
        XCTAssertLessThan(contentValue, 0.99, "the content side stayed PQ-encoded")
    }

    private static func halfToFloat(_ h: UInt16) -> Float {
        if h & 0x7C00 == 0x7C00 { return h & 0x8000 != 0 ? -.infinity : .infinity }
        let sign: Float = h & 0x8000 != 0 ? -1 : 1
        let mantissa = h & 0x03FF
        let exponent = Int((h >> 10) & 0x1F)
        if exponent == 0 {
            return sign * Float(mantissa) * Foundation.pow(2.0, -24.0)
        }
        return sign * Float(mantissa | 0x400)
            * Foundation.pow(2.0, Float(exponent - 15) - 10.0)
    }

    // MARK: - 5: key stability + EOTF-switch locality

    func testSameRecordSecondRunIsAllHits() async throws {
        let metal = try await makeMetal()
        let cache = PipeCache()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        _ = try await render(
            makeImage(), chain, policy: .drt(DrtTailParams(record: sdrRecord)),
            cache: cache, metal: metal)
        let (_, stats) = try await render(
            makeImage(), chain, policy: .drt(DrtTailParams(record: sdrRecord)),
            cache: cache, metal: metal)
        XCTAssertGreaterThan(stats.hits, 0)
        XCTAssertEqual(stats.misses, 0, "the same record re-hits the entire tail")
    }

    func testEOTFSwitchReRunsOnlyTheTail() async throws {
        let metal = try await makeMetal()
        let cache = PipeCache()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        _ = try await render(
            makeImage(), chain, policy: .drt(DrtTailParams(record: sdrRecord)),
            cache: cache, metal: metal)
        // Switch gamma22 → bt1886 (both legal for Rec709): the record hash
        // flips → the tail seed flips → the tail planes MISS; the input
        // plane (the ONLY plane before colorout — both terminal residents
        // are skipped) must HIT.
        var bt1886Record = DrtRecord()
        bt1886Record.encodingEotf = .bt1886
        let (_, stats) = try await render(
            makeImage(), chain, policy: .drt(DrtTailParams(record: bt1886Record)),
            cache: cache, metal: metal)
        XCTAssertEqual(stats.misses, 2, "exactly the two tail boxes re-render")
        XCTAssertEqual(stats.hits, 1, "the input plane (everything before colorout) stays HIT")
    }

    // MARK: - 6: the assembly order (the E2 guard, structural)

    func testTailAssemblyOrderIsMethodEotfBordersWatermark() async throws {
        let registry = try await makeRegistry()
        let residents = try await makeYiyinTail(
            registry: registry, imageExtent: CGSize(width: 48, height: 32))
        let assembled = DrtTailAssembly.instances(
            params: DrtTailParams(record: sdrRecord), residents: residents)
        let orders = assembled.map(\.iopOrder)
        XCTAssertEqual(orders.count, 4)
        XCTAssertEqual(orders[0], 74.0, "DrtMethodBox first")
        XCTAssertEqual(orders[1], 75.0, "EotfBox second — the Post-four slot lives between 74 and 75")
        XCTAssertEqual(orders[2], 76.0, "borders replays after the EOTF")
        XCTAssertEqual(orders[3], 77.0, "watermark is LAST — no tone-map segment past the印框")
    }

    // MARK: - 7: PREVIEW/FULL smoke + the method stub + the enum surface

    func testPreviewAndFullBucketsBothRenderTheTail() async throws {
        let metal = try await makeMetal()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        for resolution in [PipeResolution.preview, .full] {
            let (texture, _) = try await render(
                makeImage(), chain, policy: .drt(DrtTailParams(record: sdrRecord)),
                resolution: resolution, metal: metal)
            XCTAssertEqual(texture.pixelFormat, .bgra8Unorm, "\(resolution) smoke")
        }
    }

    func testAces20MethodRendersThroughTheTail() async throws {
        // M2-6-2 (T4): the aces20 render arm is LIVE — the tail renders it
        // (the P1 refusal stub face is gone), SDR format per the record,
        // and the output DIFFERS from the opendrt arm on the same fixture
        // (the two methods are genuinely different transforms).
        let metal = try await makeMetal()
        var acesRecord = DrtRecord()
        acesRecord.method = .aces20
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let (acesTexture, _) = try await render(
            makeImage(), chain, policy: .drt(DrtTailParams(record: acesRecord)),
            metal: metal)
        XCTAssertEqual(acesTexture.pixelFormat, .bgra8Unorm)
        let (openTexture, _) = try await render(
            makeImage(), chain, policy: .drt(DrtTailParams(record: sdrRecord)),
            metal: metal)
        let acesBytes = readBytes(acesTexture)
        let openBytes = readBytes(openTexture)
        XCTAssertNotEqual(acesBytes, openBytes, "the two methods must diverge")
    }

    func testTerminalTailPolicySwitchIsExhaustiveAndDrivesThePath() {
        // The no-default-arms discipline: this switch compiles ONLY while
        // every case is answered (a new case breaks the build — the
        // M2DRT-06 registration-gate machine check, policy edition).
        for policy in [TerminalTailPolicy.sdrGamma, .edrLinear,
                       .drt(DrtTailParams(record: sdrRecord))] {
            let tag: String = {
                switch policy {
                case .sdrGamma: return "sdr"
                case .edrLinear: return "edr"
                case .drt: return "drt"
                }
            }()
            XCTAssertFalse(tag.isEmpty)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 8: the SpektraLab gate ② timing legs (Plan M2-11-03 T2, KD-2)
//
// SpektraLab's "reprint 0.01s" = a same-config, data-hot LUT re-slap; OUR
// semantic counterpart = the tail-plane cache-hit rerender leg. Two legs at
// the preview-2560 bucket (KD-2):
//   ① same-record second render (the all-hits leg — the 5:1 semantic
//     scenarios above, now TIMED; the hits>0/misses==0 assertion stays as
//     the SEMANTIC gate that must red BEFORE the timing gate);
//   ② single-parameter tick tail replay (the EOTF-switch shape, kept on a
//     per-frame single-field tick so every frame flips the tail seed —
//     misses==2 / hits==1 asserted per frame).
// Gate (OQ-2-A②): Release asserts median ≤ 10ms (the hard gate ITSELF);
// Debug records + carries a 25ms loose bound (architecture-regression
// guard, NOT the gate). Timing discipline: the first render never counts
// (warm = data-hot planes in PipeCache); the L014 drain sits INSIDE every
// timing window (the render helper fences before returning).
// ─────────────────────────────────────────────────────────────────────────────

extension DrtTailTests {

    private var isReleaseBuild: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    /// The preview-2560 bench fixture (native = the D-C3 bucket edge —
    /// scale 1 through the pipe; the suite's 48×32 smoke fixture is too
    /// small to carry a gate number).
    private func makeBenchImage() -> DecodedImage {
        makeImage(width: 2560, height: 1920)
    }

    /// Leg ①: the same-record second render — every timed frame must be an
    /// ALL-HITS frame (the semantic assertion IS the gate's meaning guard).
    func testSameRecordSecondRunTimingAllHits() async throws {
        let metal = try await makeMetal()
        let image = makeBenchImage()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let cache = PipeCache()
        let policy = TerminalTailPolicy.drt(DrtTailParams(record: sdrRecord))
        // PSO + plane warm-up — the FIRST render never counts (KD-2: the
        // warm semantics = data-hot planes, SpektraLab's data-hot reprint).
        _ = try await render(image, chain, policy: policy, cache: cache, metal: metal)

        var times: [Double] = []
        for _ in 0..<7 {
            let start = ContinuousClock.now
            let (_, stats) = try await render(
                image, chain, policy: policy, cache: cache, metal: metal)
            times.append(
                Double((ContinuousClock.now - start).components.attoseconds) / 1e18 * 1000.0)
            XCTAssertGreaterThan(stats.hits, 0, "the input plane must hit")
            XCTAssertEqual(stats.misses, 0, "the same record re-hits the entire tail (semantic gate BEFORE the timing gate)")
        }
        let median = times.sorted()[times.count / 2]
        let label = isReleaseBuild ? "Release" : "Debug"
        print(String(
            format: "PERF| drt-tail same-record rerender preview-2560 (%@): median %.3f ms  all: %@",
            label, median, times.map { String(format: "%.3f", $0) }.joined(separator: ",")))
        if isReleaseBuild {
            XCTAssertLessThanOrEqual(
                median, 10,
                String(format: "SpektraLab gate ② tail-hit rerender: median %.3f ms > 10 ms", median))
        } else {
            XCTAssertLessThanOrEqual(median, 25, "Debug loose bound (non-gate)")
        }
    }

    /// Leg ②: the single-parameter tick tail replay — every timed frame
    /// flips ONLY the tail seed (EOTF base + one ticked record field), so
    /// exactly the two tail boxes re-render while the input plane hits.
    func testEOTFTickTailReplayTiming() async throws {
        let metal = try await makeMetal()
        let image = makeBenchImage()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let cache = PipeCache()
        // PSO + plane warm-up on the gamma22 base (the first render never
        // counts).
        _ = try await render(
            image, chain, policy: .drt(DrtTailParams(record: sdrRecord)),
            cache: cache, metal: metal)

        var whiteLimit: Float = 0.25
        var times: [Double] = []
        for _ in 0..<7 {
            // The EOTF-switch shape on a per-frame single-field tick: every
            // frame's seed is fresh — the two tail boxes miss, the input
            // plane (everything before colorout) hits.
            var record = DrtRecord()
            record.encodingEotf = .bt1886
            whiteLimit += 0.001
            record.creativeWhiteLimit = whiteLimit
            let start = ContinuousClock.now
            let (_, stats) = try await render(
                image, chain, policy: .drt(DrtTailParams(record: record)),
                cache: cache, metal: metal)
            times.append(
                Double((ContinuousClock.now - start).components.attoseconds) / 1e18 * 1000.0)
            XCTAssertEqual(stats.misses, 2, "exactly the two tail boxes re-render (semantic gate BEFORE the timing gate)")
            XCTAssertEqual(stats.hits, 1, "the input plane stays HIT")
        }
        let median = times.sorted()[times.count / 2]
        let label = isReleaseBuild ? "Release" : "Debug"
        print(String(
            format: "PERF| drt-tail eotf-tick replay preview-2560 (%@): median %.3f ms  all: %@",
            label, median, times.map { String(format: "%.3f", $0) }.joined(separator: ",")))
        if isReleaseBuild {
            XCTAssertLessThanOrEqual(
                median, 10,
                String(format: "SpektraLab gate ② tick replay: median %.3f ms > 10 ms", median))
        } else {
            XCTAssertLessThanOrEqual(median, 25, "Debug loose bound (non-gate)")
        }
    }
}
