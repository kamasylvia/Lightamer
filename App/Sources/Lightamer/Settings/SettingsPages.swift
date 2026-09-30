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
                    defaultValue: "Applies when a drawn mask is completed. Takes effect with the mask editor (M2-7)."))
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
                        chooseLutRoot()
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
            localized: "settings_lut_rescan_done \(store.installedNames.count)")
    }

    private func chooseLutRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = preferences.lutLibraryRoot()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyLutRoot(url)
    }

    private func resetLutRoot() {
        preferences.resetLutLibraryRoot()
        let store = LutLibraryStore()
        LutLibraryStore.replaceShared(store)
        lutRootPath = store.lutsDirectory.path
        lutStatusLine = String(
            localized: "settings_lut_rescan_done \(store.installedNames.count)")
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

// MARK: - Pages 4+5: LCR / ACA honest empty states (M2-10)

/// The shared structural skeleton for the two M2-10 pages: a segmented-card
/// layout with the arrival copy and ZERO fake switches (D7).
struct SettingsPlaceholderPage: View {
    let identifier: String
    let title: String
    let featureName: String

    var body: some View {
        Form {
            Section(title) {
                Label {
                    Text(verbatim: "\(featureName) ")
                        + Text(String(
                            localized: "settings_placeholder_arrives",
                            defaultValue: "arrives with M2-10"))
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.callout)
                .foregroundStyle(LightamerColors.textSecondary)
                .accessibilityIdentifier("\(identifier).arrival")
                Text(String(
                    localized: "settings_placeholder_hint",
                    defaultValue: "This page is a placeholder — no settings exist yet. On-device recognition features land with milestone M2-10."))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.\(identifier)")
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
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.page.mcp")
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
            String(localized: "catalog_rebuild_done_reconcile \(sessions)")
        case .restoredDestructive:
            String(localized: "catalog_rebuild_done_destructive")
        case .failed(let reason):
            String(localized: "catalog_rebuild_failed \(reason)")
        case nil: ""
        }
    }

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
