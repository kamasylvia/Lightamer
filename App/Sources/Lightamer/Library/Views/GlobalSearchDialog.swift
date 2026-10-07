import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// GlobalSearchDialog (Plan M2-3-2 T3, KD-3 / D8 = OQ-8 A) — the three-segment
// global search, the Alcedo `GlobalSearchDialog` IA: MODE (three segment
// cards) + INPUT + APPLY. The EXIF leg is REAL (ExifSearchParser → the
// shared filter); the CLIP and AI-description/full-text legs are the HONEST
// M2-10 placeholders (a typed empty state and nothing else — no fake
// toggles, no fake results).
//
// PRESENTATION (checker m6): the sheet rides WorkspaceModel's
// isSearchDialogPresented — the HOST presents this view and writes
// dismissal back; the dialog NEVER self-owns the presentation state.
//
// ERRORS render INLINE (the input segment's error line) — never an alert.
// ─────────────────────────────────────────────────────────────────────────────

struct GlobalSearchDialog: View {

    /// The search logic face (parse → plan fold → shared filter).
    let model: LibrarySearchModel
    /// The dismissal route (the host's binding; m6 single-owner).
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var lastError: LibrarySearchModel.ErrorFamily?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(
                localized: "search_dialog_title",
                defaultValue: "Search Library"))
                .font(.headline)
                .foregroundStyle(ThemeTokens.textPrimary)

            modeSegment
            inputSegment
            applySegment
        }
        .padding(18)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ThemeTokens.cardSurface)
                .shadow(radius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ThemeTokens.cardBorder, lineWidth: 1))
        .padding(30)
        .background(ThemeTokens.busyDim)
        .accessibilityIdentifier("search.dialog")
    }

    // MARK: - The mode segment (three cards)

    private var modeSegment: some View {
        HStack(spacing: 8) {
            modeCard(.exif, title: String(
                localized: "search_mode_exif", defaultValue: "EXIF"),
                marker: "search.tab.exif")
            modeCard(.clip, title: String(
                localized: "search_mode_clip", defaultValue: "CLIP"),
                marker: "search.tab.clip")
            modeCard(.fullText, title: String(
                localized: "search_mode_fulltext",
                defaultValue: "AI Descriptions & Tags"),
                marker: "search.tab.fulltext")
        }
    }

    private func modeCard(
        _ mode: LibrarySearchModel.Mode, title: String, marker: String
    ) -> some View {
        Button {
            model.select(mode: mode)
            lastError = nil
        } label: {
            Text(verbatim: title)
                .font(.callout.weight(model.mode == mode ? .semibold : .regular))
                .foregroundStyle(
                    model.mode == mode
                        ? ThemeTokens.accent : ThemeTokens.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            model.mode == mode
                                ? ThemeTokens.accent.opacity(0.14)
                                : ThemeTokens.cardBorder.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(marker)
    }

    // MARK: - The input segment

    @ViewBuilder
    private var inputSegment: some View {
        switch model.mode {
        case .exif:
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    String(localized:
                        "search_exif_placeholder",
                        defaultValue:
                        "e.g. sony iso800 f/2.8 35mm 2024-06"),
                    text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                    .onSubmit { Task { await apply() } }
                    .accessibilityIdentifier("search.input")
                if let lastError {
                    Text(verbatim: lastError.message)
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.accent)
                        .accessibilityIdentifier("search.error")
                }
                Text(String(
                    localized: "search_exif_hint",
                    defaultValue:
                        "Words search EXIF text; iso/f/35mm/dates combine with AND."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        case .clip:
            placeholderState(
                marker: "search.tab.clip.placeholder",
                copy: String(
                    localized: "search_tab_clip_placeholder",
                    defaultValue: "Semantic CLIP search arrives with M2-10"))
        case .fullText:
            placeholderState(
                marker: "search.tab.fulltext.placeholder",
                copy: String(
                    localized: "search_tab_fulltext_placeholder",
                    defaultValue: "AI description & tag full-text search arrives with M2-10"))
        }
    }

    private func placeholderState(marker: String, copy: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(ThemeTokens.textSecondary)
            Text(verbatim: copy)
                .font(.callout)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(ThemeTokens.cardBorder.opacity(0.2)))
        .accessibilityIdentifier(marker)
    }

    // MARK: - The apply segment

    private var applySegment: some View {
        HStack {
            Spacer()
            Button {
                query = ""
                lastError = nil
                Task { await apply() }
            } label: {
                Text(String(
                    localized: "search_clear", defaultValue: "Clear Filter"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThemeTokens.textSecondary)
            .accessibilityIdentifier("search.clear")

            Button {
                Task { await apply() }
            } label: {
                Text(String(
                    localized: "search_apply", defaultValue: "Search"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.mode != .exif)
            .accessibilityIdentifier("search.apply")
        }
    }

    private func apply() async {
        let outcome = await model.submit(query)
        if case .failed(let family) = outcome {
            lastError = family
        } else {
            lastError = nil
            onDismiss()
        }
    }
}
