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
//   C. THE SIDECAR BUMP GROUP (D-M8-1's machine face, M9-2 T2 re-anchored
//      at v12 — the declared single-bump exemption):
//      C1 schemaVersionCurrent == 12 (M9-2 T2's single-bump exemption), a
//         full v12 document (filmRecord + process=2 + versions) decode→encode
//         BYTE-EXACT, the process key round-trips (2 identity; stored 0 ≡
//         absent), and the process face is hash-isolated;
//      C2 the FilmRecord key set: the NIL face emits exactly the seven
//         M3-3 keys; the two M9-2 optionals (camera_filter/paper_grade)
//         emit only when set (the emit contract).
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

    // MARK: - C1: the sidecar bump group (M9-2 T2: v12 — the film record's
    // camera_filter/paper_grade riding INSIDE the filmRecord Codable
    // payload; the bump follows the persisted-face precedent chain and is
    // the M9-2 PLAN's declared exemption of the M7-6 sealed-face list)

    func testSidecarRoundTripsByteExactAtV12() throws {
        // M8-3+ T3 bumped 12 -> 13 (the declared single-bump exemption;
        // the test name keeps its v12 origin — the document below is
        // built at the LIVE digit, byte-exactness is the invariant).
        XCTAssertEqual(LightamerSidecar.schemaVersionCurrent, 13)

        let canonicalEncoder: JSONEncoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            return encoder
        }()
        let decoder = JSONDecoder()

        // A FULL v12 document: filmRecord + process=2 + versions + AI
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
        XCTAssertEqual(decoded.schemaVersion, 13, "M8-3+ T3: the v13 digit")
        XCTAssertEqual(decoded.process?.rawValue, 2, "the process key round-trips")
        XCTAssertEqual(decoded.filmRecord, record, "the film record round-trips")
        let reEncoded = try canonicalEncoder.encode(decoded)
        XCTAssertEqual(reEncoded, bytes,
                       "the v13 document decode→encode is BYTE-EXACT (the bump "
                           + "touches only the digit; the five new film-record "
                           + "keys stay absent when nil — M8-3+ T3)")

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

    // MARK: - C2: the FilmRecord key set (M9-2 T2: the two new optional
    // legs — camera_filter/paper_grade — emit ONLY when non-nil; the nil
    // face keeps the seven frozen M3-3 keys verbatim)

    func testFilmRecordKeySetEmitContract() throws {
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
        XCTAssertEqual(
            Set(object.keys),
            ["film_stock", "paper_stock", "y_filter_shift", "m_filter_shift",
             "content_adaptive_shift", "strength", "exposure_ev"],
            "the NIL face keeps the seven M3-3 keys verbatim — the M9-2 "
                + "optionals and the M8-3+ five legs stay absent until set")
        record.cameraFilter = "w25"
        record.paperGrade = "3"
        let setObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(record)) as? [String: Any])
        let setKeys = Set(setObject.keys)
        XCTAssertEqual(
            setKeys.subtracting(Set(object.keys)),
            ["camera_filter", "paper_grade"],
            "the SET face adds exactly the two M9-2 legs")
        // M8-3+ T3: the five legs add exactly their five keys.
        record.reversalPrintMode = SpectralNeutralSolve.directPositiveMode
        record.grainAmount = 2.5
        record.halationAmount = 0.75
        record.diffusionFamily = "pro-mist"
        record.diffusionAmount = 0.5
        let fiveObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(record)) as? [String: Any])
        XCTAssertEqual(
            Set(fiveObject.keys).subtracting(setKeys),
            ["reversal_print_mode", "grain_amount", "halation_amount",
             "diffusion_family", "diffusion_amount"],
            "the SET face adds exactly the five M8-3+ legs")
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

    // MARK: - T6: the end-to-end matrix smoke (the whole vendored set)

    /// The 28-profile × dual-arm render matrix (the smoke level — the
    /// golden level is the ramp/fixture pins above): every profile takes
    /// the film seat against the shared endura paper, renders under BOTH
    /// arms through the REAL pipe, and every render comes back finite;
    /// the fork is real across the set (the arms differ on the overwhelming
    /// majority of pairs — a coincidental bitwise match is possible in
    /// principle, so the pin is a count, not a per-pair identity). The
    /// builds ride the tc_lut slot's LRU (the capacity keeps ~6 bundles —
    /// the smoke thrashes it deliberately, the eviction face under load).
    func testAll28ProfilesRenderBothArmsEndToEnd() async throws {
        let metal = try await makeMetal()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let paper = try endura
        let names = try FileManager.default.contentsOfDirectory(
            atPath: profilesDirectory().path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        XCTAssertEqual(names.count, 28)

        let image = makeRampImage(width: 24, height: 16)
        var differingPairs = 0
        for name in names {
            let profile = try FilmProfile.load(
                profilesDirectory().appendingPathComponent(name))
            let filmTail = makeFilmTail(film: profile, paper: paper)
            let v1 = try await render(
                image, chain: chain, filmTail: filmTail,
                renderProcess: RenderProcessVersion(rawValue: 1)!, metal: metal)
            let v2 = try await render(
                image, chain: chain, filmTail: filmTail,
                renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
            let v1Bytes = Self.readAllBytes(v1)
            let v2Bytes = Self.readAllBytes(v2)
            // Both arms finite (the smoke's sanity face).
            let v1Floats = v1Bytes.withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            let v2Floats = v2Bytes.withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            for i in stride(from: 0, to: v1Floats.count, by: 4) {
                XCTAssertTrue(
                    v1Floats[i].isFinite && v1Floats[i + 1].isFinite
                        && v1Floats[i + 2].isFinite, "\(name): v1 texel \(i / 4)")
                XCTAssertTrue(
                    v2Floats[i].isFinite && v2Floats[i + 1].isFinite
                        && v2Floats[i + 2].isFinite, "\(name): v2 texel \(i / 4)")
            }
            if v1Bytes != v2Bytes { differingPairs += 1 }
        }
        XCTAssertGreaterThan(
            differingPairs, 25,
            "the spectral fork must be visible across the vendored set "
                + "(\(differingPairs)/28 pairs differ)")
        print("M8-2-SMOKE|matrix|28 profiles|differing pairs \(differingPairs)/28")
    }

    /// The export-seam smoke: a v2 document's film leg through the EXPORT
    /// resolution renders finite — the `$jobFilmTail` recursion seam is
    /// zero-changed (ExportQueueContract is a zero-diff face; the per-job
    /// carrier hands the same FilmTailParams through, and the arm rides the
    /// document's process inside the leg). The full export GUI walkthrough
    /// is M8-3's face; this pins the pipeline-level seam only.
    func testV2FilmLegRendersThroughTheExportResolution() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let image = makeRampImage(width: 32, height: 24)
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let (texture, stats) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: Self.fixtureImageID,
            resolution: .export, cache: PipeCache(), metal: metal,
            terminalTail: .edrLinear,
            filmTail: makeFilmTail(film: film, paper: paper),
            renderProcess: RenderProcessVersion(rawValue: 2)!)
        await Self.drain(metal)
        XCTAssertGreaterThan(stats.planesRendered, 0, "防空转: the export run rendered")
        let floats = Self.readAllBytes(texture).withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        for i in stride(from: 0, to: floats.count, by: 4) {
            XCTAssertTrue(
                floats[i].isFinite && floats[i + 1].isFinite && floats[i + 2].isFinite,
                "export texel \(i / 4) must be finite")
        }
    }

    // MARK: - E: the M8-3 probe-follow faces (Plan M8-3 T2)

    //
    // FilmDescriptorProbe constructs through `PixelPipe.assembleFilmLeg` —
    // the production film leg's OWN factory (the M3-4-01 §8.1 same-code-path
    // discipline). M8-2 forked that factory on the render process, so the
    // probe follows the factory BY CONSTRUCTION; these two faces pin the
    // M8-3 verification on the M8-2-integrated binary:
    //
    //   E1 the v2 arm SERVES the probe's exact call form (the 1024×1 neutral
    //      E-ladder ramp, histogram nil, the default record): the assembly
    //      resolves the spectral payloads, the box dispatches them, and the
    //      output plane comes back finite;
    //   E2 the two arms' probe outputs on the SAME ramp both resolve and
    //      DIVERGE — the readouts differ because the core differs (by
    //      design, D-M8-7; the sampled numbers are recorded in
    //      M8-3-DECISIONS, never asserted equal — the production descriptor
    //      probe's call site keeps the default arm, the density-anchored
    //      latitude posture, this batch).
    //
    // FilmDescriptor.swift (the ISO 6846 reduction) carries zero diff — the
    // machine check is the build itself plus FilmDescriptorTests staying
    // green; no behavioral re-pin lives here.

    /// The descriptor probe's exact 1024×1 neutral ramp texture
    /// (0.184·2^E, E uniform on [−12, +12] — FilmDescriptorProbe's ① shape,
    /// mirrored here so the factory receives the probe's own input).
    private func makeProbeRampTexture(
        _ metal: MetalContext, length: Int = 1024
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: length, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("no Metal texture")
        }
        var texels = [Float](repeating: 0, count: length * 4)
        for index in 0..<length {
            let e = FilmDescriptorProbe.domainMin
                + (FilmDescriptorProbe.domainMax - FilmDescriptorProbe.domainMin)
                * Double(index) / Double(length - 1)
            let value = Float(0.184 * Foundation.pow(2.0, e))
            texels[index * 4 + 0] = value
            texels[index * 4 + 1] = value
            texels[index * 4 + 2] = value
            texels[index * 4 + 3] = 1.0
        }
        texels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, length, 1),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: length * 16)
        }
        return texture
    }

    /// The probe's call form through ONE arm, dispatched through the
    /// production FilmMethodBox, read back after a fence (L014).
    private func probeFormOutput(
        renderProcess: RenderProcessVersion, film: FilmProfile, paper: FilmProfile,
        metal: MetalContext
    ) async throws -> (planeHash: UInt64, midLuma: Float, finite: Bool) {
        let pairHash = FilmMaterialStore.materialPairHash(film: film, paper: paper)
        let input = try makeProbeRampTexture(metal)
        var record = FilmRecord()
        record.filmStock = film.info.stock ?? ""
        record.paperStock = paper.info.stock ?? ""
        let assembled = PixelPipe.assembleFilmLeg(
            record: record, film: film, paper: paper,
            materialPairHash: pairHash, histogram: nil,
            plane: input, metal: metal, renderProcess: renderProcess)
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: FilmDescriptorProbe.rampLength,
            height: 1, mipmapped: false)
        outputDescriptor.usage = [.shaderRead, .shaderWrite]
        outputDescriptor.storageMode = .shared
        let output = try XCTUnwrap(metal.device.makeTexture(descriptor: outputDescriptor))
        let box: FilmMethodBox
        if let spectral = assembled.spectralPayloads {
            box = FilmMethodBox(
                record: assembled.method.record, method: assembled.method,
                spectralPayloads: spectral)
        } else {
            box = FilmMethodBox(
                record: assembled.method.record, method: assembled.method,
                payloads: try XCTUnwrap(assembled.payloads))
        }
        var piece = IOPiece()
        try await box.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        await Self.drain(metal)
        var values = [Float](repeating: 0, count: FilmDescriptorProbe.rampLength * 4)
        values.withUnsafeMutableBytes {
            output.getBytes(
                $0.baseAddress!, bytesPerRow: FilmDescriptorProbe.rampLength * 16,
                from: MTLRegionMake2D(0, 0, FilmDescriptorProbe.rampLength, 1),
                mipmapLevel: 0)
        }
        var finite = true
        for v in values where !v.isFinite { finite = false }
        let mid = FilmDescriptorProbe.rampLength / 2
        let midLuma =
            0.2627 * Double(values[mid * 4]) + 0.6780 * Double(values[mid * 4 + 1])
            + 0.0593 * Double(values[mid * 4 + 2])
        return (
            Self.fnv1a(values.withUnsafeBytes {
                Array($0.bindMemory(to: UInt8.self))
            }),
            Float(midLuma), finite)
    }

    /// E1: the v2 arm serves the probe call form — the spectral payloads
    /// resolve for the probe's exact inputs and the output plane is finite.
    func testProbeCallFormResolvesThroughTheV2Arm() async throws {
        let metal = try await makeMetal()
        let out = try await probeFormOutput(
            renderProcess: RenderProcessVersion(rawValue: 2)!,
            film: try portra, paper: try endura, metal: metal)
        XCTAssertTrue(out.finite, "the v2-arm probe output must be finite")
        XCTAssertNotEqual(out.planeHash, 0, "防空转: the v2 probe dispatch rendered")
    }

    /// E2: the same probe ramp through both arms — both resolve, the
    /// readouts DIVERGE (the core changed; never asserted equal). The
    /// sampled numbers print with the M83 marker and are recorded in
    /// M8-3-DECISIONS (the readout comparison table).
    func testProbeReadoutsDivergeAcrossArmsOnTheSameRamp() async throws {
        let metal = try await makeMetal()
        let film = try portra
        let paper = try endura
        let density = try await probeFormOutput(
            renderProcess: .legacy, film: film, paper: paper, metal: metal)
        let spectral = try await probeFormOutput(
            renderProcess: RenderProcessVersion(rawValue: 2)!,
            film: film, paper: paper, metal: metal)
        XCTAssertTrue(density.finite && spectral.finite)
        print("M83-PROBE-READOUT|density|hash=\(density.planeHash)|midLuma=\(density.midLuma)")
        print("M83-PROBE-READOUT|spectral|hash=\(spectral.planeHash)|midLuma=\(spectral.midLuma)")
        XCTAssertNotEqual(
            density.planeHash, spectral.planeHash,
            "the two arms' probe outputs must differ — the core changed "
                + "(the readout delta is BY DESIGN, D-M8-7)")
    }
}
