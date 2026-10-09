import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// BandStreamer (Plan 08-1 T3; RESEARCH §6) — the ROW-BAND streaming shape of
// the merge pass + the float32 TIFF product writer (the EXP-01 write face).
//
// TilingPlan reuse boundary (research §6): the bands are a DEGENERATE CASE
// of the pure tile geometry — tile height = band height, full-width tiles,
// zero overlap. `bands(...)` mints `TilingPlan.Tile` rects directly; NO
// in-pipe tile driver is involved (the merge never walks PixelPipe).
//
// EXECUTION-SHAPE NOTE (D-08-1, recorded): CIRAW/ImageIO cannot decode a
// RAW frame BY ROWS — the research §6 "decode per band" sketch is realizable
// only as "decode the frame ONCE per pass, consume it BAND BY BAND, release
// after the last band". The streaming guarantees that survive: the resident
// set is the accumulator planes (independent of N) plus ONE transient
// full-frame decode render (~1.63 GB at 100 MP) — never N full frames
// (the 7.3–9.8 GB full-residency denial stands).
//
// The float TIFF write: ImageIO finalizes a TIFF in one shot (no scanline
// append API), so the writer builds the CGImage OVER the finished plane
// (zero copy through CGDataProvider) and promotes `X.tmp-<uuid>` → `X`
// atomically in the same directory (the L009 posture). The plane is
// linear-Rec2020 TAGGED so the product round-trips the working space
// through `RAWDecoder.decode()` — since M4-1 the native float-faithful
// raster leg (the ①′ linear-ICC float32 → sceneLinear rule routes the
// product through the matrix branch; pre-M4-1 this was the RAW-03
// bpp=32-faithful `decodeRaster` arm).
// ─────────────────────────────────────────────────────────────────────────────

public enum BandStreamer {

    /// The band height (research §6's 256-row consumption unit).
    public static let defaultBandHeight = 256

    // MARK: - Band geometry (the TilingPlan degenerate case)

    /// Full-width row bands covering `0..<height` (edge band shrinks).
    /// Zero bands for a degenerate height/width. The `width` rides the
    /// Tile record for the FULL-WIDTH bands convention (the 08-1
    /// acceptance note: the degenerate `width: 1` stub contradicted the
    /// full-width contract — consumers only read y/height today, but the
    /// geometry now says what it means).
    public static func bands(
        height: Int, width: Int, bandHeight: Int = BandStreamer.defaultBandHeight
    ) -> [TilingPlan.Tile] {
        guard height > 0, width > 0, bandHeight > 0 else { return [] }
        var result: [TilingPlan.Tile] = []
        var y = 0
        while y < height {
            let band = min(bandHeight, height - y)
            result.append(
                TilingPlan.Tile(x: 0, y: y, width: width, height: band))
            y += band
        }
        return result
    }

    /// Extract one band's RGBA float32 rows from a full-frame plane.
    /// - Parameters:
    ///   - plane: the full-frame RGBA float32 buffer (row-major).
    ///   - bytesPerRow: the plane's row stride in bytes.
    public static func bandPixels(
        fromPlane plane: UnsafeRawBufferPointer, bytesPerRow: Int,
        width: Int, band: TilingPlan.Tile
    ) -> [Float] {
        let pixelCount = width * band.height
        var result = [Float](repeating: 0, count: pixelCount * 4)
        result.withUnsafeMutableBytes { destination in
            for row in 0..<band.height {
                let sourceRow = plane.baseAddress!
                    .advanced(by: (band.y + row) * bytesPerRow)
                let destinationRow = destination.baseAddress!
                    .advanced(by: row * width * 16)
                destinationRow.copyMemory(
                    from: sourceRow, byteCount: width * 16)
            }
        }
        return result
    }

    /// The ALIGNED band extraction: output pixel (x, y) samples the source
    /// plane at (x − dx, y − dy) — the MTB shift convention
    /// (`cmp(x,y) == ref(x−dx, y−dy)`). Samples outside the source frame
    /// become NaN (the accumulator skips them — the bracket's edge strips
    /// outside the alignment overlap carry no contribution).
    public static func shiftedBandPixels(
        fromPlane plane: UnsafeRawBufferPointer, bytesPerRow: Int,
        width: Int, height: Int, band: TilingPlan.Tile, dx: Int, dy: Int
    ) -> [Float] {
        let nan = Float.nan
        var result = [Float](repeating: nan, count: width * band.height * 4)
        result.withUnsafeMutableBytes { destination in
            let destinationFloats = destination.bindMemory(to: Float.self)
            for row in 0..<band.height {
                let outputY = band.y + row
                let sourceY = outputY - dy
                guard sourceY >= 0, sourceY < height else { continue }
                let sourceRow = plane.baseAddress!
                    .advanced(by: sourceY * bytesPerRow)
                    .bindMemory(to: Float.self, capacity: width * 4)
                for x in 0..<width {
                    let sourceX = x - dx
                    guard sourceX >= 0, sourceX < width else { continue }
                    let sourceBase = sourceX * 4
                    let destinationBase = (row * width + x) * 4
                    destinationFloats[destinationBase] = sourceRow[sourceBase]
                    destinationFloats[destinationBase + 1] = sourceRow[sourceBase + 1]
                    destinationFloats[destinationBase + 2] = sourceRow[sourceBase + 2]
                    destinationFloats[destinationBase + 3] = 1
                }
            }
        }
        return result
    }

