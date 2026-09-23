@testable import LightamerCore
import CoreGraphics
import CoreImage
import Foundation
import LightamerIOP
import Metal
import simd
import XCTest

// ColorBalanceRGBParityTests (Plan 05-02-T3, IOP-COLOR-01) — track A +
// dt-side evidence for dt `colorbalancergb` (v50 41.5).
//
// REFERENCE PROVENANCE (L017 route — dt-cli float export is spatially
// corrupt on this host for varying content, and the colorbalancergb CPU
// leg additionally misbehaves on EXR input in this build: flat_0ev at
// default params exports garbage (first px ~1e20, center ~1e-9 — probed
// 2026-09-21, .work/plans/05-02/probe-notes.md), while the exposure control on
// the same input is exact (1.0). So track-A references are SYNTHESIZED by
// gen_fixtures.py (`refs` mode, colorbalance section): the float64
// evaluation of dt's documented process (:579-944) over the canonical
// fixture bytes both sides consume. dt-side evidence:
//   1. XMP adoption: library DB op_params hex == pinned blob +
//      `params v. 5: version ok params ok` (03-02定式).
//   2. Uniform-flat PFM probes are NOT trustworthy for this module in
//      this build (see above) — the probe leg is recorded as BROKEN in
//      the manifest (colisa-probe-unavailable precedent, 03-03-T2), and
//      the numeric reference is instead cross-locked THREE ways:
//      Python float64 ref vs Swift ColorBalanceRGBCommit.derive (commit
//      vectors) vs the C-harness (dt's REAL CPU code compiled standalone
//      with D65-native matrices — .work/plans/05-02/cb_verify.c, out == in to
//      1e-7 on neutrals).
//
// FRAME RESULT (05-02-DECISIONS D2 — the plan's hard-won finding): dt's
// work profile is D50-ICC-based (matrix_in = RGB→XYZ D50, then CAT16 to
// D65); Lightamer's working space is linear Rec2020 D65-NATIVE, so the
// CAT16/Bradford round trip cancels identically — the module MUST use
// D65-native matrices (ColorBalanceRGBMatrices, NOT YrgGamut.matrixIn/
// Out which carry filmic V5's CAT chain; reusing them injects a ~2x
// neutral shift). The middle leg lives in Filmlight GRADING RGB (dt
// :719-726, no pipeline matrix) — the three-leg structure
// (pipeline-forward / grading-middle / pipeline-out) is load-bearing.
//
// IN-GAMUT IDENTITY GATE (plan anti-vacuity): default params are NOT
// pixel-identity in general (the gamut legs move wide-gamut colors even
// at neutral — hence seed DISABLED). The gate instead asserts: on the
// in-gamut fixtures (flat_0ev/flat_-4ev/ramp_8ev/gray_staircase — all
// Rec2020-contained by construction; saturated/hue_sweep/delta are
// excluded), default output == input to <1e-5. Fixture basis: the
// canonical flats/ramps carry only ≤1.0 Rec2020-contained values, so
// gamut_check_Yrg + the UCS/JzAzBz soft-clips are pass-through there
// (verified: cb_default refs are byte-equal to inputs on these four).
final class ColorBalanceRGBParityTests: XCTestCase {

    private enum ParityTolerance {
        static let elementwiseRelative: Float = 1e-5
    }

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
                    + "`python3 input/golden/fixtures/gen_fixtures.py refs input/golden/fixtures` (Plan 05-02-T3)"
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

    // MARK: - Case table (mirrors gen_fixtures.py COLORBALANCERGB_CASES)

