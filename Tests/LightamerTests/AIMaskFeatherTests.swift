@testable import LightamerCore
import XCTest

/// AIMaskFeatherTests (Plan M6-4-02 T2, KD-3) — the Edge feather ±100 pins:
/// ① the sigma mapping golden table (hand-computed exact values),
/// ② endpoint clamp, ③ percent-0 (and any non-negative) = the input plane
/// returned unchanged (the CPU face's defensive short-circuit — the wire's
/// percent-0 identity is the bake default, a separate leg), ④ monotonicity,
/// ⑤ the negative-leg logit-gain remap vs a naive Double reference
/// (double-written) + the shrink direction + the 0.5-contour invariance,
/// ⑥ long-edge normalization (portrait vs landscape).
///
/// NOTE (KD-3 DECISIONS cross-ref): the negative leg is the LOGIT GAIN
/// (Lightcraft masks.rs `gain = 1 − 7e`) — the drafted "1 − blur(1−x)"
/// formula is algebraically blur(x) under a linear Gaussian and cannot
/// shrink; the plan's own LightCraft-原文 clause rules here.
final class AIMaskFeatherTests: XCTestCase {

    // MARK: ① sigma mapping golden table (+ the S6' ROI pass-through face)

    /// ±{1, 50, 100} × longEdge {1000, 4000} — hand-computed:
    /// sigma = |percent|/100 × 0.02 × longEdge.
    func testSigmaGoldenTable() {
        let table: [(percent: Float, longEdge: Int, expected: Float)] = [
            (1, 1000, 0.2),
            (50, 1000, 10),
            (100, 1000, 20),
            (-1, 1000, 0.2),
            (-50, 1000, 10),
            (-100, 1000, 20),
            (1, 4000, 0.8),
            (50, 4000, 40),
            (100, 4000, 80),
            (-100, 4000, 80),
        ]
        var compared = 0
        for row in table {
            XCTAssertEqual(
                AIMaskFeather.sigma(percent: row.percent, longEdgePixels: row.longEdge),
                row.expected, accuracy: 1e-3,
                "sigma(\(row.percent), \(row.longEdge))")
            compared += 1
        }
        XCTAssertEqual(compared, table.count, "防空转")

        // S6' STRUCTURAL FACE (not counted as a method): segmentPatch is a
        // thin wrapper over segmentSubject — the ROI value must reach the
        // ONE request assembly (buildLayerBRequest) verbatim through the
        // single Y-flip seam. (Zero-inference, request-object assertion.)
        let patch = AIMaskRect(x: 0.2, y: 0.25, width: 0.4, height: 0.3)
        let request = try! AIMaskService.buildLayerBRequest(
            seed: .point(AIMaskPoint(x: 0.4, y: 0.4)), refine: [],
            quality: .accurate, regionOfInterest: patch, device: .anePreferred)
        let vision = patch.visionRect
        XCTAssertEqual(Double(request.regionOfInterest.origin.x), Double(vision.origin.x), accuracy: 1e-9)
        XCTAssertEqual(Double(request.regionOfInterest.origin.y), Double(vision.origin.y), accuracy: 1e-9)
        XCTAssertEqual(Double(request.regionOfInterest.width), Double(vision.width), accuracy: 1e-9)
        XCTAssertEqual(Double(request.regionOfInterest.height), Double(vision.height), accuracy: 1e-9)
    }

    // MARK: ② endpoint clamp

    func testSigmaClampsBeyondEndpoints() {
        XCTAssertEqual(
            AIMaskFeather.sigma(percent: 150, longEdgePixels: 1000), 20, accuracy: 1e-6,
            "percent > 100 clamps to the +100 radius")
        XCTAssertEqual(
            AIMaskFeather.sigma(percent: -250, longEdgePixels: 4000), 80, accuracy: 1e-6,
            "percent < −100 clamps to the −100 radius")
        XCTAssertEqual(
            AIMaskFeather.sigma(percent: 100, longEdgePixels: 1000),
            AIMaskFeather.sigma(percent: 999, longEdgePixels: 1000), accuracy: 1e-9)
    }

    // MARK: ③ percent 0 = the plane returned unchanged (short-circuit)

    /// The CPU negative face NEVER feathers: percent 0 (and any positive —
    /// the wire routes those to the GPU bake seam) returns the input floats
    /// byte-identical. This is the CPU leg's own defensive contract; the
    /// wire-level percent-0 identity is the bake default-0 leg (its
    /// byte-identity is pinned by the AIMaskGeometryTests bake regression).
    func testNonNegativePercentReturnsPlaneUnchanged() {
        var floats = [Float](repeating: 0, count: 32 * 16)
        for i in floats.indices { floats[i] = Float(i % 19) / 18.0 }
        let plane = AIMaskPlane(width: 32, height: 16, floats: floats)

        for percent: Float in [0, 0.5, 50, 100] {
            let out = AIMaskFeather.applyFeatherNegative(plane: plane, percent: percent)
            XCTAssertEqual(out.width, plane.width)
            XCTAssertEqual(out.height, plane.height)
            XCTAssertEqual(out.floats, plane.floats,
                           "percent \(percent) must short-circuit (byte identity)")
            XCTAssertEqual(out.byteIdentity, plane.byteIdentity)
        }
    }

