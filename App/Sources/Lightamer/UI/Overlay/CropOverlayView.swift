import CoreGraphics
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// CropOverlayView (Plan 04-02-T4, IOP-GEO-01 SC#1 + D-G6) — the EditorMTKView
// overlay: corner/edge/center handles + thirds/phi grid + dimmed scrim.
//
// LAYER (RESEARCH §8): `EditorAreaView`'s ZStack, above `EditorMTKView`,
// below nothing. Inputs: the fitted rect (ViewportFit — the third use of
// the extracted math), the crop record (from `EditorState.instances`),
// and the T0 live-darkening flag (dragging ⇒ crop disabled + scrim).
//
// INTERACTION (D-H1 trio, T0 decision (a) — live-disabled + scrim):
//   gesture start → `onBegin()` (coordinator.beginContinuousEdit)
//   tick          → `onLive(_:)` with a `enabled=false` snapshot (full-frame
//                   render, overlay draws the scrim + rect)
//   gesture end   → `onCommit(_:)` with the `enabled=true` final rect
//                   (exactly ONE history item; the commit renders the window
//                   once).
// The view owns NO pipe state: it converts viewport points ⇄ normalized
// rects and forwards records; the coordinator + history own the rest.
//
// HANDLES (dt `_grab_region_t`, `crop.c:71-88`): 4 corners + 4 edges +
// center map to the 16-state bit field; HitTest below mirrors
// `_gui_get_grab` (inside-box → CENTER, border bands → edges/corners).
//
// ROTATION HANDLE (Plan M9-3-T3 — the 04-02 linkage note kept above until
// this batch landed it): the angle handle floats above the box's top edge;
// dragging orbits it around the box centre and streams the angle delta
// through the D-H1 rotation trio (`onRotateBegin` / `onRotateLive` /
// `onRotateCommit` — the HOST turns live ticks into ashift live
// instances and the commit into the linked ashift+crop batch, NOT a crop
// disable: the OQ-5 ruling renders the live rotation instead of scrimming
// it). The angle math is the pure `CropRotationHandleMath` below.

/// dt `_grab_region_t` (`crop.c:71-88`) — the hit-test bit field.
/// OptionSet so corner combos (TOP|LEFT…) survive hit-testing
/// (a plain enum collapses them to `.center` — corner drags would move).
struct CropGrabRegion: OptionSet, Sendable {
    let rawValue: Int
    static let center = CropGrabRegion([])
    static let left = CropGrabRegion(rawValue: 1)
    static let top = CropGrabRegion(rawValue: 2)
    static let right = CropGrabRegion(rawValue: 4)
    static let bottom = CropGrabRegion(rawValue: 8)
    static let none = CropGrabRegion(rawValue: 16)
}

/// The crop rect in NORMALIZED (fraction) coords + the locked aspect.
struct CropOverlayRect: Equatable, Sendable {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double

    /// Locked aspect w/h (nil = freehand). `original` resolves at drag
    /// time from the upstream plane size.
    var lockedAspect: Double?

    var width: Double { right - left }
    var height: Double { bottom - top }

    /// Clamp into [0,1]² with the MIN_CROP_SIZE floor (dt `commit_params`
    /// + overlay clamp: fractions stay in range, ≥1% on the short side).
    func clamped() -> CropOverlayRect {
        let m = Double(CropLimits.minFraction)
        var out = self
        out.left = min(max(left, 0), 1 - m)
        out.top = min(max(top, 0), 1 - m)
        out.right = min(max(right, m), 1)
        out.bottom = min(max(bottom, m), 1)
        return out
    }

    /// Apply the locked aspect after a corner/edge move: the SHORT side
    /// sticks to the dragged value, the LONG side follows (RESEARCH §2.4).
    /// `anchor` is the corner/edge OPPOSITE the drag (fixed point).
    func withAspectLocked(anchor: CGPoint) -> CropOverlayRect {
        guard let aspect = lockedAspect, aspect > 0 else { return clamped() }
        var out = self
        // Short-side-sticks: compare the dragged rect's aspect against
        // the lock; shrink the long side to match.
        let w = max(width, 1e-6), h = max(height, 1e-6)
        if w / h > aspect {
            // Too wide → shrink width around the anchor x.
            let newW = h * aspect
            if anchor.x < 0.5 { out.right = out.left + newW } else { out.left = out.right - newW }
        } else {
            // Too tall → shrink height around the anchor y.
            let newH = w / aspect
            if anchor.y < 0.5 { out.bottom = out.top + newH } else { out.top = out.bottom - newH }
        }
        return out.clamped()
    }
}

