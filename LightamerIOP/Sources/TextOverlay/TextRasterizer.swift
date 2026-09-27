import CoreText
import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────
// TextRasterizer (Plan 08-5 T2) — the CoreText leg of the text overlay:
// multi-line layout → gray-AA coverage bitmap (1 byte/px).
//
// Reuse boundary (research §11.2 / D-08-CONTEXT-9): the FONT MANAGEMENT
// face reuses `YiyinFontStore` (user-installed fonts, the yiyin directory
// convention); system families resolve through CTFontCreateWithName. The
// RENDER TARGET is NOT the yiyin CGImage face — this rasterizer emits an
// alpha-COVERAGE bitmap (`kCGImageAlphaOnly`, the yiyin RGBA out is the
// final-output watermark's shape, untouched here).
//
// Geometry contract (D-08-5-T2-2):
//   - `fontSize` is in px of a 1000-px LONG-EDGE reference — the effective
//     size scales with the plane so preview and full stay proportional
//     (the editing-layer semantics; absolute-px sizing would shrink the
//     text to dust on a 100MP plane).
//   - the layout block is measured from the CTLine typographic bounds
//     (ascent/descent/leading per line), pixels CEILed.
//   - coverage: CoreText's gray antialiasing, subpixel positioning OFF
//     (the yiyin D-08-2-7 determinism posture — per-channel coverage and
//     subpixel phase both poison a byte-stable cache key).
// ─────────────────────────────────────────────────────────────────────────

public enum TextRasterizer {

    /// The long-edge reference the fontSize is expressed against.
    public static let longEdgeReference: Double = 1000

    /// Resolve the CTFont for a params face: user-installed fonts (the
    /// YiyinFontStore registry) first, then the system families (CoreText
    /// falls back to the default font for unknown names — never a failure).
    public static func resolveFont(
        name: String, sizePx: Double, store: YiyinFontStore
    ) -> CTFont {
        if let installed = store.ctFont(named: name, size: sizePx) {
            return installed
        }
        return CTFontCreateWithName(name as CFString, CGFloat(sizePx), nil)
    }

    /// The layout block dimensions for `params` at the given plane long
    /// edge (nil = nothing to draw — an empty/whitespace-only content).
    public static func blockExtent(
        content: String, fontName: String, fontSize: Double, lineSpacing: Double,
        longEdge: Int, store: YiyinFontStore
    ) -> (w: Int, h: Int)? {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let sizePx = fontSize * Double(longEdge) / longEdgeReference
        let font = resolveFont(name: fontName, sizePx: sizePx, store: store)
        let metrics = lineMetrics(font: font)
        var maxWidth: Double = 1
        for line in content.components(separatedBy: "\n") {
            maxWidth = max(maxWidth, ceil(lineWidth(line, font: font)))
        }
        let lineCount = Double(content.components(separatedBy: "\n").count)
        // The baseline advance per gap = lineHeight·(1 + lineSpacing); the
        // block height = every line's lineHeight + the inter-line extras.
        let height = lineCount * metrics.lineHeight
            + (lineCount - 1) * lineSpacing * metrics.lineHeight
        return (Int(maxWidth), Int(max(ceil(height), 1)))
    }

    /// The coverage bitmap (1 byte per pixel: CoreText gray AA).
    public struct Coverage {
        public var width: Int
        public var height: Int
        public var bytes: [UInt8]
    }

    /// Rasterize the multi-line content into the coverage bitmap (the
    /// blockExtent geometry, drawn upright).
    public static func rasterize(
        content: String, fontName: String, fontSize: Double, lineSpacing: Double,
        longEdge: Int, store: YiyinFontStore
    ) -> Coverage? {
        guard let extent = blockExtent(
            content: content, fontName: fontName, fontSize: fontSize,
            lineSpacing: lineSpacing, longEdge: longEdge, store: store)
        else { return nil }
        let width = extent.w
        let height = extent.h
        let sizePx = fontSize * Double(longEdge) / longEdgeReference
        let font = resolveFont(name: fontName, sizePx: sizePx, store: store)
        let metrics = lineMetrics(font: font)

        // The yiyin RGBA context shape (proven compile/runtime face — the
        // Swift overlay refuses the NULL colorspace an alpha-only bitmap
        // needs, so we draw WHITE text over transparent and EXTRACT the
        // alpha channel as the coverage, premultipliedLast byte 3).
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = pixels.withUnsafeMutableBytes { raw -> CGContext? in
            CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let ctx else { return nil }
        // Deterministic gray AA (the yiyin D-08-2-7 posture).
        ctx.setAllowsFontSmoothing(true)
        ctx.setShouldSmoothFonts(false)
        ctx.setAllowsFontSubpixelPositioning(false)
        ctx.setShouldSubpixelPositionFonts(false)
        ctx.setAllowsFontSubpixelQuantization(true)
        ctx.setShouldSubpixelQuantizeFonts(true)
        let white = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!
        var baselineFromTop = 0.0
        for line in content.components(separatedBy: "\n") {
            let attributed = NSMutableAttributedString(string: line)
            attributed.addAttribute(
                kCTFontAttributeName as NSAttributedString.Key,
                value: font,
                range: NSRange(location: 0, length: attributed.length))
            // CTLineDraw does NOT consume the context fill color (the
            // yiyin D-08-2-7 probe) — the foreground rides the attributes.
            attributed.addAttribute(
                kCTForegroundColorAttributeName as NSAttributedString.Key,
                value: white,
                range: NSRange(location: 0, length: attributed.length))
            let ctLine = CTLineCreateWithAttributedString(attributed)
            // The yiyin baseline recipe: top-left space → the CG
            // bottom-left conversion (y = height − baseline).
            ctx.textPosition = CGPoint(
                x: 0, y: Double(height) - (baselineFromTop + metrics.ascent))
            CTLineDraw(ctLine, ctx)
            baselineFromTop += metrics.lineHeight * (1.0 + lineSpacing)
        }
        // The alpha extraction (white text: coverage == alpha).
        var bytes = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            bytes[index] = pixels[index * 4 + 3]
        }
        return Coverage(width: width, height: height, bytes: bytes)
    }

    // MARK: - metrics

    struct LineMetrics {
        var ascent: Double
        var descent: Double
        var leading: Double
        var lineHeight: Double
    }

    static func lineMetrics(font: CTFont) -> LineMetrics {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        return LineMetrics(
            ascent: Double(ascent), descent: Double(descent),
            leading: Double(leading),
            lineHeight: Double(ascent + descent + leading))
    }

    static func lineWidth(_ text: String, font: CTFont) -> Double {
        let attributed = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return width.isFinite ? Double(width) : 0
    }
}
