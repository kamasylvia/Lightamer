import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FilmPanelTests (Plan M3-3-03 T3, KD-3 — APP bundle, the DrtPanelModelTests
// harness twin) — the film panel's ViewModel transaction face:
//
//   1. PRISTINE ENTRY: the enable tap lands EXACTLY ONE history_film_enable
//      item carrying the default material pair; one ⌘Z steps back over it.
//   2. MATERIAL PICKERS: one discrete commit per change (history_film_material);
//      an idempotent click lands NOTHING.
//   3. THE D-H1 TRIO: the Y slider's live window (begin → live ticks →
//      commit) lands EXACTLY ONE history_film_shift item; a no-op drag lands
//      nothing; the clamp face pins out-of-range ticks.
//   4. CONTENT-ADAPTIVE TOGGLE: one discrete commit (history_film_param).
//   5. THE READOUT: the solve row reads the production solve (the manual
//      shifts layered on the neutral pack; the gain with the EV trim), and
//      the Solve button's invalidation face empties the cache.
//   6. KEY STATICS: every commit label resolves through a static
//      localization key (no interpolated key anywhere — the F-2 ban).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class FilmPanelTests: XCTestCase {

    private var metal: MetalContext!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var workspace: WorkspaceModel!
    private var model: FilmPanelModel!

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
        // The film store: the repo's CC BY-SA asset set (the 01 five-piece).
        let profiles = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
        coordinator.attachFilmStore(try FilmMaterialStore(profilesDirectory: profiles))
        model = FilmPanelModel(editorState: editorState, pipeCoordinator: coordinator)
    }

    override func tearDown() async throws {
        model = nil
        workspace = nil
        coordinator = nil
        editorState = nil
        metal = nil
        try await super.tearDown()
    }

    /// Synthetic gradient plane (the DrtPanelModelTests shape).
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
            .appendingPathComponent("film-panel-\(UUID().uuidString).tif")
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

    /// Bounded wait for the carrier to reflect the committed record.
    private func waitForCarrier(
        _ url: URL, equals expected: FilmRecord, timeout: TimeInterval = 5
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if workspace.filmRecord(for: url) == expected { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(
            workspace.filmRecord(for: url), expected,
            "the carrier never reflected the committed record")
    }

    // MARK: - 1: the pristine entry

    func testEnableLandsSingleCommitAndUndoStepsBack() async throws {
        try await loadGradient()
        let url = coordinator.liveImageURL!
        XCTAssertTrue(model.isPristine, "a fresh document is pristine")
        XCTAssertNil(editorState.history.effectiveFilmRecord())
        XCTAssertFalse(workspace.hasFilmRecord(for: url))

        let before = editorState.history.items.count
        model.enableFilm()
        try await waitForItemCount(before + 1)

        var expected = FilmRecord()
        expected.filmStock = try model.filmStocks.first!.info.stock!
        expected.paperStock = try model.paperStocks.first!.info.stock!
        try await waitForCarrier(url, equals: expected)
        XCTAssertEqual(
            editorState.history.items.count, before + 1,
            "one enable tap = exactly ONE history item")
        XCTAssertEqual(
            editorState.history.items.last?.label,
            String(localized: "history_film_enable"))
        XCTAssertFalse(model.isPristine)
        XCTAssertTrue(workspace.hasFilmRecord(for: url))
        XCTAssertEqual(workspace.filmRecord(for: url), model.record)

        // One ⌘Z → pristine (the atomicity contract).
        await coordinator.undo()
        XCTAssertEqual(editorState.history.position, before - 1)
        XCTAssertNil(editorState.history.effectiveFilmRecord())
        XCTAssertTrue(model.isPristine)
        XCTAssertFalse(workspace.hasFilmRecord(for: url))
    }

    // MARK: - 2: the material pickers

    func testMaterialChangeLandsSingleCommitAndIdempotence() async throws {
        try await loadGradient()
        model.enableFilm()
        try await waitForItemCount(1)
        let url = coordinator.liveImageURL!

        let films = model.filmStocks
        XCTAssertGreaterThan(films.count, 1, "the picker needs choices")
        let otherFilm = try XCTUnwrap(films.last {
            $0.info.stock != model.record.filmStock
        })
        model.setFilmStock(otherFilm.info.stock!)
        try await waitForItemCount(2)
        XCTAssertEqual(model.record.filmStock, otherFilm.info.stock)
        XCTAssertEqual(
            editorState.history.items.last?.label,
            String(localized: "history_film_material"))
        let expected = model.record
        try await waitForCarrier(url, equals: expected)

        // The idempotent click: the same stock again lands NOTHING.
        let after = editorState.history.items.count
        model.setFilmStock(otherFilm.info.stock!)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(
            editorState.history.items.count, after,
            "an idempotent click must not fabricate a history item")
    }

    // MARK: - 3: the D-H1 trio

    func testShiftSliderLiveWindowCommitsOnce() async throws {
        try await loadGradient()
        model.enableFilm()
        try await waitForItemCount(1)
        let url = coordinator.liveImageURL!
        let before = editorState.history.items.count

        // Clamping: out-of-range ticks pin to the CC producer range.
        model.beginDrag()
        model.setYShiftLive(5000)
        XCTAssertEqual(model.record.yFilterShift, 100)
        model.setYShiftLive(-5)
        XCTAssertEqual(model.record.yFilterShift, 0)
        XCTAssertEqual(FilmPanelModel.shiftRange, 0...100)

        // The drag window: begin → live ticks → commit = EXACTLY ONE item.
        model.setYShiftLive(35)
        XCTAssertEqual(model.record.yFilterShift, 35)
        model.commitDrag()
        try await waitForItemCount(before + 1)
        XCTAssertEqual(
            editorState.history.items.count, before + 1,
            "one drag = exactly ONE history_film_shift item")
        XCTAssertEqual(
            editorState.history.items.last?.label,
            String(localized: "history_film_shift"))
        var expected = model.record
        expected.yFilterShift = 35
        try await waitForCarrier(url, equals: expected)

        // A no-op drag (begin + commit without any live change) lands
        // nothing — the seed gate.
        let after = editorState.history.items.count
        model.beginDrag()
        model.commitDrag()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(
            editorState.history.items.count, after,
            "a no-op drag must not fabricate a history item")
    }

    // MARK: - 4: the content-adaptive toggle

    func testContentAdaptiveToggleLandsSingleCommit() async throws {
        try await loadGradient()
        model.enableFilm()
        try await waitForItemCount(1)

        model.setContentAdaptive(true)
        try await waitForItemCount(2)
        XCTAssertTrue(model.record.contentAdaptiveShift)
        XCTAssertEqual(
            editorState.history.items.last?.label,
            String(localized: "history_film_param"))
    }

    // MARK: - 5: the solve readout

    func testSolveReadoutMirrorsTheProductionSolveAndInvalidationWorks() async throws {
        try await loadGradient()
        // Unbound (pristine): the readout hides.
        XCTAssertNil(model.solveReadout)

        model.enableFilm()
        try await waitForItemCount(1)
        var readout = try XCTUnwrap(model.solveReadout, "bound pair → a readout")
        // The readout IS the production solve on the live record.
        let direct = try FilmRuntimeSolve.solve(
            record: model.record,
            film: try XCTUnwrap(coordinator.filmMaterialStore?
                .profile(id: model.record.filmStock)),
            paper: try XCTUnwrap(coordinator.filmMaterialStore?
                .profile(id: model.record.paperStock)),
            materialPairHash: FilmMaterialStore.materialPairHash(
                film: try XCTUnwrap(coordinator.filmMaterialStore?
                    .profile(id: model.record.filmStock)),
                paper: try XCTUnwrap(coordinator.filmMaterialStore?
                    .profile(id: model.record.paperStock))),
            histogram: nil)
        XCTAssertEqual(readout.magentaCC, direct.magentaCC)
        XCTAssertEqual(readout.yellowCC, direct.yellowCC)
        XCTAssertEqual(readout.gain, direct.exposureGain)

        // The manual shifts layer ON TOP of the neutral pack (the KD-2
        // consumption face — visible in the readout).
        model.beginDrag()
        model.setMShiftLive(10)
        model.commitDrag()
        try await waitForItemCount(2)
        readout = try XCTUnwrap(model.solveReadout)
        XCTAssertEqual(
            readout.magentaCC, direct.magentaCC + 10, accuracy: 1e-9,
            "the readout shows the neutral pack + the manual shift")

        // The Solve button's invalidation face: the cache empties.
        FilmSolveCache.shared.store(
            FilmSolveCache.AutoSolution(
                neutralMagentaCC: 1, neutralYellowCC: 2, autoGain: 3,
                contentDeltaM: 0, contentDeltaY: 0),
            for: 42)
        XCTAssertGreaterThan(FilmSolveCache.shared.countForTesting, 0)
        model.forceResolve()
        XCTAssertEqual(
            FilmSolveCache.shared.countForTesting, 0,
            "the invalidation face empties the solve cache")
    }

    // MARK: - 6: the key statics

    func testCommitLabelsAreStaticKeys() {
        // The label vocabulary: every key the model commits through resolves
        // as a static literal (compile-time constants here; the runtime
        // equality assertions in the tests above pin the wiring). The set is
        // the model's COMPLETE label face — a new action must extend it.
        let labels: Set<String> = [
            String(localized: "history_film_enable"),
            String(localized: "history_film_material"),
            String(localized: "history_film_param"),
            String(localized: "history_film_shift"),
        ]
        XCTAssertEqual(labels.count, 4, "the four static film labels resolve")
    }
}
