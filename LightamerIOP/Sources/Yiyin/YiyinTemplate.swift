import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// YiyinTemplate (Plan 08-2 T3) — the yiyin watermark template ENGINE: the
// `{Field}` placeholder matcher, the ITemp/IFieldInfoItem config records,
// the 3 system templates, and the field-fill resolution that turns a
// template pattern + EXIF values + field overrides into INTERLEAVED
// literal/slot rows (the genTextImg flow's string face — the CoreText
// MEASUREMENT face lives in YiyinTextRenderer, T4).
//
// Spec sources (yiyin v1.7.1, read-only):
//   common/utils/temp.ts:1-22       matchFields (`\{([A-Z0-9]+)\}` gi)
//   common/const/def-temps.ts       ITemp + the 3 system templates
//   common/const/def-fields.ts      the 15 field keys
//   electron/src/config.ts:73-95    field defaults (show true / use false /
//                                   forceUse false / type text / font unused)
//   web/modules/temp-field/index.ts:40-50   getTextTempList (row font px
//                                   scale + backdrop color fallback)
//   web/modules/temp-field/index.ts:58-107  fillTempFieldInfo (exif value +
//                                   Make logo attempt + use/forceUse override)
//   web/modules/text-tool/index.ts:46-117   genTextImg (the {---} interleave,
//                                   skip-row rules, literal caseType)
//
// FAITHFUL QUIRKS kept verbatim (tests pin each):
// - JS `String.replace(temp, …)` replaces the FIRST occurrence only.
// - A hidden field's placeholder is REMOVED from the literal text.
// - Slot values TRIM (`${value}.trim()`) — leading spaces from the brand
//   normalization quirks vanish at the slot face, not the format layer.
// - Only `Make` attempts a brand logo (LensMake never does — yiyin :80-93).
// - No logo asset → the Make slot DEGRADES TO TEXT (the normalized make
//   string), never dropped for that reason.
// - Row default color = backdrop-derived: blur → white, solid → black
//   (getTextTempList's `solid_bg ? '#000' : '#fff'`; borders absent counts
//   as solid — D-08-CONTEXT Specific Ideas).
// - Case rules: literals take the ROW font's caseType here; slot values
//   take the MERGED slot font's caseType at the renderer (T4).
// ─────────────────────────────────────────────────────────────────────────

// MARK: - Config records

/// The text case rule (yiyin `caseType`).
public enum YiyinCaseType: String, Codable, Hashable, Sendable {
    case `default`
    case lowcase
    case upcase

    /// Apply the rule at the STRING layer (yiyin text-tool :87-91,143-152).
    public func apply(_ s: String) -> String {
        switch self {
        case .default: return s
        case .lowcase: return s.lowercased()
        case .upcase: return s.uppercased()
        }
    }
}

/// The slot vertical alignment (yiyin `verticalAlign`).
public enum YiyinVerticalAlign: String, Codable, Hashable, Sendable {
    case baseline
    case center
}

/// A watermark font spec (yiyin `IFont`) — `sizePercent` is the yiyin
/// `size` (a PERCENT of the canvas height); `name` "" = the PingFang SC
/// default face; `color` "" = the backdrop-derived row default.
public struct YiyinFont: Codable, Hashable, Sendable {
    public var name: String
    public var bold: Bool
    public var italic: Bool
    public var sizePercent: Double
    public var color: String
    public var caseType: YiyinCaseType

    public init(
        name: String = "",
        bold: Bool = false,
        italic: Bool = false,
        sizePercent: Double = 2.2,
        color: String = "",
        caseType: YiyinCaseType = .default
    ) {
        self.name = name
        self.bold = bold
        self.italic = italic
        self.sizePercent = sizePercent
        self.color = color
        self.caseType = caseType
    }
}

/// A per-field font OVERRIDE (yiyin `IFontParam`: `Partial<IFont> & {use}` —
/// non-nil/non-empty fields win over the row font when `use`).
public struct YiyinFontOverride: Codable, Hashable, Sendable {
    public var use: Bool
    public var name: String?
    public var bold: Bool?
    public var italic: Bool?
    public var sizePercent: Double?
    public var color: String?
    public var caseType: YiyinCaseType?

    public init(
        use: Bool = false, name: String? = nil, bold: Bool? = nil,
        italic: Bool? = nil, sizePercent: Double? = nil,
        color: String? = nil, caseType: YiyinCaseType? = nil
    ) {
        self.use = use
        self.name = name
        self.bold = bold
        self.italic = italic
        self.sizePercent = sizePercent
        self.color = color
        self.caseType = caseType
    }
}

