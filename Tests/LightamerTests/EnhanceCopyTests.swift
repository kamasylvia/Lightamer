import CoreGraphics
import Foundation
import ImageIO
import LightamerCore
import UniformTypeIdentifiers
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// EnhanceCopyTests (Plan M2-10-06 T2, KD-3/KD-4 — APP bundle) — the AI
// copy's disk face + the single-file import twin, on the REAL chain:
//
//   • RESERVATION: concurrent `reserveCopy` winners are unique (the POSIX
//     O_EXCL pin); the Lumen name shape (index 1 = no number); per-operation
//     suffixes (增强/去杂色).
//   • CONTAINER RULE MATRIX (KD-3): 16-bit PNG → PNG; 16-bit TIFF / 8-bit
//     TIFF / 8-bit JPEG / unopenable (the RAW-equivalent leg) → TIFF 16.
//   • ENCODE: 16-bit depth on disk; a gradient round-trips within uint16
//     rounding; a failed write removes the reserved placeholder (no debris).
//   • EXIF INHERITANCE: exif make/model + GPS follow the original; the
//     orientation reads 1 (baked pixels).
//   • IMPORT TWIN (E1 real chain): reserve → write into a REAL project's
//     Media/ → `ImportService.importFile` → the images row + the `.lra`
//     carrying aiProvenance + the album placement — the ORIGINAL's bytes
//     and sidecar face untouched (D-3).
//
// Fixtures: synthetic ImageIO images in NSTemporaryDirectory (L009; the
// synthetic-bytes ruling — no real photos).
// ─────────────────────────────────────────────────────────────────────────────

final class EnhanceCopyTests: XCTestCase {

