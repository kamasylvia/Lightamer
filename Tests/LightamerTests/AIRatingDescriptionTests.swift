import Foundation
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AIRatingDescriptionTests (Plan M2-10-04 T3, AC#4/6/8) — the two remote-flow
// orchestrations over a REAL `.lalb` package (E1: the store legs run the true
// schema + FTS triggers; the HTTP leg rides the AISession seam with a scripted
// transport — the same legal缝 the client goldens pin via URLProtocol):
//
//   • rubric assembly: strictness 1-5 calibrations × zh/en, clamped inputs,
//     the sentinel instruction baked in
//   • prompt_profile_id: FNV-1a DECIMAL string, stable on same inputs,
//     sensitive to rubric/protocol/model changes (the M2AI-06 guardrail)
//   • verdict parse: valid stars / out-of-range clamp / sentinel (rating 0
//     and absent) / sentinel-without-reasons malformed / non-JSON malformed
//   • rate(): appends the ai_rating row (sentinel AND real), NEVER touches
//     images.rating by itself (the negative confirm-gate pin), carries the
//     prompt profile + provider/model identity
//   • applyStars(): the ONLY images.rating write, rejects out-of-range
//   • describe(): reconcile + FTS MATCH hit through the E5 join
//     (AIUnderstandingSearch): active rows match; the E5 NEGATIVE pin — an
//     active=0 sibling-task row stays indexed but NEVER matches; a same-task
//     re-run unstages the old words (the L059 mirror through the service path)
//   • rendition_kind: "edited" default / explicit "original"
//   • fulltext sanitize: syntax characters in user input never throw
// ─────────────────────────────────────────────────────────────────────────────

final class AIRatingDescriptionTests: XCTestCase {

    /// The scripted transport (zero real network; zero URLProtocol — the
    /// service-level assertions target the STORE effects, the wire shapes
    /// are the client goldens' job).
    private struct ScriptedTransport: AISession {
        let handler: @Sendable (URLRequest) throws -> (Int, Data)

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "about:blank")!,
                statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            return (body, response)
        }
    }

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var ratingService: AIRatingService!
    private var descriptionService: AIDescriptionService!
    private var imageIDs: [Int64] = []

    private let config = AIConnectionConfig(
        protocol: .openAIChatCompletions,
        baseURL: URL(string: "https://api.example.com/v1")!,
        model: "vision-test")
    private let key = Data("sk-test".utf8)

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ai-rating-desc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Flows.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Flows")
        ratingService = AIRatingService(store: fileStore)
        descriptionService = AIDescriptionService(store: fileStore)
        imageIDs = try await seed()
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        ratingService = nil
        descriptionService = nil
        fileStore = nil
        try await super.tearDown()
    }

    /// Three images (ratings NULL).
    private func seed() async throws -> [Int64] {
        try await fileStore.withWriteBatch { handle -> [Int64] in
            let insert = try handle.prepare(
                "INSERT INTO images (image_path, path_kind, file_stem, filename) VALUES (?, 0, ?, ?)")
            var ids: [Int64] = []
            for stem in ["aaa", "bbb", "ccc"] {
                try insert.reset()
                try insert.bindText(1, "Media/\(stem).arw")
                try insert.bindText(2, stem)
                try insert.bindText(3, stem + ".arw")
                _ = try insert.step()
                ids.append(handle.lastInsertRowID())
            }
            return ids
        }
    }

    private func openAIResponse(contentJSON: String) throws -> Data {
        let wrapper: [String: Any] = [
            "choices": [[
                "message": ["role": "assistant", "content": contentJSON],
                "finish_reason": "stop",
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: wrapper)
    }

    private func transport(returning contentJSON: String) -> ScriptedTransport {
        let body = try! openAIResponse(contentJSON: contentJSON)
        return ScriptedTransport { _ in (200, body) }
    }

    private func imagesRating(_ imageID: Int64) async throws -> Int64? {
        try await fileStore.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT rating FROM images WHERE id = ?")
            try statement.bindInt(1, imageID)
            guard try statement.step() else { return nil }
            return statement.columnInt(0)
        }
    }

    private func latestRatingRow(
        _ imageID: Int64
    ) async throws -> SemanticStore.RatingRow? {
        let semantic = SemanticStore(store: fileStore)
        return try await semantic.latestRating(imageID: imageID)
    }

    // MARK: - rubric assembly

    func testRubricVariesByStrictnessAndLanguage() {
        let zh = (1...5).map {
            AIRatingService.rubricText(strictness: $0, language: .chinese)
        }
        let en = (1...5).map {
            AIRatingService.rubricText(strictness: $0, language: .english)
        }
        // Five distinct calibrations per language, languages disjoint.
        XCTAssertEqual(Set(zh).count, 5)
        XCTAssertEqual(Set(en).count, 5)
        XCTAssertTrue(zh.contains { $0.contains("宽松") })
        XCTAssertTrue(zh.contains { $0.contains("展出标准") })
        XCTAssertTrue(en.contains { $0.contains("exhibition standard") })
        // The JSON contract + the refusal instruction ride EVERY rubric.
        for rubric in zh + en {
            XCTAssertTrue(rubric.contains("\"rating\""))
            XCTAssertTrue(rubric.contains("0"))
        }
        // Out-of-domain strictness clamps (defensive calibration).
        XCTAssertEqual(
            AIRatingService.rubricText(strictness: 0, language: .english),
            AIRatingService.rubricText(strictness: 1, language: .english))
        XCTAssertEqual(
            AIRatingService.rubricText(strictness: 9, language: .english),
            AIRatingService.rubricText(strictness: 5, language: .english))
    }

    // MARK: - prompt profile id (the M2AI-06 guardrail)

    func testPromptProfileIDStableAndChangeSensitive() {
        let rubric = AIRatingService.rubricText(strictness: 3, language: .english)
        let a = AIRatingService.promptProfileID(
            rubric: rubric, protocol: .openAIChatCompletions, model: "m1")
        let b = AIRatingService.promptProfileID(
            rubric: rubric, protocol: .openAIChatCompletions, model: "m1")
        XCTAssertEqual(a, b, "same inputs → same identity")
        // Decimal string (L013 — never hex, never negative, never raw int).
        XCTAssertFalse(a.isEmpty)
        XCTAssertTrue(a.allSatisfy { $0.isNumber })
        // Rubric change → new id.
        let otherRubric = AIRatingService.rubricText(strictness: 4, language: .english)
        XCTAssertNotEqual(
            a, AIRatingService.promptProfileID(
                rubric: otherRubric, protocol: .openAIChatCompletions,
                model: "m1"))
        // Protocol change → new id.
        XCTAssertNotEqual(
            a, AIRatingService.promptProfileID(
                rubric: rubric, protocol: .anthropicMessages, model: "m1"))
        // Model change → new id.
        XCTAssertNotEqual(
            a, AIRatingService.promptProfileID(
                rubric: rubric, protocol: .openAIChatCompletions, model: "m2"))
    }

    // MARK: - verdict parse

    func testParseVerdictValidAndClamped() throws {
        XCTAssertEqual(
            try AIRatingService.parseVerdict(#"{"rating": 4, "reasons": ["good"]}"#),
            AIRatingVerdict(stars: 4, reasons: ["good"]))
        // Out-of-range clamps into [1, 5].
        XCTAssertEqual(
            try AIRatingService.parseVerdict(#"{"rating": 7, "reasons": ["r"]}"#).stars, 5)
        XCTAssertEqual(
            try AIRatingService.parseVerdict(#"{"rating": -2, "reasons": ["r"]}"#).stars, 1)
        // Missing reasons tolerates on a real rating (reasons optional there).
        XCTAssertEqual(
            try AIRatingService.parseVerdict(#"{"rating": 2}"#),
            AIRatingVerdict(stars: 2, reasons: []))
    }

    func testParseVerdictSentinelOnZeroAndMissingRating() throws {
        // rating 0 + reasons = the explicit refusal sentinel.
        XCTAssertEqual(
            try AIRatingService.parseVerdict(
                #"{"rating": 0, "reasons": ["unrecoverable motion blur"]}"#),
            AIRatingVerdict(stars: 0, reasons: ["unrecoverable motion blur"]))
        // rating ABSENT + reasons = the declined-to-rate sentinel.
        let absent = try AIRatingService.parseVerdict(
            #"{"reasons": ["cannot assess this subject"]}"#)
        XCTAssertEqual(absent.stars, 0)
        XCTAssertTrue(absent.isSentinel)
    }

    func testParseVerdictSentinelWithoutReasonsIsMalformed() {
        XCTAssertThrowsError(
            try AIRatingService.parseVerdict(#"{"rating": 0}"#)
        ) { error in
            guard case AIRatingError.malformedOutput = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try AIRatingService.parseVerdict(#"{"caption": "no rating here"}"#)
        ) { error in
            guard case AIRatingError.malformedOutput = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    func testParseVerdictNonJSONIsMalformed() {
        XCTAssertThrowsError(
            try AIRatingService.parseVerdict("I cannot help with that.")
        ) { error in
            guard case AIRatingError.malformedOutput = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    // MARK: - rate() → ai_rating (append; confirm gate separate)

    func testRateAppendsSentinelRowAndNeverTouchesImagesRating() async throws {
        let id = imageIDs[0]
        let transport = transport(returning: #"""
            {"rating": 0, "reasons": ["subject unrecognizable"]}
            """#)
        let verdict = try await ratingService.rate(
            imageJPEG: Data([0x01, 0x02]), imageID: id,
            config: config, apiKey: key, transport: transport,
            strictness: 3, language: .english, computedTime: 1_700_000_000)
        XCTAssertTrue(verdict.isSentinel)
        XCTAssertEqual(verdict.reasons, ["subject unrecognizable"])

        // The sentinel ROW: rating 0 + reasons JSON non-empty (D-4 shape).
        let row = try await latestRatingRow(id)
        let stored = try XCTUnwrap(row)
        XCTAssertEqual(stored.rating, 0)
        let reasons = try XCTUnwrap(stored.reasons)
        XCTAssertTrue(reasons.contains("subject unrecognizable"))
        XCTAssertEqual(stored.taskID, AIRatingService.taskID)
        XCTAssertEqual(stored.modelID, "vision-test")
        XCTAssertEqual(
            stored.providerID, AICredentialStore.ratingProviderAccount)
        XCTAssertEqual(stored.computedTime, 1_700_000_000)
        // The profile id matches the rubric actually assembled.
        let rubric = AIRatingService.rubricText(strictness: 3, language: .english)
        XCTAssertEqual(
            stored.promptProfileID,
            AIRatingService.promptProfileID(
                rubric: rubric, protocol: config.protocol, model: config.model))

        // THE NEGATIVE CONFIRM-GATE PIN: rate() alone never writes the star.
        let rating = try await imagesRating(id)
        XCTAssertNil(rating, "sentinel flow must not touch images.rating")
    }

    func testRateAppendsRealStarRowThenApplyStarsWritesTheColumn() async throws {
        let id = imageIDs[1]
        let transport = transport(returning: #"{"rating": 4, "reasons": ["sharp", "balanced"]}"#)
        let verdict = try await ratingService.rate(
            imageJPEG: Data([0x03]), imageID: id,
            config: config, apiKey: key, transport: transport,
            strictness: 5, language: .english, computedTime: 1_700_000_100)
        XCTAssertEqual(verdict.stars, 4)
        let beforeGate = try await imagesRating(id)
        XCTAssertNil(beforeGate, "not before the confirm gate")

        // The OQ-11-A 应用 leg.
        try await ratingService.applyStars(4, to: id)
        let afterGate = try await imagesRating(id)
        XCTAssertEqual(afterGate, 4)
    }

    func testApplyStarsRejectsOutOfRangeAndSentinelValues() async throws {
        let id = imageIDs[2]
        for invalid in [0, 6, -1] {
            do {
                try await ratingService.applyStars(invalid, to: id)
                XCTFail("expected starsOutOfRange(\(invalid))")
            } catch let error as AIRatingError {
                XCTAssertEqual(error, .starsOutOfRange(invalid))
            }
        }
        let untouched = try await imagesRating(id)
        XCTAssertNil(untouched)
    }

    // MARK: - describe() → reconcile + FTS (the E5 join face)

    func testDescribeReconcilesAndFTSMatchesThroughActiveJoin() async throws {
        let id = imageIDs[0]
        let transport = transport(returning: """
            {"caption": "a golden retriever running on the beach", "tags": ["dog", "beach"], "scene": "outdoor", "confidence": 0.92}
            """)
        let description = try await descriptionService.describe(
            imageJPEG: Data([0x07]), imageID: id,
            config: config, apiKey: key, transport: transport,
            computedTime: 1_700_000_200)
        XCTAssertEqual(description.caption, "a golden retriever running on the beach")
        XCTAssertEqual(description.tags, ["dog", "beach"])
        XCTAssertEqual(description.scene, "outdoor")
        XCTAssertEqual(description.confidence, 0.92)

        // FTS MATCH → JOIN active=1 → the image.
        let hits = try await AIDescriptionService.imageIDs(
            matching: "beach", store: fileStore)
        XCTAssertEqual(hits, [id])
        let tagHit = try await AIDescriptionService.imageIDs(
            matching: "retriever", store: fileStore)
        XCTAssertEqual(tagHit, [id])

        // The row shape: reconcile defaults + the description profile id.
        let semantic = SemanticStore(store: fileStore)
        let rows = try await semantic.understandings(imageID: id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].active)
        XCTAssertEqual(rows[0].row.taskID, AIDescriptionService.taskID)
        XCTAssertEqual(rows[0].row.renditionKind, "edited", "the default rendition")
        XCTAssertTrue(
            rows[0].row.promptProfileID.allSatisfy { $0.isNumber },
            "the profile id is a decimal string (L013)")
    }

    func testE5InactiveSiblingTaskRowStaysIndexedButNeverMatches() async throws {
        let id = imageIDs[0]
        // Task A (the plan's description flow) describes the image.
        _ = try await descriptionService.describe(
            imageJPEG: Data([0x01]), imageID: id,
            config: config, apiKey: key,
            transport: transport(returning: #"{"caption": "sunny beach with umbrellas", "tags": []}"#),
            computedTime: 1)
        // A sibling-task row (a future worker's task family) reconciles —
        // the OQ-9-style demotion flips task A's row to active=0, AND the
        // external-content index keeps it (no active concept in FTS).
        let semantic = SemanticStore(store: fileStore)
        try await semantic.replaceUnderstanding(SemanticStore.UnderstandingRow(
            imageID: id, taskID: "description-future-worker",
            providerID: "p", modelID: "m", promptProfileID: "1",
            caption: "forsaken industrial ruins at dusk", tags: "[]",
            computedTime: 2))

        // The active row matches…
        let activeHits = try await AIDescriptionService.imageIDs(
            matching: "ruins", store: fileStore)
        XCTAssertEqual(activeHits, [id])
        // …and the DEMOTED row's words — still indexed (the index has no
        // active concept) — must NOT match through the JOIN (E5 negative).
        let staleHits = try await AIDescriptionService.imageIDs(
            matching: "umbrellas", store: fileStore)
        XCTAssertTrue(
            staleHits.isEmpty,
            "an active=0 row matched — the fulltext leg leaks stale captions")

        // Row-level proof the stale row IS in the index (the leak the join
        // prevents): a raw MATCH without the join would find it.
        try await fileStore.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT count(*) FROM ai_understanding_fts WHERE ai_understanding_fts MATCH ?")
            try statement.bindText(1, "\"umbrellas\"")
            _ = try statement.step()
            XCTAssertGreaterThan(statement.columnInt(0) ?? 0, 0)
        }
    }

    func testSameTaskRerunUnstagesOldWordsAndFlipsRenditionKind() async throws {
        let id = imageIDs[1]
        _ = try await descriptionService.describe(
            imageJPEG: Data([0x01]), imageID: id,
            config: config, apiKey: key,
            transport: transport(returning: #"{"caption": "red apple on white table", "tags": ["fruit"]}"#),
            computedTime: 1)
        // Re-run (same task), now against the ORIGINAL rendition, new words.
        _ = try await descriptionService.describe(
            imageJPEG: Data([0x02]), imageID: id,
            config: config, apiKey: key,
            transport: transport(returning: #"{"caption": "city skyline at night", "tags": ["city"]}"#),
            renditionKind: "original", computedTime: 2)

        // The old words are UNSTAGED (explicit DELETE fired the trigger —
        // the L059 mirror through the service path).
        let oldHits = try await AIDescriptionService.imageIDs(
            matching: "apple", store: fileStore)
        XCTAssertTrue(oldHits.isEmpty)
        let newHits = try await AIDescriptionService.imageIDs(
            matching: "skyline", store: fileStore)
        XCTAssertEqual(newHits, [id])

        let semantic = SemanticStore(store: fileStore)
        let rows = try await semantic.understandings(imageID: id)
        XCTAssertEqual(rows.count, 1, "same-task reconcile replaces, not appends")
        XCTAssertEqual(rows[0].row.renditionKind, "original", "the explicit kind")
        XCTAssertEqual(rows[0].row.caption, "city skyline at night")
    }

    func testDescribeContractParseClampsConfidenceAndDefaultsTags() throws {
        let description = try AIDescriptionService.parse(
            #"{"caption": "only a caption"}"#)
        XCTAssertEqual(description.caption, "only a caption")
        XCTAssertEqual(description.tags, [])
        XCTAssertNil(description.scene)
        XCTAssertNil(description.confidence)

        let clamped = try AIDescriptionService.parse(
            #"{"caption": "c", "tags": ["t"], "confidence": 1.7}"#)
        XCTAssertEqual(clamped.confidence, 1.0)

        XCTAssertThrowsError(try AIDescriptionService.parse(#"{"tags": []}"#))
    }

    // MARK: - fulltext query sanitize

    func testFulltextSanitizesSyntaxCharacters() async throws {
        // FTS5 operators in user input must never explode the query.
        let hits = try await AIDescriptionService.imageIDs(
            matching: "beach (sunset) \" OR 1=1 --", store: fileStore)
        _ = hits  // the assertion is: NO throw, honest result set
        XCTAssertEqual(AIDescriptionService.ftsMatchQuery("a \"b\" c"), "\"a\" \"\"\"b\"\"\" \"c\"")
        XCTAssertTrue(AIDescriptionService.ftsMatchQuery("   ").isEmpty)
        let empty = try await AIDescriptionService.imageIDs(
            matching: "   ", store: fileStore)
            XCTAssertTrue(empty.isEmpty)
    }

    func testFulltextZeroHitsIsHonestEmpty() async throws {
        let hits = try await AIDescriptionService.imageIDs(
            matching: "nonexistentword", store: fileStore)
        XCTAssertTrue(hits.isEmpty)
    }
}
