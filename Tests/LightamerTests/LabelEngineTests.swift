import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LabelEngineTests (Plan M2-10-03 T1, KD-2) — the cosine classification:
//
//   • hand-computed anchors on 3-dim toy vectors (parallel = 1 / orthogonal
//     = 0 / opposite = −1) with exact ordering
//   • the confident margin boundary pinned BOTH sides of the threshold
//     (equal → confident, one ulp below → not) — the >= is load-bearing
//   • deterministic tie-break (equal scores → alphabetical by label)
//   • per-row runner-up fields + the tail-row (no successor) face
//   • the top-8 storage pruning + the same-source top_scores JSON shape
//   • LabelPrototypeSet.load: round-trip, revision mismatch TYPED, the
//     corrupt-index family, the absent-directory face
//   • the factory catalog completeness (zh/en parity, unique labels) and
//     the idempotent seed into a REAL .lalb (checker E1 — no stub store)
//   • REAL-prototype chain sanity (resource-gated XCTSkip): the shipped
//     bundle prototypes classify a real embedded fixture
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LabelEngineTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: SemanticStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("label-engine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Labels.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Labels")
        store = SemanticStore(store: fileStore)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        fileStore = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func prototype(_ label: String, _ vector: [Float]) -> LabelPrototype {
        LabelPrototype(label: label, vector: vector)
    }

    /// Machine-independent little-endian fp16 bytes for one vector.
    private func leFP16(_ vector: [Float]) -> Data {
        var bytes: [UInt8] = []
        for value in vector {
            let bits = Float16(value).bitPattern
            bytes.append(UInt8(bits & 0xFF))
            bytes.append(UInt8((bits >> 8) & 0xFF))
        }
        return Data(bytes)
    }

    /// Write a bundle-shaped label-prototypes directory; returns it.
    @discardableResult
    private func writeBundle(
        name: String = "label-prototypes", revision: String,
        dim: Int, labels: [(String, [Float])]
    ) throws -> URL {
        let directory = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        var payload = Data()
        var entries: [[String: Any]] = []
        for (index, entry) in labels.enumerated() {
            payload.append(leFP16(entry.1))
            entries.append(["label": entry.0, "offset": index])
        }
        let index: [String: Any] = [
            "revision": revision, "dim": dim,
            "count": labels.count, "labels": entries,
        ]
        let jsonData = try JSONSerialization.data(
            withJSONObject: index, options: [.sortedKeys, .prettyPrinted])
        try jsonData.write(to: directory.appendingPathComponent("prototypes.json"))
        try payload.write(to: directory.appendingPathComponent("prototypes.bin"))
        return directory
    }

    // MARK: - Hand-computed anchors

    func testCosineAnchorsParallelOrthogonalOpposite() {
        // 3-dim toy basis: the image sits on +x; the three prototypes are
        // parallel (+1), orthogonal (0) and opposite (−1) to it.
        let image: [Float] = [1, 0, 0]
        let scores = LabelEngine.classify(
            image: image, prototypes: [
                prototype("orthogonal", [0, 1, 0]),
                prototype("parallel", [1, 0, 0]),
                prototype("opposite", [-1, 0, 0]),
            ])
        XCTAssertEqual(scores.map(\.label), ["parallel", "orthogonal", "opposite"])
        XCTAssertEqual(scores[0].score, 1.0, accuracy: 1e-6)
        XCTAssertEqual(scores[1].score, 0.0, accuracy: 1e-6)
        XCTAssertEqual(scores[2].score, -1.0, accuracy: 1e-6)
        // Chain of runner-up fields down the ordered table (toy values are
        // float-exact — 1 − 0 has no rounding).
        XCTAssertEqual(scores[0].secondLabel, "orthogonal")
        XCTAssertEqual(scores[0].secondScore, Float(0.0))
        XCTAssertEqual(scores[0].margin, Float(1.0))
        XCTAssertEqual(scores[1].secondLabel, "opposite")
        XCTAssertEqual(scores[2].secondLabel, nil)
        XCTAssertEqual(scores[2].margin, nil)
        XCTAssertTrue(scores[2].confident) // the tail row: nothing contradicts
    }

    func testNonUnitInputTreatedAsNormalizedContract() {
        // The contract: inputs are pre-normalized — the engine does NOT
        // renormalize the image side (the engine chain guarantees it). A
        // 2×-scaled image vector doubles every cosine; this pins the
        // no-hidden-norm posture (drift would silently corrupt margins).
        let scores = LabelEngine.classify(
            image: [2, 0, 0], prototypes: [prototype("parallel", [1, 0, 0])])
        XCTAssertEqual(scores[0].score, Float(2.0), accuracy: 1e-6)
    }

    func testTieBreaksAlphabeticallyByLabel() {
        let scores = LabelEngine.classify(
            image: [1, 0, 0], prototypes: [
                prototype("zeta", [1, 0, 0]),
                prototype("alpha", [1, 0, 0]),
                prototype("mid", [1, 0, 0]),
            ])
        XCTAssertEqual(scores.map(\.label), ["alpha", "mid", "zeta"])
        XCTAssertEqual(scores[0].margin, Float(0.0))
        // An exact tie can never clear a positive threshold…
        XCTAssertFalse(scores[0].confident)
        // …but the tail row still counts confident (no competitor).
        XCTAssertTrue(scores[2].confident)
    }

    // MARK: - The confident boundary (>= — both sides, mechanically pinned)

    func testConfidentBoundaryIsInclusiveAtThreshold() throws {
        let image: [Float] = [1, 0]
        let top = prototype("top", [1, 0])
        // Runner-up at angle θ → margin = 1 − cos θ. Choose cos θ = 0.9 →
        // margin 0.1 > 0.05, then drive the threshold EXACTLY onto the
        // computed margin (the >= side) and one ulp above it (the < side).
        let angle = acos(Float(0.9))
        let runnerUp = prototype("runner", [cos(angle), sin(angle)])
        let scores = LabelEngine.classify(
            image: image, prototypes: [top, runnerUp],
            threshold: LabelEngine.confidentThreshold)
        let margin = try XCTUnwrap(scores[0].margin)
        XCTAssertEqual(margin, 0.1, accuracy: 1e-5)
        XCTAssertTrue(scores[0].confident) // 0.1 ≥ 0.05

        let atThreshold = LabelEngine.classify(
            image: image, prototypes: [top, runnerUp], threshold: margin)
        XCTAssertTrue(atThreshold[0].confident, "margin == threshold must count confident")

        let aboveThreshold = LabelEngine.classify(
            image: image, prototypes: [top, runnerUp], threshold: margin.nextUp)
        XCTAssertFalse(aboveThreshold[0].confident, "one ulp above must NOT count")
    }

    // MARK: - Storage pruning + JSON

    func testLabelRowsClampToTopEightWithMainRowJSON() throws {
        // 12 orthogonal-ish prototypes: scores 1.0, 0.95, … descending by
        // construction (each vector shares a shrinking x-component).
        var prototypes: [LabelPrototype] = []
        for index in 0..<12 {
            let x = 1.0 - Float(index) * 0.05
            let y = sqrt(max(0, 1 - x * x))
            prototypes.append(prototype("rank-\(index)", [x, y]))
        }
        let image: [Float] = [1, 0]
        let scores = LabelEngine.classify(image: image, prototypes: prototypes)
        XCTAssertEqual(scores.count, 12)
        XCTAssertEqual(scores[0].label, "rank-0")
        XCTAssertEqual(scores[11].label, "rank-11")

        let rows = LabelEngine.labelRows(from: scores)
        XCTAssertEqual(rows.count, LabelEngine.storedTopCount)
        XCTAssertEqual(rows[0].label, "rank-0")
        XCTAssertEqual(rows[7].label, "rank-7")
        // Per-row runner-up fields; the MAIN row alone carries the JSON.
        XCTAssertEqual(rows[0].secondLabel, "rank-1")
        XCTAssertNotNil(rows[0].topScoresJSON)
        XCTAssertNil(rows[1].topScoresJSON)
        // The cut boundary: the 8th row's runner-up still points at the
        // rank-9 label of the FULL table (the margin chain is computed over
        // every prototype — the pruning caps STORED rows, not the ranking).
        XCTAssertEqual(rows[7].secondLabel, "rank-8")

        // The JSON mirrors the same 8, same order, label+score keys only.
        let json = try XCTUnwrap(rows[0].topScoresJSON)
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(decoded.count, 8)
        XCTAssertEqual(decoded[0]["label"] as? String, "rank-0")
        XCTAssertEqual(decoded[0]["score"] as? Double, Double(scores[0].score))
        XCTAssertEqual(decoded[7]["label"] as? String, "rank-7")
    }

    func testSinglePrototypeFaceAndEmptyFaces() {
        let single = LabelEngine.classify(
            image: [1, 0, 0], prototypes: [prototype("only", [1, 0, 0])])
        XCTAssertEqual(single.count, 1)
        XCTAssertNil(single[0].secondLabel)
        XCTAssertNil(single[0].margin)
        XCTAssertTrue(single[0].confident)

        XCTAssertTrue(LabelEngine.classify(image: [1], prototypes: []).isEmpty)
        XCTAssertTrue(LabelEngine.labelRows(from: []).isEmpty)

        // A narrower top than the default clamp respects the caller.
        let rows = LabelEngine.labelRows(
            from: single, top: LabelEngine.storedTopCount)
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - LabelPrototypeSet.load

    func testPrototypeSetLoadRoundTripRenormalizes() throws {
        let raw = (1.0 - Float(1e-4), Float(0.0)) // slightly off-unit on purpose
        let directory = try writeBundle(
            revision: "rev-1", dim: 2,
            labels: [("a", [raw.0, raw.1]), ("b", [0, 1])])
        let set = try LabelPrototypeSet.load(
            directory: directory, expectingRevision: "rev-1")
        XCTAssertEqual(set.revision, "rev-1")
        XCTAssertEqual(set.dim, 2)
        XCTAssertEqual(set.prototypes.map(\.label), ["a", "b"])
        // The fp16 round-trip + renormalize lands back on the unit circle.
        let norm = sqrt(
            set.prototypes[0].vector.reduce(Float(0)) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1.0, accuracy: 1e-6)
        XCTAssertEqual(set.prototypes[1].vector[1], 1.0, accuracy: 1e-6)
    }

    func testPrototypeRevisionMismatchIsTyped() throws {
        let directory = try writeBundle(
            revision: "rev-old", dim: 2, labels: [("a", [1, 0])])
        do {
            _ = try LabelPrototypeSet.load(
                directory: directory, expectingRevision: "rev-new")
            XCTFail("expected prototypeRevisionMismatch")
        } catch let error as LabelPrototypeError {
            XCTAssertEqual(
                error, .prototypeRevisionMismatch(expected: "rev-new", actual: "rev-old"))
        }
    }

    func testPrototypeCorruptAndMissingFaces() throws {
        // Missing directory entirely.
        do {
            _ = try LabelPrototypeSet.load(
                directory: tempDirectory.appendingPathComponent("absent"),
                expectingRevision: "rev-1")
            XCTFail("expected prototypesUnavailable")
        } catch let error as LabelPrototypeError {
            XCTAssertEqual(error, .prototypesUnavailable)
        }
        // Undecodable index.
        let broken = try writeBundle(revision: "rev-1", dim: 2, labels: [("a", [1, 0])])
        try Data("not json".utf8).write(
            to: broken.appendingPathComponent("prototypes.json"))
        do {
            _ = try LabelPrototypeSet.load(directory: broken, expectingRevision: "rev-1")
            XCTFail("expected prototypeIndexCorrupt")
        } catch let error as LabelPrototypeError {
            guard case .prototypeIndexCorrupt = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
        // Payload size disagrees with count×dim.
        let sized = try writeBundle(revision: "rev-1", dim: 2, labels: [("a", [1, 0])])
        try Data([0, 0, 0]).write(to: sized.appendingPathComponent("prototypes.bin"))
        do {
            _ = try LabelPrototypeSet.load(directory: sized, expectingRevision: "rev-1")
            XCTFail("expected prototypeIndexCorrupt")
        } catch let error as LabelPrototypeError {
            guard case .prototypeIndexCorrupt = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
        // Duplicate labels in the index.
        let dup = try writeBundle(
            revision: "rev-1", dim: 2, labels: [("a", [1, 0]), ("a", [0, 1])])
        do {
            _ = try LabelPrototypeSet.load(directory: dup, expectingRevision: "rev-1")
            XCTFail("expected prototypeIndexCorrupt")
        } catch let error as LabelPrototypeError {
            guard case .prototypeIndexCorrupt = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    // MARK: - Factory catalog (AC #2: zh/en 对齐 + 落库幂等)

    func testFactoryCatalogCompleteness() {
        let catalog = LabelQueries.catalog
        XCTAssertGreaterThanOrEqual(catalog.count, 160, "the ~160-label plan floor")
        let labels = catalog.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count, "labels must be unique")
        for entry in catalog {
            XCTAssertFalse(entry.label.isEmpty)
            XCTAssertFalse(entry.queryZH.isEmpty, entry.label)
            XCTAssertFalse(entry.queryEN.isEmpty, entry.label)
        }
        // seedRows: exactly one zh + one en row per label, unique pairs.
        let rows = LabelQueries.seedRows(modelKey: "m")
        XCTAssertEqual(rows.count, catalog.count * 2)
        let pairs = rows.map { "\($0.label)|\($0.lang)" }
        XCTAssertEqual(Set(pairs).count, rows.count)
        XCTAssertTrue(pairs.contains("mountain|zh"))
        XCTAssertTrue(pairs.contains("mountain|en"))
    }

    func testFactorySeedIsIdempotentIntoRealProject() async throws {
        // Checker E1: a REAL .lalb — seed twice, the PK dedupes; zh/en land
        // aligned (one row of each language per label).
        let modelKey = ModelAssetCatalog.chineseClipViTB16Int8.profileID
        try await store.seedLabelQueries(LabelQueries.seedRows(modelKey: modelKey))
        try await store.seedLabelQueries(LabelQueries.seedRows(modelKey: modelKey))
        let rows = try await store.labelQueries(modelKey: modelKey)
        XCTAssertEqual(rows.count, LabelQueries.catalog.count * 2)
        var byLabel: [String: Set<String>] = [:]
        for row in rows { byLabel[row.label, default: []].insert(row.lang) }
        XCTAssertEqual(byLabel.count, LabelQueries.catalog.count)
        for (label, langs) in byLabel {
            XCTAssertEqual(langs, ["zh", "en"], label)
        }
    }

    // MARK: - Real-prototype chain sanity (resource-gated)

    func testRealPrototypesClassifyRealEmbedding() async throws {
        // The resource gate: bundled CLIP assets + the GENERATED prototype
        // tree + a loadable engine — absent on any of the three → SKIP
        // (auditable; the no-model CI face stays 0-fail).
        let clip = ModelAssetCatalog.chineseClipViTB16Int8
        let locator = ModelLocator()
        guard let profileURL = locator.bundledProfileURL(clip.profileID) else {
            throw XCTSkip("bundled CLIP assets absent — resource gate (M5)")
        }
        let prototypeDirectory = profileURL.appendingPathComponent(
            "label-prototypes", isDirectory: true)
        guard FileManager.default.fileExists(
            atPath: prototypeDirectory.appendingPathComponent("prototypes.json").path)
        else {
            throw XCTSkip("generated label prototypes absent — resource gate (M5)")
        }
        guard let searcher = await AIInferenceService.shared.semanticSearcher(),
            let engine = searcher as? SemanticEngine
        else {
            throw XCTSkip("bundled CLIP assets failed to load — resource gate (M5)")
        }

        try await store.upsertModel(SemanticStore.ModelRecord(
            modelKey: clip.profileID, modelID: clip.modelID,
            revision: clip.revision, embeddingDim: clip.embeddingDim ?? 512,
            imageSize: clip.inputSize, active: true))
        // image_embedding references images(id) — seed the parent row first.
        _ = try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare(
                "INSERT INTO images (image_path, path_kind) VALUES (?, 0)")
            try insert.bindText(1, "Media/IMG_0001.jpg")
            _ = try insert.step()
            return true
        }
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "sample-gradient", withExtension: "jpg"))
        try await engine.embedAndStore(
            imageData: try Data(contentsOf: fixture), imageID: 1, in: store,
            computedTime: 0)
        let rows = try await store.loadScanRows(modelKey: clip.profileID)
        let vector = FP16Coding.unpack(try XCTUnwrap(rows.first?.fp16))

        let prototypes = try LabelPrototypeSet.load(
            directory: prototypeDirectory, expectingRevision: clip.revision)
        XCTAssertEqual(prototypes.prototypes.count, LabelQueries.catalog.count)

        // CHAIN sanity (synthetic gradients carry no semantics — 01 §9):
        // the full ordered table, descending, scores in the cosine band,
        // and the stored rows project without loss.
        let scores = LabelEngine.classify(image: vector, prototypes: prototypes.prototypes)
        XCTAssertEqual(scores.count, LabelQueries.catalog.count)
        for index in 1..<scores.count {
            XCTAssertGreaterThanOrEqual(
                scores[index - 1].score, scores[index].score, scores[index].label)
        }
        for score in scores {
            XCTAssertLessThanOrEqual(score.score, 1.002, score.label)
            XCTAssertGreaterThanOrEqual(score.score, -1.002, score.label)
        }
        let stored = LabelEngine.labelRows(from: scores)
        XCTAssertEqual(stored.count, LabelEngine.storedTopCount)
        try await store.replaceLabels(
            imageID: 1, modelKey: clip.profileID, rows: stored)
        let readBack = try await store.labels(for: 1)
        XCTAssertEqual(readBack.count, LabelEngine.storedTopCount)
        XCTAssertEqual(readBack.first?.label, scores[0].label)
    }
}
