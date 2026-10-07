import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// LibrarySearchModel (Plan M2-3-2 T3, KD-3 / D8) — the global search
// dialog's pure-logic face: the EXIF lexical leg rides the M2-2-3
// `ExifSearchParser.parse` (zero re-parsing here), the typed errors map to
// the dialog's inline presentation, and a successful parse folds the plan
// into the SHARED `ExifSearchFilter` (grid + Inspector SEARCH FILTER move
// together — one collection state).
//
// THE FOUR ERROR FAMILIES (plan D8): the parser's two typed cases carry
// four USER-facing families — an `unrecognizedToken` is classified by its
// SHAPE (an `iso…` head = the ISO family; an `f…` numeric-looking head =
// the aperture family; anything else = the unrecognized-word family) and
// `disjointDateRanges` is the date family. The classification is a pure
// function over the token string — never a second parser run.
//
// EMPTY INPUT (the parser's `.isEmpty` 恒真 semantics): submitting an empty
// string installs the EMPTY plan — the filter's lexical leg drops out and
// the collection clears the search (the structured group arms stay).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class LibrarySearchModel {

    /// The search mode the dialog's three-segment card shows (D8: the EXIF
    /// leg is real; CLIP and the AI-description/full-text legs are the
    /// honest M2-10 placeholders).
    enum Mode: String, CaseIterable, Sendable {
        case exif
        case clip
        case fullText
    }

    /// One typed error family, mapped for the dialog's inline error line.
    enum ErrorFamily: Equatable, Sendable {
        case isoToken(String)
        case apertureToken(String)
        case dateDisjoint
        case unrecognizedToken(String)

        /// The dialog's inline copy (localized at the presentation edge).
        var message: String {
            switch self {
            case .isoToken(let token):
                return String(
                    localized: "search_error_iso",
                    defaultValue: "“\(token)” is not a valid ISO expression — try iso800 or iso:400-1600")
            case .apertureToken(let token):
                return String(
                    localized: "search_error_aperture",
                    defaultValue: "“\(token)” is not a valid aperture — try f/2.8 or f2.8")
            case .dateDisjoint:
                return String(
                    localized: "search_error_dates",
                    defaultValue: "The date terms select disjoint ranges — one date window at a time")
            case .unrecognizedToken(let token):
                return String(
                    localized: "search_error_unrecognized",
                    defaultValue: "“\(token)” was not recognized — plain words search EXIF text")
            }
        }
    }

    /// The outcome of one submit (the test observability face; the dialog
    /// reads it to keep/close the sheet).
    enum Outcome: Equatable {
        /// The plan was installed (empty input = the clearing plan).
        case applied(termCount: Int)
        /// A typed error family — the dialog shows it inline.
        case failed(ErrorFamily)
    }

    private(set) var mode: Mode = .exif
    private(set) var lastOutcome: Outcome?

    /// The grid cursor — the ONE collection state the plan folds into.
    private let grid: LibraryGridModel

    init(grid: LibraryGridModel) {
        self.grid = grid
    }

    // MARK: - Mode segment

    func select(mode newMode: Mode) {
        mode = newMode
    }

    // MARK: - The submit flow (KD-3)

    /// Parse the input and fold the plan into the shared filter. Empty
    /// input installs the empty plan (clear the lexical leg). A typed
    /// parser error maps to an inline family — never an alert, never a
    /// silent no-op.
    @discardableResult
    func submit(_ raw: String) async -> Outcome {
        guard mode == .exif else {
            // The placeholder legs never fabricate results (D8: 禁放假开关).
            lastOutcome = .failed(.unrecognizedToken(raw))
            return lastOutcome!
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let plan = try ExifSearchParser.parse(trimmed)
            try await grid.apply(
                filter: ExifSearchFilter(group: grid.filter.group, plan: plan))
            let termCount = plan.ftsTerms.count + plan.structured.count
                + (plan.dateRange == nil ? 0 : 1)
            lastOutcome = .applied(termCount: termCount)
        } catch let error as ExifSearchParserError {
            lastOutcome = .failed(Self.family(for: error))
        } catch {
            // The query face's own typed rejections ride the same surface.
            lastOutcome = .failed(.unrecognizedToken(trimmed))
        }
        return lastOutcome!
    }

    /// The typed error → presentation family (the pure classification).
    static func family(for error: ExifSearchParserError) -> ErrorFamily {
        switch error {
        case .disjointDateRanges:
            return .dateDisjoint
        case .unrecognizedToken(let token):
            let lowered = token.lowercased()
            if lowered.hasPrefix("iso") {
                return .isoToken(token)
            }
            // An aperture-shaped token: the `f` head followed by a digit
            // or the `f/` separator spelling (e.g. `f/2.8.5`, `f2,8`).
            let body = lowered.dropFirst()
            if lowered.hasPrefix("f"),
                body.first?.isNumber == true
                    || body.hasPrefix("/") {
                return .apertureToken(token)
            }
            return .unrecognizedToken(token)
        }
    }
}
