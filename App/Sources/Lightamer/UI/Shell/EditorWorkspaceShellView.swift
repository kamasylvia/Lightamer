import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// EditorWorkspaceShellView (Plan M2-3-1 T2 skeleton → M2-3-3 T1 FILL, KD-1) —
// the editor workspace's three-section layout:
//
//   [ tool rail | vertical filmstrip | VIEWPORT (hero) | scopes + stack ]
//
// The zone order is the Alcedo `EditorWorkspace.qml` non-negotiable comment
// ("tool rail left, viewport center, scopes + adjustment stack right") with
// THE USER REVISION: the filmstrip rides the editor's LEFT edge as a vertical
// strip beside the tool rail (the project's signature deviation from Alcedo's
// bottom strip). Rail expansion PUSHES THE VIEWPORT ONLY — the filmstrip
// column keeps its width (the KD-1 push-semantics mapping).
//
// The CENTER is the existing `EditorAreaView` mounted AS A CHILD — viewport,
// gestures, overlays, the two-tier busy, the FIT readout and the ZoomHUD all
// keep their behavior (KD-1: packaging, never rewriting; the M2-2-4 legacy
// gate snapshot check (the T1 first step) confirmed the editor domain is
// OUTSIDE every frozen identifier set, DECISIONS D1).
// ─────────────────────────────────────────────────────────────────────────────

struct EditorWorkspaceShellView: View {

    /// The shell routing state (the P1 seam: phase + editor face + the P3
    /// collection seam + the View-menu visibility toggles).
    let workspace: WorkspaceModel
    /// The filmstrip's thumbnail bridge (owned by the host; nil = no
    /// project / no bridge).
    let bridge: LibraryThumbnailBridge?

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    /// The filmstrip column width (the P1 slot budget).
    private static let filmstripWidth: CGFloat = 148
    /// The right pane width (scopes + adjustment stack, the Alcedo trailing
    /// column).
    private static let rightPaneWidth: CGFloat = 280

    var body: some View {
        HStack(spacing: 0) {
            // LEFT ①: the tool rail (History/Versions/Nodes) — expands by
            // pushing the viewport (the filmstrip width is constant).
            if workspace.toolRailVisible {
                EditorToolRailView()
            }
            // LEFT ②: the vertical filmstrip (the user revision) — the SAME
            // collection cursor as the P2 grid (KD-3, zero collection-state
            // copying); selection is the grid state machine's.
            filmstrip
                .frame(width: Self.filmstripWidth)
                .background(ThemeTokens.cardSurface)
                .overlay(
                    Rectangle()
                        .fill(ThemeTokens.cardBorder)
                        .frame(width: 1),
                    alignment: .trailing
                )

            // CENTER: the viewport hero — the existing EditorAreaView child
            // (zero behavior migration; the shell wraps, never rewrites).
            EditorAreaView(
                decoder: workspace.editorDecoder,
                metalContext: pipeCoordinator.detectionMetal())
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // RIGHT: the scopes + adjustment stack column (the Alcedo
            // trailing edge). T1 mounts the slots; T2 fills the stack, T3
            // fills the scope panel.
            rightPane
                .frame(width: Self.rightPaneWidth)
                .background(ThemeTokens.cardSurface)
                .overlay(
                    Rectangle()
                        .fill(ThemeTokens.cardBorder)
                        .frame(width: 1),
                    alignment: .leading
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeTokens.windowBackground)
        .accessibilityIdentifier("shell.editor.workspace")
        // The current-image load leg (T1 action 3): the editor face's
        // current id resolves through the collection seam into the ONE
        // decode request chain (EditorState.load — the D-X1 render
        // producer stays the coordinator's).
        .task(id: workspace.editorPhase.currentImageID) {
            await loadCurrentImage()
        }
        // The filmstrip click → current-image switch (T1 action 4): the
        // strip routes selection through the GRID state machine; the shell
        // maps a single-selection change onto the editor face (same source,
        // no second selection truth).
        .onChange(of: workspace.editorGrid?.selectedIDs) { _, selected in
            guard workspace.phase == .editor,
                let selected,
                selected.count == 1,
                let id = selected.first,
                id != workspace.editorPhase.currentImageID else { return }
            workspace.editorGrid?.openCurrent(id)
            workspace.updateEditorPhase { $0.currentImageID = id }
        }
    }

    // MARK: - Left ②: the filmstrip

    @ViewBuilder
    private var filmstrip: some View {
        if let grid = workspace.editorGrid {
            FilmstripView(grid: grid, bridge: bridge, onOpen: { id in
                // Already in the editor: a strip activation just switches
                // the current image (the single-tap leg did the select).
                if id != workspace.editorPhase.currentImageID {
                    workspace.updateEditorPhase { $0.currentImageID = id }
                }
            })
        } else {
            Text(String(
                localized: "shell_editor_filmstrip_empty",
                defaultValue: "Filmstrip arrives with the library"))
                .font(.caption2)
                .foregroundStyle(ThemeTokens.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("shell.editor.filmstrip.slot")
        }
    }

    // MARK: - Right: scopes + adjustment stack

    private var rightPane: some View {
        VStack(spacing: 0) {
            if workspace.scopesVisible {
                scopeSlot
                Divider()
            }
            if workspace.adjustmentStackVisible {
                stackSlot
            } else if workspace.scopesVisible {
                // At least one pane keeps the column alive.
                Color.clear
            }
        }
    }

    /// The T3 scope panel (the GPU-backed histogram/waveform; the
    /// mount/unmount IS the tap visibility gate).
    private var scopeSlot: some View {
        ScopePanelView()
    }

    /// The T2 adjustment stack (the seven-tab routing over the existing
    /// panel registry — the M1 panels instantiate untouched).
    private var stackSlot: some View {
        EditorAdjustmentStackView(workspace: workspace)
    }

    // MARK: - The current-image load leg

    /// Resolve the editor face's current id through the collection seam
    /// and route it into `EditorState.load` (the唯一 decode request chain).
    /// A row whose source file cannot be resolved keeps the previous
    /// frame (the typed resolver answers nil — no path guessing here).
    private func loadCurrentImage() async {
        guard let row = workspace.currentRow,
            let url = workspace.editorURLResolver?(row) else { return }
        guard editorState.loadedImageURL != url else { return }
        editorState.load(
            url: url,
            decoder: workspace.editorDecoder,
            metal: pipeCoordinator.detectionMetal(),
            logger: EditorState.decodeLogger,
            overrides: workspace.rawDecodeOverrides(for: url))
    }
}
