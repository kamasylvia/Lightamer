import LightamerCore
import simd
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// D-T6 Inspector panel framework (Plan 03-02-T3) — the seam between the
// ModuleRegistry/iop world and the SwiftUI Inspector column.
//
// Data flow per UI interaction (RESEARCH §7, D-H1 three-part API):
//
//   Slider drag begin → InspectorEditSession.beginEditing()
//                       → PipeCoordinator.beginContinuousEdit()
//   Slider tick      → new ModuleInstance (same instanceID, new params)
//                       → session.update(snapshot)
//                       → PipeCoordinator.setLiveParams (0 history items,
//                         PREVIEW re-render only)
//   Slider drag end  → session.endEditing(label:)
//                       → PipeCoordinator.commitContinuousEdit
//                       → exactly ONE HistoryItem + sidecar throttle write
//   Discrete click   → session.applyDiscrete(snapshot, label:)
//                       (begin + update + commit compressed — still exactly
//                       one item, D-H1 "离散控件一次一 commit")
//
// UI red lines (D-X1): panels NEVER touch `displayTexture` — they only
// produce instance records; the coordinator stays the single render
// producer. Panel values READ from `EditorState.instances` records
// (`ModuleInstance.params(of:)`), never from pipe-side boxes.
//
// Design deviation from the RESEARCH §7 sketch (recorded): the provider
// consumes the `ModuleInstance` RECORD instead of a `ModuleBox<M>` — the
// records are the canonical state the D-H1 API mutates and the 02-05
// materialization owns the boxes privately inside the coordinator; a
// provider that reached for a box would bypass the history layer.
// ─────────────────────────────────────────────────────────────────────────

/// One panel factory per iop. Registered into `InspectorState` at app
/// launch; dispatch is by `opName` (the registry key).
@MainActor
protocol IOPPanelProvider: Sendable {

    /// The iop this panel edits (`IOPModule.opName`).
    var opName: String { get }

    /// Build the panel view for the CURRENT instance record.
    /// `instance` is guaranteed to have `opName == self.opName`.
    @ViewBuilder
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView
}

/// The panel-facing façade over the D-H1 three-part API, scoped to one
/// editing interaction. Stateless besides the coordinator reference — the
/// history/instance truth lives in `EditorState`/`PipeCoordinator`.
@MainActor
final class InspectorEditSession {

    private weak var coordinator: PipeCoordinator?

    /// 06-05 layer routing: nil = image-global (the Phase 2-5 shape);
    /// a layer UUID = every edit lands in that adjustment layer's chain
    /// (the `layerScope`-型 history item). The D-H1 semantics are
    /// IDENTICAL across scopes (live ticks without history; exactly one
    /// commit per drag end) — the 24 panels stay untouched.
    private let layerScope: UUID?

    init(coordinator: PipeCoordinator, layerScope: UUID? = nil) {
        self.coordinator = coordinator
        self.layerScope = layerScope
    }

    /// Drag START: open the continuous-edit window (zero history items
    /// until the commit).
    func beginEditing() {
        coordinator?.beginContinuousEdit()
    }

    /// Drag TICK: live preview without history. Fire-and-forget Task — the
    /// render is the coordinator's business (generation newest-wins
    /// collapses storms).
    func update(_ snapshot: ModuleInstance) {
        Task { [coordinator, layerScope] in
            await coordinator?.setLiveParams(snapshot, layerID: layerScope)
        }
    }

    /// Drag END: exactly ONE HistoryItem + the sidecar throttle write.
    func endEditing(label: String) {
        Task { [coordinator, layerScope] in
            await coordinator?.commitContinuousEdit(
                label: label, layerScope: layerScope)
        }
    }

    /// Discrete control semantics (double-click reset, preset pick,
    /// eyedropper apply): ONE commit per click, compressed trio.
    /// `autoEnable = false` preserves an explicit enabled=false (the
    /// 04-08-T4 row toggle-OFF path — the coordinator's GUI-7 flip must
    /// not resurrect it; D-08-T3-2).
    ///
    /// 04-08-F3 root-cause fix: the Task captures the COORDINATOR, not
    /// `self`. `InspectorView.row()` calls this on a TEMPORARY session
    /// (`InspectorEditSession(coordinator:).applyDiscrete(...)`) — the
    /// old `Task { [weak self] }` found `self == nil` and silently did
    /// nothing (AXPress/click arrived at the Button fine; the commit died
    /// inside). Panels keep their session in `let edit` (lifetime = view
    /// lifetime) so they never noticed. Capturing the coordinator value
    /// directly keeps this correct for both call shapes with no lifetime
    /// coupling to the session object.
    func applyDiscrete(_ snapshot: ModuleInstance, label: String, autoEnable: Bool = true) {
        coordinator?.beginContinuousEdit()
        Task { [coordinator, layerScope] in
            await coordinator?.setLiveParams(snapshot, layerID: layerScope)
            await coordinator?.commitContinuousEdit(
                label: label, autoEnable: autoEnable, layerScope: layerScope)
        }
    }

    /// 04-08-F3 test seam: the same discrete trio as `applyDiscrete`, but
    /// `await`ed inline so PanelWiringTests asserts post-commit state
    /// without sleeping on the fire-and-forget Task. Production callers
    /// keep using `applyDiscrete` (unchanged fire-and-forget timing).
    func applyDiscreteForTest(
        _ snapshot: ModuleInstance, label: String, autoEnable: Bool = true
    ) async {
        coordinator?.beginContinuousEdit()
        await coordinator?.setLiveParams(snapshot, layerID: layerScope)
        await coordinator?.commitContinuousEdit(
            label: label, autoEnable: autoEnable, layerScope: layerScope)
    }

    /// Full-image per-channel min/max over the LINEAR chain (the filmic
    /// auto black/white keys' picked_color_min/max statistics, Plan
    /// 03-06-T5). nil when nothing is loaded or the render failed.
    func sampleNormMinMax() async -> (min: simd_float3, max: simd_float3)? {
        await coordinator?.sampleLinearNormMinMax()
    }

    /// The decoded source image for auto-detect (04-03 ashift horizon /
    /// rectangle): read-only, zero pipe involvement (the panel renders a
    /// small probe — no pipe-plane readback, L014-clean by construction).
    func detectionSourceImage() -> DecodedImage? {
        coordinator?.detectionSourceImage()
    }

    /// Raise a non-blocking global toast (D-26 background grading — the
    /// 04-08-T2 GUI-8 fix: auto-detect nil/failure must be USER-VISIBLE
    /// beyond the panel's local notice; the acceptance round only watched
    /// the status bar).
    func presentToast(_ message: String) {
        coordinator?.presentToast(message)
    }
}

/// Shared helpers for the concrete panels.
@MainActor
enum PanelEditing {
    /// (same UUID/iopOrder — the D-H4 hash flips through `setParams`).
    static func updated<M: IOPModule>(
        _ instance: ModuleInstance, params: M.Params, as type: M.Type
    ) -> ModuleInstance? {
        var record = instance
        do {
            try record.setParams(params, as: type)
            return record
        } catch {
            AppError.logger.error(
                "panel re-encode failed for \(instance.opName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Read the typed params of an instance record (nil on decode failure —
    /// e.g. a foreign/legacy payload; the panel then shows defaults).
    static func params<M: IOPModule>(of instance: ModuleInstance, as type: M.Type) -> M.Params? {
        try? instance.params(of: type)
    }
}
