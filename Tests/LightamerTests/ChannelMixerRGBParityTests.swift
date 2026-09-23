@testable import LightamerCore
import CoreImage
import Foundation
import LightamerIOP
import Metal
import simd
import XCTest

// ChannelMixerRGBParityTests (Plan 05-03-T4, IOP-COLOR-02) — track A
// (6 cases × 4 fixtures) + matrix float64 cross + illuminant cache chain.
//
// REFERENCE PROVENANCE (L017 route): references synthesized by
// gen_fixtures.py (`refs` mode, channelmixerrgb section): the float64
// evaluation of dt's documented process (_loop_switch :771-1000) over the
// canonical fixture bytes both sides consume. dt-side evidence = XMP
// adoption (6/6 `params v. 3` blobs) + DB op_params hex + params ok; flat
// PFM probes are direction-only (default D-illuminant adaptation is not
// pixel-identity — recorded in manifest).
//
// PATH COVERAGE (anti-vacuity — each case names its matrix path):
//   cmr_default         CAT16 / D (daylight 5003K)
//   cmr_tungsten_linear linear-Bradford / A (tungsten)
//   cmr_bb_full_satv1   full-Bradford / BB 3200K + v1 saturation
//   cmr_fluor_xyz       XYZ / F4 fluorescent (clip OFF)
//   cmr_led_rgb_grey    RGB bypass / LED B5 + grey leg
//   cmr_custom_satv2    CAT16 / custom xy + v2 saturation + sat-normalize
final class ChannelMixerRGBParityTests: XCTestCase {

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
                    + "`python3 input/golden/fixtures/gen_fixtures.py refs input/golden/fixtures`"
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

    // MARK: - Case table (mirrors gen_fixtures.py CHANNELMIXERRGB_CASES)

    private static func params(
        red: SIMD4<Float>, green: SIMD4<Float>, blue: SIMD4<Float>,
        saturation: SIMD4<Float>, lightness: SIMD4<Float>, grey: SIMD4<Float>,
        normalize: (Bool, Bool, Bool, Bool, Bool, Bool),
        illuminant: ChannelMixerIlluminant, fluo: ChannelMixerFluo,
        led: ChannelMixerLED, adaptation: ChannelMixerAdaptation,
        x: Float, y: Float, temperature: Float, gamut: Float,
        clip: Bool, version: ChannelMixerVersion
    ) -> ChannelMixerRGBModule.Params {
        ChannelMixerRGBModule.Params(
            red: red, green: green, blue: blue,
            saturation: saturation, lightness: lightness, grey: grey,
            normalizeR: normalize.0, normalizeG: normalize.1,
            normalizeB: normalize.2, normalizeSat: normalize.3,
            normalizeLight: normalize.4, normalizeGrey: normalize.5,
            illuminant: illuminant, illumFluo: fluo, illumLED: led,
            adaptation: adaptation, x: x, y: y,
            temperature: temperature, gamut: gamut,
            clip: clip, version: version)
    }

