import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// SemanticSearchTests (Plan M2-10-02 T4, KD-5/KD-6) — the query chain and the
// CLIP-tab submit leg over a REAL `.lalb` fixture:
//
//   • engine query chain with a MOCK runner (zero model dependency — CI
//     face): hit order == score order, typed .modelUnavailable /
//     .dimensionMismatch, empty-query short circuit
//   • the LibrarySearchModel CLIP leg: hits fold into the grid's semantic
//     overlay IN HIT ORDER; the count card (inspector) shows the hit count;
//     empty input clears the leg; a missing engine is the honest
//     .modelUnavailable family; the EXIF and semantic legs are exclusive
//   • REAL-model sanity (M5, resource-gated XCTSkip): the bundled Chinese-CLIP
//     end-to-end — embed two fixture images through the manifest.inputSize
//     pre-scale + image tower, then a zh AND an en query each return ordered
//     hits through the text tower + vDSP sweep. Synthetic gradient fixtures:
//     this is the CHAIN sanity (M2AI-01's 检索面可审计用例), not a quality
//     judgment (01 DECISIONS §9 keeps the real-photo golden open)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SemanticSearchTests: XCTestCase {

    /// The mock inference seam (KD-5's protocol face — fixed vectors, no
    /// CoreML).
    private final class MockRunner: AIInferencing, @unchecked Sendable {
        let textVector: [Float]
        let imageVector: [Float]
        var embedTextCalls = 0

        init(textVector: [Float], imageVector: [Float] = []) {
            self.textVector = textVector
            self.imageVector = imageVector
        }

        func embedText(
            _ profileID: String, tokens: [Int64], mask: [Int64]
        ) async throws -> [Float] {
            embedTextCalls += 1
            return textVector
        }

        func embedImage(_ profileID: String, jpeg: Data) async throws -> [Float] {
            imageVector
        }
    }

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var semanticStore: SemanticStore!
    private var queries: LibraryQueries!
    private var grid: LibraryGridModel!
    private var inspector: LibraryInspectorModel!
    private var imageIDs: [Int64] = []

    private let modelKey = "mock-clip"
    private let dim = 4

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("semantic-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Search.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Search")
        semanticStore = SemanticStore(store: fileStore)
        queries = LibraryQueries(store: fileStore)
        grid = LibraryGridModel(queries: queries, pageSize: 5)
        inspector = LibraryInspectorModel(
            grid: grid, queries: queries, smartAlbums: nil)
        imageIDs = try await seed()
        try await grid.reloadFirstPage()
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        semanticStore = nil
        grid = nil
        inspector = nil
        queries = nil
        fileStore = nil
        try await super.tearDown()
    }

    /// Three images with filename sort keys; one embedding row each.
    private func seed() async throws -> [Int64] {
        let ids = try await fileStore.withWriteBatch { handle -> [Int64] in
            let insert = try handle.prepare(
                "INSERT INTO images (image_path, path_kind, file_stem, filename, iso) VALUES (?, 0, ?, ?, ?)")
            var ids: [Int64] = []
            for (index, stem) in ["aaa", "bbb", "ccc"].enumerated() {
                try insert.reset()
                try insert.bindText(1, "Media/\(stem).arw")
                try insert.bindText(2, stem)
                try insert.bindText(3, stem + ".arw")
                try insert.bindInt(4, index == 1 ? 800 : 100)
                _ = try insert.step()
                ids.append(handle.lastInsertRowID())
            }
            return ids
        }
        try await semanticStore.upsertModel(SemanticStore.ModelRecord(
            modelKey: modelKey, modelID: "org/mock", revision: "r1",
            embeddingDim: dim, imageSize: 224, active: true))
        // Orthogonal bases + one diagonal: a hand-checkable geometry.
        let vectors: [[Float]] = [
            [1, 0, 0, 0],                              // ids[0]
            [0, 1, 0, 0],                              // ids[1]
            normalize([1, 1, 0, 0]),                   // ids[2]
        ]
        for (index, id) in ids.enumerated() {
            try await semanticStore.upsertEmbedding(
                imageID: id, modelKey: modelKey, vector: vectors[index],
                computedTime: Int64(index))
        }
        return ids
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let norm = Float(sqrt(vector.reduce(0.0) { $0 + Double($1 * $1) }))
        return vector.map { $0 / norm }
    }

    private func makeEngine(queryVector: [Float]) -> SemanticEngine {
        let tokenizer = try! WordPieceTokenizer(vocabulary: [
            "[PAD]": 0, "[UNK]": 1, "[CLS]": 2, "[SEP]": 3, "a": 4, "dog": 5,
        ])
        return SemanticEngine(
            runner: MockRunner(textVector: queryVector), tokenizer: tokenizer)
    }

    private func makeModel(engine: SemanticEngine?) -> LibrarySearchModel {
        let provider: (@Sendable () async -> (any SemanticSearching)?)? =
            engine.map { instance in
                { @Sendable in instance as (any SemanticSearching)? }
            }
        return LibrarySearchModel(
            grid: grid, semanticStore: semanticStore, semantic: provider)
    }

    // MARK: - The engine query chain (mock runner)

    func testQueryChainReturnsHitsInScoreOrder() async throws {
        // Query == row 1's direction: 1.0 > 1/√2 > 0.
        let engine = makeEngine(queryVector: [0, 1, 0, 0])
        let hits = try await engine.search("a dog", limit: 3, in: semanticStore)
        XCTAssertEqual(hits.map(\.imageID), [imageIDs[1], imageIDs[2], imageIDs[0]])
        XCTAssertEqual(hits[0].score, 1.0, accuracy: 1e-5)
        XCTAssertEqual(hits[1].score, Float(1.0 / sqrt(2.0)), accuracy: 1e-3)
        XCTAssertEqual(hits[2].score, 0.0, accuracy: 1e-5)
        // The limit truncates the tail.
        let top1 = try await engine.search("a dog", limit: 1, in: semanticStore)
        XCTAssertEqual(top1.map(\.imageID), [imageIDs[1]])
    }

    func testQueryDimensionMismatchIsTyped() async throws {
        let engine = makeEngine(queryVector: [0.5, 0.5, 0.5]) // 3 ≠ 4
        do {
            _ = try await engine.search("a dog", limit: 2, in: semanticStore)
            XCTFail("expected dimensionMismatch")
        } catch let error as SemanticSearchError {
            XCTAssertEqual(error, .dimensionMismatch(expected: 4, actual: 3))
        }
    }

    func testModelUnavailableWhenNoActiveRow() async throws {
        // A package with NO active semantic model row.
        let emptyURL = tempDirectory.appendingPathComponent("Empty.lalb")
        let emptyFileStore = ProjectFileStore(at: emptyURL)
        _ = try await emptyFileStore.create(name: "Empty")
        let emptyStore = SemanticStore(store: emptyFileStore)
        defer { Task { try? await emptyFileStore.close() } }
        let engine = makeEngine(queryVector: [1, 0, 0, 0])
        do {
            _ = try await engine.search("a dog", limit: 2, in: emptyStore)
            XCTFail("expected modelUnavailable")
        } catch let error as SemanticSearchError {
            XCTAssertEqual(error, .modelUnavailable)
        }
    }

    func testEmptyQueryShortCircuits() async throws {
        // A package with NO model row at all: the empty query never reads
        // it — the honest empty result, not an error.
        let emptyURL = tempDirectory.appendingPathComponent("Empty2.lalb")
        let emptyFileStore = ProjectFileStore(at: emptyURL)
        _ = try await emptyFileStore.create(name: "Empty2")
        let emptyStore = SemanticStore(store: emptyFileStore)
        defer { Task { try? await emptyFileStore.close() } }
        let engine = makeEngine(queryVector: [1, 0, 0, 0])
        let hits = try await engine.search("   ", limit: 2, in: emptyStore)
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - The CLIP-tab submit leg (grid + count-card linkage)

    func testClipSubmitFoldsHitsIntoGridInHitOrder() async throws {
        let engine = makeEngine(queryVector: [0, 1, 0, 0])
        let model = makeModel(engine: engine)
        model.select(mode: .clip)
        let outcome = await model.submit("a dog")
        XCTAssertEqual(outcome, .semanticApplied(hitCount: 3))
        // The grid IS the result set: hit order, non-hits hidden (here all
        // three hit — assert the ORDER flipped from filename to score).
        XCTAssertEqual(grid.semanticHits, [imageIDs[1], imageIDs[2], imageIDs[0]])
        XCTAssertEqual(
            grid.rows.map(\.id), [imageIDs[1], imageIDs[2], imageIDs[0]])
        // The count card (refresh face) shows the HIT count.
        await inspector.refresh()
        XCTAssertEqual(inspector.overviewCount, 3)
    }

    func testClipEmptySubmitClearsTheLeg() async throws {
        let engine = makeEngine(queryVector: [0, 1, 0, 0])
        let model = makeModel(engine: engine)
        model.select(mode: .clip)
        _ = await model.submit("a dog")
        XCTAssertEqual(grid.rows.count, 3)
        // Empty input = the clearing plan (EXIF symmetry).
        let outcome = await model.submit("   ")
        XCTAssertEqual(outcome, .applied(termCount: 0))
        XCTAssertNil(grid.semanticHits)
        XCTAssertEqual(grid.rows.count, 3, "the full collection is back")
    }

    func testClipSubmitWithoutEngineIsModelUnavailable() async throws {
        // No provider at all (the nil-assembly face).
        let bare = LibrarySearchModel(grid: grid, semanticStore: semanticStore)
        bare.select(mode: .clip)
        let outcome = await bare.submit("a dog")
        XCTAssertEqual(outcome, .failed(.modelUnavailable))
        XCTAssertNil(grid.semanticHits)
        XCTAssertEqual(grid.rows.count, 3, "the collection is untouched")

        // A provider that resolves nil (fail-closed asset load).
        let broken = makeModel(engine: nil)
        broken.select(mode: .clip)
        let brokenOutcome = await broken.submit("a dog")
        XCTAssertEqual(brokenOutcome, .failed(.modelUnavailable))
    }

    func testExifAndSemanticLegsAreExclusive() async throws {
        let engine = makeEngine(queryVector: [0, 1, 0, 0])
        let model = makeModel(engine: engine)
        model.select(mode: .clip)
        _ = await model.submit("a dog")
        XCTAssertNotNil(grid.semanticHits)
        // An EXIF application exits the semantic overlay (structured leg —
        // the fixture seeds no FTS materialization).
        model.select(mode: .exif)
        let exifOutcome = await model.submit("iso800")
        XCTAssertEqual(exifOutcome, .applied(termCount: 1))
        XCTAssertNil(grid.semanticHits)
        XCTAssertEqual(grid.rows.count, 1)
        XCTAssertEqual(grid.rows.first?.fileStem, "bbb")
        // And a full-text submit without an injected query face stays the
        // HONEST typed refusal (M2-10-04 replaced the placeholder — the leg
        // is real where the assembly supplies it; this model supplies none).
        model.select(mode: .fullText)
        let outcome = await model.submit("anything")
        XCTAssertEqual(outcome, .failed(.fulltextUnavailable))
        XCTAssertNil(grid.semanticHits)
        XCTAssertEqual(grid.rows.count, 1)
    }

    // MARK: - The pre-scale (E4: the manifest edge, no model needed)

    func testPreScaleProducesManifestSizedJPEG() throws {
        // A 100×50 source: shorter edge 50 → scale 4.48 → 448×224 → center
        // crop 224².
        let width = 100, height = 50
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let jpeg = try SemanticEngine.preScaledJPEG(from: image, edge: 224)
        let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        XCTAssertEqual(decoded.width, 224, "the E4 edge is the constant source")
        XCTAssertEqual(decoded.height, 224)
    }

    // MARK: - The real-model end-to-end sanity (M5, resource-gated)

    func testRealModelEndToEndZhAndEnQueries() async throws {
        // The resource gate: no bundled CLIP assets → SKIP (auditable; the
        // no-model CI face stays 0-fail).
        let locator = ModelLocator()
        guard locator.bundledProfileURL(
            ModelAssetCatalog.chineseClipViTB16Int8.profileID) != nil
        else {
            throw XCTSkip("bundled CLIP assets absent — resource gate (M5)")
        }
        guard let searcher = await AIInferenceService.shared.semanticSearcher()
        else {
            throw XCTSkip("bundled CLIP assets failed to load — resource gate (M5)")
        }
        let engine = try XCTUnwrap(searcher as? SemanticEngine)

        // The ACTIVE model row is the real bundled profile (the engine
        // reads the manifest inputSize through it).
        let clip = ModelAssetCatalog.chineseClipViTB16Int8
        try await semanticStore.upsertModel(SemanticStore.ModelRecord(
            modelKey: clip.profileID, modelID: clip.modelID,
            revision: clip.revision, embeddingDim: clip.embeddingDim ?? 512,
            imageSize: clip.inputSize, active: true))

        // Embed TWO fixture images through the REAL image chain.
        let fixtureA = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "sample-gradient", withExtension: "jpg"))
        let fixtureB = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "sample-gradient", withExtension: "png"))
        for (index, url) in [fixtureA, fixtureB].enumerated() {
            let data = try Data(contentsOf: url)
            try await engine.embedAndStore(
                imageData: data, imageID: imageIDs[index], in: semanticStore,
                computedTime: Int64(index))
        }
        let table = try await semanticStore.loadScanTable(modelKey: clip.profileID)
        XCTAssertEqual(table.rowIDs.count, 2)

        // zh + en queries, each end-to-end (tokenize → text tower → sweep):
        // non-empty, ordered descending, scores inside the normalized band.
        // Synthetic gradients carry no semantics — this is the CHAIN sanity
        // (M2AI-01's 检索面可审计用例), NOT a quality judgment (01 DECISIONS
        // §9 keeps the real-photo relative-order golden open; two queries
        // legitimately rank meaningless gradients differently).
        for query in ["蓝天白云", "a clear blue sky"] {
            let hits = try await engine.search(query, limit: 10, in: semanticStore)
            XCTAssertFalse(hits.isEmpty, "\(query) returned nothing")
            for index in 1..<hits.count {
                XCTAssertGreaterThanOrEqual(
                    hits[index - 1].score, hits[index].score, query)
            }
            for hit in hits {
                XCTAssertLessThanOrEqual(hit.score, 1.002, query)
                XCTAssertGreaterThanOrEqual(hit.score, -1.002, query)
            }
        }
    }
}
