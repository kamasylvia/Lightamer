import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// SettingsView (Plan 16-2 T1) — the Settings window's Catalogs section
// (CATALOG-01「设置中启用」字面; D-16-CONTEXT-5①).
//
// Three faces:
//   • the「启用 Catalogs 模式」toggle — writes through the Core
//     `CatalogPreferences` face (ONE key spelling; the projector guard
//     reads the same key).
//   • the catalog location row — the current `.lcat` path + its existence
//     state, and the directory picker (NSOpenPanel; re-point, NEVER
//     migrate — RQ-16-1②: the runtime closes the outgoing handles and the
//     next enable/open creates an empty library at the new path).
//   • the honest-boundary hint — 目录库可随时由会话重建 (RQ-16-15: metadata
//     mirrors rebuild from the session face; organization data rides the
//     single-file copy).
//
// zh/en keys land in the same batch (L025 discipline).
// ─────────────────────────────────────────────────────────────────────────────

internal struct SettingsView: View {

    @Environment(CatalogPreferencesModel.self) private var catalogPreferences

    var body: some View {
        Form {
            Section(String(localized: "settings_catalogs_section")) {
                Toggle(
                    String(localized: "settings_catalogs_enable"),
                    isOn: Binding(
                        get: { catalogPreferences.catalogsEnabled },
                        set: { catalogPreferences.setCatalogsEnabled($0) }
                    )
                )
                .accessibilityIdentifier("settings.catalogs.enable")

                LabeledContent(String(localized: "settings_catalogs_location")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(catalogPreferences.catalogURL.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(catalogPreferences.catalogURL.path)
                            .accessibilityIdentifier("settings.catalogs.path")
                        Text(
                            catalogPreferences.catalogFileExists
                                ? String(localized: "settings_catalogs_file_exists")
                                : String(localized: "settings_catalogs_file_missing")
                        )
                        .font(.caption2)
                        .foregroundStyle(LightamerColors.textSecondary)
                        .accessibilityIdentifier("settings.catalogs.existence")
                    }
                }

                Button(String(localized: "settings_catalogs_location_change")) {
                    chooseLocation()
                }
                .accessibilityIdentifier("settings.catalogs.change_location")

                Text("settings_catalogs_rebuild_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 220)
    }

    /// The directory picker (plan T1.2 — NSOpenPanel 目录选择). The stored
    /// preference is the DIRECTORY; the database file keeps the frozen
    /// `catalog.lcat` name inside it.
    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = catalogPreferences.catalogURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        catalogPreferences.setLocation(directory: directory)
    }
}
