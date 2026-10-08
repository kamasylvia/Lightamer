@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmLegTests (Plan M3-3-02 T1, KD-1 — LAYERS bundle, DrtTailTests
// precedent) — the film sub-run seam:
//
//   1. SEED FOLD (KD-1): fnv(recordHash ⊕ tag ⊕ solvedPackHash ⊕ upstream)
//      — stable for identical inputs, discriminates every term.
//   2. ZERO PATH: filmTail nil ≡ the pre-M3-3 call (byte-equal, no film
//      planes) — the whole LAYERS/IOPP corpus is the wider gate.
//   3. THE 3×2 MATRIX (checker E4), on cells (terminalTail × film):
//      .sdrGamma+film  → the whole terminal resident set demotes and
//                        replays colorout → borders → watermark → gamma
//                        AFTER the film leg (final bgra8; 印框 post-film).
//      .edrLinear+film → colorout joins the demotion and replays post-film;
//                        gamma NEVER replays (final float32 linear).
//      .drt+film       → zero demotion change; the film output hash is the
//                        DRT tail's upstream seed (signature unchanged).
//      (the off cells are the existing DrtTailTests族 + test 2 here).
//   4. SUB-PLANE FORMAT: the film/replay chain planes stay working float32
//      until the ordinary display-format policy fires (top-is-gamma).
//   5. RE-ENTRY GUARD: the film leg / replay leg pipes never assemble
//      tails of their own (exact planesRendered accounting).
//   6. IDENTITY CARRIER (T1): the T1 film box is a same-format blit — the
//      film-on renders are byte-equal to their film-off counterparts while
//      the CACHE structure proves the seam ran (a film-record change flips
//      the seeds and re-renders exactly the film/replay/tail planes).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmLegTests: XCTestCase {

    private static let fixtureImageID = UUID(
        uuidString: "F11DA7E0-0000-4000-8000-00000000F11D")!

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

    /// An EXPANDING borders box (50% width rate → a 2× canvas) + watermark
    /// (the DrtTailTests.makeYiyinTail shape verbatim).
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

    /// L014: never read a plane across in-flight encoders.
    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private var filmRecord: FilmRecord {
        var r = FilmRecord()
        r.filmStock = "portra_400"
        r.paperStock = "portra_endura"
        return r
    }

    /// The T1 policy carrier: profiles unbound (the T1 identity box consumes
    /// the record only; the T2 leg resolves the pair).
    private func makeFilmTail(record: FilmRecord? = nil) -> FilmTailPolicy {
        let r = record ?? filmRecord
        return FilmTailParams(
            record: r, filmProfile: nil, paperProfile: nil, materialPairHash: 0)
    }

    private func render(
        _ image: DecodedImage, _ boxes: [any ModuleBoxing],
        policy: TerminalTailPolicy = .sdrGamma,
        filmTail: FilmTailPolicy? = nil,
        resolution: PipeResolution = .preview,
        cache: PipeCache = PipeCache(), metal: MetalContext
    ) async throws -> (any MTLTexture, RenderPipeline.PipeRunStats) {
        let result = try await RenderPipeline.process(
            image: image, instances: boxes, imageID: Self.fixtureImageID,
            resolution: resolution, cache: cache, metal: metal,
            terminalTail: policy, filmTail: filmTail)
        await Self.drain(metal)
        return result
    }

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

    // MARK: - 1: the seed fold (KD-1)

    func testSeedFoldIsStableAndDiscriminatesEveryTerm() {
        let params = makeFilmTail()
        let otherRecord = makeFilmTail(record: {
            var r = filmRecord
            r.strength = 0.5
            return r
        }())
        let a = FilmTailAssembly.seed(upstream: 111, params: params, solvedPackHash: 7)
        let b = FilmTailAssembly.seed(upstream: 111, params: params, solvedPackHash: 7)
        XCTAssertEqual(a, b, "identical inputs → identical seed (the determinism face)")
        XCTAssertNotEqual(
            a, FilmTailAssembly.seed(upstream: 222, params: params, solvedPackHash: 7),
            "the upstream term discriminates")
        XCTAssertNotEqual(
            a, FilmTailAssembly.seed(upstream: 111, params: otherRecord, solvedPackHash: 7),
            "the record-hash term discriminates (strength rides the record)")
        XCTAssertNotEqual(
            a, FilmTailAssembly.seed(upstream: 111, params: params, solvedPackHash: 8),
            "the solvedPackHash term discriminates (a solve-only change re-runs the leg)")
        // The replay seed: stable + upstream-discriminating + namespaced.
        XCTAssertEqual(
            FilmTailAssembly.replaySeed(upstream: 5), FilmTailAssembly.replaySeed(upstream: 5))
        XCTAssertNotEqual(
            FilmTailAssembly.replaySeed(upstream: 5), FilmTailAssembly.replaySeed(upstream: 6))
        XCTAssertNotEqual(
            FilmTailAssembly.replaySeed(upstream: a),
            FilmTailAssembly.seed(upstream: a, params: params, solvedPackHash: 7),
            "the replay namespace is distinct from the film seed")
    }

    // MARK: - 2: the zero path

    func testFilmNilIsByteIdenticalToTheLegacyCall() async throws {
        let metal = try await makeMetal()
        let image = makeImage()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let (legacy, _) = try await render(image, chain, metal: metal)
        let (explicitNil, nilStats) = try await render(
            image, chain, filmTail: nil, metal: metal)
        XCTAssertEqual(legacy.pixelFormat, .bgra8Unorm)
        XCTAssertEqual(
            Self.readAllBytes(legacy), Self.readAllBytes(explicitNil),
            "filmTail nil IS the legacy call — bytes must not move")
        XCTAssertEqual(nilStats.planesRendered, 3, "decode + colorout + gamma — no film planes")
    }

    // MARK: - 3: the replay resident filter (the matrix's replay half)

    func testDisplayReplayResidentsPerMatrixRow() async throws {
        let registry = try await makeRegistry()
        let residents = try await makeTerminalChain(registry: registry)
            + (try await makeYiyinTail(
                registry: registry, imageExtent: CGSize(width: 48, height: 32)))
        let sdr = FilmTailAssembly.displayReplayResidents(
            terminalTail: .sdrGamma, residents: residents)
        XCTAssertEqual(
            sdr.map(\.opName),
            [ColorOutModule.opName, DrtMethodBox.tailResidentBordersOpName,
             DrtMethodBox.tailResidentWatermarkOpName, GammaModule.opName],
            ".sdrGamma+film replays the WHOLE terminal set in v50 order")
        let edr = FilmTailAssembly.displayReplayResidents(
            terminalTail: .edrLinear, residents: residents)
        XCTAssertEqual(
            edr.map(\.opName), [ColorOutModule.opName],
            ".edrLinear+film replays colorout ONLY — gamma never replays")
        XCTAssertTrue(
            FilmTailAssembly.displayReplayResidents(
                terminalTail: .drt(DrtTailParams(record: DrtRecord())), residents: residents
            ).isEmpty,
            ".drt+film: the DRT tail owns the replay (zero demotion change)")
    }

    // MARK: - 4: the .sdrGamma + film cell (E4 row 1)

    func testSDRGammaFilmDemotesAndReplaysTheWholeTerminalSet() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let chain = try await makeTerminalChain(registry: registry)
            + (try await makeYiyinTail(
                registry: registry, imageExtent: image.ciImage.extent.size))
        // The film-off face: the terminal residents live in the MAIN chain.
        let (off, offStats) = try await render(image, chain, metal: metal)
        XCTAssertEqual(off.pixelFormat, .bgra8Unorm)
        XCTAssertGreaterThan(off.width, Int(image.ciImage.extent.width), "canvas grew in-chain")
        // The film-on face: the whole set demoted → the film leg consumes
        // the pre-colorout float32 plane → the replay re-runs colorout →
        // borders → watermark → gamma post-film (the T1 identity box keeps
        // the VALUES identical — the STRUCTURE differs).
        let cache = PipeCache()
        let (on, onStats) = try await render(
            image, chain, filmTail: makeFilmTail(), cache: cache, metal: metal)
        XCTAssertEqual(on.pixelFormat, .bgra8Unorm,
                       "the SDR gamma family's tail-format logic owns the final plane")
        XCTAssertEqual(on.width, off.width, "the canvas grew exactly once (in the replay leg)")
        XCTAssertEqual(
            Self.readAllBytes(on), Self.readAllBytes(off),
            "the T1 identity carrier keeps values byte-identical to film-off")
        // Exact store accounting (the SHARED cache sees the sub-run planes;
        // `planesRendered` counts the MAIN pipe only — the established
        // DRT-tail stats semantics): input + film + colorout + borders +
        // watermark + gamma = 6 misses on the cold render.
        XCTAssertEqual(onStats.misses, 6, "input + film box + 4 replay stores")
        XCTAssertEqual(offStats.misses, 5, "input + 4 main-chain residents")
        // Cache locality: the same film record re-hits everything…
        let (_, warm) = try await render(
            image, chain, filmTail: makeFilmTail(), cache: cache, metal: metal)
        XCTAssertEqual(warm.misses, 0, "same record → the film + replay planes all HIT")
        // …a record change flips the film seed AND the replay seed (the
        // replay consumes the film output) — every sub-run plane re-renders.
        var shifted = filmRecord
        shifted.exposureEv = 0.5
        let (_, cold) = try await render(
            image, chain, filmTail: makeFilmTail(record: shifted), cache: cache,
            metal: metal)
        XCTAssertEqual(cold.misses, 5, "film box + four replay residents re-render")
        XCTAssertGreaterThanOrEqual(cold.hits, 1, "the input plane stays HIT")
    }

    // MARK: - 5: the .edrLinear + film cell (E4 row 2)

    func testEDRLinearFilmReplaysColoroutOnlyAndNeverGamma() async throws {
        let metal = try await makeMetal()
        let image = makeImage()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        // Film-off EDR: gamma demoted, the float32 colorout output IS final.
        let (off, _) = try await render(image, chain, policy: .edrLinear, metal: metal)
        XCTAssertEqual(off.pixelFormat, WorkingSpace.pixelFormat)
        // Film-on EDR: colorout JOINS the demotion (film consumes the
        // pre-colorout plane) and replays post-film; gamma stays demoted.
        let (on, onStats) = try await render(
            image, chain, policy: .edrLinear, filmTail: makeFilmTail(), metal: metal)
        XCTAssertEqual(
            on.pixelFormat, WorkingSpace.pixelFormat,
            "the final plane stays float32 linear — no gamma replay (an SDR re-encode would clamp EDR)")
        XCTAssertEqual(
            Self.readAllBytes(on), Self.readAllBytes(off),
            "the T1 identity carrier: colorout-once-post-film ≡ colorout-in-chain")
        XCTAssertEqual(
            onStats.misses, 3,
            "input + film box + colorout replay (gamma nowhere)")
    }

    // MARK: - 6: the .drt + film cell (E4 row 3) — the seed hand-off

    func testDRTFilmStacksAndFeedsTheTailSeed() async throws {
        let metal = try await makeMetal()
        let cache = PipeCache()
        let image = makeImage()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let drtParams = DrtTailParams(record: DrtRecord())
        // Film-off DRT (the M2-6 face, untouched).
        let (off, _) = try await render(
            image, chain, policy: .drt(drtParams), cache: cache, metal: metal)
        XCTAssertEqual(off.pixelFormat, .bgra8Unorm)
        // Film-on DRT: the film output is the tail's INPUT and its hash the
        // tail's upstream seed. The T1 identity box keeps values identical.
        let (on, onStats) = try await render(
            image, chain, policy: .drt(drtParams), filmTail: makeFilmTail(),
            cache: cache, metal: metal)
        XCTAssertEqual(on.pixelFormat, .bgra8Unorm)
        XCTAssertEqual(
            Self.readAllBytes(on), Self.readAllBytes(off),
            "the identity film between the chain and the DRT tail changes no pixels")
        XCTAssertEqual(
            onStats.misses, 3,
            "film box + drtMethod + eotf stores (the input plane HIT — the film-off render in this shared cache already stored it; sub-run base cases never store their external input)")
        // The seed hand-off PROOF: a film-record change flips the film
        // output hash → the DRT tail planes re-render (they keyed on the
        // film hash), while the film-off queue with the same record is all
        // hits.
        var shifted = filmRecord
        shifted.exposureEv = 0.25
        let (_, cold) = try await render(
            image, chain, policy: .drt(drtParams), filmTail: makeFilmTail(record: shifted),
            cache: cache, metal: metal)
        XCTAssertEqual(cold.misses, 3, "film box + drtMethod + eotf re-render")
        XCTAssertGreaterThanOrEqual(cold.hits, 1, "the input plane stays HIT")
        let (_, warmOff) = try await render(
            image, chain, policy: .drt(drtParams), cache: cache, metal: metal)
        XCTAssertEqual(warmOff.misses, 0, "film-off same-record tail re-hits (the control)")
    }

    // MARK: - 7: re-entry guard (exact accounting under the yiyin tail)

    func testFilmLegDoesNotReenterUnderYiyinTail() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()
        let image = makeImage()
        let chain = try await makeTerminalChain(registry: registry)
            + (try await makeYiyinTail(
                registry: registry, imageExtent: image.ciImage.extent.size))
        let (_, stats) = try await render(
            image, chain, filmTail: makeFilmTail(), metal: metal)
        XCTAssertEqual(
            stats.misses, 6,
            "input + film + colorout + borders + watermark + gamma — a re-entering film leg would exceed (the cold-store exact count)")
    }

    // MARK: - 8 (T2): the RESOLVED-materials face — the fused kernel path

    /// The profiles resolved + the histogram seam installed (the registry
    /// populate) → the film leg dispatches `film_subrun` (the fused kernel)
    /// instead of the identity carrier. Gate: the kernel runs (bytes MOVE),
    /// the plane stays working float32, the solve locality holds (a record
    /// change re-runs exactly the film plane).
    func testResolvedMaterialsRenderThroughTheFusedKernel() async throws {
        let metal = try await makeMetal()
        let registry = try await makeRegistry()  // installs FilmStatsSeam
        let store = try FilmMaterialStore(
            profilesDirectory: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/FilmProfiles/profiles"))
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let paper = try XCTUnwrap(store.profile(id: "kodak_portra_endura"))
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let image = makeImage()
        let chain = try await makeTerminalChain(registry: registry)
        let params = FilmTailParams(
            record: filmRecord, filmProfile: film, paperProfile: paper,
            materialPairHash: pairHash)
        // The film-off face (the same chain, byte-comparable).
        let (off, _) = try await render(image, chain, policy: .edrLinear, metal: metal)
        // The film-on face: the fused kernel renders.
        let (on, onStats) = try await render(
            image, chain, policy: .edrLinear, filmTail: params, metal: metal)
        XCTAssertEqual(on.pixelFormat, WorkingSpace.pixelFormat, "the float32 working face")
        XCTAssertNotEqual(
            Self.readAllBytes(on), Self.readAllBytes(off),
            "the film look MOVED the pixels (the fused kernel dispatched)")
        XCTAssertEqual(
            onStats.misses, 3, "input + film box + colorout replay")
        // The solve locality: a strength change flips the record hash (the
        // seed AND the box params) — the film plane + the replay re-render.
        var shifted = filmRecord
        shifted.strength = 0.5
        let (coldTexture, _) = try await render(
            image, chain, policy: .edrLinear,
            filmTail: FilmTailParams(
                record: shifted, filmProfile: film, paperProfile: paper,
                materialPairHash: pairHash),
            metal: metal)
        XCTAssertNotEqual(
            Self.readAllBytes(on), Self.readAllBytes(coldTexture),
            "a strength change moves the render (the strength mix)")
    }

    // MARK: - 9: FULL-resolution smoke (the matrix holds at 100% viewing)

    func testSDRGammaFilmHoldsAtFullResolution() async throws {
        let metal = try await makeMetal()
        let image = makeImage()
        let chain = try await makeTerminalChain(registry: makeRegistry())
        let (off, _) = try await render(
            image, chain, resolution: .full, metal: metal)
        let (on, onStats) = try await render(
            image, chain, filmTail: makeFilmTail(), resolution: .full, metal: metal)
        XCTAssertEqual(on.pixelFormat, .bgra8Unorm)
        XCTAssertEqual(
            Self.readAllBytes(on), Self.readAllBytes(off),
            "the identity carrier holds at FULL (the film/replay planes stayed working float32 — a format slip would garble the bytes)")
        XCTAssertEqual(
            onStats.misses, 3,
            "FULL caches input + finals only: the input, the film box output, the gamma final (the replay intermediates ping-pong uncounted)")
    }
}
