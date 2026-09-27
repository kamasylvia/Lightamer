import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// CatalogModeIsolationTests (Plan 16-2) — the double-mode isolation suite.
//
//   T1 segment (preferences / guard linkage):
//     • the settings switch drives the SAME key the projector guard reads —
//       off → `project` returns skippedByGuard and NO .lcat file exists
//       (the 16-1 probe assertion, re-driven through the UI-facing model);
//     • the location re-point (RQ-16-1②: no migration) — the next open at
//       the new path creates an EMPTY library (建空库);
//     • the cold-start organization-mode constant is SESSIONS (RQ-16-12:
//       恒默认做成常量 — the AppStorage overwrite rides this value).
//
//   T2 segment (five-section order / visibility-as-a-function).
//   T3 segment (browser model seams — see CatalogBrowserModelTests).
//   T7 segment (Sessions-mode zero-handle full flow).
//
// Fixtures are RAW lindex databases (the CatalogProjectorTests direct-
// handle style; L009: never external volume).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CatalogModeIsolationTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!
    private var defaultsSuiteName: String!

    private var lindexURL: URL {
        SessionIndexSchema.databaseURL(forSessionRoot: sessionRoot)
    }

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-iso-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot, withIntermediateDirectories: true)
        defaultsSuiteName = "catalog-iso-tests-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures (the CatalogProjectorTests direct-handle style)

    private func makeLindex() throws {
        try FileManager.default.createDirectory(
            at: lindexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: lindexURL.path)
        defer { handle.close() }
        try SessionIndexSchema.apply(to: handle)
        let stampEpoch = try handle.prepare(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('scan_epoch', '1')")
        _ = try stampEpoch.step()
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
        try insert.bindText(1, "a.arw")
        try insert.bindText(2, nil)
        try insert.bindText(3, "a.arw")
        try insert.bindInt(4, 1234)
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
        try insert.bindInt(18, 3)
        try insert.bindInt(19, nil)
        try insert.bindText(20, nil)
        try insert.bindInt(21, 0)
        try insert.bindInt(22, 0)
        try insert.bindInt(23, nil)
        try insert.bindText(24, nil)
        try insert.bindText(25, "Sony")
        try insert.bindText(26, "A7R V")
        try insert.bindText(27, nil)
        try insert.bindInt(28, nil)
        try insert.bindDouble(29, nil)
        try insert.bindDouble(30, nil)
        try insert.bindDouble(31, nil)
        _ = try insert.step()
    }

    // MARK: - T1: the switch drives the projector guard (one key)

    func testEnableSwitchDrivesProjectorGuard() async throws {
        try makeLindex()
        let model = CatalogPreferencesModel(defaultsSuiteName: defaultsSuiteName)
        model.setCatalogsEnabled(false)
        XCTAssertEqual(
            CatalogPreferences.catalogsEnabled(defaultsSuiteName: defaultsSuiteName),
            false, "the model writes through the CORE face — one key")

        // Off → the projector returns before ANY handle (16-1 probe, the
        // UI-facing re-drive).
        let projector = CatalogProjector(
            databaseURL: tempDirectory.appendingPathComponent("catalog.lcat"),
            defaultsSuiteName: defaultsSuiteName)
        let skipped = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(skipped.skippedByGuard, true)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("catalog.lcat").path),
            "disabled: zero .lcat handles")

        // On → the same key flips the guard.
        model.setCatalogsEnabled(true)
        let projected = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertEqual(projected.skippedByGuard, false)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("catalog.lcat").path))
    }

    // MARK: - T1: location re-point creates an empty library at the new path

    func testLocationRepointCreatesEmptyLibraryAtNewPath() async throws {
        try makeLindex()
        let model = CatalogPreferencesModel(defaultsSuiteName: defaultsSuiteName)
        model.setCatalogsEnabled(true)

        let oldDirectory = tempDirectory.appendingPathComponent("cat-old", isDirectory: true)
        let newDirectory = tempDirectory.appendingPathComponent("cat-new", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)

        model.setLocation(directory: oldDirectory)
        let oldURL = model.catalogURL
        XCTAssertEqual(oldURL.lastPathComponent, CatalogIndexSchema.databaseFileName)
        // An EXISTING library at the old path (the no-migration witness).
        try Data("old-library".utf8).write(to: oldURL, options: .atomic)
        var repointedTo: URL?
        model.onLocationChanged = { repointedTo = $0 }

        // The re-point: the runtime closure fires FIRST, then the
        // preference lands. No migration — the old file is not copied.
        model.setLocation(directory: newDirectory)
        XCTAssertEqual(repointedTo, newDirectory)
        let newURL = model.catalogURL
        XCTAssertNotEqual(newURL, oldURL)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: newURL.path),
            "re-point copies nothing")

        // 下次启用按新路径打开，不存在则建空库 (RQ-16-1②③) — the projector
        // at the NEW URL creates the empty library on demand.
        let projector = CatalogProjector(
            databaseURL: newURL, defaultsSuiteName: defaultsSuiteName)
        _ = try await projector.project(sessionRoot: sessionRoot)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: newURL.path),
            "the new-path library was created empty")
        // And the old file was left exactly as it was (no migration leg).
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
    }

    // MARK: - T1: the cold-start constant (RQ-16-12)

    func testColdStartOrganizationModeIsSessions() {
        XCTAssertEqual(
            CatalogPreferencesModel.coldStartRawValue,
            CatalogPreferencesModel.OrganizationMode.sessions.rawValue,
            "恒默认做成常量 — the first frame always lands on sessions")
        // The persisted-key raw values round-trip (the AppStorage face).
        XCTAssertEqual(
            CatalogPreferencesModel.OrganizationMode(
                rawValue: CatalogPreferencesModel.OrganizationMode.sessions.rawValue),
            .sessions)
        XCTAssertEqual(
            CatalogPreferencesModel.OrganizationMode(
                rawValue: CatalogPreferencesModel.OrganizationMode.catalogs.rawValue),
            .catalogs)
    }

    // MARK: - T2: the five-section order is a pinned constant

    func testCatalogSidebarSectionOrder() {
        XCTAssertEqual(
            CatalogSidebarSection.allCases,
            [.allPhotographs, .categories, .collections, .smartAlbums, .sessions],
            "the RQ-16-12 five-section order is frozen")
    }

    // MARK: - T7: the sessions-mode full flow stays zero-handle

    /// The T7 isolation red line: with the switch OFF (written through the
    /// UI-facing model), the FULL open flow (real scanner + sync) runs and
    /// the catalog file NEVER appears; switching on and reopening projects.
    /// (The 16-1 probe re-driven through the preferences model.)
    func testSessionsModeFullFlowCreatesNoCatalogFile() async throws {
        try makeLindex()
        try Data("x".utf8).write(to: sessionRoot.appendingPathComponent("a.arw"))
        let catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")

        let model = CatalogPreferencesModel(defaultsSuiteName: defaultsSuiteName)
        model.setCatalogsEnabled(false)

        let controller = SessionIndexController()
        let suiteName = defaultsSuiteName!
        controller.catalogProjectorProvider = {
            CatalogProjector(databaseURL: catalogURL, defaultsSuiteName: suiteName)
        }
        let first = await controller.openAndSync(root: sessionRoot)
        XCTAssertFalse(first.failed, "the SESSIONS flow succeeds untouched")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: catalogURL.path),
            "disabled: zero .lcat handles across the full session flow")

        // Enabled: the same flow now registers the session.
        model.setCatalogsEnabled(true)
        let second = await controller.openAndSync(root: sessionRoot)
        XCTAssertFalse(second.failed)
        var attempts = 0
        while !FileManager.default.fileExists(atPath: catalogURL.path), attempts < 200 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: catalogURL.path),
            "enabled: the detached hook projects")
    }

    // MARK: - T7: L025 — every 16-2 catalog key carries en AND zh

    func testCatalogKeysL025EnZhComplete() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LightamerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        // The 16-2 key families (settings + organization + sessions +
        // batch + quick-filter hint).
        let prefixes = ["settings_catalogs_", "organization_mode_", "catalog_"]
        let catalogKeys = strings.keys.filter { key in
            prefixes.contains { key.hasPrefix($0) }
        }
        XCTAssertGreaterThanOrEqual(
            catalogKeys.count, 28, "the 16-2 key families landed")

        // EVERY 16-2 key carries BOTH faces, translated and non-empty.
        // (The whole-file invariant does NOT hold for legacy keys — en is
        // implicit in the key for the source language; the L025 smoke
        // scopes to the new families, the yiyin test's shape.)
        for key in catalogKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any], key)
            for language in ["en", "zh"] {
                let face = try XCTUnwrap(
                    localizations[language] as? [String: Any],
                    "\(key) missing \(language)")
                let unit = try XCTUnwrap(
                    face["stringUnit"] as? [String: Any],
                    "\(key) \(language) missing stringUnit")
                XCTAssertEqual(unit["state"] as? String, "translated", key)
                XCTAssertFalse(
                    (unit["value"] as? String ?? "").isEmpty,
                    "\(key) empty \(language)")
            }
        }
    }

    // MARK: - T2: the session-anchor scope (the Sessions 从属节's click face)

    /// The sidebar's session click = the `scopeClause(sessionID:)` anchor:
    /// the anchor query returns ONLY that session's rows; the default scope
    /// returns the whole library (All Photographs).
    func testSessionAnchorScopeFiltersRows() async throws {
        // Seed two sessions × two rows directly into the catalog.
        let catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: catalogURL.path)
        defer { handle.close() }
        try CatalogIndexSchema.apply(to: handle)
        for (session, rel) in [("s-aaa", "one.arw"), ("s-aaa", "two.arw"),
                               ("s-bbb", "three.arw"), ("s-bbb", "four.arw")] {
            let insert = try handle.prepare(
                "INSERT INTO catalog_images (session_id, rel_path, filename, "
                    + "orphan_sidecar) VALUES (?, ?, ?, 0)")
            try insert.bindText(1, session)
            try insert.bindText(2, rel)
            try insert.bindText(3, rel)
            _ = try insert.step()
        }

        let store = CatalogIndexStore(databaseURL: catalogURL)
        let all = try await store.queryPage(groups: [], sort: .init(key: .filename, ascending: true))
        XCTAssertEqual(Set(all.map(\.sessionID)), ["s-aaa", "s-bbb"])

        let anchored = try await store.queryPage(
            groups: [], sort: .init(key: .filename, ascending: true),
            scope: FilterScope(sessionID: "s-aaa"))
        XCTAssertEqual(anchored.map(\.relPath), ["one.arw", "two.arw"],
                       "the anchor narrows the row set to the clicked session")
        XCTAssertTrue(anchored.allSatisfy { $0.sessionID == "s-aaa" })
    }
}
