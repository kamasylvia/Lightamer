@testable import LightamerCore
import CoreGraphics
import Metal
import XCTest

// Plan 13-2 T2/T3 — the soft-proof stage (COLOR-02): proof-OFF byte
// pass-through, the ColorSync round-trip behavior (T1 probe anchors),
// the override-not-Params/history/export contract (structural), and the
// T3 OOG gamut check (black clipping).
//
// Engine anchor: the T1 probe (13-2-probes.md) proved the RGB ICC round
// trip is EXACT inside the gamut (≤1e-4) and clips out-of-gamut colors
// (≥0.066 divergence) — these tests pin that behavior as the golden.

final class SoftProofStageTests: XCTestCase {

    private enum Fixtures {
        static let adobeRGB = URL(fileURLWithPath:
            "/System/Library/ColorSync/Profiles/AdobeRGB1998.icc")
        static let genericCMYK = URL(fileURLWithPath:
            "/System/Library/ColorSync/Profiles/Generic CMYK Profile.icc")

        static func icc(_ url: URL) throws -> Data {
            try XCTSkipIf(!FileManager.default.fileExists(atPath: url.path),
                          "system ICC fixture missing: \(url.path)")
            return try Data(contentsOf: url)
        }

        static func adobeProfile(
            bpc: Bool = true, gamutCheck: Bool = false
        ) throws -> SoftProofProfile {
            try SoftProofProfile(
                printerICC: icc(adobeRGB), label: "AdobeRGB (1998)",
                blackPointCompensation: bpc, gamutCheck: gamutCheck)
        }
    }

    private func makeMetal() throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        return try MetalContext()
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// float32 RGBA texture (row-major, 4 floats/px) — the pipe interior
    /// format (WorkingSpace).
    private func floatTexture(
        _ pixels: [[Float]], width: Int, height: Int, metal: MetalContext
    ) -> any MTLTexture {
        let flat = pixels.flatMap { $0 }
        precondition(flat.count == width * height * 4)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        flat.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    private func readFloat(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        drain(metal)
        var buffer = [Float](repeating: 0, count: texture.width * texture.height * 4)
        buffer.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return buffer
    }

    private func runStage(
        _ pixels: [[Float]], width: Int, height: Int,
        profile: SoftProofProfile?, metal: MetalContext
    ) async throws -> [Float] {
        let stage = SoftProofStage()
        stage.softProofOverride = profile
        var piece = IOPiece()
        stage.commitParams(SoftProofStage.Params(), into: &piece)
        let input = floatTexture(pixels, width: width, height: height, metal: metal)
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: width, height: height, mipmapped: false)
        outputDescriptor.usage = [.shaderRead, .shaderWrite]
        outputDescriptor.storageMode = .shared
        let output = metal.device.makeTexture(descriptor: outputDescriptor)!
        let roi = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        try await stage.process(
            input: input, output: output, roiIn: roi, roiOut: roi, piece: &piece, metal: metal)
        return readFloat(output, metal: metal)
    }

    // In-gamut Rec2020-linear samples (the T1 probe §3.1 anchor set minus
    // the out-of-gamut primaries).
    private let inGamutPixels: [[Float]] = [
        [0.0, 0.0, 0.0, 1.0],
        [0.02, 0.02, 0.02, 1.0],
        [1.0, 1.0, 1.0, 1.0],
        [0.216, 0.216, 0.216, 1.0],
        [0.3, 0.6, 0.2, 1.0],
        [0.6, 0.35, 0.2, 1.0],
    ]
    private let oogPixels: [[Float]] = [
        [1.0, 0.0, 0.0, 1.0],   // Rec2020 primaries exceed AdobeRGB
        [0.0, 1.0, 0.0, 1.0],
        [0.0, 0.0, 1.0, 1.0],
    ]

    // MARK: - Proof OFF = byte pass-through

    func testProofOffIdentityCopy() async throws {
        let metal = try makeMetal()
        let pixels = inGamutPixels + oogPixels
        let output = try await runStage(pixels, width: pixels.count, height: 1,
                                        profile: nil, metal: metal)
        // Byte-exact: the defensive identity path must be a pure copy.
        XCTAssertEqual(output.count, pixels.count * 4)
        for (i, px) in pixels.enumerated() {
            for c in 0..<3 {
                XCTAssertEqual(output[i * 4 + c], px[c], accuracy: 0.0,
                               "proof OFF must pass pixels through unchanged (px \(i) ch \(c))")
            }
            XCTAssertEqual(output[i * 4 + 3], 1.0, accuracy: 0.0)
        }
    }

