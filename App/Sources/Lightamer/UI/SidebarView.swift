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

    var body: some View {
        List {
            currentSection
            smartAlbumSection
            recentSection
            watchSection
        }
        .listStyle(.sidebar)
        .accessibilityLabel(Text("sessions"))
        .accessibilityIdentifier("Sessions")
        .accessibilityHint(Text("a11y_sidebar_hint"))
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
}
