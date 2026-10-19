import AppKit
import LightamerCore
import LightamerIOP
import SwiftUI
import os

// ─────────────────────────────────────────────────────────────────────────────
// LightamerShell (F0P-01 T6 — the shell handover flip).
//
// The GUI app runs under a manual NSApplication lifecycle
// (NSApplicationDelegate-owned NSWindow; the SwiftUI face demoted to
// NSHostingView sub-content). No SwiftUI `App`/Scene lifecycle exists after
// the flip — F0 proved macOS 27 SwiftUI bypasses `NSApp.mainMenu` whenever
// its own lifecycle hosts the app; the F0' spike proved the full handover
// (menu authority + churn 96%→0% + SwiftUI face survival). This file is the
// spike's verified transplant productionized:
//   - names: LightamerShell* (the spike's experiment-name prefix never
//     ships — the rename is grep-verified zero);
//   - the value-type state box lives in ShellGraph.swift as the ONE shared
//     instance (`ShellGraph.shared` — the review M2 single-source ruling);
//   - the four spike stubs are real: preset-manager / MCP-launcher /
//     Settings route to their window controllers (ShellWindowControllers),
//     ⌥⌘S/⌥⌘I write ShellGraph.shared.columnVisibility, export forks on
//     the gate (the sheet leg through the focused-value write path, the
//     M2 page leg through openExportPage);
//   - the D-F0P-4/8 lines: the fullscreen styleMask bit, the Dock-reopen
//     delegate callback, autosave key "LightamerMainWindow";
//   - the delegate composes the production AppDelegate (final — open
//     AppleEvents + the synchronous willTerminate flush forwarded
//     verbatim, the Notification parameter type is load-bearing).
//
// Revert discipline: the flip commit (entry swap + this file + the
// WindowCapture visibility + the ContentView toolbar seam) is ONE commit;
// reverting it restores the SwiftUI lifecycle completely.
// ─────────────────────────────────────────────────────────────────────────────

/// The transplanted face: the App struct's Window content (ContentView +
/// environment chain + tasks + sheets) and its helper methods, byte-derived
/// from `LightamerApp.swift` at main tip (mechanical perl transforms only:
/// value-state reads/writes re-pointed at the graph box). Same-named
/// properties keep every extracted closure's implicit-self capture identical
/// to the production shape.
internal struct LightamerShellFace: View {

    let graph: ShellGraph
    var graphB: Bindable<ShellGraph>
    let appDelegate: AppDelegate
    let sessionState: SessionState
    let editorState: EditorState
    let pipeCoordinator: PipeCoordinator
    let versionCoordinator: VersionCoordinator
    let exportState: ExportState
    let inspectorState: InspectorState
    let agentControl: AgentControlCoordinator
    let layerEditingState: LayerEditingState
    let sessionCoordinator: SessionCoordinator
    let sessionIndexController: SessionIndexController
    let sessionReconciler: SessionReconciler
    let aiDownloadModel: AIDownloadModel
    let depthMaskService: DepthMaskService
    let browserModel: SessionBrowserModel
    let thumbnailMemoryCache: ThumbnailMemoryCache
    let pasteboard: AdjustmentsPasteboard
    let cleanTerminateStore: CleanTerminateSentinelStore
    let metadataController: MetadataController
    let beforeAfterState: BeforeAfterState
    let softProofState: SoftProofState
    let edrHeadroomMonitor: EDRHeadroomMonitor
    let viewportState: ViewportState
    let browserLogoStore: YiyinLogoStore
    let smartAlbumStore: SmartAlbumStore
    let catalogPreferences: CatalogPreferencesModel
    let catalogBrowserModel: CatalogBrowserModel
    let catalogTreeModel: CatalogTreeModel
    let presetsStore: PresetsStore
    let presetController: PresetController
    let decoder: RAWDecoder
    let mcpWriteFace: McpWriteFaceBox
    let moduleRegistry: ModuleRegistry
    let metalContext: MetalContext?
    let colorMatchService: ColorMatchService
    let libraryProjects: LibraryProjectController
    let legacyLibraryEnabled: Bool

    // F0P-01 T6 additions (beyond the spike's two mechanical transform
    // families — the review M1/m5/m6 seams; each declared in DECISIONS):
    // the shell-facing handlers for the three window controllers (the face
    // is a struct — no weak back-ref; the controller hands in [weak self]
    // closures at makeFace) and the gate=true export-sheet raise path (the
    // App struct Commands' @FocusedBinding role, moved into the face).
    var presentPresetManager: (() -> Void)? = nil
    var presentMcpLauncher: (() -> Void)? = nil
    var presentSettings: (() -> Void)? = nil
    @FocusedBinding(\.exportPanelRequest) private var focusedExportRequest: Bool?

    var body: some View {
            ContentView(
                decoder: decoder, metalContext: metalContext,
                browserModel: browserModel, thumbnailProvider: graph.thumbnailProvider,
                catalogBrowserModel: catalogBrowserModel,
                catalogThumbnailRouter: graph.catalogThumbnailRouter,
                pasteboard: pasteboard,
                onPartialPasteRequested: { graph.pastePartialRequested = true },
                onPartialPaste: { selection, mode in
                    await pasteToSelection(selection: selection, mode: mode)
                },
                pastePartialRequested: graphB.pastePartialRequested,
                legacyLibraryEnabled: legacyLibraryEnabled,
                projectController: libraryProjects,
                // L057 (fix(l057)): Task hop — the begin-seam panel runs
                // outside this closure's frame.
                onImportFolder: { Task { await importFolderFromPanel() } }
            )
                .onChange(of: graph.presetManagerRequested) { _, requested in
                    // F0P-01 T6 (review M1): the toolbar preset-manager seam
                    // — post-flip the SwiftUI scene registry is absent and
                    // openWindow would silently no-op; the button writes the
                    // graph field, the face consumes it (the window
                    // controller's showWindow) and resets the flag.
                    guard requested else { return }
                    graph.presetManagerRequested = false
                    presentPresetManager?()
                }
                .environment(sessionState)
                .environment(sessionCoordinator)
                .environment(editorState)
                .environment(pipeCoordinator)
                .environment(versionCoordinator)
                .environment(beforeAfterState)
                .environment(softProofState)
                .environment(edrHeadroomMonitor)
                .environment(viewportState)
                .environment(exportState)
                .environment(inspectorState)
                .environment(layerEditingState)
                .environment(agentControl)
                .environment(aiDownloadModel)
                .environment(depthMaskService)
                .environment(metadataController)
                .environment(smartAlbumStore)
                .environment(colorMatchService)
                .environment(presetsStore)
                .environment(presetController)
                .environment(catalogPreferences)
                .environment(catalogBrowserModel)
                .environment(catalogTreeModel)
                .preferredColorScheme(.dark) // D-10: v1 forced dark
                // D-COL2 (Plan 02-04-05): capture the editor window the
                // moment SwiftUI places it — the coordinator follows THE
                // WINDOW's screen (multi-display: window's screen wins).
                .background {
                    WindowCapture { window in
                        pipeCoordinator.configure(window: window)
                    }
                }
                .task {
                    // 08-4 T3: the headroom monitor's initial query + the
                    // two screen-event observers (idempotent, app-lifetime).
                    edrHeadroomMonitor.start()
                }
                .task {
                    // Plan M2-2-2 (OQ-1 A): the minimal Welcome entry shows
                    // at launch when no project is open AND the recent list
                    // is empty — the additive path beside the Session face
                    // (coexistence until M2-2-4's 剥离门).
                    if libraryProjects.projectStore == nil,
                       libraryProjects.recentProjects.isEmpty {
                        graph.libraryWelcomePresented = true
                    }
                }
                .task {
                    await wireGraph()
                }
                // Plan M2-2-2: the project/import minimal faces (OQ-1 A +
                // OQ-4/OQ-11 切分线 — dialog + progress here, the complete
                // shell M2-3). View-level modifiers on the ContentView chain
                // (Scene `Window` carries no sheet/overlay face).
                .sheet(item: graphB.libraryImportRequest) { request in
                    ImportModeDialog(
                        request: request, initial: graph.libraryImportChoice,
                        onConfirm: { choice in
                            graph.libraryImportRequest = nil
                            // The OQ-4 persistence face (write on ACTION,
                            // never a body read — the D-EXEC-1 discipline).
                            ImportDefaults().storeChoice(choice)
                            Task {
                                await libraryProjects.runImport(
                                    folder: request.folder, choice: choice)
                            }
                        },
                        onCancel: { graph.libraryImportRequest = nil })
                }
                .sheet(isPresented: graphB.libraryWelcomePresented) {
                    // M7-5-01 (D-M7-5-4 face ⑫): the welcome route rides the
                    // equivalent derived-closure form — LibraryWelcomeView
                    // lives inside the zero-diff controller file (FIX2④),
                    // so the gate lands on the App-side closures.
                    LibraryWelcomeView(
                        recentProjects: libraryProjects.recentProjects,
                        onCreate: {
                            guard !agentControl.holdsControl else { return }
                            Task { await newLibraryProjectFromPanel() }
                        },
                        onOpen: {
                            guard !agentControl.holdsControl else { return }
                            Task { await openLibraryProjectFromPanel() }
                        },
                        onOpenRecent: { url in
                            guard !agentControl.holdsControl else { return }
                            Task {
                                try? await libraryProjects.openProject(at: url)
                                // M6-1-01: a published conflict keeps the
                                // welcome up until the dialog answers —
                                // dismiss only on a clean open.
                                if libraryProjects.pendingConflict == nil {
                                    graph.libraryWelcomePresented = false
                                }
                            }
                        },
                        onDismiss: { graph.libraryWelcomePresented = false })
                }
                .sheet(item: Binding(
                    get: { libraryProjects.pendingConflict },
                    set: { libraryProjects.pendingConflict = $0 }
                )) { conflict in
                    // M6-1-01 T4 (KD-3/OQ-2): the symmetric read-only
                    // fallback — 只读打开 / 重试 / 取消 (zh verbatim KD-3).
                    // Plain values + closures: no @Environment reads inside
                    // the sheet (the M2-8-3 FINDING-A boundary rule).
                    ProjectConflictDialog(
                        conflict: conflict,
                        onReadOnly: {
                            Task {
                                do {
                                    try await libraryProjects.openProjectReadOnly(
                                        at: conflict.url)
                                    libraryProjects.dismissConflict()
                                    graph.libraryWelcomePresented = false
                                    // The one-shot「只读」toast (KD-3) — the
                                    // same copy family as the banner key.
                                    editorState.presentToast(String(
                                        localized: "project_read_only_banner",
                                        defaultValue: "只读——项目已由另一实例（pid \(libraryProjects.readOnlyHolderPid.map(String.init) ?? "未知")）打开"))
                                } catch {
                                    libraryProjects.reportError(
                                        error.localizedDescription)
                                    libraryProjects.dismissConflict()
                                }
                            }
                        },
                        onRetry: {
                            Task {
                                try? await libraryProjects.openProject(
                                    at: conflict.url)
                                if libraryProjects.pendingConflict == nil {
                                    graph.libraryWelcomePresented = false
                                }
                            }
                        },
                        onCancel: { libraryProjects.dismissConflict() })
                }
                .sheet(isPresented: graphB.adjustmentTransferPresented) {
                    // Plan M2-8-2 T3 (KD-3): the Copy Adjustments transfer
                    // dialog — the paste leg rides the coordinator's
                    // pasteChain command. The content face re-injects the two
                    // Observable objects itself (the sheet boundary sits
                    // outside this chain's .environment writes — the M2-8-3
                    // acceptance FINDING-A fix; a bare AdjustmentTransferView()
                    // here traps on open).
                    AdjustmentTransferSheetContent(
                        versions: versionCoordinator, editorState: editorState)
                }
                .onChange(of: editorState.loadedImageURL != nil) { _, editorReady in
                    // M2-8-2 T4 (KD-6): the one-shot unclean-terminate
                    // toast — consumed at the EDITOR face's first readiness
                    // (the OQ-9-A global single toast; the flag clears so a
                    // later image never re-raises it).
                    if editorReady, graph.lastLaunchWasUnclean {
                        editorState.presentToast(CleanTerminateSentinel.toastCopy)
                        graph.lastLaunchWasUnclean = false
                    }
                }
                .overlay {
                    // Plan M2-3-1 T6: the progress overlay is now the LEGACY
                    // channel's face — the new shell renders the background-
                    // task bar + dialog (BackgroundTaskBarView) instead; the
                    // M2-2 view file itself stays untouched.
                    if legacyLibraryEnabled, let progress = libraryProjects.importProgress {
                        ImportProgressView(progress: progress) {
                            libraryProjects.cancelImport()
                        }
                    }
                }
                .alert(
                    Text(verbatim: "Lightamer Project"),
                    isPresented: Binding(
                        get: { libraryProjects.lastError != nil },
                        set: { if !$0 { libraryProjects.clearLastError() } })
                ) {
                    Button {
                        libraryProjects.clearLastError()
                    } label: {
                        Text(verbatim: "OK")
                    }
                } message: {
                    Text(verbatim: libraryProjects.lastError ?? "")
                }
    }

