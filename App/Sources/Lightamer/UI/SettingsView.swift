import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// SettingsView — the Settings window's navigation shell.
//
// Plan M2-3-3 T5 (KD-5 = OQ-7 A): reorganized into the Alcedo-style
// left-list/right-detail navigation over the D7 page set (ten always-visible
// pages + the gate-conditional Catalogs page). The page CONTENT pieces live
// in `Settings/SettingsPages.swift`; the Displays / MCP / Catalogs sections
// moved there VERBATIM (statement-level relocation — the 13-2 display
// override rows, the 14-4 MCP section and the M2-2-4 gated catalog face keep
// their identifiers and storage faces).
//
// History:
//   • Plan 16-2 T1 — the Settings window's Catalogs section (CATALOG-01
//     「设置中启用」字面; D-16-CONTEXT-5①): the enable toggle (ONE key
//     spelling through the Core `CatalogPreferences` face), the location
//     row, the single-file backup hint (Plan 16-4 T2③) and the two rebuild
//     faces (对账式 / 破坏式, RQ-16-14 两档).
//   • Plan M2-2-4 (M2LIB-06 / OQ-8) — the legacy-library gate: the Catalogs
//     page AND its rebuild faces hide behind the gate; there is deliberately
//     NO new "legacy library" switch (双库并存的心智负担); the production
//     assembly passes the evaluated value in (KD-1 — this body never touches
//     ProcessInfo).
//   • Plan M2-3-3 T5 — the ten-page navigation shell (this form).
// ─────────────────────────────────────────────────────────────────────────────

internal struct SettingsView: View {

    /// Plan M2-2-4 (M2LIB-06 / OQ-8): the legacy-library gate. Default
    /// `false` — the Catalogs page (the enable toggle AND the rebuild faces,
    /// one face) is hidden; the ten D7 pages stay. `var` + default: the
    /// memberwise init parameter defaults to the narrowed face — only the
    /// assembly point passes the evaluated gate.
    var legacyLibraryEnabled: Bool = false

    /// Plan M2-2-4 (KD-4 layer 2): the catalog-section markers as a pure
    /// function of the gate — a 1:1 mirror of the catalog page's conditional
    /// (`SettingsCatalogsPage` renders exactly these sections). The frozen
    /// M2-2-era set includes the two state-conditional rebuild rows
    /// (schema-failed label / destructive recovery) at family granularity;
    /// `LibraryLegacyGateTests` pins it against a hardcoded `Set<String>`
    /// literal (never runtime-recorded). UNCHANGED by the T5 reorganization
    /// — the migration was a statement-level relocation of the very sections
    /// these markers name.
    nonisolated static func visibleCatalogSectionMarkers(
        legacyLibraryEnabled: Bool
    ) -> Set<String> {
        guard legacyLibraryEnabled else { return [] }
        return [
            "settings.catalogs.enable",
            "settings.catalogs.path",
            "settings.catalogs.existence",
            "settings.catalogs.change_location",
            "settings.catalogs.schema_failed",
            "settings.catalogs.rebuild_destructive",
            "settings.catalogs.rebuild_reconcile",
        ]
    }

    @State private var selectedPage: SettingsPage = .languageTheme

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                ForEach(
                    SettingsPage.displayedPages(
                        legacyLibraryEnabled: legacyLibraryEnabled)
                ) { page in
                    Label(page.title, systemImage: page.iconName)
                        .tag(page)
                        .accessibilityIdentifier("settings.page.\(page.rawValue)")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
            // Plan M2-10-07: the entry-guidance deep link (the Inspector's
            // key-absent guidance routes here) — consumed once on appear.
            .onAppear {
                if let pending = SettingsDeepLink.pendingPage {
                    selectedPage = pending
                    SettingsDeepLink.pendingPage = nil
                }
            }
        } detail: {
            switch selectedPage {
            case .languageTheme: SettingsLanguageThemePage()
            case .defaultBehavior: SettingsDefaultBehaviorPage()
            case .cache: SettingsCachePage()
            case .localContentRecognition:
                SettingsPlaceholderPage(
                    identifier: SettingsPage.localContentRecognition.rawValue,
                    title: SettingsPage.localContentRecognition.title,
                    featureName: String(
                        localized: "settings_lcr_feature",
                        defaultValue: "Local content recognition"))
            case .advancedContentAnalysis:
                SettingsACAPage(model: ACASettingsModel())
            case .keyboard: SettingsKeyboardPage()
            case .about: SettingsAboutPage()
            case .importDefaults: SettingsImportDefaultsPage()
            case .displays: SettingsDisplaysPage()
            case .mcp: SettingsMCPPage()
            case .catalogs: SettingsCatalogsPage()
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

/// Plan M2-10-07: the Settings page the entry-guidance commands route to
/// (set BEFORE a SettingsLink opens the window; consumed on the Settings
/// view's appear). A plain MainActor static — no view body touches it.
@MainActor
enum SettingsDeepLink {
    nonisolated(unsafe) static var pendingPage: SettingsPage?
}
