import Foundation

// ─────────────────────────────────────────────────────────────────────────
// DNGOpcodeProbe (Plan LENS-01 T2, X1) — the double-correction mutex
// detector for the DNG leg.
//
// CIRAW exposes NO "did the vendor lens correction apply" query API (the
// architectural fact, RESEARCH §Mutex) — the layered judgment is:
//   DNG      → probe the OpcodeList TIFF tags (present ⇒ the decoded
//              pixels already carry the embedded geometry correction;
//              conservative existence-only semantics, X1 — we never
//              parse the opcode payload or infer application semantics),
//   other RAW → `unknown` (no reliable query surface),
//   raster/TIFF → `notApplicable` (stamped at the DecodedImage
//              construction sites).
//
// BOUNDED SEEK-STYLE READS (review m10, the `RasterIccParser
// .tiffEmbeddedICCData` precedent): only the header, the IFD0 entry
// table, and the sub-IFD entry tables are touched — never the pixel
// payload (DNG reaches 10^8-byte files). The `probe(data:)` window
// semantics: the data may be a SLICE of the file (zero-copy slicing at
// the call site); any reference that falls
// outside the window reads as absent — the caller (the RAW leg) then
// lands on `unknown`, which is the safe direction (auto-apply stays
// off). Production goes through `probe(url:)`, which seeks the file on
// disk and needs no full-file buffering at all.
//
// Failure contract: ANY malformed input (bad magic, out-of-range
// offsets, absurd entry counts, truncated tables) → `false` (not
// detected), never a throw — the probe is a hint, the caller's `unknown`
// fallback is the conservative floor.
// ─────────────────────────────────────────────────────────────────────────

/// The three-state judgment for embedded geometry (X1; Core-single-source —
/// the IOP side reads this, never re-declares it).
public enum EmbeddedGeometryState: Sendable {
    /// An embedded geometry-correction opcode list is present — the decoded
    /// pixels are assumed corrected (CIRAW's vendor-lens-correction key
    /// defaults on).
    case detected
    /// No reliable detection surface (vendor RAW, or a DNG without opcode
    /// tags — absence of the tag cannot prove absence of correction).
    case unknown
    /// The chain carries no embedded-geometry concept (raster/TIFF leg).
    case notApplicable
}

public enum DNGOpcodeProbe {

    /// DNG OpcodeList1/2/3 (TIFF tag numbers; DNG 1.4 §OpcodeList1/2/3 —
    /// stage-1/2/3 opcodes; stage 3 is where vendor lens geometry lands).
    public static let opcodeListTags: Set<Int> = [51008, 51009, 51010]

    private static let tagSubIFDs: Int = 0x014A      // 330 — multi-frame sub-IFDs
    private static let tagExifIFD: Int = 0x8769      // 34665 — Exif IFD pointer
    private static let maxIFDEntries = 4096
    private static let maxSubIFDCount = 8
    private static let maxDepth = 1                  // IFD0 (0) → sub-IFD (1)

    /// Production entry: bounded FileHandle reads against the file on disk
    /// (no full-file buffering; malformed/missing file → false).
    public static func probe(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return walk { offset, count in
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil else { return nil }
            return try? handle.read(upToCount: count)
        }
    }

    /// Window entry (tests + callers already holding a prefix window): the
    /// data may be a slice of a larger file; references outside the window
    /// read as absent (the walk degrades to `false` = unknown — safe).
    public static func probe(data: Data) -> Bool {
        walk { offset, count in
            guard offset >= 0, count >= 0, offset + count <= data.count else { return nil }
            return data.subdata(in: offset..<(offset + count))
        }
    }

    // MARK: - The shared walk

    /// TIFF-structure walk: header → IFD0 → (ExifIFD, SubIFDs) one level
    /// deep; true the moment any opcode-list tag shows up. `read` = a
    /// bounded `(offset, count) -> Data?` window (nil = out of range).
    private static func walk(read: (Int, Int) -> Data?) -> Bool {
        guard let header = read(0, 8), header.count == 8 else { return false }
        let littleEndian: Bool
        switch String(bytes: header.prefix(2), encoding: .ascii) {
        case "II": littleEndian = true
        case "MM": littleEndian = false
        default: return false
        }
        func u16(_ b: Data, _ o: Int) -> Int {
            littleEndian
                ? Int(UInt16(b[o]) | UInt16(b[o + 1]) << 8)
                : Int(UInt16(b[o]) << 8 | UInt16(b[o + 1]))
        }
        func u32(_ b: Data, _ o: Int) -> Int {
            littleEndian
                ? Int(UInt32(b[o]) | UInt32(b[o + 1]) << 8
                    | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24)
                : Int(UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16
                    | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3]))
        }
        let ifd0Offset = u32(header, 4)
        return walkIFD(at: ifd0Offset, depth: 0, read: read, u16: u16, u32: u32)
    }

    /// One IFD level: scan the entry table for the opcode tags, then
    /// descend into the Exif-IFD pointer + SubIFDs (depth-capped).
    private static func walkIFD(
        at offset: Int, depth: Int,
        read: (Int, Int) -> Data?,
        u16: (Data, Int) -> Int,
        u32: (Data, Int) -> Int
    ) -> Bool {
        guard depth <= maxDepth, offset > 0 else { return false }
        guard let countData = read(offset, 2), countData.count == 2 else { return false }
        let entryCount = u16(countData, 0)
        guard entryCount > 0, entryCount <= maxIFDEntries else { return false }
        let tableBytes = entryCount * 12
        guard let entries = read(offset + 2, tableBytes), entries.count == tableBytes
        else { return false }

        var subIFDOffsets: [Int] = []
        for i in 0..<entryCount {
            let base = i * 12
            let tag = u16(entries, base)
            if opcodeListTags.contains(tag) { return true }
            if tag == tagExifIFD || tag == tagSubIFDs {
                let type = u16(entries, base + 2)
                let count = u32(entries, base + 4)
                // LONG (4) or IFD (13) carry offsets; 4-byte payloads ride
                // the value field inline.
                guard type == 4 || type == 13, count > 0, count <= maxSubIFDCount
                else { continue }
                if count == 1 {
                    subIFDOffsets.append(u32(entries, base + 8))
                } else {
                    let arrayBytes = count * 4
                    guard let offsets = read(u32(entries, base + 8), arrayBytes),
                          offsets.count == arrayBytes else { continue }
                    for j in 0..<count { subIFDOffsets.append(u32(offsets, j * 4)) }
                }
            }
        }
        if depth < maxDepth {
            for sub in subIFDOffsets {
                if walkIFD(at: sub, depth: depth + 1, read: read, u16: u16, u32: u32) {
                    return true
                }
            }
        }
        return false
    }
}
