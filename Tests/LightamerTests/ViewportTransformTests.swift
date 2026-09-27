@testable import Lightamer
@testable import LightamerCore
import CoreGraphics
import XCTest

// ViewportTransformTests (Plan 13-3 T1/T3, L021 观察层量化口径) — the
// zoom/pan/rotation math pins:
//
//   fit 恒等回归锁   — identity transform == the 04-02 fit layout exactly
//                      (zero drift; the blit/overlay/eyedropper consumers
//                      stay byte-identical at fit).
//   正逆映射往返     — uv→point→uv and point→uv→point round-trips at
//                      zoomed/panned/rotated states to ~1e-9.
//   100% 数学锚      — hundredPercentZoom = textureWidth / rectWidth; at
//                      that zoom the image displays 1px = 1pt.
//   光标锚定         — the anchor's image uv is invariant across a zoom or
//                      rotation step (cursor-anchored zoom/rotate).
//   互斥矩阵 (T3)    — locked state swallows every gesture input AND
//                      entering the lock snaps to the fit identity.
//
// All math delegates to ViewportFit (the single source — the second
// fit/zoom math is banned).
@MainActor
final class ViewportTransformTests: XCTestCase {

    /// 3:2 landscape texture in a 4:3 viewport — letterboxed top/bottom.
    private let viewport = CGSize(width: 800, height: 600)
    private let texture = CGSize(width: 1200, height: 800)

    // MARK: - fit 恒等回归锁 (T1)

