@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Metal
import XCTest

/// LocalContrastTests (Plan 04-05-T2/T5) — IOP-DETAIL-02 (clarity, op
/// "bilat", v50 slot 54.0).
///
/// REFERENCE PROVENANCE (L017 route ① + D-G3 — the EIGF leg is not dt's
/// bilateral/local-laplacian, so no dt-cli leg exists even in principle):
/// - track-A references are CPU-SYNTHESIZED by gen_fixtures.py (`refs`
///   mode, `gen_bilat_refs`): Lab-L EIGF no-mask base (`te_eigf`, single
///   iteration — the exact toneequal leg) + clarity apply in float64,
///   formula-mirrored with `LocalContrastKernels.metal` + the toneequal
///   kernels (gate <1e-4, IIR-mix class);
/// - detail=0 ⇒ EXACT identity (the D9 blit fast path);
/// - direction: positive detail raises local contrast on a synthetic step
///   (content-level assertion — L020);
///
/// ANTI-VACUUM: every test below runs a comparison loop over real pixels
/// with a compared>0 gate — no vacuous parity passes.
/// L014: every GPU readback drains first.
final class LocalContrastTests: XCTestCase {

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

    // MARK: - Case book (mirrors gen_fixtures BILAT_CASES)

    private static let bilatCases: [(name: String, params: LocalContrastModule.Params)] = [
        ("bilat_neutral", LocalContrastModule.Params(detail: 0.0, sigmaS: 20.0, sigmaR: 0.5)),
        ("bilat_clarity", LocalContrastModule.Params(detail: 1.0, sigmaS: 20.0, sigmaR: 0.5)),
        ("bilat_soften", LocalContrastModule.Params(detail: -0.5, sigmaS: 20.0, sigmaR: 0.5)),
        ("bilat_tight", LocalContrastModule.Params(detail: 1.0, sigmaS: 8.0, sigmaR: 0.3)),
    ]

    private static let trackAFixtures = ["gradient_ramp", "flat_0ev", "flat_-4ev", "checkerboard"]

    // MARK: - Track A: synthesized EIGF-clarity parity

    /// TRACK A: every (fixture × case) synthesized reference vs the
    /// Lightamer `[bilat, colorin]` pipe, per-pixel relative <1e-4
    /// (+1e-4 abs floor — the IIR-mix class gate).
    func testLocalContrastGoldenParity() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var compared = 0
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.bilatCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runBilatPipe(
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
            "local-contrast golden parity exceeded \(Tol.iirMixRelative) rel / \(Tol.iirMixAbsFloor) abs "
                + "(max rel \(maxRelative), \(compared) samples):\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// Lightamer leg: canonical fixture → `[bilat, colorin]` pipe → RGB.
    private func runBilatPipe(
        image: DecodedImage, params: LocalContrastModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: LocalContrastModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<LocalContrastModule>)
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

    // MARK: - Identity gate (T2 acceptance: detail=0 ⇒ exact)

    /// detail=0 ⇒ byte-exact passthrough on varying content (the D9 blit
    /// fast path — every pixel compared).
    func testDetailZeroIdentityExact() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, w, h) = try await runBilatPipe(
            image: image,
            params: LocalContrastModule.Params(detail: 0.0, sigmaS: 20.0, sigmaR: 0.5),
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

    // MARK: - Direction gate (T2 acceptance: step-image contrast)

    /// Positive detail must RAISE the step edge's local contrast (the
    /// pixel just above the edge brightens relative to neutral) and
    /// negative detail must LOWER it — on a synthetic 2-level step, so
    /// the EIGF base (smooth) differs from luma (sharp) by construction.
    func testDetailSignDirectionOnStep() async throws {
        let metal = try await makeMetal()
        // 32×32 left/right step: 0.18 / 0.5 linear (both mid-Lab).
        let w = 32, h = 32
        var rgba = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v: Float = x < w / 2 ? 0.18 : 0.5
                let i = (y * w + x) * 4
                rgba[i] = v; rgba[i + 1] = v; rgba[i + 2] = v; rgba[i + 3] = 1
            }
        }
        let image = try makeImageFromRGBA(rgba, width: w, height: h)
        let probe = w / 2 + 2 // two texels above the edge (bright side)

