@testable import LightamerCore
import CoreGraphics
import Metal
@testable import LightamerIOP
import XCTest

// ToneEqualModuleTests (Plan 03-05-T4) — the assembled three-stage chain:
//
//   1. Apply-kernel identity: a LUT of exact 1.0s reproduces the input
//      BYTE-IDENTICAL through the apply stage (the plan's "恒等参数端到端"
//      gate — the correction path adds no transformation of its own; the
//      all-zero-bands PARAMS are only a ~1.8e-2-ripple approximation of
//      identity, CorrectionLUT header note, so identity is pinned via the
//      exact-1 LUT directly).
//   2. Chain-vs-CPU parity: details=none on the −8..0 EV ramp against a
//      direct Float evaluation of the same formulas (luma NORM_2 →
//      linear_contrast → LUT apply), < 1e-5 relative.
//   3. EV-band gain DIRECTION: shadows +1 EV lifts the −4 EV region,
//      leaves the −8 EV floor near-untouched.
//   4. Registration at v50 slot 24.0.
final class ToneEqualModuleTests: XCTestCase {

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

    private func rgbaTexture(_ metal: MetalContext, _ pixels: [SIMD4<Float>], width: Int, height: Int)
        -> any MTLTexture {
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

    private func readRGBA(_ tex: any MTLTexture) -> [SIMD4<Float>] {
        var data = [SIMD4<Float>](repeating: .zero, count: tex.width * tex.height)
        data.withUnsafeMutableBytes {
            tex.getBytes(
                $0.baseAddress!, bytesPerRow: tex.width * 16,
                from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        return data
    }

    /// The −8..0 EV gray ramp as an RGBA float plane (ramp_8ev semantics:
    /// v(x) = 2^(−8 + x/8)).
    private func rampPixels(width: Int, height: Int) -> [SIMD4<Float>] {
        var pixels = [SIMD4<Float>](repeating: .zero, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = Float(exp2(-8.0 + Double(x) / 8.0))
                pixels[y * width + x] = SIMD4(v, v, v, 1)
            }
        }
        return pixels
    }

    /// The shared CPU reference for details=none (luminance_mask.h +
    /// toneequal.c:771-803, Float — the same formula path the kernels
    /// transcribe).
    private func referenceNone(pixels: [SIMD4<Float>], params: ToneEqualModule.Params, lut: [Float])
        -> [SIMD4<Float>] {
        let boost = exp2(params.exposureBoost)
        let floorValue = Float(exp2(-16.0))
        return pixels.map { p in
            // NORM_2 luminance + the unboosted linear_contrast (fulcrum 0,
            // contrast 1) + the LUT apply.
            let norm2 = (p.x * p.x + p.y * p.y + p.z * p.z).squareRoot()
            let l = boost * norm2
            let contrasted = max(l, floorValue)
            let exposure = min(max(log2(contrasted), CorrectionLUT.minEV), CorrectionLUT.maxEV)
            let idx = min(
                Int(((exposure - CorrectionLUT.minEV) * Float(CorrectionLUT.lutResolution)).rounded()),
                CorrectionLUT.lutCount - 1)
            let c = lut[idx]
            return SIMD4(p.x * c, p.y * c, p.z * c, p.w * c)
        }
    }

    private func runPipe(
        _ pixels: [SIMD4<Float>], width: Int, height: Int,
        params: ToneEqualModule.Params, metal: MetalContext
    ) async throws -> [SIMD4<Float>] {
        var data = Data(capacity: pixels.count * 16)
        for p in pixels {
            for v in [p.x, p.y, p.z, p.w] {
                var le = v.bitPattern.littleEndian
                data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let image = DecodedImage(
            ciImage: CIImage(cgImage: cg), rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil, decoderVersionUsed: .v8)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let maybeBox = await registry.makeBox(opName: ToneEqualModule.opName)
        let box = try XCTUnwrap(maybeBox as? ModuleBox<ToneEqualModule>)
        box.setParams(params)
        // colorin rides along (identity on the Rec2020 working domain) —
        // the SigmoidTests pipe shape.
        let maybeColorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(maybeColorin)
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [colorinBox, box], imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        drain(metal)
        return readRGBA(texture)
    }

    // MARK: 1. Apply-stage identity (exact-1 LUT, byte-identical)

    func testApplyIdentityWithUnitLUT() async throws {
        let metal = try await makeMetal()
        let width = 16
        let height = 4
        let input = rgbaTexture(metal, rampPixels(width: width, height: height), width: width, height: height)
        let luma = rgbaTexture(
            metal, [SIMD4<Float>](repeating: SIMD4(0.25, 0, 0, 0), count: width * height),
            width: width, height: height)
        let output = rgbaTexture(metal, [SIMD4<Float>](repeating: .zero, count: width * height),
                                 width: width, height: height)
        var ones = [Float](repeating: 1.0, count: CorrectionLUT.lutCount)
        let lut = metal.device.makeBuffer(
            bytes: &ones, length: CorrectionLUT.lutCount * 4, options: .storageModeShared)!
        let session = try await metal.makeEncoder(functionName: ToneEqualKernel.applyFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(luma, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBuffer(lut, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        drain(metal)

        // BYTE-identical: bit patterns equal on every channel.
        let got = readRGBA(output)
        let want = rampPixels(width: width, height: height)
        for i in 0..<got.count {
            XCTAssertEqual(got[i].x.bitPattern, want[i].x.bitPattern, "px \(i) r")
            XCTAssertEqual(got[i].y.bitPattern, want[i].y.bitPattern, "px \(i) g")
            XCTAssertEqual(got[i].z.bitPattern, want[i].z.bitPattern, "px \(i) b")
            XCTAssertEqual(got[i].w.bitPattern, want[i].w.bitPattern, "px \(i) a")
        }
    }

    // MARK: 2. details=none chain vs CPU reference (ramp, <1e-5)

    func testNoneChainMatchesCPUReference() async throws {
        let metal = try await makeMetal()
        let width = 64
        let height = 4
        let pixels = rampPixels(width: width, height: height)
        var params = ToneEqualModule.Params(details: .none)
        params.shadows = 1.0
        params.highlights = -0.5
        let lut = CorrectionLUT.lut(
            weights: CorrectionLUT.weights(bands: params.bands, sigma: params.smoothing)!,
            sigma: params.smoothing)

        let got = try await runPipe(pixels, width: width, height: height, params: params, metal: metal)
        let want = referenceNone(pixels: pixels, params: params, lut: lut)
        var maxRel: Float = 0
        for i in 0..<got.count {
            for c in 0..<3 {
                let g = got[i][c], w = want[i][c]
                let rel = abs(g - w) / max(abs(w), 1e-9)
                maxRel = max(maxRel, rel)
            }
        }
        XCTAssertLessThan(maxRel, 1e-5, "details=none chain vs CPU reference")
    }

    // MARK: 3. EV-band gain direction (the plan's ramp gate)

    func testShadowBandLiftsMidTones() async throws {
        let metal = try await makeMetal()
        let width = 64
        let height = 2
        let pixels = rampPixels(width: width, height: height)
        var params = ToneEqualModule.Params(details: .none)
        params.shadows = 1.0 // the −4 EV band

        let got = try await runPipe(pixels, width: width, height: height, params: params, metal: metal)
        // −4 EV lives at x = 32 (v = 2^(−8 + 32/8) = 2^−4). NOTE the luma
        // is NORM_2 (v·√3 → −3.83 EV, slightly off the band center) and
        // the least-squares fit smooths the +1EV impulse to a ~1.4 gain
        // there (CorrectionLUTTests pins the same envelope on the LUT).
        let lift = got[32].x / pixels[32].x
        XCTAssertGreaterThan(Double(lift), 1.3, "shadows +1 EV must lift −4 EV")
        // The −8 EV floor (x = 0): NORM_2 luma → −6.79 EV, two bands away —
        // the RBF tail + ripple move it less than half the lift.
        let floorRatio = got[0].x / pixels[0].x
        XCTAssertLessThan(Double(floorRatio), 1.2, "−8 EV floor stays near-untouched")
        XCTAssertLessThan(Double(floorRatio), Double(lift), "gain is band-shaped")
    }

    // MARK: 4. Registration

    func testToneEqualRegisteredAtV50Slot24() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let maybeBox = await registry.makeBox(opName: ToneEqualModule.opName)
        _ = try XCTUnwrap(maybeBox as? ModuleBox<ToneEqualModule>)
        XCTAssertEqual(ToneEqualModule.opName, "toneequal")
        XCTAssertEqual(ToneEqualModule.iopOrder, 24.0)
        XCTAssertEqual(ToneEqualModule.defaultColorspace, .RGB)
        let id = UUID()
        let restored = await registry.makeBox(opName: ToneEqualModule.opName, instanceID: id)
        XCTAssertEqual(try XCTUnwrap(restored).instanceID, id, "identity-restoring init wired")
    }
}
