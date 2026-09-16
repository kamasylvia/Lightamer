import SwiftUI

/// Three-column shell (D-07): sidebar / editor area / inspector.
///
/// Observes all four D-03b state objects only to (a) provide the cross-state
/// coordination point (RESEARCH §7c — states never reference each other) and
/// (b) host the toolbar + blocking decode-error alert. Child columns re-inject
/// exactly the one state they need.
internal struct ContentView: View {

    @Environment(SessionState.self) private var sessionState
    @Environment(EditorState.self) private var editorState
    @Environment(ExportState.self) private var exportState
    @Environment(InspectorState.self) private var inspectorState

    /// Split-view column visibility (sidebar/inspector toggles, D-08).
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // D-08 layout memory — keys survive relaunch.
    @AppStorage("layout.sidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("layout.inspectorWidth") private var inspectorWidth: Double = 320
    @AppStorage("layout.inspectorVisible") private var inspectorVisible: Bool = true

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: clamped(sidebarWidth, 180, 320),
                    max: 320
                )
        } content: {
            EditorAreaView()
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(
                    min: 240,
                    ideal: clamped(inspectorWidth, 240, 460),
                    max: 460
                )
        }
        .navigationSplitViewStyle(.balanced)
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
                FileOpener.openImage { editorState.load(url: $0) }
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
