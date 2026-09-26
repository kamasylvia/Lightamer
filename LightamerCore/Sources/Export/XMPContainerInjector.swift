import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// XMPContainerInjector (Plan 12-3 T2/T3) — the per-format container seams.
//
// 11-02 D3's byte-level fact: XMP does NOT serialize through ANY ImageIO
// write path on this host, so the export chain's XMP face is a POST-ENCODE
// injection into the finished container bytes. This file is the pure
// Data→Data plane: no filesystem, no Export types (the ExportFormatSpec →
// format mapping lives in the ExportChainBuilder mount).
//
// Formats (D-12-CONTEXT-10's matrix):
//   jpeg — an APP1 segment (marker FFE1) carrying the xap namespace header
//          + the packet (Adobe XMP Part 3 §1.1.1).
//   png  — an iTXt chunk keyed "XML:com.adobe.xmp" inserted before IEND
//          (Adobe XMP Part 3 §1.1.3; the uncompressed text form).
//   tiff — tag 700 (XMP packet, type BYTE) woven into the IFD (T3).
//   heic / avif / webp — DOCUMENTED EXCEPTIONS (no injection; the export
//          matrix's reverse anchors byte-scan their products for absence).
//
// Every failure is a TYPED error and the caller (the export mount) degrades
// to an XMP-less product — an export NEVER hard-fails on metadata.
//
// RED LINE (zero exceptions): this injector touches only the bytes handed
// to it — the export product. It is structurally incapable of reaching a
// `.xmp` file beside an original (it takes Data in and returns Data).
// ─────────────────────────────────────────────────────────────────────────────

/// The container formats an XMP packet can ride (the injection matrix).
public enum XMPContainerFormat: String, Sendable {
    case jpeg
    case png
    case tiff
}

public enum XMPContainerInjector {

    public enum InjectionError: Error, Equatable, Sendable {

        /// The bytes do not carry the container's magic (a caller bug — the
        /// format came from the encode request's own spec).
        case notAJPEG
        case notAPNG
        case notATIFF

        /// The APP1 segment (header + packet + the 2-byte length field)
        /// would exceed the JPEG segment limit — a >64KB packet is NOT
        /// multi-segment-expanded (Adobe's multi-segment XMP is a
        /// reader-compatibility minefield; documented v1 boundary).
        case jpegSegmentTooLarge(totalBytes: Int, limit: Int)

        /// A pre-existing XMP payload was found in a JPEG/TIFF container.
        /// Unreachable from our chain (fresh encodes carry none — 11-02 D3
        /// and the macOS 27 probes), so v1 refuses to splice over foreign
        /// XMP. PNG is EXEMPT from this refusal: the host ITSELF generates
        /// an exif:*-only XMP iTXt there (the EXIF properties bridge), so
        /// the PNG seam uses replace semantics.
        case existingXMPNotReplaced

        /// Multi-IFD TIFFs (next-IFD pointer != 0) are out of the v1 weave —
        /// our encoder's products are always single-page.
        case multiIFDUnsupported
    }

    /// `FFE1` + 2-byte length + the xap header — the packet ceiling under
    /// JPEG's 65535 segment length (execution decision: the u16 length
    /// INCLUDES itself, hence 65535 - 2 - 29).
    public static let xmpNamespaceHeader = Array(
        "http://ns.adobe.com/xap/1.0\0".utf8)
    public static let jpegMaxPacketBytes = 65535 - 2 - xmpNamespaceHeader.count

    /// PNG's XMP iTXt keyword (Adobe XMP Part 3 §1.1.3, verbatim spelling).
    public static let pngXMPKeyword = "XML:com.adobe.xmp"

    /// Inject `xmp` into `container`. Returns the NEW bytes; the input is
    /// never mutated. Throws typed errors (all degrade at the mount, never
    /// fail the export).
    public static func inject(
        _ xmp: Data, into container: Data, format: XMPContainerFormat
    ) throws -> Data {
        switch format {
        case .jpeg: return try injectJPEG(xmp, into: container)
        case .png: return try injectPNG(xmp, into: container)
        case .tiff: return try injectTIFF(xmp, into: container)
        }
    }

