@testable import LightamerCore
import CoreGraphics
import ImageIO
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

    /// L029 close-out (11-05) — the colorout ColorSync FALLBACK leg
    /// (`convertTexture`) carries the same `.downMirrored` fix as its
    /// export twin, proven by DUAL-LEG PARITY: the same per-pixel pattern
    /// through (a) the fallback leg read back identity and (b) the fixed
    /// export leg directly must agree row-for-row AND match the input
    /// rows. Before the fix leg (a) came back vertically mirrored (64/64
    /// mismatch) — the row-vs-input assertion is the regression anchor,
    /// the (a)==(b) comparison is the parity contract between the two
    /// bitmap+replace legs.
    func testColorSyncFallbackLegParityWithExportLeg() async throws {
        let metal = try makeMetal()
        let pool = makePool(metal)
        var pattern = [Float]()
        pattern.reserveCapacity(64)
        for i in 0..<64 { pattern.append(Float(i % 17) / 16.0) }

        // (a) the colorout ColorSync fallback leg (linear Rec2020 → linear
        // Rec2020 = numeric pass-through) through the PRODUCTION facade
        // (MetalContext.convertToLinearSpace → pool.convertTexture), read
        // back identity afterwards. The texture crosses the actor boundary
        // the production way — inside a TextureBox (the codebase's renounce
        // wrapper; Swift 6 region isolation rejects tracked locals here).
        let fallbackInput = TextureBox(
            texture: try texture(metal, width: 4, height: 4, pixels: pattern))
        let converted = try await metal.convertToLinearSpace(
            fallbackInput.texture, target: WorkingSpace.colorSpace)
        let fallbackBitmap = try await pool.renderToEncodedBitmap(
            TextureBox(texture: converted),
            sourceColorSpace: WorkingSpace.colorSpace, toSpace: WorkingSpace.colorSpace)
        let a = floats(fallbackBitmap)

        // (b) the export leg on the same pattern.
        let inputForExport = try texture(metal, width: 4, height: 4, pixels: pattern)
        let exportBitmap = try await pool.renderToEncodedBitmap(
            TextureBox(texture: inputForExport), toSpace: WorkingSpace.colorSpace)
        let b = floats(exportBitmap)

        // Parity: both legs agree.
        XCTAssertEqual(a.count, b.count)
        for (i, pair) in zip(a, b).enumerated() {
            XCTAssertEqual(Double(pair.0), Double(pair.1), accuracy: 1e-5, "parity sample \(i)")
        }
        // Regression anchor: each leg matches the INPUT rows (a mirrored
        // leg misaligns 64/64 samples — the pre-fix failure shape).
        for (bitmap, label) in [(a, "fallback"), (b, "export")] {
            for (i, v) in bitmap.enumerated() {
                XCTAssertEqual(Double(v), Double(pattern[i]), accuracy: 1e-4,
                               "\(label) leg sample \(i): rows must match the input")
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 2: the five native encoders — golden round-trip matrix (T3).
// ─────────────────────────────────────────────────────────────────────────────

extension ExportEncoderGoldenTests {

    /// Deterministic temp fixture root (L009: NEVER external volume).
    private func goldenDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("11-02-golden-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// SplitMix64 byte stream — a deterministic pseudo-random plane that
    /// exercises losslessness far better than a gradient. Alpha bytes stay
    /// opaque (premultiplication through decode contexts must be a no-op).
    private func randomPlane(width: Int, height: Int, layout: ExportQuantizedPlane.Layout, seed: UInt64) -> ExportQuantizedPlane {
        var state = seed
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        var data = Data(capacity: width * height * layout.bytesPerPixel)
        for _ in 0..<(width * height) {
            switch layout {
            case .rgba8:
                var bytes = [UInt8](repeating: 255, count: 4)
                for c in 0..<3 { bytes[c] = UInt8(truncatingIfNeeded: next()) }
                data.append(contentsOf: bytes)
            case .rgba16:
                var samples = [UInt16](repeating: 65535, count: 4)
                for c in 0..<3 { samples[c] = UInt16(truncatingIfNeeded: next()) }
                samples.withUnsafeBufferPointer { data.append(contentsOf: Data(buffer: $0)) }
            case .float32:
                var samples = [Float](repeating: 1.0, count: 4)
                for c in 0..<3 { samples[c] = Float(next() % 10_000) / 10_000.0 }
                samples.withUnsafeBufferPointer { data.append(contentsOf: Data(buffer: $0)) }
            }
        }
        return ExportQuantizedPlane(data: data, width: width, height: height, layout: layout)
    }

    /// The known-point plane (odd 33×17 — doubles as the alignment probe):
    /// four quadrants around a neutral-gray center band.
    private func knownPointPlane() -> ExportQuantizedPlane {
        let w = 33, h = 17
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let quadrant = (x < w / 2 ? 0 : 1) + (y < h / 2 ? 0 : 2)
                let rgb: [UInt8] = switch quadrant {
                case 0: [255, 0, 0]      // red
                case 1: [0, 255, 0]      // green
                case 2: [0, 0, 255]      // blue
                default: [128, 128, 128] // neutral mid-gray
                }
                bytes[i] = rgb[0]; bytes[i + 1] = rgb[1]; bytes[i + 2] = rgb[2]; bytes[i + 3] = 255
            }
        }
        return ExportQuantizedPlane(
            data: Data(bytes), width: w, height: h, layout: .rgba8)
    }

    /// A source JPEG carrying EXIF (probe-verified write path) for the
    /// round-trip assertions.
    private func exifFixture(in dir: URL) throws -> (url: URL, date: String, lens: String) {
        let w = 4, h = 4
        var bytes = [UInt8](repeating: 200, count: w * h * 4)
        for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
        var imgData = Data(capacity: bytes.count)
        imgData.append(contentsOf: bytes)
        let provider = CGDataProvider(data: imgData as CFData)!
        let srgb = CGColorSpace(name: "kCGColorSpaceSRGB" as CFString)!
        let img = CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: srgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let url = dir.appendingPathComponent("exif-source.jpg")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        let exif: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: "2026:09:26 03:00:00",
            kCGImagePropertyExifLensModel: "GoldenFixture 50mm",
        ]
        CGImageDestinationAddImage(dest, img, [kCGImagePropertyExifDictionary: exif] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw AppError.encodeFailed("exif fixture write failed")
        }
        return (url, "2026:09:26 03:00:00", "GoldenFixture 50mm")
    }

    private func readBack(_ url: URL) throws -> (props: [String: Any], image: CGImage) {
        let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        guard let source else { throw AppError.decodeFailed("readback source nil: \(url.lastPathComponent)") }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AppError.decodeFailed("readback image nil: \(url.lastPathComponent)")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [String: Any] ?? [:]
        return (props, image)
    }

    /// Draw the decoded CGImage into a normalizing bitmap context of the
    /// given tier (same color space) and hand the packed bytes back.
    private func normalizedBytes(_ image: CGImage, layout: ExportQuantizedPlane.Layout, colorSpace: CGColorSpace) throws -> [UInt8] {
        let w = image.width, h = image.height
        let bytesPerRow = w * layout.bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
        let alpha = CGImageAlphaInfo.premultipliedLast.rawValue
        let info: CGBitmapInfo
        switch layout {
        case .rgba8: info = CGBitmapInfo(rawValue: alpha)
        case .rgba16: info = CGBitmapInfo(rawValue: alpha | CGBitmapInfo.byteOrder16Little.rawValue)
        case .float32: info = CGBitmapInfo(rawValue: alpha | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        }
        guard let ctx = CGContext(
            data: &buffer, width: w, height: h,
            bitsPerComponent: layout.bitsPerComponent, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: info.rawValue)
        else { throw AppError.decodeFailed("normalizing context failed") }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buffer
    }

    private func exifDict(_ props: [String: Any]) -> [String: Any] {
        props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
    }

    private func assertCommonMetadata(
        _ props: [String: Any], profile: String, dpi: Double, format: String,
        exif: (date: String, lens: String)?, file: StaticString = #filePath, line: UInt = #line
    ) {
        let profileName = props[kCGImagePropertyProfileName as String] as? String ?? ""
        XCTAssertTrue(profileName.contains(profile), "\(format): ICC profile name \(profileName) lacks \(profile)", file: file, line: line)
        let readDPI = props[kCGImagePropertyDPIWidth as String] as? Double
            ?? (props[kCGImagePropertyDPIWidth as String] as? CGFloat).map { Double($0) }
            ?? (props[kCGImagePropertyDPIWidth as String] as? Int).map { Double($0) }
        XCTAssertEqual(readDPI ?? -1, dpi, accuracy: 0.5, "\(format): DPI", file: file, line: line)
        // The R5 anchor (probed + byte-verified): XMP packets do NOT
        // serialize through any ImageIO write path on this host. If a future
        // macOS starts writing XMP, this fails and DECISIONS must be
        // refreshed (the plan's "失败格式文档化注记" face).
        XCTAssertNil(props["{XMP}"], "\(format): unexpected XMP — refresh the R5 documentation", file: file, line: line)
        if let exif {
            let dict = exifDict(props)
            XCTAssertEqual(dict["DateTimeOriginal"] as? String, exif.date, "\(format): EXIF date round-trip", file: file, line: line)
            XCTAssertEqual(dict["LensModel"] as? String, exif.lens, "\(format): EXIF lens round-trip", file: file, line: line)
        }
    }

    /// Sample the normalized RGBA8 buffer at a normalized coordinate.
    private func sample(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }

    // MARK: JPEG

    func testJPEGGoldenRoundTrip() throws {
        let dir = goldenDir()
        let srgb = ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)
        let plane = knownPointPlane()
        let exif = try exifFixture(in: dir)
        let request = ExportEncodeRequest(
            plane: plane, spec: .jpeg(quality: 0.92), colorSpace: srgb,
            dpi: 144, sourceURL: exif.url, destination: dir.appendingPathComponent("out.jpg"))
        try ExportEncoderRegistry.encoder(for: request.spec, plane: plane).encode(request)
        let (props, image) = try readBack(request.destination)
        XCTAssertEqual(image.width, 33, "odd width survives JPEG exactly")
        XCTAssertEqual(image.height, 17, "odd height survives JPEG exactly")
        assertCommonMetadata(props, profile: "sRGB", dpi: 144, format: "jpeg", exif: (exif.date, exif.lens))

        let bytes = try normalizedBytes(image, layout: .rgba8, colorSpace: srgb)
        // Lossy known-point bands (±3/255): the four quadrants + neutrality
        // of the gray block.
        func near(_ v: UInt8, _ want: Int, _ label: String) {
            XCTAssertLessThan(abs(Int(v) - want), 4, "jpeg \(label): \(v) vs \(want)")
        }
        let red = sample(bytes, width: 33, x: 2, y: 2)
        near(red.r, 255, "R quadrant r"); near(red.g, 0, "R quadrant g"); near(red.b, 0, "R quadrant b")
        let green = sample(bytes, width: 33, x: 30, y: 2)
        near(green.g, 255, "G quadrant g")
        let blue = sample(bytes, width: 33, x: 2, y: 14)
        near(blue.b, 255, "B quadrant b")
        let gray = sample(bytes, width: 33, x: 30, y: 14)
        near(gray.r, 128, "gray r"); near(gray.g, 128, "gray g"); near(gray.b, 128, "gray b")
        XCTAssertLessThan(abs(Int(gray.r) - Int(gray.g)), 4, "jpeg gray neutrality")
        XCTAssertLessThan(abs(Int(gray.g) - Int(gray.b)), 4, "jpeg gray neutrality")
    }

    // MARK: PNG (8/16 bitwise)

    func testPNGBitwiseRoundTrip() throws {
        let dir = goldenDir()
        let srgb = ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)
        let exif = try exifFixture(in: dir)

        for (bitDepth, layout) in [(ExportFormatSpec.PNGBitDepth.eight, ExportQuantizedPlane.Layout.rgba8),
                                   (.sixteen, .rgba16)] {
            let plane = randomPlane(width: 37, height: 19, layout: layout, seed: 0x504E47)
            let request = ExportEncodeRequest(
                plane: plane, spec: .png(bitDepth: bitDepth), colorSpace: srgb,
                dpi: 144, sourceURL: exif.url, destination: dir.appendingPathComponent("out-\(bitDepth.rawValue).png"))
            try ExportEncoderRegistry.encoder(for: request.spec, plane: plane).encode(request)
            let (props, image) = try readBack(request.destination)
            XCTAssertEqual(image.bitsPerComponent, layout.bitsPerComponent, "png \(bitDepth): depth")
            assertCommonMetadata(props, profile: "sRGB", dpi: 144, format: "png\(bitDepth)", exif: (exif.date, exif.lens))
            let bytes = try normalizedBytes(image, layout: layout, colorSpace: srgb)
            XCTAssertEqual(bytes, [UInt8](plane.data), "png \(bitDepth): LOSSLESS bitwise round-trip")
        }
    }

    // MARK: TIFF (8/16/32f × compressions, linear 32f, Software signature)

    func testTIFFTiersAndCompressions() throws {
        let dir = goldenDir()
        let srgb = ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)
        let exif = try exifFixture(in: dir)

        // 8/16-bit × all three compressions: bitwise (all three are lossless).
        let compressions: [(ExportFormatSpec.TIFFCompression, String)] = [(.none, "none"), (.lzw, "lzw"), (.zip, "zip")]
        for (bitDepth, layout) in [(ExportFormatSpec.TIFFBitDepth.eight, ExportQuantizedPlane.Layout.rgba8),
                                   (.sixteen, .rgba16)] {
            for (compression, label) in compressions {
                let plane = randomPlane(width: 31, height: 13, layout: layout, seed: 0x54494646)
                let request = ExportEncodeRequest(
                    plane: plane, spec: .tiff(bitDepth: bitDepth, compression: compression), colorSpace: srgb,
                    dpi: 144, sourceURL: exif.url,
                    destination: dir.appendingPathComponent("tiff-\(bitDepth.rawValue)-\(label).tif"))
                try ExportEncoderRegistry.encoder(for: request.spec, plane: plane).encode(request)
                let (props, image) = try readBack(request.destination)
                XCTAssertEqual(image.bitsPerComponent, layout.bitsPerComponent, "tiff \(label): depth")
                assertCommonMetadata(props, profile: "sRGB", dpi: 144, format: "tiff-\(label)", exif: (exif.date, exif.lens))
                let bytes = try normalizedBytes(image, layout: layout, colorSpace: srgb)
                XCTAssertEqual(bytes, [UInt8](plane.data), "tiff \(bitDepth)/\(label): LOSSLESS bitwise")
            }
        }

        // 32f linear: bit-exact floats, LINEAR profile (D-11-CONTEXT-7).
        let linear = try ExportColorSpaceMapper.linearCGColorSpace(for: .rec2020)
        let fplane = randomPlane(width: 16, height: 16, layout: .float32, seed: 0x7)
        let frequest = ExportEncodeRequest(
            plane: fplane, spec: .tiff(bitDepth: .float32, compression: .zip), colorSpace: linear,
            dpi: nil, sourceURL: nil, editorSignature: "Lightamer golden",
            destination: dir.appendingPathComponent("tiff-f32.tif"))
        try ExportEncoderRegistry.encoder(for: frequest.spec, plane: fplane).encode(frequest)
        let (fprops, fimage) = try readBack(frequest.destination)
        XCTAssertTrue(fimage.bitmapInfo.contains(.floatComponents), "tiff 32f: floatComponents")
        assertCommonMetadata(fprops, profile: "BT.2020", dpi: -1, format: "tiff-32f", exif: nil)
        let fbytes = try normalizedBytes(fimage, layout: .float32, colorSpace: linear)
        // HOST FINDING (probed): the 32f round trip differs from the input
        // by AT MOST ONE float32 ULP (max 5.96e-8 near 1.0 — the writer or
        // normalizing-context rounding step), i.e. numerically identical.
        // Bitwise equality is not attainable through the ImageIO float
        // path; the 1e-6 band is ~16x tighter than the observed worst case.
        let fIn = fplane.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        let fOut = fbytes.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        var maxDiff: Float = 0
        for (a, b) in zip(fIn, fOut) {
            maxDiff = max(maxDiff, abs(a - b))
        }
        XCTAssertLessThan(maxDiff, 1e-6, "tiff 32f: numeric identity (1-ULP host rounding)")
        // The editor signature rides the TIFF Software tag (the one working
        // carrier on this host — XMP does not serialize, DECISIONS).
        let tiffDict = fprops[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        XCTAssertEqual(tiffDict?["Software"] as? String, "Lightamer golden", "tiff Software carrier")
    }

    // MARK: HEIC (8 + 10-bit depth probe)

    func testHEICGoldens() throws {
        let dir = goldenDir()
        let srgb = ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)
        let exif = try exifFixture(in: dir)

        // 8-bit: known points.
        let plane8 = knownPointPlane()
        let r8 = ExportEncodeRequest(
            plane: plane8, spec: .heic(quality: 0.92, bitDepth: .eight), colorSpace: srgb,
            dpi: 144, sourceURL: exif.url, destination: dir.appendingPathComponent("out8.heic"))
        try ExportEncoderRegistry.encoder(for: r8.spec, plane: plane8).encode(r8)
        let (props8, image8) = try readBack(r8.destination)
        XCTAssertEqual(image8.width, 33); XCTAssertEqual(image8.height, 17)
        assertCommonMetadata(props8, profile: "sRGB", dpi: 144, format: "heic8", exif: (exif.date, exif.lens))
        let bytes8 = try normalizedBytes(image8, layout: .rgba8, colorSpace: srgb)
        let gray = sample(bytes8, width: 33, x: 30, y: 14)
        for (ch, v) in [("r", gray.r), ("g", gray.g), ("b", gray.b)] {
            XCTAssertLessThan(abs(Int(v) - 128), 5, "heic8 gray.\(ch)")
        }

        // 10-bit probe (R1): the 16bpc plane encodes at depth 10 (HOST FACT
        // — probed; the anchor fails if the host regresses).
        let plane16 = randomPlane(width: 20, height: 20, layout: .rgba16, seed: 0xB1)
        let r10 = ExportEncodeRequest(
            plane: plane16, spec: .heic(quality: 0.9, bitDepth: .ten), colorSpace: srgb,
            dpi: nil, sourceURL: nil, destination: dir.appendingPathComponent("out10.heic"))
        try ExportEncoderRegistry.encoder(for: r10.spec, plane: plane16).encode(r10)
        let (props10, _) = try readBack(r10.destination)
        XCTAssertEqual(props10[kCGImagePropertyDepth as String] as? Int ?? 0, 10, "HEIC 10-bit probe (R1)")
    }

    // MARK: AVIF (8 + 10 + the R1 12-bit documented downgrade)

    func testAVIFGoldens() throws {
        let dir = goldenDir()
        let srgb = ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)
        let exif = try exifFixture(in: dir)

        let plane8 = knownPointPlane()
        let r8 = ExportEncodeRequest(
            plane: plane8, spec: .avif(quality: 0.9, bitDepth: .eight), colorSpace: srgb,
            dpi: 144, sourceURL: exif.url, destination: dir.appendingPathComponent("out8.avif"))
        try ExportEncoderRegistry.encoder(for: r8.spec, plane: plane8).encode(r8)
        let (props8, image8) = try readBack(r8.destination)
        XCTAssertEqual(image8.width, 33); XCTAssertEqual(image8.height, 17)
        assertCommonMetadata(props8, profile: "sRGB", dpi: 144, format: "avif8", exif: (exif.date, exif.lens))
        let bytes8 = try normalizedBytes(image8, layout: .rgba8, colorSpace: srgb)
        let red = sample(bytes8, width: 33, x: 2, y: 2)
        XCTAssertGreaterThan(Int(red.r), 200, "avif8 red dominance")
        XCTAssertLessThan(Int(red.g), 60, "avif8 red dominance")
        XCTAssertLessThan(Int(red.b), 60, "avif8 red dominance")

        // 10-bit: depth 10 (probed host fact).
        let plane16 = randomPlane(width: 20, height: 20, layout: .rgba16, seed: 0xA1)
        let r10 = ExportEncodeRequest(
            plane: plane16, spec: .avif(quality: 0.9, bitDepth: .ten), colorSpace: srgb,
            dpi: nil, sourceURL: nil, destination: dir.appendingPathComponent("out10.avif"))
        try ExportEncoderRegistry.encoder(for: r10.spec, plane: plane16).encode(r10)
        let (props10, _) = try readBack(r10.destination)
        XCTAssertEqual(props10[kCGImagePropertyDepth as String] as? Int ?? 0, 10, "AVIF 10-bit probe (R1)")

        // 12-bit request → R1 DOCUMENTED DOWNGRADE: the host encoder lands
        // it at 10-bit (probed; the libavif protocol seam behind AVIFEncoder
        // is the future fix). Pinned here so a host capability change is
        // visible, not silent.
        let r12 = ExportEncodeRequest(
            plane: plane16, spec: .avif(quality: 0.9, bitDepth: .twelve), colorSpace: srgb,
            dpi: nil, sourceURL: nil, destination: dir.appendingPathComponent("out12.avif"))
        try ExportEncoderRegistry.encoder(for: r12.spec, plane: plane16).encode(r12)
        let (props12, _) = try readBack(r12.destination)
        XCTAssertEqual(props12[kCGImagePropertyDepth as String] as? Int ?? 0, 10,
                       "AVIF 12-bit request: R1 documented downgrade to 10 (refresh DECISIONS if the host gains 12-bit)")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 3: registry dispatch + the UTI write-capability anchor (T5).
