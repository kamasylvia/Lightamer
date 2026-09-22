@testable import LightamerCore
import CoreGraphics
import Foundation
@testable import LightamerIOP
import Metal
import XCTest

// SigmoidTests (Plan 03-04-T4) — IOP-FILM-02 (sigmoid), the D-T2
// scene-referred baseline. The CPU four-scalar derivation dual
// implementation lives in CPUDerivationTests (the plan's T3 surface);
// this file pins the KERNEL paths:
//
//   Track A — the 5 pinned cases (default / neutral / ACES-like /
//   rgb_ratio / smooth-primaries) × 6 fixtures vs the synthesized
//   float64 references (gen_fixtures.py `refs`, sigmoid section),
//   element-wise gate < 1e-5 (the plan's strictest band — pure
//   elementwise math).
//
//   Curve constraints on the GPU leg: f(0) → black, f(middle grey) →
//   middle grey, f(large) → white through the actual pipe.
//
//   Neutrality: gray in → gray out on BOTH color-processing paths.
//
// REFERENCE PROVENANCE (L017 route): synthesized references; dt-side
// evidence = the rgb_ratio flat probes matching the reference math to
// ≤1e-5 on three flats (0.5→0.379984, 0.03125→0.037023,
// 0.001953→0.002539) + XMP op_params adoption. The per_channel leg
// SIGSEGVs dt-cli in this build (3/3, manifest note) — it is pinned by
// the dual implementation + the shared derivation (the four scalars are
// identical for both paths and rgb_ratio-probe-verified).
final class SigmoidTests: XCTestCase {

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
                    + "`bash input/golden/regenerate.sh` (Plan 03-04)"
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

    // MARK: - Pinned cases (dt defaults + the dt presets, manifest-mapped)

    /// dt "smooth" preset rotations in radians (deg2rad of 2/−1/−3) —
    /// precomputed so the case-table literal type-checks fast.
    private static let deg = Float.pi / 180.0
    private static let smoothParams = SigmoidModule.Params(
        middleGreyContrast: 1.5, contrastSkewness: -0.2, huePreservation: 0,
        redInset: 0.1, redRotation: 2.0 * deg,
        greenInset: 0.1, greenRotation: -1.0 * deg,
        blueInset: 0.15, blueRotation: -3.0 * deg, basePrimaries: .rec2020
    )

    private var cases: [(name: String, params: SigmoidModule.Params)] {
        [
            ("sigmoid_default", SigmoidModule.Params()),
            ("sigmoid_neutral", SigmoidModule.Params(middleGreyContrast: 1.22, contrastSkewness: 0.65)),
            ("sigmoid_aces", SigmoidModule.Params(middleGreyContrast: 1.6, contrastSkewness: -0.2, huePreservation: 0)),
            ("sigmoid_rgb_ratio", SigmoidModule.Params(
                middleGreyContrast: 1.0, colorProcessing: .rgbRatio)),
            ("sigmoid_smooth", Self.smoothParams),
        ]
    }

    private static let trackAFixtures = [
        "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev", "saturated",
        "deep_shadow",
    ]

    // MARK: - Track A

