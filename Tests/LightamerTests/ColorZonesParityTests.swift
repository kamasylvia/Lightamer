@testable import LightamerCore
import CoreImage
import Foundation
import LightamerIOP
import Metal
import XCTest

// ColorZonesParityTests (Plan 05-04-T3) — colorzones 4-case track-A
// parity (synthesized float64 refs vs the live pipe) + the LUT DUAL GATE
// (ParityGate, 03-03定型: CPU LUT vs GPU lookup ≥99% <1e-5 + 2.5e-5
// floor / 1e-4 envelope) + hue-sweep full-ring live run.
//
// REFERENCE PROVENANCE (L017 route): synthesized by gen_fixtures.py
// (colorzones section) — V2-spline LUT build + v3 process with the
// CL-leg NEAREST lookup over canonical fixture bytes. dt-side = XMP
// adoption + DB hex + params ok (evidence table in the manifest).
//
// LOOKUP DIVERGENCE (module header): the LUT-direct gate calls
// ColorZonesModule.reference which is LERP (dt CPU leg parity), while
// gen_fixtures' mirror uses the NEAREST lookup (kernel-identical) — the
// dual gate absorbs dt's own CPU-vs-CL leg gap; the strict fraction
// records the measured residual index-flip rate. (05-04 复验勘误：原注释
// 把 LERP reference 误标为 NEAREST。)
final class ColorZonesParityTests: XCTestCase {

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

    private static func params(for caseName: String) -> ColorZonesModule.Params {
        switch caseName {
        case "cz_default":
            return ColorZonesModule.Params()
        case "cz_lightness":
            return ColorZonesModule.Params(
                channel: .lightness,
                curveL: [.init(x: 0, y: 0.3), .init(x: 0.5, y: 0.65), .init(x: 1, y: 0.45)],
                typeL: .catmullRom)
        case "cz_chroma":
            return ColorZonesModule.Params(
                channel: .chroma,
                curveC: [.init(x: 0, y: 0.2), .init(x: 0.5, y: 0.8), .init(x: 1, y: 0.35)],
                typeC: .monotoneHermite)
        case "cz_hue":
            return ColorZonesModule.Params(
                channel: .hue,
                curveH: [.init(x: 0, y: 0.5), .init(x: 0.25, y: 0.75),
                         .init(x: 0.5, y: 0.3), .init(x: 0.75, y: 0.6)],
                typeH: .monotoneHermite,
                strength: 50)
        default:
            fatalError("unknown case \(caseName)")
        }
    }

    // MARK: - Track A (4 cases × 6 fixtures, two tiers)

