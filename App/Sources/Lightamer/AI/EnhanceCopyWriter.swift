import Foundation
import ImageIO
import LightamerCore
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// EnhanceCopyWriter (Plan M2-10-06 KD-3) — the AI-enhanced copy's disk face:
// exclusive name reservation, the 16-bit-faithful container rule, EXIF
// inheritance, and the ImageIO encode. Lumen `reserve_copy`
// (ai_dialog.py:17-28) + `engine.export_image` provenance lineage, MIT
// read-only (structure ported, never code).
//
// CONTAINER RULE (KD-3, morning-reviewable — DECISIONS pins the wording):
//   • a 16-bit PNG original stays PNG (16-bit) — the same-format leg;
//   • EVERYTHING ELSE lands TIFF 16-bit: RAW containers are unwritable,
//     and rewriting an 8-bit JPEG/WebP/HEIF container would throw away the
//     enhanced result's bit depth (M2AI-09's「16-bit」goal) — so「随原格式」
//     narrows to「the same format when it losslessly carries 16-bit, else
//     TIFF 16」. A 16-bit TIFF also lands TIFF (the default leg).
//   • an UNOPENABLE source (synthetic/test bytes, exotic RAW) rides the
//     default TIFF leg with empty inherited EXIF — the RAW-equivalent
//     behavior, testable without real RAW fixtures (the synthetic-bytes
//     ruling).
//
// RESERVATION (KD-3): `{stem}-增强` / `{stem}-去杂色` then `-N` (N ≥ 2,
// Lumen's exact shape: index 1 carries NO number), N 1...9999, won by
// POSIX `open(O_CREAT|O_EXCL)` — `Data.write(options:.atomic)` has no
// O_EXCL. On any write failure the reserved placeholder is removed (the
// Lumen finally-unlink parity) so a cancelled run never leaves debris.
//
// EXIF INHERITANCE: the original's exif/tiff/iptc dictionaries merge into
// the destination properties; the TIFF orientation is forced to 1 (the
// render contract: the frame arrives display-upright — orientation is
// BAKED into the pixels); GPS follows the original (the personal-tool
// semantics, DECISIONS 签注).
// ─────────────────────────────────────────────────────────────────────────────

/// The typed copy-writer failures (the dialog maps these to honest copy
/// text).
enum EnhanceCopyError: Error, Equatable {
    /// All 9999 reserved names were taken (Lumen 「同名副本过多」).
    case reserveExhausted(directory: String)
    /// The POSIX reservation hit a non-EEXIST error (permissions, ...).
    case reserveFailed(path: String, errno: Int32)
    /// The output encode/destination failed.
    case encodeFailed(String)
}

enum EnhanceCopyWriter {

    /// The output container (the KD-3 rule above).
    struct Container: Equatable {
        let uti: String
        let pathExtension: String
        static let tiff16 = Container(uti: "public.tiff", pathExtension: "tif")
        static let png16 = Container(uti: "public.png", pathExtension: "png")
    }

    /// The copy-name suffix per operation (the D-3 spelling).
    static func nameSuffix(for operation: AIProvenanceOperation) -> String {
        switch operation {
        case .upscale: return "增强"
        case .denoise: return "去杂色"
        }
    }

    // MARK: - Container rule

