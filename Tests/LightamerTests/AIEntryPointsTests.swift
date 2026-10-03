import Foundation
import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// AIEntryPointsTests (Plan M2-10-07 T3, AC#3) — the dual-entry + Inspector
// command faces, the M2-3 marker methodology:
//
//   • MARKERS: the frozen AX marker set (grid context menu ×2, Image menu
//     ×2, Inspector ×3) — the views reference the constants, so the literal
//     pin cannot drift silently
//   • THE BATCH (the v1 顺序单张循环): the queue face advances job-by-job,
//     the final job stays, close clears everything (and stops the client);
//     an empty job set never opens the queue; a re-entry replaces it
//   • THE KEY-ABSENT GUIDANCE: an isolated store with no connection/key
//     reads needsSetup (the Inspector's guidance-row face), and the rating
//     sweep early-outs typed without ever building a controller
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class AIEntryPointsTests: XCTestCase {

    private var suiteName: String!
    private var account: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.aientry.\(UUID().uuidString)"
        account = "rating-provider-entry-\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? AICredentialStore.delete(account ?? "")
        super.tearDown()
    }

    // MARK: - 1: the frozen marker set

    func testEntryCommandMarkersAreTheFrozenSet() {
        let expected: Set<String> = [
            "library.grid.cell.aiUpscale",
            "library.grid.cell.aiDenoise",
            "menu.image.aiUpscale",
            "menu.image.aiDenoise",
            "library.inspector.aiRating",
            "library.inspector.aiDescription",
            "library.inspector.aiSetup",
        ]
        XCTAssertEqual(
            AIEntryPointCoordinator.Marker.all, expected,
            "the entry commands' existence is machine-checkable — the frozen "
                + "marker set is the pin (views reference the constants)")
        XCTAssertEqual(AIEntryPointCoordinator.Marker.all.count, 7)
        for marker in AIEntryPointCoordinator.Marker.all {
            XCTAssertFalse(marker.isEmpty)
        }
    }

    // MARK: - 2: the sequential batch queue (KD-3)

    private func jobs(_ ids: [Int64]) -> [AIEntryPointCoordinator.EnhanceJob] {
        ids.map {
            AIEntryPointCoordinator.EnhanceJob(
                imageID: $0,
                originalURL: URL(fileURLWithPath: "/tmp/\($0).jpg"))
        }
    }

    func testBatchAdvancesJobByJobAndStaysOnTheFinalDoneFace() {
        let coordinator = AIEntryPointCoordinator()
        XCTAssertFalse(coordinator.enhancePresented)

        coordinator.beginQueue(kind: .upscale, jobs: jobs([1, 2, 3]))
        XCTAssertTrue(coordinator.enhancePresented)
        XCTAssertEqual(coordinator.enhanceJobs.count, 3)
        XCTAssertEqual(coordinator.currentJob?.imageID, 1, "the queue starts at the head")
        XCTAssertFalse(coordinator.isLastJob)

        coordinator.advanceIfMore()
        XCTAssertEqual(coordinator.currentJob?.imageID, 2)
        XCTAssertFalse(coordinator.isLastJob)

        coordinator.advanceIfMore()
        XCTAssertEqual(coordinator.currentJob?.imageID, 3)
        XCTAssertTrue(coordinator.isLastJob, "the final job keeps its done face open")
        // Advancing past the end is a no-op (the sheet stays honest).
        coordinator.advanceIfMore()
        XCTAssertEqual(coordinator.currentJob?.imageID, 3)

        coordinator.closeEnhance()
        XCTAssertFalse(coordinator.enhancePresented)
        XCTAssertNil(coordinator.currentJob)
    }

    func testBatchRejectsAnEmptySetAndReplacesARunningQueue() {
        let coordinator = AIEntryPointCoordinator()
        coordinator.beginQueue(kind: .denoise, jobs: [])
        XCTAssertFalse(
            coordinator.enhancePresented, "an empty job set never opens the sheet")

        coordinator.beginQueue(kind: .upscale, jobs: jobs([9]))
        XCTAssertTrue(coordinator.enhancePresented)
        XCTAssertEqual(coordinator.enhanceKind, .upscale)
        coordinator.beginQueue(kind: .denoise, jobs: jobs([7, 8]))
        XCTAssertEqual(coordinator.enhanceKind, .denoise, "a re-entry replaces")
        XCTAssertEqual(coordinator.enhanceJobs.map(\.imageID), [7, 8])
        XCTAssertEqual(coordinator.enhanceIndex, 0, "the replacement restarts at the head")
    }

    func testCloseStopsTheWorkerClient() {
        let coordinator = AIEntryPointCoordinator()
        coordinator.beginQueue(kind: .upscale, jobs: jobs([1]))
        XCTAssertNotNil(coordinator.enhanceClient)
        coordinator.closeEnhance()
        XCTAssertNil(
            coordinator.enhanceClient,
            "the dismissal leg stops the worker client (idempotent stop)")
    }

    // MARK: - 3: the key-absent guidance face

    func testKeyAbsentReadsNeedsSetupAndSweepsEarlyOut() async {
        let coordinator = AIEntryPointCoordinator()
        coordinator.accessStore = LibraryConnectionStore(
            defaultsSuiteName: suiteName, keychainAccount: account!)

        // Nothing configured in the isolated suite → the guidance face.
        coordinator.refreshAccessState()
        XCTAssertTrue(
            coordinator.needsSetup,
            "no connection + no key = the Inspector's guidance row")

        // The sweep early-outs typed: no controller is ever built, no
        // confirm sheet is armed (the commands are hidden when needsSetup;
        // this pins the double-guard).
        await coordinator.runRating(imageIDs: [1, 2])
        XCTAssertNil(coordinator.ratingController)
        XCTAssertFalse(coordinator.ratingConfirmPresented)
        await coordinator.runDescription(imageIDs: [1])
        XCTAssertFalse(coordinator.ratingConfirmPresented)

        // A connection WITHOUT the key still reads needsSetup (the key is
        // the second half of the gate).
        try? coordinator.accessStore.store(AIConnectionConfig(
            protocol: .openAIChatCompletions,
            baseURL: URL(string: "https://api.example.com/v1")!,
            model: "gpt-test"))
        coordinator.refreshAccessState()
        XCTAssertTrue(
            coordinator.needsSetup,
            "a connection without a key cannot run anything remote")
    }

    // MARK: - 4: the WorkspaceModel request face (the menu route)

    func testWorkspaceEnhanceRequestRoundTrip() {
        let workspace = WorkspaceModel()
        XCTAssertNil(workspace.pendingAIEnhance)
        workspace.requestAIEnhance(kind: .denoise, imageIDs: [42])
        XCTAssertEqual(workspace.pendingAIEnhance?.kind, .denoise)
        XCTAssertEqual(workspace.pendingAIEnhance?.imageIDs, [42])
        // One consumption face — the second read sees nothing.
        XCTAssertEqual(workspace.consumeAIEnhance()?.imageIDs, [42])
        XCTAssertNil(workspace.consumeAIEnhance())
    }
}