    /// The App struct's giant wiring `.task` body, verbatim (value-state
    /// refs re-pointed at the graph box).
    func wireGraph() async {
                    // Wire the pipe owner ↔ editor state pair (both weakly
                    // linked, root-owned strongly). Runs before any open is
                    // drained below, so the first decode already has its
                    // render path.
                    editorState.attach(pipeCoordinator: pipeCoordinator)
                    pipeCoordinator.attach(editorState: editorState)
                    // M7-5-01 (F-6): the turn-taking acquire wait probe —
                    // the coordinator reads the THREE-window OR through this
                    // injected closure (MainActor hop inside; the probe
                    // never hard-references PipeCoordinator).
                    agentControl.configureLiveEditProbe { [pipeCoordinator] in
                        await MainActor.run { pipeCoordinator.liveEditActive }
                    }
                    // M2-8-2 T4 (KD-6): the sentinel launch leg — read the
                    // PREVIOUS session's verdict, then mark THIS session
                    // running (the toast decision rides the editor-ready
                    // onChange below; a missing key = first launch = silent).
                    graph.lastLaunchWasUnclean = cleanTerminateStore.consumeAtLaunch()
                    // M2-8-1 T2: the version triangle — all three weak
                    // back-references land BEFORE any open is drained, so
                    // the first restore already hydrates the slots.
                    versionCoordinator.attach(
                        editorState: editorState, pipeCoordinator: pipeCoordinator)
                    editorState.attach(versionCoordinator: versionCoordinator)
                    pipeCoordinator.attach(versionCoordinator: versionCoordinator)
                    // Defect B fix: the app-owned Metal context rides the
                    // coordinator from launch — `detectionMetal()` (the
                    // editor GUI chain's render-leg key) is non-nil BEFORE
                    // the first load, never behind the load-only assignment
                    // that deadlocked the first load into a decode-only leg.
                    pipeCoordinator.attach(metal: metalContext)

                    // Plan 16-2 T1: build the shared catalog runtime at the
                    // PERSISTED location (re-point, never migrate) and wire
                    // the preference seams (enable → repoint + empty-library
                    // touch; location change → repoint). Idempotent. The
                    // rebuilt callback re-binds the browser model (and the
                    // T5 thumbnail router) to the NEW store instance — set
                    // BEFORE the initial repoint so the first build lands.
                    SessionIndexController.sharedCatalogStoreRebuilt = { store in
                        catalogBrowserModel.configure(store: store)
                        catalogTreeModel.configure(
                            store: SessionIndexController.sharedCatalogOrganization)
                        Task { await catalogTreeModel.refresh() }
                    }
                    await SessionIndexController.repointSharedCatalog(
                        databaseURL: catalogPreferences.catalogURL)

                    // Plan 16-2 T5: the cross-session thumbnail router —
                    // the SAME injected legs the per-session provider uses
                    // (render leg + yiyin run-context injector), the SAME
                    // app-level memory LRU, and the shared catalog store
                    // read through the provider closure (repoint-safe).
                    graph.catalogThumbnailRouter = CatalogThumbnailRouter(
                        memory: thumbnailMemoryCache,
                        registry: moduleRegistry,
                        decoder: decoder,
                        renderLeg: metalContext.map {
                            SessionThumbnailRenderer.renderLeg(metal: $0)
                        },
                        runContextInjector: SessionThumbnailRenderer
                            .runContextInjector(yiyinLogoStore: browserLogoStore),
                        catalogStoreProvider: {
                            SessionIndexController.sharedCatalogStore
                        })
                    CatalogThumbnailRouter.shared = graph.catalogThumbnailRouter

                    // Plan 16-2 T6: the edit-loop projection hook + the
                    // Catalogs-mode startup sweep (both ride the shared
                    // projector; its enable guard makes them no-ops when
                    // Catalogs is off).
                    sessionCoordinator.projectToCatalog = { root in
                        _ = try? await SessionIndexController
                            .sharedCatalogProjector.project(sessionRoot: root)
                    }
                    sessionCoordinator.sweepCatalog = { recents in
                        _ = await SessionIndexController
                            .sharedCatalogProjector.sweepAll(recentRoots: recents)
                    }
                    catalogPreferences.onEnabledChanged = { enabled in
                        guard enabled else { return }
                        Task { [catalogPreferences] in
                            await SessionIndexController.repointSharedCatalog(
                                databaseURL: catalogPreferences.catalogURL)
                        }
                    }
                    catalogPreferences.onLocationChanged = { url in
                        Task {
                            await SessionIndexController.repointSharedCatalog(
                                databaseURL: url)
                        }
                    }
                    // Plan 16-4 T2: the rebuild seams — the destructive
                    // promotion requires every shared handle closed first;
                    // any rebuild ends with the trio re-pointed (fresh read
                    // faces + the browser rebind hook). The recent list is
                    // the rebuild's source of last resort (the old registry
                    // is unreadable exactly when it matters).
                    catalogPreferences.onBeforeDestructiveRebuild = {
                        await SessionIndexController.closeSharedCatalogHandles()
                    }
                    catalogPreferences.onCatalogRuntimeReset = { [catalogPreferences] in
                        await SessionIndexController.closeSharedCatalogHandles()
                        await SessionIndexController.repointSharedCatalog(
                            databaseURL: catalogPreferences.catalogURL)
                    }
                    catalogPreferences.recentRootsProvider = { [sessionState] in
                        sessionState.recentSessions
                    }

                    // Plan 11-04 T3: hand the export state its Metal +
                    // registry dependencies (D-03b closure-seam pattern —
                    // never at construction). The queue itself rebuilds per
                    // session open, inside syncIndexHandler below.
                    exportState.configure(metal: metalContext, registry: moduleRegistry)

                    // Plan 09-01 T1: wire the session orchestrator's
                    // closure seams (flush/teardown/route/toast — all
                    // closures, D-03b). ensureDirectories/closeIndex/sync
                    // land with T2/T4; the defaults are inert no-ops.
                    sessionCoordinator.configure(
                        appState: sessionState,
                        flushCurrentImage: {
                            await pipeCoordinator.flushSidecar()
                        },
                        teardownRenderer: {
                            await pipeCoordinator.prepareForSessionSwitch()
                        },
                        closeIndexHandler: {
                            // 09-02 T3: disarm the watcher BEFORE the index
                            // closes (no events into a closed store).
                            sessionReconciler.stopSession()
                            // 12-1 T6: disarm the metadata write face too
                            // (no edits route into a closed store).
                            metadataController.invalidate()
                            // 12-4 T3: disarm the preset apply face too.
                            presetController.invalidate()
                            // 09-04 T4: flush the batch sidecar queue's
                            // remainder BEFORE the index closes (the
                            // teardown seam — pending writes must land or
                            // stay honestly dirty before reopen heals).
                            if let writer = graph.batchSidecarWriter {
                                await writer.flushForTeardown()
                                graph.batchSidecarWriter = nil
                            }
                            // Plan 14-4: the MCP culling face reads the
                            // live segment-3 writer + thumbnail provider
                            // through this box — cleared WITH the teardown
                            // so a closed session never serves a stale leg.
                            mcpWriteFace.set(writer: nil, provider: nil)
                            await sessionIndexController.close()
                        },
                        ensureDirectoriesHandler: { url in
                            try SessionLayout.ensureDirectories(at: url)
                        },
                        syncIndexHandler: { url in
                            let result = await sessionIndexController.openAndSync(root: url)
                            // 09-02 T3 ①: arm the watcher AFTER the full
                            // open sync (a failed sync leaves it disarmed).
                            if !result.failed {
                                sessionReconciler.startSession(root: url)
                                // 09-02 T4: the open-time orphan snapshot.
                                sessionState.setOrphanSidecarRelPaths(
                                    await sessionIndexController.actionableOrphans()
                                )
                                // 09-3: REBUILD the thumbnail pipeline on
                                // the NEW store (the old provider's queue
                                // was cancelled by the teardown ② above)
                                // and land the authoritative collection
                                // (orphans included as placeholder cells).
                                if let store = sessionIndexController.currentStore {
                                    graph.thumbnailProvider = SessionThumbnailProvider(
                                        sessionRoot: url,
                                        store: store,
                                        disk: ThumbnailDiskStore(sessionRoot: url),
                                        memory: thumbnailMemoryCache,
                                        registry: moduleRegistry,
                                        decoder: decoder,
                                        renderLeg: metalContext.map {
                                            SessionThumbnailRenderer.renderLeg(metal: $0)
                                        },
                                        runContextInjector:
                                            SessionThumbnailRenderer.runContextInjector(
                                                yiyinLogoStore: browserLogoStore
                                            )
                                    )
                                    // 09-04 T4: the segment-3 serial write
                                    // queue, rebuilt on the NEW store.
                                    graph.batchSidecarWriter = BatchSidecarWriter(
                                        root: url, store: store)
                                    // Plan 14-4: publish the pair to the MCP
                                    // culling face (the SAME shared writer
                                    // instance — D-14-CONTEXT-5① single
                                    // source; never a private queue).
                                    mcpWriteFace.set(
                                        writer: graph.batchSidecarWriter,
                                        provider: graph.thumbnailProvider)
                                }
                                if let store = sessionIndexController.currentStore {
                                    // 12-2 T4: install the persisted sort/
                                    // filter BEFORE the authoritative reload —
                                    // a relaunched app's first grid paint rides
                                    // the user's sort (the picker restored it,
                                    // the model must match).
                                    browserModel.installQueryState(
                                        groups: sessionState.queryGroups,
                                        sort: sessionState.sort)
                                    await browserModel.finishProgressiveIngest(
                                        store: store, includeOrphans: true
                                    )
                                }
                                // 12-1 T6: the metadata write face rides the
                                // SAME per-session (store, writer) pair; the
                                // refresh seam reloads the browser model so
                                // the grid/culling overlays re-render.
                                if let store = sessionIndexController.currentStore {
                                    metadataController.configure(
                                        root: url, store: store,
                                        writer: graph.batchSidecarWriter,
                                        seed: await seedInstances())
                                    metadataController.onWrite = { [store] in
                                        await browserModel.reload(
                                            store: store, includeOrphans: true)
                                    }
                                    // 12-4 T3: the preset APPLY face rides the
                                    // same pair + the app-level library.
                                    presetController.configure(
                                        root: url, store: store,
                                        writer: graph.batchSidecarWriter,
                                        seed: await seedInstances(),
                                        presetsStore: presetsStore)
                                    presetController.onWrite = { [store] in
                                        await browserModel.reload(
                                            store: store, includeOrphans: true)
                                    }
                                }
                                // Plan 11-04 T3 (checker E1): the export
                                // queue is SESSION-SCOPED (OQ-11-3) —
                                // rebuilt beside the thumbnail provider on
                                // every successful open; the old instance's
                                // pending work dies with it (no journal,
                                // D-11-CONTEXT-8).
                                exportState.sessionRoot = url
                                await exportState.rebuildQueueForSession()
                            }
                            return result
                        },
                        routeImage: { url in
                            editorState.load(
                                url: url,
                                decoder: decoder,
                                metal: metalContext,
                                logger: EditorState.decodeLogger
                            )
                        },
                        reportError: { editorState.presentToast($0) }
                    )

                    // Plan 09-3: the progressive-ingest seam — scanner
                    // pages land as placeholder grid rows BEFORE the sync
                    // transaction commits (边扫边出).
                    // M6-1-01 T2: the legacy session.lock ride-along's typed
                    // conflict rides the SAME error face every other session
                    // failure uses (the toast; the legacy read-only fallback
                    // face is the explicit M6-5 boundary).
                    sessionIndexController.sessionLockConflictHandler = {
                        editorState.presentToast($0)
                    }
                    sessionIndexController.scanPageObserver = { page in
                        browserModel.ingestPlaceholderPage(entries: page.entries)
                    }

                    // Plan 12-2 T4: the filter re-query seam (D-03b closure
                    // — the app root owns the current-store reference; the
                    // SessionState mutations schedule the debounced refresh
                    // through this). The SessionState instance is app-
                    // lifetime, so the state↔closure reference cycle is the
                    // app's own lifetime (no leak window).
                    sessionState.onFilterChanged = {
                        guard let store = sessionIndexController.currentStore
                        else { return }
                        await browserModel.applyFilter(
                            store: store,
                            groups: sessionState.queryGroups,
                            sort: sessionState.sort,
                            includeOrphans: false)
                    }

                    // Plan 12-4 T3: the preset controller's D-03b closure
                    // seams — targets = the 12-1 routing shape (the browser/
                    // culling selection, else the editor's current image),
                    // the live install = the interactive paste leg (ONE ⌘Z),
                    // and the compose = the ⌘⇧C 产物 for create-from-current.
                    presetController.targetsProvider = { metadataTargets() }
                    presetController.liveRelPathsProvider = { currentImageRelPaths() }
                    presetController.livePaste = { payload, selection, mode in
                        await pasteLive(
                            payload: payload, selection: selection, mode: mode,
                            seed: await seedInstances())
                    }
                    presetController.composeCurrent = {
                        guard editorState.loadedImageURL != nil else { return nil }
                        let layerRecord = editorState.layerStack
                            .map { SidecarLayerStackRecord($0) }
                            .flatMap { $0.layers.isEmpty ? nil : $0 }
                        return PastePayload.compose(
                            sourceImageID: pipeCoordinator.currentImageID ?? UUID(),
                            sourceURL: editorState.loadedImageURL,
                            sourceInstances: editorState.instances,
                            sourceEffective: editorState.history.effectiveInstances(),
                            seed: await seedInstances(),
                            layerStack: layerRecord)
                    }

                    // Plan 09-02 T3: wire the reconciler's seams (state +
                    // the real index legs; the same D-03b closure shape).
                    sessionReconciler.appState = sessionState
                    sessionReconciler.reconcileHandler = { url in
                        let outcome = await sessionIndexController.reconcile(root: url)
                        if let counts = outcome?.counts {
                            sessionState.setBrowseCounts(counts)
                        }
                        if let orphans = outcome?.orphanRelPaths {
                            sessionState.setOrphanSidecarRelPaths(orphans)
                        }
                        return outcome?.plan
                    }
                    sessionReconciler.staleMarkHandler = { paths in
                        await sessionIndexController.markStale(relPaths: paths)
                    }

                    // Plan 09-02 T4: the orphan actions (never hard-fail —
                    // a failed remove surfaces as a no-op) + the snapshot
                    // refresh each action trails with.
                    sessionCoordinator.removeOrphanSidecar = { rel in
                        guard let root = sessionState.currentSessionURL else {
                            return false
                        }
                        let removed = await sessionIndexController.removeOrphanSidecar(
                            root: root, relPath: rel
                        )
                        if removed {
                            sessionState.setOrphanSidecarRelPaths(
                                await sessionIndexController.actionableOrphans()
                            )
                        }
                        return removed
                    }
                    sessionCoordinator.ignoreOrphanSidecar = { rel in
                        await sessionIndexController.setOrphanIgnored(
                            relPath: rel, ignored: true
                        )
                        sessionState.setOrphanSidecarRelPaths(
                            await sessionIndexController.actionableOrphans()
                        )
                    }

                    // 13-3 T4 (SYS-04, D-13-CONTEXT-7): the drop-import
                    // orchestration — COPY into the session (move only
                    // through the Option intent), then the EXPLICIT
                    // reconcile ingest (never FSEvents timing), then the
                    // grid reload. Per-file failures surface as one toast;
                    // the batch never aborts (ImportService). Destination
                    // = the session ROOT (the D-09-CONTEXT-3 browse set
                    // excludes the Capture tier — 13-3-DECISIONS).
                    sessionCoordinator.importHandler = { urls, move in
                        guard let root = sessionState.currentSessionURL else {
                            return
                        }
                        let outcome = ImportService.importFiles(
                            at: urls, into: root, move: move)
                        if !outcome.imported.isEmpty {
                            _ = await sessionReconciler.reconcileHandler?(root)
                            if let store = sessionIndexController.currentStore {
                                await browserModel.reload(
                                    store: store, includeOrphans: true)
                            }
                        }
                        if outcome.failures.isEmpty {
                            guard !outcome.imported.isEmpty else { return }
                            editorState.presentToast(
                                String(localized: "toast_import_done \(outcome.imported.count)"))
                        } else {
                            editorState.presentToast(
                                String(localized:
                                    "toast_import_partial \(outcome.imported.count) \(outcome.failures.count)"))
                        }
                    }

                    // Plan 08-1 T1: the HDR-merge service (its OWN dedicated
                    // command queue inside) + the coordinator seam wiring —
                    // grid menu → confirm dialog → enqueue → queued/done
                    // toasts. T5 completes the product-into-grid reload.
                    if let metalContext {
                        do {
                            let mergeService = try StackMergeService(
                                device: metalContext.device)
                            sessionCoordinator.stackMergeService = mergeService
                            sessionCoordinator.hdrMergeHandler = { relPaths, deGhost in
                                guard let root = sessionState.currentSessionURL else {
                                    return
                                }
                                let urls = relPaths.map {
                                    root.appendingPathComponent($0)
                                }
                                do {
                                    _ = try await mergeService.enqueue(
                                        kind: .hdrMerge, sources: urls,
                                        params: StackMergeService.MergeParams(
                                            deGhost: deGhost),
                                        sessionRoot: root)
                                    editorState.presentToast(
                                        String(localized: "toast_hdr_merge_queued"))
                                } catch {
                                    editorState.presentToast(
                                        error.localizedDescription)
                                }
                            }
                            // Plan 08-3 T4: the stacking handlers — the
                            // same enqueue + toast shape; the default tag
                            // rides the kind (fstack / stack_avg / ...).
                            sessionCoordinator.focusStackHandler = { relPaths in
                                guard let root = sessionState.currentSessionURL else {
                                    return
                                }
                                let urls = relPaths.map {
                                    root.appendingPathComponent($0)
                                }
                                do {
                                    _ = try await mergeService.enqueue(
                                        kind: .focusStack, sources: urls,
                                        params: StackMergeService.MergeParams(
                                            deGhost: false, tag: nil),
                                        sessionRoot: root)
                                    editorState.presentToast(
                                        String(localized: "toast_stack_merge_queued"))
                                } catch {
                                    editorState.presentToast(
                                        error.localizedDescription)
                                }
                            }
                            // Plan M5-2-02 (KD-5, OQ-4): the Mertens
                            // quick-merge handler — the second merge option.
                            // The tier rides EXPLICITLY ("medium", the OQ-3
                            // default; deGhost is the Robertson02 knob and
                            // stays off; tag nil = the mertens default tag).
                            sessionCoordinator.mertensMergeHandler = { relPaths in
                                guard let root = sessionState.currentSessionURL else {
                                    return
                                }
                                let urls = relPaths.map {
                                    root.appendingPathComponent($0)
                                }
                                do {
                                    _ = try await mergeService.enqueue(
                                        kind: .hdrMertens, sources: urls,
                                        params: StackMergeService.MergeParams(
                                            deGhost: false, tag: nil,
                                            mertensDeghost: "medium"),
                                        sessionRoot: root)
                                    editorState.presentToast(
                                        String(localized: "toast_hdr_mertens_queued"))
                                } catch {
                                    editorState.presentToast(
                                        error.localizedDescription)
                                }
                            }
                            // Plan M5-3-03 (KD-2, OQ-7): the panorama
                            // merge handler — the third merge option.
                            // deGhost is NOT consumed by the pano leg; the
                            // App passes the explicit false. tag nil = the
                            // "pano" default tag (the _pano split-account
                            // name).
                            sessionCoordinator.panoMergeHandler = { relPaths in
                                guard let root = sessionState.currentSessionURL else {
                                    return
                                }
                                let urls = relPaths.map {
                                    root.appendingPathComponent($0)
                                }
                                do {
                                    _ = try await mergeService.enqueue(
                                        kind: .pano, sources: urls,
                                        params: StackMergeService.MergeParams(
                                            deGhost: false, tag: nil),
                                        sessionRoot: root)
                                    editorState.presentToast(
                                        String(localized: "toast_pano_queued"))
                                } catch {
                                    editorState.presentToast(
                                        error.localizedDescription)
                                }
                            }
                            sessionCoordinator.stackDenoiseHandler = { relPaths, mode in
                                guard let root = sessionState.currentSessionURL else {
                                    return
                                }
                                let kind: StackMergeService.MergeKind
                                switch mode {
                                case .average: kind = .stackAverage
                                case .median: kind = .stackMedian
                                case .sigmaClip: kind = .stackSigma
                                }
                                let urls = relPaths.map {
                                    root.appendingPathComponent($0)
                                }
                                do {
                                    _ = try await mergeService.enqueue(
                                        kind: kind, sources: urls,
                                        params: StackMergeService.MergeParams(
                                            deGhost: false, tag: nil),
                                        sessionRoot: root)
                                    editorState.presentToast(
                                        String(localized: "toast_stack_merge_queued"))
                                } catch {
                                    editorState.presentToast(
                                        error.localizedDescription)
                                }
                            }
                            await mergeService.setCompletionHook { snapshot, outcome in
                                if case .done = snapshot.state {
                                    for warning in outcome.warnings {
                                        await MainActor.run {
                                            editorState.presentToast(warning)
                                        }
                                    }
                                    // T5: the product enters the grid — the
                                    // EXPLICIT reconcile ingest + the reload
                                    // (the import seam's posture). The whole
                                    // body hops to the MainActor (the state
                                    // objects are MainActor-isolated; this
                                    // hook runs detached) through the helper
                                    // below.
                                    await self.refreshGridAfterMerge(
                                        holeFraction: outcome.holeFraction)
                                }
                            }
                            await mergeService.setFailureHook { snapshot, error in
                                // Plan M5-3-03 (KD-3): the typed pano
                                // three-state mapping rides the hook's
                                // display layer — a non-pano message is
                                // byte-identical (existing face zero change).
                                let detail = PanoFailureCopy.failureMessage(
                                    for: error.localizedDescription)
                                let message = String(localized:
                                    "toast_hdr_merge_failed \(detail)")
                                await MainActor.run {
                                    editorState.presentToast(message)
                                }
                            }
                        } catch {
                            AppError.logger.error(
                                "stack merge service unavailable: \(error.localizedDescription, privacy: .public)"
                            )
                        }
                    }

                    // 02-04: register LightamerIOP's modules into the
                    // registry (testgain in DEBUG; Phase 3+ joins here),
                    // then hand the registry to the coordinator so loads
                    // resolve the terminal-trio default chain.
                    // M2-1 (D1/D2 + KD-1/KD-3): the DEFAULT face skips the
                    // disable set unless LIGHTAMER_FULL_IOP_FACE=1 opts
                    // back into the full face — one read here seeds the
                    // registry, the panels, the coordinator's pristine
                    // seed and (below) the MCP host.
                    let defaultFace = !LightamerIOPRegistry.isFullFaceRequested
                    await LightamerIOPRegistry.populate(
                        moduleRegistry, defaultFace: defaultFace)
                    pipeCoordinator.attach(
                        registry: moduleRegistry, defaultFace: defaultFace)
                    // Plan M5-1-02 (KD-6): the colormatch service's pipe
                    // faces (the extraction render + the LUT-arm resolver
                    // installation ride them).
                    if let metalContext {
                        colorMatchService.configure(
                            metal: metalContext, registry: moduleRegistry)
                    }

                    // M3-3-02 T5 (KD-6): the film material store assembly —
                    // the bundle's FilmProfiles/profiles (the folder
                    // reference). A failed store = the typed degrade: the
                    // film face goes DARK (filmTailPolicy answers nil), one
                    // toast — never silent, never a crash.
                    if let profilesURL = Bundle.main.resourceURL?
                        .appendingPathComponent("FilmProfiles/profiles")
                    {
                        do {
                            let store = try FilmMaterialStore(
                                profilesDirectory: profilesURL)
                            pipeCoordinator.attachFilmStore(store)
                        } catch {
                            AppError.logger.error(
                                "film material store unavailable (\(String(describing: error), privacy: .public)) — the film simulation face is disabled"
                            )
                            await MainActor.run {
                                editorState.presentToast(String(
                                    localized: "toast_film_store_unavailable"))
                            }
                        }
                    }

                    // Plan 03-02-T3 (D-T6): register the Inspector panel
                    // providers (exposure + temperature are the first two).
                    // M2-1: the same face gates the 6 disabled panels —
                    // one face for registry + panels + seed (KD-1).
                    inspectorState.registerDefaultProviders(defaultFace: defaultFace)

                    // Plan 04-04-T3: resolve the Lensfun database (custom
                    // path > downloaded copy > absent-downgrade; sync,
                    // no network at launch — first download is panel-driven).
                    _ = LensfunDownloadService.resolveAndInstall()

                    // Register the IOP framework's default.metallib (which
                    // carries the pass_through kernel) with the dispatch
                    // context. Plan 04's pixelpipe dispatches through it;
                    // registering at the app root keeps the pipeline ready.
                    // Core's own metallib (terminal trio kernels) resolves
                    // automatically inside MetalContext.
                    if let metalContext {
                        try? await metalContext.registerDefaultLibrary(
                            in: PassthroughKernel.metalBundle
                        )
                    }
                    // Wire the open-document Apple Event (Finder / `open` /
                    // Dock drops) into the same load path as File → Open,
                    // then drain any opens that arrived during launch.
                    // Plan 09-01: a DIRECTORY open routes to the session
                    // path (same-window L012 — never a new window).
                    let routeOpen: @MainActor (URL) -> Void = { url in
                        let isDirectory = (try? url.resourceValues(
                            forKeys: [.isDirectoryKey]
                        ))?.isDirectory ?? false
                        if isDirectory {
                            Task { await sessionCoordinator.openSession(url: url) }
                        } else {
                            editorState.load(
                                url: url,
                                decoder: decoder,
                                metal: metalContext,
                                logger: EditorState.decodeLogger
                            )
                        }
                    }
                    appDelegate.openHandler = { urls in
                        for url in urls {
                            routeOpen(url)
                        }
                    }
                    for url in appDelegate.flushBuffered() {
                        routeOpen(url)
                    }
                    // 02-06 (D-S3): quit/termination forces the pending
                    // sidecar write through the AppDelegate's synchronous
                    // willTerminate callback. Plan 11-04 T3: the export
                    // queue's flush SLOT rides the same callback — exports
                    // have no journal and no partial files, so the slot
                    // records the abandonment (v1: re-runnable work).
                    appDelegate.terminateHandler = {
                        pipeCoordinator.flushForTermination()
                        exportState.flushForTermination()
                        // Plan 14-1 T4: the embedded MCP host's graceful
                        // stop rides the SAME synchronous termination
                        // callback — bounded drain (5s), discovery json
                        // deleted, writer lock released (or the process exit
                        // cleans up through the kernel + the discovery
                        // probe).
                        McpServerController.stopEmbeddedForTermination()
                        // M6-1-01 T4 (KD-2): the open project's bounded
                        // close — checkpoint → handle close → project-lock
                        // release (5s cap, the same shape as the flushes
                        // above).
                        libraryProjects.flushForTermination()
                        // Plan M2-8-2 T4 (KD-6): the sentinel clears AFTER
                        // the bounded flushes return — a kill inside the
                        // flush window leaves the flag set, which is the
                        // unclean case the next launch reports.
                        cleanTerminateStore.markClean()
                    }
                    #if DEBUG
                    resizeProbeIfRequested()
                    sidecarProbeIfRequested()
                    importProbeIfRequested()
                    #endif
                    // Plan 14-1 T4: the EMBEDDED MCP host (D-14-CONTEXT-2①:
                    // preference on → writer lock → bind 127.0.0.1 → write
                    // the discovery json → serve; the Settings toggle lands
                    // in 14-4 — this is the read face it will drive). The
                    // probe tools see the live session store through the
                    // same seam every other closure here uses.
                    // Plan 14-2: the editing tools ride the same kernel —
                    // the GUI host supplies the live (store, root) pair,
                    // the editor's current image (the GUI-live judge,
                    // MainActor hop) and the production yiyin injector.
                    // Plan 14-4 T1: the probes RETIRED; the culling face
                    // (14 tools) rides the same kernel against the live
                    // session pair + the SHARED segment-3 writer and
                    // thumbnail provider (the mcpWriteFace box published at
                    // the per-session rebuild above — D-14-CONTEXT-5①).
                    // The metadata seed is the app-wide default chain
                    // (the same face MetadataController.configure rides).
                    let mcpSeed = await seedInstances()
                    // S2 (D-M7-4-8): the GUI assembly is the fourth preheat
                    // point — the embedded-host path is already covered
                    // transitively (startEmbeddedServer → startHTTPHost),
                    // this direct call is the LUT-panel benefit leg
                    // (redundant and harmless — swift_once idempotent).
                    McpServerController.warmLutLibrary()
                    var cullingContext = McpCullingContext(
                        store: { [sessionIndexController] in
                            await MainActor.run { sessionIndexController.currentStore }
                        },
                        sessionRoot: { [sessionIndexController] in
                            await MainActor.run { sessionIndexController.currentSession?.root }
                        },
                        metadata: { [sessionIndexController, mcpWriteFace, mcpSeed] in
                            let pair = await MainActor.run {
                                sessionIndexController.currentSession
                            }
                            guard let (store, root) = pair else { return nil }
                            return MetadataService(
                                root: root, store: store,
                                writer: mcpWriteFace.writer,
                                seed: mcpSeed)
                        },
                        sidecarWriter: { [mcpWriteFace] in mcpWriteFace.writer },
                        presets: { [presetsStore] in presetsStore },
                        liveRelPaths: { [pipeCoordinator, sessionIndexController] in
                            await MainActor.run {
                                guard let url = pipeCoordinator.liveImageURL,
                                    let (_, root) = sessionIndexController.currentSession
                                else { return Set<String>() }
                                let base = root.path
                                let imagePath = url.path
                                guard imagePath.hasPrefix(base + "/") else {
                                    return Set<String>()
                                }
                                return [String(imagePath.dropFirst(base.count + 1))]
                            }
                        },
                        thumbnailProvider: { [mcpWriteFace] in mcpWriteFace.provider },
                        decodeImage: McpCullingContext.defaultDecodeImage(),
                        renderGate: McpServerController.sharedRenderGate)
                    // M6-1-01 T7 (KD-5): the write-face project probe — the
                    // SELF-HELD exemption on the normal (writer) GUI face,
                    // the real non-holding probe on the read-only face
                    // (holder exiting = natural recovery), and the legacy
                    // face's session.lock self-held branch (m2 回注接线).
                    let projectWriteProbe: @Sendable () async -> McpProjectLockVerdict = {
                        [libraryProjects, sessionIndexController, legacyLibraryEnabled] in
                        if legacyLibraryEnabled {
                            if await sessionIndexController.holdsSessionLock {
                                return .writable
                            }
                            guard let root = await sessionIndexController.currentSession?.root
                            else { return .writable }
                            let sessionLockURL = root.appendingPathComponent(".lightamer")
                                .appendingPathComponent("session.lock")
                            if SingleWriterLock.probeLockAvailable(at: sessionLockURL) {
                                return .writable
                            }
                            return .held(
                                holderSummary: SingleWriterLock.holderSummary(at: sessionLockURL),
                                guidance: McpServerController.connectGuidanceText())
                        }
                        let readOnly = await libraryProjects.isReadOnly
                        guard readOnly else { return .writable }
                        guard let url = await libraryProjects.projectURL else {
                            return .writable
                        }
                        let lockURL = url.deletingPathExtension()
                            .appendingPathExtension("lalb.lock")
                        if SingleWriterLock.probeLockAvailable(at: lockURL) {
                            return .writable
                        }
                        return .held(
                            holderSummary: SingleWriterLock.holderSummary(at: lockURL),
                            guidance: McpServerController.connectGuidanceText())
                    }
                    var editingSeams = await McpServerController.makeEditingSeams(
                        session: { [sessionIndexController] in
                            await MainActor.run { sessionIndexController.currentSession }
                        },
                        liveImageURL: { [pipeCoordinator] in
                            await MainActor.run { pipeCoordinator.liveImageURL }
                        },
                        yiyinInjector: { [browserLogoStore] in
                            await MainActor.run {
                                ExportState.makeYiyinInjector(logoStore: browserLogoStore)
                            }
                        })
                    editingSeams.projectWriteProbe = projectWriteProbe
                    cullingContext.projectWriteProbe = projectWriteProbe
                    // M5-1-03 (KD-1): the match_color tool shares the app's ONE
                    // colormatch service (the session curves) and reads the open
                    // project's library for id-form reference resolution (the
                    // assembly-only wiring — the tool face itself is seams-pure).
                    MatchColorToolset.installColorMatchService(colorMatchService)
                    // M6-1-01 T5 (KD-3): the read-only gates — ONE boolean
                    // (`libraryProjects.isReadOnly`) drives the banner, the
                    // disabled projections and the EditorState/ExportState/
                    // VersionCoordinator write seams (the LibraryStore
                    // withWriteBatch breaker is store-internal, KD-2).
                    editorState.projectReadOnlyGate = { [libraryProjects] in
                        libraryProjects.isReadOnly
                    }
                    exportState.projectReadOnlyGate = { [libraryProjects] in
                        libraryProjects.isReadOnly
                    }
                    versionCoordinator.projectReadOnlyGate = { [libraryProjects] in
                        libraryProjects.isReadOnly
                    }
                    MatchColorToolset.installLibraryProvider { [libraryProjects] in
                        await MainActor.run {
                            guard let store = libraryProjects.projectStore,
                                let url = libraryProjects.projectURL
                            else { return nil }
                            // T5 (M7-4-01; the 20997721 precedent's third
                            // instance): the anchor is the package's
                            // DIRECTORY — the .lalb FILE url would poison
                            // the pathKind 0/1 resolution (projectRelative
                            // rows append to it).
                            return (
                                LibraryStore(store: store),
                                url.deletingLastPathComponent())
                        }
                    }
                    // M7-2-01 (T1 action 4): the search/state context — every
                    // seam a provider closure, all @Observable reads inside a
                    // MainActor.run hop (the handler never touches an
                    // @Observable type). library carries the ProjectFileStore
                    // directly (E-1: the three route single sources all take
                    // one); writeCallCount rides the embedded handle (F-4②);
                    // the workspace face assembles from the app-level state
                    // objects — the per-window LibraryPhaseState (filter /
                    // selectedIDs) is not visible from this assembly point,
                    // those fields render null (the honest absent face,
                    // DECISIONS).
                    // M7-3 T4 (OQ-8): the library/sessionPair closures are
                    // lifted into ONE pair of local variables — the SAME
                    // closure values ride BOTH contexts (the search/state
                    // context and the project context), provider logic is
                    // never duplicated.
                    let librarySeam:
                        @Sendable () async -> (
                            store: ProjectFileStore, projectDirectory: URL
                        )? = { [libraryProjects] in
                            await MainActor.run {
                                guard let store = libraryProjects.projectStore,
                                    let url = libraryProjects.projectURL
                                else { return nil }
                                // The path-kind resolution anchor is the
                                // DIRECTORY holding the package (the
                                // WorkspaceHostView urlResolver 形 —
                                // projectRelative rows append to it; the
                                // match_color provider's file-URL works
                                // only because its rows ride the absolute
                                // kind).
                                return (store: store,
                                        projectDirectory: url.deletingLastPathComponent())
                            }
                        }
                    let sessionPairSeam:
                        @Sendable () async -> (
                            store: SessionIndexStore, root: URL
                        )? = { [sessionIndexController] in
                            await MainActor.run {
                                sessionIndexController.currentSession
                            }
                        }
                    let searchStateContext = McpSearchStateContext(
                        library: librarySeam,
                        sessionPair: sessionPairSeam,
                        semanticStore: { [libraryProjects] in
                            await MainActor.run {
                                libraryProjects.projectStore.map {
                                    SemanticStore(store: $0)
                                }
                            }
                        },
                        semantic: {
                            await AIInferenceService.shared.semanticSearcher()
                        },
                        fulltext: { [libraryProjects] query in
                            guard let store = await MainActor.run(body: {
                                libraryProjects.projectStore
                            }) else {
                                throw McpToolError.notSessionMember(
                                    "no open project — open a .lalb first")
                            }
                            return try await AIDescriptionService.imageIDs(
                                matching: query, store: store)
                        },
                        liveState: { [pipeCoordinator, editorState, exportState,
                                     sessionIndexController, libraryProjects] in
                            // The @Observable reads + the queue actor call
                            // compose the project/workspace/editor/tasks/
                            // server faces here (MainActor hops inside; the
                            // tool handler only ever sees the returned
                            // value snapshot).
                            let readOnly = await MainActor.run {
                                libraryProjects.isReadOnly
                            }
                            let projectPath: String? = await MainActor.run {
                                libraryProjects.projectURL?.path
                            }
                            let project: McpJSON
                            if let projectPath {
                                project = .object([
                                    "path": .string(projectPath),
                                    "readOnly": .bool(readOnly),
                                ])
                            } else {
                                project = .object([
                                    "path": .null,
                                    "readOnly": .null,
                                ])
                            }
                            let editor: McpJSON = await MainActor.run {
                                .object([
                                    "liveImageURL": pipeCoordinator.liveImageURL
                                        .map { .string($0.path) } ?? .null,
                                    "documentURL": editorState.loadedImageURL
                                        .map { .string($0.path) } ?? .null,
                                    "hasEdits":
                                        .bool(editorState.history.position >= 0),
                                ])
                            }
                            let sessionRoot: String? = await MainActor.run {
                                sessionIndexController.currentSession?.root.path
                            }
                            let tasks: McpJSON?
                            if let queue = await MainActor.run(body: {
                                exportState.queue
                            }) {
                                let jobs = await queue.snapshots()
                                var counts: [String: Int] = [:]
                                for job in jobs {
                                    switch job.state {
                                    case .pending:
                                        counts["pending", default: 0] += 1
                                    case .rendering, .encoding:
                                        counts["active", default: 0] += 1
                                    case .done:
                                        counts["done", default: 0] += 1
                                    case .failed:
                                        counts["failed", default: 0] += 1
                                    case .cancelled:
                                        counts["cancelled", default: 0] += 1
                                    }
                                }
                                counts["total"] = jobs.count
                                var object: [String: McpJSON] = [:]
                                for (key, value) in counts {
                                    object[key] = .int(value)
                                }
                                tasks = .object(object)
                            } else {
                                tasks = nil
                            }
                            let server: McpJSON = .object([
                                "name": .string(
                                    McpServerController.serverName),
                                "version": .string(
                                    McpServerController.serverVersion),
                                "hostMode": .string("embedded"),
                                "readOnly": .bool(readOnly),
                            ])
                            let workspace: McpJSON = .object([
                                // The per-window LibraryPhaseState (filter /
                                // selectedIDs / editorPhase.currentImageID)
                                // is not visible from this app-level
                                // assembly — those fields stay null (the
                                // honest absent face, DECISIONS).
                                "currentSessionRoot": sessionRoot
                                    .map { .string($0) } ?? .null,
                                "filterSummary": .null,
                                "selectedCount": .null,
                            ])
                            return McpSearchStateLiveSnapshot(
                                project: project, workspace: workspace,
                                editor: editor, tasks: tasks, server: server)
                        },
                        projectWriteProbe: projectWriteProbe,
                        writeCallCount: {
                            await McpServerController.embeddedWriteCallCount()
                        },
                        // M7-5-01 (D-M7-5-8): the get_state control.agent
                        // face rides the same coordinator (MainActor hop
                        // inside, the tool handler only sees the snapshot).
                        agentControl: { [agentControl] in
                            await MainActor.run { agentControl.currentState() }
                        })
                    // M7-3 T4: the GUI-embedded project context (D-M7-3-1
                    // GUI arm) — the controller-hop providers with the
                    // held-target pre-check BEFORE openProject (a held
                    // target never touches the controller: one agent call
                    // must not displace the user's currently-open project)
                    // and the before/after conflict DIFF (openProject
                    // answers a held target by PUBLISHING the dialog, no
                    // throw — the diff turns that into the typed
                    // projectReadOnly answer; the before==nil clause keeps
                    // a stale dialog from反向误报). The controller FILE
                    // itself stays zero-diff (FIX2③ stays M7-4); the
                    // promoteRecent face rides the controller's own
                    // semantics (the D-M7-3-9 asymmetry — DECISIONS).
                    let projectContext = McpProjectContext(
                        openProject: { [libraryProjects] url in
                            let lockURL = url.deletingPathExtension()
                                .appendingPathExtension("lalb.lock")
                            guard SingleWriterLock.probeLockAvailable(at: lockURL)
                            else {
                                throw McpToolError.projectReadOnly(
                                    SingleWriterLock.holderSummary(at: lockURL))
                            }
                            // The MainActor hop (the probe closure's direct
                            // await 形 — @Observable reads ride MainActor.run
                            // hops; openProject itself is @MainActor async).
                            let beforeStore = await MainActor.run {
                                libraryProjects.projectStore
                            }
                            let beforeConflict = await MainActor.run {
                                libraryProjects.pendingConflict
                            }
                            try await libraryProjects.openProject(at: url)
                            let afterConflict = await MainActor.run {
                                libraryProjects.pendingConflict
                            }
                            let afterStore = await MainActor.run {
                                libraryProjects.projectStore
                            }
                            if beforeConflict == nil,
                                afterConflict != nil,
                                // Reference identity (ProjectFileStore is
                                // a class — the diff clause is "the open
                                // store did not change").
                                afterStore === beforeStore {
                                throw McpToolError.projectReadOnly(
                                    SingleWriterLock.holderSummary(at: lockURL))
                            }
                            return ProjectOpenOutcome(url: url)
                        },
                        createProject: { [libraryProjects] url, name in
                            let lockURL = url.deletingPathExtension()
                                .appendingPathExtension("lalb.lock")
                            guard SingleWriterLock.probeLockAvailable(at: lockURL)
                            else {
                                throw McpToolError.projectReadOnly(
                                    SingleWriterLock.holderSummary(at: lockURL))
                            }
                            try await libraryProjects.createProject(
                                at: url, name: name)
                            return ProjectOpenOutcome(url: url)
                        },
                        library: librarySeam,
                        sessionPair: sessionPairSeam)
                    // M7-5-01 (D-M7-5-4..9): the coordinator-backed control
                    // face — every provider MainActor.run-hops into the
                    // App-level coordinator (the liveState discipline; the
                    // F-6 structure rule: the tool implementations never
                    // reference the coordinator type).
                    let controlContext = McpControlContext(
                        acquire: { [agentControl] holderName in
                            // The plain await IS the MainActor hop (the
                            // coordinator is @MainActor; MainActor.run's
                            // body is synchronous — the async acquire hops
                            // through the await).
                            try await agentControl.acquire(holderName)
                        },
                        release: { [agentControl] in
                            await MainActor.run { agentControl.release() }
                        },
                        state: { [agentControl] in
                            await MainActor.run { agentControl.currentState() }
                        })
                    await McpServerController.startEmbeddedIfPreferenceEnabled(
                        editing: editingSeams,
                        culling: cullingContext,
                        searchState: searchStateContext,
                        project: projectContext,
                        control: controlContext,
                        admit: { [agentControl] name in
                            // M7-6-01 (major-1): the coordinator-backed admit
                            // gate — the acquire-provider plain-await hop same
                            // precedent (the plain await IS the MainActor hop;
                            // the coordinator is @MainActor).
                            try await agentControl.admit(toolName: name)
                        })
    }
    private func newLibraryProjectFromPanel() async {
        guard let url = await LibraryPanels.newProject() else { return }
        do {
            try await libraryProjects.createProject(
                at: url, name: url.deletingPathExtension().lastPathComponent)
            graph.libraryWelcomePresented = false
        } catch {
            libraryProjects.reportError(error.localizedDescription)
        }
    }

