import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────
// LayerEditingState (Plan 06-05 T3) — the layer-selection + editing-mode
// state machine, the SINGLE arbitration point for viewport gestures.
//
// The viewport overlay is a FUNCTION of this state (EditorAreaView reads
// it; nothing else mounts interaction surfaces):
//
//   maskEditingActive  (a layer is selected AND a mask tool is armed)
//        → MaskOverlayHost owns the viewport
//   liquifyRequested   (the liquify panel is the selected Inspector
//        surface — the 06-06 v1 rule, now routed THROUGH this machine)
//        → LiquifyOverlayHost owns the viewport
//   segmentActive      (the 07-3 tap-to-segment mode —「点击选取」)
//        → SegmentEditingOverlayHost owns the viewport
//   otherwise          → CropOverlayHost owns the viewport
//
// INVARIANT (the mutex contract): at most ONE of the four overlays can
// be active — the routes are an exhaustive if/else-if chain keyed on this
// state, so two gestures can never route simultaneously. The unit tests
// pin the state machine (`LayerUIWiringTests` layer group).
//
// NOT owned here: the layer STACK (EditorState), history (EditorState),
// rendering (PipeCoordinator). This is pure UI arbitration state (D-03b).
// ─────────────────────────────────────────────────────────────────────────

/// The mask drawing tools (plan T3.1 — five, Manual-Only 手感 red line).
enum MaskTool: String, CaseIterable, Sendable {
    case brush
    case eraser
    case gradient
    case ellipse
    case path

    /// The AX/toolbar identifier stem (L010: stable ids, not indexes).
    var identifier: String { "mask.tool.\(rawValue)" }

    /// zh/en catalog key stem (`mask_tool_<rawValue>`).
    var labelKey: String { "mask_tool_\(rawValue)" }

