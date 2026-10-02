import CoreGraphics
import Foundation
import ImageIO
import LightamerCore
import UniformTypeIdentifiers
@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ExportEncoderMetadataTests (Plan M2-9-03 T2 — EXPORT bundle) — the encoder's
// metadata ASSEMBLY leg (E1 case A): the policy-processed EXIF round-trip,
// the fixed strips (location/serials), the EXIF Software carrier
// (D-M2-9-CONTEXT-5), and the mountXMP policy gate.
//
// HOST FACTS these tests pin (probed 2026-10-03, M2-9-03-DECISIONS):
// - a `Software` key inside `{Exif}` does NOT serialize on ANY container;
//   the `{TIFF}` dictionary's Software tag (0x0131) is the working seat
//   (JPEG EXIF APP1 / TIFF tag / HEIC+AVIF metadata / PNG's XMP
//   CreatorTool bridge).
// - the `{GPS}` dictionary is a TOP-LEVEL properties sibling — this encoder
//   never mounts it (the location strip is construction-level absence plus
//   the defensive `{Exif}` GPS-prefix pass).
// - the Sony ARW fixture's `{Exif}` round-trip carries NO serial keys
//   (serials ride MakerNote, not surfaced by ImageIO) — the strip list is
//   the EXIF-standard defensive set, per-key pinned here.
// ─────────────────────────────────────────────────────────────────────────────

final class ExportEncoderMetadataTests: XCTestCase {

    private var tempDirectory: URL!
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("enc-meta-src-\(UUID().uuidString)", isDirectory: true)
        outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("enc-meta-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.removeItem(at: outputDirectory)
    }

    // MARK: - Harness

    private static let softwareCarrier = "Lightamer 0.5.0-meta"

