import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// TileInferenceTests (Plan M2-10-06 T1, KD-1 — LIB bundle) — the MODEL-FREE
// tiling pure face:
//
//   • SPANS: exact-tile grids with the last tile aligned to the axis end
//     (no truncated remainder — fixed shapes only); short axes = one exact
//     span; coverage is complete (no uncovered pixel, no grid padding).
//   • WEIGHTS: linear ramp over the 16 px overlap, interior edges only;
//     per-pixel accumulated sums are strictly positive and the normalized
//     contributions sum to EXACTLY 1 (the blend test anchor); separability
//     (axis product) pinned.
//   • PLAN: feed shapes = smallest supported edge ≥ span (exact for grid
//     tiles, pad-to-fit for sub-tile images); row-major order; output
//     geometry ×scale.
//   • BUDGET: the 400 MP output cap is a typed rejection before any
//     allocation.
//   • PROGRESS: 15 + 78·done/total, monotone non-decreasing, endpoints.
// ─────────────────────────────────────────────────────────────────────────────

final class TileInferenceTests: XCTestCase {

    // MARK: - Axis spans

    func testShortAxisIsOneExactSpan() throws {
        XCTAssertEqual(
            TilePlanner.axisSpans(length: 64, tileEdge: 256),
            [TileGrid.Span(start: 0, length: 64)])
        XCTAssertEqual(
            TilePlanner.axisSpans(length: 256, tileEdge: 256),
            [TileGrid.Span(start: 0, length: 256)])
        XCTAssertEqual(TilePlanner.axisSpans(length: 0, tileEdge: 256), [])
    }

    func testLongAxisTilesAreExactlyTileEdgeAndAlignToTheEnd() throws {
        for length in [257, 300, 496, 512, 540, 1000, 4097] {
            let spans = TilePlanner.axisSpans(length: length, tileEdge: 256)
            // Every span is EXACTLY the tile edge (fixed shapes — a
            // truncated remainder strip cannot feed a fixed-shape model).
            XCTAssertTrue(
                spans.allSatisfy { $0.length == 256 },
                "length \(length): fixed-shape spans only, got \(spans)")
            // Starts ascend; the last tile ends exactly at the axis end.
            XCTAssertEqual(spans.first?.start, 0)
            XCTAssertEqual(
                spans.last.map { $0.start + $0.length }, length,
                "length \(length): the last tile aligns to the axis end")
            for index in 1..<spans.count {
                XCTAssertGreaterThan(spans[index].start, spans[index - 1].start)
            }
        }
    }

    func testOverlapKeepsNeighbouringTilesAtLeastOverlapApart() throws {
        let spans = TilePlanner.axisSpans(length: 1200, tileEdge: 256)
        XCTAssertGreaterThan(spans.count, 1)
        for index in 1..<spans.count {
            let gap = spans[index].start - (spans[index - 1].start + 256)
            XCTAssertLessThanOrEqual(
                gap, -TilePlanner.overlap,
                "neighbours must overlap by at least the ramp width")
        }
    }

    // MARK: - Weights

    func testWeightsArePositiveAndNormalizeToExactlyOne() throws {
        for length in [64, 300, 496, 1000] {
            let spans = TilePlanner.axisSpans(length: length, tileEdge: 256)
            let sums = TilePlanner.axisWeightSums(spans: spans, length: length)
            for position in 0..<length {
                let sum = sums[position]
                XCTAssertGreaterThan(
                    sum, 0, "length \(length)@\(position): uncovered pixel")
                // The normalized contributions sum to exactly 1 (within
                // float round-trip of the ramp arithmetic).
                var normalized: Float = 0
                for span in spans {
                    normalized += TilePlanner.spanWeight(
                        span: span, position: position, axisLength: length)
                        / sum
                }
                XCTAssertEqual(
                    normalized, 1, accuracy: 1e-6,
                    "length \(length)@\(position): normalized weight sum")
            }
        }
    }