    func testIdentityTransformMatchesBareFitExactly() {
        let identity = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: 1, pan: .zero, rotationDegrees: 0)
        XCTAssertTrue(identity.isIdentity)
        let rect = ViewportFit.fittedRect(viewportSize: viewport, textureSize: texture)
        XCTAssertEqual(identity.rect, rect)
        // Every consumer path must agree with the bare fit math to the
        // last bit (the 04-02 zero-drift lock).
        for uv in [SIMD2(0.0, 0.0), SIMD2(0.5, 0.5), SIMD2(1.0, 1.0), SIMD2(0.25, 0.75)] {
            XCTAssertEqual(
                identity.point(atUV: uv),
                ViewportFit.point(at: uv, viewportSize: viewport, textureSize: texture)!)
            XCTAssertEqual(
                identity.uv(at: ViewportFit.point(at: uv, viewportSize: viewport, textureSize: texture)!),
                ViewportFit.uv(
                    at: ViewportFit.point(at: uv, viewportSize: viewport, textureSize: texture)!,
                    viewportSize: viewport, textureSize: texture))
        }
        // The nil-transform ViewportFit delegates must equal the identity
        // transform results (no second code path).
        let probe = CGPoint(x: 400, y: 200)
        XCTAssertEqual(
            ViewportFit.uv(at: probe, viewportSize: viewport, textureSize: texture),
            ViewportFit.uv(
                at: probe, viewportSize: viewport, textureSize: texture,
                transform: identity))
        XCTAssertEqual(
            ViewportFit.point(at: SIMD2(0.3, 0.6), viewportSize: viewport, textureSize: texture),
            ViewportFit.point(
                at: SIMD2(0.3, 0.6), viewportSize: viewport, textureSize: texture,
                transform: identity))
    }

    // MARK: - 正逆映射往返精度 (T1, L021 pattern 扩展)

    func testForwardInverseRoundTripPrecision() {
        let zooms: [Double] = [1.0, 2.5, 8.0]
        let rotations: [Double] = [0, 17, -90, 240]
        let pans: [CGPoint] = [.zero, CGPoint(x: 40, y: -25)]
        for zoom in zooms {
            for rotation in rotations {
                for pan in pans {
                    let xf = ViewportFit.transform(
                        viewportSize: viewport, textureSize: texture,
                        zoom: zoom, pan: pan, rotationDegrees: rotation)
                    // uv → point → uv: back to the same image point.
                    for uv in [SIMD2(0.1, 0.2), SIMD2(0.5, 0.5), SIMD2(0.9, 0.8)] {
                        let point = xf.point(atUV: uv)
                        let back = xf.uv(at: point)
                        XCTAssertNotNil(back, "zoom \(zoom) rot \(rotation) pan \(pan)")
                        if let back {
                            XCTAssertLessThan(abs(back.x - uv.x), 1e-9)
                            XCTAssertLessThan(abs(back.y - uv.y), 1e-9)
                        }
                    }
                }
            }
        }
    }

    func testInverseOutsideImageReturnsNil() {
        let xf = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: 4, pan: CGPoint(x: -2000, y: -2000), rotationDegrees: 30)
        // The image is panned far off-screen — the viewport center lands
        // nowhere on the image content.
        XCTAssertNil(xf.uv(at: CGPoint(x: 400, y: 300)))
        // Fit-state letterbox (below the fitted band) is nil too.
        let identity = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: 1, pan: .zero, rotationDegrees: 0)
        XCTAssertNil(identity.uv(at: CGPoint(x: 400, y: 5)))
    }

    // MARK: - 100% 数学锚 (T1)

    func testHundredPercentZoomAnchorsAtOnePixelPerPoint() {
        guard let hundred = ViewportFit.hundredPercentZoom(
            viewportSize: viewport, textureSize: texture)
        else {
            return XCTFail("hundredPercentZoom nil on live geometry")
        }
        let rect = ViewportFit.fittedRect(viewportSize: viewport, textureSize: texture)
        XCTAssertEqual(hundred, Double(texture.width) / Double(rect.width), accuracy: 1e-12)
        // At the 100% zoom the transformed image rect IS the pixel size.
        let xf = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: hundred, pan: .zero, rotationDegrees: 0)
        let topLeft = xf.point(atUV: SIMD2(0, 0))
        let bottomRight = xf.point(atUV: SIMD2(1, 1))
        XCTAssertEqual(bottomRight.x - topLeft.x, CGFloat(texture.width), accuracy: 1e-6)
        XCTAssertEqual(bottomRight.y - topLeft.y, CGFloat(texture.height), accuracy: 1e-6)
    }

    // MARK: - 光标锚定 (T1: zoom 前后光标下 uv 点不动)

    func testCursorAnchoredZoomKeepsAnchorUV() {
        let rect = ViewportFit.fittedRect(viewportSize: viewport, textureSize: texture)
        let anchor = CGPoint(x: 640, y: 220) // an off-center cursor point
        let before = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: 1, pan: .zero, rotationDegrees: 0)
        guard let anchorUV = before.uv(at: anchor) else {
            return XCTFail("anchor outside the image")
        }
        let pan = ViewportFit.panKeeping(
            uv: anchorUV, anchor: anchor, rect: rect, zoom: 3.5, rotationDegrees: 0)
        let after = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: 3.5, pan: pan, rotationDegrees: 0)
        let keptUV = after.uv(at: anchor)
        XCTAssertNotNil(keptUV)
        XCTAssertEqual(keptUV!.x, anchorUV.x, accuracy: 1e-9)
        XCTAssertEqual(keptUV!.y, anchorUV.y, accuracy: 1e-9)
    }

    func testCursorAnchoredRotationKeepsAnchorUV() {
        let rect = ViewportFit.fittedRect(viewportSize: viewport, textureSize: texture)
        let anchor = CGPoint(x: 500, y: 300)
        let before = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: 2, pan: .zero, rotationDegrees: 0)
        guard let anchorUV = before.uv(at: anchor) else {
            return XCTFail("anchor outside the image")
        }
        let pan = ViewportFit.panKeeping(
            uv: anchorUV, anchor: anchor, rect: rect, zoom: 2, rotationDegrees: 30)
        let after = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: 2, pan: pan, rotationDegrees: 30)
        let keptUV = after.uv(at: anchor)
        XCTAssertNotNil(keptUV)
        XCTAssertEqual(keptUV!.x, anchorUV.x, accuracy: 1e-9)
        XCTAssertEqual(keptUV!.y, anchorUV.y, accuracy: 1e-9)
    }

    // MARK: - blit quad 消费 (T1: 同一 transform 产物)

    func testFitQuadConsumesTransformForZoomAndRotation() {
        // Zoomed: the corners leave the NDC ±1 box (the image overflows).
        let zoomed = EditorMTKView.Coordinator.fitQuad(
            textureSize: SIMD2(1200, 800), drawableSize: CGSize(width: 800, height: 600),
            zoom: 3)
        XCTAssertLessThan(zoomed.p0.x, -1)
        XCTAssertGreaterThan(zoomed.p3.x, 1)
        // Rotated 90°: the (scaled) top-left corner lands bottom-left —
        // the corner ORDER rotates with the transform.
        let rotated = EditorMTKView.Coordinator.fitQuad(
            textureSize: SIMD2(1200, 800), drawableSize: CGSize(width: 800, height: 600),
            zoom: 2, pan: .zero, rotationDegrees: 90)
        // TL (uv 0,0) → bottom-left region (x < 0, y > 0 in NDC).
        XCTAssertLessThan(rotated.p0.x, 0)
        XCTAssertGreaterThan(rotated.p0.y, 0)
        // TR (uv 1,0) → top-left region.
        XCTAssertLessThan(rotated.p1.y, 0)
        // Identity quad unchanged (the fit regression, mirror of the
        // CropOverlayTests pin through the new signature).
        let identity = EditorMTKView.Coordinator.fitQuad(
            textureSize: SIMD2(300, 200), drawableSize: CGSize(width: 200, height: 200))
        let rect = ViewportFit.fittedRect(
            viewportSize: CGSize(width: 200, height: 200),
            textureSize: CGSize(width: 300, height: 200))
        XCTAssertEqual(identity.p0.x, Float(2 * rect.minX / 200 - 1), accuracy: 1e-6)
        XCTAssertEqual(identity.p0.y, Float(1 - 2 * rect.maxY / 200), accuracy: 1e-6)
    }

    // MARK: - ViewportState 状态机 (T1/T2 手势推进面)

    func testMagnifyAdvancesStateAndAnchors() {
        let state = ViewportState()
        XCTAssertEqual(state.mode, .fit)
        state.magnify(
            delta: 1.0, anchoredAt: CGPoint(x: 400, y: 300),
            viewportSize: viewport, textureSize: texture)
        XCTAssertEqual(state.zoom, 2.0, accuracy: 1e-12)
        XCTAssertEqual(state.mode, .free)
        // Clamped at the ceiling.
        state.magnify(
            delta: 100, anchoredAt: nil, viewportSize: viewport, textureSize: texture)
        XCTAssertEqual(state.zoom, ViewportState.maxZoom, accuracy: 1e-9)
        state.fit()
        XCTAssertEqual(state.zoom, 1)
        XCTAssertEqual(state.mode, .fit)
        XCTAssertEqual(state.pan, .zero)
    }

    func testActualSizeSetsHundredPercent() {
        let state = ViewportState()
        state.actualSize(viewportSize: viewport, textureSize: texture)
        let hundred = ViewportFit.hundredPercentZoom(
            viewportSize: viewport, textureSize: texture)!
        XCTAssertEqual(state.zoom, hundred, accuracy: 1e-9)
        XCTAssertEqual(state.mode, .hundredPercent)
        // The remembered-geometry seam (App-scene menu): fit() then
        // actualSize() with no live view still lands 100%.
        state.fit()
        state.actualSize()
        XCTAssertEqual(state.zoom, hundred, accuracy: 1e-9)
    }

    func testSmallImageActualSizeDipsBelowFit() {
        // A 100×100 texture in the 800×600 viewport upscales at fit —
        // the 100% state must zoom OUT below 1 (the floor exception).
        let small = CGSize(width: 100, height: 100)
        let state = ViewportState()
        state.actualSize(viewportSize: viewport, textureSize: small)
        XCTAssertEqual(state.zoom, 100.0 / ViewportFit.fittedRect(
            viewportSize: viewport, textureSize: small).width, accuracy: 1e-9)
        XCTAssertLessThan(state.zoom, 1)
    }

    func testScrollPanSubtractsDeltasAndIgnoresPristineFit() {
        let state = ViewportState()
        // Pristine fit: nothing to pan into — the input is ignored.
        state.scrollPan(deltaX: 10, deltaY: -5)
        XCTAssertEqual(state.pan, .zero)
        state.magnify(
            delta: 0.5, anchoredAt: nil, viewportSize: viewport, textureSize: texture)
        state.scrollPan(deltaX: 10, deltaY: -5)
        // Content follows the fingers: pan = −delta.
        XCTAssertEqual(state.pan.x, -10, accuracy: 1e-12)
        XCTAssertEqual(state.pan.y, 5, accuracy: 1e-12)
    }

    func testRotateAdvancesAndWraps() {
        let state = ViewportState()
        state.rotate(
            deltaDegrees: 400, anchoredAt: nil,
            viewportSize: viewport, textureSize: texture)
        XCTAssertEqual(state.rotationDegrees, 40, accuracy: 1e-9)
        XCTAssertEqual(state.mode, .free)
    }

    // MARK: - 互斥矩阵 (T3: crop/liquify/retouch 激活锁 fit)

    func testRouteLockMatrix() {
        // The viewport-exclusive overlays lock; mask editing and the
        // segment taps stay free (they inverse-map through the transform).
        XCTAssertTrue(EditorAreaView.routeLocksZoom(.crop))
        XCTAssertTrue(EditorAreaView.routeLocksZoom(.liquify))
        XCTAssertTrue(EditorAreaView.routeLocksZoom(.retouch))
        XCTAssertFalse(EditorAreaView.routeLocksZoom(.maskEditing))
        XCTAssertFalse(EditorAreaView.routeLocksZoom(.segment))
    }

    func testMutexLockForcesFitAndSwallowsGestures() {
        let state = ViewportState()
        state.magnify(
            delta: 2, anchoredAt: CGPoint(x: 400, y: 300),
            viewportSize: viewport, textureSize: texture)
        state.rotate(
            deltaDegrees: 25, anchoredAt: nil,
            viewportSize: viewport, textureSize: texture)
        XCTAssertEqual(state.mode, .free)

        // Entering the lock (a viewport-exclusive overlay activated)
        // snaps back to the pristine fit identity.
        state.setZoomLocked(true)
        XCTAssertTrue(state.zoomLocked)
        XCTAssertEqual(state.mode, .fit)
        XCTAssertEqual(state.zoom, 1)
        XCTAssertEqual(state.pan, .zero)
        XCTAssertEqual(state.rotationDegrees, 0)

        // Every gesture input is swallowed while locked.
        state.magnify(
            delta: 3, anchoredAt: CGPoint(x: 400, y: 300),
            viewportSize: viewport, textureSize: texture)
        state.scrollPan(deltaX: 30, deltaY: 30)
        state.rotate(
            deltaDegrees: 45, anchoredAt: nil,
            viewportSize: viewport, textureSize: texture)
        state.scrollZoom(
            ticks: 10, anchoredAt: CGPoint(x: 400, y: 300),
            viewportSize: viewport, textureSize: texture)
        state.smartMagnify(viewportSize: viewport, textureSize: texture)
        state.stepZoom(factor: 2, viewportSize: viewport, textureSize: texture)
        state.actualSize(viewportSize: viewport, textureSize: texture)
        XCTAssertEqual(state.zoom, 1)
        XCTAssertEqual(state.pan, .zero)
        XCTAssertEqual(state.rotationDegrees, 0)
        XCTAssertEqual(state.mode, .fit)

        // Unlock stays at fit (the user re-zooms from there); gestures
        // work again.
        state.setZoomLocked(false)
        XCTAssertFalse(state.zoomLocked)
        XCTAssertEqual(state.mode, .fit)
        state.magnify(
            delta: 1, anchoredAt: nil, viewportSize: viewport, textureSize: texture)
        XCTAssertEqual(state.zoom, 2, accuracy: 1e-12)
    }

    // MARK: - T3: mask 命中精度门（zoom 后 stamp 光标点 vs 落点 <1px）

    func testZoomedMaskStampHitBelowOnePixel() {
        // The zoomed+rotated state the mutex leaves to the mask tools:
        // the cursor point inverse-maps to a uv whose forward map lands
        // back within a pixel (the <1px stamp gate).
        let xf = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: 6, pan: CGPoint(x: -150, y: 80), rotationDegrees: -35)
        let cursor = CGPoint(x: 512, y: 261)
        guard let uv = xf.uv(at: cursor) else {
            return XCTFail("cursor outside the zoomed image")
        }
        let landed = xf.point(atUV: uv)
        let dx = landed.x - cursor.x, dy = landed.y - cursor.y
        XCTAssertLessThan((dx * dx + dy * dy).squareRoot(), 1.0)
    }

    // MARK: - T3: eyedropper uv 经 transform 取样正确

    func testEyedropperUVThroughTransform() {
        // The coordinator seam: the static viewportUV with a transform
        // inverse-maps; the identity path stays byte-equal (the
        // EyedropperTests pins carry over untouched).
        let xf = ViewportFit.transform(
            viewportSize: viewport, textureSize: texture,
            zoom: 2, pan: .zero, rotationDegrees: 0)
        let anchor = CGPoint(x: 640, y: 220)
        let viaStatic = PipeCoordinator.viewportUV(
            at: anchor, viewportSize: viewport, textureSize: SIMD2(1200, 800),
            transform: xf)
        XCTAssertEqual(viaStatic, xf.uv(at: anchor))
        // A point under the zoomed image maps INTO the content that was
        // under it at fit (the anchor-keeping invariant, sampled).
        let identity = PipeCoordinator.viewportUV(
            at: anchor, viewportSize: viewport, textureSize: SIMD2(1200, 800))
        XCTAssertNotNil(identity)
    }
}
