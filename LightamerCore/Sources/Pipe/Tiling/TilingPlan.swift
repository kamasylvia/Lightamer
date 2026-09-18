/// Pure tile-grid geometry (Plan 02-05-06; D-20 scaffolding + ROADMAP
/// SC#4 tail: "tiling fallback scaffolding in place"). Given a plane's
/// dimensions and a per-tile BYTE budget, produce the tile grid — nothing
/// more.
///
/// **NOT wired into the pipe — by decision.** `PixelPipe.processRec` runs
/// whole-plane (D-20: 100MP float32 ≈ 1.6GB fits unified memory at pipe
/// level; spike-b kept the 100MP budget with ping-pong + selective
/// caching). Tiling becomes LOAD-BEARING in Phase 5 when the denoise iops
/// arrive (`denoiseprofile`'s 7-band wavelet / NLMeans working sets
/// exceed the per-tile budget). Phase 5 fills this scaffold WITHOUT
/// redesign; the explicit hooks it must define are:
///
/// - `// Phase 5:` kernel-specific overlap policy (NLMeans search radius,
///   wavelet scale halo) — the current `overlap` shrink is a PLACEHOLDER
///   so the grid math and its tests exist before the semantics do;
/// - `// Phase 5:` tile execution driver inside `processRec` (tile-wise
///   recursion + per-tile cache keys + halo stitching);
/// - `// Phase 5:` budget derivation (`maxTileBytes` from the D-C1 3GB
///   pipe budget minus plane reservations).
///
/// Deterministic pure function — trivially testable, no Metal, no actor.
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
    /// `overlap` (PLACEHOLDER policy — Phase 5 defines kernel-specific
    /// overlap, e.g. the NLMeans radius): each tile's rect shrinks by
    /// `overlap` on every edge it SHARES with a neighbor (interior
    /// edges). Border edges keep their extent, so a lone tile is
    /// untouched. Shrunk regions are the kernel's halo input under a real
    /// policy; documented as the seam Phase 5 replaces.
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

                // Placeholder overlap policy: shrink on INTERIOR edges
                // only (Phase 5 replaces with the kernel-specific halo).
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
