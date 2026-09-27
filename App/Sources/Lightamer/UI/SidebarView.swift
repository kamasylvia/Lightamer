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
    // Plan 16-3 T3: the organization tree/collections model.
    @Environment(CatalogTreeModel.self) private var catalogTree
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

    // Plan 16-3 T3: the organization name sheet (one alert face for the
    // four create/rename flows) + the tree drag-drop payload prefixes.
    @State private var organizationNameSheet: OrganizationNameSheet?
    @State private var organizationNameText = ""

    /// The four name-entry flows (create/rename × category/collection).
    private enum OrganizationNameSheet: Identifiable {
        case newCategory(parentID: Int64?)
        case renameCategory(id: Int64)
        case newCollection
        case renameCollection(id: Int64)

        var id: String {
            switch self {
            case .newCategory(let parent): "newCategory-\(parent.map(String.init) ?? "root")"
            case .renameCategory(let id): "renameCategory-\(id)"
            case .newCollection: "newCollection"
            case .renameCollection(let id): "renameCollection-\(id)"
            }
        }

        var alertTitle: String {
            String(localized: String.LocalizationValue(titleKey))
        }

        var placeholder: String {
            String(localized: String.LocalizationValue(placeholderKey))
        }

        private var titleKey: String {
            switch self {
            case .newCategory: "catalog_category_new"
            case .renameCategory: "catalog_category_rename"
            case .newCollection: "catalog_collection_new"
            case .renameCollection: "catalog_collection_rename"
            }
        }

        private var placeholderKey: String {
            switch self {
            case .newCategory, .renameCategory: "catalog_name_prompt_category"
            case .newCollection, .renameCollection: "catalog_name_prompt_collection"
            }
        }
    }

    private static let categoryDragPrefix = "lightamer.cat:"
    private static let collectionDragPrefix = "lightamer.col:"

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
        // Plan 16-3 T3: the four organization name flows (one alert face).
        .alert(
            organizationNameSheet?.alertTitle ?? "",
            isPresented: Binding(
                get: { organizationNameSheet != nil },
                set: { if !$0 { organizationNameSheet = nil } })
        ) {
            TextField(
                organizationNameSheet?.placeholder ?? "",
                text: $organizationNameText)
            Button(String(localized: "alert_ok")) {
                commitOrganizationNameSheet()
            }
            .disabled(
                organizationNameText.trimmingCharacters(in: .whitespaces).isEmpty
                    || organizationNameText.contains("|"))
            Button(String(localized: "alert_cancel"), role: .cancel) {
                organizationNameSheet = nil
            }
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
                    // The router's cached root/offline map is stale.
                    CatalogThumbnailRouter.shared?.invalidateRoots()
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
            // String(format:) — a LocalizedStringKey interpolation would
            // look up "smart_album_delete_confirm_body %@" which is NOT the
            // catalog key (13-4 walkthrough finding: the raw key leaked
            // into the alert body).
            Text(String(format: String(localized: "smart_album_delete_confirm_body"), album.name))
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

    /// Categories — Plan 16-3 T3: the organization tree (flat always-
    /// expanded rows with depth indentation — execution decision; collapse
    /// is additive), one click = the scope anchor, context menu CRUD
    /// (leaf-only delete, disabled on non-empty parents WITH the hint),
    /// drag & drop = the model's before-target reorder/move.
    private var catalogCategoriesSection: some View {
        Section {
            ForEach(catalogTree.flatRows(), id: \.node.id) { row in
                categoryRow(row.node, depth: row.depth)
            }
            Button {
                organizationNameText = ""
                organizationNameSheet = .newCategory(parentID: nil)
            } label: {
                Label(
                    String(localized: "catalog_category_new"),
                    systemImage: "plus.circle")
            }
            .accessibilityIdentifier("catalog.category.add")
            if catalogTree.tree.isEmpty {
                Text("catalog_categories_empty")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
            if let failure = catalogTree.lastErrorText {
                Text(failure)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        } header: {
            Text("catalog_categories_section")
        }
    }

    /// One tree row: click = the categoryID scope anchor (re-click clears);
    /// draggable/dropDestination carry the before-target move. Indentation
    /// expresses the depth (the flat always-expanded row face).
    private func categoryRow(_ node: CatalogTreeNode, depth: Int) -> some View {
        let active = catalogBrowserModel.activeScope.categoryID == node.id
        return Button {
            Task {
                await catalogBrowserModel.setScope(
                    FilterScope(categoryID: active ? nil : node.id))
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(LightamerColors.textSecondary)
                Text(node.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, CGFloat(depth) * 14)
        }
        .accessibilityIdentifier("catalog.category.row.\(node.id)")
        .contextMenu {
            Button(String(localized: "catalog_category_new_child")) {
                organizationNameText = ""
                organizationNameSheet = .newCategory(parentID: node.id)
            }
            Button(String(localized: "catalog_category_rename")) {
                organizationNameText = node.name
                organizationNameSheet = .renameCategory(id: node.id)
            }
            moveToMenu(dragged: node.id)
            Button(
                String(localized: "catalog_category_delete"),
                role: .destructive
            ) {
                Task { await catalogTree.deleteCategory(id: node.id) }
            }
            .disabled(!node.children.isEmpty)
            if !node.children.isEmpty {
                Text("catalog_category_delete_disabled_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        }
        .draggable(Self.categoryDragPrefix + String(node.id))
        .dropDestination(for: String.self) { payload, _ in
            guard let raw = payload.first,
                  let dragged = Self.draggedID(raw, prefix: Self.categoryDragPrefix)
            else { return false }
            Task { await catalogTree.moveCategory(dragged: dragged, before: node.id) }
            return true
        } isTargeted: { _ in }
    }

    /// The move-to menu: a flat depth-indented list (execution decision —
    /// no recursive submenus in v1); the dragged node's own subtree is
    /// excluded (moving into itself is refused by the store anyway).
    private func moveToMenu(dragged: Int64) -> some View {
        Menu(String(localized: "catalog_category_move")) {
            ForEach(
                catalogTree.flatCategories()
                    .filter { !$0.contains(id: dragged) }
            ) { node in
                Button(depthPrefixedName(node)) {
                    Task {
                        await catalogTree.moveCategory(
                            dragged: dragged, before: node.id)
                    }
                }
            }
        }
    }

    private func depthPrefixedName(_ node: CatalogTreeNode) -> String {
        let byID = Dictionary(
            uniqueKeysWithValues: catalogTree.flatCategories().map { ($0.id, $0) })
        var depth = 0
        var current: CatalogTreeNode? = node
        while let parentID = current?.parentID, let parent = byID[parentID] {
            depth += 1
            current = parent
        }
        return String(repeating: "· ", count: depth) + node.name
    }

    /// Collections — Plan 16-3 T3: the flat list (click = the collectionID
    /// anchor) with the same CRUD/drag face.
    private var catalogCollectionsSection: some View {
        Section {
            ForEach(catalogTree.collections) { collection in
                collectionRow(collection)
            }
            Button {
                organizationNameText = ""
                organizationNameSheet = .newCollection
            } label: {
                Label(
                    String(localized: "catalog_collection_new"),
                    systemImage: "plus.circle")
            }
            .accessibilityIdentifier("catalog.collection.add")
            if catalogTree.collections.isEmpty {
                Text("catalog_collections_empty")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textSecondary)
            }
        } header: {
            Text("catalog_collections_section")
        }
    }

    private func collectionRow(_ collection: CatalogCollectionEntry) -> some View {
        let active = catalogBrowserModel.activeScope.collectionID == collection.id
        return Button {
            Task {
                await catalogBrowserModel.setScope(
                    FilterScope(collectionID: active ? nil : collection.id))
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(LightamerColors.textSecondary)
                Text(collection.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .accessibilityIdentifier("catalog.collection.row.\(collection.id)")
        .contextMenu {
            Button(String(localized: "catalog_collection_rename")) {
                organizationNameText = collection.name
                organizationNameSheet = .renameCollection(id: collection.id)
            }
            Button(
                String(localized: "catalog_collection_delete"),
                role: .destructive
            ) {
                Task { await catalogTree.deleteCollection(id: collection.id) }
            }
        }
        .draggable(Self.collectionDragPrefix + String(collection.id))
        .dropDestination(for: String.self) { payload, _ in
            guard let raw = payload.first,
                  let dragged = Self.draggedID(raw, prefix: Self.collectionDragPrefix)
            else { return false }
            Task { await catalogTree.moveCollection(dragged: dragged, before: collection.id) }
            return true
        } isTargeted: { _ in }
    }

    private static func draggedID(_ raw: String, prefix: String) -> Int64? {
        guard raw.hasPrefix(prefix) else { return nil }
        return Int64(raw.dropFirst(prefix.count))
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
    /// refreshes after projections are cheap). Plan 16-3: the organization
    /// tree/collections faces ride the SAME re-derivation path.
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
        await catalogTree.refresh()
    }

    /// The name sheet's OK face (Plan 16-3 T3) — dispatch on the pending
    /// flow, then drop the sheet.
    private func commitOrganizationNameSheet() {
        guard let sheet = organizationNameSheet else { return }
        organizationNameSheet = nil
        let name = organizationNameText
        Task {
            switch sheet {
            case .newCategory(let parentID):
                await catalogTree.createCategory(name: name, parentID: parentID)
            case .renameCategory(let id):
                await catalogTree.renameCategory(id: id, to: name)
            case .newCollection:
                await catalogTree.createCollection(name: name)
            case .renameCollection(let id):
                await catalogTree.renameCollection(id: id, to: name)
            }
        }
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
            // The router re-probes roots/offline on the next grid visit.
            CatalogThumbnailRouter.shared?.invalidateRoots()
            await refreshCatalogFaces()
            await catalogBrowserModel.refreshAfterProjection()
        }
        relinkSessionTarget = nil
    }
}
