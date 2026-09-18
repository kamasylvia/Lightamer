@testable import LightamerCore
import XCTest

/// `TilingPlan` pure grid math (Plan 02-05-06; D-20 scaffolding). The
/// scaffold is UNWIRED into `processRec` by decision — these tests pin the
/// geometry Phase 5's tile driver will consume: exact grids, interior-edge
/// overlap shrink (placeholder policy), full-cover accounting, degenerate
/// inputs.
final class TilingPlanTests: XCTestCase {

    /// 100×100 with a budget forcing 3×3: `maxTileBytes = 2000` at 1 B/px
    /// → tileArea 2000 → side ⌊√2000⌋ = 44 → ceil(100/44) = 3 per axis.
    func testThreeByThreeGridForHundredSquare() {
        let tiles = TilingPlan.tiles(
            forWidth: 100, height: 100, maxTileBytes: 2000, bytesPerPixel: 1
        )
        XCTAssertEqual(tiles.count, 9)

        // Row 0: x origins 0 / 44 / 88, edge tile shrinks to the remainder.
        XCTAssertEqual(tiles[0], TilingPlan.Tile(x: 0, y: 0, width: 44, height: 44))
        XCTAssertEqual(tiles[1], TilingPlan.Tile(x: 44, y: 0, width: 44, height: 44))
        XCTAssertEqual(tiles[2], TilingPlan.Tile(x: 88, y: 0, width: 12, height: 44))
        // Center tile (no shrink without overlap).
        XCTAssertEqual(tiles[4], TilingPlan.Tile(x: 44, y: 44, width: 44, height: 44))
        // Bottom-right corner keeps only the 12px remainder both ways.
        XCTAssertEqual(tiles[8], TilingPlan.Tile(x: 88, y: 88, width: 12, height: 12))

        // Full cover: adjacent tiles share edges — no gaps, no overlaps.
        XCTAssertEqual(
            tiles.reduce(0) { $0 + $1.pixelCount }, 100 * 100,
            "sum of pixelCount == plane area (full-cover invariant)"
        )
    }

    /// Placeholder overlap policy: every tile shrinks by `overlap` on each
    /// edge SHARED with a neighbor; border edges keep their extent.
    func testOverlapShrinksInteriorEdgesOnly() {
        let tiles = TilingPlan.tiles(
            forWidth: 100, height: 100, maxTileBytes: 2000,
            bytesPerPixel: 1, overlap: 4
        )
        XCTAssertEqual(tiles.count, 9)

        // Top-left: right+bottom edges are interior → width/height −4.
        XCTAssertEqual(tiles[0], TilingPlan.Tile(x: 0, y: 0, width: 40, height: 40))
        // Top-middle: shrinks on left/right/bottom.
        XCTAssertEqual(tiles[1], TilingPlan.Tile(x: 48, y: 0, width: 36, height: 40))
        // Center: shrinks on all four sides.
        XCTAssertEqual(tiles[4], TilingPlan.Tile(x: 48, y: 48, width: 36, height: 36))
        // Bottom-right: shrinks on top+left only; the 12px remainder plus
        // the left overlap is what survives.
        XCTAssertEqual(tiles[8], TilingPlan.Tile(x: 92, y: 92, width: 8, height: 8))
    }

    /// Degenerate inputs produce ZERO tiles.
    func testDegenerateInputsProduceNoTiles() {
        XCTAssertTrue(TilingPlan.tiles(forWidth: 0, height: 100, maxTileBytes: 2000, bytesPerPixel: 1).isEmpty)
        XCTAssertTrue(TilingPlan.tiles(forWidth: 100, height: -5, maxTileBytes: 2000, bytesPerPixel: 1).isEmpty)
        XCTAssertTrue(TilingPlan.tiles(forWidth: 100, height: 100, maxTileBytes: 0, bytesPerPixel: 1).isEmpty)
        XCTAssertTrue(TilingPlan.tiles(forWidth: 100, height: 100, maxTileBytes: 2000, bytesPerPixel: 0).isEmpty)
        // Budget below one pixel (bytesPerPixel > maxTileBytes).
        XCTAssertTrue(TilingPlan.tiles(forWidth: 100, height: 100, maxTileBytes: 8, bytesPerPixel: 16).isEmpty)
    }

    /// A budget covering the whole plane yields exactly ONE tile at full
    /// extent — and a lone tile has NO interior edges, so overlap is a
    /// no-op on it.
    func testSingleTileWhenBudgetCoversPlane() {
        let tiles = TilingPlan.tiles(
            forWidth: 50, height: 50, maxTileBytes: 10_000, bytesPerPixel: 1
        )
        XCTAssertEqual(tiles, [TilingPlan.Tile(x: 0, y: 0, width: 50, height: 50)])

        let overlapped = TilingPlan.tiles(
            forWidth: 50, height: 50, maxTileBytes: 10_000, bytesPerPixel: 1, overlap: 4
        )
        XCTAssertEqual(overlapped, tiles, "no interior edges → overlap cannot shrink a lone tile")
    }

    /// The default `bytesPerPixel` is the FOUND-02 working format (float32
    /// RGBA, 16 B/px) — the budget math a Phase 5 caller actually uses.
    func testDefaultBytesPerPixelIsWorkingSpace() {
        let tiles = TilingPlan.tiles(
            forWidth: 16, height: 16, maxTileBytes: 16 * 16 * WorkingSpace.bytesPerPixel
        )
        XCTAssertEqual(tiles, [TilingPlan.Tile(x: 0, y: 0, width: 16, height: 16)])
    }
}
