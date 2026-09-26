import CoreGraphics
import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// The five native CGImageDestination encoders (Plan 11-02 T3).
//
// Shared pipeline per format: quantized plane → CGImage (built IN the target
// color space — the conversion and the ICC embed are the same source object,
// RESEARCH §1.2) → AddImage properties (quality / compression / DPI / EXIF
// round-trip / TIFF Software signature) → in-memory finalize → atomic write.
//
// Per-format host facts (probed 2026-09-26, pinned by the goldens):
// - EXIF rides the PROPERTIES path (`kCGImagePropertyExifDictionary`), the
//   only path that survives on this host — `kCGImageDestinationMetadata`
//   serializes nothing (whole-replace AND merge), and XMP packets do not
//   serialize through any ImageIO write path here.
// - HEIC/AVIF deep color consumes the 16bpc plane; the host encoder
//   requantizes internally (HEIC ten → depth 10 verified; AVIF twelve
//   requests land at 10 — R1 documented ceiling, DECISIONS).
// - No alignment constraints: odd dimensions (33×17 probed) encode and
//   decode back at the exact requested size.
// ─────────────────────────────────────────────────────────────────────────────

/// Shared encode machinery for the CGImageDestination family.
struct ImageIOEncodeCore {

    /// Build the CGImage in the TARGET color space from the packed plane.
    /// Premultiplied-last RGBA at every tier (our planes carry opaque alpha
    /// = 1.0, so premultiplication is a no-op); host-endian sample orders
    /// are declared with the explicit byte-order flags.
    static func makeCGImage(from plane: ExportQuantizedPlane, colorSpace: CGColorSpace) throws -> CGImage {
        try plane.validate()
        guard let provider = CGDataProvider(data: plane.data as CFData) else {
            throw AppError.encodeFailed("CGDataProvider failed for a \(plane.data.count)B plane")
        }
        let alpha = CGImageAlphaInfo.premultipliedLast.rawValue
        let bitmapInfo: CGBitmapInfo
        switch plane.layout {
        case .rgba8:
            bitmapInfo = CGBitmapInfo(rawValue: alpha)
        case .rgba16:
            bitmapInfo = CGBitmapInfo(rawValue: alpha | CGBitmapInfo.byteOrder16Little.rawValue)
        case .float32:
            bitmapInfo = CGBitmapInfo(rawValue:
                alpha | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        }
        guard let image = CGImage(
            width: plane.width,
            height: plane.height,
            bitsPerComponent: plane.layout.bitsPerComponent,
            bitsPerPixel: plane.layout.bytesPerPixel * 8,
            bytesPerRow: plane.rowBytes,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
        else {
            throw AppError.encodeFailed(
                "CGImage construction failed for \(plane.width)×\(plane.height) \(plane.layout.rawValue)")
        }
        return image
    }

    /// The EXIF round-trip (properties path): read the source's EXIF
    /// dictionary and hand it back for the AddImage properties. The source's
    /// dictionary REPLACES any default — no merge ambiguity on either side.
    static func sourceEXIF(from sourceURL: URL?) -> [CFString: Any]? {
        guard let sourceURL else { return nil }
        let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary)
        guard let source,
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [
                kCGImageSourceShouldCache: false,
            ] as CFDictionary) as? [CFString: Any],
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        else { return nil }
        return exif
    }

    /// Encode → finalize → atomic write (Foundation `.atomic`: the
    /// half-artifact always lives in the same-directory tmp until the
    /// rename — L009 / D-11-CONTEXT-8).
    static func writeAtomically(_ image: CGImage, properties: [CFString: Any], uti: String, to destination: URL) throws {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, uti as CFString, 1, nil) else {
            throw AppError.encodeFailed("CGImageDestinationCreateWithData failed for \(uti)")
        }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw AppError.encodeFailed("CGImageDestinationFinalize failed for \(uti)")
        }
        do {
            try (data as Data).write(to: destination, options: .atomic)
        } catch {
            throw AppError.encodeFailed("atomic write failed for \(destination.lastPathComponent): \(error)")
        }
    }
}

// MARK: - JPEG

struct JPEGEncoder: ExportEncoder {

    func encode(_ request: ExportEncodeRequest) throws -> URL {
        let image = try ImageIOEncodeCore.makeCGImage(from: request.plane, colorSpace: request.colorSpace)
        var properties: [CFString: Any] = [:]
        // Guarded at the registry, but a wrong-tier plane here would bend
        // colors — JPEG is an 8-bit display-domain container.
        guard request.plane.layout == .rgba8 else {
            throw AppError.invalidParameter("jpeg needs an rgba8 plane")
        }
        properties[kCGImageDestinationLossyCompressionQuality] = request.spec.quality ?? 0.9
        if let exif = ImageIOEncodeCore.sourceEXIF(from: request.sourceURL) {
            properties[kCGImagePropertyExifDictionary] = exif
        }
        if let dpi = request.dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        try ImageIOEncodeCore.writeAtomically(image, properties: properties, uti: request.spec.utType, to: request.destination)
        return request.destination
    }
}

// MARK: - PNG

struct PNGEncoder: ExportEncoder {

