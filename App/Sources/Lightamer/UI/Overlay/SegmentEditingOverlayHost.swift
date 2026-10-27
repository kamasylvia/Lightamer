import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// SegmentEditingOverlayHost (Plan 07-3 T2; M9-1 T3 iterative face) — the
// tap-to-segment viewport interaction, the 4TH editing mode
// (LayerEditingState's `.segment` route; mutex with mask-drawing /
// liquify / retouch / crop by the machine's if/else-if chain).
//
// GESTURES (the M9-1 iterative form — the gesture IS the tool, no
// prompt-tool switcher):
//   click            → seed point (first) / INCLUDED refine point (after);
//                      a click ON an existing point (within the hit
//                      radius) DELETES it (the point-level delete,
//                      D-M9A-5's minimal face)
//   ⌥-click          → EXCLUDED refine point (after a seed exists)
//   ⇧-drag           → seed box (replaces the seed, clears the points)
//   plain drag       → PATH stroke (M9-1 T3): collected, then resampled
//                      at equal 24px arc-length intervals
//                      (`AIMaskPathSampling`) into INCLUDED refine points
//   confirm button   → bake the CANDIDATE plane when the iterative
//                      session holds one (zero re-solve), else the
//                      full re-solve — both funnel into
//                      `commitRasterMask` (exactly ONE stackSnapshot per
//                      confirm, D-07-CONTEXT-5)
//
// ITERATIVE RE-SOLVE (D-M9A-1): every point-set change schedules the
// 300ms-debounced candidate solve (`AIMaskEditing.scheduleCandidateResolve`
// → `runCandidateResolve`); the candidate tints through the coordinator's
// DEDICATED candidate arm (the pale-red coverage channel) and STAYS
// displayed while solving (the upstream「推理期间保留旧 coverage」
// semantics); Commit/Cancel clear the channel (D-M9A-4).
//
// VISUALS (the upstream input-overlay alignment — numeric parameter
// facts, not copied code): included points = GREEN + discs, excluded =
// RED − discs, the seed box dashed rect, the point-counter badge
// (used/budget, full → red), the candidate spinner.
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
    /// The pending PATH stroke (view points; sampled on release).
    @State private var strokeDraft: [SIMD2<Float>] = []
    /// The budget error surfacing (the last refusal, auto-cleared).
    @State private var budgetNotice: String?

    /// The point-delete hit radius (screen points).
    private static let pointHitRadius: CGFloat = 12
    /// The upstream input-overlay marker palette (M9-1 T3: green + disc /
    /// red − disc — numeric parameter facts, not copied code). The RGB
    /// vectors are the SINGLE SOURCE (the tests pin them; the Color
    /// initializers are pure projections).
    static let includedMarkerRGB: SIMD3<Float> = SIMD3(
        Float(0x30) / 255, Float(0xA4) / 255, Float(0x6C) / 255)
    static let excludedMarkerRGB: SIMD3<Float> = SIMD3(
        Float(0xE5) / 255, Float(0x48) / 255, Float(0x4D) / 255)
    static var includedMarkerColor: Color {
        Color(.sRGB,
              red: Double(includedMarkerRGB.x),
              green: Double(includedMarkerRGB.y),
              blue: Double(includedMarkerRGB.z))
    }
    static var excludedMarkerColor: Color {
        Color(.sRGB,
              red: Double(excludedMarkerRGB.x),
              green: Double(excludedMarkerRGB.y),
              blue: Double(excludedMarkerRGB.z))
    }

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
                    strokeDraft: strokeDraft,
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
            .onDisappear {
                // Mode exit = Cancel semantics (M9-1 T4): the unbaked
                // candidate channel dies with the face.
                session.releaseCandidate()
                pipeCoordinator.setCandidateOverlayRequest(nil)
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

    // MARK: the iterative re-solve scheduling (D-M9A-1)

    /// Every point-set change funnels here: 300ms debounce → the full
    /// candidate re-solve (the old candidate stays displayed while the
    /// new one solves).
    private func scheduleCandidateSolve() {
        guard session.hasSeed else { return }
        let coordinator = pipeCoordinator
        let editorState = editorState
        let editingState = editingState
        guard let metal = metalContext else { return }
        AIMaskEditing.scheduleCandidateResolve(session: session) {
            await AIMaskEditing.runCandidateResolve(
                coordinator: coordinator, editorState: editorState,
                editingState: editingState, metal: metal)
        }
    }

    // MARK: gestures

    /// The tap leg: plain click = include (or point-delete on an existing
    /// marker), ⌥-click = exclude. (The macOS 27 SDK dropped
    /// DragGesture.Value.modifiers — the live modifier mask is read
    /// synchronously through `NSEvent.modifierFlags` inside the handler,
    /// which runs on the main thread within the event.)
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

    /// The drag leg, split by modifier: ⇧ = the seed box (07-3 form);
    /// plain = the PATH stroke (M9-1 T3 — the stroke is collected and
    /// resampled on release).
    private var boxGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if NSEvent.modifierFlags.contains(.shift) {
                    guard let start = normalized(value.startLocation),
                          let current = normalized(value.location)
                    else { return }
                    boxDraft = (start.asSIMD, current.asSIMD)
                } else {
                    strokeDraft.append(
                        SIMD2(Float(value.location.x), Float(value.location.y)))
                }
            }
            .onEnded { value in
                if NSEvent.modifierFlags.contains(.shift) {
                    defer { boxDraft = nil }
                    guard let a = normalized(value.startLocation),
                          let b = normalized(value.location)
                    else { return }
                    let rect = AIMaskRect(
                        x: min(a.x, b.x), y: min(a.y, b.y),
                        width: abs(a.x - b.x), height: abs(a.y - b.y))
                    guard rect.width > 0.005, rect.height > 0.005 else { return }
                    session.recordSeed(.box(rect))
                    budgetNotice = nil
                    scheduleCandidateSolve()
                } else {
                    defer { strokeDraft = [] }
                    handleStrokeRelease()
                }
            }
    }

    /// A tap with the ⌥ modifier lands as a plain tap in SpatialTapGesture
    /// (modifiers read off the value); the point-delete hit check runs
    /// BEFORE any add (a click on an existing marker removes it).
    private func handleTap(at location: CGPoint, excluded: Bool) {
        guard !session.isGenerating else { return }
        // The point-delete hit test (M9-1: click ON a marker deletes it).
        if deletePoint(nearScreen: location) { return }
        guard let point = normalized(location) else { return }
        do {
            if excluded {
                try session.addExcluded(point)
            } else {
                try session.addIncluded(point)
            }
            budgetNotice = nil
            scheduleCandidateSolve()
        } catch AIMaskError.pointLimitExceeded(let limit) {
            budgetNotice = String(
                format: String(localized: "ai_segment_full %lld"), limit)
        } catch {
            budgetNotice = "\(error)"
        }
    }

    /// Delete the refine point whose marker contains the screen location
    /// (the nearest within the hit radius). Returns true when a point was
    /// deleted (the tap is consumed).
    private func deletePoint(nearScreen location: CGPoint) -> Bool {
        func screenPosition(_ point: AIMaskPoint) -> CGPoint {
            transform.point(atUV: SIMD2(Double(point.x), Double(point.y)))
        }
        func nearest<C: Collection>(
            in points: C, screen: (C.Element) -> CGPoint,
            remove: (Int) -> Void) -> Bool {
            var best: (index: Int, distance: CGFloat)?
            for (index, element) in points.enumerated() {
                let center = screen(element)
                let distance = hypot(
                    center.x - location.x, center.y - location.y)
                if distance <= Self.pointHitRadius,
                   best.map({ distance < $0.distance }) ?? true {
                    best = (index, distance)
                }
            }
            if let best { remove(best.index); return true }
            return false
        }
        // The seed point itself is a SEED, not a refine point — deleting
        // it is a seed reset (recordSeed clears everything), so the tap
        // targets only the refine vectors (the minimal D-M9A-5 face).
        if nearest(
            in: session.included.map(\.point), screen: screenPosition,
            remove: { session.removeIncluded(at: $0) })
        {
            scheduleCandidateSolve()
            return true
        }
        if nearest(
            in: session.excluded.map(\.point), screen: screenPosition,
            remove: { session.removeExcluded(at: $0) })
        {
            scheduleCandidateSolve()
            return true
        }
        return false
    }

    /// The PATH stroke release (M9-1 T3, D-M9A-6): resample the stroke at
    /// equal 24px arc-length intervals into INCLUDED refine points
    /// (capped at min(16, budget headroom)) — the FIRST sample becomes
    /// the point seed when the session has none (the stroke needs a seed
    /// for the request; the rest ride the refine vector).
    private func handleStrokeRelease() {
        guard strokeDraft.count >= 2, !session.isGenerating else { return }
        // View px → analysis px: the stroke rides the DISPLAY plane; the
        // sampling domain = the display texture's pixels (the analysis-
        // image equivalent at v1 — the normalized output is domain-free).
        let width = max(Int(displaySize.width.rounded()), 1)
        let height = max(Int(displaySize.height.rounded()), 1)
        func strokeInImagePixels(_ stroke: [SIMD2<Float>]) -> [SIMD2<Float>] {
            stroke.map { view in
                guard let uv = transform.uv(at: CGPoint(x: CGFloat(view.x), y: CGFloat(view.y))) else {
                    return view
                }
                return SIMD2(
                    Float(min(max(uv.x, 0), 1)) * Float(width),
                    Float(min(max(uv.y, 0), 1)) * Float(height))
            }
        }
        let headroom = session.pointBudget - session.usedPoints
        let samples = AIMaskPathSampling.sampleStroke(
            stroke: strokeInImagePixels(strokeDraft),
            count: AIMaskPathSampling.sampleCount(budgetHeadroom: headroom),
            imageWidth: width, imageHeight: height)
        guard !samples.isEmpty else { return }
        do {
            var iterator = samples.makeIterator()
            if session.seed == nil, let first = iterator.next() {
                try session.addIncluded(first) // records the point seed
            }
            var added = 0
            while let sample = iterator.next() {
                try session.addIncluded(sample)
                added += 1
            }
            _ = added
            budgetNotice = nil
            scheduleCandidateSolve()
        } catch AIMaskError.pointLimitExceeded(let limit) {
            budgetNotice = String(
                format: String(localized: "ai_segment_full %lld"), limit)
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
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(counterFull
                        ? AnyShapeStyle(Color.red.opacity(0.75))
                        : AnyShapeStyle(.ultraThinMaterial))
            }
            .foregroundStyle(counterFull ? Color.white : Color.primary)
            .accessibilityLabel(Text("ai_segment_counter"))
            .accessibilityValue("\(session.usedPoints)")
            .accessibilityIdentifier("segment.counter")
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            if session.candidateState == .solving {
                ProgressView()
                    .controlSize(.small)
                Text("ai_candidate_solving")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                    .accessibilityIdentifier("segment.candidate.solving")
            } else if session.candidateState == .ready {
                Text("ai_candidate_ready")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                    .accessibilityIdentifier("segment.candidate.ready")
            }
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
                cancelSession()
            }
            .controlSize(.small)
            .accessibilityIdentifier("segment.done")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// The Done button's cancel semantics (M9-1 T4): drop the unbaked
    /// candidate + the overlay channel, exit the mode — zero bake, zero
    /// history (the「攒点未 confirm 本就未 bake」face upgraded with the
    /// candidate-discard).
    private func cancelSession() {
        session.releaseCandidate()
        pipeCoordinator.setCandidateOverlayRequest(nil)
        editingState.setSegmentActive(false)
    }

    // MARK: generation (the confirm leg)

    private func generate() async {
        // The iterative form (D-M9A-1's payoff): a held candidate bakes
        // DIRECTLY — zero re-solve at confirm; without one the 07-3 full
        // re-solve runs (the fallback arm, always kept).
        if let candidate = session.candidatePlane {
            await commitCandidate(candidate)
            return
        }
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
            let ref = try await commit(plane, width: width, height: height)
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

    /// Bake the candidate plane (the confirm's iterative arm) and clear
    /// the candidate channel (D-M9A-4: it disappears; the committed
    /// mask's ordinary edit tint takes over inside commitRasterMask).
    private func commitCandidate(_ candidate: AIMaskPlane) async {
        guard metalContext != nil,
              let (_, width, height) = AIMaskEditing.decodeFrameInput(pipeCoordinator)
        else { return }
        do {
            _ = try await commit(candidate, width: width, height: height)
            editorState.presentToast(String(localized: "ai_toast_mask_ready"))
        } catch {
            editorState.presentToast(
                String(localized: "ai_toast_generate_failed") + " (\(error))")
        }
    }

    /// The shared commit channel (both arms funnel here — exactly ONE
    /// stackSnapshot item per confirm).
    private func commit(
        _ plane: AIMaskPlane, width: Int, height: Int
    ) async throws -> RasterMaskRef {
        guard let metal = metalContext else {
            throw AIMaskError.invalidInput("no metal context")
        }
        let ref = try await AIMaskEditing.commitRasterMask(
            plane: plane, source: .segment,
            decodeWidth: width, decodeHeight: height,
            label: String(localized: "history_ai_mask"),
            activateTool: nil, // stay in the segment mode for refining
            coordinator: pipeCoordinator, editorState: editorState,
            editingState: editingState, metal: metal)
        // D-M9A-4: the candidate channel disappears at commit — the
        // committed mask's ordinary edit tint (inside commitRasterMask)
        // is the AI-06 affordance, a different face by design.
        session.releaseCandidate()
        pipeCoordinator.setCandidateOverlayRequest(nil)
        session.rebakeFileName = ref.fileName
        return ref
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
    /// The live PATH stroke (view points, M9-1 T3).
    let strokeDraft: [SIMD2<Float>]
    /// 13-3 T3: the forward map (dots stay screen-constant; only their
    /// centers ride the transform).
    let transform: ViewportTransform

    var body: some View {
        Canvas { context, _ in
            // The PATH stroke preview (the upstream 4px stroke face).
            if strokeDraft.count > 1 {
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(strokeDraft[0].x), y: CGFloat(strokeDraft[0].y)))
                for point in strokeDraft.dropFirst() {
                    path.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
                }
                context.stroke(
                    path,
                    with: .color(Self.includedColor.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            func dot(_ p: SIMD2<Float>, _ color: Color) {
                let center = transform.point(atUV: SIMD2(Double(p.x), Double(p.y)))
                let rect = CGRect(
                    x: center.x - 7, y: center.y - 7, width: 14, height: 14)
                // The marker: a colored disc with a 1.5px dark rim (the
                // upstream input-overlay geometry — numeric facts).
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.black.opacity(0.55)), lineWidth: 1.5)
            }
            if case let .point(seedPoint) = seed {
                dot(seedPoint.asSIMD, Self.includedColor)
            }
            for p in included { dot(p.asSIMD, Self.includedColor) }
            for p in excluded { dot(p.asSIMD, Self.excludedColor) }
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

    /// The single-source marker palette (the tests pin the constants —
    /// the visual mapping's machine-checkable side).
    static let includedColor = SegmentEditingOverlayHost.includedMarkerColor
    static let excludedColor = SegmentEditingOverlayHost.excludedMarkerColor
}
