import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// AdjustmentsPasteboard (Plan 09-04 T2; HIST-05) — the PROCESS-INTERNAL
// clipboard for copied adjustments. Memory + Codable payload (cross-session
// paste works within one process; a cross-process pasteboard is NOT v1 —
// 09-CONTEXT deferred).
//
// D-03b posture: a tiny isolated state object; the app root owns it via
// `@State` and injects it into the consumers (the menu commands + the
// partial-copy dialog). It holds NO back-references.
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class AdjustmentsPasteboard {

    /// The frozen payload (nil = nothing copied yet).
    private(set) var payload: PastePayload?

    /// Whether the last copy was a PARTIAL selection (the dialog reopens
    /// with the same checked set — a UX nicety, not semantics).
    private(set) var lastSelection: Set<PastePayload.InstanceKey>?

    var hasPayload: Bool { payload != nil }

    /// Copy (freeze) a payload; replaces any previous one.
    func copy(_ payload: PastePayload, selection: Set<PastePayload.InstanceKey>? = nil) {
        self.payload = payload
        self.lastSelection = selection
    }

    /// Consume-free read (paste does not clear the clipboard — repeated
    /// ⌘V onto different targets is the dt/C1 behavior).
    func peek() -> PastePayload? { payload }

    /// Clear (session switch teardown hygiene).
    func clear() {
        payload = nil
        lastSelection = nil
    }
}