// ─────────────────────────────────────────────────────────────────────────────

extension ExportEncoderGoldenTests {

    /// RESEARCH §1.1's probe,固化成常驻回归锚 (2026-09-26 host facts):
    /// the five native write UTIs EXIST, WebP write does NOT (libwebp is
    /// the single WebP path — D-11-CONTEXT-1). A macOS capability drift in
    /// either direction fails HERE, not in a user export.
    func testUTIWriteCapabilityAnchor() {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        for uti in ["public.jpeg", "public.png", "public.tiff", "public.heic", "public.avif"] {
            XCTAssertTrue(writable.contains(uti), "host lost write capability for \(uti)")
        }
        XCTAssertFalse(
            writable.contains("org.webmproject.webp"),
            "host GAINED WebP write — revisit D-11-CONTEXT-1 (Swift-WebP could retire)")
    }

    /// All six specs dispatch to their correct conformer (typed checks, not
    /// just non-throw) with a correctly-tiered plane.
    func testRegistryDispatchesAllSixFormats() throws {
        let srgb = ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)
        func plane(_ layout: ExportQuantizedPlane.Layout) -> ExportQuantizedPlane {
            let bytesPerPixel = layout.bytesPerPixel
            var data = Data(count: 4 * 4 * bytesPerPixel)
            data.replaceSubrange(0..<data.count, with: Data(count: data.count))
            return ExportQuantizedPlane(data: data, width: 4, height: 4, layout: layout)
        }
        let cases: [(ExportFormatSpec, ExportQuantizedPlane.Layout, any ExportEncoder)] = [
            (.jpeg(quality: 0.9), .rgba8, JPEGEncoder()),
            (.png(bitDepth: .eight), .rgba8, PNGEncoder()),
            (.png(bitDepth: .sixteen), .rgba16, PNGEncoder()),
            (.tiff(bitDepth: .eight, compression: .none), .rgba8, TIFFEncoder()),
            (.tiff(bitDepth: .sixteen, compression: .lzw), .rgba16, TIFFEncoder()),
            (.tiff(bitDepth: .float32, compression: .zip), .float32, TIFFEncoder()),
            (.heic(quality: 0.9, bitDepth: .eight), .rgba8, HEICEncoder()),
            (.heic(quality: 0.9, bitDepth: .ten), .rgba16, HEICEncoder()),
            (.avif(quality: 0.9, bitDepth: .eight), .rgba8, AVIFEncoder()),
            (.avif(quality: 0.9, bitDepth: .ten), .rgba16, AVIFEncoder()),
            (.avif(quality: 0.9, bitDepth: .twelve), .rgba16, AVIFEncoder()),
            (.webp(quality: 0.8, lossless: false), .rgba8, LightamerWebPEncoder()),
            (.webp(quality: 0.8, lossless: true), .rgba8, LightamerWebPEncoder()),
        ]
        for (spec, layout, expected) in cases {
            let encoder = try ExportEncoderRegistry.encoder(for: spec, plane: plane(layout))
            XCTAssertEqual(
                String(describing: type(of: encoder)),
                String(describing: type(of: expected)),
                "\(spec.formatName) dispatched the wrong conformer")
        }
        // expectedLayout agrees with the dispatch tiers.
        for (spec, layout, _) in cases {
            XCTAssertEqual(try ExportEncoderRegistry.expectedLayout(for: spec), layout, "\(spec.formatName) layout face")
        }
    }

    /// Tier mismatches are caller bugs → typed invalidParameter at the
    /// dispatch point (never a silent re-tier).
    func testRegistryRejectsTierMismatches() throws {
        func mismatched(_ spec: ExportFormatSpec, _ layout: ExportQuantizedPlane.Layout) -> ExportQuantizedPlane {
            let data = Data(count: 4 * 4 * layout.bytesPerPixel)
            return ExportQuantizedPlane(data: data, width: 4, height: 4, layout: layout)
        }
        let mismatches: [(ExportFormatSpec, ExportQuantizedPlane.Layout)] = [
            (.jpeg(quality: 0.9), .rgba16),
            (.png(bitDepth: .eight), .rgba16),
            (.png(bitDepth: .sixteen), .rgba8),
            (.tiff(bitDepth: .float32, compression: .none), .rgba8),
            (.heic(quality: 0.9, bitDepth: .ten), .rgba8),
            (.avif(quality: 0.9, bitDepth: .twelve), .rgba8),
        ]
        for (spec, layout) in mismatches {
            XCTAssertThrowsError(
                try ExportEncoderRegistry.encoder(for: spec, plane: mismatched(spec, layout)),
                "\(spec.formatName) accepted a \(layout.rawValue) plane"
            ) { error in
                guard case AppError.invalidParameter = error else {
                    return XCTFail("\(spec.formatName): expected invalidParameter, got \(error)")
                }
            }
        }
    }

    /// The 32f LINEAR variant boundary: sRGB/P3/Rec2020 resolve; AdobeRGB
    /// and ProPhoto throw a typed error (no system linear profile — a 32f
    /// export must never silently encode through a display TRC).
    func testLinearVariantBoundaries() throws {
        for cs in [ExportColorSpace.sRGB, .displayP3, .rec2020] {
            let linear = try ExportColorSpaceMapper.linearCGColorSpace(for: cs)
            let name = linear.name as String?
            XCTAssertTrue(name?.contains("Linear") ?? false, "\(cs): linear variant name (\(name ?? "nil"))")
        }
        for cs in [ExportColorSpace.adobeRGB, .proPhoto] {
            XCTAssertThrowsError(try ExportColorSpaceMapper.linearCGColorSpace(for: cs), "\(cs)") { error in
                guard case AppError.invalidParameter = error else {
                    return XCTFail("\(cs): expected invalidParameter, got \(error)")
                }
            }
        }
    }
}