    // MARK: - JPEG (T2)

    /// SOI → [APP0 JFIF] → [APP1 Exif]* → **HERE** → everything else.
    /// The placement follows Adobe's rule (after APP0/Exif APP1, before
    /// other segments — execution decision, documented in 12-3-DECISIONS;
    /// the plan's "append-grade" intent keeps the walker segment-skim only).
    static func injectJPEG(_ xmp: Data, into container: Data) throws -> Data {
        let bytes = [UInt8](container)
        let packet = [UInt8](xmp)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            throw InjectionError.notAJPEG
        }
        guard packet.count <= jpegMaxPacketBytes else {
            throw InjectionError.jpegSegmentTooLarge(
                totalBytes: packet.count + xmpNamespaceHeader.count + 2,
                limit: 65535)
        }

        var offset = 2
        while offset + 4 <= bytes.count {
            guard bytes[offset] == 0xFF else { throw InjectionError.notAJPEG }
            let marker = bytes[offset + 1]
            // Standalone markers (no length field).
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { offset += 2; continue }
            if marker == 0xDA { break } // SOS — pixel data begins; insert before
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let payload = offset + 4
            if marker == 0xE0 {
                offset += 2 + length // JFIF APP0 — skip
                continue
            }
            if marker == 0xE1 {
                // An Exif APP1 ("Exif\0\0" payload) is skipped ahead of;
                // an XMP APP1 (the xap header) means pre-existing XMP.
                if payload + 6 <= bytes.count,
                    bytes[payload] == 0x45, bytes[payload + 1] == 0x78,
                    bytes[payload + 2] == 0x69, bytes[payload + 3] == 0x66,
                    bytes[payload + 4] == 0x00, bytes[payload + 5] == 0x00 {
                    offset += 2 + length
                    continue
                }
                if payload + xmpNamespaceHeader.count <= bytes.count,
                    Array(bytes[payload..<payload + xmpNamespaceHeader.count])
                        == xmpNamespaceHeader {
                    throw InjectionError.existingXMPNotReplaced
                }
                break
            }
            break // first "other" segment — the XMP APP1 goes before it
        }

        let segmentLength = 2 + xmpNamespaceHeader.count + packet.count
        precondition(segmentLength <= 65535, "guarded above")
        var segment = [UInt8]()
        segment.reserveCapacity(2 + segmentLength)
        segment += [0xFF, 0xE1]
        segment += [UInt8(segmentLength >> 8), UInt8(segmentLength & 0xFF)]
        segment += xmpNamespaceHeader
        segment += packet

