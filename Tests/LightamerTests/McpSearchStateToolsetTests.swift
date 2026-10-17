import Foundation
import LightamerCore
import LightamerIOP
import MCP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan M7-2-01 T5 — the search/state domain tests over a REAL `.lalb`
// package:
//
//   • the domain snapshot layer (the 3 read-only tools verbatim; the
//     registry without the searchState seam stays at the editing+culling
//     face (23 since M7-4 — the control domain is the independent fifth
//     domain and does not touch either)
//   • the EXIF parity golden: the tool's cursor-chain walk ≡ the GUI
//     two-segment walk (direct searchPage + searchNullTail concat) — the
//     fixture MUST carry NULL-key rows (unrated + no-capture-date) and the
//     walk must reach them through the flip (review E-2's blind-spot fix)
//   • the CLIP leg with a mock SemanticSearching (CI carries zero model
//     assets) + the modelUnavailable family mapping incl. the
//     AIWorkerClientError cases (review F-3)
//   • the fulltext leg ≡ AIDescriptionService.imageIDs direct (rank order)
//   • get_history golden over a real sidecar document (all five kinds + a
//     double-payload paste item + version meta + the F-5 truncation
//     direction)
//   • get_state: the headless nulls contract + the live-snapshot arm with
//     the MainActor-hop double judgment (review F-6 ①; ② is the T6 grep)
//   • McpToolError 16-value exhaustive codes
//   • the read-only exemption face (no writer gate, no counter, no probe)
//   • the T4 two-process judgment (F-2 甲): a held-project headless child
//     serves search_photos over HTTP, discovered through the READONLY
//     endpoint file
// ─────────────────────────────────────────────────────────────────────────────

final class McpSearchStateToolsetTests: XCTestCase {

    // MARK: - Fixture (the 12-row library shape: 4 unrated rows + 1
    // no-capture-date row — the NULL-key classes the parity golden must
    // reach through the segment flip)

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var queries: LibraryQueries!

    private struct SeedRow {
        var path: String
        var make: String?
        var model: String?
        var iso: Int64?
        var focal: Double?
        var date: Double?
        var rating: Int64?
        var filename: String
    }

    /// day epochs (2024-06-01..03 12:00 UTC).
    private let day1: Double = 1_717_224_000
    private let day2: Double = 1_717_310_400
    private let day3: Double = 1_717_396_800

