@testable import LightamerCore
import CoreGraphics
import Foundation
@testable import LightamerIOP
import Metal
import simd
import XCTest

// ShadhiParityTests (Plan 03-04-T2) — IOP-TONE-04 (shadows & highlights,
// dt `shadhi`), the first neighborhood-op module (gaussian leg; the
// bilateral leg is a Phase 5 port — plan checkpoint decision).
//
// REFERENCE PROVENANCE (L017 route, extended): the synthesized references
// (`gen_fixtures.py refs`, shadhi section) are the float64 evaluation of
// the documented shared semantic — dt shadhi.c:336-490 + the gaussian.c/
// gaussian.cl Deriche-IIR recursion (the plan's FIR wording was a source
// erratum, recorded on GaussianBlur) — over the same canonical fixture
// bytes both sides consume. The dt-cli probe route is UNUSABLE for the
// Lab chain: this build's export pipe runs IOP_CS_LAB modules on
// UNCONVERTED domain (libcolorin/colorout stale → dlopen failure; the
// flat probes match the unconverted model exactly — manifest "shadhi
// PROBE ROUTE BROKEN"). dt-side evidence = XMP adoption (DB op_params
// hex == pinned 48-byte blob + `params v. 5: version ok params ok`).
//
// Gates (plan): relative < 1e-4 (99% fraction) + ΔE < 1.0 (99th
// percentile) — the float32-vs-float64 IIR recursion difference is
// expected inside the 1e-4 band ("域内模糊的浮点顺序差预期内").
final class ShadhiParityTests: XCTestCase {

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

    // MARK: - Cases (the plan's 钉参组, all shadhi_algo = gaussian)

    private let cases: [(name: String, params: ShadhiModule.Params)] = [
        ("shadhi_default", ShadhiModule.Params()),
        ("shadhi_shadows80", ShadhiModule.Params(shadows: 80)),
        ("shadhi_highlights80", ShadhiModule.Params(highlights: -80)),
        ("shadhi_compress25", ShadhiModule.Params(compress: 25)),
    ]

    private static let trackAFixtures = [
        "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev", "saturated",
        "deep_shadow",
    ]

    // MARK: - Track A: Lightamer kernel vs the synthesized references

    func testShadhiGoldenParity() async throws {
        let metal = try await makeMetal()
        var failures: [String] = []
        var maxDeltaE = 0.0

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runShadhiPipe(
                    image: image, params: params, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size mismatch")
                    continue
                }
                if let message = ParityGate.failureMessage(
                    "\(caseName)×\(fixture)", pipe, golden.rgb,
                    strict: 1e-4, strictAbsFloor: 5e-5, envelope: 1e-3
                ) {
                    failures.append(message)
                }
                // ΔE76 p99 (the plan's perceptual gate).
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
        XCTAssertTrue(
            failures.isEmpty,
            "shadhi track A FAILED (max ΔE p99 = \(maxDeltaE)):\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// Lightamer leg: canonical fixture → [colorin, shadhi] pipe →
    /// float32 linear-Rec2020 RGB plane.
    private func runShadhiPipe(
        image: DecodedImage, params: ShadhiModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let shadhi = await registry.makeBox(opName: ShadhiModule.opName)
        let shadhiBox = try XCTUnwrap(shadhi as? ModuleBox<ShadhiModule>)
        await shadhiBox.setParams(params)
        let chain = [try XCTUnwrap(colorin), shadhiBox]

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

    // MARK: - Identity params leave the image unchanged

    /// shadows = highlights = 0 → both overlay loops never run → the
    /// output is the Lab scale/rescale round trip of the input (≤1 ulp
    /// per channel — dt's own identity has the same round trip).
    func testIdentityParamsLeaveImageUnchanged() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gray_staircase.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let golden = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("fixtures/gray_staircase.exr")
        )
        let (pipe, pipeW, pipeH) = try await runShadhiPipe(
            image: image, params: ShadhiModule.Params(shadows: 0, highlights: 0),
            metal: metal
        )
        XCTAssertEqual(pipeW, golden.width)
        XCTAssertEqual(pipeH, golden.height)
        if let message = ParityGate.failureMessage(
            "identity shadhi vs input", pipe, golden.rgb
        ) {
            XCTFail(message)
        }
    }

    // MARK: - Track B: neutrality with identity shadhi inserted

    func testTrackBNeutralityWithShadhiInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )
        let shadhi = await registry.makeBox(opName: ShadhiModule.opName)
        let shadhiBox = try XCTUnwrap(shadhi as? ModuleBox<ShadhiModule>)
        await shadhiBox.setParams(.init()) // identity
        chain.append(shadhiBox)
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
            "track B neutrality with shadhi inserted FAILED:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Registration

    func testShadhiRegisteredAtV50Slot50() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: ShadhiModule.opName)
        _ = try XCTUnwrap(box as? ModuleBox<ShadhiModule>)
        XCTAssertEqual(ShadhiModule.opName, "shadhi")
        XCTAssertEqual(ShadhiModule.iopOrder, 50.0)
        XCTAssertEqual(ShadhiModule.defaultColorspace, .Lab)
        let id = UUID()
        let restored = await registry.makeBox(opName: ShadhiModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
    }
}