        var out = Data()
        out.reserveCapacity(container.count + segment.count)
        out.append(contentsOf: bytes[0..<offset])
        out.append(contentsOf: segment)
        out.append(contentsOf: bytes[offset...])
        return out
    }

    // MARK: - PNG (T2)

    static func injectPNG(_ xmp: Data, into container: Data) throws -> Data {
        let bytes = [UInt8](container)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count > signature.count + 12, Array(bytes[0..<8]) == signature else {
            throw InjectionError.notAPNG
        }

        // The iTXt data: keyword + NUL + compression flag 0 + method 0 +
        // language NUL + translated keyword NUL + the UTF-8 packet.
        var chunkData = [UInt8](pngXMPKeyword.utf8)
        chunkData += [0x00, 0x00, 0x00, 0x00, 0x00]
        chunkData += [UInt8](xmp)

        var chunk = [UInt8]()
        chunk += [
            UInt8((chunkData.count >> 24) & 0xFF), UInt8((chunkData.count >> 16) & 0xFF),
            UInt8((chunkData.count >> 8) & 0xFF), UInt8(chunkData.count & 0xFF),
        ]
        chunk += Array("iTXt".utf8)
        chunk += chunkData
        let crc = crc32(Array("iTXt".utf8) + chunkData)
        chunk += [
            UInt8((crc >> 24) & 0xFF), UInt8((crc >> 16) & 0xFF),
            UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF),
        ]

        // Walk the chunk stream. PNG is the ONE format where the host
        // generates its OWN XMP (a probe-pinned macOS 27 fact: the EXIF
        // properties bridge writes an exif:*-only iTXt keyed
        // XML:com.adobe.xmp) — so the seam uses REPLACE semantics: every
        // existing XMP iTXt is dropped and OUR packet lands immediately
        // BEFORE THE FIRST IDAT (Adobe XMP Part 3 §1.1.3's position, and
        // the host-readability face — a post-IDAT iTXt is ignored by the
        // host's PNG reader; the plan's "IEND 前" wording yields to both).
        var offset = signature.count
        var insertionOffset = bytes.count
        var sawIDAT = false
        var removals: [Range<Int>] = []
        while offset + 8 <= bytes.count {
            let length =
                (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            let chunkEnd = offset + 12 + length
            guard chunkEnd <= bytes.count else { throw InjectionError.notAPNG }
            if type == "IEND" {
                if !sawIDAT { insertionOffset = offset } // degenerate: before IEND
                break
            }
            if type == "iTXt" {
                let keywordEnd = bytes[(offset + 8)...].firstIndex(of: 0x00)
                let keyword = keywordEnd.map {
                    String(bytes: bytes[(offset + 8)..<($0)], encoding: .ascii) ?? ""
                }
                if keyword == pngXMPKeyword {
                    removals.append(offset..<chunkEnd)
                }
            }
            if type == "IDAT" && !sawIDAT {
                sawIDAT = true
                insertionOffset = offset
                break // the pre-IDAT landing spot is decided; stop
            }
            offset = chunkEnd
        }
        guard insertionOffset < bytes.count, insertionOffset >= signature.count else {
            throw InjectionError.notAPNG
        }

        // Apply the removals (adjust for earlier shifts), then splice in.
        var stripped = bytes
        for range in removals.reversed() {
            let adjusted = stripped.index(stripped.startIndex, offsetBy: range.lowerBound)
                ..< stripped.index(stripped.startIndex, offsetBy: range.upperBound)
            stripped.removeSubrange(adjusted)
            if range.lowerBound < insertionOffset {
                insertionOffset -= range.count
            }
        }
        var out = Data()
        out.reserveCapacity(stripped.count + chunk.count)
        out.append(contentsOf: stripped[0..<insertionOffset])
        out.append(contentsOf: chunk)
        out.append(contentsOf: stripped[insertionOffset...])
        return out
    }

    // MARK: - CRC-32 (PNG's polynomial, IEEE 802.3)

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var c = UInt32(index)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
            }
            return c
        }
    }()

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - TIFF (T3)

    /// Tag 700 (XMP packet, type BYTE) woven into the first IFD:
    ///
    /// 1. Parse the header (II/MM + magic 42 + first-IFD offset) and the
    ///    entry array; refuse pre-existing tag 700 and multi-IFD files
    ///    (next-IFD pointer != 0 — our encoder's products are single-page).
    /// 2. Insert the new entry in TAG-SORTED position (the TIFF spec
    ///    requires ascending tag order); the IFD grows by exactly 12 bytes
    ///    (even — the word alignment survives).
    /// 3. Shift every OUT-OF-LINE value offset that points at/after the old
    ///    IFD end by that growth (out-of-line = count x typeSize > 4, i.e.
    ///    the entry's 4-byte field is an offset, not an inline value).
    /// 4. Append the packet at the file end (word-aligned: pad one zero
    ///    byte when the landing position is odd) and point tag 700's field
    ///    at it.
    ///
    /// The next-IFD pointer copies verbatim (0); pixels and strips are
    /// byte-identical — only the IFD grew and the packet was appended.
    static func injectTIFF(_ xmp: Data, into container: Data) throws -> Data {
        let bytes = [UInt8](container)
        guard bytes.count >= 8 else { throw InjectionError.notATIFF }

        // ── header: byte order + magic 42 + first-IFD offset ────────────
        let littleEndian: Bool
        switch (bytes[0], bytes[1]) {
        case (0x49, 0x49): littleEndian = true   // "II"
        case (0x4D, 0x4D): littleEndian = false  // "MM"
        default: throw InjectionError.notATIFF
        }
        func u16(_ offset: Int) -> Int {
            littleEndian
                ? Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
                : Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }
        func u32(_ offset: Int) -> Int {
            littleEndian
                ? Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
                    | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
                : Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                    | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        func words32(_ value: Int) -> [UInt8] {
            littleEndian
                ? [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                    UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
                : [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                    UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        }
        func words16(_ value: Int) -> [UInt8] {
            littleEndian
                ? [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
                : [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        }
        guard u16(2) == 42 else { throw InjectionError.notATIFF }

        let ifdOffset = u32(4)
        guard ifdOffset + 2 <= bytes.count else { throw InjectionError.notATIFF }
        let entryCount = u16(ifdOffset)
        let ifdEnd = ifdOffset + 2 + entryCount * 12 + 4
        guard ifdEnd <= bytes.count else { throw InjectionError.notATIFF }
        let nextIFD = u32(ifdOffset + 2 + entryCount * 12)
        guard nextIFD == 0 else { throw InjectionError.multiIFDUnsupported }

        struct Entry { var tag: Int; var type: Int; var count: Int; var field: [UInt8] }
        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)
        for index in 0..<entryCount {
            let base = ifdOffset + 2 + index * 12
            let tag = u16(base)
            guard tag != 700 else { throw InjectionError.existingXMPNotReplaced }
            entries.append(Entry(
                tag: tag, type: u16(base + 2), count: u32(base + 4),
                field: Array(bytes[(base + 8)..<(base + 12)])))
        }

        // ── the shift math: one new entry = +12 bytes after the IFD ──────
        let growth = 12
        let landingRaw = bytes.count + growth
        let packetOffset = landingRaw % 2 == 0 ? landingRaw : landingRaw + 1
        let padBytes = packetOffset - landingRaw

        // Out-of-line values (count x typeSize > 4) whose offset sits at or
        // after the old IFD end shift by the growth; inline values (the
        // value fits the 4-byte field) and any pre-IFD bytes stay put.
        let typeSizes: [Int: Int] = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1,
            8: 2, 9: 4, 10: 8, 11: 4, 12: 8]
        var shifted = entries
        for index in shifted.indices {
            let entry = shifted[index]
            let size = (typeSizes[entry.type] ?? 1) * entry.count
            guard size > 4 else { continue }
            let raw = entry.field
            let valueOffset = littleEndian
                ? Int(raw[0]) | Int(raw[1]) << 8 | Int(raw[2]) << 16 | Int(raw[3]) << 24
                : Int(raw[0]) << 24 | Int(raw[1]) << 16 | Int(raw[2]) << 8 | Int(raw[3])
            guard valueOffset >= ifdEnd else { continue }
            shifted[index].field = words32(valueOffset + growth)
        }

        // ── the new entry: tag 700, type BYTE(1), count = packet bytes ───
        let newEntry = Entry(
            tag: 700, type: 1, count: xmp.count, field: words32(packetOffset))

        // ── assemble: header + grown IFD (tag-sorted) + body + packet ────
        var sorted = shifted
        let insertIndex = sorted.firstIndex { $0.tag > 700 } ?? sorted.count
        sorted.insert(newEntry, at: insertIndex)
        precondition(sorted.count == entryCount + 1)
        // Tag-sorted ascending is a TIFF-spec MUST — assert, don't trust.
        for pair in zip(sorted, sorted.dropFirst()) {
            precondition(pair.0.tag < pair.1.tag, "entries must ascend by tag")
        }

        var ifd: [UInt8] = words16(sorted.count)
        for entry in sorted {
            ifd += words16(entry.tag)
            ifd += words16(entry.type)
            ifd += words32(entry.count)
            ifd += entry.field
        }
        ifd += words32(nextIFD)
        precondition(ifd.count == 2 + (entryCount + 1) * 12 + 4)

        var out = Data()
        out.reserveCapacity(container.count + growth + padBytes + xmp.count)
        out.append(contentsOf: bytes[0..<ifdOffset])
        out.append(contentsOf: ifd)
        out.append(contentsOf: bytes[ifdEnd...])
        out.append(contentsOf: [UInt8](repeating: 0, count: padBytes))
        out.append(xmp)
        return out
    }
}
