import SwiftUI
import UniformTypeIdentifiers

/// Empty state (D-11, UI-SPEC "Empty State"): hero icon + headline + body +
/// primary CTA + drag affordance. Copy is keyed through the String Catalog
/// (en source + zh translation) — never hardcoded.
internal struct EmptyStateView: View {

    /// Called with the dropped/selected file URL; the parent wires this to
    /// `EditorState.load(url:)` (Plan 02 makes it decode for real).
    var onOpen: @MainActor (URL) -> Void

    /// 13-3 T4 (D-13-CONTEXT-7): the file-level drop leg — the parent
    /// routes a dropped FOLDER to the session-open flow and dropped FILES
    /// to the single-image edit (the :57 onDrop 先例 extended from a
    /// single URL to the batch). nil = the legacy single-URL drop.
    var onDropURLs: (@MainActor ([URL]) -> Void)?

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(LightamerColors.textSecondary)

            Text("select_folder_to_create_session")
                .font(.system(size: 28, weight: .bold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .foregroundStyle(LightamerColors.textPrimary)
                .multilineTextAlignment(.center)

            Text("empty_state_body")
                .font(.body)
                .foregroundStyle(LightamerColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Button(String(localized: "select_folder")) {
                FileOpener.openFolder { onOpen($0) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint(Text("a11y_select_folder_hint"))

            Text("drag_raw_hint")
                .font(.callout)
                .foregroundStyle(LightamerColors.textTertiary)
        }
        .padding(48)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LightamerColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? LightamerColors.accent.opacity(0.6) : LightamerColors.border,
                    lineWidth: isTargeted ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8) // elevation-card
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            if let onDropURLs {
                SessionBrowserView.loadDropURLs(providers: providers) { urls in
                    guard !urls.isEmpty else { return }
                    onDropURLs(urls)
                }
                return true
            }
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in onOpen(url) }
            }
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("a11y_empty_state_label"))
        .accessibilityIdentifier("Empty state")
    }
}
