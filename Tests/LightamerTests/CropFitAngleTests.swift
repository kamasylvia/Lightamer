@testable import LightamerCore
import XCTest

/// CropFitAngleTests (Plan M9-3-T1) — the straighten-angle crop geometry
/// closed form + the #742/#1388/#1794 three-generation frame semantics
/// (upstream `crates/geom/src/crop.rs` test faces, same parameters).
///
/// HAND VALUES:
/// - the 3:2 @10° analytic example: max_inscribed_scale(600, 400, 10°,
///   600, 400) = min(300/(300·cos10° + 200·sin10°), 200/(300·sin10° +
///   200·cos10°)) = min(0.908639, 0.803031) = **0.803031** — the closed
///   form is checked against that decimal, not against itself; maximal is
///   proven by the 1%-bigger-does-not-fit predicate.
/// - #1794's corner-dragged crop Rect(0, 0, 0.6, 0.6): every turn keeps it
///   inside, never larger, aspect-kept, shrunk about its own centre, and
///   as large as fits there (a 1% grow about the same centre does not fit).
/// - #1388's grow-back: a fitted crop turned through [10, 25, −25, 7, 0]
///   must equal the largest fit at each angle (never the shrunk remnant).
final class CropFitAngleTests: XCTestCase {

    private static let w = 600.0
    private static let h = 400.0

    /// Field-wise assertion within tolerance (Rect's Equatable is exact;
    /// the hand-value gates here carry tolerances).
    private func assertRect(
        _ a: CropFitAngle.Rect, _ b: CropFitAngle.Rect, accuracy: Double,
        _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(a.x0, b.x0, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y0, b.y0, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.x1, b.x1, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y1, b.y1, accuracy: accuracy, message, file: file, line: line)
    }

    private func grown(_ r: CropFitAngle.Rect, by factor: Double) -> CropFitAngle.Rect {
        let wHalf = r.width * factor / 2
        let hHalf = r.height * factor / 2
        return CropFitAngle.Rect(
            x0: r.center.x - wHalf, y0: r.center.y - hHalf,
            x1: r.center.x + wHalf, y1: r.center.y + hHalf)
    }

    // MARK: - analytic example (closed form) + maximality

    func testFitRectAnalyticExampleAndMaximality() {
        let w = Self.w, h = Self.h
        // 3:2 @10° on the frame's own aspect (nil → w/h = 1.5): the largest
        // base rect IS the full frame, so s = maxInscribedScale directly.
        // Hand value: min(300/(300·cos10° + 200·sin10°), 200/(300·sin10° +
        // 200·cos10°)) = 200/249.056004 = 0.8030322372 (10 significant
        // digits; the 1e-8 gate matches their precision).
        let s = CropFitAngle.maxInscribedScale(w: w, h: h, angleDegrees: 10, cropW: w, cropH: h)
        XCTAssertEqual(s, 0.8030322372, accuracy: 1e-8, "closed-form scale hand value")
        let rect = CropFitAngle.fitRect(w: w, h: h, angleDegrees: 10, aspect: nil)
        // normalized edges: the pixel rect (600s × 400s) divided by (600, 400)
        XCTAssertEqual(rect.width, s, accuracy: 1e-9, "normalized width carries the closed-form scale")
        XCTAssertEqual(rect.height, s, accuracy: 1e-9, "normalized height carries the closed-form scale")
        // inside, and maximal: 1% bigger does not fit
        XCTAssertTrue(CropFitAngle.isWithinImage(rect, angleDegrees: 10, w: w, h: h))
        XCTAssertFalse(
            CropFitAngle.isWithinImage(grown(rect, by: 1.01), angleDegrees: 10, w: w, h: h),
            "the fit must be maximal: 1% bigger does not fit")
        // angle 0 fits exactly the full frame
        assertRect(
            CropFitAngle.fitRect(w: w, h: h, angleDegrees: 0, aspect: nil), .unit,
            accuracy: 1e-12, "angle 0 fits the full frame")
    }

    // MARK: - with_angle three-branch semantics (#742/#1388/#1794)

