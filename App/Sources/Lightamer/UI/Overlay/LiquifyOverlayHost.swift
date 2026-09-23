import LightamerCore
import LightamerIOP
import simd
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// LiquifyOverlayHost (Plan 06-06-T4) — the viewport node editor for the
// liquify warp. dt's Cairo layer/hit-test machinery (liquify.c:97-204) is
// NOT ported; this is a SwiftUI overlay redo per the plan.
//
// SEMANTICS:
// - Each path node renders as an anchor dot, a strength handle (the vector
//   `strength − point`, dt's push direction) and a radius handle (the
//   effective radius scalar `|radius − point|`). Interpolated path chains
//   (MOVE→LINE/CURVE) render as the polyline between node anchors.
// - Drag hit-tests the nearest handle (anchor / strength / radius) within
//   the grab radius and drives the D-H1 trio: drag begin → onBegin, live
//   ticks → onLive (PREVIEW re-render, 0 history), release → onCommit
//   (exactly ONE history item).
// - Coordinates: node geometry is stored as fractions of the entry frame
//   (D-06-06-T1-1); the overlay maps them through the aspect-fit rect —
//   v1 assumes no active upstream frame-changing geometry (the common
//   portrait-liquefy path); recorded as DECISIONS D-06-06-T4-2.
// - Mutual exclusion with the crop overlay is the CALLER's business (the
//   EditorAreaView mounts either the crop or the liquify overlay, keyed on
//   the selected Inspector panel).
// ─────────────────────────────────────────────────────────────────────────

/// What a drag grabbed (the node index + which handle).
enum LiquifyDragTarget: Equatable {
    case anchor(Int)
    case strength(Int)
    case radius(Int)
}

struct LiquifyOverlayHost: View {

    var viewportSize: CGSize
    var displaySize: CGSize
    var liquifyRecord: ModuleInstance?

    /// D-H1 trio callbacks (the CropOverlayHost pattern — the host owns the
    /// record decode + snapshot encode, the caller owns the coordinator).
    var onBegin: () -> Void = {}
    var onLive: (ModuleInstance) -> Void = { _ in }
    var onCommit: (ModuleInstance, String) -> Void = { _, _ in }

    @State private var dragTarget: LiquifyDragTarget?

    private var params: LiquifyModule.Params? {
        liquifyRecord.flatMap { try? $0.params(of: LiquifyModule.self) }
    }

