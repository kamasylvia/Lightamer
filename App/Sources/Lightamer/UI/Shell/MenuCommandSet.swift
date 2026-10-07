import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MenuCommandSet (Plan M2-3-1 T5, KD-6 / D11 = OQ-11 A) — the menu IA as a
// PURE FUNCTION: (gate, phase) → the set of command ids the menu bar shows.
// This is the single-testable face of the IA consolidation; LightamerApp's
// CommandMenus CONSUME it (each id maps to exactly one Button/Toggle).
//
// THE SESSION DEAD ROUTES (M2LIB-06's registered cleanup): `session.new /
// open / close / import` are the M1 behavior baseline — visible ONLY on the
// gate=true channel (the env opt-back), byte-identical there; on the new
// shell (gate=false) they are REMOVED (their keyboard slots yield to the new
// commands per the D11 conservative table).
//
// VISIBILITY ≠ ENABLEMENT: the set answers "does the item exist in the
// menu". Phase-dependent enablement (e.g. ⌘W only means something in the
// editor) stays the app layer's business — P1 visibility is phase-independent
// and the matrix asserts exactly that.
// ─────────────────────────────────────────────────────────────────────────────

/// One menu command identity (stable string — the test matrix and the
/// LightamerApp mapping both quote these).
enum MenuCommandID: String, CaseIterable, Sendable {
    // The Session dead routes (gate=true only — the M1 baseline).
    case sessionNew = "session.new"
    case sessionOpen = "session.open"
    case sessionClose = "session.close"
    case sessionImport = "session.import"

    // The project lifecycle (gate=false; the M2-2-2 command circuit).
    case projectNew = "project.new"
    case projectOpen = "project.open"
    case projectRecent = "project.recent"
    case projectImportFolder = "project.importFolder"
    case projectBackup = "project.backup"
    case projectMove = "project.move"

    // The two-workspace circuit (gate=false).
    case workspaceEnterEditor = "workspace.enterEditor"
    case workspaceBackToLibrary = "workspace.backToLibrary"

    // The global search dialog (gate=false; ⌘F — presentation state = the
    // WorkspaceModel.isSearchDialogPresented seam, P2 renders the dialog).
    case librarySearch = "library.search"

    // The editor-shell visibility toggles (gate=false placeholders until P3).
    case viewToolRail = "view.toolRail"
    case viewScopes = "view.scopes"
    case viewAdjustmentStack = "view.adjustmentStack"

    // The Copy Adjustments transfer dialog (gate=false; M2-8-2 T3 — the
    // editor-scoped enablement is the app layer's business, as everywhere).
    case editCopyAdjustments = "edit.copyAdjustments"
}

enum MenuCommandSet {

    /// The session dead routes (the gate=true-only family).
    static let sessionRoutes: Set<MenuCommandID> = [
        .sessionNew, .sessionOpen, .sessionClose, .sessionImport,
    ]

    /// The gate=false command family (project + workspace + search + view
    /// + the M2-8-2 transfer dialog).
    static let newShellRoutes: Set<MenuCommandID> = [
        .projectNew, .projectOpen, .projectRecent, .projectImportFolder,
        .projectBackup, .projectMove,
        .workspaceEnterEditor, .workspaceBackToLibrary,
        .librarySearch,
        .viewToolRail, .viewScopes, .viewAdjustmentStack,
        .editCopyAdjustments,
    ]

    /// The KD-6 pure function: gate × phase → the visible command ids.
    /// P1 visibility is phase-independent (enablement is the app layer's);
    /// the phase parameter is the IA's future seam and the matrix asserts
    /// the independence.
    static func visibleCommandIDs(gate: Bool, phase: AppPhase) -> Set<MenuCommandID> {
        if gate {
            // The M1 behavior baseline — the Session dead routes stand,
            // nothing of the new IA shows.
            return sessionRoutes
        }
        return newShellRoutes
    }
}
