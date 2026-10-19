import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ShellGraph (F0P-01 T4 — the untracked-read gap 3a lift + the shell's
// value-type state box).
//
// The value-type state that crosses the view-tree boundary (written by the
// NSMenu action closures and the shell from outside the hosted tree; read
// inside it through @Observable registration). The per-session rebuilt
// optionals ride the same box: in the flipped shell the root face re-reads
// the box per body evaluation. The spike's 9-field graph + the 10th field
// `columnVisibility` (gap 3a — lifted from ContentView's local @State so
// the View-menu ⌥⌘S/⌥⌘I closures can write it after the flip).
//
// Instance single-source (review M2's three-way ruling, DECISIONS): ONE
// process-global instance (`ShellGraph.shared`). The face assembly,
// ContentView's binding bridge and the menu closures consume the same
// object — the double-instance silent failure (menu writes A, view reads
// B → the column toggles stay visually dead) is structurally excluded.
// Simple `static let` (no NSLock/replaceShared — no hot-swap requirement;
// the LutLibraryStore.shared precedent's lock face exists for its Settings
// root swap, which has no analogue here).
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class ShellGraph {

    /// The single instance (review M2 ruling (a) — the shared-singleton
    /// form; see the file header). MainActor-isolated with the class (the
    /// Swift 6 global-actor rule: a non-Sendable class cannot back a plain
    /// static global — every consumer here is MainActor anyway: the view
    /// bodies, the @MainActor bridge controller and the shell).
    static let shared = ShellGraph()

    var libraryImportRequest: ImportFlowRequest?
    var libraryImportChoice = ImportModeChoice(mode: .copy, remember: false)
    var libraryWelcomePresented = false
    var pastePartialRequested = false
    var adjustmentTransferPresented = false
    var lastLaunchWasUnclean = false
    var thumbnailProvider: SessionThumbnailProvider?
    var catalogThumbnailRouter: CatalogThumbnailRouter?
    var batchSidecarWriter: BatchSidecarWriter?

    /// F0P-01 T4 (gap 3a): the split-view column visibility, lifted from
    /// ContentView's local @State. Default `.all` — the exact pre-lift
    /// initial value (behavior equivalence: reads/writes/toggle map
    /// point-for-point; the onAppear layout-memory restore still overwrites
    /// it per the D-08 discipline). Post-flip, the View-menu ⌥⌘S/⌥⌘I
    /// closures write THIS field (toggleSidebar/toggleInspector semantics
    /// translated verbatim).
    var columnVisibility: NavigationSplitViewVisibility = .all

    /// F0P-01 T6 (review M1): the ContentView toolbar preset-manager
    /// request — after the flip the SwiftUI scene registry is absent, so
    /// `openWindow` would silently no-op; the toolbar button writes this
    /// field instead and the shell face observes + consumes it (the window
    /// controller's showWindow), resetting the flag. The request-field +
    /// face-side-consumption shape (the DECISIONS review-M1 ruling).
    var presetManagerRequested = false
}
