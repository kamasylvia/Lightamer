import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// MaskOverlayHost (Plan 06-05 T3) — the viewport drawing surface for the
// selected layer's drawn mask, mounted when `LayerEditingState` routes the
// viewport to `.maskEditing` (the machine owns the crop/liquify mutex).
//
// Semantics:
// - Every tool edits the SELECTED layer's `MaskSpec.drawn` payload through
//   the EditorState D-H1 pair: `applyLiveLayer` per drag tick (zero
//   history, live composite re-render via the maskVersion flip — the 06-3
//   incremental leg) and ONE `commitLayerEdit` structure item per finished
//   stroke/form (「笔画结束 1 条」).
// - Brush/eraser: press-drag paints a bezier-chained stroke (straight v1
//   segments, corner = ctrl points); the eraser is the NEGATIVE-density
//   stroke (D-06-03-T5-1). Stroke-level radius/hardness/flow/opacity ride
//   the `LayerEditingState` brush parameters.
// - Gradient: press-drag pulls the falloff line out of the anchor (the
//   anchor→cursor vector = rotation + compression); re-grabbing the anchor
//   or the tip handle adjusts an existing gradient. The linear/sigmoidal
//   profile follows the toolbar toggle.
// - Ellipse: press-drag out from the center; re-grabbing the rim resizes,
//   the center translates.
// - Path: click adds a node; dragging near a node moves it. The fill
//   closes implicitly once ≥3 nodes exist (the rasterizer's SDF).
// - Coordinates: full-decode-frame NORMALIZED points (D-06-CONTEXT-7)
//   mapped through the aspect-fit rect — v1 assumes no active
//   frame-changing upstream geometry (the D-06-06-T4-2 assumption; the
//   GeometryPointMapper single-point integration is the shared follow-up).
// - The form under edit is appended to the layer's mask AT PRESS TIME with
//   its real UUID (so every live tick mutates by id — no draft shadow
//   state); the ONE history item lands at drag end.
// - Feel/latency/cursor feedback are NOT unit-testable — Manual-Only
//   register (L011/L021), FINDINGS registration is the acceptance leg.
// ─────────────────────────────────────────────────────────────────────────

internal struct MaskOverlayHost: View {

    let viewportSize: CGSize
    let displaySize: CGSize

    @Environment(EditorState.self) private var editorState
    @Environment(LayerEditingState.self) private var editingState
    /// 13-3 T3: the zoom/pan/rotation state — the brush inverse-maps the
    /// cursor through `ViewportFit` (the single math source), so mask
    /// drawing stays correct while the viewport is zoomed/rotated (the
    /// 06-06 fit-layout assumption is retired FOR THE MASK ROUTE ONLY;
    /// crop/liquify/retouch stay locked to fit by the mutex).
    @Environment(ViewportState.self) private var viewportState

    /// What the current drag grabbed (always references a REAL form id in
    /// the layer's mask — press installs the form first).
    private enum Grab: Equatable {
        case stroke(UUID) // brush/eraser
        case gradientTip(UUID) // a new gradient being pulled out + handle
        case gradientAnchor(UUID)
        case ellipseRim(UUID) // a new ellipse being dragged out + resize
        case ellipseCenter(UUID)
        case pathNode(UUID, index: Int)
    }
    @State private var grab: Grab?
    /// The stroke press point (the ellipse/gradient anchor lives in the
    /// form record itself; the stroke needs its press point for spacing).
    @State private var pressedPoint: MaskPoint?
    /// True when THIS interaction actually mutated the mask (a pure
    /// handle tap without movement must NOT fabricate a history item).
    @State private var dirty = false

    private var layer: AdjustmentLayer? {
        editingState.selectedLayer(in: editorState.layerStack)
    }

