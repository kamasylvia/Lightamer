import LightamerCore
import LightamerIOP
import simd
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// UprightGuidesOverlay (Plan M9-3-T4, M9GEO-02) — the Guided Upright
// guide-drawing surface, in the upstream tests_guided_guides semantics
// (fbc927f0 / 7635b38c):
//   • a drag press STARTS a new guide at the press point (no drag needed);
//   • dragging near an ENDPOINT moves that endpoint (the other end and the
//     other guides untouched);
//   • a click near a line SELECTS it (drawn white/bold — the UI-only
//     selection, never persisted; the upstream serde-skip semantics — the
//     selection lives in InspectorState's session face, NOT in
//     upright.Params);
//   • a click on blank space (no endpoint, no line) CLEARS the selection;
//   • Delete removes ONLY the selected guide (with no selection it is a
//     no-op: no guide, no history item);
//   • at most 4 guides (the 5th draw is refused).
// Guides persist in `upright.Params.guides` — ONE history item per edit
// step (the upstream undo granularity); a draw/endpoint drag is the D-H1
// trio (begin → live ticks stream the pending guides; the commit lands
// once at release). Coordinates live in the upright op's INPUT frame
// (normalized 0..1) and reach the viewport ONLY through GeometryPointMapper
// (CONTEXT red line 6 — the single mapping channel; the host injects the
// mapper legs).
// ─────────────────────────────────────────────────────────────────────────

/// The guides interaction state machine (pure logic; unit-testable without
/// SwiftUI — the upstream tests_guided_guides faces in-process).
struct UprightGuidesModel: Equatable {

    /// The persisted guides (normalized upright-input-frame 0..1).
    var guides: [UprightModule.Guide]
    /// The selected guide index — UI-ONLY (never enters params/sidecar).
    var selected: Int? = nil
    /// The in-flight drawn guide (press → drag → release).
    var pending: UprightModule.Guide? = nil
    /// The in-flight endpoint drag (guide index + which end: 0 = a, 1 = b).
    var dragging: DragTarget? = nil

    /// The drag target (a struct — tuples carry no Equatable synthesis).
    struct DragTarget: Equatable, Sendable {
        var index: Int
        var end: Int
    }

    static let maxGuides = 4
    /// Hit tolerances in normalized units (≈ 2% of the frame).
    static let endpointRadius: Double = 0.02
    static let lineHitDistance: Double = 0.02

    init(guides: [UprightModule.Guide] = []) {
        self.guides = guides
    }

    /// Clamp a point into the 0..1 frame.
    static func clamped(_ p: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(min(max(p.x, 0), 1), min(max(p.y, 0), 1))
    }

    /// Distance from a point to a segment (normalized units; scalar math —
    /// no SIMD operator dependence).
    static func distanceToSegment(
        _ p: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>
    ) -> Double {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let len2 = abx * abx + aby * aby
        if len2 < 1e-12 {
            let dx = p.x - a.x
            let dy = p.y - a.y
            return (dx * dx + dy * dy).squareRoot()
        }
        let t = min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / len2, 0), 1)
        let dx = p.x - (a.x + abx * t)
        let dy = p.y - (a.y + aby * t)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - drawing (a drag press starts a new guide at the press point)

    /// A press: near an endpoint? → grab it (drag; the guide becomes
    /// selected). Near a line? → select it. Otherwise → start a new guide
    /// at the press point (clears the selection first — the upstream
    /// ordering; the 5th draw is refused — `false`).
    @discardableResult
    mutating func press(at pRaw: SIMD2<Double>) -> Bool {
        let p = Self.clamped(pRaw)
        if let hit = endpointHit(at: p) {
            dragging = hit
            selected = hit.index
            pending = nil
            return true
        }
        if let line = lineHit(at: p) {
            selected = line
            pending = nil
            dragging = nil
            return true
        }
        selected = nil
        dragging = nil
        guard guides.count < Self.maxGuides else { return false }
        pending = UprightModule.Guide(ax: p.x, ay: p.y, bx: p.x, by: p.y)
        return true
    }

    /// A drag tick: the pending guide's far end follows the pointer, or the
    /// grabbed endpoint follows while the other end stays put.
    mutating func dragTick(at pRaw: SIMD2<Double>) {
        let p = Self.clamped(pRaw)
        if var draw = pending {
            draw.bx = p.x
            draw.by = p.y
            pending = draw
        } else if let drag = dragging, drag.index < guides.count {
            var g = guides[drag.index]
            if drag.end == 0 {
                g.ax = p.x
                g.ay = p.y
            } else {
                g.bx = p.x
                g.by = p.y
            }
            guides[drag.index] = g
        }
    }

    /// Release: commit the pending guide into the list (the caller turns
    /// the whole list into the ONE history item). A zero-length press (no
    /// drag) is NOT a guide. Returns whether the list changed.
    @discardableResult
    mutating func release() -> Bool {
        dragging = nil
        if let draw = pending {
            pending = nil
            let dx = draw.bx - draw.ax
            let dy = draw.by - draw.ay
            guard dx * dx + dy * dy > 1e-12 else { return false }
            guides.append(draw)
            return true
        }
        return false
    }

    // MARK: - selection (UI-only) + delete

    /// A hit test for the endpoint ring (the drag target).
    func endpointHit(at p: SIMD2<Double>) -> DragTarget? {
        for (i, g) in guides.enumerated() {
            let dax = p.x - g.ax
            let day = p.y - g.ay
            if (dax * dax + day * day).squareRoot() <= Self.endpointRadius {
                return DragTarget(index: i, end: 0)
            }
            let dbx = p.x - g.bx
            let dby = p.y - g.by
            if (dbx * dbx + dby * dby).squareRoot() <= Self.endpointRadius {
                return DragTarget(index: i, end: 1)
            }
        }
        return nil
    }

    /// A hit test for the line body (the selection target).
    func lineHit(at p: SIMD2<Double>) -> Int? {
        for (i, g) in guides.enumerated() {
            let d = Self.distanceToSegment(p, SIMD2(g.ax, g.ay), SIMD2(g.bx, g.by))
            if d <= Self.lineHitDistance { return i }
        }
        return nil
    }

    /// Delete the selected guide. With no selection this is a NO-OP —
    /// `false`, no guide removed, no history item (the upstream
    /// "never the photo" face).
    @discardableResult
    mutating func deleteSelected() -> Bool {
        guard let index = selected, index < guides.count else { return false }
        guides.remove(at: index)
        selected = nil
        return true
    }

    /// Leave the tool (blank-space semantics: clear the transient faces).
    mutating func leave() {
        selected = nil
        pending = nil
        dragging = nil
    }
}

