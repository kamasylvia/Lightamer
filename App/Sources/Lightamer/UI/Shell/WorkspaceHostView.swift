import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// WorkspaceHostView (Plan M2-3-1 T2, KD-2 / D2) — the gate=false shell ROOT:
// the single window's two-phase router. `library` renders the library face
// (P1 = the M2-2-4 ProjectWorkspaceFace container; the P2 grid/Inspector
// build inside it), `editor` renders the editor skeleton. The switch is
// EXHAUSTIVE with no default (the AppPhase discipline), and the swap rides
// the Alcedo collapse semantics — a ~200ms opacity+offset transition, no
// per-frame simulation.
//
// State ownership: the host OWNS its WorkspaceModel (`@State` — the shell
// state lives as long as the window). The T5 menu commands reach it through
// the focused-value bridge published below.
// ─────────────────────────────────────────────────────────────────────────────

/// The focused-value bridge: the App scene's menu commands (T5) read the
/// window's WorkspaceModel through this key — the same plumbing shape as the
/// column-visibility and export-request bindings above it.
internal struct WorkspaceModelKey: FocusedValueKey {
    typealias Value = WorkspaceModel
}

internal extension FocusedValues {
    var lightamerWorkspaceModel: WorkspaceModel? {
        get { self[WorkspaceModelKey.self] }
        set { self[WorkspaceModelKey.self] = newValue }
    }
}

struct WorkspaceHostView: View {

    /// The project lifecycle face (passed through to the library face; nil =
    /// the no-project state).
    let projectController: LibraryProjectController?
    let onImportFolder: () -> Void

    @State private var workspace = WorkspaceModel()

    // Plan M2-3-1 T6 (M2UIW-06): the background-task faces — ONE registry
    // behind BOTH presentations (bar + dialog), the import leg riding the
    // read-only ImportTaskAdapter subscription.
    @State private var taskRegistry = BackgroundTaskRegistry()
    @State private var isTaskDialogPresented = false
    @State private var importAdapter: ImportTaskAdapter?

    // Plan M2-3-2 T1 (KD-1): the library surface the grid renders from —
    // rebuilt on project open/close/move (the queries ride the OPEN store;
    // the bridge rides the package's `.<stem>.lathumbs/` directory). The
    // grid model is the P1 collection single-source; the host only builds
    // and wires it.
    @State private var gridModel: LibraryGridModel?
    @State private var thumbnailBridge: LibraryThumbnailBridge?

    /// The content-face markers this host renders (the test surface, the
    /// ContentView.visibleContentFaceMarkers precedent). The gate=true face
    /// is ContentView's business — the host only ever renders gate=false.
    nonisolated static func faceMarkers() -> Set<String> {
        [
            ThemeTokens.Markers.workspaceHost,
            ThemeTokens.Markers.projectWorkspace,
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                switch workspace.phase {
                case .library:
                    libraryFace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                case .editor:
                    EditorWorkspaceShellView(workspace: workspace)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: workspace.phase)
            // The background-task bottom bar (T6 — present while tasks run).
            BackgroundTaskBarView(
                registry: taskRegistry,
                isDialogPresented: $isTaskDialogPresented)
        }
        .background(ThemeTokens.windowBackground)
        .accessibilityIdentifier(ThemeTokens.Markers.workspaceHost)
        .focusedSceneValue(\.lightamerWorkspaceModel, workspace)
        // The task-dialog host (the SAME registry — dual presentation).
        .sheet(isPresented: $isTaskDialogPresented) {
            BackgroundTaskDialogHost(
                registry: taskRegistry,
                isPresented: $isTaskDialogPresented)
        }
        // The import-leg subscription (checker E3): a READ-ONLY observation
        // of the controller's importProgress publication. The adapter
        // mirrors it into the registry; the run's end (nil) finishes the
        // task. The controller itself is never touched.
        .onChange(of: projectController?.importProgress) { _, progress in
            guard let controller = projectController else { return }
            if progress != nil {
                if importAdapter == nil {
                    let adapter = ImportTaskAdapter(controller: controller)
                    taskRegistry.register(adapter)
                    importAdapter = adapter
                }
                importAdapter?.apply(progress)
            } else if let adapter = importAdapter {
                taskRegistry.finish(id: adapter.id)
                importAdapter = nil
            }
        }
        .onChange(of: projectController?.projectURL) { _, _ in
            rebuildLibrarySurface()
        }
        .onAppear {
            rebuildLibrarySurface()
        }
    }

