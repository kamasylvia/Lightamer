import AppKit
import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// SettingsPages (Plan M2-3-3 T5, KD-5 = OQ-7 A) — the Alcedo-style Settings
// navigation: a left list of page entries + a right detail area.
//
// The page SET is the D7 ruling verbatim: ten always-visible pages
// (`navigationPages`) + the Catalogs page that only the M2-2-4 legacy gate
// shows (`displayedPages(legacyLibraryEnabled:)` — the pure gate face the
// tests pin). Acceleration and Updates are deliberately NOT pages (D7 cut).
//
// Migration discipline: the Displays / MCP / Catalogs sections moved out of
// SettingsView VERBATIM (statement-level relocation, zero semantic change —
// the 13-2 display-override rows, the 14-4 MCP section and the M2-2-4
// gated catalog face all keep their identifiers and storage faces). The
// `visibleCatalogSectionMarkers` frozen function stays in SettingsView.swift
// untouched.
//
// Honesty discipline (零假开关): the LCR/ACA pages are structural skeletons
// with the "arrives with M2-10" family copy and NO fake switches; the
// Keyboard page shows/detects/restores but does not rebind (v1); the mask
// three-choice is STORED here and consumed by M2-7.
// ─────────────────────────────────────────────────────────────────────────────

/// One Settings navigation page. `catalogs` is a real case (the gated face
/// must be reachable) but sits OUT of `navigationPages` — the ten-page set
/// is the D7 assertion surface.
enum SettingsPage: String, CaseIterable, Hashable, Identifiable, Sendable {
    case languageTheme
    case defaultBehavior
    case cache
    case localContentRecognition
    case advancedContentAnalysis
    case keyboard
    case about
    case importDefaults
    case displays
    case mcp
    /// The M2-2-4 legacy-gate page (visible only when the gate is on).
    case catalogs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .languageTheme:
            String(localized: "settings_page_language_theme",
                   defaultValue: "Language & Theme")
        case .defaultBehavior:
            String(localized: "settings_page_default_behavior",
                   defaultValue: "Default Behavior")
        case .cache:
            String(localized: "settings_page_cache", defaultValue: "Cache")
        case .localContentRecognition:
            String(localized: "settings_page_lcr",
                   defaultValue: "Local Content Recognition")
        case .advancedContentAnalysis:
            String(localized: "settings_page_aca",
                   defaultValue: "Advanced Content Analysis")
        case .keyboard:
            String(localized: "settings_page_keyboard", defaultValue: "Keyboard")
        case .about:
            String(localized: "settings_page_about", defaultValue: "About")
        case .importDefaults:
            String(localized: "settings_page_import_defaults",
                   defaultValue: "Import Defaults")
        case .displays:
            String(localized: "settings_page_displays", defaultValue: "Displays")
        case .mcp:
            String(localized: "settings_page_mcp", defaultValue: "MCP")
        case .catalogs:
            String(localized: "settings_page_catalogs", defaultValue: "Catalogs")
        }
    }

    var iconName: String {
        switch self {
        case .languageTheme: "globe"
        case .defaultBehavior: "slider.horizontal.3"
        case .cache: "internaldrive"
        case .localContentRecognition: "text.magnifyingglass"
        case .advancedContentAnalysis: "wand.and.stars"
        case .keyboard: "keyboard"
        case .about: "info.circle"
        case .importDefaults: "square.and.arrow.down"
        case .displays: "display"
        case .mcp: "server.rack"
        case .catalogs: "folder.badge.gearshape"
        }
    }

    /// The ten always-visible pages (the D7 set — the exact assertion
    /// surface; Acceleration/Updates are NOT in here).
    static var navigationPages: [SettingsPage] {
        allCases.filter { $0 != .catalogs }
    }

    /// The gate face (KD-1 injection discipline: a plain Bool in — the body
    /// never touches ProcessInfo). Gate on appends Catalogs last.
    static func displayedPages(legacyLibraryEnabled: Bool) -> [SettingsPage] {
        legacyLibraryEnabled ? allCases : navigationPages
    }
}

// MARK: - Page 1: Language & Theme