    /// The resident-set accounting face (the memory-constant assertion):
    /// the accumulator planes are EXACTLY this many bytes, independent of
    /// the source count N.
    ///
    /// - deGhost OFF: Σw (3ch) + Σwp (3ch) + weight map (1ch) = 28 B/px.
    /// - deGhost ON: the phase-1 pair is FINALIZED into L̂0 (3ch) and its
    ///   accumulator RELEASED before phase 2 mints its own pair — the peak
    ///   is L̂0 (3ch) + the phase-2 pair (6ch) + weight map (1ch) + the
    ///   ghost union (1 B) = 41 B/px (D-08-1: the ×1.5 ghost pass overhead,
    ///   the full-residency denial stands).
    public static func accumulatorBytes(width: Int, height: Int, deGhost: Bool)
        -> Int
    {
        let bytesPerPixel: Int = deGhost
            ? (3 + 6 + 1) * MemoryLayout<Float>.size + 1
            : (3 + 3 + 1) * MemoryLayout<Float>.size
        return width * height * bytesPerPixel
    }

    // MARK: - The float32 TIFF product writer (EXP-01 face)

    /// Write the merged plane as a 32-bit float RGBA TIFF, atomically
    /// promoted (tmp → rename in the SAME directory — L009).
    ///
    /// - Parameters:
    ///   - destination: the FINAL product URL (`<base>_hdr.tif`).
    ///   - plane: the full-frame RGBA float32 (row-major, tight rows).
    /// - Throws: `AppError.encodeFailed` on any ImageIO/IO failure (the
    ///   retry-able hard-failure typing).
    public static func writeFloatTIFF(
        _ plane: [Float], width: Int, height: Int, to destination: URL
    ) throws {
        guard plane.count == width * height * 4 else {
            throw AppError.encodeFailed(
                "float TIFF plane size mismatch: \(plane.count) floats for "
                    + "\(width)×\(height)")
        }
        let byteCount = width * height * 16
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(
                destination.lastPathComponent + ".tmp-\(UUID().uuidString)",
                isDirectory: false)

        // The CGImage rides the SAME bitmap-info shape ImageIOEncodeCore
        // uses for the float32 tier (premultiplied-last RGBA, little-endian
        // float components) but in the WORKING space — the product is a
        // linear Rec2020 document, tagged as such (FOUND-02).
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let provider = CGDataProvider(
            data: plane.withUnsafeBufferPointer { Data(buffer: $0) } as CFData)
        else {
            throw AppError.encodeFailed("CGDataProvider failed for the merge plane")
        }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 32,
            bitsPerPixel: 128,
            bytesPerRow: width * 16,
            space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
        else {
            throw AppError.encodeFailed(
                "CGImage construction failed for the \(width)×\(height) merge plane")
        }

        let properties: [CFString: Any] = [
            // Compression 1 = None — the only lossless-safe shape for
            // float32 sample data through this host encoder.
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFCompression: 1,
                kCGImagePropertyTIFFSoftware: "Lightamer HDR merge",
            ] as [CFString: Any],
        ]

        // Finalize to the same-directory temporary, then promote (the
        // SidecarStore posture — never a cross-volume rename, L009).
        guard let destinationRef = CGImageDestinationCreateWithURL(
            temporary as CFURL, UTType.tiff.identifier as CFString, 1, nil)
        else {
            throw AppError.encodeFailed(
                "CGImageDestinationCreateWithURL failed for \(temporary.lastPathComponent)")
        }
        CGImageDestinationAddImage(destinationRef, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destinationRef) else {
            try? FileManager.default.removeItem(at: temporary)
            throw AppError.encodeFailed(
                "CGImageDestinationFinalize failed for \(temporary.lastPathComponent)")
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                // The collision-increment contract makes this unreachable
                // (the namer guarantees a free name); defend the red line
                // anyway — never overwrite (D-08-CONTEXT-11).
                try? FileManager.default.removeItem(at: temporary)
                throw AppError.encodeFailed(
                    "refusing to overwrite existing \(destination.lastPathComponent)")
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch let error as AppError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw AppError.encodeFailed(
                "promote failed for \(destination.lastPathComponent): \(error)")
        }
    }
}
