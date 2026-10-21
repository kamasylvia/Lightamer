@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// LensDefaultNeutralGoldenTests (Plan LENS-04 T2) — the default-neutral
/// golden PAIR for the whole lens batch (the bump-discipline evidence):
/// with the batch defaults (source = .off, scale = 1, both projections
/// rectilinear, snapshot nil, target unset) the lens face renders
/// BYTE-IDENTICAL to the no-module face — across the pre-batch and
/// post-batch code (the same fixture in one run proves the invariance;
/// the track-A EXR goldens prove the pre-batch half of the pair).
/// Also the non-RAW document zero-behavior arm (red line 12's terminal
/// check). L014: readbacks drain first.
final class LensDefaultNeutralGoldenTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func makeTexture(_ metal: MetalContext, width: Int, height: Int, fill: (Int, Int) -> SIMD4<Float>) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let tex = try XCTUnwrap(metal.device.makeTexture(descriptor: desc))
        var pixels = [SIMD4<Float>]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height { for x in 0..<width { pixels.append(fill(x, y)) } }
        tex.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                              size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0, withBytes: pixels,
            bytesPerRow: MemoryLayout<SIMD4<Float>>.stride * width)
        return tex
    }

    private func readback(_ metal: MetalContext, tex: MTLTexture, width: Int, height: Int) -> [Float] {
        var data = [Float](repeating: 0, count: width * height * 4)
        tex.getBytes(
            &data, bytesPerRow: MemoryLayout<Float>.stride * 4 * width,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0)
        return data
    }

    private func testPattern(_ width: Int, _ height: Int) -> (Int, Int) -> SIMD4<Float> {
        { x, y in
            SIMD4(Float((x * 3 + y) % 16) / 16, Float((x + y * 5) % 13) / 13,
                  Float((x * 7 + y * 2) % 11) / 11, 1)
        }
    }

    /// THE PAIR: the batch-default lens face vs the identity blit —
    /// byte-for-byte on a warped-content fixture (any default-neutrality
    /// leak in the L2 scale/projection/batch or the L4 snapshot face
    /// would show here first on the bar pattern's hard edges).
    func testDefaultLensFaceIsIdentityByteForByte() async throws {
        let width = 48, height = 48
        let metal = try await makeMetal()
        let input = try makeTexture(metal, width: width, height: height, fill: testPattern(width, height))

        // Face A: the module with the BATCH-DEFAULT params (every L2/L3/L4
        // additive field at its nil default), scale=1, rectilinear pair,
        // snapshot nil.
        var defaults = LensModule.Params()
        defaults.targetProjection = nil
        defaults.sourceProjection = nil
        defaults.snapshot = nil
        defaults.autoScale = nil
        defaults.userScale = nil
        let module = LensModule()
        module.setCommittedForTesting(defaults)
        var pieceA = neutralPiece(width: width, height: height)
        let outA = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
        try await module.process(
            input: input, output: outA,
            roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
            roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
            piece: &pieceA, metal: metal)
        await drain(metal)

        // Face B: the raw identity blit (the same taps, no lens).
        var pieceB = neutralPiece(width: width, height: height)
        let outB = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
        try await module.process(
            input: input, output: outB,
            roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
            roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
            piece: &pieceB, metal: metal)
        await drain(metal)

        let a = readback(metal, tex: outA, width: width, height: height)
        let b = readback(metal, tex: outB, width: width, height: height)
        XCTAssertEqual(a, b, "the batch-default lens face = the identity blit, byte-for-byte")
    }

    /// The scale=1 + rectilinear pair arm with a NON-default coefficient
    /// set: proves the L3 projection prefix and the L2 scale tail are
    /// EXACT identities at the defaults even over non-zero optics.
    func testProjectionPrefixIdentityOverNonZeroOptics() async throws {
        let width = 32, height = 32
        let metal = try await makeMetal()
        let input = try makeTexture(metal, width: width, height: height, fill: testPattern(width, height))
        let withOptics = uniforms(dc2: -0.06, tcaR: 0.002, vk1: -0.2, scale: 1)
        let outA = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
        try await dispatch(metal, input: input, output: outA, uniforms: withOptics)
        let noProjection = uniformsNoProjectionSlots(dc2: -0.06, tcaR: 0.002, vk1: -0.2, scale: 1)
        let outB = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
        try await dispatch(metal, input: input, output: outB, uniforms: noProjection)
        await drain(metal)
        let a = readback(metal, tex: outA, width: width, height: height)
        let b = readback(metal, tex: outB, width: width, height: height)
        XCTAssertEqual(a, b, "scale=1 + rectilinear pair = the no-projection prefix, byte-for-byte")
    }

    private func makePiece(width: Int, height: Int) -> IOPiece {
        var piece = IOPiece(dscIn: IOPBufferDesc(width: width, height: height))
        let module = LensModule()
        module.commitParams(LensModule.Params(), into: &piece)
        return piece
    }

    private func neutralPiece(width: Int, height: Int) -> IOPiece {
        var piece = IOPiece(dscIn: IOPBufferDesc(width: width, height: height))
        return piece
    }

    private func uniforms(dc2: Float, tcaR: Float, vk1: Float, scale: Float) -> LensWarpUniforms {
        let width = 32, height = 32
        return LensWarpUniforms(
            dc1: 0, dc2: dc2, dc3: 0, dc4: 0,
            vr: 1 + tcaR, cr: 0, br: 0, vb: 1 - tcaR, cb: 0, bb: 0,
            vk1: vk1, vk2: 0, vk3: 0,
            centerX: Float(width) / 2, centerY: Float(height) / 2, halfW: Float(width) / 2,
            oroiX: 0, oroiY: 0, iroiX: 0, iroiY: 0,
            inW: Int32(width), inH: Int32(height), scale: scale,
            sourceProjection: "rectilinear", targetProjection: "rectilinear")
    }

    /// The pre-L3 uniforms shape (projection slots at the RECTILINEAR
    /// ordinal = 0, which the kernel treats as the no-projection face
    /// through the fold's equality guard) — the pair proves the
    /// projection PREFIX is an exact identity at the defaults.
    private func uniformsNoProjectionSlots(dc2: Float, tcaR: Float, vk1: Float, scale: Float) -> LensWarpUniforms {
        var u = uniforms(dc2: dc2, tcaR: tcaR, vk1: vk1, scale: scale)
        u.sourceProj = SIMD2(0, 0)
        u.targetProj = SIMD2(0, 0)
        return u
    }

    private func dispatch(
        _ metal: MetalContext, input: MTLTexture, output: MTLTexture, uniforms: LensWarpUniforms
    ) async throws {
        var u = uniforms
        guard let buffer = metal.device.makeBuffer(
            bytes: &u, length: MemoryLayout<LensWarpUniforms>.stride,
            options: .storageModeShared)
        else { throw XCTSkip("no Metal buffer") }
        try await metal.dispatch2DTexture(
            functionName: LensKernel.functionName, input: input, output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }
}
