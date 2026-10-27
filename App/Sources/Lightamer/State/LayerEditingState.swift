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
/// M2-7-2 T6 (checker E6): `.followEdges` joins the radio set — the
/// CaseIterable consumers (the toolbar ForEach) pick it up automatically.
enum MaskTool: String, CaseIterable, Sendable {
    case brush
    case eraser
    case gradient
    case ellipse
    case path
    case followEdges

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
        case .followEdges: return "arrow.triangle.branch"
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
///
/// M2-7-2 (Plan T2, checker M5 ruling = option A): `addMaskItem` /
/// `removeMaskItem` join as PAYLOAD-FREE cases — the associated-value form
/// would break the `CaseIterable` synthesis and leak into every `allCases`
/// consumer. The removal/insertion TARGET rides the execution-seam
/// parameter (`performMaskCommand(.removeMaskItem, itemID:)`) instead, and
/// the layer-row menu enumerates the `panelMenuCases` whitelist (the two
/// item commands are panel-row actions, never layer-menu rows).
enum MaskCommand: String, CaseIterable, Sendable {
    case duplicate
    case duplicateAndInvert
    case fill
    case clear
    case resetEdits
    case addMaskItem
    case removeMaskItem

    /// zh/en catalog key stem (`mask_command_<rawValue>`).
    var labelKey: String { "mask_command_\(rawValue)" }