    var body: some View {
        if let layer,
           let tool = editingState.activeTool,
           displaySize.width >= 1, displaySize.height >= 1 {
            let xf = viewportState.transform(
                viewportSize: viewportSize, textureSize: displaySize)
            if xf.rect.width >= 1, xf.rect.height >= 1 {
                ZStack {
                    maskCanvas(transform: xf)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragGesture(layer: layer, tool: tool, transform: xf))
                        .onTapGesture { location in
                            handleTap(
                                at: location, layer: layer, tool: tool, transform: xf)
                        }
                }
                .accessibilityIdentifier("mask.overlay")
            }
        }
    }

    // MARK: canvas (existing forms + the active-form handles)

    /// The fit-space builders below are identical to the 06-05 shapes;
    /// 13-3 T3 maps them to the screen ONCE through the transform's
    /// affine (the path transforms, so line widths stay screen-constant).
    private func maskCanvas(transform xf: ViewportTransform) -> some View {
        Canvas { context, _ in
            func fitPoint(_ n: MaskPoint) -> CGPoint {
                CGPoint(
                    x: xf.rect.minX + CGFloat(n.x) * xf.rect.width,
                    y: xf.rect.minY + CGFloat(n.y) * xf.rect.height)
            }
            func screen(_ n: MaskPoint) -> CGPoint { xf.point(atUV: n.asUV) }
            guard let layer, let drawn = layer.mask?.drawn else { return }
            for form in drawn.forms {
                switch form.kind {
                case let .brush(stroke):
                    var path = Path()
                    for (index, p) in stroke.points.enumerated() {
                        let pt = fitPoint(p.corner)
                        if index == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    context.stroke(
                        path.applying(xf.affine),
                        with: .color(stroke.density < 0 ? .cyan : .yellow),
                        lineWidth: 2)
                case let .gradient(g):
                    var path = Path()
                    path.move(to: fitPoint(g.anchor))
                    path.addLine(to: fitPoint(gradientTip(g)))
                    context.stroke(
                        path.applying(xf.affine),
                        with: .color(.yellow), lineWidth: 2)
                    for p in [g.anchor, gradientTip(g)] {
                        handleDot(at: screen(p), &context, filled: true)
                    }
                case let .ellipse(e):
                    // The rotated+zoomed ellipse is the fit-space ellipse
                    // through the transform affine.
                    let rx = CGFloat(e.radiusX) * xf.rect.width
                    let ry = CGFloat(e.radiusY) * xf.rect.width
                    let rect = CGRect(
                        x: fitPoint(e.center).x - rx, y: fitPoint(e.center).y - ry,
                        width: rx * 2, height: ry * 2)
                    context.stroke(
                        Path(ellipseIn: rect).applying(xf.affine),
                        with: .color(.yellow), lineWidth: 2)
                    handleDot(
                        at: screen(MaskPoint(x: e.center.x + e.radiusX, y: e.center.y)),
                        &context, filled: false)
                case let .path(p):
                    var path = Path()
                    for (index, node) in p.nodes.enumerated() {
                        let pt = fitPoint(node.corner)
                        if index == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    if p.nodes.count >= 3 { path.closeSubpath() }
                    context.stroke(
                        path.applying(xf.affine),
                        with: .color(.yellow.opacity(0.9)), lineWidth: 1.5)
                    for node in p.nodes {
                        handleDot(at: screen(node.corner), &context, filled: true)
                    }
                }
            }
        }
    }

    private func handleDot(
        at p: CGPoint, _ context: inout GraphicsContext, filled: Bool
    ) {
        let rect = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
        if filled {
            context.fill(Path(ellipseIn: rect), with: .color(.white))
        }
        context.stroke(Path(ellipseIn: rect), with: .color(.yellow), lineWidth: 1.5)
    }

    // MARK: gestures

    private func dragGesture(
        layer: AdjustmentLayer, tool: MaskTool, transform xf: ViewportTransform
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // 13-3 T3: the cursor inverse-maps through the transform
                // (zoom/rotation-aware); a point outside the image
                // content paints NOTHING (the 06-05 clamp-to-edge form
                // is retired with the fit-layout assumption).
                guard let p = xf.uv(at: value.location).map(\.asMaskPoint) else {
                    return
                }
                pressedPoint = p
                switch tool {
                case .brush, .eraser:
                    dragStroke(layer: layer, tool: tool, at: p)
                case .gradient:
                    dragGradient(
                        layer: layer, at: p, screen: value.location, transform: xf)
                case .ellipse:
                    dragEllipse(
                        layer: layer, at: p, screen: value.location, transform: xf)
                case .path:
                    dragPathNode(layer: layer, at: p)
                }
            }
            .onEnded { _ in
                endInteraction()
            }
    }

    /// Path nodes are TAP-added (a tap near an existing node selects it
    /// for the NEXT drag; a tap in the open adds one).
    private func handleTap(
        at location: CGPoint, layer: AdjustmentLayer, tool: MaskTool,
        transform xf: ViewportTransform
    ) {
        guard tool == .path else { return }
        guard let p = xf.uv(at: location).map(\.asMaskPoint) else { return }
        if let hit = nearestPathNode(layer: layer, screen: location, transform: xf) {
            grab = .pathNode(hit.formID, index: hit.nodeIndex)
            endInteraction() // a pure handle tap changes nothing — free
            return
        }
        appendPathNode(layer: layer, at: p)
        endInteraction() // the node-add is its own ONE commit
    }

    // MARK: per-tool legs

    private func dragStroke(layer: AdjustmentLayer, tool: MaskTool, at p: MaskPoint) {
        switch grab {
        case let .stroke(formID):
            updateStrokeForm(id: formID, layer: layer) { stroke in
                guard let last = stroke.points.last else { return }
                // Append past a minimum travel (stamp spacing ~ radius/3).
                let dx = p.x - last.corner.x, dy = p.y - last.corner.y
                guard (dx * dx + dy * dy).squareRoot()
                    > editingState.brushRadius / 3 else { return }
                stroke.points.append(BrushPoint(corner: p, ctrl1: p, ctrl2: p))
            }
        case nil:
            // Press: install the stroke form with its REAL id.
            let density: Float = tool == .eraser ? -editingState.brushFlow : editingState.brushFlow
            let stroke = BrushStroke(
                points: [BrushPoint(corner: p, ctrl1: p, ctrl2: p)],
                radius: editingState.brushRadius,
                hardness: editingState.brushHardness,
                density: density,
                opacity: editingState.brushOpacity)
            let form = appendForm(.brush(stroke), layer: layer)
            grab = .stroke(form.id)
        default:
            break
        }
    }

    private func dragGradient(
        layer: AdjustmentLayer, at p: MaskPoint, screen location: CGPoint,
        transform xf: ViewportTransform
    ) {
        if grab == nil {
            // Hit-test the existing handles BEFORE creating a new form —
            // 13-3 T3: SCREEN-space 16px (rotation/zoom-proof; the 06-05
            // normalized-space distance is wrong once the view rotates).
            if let hit = gradientHandle(layer: layer, screen: location, transform: xf) {
                grab = hit
                return
            }
            // Press: a new gradient anchored here (compression floor).
            let g = GradientForm(
                anchor: p, rotationDegrees: 0, compression: 0.001,
                state: editingState.gradientState)
            let form = appendForm(.gradient(g), layer: layer)
            grab = .gradientTip(form.id)
            return
        }
        switch grab {
        case let .gradientTip(formID):
            updateGradientForm(id: formID, layer: layer) { g in
                applyGradientTip(&g, tip: p)
            }
        case let .gradientAnchor(formID):
            updateGradientForm(id: formID, layer: layer) { g in
                g.anchor = p
            }
        default:
            break
        }
    }

    private func dragEllipse(
        layer: AdjustmentLayer, at p: MaskPoint, screen location: CGPoint,
        transform xf: ViewportTransform
    ) {
        if grab == nil {
            if let hit = ellipseHandle(layer: layer, screen: location, transform: xf) {
                grab = hit
                return
            }
            // Press: a new ellipse centered here.
            let e = EllipseForm(
                center: p, radiusX: 0.005, radiusY: 0.005,
                rotationDegrees: 0, border: 0)
            let form = appendForm(.ellipse(e), layer: layer)
            grab = .ellipseRim(form.id)
            return
        }
        switch grab {
        case let .ellipseRim(formID):
            updateEllipseForm(id: formID, layer: layer) { e in
                e.radiusX = max(0.005, abs(p.x - e.center.x))
                e.radiusY = max(0.005, abs(p.y - e.center.y))
            }
        case let .ellipseCenter(formID):
            updateEllipseForm(id: formID, layer: layer) { e in
                guard let press = pressedPoint else {
                    e.center = p
                    return
                }
                // Translate by the drag delta from the press point.
                e.center = MaskPoint(
                    x: e.center.x + (p.x - press.x), y: e.center.y + (p.y - press.y))
                pressedPoint = p
            }
        default:
            break
        }
    }

    private func dragPathNode(layer: AdjustmentLayer, at p: MaskPoint) {
        if case let .pathNode(formID, index) = grab {
            updatePathForm(id: formID, layer: layer) { path in
                guard path.nodes.indices.contains(index) else { return }
                path.nodes[index].corner = p
                path.nodes[index].ctrl1 = p
                path.nodes[index].ctrl2 = p
            }
        }
    }

    private func appendPathNode(layer: AdjustmentLayer, at p: MaskPoint) {
        // Extend the LAST path form when one exists; otherwise open one.
        if let last = layer.mask?.drawn?.forms.last,
           case var .path(path) = last.kind {
            path.nodes.append(PathNode(corner: p, ctrl1: p, ctrl2: p))
            updatePathForm(id: last.id, layer: layer) { $0 = path }
        } else {
            let path = PathForm(
                nodes: [PathNode(corner: p, ctrl1: p, ctrl2: p)], border: 0)
            _ = appendForm(.path(path), layer: layer)
        }
    }

    // MARK: commit (exactly ONE structure item per finished interaction)

    private func endInteraction() {
        let hadInteraction = grab != nil
        grab = nil
        pressedPoint = nil
        // Exactly ONE structure item per finished, ACTUALLY-MUTATING
        // interaction (「笔画结束 1 条」; a no-op tap never lands history).
        guard hadInteraction, dirty else { return }
        dirty = false
        guard let live = selectedLayer() else { return }
        editorState.commitLayerEdit(
            live, label: String(localized: String.LocalizationValue(commitLabelKey)))
    }

    private func selectedLayer() -> AdjustmentLayer? {
        editingState.selectedLayer(in: editorState.layerStack)
    }

    private var commitLabelKey: String {
        switch editingState.activeTool {
        case .brush, .eraser, nil: return "history_mask_brush"
        case .gradient: return "history_mask_gradient"
        case .ellipse: return "history_mask_ellipse"
        case .path: return "history_mask_path"
        }
    }

    // MARK: mask record plumbing

    /// Append a form to the layer's drawn mask (LIVE leg — zero history)
    /// and return it (the caller grabs its real id).
    @discardableResult
    private func appendForm(_ kind: MaskForm.Kind, layer: AdjustmentLayer) -> MaskForm {
        let form = MaskForm(kind: kind)
        var drawn = layer.mask?.drawn ?? DrawnMaskSpec(forms: [])
        drawn.forms.append(form)
        layer.mask = MaskSpec(drawn: drawn)
        dirty = true
        editorState.applyLiveLayer(layer)
        return form
    }

    /// The LIVE leg: mutate one form by id, zero history.
    private func mutateForm(
        id: UUID, layer: AdjustmentLayer, mutate: (inout MaskForm.Kind) -> Void
    ) {
        guard let live = editorState.adjustmentLayer(id: layer.id),
              var drawn = live.mask?.drawn,
              let index = drawn.forms.firstIndex(where: { $0.id == id })
        else { return }
        mutate(&drawn.forms[index].kind)
        dirty = true
        live.mask = MaskSpec(drawn: drawn)
        editorState.applyLiveLayer(live)
    }

    private func updateStrokeForm(
        id: UUID, layer: AdjustmentLayer, mutate: (inout BrushStroke) -> Void
    ) {
        mutateForm(id: id, layer: layer) { kind in
            if case var .brush(stroke) = kind {
                mutate(&stroke)
                kind = .brush(stroke)
            }
        }
    }

    private func updateGradientForm(
        id: UUID, layer: AdjustmentLayer, mutate: (inout GradientForm) -> Void
    ) {
        mutateForm(id: id, layer: layer) { kind in
            if case var .gradient(g) = kind {
                mutate(&g)
                kind = .gradient(g)
            }
        }
    }

    private func updateEllipseForm(
        id: UUID, layer: AdjustmentLayer, mutate: (inout EllipseForm) -> Void
    ) {
        mutateForm(id: id, layer: layer) { kind in
            if case var .ellipse(e) = kind {
                mutate(&e)
                kind = .ellipse(e)
            }
        }
    }

    private func updatePathForm(
        id: UUID, layer: AdjustmentLayer, mutate: (inout PathForm) -> Void
    ) {
        mutateForm(id: id, layer: layer) { kind in
            if case var .path(p) = kind {
                mutate(&p)
                kind = .path(p)
            }
        }
    }

    // MARK: hit-testing (13-3 T3: SCREEN-space 16px handles)

    /// The handle hit radius in SCREEN points — constant under any
    /// zoom/rotation (the handle DOTS are screen-constant too).
    private static let handleRadius: CGFloat = 16

    private func gradientHandle(
        layer: AdjustmentLayer, screen location: CGPoint, transform xf: ViewportTransform
    ) -> Grab? {
        for form in layer.mask?.drawn?.forms ?? [] {
            if case let .gradient(g) = form.kind {
                if hypot(location.x - xf.point(atUV: g.anchor.asUV).x,
                         location.y - xf.point(atUV: g.anchor.asUV).y)
                    < Self.handleRadius { return .gradientAnchor(form.id) }
                if hypot(location.x - xf.point(atUV: gradientTip(g).asUV).x,
                         location.y - xf.point(atUV: gradientTip(g).asUV).y)
                    < Self.handleRadius { return .gradientTip(form.id) }
            }
        }
        return nil
    }

    private func ellipseHandle(
        layer: AdjustmentLayer, screen location: CGPoint, transform xf: ViewportTransform
    ) -> Grab? {
        for form in layer.mask?.drawn?.forms ?? [] {
            if case let .ellipse(e) = form.kind {
                let rim = MaskPoint(x: e.center.x + e.radiusX, y: e.center.y)
                if hypot(location.x - xf.point(atUV: rim.asUV).x,
                         location.y - xf.point(atUV: rim.asUV).y)
                    < Self.handleRadius { return .ellipseRim(form.id) }
                if hypot(location.x - xf.point(atUV: e.center.asUV).x,
                         location.y - xf.point(atUV: e.center.asUV).y)
                    < Self.handleRadius { return .ellipseCenter(form.id) }
            }
        }
        return nil
    }

    private func nearestPathNode(
        layer: AdjustmentLayer, screen location: CGPoint, transform xf: ViewportTransform
    ) -> (formID: UUID, nodeIndex: Int)? {
        for form in layer.mask?.drawn?.forms ?? [] {
            if case let .path(path) = form.kind {
                for (index, node) in path.nodes.enumerated() {
                    let p = xf.point(atUV: node.corner.asUV)
                    if hypot(location.x - p.x, location.y - p.y) < Self.handleRadius {
                        return (form.id, index)
                    }
                }
            }
        }
        return nil
    }

    // MARK: geometry helpers

    private func gradientTip(_ g: GradientForm) -> MaskPoint {
        // The falloff tip: anchor + the profile direction × compression.
        let angle = Float(Double(g.rotationDegrees) * .pi / 180)
        return MaskPoint(
            x: g.anchor.x + cos(angle) * g.compression,
            y: g.anchor.y + sin(angle) * g.compression)
    }

    private func applyGradientTip(_ g: inout GradientForm, tip: MaskPoint) {
        let dx = tip.x - g.anchor.x, dy = tip.y - g.anchor.y
        g.compression = max(0.001, (dx * dx + dy * dy).squareRoot())
        g.rotationDegrees = Float(atan2(Double(dy), Double(dx)) * 180 / .pi)
    }

    private func distance(_ a: MaskPoint, _ b: MaskPoint) -> Float {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

private extension MaskPoint {
    /// The transform seam (13-3 T3): the drawn payload's normalized pair
    /// rides `ViewportFit`'s SIMD2 uv convention.
    var asUV: SIMD2<Double> { SIMD2(Double(x), Double(y)) }
}

private extension SIMD2<Double> {
    var asMaskPoint: MaskPoint { MaskPoint(x: Float(x), y: Float(y)) }
}
