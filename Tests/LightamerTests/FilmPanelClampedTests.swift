import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore
// ─────────────────────────────────────────────────────────────────────────────
// FilmPanelClampedTests (Plan M8-3+ T2 — App) — the disclosed + reversal
// panel faces (the FilmPanelSpectralUITests harness twin):
//
//   1. THE DISCLOSED ROW's trigger: the C200×crystal pair's solveClamped
//      reads true (the amber row's model face); the portra×endura pair
//      reads false/nil (no row — the negative face).
//   2. THE C CONVERGENCE: a reversal film's convergedPaperStocks converges
//      onto the print-film pair (2383/2393) with the incumbent paper head;
//      a reversal-bound-on-print pair lists the pair only; a negative
//      film keeps the full list.
//   3. THE MODE COMMIT: setReversalPrintMode commits ONE discrete item
//      (the record flips; idempotent re-set = no item); the mode section
//      shows on reversal films only (isReversalFilm both faces).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class FilmPanelClampedTests: XCTestCase {

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
            .appendingPathComponent("film-clamped-ui-\(UUID().uuidString).tif")
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
    }

    private func bind(film: String, paper: String) async throws {
        try await loadGradient()
        model.enableFilm()
        model.setFilmStock(film)
        model.setPaperStock(paper)
    }

    // MARK: - 1: the disclosed trigger

    func testSolveClampedTrueOnC200FalseOnPortra() async throws {
        try await bind(
            film: "fujifilm_c200", paper: "fujifilm_crystal_archive_typeii")
        XCTAssertEqual(
            model.solveClamped, true,
            "the C200×crystal pair triggers the disclosed amber row")
        try await loadGradient()
        model.enableFilm()
        model.setFilmStock("kodak_portra_400")
        model.setPaperStock("kodak_portra_endura")
        XCTAssertEqual(
            model.solveClamped, false,
            "the safe pair renders no disclosed row")
    }

    // MARK: - 2: the C convergence

    func testConvergedPapersConvergeOnReversalOnly() async throws {
        // Reversal + RA-4 incumbent: the incumbent stays head, the
        // print pair follows (new selections converge).
        try await bind(
            film: "fujifilm_velvia_100", paper: "kodak_portra_endura")
        XCTAssertTrue(model.isReversalFilm)
        let converged = model.convergedPaperStocks.map(\.info.stock)
        XCTAssertEqual(
            converged.first, "kodak_portra_endura",
            "the incumbent paper never jumps")
        XCTAssertTrue(converged.contains("kodak_2383"))
        XCTAssertTrue(converged.contains("kodak_2393"))
        // A record BOUND on print film (hand-set — the picker cannot
        // bind it): the pair only (the convergence target's own face).
        model.setPaperStock("kodak_2383")
        XCTAssertEqual(
            Set(model.convergedPaperStocks.compactMap(\.info.stock)),
            ["kodak_2383", "kodak_2393"],
            "a print-film-bound record lists the pair only (the store "
                + "resolves the pair even though the paper roster "
                + "cannot bind it)")
        // Negative film: the full list (no convergence).
        model.setFilmStock("kodak_portra_400")
        XCTAssertFalse(model.isReversalFilm)
        XCTAssertEqual(
            model.convergedPaperStocks.count, model.paperStocks.count)
    }

    // MARK: - 3: the mode commit

    func testModeCommitLandsOneDiscreteItem() async throws {
        try await bind(
            film: "fujifilm_velvia_100", paper: "kodak_portra_endura")
        XCTAssertNil(model.selectedReversalPrintMode)
        let itemsBefore = editorState.history.items.count
        model.setReversalPrintMode(SpectralNeutralSolve.directPositiveMode)
        XCTAssertEqual(
            model.selectedReversalPrintMode,
            SpectralNeutralSolve.directPositiveMode)
        XCTAssertEqual(
            editorState.history.items.count, itemsBefore + 1,
            "the mode choice lands ONE discrete item")
        // Idempotent re-set = no item.
        model.setReversalPrintMode(SpectralNeutralSolve.directPositiveMode)
        XCTAssertEqual(editorState.history.items.count, itemsBefore + 1)
        // Back to legacy = one more item, nil mode.
        model.setReversalPrintMode(nil)
        XCTAssertNil(model.selectedReversalPrintMode)
        XCTAssertEqual(editorState.history.items.count, itemsBefore + 2)
    }
}