/// Pure hit-test: viewport point → grab region for the rect's fitted box.
/// `border` = grab-band width in viewport points (dt's `border` param,
/// scaled by zoom there — fixed 12pt here, no zoom in Phase 4).
/// `internal` for the unit tests' hit vectors.
func cropHitTest(
    point: CGPoint, rectBox: CGRect, border: CGFloat = 12
) -> CropGrabRegion {
    guard rectBox.contains(point) else { return .none }
    let inLeft = point.x - rectBox.minX < border
        && (point.x - rectBox.minX) < rectBox.width / 2
    let inRight = rectBox.maxX - point.x < border
        && (rectBox.maxX - point.x) < rectBox.width / 2
    let inTop = point.y - rectBox.minY < border
        && (point.y - rectBox.minY) < rectBox.height / 2
    let inBottom = rectBox.maxY - point.y < border
        && (rectBox.maxY - point.y) < rectBox.height / 2
    // Corners first (dt `_gui_get_grab` order: left/right, then top/bottom
    // OR-accumulate — corners emerge as the bit combos).
    var raw = 0
    if inLeft { raw |= 1 }
    if inRight { raw |= 4 }
    if inTop { raw |= 2 }
    if inBottom { raw |= 8 }
    return CropGrabRegion(rawValue: raw)
}

/// The rotation-handle angle math (pure; unit-testable without SwiftUI —
/// M9-3-T3). The handle orbits the box centre; the streamed angle is the
/// VIEWPORT angle (y-down screen space, degrees, clockwise +): dragging
/// the handle right of the box turns the image clockwise on screen. The
/// sign hand-off to ashift.rotation is the TESTS' pin (the +screen-CW
/// delta maps to a NEGATIVE ashift increment — the image turns clockwise
/// while the content coordinate rotation is the inverse), verified by the
/// forward-matrix golden in CropToolRotationTests.
enum CropRotationHandleMath {

    /// Handle rest position: the box top edge centre, lifted by `lift`.
    static func handlePoint(for box: CGRect, lift: CGFloat = 28) -> CGPoint {
        CGPoint(x: box.midX, y: box.minY - lift)
    }

    /// The handle's orbit position for a live angle (degrees, screen-CW+).
    static func orbitPoint(for box: CGRect, angleDegrees: Double, lift: CGFloat = 28) -> CGPoint {
        let a = angleDegrees * Double.pi / 180
        // rotate the rest position about the box centre (y-down CW+)
        let rest = handlePoint(for: box, lift: lift)
        let dx = Double(rest.x - box.midX)
        let dy = Double(rest.y - box.midY)
        let s = sin(a), c = cos(a)
        return CGPoint(
            x: box.midX + CGFloat(c * dx - s * dy),
            y: box.midY + CGFloat(s * dx + c * dy))
    }

    /// The streamed angle for a drag tick: the CURRENT box angle plus the
    /// pointer's angular offset from the drag-start handle position,
    /// folded to ±45° (the ashift slider range). Screen y-down: a pointer
    /// moving clockwise around the centre increases the angle.
    static func liveDegrees(
        box: CGRect, dragStartAngle: Double, dragStartHandle: CGPoint, pointer: CGPoint
    ) -> Double {
        let start = atan2(
            Double(dragStartHandle.y - box.midY), Double(dragStartHandle.x - box.midX))
        let now = atan2(Double(pointer.y - box.midY), Double(pointer.x - box.midX))
        var delta = (now - start) * 180 / Double.pi
        // fold the atan2 wrap into (−180, 180]
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        return min(max(dragStartAngle + delta, -45), 45)
    }
}

/// The overlay view. Pure function of (fittedRect, cropRect, dimmed):
/// all pipe/history traffic exits through the three callbacks (D-H1).
struct CropOverlayView: View {