    func testWeightsAreOneAwayFromInteriorEdgesAndRampAtOverlapZones() throws {
        // Two 256 tiles at starts 0 and 240 (overlap zone 240..<256).
        let spans = [
            TileGrid.Span(start: 0, length: 256),
            TileGrid.Span(start: 240, length: 256),
        ]
        let length = 496
        // Deep interior of the FIRST tile: weight 1 (no ramp at the axis
        // start).
        XCTAssertEqual(
            TilePlanner.spanWeight(span: spans[0], position: 100, axisLength: length), 1)
        // The ramp RISES into the second tile's leading edge...
        XCTAssertEqual(
            TilePlanner.spanWeight(span: spans[1], position: 240, axisLength: length),
            1 / 16, accuracy: 1e-6)
        XCTAssertEqual(
            TilePlanner.spanWeight(span: spans[1], position: 255, axisLength: length),
            1, accuracy: 1e-6)
        // ...and FALLS out of the first tile's trailing edge.
        XCTAssertEqual(
            TilePlanner.spanWeight(span: spans[0], position: 255, axisLength: length),
            1 / 16, accuracy: 1e-6)
        // Outside a span: zero.
        XCTAssertEqual(
            TilePlanner.spanWeight(span: spans[0], position: 300, axisLength: length), 0)
    }

    func testSeparableWeightsMultiplyToThePixelSum() throws {
        // The 2-D accumulated weight = rowSum[y] * columnSum[x] (the
        // engine's normalization denominators are the axis products).
        let width = 300, height = 496
        let rows = TilePlanner.axisSpans(length: height, tileEdge: 256)
        let columns = TilePlanner.axisSpans(length: width, tileEdge: 256)
        let rowSums = TilePlanner.axisWeightSums(spans: rows, length: height)
        let columnSums = TilePlanner.axisWeightSums(spans: columns, length: width)
        // Spot-check the separability identity through normalized sums:
        // normalizing by the product leaves every pixel's total at 1.
        let y = 248, x = 248 // inside both overlap zones
        var total: Float = 0
        for row in rows {
            for column in columns {
                let wy = TilePlanner.spanWeight(span: row, position: y, axisLength: height)
                let wx = TilePlanner.spanWeight(span: column, position: x, axisLength: width)
                total += wy * wx / (rowSums[y] * columnSums[x])
            }
        }
        XCTAssertEqual(total, 1, accuracy: 1e-6)
    }

    // MARK: - Plan

    func testPlanGridStartsFeedsAndOutputGeometry() throws {
        // 300 × 64 input at ×4: columns start [0, 44] (last aligned), the
        // single row is the exact 64 span; feeds pad the short axis to the
        // smallest supported edge.
        let grid = try TilePlanner.plan(
            inputWidth: 300, inputHeight: 64, scale: 4,
            supportedEdges: [256, 512])
        XCTAssertEqual(grid.tileEdge, 256, "the base edge is the smallest supported")
        XCTAssertEqual(grid.tiles.count, 2, "1 row × 2 columns, row-major")
        XCTAssertEqual(grid.tiles[0].x, 0)
        XCTAssertEqual(grid.tiles[0].y, 0)
        XCTAssertEqual(grid.tiles[1].x, 44, "the last tile aligns to the axis end")
        XCTAssertEqual(grid.tiles[0].feedWidth, 256)
        XCTAssertEqual(
            grid.tiles[0].feedHeight, 256,
            "the 64 px axis feeds pad-to-fit (the only padding in the system)")
        let rect = grid.outputRect(of: grid.tiles[1])
        XCTAssertEqual(rect.x, 176)
        XCTAssertEqual(rect.y, 0)
        XCTAssertEqual(rect.width, 1024)
        XCTAssertEqual(rect.height, 256)
        XCTAssertEqual(grid.outputWidth, 1200)
        XCTAssertEqual(grid.outputHeight, 256)
    }

