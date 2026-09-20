@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Metal
import simd
import XCTest

/// SharpenParityTests (Plan 04-05-T1/T5) — IOP-DETAIL-01 (USM, op
/// "sharpen", v50 slot 35.0).
///
/// REFERENCE PROVENANCE (L017 route ① — USM is a spatial operator;
/// dt-cli float export is spatially corrupt on this host, manifest
/// "dt-cli host finding" re-confirmed for geometry in 04-02-T3):
/// - track-A references are CPU-SYNTHESIZED by gen_fixtures.py (`refs`
///   mode, `gen_sharpen_refs`): Lab prep + Deriche-IIR blur (the SHARED
///   GaussianBlur side — NOT dt's truncated FIR, DECISIONS D1) +
///   soft-threshold mix in float64, formula-mirrored with
///   `SharpenKernels.metal` (gate <1e-4, IIR-mix class);
/// - σ = radius·scale (the commit 2.5× cancels dt's FIR σ² denominator —
///   sharpen.c:160-161 × :376); rad = min(12, ceil(2.5·r·scale));
/// - uniform probes (in-test): amount=0 / flat-field ⇒ exact identity
///   (delta 0 ⇒ mix identity; the blit fast path);
///
/// ANTI-VACUUM: every test below runs a comparison loop over real pixels
/// with a compared>0 gate — no vacuous parity passes.
/// L014: every GPU readback drains first.
/// L020: content-level assertions (golden bytes), not just ROI bookkeeping.
final class SharpenParityTests: XCTestCase {

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

    // MARK: - Case book (mirrors gen_fixtures SHARPEN_CASES)

    private static let sharpenCases: [(name: String, params: SharpenModule.Params)] = [
        ("sharpen_neutral", SharpenModule.Params(radius: 2.0, amount: 0.0, threshold: 0.5)),
        ("sharpen_default", SharpenModule.Params(radius: 2.0, amount: 0.5, threshold: 0.5)),
        ("sharpen_strong", SharpenModule.Params(radius: 2.0, amount: 1.0, threshold: 0.0)),
        ("sharpen_fine", SharpenModule.Params(radius: 0.8, amount: 1.0, threshold: 0.2)),
    ]

    private static let trackAFixtures = ["gradient_ramp", "flat_0ev", "flat_-4ev", "checkerboard"]

    // MARK: - Track A: synthesized USM parity

    /// TRACK A: every (fixture × case) synthesized reference vs the
    /// Lightamer `[sharpen, colorin]` pipe, per-pixel relative <1e-4
    /// (+1e-4 abs floor — the IIR-mix class gate).
    func testSharpenGoldenParity() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var compared = 0
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.sharpenCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runSharpenPipe(
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
            "sharpen golden parity exceeded \(Tol.iirMixRelative) rel / \(Tol.iirMixAbsFloor) abs "
                + "(max rel \(maxRelative), \(compared) samples):\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// Lightamer leg: canonical fixture → `[sharpen, colorin]` pipe → RGB.
    private func runSharpenPipe(
        image: DecodedImage, params: SharpenModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        await colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: SharpenModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<SharpenModule>)
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

    // MARK: - Identity gates (T1 acceptance)

    /// amount=0 ⇒ byte-exact passthrough on varying content (the D9 blit
    /// fast path — every pixel compared, not just the hash).
    func testNeutralAmountZeroIdentityExact() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, w, h) = try await runSharpenPipe(
            image: image,
            params: SharpenModule.Params(radius: 2.0, amount: 0.0, threshold: 0.5),
            metal: metal)
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

    /// Flat field + active amount ⇒ identity (delta 0 ⇒ mix identity —
    /// the USM fixed point; exercises the KERNEL path, not the blit).
    func testFlatFieldActiveAmountIdentity() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/flat_0ev.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, w, h) = try await runSharpenPipe(
            image: image,
            params: SharpenModule.Params(radius: 2.0, amount: 1.0, threshold: 0.5),
            metal: metal)
        let fixture = try GoldenParityTests.UncompressedEXR.load(fixtureURL)
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 3) {
            maxDiff = max(maxDiff, abs(pipe[i] - fixture.rgb[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxDiff, 1e-4, "flat-field USM must hold within the IIR envelope")
    }

    // MARK: - Derivation pins (T1 acceptance: σ chain + halo)

    func testSigmaChainKnownVectors() {
        // D1: σ = radius·scale (the commit 2.5× cancels the FIR denominator).
        XCTAssertEqual(SharpenModule.sigma(radius: 2.0, scale: 1.0), 2.0, accuracy: 1e-6)
        XCTAssertEqual(SharpenModule.sigma(radius: 0.8, scale: 0.5), 0.4, accuracy: 1e-6)
        // FIR radius: min(12, ceil(2.5·r·scale)) — MAXR clamp.
        XCTAssertEqual(SharpenModule.firRadius(radius: 2.0, scale: 1.0), 5)
        XCTAssertEqual(SharpenModule.firRadius(radius: 99.0, scale: 1.0), 12)
        // Halo: ceil(3σ) — the D-G5 constant.
        XCTAssertEqual(SharpenModule.halo(radius: 2.0, scale: 1.0), 6)
        XCTAssertEqual(SharpenModule.halo(radius: 0.8, scale: 1.0), 3)
    }

    // MARK: - Registration

    func testSharpenRegisteredAtV50Slot35() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: SharpenModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<SharpenModule>)
        await box.setParams(SharpenModule.Params())
        XCTAssertEqual(SharpenModule.opName, "sharpen")
        XCTAssertEqual(SharpenModule.iopOrder, 35.0)
        XCTAssertEqual(SharpenModule.defaultColorspace, .Lab)
        XCTAssertLessThan(HighpassModule.iopOrder, SharpenModule.iopOrder)
        let id = UUID()
        let restored = await registry.makeBox(opName: SharpenModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
    }
}
