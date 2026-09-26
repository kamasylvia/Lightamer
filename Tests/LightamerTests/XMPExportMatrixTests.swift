import CoreGraphics
import ImageIO
import LightamerCore
import LightamerIOP
@testable import LightamerCore
import XCTest

/// Plan 12-3 T4 — the six-format × XMP export matrix, driven through the
/// REAL post-encode chain (`ExportRenderer.encodeStage` → the
/// `ExportChainBuilder.mountXMP` seam): JPEG/TIFF/PNG products carry the
/// packet (positive anchors + host round-trip where the host reads XMP),
/// HEIC/AVIF/WebP products byte-scan CLEAN (the D-12-CONTEXT-10 reverse
/// anchors — any host drift flips these red, the 11-02 discipline).
final class XMPExportMatrixTests: XCTestCase {

    private var tempDirectory: URL!
    private var outputDirectory: URL!
    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xmp-matrix-src-\(UUID().uuidString)", isDirectory: true)
        outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xmp-matrix-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        if MTLCreateSystemDefaultDevice() != nil {
            metal = try MetalContext()
            registry = ModuleRegistry.makeDefault()
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.removeItem(at: outputDirectory)
    }

    // MARK: - Harness

    /// A source PNG + a metadata-bearing sidecar beside it (the export's
    /// XMP projection source).
    private func makeSource(
        rating: Int? = 3, flag: Int? = nil, colorLabel: Int? = 4,
        keywords: [String]? = ["Nature|Flower|Rose"]
    ) throws -> URL {
        let plane = ExportQuantizedPlane(
            data: Data([UInt8](repeating: 77, count: 16 * 16 * 4)),
            width: 16, height: 16, layout: .rgba8)
        let url = tempDirectory.appendingPathComponent("MTRX_0001.png")
        _ = try PNGEncoder().encode(ExportEncodeRequest(
            plane: plane, spec: .png(bitDepth: .eight),
            colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            destination: url))
        try writeSidecar(
            imageURL: url,
            rating: rating, flag: flag, colorLabel: colorLabel, keywords: keywords)
        return url
    }

