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
    }

    @Environment(SessionState.self) private var sessionState
    @Environment(SessionCoordinator.self) private var sessionCoordinator

    var body: some View {
        List {
            currentSection
            recentSection
            watchSection
        }
        .listStyle(.sidebar)
        .accessibilityLabel(Text("sessions"))
        .accessibilityIdentifier("Sessions")
        .accessibilityHint(Text("a11y_sidebar_hint"))
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
        }
    }

    // MARK: - Actions

    private func openSessionPanel() {
        FileOpener.openSessionFolder { url in
            Task { await sessionCoordinator.openSession(url: url) }
        }
    }
}