    private func openLibraryProjectFromPanel() async {
        guard let url = await LibraryPanels.openProject() else { return }
        do {
            try await libraryProjects.openProject(at: url)
            // M6-1-01: a published conflict answers through the dialog —
            // the welcome only dismisses on a clean open.
            if libraryProjects.pendingConflict == nil {
                graph.libraryWelcomePresented = false
            }
        } catch {
            libraryProjects.reportError(error.localizedDescription)
        }
    }

    private func importFolderFromPanel() async {
        guard let folder = await LibraryPanels.folder(title: "Import Folder") else { return }
        // Seed the dialog choice OUTSIDE any view body (the D-EXEC-1
        // no-defaults-in-body discipline).
        let defaults = ImportDefaults()
        graph.libraryImportChoice = ImportModeChoice(
            mode: defaults.resolvedMode(), remember: defaults.rememberMode)
        graph.libraryImportRequest = ImportFlowRequest(folder: folder)
    }

    private func backupProjectFromPanel() async {
        guard libraryProjects.projectStore != nil else { return }
        let stem = libraryProjects.projectURL?
            .deletingPathExtension().lastPathComponent ?? "Project"
        guard let destination = await LibraryPanels.destination(
            title: "Backup Project",
            defaultName: stem + "-backup." + LibrarySchema.fileExtension)
        else { return }
        do {
            try await libraryProjects.backupProject(to: destination)
        } catch {
            libraryProjects.reportError(error.localizedDescription)
        }
    }

