import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// SemanticStoreTests (Plan M2-10-02 T2, KD-2) — the four-domain read/write
// face over a REAL `.lalb` fixture (checker E1: the real file chain, no
// in-memory stubs):
//
//   • semantic_model: upsert + the single-active flip (DB partial-unique
//     backstop already pinned in LibrarySchemaTests)
//   • image_embedding: fp16 round-trip inside the representation error
//     band, scoped deletes, the scan-rows load
//   • image_label: whole-group reconcile idempotency
//   • label_query: idempotent factory seed
//   • ai_understanding: the UNIQUE(image,task) reconcile + sibling active
//     flip + the FTS trigger mirror (write / re-write / delete → MATCH)
//   • ai_rating: append-only + latest-per-image
//   • CASCADE: the image row delete annihilates all four domains
//     (checker E4: asserted at ROW COUNTS, not presence)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SemanticStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: SemanticStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("semantic-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Semantic.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Semantic")
        store = SemanticStore(store: fileStore)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        fileStore = nil
        try await super.tearDown()
    }

    /// Seed `count` images; returns the rowids (1…count).
    @discardableResult
    private func seedImages(_ count: Int64) async throws -> [Int64] {
        try await fileStore.withWriteBatch { handle -> [Int64] in
            let insert = try handle.prepare(
                "INSERT INTO images (image_path, path_kind) VALUES (?, 0)")
            var ids: [Int64] = []
            for index in 1...count {
                try insert.reset()
                try insert.bindText(1, "Media/IMG_\(index).ARW")
                _ = try insert.step()
                ids.append(handle.lastInsertRowID())
            }
            return ids
        }
    }

    private func seededVector(_ seed: Int, dim: Int = 16) -> [Float] {
        var vector = (0..<dim).map { index in
            Float(sin(Double(seed * 7 + index) * 0.7))
        }
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        for index in vector.indices { vector[index] /= norm }
        return vector
    }

    private let modelKey = "chinese-clip-vitb16-int8"

    // MARK: - semantic_model

    func testModelUpsertFlipsSingleActive() async throws {
        let first = SemanticStore.ModelRecord(
            modelKey: "a-profile", modelID: "org/a", revision: "r1",
            embeddingDim: 512, imageSize: 224, active: true)
        try await store.upsertModel(first)
        var active = try await store.activeModel()
        XCTAssertEqual(active?.modelKey, "a-profile")

        // A second activation demotes the first (single batch).
        let second = SemanticStore.ModelRecord(
            modelKey: "b-profile", modelID: "org/b", revision: "r2",
            embeddingDim: 768, imageSize: 512, active: true)
        try await store.upsertModel(second)
        active = try await store.activeModel()
        XCTAssertEqual(active?.modelKey, "b-profile")
        XCTAssertEqual(active?.embeddingDim, 768)

        // The demoted row SURVIVES (换档回切 space), inactive.
        try await fileStore.withHandle { handle -> Bool in
            let count = try handle.prepare(
                "SELECT COUNT(*) FROM semantic_model WHERE active = 0")
            try XCTAssertTrue(count.step())
            XCTAssertEqual(count.columnInt(0), 1)
            return true
        }
    }

    // MARK: - image_embedding

    func testEmbeddingRoundTripWithinFP16ErrorBand() async throws {
        let ids = try await seedImages(1)
        let vector = seededVector(3)
        try await store.upsertEmbedding(
            imageID: ids[0], modelKey: modelKey, vector: vector, computedTime: 100)
        let rows = try await store.loadScanRows(modelKey: modelKey)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].imageID, ids[0])
        XCTAssertEqual(rows[0].fp16.count, vector.count * 2, "dim*2 bytes")
        let decoded = FP16Coding.unpack(rows[0].fp16)
        XCTAssertEqual(decoded.count, vector.count)
        for (index, value) in zip(decoded, vector) {
            // fp16 representation error for unit-scale values ≈ 5e-4; the
            // pinned band is the plan's 1e-3.
            XCTAssertEqual(
                Double(abs(value - index)), 0, accuracy: 1e-3,
                "fp16 round-trip band at [\(index)]")
        }
    }

    func testDeleteEmbeddingsScopedByModelKey() async throws {
        let ids = try await seedImages(2)
        for id in ids {
            try await store.upsertEmbedding(
                imageID: id, modelKey: "model-a", vector: seededVector(Int(id)),
                computedTime: 1)
            try await store.upsertEmbedding(
                imageID: id, modelKey: "model-b", vector: seededVector(Int(id) + 40),
                computedTime: 1)
        }
        // Scoped: one image, one model key.
        try await store.deleteEmbeddings(imageID: ids[0], modelKey: "model-a")
        var rows = try await store.loadScanRows(modelKey: "model-a")
        XCTAssertEqual(rows.map(\.imageID), [ids[1]])
        rows = try await store.loadScanRows(modelKey: "model-b")
        XCTAssertEqual(rows.count, 2)
        // The nil sweep: every model's rows for the image.
        try await store.deleteEmbeddings(imageID: ids[1])
        rows = try await store.loadScanRows(modelKey: "model-b")
        XCTAssertEqual(rows.map(\.imageID), [ids[0]])
    }

    func testLoadScanRowsStreamsEveryRow() async throws {
        let ids = try await seedImages(50)
        for (index, id) in ids.enumerated() {
            try await store.upsertEmbedding(
                imageID: id, modelKey: modelKey, vector: seededVector(index),
                computedTime: Int64(index))
        }
        let rows = try await store.loadScanRows(modelKey: modelKey)
        XCTAssertEqual(rows.count, 50)
        XCTAssertEqual(Set(rows.map(\.imageID)), Set(ids))
    }

    // MARK: - image_label / label_query

    func testReplaceLabelsReconcilesWholeGroup() async throws {
        let ids = try await seedImages(1)
        func row(_ label: String, _ score: Double) -> SemanticStore.LabelRow {
            SemanticStore.LabelRow(
                label: label, score: score, secondLabel: "other",
                secondScore: score - 0.1, margin: 0.1, confident: score > 0.5,
                topScoresJSON: "[{\"label\":\"\(label)\",\"score\":\(score)}]")
        }
        try await store.replaceLabels(
            imageID: ids[0], modelKey: modelKey,
            rows: [row("sunset", 0.9), row("beach", 0.8), row("dog", 0.3)])
        var labels = try await store.labels(for: ids[0])
        XCTAssertEqual(Set(labels.map(\.label)), ["sunset", "beach", "dog"])

        // Re-run with a DIFFERENT set: the group reconciles (no residue).
        try await store.replaceLabels(
            imageID: ids[0], modelKey: modelKey, rows: [row("sunset", 0.95)])
        labels = try await store.labels(for: ids[0])
        XCTAssertEqual(labels.map(\.label), ["sunset"])
        XCTAssertEqual(labels[0].score, 0.95, accuracy: 1e-12)
        XCTAssertTrue(labels[0].confident)
        // Idempotent re-run: same rows, same face.
        try await store.replaceLabels(
            imageID: ids[0], modelKey: modelKey, rows: [row("sunset", 0.95)])
        labels = try await store.labels(for: ids[0])
        XCTAssertEqual(labels.count, 1)
    }

    func testSeedLabelQueriesIdempotent() async throws {
        let rows = [
            SemanticStore.LabelQueryRow(
                modelKey: modelKey, label: "sunset", queryText: "日落", lang: "zh"),
            SemanticStore.LabelQueryRow(
                modelKey: modelKey, label: "sunset",
                queryText: "a sunset photo", lang: "en"),
        ]
        try await store.seedLabelQueries(rows)
        try await store.seedLabelQueries(rows) // re-seed: ignored
        var loaded = try await store.labelQueries(modelKey: modelKey)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(Set(loaded.map(\.lang)), ["zh", "en"])
        loaded = try await store.labelQueries(modelKey: "other-model")
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - ai_understanding (+ the FTS mirror, AC #7)

    private func understanding(
        _ imageID: Int64, task: String, caption: String
    ) -> SemanticStore.UnderstandingRow {
        SemanticStore.UnderstandingRow(
            imageID: imageID, taskID: task, providerID: "openai",
            modelID: "gpt-test", promptProfileID: "987654321",
            caption: caption, tags: "[\"tag-\(task)\"]", computedTime: 50)
    }

    func testUnderstandingReconcileFlipsActiveAndMirrorsFTS() async throws {
        let ids = try await seedImages(1)
        try await store.replaceUnderstanding(
            understanding(ids[0], task: "t1", caption: "golden retriever on beach"))

        // The INSERT trigger indexed the caption.
        try await assertMatch("retriever", expected: 1)

        // A second task on the same image: the sibling demotes to active=0
        // (旧行留痕), its indexed document REMAINS in the index (checker
        // E5: the index has no active concept — the CONSUMER filters).
        try await store.replaceUnderstanding(
            understanding(ids[0], task: "t2", caption: "city nightscape"))
        var rows = try await store.understandings(imageID: ids[0])
        XCTAssertEqual(rows.count, 2)
        let byTask = Dictionary(uniqueKeysWithValues: rows.map { ($0.row.taskID, $0.active) })
        XCTAssertEqual(byTask, ["t1": false, "t2": true])
        try await assertMatch("retriever", expected: 1)
        try await assertMatch("nightscape", expected: 1)

        // Re-running t1 REPLACES its row (UNIQUE(image,task)) and
        // re-activates it, demoting t2 — one transaction.
        try await store.replaceUnderstanding(
            understanding(ids[0], task: "t1", caption: "a golden sunset"))
        rows = try await store.understandings(imageID: ids[0])
        XCTAssertEqual(rows.count, 2, "the replaced row did not duplicate")
        let activeByTask = Dictionary(
            uniqueKeysWithValues: rows.map { ($0.row.taskID, $0.active) })
        XCTAssertEqual(activeByTask, ["t1": true, "t2": false])
        let captionByTask = Dictionary(
            uniqueKeysWithValues: rows.map { ($0.row.taskID, $0.row.caption ?? "") })
        XCTAssertEqual(captionByTask["t1"], "a golden sunset")
        // The FTS mirror restaged the new document (old words gone).
        try await assertMatch("sunset", expected: 1)
        try await assertMatch("beach", expected: 0)
    }

    func testUnderstandingDeleteUnstagesFTS() async throws {
        let ids = try await seedImages(1)
        try await store.replaceUnderstanding(
            understanding(ids[0], task: "t1", caption: "a foggy harbour"))
        try await assertMatch("harbour", expected: 1)
        // The raw-row delete (the CASCADE's leg shape) unstages through the
        // DELETE trigger.
        try await fileStore.withHandle { handle -> Bool in
            try handle.execute("DELETE FROM ai_understanding WHERE image_id = \(ids[0])")
            return true
        }
        try await assertMatch("harbour", expected: 0)
        let rows = try await store.understandings(imageID: ids[0])
        XCTAssertTrue(rows.isEmpty)
    }

    private func assertMatch(
        _ term: String, expected: Int, file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let hits: [Int64] = try await fileStore.withHandle { handle in
            let statement = try handle.prepare("""
                SELECT rowid FROM ai_understanding_fts
                WHERE ai_understanding_fts MATCH ?
                """)
            try statement.bindText(1, term)
            var ids: [Int64] = []
            while try statement.step() {
                ids.append(statement.columnInt(0) ?? 0)
            }
            return ids
        }
        XCTAssertEqual(hits.count, expected, "MATCH '\(term)'", file: file, line: line)
    }

    // MARK: - ai_rating

    func testRatingAppendOnlyAndLatest() async throws {
        let ids = try await seedImages(1)
        try await store.appendRating(SemanticStore.RatingRow(
            imageID: ids[0], taskID: "t1", providerID: "p", modelID: "m",
            promptProfileID: "42", rating: 0,
            reasons: "[\"too dark to rate\"]", computedTime: 1))
        try await store.appendRating(SemanticStore.RatingRow(
            imageID: ids[0], taskID: "t2", providerID: "p", modelID: "m",
            promptProfileID: "42", rating: 4, reasons: "[\"sharp\"]",
            computedTime: 2))
        let latest = try await store.latestRating(imageID: ids[0])
        XCTAssertEqual(latest?.rating, 4, "the newest row wins")
        XCTAssertEqual(latest?.taskID, "t2")
        // The sentinel row stays in history (append-only).
        try await fileStore.withHandle { handle -> Bool in
            let count = try handle.prepare(
                "SELECT COUNT(*) FROM ai_rating WHERE image_id = \(ids[0])")
            try XCTAssertTrue(count.step())
            XCTAssertEqual(count.columnInt(0), 2)
            return true
        }
        let none = try await store.latestRating(imageID: 999)
        XCTAssertNil(none)
    }

    // MARK: - CASCADE across the four AI domains (AC #2)

    func testImageDeleteCascadesAllFourDomains() async throws {
        let ids = try await seedImages(1)
        let id = ids[0]
        try await store.upsertModel(SemanticStore.ModelRecord(
            modelKey: modelKey, modelID: "org/m", revision: "r",
            embeddingDim: 16, imageSize: 224, active: true))
        try await store.upsertEmbedding(
            imageID: id, modelKey: modelKey, vector: seededVector(1),
            computedTime: 1)
        try await store.replaceLabels(
            imageID: id, modelKey: modelKey,
            rows: [SemanticStore.LabelRow(label: "dog", score: 0.9, confident: true)])
        try await store.replaceUnderstanding(
            understanding(id, task: "t1", caption: "a dog in a park"))
        try await store.appendRating(SemanticStore.RatingRow(
            imageID: id, taskID: "t1", providerID: "p", modelID: "m",
            promptProfileID: "42", rating: 3, computedTime: 1))
        try await assertMatch("dog", expected: 1)

        // The image row dies — every AI-domain row follows (label_query is
        // image-INDEPENDENT and stays).
        try await fileStore.withHandle { handle -> Bool in
            try handle.execute("DELETE FROM images WHERE id = \(id)")
            return true
        }
        for table in ["image_embedding", "image_label", "ai_understanding",
                      "ai_rating"] {
            let count: Int = try await fileStore.withHandle { handle in
                let statement = try handle.prepare(
                    "SELECT COUNT(*) FROM \(table)")
                try XCTAssertTrue(statement.step())
                return Int(statement.columnInt(0) ?? -1)
            }
            XCTAssertEqual(count, 0, "\(table) rows must cascade away")
        }
        try await assertMatch("dog", expected: 0)
        let queries = try await store.labelQueries(modelKey: modelKey)
        XCTAssertTrue(queries.isEmpty, "no factory rows were seeded anyway")
        // The model registry row is image-independent too.
        let model = try await store.activeModel()
        XCTAssertEqual(model?.modelKey, modelKey)
    }
}
