import Foundation
import LightamerCore
import SQLite3
import UniformTypeIdentifiers
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ExifFoldTests (Plan M2-2-1 T3) — the folded-vocabulary 双向 contract:
//
//   • DOCUMENT side: structured facts → `words` carries EVERY variant of
//     the plan-pinned families (`f2.8` + `f 2 8`, `iso800` + `iso 800`,
//     `35mm` + `35 mm`, the date decompositions, name folds); `text`
//     additionally carries the raw separator forms (`f/2.8`, `1/250`).
//   • QUERY side: `matchQueryToken` maps a user token onto the SAME
//     variant sets (the双向 alignment — every document variant is a
//     reachable query form and vice versa).
//   • PREFIX SAFETY (probe P2 correctness pin): an `iso8000` row is NOT
//     hit by an `iso800` query — asserted against the REAL FTS5 index on
//     a real package file (L009: /tmp fixture, never external volume).
//   • INDEXER ROUND-TRIP: a synthesized EXIF JPEG → fillMetadata → the
//     structured columns land + `images_fts MATCH` hits the row via the
//     folded query forms; `VALUES('rebuild')` keeps the count stable.
// ─────────────────────────────────────────────────────────────────────────────

final class ExifFoldTests: XCTestCase {

    // MARK: - Document face (facts → folded variants)

    func testApertureFamilyVariants() {
        let folded = ExifFold.foldedVariants(for: .init(aperture: 2.8))
        for variant in ["f2.8", "f 2 8"] {
            XCTAssertTrue(
                folded.words.contains(variant),
                "words must contain aperture variant \(variant)")
        }
        XCTAssertTrue(
            folded.text.contains("f/2.8"), "text carries the raw separator form")
    }

    func testISOFamilyVariants() {
        let folded = ExifFold.foldedVariants(for: .init(iso: 800))
        XCTAssertTrue(folded.words.contains("iso800"))
        XCTAssertTrue(folded.words.contains("iso 800"))
    }

    func testFocalFamilyVariants() {
        let folded = ExifFold.foldedVariants(for: .init(focalLength: 35))
        XCTAssertTrue(folded.words.contains("35mm"))
        XCTAssertTrue(folded.words.contains("35 mm"))
    }

