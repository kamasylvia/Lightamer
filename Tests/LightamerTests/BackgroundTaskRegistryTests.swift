import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundTaskRegistryTests (Plan M2-3-1 T6, AC #8) — the three-leg task
// registry contract + the import leg:
//
//   • registry lifecycle: register / update / finish / cancel / cancelAll,
//     multi-task order semantics (insertion order; completion removes)
//   • the import adapter: monotonic clamped snapshots over a fixture
//     ImportProgress stream (a regressed replay never moves the bar back),
//     the phase copy, and the cancel transit (checker E3: straight to the
//     controller's cancelImport route — the spy face)
//   • dual presentation: bar and dialog render the SAME projection — one
//     descriptor function, identical rows
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class BackgroundTaskRegistryTests: XCTestCase {

    // MARK: - Mock handle

    @MainActor
    private final class MockTask: BackgroundTaskHandle {
        let id = UUID()
        let title: String
        var snapshot = BackgroundTaskSnapshot.indeterminate("idle")
        private(set) var cancelCalled = false

        init(_ title: String) {
            self.title = title
        }

        func cancel() async {
            cancelCalled = true
        }
    }

    // MARK: - Registry lifecycle (the four states + multi-task semantics)

    func testRegisterUpdateFinishLifecycle() async {
        let registry = BackgroundTaskRegistry()
        let task = MockTask("Export batch 1")
        registry.register(task)
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.handles.first?.title, "Export batch 1")

        let running = BackgroundTaskSnapshot.fraction(0.4, "12 of 30")
        registry.update(id: task.id, snapshot: running)
        XCTAssertEqual(registry.handle(id: task.id)?.snapshot, running)

        registry.finish(id: task.id)
        XCTAssertEqual(registry.count, 0, "completion removes the task")
    }

    func testCancelRoutesToTheHandleAndRemoves() async {
        let registry = BackgroundTaskRegistry()
        let task = MockTask("AI tagging")
        registry.register(task)

        await registry.cancel(id: task.id)
        XCTAssertTrue(task.cancelCalled, "cancellation routed into the handle")
        XCTAssertEqual(registry.count, 0, "cancellation removes the task")
    }

    func testMultipleTasksPreserveInsertionOrderThroughCompletion() async {
        let registry = BackgroundTaskRegistry()
        let a = MockTask("A")
        let b = MockTask("B")
        let c = MockTask("C")
        registry.register(a)
        registry.register(b)
        registry.register(c)
        XCTAssertEqual(registry.handles.map(\.title), ["A", "B", "C"])

        registry.finish(id: b.id)
        XCTAssertEqual(registry.handles.map(\.title), ["A", "C"], "order survives a middle finish")

        await registry.cancelAll()
        XCTAssertEqual(registry.count, 0)
    }

    func testDuplicateRegistrationIsIgnored() {
        let registry = BackgroundTaskRegistry()
        let task = MockTask("once")
        registry.register(task)
        registry.register(task)
        XCTAssertEqual(registry.count, 1, "the same id registers once")
    }

    // MARK: - The import leg (KD-7 first implementation, checker E3)

    func testImportAdapterSnapshotsAreMonotonicOverTheFixtureStream() {
        // The M2-2-2 progress-shape fixture: scanning → importing (forward)
        // → a REGRESSED replay → terminal phases.
        let adapter = ImportTaskAdapter(title: "Importing Session…", cancelRoute: {})
        adapter.apply(ImportProgress(phase: .scanning, total: 0))
        XCTAssertTrue(adapter.snapshot.isIndeterminate, "scanning = indeterminate")

        adapter.apply(ImportProgress(phase: .importing, total: 100, processed: 5))
        XCTAssertEqual(adapter.snapshot.progress ?? -1, 0.05, accuracy: 1e-9)
        adapter.apply(ImportProgress(phase: .importing, total: 100, processed: 40))
        XCTAssertEqual(adapter.snapshot.progress ?? -1, 0.4, accuracy: 1e-9)
        XCTAssertTrue(adapter.snapshot.detail.contains("40 of 100"))

        // A replayed/out-of-order snapshot NEVER moves the bar backwards.
        adapter.apply(ImportProgress(phase: .importing, total: 100, processed: 12))
        XCTAssertEqual(
            adapter.snapshot.progress ?? -1, 0.4, accuracy: 1e-9,
            "the monotonic clamp holds")

        // Failures and duplicate skips ride the detail copy.
        adapter.apply(ImportProgress(
            phase: .importing, total: 100, processed: 80, failed: 2,
            skippedDuplicates: 3))
        let detail = adapter.snapshot.detail
        XCTAssertTrue(detail.contains("80 of 100"))
        XCTAssertTrue(detail.contains("failed 2"))
        XCTAssertTrue(detail.contains("duplicates skipped 3"))

        adapter.apply(ImportProgress(phase: .completed, total: 100, processed: 100))
        XCTAssertEqual(adapter.snapshot.progress ?? -1, 1.0, accuracy: 1e-9)

        adapter.apply(ImportProgress(phase: .cancelled, total: 100, processed: 50))
        XCTAssertEqual(
            adapter.snapshot.progress ?? -1, 1.0, accuracy: 1e-9,
            "cancel-after-complete keeps the floor")
    }

    func testImportAdapterNeverMovesBackwardsAcrossPhases() {
        let adapter = ImportTaskAdapter(title: "Import", cancelRoute: {})
        adapter.apply(ImportProgress(phase: .importing, total: 10, processed: 9))
        XCTAssertEqual(adapter.snapshot.progress ?? -1, 0.9, accuracy: 1e-9)
        // A restart-shaped stream (total resets mid-flight) still clamps.
        adapter.apply(ImportProgress(phase: .importing, total: 5, processed: 1))
        XCTAssertEqual(adapter.snapshot.progress ?? -1, 0.9, accuracy: 1e-9)
    }

    func testImportAdapterCancelTransitsToTheControllerRoute() async {
        // The checker-E3 transit: the adapter's cancel goes STRAIGHT to the
        // controller's cancelImport route (never into runImport's
        // orchestration — the controller file stays out of the diff).
        let transit = XCTestExpectation(description: "cancelImport transited")
        let adapter = ImportTaskAdapter(title: "Import", cancelRoute: {
            transit.fulfill()
        })
        await adapter.cancel()
        await fulfillment(of: [transit], timeout: 2)
    }

    func testImportAdapterDefaultRouteRidesTheControllerWithoutSideEffects() {
        // The production default: a controller-routed cancel on an idle
        // controller is a safe no-op (no active service — the M2-2 guard).
        let controller = LibraryProjectController()
        let adapter = ImportTaskAdapter(controller: controller)
        Task {
            await adapter.cancel()
        }
        XCTAssertNil(controller.importProgress)
        XCTAssertTrue(adapter.title.contains("Import"))
    }

    // MARK: - Dual presentation (same source by construction)

    func testBarAndDialogRenderTheSameProjection() {
        let registry = BackgroundTaskRegistry()
        let a = MockTask("Import batch")
        a.snapshot = .fraction(0.5, "5 of 10")
        let b = MockTask("Export batch")
        b.snapshot = .indeterminate("Scanning…")
        registry.register(a)
        registry.register(b)

        // ONE projection function — both faces call exactly it, so the rows
        // are identical by construction; the assertion pins the projection.
        let rows = BackgroundTaskProjection.descriptors(in: registry)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], BackgroundTaskDescriptor(
            id: a.id, title: "Import batch", progress: 0.5, detail: "5 of 10"))
        XCTAssertEqual(rows[1], BackgroundTaskDescriptor(
            id: b.id, title: "Export batch", progress: nil, detail: "Scanning…"))
        XCTAssertEqual(
            rows, BackgroundTaskProjection.descriptors(in: registry),
            "the projection is stable across faces")
    }
}
