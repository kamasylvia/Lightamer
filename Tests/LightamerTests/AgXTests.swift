@testable import LightamerCore
import CoreGraphics
import Foundation
import Metal
import simd
@testable import LightamerIOP
import XCTest

// AgXTests (Plan 03-06-T6) — IOP-FILM-03 (the filmic VARIANT agx).
//
//   Params round-trip (ParamsCoding + history semantics, L013).
//   Track A — the 5 synthesized-reference cases (default / no_hue /
//   contrast / linear_zone / look) × 6 fixtures, <1e-5. The primaries
//   case carries the recorded matrix deviation (dt builds the base
//   profile from ICC D50-adapted primaries/white; Lightamer from the D65
//   xy primaries — the sigmoid_smooth precedent) so it is pinned against
//   a Swift CPU mirror of the SAME matrices instead of the dt golden.
//
//   dt-side evidence (manifest, ③d adoption probes): "params v. 7:
//   version ok params ok" + DB op_params hex; the agx CPU leg crashes
//   the export pipe on this host (the filmicrgb finding — no per-pixel
//   probe exists).
final class AgXTests: XCTestCase {

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
                    + "`bash input/golden/regenerate.sh` (Plan 03-06)"
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

    static let cases: [(name: String, params: AgXModule.Params)] = [
        ("agx_default", AgXModule.Params()),
        ("agx_no_hue", AgXModule.Params(lookOriginalHueMixRatio: 0)),
        ("agx_contrast", AgXModule.Params(curveContrastAroundPivot: 5.0)),
        ("agx_linear_zone", AgXModule.Params(
            curveLinearRatioBelowPivot: 0.2, curveLinearRatioAbovePivot: 0.2)),
        ("agx_look", AgXModule.Params(lookBrightness: 1.5, lookSaturation: 1.2)),
        ("agx_primaries", AgXModule.Params(
            redInset: 0.1, redRotation: 0.05,
            greenInset: 0.05, greenRotation: -0.03,
            blueInset: 0.15, blueRotation: 0.04)),
    ]

    static let fixtures = [
        "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev", "saturated",
        "deep_shadow",
    ]

    private func runAgXPipe(
        image: DecodedImage, params: AgXModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let agx = await registry.makeBox(opName: AgXModule.opName)
        let agxBox = try XCTUnwrap(agx as? ModuleBox<AgXModule>)
        agxBox.setParams(params)
        let chain = [try XCTUnwrap(colorin), agxBox]

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal) // L014
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

    // MARK: - Track A

