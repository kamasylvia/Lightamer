@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoCropTests (Plan M5-3-02 T3; KD-11 G3④) — the valid-domain crop's gates:
//
// G3④ the histogram stack vs the brute-force reference, BIT-IDENTICAL on the
// unique-maximum shape matrix (L shape / double island / full grid / single
// row / notched band), the all-invalid typed failure on both paths, the
// min-pool conservatism (one invalid pixel poisons its cell), the pixel-
// bounds rescale clamp, and the max-area agreement on seeded random grids
// (area equality only — the tie-break freedom is the DECISIONS note).
// ─────────────────────────────────────────────────────────────────────────────

final class PanoCropTests: XCTestCase {

    // MARK: - Fixtures

    /// A pixel mask from row strings ('#' = valid, '.' = invalid).
    private func mask(
        _ rows: [String]
    ) -> (valid: [UInt8], width: Int, height: Int) {
        let width = rows[0].count
        let height = rows.count
        var valid = [UInt8](repeating: 0, count: width * height)
        for (y, row) in rows.enumerated() {
            precondition(row.count == width, "ragged fixture rows")
            for (x, character) in row.enumerated() where character == "#" {
                valid[y * width + x] = 1
            }
        }
        return (valid, width, height)
    }

    private func assertBothPaths(
        _ rows: [String], expected: PanoCropRect,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = mask(rows)
        let stacked = try PanoCrop.innerCrop(
            valid: fixture.valid, width: fixture.width, height: fixture.height)
        XCTAssertEqual(stacked, expected, file: file, line: line)
        let naive = try PanoCrop.innerCropNaive(
            valid: fixture.valid, width: fixture.width, height: fixture.height)
        XCTAssertEqual(
            naive, expected, "naive diverged", file: file, line: line)
        XCTAssertEqual(
            stacked, naive, "paths diverged", file: file, line: line)
    }

    // MARK: - G3④: the shape matrix (bit-identical paths)

    func testLShapeMatchesNaiveBitIdentical() throws {
        // L shape: the unique max rectangle is the vertical bar (3×5 = 15;
        // the horizontal arm's 6×2 = 12 and every other candidate lose).
        try assertBothPaths(
            [
              "######...",
              "######...",
              "###......",
              "###......",
              "###......",
            ],
            expected: PanoCropRect(x0: 0, y0: 0, x1: 3, y1: 5))
    }

    func testDoubleIslandMatchesNaiveBitIdentical() throws {
        // Two disjoint islands: the larger one wins (12 vs 6 — unique).
        try assertBothPaths(
            [
              "....####....",
              "....####....",
              "....####....",
              "............",
              "..###.......",
              "..###.......",
            ],
            expected: PanoCropRect(x0: 4, y0: 0, x1: 8, y1: 3))
    }

    func testFullGridMatchesNaiveBitIdentical() throws {
        try assertBothPaths(
            [
              "#####",
              "#####",
              "#####",
            ],
            expected: PanoCropRect(x0: 0, y0: 0, x1: 5, y1: 3))
    }

    func testSingleRowMatchesNaiveBitIdentical() throws {
        try assertBothPaths(
            [
              "..........",
              "..#######.",
              "..........",
            ],
            expected: PanoCropRect(x0: 2, y0: 1, x1: 9, y1: 2))
    }

    func testNotchedBandMatchesNaiveBitIdentical() throws {
        // A notch bitten out of the top edge of a 4-row band: the largest
        // rect is the notch-free 2-row bottom (8×2 = 16; the 5×3 right
        // block loses).
        try assertBothPaths(
            [
              "###..###",
              "###..###",
              "########",
              "########",
            ],
            expected: PanoCropRect(x0: 0, y0: 2, x1: 8, y1: 4))
    }

    // MARK: - The typed failure (KD-8 / merge.py:115)