/// One template row (yiyin `ITemp`). `key` is the STABLE identity the panel
/// rows address (`yiyin.template.row.<key>`, L010 — never an index).
/// `rotation` is the v2 RESERVED seat (Codable forward-compatibility,
/// D-08-CONTEXT-2) — never consumed by v1 rendering.
public struct YiyinTemplate: Codable, Hashable, Sendable {
    public var key: String
    public var name: String
    public var pattern: String
    public var use: Bool
    public var verticalAlign: YiyinVerticalAlign
    public var font: YiyinFont
    public var rotation: Double?

    public init(
        key: String, name: String, pattern: String, use: Bool,
        verticalAlign: YiyinVerticalAlign = .baseline, font: YiyinFont = YiyinFont(),
        rotation: Double? = nil
    ) {
        self.key = key
        self.name = name
        self.pattern = pattern
        self.use = use
        self.verticalAlign = verticalAlign
        self.font = font
        self.rotation = rotation
    }
}

/// The slot content type (yiyin `IFieldInfoItem.type`).
public enum YiyinSlotType: String, Codable, Hashable, Sendable {
    case text
    case logo
}

/// The logo light/dark variant (yiyin `-w.svg` / `-b.svg`; `.auto` reads
/// the borders backdrop — D-08-CONTEXT Specific Ideas).
public enum YiyinLogoVariant: String, Codable, Hashable, Sendable {
    case auto
    case black
    case white

    /// The concrete variant for `.auto` under the given backdrop.
    public func resolved(backdropIsBlur: Bool) -> YiyinLogoVariant {
        switch self {
        case .auto: return backdropIsBlur ? .white : .black
        case .black: return .black
        case .white: return .white
        }
    }
}

/// One field config (yiyin `IFieldInfoItem` + the Lightamer logoVariant
/// addition, D-08-CONTEXT-2). Semantics (yiyin config defaults + fill):
/// `show` gates the placeholder entirely; `use` arms the CUSTOM override;
/// with `use`, `forceUse` overrides ALWAYS and otherwise only when the
/// EXIF value is empty.
public struct YiyinField: Codable, Hashable, Sendable {
    public var key: String
    public var show: Bool
    public var use: Bool
    public var forceUse: Bool
    public var customValue: String
    public var type: YiyinSlotType
    public var logoVariant: YiyinLogoVariant
    public var font: YiyinFontOverride?

    public init(
        key: String, show: Bool = true, use: Bool = false, forceUse: Bool = false,
        customValue: String = "", type: YiyinSlotType = .text,
        logoVariant: YiyinLogoVariant = .auto, font: YiyinFontOverride? = nil
    ) {
        self.key = key
        self.show = show
        self.use = use
        self.forceUse = forceUse
        self.customValue = customValue
        self.type = type
        self.logoVariant = logoVariant
        self.font = font
    }
}

// MARK: - The 3 system templates (def-temps.ts verbatim)

extension YiyinTemplate {

    /// `{Make} {Model}` — the logo/model row (size 3, bold).
    public static func makeModel() -> YiyinTemplate {
        YiyinTemplate(
            key: "make-model", name: "Logo型号模版", pattern: "{Make} {Model}",
            use: true,
            font: YiyinFont(bold: true, sizePercent: 3))
    }

    /// The 等效焦距 parameters row (size 2.2, bold).
    public static func exifParams35mm() -> YiyinTemplate {
        YiyinTemplate(
            key: "exif-params", name: "参数模版 - 等效焦距",
            pattern: "{FocalLengthIn35mmFormat}mm f/{FNumber} {ExposureTime}s ISO{ISO}",
            use: true,
            font: YiyinFont(bold: true, sizePercent: 2.2))
    }

    /// The 原始焦距 parameters row (size 2.2, bold, OFF in yiyin defaults).
    public static func exifParamsFocal() -> YiyinTemplate {
        YiyinTemplate(
            key: "exif-params-1", name: "参数模版 - 原始焦距",
            pattern: "{FocalLength}mm f/{FNumber} {ExposureTime}s ISO{ISO}",
            use: false,
            font: YiyinFont(bold: true, sizePercent: 2.2))
    }

    /// The yiyin default catalog (def-temps.ts order).
    public static func systemDefaults() -> [YiyinTemplate] {
        [makeModel(), exifParams35mm(), exifParamsFocal()]
    }
}

// MARK: - Placeholder matching (common/utils/temp.ts matchFields)

public enum YiyinTemplateEngine {

    /// One matched `{FIELD}` placeholder — `temp` the full `{…}` token,
    /// `field` the inner name (first-occurrence order, deduped by field).
    public struct FieldMatch: Equatable, Sendable {
        public var temp: String
        public var field: String
    }

