import CoreGraphics
import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// ExportEncoder — the format-dispatch single point (Plan 11-02 T3).
//
// The consumption chain (11-03 export leg): the exit conversion
// (`CIContextPool.renderToEncodedBitmap`) lands target-ENCODED float32 →
// `ExportQuantizer` packs it to the spec's layout → the registry dispatches
// to the format encoder → CGImageDestination (or libwebp, T4) writes the
// file ATOMICALLY (encode to in-memory data, `Data.write(.atomic)` — the
// half-written artifact always lives in Foundation's same-directory tmp,
// D-11-CONTEXT-8 / L009).
//
// HOST FACTS this face is built on (2026-09-26 probes, all pinned by
// ExportEncoderGoldenTests — see 11-02-DECISIONS for the full matrix):
// - EXIF round-trips through the PROPERTIES path (`kCGImagePropertyExifDictionary`
//   on AddImage) in ALL FIVE native formats.
// - `kCGImageDestinationMetadata` (whole-replace AND merge) serializes
//   NOTHING from the metadata object on this host — EXIF/XMP blocks vanish;
//   XMP packets do not serialize through ANY ImageIO write path (source
//   metadata / fresh mutable metadata / CGImageMetadataCreateFromXMPData —
//   all byte-level verified absent). v1 documented limitation.
// - Deep color: HEIC 10-bit and AVIF 10-bit encode from a 16bpc source;
//   AVIF 12-bit requests land at 10-bit (R1 documented ceiling).
// ─────────────────────────────────────────────────────────────────────────────

/// The quantized packed plane — the exact handoff between the quantizer and
/// an encoder. Sendable value (Data + ints); no GPU objects aboard.
public struct ExportQuantizedPlane: Sendable {

    public enum Layout: String, Sendable {

        /// 4 B/px RGBA, host byte order (arm64 = LE).
        case rgba8

        /// 8 B/px RGBA, host-endian UInt16 samples (CGImage face reads it
        /// with `.byteOrder16Little`).
        case rgba16

        /// 16 B/px RGBA float32, host-endian (the 32f linear tier).
        case float32

        public var bytesPerPixel: Int {
            switch self {
            case .rgba8: return 4
            case .rgba16: return 8
            case .float32: return 16
            }
        }

        public var bitsPerComponent: Int {
            switch self {
            case .rgba8: return 8
            case .rgba16: return 16
            case .float32: return 32
            }
        }
    }

    /// Packed samples, `rowBytes = width * layout.bytesPerPixel`.
    public let data: Data
    public let width: Int
    public let height: Int
    public let layout: Layout

    public init(data: Data, width: Int, height: Int, layout: Layout) {
        self.data = data
        self.width = width
        self.height = height
        self.layout = layout
    }

    public var rowBytes: Int { width * layout.bytesPerPixel }

    public func validate() throws {
        guard width >= 1, height >= 1 else {
            throw AppError.invalidParameter("export plane degenerate dimensions \(width)×\(height)")
        }
        let expected = width * height * layout.bytesPerPixel
        guard data.count == expected else {
            throw AppError.invalidParameter(
                "export plane \(layout) byte count \(data.count) != \(width)×\(height) packed (\(expected))")
        }
    }
}

/// One synchronous encode request. NOT Sendable (carries the non-Sendable
/// target `CGColorSpace`): the encode leg consumes it where it builds it.
public struct ExportEncodeRequest {

    /// The quantized plane (layout must match the spec — the registry
    /// validates before dispatch).
    public let plane: ExportQuantizedPlane

    /// The format + parameters.
    public let spec: ExportFormatSpec

    /// The TARGET color space — the plane's pixels are ALREADY encoded in
    /// it (the exit conversion did primaries+white+TRC); building the
    /// CGImage in this space is also the ICC embed (conversion and embed
    /// same-source, RESEARCH §1.2).
    public let colorSpace: CGColorSpace

    /// Output resolution metadata (yiyin DPI semantics; `nil` = omit).
    public let dpi: Double?

    /// The source file for the EXIF round-trip (properties path — HOST
    /// FACT above). `nil` = no EXIF carrier.
    public let sourceURL: URL?

    /// Reserved provenance face (Phase 12): carried onto TIFF's Software
    /// tag (the only working carrier this host exposes). XMP
    /// `xmp:CreatorTool` is NOT writable through ImageIO here — documented
    /// limitation, not a silent drop.
    public let editorSignature: String?

    /// The FINAL destination. The encoder writes atomically (in-memory
    /// encode → `.atomic` write); collisions are resolved upstream by
    /// `ExportNamer`.
    public let destination: URL

