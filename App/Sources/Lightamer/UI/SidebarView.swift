import SwiftUI

/// Sidebar column — Session navigation (Phase 1 stub, UI-SPEC "Sidebar").
///
/// D-03b: injects ONLY `SessionState`.
internal struct SidebarView: View {

    @Environment(SessionState.self) private var sessionState

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("no_sessions")
                        .font(.headline)
                    Text("no_sessions_hint")
                        .font(.callout)
                        .foregroundStyle(LightamerColors.textSecondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("sessions")
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel(Text("sessions"))
        .accessibilityIdentifier("Sessions")
        .accessibilityHint(Text("a11y_sidebar_hint"))
    }
}
