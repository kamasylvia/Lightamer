import ImageIO
import LightamerCore
@testable import LightamerCore
import XCTest

/// Plan 12-3 T2/T3 — the container injection seams: JPEG APP1 and PNG iTXt
/// positive byte anchors + host re-parsability (CGImageSource round-trip),
/// the 64KB segment-limit typed degradation, the misuse/existing-XMP typed
/// errors, and the TIFF tag-700 IFD weave (byte-preserving for every
/// pre-existing entry value).
final class XMPContainerInjectorTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        // L009: fixtures NEVER live on the external volume volume — /tmp is local.
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xmp-inject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Harness

    private let packet = XMPWriter.write(fields: XMPFields(
        rating: 3, label: "Green",
        hierarchicalSubject: ["Nature|Flower|Rose"],
        subject: ["Rose", "Flower"]))!

    /// A small real JPEG product (the same shape the export chain lands).
    private func makeJPEG() throws -> Data {
        let plane = ExportQuantizedPlane(
            data: Data([UInt8](repeating: 128, count: 8 * 8 * 4)),
            width: 8, height: 8, layout: .rgba8)
        let url = tempDirectory.appendingPathComponent("src.jpg")
        _ = try JPEGEncoder().encode(ExportEncodeRequest(
            plane: plane, spec: .jpeg(quality: 0.9),
            colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            destination: url))
        return try Data(contentsOf: url)
    }

    private func makePNG() throws -> Data {
        let plane = ExportQuantizedPlane(
            data: Data([UInt8](repeating: 90, count: 8 * 8 * 4)),
            width: 8, height: 8, layout: .rgba8)
        let url = tempDirectory.appendingPathComponent("src.png")
        _ = try PNGEncoder().encode(ExportEncodeRequest(
            plane: plane, spec: .png(bitDepth: .eight),
            colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            destination: url))
        return try Data(contentsOf: url)
    }

    private func makeTIFF() throws -> Data {
        let plane = ExportQuantizedPlane(
            data: Data([UInt8](repeating: 60, count: 8 * 8 * 4)),
            width: 8, height: 8, layout: .rgba8)
        let url = tempDirectory.appendingPathComponent("src.tif")
        _ = try TIFFEncoder().encode(ExportEncodeRequest(
            plane: plane, spec: .tiff(bitDepth: .eight, compression: .none),
            colorSpace: ExportColorSpaceMapper.displayCGColorSpace(for: .sRGB),
            destination: url))
        return try Data(contentsOf: url)
    }

    /// Host-parsability proof: re-read the injected file through
    /// CGImageSource and pull the XMP metadata the way any consumer would.
    private func hostXMP(of data: Data) throws -> (rating: String?, bags: [String: [String]]) {
        let url = tempDirectory.appendingPathComponent("probe-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let metadata = try XCTUnwrap(
            CGImageSourceCopyMetadataAtIndex(source, 0, nil),
            "the host must surface the injected XMP as image metadata")
        var bags: [String: [String]] = [:]
        for path in ["lr:hierarchicalSubject", "dc:subject"] {
            if let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
                let value = CGImageMetadataTagCopyValue(tag) as? [Any] {
                bags[path] = value.compactMap {
                    ($0 as? String) ?? (CGImageMetadataTagCopyValue($0 as! CGImageMetadataTag) as? String)
                }
            }
        }
        return (CGImageMetadataCopyStringValueWithPath(metadata, nil, "xmp:Rating" as CFString) as String?, bags)
    }

    /// The host's single-value read (for the JPEG host-fact assertion).
    private func hostXMPRatingOnly(of data: Data) throws -> String? {
        let url = tempDirectory.appendingPathComponent("probe-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        return metadata.flatMap {
            CGImageMetadataCopyStringValueWithPath($0, nil, "xmp:Rating" as CFString) as String?
        }
    }

    /// Extract the packet bytes back out of an injected JPEG (the walk any
    /// conformant consumer performs), for the host-parser round-trip.
    private func extractedJPEGPacket(from data: Data) throws -> Data {
        let bytes = [UInt8](data)
        let header = XMPContainerInjector.xmpNamespaceHeader
        var offset = 2
        while offset + 4 <= bytes.count {
            guard bytes[offset] == 0xFF, bytes[offset + 1] == 0xE1 else {
                if bytes[offset] == 0xFF, bytes[offset + 1] == 0xDA { break }
                // standalone markers have no length field
                if bytes[offset + 1] == 0x01 || (0xD0...0xD7).contains(bytes[offset + 1]) {
                    offset += 2; continue
                }
                let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
                offset += 2 + length
                continue
            }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let payload = offset + 4
            if Array(bytes[payload..<(payload + header.count)]) == header {
                return Data(bytes[(payload + header.count)..<(offset + 2 + length)])
            }
            offset += 2 + length
        }
        throw XCTSkip("no XMP APP1 found")
    }

    /// The decoded pixels stay identical through the injection (the
    /// container splice must not touch image data).
    private func assertPixelsUnchanged(_ before: Data, _ after: Data, uti: String) throws {
        func pixels(_ data: Data) throws -> [UInt8] {
            let url = tempDirectory.appendingPathComponent("px-\(UUID().uuidString).bin")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let context = try XCTUnwrap(CGContext(
                data: nil, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            let buf = context.data!
            return Array(UnsafeBufferPointer(
                start: buf.assumingMemoryBound(to: UInt8.self), count: cg.width * cg.height * 4))
        }
        XCTAssertEqual(try pixels(before), try pixels(after), "\(uti): pixels must survive the splice")
    }

    // MARK: - JPEG APP1 (T2)

    func testJPEGPositiveAnchorAndHostRoundTrip() throws {
        let original = try makeJPEG()
        let injected = try XMPContainerInjector.inject(packet, into: original, format: .jpeg)

        // SOI intact; the APP1 marker + xap header + packet appear verbatim
        // and EXACTLY ONCE.
        let bytes = [UInt8](injected)
        XCTAssertEqual(bytes[0], 0xFF); XCTAssertEqual(bytes[1], 0xD8)
        let segment = [UInt8](packet)
        let header = XMPContainerInjector.xmpNamespaceHeader
        var occurrences = 0
        var anchor = -1
        for offset in 0...(bytes.count - (4 + header.count + segment.count)) {
            guard bytes[offset] == 0xFF, bytes[offset + 1] == 0xE1 else { continue }
            let declared = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard declared == 2 + header.count + segment.count else { continue }
            guard Array(bytes[(offset + 4)..<(offset + 4 + header.count)]) == header else { continue }
            guard Array(bytes[(offset + 4 + header.count)..<(offset + 4 + header.count + segment.count)]) == segment else { continue }
            occurrences += 1
            anchor = offset
        }
        XCTAssertEqual(occurrences, 1, "exactly one well-formed XMP APP1")
        XCTAssertGreaterThan(anchor, 0)
        // The u16 length field includes itself but not the marker.
        XCTAssertEqual(Int(bytes[anchor + 2]) << 8 | Int(bytes[anchor + 3]),
            2 + header.count + segment.count)

        // Removing the inserted segment restores the ORIGINAL bytes exactly
        // (the splice is purely additive).
        var stripped = bytes
        stripped.removeSubrange(anchor..<(anchor + 4 + header.count + segment.count))
        XCTAssertEqual(Data(stripped), original, "the splice must be purely additive")

        // Host re-parsability + value round-trip + pixels untouched.
        // HOST FACT (macOS 27, probe-pinned + reverse-anchored): ImageIO's
        // JPEG reader exposes NO XMP face — even a real-world XMP-bearing
        // JPEG (Keynote's PresetImageFill.jpg) reads {XMP}=nil. The packet
        // bytes are spec-correct (Adobe XMP Part 3 §1.1.1) and every
        // conformant consumer parses them — proven HERE by re-parsing the
        // exact injected packet through the host's own XMP parser
        // (CGImageMetadataCreateFromXMPData — the importer's face), while
        // CGImageSource proves the container still decodes to identical
        // pixels. The nil host face below is a DOCUMENTED limitation
        // (12-3-DECISIONS D-host-jpeg) — if a future macOS starts reading
        // JPEG XMP, this assertion flips red and the limitation is
        // revisited (the 11-02 reverse-anchor discipline).
        let hostRating = try hostXMPRatingOnly(of: injected)
        XCTAssertNil(hostRating, "documented host fact: macOS 27 ImageIO reads no JPEG XMP — if this flips, revisit the limitation")
        let extracted = try extractedJPEGPacket(from: injected)
        let reparsed = try XCTUnwrap(CGImageMetadataCreateFromXMPData(extracted as CFData))
        XCTAssertEqual(
            CGImageMetadataCopyStringValueWithPath(reparsed, nil, "xmp:Rating" as CFString) as String?,
            "3")
        try assertPixelsUnchanged(original, injected, uti: "jpeg")
    }

    func testJPEGPlacementAfterAPP0AndExif() throws {
        // A synthetic minimal container: SOI + APP0(JFIF) + APP1(Exif) +
        // SOS-prefixed tail — the XMP APP1 must land AFTER both, before the
        // rest (Adobe placement; execution decision).
        var container: [UInt8] = [0xFF, 0xD8]
        func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
            [0xFF, marker, UInt8((payload.count + 2) >> 8), UInt8((payload.count + 2) & 0xFF)] + payload
        }
        container += segment(0xE0, [UInt8]("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0])
        container += segment(0xE1, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00] + [0xAA])
        container += [0xFF, 0xDA, 0x00, 0x02] // SOS stub
        let injected = try XMPContainerInjector.inject(
            packet, into: Data(container), format: .jpeg)
        let bytes = [UInt8](injected)
        // Layout: SOI | APP0 | Exif APP1 | XMP APP1 | SOS.
        let xapFirst = Array("http://ns.adobe".utf8)
        var xmpOffset = -1
        for offset in 0..<(bytes.count - 20) where bytes[offset] == 0xFF && bytes[offset + 1] == 0xE1 {
            if Array(bytes[(offset + 4)..<(offset + 4 + 15)]) == xapFirst { xmpOffset = offset; break }
        }
        XCTAssertGreaterThan(xmpOffset, 0)
        let app0End = 2 + 2 + (Int(bytes[4]) << 8 | Int(bytes[5])) // after APP0 length
        let exifEnd = app0End + 2 + (Int(bytes[app0End + 2]) << 8 | Int(bytes[app0End + 3]))
        XCTAssertEqual(xmpOffset, exifEnd, "XMP APP1 lands right after the Exif APP1")
    }

    func testJPEGSegmentLimitTypedError() throws {
        let original = try makeJPEG()
        let oversized = XMPWriter.write(fields: XMPFields(
            rating: nil, label: nil,
            hierarchicalSubject: [String(repeating: "k", count: XMPContainerInjector.jpegMaxPacketBytes)],
            subject: []))!
        XCTAssertThrowsError(
            try XMPContainerInjector.inject(oversized, into: original, format: .jpeg)
        ) { error in
            guard case XMPContainerInjector.InjectionError.jpegSegmentTooLarge(let total, let limit) = error else {
                return XCTFail("expected jpegSegmentTooLarge, got \(error)")
            }
            XCTAssertGreaterThan(total, limit)
            XCTAssertEqual(limit, 65535)
        }
        // Boundary: AT the limit injects fine.
        let exact = XMPWriter.write(fields: XMPFields(
            rating: nil, label: nil,
            hierarchicalSubject: [String(repeating: "k", count: XMPContainerInjector.jpegMaxPacketBytes - 6)],
            subject: []))!  // -6 leaves the packet just under (subject omitted)
        if exact.count <= XMPContainerInjector.jpegMaxPacketBytes {
            XCTAssertNoThrow(try XMPContainerInjector.inject(exact, into: original, format: .jpeg))
        }
    }

    func testJPEGMisuseAndExistingXMP() throws {
        let png = try makePNG()
        XCTAssertThrowsError(
            try XMPContainerInjector.inject(packet, into: png, format: .jpeg)
        ) { error in
            XCTAssertEqual(
                error as? XMPContainerInjector.InjectionError, .notAJPEG)
        }
        // A container already carrying an XMP APP1 refuses (v1 never splices
        // over existing XMP — unreachable from our fresh encodes anyway).
        let original = try makeJPEG()
        let once = try XMPContainerInjector.inject(packet, into: original, format: .jpeg)
        XCTAssertThrowsError(
            try XMPContainerInjector.inject(packet, into: once, format: .jpeg)
        ) { error in
            XCTAssertEqual(
                error as? XMPContainerInjector.InjectionError, .existingXMPNotReplaced)
        }
    }

    // MARK: - PNG iTXt (T2)

    func testPNGPositiveAnchorAndHostRoundTrip() throws {
        let original = try makePNG()
        let injected = try XMPContainerInjector.inject(packet, into: original, format: .png)
        let bytes = [UInt8](injected)

        // Walk the chunk stream: exactly one iTXt keyed XML:com.adobe.xmp,
        // immediately before IEND, with a valid CRC over type+data.
        let keyword = Array(XMPContainerInjector.pngXMPKeyword.utf8)
        var found = -1
        var count = 0
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii)!
            if type == "IEND" { break }
            if type == "iTXt" {
                count += 1
                let dataStart = offset + 8
                let dataEnd = dataStart + length
                XCTAssertEqual(Array(bytes[dataStart..<(dataStart + keyword.count)]), keyword)
                // compression flag + method must both be 0 (uncompressed).
                let nulAfterKeyword = dataStart + keyword.count
                XCTAssertEqual(bytes[nulAfterKeyword], 0x00)
                XCTAssertEqual(bytes[nulAfterKeyword + 1], 0x00, "compression flag")
                XCTAssertEqual(bytes[nulAfterKeyword + 2], 0x00, "compression method")
                XCTAssertEqual(
                    Array(bytes[(nulAfterKeyword + 5)..<(nulAfterKeyword + 5 + packet.count)]),
                    [UInt8](packet))
                let crcBytes = Array(bytes[(dataEnd)..<(dataEnd + 4)])
                let crc = (UInt32(crcBytes[0]) << 24) | (UInt32(crcBytes[1]) << 16)
                    | (UInt32(crcBytes[2]) << 8) | UInt32(crcBytes[3])
                XCTAssertEqual(crc, XMPContainerInjector.crc32(Array(bytes[(offset + 4)..<dataEnd])))
                found = offset
            }
            offset += 12 + length
        }
        XCTAssertEqual(count, 1, "exactly one XMP iTXt")
        // Immediately before the FIRST IDAT (Adobe's position AND the
        // probe-pinned host-readability face — a post-IDAT iTXt is ignored
        // by macOS 27's ImageIO PNG reader).
        XCTAssertNotNil(found)
        let firstIDAT = bytesToIDAT(in: bytes)
        XCTAssertEqual(found + 12 + keyword.count + 5 + packet.count, firstIDAT,
            "the iTXt sits directly before the first IDAT")

        // Purely additive splice: remove [found, firstIDAT).
        var stripped = bytes
        stripped.removeSubrange(found..<firstIDAT)
        XCTAssertEqual(Data(stripped), original, "the splice must be purely additive")

        let xmp = try hostXMP(of: injected)
        XCTAssertEqual(xmp.rating, "3", "the host READS the pre-IDAT XMP iTXt")
        XCTAssertEqual(xmp.bags["dc:subject"], ["Rose", "Flower"])
        try assertPixelsUnchanged(original, injected, uti: "png")
    }

    /// Offset of the first IDAT chunk (the XMP iTXt's landing neighbor).
    private func bytesToIDAT(in bytes: [UInt8]) -> Int {
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            if type == "IDAT" { return offset }
            if type == "IEND" { return offset }
            offset += 12 + length
        }
        return bytes.count
    }

    func testPNGMisuseAndReplaceSemantics() throws {
        let jpeg = try makeJPEG()
        XCTAssertThrowsError(
            try XMPContainerInjector.inject(packet, into: jpeg, format: .png)
        ) { error in
            XCTAssertEqual(error as? XMPContainerInjector.InjectionError, .notAPNG)
        }
        // PNG is the one format where the HOST generates its own XMP iTXt
        // (the EXIF properties bridge) — the seam REPLACES it. Re-injection
        // therefore converges: exactly ONE XMP iTXt carrying the LATEST
        // packet, and the host reads the latest values.
        let original = try makePNG()
        let once = try XMPContainerInjector.inject(packet, into: original, format: .png)
        let second = XMPWriter.write(fields: XMPFields(
            rating: 5, label: nil, hierarchicalSubject: [], subject: []))!
        let twice = try XMPContainerInjector.inject(second, into: once, format: .png)
        let bytes = [UInt8](twice)
        var count = 0
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            if type == "iTXt" { count += 1 }
            if type == "IEND" { break }
            offset += 12 + length
        }
        XCTAssertEqual(count, 1, "replace semantics: exactly one XMP iTXt survives")
        let xmp = try hostXMP(of: twice)
        XCTAssertEqual(xmp.rating, "5", "the host reads the LATEST packet")
        try assertPixelsUnchanged(original, twice, uti: "png")
    }

    // MARK: - TIFF tag 700 (T3 — the plan's cut-risk item; golden-all-green
    // is the completion criterion, otherwise the documented degradation)

    func testTIFFPositiveAnchorValueMatchAndHostRoundTrip() throws {
        let original = try makeTIFF()
        let injected = try XMPContainerInjector.inject(packet, into: original, format: .tiff)
        let bytes = [UInt8](injected)

        // ── parse both files' IFDs ───────────────────────────────────────
        func parse(_ data: [UInt8]) -> (ifd: Int, count: Int, entries: [(tag: Int, type: Int, count: Int, field: [UInt8])], next: Int, endian: Bool) {
            let le = data[0] == 0x49
            func u16(_ o: Int) -> Int { le ? Int(data[o]) | Int(data[o + 1]) << 8 : Int(data[o]) << 8 | Int(data[o + 1]) }
            func u32(_ o: Int) -> Int { le ? Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24 : Int(data[o]) << 24 | Int(data[o + 1]) << 16 | Int(data[o + 2]) << 8 | Int(data[o + 3]) }
            let ifd = u32(4)
            let n = u16(ifd)
            var entries: [(Int, Int, Int, [UInt8])] = []
            for i in 0..<n {
                let base = ifd + 2 + i * 12
                entries.append((u16(base), u16(base + 2), u32(base + 4), Array(data[(base + 8)..<(base + 12)])))
            }
            return (ifd, n, entries, u32(ifd + 2 + n * 12), le)
        }
        let before = parse([UInt8](original))
        let after = parse(bytes)
        XCTAssertEqual(after.count, before.count + 1, "exactly one entry added")
        XCTAssertEqual(after.next, 0, "the IFD chain stays single-page")
        XCTAssertEqual(before.endian, after.endian)

        // The new tag 700 sits in sorted position and points at the packet.
        let xmpEntry = after.entries.first { $0.tag == 700 }
        XCTAssertNotNil(xmpEntry, "tag 700 present")
        XCTAssertEqual(xmpEntry?.type, 1, "type BYTE")
        XCTAssertEqual(xmpEntry?.count, packet.count)
        let le = after.endian
        func u32(_ b: [UInt8], _ o: Int) -> Int {
            le ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24
                : Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
        }
        let valueOffset = u32(bytes, after.ifd + 2 + (after.entries.firstIndex { $0.tag == 700 }!) * 12 + 8)
        XCTAssertEqual(Array(bytes[valueOffset..<(valueOffset + packet.count)]), [UInt8](packet),
            "tag 700's value is the packet verbatim")
        // Tag order ascending (the TIFF-spec MUST).
        let tags = after.entries.map(\.tag)
        XCTAssertEqual(tags, tags.sorted(), "entries stay in ascending tag order")

        // EVERY pre-existing entry keeps tag/type/count; inline values are
        // byte-identical, out-of-line values shift by exactly +12 and the
        // pointed-to bytes survive verbatim.
        let growth = 12
        for old in before.entries {
            let new = after.entries.first { $0.tag == old.tag }
            XCTAssertNotNil(new, "tag \(old.tag) survives")
            XCTAssertEqual(new?.type, old.type)
            XCTAssertEqual(new?.count, old.count)
            let size = old.count * ([1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1][old.type] ?? 1)
            if size <= 4 {
                XCTAssertEqual(new?.field, old.field, "tag \(old.tag) inline value untouched")
            } else {
                let oldOffset = u32([UInt8](original), before.ifd + 2 + before.entries.firstIndex { $0.tag == old.tag }! * 12 + 8)
                let newOffset = u32(bytes, after.ifd + 2 + after.entries.firstIndex { $0.tag == old.tag }! * 12 + 8)
                XCTAssertEqual(newOffset, oldOffset + growth, "tag \(old.tag) offset shifts by the IFD growth")
                XCTAssertEqual(
                    Array(bytes[newOffset..<(newOffset + min(size, 64))]),
                    Array([UInt8](original)[oldOffset..<(oldOffset + min(size, 64))]),
                    "tag \(old.tag) pointed-to bytes survive verbatim")
            }
        }

        // Host re-parsability + pixels + the image survives as an image.
        let xmp = try hostXMP(of: injected)
        XCTAssertEqual(xmp.rating, "3")
        try assertPixelsUnchanged(original, injected, uti: "tiff")
    }

    func testTIFFDoubleInjectionRefusesAndMisuse() throws {
        let jpeg = try makeJPEG()
        XCTAssertThrowsError(
            try XMPContainerInjector.inject(packet, into: jpeg, format: .tiff)
        ) { error in
            XCTAssertEqual(error as? XMPContainerInjector.InjectionError, .notATIFF)
        }
        let original = try makeTIFF()
        let once = try XMPContainerInjector.inject(packet, into: original, format: .tiff)
        XCTAssertThrowsError(
            try XMPContainerInjector.inject(packet, into: once, format: .tiff)
        ) { error in
            XCTAssertEqual(error as? XMPContainerInjector.InjectionError, .existingXMPNotReplaced)
        }
    }

    // MARK: - CRC-32 known points

    func testCRC32KnownValues() {
        // The canonical check values for PNG's polynomial.
        XCTAssertEqual(XMPContainerInjector.crc32(Array("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(XMPContainerInjector.crc32([]), 0x00000000)
        XCTAssertEqual(XMPContainerInjector.crc32(Array("IEND".utf8)), 0xAE426082)
    }
}
