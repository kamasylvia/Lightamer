@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmPlacementKernelTests (Plan M3-3-02 T4, KD-5 — IOPParity bundle, the
// *Kernel* domain convention) — the placement kernel's SMOKE gate (the
// per-pixel golden body = M3-3-03):
//
//   1. IDENTITY bit-exact: both pull-backs zero → the output bytes equal
//      the input bytes (the early-exit copy — the GradeCatalog identityJSON
//      contract, pixel tolerance 0).
//   2. GPU vs the Float64 scalar reference on a probe field (light gate —
//      the golden gate's tolerances arrive with M3-3-03).
//   3. m-ORDER KNEE CONTACT smoke: the delta at the knee vanishes to
//      higher order as m grows (|δ(Δ→0⁺)| shrinks with m — the §5.5
//      curvature-step removal).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmPlacementKernelTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: FilmPlacementKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    private let size = (width: 16, height: 12)

    private func makeTexture(
        _ metal: MetalContext, texels: [Float]
    ) -> (input: any MTLTexture, output: any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: size.width, height: size.height,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        texels.withUnsafeBytes {
            input.replace(
                region: MTLRegionMake2D(0, 0, size.width, size.height),
                mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: size.width * 16)
        }
        return (input, output)
    }

    private func read(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        drain(metal)
        var values = [Float](repeating: 0, count: size.width * size.height * 4)
        values.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: size.width * 16,
                from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0)
        }
        return values
    }

    /// ACEScc-encoded probe field spanning deep shadows to far highlights
    /// (mid-gray anchored, ±16 stops on a neutral ramp + chroma variants).
    private func probeField() -> [Float] {
        var texels = [Float](repeating: 0, count: size.width * size.height * 4)
        var seed: UInt64 = 0x5DEECE66D
        for index in 0..<(size.width * size.height) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let u = Double((seed >> 11) & 0xFFFFFF) / Double(0xFFFFFF)
            let ev = -16.0 + 32.0 * u
            let base = 0.184 * Foundation.pow(2.0, ev)
            let linear = SIMD3(base, base * 0.9, base * 1.1)  // slight chroma
            texels[index * 4 + 0] = Float(Cat02WBMath.acesccEncode(linear.x))
            texels[index * 4 + 1] = Float(Cat02WBMath.acesccEncode(linear.y))
            texels[index * 4 + 2] = Float(Cat02WBMath.acesccEncode(linear.z))
            texels[index * 4 + 3] = 1.0
        }
        return texels
    }

    // MARK: - 1: identity bit-exact

    func testIdentityParamsAreByteExactPassThrough() async throws {
        let metal = try await makeMetal()
        let texels = probeField()
        let module = FilmPlacementModule()
        var piece = IOPiece()
        module.commitParams(FilmPlacementModule.Params(), into: &piece)
        XCTAssertNil(piece.data, "the identity point commits NO uniforms (the flag path)")
        let (input, output) = makeTexture(metal, texels: texels)
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = read(output, metal: metal)
        XCTAssertEqual(out, texels, "the identity op is a bit-exact copy (tolerance 0)")
    }

    // MARK: - 2: GPU vs the Float64 scalar reference (light)

    func testKernelMatchesTheScalarReferenceOnProbeField() async throws {
        let metal = try await makeMetal()
        // The RESOLVED face (M3-4-01): the knees ride the params, solved
        // against the fallback anchors (valid demands only — minimum 3.0).
        let a = FilmPlacementModule.sceneTopEV
        let c = FilmPlacementModule.mediumTopEV
        let aS = FilmPlacementModule.sceneBottomEV
        let cS = FilmPlacementModule.mediumBottomEV
        let hi = FilmPlacementModule.solveKnee(
            pullBack: 3.25, rolloff: 2, sceneExtreme: a, mediumBoundary: c)!
        let lo = FilmPlacementModule.solveKnee(
            pullBack: 3.05, rolloff: 2, sceneExtreme: aS, mediumBoundary: cS)!
        let params = FilmPlacementModule.Params(
            shadowsPullBack: 3.05, highlightsPullBack: 3.25, rolloff: 2,
            kShadow: lo.knee, hShadow: lo.room,
            kHighlight: hi.knee, hHighlight: hi.room)
        let texels = probeField()
        let module = FilmPlacementModule(device: metal.device)
        var piece = IOPiece()
        module.commitParams(params, into: &piece)
        let (input, output) = makeTexture(metal, texels: texels)
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = read(output, metal: metal)
        // Both sides compared in ACEScc (the domain the op lives in); the
        // smoke gate is deliberately loose (the golden gate = FilmGoldenTests).
        var maxDiff: Float = 0
        for index in 0..<(size.width * size.height) {
            let encoded = SIMD3(
                Double(texels[index * 4]), Double(texels[index * 4 + 1]),
                Double(texels[index * 4 + 2]))
            let linear = SIMD3(
                Cat02WBMath.acesccDecode(encoded.x),
                Cat02WBMath.acesccDecode(encoded.y),
                Cat02WBMath.acesccDecode(encoded.z))
            let (gain, onBranch) = FilmPlacementModule.placementGain(linear, params: params)
            let expected: SIMD3<Double> =
                onBranch ? linear * gain : linear
            let actual = SIMD3(
                Double(out[index * 4]), Double(out[index * 4 + 1]),
                Double(out[index * 4 + 2]))
            let expectedEncoded = SIMD3(
                Cat02WBMath.acesccEncode(expected.x),
                Cat02WBMath.acesccEncode(expected.y),
                Cat02WBMath.acesccEncode(expected.z))
            for c in 0..<3 {
                maxDiff = max(maxDiff, Float(abs(actual[c] - expectedEncoded[c])))
            }
        }
        XCTAssertLessThanOrEqual(
            maxDiff, 2e-3,
            "GPU vs Float64 reference on the encoded axis (smoke; golden = FilmGoldenTests)")
    }

    // MARK: - 3: the m-order knee contact (smoke)

    func testHigherOrderKneeHasSmallerNearKneeDelta() {
        // §5.5/§7.3: higher m bends EARLIER (the knee sits lower) but with
        // a FLATTER start — the COMPRESSION delta (Δ − g_m(Δ)) just past
        // the knee SHRINKS with m (the C^m contact: δ ~ Δ^(m+1) scale).
        func nearKneeDelta(m: Double) -> Double {
            let sol = FilmPlacementModule.solveKnee(
                pullBack: 4.0, rolloff: m,
                sceneExtreme: FilmPlacementModule.sceneTopEV,
                mediumBoundary: FilmPlacementModule.mediumTopEV)!
            let excursion = 1e-3
            let placed = FilmPlacementModule.smoothMin(excursion, sol.room, m)
            return excursion - placed   // the compression delta at the excursion
        }
        let d1 = nearKneeDelta(m: 1)
        let d2 = nearKneeDelta(m: 2)
        let d4 = nearKneeDelta(m: 4)
        XCTAssertGreaterThan(d1, d2, "m=2's near-knee delta is smaller (the C² contact)")
        XCTAssertGreaterThan(d2, d4, "m=4's is smaller still")
        // And every order is C⁰ at the knee: the delta vanishes as the
        // excursion does (order-of-contact probe at 1e-3 → the m=2 delta
        // is ~1e-11 — the curvature step is gone).
        XCTAssertLessThan(d2, 1e-9, "m=2 starts flat at the knee")
    }
}
