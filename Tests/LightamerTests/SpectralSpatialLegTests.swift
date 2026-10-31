@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralSpatialLegTests (Plan M8-3+ T5 — IOPParity; T7 extends the smoke)
// — the pre-leg's math + off-identity faces (the halation/diffusion leg's
// contract):
//
//   1. THE HALATION MATH: the bounce σ√k + the decay weights + the still
//      baseline transcription pins (verbatim values) + the s clamp.
//   2. THE DIFFUSION BANK: ≤ 11 components + the moment match (σ = λ√3)
//      + the p_s curve pins + the four family ids verbatim.
//   3. THE LEG OFF-IDENTITY: nil legs render bit-identically to the
//      pre-T5 chain (the full-pipe face); amount-0 legs ditto.
//   4. THE LEG ON-FACE: armed legs move the render + re-render
//      bit-identically (deterministic) + finite everywhere.
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralSpatialLegTests: XCTestCase {

    private static let fixtureImageID = UUID(
        uuidString: "B2C3D4E5-2B3C-4D5E-6F7A-8B9C0D1E2F3A")!

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
        film: FilmProfile, paper: FilmProfile,
        halationAmount: Float? = nil, diffusionFamily: String? = nil,
        diffusionAmount: Float? = nil, grainAmount: Float? = nil
    ) -> FilmTailPolicy {
        var r = FilmRecord()
        r.filmStock = film.info.stock ?? ""
        r.paperStock = paper.info.stock ?? ""
        r.halationAmount = halationAmount
        r.diffusionFamily = diffusionFamily
        r.diffusionAmount = diffusionAmount
        r.grainAmount = grainAmount
        return FilmTailParams(
            record: r, filmProfile: film, paperProfile: paper,
            materialPairHash: FilmMaterialStore.materialPairHash(film: film, paper: paper))
    }

    private func makeRampImage(width: Int = 64, height: Int = 48) -> DecodedImage {
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

    // MARK: - 1: the halation math

    func testHalationStillBaselineTranscription() throws {
        let base = SpectralSpatialTables.stillBaseline
        XCTAssertEqual(base.strength.x, 0.05, accuracy: 1e-12)
        XCTAssertEqual(base.strength.y, 0.015, accuracy: 1e-12)
        XCTAssertEqual(base.strength.z, 0.0, accuracy: 1e-12)
        XCTAssertEqual(base.firstSigmaUm, 65.0, accuracy: 1e-12)
        XCTAssertEqual(base.scatterCore.x, 2.2, accuracy: 1e-12)
        XCTAssertEqual(base.scatterTail.z, 9.1, accuracy: 1e-12)
        XCTAssertEqual(base.scatterTailWeight.y, 0.65, accuracy: 1e-12)
        XCTAssertEqual(SpectralSpatialTables.tailAmps[1], 0.6496,
                       accuracy: 1e-12)
        XCTAssertEqual(SpectralSpatialTables.tailRatios[2], 2.7684,
                       accuracy: 1e-12)
        // The bounce σ√k + the decay weights.
        XCTAssertEqual(
            SpectralSpatialTables.bounceSigma(firstSigma: 65, bounce: 2),
            65 * 2.0.squareRoot(), accuracy: 1e-9)
        let decay = SpectralSpatialTables.bounceDecay
        XCTAssertEqual(decay[0], 1.0 / 1.75, accuracy: 1e-9)
        XCTAssertEqual(decay[1], 0.5 / 1.75, accuracy: 1e-9)
        XCTAssertEqual(decay[2], 0.25 / 1.75, accuracy: 1e-9)
    }

    // MARK: - 2: the diffusion bank

    func testDiffusionBankShapeAndMomentMatch() throws {
        XCTAssertEqual(
            SpectralSpatialTables.families.map(\.id),
            ["black-pro-mist", "glimmerglass", "pro-mist", "cinebloom"])
        let bpm = try XCTUnwrap(SpectralSpatialTables.family(
            id: "black-pro-mist"))
        XCTAssertNil(SpectralSpatialTables.family(id: "no-such-family"))
        let bank = SpectralSpatialTables.bank(family: bpm)
        // Core 2 + halo 3 + bloom 4 = 9 ≤ 11.
        XCTAssertEqual(bank.count, 9)
        // The moment match (σ = λ√3 — the first core component: λ =
        // 16/1.5..16·1.5 geometric pair, σ = λ√3).
        let group = SpectralSpatialTables.expandGroup(
            bpm.core, isBloom: false)
        XCTAssertEqual(group.count, 2)
        XCTAssertEqual(
            bank[0].sigmaUm, group[0].lambdaUm * 3.0.squareRoot(),
            accuracy: 1e-9)
        // The p_s curve pins (strength 1.0 → frac 0.55 × gain 0.75).
        XCTAssertEqual(
            SpectralSpatialTables.scatterFraction(
                strength: 1.0, family: bpm),
            0.55 * 0.75, accuracy: 1e-12)
        XCTAssertEqual(
            SpectralSpatialTables.scatterFraction(
                strength: 0.0, family: bpm), 0.0)
        // The group weights sum to 1 (energy-conserving bank).
        XCTAssertEqual(
            bpm.weightCore + bpm.weightHalo + bpm.weightBloom, 1.0,
            accuracy: 1e-12)
    }

    // MARK: - 3: the leg off-identity (nil + 0)

    func testNilLegsRenderBitIdentically() async throws {
        let metal = try await makeMetal()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let image = makeRampImage()
        let film = try portra
        let paper = try endura
        let bare = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(film: film, paper: paper),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let bareBytes = Self.readAllBytes(bare)
        // Explicit nil legs (the record face's all-nil twin).
        let explicit = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(
                film: film, paper: paper, halationAmount: nil,
                diffusionFamily: nil, diffusionAmount: nil),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        XCTAssertEqual(Self.readAllBytes(explicit), bareBytes)
        // Amount-0 legs (the on-identity face).
        let zero = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(
                film: film, paper: paper, halationAmount: 0.0,
                diffusionFamily: "black-pro-mist", diffusionAmount: 0.0),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        XCTAssertEqual(
            Self.readAllBytes(zero), bareBytes,
            "amount-0 legs are the on-identity")
        // Family-absent amount (the priority face — ignored).
        let orphan = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(
                film: film, paper: paper, diffusionAmount: 0.5),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        XCTAssertEqual(
            Self.readAllBytes(orphan), bareBytes,
            "family-absent amount is ignored (the priority face)")
    }

    // MARK: - 4: the leg on-face (moves + deterministic + finite)

    func testArmedLegsMoveAndReRenderBitIdentically() async throws {
        let metal = try await makeMetal()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let image = makeRampImage()
        let film = try portra
        let paper = try endura
        let off = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(film: film, paper: paper),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let offBytes = Self.readAllBytes(off)
        // Halation armed.
        let hal1 = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(
                film: film, paper: paper, halationAmount: 1.0),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let hal1Bytes = Self.readAllBytes(hal1)
        XCTAssertNotEqual(hal1Bytes, offBytes, "halation moves the render")
        let hal2 = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(
                film: film, paper: paper, halationAmount: 1.0),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        XCTAssertEqual(
            Self.readAllBytes(hal2), hal1Bytes,
            "halation re-renders bit-identically")
        // Diffusion armed (family + default amount).
        let dif1 = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(
                film: film, paper: paper,
                diffusionFamily: "black-pro-mist"),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let dif1Bytes = Self.readAllBytes(dif1)
        XCTAssertNotEqual(dif1Bytes, offBytes, "diffusion moves the render")
        let floats = dif1Bytes.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        for i in stride(from: 0, to: floats.count, by: 4) {
            XCTAssertTrue(
                floats[i].isFinite && floats[i + 1].isFinite
                    && floats[i + 2].isFinite, "texel \(i / 4) finite")
        }
    }

    // MARK: - T7: the end-to-end smoke (the batch closeout face)

    func testAllOffSampleRendersFiniteAcrossPairs() async throws {
        // 28-pair × all-off sample (4 corners: portra/endura,
        // C200/crystal, ektar/ultra, velvia/endura) — every render
        // finite (the batch's breadth smoke).
        let metal = try await makeMetal()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let image = makeRampImage(width: 24, height: 16)
        let store = try FilmMaterialStore(
            profilesDirectory: profilesDirectory())
        let pairs = [
            ("kodak_portra_400", "kodak_portra_endura"),
            ("fujifilm_c200", "fujifilm_crystal_archive_typeii"),
            ("kodak_ektar_100", "kodak_ultra_endura"),
            ("fujifilm_velvia_100", "kodak_portra_endura"),
        ]
        for (filmId, paperId) in pairs {
            let film = try XCTUnwrap(store.profile(id: filmId))
            let paper = try XCTUnwrap(store.profile(id: paperId))
            let texture = try await render(
                image, chain: chain,
                filmTail: makeFilmTail(film: film, paper: paper),
                renderProcess: RenderProcessVersion(rawValue: 2)!,
                metal: metal)
            let floats = Self.readAllBytes(texture).withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            for i in stride(from: 0, to: floats.count, by: 4) {
                XCTAssertTrue(
                    floats[i].isFinite && floats[i + 1].isFinite
                        && floats[i + 2].isFinite,
                    "\(filmId)×\(paperId): texel \(i / 4)")
            }
        }
    }

    func testAllThreeLegsArmedRendersFiniteAndDeterministic() async throws {
        // All three legs armed at once (grain + halation + diffusion)
        // + the C200 fallback pair: finite + deterministic (the batch's
        // combined smoke — NOT a golden: on-semantics冒烟 only).
        let metal = try await makeMetal()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let image = makeRampImage()
        let store = try FilmMaterialStore(
            profilesDirectory: profilesDirectory())
        let film = try XCTUnwrap(store.profile(id: "fujifilm_c200"))
        let paper = try XCTUnwrap(
            store.profile(id: "fujifilm_crystal_archive_typeii"))
        func armed() async throws -> [UInt8] {
            let texture = try await render(
                image, chain: chain,
                filmTail: makeFilmTail(
                    film: film, paper: paper, halationAmount: 1.0,
                    diffusionFamily: "cinebloom", diffusionAmount: 0.5,
                    grainAmount: 1.0),
                renderProcess: RenderProcessVersion(rawValue: 2)!,
                metal: metal)
            return Self.readAllBytes(texture)
        }
        let first = try await armed()
        let floats = first.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        for i in stride(from: 0, to: floats.count, by: 4) {
            XCTAssertTrue(
                floats[i].isFinite && floats[i + 1].isFinite
                    && floats[i + 2].isFinite, "texel \(i / 4) finite")
        }
        let second = try await armed()
        XCTAssertEqual(
            second, first,
            "the fully-armed render re-renders bit-identically")
    }
}
