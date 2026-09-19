@testable import LightamerCore
import CoreGraphics
import CoreImage
import Foundation
import LightamerIOP
import Metal
import XCTest

// LevelsParityTests (Plan 03-03-T4) — IOP-TONE-06 manual mode.
//
// REFERENCE PROVENANCE: synthesized references (gen_fixtures.py refs,
// levels section — the float64 evaluation of dt levels.c compute_lut +
// process over the canonical fixtures). The dt-cli probe route is
// unavailable for the Lab chain (see ColisaParityTests header + manifest
// — the same piece-state corruption applies to every Lab-domain module;
// the rebuilt liblevels.so adopts the XMP blob: `params v. 2: version ok
// params ok`). T5 adds the automatic-percentile cases on top.
final class LevelsParityTests: XCTestCase {

    private static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/golden", isDirectory: true)

    private func requireGolden(_ path: String) throws -> URL {
        let url = Self.goldenDir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip(
                "golden artifact missing: input/golden/\(path) — run "
                    + "`bash input/golden/regenerate.sh` (Plan 03-03)"
            )
        }
        return url
    }

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

    private var cases: [(name: String, params: LevelsModule.Params)] {
        [
            ("levels_default", LevelsModule.Params(mode: .manual, levels: [0, 0.5, 1])),
            ("levels_bw", LevelsModule.Params(mode: .manual, levels: [0.2, 0.5, 0.8])),
            ("levels_gamma", LevelsModule.Params(mode: .manual, levels: [0, 0.25, 1])),
        ]
    }

    // MARK: - CPU LUT unit tests (levels.c:252-267)

    /// Default points (0, 0.5, 1) → gamma 1 → identity LUT.
    func testIdentityLevelsGiveIdentityLUT() {
        let lut = LevelsModule.buildLUT(levels: [0, 0.5, 1])
        XCTAssertEqual(LevelsModule.inverseGamma(levels: [0, 0.5, 1]), 1.0, accuracy: 1e-12)
        for k in stride(from: 0, to: LevelsModule.lutResolution, by: 977) {
            XCTAssertEqual(
                lut[k], 100.0 * Float(k) / Float(LevelsModule.lutResolution),
                accuracy: 1e-3, "lut[\(k)]"
            )
        }
    }

    /// gray=25% → tmp = (0.25−0.5)/0.5 = −0.5 → inv_gamma = 10^−0.5.
    func testGammaVector() {
        let gamma = LevelsModule.inverseGamma(levels: [0, 0.25, 1])
        XCTAssertEqual(gamma, Foundation.pow(10.0, -0.5), accuracy: 1e-12)
        let lut = LevelsModule.buildLUT(levels: [0, 0.25, 1])
        let mid = LevelsModule.lutResolution / 2
        XCTAssertEqual(
            Double(lut[mid]), 100.0 * Foundation.pow(0.5, gamma),
            accuracy: 1e-3
        )
    }

    /// black=20/white=80 → linear stretch with gamma 1 (mid unchanged).
    func testBlackWhiteVector() {
        // Float32 point arithmetic (dt's domain): 0.2/0.8 are not exact
        // binary floats, so the gamma is 1 within float32 rounding.
        let gamma = LevelsModule.inverseGamma(levels: [0.2, 0.5, 0.8])
        XCTAssertEqual(gamma, 1.0, accuracy: 1e-7)
        let lut = LevelsModule.buildLUT(levels: [0.2, 0.5, 0.8])
        let mid = LevelsModule.lutResolution / 2 // percentage 0.5 → 50
        XCTAssertEqual(lut[mid], 50.0, accuracy: 1e-3)
    }

    // MARK: - Kernel: chroma preservation (plan acceptance)

    /// The chroma-preservation law: a,b × L_out/max(L_in, 0.01) — the a/b
    /// RATIO (hue) is invariant for any pixel above the black point.
    func testKernelChromaHuePreservation() async throws {
        let metal = try await makeMetal()
        let module = LevelsModule()
        var piece = IOPiece()
        await module.commitParams(
            LevelsModule.Params(mode: .manual, levels: [0.2, 0.5, 0.8]), into: &piece
        )

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 2, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        // a saturated orange-ish Rec2020 color + a neutral
        var pixels: [Float] = [
            0.45, 0.25, 0.05, 1.0,
            0.5, 0.5, 0.5, 1.0,
            0.45, 0.25, 0.05, 1.0,
            0.5, 0.5, 0.5, 1.0,
        ]
        pixels.withUnsafeBytes {
            input.replace(
                region: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 2 * 16
            )
        }
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal
        )
        drain(metal)
        var out = [Float](repeating: 0, count: 2 * 4)
        out.withUnsafeMutableBytes {
            output.getBytes(
                $0.baseAddress!, bytesPerRow: 2 * 16,
                from: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0
            )
        }
        let inA = Double(pixels[0]), inB = Double(pixels[2])
        // Lab a/b ratios preserved — compare through the CPU Lab conversion.
        let labIn = LabRoundTrip.rec2020ToLab(SIMD3(inA, 0.25, 0.05))
        let labOut = LabRoundTrip.rec2020ToLab(
            SIMD3(Double(out[0]), Double(out[1]), Double(out[2]))
        )
        let hueIn = labIn.y / labIn.z
        let hueOut = labOut.y / labOut.z
        XCTAssertEqual(hueOut, hueIn, accuracy: 5e-4, "a/b hue ratio preserved")
        // neutrals stay neutral
        let neutralOut = LabRoundTrip.rec2020ToLab(
            SIMD3(Double(out[4]), Double(out[5]), Double(out[6]))
        )
        XCTAssertEqual(neutralOut.y, 0, accuracy: 1e-4)
        XCTAssertEqual(neutralOut.z, 0, accuracy: 1e-4)
    }

    // MARK: - Track A: kernel vs the synthesized references

    private static let trackAFixtures = [
        "stair_1d", "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev",
        "saturated",
    ]

    func testLevelsGoldenParityManual() async throws {
        let metal = try await makeMetal()
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runLevelsPipe(
                    image: image, params: params, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size mismatch")
                    continue
                }
                if let message = ParityGate.failureMessage(
                    "\(caseName)×\(fixture)", pipe, golden.rgb
                ) {
                    failures.append(message)
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "levels track A FAILED:\n" + failures.prefix(6).joined(separator: "\n"))
    }

    private func runLevelsPipe(
        image: DecodedImage, params: LevelsModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let levels = await registry.makeBox(opName: LevelsModule.opName)
        let levelsBox = try XCTUnwrap(levels as? ModuleBox<LevelsModule>)
        await levelsBox.setParams(params)
        let chain = [try XCTUnwrap(colorin), levelsBox]

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal) // L014
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat)
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        var rgb = [Float](repeating: 0, count: texture.width * texture.height * 3)
        for i in 0..<(texture.width * texture.height) {
            rgb[i * 3] = floats[i * 4]
            rgb[i * 3 + 1] = floats[i * 4 + 1]
            rgb[i * 3 + 2] = floats[i * 4 + 2]
        }
        return (rgb, texture.width, texture.height)
    }

    // MARK: - Track B: identity levels inserted

    func testTrackBNeutralityWithLevelsInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )
        let levels = await registry.makeBox(opName: LevelsModule.opName)
        let levelsBox = try XCTUnwrap(levels as? ModuleBox<LevelsModule>)
        await levelsBox.setParams(.init()) // identity points
        chain.append(levelsBox)
        chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal)
        let rgb8 = try XCTUnwrap(texture.pixelFormat == .bgra8Unorm ? texture : nil)
        var bytes = [UInt8](repeating: 0, count: rgb8.width * rgb8.height * 4)
        bytes.withUnsafeMutableBytes {
            rgb8.getBytes(
                $0.baseAddress!, bytesPerRow: rgb8.width * 4,
                from: MTLRegionMake2D(0, 0, rgb8.width, rgb8.height), mipmapLevel: 0
            )
        }
        var failures: [String] = []
        for patch in Fixtures.neutralPatches {
            let cx = Int(patch.x * Double(rgb8.width - 1))
            let cy = Int(patch.y * Double(rgb8.height - 1))
            var rs = 0, gs = 0, bs = 0, n = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let x = min(max(cx + dx, 0), rgb8.width - 1)
                    let y = min(max(cy + dy, 0), rgb8.height - 1)
                    let p = (y * rgb8.width + x) * 4
                    rs += Int(bytes[p + 2]); gs += Int(bytes[p + 1]); bs += Int(bytes[p])
                    n += 1
                }
            }
            let (r, g, b) = (Double(rs) / Double(n), Double(gs) / Double(n), Double(bs) / Double(n))
            if abs(r - g) >= 2 || abs(g - b) >= 2 {
                failures.append("\(patch.name): |R−G|=\(abs(r - g)) |G−B|=\(abs(g - b))")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "track B neutrality with levels inserted FAILED:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Registration

    func testLevelsRegisteredAtV50Slot49() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: LevelsModule.opName)
        _ = try XCTUnwrap(box as? ModuleBox<LevelsModule>)
        XCTAssertEqual(LevelsModule.opName, "levels")
        XCTAssertEqual(LevelsModule.iopOrder, 49.0)
        XCTAssertEqual(LevelsModule.defaultColorspace, .Lab)
        let id = UUID()
        let restored = await registry.makeBox(opName: LevelsModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
    }
}
