import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// LensProfileBrowser (Plan LENS-02 T4, D-LENS-2 v1 face / X6 §4) — the
// profile database browser replacing the retired Apply/Clear buttons.
//
// The MODEL is the testable pure face (scoring/ordering/selection are
// here); the VIEW is a thin shell (search field + candidate list + the
// selection action) — body never runs the full-library scoring (it
// caches into @State, debounced off the body path).
//
// Semantics (D-LENS-4 continuation): the 40 word-overlap tier stays
// VISIBLE as a low-confidence annotation but never auto-selects; the
// selection commits ONE discrete edit (source = .lensfun + the picked
// model as lensKey — the resolved coefficients still ride the LENS-01
// memo path; the durable snapshot is LENS-04 T1's scope, this file
// deliberately does NOT write it).
//
// DETECTED CONFIRMATION (D-LENS-2 v1 face owner, review M2): on a
// document whose embedded geometry is DETECTED, a browser selection
// raises the confirmation copy — the source flips ONLY after the user
// confirms; an unconfirmed selection never touches params.
// ─────────────────────────────────────────────────────────────────────────

/// One scored candidate row (the model's output face).
struct LensProfileCandidate: Equatable, Identifiable, Sendable {
    let maker: String
    let model: String
    let score: Int
    /// True = the 40-tier (word-overlap) band — visible, annotated
    /// low-confidence, never auto-selected.
    let lowConfidence: Bool

    var id: String { maker + "\u{1F}" + model }
}

/// The pure model (static namespace — the App-bundle tests pin every face).
enum LensProfileBrowserModel {

    /// The confidence tier boundary (the auto-apply threshold — single
    /// source with the IOP side).
    static let confidenceThreshold = 60

    /// Order + annotate the scored rows (the store returns UNSORTED
    /// score>0 rows): score desc, then maker/model asc; the <60 band is
    /// the low-confidence annotation (D-LENS-4 continuation — visible,
    /// never auto-selected).
    static func candidates(rows: [LensCandidateRow]) -> [LensProfileCandidate] {
        rows
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.maker != b.maker { return a.maker < b.maker }
                return a.model < b.model
            }
            .map { row in
                LensProfileCandidate(
                    maker: row.maker,
                    model: row.model,
                    score: row.score,
                    lowConfidence: row.score < confidenceThreshold)
            }
    }

    /// The selection commit face: the base params with source = .lensfun
    /// and the picked model as the lens key (everything else rides).
    static func selectedParams(base: LensModule.Params, candidate: LensProfileCandidate) -> LensModule.Params {
        var p = base
        p.source = .lensfun
        p.lensKey = candidate.model
        return p
    }

    /// The clear-to-manual face (the retired Clear button's surviving
    /// arm): drops the lensfun source, keeps every stored value.
    static func clearedParams(base: LensModule.Params) -> LensModule.Params {
        var p = base
        p.source = .manual
        return p
    }

    /// The detected-confirmation gate (D-LENS-2 v1 face): ONLY the
    /// .detected judgment requires confirmation before a selection lands.
    static func needsConfirmation(embedded: EmbeddedGeometryState?) -> Bool {
        embedded == .detected
    }

    /// The display name (maker + model, maker omitted when empty).
    static func displayName(_ c: LensProfileCandidate) -> String {
        c.maker.isEmpty ? c.model : c.maker + " " + c.model
    }
}

/// The thin view shell (the LensPanelView §4 section body).
struct LensProfileBrowserView: View {
    let params: LensModule.Params
    let edit: InspectorEditSession
    /// The selection callback (the panel owns the confirmation face —
    /// detected documents route through the alert first).
    let onSelect: (LensProfileCandidate) -> Void

    @State private var search: String = ""
    @State private var candidates: [LensProfileCandidate] = []
    @State private var scoring = false

    var body: some View {
        TextField(
            String(localized: "panel_lens_browser_search_placeholder"),
            text: $search
        )
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("inspector.lens.browserSearch")
        .onSubmit { rescore() }

        if scoring {
            Text(String(localized: "panel_lens_browser_scoring"))
                .font(.caption2)
                .foregroundStyle(LightamerColors.textTertiary)
        } else if candidates.isEmpty {
            Text(String(localized: search.isEmpty
                ? "panel_lens_browser_empty"
                : "panel_lens_browser_no_match"))
                .font(.caption2)
                .foregroundStyle(LightamerColors.textTertiary)
                .accessibilityIdentifier("inspector.lens.browserEmpty")
        } else {
            ForEach(candidates.prefix(30)) { c in
                Button {
                    onSelect(c)
                } label: {
                    HStack {
                        Text(verbatim: LensProfileBrowserModel.displayName(c))
                            .font(.caption)
                        Spacer()
                        if c.lowConfidence {
                            Text(String(localized: "panel_lens_browser_low_confidence"))
                                .font(.caption2)
                                .foregroundStyle(LightamerColors.textTertiary)
                        }
                        Text(verbatim: "\(c.score)")
                            .font(.caption2)
                            .foregroundStyle(LightamerColors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inspector.lens.browserCandidate.\(c.id)")
            }
            if candidates.count > 30 {
                Text(String(localized: "panel_lens_browser_truncated"))
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textTertiary)
            }
        }
    }

    /// The debounced rescore (off the body path; 150ms debounce).
    private func rescore() {
        scoring = !search.isEmpty
        Task {
            if !search.isEmpty {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            let term = search
            let raw = LensfunStore.candidateRows(search: term) ?? []
            guard term == search else { return }
            candidates = LensProfileBrowserModel.candidates(rows: raw)
            scoring = false
        }
    }
}