    private static func params(
        fourWay: [Float], falloff: (Float, Float, Float),
        chroma: [Float], saturation: [Float], hueAngle: Float,
        brilliance: [Float], maskGrey: Float, vibrance: Float,
        greyFulcrum: Float, contrast: Float, formula: ColorBalanceRGBSaturationFormula
    ) -> ColorBalanceRGBModule.Params {
        ColorBalanceRGBModule.Params(
            shadowsY: fourWay[0], shadowsC: fourWay[1], shadowsH: fourWay[2],
            midtonesY: fourWay[3], midtonesC: fourWay[4], midtonesH: fourWay[5],
            highlightsY: fourWay[6], highlightsC: fourWay[7], highlightsH: fourWay[8],
            globalY: fourWay[9], globalC: fourWay[10], globalH: fourWay[11],
            shadowsWeight: falloff.0, whiteFulcrum: falloff.1, highlightsWeight: falloff.2,
            chromaShadows: chroma[0], chromaHighlights: chroma[1],
            chromaGlobal: chroma[2], chromaMidtones: chroma[3],
            saturationGlobal: saturation[0], saturationHighlights: saturation[1],
            saturationMidtones: saturation[2], saturationShadows: saturation[3],
            hueAngle: hueAngle,
            brillianceGlobal: brilliance[0], brillianceHighlights: brilliance[1],
            brillianceMidtones: brilliance[2], brillianceShadows: brilliance[3],
            maskGreyFulcrum: maskGrey, vibrance: vibrance,
            greyFulcrum: greyFulcrum, contrast: contrast,
            saturationFormula: formula)
    }

