import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryProjectControllerTests (Plan M2-2-2 T4) — the KD-5 command face:
//
//   • recent: dedupe-move-front, cap 10, dead-path prune, cross-instance
//     persistence through the injected suite (the SessionState pattern)
//   • backup: the ProjectFileStore.backup passthrough (an independently
//     openable, schema-valid copy)
//   • moveProject SAME-VOLUME rename: the whole directory lands at the new
//     location, the old one is gone, the reopened package's kind0 rows
//     resolve against the NEW project directory (the mount-point-immunity
//     chain, live) — and the recent list points at the new package
//   • moveProject RED PIN: a verify-failing cross-volume leg (the injected
//     verifyStrategy + uuidProbe seams) leaves the SOURCE project directory
//     byte-intact, reopens in place, counts a typed failure
//   • the dialog default face (OQ-4 through the injected ImportDefaults):
//     default copy; the remembered mode only honors the remember gate; a
//     single-shot override with remember unchecked persists nothing
//
// ImportModeDialog/ImportProgressView are stateless shells — no UI tests
// (SUMMARY declaration; the state faces are Core-tested).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryProjectControllerTests: XCTestCase {

    private var root: URL!
    private var suiteName: String!
    private var controller: LibraryProjectController!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("project-ctl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        suiteName = "project-ctl-\(UUID().uuidString)"
        controller = LibraryProjectController(defaultsSuiteName: suiteName)
    }

    override func tearDown() async throws {
        try? await controller.closeProject()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeProject(named name: String) async throws -> URL {
        // The project gets its OWN directory (the real package shape:
        // `<dir>/<stem>.lalb` + `Media/` beside it) — never the bare temp
        // root, which would put move destinations inside the project.
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
            .appendingPathExtension("lalb")
        try await controller.createProject(at: url, name: name)
        return url
    }

    private func makeFile(_ path: String, bytes: Data) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        return url
    }

    private func imageCount(in packageURL: URL) throws -> Int {
        let handle = try SQLiteHandle(path: packageURL.path)
        defer { handle.close() }
        try LibrarySchema.apply(to: handle)
        let statement = try handle.prepare("SELECT COUNT(*) FROM images")
        try XCTAssertTrue(statement.step())
        return Int(statement.columnInt(0) ?? 0)
    }

    // MARK: - Recent list

    func testRecentDeduplicatesMovesFrontAndCapsAtTen() async throws {
        var urls: [URL] = []
        for index in 0..<12 {
            let directory = root.appendingPathComponent(
                "recent-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            urls.append(directory)
        }
        for url in urls { controller.promoteRecent(url) }
        XCTAssertEqual(controller.recentProjects.count, 10, "cap 10")
        XCTAssertEqual(controller.recentProjects.first, urls.last, "front = most recent")

        // Re-promote an early entry → dedupe-move-front, no duplicates.
        controller.promoteRecent(urls[3])
        XCTAssertEqual(controller.recentProjects.count, 10)
        XCTAssertEqual(controller.recentProjects.first, urls[3])
        XCTAssertEqual(
            Set(controller.recentProjects.map(\.absoluteString)).count,
            controller.recentProjects.count,
            "no duplicate entries")

        // Cross-instance persistence (the UserDefaults face).
        let reloaded = LibraryProjectController(defaultsSuiteName: suiteName)
        XCTAssertEqual(reloaded.recentProjects, controller.recentProjects)
    }

    func testPruneMissingRecentsDropsDeadPaths() async throws {
        let alive = root.appendingPathComponent("alive", isDirectory: true)
        let dead = root.appendingPathComponent("dead", isDirectory: true)
        try FileManager.default.createDirectory(at: alive, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dead, withIntermediateDirectories: true)
        controller.promoteRecent(alive)
        controller.promoteRecent(dead)
        try FileManager.default.removeItem(at: dead)

        controller.pruneMissingRecents()
        XCTAssertEqual(controller.recentProjects, [alive])
    }

    // MARK: - Backup passthrough

    func testBackupProjectPassthroughProducesOpenableCopy() async throws {
        let url = try await makeProject(named: "BackupProj")
        // One row so the copy proves row fidelity, not just existence.
        let store = try XCTUnwrap(controller.projectStore)
        _ = try await LibraryStore(store: store).insertImage(record: LibraryImageRecord(
            imagePath: "Media/x.arw", pathKind: .projectRelative, fileStem: "x"))

        let backupURL = root.appendingPathComponent("BackupProj-backup.lalb")
        try await controller.backupProject(to: backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(try imageCount(in: backupURL), 1)
        XCTAssertEqual(try imageCount(in: url), 1)
    }

    // MARK: - Move (same volume → rename; kind0 immunity chain)

    func testMoveProjectSameVolumeRenamesAndKind0Resolves() async throws {
        let url = try await makeProject(named: "MoveProj")
        // A kind0 row with its Media bytes — the immunity chain's payload.
        _ = try makeFile(
            "MoveProj/Media/Card/DSC00001.ARW", bytes: Data([0x41, 0x42]))
        let store = try XCTUnwrap(controller.projectStore)
        _ = try await LibraryStore(store: store).insertImage(record: LibraryImageRecord(
            imagePath: "Media/Card/DSC00001.ARW",
            pathKind: .projectRelative,
            fileStem: "DSC00001"))

        let destination = root.appendingPathComponent("MovedProj", isDirectory: true)
        try await controller.moveProject(to: destination)

        // The whole directory moved; the old location is gone.
        let newPackage = destination.appendingPathComponent("MoveProj.lalb")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPackage.path))
        let movedMedia = destination.appendingPathComponent("Media/Card/DSC00001.ARW")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedMedia.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        // The controller rides the NEW location.
        XCTAssertEqual(controller.projectURL, newPackage)
        XCTAssertEqual(controller.recentProjects.first, newPackage)

        // THE CHAIN: kind0 (project-relative) resolves against the NEW
        // project directory — the whole-directory move immunity, live.
        let resolution = ImageLinker.resolve(
            imagePath: "Media/Card/DSC00001.ARW",
            pathKind: .projectRelative, volumeUUID: nil,
            projectDirectory: destination)
        XCTAssertEqual(resolution, .resolved(movedMedia))

        // The reopened package carries the row.
        XCTAssertEqual(try imageCount(in: newPackage), 1)
    }

    // MARK: - Move red pin (verify failure → source intact)

    func testMoveProjectVerifyFailureLeavesSourceProjectIntact() async throws {
        let url = try await makeProject(named: "PinProj")
        _ = try makeFile("PinProj/Media/Card/DSC00001.ARW", bytes: Data([0x41]))
        let store = try XCTUnwrap(controller.projectStore)
        _ = try await LibraryStore(store: store).insertImage(record: LibraryImageRecord(
            imagePath: "Media/Card/DSC00001.ARW",
            pathKind: .projectRelative,
            fileStem: "DSC00001"))

        // Force the cross-volume leg + a failing verify (the M2LIB-07①
        // red-line seams, mirrored on the controller).
        controller.uuidProbe = { url in
            url.path.contains("PinProj") ? "vol-src" : "vol-dst"
        }
        controller.verifyStrategy = { _, _ in false }

        let destination = root.appendingPathComponent("PinMoved", isDirectory: true)
        do {
            try await controller.moveProject(to: destination)
            XCTFail("the failing verify must reject the move")
        } catch {
            // The typed verify failure surfaces.
            guard case ImportError.verifyFailed = error else {
                return XCTFail("expected ImportError.verifyFailed, got \(error)")
            }
        }

        // THE RED LINE: the source project directory stands byte-intact.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("PinProj/Media/Card/DSC00001.ARW").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path),
                       "the half-copy rolled back")
        XCTAssertEqual(try imageCount(in: url), 1, "the source package row intact")

        // The controller reopened IN PLACE.
        XCTAssertEqual(controller.projectURL, url)
        let reopened = try XCTUnwrap(controller.projectStore)
        let isOpen = await reopened.isOpen
        XCTAssertTrue(isOpen)
    }

    // MARK: - Dialog default face (OQ-4 through the injected host)

    func testDialogDefaultFaceDefaultCopyRememberGateAndSingleShot() {
        let defaults = ImportDefaults(defaultsSuiteName: suiteName)
        // Default = copy.
        XCTAssertEqual(defaults.resolvedMode(), .copy)
        XCTAssertFalse(defaults.rememberMode)

        // Remembered move persists and is honored.
        defaults.storeChoice(ImportModeChoice(mode: .move, remember: true))
        XCTAssertEqual(defaults.resolvedMode(), .move)

        // A single-shot copy with remember unchecked: next dialog = copy
        // again, nothing lingers.
        defaults.storeChoice(ImportModeChoice(mode: .copy, remember: false))
        XCTAssertEqual(defaults.resolvedMode(), .copy)
        XCTAssertNil(
            UserDefaults(suiteName: suiteName)?.string(forKey: ImportDefaults.modeKey))
    }
}
