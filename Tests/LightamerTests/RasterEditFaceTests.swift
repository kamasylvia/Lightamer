import CoreImage
import Foundation
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// RasterEditFaceTests (Plan M4-1-02 T3, KD-2 — APP bundle, the
// FilmCoordinatorTests assembly pattern) — the raster default-record seed
// and the edit-face gating:
//
//   • load seeds the derived aces20 record into the CARRIER (restore
//     first / idempotent / non-raster zero action);
//   • the seed is CARRIER-ONLY — no sidecar file appears until a real
//     edit commits (the 2s-debounce write is never scheduled by the seed);
//   • restore wins over derive (a persisted edited record survives a
//     reload untouched);
//   • undo-to-top KEEPS the raster DRT carrier (the Alcedo「DRT 恒在」
//     semantics — the explicit RAW-deviation);
//   • the default-look mint is SKIPPED for raster documents (upstream D2).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class RasterEditFaceTests: XCTestCase {

    private static let fixtureDirectory: URL = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/TiffRaster", isDirectory: true)
    }()

    private func fixture(_ name: String) throws -> URL {
        let url = Self.fixtureDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("fixture missing: \(name)")
        }
        return url
    }

    private func makeAssembly() async throws -> (
        editorState: EditorState, coordinator: PipeCoordinator,
        workspace: WorkspaceModel, metal: MetalContext
    ) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        let workspace = WorkspaceModel()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry, defaultFace: false)
        return (editorState, coordinator, workspace, metal)
    }

    /// A synthetic (non-raster) decode — the pre-M4-1 carrier face.
    nonisolated private static func decodedGradient(size: Int = 64) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: gradient,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }

    private func editedRecord() -> DrtRecord {
        var record = DrtRecord()
        record.method = .aces20
        record.encodingSpace = .p3d65
        record.encodingEotf = .gamma22
        record.peakLuminance = 400
        return record
    }

    @discardableResult
    private func loadRaster(
        _ name: String, _ assembly: (editorState: EditorState,
        coordinator: PipeCoordinator, workspace: WorkspaceModel,
        metal: MetalContext)
    ) async throws -> (url: URL, decoded: DecodedImage) {
        let url = try fixture(name)
        let decoded = try await RAWDecoder().decode(url)
        await assembly.coordinator.load(
            url: url, decoded: decoded, instances: [], metal: assembly.metal)
        return (url, decoded)
    }

    private func flushUntilPersisted(
        _ sidecarURL: URL, _ coordinator: PipeCoordinator, timeout: TimeInterval = 10
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if FileManager.default.fileExists(atPath: sidecarURL.path) {
                try await Task.sleep(for: .milliseconds(100))
                return
            }
            await coordinator.flushSidecar()
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("the sidecar never persisted within \(timeout)s")
    }

    // MARK: - The seed branches

    func testLoadSeedsDerivedCarrierForRasterDoc() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let assembly = try await makeAssembly()
        let (url, decoded) = try await loadRaster("srgb-matrix-8.tif", assembly)
        let description = try XCTUnwrap(decoded.rasterColor)
        XCTAssertTrue(
            assembly.workspace.hasDrtRecord(for: url),
            "the load must seed the raster derive record")
        let record = assembly.workspace.drtRecord(for: url)
        let expected = RasterDefaultRecord.derive(
            from: description,
            contentProbeMax: decoded.rasterNative?.contentProbeMax ?? 0).record
        XCTAssertEqual(record, expected, "the carrier holds the derive product")
        XCTAssertEqual(record.method, .aces20)
        XCTAssertNotEqual(
            record, DrtRecord(), "a derive product never equals the default record")
    }

    func testLoadSkipsSeedForNonRasterDecode() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let assembly = try await makeAssembly()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("raster-seed-synthetic-\(UUID().uuidString).arw")
        await assembly.coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [],
            metal: assembly.metal)
        XCTAssertFalse(
            assembly.workspace.hasDrtRecord(for: url),
            "a non-raster decode never seeds")
    }

    func testSeedIsCarrierOnlyNoSidecarWrite() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let assembly = try await makeAssembly()
        let (url, _) = try await loadRaster("no-icc-8.tif", assembly)
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sidecarURL.path),
            "the seed must never schedule a sidecar write (carrier-only)")
    }

    func testSeedIdempotentOnRepeatLoad() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let assembly = try await makeAssembly()
        let (url, _) = try await loadRaster("srgb-matrix-16.tif", assembly)
        let first = assembly.workspace.drtRecord(for: url)
        let decoded = try await RAWDecoder().decode(url)
        await assembly.coordinator.load(
            url: url, decoded: decoded, instances: [], metal: assembly.metal)
        XCTAssertEqual(
            assembly.workspace.drtRecord(for: url), first,
            "a repeated open re-derives the identical record")
    }

    func testRestoreWinsOverDerive() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let url = try fixture("srgb-matrix-8.tif")
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        defer { try? FileManager.default.removeItem(at: sidecarURL) }

        // Build a persisted edit through the REAL write path.
        let first = try await makeAssembly()
        let decoded = try await RAWDecoder().decode(url)
        await first.coordinator.load(
            url: url, decoded: decoded, instances: [], metal: first.metal)
        first.editorState.recordDrtChange(editedRecord(), label: "history_drt_param")
        try await flushUntilPersisted(sidecarURL, first.coordinator)

        // A FRESH assembly: the restore leg primes the EDITED record —
        // the seed must not overwrite it with the derive product.
        let second = try await makeAssembly()
        await second.coordinator.load(
            url: url, decoded: decoded, instances: [], metal: second.metal)
        XCTAssertEqual(
            second.workspace.drtRecord(for: url), editedRecord(),
            "restore beats derive")
    }

    func testUndoToTopKeepsRasterDrtCarrier() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let assembly = try await makeAssembly()
        let (url, decoded) = try await loadRaster("srgb-matrix-8.tif", assembly)
        let seeded = assembly.workspace.drtRecord(for: url)

        // One DRT edit, then undo back to the all-default history.
        assembly.editorState.recordDrtChange(editedRecord(), label: "history_drt_param")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(
            assembly.workspace.drtRecord(for: url), editedRecord())
        await assembly.coordinator.undo()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(
            assembly.workspace.drtRecord(for: url), seeded,
            "undo-to-top re-arms the derive record — the render stays DRT")
        XCTAssertTrue(
            assembly.workspace.hasDrtRecord(for: url),
            "the raster tail never drops (the RAW deviation)")
        _ = decoded
    }

    // MARK: - The mint skip

    func testDefaultLookMintSkippedForRasterDocument() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let assembly = try await makeAssembly()
        let url = try fixture("srgb-matrix-8.tif")
        assembly.editorState.load(
            url: url, decoder: RAWDecoder(), metal: assembly.metal,
            logger: EditorState.decodeLogger, defaultLookPending: true)
        // Wait out the decode task.
        let start = Date()
        while assembly.editorState.isDecoding,
              Date().timeIntervalSince(start) < 30
        { try await Task.sleep(for: .milliseconds(100)) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(
            assembly.editorState.decodeError,
            "the raster decode must succeed")
        XCTAssertTrue(
            assembly.editorState.layerStack?.compositeLayers.isEmpty ?? false,
            "the raster document never mints the RAW default look")
        XCTAssertTrue(
            assembly.workspace.hasDrtRecord(for: url),
            "the DRT seed ran inside the load")
    }
}
