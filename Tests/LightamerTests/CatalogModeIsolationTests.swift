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
// handle style; L009: never UNITEK).
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
}