    var systemImage: String {
        switch self {
        case .brush: return "paintbrush.pointed"
        case .eraser: return "eraser"
        case .gradient: return "line.diagonal" // GUI-14 fix: "gradient.3.crossing" is MISSING on this OS → blank icon
        case .ellipse: return "circle" // GUI-14 fix: "ellipse" is MISSING → blank icon
        case .path: return "scribble"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Mask overlay display styles (Plan 13-3 T5, D-13-CONTEXT-9③) — the THREE
// display states of the 「显示蒙版」 tint. A DISPLAY-STYLE enum: it never
// enters the mask record, the history, or the sidecar — only the
// coordinator's overlay request carries it.
// ─────────────────────────────────────────────────────────────────────────

/// The mask overlay's display style (half-transparent yellow tint is the
/// 06-3 legacy default; rubylith = the classic red scrim; on-black = the
/// dt-style white-mask-on-black inspection view).
enum MaskOverlayStyle: String, CaseIterable, Sendable {
    case translucent
    case rubylith
    case onBlack

    /// zh/en catalog key stem (`mask_overlay_style_<rawValue>`).
    var labelKey: String { "mask_overlay_style_\(rawValue)" }
}

/// The mask COMMAND face (Plan 13-3 T5, D-13-CONTEXT-9② — the 2026-09-26
/// registered UI batch). The five commands route through the LayerStack's
/// EXISTING edit entries (`EditorState.commitLayerEdit` — every command
/// lands EXACTLY ONE history item, ⌘Z-able). KERNEL ZERO-CHANGE: nothing
/// here touches `AdjustmentLayer`/`MaskCombiner`/the combine assembly
/// (the Phase 6 verified surface) — a command is a RECORD edit.
enum MaskCommand: String, CaseIterable, Sendable {
    case duplicate
    case duplicateAndInvert
    case fill
    case clear
    case resetEdits

    /// zh/en catalog key stem (`mask_command_<rawValue>`).
    var labelKey: String { "mask_command_\(rawValue)" }
}

@Observable
@MainActor
final class LayerEditingState {

    // MARK: selection

    /// The currently selected layer (nil = base/global scope — the
    /// Inspector shows the global chain and the mask tools disable).
    /// BOTH kinds anchor here since 06-07 (adjustment + retouch).
    private(set) var selectedLayerID: UUID?

    /// The layer object for the selection, if it still exists in the
    /// stack (a structural undo can remove it — selection then clears).
    func selectedLayer(in stack: LayerStack?) -> AdjustmentLayer? {
        guard let id = selectedLayerID else { return nil }
        guard let stack else { return nil } // no stack info — keep the selection
        guard let layer = stack.compositeLayers.first(where: { $0.id == id }) else {
            selectedLayerID = nil // dangling selection self-heals
            return nil
        }
        return layer
    }

    /// 06-07: the selected RETOUCH layer, when one is (still) selected.
    func selectedRetouchLayer(in stack: LayerStack?) -> RetouchLayer? {
        guard let id = selectedLayerID else { return nil }
        guard let stack else { return nil }
        guard let layer = stack.adjustmentLayers.first(where: { $0.id == id }),
              let retouch = layer as? RetouchLayer
        else {
            // A dangling OR re-typed selection heals only when the id is
            // really gone; an adjustment selection simply reports nil.
            if !stack.adjustmentLayers.contains(where: { $0.id == id }) {
                selectedLayerID = nil
            }
            return nil
        }
        return retouch
    }

    /// Select a layer (nil = back to the global/base scope). Selecting a
    /// layer arms the LAYERS Inspector surface; the mask toolbar enables.
    func select(_ layerID: UUID?) {
        selectedLayerID = layerID
    }

    // MARK: mask tools

    /// The armed mask tool (nil = no mask editing — the viewport routes
    /// to the crop/liquify overlays per the machine above).
    private(set) var activeTool: MaskTool?

    /// 「显示蒙版」— the selected layer's mask overlay tint on the display
    /// plane (the 06-3 render leg; the UI toggle this plan wires).
    var showsMaskOverlay: Bool = true

    /// 13-3 T5: the overlay display STYLE (On-Black / Rubylith / 半透明).
    /// UI state only — rides the overlay REQUEST, never the record.
    var maskOverlayStyle: MaskOverlayStyle = .translucent

    /// Brush parameters (stroke-level, v1 — D-06-03-T5-1 keeps density/
    /// hardness per STROKE; the toolbar edits the one brush at a time).
    var brushRadius: Float = 0.06       // normalized WIDTH units
    var brushHardness: Float = 0.7      // 0..1 solid-core fraction
    var brushFlow: Float = 1.0          // per-stamp weight
    var brushOpacity: Float = 1.0       // stroke ceiling multiplier
    var gradientState: GradientState = .linear

    // MARK: retouch tools (Plan 06-07 T4)

    /// The algorithm the NEXT stroke lands with (dt's module-level
    /// `algorithm` default = heal — retouch.c:118 $DEFAULT comment).
    var retouchAlgorithm: RetouchAlgorithm = .heal

    /// The stroke radius in normalized WIDTH units (the circle/lasso size).
    var retouchRadius: Float = 0.06

    /// Stroke feather (the shape's `border` fraction, dt form feather).
    var retouchFeather: Float = 0.15

    /// Stroke opacity ceiling (the per-stroke alpha).
    var retouchStrokeOpacity: Float = 1.0

    /// Blur algorithm sigma (dt `blur_radius` default 10 — full-res px
    /// semantics; the normalized stroke keeps it a plain scalar in v1).
    var retouchBlurRadius: Float = 10.0

    /// Fill color (linear Rec2020 0-1).
    var retouchFillColor: SIMD3<Float> = SIMD3(0.5, 0.5, 0.5)

    /// The clone/heal source-PICK mode: armed → the next viewport TAP
    /// samples the source patch center instead of painting (dt's
    /// ctrl-click source pick; the手感 is Manual-Only registered).
    var retouchSourcePickArmed: Bool = false

    /// The sampled source center (normalized) the NEXT clone/heal stroke
    /// carries; nil = paint without a source (heal degrades to clone-from
    /// -offset-zero semantics — the UI never creates one: strokes without
    /// a source default to same-position sampling).
    var pendingRetouchSource: SIMD2<Float>?

    /// The masked layer under edit (drives the overlay host's live legs).
    var maskEditingActive: Bool { selectedLayerID != nil && activeTool != nil }

    /// Arm/disarm a tool. Arming one disarms the others (radio semantics)
    /// AND disarms the tap-to-segment mode (the 4th route's mutex).
    func setTool(_ tool: MaskTool?) {
        activeTool = tool
        if tool != nil { segmentActive = false }
    }

    // MARK: tap-to-segment (Plan 07-3 T2 — the 4th editing mode)

    /// The 4th editing mode armed (MaskToolbar「点击选取」, layer B ready).
    /// Mutually exclusive with the mask tools by construction (arming a
    /// tool disarms segment and vice versa).
    private(set) var segmentActive = false

    /// The live tap-to-segment session (seeds + refine points + the
    /// re-bake target). UI-STATE ONLY — AI generation parameters never
    /// persist (07-CONTEXT 继承定案); the session dies with the mode.
    private(set) var segmentSession = SegmentSession()

    func setSegmentActive(_ active: Bool) {
        segmentActive = active
        if active {
            activeTool = nil
            // Re-entry on a layer that already carries a layer-B raster
            // mask seeds a REFINE session pointing at the same mask file
            // (D-07-CONTEXT-5 overwrite re-bake). Needs the stack — the
            // caller (toolbar) guarantees a selection; the session seeds
            // lazily through `armSegmentSession(for:)`.
        } else {
            segmentSession = SegmentSession()
        }
    }

    /// Seed/refresh the session against the selected layer's mask state
    /// (called on mode entry; the refine marker is the mask file's source
    /// prefix — D-07-CONTEXT-5).
    func armSegmentSession(for layer: AdjustmentLayer?) {
        segmentSession = SegmentSession()
        if let fileName = layer?.mask?.raster?.fileName,
           AIMaskSource.source(ofFileName: fileName) == .segment {
            segmentSession.rebakeFileName = fileName
        }
    }

    // MARK: arbitration (the machine's single decision point)

    /// Which overlay owns the viewport RIGHT NOW. Exactly one answer —
    /// the mutex invariant the tests pin.
    enum ViewportRoute: Equatable, Sendable {
        case maskEditing
        case liquify
        case retouch
        case segment
        case crop
    }

    func viewportRoute(liquifyPanelSelected: Bool, retouchPanelSelected: Bool) -> ViewportRoute {
        if maskEditingActive { return .maskEditing }
        if liquifyPanelSelected { return .liquify }
        if retouchPanelSelected { return .retouch }
        if segmentActive { return .segment }
        return .crop
    }

    // MARK: mask commands (13-3 T5 — the five-command face)

    /// Route a mask command onto the SELECTED layer through EditorState's
    /// EXISTING edit entries. Every command lands EXACTLY ONE history
    /// item (the compound `duplicateAndInvert` is the documented
    /// exception: the structural clone + the inversion flip — TWO items,
    /// two ⌘Z steps, both recorded). No selection → a silent no-op (the
    /// menu disables before this can fire).
    func performMaskCommand(_ command: MaskCommand, editorState: EditorState) {
        guard let id = selectedLayerID,
              let layer = editorState.adjustmentLayer(id: id)
        else { return }
        switch command {
        case .duplicate:
            // The EXISTING duplicate path (fresh identities above the
            // original — the layer's mask value-copies along).
            editorState.duplicateLayer(id: id)
        case .duplicateAndInvert:
            // TWO history items (the clone rides the existing structure
            // entry; the inversion is ONE property commit on the copy).
            guard let copy = editorState.duplicateLayer(id: id) as? AdjustmentLayer
            else { return }
            var invertedCopy = Self.snapshot(copy)
            invertedCopy.mask = Self.inverted(invertedCopy.mask)
            editorState.commitLayerEdit(
                invertedCopy, label: String(localized: "mask_command_duplicateAndInvert"))
        case .fill:
            // Fill = the mask record becomes the EMPTY spec — the
            // constant-1 passthrough of the degenerate triple (the Phase
            // 6 contract). Composite-identical to a full plane with ZERO
            // kernel/GPU involvement (the App layer never calls
            // MaskCombiner.fill — that is a render-time helper).
            var copy = Self.snapshot(layer)
            copy.mask = MaskSpec()
            editorState.commitLayerEdit(
                copy, label: String(localized: "mask_command_fill"))
        case .clear:
            // Clear = NO mask record at all (the chip's empty state).
            var copy = Self.snapshot(layer)
            copy.mask = nil
            editorState.commitLayerEdit(
                copy, label: String(localized: "mask_command_clear"))
        case .resetEdits:
            // Reset Edits = the layer's iop CHAIN returns to the default
            // (empty) — the mask itself is PRESERVED (this command lives
            // on the mask context menu; "edits" = what the mask applies).
            var copy = Self.snapshot(layer)
            copy.chain = []
            editorState.commitLayerEdit(
                copy, label: String(localized: "mask_command_resetEdits"))
        }
    }

    /// The VALUE copy with the SAME identity (the class fields are all
    /// value types — the same snapshot shape `LayerRowView` commits).
    private static func snapshot(_ layer: AdjustmentLayer) -> AdjustmentLayer {
        AdjustmentLayer(
            id: layer.id, name: layer.name, isVisible: layer.isVisible,
            opacity: layer.opacity, blendMode: layer.blendMode,
            blendOptions: layer.blendOptions, enabled: layer.enabled,
            chain: layer.chain, mask: layer.mask)
    }

    /// The inversion flip across ALL mask payloads (the invert bits are
    /// Phase 6 verified fields — this flips RECORDS, never kernels):
    /// drawn group items (recursively), a group-less drawn spec gets a
    /// group whose items carry the inverted bit, the parametric invert
    /// flag, and the raster ref's invert flag.
    static func inverted(_ mask: MaskSpec?) -> MaskSpec? {
        guard var mask else { return nil }
        if var drawn = mask.drawn {
            if var group = drawn.group {
                group.items = group.items.map { Self.invertedItem($0) }
                drawn.group = group
            } else if !drawn.forms.isEmpty {
                // The 06-03 single-form path has NO group: inversion wraps
                // every form into a group item with the bit set (per-item
                // invert = the dt group semantics the combiner implements).
                drawn.group = MaskGroupSpec(items: drawn.forms.map {
                    MaskGroupItem(
                        formID: $0.id, op: .union, inverted: true, opacity: 1)
                })
            }
            mask.drawn = drawn
        }
        if var parametric = mask.parametric {
            parametric.invert.toggle()
            mask.parametric = parametric
        }
        if var raster = mask.raster {
            raster.invert.toggle()
            mask.raster = raster
        }
        return mask
    }

    /// Recursive (nested groups ride `MaskGroupItem.child`).
    private static func invertedItem(_ item: MaskGroupItem) -> MaskGroupItem {
        var copy = item
        copy.inverted.toggle()
        if let child = copy.child {
            var flipped = child
            flipped.items = flipped.items.map { Self.invertedItem($0) }
            copy.child = flipped
        }
        return copy
    }
}

// ─────────────────────────────────────────────────────────────────────────
// SegmentSession (Plan 07-3 T2) — the tap-to-segment UI state: the seed
// (point first tap / ⇧-box), the accumulated refine points (⌥·right-click
// = excluded), and the point-budget counter (13 point-seeded / 11
// box-seeded — AIPointBudget; full → the host refuses further points with
// a visible state, the service's typed error is the backstop).
//
// Coordinates: every point is an `AIMaskPoint` in VIEW-normalized
// (top-left) space; the Vision Y-flip happens ONLY in `visionPoint` (the
// single seam, 07-1 AIMaskTypes — the wiring test pins the flipped vector).
//
// UPGRADE SEAM (D-07-CONTEXT-4): the seed type is `AISubjectSeed` whose
// `.scribble` case exists but throws `scribbleNotSupported` in v1 — the
// exhaustive switch here is written from day one so scribble/lasso lands
// without a state-machine refactor.
// ─────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class SegmentSession {

    /// The seed (nil until the first tap / completed ⇧-box).
    private(set) var seed: AISubjectSeed?

    /// Included refine points (tap after the seed).
    private(set) var included: [AIRefinePoint] = []
    /// Excluded refine points (⌥-tap / right-click after the seed).
    private(set) var excluded: [AIRefinePoint] = []

    /// The re-bake target file (set on refine re-entry — same maskID
    /// overwrite, D-07-CONTEXT-5); nil = first generation for this layer.
    var rebakeFileName: String?

    /// The in-flight generation flag (the host's spinner).
    var isGenerating = false

    /// The point budget for the CURRENT seed kind (before a seed exists
    /// the point-seeded budget is the ceiling — the first tap decides).
    var pointBudget: Int {
        if case .box = seed { return AIPointBudget.boxSeeded }
        return AIPointBudget.pointSeeded
    }

    /// Points recorded so far (a point seed counts itself, AIPointBudget
    /// semantics).
    var usedPoints: Int {
        switch seed {
        case .point: return 1 + included.count + excluded.count
        case .box: return included.count + excluded.count
        case nil: return included.count + excluded.count
        case .scribble: return included.count + excluded.count
        }
    }

    var budgetFull: Bool { usedPoints >= pointBudget }

    /// Record the seed. A second seed REPLACES the first (fresh request)
    /// and clears the accumulated refine points.
    func recordSeed(_ newSeed: AISubjectSeed) {
        guard newSeed != .scribble else { return } // the v1 typed seam
        seed = newSeed
        included = []
        excluded = []
    }

    /// The budget-gated point adds (throwing keeps the UI honest — the
    /// host presents the error, nothing crashes, nothing silently drops).
    func addIncluded(_ point: AIMaskPoint) throws {
        guard seed != nil else {
            seed = .point(point)
            return
        }
        guard !budgetFull else {
            throw AIMaskError.pointLimitExceeded(limit: pointBudget)
        }
        included.append(AIRefinePoint(point, .included))
    }

    func addExcluded(_ point: AIMaskPoint) throws {
        guard seed != nil else {
            seed = .point(point)
            return
        }
        guard !budgetFull else {
            throw AIMaskError.pointLimitExceeded(limit: pointBudget)
        }
        excluded.append(AIRefinePoint(point, .excluded))
    }

    /// The refine vector for the request (view-normalized; the service
    /// applies the single Y-flip seam).
    var refinePoints: [AIRefinePoint] { included + excluded }

    /// True once a generation could run (a seed exists).
    var hasSeed: Bool { seed != nil }

    func clear() {
        seed = nil
        included = []
        excluded = []
        isGenerating = false
        // rebakeFileName survives — the mode exit resets the whole session
        // through setSegmentActive(false); a cleared point set keeps the
        // re-bake target for the next confirm.
    }
}
