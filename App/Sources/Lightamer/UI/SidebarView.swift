import AppKit
import LightamerCore
import SwiftUI

/// Sidebar column — Session navigation (Plan 09-01 T1: the three-section
/// session area).
///
/// Sections: ① current session (name/path/counts, or the empty-state card
/// with the open button), ② recent sessions (tap = same-window switch,
/// L012), ③ folder-watch status line (Plan 9-2 feeds the real source).
///
/// L010: identifiers for region queries (`session.current` /
/// `session.row.<pathhash>` / `session.watch` — STABLE ids, never index);
/// labels live on LEAF text only; the List container keeps its Phase 1
/// label (`AppLaunchTests` queries it — L010's swallow behavior accepted
/// there since Phase 1 UAT).
internal struct SidebarView: View {

    /// Stable identifiers for the session area (unit-test + UITest anchors).
    internal enum SessionIdentifiers {
        static let current = "session.current"
        static let watch = "session.watch"
        static let openButton = "session.open"
        /// Stable per-path id (FNV-1a decimal — survives relaunches, no
        /// array-index coupling).
        static func row(_ url: URL) -> String {
            "session.row.\(StableHash.hash(url.path))"
        }
        /// Stable per-orphan id (09-02 T4; L010 leaf-level).
        static func orphan(_ relPath: String) -> String {
            "session.orphan.\(StableHash.hash(relPath))"
        }
    }

    @Environment(SessionState.self) private var sessionState
    @Environment(SessionCoordinator.self) private var sessionCoordinator

    /// The orphan row pending REMOVE confirmation (nil = dialog closed).
    /// REMOVE destroys a sidecar file — the dialog is the misfire guard;
    /// IGNORE is non-destructive and needs no confirm.
    @State private var orphanPendingRemoval: String?

    // Plan 12-2 T5: the smart-album section's local face.
    @Environment(SmartAlbumStore.self) private var smartAlbumStore
    @State private var renameTarget: SmartAlbum?
    @State private var renameText = ""
    @State private var deleteTarget: SmartAlbum?
    @State private var createRequested = false
    @State private var createName = ""

    // Plan 16-2 T2: the organization-mode axis + the Catalogs five-section
    // face. The switcher exists ONLY when Catalogs is enabled (D-16-
    // CONTEXT-5① — the Sessions default is zero-awareness); the persisted
    // selection is overwritten with the sessions constant on the app's
    // first frame (ContentView.onAppear — RQ-16-12 冷启动恒 Sessions).
    @Environment(CatalogPreferencesModel.self) private var catalogPreferences
    @Environment(CatalogBrowserModel.self) private var catalogBrowserModel
    @AppStorage(CatalogPreferencesModel.organizationModeStorageKey)
    private var organizationModeRaw: String = CatalogPreferencesModel.coldStartRawValue

    /// The catalog_sessions registry rows (the Sessions 从属节's data).
    @State private var catalogSessionRows: [CatalogIndexStore.CatalogSessionRow] = []
    /// The smart-album badge counts (catalog-domain `count` consumption;
    /// refreshed on appear and after projections — the memo absorbs the
    /// repeated queries).
    @State private var catalogAlbumCounts: [String: Int] = [:]
    /// The session row pending REMOVE (the dialog is the misfire guard —
    /// the action also deletes the organization memberships, so the copy
    /// says so) / the session row pending RE-LINK (the panel's anchor).
    @State private var removeSessionTarget: CatalogIndexStore.CatalogSessionRow?
    @State private var relinkSessionTarget: CatalogIndexStore.CatalogSessionRow?

    private var organizationMode: CatalogPreferencesModel.OrganizationMode {
        CatalogPreferencesModel.OrganizationMode(rawValue: organizationModeRaw) ?? .sessions
    }

