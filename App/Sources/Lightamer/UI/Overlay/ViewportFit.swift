import CoreGraphics
import simd

// ─────────────────────────────────────────────────────────────────────────
// ViewportFit (Plan 04-02-T4) — the aspect-fit math in ONE place.
//
// Three consumers shared two copies of this math (RESEARCH §6遗留债):
// `PipeCoordinator.viewportUV` (uv from a viewport point) and
// `EditorMTKView.Coordinator.aspectFitUniforms` (NDC scale for the blit).
// The crop overlay is the third — it needs the FITTED RECT itself (to
// place handles/grids in viewport points). All three derive from the
// single `fittedRect` below; the two call sites keep their signatures
// (UI behavior byte-identical) and delegate here.
//
// Plan 13-3 T1 (D-13-CONTEXT-6): the SAME single point now carries the
// zoom/pan/rotation math — `ViewportTransform` composes ON TOP of
// `fittedRect` and every consumer (blit quad, mask overlay inverse
// mapping, eyedropper, segment taps) reads the transform from here.
// SECOND FIT/ZOOM MATH ELSEWHERE IS BANNED (the file's whole job).
//
// Convention (matches both call sites): the image centers in the
// viewport; the fitted rect is the maximal aspect-preserving rect.
// Letterbox bands are empty (no uv / no handles there).
// ─────────────────────────────────────────────────────────────────────────

/// Aspect-fit geometry shared by the viewport blit, the eyedropper
/// picker, and the crop overlay. App-layer `internal` (Core never
/// depends on UI — RESEARCH §6).
enum ViewportFit {

    /// The image rect (viewport points) when `textureSize` aspect-fits
    /// inside `viewportSize`, centered. Zero-size on degenerate input
    /// (mirrors both call sites' guards).
    static func fittedRect(
        viewportSize: CGSize, textureSize: CGSize
    ) -> CGRect {
        guard viewportSize.width >= 1, viewportSize.height >= 1,
              textureSize.width >= 1, textureSize.height >= 1
        else { return .zero }
        let fit = min(
            viewportSize.width / textureSize.width,
            viewportSize.height / textureSize.height)
        let w = textureSize.width * fit
        let h = textureSize.height * fit
        return CGRect(
            x: (viewportSize.width - w) / 2,
            y: (viewportSize.height - h) / 2,
            width: w, height: h)
    }

    /// Per-axis NDC scale of the fitted rect (`aspectFitUniforms`
    /// semantics: `fit·tw/vw`, `fit·th/vh`; ≤ 1, 1 on the constraining
    /// axis; (1,1) on degenerate input).
    static func blitScale(
        viewportSize: CGSize, textureSize: CGSize
    ) -> SIMD2<Double> {
        guard viewportSize.width >= 1, viewportSize.height >= 1,
              textureSize.width >= 1, textureSize.height >= 1
        else { return SIMD2(1, 1) }
        let fit = min(
            viewportSize.width / textureSize.width,
            viewportSize.height / textureSize.height)
        return SIMD2(
            fit * Double(textureSize.width) / Double(viewportSize.width),
            fit * Double(textureSize.height) / Double(viewportSize.height))
    }

    /// Viewport POINT → normalized texture uv (nil in the letterbox).
    /// Same math as `PipeCoordinator.viewportUV` (which keeps its
    /// signature and now delegates here). `transform` non-nil = the point
    /// is inverse-mapped through the zoom/pan/rotation state first
    /// (13-3 T1/T3 — mask brush + eyedropper + segment taps).
    static func uv(
        at point: CGPoint, viewportSize: CGSize, textureSize: CGSize,
        transform: ViewportTransform? = nil
    ) -> SIMD2<Double>? {
        if let transform {
            return transform.uv(at: point)
        }
        let rect = fittedRect(viewportSize: viewportSize, textureSize: textureSize)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let uv = SIMD2<Double>(
            (point.x - rect.minX) / rect.width,
            (point.y - rect.minY) / rect.height)
        guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { return nil }
        return uv
    }

    /// Normalized texture uv → viewport POINT (the overlay's handle
    /// placement direction). `transform` non-nil = forward-mapped through
    /// the zoom/pan/rotation state (13-3 T1).
    static func point(
        at uv: SIMD2<Double>, viewportSize: CGSize, textureSize: CGSize,
        transform: ViewportTransform? = nil
    ) -> CGPoint? {
        if let transform {
            return transform.point(atUV: uv)
        }
        let rect = fittedRect(viewportSize: viewportSize, textureSize: textureSize)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return CGPoint(
            x: rect.minX + CGFloat(uv.x) * rect.width,
            y: rect.minY + CGFloat(uv.y) * rect.height)
    }

    // MARK: - 13-3 T1: the zoom/pan/rotation transform (single math source)

    /// Compose the full viewport transform: the base `fittedRect` with
    /// `zoom` (1 = fit) about the rect center, then `rotationDegrees`
    /// about the same center, then `pan` (viewport points). The ONE
    /// factory every consumer builds from — no second composition.
    static func transform(
        viewportSize: CGSize, textureSize: CGSize,
        zoom: Double, pan: CGPoint, rotationDegrees: Double
    ) -> ViewportTransform {
        ViewportTransform(
            rect: fittedRect(viewportSize: viewportSize, textureSize: textureSize),
            zoom: zoom, pan: pan, rotationDegrees: rotationDegrees)
    }