    // MARK: ④ monotonicity

    func testSigmaMonotonicInAbsolutePercent() {
        let longEdge = 3000
        var previous: Float = -1
        for percent in stride(from: 0.0, through: 100.0, by: 5.0) {
            let s = AIMaskFeather.sigma(percent: Float(percent), longEdgePixels: longEdge)
            XCTAssertGreaterThan(s, previous, "sigma must grow with |percent| (at \(percent))")
            previous = s
        }
        // The negative side mirrors (abs).
        for percent in stride(from: -5.0, through: -100.0, by: -5.0) {
            XCTAssertEqual(
                AIMaskFeather.sigma(percent: Float(percent), longEdgePixels: longEdge),
                AIMaskFeather.sigma(percent: Float(-percent), longEdgePixels: longEdge),
                accuracy: 1e-9, "negative percent mirrors the positive radius")
        }
    }

    // MARK: ⑤ negative shrink vs naive reference + 0.5-contour invariance

    /// A sigmoid row remapped by the logit gain: (a) every pixel matches the
    /// naive Double pow-form reference (independent double-write), (b) the
    /// 10-90% transition width SHRINKS monotonically with |percent|, (c) the
    /// 0.5 contour stays exactly at 0.5 (the border does not move).
    func testNegativeLegShrinksTransitionVsNaiveReference() {
        // A sigmoid ramp across 200 px (the soft edge the base pass leaves).
        let w = 200, h = 4
        var floats = [Float](repeating: 0, count: w * h)
        for x in 0..<w {
            let v = 1.0 / (1.0 + exp(-(Double(x) - 100.0) / 12.0))
            for y in 0..<h { floats[y * w + x] = Float(v) }
        }
        let plane = AIMaskPlane(width: w, height: h, floats: floats)

        func riseWidth(_ p: AIMaskPlane) -> Int {
            let row = p.floats[0..<w].map { $0 }
            let ten = row.firstIndex(where: { $0 >= 0.1 }) ?? w
            let ninety = row.firstIndex(where: { $0 >= 0.9 }) ?? w
            return ninety - ten
        }
        let original = riseWidth(plane)
        var previousWidth = original
        var comparedPixels = 0
        for percent: Float in [-25, -50, -100] {
            let out = AIMaskFeather.applyFeatherNegative(plane: plane, percent: percent)

            // (a) naive Double reference double-write.
            let e = Double(percent) / 100.0
            let g = 1.0 - 7.0 * e
            for i in floats.indices {
                let x = Double(floats[i])
                let expected: Double
                if x <= 0 { expected = 0 } else if x >= 1 { expected = 1 }
                else {
                    let a = pow(x, g), b = pow(1 - x, g)
                    expected = a / (a + b)
                }
                XCTAssertEqual(Double(out.floats[i]), expected, accuracy: 1e-5,
                               "logit-gain remap at \(percent), px \(i)")
                comparedPixels += 1
            }

            // (b) the transition narrows, monotonically in |percent|.
            let width = riseWidth(out)
            XCTAssertLessThan(width, previousWidth,
                              "percent \(percent) must narrow the transition")
            previousWidth = width

            // (c) the 0.5 contour is invariant (the border does not move).
            let midIndex = 100 // sigmoid center
            XCTAssertEqual(out.floats[midIndex], 0.5, accuracy: 1e-6,
                           "the 0.5 contour stays at the same pixel")
        }
        XCTAssertGreaterThan(comparedPixels, 0, "防空转")
        XCTAssertGreaterThan(original, previousWidth, "the shrink direction must hold overall")
    }

    // MARK: ⑥ long-edge normalization

    /// Portrait 1000×4000 and landscape 4000×1000 share the SAME physical
    /// radius at the same percent (the radius keys off the LONG edge —
    /// LightCraft's "so previews and exports match").
    func testSigmaNormalizesByLongEdgeAcrossOrientations() {
        // Portrait vs landscape: the plane dimensions only matter through
        // max(w, h) — the caller passes the long edge; both orientations
        // with the same long edge give the same physical radius.
        let portrait = (w: 1000, h: 4000), landscape = (w: 4000, h: 1000)
        for percent: Float in [1, 25, 50, 100, -50] {
            XCTAssertEqual(
                AIMaskFeather.sigma(percent: percent, longEdgePixels: max(portrait.w, portrait.h)),
                AIMaskFeather.sigma(percent: percent, longEdgePixels: max(landscape.w, landscape.h)),
                accuracy: 1e-9,
                "the same long edge = the same physical radius across orientations (percent \(percent))")
        }
        // The short edge alone must NOT set the radius: a 1000-short-edge
        // portrait has a different radius from a 1000-long-edge landscape.
        XCTAssertNotEqual(
            AIMaskFeather.sigma(percent: 50, longEdgePixels: 4000),
            AIMaskFeather.sigma(percent: 50, longEdgePixels: 1000),
            "the radius keys off the LONG edge")
    }
}
