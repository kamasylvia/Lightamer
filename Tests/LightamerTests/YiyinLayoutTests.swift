@testable import LightamerCore
import LightamerIOP
import XCTest

/// Plan 08-01 T2 — YiyinLayout float64 mirror vs the yiyin reference
/// harness (`Scripts/yiyin-ref-harness.mjs`, run against the yiyin v1.7.1
/// source's VERBATIM layout arithmetic; reference JSON at
/// `.work/plans/08-01/yiyin-layout-reference.json`, numbers embedded
/// verbatim below — regenerate + diff with the script).
///
/// Gates (plan Verification row 布局几何): integer fields EXACT (both
/// sides are float64 with identical ceil/round sequences); float fields
/// < 1e-6; compared > 0 (防空转).
final class YiyinLayoutTests: XCTestCase {

    struct RefCase {
        var id: String
        var image: SIMD2<Int>
        var rate: Double
        var margin: Double
        var aspect: BordersModule.AspectRatio?
        var landscape: Bool
        var radius: Double?
        var shadow: Double?
        var canvas: SIMD2<Int>
        var main: SIMD2<Int>
        var contentH: Int
        var contentTop: Int
        var radiusPx: Double
        var shadowPx: Double
        var textBottomOffsetPx: Double
        /// (left, top, w, h) in placement order (list-reversed — bottom
        /// row first); empty = the 08-1 no-watermark face.
        var rows: [(Int, Int, Int, Int)]

        init(
            id: String, image: SIMD2<Int>, rate: Double = 90, margin: Double = 0,
            aspect: BordersModule.AspectRatio? = nil, landscape: Bool = false,
            radius: Double? = nil, shadow: Double? = nil,
            canvas: SIMD2<Int>, main: SIMD2<Int>, contentH: Int, contentTop: Int,
            radiusPx: Double = 0, shadowPx: Double = 0,
            rows: [(Int, Int, Int, Int)] = []
        ) {
            // textBottomOffsetPx = bgHeight(first pass) × 0.027 — derived
            // per case below (the first-pass height = the reference run's
            // `textBottomOffsetPx / 0.027` sanity anchor).
            self.id = id
            self.image = image
            self.rate = rate
            self.margin = margin
            self.aspect = aspect
            self.landscape = landscape
            self.radius = radius
            self.shadow = shadow
            self.canvas = canvas
            self.main = main
            self.contentH = contentH
            self.contentTop = contentTop
            self.radiusPx = radiusPx
            self.shadowPx = shadowPx
            self.rows = rows
            switch id {
            // bg1.h (first-pass canvas height) × 0.027 — values from the
            // reference JSON (they differ per aspect/landscape/reset case).
            case "landscape_default", "square_default", "landscape_margin5_shadow6",
                "landscape_with_rows":
                self.textBottomOffsetPx = 90.018 // bg1.h 3334
            case "portrait_default", "portrait_aspect_3_4_margin2_shadow3":
                self.textBottomOffsetPx = 120.042 // bg1.h 4446
            case "landscape_aspect_1_1":
                self.textBottomOffsetPx = 120.015 // bg1.h 4445
            case "portrait_landscape_swap", "portrait_aspect_1_1":
                self.textBottomOffsetPx = 108.0 // bg1.h 4000
            case "landscape_aspect_3_2", "square_rate100_neutral":
                self.textBottomOffsetPx = 81.0 // bg1.h 3000
            case "landscape_rate50":
                self.textBottomOffsetPx = 162.0 // bg1.h 6000
            case "tiny_ceil_quirk_58x7":
                self.textBottomOffsetPx = 0.189 // bg1.h 7
            default:
                self.textBottomOffsetPx = -1
            }
        }
    }

