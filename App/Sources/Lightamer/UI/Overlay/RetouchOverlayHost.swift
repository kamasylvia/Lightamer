import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// RetouchOverlayHost (Plan 06-07 T4) — the viewport stroke editor for the
// SELECTED retouch layer (dt paints retouch strokes directly on the
// canvas; the Cairo machinery stays unported — the SwiftUI overlay redo
// per the LiquifyOverlayHost precedent).
//
// GESTURES (one stroke per gesture — exactly ONE history commit each):
// - drag from empty canvas → a CIRCLE stroke lands at the drag start with
//   the radius = drag distance (clamped ≥ the minimum), carrying the
//   panel-armed algorithm/feather/opacity/params.
// - source pick (clone/heal): with the panel's「拾取源」armed, a TAP
//   samples the source center instead of painting (dt's ctrl-click
//   source pick); the armed flag disarms after one sample. The sampled
//   source renders as a linked crosshair on the NEXT stroke's preview.
// - drag on an existing stroke's anchor → move it (D-H1 live ticks, ONE
//   commit at release); the source link moves WITH the stroke (dt's
//   translation-only source, D-06-07-T1-2).
//
// Coordinates: stroke geometry is stored in FULL-DECODE-FRAME normalized
// coords (the 06-03 mask convention, D-06-CONTEXT-7 content anchoring);
// the overlay v1 maps through the aspect-fit rect directly — the same
// no-active-frame-changing-geometry assumption the liquify overlay
// records (D-06-06-T4-2).
// ─────────────────────────────────────────────────────────────────────────

struct RetouchOverlayHost: View {

    var viewportSize: CGSize
    var displaySize: CGSize
    let layer: RetouchLayer

    @Environment(EditorState.self) private var editorState
    @Environment(LayerEditingState.self) private var editingState

    /// A stroke drag: existing-stroke move vs new-stroke paint.
    @State private var movingStrokeID: UUID?
    @State private var moveStart: SIMD2<Float>?
    @State private var moveSourceStart: SIMD2<Float>?
    @State private var paintStart: SIMD2<Float>?
    @State private var paintRadius: Float = 0

    private var fitted: CGRect {
        ViewportFit.fittedRect(viewportSize: viewportSize, textureSize: displaySize)
    }

    var body: some View {
        if displaySize.width >= 1, displaySize.height >= 1,
           fitted.width >= 1, fitted.height >= 1 {
            ZStack {
                RetouchOverlayCanvas(
                    strokes: layer.strokes,
                    pendingSource: editingState.pendingRetouchSource,
                    armedAlgorithm: editingState.retouchAlgorithm,
                    fitted: fitted)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .onTapGesture(perform: handleTap)
            }
            .accessibilityIdentifier("retouch.overlay")
        }
    }

    // MARK: coordinate mapping

    private func normalized(_ location: CGPoint) -> SIMD2<Float> {
        let nx = (location.x - fitted.minX) / fitted.width
        let ny = (location.y - fitted.minY) / fitted.height
        return SIMD2(
            Float(min(max(nx, 0), 1)),
            Float(min(max(ny, 0), 1)))
    }

    private func point(_ n: SIMD2<Float>) -> CGPoint {
        CGPoint(
            x: fitted.minX + CGFloat(n.x) * fitted.width,
            y: fitted.minY + CGFloat(n.y) * fitted.height)
    }

    // MARK: gestures

    private func handleTap(at location: CGPoint) {
        // Source-pick mode: ONE tap samples, then disarms (dt ctrl-click).
        if editingState.retouchSourcePickArmed,
           editingState.retouchAlgorithm == .clone
            || editingState.retouchAlgorithm == .heal {
            editingState.pendingRetouchSource = normalized(location)
            editingState.retouchSourcePickArmed = false
        }
    }

