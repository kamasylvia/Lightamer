import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// SegmentEditingOverlayHost (Plan 07-3 T2) — the tap-to-segment viewport
// interaction, the 4TH editing mode (LayerEditingState's `.segment`
// route; mutex with mask-drawing / liquify / retouch / crop by the
// machine's if/else-if chain).
//
// GESTURES (D-07-CONTEXT-4 v1 scope — scribble/lasso deferred, the seed
// enum's `.scribble` case is the recorded upgrade seam):
//   click            → seed point (first) / INCLUDED refine point (after)
//   ⌥-click          → EXCLUDED refine point (after a seed exists)
//   ⇧-drag           → seed box (replaces the seed, clears the points)
//   confirm button   → run `AIMaskService.segmentSubject` (background) →
//                      bake → the selected layer's mask slot — exactly ONE
//                      stackSnapshot commit per confirm (the refine path
//                      re-bakes the SAME maskID, D-07-CONTEXT-5).
//
// VISUALS: included points (accent dots), excluded points (orange dots),
// the pending seed box (dashed rect), and the point-counter badge
// (used/13 or /11 — full → the counter turns red and further points are
// refused through SegmentSession's typed throw, surfaced as a hint).
//
// COORDINATES: the overlay records VIEW-normalized (top-left) points —
// the Vision Y-flip happens ONLY at `AIMaskPoint.visionPoint` (the single
// seam; the wiring test pins the flipped vector the service receives).
// ─────────────────────────────────────────────────────────────────────────

internal struct SegmentEditingOverlayHost: View {

    var viewportSize: CGSize
    var displaySize: CGSize
    let metalContext: MetalContext?

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator
    @Environment(LayerEditingState.self) private var editingState
    /// 13-3 T3: the segment route is NOT in the zoom-lock set, so its taps
    /// inverse-map through the transform (the same single math source the
    /// mask brush uses).
    @Environment(ViewportState.self) private var viewportState

    /// The pending ⇧-box drag (start → current, normalized).
    @State private var boxDraft: (start: SIMD2<Float>, current: SIMD2<Float>)?
    /// The budget error surfacing (the last refusal, auto-cleared).
    @State private var budgetNotice: String?

    private var session: SegmentSession { editingState.segmentSession }

    private var fitted: CGRect {
        viewportState.transform(
            viewportSize: viewportSize, textureSize: displaySize).rect
    }

    private var transform: ViewportTransform {
        viewportState.transform(viewportSize: viewportSize, textureSize: displaySize)
    }

    var body: some View {
        if displaySize.width >= 1, displaySize.height >= 1,
           fitted.width >= 1, fitted.height >= 1 {
            ZStack {
                SegmentPointsCanvas(
                    seed: session.seed,
                    included: session.included.map(\.point),
                    excluded: session.excluded.map(\.point),
                    boxDraft: boxDraft.map { ($0.start, $0.current) },
                    transform: transform)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(boxGesture.simultaneously(with: tapDisambiguator))
            }
            .overlay(alignment: .top) { counterBadge.padding(.top, 10) }
            .overlay(alignment: .bottom) { controlBar.padding(.bottom, 56) }
            .accessibilityIdentifier("segment.overlay")
            .onAppear {
                editingState.armSegmentSession(
                    for: selectedAdjustmentLayer)
            }
        }
    }

    private var selectedAdjustmentLayer: AdjustmentLayer? {
        guard let id = editingState.selectedLayerID else { return nil }
        return editorState.adjustmentLayer(id: id)
    }

    // MARK: coordinate mapping (13-3 T3: the transform's inverse — nil
    // outside the zoomed image content; the 07-3 clamp-to-edge form is
    // retired with the fit-layout assumption)

    private func normalized(_ location: CGPoint) -> AIMaskPoint? {
        guard let uv = transform.uv(at: location) else { return nil }
        return AIMaskPoint(
            x: Float(min(max(uv.x, 0), 1)),
            y: Float(min(max(uv.y, 0), 1)))
    }

    // MARK: gestures