    /// The harness run of 2026-09-22 (Scripts/yiyin-ref-harness.mjs).
    /// The sharp placement probe on `landscape_rate50` measured the
    /// composited PNG's non-white bbox [2000,1500,4000,3000] == the placed
    /// integers exactly (probe in the reference JSON).
    private let reference: [RefCase] = [
        RefCase(
            id: "landscape_default", image: SIMD2(4000, 3000),
            canvas: SIMD2(4445, 3334), main: SIMD2(223, 167),
            contentH: 3000, contentTop: 0),
        RefCase(
            id: "portrait_default", image: SIMD2(3000, 4000),
            canvas: SIMD2(3334, 4446), main: SIMD2(167, 223),
            contentH: 4000, contentTop: 0),
        RefCase(
            id: "square_default", image: SIMD2(3000, 3000),
            canvas: SIMD2(3334, 3334), main: SIMD2(167, 167),
            contentH: 3000, contentTop: 0),
        RefCase(
            id: "landscape_aspect_1_1", image: SIMD2(4000, 3000),
            aspect: BordersModule.AspectRatio(w: 1, h: 1),
            canvas: SIMD2(4445, 4445), main: SIMD2(223, 723),
            contentH: 3000, contentTop: 0),
        RefCase(
            id: "portrait_aspect_1_1", image: SIMD2(3000, 4000),
            aspect: BordersModule.AspectRatio(w: 1, h: 1),
            canvas: SIMD2(4000, 4000), main: SIMD2(500, 0),
            contentH: 4000, contentTop: 0),
        RefCase(
            id: "landscape_aspect_3_2", image: SIMD2(4000, 3000),
            aspect: BordersModule.AspectRatio(w: 3, h: 2),
            canvas: SIMD2(4500, 3000), main: SIMD2(250, 0),
            contentH: 3000, contentTop: 0),
        RefCase(
            id: "portrait_landscape_swap", image: SIMD2(3000, 4000),
            landscape: true,
            canvas: SIMD2(5334, 4000), main: SIMD2(1167, 0),
            contentH: 4000, contentTop: 0),
        RefCase(
            id: "landscape_margin5_shadow6", image: SIMD2(4000, 3000),
            margin: 5, shadow: 6,
            canvas: SIMD2(4480, 3360), main: SIMD2(240, 180),
            contentH: 3360, contentTop: 180, shadowPx: 180),
        RefCase(
            id: "landscape_rate50", image: SIMD2(4000, 3000),
            rate: 50,
            canvas: SIMD2(8000, 6000), main: SIMD2(2000, 1500),
            contentH: 3000, contentTop: 0),
        RefCase(
            id: "portrait_aspect_3_4_margin2_shadow3", image: SIMD2(3000, 4000),
            margin: 2, aspect: BordersModule.AspectRatio(w: 3, h: 4), shadow: 3,
            canvas: SIMD2(3334, 4446), main: SIMD2(167, 223),
            contentH: 4240, contentTop: 120, shadowPx: 120),
        RefCase(
            id: "square_rate100_neutral", image: SIMD2(3000, 3000),
            rate: 100,
            canvas: SIMD2(3000, 3000), main: SIMD2(0, 0),
            contentH: 3000, contentTop: 0),
        RefCase(
            id: "tiny_ceil_quirk_58x7", image: SIMD2(58, 7),
            rate: 100,
            canvas: SIMD2(59, 7), main: SIMD2(1, 0),
            contentH: 7, contentTop: 0),
        RefCase(
            id: "landscape_with_rows", image: SIMD2(4000, 3000),
            canvas: SIMD2(4445, 3334), main: SIMD2(223, 87),
            contentH: 3161, contentTop: 0,
            rows: [(1923, 3214, 600, 30), (1973, 3174, 500, 40)]),
    ]

    private func params(_ c: RefCase) -> BordersModule.Params {
        var p = BordersModule.Params()
        p.mainImageWidthRate = c.rate
        p.miniTopBottomMargin = c.margin
        p.aspectRatio = c.aspect
        p.landscapeOutput = c.landscape
        p.cornerRadius = c.radius
        p.shadow = c.shadow
        return p
    }

