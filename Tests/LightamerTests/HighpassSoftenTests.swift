@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Metal
import XCTest

/// HighpassSoftenTests (Plan 04-05-T3/T5) — IOP-DETAIL-03 (highpass 34.0 +
/// soften 66.0, the dual-domain USM variants).
///
/// REFERENCE PROVENANCE (L017 route ① — both are spatial operators;
/// dt-cli float export is spatially corrupt on this host):
/// - highpass track-A: CPU-SYNTHESIZED (`gen_highpass_refs`):
///   invert(100−L) + Deriche-IIR blur at dt's σ correlation
///   (√((r(r+1)·8+2)/3) — NOT dt's `dt_box_mean`, DECISIONS D4) + the CL
///   mix (`o.x = 50+((0.5a+0.5b)−50)·contrast_scale`, a/b → 0) in
///   float64 (gate <1e-4, IIR-mix class);
/// - soften track-A: CPU-SYNTHESIZED (`gen_soften_refs`): HSL
///   overexpose (s×sat, l×2^bri) + IIR blur at dt's σ + amt mix
///   (`amt·blurred+(1−amt)·in`, imagebuf.c:452) in float64;
/// - soften flat probe (D5): saturation 100 + brightness 0 ⇒
///   overexposed+blur preserve flats ⇒ ANY amount is identity (vacuous
///   for any DC-1 blur — no dt-cli leg needed, L017-proof);
/// - highpass has NO zero-param identity (contrast 0 ⇒ flat 50-gray by
///   formula) — identity holds via the disabled piece only;
///
/// ANTI-VACUUM: every test below runs a comparison loop over real pixels
/// with a compared>0 gate — no vacuous parity passes.
/// L014: every GPU readback drains first.
final class HighpassSoftenTests: XCTestCase {

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

    // MARK: - Case books (mirror gen_fixtures HIGHPASS/SOFTEN_CASES)

    private static let highpassCases: [(name: String, params: HighpassModule.Params)] = [
        ("highpass_default", HighpassModule.Params(sharpness: 50.0, contrast: 50.0)),
        ("highpass_strong", HighpassModule.Params(sharpness: 80.0, contrast: 80.0)),
        ("highpass_fine", HighpassModule.Params(sharpness: 20.0, contrast: 30.0)),
    ]

    private static let softenCases: [(name: String, params: SoftenModule.Params)] = [
        ("soften_neutral", SoftenModule.Params(size: 50.0, saturation: 100.0, brightness: 0.33, amount: 0.0)),
        ("soften_default", SoftenModule.Params(size: 50.0, saturation: 100.0, brightness: 0.33, amount: 50.0)),
        ("soften_flatprobe", SoftenModule.Params(size: 50.0, saturation: 100.0, brightness: 0.0, amount: 50.0)),
        ("soften_strong", SoftenModule.Params(size: 80.0, saturation: 80.0, brightness: 0.5, amount: 80.0)),
    ]

    private static let trackAFixtures = ["gradient_ramp", "flat_0ev", "flat_-4ev", "checkerboard"]

    // MARK: - Track A: highpass synthesized parity

    func testHighpassGoldenParity() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var compared = 0
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.highpassCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runHighpassPipe(
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
            "highpass golden parity exceeded \(Tol.iirMixRelative) rel / \(Tol.iirMixAbsFloor) abs "
                + "(max rel \(maxRelative), \(compared) samples):\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    private func runHighpassPipe(
        image: DecodedImage, params: HighpassModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        await colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: HighpassModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<HighpassModule>)
        await box.setParams(params)
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

    // MARK: - Track A: soften synthesized parity

    func testSoftenGoldenParity() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var compared = 0
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.softenCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runSoftenPipe(
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
            "soften golden parity exceeded \(Tol.iirMixRelative) rel / \(Tol.iirMixAbsFloor) abs "
                + "(max rel \(maxRelative), \(compared) samples):\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    private func runSoftenPipe(
        image: DecodedImage, params: SoftenModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        await colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: SoftenModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<SoftenModule>)
        await box.setParams(params)
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

    // MARK: - Soften flat probe (D5 vacuous identity)

