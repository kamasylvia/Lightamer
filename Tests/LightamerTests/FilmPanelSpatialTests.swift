import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FilmPanelSpatialTests (Plan M8-3+ T3 — App; T4/T5 extend the methods) —
// the spatial legs' panel contract:
//
//   1. THE PRISTINE DOUBLE FACE: a nil-legs record is pristine (the
//      hand-extended isPristine keeps the untouched face); setting ANY
//      of the five legs flips it touched (per-field).
//   2. THE OFF-DEFAULT COMMIT FACE: the panel commits no leg until the
//      user acts (enableFilm writes the default PAIR only — all five
//      legs nil; the T4/T5 commit faces extend this file).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class FilmPanelSpatialTests: XCTestCase {

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
            .appendingPathComponent("film-spatial-ui-\(UUID().uuidString).tif")
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
    }

    // MARK: - 1: the pristine double face

    func testNilLegsPristineEachSetLegTouched() async throws {
        try await loadGradient()
        XCTAssertTrue(model.isPristine)
        model.enableFilm()
        XCTAssertFalse(
            model.isPristine, "the enabled pair is touched (stocks bound)")
        // The five legs ride nil at enable (the off-default face).
        let record = model.record
        XCTAssertNil(record.reversalPrintMode)
        XCTAssertNil(record.grainAmount)
        XCTAssertNil(record.halationAmount)
        XCTAssertNil(record.diffusionFamily)
        XCTAssertNil(record.diffusionAmount)
    }

    func testEachLegFlipsPristine() async throws {
        try await loadGradient()
        // A legs-only record (no stocks): each set leg flips pristine.
        // Driven through the history face (the panel's commit funnel
        // owns the discrete items; the pristine gate reads the record).
        var legsOnly = FilmRecord()
        legsOnly.grainAmount = 1.0
        editorState.recordFilmChange(legsOnly, label: "legs")
        XCTAssertFalse(
            model.isPristine, "a grain-only record is touched")
    }

    // MARK: - 2: the off-default commit face (T4/T5 extend)

    func testEnableWritesNoLegs() async throws {
        try await loadGradient()
        model.enableFilm()
        let record = model.record
        XCTAssertFalse(record.filmStock.isEmpty)
        XCTAssertFalse(record.paperStock.isEmpty)
        XCTAssertNil(record.grainAmount, "enable writes no grain leg")
        XCTAssertNil(record.halationAmount, "enable writes no halation leg")
        XCTAssertNil(record.diffusionFamily, "enable writes no diffusion leg")
        XCTAssertNil(record.diffusionAmount, "enable writes no diffusion amount")
    }
}
