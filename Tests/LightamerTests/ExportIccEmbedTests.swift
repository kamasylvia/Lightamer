import CoreGraphics
import Foundation
import ImageIO
import LightamerCore
import UniformTypeIdentifiers
@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ExportIccEmbedTests (Plan M2-9-03 T3 — EXPORT bundle) — the output-ICC tier
// (OQ-7, checker E1 case A):
//
//   EMBED (the default) is the CGImage construction itself — the product
//   carries the target profile (the 11-02 golden face, re-anchored here).
//   OMIT is the post-encode strip: JPEG loses its APP2 ICC_PROFILE segments,
//   PNG its iCCP chunk, TIFF its tag 34675 — pixels untouched, every other
//   metadata face intact; HEIC/AVIF/WebP record the unreachable tier typed.
//
//   Plus the OQ-7 entry gate: a DRT linkage without a finite positive peak
//   is a typed variant refusal (Alcedo RequireResolvedExportOutputColor).
// ─────────────────────────────────────────────────────────────────────────────

final class ExportIccEmbedTests: XCTestCase {

    private var tempDirectory: URL!
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("icc-src-\(UUID().uuidString)", isDirectory: true)
        outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("icc-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.removeItem(at: outputDirectory)
    }

    // MARK: - Harness

    /// Encode a 16×16 product in the given format (the registry dispatch —
    /// the REAL encoder face), optionally carrying EXIF for the strip's
    /// metadata-integrity assertions and an explicit target space.
    private func encodeProduct(
        _ spec: ExportFormatSpec, stem: String, withEXIF: Bool = false,
        space: CGColorSpace? = nil
    ) throws -> URL {
        let layout = try ExportEncoderRegistry.expectedLayout(for: spec)
        let plane: ExportQuantizedPlane
        switch layout {
        case .rgba8:
            var rgba = [UInt8](repeating: 90, count: 16 * 16 * 4)
            for y in 0..<16 {
                for x in 0..<16 {
                    let i = (y * 16 + x) * 4
                    rgba[i] = UInt8(x * 14); rgba[i + 1] = UInt8(y * 14)
                }
            }
            plane = ExportQuantizedPlane(
                data: Data(rgba), width: 16, height: 16, layout: .rgba8)
        case .rgba16:
            var bytes = [UInt8](repeating: 0, count: 16 * 16 * 8)
            for i in stride(from: 0, to: bytes.count, by: 8) {
                bytes[i] = 0x40; bytes[i + 1] = 0x40
            }
            plane = ExportQuantizedPlane(
                data: Data(bytes), width: 16, height: 16, layout: .rgba16)
        case .float32:
            var bytes = [UInt8](repeating: 0, count: 16 * 16 * 16)
            for i in stride(from: 0, to: bytes.count, by: 16) {
                bytes[i + 2] = 0x80; bytes[i + 3] = 0x3E // 0.25f LE
            }
            plane = ExportQuantizedPlane(
                data: Data(bytes), width: 16, height: 16, layout: .float32)
        }
        let destination = outputDirectory.appendingPathComponent(
            "\(stem).\(spec.fileExtension)")
        let sourceURL: URL? = withEXIF ? try makeEXIFSource() : nil
        return try ExportEncoderRegistry.encoder(for: spec, plane: plane).encode(
            ExportEncodeRequest(
                plane: plane, spec: spec,
                colorSpace: space ?? ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
                sourceURL: sourceURL, destination: destination))
    }