    private func moveProjectFromPanel() async {
        guard let packageURL = libraryProjects.projectURL else { return }
        let stem = packageURL.deletingPathExtension().lastPathComponent
        guard let picked = await LibraryPanels.folder(title: "Move Project To") else { return }
        // The open panel picks an existing parent; the moved directory
        // takes the project's stem inside it.
        let destination = picked.appendingPathComponent(stem)
        do {
            try await libraryProjects.moveProject(to: destination)
        } catch {
            libraryProjects.reportError(error.localizedDescription)
        }
    }
    // MARK: - View menu actions (via focused binding into ContentView)

    // ── 12-1 T6 metadata command routing ───────────────────────────────────
    // Targets = the browser/culling SELECTION when non-empty, else the
    // editor's CURRENT image (if inside the open session) — the three
    // states (grid / culling / single) share one routing shape.

    /// Plan 08-1 T5: the post-merge grid refresh + the completion toast —
    /// MainActor-isolated (the completion hook hops here). The product
    /// landed in the session ROOT, so the browse set picks it up through
    /// the EXPLICIT reconcile ingest (the import seam's posture).
    @MainActor
    private func refreshGridAfterMerge(holeFraction: Float) async {
        // V2M-01 T5 (defect D-5): the interpolation is Int-ized to match
        // the catalog's `%lld` variant (`toast_hdr_merge_done %lld`,
        // xcstrings in-manual). The old Float interpolation looked the key
        // up as `%lf` - a guaranteed miss rendering the bare key face.
        // `rounded()` on the half boundary rounds away from zero (the
        // Foundation rounding rule for .rounded()); a 12.34% hole
        // presents as 12 - the integer-percentage semantics the catalog
        // strings are written in.
        let message = String(localized:
            "toast_hdr_merge_done \(Int((holeFraction * 100).rounded()))")
        editorState.presentToast(message)
        if let root = sessionState.currentSessionURL {
            _ = await sessionReconciler.reconcileHandler?(root)
            if let store = sessionIndexController.currentStore {
                await browserModel.reload(store: store, includeOrphans: true)
            }
        }
    }

