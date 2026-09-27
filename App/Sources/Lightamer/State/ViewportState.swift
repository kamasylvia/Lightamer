import Foundation
import Observation

// ─────────────────────────────────────────────────────────────────────────
// ViewportState (Plan 13-3 T1/T2/T3, D-13-CONTEXT-6) — the zoom/pan/
// rotation state machine + the overlay mutex lock. D-03b isolated state:
// it owns ONLY viewport geometry state; it holds no references to the
// editor/coordinator states (the views + EditorMTKView's Coordinator push
// and read it).
//
// Zoom state machine (SYS-03): `fit` (the 04-02 identity layout — the
// default), `hundredPercent` (1 image px = 1 viewport point), `free`
// (cursor-anchored magnify / two-finger pan / rotate). ANY free input
// moves the mode to `free`; `fit()` restores the pristine identity.
//
// Overlay mutex (D-13-CONTEXT-6③, v1 从简): while `zoomLocked` (the
// crop/liquify/retouch route owns the viewport — their overlay geometry
// assumes the fit layout), EVERY gesture input is swallowed and entering
// the lock forces the fit identity. The mask brush / segment taps are NOT
// in the lock set — they inverse-map through `ViewportFit` (T3).
//
// All math delegates to `ViewportFit` (the single math source — the
// second fit/zoom math is banned there).
// ─────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class ViewportState {

    /// The zoom state machine's mode (display + the HUD's label face).
    enum ZoomMode: Equatable {
        case fit
        case hundredPercent
        case free
    }

    /// Free-zoom ceiling (× fit). Execution decision (13-3-DECISIONS):
    /// the zoom range is [min(1, 100%), 32] — the floor dips below fit
    /// only to reach the 100% state of a SMALLER-than-viewport image.
    nonisolated static let maxZoom: Double = 32.0

    /// ⌘-scroll zoom sensitivity (per wheel tick, multiplicative).
    nonisolated static let scrollZoomTickFactor: Double = 0.08

    private(set) var mode: ZoomMode = .fit

    /// The zoom factor relative to the FIT layout (1 = fit).
    private(set) var zoom: Double = 1.0

    /// Viewport-point offset applied after zoom+rotation (see the
    /// `ViewportTransform` composition).
    private(set) var pan: CGPoint = .zero

    /// Degrees; positive = clockwise on screen (y-down points).
    private(set) var rotationDegrees: Double = 0.0

    /// The overlay mutex (crop/liquify/retouch route). Entering the lock
    /// snaps back to the fit identity; gestures are swallowed while set.
    private(set) var zoomLocked = false

    // MARK: last-seen geometry (the menu-command leg — ⌘0 Actual Size runs
    // in the App scene without view geometry; the viewport keeps the last
    // real sizes here. Execution decision, 13-3-DECISIONS.)

    private var lastViewportSize: CGSize = .zero
    private var lastTextureSize: CGSize = .zero

    /// The editor viewport reports its live sizes (EditorAreaView /
    /// EditorMTKView push). Zero sizes are ignored (never clobber a good
    /// value with a transient empty frame).
    func noteGeometry(viewportSize: CGSize, textureSize: CGSize) {
        if viewportSize.width >= 1, viewportSize.height >= 1 {
            lastViewportSize = viewportSize
        }
        if textureSize.width >= 1, textureSize.height >= 1 {
            lastTextureSize = textureSize
        }
    }

    // MARK: transform

    /// The current transform for the given geometry (the ONE consumer
    /// seam — blit quad, overlays, eyedropper all build from here).
    func transform(viewportSize: CGSize, textureSize: CGSize) -> ViewportTransform {
        ViewportFit.transform(
            viewportSize: viewportSize, textureSize: textureSize,
            zoom: zoom, pan: pan, rotationDegrees: rotationDegrees)
    }

    /// The HUD/menu label: 100 = fit, and 100% displays as its own factor.
    var displayPercent: Int { Int((zoom * 100).rounded()) }

    // MARK: gesture entries (all swallow while locked)

    /// Trackpad pinch (magnify gesture): multiplicative delta, anchored at
    /// the cursor. Locked → no-op (the mutex matrix).
    func magnify(
        delta: Double, anchoredAt anchor: CGPoint?,
        viewportSize: CGSize, textureSize: CGSize
    ) {
        guard !zoomLocked else { return }
        noteGeometry(viewportSize: viewportSize, textureSize: textureSize)
        guard let rect = liveRect(viewportSize: viewportSize, textureSize: textureSize)
        else { return }
        applyZoom(
            zoom * (1 + delta), anchoredAt: anchor,
            viewportSize: viewportSize, textureSize: textureSize, rect: rect)
    }

    /// ⌘-scroll zoom (the keyboard-mouse fallback leg): wheel ticks,
    /// anchored at the cursor.
    func scrollZoom(
        ticks: Double, anchoredAt anchor: CGPoint?,
        viewportSize: CGSize, textureSize: CGSize
    ) {
        guard !zoomLocked else { return }
        magnify(
            delta: -ticks * Self.scrollZoomTickFactor, anchoredAt: anchor,
            viewportSize: viewportSize, textureSize: textureSize)
    }

    /// Two-finger scroll pan (content follows the fingers: the deltas
    /// subtract — the trackpad's natural-scrolling convention; the FEEL
    /// is Manual-Only registered, the SIGN is pinned by the unit tests).
    /// A pristine fit has nothing to pan into — the input is ignored
    /// until some zoom/rotation is active.
    func scrollPan(deltaX: Double, deltaY: Double) {
        guard !zoomLocked else { return }
        guard mode != .fit else { return }
        pan = CGPoint(x: pan.x - CGFloat(deltaX), y: pan.y - CGFloat(deltaY))
    }

    /// Trackpad rotate gesture (degrees, anchored at the cursor).
    func rotate(
        deltaDegrees: Double, anchoredAt anchor: CGPoint?,
        viewportSize: CGSize, textureSize: CGSize
    ) {
        guard !zoomLocked else { return }
        noteGeometry(viewportSize: viewportSize, textureSize: textureSize)
        guard let rect = liveRect(viewportSize: viewportSize, textureSize: textureSize)
        else { return }
        if mode == .fit { mode = .free }
        if let anchor,
           let uv = ViewportFit.uv(
            at: anchor, viewportSize: viewportSize, textureSize: textureSize) {
            // Keep the cursor's image point fixed under the rotation.
            pan = ViewportFit.panKeeping(
                uv: uv, anchor: anchor, rect: rect,
                zoom: zoom, rotationDegrees: rotationDegrees + deltaDegrees)
        }
        rotationDegrees = (rotationDegrees + deltaDegrees)
            .truncatingRemainder(dividingBy: 360)
    }

    /// The two-finger double-tap (smart magnify): toggle fit ↔ 100%.
    func smartMagnify(viewportSize: CGSize, textureSize: CGSize) {
        guard !zoomLocked else { return }
        if mode == .fit {
            actualSize(viewportSize: viewportSize, textureSize: textureSize)
        } else {
            fit()
        }
    }

    // MARK: mode entries (menu/HUD seams)

    /// Back to the pristine fit identity (zoom 1, pan zero, rotation 0).
    func fit() {
        mode = .fit
        zoom = 1.0
        pan = .zero
        rotationDegrees = 0
    }

    /// The 100% state with the REMEMBERED geometry (the App-scene menu
    /// seam — ⌘0 / the HUD have no live view sizes there).
    func actualSize() {
        guard !zoomLocked else { return }
        actualSize(viewportSize: lastViewportSize, textureSize: lastTextureSize)
    }

    /// 100% with explicit geometry (the view seam).
    func actualSize(viewportSize: CGSize, textureSize: CGSize) {
        guard !zoomLocked else { return }
        noteGeometry(viewportSize: viewportSize, textureSize: textureSize)
        guard let rect = liveRect(viewportSize: viewportSize, textureSize: textureSize),
              let hundred = ViewportFit.hundredPercentZoom(
                viewportSize: viewportSize, textureSize: textureSize)
        else { return }
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        applyZoom(
            hundred, anchoredAt: center,
            viewportSize: viewportSize, textureSize: textureSize, rect: rect)
        if zoom == hundred { mode = .hundredPercent }
    }

    /// Reset the rotation only (the HUD's double-click face; anchored at
    /// the viewport center so the image stays put).
    func resetRotation(viewportSize: CGSize, textureSize: CGSize) {
        guard !zoomLocked, rotationDegrees != 0 else { return }
        guard let rect = liveRect(viewportSize: viewportSize, textureSize: textureSize)
        else { return }
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        if let uv = ViewportFit.uv(
            at: center, viewportSize: viewportSize, textureSize: textureSize) {
            pan = ViewportFit.panKeeping(
                uv: uv, anchor: center, rect: rect,
                zoom: zoom, rotationDegrees: 0)
        }
        rotationDegrees = 0
    }

    /// Nudge zoom from the HUD's −/+ buttons (center-anchored).
    func stepZoom(factor: Double, viewportSize: CGSize, textureSize: CGSize) {
        guard !zoomLocked else { return }
        noteGeometry(viewportSize: viewportSize, textureSize: textureSize)
        guard let rect = liveRect(viewportSize: viewportSize, textureSize: textureSize)
        else { return }
        applyZoom(
            zoom * factor, anchoredAt: nil,
            viewportSize: viewportSize, textureSize: textureSize, rect: rect)
    }

    // MARK: the overlay mutex (T3)

    /// Lock/unlock for the viewport-exclusive overlays (crop/liquify/
    /// retouch). Entering the lock snaps to the fit identity (D-13-
    /// CONTEXT-6③: 切面板自动回 fit); the unlock stays at fit (the user
    /// re-zooms from there).
    func setZoomLocked(_ locked: Bool) {
        guard zoomLocked != locked else { return }
        zoomLocked = locked
        if locked {
            fit()
        }
    }

    // MARK: plumbing

    private func liveRect(viewportSize: CGSize, textureSize: CGSize) -> CGRect? {
        let rect = ViewportFit.fittedRect(
            viewportSize: viewportSize, textureSize: textureSize)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return rect
    }

    /// The zoom-apply core: clamp to [min(1, 100%), maxZoom], keep the
    /// anchor's image point fixed (cursor-anchored zoom), demote `fit` to
    /// `free` on any non-identity zoom. ALL math reads `ViewportFit` —
    /// no second fit/zoom formula lives here.
    private func applyZoom(
        _ proposed: Double,
        anchoredAt anchor: CGPoint?,
        viewportSize: CGSize,
        textureSize: CGSize,
        rect: CGRect
    ) {
        let hundred = ViewportFit.hundredPercentZoom(
            viewportSize: viewportSize, textureSize: textureSize) ?? 1.0
        let floor = min(1.0, hundred)
        let next = min(max(proposed, floor), Self.maxZoom)
        if next == zoom {
            if mode == .fit, next != 1 { mode = .free }
            return
        }
        if let anchor,
           let uv = ViewportTransform(
            rect: rect, zoom: zoom, pan: pan, rotationDegrees: rotationDegrees
           ).uv(at: anchor) {
            pan = ViewportFit.panKeeping(
                uv: uv, anchor: anchor, rect: rect,
                zoom: next, rotationDegrees: rotationDegrees)
        }
        zoom = next
        if mode == .fit { mode = .free }
    }
}
