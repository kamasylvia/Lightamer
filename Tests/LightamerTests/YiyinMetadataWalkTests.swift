import ImageIO
import LightamerCore
import Metal
@testable import LightamerIOP
import XCTest

/// Plan 08-3 T2 (YIYIN-02) — the CaptureMetadata decoder walk: the six
/// yiyin EXIF fields the 08-2 struct face declared are now FILLED from the
/// ImageIO dictionaries (`RAWDecoder.readCaptureMetadata`), plus the
/// orientation=6 end-to-end byte-exact regression (the 8-1 pin proved the
/// layout follows upright pixels; here the FULL pipe proves the upright
/// content itself).
///
/// Honesty pattern (MetadataTests precedent): the expected values DERIVE
/// from the same file via an independent ImageIO read — no per-file facts
/// hardcoded, the tests stay honest as fixtures rotate. Samples missing a
/// field SKIP with the reason (a fixture property, not a decoder bug).
@MainActor
final class YiyinMetadataWalkTests: XCTestCase {

    // MARK: - the six-field walk (real RAW samples)

    /// Every available RAW sample: for each of the six fields, the decoder
    /// output must AGREE with the independent ImageIO read, and any
    /// non-nil value must be directionally sensible (EXIF enum ranges,
    /// positive focal length, plausible EV bias).
    func testRealRAWWalkFillsSixFieldsAgreeingWithImageIO() async throws {
        try Fixtures.require(Fixtures.cr3)
        try Fixtures.require(Fixtures.nef)
        try Fixtures.require(Fixtures.arw)
        let decoder = RAWDecoder()

        for url in [Fixtures.cr3, Fixtures.nef, Fixtures.arw] {
            let decoded = try await decoder.decode(url)
            let capture = decoded.capture
            let props = try XCTUnwrap(
                Self.imageIOProperties(url: url), "\(url.lastPathComponent): ImageIO read")
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let exifAux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any]

            // 1. focalLength35mm — positive when the file reports it.
            if let raw = exif?[kCGImagePropertyExifFocalLenIn35mmFilm]
                .flatMap(Self.double) {
                let got = try XCTUnwrap(
                    capture.focalLength35mm,
                    "\(url.lastPathComponent): ImageIO has FocalLenIn35mmFilm → decoder fills")
                XCTAssertEqual(got, raw, accuracy: 0.01, url.lastPathComponent)
                XCTAssertGreaterThan(got, 0, url.lastPathComponent)
            } else {
                XCTAssertNil(
                    capture.focalLength35mm,
                    "\(url.lastPathComponent): field absent in file → nil (additive face)")
            }

            // 2. exposureProgram — EXIF enum 0...8.
            if let raw = exif?[kCGImagePropertyExifExposureProgram]
                .flatMap(Self.double) {
                let got = try XCTUnwrap(
                    capture.exposureProgram,
                    "\(url.lastPathComponent): ImageIO has ExposureProgram → decoder fills")
                XCTAssertEqual(got, Int(raw), url.lastPathComponent)
                XCTAssertTrue(
                    (0...8).contains(got),
                    "\(url.lastPathComponent): exposureProgram enum range, got \(got)")
            } else {
                XCTAssertNil(capture.exposureProgram, url.lastPathComponent)
            }

            // 3. exposureCompensation — EV bias, plausibly ±5 stops.
            if let raw = exif?[kCGImagePropertyExifExposureBiasValue]
                .flatMap(Self.double) {
                let got = try XCTUnwrap(
                    capture.exposureCompensation,
                    "\(url.lastPathComponent): ImageIO has ExposureBias → decoder fills")
                XCTAssertEqual(got, raw, accuracy: 0.001, url.lastPathComponent)
                XCTAssertTrue(
                    (-5.0...5.0).contains(got),
                    "\(url.lastPathComponent): EV bias plausible range, got \(got)")
            } else {
                XCTAssertNil(capture.exposureCompensation, url.lastPathComponent)
            }

            // 4. meteringMode — EXIF enum 0...6.
            if let raw = exif?[kCGImagePropertyExifMeteringMode]
                .flatMap(Self.double) {
                let got = try XCTUnwrap(
                    capture.meteringMode,
                    "\(url.lastPathComponent): ImageIO has MeteringMode → decoder fills")
                XCTAssertEqual(got, Int(raw), url.lastPathComponent)
                XCTAssertTrue(
                    (0...6).contains(got),
                    "\(url.lastPathComponent): meteringMode enum range, got \(got)")
            } else {
                XCTAssertNil(capture.meteringMode, url.lastPathComponent)
            }

            // 5. whiteBalance — EXIF enum 0 (auto) / 1 (manual).
            if let raw = exif?[kCGImagePropertyExifWhiteBalance]
                .flatMap(Self.double) {
                let got = try XCTUnwrap(
                    capture.whiteBalance,
                    "\(url.lastPathComponent): ImageIO has WhiteBalance → decoder fills")
                XCTAssertEqual(got, Int(raw), url.lastPathComponent)
                XCTAssertTrue(
                    (0...1).contains(got),
                    "\(url.lastPathComponent): whiteBalance enum range, got \(got)")
            } else {
                XCTAssertNil(capture.whiteBalance, url.lastPathComponent)
            }

            // 6. lensMake — SDK face: the MAIN EXIF dictionary carries
            // LensMake (`kCGImagePropertyExifLensMake`); the Aux fallback
            // stays defensive (D-08-3-T2-1 plan correction).
            let rawLensMake = (exif?[kCGImagePropertyExifLensMake]
                ?? exifAux?[kCGImagePropertyExifLensMake]) as? String
            if let raw = rawLensMake {
                let got = try XCTUnwrap(
                    capture.lensMake,
                    "\(url.lastPathComponent): ImageIO has LensMake → decoder fills")
                XCTAssertEqual(got, raw, url.lastPathComponent)
                XCTAssertFalse(got.isEmpty, url.lastPathComponent)
            } else {
                XCTAssertNil(capture.lensMake, url.lastPathComponent)
            }
        }
    }

    /// The legacy face (08-2 T1's additive contract, re-proven end-to-end
    /// here): a sidecar-era record JSON WITHOUT the six keys decodes
    /// cleanly (all six nil) and re-encodes byte-stably.
    func testLegacyRecordJSONWithoutSixKeysDecodesCleanly() throws {
        let legacy = """
        {"cameraMake":"Canon","cameraModel":"Canon EOS R5","iso":400}
        """
        let meta = try JSONDecoder().decode(CaptureMetadata.self, from: Data(legacy.utf8))
        XCTAssertNil(meta.focalLength35mm)
        XCTAssertNil(meta.exposureProgram)
        XCTAssertNil(meta.exposureCompensation)
        XCTAssertNil(meta.meteringMode)
        XCTAssertNil(meta.whiteBalance)
        XCTAssertNil(meta.lensMake)
        XCTAssertEqual(meta.cameraMake, "Canon")
        // Round-trip: the NEW encoder writes the six keys, the decoder
        // reads them back (the additive forward face; CaptureMetadata is
        // Codable+Sendable — not Equatable, compare field-wise).
        let data = try JSONEncoder().encode(meta)
        let re = try JSONDecoder().decode(CaptureMetadata.self, from: data)
        XCTAssertEqual(re.cameraMake, meta.cameraMake)
        XCTAssertEqual(re.cameraModel, meta.cameraModel)
        XCTAssertEqual(re.iso, meta.iso)
        XCTAssertNil(re.focalLength35mm)
        XCTAssertNil(re.exposureProgram)
        XCTAssertNil(re.exposureCompensation)
        XCTAssertNil(re.meteringMode)
        XCTAssertNil(re.whiteBalance)
        XCTAssertNil(re.lensMake)
    }

    // MARK: - orientation=6 end-to-end byte-exact regression

    /// The 8-1 pin (`YiyinBordersTests.testBordersSeesUprightPixelsOrientation6`)
    /// proved the LAYOUT follows upright pixels (canvas 64×128). This T2
    /// regression proves the CONTENT end-to-end: a landscape sensor image
    /// carrying the CIImage orientation (.right = EXIF 6) renders through
    /// the borders chain exactly like the same picture supplied
    /// PRE-UPRIGHT — the decode layer's rotate() equivalent fully bakes
    /// before borders sees a single pixel (RESEARCH §8.5; yiyin
    /// `sharp().rotate()` semantics).
    ///
    /// Assertion structure (GUI-22 family honesty): cross-graph CI
    /// renders are NOT last-bit identical (two different Core Image
    /// graphs round differently), so the byte-exact face = determinism
    /// (the oriented source renders byte-identically twice) and the
    /// content face = the oriented output vs the pre-upright output
    /// within a tight epsilon, against an INDEPENDENTLY constructed
    /// upright reference image (the 90°-CW mapping
    /// upright(u,v) = sensor(x=v, y=H−1−u) baked into the fixture).
    func testOrientation6RendersByteExactAgainstPreUprightSource() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)

        // A: 64×32 landscape sensor + EXIF orientation 6 (90° CW → upright
        // portrait). B: the SAME picture pre-upright at 32×64 — pixels
        // r = v/63, g = (31−u)/31, the 90°-CW mapping of the sensor
        // gradient (r = x/63, g = y/31) — constructed independently.
        let sensor = Self.gradientImage(width: 64, height: 32)
        let upright = Self.uprightGradient(width: 32, height: 64)
        let oriented = DecodedImage(
            ciImage: sensor.ciImage.oriented(.right),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(
                orientation: 6),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
        let preUpright = DecodedImage(
            ciImage: upright.ciImage,
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(
                orientation: 1),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)

        // The borders chain (colorout → borders rate 50 → no gamma: the
        // sampled plane stays linear float32, the 08-1 pin's chain shape).
        let colorout = ModuleBox(module: ColorOutModule())
        var coParams = ColorOutModule.Params()
        coParams.outputProfile = .sRGB
        colorout.setParams(coParams)
        let borders = ModuleBox(module: BordersModule())
        var params = BordersModule.Params.neutralSeed
        params.mainImageWidthRate = 50
        borders.setParams(params)
        borders.module.displayProfileOverride = .sRGB
        let chain = [colorout as any ModuleBoxing, borders as any ModuleBoxing]

        let (fromOriented, _) = try await RenderPipeline.process(
            image: oriented, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let (fromUpright, _) = try await RenderPipeline.process(
            image: preUpright, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)

        XCTAssertEqual(fromOriented.width, 64, "the upright-portrait canvas (8-1 pin)")
        XCTAssertEqual(fromOriented.height, 128)
        XCTAssertEqual(fromUpright.width, fromOriented.width)
        XCTAssertEqual(fromUpright.height, fromOriented.height)

        let a = Self.readFloats(fromOriented, metal: metal)

        // ① DETERMINISM (the byte-exact face): the SAME oriented source
        // through a fresh pipe renders byte-identical — the rotate is
        // fully baked upstream (no per-run orientation variance).
        let (again, _) = try await RenderPipeline.process(
            image: oriented, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        let a2 = Self.readFloats(again, metal: metal)
        XCTAssertEqual(a.count, a2.count)
        XCTAssertEqual(a, a2, "orientation=6 render is byte-deterministic across pipes")

        // ② CONTENT face: the oriented output equals the pre-upright
        // output within the cross-graph epsilon (two CI render graphs of
        // the same math — the informative maxDiff prints to the log).
        let b = Self.readFloats(fromUpright, metal: metal)
        XCTAssertEqual(a.count, b.count)
        var compared = 0
        var maxDiff: Float = 0
        for (x, y) in zip(a, b) {
            compared += 1
            maxDiff = max(maxDiff, abs(x - y))
        }
        XCTAssertGreaterThan(compared, 0, "防空转: pixels compared")
        print("ORIENT6 cross-graph maxDiff = \(maxDiff) (CI graph rounding, informational)")
        XCTAssertLessThan(
            maxDiff, 1e-5,
            "orientation=6 output == pre-upright output (cross-graph CI rounding)")

        // ③ Anchor probes on the canvas: the background band is display
        // white (the #ffffff solid through COLOR-2 — COLOR-2's white face)
        // and the main region is NOT white (the gradient landed there).
        func sample(_ x: Int, _ y: Int) -> (Float, Float, Float) {
            let o = (y * fromOriented.width + x) * 4
            return (a[o], a[o + 1], a[o + 2])
        }
        let (br, bg, bb) = sample(4, 4)
        XCTAssertEqual(br, 1.0, accuracy: 1e-4, "band white r")
        XCTAssertEqual(bg, 1.0, accuracy: 1e-4, "band white g")
        XCTAssertEqual(bb, 1.0, accuracy: 1e-4, "band white b")
        let (mr, mg, _) = sample(16, 32) // the main region's top-left pixel
        XCTAssertGreaterThan(
            abs(mr - 1.0) + abs(mg - 1.0) + abs(bb - 1.0), 0.1,
            "the main region carries gradient content, not the band white")
    }

    // MARK: - helpers

    private static func imageIOProperties(url: URL) throws -> [CFString: Any]? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    /// NSNumber/NSString → Double (the decoder's own normalization face).
    private static func double(_ any: Any) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    /// A deterministic float32 gradient (the YiyinBordersTests fixture
    /// shape — L016: no ImageIO decode involved).
    private static func gradientImage(width: Int, height: Int) -> DecodedImage {
        pixelImage(width: width, height: height) { x, y in
            (Float(x) / Float(max(width - 1, 1)),
             Float(y) / Float(max(height - 1, 1)), 0.25)
        }
    }

    /// The INDEPENDENT upright reference: the 90°-CW mapping of the
    /// 64×32 sensor gradient — upright(u,v) = sensor(x=v, y=31−u), so
    /// r = v/63, g = (31−u)/31 (b = 0.25 unchanged).
    private static func uprightGradient(width: Int, height: Int) -> DecodedImage {
        pixelImage(width: width, height: height) { x, y in
            (Float(y) / 63.0, Float(31 - x) / 31.0, 0.25)
        }
    }

    private static func pixelImage(
        width: Int, height: Int, _ pixel: (Int, Int) -> (Float, Float, Float)
    ) -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let (r, g, b) = pixel(x, y)
                rgba[i + 0] = r
                rgba[i + 1] = g
                rgba[i + 2] = b
                rgba[i + 3] = 1.0
            }
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    /// float32 RGBA readback — drain FIRST (L014).
    private static func readFloats(
        _ texture: any MTLTexture, metal: MetalContext
    ) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return floats
    }
}
