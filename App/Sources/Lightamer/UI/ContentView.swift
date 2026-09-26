import LightamerCore
import SwiftUI
import UniformTypeIdentifiers

/// Three-column shell (D-07): sidebar / editor area / inspector.
///
/// Observes all four D-03b state objects only to (a) provide the cross-state
/// coordination point (RESEARCH §7c — states never reference each other) and
/// (b) host the toolbar + blocking decode-error alert. Child columns re-inject
/// exactly the one state they need.
internal struct ContentView: View {

    /// The app-owned decode actor (D-21), passed on to `EditorState.load`.
    let decoder: RAWDecoder

    /// The app-owned Metal context (Plan 03); nil = no Metal GPU → the fatal
    /// `.metalDeviceUnavailable` alert below (UI-SPEC Error Messages).
    let metalContext: MetalContext?

    /// Plan 09-3: the browser collection model + the thumbnail pipeline
    /// (rebuilt per session by the app root; nil = not wired yet).
    let browserModel: SessionBrowserModel
    let thumbnailProvider: SessionThumbnailProvider?

    /// Plan 09-04 (HIST-05): the adjustments clipboard + the app root's
    /// partial-paste routing (the sheet raises the request; the app root's
    /// closure performs the paste) + the presentation binding.
    let pasteboard: AdjustmentsPasteboard
    let onPartialPasteRequested: () -> Void
    let onPartialPaste: (
        (_ selection: Set<PastePayload.InstanceKey>, _ mode: PasteMode) async -> Void
    )?
    @Binding var pastePartialRequested: Bool

    /// The THREE browser modes (RESEARCH §9 — 网格 | 单图 | 对比). The
    /// persisted value survives relaunches; `single` (the pre-9-3 whole
    /// app) stays the default.
    enum BrowserMode: String, CaseIterable, Identifiable {
        case grid
        case single
        case culling
        var id: String { rawValue }
        var identifier: String { "browser.mode.\(rawValue)" }
        var titleKey: String {
            switch self {
            case .grid: "browser_mode_grid"
            case .single: "browser_mode_single"
            case .culling: "browser_mode_culling"
            }
        }
    }

    @AppStorage("browser.mode") private var browserModeRaw: String = BrowserMode.single.rawValue
    private var browserMode: BrowserMode {
        BrowserMode(rawValue: browserModeRaw) ?? .single
    }

    @Environment(SessionState.self) private var sessionState
    @Environment(EditorState.self) private var editorState
    @Environment(BeforeAfterState.self) private var beforeAfterState
    @Environment(ExportState.self) private var exportState
    @Environment(InspectorState.self) private var inspectorState
    @Environment(MetadataController.self) private var metadataController

    /// Plan 12-4 T3: the preset-manager window opener (the toolbar's
    /// import menu hosts the entry; the Edit menu mirrors it).
    @Environment(\.openWindow) private var openWindow