    // ── M2-9-03 T2/T3 additive metadata carriers (KD-3/KD-4) — the
    // defaults reproduce the pre-M2-9-03 assembly byte-for-byte except the
    // OQ-6 sanctioned default-policy narrowing (the packet's default-not-
    // mounted face) ──

    /// The EXIF `Software` carrier (D-M2-9-CONTEXT-5): `nil` = omit (the
    /// App layer passes `Lightamer <version>` from `Bundle.main` — Core
    /// never reads the bundle). Consumed in the STANDARD mode only.
    public let exifSoftware: String?

    /// The MEXP-02 metadata strategy (OQ-6). The type default IS the
    /// STANDARD-with-fixed-strips face; `NONE` short-circuits the whole
    /// EXIF round-trip and the Software seat.
    public let metadataPolicy: ExportMetadataPolicy

    /// The output-ICC face (OQ-7 / E1 case A): `true` = EMBED (the CGImage
    /// construction's target space — unchanged); `false` = OMIT, consumed
    /// as the post-encode strip (T3). HEIC/AVIF/WebP cannot strip — the
    /// outcome records the unreachable tier, the product stays embedded.
    public let embedICC: Bool

    public init(
        plane: ExportQuantizedPlane,
        spec: ExportFormatSpec,
        colorSpace: CGColorSpace,
        dpi: Double? = nil,
        sourceURL: URL? = nil,
        editorSignature: String? = nil,
        destination: URL,
        exifSoftware: String? = nil,
        metadataPolicy: ExportMetadataPolicy = .standard,
        embedICC: Bool = true
    ) {
        self.plane = plane
        self.spec = spec
        self.colorSpace = colorSpace
        self.dpi = dpi
        self.sourceURL = sourceURL
        self.editorSignature = editorSignature
        self.destination = destination
        self.exifSoftware = exifSoftware
        self.metadataPolicy = metadataPolicy
        self.embedICC = embedICC
    }
}

/// One format encoder. Stateless and synchronous; concurrency safety comes
/// from statelessness (the 11-04 queue holds concurrency at 1 anyway).
public protocol ExportEncoder: Sendable {
    /// Encode → atomically write → the destination URL (echoed back).
    func encode(_ request: ExportEncodeRequest) throws -> URL
}

// ─────────────────────────────────────────────────────────────────────────────
// ExportICCStrip — the post-encode ICC face (M2-9-03 T3, OQ-7 / checker E1
// case A). The EMBED face is the CGImage construction itself (conversion and
// embed same-source, RESEARCH §1.2 — zero code). The OMIT face is THIS pure
// Data-plane strip, the mountXMP outcome family: the product is already
// written, the strip rewrites it in place (atomic write, L009), and every
// non-stripped outcome DEGRADES — an export never hard-fails on the ICC face.
//
// Why post-encode and not a nil-colorspace CGImage: a nil colorspace is only
// legal for image MASKS — a regular bitmap construction returns nil and the
// existing guard throws encodeFailed (the checker E1 probe face). The
// strip-capable trio is JPEG (APP2 ICC_PROFILE markers), PNG (iCCP chunks)
// and TIFF (tag 34675); the container-profiled HEIC/AVIF cannot strip (the
// ICC rides the container metadata box) and WebP never embeds at all (the
// libwebp v1 no-mux face) — both record the unreachable tier.
// ─────────────────────────────────────────────────────────────────────────────

public enum ExportICCStrip {

    /// The post-encode outcome (the mountXMP family posture).
    public enum Outcome: Equatable, Sendable {
        /// The ICC payload was removed from the product.
        case stripped
        /// HEIC / AVIF / WebP — OMIT is unreachable for the container: the
        /// product stays EMBEDDED (the UI disables the tier per format,
        /// M2-9-04). NOT a degradation of the pixels.
        case skippedUnsupportedFormat
        /// A typed strip error degraded the face: the product exists and
        /// keeps its ICC. Payload = the reason.
        case failed(String)
    }

    /// Strip the embedded ICC from a freshly encoded product, in place
    /// (same-directory tmp atomic rewrite). Pure over the container bytes.
    @discardableResult
    public static func stripICC(from url: URL, format: ExportFormatSpec) -> Outcome {
        switch format {
        case .jpeg, .png, .tiff:
            break
        case .heic, .avif, .webp:
            return .skippedUnsupportedFormat
        }
        guard let original = try? Data(contentsOf: url) else {
            return .failed("ICC strip: unreadable product \(url.lastPathComponent)")
        }
        let stripped: Data
        switch format {
        case .jpeg: stripped = stripJPEGICC(original)
        case .png: stripped = stripPNGICCP(original)
        case .tiff: stripped = stripTIFFICC(original)
        default: return .skippedUnsupportedFormat
        }
        guard stripped != original else {
            return .failed("ICC strip: no ICC payload found in \(url.lastPathComponent)")
        }
        do {
            try stripped.write(to: url, options: .atomic)
            return .stripped
        } catch {
            return .failed("ICC strip: atomic rewrite failed: \(error)")
        }
    }

