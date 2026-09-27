import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// SettingsView (Plan 16-2 T1) — the Settings window's Catalogs section
// (CATALOG-01「设置中启用」字面; D-16-CONTEXT-5①).
//
// Faces:
//   • the「启用 Catalogs 模式」toggle — writes through the Core
//     `CatalogPreferences` face (ONE key spelling; the projector guard
//     reads the same key).
//   • the catalog location row — the current `.lcat` path + its existence
//     state, and the directory picker (NSOpenPanel; re-point, NEVER
//     migrate — RQ-16-1②: the runtime closes the outgoing handles and the
//     next enable/open creates an empty library at the new path).
//   • the single-file backup hint (Plan 16-4 T2③, RQ-16-1①/RQ-16-15):
//     「退出 app 后拷贝此文件即完整备份」 — no automatic backup mechanism
//     (the pinned ruling), the honest user-side backup story.
//   • the rebuild faces (Plan 16-4 T2, RQ-16-14 两档):
//     - 对账式（默认日常入口） — ids and organization data survive;
//       completion copy 「目录已与 N 个会话对账」.
//     - 破坏式（仅 schemaFailed 禁用态出现） — file-level recovery; the
//       completion copy spells the organization-data loss out VERBATIM:
//       「元数据已恢复；分类与集合需从备份恢复或重新整理」. A confirmation
//       dialog precedes it (the loss is destructive and user-approved).
//   • progress: the X/N-会话 row while a rebuild runs (the grid shows its
//     空网格 + 进度 face through the same model state — RQ-16-14 推荐态).
//
// zh/en keys land in the same batch (L025 discipline).
// ─────────────────────────────────────────────────────────────────────────────

internal struct SettingsView: View {

    @Environment(CatalogPreferencesModel.self) private var catalogPreferences
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    @State private var confirmDestructive = false