    private func writeSidecar(
        imageURL: URL, rating: Int?, flag: Int?, colorLabel: Int?, keywords: [String]?
    ) throws {
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: UUID(),
            decoderVersionUsed: "v8",
            decodeParamsHash: 0,
            instances: [],
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: 0),
            appVersion: "0.4.0-matrix",
            rating: rating, flag: flag, colorLabel: colorLabel,
            keywords: keywords, note: nil)
        let data = try JSONEncoder().encode(document)
        try data.write(to: LightamerSidecar.sidecarURL(for: imageURL))
    }

    private func encode(_ source: URL, _ spec: ExportFormatSpec) throws -> URL {
        // The plane layout must match the spec (the registry's rule).
        let layout = try ExportEncoderRegistry.expectedLayout(for: spec)
        let samples: [UInt8]
        let count = 16 * 16 * layout.bytesPerPixel
        switch layout {
        case .rgba8: samples = [UInt8](repeating: 77, count: count)
        case .rgba16:
            var bytes = [UInt8](repeating: 0, count: count)
            for i in stride(from: 0, to: count, by: 2) {
                bytes[i] = 0x40; bytes[i + 1] = 0x40
            }
            samples = bytes
        case .float32:
            var bytes = [UInt8](repeating: 0, count: count)
            for i in stride(from: 0, to: count, by: 4) {
                bytes[i] = 0x00; bytes[i + 1] = 0x00
                bytes[i + 2] = 0x80; bytes[i + 3] = 0x3E // little-endian 0.25f
            }
            samples = bytes
        }
        let plane = ExportQuantizedPlane(
            data: Data(samples), width: 16, height: 16, layout: layout)
        let destination = outputDirectory.appendingPathComponent(
            "out.\(spec.formatName)")
        return try ExportRenderer.encodeStage(
            plane: plane, formatSpec: spec,
            targetColorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            dpi: 72, sourceURL: source, editorSignature: nil,
            destination: destination)
    }

    private func byteScan(_ url: URL, _ needle: String) throws -> Bool {
        let data = try Data(contentsOf: url)
        return data.range(of: Data(needle.utf8)) != nil
    }

    private func hostRating(_ url: URL) throws -> String? {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            return nil
        }
        return CGImageMetadataCopyStringValueWithPath(metadata, nil, "xmp:Rating" as CFString) as String?
    }

    // MARK: - The six-format matrix

    func testSixFormatMatrixPositiveAndReverseAnchors() throws {
        let source = try makeSource()

        // ── the three POSITIVE anchors ──────────────────────────────────
        let jpeg = try encode(source, .jpeg(quality: 0.9))
        XCTAssertTrue(try byteScan(jpeg, "x:xmpmeta"), "jpeg carries the packet")
        // The host's JPEG reader has no XMP face (documented host fact) —
        // the VALUE proof is the serialized element in the APP1 bytes.
        let jpegData = try Data(contentsOf: jpeg)
        XCTAssertNotNil(
            jpegData.range(of: Data("<xmp:Rating>3</xmp:Rating>".utf8)),
            "jpeg packet carries the sidecar rating")

        let png = try encode(source, .png(bitDepth: .eight))
        XCTAssertTrue(try byteScan(png, "XML:com.adobe.xmp"), "png carries the iTXt")
        XCTAssertEqual(try hostRating(png), "3", "the host reads the pre-IDAT iTXt (replacing the host's own exif:* bridge packet)")

        let tiff = try encode(source, .tiff(bitDepth: .eight, compression: .none))
        XCTAssertTrue(try byteScan(tiff, "x:xmpmeta"), "tiff carries tag 700")
        XCTAssertEqual(try hostRating(tiff), "3", "the host reads TIFF tag 700")

        // ── the three REVERSE anchors (11-02 discipline: host drift = red) ──
        let heic = try encode(source, .heic(quality: 0.9, bitDepth: .eight))
        XCTAssertFalse(try byteScan(heic, "x:xmpmeta"), "heic: documented exception")
        XCTAssertFalse(try byteScan(heic, "XML:com.adobe.xmp"), "heic: documented exception")

        let avif = try encode(source, .avif(quality: 0.6, bitDepth: .eight))
        XCTAssertFalse(try byteScan(avif, "x:xmpmeta"), "avif: documented exception")
        XCTAssertFalse(try byteScan(avif, "XML:com.adobe.xmp"), "avif: documented exception")

        let webp = try encode(source, .webp(quality: 0.8, lossless: true))
        XCTAssertFalse(try byteScan(webp, "x:xmpmeta"), "webp: documented exception")
        XCTAssertFalse(try byteScan(webp, "XML:com.adobe.xmp"), "webp: documented exception")
    }

    // MARK: - The reject → Rating -1 mapping (through the real chain)

    func testRejectFlagMapsToRatingMinusOne() throws {
        let source = try makeSource(rating: 5, flag: 2, colorLabel: nil, keywords: nil)
        let jpeg = try encode(source, .jpeg(quality: 0.9))
        let data = try Data(contentsOf: jpeg)
        // The packet rides APP1; find the Rating element in the bytes.
        XCTAssertTrue(data.range(of: Data("<xmp:Rating>-1</xmp:Rating>".utf8)) != nil,
            "reject must serialize Rating = -1 (the dt/Lr convention)")
        // A flagged-pick sidecar keeps its star rating (no XMP pick seat).
        let pickSource = try makeSource(rating: 4, flag: 1, colorLabel: nil, keywords: nil)
        let pickJPEG = try encode(pickSource, .jpeg(quality: 0.9))
        let pickData = try Data(contentsOf: pickJPEG)
        XCTAssertTrue(pickData.range(of: Data("<xmp:Rating>4</xmp:Rating>".utf8)) != nil)
        XCTAssertFalse(pickData.range(of: Data("<xmp:Rating>-1</xmp:Rating>".utf8)) != nil)
    }

    // MARK: - The degradation faces (export NEVER hard-fails on metadata)

    func testEmptySidecarSkipsAndNoFieldProductHasNoPacket() throws {
        // All-nil metadata → no packet even though the sidecar EXISTS.
        let source = try makeSource(
            rating: nil, flag: nil, colorLabel: nil, keywords: nil)
        let jpeg = try encode(source, .jpeg(quality: 0.9))
        XCTAssertFalse(try byteScan(jpeg, "x:xmpmeta"), "no fields, no packet")
        // The mount outcome face: skippedNoFields.
        let outcome = ExportChainBuilder.mountXMP(
            destination: jpeg, format: .jpeg(quality: 0.9), sourceURL: source)
        XCTAssertEqual(outcome, .skippedNoFields)
    }

    func testInjectionFailureDegradesWithoutBlocking() throws {
        // A corrupt product (SOI followed by a non-marker byte): the
        // walker throws notAJPEG, the mount reports .failed and leaves the
        // file ALIVE — the export's other value (the pixels) is never
        // destroyed by a metadata failure.
        let source = try makeSource()
        let corrupt = outputDirectory.appendingPathComponent("corrupt.jpg")
        try Data([0xFF, 0xD8, 0x12, 0x34, 0x56, 0x78]).write(to: corrupt)
        let outcome = ExportChainBuilder.mountXMP(
            destination: corrupt, format: .jpeg(quality: 0.9), sourceURL: source)
        guard case .failed = outcome else {
            return XCTFail("expected .failed, got \(outcome)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path),
            "the product survives the metadata failure")
        // The unsupported-format face: HEIC → skippedUnsupportedFormat.
        let heicOutcome = ExportChainBuilder.mountXMP(
            destination: outputDirectory.appendingPathComponent("x.heic"),
            format: .heic(quality: 0.9, bitDepth: .eight), sourceURL: source)
        XCTAssertEqual(heicOutcome, .skippedUnsupportedFormat)
    }

    // MARK: - The FULL chain (render leg included — one GPU-gated case)

    func testFullRenderChainLandsXMP() async throws {
        try XCTSkipIf(metal == nil, "no Metal GPU")
        try await LightamerIOPRegistry.populate(registry)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let source = try makeSource()
        let variant = ExportVariant(
            sizing: YiyinExportSettings(mode: .longEdge(px: 16), dpi: 72),
            format: .jpeg(quality: 0.9), colorSpace: .sRGB)
        let outcome = try await ExportRenderer.render(
            request: ExportRenderer.Request(
                imageURL: source,
                destinationDirectory: outputDirectory,
                occupiedNames: [source.lastPathComponent],
                variant: variant),
            metal: metal, registry: registry)
        XCTAssertTrue(try byteScan(outcome.destination, "x:xmpmeta"),
            "the render leg's encode stage mounts the XMP")
        let data = try Data(contentsOf: outcome.destination)
        XCTAssertTrue(data.range(of: Data("<xmp:Rating>3</xmp:Rating>".utf8)) != nil)
    }
}