    var body: some View {
        List {
            if catalogPreferences.catalogsEnabled {
                modeSection
            }
            if catalogPreferences.catalogsEnabled,
               organizationMode == .catalogs {
                catalogAllPhotographsSection
                catalogCategoriesSection
                catalogCollectionsSection
                catalogSmartAlbumSection
                catalogSessionsSection
            } else {
                currentSection
                smartAlbumSection
                recentSection
                watchSection
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel(Text("sessions"))
        .accessibilityIdentifier("Sessions")
        .accessibilityHint(Text("a11y_sidebar_hint"))
        .task(id: organizationModeRaw) {
            await refreshCatalogFaces()
        }
        .confirmationDialog(
            String(localized: "catalog_session_remove_confirm_title"),
            isPresented: Binding(
                get: { removeSessionTarget != nil },
                set: { if !$0 { removeSessionTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: removeSessionTarget
        ) { row in
            Button(
                String(localized: "catalog_session_remove_confirm_action"),
                role: .destructive
            ) {
                Task {
                    try? await SessionIndexController.sharedCatalogProjector
                        .removeSession(sessionID: row.sessionID)
                    // The removed session's anchor scope is dead — the grid
                    // falls back to All Photographs.
                    if catalogBrowserModel.activeScope.sessionID == row.sessionID {
                        await catalogBrowserModel.setScope(FilterScope())
                    }
                    await refreshCatalogFaces()
                }
            }
            Button(String(localized: "alert_ok"), role: .cancel) {}
        } message: { row in
            Text("catalog_session_remove_confirm_body \(row.displayName ?? row.rootPath)")
        }
        .confirmationDialog(
            String(localized: "session_orphan_remove_confirm_title"),
            isPresented: Binding(
                get: { orphanPendingRemoval != nil },
                set: { if !$0 { orphanPendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: orphanPendingRemoval
        ) { rel in
            Button(
                String(localized: "session_orphan_remove_confirm_action"),
                role: .destructive
            ) {
                Task { await sessionCoordinator.removeOrphanSidecar(rel) }
            }
            Button(String(localized: "alert_ok"), role: .cancel) {}
        } message: { rel in
            Text("session_orphan_remove_confirm_body \(rel)")
        }
        // The smart-album DELETE guard (an album rule file is destroyed).
        .confirmationDialog(
            String(localized: "smart_album_delete_confirm_title"),
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { album in
            Button(String(localized: "smart_album_delete"), role: .destructive) {
                try? smartAlbumStore.remove(id: album.id)
                if sessionState.activeSmartAlbumID == album.id {
                    sessionState.activateSmartAlbum(id: nil, group: nil)
                }
            }
            Button(String(localized: "alert_ok"), role: .cancel) {}
        } message: { album in
            Text("smart_album_delete_confirm_body \(album.name)")
        }
        // The rename / create sheets (one alert face each — a single text
        // field; the '|' separator is banned like every tag entry).
        .alert(
            String(localized: "smart_album_rename_title"),
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } })
        ) {
            TextField(
                String(localized: "smart_album_name_placeholder"),
                text: $renameText)
            Button(String(localized: "alert_ok")) {
                guard let target = renameTarget else { return }
                renameTarget = nil
                try? smartAlbumStore.rename(id: target.id, to: renameText)
            }
            Button(String(localized: "alert_cancel"), role: .cancel) {
                renameTarget = nil
            }
        }
        .alert(
            String(localized: "smart_album_new_title"),
            isPresented: $createRequested
        ) {
            TextField(
                String(localized: "smart_album_name_placeholder"),
                text: $createName)
            Button(String(localized: "smart_album_create")) {
                let name = createName
                createName = ""
                createRequested = false
                let chips = sessionState.filterChips
                let group = FilterPredicateGroup(match: .all, rules: chips)
                if let album = try? smartAlbumStore.create(name: name, group: group) {
                    sessionState.activateSmartAlbum(id: album.id, group: album.group)
                }
            }
            .disabled(
                createName.trimmingCharacters(in: .whitespaces).isEmpty
                    || createName.contains("|")
                    || sessionState.filterChips.isEmpty)
            Button(String(localized: "alert_cancel"), role: .cancel) {
                createRequested = false
            }
        } message: {
            Text("smart_album_new_body")
        }
    }

    // MARK: - ① Current session / empty state

    @ViewBuilder
    private var currentSection: some View {
        Section {
            if let url = sessionState.currentSessionURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .accessibilityIdentifier(SessionIdentifiers.current)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(LightamerColors.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.head)
                    if let counts = sessionState.browseCounts {
                        Text("session_counts \(counts.total) \(counts.edited) \(counts.orphans)")
                            .font(.caption)
                            .foregroundStyle(LightamerColors.textSecondary)
                    }
                    orphanSection
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("no_sessions")
                        .font(.headline)
                    Text("no_sessions_hint")
                        .font(.callout)
                        .foregroundStyle(LightamerColors.textSecondary)
                    Button(String(localized: "session_open_button")) {
                        openSessionPanel()
                    }
                    .accessibilityIdentifier(SessionIdentifiers.openButton)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("session_current")
        }
    }

    // MARK: - ①-b Orphan sidecars (09-02 T4 — remove / ignore, never a
    // hard failure; the grid badge is 9-3)

    @ViewBuilder
    private var orphanSection: some View {
        if !sessionState.orphanSidecarRelPaths.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                // 09-3 visual seam: the count badge rides the header (the
                // grid's orphan cells mirror the same count).
                HStack(spacing: 4) {
                    Text("session_orphan_header")
                        .font(.caption2)
                        .foregroundStyle(LightamerColors.textSecondary)
                    Text("\(sessionState.orphanSidecarRelPaths.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.orange))
                        .accessibilityIdentifier("session.orphan.count")
                }
                ForEach(sessionState.orphanSidecarRelPaths, id: \.self) { rel in
                    HStack(spacing: 6) {
                        Text(rel)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            orphanPendingRemoval = rel
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("session_orphan_remove"))
                        .accessibilityIdentifier(SessionIdentifiers.orphan(rel) + ".remove")
                        Button {
                            Task { await sessionCoordinator.ignoreOrphanSidecar(rel) }
                        } label: {
                            Image(systemName: "eye.slash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("session_orphan_ignore"))
                        .accessibilityIdentifier(SessionIdentifiers.orphan(rel) + ".ignore")
                    }
                    .accessibilityIdentifier(SessionIdentifiers.orphan(rel))
                }
            }
        }
    }

    // MARK: - ② Smart albums (Plan 12-2 T5; D-12-CONTEXT-4 — rules ride
    // the app, results follow the open session)

    @ViewBuilder
    private var smartAlbumSection: some View {
        Section {
            ForEach(smartAlbumStore.albums()) { album in
                let active = sessionState.activeSmartAlbumID == album.id
                Button {
                    // Toggle: an active album deactivates back to the chip
                    // face (activation replaces the chips — the mutual-
                    // exclusion decision).
                    if active {
                        sessionState.activateSmartAlbum(id: nil, group: nil)
                    } else {
                        sessionState.activateSmartAlbum(id: album.id, group: album.group)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(LightamerColors.textSecondary)
                        Text(album.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if active {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityIdentifier("smartalbum.row." + album.id)
                .contextMenu {
                    Button(String(localized: "smart_album_rename")) {
                        renameText = album.name
                        renameTarget = album
                    }
                    Button(String(localized: "smart_album_delete"), role: .destructive) {
                        deleteTarget = album
                    }
                }
            }
            Button {
                createName = ""
                createRequested = true
            } label: {
                Label(
                    String(localized: "smart_album_add"),
                    systemImage: "plus.circle")
            }
            .disabled(sessionState.filterChips.isEmpty)
            .accessibilityIdentifier("smartalbum.add")
            if smartAlbumStore.albums().isEmpty {
                Text("smart_album_empty_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        } header: {
            Text("smart_albums_section")
        }
    }

    // MARK: - ② Recent sessions

    @ViewBuilder
    private var recentSection: some View {
        Section {
            ForEach(
                sessionState.recentSessions, id: \.absoluteString
            ) { url in
                Button {
                    Task { await sessionCoordinator.openSession(url: url) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.callout)
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption2)
                            .foregroundStyle(LightamerColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .accessibilityIdentifier(SessionIdentifiers.row(url))
            }
        } header: {
            Text("session_recent")
        }
    }

    // MARK: - ③ Watch status

    @ViewBuilder
    private var watchSection: some View {
        Section {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 8, height: 8)
                Text(String(localized: String.LocalizationValue(
                    sessionState.folderWatchStatus.displayKey
                )))
                .font(.caption)
            }
            .accessibilityIdentifier(SessionIdentifiers.watch)
            if sessionState.currentSessionRootLost {
                // WatchRoot fired: the session folder moved/renamed — the
                // recent entry is stale; reopening is an explicit action.
                Text("session_watch_root_lost_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        } header: {
            Text("session_watch")
        }
    }

    private var statusTint: Color {
        switch sessionState.folderWatchStatus {
        case .notWatching: LightamerColors.textSecondary
        case .scanning: .yellow
        case .synced: .green
        case .stale: .orange
        case .rootLost: .red
        }
    }

    // MARK: - Actions

    private func openSessionPanel() {
        FileOpener.openSessionFolder { url in
            Task { await sessionCoordinator.openSession(url: url) }
        }
    }

    // MARK: - 16-2 T2: the mode switcher + the Catalogs five sections

    /// The segmented switcher — exists ONLY while Catalogs is enabled
    /// (D-16-CONTEXT-5①); the L010 stable-id face rides the picker.
    private var modeSection: some View {
        Section {
            Picker(
                String(localized: "organization_mode_label"),
                selection: $organizationModeRaw
            ) {
                Text(String(localized: "organization_mode_sessions"))
                    .tag(CatalogPreferencesModel.OrganizationMode.sessions.rawValue)
                Text(String(localized: "organization_mode_catalogs"))
                    .tag(CatalogPreferencesModel.OrganizationMode.catalogs.rawValue)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("organization.mode")
        }
    }

    /// All Photographs — the no-anchor full-library grid entry.
    private var catalogAllPhotographsSection: some View {
        Section {
            Button {
                Task { await catalogBrowserModel.setScope(FilterScope()) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundStyle(LightamerColors.textSecondary)
                    Text("catalog_all_photographs")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if catalogBrowserModel.activeScope.isDefault {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .accessibilityIdentifier("catalog.section.all")
        }
    }

    /// Categories — the 16-3 tree wiring slot (this plan: the skeleton +
    /// the empty face).
    private var catalogCategoriesSection: some View {
        Section {
            Text("catalog_categories_empty")
                .font(.caption2)
                .foregroundStyle(LightamerColors.textSecondary)
        } header: {
            Text("catalog_categories_section")
        }
    }

    /// Collections — the 16-3 list wiring slot (same shape).
    private var catalogCollectionsSection: some View {
        Section {
            Text("catalog_collections_empty")
                .font(.caption2)
                .foregroundStyle(LightamerColors.textSecondary)
        } header: {
            Text("catalog_collections_section")
        }
    }

    /// Smart Albums (catalog face) — the SAME app-level rule assets; the
    /// activation drives the CATALOG grid's groups and the badge counts
    /// evaluate on the catalog domain (D-16-CONTEXT-6 — the rules ride the
    /// app, the results follow the MODE's connection).
    private var catalogSmartAlbumSection: some View {
        Section {
            ForEach(smartAlbumStore.albums()) { album in
                let active = catalogBrowserModel.activeSmartAlbumID == album.id
                Button {
                    if active {
                        catalogBrowserModel.activateSmartAlbum(id: nil, group: nil)
                    } else {
                        catalogBrowserModel.activateSmartAlbum(id: album.id, group: album.group)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(LightamerColors.textSecondary)
                        Text(album.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let count = catalogAlbumCounts[album.id] {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(LightamerColors.textSecondary)
                                .accessibilityIdentifier("catalog.smartalbum.count.\(album.id)")
                        }
                        if active {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityIdentifier("catalog.smartalbum.row." + album.id)
                .contextMenu {
                    Button(String(localized: "smart_album_rename")) {
                        renameText = album.name
                        renameTarget = album
                    }
                    Button(String(localized: "smart_album_delete"), role: .destructive) {
                        deleteTarget = album
                    }
                }
            }
            if smartAlbumStore.albums().isEmpty {
                Text("smart_album_empty_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        } header: {
            Text("smart_albums_section")
        }
    }

    /// The Sessions 从属节 (RQ-16-12 section five): one row per registered
    /// catalog session — display name + 图计数角标, offline rows gray out;
    /// the click = the sessionID scope anchor. The context menu carries the
    /// two session-management actions (D-16-CONTEXT-7②④).
    private var catalogSessionsSection: some View {
        Section {
            ForEach(catalogSessionRows, id: \.sessionID) { row in
                let active = catalogBrowserModel.activeScope.sessionID == row.sessionID
                Button {
                    Task {
                        await catalogBrowserModel.setScope(
                            FilterScope(
                                sessionID: active ? nil : row.sessionID))
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(LightamerColors.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.displayName ?? URL(fileURLWithPath: row.rootPath).lastPathComponent)
                                .lineLimit(1)
                                .foregroundStyle(
                                    row.offline == 1 ? LightamerColors.textSecondary : Color.primary)
                            if row.offline == 1 {
                                Text("catalog_session_offline")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.imageCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(LightamerColors.textSecondary)
                            .accessibilityIdentifier("catalog.session.count.\(row.sessionID)")
                        if active {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityIdentifier("catalog.session.row." + row.sessionID)
                .contextMenu {
                    Button(String(localized: "catalog_session_remove")) {
                        removeSessionTarget = row
                    }
                    Button(String(localized: "catalog_session_relink")) {
                        relinkSessionTarget = row
                        chooseRelinkDirectory()
                    }
                }
            }
            if catalogSessionRows.isEmpty {
                Text("catalog_empty_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        } header: {
            Text("catalog_sessions_section")
        }
    }

    /// The Catalogs-face data refresh (registry rows + smart-album badge
    /// counts — the badge queries ride the store's COUNT memo, so repeat
    /// refreshes after projections are cheap).
    private func refreshCatalogFaces() async {
        guard catalogPreferences.catalogsEnabled, organizationMode == .catalogs else { return }
        catalogSessionRows = (try? await SessionIndexController.sharedCatalogStore.fetchSessions())
            ?? []
        var counts: [String: Int] = [:]
        for album in smartAlbumStore.albums() where !album.group.rules.isEmpty {
            counts[album.id] = (try? await SessionIndexController.sharedCatalogStore
                .count(groups: [album.group])) ?? 0
        }
        catalogAlbumCounts = counts
    }

    /// The re-link directory picker (D-16-CONTEXT-7②: the user picks the
    /// moved folder — no automatic path search). The re-projection rides
    /// the projector's relink face; the sidebar faces refresh after.
    private func chooseRelinkDirectory() {
        guard let target = relinkSessionTarget else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "catalog_session_relink")
        guard panel.runModal() == .OK, let directory = panel.url else {
            relinkSessionTarget = nil
            return
        }
        Task {
            _ = try? await SessionIndexController.sharedCatalogProjector
                .relinkSession(sessionID: target.sessionID, newRoot: directory)
            await refreshCatalogFaces()
            await catalogBrowserModel.refreshAfterProjection()
        }
        relinkSessionTarget = nil
    }
}
