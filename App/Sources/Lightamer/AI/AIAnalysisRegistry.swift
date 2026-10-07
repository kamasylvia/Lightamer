import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// AIAnalysisRegistry (Plan M2-10-03 KD-3) — the M2AI-07 AI leg of the
// background-task system: the three task kinds (embedding / labeling /
// recomputeAll) run through a SERIAL utility-priority queue; every task is a
// `BackgroundTaskHandle` conformer registered into the SHELL's existing
// BackgroundTaskRegistry (the bar/dialog render AI rows with ZERO new
// presentation faces — the M2UIW-06 aggregate discipline).
//
// M2AI-07「分析期间可继续工作」mechanics:
//   • the queue NEVER blocks the main thread — file IO/decode/embed ride the
//     engine actor + background hops; the MainActor work between images is
//     bookkeeping only, separated by `Task.yield()`;
//   • utility priority (below user interaction) for the whole drain;
//   • cancellation is per-task via the token, observed at EVERY per-image
//     checkpoint; cancellation is INCREMENTAL — committed rows stay (the
//     re-run reconcile is idempotent: embedding upserts, labeling
//     whole-group replaces).
//
// FAIL-CLOSED (the D8 禁假开关 discipline): a missing store/engine/model/
// prototypes turns the task into a typed failure — the handle shows the
// honest error copy, then the task leaves the registry. Never a silent
// empty pass, never a crash.
//
// THE ENGINE SEAM (KD-5 lineage): `AIAnalysisEngining` is the narrow face
// the registry consumes (embedAndStore over the store). The production
// conformer is `SemanticEngine` (retro-conformed below); tests inject mocks.
// ─────────────────────────────────────────────────────────────────────────────

/// The embedding face the registry consumes (one conformer per execution
/// world — the M2-10-05 worker swap re-points the provider, not this file).
public protocol AIAnalysisEngining: Sendable {
    func embedAndStore(
        imageData: Data, imageID: Int64, in store: SemanticStore,
        computedTime: Int64
    ) async throws
}

/// Retro-conformance: the in-process engine IS the analysis engine.
extension SemanticEngine: AIAnalysisEngining {}

@MainActor
@Observable
final class AIAnalysisRegistry {

    /// One registered task as the bar/dialog see it.
    @Observable
    final class AnalysisTaskHandle: BackgroundTaskHandle {

        let id: UUID
        let title: String
        var snapshot: BackgroundTaskSnapshot

        /// The registry-side cancel transit (MainActor hop; the executor
        /// observes the token at the next per-image checkpoint).
        private let onCancelRoute: @Sendable () -> Void

        init(
            id: UUID, title: String,
            onCancel: @escaping @Sendable () -> Void
        ) {
            self.id = id
            self.title = title
            self.snapshot = .indeterminate(
                String(localized: "tasks_ai_waiting",
                       defaultValue: "Pending…"))
            self.onCancelRoute = onCancel
        }

        func apply(_ snapshot: BackgroundTaskSnapshot) {
            self.snapshot = snapshot
        }

        func cancel() async {
            onCancelRoute()
        }
    }

    private struct QueuedTask {
        let kind: AIAnalysisTaskKind
        let handle: AnalysisTaskHandle
        let token: AIAnalysisCancelToken
    }

    // MARK: - Dependencies (injected; tests drive every seam)

    private let backgroundRegistry: BackgroundTaskRegistry
    private let storeProvider: @MainActor () -> ProjectFileStore?
    private let engineProvider: @MainActor () async -> (any AIAnalysisEngining)?
    private let prototypesProvider: @MainActor () async throws -> LabelPrototypeSet?
    private let projectDirectoryProvider: @MainActor () -> URL?
    private let clock: @Sendable () -> Int64

    /// Test observability (the E3 可观测 face): fired on the MainActor after
    /// each task leaves the queue (cancelled or completed).
    var taskDidFinish: ((UUID, AIAnalysisTaskKind, Bool) -> Void)?

    /// The typed failure copy of the most recent failed task (nil = none
    /// failed yet) — the fail-closed face is OBSERVABLE, not silent.
    private(set) var lastFailureCopy: String?