    private var root: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var service: LightamerCore.ImportService!
    private var library: LibraryStore!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("enhance-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        packageURL = root.appendingPathComponent("Proj.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Proj")
        // Qualified: the App target carries its own Session ImportService
        // (Plan 13-3) — the library-project twin is the Core one.
        service = LightamerCore.ImportService(store: fileStore)
        library = LibraryStore(store: fileStore)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private var packageDirectory: URL { packageURL.deletingLastPathComponent() }
    private var mediaDirectory: URL {
        packageDirectory.appendingPathComponent("Media", isDirectory: true)
    }

    // MARK: - Fixture helpers

    /// A gradient 16-bit image written through the REAL writer (the encode
    /// leg exercised end-to-end).
    private func gradientFrame(width: Int, height: Int) -> [Float] {
        (0..<width * height).flatMap { index -> [Float] in
            let value = Float(index % width) / Float(max(1, width - 1))
            return [value, 1 - value, value, 1]
        }
    }

    /// Write a 16-bit source image with the given properties (the fixture
    /// side of the EXIF-inheritance matrix).
    private func makeSource(
        _ name: String, uti: String, width: Int = 4, height: Int = 4,
        depth16: Bool, orientation: Int? = nil, make: String? = nil,
        gpsLatitude: Double? = nil
    ) throws -> URL {
        let url = root.appendingPathComponent(name)
        var pixels = [UInt16]()
        for index in 0..<(width * height * 4) {
            pixels.append(UInt16((index % 65536)))
        }
        let pixelData = pixels.withUnsafeBytes { Data($0) }
        let provider = try XCTUnwrap(CGDataProvider(data: pixelData as CFData))
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGBitmapInfo.byteOrder16Little.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue)
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 16,
            bitsPerPixel: 64, bytesPerRow: width * 8,
            space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
        // An 8-bit fixture: re-encode through an 8-bit destination without
        // the 16-bit properties (ImageIO writes 8 bpc from the request).
        if !depth16 {
            let context = try XCTUnwrap(CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let eightBit = try XCTUnwrap(context.makeImage())
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
                url as CFURL, uti as CFString, 1, nil))
            CGImageDestinationAddImage(destination, eightBit, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return url
        }
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyTIFFDictionary] =
                [kCGImagePropertyTIFFOrientation: orientation]
        }
        if let make {
            // ImageIO maps the EXIF Make/Model tags into the TIFF dictionary.
            properties[kCGImagePropertyTIFFDictionary] =
                [kCGImagePropertyTIFFMake: make, kCGImagePropertyTIFFModel: "TestModel"]
        }
        if let gpsLatitude {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: gpsLatitude,
                kCGImagePropertyGPSLatitudeRef: "N",
            ]
        }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, uti as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func sourceProperties(_ url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(
            source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
            as? [CFString: Any])
    }

    // MARK: - Reservation

    func testConcurrentReservationsAreUniqueAndIncrement() async throws {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let stem = "P1000001"
        let directory = mediaDirectory
        let results = try await withThrowingTaskGroup(
            of: URL.self, returning: [URL].self
        ) { group in
            for _ in 0..<8 {
                group.addTask {
                    try EnhanceCopyWriter.reserveCopy(
                        in: directory, sourceStem: stem,
                        operation: .upscale, container: .tiff16)
                }
            }
            var collected: [URL] = []
            for try await url in group { collected.append(url) }
            return collected
        }
        XCTAssertEqual(results.count, 8)
        XCTAssertEqual(Set(results).count, 8, "every concurrent winner is unique")
        let names = Set(results.map(\.lastPathComponent))
        XCTAssertTrue(names.contains("\(stem)-增强.tif"), "index 1 carries no number")
        for index in 2...8 {
            XCTAssertTrue(
                names.contains("\(stem)-增强-\(index).tif"),
                "the -N ladder covers the concurrent losers")
        }
    }

    func testReservationSuffixFollowsOperation() throws {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let upscale = try EnhanceCopyWriter.reserveCopy(
            in: mediaDirectory, sourceStem: "IMG_0001",
            operation: .upscale, container: .tiff16)
        let denoise = try EnhanceCopyWriter.reserveCopy(
            in: mediaDirectory, sourceStem: "IMG_0001",
            operation: .denoise, container: .tiff16)
        XCTAssertEqual(upscale.lastPathComponent, "IMG_0001-增强.tif")
        XCTAssertEqual(denoise.lastPathComponent, "IMG_0001-去杂色.tif")
    }

    // MARK: - Container rule

    func testContainerRuleMatrix() throws {
        // 16-bit PNG → PNG (the same-format leg).
        let png16 = try makeSource("src16.png", uti: "public.png", depth16: true)
        XCTAssertEqual(
            EnhanceCopyWriter.outputContainer(forOriginal: png16), .png16)
        // 16-bit TIFF → TIFF (the same-format leg via the default).
        let tiff16 = try makeSource("src16.tif", uti: "public.tiff", depth16: true)
        XCTAssertEqual(
            EnhanceCopyWriter.outputContainer(forOriginal: tiff16), .tiff16)
        // 8-bit TIFF → TIFF 16 (an 8-bit container would lose the depth).
        let tiff8 = try makeSource("src8.tif", uti: "public.tiff", depth16: false)
        XCTAssertEqual(
            EnhanceCopyWriter.outputContainer(forOriginal: tiff8), .tiff16)
        // 8-bit JPEG → TIFF 16 (the RAW/JPEG/WebP/HEIF leg).
        let jpeg8 = try makeSource("src8.jpg", uti: "public.jpeg", depth16: false)
        XCTAssertEqual(
            EnhanceCopyWriter.outputContainer(forOriginal: jpeg8), .tiff16)
        // 8-bit PNG → TIFF 16 (only a 16-BIT PNG keeps PNG).
        let png8 = try makeSource("src8.png", uti: "public.png", depth16: false)
        XCTAssertEqual(
            EnhanceCopyWriter.outputContainer(forOriginal: png8), .tiff16)
        // Unopenable synthetic bytes → TIFF 16 (the RAW-equivalent leg).
        let raw = root.appendingPathComponent("synthetic.ARW")
        try Data([0x9A, 0xBC, 0xDE, 0x01]).write(to: raw)
        XCTAssertEqual(
            EnhanceCopyWriter.outputContainer(forOriginal: raw), .tiff16)
    }

    // MARK: - Encode

    func testWrittenCopyIs16BitAndGradientRoundTrips() throws {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let destination = try EnhanceCopyWriter.reserveCopy(
            in: mediaDirectory, sourceStem: "grad",
            operation: .upscale, container: .tiff16)
        let width = 5, height = 3
        try EnhanceCopyWriter.writeCopy(
            rgba: gradientFrame(width: width, height: height),
            width: width, height: height,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            to: destination, originalURL: nil)
        let properties = try sourceProperties(destination)
        XCTAssertEqual(properties[kCGImagePropertyDepth] as? Int, 16)
        XCTAssertEqual(
            properties[kCGImagePropertyPixelWidth] as? Int, width)
        XCTAssertEqual(
            properties[kCGImagePropertyPixelHeight] as? Int, height)
    }

    func testFailedWriteRemovesTheReservedPlaceholder() throws {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let destination = try EnhanceCopyWriter.reserveCopy(
            in: mediaDirectory, sourceStem: "gone",
            operation: .denoise, container: .tiff16)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        // A shape-mismatched frame throws AND removes the placeholder.
        XCTAssertThrowsError(
            try EnhanceCopyWriter.writeCopy(
                rgba: [0, 0, 0, 0], width: 4, height: 4,
                colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                to: destination, originalURL: nil))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.path),
            "no debris: a cancelled run leaves no reserved placeholder")
    }

    // MARK: - EXIF inheritance

    func testEXIFInheritsOrientationBakesAndGPSPreserves() throws {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let original = try makeSource(
            "orig.tif", uti: "public.tiff", depth16: true,
            orientation: 6, make: "TestMake", gpsLatitude: 35.6812)
        let destination = try EnhanceCopyWriter.reserveCopy(
            in: mediaDirectory, sourceStem: "orig",
            operation: .upscale, container: .tiff16)
        try EnhanceCopyWriter.writeCopy(
            rgba: gradientFrame(width: 4, height: 4),
            width: 4, height: 4,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            to: destination, originalURL: original)

        let out = try sourceProperties(destination)
        // Orientation BAKED + EXIF make/model inherited (ImageIO's
        // TIFF-dictionary mapping).
        let tiffOut = try XCTUnwrap(
            out[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        XCTAssertEqual(tiffOut[kCGImagePropertyTIFFOrientation] as? Int, 1)
        XCTAssertEqual(tiffOut[kCGImagePropertyTIFFMake] as? String, "TestMake")
        XCTAssertEqual(tiffOut[kCGImagePropertyTIFFModel] as? String, "TestModel")
        // GPS follows the original (the personal-tool semantics).
        let gps = try XCTUnwrap(
            out[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        let latitude = try XCTUnwrap(gps[kCGImagePropertyGPSLatitude] as? Double)
        XCTAssertEqual(latitude, 35.6812, accuracy: 0.001)
    }

    // MARK: - The import twin (E1 real chain)

    func testImportChainRoundTripAdoptsCopyWithProvenance() async throws {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        // The ORIGINAL: a 16-bit TIFF outside the project (the enhance source).
        let original = try makeSource(
            "DSC09991.tif", uti: "public.tiff", depth16: true,
            make: "SourceMake")
        let originalBytes = try Data(contentsOf: original)

        // The writer reserves + writes INTO the project's Media/ directory.
        let copy = try EnhanceCopyWriter.reserveCopy(
            in: mediaDirectory, sourceStem: "DSC09991",
            operation: .upscale, container: .tiff16)
        try EnhanceCopyWriter.writeCopy(
            rgba: gradientFrame(width: 4, height: 4),
            width: 4, height: 4,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            to: copy, originalURL: original)

        // The album to land in (optional, default-on in the dialog).
        let album = try await library.createAlbum(kind: .album, name: "Trip")

        let provenance = SidecarAIProvenanceRecord(
            operation: .upscale, scale: 4, amount: 0,
            sourceFile: original.lastPathComponent,
            sourceImageID: "6F1D2FB2-7A34-4C1E-9E8A-55B0C3A1D2E4",
            backend: "coreml-worker")
        let rowID = try await service.importFile(
            at: copy, projectDirectory: packageDirectory,
            albumID: album.id, aiProvenance: provenance)

        // The images row: kind0 project-relative Media/ path.
        let row = try await library.image(id: rowID)
        XCTAssertEqual(row.imagePath, "Media/\(copy.lastPathComponent)")
        XCTAssertEqual(row.pathKind, .projectRelative)
        XCTAssertEqual(row.fileStem, copy.deletingPathExtension().lastPathComponent)

        // The album placement.
        let members = try await library.members(of: album.id)
        XCTAssertEqual(members, [rowID])

        // The copy's own .lra with the provenance round-trip (E4: to the
        // decode round-trip).
        let sidecarURL = LightamerSidecar.sidecarURL(for: copy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
        let sidecarData = try Data(contentsOf: sidecarURL)
        let sidecar = try JSONDecoder().decode(LightamerSidecar.self, from: sidecarData)
        XCTAssertEqual(sidecar.aiProvenance, provenance)
        XCTAssertEqual(sidecar.aiProvenance?.operation, .upscale)
        XCTAssertEqual(sidecar.aiProvenance?.scale, 4)
        XCTAssertTrue(sidecar.history.items.isEmpty, "the copy starts pristine")
        XCTAssertFalse(sidecar.driftDetected, "the mint is anchor-consistent")

        // D-3: the ORIGINAL is untouched — same bytes, NO sidecar appeared.
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: LightamerSidecar.sidecarURL(for: original).path),
            "the original's sidecar face is never created/touched by the twin")

        // A SECOND run lands on -2 (the increment ladder through the full chain).
        let second = try EnhanceCopyWriter.reserveCopy(
            in: mediaDirectory, sourceStem: "DSC09991",
            operation: .upscale, container: .tiff16)
        XCTAssertEqual(
            second.lastPathComponent, "DSC09991-增强-2.tif")
    }

    func testImportFileRejectsTargetsOutsideMedia() async throws {
        let outside = try makeSource("outside.tif", uti: "public.tiff", depth16: true)
        do {
            _ = try await service.importFile(
                at: outside, projectDirectory: packageDirectory)
            XCTFail("the adopt twin refuses files outside Media/")
        } catch let error as ImportError {
            XCTAssertEqual(
                error, .adoptTargetOutsideMedia(path: outside.path),
                "the typed adopt rejection")
        }
    }
}
