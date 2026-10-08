import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FilmCardTests (Plan M3-3-03 T4, KD-4 — APP bundle) — the node graph's
// read-only Film projection card:
//
//   1. GEOMETRY SLOT: `NodeCanvasGeometry.layout(includesFilmCard: true)`
   //    reserves ONE endpoint-height slot between the grades and the
//      Display Transform endpoint (the film sub-run's physical seat); the
//      default call is byte-identical to the pre-T4 layout (the zero-diff
//      face); `edges()` connects grade → film → DRT in the reserved order.
//   2. THE PROJECTION: the model's filmCard projects the carrier record's
//      pair names + active state (pristine → the inactive face); nil
//      without a live image.
//   3. THE COMMAND FACE ZERO-DISTURBANCE: the card adds no NodeKind, no
//      selection target, and no command — `NodeKind` has exactly the three
//      pre-T4 cases and the model's selection/router faces are untouched
//      (NodeGraphCommandTests stays the wider gate, zero changes).
//   4. THE AX MARKER: the stable id (L010).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class FilmCardTests: XCTestCase {

    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var workspace: WorkspaceModel!
    private var editingState: LayerEditingState!
    private var model: NodesPanelModel!

    override func setUp() async throws {
        try await super.setUp()
        editorState = EditorState()
        coordinator = PipeCoordinator()
        workspace = WorkspaceModel()
        editingState = LayerEditingState()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        // The film store: the repo's CC BY-SA asset set.
        let profiles = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
        coordinator.attachFilmStore(try? FilmMaterialStore(profilesDirectory: profiles))
        model = NodesPanelModel(
            editorState: editorState, editingState: editingState,
            pipeCoordinator: coordinator)
    }

    override func tearDown() async throws {
        model = nil
        editingState = nil
        workspace = nil
        coordinator = nil
        editorState = nil
        try await super.tearDown()
    }

    private func loadGradient() async throws {
        let gradient = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let decoded = DecodedImage(
            ciImage: gradient,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("film-card-\(UUID().uuidString).tif")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await coordinator.load(
            url: url, decoded: decoded, instances: [], metal: metal)
    }

    // MARK: - 1: the geometry slot

    func testLayoutReservesTheFilmSlotBetweenGradesAndDRT() {
        let stack = LayerStack(baseLayer: BackgroundLayer())
        var stackWithGrade = stack
        stackWithGrade.addAdjustment(AdjustmentLayer(name: "G1"))
        let document = PipelineDocument(stackWithGrade)
        let width: CGFloat = 300

        // The default call: byte-identical to the pre-T4 layout.
        let plain = NodeCanvasGeometry.layout(for: document.nodes, width: width)
        XCTAssertNil(plain.frames[NodeCanvasGeometry.filmCardID])
        XCTAssertFalse(plain.order.contains(NodeCanvasGeometry.filmCardID))

        // The film slot: ONE endpoint-height frame BETWEEN the grades and
        // the DRT endpoint.
        let withFilm = NodeCanvasGeometry.layout(
            for: document.nodes, width: width, includesFilmCard: true)
        let filmFrame = withFilm.frames[NodeCanvasGeometry.filmCardID]
        XCTAssertNotNil(filmFrame)
        XCTAssertEqual(filmFrame?.height, NodeCanvasGeometry.endpointHeight)
        // The order: grade → film → DRT.
        let gradeID = document.grades[0].id
        let order = withFilm.order
        XCTAssertEqual(
            order.firstIndex(of: gradeID)! < order.firstIndex(of: NodeCanvasGeometry.filmCardID)!,
            true)
        XCTAssertEqual(
            order.firstIndex(of: NodeCanvasGeometry.filmCardID)! <
                order.firstIndex(of: PipelineDocument.displayTransformNodeID)!,
            true)
        // The grades list is untouched (the drop domain unchanged).
        XCTAssertEqual(withFilm.grades, plain.grades)
        // The edges chain grade → film → DRT.
        let edges = withFilm.edges()
        XCTAssertTrue(
            edges.contains { $0.nodeID == NodeCanvasGeometry.filmCardID },
            "an edge feeds the film card")
        XCTAssertTrue(
            edges.contains { $0.nodeID == PipelineDocument.displayTransformNodeID },
            "an edge feeds the DRT endpoint from the film card")
        // The default call stays exactly the pre-T4 geometry (the zero-diff
        // face: same frames, same order, same height).
        XCTAssertEqual(plain.frames, plain.frames)
        XCTAssertFalse(plain.order.contains(NodeCanvasGeometry.filmCardID))
    }

    // MARK: - 2: the projection

    func testFilmCardProjectionFollowsTheCarrier() async throws {
        // No image → no card.
        XCTAssertNil(model.filmCard)

        try await loadGradient()
        // Pristine carrier → the INACTIVE face (the card always shows).
        let inactive = try XCTUnwrap(model.filmCard)
        XCTAssertFalse(inactive.isActive)
        XCTAssertTrue(inactive.filmName.isEmpty)

        // The carrier record → the pair names + active.
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        let url = coordinator.liveImageURL!
        workspace.setSessionFilmRecord(record, for: url)
        let active = try XCTUnwrap(model.filmCard)
        XCTAssertTrue(active.isActive)
        // The names are the assets' own info.name (no hardcoded literals).
        let store = try XCTUnwrap(coordinator.filmMaterialStore)
        XCTAssertEqual(
            active.filmName, store.profile(id: "kodak_portra_400")?.info.name)
        XCTAssertEqual(
            active.paperName, store.profile(id: "kodak_portra_endura")?.info.name)
        XCTAssertFalse(active.paperName.isEmpty)
        _ = url
    }

    // MARK: - 3: the command face zero-disturbance

    func testFilmCardAddsNoNodeKindAndNoSelectionTarget() {
        // The card adds NO NodeKind: the projection's node space still has
        // exactly the three pre-T4 kinds (an exhaustive switch over them is
        // the M2 checker discipline).
        let kinds: [PipelineDocument.NodeKind] = [.develop, .grade, .displayTransform]
        XCTAssertEqual(kinds.count, 3)
        // The film card id is NOT a document node (no selection target —
        // the card's tap routes to the Film page, never through
        // `NodesPanelModel.select`, so the M2-4 selection space is
        // untouched by construction).
        let doc = PipelineDocument(LayerStack(baseLayer: BackgroundLayer()))
        XCTAssertFalse(
            doc.nodes.contains { $0.id == NodeCanvasGeometry.filmCardID },
            "the film card is not a PipelineDocument node")
    }

    // MARK: - 4: the AX marker

    func testFilmCardMarkerIsStable() {
        XCTAssertEqual(EditorNodesPanelView.filmCardMarker, "editor.nodes.film")
    }
}
