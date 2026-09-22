@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Metal
import XCTest

/// EqualizerParityTests (Plan 04-05-T4/T5) — IOP-DETAIL-04 (op
/// "equalizer", v50 slot 27.0).
///
/// REFERENCE PROVENANCE (L017 route ① — the pyramid is a spatial
/// operator; dt-cli float export is spatially corrupt on this host; the
/// legacy equalizer is DEPRECATED and the contrast-equalizer eaw has no
/// dt-cli leg in this build):
/// - track-A references are CPU-SYNTHESIZED by gen_fixtures.py (`refs`
///   mode, `gen_equalizer_refs`): Lab prep + CHAINED IIR pyramid
///   (σ 1/2/4/8/16, level[i] = blur(predecessor)) + per-band gain
///   recombine in float64, formula-mirrored with
///   `EqualizerKernels.metal` (gate <1e-4, IIR-mix class);
/// - all-zero deltas ⇒ EXACT identity (the D9 blit fast path — the
///   pyramid recombines telescopically only up to float rounding, so the
///   bit-exact gate rides the fast path, not the recombine);
/// - single-band gain ⇒ that band's energy moves (content-level
///   assertion — L020: a ±0.5 fine-band boost must raise the checkerboard
///   edge energy measurably);
///
/// ANTI-VACUUM: every test below runs a comparison loop over real pixels
/// with a compared>0 gate — no vacuous parity passes.
/// L014: every GPU readback drains first.
final class EqualizerParityTests: XCTestCase {

    private enum Tol {
        static let iirMixRelative: Float = 1e-4
        static let iirMixAbsFloor: Float = 1e-4
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
                    + "`python3 input/golden/fixtures/gen_fixtures.py refs input/golden/fixtures` (Plan 04-05-T5)"
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

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    // MARK: - Case book (mirrors gen_fixtures EQUALIZER_CASES)

    private static let equalizerCases: [(name: String, params: EqualizerModule.Params)] = [
        ("equalizer_neutral", EqualizerModule.Params()),
        ("equalizer_fine_boost", EqualizerModule.Params(g0: 0.5)),
        ("equalizer_coarse_boost", EqualizerModule.Params(g4: 0.5)),
        ("equalizer_mid_cut", EqualizerModule.Params(g2: -0.5, g3: -0.5)),
    ]

    private static let trackAFixtures = ["gradient_ramp", "flat_0ev", "flat_-4ev", "checkerboard"]

    // MARK: - Track A: synthesized pyramid parity