    /// A small JPEG source with EXIF (the strip's metadata-integrity input).
    private func makeEXIFSource() throws -> URL {
        var rgba = [UInt8](repeating: 90, count: 16 * 16 * 4)
        for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        let plane = ExportQuantizedPlane(
            data: Data(rgba), width: 16, height: 16, layout: .rgba8)
        let url = tempDirectory.appendingPathComponent("icc-exif-src.jpg")
        let cg = try XCTUnwrap(ImageIOEncodeCore.makeCGImage(
            from: plane, colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)))
        let exif: [CFString: Any] = [
            "DateTimeOriginal" as CFString: "2026:01:02 03:04:05",
        ]
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil)
        XCTAssertNotNil(destination)
        CGImageDestinationAddImage(destination!, cg, [
            kCGImagePropertyExifDictionary: exif,
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination!))
        try (data as Data).write(to: url)
        return url
    }

    private func profileName(_ url: URL) throws -> String? {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return props[kCGImagePropertyProfileName] as? String
    }

    private func byteScan(_ url: URL, _ needle: String) throws -> Bool {
        try Data(contentsOf: url).range(of: Data(needle.utf8)) != nil
    }

    /// The JPEG entropy stream's face: everything from the SOS marker on.
    private func suffixFromSOS(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return data }
        for i in 2..<(bytes.count - 1) where bytes[i] == 0xFF && bytes[i + 1] == 0xDA {
            return data.subdata(in: i..<data.count)
        }
        return data
    }

    /// Decode to RGBA8 (the lossless-comparison face).
    private func decodedRGBA8(_ url: URL) throws -> (size: SIMD2<Int>, bytes: [UInt8]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let data = try XCTUnwrap(context.data)
        let bytes = Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: cg.width * cg.height * 4))
        return (SIMD2(cg.width, cg.height), bytes)
    }

    /// OMIT through the REAL chain shape: encode (EMBED), then strip.
    private func encodeThenStrip(
        _ spec: ExportFormatSpec, stem: String, withEXIF: Bool = false
    ) throws -> (url: URL, outcome: ExportICCStrip.Outcome) {
        let url = try encodeProduct(spec, stem: stem, withEXIF: withEXIF)
        let outcome = ExportICCStrip.stripICC(from: url, format: spec)
        return (url, outcome)
    }

    // MARK: - EMBED (the default face)

    func testEmbedDefaultKeepsProfileOnCapableContainers() throws {
        let jpeg = try encodeProduct(.jpeg(quality: 0.9), stem: "emb-jpg")
        XCTAssertTrue(try profileName(jpeg)?.contains("sRGB") == true)
        let png = try encodeProduct(.png(bitDepth: .eight), stem: "emb-png")
        XCTAssertTrue(try profileName(png)?.contains("sRGB") == true)
        let tiff = try encodeProduct(
            .tiff(bitDepth: .eight, compression: .none), stem: "emb-tif")
        XCTAssertTrue(try profileName(tiff)?.contains("sRGB") == true)
        let heic = try encodeProduct(
            .heic(quality: 0.9, bitDepth: .eight), stem: "emb-heic")
        XCTAssertTrue(try profileName(heic)?.contains("sRGB") == true)
        let avif = try encodeProduct(
            .avif(quality: 0.6, bitDepth: .eight), stem: "emb-avif")
        XCTAssertTrue(try profileName(avif)?.contains("sRGB") == true)
        // WebP never embeds (the libwebp v1 no-mux face — the documented
        // exception, pinned here as the EMBED tier's container boundary).
        let webp = try encodeProduct(
            .webp(quality: 0.8, lossless: true), stem: "emb-webp")
        XCTAssertNil(try profileName(webp))
    }

    // MARK: - OMIT on the strip-capable trio
    //
    // HOST FACT (probe-pinned, DECISIONS): for the WELL-KNOWN sRGB space
    // the JPEG/PNG writers embed NO profile payload at all (the reader
    // infers sRGB from the JFIF marker / the sRGB chunk) — the OMIT face
    // is only OBSERVABLE where a payload exists. These tests therefore
    // drive the strip on AdobeRGB targets (real APP2/iCCP payloads, the
    // M2EXP-01 menu's second stop); the sRGB no-payload face gets its own
    // typed assertion below.

    func testOMITStripsJPEGICCAndKeepsPixels() throws {
        let adobeRGB = ExportColorSpaceMapper.displayCGColorSpace(for: .adobeRGB)
        let spec = ExportFormatSpec.jpeg(quality: 0.9)
        let embedded = try encodeProduct(spec, stem: "om-jpg-ref", space: adobeRGB)
        XCTAssertTrue(try profileName(embedded)?.contains("Adobe RGB") == true,
                      "EMBED face: the payload is in (APP2)")
        let strippedURL = try encodeProduct(spec, stem: "om-jpg", space: adobeRGB)
        let outcome = ExportICCStrip.stripICC(from: strippedURL, format: spec)
        XCTAssertEqual(outcome, .stripped)
        // HOST FACT: a JPEG reader INFERS sRGB for an untagged JFIF (the
        // profile name never reads nil) — the OMIT face is the embedded
        // profile's disappearance + the payload bytes' absence.
        XCTAssertFalse(try profileName(strippedURL)?.contains("Adobe RGB") == true,
                       "the embedded profile is gone")
        XCTAssertFalse(try byteScan(strippedURL, "ICC_PROFILE"), "no APP2 ICC bytes")
        // DETERMINISM (the strongest integrity face): the stripped file is
        // EXACTLY the embedded file minus the ICC segments — the entropy
        // data (everything from SOS on) is untouched, so the decode is
        // pixel-identical by construction.
        let embeddedBytes = try Data(contentsOf: embedded)
        let strippedBytes = try Data(contentsOf: strippedURL)
        XCTAssertEqual(strippedBytes, ExportICCStrip.stripJPEGICC(embeddedBytes))
        XCTAssertEqual(
            suffixFromSOS(strippedBytes), suffixFromSOS(embeddedBytes),
            "the scan bytes are identical")
    }

    func testOMITStripsPNGICCAndKeepsPixels() throws {
        let adobeRGB = ExportColorSpaceMapper.displayCGColorSpace(for: .adobeRGB)
        let spec = ExportFormatSpec.png(bitDepth: .eight)
        let embedded = try encodeProduct(spec, stem: "om-png-ref", space: adobeRGB)
        XCTAssertTrue(try byteScan(embedded, "iCCP"), "EMBED face: the iCCP is in")
        let strippedURL = try encodeProduct(spec, stem: "om-png", space: adobeRGB)
        let outcome = ExportICCStrip.stripICC(from: strippedURL, format: spec)
        XCTAssertEqual(outcome, .stripped)
        XCTAssertNil(try profileName(strippedURL),
                     "PNG carries no inference fallback — untagged reads nil")
        XCTAssertFalse(try byteScan(strippedURL, "iCCP"), "no iCCP chunk")
        // DETERMINISM: the stripped file is exactly the embedded file minus
        // the iCCP chunk (the IDAT stream untouched → lossless decode
        // identical by construction).
        let embeddedBytes = try Data(contentsOf: embedded)
        let strippedBytes = try Data(contentsOf: strippedURL)
        XCTAssertEqual(strippedBytes, ExportICCStrip.stripPNGICCP(embeddedBytes))
    }

    func testOMITStripsTIFFICCAndKeepsMetadataWalkable() throws {
        let spec = ExportFormatSpec.tiff(bitDepth: .eight, compression: .none)
        let (stripped, outcome) = try encodeThenStrip(spec, stem: "om-tif",
                                                      withEXIF: true)
        XCTAssertEqual(outcome, .stripped)
        // HOST FACT: an untagged TIFF's profile name INFERS to sRGB — the
        // OMIT face is the ICC payload's disappearance ("acsp" signature).
        XCTAssertFalse(try byteScan(stripped, "acsp"), "tag 34675's payload gone")
        // The IFD survived the compaction: the product still DECODES and
        // the EXIF round-trip face is intact.
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(stripped as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(cg.width, 16)
        let props = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertEqual(
            exif?["DateTimeOriginal" as CFString] as? String, "2026:01:02 03:04:05",
            "the compacted IFD still walks every other entry")
    }

    /// The sRGB face: the JPEG/PNG writers embed NO payload for the
    /// well-known space (the reader infers it) — the strip degrades typed
    /// (nothing to remove) and the product stays byte-identical. The OMIT
    /// intent is already satisfied natively.
    func testOMITOnWellKnownSpaceHasNoPayloadAndDegradesTyped() throws {
        let jpeg = try encodeProduct(.jpeg(quality: 0.9), stem: "om-srgb-jpg")
        XCTAssertFalse(try byteScan(jpeg, "ICC_PROFILE"),
                       "the sRGB JPEG never embedded a payload")
        let outcome = ExportICCStrip.stripICC(from: jpeg, format: .jpeg(quality: 0.9))
        guard case .failed(let reason) = outcome else {
            return XCTFail("expected the no-payload degradation, got \(outcome)")
        }
        XCTAssertTrue(reason.contains("no ICC payload"))
        let png = try encodeProduct(.png(bitDepth: .eight), stem: "om-srgb-png")
        let pngOutcome = ExportICCStrip.stripICC(
            from: png, format: .png(bitDepth: .eight))
        guard case .failed = pngOutcome else {
            return XCTFail("expected the no-payload degradation, got \(pngOutcome)")
        }
    }

    // MARK: - OMIT on the unreachable containers

    func testOMITUnreachableRecordsTypedOutcomeAndKeepsEmbed() throws {
        let heic = try encodeProduct(
            .heic(quality: 0.9, bitDepth: .eight), stem: "om-heic")
        XCTAssertEqual(
            ExportICCStrip.stripICC(from: heic, format: .heic(quality: 0.9, bitDepth: .eight)),
            .skippedUnsupportedFormat)
        XCTAssertTrue(try profileName(heic)?.contains("sRGB") == true,
                      "the container keeps its embed")

        let avif = try encodeProduct(
            .avif(quality: 0.6, bitDepth: .eight), stem: "om-avif")
        XCTAssertEqual(
            ExportICCStrip.stripICC(from: avif, format: .avif(quality: 0.6, bitDepth: .eight)),
            .skippedUnsupportedFormat)
        XCTAssertTrue(try profileName(avif)?.contains("sRGB") == true)

        let webp = try encodeProduct(
            .webp(quality: 0.8, lossless: true), stem: "om-webp")
        XCTAssertEqual(
            ExportICCStrip.stripICC(from: webp, format: .webp(quality: 0.8, lossless: true)),
            .skippedUnsupportedFormat)
    }

    /// A second strip on an already-stripped (AdobeRGB) product degrades
    /// typed (no payload found) and leaves the product byte-identical.
    func testSecondStripDegradesTypedWithoutTouchingProduct() throws {
        let adobeRGB = ExportColorSpaceMapper.displayCGColorSpace(for: .adobeRGB)
        let spec = ExportFormatSpec.jpeg(quality: 0.9)
        let stripped = try encodeProduct(spec, stem: "om2-jpg", space: adobeRGB)
        XCTAssertEqual(
            ExportICCStrip.stripICC(from: stripped, format: spec), .stripped)
        let bytesBefore = try Data(contentsOf: stripped)
        let second = ExportICCStrip.stripICC(from: stripped, format: spec)
        guard case .failed = second else {
            return XCTFail("expected .failed on an ICC-free product, got \(second)")
        }
        XCTAssertEqual(try Data(contentsOf: stripped), bytesBefore)
    }

    // MARK: - The OQ-7 entry gate (Alcedo RequireResolvedExportOutputColor)

    private func gateVariant(peak: Float) -> ExportVariant {
        var record = DrtRecord()
        record.peakLuminance = peak
        return ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 48)),
            format: .png(bitDepth: .eight), colorSpace: .sRGB,
            drtOutput: record)
    }

    func testDRTOutputPeakGateTypedRefusalsAndLegals() throws {
        for bad in [Float(0), Float(-1), Float.nan, Float.infinity, -Float.infinity] {
            XCTAssertThrowsError(
                try gateVariant(peak: bad).validate(),
                "peak \(bad) must be a typed refusal"
            ) { error in
                guard case AppError.invalidParameter(let message) = error else {
                    return XCTFail("expected invalidParameter, got \(error)")
                }
                XCTAssertTrue(message.contains("peak"), "the message names the face")
            }
        }
        // A usable peak passes.
        XCTAssertNoThrow(try gateVariant(peak: 100).validate())
        // The legacy face (drtOutput nil) never triggers the gate — even a
        // carrier-free variant with everything else default validates.
        XCTAssertNoThrow(
            try ExportVariant(format: .jpeg(quality: 0.9)).validate())
    }
}
