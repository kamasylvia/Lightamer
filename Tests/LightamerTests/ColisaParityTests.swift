@testable import LightamerCore
import CoreGraphics
import CoreImage
import Foundation
import LightamerIOP
import Metal
import XCTest

// ColisaParityTests (Plan 03-03-T2) — IOP-TONE-05 (contrast/brightness/
// saturation, dt `colisa`), the first Lab-domain parity module.
//
// REFERENCE PROVENANCE (L017 protocol, extended): the synthesized
// references (`gen_fixtures.py refs`, colisa section) are the float64
// evaluation of the documented shared semantic (dt colisa.c:179-235 +
// process :153-176 with the project LabRoundTrip constants) over the same
// canonical fixture bytes both sides consume. The dt-cli probe route is
// UNAVAILABLE for the Lab chain in this build — see manifest "colisa
// probe route unavailable": the XMP params ARE adopted (library DB
// op_params hex == pinned blob + `params ok` log, verified 03-03-T2), but
// the export applies nondeterministic piece state (a gray input turns
// BLACK under saturation=-1 although a=b=0 must stay gray under any
// gain — mathematically impossible for the colisa process, so the
// corruption is in the pipeline/piece path, not the module math).
//
// Parity gates: the dual gate (ParityGate) — ≥99.9% of samples < 1e-5
// relative (plan gate) + all samples inside the 2e-4 LUT-nearest cliff
// envelope.
final class ColisaParityTests: XCTestCase {

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
                    + "`bash input/golden/regenerate.sh` (Plan 03-03)"
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

    // MARK: - CPU LUT unit tests (colisa.c:179-235)

    private let cases: [(name: String, params: ColisaModule.Params)] = [
        ("colisa_default", ColisaModule.Params(contrast: 0, brightness: 0, saturation: 0)),
        ("colisa_c05", ColisaModule.Params(contrast: 0.5, brightness: 0, saturation: 0)),
        ("colisa_cm05_b03", ColisaModule.Params(contrast: -0.5, brightness: 0.3, saturation: 0)),
        ("colisa_bm03_s05", ColisaModule.Params(contrast: 0, brightness: -0.3, saturation: 0.5)),
        ("colisa_combo", ColisaModule.Params(contrast: 0.5, brightness: -0.3, saturation: -0.5)),
    ]

    /// contrast=0 & brightness=0 → identity LUTs (colisa.c:194/220 with the
    /// rescales at 1.0 / 0).
    func testIdentityParamsGiveIdentityLUTs() {
        let p = ColisaModule.Params()
        let ctable = ColisaModule.contrastTable(p)
        let ltable = ColisaModule.brightnessTable(p)
        for k in stride(from: 0, to: ColisaModule.lutResolution, by: 977) {
            let x = 100.0 * Float(k) / Float(ColisaModule.lutResolution)
            XCTAssertEqual(ctable[k], x, accuracy: 1e-4, "ctable[\(k)]")
            XCTAssertEqual(ltable[k], x, accuracy: 1e-4, "ltable[\(k)]")
        }
        XCTAssertEqual(ColisaModule.saturationGain(p), 1.0)
    }

    /// Known (contrast, brightness) vectors against the direct formulas.
    func testKnownTableVectors() {
        // contrast=0.5 → d.contrast=1.5 → sigmoidal; center fixed at 50,
        // endpoints 0/100, max slope at center = sqrt(1 + 20·0.25).
        var p = ColisaModule.Params(contrast: 0.5)
        var ctable = ColisaModule.contrastTable(p)
        let mid = ColisaModule.lutResolution / 2
        XCTAssertEqual(ctable[mid], 50.0, accuracy: 1e-5)
        XCTAssertEqual(ctable[0], 0.0, accuracy: 1e-5)
        XCTAssertEqual(ctable[ColisaModule.lutResolution - 1], 100.0, accuracy: 1e-3)
        // quarter point: kx2m1 = −0.5 → 50·(√6·(−0.5)/√(1+5·0.25)+1) = 29.5755
        let q = mid / 2
        let kx2m1 = 2.0 * Float(q) / Float(ColisaModule.lutResolution) - 1.0
        let scale: Float = 2.449489743
        let expected: Float = 50.0 * (scale * kx2m1 / Foundation.sqrt(1 + 5 * kx2m1 * kx2m1) + 1)
        XCTAssertEqual(ctable[q], expected, accuracy: 1e-4)

        // contrast=−0.5 → d.contrast=0.5 → linear: 0.5·(x−50)+50.
        p = ColisaModule.Params(contrast: -0.5)
        ctable = ColisaModule.contrastTable(p)
        XCTAssertEqual(ctable[0], 25.0, accuracy: 1e-5)
        XCTAssertEqual(ctable[mid], 50.0, accuracy: 1e-5)
        XCTAssertEqual(ctable[ColisaModule.lutResolution - 1], 75.0, accuracy: 1e-3)

        // brightness=0.3 → d.brightness=0.6 → gamma=1/1.6 → L''=100·x^0.625.
        // brightness=−0.3 → d.brightness=−0.6 → gamma=1.6.
        let lb = ColisaModule.brightnessTable(ColisaModule.Params(brightness: 0.3))
        let ld = ColisaModule.brightnessTable(ColisaModule.Params(brightness: -0.3))
        XCTAssertEqual(lb[mid], 100.0 * Foundation.pow(0.5, 0.625), accuracy: 1e-4)
        XCTAssertEqual(ld[mid], 100.0 * Foundation.pow(0.5, 1.6), accuracy: 1e-4)
        XCTAssertEqual(lb[0], 0.0, accuracy: 1e-6)
    }