    /// TRACK A: every (fixture × case) synthesized reference vs the
    /// Lightamer `[equalizer, colorin]` pipe, per-pixel relative <1e-4
    /// (+1e-4 abs floor — the IIR-mix class gate).
    func testEqualizerGoldenParity() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var compared = 0
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.equalizerCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runEqualizerPipe(
                    image: image, params: params, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size \(pipeW)×\(pipeH) vs golden \(golden.width)×\(golden.height)")
                    continue
                }
                let n = golden.width * golden.height
                compared += n * 3
                for i in 0..<n {
                    for c in 0..<3 {
                        let ref = golden.rgb[i * 3 + c]
                        let got = pipe[i * 3 + c]
                        let diff = abs(got - ref)
                        let rel = diff / max(abs(ref), 1e-3)
                        maxRelative = max(maxRelative, rel)
                        if rel >= Tol.iirMixRelative && diff >= Tol.iirMixAbsFloor,
                           failures.count < 12 {
                            let (x, y) = (i % golden.width, i / golden.width)
                            failures.append(
                                "\(caseName)×\(fixture) (\(x),\(y)) ch\(c): "
                                    + "lightamer=\(got) ref=\(ref) rel=\(rel)"
                            )
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity must compare real pixels (anti-vacuum)")
        XCTAssertTrue(
            failures.isEmpty,
            "equalizer golden parity exceeded \(Tol.iirMixRelative) rel / \(Tol.iirMixAbsFloor) abs "
                + "(max rel \(maxRelative), \(compared) samples):\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// Lightamer leg: canonical fixture → `[equalizer, colorin]` pipe → RGB.
    private func runEqualizerPipe(
        image: DecodedImage, params: EqualizerModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: EqualizerModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<EqualizerModule>)
        box.setParams(params)
        let chain = [box as any ModuleBoxing, colorinBox]
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        await drain(metal) // L014
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

    // MARK: - Identity gate (T4 acceptance: all-zero ⇒ exact)

    /// All-zero deltas ⇒ byte-exact passthrough on varying content (the
    /// D9 blit fast path — every pixel compared).
    func testAllZeroIdentityExact() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, w, h) = try await runEqualizerPipe(
            image: image, params: EqualizerModule.Params(), metal: metal)
        let fixture = try GoldenParityTests.UncompressedEXR.load(fixtureURL)
        XCTAssertEqual(w, fixture.width)
        XCTAssertEqual(h, fixture.height)
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 3) {
            maxDiff = max(maxDiff, abs(pipe[i] - fixture.rgb[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(maxDiff, 0, accuracy: 1e-6)
    }

    // MARK: - Band-energy gate (T4 acceptance: content-level)

    /// A +0.5 fine-band boost must RAISE the checkerboard's edge energy
    /// (mean |neighbor difference| over the R channel) and a −0.5 mid
    /// cut must LOWER the gradient ramp's mid-frequency variance — both
    /// measured against the neutral render, compared>0 gated.
    func testSingleBandGainMovesBandEnergy() async throws {
        let metal = try await makeMetal()

        let checkerURL = try requireGolden("fixtures/checkerboard.exr")
        let checkerImage = try GoldenParityTests.decodeFixtureEXR(checkerURL)
        let (neutralC, wc, hc) = try await runEqualizerPipe(
            image: checkerImage, params: EqualizerModule.Params(), metal: metal)
        let (boosted, wb, hb) = try await runEqualizerPipe(
            image: checkerImage, params: EqualizerModule.Params(g0: 0.5), metal: metal)
        XCTAssertEqual(wb, wc)
        XCTAssertEqual(hb, hc)
        var comparedC = 0
        var energyNeutral = 0.0
        var energyBoosted = 0.0
        for y in 0..<hc {
            for x in 0..<(wc - 1) {
                energyNeutral += Double(abs(neutralC[(y * wc + x) * 3] - neutralC[(y * wc + x + 1) * 3]))
                energyBoosted += Double(abs(boosted[(y * wc + x) * 3] - boosted[(y * wc + x + 1) * 3]))
                comparedC += 1
            }
        }
        XCTAssertGreaterThan(comparedC, 0)
        XCTAssertGreaterThan(energyBoosted, energyNeutral,
            "fine-band +0.5 must raise checkerboard edge energy (\(energyBoosted) vs \(energyNeutral))")

        let rampURL = try requireGolden("fixtures/gradient_ramp.exr")
        let rampImage = try GoldenParityTests.decodeFixtureEXR(rampURL)
        let (neutralR, _, _) = try await runEqualizerPipe(
            image: rampImage, params: EqualizerModule.Params(), metal: metal)
        let (cut, _, _) = try await runEqualizerPipe(
            image: rampImage, params: EqualizerModule.Params(g2: -0.5, g3: -0.5), metal: metal)
        var comparedR = 0
        var varNeutral = 0.0
        var varCut = 0.0
        let n = neutralR.count / 3
        var meanN = 0.0
        var meanC = 0.0
        for i in 0..<n {
            meanN += Double(neutralR[i * 3])
            meanC += Double(cut[i * 3])
        }
        meanN /= Double(n)
        meanC /= Double(n)
        for i in 0..<n {
            varNeutral += (Double(neutralR[i * 3]) - meanN) * (Double(neutralR[i * 3]) - meanN)
            varCut += (Double(cut[i * 3]) - meanC) * (Double(cut[i * 3]) - meanC)
            comparedR += 1
        }
        XCTAssertGreaterThan(comparedR, 0)
        XCTAssertLessThan(varCut, varNeutral,
            "mid-band −0.5 cut must lower ramp variance (\(varCut) vs \(varNeutral))")
    }

    // MARK: - Registration

    func testEqualizerRegisteredAtV50Slot27() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: EqualizerModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<EqualizerModule>)
        box.setParams(EqualizerModule.Params())
        XCTAssertEqual(EqualizerModule.opName, "equalizer")
        XCTAssertEqual(EqualizerModule.iopOrder, 27.0)
        XCTAssertEqual(EqualizerModule.defaultColorspace, .Lab)
        XCTAssertLessThan(EqualizerModule.iopOrder, ColorInModule.iopOrder)
        let id = UUID()
        let restored = await registry.makeBox(opName: EqualizerModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
    }
}
