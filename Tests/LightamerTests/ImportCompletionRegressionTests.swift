import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// ImportCompletionRegressionTests — defect A (M2-3 walkthrough 真缺陷 A):
// the import run's completion publication never landed — `importProgress`
// never returned to nil, the background-task bar hung forever, `runImport`'s
// tail statements never executed (2/2 GUI repro with a process sample showing
// ZERO import stack frames at 0% CPU — the ImportService actor suspended on
// a never-resumed continuation).
//
// ROOT CAUSE (the pinned mechanism): `runImport`'s progress handler was
// `await MainActor.run { ... }` — every emission BLOCKED the ImportService
// actor until the main thread drained that hop (a structural actor↔main
// mutual dependency). When one hop lost its wake-up on the idle run loop,
// the actor suspended forever and the completion chain died. The fix cuts
// the dependency: the handler hands the snapshot to a detached MainActor
// task and returns immediately, so the import loop and the completion
// publication never wait on a main-executor drain.
//
// These tests pin the CONTRACT both faces:
//   1. the full `runImport` chain publishes completion (`importProgress`
//      back to nil) with rows landed — the GUI-shaped drive (MainActor);
//   2. the fire-and-forget handler preserves snapshot ORDER (Main-queue
//      FIFO) — the monotonic publication face the bar and the adapter
//      consume.
// The hang itself was environment-shaped (idle-run-loop main-executor drain
// loss) and does not reproduce under XCTest; the GUI-level regression face
// is the `-la_import_probe` DEBUG probe (see LightamerApp) which drives the
// production chain inside the real NSApplication event loop.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ImportCompletionRegressionTests: XCTestCase {

    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("import-completion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func makeSource(named name: String, count: Int) throws -> URL {
        let source = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for index in 0..<count {
            try Data("synthetic-\(name)-\(index)".utf8)
                .write(to: source.appendingPathComponent(String(format: "DSC%05d.ARW", index)))
        }
        return source
    }

    /// Contract 1: the full production `runImport` chain (the sheet's
    /// onConfirm Task inherits MainActor — this direct await is the same
    /// isolation shape) must PUBLISH completion: `importProgress` back to
    /// nil, no lingering service, no error, rows landed. The defect left
    /// the bar on "Importing photos…" forever.
    func testRunImportPublishesCompletion() async throws {
        let source = try makeSource(named: "Src", count: 6)
        let suiteName = "import-completion-\(UUID().uuidString)"
        let controller = LibraryProjectController(defaultsSuiteName: suiteName)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let package = root.appendingPathComponent("Proj.lalb")
        _ = try await controller.createProject(at: package, name: "Proj")

        await controller.runImport(
            folder: source,
            choice: ImportModeChoice(mode: .link, remember: false))

        XCTAssertEqual(controller.importProgress, nil,
                       "completion must clear importProgress (the bar's finish signal)")
        XCTAssertEqual(controller.lastError, nil, "the happy path carries no error")

        // Rows landed (the import actually ran — not a silent guard return).
        let handle = try SQLiteHandle(path: package.path)
        defer { handle.close() }
        let statement = try handle.prepare("SELECT COUNT(*) FROM images")
        _ = try statement.step()
        XCTAssertEqual(statement.columnInt(0) ?? 0, 6,
                       "all six link rows must be committed")
    }

    /// Contract 2: the fixed handler shape (fire-and-forget MainActor task)
    /// preserves emission order — the MainActor side observes the snapshots
    /// in EXACTLY the emitted order (Main-queue FIFO). A reordered stream
    /// would flicker the bar backwards (the adapter clamps, the legacy
    /// overlay does not).
    func testFireAndForgetHandlerPreservesSnapshotOrder() async throws {
        actor Inbox {
            var received: [Int] = []
            func append(_ value: Int) { received.append(value) }
        }
        let inbox = Inbox()

        // The runImport handler shape under test: a detached MainActor task
        // per emission — the actor loop never awaits the delivery.
        let deliver: @Sendable (Int) -> Void = { value in
            Task { @MainActor in await inbox.append(value) }
        }

        // Emit 1...64 from off-main (the ImportService actor's shape) and
        // wait for the drain.
        await Task.detached(priority: .utility) {
            for value in 1...64 { deliver(value) }
        }.value
        for _ in 0..<100 where await inbox.received.count < 64 {
            try await Task.sleep(for: .milliseconds(20))
        }

        let received = await inbox.received
        XCTAssertEqual(received, Array(1...64),
                       "snapshot order must survive the fire-and-forget delivery")
    }

    /// Contract 3 (R6, the R5-2 / omp obs-4 zero-row root cause): the nil
    /// terminal is the LAST writer of the run. The delivery coalescer's
    /// queued jobs (window drain / terminal flush) race the run tail's
    /// direct nil write on the main queue; a delivery landing after the
    /// nil resurrects the published progress with no writer behind it, so
    /// the WorkspaceHostView onChange's nil-finish branch — the grid's
    /// `reloadFirstPage`, the row-arrival publication — never fires while
    /// the DB rows sit committed (the probe's "grid rows never arrived"
    /// phenotype). This test drains the main queue AFTER the run and
    /// asserts the terminal stays nil: any late coalescer writer must have
    /// been invalidated before the nil write (the deterministic interleave
    /// itself is pinned in ImportProgressCoalescingTests' invalidation
    /// suite). Assertion face = publication state, not a timed grid wait.
    func testRunImportNilTerminalNeverResurrects() async throws {
        let source = try makeSource(named: "SrcR6", count: 3)
        let suiteName = "import-r6-\(UUID().uuidString)"
        let controller = LibraryProjectController(defaultsSuiteName: suiteName)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let package = root.appendingPathComponent("ProjR6.lalb")
        _ = try await controller.createProject(at: package, name: "ProjR6")

        await controller.runImport(
            folder: source,
            choice: ImportModeChoice(mode: .link, remember: false))
        XCTAssertEqual(controller.importProgress, nil,
                       "the run's terminal is nil")

        // Drain the main queue: every straggler delivery job the run queued
        // gets its turn here. A resurrecting writer flips the state back to
        // non-nil — exactly the zero-row disease the fix removes.
        for _ in 0..<20 {
            await MainActor.run {}
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(
            controller.importProgress, nil,
            "a late coalescer delivery must never resurrect the nil terminal; "
                + "the grid's reloadFirstPage keys on the nil-finish publication")

        // Rows landed (the import actually ran — not a silent guard return).
        let handle = try SQLiteHandle(path: package.path)
        defer { handle.close() }
        let statement = try handle.prepare("SELECT COUNT(*) FROM images")
        _ = try statement.step()
        XCTAssertEqual(statement.columnInt(0) ?? 0, 3,
                       "all three link rows must be committed")
    }

    // MARK: R6-R1 (B-1 second lesion) — the run-end EVENT channel

    /// The instrumented GUI rounds (2026-10-27, /tmp/r6r1-runs) pinned the
    /// second lesion: the WorkspaceHostView onChange OF the nil terminal
    /// fires only ~72%/round — the failing rounds show `fire(.completed)`,
    /// the tail's nil write, a subsequent modifier-body evaluation that
    /// READS nil with the @State adapter alive, and NO final onChange
    /// firing (the value input's re-evaluation is the attribute graph's
    /// own scheduling decision; nil is the run's LAST write, so one missed
    /// propagation is lost forever — the zero-row phenotype). The fix's
    /// primary channel is the tail's direct `onImportRunEnded` event. This
    /// test pins the ordering contract: the event fires in the SAME
    /// main-actor turn as the nil write (the listener observes nil), fires
    /// exactly once, and clears itself (idempotent vs the onChange else-arm
    /// that stays armed as the second channel).
    func testRunEndEventFiresAfterNilTerminalAndClears() async throws {
        let source = try makeSource(named: "SrcR6R1a", count: 3)
        let suiteName = "import-r6r1-a-\(UUID().uuidString)"
        let controller = LibraryProjectController(defaultsSuiteName: suiteName)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let package = root.appendingPathComponent("ProjR6R1a.lalb")
        _ = try await controller.createProject(at: package, name: "ProjR6R1a")

        var fireCount = 0
        var progressAtFire: ImportProgress? =
            ImportProgress(phase: .importing, total: 1, processed: 1)
        controller.onImportRunEnded = {
            fireCount += 1
            progressAtFire = controller.importProgress
        }

        await controller.runImport(
            folder: source, choice: ImportModeChoice(mode: .link, remember: false))

        XCTAssertEqual(fireCount, 1,
                       "the run-end event fires exactly once per run")
        XCTAssertNil(
            progressAtFire,
            "the event fires AFTER the nil terminal write (same main-actor "
                + "turn — the terminal ordering the onChange channel loses)")
        XCTAssertNil(
            controller.onImportRunEnded,
            "the listener clears at fire — the onChange else-arm stays a "
                + "structural no-op (idempotent double channel)")
    }

    /// The deterministic LOSS SHAPE: this process has NO SwiftUI graph, so
    /// the onChange consumer is structurally ABSENT — exactly the failing
    /// rounds' world (the final transition never reaches a consumer). The
    /// production consumer's arm (ImportProgressModifier) mirrors the
    /// onChange arms: register the adapter, apply the terminal snapshot
    /// (the omp stay-alive evidence face: the bar shows "Import complete"
    /// while the grid stays zero-row), route the run-end through the tail
    /// listener. The adapter must finish and the reload must fire — with
    /// the pre-fix code the ONLY channel was the onChange that this world
    /// does not have.
    func testRunEndEventDrivesFinishAndReloadWhenObservationAbsent() async throws {
        let source = try makeSource(named: "SrcR6R1b", count: 3)
        let suiteName = "import-r6r1-b-\(UUID().uuidString)"
        let controller = LibraryProjectController(defaultsSuiteName: suiteName)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let package = root.appendingPathComponent("ProjR6R1b.lalb")
        _ = try await controller.createProject(at: package, name: "ProjR6R1b")

        // The modifier's adapter arm (verbatim shape): adapter registered,
        // terminal snapshot applied, listener armed.
        let registry = BackgroundTaskRegistry()
        let adapter = ImportTaskAdapter(controller: controller)
        registry.register(adapter)
        adapter.apply(ImportProgress(phase: .importing, total: 3, processed: 3))
        adapter.apply(ImportProgress(phase: .completed, total: 3, processed: 3))
        var reloadCount = 0
        controller.onImportRunEnded = { [weak adapter] in
            guard let adapter else { return }
            registry.finish(id: adapter.id)
            reloadCount += 1   // the reloadFirstPage stand-in
        }

        await controller.runImport(
            folder: source, choice: ImportModeChoice(mode: .link, remember: false))

        XCTAssertEqual(
            reloadCount, 1,
            "the tail's direct event must drive the finish+reload even when "
                + "the onChange channel is structurally absent (the second "
                + "lesion's deterministic loss shape)")
        XCTAssertTrue(
            registry.handles.isEmpty,
            "the adapter must be finished (the bar's row leaves)")
    }

    /// An unarmed tail (no consumer — tests, no-shell contexts, a run that
    /// pre-dates the modifier's mount) is a clean no-op; the run still
    /// publishes its nil terminal.
    func testRunEndEventUnarmedTailIsNoOp() async throws {
        let source = try makeSource(named: "SrcR6R1c", count: 3)
        let suiteName = "import-r6r1-c-\(UUID().uuidString)"
        let controller = LibraryProjectController(defaultsSuiteName: suiteName)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let package = root.appendingPathComponent("ProjR6R1c.lalb")
        _ = try await controller.createProject(at: package, name: "ProjR6R1c")
        XCTAssertNil(controller.onImportRunEnded)

        await controller.runImport(
            folder: source, choice: ImportModeChoice(mode: .link, remember: false))
        XCTAssertEqual(controller.importProgress, nil,
                       "an unarmed tail still publishes the nil terminal")
    }
}
