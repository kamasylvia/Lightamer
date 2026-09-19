@testable import LightamerCore
import Metal
@testable import LightamerIOP
import XCTest

// ToneEqualKernelTests (Plan 03-05-T2/T3) — the Metal kernel units of the
// tone equalizer graph, driven directly (analytic synthetic inputs, r32
// readback after an L014 drain).
//
//   T2  luma_estimate: the SEVEN estimators against hand-computed values
//       (luminance_mask.h formulas) + the linear_contrast fulcrum path
//       (NORM_2 + boost vs toneequal.c:132's GUIDED/EIGF configuration).
//   T3  box mean / quantize / pack / blend: uniform-in = uniform-out,
//       delta-response analytic means, EIGF feathering→∞ degeneration to
//       the (gaussian) mean filter, identity pass-through.
final class ToneEqualKernelTests: XCTestCase {

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

    // MARK: - Texture helpers

    private func rgbaTexture(_ metal: MetalContext, _ pixels: [SIMD4<Float>], width: Int, height: Int) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let tex = metal.device.makeTexture(descriptor: d)!
        var data = pixels
        data.withUnsafeBytes {
            tex.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return tex
    }

    private func r32Texture(_ metal: MetalContext, width: Int, height: Int) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return metal.device.makeTexture(descriptor: d)!
    }

    /// Read back a single-channel float plane (r32Float via the rgba
    /// row layout — Metal r32 getBytes rows are 4 B/px).
    private func readR32(_ tex: any MTLTexture) -> [Float] {
        var data = [Float](repeating: 0, count: tex.width * tex.height)
        data.withUnsafeMutableBytes {
            tex.getBytes(
                $0.baseAddress!, bytesPerRow: tex.width * 4,
                from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        return data
    }

    private func uniformBytes<T>(_ value: T) -> [UInt8] {
        var v = value
        return withUnsafeBytes(of: &v) { Array($0) }
    }

    private func dispatch(
        _ metal: MetalContext, function: String,
        input: any MTLTexture, output: any MTLTexture,
        uniforms: [UInt8]? = nil,
        extraTextures: [any MTLTexture] = [],
        extraConfigure: (any MTLComputeCommandEncoder) -> Void = { _ in }
    ) async throws {
        let session = try await metal.makeEncoder(functionName: function)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        for (i, tex) in extraTextures.enumerated() {
            session.encoder.setTexture(tex, index: 2 + i)
        }
        if let uniforms {
            session.encoder.setBytes(uniforms, length: uniforms.count, index: 0)
        }
        extraConfigure(session.encoder)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    struct LumaUniforms {
        var method: Int32
        var exposureBoost: Float
        var fulcrum: Float
        var contrastBoost: Float
    }

    // MARK: - T2: the seven estimators (unboosted: fulcrum 0, boost 1)

    /// Each estimator on the asymmetric pixel (0.5, 0.25, 0.125) against
    /// its luminance_mask.h formula; exposure_boost = exp2(0.5) multiplies
    /// the RAW luminance (dt multiplies BEFORE linear_contrast).
    func testLumaEstimatorsAnalytic() async throws {
        let metal = try await makeMetal()
        let pixel: SIMD4<Float> = [0.5, 0.25, 0.125, 1.0]
        let input = rgbaTexture(metal, [pixel], width: 1, height: 1)
        let boost = Float(exp2(0.5))
        // (formula, expected luminance BEFORE contrast) — fulcrum 0 +
        // contrast 1 passes it through, then the MIN_FLOAT floor.
        let cases: [(Int, Float)] = [
            (0, boost * (0.5 + 0.25 + 0.125) / 3),              // mean
            (1, boost * (0.5 + 0.125) / 2),                     // lightness
            (2, boost * 0.5),                                   // value
            (3, boost * (0.5 + 0.25 + 0.125)),                  // norm1
            (4, boost * Float((0.25 + 0.0625 + 0.015625).squareRoot())), // norm2
            (5, boost * (0.125 + 0.015625 + 0.001953125) / (0.25 + 0.0625 + 0.015625)), // normPower
            (6, boost * Float(pow(0.5 * 0.25 * 0.125, 1.0 / 3.0))),     // geomean
        ]
        for (method, expected) in cases {
            let out = r32Texture(metal, width: 1, height: 1)
            let u = uniformBytes(
                LumaUniforms(method: Int32(method), exposureBoost: boost, fulcrum: 0, contrastBoost: 1))
            try await dispatch(
                metal, function: ToneEqualKernel.lumaEstimateFunction,
                input: input, output: out, uniforms: u)
            drain(metal)
            let values = readR32(out)
            XCTAssertEqual(
                Double(values[0]), Double(expected), accuracy: 1e-6,
                "estimator \(method)")
        }
    }

    /// linear_contrast with the dt GUIDED/EIGF configuration (fulcrum =
    /// exp2(−4), contrast = exp2(boost EV)): slope around the fulcrum,
    /// MIN_FLOAT floor, and the UNBOOSTED modes' fulcrum-0/contrast-1.
    func testLumaLinearContrastFulcrum() async throws {
        let metal = try await makeMetal()
        let input = rgbaTexture(metal, [[0.03125, 0.03125, 0.03125, 1]], width: 1, height: 1) // −5 EV
        let contrast = Float(exp2(2.0))
        let out = r32Texture(metal, width: 1, height: 1)
        let u = uniformBytes(LumaUniforms(
            method: 4, exposureBoost: 1,
            fulcrum: Float(exp2(-4.0)), contrastBoost: contrast))
        try await dispatch(
            metal, function: ToneEqualKernel.lumaEstimateFunction,
            input: input, output: out, uniforms: u)
        drain(metal)
        let values = readR32(out)
        // norm2 of a gray v = v·√3; linear_contrast about exp2(−4) with
        // contrast 4: (v·√3 − f)·4 + f.
        let fulcrum: Float = 0.0625
        let norm2: Float = 0.03125 * (3.0 as Float).squareRoot()
        let expected: Float = (norm2 - fulcrum) * 4.0 + fulcrum
        XCTAssertEqual(Double(values[0]), Double(expected), accuracy: 1e-6)

        // The MIN_FLOAT floor: a hard-zero input (norm2 = 0) with fulcrum 0
        // clamps to exp2(−16), never zero (luminance_mask.h:52-56).
        let zero = rgbaTexture(metal, [[0, 0, 0, 1]], width: 1, height: 1)
        let out2 = r32Texture(metal, width: 1, height: 1)
        let u2 = uniformBytes(LumaUniforms(method: 4, exposureBoost: 1, fulcrum: 0, contrastBoost: 1))
        try await dispatch(
            metal, function: ToneEqualKernel.lumaEstimateFunction,
            input: zero, output: out2, uniforms: u2)
        drain(metal)
        XCTAssertEqual(readR32(out2)[0], Float(exp2(-16.0)), accuracy: 0, "MIN_FLOAT floor")
    }
}
