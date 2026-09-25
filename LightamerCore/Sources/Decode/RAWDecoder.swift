import CoreImage
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// The decode layer of the pixelpipe (D-21, ONE-WAY contract) — a `public`
/// actor in LightamerCore wrapping `CIRAWFilter` with a **unified RAW +
/// non-RAW entry** (D-24) and RAW 9 opt-in + RAW 8 auto-fallback (D-22).
///
/// Concurrency shape (D-33/D-34, RESEARCH Open Question #1): actor over
/// `@unchecked Sendable` class — Swift 6 strict-concurrency favors it, decode
/// latency dominates over actor hops. `decode(_:)` is actor-isolated async, so
/// it always runs off-MainActor; the app's `EditorState` hops back for UI
/// updates. Each decode instantiates a fresh `CIRAWFilter` (`CIFilter` is not
/// `Sendable` and is never stored across calls — `internal`, never exposed).
///
/// Errors are always typed `AppError` cases (D-25) — raw `CIFilter` failures
/// never escape. The decode is wrapped in `os.signpost` intervals (D-31) and
/// honours `Task.cancel()` (D-34) at every await/checkpoint boundary.
public actor RAWDecoder {

    /// Signpost subsystem shared with the app-side decode interval (D-31).
    private static let signposter = OSSignposter(
        subsystem: "com.kamasylvia.lightamer",
        category: "decode"
    )

    public init() {}

    // MARK: - Unified entry (D-24)

    /// Decode any supported image: RAW UTIs route through `CIRAWFilter`,
    /// raster UTIs (JPEG/HEIC/PNG/WebP/TIFF/PSD-flat, RAW-04) through
    /// `CGImageSource`. Callers see one entry point; the branching is
    /// internal.
    public func decode(_ url: URL) async throws -> DecodedImage {
        let interval = Self.signposter.beginInterval(
            "decode", id: Self.signposter.makeSignpostID()
        )
        defer { Self.signposter.endInterval("decode", interval) }

        try Task.checkCancellation() // D-34: honour cancellation on both paths

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw AppError.fileUnreadable(url.path)
        }

        let uti = Self.utiForFile(at: url)
        if Self.isRAWUTI(uti) {
            return try await decodeRAW(url)
        } else {
            return try decodeRaster(url, uti: uti)
        }
    }

    // MARK: - RAW path (CIRAWFilter, D-21/D-22)

    /// CIRAW decode with RAW 9 opt-in (D-22, RAW-05, L001):
    /// 1. probe `supportedDecoderVersions` on a scratch filter (the key is
    ///    read-only — setting it raises; RESEARCH §2 gotcha),
    /// 2. under `#available(macOS 27, *)` request `.version9` when the file
    ///    reports it, else silently fall back to `.version8`,
    /// 3. read the three D-23 metadata classes off the real filter.
    internal func decodeRAW(_ url: URL) async throws -> DecodedImage {
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            // ── probe: which decoder versions does THIS file support? ──
            let supported = try await supportedDecoderVersions(for: url)
            guard !Task.isCancelled else { throw AppError.cancelled }

            var requested = CIRAWDecoderVersion.version8
            var used = DecodedImage.DecoderVersion.v8
            if #available(macOS 27, *), supported.contains(CIRAWDecoderVersion.version9) {
                requested = CIRAWDecoderVersion.version9
                used = .v9
            }

            // ── the real filter ──
            guard let filter = CIRAWFilter(imageURL: url) else {
                throw AppError.decodeFailed("CIRAWFilter could not initialize for \(url.lastPathComponent)")
            }
            filter.decoderVersion = requested
            // kCIInputEnableVendorLensCorrectionKey equivalent stays at its
            // default `true` (embedded DNG OpcodeList / vendor opcodes) —
            // manual lens iop is Phase 4.
            // RAW 9 no-op keys (colorNoiseReductionAmount, detailAmount,
            // moireReductionAmount) are intentionally NOT set (WWDC26/305).

            guard let output = filter.outputImage else {
                throw AppError.decodeFailed("CIRAW produced no image for \(url.lastPathComponent) (file may be corrupted or truncated)")
            }
            guard !Task.isCancelled else { throw AppError.cancelled }

            // ── the three metadata classes (D-23) ──
            let tech = Self.rawTechnicalParams(from: filter, url: url)
            let capture = try Self.readCaptureMetadata(url: url)
            let skyMatte = filter.semanticSegmentationSkyMatte // nil unless iPhone ProRAW (L004)

            guard !Task.isCancelled else { throw AppError.cancelled }
            return DecodedImage(
                ciImage: output,
                rawTech: tech,
                capture: capture,
                segmentationSkyMatte: skyMatte,
                decoderVersionUsed: used,
                contentDedupeID: Self.contentDedupeID(for: url)
            )
        } onCancel: {
            // The ObjC CIRAW decode cannot be interrupted synchronously; the
            // `Task.isCancelled` checkpoints above convert the cancelled
            // state into `AppError.cancelled` at the next boundary (D-34).
        }
    }

    /// Probe result cache (RESEARCH §2: two `CIRAWFilter` instantiations per
    /// decode otherwise double the init cost; `supportedDecoderVersions` is
    /// per-file stable). Internal LRU keyed on `(url, mtime)`.
    private struct ProbeKey: Hashable {
        let path: String
        let modification: Double
    }

    private var probeCache: [ProbeKey: [CIRAWDecoderVersion]] = [:]
    private var probeOrder: [ProbeKey] = []
    private static let probeCacheLimit = 16

    private func supportedDecoderVersions(for url: URL) async throws -> [CIRAWDecoderVersion] {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let key = ProbeKey(path: url.path, modification: mtime?.timeIntervalSince1970 ?? 0)
        if let hit = probeCache[key] {
            return hit
        }

        guard let probe = CIRAWFilter(imageURL: url) else {
            throw AppError.unsupportedFile(url.path)
        }
        let versions = probe.supportedDecoderVersions

        probeCache[key] = versions
        probeOrder.append(key)
        while probeOrder.count > Self.probeCacheLimit {
            let evicted = probeOrder.removeFirst()
            probeCache[evicted] = nil
        }
        return versions
    }

    // MARK: - Raster path (CGImageSource, RAW-04)

    /// Non-RAW decode (JPEG/HEIC/PNG/WebP/TIFF/PSD-flat). Multi-image TIFF →
    /// first image.
    ///
    /// **RAW-03 float decision (Plan 02-06-06, host-proven 2026-09-19,
    /// macOS 27.0 / M4):** 32-bit float TIFF and EXR preserve their bit
    /// depth through THIS path — `CGImageSourceCreateImageAtIndex` returns
    /// bpp=32/96 for float32 RGB TIFF and bpp=32/128 for float32 RGBA EXR
    /// (`bitsPerComponent == 32`, colorspace extendedLinearSRGB), and the
    /// pinned extreme values (0.0 / 0.5 / 1.0 / 2.0 / 65504.0) survive into
    /// the float32 pipe input plane bit-near-exactly (`RAW03Tests`). The
    /// research-sketched `CIImage(contentsOf:)` fallback is therefore NOT
    /// adopted: the CGImage leg is float-faithful, and one loader keeps the
    /// decode surface uniform. Re-probe if a future macOS regresses (probe:
    /// decode → `CGImageGetBitsPerComponent == 32` else retry via CI — the
    /// guard would slot right here). Gray test pixels: channel-equal values
    /// survive ANY white-point-preserving linear RGB→RGB conversion, which
    /// is why the fixtures are gray.
    internal func decodeRaster(_ url: URL, uti: String) throws -> DecodedImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw AppError.fileUnreadable(url.path)
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AppError.decodeFailed("No decodable image in \(url.lastPathComponent) (\(uti))")
        }

        let capture = try Self.readCaptureMetadata(url: url)
        return DecodedImage(
            ciImage: CIImage(cgImage: cgImage),
            rawTech: RAWTechnicalParams(), // raster carries no RAW technical state
            capture: capture,
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8, // n/a for raster; field is non-optional
            contentDedupeID: Self.contentDedupeID(for: url)
        )
    }

    // MARK: - UTI routing (D-24, RAW-01/02)

    /// RAW UTIs (RAW-01/02). The identifiers marked "verified" were resolved
    /// on the macOS 27 SDK via `UTType(tag:tagClass:conformingTo:)`; the rest
    /// are historical/alias spellings kept so routing still matches on
    /// systems that declare them. Routing additionally accepts ANY UTI that
    /// conforms to `public.camera-raw-image`, so vendor UTIs missing from
    /// this set still take the RAW path.
    internal static let rawUTIs: Set<String> = [
        // Canon (verified)
        "com.canon.cr2-raw-image",
        "com.canon.cr3-raw-image",
        // Nikon (verified)
        "com.nikon.raw-image",
        // Sony (verified: com.sony.arw-raw-image)
        "com.sony.arw-raw-image",
        "com.sony.raw-image", // alias
        // Fujifilm (verified)
        "com.fuji.raw-image",
        // Panasonic (verified: com.panasonic.rw2-raw-image)
        "com.panasonic.rw2-raw-image",
        "com.panasonic.rw2-image", // alias
        "com.panasonic.raw-image", // alias
        // Olympus / OM System (verified)
        "com.olympus.raw-image",
        // Pentax (verified)
        "com.pentax.raw-image",
        // Leica (verified: com.leica.rwl-raw-image)
        "com.leica.rwl-raw-image",
        "com.leica.raw-image", // alias
        // Hasselblad (verified: com.hasselblad.3fr-raw-image)
        "com.hasselblad.3fr-raw-image",
        "com.hasselblad.3fr", // alias
        // Phase One (verified: com.phaseone.raw-image)
        "com.phaseone.raw-image",
        "com.phaseone.iiq", // alias
        // Adobe DNG (verified: com.adobe.raw-image; DNG "just works" — RAW-02)
        "com.adobe.raw-image",
        "public.adobe-dng", // alias
        // Sigma Foveon (partial per STACK.md; dyn-UTI fallback may miss)
        "com.sigma.x3f",
    ]

    /// Resolve the file's UTI via ImageIO (defaults to `public.data` when
    /// no type can be determined).
    /// GUI-22: the source-file fingerprint for `DecodedImage.contentDedupeID`
    /// — path ⊕ size ⊕ mtime (StableHash). The CI input-plane render memo
    /// dedupes on it so a re-decode of the SAME file reuses the frozen
    /// first render (CIRAW re-execution is speckle-nondeterministic); an
    /// in-place re-save changes mtime → a fresh render. Key domain note:
    /// same class as the pipe cache's §1.3 decode domain — no new staleness.
    private static func contentDedupeID(for url: URL) -> UInt64? {
        // NOTE: hash the path's UTF-8 CONTENT — `withUnsafeBytes(of: &path)`
        // on a String hashes the STRUCT (a heap pointer for long paths:
        // fresh per call, the first cut's drifting key).
        let pathBytes = Array(url.path.utf8)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        var size = attrs?[.size] as? Int ?? -1
        var mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        var h = StableHash.hash(pathBytes)
        h = withUnsafeBytes(of: &size) { StableHash.combine(h, $0) }
        h = withUnsafeBytes(of: &mtime) { StableHash.combine(h, $0) }
        return h
    }

    private static func utiForFile(at url: URL) -> String {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let type = CGImageSourceGetType(source)
        else { return "public.data" }
        return type as String
    }

    /// RAW routing: static set membership OR conformance to
    /// `public.camera-raw-image` (covers UTIs not enumerated above).
    private static func isRAWUTI(_ uti: String) -> Bool {
        if rawUTIs.contains(uti) { return true }
        guard let type = UTType(uti),
              let rawImage = UTType("public.camera-raw-image")
        else { return false }
        return type.conforms(to: rawImage)
    }

    // MARK: - RAW technical params (D-23b)

    /// Read black/white level, baseline exposure and neutral chromaticity.
    /// The macOS 27 SDK exposes no blackLevel/whiteLevel keys on CIRAWFilter;
    /// those come from the ImageIO DNG dictionary when present (DNG, RAW-02,
    /// in the file's native sensor domain — Phase 2 `rawprepare` consumes
    /// them) and fall back to the 0...1 normalized defaults otherwise.
    /// Baseline exposure and neutral chromaticity are queryable CIRAWFilter
    /// properties.
    private static func rawTechnicalParams(from filter: CIRAWFilter, url: URL) -> RAWTechnicalParams {
        var tech = RAWTechnicalParams()

        tech.baselineExposure = Double(filter.baselineExposure)
        let neutral = filter.neutralChromaticity
        tech.neutralChromaticity = CIVector(x: Double(neutral.x), y: Double(neutral.y))

        // DNG dictionary (also populated for some proprietary containers).
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let dng = props[kCGImagePropertyDNGDictionary] as? [CFString: Any]
            if let black = Self.doubleValue(dng?[kCGImagePropertyDNGBlackLevel]) {
                tech.blackLevel = black
            }
            if let white = Self.doubleValue(dng?[kCGImagePropertyDNGWhiteLevel]) {
                tech.whiteLevel = white // native sensor domain (Phase 2 rawprepare input)
            }
            if let baseline = Self.doubleValue(dng?[kCGImagePropertyDNGBaselineExposure]) {
                tech.baselineExposure = baseline
            }
        }
        return tech
    }

    // MARK: - Capture metadata (D-23a, RAW-06)

    /// Walk the ImageIO property dictionaries: TIFF (Make/Model), EXIF
    /// (focal/aperture/shutter/ISO/time/orientation), EXIF-Aux (lens!),
    /// GPS, IPTC (capture-time fallback). XMP is present as a raw `Data`
    /// blob and is reserved for Phase 12 (META-04 standard-metadata
    /// read/write); Phase 1 does not parse it.
    internal static func readCaptureMetadata(url: URL) throws -> CaptureMetadata {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw AppError.fileUnreadable(url.path)
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return CaptureMetadata() // metadata-less file is not an error
        }

        var meta = CaptureMetadata()
        meta.width = (props[kCGImagePropertyPixelWidth] as? Int)
        meta.height = (props[kCGImagePropertyPixelHeight] as? Int)
        if let dpiY = doubleValue(props[kCGImagePropertyDPIHeight]), dpiY > 0 { meta.dpi = dpiY }
        meta.orientation = (props[kCGImagePropertyOrientation] as? Int)

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            meta.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            meta.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }
        // Some containers report the model only in the DNG dict.
        if meta.cameraModel == nil,
           let dng = props[kCGImagePropertyDNGDictionary] as? [CFString: Any] {
            meta.cameraModel = dng[kCGImagePropertyDNGUniqueCameraModel] as? String
        }

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            meta.focalLength = doubleValue(exif[kCGImagePropertyExifFocalLength])
            meta.aperture = doubleValue(exif[kCGImagePropertyExifFNumber])
            meta.shutterSpeed = doubleValue(exif[kCGImagePropertyExifExposureTime])
            if let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int],
               let iso = isoValues.first {
                meta.iso = iso
            } else if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? Int {
                meta.iso = iso
            } else if let iso = doubleValue(exif[kCGImagePropertyExifISOSpeed]) {
                // EXIF 2.3+ keys — modern Canon CR3 reports ISO only here
                // (IMG_4276.CR3: ISOSpeedRatings nil, ISOSpeed 1600), found
                // by the Plan 06 real-RAW metadata tests.
                meta.iso = Int(iso)
            } else if let iso = doubleValue(exif[kCGImagePropertyExifRecommendedExposureIndex]) {
                meta.iso = Int(iso)
            }
            if let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                meta.captureTime = Self.parseEXIFDate(raw)
            }
            // Plan 08-3 T2 (YIYIN-02): the six yiyin EXIF fields — the
            // struct face landed in 08-2 (additive Optional, old-record
            // compatible); this walk fills them. Types mirror the ImageIO
            // property types (numbers may arrive as NSNumber/NSString —
            // `doubleValue` normalizes).
            meta.focalLength35mm = doubleValue(
                exif[kCGImagePropertyExifFocalLenIn35mmFilm])
            if let program = doubleValue(exif[kCGImagePropertyExifExposureProgram]) {
                meta.exposureProgram = Int(program)
            }
            meta.exposureCompensation = doubleValue(
                exif[kCGImagePropertyExifExposureBiasValue])
            if let metering = doubleValue(exif[kCGImagePropertyExifMeteringMode]) {
                meta.meteringMode = Int(metering)
            }
            if let whiteBalance = doubleValue(exif[kCGImagePropertyExifWhiteBalance]) {
                meta.whiteBalance = Int(whiteBalance)
            }
            // The lens MAKE (08-3 T2 — YiyinExifFormat's lens-logo
            // dispatch key). PLAN CORRECTION (D-08-3-T2-1): the plan's
            // "ExifAuxDictionary LensMake" wording followed the LensModel
            // twin, but the SDK exposes LensMake ONLY in the MAIN EXIF
            // dictionary (`kCGImagePropertyExifLensMake`, 10.7+ — EXIF tag
            // 0xA434; the Aux dictionary ships no LensMake constant). Read
            // the main dict, keep the aux dict as a defensive fallback.
            meta.lensMake = exif[kCGImagePropertyExifLensMake] as? String
        }

        // Lens model lives in the EXIF **auxiliary** dictionary (RESEARCH §6).
        if let exifAux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] {
            meta.lensModel = exifAux[kCGImagePropertyExifAuxLensModel] as? String
            if meta.lensMake == nil {
                meta.lensMake = exifAux[kCGImagePropertyExifLensMake] as? String
            }
        }
        if meta.lensModel == nil,
           let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let lens = exif[kCGImagePropertyExifLensModel] as? String {
            meta.lensModel = lens
        }

        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            var info = CaptureMetadata.GPSInfo()
            if var lat = doubleValue(gps[kCGImagePropertyGPSLatitude]) {
                if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
                info.latitude = lat
            }
            if var lon = doubleValue(gps[kCGImagePropertyGPSLongitude]) {
                if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
                info.longitude = lon
            }
            info.altitude = doubleValue(gps[kCGImagePropertyGPSAltitude])
            if info.latitude != nil || info.longitude != nil || info.altitude != nil {
                meta.gps = info
            }
        }

        // IPTC fallback when EXIF lacks DateTimeOriginal.
        if meta.captureTime == nil,
           let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            if let date = iptc[kCGImagePropertyIPTCDateCreated] as? String {
                let time = (iptc[kCGImagePropertyIPTCTimeCreated] as? String) ?? "00:00:00"
                meta.captureTime = Self.parseEXIFDate("\(date) \(time)")
            }
        }

        // XMP: the property dictionary carries no XMP dict on the macOS 27
        // SDK — reading the XMP packet goes through the CGImageMetadata APIs
        // and is reserved for Phase 12 (META-04). EXIF/IPTC above cover the
        // Phase 1 RAW-06 fields.

        return meta
    }

    // MARK: - Parsing helpers

    /// EXIF dates are "yyyy:MM:dd HH:mm:ss" (GMT, no zone marker).
    private static func parseEXIFDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }

    /// Numbers arrive as NSNumber/NSString/CFNumber depending on container.
    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
