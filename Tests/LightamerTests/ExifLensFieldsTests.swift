@testable import LightamerCore
import ImageIO
import XCTest

/// ExifLensFieldsTests (Plan LENS-01 T1) — pins the EXISTING
/// `CaptureMetadata` lens-field wiring for the Lensfun match inputs.
///
/// CONTEXT 勘误③ (review B1): `focalLength35mm` (CaptureMetadata.swift:58)
/// and `lensMake` (:78) ALREADY exist (the 08-2/08-3 yiyin six-field batch)
/// and are ALREADY wired in the decode walk (RAWDecoder.swift:550/:563-577
/// — LensMake reads the MAIN EXIF dict with the Aux fallback, plan
/// correction D-08-3-T2-1). This suite therefore asserts the EXISTING
/// wiring (a synthetic-EXIF fixture decode → non-nil values), NOT a new
/// declaration: zero production diff is the expected shape (grep guards in
/// the test body comments; `focalLengthIn35mm` re-declaration is FORBIDDEN
/// by the single-source rule).
///
/// Also pins the tolerant-additive decode contract: a legacy metadata JSON
/// (no six-key tail) decodes to the identical legacy structure (all
/// appended fields nil).
final class ExifLensFieldsTests: XCTestCase {

    // MARK: - Fixture (hand-woven minimal TIFF with an Exif IFD)

