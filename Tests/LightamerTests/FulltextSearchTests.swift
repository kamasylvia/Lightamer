import Foundation
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FulltextSearchTests (Plan M2-10-04 T4, AC#5/7) — two APP-level families over
// a REAL `.lalb` package:
//
// THE FULLTEXT SUBMIT LEG (KD-4): LibrarySearchModel.submitFulltext rides the
// Core E5 join (AIDescriptionService.imageIDs: FTS MATCH → JOIN active=1) and
// folds the hit set into the grid's overlay — the CLIP leg's exact shape,
// rank-ordered:
//   • hits overlay the collection in rank order
//   • zero hits install the EMPTY result set (the honest count card)
//   • empty input clears the leg
//   • no query face = the typed .fulltextUnavailable family
//   • the EXIF and fulltext legs stay exclusive
//
// THE RATING CONFIRM GATE (OQ-11-A): AIRatingController over a REAL
// AIRatingService — present() alone NEVER writes images.rating (the negative
// pin), confirm/confirmAll write through the real service, sentinel verdicts
// never propose, the 200-row batch cap truncates, the 不再询问 preference
// round-trips and bypasses the gate, a failed write keeps the proposal.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class FulltextSearchTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var semantic: SemanticStore!
    private var queries: LibraryQueries!
    private var grid: LibraryGridModel!
    private var ratingService: AIRatingService!
    private var imageIDs: [Int64] = []

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fulltext-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Fulltext.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Fulltext")
        semantic = SemanticStore(store: fileStore)
        queries = LibraryQueries(store: fileStore)
        grid = LibraryGridModel(queries: queries, pageSize: 5)
        ratingService = AIRatingService(store: fileStore)
        imageIDs = try await seed()
        try await grid.reloadFirstPage()
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        semantic = nil
        grid = nil
        queries = nil
        ratingService = nil
        fileStore = nil
        try await super.tearDown()
    }

    /// Three images; the first two carry active understanding rows.
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
        try await semantic.replaceUnderstanding(SemanticStore.UnderstandingRow(
            imageID: ids[0], taskID: "description", providerID: "p",
            modelID: "m", promptProfileID: "111",
            caption: "a golden beach at sunset", tags: #"["beach","sunset"]"#,
            computedTime: 1))
        try await semantic.replaceUnderstanding(SemanticStore.UnderstandingRow(
            imageID: ids[1], taskID: "description", providerID: "p",
            modelID: "m", promptProfileID: "111",
            caption: "a misty mountain lake at dawn", tags: #"["lake","mountain"]"#,
            computedTime: 1))
        return ids
    }

    private func makeModel(
        withFulltext: Bool = true
    ) -> LibrarySearchModel {
        let store = fileStore!
        var fulltext: (@Sendable (String) async throws -> [Int64])?
        if withFulltext {
            fulltext = { query in
                try await AIDescriptionService.imageIDs(
                    matching: query, store: store)
            }
        }
        return LibrarySearchModel(grid: grid, fulltext: fulltext)
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

    // MARK: - the fulltext submit leg

    func testFulltextHitsFoldIntoTheOverlay() async throws {
        let model = makeModel()
        model.select(mode: .fullText)
        let outcome = await model.submit("beach")
        XCTAssertEqual(outcome, .semanticApplied(hitCount: 1))
        XCTAssertEqual(grid.semanticHits, [imageIDs[0]])
        // The overlay IS the collection: only the hit renders.
        XCTAssertEqual(grid.rows.map(\.id), [imageIDs[0]])
    }

    func testFulltextZeroHitsInstallsTheEmptyResultSet() async throws {
        let model = makeModel()
        model.select(mode: .fullText)
        let outcome = await model.submit("zebra")
        XCTAssertEqual(outcome, .semanticApplied(hitCount: 0))
        // The empty set IS installed (the honest count card shows 0) —
        // not a silent no-op, not a fabricated pass-through.
        XCTAssertEqual(grid.semanticHits, [])
        XCTAssertTrue(grid.rows.isEmpty)
    }

    func testFulltextEmptyInputClearsTheLeg() async throws {
        let model = makeModel()
        model.select(mode: .fullText)
        _ = await model.submit("beach")
        XCTAssertEqual(grid.semanticHits, [imageIDs[0]])
        let outcome = await model.submit("   ")
        XCTAssertEqual(outcome, .applied(termCount: 0))
        XCTAssertNil(grid.semanticHits)
        XCTAssertEqual(grid.rows.count, 3)
    }

    func testFulltextWithoutQueryFaceIsHonestUnavailable() async {
        let model = makeModel(withFulltext: false)
        model.select(mode: .fullText)
        let outcome = await model.submit("beach")
        XCTAssertEqual(
            outcome, .failed(.fulltextUnavailable),
            "no assembly-provided query face = the honest family, never a fake result")
        XCTAssertNil(grid.semanticHits)
    }

    func testEXIFAndFulltextLegsAreExclusive() async throws {
        let model = makeModel()
        model.select(mode: .fullText)
        _ = await model.submit("beach")
        XCTAssertEqual(grid.semanticHits, [imageIDs[0]])
        // An EXIF application EXITS the overlay (LibraryGridModel semantics).
        model.select(mode: .exif)
        _ = await model.submit("iso800")
        XCTAssertNil(grid.semanticHits)
        XCTAssertEqual(grid.rows.count, 1, "the EXIF leg landed")
    }

    func testFulltextQueryFailureIsTheRuntimeFamily() async {
        let model = LibrarySearchModel(
            grid: grid,
            fulltext: { _ in throw LibraryError.notOpen })
        model.select(mode: .fullText)
        let outcome = await model.submit("beach")
        XCTAssertEqual(outcome, .failed(.semanticQueryFailed))
    }

    // MARK: - the rating confirm gate (OQ-11-A)

    private func makeController(
        suiteName: String? = "fulltext-tests-\(UUID().uuidString)"
    ) -> AIRatingController {
        let service = ratingService!
        return AIRatingController(
            preferences: RatingConfirmPreferences(defaultsSuiteName: suiteName),
            applyStars: { stars, imageID in
                try await service.applyStars(stars, to: imageID)
            })
    }

    func testPresentAloneNeverWritesImagesRating() async throws {
        let controller = makeController()
        controller.present([
            (imageIDs[0], AIRatingVerdict(stars: 4, reasons: ["sharp"])),
            (imageIDs[1], AIRatingVerdict(stars: 2, reasons: ["soft"])),
        ])
        XCTAssertEqual(controller.pendingProposals.count, 2)
        // THE NEGATIVE PIN: the gate is the only protection — presenting
        // writes nothing.
        for id in imageIDs {
            let rating = try await imagesRating(id)
            XCTAssertNil(rating, "present() must not touch images.rating")
        }
    }

    func testConfirmWritesOneProposalAndClearsIt() async throws {
        let controller = makeController()
        controller.present([
            (imageIDs[0], AIRatingVerdict(stars: 4, reasons: ["sharp"])),
            (imageIDs[1], AIRatingVerdict(stars: 2, reasons: ["soft"])),
        ])
        try await controller.confirm(controller.pendingProposals[0])
        let first = try await imagesRating(imageIDs[0])
        XCTAssertEqual(first, 4)
        let second = try await imagesRating(imageIDs[1])
        XCTAssertNil(second, "the other row waits")
        XCTAssertEqual(controller.pendingProposals.map(\.imageID), [imageIDs[1]])
    }

    func testConfirmAllWritesEveryProposal() async throws {
        let controller = makeController()
        controller.present([
            (imageIDs[0], AIRatingVerdict(stars: 5, reasons: ["exhibit"])),
            (imageIDs[1], AIRatingVerdict(stars: 3, reasons: ["usable"])),
        ])
        try await controller.confirmAll()
        let first = try await imagesRating(imageIDs[0])
        XCTAssertEqual(first, 5)
        let second = try await imagesRating(imageIDs[1])
        XCTAssertEqual(second, 3)
        XCTAssertTrue(controller.pendingProposals.isEmpty)
    }

    func testSentinelVerdictsNeverPropose() async {
        let controller = makeController()
        controller.present([
            (imageIDs[0], AIRatingVerdict(stars: 0, reasons: ["refused"])),
        ])
        XCTAssertTrue(
            controller.pendingProposals.isEmpty,
            "a sentinel's record IS the ai_rating row — the star gate never sees it")
    }

    func testBatchCapTruncatesAndReportsTheDrop() async {
        let controller = makeController()
        let verdicts = (0..<AIRatingController.batchLimit + 5).map { index in
            (imageIDs[index % imageIDs.count], AIRatingVerdict(stars: 3, reasons: []))
        }
        controller.present(verdicts)
        XCTAssertEqual(controller.pendingProposals.count, AIRatingController.batchLimit)
        XCTAssertEqual(controller.droppedByCap, 5)
    }

    func testDontAskPreferenceRoundTripAndBypass() {
        let suiteName = "fulltext-prefs-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let preferences = RatingConfirmPreferences(defaultsSuiteName: suiteName)
        // Default: ALWAYS confirm (false = the gate shows).
        XCTAssertFalse(preferences.skipConfirmation)
        preferences.setSkipConfirmation(true)
        XCTAssertTrue(preferences.skipConfirmation, "不再询问 = the caller applies directly")
        preferences.reset()
        XCTAssertFalse(preferences.skipConfirmation)

        let service = ratingService!
        let controller = AIRatingController(
            preferences: RatingConfirmPreferences(defaultsSuiteName: suiteName),
            applyStars: { stars, imageID in
                try await service.applyStars(stars, to: imageID)
            })
        controller.present([
            (imageIDs[0], AIRatingVerdict(stars: 4, reasons: [])),
        ])
        // The caller's bypass path reads the same face:
        preferences.setSkipConfirmation(true)
        XCTAssertTrue(controller.confirmationBypassed)
    }

    func testFailedWriteKeepsTheProposalPending() async throws {
        let failing = AIRatingController(
            preferences: RatingConfirmPreferences(
                defaultsSuiteName: "fulltext-fail-\(UUID().uuidString)"),
            applyStars: { _, _ in throw LibraryError.notOpen })
        failing.present([
            (imageIDs[0], AIRatingVerdict(stars: 4, reasons: [])),
        ])
        do {
            try await failing.confirm(failing.pendingProposals[0])
            XCTFail("expected the write to throw")
        } catch {}
        XCTAssertEqual(
            failing.pendingProposals.count, 1,
            "a failed write must not silently vanish the proposal")
        // And the column is untouched.
        let rating = try await imagesRating(imageIDs[0])
        XCTAssertNil(rating)
    }
}