    /// `matchFields` — `\{([A-Z0-9]+)\}` with the `gi` case-insensitivity
    /// (lowercase braces/letters match too), FIRST-occurrence order,
    /// deduped by field name (yiyin builds a record keyed by field).
    public static func matchFields(_ str: String) -> [FieldMatch] {
        guard !str.isEmpty else { return [] }
        // The yiyin regex is [A-Z0-9] with the `i` flag; NSRegularExpression
        // takes the widened class instead.
        guard let regex = try? NSRegularExpression(pattern: #"\{([A-Za-z0-9]+)\}"#) else {
            return []
        }
        let range = NSRange(str.startIndex..., in: str)
        var seen = Set<String>()
        var out: [FieldMatch] = []
        for match in regex.matches(in: str, range: range) {
            guard let full = Range(match.range, in: str),
                let inner = Range(match.range(at: 1), in: str)
            else { continue }
            let field = String(str[inner])
            // yiyin: `if (field) fields[field] = …` — the record-key dedup.
            if seen.insert(field).inserted {
                out.append(FieldMatch(temp: String(str[full]), field: field))
            }
        }
        return out
    }

    // MARK: - Resolution (fillTempFieldInfo + genTextImg's string face)

    /// One resolved slot — a TEXT value or a LOGO request.
    public enum ResolvedSlot: Equatable, Sendable {
        case text(String)
        case logo(make: String, variant: YiyinLogoVariant)
        case customLogo(name: String)
    }

    /// One item of a resolved row: a literal segment (row caseType ALREADY
    /// applied — the yiyin genTextImg loop) or a slot.
    public enum ResolvedItem: Equatable, Sendable {
        case literal(String)
        case slot(ResolvedSlot, font: YiyinFontOverride, sizePx: Double)
    }

    /// A fully resolved row ready for the renderer: `fontPx` is the row
    /// font in px (`bgHeight × sizePercent/100` — JS float, NOT rounded;
    /// field fonts round, temp-field/index.ts:26).
    public struct ResolvedRow: Equatable, Sendable {
        public var items: [ResolvedItem]
        public var font: YiyinFont
        public var fontPx: Double
        public var color: String
        public var verticalAlign: YiyinVerticalAlign
    }

    /// The logo existence probe (the yiyin `loadImage(wImg/bImg)` face):
    /// return true when the brand logo asset exists for the given
    /// normalized-make key and variant. The store wires this (T5); nil =
    /// no asset store → every Make degrades to text.
    public typealias LogoExists = @Sendable (_ makeKey: String, _ variant: YiyinLogoVariant) -> Bool

    /// Resolution inputs.
    public struct Inputs: Sendable {
        /// The formatted display values (YiyinExifFormat.fields).
        public var fields: [YiyinExifField: String]
        /// The field CONFIGS (keyed by the YiyinExifField rawValue).
        public var fieldConfigs: [String: YiyinField]
        /// The row-level default font (the yiyin `options.font` + the
        /// panel's default font settings).
        public var defaultFont: YiyinFont
        /// The backdrop-derived row color fallback (blur → white, solid →
        /// black — getTextTempList's face).
        public var backdropIsBlur: Bool
        /// The pass-1 canvas height (the font % basis, yiyin `opt.bgHeight`).
        public var bgHeight: Double
        public var logoExists: LogoExists?

        public init(
            fields: [YiyinExifField: String], fieldConfigs: [String: YiyinField],
            defaultFont: YiyinFont, backdropIsBlur: Bool, bgHeight: Double,
            logoExists: LogoExists? = nil
        ) {
            self.fields = fields
            self.fieldConfigs = fieldConfigs
            self.defaultFont = defaultFont
            self.backdropIsBlur = backdropIsBlur
            self.bgHeight = bgHeight
            self.logoExists = logoExists
        }
    }

