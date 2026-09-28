import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// ExifSearchIndexer (Plan M2-2-1 T3) — the materialized-column filler and
// FTS5 sync face for the library domain.
//
// `fillMetadata` reads EXIF via ImageIO PROPERTIES ONLY
// (`CGImageSourceCopyPropertiesAtIndex` — metadata read, never a decode;
// the SessionIndexStore.backfillExifMetadata:892 same-path key set: TIFF
// Make/Model, Exif LensModel/ISOSpeedRatings/FocalLength/FNumber/
// ExposureTime/DateTimeOriginal) and UPDATEs the images row's structured
// light columns + the two folded search columns (ExifFold synthesis). The
// KD-5 sync triggers keep images_fts aligned automatically — the indexer
// never writes the FTS table directly on this path.
//
// `rebuildFTS` runs the `VALUES('rebuild')` command — the full
// reconstruction from the content table (P2 import batch tails and future
// migrations consume it; the external-content column-name pin makes it
// work: images_fts reads the SAME-NAMED images.exif_search_words).
//
// Every write exits through ProjectFileStore.withWriteBatch — the KD-6
// checkpoint discipline rides along for free.
// ─────────────────────────────────────────────────────────────────────────────

public actor ExifSearchIndexer {

    private let store: ProjectFileStore

    public init(store: ProjectFileStore) {
        self.store = store
    }

    // MARK: - Fill one row (ImageIO → structured + folded columns)

    /// Read `url`'s EXIF properties and update the images row `imageID`:
    /// the eight EXIF light columns (camera_make/camera_model/lens_model/
    /// iso/focal_length/aperture/exposure/capture_date — the session v2
    /// key set) + `exif_search_text`/`exif_search_words` (ExifFold over
    /// the facts AND the row's own file_stem). Missing text → the ''
    /// attempted sentinel; missing numerics stay NULL (the session
    /// backfill's honest-absence semantics). Returns false when the file
    /// could not be opened (the row keeps NULL and a later sweep retries).
    @discardableResult
    public func fillMetadata(imageID: Int64, from url: URL) async throws -> Bool {
        guard let read = Self.readProperties(from: url) else { return false }
        return try await store.withWriteBatch { handle in
            // The row's own stem joins the fold (the M2LIB-04 search face
            // covers filenames too).
            let stemStatement = try handle.prepare(
                "SELECT file_stem FROM images WHERE id = ?")
            try stemStatement.bindInt(1, imageID)
            guard try stemStatement.step() else { return false }
            let stem = stemStatement.columnText(0)

            let facts = ExifFold.Facts(
                fileStem: stem,
                cameraMake: read.cameraMake,
                cameraModel: read.cameraModel,
                lensModel: read.lensModel,
                iso: read.iso.map(Int.init),
                focalLength: read.focalLength,
                aperture: read.aperture,
                exposure: read.exposure,
                captureDate: read.captureDate)
            let folded = ExifFold.foldedVariants(for: facts)

            let update = try handle.prepare("""
                UPDATE images SET camera_make = ?, camera_model = ?,
                    lens_model = ?, iso = ?, focal_length = ?, aperture = ?,
                    exposure = ?, capture_date = ?,
                    exif_search_text = ?, exif_search_words = ?,
                    modified_time = ?
                WHERE id = ?
                """)
            try update.bindText(1, read.cameraMake)
            try update.bindText(2, read.cameraModel)
            try update.bindText(3, read.lensModel)
            try update.bindInt(4, read.iso)
            try update.bindDouble(5, read.focalLength)
            try update.bindDouble(6, read.aperture)
            try update.bindDouble(7, read.exposure)
            try update.bindDouble(
                8, read.captureDate?.timeIntervalSince1970)
            try update.bindText(9, folded.text)
            try update.bindText(10, folded.words)
            try update.bindDouble(11, Date().timeIntervalSince1970)
            try update.bindInt(12, imageID)
            _ = try update.step()
            return true
        }
    }

    // MARK: - FTS rebuild

    /// The full FTS reconstruction from the content table (KD-5). The
    /// external-content column-name pin (`exif_search_words`, SAME name on
    /// both tables) is what makes this command legal.
    public func rebuildFTS() async throws {
        try await store.withWriteBatch { handle in
            try handle.execute(
                "INSERT INTO images_fts(images_fts) VALUES('rebuild')")
        }
    }

    // MARK: - ImageIO properties (the session v2 key set, verbatim)

    struct ExifRead: Sendable {
        var cameraMake: String
        var cameraModel: String
        var lensModel: String
        var iso: Int64?
        var focalLength: Double?
        var aperture: Double?
        var exposure: Double?
        var captureDate: Date?
    }

    /// PROPERTIES-only read (never a decode). Same extraction semantics as
    /// SessionIndexStore.backfillExifMetadata: text missing → '' (the
    /// attempted sentinel), numerics missing → NULL, ISOSpeedRatings
    /// arrives as array OR bare number, capture date from
    /// DateTimeOriginal with TIFF DateTime fallback.
    static func readProperties(from url: URL) -> ExifRead? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL, options) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source, 0, options) as? [CFString: Any] else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary]
            as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary]
            as? [CFString: Any] ?? [:]

        var captureDate: Date?
        if let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            captureDate = Self.parseEXIFDate(raw)
        }
        if captureDate == nil,
           let raw = tiff[kCGImagePropertyTIFFDateTime] as? String {
            captureDate = Self.parseEXIFDate(raw)
        }

        var iso: Int64?
        if let list = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int],
           let first = list.first {
            iso = Int64(first)
        } else if let single = exif[kCGImagePropertyExifISOSpeedRatings] as? Int {
            iso = Int64(single)
        }

        return ExifRead(
            cameraMake: (tiff[kCGImagePropertyTIFFMake] as? String) ?? "",
            cameraModel: (tiff[kCGImagePropertyTIFFModel] as? String) ?? "",
            lensModel: (exif[kCGImagePropertyExifLensModel] as? String) ?? "",
            iso: iso,
            focalLength: exif[kCGImagePropertyExifFocalLength] as? Double,
            aperture: exif[kCGImagePropertyExifFNumber] as? Double,
            exposure: exif[kCGImagePropertyExifExposureTime] as? Double,
            captureDate: captureDate)
    }

    /// The EXIF date format ("2024:06:01 10:00:00").
    static func parseEXIFDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }
}
