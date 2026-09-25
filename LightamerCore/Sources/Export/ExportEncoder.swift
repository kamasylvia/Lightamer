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

    public init(
        plane: ExportQuantizedPlane,
        spec: ExportFormatSpec,
        colorSpace: CGColorSpace,
        dpi: Double? = nil,
        sourceURL: URL? = nil,
        editorSignature: String? = nil,
        destination: URL
    ) {
        self.plane = plane
        self.spec = spec
        self.colorSpace = colorSpace
        self.dpi = dpi
        self.sourceURL = sourceURL
        self.editorSignature = editorSignature
        self.destination = destination
    }
}

/// One format encoder. Stateless and synchronous; concurrency safety comes
/// from statelessness (the 11-04 queue holds concurrency at 1 anyway).
public protocol ExportEncoder: Sendable {
    /// Encode → atomically write → the destination URL (echoed back).
    func encode(_ request: ExportEncodeRequest) throws -> URL
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