    var body: some View {
        Form {
            Section(String(localized: "settings_displays_section")) {
                // 13-2 T6 (COLOR-03): the manual per-display profile
                // override — a hand-picked ICC replaces ONE display's auto
                // resolution (the precise `.colorSyncFallback` leg). The
                // override touches the RESOLUTION only; the copy states
                // the display-simulation boundary.
                ForEach(NSScreen.screens, id: \.localizedName) { screen in
                    displayRow(screen)
                }
                Text("settings_displays_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }

            Section(String(localized: "settings_catalogs_section")) {
                Toggle(
                    String(localized: "settings_catalogs_enable"),
                    isOn: Binding(
                        get: { catalogPreferences.catalogsEnabled },
                        set: { catalogPreferences.setCatalogsEnabled($0) }
                    )
                )
                .disabled(catalogPreferences.isRebuilding)
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
                .disabled(catalogPreferences.isRebuilding)
                .accessibilityIdentifier("settings.catalogs.change_location")

                Text("settings_catalogs_backup_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }

            Section(String(localized: "settings_catalogs_rebuild_section")) {
                if catalogPreferences.schemaFailed {
                    // The 损坏处置 disabled state (RQ-16-14): Catalogs mode
                    // cannot open the library; the destructive file-level
                    // recovery is the ONLY action. Sessions mode untouched.
                    Label(String(localized: "settings_catalogs_schema_failed"),
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("settings.catalogs.schema_failed")

                    Button(String(localized: "settings_catalogs_rebuild_destructive")) {
                        confirmDestructive = true
                    }
                    .disabled(catalogPreferences.isRebuilding)
                    .accessibilityIdentifier("settings.catalogs.rebuild_destructive")
                } else {
                    // The daily entry (the DEFAULT 档): the row-set repair
                    // that keeps ids and organization data.
                    Button(String(localized: "settings_catalogs_rebuild_reconcile")) {
                        Task { await catalogPreferences.runReconcileRebuild() }
                    }
                    .disabled(
                        !catalogPreferences.catalogsEnabled
                            || catalogPreferences.isRebuilding)
                    .accessibilityIdentifier("settings.catalogs.rebuild_reconcile")
                }

                Text("settings_catalogs_rebuild_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)

                if catalogPreferences.isRebuilding {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        if let progress = catalogPreferences.rebuildProgress {
                            Text("settings_catalogs_rebuild_progress \(progress.completed) \(progress.total)")
                        } else {
                            Text("settings_catalogs_rebuild_preparing")
                        }
                    }
                    .font(.callout)
                    .accessibilityIdentifier("settings.catalogs.rebuild_progress")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { catalogPreferences.refreshSchemaState() }
        .confirmationDialog(
            String(localized: "catalog_rebuild_confirm_destructive_title"),
            isPresented: $confirmDestructive,
            titleVisibility: .visible
        ) {
            Button(String(localized: "catalog_rebuild_confirm_destructive_accept"),
                   role: .destructive) {
                Task { await catalogPreferences.runDestructiveRebuild() }
            }
            Button(String(localized: "catalog_rebuild_confirm_cancel"), role: .cancel) {}
        } message: {
            Text("catalog_rebuild_confirm_destructive_body")
        }
        .alert(
            rebuildOutcomeTitle,
            isPresented: Binding(
                get: { catalogPreferences.lastOutcome != nil },
                set: { shown in if !shown { catalogPreferences.clearOutcome() } }
            )
        ) {
            Button(String(localized: "catalog_rebuild_alert_ok"), role: .cancel) {}
        } message: {
            Text(rebuildOutcomeMessage)
        }
        .accessibilityIdentifier("settings.catalogs.section")
    }

    // The completion faces (the TWO honest copies — the discipline).
    private var rebuildOutcomeTitle: String {
        switch catalogPreferences.lastOutcome {
        case .reconciled: String(localized: "catalog_rebuild_done_title")
        case .restoredDestructive: String(localized: "catalog_rebuild_done_title")
        case .failed: String(localized: "catalog_rebuild_failed_title")
        case nil: ""
        }
    }

    private var rebuildOutcomeMessage: String {
        switch catalogPreferences.lastOutcome {
        case .reconciled(let sessions):
            String(localized: "catalog_rebuild_done_reconcile \(sessions)")
        case .restoredDestructive:
            String(localized: "catalog_rebuild_done_destructive")
        case .failed(let reason):
            String(localized: "catalog_rebuild_failed \(reason)")
        case nil: ""
        }
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

    // MARK: - 13-2 T6: the per-display override row

    /// One display: its name, the override state (hand-picked profile name
    /// or auto), and the pick/clear faces. The pick = an ICC file panel;
    /// both faces route through the store then refresh the coordinator's
    /// resolution (idempotent when nothing changed).
    @ViewBuilder
    private func displayRow(_ screen: NSScreen) -> some View {
        let displayID = ManualDisplayOverrideStore.displayID(of: screen)
        let overridePath = displayID.flatMap {
            ManualDisplayOverrideStore.shared.overridePath(displayID: $0)
        }
        LabeledContent {
            HStack(spacing: 8) {
                Button(String(localized: "settings_displays_choose")) {
                    chooseICCProfile(displayID: displayID)
                }
                .disabled(displayID == nil)
                .accessibilityIdentifier("settings.displays.choose")
                if overridePath != nil {
                    Button(String(localized: "settings_displays_clear")) {
                        if let displayID {
                            ManualDisplayOverrideStore.shared.setOverride(nil, displayID: displayID)
                            pipeCoordinator.refreshDisplayProfile()
                        }
                    }
                    .accessibilityIdentifier("settings.displays.clear")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(screen.localizedName)
                    .font(.callout)
                Text(overridePath.map {
                        String(localized: "settings_displays_overridden \($0)")
                    } ?? String(localized: "settings_displays_auto"))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .accessibilityIdentifier("settings.displays.row.\(screen.localizedName)")
    }

    /// The ICC picker (NSOpenPanel, .icc/.icm). A picked file wins for THIS
    /// display on the next resolution; unreadable files are stored anyway
    /// (the resolution degrades to auto — the store's graceful contract).
    private func chooseICCProfile(displayID: UInt32?) {
        guard let displayID else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["icc", "icm"]
        panel.directoryURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ManualDisplayOverrideStore.shared.setOverride(url.path, displayID: displayID)
        pipeCoordinator.refreshDisplayProfile()
    }
}