    /// The tap leg: plain click = include, ⌥-click = exclude. (The macOS
    /// 27 SDK dropped DragGesture.Value.modifiers — the live modifier mask
    /// is read synchronously through `NSEvent.modifierFlags` inside the
    /// handler, which runs on the main thread within the event.)
    /// Right-click exclusion is NOT wired in v1 — SwiftUI has no view-level
    /// right-click gesture with a location on macOS; ⌥-click covers the
    /// exclude leg (recorded decision + Manual-Only item).
    private var tapDisambiguator: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let travel = hypot(
                    value.location.x - value.startLocation.x,
                    value.location.y - value.startLocation.y)
                guard travel < 3 else { return } // a drag, not a tap
                handleTap(
                    at: value.location,
                    excluded: NSEvent.modifierFlags.contains(.option))
            }
    }

    /// The ⇧-box leg: the macOS 27 SDK has no `modifiers:` gesture init —
    /// the box materializes only when SHIFT is still held at drag end.
    private var boxGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard NSEvent.modifierFlags.contains(.shift) else { return }
                guard let start = normalized(value.startLocation),
                      let current = normalized(value.location)
                else { return }
                boxDraft = (start.asSIMD, current.asSIMD)
            }
            .onEnded { value in
                guard NSEvent.modifierFlags.contains(.shift) else {
                    boxDraft = nil
                    return
                }
                guard let a = normalized(value.startLocation),
                      let b = normalized(value.location)
                else {
                    boxDraft = nil
                    return
                }
                boxDraft = nil
                let rect = AIMaskRect(
                    x: min(a.x, b.x), y: min(a.y, b.y),
                    width: abs(a.x - b.x), height: abs(a.y - b.y))
                guard rect.width > 0.005, rect.height > 0.005 else { return }
                session.recordSeed(.box(rect))
                budgetNotice = nil
            }
    }

    /// A tap with the ⌥ modifier lands as a plain tap in SpatialTapGesture
    /// (modifiers read off the value); right-click needs the AppKit menu —
    /// the contextMenu leg records the exclusion at the click point.
    private func handleTap(at location: CGPoint, excluded: Bool) {
        guard !session.isGenerating else { return }
        guard let point = normalized(location) else { return }
        do {
            if excluded {
                try session.addExcluded(point)
            } else {
                try session.addIncluded(point)
            }
            budgetNotice = nil
        } catch AIMaskError.pointLimitExceeded(let limit) {
            budgetNotice = String(localized: "ai_segment_full \(limit)")
        } catch {
            budgetNotice = "\(error)"
        }
    }

    // MARK: visuals

    private var counterFull: Bool { session.budgetFull }

    private var counterBadge: some View {
        Text("\(session.usedPoints)/\(session.pointBudget)")
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(counterFull
                        ? AnyShapeStyle(Color.red.opacity(0.75))
                        : AnyShapeStyle(.ultraThinMaterial)))
            .foregroundStyle(counterFull ? Color.white : Color.primary)
            .accessibilityLabel(Text("ai_segment_counter"))
            .accessibilityValue("\(session.usedPoints)")
            .accessibilityIdentifier("segment.counter")
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            if let notice = budgetNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("segment.budgetnotice")
            }
            Text("ai_segment_hint")
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
            Button(String(localized: session.rebakeFileName == nil ? "ai_segment_confirm" : "ai_segment_refine")) {
                Task { await generate() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!session.hasSeed || session.isGenerating)
            .accessibilityIdentifier("segment.confirm")
            Button(String(localized: "alert_done")) {
                editingState.setSegmentActive(false)
            }
            .controlSize(.small)
            .accessibilityIdentifier("segment.done")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(6)
    }

    // MARK: generation (the confirm leg)

    private func generate() async {
        guard let seed = session.seed, let metal = metalContext else { return }
        session.isGenerating = true
        defer { session.isGenerating = false }
        do {
            guard let (input, width, height) = AIMaskEditing.decodeFrameInput(pipeCoordinator) else {
                throw AIMaskError.invalidInput("no decoded frame for inference")
            }
            // Refine re-bake: the session's fixed file name (same maskID,
            // D-07-CONTEXT-5). First generation: derive it at commit time
            // through AIMaskSource (the layer UUID names the file).
            let plane = try await AIMaskService.segmentSubject(
                input: input, seed: seed, refine: session.refinePoints,
                quality: .accurate)
            let ref = try await AIMaskEditing.commitRasterMask(
                plane: plane, source: .segment,
                decodeWidth: width, decodeHeight: height,
                label: String(localized: "history_ai_mask"),
                activateTool: nil, // stay in the segment mode for refining
                coordinator: pipeCoordinator, editorState: editorState,
                editingState: editingState, metal: metal)
            // The re-bake target is now pinned to the written file.
            session.rebakeFileName = ref.fileName
            editorState.presentToast(String(localized: "ai_toast_mask_ready"))
        } catch let error as AIMaskError {
            editorState.presentToast(
                error == .noSubject
                    ? String(localized: "ai_toast_no_subject")
                    : String(localized: "ai_toast_generate_failed") + " (\(error))")
        } catch {
            editorState.presentToast(
                String(localized: "ai_toast_generate_failed") + " (\(error))")
        }
    }
}

private extension AIMaskPoint {
    var asSIMD: SIMD2<Float> { SIMD2(x, y) }
}

// MARK: - The points/box canvas

private struct SegmentPointsCanvas: View {
    let seed: AISubjectSeed?
    let included: [AIMaskPoint]
    let excluded: [AIMaskPoint]
    let boxDraft: (SIMD2<Float>, SIMD2<Float>)?
    /// 13-3 T3: the forward map (dots stay screen-constant; only their
    /// centers ride the transform).
    let transform: ViewportTransform

    var body: some View {
        Canvas { context, _ in
            func dot(_ p: SIMD2<Float>, _ color: Color) {
                let center = transform.point(atUV: SIMD2(Double(p.x), Double(p.y)))
                let rect = CGRect(
                    x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                    with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
            if case let .point(seedPoint) = seed {
                dot(seedPoint.asSIMD, .accentColor)
            }
            for p in included { dot(p.asSIMD, .accentColor) }
            for p in excluded { dot(p.asSIMD, .orange) }
            if let (a, b) = boxDraft {
                // The draft box: the two corners forward-mapped (with a
                // rotation the axis-aligned screen rect is the corners'
                // bounding box — the draft is provisional; the seed
                // records the normalized rect, identical to 07-3).
                let topLeft = transform.point(atUV: SIMD2(Double(min(a.x, b.x)), Double(min(a.y, b.y))))
                let bottomRight = transform.point(atUV: SIMD2(Double(max(a.x, b.x)), Double(max(a.y, b.y))))
                let screen = CGRect(
                    x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
                    width: abs(bottomRight.x - topLeft.x),
                    height: abs(bottomRight.y - topLeft.y))
                context.stroke(
                    Path(screen), with: .color(.yellow),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
        }
        .allowsHitTesting(false)
    }
}
