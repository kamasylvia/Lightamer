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

    // MARK: - T3: the filter kernel cluster

    private struct BilinearUniforms {
        var srcWidth: UInt32
        var srcHeight: UInt32
        var dstWidth: UInt32
        var dstHeight: UInt32
    }

    private struct QuantizeUniforms {
        var sampling: Float
        var clipMin: Float
        var clipMax: Float
    }

    private struct BlendUniforms {
        var mode: Int32
        var upsample: Int32
        var geomean: Int32
        var feathering: Float
        var auxWidth: UInt32
        var auxHeight: UInt32
        var srcWidth: UInt32
        var srcHeight: UInt32
    }

    private func rgbaPlane(_ metal: MetalContext, width: Int, height: Int) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        return metal.device.makeTexture(descriptor: d)!
    }

    private func fill(_ tex: any MTLTexture, _ pixels: [SIMD4<Float>]) {
        var data = pixels
        data.withUnsafeBytes {
            tex.replace(
                region: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: tex.width * 16)
        }
    }

    private func readRGBA(_ tex: any MTLTexture) -> [SIMD4<Float>] {
        var data = [SIMD4<Float>](repeating: .zero, count: tex.width * tex.height)
        data.withUnsafeMutableBytes {
            tex.getBytes(
                $0.baseAddress!, bytesPerRow: tex.width * 16,
                from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        return data
    }

    /// Uniform input → uniform output on the box mean (boundary windows
    /// included), < 1e-6.
    func testBoxMeanUniformInUniformOut() async throws {
        let metal = try await makeMetal()
        let size = 13
        let input = rgbaPlane(metal, width: size, height: size)
        fill(input, [SIMD4<Float>](repeating: SIMD4(0.37, 1.1, -2.0, 4.0), count: size * size))
        let output = rgbaPlane(metal, width: size, height: size)
        var radius: UInt32 = 3
        try await dispatchBox(metal, input: input, output: output, radius: &radius, horizontal: true)
        try await dispatchBox(metal, input: output, output: input, radius: &radius, horizontal: false)
        drain(metal)
        for (i, v) in readRGBA(input).enumerated() {
            XCTAssertEqual(Double(v.x), 0.37, accuracy: 1e-6, "ch r at \(i)")
            XCTAssertEqual(Double(v.y), 1.1, accuracy: 1e-6, "ch g at \(i)")
            XCTAssertEqual(Double(v.z), -2.0, accuracy: 1e-6, "ch b at \(i)")
            XCTAssertEqual(Double(v.w), 4.0, accuracy: 1e-6, "ch a at \(i)")
        }
    }

    /// Delta response: a unit impulse blurs to the analytic truncated-window
    /// mean — total mass conserved to < 1e-6, the center pixel carrying
    /// exactly the full-window share.
    func testBoxMeanDeltaResponse() async throws {
        let metal = try await makeMetal()
        let size = 17
        let radius = 4
        var pixels = [SIMD4<Float>](repeating: .zero, count: size * size)
        pixels[(size / 2) * size + size / 2] = SIMD4(1, 1, 1, 1)
        let input = rgbaPlane(metal, width: size, height: size)
        fill(input, pixels)
        let output = rgbaPlane(metal, width: size, height: size)
        var r = UInt32(radius)
        try await dispatchBox(metal, input: input, output: output, radius: &r, horizontal: true)
        try await dispatchBox(metal, input: output, output: input, radius: &r, horizontal: false)
        drain(metal)
        let values = readRGBA(input)
        var total: Float = 0
        for v in values { total += v.x }
        XCTAssertEqual(Double(total), 1.0, accuracy: 1e-6, "mass conservation")
        let window = Float((2 * radius + 1) * (2 * radius + 1))
        XCTAssertEqual(
            Double(values[(size / 2) * size + size / 2].x), Double(1.0 / window),
            accuracy: 1e-6, "center = full-window mean")
    }

    private func dispatchBox(
        _ metal: MetalContext, input: any MTLTexture, output: any MTLTexture,
        radius: inout UInt32, horizontal: Bool
    ) async throws {
        let session = try await metal.makeEncoder(
            functionName: horizontal ? ToneEqualKernel.boxMeanXFunction : ToneEqualKernel.boxMeanYFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(&radius, length: MemoryLayout<UInt32>.stride, index: 0)
        if horizontal {
            session.encoder.dispatchThreads(
                MTLSize(width: 1, height: input.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 16, depth: 1))
        } else {
            session.encoder.dispatchThreads(
                MTLSize(width: input.width, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 1, depth: 1))
        }
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// EIGF degeneration: with feathering → ∞ the solve collapses to
    /// a=0, b=avg — the blend output equals the (gaussian) mean filter,
    /// cross-checked against the SHARED GaussianBlur primitive on the same
    /// plane (different kernel source, same math).
    func testEIGFBlendDegradesToGaussianMean() async throws {
        let metal = try await makeMetal()
        let size = 12
        var pixels = [SIMD4<Float>](repeating: .zero, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                // A smooth varying field (all positive — the luma domain).
                let v = 0.2 + 0.05 * Float(x) + 0.03 * Float(y) + 0.1 * sin(Float(x * y))
                pixels[y * size + x] = SIMD4(v, 0, 0, 0)
            }
        }
        let guide = rgbaPlane(metal, width: size, height: size)
        fill(guide, pixels)
        let packed = rgbaPlane(metal, width: size, height: size)
        let blurred = rgbaPlane(metal, width: size, height: size)

        // pack4 (no-mask: guide twice)
        let packSession = try await metal.makeEncoder(functionName: ToneEqualKernel.pack4Function)
        packSession.encoder.setTexture(guide, index: 0)
        packSession.encoder.setTexture(guide, index: 1)
        packSession.encoder.setTexture(packed, index: 2)
        packSession.encoder.dispatchThreads(
            MTLSize(width: size, height: size, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        packSession.encoder.endEncoding()
        packSession.commandBuffer.commit()

        // The gaussian leg (σ=1.5, the luma-domain constant bounds).
        let planes = metal.device.makeBuffer(
            length: size * size * 16 * 2, options: .storageModeShared)!
        try await GaussianBlur.blur(
            input: packed, output: blurred, planes: planes,
            sigma: 1.5,
            boundsMin: SIMD4(repeating: Float(exp2(-16.0))),
            boundsMax: SIMD4(repeating: Float.greatestFiniteMagnitude),
            metal: metal)

        // blend mode 0 (no-mask EIGF) with feathering 1e12 → a≈0, b=avg.
        let out = rgbaPlane(metal, width: size, height: size)
        let u = uniformBytes(BlendUniforms(
            mode: 0, upsample: 0, geomean: 0, feathering: 1e12,
            auxWidth: UInt32(size), auxHeight: UInt32(size),
            srcWidth: UInt32(size), srcHeight: UInt32(size)))
        let blendSession = try await metal.makeEncoder(functionName: ToneEqualKernel.blendFunction)
        blendSession.encoder.setTexture(guide, index: 0)
        blendSession.encoder.setTexture(guide, index: 1)
        blendSession.encoder.setTexture(blurred, index: 2)
        blendSession.encoder.setTexture(out, index: 3)
        blendSession.encoder.setBytes(u, length: u.count, index: 0)
        blendSession.encoder.dispatchThreads(
            MTLSize(width: size, height: size, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        blendSession.encoder.endEncoding()
        blendSession.commandBuffer.commit()
        drain(metal)

        // Cross-check: blend result == gaussian-blurred r channel.
        let reference = rgbaPlane(metal, width: size, height: size)
        try await GaussianBlur.blur(
            input: guide, output: reference, planes: planes,
            sigma: 1.5,
            boundsMin: SIMD4(repeating: Float(exp2(-16.0))),
            boundsMax: SIMD4(repeating: Float.greatestFiniteMagnitude),
            metal: metal)
        drain(metal)
        let got = readRGBA(out)
        let want = readRGBA(reference)
        for i in 0..<got.count {
            XCTAssertEqual(Double(got[i].x), Double(want[i].x), accuracy: 1e-5, "px \(i)")
        }
    }

    /// Bilinear downsample of a uniform field stays uniform (the dt corner
    /// convention included), and the upsample round-trip on a linear ramp
    /// reproduces the ramp within the interpolation's own error.
    func testBilinearDownsampleUniform() async throws {
        let metal = try await makeMetal()
        let input = rgbaPlane(metal, width: 16, height: 16)
        fill(input, [SIMD4<Float>](repeating: SIMD4(0.73, 0, 0, 0), count: 256))
        let output = rgbaPlane(metal, width: 4, height: 4)
        let u = uniformBytes(BilinearUniforms(
            srcWidth: 16, srcHeight: 16, dstWidth: 4, dstHeight: 4))
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.bilinear1cFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(u, length: u.count, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: 4, height: 4, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 4, height: 4, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        drain(metal)
        for (i, v) in readRGBA(output).enumerated() {
            XCTAssertEqual(Double(v.x), 0.73, accuracy: 1e-6, "px \(i)")
        }
    }

    /// quantize: sampling 1 floors to whole EVs; the clip bounds apply.
    func testQuantizeSteps() async throws {
        let metal = try await makeMetal()
        let values: [Float] = [0.3, 0.6, 1.7, 0.001]
        let input = rgbaPlane(metal, width: values.count, height: 1)
        fill(input, values.map { SIMD4($0, 0, 0, 0) })
        let output = rgbaPlane(metal, width: values.count, height: 1)
        let q = uniformBytes(QuantizeUniforms(sampling: 1, clipMin: Float(exp2(-14.0)), clipMax: 4))
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.quantizeFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(q, length: q.count, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: values.count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 1, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        drain(metal)
        let got = readRGBA(output)
        // floor(log2(v)) in EV: 0.3 → 0.25, 0.6 → 0.5, 1.7 → 1, 0.001 → 2^-10
        XCTAssertEqual(Double(got[0].x), 0.25, accuracy: 1e-6)
        XCTAssertEqual(Double(got[1].x), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(got[2].x), 1.0, accuracy: 1e-6)
        XCTAssertEqual(Double(got[3].x), Double(exp2(-10.0)), accuracy: 1e-6)
    }
}
