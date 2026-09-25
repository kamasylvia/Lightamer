@testable import LightamerCore
import CoreGraphics
import Metal
import XCTest

/// Plan 11-02 goldens. SECTIONS:
/// 1. Exit leg (`renderToEncodedBitmap`) — known points, five target gamuts,
///    the checker-E3 sourceColorSpace dual state, and the fence (L014 form).
///    (Encoder round-trip sections land with T3/T4/T5.)
///
/// Known-point sources: COLOR-2 invariants (neutral gray stays neutral —
/// GoldenColorTests' criterion-1 precondition), the sRGB encode ladder
/// (0.5 linear → 187-188 display), and the system ICC TRCs (sRGB segmented
/// curve, AdobeRGB γ2.19921875, ROMM γ1.8, BT.1886 γ2.4) with ±2/255 bands
/// (the ColorSync low-end table finding, GoldenTolerance, does not reach
/// these mid/high float-domain points).
final class ExportEncoderGoldenTests: XCTestCase {

    // MARK: - Harness

    private func makeMetal() throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        return try MetalContext()
    }

    private func makePool(_ metal: MetalContext) -> CIContextPool {
        // Production exit legs (11-03) hand the pool the export command
        // queue; here the shared queue — the fence semantics under test are
        // the same "orders every prior write on THIS queue" contract.
        CIContextPool(device: metal.device, commandQueue: metal.commandQueue)
    }

    /// An rgba32Float shared-storage texture filled with a UNIFORM value.
    private func uniformTexture(
        _ metal: MetalContext, width: Int = 8, height: Int = 8, rgba: SIMD4<Float>
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = rgba.x; pixels[i + 1] = rgba.y
            pixels[i + 2] = rgba.z; pixels[i + 3] = rgba.w
        }
        return try texture(metal, width: width, height: height, pixels: pixels)
    }

    private func texture(
        _ metal: MetalContext, width: Int, height: Int, pixels: [Float]
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    private func floats(_ bitmap: CIContextPool.EncodedBitmap) -> [Float] {
        bitmap.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    private func firstPixel(_ bitmap: CIContextPool.EncodedBitmap) -> SIMD4<Float> {
        let f = floats(bitmap)
        return SIMD4(f[0], f[1], f[2], f[3])
    }

    /// The IEC sRGB segmented encode curve (the emission spec — the gamma
    /// module implements the same; GoldenColorTests' `srgbEncode` twin).
    private func srgbEncode(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }

    /// System display-TRC color spaces by raw constant name (the typed
    /// overlay has no ROMM/ITUR_2020 members on this SDK — see DECISIONS).
    private func targetSpace(_ name: String) throws -> CGColorSpace {
        guard let cs = CGColorSpace(name: name as CFString) else {
            throw XCTSkip("system colorspace \(name) unavailable on this host")
        }
        return cs
    }

    // MARK: - Section 1: the export exit leg (T2)

    /// Neutral gray stays neutral through EVERY target gamut (COLOR-2
    /// invariant), and the 0.5-linear level lands on each profile's own TRC
    /// encode (±2/255 band). This is the exit-leg COLOR-2 known-point set.
    func testExitLegNeutralGrayAcrossFiveTargets() async throws {
        let metal = try makeMetal()
        let pool = makePool(metal)
        let tex = try uniformTexture(metal, rgba: SIMD4(0.5, 0.5, 0.5, 1))

        let cases: [(label: String, name: String, encode: (Double) -> Double)] = [
            ("sRGB", "kCGColorSpaceSRGB", { self.srgbEncode($0) }),
            ("displayP3", "kCGColorSpaceDisplayP3", { self.srgbEncode($0) }),
            ("adobeRGB", "kCGColorSpaceAdobeRGB1998", { pow($0, 1 / 2.19921875) }),
            ("proPhoto(ROMM)", "kCGColorSpaceROMMRGB", { pow($0, 1 / 1.8) }),
            ("rec2020", "kCGColorSpaceITUR_2020", { pow($0, 1 / 2.4) }),
        ]
        for (label, name, encode) in cases {
            let target = try targetSpace(name)
            let bitmap = try await pool.renderToEncodedBitmap(TextureBox(texture: tex), toSpace: target)
            let px = firstPixel(bitmap)
            XCTAssertEqual(bitmap.width, 8)
            XCTAssertEqual(bitmap.rowBytes, 8 * 16, "\(label): float32 RGBA row pitch")
            let spread = max(abs(px.x - px.y), abs(px.y - px.z))
            XCTAssertLessThan(
                Double(spread), 1.5 / 255,
                "\(label): neutral gray drifted (R=\(px.x) G=\(px.y) B=\(px.z))")
            let want = encode(0.5)
            for (ch, v) in [("R", px.x), ("G", px.y), ("B", px.z)] {
                XCTAssertLessThan(
                    abs(Double(v) - want), 2.0 / 255,
                    "\(label).\(ch): level \(v) vs \(label)-encoded 0.5 = \(want)")
            }
        }
    }

    /// The pinned sRGB known point (plan literal): 0.5 linear → 187-188
    /// display value.
    func testExitLegSRGBHalfLinearKnownPoint() async throws {
        let metal = try makeMetal()
        let pool = makePool(metal)
        let tex = try uniformTexture(metal, rgba: SIMD4(0.5, 0.5, 0.5, 1))
        let srgb = try targetSpace("kCGColorSpaceSRGB")
        let bitmap = try await pool.renderToEncodedBitmap(TextureBox(texture: tex), toSpace: srgb)
        let px = firstPixel(bitmap)
        let byte = Double(px.x) * 255.0
        XCTAssertTrue(
            (187.0...188.0).contains(byte),
            "0.5 linear must encode to 187-188/255, got \(byte)")
    }

    /// White and black corner points across all five targets (white D65 →
    /// white via relative colorimetric; black → black).
    func testExitLegWhiteBlackCornersAllTargets() async throws {
        let metal = try makeMetal()
        let pool = makePool(metal)
        let names = [
            "kCGColorSpaceSRGB", "kCGColorSpaceDisplayP3", "kCGColorSpaceAdobeRGB1998",
            "kCGColorSpaceROMMRGB", "kCGColorSpaceITUR_2020",
        ]
        for name in names {
            let target = try targetSpace(name)
            let white = try await pool.renderToEncodedBitmap(
                TextureBox(texture: uniformTexture(metal, rgba: SIMD4(1, 1, 1, 1))), toSpace: target)
            let w = firstPixel(white)
            for v in [w.x, w.y, w.z] {
                XCTAssertGreaterThan(Double(v), 0.996, "\(name): white corner")
                XCTAssertLessThan(Double(v), 1.005, "\(name): white corner")
            }
            let black = try await pool.renderToEncodedBitmap(
                TextureBox(texture: uniformTexture(metal, rgba: SIMD4(0, 0, 0, 1))), toSpace: target)
            let b = firstPixel(black)
            for v in [b.x, b.y, b.z] {
                XCTAssertLessThan(Double(v), 0.004, "\(name): black corner")
            }
        }
    }

    /// Rec2020 primaries into Display P3 — the COLOR-2 matrix corner values
    /// (ColorOutModule header, Rec2020→P3 rows) after P3 TRC encode:
    /// red (1.34393,-0.28259,-0.06134), green (-0.06686,1.07734,-0.01048),
    /// blue (0.00375,-0.01963,1.01588). The leg is FLOAT and never clamps
    /// (the quantizer owns saturation, D-11-CONTEXT-7) — HOST FINDING (this
    /// test's first run): ColorSync passes out-of-gamut channels through as
    /// near-linear NEGATIVES (rec2020 red's G -0.2826 arrived -0.2834), so
    /// only the DOMINANT channel carries an exact expectation; the others
    /// are pinned by the dominance ordering.
    func testExitLegRec2020PrimariesIntoP3() async throws {
        let metal = try makeMetal()
        let pool = makePool(metal)
        let p3 = try targetSpace("kCGColorSpaceDisplayP3")

        let primaries: [(SIMD4<Float>, dominant: Int, want: Double)] = [
            (SIMD4(1, 0, 0, 1), 0, srgbEncode(1.343930183)),
            (SIMD4(0, 1, 0, 1), 1, srgbEncode(1.077337009)),
            (SIMD4(0, 0, 1, 1), 2, srgbEncode(1.015875875)),
        ]
        for (input, dominant, want) in primaries {
            let tex = try uniformTexture(metal, rgba: input)
            let bitmap = try await pool.renderToEncodedBitmap(TextureBox(texture: tex), toSpace: p3)
            let px = firstPixel(bitmap)
            let got = [Double(px.x), Double(px.y), Double(px.z)]
            XCTAssertLessThan(
                abs(got[dominant] - want), 0.01,
                "primary \(input): dominant channel \(got) vs expected \(want)")
            for (i, v) in got.enumerated() where i != dominant {
                XCTAssertLessThan(v, got[dominant] - 0.05, "primary \(input): dominance broken at ch\(i)")
            }
        }
    }

    /// CHECKER E3 / R2 — the sourceColorSpace DUAL STATE:
    /// 1. Identity state: a plane tagged ALREADY sRGB-encoded, rendered
    ///    source=sRGB target=sRGB, must come out UNCHANGED (the 11-03
    ///    export-chain shape: colorout did the conversion upstream, the exit
    ///    render is an identity). A second encode here IS the systematic
    ///    color cast the checker fears — the band below (±0.01) fails long
    ///    before it (encode(0.735)≈0.874, a 0.14 shift).
    /// 2. Default state: the same VALUES as linear Rec2020 (default source)
    ///    DO convert — 0.5 linear lands at the sRGB-encoded 0.735, proving
    ///    the default path converts exactly once.
    func testExitLegSourceColorSpaceDualState() async throws {
        let metal = try makeMetal()
        let pool = makePool(metal)
        let srgb = try targetSpace("kCGColorSpaceSRGB")
        let encodedHalf = Float(srgbEncode(0.5)) // ≈ 0.7354

        // (1) identity: already-encoded plane through source=target=sRGB.
        let encodedTex = try uniformTexture(metal, rgba: SIMD4(encodedHalf, encodedHalf, encodedHalf, 1))
        let identity = try await pool.renderToEncodedBitmap(TextureBox(texture: encodedTex), sourceColorSpace: srgb, toSpace: srgb)
        let ip = firstPixel(identity)
        for v in [ip.x, ip.y, ip.z] {
            XCTAssertLessThan(
                abs(Double(v) - Double(encodedHalf)), 0.01,
                "IDENTITY PATH CONVERTED (double-encode color cast): \(v) vs input \(encodedHalf)")
        }
        // The reverse witness: a second conversion would have moved the
        // value by >0.1 — far outside the identity band above.
        XCTAssertGreaterThan(
            abs(srgbEncode(Double(encodedHalf)) - Double(encodedHalf)), 0.1,
            "harness sanity: double-encoding IS detectable at this level")

        // (2) default: linear Rec2020 plane (source = WorkingSpace default)
        // converts exactly once → the sRGB-encoded half level.
        let linearTex = try uniformTexture(metal, rgba: SIMD4(0.5, 0.5, 0.5, 1))
        let converted = try await pool.renderToEncodedBitmap(TextureBox(texture: linearTex), toSpace: srgb)
        let cp = firstPixel(converted)
        for v in [cp.x, cp.y, cp.z] {
            XCTAssertLessThan(abs(Double(v) - Double(encodedHalf)), 0.01)
        }
        // And the default path genuinely differs from pass-through (the
        // conversion happened HERE, not nowhere): 0.735 vs raw 0.5.
        XCTAssertGreaterThan(abs(Double(cp.x) - 0.5), 0.1)
    }

    /// The L014 fence (GUI-22 test form): a kernel write committed WITHOUT
    /// waiting (the dispatch2DTexture shape), followed IMMEDIATELY by the
    /// exit render, must observe the written plane — the in-function fence
    /// orders every prior write on the pool's queue before CI reads. The
    /// target is LINEAR Rec2020 (same space as the source): the render is a
    /// numeric pass-through, so the assertion is pattern equality — any
    /// raced read (zeroed plane) fails loudly.
    func testExitLegFenceObservesUnwaitedDispatch() async throws {
        let metal = try makeMetal()
        let pool = makePool(metal)

        // Distinct per-pixel pattern (4×4).
        var pattern = [Float]()
        pattern.reserveCapacity(4 * 4 * 4)
        for i in 0..<64 { pattern.append(Float(i % 17) / 16.0) }
        let src = try texture(metal, width: 4, height: 4, pixels: pattern)
        let input = try texture(metal, width: 4, height: 4, pixels: [Float](repeating: -1, count: 64))

        // Commit WITHOUT waiting (the race shape from L014's host finding).
        try await metal.dispatch2DTexture(
            functionName: TerminalKernels.copy, input: src, output: input)

        // No drain here — the fence INSIDE the exit leg must do the waiting.
        let bitmap = try await pool.renderToEncodedBitmap(TextureBox(texture: input), toSpace: WorkingSpace.colorSpace)
        XCTAssertEqual(bitmap.width, 4)
        XCTAssertEqual(bitmap.height, 4)
        let got = floats(bitmap)
        XCTAssertEqual(got.count, 64)
        for (i, v) in got.enumerated() {
            // A raced read would surface the pre-copy ZEROED plane here.
            XCTAssertEqual(Double(v), Double(pattern[i]), accuracy: 1e-4, "pixel \(i)")
        }
    }
}

extension ExportEncoderGoldenTests {

    /// ROW-ORDER CONTRACT — the permanent form of the 11-02 orientation
    /// probe. `CIImage(mtlTexture:)` reads textures bottom-up (CI origin
    /// convention); the leg undoes that mirror internally, so the bitmap
    /// rows MUST match the texture rows 1:1 (this failed 64/64 before the
    /// `.downMirrored` fix — the encoded file would have been upside down).
    func testExitLegBitmapRowsMatchTextureRows() async throws {
        let metal = try makeMetal()
        let pool = makePool(metal)
        var pattern = [Float]()
        pattern.reserveCapacity(64)
        for i in 0..<64 { pattern.append(Float(i % 17) / 16.0) }
        let tex = try texture(metal, width: 4, height: 4, pixels: pattern)
        let bitmap = try await pool.renderToEncodedBitmap(
            TextureBox(texture: tex), toSpace: WorkingSpace.colorSpace)
        let got = floats(bitmap)
        for (i, v) in got.enumerated() {
            XCTAssertEqual(Double(v), Double(pattern[i]), accuracy: 1e-4, "sample \(i)")
        }
    }
}