    private func metadataTargets() -> [String] {
        let selected = browserModel.selectedOrderedPaths
        if !selected.isEmpty { return selected }
        if let root = sessionState.currentSessionURL,
           let loaded = editorState.loadedImageURL {
            let prefix = root.path + "/"
            if loaded.path.hasPrefix(prefix) {
                return [String(loaded.path.dropFirst(prefix.count))]
            }
        }
        return []
    }

    /// The LIVE target set (12-4): the currently edited image's relPath —
    /// the batch loop skips it and the interactive layer installs it
    /// (empty when nothing is loaded / outside the session root).
    private func currentImageRelPaths() -> Set<String> {
        guard let root = sessionState.currentSessionURL,
              let loaded = editorState.loadedImageURL else { return [] }
        let prefix = root.path + "/"
        guard loaded.path.hasPrefix(prefix) else { return [] }
        return [String(loaded.path.dropFirst(prefix.count))]
    }

    private func applyRating(_ value: Int?) {
        let targets = metadataTargets()
        guard !targets.isEmpty else { return }
        Task { await metadataController.setRating(value, relPaths: targets) }
    }

    /// V14/FINDING-G (M3-1-03 KD-4): the rating menu labels resolved
    /// through an EXPLICIT switch returning STATIC keys. The old shape —
    /// `String(localized: String.LocalizationValue("metadata_rating_\(stars)"))`
    /// — built the lookup key at runtime, invisible to the zh-audit
    /// extractor (the F-2 interpolated-literal trap family). The 11 keys
    /// are in the catalog WITH zh values; this is shape hardening (the
    /// keys become extractor-visible and auditable), not key addition.
    private func ratingMenuLabel(_ stars: Int) -> String {
        switch stars {
        case 1: return String(localized: "metadata_rating_1")
        case 2: return String(localized: "metadata_rating_2")
        case 3: return String(localized: "metadata_rating_3")
        case 4: return String(localized: "metadata_rating_4")
        case 5: return String(localized: "metadata_rating_5")
        default: return String(localized: "metadata_rating_clear")
        }
    }

