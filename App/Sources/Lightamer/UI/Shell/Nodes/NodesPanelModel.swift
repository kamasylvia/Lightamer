import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// NodesPanelModel (Plan M2-4-3 T1, KD-2) — the node panel's view model: the
// PipelineDocument PROJECTION + the selection write side + the command
// router. The graph view stays a pure dumb renderer (KD-2).
//
// CONSISTENCY FACE (the KD-2 必答): the model caches NO projection
// semantics — `document` is a per-read pure derivation over the OBSERVED
// `editorState.layerStack` (a computed property, so the @Observable graph
// re-derives it on every stack change; zero staleness is structural, and
// the plan's "rebuild on stack change" is satisfied per read — recorded as
// D-M2-4-3-2). The selection is the model's ONLY owned state, and its
// write side is the EXISTING `LayerEditingState.selectedLayerID`
// arbitration point — never a second selection truth (D-M2-4-CONTEXT-9).
//
// mix legs (KD-2): the slider rides the EXISTING Phase-6 live/commit pair —
// `applyLiveLayer` (zero history) during the drag + `commitLayerEdit`
// (EXACTLY one history item) at drag end with the `history_graph_mix`
// label. The `setGradeMix` COMMAND still routes through `apply` (menu /
// future batch consumers); the slider is its live/commit incarnation — the
// math equivalence (mix 0 ≡ bypass) is pinned by M2-4-1 AC2.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class NodesPanelModel {

    private let editorState: EditorState
    private let editingState: LayerEditingState
    /// The film card's data face (M3-3-03 T4, KD-4): the coordinator's
    /// carrier/store read faces. Optional (tests, pre-assembly) — nil = the
    /// film card never projects.
    private weak var pipeCoordinator: PipeCoordinator?

    /// The model's only owned state: the highlighted node (nil = nothing
    /// highlighted). The TAB scope rides `editingState.selectedLayerID`
    /// (written by `select`, read by the seven-tab face).
    private(set) var selectedNodeID: UUID?

    init(
        editorState: EditorState, editingState: LayerEditingState,
        pipeCoordinator: PipeCoordinator? = nil
    ) {
        self.editorState = editorState
        self.editingState = editingState
        self.pipeCoordinator = pipeCoordinator
    }

    // MARK: The read-only Film projection card (M3-3-03 T4, KD-4)

    /// One read-only Film card's data face: the material pair's display
    /// names + the active state. NOT a PipelineDocument node — no id in the
    /// selection space, no commands, no history face (the M2-4 semantics
    /// zero-diff guarantee); the card's tap routes to the Film page.
    struct FilmCardProjection: Equatable {
        let filmName: String
        let paperName: String
        let isActive: Bool
    }

    /// The projection: present whenever an image is open (the card always
    /// shows, projecting the INACTIVE face when no film record exists);
    /// nil without an image / coordinator.
    var filmCard: FilmCardProjection? {
        guard let coordinator = pipeCoordinator,
            coordinator.liveImageURL != nil
        else { return nil }
        guard let record = coordinator.currentFilmRecord,
            !record.filmStock.isEmpty || !record.paperStock.isEmpty
        else {
            return FilmCardProjection(filmName: "", paperName: "", isActive: false)
        }
        func name(_ stockId: String) -> String {
            guard !stockId.isEmpty,
                let profile = coordinator.filmMaterialStore?.profile(id: stockId)
            else { return stockId }
            return profile.info.name ?? stockId
        }
        return FilmCardProjection(
            filmName: name(record.filmStock), paperName: name(record.paperStock),
            isActive: true)
    }

    // MARK: The projection (KD-2 — per-read pure derivation)

    /// The read-only node-graph document, re-derived on every read from the
    /// observed stack (nil = no image loaded). Reading this from a view
    /// body registers the layerStack observation dependency — SwiftUI
    /// re-renders the panel on every stack change with zero manual sync.
    var document: PipelineDocument? {
        editorState.layerStack.map(PipelineDocument.init)
    }

    // MARK: Selection (the P2 linkage seam's write side)

    /// Select a node (nil = clear). A GRADE routes the tab scope through
    /// the existing `selectedLayerID` (D-M2-4-CONTEXT-9: the seven tabs
    /// then edit that layer); develop/drt/nil keep the global-chain face
    /// (`selectedLayerID` = nil — the unselected behavior verbatim).
    func select(_ id: UUID?) {
        selectedNodeID = id
        guard let id else {
            editingState.select(nil)
            return
        }
        if document?.node(for: id)?.kind == .grade {
            editingState.select(id)
        } else {
            editingState.select(nil)
        }
    }

    /// Clear the highlight when its node left the graph (a structural undo
    /// removing the selected grade). The layer-scope dangling heal stays
    /// with the EXISTING `LayerEditingState` machinery — this only prunes
    /// the panel's own highlight (no forced writes on other surfaces).
    func pruneSelection() {
        guard let selectedNodeID,
            let document,
            document.node(for: selectedNodeID) == nil
        else { return }
        self.selectedNodeID = nil
    }

    // MARK: The command router (KD-2 — the thin forwarding shell)

    /// Route a graph command through the ONE execution entry
    /// (`EditorState.apply` — the toast/error face lives THERE: silent
    /// interception for locked endpoints, the D-26 toast for every other
    /// typed failure). Panels are pure producers and never switch on
    /// commands (the M2-4-1 layering note).
    func apply(_ command: NodeGraphCommand) {
        editorState.apply(command)
    }

    // MARK: The lock face (D-M2-4-CONTEXT-7)

    /// develop/drt are structurally locked (the P1 projection's
    /// `isDeletionLocked`); grades are never locked in v1 (the per-grade
    /// lock is an M2-7 shape). Unknown ids answer false (nothing to lock).
    func isLocked(_ id: UUID) -> Bool {
        document?.node(for: id)?.isDeletionLocked ?? false
    }

    /// The locked-card hint (the lock badge's tap feedback — the Alcedo
    /// `LockedNodeMaskPromptDialog` semantics as a toast, copy self-written
    /// per D-M2-4-CONTEXT-7). Grades/unknown never hint (not locked).
    func lockHint(_ id: UUID) {
        switch document?.node(for: id)?.kind {
        case .develop:
            editorState.presentToast(
                String(
                    localized: "node_lock_develop",
                    defaultValue: "The Develop node is locked"))
        case .displayTransform:
            editorState.presentToast(
                String(
                    localized: "node_lock_drt",
                    defaultValue: "Display Transform is a fixed endpoint"))
        case .grade, nil:
            break
        }
    }

    // MARK: The mix legs (KD-2 — the Phase-6 live/commit pair)

    /// The drag leg: swap the layer's opacity in place, ZERO history (the
    /// composite re-renders live through the existing stack reassignment).
    func setMixLive(_ mix: Float, nodeID: UUID) {
        guard let current = editorState.adjustmentLayer(id: nodeID) else { return }
        editorState.applyLiveLayer(Self.snapshot(current, opacity: mix))
    }

    /// The drag-end leg: EXACTLY ONE structure history item with the
    /// `history_graph_mix` label (the same localization key the command
    /// face uses — same resolution, any locale).
    func commitMix(_ mix: Float, nodeID: UUID) {
        guard let current = editorState.adjustmentLayer(id: nodeID) else { return }
        editorState.commitLayerEdit(
            Self.snapshot(current, opacity: mix),
            label: String(
                localized: "history_graph_mix",
                defaultValue: "Adjust color grade mix"))
    }

    /// The VALUE copy with the SAME identity (Layer is a class — the
    /// snapshot shape every sibling mutator uses), opacity clamped 0...1
    /// (the D5 clamp, the command face's own bound).
    private static func snapshot(_ layer: AdjustmentLayer, opacity: Float)
        -> AdjustmentLayer
    {
        AdjustmentLayer(
            id: layer.id, name: layer.name, isVisible: layer.isVisible,
            opacity: min(max(opacity, 0), 1), blendMode: layer.blendMode,
            blendOptions: layer.blendOptions, enabled: layer.enabled,
            chain: layer.chain, mask: layer.mask)
    }
}
