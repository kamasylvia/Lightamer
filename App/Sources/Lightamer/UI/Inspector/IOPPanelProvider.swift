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

    init(coordinator: PipeCoordinator) {
        self.coordinator = coordinator
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
        Task { await coordinator?.setLiveParams(snapshot) }
    }

    /// Drag END: exactly ONE HistoryItem + the sidecar throttle write.
    func endEditing(label: String) {
        Task { await coordinator?.commitContinuousEdit(label: label) }
    }

    /// Discrete control semantics (double-click reset, preset pick,
    /// eyedropper apply): ONE commit per click, compressed trio.
    func applyDiscrete(_ snapshot: ModuleInstance, label: String) {
        coordinator?.beginContinuousEdit()
        Task {
            await coordinator?.setLiveParams(snapshot)
            await coordinator?.commitContinuousEdit(label: label)
        }
    }

    /// Full-image per-channel min/max over the LINEAR chain (the filmic
    /// auto black/white keys' picked_color_min/max statistics, Plan
    /// 03-06-T5). nil when nothing is loaded or the render failed.
    func sampleNormMinMax() async -> (min: simd_float3, max: simd_float3)? {
        await coordinator?.sampleLinearNormMinMax()
    }
}

/// Shared helpers for the concrete panels.
@MainActor
enum PanelEditing {

    /// Re-parameterize an instance record with a new typed Params value
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
