import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryFirstLaunchTests (gallery-first startup, 2026-11-02) — the default
// library's PURE assignment faces:
//
//   • the default URL = `<support>/Lightamer/Library.lalb` (injected base;
//     the production base is `.applicationSupportDirectory`, asserted only
//     for its suffix shape — the suite never writes into the real support
//     dir)
//   • nil support directory = nil URL (the launch task's fallback face)
//   • the file/name single sources are what the URL is built from
//   • the open-or-create DRIVE is the controller's existing faces — pinned
//     live here (create on absent, open on present, schema-valid both ways)
//
// The shell's launch-task condition (no store open → the default-library
// drive, recents or not) is a one-line guard over published controller
// state — asserted through the controller's own faces, not the SwiftUI task
// (see `testLaunchConditionOpensDefaultLibraryRegardlessOfRecents`).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryFirstLaunchTests: XCTestCase {

    private var root: URL!
    private var suiteName: String!
    private var controller: LibraryProjectController!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("first-launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        suiteName = "first-launch-\(UUID().uuidString)"
        controller = LibraryProjectController(defaultsSuiteName: suiteName)
    }

    override func tearDown() async throws {
        try? await controller.closeProject()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - The pure assignment

    func testDefaultLibraryURLAppendsLightamerDirectoryAndFileName() {
        let base = URL(fileURLWithPath: "/tmp/support", isDirectory: true)
        XCTAssertEqual(
            LibraryFirstLaunch.defaultLibraryURL(supportDirectory: base)?.path,
            "/tmp/support/Lightamer/" + LibraryFirstLaunch.defaultLibraryFileName)
    }

    func testDefaultLibraryURLIsNilWhenSupportIsUnreachable() {
        XCTAssertNil(LibraryFirstLaunch.defaultLibraryURL(supportDirectory: nil))
    }

    func testDefaultLibraryFileNameIsALalbPackage() {
        XCTAssertEqual(LibraryFirstLaunch.defaultLibraryFileName, "Library.lalb")
        XCTAssertTrue(
            LibraryFirstLaunch.defaultLibraryFileName.hasSuffix(".lalb"),
            "the store's create leg suffix-validates — a non-.lalb name would throw")
    }

    func testProductionBaseKeepsTheSuffixShape() {
        // The ONLY assertion over the real support directory — suffix shape,
        // never a write (the suite must not touch the user's library).
        let url = LibraryFirstLaunch.defaultLibraryURL()
        XCTAssertEqual(url?.lastPathComponent, LibraryFirstLaunch.defaultLibraryFileName)
        XCTAssertEqual(
            url?.deletingLastPathComponent().lastPathComponent, "Lightamer")
    }

    // MARK: - The open-or-create drive (the shell launch task's legs)

    func testCreateDriveMakesASchemaValidPackageOnAbsentPath() async throws {
        let url = root.appendingPathComponent("Lightamer", isDirectory: true)
            .appendingPathComponent(LibraryFirstLaunch.defaultLibraryFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try await controller.createProject(
            at: url, name: LibraryFirstLaunch.defaultLibraryName)
        XCTAssertEqual(controller.projectURL, url)
        // Schema-valid: the images table answers (fresh-leg apply ran).
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        let statement = try handle.prepare("SELECT COUNT(*) FROM images")
        XCTAssertTrue(try statement.step())
        XCTAssertEqual(statement.columnInt(0), 0)
    }

    func testOpenDriveReopensTheExistingPackage() async throws {
        let directory = root.appendingPathComponent("Lightamer", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory
            .appendingPathComponent(LibraryFirstLaunch.defaultLibraryFileName)
        try await controller.createProject(
            at: url, name: LibraryFirstLaunch.defaultLibraryName)
        try await controller.closeProject()
        XCTAssertNil(controller.projectStore)
        try await controller.openProject(at: url)
        XCTAssertEqual(controller.projectURL, url)
        XCTAssertNotNil(controller.projectStore)
    }

    // MARK: - The test-host guard

    func testIsTestHostReadsTheXCTestBundlePathVariable() {
        XCTAssertTrue(LibraryFirstLaunch.isTestHost(
            environment: ["XCTestBundlePath": "/any/Bundle.xctest"]))
        XCTAssertFalse(LibraryFirstLaunch.isTestHost(environment: [:]))
        XCTAssertFalse(LibraryFirstLaunch.isTestHost(environment: [
            "HOME": "/Users/someone",
            "XCTestConfigurationFilePath": "/tmp/old-style.plist",
        ]))
    }

    func testCurrentProcessIsATestHost() {
        // This suite RUNS inside a test host — the production default
        // (the live environment) must answer true here, which is exactly
        // the launch task's skip condition.
        XCTAssertTrue(LibraryFirstLaunch.isTestHost())
    }

    // MARK: - The launch condition (controller-state reads)

    func testLaunchConditionOpensDefaultLibraryRegardlessOfRecents() async throws {
        // Gallery-first startup: the launch task drives the default
        // library whenever no store is open — recents or not (a returning
        // user lands on their collection, not a picker). The published
        // `projectStore` nil-read is the condition's only input.
        XCTAssertNil(controller.projectStore)
        XCTAssertTrue(controller.recentProjects.isEmpty)
        let url = root.appendingPathComponent("P").appendingPathExtension("lalb")
        try await controller.createProject(at: url, name: "P")
        XCTAssertFalse(controller.recentProjects.isEmpty)
        try await controller.closeProject()
        // Recents present AND no store open = the drive still runs (the
        // unit under test is the default-URL assignment, not the SwiftUI
        // task — the task's guard is `projectStore == nil` only).
        XCTAssertNil(controller.projectStore)
        XCTAssertFalse(controller.recentProjects.isEmpty)
        let reopened = root.appendingPathComponent("Lightamer", isDirectory: true)
            .appendingPathComponent(LibraryFirstLaunch.defaultLibraryFileName)
        try await controller.createProject(
            at: reopened, name: LibraryFirstLaunch.defaultLibraryName)
        XCTAssertEqual(controller.projectURL, reopened)
    }
}
