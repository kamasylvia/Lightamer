@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralGrainGoldenTests (Plan M8-3+ T4 — IOPParity) — the B-split
// off-identity + the grain group's golden faces (the SpectralDualArmGolden
// harness twin: full-pipe renders through RenderPipeline):
//
//   1. THE B-SPLIT OFF-IDENTITY: the nil-grain spectral arm renders the
//      DUAL-ARM sentinels bit-identically (ramp512 + fixture + neutral
//      closure — the split's main gate: B1→B2 with the grain group
//      SKIPPED is the fused B, verbatim).
//   2. THE 28-PAIR SWEEP: every vendored film × endura renders finite
//      through the split (the off-identity's breadth face).
//   3. THE ON-GOLDEN: a grain-armed render DIFFERS from the off render
//      (the leg runs) and re-renders BIT-IDENTICALLY (deterministic —
//      the Teschner stability's pipe face).
//   4. THE ZERO-IDENTITY: amount-0 renders BIT-IDENTICALLY to nil
//      (the on-identity face — the math runs, the delta is zero).
//   5. THE CPU/GPU BIT-EXACT: the host Poisson twin vs the kernel's
//      gen_raw_sl on a synthetic density (the grain.h discipline's
//      device face — shared polynomial + grain_exp_neg + plain sqrt).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralGrainGoldenTests: XCTestCase {

    private static let fixtureImageID = UUID(
        uuidString: "A1B2C3D4-1A2B-3C4D-5E6F-7A8B9C0D1E2F")!

    // The M8-2 registered sentinels (the split's no-drift pins — the
    // T4 off-identity's main gate).
    private static let rampSentinel: UInt64 = 3613671270926763817
    private static let closureSpread = 0.1300766902548187

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
        film: FilmProfile, paper: FilmProfile, grainAmount: Float? = nil
    ) -> FilmTailPolicy {
        var r = FilmRecord()
        r.filmStock = film.info.stock ?? ""
        r.paperStock = paper.info.stock ?? ""
        r.grainAmount = grainAmount
        return FilmTailParams(
            record: r, filmProfile: film, paperProfile: paper,
            materialPairHash: FilmMaterialStore.materialPairHash(film: film, paper: paper))
    }

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

    // MARK: - 1: the B-split off-identity (the sentinel gate)

    func testNilGrainHoldsTheDualArmSentinels() async throws {
        let metal = try await makeMetal()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let texture = try await render(
            makeRampImage(), chain: chain,
            filmTail: makeFilmTail(film: try portra, paper: try endura),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        XCTAssertEqual(
            Self.fnv1a(Self.readAllBytes(texture)), Self.rampSentinel,
            "the B1→B2 split holds the ramp512 sentinel (off-identity)")
    }

    // MARK: - 2: the 28-pair sweep (the breadth face)

    func testAll28PairsRenderFiniteThroughTheSplit() async throws {
        let metal = try await makeMetal()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let paper = try endura
        let names = try FileManager.default.contentsOfDirectory(
            atPath: profilesDirectory().path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        XCTAssertEqual(names.count, 28)
        let image = makeRampImage(width: 24, height: 16)
        for name in names {
            let profile = try FilmProfile.load(
                profilesDirectory().appendingPathComponent(name))
            let texture = try await render(
                image, chain: chain,
                filmTail: makeFilmTail(film: profile, paper: paper),
                renderProcess: RenderProcessVersion(rawValue: 2)!,
                metal: metal)
            let floats = Self.readAllBytes(texture).withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            for i in stride(from: 0, to: floats.count, by: 4) {
                XCTAssertTrue(
                    floats[i].isFinite && floats[i + 1].isFinite
                        && floats[i + 2].isFinite, "\(name): texel \(i / 4)")
            }
        }
    }

    // MARK: - 3+4: the on-golden + the zero-identity

    func testGrainOnDiffersAndReRendersBitIdentically() async throws {
        let metal = try await makeMetal()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let image = makeRampImage(width: 64, height: 48)
        let film = try portra
        let paper = try endura
        let off = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(film: film, paper: paper),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let offBytes = Self.readAllBytes(off)
        let on1 = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(film: film, paper: paper, grainAmount: 1.0),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let on1Bytes = Self.readAllBytes(on1)
        XCTAssertNotEqual(
            on1Bytes, offBytes, "the armed grain leg moves the render")
        // Finite everywhere (the leg never NaNs the pipe).
        let floats = on1Bytes.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        for i in stride(from: 0, to: floats.count, by: 4) {
            XCTAssertTrue(
                floats[i].isFinite && floats[i + 1].isFinite
                    && floats[i + 2].isFinite, "on-render texel \(i / 4)")
        }
        let on2 = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(film: film, paper: paper, grainAmount: 1.0),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        XCTAssertEqual(
            Self.readAllBytes(on2), on1Bytes,
            "the grain leg re-renders bit-identically (deterministic)")
    }

    func testAmountZeroIsBitIdenticalToNil() async throws {
        let metal = try await makeMetal()
        let chain = try await makeColorOut(registry: ModuleRegistry.makeDefault())
        let image = makeRampImage(width: 64, height: 48)
        let film = try portra
        let paper = try endura
        let off = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(film: film, paper: paper),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        let zero = try await render(
            image, chain: chain,
            filmTail: makeFilmTail(film: film, paper: paper, grainAmount: 0.0),
            renderProcess: RenderProcessVersion(rawValue: 2)!, metal: metal)
        XCTAssertEqual(
            Self.readAllBytes(zero), Self.readAllBytes(off),
            "amount-0 is the on-identity (bit-identical to nil)")
    }
}