    /// Resolve one template into a row, or nil when the row SKIPS (the
    /// yiyin skip rules: an empty trimmed pattern, or a fielded pattern
    /// whose slots all dropped).
    public static func resolve(
        template: YiyinTemplate, inputs: Inputs
    ) -> ResolvedRow? {
        let text = template.pattern.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        // Row font scale (getTextTempList: `size: bgHeight × (size/100)` —
        // JS float for the TEMPLATE font) + the family/color fallbacks.
        var rowFont = template.font
        if rowFont.name.isEmpty { rowFont.name = inputs.defaultFont.name }
        if rowFont.color.isEmpty {
            rowFont.color = inputs.backdropIsBlur ? "#ffffff" : "#000000"
        }
        let rowFontPx = inputs.bgHeight * (rowFont.sizePercent / 100)
        let rowCase = rowFont.caseType

        let matches = matchFields(text)
        var items: [ResolvedItem] = []

        if matches.isEmpty {
            // The no-field face: the whole pattern is one literal.
            items.append(.literal(rowCase.apply(text)))
        } else {
            // yiyin genTextImg: shown placeholders become '{---}' markers
            // (FIRST occurrence per field) in match order, each shown
            // field pushes a slot entry (valid or the '' drop) in the SAME
            // order; hidden placeholders are removed with NO entry.
            var work = text
            var slots: [ResolvedItem?] = []
            for match in matches {
                let config = inputs.fieldConfigs[match.field]
                let shown = config?.show ?? false
                guard shown else {
                    // A template referencing an UNCONFIGURED field: yiyin
                    // crashes on undefined.show; Lightamer treats it as
                    // hidden (D-08-2-5) — the placeholder is removed.
                    work = work.replacingOccurrences(of: match.temp, with: "")
                    continue
                }
                work = work.replacingOccurrences(
                    of: match.temp, with: "{---}",
                    range: firstRange(of: match.temp, in: work))
                slots.append(resolveSlot(field: match.field, config: config, inputs: inputs))
            }

            // yiyin trims the WHOLE string before the split.
            let segments = work.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: "{---}")
            // The skip rule (genTextImg): one all-empty literal segment, or
            // segments but zero valid slots.
            let validSlots = slots.compactMap { $0 }
            if segments.count == 1 {
                if segments[0].trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            } else if validSlots.isEmpty {
                return nil
            }

            // Segment j PRECEDES slot j (slot j sits BETWEEN segment j and
            // j+1 — the yiyin push(commonText_j, slot_j) pair order); the
            // final segment has no slot. Empty literals drop (yiyin keeps
            // them in the list; createTextImg's filter(Boolean) removes
            // them — same width/render face).
            for (index, segment) in segments.enumerated() {
                if !segment.isEmpty {
                    items.append(.literal(rowCase.apply(segment)))
                }
                if index < slots.count, let slot = slots[index] {
                    items.append(slot)
                }
            }
        }

        guard !items.isEmpty else { return nil }
        return ResolvedRow(
            items: items, font: rowFont, fontPx: rowFontPx, color: rowFont.color,
            verticalAlign: template.verticalAlign)
    }

    /// Resolve ONE field slot, or nil when the slot DROPS (empty value).
    private static func resolveSlot(
        field: String, config: YiyinField?, inputs: Inputs
    ) -> ResolvedItem? {
        guard let key = YiyinExifField(rawValue: field) else {
            return nil // an unknown field name has no EXIF source
        }
        let config = config ?? YiyinField(key: field)

        // The EXIF display value (fillTempFieldInfo `_info`).
        var value = inputs.fields[key] ?? ""
        var type: YiyinSlotType = .text
        var logoRequest: ResolvedSlot? = nil

        if key == .make, !value.isEmpty {
            // The Make logo attempt (:80-93) — ONLY for Make; the key is
            // the lower-cased NORMALIZED make (yiyin `{make}-w.svg`).
            let makeKey = value.lowercased()
            let variant = config.logoVariant.resolved(backdropIsBlur: inputs.backdropIsBlur)
            if inputs.logoExists?(makeKey, variant) == true {
                type = .logo
                logoRequest = .logo(make: makeKey, variant: variant)
            }
        }

        // The custom override (fillTempFieldInfo tail): armed by `use` and
        // (forceUse OR an empty EXIF value).
        if config.use, config.forceUse || value.isEmpty {
            type = config.type
            value = config.customValue
            logoRequest = nil
            if config.type == .logo {
                logoRequest = config.customValue.isEmpty
                    ? nil : .customLogo(name: config.customValue)
            }
        }

        // The slot value TRIMS (genTextImg `${value}.trim()`).
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil } // the `push(slotInfo.value ? slotInfo : '')` drop

        let sizePx: Double
        if let override = config.font, override.use, let pct = override.sizePercent, pct > 0 {
            // Field fonts ROUND to px (temp-field/index.ts:26).
            sizePx = (inputs.bgHeight * (pct / 100)).rounded()
        } else {
            sizePx = 0 // 0 = inherit the row font (no override size)
        }
        switch type {
        case .text:
            return .slot(.text(trimmed), font: config.font ?? YiyinFontOverride(), sizePx: sizePx)
        case .logo:
            if let request = logoRequest {
                return .slot(request, font: config.font ?? YiyinFontOverride(), sizePx: sizePx)
            }
            // A logo config with no resolvable asset degrades to the text
            // value (the Make no-asset face).
            return .slot(.text(trimmed), font: config.font ?? YiyinFontOverride(), sizePx: sizePx)
        }
    }

    private static func firstRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        haystack.range(of: needle)
    }
}
