import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AnalysisTaskTypes (Plan M2-10-03 KD-3) — the Core-level VALUE faces of the
// AI background-task system (M2AI-07): the three task kinds, the cancel
// token, the typed failure face, and the tiny image-id query family the
// App-side registry (AIAnalysisRegistry) consumes.
//
// Core-level on purpose: the kinds/progress/errors are pure values the LIB
// bundle can pin without the App module, and the id queries ride the store's
// internal single-writer seam (same module) so the App side never needs its
// own SQL. The registry/orchestration itself lives App-side
// (AIAnalysisRegistry) — it is @MainActor UI-adjacent state.
//
// OQ-6-A SEMANTICS: embedding = pure derived data (auto, cancellable,
// idempotent); labeling = user-visible state (prompted). OQ-9-A: recomputeAll
// flips the single active model and re-embeds EVERY image under the new key
// while the old-key rows stay (回切 = flip active back, no recompute).
// ─────────────────────────────────────────────────────────────────────────────

/// The three AI-analysis task kinds (KD-3 verbatim shapes).
public enum AIAnalysisTaskKind: Sendable, Equatable, Hashable {
    /// Derive+store embeddings for the given image rows (the import tail's
    /// auto leg — never prompted).
    case embedding(imageIDs: [Int64])
    /// Cosine-classify the given image rows into `image_label` rows (the
    /// prompted leg; missing embeddings are embedded first — the OQ-6-A
    /// 「嵌入完成后就地打标」composition).
    case labeling(imageIDs: [Int64])
    /// Flip the active model to `newModelKey` (one batch) then re-embed the
    /// whole library under it; old-key rows are KEPT (OQ-9-A 回切 space).
    case recomputeAll(newModelKey: String)
}

/// A thread-safe cancel flag (the plan's 取消令牌). The registry hands one
/// per task; the handle's cancel face flips it and the executor observes it
/// at every per-image checkpoint. Cancellation is INCREMENTAL: whatever rows
/// already landed stay (re-runs are idempotent reconciles).
public final class AIAnalysisCancelToken: Sendable {

    private let lock = NSLock()
    private nonisolated(unsafe) var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// The typed registry failure face (the snapshot's honest error copy —
/// never a silent no-op and never a crash on the no-model/no-project path).
public enum AIAnalysisError: Error, Equatable, Sendable {
    /// No open project package.
    case storeUnavailable
    /// The inference assets are absent/broken (the fail-closed nil face).
    case engineUnavailable
    /// No active semantic model row, or the requested key has no manifest.
    case modelUnavailable
    /// The bundle label-prototypes tree is absent.
    case prototypesUnavailable
}

public enum AIAnalysisQueries {

    /// The current images-row high-water mark (the import-tail capture
    /// anchor). `nil` = the read failed — the AI legs skip that import
    /// (derived-data bookkeeping never fails an import; registry side
    /// decides on the nil).
    public static func maxImageRowID(
        in store: ProjectFileStore
    ) async throws -> Int64 {
        try await store.withHandle { handle in
            let statement = try handle.prepare("SELECT MAX(id) FROM images")
            guard try statement.step() else { return 0 }
            return statement.columnInt(0) ?? 0
        }
    }

    /// Image row ids added after `afterRowID` (the import tail's new-row set).
    public static func imageIDs(
        in store: ProjectFileStore, afterRowID: Int64
    ) async throws -> [Int64] {
        try await store.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT id FROM images WHERE id > ? ORDER BY id")
            try statement.bindInt(1, afterRowID)
            var ids: [Int64] = []
            while try statement.step() {
                if let id = statement.columnInt(0) { ids.append(id) }
            }
            return ids
        }
    }

    /// Every image row id (the OQ-9-A full-library recompute sweep input).
    public static func allImageIDs(
        in store: ProjectFileStore
    ) async throws -> [Int64] {
        try await store.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT id FROM images ORDER BY id")
            var ids: [Int64] = []
            while try statement.step() {
                if let id = statement.columnInt(0) { ids.append(id) }
            }
            return ids
        }
    }
}
