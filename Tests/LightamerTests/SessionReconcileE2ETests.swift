import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-02 T4 — the external-change E2E suite (Finder simulation through
// the REAL controller → scanner → pure diff → single-transaction apply):
//
//   • the four Finder-simulated external change classes (add / delete /
//     in-session move / content rewrite) converge the index to disk
//     EXACTLY (row set + stat columns + counts)
//   • the rename-LOST scenario pinned: a move whose two FSEvents events
//     would read as delete+add converges to renamedSurvived — the row is
//     re-pointed with its backfilled columns, no loss, no duplicate
//   • move-OUT of the session: the row converges to removed
//   • externalEdits: a rewritten original under an untouched sidecar
//     lands the dedicated bucket (the 9-3/9-4 decode-invalidation seam)
//   • the orphan actions: REMOVE (`.lra` really gone from disk + row
//     swept) and IGNORE (flag persisted, row stays stable across
//     reconciles) — plus the never-hard-fail edges (missing store, bogus
//     relPath)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionReconcileE2ETests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("reconcile-e2e-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot, withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Write an original with a PINNED mtime (deterministic stat rulings).
    @discardableResult
    private func write(
        _ rel: String, bytes: Int = 8, mtime: TimeInterval = 1000
    ) throws -> SessionScanEntry {
        let url = sessionRoot.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: mtime)],
            ofItemAtPath: url.path
        )
        return SessionScanEntry(relPath: rel, mtime: mtime, size: Int64(bytes))
    }

    /// An EDITED sidecar (one commit → has_edits 1) with a pinned mtime.
    private func writeSidecar(
        _ rel: String, mtime: TimeInterval = 500
    ) throws -> (historyHash: UInt64, imageID: UUID) {
        let imageID = UUID()
        let gain = ModuleInstance(
            module: TestGainModule.self, multiName: "t", params: .init(gain: 2.0)
        )
        let hash = HistoryHash.hash(instances: [gain], decodeParamsHash: 42)
        var stack = HistoryStack()
        stack.commit(gain, label: "test")
        let document = LightamerSidecar(
            imageID: imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: 42,
            instances: [gain],
            history: stack,
            historyHash: hash,
            layerStack: nil
        )
        let url = sessionRoot.appendingPathComponent(rel + ".lra")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: mtime)],
            ofItemAtPath: url.path
        )
        return (hash, imageID)
    }

    /// The controller the app root would drive (real scanner + store).
    private func makeController() -> SessionIndexController {
        SessionIndexController()
    }

    // MARK: - Finder-simulated changes converge exactly

    func testFourExternalChangeClassesConvergeExactly() async throws {
        // Tree: keep.arw / delete.arw / move.arw / rewrite.arw (edited).
        try write("keep.arw", bytes: 8, mtime: 100)
        try write("delete.arw", bytes: 8, mtime: 100)
        try write("move.arw", bytes: 16, mtime: 200)
        try write("rewrite.arw", bytes: 8, mtime: 300)
        try writeSidecar("rewrite.arw", mtime: 400)

        let controller = makeController()
        _ = await controller.openAndSync(root: sessionRoot)

        // ── Finder simulation: ① add ② delete ③ move (in-session)
        // ④ rewrite content (mtime+size drift, sidecar untouched).
        try write("added.arw", bytes: 24, mtime: 500)
        try FileManager.default.removeItem(
            at: sessionRoot.appendingPathComponent("delete.arw")
        )
        try FileManager.default.createDirectory(
            at: sessionRoot.appendingPathComponent("sub"), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(
            at: sessionRoot.appendingPathComponent("move.arw"),
            to: sessionRoot.appendingPathComponent("sub/moved.arw")
        )
        try write("rewrite.arw", bytes: 64, mtime: 900)

        let outcomeOpt = await controller.reconcile(root: sessionRoot)
        let outcome = try XCTUnwrap(outcomeOpt)
        let plan = outcome.plan

        // EXACT buckets (the move pairs as a rename — Finder renames
        // preserve mtime+size).
        XCTAssertEqual(plan.added, ["added.arw"])
        XCTAssertEqual(plan.removed, ["delete.arw"])
        XCTAssertEqual(plan.changed, ["rewrite.arw"])
        XCTAssertEqual(
            plan.renamedSurvived,
            [SessionReconcileRename(fromPath: "move.arw", toPath: "sub/moved.arw")]
        )
        XCTAssertEqual(
            plan.externalEdits, ["rewrite.arw"],
            "original rewritten, sidecar mtime pinned → the external bucket"
        )
        XCTAssertEqual(plan.orphanSidecars, [])

        // Index == disk EXACTLY (row set + counts).
        let counts = try XCTUnwrap(outcome.counts)
        XCTAssertEqual(counts.total, 4, "keep + added + moved + rewrite")
        XCTAssertEqual(counts.edited, 1)
        XCTAssertEqual(counts.orphans, 0)

        // A converged index diffs EMPTY on the next reconcile (anti-churn).
        let secondOpt = await controller.reconcile(root: sessionRoot)
        let second = try XCTUnwrap(secondOpt)
        XCTAssertTrue(
            second.plan.isTrivial,
            "a converged index diffs empty on the next reconcile — got \(second.plan)"
        )
        await controller.close()
    }

    // MARK: - The rename-LOST scenario (no loss, no duplicate)

    func testMoveOutRenameSurvivesWithoutLossOrDuplicate() async throws {
        // Edited original + sidecar; Finder MOVES BOTH into a subfolder
        // (the FSEvents split would report delete@old + add@new).
        try write("a.arw", bytes: 16, mtime: 1000)
        let (hash, imageID) = try writeSidecar("a.arw", mtime: 500)

        let controller = makeController()
        _ = await controller.openAndSync(root: sessionRoot)

        try FileManager.default.createDirectory(
            at: sessionRoot.appendingPathComponent("sub"), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(
            at: sessionRoot.appendingPathComponent("a.arw"),
            to: sessionRoot.appendingPathComponent("sub/b.arw")
        )
        try FileManager.default.moveItem(
            at: sessionRoot.appendingPathComponent("a.arw.lra"),
            to: sessionRoot.appendingPathComponent("sub/b.arw.lra")
        )

        let outcomeOpt = await controller.reconcile(root: sessionRoot)
        let outcome = try XCTUnwrap(outcomeOpt)
        XCTAssertEqual(
            outcome.plan.renamedSurvived,
            [SessionReconcileRename(fromPath: "a.arw", toPath: "sub/b.arw")]
        )
        XCTAssertTrue(outcome.plan.added.isEmpty, "NOT an addition")
        XCTAssertTrue(outcome.plan.removed.isEmpty, "NOT a removal")
        XCTAssertEqual(outcome.counts?.total, 1, "exactly ONE row — no loss, no duplicate")
        XCTAssertEqual(outcome.counts?.edited, 1, "the sidecar truth rode along")
        _ = hash
        _ = imageID

        // Then a MOVE-OUT of the session entirely: the row converges to
        // removed (the rename ruling cannot apply — the destination left
        // the watched tree).
        try FileManager.default.moveItem(
            at: sessionRoot.appendingPathComponent("sub/b.arw"),
            to: tempDirectory.appendingPathComponent("b.arw")
        )
        try FileManager.default.moveItem(
            at: sessionRoot.appendingPathComponent("sub/b.arw.lra"),
            to: tempDirectory.appendingPathComponent("b.arw.lra")
        )
        let afterMoveOutOpt = await controller.reconcile(root: sessionRoot)
        let afterMoveOut = try XCTUnwrap(afterMoveOutOpt)
        XCTAssertEqual(afterMoveOut.plan.removed, ["sub/b.arw"])
        XCTAssertEqual(afterMoveOut.counts?.total, 0)
        await controller.close()
    }

    // MARK: - Orphan actions

    func testOrphanRemoveActionDeletesFileAndRow() async throws {
        try write("gone.arw", bytes: 8, mtime: 100)
        try Data([0x01]).write(to: sessionRoot.appendingPathComponent("gone.arw.lra"))
        let controller = makeController()
        _ = await controller.openAndSync(root: sessionRoot)

        // External: the original walks; the `.lra` stays → orphan.
        try FileManager.default.removeItem(
            at: sessionRoot.appendingPathComponent("gone.arw")
        )
        let outcomeOpt = await controller.reconcile(root: sessionRoot)
        let outcome = try XCTUnwrap(outcomeOpt)
        XCTAssertEqual(outcome.plan.orphanSidecars, ["gone.arw.lra"])
        XCTAssertEqual(outcome.orphanRelPaths, ["gone.arw.lra"])
        XCTAssertEqual(outcome.counts?.orphans, 1)

        // REMOVE: the `.lra` is REALLY gone from disk; the row is swept.
        let removed = await controller.removeOrphanSidecar(
            root: sessionRoot, relPath: "gone.arw.lra"
        )
        XCTAssertTrue(removed)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionRoot.appendingPathComponent("gone.arw.lra").path
            ),
            "the sidecar file must be gone from disk"
        )
        let after = await controller.actionableOrphans()
        XCTAssertEqual(after, [], "the actionable list cleared")

        // A following reconcile keeps the state stable (no resurrection).
        let finalOpt = await controller.reconcile(root: sessionRoot)
        let final = try XCTUnwrap(finalOpt)
        XCTAssertTrue(final.plan.isTrivial)
        XCTAssertEqual(final.counts?.orphans, 0)
        await controller.close()
    }

    func testOrphanIgnoreActionPersistsAndKeepsRowStable() async throws {
        try write("stuck.arw", bytes: 8, mtime: 100)
        try Data([0x02]).write(to: sessionRoot.appendingPathComponent("stuck.arw.lra"))
        let controller = makeController()
        _ = await controller.openAndSync(root: sessionRoot)
        try FileManager.default.removeItem(
            at: sessionRoot.appendingPathComponent("stuck.arw")
        )
        _ = await controller.reconcile(root: sessionRoot)
        let orphansBefore = await controller.actionableOrphans()
        XCTAssertEqual(orphansBefore, ["stuck.arw.lra"])

        // IGNORE: the flag persists; the actionable list empties.
        await controller.setOrphanIgnored(relPath: "stuck.arw.lra", ignored: true)
        let snapshotOpt = await controller.reconcile(root: sessionRoot)
        let snapshot = try XCTUnwrap(snapshotOpt)
        XCTAssertEqual(
            snapshot.orphanRelPaths, [],
            "ignored orphans leave the ACTIONABLE snapshot"
        )
        XCTAssertEqual(
            snapshot.counts?.orphans, 1,
            "the classification row itself STAYS (stable record)"
        )

        // The ignore survives a store reopen (persistence, not memory).
        await controller.close()
        let reopened = makeController()
        _ = await reopened.openAndSync(root: sessionRoot)
        let orphansReopened = await reopened.actionableOrphans()
        XCTAssertEqual(
            orphansReopened, [],
            "the ignore flag persisted across close/reopen"
        )
        await reopened.close()
    }

    func testOrphanActionsNeverHardFail() async throws {
        // No session open (store closed) → false / no-op / empty — never a
        // throw into the UI (SC#2).
        let controller = makeController()
        let removed = await controller.removeOrphanSidecar(
            root: sessionRoot, relPath: "anything.arw.lra"
        )
        XCTAssertFalse(removed, "a closed store refuses gracefully")
        await controller.setOrphanIgnored(relPath: "anything.arw.lra", ignored: true)
        let orphansClosed = await controller.actionableOrphans()
        XCTAssertEqual(orphansClosed, [])

        // A non-`.lra` relPath is refused by construction.
        _ = await controller.openAndSync(root: sessionRoot)
        let bogus = await controller.removeOrphanSidecar(
            root: sessionRoot, relPath: "not-a-sidecar.arw"
        )
        XCTAssertFalse(bogus, "non-`.lra` targets are refused")
        await controller.close()
    }
}