    func testDateFamilyVariants() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let date = calendar.date(
            from: DateComponents(year: 2024, month: 6, day: 1))!
        let folded = ExifFold.foldedVariants(for: .init(captureDate: date))
        for variant in ["20240601", "2024 06 01", "202406", "2024 06", "2024"] {
            XCTAssertTrue(
                folded.words.contains(variant), "missing date variant \(variant)")
        }
    }

    func testNameFoldsAndDeduplication() {
        let folded = ExifFold.foldedVariants(
            for: .init(
                fileStem: "DSC_0001", cameraMake: "Sony",
                cameraModel: "ILCE-7M4", lensModel: "FE 35mm F1.4"))
        XCTAssertTrue(folded.words.contains("sony"))
        XCTAssertTrue(folded.words.contains("ilce-7m4"))
        XCTAssertTrue(folded.words.contains("dsc_0001"))
        // Byte-stable: same facts → identical output.
        let again = ExifFold.foldedVariants(
            for: .init(
                fileStem: "DSC_0001", cameraMake: "Sony",
                cameraModel: "ILCE-7M4", lensModel: "FE 35mm F1.4"))
        XCTAssertEqual(folded.words, again.words)
        XCTAssertEqual(folded.text, again.text)
    }

    func testExposureReciprocalFamily() {
        let folded = ExifFold.foldedVariants(for: .init(exposure: 1.0 / 250.0))
        XCTAssertTrue(folded.words.contains("1/250"))
        XCTAssertTrue(folded.words.contains("1 250"))
    }

    // MARK: - Query face (the双向 alignment)

    func testMatchQueryTokenISO() {
        let variants = ExifFold.matchQueryToken("iso800")
        XCTAssertTrue(variants.contains("iso800"))
        XCTAssertTrue(variants.contains("iso 800"))
        // Spaced query form normalizes onto the same set.
        XCTAssertEqual(
            Set(ExifFold.matchQueryToken("ISO 800")),
            Set(ExifFold.matchQueryToken("iso800")))
    }

    func testMatchQueryTokenAperture() {
        let variants = ExifFold.matchQueryToken("f2.8")
        XCTAssertTrue(variants.contains("f2.8"))
        XCTAssertTrue(variants.contains("f 2 8"))
        XCTAssertTrue(variants.contains("f/2.8"))
        // A pasted raw `f/2.8` folds onto the SAME set.
        XCTAssertEqual(
            Set(ExifFold.matchQueryToken("f/2.8")),
            Set(ExifFold.matchQueryToken("f2.8")))
    }

    func testMatchQueryTokenFocal() {
        let variants = ExifFold.matchQueryToken("35mm")
        XCTAssertTrue(variants.contains("35mm"))
        XCTAssertTrue(variants.contains("35 mm"))
    }

    func testMatchQueryTokenDatePartials() {
        XCTAssertTrue(ExifFold.matchQueryToken("20240601").contains("20240601"))
        XCTAssertTrue(ExifFold.matchQueryToken("202406").contains("202406"))
        XCTAssertTrue(ExifFold.matchQueryToken("2024").contains("2024"))
    }

    func testMatchQueryTokenPlainWord() {
        // A plain word folds to its normalized + squashed forms.
        let variants = ExifFold.matchQueryToken("Sony")
        XCTAssertTrue(variants.contains("sony"))
    }

    // MARK: - FTS real-index assertions (the P2 prefix-safety pin)

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var store: ProjectFileStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exif-fold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("FoldProj.lalb")
        store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "FoldProj")
    }

    override func tearDown() async throws {
        try await store.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// Insert a row with the folded words pre-materialized (what the
    /// Indexer's UPDATE path leaves behind).
    private static func insertImage(
        _ handle: SQLiteHandle, path: String, stem: String, words: String?
    ) throws -> Int64 {
        let statement = try handle.prepare(
            "INSERT INTO images (image_path, path_kind, file_stem, exif_search_words)"
                + " VALUES (?, 0, ?, ?)")
        try statement.bindText(1, path)
        try statement.bindText(2, stem)
        try statement.bindText(3, words)
        _ = try statement.step()
        return handle.lastInsertRowID()
    }

    /// FTS MATCH over the folded query variants (the consumer's spelling:
    /// one OR-joined quoted-phrase group per token's variant set).
    private static func ftsMatches(
        _ handle: SQLiteHandle, variants: [String]
    ) throws -> [Int64] {
        let query = variants
            .map { "\"\($0)\"" }
            .joined(separator: " OR ")
        let statement = try handle.prepare(
            "SELECT rowid FROM images_fts WHERE images_fts MATCH ?")
        try statement.bindText(1, query)
        var ids: [Int64] = []
        while try statement.step() {
            if let id = statement.columnInt(0) { ids.append(id) }
        }
        return ids
    }

    func testISO800QueryDoesNotHitISO8000Row() async throws {
        let iso800ID = try await store.withWriteBatch { handle in
            try ExifFoldTests.insertImage(
                handle, path: "Media/a.arw", stem: "a",
                words: "a iso800 iso 800")
        }
        let iso8000ID = try await store.withWriteBatch { handle in
            try ExifFoldTests.insertImage(
                handle, path: "Media/b.arw", stem: "b",
                words: "b iso8000 iso 8000")
        }

        let matches = try await store.withHandle { handle in
            try ExifFoldTests.ftsMatches(
                handle, variants: ExifFold.matchQueryToken("iso800"))
        }
        XCTAssertTrue(matches.contains(iso800ID), "iso800 must hit its own row")
        XCTAssertFalse(
            matches.contains(iso8000ID),
            "prefix safety: iso800 must NOT hit the iso8000 row (probe P2)")
    }

    // MARK: - Indexer round-trip (synthesized EXIF JPEG → columns → FTS)

    /// Write a tiny JPEG carrying EXIF (ISO 800, f/2.8, 35mm, Sony) via
    /// ImageIO (the metadata-injection face, no fixture file needed).
    private func writeExifJPEG(to url: URL) throws {
        let width = 8, height = 8
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.4, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!

        let exif: [CFString: Any] = [
            kCGImagePropertyExifISOSpeedRatings: [800],
            kCGImagePropertyExifFNumber: 2.8,
            kCGImagePropertyExifFocalLength: 35.0,
            kCGImagePropertyExifExposureTime: 1.0 / 250.0,
            kCGImagePropertyExifDateTimeOriginal: "2024:06:01 10:20:30",
        ]
        let tiff: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "Sony",
            kCGImagePropertyTIFFModel: "ILCE-7M4",
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff,
        ]
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return XCTFail("CGImageDestinationCreateWithURL failed")
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func testIndexerRoundTripFillsColumnsAndFTS() async throws {
        let jpegURL = tempDirectory.appendingPathComponent("shot.jpg")
        try writeExifJPEG(to: jpegURL)

        let imageID = try await store.withWriteBatch { handle in
            try ExifFoldTests.insertImage(
                handle, path: "Media/shot.jpg", stem: "shot", words: nil)
        }

        let indexer = ExifSearchIndexer(store: store)
        let filled = try await indexer.fillMetadata(imageID: imageID, from: jpegURL)
        XCTAssertTrue(filled)

        // The structured columns landed.
        let row = try await store.withHandle { handle -> (String?, Int64?, Double?) in
            let statement = try handle.prepare(
                "SELECT exif_search_words, iso, aperture FROM images WHERE id = ?")
            try statement.bindInt(1, imageID)
            try XCTAssertTrue(statement.step())
            return (
                statement.columnText(0),
                statement.columnInt(1),
                statement.columnDouble(2)
            )
        }
        XCTAssertEqual(row.1, 800)
        XCTAssertEqual(row.2 ?? 0, 2.8, accuracy: 0.0001)
        // The words column carries the plan-pinned families.
        let words = row.0 ?? ""
        XCTAssertTrue(words.contains("f2.8"))
        XCTAssertTrue(words.contains("iso800"))
        XCTAssertTrue(words.contains("35mm"))
        XCTAssertTrue(words.contains("20240601"))
        XCTAssertTrue(words.contains("shot"))

        // FTS MATCH via the folded query form hits THE row.
        let matches = try await store.withHandle { handle in
            try ExifFoldTests.ftsMatches(
                handle, variants: ExifFold.matchQueryToken("f2.8"))
        }
        XCTAssertEqual(matches, [imageID])

        // The rebuild keeps the index count stable (KD-5 idempotence).
        let beforeCount = try await store.withHandle { handle -> Int64 in
            let statement = try handle.prepare("SELECT COUNT(*) FROM images_fts")
            try XCTAssertTrue(statement.step())
            return statement.columnInt(0) ?? -1
        }
        try await indexer.rebuildFTS()
        let afterCount = try await store.withHandle { handle -> Int64 in
            let statement = try handle.prepare("SELECT COUNT(*) FROM images_fts")
            try XCTAssertTrue(statement.step())
            return statement.columnInt(0) ?? -2
        }
        XCTAssertEqual(beforeCount, afterCount)
        // …and the MATCH survives the rebuild.
        let matchesAfter = try await store.withHandle { handle in
            try ExifFoldTests.ftsMatches(
                handle, variants: ExifFold.matchQueryToken("f2.8"))
        }
        XCTAssertEqual(matchesAfter, [imageID])
    }

    func testFillMetadataReturnsFalseForUnreadableFile() async throws {
        let imageID = try await store.withWriteBatch { handle in
            try ExifFoldTests.insertImage(
                handle, path: "Media/missing.arw", stem: "missing", words: nil)
        }
        let indexer = ExifSearchIndexer(store: store)
        let filled = try await indexer.fillMetadata(
            imageID: imageID, from: tempDirectory.appendingPathComponent("nope.arw"))
        XCTAssertFalse(filled)
    }
}
