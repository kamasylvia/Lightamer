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
    ///   - colorSpace: the embedded color-space TAG (Plan M5-2-02 KD-2).
    ///     The default = the working space (the linear-Rec2020 product tag
    ///     — every pre-M5-2-02 caller is byte-identical); the Mertens leg
    ///     passes sRGB (the display-referred [0,1] product domain — an
    ///     untagged/working-tagged float32 would resolve as scene-linear
    ///     through `RasterColorDescription.resolve` ②/①′ and be domain-
    ///     misjudged on reimport).
    /// - Throws: `AppError.encodeFailed` on any ImageIO/IO failure (the
    ///   retry-able hard-failure typing).
    public static func writeFloatTIFF(
        _ plane: [Float], width: Int, height: Int, to destination: URL,
        colorSpace: CGColorSpace = WorkingSpace.colorSpace
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
        // float components) in the caller's tag space — the Robertson02
        // products are linear-Rec2020 documents (the working space,
        // FOUND-02); the Mertens products are sRGB-tagged display codes
        // (the M5-2-02 KD-2 domain declaration).
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
            space: colorSpace,
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

    // MARK: - The streaming strip-TIFF writer (Plan M5-3-02 KD-9)

    /// The ROW-BAND streaming float32 RGBA TIFF writer — the pano leg's
    /// product face. NOT an ImageIO face: ImageIO finalizes a TIFF in one
    /// shot over a finished plane (the header note above), which would
    /// re-materialize the full canvas the pano memory red line forbids.
    /// The container strategy (the checker-minor-3 ruling: the plan's
    /// "internal delegation to writeFloatTIFF" hedge has no streaming
    /// semantics) = a HAND-WRITTEN classic strip TIFF: a little-endian
    /// header, the RGBA float32 rows streamed strip by strip, and the IFD
    /// (with the ICC payload embedded via `CGColorSpaceCopyICCData`)
    /// appended at `finish()` with the header offset backfilled — the tmp
    /// file then promotes atomically in the destination directory (L009).
    /// The existing `writeFloatTIFF` face stays byte-identical (the pinned
    /// default-colorSpace negative test in MertensRasterDomainTests).
    public final class FloatTIFFWriter {

        private let width: Int
        private let height: Int
        private let colorSpace: CGColorSpace
        private let destination: URL
        private let temporary: URL
        private var handle: FileHandle?
        /// (file offset, byte count, row count) per strip, in write order.
        private var strips: [(offset: UInt32, byteCount: UInt32, rows: Int)] = []
        private var bytesWritten: UInt64 = 8 // the header placeholder
        private var firstStripRows = 0
        private var finished = false

        /// - Parameters:
        ///   - destination: the FINAL product URL (the writer writes a
        ///     same-directory tmp and promotes on `finish()`).
        ///   - colorSpace: the embedded ICC payload (the pano leg passes
        ///     sRGB — the Mertens T2 `productColorSpace` twin).
        public init(
            width: Int, height: Int, destination: URL, colorSpace: CGColorSpace
        ) throws {
            guard width >= 1, height >= 1 else {
                throw AppError.encodeFailed(
                    "float TIFF writer: degenerate \(width)×\(height) canvas")
            }
            self.width = width
            self.height = height
            self.colorSpace = colorSpace
            self.destination = destination
            temporary = destination.deletingLastPathComponent()
                .appendingPathComponent(
                    destination.lastPathComponent + ".tmp-\(UUID().uuidString)",
                    isDirectory: false)
            FileManager.default.createFile(
                atPath: temporary.path, contents: nil)
            let handle = try FileHandle(forWritingTo: temporary)
            // The 8-byte little-endian header placeholder (the IFD offset
            // backfills at finish).
            var header = [UInt8]()
            header.append(contentsOf: [0x49, 0x49]) // "II"
            header.append(contentsOf: Self.u16Little(42))
            header.append(contentsOf: Self.u32Little(8))
            try handle.write(contentsOf: Data(header))
            self.handle = handle
        }

        deinit {
            if !finished {
                try? handle?.close()
                try? FileManager.default.removeItem(at: temporary)
            }
        }

        /// Stream one row band (RGBA float32, tight rows — `rows.count ==
        /// rowCount × width × 4`). Each call lands one strip; every strip
        /// except the last must carry the first strip's row count (the
        /// classic-TIFF RowsPerStrip contract, checked at `finish`).
        /// Chunked at 64 rows (the StagedSet.writePixels posture) so the
        /// transient stays band-bounded.
        public func write(rows: [Float]) throws {
            guard !finished, handle != nil else {
                throw AppError.encodeFailed(
                    "float TIFF writer: write after finish")
            }
            let rowCount = rows.count / max(1, width * 4)
            guard rowCount >= 1, rows.count == rowCount * width * 4 else {
                throw AppError.encodeFailed(
                    "float TIFF writer: band size mismatch (\(rows.count) "
                        + "floats for width \(width))")
            }
            guard bytesWritten + UInt64(rowCount * width * 16)
                <= UInt64(UInt32.max)
            else {
                throw AppError.encodeFailed(
                    "float TIFF writer: product exceeds the classic TIFF "
                        + "4 GiB offset limit")
            }
            if strips.isEmpty {
                firstStripRows = rowCount
            }
            let stripOffset = UInt32(bytesWritten)
            let chunkRows = 64
            var chunkStart = 0
            try rows.withUnsafeBufferPointer { buffer in
                while chunkStart < rowCount {
                    let chunk = min(chunkRows, rowCount - chunkStart)
                    let data = Data(
                        bytes: buffer.baseAddress!
                            .advanced(by: chunkStart * width * 4),
                        count: chunk * width * 16)
                    try handle?.write(contentsOf: data)
                    chunkStart += chunk
                }
            }
            bytesWritten += UInt64(rowCount * width * 16)
            strips.append(
                (offset: stripOffset,
                 byteCount: UInt32(rowCount * width * 16),
                 rows: rowCount))
        }

        /// The diagnostic flush (the probe's footprint localization):
        /// sync the product's dirty page-cache pages back to the volume
        /// WITHOUT finishing — the L077 dirty-file-cache footprint share,
        /// measured per band.
        func syncForDiagnostics() throws {
            guard let handle else { return }
            try handle.synchronizeFile()
        }

        /// Append the IFD (+ the external values and the ICC payload),
        /// backfill the header offset, and promote tmp → destination.
        public func finish() throws {
            guard !finished, let handle else {
                throw AppError.encodeFailed(
                    "float TIFF writer: finish without an open writer")
            }
            guard let first = strips.first else {
                throw AppError.encodeFailed(
                    "float TIFF writer: finish with no strips written")
            }
            // The RowsPerStrip contract: only the last strip may shrink.
            for strip in strips.dropLast()
            where strip.rows != firstStripRows {
                throw AppError.encodeFailed(
                    "float TIFF writer: non-uniform strip rows "
                        + "\(strip.rows) vs \(firstStripRows)")
            }

            let ifdOffset = Self.aligned(bytesWritten)
            if UInt64(ifdOffset) > bytesWritten {
                // Strip bytes are 16-row multiples — always even; the pad
                // is belt-and-braces for the word-aligned IFD offset.
                let pad = Int(UInt64(ifdOffset) - bytesWritten)
                try handle.write(contentsOf: Data(repeating: 0, count: pad))
            }

            // The external value pool (laid out first, offsets captured),
            // then the 14-entry tag-ascending IFD.
            let ifdSize = 2 + 14 * 12 + 4
            var external = Data()
            func place(_ payload: [UInt8]) -> UInt32 {
                var at = ifdOffset + UInt32(ifdSize) + UInt32(external.count)
                if at % 2 == 1 {
                    external.append(0)
                    at += 1
                }
                external.append(contentsOf: payload)
                return at
            }
            func even(_ payload: [UInt8]) -> [UInt8] {
                var copy = payload
                if copy.count % 2 == 1 {
                    copy.append(0)
                }
                return copy
            }
            let icc = Self.iccData(colorSpace) ?? Data()
            let iccBytes = Array(icc)
            let software = Array("Lightamer pano merge\0".utf8)
            let stripCount = strips.count

            let bitsOffset = place(Self.u16ArrayLittle([32, 32, 32, 32]))
            let stripOffsets: [UInt8] = strips.flatMap {
                Self.u32Little($0.offset)
            }
            let stripCounts: [UInt8] = strips.flatMap {
                Self.u32Little($0.byteCount)
            }
            let offsetsOffset = stripCount > 1 ? place(stripOffsets) : 0
            let countsOffset = stripCount > 1 ? place(stripCounts) : 0
            let formatOffset = place(Self.u16ArrayLittle([3, 3, 3, 3]))
            let softwareOffset = place(even(software))
            let iccOffset = place(even(iccBytes))

            func entry(
                _ tag: UInt16, _ type: UInt16, _ count: UInt32,
                inline: UInt32? = nil, short: UInt16? = nil,
                at: UInt32? = nil
            ) -> [UInt8] {
                var bytes: [UInt8] = []
                bytes.append(contentsOf: Self.u16Little(tag))
                bytes.append(contentsOf: Self.u16Little(type))
                bytes.append(contentsOf: Self.u32Little(count))
                if let inline {
                    bytes.append(contentsOf: Self.u32Little(inline))
                } else if let short {
                    bytes.append(contentsOf: Self.u16Little(short))
                    bytes.append(contentsOf: Self.u16Little(0))
                } else if let at {
                    bytes.append(contentsOf: Self.u32Little(at))
                } else {
                    bytes.append(contentsOf: Self.u32Little(0))
                }
                return bytes
            }

            var ifd: [UInt8] = []
            ifd.append(contentsOf: Self.u16Little(14))
            ifd.append(contentsOf: entry(256, 4, 1, inline: UInt32(width)))
            ifd.append(contentsOf: entry(257, 4, 1, inline: UInt32(height)))
            ifd.append(contentsOf: entry(258, 3, 4, at: bitsOffset))
            ifd.append(contentsOf: entry(259, 3, 1, short: 1))
            ifd.append(contentsOf: entry(262, 3, 1, short: 2))
            if stripCount > 1 {
                ifd.append(
                    contentsOf: entry(273, 4, UInt32(stripCount),
                        at: offsetsOffset))
            } else {
                ifd.append(
                    contentsOf: entry(273, 4, 1, inline: strips[0].offset))
            }
            ifd.append(contentsOf: entry(277, 3, 1, short: 4))
            ifd.append(
                contentsOf: entry(278, 4, 1, inline: UInt32(firstStripRows)))
            if stripCount > 1 {
                ifd.append(
                    contentsOf: entry(279, 4, UInt32(stripCount),
                        at: countsOffset))
            } else {
                ifd.append(
                    contentsOf: entry(279, 4, 1, inline: strips[0].byteCount))
            }
            ifd.append(contentsOf: entry(284, 3, 1, short: 1))
            ifd.append(
                contentsOf: entry(305, 2, UInt32(software.count),
                    at: softwareOffset))
            ifd.append(contentsOf: entry(338, 3, 1, short: 1))
            ifd.append(contentsOf: entry(339, 3, 4, at: formatOffset))
            ifd.append(
                contentsOf: entry(34675, 7, UInt32(icc.count), at: iccOffset))
            ifd.append(contentsOf: Self.u32Little(0))
            precondition(
                ifd.count == ifdSize,
                "IFD layout drifted from the external-offset arithmetic")

            try handle.write(contentsOf: Data(ifd))
            try handle.write(contentsOf: external)
            // Backfill the header's IFD offset.
            try handle.seek(toOffset: 4)
            try handle.write(contentsOf: Data(Self.u32Little(ifdOffset)))
            try handle.synchronizeFile()
            try handle.close()
            self.handle = nil
            finished = true

            // The atomic promote (never overwrite — D-08-CONTEXT-11).
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.removeItem(at: temporary)
                    throw AppError.encodeFailed(
                        "refusing to overwrite existing "
                            + "\(destination.lastPathComponent)")
                }
                try FileManager.default.moveItem(
                    at: temporary, to: destination)
            } catch let error as AppError {
                throw error
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw AppError.encodeFailed(
                    "promote failed for \(destination.lastPathComponent): "
                        + "\(error)")
            }
        }

        // MARK: little-endian helpers

        private static func u16Little(_ value: UInt16) -> [UInt8] {
            [UInt8(value & 0xFF), UInt8(value >> 8)]
        }

        private static func u32Little(_ value: UInt32) -> [UInt8] {
            [
                UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF),
            ]
        }

        private static func u16ArrayLittle(_ values: [UInt16]) -> [UInt8] {
            values.flatMap { u16Little($0) }
        }

        private static func aligned(_ offset: UInt64) -> UInt32 {
            UInt32((offset + 1) & ~UInt64(1))
        }

        private static func iccData(_ colorSpace: CGColorSpace) -> Data? {
            colorSpace.copyICCData() as Data?
        }
    }
}
