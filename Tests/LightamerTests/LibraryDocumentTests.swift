import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryDocumentTests (Plan M2-2-1 T2) — the `.lalb` package lifecycle:
//
//   • create: suffix validation / existing-file refusal / manifest seed
//   • open: missing-file refusal / zero-byte file heals through the fresh
//     leg (KD-2 absent → fresh) / current ok / future typed `.futureSchema` REFUSE
//   • checkpoint discipline (KD-6, probe P3): the throttled face leaves
//     the `-wal` NON-ZERO below the threshold, TRUNCATES it to 0 bytes at
//     the 64-batch boundary; close FORCES the checkpoint — after close
//     the `-wal` exists but is 0 bytes (the 3.54.0 empty-shell posture)
//   • backup: the sqlite3_backup online copy yields an independently
//     openable, row-count-identical file; an existing destination is a
//     typed refusal; post-close work is `.notOpen`; close is idempotent
//
// Fixtures in NSTemporaryDirectory (L009: never external volume).
// ─────────────────────────────────────────────────────────────────────────────

final class LibraryDocumentTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-doc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("DocProj.lalb")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// The typed-error assertion (actor calls cannot ride XCTAssertThrowsError's
    /// non-async autoclosure — do/catch with an exact Equatable compare).
    private func assertLibraryError(
        _ expected: LibraryError,
        from action: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await action()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as LibraryError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error type: \(error)", file: file, line: line)
        }
    }

    private func isOpen(_ store: ProjectFileStore) async -> Bool {
        await store.isOpen
    }

    /// One minimal images row (autocommit batch). STATIC — closures handed
    /// to the store actor must capture nothing non-Sendable (the test case
    /// itself is not).
    private static func insertImage(
        _ handle: SQLiteHandle, path: String, stem: String
    ) throws {
        let statement = try handle.prepare(
            "INSERT INTO images (image_path, path_kind, file_stem) VALUES (?, 0, ?)")
        try statement.bindText(1, path)
        try statement.bindText(2, stem)
        _ = try statement.step()
    }

    private func walSize() -> Int64? {
        let path = packageURL.path + "-wal"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.size] as? Int64
    }

    private func imageCount(in url: URL) throws -> Int {
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        try LibrarySchema.apply(to: handle)
        let statement = try handle.prepare("SELECT COUNT(*) FROM images")
        try XCTAssertTrue(statement.step())
        return Int(statement.columnInt(0) ?? 0)
    }

    // MARK: - Create

    func testCreateSeedsFreshPackage() async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "DocProj")
        let created = await isOpen(store)
        XCTAssertTrue(created)

        let handle = try SQLiteHandle(path: packageURL.path)
        defer { handle.close() }
        // M2-8-1 KD-3: fresh creates stamp the current version (3).
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 3)
        let statement = try handle.prepare(
            "SELECT value FROM project_meta WHERE key = 'project_name'")
        try XCTAssertTrue(statement.step())
        XCTAssertEqual(statement.columnText(0), "DocProj")
    }

    func testCreateRefusesNonLalbSuffixAndExistingFile() async throws {
        let badURL = tempDirectory.appendingPathComponent("DocProj.txt")
        let store = ProjectFileStore(at: badURL)
        await assertLibraryError(
            .openFailed(
                path: badURL.path, code: 0,
                message: "not a .lalb package path")
        ) { try await store.create(name: "DocProj") }

        try "".write(to: packageURL, atomically: true, encoding: .utf8)
        let second = ProjectFileStore(at: packageURL)
        await assertLibraryError(
            .openFailed(
                path: packageURL.path, code: 0, message: "package already exists")
        ) { try await second.create(name: "DocProj") }
    }

    // MARK: - Open + version dispatch (KD-2)

    func testOpenMissingFileRefused() async throws {
        let store = ProjectFileStore(at: packageURL)
        await assertLibraryError(
            .openFailed(
                path: packageURL.path, code: 0,
                message: "package file does not exist")
        ) { try await store.open() }
    }

    func testOpenZeroByteFileHealsThroughFreshLeg() async throws {
        // An absent user_version (0-byte stub) → the KD-2 fresh leg.
        try Data().write(to: packageURL)
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.open()
        let opened = await isOpen(store)
        XCTAssertTrue(opened)
        let handle = try SQLiteHandle(path: packageURL.path)
        defer { handle.close() }
        XCTAssertEqual(try LibrarySchema.readUserVersion(from: handle), 3)
        let statement = try handle.prepare("SELECT COUNT(*) FROM project_meta")
        try XCTAssertTrue(statement.step())
        XCTAssertGreaterThan(statement.columnInt(0) ?? 0, 0)
    }

    func testOpenVersionOneOK() async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "DocProj")
        try await store.close()

        let reopened = ProjectFileStore(at: packageURL)
        _ = try await reopened.open()
        let reopenedOK = await isOpen(reopened)
        XCTAssertTrue(reopenedOK)
    }

    func testOpenFutureVersionRefused() async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "DocProj")
        try await store.close()

        // Hand-modify the version stamp (the "written by a future binary"
        // simulation; M2-8-1: the current version is 3, so 4 is the future).
        let handle = try SQLiteHandle(path: packageURL.path)
        try LibrarySchema.writeUserVersion(4, to: handle)
        handle.close()

        let reopened = ProjectFileStore(at: packageURL)
        await assertLibraryError(.futureSchema(version: 4)) {
            try await reopened.open()
        }
        let refusedOpen = await isOpen(reopened)
        XCTAssertFalse(refusedOpen)
    }

    // MARK: - Checkpoint discipline (KD-6 / probe P3)

    func testThrottledCheckpointTruncatesWALAtBatchBoundary() async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "DocProj")

        // Batch 1: below both throttle legs → the WAL stays non-zero.
        try await store.withWriteBatch { handle in
            try LibraryDocumentTests.insertImage(handle, path: "Media/a.arw", stem: "a")
        }
        let earlySize = walSize()
        XCTAssertNotNil(earlySize)
        XCTAssertGreaterThan(earlySize ?? 0, 0, "no checkpoint below the throttle")

        // Batches 2…64: the 64-batch leg fires the TRUNCATE checkpoint.
        for index in 2...64 {
            try await store.withWriteBatch { handle in
                try LibraryDocumentTests.insertImage(
                    handle, path: "Media/img\(index).arw", stem: "img\(index)")
            }
        }
        let truncatedSize = walSize()
        XCTAssertEqual(truncatedSize, 0, "the 64-batch leg must TRUNCATE the WAL")

        // Close forces the checkpoint; the 3.54.0 empty shell remains
        // (0 bytes — probe P3's "one data file + empty companion").
        try await store.close()
        if let sizeAfterClose = walSize() {
            XCTAssertEqual(
                sizeAfterClose, 0,
                "close must leave the WAL at 0 bytes (the P3 empty shell)")
        }
    }

    // MARK: - Backup (the sanctioned copy path)

    func testBackupOnlineCopyIsIndependentlyOpenableAndIdentical() async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "DocProj")
        let rowCount = 25
        for index in 0..<rowCount {
            try await store.withWriteBatch { handle in
                try LibraryDocumentTests.insertImage(
                    handle, path: "Media/b\(index).arw", stem: "b\(index)")
            }
        }

        let backupURL = tempDirectory.appendingPathComponent("DocProj-backup.lalb")
        try await store.backup(to: backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        // The copy opens independently (valid schema, same version) and
        // carries the SAME committed row count (the online consistency).
        XCTAssertEqual(try imageCount(in: backupURL), rowCount)
        XCTAssertEqual(try imageCount(in: packageURL), rowCount)
        try await store.close()
    }

    func testBackupRefusesExistingDestination() async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "DocProj")
        let backupURL = tempDirectory.appendingPathComponent("DocProj-backup.lalb")
        try "occupied".write(to: backupURL, atomically: true, encoding: .utf8)
        await assertLibraryError(
            .backupFailed(detail: "destination already exists: \(backupURL.path)")
        ) { try await store.backup(to: backupURL) }
        try await store.close()
    }

    // MARK: - Close semantics

    func testCloseIsIdempotentAndPostCloseWorkIsNotOpen() async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "DocProj")
        try await store.close()
        try await store.close() // idempotent — no throw

        await assertLibraryError(.notOpen) {
            try await store.backup(
                to: self.tempDirectory.appendingPathComponent("x.lalb"))
        }
    }

    func testWithHandleAfterCloseThrowsNotOpen() async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "DocProj")
        try await store.close()
        await assertLibraryError(.notOpen) {
            _ = try await store.withHandle { handle in
                try handle.execute("SELECT 1")
                return true
            }
        }
    }
}
