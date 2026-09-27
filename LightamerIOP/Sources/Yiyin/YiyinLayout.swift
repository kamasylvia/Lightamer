import Foundation

// ─────────────────────────────────────────────────────────────────────────
// YiyinLayout (Plan 08-01) — the float64 seven-step joint layout, a 1:1
// mirror of the yiyin composition pipeline's pure-arithmetic steps (the
// yiyin repo (https://github.com/kamasylvia/yiyin, v1.7.1) is the
// read-only spec source; L017 route: geometry is pinned per-value against
// the node harness, NO bitmap parity):
//
//   init            :92-136   aspect reset (bg_rate) + landscape swap
//   clacBgImgSize   :472-506  canvas size (content-height driven; width
//                             grows when the main image exceeds the rate)
//   calcContentHeight:508-546 content height (margins ≥ shadow; text rows
//                             consume 3/4 of the offset + the bottom slot)
//   genBgImg        :197-211  main image centered on the final canvas
//   composite       :288-348  text rows stacked bottom-up (08-2 rows)
//
// ALL arithmetic is float64 (`Double`) with JS `Math.ceil` → `.rounded(.up)`
// and `Math.round` → `.rounded()` (half-up; every quantity here is ≥ 0, so
// half-up == half-away-from-zero). The yiyin ceil-quirk is preserved
// VERBATIM — e.g. a 7px canvas at rate 100 yields ceil(3 × (7/3)) = 8, not
// 7; the SEED identity never rides the formula (BordersModule takes the
// param-based blit fast path — the formula quirk is exactly why).
//
// JOINT LAYOUT RECORD (08-CONTEXT 继承定案): yiyin's `calcContentHeight`
// consumes the TEXT row heights, so the borders (76.0) canvas must RESERVE
// the watermark (77.0) text block. This file is the single pure function
// both terminal modules consume: `layout(imageSize:bordersParams:rows:)` —
// borders consumes canvasSize/mainImageRect/radius/shadow, watermark
// consumes the placed rows. 08-1 delivers the EMPTY-rows state (watermark
// absent or rowless); 08-2 activates the rows leg. Protocol seam decision
// (driver-injected aux vs per-module lazy compute): recorded in
// 08-1-DECISIONS — 08-1 computes lazily per module from dscIn + params
// (O(1) math); the override injection seam exists for the 8-2 segment
// assembly (`BordersModule.jointLayoutOverride`).
// ─────────────────────────────────────────────────────────────────────────

/// The joint yiyin layout record — one computation consumed by BOTH
/// terminal-segment modules (borders 76.0 geometry + watermark 77.0 text
/// rows). All pixel values are integers in the CANVAS coordinate frame
/// (top-left origin, y down — the yiyin/sharp composite frame); the
/// float64 intermediates are folded in exactly as yiyin does.
public struct YiyinLayoutRecord: Equatable, Sendable {

    /// One placed text row (08-2 rows leg; 08-1 records are always empty).
    /// `top/left` = the row's top-left corner in canvas px (the yiyin
    /// `composite` overlay offsets, `:304-317` — bottom-up stacking, list
    /// order reversed, last row nearest the bottom edge).
    public struct PlacedRow: Equatable, Sendable {
        public var left: Int
        public var top: Int
        public var width: Int
        public var height: Int

        public init(left: Int, top: Int, width: Int, height: Int) {
            self.left = left
            self.top = top
            self.width = width
            self.height = height
        }
    }

    /// The image size this record was computed FOR — the override-injection
    /// validation key (a stale override computed at a different plane size
    /// is discarded and the module recomputes locally).
    public var sourceImageSize: SIMD2<Int>

    /// The background canvas size (`material.bg.w/h` — final
    /// `clacBgImgSize(contentH)` pass, yiyin `genBgImg:199`).
    public var canvasSize: SIMD2<Int>

    /// The main image's top-left corner in canvas px (`material.main[0]
    /// .left/top` — centered, yiyin `genBgImg:209-210`).
    public var mainImageOrigin: SIMD2<Int>

    /// The content height (`this.contentH`, yiyin `calcContentHeight:538`).
    public var contentHeight: Int

    /// The main image's top margin BEFORE the vertical centering shift
    /// (`contentTop` — max(min-margin, shadow height), yiyin `:515-523`).
    public var contentTop: Int

    /// Corner radius in canvas px (yiyin web `image-tool/index.ts:63` —
    /// `ceil(mainH) × radius%/100`; 0 = square path).
    public var cornerRadiusPx: Double

