import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// MetalContext + pass-through kernel tests (FOUND-06, D-16/D-17) — real
/// GPU dispatches through the `public` surface. Every test guards on GPU
/// availability (VALIDATION: Metal compute requires a GPU context) and
/// registers LightamerIOP's `default.metallib` before dispatching
/// (RESEARCH §1 gotcha #1: the IOP metallib lives in the FRAMEWORK bundle).
final class MetalContextTests: XCTestCase {

    /// Fresh context with the IOP metallib registered (helper).
    private func makeContext() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    /// Identity function-constants (`useSrgbGamma=false, exposureEV=0`) —
    /// BOTH constants must be set (the kernel declares no MSL defaults,
    /// RESEARCH §3 gotcha). Fresh instance per call so callers control the
    /// PSO-cache fingerprint (instance identity, D-17).
    private func identityConstants(metal: MetalContext) -> MTLFunctionConstantValues {
        let constants = metal.makeConstants(false, at: 0, type: .bool)
        metal.setConstant(Float(0.0), at: 1, type: .float, into: constants)
        return constants
    }

    /// FOUND-06: device + command queue are created (D-14/D-15).
    func testMetalContextInit() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        XCTAssertNotNil(metal.device)
        XCTAssertNotNil(metal.commandQueue)
    }

    /// FOUND-06: dispatch `pass_through` with identity constants through the
    /// texture dispatch path (`dispatch2DTexture`) and assert output ==
    /// input bit-for-bit (float32 RGBA, including the alpha channel).
    func testPassThroughKernelBitExact() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeContext()
        let constants = identityConstants(metal: metal)

        let width = 8, height = 4
        // Known pattern incl. 0.0/1.0 endpoints, sub-0.5 values, alpha < 1.
        var input = [Float](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            input[pixel * 4 + 0] = Float(pixel) / Float(width * height)
            input[pixel * 4 + 1] = 0.5
            input[pixel * 4 + 2] = pixel % 2 == 0 ? 1.0 : 0.25
            input[pixel * 4 + 3] = 1.0 - Float(pixel % 3) / 4.0
        }

        func makeTexture(usage: MTLTextureUsage) -> any MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: WorkingSpace.pixelFormat, width: width, height: height,
                mipmapped: false
            )
            d.usage = usage
            d.storageMode = .shared
            return metal.device.makeTexture(descriptor: d)!
        }
        let inTex = makeTexture(usage: [.shaderRead])
        let outTex = makeTexture(usage: [.shaderWrite])
        inTex.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: input, bytesPerRow: width * WorkingSpace.bytesPerPixel
        )

        try await metal.dispatch2DTexture(
            functionName: PassthroughKernel.functionName,
            input: inTex, output: outTex,
            constants: constants
        )
        // Drain: a command buffer committed after the kernel completes only
        // when the kernel has (same-queue FIFO, the PassthroughModule trick).
        let drain = try XCTUnwrap(metal.commandQueue.makeCommandBuffer())
        drain.commit()
        await drain.completed()

        var output = [Float](repeating: -1, count: input.count)
        outTex.getBytes(
            &output, bytesPerRow: width * WorkingSpace.bytesPerPixel,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0
        )

        // Bit-exact: the identity specialization is a true no-op.
        XCTAssertEqual(
            input.map { $0.bitPattern }, output.map { $0.bitPattern },
            "identity pass_through must preserve every bit (float32 RGBA)"
        )
    }

    /// D-16: the second `makeEncoder` for the same (function, constants
    /// INSTANCE) pair reuses the cached PSO — the returned
    /// `MTLComputePipelineState` is the SAME object instance, which is the
    /// only public-surface observable of a cache hit (the cache itself is
    /// internal per RESEARCH §9). Each probe session is closed immediately
    /// (`endEncoding` + `commit` — the documented caller contract): dropping
    /// a session with a live encoder trips Metal's
    /// `Command encoder released without endEncoding` fatal assertion.
    func testPSOCacheHit() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeContext()
        let constants = identityConstants(metal: metal) // ONE instance → one fingerprint

        let first = try await metal.makeEncoder(
            functionName: PassthroughKernel.functionName, constants: constants
        )
        first.encoder.endEncoding()
        first.commandBuffer.commit()

        let second = try await metal.makeEncoder(
            functionName: PassthroughKernel.functionName, constants: constants
        )
        second.encoder.endEncoding()
        second.commandBuffer.commit()

        XCTAssertTrue(
            ObjectIdentifier(first.pipelineState as AnyObject)
                == ObjectIdentifier(second.pipelineState as AnyObject),
            "same (function, constants) must hit the PSO cache and return the same instance"
        )
    }

    /// D-17: two distinct constant combinations (`useSrgbGamma=true` vs
    /// `false`) yield DISTINCT PSO instances (separate cache entries per
    /// `(name, constants)` fingerprint), while each combination stays
    /// stable across repeated lookups. Probe sessions are closed in place
    /// (the `makeEncoder` caller contract — see `testPSOCacheHit`).
    func testFunctionConstantsSpecialization() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeContext()

        let gammaOn = metal.makeConstants(true, at: 0, type: .bool)
        metal.setConstant(Float(0.0), at: 1, type: .float, into: gammaOn)
        let gammaOff = metal.makeConstants(false, at: 0, type: .bool)
        metal.setConstant(Float(0.0), at: 1, type: .float, into: gammaOff)

        let srgb = try await metal.makeEncoder(
            functionName: PassthroughKernel.functionName, constants: gammaOn
        )
        srgb.encoder.endEncoding()
        srgb.commandBuffer.commit()
        let linear = try await metal.makeEncoder(
            functionName: PassthroughKernel.functionName, constants: gammaOff
        )
        linear.encoder.endEncoding()
        linear.commandBuffer.commit()
        let srgbAgain = try await metal.makeEncoder(
            functionName: PassthroughKernel.functionName, constants: gammaOn
        )
        srgbAgain.encoder.endEncoding()
        srgbAgain.commandBuffer.commit()

        XCTAssertNotEqual(
            ObjectIdentifier(srgb.pipelineState as AnyObject),
            ObjectIdentifier(linear.pipelineState as AnyObject),
            "distinct specializations must build distinct PSOs"
        )
        XCTAssertEqual(
            ObjectIdentifier(srgb.pipelineState as AnyObject),
            ObjectIdentifier(srgbAgain.pipelineState as AnyObject),
            "repeated lookups of one specialization stay cached"
        )
    }
}