    var body: some View {
        if let record = liquifyRecord,
           let params,
           displaySize.width >= 1, displaySize.height >= 1 {
            let fitted = ViewportFit.fittedRect(
                viewportSize: viewportSize,
                textureSize: displaySize)
            if fitted.width >= 1, fitted.height >= 1 {
                ZStack {
                    LiquifyOverlayCanvas(
                        params: params,
                        fitted: fitted,
                        dragTarget: dragTarget)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragGesture(record: record, fitted: fitted))
                        .onTapGesture(perform: { location in
                            tapToAdd(at: location, record: record, fitted: fitted)
                        })
                }
                .accessibilityIdentifier("liquify.overlay")
            }
        }
    }

    // MARK: coordinate mapping (normalized ↔ viewport points)

    private func point(_ n: SIMD2<Float>, _ fitted: CGRect) -> CGPoint {
        CGPoint(
            x: fitted.minX + CGFloat(n.x) * fitted.width,
            y: fitted.minY + CGFloat(n.y) * fitted.height)
    }

    private func normalized(_ location: CGPoint, _ fitted: CGRect) -> SIMD2<Float> {
        let nx = (location.x - fitted.minX) / fitted.width
        let ny = (location.y - fitted.minY) / fitted.height
        return SIMD2(Float(min(max(nx, 0), 1)), Float(min(max(ny, 0), 1)))
    }

    // MARK: hit-testing

    private func hitTest(
        _ location: CGPoint, params: LiquifyModule.Params, fitted: CGRect
    ) -> LiquifyDragTarget? {
        let grabRadius: CGFloat = 16
        var best: (target: LiquifyDragTarget, distance: CGFloat)?
        func consider(_ target: LiquifyDragTarget, _ p: CGPoint) {
            let d = hypot(location.x - p.x, location.y - p.y)
            if d <= grabRadius, best == nil || d < best!.distance {
                best = (target, d)
            }
        }
        for (index, node) in params.paths.enumerated() {
            consider(.strength(index), point(node.strength, fitted))
            consider(.radius(index), point(node.radius, fitted))
            consider(.anchor(index), point(node.point, fitted))
        }
        return best?.target
    }

    // MARK: gestures

    private func dragGesture(record: ModuleInstance, fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragTarget == nil {
                    guard let params else { return }
                    dragTarget = hitTest(value.startLocation, params: params, fitted: fitted)
                    if dragTarget != nil { onBegin() }
                }
                guard let target = dragTarget,
                      var current = try? record.params(of: LiquifyModule.self)
                else { return }
                let n = normalized(value.location, fitted)
                switch target {
                case .anchor(let index) where current.paths.indices.contains(index):
                    current.paths[index].point = n
                case .strength(let index) where current.paths.indices.contains(index):
                    current.paths[index].strength = n
                case .radius(let index) where current.paths.indices.contains(index):
                    current.paths[index].radius = n
                default:
                    return
                }
                if let snapshot = Self.snapshot(from: record, params: current) {
                    onLive(snapshot)
                }
            }
            .onEnded { _ in
                guard let target = dragTarget else { return }
                dragTarget = nil
                guard var current = try? record.params(of: LiquifyModule.self) else { return }
                // Re-apply the final tick position (the live record already
                // carries it — commit the CURRENT state verbatim).
                _ = target
                if let snapshot = Self.snapshot(from: record, params: current) {
                    onCommit(snapshot, String(localized: "history_liquify"))
                }
            }
    }

    /// Tap on empty canvas adds a first node at the tap point (the overlay's
    /// counterpart to the panel's add button).
    private func tapToAdd(at location: CGPoint, record: ModuleInstance, fitted: CGRect) {
        guard var current = try? record.params(of: LiquifyModule.self) else { return }
        guard current.paths.count < LiquifyPathData.maxNodes else { return }
        var node = LiquifyPathData.moveTo(normalized(location, fitted), warpType: .radialGrow)
        node.radius = node.point + SIMD2<Float>(0.1, 0)
        current.paths.append(node)
        if let snapshot = Self.snapshot(from: record, params: current) {
            onBegin()
            onCommit(snapshot, String(localized: "history_liquify"))
        }
    }

    /// Same-UUID re-encode (the D-H4 hash flips through setParams).
    static func snapshot(
        from record: ModuleInstance, params: LiquifyModule.Params
    ) -> ModuleInstance? {
        var snapshot = record
        do {
            try snapshot.setParams(params, as: LiquifyModule.self)
            return snapshot
        } catch {
            return nil
        }
    }
}

/// The node/handle rendering (Canvas — draw-only, no hit testing).
private struct LiquifyOverlayCanvas: View {
    let params: LiquifyModule.Params
    let fitted: CGRect
    let dragTarget: LiquifyDragTarget?

    var body: some View {
        Canvas { context, _ in
            let p: (SIMD2<Float>) -> CGPoint = { n in
                CGPoint(
                    x: fitted.minX + CGFloat(n.x) * fitted.width,
                    y: fitted.minY + CGFloat(n.y) * fitted.height)
            }
            // Subpath polylines: MOVE anchors connect to their LINE/CURVE
            // successors (draw-only — the v1 renderer draws every node type
            // identically, D-06-06-T1-2 note).
            var path = Path()
            for (index, node) in params.paths.enumerated() {
                if node.type == .moveTo {
                    path.move(to: p(node.point))
                } else if index > 0 {
                    path.addLine(to: p(node.point))
                }
                // strength vector
                var arrow = Path()
                arrow.move(to: p(node.point))
                arrow.addLine(to: p(node.strength))
                context.stroke(arrow, with: .color(.orange), lineWidth: 1.5)
                // radius circle
                let rd = node.radius - node.point
                let r = CGFloat((rd.x * rd.x + rd.y * rd.y).squareRoot())
                    * max(fitted.width, fitted.height)
                let radiusCircle = Path(
                    ellipseIn: CGRect(
                        x: p(node.point).x - r, y: p(node.point).y - r,
                        width: 2 * r, height: 2 * r))
                context.stroke(radiusCircle, with: .color(.orange.opacity(0.5)), lineWidth: 1)
            }
            context.stroke(path, with: .color(.orange.opacity(0.8)), lineWidth: 1.5)

            // handles
            for (index, node) in params.paths.enumerated() {
                let selected = dragTarget.map { target in
                    switch target {
                    case .anchor(let i): return i == index
                    case .strength(let i): return i == index
                    case .radius(let i): return i == index
                    }
                } ?? false
                for (n, filled) in [(node.point, true), (node.strength, false), (node.radius, false)] {
                    let pt = p(n)
                    let radius: CGFloat = filled ? 5 : 4
                    let rect = CGRect(x: pt.x - radius, y: pt.y - radius,
                                      width: 2 * radius, height: 2 * radius)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(filled || selected ? .orange : .white))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