    // MARK: - Proof ON: the ColorSync round trip (T1 probe anchors)

    func testInGamutRoundTripExact() async throws {
        let metal = try makeMetal()
        let profile = try Fixtures.adobeProfile()
        let width = inGamutPixels.count
        let output = try await runStage(inGamutPixels, width: width, height: 1,
                                        profile: profile, metal: metal)
        for (i, px) in inGamutPixels.enumerated() {
            for c in 0..<3 {
                XCTAssertEqual(
                    output[i * 4 + c], px[c], accuracy: Float(SoftProofStage.oogRoundTripThreshold),
                    "in-gamut color must round trip exactly (px \(i) ch \(c))")
            }
        }
    }

    func testOutOfGamutClipped() async throws {
        let metal = try makeMetal()
        let profile = try Fixtures.adobeProfile()
        let width = oogPixels.count
        let output = try await runStage(oogPixels, width: width, height: 1,
                                        profile: profile, metal: metal)
        // The Rec2020 primaries clip inside AdobeRGB — irreversibly
        // (T1 probe §3.1: deltas 0.066..0.123). At least one channel of
        // each primary must move beyond the OOG threshold.
        for (i, px) in oogPixels.enumerated() {
            let delta = (0..<3).map { abs(output[i * 4 + $0] - px[$0]) }.max() ?? 0
            XCTAssertGreaterThan(
                delta, SoftProofStage.oogRoundTripThreshold,
                "out-of-gamut primary must clip (px \(i))")
        }
    }

    /// The T1 probe §3.2 BPC anchor on the black-point-zero profile: with
    /// AdobeRGB (L*=0 black) BPC has nothing to compensate — on and off are
    /// byte-identical (the mathematical expectation; a divergence here
    /// would mean the BPC key mutates non-black points).
    func testBPCAnchorBlackPointZeroInvariant() async throws {
        let metal = try makeMetal()
        let pixels = inGamutPixels + oogPixels
        let width = pixels.count
        let withBPC = try await runStage(
            pixels, width: width, height: 1, profile: Fixtures.adobeProfile(bpc: true), metal: metal)
        let withoutBPC = try await runStage(
            pixels, width: width, height: 1, profile: Fixtures.adobeProfile(bpc: false), metal: metal)
        XCTAssertEqual(withBPC, withoutBPC,
                       "BPC must be a no-op on a zero-black-point printer profile")
    }

    // MARK: - T3: OOG gamut check (black clipping)

    /// Gamut check ON: the out-of-gamut primaries render BLACK; every
    /// in-gamut pixel is BIT-IDENTICAL to its gamut-check-OFF proof value
    /// (the clip may only touch OOG pixels — the golden sample set = the
    /// T1 probe anchor set, DECISIONS D-13-2-OOG).
    func testGamutCheckBlackClipsOutOfGamut() async throws {
        let metal = try makeMetal()
        let pixels = inGamutPixels + oogPixels
        let width = pixels.count
        let clipped = try await runStage(
            pixels, width: width, height: 1,
            profile: Fixtures.adobeProfile(gamutCheck: true), metal: metal)
        let plain = try await runStage(
            pixels, width: width, height: 1,
            profile: Fixtures.adobeProfile(gamutCheck: false), metal: metal)
        for i in 0..<width {
            let isInGamut = i < inGamutPixels.count
            if isInGamut {
                for c in 0..<4 {
                    XCTAssertEqual(
                        clipped[i * 4 + c], plain[i * 4 + c], accuracy: 1e-9,
                        "gamut check must not touch in-gamut sample \(i) ch \(c)")
                }
            } else {
                let rgb = (0..<3).map { clipped[i * 4 + $0] }
                XCTAssertEqual(rgb, [Float(0), 0, 0],
                               "out-of-gamut sample \(i) must be black-clipped")
                XCTAssertEqual(clipped[i * 4 + 3], 1.0, accuracy: 1e-6)
                let plainRGB = (0..<3).map { plain[i * 4 + $0] }
                XCTAssertFalse(plainRGB.allSatisfy { $0 == 0 },
                               "contrast: without the check the clipped color must show")
            }
        }
    }

    /// Gamut check OFF (the pass-through contrast): the clipped colors show
    /// their proof values — nonzero, non-black (the clip is the simulation,
    /// black is the WARNING).
    func testGamutCheckOffPassesProofValues() async throws {
        let metal = try makeMetal()
        let profile = try Fixtures.adobeProfile(gamutCheck: false)
        let width = oogPixels.count
        let output = try await runStage(oogPixels, width: width, height: 1,
                                        profile: profile, metal: metal)
        for i in 0..<width {
            let rgb = (0..<3).map { output[i * 4 + $0] }
            XCTAssertFalse(rgb.allSatisfy { $0 == 0 },
                           "without gamut check the clipped color must show, not black (px \(i))")
        }
    }

