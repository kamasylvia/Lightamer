import Foundation

/// Capture metadata (D-23a, RAW-06) — EXIF/IPTC/XMP-derived shooting facts.
///
/// `public` + `Codable` + `Sendable`: the InspectorState display contract and
/// the Phase 2 sidecar schema. All fields optional — files legitimately lack
/// any subset (synthetic test images, older bodies without lens reports, …).
public struct CaptureMetadata: Codable, Sendable {

    /// TIFF `Make` (e.g. "Canon").
    public var cameraMake: String?

    /// TIFF `Model` (e.g. "Canon EOS R5").
    public var cameraModel: String?

    /// Lens model string — sourced from the EXIF **auxiliary** dictionary
    /// (`kCGImagePropertyExifAuxLensModel`, NOT the main EXIF dict; quality
    /// varies per vendor — Phase 4 lensfun picks a profile from this).
    public var lensModel: String?

    /// Focal length in mm.
    public var focalLength: Double?

    /// F-number (aperture).
    public var aperture: Double?

    /// Exposure time in seconds (1/200 → 0.005).
    public var shutterSpeed: Double?

    /// ISO speed rating.
    public var iso: Int?

    /// `DateTimeOriginal` (EXIF), with an IPTC DateCreated fallback.
    public var captureTime: Date?

    /// GPS coordinates, when embedded.
    public var gps: GPSInfo?

    /// EXIF orientation, 1...8 (fed to `CIRAWFilter.orientation` upstream).
    public var orientation: Int?

    /// Pixel width of the decoded frame.
    public var width: Int?

    /// Pixel height of the decoded frame.
    public var height: Int?

    /// Dots per inch (Y axis), when reported.
    public var dpi: Double?

    // ── Plan 08-2 T1: the six yiyin watermark fields (additive Optional —
    // Codable decodes old sidecars/records that lack the keys; the
    // RAWDecoder ImageIO walk that FILLS them landed in Plan 08-3 T2 — the
    // 08-CONTEXT 继承定案 split: struct declaration first, reader later).
    // Types mirror the ImageIO property types the walk reads.

    /// EXIF `FocalLengthIn35mmFilm` (等效焦距, mm).
    public var focalLength35mm: Double?

    /// EXIF `ExposureProgram` enum 0...8 (0 undefined, 1 manual, 2 program
    /// AE, 3 aperture-priority, 4 shutter-priority, 5 creative, 6 action,
    /// 7 portrait, 8 landscape).
    public var exposureProgram: Int?

    /// EXIF `ExposureBias` (曝光补偿, EV).
    public var exposureCompensation: Double?

    /// EXIF `MeteringMode` enum 0...6 (0 unknown, 1 average,
    /// 2 center-weighted average, 3 spot, 4 multi-spot, 5 pattern,
    /// 6 partial).
    public var meteringMode: Int?

    /// EXIF `WhiteBalance` enum (0 auto, 1 manual).
    public var whiteBalance: Int?

    /// Lens make string — sourced from the EXIF **auxiliary** dictionary
    /// (`kCGImagePropertyExifAuxLensMake`, the `lensModel` twin).
    public var lensMake: String?

    /// GPS triplet (WGS84 decimal degrees / meters).
    public struct GPSInfo: Codable, Sendable {
        public var latitude: Double?
        public var longitude: Double?
        public var altitude: Double?

        public init(latitude: Double? = nil, longitude: Double? = nil, altitude: Double? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
        }
    }

    public init(
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        focalLength: Double? = nil,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        iso: Int? = nil,
        captureTime: Date? = nil,
        gps: GPSInfo? = nil,
        orientation: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        dpi: Double? = nil,
        focalLength35mm: Double? = nil,
        exposureProgram: Int? = nil,
        exposureCompensation: Double? = nil,
        meteringMode: Int? = nil,
        whiteBalance: Int? = nil,
        lensMake: String? = nil
    ) {
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.focalLength = focalLength
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.captureTime = captureTime
        self.gps = gps
        self.orientation = orientation
        self.width = width
        self.height = height
        self.dpi = dpi
        self.focalLength35mm = focalLength35mm
        self.exposureProgram = exposureProgram
        self.exposureCompensation = exposureCompensation
        self.meteringMode = meteringMode
        self.whiteBalance = whiteBalance
        self.lensMake = lensMake
    }
}
