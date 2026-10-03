import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// AIRatingController (Plan M2-10-04 T4, KD-3, OQ-11-A) — the rating CONFIRM
// GATE orchestration (pure state + policy, no UI — the shell hosts dialogs
// when a presentation plan lands; the LabelingPromptController shape):
//
//   batch verdicts → proposals (real stars ONLY; sentinel rows never reach
//   this face — their record IS the ai_rating row) → the user applies per
//   row / applies all / checks 不再询问 → applyStars writes images.rating
//
// THE OQ-11-A RED LINE: images.rating has NO undo infrastructure (rating is
// not in the edit history), so the confirm gate is the ONLY protection —
// nothing writes until an explicit apply routes through `confirm` /
// `confirmAll` (or the don't-ask preference directs the caller to apply
// straight away). The negative test pin: present() alone leaves the column
// untouched.
//
// FEE GUARD: the batch preview hard-caps at 200 rows (a misfired bulk cull
// on a huge selection must not become a surprise bill; the cap is signed in
// DECISIONS). The remote calls themselves are made by the caller — the
// controller only sees verdicts.
// ─────────────────────────────────────────────────────────────────────────────

/// The `library.ai.ratingConfirm` preference (KD-3): `false` (default) =
/// ALWAYS confirm before writing stars; `true` = the user's 不再询问 — the
/// caller applies directly. ImportDefaults twin shape: constant key +
/// injectable suite + reset. (The inverted-polarity name is the plan's
/// pinned spelling — the bool records "don't ask me again".)
struct RatingConfirmPreferences: Sendable {

    /// The single key (the ONLY spelling).
    nonisolated static let key = "library.ai.ratingConfirm"

    let defaultsSuiteName: String?

    init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
    }

    private var suite: UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    }

    /// true = the don't-ask preference is set (apply without the dialog).
    var skipConfirmation: Bool {
        suite.bool(forKey: Self.key)
    }

    func setSkipConfirmation(_ value: Bool) {
        suite.set(value, forKey: Self.key)
    }

    func reset() {
        suite.removeObject(forKey: Self.key)
    }
}

@MainActor
@Observable
final class AIRatingController {

    /// One pending star write awaiting the user's 应用.
    struct Proposal: Identifiable, Equatable {
        let imageID: Int64
        let stars: Int
        let reasons: [String]
        var id: Int64 { imageID }
    }

    /// The batch hard cap (the fee guard; DECISIONS sign).
    static let batchLimit = 200

    private(set) var pendingProposals: [Proposal] = []
    /// Rows dropped by the cap (the caller surfaces the count).
    private(set) var droppedByCap = 0

    private let preferences: RatingConfirmPreferences
    /// The write seam (the Core `AIRatingService.applyStars` — injected so
    /// the controller stays store-free and test-drives a REAL service).
    private let applyStars: @Sendable (Int, Int64) async throws -> Void

    init(
        preferences: RatingConfirmPreferences = RatingConfirmPreferences(),
        applyStars: @escaping @Sendable (Int, Int64) async throws -> Void
    ) {
        self.preferences = preferences
        self.applyStars = applyStars
    }

    /// Whether the gate must show. false = the caller applies straight away
    /// (the 不再询问 preference).
    var confirmationBypassed: Bool {
        preferences.skipConfirmation
    }

    /// Publish the batch's real-star verdicts as proposals. Sentinel rows
    /// (stars 0) NEVER become proposals — their ai_rating row is the record.
    /// Over-cap input truncates (the fee guard) and reports the drop.
    func present(
        _ verdicts: [(imageID: Int64, verdict: AIRatingVerdict)]
    ) {
        let realStars = verdicts.filter { (1...5).contains($0.verdict.stars) }
        droppedByCap = max(0, realStars.count - Self.batchLimit)
        pendingProposals = realStars.prefix(Self.batchLimit).map {
            Proposal(
                imageID: $0.imageID, stars: $0.verdict.stars,
                reasons: $0.verdict.reasons)
        }
    }

    /// Apply ONE confirmed proposal (the single-image dialog's 应用 leg).
    /// The write fails → the proposal STAYS pending (a failed write must
    /// not silently vanish).
    func confirm(_ proposal: Proposal) async throws {
        try await applyStars(proposal.stars, proposal.imageID)
        pendingProposals.removeAll { $0.id == proposal.id }
    }

    /// Apply EVERY pending proposal (the batch 全应用 leg; also the
    /// don't-ask path the caller takes when `confirmationBypassed`).
    /// First failure throws with the remaining proposals intact.
    func confirmAll() async throws {
        for proposal in pendingProposals {
            try await applyStars(proposal.stars, proposal.imageID)
            pendingProposals.removeAll { $0.id == proposal.id }
        }
    }

    /// The neutral dismissal (nothing writes; a re-run re-proposes).
    func dismiss() {
        pendingProposals = []
        droppedByCap = 0
    }
}
