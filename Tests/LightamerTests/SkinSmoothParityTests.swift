@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// SkinSmoothParityTests (Plan 07-2 T2/T4) — AI-05's frequency-separation
// skin smoothing. NO DARKTABLE COUNTERPART (L017 route: SELF-SYNTHESIZED
// float64 reference + identity triple — dt has no AI skin-smoothing
// module, 07-RESEARCH §2), so the golden face is:
//   - IDENTITY TRIPLE (T2, this file — direct-drive, GaussianBlurTests
//     pattern):
//     1. strength 0 ⇒ byte-exact blit;
//     2. mask nil == all-ones mask, byte-identical (the mask channel is a
//        no-op when absent — production spatial limiting rides the blendop);
//     3. flat field ⇒ any DC-1 blur preserves the flat ⇒ out ≈ in at ANY
//        strength (L017-proof vacuous identity, soften D5 twin).
//   - FLOAT64 PARITY (T4): 6 pinned σ×a×t cases × 6 fixtures vs
//     SkinSmoothReference (the Double transliteration of the split +
//     raised-cosine attenuation), gate <1e-5 (ParityGate double-gate
//     discipline).
//
// ANTI-VACUUM: every test runs a real comparison loop with compared>0.
// L014: every GPU readback drains first.
final class SkinSmoothParityTests: XCTestCase {