    func testAllInvalidTypedOnBothPaths() {
        let empty = [UInt8](repeating: 0, count: 12)
        XCTAssertThrowsError(try PanoCrop.innerCrop(
            valid: empty, width: 4, height: 3)) { error in
            guard case AppError.invalidParameter(let message) = error else {
                XCTFail("expected invalidParameter, got \(error)")
                return
            }
            XCTAssertTrue(
                message.hasPrefix(PanoMatch.FailurePrefix.canvas),
                "canvas-invalid prefix required: \(message)")
        }
        XCTAssertThrowsError(try PanoCrop.innerCropNaive(
            valid: empty, width: 4, height: 3)) { error in
            guard case AppError.invalidParameter(_) = error else {
                XCTFail("expected invalidParameter, got \(error)")
                return
            }
        }
        // A single isolated valid cell IS a 1×1 rectangle (both paths).
        let fixture = mask(["...", ".#."])
        let stacked = try? PanoCrop.innerCrop(
            valid: fixture.valid, width: fixture.width, height: fixture.height)
        XCTAssertEqual(stacked, PanoCropRect(x0: 1, y0: 1, x1: 2, y1: 2))
    }

    // MARK: - The min-pool conservatism (KD-8)

    func testMinPoolOneInvalidPixelPoisonsItsCell() throws {
        // A 2048-wide mask has step 2 exactly: one invalid pixel at row 1,
        // x = 1024 poisons cell 512 (covering 1024..1025) and the crop's
        // bottom band (rows 2-3, 2048×2 = 4096 — the unique max) must
        // start below the poisoned row.
        let width = 2048
        let height = 6
        var valid = [UInt8](repeating: 1, count: width * height)
        valid[1 * width + 1024] = 0
        let pooled = PanoCrop.minPooledGrid(
            valid: valid, width: width, height: height)
        XCTAssertEqual(pooled.step, 2)
        XCTAssertEqual(pooled.gridWidth, 1024)
        XCTAssertEqual(pooled.gridHeight, 3)
        // y = 1 lands in grid row 0 (each cell spans 2 pixel rows).
        XCTAssertFalse(pooled.grid[0 * pooled.gridWidth + 512])
        XCTAssertTrue(pooled.grid[0 * pooled.gridWidth + 511])
        XCTAssertTrue(pooled.grid[1 * pooled.gridWidth + 512])
        // Unique max = the untouched bottom band (2048×4 = 8192; the left
        // block's 1024×6 = 6144 loses).
        let crop = try PanoCrop.innerCrop(
            valid: valid, width: width, height: height)
        XCTAssertEqual(crop, PanoCropRect(x0: 0, y0: 2, x1: width, y1: 6))
    }

    func testPooledRowsShareTheCellBudget() {
        // Both dimensions pool under ONE step (the max(h, w) form).
        let width = 3000
        let height = 10
        let valid = [UInt8](repeating: 1, count: width * height)
        let pooled = PanoCrop.minPooledGrid(
            valid: valid, width: width, height: height)
        XCTAssertEqual(pooled.step, 3) // ceil(3000/1024) = 3
        XCTAssertEqual(pooled.gridWidth, 1000) // ceil(3000/3)
        XCTAssertEqual(pooled.gridHeight, 4) // ceil(10/3)
    }

    // MARK: - The bounds clamp (KD-8)

    func testRescaleClampsToPixelBounds() throws {
        // All-valid 2050×3: step 3, gridWidth 684 → 684×3 = 2052 > 2050 —
        // the rescale clamps to the pixel bounds.
        let width = 2050
        let height = 3
        let valid = [UInt8](repeating: 1, count: width * height)
        let crop = try PanoCrop.innerCrop(
            valid: valid, width: width, height: height)
        XCTAssertEqual(
            crop, PanoCropRect(x0: 0, y0: 0, x1: width, y1: height))
    }

    // MARK: - Random-grid agreement (area equality; tie-break freedom)

    func testRandomGridsAgreeOnMaxArea() throws {
        // Ten seeded random grids: the two algorithms must agree on the
        // max AREA; the rects may differ on ties (the Lumen stack's
        // discovery-order tie-break is the production behavior — the
        // DECISIONS note; the golden shapes above are tie-free).
        var state: UInt64 = 0x9E3779B97F4A7C15
        for trial in 0..<10 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let width = 17 + Int((state >> 33) % 23)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let height = 11 + Int((state >> 33) % 19)
            var valid = [UInt8](repeating: 0, count: width * height)
            for index in valid.indices {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                valid[index] = (state >> 63) == 0 ? 1 : 0
            }
            let stacked = try PanoCrop.innerCrop(
                valid: valid, width: width, height: height)
            let naive = try PanoCrop.innerCropNaive(
                valid: valid, width: width, height: height)
            XCTAssertEqual(
                stacked.width * stacked.height,
                naive.width * naive.height,
                "trial \(trial): max area diverged")
        }
    }
}
