import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// DrtPanelModelTests (Plan M2-6-3 T2, AC#2 — APP bundle) — the panel's
// ViewModel transaction face:
//
//   1. STRUCTURE: the section list is FEATURE-MAP §5 line-for-line (组序:
//      Method first, always expanded; Color & Encoding second; the method-
//      specific group LAST and ONLY under its method).
//   2. THE ROUTING TABLE: the Display Transform page keeps EXACTLY the
//      Vignette row (checker E1 勘误边界 — Vignette 行原地保留) and its
//      special-content slot is non-none (the live panel's slot).
//   3. PRESET ATOMICITY: one look application = EXACTLY ONE
//      history_drt_preset item; one ⌘Z steps back over it.
//   4. METHOD: a discrete commit; an idempotent click lands NOTHING.
//   5. CUSTOM: the derived judgment — a look snapshot matches → named; a
//      tweaked param → custom.
//   6. PEAK: clamped to 100...1000; the live window (begin/live/commit)
//      lands EXACTLY ONE history_drt_encoding item; a no-op drag lands
//      nothing.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class DrtPanelModelTests: XCTestCase {

    private var metal: MetalContext!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var workspace: WorkspaceModel!
    private var model: DrtPanelModel!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        editorState = EditorState()
        coordinator = PipeCoordinator()
        workspace = WorkspaceModel()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)
        model = DrtPanelModel(
            workspace: workspace, editorState: editorState,
            pipeCoordinator: coordinator)
    }

    override func tearDown() async throws {
        model = nil
        workspace = nil
        coordinator = nil
        editorState = nil
        metal = nil
        try await super.tearDown()
    }

    /// Synthetic gradient plane (EditorMetalLegRegressionTests' shape).
    nonisolated private static func decodedGradient(size: Int = 160) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.55, green: 0.45, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: gradient,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }

    private func loadGradient() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drt-panel-\(UUID().uuidString).tif")
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
    }

    /// Bounded wait for a history item count (the notification Task hop).
    private func waitForItemCount(
        _ count: Int, timeout: TimeInterval = 5
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if editorState.history.items.count >= count { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(
            editorState.history.items.count, count,
            "the history never reached \(count) items")
    }

    /// Bounded wait for the carrier to reflect the committed record (the
    /// drtRecordDidChange Task hop + its re-render precede the sync).
    private func waitForCarrier(
        _ url: URL, equals expected: DrtRecord, timeout: TimeInterval = 5
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if workspace.drtRecord(for: url) == expected { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(
            workspace.drtRecord(for: url), expected,
            "the carrier never reflected the committed record")
    }

    // MARK: - 1: the panel structure (FEATURE-MAP §5 line-for-line)

    func testPanelStructureFollowsTheMethodSwitch() {
        // OpenDRT: Method → Color & Encoding → the preset trio.
        let opendrt = DrtPanelModel.sections(method: .opendrt)
        XCTAssertEqual(opendrt.count, 3)
        XCTAssertEqual(opendrt[0].kind, .method)
        XCTAssertEqual(opendrt[1].kind, .colorEncoding)
        XCTAssertEqual(opendrt[2].kind, .opendrtPresets)
        // ACES 2.0: the limiting group replaces the preset trio.
        let aces = DrtPanelModel.sections(method: .aces20)
        XCTAssertEqual(aces.count, 3)
        XCTAssertEqual(aces[0].kind, .method)
        XCTAssertEqual(aces[1].kind, .colorEncoding)
        XCTAssertEqual(aces[2].kind, .acesLimiting)
        // Every section defaults expanded; the Method card is pinned first
        // (恒展开置顶) and is the ONLY always-expanded-by-contract card.
        for section in opendrt + aces {
            XCTAssertTrue(section.expandedByDefault)
        }
        XCTAssertNotEqual(opendrt[2].kind, aces[2].kind)
    }

    // MARK: - 2: the routing-table face (Vignette 行原地保留)

    func testDisplayTransformPageKeepsVignetteAndThePanelSlot() {
        let rows = EditorTabRoutingTable.panels(for: .displayTransform)
        XCTAssertEqual(rows.count, 1, "exactly one panel row on the page")
        XCTAssertEqual(rows.first?.opName, VignetteModule.opName)
        // The special-content slot is non-none (the live panel's mount).
        XCTAssertNotEqual(
            EditorTabRoutingTable.specialContent(for: .displayTransform),
            .none)
    }

    // MARK: - 3: preset atomicity

    func testPresetApplicationLandsSingleCommitAndUndoStepsBack() async throws {
        try await loadGradient()
        let url = coordinator.liveImageURL!
        let before = editorState.history.items.count

        model.applyLook(.arriba)
        try await waitForItemCount(before + 1)
        var expected = DrtRecord()
        expected.lookPreset = DrtLookPreset.arriba.rawValue
        expected.parameters = DrtLookPreset.arriba.snapshot
        try await waitForCarrier(url, equals: expected)
        XCTAssertEqual(
            editorState.history.items.count, before + 1,
            "one look application = exactly ONE history item")
        XCTAssertEqual(
            editorState.history.items.last?.label,
            String(localized: "history_drt_preset"))
        XCTAssertEqual(model.record.lookPreset, DrtLookPreset.arriba.rawValue)
        XCTAssertEqual(
            model.record.parameters, DrtLookPreset.arriba.snapshot,
            "the look snapshot replaced the parameter group wholesale")
        XCTAssertFalse(model.isCustomLook)
        XCTAssertEqual(
            workspace.drtRecord(for: url), model.record,
            "the carrier followed the commit")

        // One ⌘Z → pristine (the atomicity contract). The items ARRAY keeps
        // the entry (undo moves the pointer only) — assert the pointer and
        // the projections.
        await coordinator.undo()
        XCTAssertEqual(editorState.history.position, before - 1)
        XCTAssertNil(editorState.history.effectiveDrtRecord())
        XCTAssertEqual(model.record, DrtRecord())
        XCTAssertFalse(workspace.hasDrtRecord(for: url))
    }

    // MARK: - 4: the method switch

    func testSetMethodDiscreteCommitAndIdempotence() async throws {
        try await loadGradient()
        let url = coordinator.liveImageURL!
        let before = editorState.history.items.count

        model.setMethod(.aces20)
        try await waitForItemCount(before + 1)
        var expected = DrtRecord()
        expected.method = .aces20
        try await waitForCarrier(url, equals: expected)
        XCTAssertEqual(model.record.method, .aces20)
        XCTAssertEqual(
            editorState.history.items.last?.label,
            String(localized: "history_drt_method"))

        // The idempotent click: the same method again lands NOTHING.
        let after = editorState.history.items.count
        model.setMethod(.aces20)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(
            editorState.history.items.count, after,
            "an idempotent click must not fabricate a history item")
    }

    // MARK: - 5: the derived custom judgment

    func testCustomLookDerivedFromSnapshotMatch() async throws {
        try await loadGradient()
        // The pristine record = the standard snapshot → named, not custom.
        XCTAssertFalse(model.isCustomLook)
        XCTAssertEqual(
            DrtLookPreset(rawValue: model.record.lookPreset), .standard)

        // A tweaked parameter breaks every snapshot match → custom.
        var tweaked = DrtRecord()
        tweaked.parameters.tnCon = 1.9
        workspace.setSessionDrtRecord(tweaked, for: coordinator.liveImageURL!)
        XCTAssertTrue(model.isCustomLook)
        XCTAssertTrue(model.hasImage)
    }

    // MARK: - 6: peak clamp + the live/commit window

    func testPeakClampedAndLiveWindowCommitsOnce() async throws {
        try await loadGradient()
        let before = editorState.history.items.count
        let url = coordinator.liveImageURL!

        // Clamping: out-of-range values pin to the producer range.
        model.setPeakLive(5000)
        XCTAssertEqual(workspace.drtRecord(for: url).peakLuminance, 1000)
        model.setPeakLive(10)
        XCTAssertEqual(workspace.drtRecord(for: url).peakLuminance, 100)
        XCTAssertEqual(
            DrtPanelModel.clampedPeak(480), 480, "in-range values pass through")

        // The drag window: begin → live ticks → commit = EXACTLY ONE item.
        model.beginPeakDrag()
        model.setPeakLive(650)
        XCTAssertEqual(workspace.drtRecord(for: url).peakLuminance, 650)
        model.commitPeak()
        try await waitForItemCount(before + 1)
        XCTAssertEqual(
            editorState.history.items.count, before + 1,
            "one drag = exactly ONE history_drt_encoding item")
        XCTAssertEqual(
            editorState.history.items.last?.label,
            String(localized: "history_drt_encoding"))

        // A no-op drag (begin + commit without any live change) lands
        // nothing — the seed gate (the commitContinuousEdit shape).
        let after = editorState.history.items.count
        model.beginPeakDrag()
        model.commitPeak()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(
            editorState.history.items.count, after,
            "a no-op drag must not fabricate a history item")
    }
}