    /// The unbounded extrapolation fits are continuous with the table at
    /// the anchor (fit anchored at x=1.0 → eval(1.0) == table end value)
    /// and monotone-ordered around it.
    func testExtrapolationContinuity() {
        for (name, params) in cases {
            let ctable = ColisaModule.contrastTable(params)
            let ltable = ColisaModule.brightnessTable(params)
            let xs: [Float] = [0.7, 0.8, 0.9, 1.0]
            func sample(_ t: [Float], _ x: Float) -> Float {
                t[min(Int(x * Float(ColisaModule.lutResolution)), ColisaModule.lutResolution - 1)]
            }
            let cc = IOPExpFit.estimate(xs, xs.map { sample(ctable, $0) })
            let lc = IOPExpFit.estimate(xs, xs.map { sample(ltable, $0) })
            let endC = ctable[ColisaModule.lutResolution - 1]
            let endL = ltable[ColisaModule.lutResolution - 1]
            // eval at the anchor x=1.0 must equal the anchor sample (the
            // fit is (x0,y0)-anchored: coeff = {1/x0, y0, g}).
            XCTAssertEqual(IOPExpFit.eval(cc, 1.0), endC, accuracy: 1e-3, "\(name) c")
            XCTAssertEqual(IOPExpFit.eval(lc, 1.0), endL, accuracy: 1e-3, "\(name) l")
            // continuity just past the boundary: eval(1.0+ε) stays close.
            XCTAssertLessThan(abs(IOPExpFit.eval(cc, 1.001) - endC), 1.0, "\(name) c step")
            // beyond 1.0 the fit must stay finite and ordered (g > 0 for
            // monotone tables).
            XCTAssertGreaterThan(cc[2], 0, "\(name) c exponent")
            XCTAssertGreaterThan(lc[2], 0, "\(name) l exponent")
        }
    }

    // MARK: - Track A: Lightamer kernel vs the synthesized references

    private static let trackAFixtures = [
        "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev", "saturated",
        "deep_shadow",
    ]

    func testColisaGoldenParity() async throws {
        let metal = try await makeMetal()
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runColisaPipe(
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
        XCTAssertTrue(failures.isEmpty, "colisa track A FAILED:\n" + failures.prefix(6).joined(separator: "\n"))
    }

    /// Lightamer leg: canonical fixture → [colorin, colisa] pipe → float32
    /// linear-Rec2020 RGB plane (colisa sorts after colorin by v50 order).
    private func runColisaPipe(
        image: DecodedImage, params: ColisaModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colisa = await registry.makeBox(opName: ColisaModule.opName)
        let colisaBox = try XCTUnwrap(colisa as? ModuleBox<ColisaModule>)
        colisaBox.setParams(params)
        let chain = [try XCTUnwrap(colorin), colisaBox]

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

    // MARK: - Kernel leg: neutral gray must stay neutral exactly

    /// The LabRoundTrip white anchoring makes neutrals a==b==0 exactly, so
    /// saturation cannot tint grays and contrast/brightness cannot shift
    /// the RGB ratios — a gray through ANY colisa params stays gray.
    func testKernelGraysStayNeutralUnderSaturation() async throws {
        let metal = try await makeMetal()
        let module = ColisaModule()
        var piece = IOPiece()
        let params = ColisaModule.Params(contrast: 0.5, brightness: -0.3, saturation: -1.0)
        module.commitParams(params, into: &piece)

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
            let r = out[i * 4], g = out[i * 4 + 1], b = out[i * 4 + 2]
            XCTAssertEqual(r, g, accuracy: 1e-6, "px\(i) R==G")
            XCTAssertEqual(g, b, accuracy: 1e-6, "px\(i) G==B")
            XCTAssertGreaterThan(r, 0.0) // contrast moved the LEVEL, not neutrality
        }
    }

    // MARK: - Track B: dual criteria with identity colisa inserted

    func testTrackBNeutralityWithColisaInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )
        let colisa = await registry.makeBox(opName: ColisaModule.opName)
        let colisaBox = try XCTUnwrap(colisa as? ModuleBox<ColisaModule>)
        colisaBox.setParams(.init()) // identity
        chain.append(colisaBox)
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
            "track B neutrality with colisa inserted FAILED:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Registration

    func testColisaRegisteredAtV50Slot47() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: ColisaModule.opName)
        _ = try XCTUnwrap(box as? ModuleBox<ColisaModule>)
        XCTAssertEqual(ColisaModule.opName, "colisa")
        XCTAssertEqual(ColisaModule.iopOrder, 47.0)
        XCTAssertEqual(ColisaModule.defaultColorspace, .Lab)
        let id = UUID()
        let restored = await registry.makeBox(opName: ColisaModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
    }
}