    func testWithAngleThreeGenerationSemantics() {
        let w = Self.w, h = Self.h

        // (a) still fits → the rect does not move (#742's convergence: every
        // entrance funnels to one answer)
        let small = CropFitAngle.Rect(x0: 0.3, y0: 0.3, x1: 0.7, y1: 0.7)
        for ang in [-3.0, 0.5, 2.0, 5.0] {
            let t = CropFitAngle.withAngle(small, angleDegrees: 0, newAngleDegrees: ang, w: w, h: h)
            assertRect(t, small, accuracy: 1e-12, "\(ang)°: a crop that still fits is untouched")
            XCTAssertFalse(
                CropFitAngle.shouldAutoRefit(small, oldAngleDegrees: 0, newAngleDegrees: ang, w: w, h: h),
                "\(ang)°: the predicate must report no refit needed")
        }

        // (b) no longer fits → shrunk about its own centre, aspect kept
        // (upstream's shrink trio, same parameters)
        for (rect, ang) in [
            (CropFitAngle.Rect.unit, 15.0),
            (CropFitAngle.Rect(x0: 0.0, y0: 0.1, x1: 0.8, y1: 0.9), -20.0),
            (CropFitAngle.Rect(x0: 0.2, y0: 0.0, x1: 0.8, y1: 1.0), 45.0),
        ] {
            let t = CropFitAngle.withAngle(rect, angleDegrees: 0, newAngleDegrees: ang, w: w, h: h)
            XCTAssertTrue(CropFitAngle.isWithinImage(t, angleDegrees: ang, w: w, h: h), "\(rect) at \(ang)°")
            XCTAssertEqual(t.aspect ?? 0, rect.aspect ?? 0, accuracy: 1e-9, "aspect kept")
            // aspect kept AND shrunk: a hand-tuned frame never grows
            XCTAssertLessThanOrEqual(t.pixelWidth(in: w), rect.pixelWidth(in: w) + 1e-9)
        }

        // (c) #1794's corner-dragged crop: never grows, stays about its own
        // centre, and is as large as fits there
        let dragged = CropFitAngle.Rect(x0: 0.0, y0: 0.0, x1: 0.6, y1: 0.6)
        let draggedW = dragged.pixelWidth(in: w)
        let draggedCenter = dragged.center
        for ang in [-10.0, -1.0, 0.5, 3.0, 20.0] {
            let t = CropFitAngle.withAngle(dragged, angleDegrees: 0, newAngleDegrees: ang, w: w, h: h)
            XCTAssertTrue(CropFitAngle.isWithinImage(t, angleDegrees: ang, w: w, h: h), "\(ang)°")
            XCTAssertLessThanOrEqual(t.pixelWidth(in: w), draggedW + 1e-9, "\(ang)°: never larger")
            XCTAssertEqual(t.aspect ?? 0, dragged.aspect ?? 0, accuracy: 1e-9, "\(ang)°: aspect kept")
            XCTAssertEqual(t.center.x, draggedCenter.x, accuracy: 1e-9, "\(ang)°: shrunk about its own centre")
            XCTAssertEqual(t.center.y, draggedCenter.y, accuracy: 1e-9, "\(ang)°: shrunk about its own centre")
            XCTAssertFalse(
                CropFitAngle.isWithinImage(grown(t, by: 1.01), angleDegrees: ang, w: w, h: h),
                "\(ang)°: the largest about its centre (1% bigger does not fit)")
        }
        // a small turn is a small change, not a jump
        let gentle = CropFitAngle.withAngle(dragged, angleDegrees: 0, newAngleDegrees: 0.5, w: w, h: h)
        XCTAssertGreaterThan(gentle.pixelWidth(in: w), 0.97 * draggedW, "0.5° keeps nearly all of the crop")

        // (d) #1388: a fitted crop grows back as the angle returns — each
        // step equals the largest fit at the current angle (width AND height)
        for aspect in [Double?.none, 1.0, 16.0 / 9.0] {
            var oldAngle = 0.0
            var current = CropFitAngle.fitRect(w: w, h: h, angleDegrees: 0, aspect: aspect)
            for ang in [10.0, 25.0, -25.0, 7.0, 0.0] {
                current = CropFitAngle.withAngle(current, angleDegrees: oldAngle, newAngleDegrees: ang, w: w, h: h)
                oldAngle = ang
                let want = CropFitAngle.fitRect(w: w, h: h, angleDegrees: ang, aspect: aspect)
                XCTAssertEqual(current.width, want.width, accuracy: 1e-9, "\(String(describing: aspect)) at \(ang)°")
                XCTAssertEqual(current.height, want.height, accuracy: 1e-9, "\(String(describing: aspect)) at \(ang)°")
            }
        }

        // (e) the full-frame crop turning IS the largest branch → the
        // predicate refits, and angle back to 0 restores the full frame
        XCTAssertTrue(CropFitAngle.shouldAutoRefit(.unit, oldAngleDegrees: 0, newAngleDegrees: 10, w: w, h: h))
        let back = CropFitAngle.withAngle(
            CropFitAngle.fitRect(w: w, h: h, angleDegrees: 10, aspect: nil),
            angleDegrees: 10, newAngleDegrees: 0, w: w, h: h)
        assertRect(back, .unit, accuracy: 1e-12, "angle back to 0 restores the full frame")
    }
}
