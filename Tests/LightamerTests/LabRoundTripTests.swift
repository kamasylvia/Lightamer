@testable import LightamerCore
import Foundation
import LightamerIOP
import Metal
import XCTest

// LabRoundTripTests (Plan 03-03-T1) — the shared Lab-domain component:
//
//   1. Known vectors (Double CPU): Rec2020 white → L=100/a=b=0 EXACT
//      (the white-anchored reference-white decision); 50% gray → a=b=0,
//      L ≈ 76.07; the three primaries against design-time-computed
//      constants.
//   2. Random-domain round-trip identity (Double): < 1e-9 (measured
//      ~2.4e-15) across in-domain AND out-of-domain values (negative /
//      >1 components — the spectral fixtures) — the conversion is
//      unbounded by design (dt Lab semantics: no clamping).
//   3. GPU leg: the Metal float32 conversion vs the CPU Double reference
//      on the same vectors + a float32 round-trip identity gate.
//   4. Track B dual criterion: a Lab forward+inverse pair inserted into
//      the default chain leaves the rendered output unchanged within
//      float32 rounding.
final class LabRoundTripTests: XCTestCase {

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

    // MARK: - 1. Known vectors (CPU Double)

    func testKnownVectorsWhiteAndGrays() {
        // D65/Rec2020 white through the SAME constants → exact (100, 0, 0).
        let white = LabRoundTrip.rec2020ToLab(SIMD3(1.0, 1.0, 1.0))
        XCTAssertEqual(white.x, 100.0, accuracy: 1e-9)
        XCTAssertEqual(white.y, 0.0, accuracy: 1e-9)
        XCTAssertEqual(white.z, 0.0, accuracy: 1e-9)

        // Every neutral maps to a == b == 0 exactly (both f() branches are
        // homogeneous): a dark gray exercises the linear branch of f().
        for v in [0.5, 0.214, 0.001, 0.25, 0.9] {
            let lab = LabRoundTrip.rec2020ToLab(SIMD3(v, v, v))
            XCTAssertEqual(lab.y, 0.0, accuracy: 1e-9, "gray \(v) a")
            XCTAssertEqual(lab.z, 0.0, accuracy: 1e-9, "gray \(v) b")
        }
        // 50% gray L (design-time computed constant).
        let gray = LabRoundTrip.rec2020ToLab(SIM3_GRAY)
        XCTAssertEqual(gray.x, 76.069261014156, accuracy: 1e-9)
    }

    private var SIM3_GRAY: SIMD3<Double> { SIMD3(0.5, 0.5, 0.5) }

    func testKnownVectorsPrimaries() {
        // Design-time Double reference values (same constants, independent
        // evaluation during plan execution).
        let cases: [(rgb: SIMD3<Double>, lab: SIMD3<Double>)] = [
            (SIMD3(1, 0, 0), SIMD3(59.799905179, 116.895209691, 106.745650041)),
            (SIMD3(0, 1, 0), SIMD3(85.773497089, -160.726621010, 109.233598006)),
            (SIMD3(0, 0, 1), SIMD3(25.451686944, 74.477921820, -126.239516543)),
        ]
        for (rgb, expected) in cases {
            let got = LabRoundTrip.rec2020ToLab(rgb)
            for c in 0..<3 {
                XCTAssertEqual(got[c], expected[c], accuracy: 1e-7, "primary \(rgb) ch\(c)")
            }
        }
    }

    // MARK: - 2. Round-trip identity (CPU Double, unbounded domain)

    func testRoundTripIdentityDouble() {
        var seed: UInt64 = 0x4c41424c // deterministic LCG
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        var worst = 0.0
        for _ in 0..<20_000 {
            // In-domain + out-of-domain mix (spectral fixtures go negative).
            let v = SIMD3(next() * 1.7 - 0.2, next() * 1.7 - 0.2, next() * 1.7 - 0.2)
            let back = LabRoundTrip.labToRec2020(LabRoundTrip.rec2020ToLab(v))
            worst = max(worst, max(abs(back.x - v.x), abs(back.y - v.y), abs(back.z - v.z)))
        }
        XCTAssertLessThan(worst, 1e-9, "Double round-trip identity (plan gate < 1e-6)")
    }

    func testUnboundedSemanticsNoNaN() {
        // Out-of-domain Lab (L < 0 / L > 100) and negative Rec2020 both stay
        // finite and round-trip — dt Lab modules rely on unbounded values.
        let overshoot = LabRoundTrip.rec2020ToLab(SIMD3(1.5, 1.5, 1.5))
        XCTAssertGreaterThan(overshoot.x, 100.0)
        let back = LabRoundTrip.labToRec2020(overshoot)
        for c in 0..<3 {
            XCTAssertTrue(back[c].isFinite)
            XCTAssertEqual(back[c], 1.5, accuracy: 1e-9)
        }
        let negative = LabRoundTrip.rec2020ToLab(SIMD3(-0.1, 0.4, 0.8))
        let backNeg = LabRoundTrip.labToRec2020(negative)
        for c in 0..<3 {
            XCTAssertTrue(negative[c].isFinite)
            XCTAssertEqual(backNeg[c], [-0.1, 0.4, 0.8][c], accuracy: 1e-9)
        }
    }

    // MARK: - 3. GPU leg (Metal float32 vs CPU Double)

    private struct LabTestKernel {
        static let forward = "lab_roundtrip_forward"
        static let inverse = "lab_roundtrip_inverse"
    }