    /// The zoom factor that displays 1 image pixel = 1 viewport point
    /// (the 100% state): the fitted rect must scale up to the texture's
    /// pixel width. `nil` on degenerate geometry.
    static func hundredPercentZoom(
        viewportSize: CGSize, textureSize: CGSize
    ) -> Double? {
        let rect = fittedRect(viewportSize: viewportSize, textureSize: textureSize)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return Double(textureSize.width) / Double(rect.width)
    }

    /// The pan that keeps `uv` pinned under `anchor` after the state
    /// moves to (`newZoom`, `newRotationDegrees`) — the cursor-anchored
    /// zoom/rotate math. Composition (13-3 T1): screen(p) =
    /// R(z·(p − c)) + c + pan with c = rect center, so the kept-anchor
    /// pan is anchor − R(z'·(fit(uv) − c)) (the pan lands AFTER the
    /// rotation, component-wise).
    static func panKeeping(
        uv: SIMD2<Double>, anchor: CGPoint, rect: CGRect,
        zoom newZoom: Double, rotationDegrees newRotation: Double
    ) -> CGPoint {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let fit = CGPoint(
            x: rect.minX + CGFloat(uv.x) * rect.width,
            y: rect.minY + CGFloat(uv.y) * rect.height)
        let scaled = CGPoint(
            x: c.x + (fit.x - c.x) * CGFloat(newZoom),
            y: c.y + (fit.y - c.y) * CGFloat(newZoom))
        let rotated = Self.rotated(scaled, around: c, by: newRotation)
        return CGPoint(x: anchor.x - rotated.x, y: anchor.y - rotated.y)
    }

    /// Rotate `p` around `center` by `degrees` (screen points, y-down).
    static func rotated(
        _ p: CGPoint, around center: CGPoint, by degrees: Double
    ) -> CGPoint {
        let radians = degrees * .pi / 180
        let dx = p.x - center.x, dy = p.y - center.y
        let cos = CGFloat(cos(radians)), sin = CGFloat(sin(radians))
        return CGPoint(
            x: center.x + dx * cos - dy * sin,
            y: center.y + dx * sin + dy * cos)
    }
}

// ─────────────────────────────────────────────────────────────────────────
// ViewportTransform (13-3 T1) — the immutable zoom/pan/rotation geometry
// derived from ONE `fittedRect` base. Composition order (pinned by
// ViewportTransformTests): zoom about the rect center → rotation about
// the SAME center → pan. Identity (zoom 1, pan zero, rotation 0) is
// byte-equivalent to the bare fitted rect (the 04-02 fit layout).
// ─────────────────────────────────────────────────────────────────────────
struct ViewportTransform: Equatable {

    /// The base fitted rect (the 04-02 fit layout — the identity state).
    let rect: CGRect
    /// 1 = fit; `ViewportFit.hundredPercentZoom` is the 100% state.
    let zoom: Double
    /// Viewport-point offset applied AFTER zoom and rotation.
    let pan: CGPoint
    /// Degrees, about the rect center (y-down screen convention: positive
    /// = clockwise on screen).
    let rotationDegrees: Double

    /// True when the transform is EXACTLY the bare fit layout (the state
    /// machine's `.fit` mode) — consumers may take the zero-cost path.
    var isIdentity: Bool {
        zoom == 1 && pan == .zero && rotationDegrees == 0
    }

    /// Normalized texture uv → viewport point. Total function over uv
    /// (the caller guards the degenerate rect).
    func point(atUV uv: SIMD2<Double>) -> CGPoint {
        let fit = CGPoint(
            x: rect.minX + CGFloat(uv.x) * rect.width,
            y: rect.minY + CGFloat(uv.y) * rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let scaled = CGPoint(
            x: c.x + (fit.x - c.x) * CGFloat(zoom),
            y: c.y + (fit.y - c.y) * CGFloat(zoom))
        let rotated = ViewportFit.rotated(scaled, around: c, by: rotationDegrees)
        return CGPoint(x: rotated.x + pan.x, y: rotated.y + pan.y)
    }

    /// Viewport point → normalized texture uv; nil outside the image
    /// content (the letterbox / outside the rotated image bounds — the
    /// caller decides clamp-vs-ignore; mask strokes IGNORE).
    func uv(at point: CGPoint) -> SIMD2<Double>? {
        guard rect.width >= 1, rect.height >= 1, zoom != 0 else { return nil }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let unpanned = CGPoint(x: point.x - pan.x, y: point.y - pan.y)
        let unrotated = ViewportFit.rotated(
            unpanned, around: c, by: -rotationDegrees)
        let fit = CGPoint(
            x: c.x + (unrotated.x - c.x) / CGFloat(zoom),
            y: c.y + (unrotated.y - c.y) / CGFloat(zoom))
        let uv = SIMD2<Double>(
            (fit.x - rect.minX) / rect.width,
            (fit.y - rect.minY) / rect.height)
        guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { return nil }
        return uv
    }

    /// The same geometry as a path-space affine (Canvas drawing maps fit-
    /// space shapes to the screen; line widths stay screen-constant
    /// because the PATH transforms, not the context).
    var affine: CGAffineTransform {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var t = CGAffineTransform(translationX: -c.x, y: -c.y)
        t = t.scaledBy(x: CGFloat(zoom), y: CGFloat(zoom))
        t = t.translatedBy(x: c.x, y: c.y)
        t = t.translatedBy(x: -c.x, y: -c.y)
        t = t.rotated(by: CGFloat(rotationDegrees * .pi / 180))
        t = t.translatedBy(x: c.x, y: c.y)
        t = t.translatedBy(x: pan.x, y: pan.y)
        return t
    }
}
