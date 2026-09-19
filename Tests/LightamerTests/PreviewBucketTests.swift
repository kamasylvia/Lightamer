@testable import LightamerCore
import XCTest

/// D-C3 quantization ladder (Plan 02-03-01): the bucket function is pure,
/// snap-DOWN, capped at 2560, floored at 360. The boundary table is the
/// plan's must-have list verbatim (×2 defaults) plus the raw-target
/// boundaries asserted via `pixelScale: 1.0` (2559→2200, 1121→1120,
/// 1119→760, 2599→2560-cap) — no Metal, no GPU guard needed.
final class PreviewBucketTests: XCTestCase {

    /// The plan's ×2 boundary table (default `pixelScale: 2.0`).
    func testDefaultPixelScaleBoundaries() {
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 1280), 2560, "1280×2=2560 → top step, on the cap")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 1279), 2200, "1279×2=2558 → snap down off the cap")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 920), 1840, "920×2=1840 → exact step hit")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 740), 1480, "740×2=1480 → exact step hit")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 560), 1120, "560×2=1120 → exact step hit")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 380), 760, "380×2=760 → exact step hit")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 180), 360, "180×2=360 → exact floor hit")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 100), 360, "100×2=200 → below the ladder → floor")
    }

    /// Raw-target boundaries (the plan Must-have list): pass `pixelScale: 1`
    /// so the input IS the pixel target — proves snap-DOWN direction and
    /// that the 2560 CAP (not 2200) catches near-cap targets.
    func testRawTargetBoundaries() {
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 2560, pixelScale: 1), 2560, "cap on the nose")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 2599, pixelScale: 1), 2560, "2599 is ABOVE the cap → capped to 2560, NOT snapped to 2200")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 2559, pixelScale: 1), 2200, "2559 under the cap by 1 → snap down to 2200")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 2201, pixelScale: 1), 2200, "just inside the 2200 step")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 2199, pixelScale: 1), 1840, "just below the 2200 step")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 1121, pixelScale: 1), 1120, "one above a step stays on the step")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 1119, pixelScale: 1), 760, "one below a step falls a full step")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 361, pixelScale: 1), 360, "one above the floor")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 200, pixelScale: 1), 360, "below-ladder target → floor")
    }

    /// Non-2 scales are honored (e.g. 1× non-Retina drawable, or a future
    /// 3× preview-quality setting).
    func testPixelScaleOverrideHonored() {
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 1280, pixelScale: 1), 1120, "1280 @1× → 1120 step")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 900, pixelScale: 3), 2560, "900×3=2700 → capped at 2560")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 380, pixelScale: 2.2), 760, "380×2.2=836 → snap DOWN to 760")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 700, pixelScale: 1.5), 760, "700×1.5=1050 → snap DOWN to 760")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 700, pixelScale: 1.7), 1120, "700×1.7=1190 → snap DOWN to 1120")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 900, pixelScale: 2.5), 2200, "900×2.5=2250 → snap DOWN to 2200")
    }

    /// Defensive: degenerate drawables never produce a non-ladder value.
    func testDegenerateInputsFloorAt360() {
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 0), 360)
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: -320), 360)
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 500, pixelScale: 0), 360, "zero scale is degenerate")
        XCTAssertEqual(PreviewBucket.longEdge(forDrawable: 500, pixelScale: -2), 360, "negative scale is degenerate")
    }

    /// The published constants match the D-C3 decision document exactly
    /// (a silent constant edit would silently change every bucket).
    func testPublishedConstantsMatchDC3() {
        XCTAssertEqual(PreviewBucket.cap, 2560)
        XCTAssertEqual(PreviewBucket.ladder, [2560, 2200, 1840, 1480, 1120, 760, 360])
    }
}
