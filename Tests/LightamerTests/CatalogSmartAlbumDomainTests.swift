import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// CatalogSmartAlbumDomainTests (Plan 16-2 T4; D-16-CONTEXT-6) — the smart-
// album EVALUATION is domain-parameterized while the RULE ASSET is frozen:
//
//   • SESSION REGRESSION LOCK: the new `evaluate(domain: .session)` entry
//     returns EXACTLY what the 12-2 face (SessionIndexStore.query) returns
//     for the same album — the session shape adds nothing.
//   • CATALOG DOMAIN: the same rules evaluated over the projected catalog
//     return cross-session identities (keywords rules ride the EXISTS
//     materialization); for the same data the catalog row set ⊆ the union
//     of the session-domain row sets (the 16-1 directional ruling), EQUAL
//     for this flat-tag fixture.
//   • ZERO MIGRATION: the rule files' BYTES are identical before/after the
//     two-domain evaluations; schemaVersion stays 1 (schema Version 1
//     assets untouched).
//   • OFFLINE INTEGRITY (execution decision): rows of an OFFLINE session
//     stay in the catalog evaluation (row-set integrity first; the gray-
//     out is a grid-layer concern).
//
// Fixtures are RAW lindex databases (the CatalogProjectorTests direct-
// handle style; L009: never external-volume).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CatalogSmartAlbumDomainTests: XCTestCase {

    private var tempDirectory: URL!
    private var smartAlbumDirectory: URL!
    private var catalogURL: URL!
    private var defaultsSuiteName: String!
    private var sessionRoots: [URL] = []
    private var smartAlbumStore: SmartAlbumStore!

    private var catalogStore: CatalogIndexStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-smart-\(UUID().uuidString)", isDirectory: true)
        smartAlbumDirectory = tempDirectory.appendingPathComponent(
            "SmartAlbums", isDirectory: true)
        catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
        defaultsSuiteName = "catalog-smart-tests-\(UUID().uuidString)"
        CatalogPreferences.setCatalogsEnabled(true, defaultsSuiteName: defaultsSuiteName)

        // Two sessions: (a.arw rating 5 "Nature") + (b.arw rating 2) in the
        // first; (c.arw rating 4 "Nature|Landscape") in the second.
        sessionRoots = []
        for name in ["one", "two"] {
            let root = tempDirectory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true)
            sessionRoots.append(root)
        }
        try makeLindex(
            at: sessionRoots[0],
            rows: [
                ("a.arw", 5, "Nature"),
                ("b.arw", 2, nil),
            ])
        try makeLindex(
            at: sessionRoots[1],
            rows: [
                ("c.arw", 4, "Nature|Landscape"),
            ])

        // Project both into the catalog.
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        for root in sessionRoots {
            _ = try await projector.project(sessionRoot: root)
        }
        catalogStore = CatalogIndexStore(databaseURL: catalogURL)

        // The rule assets.
        smartAlbumStore = SmartAlbumStore(directory: smartAlbumDirectory)
        _ = try smartAlbumStore.create(
            name: "Rated", group: .init(
                match: .all,
                rules: [.init(field: .rating, op: .gte, value: .int(4))]))
        _ = try smartAlbumStore.create(
            name: "Nature", group: .init(
                match: .all,
                rules: [.init(field: .keywords, op: .contains, value: .text("Nature"))]))
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func lindexURL(_ root: URL) -> URL {
        SessionIndexSchema.databaseURL(forSessionRoot: root)
    }

    private func makeLindex(
        at root: URL, rows: [(relPath: String, rating: Int64, keywords: String?)]
    ) throws {
        try FileManager.default.createDirectory(
            at: lindexURL(root).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: lindexURL(root).path)
        defer { handle.close() }
        try SessionIndexSchema.apply(to: handle)
        let stampEpoch = try handle.prepare(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('scan_epoch', '1')")
        _ = try stampEpoch.step()
        for row in rows {
            let insert = try handle.prepare("""
                INSERT INTO images (
                  path, dir, filename, file_size, file_mtime, scan_epoch,
                  imageID, sidecar_present, sidecar_mtime, has_edits,
                  params_hash, layer_count, layer_summary, orientation,
                  width, height, capture_date, rating, color_label, keywords,
                  orphan_sidecar, dirty, flag, note,
                  camera_make, camera_model, lens_model, iso, focal_length,
                  aperture, exposure
                ) VALUES (?, ?, ?, ?, ?, ?,
                          ?, ?, ?, ?,
                          ?, ?, ?, ?,
                          ?, ?, ?, ?, ?, ?,
                          ?, ?, ?, ?,
                          ?, ?, ?, ?, ?,
                          ?, ?)
                """)
            try insert.bindText(1, row.relPath)
            try insert.bindText(2, nil)
            try insert.bindText(3, row.relPath)
            try insert.bindInt(4, 1000)
            try insert.bindDouble(5, 1_700_000_000)
            try insert.bindInt(6, 1)
            try insert.bindText(7, "11111111-2222-3333-4444-555555555555")
            try insert.bindInt(8, 0)
            try insert.bindDouble(9, 0)
            try insert.bindInt(10, 0)
            try insert.bindText(11, nil)
            try insert.bindInt(12, nil)
            try insert.bindText(13, nil)
            try insert.bindInt(14, 1)
            try insert.bindInt(15, 100)
            try insert.bindInt(16, 100)
            try insert.bindDouble(17, 1_700_000_100)
            try insert.bindInt(18, row.rating)
            try insert.bindInt(19, nil)
            try insert.bindText(20, row.keywords)
            try insert.bindInt(21, 0)
            try insert.bindInt(22, 0)
            try insert.bindInt(23, nil)
            try insert.bindText(24, nil)
            try insert.bindText(25, "Sony")
            try insert.bindText(26, nil)
            try insert.bindText(27, nil)
            try insert.bindInt(28, nil)
            try insert.bindDouble(29, nil)
            try insert.bindDouble(30, nil)
            try insert.bindDouble(31, nil)
            _ = try insert.step()
        }
    }

    /// Open a session store over the fixture lindex WITHOUT drifting it:
    /// the scan stream re-asserts the exact fixture entries (matching
    /// mtime/size → the diff is a no-op; no backfill targets appear).
    private func openSessionStore(_ root: URL) async throws -> SessionIndexStore {
        let store = SessionIndexStore(databaseURL: lindexURL(root))
        // The scan carries EXACTLY the fixture's key set (matching
        // mtime/size → the diff is a no-op; no backfill targets appear).
        let held: [String] = root == sessionRoots[0] ? ["a.arw", "b.arw"] : ["c.arw"]
        let page = SessionScanPage(
            entries: held.map {
                .init(relPath: $0, mtime: 1_700_000_000, size: 1000)
            })
        let stream = AsyncStream<SessionScanPage> { continuation in
            continuation.yield(page)
            continuation.finish()
        }
        _ = try await store.openSession(root: root, scan: stream)
        return store
    }

    private func ruleFileData(of album: SmartAlbum) throws -> Data {
        try Data(contentsOf: smartAlbumDirectory.appendingPathComponent(album.id + ".json"))
    }

    // MARK: - Session regression lock (byte-equal to the 12-2 face)

    func testSessionDomainEvaluationMatchesLegacyFace() async throws {
        let store = try await openSessionStore(sessionRoots[0])
        defer { Task { await store.close() } }

        let rated = smartAlbumStore.albums().first { $0.name == "Rated" }!
        let evaluation = try await smartAlbumStore.evaluate(
            id: rated.id, domain: .session,
            sessionStore: store, catalogStore: nil)
        guard case .session(let paths) = evaluation else {
            return XCTFail("expected the session face")
        }
        // The 12-2 face, called directly — the SAME result.
        let legacy = try await store.query(groups: [rated.group], sort: nil)
        XCTAssertEqual(paths, legacy.map(\.path))
        XCTAssertEqual(Set(paths), ["a.arw"], "rating ≥ 4 in session one")
    }

    // MARK: - Catalog domain (cross-session + EXISTS keywords)

    func testCatalogDomainCrossSessionAndKeywords() async throws {
        let rated = smartAlbumStore.albums().first { $0.name == "Rated" }!
        let evaluation = try await smartAlbumStore.evaluate(
            id: rated.id, domain: .catalog,
            sessionStore: nil, catalogStore: catalogStore)
        guard case .catalog(let identities) = evaluation else {
            return XCTFail("expected the catalog face")
        }
        XCTAssertEqual(
            Set(identities.map { "\($0.sessionID)/\($0.relPath)" }).count,
            identities.count, "no duplicate identities")
        // Cross-session: a.arw (rating 5) AND c.arw (rating 4), b.arw out.
        let relPaths = Set(identities.map(\.relPath))
        XCTAssertEqual(relPaths, ["a.arw", "c.arw"])
        // The identities carry BOTH sessions' ids (cross-session reach).
        XCTAssertEqual(
            Set(identities.map(\.sessionID)).count, 2,
            "the rating ≥ 4 rows live in two different sessions")

        // The keywords album: the catalog EXISTS materialization — the
        // prefix-expanded tags match both the flat "Nature" and the
        // "Nature|Landscape" chain.
        let nature = smartAlbumStore.albums().first { $0.name == "Nature" }!
        let natureEvaluation = try await smartAlbumStore.evaluate(
            id: nature.id, domain: .catalog,
            sessionStore: nil, catalogStore: catalogStore)
        guard case .catalog(let natureIdentities) = natureEvaluation else {
            return XCTFail("expected the catalog face")
        }
        XCTAssertEqual(Set(natureIdentities.map(\.relPath)), ["a.arw", "c.arw"])

        // The 16-1 directional ruling on the SAME data: catalog ⊆ the
        // union of the session-domain row sets — equal for flat tags.
        var sessionUnion: Set<String> = []
        for root in sessionRoots {
            let store = try await openSessionStore(root)
            let result = try await smartAlbumStore.evaluate(
                id: nature.id, domain: .session,
                sessionStore: store, catalogStore: nil)
            if case .session(let paths) = result {
                sessionUnion.formUnion(paths)
            }
            await store.close()
        }
        XCTAssertTrue(
            Set(natureIdentities.map(\.relPath)).isSubset(of: sessionUnion),
            "catalog ⊆ session (same data, same predicates)")
        XCTAssertEqual(
            Set(natureIdentities.map(\.relPath)), sessionUnion,
            "equal for this flat-tag fixture")
    }

    // MARK: - Rule files: zero migration across both domains

    func testRuleFilesByteIdenticalAcrossDomainEvaluations() async throws {
        let albums = smartAlbumStore.albums()
        let before = try albums.map { try ($0.id, try ruleFileData(of: $0)) }

        let store = try await openSessionStore(sessionRoots[0])
        for album in albums {
            _ = try await smartAlbumStore.evaluate(
                id: album.id, domain: .session,
                sessionStore: store, catalogStore: nil)
            _ = try await smartAlbumStore.evaluate(
                id: album.id, domain: .catalog,
                sessionStore: nil, catalogStore: catalogStore)
        }
        await store.close()

        for (id, data) in try albums.map({ try ($0.id, try ruleFileData(of: $0)) }) {
            let original = try XCTUnwrap(before.first { $0.0 == id }?.1)
            XCTAssertEqual(
                data, original,
                "the rule file \(id) is byte-identical across evaluations")
            let document = try JSONDecoder().decode(
                SmartAlbumDocument.self, from: data)
            XCTAssertEqual(
                document.schemaVersion,
                SmartAlbumDocument.schemaVersionCurrent,
                "schemaVersion 1 assets untouched")
        }
    }

    // MARK: - Offline integrity (execution decision pin)

    func testOfflineSessionRowsRemainInCatalogEvaluation() async throws {
        // Park session two's lindex away → the sweep marks it offline and
        // LEAVES its rows (the 16-1 offline semantics).
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        let parked = tempDirectory.appendingPathComponent("parked.lindex")
        try FileManager.default.moveItem(at: lindexURL(sessionRoots[1]), to: parked)
        let result = try await projector.project(sessionRoot: sessionRoots[1])
        XCTAssertTrue(result.offline, "the session marks offline")

        let rated = smartAlbumStore.albums().first { $0.name == "Rated" }!
        let evaluation = try await smartAlbumStore.evaluate(
            id: rated.id, domain: .catalog,
            sessionStore: nil, catalogStore: catalogStore)
        guard case .catalog(let identities) = evaluation else {
            return XCTFail("expected the catalog face")
        }
        // Row-set integrity first: the offline session's matching rows
        // stay in the evaluation (the gray-out lives in the grid layer).
        XCTAssertTrue(
            identities.contains { $0.relPath == "c.arw" },
            "offline-session rows are NOT filtered out of the evaluation")
        XCTAssertTrue(
            identities.contains { $0.relPath == "a.arw" },
            "online-session rows are unaffected")
    }
}