    // MARK: - Queue state (MainActor)

    private var queue: [QueuedTask] = []
    private var runner: Task<Void, Never>?

    /// True while no task is queued or executing (the test drain face).
    var isIdle: Bool { runner == nil }

    init(
        backgroundRegistry: BackgroundTaskRegistry,
        storeProvider: @escaping @MainActor () -> ProjectFileStore?,
        engineProvider: @escaping @MainActor () async -> (any AIAnalysisEngining)?,
        prototypesProvider: @escaping @MainActor () async throws -> LabelPrototypeSet?,
        projectDirectoryProvider: @escaping @MainActor () -> URL?,
        clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970) }
    ) {
        self.backgroundRegistry = backgroundRegistry
        self.storeProvider = storeProvider
        self.engineProvider = engineProvider
        self.prototypesProvider = prototypesProvider
        self.projectDirectoryProvider = projectDirectoryProvider
        self.clock = clock
    }

    // MARK: - Enqueue / cancel (the KD-3 public face)

    /// Register one task: the handle lands in the shell's aggregate registry
    /// (bar + dialog) immediately; the serial utility drain picks it up.
    @discardableResult
    func enqueue(_ kind: AIAnalysisTaskKind) -> UUID {
        let id = UUID()
        let token = AIAnalysisCancelToken()
        let handle = AnalysisTaskHandle(
            id: id, title: Self.title(for: kind)) { [weak self] in
                // Off-main cancel route: hop to the MainActor for the queue
                // surgery / token flip (never touch isolated state here).
                Task { @MainActor [weak self] in
                    self?.userRequestedCancel(id: id)
                }
            }
        tokenByID[id] = token
        queue.append(QueuedTask(kind: kind, handle: handle, token: token))
        backgroundRegistry.register(handle)
        startRunnerIfNeeded()
        return id
    }

    /// Programmatic cancel (the tests' face; the bar routes through the
    /// handle's cancel into the same token).
    func cancel(id: UUID) {
        userRequestedCancel(id: id)
    }

    /// queued → drop instantly; running/unknown → flip the token (the
    /// executor stops at the next checkpoint and the drain finishes it).
    private func userRequestedCancel(id: UUID) {
        if let index = queue.firstIndex(where: { $0.handle.id == id }) {
            let task = queue.remove(at: index)
            task.token.cancel()
            tokenByID[id] = nil
            backgroundRegistry.finish(id: id)
            taskDidFinish?(id, task.kind, true)
            return
        }
        tokenByID[id]?.cancel()
    }

    private var tokenByID: [UUID: AIAnalysisCancelToken] = [:]

    nonisolated private static func title(for kind: AIAnalysisTaskKind) -> String {
        switch kind {
        case .embedding:
            String(localized: "tasks_ai_embedding",
                   defaultValue: "Embedding photos…")
        case .labeling:
            String(localized: "tasks_ai_labeling",
                   defaultValue: "Labeling photos…")
        case .recomputeAll:
            String(localized: "tasks_ai_recompute",
                   defaultValue: "Recomputing library embeddings…")
        }
    }

    // MARK: - The serial utility drain (M2AI-07)

    private func startRunnerIfNeeded() {
        guard runner == nil else { return }
        runner = Task(priority: .utility) { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            let task = queue[0]
            let cancelled = await execute(task)
            // Fire/finish ONLY when the task is still ours to finish — a
            // userRequestedCancel that found it in the queue already removed,
            // finished and fired it (the exactly-once terminal state).
            if let index = queue.firstIndex(where: { $0.handle.id == task.handle.id }) {
                queue.remove(at: index)
                tokenByID[task.handle.id] = nil
                backgroundRegistry.finish(id: task.handle.id)
                taskDidFinish?(task.handle.id, task.kind, cancelled)
            }
        }
        runner = nil
    }

    /// Execute one task; returns whether it ended through the cancel
    /// checkpoint. All typed failures land as the handle's error snapshot
    /// (fail-closed, then the task leaves).
    private func execute(_ task: QueuedTask) async -> Bool {
        guard let fileStore = storeProvider() else {
            return fail(task, AIAnalysisError.storeUnavailable)
        }
        let store = SemanticStore(store: fileStore)
        do {
            switch task.kind {
            case .embedding(let ids):
                return try await runEmbedding(
                    ids, store: store, fileStore: fileStore,
                    task: task)
            case .labeling(let ids):
                return try await runLabeling(
                    ids, store: store, fileStore: fileStore, task: task)
            case .recomputeAll(let newModelKey):
                return try await runRecomputeAll(
                    newModelKey, store: store, fileStore: fileStore, task: task)
            }
        } catch {
            return fail(task, error)
        }
    }

    // MARK: - Task bodies

    private func runEmbedding(
        _ ids: [Int64], store: SemanticStore, fileStore: ProjectFileStore,
        task: QueuedTask
    ) async throws -> Bool {
        guard let engine = await engineProvider() else {
            throw AIAnalysisError.engineUnavailable
        }
        let total = ids.count
        for (index, id) in ids.enumerated() {
            if task.token.isCancelled { return true }
            if let data = await imageData(id: id, fileStore: fileStore) {
                try await engine.embedAndStore(
                    imageData: data, imageID: id, in: store,
                    computedTime: clock())
            }
            publish(task, done: index + 1, total: total)
            await Task.yield()
        }
        return false
    }

    private func runLabeling(
        _ ids: [Int64], store: SemanticStore, fileStore: ProjectFileStore,
        task: QueuedTask
    ) async throws -> Bool {
        guard let model = try await store.activeModel() else {
            throw AIAnalysisError.modelUnavailable
        }
        let prototypes = try await prototypesProvider()
        guard let prototypes else {
            throw AIAnalysisError.prototypesUnavailable
        }
        guard let engine = await engineProvider() else {
            throw AIAnalysisError.engineUnavailable
        }
        // Pass 0: who already carries an embedding under the active model?
        let table = try await store.loadScanTable(modelKey: model.modelKey)
        let present = Set(table.rowIDs)
        let missing = ids.filter { !present.contains($0) }
        let total = ids.count + missing.count
        var done = 0

        // Pass 1 (the OQ-6-A 「缺者先补」leg): embed the missing rows first —
        // the same auto embedding leg the import tail rides.
        for id in missing {
            if task.token.isCancelled { return true }
            if let data = await imageData(id: id, fileStore: fileStore) {
                try await engine.embedAndStore(
                    imageData: data, imageID: id, in: store,
                    computedTime: clock())
            }
            done += 1
            publish(task, done: done, total: total)
            await Task.yield()
        }

        // Pass 2: ONE scan-table load for the whole classify sweep.
        let reloaded = try await store.loadScanTable(modelKey: model.modelKey)
        let dim = model.embeddingDim
        let offsetByID = Dictionary(
            uniqueKeysWithValues: reloaded.rowIDs.enumerated().map { ($1, $0) })
        for id in ids {
            if task.token.isCancelled { return true }
            if let offset = offsetByID[id] {
                let start = offset * dim * 2
                let end = start + dim * 2
                guard end <= reloaded.fp16.count else { continue }
                let vector = FP16Coding.unpack(
                    reloaded.fp16.subdata(in: start..<end))
                let scores = LabelEngine.classify(
                    image: vector, prototypes: prototypes.prototypes)
                try await store.replaceLabels(
                    imageID: id, modelKey: model.modelKey,
                    rows: LabelEngine.labelRows(from: scores))
            }
            done += 1
            publish(task, done: done, total: total)
            await Task.yield()
        }
        return false
    }

    private func runRecomputeAll(
        _ newModelKey: String, store: SemanticStore,
        fileStore: ProjectFileStore, task: QueuedTask
    ) async throws -> Bool {
        guard let manifest = ModelAssetCatalog.manifest(for: newModelKey),
            let dim = manifest.embeddingDim
        else { throw AIAnalysisError.modelUnavailable }
        // OQ-9-A: the flip is ONE batch (the DB partial-unique index is the
        // backstop); the old-key rows stay put — 回切 = flip active back.
        try await store.upsertModel(SemanticStore.ModelRecord(
            modelKey: manifest.profileID, modelID: manifest.modelID,
            revision: manifest.revision, embeddingDim: dim,
            imageSize: manifest.inputSize, active: true))
        guard let engine = await engineProvider() else {
            throw AIAnalysisError.engineUnavailable
        }
        let ids = try await AIAnalysisQueries.allImageIDs(in: fileStore)
        for (index, id) in ids.enumerated() {
            if task.token.isCancelled { return true }
            if let data = await imageData(id: id, fileStore: fileStore) {
                try await engine.embedAndStore(
                    imageData: data, imageID: id, in: store,
                    computedTime: clock())
            }
            publish(task, done: index + 1, total: ids.count)
            await Task.yield()
        }
        return false
    }

    // MARK: - Shared legs

    /// Resolve one image row to its file bytes (LibraryStore row read → the
    /// ImageLinker three-form resolve → Data). `nil` = a stale link or an
    /// unreadable file — that image is SKIPPED (the task keeps moving;
    /// re-runs and relinks cover it later).
    private func imageData(
        id: Int64, fileStore: ProjectFileStore
    ) async -> Data? {
        guard let directory = projectDirectoryProvider() else { return nil }
        let library = LibraryStore(store: fileStore)
        guard let image = try? await library.image(id: id),
            let url = Self.resolveURL(
                imagePath: image.imagePath, pathKind: image.pathKind,
                volumeUUID: image.volumeUUID, projectDirectory: directory)
        else { return nil }
        return try? Data(contentsOf: url)
    }

    nonisolated private static func resolveURL(
        imagePath: String, pathKind: LibrarySchema.PathKind,
        volumeUUID: String?, projectDirectory: URL
    ) -> URL? {
        guard case .resolved(let url) = ImageLinker.resolve(
            imagePath: imagePath, pathKind: pathKind,
            volumeUUID: volumeUUID, projectDirectory: projectDirectory)
        else { return nil }
        return url
    }

    private func publish(
        _ task: QueuedTask, done: Int, total: Int
    ) {
        let fraction = total > 0 ? Double(done) / Double(total) : nil
        task.handle.apply(.fraction(
            fraction ?? 1,
            String(localized: "tasks_ai_counts",
                   defaultValue: "\(done) of \(total)")))
    }

    /// The typed failure face: the honest error copy lands on the handle,
    /// then the task leaves the registry (fail-closed, no retry loop).
    private func fail(_ task: QueuedTask, _ error: Error) -> Bool {
        let copy = Self.errorCopy(for: error)
        lastFailureCopy = copy
        task.handle.apply(.indeterminate(copy))
        return false
    }

    nonisolated private static func errorCopy(for error: Error) -> String {
        switch error as? AIAnalysisError {
        case .storeUnavailable:
            String(localized: "tasks_ai_error_no_project",
                   defaultValue: "No open project — analysis skipped.")
        case .engineUnavailable:
            String(localized: "tasks_ai_error_no_model_assets",
                   defaultValue: "AI model assets unavailable — analysis skipped.")
        case .modelUnavailable:
            String(localized: "tasks_ai_error_no_active_model",
                   defaultValue: "No active semantic model — analysis skipped.")
        case .prototypesUnavailable:
            String(localized: "tasks_ai_error_no_prototypes",
                   defaultValue: "Label prototypes unavailable — analysis skipped.")
        case nil:
            switch error as? LabelPrototypeError {
            case .prototypeRevisionMismatch(let expected, let actual):
                String(localized: "tasks_ai_error_revision_mismatch",
                       defaultValue: "Label prototypes mismatch the model (\(actual) ≠ \(expected)).")
            case .prototypeIndexCorrupt, .prototypesUnavailable, nil:
                String(localized: "tasks_ai_error_generic",
                       defaultValue: "Analysis failed — \(error.localizedDescription).")
            }
        }
    }
}
