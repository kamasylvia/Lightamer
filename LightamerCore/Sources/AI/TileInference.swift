import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// TileInference (Plan M2-10-06 KD-1) — the MODEL-FREE tiling pure face:
// grid planning, overlap blend weights, feed-shape mapping, progress
// scaling, and the 400-megapixel output budget. No CoreML, no I/O —
// everything here is unit-testable without a model (the resource-gate
// discipline: the REAL-model legs live in the worker + engine, tested
// behind XCTSkip).
//
// PLANNING RULES (KD-1):
//   • NO INPUT PADDING on the grid: spans tile the input axis exactly.
//     Tiles after the first use `tileEdge - overlap` strides; the LAST
//     tile is aligned to the axis END so every span of a long axis is
//     EXACTLY `tileEdge` wide (the fixed-shape discipline — a truncated
//     remainder strip cannot feed a fixed-shape model, and padding is
//     banned on the grid; Lumen MODEL.md:8 "输入不做额外补边" paradigm).
//     An axis SHORTER than the tile edge is ONE exact-length span (the
//     feed is then PAD-TO-FIT — the only padding in the system, mirroring
//     the DRUNet-internal pad-and-crop precedent, Lumen MODEL.md 1.1).
//   • BLEND = linear ramp over the OVERLAP (16 px input-side), separable
//     per axis. The per-pixel accumulated weight is the axis-sum product
//     and is strictly positive everywhere; dividing by it normalizes the
//     tile contributions to sum EXACTLY 1 (the test anchor). Weights map
//     to output space by ×scale repetition (Lumen `np.repeat(w, scale)`).
//   • PROGRESS: `15 + 78 * done/total` — the Lumen three-segment budget
//     (decode 15% / tiles 78% / save 7%), monotone non-decreasing.
//   • BUDGET: 400,000,000 OUTPUT pixels (Lumen `large_image.MAX_PIXELS`
//     parity — `validate_size` checks the SCALED geometry (h·scale,
//     w·scale) against the cap); exceeded = typed rejection, never an
//     allocation. Note the pixel-domain arithmetic: ×4 LINEAR scale is a
//     ×16 pixel multiplier, so the cap admits ~25 MP inputs at ×4 and
//     100 MP at ×2 (the plan's "100MP ×4 = 4 亿贴线" arithmetic was the
//     pixel-domain reading — DECISIONS M2-10-06 pins the output-geometry
//     rule, the Lumen-parity one).
//
// FEED SHAPES: the planner takes the model's SUPPORTED input edges
// (discovered from the worker's open response — a static-converted asset
// supports exactly its baked edge, e.g. manifest.inputSize = 256). The
// grid's base edge is the SMALLEST supported edge; a span maps to its
// feed by "smallest supported edge ≥ span length" (exact for grid tiles,
// pad-to-fit only for sub-tile images).
// ─────────────────────────────────────────────────────────────────────────────

/// The typed tiling failures (the dialog maps these to honest copy text).
public enum TileInferenceError: Error, Equatable, Sendable {
    /// The scaled output exceeds the 400 MP budget (Lumen `validate_size`
    /// parity: "图像超过 4 亿像素，请裁切或降低输出倍率。").
    case pixelBudgetExceeded(outputPixels: Int, limit: Int)
    /// Dimensions degenerate (zero/negative input, scale < 1, or an empty
    /// supported-edge set).
    case invalidDimensions
    /// A span longer than every supported edge (cannot happen for
    /// planner-produced grids — defensive for direct callers).
    case unsupportedTileEdge(length: Int)
}

/// One planned tiling: the input grid, the feed shapes, and the output
/// geometry. Pure value — the engine executes it, tests assert it.
public struct TileGrid: Equatable, Sendable {

    /// One axis span in INPUT space (`start` inclusive, `start + length`
    /// exclusive).
    public struct Span: Equatable, Sendable {
        public let start: Int
        public let length: Int

        public init(start: Int, length: Int) {
            self.start = start
            self.length = length
        }
    }

    /// One tile: the input rect, the FEED shape the model runs at (≥ the
    /// rect — larger only in the pad-to-fit sub-tile case), and the output
    /// rect (input rect × scale).
    public struct Tile: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int
        /// The shape the model is fed (`feedWidth × feedHeight` — the
        /// worker session's compiled-shape key, the ShapedSessions LRU).
        public let feedWidth: Int
        public let feedHeight: Int

        public init(
            x: Int, y: Int, width: Int, height: Int,
            feedWidth: Int, feedHeight: Int
        ) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.feedWidth = feedWidth
            self.feedHeight = feedHeight
        }
    }

    /// Input dimensions.
    public let width: Int
    public let height: Int
    /// The super-resolution factor (1 for denoise).
    public let scale: Int
    /// The input-side overlap in pixels (the ramp width).
    public let overlap: Int
    /// The grid's base edge (the smallest supported edge).
    public let tileEdge: Int
    /// Row-major tiles (y outer, x inner — the execution order).
    public let tiles: [Tile]
    /// Output dimensions (`width × scale`, `height × scale`).
    public var outputWidth: Int { width * scale }
    public var outputHeight: Int { height * scale }

    /// The output-space rect of a tile (input rect × scale).
    public func outputRect(of tile: Tile) -> (
        x: Int, y: Int, width: Int, height: Int
    ) {
        (tile.x * scale, tile.y * scale, tile.width * scale, tile.height * scale)
    }
}

public enum TilePlanner {

    /// The tile shape family (KD-1: {256, 512}; 256 = the manifest
    /// inputSize base — M2-10-01 DECISIONS §7/§8. The planner's grid uses
    /// the smallest SUPPORTED edge; the 512 member is the large-tile lever
    /// for future flexible-shape assets, not a current-path input).
    public static let shapeFamily: [Int] = [256, 512]

