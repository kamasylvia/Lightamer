@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanoWarpTests (Plan M5-3-02 T1; KD-11 G3①/G3⑤) — the projection segment's
// gates:
//
// G3① sphericalMap vs the TEST-LOCAL closed-form solution, point by point
// (the anti-golden-loop rule: the reference recomputes the merge.py:205-211
// formulas independently — deliberately NOT calling PanoWarp), plus the
// forward/backward exact-inverse identity and the z ≤ 1e-6 invalid marker.
//
// G3⑤ boundedCanvas invariants: output ≤ 200 MP, rounds ≤ 8 (observed
// through the accepted scale), post-shrink ROIs non-empty, and the typed
// canvas-invalid failures (projection invalid / budget exhausted).
//
// L048: comparisons ride the f32 production constant
// `Double(Float(x))`; the point-wise tolerance band is measured on the
// first run and pinned in M5-3-02-DECISIONS (no band tuning afterwards).
// ─────────────────────────────────────────────────────────────────────────────

final class PanoWarpTests: XCTestCase {

    // MARK: - Fixtures

    private func rotationAroundY(_ yaw: Double) -> Mat3D {
        PanoCamera.rotation(fromAxisAngle: SIMD3(0, yaw, 0))
    }

    private func geometry(
        width: Int, height: Int, focal: Double, rotation: Mat3D
    ) -> PanoSourceGeometry {
        PanoSourceGeometry(
            width: width, height: height, focal: focal, rotation: rotation)
    }

    // MARK: - G3①: sphericalMap vs the test-local closed form

    /// The INDEPENDENT recomputation of merge.py:205-211 (the anti-loop
    /// reference — no PanoWarp call): Double math, Float32 output.
    private func referenceMap(
        rectX: Double, rectY: Double, width: Int, height: Int,
        scale: Double, source: PanoSourceGeometry
    ) -> (mx: [Double], my: [Double], valid: [Bool]) {
        var mx = [Double](repeating: -1, count: width * height)
        var my = [Double](repeating: -1, count: width * height)
        var valid = [Bool](repeating: false, count: width * height)
        let r = source.rotation
        let centerX = Double(source.width - 1) / 2
        let centerY = Double(source.height - 1) / 2
        for y in 0..<height {
            let v = (rectY + Double(y)) / scale
            let (sinV, cosV) = (sin(v), cos(v))
            for x in 0..<width {
                let u = (rectX + Double(x)) / scale
                let ray = (
                    sinV * sin(u), -cosV, sinV * cos(u)
                )
                let cam = (
                    r[0, 0] * ray.0 + r[0, 1] * ray.1 + r[0, 2] * ray.2,
                    r[1, 0] * ray.0 + r[1, 1] * ray.1 + r[1, 2] * ray.2,
                    r[2, 0] * ray.0 + r[2, 1] * ray.1 + r[2, 2] * ray.2)
                guard cam.2 > 1e-6 else { continue }
                valid[y * width + x] = true
                mx[y * width + x] = source.focal * (cam.0 / cam.2) + centerX
                my[y * width + x] = source.focal * (cam.1 / cam.2) + centerY
            }
        }
        return (mx, my, valid)
    }