    /// Split-view column visibility (sidebar/inspector toggles, D-08).
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Plan 11-04: the export sheet presentation flag (the toolbar's
    /// export button raises it).
    @State private var exportPanelRequested = false

    /// Plan 12-3 T5: the third-party `.xmp` import dialog (the toolbar's
    /// import menu raises it) + the user-visible failure message.
    @State private var xmpImportPresented = false
    @State private var xmpImportFailure: String?

    // D-08 layout memory — keys survive relaunch (NSSplitView autosave;
    // the @AppStorage ideals below are the clean-launch defaults).
    //
    // 04-08-F1 (GUI-4 真修复): viewport-is-hero 红线 —— 990pt 窗要求视口
    // ≥50% (≥495pt). 两层保证:
    // ① ideals 收窄: sidebar 200 + inspector 240 = 440, 余 550 给编辑器
    // (55.6%). inspector min 220→200 给小窗留 slack; max 460 保留 (曲线
    // 编辑器手动拉宽).
    // ② 编辑列硬 min 495pt (下 content 闭包处): 即使 NSSplitView 恢复的旧
    // frames 压倒 ideal (04-06 教训: 首启顶 max 460 → 视口 33.2%), 小窗下
    // 编辑器 min 也会先把 inspector 压回 ≤290, 红线按构造守住. 大窗
    // (1440) 不受影响 (200+500+460=1160<1440, inspector 可留 460).
    @AppStorage("layout.sidebarWidth") private var sidebarWidth: Double = 200
    @AppStorage("layout.inspectorWidth") private var inspectorWidth: Double = 240
    @AppStorage("layout.inspectorVisible") private var inspectorVisible: Bool = true

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
            // UI-SPEC dims, GUI-4 narrowed: min 150 / ideal 200 / max 240.
                .navigationSplitViewColumnWidth(min: 150, ideal: clamped(sidebarWidth, 150, 240), max: 240)
        } content: {
            browserContent
                // 04-08-F1 ②: 编辑列硬 min 495pt = 990pt 窗的 50% 红线 ——
                // 旧 split frames 恢复压倒 ideal 时 (04-06 教训: 首启顶 max
                // 460 → 视口 33.2%), 小窗下先压侧栏/inspector (mins 150/
                // 200, 合计 150+495+200=845 < 990: 常规拖拽不受限)；
                // 大窗 (1440) inspector 仍可到 max 460. ideal 700 保留：
                // 富余分配仍由 balanced 定，不干预大窗比例.
                .navigationSplitViewColumnWidth(min: 495, ideal: 700)
        } detail: {
            // 09-3 GUI-19 fix: the browser modes hide the Inspector by NOT
            // RENDERING the detail column (the columnVisibility change alone
            // did not collapse it on macOS 27 — the acceptance round caught
            // the panel still standing). The single mode restores it with
            // the remembered widths.
            if browserMode == .single {
                InspectorView()
                // UI-SPEC dims, GUI-4 真修复（F1 ①）: min 200 / ideal 240 / max 460.
                // 曲线编辑器满宽 = 240 列 − padding ≈ 216pt 画布；max 460 只在
                // 用户手动拉宽时到达.
                    .navigationSplitViewColumnWidth(min: 200, ideal: clamped(inspectorWidth, 200, 460), max: 460)
            }
        }
        .navigationSplitViewStyle(.balanced)
        // 04-08-T2 (GUI-8 fix): the D-26 status bar lives at the WINDOW
        // bottom (all three columns) — it used to sit inside the editor
        // column, where the acceptance round read it as viewport chrome
        // and never saw auto-detect toasts.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(
                isDecoding: editorState.isDecoding, toast: editorState.toast,
                comparePoint: beforeAfterState.isCompareActive
                    ? beforeAfterState.comparePointLabel : nil)
        }
        .focusedSceneValue(\.lightamerColumnVisibility, $columnVisibility)
        .focusedSceneValue(\.exportPanelRequest, $exportPanelRequested)
        .toolbar { toolbarContent }
        .alert(
            String(localized: "alert_decode_failed_title"),
            isPresented: Binding(
                get: { editorState.decodeError != nil },
                set: { if !$0 { editorState.clearError() } }
            ),
            presenting: editorState.decodeError
        ) { _ in
            Button(String(localized: "alert_ok"), role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        // Fatal (UI-SPEC): no Metal GPU — the editor cannot proceed. The
        // binding never dismisses; the app stays at the empty-state canvas.
        .alert(
            String(localized: "alert_metal_unavailable_title"),
            isPresented: .constant(metalContext == nil)
        ) {
            Button(String(localized: "alert_ok"), role: .cancel) {}
        } message: {
            Text(AppError.metalDeviceUnavailable.localizedDescription)
        }
        .onAppear {
            // D-08: restore inspector visibility from layout memory.
            columnVisibility = inspectorVisible ? .all : .detailOnly
            applyBrowserModeColumnRules()
        }
        .onChange(of: inspectorVisible) { _, isVisible in
            columnVisibility = isVisible ? .all : .detailOnly
        }
        // The browser modes HIDE the Inspector (v1 范围控制: 浏览模式整页
        // 替换 — the adjustment panels belong to the editor). Returning to
        // the single mode restores the remembered visibility.
        // 09-04 T7: a new image invalidates the compare planes (the state
        // resets — the compare forms re-arm per image).
        .onChange(of: editorState.loadedImageURL) { _, _ in
            beforeAfterState.reset()
        }
        .onChange(of: browserModeRaw) { _, newValue in
            if ContentView.BrowserMode(rawValue: newValue) != .single {
                columnVisibility = .doubleColumn
            } else {
                columnVisibility = inspectorVisible ? .all : .detailOnly
            }
        }
        // Plan 07-1 T3: the layer-B model first-launch prompt + progress +
        // failure surfaces (app-level state; 07-3's MaskToolbar reuses the
        // same AIAssetStore model).
        .modifier(AIDownloadPrompt())
        // 09-04 HIST-05: the partial-paste dialog (the menu command raises
        // the request; the paste routes back through the app root).
        .sheet(isPresented: $pastePartialRequested) {
            if let payload = pasteboard.peek() {
                PastePartialDialog(
                    payload: payload,
                    initialSelection: pasteboard.lastSelection,
                    onPaste: { selection, mode in
                        pastePartialRequested = false
                        Task {
                            await onPartialPaste?(selection, mode)
                        }
                    },
                    onCancel: { pastePartialRequested = false }
                )
            }
        }
        // Plan 11-04: the export panel (T4 — the toolbar's export button
        // raises it; the session must be open).
        .sheet(isPresented: $exportPanelRequested) {
            ExportPanelView(browserModel: browserModel)
        }
        // Plan 12-3 T5: the third-party `.xmp` READ-ONLY import — the
        // parsed fields route through MetadataController (the single
        // write implementation); the source file is never written.
        .fileImporter(
            isPresented: $xmpImportPresented,
            allowedContentTypes: [UTType(filenameExtension: "xmp") ?? .xml],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importXMP(from: url)
        }
        .alert(
            String(localized: "alert_xmp_import_failed_title"),
            isPresented: Binding(
                get: { xmpImportFailure != nil },
                set: { if !$0 { xmpImportFailure = nil } }
            ),
            presenting: xmpImportFailure
        ) { _ in
            Button(String(localized: "alert_ok"), role: .cancel) {}
        } message: { failure in
            Text(failure)
        }
    }

    // Plan 09-3 THREE-MODE switch — a WHOLE-PAGE replacement (the browser
    // never squeezes the editor's layout; 视口主导红线). The editor-column
    // width contract (hard min 495pt) rides the SAME modifier as before.
    @ViewBuilder
    private var browserContent: some View {
        switch browserMode {
        case .grid:
            SessionBrowserView(
                model: browserModel,
                thumbnailProvider: thumbnailProvider,
                onOpenInEditor: { url in
                    editorState.load(
                        url: url,
                        decoder: decoder,
                        metal: metalContext,
                        logger: EditorState.decodeLogger
                    )
                    browserModeRaw = ContentView.BrowserMode.single.rawValue
                },
                sessionRoot: sessionState.currentSessionURL
            )
        case .single:
            EditorAreaView(decoder: decoder, metalContext: metalContext)
        case .culling:
            CullingView(
                model: browserModel,
                decoder: decoder,
                metalContext: metalContext,
                sessionRoot: sessionState.currentSessionURL
            )
        }
    }

    /// The Inspector column rule per mode (see the onChange above).
    private func applyBrowserModeColumnRules() {
        guard columnVisibility != .detailOnly || browserMode == .single else { return }
        if browserMode != .single {
            columnVisibility = .doubleColumn // sidebar visible, inspector hidden
        } else {
            columnVisibility = inspectorVisible ? .all : .detailOnly
        }
    }

    /// The mode segmented control (L010: stable per-mode identifiers).
    private var modePicker: some View {
        Picker(String(localized: "browser_mode_label"), selection: $browserModeRaw) {
            ForEach(ContentView.BrowserMode.allCases) { mode in
                Text(String(localized: String.LocalizationValue(mode.titleKey)))
                    .tag(mode.rawValue)
                    .accessibilityIdentifier(mode.identifier)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }

    // MARK: - Toolbar (UI-SPEC Top Toolbar table)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                columnVisibility = (columnVisibility == .doubleColumn) ? .all : .doubleColumn
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .accessibilityLabel(Text("toolbar_toggle_sidebar"))
            .accessibilityHint(Text("a11y_toggle_sidebar_hint"))

            Button {
                FileOpener.openImage {
                    editorState.load(
                        url: $0,
                        decoder: decoder,
                        metal: metalContext,
                        logger: EditorState.decodeLogger
                    )
                }
            } label: {
                Label(String(localized: "toolbar_open"), systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityLabel(Text("toolbar_open"))
            .accessibilityHint(Text("a11y_open_hint"))
        }
        ToolbarItemGroup {
            // Plan 12-3 T5: the import slot now hosts the third-party
            // `.xmp` READ-ONLY import (the Phase-9 "import photos into the
            // session" placeholder keeps its seat, still deferred).
            Menu {
                Button(String(localized: "menu_import_xmp")) {
                    xmpImportPresented = true
                }
                .disabled(xmpTargetRelPaths.isEmpty)
                .accessibilityIdentifier("toolbar.import_xmp")

                Button(String(localized: "toolbar_import")) {}
                    .disabled(true)

                Divider()
                // Plan 12-4 T3: the preset manager entry (the CRUD/
                // import/export window; the apply face lives in the
                // Inspector's preset panel).
                Button(String(localized: "menu_preset_manager")) {
                    openWindow(id: "preset-manager")
                }
                .accessibilityIdentifier("toolbar.preset_manager")
            } label: {
                Label(String(localized: "toolbar_import"), systemImage: "square.and.arrow.down")
            }
            .disabled(sessionState.currentSessionURL == nil)
            .accessibilityIdentifier("toolbar.import")

            // Plan 11-04 (EXP-03): the export sheet — the panel edits the
            // in-memory recipe, fans the selection × recipe out as ONE
            // queue action, and shows the live per-job status.
            Button {
                exportPanelRequested = true
            } label: {
                Label(String(localized: "menu_export"), systemImage: "square.and.arrow.up")
            }
            .disabled(sessionState.currentSessionURL == nil)
            .accessibilityIdentifier("toolbar.export")
            .keyboardShortcut("e", modifiers: [.command, .shift])

            // 09-04 (HIST-06): the split before/after toggle (the peek
            // stepper + hold ride the viewport HUD / keyboard).
            Button {
                beforeAfterState.splitEnabled.toggle()
                if !beforeAfterState.splitEnabled {
                    beforeAfterState.peekIndex = nil
                }
            } label: {
                Label(String(localized: "toolbar_before_after"), systemImage: "rectangle.lefthalf.filled")
            }
            .disabled(browserMode != .single || editorState.loadedImageURL == nil)
            .accessibilityIdentifier("toolbar.before_after")

            Button {
            } label: {
                Label(String(localized: "toolbar_fit"), systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(true)

            Button {
            } label: {
                Label(String(localized: "toolbar_zoom_100"), systemImage: "plus.magnifyingglass")
            }
            .disabled(true)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            modePicker

            Button {
                inspectorVisible.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .accessibilityLabel(Text("toolbar_toggle_inspector"))
            .accessibilityHint(Text("a11y_toggle_inspector_hint"))
        }
    }

    // MARK: - Helpers

    private func clamped(_ value: Double, _ lower: Double, _ upper: Double) -> CGFloat {
        CGFloat(min(max(value, lower), upper))
    }

    // MARK: - The XMP import (Plan 12-3 T5)

    /// The import targets: the browser/culling SELECTION when non-empty,
    /// else the editor's CURRENT image inside the open session (the same
    /// routing shape as the 12-1 metadata commands).
    private var xmpTargetRelPaths: [String] {
        let selected = browserModel.selectedOrderedPaths
        if !selected.isEmpty { return Array(selected) }
        if let root = sessionState.currentSessionURL,
            let loaded = editorState.loadedImageURL {
            let prefix = root.path + "/"
            if loaded.path.hasPrefix(prefix) {
                return [String(loaded.path.dropFirst(prefix.count))]
            }
        }
        return []
    }

    /// Parse (READ-ONLY — the source file is never written) and route the
    /// fields through the MetadataController (the single write face).
    private func importXMP(from url: URL) {
        let targets = xmpTargetRelPaths
        guard !targets.isEmpty else {
            xmpImportFailure = String(localized: "alert_xmp_no_target")
            return
        }
        do {
            let fields = try XMPImport.read(fileURL: url)
            Task { @MainActor in
                // Reject first (the -1 convention downgrades the rating).
                if fields.flag == 2 {
                    await metadataController.setFlag(2, relPaths: targets)
                }
                if fields.rating != nil {
                    await metadataController.setRating(fields.rating, relPaths: targets)
                }
                if let colorLabel = fields.colorLabel {
                    await metadataController.setColorLabel(colorLabel, relPaths: targets)
                }
                if let keywords = fields.keywords {
                    await metadataController.setImportedKeywords(keywords, relPaths: targets)
                }
            }
        } catch {
            // The typed degradation face: unparsable / empty / unreadable
            // packets surface to the user; nothing is written.
            switch error as? XMPImport.ImportError {
            case .unparsableXMP:
                xmpImportFailure = String(localized: "alert_xmp_unparsable")
            case .noFields:
                xmpImportFailure = String(localized: "alert_xmp_no_fields")
            case .unreadableFile(let name):
                xmpImportFailure = String(localized: "alert_xmp_unreadable") + " " + name
            case nil:
                xmpImportFailure = error.localizedDescription
            }
        }
    }
}
