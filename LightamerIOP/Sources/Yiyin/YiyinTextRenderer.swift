import CoreText
import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// YiyinTextRenderer (Plan 08-2 T4) — the CoreText row renderer: per-slot
// measurement + the row bitmap (yiyin web/modules/text-tool/index.ts
// createTextImg :126-267, L017 route — NO bitmap parity with Chromium
// canvas; the GEOMETRY formulas are same-shape and the bitmap is a
// CoreText SELF-baseline golden, D-08-CONTEXT-8).
//
// yiyin formula faces kept same-shape (each pinned by tests):
//   slot px        field fonts ROUND to px (temp-field :26); the row font
//                  stays a JS float (getTextTempList :46-49)
//   getMaxFontParam :302-320   max slot size + bold OR → the canvas height
//                  driver, measured on the CONCATENATED text (or the
//                  'QOSyYtl709' pseudo-string when a logo slot exists —
//                  yiyin's :199 verbatim face; the slot-loop pseudo-string
//                  is the DIFFERENT 'QSOPNYuiyl90' — kept verbatim too)
//   canvas height  ceil(max(ascent+descent+2×textMargin, maxFontPx))
//   canvas width   30 + Σ slot widths + 30 (the :176/:250 pads)
//   baseline       ceil(ascent of the max-font whole-text measure)
//   slot y         verticalAlign baseline/center formulas at 2-decimal
//                  rounding (roundDecimalPlaces(x, 2))
//   logo slot      h = ceil(ascent('QSOPNYuiyl90')), w = ceil(h × aspect)
//
// DOCUMENTED DIVERGENCES (08-2-DECISIONS D-08-2-7):
// - Slot ascent/descent come from CTLineGetTypographicBounds (font
//   metrics), not canvas INK bounds (actualBoundingBox*) — sub-pixel
//   differences are the self-baseline golden's own business.
// - Slot width = ceil(advance width) (the `info.width` half of yiyin's
//   max(ink, advance) — ink measurement has no CT equivalent).
// - Logo opacity bakes into the bitmap alpha at draw time (the CGContext
//   global alpha over the logo slot's rect) — the Metal composite stays a
//   plain premultiplied-over.
// - The bitmap is 8-bit sRGB-ENCODED premultiplied RGBA; the Metal leg
//   decodes with the sRGB EOTF and converts primaries per COLOR-2 (the
//   sRGB-framebuffer-blend face).
//
// CACHE (L013): key = StableHash over the ParamsCoding-encoded determinant
// set (pattern ⊕ slots ⊕ fonts ⊕ bgHeight ⊕ lineSpacing ⊕ align ⊕ colors ⊕
// logo refs) — a borders-blur-only param edit leaves every row key
// unchanged → all HITs. FIFO eviction at a small budget.
// ─────────────────────────────────────────────────────────────────────────

/// A resolved logo image the renderer draws into a logo slot (the
/// YiyinLogoStore's product — T5; tests provide fixtures). `@unchecked
/// Sendable`: CGImage is immutable (documented thread-safe).
public struct YiyinLogoImage: @unchecked Sendable {
    public let image: CGImage
    /// width / height of the SOURCE artwork (the yiyin
    /// `i.value.width / i.value.height` aspect face).
    public let aspect: Double

    public init(image: CGImage, aspect: Double) {
        self.image = image
        self.aspect = aspect
    }
}

public typealias YiyinLogoProvider =
    @Sendable (_ request: YiyinTemplateEngine.ResolvedSlot) -> YiyinLogoImage?

/// The rendered row bitmap — 8-bit sRGB-ENCODED premultiplied RGBA
/// (top-left origin), ready for texture upload.
public struct YiyinRowBitmap {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

public final class YiyinTextRenderer: @unchecked Sendable {

    public init() {}

    // MARK: - Cache accounting (the MISS/HIT 记账 tests read these)

    public private(set) var cacheHits = 0
    public private(set) var cacheMisses = 0
    public static let cacheBudget = 48
    private var cache: [UInt64: YiyinRowBitmap] = [:]
    private var cacheOrder: [UInt64] = []
    private let cacheLock = NSLock()

