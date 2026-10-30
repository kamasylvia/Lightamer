import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FilmPanelBWTests (Plan M9-2 T2 — APP) — the BW faces of the film panel:
//
//   1. THE SECTIONED DATA SOURCE: with the dual-directory store attached,
//      the BW stocks group under their own section (D-M92-7) and the
//      legacy color set stays flat on top.
//   2. THE GRADE PICKER FACE: binding a BW paper makes the grade keys
//      available; a grade commit lands ONE discrete history item with the
//      record's paperGrade verbatim; clearing returns nil.
//   3. THE PRISTINE GATE'S HAND EXTENSION (MIN-5): a grade-only record is
//      NOT pristine (the render face sees a touched session).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class FilmPanelBWTests: XCTestCase {

    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var workspace: WorkspaceModel!
    private var model: FilmPanelModel!

    private var metal: MetalContext!

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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cc = root.appendingPathComponent("Resources/FilmProfiles/profiles")
        let bw = root.appendingPathComponent("Resources/FilmProfilesBW/profiles")
        coordinator.attachFilmStore(try FilmMaterialStore(
            profilesDirectories: [cc, bw]))
        model = FilmPanelModel(editorState: editorState, pipeCoordinator: coordinator)
        // M9-2 T4: the granularity table points at the repo tree (the
        // App default reads the bundle — absent in the test host).
        model.grainCalibrationURL = root
            .appendingPathComponent("Resources/FilmProfilesBW/grain_calibration.json")
        // The commit funnel's placeholder (closeout fix): recordFilmChange
        // guards on `instances.first ?? baseInstances.first` — without a
        // LOADED document both stay nil and every panel commit silently
        // drops (the FilmPanelTests shape: a synthetic gradient load).
        try await loadGradient()
    }

    /// The FilmPanelTests shape — a synthetic gradient through
    /// `coordinator.load` (the placeholder instance seat).
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
            .appendingPathComponent("film-panel-bw-\(UUID().uuidString).tif")
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
    }

    override func tearDown() async throws {
        model = nil; workspace = nil; coordinator = nil; editorState = nil
        try await super.tearDown()
    }

    // MARK: - 1: the sectioned data source

    func testBWStocksGroupIntoTheirOwnSection() {
        let sections = model.filmStockSections
        // The CC set (flat) + the BW section — both present.
        XCTAssertTrue(sections.contains { $0.title == nil && !$0.stocks.isEmpty },
                      "the color set stays flat on top")
        let bw = sections.first { $0.title == "bw" }
        XCTAssertNotNil(bw, "the BW section exists")
        XCTAssertEqual(Set((bw?.stocks ?? []).map { $0.info.stock ?? "" }),
                       ["kodak_tri_x_400", "kodak_tmax_100",
                        "fujifilm_neopan_acros_100_ii", "ilford_hp5_plus_400"],
                       "the four BW films ride the section")
        // The paper picker's twin.
        let paperSections = model.paperStockSections
        let bwPaper = paperSections.first { $0.title == "bw" }
        XCTAssertEqual(bwPaper?.stocks.map { $0.info.stock ?? "" },
                       ["ilford_multigrade_iv_rc"])
    }

    // MARK: - 2: the grade picker face

    func testGradeCommitLandsOneDiscreteItemWithVerbatimKey() {
        // Bind the BW pair first.
        model.setFilmStock("kodak_tri_x_400")
        model.setPaperStock("ilford_multigrade_iv_rc")
        let itemsBefore = editorState.history.items.count
        let keys = model.availableGradeKeys
        XCTAssertEqual(keys.first, "00", "the sorted grade keys (MAJ-1 verbatim)")
        XCTAssertEqual(keys.count, 7, "seven grades")
        XCTAssertTrue(keys.contains("0") && keys.contains("00"),
                      "the 00/0 pair stays distinct strings")

        model.setGrade("3")
        XCTAssertEqual(model.selectedGrade, "3")
        XCTAssertEqual(editorState.history.items.count, itemsBefore + 1,
                       "ONE discrete commit")
        model.setGrade("3")   // idempotent repeat = no extra item
        XCTAssertEqual(editorState.history.items.count, itemsBefore + 1)

        model.setGrade(nil)
        XCTAssertNil(model.selectedGrade, "clearing returns the solver neutral")
        XCTAssertEqual(editorState.history.items.count, itemsBefore + 2)
    }

    // MARK: - 3b (R7 T4, issue #15): the paper-switch grade clear

    /// M9-2 obs-omp3: the grade key is a graded-BW-paper parameter — a
    /// switch onto a COLOR paper clears it in the SAME commit (the
    /// sidecar never carries a `paper_grade` the bound paper cannot
    /// consume), while a switch between graded BW papers keeps it.
    func testPaperSwitchClearsGradeOnlyOnNonGradedPaper() {
        model.setFilmStock("kodak_tri_x_400")
        model.setPaperStock("ilford_multigrade_iv_rc")
        model.setGrade("4")
        XCTAssertEqual(model.selectedGrade, "4")

        // BW → graded BW: the grade survives (the shared ladder memory).
        model.setPaperStock("ilford_multigrade_iv_rc")
        XCTAssertEqual(model.selectedGrade, "4", "the graded-BW switch keeps the grade")

        // BW → color paper: the stale key clears in the SAME commit (ONE
        // history item for the switch — no second grade-clearing item).
        let itemsBefore = editorState.history.items.count
        model.setPaperStock("kodak_endura_premier")
        XCTAssertNil(
            model.selectedGrade,
            "the color paper cannot consume a grade — the key clears")
        XCTAssertEqual(
            editorState.history.items.count, itemsBefore + 1,
            "the clear rides the SAME commit as the switch")
        XCTAssertNil(
            editorState.history.items.last?.filmRecord?.paperGrade,
            "the landed record carries no paper_grade")
    }

    // MARK: - 3: the pristine gate's hand extension

    func testGradeOnlyRecordIsNotPristine() {
        XCTAssertTrue(model.isPristine, "the fresh session is pristine")
        model.setFilmStock("ilford_hp5_plus_400")
        model.setPaperStock("ilford_multigrade_iv_rc")
        XCTAssertFalse(model.isPristine, "a bound pair is touched")
        // Reset to a grade-only touched state via the record face: bind
        // stocks, clear them through the same funnel shape, then set ONLY
        // a grade — the hand-extended gate must still see it touched.
        var record = FilmRecord()
        record.paperGrade = "2"
        editorState.recordFilmChange(record, label: "grade-only")
        XCTAssertFalse(model.isPristine,
                       "a grade-only record is a touched session (MIN-5)")
    }

    // MARK: - 4: M9-2 T3/T4 — the filter picker + the granularity readout

    func testCameraFilterPickerCommitsOneDiscreteItem() {
        model.setFilmStock("kodak_tri_x_400")
        model.setPaperStock("ilford_multigrade_iv_rc")
        // The store's BW directory carries the filter table.
        XCTAssertFalse(model.availableCameraFilters.isEmpty,
                       "the taking-filter table is loaded")
        XCTAssertTrue(model.availableCameraFilters.contains("w25"))
        XCTAssertNil(model.selectedCameraFilter, "the fresh session has no filter")

        let itemsBefore = editorState.history.items.count
        model.setCameraFilter("w25")
        XCTAssertEqual(model.selectedCameraFilter, "w25")
        XCTAssertEqual(editorState.history.items.count, itemsBefore + 1,
                       "ONE discrete commit")
        model.setCameraFilter(nil)
        XCTAssertNil(model.selectedCameraFilter)
        XCTAssertEqual(editorState.history.items.count, itemsBefore + 2)
    }

    func testGranularityReadoutAndOneClickApply() {
        // A calibrated BW film answers the readout; a color film hides it.
        model.setFilmStock("kodak_tri_x_400")
        model.setPaperStock("ilford_multigrade_iv_rc")
        let readout = model.bwGrainReadout
        XCTAssertNotNil(readout, "Tri-X carries the calibration")
        XCTAssertEqual(readout?.publishedRms, 17)
        XCTAssertTrue((0...100).contains(readout?.recommendedStrength ?? -1))

        // HP5 (no published figure) answers NOTHING — the honest null.
        model.setFilmStock("ilford_hp5_plus_400")
        XCTAssertNil(model.bwGrainReadout, "HP5's null stays null")

        // The one-click apply = a plain grain params edit through the
        // existing instance funnel (D-M92-2 — the operator semantic
        // never moves): with a grain instance in the stack, the apply
        // lands ONE discrete item carrying the recommended strength.
        model.setFilmStock("kodak_tri_x_400")
        let grain = ModuleInstance(
            module: GrainModule.self, multiPriority: 0,
            params: GrainModule.Params())
        editorState.recordChange(grain, label: "grain base")
        let itemsBefore = editorState.history.items.count
        // Guarded unwrap (closeout fix): the assert above does NOT stop
        // execution — a nil readout must fail, never crash the host.
        guard let recommended = readout?.recommendedStrength else {
            return XCTFail("the readout vanished before the apply")
        }
        model.applyRecommendedGrainStrength()
        XCTAssertEqual(editorState.history.items.count, itemsBefore + 1,
                       "the apply is ONE discrete item")
        let applied = editorState.instances.first {
            $0.opName == GrainModule.opName
        }
        let params = PanelEditing.params(of: applied!, as: GrainModule.self)
        XCTAssertEqual(Double(params?.strength ?? -1), recommended,
                       accuracy: 0.01,
                       "the grain strength carries the recommended value")
    }
}