/// v1 honesty: the UI language follows the system (no in-app switcher yet)
/// and the appearance is pinned dark (D-10) — the page STATES both instead
/// of shipping fake switches.
struct SettingsLanguageThemePage: View {
    var body: some View {
        Form {
            Section(String(localized: "settings_language_section",
                           defaultValue: "Language")) {
                LabeledContent(String(localized: "settings_language_ui",
                                      defaultValue: "Interface language")) {
                    Text(String(localized: "settings_language_system",
                                defaultValue: "Follows system"))
                        .foregroundStyle(LightamerColors.textSecondary)
                }
                .accessibilityIdentifier("settings.language.system")
            }
            Section(String(localized: "settings_theme_section",
                           defaultValue: "Theme")) {
                LabeledContent(String(localized: "settings_theme_appearance",
                                      defaultValue: "Appearance")) {
                    Text(String(localized: "settings_theme_dark_pinned",
                                defaultValue: "Dark (pinned in v1)"))
                        .foregroundStyle(LightamerColors.textSecondary)
                }
                .accessibilityIdentifier("settings.theme.pinned")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.languageTheme")
    }
}

// MARK: - Page 2: Default Behavior

/// The mask-draw three-choice (KD-5) — stored through `AppPreferences`
/// (injected instance; M2-7 consumes the key, this plan only stores).
struct SettingsDefaultBehaviorPage: View {
    /// nil = the app face (`.standard`); tests inject an isolated suite via
    /// the initializer.
    var preferences: AppPreferences = AppPreferences()

    @State private var behavior: MaskDrawBehavior = .ask

    var body: some View {
        Form {
            Section(String(localized: "settings_behavior_masks_section",
                           defaultValue: "Mask drawing")) {
                Picker(
                    String(localized: "settings_behavior_mask_default",
                           defaultValue: "After drawing a mask"),
                    selection: $behavior
                ) {
                    Text(String(localized: "settings_behavior_mask_ask",
                                defaultValue: "Ask what to do"))
                        .tag(MaskDrawBehavior.ask)
                    Text(String(localized: "settings_behavior_mask_new_layer",
                                defaultValue: "Create a new layer"))
                        .tag(MaskDrawBehavior.newLayer)
                    Text(String(localized: "settings_behavior_mask_current_node",
                                defaultValue: "Draw into the current node"))
                        .tag(MaskDrawBehavior.currentNode)
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("settings.behavior.mask")
                Text(String(
                    localized: "settings_behavior_mask_hint",
                    defaultValue: "Applies when a drawn mask is completed."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
            // LUMEN-A T7 (review M-3): the culling-analysis toggle (D-LU-5
            // 默认开 — the Settings-reachable face of the analysis pass's
            // one UserDefaults key; the key spelling is the Core service's
            // single source through the AppPreferences alias).
            Section(String(localized: "settings_analysis_section",
                           defaultValue: "Photo analysis")) {
                Toggle(isOn: Binding(
                    get: { preferences.libraryAnalysisEnabled },
                    set: { preferences.libraryAnalysisEnabled = $0 })) {
                    Text(String(localized: "settings_analysis_toggle",
                                defaultValue: "Analyze photos in the background"))
                }
                .accessibilityIdentifier("settings.behavior.analysis")
                Text(String(
                    localized: "settings_analysis_hint",
                    defaultValue: "Computes sharpness, closed-eye and burst hints for the library while the app idles. Export and AI work always takes priority."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.defaultBehavior")
        .onAppear { behavior = preferences.maskDrawBehavior }
        .onChange(of: behavior) { _, newValue in
            preferences.maskDrawBehavior = newValue
        }
    }
}

// MARK: - Page 3: Cache

/// The derived-cache face: the app caches directory display + a real clear
/// button (the contents are rebuildable derived data — thumbnails, decode
/// scratch). Per-project `.lathumbs` dirs live beside their projects and are
/// named as rebuildable in the copy.
struct SettingsCachePage: View {
    /// nil = the app face (`.standard`); tests inject an isolated suite.
    var preferences: AppPreferences = AppPreferences()

    @State private var cachesPath: String = ""
    @State private var clearedBanner = false
    @State private var lutRootPath: String = ""
    @State private var lutStatusLine: String?
    // LENS-03 T3: the Lensfun data-management face (the §5 section).
    @State private var lensfunDBTag: String?
    @State private var lensfunUpdating = false
    @State private var lensfunUpdateLine: String?

    var body: some View {
        Form {
            Section(String(localized: "settings_cache_section",
                           defaultValue: "Derived caches")) {
                LabeledContent(String(localized: "settings_cache_location",
                                      defaultValue: "Location")) {
                    Text(cachesPath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(cachesPath)
                        .accessibilityIdentifier("settings.cache.location")
                }
                Button(String(localized: "settings_cache_clear",
                              defaultValue: "Clear Derived Caches")) {
                    Self.clearCaches()
                    clearedBanner = true
                }
                .accessibilityIdentifier("settings.cache.clear")
                if clearedBanner {
                    Label(String(localized: "settings_cache_cleared",
                                 defaultValue: "Derived caches cleared"),
                          systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(LightamerColors.textSecondary)
                        .accessibilityIdentifier("settings.cache.cleared")
                }
                Text(String(
                    localized: "settings_cache_hint",
                    defaultValue: "Everything here is rebuilt on demand. Per-project thumbnail caches live in hidden .lathumbs folders next to their projects and are equally rebuildable."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }

            // LUMEN-B T7 (红线 11): the smart-preview budget — the
            // preview-budget ladder (0 = off; the Lumen choice set). The
            // setter also live-updates the shared store (the Lumen
            // set_limit semantics).
            Section(String(localized: "settings_previews_section",
                           defaultValue: "Smart previews")) {
                Picker(String(localized: "settings_previews_limit",
                              defaultValue: "Cache limit"),
                       selection: Binding(
                        get: { preferences.previewCacheLimitMB },
                        set: { newValue in
                            preferences.previewCacheLimitMB = newValue
                            Task {
                                await SmartPreviewStore.shared
                                    .setLimit(megabytes: newValue)
                            }
                        })) {
                    ForEach(
                        [0, 1024, 2048, 4096, 8192, 16384, 32768],
                        id: \.self) { megabytes in
                            Text(megabytes == 0
                                ? String(localized: "settings_previews_off",
                                         defaultValue: "Off")
                                : String(localized: "settings_previews_mb",
                                         defaultValue: "\(megabytes) MB"))
                                .tag(megabytes)
                        }
                }
                .accessibilityIdentifier("settings.cache.previewsLimit")
                Text(String(
                    localized: "settings_previews_hint",
                    defaultValue: "Caches the decoded working planes so reopening and culling skip the RAW decode. Off disables the cache; everything in it is rebuildable."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }

            // LUMEN-C T4 (D-LU-7 / 红线 11): the mask fine-refine auto
            // trigger — the Settings face of the batch's ONE new key.
            Section(String(localized: "settings_maskrefine_section",
                           defaultValue: "Mask refinement")) {
                Toggle(String(localized: "settings_maskrefine_auto",
                              defaultValue: "Refine AI mask edges automatically"),
                       isOn: Binding(
                        get: { preferences.maskFineAuto },
                        set: { preferences.maskFineAuto = $0 }))
                    .accessibilityIdentifier("settings.mask.fineAuto")
                Text(String(
                    localized: "settings_maskrefine_hint",
                    defaultValue: "After an AI mask is generated its edges are refined against the developed image in the background (seconds per mask). A failure keeps the quick mask."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }

            // LENS-03 T3 (D-LENS-6 / X7): the Lensfun data-management
            // section — dbTag readout + the MANUAL SHA-verified update.
            // No automatic fetch (D-LENS-6); the L057 async seam for the
            // download task (Task hop, no runModal).
            Section(String(localized: "settings_lensfun_section",
                           defaultValue: "Lens Data")) {
                LabeledContent(String(localized: "settings_lensfun_dbtag",
                                      defaultValue: "Database tag")) {
                    Text(lensfunDBTag ?? "—")
                        .font(.caption)
                        .accessibilityIdentifier("settings.lensfun.dbtag")
                }
                Button(lensfunUpdating
                       ? String(localized: "settings_lensfun_updating",
                                defaultValue: "Checking for updates…")
                       : String(localized: "settings_lensfun_check_update",
                                defaultValue: "Check for Database Updates")) {
                    lensfunUpdating = true
                    lensfunUpdateLine = nil
                    Task {
                        let outcome = await LensfunDataDistribution.checkForUpdates()
                        await MainActor.run {
                            lensfunUpdating = false
                            switch outcome {
                            case .installed:
                                lensfunUpdateLine = String(localized:
                                    "settings_lensfun_updated",
                                    defaultValue: "Database updated.")
                                lensfunDBTag = LensfunDataDistribution.dbTag(
                                    directory: LensfunDownloadService.supportDirectory()
                                        .appendingPathComponent("version_1", isDirectory: true))
                            case .shaMismatch(let expected, let actual):
                                lensfunUpdateLine = String(localized:
                                    "settings_lensfun_sha_mismatch",
                                    defaultValue: "SHA-256 mismatch — install refused.")
                                AppError.logger.error(
                                    "lensfun update SHA mismatch: expected \(expected), got \(actual)")
                            case .downloadFailed:
                                lensfunUpdateLine = String(localized:
                                    "settings_lensfun_update_failed",
                                    defaultValue: "Update download failed — the installed database is untouched.")
                            }
                        }
                    }
                }
                .disabled(lensfunUpdating)
                .accessibilityIdentifier("settings.lensfun.checkUpdate")
                if let lensfunUpdateLine {
                    Text(lensfunUpdateLine)
                        .font(.caption)
                        .foregroundStyle(LightamerColors.textSecondary)
                        .accessibilityIdentifier("settings.lensfun.updateLine")
                }
                Text(String(localized: "settings_lensfun_hint",
                            defaultValue: "The bundled snapshot is pinned and attributed (CC-BY-SA-3.0). Updates are manual and SHA-verified; a mismatched archive is never installed."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }

            // M2-5-3 (KD-3, M2GRADE-06): the user-configurable LUT library
            // root — probe-then-persist; a failed probe degrades with an
            // error line and keeps the effective root (L009: no bookmarks
            // in v1). USER data, not derived — hence the explicit copy.
            Section(String(localized: "settings_lut_section",
                           defaultValue: "LUT Library")) {
                LabeledContent(String(localized: "settings_lut_root_location",
                                      defaultValue: "Library root")) {
                    Text(lutRootPath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(lutRootPath)
                        .accessibilityIdentifier("settings.lut.root")
                }
                HStack {
                    Button(String(localized: "settings_lut_root_choose",
                                  defaultValue: "Choose…")) {
                        // L057 (fix(l057)): async panel via the begin seam.
                        Task { await chooseLutRoot() }
                    }
                    .accessibilityIdentifier("settings.lut.choose")
                    Button(String(localized: "settings_lut_root_reset",
                                  defaultValue: "Reset to Default Root")) {
                        resetLutRoot()
                    }
                    .accessibilityIdentifier("settings.lut.reset")
                }
                if let lutStatusLine {
                    Text(lutStatusLine)
                        .font(.caption)
                        .foregroundStyle(
                            lutRootRejected ? Color.orange : LightamerColors.textSecondary)
                        .accessibilityIdentifier("settings.lut.status")
                }
                Text(String(
                    localized: "settings_lut_hint",
                    defaultValue: "Tables live in subdirectories of the root; the built-in film set is seeded into BuiltIn/ on the default root only."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.cache")
        .onAppear {
            cachesPath = (FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask).first?
                .path) ?? "—"
            lutRootPath = preferences.lutLibraryRoot().path
            // LENS-03 T3: the active database's dbTag readout (the
            // resolution mirrors the launch priority; read-only).
            let loc = LensfunDataDistribution.resolveAndInstall()
            let dir: URL?
            switch loc {
            case .custom(let u), .seeded(let u), .downloaded(let u): dir = u
            case .absent: dir = nil
            }
            lensfunDBTag = dir.flatMap { LensfunDataDistribution.dbTag(directory: $0) } ?? "—"
        }
    }

    /// The error-line tint discriminator (the invalid-root copy renders
    /// orange; the rescan outcome renders secondary).
    private var lutRootRejected: Bool { lutStatusLine == rejectedCopy }

    private var rejectedCopy: String {
        String(localized: "settings_lut_root_invalid",
               defaultValue: "That folder is not usable as the LUT library root — keeping the current root.")
    }

    /// KD-3: probe-then-persist-then-atomically-replace the shared store;
    /// the result line reports the fresh registry size.
    private func applyLutRoot(_ url: URL) {
        guard LutLibraryStore.validateRoot(url) else {
            lutStatusLine = rejectedCopy
            return
        }
        preferences.setLutLibraryRoot(url)
        let store = LutLibraryStore()  // reads the key → the new root
        LutLibraryStore.replaceShared(store)
        lutRootPath = store.lutsDirectory.path
        lutStatusLine = String(
            format: String(localized: "settings_lut_rescan_done %lld"),
            store.installedNames.count)
    }

    /// L057 (fix(l057)): async via the begin seam — a sync runModal here
    /// nested inside the button-action dispatch (the crash family shape).
    private func chooseLutRoot() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = preferences.lutLibraryRoot()
        guard let url = await PanelPresentation.present(panel) else { return }
        applyLutRoot(url)
    }

    private func resetLutRoot() {
        preferences.resetLutLibraryRoot()
        let store = LutLibraryStore()
        LutLibraryStore.replaceShared(store)
        lutRootPath = store.lutsDirectory.path
        lutStatusLine = String(
            format: String(localized: "settings_lut_rescan_done %lld"),
            store.installedNames.count)
    }

    /// The clear face: remove the CONTENTS of the app caches directory
    /// (never the directory itself). Best-effort — failures keep the banner
    /// silent rather than alarming (the data is rebuildable by definition).
    private static func clearCaches() {
        guard let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: caches, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }
}

// MARK: - Page 4: Local Content Recognition (M2-10-07 T2, KD-1)

/// The LCR page: the five-tier model list (M2-10-01 Catalog) with status,
/// download/remove, the fail-closed 「待发布」 face, the OQ-9-A 换激活
/// (confirm → registry recompute enqueue), the D-6 compatibility-record
/// reset, the auto-labeling three-choice (03 handoff), the readiness probe
/// line and the local data-policy footnote. Zero fake switches.
struct SettingsLCRPage: View {
    let model: LCRSettingsModel

    @State private var pendingActivateKey: String?
    @State private var pendingActivateName = ""
    @State private var confirmCompatReset = false

    var body: some View {
        Form {
            readinessSection
            tiersSection
            labelingSection
            compatibilitySection
            policySection
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.localContentRecognition")
        .task { await model.refresh() }
        .confirmationDialog(
            String(
                localized: "settings_lcr_activate_confirm_title",
                defaultValue: "Switch the active semantic model?"),
            isPresented: Binding(
                get: { pendingActivateKey != nil },
                set: { if !$0 { pendingActivateKey = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(
                localized: "settings_lcr_activate_confirm_accept",
                defaultValue: "Switch & Recompute")) {
                if let key = pendingActivateKey {
                    model.enqueueRecompute(newModelKey: key)
                }
                pendingActivateKey = nil
            }
            Button(String(
                localized: "settings_lcr_activate_confirm_cancel",
                defaultValue: "Cancel"), role: .cancel) {
                pendingActivateKey = nil
            }
        } message: {
            Text(String(
                format: String(localized: "settings_lcr_activate_confirm_body %@"),
                pendingActivateName))
        }
        .confirmationDialog(
            String(
                localized: "settings_lcr_compat_confirm_title",
                defaultValue: "Reset the AI compatibility record?"),
            isPresented: $confirmCompatReset,
            titleVisibility: .visible
        ) {
            Button(String(
                localized: "settings_lcr_compat_confirm_accept",
                defaultValue: "Reset"), role: .destructive) {
                model.resetCompatibilityRecord()
            }
            Button(String(
                localized: "settings_lcr_compat_confirm_cancel",
                defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(
                localized: "settings_lcr_compat_confirm_body",
                defaultValue: "The record of compute units that crashed is cleared, so every combination is tried again after a driver or system update."))
        }
    }

    // MARK: Readiness (the worker/asset probe line)

    @ViewBuilder
    private var readinessSection: some View {
        Section(String(
            localized: "settings_lcr_readiness_section",
            defaultValue: "Local AI")) {
            switch model.readiness {
            case .probing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(
                        localized: "settings_lcr_probe_probing",
                        defaultValue: "Checking local AI readiness…"))
                        .foregroundStyle(LightamerColors.textSecondary)
                }
                .accessibilityIdentifier("settings.lcr.probing")
            case .ready:
                Label(String(
                    localized: "settings_lcr_probe_ready",
                    defaultValue: "AI ready — local inference is available."),
                    systemImage: "checkmark.circle")
                    .font(.callout)
                    .accessibilityIdentifier("settings.lcr.ready")
            case .unavailable(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.lcr.unavailable")
            }
            if let statusLine = model.statusLine {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.lcr.status")
            }
            if model.recomputeActive {
                Label(String(
                    localized: "settings_lcr_recompute_active",
                    defaultValue: "Recomputing library embeddings — progress is in the background-task bar."),
                    systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .accessibilityIdentifier("settings.lcr.recompute.active")
            }
        }
    }

    // MARK: The five-tier list

    private var tiersSection: some View {
        Section(String(
            localized: "settings_lcr_models_section",
            defaultValue: "Models")) {
            ForEach(model.rows) { row in
                tierRow(row)
            }
        }
    }

    @ViewBuilder
    private func tierRow(_ row: LCRSettingsModel.TierRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.manifest.profileID)
                    .font(.callout.weight(.medium))
                tierBadge(row)
                if row.isActiveModel {
                    Text(String(
                        localized: "settings_lcr_active_badge",
                        defaultValue: "Active"))
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                actionButton(row)
            }
            Text(String(
                format: String(localized: "settings_lcr_tier_detail %@ %@ %@"),
                dimCopy(row), row.manifest.licenseName, row.sizeCopy ?? "—"))
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
            Text(row.statusCopy)
                .font(.caption)
                .foregroundStyle(row.status == .corrupt ? Color.orange : LightamerColors.textSecondary)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("settings.lcr.tier.\(row.manifest.profileID)")
    }

    private func dimCopy(_ row: LCRSettingsModel.TierRow) -> String {
        guard let dim = row.manifest.embeddingDim else {
            return String(
                localized: "settings_lcr_dim_enhancement",
                defaultValue: "Enhancement")
        }
        return String(
            format: String(localized: "settings_lcr_dim_semantic %lld"), dim)
    }

    @ViewBuilder
    private func tierBadge(_ row: LCRSettingsModel.TierRow) -> some View {
        switch row.manifest.tier {
        case .bundled:
            Text(String(
                localized: "settings_lcr_tier_bundled",
                defaultValue: "Built in"))
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        case .gitHubRelease:
            Text(String(
                localized: "settings_lcr_tier_release",
                defaultValue: "Download"))
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
    }

    @ViewBuilder
    private func actionButton(_ row: LCRSettingsModel.TierRow) -> some View {
        switch row.action {
        case .builtIn, .downloading:
            EmptyView()
        case .download:
            Button(String(
                localized: "settings_lcr_action_download",
                defaultValue: "Download")) {
                Task { await model.download(row.manifest.profileID) }
            }
            .accessibilityIdentifier("settings.lcr.download.\(row.manifest.profileID)")
        case .remove:
            Button(String(
                localized: "settings_lcr_action_remove",
                defaultValue: "Remove")) {
                Task { await model.remove(row.manifest.profileID) }
            }
            .accessibilityIdentifier("settings.lcr.remove.\(row.manifest.profileID)")
        case .awaitingRelease:
            Text(String(
                localized: "settings_lcr_action_awaiting",
                defaultValue: "Awaiting release"))
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
                .accessibilityIdentifier("settings.lcr.awaiting.\(row.manifest.profileID)")
        }
        if row.canActivate {
            Button(String(
                localized: "settings_lcr_action_activate",
                defaultValue: "Activate…")) {
                pendingActivateKey = row.manifest.profileID
                pendingActivateName = row.manifest.profileID
            }
            .accessibilityIdentifier("settings.lcr.activate.\(row.manifest.profileID)")
        }
    }

    // MARK: Auto-labeling (the M2-10-03 three-choice)

    private var labelingSection: some View {
        Section(String(
            localized: "settings_lcr_labeling_section",
            defaultValue: "Auto-labeling")) {
                Picker(
                    String(localized: "settings_lcr_labeling_mode",
                           defaultValue: "When importing images"),
                    selection: Binding(
                        get: { model.labelingMode },
                        set: { model.setLabelingMode($0) })
                ) {
                    Text(String(
                        localized: "settings_lcr_labeling_ask",
                        defaultValue: "Ask what to do"))
                        .tag(LabelingMode.ask)
                    Text(String(
                        localized: "settings_lcr_labeling_always",
                        defaultValue: "Label automatically"))
                        .tag(LabelingMode.always)
                    Text(String(
                        localized: "settings_lcr_labeling_never",
                        defaultValue: "Never label"))
                        .tag(LabelingMode.never)
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("settings.lcr.labeling.mode")
                Button(String(
                    localized: "settings_lcr_labeling_reset",
                    defaultValue: "Reset Auto-labeling Preference")) {
                    model.resetLabelingPreference()
                }
                .accessibilityIdentifier("settings.lcr.labeling.reset")
            }
    }

    // MARK: Compatibility record

    private var compatibilitySection: some View {
        Section(String(
            localized: "settings_lcr_compat_section",
            defaultValue: "Diagnostics")) {
            Button(String(
                localized: "settings_lcr_compat_reset",
                defaultValue: "Reset AI Compatibility Record")) {
                confirmCompatReset = true
            }
            .accessibilityIdentifier("settings.lcr.compat.reset")
            Text(String(
                localized: "settings_lcr_compat_hint",
                defaultValue: "Clears the memory of compute units that crashed local inference, so every combination is retried after a driver or system update."))
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
        }
    }

    // MARK: The local data-policy statement

    private var policySection: some View {
        Section {
            Text(String(
                localized: "settings_lcr_policy",
                defaultValue: "All semantic indexing and enhancement runs locally on this device. No image is ever uploaded."))
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
                .accessibilityIdentifier("settings.lcr.policy")
        }
    }
}

// MARK: - Page 5: Advanced Content Analysis (M2-10-07 T1, KD-2)

/// The ACA page: the single remote connection form (protocol / baseURL /
/// model) with the live admission gate, the key face (SecureField →
/// Keychain + the 「未配置」 banner), the rating preferences (strictness /
/// output language / the 不再询问 toggle) and the inline connection test.
struct SettingsACAPage: View {
    var model: ACASettingsModel = ACASettingsModel()

    @State private var keyBuffer = ""

    var body: some View {
        Form {
            connectionSection
            keySection
            ratingSection
            testSection
            policySection
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.advancedContentAnalysis")
        .onAppear {
            model.load()
        }
    }

    // MARK: Connection form

    private var connectionSection: some View {
        Section(String(
            localized: "settings_aca_connection_section",
            defaultValue: "Connection")) {
            Picker(String(
                localized: "settings_aca_protocol",
                defaultValue: "Protocol"), selection: Binding(
                    get: { model.provider },
                    set: { model.setProvider($0) })
            ) {
                Text(String(
                    localized: "settings_aca_protocol_openai",
                    defaultValue: "OpenAI-compatible (chat completions)"))
                    .tag(AIProviderProtocol.openAIChatCompletions)
                Text(String(
                    localized: "settings_aca_protocol_anthropic",
                    defaultValue: "Anthropic (messages)"))
                    .tag(AIProviderProtocol.anthropicMessages)
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("settings.aca.protocol")

            LabeledContent(String(
                localized: "settings_aca_base_url",
                defaultValue: "Base URL")) {
                TextField(
                    String(
                        localized: "settings_aca_base_url_placeholder",
                        defaultValue: "https://api.openai.com/v1"),
                    text: Binding(
                        get: { model.baseURLText },
                        set: { model.baseURLText = $0; model.commitConnection() }),
                    axis: .vertical)
                .font(.system(size: 11, design: .monospaced))
                .accessibilityIdentifier("settings.aca.baseURL")
            }

            if let rejection = model.endpointRejection {
                Text(rejection)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.aca.endpoint.rejection")
            }

            LabeledContent(String(
                localized: "settings_aca_model",
                defaultValue: "Model")) {
                TextField(
                    String(
                        localized: "settings_aca_model_placeholder",
                        defaultValue: "gpt-4o-mini / claude-sonnet…"),
                    text: Binding(
                        get: { model.modelText },
                        set: { model.modelText = $0; model.commitConnection() }))
                .font(.system(size: 11, design: .monospaced))
                .accessibilityIdentifier("settings.aca.model")
            }
        }
    }

    // MARK: Key face

    @ViewBuilder
    private var keySection: some View {
        Section(String(
            localized: "settings_aca_key_section",
            defaultValue: "API Key")) {
            if model.needsSetup {
                Label(String(
                    localized: "settings_aca_key_missing_banner",
                    defaultValue: "No API key configured — rating and description cannot run until a key is saved."),
                    systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.aca.key.missing")
            }
            SecureField(
                String(localized: "settings_aca_key_placeholder",
                       defaultValue: "Paste the provider API key"),
                text: $keyBuffer)
                .font(.system(size: 11, design: .monospaced))
                .accessibilityIdentifier("settings.aca.key.field")
            HStack {
                Button(String(
                    localized: "settings_aca_key_save",
                    defaultValue: "Save Key")) {
                    model.saveKey(keyBuffer)
                    keyBuffer = ""
                }
                .disabled(keyBuffer.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("settings.aca.key.save")
                if model.keyPresent {
                    Button(String(
                        localized: "settings_aca_key_delete",
                        defaultValue: "Remove Key"), role: .destructive) {
                        model.deleteKey()
                    }
                    .accessibilityIdentifier("settings.aca.key.delete")
                    Text(String(
                        localized: "settings_aca_key_present",
                        defaultValue: "A key is stored in the Keychain."))
                        .font(.caption)
                        .foregroundStyle(LightamerColors.textSecondary)
                }
            }
            Text(String(
                localized: "settings_aca_key_hint",
                defaultValue: "The key is stored only in the macOS Keychain and is sent solely in the request's auth header — never into defaults, logs or error text."))
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
        }
    }

    // MARK: Rating preferences

    private var ratingSection: some View {
        Section(String(
            localized: "settings_aca_rating_section",
            defaultValue: "AI Rating")) {
            HStack {
                Text(String(
                    localized: "settings_aca_strictness",
                    defaultValue: "Strictness \(model.strictness)"))
                    .accessibilityIdentifier("settings.aca.strictness.label")
                Slider(
                    value: Binding(
                        get: { Double(model.strictness) },
                        set: { model.setStrictness(Int($0.rounded())) }),
                    in: 1...5, step: 1)
                    .accessibilityIdentifier("settings.aca.strictness")
            }
            Text(String(
                localized: "settings_aca_strictness_hint",
                defaultValue: "1 = only obvious rejects … 5 = exhibition standard. The wording ships with the rubric sent to the provider."))
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)

            Picker(String(
                localized: "settings_aca_language",
                defaultValue: "Output language"), selection: Binding(
                    get: { model.language },
                    set: { model.setLanguage($0) })
            ) {
                Text(String(
                    localized: "settings_aca_language_system",
                    defaultValue: "Follow system"))
                    .tag(AIOutputLanguage.system)
                Text(String(
                    localized: "settings_aca_language_chinese",
                    defaultValue: "Chinese"))
                    .tag(AIOutputLanguage.chinese)
                Text(String(
                    localized: "settings_aca_language_english",
                    defaultValue: "English"))
                    .tag(AIOutputLanguage.english)
            }
            .accessibilityIdentifier("settings.aca.language")

            Toggle(String(
                localized: "settings_aca_skip_confirm",
                defaultValue: "Apply ratings without asking"),
                isOn: Binding(
                    get: { model.skipRatingConfirmation },
                    set: { model.skipRatingConfirmation = $0 }))
                .accessibilityIdentifier("settings.aca.skip.confirm")
        }
    }

    // MARK: Connection test

    @ViewBuilder
    private var testSection: some View {
        Section(String(
            localized: "settings_aca_test_section",
            defaultValue: "Connection Test")) {
            Button {
                Task { await model.runConnectionTest() }
            } label: {
                if model.testRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Text(String(
                        localized: "settings_aca_test_run",
                        defaultValue: "Test Connection"))
                }
            }
            .disabled(model.testRunning)
            .accessibilityIdentifier("settings.aca.test.run")
            if let line = model.testOutcomeLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(
                        model.testOutcome == .ok
                            ? LightamerColors.textSecondary : Color.orange)
                    .accessibilityIdentifier("settings.aca.test.outcome")
            }
            if let statusLine = model.statusLine {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        }
    }

    // MARK: The remote data-policy statement

    private var policySection: some View {
        Section {
            Text(String(
                localized: "settings_aca_policy",
                defaultValue: "Rating and description send the photograph you choose to the provider configured above. Nothing is sent until you run a command; local AI features never use this connection."))
                .font(.caption)
                .foregroundStyle(LightamerColors.textSecondary)
                .accessibilityIdentifier("settings.aca.policy")
        }
    }
}

// MARK: - Page 6: Keyboard

/// One row of the Keyboard page's table (the Identifiable wrapper —
/// `MenuCommandID` itself stays untouched in its M2-3-1 file).
private struct KeyboardRow: Identifiable {
    let id: MenuCommandID
}

/// The Keyboard page (KD-5 v1): the command × binding table over the
/// `MenuCommandID` set, the pure conflict highlight, and the restore face
/// (visible only when overrides exist — v1 ships none, so it stays hidden
/// until the M2-x rebinding work writes them; 零假开关).
struct SettingsKeyboardPage: View {
    var preferences: AppPreferences = AppPreferences()

    @State private var overridesTick = 0

    /// The effective combo per command (default ⊕ override), recomputed on
    /// the override tick.
    private func effectiveCombo(_ id: MenuCommandID) -> SettingsKeyCombo? {
        _ = overridesTick
        return preferences.keyboardOverride(for: id) ?? DefaultKeymap.combo(for: id)
    }

    private var conflicts: [String: [MenuCommandID]] {
        overridesTick
        return KeyboardConflictDetector.conflicts(
            default: { DefaultKeymap.combo(for: $0) },
            override: { preferences.keyboardOverride(for: $0) })
    }

    var body: some View {
        Table(KeyboardRow.allRows, selection: .constant(nil)) {
            TableColumn(String(localized: "settings_keyboard_command",
                               defaultValue: "Command")) { row in
                Text(row.id.rawValue)
                    .font(.callout.monospaced())
            }
            TableColumn(String(localized: "settings_keyboard_binding",
                               defaultValue: "Binding")) { row in
                let combo = effectiveCombo(row.id)
                Text(combo?.normalized ?? "—")
                    .font(.callout.monospaced())
                    .foregroundStyle(
                        conflicts[combo?.normalized ?? ""] != nil
                            ? Color.orange
                            : LightamerColors.textPrimary)
            }
        }
        .frame(minHeight: 320)
        .accessibilityIdentifier("settings.page.keyboard")
        .safeAreaInset(edge: .bottom) {
            HStack {
                if !conflicts.isEmpty {
                    Label(String(
                        localized: "settings_keyboard_conflict",
                        defaultValue: "\(conflicts.count) conflicting binding(s) — highlighted in orange"),
                        systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("settings.keyboard.conflicts")
                }
                Spacer()
                if preferences.hasKeyboardOverrides {
                    Button(String(localized: "settings_keyboard_restore",
                                  defaultValue: "Restore Defaults")) {
                        preferences.resetKeyboardOverrides()
                        overridesTick += 1
                    }
                    .accessibilityIdentifier("settings.keyboard.restore")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

private extension KeyboardRow {
    static var allRows: [KeyboardRow] {
        MenuCommandID.allCases.map(KeyboardRow.init)
    }
}

// MARK: - Page 7: About

struct SettingsAboutPage: View {
    var body: some View {
        Form {
            Section(String(localized: "settings_about_section",
                           defaultValue: "About Lightamer")) {
                LabeledContent(String(localized: "settings_about_version",
                                      defaultValue: "Version")) {
                    Text(Self.versionText)
                        .font(.callout.monospacedDigit())
                        .accessibilityIdentifier("settings.about.version")
                }
                LabeledContent(String(localized: "settings_about_license",
                                      defaultValue: "License")) {
                    Text("MIT")
                        .foregroundStyle(LightamerColors.textSecondary)
                }
                .accessibilityIdentifier("settings.about.license")
                Text(String(
                    localized: "settings_about_description",
                    defaultValue: "A native macOS RAW photo editor — node-based grading, Core Image RAW decoding and direct Metal rendering."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
            Section(String(localized: "settings_about_ack_section",
                           defaultValue: "Acknowledgments")) {
                Text(String(
                    localized: "settings_about_ack_body",
                    defaultValue: "Algorithm references: darktable (GPL-3.0, read-only study). UI and workflow references: Alcedo Studio (GPL-3.0, read-only study). Frame and watermark panel lineage: yiyin."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                    .accessibilityIdentifier("settings.about.ack")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.about")
    }

    private static var versionText: String {
        let bundle = Bundle.main
        let version = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

// MARK: - Page 8: Import Defaults (M2LIB-07④)

/// The import transport defaults: the three-choice mode + the remember
/// toggle + the RAW whitelist replacement + reset — all through the Core
/// `ImportDefaults` face (the three registered keys; replace-never-union
/// whitelist semantics).
struct SettingsImportDefaultsPage: View {
    /// nil = the app face (`.standard`); tests inject an isolated suite.
    var importDefaults: ImportDefaults = ImportDefaults()

    @State private var mode: ImportMode = .copy
    @State private var remember = false
    @State private var whitelistText = ""

    var body: some View {
        Form {
            Section(String(localized: "settings_import_section",
                           defaultValue: "Import transport")) {
                Picker(
                    String(localized: "settings_import_mode",
                           defaultValue: "When importing images"),
                    selection: $mode
                ) {
                    Text(String(localized: "settings_import_mode_move",
                                defaultValue: "Move into project"))
                        .tag(ImportMode.move)
                    Text(String(localized: "settings_import_mode_copy",
                                defaultValue: "Copy into project"))
                        .tag(ImportMode.copy)
                    Text(String(localized: "settings_import_mode_link",
                                defaultValue: "Link in place"))
                        .tag(ImportMode.link)
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("settings.import.mode")

                Toggle(String(localized: "settings_import_remember",
                              defaultValue: "Remember this choice"),
                       isOn: $remember)
                    .accessibilityIdentifier("settings.import.remember")
            }

            Section(String(localized: "settings_import_whitelist_section",
                           defaultValue: "RAW extensions")) {
                TextField(
                    String(localized: "settings_import_whitelist_placeholder",
                           defaultValue: "arw, nef, cr3 …"),
                    text: $whitelistText
                )
                .font(.system(size: 11, design: .monospaced))
                .accessibilityIdentifier("settings.import.whitelist")
                Text(String(
                    localized: "settings_import_whitelist_hint",
                    defaultValue: "Comma or space separated. Replaces the default set entirely (never merges)."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }

            Section {
                Button(String(localized: "settings_import_reset",
                              defaultValue: "Reset Import Defaults")) {
                    importDefaults.reset()
                    seed()
                }
                .accessibilityIdentifier("settings.import.reset")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.importDefaults")
        .onAppear { seed() }
        .onChange(of: mode) { _, newValue in commitMode(newValue) }
        .onChange(of: remember) { _, _ in commitMode(mode) }
        .onChange(of: whitelistText) { _, newValue in commitWhitelist(newValue) }
    }

    private func seed() {
        mode = importDefaults.resolvedMode()
        remember = importDefaults.rememberMode
        let stored = importDefaults.resolvedWhitelist().sorted().map { ".\($0)" }
        whitelistText = stored.joined(separator: ", ")
    }

    /// The mode/remember write face — the KD-4 single-write contract: an
    /// unchecked remember persists NOTHING (stale mode dropped).
    private func commitMode(_ newMode: ImportMode) {
        importDefaults.storeChoice(ImportModeChoice(mode: newMode, remember: remember))
    }

    private func commitWhitelist(_ text: String) {
        let parts = text.split(whereSeparator: { ", ".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        importDefaults.setWhitelist(parts)
    }
}

// MARK: - Page 9: Displays (13-2 T6 migration — statements verbatim)

/// The per-display ICC override face, relocated verbatim from
/// SettingsView (the 13-2 identifiers and the ManualDisplayOverrideStore
/// storage face unchanged). Requires the PipeCoordinator environment — the
/// app's Settings scene now injects it (the 13-2 latent missing-injection
/// fix recorded in DECISIONS).
struct SettingsDisplaysPage: View {
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    var body: some View {
        Form {
            Section(String(localized: "settings_displays_section")) {
                ForEach(NSScreen.screens, id: \.localizedName) { screen in
                    displayRow(screen)
                }
                Text("settings_displays_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.displays")
    }

    @ViewBuilder
    private func displayRow(_ screen: NSScreen) -> some View {
        let displayID = ManualDisplayOverrideStore.displayID(of: screen)
        let overridePath = displayID.flatMap {
            ManualDisplayOverrideStore.shared.overridePath(displayID: $0)
        }
        LabeledContent {
            HStack(spacing: 8) {
                Button(String(localized: "settings_displays_choose")) {
                    // L057 (fix(l057)): async panel via the begin seam.
                    Task { await chooseICCProfile(displayID: displayID) }
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
                        String(
                            format: String(localized: "settings_displays_overridden %@"),
                            $0)
                    } ?? String(localized: "settings_displays_auto"))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .accessibilityIdentifier("settings.displays.row.\(screen.localizedName)")
    }

    /// L057 (fix(l057)): async via the begin seam.
    private func chooseICCProfile(displayID: UInt32?) async {
        guard let displayID else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["icc", "icm"]
        panel.directoryURL = URL(fileURLWithPath: "/Library/ColorSync/Profiles")
        guard let url = await PanelPresentation.present(panel) else { return }
        ManualDisplayOverrideStore.shared.setOverride(url.path, displayID: displayID)
        pipeCoordinator.refreshDisplayProfile()
    }
}

// MARK: - Page 10: MCP (14-4 T1 migration — statements verbatim)

/// The MCP section, relocated verbatim from SettingsView (the registered
/// key spellings McpServerController reads and every identifier unchanged).
struct SettingsMCPPage: View {
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
            // UQ-S2: the Agents onboarding section — paste-ready configs
            // (generated from the live discovery path) + the CLI install
            // face (UQ-S3). Everything an agent could be told to type is
            // shown here with a Copy button.
            Section(String(localized: "settings_mcp_onboarding_section")) {
                Text("settings_mcp_onboarding_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                McpOnboardingSection()
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.mcp")
    }
}

/// UQ-S2: the onboarding section body — install row + three copyable
/// snippets (Claude Code / Claude Desktop / CLI). Pure view over the
/// McpOnboarding model single sources.
struct McpOnboardingSection: View {
    @State private var installState = McpOnboarding.installState
    @State private var installError: String?
    @State private var copied: String?

    var body: some View {
        // The CLI install row (UQ-S3's install face).
        HStack(spacing: 10) {
            Text(statusText)
                .font(.caption)
                .accessibilityIdentifier("settings.mcp.onboarding.install-state")
            Spacer(minLength: 0)
            if installState != .absent {
                Button(String(localized: "settings_mcp_onboarding_uninstall")) {
                    run(McpOnboarding.uninstall)
                }
                .accessibilityIdentifier("settings.mcp.onboarding.uninstall")
            }
            Button(
                installState == .absent
                    ? String(localized: "settings_mcp_onboarding_install")
                    : String(localized: "settings_mcp_onboarding_reinstall")
            ) {
                run(McpOnboarding.install)
            }
            .accessibilityIdentifier("settings.mcp.onboarding.install")
        }
        Text(McpOnboarding.installURL.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(LightamerColors.textSecondary)
            .textSelection(.enabled)
        Text("settings_mcp_onboarding_cli_hint")
            .font(.caption)
            .foregroundStyle(LightamerColors.textSecondary)
        if let installError {
            Text(installError)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        snippet(
            titleKey: "settings_mcp_onboarding_claude_code",
            text: McpOnboarding.claudeCodeCommand,
            id: "settings.mcp.onboarding.claude-code")
        snippet(
            titleKey: "settings_mcp_onboarding_claude_desktop",
            text: McpOnboarding.desktopConfig,
            id: "settings.mcp.onboarding.claude-desktop")
        snippet(
            titleKey: "settings_mcp_onboarding_cli",
            text: McpOnboarding.cliUsage,
            id: "settings.mcp.onboarding.cli")
        Text("settings_mcp_onboarding_config_hint")
            .font(.caption)
            .foregroundStyle(LightamerColors.textSecondary)
    }

    private var statusText: String {
        switch installState {
        case .absent: String(localized: "settings_mcp_onboarding_not_installed")
        case .current: String(localized: "settings_mcp_onboarding_installed")
        case .other: String(localized: "settings_mcp_onboarding_installed_other")
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            installError = nil
        } catch {
            installError = String(describing: error)
        }
        installState = McpOnboarding.installState
    }

    private func snippet(titleKey: LocalizedStringKey, text: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(titleKey)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button(
                    copied == id
                        ? String(localized: "settings_mcp_onboarding_copied")
                        : String(localized: "settings_mcp_onboarding_copy")
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = id
                }
                .accessibilityIdentifier(id + ".copy")
            }
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(LightamerColors.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(id)
        }
    }
}

// MARK: - Page 11 (gate=true only): Catalogs (M2-2-4 migration — verbatim)

/// The catalog face, relocated verbatim from SettingsView: the enable
/// toggle, the location row, the rebuild faces and their dialogs. The gate
/// CONDITIONAL moved up into `SettingsView`'s page list
/// (`displayedPages(legacyLibraryEnabled:)`); inside this page the sections
/// render unconditionally (the gate is the LIST's business).
struct SettingsCatalogsPage: View {
    @Environment(CatalogPreferencesModel.self) private var catalogPreferences

    @State private var confirmDestructive = false

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
                    // L057 (fix(l057)): async panel via the begin seam.
                    Task { await chooseLocation() }
                }
                .disabled(catalogPreferences.isRebuilding)
                .accessibilityIdentifier("settings.catalogs.change_location")

                Text("settings_catalogs_backup_hint")
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }

            Section(String(localized: "settings_catalogs_rebuild_section")) {
                if catalogPreferences.schemaFailed {
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
            String(
                format: String(localized: "catalog_rebuild_done_reconcile %lld"),
                sessions)
        case .restoredDestructive:
            String(localized: "catalog_rebuild_done_destructive")
        case .failed(let reason):
            String(format: String(localized: "catalog_rebuild_failed %@"), reason)
        case nil: ""
        }
    }

    /// L057 (fix(l057)): async via the begin seam.
    private func chooseLocation() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = catalogPreferences.catalogURL.deletingLastPathComponent()
        guard let directory = await PanelPresentation.present(panel) else { return }
        catalogPreferences.setLocation(directory: directory)
    }
}