    /// V14/FINDING-G (M3-1-03 KD-4): the color-label menu's static-key
    /// twin of `ratingMenuLabel`.
    private func colorMenuLabel(_ label: Int) -> String {
        switch label {
        case 0: return String(localized: "metadata_color_0")
        case 1: return String(localized: "metadata_color_1")
        case 2: return String(localized: "metadata_color_2")
        case 3: return String(localized: "metadata_color_3")
        case 4: return String(localized: "metadata_color_4")
        case 5: return String(localized: "metadata_color_5")
        default: return String(localized: "metadata_color_clear")
        }
    }

    private func applyColor(_ value: Int?) {
        let targets = metadataTargets()
        guard !targets.isEmpty else { return }
        Task { await metadataController.setColorLabel(value, relPaths: targets) }
    }

    private func applyFlag(_ value: Int?) {
        let targets = metadataTargets()
        guard !targets.isEmpty else { return }
        Task { await metadataController.setFlag(value, relPaths: targets) }
    }

    /// The X/P toggle: read the targets' current flags — ALL carry the
    /// value → clear it on all; otherwise set it on all (the uniform Lr
    /// rule; single-target toggle is the natural case).
    private func toggleFlag(_ value: Int) {
        let targets = metadataTargets()
        guard !targets.isEmpty else { return }
        Task {
            var allCarry = true
            for rel in targets {
                if await metadataController.snapshot(relPath: rel)?.flag
                    != Int64(value) {
                    allCarry = false
                    break
                }
            }
            await metadataController.setFlag(
                allCarry ? nil : value, relPaths: targets)
        }
    }
    /// D-X2 probe (Plan 02-03 manual resize verification — RETIRE after
    /// verification per the D-X2 probe policy): osascript/AX window
    /// resizing is unavailable to headless drivers (no Accessibility grant
    /// for the CLI), so `-la_resize_probe` drives the REAL window-geometry
    /// chain (NSWindow.setFrame → drawable resize → GeometryReader →
    /// `PipeCoordinator.drawableDidChange`) through a scripted sequence
    /// sized for this 1504×846pt display (viewport ≈ window − 260pt, long
    /// edge height-capped): t+6s within-bucket grow (2200 stays 2200),
    /// t+14s aggressive shrink crossing down to the 1120 bucket (exactly
    /// one re-render), t+22s within-bucket jitter (no re-render).
    /// `#if DEBUG`: never ships.
    #if DEBUG
    private nonisolated(unsafe) static var resizeProbeArmed = false
    private func resizeProbeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-la_resize_probe") else { return }
        guard !Self.resizeProbeArmed else { return } // .task can re-run on scene re-activation
        Self.resizeProbeArmed = true
        let logger = Logger(subsystem: "com.kamasylvia.lightamer", category: "probe")
        logger.info("resize probe armed")
        let sequence: [(Double, CGFloat, CGFloat)] = [
            (6, 1460, 920), // grow within the current bucket → no re-render
            (14, 1000, 700), // cross DOWN a bucket boundary → exactly one re-render
            (22, 990, 695), // jitter within the new bucket → no re-render
        ]
        for (delay, width, height) in sequence {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                for window in NSApp.windows where window.isVisible {
                    var frame = window.frame
                    frame.origin.y += frame.height - height
                    frame.size = CGSize(width: width, height: height)
                    window.setFrame(frame, display: true)
                    logger.info("resize probe: window → \(Int(width))×\(Int(height))")
                }
            }
        }
    }
    #endif

    // ── Defect-A import probe (the fix special, DEBUG-only): the GUI-shaped
    // drive of the PRODUCTION import chain — `createProject` + `runImport`
    // run on the MainActor exactly as the sheet's onConfirm Task does (the
    // panels are the only layer removed). The first existing directory
    // argument is the import source; the project is a throwaway /tmp
    // package. PASS = runImport's completion publication face
    // (`importProgress == nil`); a hang leaves the probe silent after
    // "armed" (sample the process then). Terminate-on-done keeps the run
    // scriptable.
    #if DEBUG
    private nonisolated(unsafe) static var importProbeArmed = false
    private func importProbeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-la_import_probe") else { return }
        guard !Self.importProbeArmed else { return } // .task can re-run on re-activation
        Self.importProbeArmed = true
        let probe = Logger(subsystem: "com.kamasylvia.lightamer", category: "probe")
        // stderr twin: the probe runner tails stdout (oslog needs `log show`).
        func note(_ line: String, os only: Bool = false) {
            if !only { FileHandle.standardError.write(Data("[import-probe] \(line)\n".utf8)) }
            probe.info("\(line, privacy: .public)")
        }
        let args = ProcessInfo.processInfo.arguments.dropFirst()
        guard let folder = args.first(where: {
            !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
        }).map({ URL(fileURLWithPath: $0, isDirectory: true) }) else {
            note("FAIL: no source folder argument")
            NSApp.terminate(nil)
            return
        }
        Task {
            let package = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-probe-\(UUID().uuidString).lalb")
            do {
                try await libraryProjects.createProject(at: package, name: "ImportProbe")
            } catch {
                note("FAIL: createProject threw: \(error)")
                NSApp.terminate(nil)
                return
            }
            guard libraryProjects.projectStore != nil else {
                note("FAIL: createProject did not open the store")
                NSApp.terminate(nil)
                return
            }
            note("armed — quiescing 12s (walkthrough hang hit the idle run loop)")
            try? await Task.sleep(for: .seconds(12))
            await libraryProjects.runImport(
                folder: folder,
                choice: ImportModeChoice(mode: .link, remember: false))
            if libraryProjects.importProgress == nil {
                note("PASS: run 1 completion published (importProgress == nil)")
            } else {
                note("FAIL: run 1 returned with importProgress non-nil")
            }
            // The walkthrough shape: a SECOND import into the now-NON-EMPTY
            // project (the 2/2 reproductions were both second-run legs —
            // 34/40 = 6 pre-existing rows + 34 fresh).
            await libraryProjects.runImport(
                folder: folder,
                choice: ImportModeChoice(mode: .link, remember: false))
            if libraryProjects.importProgress == nil {
                note("PASS: run 2 completion published (importProgress == nil)")
            } else {
                note("FAIL: run 2 returned with importProgress non-nil")
            }
            NSApp.terminate(nil)
        }
    }
    #endif
    // ── 09-04 HIST-05: copy + paste routing (the app-root owns the whole
    // state graph — the menu commands orchestrate, the states never
    // reference each other, D-03b) ─────────────────────────────────────────

    /// ⌘⇧C: freeze the CURRENT image's effective adjustments into the
    /// clipboard (the skip set applies inside `compose`).
    private func copyAdjustments() async {
        guard editorState.loadedImageURL != nil else { return }
        let effective = editorState.history.effectiveInstances()
        let layerRecord = editorState.layerStack
            .map { SidecarLayerStackRecord($0) }
            .flatMap { $0.layers.isEmpty ? nil : $0 }
        let payload = PastePayload.compose(
            sourceImageID: pipeCoordinator.currentImageID ?? UUID(),
            sourceURL: editorState.loadedImageURL,
            sourceInstances: editorState.instances,
            sourceEffective: effective,
            seed: await seedInstances(),
            layerStack: layerRecord)
        pasteboard.copy(payload)
    }

    /// ⌘⇧V / the partial dialog's paste: route the payload onto the
    /// browser selection (batch, segments 1-3) with the CURRENT image's
    /// relPath carved out as the LIVE target (dt
    /// `_safe_history_job_on_imgid`: the edited image goes through the
    /// interactive layer, never the batch loop). Without a session
    /// selection, the current image alone is the live target.
    private func pasteToSelection(
        selection: Set<PastePayload.InstanceKey>?, mode: PasteMode
    ) async {
        guard let payload = pasteboard.peek(), !payload.instances.isEmpty else {
            return
        }
        // M6-1-01 omp E-OMP-1 (c): the batch entry's project-face gate —
        // SessionBatchApplier + graph.batchSidecarWriter land .lra bytes directly,
        // so a read-only project refuses HERE with the one-shot toast (the
        // legacy session face stays ungated: no project open = the gate
        // reads false — the KD-5 m2 two-face split). The live-image leg is
        // separately backstopped by the EditorState install guards.
        if Self.batchPasteBlocked(gate: editorState.projectReadOnlyGate) {
            editorState.presentToast(
                Self.readOnlyPasteToast(holderPid: libraryProjects.readOnlyHolderPid))
            return
        }
        let seed = await seedInstances()
        let targets = browserModel.selectedOrderedPaths
        let sessionRoot = sessionState.currentSessionURL
        let store = sessionIndexController.currentStore

        if let sessionRoot, let store, !targets.isEmpty {
            // The live relPath: the currently edited image, relative to the
            // session root (nil when nothing is loaded / outside the root).
            var liveRelPaths = Set<String>()
            if let loaded = editorState.loadedImageURL {
                let loadedPrefix = sessionRoot.path + "/"
                if loaded.path.hasPrefix(loadedPrefix) {
                    liveRelPaths.insert(String(loaded.path.dropFirst(loadedPrefix.count)))
                }
            }
            _ = await SessionBatchApplier.apply(
                root: sessionRoot,
                relPaths: targets,
                payload: payload,
                mode: mode,
                seed: seed,
                selection: selection,
                liveRelPaths: liveRelPaths,
                store: store,
                writer: graph.batchSidecarWriter,
                label: String(localized: "history_paste_adjustments"))
            // The grid's hasEdits/dirty badges refresh from the claimed
            // rows (the thumbnails regenerate through the 9-3 queue).
            await browserModel.reload(store: store, includeOrphans: true)
            // The LIVE target pastes through the interactive layer (the
            // composed stack lands via EditorState; ONE ⌘Z undoes it).
            if let liveRel = liveRelPaths.first, targets.contains(liveRel) {
                await pasteLive(payload: payload, selection: selection, mode: mode, seed: seed)
            }
        } else if editorState.loadedImageURL != nil {
            // No session selection — the current image is the target.
            await pasteLive(payload: payload, selection: selection, mode: mode, seed: seed)
        }
    }

    // MARK: - M6-1-01 omp E-OMP-1 (c): the batch-paste read-only face

    /// The batch entry predicate: true = the read-only face must refuse the
    /// paste. Internal + pure so the golden gate asserts the refusal without
    /// constructing the App struct; `pasteToSelection` consults it with the
    /// live EditorState gate (nil = writable — the zero-diff default).
    static func batchPasteBlocked(gate: (() -> Bool)?) -> Bool {
        gate?() ?? false
    }

    /// The refusal copy — the banner key family (the read-only open toast's
    /// exact shape), pid interpolation included.
    static func readOnlyPasteToast(holderPid: Int32?) -> String {
        String(
            localized: "project_read_only_banner",
            defaultValue: "只读——项目已由另一实例（pid \(holderPid.map(String.init) ?? "未知")）打开")
    }

    /// The LIVE paste leg (the currently edited image): compose against
    /// EditorState's in-memory stack and install — ONE commit, ⌘Z-able.
    private func pasteLive(
        payload: PastePayload, selection: Set<PastePayload.InstanceKey>?,
        mode: PasteMode, seed: [ModuleInstance]
    ) async {
        let composed = PasteSemantics.paste(
            targetHistory: editorState.history,
            targetInstances: editorState.instances,
            payload: payload,
            mode: mode,
            seed: seed,
            selection: selection,
            label: String(localized: "history_paste_adjustments"))
        guard let composed else { return }
        switch mode {
        case .merge:
            editorState.installMergePaste(history: composed.history)
        case .overwrite:
            editorState.installOverwritePaste(
                history: composed.history, seed: seed)
        }
    }

    /// The identity-default seed (terminal trio + the editing defaults).
    /// M2-1: the face rides `isFullFaceRequested` (KD-3) so every seed
    /// consumer — pristine loads, preset/batch apply compose bases, the
    /// MCP metadata seed — narrows with the same one switch.
    private func seedInstances() async -> [ModuleInstance] {
        (
            await moduleRegistry.makeDefaultInstances()
                + LightamerIOPRegistry.editingDefaultInstances(
                    defaultFace: !LightamerIOPRegistry.isFullFaceRequested)
        )
        .sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }
    // MARK: - 02-06 headless sidecar round-trip probe (DEBUG only)

    #if DEBUG
    /// Headless round-trip driver for the SC#3 acceptance artifact
    /// (`.work/plans/02-06/roundtrip.md`) — `resizeProbeIfRequested`-style:
    /// AX/menus are unavailable to headless drivers, so the probe applies
    /// the edit and quits by itself. Launch via LaunchServices so window
    /// creation is deterministic (direct exec behind a fullscreen space is
    /// flaky): `open -a Lightamer.app <image> --args -la_sidecar_probe` —
    /// the image then arrives through the odoc open event (openHandler);
    /// direct-exec argv images are also covered. Every verdict is mirrored
    /// into the unified log (stdout is detached under `open`).
    ///
    /// Modes, decided by sidecar presence AFTER the first render:
    /// - **edit** (no `.lra` beside the image): commits one `testgain 1.5×`
    ///   history item via the REAL D-H1 trio, waits past the 2s throttle,
    ///   prints the rendered-plane hash, then terminates (the synchronous
    ///   willTerminate flush covers any straggler).
    /// - **verify** (`.lra` exists): logs the restored history/position/
    ///   paramsHash + the rendered-plane hash — run1 vs run2 hashes must
    ///   match for the round-trip to PASS.
    private nonisolated(unsafe) static var sidecarProbeArmed = false

    private func sidecarProbeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-la_sidecar_probe") else { return }
        guard !Self.sidecarProbeArmed else { return } // .task can re-run on re-activation
        Self.sidecarProbeArmed = true
        let probe = Logger(subsystem: "com.kamasylvia.lightamer", category: "probe")

        // argv[0] is the executable path — scan only real arguments. nil =
        // the image arrives through the odoc open event instead.
        let args = ProcessInfo.processInfo.arguments.dropFirst()
        let argImage = args.first(where: {
            !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
        }).map { URL(fileURLWithPath: $0) }

        Task {
            if let url = argImage {
                probe.info("probe armed — loading \(url.lastPathComponent, privacy: .public) from argv")
                editorState.load(
                    url: url, decoder: decoder, metal: metalContext,
                    logger: EditorState.decodeLogger
                )
            } else {
                probe.info("probe armed — waiting for the odoc open event")
                for _ in 0..<200 where editorState.loadedImageURL == nil {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard editorState.loadedImageURL != nil else {
                    print("[probe] FAIL: no image opened within 20s")
                    probe.error("probe FAIL: no image opened within 20s")
                    NSApp.terminate(nil)
                    return
                }
            }
            // Wait for the first rendered plane (decode + PREVIEW leg),
            // then let the GPU command buffer DRAIN before reading bytes —
            // getBytes on shared memory does not wait for in-flight
            // encoders (the verify leg reads ~40ms after the render push;
            // without the drain it hashes half-written memory).
            for _ in 0..<600 where editorState.displayTexture == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(800))
            pipeCoordinator.drainGPUForProbe()
            guard editorState.displayTexture != nil,
                  let url = editorState.loadedImageURL else {
                print("[probe] FAIL: no render within 60s")
                probe.error("probe FAIL: no render within 60s")
                NSApp.terminate(nil)
                return
            }
            let destination = LightamerSidecar.sidecarURL(for: url)

            if FileManager.default.fileExists(atPath: destination.path) {
                // ── VERIFY (run 2) ──
                if ProcessInfo.processInfo.arguments.contains("-la_sidecar_dump"),
                   let image = editorState.image, let metal = metalContext {
                    let inputPlaneOpt = try? await RenderPipeline.render(
                        image: image, layerStack: nil, metal: metal
                    )
                    if let inputPlane = inputPlaneOpt {
                        let rowBytes = inputPlane.width * 16
                        var f = [Float](repeating: 0, count: inputPlane.width * inputPlane.height * 4)
                        f.withUnsafeMutableBufferPointer { ptr in
                            inputPlane.getBytes(
                                ptr.baseAddress!, bytesPerRow: rowBytes,
                                from: MTLRegionMake2D(0, 0, inputPlane.width, inputPlane.height),
                                mipmapLevel: 0
                            )
                        }
                        pipeCoordinator.drainGPUForProbe()
                        let mid = (inputPlane.height / 2 * inputPlane.width + inputPlane.width / 2) * 4
                        AppError.logger.info(
                            "probe input-plane mid RGBA: \(f[mid], privacy: .public) \(f[mid+1], privacy: .public) \(f[mid+2], privacy: .public)"
                        )
                    }
                }
                let restored = editorState.history
                let labels = restored.items.map(\.label).joined(separator: " | ")
                let gainHash = restored.currentValue?.paramsHash ?? 0
                let displayHash = Self.displayPlaneHash(editorState.displayTexture) ?? 0
                print("[probe] mode=verify history=\(restored.position + 1)/\(restored.items.count) position=\(restored.position)")
                print("[probe] labels=\(labels)")
                print("[probe] topParamsHash=\(gainHash)")
                print("[probe] displayHash=\(displayHash)")
                print("[probe] instances=\(editorState.instances.count)")
                probe.info("probe mode=verify history=\(restored.position + 1, privacy: .public)/\(restored.items.count, privacy: .public) position=\(restored.position, privacy: .public) topParamsHash=\(String(gainHash, radix: 16), privacy: .public) displayHash=\(String(displayHash, radix: 16), privacy: .public) instances=\(editorState.instances.count, privacy: .public)")
            } else {
                // ── EDIT (run 1): apply one testgain commit via the trio ──
                let snapshot = ModuleInstance(
                    module: TestGainModule.self, multiName: "probe",
                    params: .init(gain: 1.5)
                )
                pipeCoordinator.beginContinuousEdit()
                await pipeCoordinator.setLiveParams(snapshot)
                await pipeCoordinator.commitContinuousEdit(label: "probe testgain 1.5×")
                probe.info("probe edit committed — waiting for the 2s throttled flush")
                for _ in 0..<200 where !FileManager.default.fileExists(atPath: destination.path) {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard FileManager.default.fileExists(atPath: destination.path) else {
                    print("[probe] FAIL: sidecar not written within 10s")
                    NSApp.terminate(nil)
                    return
                }
                let displayHash = Self.displayPlaneHash(editorState.displayTexture) ?? 0
                print("[probe] mode=edit sidecar flushed: \(destination.lastPathComponent)")
                print("[probe] displayHash=\(displayHash)")
                probe.info("probe mode=edit sidecar flushed, displayHash=\(String(displayHash, radix: 16), privacy: .public)")
            }
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.terminate(nil) // triggers willTerminate → flushForTermination
        }
    }

    /// FNV hash of the display-plane bytes (`.bgra8Unorm` handoff plane;
    /// NOT a drawable — readback is legal). Same-hash run1 vs run2 proves
    /// the restored state re-renders identically (SC#3). With
    /// `-la_sidecar_dump`, the raw bytes also land in /tmp for byte-level
    /// diffing (probe diagnostics only).
    static func displayPlaneHash(_ texture: (any MTLTexture)?) -> UInt64? {
        guard let texture else { return nil }
        let rowBytes = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * texture.height)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
        )
        if ProcessInfo.processInfo.arguments.contains("-la_sidecar_dump") {
            let url = URL(fileURLWithPath: "/tmp/lra-display-dump.bin")
            try? Data(bytes).write(to: url)
            AppError.logger.info(
                "probe dump: \(texture.width, privacy: .public)x\(texture.height, privacy: .public) → /tmp/lra-display-dump.bin"
            )
        }
        return StableHash.hash(bytes)
    }

    #endif
    func installMenu() {
        NSMenuBridgeController.shared.install(deps: .init(
            editorState: editorState,
            sessionState: sessionState,
            libraryProjects: libraryProjects,
            agentControl: agentControl,
            pasteboard: pasteboard,
            softProofState: softProofState,
            // F0P-01 T3 (review m6): the B18 export PAGE leg's truth.
            inspectorState: inspectorState,
            legacyLibraryEnabled: legacyLibraryEnabled,
            openImage: {
                Task {
                    await FileOpener.openImage { url in
                        self.editorState.load(
                            url: url, decoder: self.decoder,
                            metal: self.metalContext,
                            logger: EditorState.decodeLogger)
                    }
                }
            },
            openSession: { url in
                Task { await self.sessionCoordinator.openSession(url: url) }
            },
            // F0P-01 T3 (review M4): the ⇧⌘O production body — the
            // FileOpener.openSessionFolder picker seam (the same shape the
            // SwiftUI command runs).
            openSessionPicker: {
                Task {
                    await FileOpener.openSessionFolder { url in
                        Task { await self.sessionCoordinator.openSession(url: url) }
                    }
                }
            },
            newProject: { Task { await self.newLibraryProjectFromPanel() } },
            openProject: { Task { await self.openLibraryProjectFromPanel() } },
            openRecentProject: { url in
                Task {
                    try? await self.libraryProjects.openProject(at: url)
                    if self.libraryProjects.pendingConflict == nil {
                        self.graph.libraryWelcomePresented = false
                    }
                }
            },
            importFolder: { Task { await self.importFolderFromPanel() } },
            backupProject: { Task { await self.backupProjectFromPanel() } },
            moveProject: { Task { await self.moveProjectFromPanel() } },
            enterEditor: {
                NSMenuBridgeController.shared.workspace?
                    .openEditor(imageID: nil)
            },
            backToLibrary: {
                NSMenuBridgeController.shared.workspace?.closeEditor()
            },
            searchLibrary: {
                NSMenuBridgeController.shared.workspace?.isSearchDialogPresented = true
            },
            // F0P-01 T6: the export gate fork — the gate=false M2 PAGE leg
            // goes straight to openExportPage (the F0PRIME §1.1 same-seam
            // ruling); the gate=true sheet leg raises the legacy sheet
            // through the pre-flip focused-value WRITE path (the App struct
            // Commands' @FocusedBinding role, moved into this face). If the
            // focused publisher is absent under the hosting bridge (reads
            // nil), the page seam degrades in honestly — the same
            // InspectorView export page renders in both faces.
            export: {
                if self.legacyLibraryEnabled, self.focusedExportRequest != nil {
                    self.focusedExportRequest = true
                } else {
                    self.inspectorState.openExportPage()
                }
            },
            undo: { Task { await self.pipeCoordinator.undo() } },
            redo: { Task { await self.pipeCoordinator.redo() } },
            copyAdjustments: { Task { await self.copyAdjustments() } },
            pasteAdjustments: {
                Task { await self.pasteToSelection(selection: nil, mode: .merge) }
            },
            pastePartial: { self.graph.pastePartialRequested = true },
            copyAdjustmentsDialog: { self.graph.adjustmentTransferPresented = true },
            // F0P-01 T6 (the four spike stubs productionized): the three
            // window controllers + the column toggles (the
            // toggleSidebar/toggleInspector semantics translated verbatim
            // onto ShellGraph.shared.columnVisibility).
            presetManager: { self.presentPresetManager?() },
            mcpLauncher: { self.presentMcpLauncher?() },
            settings: { self.presentSettings?() },
            filmPanel: { self.inspectorState.openFilmPage() },
            showSidebar: {
                let visibility = ShellGraph.shared.columnVisibility
                ShellGraph.shared.columnVisibility =
                    (visibility == .doubleColumn) ? .all : .doubleColumn
            },
            showInspector: {
                let visibility = ShellGraph.shared.columnVisibility
                ShellGraph.shared.columnVisibility =
                    (visibility == .detailOnly) ? .all : .detailOnly
            },
            toggleSoftProof: {
                self.softProofState.toggle(coordinator: self.pipeCoordinator)
            },
            setGamutCheck: {
                self.softProofState.setGamutCheck(
                    !self.softProofState.gamutCheck,
                    coordinator: self.pipeCoordinator)
            },
            actualSize: { self.viewportState.actualSize() },
            fitToScreen: { self.viewportState.fit() },
            expandAllStacks: {
                NSMenuBridgeController.shared.workspace?
                    .requestStackCommand(.expandAll)
            },
            collapseAllStacks: {
                NSMenuBridgeController.shared.workspace?
                    .requestStackCommand(.collapseAll)
            },
            toggleToolRail: {
                NSMenuBridgeController.shared.workspace?.toolRailVisible.toggle()
            },
            toggleScopes: {
                NSMenuBridgeController.shared.workspace?.scopesVisible.toggle()
            },
            toggleAdjustmentStack: {
                NSMenuBridgeController.shared.workspace?.adjustmentStackVisible.toggle()
            },
            applyRating: { self.applyRating($0) },
            applyFlag: { self.applyFlag($0) },
            toggleFlag: { self.toggleFlag($0) },
            applyColor: { self.applyColor($0) },
            aiUpscale: {
                guard let workspace = NSMenuBridgeController.shared.workspace,
                    let id = workspace.editorPhase.currentImageID
                else { return }
                workspace.requestAIEnhance(kind: .upscale, imageIDs: [id])
            },
            aiDenoise: {
                guard let workspace = NSMenuBridgeController.shared.workspace,
                    let id = workspace.editorPhase.currentImageID
                else { return }
                workspace.requestAIEnhance(kind: .denoise, imageIDs: [id])
        }))
    }
}

