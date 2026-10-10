@testable import LightamerCore
@testable import LightamerIOP
@testable import Lightamer
import XCTest

/// ColorMatchServiceTests (Plan M5-1-02 T6, KD-6 + checker 回注 E5/E6) —
/// the solve orchestration face:
///
/// - the PIPELINE-LEVEL extraction (E6): a headless extraction on a
///   synthetic document face needs NO GUI session; the live-document face
///   and the headless face produce the SAME statistics bytes;
/// - the SOLVE-TWICE stability (E5): after the instance activates, the
///   re-solve re-extracts on the colormatch INPUT plane and lands
///   BYTE-IDENTICAL params (no feedback collapse);
/// - the ATTACH seam: the pure projection (upsert semantics) + the live
///   commit chain (exactly ONE history item, the record landed);
/// - the PRISTINE reference semantics (OQ-7): the reference leg renders
///   the image pristine regardless of any editing chain;
/// - the re-solve invalidation edge.
final class ColorMatchServiceTests: XCTestCase {

    @MainActor
    private func makeAssembly() async throws -> (
        editorState: EditorState, coordinator: PipeCoordinator,
        workspace: WorkspaceModel, metal: MetalContext, registry: ModuleRegistry
    ) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        let workspace = WorkspaceModel()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ColormatchKernel.metalBundle)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry, defaultFace: false)
        return (editorState, coordinator, workspace, metal, registry)
    }

    /// A warm constant-plane decoded image (non-uniform enough for real
    /// spread: the CI constant color renders a flat plane — the stats are
    /// the degenerate-but-valid single-color face).
    nonisolated private static func decodedGradient(
        size: Int = 96, shift: Double = 0
    ) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.45 + shift, green: 0.35, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: gradient,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }

    /// A synthetic reference stats set (a real distribution over the a=b=0
    /// axis — non-degenerate for the solver family).
    nonisolated private static func syntheticReference() throws -> ColorMatchStats {
        try ColorMatchStats.extract(samples: (0..<196).map { bin in
            let v = Float(bin) / 255.0
            return SIMD3<Float>(v, 0.02 * sin(Float(bin)), 0.02 * cos(Float(bin)))
        })
    }

    @MainActor
    private func tempImageURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name)-\(UUID().uuidString).tif")
    }

    @MainActor
    private func cleanupArtifacts(_ url: URL) {
        try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url))
        try? FileManager.default.removeItem(
            at: ColormatchCubeAsset.directory(forImageURL: url))
    }

    // MARK: - The pipeline-level extraction (E6)

    @MainActor
    func testHeadlessExtractionNeedsNoGUISession() async throws {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ColormatchKernel.metalBundle)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let service = ColorMatchService(metal: metal, registry: registry)
        let document = ColorMatchDocument(
            image: Self.decodedGradient(), instances: [], layerStack: nil, imageID: UUID())
        let stats = try await service.extractStats(document: document, bucket: 256)
        XCTAssertGreaterThan(stats.sampleCount, 0)
        // Determinism: the same document face extracts to the same bytes.
        let again = try await service.extractStats(document: document, bucket: 256)
        XCTAssertEqual(again.statsHash, stats.statsHash)
    }

    @MainActor
    func testLiveFaceMatchesTheHeadlessFace() async throws {
        let (editorState, coordinator, _, metal, registry) = try await makeAssembly()
        let service = ColorMatchService(metal: metal, registry: registry)
        let url = tempImageURL("cm-live-face")
        defer { cleanupArtifacts(url) }
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)

        // The LIVE face (the coordinator's document) — the panel's shape.
        let liveStats = try await service.extractSourceStats(
            coordinator: coordinator, editorState: editorState)
        // The HEADLESS face: the SAME document value (decoded image + the
        // same instance set + the same minted ID), no coordinator state —
        // the E6 claim: one API, identical bytes regardless of who
        // produces the document face.
        let headlessDocument = ColorMatchDocument(
            image: Self.decodedGradient(), instances: editorState.instances,
            layerStack: editorState.layerStack,
            imageID: coordinator.currentImageID ?? UUID())
        let headlessStats = try await service.extractStats(
            document: headlessDocument, bucket: ColorMatchExtractBucket.sourcePreviewCap)
        XCTAssertEqual(
            liveStats.statsHash, headlessStats.statsHash,
            "the live face and the headless face are the SAME API (E6)")
    }

    // MARK: - The solve-twice stability (E5)

    @MainActor
    func testSolveTwiceLandsByteIdenticalParams() async throws {
        let (editorState, coordinator, _, metal, registry) = try await makeAssembly()
        let service = ColorMatchService(metal: metal, registry: registry)
        let url = tempImageURL("cm-solve-twice")
        defer { cleanupArtifacts(url) }
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
        let reference = try Self.syntheticReference()

        // Solve #1: the instance does not exist yet (the first-solve face).
        let source1 = try await service.extractSourceStats(
            coordinator: coordinator, editorState: editorState)
        let params1 = try await service.solveAndAttach(
            source: source1, references: [ColorMatchPoolEntry(stats: reference)],
            solver: .cdf, strength: 0.7,
            editorState: editorState, coordinator: coordinator)
        XCTAssertEqual(
            editorState.instances.filter { $0.opName == ColormatchModule.opName }.count, 1)
        let historyAfterFirst = editorState.history.items.count
        XCTAssertNotNil(params1.assetRef)
        XCTAssertNotNil(params1.assetHash)
        // The asset really is on disk beside the image.
        let assetURL = ColormatchCubeAsset.fileURL(
            assetRef: params1.assetRef!, forImageURL: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetURL.path))

        // Solve #2 (the panel's re-solve shape): the instance is ACTIVE
        // now — the plane must STILL be the colormatch input (E5: no
        // feedback), and the product BYTE-IDENTICAL.
        service.invalidateAll()
        let source2 = try await service.extractSourceStats(
            coordinator: coordinator, editorState: editorState)
        XCTAssertEqual(
            source2.statsHash, source1.statsHash,
            "the source plane is decoupled from the instance's own output (E5)")
        let params2 = try await service.solveAndAttach(
            source: source2, references: [ColorMatchPoolEntry(stats: reference)],
            solver: .cdf, strength: 0.7,
            editorState: editorState, coordinator: coordinator)
        XCTAssertEqual(params1, params2, "solve-twice: byte-identical params")
        // The idempotent projection wrote nothing new (the upsert equals
        // the current set → no extra history item).
        XCTAssertEqual(
            editorState.history.items.count, historyAfterFirst,
            "the re-solve's identical projection must not fabricate history")
    }

    // MARK: - The attach seam

    @MainActor
    func testProjectionUpsertSemantics() throws {
        var params = ColormatchModule.Params()
        params.strength = 0.4
        // The CREATE face: the record appends SORTED into an arbitrary set.
        let exposure = ModuleInstance(
            module: ExposureModule.self, multiPriority: 0,
            params: ExposureModule.Params())
        var exposureSorted = exposure
        exposureSorted.iopOrder = 10.0
        let projected = ColorMatchService.projectColormatch(
            current: [exposureSorted], params: params)
        XCTAssertEqual(projected.count, 2)
        XCTAssertEqual(projected.last?.opName, ColormatchModule.opName, "36.5 sorts after 10.0")

        // The REPLACE face: identity preserved, params swapped.
        let existing = ModuleInstance(
            module: ColormatchModule.self, multiPriority: 0,
            params: ColormatchModule.Params())
        let originalID = existing.id
        var stronger = params
        stronger.strength = 0.9
        let replaced = ColorMatchService.projectColormatch(
            current: [exposureSorted, existing], params: stronger)
        let replacedRecord = replaced.first { $0.opName == ColormatchModule.opName }
        XCTAssertEqual(replacedRecord?.id, originalID, "the projection preserves identity")
        let decoded = try XCTUnwrap(replacedRecord?.params(of: ColormatchModule.self))
        XCTAssertEqual(decoded.strength, 0.9)
    }

    @MainActor
    func testAttachLandsOneHistoryItemWithParams() async throws {
        let (editorState, coordinator, _, metal, registry) = try await makeAssembly()
        let service = ColorMatchService(metal: metal, registry: registry)
        let url = tempImageURL("cm-attach")
        defer { cleanupArtifacts(url) }
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
        let source = try await service.extractSourceStats(
            coordinator: coordinator, editorState: editorState)
        let reference = try Self.syntheticReference()
        let before = editorState.history.items.count
        _ = try await service.solveAndAttach(
            source: source, references: [ColorMatchPoolEntry(stats: reference)],
            solver: .gaussianOT, strength: 0.6,
            editorState: editorState, coordinator: coordinator)
        XCTAssertEqual(
            editorState.history.items.count, before + 1,
            "exactly ONE history item per attach")
        let record = try XCTUnwrap(editorState.instances.first {
            $0.opName == ColormatchModule.opName
        })
        let params = try record.params(of: ColormatchModule.self)
        XCTAssertEqual(params.solver, .gaussianOT)
        XCTAssertEqual(params.strength, 0.6)
        XCTAssertNotNil(params.sourceStatsHash)
        XCTAssertNil(params.assetRef, "the linear arm carries no asset")
    }

    // MARK: - The pristine reference semantics (OQ-7)

    @MainActor
    func testReferenceExtractionIsPristineAndCached() async throws {
        let (_, _, _, metal, registry) = try await makeAssembly()
        let service = ColorMatchService(metal: metal, registry: registry)
        // The bundled raster fixture — the reference decode rides the real
        // ImageIO leg (the RAWDecoder's raster arm).
        let referenceURL = try Fixtures.raster("sample-gradient", "tiff")

        let decoder = RAWDecoder()
        let first = try await service.extractReferenceStats(
            imageURL: referenceURL, decoder: decoder)
        XCTAssertGreaterThan(first.sampleCount, 0)
        // The cached face: the second call answers the same bytes.
        let second = try await service.extractReferenceStats(
            imageURL: referenceURL, decoder: decoder)
        XCTAssertEqual(second.statsHash, first.statsHash)

        // The PRISTINE face: the same image run through an EDITING chain
        // (an exposure instance) extracts DIFFERENT source statistics —
        // while the reference leg (instances = []) stays pristine.
        var exposure = ModuleInstance(
            module: ExposureModule.self, multiPriority: 0,
            params: ExposureModule.Params())
        var exposureParams = try exposure.params(of: ExposureModule.self)
        exposureParams.exposure = 1.5
        try exposure.setParams(exposureParams, as: ExposureModule.self)
        let decoded = try await decoder.decode(referenceURL, technicalOverrides: .init())
        let editedDocument = ColorMatchDocument(
            image: decoded, instances: [exposure], layerStack: nil, imageID: UUID())
        let editedStats = try await service.extractStats(document: editedDocument, bucket: nil)
        XCTAssertNotEqual(
            editedStats.statsHash, first.statsHash,
            "the editing chain moves the source face; the reference leg stays pristine")
    }

    // MARK: - The re-solve invalidation edge

    @MainActor
    func testInvalidateAllDropsSessionFaces() async throws {
        let (editorState, coordinator, _, metal, registry) = try await makeAssembly()
        let service = ColorMatchService(metal: metal, registry: registry)
        let url = tempImageURL("cm-invalidate")
        defer { cleanupArtifacts(url) }
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
        let source = try await service.extractSourceStats(
            coordinator: coordinator, editorState: editorState)
        XCTAssertNotNil(service.lastSourceStats)
        let reference = try Self.syntheticReference()
        _ = try await service.solveAndAttach(
            source: source, references: [ColorMatchPoolEntry(stats: reference)],
            solver: .cdf, strength: 0.5,
            editorState: editorState, coordinator: coordinator)
        // The curves are consultable through the shared box (the module's
        // face).
        let forward = ColormatchSharedResolverForward()
        XCTAssertNotNil(
            forward.cdfSolution(
                sourceStatsHash: String(source.statsHash),
                referenceStatsHash: String(reference.statsHash)),
            "the session curves serve the LUT arm after the solve")
        service.invalidateAll()
        XCTAssertNil(service.lastSourceStats, "the re-solve edge drops the source face")
        XCTAssertNil(
            forward.cdfSolution(
                sourceStatsHash: String(source.statsHash),
                referenceStatsHash: String(reference.statsHash)),
            "the session curves drop (the next solve recomputes)")
    }
}
