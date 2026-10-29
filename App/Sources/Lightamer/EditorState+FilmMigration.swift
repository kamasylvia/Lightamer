import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// EditorState+FilmMigration (Plan M8-3 T3) — the process migration's
// testable pure model (M6-2 §6 挂账正主, D-M8-7's single new-UI exception).
// M9-4 T2 (D-M9SP-7/勘误③): the channel GENERALIZED from the film-only
// gate to a two-source gate — a film record OR non-neutral colorWheels
// params earns the row (both generations share ONE row/ONE action; the
// type/file names keep the historical FilmMigration spelling). The
// marker's two forms live on EditorState.commitProcessMigrationMarker.
//
// The evaluate face is a pure function over the document's stored process,
// the film-record presence, the colorWheels edit presence and the
// in-flight-edit flag: the View never re-derives it (body-evaluation
// discipline — the plan's "禁在 body 求值路径做迁移判定重活" — the model
// computes it and the panel caches the answer through @Observable reads).
//
// The OTHER halves of the migration live at their seams: the carrier flip
// + sidecar write + re-render on PipeCoordinator.runProcessMigration, the
// history marker on EditorState.commitProcessMigrationMarker (both in
// their own files — the App-side file-private members keep those faces
// in-file), and the panel row + confirm sheet on the panels (Film + the
// M9-4 ColorWheels mount).
// ─────────────────────────────────────────────────────────────────────────────

/// The migration row's decision (the table-driven model the tests pin).
enum FilmMigrationAction: Equatable {

    /// The document renders the frozen previous generation (stored <
    /// current) and CAN be migrated to the build's current generation
    /// (`targetRawValue`).
    case migrate(targetRawValue: Int)
    /// The document is already at (or past) the current generation — the
    /// row hides (zero visual delta for current documents).
    case alreadyCurrent
    /// A D-H1 live window is open — migrate later (the unsaved-edit
    /// guard; the panel's confirm sheet is not presented).
    case editingInFlight
    /// No image / no film record AND no colorWheels edit — the process
    /// generation is invisible to the render (both arms render the
    /// identity bit-identically), so there is nothing to migrate.
    case notApplicable

    /// The pure gate (the ONE decision place). `hasColorWheelsEdits`
    /// (M9-4 泛化①) rides with a default false so the M8-3-era call
    /// shapes and tests compile untouched.
    static func evaluate(
        processRawValue: Int?, hasFilmRecord: Bool,
        hasColorWheelsEdits: Bool = false, editingInFlight: Bool,
        currentRawValue: Int = RenderProcessVersion.current.rawValue
    ) -> FilmMigrationAction {
        if editingInFlight { return .editingInFlight }
        guard let processRawValue, hasFilmRecord || hasColorWheelsEdits
        else { return .notApplicable }
        guard processRawValue < currentRawValue else { return .alreadyCurrent }
        return .migrate(targetRawValue: currentRawValue)
    }

    /// The row's visibility face.
    var migratable: Bool {
        if case .migrate = self { return true }
        return false
    }
}