/// The shell owner: the App struct's state graph as plain class properties
/// (the same objects, one owner, no SwiftUI lifecycle).
@MainActor
final class LightamerShellController {

    // F0P-01 (review M2): the ONE shared graph instance (ShellGraph.swift).
    let graph = ShellGraph.shared
    let appDelegate = AppDelegate()
    let sessionState = SessionState()
    let editorState = EditorState()
    let pipeCoordinator = PipeCoordinator()
    let versionCoordinator = VersionCoordinator()
    let exportState = ExportState()
    let inspectorState = InspectorState()
    let agentControl = AgentControlCoordinator()
    let layerEditingState = LayerEditingState()
    let sessionCoordinator = SessionCoordinator()
    let sessionIndexController = SessionIndexController()
    let sessionReconciler = SessionReconciler()
    let aiDownloadModel = AIDownloadModel()
    let depthMaskService = DepthMaskService()
    let browserModel = SessionBrowserModel()
    let thumbnailMemoryCache = ThumbnailMemoryCache()
    let pasteboard = AdjustmentsPasteboard()
    let cleanTerminateStore = CleanTerminateSentinelStore()
    let metadataController = MetadataController()
    let beforeAfterState = BeforeAfterState()
    let softProofState = SoftProofState()
    let edrHeadroomMonitor = EDRHeadroomMonitor()
    let viewportState = ViewportState()
    let browserLogoStore = YiyinLogoStore()
    let smartAlbumStore = SmartAlbumStore()
    let catalogPreferences = CatalogPreferencesModel()
    let catalogBrowserModel = CatalogBrowserModel()
    let catalogTreeModel = CatalogTreeModel()
    let presetsStore = PresetsStore()
    let presetController = PresetController()
    let decoder = RAWDecoder()
    let mcpWriteFace = McpWriteFaceBox()
    let moduleRegistry = ModuleRegistry.makeDefault()
    let metalContext: MetalContext? = (try? MetalContext())
    let colorMatchService = ColorMatchService()
    let libraryProjects = LibraryProjectController()
    private let legacyLibraryEnabled = LibraryLegacyGate.isLegacyLibraryRequested()