    func testPlanSubTileImagePadsFeedToSmallestSupportedEdge() throws {
        let grid = try TilePlanner.plan(
            inputWidth: 64, inputHeight: 64, scale: 4, supportedEdges: [256])
        XCTAssertEqual(grid.tiles.count, 1)
        XCTAssertEqual(grid.tiles[0].width, 64)
        XCTAssertEqual(grid.tiles[0].feedWidth, 256)
        XCTAssertEqual(grid.tiles[0].feedHeight, 256)
        XCTAssertEqual(grid.outputWidth, 256, "64 × 4 = the golden output edge")
        XCTAssertEqual(grid.outputHeight, 256)
    }

    func testPlanDenoiseScaleOneCarriesIdentityGeometry() throws {
        let grid = try TilePlanner.plan(
            inputWidth: 600, inputHeight: 600, scale: 1, supportedEdges: [256])
        XCTAssertEqual(grid.outputWidth, 600)
        XCTAssertEqual(grid.outputHeight, 600)
        // All grid tiles feed at EXACTLY the base edge (no padding on the
        // long-axis path).
        XCTAssertTrue(
            grid.tiles.allSatisfy { $0.feedWidth == 256 && $0.feedHeight == 256 })
    }

    func testPlanRowMajorOrderOnMultiRowGrid() throws {
        // 300 × 300 at ×1: 2 columns × 2 rows; row-major = y outer.
        let grid = try TilePlanner.plan(
            inputWidth: 300, inputHeight: 300, scale: 1, supportedEdges: [256])
        XCTAssertEqual(grid.tiles.count, 4)
        XCTAssertEqual(
            grid.tiles.map { "\($0.y),\($0.x)" },
            ["0,0", "0,44", "44,0", "44,44"],
            "row-major execution order (y outer, x inner)")
    }

    // MARK: - Budget

    func testOutputBudgetIsTypedRejection() throws {
        // 10001² × 2² = 400,080,004 OUTPUT pixels > 400,000,000 → rejected
        // (the cap is on the OUTPUT geometry — Lumen validate_size parity:
        // it checks (h·scale, w·scale) against MAX_PIXELS).
        XCTAssertThrowsError(
            try TilePlanner.plan(
                inputWidth: 10001, inputHeight: 10001, scale: 2,
                supportedEdges: [256])
        ) { error in
            guard case TileInferenceError.pixelBudgetExceeded(
                let pixels, let limit) = error else {
                return XCTFail("typed budget error expected, got \(error)")
            }
            XCTAssertEqual(limit, 400_000_000)
            XCTAssertGreaterThan(pixels, limit)
        }
        // 10000² × 2² = 400,000,000 == limit → accepted (100MP ×2 sits on
        // the line, Lumen parity); 42×42 grid of exact 256 tiles.
        let atLimit = try TilePlanner.plan(
            inputWidth: 10000, inputHeight: 10000, scale: 2,
            supportedEdges: [256])
        XCTAssertEqual(atLimit.tiles.count, 1764)
    }

    func testInvalidDimensionsThrow() throws {
        XCTAssertThrowsError(
            try TilePlanner.plan(
                inputWidth: 0, inputHeight: 10, scale: 4, supportedEdges: [256]))
        XCTAssertThrowsError(
            try TilePlanner.plan(
                inputWidth: 10, inputHeight: 10, scale: 0, supportedEdges: [256]))
        XCTAssertThrowsError(
            try TilePlanner.plan(
                inputWidth: 10, inputHeight: 10, scale: 4, supportedEdges: []))
    }

    // MARK: - Progress

    func testProgressIsMonotoneWithPinnedEndpoints() throws {
        let total = 37
        var previous = 0
        for done in 0...total {
            let percent = TilePlanner.progressPercent(done: done, total: total)
            XCTAssertGreaterThanOrEqual(percent, previous, "monotone non-decreasing")
            previous = percent
        }
        XCTAssertEqual(TilePlanner.progressPercent(done: 0, total: total), 15)
        XCTAssertEqual(TilePlanner.progressPercent(done: total, total: total), 93)
        // Degenerate totals clamp instead of dividing by zero.
        XCTAssertEqual(TilePlanner.progressPercent(done: 5, total: 0), 15)
    }
}
