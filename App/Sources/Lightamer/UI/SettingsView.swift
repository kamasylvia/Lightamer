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

    /// Plan M2-2-4 (M2LIB-06 / OQ-8): the legacy-library gate. Default
    /// `false` — the Catalogs section AND the rebuild section (both are the
    /// catalog face) are hidden; the display + MCP sections stay. There is
    /// deliberately NO new "legacy library" switch here (双库并存的心智负担 —
    /// the OQ-8 rationale); `LIGHTAMER_LEGACY_LIBRARY=1` at the assembly
    /// point opts back. The production assembly passes the value in (KD-1 —
    /// this body never touches ProcessInfo). (`var` + default: the
    /// memberwise init parameter defaults to the narrowed face — only the
    /// assembly point passes the evaluated gate.)
    var legacyLibraryEnabled: Bool = false

    /// Plan M2-2-4 (KD-4 layer 2): the catalog-section markers as a pure
    /// function of the gate — a 1:1 mirror of the body's single conditional
    /// below. The frozen M2-2-era set includes the two state-conditional
    /// rebuild rows (schema-failed label / destructive recovery) at family
    /// granularity; `LibraryLegacyGateTests` pins it against a hardcoded
    /// `Set<String>` literal (never runtime-recorded).
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

    @Environment(CatalogPreferencesModel.self) private var catalogPreferences
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    @State private var confirmDestructive = false

    // MARK: Plan 14-4 T1: the MCP preference keys (the same spellings
    // McpServerController reads; the toggles write through @AppStorage so
    // the launch-time hook and this section share ONE storage face).
    @AppStorage(McpServerController.embeddedServerEnabledKey)
    private var mcpServerEnabled = false
    @AppStorage(McpServerController.lanExposureEnabledKey)
    private var mcpLanExposure = false
    @AppStorage("mcp_agent_command_template")
    private var mcpAgentTemplate = ""
    @AppStorage("mcp_agent_prompt_template")
    private var mcpAgentPrompt = ""

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

            // Plan M2-2-4 (M2LIB-06 / OQ-8): both catalog sections hide
            // behind the legacy gate — the enable toggle AND its rebuild
            // faces (they are one face; 既有开关随 catalog 面同隐). Gate false
            // leaves the display + MCP sections only.
            if legacyLibraryEnabled {
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

            // ── Plan 14-4 T1: the MCP section (MCP-02 GUI switch + MCP-10
            // templates; D-14-CONTEXT-6① exposure gate) ──────────────────
            Section(String(localized: "settings_mcp_section")) {
                Toggle(
                    String(localized: "settings_mcp_enable"),
                    isOn: Binding(
                        get: { mcpServerEnabled },
                        set: { enabled in
                            mcpServerEnabled = enabled
                            Task {
                                if enabled {
                                    await McpServerController.startEmbeddedServer()
                                } else {
                                    await McpServerController.stopEmbeddedServer()
                                }
                            }
                        }
                    )
                )
                .accessibilityIdentifier("settings.mcp.enable")

                Text("settings_mcp_enable_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)

                // The non-loopback gate: explicit ON binds 0.0.0.0 AND the
                // Bearer valve becomes mandatory (the start path enforces
                // it; toggling while serving restarts the host so the new
                // binding actually applies — never a silent half-state).
                Toggle(
                    String(localized: "settings_mcp_lan"),
                    isOn: Binding(
                        get: { mcpLanExposure },
                        set: { enabled in
                            mcpLanExposure = enabled
                            if mcpServerEnabled {
                                Task {
                                    await McpServerController.stopEmbeddedServer()
                                    await McpServerController.startEmbeddedServer()
                                }
                            }
                        }
                    )
                )
                .accessibilityIdentifier("settings.mcp.lan")

                Text("settings_mcp_lan_risk")
                    .font(.caption)
                    .foregroundStyle(.orange)

                LabeledContent(String(localized: "settings_mcp_agent_template")) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $mcpAgentTemplate)
                            .frame(height: 64)
                            .font(.system(size: 11, design: .monospaced))
                            .accessibilityIdentifier("settings.mcp.template")
                        if mcpAgentTemplate.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings_mcp_template_placeholder_omp")
                                Text("settings_mcp_template_placeholder_pi")
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(LightamerColors.textSecondary)
                            .padding(.top, 4)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                        }
                    }
                }

                LabeledContent(String(localized: "settings_mcp_agent_prompt")) {
                    TextField(
                        String(localized: "settings_mcp_agent_prompt_placeholder"),
                        text: $mcpAgentPrompt, axis: .vertical)
                    .font(.system(size: 11))
                    .accessibilityIdentifier("settings.mcp.prompt")
                }

                Text("settings_mcp_placeholders_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                Text("settings_mcp_agent_consumption_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
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
