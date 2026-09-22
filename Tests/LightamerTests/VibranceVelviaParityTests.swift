@testable import LightamerCore
import CoreImage
import Foundation
import LightamerIOP
import Metal
import XCTest

// VibranceVelviaParityTests (Plan 05-04-T3) — vibrance 2-case + velvia
// 3-case track-A parity (synthesized refs vs the live pipe) + identity
// gates + velvia clamp nails + vibrance low-saturation direction.
//
// REFERENCE PROVENANCE (L017 route): synthesized by gen_fixtures.py
// (vibrance/velvia sections) — float64 evaluation of the documented dt
// process over canonical fixture bytes. dt-side = XMP adoption + DB hex
// + params ok (evidence table in the manifest).
final class VibranceVelviaParityTests: XCTestCase {

    private static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/golden", isDirectory: true)

    private func requireGolden(_ path: String) throws -> URL {
        let url = Self.goldenDir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("golden artifact missing: input/golden/\(path)")
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

    private static let fixtures = [
        "ramp_8ev", "flat_0ev", "flat_-4ev", "saturated",
        "gray_staircase", "hue_sweep",
    ]

    // MARK: - Vibrance parity (2 cases)

    /// TRACK A vibrance (2×6): synthesized refs vs the live pipe, <1e-5
    /// rel (Lab round-trip legs — 03 Lab gate).
    func testVibranceGoldenParity() async throws {
        let metal = try await makeMetal()
        let cases: [(String, VibranceModule.Params)] = [
            ("vib_default", VibranceModule.Params(amount: 0)),
            ("vib_strong", VibranceModule.Params(amount: 75)),
        ]
        var gotAll: [Float] = []
        var refAll: [Float] = []
        var compared = 0
        for fixture in Self.fixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            for (caseName, params) in cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, w, h) = try await runVibrancePipe(
                    image: image, params: params, metal: metal)
                XCTAssertEqual(w, golden.width, "\(caseName)×\(fixture)")
                XCTAssertEqual(h, golden.height, "\(caseName)×\(fixture)")
                let n = golden.width * golden.height
                var local: Float = 0
                for i in 0..<n {
                    for c in 0..<3 {
                        compared += 1
                        gotAll.append(pipe[i * 3 + c])
                        refAll.append(golden.rgb[i * 3 + c])
                        local = max(local, abs(pipe[i * 3 + c] - golden.rgb[i * 3 + c])
                            / max(abs(golden.rgb[i * 3 + c]), 1e-9))
                    }
                }
                print("VIB parity \(caseName)×\(fixture): maxRel=\(local)")
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels")
        // 非空转门：strong refs 必须随输入变化。
        let ramp = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/vib_strong__ramp_8ev.exr"))
        let flat = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/vib_strong__flat_0ev.exr"))
        XCTAssertNotEqual(ramp.rgb, flat.rgb,
            "vib_strong: ramp refs == flat refs — 输出不随输入变化")
        if let msg = ParityGate.failureMessage(
            "vibrance parity", gotAll, refAll,
            strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-4, envelopeAbs: 5e-4)
        {
            XCTFail(msg + "\ncompared=\(compared)")
        }
    }

