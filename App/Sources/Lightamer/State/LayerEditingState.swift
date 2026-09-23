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
//   otherwise          → CropOverlayHost owns the viewport
//
// INVARIANT (the mutex contract): at most ONE of the three overlays can
// be active — the routes are an exhaustive if/else-if chain keyed on this
// state, so two gestures can never route simultaneously. The unit tests
// pin the state machine (`PanelWiringTests` layer group).
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

@Observable
@MainActor
final class LayerEditingState {

    // MARK: selection

    /// The currently selected adjustment layer (nil = base/global scope —
    /// the Inspector shows the global chain and the mask tools disable).
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

    /// Brush parameters (stroke-level, v1 — D-06-03-T5-1 keeps density/
    /// hardness per STROKE; the toolbar edits the one brush at a time).
    var brushRadius: Float = 0.06       // normalized WIDTH units
    var brushHardness: Float = 0.7      // 0..1 solid-core fraction
    var brushFlow: Float = 1.0          // per-stamp weight
    var brushOpacity: Float = 1.0       // stroke ceiling multiplier
    var gradientState: GradientState = .linear

    /// The masked layer under edit (drives the overlay host's live legs).
    var maskEditingActive: Bool { selectedLayerID != nil && activeTool != nil }

    /// Arm/disarm a tool. Arming one disarms the others (radio semantics).
    func setTool(_ tool: MaskTool?) {
        activeTool = tool
    }

    // MARK: arbitration (the machine's single decision point)

    /// Which overlay owns the viewport RIGHT NOW. Exactly one answer —
    /// the mutex invariant the tests pin.
    enum ViewportRoute: Equatable, Sendable {
        case maskEditing
        case liquify
        case crop
    }

    func viewportRoute(liquifyPanelSelected: Bool) -> ViewportRoute {
        if maskEditingActive { return .maskEditing }
        if liquifyPanelSelected { return .liquify }
        return .crop
    }
}