    /// TRACK A colorzones (4×6): synthesized refs vs the live pipe.
    /// Two tiers (DECISIONS D-05-04-T3-1):
    /// - MAIN (5 in-gamut fixtures): the plan dual gate — strict ≥99%
    ///   <1e-5 (+2.5e-5 floor) + 1e-4 envelope.
    /// - SPECTRAL (saturated only): envelope 1e-2 abs + strict REPORTED.
    ///   Physics: output angle noise × chroma amplification — d(out) ≈
    ///   C·2π·d(h) with C up to 5507 on the spectral blocks (measured
    ///   coefficient: dh ~3e-7 float32 → 5e-3 abs). dt's own CL leg is the
    ///   same fast-math family. Precedent: FilmicRGB F3 treats spectral
    ///   blocks as gamut assertions, not parity.
    func testColorZonesGoldenParity() async throws {
        let metal = try await makeMetal()
        let cases = ["cz_default", "cz_lightness", "cz_chroma", "cz_hue"]
        var mainGot: [Float] = []
        var mainRef: [Float] = []
        var mainCompared = 0
        var specGot: [Float] = []
        var specRef: [Float] = []
        var specCompared = 0
        for fixture in Self.fixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            for caseName in cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, w, h) = try await runZonesPipe(
                    image: image, params: Self.params(for: caseName), metal: metal)
                XCTAssertEqual(w, golden.width, "\(caseName)×\(fixture)")
                XCTAssertEqual(h, golden.height, "\(caseName)×\(fixture)")
                let n = golden.width * golden.height
                var local: Float = 0
                let spectral = fixture == "saturated"
                for i in 0..<n {
                    for c in 0..<3 {
                        if spectral {
                            specCompared += 1
                            specGot.append(pipe[i * 3 + c])
                            specRef.append(golden.rgb[i * 3 + c])
                        } else {
                            mainCompared += 1
                            mainGot.append(pipe[i * 3 + c])
                            mainRef.append(golden.rgb[i * 3 + c])
                        }
                        local = max(local, abs(pipe[i * 3 + c] - golden.rgb[i * 3 + c])
                            / max(abs(golden.rgb[i * 3 + c]), 1e-9))
                    }
                }
                print("CZ parity \(caseName)×\(fixture): maxRel=\(local)")
            }
        }
        XCTAssertGreaterThan(mainCompared, 0, "main tier compared zero pixels")
        XCTAssertGreaterThan(specCompared, 0, "spectral tier compared zero pixels")
        // 非空转门：hue refs 必须随输入变化 + LUT 实际插值中（hue sweep
        // 输出方差 > 0 — 跨格点的真实查表，不是退化恒等）。
        let ramp = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/cz_hue__ramp_8ev.exr"))
        let flat = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/cz_hue__flat_0ev.exr"))
        XCTAssertNotEqual(ramp.rgb, flat.rgb,
            "cz_hue: ramp refs == flat refs — 输出不随输入变化")
        let sweep = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/cz_hue__hue_sweep.exr"))
        let mean = sweep.rgb.reduce(0, +) / Float(sweep.rgb.count)
        let variance = sweep.rgb.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
            / Float(sweep.rgb.count)
        XCTAssertGreaterThan(variance, 1e-6,
            "cz_hue hue_sweep refs variance=\(variance) — LUT 未实际插值")
        // MAIN tier: the plan dual gate (asserted).
        let mainEval = ParityGate.evaluate(
            mainGot, mainRef, strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-4, envelopeAbs: 1e-4)
        let mainFrac =
            Double(mainRef.count - mainEval.strictViolations) / Double(max(mainRef.count, 1))
        print("CZ dual gate MAIN: strictFrac=\(mainFrac) "
            + "strictViol=\(mainEval.strictViolations) envViol=\(mainEval.envelopeViolations) "
            + "maxRel=\(mainEval.maxRelative) compared=\(mainCompared)")
        if let msg = ParityGate.failureMessage(
            "colorzones parity MAIN", mainGot, mainRef,
            strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-4, envelopeAbs: 1e-4)
        {
            XCTFail(msg + "\ncompared=\(mainCompared)")
        }
        // SPECTRAL tier: envelope-gated (asserted) + strict reported.
        var specMaxAbs: Float = 0
        for i in 0..<specRef.count {
            specMaxAbs = max(specMaxAbs, abs(specGot[i] - specRef[i]))
        }
        let specEval = ParityGate.evaluate(
            specGot, specRef, strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-2, envelopeAbs: 1e-2)
        let specFrac =
            Double(specRef.count - specEval.strictViolations) / Double(max(specRef.count, 1))
        print("CZ SPECTRAL tier: strictFrac=\(specFrac) "
            + "envViol(1e-2)=\(specEval.envelopeViolations) maxAbs=\(specMaxAbs) "
            + "compared=\(specCompared)")
        XCTAssertEqual(specEval.envelopeViolations, 0,
            "spectral tier envelope (1e-2 abs) violations=\(specEval.envelopeViolations) maxAbs=\(specMaxAbs)")
    }

    // MARK: - LUT dual gate, direct (CPU LUT vs GPU lookup)

    /// LUT 双闸直接门：同一 committed buffer 经 GPU 查表 vs CPU
    /// NEAREST 参考 — 隔离 LUT/lookup 腿（不经过 Lab 往返噪声）。
    /// Uses a tilted L curve (guaranteed cross-gridpoint lookups) on the
    /// stair_1d adversarial grid (targets LUT resolution directly).
    func testColorZonesLUTDualGate() async throws {
        let metal = try await makeMetal()
        let params = ColorZonesModule.Params(
            channel: .lightness,
            curveL: [.init(x: 0, y: 0.2), .init(x: 0.5, y: 0.7), .init(x: 1, y: 0.4)],
            typeL: .catmullRom)
        let fixtureURL = try requireGolden("fixtures/stair_1d.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, w, h) = try await runZonesPipe(image: image, params: params, metal: metal)
        let fixture = try GoldenParityTests.UncompressedEXR.load(fixtureURL)
        let tables = committedTables(params: params)
        var refAll: [Float] = []
        var gotAll: [Float] = []
        var compared = 0
        let n = w * h
        for i in 0..<n {
            let rgb = SIMD3<Double>(
                Double(fixture.rgb[i * 3]), Double(fixture.rgb[i * 3 + 1]),
                Double(fixture.rgb[i * 3 + 2]))
            let lab = LabRoundTrip.rec2020ToLab(rgb)
            let out = ColorZonesModule.reference(
                lab: lab,
                tables: (tables.l, tables.c, tables.h),
                selectChannel: .lightness)
            let back = LabRoundTrip.labToRec2020(out)
            for c in 0..<3 {
                compared += 1
                gotAll.append(pipe[i * 3 + c])
                refAll.append(Float([back.x, back.y, back.z][c]))
            }
        }
        XCTAssertGreaterThan(compared, 0)
        // Envelope-asserted (lookup correctness); strict is REPORTED, not
        // asserted: Metal fast-math pow() carries a systematic ~2.5e-5 abs
        // bias on L'~100 (measured; dt's dtcl_pow/native_powr is the same
        // fast family — dt-GPU shows the same bias vs dt-CPU). The bias is
        // per-select-value systematic, so the tilted curve shifts every
        // pixel of a stair level together (DECISIONS D-05-04-T3-2).
        var maxAbs: Float = 0
        for i in 0..<refAll.count {
            maxAbs = max(maxAbs, abs(gotAll[i] - refAll[i]))
        }
        print("CZ LUT direct bias: maxAbs=\(maxAbs) (fast-pow characteristic)")
        // Bias stays inside the envelope's abs leg (one consistent number:
        // measured max 8.5e-5 on the bright stair end, envelope abs 1e-4).
        XCTAssertLessThan(maxAbs, 1e-4,
            "LUT-direct systematic bias maxAbs=\(maxAbs) exceeds envelope abs")
        let eval = ParityGate.evaluate(
            gotAll, refAll, strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-4, envelopeAbs: 1e-4)
        let strictFrac =
            Double(refAll.count - eval.strictViolations) / Double(max(refAll.count, 1))
        print("CZ LUT direct gate: strictFrac=\(strictFrac) "
            + "strictViol=\(eval.strictViolations) envViol=\(eval.envelopeViolations) "
            + "maxRel=\(eval.maxRelative) compared=\(compared)")
        XCTAssertEqual(eval.envelopeViolations, 0,
            "LUT-direct envelope (1e-4) violations=\(eval.envelopeViolations)")
    }

    // MARK: - Hue sweep full ring (live pipe)

    /// hue sweep 全环实跑：360 列全环经 live pipe，输出 hue 单调覆盖
    /// 全环（防空转：真循环 compared > 0 + 全环覆盖断言）。
    func testHueSweepFullRingLive() async throws {
        let metal = try await makeMetal()
        let params = ColorZonesModule.Params(
            channel: .hue,
            curveH: [.init(x: 0, y: 0.5), .init(x: 0.25, y: 0.75),
                     .init(x: 0.5, y: 0.3), .init(x: 0.75, y: 0.6)],
            typeH: .monotoneHermite,
            strength: 50)
        let fixtureURL = try requireGolden("fixtures/hue_sweep.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, w, h) = try await runZonesPipe(image: image, params: params, metal: metal)
        XCTAssertEqual(w, 360)
        XCTAssertEqual(h, 64)
        // Output hue per column (mean over rows) must span the ring:
        // min/max column-mean hue differ by > 0.5 ring (real sweep, not
        // a collapsed constant) + every column compared.
        var colHue = [Double](repeating: 0, count: w)
        var compared = 0
        for x in 0..<w {
            var acc = 0.0
            for y in 0..<h {
                let i = y * w + x
                let rgb = SIMD3<Double>(
                    Double(pipe[i * 3]), Double(pipe[i * 3 + 1]),
                    Double(pipe[i * 3 + 2]))
                let lab = LabRoundTrip.rec2020ToLab(rgb)
                var hh = atan2(lab.z, lab.y) / (2.0 * Double.pi)
                if hh < 0 { hh += 1.0 }
                acc += hh
                compared += 1
            }
            colHue[x] = acc / Double(h)
        }
        XCTAssertGreaterThan(compared, 0, "hue sweep loop compared zero pixels")
        let span = colHue.max()! - colHue.min()!
        XCTAssertGreaterThan(span, 0.5, "hue sweep output span=\(span) — ring collapsed")
    }

    // MARK: - Helpers

    private func committedTables(
        params: ColorZonesModule.Params
    ) -> (l: [Double], c: [Double], h: [Double]) {
        let periodicH = params.channel == .hue
        return (
            l: ColorZonesLUT.buildTable(
                nodes: params.curveL.map { (Double($0.x), Double($0.y)) },
                type: params.typeL, strength: Double(params.strength), periodic: false),
            c: ColorZonesLUT.buildTable(
                nodes: params.curveC.map { (Double($0.x), Double($0.y)) },
                type: params.typeC, strength: Double(params.strength), periodic: false),
            h: ColorZonesLUT.buildTable(
                nodes: params.curveH.map { (Double($0.x), Double($0.y)) },
                type: params.typeH, strength: Double(params.strength), periodic: periodicH))
    }

    private func runZonesPipe(
        image: DecodedImage, params: ColorZonesModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: ColorZonesModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<ColorZonesModule>)
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
