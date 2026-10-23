import Foundation
import ImageIO
import LightamerCore
import UniformTypeIdentifiers
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ExifSerialSubsecTests (Plan LUMEN-A T2, X2) — the camera-serial +
// SubSecTime read legs on ExifSearchIndexer.readProperties:
//
//   ① positive: BodySerialNumber + SubsecTimeOriginal round-trip through
//      the CGImageDestination JPEG writer → the read face sees serial +
//      the subsecond-folded captureDate ("250" ms digits = +0.250 s) and
//      fillMetadata lands camera_serial on the row
//   ② missing: no tags → serial NULL + a whole-second captureDate
//   ③ fallback + empty-serial: the unprefixed SubsecTime arm folds; an
//      EMPTY serial reads NULL (an empty key must not group)
//
// VEHICLE NOTE (the T8 first-registration finding): the hand-woven TIFF
// path was RETIRED — ImageIO's TIFF reader drops the SubSecTime tags
// entirely (the 0xA421 tag never surfaces through
// CGImageSourceCopyPropertiesAtIndex; probed 2026-10-23), while the JPEG
// writer/reader round-trips both BodySerialNumber AND SubsecTimeOriginal
// (both probed in the same session). The JPEG fixture is the honest vehicle
// for both legs — DECISIONS carries the reader-behavior record.
// ─────────────────────────────────────────────────────────────────────────────

final class ExifSerialSubsecTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: ProjectFileStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exif-serial-subsec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        store = ProjectFileStore(at: tempDirectory.appendingPathComponent("SerialProj.lalb"))
        _ = try await store.create(name: "SerialProj")
    }

    override func tearDown() async throws {
        try? await store.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixture (CGImageDestination JPEG, the ExifFoldTests precedent)

    /// Write a 4×4 JPEG whose Exif dict carries DateTimeOriginal plus (when
    /// non-nil) a SubSecTime-family tag and a BodySerialNumber tag. The
    /// writer preserves both (probed 2026-10-23).
    private func writeExifJPEG(
        to url: URL,
        subsecKey: CFString? = kCGImagePropertyExifSubsecTimeOriginal,
        subsecValue: String? = nil,
        serialValue: String? = nil
    ) throws {
        let width = 4, height = 4
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.4, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!

        var exif: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: "2024:06:01 10:00:00",
        ]
        if let subsecKey, let subsecValue {
            exif[subsecKey] = subsecValue
        }
        if let serialValue {
            exif[kCGImagePropertyExifBodySerialNumber] = serialValue
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Canon",
                kCGImagePropertyTIFFModel: "EOS R5",
            ],
        ]
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    // MARK: - Store helpers

    private func storeInsert(path: String) async throws -> Int64 {
        try await store.withWriteBatch { handle in
            let insert = try handle.prepare(
                "INSERT INTO images (image_path, path_kind) VALUES (?, 0)")
            try insert.bindText(1, path)
            _ = try insert.step()
            return handle.lastInsertRowID()
        }
    }

    private func storeReadSerialRow(
        _ imageID: Int64
    ) async throws -> (serial: String?, make: String?, captureDate: Date?) {
        try await store.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT camera_serial, capture_date, camera_make FROM images"
                    + " WHERE id = ?")
            try statement.bindInt(1, imageID)
            try XCTAssertTrue(statement.step())
            return (
                serial: statement.columnText(0),
                make: statement.columnText(2),
                captureDate: statement.columnDouble(1)
                    .map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    /// "yyyy:MM:dd HH:mm:ss" → epoch seconds (the indexer's own parse
    /// semantics: UTC, whole seconds).
    private static func parseUTC(_ raw: String) -> TimeInterval {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)!.timeIntervalSince1970
    }

    private static let baseEpoch = parseUTC("2024:06:01 10:00:00")

    // MARK: - ① Positive: serial + SubsecTimeOriginal fold + write leg

    func testSerialAndSubsecOriginalReadAndWritePositive() async throws {
        let jpegURL = tempDirectory.appendingPathComponent("shot.jpg")
        try writeExifJPEG(to: jpegURL, subsecValue: "250", serialValue: "032151001234")

        // The RESEARCH §风险 4 key-name surface: the writer-round-tripped
        // tags surface through the ImageIO keys the read face consumes.
        let source = try XCTUnwrap(
            CGImageSourceCreateWithURL(jpegURL as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = try XCTUnwrap(
            properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        XCTAssertEqual(
            exif[kCGImagePropertyExifBodySerialNumber] as? String, "032151001234")
        XCTAssertEqual(exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, "250")

        let imageID = try await storeInsert(path: "Media/shot.jpg")
        let indexer = ExifSearchIndexer(store: store)
        let filled = try await indexer.fillMetadata(imageID: imageID, from: jpegURL)
        XCTAssertTrue(filled)

        let row = try await storeReadSerialRow(imageID)
        XCTAssertEqual(row.serial, "032151001234")
        XCTAssertEqual(row.make, "Canon")
        let stored = try XCTUnwrap(row.captureDate)
        XCTAssertEqual(
            stored.timeIntervalSince1970, Self.baseEpoch + 0.250, accuracy: 1e-6,
            "the '250' ms digits fold to +0.250 s on the epoch REAL column")
    }

    // MARK: - ② Missing: honest absence, no fold

    func testMissingSerialAndSubsecReadNil() async throws {
        let jpegURL = tempDirectory.appendingPathComponent("plain.jpg")
        try writeExifJPEG(to: jpegURL)

        let imageID = try await storeInsert(path: "Media/plain.jpg")
        let indexer = ExifSearchIndexer(store: store)
        let filled = try await indexer.fillMetadata(imageID: imageID, from: jpegURL)
        XCTAssertTrue(filled)

        let row = try await storeReadSerialRow(imageID)
        XCTAssertNil(row.serial, "absent serial reads NULL (never '' — a '' key would group)")
        let stored = try XCTUnwrap(row.captureDate)
        XCTAssertEqual(
            stored.timeIntervalSince1970, Self.baseEpoch, accuracy: 1e-6,
            "no SubSec tag → the whole-second date stands unfused")
    }

    // MARK: - ③ Fallback chain + empty serial is absence

    func testSubsecFallbackChainAndEmptySerialIsAbsence() async throws {
        // Only the unprefixed SubsecTime — the SECOND key of the fold chain
        // — plus an EMPTY BodySerialNumber.
        let jpegURL = tempDirectory.appendingPathComponent("chain.jpg")
        try writeExifJPEG(
            to: jpegURL, subsecKey: kCGImagePropertyExifSubsecTime,
            subsecValue: "500", serialValue: "")

        let imageID = try await storeInsert(path: "Media/chain.jpg")
        let indexer = ExifSearchIndexer(store: store)
        let filled = try await indexer.fillMetadata(imageID: imageID, from: jpegURL)
        XCTAssertTrue(filled)

        let row = try await storeReadSerialRow(imageID)
        XCTAssertNil(
            row.serial,
            "an EMPTY serial is absence — '' would group every serial-less body")
        let stored = try XCTUnwrap(row.captureDate)
        XCTAssertEqual(
            stored.timeIntervalSince1970, Self.baseEpoch + 0.500, accuracy: 1e-6,
            "the unprefixed SubsecTime fallback arm folds the same way")
    }
}
