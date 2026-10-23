import Foundation
import ImageIO
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ExifSerialSubsecTests (Plan LUMEN-A T2, X2) — the camera-serial +
// SubSecTime read legs on ExifSearchIndexer.readProperties:
//
//   ① positive: a hand-woven TIFF carrying Exif-IFD BodySerialNumber
//      (0xA431) + SubSecTimeOriginal (0xA421) + DateTimeOriginal (0x9003)
//      reads serial + a subsecond-folded captureDate (the "250" ms
//      digits = +0.250 s — Lumen's SubSecDateTimeOriginal fraction
//      semantic), and fillMetadata lands camera_serial on the row.
//      Key-name note: ImageIO's constants spell "SubsecTime" (lowercase
//      s — CGImageProperties.h :572); the plan's "SubSecTime" spelling
//      is not an ImageIO symbol (DECISIONS carries the check record)
//   ② missing: the same TIFF WITHOUT the two tags reads serial NULL and a
//      whole-second captureDate (honest absence, no fold)
//   ③ fallback + empty-serial: the unprefixed SubSecTime (0xA420) arm
//      still folds; an EMPTY BodySerialNumber reads NULL (an empty key
//      must not group all serial-less bodies)
//
// The fixture hand-weaves the TIFF bytes (the ExifLensFieldsTests
// precedent: ImageIO's CGImageDestination WRITER filters Exif-IFD tags,
// so the bytes are woven directly and read through the regular
// CGImageSource properties face — ① also pins the RESEARCH §风险 4
// ImageIO key-name surface).
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

    // MARK: - Fixture (hand-woven minimal TIFF with an Exif IFD)

    /// Weave a legal 4×4 RGB8 uncompressed TIFF whose IFD0 carries
    /// Make/Model + the Exif-IFD pointer, and whose Exif IFD carries
    /// DateTimeOriginal plus (when non-nil) a SubSecTime-family tag and a
    /// BodySerialNumber tag.
    private func writeTIFF(
        to url: URL,
        subsecTag: Int?,       // 0xA421 Original / 0xA420 plain / 0xA422 Digitized / nil absent
        subsecValue: String = "250",
        serialValue: String?   // nil = tag absent; "" = tag present but empty
    ) throws {
        func u16(_ v: Int, into out: inout [UInt8]) {
            out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF))
        }
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
        let makeBytes = Array("Canon".utf8) + [0]
        let modelBytes = Array("EOS R5".utf8) + [0]
        let dtoBytes = Array("2024:06:01 10:00:00".utf8) + [0]   // 19 incl NUL
        let subsecBytes = Array(subsecValue.utf8) + [0]
        let serialBytes = Array((serialValue ?? "").utf8) + [0]

        // Layout: header(8) | IFD0(2+3*12+4) | ExifIFD(2+n*12+4)
        //         | make | model | dto | subsec | serial | pixels
        let ifd0Offset = 8
        let ifd0Size = 2 + 3 * 12 + 4
        let exifOffset = ifd0Offset + ifd0Size
        let exifCount = 1 + (subsecTag != nil ? 1 : 0) + (serialValue != nil ? 1 : 0)
        let exifSize = 2 + exifCount * 12 + 4
        let makeOffset = exifOffset + exifSize
        let modelOffset = makeOffset + makeBytes.count
        let dtoOffset = modelOffset + modelBytes.count
        let subsecOffset = dtoOffset + dtoBytes.count
        let serialOffset = subsecOffset + subsecBytes.count
        let pixelOffset = serialOffset + serialBytes.count

        var d: [UInt8] = []
        d.append(contentsOf: [0x49, 0x49])          // "II"
        u16(42, into: &d)
        u32(ifd0Offset, into: &d)

        // IFD0 (tag-ascending): Make, Model, ExifIFD pointer.
        u16(3, into: &d)
        d.append(contentsOf: entry(0x010F, 2, makeBytes.count, makeOffset))
        d.append(contentsOf: entry(0x0110, 2, modelBytes.count, modelOffset))
        d.append(contentsOf: entry(0x8769, 4, 1, exifOffset))
        u32(0, into: &d)                             // no next IFD

        // Exif IFD (tag-ascending): DateTimeOriginal [, SubSecTime-family
        // [, BodySerialNumber]] — ASCII type 2, LONG type 4.
        u16(exifCount, into: &d)
        d.append(contentsOf: entry(0x9003, 2, dtoBytes.count, dtoOffset))
        if let subsecTag {
            d.append(contentsOf: entry(subsecTag, 2, subsecBytes.count, subsecOffset))
        }
        if serialValue != nil {
            d.append(contentsOf: entry(0xA431, 2, serialBytes.count, serialOffset))
        }
        u32(0, into: &d)

        d.append(contentsOf: makeBytes)
        d.append(contentsOf: modelBytes)
        d.append(contentsOf: dtoBytes)
        d.append(contentsOf: subsecBytes)
        d.append(contentsOf: serialBytes)
        // 4×4 RGB strip (a tiny gradient — content irrelevant to the reader).
        for y in 0..<height {
            for x in 0..<width {
                d.append(UInt8((x * 60) % 256))
                d.append(UInt8((y * 60) % 256))
                d.append(UInt8(((x + y) * 30) % 256))
            }
        }
        precondition(d.count == pixelOffset + pixelBytes)
        try Data(d).write(to: url)
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

    // MARK: - ① Positive: serial + SubSecTimeOriginal fold + write leg

    func testSerialAndSubsecOriginalReadAndWritePositive() throws {
        let tiffURL = tempDirectory.appendingPathComponent("shot.tif")
        try writeTIFF(
            to: tiffURL, subsecTag: 0xA421, serialValue: "032151001234")

        // The RESEARCH §风险 4 key-name surface: the woven Exif-IFD tags
        // surface through the ImageIO keys the read face consumes.
        let source = try XCTUnwrap(
            CGImageSourceCreateWithURL(tiffURL as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = try XCTUnwrap(
            properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        XCTAssertEqual(
            exif[kCGImagePropertyExifBodySerialNumber] as? String, "032151001234")
        XCTAssertEqual(exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, "250")

        let imageID = try await storeInsert(path: "Media/shot.tif")
        let indexer = ExifSearchIndexer(store: store)
        let filled = try await indexer.fillMetadata(imageID: imageID, from: tiffURL)
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

    func testMissingSerialAndSubsecReadNil() throws {
        let tiffURL = tempDirectory.appendingPathComponent("plain.tif")
        try writeTIFF(to: tiffURL, subsecTag: nil, serialValue: nil)

        let imageID = try await storeInsert(path: "Media/plain.tif")
        let indexer = ExifSearchIndexer(store: store)
        let filled = try await indexer.fillMetadata(imageID: imageID, from: tiffURL)
        XCTAssertTrue(filled)

        let row = try await storeReadSerialRow(imageID)
        XCTAssertNil(row.serial, "absent serial reads NULL (never '' — a '' key would group)")
        let stored = try XCTUnwrap(row.captureDate)
        XCTAssertEqual(
            stored.timeIntervalSince1970, Self.baseEpoch, accuracy: 1e-6,
            "no SubSec tag → the whole-second date stands unfused")
    }

    // MARK: - ③ Fallback chain + empty serial is absence

    func testSubsecFallbackChainAndEmptySerialIsAbsence() throws {
        // Only the unprefixed SubSecTime (0xA420) — the SECOND key of the
        // fold chain — plus an EMPTY BodySerialNumber.
        let tiffURL = tempDirectory.appendingPathComponent("chain.tif")
        try writeTIFF(
            to: tiffURL, subsecTag: 0xA420, subsecValue: "500", serialValue: "")

        let imageID = try await storeInsert(path: "Media/chain.tif")
        let indexer = ExifSearchIndexer(store: store)
        let filled = try await indexer.fillMetadata(imageID: imageID, from: tiffURL)
        XCTAssertTrue(filled)

        let row = try await storeReadSerialRow(imageID)
        XCTAssertNil(
            row.serial,
            "an EMPTY serial is absence — '' would group every serial-less body")
        let stored = try XCTUnwrap(row.captureDate)
        XCTAssertEqual(
            stored.timeIntervalSince1970, Self.baseEpoch + 0.500, accuracy: 1e-6,
            "the unprefixed SubSecTime fallback arm folds the same way")
    }
}
