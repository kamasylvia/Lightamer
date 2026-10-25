import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// EditorState+FilmMigration (Plan M8-3 T3) — the process migration's
// testable pure model (M6-2 §6 挂账正主, D-M8-7's single new-UI exception).
//
// The evaluate face is a pure function over the document's stored process,
// the film-record presence and the in-flight-edit flag: the View never
// re-derives it (body-evaluation discipline — the plan's "禁在 body 求值
// 路径做迁移判定重活" — the model computes it and the panel caches the
// answer through @Observable reads).
//
// The OTHER halves of the migration live at their seams: the carrier flip
// + sidecar write + re-render on PipeCoordinator.runProcessMigration, the
// history marker on EditorState.commitProcessMigrationMarker (both in
// their own files — the App-side file-private members keep those faces
// in-file), and the panel row + confirm sheet on FilmPanelView.
// ─────────────────────────────────────────────────────────────────────────────

/// The migration row's decision (the table-driven model the tests pin).
enum FilmMigrationAction: Equatable {

    /// The document renders the frozen density arm (stored ≤ v1) and CAN
    /// be migrated to the build's current generation (`targetRawValue`).
    case migrate(targetRawValue: Int)
    /// The document is already at (or past) the current generation — the
    /// row hides (zero visual delta for v2 documents).
    case alreadyCurrent
    /// A film D-H1 live window is open — migrate later (the unsaved-edit
    /// guard; the panel's confirm sheet is not presented).
    case editingInFlight
    /// No image / no film record — the process generation is invisible to
    /// the render (filmTail nil), so there is nothing to migrate.
    case notApplicable

    /// The pure gate (the ONE decision place).
    static func evaluate(
        processRawValue: Int?, hasFilmRecord: Bool, editingInFlight: Bool,
        currentRawValue: Int = RenderProcessVersion.current.rawValue
    ) -> FilmMigrationAction {
        if editingInFlight { return .editingInFlight }
        guard hasFilmRecord, let processRawValue else { return .notApplicable }
        guard processRawValue < currentRawValue else { return .alreadyCurrent }
        return .migrate(targetRawValue: currentRawValue)
    }

    /// The row's visibility face.
    var migratable: Bool {
        if case .migrate = self { return true }
        return false
    }
}