    /// ImageIO's CGImageDestination WRITER drops `FocalLenIn35mmFilm` (the
    /// 0xA405 tag never serializes into TIFF or JPEG output — probed
    /// 2026-10-21), so the fixture WOVES the TIFF bytes directly: a legal
    /// 4×4 RGB8 strip + IFD0 (10 entries incl. the 0x8769 Exif-IFD pointer)
    /// + an Exif IFD carrying 0xA405 (35mm equiv focal), 0xA433 (LensMake),
    /// 0xA434 (LensModel). ImageIO's READER side picks all three up — the
    /// walk under test (`readCaptureMetadata` →
    /// `kCGImagePropertyExifFocalLenIn35mmFilm` / `ExifLensMake`) then sees
    /// them through the regular CGImageSource properties.
    private func writeExifTIFF(
        focal35mm: UInt16,
        lensMake: String,
        lensModel: String
    ) throws -> URL {
        func u16(_ v: Int, into out: inout [UInt8]) { out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF)) }
        func u32(_ v: Int, into out: inout [UInt8]) {
            out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF)); out.append(UInt8((v >> 24) & 0xFF))
        }
        func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) -> [UInt8] {
            var e: [UInt8] = []
            u16(tag, into: &e); u16(type, into: &e); u32(count, into: &e); u32(value, into: &e)
            return e
        }

        let width = 4, height = 4
        let pixelBytes = width * height * 3
        let makeBytes = Array(lensMake.utf8) + [0]
        let modelBytes = Array(lensModel.utf8) + [0]

        // Layout: header(8) | IFD0(2 + 10*12 + 4) | ExifIFD(2 + 3*12 + 4)
        //         | bitsPerSample(6) | make | model | pixels
        let ifd0Offset = 8
        let ifd0Size = 2 + 10 * 12 + 4
        let exifOffset = ifd0Offset + ifd0Size
        let exifSize = 2 + 3 * 12 + 4
        let bitsOffset = exifOffset + exifSize
        let makeOffset = bitsOffset + 6
        let modelOffset = makeOffset + makeBytes.count
        let pixelOffset = modelOffset + modelBytes.count

        var d: [UInt8] = []
        d.append(contentsOf: [0x49, 0x49])          // "II"
        u16(42, into: &d)
        u32(ifd0Offset, into: &d)

        // IFD0 (entries must be tag-ascending).
        u16(10, into: &d)
        d.append(contentsOf: entry(256, 4, 1, width))          // ImageWidth
        d.append(contentsOf: entry(257, 4, 1, height))         // ImageLength
        d.append(contentsOf: entry(258, 3, 3, bitsOffset))     // BitsPerSample → 8,8,8
        d.append(contentsOf: entry(259, 3, 1, 1))              // Compression: none
        d.append(contentsOf: entry(262, 3, 1, 2))              // Photometric: RGB
        d.append(contentsOf: entry(273, 4, 1, pixelOffset))    // StripOffsets
        d.append(contentsOf: entry(277, 3, 1, 3))              // SamplesPerPixel
        d.append(contentsOf: entry(278, 4, 1, height))         // RowsPerStrip
        d.append(contentsOf: entry(279, 4, 1, pixelBytes))     // StripByteCounts
        d.append(contentsOf: entry(0x8769, 4, 1, exifOffset))  // Exif IFD pointer
        u32(0, into: &d)                                        // next IFD = none

        // Exif IFD.
        u16(3, into: &d)
        d.append(contentsOf: entry(0xA405, 3, 1, Int(focal35mm)))  // 35mm equiv focal
        d.append(contentsOf: entry(0xA433, 2, makeBytes.count, makeOffset))
        d.append(contentsOf: entry(0xA434, 2, modelBytes.count, modelOffset))
        u32(0, into: &d)

        u16(8, into: &d); u16(8, into: &d); u16(8, into: &d)   // BitsPerSample
        d.append(contentsOf: makeBytes)
        d.append(contentsOf: modelBytes)
        d.append(contentsOf: [UInt8](repeating: 128, count: pixelBytes))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exif-lens-\(UUID().uuidString).tif")
        try Data(d).write(to: url)
        return url
    }

    // MARK: - Wiring assertions (the EXISTING walk, through the TIFF leg)

    func testLensFieldsSurviveDecodeWalk() throws {
        let url = try writeExifTIFF(
            focal35mm: 75, lensMake: "Canon", lensModel: "EF 50mm f/1.4")
        defer { try? FileManager.default.removeItem(at: url) }

        let meta = try RAWDecoder.readCaptureMetadata(url: url)
        XCTAssertEqual(meta.focalLength35mm, 75.0, "35mm equiv focal must survive the main-EXIF walk")
        XCTAssertEqual(meta.lensMake, "Canon", "LensMake must survive the main-EXIF walk (aux fallback)")
        XCTAssertEqual(meta.lensModel, "EF 50mm f/1.4")
    }

    func testDecodedTIFFCarriesLensFieldsThroughDecodedImage() throws {
        let url = try writeExifTIFF(
            focal35mm: 120, lensMake: "Fujifilm", lensModel: "XF 23mm F1.4")
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try RasterDecoder.decodeTIFF(url)
        XCTAssertEqual(decoded.capture.focalLength35mm, 120.0)
        XCTAssertEqual(decoded.capture.lensMake, "Fujifilm")
    }

    // MARK: - Legacy zero-drift (tolerant additive decode)

    /// A pre-08-2 metadata record (no six-key tail) decodes to the SAME
    /// legacy structure: base fields intact, appended fields all nil.
    func testLegacyMetadataJSONDecodesWithoutAppendedKeys() throws {
        let legacyJSON = """
        {
          "cameraMake": "Sony",
          "cameraModel": "ILCE-7M4",
          "lensModel": "FE 16mm F2.8",
          "focalLength": 16.0,
          "aperture": 2.8,
          "iso": 400
        }
        """
        let meta = try JSONDecoder().decode(CaptureMetadata.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(meta.cameraMake, "Sony")
        XCTAssertEqual(meta.cameraModel, "ILCE-7M4")
        XCTAssertEqual(meta.lensModel, "FE 16mm F2.8")
        XCTAssertEqual(meta.focalLength, 16.0)
        XCTAssertEqual(meta.aperture, 2.8)
        XCTAssertEqual(meta.iso, 400)
        XCTAssertNil(meta.focalLength35mm)
        XCTAssertNil(meta.lensMake)
        XCTAssertNil(meta.exposureProgram)
        XCTAssertNil(meta.exposureCompensation)
        XCTAssertNil(meta.meteringMode)
        XCTAssertNil(meta.whiteBalance)
    }

    /// Full round-trip: a metadata record carrying the lens fields survives
    /// the JSON encode/decode cycle bit-for-bit on the lens face.
    func testLensFieldsRoundTripThroughJSON() throws {
        var meta = CaptureMetadata()
        meta.cameraMake = "Canon"
        meta.focalLength35mm = 75.0
        meta.lensMake = "Canon"
        meta.lensModel = "RF 24-70mm F2.8"
        let data = try JSONEncoder().encode(meta)
        let back = try JSONDecoder().decode(CaptureMetadata.self, from: data)
        XCTAssertEqual(back.focalLength35mm, 75.0)
        XCTAssertEqual(back.lensMake, "Canon")
        XCTAssertEqual(back.lensModel, "RF 24-70mm F2.8")
    }
}