    /// A 16×16 gray JPEG source carrying the full metadata face: `{Exif}`
    /// with the round-trip trio (DateTimeOriginal / LensModel /
    /// BodySerialNumber) + a `Software` key (the PROVEN non-seat), the
    /// `{GPS}` dictionary, and the `{TIFF}` dictionary.
    private func makeRichSource(stem: String = "META_0001") throws -> URL {
        var rgba = [UInt8](repeating: 90, count: 16 * 16 * 4)
        for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        let plane = ExportQuantizedPlane(
            data: Data(rgba), width: 16, height: 16, layout: .rgba8)
        let url = tempDirectory.appendingPathComponent("\(stem).jpg")
        let cg = try XCTUnwrap(ImageIOEncodeCore.makeCGImage(
            from: plane, colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB)))
        let exif: [CFString: Any] = [
            "DateTimeOriginal" as CFString: "2026:01:02 03:04:05",
            "LensModel" as CFString: "Test 50mm",
            kCGImagePropertyExifBodySerialNumber: "SN123456",
            "Software" as CFString: "ProbeCam 1.0", // the proven non-seat
        ]
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 37.5,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 122.0,
            kCGImagePropertyGPSLongitudeRef: "W",
        ]
        let tiff: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "TestMake",
            kCGImagePropertyTIFFModel: "TestModel",
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyGPSDictionary: gps,
            kCGImagePropertyTIFFDictionary: tiff,
        ]
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil)
        XCTAssertNotNil(destination)
        CGImageDestinationAddImage(destination!, cg, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination!))
        try (data as Data).write(to: url)
        // The source really carries the face (guard the fixture itself).
        let props = try sourceProperties(url)
        let sourceExif = try XCTUnwrap(props[kCGImagePropertyExifDictionary] as? [CFString: Any])
        XCTAssertNotNil(sourceExif[kCGImagePropertyExifBodySerialNumber])
        XCTAssertNotNil(props[kCGImagePropertyGPSDictionary])
        return url
    }

    /// A plain 16×16 JPEG (no metadata beyond the container's own).
    private func makePlainSource(stem: String) throws -> URL {
        var rgba = [UInt8](repeating: 90, count: 16 * 16 * 4)
        for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        let plane = ExportQuantizedPlane(
            data: Data(rgba), width: 16, height: 16, layout: .rgba8)
        let url = tempDirectory.appendingPathComponent("\(stem).jpg")
        _ = try JPEGEncoder().encode(ExportEncodeRequest(
            plane: plane, spec: .jpeg(quality: 0.9),
            colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            destination: url))
        return url
    }

    /// Encode a product JPEG through the REAL encoder with an explicit
    /// request (the assembly leg's direct consumption face).
    private func encodeProduct(
        source: URL, spec: ExportFormatSpec = .jpeg(quality: 0.9),
        metadataPolicy: ExportMetadataPolicy = .standard,
        exifSoftware: String? = nil, editorSignature: String? = nil,
        stem: String = "out"
    ) throws -> URL {
        let layout = try ExportEncoderRegistry.expectedLayout(for: spec)
        let samples = [UInt8](
            repeating: 77, count: 16 * 16 * layout.bytesPerPixel)
        let plane = ExportQuantizedPlane(
            data: Data(samples), width: 16, height: 16, layout: layout)
        let destination = outputDirectory.appendingPathComponent(
            "\(stem).\(spec.fileExtension)")
        return try ExportEncoderRegistry.encoder(for: spec, plane: plane).encode(
            ExportEncodeRequest(
                plane: plane, spec: spec,
                colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
                sourceURL: source, editorSignature: editorSignature,
                destination: destination,
                exifSoftware: exifSoftware, metadataPolicy: metadataPolicy))
    }

    private func sourceProperties(_ url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func exifDict(_ url: URL) throws -> [CFString: Any] {
        (try sourceProperties(url))[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
    }

    private func tiffDict(_ url: URL) throws -> [CFString: Any] {
        (try sourceProperties(url))[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    }

    private func byteScan(_ url: URL, _ needle: String) throws -> Bool {
        try Data(contentsOf: url).range(of: Data(needle.utf8)) != nil
    }

    // MARK: - The three policy tiers on the EXIF face

    /// NONE: the whole round-trip skipped, no Software seat, no GPS — the
    /// metadata-free product. HOST FACT: ImageIO still emits a MINIMAL
    /// `{Exif}` (ColorSpace/PixelXDimension/PixelYDimension) on a JPEG —
    /// the assertion pins the ROUND-TRIP CONTENT's absence, not the
    /// container's host-generated trio.
    func testNonePolicyStripsWholeMetadataFace() throws {
        let source = try makeRichSource()
        let product = try encodeProduct(
            source: source, metadataPolicy: .none,
            exifSoftware: Self.softwareCarrier)
        let exif = try exifDict(product)
        XCTAssertNil(exif["DateTimeOriginal" as CFString], "no round-trip content")
        XCTAssertNil(exif[kCGImagePropertyExifBodySerialNumber])
        XCTAssertNil(exif["LensModel" as CFString])
        XCTAssertNil(
            try sourceProperties(product)[kCGImagePropertyGPSDictionary], "no GPS dictionary")
        let tiff = try sourceProperties(product)[kCGImagePropertyTIFFDictionary]
            as? [CFString: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFSoftware], "no Software seat")
    }

    /// STANDARD (the default policy): Software written to the working seat,
    /// serial + location stripped per-key, the rest of the round-trip kept.
    /// HOST FACT: the JPEG writer serializes the `{TIFF}` Software tag into
    /// the EXIF APP1 but the properties READBACK never surfaces `{TIFF}` on
    /// a JPEG product — the seat assertion is a byte-scan (probe-pinned,
    /// DECISIONS).
    func testStandardWritesSoftwareAndStripsSerialsAndLocation() throws {
        let source = try makeRichSource()
        let product = try encodeProduct(
            source: source, exifSoftware: Self.softwareCarrier)
        XCTAssertTrue(
            try byteScan(product, Self.softwareCarrier),
            "the carrier lands on the {TIFF} Software seat (EXIF APP1 bytes)")
        let exif = try exifDict(product)
        XCTAssertNil(
            exif[kCGImagePropertyExifBodySerialNumber],
            "the serial family's EXIF-standard seat is stripped")
        XCTAssertNil(
            exif["Software" as CFString],
            "a source {Exif} Software key neither round-trips into a seat nor leaks")
        XCTAssertEqual(exif["DateTimeOriginal" as CFString] as? String, "2026:01:02 03:04:05",
                       "the round-trip keeps the photo-mechanics keys")
        XCTAssertEqual(exif["LensModel" as CFString] as? String, "Test 50mm")
        XCTAssertNil(
            try sourceProperties(product)[kCGImagePropertyGPSDictionary],
            "the {GPS} dictionary is never mounted (construction-level absence)")
        // The source's own {TIFF} Make/Model never ride either (only the
        // Exif dictionary is mounted from the source).
        let productTIFF = try tiffDict(product)
        XCTAssertNil(productTIFF[kCGImagePropertyTIFFMake] as? String)
    }

    /// The DEFAULT carriers with no Software argument = the pre-M2-9-03
    /// face minus the sanctioned strips (the byte-stable round-trip trio).
    func testStandardWithoutCarrierKeepsRoundTripFace() throws {
        let source = try makeRichSource()
        let product = try encodeProduct(source: source)
        let exif = try exifDict(product)
        XCTAssertEqual(exif["DateTimeOriginal" as CFString] as? String, "2026:01:02 03:04:05")
        XCTAssertEqual(exif["LensModel" as CFString] as? String, "Test 50mm")
        XCTAssertNil(exif[kCGImagePropertyExifBodySerialNumber], "the fixed strip runs")
        XCTAssertNil(try tiffDict(product)[kCGImagePropertyTIFFSoftware] as? String,
                     "no carrier, no seat")
        XCTAssertNil(try sourceProperties(product)[kCGImagePropertyGPSDictionary])
    }

    /// The `exif` carrier OFF skips the round-trip (the v1 consumption
    /// face); the IPTC carrier is a documented no-op at this encoder (no
    /// IPTC dictionary is mounted on this host — DECISIONS).
    func testExifCarrierOffSkipsRoundTripAndIPTCBoolIsBoundaryNoOp() throws {
        let source = try makeRichSource()
        var policy = ExportMetadataPolicy.standard
        policy.includeExif = false
        let product = try encodeProduct(source: source, metadataPolicy: policy)
        let exif = try exifDict(product)
        XCTAssertNil(exif["DateTimeOriginal" as CFString],
                     "exif off = no round-trip content (the host trio only)")

        var iptcOff = ExportMetadataPolicy.standard
        iptcOff.includeIPTC = false
        let iptcProduct = try encodeProduct(source: source, metadataPolicy: iptcOff)
        XCTAssertEqual(
            try exifDict(iptcProduct)["DateTimeOriginal" as CFString] as? String,
            "2026:01:02 03:04:05",
            "the IPTC carrier does not gate the EXIF round-trip (v1 boundary)")
    }

    // MARK: - The Software carrier's container seats

    /// TIFF: the `editorSignature` reserved face OWNS the seat when both
    /// carriers are present (D-M2-9-CONTEXT-5's independence note — the
    /// two never fight over tag 0x0131); alone, the carrier takes it.
    func testTIFFSoftwareSeatPrecedence() throws {
        let source = try makePlainSource(stem: "TIFFSEAT_0001")
        let both = try encodeProduct(
            source: source, spec: .tiff(bitDepth: .eight, compression: .none),
            exifSoftware: Self.softwareCarrier, editorSignature: "reserved sig",
            stem: "both")
        XCTAssertEqual(
            try tiffDict(both)[kCGImagePropertyTIFFSoftware] as? String,
            "reserved sig", "the editorSignature reserved face wins the shared seat")
        let carrierOnly = try encodeProduct(
            source: source, spec: .tiff(bitDepth: .eight, compression: .none),
            exifSoftware: Self.softwareCarrier, stem: "carrier")
        XCTAssertEqual(
            try tiffDict(carrierOnly)[kCGImagePropertyTIFFSoftware] as? String,
            Self.softwareCarrier)
    }

    /// HEIC: the {TIFF} Software seat serializes and reads back (probe G).
    func testHEICSoftwareCarrierSerializes() throws {
        let source = try makePlainSource(stem: "HEICSEAT_0001")
        let product = try encodeProduct(
            source: source, spec: .heic(quality: 0.9, bitDepth: .eight),
            exifSoftware: Self.softwareCarrier)
        XCTAssertEqual(
            try tiffDict(product)[kCGImagePropertyTIFFSoftware] as? String,
            Self.softwareCarrier)
    }

    /// PNG: the {TIFF} Software seat rides the host's XMP CreatorTool
    /// bridge packet — under the DEFAULT policy (mount skipped) the bridge
    /// packet survives and the string is in the file bytes (the documented
    /// per-container seat drift; DECISIONS).
    func testPNGSoftwareRidesBridgePacketUnderDefaultPolicy() throws {
        let source = try makePlainSource(stem: "PNGSEAT_0001")
        let product = try encodeProduct(
            source: source, spec: .png(bitDepth: .eight),
            exifSoftware: Self.softwareCarrier)
        XCTAssertTrue(
            try byteScan(product, "xmp:CreatorTool"),
            "the bridge packet carries the seat")
        XCTAssertTrue(
            try byteScan(product, Self.softwareCarrier),
            "the carrier string is in the file bytes")
    }

    // MARK: - The mountXMP policy gate (outcome level)

    func testMountGateOutcomesPerPolicy() throws {
        let source = try makePlainSource(stem: "GATE_0001")
        try writeSidecar(imageURL: source, rating: 3)
        let product = try encodeProduct(source: source, stem: "gate")

        // Default → skippedByPolicy (the sanctioned narrowing).
        XCTAssertEqual(
            ExportChainBuilder.mountXMP(
                destination: product, format: .jpeg(quality: 0.9), sourceURL: source),
            .skippedByPolicy)
        // NONE mode → skippedByPolicy (the bools are moot).
        XCTAssertEqual(
            ExportChainBuilder.mountXMP(
                destination: product, format: .jpeg(quality: 0.9), sourceURL: source,
                policy: .none),
            .skippedByPolicy)
        // XMP carrier off → skippedByPolicy.
        var noXMP = ExportMetadataPolicy.standard
        noXMP.includeEditingHistory = true
        noXMP.includeXMP = false
        XCTAssertEqual(
            ExportChainBuilder.mountXMP(
                destination: product, format: .jpeg(quality: 0.9), sourceURL: source,
                policy: noXMP),
            .skippedByPolicy)
        // All carriers on → the mount runs (attached — fields exist).
        XCTAssertEqual(
            ExportChainBuilder.mountXMP(
                destination: product, format: .jpeg(quality: 0.9), sourceURL: source,
                policy: ExportMetadataPolicy(editingHistory: true)),
            .attached)
    }

    private func writeSidecar(imageURL: URL, rating: Int?) throws {
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: 0,
            instances: [],
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 0),
            appVersion: "0.4.0-enc-meta",
            rating: rating)
        try JSONEncoder().encode(document).write(
            to: LightamerSidecar.sidecarURL(for: imageURL))
    }
}