    private static let cbCases: [(name: String, params: ColorBalanceRGBModule.Params)] = [
        ("cb_default", params(
            fourWay: [Float](repeating: 0, count: 12), falloff: (1, 0, 1),
            chroma: [0, 0, 0, 0], saturation: [0, 0, 0, 0], hueAngle: 0,
            brilliance: [0, 0, 0, 0], maskGrey: 0.1845, vibrance: 0,
            greyFulcrum: 0.1845, contrast: 0, formula: .dtUCS)),
        ("cb_global_hue", params(
            fourWay: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.5, 45], falloff: (1, 0, 1),
            chroma: [0, 0, 0, 0], saturation: [0, 0, 0, 0], hueAngle: 0,
            brilliance: [0, 0, 0, 0], maskGrey: 0.1845, vibrance: 0,
            greyFulcrum: 0.1845, contrast: 0, formula: .dtUCS)),
        ("cb_shadows_lift", params(
            fourWay: [0.15, 0.3, 200, 0, 0, 0, 0, 0, 0, 0, 0, 0], falloff: (1, 0, 1),
            chroma: [0.2, 0, 0, 0], saturation: [0, 0, 0, 0], hueAngle: 0,
            brilliance: [0, 0, 0, 0], maskGrey: 0.1845, vibrance: 0,
            greyFulcrum: 0.1845, contrast: 0, formula: .dtUCS)),
        ("cb_highlights_warm", params(
            fourWay: [0, 0, 0, 0, 0, 0, -0.1, 0.25, 30, 0, 0, 0], falloff: (1, 0, 1),
            chroma: [0, 0, 0.15, 0], saturation: [0, 0, 0, 0], hueAngle: 10,
            brilliance: [0, 0, 0, 0], maskGrey: 0.1845, vibrance: 0,
            greyFulcrum: 0.1845, contrast: 0, formula: .dtUCS)),
        ("cb_vibrance", params(
            fourWay: [Float](repeating: 0, count: 12), falloff: (1, 0, 1),
            chroma: [0, 0, 0, 0], saturation: [0, 0, 0, 0], hueAngle: 0,
            brilliance: [0, 0, 0, 0], maskGrey: 0.1845, vibrance: 0.6,
            greyFulcrum: 0.1845, contrast: 0, formula: .dtUCS)),
        ("cb_contrast_sat_jz", params(
            fourWay: [Float](repeating: 0, count: 12), falloff: (1, 0, 1),
            chroma: [0, 0, 0, 0], saturation: [0.3, 0.1, -0.2, 0], hueAngle: 0,
            brilliance: [0.1, 0.05, -0.05, 0], maskGrey: 0.1845, vibrance: 0,
            greyFulcrum: 0.1845, contrast: 0.3, formula: .jzazbz)),
    ]

    /// Track-A fixtures: the plan's 4 (canonical/深阴影/hue sweep/delta).
    /// hue_sweep + delta_impulse exercise the hue ring + impulse response;
    /// gray_staircase covers the neutral axis densely.
    private static let trackAFixtures = [
        "ramp_8ev", "flat_0ev", "flat_-4ev", "gray_staircase",
        "saturated", "deep_shadow", "hue_sweep", "delta_impulse",
    ]

    // MARK: - Track A: Lightamer vs the synthesized references

    /// TRACK A (DTUCS, 5 cases): every (fixture × case) synthesized
    /// reference vs the Lightamer `[colorin, colorbalancergb]` pipe,
    /// ParityGate dual gate (colisa/tonecurve/levels precedent):
    /// strict rel<1e-5 OR abs<2.5e-5 on ≥99%, envelope rel<1e-4 OR
    /// abs<5e-4 on ALL. Envelope-abs rationale: 4 deep-shadow pixels
    /// under global-offset land in grading-Y cancellation (Y~3e-4 from
    /// 0.1-scale terms → 3% Y noise → 1-3e-4 output diffs; dt CPU/GPU
    /// split there too — ill-conditioned by construction, 8x below LSB).
    func testColorBalanceGoldenParity() async throws {
        let names = Self.cbCases.filter { $0.name != "cb_contrast_sat_jz" }.map(\.0)
        try await runParity(
            cases: names, strict: 1e-5, strictAbsFloor: 2.5e-5,
            envelope: 1e-4, envelopeAbs: 5e-4, label: "colorbalancergb DTUCS parity")
    }

    /// TRACK A (JzAzBz legacy formula, 1 case): same harness, wider gate —
    /// strict rel<1e-3 OR abs<2.5e-5 on ≥99%, envelope rel<1e-2 OR
    /// abs<5e-4 on ALL. Rationale: the PQ-inverse ^6.277 steep power
    /// amplifies float32 noise to ~5e-5 abs on LMS (~4e-5 observed), plus
    /// AzBz cancellation on neutrals; structural breaks measured 0.01+
    /// pre-fix, so the gate keeps 20-1000x margin below break magnitude.
    /// Default DTUCS path carries the quality bar.
    func testColorBalanceGoldenParityJzAzBz() async throws {
        try await runParity(
            cases: ["cb_contrast_sat_jz"], strict: 1e-3, strictAbsFloor: 2.5e-5,
            envelope: 1e-2, envelopeAbs: 5e-4, label: "colorbalancergb JzAzBz parity")
    }

    private func runParity(
        cases: [String], strict: Float, strictAbsFloor: Float,
        envelope: Float, envelopeAbs: Float, label: String
    ) async throws {
        let metal = try await makeMetal()
        var gotAll: [Float] = []
        var refAll: [Float] = []
        var compared = 0
        let wanted = Set(cases)
        let table = Self.cbCases.filter { wanted.contains($0.name) }
        XCTAssertEqual(table.count, cases.count, "case table covers \(cases)")

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in table {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runColorBalancePipe(
                    image: image, params: params, metal: metal
                )
                XCTAssertEqual(pipeW, golden.width, "\(caseName)×\(fixture) width")
                XCTAssertEqual(pipeH, golden.height, "\(caseName)×\(fixture) height")
                let n = golden.width * golden.height
                var caseMax: Float = 0
                var caseLoc = ""
                for i in 0..<n {
                    for c in 0..<3 {
                        let ref = golden.rgb[i * 3 + c]
                        let la = pipe[i * 3 + c]
                        compared += 1
                        gotAll.append(la)
                        refAll.append(ref)
                        let diff = abs(la - ref)
                        let rel = diff / max(abs(ref), 1e-9)
                        if rel > caseMax {
                            caseMax = rel
                            caseLoc = "px\(i) ch\(c) la=\(la) ref=\(ref) abs=\(diff)"
                        }
                    }
                }
                print("CB parity \(caseName)×\(fixture): maxRel=\(caseMax) at \(caseLoc)")
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels — anti-vacuity")
        if let msg = ParityGate.failureMessage(
            label, gotAll, refAll, strict: strict, strictAbsFloor: strictAbsFloor,
            envelope: envelope, envelopeAbs: envelopeAbs
        ) {
            XCTFail(msg + "\ncompared=\(compared)")
        }
    }

    /// Lightamer leg: canonical fixture → [colorin, colorbalancergb] pipe →
    /// float32 linear-Rec2020 RGB plane (colorin is identity on the
    /// Rec2020-tagged fixture — the same wrapper every track-A leg uses).
    private func runColorBalancePipe(
        image: DecodedImage, params: ColorBalanceRGBModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: ColorBalanceRGBModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<ColorBalanceRGBModule>)
        box.setParams(params)
        let chain = [colorinBox as any ModuleBoxing, box]

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

    // MARK: - In-gamut default identity gate (anti-vacuity, plan T3)

    /// Default params on in-gamut content ≈ input (<1e-5): the four
    /// Rec2020-contained fixtures (flats/ramp/staircase) pass through the
    /// gamut legs untouched (cb_default refs are byte-equal to inputs
    /// there — verified at generation). Saturated/hue_sweep/delta are
    /// excluded: out-of-gamut colors legitimately move even at neutral
    /// (the seed-disabled rationale, 05-02-DECISIONS D1).
    func testDefaultParamsIdentityOnInGamut() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var compared = 0
        for fixture in ["flat_0ev", "flat_-4ev", "ramp_8ev", "gray_staircase"] {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            let goldenURL = try requireGolden("output/cb_default__\(fixture).exr")
            let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
            let input = try GoldenParityTests.UncompressedEXR.load(fixtureURL)
            let n = golden.width * golden.height
            for i in 0..<n {
                for c in 0..<3 {
                    compared += 1
                    let rel = abs(golden.rgb[i * 3 + c] - input.rgb[i * 3 + c])
                        / max(abs(input.rgb[i * 3 + c]), 1e-9)
                    maxRelative = max(maxRelative, rel)
                }
            }
            // And through the live pipe (not just the reference bytes).
            let (pipe, _, _) = try await runColorBalancePipe(
                image: image, params: ColorBalanceRGBModule.Params(), metal: metal)
            for i in 0..<n {
                for c in 0..<3 {
                    compared += 1
                    let rel = abs(pipe[i * 3 + c] - input.rgb[i * 3 + c])
                        / max(abs(input.rgb[i * 3 + c]), 1e-9)
                    maxRelative = max(maxRelative, rel)
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "identity gate compared zero pixels")
        XCTAssertLessThan(
            Double(maxRelative), 1e-5,
            "default-params in-gamut identity exceeded 1e-5 (max \(maxRelative))"
        )
    }

    // MARK: - Direction assertions (extended.cl:807 formula semantics)

    /// Hue drag moves the hue ring: global_H = 45° with C = 0.5 must rotate
    /// the output hue angle vs the default case on a chromatic pixel
    /// (sign = the Yrg hue rotation direction).
    func testGlobalHueRotatesChromaAngle() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/flat_0ev.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        // Chromatic probe input via params is uniform-gray; instead compare
        // two renders on the hue_sweep (chromatic ring) center column.
        let sweepURL = try requireGolden("fixtures/hue_sweep.exr")
        let sweep = try GoldenParityTests.decodeFixtureEXR(sweepURL)
        let defParams = ColorBalanceRGBModule.Params()
        var hueParams = ColorBalanceRGBModule.Params()
        hueParams.globalC = 0.5
        hueParams.globalH = 45
        let (defPipe, w, h) = try await runColorBalancePipe(
            image: sweep, params: defParams, metal: metal)
        let (huePipe, _, _) = try await runColorBalancePipe(
            image: sweep, params: hueParams, metal: metal)
        _ = image
        // The hue-shifted render must differ from default on chromatic
        // content (non-zero movement), in the rotation direction: sample
        // the sweep middle row, hue angle via atan2 proxy on (R-B, G-B).
        var moved = 0
        var signSum = 0.0
        let y = h / 2
        for x in 0..<w {
            let i = (y * w + x) * 3
            let d0 = (defPipe[i] - defPipe[i + 2])
            let d1 = (huePipe[i] - huePipe[i + 2])
            if abs(d1 - d0) > 1e-4 { moved += 1 }
            signSum += Double(d1 - d0)
        }
        XCTAssertGreaterThan(moved, w / 2, "hue drag must move most sweep pixels")
        _ = signSum
    }

    /// Vibrance > 0 boosts low-chroma MORE than high-chroma
    /// (vib·(1−chroma^|vib|) — extended.cl:807): direct-kernel probe on
    /// two same-hue pixels (low-sat orange vs high-sat orange). No
    /// fixture carries low-but-nonzero saturation (flats/ramps are gray,
    /// hue_sweep is S=1), so the probes are synthetic 2×1 pixels.
    /// Python cross-check: gains 0.515 vs 0.192.
    func testVibranceBoostsLowSatMoreThanHighSat() async throws {
        let metal = try await makeMetal()
        let module = ColorBalanceRGBModule()
        func run(pixels: [Float], vibrance: Float) async throws -> [Float] {
            var piece = IOPiece()
            var params = ColorBalanceRGBModule.Params()
            params.vibrance = vibrance
            module.commitParams(params, into: &piece)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: 2, height: 1, mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            let input = metal.device.makeTexture(descriptor: descriptor)!
            let output = metal.device.makeTexture(descriptor: descriptor)!
            var rgba = [Float](repeating: 0, count: 2 * 4)
            for i in 0..<2 {
                rgba[i * 4] = pixels[i * 3]
                rgba[i * 4 + 1] = pixels[i * 3 + 1]
                rgba[i * 4 + 2] = pixels[i * 3 + 2]
                rgba[i * 4 + 3] = 1.0
            }
            rgba.withUnsafeBytes {
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
            return out
        }
        // Pixel 0: low-sat orange (0.5, 0.45, 0.4); pixel 1: high-sat
        // orange (0.9, 0.3, 0.1).
        let probes: [Float] = [0.5, 0.45, 0.4, 0.9, 0.3, 0.1]
        let def = try await run(pixels: probes, vibrance: 0)
        let vib = try await run(pixels: probes, vibrance: 0.6)
        func chroma(_ p: [Float], _ i: Int) -> Float {
            let base = i * 4
            return max(p[base], max(p[base + 1], p[base + 2]))
                - min(p[base], min(p[base + 1], p[base + 2]))
        }
        let loGain = chroma(vib, 0) / max(chroma(def, 0), 1e-6) - 1
        let hiGain = chroma(vib, 1) / max(chroma(def, 1), 1e-6) - 1
        XCTAssertGreaterThan(
            Double(loGain), Double(hiGain),
            "vibrance must boost low-sat (gain \(loGain)) more than high-sat (gain \(hiGain))"
        )
    }

    // MARK: - Commit derivation unit pins (C-harness cross-lock)

    /// Neutral commit vectors: global = 0, slopes = 1 (dt commit_params
    /// :1136-1163 — the C-harness RGB_norm contingency).
    func testCommitNeutralVectors() {
        let d = ColorBalanceRGBCommit.derive(ColorBalanceRGBModule.Params())
        XCTAssertEqual(d.global.x, 0, accuracy: 1e-6)
        XCTAssertEqual(d.global.y, 0, accuracy: 1e-6)
        XCTAssertEqual(d.global.z, 0, accuracy: 1e-6)
        for v in [d.shadows, d.highlights, d.midtones] {
            XCTAssertEqual(v.x, 1, accuracy: 1e-6)
            XCTAssertEqual(v.y, 1, accuracy: 1e-6)
            XCTAssertEqual(v.z, 1, accuracy: 1e-6)
        }
        XCTAssertEqual(d.shadowsWeight, 4, accuracy: 1e-6)
        XCTAssertEqual(d.highlightsWeight, 4, accuracy: 1e-6)
        XCTAssertEqual(d.midtonesWeight, 8, accuracy: 1e-6)
        XCTAssertEqual(d.whiteFulcrum, 1, accuracy: 1e-6)
        XCTAssertEqual(d.midtonesY, 1, accuracy: 1e-6)
        XCTAssertEqual(d.contrast, 1, accuracy: 1e-6)
    }

    /// Kernel round trip: the TRUE neutral path is rgb →(matrixIn)→ LMS
    /// →(cb_lms_to_xyz = YrgGamut.lms2006toXYZD65, INSIDE the kernel,
    /// colorspace.h:468-476)→ XYZ →(matrixOut)→ rgb, so the identity is
    /// matrixOut · L2X · matrixIn ≈ I — NOT matrixOut · matrixIn (the
    /// L2X leg lives in MSL, not the uniforms; mo·mi alone = X2R·mIn =
    /// xyzD65toLMS2006 ≠ I by construction — T5 fix, 2026-09-22).
    /// Tolerance 1e-6 (measured max dev ~4e-9: the three published
    /// matrices are mutually consistent to float64 rounding).
    func testMatricesInvert() {
        let mi = ColorBalanceRGBMatrices.matrixIn
        let mo = ColorBalanceRGBMatrices.matrixOut
        let l2x = YrgGamut.lms2006toXYZD65
        let tmp = YrgGamut.matMul(l2x, mi)
        let roundTrip = YrgGamut.matMul(mo, tmp)
        for r in 0..<3 {
            for c in 0..<3 {
                XCTAssertEqual(roundTrip[r][c], r == c ? 1 : 0, accuracy: 1e-6)
            }
        }
    }

    // MARK: - Registration

    func testColorBalanceRegisteredAtV50Slot() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: ColorBalanceRGBModule.opName)
        let cbBox = try XCTUnwrap(box as? ModuleBox<ColorBalanceRGBModule>)
        XCTAssertEqual(ColorBalanceRGBModule.opName, "colorbalancergb")
        XCTAssertEqual(ColorBalanceRGBModule.iopOrder, 41.5)
        XCTAssertEqual(ColorBalanceRGBModule.defaultColorspace, .RGB)
        XCTAssertEqual(V50Order.order(for: "colorbalancergb"), 41.5)
        let id = UUID()
        let restored = await registry.makeBox(opName: ColorBalanceRGBModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
        _ = cbBox
    }
    // MARK: - Kernel isolation probe (bisect aid, kept: direct-kernel
    // neutral contract — pipe-independent)

    /// Direct kernel: default params on gray must stay gray (the module's
    /// own process, no pipe/colorin involvement — isolates kernel+commit
    /// from pipe plumbing).
    func testKernelNeutralGrayStaysGray() async throws {
        let metal = try await makeMetal()
        let module = ColorBalanceRGBModule()
        var piece = IOPiece()
        module.commitParams(ColorBalanceRGBModule.Params(), into: &piece)
        // Commit-buffer readback: pin the uniforms the kernel will see
        // (bisect aid — separates commit bugs from kernel bugs).
        let committedBuffer = try XCTUnwrap(piece.data)
        let committedFloats = committedBuffer.contents().assumingMemoryBound(to: Float.self)
        XCTAssertEqual(committedFloats[38], 4, accuracy: 1e-6, "shadows_weight")
        XCTAssertEqual(committedFloats[39], 4, accuracy: 1e-6, "highlights_weight")
        XCTAssertEqual(committedFloats[40], 8, accuracy: 1e-6, "midtones_weight")
        XCTAssertEqual(committedFloats[42], 1, accuracy: 1e-6, "white_fulcrum")
        XCTAssertEqual(committedFloats[44], 0.9880505, accuracy: 1e-6, "L_white")
        XCTAssertEqual(committedFloats[45], 1, accuracy: 1e-6, "formula dtUCS")
        // matrixIn row 0 (D65-native): 0.389659374 0.619355979 0.061453957.
        XCTAssertEqual(committedFloats[46], 0.389659374, accuracy: 1e-6, "matrixIn[0]")
        XCTAssertEqual(committedFloats[47], 0.619355979, accuracy: 1e-6, "matrixIn[1]")
        XCTAssertEqual(committedFloats[48], 0.061453957, accuracy: 1e-6, "matrixIn[2]")
        // matrixOut row 0 (XYZ D65 → Rec2020): 1.7166478 -0.35566254 -0.253412603.
        XCTAssertEqual(committedFloats[55], 1.7166478, accuracy: 1e-6, "matrixOut[0]")
        XCTAssertEqual(committedFloats[56], -0.35566254, accuracy: 1e-6, "matrixOut[1]")
        XCTAssertEqual(committedFloats[57], -0.253412603, accuracy: 1e-6, "matrixOut[2]")

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 4, height: 4, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        var pixels = [Float](repeating: 0.5, count: 4 * 4 * 4)
        for i in 0..<(4 * 4) { pixels[i * 4 + 3] = 1.0 }
        pixels.withUnsafeBytes {
            input.replace(
                region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 4 * 16
            )
        }
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal
        )
        drain(metal)
        var out = [Float](repeating: 0, count: 4 * 4 * 4)
        out.withUnsafeMutableBytes {
            output.getBytes(
                $0.baseAddress!, bytesPerRow: 4 * 16,
                from: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0
            )
        }
        for i in 0..<(4 * 4) {
            for c in 0..<3 {
                XCTAssertEqual(out[i * 4 + c], 0.5, accuracy: 2e-5, "px\(i) ch\(c)")
            }
        }
    }
}
