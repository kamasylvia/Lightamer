import Foundation
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan M6-1-01 T2 (KD-8 golden gates 1/2 store half + checker E2/m3a): the
// `.lalb` project-lock face — role-nil zero-diff, acquire-before-any-write,
// the openReadOnly E2 three-way, the close release order, the backup
// interaction and the legacy session.lock path shape. L009: fixtures on
// NSTemporaryDirectory.
// ─────────────────────────────────────────────────────────────────────────────

final class ProjectLockTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("project-lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Widget.lalb")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    private var lockURL: URL {
        packageURL.deletingPathExtension().appendingPathExtension("lalb.lock")
    }

    /// A fresh v4 package, then user_version stamped DOWN to `version` (the
    /// migration-leg fixture — every migrate slot is idempotent, so a
    /// down-stamped v4 body re-migrates cleanly).
    private func makePackage(stampedVersion version: Int? = nil) async throws {
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.create(name: "Widget")
        try await store.close()
        if let version {
            let handle = try SQLiteHandle(path: packageURL.path)
            defer { handle.close() }
            try LibrarySchema.writeUserVersion(version, to: handle)
        }
    }

    /// KD-2 negative: the role-nil open path is byte-identical legacy
    /// behavior — NO lock file is created, the store opens as before.
    func testOpenWithNilRoleCreatesNoLockFile() async throws {
        try await makePackage()
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.open()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: lockURL.path),
            "a role-nil open must not create the sibling lock file")
        try await store.close()
    }

    /// A held lock → typed `projectHeldByOther` with the holder summary in
    /// the detail (the m3a conflict face's store-level half).
    func testOpenWithRoleHeldByOtherTypedConflict() async throws {
        try await makePackage()
        let holder = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        holder.writePayload(
            SingleWriterLockPayload(
                role: .gui, pid: getpid(),
                startedAt: SingleWriterLockPayload.nowISO8601()))
        let store = ProjectFileStore(at: packageURL)
        do {
            _ = try await store.open(role: .gui)
            XCTFail("open must refuse a held lock")
        } catch let error as LibraryError {
            guard case .projectHeldByOther(let detail) = error else {
                return XCTFail("wrong typed error: \(error)")
            }
            XCTAssertTrue(detail.contains("pid="), "detail carries holder: \(detail)")
        }
        let isOpen = await store.isOpen
        XCTAssertFalse(isOpen, "the refused open leaves no handle behind")
        holder.unlock()
    }

    /// The acquire strictly precedes every write leg: on an old-version
    /// package a held lock refuses the open BEFORE the pre-migrate snapshot
    /// rotation (the E2 concurrency hazard the ordering kills).
    func testAcquirePrecedesMigrationSnapshotLeg() async throws {
        try await makePackage(stampedVersion: 3)
        let holder = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        let store = ProjectFileStore(at: packageURL)
        do {
            _ = try await store.open(role: .headless)
            XCTFail("open must refuse a held lock before migrating")
        } catch let error as LibraryError {
            guard case .projectHeldByOther = error else {
                return XCTFail("wrong typed error: \(error)")
            }
        }
        let snapshot = packageURL.deletingPathExtension()
            .appendingPathExtension("pre-migrate.3-4.bak")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: snapshot.path),
            "no snapshot may exist when the lock refused the open")
        holder.unlock()
    }

    /// The happy migration path: the snapshot + migrate legs run INSIDE the
    /// held lock — the store holds it after open and close() releases it.
    func testMigrationRunsInsideLockAndCloseReleases() async throws {
        try await makePackage(stampedVersion: 3)
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.open(role: .headless)
        let snapshot = packageURL.deletingPathExtension()
            .appendingPathExtension("pre-migrate.3-4.bak")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshot.path),
            "the migration snapshot ran")
        guard case .failure(.heldByOther) = SingleWriterLock.acquire(at: lockURL)
        else {
            return XCTFail("the open store must still hold the project lock")
        }
        try await store.close()
        guard case .success = SingleWriterLock.acquire(at: lockURL) else {
            return XCTFail("close must release the project lock")
        }
    }

    /// The E2 read-only face on a CURRENT package: no lock taken, opens,
    /// and every write batch is the typed `projectReadOnly`.
    func testOpenReadOnlyCurrentVersionWriteBatchTypedRejected() async throws {
        try await makePackage()
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.openReadOnly()
        let isOpen = await store.isOpen
        XCTAssertTrue(isOpen)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: lockURL.path),
            "openReadOnly never locks")
        do {
            _ = try await store.withWriteBatch { _ in () }
            XCTFail("a read-only store must reject write batches")
        } catch let error as LibraryError {
            guard case .projectReadOnly = error else {
                return XCTFail("wrong typed error: \(error)")
            }
        }
        try await store.close()
    }

    /// E2 negative: an OLD-version package read-only-opened is typed-refused
    /// WITHOUT touching the file (no half-migration state, no snapshot).
    func testOpenReadOnlyOnOldVersionTypedRefused() async throws {
        try await makePackage(stampedVersion: 3)
        let store = ProjectFileStore(at: packageURL)
        do {
            _ = try await store.openReadOnly()
            XCTFail("an old-version package must refuse a read-only open")
        } catch let error as LibraryError {
            guard case .projectReadOnly = error else {
                return XCTFail("wrong typed error: \(error)")
            }
        }
        // The file stands unmigrated.
        let handle = try SQLiteHandle(path: packageURL.path)
        let stored = try LibrarySchema.readUserVersion(from: handle)
        handle.close()
        XCTAssertEqual(stored, 3, "the read-only refusal must not migrate")
        let snapshot = packageURL.deletingPathExtension()
            .appendingPathExtension("pre-migrate.3-4.bak")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: snapshot.path),
            "no snapshot on the read-only refusal path")
    }

    /// E2 negative: a zero-byte stub read-only-opened is typed-refused (the
    /// stub's stored==0 leg is the full fresh DDL — a write leg; the stub
    /// stays byte-identical).
    func testOpenReadOnlyOnZeroByteStubTypedRefused() async throws {
        try Data().write(to: packageURL)
        let store = ProjectFileStore(at: packageURL)
        do {
            _ = try await store.openReadOnly()
            XCTFail("a zero-byte stub must refuse a read-only open")
        } catch let error as LibraryError {
            guard case .projectReadOnly = error else {
                return XCTFail("wrong typed error: \(error)")
            }
        }
        let bytes = try Data(contentsOf: packageURL)
        XCTAssertTrue(bytes.isEmpty, "the stub stays byte-identical")
    }

    /// The backup interaction: read-only open still backs up (the ONLY
    /// sanctioned copy path stays available) and the product carries no lock
    /// file (the lock is runtime state, not data).
    func testBackupAllowedInReadOnlyAndNoLockInProduct() async throws {
        try await makePackage()
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.openReadOnly()
        let destination = tempDirectory.appendingPathComponent("Widget-backup.lalb")
        try await store.backup(to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let siblings = try FileManager.default.contentsOfDirectory(
            at: tempDirectory, includingPropertiesForKeys: nil)
        XCTAssertFalse(
            siblings.contains { $0.lastPathComponent.hasSuffix(".lalb.lock") },
            "no lock file rides the backup products: \(siblings)")
        try await store.close()
    }

    /// The close release order (KD-2): checkpoint → handle close → unlock —
    /// a second instance can acquire after a clean close (the five-state ③
    /// window, in-process form).
    func testCloseReleasesLockForSecondInstance() async throws {
        try await makePackage()
        let first = ProjectFileStore(at: packageURL)
        _ = try await first.open(role: .gui)
        guard case .failure(.heldByOther) = SingleWriterLock.acquire(at: lockURL)
        else {
            return XCTFail("the open store holds the lock")
        }
        try await first.close()
        let second = try XCTUnwrap(
            SingleWriterLock.acquire(at: lockURL).get(),
            "close releases the lock for the next instance")
        second.unlock()
    }

    /// m3a: the legacy ride-along's PRIMITIVE-level path shape — the
    /// `<root>/.lightamer/session.lock` acquire + release round-trip (the
    /// controller-level conflict face lives in the APP bundle).
    func testLegacySessionLockPathShape() throws {
        let root = tempDirectory.appendingPathComponent("session-root", isDirectory: true)
        let sessionLock = root.appendingPathComponent(".lightamer")
            .appendingPathComponent("session.lock")
        let first = try XCTUnwrap(
            SingleWriterLock.acquire(at: sessionLock).get(),
            "acquire creates the <root>/.lightamer intermediates")
        guard case .failure(.heldByOther) = SingleWriterLock.acquire(at: sessionLock)
        else {
            return XCTFail("the session lock is exclusive")
        }
        first.unlock()
        guard case .success = SingleWriterLock.acquire(at: sessionLock) else {
            return XCTFail("release lets the next holder in")
        }
    }
}
