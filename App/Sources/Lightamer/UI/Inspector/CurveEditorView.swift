import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// CurveEditorView (Plan 03-03-T3 action 5) — the D-T6 curve control slot:
// a MINIMAL node editor for the tonecurve iop.
//
// Scope (plan: "5 节点最小版"): drags the EXISTING nodes (x clamped
// between the neighbors, y clamped to [0,1]), draws the live LUT curve
// through `ToneCurveLUT` (the same CPU path the pipe consumes — the
// displayed curve IS the applied curve). Node add/remove, per-node read
//outs, log scales and the three interpolator switches are Phase 4+
// refinements; the monotone Hermite interpolator ships first.
//
// D-H1 wiring: drag begin → onDragBegin (beginContinuousEdit); per-tick
// → onNodesChanged (setLiveParams, 0 history); drag end → onDragEnd
// (exactly ONE commit). The view is stateless about history — it only
// emits node sets.
// ─────────────────────────────────────────────────────────────────────────

internal struct CurveEditorView: View {

    let nodes: [ToneCurveModule.Node]
    let curveType: ToneCurveLUT.CurveType
    let onDragBegin: () -> Void
    let onNodesChanged: ([ToneCurveModule.Node]) -> Void
    let onDragEnd: () -> Void

    @State private var dragStarted = false

    /// Preview sample count (the LUT itself stays 65536 — this is display).
    private static let previewSamples = 128

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Canvas { context, canvasSize in
                    drawGrid(context, canvasSize)
                    drawCurve(context, canvasSize)
                }
                .frame(width: size, height: size)
                .gesture(dragGesture(size: CGSize(width: size, height: size)))
                ForEach(nodes.indices, id: \.self) { i in
                    nodeHandle(index: i, size: CGSize(width: size, height: size))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(LightamerColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("inspector.curveeditor")
    }

    // MARK: Drawing

    private func drawGrid(_ context: GraphicsContext, _ size: CGSize) {
        var path = Path()
        for i in 0...4 {
            let t = CGFloat(i) / 4
            path.move(to: CGPoint(x: t * size.width, y: 0))
            path.addLine(to: CGPoint(x: t * size.width, y: size.height))
            path.move(to: CGPoint(x: 0, y: t * size.height))
            path.addLine(to: CGPoint(x: size.width, y: t * size.height))
        }
        context.stroke(path, with: .color(LightamerColors.border.opacity(0.4)), lineWidth: 1)

        // identity diagonal
        var diagonal = Path()
        diagonal.move(to: CGPoint(x: 0, y: size.height))
        diagonal.addLine(to: CGPoint(x: size.width, y: 0))
        context.stroke(
            diagonal, with: .color(LightamerColors.textTertiary.opacity(0.35)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
        )
    }

    /// The preview curve samples the REAL CPU LUT build (ToneCurveLUT) —
    /// display and pipeline share one implementation.
    private func drawCurve(_ context: GraphicsContext, _ size: CGSize) {
        let nodesD = nodes.map { (x: Double($0.x), y: Double($0.y)) }
        let table = ToneCurveLUT.buildTable(nodes: nodesD, type: curveType)
        var path = Path()
        let n = Self.previewSamples
        for i in 0...n {
            let t = Double(i) / Double(n)
            let idx = min(Int(t * Double(ToneCurveLUT.resolution - 1) + 0.5), ToneCurveLUT.resolution - 1)
            let v = table[idx]
            let point = CGPoint(
                x: CGFloat(t) * size.width,
                y: (1 - CGFloat(v)) * size.height
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(LightamerColors.accent), lineWidth: 1.5)
    }

    private func nodeHandle(index: Int, size: CGSize) -> some View {
        let node = nodes[index]
        return Circle()
            .fill(LightamerColors.accent)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(LightamerColors.surface, lineWidth: 1.5))
            .position(
                x: CGFloat(node.x) * size.width,
                y: (1 - CGFloat(node.y)) * size.height
            )
            .accessibilityIdentifier("inspector.curveeditor.node\(index)")
    }

    // MARK: Dragging

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !dragStarted {
                    dragStarted = true
                    onDragBegin()
                }
                guard !nodes.isEmpty else { return }
                let px = min(max(value.location.x / size.width, 0), 1)
                let py = min(max(1 - value.location.y / size.height, 0), 1)
                moveNode(nearestNode(px: Double(px), py: Double(py)), px: px, py: py)
            }
            .onEnded { _ in
                if dragStarted {
                    dragStarted = false
                    onDragEnd()
                }
            }
    }

    private func nearestNode(px: Double, py: Double) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (i, node) in nodes.enumerated() {
            let dx = Double(node.x) - px
            let dy = Double(node.y) - py
            let d = dx * dx + dy * dy
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        return best
    }

    private func moveNode(_ index: Int, px: Double, py: Double) {
        var updated = nodes
        let minX: Float = index == 0 ? 0 : updated[index - 1].x + 0.01
        let maxX: Float = index == nodes.count - 1 ? 1 : updated[index + 1].x - 0.01
        updated[index].x = min(max(Float(px), minX), maxX)
        updated[index].y = min(max(Float(py), 0), 1)
        onNodesChanged(updated)
    }
}