    /// The shadow blur in canvas px (yiyin web `image-tool/index.ts:50` —
    /// `ceil(mainH) × shadow%/100`; the CSS canvas `shadowBlur` unit, NOT a
    /// Gaussian σ — BordersModule maps σ = 0.5 × this, DECISIONS).
    public var shadowBlurPx: Double

    /// The text bottom slot in canvas px (`bgHeight × textBottomOffset`,
    /// yiyin `:512` — reserved by the canvas even while rows are empty in
    /// the yiyin formula only when rows exist; recorded for 08-2).
    public var textBottomOffsetPx: Double

    /// Placed text rows (empty in the 08-1 no-watermark state).
    public var rows: [PlacedRow]

    public init(
        sourceImageSize: SIMD2<Int>,
        canvasSize: SIMD2<Int>,
        mainImageOrigin: SIMD2<Int>,
        contentHeight: Int,
        contentTop: Int,
        cornerRadiusPx: Double,
        shadowBlurPx: Double,
        textBottomOffsetPx: Double,
        rows: [PlacedRow] = []
    ) {
        self.sourceImageSize = sourceImageSize
        self.canvasSize = canvasSize
        self.mainImageOrigin = mainImageOrigin
        self.contentHeight = contentHeight
        self.contentTop = contentTop
        self.cornerRadiusPx = cornerRadiusPx
        self.shadowBlurPx = shadowBlurPx
        self.textBottomOffsetPx = textBottomOffsetPx
        self.rows = rows
    }

    /// The canvas COINCIDES with the main image (no visible background
    /// band, no rows). True identity additionally requires radius/shadow
    /// to be zero — `BordersModule.isIdentityRender` checks those too.
    public var isIdentityCanvas: Bool {
        canvasSize == sourceImageSize && mainImageOrigin == .zero && rows.isEmpty
    }
}

/// The nine-grid anchor (D-08-CONTEXT-2 — `.bottomCenter` is the
/// yiyin-exact default; the other eight are the Lightamer extension).
public enum YiyinNineGridAnchor: String, Codable, Hashable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case center
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

/// The pure float64 layout (yiyin pipeline steps 2/5/7's arithmetic).
public enum YiyinLayout {

    /// The PASS-1 canvas (the font-sizing basis, yiyin `clacBgImgSize()`
    /// default `height = sizeInfo.h`) — row-height independent, which is
    /// exactly why yiyin can size fonts before knowing the rows. The
    /// 08-2 watermark measurement consumes `.y`. Mirrors `layout`'s
    /// `bgSize(contentHeight: h)` VERBATIM (including the ceil-quirk —
    /// this is a SIZING basis only; identity never rides it, D-08-1-2).
    public static func firstPassCanvasSize(
        imageSize: SIMD2<Int>, borders: BordersModule.Params
    ) -> SIMD2<Int> {
        let w = Double(max(imageSize.x, 1))
        let h = Double(max(imageSize.y, 1))
        // Step 1: the aspect/landscape reset (init :110-131).
        var resetW = w
        var resetH = h
        if let aspect = borders.aspectRatio {
            let rate = Double(aspect.w) / Double(aspect.h)
            if imageSize.x >= imageSize.y {
                resetH = (resetW / rate).rounded()
            } else {
                resetW = (resetH * rate).rounded()
            }
        } else if borders.landscapeOutput, resetW < resetH {
            let t = resetW
            resetW = resetH
            resetH = t
        }
        let whRate = resetW / resetH
        // Pass 1: contentHeight = the image height (yiyin's default arg).
        var rh = h
        var rw = (rh * whRate).rounded(.up)
        let rate = borders.mainImageWidthRate / 100
        if w / rw > rate {
            rw = (w / rate).rounded(.up)
            rh = (rw / whRate).rounded(.up)
        }
        return SIMD2(Int(rw), Int(rh))
    }