    /// The layer-row context-menu whitelist (checker M5): the five
    /// layer-scoped commands. The two item commands need a TARGET ITEM id
    /// (the panel row's seam parameter) and MUST NOT enumerate in the
    /// layer menu — every menu consumer reads this list, never `allCases`,
    /// so a future command case cannot silently leak into the menu.
    static let panelMenuCases: [MaskCommand] = [
        .duplicate, .duplicateAndInvert, .fill, .clear, .resetEdits,
    ]
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
    /// V2M-02 T3 (residual ① eager release): the patch-flow face belongs
    /// to the PREVIOUS layer identity — switching layers releases it
    /// immediately instead of holding the live plane until the next wire
    /// activity (the D-13 residual: a switch after the last pass with no
    /// pending debounce kept the plane resident until mode exit / a new
    /// seed / the next wire event). A same-value re-select is a no-op.
    func select(_ layerID: UUID?) {
        if selectedLayerID != layerID {
            segmentSession.releaseLivePatchState()
        }
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

    // MARK: Follow Edges parameters (M2-7-2 T5, KD-5 — the toolbar section
    // binds these; the walker consumes them per stroke. EDITING-MODE state:
    // no history, never persisted — the brush-parameter precedent).

    /// The edge-aware brush's parameters (Core `FollowEdgesParams`; the
    /// brush WIDTH is NOT here — it passes through as the current brush
    /// radius, the KD-5 division). The UI default is `.snap` — the M2-7-3
    /// walkthrough fuse verdict (OQ-4-C): the streamline walker breaks on
    /// real-photo ridges at shipped params (chains of 1-3 points across all
    /// scenes); snap delivers deterministic edge-anchored lines. The walker
    /// stays selectable from the mode picker; the V2 re-anchor (M4-2) was
    /// deleted after its gate failure (2026-10-10 user ruling — requirement
    /// IOP-MASK-06 parked, restart = a reliable open-source reference).
    var followEdgesParams = FollowEdgesParams(mode: .snap)

    /// The empty-chain degrade status (KD-P1 KD-6 consumption face): set by
    /// the interaction leg when the walker returns an EMPTY chain (no map /
    /// no edge within reach) — the toolbar status hint surfaces it; any
    /// successful stroke clears it.
    var followEdgesDegraded = false

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

    // MARK: Locate (M2-7-2, KD-3 dispatch table)

    /// The ONE-shot pending right-rail tab route. The Mask Groups panel's
    /// Locate writes it; `EditorAdjustmentStackView` consumes (clears) it
    /// on change — the tab STATE stays the stack view's private `@State`
    /// (no second selection truth; this is a routed REQUEST, not state).
    var pendingTabRoute: EditorTabRoute?

    /// Locate a mask row: select its layer (the seven tabs then edit that
    /// layer — the D-M2-4-CONTEXT-9 write side), disarm any armed tool
    /// (KD-3「联动选中」), and route the right rail to the Mask page.
    func locateMask(layerID: UUID) {
        select(layerID)
        setTool(nil)
        pendingTabRoute = .mask
    }

    // MARK: Default Behavior (M2-7-2 T4, KD-4 — checker E1 re-ruling)

    /// The completion-time behavior resolver, INJECTED (M2-1 D-EXEC-1
    /// shape): the default reads the M2-3 stored preference
    /// (`AppPreferences.maskDrawBehavior`, key `mask.behavior.default`);
    /// tests inject a constant. View bodies NEVER read UserDefaults —
    /// the resolver is invoked from event handlers only.
    var maskDrawBehaviorResolver: () -> MaskDrawBehavior = {
        AppPreferences().maskDrawBehavior
    }

    /// The one-shot ask-sheet request (`ask` behavior). NOT a persisted
    /// choice — M2-3's semantics is ask-every-completion (no "don't ask
    /// again").
    var pendingMaskBehaviorAsk = false

    /// The completion-time dispatch (M2-3 page semantics: the choice
    /// applies when a drawn mask is COMPLETED). Call AFTER the
    /// interaction's commit landed; `didCommit` false (a no-op tap) is a
    /// silent no-op. Exhaustive, no default arm (纪律 7).
    ///
    ///   currentNode — zero action (the mask stays on its layer);
    ///   newLayer    — the drawn mask migrates to a FRESH layer above
    ///                 (ONE structure item, the source left clean);
    ///   ask         — the one-shot sheet (the move lands ONE item when
    ///                 confirmed; "keep" lands nothing).
    func maskDrawInteractionDidComplete(didCommit: Bool, editorState: EditorState) {
        guard didCommit else { return }
        switch maskDrawBehaviorResolver() {
        case .currentNode:
            break
        case .newLayer:
            if let id = selectedLayerID {
                _ = editorState.migrateMaskToNewLayer(from: id)
            }
        case .ask:
            pendingMaskBehaviorAsk = true
        }
    }

    /// The ask-sheet「移入新层」action — the SAME one-item migration the
    /// newLayer behavior uses (the sheet choice is NOT persisted).
    func confirmMaskBehaviorMove(editorState: EditorState) {
        pendingMaskBehaviorAsk = false
        if let id = selectedLayerID {
            _ = editorState.migrateMaskToNewLayer(from: id)
        }
    }

    // MARK: mask commands (13-3 T5 — the five-command face)

    /// Route a mask command onto the SELECTED layer through EditorState's
    /// EXISTING edit entries. Every command lands EXACTLY ONE history
    /// item (the compound `duplicateAndInvert` is the documented
    /// exception: the structural clone + the inversion flip — TWO items,
    /// two ⌘Z steps, both recorded). No selection → a silent no-op (the
    /// menu disables before this can fire).
    ///
    /// `itemID` is the ITEM-command execution seam (checker M5): the
    /// payload-free `.removeMaskItem` case takes its target here. A nil
    /// id with an item command = a silent no-op (the caller never does).
    func performMaskCommand(
        _ command: MaskCommand, itemID: UUID? = nil, editorState: EditorState
    ) {
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
            // Defensive revision pin (KD-5 dispatch table): the synchronous
            // single-writer leg cannot see a mid-command write on
            // @MainActor — the assert documents the unreachability (release
            // runs the unconditional path; a future async caller must go
            // through the gate instead).
            let expected = copy.mask?.contentRevision
            assert(MaskSpec.matchesExpected(expected, in: copy.mask ?? MaskSpec()))
            var invertedCopy = Self.snapshot(copy)
            invertedCopy.mask = Self.inverted(invertedCopy.mask)
            // The invert variant is a CONTENT WRITE (KD-3 write-point ④):
            // the committed value bumps +1 (nil folds to 0 first).
            invertedCopy.mask?.bumpContentRevision()
            editorState.commitLayerEdit(
                invertedCopy, label: String(localized: "mask_command_duplicateAndInvert"))
        case .fill:
            // Fill = the mask record becomes the EMPTY spec — the
            // constant-1 passthrough of the degenerate triple (the Phase
            // 6 contract). Composite-identical to a full plane with ZERO
            // kernel/GPU involvement (the App layer never calls
            // MaskCombiner.fill — that is a render-time helper).
            // M2-4 (Plan M2-4-2 KD-4, checker E3): fill empties the mask
            // content exactly like clear does (empty spec = constant-1) —
            // a deletionProtected mask refuses BOTH legs.
            if Self.isDeletionProtected(layer) {
                editorState.presentToast(Self.deletionProtectedToast)
                return
            }
            // The committed value carries the revision FORWARD +1 (KD-3
            // write-point ③ — a content rewrite keeps the guard monotonic
            // within the history segment, so a stale in-flight writer's
            // expected value can never re-validate against the new record).
            var copy = Self.snapshot(layer)
            var newMask = MaskSpec()
            newMask.contentRevision = layer.mask?.contentRevision
            newMask.bumpContentRevision()
            copy.mask = newMask
            editorState.commitLayerEdit(
                copy, label: String(localized: "mask_command_fill"))
        case .clear:
            // Clear = NO mask record at all (the chip's empty state).
            // M2-4 (Plan M2-4-2 KD-4): the deletion-protected interception
            // leg — toast + ZERO history item (the mask survives).
            if Self.isDeletionProtected(layer) {
                editorState.presentToast(Self.deletionProtectedToast)
                return
            }
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
        case .addMaskItem:
            // M2-7-2 (KD-3): one default-shaped form + one group item —
            // EXACTLY ONE history item (the write-point-⑤ bump inside).
            Self.addMaskItem(to: layer, tool: activeTool, editorState: editorState)
        case .removeMaskItem:
            // M2-7-2 (KD-3): drop the item (depth-first across nested
            // children), sweep its form when nothing references it, and
            // honor the deletion lock with the EXISTING double-leg toast.
            guard let itemID else { return }
            Self.removeMaskItem(itemID, from: layer, editorState: editorState)
        }
    }