    /// The fitted image rect in viewport points (ViewportFit).
    let fittedRect: CGRect
    /// The current crop rect (fractions); nil = full frame, no overlay.
    var cropRect: CropOverlayRect?
    /// T0 live state: dragging ⇒ scrim + rect (crop disabled in the pipe).
    var isDimmed: Bool
    /// Grid style.
    var showsPhiGrid: Bool

    /// D-H1 legs (wired by EditorAreaView to the coordinator).
    var onBegin: () -> Void = {}
    var onLive: (CropOverlayRect) -> Void = { _ in }
    var onCommit: (CropOverlayRect) -> Void = { _ in }

    /// The rotation-handle D-H1 trio (M9-3-T3; the HOST wires live ticks
    /// to ashift live instances and the commit to the linked batch).
    /// `degrees` = the SCREEN-CW+ angle; `baseDegrees` = the box angle at
    /// drag start (the live stream carries absolute values).
    var baseRotationDegrees: Double = 0
    var onRotateBegin: () -> Void = {}
    var onRotateLive: (Double) -> Void = { _ in }
    var onRotateCommit: (Double) -> Void = { _ in }

    /// Active drag (viewport-points start + grab region + start rect).
    @State private var drag: (start: CGPoint, region: CropGrabRegion, rect: CropOverlayRect)?
    /// Last live rect this drag produced (commit forwards it — the
    /// parent record may not have re-rendered yet when the drag ends).
    @State private var lastLive: CropOverlayRect?

    /// The active rotation drag (start handle point + live angle).
    @State private var rotationDrag: (startHandle: CGPoint, live: Double)?
    @State private var rotationLive: Double?