    /// Compute the joint layout for one yiyin terminal-segment instance
    /// pair at the given (upright, dscIn-space) image size.
    ///
    /// - Parameters:
    ///   - imageSize: the main image plane size in px (the borders piece's
    ///     `dscIn` — already EXIF-upright, scale-folded plane pixels).
    ///   - borders: the borders instance params.
    ///   - rows: per-row METRICS (width/height px) of the watermark text
    ///     block, in LIST ORDER (top-most first — the yiyin template list
    ///     order). Empty in 08-1.
    public static func layout(
        imageSize: SIMD2<Int>,
        borders: BordersModule.Params,
        rows: [TextRowMetrics]
    ) -> YiyinLayoutRecord {
        let w = Double(imageSize.x)
        let h = Double(imageSize.y)

        // ── Step 1: aspect reset + landscape swap (init :110-131).
        var resetW = w
        var resetH = h
        if let aspect = borders.aspectRatio {
            // bg_rate active — landscapeOutput is force-cleared at commit
            // (yiyin onBGRateChange mutual exclusion, actions/index.svelte).
            let rate = Double(aspect.w) / Double(aspect.h)
            if imageSize.x >= imageSize.y {
                resetH = (resetW / rate).rounded()
            } else {
                resetW = (resetH * rate).rounded()
            }
        } else if borders.landscapeOutput, resetW < resetH {
            // 竖转横: swap the reset dims (init :123-131).
            let t = resetW
            resetW = resetH
            resetH = t
        }
        let whRate = resetW / resetH

        // ── Step 2: canvas size (clacBgImgSize :472-506 — called TWICE in
        //    yiyin: once with the default height for the font sizing, then
        //    again with the final content height in genBgImg :199).
        //    `contentHeight > 0` branch is the live path in both calls.
        func bgSize(contentHeight: Double) -> SIMD2<Double> {
            var rh = resetH
            var rw = resetW
            if contentHeight > 0 {
                rh = contentHeight
                rw = (rh * whRate).rounded(.up) // Math.ceil(resetHeight * whRate)
            } else {
                rh = max(h, resetH)
                rw = (rh * whRate).rounded(.up)
            }
            // 宽度太窄 → 等比扩大 (:493-497). JS `|| 90` — our param is
            // commit-clamped > 0.
            let mainImgWidthRate = borders.mainImageWidthRate / 100
            if w / rw > mainImgWidthRate {
                rw = (w / mainImgWidthRate).rounded(.up)
                rh = (rw / whRate).rounded(.up)
            }
            return SIMD2(rw, rh)
        }

        // Pass 1 (font-sizing canvas, yiyin `genWatermark` step 2 —
        // `clacBgImgSize()` default height = sizeInfo.h).
        let bg1 = bgSize(contentHeight: h)

        // ── Step 3: content height (calcContentHeight :508-546).
        let bgHeight = bg1.y
        let mainImgTopOffset = bgHeight * (borders.miniTopBottomMargin / 100)
        let textButtomOffsetPx = bgHeight * borders.textBottomOffset // :512 (sic)

        var contentTop = Int(mainImgTopOffset.rounded(.up)) // Math.ceil
        var mainImgOffset = Double(contentTop * 2)
        if let shadow = borders.shadow {
            // 阴影宽度 (:519-523) — ceil BEFORE the percent multiply
            // (yiyin web `image-tool/index.ts:50` shape).
            let shadowHeight = Int((h * (shadow / 100)).rounded(.up))
            contentTop = max(contentTop, shadowHeight)
            mainImgOffset = Double(contentTop * 2)
        }
        // 有文字时 (:526-529) — JS float math, kept in Double verbatim.
        let textH = rows.reduce(0.0) { $0 + Double($1.height) }
        if !rows.isEmpty {
            mainImgOffset = mainImgOffset * 3 / 4
            mainImgOffset += textButtomOffsetPx
        }
        let contentH = Int((textH + h + mainImgOffset).rounded(.up))

        // ── Step 4: final canvas (the genBgImg :199 second pass).
        let bg2 = bgSize(contentHeight: Double(contentH))

        // ── Step 5: main image placement (genBgImg :209-210).
        //    left = round((bg.w − main.w)/2);
        //    top  = contentTop + round((bg.h − contentH)/2).
        let mainLeft = Int(((bg2.x - w) / 2).rounded())
        let mainTop = contentTop + Int(((bg2.y - Double(contentH)) / 2).rounded())

        // ── Step 6: corner radius / shadow blur (web :50,63 — ceil(mainH)
        //    BEFORE the percent; `rate` is 1 outside yiyin's >10240 guard,
        //    which our windowed rendering never triggers, RESEARCH §5).
        let mainHCeiled = h.rounded(.up)
        let cornerRadiusPx = borders.cornerRadius.map { mainHCeiled * ($0 / 100) } ?? 0
        let shadowBlurPx = borders.shadow.map { mainHCeiled * ($0 / 100) } ?? 0

        // ── Step 7: text rows stacked bottom-up (composite :300-319) —
        //    horizontal center, the list-LAST row placed first at
        //    top = bg.h − h_last, each earlier row above at
        //    round(prevTop − h). QUIRK (:543-545, kept verbatim): the
        //    list-LAST row's height grows by textBottomOffset BEFORE
        //    placement (the contentH sum at step 3 used the UNinflated
        //    heights — the mutation happens after :532-535).
        let placed = stackRows(
            rows: rows, canvasWidth: Int(bg2.x), canvasHeight: Int(bg2.y),
            bottomOffsetPx: textButtomOffsetPx)

        return YiyinLayoutRecord(
            sourceImageSize: imageSize,
            canvasSize: SIMD2(Int(bg2.x), Int(bg2.y)),
            mainImageOrigin: SIMD2(mainLeft, mainTop),
            contentHeight: contentH,
            contentTop: contentTop,
            cornerRadiusPx: cornerRadiusPx,
            shadowBlurPx: shadowBlurPx,
            textBottomOffsetPx: textButtomOffsetPx,
            rows: placed)
    }

