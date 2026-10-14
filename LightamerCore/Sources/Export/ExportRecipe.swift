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

    // ── M2-9-01 T3 additive carriers (KD-2) — consumption in M2-9-02/03 ──

    /// The DRT mandatory-linkage carrier (OQ-7): `nil` = the LEGACY
    /// five-space path (`colorSpace` decides — every existing test and the
    /// legacy sheet ride this, byte-frozen); non-nil = the DRT linkage is
    /// FORCED and `colorSpace` is an ignored legacy carrier (the M2 UI
    /// always sets this; space/EOTF/peak come from the record).
    public var drtOutput: DrtRecord?

    /// The M2EXP-02 metadata strategy (OQ-6). The type default IS the
    /// STANDARD-with-fixed-strips face.
    public var metadataPolicy: ExportMetadataPolicy

    /// The output-ICC face (Alcedo ExportIccPolicy): `true` = EMBED
    /// (the Alcedo default), `false` = OMIT (M2-9-03's post-encode strip).
    public var embedICC: Bool

    // ── M6-3-01 T1 additive carrier (KD-1, ALCE-03) ─────────────────────────

    /// `true` = this JPEG variant carries an ISO 21496-1 gain map layer
    /// (UltraHDR): the render captures the DRT tail's pre-EOTF linear plane
    /// and the encode leg goes through `ExportGainMapEncoder` (the CI
    /// full-service write). Session-lifetime recipe face like every other
    /// field (the variant is never persisted — M2-9 既定); the decode falls
    /// back to `false` on every pre-M6-3 payload, so the old bytes are
    /// zero-drift. The six validate gates below make every illegal
    /// combination a typed refusal at the variant gate.
    public var gainMapHDR: Bool

    public init(
        sizing: YiyinExportSettings = YiyinExportSettings(),
        scalePercent: Double? = nil,
        format: ExportFormatSpec,
        colorSpace: ExportColorSpace = .sRGB,
        yiyin: Bool = false,
        outputTag: String? = nil,
        drtOutput: DrtRecord? = nil,
        metadataPolicy: ExportMetadataPolicy = .standard,
        embedICC: Bool = true,
        gainMapHDR: Bool = false
    ) {
        self.sizing = sizing
        self.scalePercent = scalePercent
        self.format = format
        self.colorSpace = colorSpace
        self.yiyin = yiyin
        self.outputTag = outputTag
        self.drtOutput = drtOutput
        self.metadataPolicy = metadataPolicy
        self.embedICC = embedICC
        self.gainMapHDR = gainMapHDR
    }

    // MARK: - Codable (KD-2 additive decode tolerance)

    // Hand-written decode: the synthesized one would demand the three new
    // keys (two of them non-optional) and THROW on every pre-M2-9 payload.
    // All three new fields decode with decodeIfPresent + defaults. The
    // encode face stays synthesized (additive keys only).
    private enum CodingKeys: String, CodingKey {
        case sizing, scalePercent, format, colorSpace, yiyin, outputTag
        case drtOutput, metadataPolicy, embedICC, gainMapHDR
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sizing = try container.decode(YiyinExportSettings.self, forKey: .sizing)
        scalePercent = try container.decodeIfPresent(Double.self, forKey: .scalePercent)
        format = try container.decode(ExportFormatSpec.self, forKey: .format)
        colorSpace = try container.decode(ExportColorSpace.self, forKey: .colorSpace)
        yiyin = try container.decode(Bool.self, forKey: .yiyin)
        outputTag = try container.decodeIfPresent(String.self, forKey: .outputTag)
        drtOutput = try container.decodeIfPresent(DrtRecord.self, forKey: .drtOutput)
        metadataPolicy = try container.decodeIfPresent(
            ExportMetadataPolicy.self, forKey: .metadataPolicy) ?? .standard
        embedICC = try container.decodeIfPresent(Bool.self, forKey: .embedICC) ?? true
        gainMapHDR = try container.decodeIfPresent(Bool.self, forKey: .gainMapHDR) ?? false
    }

    /// Validate every dimension BEFORE a queue action consumes it
    /// (sizing bounds + format quality bounds + percent domain + the OQ-7
    /// resolved-output-color gate).
    public func validate() throws {
        try sizing.validate()
        try format.validate()
        try Self.validateScalePercent(scalePercent)
        // OQ-7 (M2-9-03 T3, Alcedo RequireResolvedExportOutputColor 同构):
        // a DRT linkage WITHOUT a usable peak is a construction bug — the
        // peak feeds the render's tonemap and the record's ICC; a
        // non-finite/non-positive value would poison both. Typed refusal
        // at the variant gate; `drtOutput == nil` (the legacy five-space
        // face) never triggers it.
        if let record = drtOutput {
            guard record.peakLuminance.isFinite, record.peakLuminance > 0 else {
                throw AppError.invalidParameter(
                    "export drtOutput peak must be a finite positive value, "
                        + "got \(record.peakLuminance)")
            }
        }
        // ── M6-3-01 KD-1: the six gain map gates (ALCE-03). Every illegal
        // combination is a typed refusal HERE so a misassembled batch fails
        // at the variant gate, never as a silently-wrong product.
        // ① UltraHDR rides JPEG only (the five other formats are typed-
        //    unreachable — the ExportICCStrip unreachable-copy face).
        // ② The HDR plane's source IS the DRT record (the OQ-7 linkage's
        //    mirror): no record → no pre-EOTF linear plane → no gain map.
        // ③ The peak must clear the SDR reference white (headroom =
        //    peak/203 ≥ 1.0) — below it there is no HDR headroom to encode.
        //    API-CONSUMER CONTRACT (M6-5 T5, the M6-3 ledger D4 residue):
        //    this gate reads `variant.drtOutput.peakLuminance` only — the
        //    RENDER-side headroom comes from the OTHER carrier
        //    (`drtTail.record.peakLuminance`, ExportRenderer's capture
        //    assembly). A Request built directly against this public API
        //    can therefore assemble "drtOutput ≥ 203 (gate ③ passes) +
        //    drtTail.record peak low" → a legal gate face whose product
        //    carries headroom < 1 (weakened gain semantics, never a crash).
        //    The two carriers being same-source is the API consumer's duty
        //    to prove; the production UI path cannot reach the fork —
        //    enqueueExportM2 forces the drtOutput = drtRecord linkage
        //    (OQ-7), dual-path acceptance on record (M6-3 VALIDATION).
        // ④ embedICC is FORCED (RESEARCH §8.4): stripping the APP2 ICC
        //    segment shifts every absolute file offset and invalidates the
        //    MPF subimage pointers — the gain map tier only exists in the
        //    embed form.
        // ⑤ The base must be an SDR rendition (D-M6-3-7): st2084/hlg bases
        //    are the E4 forbidden shape's base-side projection — gain ratios
        //    over PQ/HLG code values are unreadable on an SDR display.
        // ⑥ yiyin is refused (review E1): borders/watermark replay AFTER the
        //    EotfBox, so the tail output's canvas can exceed the captured
        //    EOTF-box input plane — a `.hdrImage` input that no longer
        //    matches the SDR base (a structurally valid, semantically broken
        //    container). Validate-only: the M2 page cannot reach it.
        if gainMapHDR {
            guard case .jpeg = format else {
                throw AppError.invalidParameter(
                    "export gainMapHDR requires the jpeg format "
                        + "(ISO 21496-1 gain map rides JPEG only); "
                        + "\(format.formatName) is typed-unreachable for the tier")
            }
            guard let record = drtOutput else {
                throw AppError.invalidParameter(
                    "export gainMapHDR requires a drtOutput record — the HDR "
                        + "linear plane is captured at the DRT tail's pre-EOTF "
                        + "stage (no record, no plane)")
            }
            guard record.peakLuminance.isFinite,
                  record.peakLuminance >= ExportGainMapEncoder.sdrReferenceWhite
            else {
                throw AppError.invalidParameter(
                    "export gainMapHDR requires peakLuminance ≥ "
                        + "\(ExportGainMapEncoder.sdrReferenceWhite) nits (the SDR "
                        + "reference white — headroom = peak/203 ≥ 1.0), got "
                        + "\(record.peakLuminance)")
            }
            guard !isHdrEncoding(record.encodingEotf) else {
                throw AppError.invalidParameter(
                    "export gainMapHDR requires an SDR encoding EOTF — a "
                        + "st2084/hlg base is not an SDR rendition, the gain "
                        + "ratios would be taken over PQ/HLG code values "
                        + "(D-M6-3-7), got \(record.encodingEotf)")
            }
            guard embedICC else {
                throw AppError.invalidParameter(
                    "export gainMapHDR requires embedICC — a post-encode ICC "
                        + "strip deletes the APP2 segment and invalidates the "
                        + "MPF subimage absolute offsets (RESEARCH §8.4)")
            }
            guard !yiyin else {
                throw AppError.invalidParameter(
                    "export gainMapHDR cannot ride the yiyin face — borders/"
                        + "watermark replay after the EotfBox, so the SDR base "
                        + "canvas can exceed the captured HDR plane (gain map "
                        + "semantics undefined)")
            }
        }
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
    case .bounds(let w, let h):
        return "\(w)x\(h)" // M2-9-01 KD-5#2 (planner ruling, DECISIONS)
    case .physical:
        return variant.format.formatName // same fallback rule as original
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
