@testable import LightamerCore
import Foundation
@testable import LightamerIOP
import Metal
import simd
import XCTest

// ToneEqualParityTests (Plan 03-05-T5) — IOP-TONE-07 (tone equalizer),
// the TWO-TIER golden gate (plan T5 / D-T3 checkpoint #2):
//
//   Tier 1 — details=none (pure per-pixel luma+LUT): relative < 1e-5
//            (≥99% fraction) + 1e-4 envelope. The envelope covers the
//            one-LUT-index flip at rounding boundaries (the GPU's
//            float32 luma vs the reference's float64 log2 — the same
//            ParityGate rationale as colisa/tonecurve/levels).
//   Tier 2 — EIGF (dt default detail leg): relative < 1e-4 (≥99%) +
//            ΔE76 p99 < 1.0 (the CPU-vs-Metal reduction-order band,
//            RESEARCH Risk #7).
//
// REFERENCE PROVENANCE (L017 route): synthesized float64 references
// (gen_fixtures.py `refs`, toneequal section) — darktable has NO OpenCL
// for this iop (toneequal.c:313 TODO), and the host's float-export
// corruption rules out spatially-varying EXR references. The float64
// reference replicates the CPU sources; the choleski.h pseudo-solve is
// REPLICATED IN float32 there (a float64 solve drifts ~3e-4 through the
// 9×8 conditioning — the float32-faithful weights match this port's to
// ~1e-7). dt-side evidence = XMP adoption (DB op_params 72-byte blob
// matches the pinned hex; `params v. 2: version ok params ok`) +
// uniform-flat PFM probes (a uniform field is the EIGF fixed point:
// var→0 forces a=0, b=avg ⇒ the blend is identity, so the flats pin the
// luma+LUT apply semantics exactly).
final class ToneEqualParityTests: XCTestCase {

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
                    + "`bash input/golden/regenerate.sh` (Plan 03-05)"
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

    // MARK: - Cases (manifest-mapped to the pinned XMP blobs)

    /// (name, params) — field values mirror gen_fixtures.py TONEEQUAL_CASES.
    private var cases: [(name: String, params: ToneEqualModule.Params)] {
        [
            ("toneequal_default", ToneEqualModule.Params()),
            ("toneequal_shadow_lift", ToneEqualModule.Params(
                deepBlacks: 0.5, shadows: 1.0)),
            ("toneequal_highlight_compress", ToneEqualModule.Params(
                highlights: -1.0, whites: -0.5)),
            ("toneequal_contrast_boost", ToneEqualModule.Params(
                shadows: 0.8, contrastBoost: 4.0)),
            ("toneequal_none_ramp", ToneEqualModule.Params(
                shadows: 1.0, highlights: -0.5, details: .none)),
        ]
    }

    private static let trackAFixtures = [
        "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev", "saturated",
        "deep_shadow",
    ]

    // MARK: - Track A: the two-tier gate

    func testToneEqualGoldenParityTwoTiers() async throws {
        let metal = try await makeMetal()
        var failures: [String] = []
        var maxDeltaE = 0.0

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runToneEqualPipe(
                    image: image, params: params, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size mismatch")
                    continue
                }
                let isNone = params.details == .none
                if let message = isNone
                    ? ParityGate.failureMessage("\(caseName)×\(fixture) [none]", pipe, golden.rgb)
                    : ParityGate.failureMessage(
                        "\(caseName)×\(fixture) [eigf]", pipe, golden.rgb,
                        strict: 1e-4, strictAbsFloor: 5e-5, envelope: 1e-3)
                {
                    failures.append(message)
                }
                if !isNone {
                    // ΔE76 p99 — the perceptual second criterion of the
                    // EIGF tier (ShadhiParityTests shape).
                    let n = pipeW * pipeH
                    var deltaEs = [Double]()
                    deltaEs.reserveCapacity(n)
                    for i in 0..<n {
                        let got = LabRoundTrip.rec2020ToLab(SIMD3(
                            Double(pipe[i * 3]), Double(pipe[i * 3 + 1]), Double(pipe[i * 3 + 2])
                        ))
                        let ref = LabRoundTrip.rec2020ToLab(SIMD3(
                            Double(golden.rgb[i * 3]), Double(golden.rgb[i * 3 + 1]),
                            Double(golden.rgb[i * 3 + 2])
                        ))
                        deltaEs.append(simd_length(got - ref))
                    }
                    deltaEs.sort()
                    let p99 = deltaEs[Int(Double(deltaEs.count - 1) * 0.99)]
                    maxDeltaE = max(maxDeltaE, p99)
                    if p99 >= 1.0 {
                        failures.append("\(caseName)×\(fixture): ΔE p99 = \(p99) ≥ 1.0")
                    }
                }
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "toneequal track A FAILED (max ΔE p99 = \(maxDeltaE)):\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// Lightamer leg: canonical fixture → [colorin, toneequal] pipe →
    /// float32 linear-Rec2020 RGB plane.
    private func runToneEqualPipe(
        image: DecodedImage, params: ToneEqualModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let maybeColorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorin = try XCTUnwrap(maybeColorin)
        let maybeBox = await registry.makeBox(opName: ToneEqualModule.opName)
        let box = try XCTUnwrap(maybeBox as? ModuleBox<ToneEqualModule>)
        box.setParams(params)
        let chain = [colorin, box]

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

    // MARK: - Track B: the terminal trio semantics with toneequal inserted

    func testTrackBNeutralityWithToneEqualInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )
        let maybeBox = await registry.makeBox(opName: ToneEqualModule.opName)
        let box = try XCTUnwrap(maybeBox as? ModuleBox<ToneEqualModule>)
        box.setParams(.init()) // dt defaults (EIGF, all bands 0)
        chain.append(box)
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
            "track B neutrality with toneequal inserted FAILED:\n" + failures.joined(separator: "\n")
        )
    }
}