    private func hitStroke(_ location: CGPoint) -> UUID? {
        let grabRadius: CGFloat = 14
        var best: (id: UUID, distance: CGFloat)?
        for stroke in layer.strokes {
            let anchor = stroke.formAnchorPoint
            let d = hypot(
                location.x - point(anchor).x,
                location.y - point(anchor).y)
            if d <= grabRadius, best == nil || d < best!.distance {
                best = (stroke.id, d)
            }
        }
        return best?.id
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = normalized(value.startLocation)
                let now = normalized(value.location)
                if movingStrokeID == nil && paintStart == nil {
                    if let hit = hitStroke(value.startLocation) {
                        // Move an existing stroke (its source link rides).
                        movingStrokeID = hit
                        moveStart = start
                        moveSourceStart = layer.strokes.first { $0.id == hit }?.source
                            .map { SIMD2($0.x, $0.y) }
                    } else {
                        // Paint a fresh stroke; the radius = drag distance.
                        paintStart = start
                        paintRadius = editingState.retouchRadius
                    }
                }
                if let id = movingStrokeID, let origin = moveStart {
                    let delta = now - origin
                    mutateLive { strokes in
                        guard let index = strokes.firstIndex(where: { $0.id == id })
                        else { return }
                        var stroke = strokes[index]
                        let anchor = stroke.formAnchorPoint
                        stroke = Self.translate(stroke, by: delta)
                        _ = anchor
                        strokes[index] = stroke
                    }
                } else if paintStart != nil {
                    let d = hypot(
                        value.location.x - point(paintStart!).x,
                        value.location.y - point(paintStart!).y)
                    paintRadius = Float(min(
                        max(d / Double(fitted.width), 0.01), 0.3))
                }
            }
            .onEnded { value in
                if movingStrokeID != nil {
                    movingStrokeID = nil
                    moveStart = nil
                    // ONE commit: the CURRENT live strokes verbatim.
                    commit(String(localized: "history_retouch_stroke"))
                } else if let start = paintStart {
                    paintStart = nil
                    paintRadius = 0
                    let algorithm = editingState.retouchAlgorithm
                    let needsSource = algorithm == .clone || algorithm == .heal
                    let sourceCenter: SIMD2<Float>? = needsSource
                        ? (editingState.pendingRetouchSource ?? start)
                        : nil
                    // The drag refines the circle radius; the stroke lands
                    // at release (one gesture = one stroke = one commit).
                    let radius = max(paintRadiusFrom(value, start: start), 0.01)
                    let stroke = RetouchStroke(
                        algorithm: algorithm,
                        form: MaskForm(kind: .ellipse(EllipseForm(
                            center: MaskPoint(x: start.x, y: start.y),
                            radiusX: radius, radiusY: radius,
                            rotationDegrees: 0,
                            border: editingState.retouchFeather))),
                        source: sourceCenter.map { MaskPoint(x: $0.x, y: $0.y) },
                        opacity: editingState.retouchStrokeOpacity,
                        blurRadius: algorithm == .blur
                            ? editingState.retouchBlurRadius : nil,
                        fillColor: algorithm == .fill
                            ? editingState.retouchFillColor : nil)
                    commitNewStroke(stroke)
                }
            }
    }

    /// The painted circle's radius: the drag distance in normalized width
    /// units, clamped to the usable band.
    private func paintRadiusFrom(_ value: DragGesture.Value, start: SIMD2<Float>) -> Float {
        let d = hypot(
            value.location.x - point(start).x,
            value.location.y - point(start).y)
        return Float(min(max(d / Double(fitted.width), 0.01), 0.3))
    }

    /// Translation-only stroke move (the source link rides the same delta —
    /// dt's translated source form, D-06-07-T1-2).
    private static func translate(
        _ stroke: RetouchStroke, by delta: SIMD2<Float>
    ) -> RetouchStroke {
        var copy = stroke
        if let source = copy.source {
            copy.source = MaskPoint(x: source.x + delta.x, y: source.y + delta.y)
        }
        switch copy.form.kind {
        case var .ellipse(e):
            e.center = MaskPoint(x: e.center.x + delta.x, y: e.center.y + delta.y)
            copy.form.kind = .ellipse(e)
        case var .path(p):
            for index in p.nodes.indices {
                p.nodes[index].corner = MaskPoint(
                    x: p.nodes[index].corner.x + delta.x,
                    y: p.nodes[index].corner.y + delta.y)
                p.nodes[index].ctrl1 = MaskPoint(
                    x: p.nodes[index].ctrl1.x + delta.x,
                    y: p.nodes[index].ctrl1.y + delta.y)
                p.nodes[index].ctrl2 = MaskPoint(
                    x: p.nodes[index].ctrl2.x + delta.x,
                    y: p.nodes[index].ctrl2.y + delta.y)
            }
            copy.form.kind = .path(p)
        case .brush, .gradient: break
        }
        return copy
    }

    // MARK: EditorState plumbing

    /// Live-tick the stroke list (zero history).
    private func mutateLive(_ mutate: (inout [RetouchStroke]) -> Void) {
        var strokes = layer.strokes
        mutate(&strokes)
        let updated = RetouchLayer(
            id: layer.id, name: layer.name, isVisible: layer.isVisible,
            opacity: layer.opacity, blendMode: layer.blendMode,
            blendOptions: layer.blendOptions, enabled: layer.enabled,
            strokes: strokes)
        editorState.applyLiveRetouch(updated)
    }

    /// ONE commit of the CURRENT live strokes (a move's release).
    private func commit(_ label: String) {
        guard let live = editorState.retouchLayer(id: layer.id) else { return }
        editorState.commitRetouchEdit(live, label: label)
    }

    /// ONE commit appending a fresh stroke (a paint's release).
    private func commitNewStroke(_ stroke: RetouchStroke) {
        let updated = RetouchLayer(
            id: layer.id, name: layer.name, isVisible: layer.isVisible,
            opacity: layer.opacity, blendMode: layer.blendMode,
            blendOptions: layer.blendOptions, enabled: layer.enabled,
            strokes: layer.strokes + [stroke])
        editorState.commitRetouchEdit(
            updated, label: String(localized: "history_retouch_stroke"))
    }
}