    private var mainWindow: NSWindow?

    // F0P-01 T4/T6: the three secondary-window controllers (D-F0P-1 — the
    // real Settings window; the spike's stubs productionized). Lazy: the
    // windows build their hosting content on first showWindow.
    private lazy var presetManagerWindowController = PresetManagerWindowController(
        presetsStore: presetsStore, presetController: presetController)
    private lazy var mcpLauncherWindowController = McpLauncherWindowController()
    private lazy var settingsWindowController = SettingsWindowController(
        legacyLibraryEnabled: legacyLibraryEnabled,
        catalogPreferences: catalogPreferences,
        pipeCoordinator: pipeCoordinator,
        libraryProjects: libraryProjects)

    func presentPresetManagerWindow() {
        presetManagerWindowController.showWindow(nil)
    }
    func presentMcpLauncherWindow() {
        mcpLauncherWindowController.showWindow(nil)
    }
    func presentSettingsWindow() {
        settingsWindowController.showWindow(nil)
    }

    init() {
        #if DEBUG
        LightamerApp.runAIDeterminismProbeIfRequested()
        #endif
    }

    func applicationDidFinishLaunching() {
        mainWindow = presentMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }
    /// D-F0P-4's reopen face: show the existing main window, or rebuild it
    /// when the handle is gone (D-F0P-6: the always-one-main-window ruling).
    func reopenMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            mainWindow = presentMainWindow()
        }
    }
    func presentMainWindow() -> NSWindow {
        let face = makeFace()
        face.installMenu()
        let hosting = NSHostingView(rootView: face)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                        // D-F0P-4: the fullscreen space (SwiftUI default
                        // behavior alignment; the spike shape lacked it).
                        .fullScreen],
            backing: .buffered, defer: false)
        window.title = "Lightamer"
        window.contentView = hosting
        window.center()
        // D-F0P-8: the production autosave key (the spike's experiment name
        // never ships — a rename would orphan the user's window frame).
        window.setFrameAutosaveName("LightamerMainWindow")
        window.makeKeyAndOrderFront(nil)
        return window
    }

    func makeFace() -> LightamerShellFace {
        LightamerShellFace(
            graph: graph,
            graphB: Bindable(graph),
            appDelegate: appDelegate,
            sessionState: sessionState,
            editorState: editorState,
            pipeCoordinator: pipeCoordinator,
            versionCoordinator: versionCoordinator,
            exportState: exportState,
            inspectorState: inspectorState,
            agentControl: agentControl,
            layerEditingState: layerEditingState,
            sessionCoordinator: sessionCoordinator,
            sessionIndexController: sessionIndexController,
            sessionReconciler: sessionReconciler,
            aiDownloadModel: aiDownloadModel,
            depthMaskService: depthMaskService,
            browserModel: browserModel,
            thumbnailMemoryCache: thumbnailMemoryCache,
            pasteboard: pasteboard,
            cleanTerminateStore: cleanTerminateStore,
            metadataController: metadataController,
            beforeAfterState: beforeAfterState,
            softProofState: softProofState,
            edrHeadroomMonitor: edrHeadroomMonitor,
            viewportState: viewportState,
            browserLogoStore: browserLogoStore,
            smartAlbumStore: smartAlbumStore,
            catalogPreferences: catalogPreferences,
            catalogBrowserModel: catalogBrowserModel,
            catalogTreeModel: catalogTreeModel,
            presetsStore: presetsStore,
            presetController: presetController,
            decoder: decoder,
            mcpWriteFace: mcpWriteFace,
            moduleRegistry: moduleRegistry,
            metalContext: metalContext,
            colorMatchService: colorMatchService,
            libraryProjects: libraryProjects,
            legacyLibraryEnabled: legacyLibraryEnabled,
            // F0P-01 T6: the window-controller seams (the face is a struct —
            // the controller hands in [weak self] closures).
            presentPresetManager: { [weak self] in
                self?.presentPresetManagerWindow()
            },
            presentMcpLauncher: { [weak self] in
                self?.presentMcpLauncherWindow()
            },
            presentSettings: { [weak self] in
                self?.presentSettingsWindow()
            })
    }
}

/// NSApplicationDelegate face — composes the production `AppDelegate` (it is
/// `final`; the open-AppleEvent routing and the synchronous willTerminate
/// flush are forwarded verbatim).
@MainActor
final class LightamerShellDelegate: NSObject, NSApplicationDelegate {

    let shell: LightamerShellController

    init(shell: LightamerShellController) {
        self.shell = shell
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        shell.applicationDidFinishLaunching()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool { true }

    // D-F0P-4: the Dock reopen alignment (SwiftUI default behavior — show /
    // rebuild the main window when the Dock icon is clicked with no visible
    // window).
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            shell.reopenMainWindow()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        shell.appDelegate.application(application, open: urls)
    }

    // M2-8-2 T4 lesson (load-bearing): the parameter type MUST be
    // `Notification` — an `NSApplication`-typed "nearly matching" method
    // never enters the ObjC selector dispatch. Forwarded verbatim.
    func applicationWillTerminate(_ notification: Notification) {
        shell.appDelegate.applicationWillTerminate(notification)
    }
}

@MainActor
enum LightamerShellMain {

    // NSApp.delegate is weak — the delegate lives app-long.
    private nonisolated(unsafe) static var retainedDelegate: LightamerShellDelegate?

    static func run() {
        let shell = LightamerShellController()
        let delegate = LightamerShellDelegate(shell: shell)
        retainedDelegate = delegate
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