    // MARK: - Profile validation (the T1 downgrade rulings)

    func testProfileRejectsCMYKPrinterICC() throws {
        let cmyk = try Fixtures.icc(Fixtures.genericCMYK)
        XCTAssertThrowsError(
            try SoftProofProfile(printerICC: cmyk, label: "Generic CMYK")
        ) { error in
            guard case AppError.invalidParameter = AppError(error) else {
                return XCTFail("expected invalidParameter, got \(error)")
            }
        }
    }

    func testProfileRejectsNonRelativeIntent() throws {
        let icc = try Fixtures.icc(Fixtures.adobeRGB)
        XCTAssertThrowsError(
            try SoftProofProfile(printerICC: icc, label: "AdobeRGB", intent: .perceptual)
        ) { error in
            guard case AppError.invalidParameter = AppError(error) else {
                return XCTFail("expected invalidParameter, got \(error)")
            }
        }
    }

    // MARK: - Identity (the cache-invalidation atom)

    func testStableIDStableAndDistinct() throws {
        let a = try Fixtures.adobeProfile()
        let b = try Fixtures.adobeProfile()
        XCTAssertEqual(a.stableID, b.stableID, "same ICC + config ⇒ same identity")

        let noBPC = try Fixtures.adobeProfile(bpc: false)
        XCTAssertNotEqual(a.stableID, noBPC.stableID, "BPC flip must change the identity")
        let gamut = try Fixtures.adobeProfile(gamutCheck: true)
        XCTAssertNotEqual(a.stableID, gamut.stableID, "gamut-check flip must change the identity")
    }

    // MARK: - Structural contract: never Params/history/sidecar/export

    func testStageIsNotARegistryModule() async {
        // The history/sidecar/export "never" trio is STRUCTURAL: the stage
        // is not registered, so the registry-driven materialization paths
        // (history rematerialization, sidecar restore, export chain
        // assembly) can never mint it.
        let registry = ModuleRegistry.makeDefault()
        let chain = await registry.makeDefaultChain()
        XCTAssertFalse(
            chain.contains { $0.opName == SoftProofStage.opName },
            "the default chain must not carry the proof stage")
        let box = await registry.makeBox(opName: SoftProofStage.opName, instanceID: UUID())
        XCTAssertNil(box, "an unregistered op must not mint a box (sidecar degrade safety)")
        let instances = await registry.makeDefaultInstances()
        XCTAssertFalse(
            instances.contains { $0.opName == SoftProofStage.opName },
            "default instances (the history seed) must not carry the proof stage")
    }

    func testCommitParamsFoldsProfileIdentity() throws {
        let stage = SoftProofStage()
        var piece = IOPiece()
        stage.commitParams(SoftProofStage.Params(), into: &piece)
        let offHash = piece.paramsHash

        stage.softProofOverride = try Fixtures.adobeProfile()
        stage.commitParams(SoftProofStage.Params(), into: &piece)
        let adobeHash = piece.paramsHash
        XCTAssertNotEqual(offHash, adobeHash, "proof ON must re-commit to a different hash")

        stage.softProofOverride = try Fixtures.adobeProfile(gamutCheck: true)
        stage.commitParams(SoftProofStage.Params(), into: &piece)
        XCTAssertNotEqual(piece.paramsHash, adobeHash,
                          "gamut-check flip must re-commit (cache keys flip below the stage)")

        stage.softProofOverride = try Fixtures.adobeProfile()
        stage.commitParams(SoftProofStage.Params(), into: &piece)
        XCTAssertEqual(piece.paramsHash, adobeHash,
                       "the same profile re-commits to the same hash (cache-neutral)")
    }

    // MARK: - Catalog

    func testCatalogListsAdobeRGBAndConstructsProfiles() throws {
        let entries = PrinterProfileCatalog.installedProfiles()
        XCTAssertFalse(entries.isEmpty, "the system profile directories must yield entries")
        let adobe = entries.first { $0.name.contains("AdobeRGB") }
        XCTAssertNotNil(adobe, "AdobeRGB1998.icc ships with macOS")
        let profile = try XCTUnwrap(adobe).makeProfile()
        XCTAssertEqual(profile.label, adobe?.name)
    }
}