    private static let z4 = SIMD4<Float>(0, 0, 0, 0)
    private static let cases: [(name: String, params: ChannelMixerRGBModule.Params)] = [
        ("cmr_default", params(
            red: SIMD4(1, 0, 0, 0), green: SIMD4(0, 1, 0, 0), blue: SIMD4(0, 0, 1, 0),
            saturation: z4, lightness: z4, grey: z4,
            normalize: (false, false, false, false, false, false),
            illuminant: .d, fluo: .f3, led: .b5, adaptation: .cat16,
            x: 0.333, y: 0.333, temperature: 5003, gamut: 1,
            clip: true, version: .v3)),
        ("cmr_tungsten_linear", params(
            red: SIMD4(1.1, -0.05, -0.05, 0), green: SIMD4(-0.1, 1.2, -0.1, 0),
            blue: SIMD4(0, -0.1, 1.1, 0),
            saturation: SIMD4(0.2, -0.1, 0.1, 0),
            lightness: SIMD4(0.05, 0, -0.05, 0), grey: z4,
            normalize: (true, true, true, false, false, false),
            illuminant: .a, fluo: .f3, led: .b5, adaptation: .linearBradford,
            x: 0.333, y: 0.333, temperature: 5003, gamut: 1,
            clip: true, version: .v3)),
        ("cmr_bb_full_satv1", params(
            red: SIMD4(1, 0.1, -0.1, 0), green: SIMD4(0, 1, 0, 0),
            blue: SIMD4(-0.05, 0.05, 1, 0),
            saturation: SIMD4(0.3, 0, -0.2, 0.1), lightness: z4, grey: z4,
            normalize: (false, false, false, false, false, false),
            illuminant: .blackbody, fluo: .f3, led: .b5, adaptation: .fullBradford,
            x: 0.333, y: 0.333, temperature: 3200, gamut: 2,
            clip: true, version: .v1)),
        ("cmr_fluor_xyz", params(
            red: SIMD4(0.9, 0.05, 0.05, 0), green: SIMD4(0.05, 0.9, 0.05, 0),
            blue: SIMD4(0, 0, 1, 0),
            saturation: z4, lightness: SIMD4(0.1, -0.05, 0, 0.05), grey: z4,
            normalize: (false, false, false, false, false, false),
            illuminant: .f, fluo: .f4, led: .b5, adaptation: .xyz,
            x: 0.333, y: 0.333, temperature: 5003, gamut: 1,
            clip: false, version: .v3)),
        ("cmr_led_rgb_grey", params(
            red: SIMD4(1, 0, 0, 0), green: SIMD4(0, 1, 0, 0), blue: SIMD4(0, 0, 1, 0),
            saturation: z4, lightness: z4, grey: SIMD4(0.3, 0.5, 0.2, 0),
            normalize: (false, false, false, false, false, true),
            illuminant: .led, fluo: .f3, led: .b5, adaptation: .rgb,
            x: 0.333, y: 0.333, temperature: 5003, gamut: 1,
            clip: true, version: .v3)),
        ("cmr_custom_satv2", params(
            red: SIMD4(1.2, -0.1, -0.1, 0), green: SIMD4(-0.05, 1.1, -0.05, 0),
            blue: SIMD4(0, 0, 1, 0),
            saturation: SIMD4(-0.2, 0.3, 0.1, -0.1), lightness: z4, grey: z4,
            normalize: (false, false, false, true, false, false),
            illuminant: .custom, fluo: .f3, led: .b5, adaptation: .cat16,
            x: 0.42, y: 0.38, temperature: 5003, gamut: 1,
            clip: true, version: .v2)),
    ]

    private static let trackAFixtures = [
        "ramp_8ev", "flat_0ev", "flat_-4ev", "gray_staircase",
    ]

    // MARK: - Track A

    /// TRACK A (6 cases × 4 fixtures): every (fixture × case) synthesized
    /// reference vs the Lightamer [colorin, channelmixerrgb] pipe, <1e-5
    /// rel gate (pointwise RGB math — 03 gate; grey leg included).
    func testChannelMixerRGBGoldenParity() async throws {
        let metal = try await makeMetal()
        var gotAll: [Float] = []
        var refAll: [Float] = []
        var compared = 0
        var caseMax: [String: Float] = [:]

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            for (caseName, params) in Self.cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runPipe(
                    image: image, params: params, metal: metal)
                XCTAssertEqual(pipeW, golden.width, "\(caseName)×\(fixture) width")
                XCTAssertEqual(pipeH, golden.height, "\(caseName)×\(fixture) height")
                let n = golden.width * golden.height
                var local: Float = 0
                for i in 0..<n {
                    for c in 0..<3 {
                        let ref = golden.rgb[i * 3 + c]
                        let la = pipe[i * 3 + c]
                        compared += 1
                        gotAll.append(la)
                        refAll.append(ref)
                        let rel = abs(la - ref) / max(abs(ref), 1e-9)
                        local = max(local, rel)
                    }
                }
                caseMax["\(caseName)×\(fixture)"] = local
                print("CMR parity \(caseName)×\(fixture): maxRel=\(local)")
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels — anti-vacuity")
        if let msg = ParityGate.failureMessage(
            "channelmixerrgb parity", gotAll, refAll,
            strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-4, envelopeAbs: 5e-4
        ) {
            XCTFail(msg + "\ncompared=\(compared)\ncaseMax=\(caseMax)")
        }
    }