    // MARK: - The per-container Data-plane parsers

    /// JPEG: walk the marker segments, drop every APP2 carrying the
    /// "ICC_PROFILE\0" payload (chunked profiles = several APP2 segments,
    /// all dropped). Anything this parser cannot walk returns the original
    /// bytes (the caller records the degradation).
    static func stripJPEGICC(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return data }
        var out = Data(capacity: bytes.count)
        out.append(contentsOf: [0xFF, 0xD8])
        var i = 2
        let iccHead = Array("ICC_PROFILE\0".utf8)
        while i < bytes.count {
            guard bytes[i] == 0xFF else { return data }
            var j = i + 1
            while j < bytes.count, bytes[j] == 0xFF { j += 1 }
            guard j < bytes.count else { return data }
            let marker = bytes[j]
            // EOI / SOS: no length field — copy the remainder verbatim (the
            // ICC segments always precede the scan).
            if marker == 0xD8 || marker == 0xD9 || marker == 0xDA {
                out.append(contentsOf: bytes[i...])
                return out
            }
            guard j + 2 < bytes.count else { return data }
            let length = Int(bytes[j + 1]) << 8 | Int(bytes[j + 2])
            let segmentEnd = j + 1 + length
            guard length >= 2, segmentEnd <= bytes.count else { return data }
            let payloadStart = j + 3
            let isICC = marker == 0xE2
                && payloadStart + iccHead.count <= segmentEnd
                && Array(bytes[payloadStart..<(payloadStart + iccHead.count)]) == iccHead
            if !isICC {
                out.append(contentsOf: bytes[i..<segmentEnd])
            }
            i = segmentEnd
        }
        return out
    }

    /// PNG: walk the chunk stream, drop every iCCP chunk. Any structural
    /// anomaly returns the original bytes.
    static func stripPNGICCP(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { return data }
        var out = Data(capacity: bytes.count)
        out.append(contentsOf: signature)
        var i = 8
        while i + 8 <= bytes.count {
            let length = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16
                | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            let type = String(bytes: bytes[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
            let chunkEnd = i + 12 + length
            guard length >= 0, chunkEnd <= bytes.count else { return data }
            if type != "iCCP" {
                out.append(contentsOf: bytes[i..<chunkEnd])
            }
            i = chunkEnd
        }
        guard i == bytes.count else { return data }
        return out
    }

    /// TIFF: remove tag 34675 from IFD0 (and any IFD chain), COMPACTING the
    /// entry table in place — the file LENGTH stays untouched so every
    /// external data offset after the table remains valid; the vacated tail
    /// slots and the shifted next-IFD pointer region are zeroed (readers
    /// stop at the decremented entry count), and the stripped entry's
    /// external DATA BLOCK (the profile payload) is ZEROED too — the payload
    /// size rides the entry's (type, count) face, so the orphan never
    /// survives on disk. Any anomaly returns the original bytes.
    static func stripTIFFICC(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        func u16(_ offset: Int) -> Int? {
            guard offset + 1 < bytes.count else { return nil }
            return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }
        func u32(_ offset: Int) -> Int? {
            guard offset + 3 < bytes.count else { return nil }
            return Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        let bigEndian = bytes.count > 1 && bytes[0] == 0x4D && bytes[1] == 0x4D
        let littleEndian = bytes.count > 1 && bytes[0] == 0x49 && bytes[1] == 0x49
        guard bigEndian || littleEndian else { return data }
        func read16(_ offset: Int) -> Int? {
            guard let raw = u16(offset) else { return nil }
            return littleEndian ? (raw >> 8) | ((raw & 0xFF) << 8) : raw
        }
        func read32(_ offset: Int) -> Int? {
            guard let raw = u32(offset) else { return nil }
            return littleEndian
                ? ((raw & 0xFF) << 24) | ((raw & 0xFF00) << 8)
                    | ((raw >> 8) & 0xFF00) | ((raw >> 24) & 0xFF)
                : raw
        }
        // The TIFF field-type byte sizes (the inline/external split sits at
        // 4 bytes — values larger live at the entry's offset face).
        func typeSize(_ type: Int) -> Int? {
            switch type {
            case 1, 2, 6, 7: return 1 // BYTE / ASCII / SBYTE / UNDEFINED
            case 3, 8: return 2       // SHORT / SSHORT
            case 4, 9, 11: return 4   // LONG / SLONG / FLOAT
            case 5, 10, 12: return 8  // RATIONAL / SRATIONAL / DOUBLE
            default: return nil
            }
        }
        guard bytes.count > 4, read16(2) == 42, var ifdOffset = read32(4) else {
            return data
        }
        var removedAny = false
        while ifdOffset > 0, ifdOffset + 2 <= bytes.count {
            guard let count = read16(ifdOffset),
                ifdOffset + 2 + count * 12 + 4 <= bytes.count else { return data }
            var writeIndex = ifdOffset + 2
            var removedInThisIFD = false
            var orphanRange: Range<Int>?
            for entryIndex in 0..<count {
                let entry = ifdOffset + 2 + entryIndex * 12
                let tag = read16(entry) ?? 0
                if tag == 34675 {
                    removedAny = true
                    removedInThisIFD = true
                    // Zero the profile payload: the entry's (type, count)
                    // sizes the block; > 4 bytes lives at the offset face.
                    if let type = read16(entry + 2), let count64 = read32(entry + 4),
                        let size = typeSize(type) {
                        let total = count64 * size
                        if total > 4, let offset = read32(entry + 8),
                            offset >= 0, offset < bytes.count {
                            orphanRange = offset..<min(offset + total, bytes.count)
                        }
                    }
                    continue // dropped: the following entries shift left
                }
                if writeIndex != entry {
                    for k in 0..<12 { bytes[writeIndex + k] = bytes[entry + k] }
                }
                writeIndex += 12
            }
            if let orphanRange {
                for k in orphanRange { bytes[k] = 0 }
            }
            // The original next-IFD pointer sits after the last entry.
            let nextIFD = read32(ifdOffset + 2 + count * 12) ?? 0
            // Rewrite the compacted next-IFD pointer, then zero the stale
            // tail (the vacated entry slot + the old pointer slot).
            func write32(_ offset: Int, _ value: Int, big: Bool) {
                let b0 = (value >> 24) & 0xFF, b1 = (value >> 16) & 0xFF
                let b2 = (value >> 8) & 0xFF, b3 = value & 0xFF
                let bytesOut: [UInt8] = big ? [UInt8(b0), UInt8(b1), UInt8(b2), UInt8(b3)]
                    : [UInt8(b3), UInt8(b2), UInt8(b1), UInt8(b0)]
                for (k, byte) in bytesOut.enumerated() { bytes[offset + k] = byte }
            }
            let newCount = count - (removedInThisIFD ? 1 : 0)
            func write16(_ offset: Int, _ value: Int, big: Bool) {
                let b0 = (value >> 8) & 0xFF, b1 = value & 0xFF
                let bytesOut: [UInt8] = big ? [UInt8(b0), UInt8(b1)]
                    : [UInt8(b1), UInt8(b0)]
                for (k, byte) in bytesOut.enumerated() { bytes[offset + k] = byte }
            }
            write16(ifdOffset, newCount, big: bigEndian)
            let pointerOffset = ifdOffset + 2 + newCount * 12
            write32(pointerOffset, nextIFD, big: bigEndian)
            let staleEnd = ifdOffset + 2 + count * 12 + 4
            if pointerOffset + 4 < staleEnd {
                for k in (pointerOffset + 4)..<staleEnd { bytes[k] = 0 }
            }
            ifdOffset = nextIFD
        }
        guard removedAny else { return data }
        return Data(bytes)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Registry
// ─────────────────────────────────────────────────────────────────────────────

public enum ExportEncoderRegistry {

    /// The quantized layout each format spec consumes (the quantizer's
    /// dispatch face — D-11-CONTEXT-7 tiers): display 8-bit for the lossy
    /// trio + WebP; 16bpc for deep HEIC/AVIF (the container the encoder
    /// requantizes from); per-format TIFF.
    public static func expectedLayout(for spec: ExportFormatSpec) throws -> ExportQuantizedPlane.Layout {
        switch spec {
        case .jpeg, .webp:
            return .rgba8
        case .png(.eight), .tiff(.eight, _):
            return .rgba8
        case .png(.sixteen), .tiff(.sixteen, _):
            return .rgba16
        case .tiff(.float32, _):
            return .float32
        case .heic(_, .eight), .avif(_, .eight):
            return .rgba8
        case .heic(_, .ten), .avif(_, .ten), .avif(_, .twelve):
            return .rgba16
        }
    }

    /// The dispatch single point (11-03/11-04 consume this). Throws a typed
    /// error when the plane's layout doesn't match the spec's expectation —
    /// a mismatch is a caller bug, not a runtime condition.
    public static func encoder(for spec: ExportFormatSpec, plane: ExportQuantizedPlane) throws -> any ExportEncoder {
        let expected = try expectedLayout(for: spec)
        guard plane.layout == expected else {
            throw AppError.invalidParameter(
                "\(spec.formatName) needs a \(expected.rawValue) plane, got \(plane.layout.rawValue)")
        }
        switch spec {
        case .jpeg: return JPEGEncoder()
        case .png: return PNGEncoder()
        case .tiff: return TIFFEncoder()
        case .heic: return HEICEncoder()
        case .avif: return AVIFEncoder()
        case .webp: return LightamerWebPEncoder()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExportColorSpace → CGColorSpace mapping (RESEARCH §3.3)
// ─────────────────────────────────────────────────────────────────────────────

public enum ExportColorSpaceMapper {

    /// Raw `kCGColorSpace*` constant names — the typed CGColorSpace overlay
    /// has NO members for ROMM / ITUR_2020 display on this SDK (probed), and
    /// the raw constants are the system headers' stable public face. The
    /// force-unwraps carry the same safety argument as
    /// `WorkingSpace.colorSpace` (system-provided constants, always present).
    private enum SystemName {
        static let sRGB = "kCGColorSpaceSRGB"
        static let linearSRGB = "kCGColorSpaceLinearSRGB"
        static let displayP3 = "kCGColorSpaceDisplayP3"
        static let linearDisplayP3 = "kCGColorSpaceLinearDisplayP3"
        static let adobeRGB = "kCGColorSpaceAdobeRGB1998"
        static let rommRGB = "kCGColorSpaceROMMRGB" // ProPhoto (ROMM)
        static let rec2020 = "kCGColorSpaceITUR_2020" // display TRC variant
        static let linearRec2020 = "kCGColorSpaceLinearITUR_2020"
    }

    /// The display-TRC variant (the quantized 8/16-bit tiers' target —
    /// RESEARCH §3.3 "目标 ICC（显示 TRC 版）").
    public static func displayCGColorSpace(for cs: ExportColorSpace) -> CGColorSpace {
        switch cs {
        case .sRGB: return CGColorSpace(name: SystemName.sRGB as CFString)!
        case .displayP3: return CGColorSpace(name: SystemName.displayP3 as CFString)!
        case .adobeRGB: return CGColorSpace(name: SystemName.adobeRGB as CFString)!
        case .proPhoto: return CGColorSpace(name: SystemName.rommRGB as CFString)!
        case .rec2020: return CGColorSpace(name: SystemName.rec2020 as CFString)!
        }
    }

    /// The LINEAR variant (the TIFF 32f scene-referred handoff —
    /// D-11-CONTEXT-7). The system provides linear variants ONLY for
    /// sRGB / Display P3 / Rec2020 — no linear AdobeRGB / linear ROMM exists
    /// (probed; DECISIONS D-11-02-2), so those two throw a typed error: a
    /// 32f export must stay linear, a display-TRC profile would silently
    /// bend the values.
    public static func linearCGColorSpace(for cs: ExportColorSpace) throws -> CGColorSpace {
        switch cs {
        case .sRGB: return CGColorSpace(name: SystemName.linearSRGB as CFString)!
        case .displayP3: return CGColorSpace(name: SystemName.linearDisplayP3 as CFString)!
        case .rec2020: return CGColorSpace(name: SystemName.linearRec2020 as CFString)!
        case .adobeRGB, .proPhoto:
            throw AppError.invalidParameter(
                "32-bit float TIFF needs a LINEAR profile variant; the system ships none for "
                    + "\(cs) (R1-adjacent v1 boundary — the eight/float menu pairs sRGB/P3/Rec2020)")
        }
    }

    /// The ICC profile-name substring the round-trip goldens assert (probed:
    /// "sRGB IEC61966-2.1" / "Display P3" / "Adobe RGB (1998)" / "ROMM RGB:
    /// ISO 22028-2:2013" / "Rec. ITU-R BT.2020-1"; linear variants append
    /// " Linear" — a substring still matches).
    public static func iccProfileNameSubstring(for cs: ExportColorSpace) -> String {
        switch cs {
        case .sRGB: return "sRGB"
        case .displayP3: return "Display P3"
        case .adobeRGB: return "Adobe RGB"
        case .proPhoto: return "ROMM"
        case .rec2020: return "BT.2020"
        }
    }
}