    // MARK: - Library face (Plan M2-3-2 T1, KD-1: 左网格 + 右 Inspector 槽位;
    // T2 fills the right pane — the fixed-width slot below is its mount)

    @ViewBuilder
    private var libraryFace: some View {
        if let gridModel {
            HStack(spacing: 0) {
                LibraryGridView(
                    grid: gridModel,
                    bridge: thumbnailBridge,
                    onOpen: { id in
                        // The D2 真缝: the grid's current-image bookkeeping
                        // plus the routing transition (current image →
                        // EditorPhaseState + the lossless library snapshot).
                        gridModel.openCurrent(id)
                        workspace.openEditor(imageID: id)
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The T2 Album Inspector mount (fixed-width tier).
                VStack(spacing: 6) {
                    Text(String(
                        localized: "shell_library_inspector_arrives",
                        defaultValue: "Album Inspector arrives with M2-3/P2"))
                        .font(.caption2)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(6)
                }
                .frame(width: 280)
                .frame(maxHeight: .infinity)
                .background(ThemeTokens.cardSurface)
                .overlay(
                    Rectangle()
                        .fill(ThemeTokens.cardBorder)
                        .frame(width: 1),
                    alignment: .leading)
                .accessibilityIdentifier("shell.library.inspector.slot")
            }
        } else {
            // The no-project state keeps the M2-2-4 container verbatim
            // (welcome / import entry).
            ProjectWorkspaceFace(
                controller: projectController,
                onImportFolder: onImportFolder)
        }
    }

    /// Build (or drop) the grid + bridge for the OPEN project. Called on
    /// appear and on every projectURL change (open / create / move — the
    /// controller's own publication face; no controller code touched).
    private func rebuildLibrarySurface() {
        guard let controller = projectController,
            let store = controller.projectStore,
            let packageURL = controller.projectURL else {
            gridModel = nil
            thumbnailBridge = nil
            return
        }
        let directory = packageURL.deletingLastPathComponent()
        let stem = packageURL.deletingPathExtension().lastPathComponent
        let thumbsDirectory = directory.appendingPathComponent(
            LibrarySchema.thumbsDirectoryName(stem: stem))
        // The source-URL resolver: the row's three-form path carrier through
        // the Core ImageLinker (zero path guessing in the shell).
        let resolve: LibraryThumbnailBridge.URLResolver = { row in
            guard let kind = LibrarySchema.PathKind(rawValue: row.pathKind) else {
                return nil
            }
            if case .resolved(let url) = ImageLinker.resolve(
                imagePath: row.imagePath,
                pathKind: kind,
                volumeUUID: row.volumeUUID,
                projectDirectory: directory) {
                return url
            }
            return nil
        }
        let bridge = LibraryThumbnailBridge(
            thumbsDirectory: thumbsDirectory, renderLeg: nil, resolveURL: resolve)
        let grid = LibraryGridModel(queries: LibraryQueries(store: store))
        thumbnailBridge = bridge
        gridModel = grid
        Task { try? await grid.reloadFirstPage() }
    }

    // MARK: - Top bar (the T5 seam: project name + phase command buttons;
    // P2/P3 fill in the full command row)

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 12) {
            if workspace.phase == .editor {
                Button {
                    workspace.closeEditor()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("shell.topbar.backToLibrary")
                .accessibilityLabel(Text(String(localized: "shell_topbar_back_to_library", defaultValue: "Back to Library")))
            }
            Text(projectName)
                .font(.headline)
                .foregroundStyle(ThemeTokens.textPrimary)
                .accessibilityIdentifier("shell.topbar.projectName")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ThemeTokens.cardSurface)
        .overlay(
            Rectangle()
                .fill(ThemeTokens.cardBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var projectName: String {
        guard let url = projectController?.projectURL else {
            return String(localized: "shell_topbar_no_project", defaultValue: "Lightamer")
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