    func encode(_ request: ExportEncodeRequest) throws -> URL {
        let image = try ImageIOEncodeCore.makeCGImage(from: request.plane, colorSpace: request.colorSpace)
        var properties: [CFString: Any] = [:]
        // PNG is lossless-deflate with NO quality knob; the bit depth is the
        // SOURCE CGImage's bitsPerComponent (8 ↔ sixteen per the spec —
        // guarded at the registry).
        switch request.spec {
        case .png(.eight):
            guard request.plane.layout == .rgba8 else {
                throw AppError.invalidParameter("png 8-bit needs an rgba8 plane")
            }
        case .png(.sixteen):
            guard request.plane.layout == .rgba16 else {
                throw AppError.invalidParameter("png 16-bit needs an rgba16 plane")
            }
        default:
            throw AppError.invalidParameter("PNGEncoder dispatched a non-png spec")
        }
        if let exif = ImageIOEncodeCore.sourceEXIF(from: request.sourceURL) {
            properties[kCGImagePropertyExifDictionary] = exif
        }
        if let dpi = request.dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        try ImageIOEncodeCore.writeAtomically(image, properties: properties, uti: request.spec.utType, to: request.destination)
        return request.destination
    }
}

// MARK: - TIFF

struct TIFFEncoder: ExportEncoder {

    func encode(_ request: ExportEncodeRequest) throws -> URL {
        let image = try ImageIOEncodeCore.makeCGImage(from: request.plane, colorSpace: request.colorSpace)
        guard case .tiff(_, let compression) = request.spec else {
            throw AppError.invalidParameter("TIFFEncoder dispatched a non-tiff spec")
        }
        var properties: [CFString: Any] = [:]
        // Compression 1 = None / 5 = LZW / 8 = AdobeDeflate(ZIP). 7 =
        // JPEG-in-TIFF deliberately absent (a lossy domain inside a linear
        // container is ambiguous — RESEARCH §1.2); all three shipped values
        // are lossless.
        let compressionValue: Int
        switch compression {
        case .none: compressionValue = 1
        case .lzw: compressionValue = 5
        case .zip: compressionValue = 8
        }
        properties[kCGImagePropertyTIFFDictionary] = [
            kCGImagePropertyTIFFCompression: compressionValue,
        ] as [CFString: Any]
        // The one working carrier for the editor signature on this host
        // (EXIF Software has no public ImageIO property constant; XMP does
        // not serialize — DECISIONS).
        if let signature = request.editorSignature {
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFCompression: compressionValue,
                kCGImagePropertyTIFFSoftware: signature,
            ] as [CFString: Any]
        }
        if let exif = ImageIOEncodeCore.sourceEXIF(from: request.sourceURL) {
            properties[kCGImagePropertyExifDictionary] = exif
        }
        if let dpi = request.dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        try ImageIOEncodeCore.writeAtomically(image, properties: properties, uti: request.spec.utType, to: request.destination)
        return request.destination
    }
}

// MARK: - HEIC

struct HEICEncoder: ExportEncoder {

    func encode(_ request: ExportEncodeRequest) throws -> URL {
        let image = try ImageIOEncodeCore.makeCGImage(from: request.plane, colorSpace: request.colorSpace)
        guard case .heic(_, let bitDepth) = request.spec else {
            throw AppError.invalidParameter("HEICEncoder dispatched a non-heic spec")
        }
        switch (bitDepth, request.plane.layout) {
        case (.eight, .rgba8), (.ten, .rgba16):
            break // the legal pairings
        default:
            throw AppError.invalidParameter(
                "heic \(bitDepth) needs the matched plane tier (got \(request.plane.layout.rawValue))")
        }
        var properties: [CFString: Any] = [:]
        // The 16bpc source IS the 10-bit path (probed: depth reads 10 with
        // no base-pixel-format request — the encoder requantizes).
        properties[kCGImageDestinationLossyCompressionQuality] = request.spec.quality ?? 0.9
        if let exif = ImageIOEncodeCore.sourceEXIF(from: request.sourceURL) {
            properties[kCGImagePropertyExifDictionary] = exif
        }
        if let dpi = request.dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        try ImageIOEncodeCore.writeAtomically(image, properties: properties, uti: request.spec.utType, to: request.destination)
        return request.destination
    }
}

// MARK: - AVIF

/// D-11-CONTEXT-1's protocol SEAM: v1 = the native ImageIO encoder only. If
/// a future host/requirement needs true 12-bit, a libavif-backed second
/// conformer slots in behind this type without touching the registry face.
struct AVIFEncoder: ExportEncoder {

    func encode(_ request: ExportEncodeRequest) throws -> URL {
        let image = try ImageIOEncodeCore.makeCGImage(from: request.plane, colorSpace: request.colorSpace)
        guard case .avif(_, let bitDepth) = request.spec else {
            throw AppError.invalidParameter("AVIFEncoder dispatched a non-avif spec")
        }
        switch (bitDepth, request.plane.layout) {
        case (.eight, .rgba8), (.ten, .rgba16), (.twelve, .rgba16):
            break
        default:
            throw AppError.invalidParameter(
                "avif \(bitDepth) needs the matched plane tier (got \(request.plane.layout.rawValue))")
        }
        // R1 DOWNGRADE (documented, not silent): a .twelve request encodes
        // from the same 16bpc plane as .ten and the HOST ENCODER lands it at
        // 10-bit (probed — the base-pixel-format request does not lift the
        // ceiling). The file is written at 10-bit deep color; the ceiling
        // and the libavif seam are recorded in 11-02-DECISIONS.
        var properties: [CFString: Any] = [:]
        properties[kCGImageDestinationLossyCompressionQuality] = request.spec.quality ?? 0.9
        if let exif = ImageIOEncodeCore.sourceEXIF(from: request.sourceURL) {
            properties[kCGImagePropertyExifDictionary] = exif
        }
        if let dpi = request.dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        try ImageIOEncodeCore.writeAtomically(image, properties: properties, uti: request.spec.utType, to: request.destination)
        return request.destination
    }
}