    /// The input-side overlap (the linear-ramp width).
    public static let overlap = 16

    /// The output-pixel budget (Lumen `MAX_PIXELS` parity).
    public static let maxOutputPixels = 400_000_000

    // MARK: - Axis spans

    /// The axis spans for one dimension: exact `tileEdge` tiles with the
    /// LAST tile aligned to the axis end (every span of a long axis is
    /// exactly `tileEdge`); an axis ≤ tileEdge is ONE exact span.
    public static func axisSpans(
        length: Int, tileEdge: Int, overlap: Int = TilePlanner.overlap
    ) -> [TileGrid.Span] {
        precondition(tileEdge > 0, "tileEdge must be positive")
        guard length > 0 else { return [] }
        guard length > tileEdge else { return [TileGrid.Span(start: 0, length: length)] }
        let stride = tileEdge - max(0, min(overlap, tileEdge - 1))
        let remainder = length - tileEdge
        let count = 1 + Int((Double(remainder) / Double(stride)).rounded(.up))
        var spans: [TileGrid.Span] = []
        spans.reserveCapacity(count)
        for index in 0..<count {
            let start = min(index * stride, remainder)
            if spans.last?.start == start { continue }
            spans.append(TileGrid.Span(start: start, length: tileEdge))
        }
        return spans
    }

    // MARK: - Blend weights (separable, linear ramp)

    /// The blend weight of ONE span at input `position` (0 outside the
    /// span). Linear ramp over `overlap` at interior edges only:
    /// `(i+1)/n` rising into the span, mirrored falling out.
    public static func spanWeight(
        span: TileGrid.Span, position: Int, axisLength: Int,
        overlap: Int = TilePlanner.overlap
    ) -> Float {
        let relative = position - span.start
        guard relative >= 0, relative < span.length else { return 0 }
        let ramp = min(overlap, span.length)
        var weight: Float = 1
        if span.start > 0, relative < ramp {
            weight *= Float(relative + 1) / Float(ramp)
        }
        let fromEnd = span.length - 1 - relative
        if span.start + span.length < axisLength, fromEnd < ramp {
            weight *= Float(fromEnd + 1) / Float(ramp)
        }
        return weight
    }

    /// The accumulated per-position weight sums along one axis (the
    /// normalization denominators). Strictly positive everywhere the
    /// spans cover — the test anchor divides by these.
    public static func axisWeightSums(
        spans: [TileGrid.Span], length: Int,
        overlap: Int = TilePlanner.overlap
    ) -> [Float] {
        var sums = [Float](repeating: 0, count: length)
        for span in spans {
            for relative in 0..<span.length {
                let position = span.start + relative
                guard position < length else { break }
                sums[position] += spanWeight(
                    span: span, position: position, axisLength: length,
                    overlap: overlap)
            }
        }
        return sums
    }

    // MARK: - Planning

    /// Plan the full tiling. `supportedEdges` = the model's supported
    /// input edges (ascending; discovered at worker open — a static asset
    /// supports exactly one). The base edge = the smallest supported.
    public static func plan(
        inputWidth: Int, inputHeight: Int, scale: Int,
        supportedEdges: [Int], overlap: Int = TilePlanner.overlap
    ) throws -> TileGrid {
        guard inputWidth >= 1, inputHeight >= 1, scale >= 1,
              !supportedEdges.isEmpty
        else { throw TileInferenceError.invalidDimensions }
        let outputPixels = inputWidth * scale * (inputHeight * scale)
        guard outputPixels <= maxOutputPixels else {
            throw TileInferenceError.pixelBudgetExceeded(
                outputPixels: outputPixels, limit: maxOutputPixels)
        }
        let edges = supportedEdges.sorted()
        let tileEdge = edges[0]
        let rowSpans = axisSpans(length: inputHeight, tileEdge: tileEdge, overlap: overlap)
        let columnSpans = axisSpans(length: inputWidth, tileEdge: tileEdge, overlap: overlap)
        var tiles: [TileGrid.Tile] = []
        tiles.reserveCapacity(rowSpans.count * columnSpans.count)
        for row in rowSpans {
            for column in columnSpans {
                tiles.append(TileGrid.Tile(
                    x: column.start, y: row.start,
                    width: column.length, height: row.length,
                    feedWidth: try feedEdge(
                        spanLength: column.length, supportedEdges: edges),
                    feedHeight: try feedEdge(
                        spanLength: row.length, supportedEdges: edges)))
            }
        }
        return TileGrid(
            width: inputWidth, height: inputHeight, scale: scale,
            overlap: overlap, tileEdge: tileEdge, tiles: tiles)
    }

    /// The FEED edge for one span: the smallest supported edge ≥ the span
    /// length (exact for grid tiles; pad-to-fit for sub-tile spans).
    public static func feedEdge(
        spanLength: Int, supportedEdges: [Int]
    ) throws -> Int {
        guard spanLength >= 1, !supportedEdges.isEmpty else {
            throw TileInferenceError.invalidDimensions
        }
        for edge in supportedEdges.sorted() where edge >= spanLength {
            return edge
        }
        throw TileInferenceError.unsupportedTileEdge(length: spanLength)
    }

    // MARK: - Progress (the Lumen three-segment budget)

    /// `15 + 78 * done/total` clamped to 15...93 — the tile phase's share
    /// (decode holds 15, save holds the 93...100 tail). Monotone in `done`.
    public static func progressPercent(done: Int, total: Int) -> Int {
        guard total > 0, done >= 0 else { return 15 }
        let fraction = min(Double(done) / Double(total), 1)
        return 15 + Int((78 * fraction).rounded())
    }
}
