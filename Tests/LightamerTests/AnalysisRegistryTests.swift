import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AnalysisRegistryTests (Plan M2-10-03 T2, KD-3 / M2AI-07) — the AI task
// registry over REAL `.lalb` fixtures (checker E1: the real store + the real
// ImportService import chain — no stub stores):
//
//   • embedding task round-trip: rows land in image_embedding under the
//     ACTIVE model key, progress snapshots climb monotonically to 1
//   • serial drain: two tasks run strictly one after the other (max
//     concurrency 1), FIFO order preserved
//   • cancellation is INCREMENTAL: whatever images completed keep their
//     rows, the task leaves the registry, no further embeds run
//   • recomputeAll (OQ-9-A): the active flip is one batch, the new-key rows
//     appear, the OLD-key rows survive (回切 space); a cancelled recompute
//     keeps its partial new-key set and the flipped active row
//   • labeling: missing embeddings are embedded FIRST (the OQ-6-A
//     「缺者先补」composition), then the cosine rows land via replaceLabels
//   • every absent-dependency path is TYPED and observable — no crash, no
//     silent pass (the D8 禁假开关 discipline)
//   • the import wiring: a REAL ImportService import through
//     LibraryProjectController.runImport auto-enqueues the embedding leg
//     (no prompt) and drives the labeling mode three-state
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class AnalysisRegistryTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var backgroundRegistry: BackgroundTaskRegistry!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ai-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Registry.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Registry")
        backgroundRegistry = BackgroundTaskRegistry()
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        fileStore = nil
        backgroundRegistry = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// The toy embedding the mock engine stores for every image: a 2-dim
    /// [0.6, 0.8] (unit) vector the toy prototypes rank deterministically.
    static let toyVector: [Float] = [0.6, 0.8]

    /// Three toy prototypes: "mountain" close to the toy vector (cos ≈
    /// 0.98), "beach" near-orthogonal (cos = 0.28), "sunset" opposite-ish.
    static func toyPrototypes(revision: String) -> LabelPrototypeSet {
        LabelPrototypeSet(
            revision: revision, dim: 2, prototypes: [
                LabelPrototype(label: "mountain", vector: [0.8, 0.6]),
                LabelPrototype(label: "beach", vector: [0.96, 0.28]),
                LabelPrototype(label: "sunset", vector: [-0.6, -0.8]),
            ])
    }

    private let activeKey = "toy-clip"

    /// Seed `count` images with REAL small JPEGs under Media/ (path_kind 0,
    /// project-relative — the resolve path the registry's data leg rides).
    private func seedImages(_ count: Int) async throws {
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "sample-gradient", withExtension: "jpg"))
        let media = tempDirectory.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(
            at: media, withIntermediateDirectories: true)
        for index in 1...count {
            let name = String(format: "IMG_%04d.jpg", index)
            try FileManager.default.copyItem(
                at: fixture, to: media.appendingPathComponent(name))
        }
        _ = try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare(
                "INSERT INTO images (image_path, path_kind) VALUES (?, 0)")
            for index in 1...count {
                try insert.reset()
                try insert.bindText(
                    1, "Media/" + String(format: "IMG_%04d.jpg", index))
                _ = try insert.step()
            }
            return true
        }
    }

    /// Activate the toy model row (in the fixture store).
    private func activateToyModel() async throws {
        try await Self.activateToyModel(in: fileStore)
    }

    /// Activate the toy model row (in any store — the wired fixtures use
    /// their own package).
    private static func activateToyModel(in store: ProjectFileStore) async throws {
        try await store.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO semantic_model (model_key, model_id, revision,
                    embedding_dim, image_size, prompt_config_hash, active)
                VALUES (?, 'toy/model', 'toy-rev', 2, 64, NULL, 1)
                """)
            try insert.bindText(1, "toy-clip")
            _ = try insert.step()
            return true
        }
    }

    private func embeddingRowCount(modelKey: String? = nil) async throws -> Int {
        try await fileStore.withHandle { handle in
            let statement = try handle.prepare(modelKey == nil
                ? "SELECT COUNT(*) FROM image_embedding"
                : "SELECT COUNT(*) FROM image_embedding WHERE model_key = ?")
            if let modelKey { try statement.bindText(1, modelKey) }
            _ = try statement.step()
            return Int(statement.columnInt(0) ?? 0)
        }
    }

    private func labelRowCount() async throws -> Int {
        try await fileStore.withHandle { handle in
            let statement = try handle.prepare("SELECT COUNT(*) FROM image_label")
            _ = try statement.step()
            return Int(statement.columnInt(0) ?? 0)
        }
    }

    /// The mock engine: records embed order/flight count, stores the toy
    /// vector under the CURRENTLY ACTIVE model (the production embedAndStore
    /// semantics the recompute test leans on).
    final class MockAnalysisEngine: AIAnalysisEngining, @unchecked Sendable {
        let vector: [Float]
        let delayNanoseconds: UInt64
        private let lock = NSLock()
        private(set) var embeddedIDs: [Int64] = []
        private(set) var maxInFlight = 0
        private var inFlight = 0

        init(vector: [Float], delayMilliseconds: Int = 0) {
            self.vector = vector
            self.delayNanoseconds = UInt64(delayMilliseconds) * 1_000_000
        }

        func embedAndStore(
            imageData: Data, imageID: Int64, in store: SemanticStore,
            computedTime: Int64
        ) async throws {
            recordBegin()
            // The elevated window: a concurrent drain would overlap here.
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            recordEnd(imageID)
            let model = try await store.activeModel()
            try await store.upsertEmbedding(
                imageID: imageID, modelKey: model?.modelKey ?? "unknown",
                vector: vector, computedTime: computedTime)
        }

        private func recordBegin() {
            lock.lock()
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            lock.unlock()
        }

        private func recordEnd(_ imageID: Int64) {
            lock.lock()
            embeddedIDs.append(imageID)
            inFlight -= 1
            lock.unlock()
        }
    }

    private func makeRegistry(
        engine: MockAnalysisEngine?,
        prototypes: LabelPrototypeSet? = nil,
        prototypesError: (any Error)? = nil,
        withStore: Bool = true
    ) -> AIAnalysisRegistry {
        AIAnalysisRegistry(
            backgroundRegistry: backgroundRegistry,
            storeProvider: { [weak self] in withStore ? self?.fileStore : nil },
            engineProvider: { engine },
            prototypesProvider: {
                if let prototypesError { throw prototypesError }
                return prototypes
            },
            projectDirectoryProvider: { [weak self] in
                self?.tempDirectory
            })
    }

    private func waitUntilIdle(
        _ registry: AIAnalysisRegistry, timeout: TimeInterval = 15
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !registry.isIdle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(registry.isIdle, "registry did not drain in \(timeout)s")
    }

    // MARK: - Embedding round-trip + progress

    func testEmbeddingTaskLandsRowsAndClimbsToFullProgress() async throws {
        try await seedImages(3)
        try await activateToyModel()
        let engine = MockAnalysisEngine(vector: Self.toyVector, delayMilliseconds: 40)
        let registry = makeRegistry(engine: engine)
        var fractions: [Double] = []

        let id = registry.enqueue(.embedding(imageIDs: [1, 2, 3]))
        // Sample the LIVE handle while the drain runs — the fractions must
        // climb monotonically (E3: 进度到快照 fraction).
        while !registry.isIdle {
            if let handle = backgroundRegistry.handle(id: id),
               let fraction = handle.snapshot.progress {
                if fractions.last != fraction { fractions.append(fraction) }
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try await waitUntilIdle(registry)
        let rows = try await embeddingRowCount()
        XCTAssertEqual(rows, 3)
        XCTAssertEqual(engine.embeddedIDs, [1, 2, 3])
        XCTAssertFalse(fractions.isEmpty, "no progress snapshots observed")
        for index in 1..<fractions.count {
            XCTAssertGreaterThanOrEqual(
                fractions[index], fractions[index - 1], "progress went backwards")
        }
        XCTAssertNil(registry.lastFailureCopy)
    }

    func testSerialDrainRunsTasksOneAtATimeInFIFOOrder() async throws {
        try await seedImages(5)
        try await activateToyModel()
        let engine = MockAnalysisEngine(vector: Self.toyVector, delayMilliseconds: 10)
        let registry = makeRegistry(engine: engine)
        registry.enqueue(.embedding(imageIDs: [1, 2]))
        registry.enqueue(.embedding(imageIDs: [3, 4, 5]))
        try await waitUntilIdle(registry)
        XCTAssertEqual(engine.maxInFlight, 1, "tasks overlapped")
        XCTAssertEqual(engine.embeddedIDs, [1, 2, 3, 4, 5], "FIFO broken")
        XCTAssertEqual(backgroundRegistry.count, 0, "finished tasks lingered")
    }

    // MARK: - Cancellation (incremental terminal state)

    func testCancelMidTaskKeepsCompletedRowsOnly() async throws {
        try await seedImages(8)
        try await activateToyModel()
        let engine = MockAnalysisEngine(vector: Self.toyVector, delayMilliseconds: 60)
        let registry = makeRegistry(engine: engine)
        var finishedIDs: [UUID] = []
        registry.taskDidFinish = { id, _, cancelled in
            if cancelled { finishedIDs.append(id) }
        }
        let id = registry.enqueue(.embedding(imageIDs: (1...8).map(Int64.init)))
        // Let at least two images land, then cancel.
        while engine.embeddedIDs.count < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        registry.cancel(id: id)
        try await waitUntilIdle(registry)
        let landed = engine.embeddedIDs.count
        XCTAssertLessThan(landed, 8, "cancel did not stop the drain")
        XCTAssertGreaterThanOrEqual(landed, 2)
        let hoisted = try await embeddingRowCount()
        XCTAssertEqual(hoisted, landed, "incremental rows lost")
        XCTAssertEqual(finishedIDs, [id], "the cancel terminal state did not fire")
        XCTAssertEqual(backgroundRegistry.count, 0)
    }

    // MARK: - recomputeAll (OQ-9-A)

    func testRecomputeAllFlipsActiveAndKeepsOldRows() async throws {
        try await seedImages(3)
        // The OLD model holds the pre-existing rows.
        try await activateToyModel()
        let oldEngine = MockAnalysisEngine(vector: Self.toyVector)
        let registry = makeRegistry(engine: oldEngine)
        registry.enqueue(.embedding(imageIDs: [1, 2, 3]))
        try await waitUntilIdle(registry)
        let hoisted = try await embeddingRowCount(modelKey: activeKey)
        XCTAssertEqual(hoisted, 3)

        // Recompute under a REAL catalog manifest key (compiled-in — no
        // download involved; the mock engine embeds under the active key).
        let jina = ModelAssetCatalog.jinaClipV2Int8
        let newEngine = MockAnalysisEngine(vector: [0.0, 1.0])
        let recompute = AIAnalysisRegistry(
            backgroundRegistry: backgroundRegistry,
            storeProvider: { [weak self] in self?.fileStore },
            engineProvider: { newEngine },
            prototypesProvider: { nil },
            projectDirectoryProvider: { [weak self] in self?.tempDirectory })
        recompute.enqueue(.recomputeAll(newModelKey: jina.profileID))
        try await waitUntilIdle(recompute)

        let active = try await SemanticStore(store: fileStore).activeModel()
        XCTAssertEqual(active?.modelKey, jina.profileID, "active did not flip")
        let oldRows = try await embeddingRowCount(modelKey: activeKey)
        XCTAssertEqual(oldRows, 3, "old-key rows were dropped — 回切 space violated")
        let newRows = try await embeddingRowCount(modelKey: jina.profileID)
        XCTAssertEqual(newRows, 3)
        XCTAssertNil(recompute.lastFailureCopy)
    }

    func testRecomputeCancelKeepsPartialNewRowsAndFlippedActive() async throws {
        try await seedImages(6)
        try await activateToyModel()
        // The old model carries the pre-existing rows the recompute must
        // leave untouched.
        let semantic = SemanticStore(store: fileStore)
        for id in Int64(1)...6 {
            try await semantic.upsertEmbedding(
                imageID: id, modelKey: activeKey, vector: Self.toyVector,
                computedTime: 0)
        }
        let jina = ModelAssetCatalog.jinaClipV2Int8
        let engine = MockAnalysisEngine(vector: [0.0, 1.0], delayMilliseconds: 60)
        let registry = makeRegistry(engine: engine)
        let id = registry.enqueue(.recomputeAll(newModelKey: jina.profileID))
        while engine.embeddedIDs.count < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        registry.cancel(id: id)
        try await waitUntilIdle(registry)

        let active = try await SemanticStore(store: fileStore).activeModel()
        XCTAssertEqual(active?.modelKey, jina.profileID,
                       "the flip is one batch at task start — a cancel keeps it")
        let partial = try await embeddingRowCount(modelKey: jina.profileID)
        XCTAssertGreaterThan(partial, 0)
        XCTAssertLessThan(partial, 6)
        let hoisted = try await embeddingRowCount(modelKey: activeKey)
        XCTAssertEqual(hoisted, 6)
    }

    // MARK: - Labeling (缺者先补 + cosine rows)

    func testLabelingEmbedsMissingFirstThenWritesCosineRows() async throws {
        try await seedImages(3)
        try await activateToyModel()
        // Image 1 already carries an embedding; 2 and 3 are missing.
        try await SemanticStore(store: fileStore).upsertEmbedding(
            imageID: 1, modelKey: activeKey, vector: Self.toyVector, computedTime: 0)
        let engine = MockAnalysisEngine(vector: Self.toyVector)
        let registry = makeRegistry(
            engine: engine, prototypes: Self.toyPrototypes(revision: "toy-rev"))
        registry.enqueue(.labeling(imageIDs: [1, 2, 3]))
        try await waitUntilIdle(registry)

        // Only the MISSING rows went through the engine (缺者先补).
        XCTAssertEqual(engine.embeddedIDs, [2, 3])
        let rows = try await embeddingRowCount()
        XCTAssertEqual(rows, 3)

        // The cosine rows: three labels per image, main row "mountain" (the
        // closest toy prototype), top_scores JSON on the main row only.
        let hoisted = try await labelRowCount()
        XCTAssertEqual(hoisted, 9)
        let labels = try await SemanticStore(store: fileStore).labels(for: 1)
        XCTAssertEqual(labels.first?.label, "mountain")
        XCTAssertEqual(labels.count, 3)
        XCTAssertNotNil(labels.first?.topScoresJSON)
        XCTAssertNotNil(labels.first?.margin)
        XCTAssertTrue(labels.first?.confident ?? false)
        XCTAssertNil(registry.lastFailureCopy)
    }

    // MARK: - Typed failure faces (fail-closed, observable)

    func testEngineUnavailableIsTypedAndObservable() async throws {
        try await seedImages(2)
        try await activateToyModel()
        let registry = makeRegistry(engine: nil)
        var finished = false
        registry.taskDidFinish = { _, _, _ in finished = true }
        registry.enqueue(.embedding(imageIDs: [1, 2]))
        try await waitUntilIdle(registry)
        XCTAssertTrue(finished)
        let rows = try await embeddingRowCount()
        XCTAssertEqual(rows, 0, "silent pass detected")
        XCTAssertNotNil(registry.lastFailureCopy, "the failure was silent")
    }

    func testLabelingWithoutActiveModelIsTyped() async throws {
        try await seedImages(2)
        // No semantic_model row at all.
        let engine = MockAnalysisEngine(vector: Self.toyVector)
        let registry = makeRegistry(
            engine: engine, prototypes: Self.toyPrototypes(revision: "toy-rev"))
        registry.enqueue(.labeling(imageIDs: [1, 2]))
        try await waitUntilIdle(registry)
        let labels = try await labelRowCount()
        XCTAssertEqual(labels, 0)
        XCTAssertNotNil(registry.lastFailureCopy)
        XCTAssertTrue(engine.embeddedIDs.isEmpty, "no embeds without a model")
    }

    func testPrototypeRevisionMismatchIsTyped() async throws {
        try await seedImages(2)
        try await activateToyModel() // revision "toy-rev"
        // A bundle built for a DIFFERENT revision → typed refusal.
        let wrong = try writePrototypeBundle(revision: "other-rev")
        let engine = MockAnalysisEngine(vector: Self.toyVector)
        let registry = AIAnalysisRegistry(
            backgroundRegistry: backgroundRegistry,
            storeProvider: { [weak self] in self?.fileStore },
            engineProvider: { engine },
            prototypesProvider: { [weak self] in
                try LabelPrototypeSet.load(
                    directory: try XCTUnwrap(self?.tempDirectory)
                        .appendingPathComponent(wrong.lastPathComponent),
                    expectingRevision: "toy-rev")
            },
            projectDirectoryProvider: { [weak self] in self?.tempDirectory })
        registry.enqueue(.labeling(imageIDs: [1, 2]))
        try await waitUntilIdle(registry)
        let labels = try await labelRowCount()
        XCTAssertEqual(labels, 0)
        XCTAssertTrue(engine.embeddedIDs.isEmpty)
        XCTAssertTrue(
            registry.lastFailureCopy?.contains("toy-rev") == true,
            "the mismatch copy should name the revision: \(registry.lastFailureCopy ?? "nil")")
    }

    func testNoOpenProjectIsTyped() async throws {
        let engine = MockAnalysisEngine(vector: Self.toyVector)
        let registry = makeRegistry(engine: engine, withStore: false)
        registry.enqueue(.embedding(imageIDs: [1]))
        try await waitUntilIdle(registry)
        XCTAssertNotNil(registry.lastFailureCopy)
        XCTAssertTrue(engine.embeddedIDs.isEmpty)
    }

    /// A real bundle-shaped prototype directory under the temp root.
    private func writePrototypeBundle(revision: String) throws -> URL {
        let directory = tempDirectory.appendingPathComponent(
            "label-prototypes-\(revision)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        func le(_ vector: [Float]) -> Data {
            var bytes: [UInt8] = []
            for value in vector {
                let bits = Float16(value).bitPattern
                bytes.append(UInt8(bits & 0xFF))
                bytes.append(UInt8((bits >> 8) & 0xFF))
            }
            return Data(bytes)
        }
        let set = Self.toyPrototypes(revision: revision)
        var payload = Data()
        var labels: [[String: Any]] = []
        for (index, prototype) in set.prototypes.enumerated() {
            payload.append(le(prototype.vector))
            labels.append(["label": prototype.label, "offset": index])
        }
        let index: [String: Any] = [
            "revision": revision, "dim": 2,
            "count": set.prototypes.count, "labels": labels,
        ]
        try JSONSerialization.data(withJSONObject: index)
            .write(to: directory.appendingPathComponent("prototypes.json"))
        try payload.write(to: directory.appendingPathComponent("prototypes.bin"))
        return directory
    }

    // MARK: - The import wiring (checker E1: the REAL import chain)

    /// Build a controller + registry + prompt controller wired exactly like
    /// the shell host does, over a REAL one-photo import.
    private func makeWiredFixture(
        labelingSuite: String
    ) async throws -> (LibraryProjectController, AIAnalysisRegistry,
                       LabelingPromptController, URL) {
        // The project package in its own subdirectory (project-relative
        // Media paths resolve against the package PARENT).
        let root = tempDirectory.appendingPathComponent(
            "wired-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        let packageURL = root.appendingPathComponent("Wired.lalb")

        // The source folder: two real JPEGs.
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source, withIntermediateDirectories: true)
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "sample-gradient", withExtension: "jpg"))
        try FileManager.default.copyItem(
            at: fixture, to: source.appendingPathComponent("A.jpg"))
        try FileManager.default.copyItem(
            at: fixture, to: source.appendingPathComponent("B.jpg"))

        // The real lifecycle route (createProject creates + opens + owns
        // the URL); an isolated defaults suite keeps the recent list AND the
        // import whitelist test-local (the fixture photos are JPEGs — the
        // frozen RAW default whitelist would reject them).
        let importSuite = "wired-import-" + UUID().uuidString
        ImportDefaults(defaultsSuiteName: importSuite).setWhitelist(["jpg"])
        let controller = LibraryProjectController(defaultsSuiteName: importSuite)
        try await controller.createProject(at: packageURL, name: "Wired")
        // The labeling leg needs an active model in the wired package.
        try await Self.activateToyModel(
            in: try XCTUnwrap(controller.projectStore))

        let background = BackgroundTaskRegistry()
        let engine = MockAnalysisEngine(vector: Self.toyVector)
        let registry = AIAnalysisRegistry(
            backgroundRegistry: background,
            storeProvider: { [weak controller] in controller?.projectStore },
            engineProvider: { engine },
            prototypesProvider: {
                Self.toyPrototypes(revision: "toy-rev")
            },
            projectDirectoryProvider: { [weak controller] in
                controller?.projectURL?.deletingLastPathComponent()
            })
        let prompts = LabelingPromptController(
            preferences: LabelingPreferences(defaultsSuiteName: labelingSuite))
        controller.aiAnalysis = registry
        controller.labelingPrompts = prompts
        return (controller, registry, prompts, root)
    }

    private func runWiredImport(
        _ controller: LibraryProjectController, root: URL
    ) async throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        await controller.runImport(
            folder: source,
            choice: ImportModeChoice(mode: .copy, remember: false))
    }

    private func embeddedImageIDsInWiredStore(
        _ controller: LibraryProjectController
    ) async throws -> [Int64] {
        guard let store = controller.projectStore else { return [] }
        return try await store.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT image_id FROM image_embedding ORDER BY image_id")
            var ids: [Int64] = []
            while try statement.step() {
                if let id = statement.columnInt(0) { ids.append(id) }
            }
            return ids
        }
    }

    func testImportTailAutoEmbedsAndAsksInAskMode() async throws {
        let suite = "ai-registry-ask-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let (controller, registry, prompts, root) =
            try await makeWiredFixture(labelingSuite: suite)
        try await runWiredImport(controller, root: root)
        try await waitUntilIdle(registry)

        // The AUTO leg ran without any prompt: both new rows embedded.
        let embedded = try await embeddedImageIDsInWiredStore(controller)
        XCTAssertEqual(embedded, [1, 2])
        // ASK mode published the prompt for the new-row set…
        let prompt = try XCTUnwrap(prompts.pendingPrompt)
        XCTAssertEqual(prompt.imageCount, 2)
        // …and labeling stays OFF until the user answers.
        let labelsBefore = try await labelRowCountViaStore(controller)
        XCTAssertEqual(labelsBefore, 0)
        // 「分析」→ the labeling task lands rows for both images.
        let ids = try XCTUnwrap(prompts.accept(remember: false))
        registry.enqueue(.labeling(imageIDs: ids))
        try await waitUntilIdle(registry)
        let labelsAfter = try await labelRowCountViaStore(controller)
        XCTAssertEqual(labelsAfter, 6)
        XCTAssertNil(prompts.pendingPrompt)
    }

    func testImportTailAlwaysModeSkipsTheAsk() async throws {
        let suite = "ai-registry-always-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let (controller, registry, prompts, root) =
            try await makeWiredFixture(labelingSuite: suite)
        let preferences = LabelingPreferences(defaultsSuiteName: suite)
        preferences.store(.always)
        try await runWiredImport(controller, root: root)
        try await waitUntilIdle(registry)
        let embedded = try await embeddedImageIDsInWiredStore(controller)
        XCTAssertEqual(embedded, [1, 2])
        let labelCount = try await labelRowCountViaStore(controller)
        XCTAssertEqual(labelCount, 6, "always mode must label right away")
        XCTAssertNil(prompts.pendingPrompt, "always mode must not ask")
    }

    func testImportTailNeverModeRunsEmbeddingOnly() async throws {
        let suite = "ai-registry-never-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let (controller, registry, prompts, root) =
            try await makeWiredFixture(labelingSuite: suite)
        LabelingPreferences(defaultsSuiteName: suite).store(.never)
        try await runWiredImport(controller, root: root)
        try await waitUntilIdle(registry)
        // The auto embedding leg is INDEPENDENT of the labeling preference.
        let embedded = try await embeddedImageIDsInWiredStore(controller)
        XCTAssertEqual(embedded, [1, 2])
        let hoisted = try await labelRowCountViaStore(controller)
        XCTAssertEqual(hoisted, 0)
        XCTAssertNil(prompts.pendingPrompt)
    }

    private func labelRowCountViaStore(
        _ controller: LibraryProjectController
    ) async throws -> Int {
        guard let store = controller.projectStore else { return -1 }
        return try await store.withHandle { handle in
            let statement = try handle.prepare("SELECT COUNT(*) FROM image_label")
            _ = try statement.step()
            return Int(statement.columnInt(0) ?? 0)
        }
    }
}