    private static let rows: [SeedRow] = [
        .init(path: "Media/00.arw", make: "Sony", model: "A7R V", iso: 800,
              focal: 24, date: 1_717_224_000, rating: 5, filename: "00.arw"),
        .init(path: "Media/01.arw", make: "Sony", model: "A7R V", iso: 800,
              focal: 35, date: 1_717_227_600, rating: 4, filename: "01.arw"),
        .init(path: "Media/02.arw", make: "Canon", model: "EOS R5", iso: 100,
              focal: 50, date: 1_717_231_200, rating: nil, filename: "02.arw"),
        .init(path: "Media/03.arw", make: "Canon", model: "EOS R5", iso: 200,
              focal: 50, date: 1_717_310_400, rating: 3, filename: "03.arw"),
        .init(path: "Media/04.arw", make: "Canon", model: "EOS R5", iso: 400,
              focal: nil, date: 1_717_314_000, rating: nil, filename: "04.arw"),
        .init(path: "Media/05.nef", make: nil, model: nil, iso: 8000,
              focal: 85, date: 1_717_317_600, rating: 2, filename: "05.nef"),
        .init(path: "Media/06.raf", make: "Fujifilm", model: "X-T5", iso: 1600,
              focal: 35, date: 1_717_321_200, rating: nil, filename: "06.raf"),
        .init(path: "Media/07.arw", make: "Sony", model: nil, iso: 3200,
              focal: 24, date: 1_717_396_800, rating: 4, filename: "07.arw"),
        .init(path: "Media/08.arw", make: nil, model: nil, iso: 6400,
              focal: nil, date: 1_717_400_400, rating: nil, filename: "08.arw"),
        .init(path: "Media/09.arw", make: "Canon", model: "EOS R5", iso: 800,
              focal: 200, date: nil, rating: 1, filename: "09.arw"),
        .init(path: "Media/10.arw", make: "Sony", model: "A7R V", iso: 800,
              focal: 35, date: 1_717_224_000, rating: 5, filename: "10.arw"),
        .init(path: "Media/11.arw", make: "Sony", model: "A7R V", iso: 800,
              focal: 35, date: 1_717_227_600, rating: nil, filename: "11.arw"),
    ]

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-search-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Media", isDirectory: true),
            withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("SearchState.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "SearchState")
        queries = LibraryQueries(store: fileStore)
        for row in Self.rows {
            // A real file per row (the get_history digits arm resolves
            // through the linker, which stats the path).
            try Data(repeating: 0xAB, count: 16)
                .write(to: tempDirectory.appendingPathComponent(row.path))
        }
        try await seedRows()
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func seedRows() async throws {
        try await fileStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, camera_make,
                    camera_model, iso, focal_length, capture_date, rating,
                    file_stem, exif_search_text, exif_search_words, filename,
                    dir)
                VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for (index, row) in Self.rows.enumerated() {
                let stem = String(format: "DSC%05d", index)
                let facts = ExifFold.Facts(
                    fileStem: stem,
                    cameraMake: row.make, cameraModel: row.model,
                    lensModel: nil, iso: row.iso.map(Int.init),
                    focalLength: row.focal, aperture: nil,
                    captureDate: row.date.map { Date(timeIntervalSince1970: $0) })
                let folded = ExifFold.foldedVariants(for: facts)
                try insert.reset()
                try insert.bindText(1, row.path)
                try insert.bindText(2, row.make)
                try insert.bindText(3, row.model)
                try insert.bindInt(4, row.iso)
                try insert.bindDouble(5, row.focal)
                try insert.bindDouble(6, row.date)
                try insert.bindInt(7, row.rating)
                try insert.bindText(8, stem)
                try insert.bindText(9, folded.text)
                try insert.bindText(10, folded.words)
                try insert.bindText(11, row.filename)
                try insert.bindText(12, "Media")
                _ = try insert.step()
            }
            return true
        }
    }

    /// The all-nil context bound to this fixture (the library seam lives;
    /// every optional face absent = the typed honest arms).
    private func libraryProvider()
        -> (@Sendable () async -> (store: ProjectFileStore, projectDirectory: URL)?)?
    {
        { [packageURL, fileStore] in
            (store: fileStore, projectDirectory: packageURL.deletingLastPathComponent())
        }
    }

    private func makeRegistry(
        context: McpSearchStateContext? = nil
    ) async -> McpToolRegistry {
        await McpServerController.makeRegistry(searchState: context)
    }

    // MARK: - Call helpers

    private static func callJSON(
        _ registry: McpToolRegistry, name: String,
        arguments: [String: McpJSON] = [:], file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [String: Any] {
        let output = try await registry.call(name: name, arguments: arguments)
        guard case .text(let text) = output.content.first else {
            XCTFail("expected a text payload", file: file, line: line)
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(object as? [String: Any], file: file, line: line)
    }

    private static func toolError(
        of body: () async throws -> Void, file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> McpToolError {
        do {
            try await body()
        } catch let error as McpToolError {
            return error
        } catch {
            XCTFail("unexpected non-typed error: \(error)", file: file, line: line)
            throw error
        }
        XCTFail("expected a typed McpToolError", file: file, line: line)
        throw McpToolError.internalError("unreachable")
    }

    private static func resultIDs(_ payload: [String: Any]) -> [Int64] {
        let results = payload["results"] as? [[String: Any]] ?? []
        return results.compactMap { ($0["imageID"] as? Int).map(Int64.init) }
    }

    // MARK: - The domain snapshot layer (the fourth snapshot layer)

    /// The 3-tool face verbatim (schemas byte-equal the registration
    /// source; every tool read-only). The count 23 rides the UNION file —
    /// this layer pins the domain's own three rows.
    func testSearchStateDomainSnapshotVerbatim() async throws {
        let registry = await makeRegistry(context: McpSearchStateContext())
        let descriptors = await registry.descriptors()
        XCTAssertEqual(
            Set(descriptors.map(\.name)),
            ["get_history", "get_state", "search_photos"])
        for descriptor in descriptors where
            ["get_history", "get_state", "search_photos"].contains(descriptor.name) {
            XCTAssertEqual(descriptor.readOnlyHint, true, descriptor.name)
            XCTAssertNil(descriptor.destructiveHint, descriptor.name)
            XCTAssertFalse(descriptor.description.isEmpty, descriptor.name)
            // The dual-domain boundary sentence (D-M7-2-1) lives in the
            // search_photos description verbatim.
            if descriptor.name == "search_photos" {
                XCTAssertTrue(
                    descriptor.description.contains("OPEN LIBRARY")
                        // The zh catalog entry shadows the en defaultValue
                        // in this host locale — the boundary sentence must
                        // ride EITHER face (the T6 grep pins the en source).
                        || descriptor.description.contains("打开的图库"),
                    "the addressing boundary must name the domain: \(descriptor.description.prefix(120))")
                XCTAssertTrue(
                    descriptor.description.contains("list_photos"))
            }
            if descriptor.name == "get_state" {
                XCTAssertTrue(
                    descriptor.description.contains("MOMENTARY")
                        || descriptor.description.contains("一次性快照"),
                    "the hot-state caveat must ride the description: \(descriptor.description.prefix(120))")
            }
        }
        // The schema faces: verbatim terminal forms.
        let search = try XCTUnwrap(
            descriptors.first { $0.name == "search_photos" })
        XCTAssertTrue(
            search.inputSchemaJSON.contains("\"enum\":[\"exif\",\"clip\",\"fulltext\"]"),
            search.inputSchemaJSON)
        XCTAssertTrue(
            search.inputSchemaJSON.contains("\"required\":[\"query\"]"),
            search.inputSchemaJSON)
        let history = try XCTUnwrap(descriptors.first { $0.name == "get_history" })
        XCTAssertTrue(
            history.inputSchemaJSON.contains("\"required\":[\"image\"]"),
            history.inputSchemaJSON)
        XCTAssertTrue(history.inputSchemaJSON.contains("includeParams"),
                      history.inputSchemaJSON)
        let state = try XCTUnwrap(descriptors.first { $0.name == "get_state" })
        XCTAssertEqual(state.inputSchemaJSON, #"{"type":"object","properties":{},"required":[]}"#)
    }

    /// The zero-diff negative: WITHOUT the searchState seam the registry is
    /// byte-identical to the pre-M7-2 face grown by list_luts (the editing
    /// domain's own M7-3 addition) — the negative's semantics ("no new
    /// domain without its context") is unchanged; the count rides 23
    /// (editing 9 + culling 14 since M7-4 — the control domain is the
    /// independent fifth domain and does not touch either).
    func testRegistryWithoutSearchStateStaysAtTwenty() async throws {
        let registry = await McpServerController.makeRegistry(
            editing: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }),
            culling: McpServerController.makeCullingContext(session: { nil }))
        let descriptors = await registry.descriptors()
        XCTAssertEqual(
            descriptors.count, 23,
            "the default seam stays nil = 23 (M7-4 copy/paste joined the "
                + "editing domain)")
        XCTAssertFalse(descriptors.contains { $0.name == "search_photos" })
    }

    // MARK: - The EXIF parity golden (ROADMAP acceptance shape ①)

    /// The GUI two-segment walk (the REFERENCE leg): direct
    /// `searchPage` until a short page, then `searchNullTail` from the
    /// tier head — at the golden limit the NULL-key rows never enter a
    /// main page, so the reference is the plain two-segment concat (the
    /// review E-2 shape; the tool must produce the SAME id sequence).
    private func referenceWalk(
        plan: ExifSearchPlan, sort: FilterSort, limit: Int
    ) async throws -> [Int64] {
        let filter = ExifSearchFilter(
            group: FilterPredicateGroup(rules: []), plan: plan)
        var ids: [Int64] = []
        var anchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchPage(
                filter: filter, sort: sort, anchor: anchor, limit: limit)
            ids.append(contentsOf: page.map(\.id))
            guard page.count == limit, let last = page.last,
                let next = LibraryPageAnchor.anchor(of: last, key: sort.key)
            else { break }
            anchor = next
        }
        var tailAnchor: LibraryPageAnchor?
        while true {
            let tail = try await queries.searchNullTail(
                filter: filter, sort: sort, anchor: tailAnchor, limit: limit)
            ids.append(contentsOf: tail.map(\.id))
            guard tail.count == limit, let last = tail.last else { break }
            tailAnchor = LibraryPageAnchor(
                keyValue: FilterSQLBind.int(nil), imagePath: last.imagePath)
        }
        return ids
    }

    /// The tool's cursor-chain walk (the TOOL leg): calls search_photos
    /// until nextCursor is nil, recording every flip's segment.
    private func toolWalk(
        registry: McpToolRegistry, query: String, sortArguments: [String: McpJSON],
        limit: Int
    ) async throws -> (ids: [Int64], segments: [String]) {
        var ids: [Int64] = []
        var segments: [String] = []
        var cursor: String?
        var arguments: [String: McpJSON] = [
            "query": .string(query), "limit": .int(limit),
        ]
        for (key, value) in sortArguments { arguments[key] = value }
        while true {
            if let cursor { arguments["cursor"] = .string(cursor) }
            let payload = try await Self.callJSON(
                registry, name: "search_photos", arguments: arguments)
            ids.append(contentsOf: Self.resultIDs(payload))
            guard let next = payload["nextCursor"] as? String else { break }
            let decoded = try McpSearchStateToolset.SearchCursor.decode(next)
            segments.append(decoded.segment.rawValue)
            cursor = next
        }
        return (ids, segments)
    }

    /// Golden ①: rating ASC — the walk MUST flip into the NULL tier and
    /// reach the four unrated rows (the review-E-2 blind-spot fix).
    func testExifParityGoldenRatingAscReachesUnratedRows() async throws {
        let registry = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider()))
        // The structured term (a plan with NO lexical leg lists all its
        // iso-800 rows) — the flip behavior is pinned across the full
        // page boundary.
        let structured = try ExifSearchParser.parse("iso800")
        let reference = try await referenceWalk(
            plan: structured, sort: FilterSort(key: .rating, ascending: true),
            limit: 3)
        let (toolIDs, segments) = try await toolWalk(
            registry: registry, query: "iso800",
            sortArguments: ["sort": .object([
                "key": .string("rating"), "ascending": .bool(true),
            ])],
            limit: 3)
        XCTAssertEqual(toolIDs, reference, "the tool ≡ the two-segment walk")
        XCTAssertEqual(Set(toolIDs).count, toolIDs.count, "no duplicates")
        XCTAssertTrue(segments.contains("nullTail"), "the walk flipped")
        // The iso-800 UNRATED row is reachable through the flip (it can
        // never appear in an anchored main page — the whole point of E-2).
        let isoUnratedID = try await fileStore.withHandle { handle -> Int64? in
            let statement = try handle.prepare(
                "SELECT id FROM images WHERE rating IS NULL AND iso = 800")
            _ = try statement.step()
            return statement.columnInt(0)
        }
        let unratedID = try XCTUnwrap(isoUnratedID)
        XCTAssertTrue(
            toolIDs.contains(unratedID),
            "the NULL-key row is reachable through the flip: \(toolIDs)")
        XCTAssertEqual(toolIDs.last, unratedID, "the NULL tier walks last")
    }

    /// Golden ②: captureDate DESC — the NULL-date row rides LAST (NULLs
    /// sort last in BOTH directions) and the tool walk reaches it.
    func testExifParityGoldenCaptureDateDescReachesNullDateRow() async throws {
        let registry = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider()))
        let plan = try ExifSearchParser.parse("iso800")
        let reference = try await referenceWalk(
            plan: plan, sort: FilterSort(key: .captureDate, ascending: false),
            limit: 3)
        let (toolIDs, segments) = try await toolWalk(
            registry: registry, query: "iso800",
            sortArguments: ["sort": .object([
                "key": .string("captureDate"), "ascending": .bool(false),
            ])],
            limit: 3)
        XCTAssertEqual(toolIDs, reference)
        XCTAssertTrue(segments.contains("nullTail"))
        // The NULL-date row (Media/09.arw) rides the walk's tail.
        let nullDateRowID = try await fileStore.withHandle { handle -> Int64? in
            let statement = try handle.prepare(
                "SELECT id FROM images WHERE capture_date IS NULL")
            _ = try statement.step()
            return statement.columnInt(0)
        }
        XCTAssertEqual(toolIDs.last, nullDateRowID, "the NULL tier walks last")
        // The parser plan identity (the structural same-source guarantee):
        // the tool's rows for the same query ≡ the direct
        // parse -> searchPage single page.
        let direct = try await queries.searchPage(
            filter: ExifSearchFilter(
                group: FilterPredicateGroup(rules: []), plan: plan),
            sort: FilterSort(key: .captureDate, ascending: false), limit: 3)
        XCTAssertEqual(
            Array(toolIDs.prefix(3)), direct.map(\.id),
            "the tool's first page ≡ the direct parse+searchPage page")
    }

    /// The cursor chain mechanics: the cross-tool token rejection (a
    /// list_photos token — same {k,d,p,v} shape, NO segment), the
    /// sort-mismatch rejection, and the cross-arm combos (N-4).
    func testExifCursorRejectionsAndCrossArmCombos() async throws {
        let registry = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider()))
        let sortRating: [String: McpJSON] = ["sort": .object([
            "key": .string("rating"), "ascending": .bool(true),
        ])]
        // A valid first page issues a flip token (rating: 8 rated rows,
        // limit 5 → full page → nextCursor present).
        let first = try await Self.callJSON(registry, name: "search_photos", arguments: [
            "query": .string("iso800"), "limit": .int(5),
            "sort": sortRating["sort"]!,
        ])
        let token = try XCTUnwrap(first["nextCursor"] as? String)

        // The sort-mismatch negative (换键失效 — the token carries its key).
        try await Self.toolError {
            _ = try await registry.call(name: "search_photos", arguments: [
                "query": .string("iso800"), "cursor": .string(token),
                "sort": .object([
                    "key": .string("filename"), "ascending": .bool(true),
                ]),
            ])
        }
        // A hand-built token WITHOUT the segment field (= a list_photos
        // token shape) is rejected (R-3).
        let noSegmentToken = Data(
            #"{"d":"asc","k":"rating","p":"Media/00.arw","v":{"int":5,"kind":"int"}}"#.utf8
        ).base64EncodedString()
        try await Self.toolError {
            _ = try await registry.call(name: "search_photos", arguments: [
                "query": .string("iso800"), "cursor": .string(noSegmentToken),
            ])
        }
        // Garbage tokens are rejected.
        try await Self.toolError {
            _ = try await registry.call(name: "search_photos", arguments: [
                "query": .string("iso800"), "cursor": .string("not-a-token"),
            ])
        }
        // The cross-arm combos: cursor/sort with clip or fulltext (N-4).
        try await Self.toolError {
            _ = try await registry.call(name: "search_photos", arguments: [
                "query": .string("beach"), "mode": .string("clip"),
                "cursor": .string(token),
            ])
        }
        try await Self.toolError {
            _ = try await registry.call(name: "search_photos", arguments: [
                "query": .string("beach"), "mode": .string("fulltext"),
                "sort": sortRating["sort"]!,
            ])
        }
        // scanEpoch is explicitly out of the library whitelist.
        try await Self.toolError {
            _ = try await registry.call(name: "search_photos", arguments: [
                "query": .string("iso800"),
                "sort": .object([
                    "key": .string("scanEpoch"), "ascending": .bool(true),
                ]),
            ])
        }
        _ = token
    }

    /// The typed error arms: empty query / unrecognized token / disjoint
    /// dates / no open project / semantic seam absent.
    func testSearchPhotosTypedErrorArms() async throws {
        let registry = await makeRegistry(context: McpSearchStateContext())
        // No open project (the all-nil context).
        try await Self.toolError {
            _ = try await registry.call(name: "search_photos", arguments: [
                "query": .string("sony"),
            ])
        }
        // Empty query (the GUI's empty-submit CLEARS the filter — the MCP
        // face has no filter state to clear, so it honestly rejects).
        let emptyError = try await Self.toolError {
            _ = try await registry.call(name: "search_photos", arguments: [
                "query": .string(""),
            ])
        }
        // The library face gates BEFORE the query validation shape errors
        // surface, so re-arm with a live library for the parser errors.
        let registryLive = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider()))
        let parseError = try await Self.toolError {
            _ = try await registryLive.call(name: "search_photos", arguments: [
                "query": .string("isoabc"),
            ])
        }
        XCTAssertEqual(parseError.code, "invalidParams")
        XCTAssertTrue(parseError.message.contains("isoabc"))
        let dateError = try await Self.toolError {
            _ = try await registryLive.call(name: "search_photos", arguments: [
                "query": .string("2024-06 2025-01"),
            ])
        }
        XCTAssertEqual(dateError.code, "invalidParams")
        XCTAssertEqual(emptyError.code, "invalidParams")
        // The semantic seam absent = modelUnavailable (D-M7-2-6 — the
        // honest "not ready" family, never a fake empty result).
        let clipError = try await Self.toolError {
            _ = try await registryLive.call(name: "search_photos", arguments: [
                "query": .string("beach"), "mode": .string("clip"),
            ])
        }
        XCTAssertEqual(clipError.code, "modelUnavailable")
    }

    // MARK: - The CLIP leg (mock — CI carries zero model assets)

    private struct MockSearcher: SemanticSearching {
        var hits: [SemanticSearchHit]
        var error: Error?

        func search(
            _ queryText: String, limit: Int,
            in store: SemanticStore
        ) async throws -> [SemanticSearchHit] {
            if let error { throw error }
            return Array(hits.prefix(limit))
        }
    }

    /// The mock golden: hit order + score projection identity, and the
    /// limit slice.
    func testClipRouteMockGolden() async throws {
        let store = SemanticStore(store: fileStore)
        let hits = [
            SemanticSearchHit(imageID: 7, score: 0.97),
            SemanticSearchHit(imageID: 3, score: 0.81),
            SemanticSearchHit(imageID: 9, score: 0.42),
        ]
        let registry = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider(),
            semanticStore: { [store] in store },
            semantic: { MockSearcher(hits: hits) }))
        let payload = try await Self.callJSON(registry, name: "search_photos", arguments: [
            "query": .string("beach"), "mode": .string("clip"),
        ])
        let results = payload["results"] as? [[String: Any]] ?? []
        XCTAssertEqual(results.compactMap { $0["imageID"] as? Int }, [7, 3, 9])
        let scores = results.compactMap { $0["score"] as? Double }
        XCTAssertEqual(scores.count, 3)
        XCTAssertEqual(scores[0], 0.97, accuracy: 0.001)
        XCTAssertEqual(scores[1], 0.81, accuracy: 0.001)
        XCTAssertEqual(scores[2], 0.42, accuracy: 0.001)
        XCTAssertEqual(results.compactMap { $0["rank"] as? Int }, [0, 1, 2])
        // The limit slice (the bounded top-K).
        let sliced = try await Self.callJSON(registry, name: "search_photos", arguments: [
            "query": .string("beach"), "mode": .string("clip"), "limit": .int(2),
        ])
        XCTAssertEqual((sliced["results"] as? [[String: Any]])?.count, 2)
    }

    /// The modelUnavailable family mapping (D-M7-2-6 + review F-3): the
    /// missing model, the dimension mismatch, and the four
    /// AIWorkerClientError cases all ride the SAME code with leg detail in
    /// the message.
    func testClipRouteErrorFamilyMapping() async throws {
        let store = SemanticStore(store: fileStore)
        func registryFor(_ error: Error) async -> McpToolRegistry {
            await makeRegistry(context: McpSearchStateContext(
                library: libraryProvider(),
                semanticStore: { [store] in store },
                semantic: { MockSearcher(hits: [], error: error) }))
        }
        let mismatchRegistry = await registryFor(SemanticSearchError.dimensionMismatch(
            expected: 512, actual: 768))
        let mismatch = try await Self.toolError {
            _ = try await Self.callJSON(
                mismatchRegistry,
                name: "search_photos",
                arguments: ["query": .string("beach"), "mode": .string("clip")])
        }
        XCTAssertEqual(mismatch.code, "modelUnavailable")
        XCTAssertTrue(mismatch.message.contains("mismatch"))
        let workerRegistry = await registryFor(AIWorkerClientError.workerUnavailable(
            "spawn failed: no executable"))
        let worker = try await Self.toolError {
            _ = try await Self.callJSON(
                workerRegistry,
                name: "search_photos",
                arguments: ["query": .string("beach"), "mode": .string("clip")])
        }
        XCTAssertEqual(worker.code, "modelUnavailable", "the F-3 family mapping")
        XCTAssertTrue(
            worker.message.contains("spawn failed"),
            "the message carries the worker detail")
        let crashedRegistry = await registryFor(AIWorkerClientError.workerCrashed("pipe broke"))
        let crashed = try await Self.toolError {
            _ = try await Self.callJSON(
                crashedRegistry,
                name: "search_photos",
                arguments: ["query": .string("beach"), "mode": .string("clip")])
        }
        XCTAssertEqual(crashed.code, "modelUnavailable")
        let exhaustedRegistry = await registryFor(AIWorkerClientError.workerExhausted)
        let exhausted = try await Self.toolError {
            _ = try await Self.callJSON(
                exhaustedRegistry,
                name: "search_photos",
                arguments: ["query": .string("beach"), "mode": .string("clip")])
        }
        XCTAssertEqual(exhausted.code, "modelUnavailable")
        let failedRegistry = await registryFor(AIWorkerClientError.requestFailed("boom"))
        let failed = try await Self.toolError {
            _ = try await Self.callJSON(
                failedRegistry,
                name: "search_photos",
                arguments: ["query": .string("beach"), "mode": .string("clip")])
        }
        XCTAssertEqual(failed.code, "modelUnavailable",
                       "the fourth family case closes F-3 (N2-4)")
    }

    // MARK: - The fulltext leg (rank identity vs the Core seam)

    func testFulltextRouteRankIdentity() async throws {
        let semantic = SemanticStore(store: fileStore)
        let ids = try await fileStore.withHandle { handle -> [Int64] in
            let statement = try handle.prepare(
                "SELECT id, image_path FROM images ORDER BY id")
            var ids: [Int64] = []
            while try statement.step() { ids.append(statement.columnInt(0)!) }
            return ids
        }
        // Two understanding rows (rows 0 and 2 — the FTS leg).
        try await semantic.replaceUnderstanding(SemanticStore.UnderstandingRow(
            imageID: ids[0], taskID: "description", providerID: "p",
            modelID: "m", promptProfileID: "111",
            caption: "a golden beach at sunset",
            tags: #"["beach","sunset"]"#, computedTime: 1))
        try await semantic.replaceUnderstanding(SemanticStore.UnderstandingRow(
            imageID: ids[2], taskID: "description", providerID: "p",
            modelID: "m", promptProfileID: "111",
            caption: "mountain fog at dawn",
            tags: #"["mountain","fog"]"#, computedTime: 2))
        let registry = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider(),
            fulltext: { [fileStore] query in
                try await AIDescriptionService.imageIDs(
                    matching: query, store: fileStore)
            }))
        let payload = try await Self.callJSON(registry, name: "search_photos", arguments: [
            "query": .string("beach"), "mode": .string("fulltext"),
        ])
        let direct = try await AIDescriptionService.imageIDs(
            matching: "beach", store: fileStore)
        XCTAssertEqual(
            Self.resultIDs(payload), direct,
            "the tool ≡ the imageIDs direct call (bm25 rank order)")
        // The limit slice keeps the head of the rank order.
        let sliced = try await Self.callJSON(registry, name: "search_photos", arguments: [
            "query": .string("beach"), "mode": .string("fulltext"), "limit": .int(1),
        ])
        XCTAssertEqual(Self.resultIDs(sliced), Array(direct.prefix(1)))
    }

    // MARK: - get_history golden

    /// Builds the golden sidecar document: all five kinds + the
    /// double-payload paste item (pasteSet + stackSnapshot riding ONE
    /// item — the N-5 review pin) + three version records + the metadata
    /// face. Returns the image row id.
    /// - Parameters:
    ///   - positionOverride: rebuilds the stack at this position (the F8
    ///     red-tail fixture — an UNDONE tail item; M7-4-01).
    private func makeGoldenSidecar(positionOverride: Int? = nil) async throws -> Int64 {
        let imageURL = tempDirectory.appendingPathComponent("Media/golden.arw")
        try Data(repeating: 0xCD, count: 32).write(to: imageURL)
        let record = LibraryImageRecord(
            imagePath: "Media/golden.arw", pathKind: .projectRelative,
            fileStem: "golden", fileExt: "arw", filename: "golden.arw",
            dir: "Media")
        let id = try await LibraryStore(store: fileStore)
            .insertImage(record: record)

        let exposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())
        var stack = HistoryStack()
        stack.commit(exposure, label: "Exposure 2.0×")
        stack.commit(
            exposure, label: "Add layer",
            stackSnapshot: LayerStackSnapshot(
                layers: [.init(AdjustmentLayer(name: "L1"))]))
        // The DOUBLE-payload paste: pasteSet AND stackSnapshot on ONE item.
        stack.commitPaste(
            records: [exposure, ModuleInstance(
                module: ExposureModule.self, params: ExposureModule.Params())],
            label: "Paste look", timestamp: Date(timeIntervalSince1970: 100),
            scope: nil,
            stackSnapshot: LayerStackSnapshot(
                layers: [.init(AdjustmentLayer(name: "Pasted"))]))
        stack.commitDrt(
            record: DrtRecord(), placeholder: exposure, label: "DRT tweak",
            timestamp: Date(timeIntervalSince1970: 200))
        stack.commitFilm(
            record: FilmRecord(), placeholder: exposure, label: "Film look",
            timestamp: Date(timeIntervalSince1970: 300))
        // M7-4-01: the drt item carries an MCP stamp (note + author) — the
        // attribution face's golden anchor.
        var stamped = stack.items
        stamped[3].note = "tuned via MCP"
        stamped[3].author = "mcp"
        stack = HistoryStack(items: stamped, position: stack.position)
        if let positionOverride {
            stack = HistoryStack(items: stack.items, position: positionOverride)
        }

        var chainedA = HistoryStack()
        chainedA.commit(exposure, label: "vA")
        var chainedB = HistoryStack()
        chainedB.commit(exposure, label: "vB")
        let versions = [
            SidecarVersionRecord(
                id: UUID(), name: "Alt A", createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 11), chain: chainedA),
            SidecarVersionRecord(
                id: UUID(), name: "Alt B", createdAt: Date(timeIntervalSince1970: 20),
                updatedAt: Date(timeIntervalSince1970: 21), chain: chainedB),
            SidecarVersionRecord(
                id: UUID(), name: "Main", createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 31), chain: nil),
        ]
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "RAW8", decodeParamsHash: 7,
            instances: [exposure], history: stack, historyHash: 9,
            rating: 4, flag: 1, colorLabel: 2, keywords: ["Nature|Flower"],
            note: "agent visible note", versions: versions,
            activeVersionID: versions[2].id.uuidString)
        let sidecarURL = LightamerSidecar.sidecarURL(for: imageURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: sidecarURL)
        return id
    }

    func testGetHistoryGoldenProjection() async throws {
        let id = try await makeGoldenSidecar()
        let registry = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider()))
        let payload = try await Self.callJSON(registry, name: "get_history", arguments: [
            "image": .string(String(id)),
        ])
        XCTAssertEqual(payload["position"] as? Int, 4)
        XCTAssertEqual(payload["itemCount"] as? Int, 5)
        XCTAssertEqual(payload["truncated"] as? Bool, false)
        // M7-4-01: the top-level author is the POSITION item's author (the
        // truth-value form) — position 4 = the film item, which carries
        // none, so .null (the stamped drt item is NOT the position item).
        XCTAssertEqual(payload["author"] as? NSNull, NSNull(),
                       "the position item (film) carries no author")
        XCTAssertEqual(payload["note"] as? String, "agent visible note")
        XCTAssertEqual(payload["rating"] as? Int, 4)
        XCTAssertEqual(payload["flag"] as? Int, 1)
        XCTAssertEqual(payload["colorLabel"] as? Int, 2)
        XCTAssertEqual(payload["keywords"] as? [String], ["Nature|Flower"])
        XCTAssertNotNil(payload["activeVersionID"], "the key rides the payload")

        let items = try XCTUnwrap(payload["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 5)
        // The five kinds in order (the double-payload paste still classifies
        // as paste — the payload-specificity priority, N-5).
        XCTAssertEqual(items.map { $0["kind"] as? String },
                       ["param", "structure", "paste", "drt", "film"])
        XCTAssertEqual(items[0]["label"] as? String, "Exposure 2.0×")
        // M7-4-01: the per-item note/author keys — only the stamped drt
        // row carries them; every other row answers .null.
        XCTAssertEqual(items[3]["note"] as? String, "tuned via MCP")
        XCTAssertEqual(items[3]["author"] as? String, "mcp")
        for (index, item) in items.enumerated() where index != 3 {
            XCTAssertEqual(item["note"] as? NSNull, NSNull(), "item \(index) note")
            XCTAssertEqual(item["author"] as? NSNull, NSNull(), "item \(index) author")
        }
        // includeParams=false → NO params key on any item.
        for (index, item) in items.enumerated() {
            XCTAssertNil(item["params"], "item \(index) carried a summary params face")
        }

        let versions = try XCTUnwrap(payload["versions"] as? [[String: Any]])
        XCTAssertEqual(versions.count, 3)
        XCTAssertEqual(versions.filter { ($0["active"] as? Bool) == true }.count, 1)
        XCTAssertTrue(versions.allSatisfy { $0["chain"] == nil },
                      "versions are META only — no chain items")

        // includeParams=true: the params faces land.
        let detailed = try await Self.callJSON(registry, name: "get_history", arguments: [
            "image": .string(String(id)), "includeParams": .bool(true),
        ])
        let detailedItems = try XCTUnwrap(detailed["items"] as? [[String: Any]])
        let detailedParam = try XCTUnwrap(detailedItems[0]["params"] as? [String: Any])
        XCTAssertEqual(detailedParam["opName"] as? String, ExposureModule.opName)
        XCTAssertEqual(detailedParam["enabled"] as? Bool, true)
        XCTAssertNotNil(detailedParam["paramsBase64"])
        // The drt/film placeholder snapshots DROP OUT of the params face.
        XCTAssertNil(detailedItems[3]["params"] as? [String: Any],
                    "drt params face is null (the placeholder never projects)")
        XCTAssertNil(detailedItems[4]["params"] as? [String: Any],
                     "film params face is null")
    }

    /// The F-5 truncation direction: the NEWEST end survives; position and
    /// itemCount stay the true values (truncation is detectable).
    func testGetHistoryLimitTruncationKeepsNewestEnd() async throws {
        let id = try await makeGoldenSidecar()
        let registry = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider()))
        let payload = try await Self.callJSON(registry, name: "get_history", arguments: [
            "image": .string(String(id)), "limit": .int(2),
        ])
        XCTAssertEqual(payload["position"] as? Int, 4, "position stays TRUE")
        XCTAssertEqual(payload["itemCount"] as? Int, 5, "itemCount stays TRUE")
        XCTAssertEqual(payload["truncated"] as? Bool, true)
        let items = try XCTUnwrap(payload["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map { $0["label"] as? String }, ["DRT tweak", "Film look"],
                       "the newest end survives the cap")
        XCTAssertEqual(items[0]["author"] as? String, "mcp",
                       "the kept drt row carries its stamp")
    }

    /// The F8 truth-value form's RED-TAIL leg: position 3 (the film item
    /// UNDONE) with limit 2 — the kept window is [drt, film], so the
    /// newest KEPT item (film, no author) is NOT the POSITION item (drt,
    /// "mcp"). The top-level author reads the POSITION item, deliberately
    /// decoupled from truncation.
    func testGetHistoryTopAuthorReadsThePositionItemNotTheNewestKept() async throws {
        let id = try await makeGoldenSidecar(positionOverride: 3)
        let registry = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider()))
        let payload = try await Self.callJSON(registry, name: "get_history", arguments: [
            "image": .string(String(id)), "limit": .int(2),
        ])
        XCTAssertEqual(payload["position"] as? Int, 3, "position stays TRUE")
        XCTAssertEqual(payload["itemCount"] as? Int, 5)
        XCTAssertEqual(payload["truncated"] as? Bool, true)
        let items = try XCTUnwrap(payload["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["label"] as? String }, ["DRT tweak", "Film look"])
        // The newest KEPT item (film) carries no author; the POSITION item
        // (drt) carries "mcp" — the flip reads position, not "last row".
        XCTAssertEqual(items[1]["author"] as? NSNull, NSNull(),
                       "the newest KEPT item carries no author")
        XCTAssertEqual(payload["author"] as? String, "mcp",
                       "the top-level author is the POSITION item's")
    }

    /// The pristine honest face: no sidecar = position -1, empty items,
    /// null metadata — NOT an error.
    func testGetHistoryPristineFace() async throws {
        // A library row WITHOUT a sidecar document.
        let record = LibraryImageRecord(
            imagePath: "Media/pristine.arw", pathKind: .projectRelative,
            fileStem: "pristine", fileExt: "arw", filename: "pristine.arw",
            dir: "Media")
        let id = try await LibraryStore(store: fileStore).insertImage(record: record)
        try Data(repeating: 0xEF, count: 8).write(
            to: tempDirectory.appendingPathComponent("Media/pristine.arw"))
        let registry = await makeRegistry(context: McpSearchStateContext(
            library: libraryProvider()))
        let payload = try await Self.callJSON(registry, name: "get_history", arguments: [
            "image": .string(String(id)),
        ])
        XCTAssertEqual(payload["position"] as? Int, -1)
        XCTAssertEqual((payload["items"] as? [Any])?.count, 0)
        XCTAssertEqual(payload["truncated"] as? Bool, false,
                       "the pristine face carries the shape-consistency key (N2-1)")
        XCTAssertEqual(payload["rating"] as? NSNull, NSNull())
        // M7-4-01: the pristine chain answers .null for the author flip
        // (position -1 → null) — the negative half of the truth-value form.
        XCTAssertEqual(payload["author"] as? NSNull, NSNull(),
                       "pristine = the .null author")
        // The relPath arm with no session open = the typed honest arm.
        let error = try await Self.toolError {
            _ = try await registry.call(name: "get_history", arguments: [
                "image": .string("Media/golden.arw"),
            ])
        }
        XCTAssertEqual(error.code, "notSessionMember")
    }

    // MARK: - get_state (the F-6 double judgment lives here + the T6 grep)

    /// The headless no-project contract: the absent faces are JSON nulls;
    /// the control and server faces stay alive. M7-5-01 (F4 勘正 — get_state
    /// has NO whole-face golden; every control assertion is per-key, so the
    /// additive agent key rides THIS contract as its nil-provider negative
    /// leg; the truth-provider leg lives in McpControlToolsetTests).
    func testGetStateHeadlessNoProjectNullsContract() async throws {
        let registry = await makeRegistry(context: McpSearchStateContext(
            projectWriteProbe: { .writable }))
        let payload = try await Self.callJSON(registry, name: "get_state", arguments: [:])
        for face in ["project", "workspace", "editor", "tasks"] {
            XCTAssertTrue(payload[face] is NSNull, "\(face) must be null headless")
        }
        let control = try XCTUnwrap(payload["control"] as? [String: Any])
        XCTAssertEqual(control["lock"] as? String, "writable")
        XCTAssertTrue(control["writeCallCount"] is NSNull,
                      "the headless face has no exposed handle (F-4②)")
        // M7-5-01: the nil provider answers the JSON null honest face.
        XCTAssertTrue(control["agent"] is NSNull,
                      "nil agentControl provider = the null honest face")
        let server = try XCTUnwrap(payload["server"] as? [String: Any])
        XCTAssertEqual(server["name"] as? String, McpServerController.serverName)
        XCTAssertTrue(server["hostMode"] is NSNull)
    }

    /// The live-snapshot arm: the fixture liveState closure carries the
    /// MainActor hop INSIDE (the F-6① executable judgment — the closure
    /// is called AND runs on the main thread), and every face renders.
    func testGetStateLiveSnapshotFacesAndMainActorHop() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func bump() { lock.lock(); value += 1; lock.unlock() }
            var count: Int { lock.withLock { value } }
        }
        let counter = Counter()
        let registry = await makeRegistry(context: McpSearchStateContext(
            liveState: {
                await MainActor.run {
                    dispatchPrecondition(condition: .onQueue(.main))
                    counter.bump()
                    return McpSearchStateLiveSnapshot(
                        project: .object([
                            "path": .string("/tmp/Foo.lalb"),
                            "readOnly": .bool(false),
                        ]),
                        workspace: .object(["currentSessionRoot": .null]),
                        editor: .object([
                            "liveImageURL": .null, "hasEdits": .bool(false),
                        ]),
                        tasks: .object(["pending": .int(1), "total": .int(1)]),
                        server: .object([
                            "hostMode": .string("embedded"),
                            "readOnly": .bool(false),
                        ]))
                }
            },
            projectWriteProbe: { .held(
                holderSummary: "pid 123", guidance: "connect guidance text") },
            writeCallCount: { 3 }))
        let payload = try await Self.callJSON(registry, name: "get_state", arguments: [:])
        XCTAssertEqual(counter.count, 1, "the closure was called exactly once")
        // F-6①: the closure ran on the main queue (the dispatchPrecondition
        // inside it would have crashed the suite otherwise).
        let project = try XCTUnwrap(payload["project"] as? [String: Any])
        XCTAssertEqual(project["path"] as? String, "/tmp/Foo.lalb")
        let workspace = try XCTUnwrap(payload["workspace"] as? [String: Any])
        XCTAssertNotNil(workspace["currentSessionRoot"])
        let editor = try XCTUnwrap(payload["editor"] as? [String: Any])
        XCTAssertEqual(editor["hasEdits"] as? Bool, false)
        let tasks = try XCTUnwrap(payload["tasks"] as? [String: Any])
        XCTAssertEqual(tasks["total"] as? Int, 1)
        let control = try XCTUnwrap(payload["control"] as? [String: Any])
        XCTAssertEqual(control["lock"] as? String, "held")
        XCTAssertEqual(control["holder"] as? String, "pid 123")
        XCTAssertEqual(control["writeCallCount"] as? Int, 3)
        let server = try XCTUnwrap(payload["server"] as? [String: Any])
        XCTAssertEqual(server["hostMode"] as? String, "embedded")
    }

    // MARK: - The headless searchState construction face (M7-3 F-AC-2/N2-3)

    /// F-AC-2: the headless searchState carries the project write probe —
    /// `get_state.control.lock` is the verdict TRUTH (writer arm
    /// self-held writable / held arm the real holder summary).
    func testHeadlessGetStateControlLockRidesTheProbe() async throws {
        let writerContext = McpServerController.makeHeadlessSearchState(
            mode: .stdio, projectWriteProbe: { .writable })
        let writerRegistry = await makeRegistry(context: writerContext)
        let payload = try await Self.callJSON(
            writerRegistry, name: "get_state", arguments: [:])
        let control = try XCTUnwrap(payload["control"] as? [String: Any])
        XCTAssertEqual(control["lock"] as? String, "writable")

        let heldContext = McpServerController.makeHeadlessSearchState(
            mode: .stdio,
            projectWriteProbe: { .held(holderSummary: "pid 77", guidance: "g") })
        let heldRegistry = await makeRegistry(context: heldContext)
        let held = try await Self.callJSON(
            heldRegistry, name: "get_state", arguments: [:])
        let heldControl = try XCTUnwrap(held["control"] as? [String: Any])
        XCTAssertEqual(heldControl["lock"] as? String, "held")
        XCTAssertEqual(heldControl["holder"] as? String, "pid 77")
    }

    /// N2-3: the nil-carrier fulltext closure is the TYPED honest arm —
    /// never a silent empty result. Invoking the headless context's closure
    /// directly (no carrier parked in the test process) must throw
    /// `notSessionMember` with the single-source no-open-project message.
    func testHeadlessFulltextNilCarrierThrowsTyped() async throws {
        // The box is process-global (an earlier suite's parking test may
        // have parked) — the nil-carrier judgment needs the empty box.
        McpServerController.headlessProjectBox.set(.init(store: nil, url: nil, readOnly: false))
        let context = McpServerController.makeHeadlessSearchState(mode: .stdio)
        let fulltext = try XCTUnwrap(context.fulltext)
        do {
            _ = try await fulltext("beach")
            XCTFail("the nil carrier must throw the typed error")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
            XCTAssertTrue(
                error.message.contains("no open project"),
                "the message is the noOpenProjectMessage single source: "
                    + "\(error.message)")
        }
    }

    // MARK: - The McpToolError 19-value exhaustive codes

    func testMcpToolErrorCodesNineteenValuesExhaustive() {
        let errors: [McpToolError] = [
            .unknownOp("x"), .invalidParams("x"), .imageLiveInEditor("x"),
            .notSessionMember("x"), .serverReadOnly("x"), .renderFailed("x"),
            .renderTimeout("x"), .exportFailed("x"), .invalidFilter("x"),
            .roiOutOfBounds("x"), .keywordContainsSeparator("x"),
            .exportPresetNotApplicable("x"), .unknownPreset("x"),
            .projectReadOnly("x"), .internalError("x"), .modelUnavailable("x"),
            .controlNotHeld("x"), .controlRevokedByUser("x"), .controlBusy("x"),
        ]
        let expected = [
            "unknownOp", "invalidParams", "imageLiveInEditor",
            "notSessionMember", "serverReadOnly", "renderFailed",
            "renderTimeout", "exportFailed", "invalidFilter",
            "roiOutOfBounds", "keywordContainsSeparator",
            "exportPresetNotApplicable", "unknownPreset", "projectReadOnly",
            "internalError", "modelUnavailable",
            "controlNotHeld", "controlRevokedByUser", "controlBusy",
        ]
        XCTAssertEqual(errors.count, 19, "the closed table is 19 values (M7-5-01)")
        XCTAssertEqual(errors.map(\.code), expected)
        XCTAssertEqual(errors.map(\.message), Array(repeating: "x", count: 19))
    }

    // MARK: - The read-only exemption face

    /// The three tools pass the writerCheck { false } gate untouched, the
    /// counter never moves, and the probe face is never consulted (the
    /// write-face contrast: apply_params dies with serverReadOnly).
    func testReadOnlyToolsExemptFromWriterFace() async throws {
        final class ProbeBox: @unchecked Sendable {
            private let lock = NSLock()
            var calls = 0
            func bump() { lock.lock(); calls += 1; lock.unlock() }
        }
        let probe = ProbeBox()
        // The FULL union (the write-face contrast needs a real write tool).
        let registry = await McpServerController.makeRegistry(
            editing: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }),
            culling: McpServerController.makeCullingContext(session: { nil }),
            searchState: McpSearchStateContext(
                library: libraryProvider(),
                projectWriteProbe: { [probe] in probe.bump(); return .held(
                    holderSummary: "x", guidance: "y") }))
        await registry.setWriterCheck { false }
        let before = await registry.writeCallCount

        // The retrieval faces serve THROUGH the false writer gate and
        // never consult the probe (write-face-only).
        _ = try await Self.callJSON(registry, name: "search_photos", arguments: [
            "query": .string("sony"),
        ])
        let historyError = try await Self.toolError {
            _ = try await registry.call(name: "get_history", arguments: [
                "image": .string("999999"),
            ])
        }
        XCTAssertEqual(historyError.code, "notSessionMember")
        XCTAssertEqual(probe.calls, 0, "search/get_history never touch the probe")

        // get_state READS the probe as control-face DATA — exactly once.
        _ = try await Self.callJSON(registry, name: "get_state", arguments: [:])
        XCTAssertEqual(probe.calls, 1, "the probe rides as get_state's data face")

        let after = await registry.writeCallCount
        XCTAssertEqual(before, after, "read-only calls never touch the counter")

        // The write-face contrast: the gate now answers false →
        // serverReadOnly (proving the gate was actually armed).
        do {
            _ = try await registry.call(name: "apply_params", arguments: [
                "relPath": .string("x.arw"), "ops": .array([]),
            ])
            XCTFail("apply_params must hit the writer gate")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "serverReadOnly")
        }
    }

    // MARK: - The T4 two-process judgment (F-2 甲)

    /// A held-project headless `--mcp-http` child: the connect guidance on
    /// stdout, the read-only face bound on a real port (discovered through
    /// the READONLY file — never the writer's), and search_photos +
    /// get_state serving over the wire.
    func testReadOnlyArmServesSearchPhotosTwoProcess() async throws {
        // The package (with rows) + the parent holding its project lock.
        try Data(repeating: 0xAB, count: 16).write(
            to: tempDirectory.appendingPathComponent("Media/00.arw"))
        let childPackageURL = tempDirectory.appendingPathComponent("Held.lalb")
        let childStore = ProjectFileStore(at: childPackageURL)
        _ = try await childStore.create(name: "Held")
        try await childStore.withWriteBatch { handle -> Bool in
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, camera_make,
                    camera_model, iso, capture_date, rating, file_stem,
                    exif_search_text, exif_search_words, filename)
                VALUES ('Media/held.arw', 0, 'Sony', 'A7R V', 800, 1, 3,
                        'held', 'sony a7r v 800', 'sony a7r v 800', 'held.arw')
                """)
            _ = try insert.step()
            return true
        }
        try Data(repeating: 0xAB, count: 16).write(
            to: tempDirectory.appendingPathComponent("Media/held.arw"))
        try? await childStore.close()
        let lockURL = childPackageURL.deletingPathExtension()
            .appendingPathExtension("lalb.lock")
        let holder = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        holder.writePayload(SingleWriterLockPayload(
            role: .gui, pid: getpid(),
            startedAt: SingleWriterLockPayload.nowISO8601()))

        let endpointDirectory = tempDirectory.appendingPathComponent("mcp", isDirectory: true)
        try FileManager.default.createDirectory(at: endpointDirectory, withIntermediateDirectories: true)
        let paths = McpEndpointPaths(directory: endpointDirectory)
        McpEndpointFile.removeReadOnly(in: paths)

        let process = Process()
        process.executableURL = try XCTUnwrap(Bundle.main.executableURL)
        var environment = ProcessInfo.processInfo.environment
        environment["LIGHTAMER_MCP_ENDPOINT_DIR"] = endpointDirectory.path
        process.environment = environment
        process.arguments = [
            "--mcp-http", McpServerController.projectFlag, childPackageURL.path,
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            McpEndpointFile.removeReadOnly(in: paths)
            holder.unlock()
        }

        // The guidance JSON rides stdout FIRST (the A/B fixture shape).
        let guidanceData = try await Self.readAvailable(
            stdout.fileHandleForReading, timeout: 8)
        let guidanceLine = String(
            decoding: guidanceData, as: UTF8.self)
            .components(separatedBy: "\n").first { $0.contains("connect-guidance") }
        let guidance = try JSONDecoder().decode(
            McpServerController.McpConnectGuidance.self,
            from: XCTUnwrap(guidanceLine?.data(using: .utf8)))
        XCTAssertEqual(guidance.event, McpServerController.connectGuidanceEvent)

        // The READONLY discovery file appears (the child's read-only face
        // is up); the WRITER file must NOT exist in this domain.
        var readonlyInfo: McpEndpointInfo?
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let info = McpEndpointFile.readReadOnly(in: paths) {
                readonlyInfo = info
                break
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        let info = try XCTUnwrap(
            readonlyInfo, "the read-only face never wrote its discovery file")
        XCTAssertNil(
            McpEndpointFile.read(in: paths),
            "the writer's mcp-endpoint.json is never touched by this face")

        // Over-the-wire: search_photos serves the held package's rows.
        let endpoint = URL(string: "http://127.0.0.1:\(info.port)/mcp")!
        let client = MCP.Client(name: "readonly-arm-probe", version: "0.0.1")
        try await client.connect(transport: HTTPClientTransport(endpoint: endpoint))
        let search = try await client.callTool(
            name: "search_photos",
            arguments: ["query": .string("sony"), "limit": .int(10)])
        XCTAssertNil(search.isError, "the read-only arm serves the search face")
        let searchText = Self.firstText(search.content)
        XCTAssertTrue(searchText.contains("held.arw"), searchText)

        // get_state reports the held stance.
        let state = try await client.callTool(name: "get_state", arguments: [:])
        let stateText = Self.firstText(state.content)
        let statePayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(stateText.utf8)) as? [String: Any])
        let project = try XCTUnwrap(statePayload["project"] as? [String: Any])
        XCTAssertEqual(project["heldByOther"] as? Bool, true)
        await client.disconnect()
    }

    private static func firstText(_ content: [MCP.Tool.Content]) -> String {
        for item in content {
            if case .text(let text) = McpAdapters.outputContent(from: item) {
                return text
            }
        }
        return ""
    }

    private static func readAvailable(
        _ handle: FileHandle, timeout: TimeInterval
    ) async throws -> Data {
        var data = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let chunk = handle.availableData
            data.append(chunk)
            if String(decoding: data, as: UTF8.self).contains("\n") { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        return data
    }
}
