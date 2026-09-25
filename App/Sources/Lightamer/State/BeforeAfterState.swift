import Foundation
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// BeforeAfterState (Plan 09-04 T7; HIST-06) — the presentation state of the
// three before/after forms (split / snapshot-peek / hold-to-original).
//
// D-03b posture: a small isolated state object owned by the app root; it
// holds NO back-references and NEVER drives a render itself — the compare
// plane is fetched through the coordinator's override render by the view
// layer reacting to these flags (the D-X1 single-producer rule intact:
// peek/hold produce ZERO history items, asserted in BeforeAfterTests).
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class BeforeAfterState {

    /// The split-screen toggle (toolbar button).
    var splitEnabled = false

    /// The split line as a fraction of the viewport width (0...1; the
    /// AFTER image shows on the right of the line, BEFORE on the left).
    var splitFraction: Double = 0.5

    /// The snapshot-point comparison: nil = pristine (the before plane);
    /// k = the history item at index k. Peek renders ride the override
    /// path and never touch `EditorState.history`.
    var peekIndex: Int?

    /// True while the hold key (`\`, the C1 habit) is DOWN — the blit
    /// switches to the before plane for the whole viewport. A CONSTANT
    /// blit switch: zero renders on both edges (the plane is resident).
    var isHoldingOriginal = false

    /// Effective split fraction: hold forces 0 (all before) without
    /// losing the user's split position.
    var effectiveSplitFraction: Double {
        isHoldingOriginal ? 0 : splitFraction
    }

    /// The status-bar label for the current compare point.
    var comparePointLabel: String {
        if isHoldingOriginal { return String(localized: "beforeafter_hold_label") }
        if let peekIndex {
            return String(localized: "beforeafter_compare_step \(peekIndex + 1)")
        }
        return String(localized: "beforeafter_compare_pristine")
    }

    var isCompareActive: Bool { splitEnabled || isHoldingOriginal }

    /// Reset (image switch / session teardown).
    func reset() {
        splitEnabled = false
        splitFraction = 0.5
        peekIndex = nil
        isHoldingOriginal = false
    }
}
