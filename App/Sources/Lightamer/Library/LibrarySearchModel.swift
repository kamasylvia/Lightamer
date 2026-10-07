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
        /// M2-10-02 (KD-5): the active semantic model / bundled assets are
        /// absent — the「语义模型未就绪」honest face (never a fake empty
        /// result).
        case modelUnavailable
        /// A semantic query failed at runtime (inference/scan rejection).
        case semanticQueryFailed
        /// M2-10-04 (KD-4): the fulltext leg has no query face — no open
        /// package assembly passed one (the honest「未就绪」face).
        case fulltextUnavailable

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
            case .modelUnavailable:
                return String(
                    localized: "search_error_model_unavailable",
                    defaultValue: "The semantic model is not ready — the bundled CLIP assets are missing or failed to load")
            case .semanticQueryFailed:
                return String(
                    localized: "search_error_semantic_failed",
                    defaultValue: "The semantic query failed — try again or rephrase")
            case .fulltextUnavailable:
                return String(
                    localized: "search_error_fulltext_unavailable",
                    defaultValue: "Full-text search is not available — open a project first")
            }
        }
    }

    /// The outcome of one submit (the test observability face; the dialog
    /// reads it to keep/close the sheet).
    enum Outcome: Equatable {
        /// The plan was installed (empty input = the clearing plan).
        case applied(termCount: Int)
        /// The semantic result set was installed (M2-10-02); zero hits
        /// keeps the dialog open with the honest「无语义匹配」note.
        case semanticApplied(hitCount: Int)
        /// A typed error family — the dialog shows it inline.
        case failed(ErrorFamily)
    }

    private(set) var mode: Mode = .exif
    private(set) var lastOutcome: Outcome?

    /// The grid cursor — the ONE collection state the plan folds into.
    private let grid: LibraryGridModel

    /// The M2-10-02 semantic read face over the OPEN package (nil in the
    /// EXIF-only tests — a CLIP submit then fails `.modelUnavailable`).
    private let semanticStore: SemanticStore?
    /// The engine supplier (the AIInferenceService seam; nil = never
    /// available). Supplied per submit so a late asset load still lands.
    private let semanticProvider: (@Sendable () async -> (any SemanticSearching)?)?

    /// The M2-10-04 fulltext query seam (KD-4: FTS MATCH → JOIN active=1 →
    /// ordered ids — the Core face is `AIDescriptionService.imageIDs`; nil =
    /// the honest `.fulltextUnavailable` family).
    private let fulltextProvider: (@Sendable (String) async throws -> [Int64])?

    init(
        grid: LibraryGridModel,
        semanticStore: SemanticStore? = nil,
        semantic: (@Sendable () async -> (any SemanticSearching)?)? = nil,
        fulltext: (@Sendable (String) async throws -> [Int64])? = nil
    ) {
        self.grid = grid
        self.semanticStore = semanticStore
        self.semanticProvider = semantic
        self.fulltextProvider = fulltext
    }

    // MARK: - Mode segment

    func select(mode newMode: Mode) {
        mode = newMode
    }

    // MARK: - The submit flow (KD-3 + M2-10-02 KD-6)

    /// Parse the input and fold the plan into the shared filter. Empty
    /// input installs the empty plan (clear the lexical leg). A typed
    /// parser error maps to an inline family — never an alert, never a
    /// silent no-op. The CLIP leg routes to `submitSemantic`; the fulltext
    /// leg (M2-10-04) routes to `submitFulltext`.
    @discardableResult
    func submit(_ raw: String) async -> Outcome {
        switch mode {
        case .exif:
            return await submitExif(raw)
        case .clip:
            return await submitSemantic(raw)
        case .fullText:
            return await submitFulltext(raw)
        }
    }

    private func submitExif(_ raw: String) async -> Outcome {
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

    /// The CLIP leg (KD-6): query → engine → hit IDs → the grid's semantic
    /// overlay (EXIF 腿同型集合过滤, hit order). Empty input clears the
    /// leg (the EXIF empty-plan symmetry). Model absence is the typed
    /// `.modelUnavailable` family — an honest state, not a fake empty set.
    private func submitSemantic(_ raw: String) async -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try? await grid.apply(semanticHits: nil)
            lastOutcome = .applied(termCount: 0)
            return lastOutcome!
        }
        guard let semanticStore, let semanticProvider else {
            lastOutcome = .failed(.modelUnavailable)
            return lastOutcome!
        }
        guard let searcher = await semanticProvider() else {
            lastOutcome = .failed(.modelUnavailable)
            return lastOutcome!
        }
        do {
            let hits = try await searcher.search(
                trimmed, limit: Self.semanticHitLimit, in: semanticStore)
            try await grid.apply(semanticHits: hits.map(\.imageID))
            lastOutcome = .semanticApplied(hitCount: hits.count)
        } catch SemanticSearchError.modelUnavailable {
            lastOutcome = .failed(.modelUnavailable)
        } catch {
            // Inference/scan rejections (dimension mismatch, cancellation,
            // runner failures) — one honest runtime family.
            lastOutcome = .failed(.semanticQueryFailed)
        }
        return lastOutcome!
    }

    /// The D-1 top-K budget (the scanner's k; the dialog presents the
    /// count card from the same number).
    static let semanticHitLimit = 256

    /// The fulltext leg (KD-4): the query rides the Core seam (FTS MATCH →
    /// JOIN active=1 → ordered ids) and folds into the grid's overlay —
    /// the CLIP leg's exact shape, rank-ordered instead of score-ordered.
    /// Empty input clears the leg; a missing query face is the honest
    /// `.fulltextUnavailable` family; a MATCH failure is the runtime family.
    private func submitFulltext(_ raw: String) async -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try? await grid.apply(semanticHits: nil)
            lastOutcome = .applied(termCount: 0)
            return lastOutcome!
        }
        guard let fulltextProvider else {
            lastOutcome = .failed(.fulltextUnavailable)
            return lastOutcome!
        }
        do {
            let hits = try await fulltextProvider(trimmed)
            try await grid.apply(semanticHits: hits)
            lastOutcome = .semanticApplied(hitCount: hits.count)
        } catch {
            lastOutcome = .failed(.semanticQueryFailed)
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
