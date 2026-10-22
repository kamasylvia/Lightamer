import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// GlobalSearchDialog (Plan M2-3-2 T3, KD-3 / D8 = OQ-8 A) — the three-segment
// global search, the Alcedo `GlobalSearchDialog` IA: MODE (three segment
// cards) + INPUT + APPLY. The EXIF leg is REAL (ExifSearchParser → the
// shared filter); the CLIP leg is REAL since M2-10-02 (KD-6: the submit leg
// rides LibrarySearchModel.submitSemantic → the grid's semantic overlay —
// EXIF 腿同型集合过滤); the fulltext leg is REAL since M2-10-04 (KD-4: the
// submit leg rides submitFulltext → ai_understanding_fts MATCH → JOIN
// active=1 → the same overlay, rank-ordered).
//
// PRESENTATION (checker m6): the sheet rides WorkspaceModel's
// isSearchDialogPresented — the HOST presents this view and writes
// dismissal back; the dialog NEVER self-owns the presentation state.
//
// ERRORS render INLINE (the input segment's error line) — never an alert.
// A ZERO-hit semantic/fulltext search keeps the dialog open with the honest
//「无命中」note (the empty result set IS applied behind it — the count card
// shows 0).
// ─────────────────────────────────────────────────────────────────────────────

struct GlobalSearchDialog: View {

    /// The search logic face (parse → plan fold → shared filter).
    let model: LibrarySearchModel
    /// The dismissal route (the host's binding; m6 single-owner).
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var lastError: LibrarySearchModel.ErrorFamily?
    /// The zero-hit semantic note (kept-open face; cleared on any submit).
    @State private var emptyNote: String?

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
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(ThemeTokens.cardSurface)
                .shadow(radius: 18)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(ThemeTokens.cardBorder, lineWidth: 1)
        }
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
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            model.mode == mode
                                ? ThemeTokens.accent.opacity(0.14)
                                : ThemeTokens.cardBorder.opacity(0.3))
                }
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
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    String(localized:
                        "search_clip_placeholder",
                        defaultValue:
                        "Describe what you're looking for — any language"),
                    text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { Task { await apply() } }
                    .accessibilityIdentifier("search.input.clip")
                if let lastError {
                    Text(verbatim: lastError.message)
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.accent)
                        .accessibilityIdentifier("search.error")
                }
                if let emptyNote {
                    Text(verbatim: emptyNote)
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .accessibilityIdentifier("search.empty.note")
                }
                Text(String(
                    localized: "search_clip_hint",
                    defaultValue:
                        "Semantic search runs against the analyzed collection — import first, then let embedding finish."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        case .fullText:
            // M2-10-04 (KD-4): the REAL fulltext leg — the query rides
            // LibrarySearchModel.submitFulltext (FTS MATCH → JOIN active=1
            // → the grid overlay). Radius: this branch ONLY (the CLIP and
            // EXIF branches are untouched).
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    String(localized:
                        "search_fulltext_placeholder",
                        defaultValue:
                        "Search AI descriptions and tags"),
                    text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { Task { await apply() } }
                    .accessibilityIdentifier("search.input.fulltext")
                if let lastError {
                    Text(verbatim: lastError.message)
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.accent)
                        .accessibilityIdentifier("search.error")
                }
                if let emptyNote {
                    Text(verbatim: emptyNote)
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .accessibilityIdentifier("search.empty.note")
                }
                Text(String(
                    localized: "search_fulltext_hint",
                    defaultValue:
                        "Matches image captions and tags written by AI description analysis."))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        }
    }

    // MARK: - The apply segment

    private var applySegment: some View {
        HStack {
            Spacer()
            Button {
                query = ""
                lastError = nil
                emptyNote = nil
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
            .accessibilityIdentifier("search.apply")
        }
    }

    private func apply() async {
        emptyNote = nil
        let outcome = await model.submit(query)
        switch outcome {
        case .failed(let family):
            lastError = family
        case .semanticApplied(0):
            // Zero hits: the empty result set IS installed behind the
            // dialog — the honest「无命中」note keeps it open for a
            // rephrase (KD-6's 空命中空态). The copy is mode-keyed; the
            // CLIP arm's text is byte-identical to its pre-fulltext form.
            lastError = nil
            emptyNote = Self.emptyNoteText(for: model.mode)
        case .applied, .semanticApplied:
            lastError = nil
            onDismiss()
        }
    }

    private static func emptyNoteText(
        for mode: LibrarySearchModel.Mode
    ) -> String {
        switch mode {
        case .fullText:
            return String(
                localized: "search_fulltext_empty",
                defaultValue: "No description matches — the analyzed collection has no image whose AI caption or tags contain those words")
        default:
            return String(
                localized: "search_semantic_empty",
                defaultValue: "No semantic matches — the collection has no image close to that description")
        }
    }
}