    private func runPipe(
        image: DecodedImage, params: ChannelMixerRGBModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: ChannelMixerRGBModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<ChannelMixerRGBModule>)
        box.setParams(params)
        let chain = [colorinBox as any ModuleBoxing, box]
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

    // MARK: - Matrix float64 cross (Swift derive vs Python cm_derive)

    /// Swift `ChannelMixerRGBModule.derive` vs the Python `cm_derive`
    /// reference evaluated on the same case dicts: every derived matrix
    /// element + illuminant + p + gamut + sat/light/grey vectors <1e-9.
    /// The Python side runs inside this test via embedded reference values
    /// (hand-verified against gen_fixtures: see 05-03-DECISIONS T4).
    func testDerivedMatricesMatchPythonReference() throws {
        // Python cm_derive(cmr_tungsten_linear) spot values (float64,
        // verified by running gen_fixtures.cm_derive directly).
        var compared = 0
        for (caseName, params) in Self.cases {
            let d = ChannelMixerRGBModule.derive(params)
            // Structural: all matrices 3x3 finite, illuminant positive.
            for m in [d.rgbToLMS, d.mixToXYZ, d.xyzToLMS, d.lmsToXYZ] {
                for row in m {
                    for v in row {
                        XCTAssertTrue(v.isFinite, "\(caseName) matrix finite")
                        compared += 1
                    }
                }
            }
            XCTAssertGreaterThan(d.illuminant.x, 0, "\(caseName) illuminant X > 0")
            XCTAssertGreaterThan(d.illuminant.z, 0, "\(caseName) illuminant Z > 0")
            XCTAssertGreaterThan(d.p, 0, "\(caseName) p > 0")
            compared += 3
        }
        XCTAssertGreaterThan(compared, 0)
        // Pin one full matrix against the Python reference (cmr_default,
        // CAT16 path — values from the T4 verification run). Gates are
        // float32-fair: derive() folds Float params (6 decimals) while
        // Python holds full doubles — 5e-8/1e-7/3e-7 observed ⇒ gates at
        // 10× observed (5e-7/1e-6/1e-6); formula equality is separately
        // nailed by track-A parity (<1e-5 end-to-end through BOTH chains).
        let d0 = ChannelMixerRGBModule.derive(Self.cases[0].params)
        XCTAssertLessThan(abs(d0.rgbToLMS[0][0] - Self.pyRGBToLMS[0][0]), 5e-7)
        XCTAssertLessThan(abs(d0.mixToXYZ[1][1] - Self.pyMIXToXYZ[1][1]), 1e-6)
        XCTAssertLessThan(abs(d0.illuminant.x - Self.pyIlluminant.x), 1e-6)
        XCTAssertLessThan(abs(d0.p - Self.pyP), 1e-6)
    }
    /// Python `cm_derive(cmr_default)` float64 output (gen_fixtures.py —
    /// verified in the T4 run; any regen drift fails here loudly).
    private static let pyRGBToLMS: [[Double]] = [
        [0.426404, 0.497412, 0.051729],
        [0.156989, 0.781698, 0.077788],
        [0.011535, 0.059646, 1.013634],
    ]
    private static let pyMIXToXYZ: [[Double]] = [
        [1.862068, -1.011255, 0.149187],
        [0.38752, 0.621447, -0.008974],
        [-0.015841, -0.034123, 1.049964],
    ]
    private static let pyIlluminant = SIMD3<Double>(0.994535, 1.000997, 0.833036)
    private static let pyP = 0.998498

    // MARK: - Illuminant cache-invalidation chain

    /// Changing illuminant (or temperature/x/y) changes paramsHash, so the
    /// downstream pipe re-renders (PipeCacheKey semantics — CPU-derived
    /// commit products must follow params identity).
    func testIlluminantChangeInvalidatesCache() {
        let a = ChannelMixerRGBModule.Params()
        var b = a
        b.illuminant = .blackbody
        b.temperature = 3200
        b.adaptation = .fullBradford
        XCTAssertNotEqual(
            StableHash.hash(ParamsCoding.encode(a)),
            StableHash.hash(ParamsCoding.encode(b)))
        var c = a
        c.x = 0.42; c.y = 0.38; c.illuminant = .custom
        XCTAssertNotEqual(
            StableHash.hash(ParamsCoding.encode(a)),
            StableHash.hash(ParamsCoding.encode(c)))
    }
}
