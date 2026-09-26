import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ExportRecipe / ExportVariant — the EXP-07/EXP-03 export model (Plan 11-01 T1).
//
// D-11-CONTEXT-3: `ExportRecipe = [ExportVariant]`, a pure VALUE type. v1 does
// NOT persist it (the export panel builds it inline; session-lifetime only).
// Codable exists solely so the Phase 12 preset face can mount these types with
// zero migration — nothing here touches disk in this phase.
//
// L013 red line: NO hash fields on any of these types — a recipe never enters
// a cross-process identity (StableHash territory is for pipe/history/sidecar).
//
// Sizing ownership (OQ-11-6, D-08-CONTEXT-7): `variant.sizing` IS a
// `YiyinExportSettings` — the yiyin panel's own sizing model, reused verbatim
// (no parallel `ExportSizing` shim). The EXP-03 percent mode rides the
// dedicated `scalePercent` carrier field and is folded into the SAME math via
// `effectiveSizing` (pure; test-vector pinned in ExportRecipeTests).
// ─────────────────────────────────────────────────────────────────────────────

/// One export specification: sizing × format × color space × yiyin switch,
/// fanned out over a queue action as N variants → N jobs (EXP-07).
public struct ExportVariant: Codable, Hashable, Sendable {

    /// The sizing spec (yiyin `OutputMode` — original / longEdge / shortEdge,
    /// never-upscale clamped by `YiyinExportSettings.targetSize`).
    public var sizing: YiyinExportSettings

    /// The EXP-03 percent-mode carrier. `nil` = consume `sizing` verbatim;
    /// a value = the output is this percentage of the SOURCE canvas, folded
    /// to a longEdge px by `effectiveSizing` at queue-entry time (the same
    /// never-upscale + 100k-px-cap math as every other mode).
    public var scalePercent: Double?

    /// The file format + its per-format parameter face (RESEARCH §1.2).
    public var format: ExportFormatSpec

    /// The output color space (EXP-04, five choices).
    public var colorSpace: ExportColorSpace

    /// `true` = consume the sidecar's existing borders/watermark instances
    /// (EXP-05 shared config) — this variant renders THROUGH the yiyin
    /// modules; `false` = plain render. Per-instance enable lives in the
    /// sidecar, as for the editor preview.
    public var yiyin: Bool

    /// Explicit output tag override (D-11-CONTEXT-4). `nil` = derive (single
    /// variant → no tag; multi-variant → size/format-derived, see
    /// `ExportRecipe.resolvedOutputTags`).
    public var outputTag: String?

    public init(
        sizing: YiyinExportSettings = YiyinExportSettings(),
        scalePercent: Double? = nil,
        format: ExportFormatSpec,
        colorSpace: ExportColorSpace,
        yiyin: Bool = false,
        outputTag: String? = nil
    ) {
        self.sizing = sizing
        self.scalePercent = scalePercent
        self.format = format
        self.colorSpace = colorSpace
        self.yiyin = yiyin
        self.outputTag = outputTag
    }

    /// Validate every dimension BEFORE a queue action consumes it
    /// (sizing bounds + format quality bounds + percent domain).
    public func validate() throws {
        try sizing.validate()
        try format.validate()
        try Self.validateScalePercent(scalePercent)
    }

    /// The percent-mode legal domain (execution decision, 11-01-DECISIONS D4):
    /// `0 < p ≤ 10_000`. Zero/negative is meaningless; the 10_000 upper bound
    /// is a defensive typo guard only — anything above 100 is clamped to the
    /// source by the never-upscale fold anyway.
    public static func validateScalePercent(_ percent: Double?) throws {
        guard let percent else { return }
        guard percent > 0, percent <= 10_000 else {
            throw AppError.invalidParameter(
                "export scalePercent \(percent) outside (0, 10_000]")
        }
    }