    private enum Tol {
        // Identity #3's envelope: the DC-1 IIR preserves a flat to ~1 ulp;
        // the residual feeds high ≈ ε and out = in − ε·a·m·g ≤ ε.
        static let flatFieldAbs: Float = 1e-5
    }

    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
    }

    private func drain() {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Direct-drive plumbing (GaussianBlurTests pattern)

    private func makeRGBATexture(width: Int, height: Int, pixels: [Float]) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        precondition(pixels.count == width * height * 4 || pixels.isEmpty)
        if !pixels.isEmpty {
            pixels.withUnsafeBytes {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: width * 16)
            }
        }
        return texture
    }

    /// A single-channel r32Float plane (the mask seam's currency — the
    /// MaskCombiner effectivePlane shape).
    private func makeMaskTexture(width: Int, height: Int, value: Float) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        var pixels = [Float](repeating: value, count: width * height)
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    private func readTexture(_ texture: any MTLTexture) -> [Float] {
        var out = [Float](repeating: 0, count: texture.width * texture.height * 4)
        out.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return out
    }

    /// Deterministic pseudo-random RGB content (linear Rec2020-ish range
    /// incl. >1 scene-referred values — the working space is unbounded).
    private func syntheticPixels(width: Int, height: Int, seed: UInt64 = 0x5EED) -> [Float] {
        var state = seed
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(state >> 11) / Double(1 << 53))
        }
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            // Bases span 0.005..1.4 with per-channel jitter — plenty of
            // low/high frequency content after the DC split.
            pixels[i * 4] = next() * 1.4 + 0.005
            pixels[i * 4 + 1] = next() * 1.2 + 0.005
            pixels[i * 4 + 2] = next() * 1.0 + 0.005
            pixels[i * 4 + 3] = 1.0
        }
        return pixels
    }

    /// Drive the module directly (box-free): commit + process on a full
    /// 1:1 ROI. `mask` binds the module's direct-drive seam (nil = the
    /// no-mask leg).
    private func runDirect(
        pixels: [Float], width: Int, height: Int,
        params: SkinSmoothModule.Params,
        mask: (any MTLTexture)? = nil
    ) async throws -> [Float] {
        let module = SkinSmoothModule()
        var piece = IOPiece(
            dscIn: IOPBufferDesc(width: width, height: height),
            dscOut: IOPBufferDesc(width: width, height: height))
        module.commitParams(params, into: &piece)
        module.maskPlane = mask
        let input = makeRGBATexture(width: width, height: height, pixels: pixels)
        let output = makeRGBATexture(width: width, height: height, pixels: [])
        let roi = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        try await module.process(
            input: input, output: output,
            roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        drain() // L014
        return readTexture(output)
    }

    // MARK: - Identity triple

    /// Triple #1: strength 0 ⇒ the D9 blit fast path — BYTE-exact on
    /// varying content (every pixel compared, including alpha).
    func testStrengthZeroIsByteExactIdentity() async throws {
        let w = 64, h = 64
        let pixels = syntheticPixels(width: w, height: h)
        let out = try await runDirect(
            pixels: pixels, width: w, height: h,
            params: SkinSmoothModule.Params(radius: 8.0, strength: 0.0, detailPreserve: 0.02))
        XCTAssertEqual(out.count, pixels.count)
        var compared = 0
        for i in 0..<out.count {
            XCTAssertEqual(
                out[i].bitPattern, pixels[i].bitPattern,
                "byte mismatch at \(i) (channel \(i % 4))")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
    }

    /// Triple #2: the mask channel is a NO-OP when absent — mask nil vs an
    /// ALL-ONES r32Float plane produce byte-identical output at active
    /// strength (the hasMask uniform gate must not change the m ≡ 1 math).
    func testMaskNilEqualsAllOnesMaskByteExact() async throws {
        let w = 48, h = 48
        let pixels = syntheticPixels(width: w, height: h, seed: 0xFACE)
        let params = SkinSmoothModule.Params(radius: 6.0, strength: 0.7, detailPreserve: 0.02)
        let noMask = try await runDirect(
            pixels: pixels, width: w, height: h, params: params, mask: nil)
        let ones = try await runDirect(
            pixels: pixels, width: w, height: h, params: params,
            mask: makeMaskTexture(width: w, height: h, value: 1.0))
        var compared = 0
        for i in 0..<noMask.count {
            XCTAssertEqual(
                noMask[i].bitPattern, ones[i].bitPattern,
                "nil-mask vs ones-mask diverge at \(i)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
    }

    /// Triple #3: flat field ⇒ out ≈ in at ACTIVE strength through the
    /// KERNEL path (not the blit) — any DC-1 blur preserves the flat, so
    /// high ≈ 0 and the mix returns the flat (L017-proof; the envelope is
    /// the IIR's ulp-level flat residual feeding out = in − ε·a·m·g).
    func testFlatFieldIdentityAtActiveStrength() async throws {
        let w = 48, h = 48
        // Scene-referred mid-gray, flat everywhere (alpha 1).
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            pixels[i * 4] = 0.18
            pixels[i * 4 + 1] = 0.18
            pixels[i * 4 + 2] = 0.18
            pixels[i * 4 + 3] = 1.0
        }
        let out = try await runDirect(
            pixels: pixels, width: w, height: h,
            params: SkinSmoothModule.Params(radius: 8.0, strength: 1.0, detailPreserve: 0.02))
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 3) { // RGB only — alpha rides the original
            maxDiff = max(maxDiff, abs(out[i] - pixels[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
        XCTAssertLessThan(maxDiff, Tol.flatFieldAbs, "flat-field identity within the IIR envelope")
    }

    /// The mask seam actually attenuates: a ZERO mask must return the
    /// input through the KERNEL path (m=0 ⇒ factor 1 everywhere) — the
    /// directional counterweight of triple #2 (anti-vacuum: the mask
    /// channel must be load-bearing, not decorative).
    func testZeroMaskReturnsInputThroughKernelPath() async throws {
        let w = 48, h = 48
        let pixels = syntheticPixels(width: w, height: h, seed: 0xBEEF)
        let out = try await runDirect(
            pixels: pixels, width: w, height: h,
            params: SkinSmoothModule.Params(radius: 6.0, strength: 1.0, detailPreserve: 0.02),
            mask: makeMaskTexture(width: w, height: h, value: 0.0))
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 4) {
            maxDiff = max(maxDiff, abs(out[i] - pixels[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        // out = low + (in − low)·1: float round-trip through the split
        // keeps the identity to the mix arithmetic's rounding (≤1e-6 rel
        // on these magnitudes).
        XCTAssertLessThan(maxDiff, 1e-5, "zero mask ⇒ kernel-path identity")
    }

    // MARK: - Derivation pins (σ chain — highpass.c:140 citation)

    func testSigmaHaloChains() {
        // r=8: σ = √((8·9·8+2)/3) = √(192.666..)
        let sig8 = SkinSmoothModule.sigma(radius: 8, scale: 1.0)
        XCTAssertEqual(sig8, ((8.0 * 9.0 * 8.0 + 2.0) / 3.0).squareRoot(), accuracy: 1e-5)
        // Scale compensation: radius 8 at half-scale → r=4.
        let sig4 = SkinSmoothModule.sigma(radius: 8, scale: 0.5)
        XCTAssertEqual(sig4, ((4.0 * 5.0 * 8.0 + 2.0) / 3.0).squareRoot(), accuracy: 1e-5)
        // Radius floors at 1 (σ=0 degenerates the IIR).
        XCTAssertEqual(SkinSmoothModule.scaledRadius(radius: 4, scale: 0.1), 1)
        XCTAssertEqual(SkinSmoothModule.scaledRadius(radius: 0.5, scale: 1.0), 1)
        // Halo = ceil(3σ) (D7, soften/highpass twin).
        XCTAssertEqual(
            SkinSmoothModule.halo(radius: 8, scale: 1.0),
            Int((3 * sig8).rounded(.up)))
        // Neutral predicate.
        let module = SkinSmoothModule()
        XCTAssertTrue(module.isNeutral(SkinSmoothModule.Params(strength: 0)))
        XCTAssertFalse(module.isNeutral(SkinSmoothModule.Params(strength: 0.01)))
    }
}