    private func makeTexture(_ metal: MetalContext, _ pixels: [[Float]]) throws -> (any MTLTexture, any MTLTexture, any MTLTexture) {
        let n = pixels.count
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: n, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let mid = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        var data = [Float](repeating: 0, count: n * 4)
        for (i, px) in pixels.enumerated() {
            data[i * 4] = px[0]
            data[i * 4 + 1] = px[1]
            data[i * 4 + 2] = px[2]
            data[i * 4 + 3] = 1.0
        }
        data.withUnsafeBytes {
            input.replace(region: MTLRegionMake2D(0, 0, n, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: n * 16)
        }
        return (input, mid, output)
    }

    private func readTexture(_ texture: any MTLTexture) -> [Float] {
        var out = [Float](repeating: 0, count: texture.width * texture.height * 4)
        out.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return out
    }

    func testGPULabConversionMatchesCPU() async throws {
        let metal = try await makeMetal()
        // White, 50% gray, primaries, a mid chromatic, an out-of-domain value.
        let pixels: [[Float]] = [
            [1, 1, 1], [0.5, 0.5, 0.5], [1, 0, 0], [0, 1, 0], [0, 0, 1],
            [0.3, 0.7, 0.2], [0.05, 0.9, 0.4], [1.2, 0.3, 0.6],
        ]
        let (input, mid, output) = try makeTexture(metal, pixels)
        try await metal.dispatch2DTexture(functionName: LabTestKernel.forward, input: input, output: mid)
        try await metal.dispatch2DTexture(functionName: LabTestKernel.inverse, input: mid, output: output)
        drain(metal) // L014

        let lab = readTexture(mid)
        let back = readTexture(output)

        for (i, px) in pixels.enumerated() {
            let rgb = SIMD3<Double>(Double(px[0]), Double(px[1]), Double(px[2]))
            let expected = LabRoundTrip.rec2020ToLab(rgb)
            // float32 matrix chain + cbrt: abs tolerance on L (≤ ~100) is
            // ~1e-4; a/b around zero use the same absolute floor.
            for c in 0..<3 {
                XCTAssertEqual(
                    lab[i * 4 + c], Float(expected[c]), accuracy: 5e-4,
                    "px\(i) lab ch\(c)"
                )
            }
            // Round-trip identity through the GPU (float32): plan gate
            // < 1e-6 for in-domain values — measured float32 worst ~1.5e-6
            // over the extrapolation range; the [0, 1.2] domain here holds
            // the gate.
            for c in 0..<3 {
                if px[c] <= 1.0 {
                    XCTAssertEqual(back[i * 4 + c], Float(px[c]), accuracy: 1e-6, "px\(i) roundtrip ch\(c)")
                } else {
                    XCTAssertEqual(back[i * 4 + c], Float(px[c]), accuracy: 1e-5, "px\(i) roundtrip ch\(c)")
                }
            }
            XCTAssertEqual(lab[i * 4 + 3], 1.0) // alpha untouched
        }
    }

    // MARK: - 4. Track B dual criterion: Lab pair inserted → output unchanged

    /// A minimal IOPModule applying `lab_roundtrip_forward` then
    /// `_inverse` — the "Lab round-trip inserted with identity params"
    /// probe for the track-B criterion (no registration; test-only).
    private struct LabRoundTripProbeModule: IOPModule {
        struct Params: Codable & Hashable { }

        static var opName: String { "labroundtrip_probe" }
        static var iopOrder: Float { 60.0 }
        static var flags: IOPFlags { [.allowTiling] }
        static var defaultColorspace: IOPColorspace { .Lab }

        func reloadDefaults(image: DecodedImage) async -> Params { Params() }
        func commitParams(_ params: Params, into piece: inout IOPiece) async {
            piece.paramsHash = 0xC0FFEE
        }
        func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) { roi = input }
        func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) { input = roi }

        func process(
            input: any MTLTexture, output: any MTLTexture,
            roiIn: ROI, roiOut: ROI, piece: inout IOPiece, metal: MetalContext
        ) async throws {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: input.width, height: input.height, mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            guard let mid = metal.device.makeTexture(descriptor: descriptor) else {
                throw MetalError.deviceUnavailable
            }
            try await metal.dispatch2DTexture(functionName: LabTestKernel.forward, input: input, output: mid)
            try await metal.dispatch2DTexture(functionName: LabTestKernel.inverse, input: mid, output: output)
        }
    }

    func testTrackBLabPairInsertionKeepsOutput() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let baseChain = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )

        func render(_ chain: [any ModuleBoxing]) async throws -> [UInt8] {
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
            return bytes
        }

        let base = try await render(baseChain)

        var probeBox = ModuleBox(module: LabRoundTripProbeModule(), instanceID: UUID())
        await probeBox.setParams(LabRoundTripProbeModule.Params())
        let probeChain = baseChain + [probeBox]
        let withProbe = try await render(probeChain)

        XCTAssertEqual(base.count, withProbe.count)
        var worst = 0
        for i in 0..<base.count {
            worst = max(worst, abs(Int(base[i]) - Int(withProbe[i])))
        }
        // The Lab pair reintroduces the display conversion with ~1e-6 float
        // noise; after the 8-bit display encode the round trip must be
        // visually byte-stable (≤ 1 LSB).
        XCTAssertLessThanOrEqual(worst, 1, "track B: Lab pair insertion changed output by \(worst)")
        _ = LabRoundTripProbeModule.self
    }
}