        let (neutral, _, _) = try await runBilatPipe(
            image: image,
            params: LocalContrastModule.Params(detail: 0.0, sigmaS: 20.0, sigmaR: 0.5),
            metal: metal)
        let (pos, _, _) = try await runBilatPipe(
            image: image,
            params: LocalContrastModule.Params(detail: 1.0, sigmaS: 20.0, sigmaR: 0.5),
            metal: metal)
        let (neg, _, _) = try await runBilatPipe(
            image: image,
            params: LocalContrastModule.Params(detail: -0.5, sigmaS: 20.0, sigmaR: 0.5),
            metal: metal)
        // Compare the bright-side probe's R (== G == B on neutrals).
        var comparedPos = 0, comparedNeg = 0
        for dy in -1...1 {
            let i = (((h / 2 + dy) * w + probe) * 3)
            if pos[i] > neutral[i] + 1e-5 { comparedPos += 1 }
            if neg[i] < neutral[i] - 1e-5 { comparedNeg += 1 }
        }
        XCTAssertGreaterThan(comparedPos, 0, "positive detail must lift the bright side of the step")
        XCTAssertGreaterThan(comparedNeg, 0, "negative detail must sink the bright side of the step")
    }

    private func makeImageFromRGBA(_ rgba: [Float], width: Int, height: Int) throws -> DecodedImage {
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw NSError(domain: "LocalContrastTests", code: 1)
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let cg = CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw NSError(domain: "LocalContrastTests", code: 2)
        }
        return DecodedImage(
            ciImage: CIImage(cgImage: cg), rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    // MARK: - Derivation pins (D6 mappings)

    func testRadiusAndFeatheringMappings() {
        XCTAssertEqual(LocalContrastModule.effectiveRadius(sigmaS: 20, scale: 1.0), 20, accuracy: 1e-6)
        XCTAssertEqual(LocalContrastModule.effectiveRadius(sigmaS: 20, scale: 0.5), 10, accuracy: 1e-6)
        // sigmaR 0.5 ⇒ eps 1.0 = toneequal's default feathering.
        XCTAssertEqual(LocalContrastModule.feathering(sigmaR: 0.5), 1.0, accuracy: 1e-6)
        XCTAssertEqual(LocalContrastModule.feathering(sigmaR: 0.3), 0.36, accuracy: 1e-6)
        // downsample: scaling = clamp(r,1,4), ds_sigma = max(r/s,1).
        let ds = LocalContrastModule.downsample(width: 64, height: 64, radius: 20)
        XCTAssertEqual(ds.w, 16)
        XCTAssertEqual(ds.h, 16)
        XCTAssertEqual(ds.sigma, 5.0, accuracy: 1e-6)
    }

    // MARK: - Tiling consistency (T2 acceptance: <1e-4)

    /// Force-tiled FULL run vs the whole-plane run on the same input —
    /// the tile outputs compose to the untiled output within 1e-4 (the
    /// halo policy's direct evidence; TilingOverlapTests toneequal gate
    /// is the pattern).
    func testForcedTilingMatchesWholePlane() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let params = LocalContrastModule.Params(detail: 1.0, sigmaS: 20.0, sigmaR: 0.5)
        let whole = try await runBilatPipe(image: image, params: params, metal: metal).0

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: LocalContrastModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<LocalContrastModule>)
        box.setParams(params)
        let chain = [box as any ModuleBoxing, colorinBox]
        let (tiled, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal,
            longEdge: nil, maxTileWorkingBytes: 4096
        )
        await drain(metal)
        XCTAssertEqual(tiled.width, 64)
        XCTAssertEqual(tiled.height, 64)
        var floats = [Float](repeating: 0, count: 64 * 64 * 4)
        floats.withUnsafeMutableBytes {
            tiled.getBytes(
                $0.baseAddress!, bytesPerRow: 64 * 16,
                from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
        }
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(64 * 64 * 3) {
            let channel = i % 3
            maxDiff = max(maxDiff, abs(floats[(i / 3) * 4 + channel] - whole[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxDiff, 1e-4, "force-tiled FULL must match whole-plane <1e-4")
    }

    // MARK: - Registration

    func testBilatRegisteredAtV50Slot54() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: LocalContrastModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<LocalContrastModule>)
        box.setParams(LocalContrastModule.Params())
        XCTAssertEqual(LocalContrastModule.opName, "bilat")
        XCTAssertEqual(LocalContrastModule.iopOrder, 54.0)
        XCTAssertEqual(LocalContrastModule.defaultColorspace, .Lab)
        let id = UUID()
        let restored = await registry.makeBox(opName: LocalContrastModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
    }
}