    func testLayoutMatchesYiyinHarnessPerValue() {
        var compared = 0
        for c in reference {
            // c.rows is PLACEMENT order (bottom row first); the metrics
            // input is the yiyin LIST order (top-most first) — the exact
            // inverse.
            let rows = c.rows.reversed().map {
                YiyinLayout.TextRowMetrics(width: $0.2, height: $0.3)
            }
            let record = YiyinLayout.layout(
                imageSize: c.image, borders: params(c), rows: rows)

            // Integers: EXACT (identical float64 ceil/round sequences).
            XCTAssertEqual(record.canvasSize.x, c.canvas.x, "\(c.id): canvas w")
            XCTAssertEqual(record.canvasSize.y, c.canvas.y, "\(c.id): canvas h")
            XCTAssertEqual(record.mainImageOrigin.x, c.main.x, "\(c.id): main left")
            XCTAssertEqual(record.mainImageOrigin.y, c.main.y, "\(c.id): main top")
            XCTAssertEqual(record.contentHeight, c.contentH, "\(c.id): contentH")
            XCTAssertEqual(record.contentTop, c.contentTop, "\(c.id): contentTop")
            XCTAssertEqual(record.sourceImageSize, c.image, "\(c.id): source size echo")
            compared += 6

            // Floats: < 1e-6.
            XCTAssertEqual(
                record.cornerRadiusPx, c.radiusPx, accuracy: 1e-6, "\(c.id): radius px")
            XCTAssertEqual(
                record.shadowBlurPx, c.shadowPx, accuracy: 1e-6, "\(c.id): shadow px")
            XCTAssertEqual(
                record.textBottomOffsetPx, c.textBottomOffsetPx, accuracy: 1e-6,
                "\(c.id): text bottom slot px")
            compared += 3

            // Rows: exact, placement order = list-reversed.
            XCTAssertEqual(record.rows.count, c.rows.count, "\(c.id): row count")
            for (got, want) in zip(record.rows, c.rows) {
                XCTAssertEqual(got.left, want.0, "\(c.id): row left")
                XCTAssertEqual(got.top, want.1, "\(c.id): row top")
                XCTAssertEqual(got.width, want.2, "\(c.id): row width")
                XCTAssertEqual(got.height, want.3, "\(c.id): row height")
                compared += 4
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: values compared")
        XCTAssertGreaterThanOrEqual(
            reference.count, 8, "plan gate: ≥8 harness cases pinned")
    }

    /// The yiyin ceil QUIRK (float64 `h × (w/h)` rounding): 58×7 at rate
    /// 100 grows the canvas to 59 — the mirror reproduces it bit-for-bit.
    /// The MODULE never rides the formula at these params (the PARAM-based
    /// neutral blit, YiyinBordersTests) — this pin is the pure-function
    /// parity proof.
    func testYiyinCeilQuirkIsPreserved() {
        let p = params(RefCase(
            id: "tiny_ceil_quirk_58x7", image: SIMD2(58, 7), rate: 100,
            canvas: .zero, main: .zero, contentH: 0, contentTop: 0))
        let record = YiyinLayout.layout(imageSize: SIMD2(58, 7), borders: p, rows: [])
        XCTAssertEqual(record.canvasSize, SIMD2(59, 7))
        var compared = 0
        for value in [record.canvasSize.x, record.canvasSize.y] {
            XCTAssertGreaterThan(value, 0)
            compared += 1
        }
        XCTAssertEqual(compared, 2, "防空转")
    }

    /// Joint-layout seam: the rows leg changes contentH/canvas exactly as
    /// yiyin's `calcContentHeight` rows branch (3/4 offset + bottom slot)
    /// — the 08-2 watermark reservation interface.
    func testRowsLegReservesTextBlock() {
        var base = params(RefCase(
            id: "landscape_default", image: SIMD2(4000, 3000),
            canvas: .zero, main: .zero, contentH: 0, contentTop: 0))
        base.textBottomOffset = 0.027
        let empty = YiyinLayout.layout(imageSize: SIMD2(4000, 3000), borders: base, rows: [])
        let withRows = YiyinLayout.layout(
            imageSize: SIMD2(4000, 3000), borders: base,
            rows: [YiyinLayout.TextRowMetrics(width: 500, height: 40)])
        XCTAssertEqual(empty.rows.isEmpty, true)
        XCTAssertGreaterThan(withRows.contentHeight, empty.contentHeight, "text block reserved")
        // The canvas may stay (the width-rate branch re-derives the same
        // 4445×3334 here); the RESERVATION is the main image shifting UP
        // (main.top 87 vs 167) — the bottom band is the text slot.
        XCTAssertLessThan(
            withRows.mainImageOrigin.y, empty.mainImageOrigin.y,
            "main image shifts up to reserve the bottom text band")
        var compared = 0
        for row in withRows.rows {
            XCTAssertGreaterThanOrEqual(row.top, 0)
            XCTAssertGreaterThan(row.width, 0)
            compared += 2
        }
        XCTAssertGreaterThan(compared, 0, "防空转")
    }
}