    // MARK: M2-7-2 item commands (KD-3 dispatch table; checker M5 shape)

    /// The default form shape for a panel-add (the current tool's shape;
    /// no armed tool = the ellipse — Alcedo's default mask shape; the
    /// follow-edges tool defaults to the same brush stroke — the walker's
    /// output IS a brush form).
    private static func defaultFormKind(for tool: MaskTool?) -> MaskForm.Kind {
        switch tool {
        case .brush, .eraser, .followEdges, nil:
            .brush(BrushStroke(
                points: [BrushPoint(
                    corner: MaskPoint(x: 0.5, y: 0.5), ctrl1: MaskPoint(x: 0.5, y: 0.5),
                    ctrl2: MaskPoint(x: 0.5, y: 0.5))],
                radius: 0.06, hardness: 0.7, density: 1, opacity: 1))
        case .gradient:
            .gradient(GradientForm(
                anchor: MaskPoint(x: 0.35, y: 0.5), rotationDegrees: 0,
                compression: 0.3, state: .linear))
        case .ellipse:
            .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.2, radiusY: 0.2,
                rotationDegrees: 0, border: 0))
        case .path:
            .path(PathForm(
                nodes: [
                    PathNode(corner: MaskPoint(x: 0.35, y: 0.35), ctrl1: MaskPoint(x: 0.35, y: 0.35), ctrl2: MaskPoint(x: 0.35, y: 0.35)),
                    PathNode(corner: MaskPoint(x: 0.65, y: 0.35), ctrl1: MaskPoint(x: 0.65, y: 0.35), ctrl2: MaskPoint(x: 0.65, y: 0.35)),
                    PathNode(corner: MaskPoint(x: 0.5, y: 0.65), ctrl1: MaskPoint(x: 0.5, y: 0.65), ctrl2: MaskPoint(x: 0.5, y: 0.65)),
                ],
                border: 0))
        }
    }

    /// Add: the default-shaped form joins `drawn.forms` and a group item
    /// (union, visible, opacity 1) joins `drawn.group` (created when the
    /// spec was on the single-form path). One commit, one +1 bump.
    private static func addMaskItem(
        to layer: AdjustmentLayer, tool: MaskTool?, editorState: EditorState
    ) {
        var spec = layer.mask ?? MaskSpec()
        var drawn = spec.drawn ?? DrawnMaskSpec(forms: [])
        let form = MaskForm(kind: defaultFormKind(for: tool))
        drawn.forms.append(form)
        var group = drawn.group ?? MaskGroupSpec(items: [])
        group.items.append(
            MaskGroupItem(formID: form.id, op: .union, inverted: false, opacity: 1))
        drawn.group = group
        spec.drawn = drawn
        spec.bumpContentRevision()
        var copy = snapshot(layer)
        copy.mask = spec
        editorState.commitLayerEdit(
            copy, label: String(localized: "mask_command_addMaskItem"))
    }

    /// Remove: depth-first item drop (nested children included), then the
    /// ORPHAN FORM SWEEP (a form no leaf item references is dead weight —
    /// dt's group semantics keep forms alive only through items). The
    /// deletion lock intercepts with the EXISTING toast (zero history);
    /// a miss (unknown id / no group) is a silent no-op.
    private static func removeMaskItem(
        _ itemID: UUID, from layer: AdjustmentLayer, editorState: EditorState
    ) {
        if isDeletionProtected(layer) {
            editorState.presentToast(deletionProtectedToast)
            return
        }
        guard var spec = layer.mask, var drawn = spec.drawn,
            var group = drawn.group
        else { return }
        guard let remaining = Self.removingItem(itemID, from: group.items) else {
            return
        }
        group.items = remaining
        drawn.group = group
        let referenced = Self.referencedFormIDs(in: group.items)
        drawn.forms.removeAll { !referenced.contains($0.id) }
        spec.drawn = drawn
        spec.bumpContentRevision()
        var copy = snapshot(layer)
        copy.mask = spec
        editorState.commitLayerEdit(
            copy, label: String(localized: "mask_command_removeMaskItem"))
    }

    /// Depth-first item removal: nil = the id matched nothing (miss).
    private static func removingItem(
        _ id: UUID, from items: [MaskGroupItem]
    ) -> [MaskGroupItem]? {
        var changed = false
        var out: [MaskGroupItem] = []
        for var item in items {
            if item.formID == id {
                changed = true
                continue
            }
            if var child = item.child,
                let grandChild = removingItem(id, from: child.items) {
                child.items = grandChild
                item.child = child
                changed = true
            }
            out.append(item)
        }
        return changed ? out : nil
    }

    /// The form ids the tree still references (leaf items only — a child
    /// group's items carry their own leaves).
    private static func referencedFormIDs(in items: [MaskGroupItem]) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in items {
            if item.child == nil { ids.insert(item.formID) }
            if let child = item.child {
                ids.formUnion(referencedFormIDs(in: child.items))
            }
        }
        return ids
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

    // MARK: deletion lock (Plan M2-4-2 KD-4, D-M2-4-CONTEXT-7)

    /// The spec-level deletion lock (v5 optional; nil = unlocked). Only
    /// the two content-CLEARING legs consult it — the command face's sole
    /// unrecoverable writes (grep audit: `LayerEditingState.swift` .fill
    /// `:292` empty-spec + .clear `:298` nil; every other `mask =` touch
    /// is content-producing or a load/undo restore — the DECISIONS table).
    private static func isDeletionProtected(_ layer: AdjustmentLayer) -> Bool {
        layer.mask?.deletionProtected == true
    }

    /// The refusal notice (new UI key — D-M2-4-CONTEXT-11: zh lags, the
    /// close-out batch reconciles the catalog).
    private static var deletionProtectedToast: String {
        String(
            localized: "toast_mask_deletion_protected",
            defaultValue: "This mask is protected and cannot be cleared")
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

    // MARK: hi-res patch + feather session state (Plan M6-4-02, KD-1/KD-3)

    /// The session's LIVE BASE PLANE (M6 落位): the decode-frame-resolution
    /// float plane captured at every successful `.segment` generation
    /// (AIMaskEditing.commitRasterMask's seam — the host stays untouched).
    /// Patch passes compose onto THIS plane; a NEW generation overwrites
    /// it. HELD from the first successful generation until the session
    /// tears down (mode exit / armSegmentSession replace / a new seed / an
    /// image-or-layer identity change at the wire seams — N-1) —
    /// the memory posture (accurate = full-resolution float32 single
    /// channel, ~400 MB magnitude at 100MP, session-held) is the DECISIONS
    /// declaration; UI-STATE ONLY (never the sidecar, never params).
    var livePlane: AIMaskPlane?

    /// The accumulated hi-res detail patches (≤4 — `AIPatchComposer.capped`
    /// FIFO replaces the earliest). The bake recomposes
    /// `compose(livePlane, capped(patches))` fresh each pass, so the FIFO
    /// drop really removes the earliest patch's detail.
    var patches: [AIPatch] = []

    /// The patch-refine state face (the toolbar's refining indicator).
    enum PatchRefineState: Equatable {
        case idle
        case refining
        case done(count: Int)
    }
    var patchState: PatchRefineState = .idle

    /// The Edge feather percent (−100...100, 0 = off) — KD-3's session
    /// value. Positive = the GPU bake seam's radius; negative = the CPU
    /// logit-gain leg (bake radius forced 0 — the double-feather pin).
    /// The next bake (patch pass or re-generate) picks it up; UI state
    /// only, never persisted.
    var featherPercent: Float = 0

    /// The Edge feather in ABSOLUTE px ([0,50], M9-1 T2 / D-M9A-7): the
    /// px-domain panel face. Positive → σ = `AIMaskFeather.sigmaFromPx`
    /// at the bake plane's long edge; 0 → the legacy `featherPercent`
    /// leg above (the negative logit-gain superset stays reachable
    /// through it — the field and both legs are KEPT). UI state only,
    /// never persisted (AI-06).
    var featherPx: Float = 0

    /// The Expand radius in px ([−50,50]; >0 dilate / <0 erode, 0 =
    /// off): the bake seam's morphology pre-pass
    /// (`RasterMaskStore.bake(expandPx:)`, order expand → feather →
    /// quantize — M9-1 T2). UI state only, never persisted (AI-06).
    var expandPx: Int = 0

    /// The 1s debounce handle (KD-1: the last interaction's task wins —
    /// each schedule cancels the previous). The patch pass itself is
    /// `AIMaskEditing.runPatchRefine`.
    var patchDebounceTask: Task<Void, Never>?

    /// The identity the CURRENT patch flow was armed against (M6-4-02
    /// N-1): the image session + the selected layer captured at every
    /// schedule. A mismatch at a consumption seam (the next schedule, or
    /// the debounce fire) means the held face belongs to the PREVIOUS
    /// image/layer — the pass must not bake a mixed-input patch, and the
    /// face releases.
    var patchImageURL: URL?
    var patchLayerID: UUID?

    /// Release the patch-flow transient face (the N-1 release point): the
    /// held live plane, the accumulated patches, and the in-flight debounce
    /// task. `recordSeed`/`armSegmentSession` already reset the same face
    /// for their own flows; this is the switch-driven form (the image or
    /// the layer changed under the armed session — the plane and the
    /// patches belong to the PREVIOUS identity and must not compose onto a
    /// future base).
    func releaseLivePatchState() {
        livePlane = nil
        patches = []
        patchState = .idle
        patchDebounceTask?.cancel()
        patchDebounceTask = nil
    }

    /// The N-1 identity guard: when the CURRENT image/layer differs from
    /// the schedule stamp, the held face belongs to the previous identity —
    /// release it. Called at the wire's two consumption seams (the next
    /// schedule in `AIMaskEditing.commitRasterMask`, the debounce fire in
    /// `AIMaskEditing.runPatchRefine`); nil stamps (a never-scheduled
    /// session) only mismatch against a live image session, releasing an
    /// empty face — a no-op by construction.
    func releaseIfIdentityChanged(imageURL: URL?, layerID: UUID?) {
        if patchImageURL != imageURL || patchLayerID != layerID {
            releaseLivePatchState()
        }
    }

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
    /// and clears the accumulated refine points. The patch face resets
    /// with it: the patches and the held live plane belong to the OLD
    /// subject (M6's release point — a new seed releases the plane until
    /// the next generation captures a fresh one).
    func recordSeed(_ newSeed: AISubjectSeed) {
        guard newSeed != .scribble else { return } // the v1 typed seam
        seed = newSeed
        included = []
        excluded = []
        patches = []
        livePlane = nil
        patchState = .idle
        patchDebounceTask?.cancel()
        patchDebounceTask = nil
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