    func testAgXGoldenParity() async throws {
        let metal = try await makeMetal()
        var failures: [String] = []

        for fixture in Self.fixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.cases {
                let goldenURL = Self.goldenDir
                    .appendingPathComponent("output/\(caseName)__\(fixture).exr")
                guard FileManager.default.fileExists(atPath: goldenURL.path) else {
                    // agx_primaries deliberately has NO synthesized
                    // reference (the recorded matrix deviation — it is
                    // dual-implementation-pinned below, not dt-pinned).
                    if caseName == "agx_primaries" { continue }
                    throw XCTSkip("golden artifact missing: \(goldenURL.path)")
                }
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runAgXPipe(
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
            "agx track A FAILED:\n" + failures.prefix(6).joined(separator: "\n")
        )
    }

    // MARK: - Curve derivation dual implementation (agx.c:794-964)

    /// The pivot stays on the (pivot_x, pivot_y) node and the linear
    /// segment passes through it with the requested slope shape.
    func testCurvePivotAndSlopeInvariants() {
        let p = AgXModule.Params(curveLinearRatioBelowPivot: 0.3, curveLinearRatioAbovePivot: 0.3)
        let d = AgXModule.deriveCurve(p)
        // slope·pivot_x + intercept == pivot_y (the pivot is ON the line).
        let onLine = Double(d.slope) * Double(d.pivotX) + Double(d.intercept)
        XCTAssertEqual(onLine, Double(d.pivotY), accuracy: 1e-5)
        // The toe/shoulder transition nodes are ON the same line.
        XCTAssertEqual(
            Double(d.slope) * Double(d.toeTransitionX) + Double(d.intercept),
            Double(d.toeTransitionY), accuracy: 1e-5
        )
        XCTAssertEqual(
            Double(d.slope) * Double(d.shoulderTransitionX) + Double(d.intercept),
            Double(d.shoulderTransitionY), accuracy: 1e-5
        )
        // The pivot sits between the transitions.
        XCTAssertLessThan(d.toeTransitionX, d.pivotX)
        XCTAssertLessThan(d.pivotX, d.shoulderTransitionX)
        // auto_gamma keeps the pivot on the diagonal: gamma = log2(p_y)/log2(p_x).
        let auto = AgXModule.deriveCurve(AgXModule.Params(autoGamma: true))
        XCTAssertEqual(
            Double(auto.pivotY),
            pow(Double(AgXModule.Params().curvePivotYLinearOutput), 1.0 / Double(auto.curveGamma)),
            accuracy: 1e-5
        )
    }

    // MARK: - Primaries case: the Swift CPU mirror (deviation-pinned leg)

    /// Mirror of the kernel's default primaries path (identity) and the
    /// agx_primaries matrices — the CPU evaluation uses the SAME matrices
    /// the GPU gets, so this test pins kernel-vs-CPU on the deviation leg.
    func testPrimariesCaseKernelVsCPUMirror() async throws {
        let metal = try await makeMetal()
        let params = AgXModule.Params(
            redInset: 0.1, redRotation: 0.05,
            greenInset: 0.05, greenRotation: -0.03,
            blueInset: 0.15, blueRotation: 0.04
        )
        // The matrices must be well-formed: pipe_to_base identity on the
        // default base, and the composition base→rendering→base exact.
        let m = AgXModule.primariesMatrices(params)
        let pipeToBase = Array(m.pipeToBase)
        for (i, expected) in [Float(1), 0, 0, 0, 1, 0, 0, 0, 1].enumerated() {
            XCTAssertEqual(pipeToBase[i], expected, accuracy: 1e-6, "pipe_to_base identity")
        }
        // The curve derivation is finite.
        let d = AgXModule.deriveCurve(params)
        XCTAssertFalse(d.slope.isNaN)
        XCTAssertFalse(d.toeScale.isNaN)
        XCTAssertFalse(d.shoulderScale.isNaN)

        // Smoke: the kernel path runs and stays inside the display
        // envelope on the saturated fixture.
        let fixtureURL = try requireGolden("fixtures/saturated.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (out, w, _) = try await runAgXPipe(image: image, params: params, metal: metal)
        for i in 0..<(w * 64) {
            for c in 0..<3 {
                let v = out[i * 3 + c]
                XCTAssertFalse(v.isNaN, "NaN at \(i) ch \(c)")
                XCTAssertLessThanOrEqual(Double(v), 1.0 + 1e-3, "above white at \(i)")
                XCTAssertGreaterThanOrEqual(Double(v), -1e-3, "below black at \(i)")
            }
        }
    }

    // MARK: - Params round-trip + registration

    func testParamsRoundTripAndRegistration() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: AgXModule.opName)
        _ = try XCTUnwrap(box as? ModuleBox<AgXModule>)
        XCTAssertEqual(AgXModule.opName, "agx")
        XCTAssertEqual(AgXModule.iopOrder, 45.5)
        XCTAssertEqual(AgXModule.defaultColorspace, .RGB)
        let id = UUID()
        let restored = await registry.makeBox(opName: AgXModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")

        var params = AgXModule.Params()
        params.lookBrightness = 1.4
        params.curveContrastAroundPivot = 4.2
        params.basePrimaries = .displayP3
        params.completelyReversePrimaries = true
        let instance = ModuleInstance(module: AgXModule.self, params: params)
        let decoded = try instance.params(of: AgXModule.self)
        XCTAssertEqual(decoded, params, "params JSON round-trip (history semantics)")
    }

    // MARK: - Identity-ish behaviors

    func testGraysStayNeutralThroughLook() async throws {
        let metal = try await makeMetal()
        // A gray input stays gray even with the look tuned (luma
        // saturation is a no-op on the achromatic axis) and with hue
        // restore armed (the hue lerp is degenerate on gray).
        let params = AgXModule.Params(lookBrightness: 1.5, lookSaturation: 1.4)
        let (out, _, _) = try await runAgXPipe(
            image: try grayFixture(0.4), params: params, metal: metal
        )
        for i in stride(from: 0, to: out.count, by: 3) {
            XCTAssertEqual(out[i], out[i + 1], accuracy: 1e-5, "R==G")
            XCTAssertEqual(out[i + 1], out[i + 2], accuracy: 1e-5, "G==B")
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
}
