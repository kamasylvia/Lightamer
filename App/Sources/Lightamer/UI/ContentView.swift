import LightamerCore
import SwiftUI

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

    @Environment(SessionState.self) private var sessionState
    @Environment(EditorState.self) private var editorState
    @Environment(ExportState.self) private var exportState
    @Environment(InspectorState.self) private var inspectorState

    /// Split-view column visibility (sidebar/inspector toggles, D-08).
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // D-08 layout memory — keys survive relaunch.
    // 04-06 GUI-4 (D-GUI-3): viewport-is-hero redline — the window's
    // pixels belong to the editor first. Sidebar ideal 240→200 (empty
    // Phase 9 stub, no content yet), inspector ideal 320→280 (panels have
    // ONE slider column; 460 max kept for curve editors). Editor eats the
    // rest: at 990pt the viewport is ≥50% by construction.
    @AppStorage("layout.sidebarWidth") private var sidebarWidth: Double = 200
    @AppStorage("layout.inspectorWidth") private var inspectorWidth: Double = 280
    @AppStorage("layout.inspectorVisible") private var inspectorVisible: Bool = true

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
            // UI-SPEC dims, GUI-4 narrowed: min 150 / ideal 200 / max 240.
                .navigationSplitViewColumnWidth(min: 150, ideal: clamped(sidebarWidth, 150, 240), max: 240)
        } content: {
            EditorAreaView(decoder: decoder, metalContext: metalContext)
        } detail: {
            InspectorView()
            // UI-SPEC dims, GUI-4 narrowed: min 220 / ideal 280 / max 460.
                .navigationSplitViewColumnWidth(min: 220, ideal: clamped(inspectorWidth, 220, 460), max: 460)
        }
        .navigationSplitViewStyle(.balanced)
        // 04-08-T2 (GUI-8 fix): the D-26 status bar lives at the WINDOW
        // bottom (all three columns) — it used to sit inside the editor
        // column, where the acceptance round read it as viewport chrome
        // and never saw auto-detect toasts.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(isDecoding: editorState.isDecoding, toast: editorState.toast)
        }
        .focusedSceneValue(\.lightamerColumnVisibility, $columnVisibility)
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
        }
        .onChange(of: inspectorVisible) { _, isVisible in
            columnVisibility = isVisible ? .all : .detailOnly
        }
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
            // Phase 9 — disabled.
            Button {
            } label: {
                Label(String(localized: "toolbar_import"), systemImage: "square.and.arrow.down")
            }
            .disabled(true)

            // Phase 11 — disabled.
            Button {
            } label: {
                Label(String(localized: "menu_export"), systemImage: "square.and.arrow.up")
            }
            .disabled(true)

            // Phase 9 (HIST-06) — disabled. D-13: no zoom in Phase 1 — disabled.
            Button {
            } label: {
                Label(String(localized: "toolbar_before_after"), systemImage: "rectangle.lefthalf.filled")
            }
            .disabled(true)

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
}
