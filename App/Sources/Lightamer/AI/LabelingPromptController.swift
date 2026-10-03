import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// LabelingPromptController (Plan M2-10-03 KD-3 / OQ-6-A) — the labeling ask
// orchestration: the Alcedo `SemanticGenerationDialog`-shaped prompt
// (「用 AI 分析图片内容？」+ yes/no + "Remember my choice"), resolved through
// the `library.ai.labelingMode` three-state preference.
//
// THE OQ-6-A RED LINE: labeling WRITES user-visible state → it must ask
// (mode `.ask`, the default). `.always` skips the ask and enqueues directly;
// `.never` does nothing. The remember write-back lands ONLY on an explicit
// remember checkbox (the ImportDefaults storeChoice semantics: a single-shot
// answer persists nothing).
//
// The controller is pure state + policy (no UI): the shell hosts the sheet
// (LabelingAskDialog) and routes the buttons back through accept/decline.
// ─────────────────────────────────────────────────────────────────────────────

/// What the import tail should do about labeling for a fresh import.
enum LabelingIntent: Equatable {
    /// Enqueue `.labeling` right away (mode `.always`).
    case enqueueNow
    /// A prompt was published — the sheet drives the rest (mode `.ask`).
    case ask
}

@MainActor
@Observable
final class LabelingPromptController {

    /// The sheet item: one pending labeling ask (the import's new-row set).
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let imageIDs: [Int64]
        var imageCount: Int { imageIDs.count }
    }

    /// The live prompt (nil = nothing pending; the sheet's item binding).
    private(set) var pendingPrompt: Request?

    private let preferences: LabelingPreferences

    init(preferences: LabelingPreferences = LabelingPreferences()) {
        self.preferences = preferences
    }

    /// The import-tail route (KD-3): mode three-state. `.ask` returns `.ask`
    /// WITHOUT publishing — the tail presents the prompt itself, one beat
    /// after the progress close (the plan's 弹询时机 pin).
    func intentForNewImages(_ imageIDs: [Int64]) -> LabelingIntent? {
        switch preferences.mode {
        case .never:
            return nil
        case .always:
            return .enqueueNow
        case .ask:
            return .ask
        }
    }

    /// Test seam: publish a prompt directly.
    func presentPrompt(_ imageIDs: [Int64]) {
        pendingPrompt = Request(imageIDs: imageIDs)
    }

    /// The neutral dismissal (the sheet's swipe-away route — no preference
    /// write; the next import asks again).
    func dismissPrompt() {
        pendingPrompt = nil
    }

    /// The 「分析」 leg: clears the prompt, persists `.always` when remembered,
    /// and hands back the ids to enqueue `.labeling` for.
    @discardableResult
    func accept(remember: Bool) -> [Int64]? {
        guard let prompt = pendingPrompt else { return nil }
        pendingPrompt = nil
        if remember { preferences.store(.always) }
        return prompt.imageIDs
    }

    /// The 「不分析」 leg: clears the prompt, persists `.never` when remembered.
    func decline(remember: Bool) {
        pendingPrompt = nil
        if remember { preferences.store(.never) }
    }
}