    func testSigmoidGoldenParity() async throws {
        let metal = try await makeMetal()
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runSigmoidPipe(
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
        XCTAssertTrue(
            failures.isEmpty,
            "sigmoid track A FAILED:\n" + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// Lightamer leg: canonical fixture → [colorin, sigmoid] pipe →
    /// float32 linear-Rec2020 RGB plane (sigmoid 45.3 < colorin? no —
    /// sigmoid sorts AFTER colorin by v50 order; the scene-linear values
    /// flow through unchanged into the curve domain).
    private func runSigmoidPipe(
        image: DecodedImage, params: SigmoidModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let sigmoid = await registry.makeBox(opName: SigmoidModule.opName)
        let sigmoidBox = try XCTUnwrap(sigmoid as? ModuleBox<SigmoidModule>)
        sigmoidBox.setParams(params)
        let chain = [try XCTUnwrap(colorin), sigmoidBox]

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

    // MARK: - Curve constraints through the GPU leg (scene-referred semantics)

    /// f(0) → display black, f(middle grey) → middle grey, f(large) →
    /// white — evaluated through the actual pipe on flat images.
    func testGPUCurveConstraints() async throws {
        let metal = try await makeMetal()

        // f(0): a true zero input maps to the display black target.
        let (blackOut, _, _) = try await runSigmoidPipe(
            image: try grayFixture(0.0), params: SigmoidModule.Params(), metal: metal
        )
        for i in 0..<blackOut.count {
            XCTAssertLessThan(blackOut[i], 0.001, "f(0) near display black, ch \(i)")
        }

        // f(middle grey): the grey anchor passes through (≈identity by
        // construction — the curve is pinned to f(grey) = grey).
        let greyValue = Float(SigmoidDerivation.middleGrey)
        let (greyOut, _, _) = try await runSigmoidPipe(
            image: try grayFixture(greyValue), params: SigmoidModule.Params(), metal: metal
        )
        for i in 0..<greyOut.count {
            XCTAssertEqual(Double(greyOut[i]), Double(greyValue), accuracy: 2e-3,
                           "f(middle grey) = middle grey, ch \(i)")
        }

        // f(large): a huge scene value maps to the display white target.
        let (whiteOut, _, _) = try await runSigmoidPipe(
            image: try grayFixture(1e6), params: SigmoidModule.Params(), metal: metal
        )
        for i in 0..<whiteOut.count {
            XCTAssertEqual(Double(whiteOut[i]), 1.0, accuracy: 1e-4,
                           "f(large) = display white, ch \(i)")
        }
    }

    /// Neutrality: a gray input stays gray on BOTH color-processing
    /// paths (per_channel hue preservation and rgb_ratio's uniform
    /// scaling both conserve R==G==B).
    func testGraysStayNeutralOnBothPaths() async throws {
        let metal = try await makeMetal()
        for params in [
            SigmoidModule.Params(middleGreyContrast: 1.8, contrastSkewness: 0.4),
            SigmoidModule.Params(middleGreyContrast: 1.8, contrastSkewness: 0.4, colorProcessing: .rgbRatio),
        ] {
            let (out, _, _) = try await runSigmoidPipe(
                image: try grayFixture(0.37), params: params, metal: metal
            )
            for i in stride(from: 0, to: out.count, by: 3) {
                XCTAssertEqual(out[i], out[i + 1], accuracy: 1e-6, "R==G")
                XCTAssertEqual(out[i + 1], out[i + 2], accuracy: 1e-6, "G==B")
            }
        }
    }

    private func grayFixture(_ v: Float) throws -> DecodedImage {
        let width = 4, height = 4
        var rgba = [Float](repeating: v, count: width * height * 4)
        for i in 0..<(width * height) { rgba[i * 4 + 3] = 1.0 }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return DecodedImage(
            ciImage: CIImage(cgImage: cg), rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    // MARK: - Track B: dual criteria with identity sigmoid inserted

    func testTrackBNeutralityWithSigmoidInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )
        let sigmoid = await registry.makeBox(opName: SigmoidModule.opName)
        let sigmoidBox = try XCTUnwrap(sigmoid as? ModuleBox<SigmoidModule>)
        sigmoidBox.setParams(.init()) // identity-ish defaults
        chain.append(sigmoidBox)
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
            "track B neutrality with sigmoid inserted FAILED:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Registration

    func testSigmoidRegisteredAtV50Slot45_3() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: SigmoidModule.opName)
        _ = try XCTUnwrap(box as? ModuleBox<SigmoidModule>)
        XCTAssertEqual(SigmoidModule.opName, "sigmoid")
        XCTAssertEqual(SigmoidModule.iopOrder, 45.3)
        XCTAssertEqual(SigmoidModule.defaultColorspace, .RGB)
        let id = UUID()
        let restored = await registry.makeBox(opName: SigmoidModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
    }
}