    /// Watermark text-row metrics input (08-2 produces these from the
    /// CoreText layout; 08-1 only ever passes []). List order = the yiyin
    /// template list order (top-most row first).
    public struct TextRowMetrics: Sendable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// The yiyin composite row stacking (composite :300-319 + the :543-545
    /// last-row inflation quirk), factored so the watermark-only face
    /// stacks against the IMAGE itself with the same loop.
    public static func stackRows(
        rows: [TextRowMetrics], canvasWidth: Int, canvasHeight: Int,
        bottomOffsetPx: Double
    ) -> [YiyinLayoutRecord.PlacedRow] {
        var placed: [YiyinLayoutRecord.PlacedRow] = []
        placed.reserveCapacity(rows.count)
        var prevTop = 0
        for (index, row) in rows.reversed().enumerated() {
            let heightD = Double(row.height) + (index == 0 ? bottomOffsetPx : 0)
            let top: Int
            if index == 0 {
                top = Int((Double(canvasHeight) - heightD).rounded())
            } else {
                top = Int((Double(prevTop) - heightD).rounded())
            }
            let left = Int(((Double(canvasWidth) - Double(row.width)) / 2).rounded())
            placed.append(
                YiyinLayoutRecord.PlacedRow(
                    left: left, top: top, width: row.width, height: row.height))
            prevTop = top
        }
        return placed
    }

    /// Translate the placed rows so the text BLOCK anchors at the requested
    /// grid position, `marginPx` from each anchored edge (the yiyin bottom
    /// slot margin generalized — D-08-2-6). `.bottomCenter` is the IDENTITY
    /// (the stacking above already produces it — yiyin parity never rides
    /// this function's math).
    public static func applyAnchor(
        _ anchor: YiyinNineGridAnchor,
        rows: [YiyinLayoutRecord.PlacedRow],
        canvas: SIMD2<Int>,
        marginPx: Double
    ) -> [YiyinLayoutRecord.PlacedRow] {
        guard anchor != .bottomCenter, !rows.isEmpty else { return rows }
        let minX = rows.map(\.left).min() ?? 0
        let maxX = rows.map { $0.left + $0.width }.max() ?? 0
        let minY = rows.map(\.top).min() ?? 0
        let maxY = rows.map { $0.top + $0.height }.max() ?? 0
        let blockW = maxX - minX
        let blockH = maxY - minY
        let margin = Int(marginPx.rounded())

        let targetX: Int
        switch anchor {
        case .topLeft, .centerLeft, .bottomLeft: targetX = margin
        case .topCenter, .center, .bottomCenter:
            targetX = Int((Double(canvas.x - blockW) / 2).rounded())
        case .topRight, .centerRight, .bottomRight: targetX = canvas.x - margin - blockW
        }
        let targetY: Int
        switch anchor {
        case .topLeft, .topCenter, .topRight: targetY = margin
        case .centerLeft, .center, .centerRight:
            targetY = Int((Double(canvas.y - blockH) / 2).rounded())
        case .bottomLeft, .bottomCenter, .bottomRight: targetY = canvas.y - margin - blockH
        }
        let dx = targetX - minX
        let dy = targetY - minY
        return rows.map { row in
            YiyinLayoutRecord.PlacedRow(
                left: row.left + dx, top: row.top + dy,
                width: row.width, height: row.height)
        }
    }
}
