@testable import LightamerIOP
import XCTest

/// LensAutoCropTests (Plan LENS-02 T3, D-LENS-5) — the RawLab bisection
/// port over ANALYTIC edge maps (exact known minimum scales).
///
/// The synthetic warps are constructed so the minimal scale has a closed
/// form: an edge map that samples at a constant factor k around the
/// center (`q = center + (p − center)·k/scale`) is inside exactly when
/// k/scale ≤ 1 — so minimumScale must converge to k (× the 1.00001
/// margin when k > 1). The pure-zoom k=1 face returns exactly 1.0
/// (upstream: the autoCrop block is skipped entirely — no margin).
final class LensAutoCropTests: XCTestCase {

    /// The constant-factor edge map (three identical channels — the pure
    /// distortion-free zoom semantics; per-channel independence is the
    /// kernel's face, not the search's).
    private func zoomEdgeMap(
        factor k: Float, width: Int, height: Int
    ) -> (Float, Float, Float) -> [(x: Float, y: Float)] {
        let cx = Float(width) / 2, cy = Float(height) / 2
        return { x, y, scale in
            let f = k / scale
            let qx = cx + (x - cx) * f
            let qy = cy + (y - cy) * f
            return [(qx, qy), (qx, qy), (qx, qy)]
        }
    }

    func testInsideAtOneReturnsExactOne() {
        let s = LensAutoCrop.minimumScale(
            width: 100, height: 80, edgeMap: zoomEdgeMap(factor: 1, width: 100, height: 80))
        XCTAssertEqual(s, 1.0, "the no-compensation face skips the bisection (no margin)")
    }

    func testClosedFormFactorTwo() {
        // k = 2: inside exactly at scale ≥ 2 → the bisection converges to
        // 2 × 1.00001 (the 18-round floor).
        let s = LensAutoCrop.minimumScale(
            width: 100, height: 80, edgeMap: zoomEdgeMap(factor: 2, width: 100, height: 80))
        let expected: Float = 2 * LensAutoCrop.margin
        XCTAssertNotNil(s)
        XCTAssertEqual(s!, expected, accuracy: 1e-4,
                       "the analytic minimum is k × margin, got \(String(describing: s))")
    }

    func testClosedFormFactorThree() {
        let s = LensAutoCrop.minimumScale(
            width: 64, height: 64, edgeMap: zoomEdgeMap(factor: 3, width: 64, height: 64))
        XCTAssertEqual(s!, 3 * LensAutoCrop.margin, accuracy: 1e-4)
    }

    func testBeyondZoomCapReadsNil() {
        // k = 50: even zoom 8 leaves the frame → unsupported input.
        let s = LensAutoCrop.minimumScale(
            width: 100, height: 100, edgeMap: zoomEdgeMap(factor: 50, width: 100, height: 100))
        XCTAssertNil(s)
    }

    func testDegenerateFramesReadNil() {
        let map = zoomEdgeMap(factor: 1, width: 1, height: 1)
        XCTAssertNil(LensAutoCrop.minimumScale(width: 1, height: 1, edgeMap: map))
        XCTAssertNil(LensAutoCrop.minimumScale(width: 0, height: 10, edgeMap: map))
    }

    /// A NON-finite mapping on any channel footprint fails the inside test
    /// (the three-channel union contract — a per-channel NaN is not
    /// confined to its channel).
    func testNonFiniteChannelFootprintFailsInside() {
        let width = 50, height = 50
        let map: (Float, Float, Float) -> [(x: Float, y: Float)] = { _, _, _ in
            [(Float.nan, 0), (25, 25), (25, 25)]
        }
        // scale 1: the R channel is NaN everywhere on the border → not
        // inside → the search runs; zoom 8 still NaN → nil (never a false
        // "inside").
        XCTAssertNil(LensAutoCrop.minimumScale(width: width, height: height, edgeMap: map))
    }

    /// The scale=1 search-internal face: `inside(scale:)` with a
    /// distortion-shaped map (barrel pull-in keeps the border inside).
    func testInsideWithBarrelMap() {
        let width = 100, height = 100
        // Barrel (dc2 < 0: Rd < Ru pulls border points toward the
        // center): the border maps inward → inside at scale 1.
        let barrel = LensModule.edgeSample(
            x: 99, y: 50, scale: 1, bufW: width, bufH: height,
            k: LensModule.manualKernelParams(LensModule.Params(distortionK1: -0.15, source: .manual)))
        XCTAssertLessThan(barrel[1].x, 99, "barrel pulls the border inward (G channel)")
    }
}
