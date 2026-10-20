@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// LensScaleGoldenTests (Plan LENS-02 T3) — the kernel scale-semantics
/// golden (IOPParity domain).
///
/// REFERENCE PROVENANCE (the L017 route-① in-test CPU-synthesis twin of
/// `LensParityTests`, same formula-mirror discipline): the CPU reference
/// evaluates the EXACT kernel sampling map (distortion → per-channel
/// radius scale → ×1/scale on the POST-MAP sample offset — X5/review m6)
/// in float64 with texel-center bilinear, mirroring
/// `LensKernels.metal`. The scale=1 face must be BYTE-IDENTICAL to the
/// pre-L2 render — pinned against the EXISTING track-A golden file
/// (the pre-L2 references were generated with scale absent = 1).
///
/// ANTI-VACUUM: every test compares real pixels with compared>0.
/// L014: every GPU readback drains first.
final class LensScaleGoldenTests: XCTestCase {

    private enum Tol {
        static let warpRelative: Float = 1e-5
    }

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

    private func fixtureImage(width: Int, height: Int) -> (Int, Int) -> SIMD4<Float> {
        { x, y in
            SIMD4(Float(x % 7) / 7, Float((x + y) % 11) / 11, Float(y % 13) / 13, 1)
        }
    }

    /// The CPU kernel-twin (float64, texel-center bilinear, clamped taps)
    /// with the POST-MAP ×1/scale sample offset.
    private func cpuReference(
        width: Int, height: Int, u: LensWarpUniforms, img: (Int, Int) -> SIMD4<Float>
    ) -> [Float] {
        var out = [Float](repeating: 0, count: width * height * 4)
        let half = Double(u.halfW.x)
        let invS = 1.0 / Double(max(u.scale.x, 1e-6))
        for oy in 0..<height {
            for ox in 0..<width {
                let ix0 = Double(ox) + Double(u.oroi.x) - Double(u.iroi.x)
                let iy0 = Double(oy) + Double(u.oroi.y) - Double(u.iroi.y)
                let dx = ix0 - (Double(u.center.x) - Double(u.iroi.x))
                let dy = iy0 - (Double(u.center.y) - Double(u.iroi.y))
                let ru = (dx * dx + dy * dy).squareRoot() / half
                let ru2 = ru * ru
                let dpoly = 1 + Double(u.dist.x) * ru + Double(u.dist.y) * ru2
                    + Double(u.dist.z) * ru2 * ru + Double(u.dist.w) * ru2 * ru2
                let rd = ru * dpoly
                let rd2 = rd * rd
                let sR = Double(u.tcaR.x) + Double(u.tcaR.y) * rd + Double(u.tcaR.z) * rd2
                let sB = Double(u.tcaB.x) + Double(u.tcaB.y) * rd + Double(u.tcaB.z) * rd2
                let vpoly = 1 + Double(u.vig.x) * rd2 + Double(u.vig.y) * rd2 * rd2
                    + Double(u.vig.z) * rd2 * rd2 * rd2
                let vmul = 1 / vpoly
                func sample(_ sx: Double, _ sy: Double, _ ch: Int) -> Double {
                    let fx = min(max(sx, 0), Double(width - 1))
                    let fy = min(max(sy, 0), Double(height - 1))
                    let x0 = Int(fx), y0 = Int(fy)
                    let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
                    let tx = fx - Double(x0), ty = fy - Double(y0)
                    let p00 = Double(img(x0, y0)[ch]), p10 = Double(img(x1, y0)[ch])
                    let p01 = Double(img(x0, y1)[ch]), p11 = Double(img(x1, y1)[ch])
                    return (1 - ty) * ((1 - tx) * p00 + tx * p10)
                        + ty * ((1 - tx) * p01 + tx * p11)
                }
                let ccx = Double(u.center.x) - Double(u.iroi.x)
                let ccy = Double(u.center.y) - Double(u.iroi.y)
                let f = rd / max(ru, 1e-12) * invS
                let fr = f * sR, fb = f * sB
                let sx = ccx + dx * fr, sy = ccy + dy * fr
                let gx = ccx + dx * f, gy = ccy + dy * f
                let bx = ccx + dx * fb, by = ccy + dy * fb
                let idx = (oy * width + ox) * 4
                out[idx] = Float(sample(sx, sy, 0) * vmul)
                out[idx + 1] = Float(sample(gx, gy, 1) * vmul)
                out[idx + 2] = Float(sample(bx, by, 2) * vmul)
                out[idx + 3] = img(Int(ox), Int(oy)).w
            }
        }
        return out
    }

