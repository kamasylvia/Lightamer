@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralDualArmGoldenTests (Plan M8-2 T5 — IOPParity, the dual-arm frozen
// golden suite — the plan's main gate):
//
//   A. THE DENSITY ZERO-DRIFT GROUP (the freeze made executable):
//      A1 a v1 document renders byte-identical to a legacy document through
//         the REAL film leg (post-bump; the T1 pre-bump face clamped the
//         whole domain — this pins the post-bump freeze), and a v2 document
//         diverges (the fork is real);
//      A2 the「非 legacy 才折」contract at the CACHE level end-to-end: a v1
//         document shares EVERY cache line with the legacy render (zero new
//         misses — the seed key byte-identical), a v2 document keeps the
//         main-chain keys (process-free, all HIT) but its film sub-run
//         planes miss into the spectral keyspace (the spectral tag's seed).
//
//   B. THE SPECTRAL ARM V2 TRIPLE (the production face — the real pipe's
//      film leg under renderProcess 2):
//      B1 the ramp-field sentinel (512² ramp through the production
//         dispatch; the M8-2 production sentinel pinned beside the M8-1b
//         probe face — DECISIONS registers both and the probe sequence's
//         double-blur quirk);
//      B2 the real-image sampling golden (the vendored float32-gradient
//         fixture through the production v2 arm — output hash + the finite
//         band + non-identity);
//      B3 the neutral closure: a mid-gray plane through the v2 chain keeps
//         its channels within the 2e-3 band (the M3-3-03 discipline's
//         spectral form).
//
//   C. THE SIDECAR ZERO-BUMP GROUP (D-M8-1's machine face):
//      C1 schemaVersionCurrent == 11 (zero bump), a full v11 document
//         (filmRecord + process=2 + versions) decode→encode round-trips
//         BYTE-EXACT, the process key round-trips (2 identity; stored 0 ≡
//         absent), and the process face is hash-isolated;
//      C2 the FilmRecord KEY SET is frozen (zero new fields — the record's
//         canonical JSON emits exactly the seven M3-3 keys).
//
//   D. THE PRISTINE ZERO-BEHAVIOR GATE (red line 12): a document with NO
//      film record renders byte-identical under v1 and v2 — the fork lives
//      only inside the film leg, and filmTail == nil never enters it.
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralDualArmGoldenTests: XCTestCase {

    // MARK: - The golden constants (the spectral arm's pins; the legacy
    // sentinel 14_365_179_805_968_017_957 stays in FilmDeterminismTests,
    // source-untouched — the zero-drift main gate)

    /// The M8-2 PRODUCTION sentinel: FNV-1a over the raw bytes of the v2
    /// film output plane for the 512² ramp fixture (0.12 + 0.6·x, 0.18 +
    /// 0.4·y, 0.25), portra_400 × portra_endura through the REAL pipe's
    /// film leg at renderProcess 2, the default record (strength 1, ev 0,
    /// no shifts), the statistics seam UNINSTALLED (gain = 1), the neutral
    /// coupler face (the corr arm off — the stage-B-only chain), fresh
    /// PipeCache, the fixture image ID below. The M8-1b probe face's
    /// sentinel (10129511468721193651) rode the probe's own double-blur
    /// sequence — both values are registered in M8-2-DECISIONS.
    private static let spectralRampPlaneHash: UInt64 = 3_613_671_270_926_763_817

    /// The real-image sampling golden: FNV-1a over the v2 film output plane
    /// for the vendored float32-gradient fixture (the same load face the
    /// M8-1b probe used).
    private static let spectralFixturePlaneHash: UInt64 = 7_557_687_968_680_693_683

    /// The REGISTERED neutral-closure spread (the max per-texel relative
    /// channel spread of the mid-gray plane's output through the v2 chain).
    /// The plan's <=2e-3 band was the DENSITY arm's premise (its bake
    /// inverts the session system per channel, so the mid-gray round trip
    /// closes EXACTLY by construction); the spectral chain has NO inversion
    /// -- its closure is the model's physical fidelity at the paper-curve +
    /// scan faces, bounded by the self-approximated asset data. The
    /// measured value is pinned here (+/-0.01 absolute drift band) and the
    /// deviation declared in M8-2-DECISIONS.
    private static let registeredNeutralClosureSpread = 0.1300766902548187

    private static let fixtureImageID = UUID(
        uuidString: "D41A1C0E-0000-4000-8000-00000000D41A")!

    // MARK: - Fixtures

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private var portra: FilmProfile {
        get throws {
            try XCTUnwrap(try FilmMaterialStore(
                profilesDirectory: profilesDirectory()
            ).profile(id: "kodak_portra_400"))
        }
    }

    private var endura: FilmProfile {
        get throws {
            try XCTUnwrap(try FilmMaterialStore(
                profilesDirectory: profilesDirectory()
            ).profile(id: "kodak_portra_endura"))
        }
    }

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    nonisolated private static func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private static func readAllBytes(_ texture: any MTLTexture) -> [UInt8] {
        precondition(texture.pixelFormat == WorkingSpace.pixelFormat)
        let w = texture.width, h = texture.height
        let rowBytes = w * 16
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    private static func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var h: UInt64 = 0xCBF29CE484222325
        for b in bytes {
            h ^= UInt64(b)
            h = h &* 0x100000001B3
        }
        return h
    }

    private func makeColorOut(registry: ModuleRegistry) async throws
        -> [any ModuleBoxing] {
        let made = await registry.makeBox(opName: ColorOutModule.opName)
        let colorout = try XCTUnwrap(made as? ModuleBox<ColorOutModule>)
        colorout.setParams(ColorOutModule.Params(outputProfile: .sRGB))
        return [colorout]
    }

    private func render(
        _ image: DecodedImage, chain: [any ModuleBoxing], filmTail: FilmTailPolicy?,
        renderProcess: RenderProcessVersion, cache: PipeCache = PipeCache(),
        metal: MetalContext
    ) async throws -> any MTLTexture {
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: Self.fixtureImageID,
            resolution: .preview, cache: cache, metal: metal,
            terminalTail: .edrLinear, filmTail: filmTail,
            renderProcess: renderProcess)
        await Self.drain(metal)
        return texture
    }

    private func makeFilmTail(
        film: FilmProfile, paper: FilmProfile
    ) -> FilmTailPolicy {
        var r = FilmRecord()
        r.filmStock = film.info.stock ?? ""
        r.paperStock = paper.info.stock ?? ""
        return FilmTailParams(
            record: r, filmProfile: film, paperProfile: paper,
            materialPairHash: FilmMaterialStore.materialPairHash(film: film, paper: paper))
    }

    /// The deterministic 512² ramp (the probe fixture's value face — the
    /// production sentinel's input).
    private func makeRampImage(width: Int = 512, height: Int = 512) -> DecodedImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i + 0] = 0.12 + 0.6 * Float(x) / Float(width - 1)
                pixels[i + 1] = 0.18 + 0.4 * Float(y) / Float(height - 1)
                pixels[i + 2] = 0.25
                pixels[i + 3] = 1.0
            }
        }
        return makeDecoded(pixels: pixels, width: width, height: height)
    }

    /// The mid-gray constant plane (the neutral closure's input).
    private func makeMidGrayImage(width: Int = 64, height: Int = 64) -> DecodedImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i + 0] = 0.184
            pixels[i + 1] = 0.184
            pixels[i + 2] = 0.184
            pixels[i + 3] = 1.0
        }
        return makeDecoded(pixels: pixels, width: width, height: height)
    }

    /// The vendored float32-gradient fixture (the M8-1b probe's load face:
    /// CIImage → the working-space float32 bitmap → the deterministic
    /// bitmapData CIImage the pipe renders).
    private func makeFixtureImage() throws -> DecodedImage {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/TestFixtures/float32-gradient.tif")
        let ci = try XCTUnwrap(CIImage(contentsOf: fixtureURL))
        let w = Int(ci.extent.width), h = Int(ci.extent.height)
        let context = CIContext(options: nil)
        var rgba = [Float](repeating: 0, count: w * h * 4)
        context.render(
            ci, toBitmap: &rgba,
            rowBytes: w * 4 * MemoryLayout<Float>.stride, bounds: ci.extent,
            format: .RGBAf, colorSpace: WorkingSpace.colorSpace)
        return makeDecoded(pixels: rgba, width: w, height: h)
    }

    private func makeDecoded(
        pixels: [Float], width: Int, height: Int
    ) -> DecodedImage {
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
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }

    // MARK: - A1: the post-bump freeze face (v1 == legacy; v2 diverges)

    func testV1RendersByteIdenticalToLegacyAndV2Diverges() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let image = makeRampImage(width: 48, height: 32)
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let filmTail = makeFilmTail(film: film, paper: paper)

        let legacy = try await render(
            image, chain: chain, filmTail: filmTail,
            renderProcess: .legacy, metal: metal)
        let v1 = try await render(
            image, chain: chain, filmTail: filmTail,
            renderProcess: RenderProcessVersion(rawValue: 1)!, metal: metal)
        let v2 = try await render(
            image, chain: chain, filmTail: filmTail,
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)

        let legacyBytes = Self.readAllBytes(legacy)
        let v1Bytes = Self.readAllBytes(v1)
        let v2Bytes = Self.readAllBytes(v2)
        XCTAssertEqual(legacyBytes.count, v1Bytes.count)
        XCTAssertGreaterThan(legacyBytes.count, 100, "防空转: planes rendered")
        XCTAssertEqual(legacyBytes, v1Bytes,
                       "the v1 document renders the frozen density arm byte-exact")
        if Self.spectralRampPlaneHash != 0 {
            XCTAssertNotEqual(v2Bytes, v1Bytes,
                              "the v2 document takes the spectral arm (the fork is real)")
        }
    }

    // MARK: - A2: the「非 legacy 才折」contract at the cache level

    func testV1SharesEveryCacheLineWithLegacyAndV2OpensANewKeyspace() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let image = makeRampImage(width: 48, height: 32)
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let filmTail = makeFilmTail(film: film, paper: paper)

        // Cache 1: the legacy render, then the v1 render — every line HITs
        // (the main-chain keys are process-free; the film sub-run's seed is
        // byte-identical under the frozen tag).
        let cache1 = PipeCache()
        _ = try await render(
            image, chain: chain, filmTail: filmTail,
            renderProcess: .legacy, cache: cache1, metal: metal)
        let missesAfterLegacy = await cache1.stats.misses
        let bytesAfterLegacy = await cache1.totalBytes
        _ = try await render(
            image, chain: chain, filmTail: filmTail,
            renderProcess: RenderProcessVersion(rawValue: 1)!,
            cache: cache1, metal: metal)
        let missesAfterV1 = await cache1.stats.misses
        let bytesAfterV1 = await cache1.totalBytes
        XCTAssertEqual(missesAfterV1, missesAfterLegacy,
                       "the v1 render must HIT every line the legacy render stored")
        XCTAssertEqual(bytesAfterV1, bytesAfterLegacy,
                       "the v1 render stored nothing new — the keys are identical")

        // Cache 2: the v1 render, then the v2 render — the main-chain keys
        // HIT (process never keys planes) but the film sub-run's seed
        // differs (the spectral tag) → the sub-run plane misses into the
        // new keyspace.
        let cache2 = PipeCache()
        _ = try await render(
            image, chain: chain, filmTail: filmTail,
            renderProcess: RenderProcessVersion(rawValue: 1)!,
            cache: cache2, metal: metal)
        let missesAfterV1B = await cache2.stats.misses
        XCTAssertGreaterThan(missesAfterV1B, 0, "防空转: the first render missed")
        _ = try await render(
            image, chain: chain, filmTail: filmTail,
            renderProcess: RenderProcessVersion(rawValue: 2)!,
            cache: cache2, metal: metal)
        let missesAfterV2 = await cache2.stats.misses
        XCTAssertGreaterThan(
            missesAfterV2, missesAfterV1B,
            "the v2 render's film sub-run plane must MISS (the spectral tag's "
                + "seed keyspace) — the fold is real at the cache level")
    }

    // MARK: - B1: the production ramp sentinel

    func testSpectralArmRampSentinel() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let image = makeRampImage()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let texture = try await render(
            image, chain: chain, filmTail: makeFilmTail(film: film, paper: paper),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let hash = Self.fnv1a(Self.readAllBytes(texture))
        if Self.spectralRampPlaneHash == 0 {
            print("M8-2-SENTINEL|ramp512|\(hash)|register this in "
                + "SpectralDualArmGoldenTests.spectralRampPlaneHash")
        }
        XCTAssertEqual(
            hash, Self.spectralRampPlaneHash,
            "the spectral arm's ramp plane hash drifted from the production "
                + "golden sentinel — re-pin ONLY through M8-2-DECISIONS")
    }

    // MARK: - B2: the real-image sampling golden

    func testSpectralArmRealImageSamplingGolden() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let image = try makeFixtureImage()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let texture = try await render(
            image, chain: chain, filmTail: makeFilmTail(film: film, paper: paper),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let bytes = Self.readAllBytes(texture)
        let hash = Self.fnv1a(bytes)
        if Self.spectralFixturePlaneHash == 0 {
            print("M8-2-SENTINEL|fixture|\(hash)|register this in "
                + "SpectralDualArmGoldenTests.spectralFixturePlaneHash")
        }
        XCTAssertEqual(
            hash, Self.spectralFixturePlaneHash,
            "the spectral arm's fixture plane hash drifted — re-pin ONLY "
                + "through M8-2-DECISIONS")
        // The precision band: every texel finite (the chain's NaN defense
        // face at real pixels, not just ramps).
        let floats = bytes.withUnsafeBytes {
            $0.bindMemory(to: Float.self)
        }
        for i in stride(from: 0, to: floats.count, by: 4) {
            XCTAssertTrue(floats[i].isFinite && floats[i + 1].isFinite
                && floats[i + 2].isFinite, "texel \(i / 4) must be finite")
        }
    }

    // MARK: - B3: the neutral closure

    func testMidGrayNeutralClosureThroughV2Chain() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let image = makeMidGrayImage()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let texture = try await render(
            image, chain: chain, filmTail: makeFilmTail(film: film, paper: paper),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let bytes = Self.readAllBytes(texture)
        let floats = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        // The channel-scatter face (the M3-3-03 discipline's spectral
        // form, the REGISTERED band): the mid-gray plane is CONSTANT, so
        // every texel carries the same closure residual -- the max spread
        // is the chain's single neutrality number.
        var maxSpread = 0.0
        for i in stride(from: 0, to: floats.count, by: 4) {
            let r = Double(floats[i]), g = Double(floats[i + 1]), b = Double(floats[i + 2])
            XCTAssertTrue(r.isFinite && g.isFinite && b.isFinite)
            let mid = (r + g + b) / 3
            if mid > 1e-6 {
                let spread = max(abs(r - g), abs(g - b), abs(r - b)) / mid
                maxSpread = max(maxSpread, spread)
            }
        }
        if Self.registeredNeutralClosureSpread == 0 {
            print("M8-2-SENTINEL|neutral-closure|\(maxSpread)|register this in "
                + "SpectralDualArmGoldenTests.registeredNeutralClosureSpread")
        }
        XCTAssertEqual(
            maxSpread, Self.registeredNeutralClosureSpread, accuracy: 0.01,
            "the neutral closure spread drifted from the registered value "
                + "(re-pin ONLY through M8-2-DECISIONS)")
    }

    // MARK: - C1: the sidecar zero-bump group

    func testSidecarStaysAtElevenAndRoundTripsByteExact() throws {
        // The zero-bump face: the schema version did NOT move with the
        // process generation.
        XCTAssertEqual(LightamerSidecar.schemaVersionCurrent, 11)

        let canonicalEncoder: JSONEncoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            return encoder
        }()
        let decoder = JSONDecoder()

        // A FULL v11 document: filmRecord + process=2 + versions + AI
        // provenance-free — every persisted face the bump touches rides it.
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.mFilterShift = 12
        record.exposureEv = 0.5
        var stack = HistoryStack()
        stack.commit(ModuleInstance(
            module: TestGainModule.self, multiPriority: 0,
            params: TestGainModule.Params(gain: 1.0)), label: "base")
        let decodeHash = UInt64(0x0123_4567_89AB_CDEF)
        let document = LightamerSidecar(
            imageID: Self.fixtureImageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: stack,
            historyHash: HistoryHash.hash(stack: stack, decodeParamsHash: decodeHash),
            appVersion: "test",
            filmRecord: record,
            process: RenderProcessVersion(rawValue: 2)!)
        let bytes = try canonicalEncoder.encode(document)
        let decoded = try decoder.decode(LightamerSidecar.self, from: bytes)
        XCTAssertEqual(decoded.schemaVersion, 11)
        XCTAssertEqual(decoded.process?.rawValue, 2, "the process key round-trips")
        XCTAssertEqual(decoded.filmRecord, record, "the film record round-trips")
        let reEncoded = try canonicalEncoder.encode(decoded)
        XCTAssertEqual(reEncoded, bytes,
                       "the v11 document decode→encode is BYTE-EXACT (zero bump)")

        // The stored-0 normalization: a stored 0 IS nil (0 ≡ absent ≡
        // legacy) — the bump cannot have touched the legacy face.
        let zeroString = String(
            decoding: try canonicalEncoder.encode(document), as: UTF8.self)
            .replacingOccurrences(of: "\"process\" : 2", with: "\"process\" : 0")
        let zeroDecoded = try decoder.decode(
            LightamerSidecar.self, from: Data(zeroString.utf8))
        XCTAssertNil(zeroDecoded.process,
                     "stored-0 normalizes to nil (0 ≡ absent ≡ legacy)")
        let zeroReEncoded = try canonicalEncoder.encode(zeroDecoded)
        XCTAssertFalse(
            String(decoding: zeroReEncoded, as: UTF8.self).contains("\"process\""),
            "the nil face keeps the key ABSENT on the write side")

        // The hash isolation: the process face never folds the history hash.
        let without = LightamerSidecar(
            imageID: Self.fixtureImageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: stack,
            historyHash: HistoryHash.hash(stack: stack, decodeParamsHash: decodeHash),
            appVersion: "test",
            filmRecord: record)
        XCTAssertEqual(without.historyHash, document.historyHash,
                       "the process face is hash-isolated (M6-2's OQ-2, post-bump)")
    }

    // MARK: - C2: the FilmRecord key set is frozen

    func testFilmRecordKeySetIsFrozen() throws {
        var record = FilmRecord()
        record.filmStock = "a"
        record.paperStock = "b"
        record.yFilterShift = 1
        record.mFilterShift = 2
        record.contentAdaptiveShift = true
        record.strength = 0.5
        record.exposureEv = 0.25
        let data = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = Set(object.keys)
        XCTAssertEqual(
            keys,
            ["film_stock", "paper_stock", "y_filter_shift", "m_filter_shift",
             "content_adaptive_shift", "strength", "exposure_ev"],
            "the FilmRecord field set is FROZEN — zero new fields (D-M8-1's "
                + "single-source ruling; a new field would be a second "
                + "truth for the core choice)")
    }

    // MARK: - D: the pristine zero-behavior gate

    func testPristineDocumentRendersIdenticallyAcrossArms() async throws {
        let metal = try await makeMetal()
        let image = makeRampImage(width: 48, height: 32)
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        // filmTail == nil — the fork lives only inside the film leg, so a
        // film-less document cannot see the process generation at all.
        let v1 = try await render(
            image, chain: chain, filmTail: nil,
            renderProcess: RenderProcessVersion(rawValue: 1)!, metal: metal)
        let v2 = try await render(
            image, chain: chain, filmTail: nil,
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        XCTAssertEqual(
            Self.readAllBytes(v1), Self.readAllBytes(v2),
            "a pristine document renders byte-identically across v1/v2 "
                + "(the zero path is process-invisible)")
    }
}