    func testSphericalMapMatchesClosedFormPointWise() {
        // A rotated camera + a non-trivial rect (the union-offset shape the
        // tile loop produces): every valid point must agree with the
        // independent closed form inside the Float32 output's noise floor.
        let source = geometry(
            width: 640, height: 480, focal: 500,
            rotation: rotationAroundY(12 * Double.pi / 180))
        let rect = (x: -137.0, y: 45.0, w: 128, h: 96)
        let scale = 500.0
        let (mx, my) = PanoWarp.sphericalMap(
            rectX: rect.x, rectY: rect.y, width: rect.w, height: rect.h,
            scale: scale, source: source)
        let reference = referenceMap(
            rectX: rect.x, rectY: rect.y, width: rect.w, height: rect.h,
            scale: scale, source: source)
        var checked = 0
        var worst = 0.0
        for index in 0..<(rect.w * rect.h) {
            XCTAssertEqual(mx[index] >= 0, reference.valid[index])
            guard reference.valid[index] else { continue }
            checked += 1
            // The production constant (L048): the f32 output compares in
            // Double against the Double reference — the f32 quantization
            // at ~500px scale floors around 3e-5 relative.
            let errorX = abs(Double(mx[index]) - reference.mx[index])
            let errorY = abs(Double(my[index]) - reference.my[index])
            worst = max(worst, errorX, errorY)
            XCTAssertLessThanOrEqual(
                errorX, 1e-3, "point \(index): mx diverged")
            XCTAssertLessThanOrEqual(
                errorY, 1e-3, "point \(index): my diverged")
        }
        XCTAssertGreaterThan(checked, rect.w * rect.h / 2, "too few valid")
        print("G3① worst |Δ| = \(worst) over \(checked) points")
    }

    func testSphericalMapInvalidMarkerBehindCamera() {
        // A camera rotated 180°: every ray lands behind (z ≤ 1e-6) → the
        // whole map is −1 (the Lumen invalid marker).
        let source = geometry(
            width: 100, height: 80, focal: 300,
            rotation: rotationAroundY(Double.pi))
        let (mx, my) = PanoWarp.sphericalMap(
            rectX: 0, rectY: 0, width: 20, height: 16,
            scale: 300, source: source)
        for index in mx.indices {
            XCTAssertEqual(mx[index], -1)
            XCTAssertEqual(my[index], -1)
        }
    }

    func testForwardBackwardAreExactInverses() {
        // projectToCanvas ∘ sphericalMap == identity on the z > 0 branch:
        // for sampled source pixels, the canvas point that maps back must
        // land within one canvas pixel of the original.
        let source = geometry(
            width: 800, height: 600, focal: 500,
            rotation: rotationAroundY(-17 * Double.pi / 180))
        let scale = 500.0
        for pixel in stride(from: 0, to: 800 * 600, by: 9973) {
            let px = Double(pixel % 800)
            let py = Double(pixel / 800)
            let uv = PanoWarp.projectToCanvas(
                x: px, y: py, scale: scale, source: source)
            let (mx, my) = PanoWarp.sphericalMap(
                rectX: uv.u, rectY: uv.v, width: 1, height: 1,
                scale: scale, source: source)
            guard mx[0] >= 0 else {
                // Behind-camera forward points have no inverse — skip.
                continue
            }
            let error = hypot(
                Double(mx[0]) - px, Double(my[0]) - py)
            XCTAssertLessThanOrEqual(
                error, 1e-2,
                "pixel (\(px), \(py)) → canvas (\(uv.u), \(uv.v)) "
                    + "→ back (\(mx[0]), \(my[0])), error \(error)px")
        }
    }

    // MARK: - The scale anchor (KD-3)

    func testGlobalScaleIsMedianOfFocals() {
        XCTAssertEqual(
            PanoWarp.globalScale(focals: [500, 480, 520, 490, 30000]), 500)
        // Even count → the mean of the two middles (numpy convention).
        XCTAssertEqual(PanoWarp.globalScale(focals: [400, 500, 510, 900]), 505)
        XCTAssertEqual(PanoWarp.globalScale(focals: [321]), 321)
        XCTAssertEqual(PanoWarp.globalScale(focals: []), 0)
    }

    func testFullResolutionFocalBackProjection() {
        // f_full = f_preview · fullW / previewW (the inv(preview_scale)@K
        // reduction); the no-downsample case rescales by 1.
        XCTAssertEqual(
            PanoWarp.fullResolutionFocal(
                previewFocal: 500, previewWidth: 600, fullWidth: 1200),
            1000, accuracy: 1e-12)
        XCTAssertEqual(
            PanoWarp.fullResolutionFocal(
                previewFocal: 500, previewWidth: 700, fullWidth: 700),
            500, accuracy: 1e-12)
    }

