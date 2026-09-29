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
}