    /// The output container for the ORIGINAL file: PNG16 only for 16-bit
    /// PNG sources; TIFF16 otherwise.
    static func outputContainer(forOriginal originalURL: URL) -> Container {
        guard let source = CGImageSourceCreateWithURL(
            originalURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let uti = CGImageSourceGetType(source) as String?,
            UTType(uti)?.conforms(to: .png) == true,
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
                as? [CFString: Any],
            let depth = properties[kCGImagePropertyDepth] as? Int,
            depth > 8
        else { return .tiff16 }
        return .png16
    }

    // MARK: - Reservation (O_EXCL)

    /// Reserve the copy's name under `directory` (the project `Media/`
    /// directory): `{stem}-{suffix}`, then `{stem}-{suffix}-N` for N ≥ 2,
    /// up to 9999. The winner is an EMPTY placeholder file — the caller
    /// writes the bytes and MUST remove the placeholder on failure.
    static func reserveCopy(
        in directory: URL, sourceStem: String, operation: AIProvenanceOperation,
        container: Container
    ) throws -> URL {
        try reserve(
            in: directory, stem: sourceStem,
            suffix: nameSuffix(for: operation),
            pathExtension: container.pathExtension)
    }

    private static func reserve(
        in directory: URL, stem: String, suffix: String, pathExtension: String
    ) throws -> URL {
        for index in 1...9999 {
            let numbered = index == 1 ? "" : "-\(index)"
            let target = directory.appendingPathComponent(
                "\(stem)-\(suffix)\(numbered).\(pathExtension)")
            let fd = open(target.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if fd >= 0 {
                close(fd)
                return target
            }
            guard errno == EEXIST else {
                throw EnhanceCopyError.reserveFailed(
                    path: target.path, errno: errno)
            }
        }
        throw EnhanceCopyError.reserveExhausted(directory: directory.path)
    }

    // MARK: - Encode

    /// Write the enhanced frame (interleaved RGBA float32, [0,1] domain —
    /// values clamp; the alpha channel is dropped and the pixels are
    /// opaque) as 16-bit into the RESERVED destination, merging the
    /// original's EXIF. On failure the reserved placeholder leaves with
    /// the error (no debris).
    static func writeCopy(
        rgba: [Float], width: Int, height: Int,
        colorSpace: CGColorSpace,
        to destination: URL,
        originalURL: URL?
    ) throws {
        do {
            let image = try makeImage(
                rgba: rgba, width: width, height: height, colorSpace: colorSpace)
            guard let destinationImage = CGImageDestinationCreateWithURL(
                destination as CFURL, outputContainerUTI(destination) as CFString,
                1, nil)
            else {
                throw EnhanceCopyError.encodeFailed(
                    "destination create failed: \(destination.path)")
            }
            CGImageDestinationAddImage(
                destinationImage, image,
                inheritedProperties(of: originalURL) as CFDictionary)
            guard CGImageDestinationFinalize(destinationImage) else {
                throw EnhanceCopyError.encodeFailed(
                    "finalize failed: \(destination.path)")
            }
        } catch let error as EnhanceCopyError {
            try? FileManager.default.removeItem(at: destination)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw EnhanceCopyError.encodeFailed("\(error)")
        }
    }

    /// The destination UTI from its own extension (the reservation chose
    /// it: tif → TIFF, png → PNG).
    private static func outputContainerUTI(_ destination: URL) -> String {
        destination.pathExtension.lowercased() == "png"
            ? "public.png" : "public.tiff"
    }

    /// The 16-bit CGImage: float RGBA → clamped uint16 (opaque alpha).
    static func makeImage(
        rgba: [Float], width: Int, height: Int, colorSpace: CGColorSpace
    ) throws -> CGImage {
        guard width >= 1, height >= 1, rgba.count == width * height * 4 else {
            throw EnhanceCopyError.encodeFailed(
                "frame shape \(rgba.count) does not match \(width)×\(height)×4")
        }
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        for index in 0..<width * height {
            let source = index * 4
            // Clamp to [0,1] — a 16-bit integer container cannot carry the
            // scene-referred >1.0 tail (DECISIONS: the tone-mapping
            // responsibility stays with the render provider).
            for channel in 0..<4 {
                let value = rgba[source + channel]
                let clamped = min(max(value, 0), 1)
                // clamped ∈ [0,1] → the scaled integer ∈ [0, 65535].
                pixels[source + channel] = UInt16(
                    Int((clamped * 65535.0).rounded()))
            }
        }
        let pixelData = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: pixelData as CFData) else {
            throw EnhanceCopyError.encodeFailed("provider create failed")
        }
        // 16bpc RGBA, little-endian 16-bit words, premultiplied-last (the
        // alpha is opaque so premultiplication is the identity).
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGBitmapInfo.byteOrder16Little.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = CGImage(
            width: width, height: height,
            bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 8,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
        else {
            throw EnhanceCopyError.encodeFailed("CGImage create failed")
        }
        return image
    }

    /// The EXIF inheritance (KD-3): exif/tiff/iptc dictionaries merge;
    /// the TIFF orientation forces 1 (pixels are display-upright); GPS
    /// follows the original. An unopenable source inherits nothing (the
    /// TIFF-default leg's honest face).
    static func inheritedProperties(of originalURL: URL?) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]
        guard let originalURL,
              let source = CGImageSourceCreateWithURL(
                originalURL as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
                as? [CFString: Any]
        else { return properties }
        if let exif = sourceProperties[kCGImagePropertyExifDictionary] {
            properties[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = sourceProperties[kCGImagePropertyTIFFDictionary]
            as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        if let iptc = sourceProperties[kCGImagePropertyIPTCDictionary] {
            properties[kCGImagePropertyIPTCDictionary] = iptc
        }
        if let gps = sourceProperties[kCGImagePropertyGPSDictionary] {
            properties[kCGImagePropertyGPSDictionary] = gps
        }
        return properties
    }
}