    /// The EXP-03 fold: percent mode → a `YiyinExportSettings` in the SAME
    /// longEdge math everything else uses. Pure; test-vector pinned.
    ///
    /// - `scalePercent == nil` (or 100) → `sizing` verbatim.
    /// - otherwise → `.longEdge(px:)` at `round(sourceLongEdge × p/100)`,
    ///   clamped to `[1, sourceLongEdge]` (never upscale; the downstream
    ///   `targetSize` clamp then has nothing left to catch).
    public func effectiveSizing(canvasWidth: Int, canvasHeight: Int) -> YiyinExportSettings {
        guard let percent = scalePercent, percent != 100 else { return sizing }
        let long = max(max(canvasWidth, canvasHeight), 1)
        let px = min(max((Double(long) * percent / 100).rounded(), 1), Double(long))
        return YiyinExportSettings(mode: .longEdge(px: Int(px)), dpi: sizing.dpi)
    }
}

/// A queue action's variant list (D-11-CONTEXT-3). Value type; v1 inline in
/// the export panel, Phase 12 mounts it into presets via Codable.
public typealias ExportRecipe = [ExportVariant]

public extension Array where Element == ExportVariant {

    /// The D-11-CONTEXT-4 tag derivation (pure): single variant → no tag;
    /// multi-variant → a per-variant tag so same-stem outputs never overwrite
    /// each other. Order matches the recipe order.
    ///
    /// Per variant: an explicit non-empty `outputTag` wins; otherwise size
    /// derivation (`"1200"` from longEdge/shortEdge px — percent folded via
    /// `effectiveSizing`), falling back to the format name (`"webp"`) for
    /// `original` sizing. A collision appends `-<formatName>` (then
    /// `-<index>`) so two variants can still collide only by full intent.
    func resolvedOutputTags(canvasWidth: Int, canvasHeight: Int) -> [String?] {
        guard count > 1 else { return map { _ in nil } }
        var seen: [String: Int] = [:]
        return enumerated().map { index, variant in
            let explicit = variant.outputTag?.trimmingCharacters(in: .whitespaces)
            let base: String
            if let explicit, !explicit.isEmpty {
                base = explicit
            } else {
                base = derivedTag(
                    for: variant, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
            }
            let seenCount = seen[base, default: 0]
            seen[base] = seenCount + 1
            switch seenCount {
            case 0: return base
            case 1: return "\(base)-\(variant.format.formatName)"
            default: return "\(base)-\(variant.format.formatName)-\(index)"
            }
        }
    }
}

/// The size-first tag derivation (free function — it folds percent mode
/// through `effectiveSizing` so it shares the px-tag face; only `original`
/// falls back to the format name, a percent of the source is still a size).
private func derivedTag(
    for variant: ExportVariant, canvasWidth: Int, canvasHeight: Int
) -> String {
    let effective = variant.effectiveSizing(
        canvasWidth: canvasWidth, canvasHeight: canvasHeight)
    switch effective.mode {
    case .longEdge(let px), .shortEdge(let px):
        return "\(px)"
    case .original:
        return variant.format.formatName
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExportFormatSpec — the six-format parameter face (RESEARCH §1.2 capability
// boundaries; D-11-CONTEXT-1: no libavif, AVIF is native macOS 27+).
// ─────────────────────────────────────────────────────────────────────────────

/// One output format with EXACTLY the knobs that format exposes — no
/// cross-format option soup (a PNG has no quality slider; a WebP has no
/// bit-depth menu above 8; TIFF float keeps linear, RESEARCH §3.3).
public enum ExportFormatSpec: Codable, Hashable, Sendable {

    /// 8-bit, lossy, quality 0...1 (`kCGImageDestinationLossyCompressionQuality`).
    case jpeg(quality: Double)

    /// 8/16-bit, lossless deflate (no user-facing quality knob).
    case png(bitDepth: PNGBitDepth)

    /// 8/16-bit display-domain or 32-bit-float LINEAR (D-11-CONTEXT-7
    /// quantization tiers); compression None/LZW/AdobeDeflate(ZIP).
    /// JPEG-in-TIFF deliberately absent (lossy domain over a linear pipe
    /// is ambiguous — RESEARCH §1.2).
    case tiff(bitDepth: TIFFBitDepth, compression: TIFFCompression)

    /// 8/10-bit, lossy, quality 0...1.
    case heic(quality: Double, bitDepth: HEICBitDepth)

    /// 8/10/12-bit (12 verified at the 11-02 goldens; R1 downgrade path =
    /// document an 8/10 ceiling), lossy, quality 0...1.
    case avif(quality: Double, bitDepth: AVIFBitDepth)

    /// 8-bit only (libwebp v1 capability edge); lossy quality 0...1 or the
    /// independent lossless face.
    case webp(quality: Double, lossless: Bool)

    // MARK: Nested bit-depth / compression menus (per format — no shared
    // union type, so an illegal depth is UNREPRESENTABLE at the type level).

    public enum PNGBitDepth: String, Codable, Hashable, Sendable {
        case eight, sixteen
    }

    public enum TIFFBitDepth: String, Codable, Hashable, Sendable {
        case eight, sixteen, float32
    }

    public enum TIFFCompression: String, Codable, Hashable, Sendable {
        /// `kCGImagePropertyTIFFCompression` 1.
        case none
        /// 5 (LZW).
        case lzw
        /// 8 (AdobeDeflate / ZIP).
        case zip
    }

    public enum HEICBitDepth: String, Codable, Hashable, Sendable {
        case eight, ten
    }

    public enum AVIFBitDepth: String, Codable, Hashable, Sendable {
        case eight, ten, twelve
    }

    // MARK: Derived faces

    /// The canonical lowercase format name (also the tag-derivation fallback).
    public var formatName: String {
        switch self {
        case .jpeg: return "jpeg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .heic: return "heic"
        case .avif: return "avif"
        case .webp: return "webp"
        }
    }

    /// The conventional file extension (execution decision D5: `jpg`/`tif`
    /// short forms — the interop convention Lightroom/C1/darktable share).
    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tif"
        case .heic: return "heic"
        case .avif: return "avif"
        case .webp: return "webp"
        }
    }

    /// The UTI this format encodes through (WebP = libwebp direct, no UTI
    /// write path on any macOS — D-11-CONTEXT-1).
    public var utType: String {
        switch self {
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .tiff: return "public.tiff"
        case .heic: return "public.heic"
        case .avif: return "public.avif"
        case .webp: return "org.webmproject.webp"
        }
    }

    /// The quality knob value, when the format has one (PNG/TIFF are
    /// lossless-without-a-knob → nil).
    public var quality: Double? {
        switch self {
        case .jpeg(let q): return q
        case .png: return nil
        case .tiff: return nil
        case .heic(let q, _): return q
        case .avif(let q, _): return q
        case .webp(let q, _): return q
        }
    }

    // MARK: Validation (RESEARCH §1.2 capability boundaries, vector-pinned)

    /// The shared lossy-quality domain: 0...1 (ImageIO
    /// `kCGImageDestinationLossyCompressionQuality` and the libwebp quality
    /// slider both normalize to this; the 11-02 encoders scale to 0-100).
    public static let qualityRange = 0.0...1.0

    /// Throw `.invalidParameter` for any out-of-domain value. Bit-depth ×
    /// format legality is enforced by the per-format nested enums (an
    /// illegal pairing cannot be CONSTRUCTED); the runtime checks here guard
    /// the continuous knobs (quality, lossless semantics).
    public func validate() throws {
        switch self {
        case .jpeg(let quality):
            try Self.validateQuality(quality, format: "jpeg")
        case .png:
            break // no continuous knob
        case .tiff:
            break // no continuous knob
        case .heic(let quality, _):
            try Self.validateQuality(quality, format: "heic")
        case .avif(let quality, _):
            try Self.validateQuality(quality, format: "avif")
        case .webp(let quality, _):
            // Lossless keeps the knob as the effort/quality face the 11-02
            // encoder maps onto libwebp; the domain stays 0...1 either way.
            try Self.validateQuality(quality, format: "webp")
        }
    }

    private static func validateQuality(_ quality: Double, format: String) throws {
        guard Self.qualityRange.contains(quality) else {
            throw AppError.invalidParameter(
                "\(format) quality \(quality) outside \(Self.qualityRange)")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExportColorSpace — the EXP-04 output-space five-choice menu (D-11-CONTEXT-7:
// single exit conversion, ICC primaries+TRC in one ColorSync render).
// ─────────────────────────────────────────────────────────────────────────────

public enum ExportColorSpace: String, Codable, Hashable, Sendable, CaseIterable {
    case sRGB
    case displayP3
    case adobeRGB
    case proPhoto
    case rec2020
}
