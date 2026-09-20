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
    /// signature and now delegates here).
    static func uv(
        at point: CGPoint, viewportSize: CGSize, textureSize: CGSize
    ) -> SIMD2<Double>? {
        let rect = fittedRect(viewportSize: viewportSize, textureSize: textureSize)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let uv = SIMD2<Double>(
            (point.x - rect.minX) / rect.width,
            (point.y - rect.minY) / rect.height)
        guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { return nil }
        return uv
    }

    /// Normalized texture uv → viewport POINT (the overlay's handle
    /// placement direction).
    static func point(
        at uv: SIMD2<Double>, viewportSize: CGSize, textureSize: CGSize
    ) -> CGPoint? {
        let rect = fittedRect(viewportSize: viewportSize, textureSize: textureSize)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return CGPoint(
            x: rect.minX + CGFloat(uv.x) * rect.width,
            y: rect.minY + CGFloat(uv.y) * rect.height)
    }
}