    // MARK: - G3⑤: boundedCanvas invariants

    /// A synthetic wide-rig: 5 cameras sweeping 70° of yaw at a focal that
    /// projects past the cap (the first round exceeds 200 MP, the shrink
    /// loop converges inside the budget).
    private func wideRig(focal: Double) -> [PanoSourceGeometry] {
        let yaws = (-2...2).map { Double($0) * 17.5 * Double.pi / 180 }
        return yaws.map {
            geometry(
                width: 6000, height: 4000, focal: focal,
                rotation: rotationAroundY($0))
        }
    }

    func testBoundedCanvasInvariants() throws {
        // First-round area deliberately overshoots: 5 × 17.5° at f = 60000
        // spans ≈ 1.66 rad ≈ 100k px wide × ~6000 px high ≫ 200 MP — the
        // loop must shrink and land under the cap with non-empty ROIs.
        let sources = wideRig(focal: 60000)
        let plan = try PanoWarp.boundedCanvas(
            sources: sources, scale: PanoWarp.globalScale(focals: sources.map(\.focal)))
        XCTAssertLessThanOrEqual(
            plan.width * plan.height, PanoWarp.maxCanvasPixels)
        XCTAssertGreaterThan(plan.width, 0)
        XCTAssertGreaterThan(plan.height, 0)
        XCTAssertEqual(plan.rois.count, sources.count)
        for (index, roi) in plan.rois.enumerated() {
            XCTAssertGreaterThan(roi.width, 0, "roi \(index) empty")
            XCTAssertGreaterThan(roi.height, 0, "roi \(index) empty")
        }
        // The accepted scale differs from the initial one → the loop
        // actually shrunk (≤ 8 rounds is the loop's own bound; the scale
        // ratio witnesses ≥ 1 contraction round).
        XCTAssertLessThan(plan.scale, 60000)
        // ROIs' union == the plan bounds (the origin anchors (0, 0)).
        XCTAssertEqual(plan.rois.map(\.x).min() ?? -1, plan.originX)
        XCTAssertEqual(plan.rois.map(\.y).min() ?? -1, plan.originY)
        XCTAssertEqual(
            (plan.rois.map { $0.x + $0.width }.max() ?? 0) - plan.originX,
            plan.width)
        XCTAssertEqual(
            (plan.rois.map { $0.y + $0.height }.max() ?? 0) - plan.originY,
            plan.height)
    }

    func testBoundedCanvasUnderCapAcceptsImmediately() throws {
        // A small rig: no shrink needed — the accepted scale == input.
        let sources = wideRig(focal: 400)
        let plan = try PanoWarp.boundedCanvas(
            sources: sources, scale: 400)
        XCTAssertEqual(plan.scale, 400)
        XCTAssertLessThanOrEqual(
            plan.width * plan.height, PanoWarp.maxCanvasPixels)
    }

    func testBoundedCanvasTypedFailureOnDegenerateFocal() {
        // focal = 0: the ROI border walk projects to non-finite coordinates
        // → the typed projection-invalid failure (merge.py:199 semantics;
        // the 8-round budget exhaustion arm is Lumen parity but needs a
        // nonlinearity oscillation the product gate converges past in one
        // round — the DECISIONS note).
        let source = geometry(
            width: 400, height: 300, focal: 0, rotation: rotationAroundY(0.1))
        XCTAssertThrowsError(try PanoWarp.boundedCanvas(
            sources: [source], scale: 1)) { error in
            guard case AppError.invalidParameter(let message) = error else {
                XCTFail("expected invalidParameter, got \(error)")
                return
            }
            XCTAssertTrue(
                message.hasPrefix(PanoMatch.FailurePrefix.canvas),
                "canvas-invalid prefix required: \(message)")
            XCTAssertTrue(
                message.contains("projection invalid"),
                "the projection-invalid arm: \(message)")
        }
    }
}
