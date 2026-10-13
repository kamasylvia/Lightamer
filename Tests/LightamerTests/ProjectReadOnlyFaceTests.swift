import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan M6-1-01 T4/T5 (KD-8 golden gate 4): the GUI read-only fallback face —
// the conflict projection (controller + the legacy ride-along, m3a), the
// dialog three legs, the termination flush, the three write-seam guards and
// the red-line self-checks. L009: fixtures on NSTemporaryDirectory.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ProjectReadOnlyFaceTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ro-face-\(UUID().uuidString)", isDirectory: true)
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

    /// A fresh package created through the controller (the production shape).
    private func makePackage(name: String = "Widget") async throws {
        let controller = LibraryProjectController()
        try await controller.createProject(at: packageURL, name: name)
        try await controller.closeProject()
    }

    /// Acquire the package lock as a foreign holder would (second open file
    /// description in this process — the checker o1 semantics) and write the
    /// diagnostics payload.
    @discardableResult
    private func holdPackageLock(pid: Int32 = 4242) throws -> SingleWriterLock {
        let holder = try XCTUnwrap(SingleWriterLock.acquire(at: lockURL).get())
        holder.writePayload(
            SingleWriterLockPayload(
                role: .gui, pid: pid,
                startedAt: SingleWriterLockPayload.nowISO8601()))
        return holder
    }

    // MARK: - T4 前半（6 法）

    /// The typed conflict projects onto `pendingConflict` (url + holder pid
    /// + holder role), the store stays nil. m3a 并档: the SAME method
    /// asserts the legacy ride-along's conflict face — a held session.lock
    /// reports through the handler and fails the sync honestly.
    func testOpenProjectConflictPublishesPendingConflict() async throws {
        try await makePackage()
        let holder = try holdPackageLock(pid: 4242)
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        let conflict = try XCTUnwrap(controller.pendingConflict)
        XCTAssertEqual(conflict.url, packageURL)
        XCTAssertEqual(conflict.holderPid, 4242)
        XCTAssertEqual(conflict.holderRole, "gui")
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertNil(isOpen, "the conflict open leaves no store behind")
        holder.unlock()

        // ── m3a 并档: the legacy session conflict face ──
        let sessionRoot = tempDirectory.appendingPathComponent("legacy-root")
        try FileManager.default.createDirectory(
            at: sessionRoot.appendingPathComponent(".lightamer"),
            withIntermediateDirectories: true)
        let sessionLock = sessionRoot.appendingPathComponent(".lightamer")
            .appendingPathComponent("session.lock")
        let sessionHolder = try XCTUnwrap(
            SingleWriterLock.acquire(at: sessionLock).get())
        let indexController = SessionIndexController()
        var reported: String?
        indexController.sessionLockConflictHandler = { reported = $0 }
        let result = await indexController.openAndSync(root: sessionRoot)
        XCTAssertTrue(result.failed, "a held session.lock fails the open")
        XCTAssertNotNil(reported, "the conflict handler reports the holder")
        XCTAssertTrue(reported?.contains("pid") == true, "copy carries pid info")
        sessionHolder.unlock()
        await indexController.close()
    }

    /// The 只读打开 leg: lockless open, the face flag + the holder pid land,
    /// the project becomes current (the read-only one).
    func testConflictReadOnlyLeg() async throws {
        try await makePackage()
        let holder = try holdPackageLock(pid: 5150)
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        XCTAssertNotNil(controller.pendingConflict)
        try await controller.openProjectReadOnly(at: packageURL)
        XCTAssertTrue(controller.isReadOnly)
        XCTAssertEqual(controller.readOnlyHolderPid, 5150)
        XCTAssertEqual(controller.projectURL, packageURL)
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertTrue(isOpen == true, "the read-only face holds an open store")
        controller.dismissConflict()
        holder.unlock()
        try await controller.closeProject()
    }

    /// The 重试 leg: after the holder exits (the five-state ③ window) the
    /// retry re-acquires the write right — the upgrade path.
    func testConflictRetryLegAfterHolderExit() async throws {
        try await makePackage()
        let holder = try holdPackageLock()
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        XCTAssertNotNil(controller.pendingConflict)
        holder.unlock()
        try await controller.openProject(at: packageURL)
        XCTAssertFalse(controller.isReadOnly, "the retry won the write right")
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertTrue(isOpen == true)
        try await controller.closeProject()
    }

    /// The 取消 leg: dismiss the conflict, open nothing.
    func testConflictCancelLegOpensNothing() async throws {
        try await makePackage()
        let holder = try holdPackageLock()
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        XCTAssertNotNil(controller.pendingConflict)
        controller.dismissConflict()
        XCTAssertNil(controller.pendingConflict)
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertNil(isOpen, "cancel opens nothing")
        holder.unlock()
    }

    /// flushForTermination: the bounded close releases the project lock
    /// (the kernel-side observable) and clears the controller face.
    func testFlushForTerminationReleasesLock() async throws {
        try await makePackage()
        let controller = LibraryProjectController()
        try await controller.openProject(at: packageURL)
        // The open store holds the lock.
        guard case .failure(.heldByOther) = SingleWriterLock.acquire(at: lockURL)
        else {
            return XCTFail("the open project must hold the lock")
        }
        controller.flushForTermination()
        let isOpen = await controller.projectStore?.isOpen
        XCTAssertNil(isOpen, "the termination flush clears the face")
        let second = try XCTUnwrap(
            SingleWriterLock.acquire(at: lockURL).get(),
            "the flush must release the project lock")
        second.unlock()
    }

    /// L057 red line: the runModal ban — zero `.runModal(` hits across the
    /// App sources (the conflict dialog is a SwiftUI sheet, not a modal
    /// panel). Machine-checked here so the ban cannot silently rot.
    func testL057RunModalZeroHits() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        // <repo>/Tests/LightamerTests/<file> → <repo>
        let repoRoot = testFile
            .deletingLastPathComponent()  // Tests/LightamerTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo
        let appSources = repoRoot.appendingPathComponent("App/Sources")
        var hits: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: appSources, includingPropertiesForKeys: nil)
        while let next = enumerator?.nextObject() as? URL {
            guard next.pathExtension == "swift" else { continue }
            guard let source = try? String(contentsOf: next, encoding: .utf8)
            else { continue }
            for (index, line) in source.components(separatedBy: "\n").enumerated()
            where line.contains(".runModal(") {
                hits.append("\(next.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertTrue(
            hits.isEmpty,
            "L057 ban: .runModal( must stay out of App/Sources — \(hits)")
    }
}