/// The overlay view: draws the guides + endpoints over the fitted image
/// rect; the drag face streams through the D-H1 trio, the click face
/// selects (the host persists the selection in the session face). Pure
/// function of (fittedRect, guides, selected, pending).
struct UprightGuidesOverlayView: View {

    let fittedRect: CGRect
    /// The live guides (the committed params' list — the host's truth).
    var guides: [UprightModule.Guide]
    /// The session selection (UI-only).
    var selected: Int?
    var onBegin: () -> Void = {}
    /// Live ticks carry the FULL guides list (pending included) — the host
    /// turns them into the upright live instance.
    var onLive: ([UprightModule.Guide]) -> Void = { _ in }
    /// The release commit (the list including the new guide; the host
    /// commits ONE history item).
    var onCommit: ([UprightModule.Guide]) -> Void = { _ in }
    /// The selection moved (the host writes the session face).
    var onSelect: (Int?) -> Void = { _ in }

    /// The drag face's working copy (nil = no active drag).
    @State private var dragModel: UprightGuidesModel?

    var body: some View {
        GeometryReader { _ in
            ZStack {
                guidesCanvas
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityIdentifier("upright.guides.overlay")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragModel == nil {
                            var m = UprightGuidesModel(guides: guides)
                            m.selected = selected
                            m.press(at: viewportToFrame(value.startLocation))
                            dragModel = m
                            onBegin()
                            onLive(m.guides + (m.pending.map { [$0] } ?? []))
                        } else {
                            dragModel?.dragTick(at: viewportToFrame(value.location))
                            if let m = dragModel {
                                onLive(m.guides + (m.pending.map { [$0] } ?? []))
                            }
                        }
                    }
                    .onEnded { _ in
                        guard var m = dragModel else { return }
                        let changed = m.release()
                        dragModel = nil
                        if changed {
                            onCommit(m.guides)
                        }
                    }
            )
            .onTapGesture { location in
                // the selection face (a click is not a drag): near-line
                // selects (toggle), blank clears — UI-only, no history.
                let p = viewportToFrame(location)
                var m = UprightGuidesModel(guides: guides)
                m.selected = selected
                if m.endpointHit(at: p) == nil {
                    if let line = m.lineHit(at: p) {
                        onSelect(selected == line ? nil : line)
                    } else {
                        onSelect(nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var guidesCanvas: some View {
        let live = dragModel
        let all = live.map { $0.guides + ($0.pending.map { [$0] } ?? []) } ?? guides
        ForEach(Array(all.enumerated()), id: \.offset) { index, guide in
            let isSelected = (live?.selected ?? selected) == index
            let start = frameToViewport(SIMD2(guide.ax, guide.ay))
            let end = frameToViewport(SIMD2(guide.bx, guide.by))
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(
                isSelected ? Color.white : Color.white.opacity(0.7),
                style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, lineCap: .round))
            .allowsHitTesting(false)
            Circle()
                .fill(Color.white)
                .frame(width: isSelected ? 12 : 9, height: isSelected ? 12 : 9)
                .position(start)
                .allowsHitTesting(false)
            Circle()
                .fill(Color.white)
                .frame(width: isSelected ? 12 : 9, height: isSelected ? 12 : 9)
                .position(end)
                .allowsHitTesting(false)
        }
    }

    // MARK: - coordinate conversion (frame 0..1 ↔ viewport points)

    private func frameToViewport(_ p: SIMD2<Double>) -> CGPoint {
        CGPoint(
            x: fittedRect.minX + CGFloat(p.x) * fittedRect.width,
            y: fittedRect.minY + CGFloat(p.y) * fittedRect.height)
    }

    private func viewportToFrame(_ point: CGPoint) -> SIMD2<Double> {
        guard fittedRect.width >= 1, fittedRect.height >= 1 else { return SIMD2(0, 0) }
        return SIMD2(
            Double((point.x - fittedRect.minX) / fittedRect.width),
            Double((point.y - fittedRect.minY) / fittedRect.height))
    }
}

/// The tool window's host bridge (the CropOverlayHost shape): the mapper
/// legs (viewport ⇄ upright-input-frame, the ONLY channel), the D-H1
/// wiring (live ticks → the upright live instance; the release commit →
/// ONE history item), the Delete-key face, and the Done disarm.
struct UprightGuidesToolHost: View {

    let viewportSize: CGSize
    let displaySize: CGSize

    @Environment(EditorState.self) private var editorState
    @Environment(InspectorState.self) private var inspectorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    var body: some View {
        let fitted = ViewportFit.fittedRect(viewportSize: viewportSize, textureSize: displaySize)
        if fitted.width >= 1, fitted.height >= 1,
            let uprightRecord = editorState.instances.first(where: { $0.opName == UprightModule.opName })
        {
            // The ONLY coordinate channel (CONTEXT red line 6): the guides
            // persist in the upright INPUT frame; the overlay draws in the
            // DISPLAY frame — every crossing goes through the mapper
            // (the post-upright display leg: forward draws stored guides
            // where the user sees them, inverse stores what they drew).
            let mapper = pipeCoordinator.uprightGuideMapper()
            let guides = (try? uprightRecord.params(of: UprightModule.self))?.guides ?? []
            let displayGuides = guides.map { Self.mapGuide($0, mapper?.forward(normalized:)) }
            UprightGuidesOverlayView(
                fittedRect: fitted,
                guides: displayGuides,
                selected: inspectorState.uprightGuideSelected,
                onBegin: {
                    pipeCoordinator.beginContinuousEdit()
                },
                onLive: { liveGuides in
                    if var params = try? uprightRecord.params(of: UprightModule.self) {
                        params.guides = liveGuides.map { Self.mapGuide($0, mapper?.inverse(normalized:)) }
                        var snapshot = uprightRecord
                        try? snapshot.setParams(params, as: UprightModule.self)
                        Task { await pipeCoordinator.setLiveParams(snapshot) }
                    }
                },
                onCommit: { finalGuides in
                    if var params = try? uprightRecord.params(of: UprightModule.self) {
                        params.guides = finalGuides.map { Self.mapGuide($0, mapper?.inverse(normalized:)) }
                        var snapshot = uprightRecord
                        try? snapshot.setParams(params, as: UprightModule.self)
                        pipeCoordinator.commitLinkedSnapshots(
                            [snapshot], label: String(localized: "history_upright_guides"))
                    }
                },
                onSelect: { index in
                    inspectorState.uprightGuideSelected = index
                }
            )
            .overlay(alignment: .topTrailing) {
                Button(String(localized: "upright_tool_done")) {
                    inspectorState.closeUprightGuidesTool()
                }
                .padding(12)
                .accessibilityIdentifier("upright.tool.done")
            }
            .onTapGesture { _ in }
        }
    }

    /// One-guide endpoint remap through an optional normalized↔normalized
    /// mapper leg (nil = identity — the neutral base chain).
    static func mapGuide(
        _ g: UprightModule.Guide, _ leg: ((SIMD2<Double>) -> SIMD2<Double>)?
    ) -> UprightModule.Guide {
        guard let leg else { return g }
        let a = leg(SIMD2(g.ax, g.ay))
        let b = leg(SIMD2(g.bx, g.by))
        return UprightModule.Guide(ax: a.x, ay: a.y, bx: b.x, by: b.y)
    }

    /// The keyboard-Delete face (the panel's Delete button routes here in
    /// the walkthrough; the key hook rides the tool window's focus).
    func deleteSelectedGuide(uprightRecord: ModuleInstance) {
        var model = UprightGuidesModel(
            guides: (try? uprightRecord.params(of: UprightModule.self))?.guides ?? [])
        model.selected = inspectorState.uprightGuideSelected
        guard model.deleteSelected() else { return }  // no selection = no-op
        inspectorState.uprightGuideSelected = nil
        if var params = try? uprightRecord.params(of: UprightModule.self) {
            params.guides = model.guides
            var snapshot = uprightRecord
            try? snapshot.setParams(params, as: UprightModule.self)
            pipeCoordinator.commitLinkedSnapshots(
                [snapshot], label: String(localized: "history_upright_guides"))
        }
    }
}