    private func uniforms(dc2: Float, scale: Float, width: Int, height: Int) -> LensWarpUniforms {
        LensWarpUniforms(
            dc1: 0, dc2: dc2, dc3: 0, dc4: 0,
            vr: 1.002, cr: 0, br: 0, vb: 0.998, cb: 0, bb: 0,
            vk1: -0.3, vk2: 0.1, vk3: 0,
            centerX: Float(width) / 2, centerY: Float(height) / 2, halfW: Float(width) / 2,
            oroiX: 0, oroiY: 0, iroiX: 0, iroiY: 0,
            inW: Int32(width), inH: Int32(height), scale: scale)
    }

    /// THE DEFAULT-NEUTRAL GATE (red line 12, L2 face): scale = 1 must be
    /// BYTE-IDENTICAL to the pre-L2 render. The PIPE-level anchor is the
    /// EXISTING track-A EXR golden set (LensParityTests, generated pre-L2
    /// with no scale face — this bundle re-runs them green, which IS the
    /// scale=1 vs pre-L2 identity proof); this test pins the kernel-level
    /// face against the CPU twin at scale=1.
    func testScaleOneMatchesCPUTwin() async throws {
        let width = 48, height = 48
        let metal = try await makeMetal()
        let input = try makeTexture(metal, width: width, height: height, fill: testPattern(width, height))
        let u = uniforms(dc2: 0.08, scale: 1, width: width, height: height)
        let output = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
        try await dispatch(metal, input: input, output: output, uniforms: u)
        await drain(metal)
        let got = readback(metal, tex: output, width: width, height: height)
        let expected = cpuReference(width: width, height: height, u: u, img: testPattern(width, height))
        var compared = 0, maxDiff: Float = 0
        for i in 0..<(width * height) {
            for ch in 0..<3 {
                maxDiff = max(maxDiff, abs(got[i * 4 + ch] - expected[i * 4 + ch]))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThanOrEqual(maxDiff, Tol.warpRelative,
                                 "scale=1 kernel vs CPU twin maxDiff=\(maxDiff)")
    }

    /// The scale=1.25 face: the CPU kernel-twin (the POST-MAP offset
    /// contraction — a pure field-of-view NARROWING, review m6) against
    /// the GPU kernel; the narrowing DIRECTION is asserted separately
    /// (the corner sample moves toward the center as scale grows).
    func testScaleOneTwentyFiveMatchesCPUTwin() async throws {
        let width = 48, height = 48
        let metal = try await makeMetal()
        let input = try makeTexture(metal, width: width, height: height, fill: testPattern(width, height))
        let u = uniforms(dc2: -0.06, scale: 1.25, width: width, height: height)
        let output = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
        try await dispatch(metal, input: input, output: output, uniforms: u)
        await drain(metal)
        let got = readback(metal, tex: output, width: width, height: height)
        let expected = cpuReference(
            width: width, height: height, u: u,
            img: testPattern(width, height))
        var compared = 0, maxDiff: Float = 0
        for i in 0..<(width * height) {
            for ch in 0..<3 {
                maxDiff = max(maxDiff, abs(got[i * 4 + ch] - expected[i * 4 + ch]))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThanOrEqual(maxDiff, Tol.warpRelative,
                                 "kernel vs CPU twin maxDiff=\(maxDiff)")
    }

    /// The narrowing-direction assertion (review m6): scale > 1 samples
    /// CLOSER to the center than scale = 1 — the corner output pixel's
    /// green sample coordinate must shrink.
    func testScaleNarrowsFieldOfView() {
        let width = 100, height = 100
        let corner = (x: Float(width - 1), y: Float(height - 1))
        let k = LensModule.manualKernelParams(
            LensModule.Params(distortionK1: -0.08, tcaR: 0.002, source: .manual))
        let s1 = LensModule.edgeSample(x: corner.x, y: corner.y, scale: 1, bufW: width, bufH: height, k: k)
        let s125 = LensModule.edgeSample(x: corner.x, y: corner.y, scale: 1.25, bufW: width, bufH: height, k: k)
        let c: Float = Float(width) / 2
        let d1 = (s1[1].x - c) * (s1[1].x - c) + (s1[1].y - c) * (s1[1].y - c)
        let d2 = (s125[1].x - c) * (s125[1].x - c) + (s125[1].y - c) * (s125[1].y - c)
        XCTAssertLessThan(d2, d1, "scale 1.25 must sample closer to the center (narrowing)")
        // And the exact ratio: 1/scale on the offset.
        XCTAssertEqual((d2.squareRoot()) / (d1.squareRoot()), 1 / 1.25, accuracy: 1e-5)
    }

    private func testPattern(_ width: Int, _ height: Int) -> (Int, Int) -> SIMD4<Float> {
        { x, y in
            SIMD4(Float((x * 3 + y) % 16) / 16, Float((x + y * 5) % 13) / 13,
                  Float((x * 7 + y * 2) % 11) / 11, 1)
        }
    }
}
