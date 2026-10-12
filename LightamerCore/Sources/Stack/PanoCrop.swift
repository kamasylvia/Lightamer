import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PanoCrop (Plan M5-3-02 T3; KD-8) — the panorama valid-domain crop: the
// ≤1024-cell conservative min-pool grid and the largest all-valid rectangle
// via the histogram-stack algorithm, with a brute-force reference
// implementation for the G3④ bit-identity golden (production never calls
// it). Pure CPU, stateless, deterministic.
//
// MIT ATTRIBUTION (CONVENTIONS 参考项目节): Portions derived from Lumen RAW
// (lumen-raw, MIT) — the CROP-SEGMENT STRUCTURE: `inner_crop`
// (merge.py:100-117) verbatim decomposition — the ≤1024-cell min-pool step
// (`step=max(1,ceil(max(h,w)/1024))`, conservative: one invalid pixel
// poisons its whole cell), the per-row height accumulation + monotonic
// stack largest-rectangle pass (the strictly-greater area tie-break and
// the strict-< push guard are the Lumen forms), the empty-rectangle typed
// failure (merge.py:115), and the `x0*step … min(w, x1*step)` pixel
// rescale. Swift rewrite.
// ─────────────────────────────────────────────────────────────────────────────

/// The inner-crop rectangle in PIXEL coordinates (x1/y1 exclusive — the
/// Lumen `output[y0:y1, x0:x1]` slicing convention).
public struct PanoCropRect: Sendable, Equatable {
    public let x0: Int
    public let y0: Int
    public let x1: Int
    public let y1: Int

    public init(x0: Int, y0: Int, x1: Int, y1: Int) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    public var width: Int { x1 - x0 }
    public var height: Int { y1 - y0 }
}

public enum PanoCrop {

    // MARK: - Constants (KD-8: file constants, NOT parameters)

    /// The pooled-grid long-edge cell budget (merge.py:102
    /// `ceil(max(h,w)/1024)`).
    public static let maxGridCells = 1024

    // MARK: - The min-pool grid (merge.py:102-104)

    /// The conservative pooled grid: cell (cx, cy) is valid iff EVERY
    /// covered pixel is valid (`minimum.reduceat` semantics — one invalid
    /// pixel poisons its cell). Returns (grid row-major, gridWidth,
    /// gridHeight, step).
    public static func minPooledGrid(
        valid: [UInt8], width: Int, height: Int
    ) -> (grid: [Bool], gridWidth: Int, gridHeight: Int, step: Int) {
        precondition(valid.count == width * height, "valid mask size mismatch")
        let step = max(1, (max(height, width) + maxGridCells - 1) / maxGridCells)
        let gridWidth = (width + step - 1) / step
        let gridHeight = (height + step - 1) / step
        var grid = [Bool](repeating: false, count: gridWidth * gridHeight)
        for cy in 0..<gridHeight {
            let pixelY0 = cy * step
            let pixelY1 = min(height, pixelY0 + step)
            for cx in 0..<gridWidth {
                let pixelX0 = cx * step
                let pixelX1 = min(width, pixelX0 + step)
                var allValid = true
                scan: for py in pixelY0..<pixelY1 {
                    let row = py * width
                    for px in pixelX0..<pixelX1 where valid[row + px] == 0 {
                        allValid = false
                        break scan
                    }
                }
                grid[cy * gridWidth + cx] = allValid
            }
        }
        return (grid, gridWidth, gridHeight, step)
    }

    // MARK: - The largest all-valid rectangle (merge.py:105-113)

    /// The histogram-stack largest rectangle (the Lumen loop verbatim):
    /// per-row height accumulation, the monotonic stack with the
    /// strictly-greater area tie-break, the strict-< push guard. Typed
    /// failure when no non-empty rectangle exists (merge.py:115 — the
    /// KD-4 canvas-invalid vocabulary).
    public static func innerCrop(
        valid: [UInt8], width: Int, height: Int
    ) throws -> PanoCropRect {
        let (grid, gridWidth, gridHeight, step) = minPooledGrid(
            valid: valid, width: width, height: height)
        var heights = [Int](repeating: 0, count: gridWidth)
        var best = (area: 0, x0: 0, y0: 0, x1: 0, y1: 0)
        for y in 0..<gridHeight {
            let rowBase = y * gridWidth
            for x in 0..<gridWidth {
                heights[x] = grid[rowBase + x] ? heights[x] + 1 : 0
            }
            var stack: [(start: Int, height: Int)] = []
            for x in 0...gridWidth {
                let value = x < gridWidth ? heights[x] : 0
                var start = x
                while let top = stack.last, top.height > value {
                    stack.removeLast()
                    let area = top.height * (x - top.start)
                    if area > best.area {
                        best = (
                            area, top.start, y - top.height + 1, x, y + 1)
                    }
                    start = top.start
                }
                if stack.isEmpty || stack.last!.height < value {
                    stack.append((start, value))
                }
            }
        }
        guard best.area > 0 else {
            throw AppError.invalidParameter(
                PanoMatch.FailurePrefix.canvas
                    + "no all-valid rectangle exists")
        }
        return PanoCropRect(
            x0: best.x0 * step,
            y0: best.y0 * step,
            x1: min(width, best.x1 * step),
            y1: min(height, best.y1 * step))
    }

    // MARK: - The brute-force reference (G3④ golden anchor; NOT production)

    /// The O(N²M²) reference over the SAME pooled grid: every cell rect
    /// enumerated (y0/x0/y1/x1 ascending) with O(1) all-valid checks via
    /// the invalid-count prefix sums, strictly-greater area tie-break.
    /// Same typed failure, same pixel rescale — the histogram stack must
    /// land byte-identical on unique-maximum shapes (the G3④ fixtures).
    public static func innerCropNaive(
        valid: [UInt8], width: Int, height: Int
    ) throws -> PanoCropRect {
        let (grid, gridWidth, gridHeight, step) = minPooledGrid(
            valid: valid, width: width, height: height)
        // Prefix sums of INVALID cells (padded +1 on every edge).
        var prefix = [[Int]](
            repeating: [Int](repeating: 0, count: gridWidth + 1),
            count: gridHeight + 1)
        for cy in 0..<gridHeight {
            for cx in 0..<gridWidth {
                prefix[cy + 1][cx + 1] = prefix[cy][cx + 1]
                    + prefix[cy + 1][cx]
                    - prefix[cy][cx]
                    + (grid[cy * gridWidth + cx] ? 0 : 1)
            }
        }
        func invalidCount(
            _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int
        ) -> Int {
            prefix[y1 + 1][x1 + 1] - prefix[y0][x1 + 1]
                - prefix[y1 + 1][x0] + prefix[y0][x0]
        }
        var best = (area: 0, x0: 0, y0: 0, x1: 0, y1: 0)
        for y0 in 0..<gridHeight {
            for x0 in 0..<gridWidth {
                for y1 in y0..<gridHeight {
                    for x1 in x0..<gridWidth {
                        let area = (y1 - y0 + 1) * (x1 - x0 + 1)
                        if area > best.area,
                           invalidCount(x0, y0, x1, y1) == 0 {
                            best = (area, x0, y0, x1 + 1, y1 + 1)
                        }
                    }
                }
            }
        }
        guard best.area > 0 else {
            throw AppError.invalidParameter(
                PanoMatch.FailurePrefix.canvas
                    + "no all-valid rectangle exists")
        }
        return PanoCropRect(
            x0: best.x0 * step,
            y0: best.y0 * step,
            x1: min(width, best.x1 * step),
            y1: min(height, best.y1 * step))
    }
}
