/// Pure tile-grid geometry (Plan 02-05-06; D-20). Given a plane's
/// dimensions and a per-tile BYTE budget, produce the tile grid — nothing
/// more.
///
/// **LIVE since Plan 03-05-T6** (the toneequal FULL engagement): the tile
/// execution driver lives in `PixelPipe.executeTiled` — the grid comes
/// from `tiles(...)` with the MODULE-REPORTED halo
/// (`IOPModule.tileHalo`, bytes-per-pixel from `tileWorkingSetBytesPerPixel`)
/// and per-tile cache keys are NOT needed (the tile driver runs INSIDE a
/// single module execution: upstream plane rendered once, tiles blitted
/// out — the cache sees one whole plane either way). Phase 5's denoise
/// iops (`denoiseprofile`'s 7-band wavelet / NLMeans working sets) reuse
/// the same driver by declaring the seam values.
///
/// Deterministic pure function — trivially testable.
public struct TilingPlan: Sendable, Equatable {

    /// One tile rectangle in PLANE pixel coordinates.
    public struct Tile: Sendable, Equatable {

        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int

        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// Area in pixels (the budget-relevant quantity).
        public var pixelCount: Int { width * height }
    }

    /// Decompose a `forWidth × forHeight` plane into tiles, each at most
    /// `maxTileBytes` bytes at the given `bytesPerPixel`.
    ///
    /// Grid math: square tiles of side `⌊√(maxTileBytes / bytesPerPixel)⌋`
    /// (≥ 1); `ceil(dimension / side)` tiles per axis; edge tiles shrink
    /// to the remaining extent (interior tiles stay full-size, so
    /// adjacent tiles SHARE an edge — no gaps, no overlaps, full cover:
    /// the sum of `pixelCount` is exactly `width × height`).
    ///
    /// `overlap` (LIVE since 03-05-T6 — the toneequal FULL engagement):
    /// each tile's rect shrinks by `overlap` on every edge it SHARES with
    /// a neighbor (interior edges); border edges keep their extent. The
    /// shrunk rects are the OUTPUT regions; the tile driver
    /// (`PixelPipe.executeTiled`) reads each tile WIDENED by the
    /// module-reported halo (`IOPModule.tileHalo` — for toneequal the dt
    /// modify_roi_in radius plus the IIR runway), so the discarded
    /// shrink ring is exactly the halo-contaminated margin and the tile
    /// output matches whole-plane execution.
    ///
    /// Degenerate inputs produce ZERO tiles: non-positive dimensions or a
    /// non-positive byte budget.
    public static func tiles(
        forWidth width: Int,
        height: Int,
        maxTileBytes: Int,
        bytesPerPixel: Int = WorkingSpace.bytesPerPixel,
        overlap: Int = 0
    ) -> [Tile] {
        guard width > 0, height > 0, maxTileBytes > 0, bytesPerPixel > 0 else {
            return []
        }
        let tileArea = maxTileBytes / bytesPerPixel
        guard tileArea >= 1 else { return [] }
        let side = max(1, Int((Double(tileArea).squareRoot())))

        let columns = (width + side - 1) / side
        let rows = (height + side - 1) / side

        var plan: [Tile] = []
        plan.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                var x = column * side
                var y = row * side
                var tileWidth = min(side, width - x)
                var tileHeight = min(side, height - y)

                // Overlap policy (LIVE, 03-05-T6): shrink on INTERIOR
                // edges only — the shrunk ring is what the tile driver's
                // halo-widened read rect covers.
                let shrinksLeft = column > 0
                let shrinksRight = column < columns - 1
                let shrinksTop = row > 0
                let shrinksBottom = row < rows - 1
                if shrinksLeft {
                    x += overlap
                    tileWidth -= overlap
                }
                if shrinksRight {
                    tileWidth -= overlap
                }
                if shrinksTop {
                    y += overlap
                    tileHeight -= overlap
                }
                if shrinksBottom {
                    tileHeight -= overlap
                }
                // An overlap ≥ half the tile side could invert a tile;
                // clamp to a legal (possibly degenerate-slim) rect and
                // let Phase 5's policy own sanity beyond that.
                plan.append(
                    Tile(
                        x: x, y: y,
                        width: max(tileWidth, 0),
                        height: max(tileHeight, 0)
                    )
                )
            }
        }
        return plan
    }
}