    private func runVibrancePipe(
        image: DecodedImage, params: VibranceModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: VibranceModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<VibranceModule>)
        box.setParams(params)
        return try await renderChain(
            image: image, chain: [colorinBox as any ModuleBoxing, box], metal: metal)
    }

    // MARK: - Velvia parity (3 cases incl. clamp)

    /// TRACK A velvia (3×6): synthesized refs vs the live pipe, <1e-5 rel
    /// (pure-RGB domain — no Lab legs; the clamp case pins the [0,1]
    /// truncation path with bias 0).
    func testVelviaGoldenParity() async throws {
        let metal = try await makeMetal()
        let cases: [(String, VelviaModule.Params)] = [
            ("vel_default", VelviaModule.Params(strength: 0, bias: 1.0)),
            ("vel_strong", VelviaModule.Params(strength: 75, bias: 1.0)),
            ("vel_clamp", VelviaModule.Params(strength: 100, bias: 0.0)),
        ]
        var gotAll: [Float] = []
        var refAll: [Float] = []
        var compared = 0
        for fixture in Self.fixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            for (caseName, params) in cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, w, h) = try await runVelviaPipe(
                    image: image, params: params, metal: metal)
                XCTAssertEqual(w, golden.width, "\(caseName)×\(fixture)")
                XCTAssertEqual(h, golden.height, "\(caseName)×\(fixture)")
                let n = golden.width * golden.height
                var local: Float = 0
                for i in 0..<n {
                    for c in 0..<3 {
                        compared += 1
                        gotAll.append(pipe[i * 3 + c])
                        refAll.append(golden.rgb[i * 3 + c])
                        local = max(local, abs(pipe[i * 3 + c] - golden.rgb[i * 3 + c])
                            / max(abs(golden.rgb[i * 3 + c]), 1e-9))
                    }
                }
                print("VEL parity \(caseName)×\(fixture): maxRel=\(local)")
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels")
        // 非空转门：strong refs 必须随输入变化。
        let ramp = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/vel_strong__ramp_8ev.exr"))
        let flat = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/vel_strong__flat_0ev.exr"))
        XCTAssertNotEqual(ramp.rgb, flat.rgb,
            "vel_strong: ramp refs == flat refs — 输出不随输入变化")
        if let msg = ParityGate.failureMessage(
            "velvia parity", gotAll, refAll,
            strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-4, envelopeAbs: 5e-4)
        {
            XCTFail(msg + "\ncompared=\(compared)")
        }
    }

    private func runVelviaPipe(
        image: DecodedImage, params: VelviaModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: VelviaModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<VelviaModule>)
        box.setParams(params)
        return try await renderChain(
            image: image, chain: [colorinBox as any ModuleBoxing, box], metal: metal)
    }

    // MARK: - Identity gates (neutral params)

    /// amount=0 / strength=0 ⇒ pipe output == fixture input (the
    /// seed-neutral argument through the LIVE pipe, not just the CPU ref).
    /// Fixture is gray_staircase (in-gamut [0.02,1.0]): saturated carries
    /// out-of-[0,1] spectral channels where velvia's clamp (the formula)
    /// legitimately moves values even at strength 0 — identity cannot hold
    /// there by design. Threshold 1e-5 = the track-A strict gate (Lab
    /// round-trip legs on the vibrance side).
    func testNeutralIdentityThroughPipe() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gray_staircase.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (vib, _, _) = try await runVibrancePipe(
            image: image, params: VibranceModule.Params(amount: 0), metal: metal)
        let (vel, _, _) = try await runVelviaPipe(
            image: image, params: VelviaModule.Params(strength: 0, bias: 1.0), metal: metal)
        let input = try await inputRGB(image: image, metal: metal)
        var compared = 0
        for (got, label) in [(vib, "vibrance"), (vel, "velvia")] {
            var local: Float = 0
            for i in 0..<input.count {
                compared += 1
                local = max(local, abs(got[i] - input[i]) / max(abs(input[i]), 1e-9))
            }
            XCTAssertLessThan(local, 1e-5, "\(label) neutral identity maxRel=\(local)")
        }
        XCTAssertGreaterThan(compared, 0)
    }

    private func inputRGB(image: DecodedImage, metal: MetalContext) async throws -> [Float] {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let (rgb, _, _) = try await renderChain(
            image: image, chain: [colorinBox as any ModuleBoxing], metal: metal)
        return rgb
    }

    private func renderChain(
        image: DecodedImage, chain: [any ModuleBoxing], metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil)
        drain(metal) // L014
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        var rgb = [Float](repeating: 0, count: texture.width * texture.height * 3)
        for i in 0..<(texture.width * texture.height) {
            rgb[i * 3] = floats[i * 4]
            rgb[i * 3 + 1] = floats[i * 4 + 1]
            rgb[i * 3 + 2] = floats[i * 4 + 2]
        }
        return (rgb, texture.width, texture.height)
    }
}
