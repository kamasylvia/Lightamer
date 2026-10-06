import LightamerCore
import LightamerIOP
import ImageIO
import CoreImage
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

    /// M2-4-1 T5 (KD-5/E1③): the RAW-overrides persistence channel is the
    /// app-root's singleton coordinator (`@Environment`, the same instance
    /// `EditorState` already binds to) — the `.task` below cross-attaches it
    /// with the shell model (both ends weak, the owners strong).
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    /// M2-8-3 acceptance FINDING-B fix: the D-26 toast channel's DEFAULT-face
    /// render site reads the editor state's toast here (the StatusBar slot is
    /// the legacy face's twin — reachable at this depth, the same injection
    /// YiyinTopBarSheet reads beside it).
    @Environment(EditorState.self) private var editorState

    // M2-9-04 (declared increment — the front-matter omission family): the
    // top-bar EXPORT entry (OQ-1 A / KD-1 — the M2 face's "toolbar 导出按钮")
    // and the grid-selection provider arm (KD-4's target derivation — the
    // shell owns the selection, the assembly point reads, views inject L036).
    @Environment(ExportState.self) private var exportState
    @Environment(InspectorState.self) private var inspectorState

    // Plan M2-3-1 T6 (M2UIW-06): the background-task faces — ONE registry
    // behind BOTH presentations (bar + dialog), the import leg riding the
    // read-only ImportTaskAdapter subscription.
    @State private var taskRegistry = BackgroundTaskRegistry()
    @State private var isTaskDialogPresented = false
    @State private var importAdapter: ImportTaskAdapter?

    // M2-10-03 (declared increment): the AI analysis leg + the labeling ask.
    // The registry rides THIS host's aggregate task registry (the bar/dialog
    // render AI rows with zero new presentation faces — the M2UIW-06
    // single-aggregate discipline) and the prompt sheet hangs beside the
    // other shell sheets. The controller receives both legs by injection
    // (nil-until-bound = the inert face the import tests see).
    @State private var labelingPrompts = LabelingPromptController()
    @State private var aiAnalysis: AIAnalysisRegistry?

    // M2-10-07 (declared increment): the AI entry coordinator — the two
    // enhance-dialog entries (grid context menu / editor Image menu), the
    // Inspector's remote commands (rating via the confirm gate, description
    // straight to the queue), the production seams (frame provider / worker
    // closures / the EnhanceContext) and the two sheets. Default-constructed
    // so body closures capture a STABLE instance; the deps land in .task
    // via `configure` (the aiAnalysis pattern).
    @State private var aiEntry = AIEntryPointCoordinator()

    // Plan M2-3-2 T1 (KD-1): the library surface the grid renders from —
    // rebuilt on project open/close/move (the queries ride the OPEN store;
    // the bridge rides the package's `.<stem>.lathumbs/` directory). The
    // grid model is the P1 collection single-source; the host only builds
    // and wires it.
    @State private var gridModel: LibraryGridModel?
    @State private var thumbnailBridge: LibraryThumbnailBridge?
    /// The Album Inspector's logic face (Plan M2-3-2 T2, KD-2/KD-5) — built
    /// beside the grid, over the same cursor + query face.
    @State private var inspectorModel: LibraryInspectorModel?
    /// The global search's logic face (Plan M2-3-2 T3, KD-3) — the EXIF
    /// lexical leg folds into the SAME cursor.
    @State private var searchModel: LibrarySearchModel?
    /// The batch-relink sheet (Plan M2-3-2 T4, KD-4): built on demand from
    /// the inspector's stale selection.
    @State private var isRelinkSheetPresented = false
    @State private var relinkModel: LibraryRelinkModel?
    @State private var relinkRows: [LibraryImageRow] = []
    /// The M2-3-3 T2 yiyin top-bar sheet (the D4 独有入口).
    @State private var isYiyinSheetPresented = false

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
                    EditorWorkspaceShellView(
                        workspace: workspace,
                        bridge: thumbnailBridge,
                        projectController: projectController)
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
        // M2-8-3 acceptance FINDING-B fix: the DEFAULT shell's D-26 toast
        // render site. The M2-3-1 shell swap moved the project workspace onto
        // this host and left `EditorState.presentToast`'s channel with no
        // render point on the default face (the StatusBar toast slot only
        // mounts in `legacyBody`) — the unclean-terminate sentinel, export
        // failures, deletion locks and drift warnings were structurally
        // invisible here. Zero-height when no toast is up; the StatusBar's
        // 22pt visual language when one is.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ToastBarView(toast: editorState.toast)
                .animation(.easeInOut(duration: 0.2), value: editorState.toast)
        }
        .focusedSceneValue(\.lightamerWorkspaceModel, workspace)
        // The task-dialog host (the SAME registry — dual presentation).
        .sheet(isPresented: $isTaskDialogPresented) {
            BackgroundTaskDialogHost(
                registry: taskRegistry,
                isPresented: $isTaskDialogPresented)
        }
        // The ⌘F global search (Plan M2-3-2 T3, m6): the presentation
        // boolean is the WorkspaceModel's — the host CONSUMES it here and
        // writes dismissal back through the model's faces; the dialog never
        // self-owns the state.
        .sheet(isPresented: Binding(
            get: { workspace.isSearchDialogPresented },
            set: { presented in
                if presented {
                    workspace.presentSearchDialog()
                } else {
                    workspace.dismissSearchDialog()
                }
            })) {
            if let searchModel {
                GlobalSearchDialog(
                    model: searchModel,
                    onDismiss: {
                        workspace.dismissSearchDialog()
                        // M2-10-02: the count card rides the fresh filter /
                        // semantic result set (the EXIF leg shares this).
                        Task { await inspectorModel?.refresh() }
                    })
            }
        }
        // The batch-relink sheet (Plan M2-3-2 T4, KD-4): the rows were
        // snapshotted at entry; the store/package ride the OPEN project.
        .sheet(isPresented: $isRelinkSheetPresented) {
            if let projectController, let store = projectController.projectStore,
                let packageURL = projectController.projectURL,
                let relinkModel {
                RelinkSheetView(
                    model: relinkModel,
                    rows: relinkRows,
                    projectDirectory: packageURL.deletingLastPathComponent(),
                    store: store,
                    onDismiss: { isRelinkSheetPresented = false })
            }
        }
        // The yiyin 印框/水印 + text-overlay sheet (M2-3-3 T2, D4 独有入口).
        .sheet(isPresented: $isYiyinSheetPresented) {
            YiyinTopBarSheet(onDismiss: { isYiyinSheetPresented = false })
        }
        // M2-10-03: the labeling ask (OQ-6-A — labeling writes user-visible
        // state, so it asks). 「分析」routes the ids into the registry's
        // labeling task; the remember checkbox persists through
        // LabelingPreferences (the ImportDefaults storeChoice semantics —
        // a single-shot answer persists nothing). isPresented + content-read
        // shape: the controller's pendingPrompt is private(set) — the sheet
        // never writes it except through the controller faces.
        .sheet(isPresented: Binding(
            get: { labelingPrompts.pendingPrompt != nil },
            set: { if !$0 { labelingPrompts.dismissPrompt() } })) {
            if let request = labelingPrompts.pendingPrompt {
                LabelingAskDialog(request: request) { accepted, remember in
                    if accepted {
                        if let ids = labelingPrompts.accept(remember: remember) {
                            aiAnalysis?.enqueue(.labeling(imageIDs: ids))
                        }
                    } else {
                        labelingPrompts.decline(remember: remember)
                    }
                }
            }
        }
        // M2-10-07 (KD-3): the editor Image menu's enhancement request —
        // consumed here and turned into the enhance queue (ONE presentation
        // owner; the menu command only sets the request face).
        .onChange(of: workspace.pendingAIEnhance) { _, request in
            guard let request else { return }
            _ = workspace.consumeAIEnhance()
            aiEntry.openEnhance(
                kind: request.kind, imageIDs: request.imageIDs)
        }
        // M2-10-07: the AI enhancement sheet — one dialog per queued image
        // (the v1 sequential batch; a finished non-final job auto-advances,
        // a user close aborts the remainder and stops the worker client).
        .sheet(isPresented: Binding(
            get: { aiEntry.enhancePresented },
            set: { presented in
                if !presented {
                    aiEntry.closeEnhance()
                    // The copies landed through the import twin — refresh
                    // the visible collection (the import-tail precedent).
                    Task {
                        try? await gridModel?.reloadFirstPage()
                        await inspectorModel?.refresh()
                    }
                }
            })) {
            if aiEntry.enhancePresented {
                AIEnhanceBatchSheet(coordinator: aiEntry)
            }
        }
        // M2-10-07: the rating confirm gate (the OQ-11-A dialog — nothing
        // writes until an explicit apply; the 不再询问 path never gets here).
        .sheet(isPresented: Binding(
            get: { aiEntry.ratingConfirmPresented },
            set: { if !$0 { aiEntry.dismissRatingConfirm() } })) {
            if let controller = aiEntry.ratingController,
                aiEntry.ratingConfirmPresented {
                AIRatingConfirmSheet(controller: controller)
            }
        }
        // The import-leg subscription (checker E3): a READ-ONLY observation
        // of the controller's importProgress publication. The adapter
        // mirrors it into the registry; the run's end (nil) finishes the
        // task. The controller itself is never touched. The M2-3-4 T2
        // walkthrough fix: the run's end also refreshes the library surface
        // (grid first page + inspector aggregates) — a fresh import must
        // land in the visible collection without a project reopen.
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
                guard gridModel != nil else { return }
                Task {
                    // Hoisted locals: the optional-chain compound below the
                    // locals trips the Release -O type-checker timeout
                    // (M2-11-02 T5 execution finding — Debug face identical).
                    let grid = gridModel
                    try? await grid?.reloadFirstPage()
                    let inspector = inspectorModel
                    await inspector?.refresh()
                }
            }
        }
        .onChange(of: projectController?.projectURL) { _, _ in
            rebuildLibrarySurface()
        }
        .onAppear {
            rebuildLibrarySurface()
        }
        // M2-4-1 T5 (KD-5/E1③): the bidirectional attach seam (the
        // M2-3-1 `EditorState.attach` pattern) — write-leg pass-through +
        // restore-leg priming ride it.
        .task {
            // M2-10-07: bind the AI entry coordinator (once per host
            // lifetime; the injections are plain reference writes).
            aiEntry.configure(
                projectController: projectController,
                taskRegistry: taskRegistry,
                grid: gridModel,
                urlResolver: { row in
                    guard let controller = projectController,
                        let packageURL = controller.projectURL,
                        let kind = LibrarySchema.PathKind(rawValue: row.pathKind),
                        case .resolved(let url) = ImageLinker.resolve(
                            imagePath: row.imagePath, pathKind: kind,
                            volumeUUID: row.volumeUUID,
                            projectDirectory: packageURL.deletingLastPathComponent())
                    else { return nil }
                    return url
                })
            aiEntry.refreshAccessState()
            // M2-10-03: bind the AI legs to the project controller (once per
            // host lifetime; the injections are plain reference writes).
            if aiAnalysis == nil {
                aiAnalysis = AIAnalysisRegistry(
                    backgroundRegistry: taskRegistry,
                    storeProvider: { [weak projectController] in
                        projectController?.projectStore
                    },
                    engineProvider: {
                        await AIInferenceService.shared.analysisEngine()
                    },
                    prototypesProvider: { [weak projectController] in
                        // The bundle prototype tree, revision-checked against
                        // the ACTIVE model row per task (the same-revision
                        // contract; a mismatch throws the typed refusal).
                        guard let store = projectController?.projectStore,
                            let revision = try await SemanticStore(store: store)
                                .activeModel()?.revision
                        else { return nil }
                        let clip = ModelAssetCatalog.chineseClipViTB16Int8
                        guard let directory = ModelLocator().bundledProfileURL(
                            clip.profileID)?
                            .appendingPathComponent(
                                "label-prototypes", isDirectory: true)
                        else { return nil }
                        return try LabelPrototypeSet.load(
                            directory: directory, expectingRevision: revision)
                    },
                    projectDirectoryProvider: { [weak projectController] in
                        projectController?.projectURL?.deletingLastPathComponent()
                    })
            }
            projectController?.aiAnalysis = aiAnalysis
            projectController?.labelingPrompts = labelingPrompts
            workspace.attach(pipeCoordinator: pipeCoordinator)
            pipeCoordinator.attach(workspace: workspace)
            // M2-9-04 (KD-4): the M2 export target provider — the grid
            // multi-select resolved to source URLs in ROW order (the filmstrip
            // and the grid share the one selection state machine). Weakly
            // captured: a torn-down surface drops the face to empty and the
            // derivation falls back to the current image.
            exportState.m2SelectionProvider = { [weak workspace] in
                guard let workspace, let grid = workspace.editorGrid else { return [] }
                let ids = grid.selectedIDs
                guard !ids.isEmpty else { return [] }
                return grid.rows
                    .filter { ids.contains($0.id) }
                    .compactMap { workspace.editorURLResolver?($0) }
            }
        }
        #if DEBUG
        .modifier(EditorProbeIfRequested(
            projectController: projectController, workspace: workspace,
            gridModel: $gridModel))
        #endif
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
                    },
                    // M2-10-07 (KD-3): the two enhance entries — the acted-on
                    // set = the grid selection when it contains the clicked
                    // row, else the clicked row alone (multi-select = the
                    // sequential batch, v1).
                    onAIUpscale: { clicked in
                        aiEntry.openEnhance(
                            kind: .upscale, clickedRowID: clicked,
                            selection: gridModel.selectedIDs)
                    },
                    onAIDenoise: { clicked in
                        aiEntry.openEnhance(
                            kind: .denoise, clickedRowID: clicked,
                            selection: gridModel.selectedIDs)
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The T2 Album Inspector (fixed-width tier, KD-2): the
                // Alcedo panel IA over the SAME cursor the grid renders.
                Group {
                    if let inspectorModel {
                        LibraryInspectorView(
                            model: inspectorModel,
                            onRelinkRequested: {
                                // The batch acts on the CURRENT selection;
                                // the sheet classifies it into the two
                                // stale forms on appear.
                                relinkRows = inspectorModel.selectedRows
                                relinkModel = LibraryRelinkModel()
                                isRelinkSheetPresented = true
                            },
                            // M2-10-07 (KD-3): the AI analysis commands —
                            // key-absent renders the guidance row instead.
                            aiNeedsSetup: aiEntry.needsSetup,
                            onAIRating: {
                                Task {
                                    await aiEntry.runRating(
                                        imageIDs: inspectorModel.selectedRows
                                            .map(\.id))
                                }
                            },
                            onAIDescription: {
                                Task {
                                    await aiEntry.runDescription(
                                        imageIDs: inspectorModel.selectedRows
                                            .map(\.id))
                                }
                            })
                    } else {
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
                        .accessibilityIdentifier("shell.library.inspector.slot")
                    }
                }
                .background(ThemeTokens.cardSurface)
                .overlay(
                    Rectangle()
                        .fill(ThemeTokens.cardBorder)
                        .frame(width: 1),
                    alignment: .leading)
            }
        } else {
            // The no-project state keeps the M2-2-4 container verbatim
            // (welcome / import entry).
            ProjectWorkspaceFace(
                controller: projectController,
                onImportFolder: onImportFolder)
        }
    }

    /// Build (or drop) the grid + bridge + inspector for the OPEN project.
    /// Called on appear and on every projectURL change (open / create /
    /// move — the controller's own publication face; no controller code
    /// touched).
    private func rebuildLibrarySurface() {
        guard let controller = projectController,
            let store = controller.projectStore,
            let packageURL = controller.projectURL else {
            gridModel = nil
            thumbnailBridge = nil
            inspectorModel = nil
            searchModel = nil
            // M2-10-07: the AI entry faces drop with the surface.
            aiEntry.rebindGrid(nil, resolver: nil)
            // The P3 editor seam drops with the surface (the shell's
            // rows/EXIF/readback face rides the open project).
            workspace.editorGrid = nil
            workspace.editorURLResolver = nil
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
        let inspector = LibraryInspectorModel(
            grid: grid,
            queries: LibraryQueries(store: store),
            smartAlbums: SmartAlbumStore())
        let search = LibrarySearchModel(
            grid: grid,
            // M2-10-02 (KD-5/T4): the CLIP leg — the semantic read face over
            // THIS project's package + the App assembly point's engine
            // (nil in no-model environments = the honest unavailable face).
            semanticStore: SemanticStore(store: store),
            semantic: { await AIInferenceService.shared.semanticSearcher() },
            // M2-10-04 (KD-4): the fulltext leg — the same package's
            // ai_understanding FTS (the E5 JOIN-active face lives in Core).
            fulltext: { query in
                try await AIDescriptionService.imageIDs(
                    matching: query, store: store)
            })
        thumbnailBridge = bridge
        gridModel = grid
        inspectorModel = inspector
        searchModel = search
        // M2-10-07: the coordinator's row/URL faces ride the LIVE surface
        // (re-bound on every rebuild — open/close/move).
        aiEntry.rebindGrid(grid, resolver: resolve)
        // The P3 editor seam (M2-3-3 T1): the shell reads rows + resolves
        // source URLs through the SAME surface the grid renders (zero
        // collection-state copying, KD-3).
        workspace.editorGrid = grid
        workspace.editorURLResolver = resolve
        Task {
            try? await grid.reloadFirstPage()
            await inspector.refresh()
        }
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
            if workspace.phase == .editor {
                // M2-9-04 (OQ-1 A / KD-1): the M2 export entry — routes to
                // the Inspector Export page (the page switch + the column
                // raise in one arm via ContentView's inspector mount; the
                // legacy sheet face is not reachable here).
                Button {
                    inspectorState.openExportPage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("shell.topbar.export")
                .accessibilityLabel(Text(String(localized: "menu_export")))
                // The D4 独有入口: the yiyin 印框/水印 sheet (the export-domain
                // first-class panel — no Alcedo counterpart; TextOverlay is
                // the sheet's text carrier).
                Button {
                    isYiyinSheetPresented = true
                } label: {
                    Image(systemName: "signature")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("shell.topbar.yiyin")
                .accessibilityLabel(Text(String(
                    localized: "shell_topbar_yiyin",
                    defaultValue: "Yiyin frame & watermark")))
            }
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

// ─────────────────────────────────────────────────────────────────────────────
// AIEntryPointCoordinator (Plan M2-10-07 T3, KD-3, declared increment) — the
// AI ENTRY FACES the M2-10 plan lights: the two enhance-dialog entries (the
// grid context menu + the editor Image menu), the Inspector's remote commands
// (rating through the OQ-11-A confirm gate; description straight to the
// queue), and the production seams the M2-10-06 dialog hands over
// (frameProvider = the ORIGINAL file's decode — the D-3 new-source-pixel
// semantics; modelFacts/tileExecutor = the worker client's enhancement
// channel; EnhanceContext = the project import twin).
//
// BATCH SEMANTICS (v1, the plan's 顺序单张循环): one dialog per image; a
// finished NON-final job auto-advances; a user close aborts the remainder
// (the true queue-with-concurrency is the plan's registered observation
// item). The queue face (`beginQueue/advanceIfMore/closeEnhance`) is
// deliberately grid-free — the entry-point tests drive it directly.
//
// KEY DISCIPLINE: the remote sweeps read the key ONCE per run, pass it to
// the service (the client scrubs its internal copy), and zeroize the caller
// buffer at the end — the 04 red line.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class AIEntryPointCoordinator {

    /// The frozen AX marker set (the M2-3 marker methodology: the new entry
    /// commands' existence is machine-checkable against THIS set — the views
    /// reference the constants, so drift cannot compile).
    enum Marker {
        static let gridUpscale = "library.grid.cell.aiUpscale"
        static let gridDenoise = "library.grid.cell.aiDenoise"
        static let menuUpscale = "menu.image.aiUpscale"
        static let menuDenoise = "menu.image.aiDenoise"
        static let inspectorRating = "library.inspector.aiRating"
        static let inspectorDescription = "library.inspector.aiDescription"
        static let inspectorSetup = "library.inspector.aiSetup"
        static let all: Set<String> = [
            gridUpscale, gridDenoise, menuUpscale, menuDenoise,
            inspectorRating, inspectorDescription, inspectorSetup,
        ]
    }

    /// One queued enhancement (a resolved library row + its source URL).
    struct EnhanceJob: Equatable {
        let imageID: Int64
        let originalURL: URL
    }

    // MARK: Dependencies (configured once by the host; the grid re-binds)

    private var projectController: LibraryProjectController?
    private var taskRegistry: BackgroundTaskRegistry?
    private var grid: LibraryGridModel?
    private var urlResolver: ((LibraryImageRow) -> URL?)?
    private var configured = false

    func configure(
        projectController: LibraryProjectController?,
        taskRegistry: BackgroundTaskRegistry,
        grid: LibraryGridModel?,
        urlResolver: @escaping (LibraryImageRow) -> URL?
    ) {
        guard !configured else { return }
        self.projectController = projectController
        self.taskRegistry = taskRegistry
        self.grid = grid
        self.urlResolver = urlResolver
        configured = true
    }

    /// The live-surface rebind (the host's rebuildLibrarySurface — every
    /// project open/close/move).
    func rebindGrid(
        _ grid: LibraryGridModel?, resolver: ((LibraryImageRow) -> URL?)?
    ) {
        self.grid = grid
        self.urlResolver = resolver
    }

    // MARK: The enhancement queue (the two entries converge here)

    private(set) var enhanceKind: WorkspaceModel.AIEnhanceKind?
    private(set) var enhanceJobs: [EnhanceJob] = []
    private(set) var enhanceIndex = 0
    private(set) var enhanceClient: AIWorkerClient?

    var enhancePresented: Bool { enhanceKind != nil }

    var currentJob: EnhanceJob? {
        enhanceJobs.indices.contains(enhanceIndex) ? enhanceJobs[enhanceIndex] : nil
    }

    var isLastJob: Bool { enhanceIndex + 1 >= enhanceJobs.count }

    /// The LIBRARY entry (the grid context menu): the acted-on set = the
    /// grid selection when it contains the right-clicked row, else the
    /// clicked row alone.
    func openEnhance(
        kind: WorkspaceModel.AIEnhanceKind, clickedRowID: Int64,
        selection: Set<Int64>
    ) {
        let ids = selection.contains(clickedRowID)
            ? Array(selection)
            : [clickedRowID]
        openEnhance(kind: kind, imageIDs: ids)
    }

    /// The EDITOR entry (the Image menu): the explicit id set.
    func openEnhance(kind: WorkspaceModel.AIEnhanceKind, imageIDs: [Int64]) {
        // Resolve in grid-row order (the collection's canonical order).
        let rows = (grid?.rows ?? []).filter { imageIDs.contains($0.id) }
        let jobs: [EnhanceJob] = rows.compactMap { row in
            guard let url = urlResolver?(row) else { return nil }
            return EnhanceJob(imageID: row.id, originalURL: url)
        }
        guard !jobs.isEmpty else { return }
        beginQueue(kind: kind, jobs: jobs)
    }

    /// The queue face (testable without a grid — the entry-point tests).
    func beginQueue(
        kind: WorkspaceModel.AIEnhanceKind, jobs: [EnhanceJob]
    ) {
        guard !jobs.isEmpty else { return }
        // A re-entry while a queue runs replaces it (the previous client
        // stops — one enhancement channel at a time).
        if let enhanceClient {
            let client = enhanceClient
            Task { await client.stop() }
        }
        enhanceKind = kind
        enhanceJobs = jobs
        enhanceIndex = 0
        enhanceClient = AIWorkerClient(
            record: CompatRecord(path: CompatRecord.defaultPath()))
    }

    /// The auto-advance leg: a finished NON-final job moves to the next
    /// (the final job stays open showing its done face).
    func advanceIfMore() {
        guard !isLastJob else { return }
        enhanceIndex += 1
    }

    /// The dismissal/abort leg: the worker client stops (idempotent) and
    /// the queue clears.
    func closeEnhance() {
        if let enhanceClient {
            let client = enhanceClient
            Task { await client.stop() }
        }
        enhanceClient = nil
        enhanceJobs = []
        enhanceIndex = 0
        enhanceKind = nil
    }

    /// The production model for the CURRENT job (the M2-10-06 handoff:
    /// 「接线即换生产闭包」). nil = no job / no project store.
    func buildModel() -> EnhanceDialogModel? {
        guard let job = currentJob, let kind = enhanceKind,
            let controller = projectController,
            let store = controller.projectStore,
            let packageURL = controller.projectURL
        else { return nil }
        let choice: EnhanceOperationChoice =
            kind == .upscale
            ? .upscale(profileID: ModelAssetCatalog.realesrGeneralX4V3FP16.profileID)
            : .denoise(
                profileID: ModelAssetCatalog.drunetColorFP16.profileID,
                strength: 35)
        let context = EnhanceContext(
            originalURL: job.originalURL,
            sourceImageID: String(job.imageID),
            projectDirectory: packageURL.deletingLastPathComponent(),
            albumID: nil,
            importService: LightamerCore.ImportService(store: store))
        guard let client = enhanceClient else { return nil }
        // The profile the facts were opened WITH rides this box (the tile
        // executor routes to it — a mid-run picker switch cannot desync the
        // session; the facts face is the only writer, before any tile runs).
        let box = CurrentProfileBox()
        return EnhanceDialogModel(
            choice: choice, context: context,
            frameProvider: Self.frameProvider(for: job.originalURL),
            modelFacts: { profileID in
                box.set(profileID)
                return try await client.openEnhancement(profileID)
            },
            tileExecutor: { request in
                _ = try await client.enhanceTile(
                    box.current,
                    inPath: request.inputTile.path,
                    outPath: request.outputTile.path,
                    feedHeight: request.feedHeight,
                    feedWidth: request.feedWidth,
                    amount: request.amount)
            })
    }

    /// The worker session's open-profile box (the modelFacts → tileExecutor
    /// handoff; a lock-guarded Sendable pair).
    private final class CurrentProfileBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = ""
        func set(_ profileID: String) {
            lock.lock()
            value = profileID
            lock.unlock()
        }
        var current: String {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    // MARK: Production frame provider (the D-3 original-pixels semantics)

    /// Decode the ORIGINAL file (RAW/raster through the app decoder) and
    /// render it to the engine's fp32 RGBA frame currency ([0,1], linear
    /// sRGB). Runs off the main actor (the dialog's scoped closure). The
    /// engine's typed memory gate rejects over-budget jobs BEFORE any
    /// output allocation — the 100MP honesty face.
    nonisolated static func frameProvider(
        for url: URL
    ) -> @Sendable () async throws -> EnhanceFrame {
        {
            let decoded = try await RAWDecoder().decode(url)
            let image = decoded.ciImage
            let extent = image.extent
            let width = max(Int(extent.width), 1)
            let height = max(Int(extent.height), 1)
            var rgba = [Float](repeating: 0, count: width * height * 4)
            let context = CIContext()
            let space = CGColorSpace(name: CGColorSpace.linearSRGB)!
            rgba.withUnsafeMutableBytes { raw in
                context.render(
                    image, toBitmap: raw.baseAddress!,
                    rowBytes: width * MemoryLayout<Float>.stride * 4,
                    bounds: CGRect(x: 0, y: 0, width: width, height: height),
                    format: CIFormat.RGBAf, colorSpace: space)
            }
            return EnhanceFrame(rgba: rgba, width: width, height: height)
        }
    }

    /// The remote legs' vision payload: the image decoded and letterboxed
    /// down to `maxLongEdge`, JPEG-encoded (a base64 ride — the provider
    /// does not need the full-resolution bytes).
    nonisolated static func jpegPayload(
        for url: URL, maxLongEdge: Int = 1568
    ) async throws -> Data {
        let decoded = try await RAWDecoder().decode(url)
        var image = decoded.ciImage
        let extent = image.extent
        let longEdge = max(Int(extent.width), Int(extent.height), 1)
        let scale = min(1.0, Double(maxLongEdge) / Double(longEdge))
        if scale < 1.0 {
            image = image.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let context = CIContext()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cgImage = context.createCGImage(
            image, from: image.extent, format: CIFormat.RGBA8,
            colorSpace: space)
        else {
            throw AppError.decodeFailed("AI payload: CGImage render failed")
        }
        let out = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                out, "public.jpeg" as CFString, 1, nil)
        else {
            throw AppError.decodeFailed("AI payload: JPEG destination failed")
        }
        CGImageDestinationAddImage(
            destination, cgImage,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.decodeFailed("AI payload: JPEG encode failed")
        }
        return out as Data
    }

    // MARK: The remote legs (rating / description)

    /// The key-absent face (the Inspector's guidance root). Refreshed on
    /// configure, before each sweep, and when sheets close.
    private(set) var needsSetup = true
    /// The connection store (injectable — tests drive an isolated
    /// defaults/keychain pair; the production default is the app face).
    var accessStore = LibraryConnectionStore()

    private(set) var ratingConfirmPresented = false
    private(set) var ratingController: AIRatingController?

    func refreshAccessState() {
        needsSetup = accessStore.connection() == nil || !accessStore.hasAPIKey
    }

    func dismissRatingConfirm() {
        ratingController?.dismiss()
        ratingController = nil
        ratingConfirmPresented = false
    }

    /// The shared sweep guard: nil = the caller's typed early-out (the
    /// guidance face). The key buffer is the CALLER's to zeroize.
    private func remoteLegs(
        imageIDs ids: [Int64]
    ) -> (config: AIConnectionConfig, key: Data, store: ProjectFileStore)? {
        refreshAccessState()
        guard !needsSetup,
            let controller = projectController,
            let store = controller.projectStore
        else { return nil }
        guard let config = accessStore.connection(),
            let key = try? AICredentialStore.read(accessStore.keychainAccount),
            !key.isEmpty
        else { return nil }
        return (config, key, store)
    }

    /// 「AI 评片…」: the sequential sweep → the confirm gate (or the direct
    /// apply on the 不再询问 preference). Nothing writes stars before the
    /// gate — the OQ-11-A red line lives in the controller.
    func runRating(imageIDs ids: [Int64]) async {
        guard !ids.isEmpty, let legs = remoteLegs(imageIDs: ids) else { return }
        var key = legs.key
        defer { key.resetBytes(in: 0..<key.count) }
        let strictness = accessStore.strictness()
        let language = accessStore.outputLanguage().resolved(
            preferredLocalizations: Locale.preferredLanguages)
        let service = AIRatingService(store: legs.store)
        let transport = URLSessionTransport()
        let controller = AIRatingController(
            preferences: RatingConfirmPreferences()) { stars, imageID in
                try await AIRatingService(store: legs.store)
                    .applyStars(stars, to: imageID)
            }
        ratingController = controller

        let flag = SendableCancelFlag()
        let handle = AIProgressHandle(
            title: String(localized: "tasks_ai_rating",
                          defaultValue: "AI rating…"),
            totalCount: ids.count) { flag.cancel() }
        taskRegistry?.register(handle)
        var verdicts: [(imageID: Int64, verdict: AIRatingVerdict)] = []
        var done = 0
        for id in ids {
            if flag.isCancelled { break }
            if let url = resolvedURL(id),
                let jpeg = try? await Self.jpegPayload(for: url) {
                if let verdict = try? await service.rate(
                    imageJPEG: jpeg, imageID: id, config: legs.config,
                    apiKey: key, transport: transport,
                    strictness: strictness, language: language) {
                    verdicts.append((id, verdict))
                }
            }
            done += 1
            handle.snapshot = .fraction(
                Double(done) / Double(max(ids.count, 1)),
                String(localized: "tasks_ai_counts",
                       defaultValue: "\(done) of \(ids.count)"))
            await Task.yield()
        }
        taskRegistry?.finish(id: handle.id)
        guard !verdicts.isEmpty else { return }
        controller.present(verdicts)
        if controller.confirmationBypassed {
            try? await controller.confirmAll()
        } else {
            ratingConfirmPresented = true
        }
    }

    /// 「AI 描述」: the sequential sweep, rows written straight to
    /// `ai_understanding` (FTS-triggered) — NO confirm gate: descriptions
    /// are derived data, not user-authored stars (the DECISIONS sign).
    func runDescription(imageIDs ids: [Int64]) async {
        guard !ids.isEmpty, let legs = remoteLegs(imageIDs: ids) else { return }
        var key = legs.key
        defer { key.resetBytes(in: 0..<key.count) }
        let service = AIDescriptionService(store: legs.store)
        let transport = URLSessionTransport()

        let flag = SendableCancelFlag()
        let handle = AIProgressHandle(
            title: String(localized: "tasks_ai_description",
                          defaultValue: "AI description…"),
            totalCount: ids.count) { flag.cancel() }
        taskRegistry?.register(handle)
        var done = 0
        for id in ids {
            if flag.isCancelled { break }
            if let url = resolvedURL(id),
                let jpeg = try? await Self.jpegPayload(for: url) {
                let row = grid?.rows.first { $0.id == id }
                _ = try? await service.describe(
                    imageJPEG: jpeg, imageID: id, config: legs.config,
                    apiKey: key, transport: transport,
                    renditionKind: row?.hasEdits == 1 ? "edited" : "original")
            }
            done += 1
            handle.snapshot = .fraction(
                Double(done) / Double(max(ids.count, 1)),
                String(localized: "tasks_ai_counts",
                       defaultValue: "\(done) of \(ids.count)"))
            await Task.yield()
        }
        taskRegistry?.finish(id: handle.id)
    }

    private func resolvedURL(_ id: Int64) -> URL? {
        guard let row = grid?.rows.first(where: { $0.id == id }) else {
            return nil
        }
        return urlResolver?(row)
    }
}

/// The lock-guarded cancel flag (the EnhanceDialogModel.CancelFlag shape,
/// shared by the sweeps).
final class SendableCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSetStorage = false
    func cancel() {
        lock.lock()
        isSetStorage = true
        lock.unlock()
    }
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSetStorage
    }
}

/// A generic progress handle for the AI sweeps (the ImportTaskAdapter
/// shape — one conformer, the SAME aggregate bar/dialog render it).
@MainActor
@Observable
final class AIProgressHandle: BackgroundTaskHandle {
    let id = UUID()
    let title: String
    var snapshot: BackgroundTaskSnapshot
    private let onCancelRoute: @Sendable () -> Void

    init(
        title: String, totalCount: Int,
        onCancel: @escaping @Sendable () -> Void
    ) {
        self.title = title
        self.snapshot = .fraction(
            0, String(localized: "tasks_ai_counts",
                      defaultValue: "0 of \(totalCount)"))
        self.onCancelRoute = onCancel
    }

    func cancel() async {
        onCancelRoute()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// AIEnhanceBatchSheet (Plan M2-10-07 T3, KD-3) — the enhance sheet's wrapper:
// one EnhanceDialog per queued image, the .done auto-advance for non-final
// jobs, the user close = abort-the-rest (the host's dismissal binding runs
// closeEnhance + the grid refresh). The worker client stops on disappear.
// ─────────────────────────────────────────────────────────────────────────────

struct AIEnhanceBatchSheet: View {
    let coordinator: AIEntryPointCoordinator
    @State private var model: EnhanceDialogModel?

    var body: some View {
        Group {
            if let model {
                EnhanceDialog(model: model)
                    .id(coordinator.enhanceIndex)
                    .onChange(of: model.phase) { _, phase in
                        if case .done = phase, !coordinator.isLastJob {
                            coordinator.advanceIfMore()
                        }
                    }
            } else {
                ProgressView()
                    .frame(width: 480, height: 200)
            }
        }
        .task(id: coordinator.enhanceIndex) {
            model = coordinator.buildModel()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// AIRatingConfirmSheet (Plan M2-10-07 T3, KD-3 / OQ-11-A) — the confirm gate:
// the sweep's real-star verdicts as proposals, applied ONLY here (or the
// batch 全应用). Dismissal without an apply never touches images.rating.
// ─────────────────────────────────────────────────────────────────────────────

struct AIRatingConfirmSheet: View {
    let controller: AIRatingController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(
                localized: "ai_rating_confirm_title",
                defaultValue: "AI Rating Suggestions"))
                .font(.headline)
            Text(String(
                localized: "ai_rating_confirm_hint",
                defaultValue: "Stars are written only when you apply — the library rating has no undo."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if controller.pendingProposals.isEmpty {
                Text(String(
                    localized: "ai_rating_confirm_empty",
                    defaultValue: "The model returned no star suggestions for this run."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.pendingProposals) { proposal in
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: String(repeating: "★", count: proposal.stars))
                            .foregroundStyle(.yellow)
                        Text(verbatim: proposal.reasons.joined(separator: "；"))
                            .font(.caption)
                            .lineLimit(2)
                        Spacer()
                        Button(String(
                            localized: "ai_rating_confirm_apply",
                            defaultValue: "Apply")) {
                            Task {
                                try? await controller.confirm(proposal)
                                if controller.pendingProposals.isEmpty {
                                    dismissSheet()
                                }
                            }
                        }
                        .accessibilityIdentifier("ai.rating.apply.\(proposal.imageID)")
                    }
                }
            }
            HStack {
                Spacer()
                Button(String(
                    localized: "ai_rating_confirm_cancel",
                    defaultValue: "Discard")) {
                    dismissSheet()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(
                    localized: "ai_rating_confirm_apply_all",
                    defaultValue: "Apply All")) {
                    Task {
                        try? await controller.confirmAll()
                        dismissSheet()
                    }
                }
                .disabled(controller.pendingProposals.isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("ai.rating.applyAll")
            }
            if controller.droppedByCap > 0 {
                Text(String(
                    localized: "ai_rating_confirm_capped \(controller.droppedByCap)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 460, height: 320)
    }

    private func dismissSheet() {
        controller.dismiss()
        dismiss()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// YiyinTopBarSheet (Plan M2-3-3 T2, D4) — the 印框/水印 first-class entry: the
// dual-section yiyin panel (watermark + borders rows) plus the TextOverlay
// carrier, presented from the editor top bar. The panel FILES are untouched:
// the sheet instances them with chain records (a missing op mounts a default
// record — the first edit absorbs it into the global chain through the D-H1
// live upsert, so the sheet is honest on an un-edited image too).
// ─────────────────────────────────────────────────────────────────────────────

struct YiyinTopBarSheet: View {

    let onDismiss: () -> Void

    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(
                    localized: "yiyin_sheet_title",
                    defaultValue: "Yiyin frame & watermark"))
                    .font(.headline)
                    .foregroundStyle(ThemeTokens.textPrimary)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("yiyin.sheet.close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if editorState.loadedImageURL == nil {
                ContentUnavailableView {
                    Label("no_image_selected", systemImage: "signature")
                } description: {
                    Text("no_image_selected_body")
                }
            } else {
                let session = InspectorEditSession(coordinator: pipeCoordinator)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        YiyinPanelView(
                            dispatched: record(
                                WatermarkModule.opName,
                                fallback: ModuleInstance(
                                    module: WatermarkModule.self,
                                    params: WatermarkModule.Params())),
                            edit: session)
                        TextOverlayPanelView(
                            instance: record(
                                TextOverlayModule.opName,
                                fallback: ModuleInstance(
                                    module: TextOverlayModule.self,
                                    params: TextOverlayModule.Params())),
                            edit: session)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .frame(width: 420, height: 560)
        .background(ThemeTokens.windowBackground)
        .accessibilityIdentifier("yiyin.sheet")
    }

    /// The chain record for the op, or the default record when the op has
    /// never been edited (the D-H1 live upsert absorbs it on first edit).
    private func record(
        _ opName: String, fallback: ModuleInstance
    ) -> ModuleInstance {
        editorState.instances.first { $0.opName == opName } ?? fallback
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ToastBarView (M2-8-3 acceptance FINDING-B fix) — the DEFAULT shell's D-26
// toast face. The StatusBar toast slot (ContentView.legacyBody's bottom
// safeAreaInset) is the legacy face's twin; this host mirrors its visual
// language (22pt raised bar, monospaced secondary text, hairline top border)
// with one contract difference: NO toast = NO chrome (EmptyView — the default
// face gains nothing permanent; the legacy face's always-on Ready/Decoding
// readout stays legacy-only). `ToastFaceTests` pins both halves of that
// contract.
// ─────────────────────────────────────────────────────────────────────────────

struct ToastBarView: View {

    /// D-26 background notice (nil = nothing shown).
    var toast: String?

    var body: some View {
        if let toast {
            HStack(spacing: 8) {
                Text(toast)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(LightamerColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
                    .accessibilityIdentifier("status_toast")
            }
            .frame(height: 22)
            .frame(maxWidth: .infinity)
            .background(LightamerColors.surfaceRaised)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(LightamerColors.border)
                    .frame(height: 1)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Defect-B editor probe (the fix special, DEBUG-only) — the GUI-chain drive
// of the editor load leg at the code level the walkthrough's double-click
// reaches: createProject → runImport(link) → wait for the library surface →
// `openCurrent` + `workspace.openEditor(imageID:)` (the onOpen closure body,
// verbatim) → await the decode + the display texture. Prints the row the
// EXIF header reads (currentRow) beside the URL the load leg resolved, then
// PASS/FAILs the render. `-la_editor_probe <sourceFolder>`.
// ─────────────────────────────────────────────────────────────────────────────

#if DEBUG
private nonisolated(unsafe) var editorProbeArmed = false

struct EditorProbeIfRequested: ViewModifier {
    let projectController: LibraryProjectController?
    let workspace: WorkspaceModel
    @Binding var gridModel: LibraryGridModel?
    @Environment(EditorState.self) private var editorState
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    func body(content: Content) -> some View {
        content.task {
            guard !editorProbeArmed,
                ProcessInfo.processInfo.arguments.contains("-la_editor_probe")
            else { return }
            editorProbeArmed = true
            let note: @MainActor (String) -> Void = { line in
                FileHandle.standardError.write(Data("[editor-probe] \(line)\n".utf8))
            }
            let args = ProcessInfo.processInfo.arguments.dropFirst()
            guard let folder = args.first(where: {
                !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
            }).map({ URL(fileURLWithPath: $0, isDirectory: true) }),
                let controller = projectController
            else {
                note("FAIL: no source folder argument or no controller")
                NSApp.terminate(nil)
                return
            }
            do {
                let package = FileManager.default.temporaryDirectory
                    .appendingPathComponent("editor-probe-\(UUID().uuidString).lalb")
                try await controller.createProject(at: package, name: "EditorProbe")
                note("project created — importing \(folder.lastPathComponent)")
                await controller.runImport(
                    folder: folder,
                    choice: ImportModeChoice(mode: .link, remember: false))
                // The library surface rebuilds on the projectURL change; the
                // first page loads asynchronously — wait for rows.
                for _ in 0..<100 where gridModel?.rows.isEmpty != false {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard let rows = gridModel?.rows, !rows.isEmpty else {
                    note("FAIL: grid rows never arrived")
                    NSApp.terminate(nil)
                    return
                }
                for row in rows {
                    note(String(
                        format: "row id=%lld file=%@ sidecar=%@ focal=%@ aperture=%@ exposure=%@ iso=%@",
                        row.id, row.filename ?? "nil",
                        FileManager.default.fileExists(
                            atPath: row.imagePath + ".lra") ? "yes" : "no",
                        row.focalLength.map { "\($0)" } ?? "nil",
                        row.aperture.map { "\($0)" } ?? "nil",
                        row.exposure.map { "\($0)" } ?? "nil",
                        row.iso.map { "\($0)" } ?? "nil"))
                }
                // Every row: the onOpen closure body (the double-click route,
                // verbatim) + a bounded render wait — separates the .lra-restore
                // rows from the pristine-seed rows in ONE run.
                for row in rows {
                    gridModel?.openCurrent(row.id)
                    workspace.openEditor(imageID: row.id)
                    var loaded = false
                    for _ in 0..<100 where editorState.loadedImageURL == nil {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    loaded = editorState.loadedImageURL != nil
                    var rendered = false
                    for _ in 0..<300 where editorState.displayTexture == nil {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    rendered = editorState.displayTexture != nil
                    note(String(
                        format: "load file=%@ loaded=%@ rendered=%@ texture=%@",
                        row.filename ?? "nil",
                        loaded ? "yes" : "NO",
                        rendered ? "yes" : "NO",
                        editorState.loadedImageURL?.lastPathComponent ?? "nil"))
                    if !rendered {
                        note(String(
                            format: "state decodeError=%@ image=%@ isDecoding=%@ layerStack=%@",
                            String(describing: editorState.decodeError),
                            editorState.image != nil ? "present" : "nil",
                            editorState.isDecoding ? "true" : "false",
                            editorState.layerStack != nil ? "present" : "nil"))
                        // The decisive bifurcation: drive pipeCoordinator.load
                        // DIRECTLY (this probe task IS the MainActor — no hop
                        // involved). Success here pins the hang on the
                        // decodeTask→MainActor hop; failure pins it inside
                        // the pipe load body.
                        if let decoded = editorState.image,
                            let url = editorState.loadedImageURL,
                            let metal = pipeCoordinator.detectionMetal() {
                            note("direct pipeCoordinator.load call…")
                            await pipeCoordinator.load(
                                url: url, decoded: decoded,
                                instances: [], metal: metal)
                            note(String(
                                format: "direct call returned; texture=%@",
                                editorState.displayTexture != nil ? "present" : "nil"))
                        } else {
                            note("direct call skipped: missing decoded/url/metal")
                        }
                    }
                    // Force the next row's reload (the same-url guard would
                    // otherwise skip a distinct row? no — but reset texture so
                    // the wait loop observes a FRESH push).
                    editorState.displayTexture = nil
                    try? await Task.sleep(for: .milliseconds(300))
                }
            } catch {
                note("FAIL: \(error)")
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
