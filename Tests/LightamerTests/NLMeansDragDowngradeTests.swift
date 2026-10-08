import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// NLMeansDragDowngradeTests (Plan M3-1-03 T3, KD-3/OQ-6①) — the drag-time
// denoise preview bypass state layer:
//
//   • the bypass is a LIVE-PROJECTION overlay on the DRAGGED instance's
//     identity: the PREVIEW face reads enabled=false while the thumb is
//     down; zero params changes, zero history items;
//   • keyed by INSTANCE IDENTITY (checker 回注 M6) — a second nlmeans
//     record (the layer-embedded shape) is never collateral;
//   • live ticks keep the bypass in force (the panel's ticks carry the
//     stored enabled — the projection enforces the downgrade);
//   • disarm restores the PRIOR enabled (a user-disabled module stays
//     disabled) and the release lands the existing exactly-ONE commit
//     with the ticked params and the untouched enabled — the FULL
//     decision face outside the drag window is byte-identical (the
//     instances truth == the history truth again);
//   • wholesale projection replacement (load / rebuilds) drops an armed
//     bypass — no stale force-false can outlive the gesture.
//
// Metal-free: the trio runs against EditorState + PipeCoordinator with
// no decoded image (historyDidChange no-ops) — the bypass lives entirely
// in the state layer, no pipe involvement (the KD-3 red line).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class NLMeansDragDowngradeTests: XCTestCase {

    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!

    private var nlmeans: ModuleInstance!
    private var siblingNlmeans: ModuleInstance!
    private var exposure: ModuleInstance!

    override func setUp() async throws {
        try await super.setUp()
        editorState = EditorState()
        coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        nlmeans = ModuleInstance(module: NLMeansModule.self, params: .init())
        // The layer-embedded shape: a SECOND nlmeans record with its own
        // identity (different UUID, non-zero multi-priority like a layer
        // chain instance).
        siblingNlmeans = ModuleInstance(
            module: NLMeansModule.self, multiPriority: 1, params: .init())
        exposure = ModuleInstance(module: ExposureModule.self, params: .init())
        editorState.resetHistoryForNewImage(
            defaultInstances: [nlmeans, siblingNlmeans, exposure])
    }

    override func tearDown() async throws {
        editorState = nil
        coordinator = nil
        nlmeans = nil
        siblingNlmeans = nil
        exposure = nil
        try await super.tearDown()
    }

    // MARK: - Faces

    private func record(_ instance: ModuleInstance) -> ModuleInstance {
        // swiftlint:disable:next force_unwrap — test-local lookup of a
        // freshly seeded identity.
        editorState.instances.first { $0.id == instance.id }!
    }

    private func ticked(_ instance: ModuleInstance, strength: Float) -> ModuleInstance {
        var record = instance
        try! record.setParams(
            NLMeansModule.Params(strength: strength), as: NLMeansModule.self)
        return record
    }

    // MARK: - 1: identity keying + the live-projection downgrade

    func testBypassDisablesOnlyTheDraggedInstanceLiveProjection() async {
        coordinator.beginContinuousEdit()
        editorState.setPreviewDenoiseBypass(nlmeans.id, on: true)

        XCTAssertFalse(
            record(nlmeans).enabled,
            "the DRAGGED instance's live projection reads enabled=false")
        XCTAssertTrue(
            record(siblingNlmeans).enabled,
            "the sibling nlmeans (layer-embedded shape) is never collateral")
        XCTAssertTrue(
            record(exposure).enabled, "unrelated modules are untouched")

        // Live ticks keep the bypass in force: the panel's tick record
        // carries the stored enabled (true) — the projection enforces.
        await coordinator.setLiveParams(ticked(nlmeans, strength: 80))
        XCTAssertFalse(
            record(nlmeans).enabled,
            "the tick upsert must NOT resurrect the bypassed instance")

        // History untouched inside the window (zero params, zero items).
        XCTAssertTrue(editorState.history.items.isEmpty)

        editorState.setPreviewDenoiseBypass(nlmeans.id, on: false)
        XCTAssertTrue(record(nlmeans).enabled, "disarm restores the record")
        XCTAssertTrue(editorState.history.items.isEmpty)
    }

    // MARK: - 2: the prior-enabled restore (user-disabled edge)

    func testBypassRestoreRespectsPriorDisabledState() {
        let disabled = ModuleInstance(
            module: NLMeansModule.self, params: .init(), enabled: false)
        editorState.resetHistoryForNewImage(
            defaultInstances: [disabled])

        editorState.setPreviewDenoiseBypass(disabled.id, on: true)
        XCTAssertFalse(record(disabled).enabled)
        editorState.setPreviewDenoiseBypass(disabled.id, on: false)
        XCTAssertFalse(
            record(disabled).enabled,
            "a user-disabled module stays disabled — the prior value restores")

        // Double-arm is a no-op (the prior-value map never corrupts).
        editorState.setPreviewDenoiseBypass(disabled.id, on: true)
        editorState.setPreviewDenoiseBypass(disabled.id, on: true)
        editorState.setPreviewDenoiseBypass(disabled.id, on: false)
        XCTAssertFalse(record(disabled).enabled)

        // Disarm without arm: no-op.
        editorState.setPreviewDenoiseBypass(disabled.id, on: false)
        XCTAssertFalse(record(disabled).enabled)
    }

    // MARK: - 3: the full trio — window zero-history, release one commit

    func testDragWindowKeepsHistoryEmptyAndReleaseCommitsOnceWithUntouchedEnabled() async {
        coordinator.beginContinuousEdit()
        editorState.setPreviewDenoiseBypass(nlmeans.id, on: true)
        await coordinator.setLiveParams(ticked(nlmeans, strength: 30))
        await coordinator.setLiveParams(ticked(nlmeans, strength: 60))
        XCTAssertEqual(
            editorState.history.items.count, 0,
            "ticks inside the bypass window accumulate ZERO history items")

        // Release: disarm FIRST, then the existing single-commit collapse.
        editorState.setPreviewDenoiseBypass(nlmeans.id, on: false)
        await coordinator.commitContinuousEdit(label: "nlmeans")

        XCTAssertEqual(
            editorState.history.items.count, 1,
            "release lands the existing exactly-ONE commit (no new commit face)")
        let committed = record(nlmeans)
        XCTAssertTrue(
            committed.enabled,
            "the committed record carries the untouched enabled (the bypass "
                + "never rode the snapshot)")
        XCTAssertEqual(
            try committed.params(of: NLMeansModule.self).strength, 60.0, accuracy: 1e-6,
            "the ticked params commit (newest tick wins)")
        XCTAssertEqual(
            editorState.history.effectiveInstances().first { $0.id == nlmeans.id }?
                .enabled,
            true,
            "the FULL decision face outside the window == the history truth")
    }

    /// A zero-tick drag (grab + release without a value change) must not
    /// fabricate a commit — the bypass never enters liveEdited.
    func testZeroTickDragFabricatesNoCommit() async {
        coordinator.beginContinuousEdit()
        editorState.setPreviewDenoiseBypass(nlmeans.id, on: true)
        editorState.setPreviewDenoiseBypass(nlmeans.id, on: false)
        await coordinator.commitContinuousEdit(label: "nlmeans")
        XCTAssertEqual(
            editorState.history.items.count, 0,
            "no tick → no touched snapshot → no history item")
    }

    // MARK: - 4: wholesale projection replacement drops an armed bypass

    func testProjectionRebuildDropsAnArmedBypass() {
        editorState.setPreviewDenoiseBypass(nlmeans.id, on: true)
        XCTAssertFalse(record(nlmeans).enabled)

        // The load path (a fresh image while the gesture state lingers).
        let fresh = ModuleInstance(module: NLMeansModule.self, params: .init())
        editorState.resetHistoryForNewImage(defaultInstances: [fresh])
        XCTAssertTrue(
            record(fresh).enabled,
            "the load reset drops the armed bypass — no stale force-false")

        // The commit path self-heals: a truth landing on an armed bypass
        // disarms it (the upsert then stores the snapshot's real enabled).
        editorState.setPreviewDenoiseBypass(fresh.id, on: true)
        XCTAssertFalse(record(fresh).enabled)
        editorState.recordChange(ticked(fresh, strength: 10), label: "nlmeans")
        XCTAssertTrue(
            record(fresh).enabled,
            "the commit disarms the bypass — instances == the history truth")
    }

    // MARK: - 5: the session routing face (the panel→state chain)

    func testSessionFaceRoutesThroughTheCoordinator() {
        let session = InspectorEditSession(coordinator: coordinator)
        session.setPreviewDenoiseBypass(nlmeans.id, on: true)
        XCTAssertFalse(
            record(nlmeans).enabled,
            "the InspectorEditSession face reaches the EditorState projection")
        session.setPreviewDenoiseBypass(nlmeans.id, on: false)
        XCTAssertTrue(record(nlmeans).enabled)
    }
}