    public func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeAll()
        cacheOrder.removeAll()
    }

    /// The live cache entry count (the eviction test's probe).
    var cacheKeysCount: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache.count
    }

    // MARK: - Determinants (the L013 cache key)

    struct CacheKey: Codable {
        var pattern: String
        var rowFont: YiyinFont
        var fontPx: Double
        var color: String
        var verticalAlign: String
        var lineSpacingPercent: Double
        var bgHeight: Double
        var logoOpacity: Double
        var slots: [SlotKey]
    }

    struct SlotKey: Codable {
        enum Kind: String, Codable {
            case literal, text, logo, customLogo
        }
        var kind: Kind
        var value: String
        var variant: String?
        var use: Bool
        var name: String?
        var bold: Bool?
        var italic: Bool?
        var sizePx: Double
        var color: String?
        var caseType: String?
    }

    func cacheKey(
        row: YiyinTemplateEngine.ResolvedRow, bgHeight: Double, lineSpacingPercent: Double,
        logoOpacity: Double
    ) -> CacheKey {
        func slotKey(_ item: YiyinTemplateEngine.ResolvedItem) -> SlotKey {
            switch item {
            case .literal(let s):
                return SlotKey(
                    kind: .literal, value: s, variant: nil, use: false, name: nil,
                    bold: nil, italic: nil, sizePx: 0, color: nil, caseType: nil)
            case .slot(let slot, let font, let sizePx):
                let kind: SlotKey.Kind
                let value: String
                let variant: String?
                switch slot {
                case .text(let v): kind = .text; value = v; variant = nil
                case .logo(let make, let v): kind = .logo; value = make; variant = v.rawValue
                case .customLogo(let name): kind = .customLogo; value = name; variant = nil
                }
                return SlotKey(
                    kind: kind, value: value, variant: variant, use: font.use,
                    name: font.name, bold: font.bold, italic: font.italic,
                    sizePx: sizePx, color: font.color, caseType: font.caseType?.rawValue)
            }
        }
        return CacheKey(
            pattern: "row", rowFont: row.font, fontPx: row.fontPx, color: row.color,
            verticalAlign: row.verticalAlign.rawValue, lineSpacingPercent: lineSpacingPercent,
            bgHeight: bgHeight, logoOpacity: logoOpacity, slots: row.items.map(slotKey))
    }

    // MARK: - Font helpers (getFont :269-300 face)

    /// `getFont` — the family falls back to PingFang SC; bold/italic ride
    /// the symbolic traits.
    static func ctFont(name: String, size: Double, bold: Bool, italic: Bool) -> CTFont {
        let family = name.isEmpty ? "PingFang SC" : name
        let base = CTFontCreateWithName(family as CFString, CGFloat(size), nil)
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.boldTrait) }
        if italic { traits.insert(.italicTrait) }
        guard !traits.isEmpty else { return base }
        if let styled = CTFontCreateCopyWithSymbolicTraits(
            base, CGFloat(size), nil, traits, traits)
        {
            return styled
        }
        return base
    }

    /// Merge a slot's font override onto the row font (mergeFontParam +
    /// getFont's size face: the override wins field-by-field when `use`;
    /// the size resolves in PX here — the row fontPx float vs the rounded
    /// field px asymmetry happened at resolution time).
    static func mergedSlotFont(
        row: YiyinTemplateEngine.ResolvedRow, override: YiyinFontOverride, sizePx: Double
    ) -> (name: String, bold: Bool, italic: Bool, size: Double, color: String, caseType: YiyinCaseType) {
        let use = override.use
        let name = use ? (override.name ?? row.font.name) : row.font.name
        let bold = use ? (override.bold ?? row.font.bold) : row.font.bold
        let italic = use ? (override.italic ?? row.font.italic) : row.font.italic
        let size = (use && sizePx > 0) ? sizePx : row.fontPx
        let color = use ? (override.color ?? row.color) : row.color
        let caseType = use ? (override.caseType ?? row.font.caseType) : row.font.caseType
        return (name, bold, italic, size, color, caseType)
    }

    private static func metrics(
        _ s: String, font: CTFont
    ) -> (ascent: Double, descent: Double, width: Double) {
        let attributed = NSMutableAttributedString(string: s)
        attributed.addAttribute(
            kCTFontAttributeName as NSAttributedString.Key, value: font,
            range: NSRange(location: 0, length: attributed.length))
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (Double(ascent), Double(descent), Double(width))
    }

    /// roundDecimalPlaces(x, 2).
    private static func round2(_ x: Double) -> Double {
        (x * 100).rounded() / 100
    }

    /// The pseudo-string ascent probe for LOGO slots (:199-202 — the
    /// `'QSOPNYuiyl90'` face; the whole-text pseudo 'QOSyYtl709' differs
    /// and lives in `layout`).
    static let slotLogoPseudo = "QSOPNYuiyl90"
    /// The whole-text pseudo-string when a logo slot is present (:199).
    static let canvasPseudo = "QOSyYtl709"

    // MARK: - Layout (createTextImg's measurement face)

    /// The row's pixel metrics (the YiyinLayout.TextRowMetrics product).
    /// `logoProvider` supplies logo aspects (measure and render MUST see
    /// the same answers — the module passes one closure to both).
    public func layoutRow(
        row: YiyinTemplateEngine.ResolvedRow,
        bgHeight: Double,
        lineSpacingPercent: Double,
        logoProvider: YiyinLogoProvider?
    ) -> (metrics: YiyinLayout.TextRowMetrics, detail: RowLayout) {
        // getMaxFontParam (:302-320) — the max size + bold OR across the
        // USED slot overrides.
        var maxFontPx = row.fontPx
        var anyBold = row.font.bold
        for item in row.items {
            guard case .slot(_, let font, let sizePx) = item, font.use else { continue }
            if font.bold == true { anyBold = true }
            if sizePx > maxFontPx { maxFontPx = sizePx }
        }

        // The whole-text measure (:193-199) — the CONCATENATED values at
        // the max font, or the pseudo-string when a logo slot exists.
        var total = ""
        var hasLogo = false
        for item in row.items {
            switch item {
            case .literal(let s): total += s
            case .slot(.text(let v), let font, let sizePx):
                let merged = Self.mergedSlotFont(row: row, override: font, sizePx: sizePx)
                total += merged.caseType.apply(v)
            case .slot(.logo, _, _), .slot(.customLogo, _, _):
                hasLogo = true
            }
        }
        let maxFont = Self.ctFont(
            name: row.font.name, size: maxFontPx, bold: anyBold, italic: row.font.italic)
        let whole = Self.metrics(hasLogo ? Self.canvasPseudo : total, font: maxFont)
        let baseline = whole.ascent.rounded(.up) // Math.ceil(actualBoundingBoxAscent)

        let textMargin = bgHeight * (lineSpacingPercent / 100)
        let canvasHeight = Int(
            max(whole.ascent + whole.descent + textMargin * 2, maxFontPx).rounded(.up))

        // Per-slot layout (:204-249).
        var slots: [RowLayout.Slot] = []
        var width: Double = 30
        for item in row.items {
            switch item {
            case .literal(let s):
                guard !s.trimmingCharacters(in: .whitespaces).isEmpty || !s.isEmpty else {
                    continue
                }
                // yiyin skips only leading/trailing WHITESPACE-ONLY
                // entries; interior whitespace measures normally. Our
                // engine already dropped empty strings — keep the rest.
                let font = Self.ctFont(
                    name: row.font.name, size: row.fontPx, bold: row.font.bold,
                    italic: row.font.italic)
                let m = Self.metrics(s, font: font)
                let w = Int(m.width.rounded(.up))
                let h = Int((m.ascent + m.descent).rounded(.up))
                let y: Double = row.verticalAlign == .center
                    ? Self.round2(Double(h) + (Double(canvasHeight) - Double(h)) / 2)
                    : Self.round2(baseline + (Double(canvasHeight) - baseline) / 2)
                slots.append(
                    .init(kind: .text(s), x: width, y: y, w: w, h: h,
                          fontName: row.font.name, bold: row.font.bold,
                          italic: row.font.italic, sizePx: row.fontPx, color: row.color))
                width += Double(w)
            case .slot(.text(let value), let fontOverride, let sizePx):
                let merged = Self.mergedSlotFont(
                    row: row, override: fontOverride, sizePx: sizePx)
                let applied = merged.caseType.apply(value)
                let font = Self.ctFont(
                    name: merged.name, size: merged.size, bold: merged.bold, italic: merged.italic)
                let m = Self.metrics(applied, font: font)
                let w = Int(m.width.rounded(.up))
                let h = Int((m.ascent + m.descent).rounded(.up))
                let y: Double = row.verticalAlign == .center
                    ? Self.round2(Double(h) + (Double(canvasHeight) - Double(h)) / 2)
                    : Self.round2(baseline + (Double(canvasHeight) - baseline) / 2)
                slots.append(
                    .init(kind: .text(applied), x: width, y: y, w: w, h: h,
                          fontName: merged.name, bold: merged.bold, italic: merged.italic,
                          sizePx: merged.size, color: merged.color))
                width += Double(w)
            case .slot(.logo(let make, let variant), let fontOverride, let sizePx):
                guard let image = logoProvider?(.logo(make: make, variant: variant)) else {
                    continue // the provider dropped it — whitespace only
                }
                let merged = Self.mergedSlotFont(
                    row: row, override: fontOverride, sizePx: sizePx)
                let probe = Self.ctFont(
                    name: merged.name, size: merged.size, bold: merged.bold, italic: merged.italic)
                let pseudo = Self.metrics(Self.slotLogoPseudo, font: probe)
                let h = Int(pseudo.ascent.rounded(.up))
                let w = Int((Double(h) * image.aspect).rounded(.up))
                let y: Double = row.verticalAlign == .baseline
                    ? Self.round2(
                        baseline - Double(h) + Double(h) * 0.03
                            + (Double(canvasHeight) - baseline) / 2)
                    : Self.round2((Double(canvasHeight) - Double(h)) / 2)
                slots.append(
                    .init(kind: .logo(image.image), x: width, y: y, w: w, h: h,
                          fontName: merged.name, bold: merged.bold, italic: merged.italic,
                          sizePx: merged.size, color: merged.color))
                width += Double(w)
            case .slot(.customLogo(let name), let fontOverride, let sizePx):
                guard let image = logoProvider?(.customLogo(name: name)) else { continue }
                let merged = Self.mergedSlotFont(
                    row: row, override: fontOverride, sizePx: sizePx)
                let probe = Self.ctFont(
                    name: merged.name, size: merged.size, bold: merged.bold, italic: merged.italic)
                let pseudo = Self.metrics(Self.slotLogoPseudo, font: probe)
                let h = Int(pseudo.ascent.rounded(.up))
                let w = Int((Double(h) * image.aspect).rounded(.up))
                let y: Double = row.verticalAlign == .baseline
                    ? Self.round2(
                        baseline - Double(h) + Double(h) * 0.03
                            + (Double(canvasHeight) - baseline) / 2)
                    : Self.round2((Double(canvasHeight) - Double(h)) / 2)
                slots.append(
                    .init(kind: .logo(image.image), x: width, y: y, w: w, h: h,
                          fontName: merged.name, bold: merged.bold, italic: merged.italic,
                          sizePx: merged.size, color: merged.color))
                width += Double(w)
            }
        }
        width += 30 // the :250 trailing pad

        let detail = RowLayout(
            width: Int(width), height: canvasHeight, baseline: baseline, slots: slots)
        return (YiyinLayout.TextRowMetrics(width: detail.width, height: detail.height), detail)
    }

    /// The fully-resolved row layout (the draw plan + the formulas' output
    /// — what the geometry tests assert).
    public struct RowLayout {
        public var width: Int
        public var height: Int
        public var baseline: Double

        public enum SlotContent {
            case text(String)
            case logo(CGImage)
        }

        public struct Slot {
            public var kind: SlotContent
            public var x: Double
            public var y: Double
            public var w: Int
            public var h: Int
            public var fontName: String
            public var bold: Bool
            public var italic: Bool
            public var sizePx: Double
            public var color: String
        }

        public var slots: [Slot]
    }

    // MARK: - Render (the bitmap face)

    /// Render (or fetch) the row bitmap. The cache key covers the full
    /// determinant set — an unrelated param edit (blur amount etc.) never
    /// changes it.
    public func renderRow(
        row: YiyinTemplateEngine.ResolvedRow,
        bgHeight: Double,
        lineSpacingPercent: Double,
        logoOpacity: Double,
        logoProvider: YiyinLogoProvider?
    ) -> YiyinRowBitmap {
        let key = cacheKey(
            row: row, bgHeight: bgHeight, lineSpacingPercent: lineSpacingPercent,
            logoOpacity: logoOpacity)
        let hash = StableHash.hash(ParamsCoding.encode(key))
        cacheLock.lock()
        if let cached = cache[hash] {
            cacheHits += 1
            cacheLock.unlock()
            return cached
        }
        cacheMisses += 1
        cacheLock.unlock()

        let (_, layout) = layoutRow(
            row: row, bgHeight: bgHeight, lineSpacingPercent: lineSpacingPercent,
            logoProvider: logoProvider)
        let bitmap = Self.draw(layout: layout, logoOpacity: logoOpacity)

        cacheLock.lock()
        cache[hash] = bitmap
        cacheOrder.append(hash)
        if cacheOrder.count > Self.cacheBudget {
            let evict = cacheOrder.removeFirst()
            cache.removeValue(forKey: evict)
        }
        cacheLock.unlock()
        return bitmap
    }

    /// The CoreText/CG draw (deterministic per system — the golden basis).
    static func draw(layout: RowLayout, logoOpacity: Double) -> YiyinRowBitmap {
        let width = max(layout.width, 1)
        let height = max(layout.height, 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return YiyinRowBitmap(width: width, height: height, pixels: pixels)
        }
        // Deterministic GRAY antialiasing: subpixel positioning produces
        // per-channel coverage (colored glyph edges) — off for the
        // self-baseline golden's r=g=b=a white face (D-08-2-7).
        ctx.setAllowsFontSubpixelPositioning(false)
        ctx.setShouldSubpixelPositionFonts(false)
        ctx.setAllowsFontSubpixelQuantization(true)
        ctx.setShouldSubpixelQuantizeFonts(true)
        // Solid colors: set the fill color per slot (the hex parse degrades
        // to black — yiyin `|| '#000'`).
        var currentFill = CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!
        func setFill(_ hex: String) {
            let components = YiyinColor.parseSRGBHex(hex) ?? SIMD3(0, 0, 0)
            currentFill = CGColor(
                colorSpace: colorSpace,
                components: [components.x, components.y, components.z, 1])!
            ctx.setFillColor(currentFill)
        }
        for slot in layout.slots {
            switch slot.kind {
            case .text(let s):
                setFill(slot.color)
                let font = ctFont(
                    name: slot.fontName, size: slot.sizePx, bold: slot.bold, italic: slot.italic)
                let attributed = NSMutableAttributedString(string: s)
                attributed.addAttribute(
                    kCTFontAttributeName as NSAttributedString.Key, value: font,
                    range: NSRange(location: 0, length: attributed.length))
                // CTLineDraw does NOT consume the context fill color — the
                // foreground rides the attributes (probed: context-only
                // fill renders black, D-08-2-7 note).
                attributed.addAttribute(
                    kCTForegroundColorAttributeName as NSAttributedString.Key,
                    value: currentFill, range: NSRange(location: 0, length: attributed.length))
                let line = CTLineCreateWithAttributedString(attributed)
                // fillText(x, y) = the BASELINE position (top-left space) →
                // the CG bottom-left conversion.
                ctx.textPosition = CGPoint(x: slot.x, y: Double(height) - slot.y)
                CTLineDraw(line, ctx)
            case .logo(let image):
                ctx.saveGState()
                ctx.setAlpha(CGFloat(logoOpacity))
                let rect = CGRect(
                    x: slot.x, y: Double(height) - slot.y - Double(slot.h),
                    width: Double(slot.w), height: Double(slot.h))
                ctx.draw(image, in: rect)
                ctx.restoreGState()
            }
        }
        return YiyinRowBitmap(width: width, height: height, pixels: pixels)
    }
}