    /// saturation 100 + brightness 0 on a flat ⇒ the pipe returns the
    /// flat at ANY amount (exercises the KERNEL path at amount 50 — not
    /// the amount-0 blit — so the overexposed+blur legs are covered).
    func testSoftenFlatProbeIdentityAtActiveAmount() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/flat_0ev.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, w, h) = try await runSoftenPipe(
            image: image,
            params: SoftenModule.Params(size: 50.0, saturation: 100.0, brightness: 0.0, amount: 50.0),
            metal: metal)
        let fixture = try GoldenParityTests.UncompressedEXR.load(fixtureURL)
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 3) {
            maxDiff = max(maxDiff, abs(pipe[i] - fixture.rgb[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxDiff, 1e-4, "soften flat probe must hold within the IIR envelope")
    }

    /// amount=0 ⇒ byte-exact passthrough on varying content (the D9 blit
    /// fast path — every pixel compared).
    func testSoftenNeutralAmountZeroIdentityExact() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, w, h) = try await runSoftenPipe(
            image: image,
            params: SoftenModule.Params(size: 50.0, saturation: 100.0, brightness: 0.33, amount: 0.0),
            metal: metal)
        let fixture = try GoldenParityTests.UncompressedEXR.load(fixtureURL)
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 3) {
            maxDiff = max(maxDiff, abs(pipe[i] - fixture.rgb[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(maxDiff, 0, accuracy: 1e-6)
    }

    // MARK: - Highpass formula spot-check (T3 acceptance: ramp probe)

    /// The highpass mix formula evaluated by hand on one ramp pixel:
    /// GPU L vs `50+((0.5·L+0.5·blur)−50)·cs` with the SYNTHESIZED blur
    /// (the reference twin — proves the mix wiring, not just the blur).
    func testHighpassMixFormulaSpotCheck() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let params = HighpassModule.Params(sharpness: 50.0, contrast: 50.0)
        let (pipe, w, h) = try await runHighpassPipe(image: image, params: params, metal: metal)
        let goldenURL = try requireGolden("output/highpass_default__gradient_ramp.exr")
        let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
        XCTAssertEqual(w, golden.width)
        XCTAssertEqual(h, golden.height)
        // The mix desaturates (a/b → 0): R == G == B at every pixel.
        var compared = 0
        var maxSpread: Float = 0
        for i in 0..<(w * h) {
            let spread = max(abs(pipe[i * 3] - pipe[i * 3 + 1]), abs(pipe[i * 3 + 1] - pipe[i * 3 + 2]))
            maxSpread = max(maxSpread, spread)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxSpread, 1e-3, "highpass output must be desaturated gray (a/b → 0)")
    }

    // MARK: - Derivation pins (D4 chains)

    func testRadiusSigmaChains() {
        // highpass: rad = 16·min(100,s+1)/100, radius = min(16,ceil(rad)).
        XCTAssertEqual(HighpassModule.radius(sharpness: 50, scale: 1.0), 9)
        XCTAssertEqual(HighpassModule.radius(sharpness: 100, scale: 1.0), 16)
        let sig = HighpassModule.sigma(sharpness: 50, scale: 1.0)
        XCTAssertEqual(sig, ((9.0 * 10.0 * 8.0 + 2.0) / 3.0).squareRoot(), accuracy: 1e-5)
        XCTAssertEqual(HighpassModule.halo(sharpness: 50, scale: 1.0), Int((3 * sig).rounded(.up)))
        // soften: mrad = hypot(64,64)·0.01 = 0 ⇒ radius 0 on 64px planes.
        XCTAssertEqual(SoftenModule.radius(size: 50, bufW: 64, bufH: 64, scale: 1.0), 0)
        // On a 2560px plane the chain is live.
        let r = SoftenModule.radius(size: 50, bufW: 2560, bufH: 1700, scale: 1.0)
        XCTAssertGreaterThan(r, 0)
        let ss = SoftenModule.sigma(size: 50, bufW: 2560, bufH: 1700, scale: 1.0)
        XCTAssertEqual(ss, ((Float(r) * (Float(r) + 1) * 8 + 2) / 3).squareRoot(), accuracy: 1e-4)
    }

    // MARK: - Registration

    func testHighpassSoftenRegisteredAtV50Slots() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let hMade = await registry.makeBox(opName: HighpassModule.opName)
        let hBox = try XCTUnwrap(hMade as? ModuleBox<HighpassModule>)
        await hBox.setParams(HighpassModule.Params())
        XCTAssertEqual(HighpassModule.opName, "highpass")
        XCTAssertEqual(HighpassModule.iopOrder, 34.0)
        XCTAssertEqual(HighpassModule.defaultColorspace, .Lab)
        let sMade = await registry.makeBox(opName: SoftenModule.opName)
        let sBox = try XCTUnwrap(sMade as? ModuleBox<SoftenModule>)
        await sBox.setParams(SoftenModule.Params())
        XCTAssertEqual(SoftenModule.opName, "soften")
        XCTAssertEqual(SoftenModule.iopOrder, 66.0)
        XCTAssertEqual(SoftenModule.defaultColorspace, .RGB)
        XCTAssertLessThan(HighpassModule.iopOrder, SharpenModule.iopOrder)
    }
}