    var body: some View {
        GeometryReader { _ in
            ZStack {
                if let rect = cropRect {
                    let box = rectBox(for: rect)
                    // Scrim (T0 (a)): dimmed while dragging (crop disabled
                    // ⇒ full-frame render behind the overlay).
                    if isDimmed {
                        Rectangle()
                            .fill(Color.black.opacity(0.55))
                            .mask {
                                Rectangle()
                                    .fill(Color.black)
                                    .overlay {
                                        Rectangle()
                                            .frame(width: box.width, height: box.height)
                                            .position(x: box.midX, y: box.midY)
                                            .blendMode(.destinationOut)
                                    }
                            }
                            .allowsHitTesting(false)
                    }
                    // Crop rect outline.
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                        .allowsHitTesting(false)
                    // Grid (thirds or phi).
                    gridLines(for: box)
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.75)
                        .allowsHitTesting(false)
                    // Handles: 4 corners + 4 edges + center (L010:
                    // identifiers on the leaves, never a container label).
                    ForEach(handles(for: box), id: \.id) { handle in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .position(handle.point)
                            .accessibilityIdentifier("crop.handle.\(handle.id)")
                            .allowsHitTesting(false)
                    }
                    // The rotation handle (M9-3-T3): above the top edge,
                    // orbits while dragging (the angle streams through the
                    // D-H1 rotation trio; the handle itself is interactive).
                    let liveAngle = rotationLive ?? baseRotationDegrees
                    let handlePoint = rotationDrag != nil
                        ? CropRotationHandleMath.orbitPoint(for: box, angleDegrees: liveAngle)
                        : CropRotationHandleMath.handlePoint(for: box)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .position(handlePoint)
                        .accessibilityIdentifier("crop.handle.rotation")
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    if rotationDrag == nil {
                                        rotationDrag = (value.startLocation, baseRotationDegrees)
                                        rotationLive = baseRotationDegrees
                                        onRotateBegin()
                                    }
                                    let angle = CropRotationHandleMath.liveDegrees(
                                        box: box,
                                        dragStartAngle: rotationDrag!.live,
                                        dragStartHandle: rotationDrag!.startHandle,
                                        pointer: value.location)
                                    rotationLive = angle
                                    onRotateLive(angle)
                                }
                                .onEnded { _ in
                                    let final = rotationLive ?? baseRotationDegrees
                                    rotationDrag = nil
                                    rotationLive = nil
                                    onRotateCommit(final)
                                }
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // NO container accessibilityLabel — L010: it would absorb the
            // handle leaves from the AX tree.
            .accessibilityIdentifier("crop.overlay")
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        dragChanged(at: value.location, translation: value.translation)
                    }
                    .onEnded { value in
                        dragEnded(at: value.location)
                    }
            )
        }
        .allowsHitTesting(cropRect != nil)
    }

    // MARK: - Geometry

    /// Fractions → viewport box.
    func rectBox(for rect: CropOverlayRect) -> CGRect {
        CGRect(
            x: fittedRect.minX + CGFloat(rect.left) * fittedRect.width,
            y: fittedRect.minY + CGFloat(rect.top) * fittedRect.height,
            width: CGFloat(rect.width) * fittedRect.width,
            height: CGFloat(rect.height) * fittedRect.height)
    }

    /// Viewport box → fractions (tick conversion; clamped).
    func overlayRect(for box: CGRect) -> CropOverlayRect {
        CropOverlayRect(
            left: Double((box.minX - fittedRect.minX) / fittedRect.width),
            top: Double((box.minY - fittedRect.minY) / fittedRect.height),
            right: Double((box.maxX - fittedRect.minX) / fittedRect.width),
            bottom: Double((box.maxY - fittedRect.minY) / fittedRect.height),
            lockedAspect: cropRect?.lockedAspect)
            .clamped()
    }

    // MARK: - Drag

    private func dragChanged(at point: CGPoint, translation: CGSize) {
        guard let base = cropRect else { return }
        if drag == nil {
            let box = rectBox(for: base)
            let region = cropHitTest(point: point, rectBox: box)
            guard region != .none else { return }
            drag = (point, region, base)
            onBegin()
        }
        guard let active = drag else { return }
        let dx = Double(translation.width / fittedRect.width)
        let dy = Double(translation.height / fittedRect.height)
        var next = active.rect
        let r = active.region.rawValue
        if r == 0 {
            // Center: move the whole box.
            next.left += dx; next.right += dx
            next.top += dy; next.bottom += dy
        } else {
            if r & 1 != 0 { next.left += dx }
            if r & 4 != 0 { next.right += dx }
            if r & 2 != 0 { next.top += dy }
            if r & 8 != 0 { next.bottom += dy }
        }
        // Aspect lock (corners only — edges drag free, dt `_aspect_apply`
        // keeps the dragged axis): anchor = opposite corner.
        if next.lockedAspect != nil, r != 0, r != 1, r != 2, r != 4, r != 8 {
            let anchor = CGPoint(
                x: (r & 1 != 0) ? 1 : 0, y: (r & 2 != 0) ? 1 : 0)
            next = next.withAspectLocked(anchor: anchor)
        } else {
            next = next.clamped()
        }
        lastLive = next
        onLive(next)
    }

    private func dragEnded(at point: CGPoint) {
        guard drag != nil else { return }
        drag = nil
        if let rect = lastLive ?? cropRect {
            lastLive = nil
            onCommit(rect)
        }
    }


    // MARK: - Grid + handles

    private func gridLines(for box: CGRect) -> Path {
        var path = Path()
        let ratios: [CGFloat] = showsPhiGrid ? [0.3819, 0.6181] : [1 / 3, 2 / 3]
        for r in ratios {
            path.move(to: CGPoint(x: box.minX + box.width * r, y: box.minY))
            path.addLine(to: CGPoint(x: box.minX + box.width * r, y: box.maxY))
            path.move(to: CGPoint(x: box.minX, y: box.minY + box.height * r))
            path.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * r))
        }
        return path
    }

    private struct Handle: Sendable {
        var id: String
        var point: CGPoint
    }

    private func handles(for box: CGRect) -> [Handle] {
        [
            Handle(id: "topLeft", point: CGPoint(x: box.minX, y: box.minY)),
            Handle(id: "top", point: CGPoint(x: box.midX, y: box.minY)),
            Handle(id: "topRight", point: CGPoint(x: box.maxX, y: box.minY)),
            Handle(id: "right", point: CGPoint(x: box.maxX, y: box.midY)),
            Handle(id: "bottomRight", point: CGPoint(x: box.maxX, y: box.maxY)),
            Handle(id: "bottom", point: CGPoint(x: box.midX, y: box.maxY)),
            Handle(id: "bottomLeft", point: CGPoint(x: box.minX, y: box.maxY)),
            Handle(id: "left", point: CGPoint(x: box.minX, y: box.midY)),
            Handle(id: "center", point: CGPoint(x: box.midX, y: box.midY)),
        ]
    }
}
