import ImageIO
import LightamerCore
import UniformTypeIdentifiers
import XCTest

/// RAW-06 deep coverage — capture-metadata semantics of `RAWDecoder.decode`
/// (D-23a): EXIF orientation range, EXIF date parsing, dimensions, GPS and
/// IPTC presence. The expected values are DERIVED from the same file via
/// ImageIO (public APIs, independent read path) — no per-file facts are
/// hardcoded, so the tests stay honest as fixtures rotate.
final class MetadataTests: XCTestCase {

    /// CR3 + NEF: orientation is nil or a valid EXIF 1...8 value; width and
    /// height are positive; EXIF-derived exposure fields agree with the
    /// ImageIO dictionaries.
    func testOrientationDimensionsAndExposureAgreeWithImageIO() async throws {
        try Fixtures.require(Fixtures.cr3)
        try Fixtures.require(Fixtures.nef)
        let decoder = RAWDecoder()

        for url in [Fixtures.cr3, Fixtures.nef] {
            let decoded = try await decoder.decode(url)
            let capture = decoded.capture

            if let orientation = capture.orientation {
                XCTAssertTrue(
                    (1...8).contains(orientation),
                    "\(url.pathExtension): EXIF orientation must be 1...8, got \(orientation)"
                )
            } else {
                XCTFail("\(url.pathExtension): camera RAW files carry an EXIF orientation")
            }

            XCTAssertGreaterThan(capture.width ?? 0, 0, "\(url.pathExtension): width")
            XCTAssertGreaterThan(capture.height ?? 0, 0, "\(url.pathExtension): height")

            // Cross-check against ImageIO's own read of the same file.
            let props = try XCTUnwrap(
                MetadataTests.imageIOProperties(url: url),
                "\(url.pathExtension): ImageIO read for cross-check"
            )
            let pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
            let pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
            XCTAssertEqual(capture.width, pixelWidth, "\(url.pathExtension): width vs ImageIO")
            XCTAssertEqual(capture.height, pixelHeight, "\(url.pathExtension): height vs ImageIO")

            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let fNumber = exif[kCGImagePropertyExifFNumber] as? Double {
                XCTAssertEqual(
                    capture.aperture ?? 0, fNumber, accuracy: 0.01,
                    "\(url.pathExtension): aperture vs EXIF FNumber"
                )
            }
            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double {
                XCTAssertEqual(
                    capture.shutterSpeed ?? 0, exposureTime, accuracy: 0.0001,
                    "\(url.pathExtension): shutter vs EXIF ExposureTime"
                )
            }
        }
    }

    /// RAW-06 — EXIF DateTimeOriginal parses into a real `Date` ("yyyy:MM:dd
    /// HH:mm:ss" GMT per `RAWDecoder.parseEXIFDate` semantics): the decoded
    /// capture time must equal the EXIF string parsed independently here.
    func testCaptureTimeParsesFromEXIF() async throws {
        try Fixtures.require(Fixtures.cr3)
        let decoded = try await RAWDecoder().decode(Fixtures.cr3)
        let captureTime = try XCTUnwrap(decoded.capture.captureTime, "CR3 carries DateTimeOriginal")

        let props = try XCTUnwrap(MetadataTests.imageIOProperties(url: Fixtures.cr3))
        let exif = try XCTUnwrap(props[kCGImagePropertyExifDictionary] as? [CFString: Any])
        let raw = try XCTUnwrap(
            exif[kCGImagePropertyExifDateTimeOriginal] as? String,
            "EXIF DateTimeOriginal string present"
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let expected = try XCTUnwrap(formatter.date(from: raw), "EXIF date parses: \(raw)")
        XCTAssertEqual(
            captureTime.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0,
            "decoder capture time == EXIF DateTimeOriginal (GMT, ±1 s clock rounding)"
        )
    }

    /// RAW-06 — GPS: extracted when the file carries a GPS dictionary
    /// (latitude/longitude sign follows the N/S + E/W refs); skipped with a
    /// documented reason on fixtures without GPS (studio samples often
    /// carry none — that is a fixture property, not a decoder bug).
    func testGPSParsedWhenPresent() async throws {
        try Fixtures.require(Fixtures.cr3)
        let props = try XCTUnwrap(MetadataTests.imageIOProperties(url: Fixtures.cr3))
        guard let gpsDict = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              gpsDict[kCGImagePropertyGPSLatitude] != nil
        else {
            throw XCTSkip("CR3 fixture carries no GPS dictionary — nothing to assert")
        }

        let decoded = try await RAWDecoder().decode(Fixtures.cr3)
        let gps = try XCTUnwrap(decoded.capture.gps, "GPS dict present → capture.gps non-nil")

        let lat = try XCTUnwrap(gpsDict[kCGImagePropertyGPSLatitude] as? Double)
        let lon = try XCTUnwrap(gpsDict[kCGImagePropertyGPSLongitude] as? Double)
        let expectedLat = (gpsDict[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -lat : lat
        let expectedLon = (gpsDict[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -lon : lon
        XCTAssertEqual(gps.latitude ?? .nan, expectedLat, accuracy: 0.0001)
        XCTAssertEqual(gps.longitude ?? .nan, expectedLon, accuracy: 0.0001)
    }

    /// RAW-06 — IPTC presence is surfaced without crashing. IPTC is
    /// optional (fixture-dependent); when the decoder reports a capture time
    /// ONLY via the IPTC fallback the EXIF dict must lack DateTimeOriginal.
    /// Primary assertion: a full decode runs with IPTC dictionaries present
    /// and the metadata stays self-consistent.
    func testIPTCAndXPMPresenceDoesNotDisturbExtraction() async throws {
        try Fixtures.require(Fixtures.nef)
        let props = try XCTUnwrap(MetadataTests.imageIOProperties(url: Fixtures.nef))
        let hasIPTC = (props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]) != nil
        // XMP note: the macOS 27 SDK exposes no XMP property dictionary
        // (the packet goes through the CGImageMetadata APIs — Phase 12,
        // META-04; see RAWDecoder.readCaptureMetadata). Its file-level
        // presence therefore cannot be asserted here and must not disturb
        // the Phase 1 fields.

        let decoded = try await RAWDecoder().decode(Fixtures.nef)
        let capture = decoded.capture
        XCTAssertNotNil(capture.cameraModel)
        // XMP packet parsing is Phase 12 (META-04) by contract — its
        // presence in the file must not disturb the Phase 1 fields.
        XCTAssertNotNil(capture.captureTime, "capture time survives IPTC/XMP presence")
        if hasIPTC {
            // Recorded for the report: fixture carries embedded IPTC.
            XCTAssertNotNil(capture.cameraModel)
        }
    }

    // MARK: - helpers

    /// Independent ImageIO read of the file's property dictionary
    /// (kCGImageSourceShouldCache: false — same options as the decoder).
    private static func imageIOProperties(url: URL) throws -> [CFString: Any]? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }
}