/// The stroke rendering (Canvas — draw-only): circles/paths as outlines,
/// the armed algorithm glyph at each anchor, and the pending source
/// crosshair with its link line.
private struct RetouchOverlayCanvas: View {
    let strokes: [RetouchStroke]
    let pendingSource: SIMD2<Float>?
    let armedAlgorithm: RetouchAlgorithm
    let fitted: CGRect

    var body: some View {
        Canvas { context, _ in
            let p: (SIMD2<Float>) -> CGPoint = { n in
                CGPoint(
                    x: fitted.minX + CGFloat(n.x) * fitted.width,
                    y: fitted.minY + CGFloat(n.y) * fitted.height)
            }
            for stroke in strokes {
                let anchor = stroke.formAnchorPoint
                if let source = stroke.source {
                    // The source link: a thin line + crosshair (dt shows
                    // the clone source the same way).
                    var link = Path()
                    link.move(to: p(anchor))
                    link.addLine(to: p(SIMD2(source.x, source.y)))
                    context.stroke(
                        link, with: .color(.cyan.opacity(0.7)),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    crosshair(&context, at: p(SIMD2(source.x, source.y)))
                }
                let strokeColor: Color = switch stroke.algorithm {
                case .clone: .cyan
                case .heal: .green
                case .blur: .orange
                case .fill: .pink
                }
                switch stroke.form.kind {
                case let .ellipse(e):
                    let center = p(SIMD2(e.center.x, e.center.y))
                    let rx = CGFloat(e.radiusX) * fitted.width
                    let ry = CGFloat(e.radiusY) * fitted.height
                    let rect = CGRect(
                        x: center.x - rx, y: center.y - ry,
                        width: rx * 2, height: ry * 2)
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(strokeColor.opacity(0.9)), lineWidth: 1.5)
                case let .path(pathForm):
                    var path = Path()
                    for (index, node) in pathForm.nodes.enumerated() {
                        let pt = p(SIMD2(node.corner.x, node.corner.y))
                        if index == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    path.closeSubpath()
                    context.stroke(
                        path, with: .color(strokeColor.opacity(0.9)), lineWidth: 1.5)
                case .brush, .gradient: break
                }
            }
            // The pending source crosshair (armed pick result, not yet painted).
            if let source = pendingSource {
                crosshair(&context, at: p(source))
            }
        }
        .allowsHitTesting(false)
    }

    private func crosshair(_ context: inout GraphicsContext, at point: CGPoint) {
        var x = Path()
        x.move(to: CGPoint(x: point.x - 5, y: point.y))
        x.addLine(to: CGPoint(x: point.x + 5, y: point.y))
        var y = Path()
        y.move(to: CGPoint(x: point.x, y: point.y - 5))
        y.addLine(to: CGPoint(x: point.x, y: point.y + 5))
        context.stroke(x, with: .color(.cyan), lineWidth: 1)
        context.stroke(y, with: .color(.cyan), lineWidth: 1)
    }
}
