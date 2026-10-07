import Foundation
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundTaskHosting (Plan M2-3-1 T6, KD-7 / M2UIW-06) — the THREE-LEG
// background-task protocol, delivered ONCE (the CONTEXT Specific Ideas
// anti-pattern: three legs must not grow three registry implementations):
//
//   • import leg  — THIS plan (ImportTaskAdapter over the M2-2-2
//                   ImportProgress snapshots; controller untouched — the
//                   adapter READS `importProgress` and transits cancel).
//   • export leg  — M2-9 consumes (ExportQueue's four states map onto the
//                   same handle).
//   • AI leg      — M2-10 consumes.
//
// The protocol carries ONLY progress + cancel (KD-7: no leg-specific fields
// — a leg that needs more evolves the protocol THEN, not speculatively).
//
// ISOLATION: the handle protocol is @MainActor (Sendable by isolation) —
// progress snapshots arrive on background queues and hop to the main actor
// through the adapter; the registry and both presentation faces (bar +
// dialog) are main-thread state by nature.
// ─────────────────────────────────────────────────────────────────────────────

/// One task's progress face: a 0…1 fraction, or nil = indeterminate (the
/// scanning phase before a total is known). `detail` is the per-file stage
/// copy ("12 of 120 — failed 1").
struct BackgroundTaskSnapshot: Sendable, Equatable {
    /// The completion fraction 0…1; nil = indeterminate.
    var progress: Double?
    /// The human-readable stage copy (already localized by the producer).
    var detail: String

    var isIndeterminate: Bool { progress == nil }

    init(progress: Double?, detail: String) {
        self.progress = progress
        self.detail = detail
    }

    static func indeterminate(_ detail: String) -> Self {
        Self(progress: nil, detail: detail)
    }

    static func fraction(_ value: Double, _ detail: String) -> Self {
        Self(progress: min(max(value, 0), 1), detail: detail)
    }
}

/// One cancellable background task as the registry stores it. Conformers are
/// @MainActor @Observable classes: the snapshot mutation IS the UI update.
@MainActor
protocol BackgroundTaskHandle: AnyObject {
    /// Stable task identity.
    var id: UUID { get }
    /// The task title (localized; the bar/dialog row headline).
    var title: String { get }
    /// The live progress snapshot (written through the registry's update).
    var snapshot: BackgroundTaskSnapshot { get set }
    /// The cancel route (transit to the owning leg's cancel face).
    func cancel() async
}

/// The ONE background-task registry (M2UIW-06): both presentation faces (the
/// bottom bar AND the task dialog) render from THIS — the dual-presentation
/// same-source guarantee by construction. Completion removes the task;
/// cancellation routes to the handle and removes it.
@MainActor
@Observable
final class BackgroundTaskRegistry {

    /// The live tasks in registration order (the bar's stable row order).
    private(set) var handles: [any BackgroundTaskHandle] = []

    var count: Int { handles.count }

    func register(_ handle: any BackgroundTaskHandle) {
        guard !handles.contains(where: { $0.id == handle.id }) else { return }
        handles.append(handle)
    }

    /// Push a snapshot into the stored handle (the adapter's progress route).
    func update(id: UUID, snapshot: BackgroundTaskSnapshot) {
        guard let handle = handles.first(where: { $0.id == id }) else { return }
        handle.snapshot = snapshot
    }

    /// The task completed — it leaves the registry (and every face).
    func finish(id: UUID) {
        handles.removeAll { $0.id == id }
    }

    /// Cancel the task through its own route, then remove it.
    func cancel(id: UUID) async {
        guard let handle = handles.first(where: { $0.id == id }) else { return }
        await handle.cancel()
        finish(id: id)
    }

    /// Cancel everything (window teardown / quit faces).
    func cancelAll() async {
        for handle in handles {
            await handle.cancel()
        }
        handles.removeAll()
    }

    /// The handle lookup (the bar/dialog helpers).
    func handle(id: UUID) -> (any BackgroundTaskHandle)? {
        handles.first { $0.id == id }
    }
}
