@testable import LightamerCore
import CoreImage
import Foundation
import LightamerIOP
import Metal
import XCTest

// ChannelMixerColorContrastParityTests (Plan 05-03-T4) — legacy mixer
// 3-case parity + colorcontrast 3-case parity (incl. unbound dual gate).
//
// REFERENCE PROVENANCE (L017 route): synthesized by gen_fixtures.py
// (channelmixer/channelcontrast sections) — float64 evaluation of the
// documented dt process over canonical fixture bytes. dt-side = XMP
// adoption + DB hex + params ok.
final class ChannelMixerColorContrastParityTests: XCTestCase {

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
        "ramp_8ev", "flat_0ev", "flat_-4ev", "gray_staircase", "saturated",
    ]


    // MARK: - Legacy mixer parity (3 cases: RGB swap / gray / HSL v1)

    /// TRACK A legacy (3×4): synthesized refs vs the live pipe, <1e-5 rel
    /// (RGB/gray exact-linear legs; HSL leg carries rgb2hsl float32 trig —
    /// same gate, envelope absorbs).
    func testChannelMixerGoldenParity() async throws {
        let metal = try await makeMetal()
        let cases: [(String, ChannelMixerModule.Params)] = [
            ("cm_rgb_swap", ChannelMixerModule.Params(
                red: [0, 0, 0, 0, 0, 1, 0],
                green: [0, 0, 0, 0, 1, 0, 0],
                blue: [0, 0, 0, 1, 0, 0, 0], algorithm: .v2)),
            ("cm_gray_luma", ChannelMixerModule.Params(
                red: [0, 0, 0, 1, 0, 0, 0.299],
                green: [0, 0, 0, 0, 1, 0, 0.587],
                blue: [0, 0, 0, 0, 0, 1, 0.114], algorithm: .v2)),
            ("cm_hsl_v1_sat", ChannelMixerModule.Params(
                red: [0, 0.5, 0, 1, 0, 0, 0],
                green: [0, 0, 0, 0, 1, 0, 0],
                blue: [0, 0, 0, 0, 0, 0, 0], algorithm: .v1)),
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
                let (pipe, w, h) = try await runMixerPipe(
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
                print("CM parity \(caseName)×\(fixture): maxRel=\(local)")
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels")
        // 非空转门（F2）：ramp refs 必须随输入变化——flat 全等 refs 即恒黑/恒等
        // 空转，parity 门再严也判不出。
        for caseName in ["cm_rgb_swap", "cm_gray_luma"] {
            let ramp = try GoldenParityTests.UncompressedEXR.load(
                requireGolden("output/\(caseName)__ramp_8ev.exr"))
            let flat = try GoldenParityTests.UncompressedEXR.load(
                requireGolden("output/\(caseName)__flat_0ev.exr"))
            XCTAssertNotEqual(ramp.rgb, flat.rgb,
                "\(caseName): ramp refs == flat refs — 输出不随输入变化")
        }
        if let msg = ParityGate.failureMessage(
            "channelmixer parity", gotAll, refAll,
            strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-4, envelopeAbs: 5e-4)
        {
            XCTFail(msg + "\ncompared=\(compared)")
        }
    }

    private func runMixerPipe(
        image: DecodedImage, params: ChannelMixerModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: ChannelMixerModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<ChannelMixerModule>)
        box.setParams(params)
        return try await renderChain(
            image: image, chain: [colorinBox as any ModuleBoxing, box], metal: metal)
    }

    // MARK: - ColorContrast parity (3 cases incl. bound clamp)

    /// TRACK A contrast (3×4): synthesized refs vs the live pipe, <1e-5
    /// rel (Lab round-trip legs — 03 Lab gate). The bound case pins the
    /// ±128 clamp path (cc_bound pushes a×3+60 deep into clamp).
    func testColorContrastGoldenParity() async throws {
        let metal = try await makeMetal()
        let cases: [(String, ColorContrastModule.Params)] = [
            ("cc_default", ColorContrastModule.Params()),
            ("cc_steep", ColorContrastModule.Params(
                aSteepness: 1.8, aOffset: 5, bSteepness: 0.6, bOffset: -8,
                unbound: true)),
            ("cc_bound", ColorContrastModule.Params(
                aSteepness: 3, aOffset: 60, bSteepness: 3, bOffset: -60,
                unbound: false)),
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
                let (pipe, w, h) = try await runContrastPipe(
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
                print("CC parity \(caseName)×\(fixture): maxRel=\(local)")
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels")
        if let msg = ParityGate.failureMessage(
            "colorcontrast parity", gotAll, refAll,
            strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-4, envelopeAbs: 5e-4)
        {
            XCTFail(msg + "\ncompared=\(compared)")
        }
    }

    private func runContrastPipe(
        image: DecodedImage, params: ColorContrastModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: ColorContrastModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<ColorContrastModule>)
        box.setParams(params)
        return try await renderChain(
            image: image, chain: [colorinBox as any ModuleBoxing, box], metal: metal)
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
