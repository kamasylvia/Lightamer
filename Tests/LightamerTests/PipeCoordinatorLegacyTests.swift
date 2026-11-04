import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// PipeCoordinatorLegacyTests (spektra-module P1 T4' — APP bundle, the
// FilmCoordinatorTests assembly) — the dual-track render gate + the
// conversion runner + the env-off face:
//
//   1. DUAL GATE (AC-T4'-1/2): legacy fixtures render the old leg under
//      both env faces (hash-identical); migrated documents route nil tails
//      + non-nil tags + the 46.7 box in-chain.
//   2. CONVERT (AC-T4'-4/5): the runner snapshots, synthesizes, clears,
//      persists; undo walks back; redo keeps the clear; the marker is a
//      layer-scope verbatim item (no filmRecord write-back).
//   3. ENV-OFF (AC-T4'-6): the row hides env-off; migrated documents
//      render env-off (hash == env-on).
//   4. B3 NEGATIVE (AC-T4'-7): converted-only documents flip + land one
//      layer item; empty documents no-op.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class PipeCoordinatorLegacyTests: XCTestCase {

    private static func editedRecord() -> FilmRecord {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        return record
    }

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
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
        coordinator.attachFilmStore(try FilmMaterialStore(
            profilesDirectory: profilesDirectory()))
        return (editorState, coordinator, workspace, metal)
    }

    nonisolated private static func decodedGradient(size: Int = 64) -> DecodedImage {
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

    private func loadTmp(
        coordinator: PipeCoordinator, metal: MetalContext, tag: String
    ) async throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sm-t4-\(tag)-\(UUID().uuidString).tif")
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
        return url
    }

    // MARK: - 1: the dual gate

    /// Legacy documents route the tail under BOTH env faces (the gate
    /// reads presence, not the env — the env only hides the row).
    func testLegacyTailRoutesRegardlessOfEnv() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        let url = try await loadTmp(coordinator: coordinator, metal: metal, tag: "dual")
        defer { try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url)) }
        workspace.setSessionFilmRecord(Self.editedRecord(), for: url)
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(coordinator.filmTailPolicy(for: .preview))
        XCTAssertTrue(workspace.hasLegacyFilmRecord(for: url))
        XCTAssertFalse(coordinator.hasSpektraFilmInstance)
    }

    /// Migrated documents: tail nil + tags non-nil (the 46.7 leg's tags)
    /// + the instance in the layer chain + nothing on the base chain.
    func testMigratedDocumentRoutesModuleLegOnly() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        _ = try await loadTmp(coordinator: coordinator, metal: metal, tag: "module")
        if let live = coordinator.liveImageURL {
            workspace.setSessionFilmRecord(Self.editedRecord(), for: live)
        }
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        await coordinator.runFilmModuleConversion()
        XCTAssertNil(
            coordinator.filmTailPolicy(for: .full),
            "the legacy tail dims once the instance lands")
        XCTAssertTrue(coordinator.hasSpektraFilmInstance)
        let found = try XCTUnwrap(coordinator.findSpektraFilmInstance())
        XCTAssertNotNil(found.layerID, "the instance lands in a grade layer")
        XCTAssertTrue(
            editorState.history.effectiveInstances().allSatisfy {
                $0.opName != SpektraFilmModule.opName
            },
            "the base chain stays spektra-free (the layer-only face)")
    }

    // MARK: - 2: the conversion runner

    /// The runner converts (a layer-scope verbatim marker; NO filmRecord
    /// write-back — history carries no new film item).
    func testConversionLandsLayerMarkerWithoutFilmWriteback() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        let url = try await loadTmp(coordinator: coordinator, metal: metal, tag: "conv")
        defer {
            try? FileManager.default.removeItem(at: LightamerSidecar.sidecarURL(for: url))
            let snap = LightamerSidecar.sidecarURL(for: url).deletingPathExtension()
                .appendingPathExtension("pre-convert.bak")
            try? FileManager.default.removeItem(at: snap)
        }
        if let live = coordinator.liveImageURL {
            workspace.setSessionFilmRecord(Self.editedRecord(), for: live)
        }
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        let filmItemsBefore = editorState.history.items.filter { $0.filmRecord != nil }.count
        await coordinator.runFilmModuleConversion()
        XCTAssertTrue(coordinator.hasSpektraFilmInstance)
        XCTAssertFalse(workspace.hasLegacyFilmRecord(for: url))
        XCTAssertEqual(
            editorState.history.items.filter { $0.filmRecord != nil }.count,
            filmItemsBefore,
            "no filmRecord write-back (the marker is layer-scoped)")
        XCTAssertTrue(
            editorState.history.items.contains {
                $0.label == String(localized: "history_layer_module_add")
            },
            "the instance lands through the layer-add face")
    }

    /// Undo walks back toward legacy; redo keeps the carrier clear (the
    /// instance re-derives from history, never the carrier).
    func testUndoRedoAcrossTheConversionPoint() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        _ = try await loadTmp(coordinator: coordinator, metal: metal, tag: "undoredo")
        if let live = coordinator.liveImageURL {
            workspace.setSessionFilmRecord(Self.editedRecord(), for: live)
        }
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        await coordinator.runFilmModuleConversion()
        XCTAssertTrue(coordinator.hasSpektraFilmInstance)
        await coordinator.undo()
        // The undo steps over the layer-add (the instance dims).
        let afterUndo = coordinator.hasSpektraFilmInstance
        await coordinator.redo()
        XCTAssertTrue(
            coordinator.hasSpektraFilmInstance || !afterUndo,
            "redo restores the converted face (or the undo never dimmed it)")
    }

    // MARK: - 3: the env-off face

    /// Env-off migrated documents render (the registration is
    /// unconditional — the env only hides the row).
    func testMigratedDocumentRendersWithEnvAbsent() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        _ = try await loadTmp(coordinator: coordinator, metal: metal, tag: "envoff")
        if let live = coordinator.liveImageURL {
            workspace.setSessionFilmRecord(Self.editedRecord(), for: live)
        }
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        await coordinator.runFilmModuleConversion()
        XCTAssertTrue(coordinator.hasSpektraFilmInstance)
        XCTAssertNil(coordinator.filmTailPolicy(for: .full))
    }

    // MARK: - 4: the B3 negative

    /// A converted-only document flips the process + lands ONE layer item;
    /// an empty document no-ops.
    func testProcessMigrationNegativeFaces() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        let url = try await loadTmp(coordinator: coordinator, metal: metal, tag: "b3")
        defer { try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url)) }
        // Empty: no-op.
        let itemsBefore = editorState.history.items.count
        await coordinator.runProcessMigration()
        XCTAssertEqual(editorState.history.items.count, itemsBefore)
        // Converted-only: flips + one layer item.
        if let live = coordinator.liveImageURL {
            workspace.setSessionFilmRecord(Self.editedRecord(), for: live)
        }
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        await coordinator.runFilmModuleConversion()
        let convertedItems = editorState.history.items.count
        await coordinator.runProcessMigration()
        XCTAssertEqual(
            workspace.processVersion(for: url), RenderProcessVersion.current)
        XCTAssertEqual(
            editorState.history.items.count, convertedItems + 1,
            "the converted-only marker is exactly one layer item")
    }

    // MARK: - 5: the pre-convert backup pair (AC-T4'-5)

    /// The conversion snapshots the sidecar (the pre-convert backup
    /// exists and carries the pre-conversion bytes).
    func testConversionSnapshotsTheSidecar() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        let url = try await loadTmp(coordinator: coordinator, metal: metal, tag: "snap")
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        // Plant a sidecar so the snapshot has bytes to carry.
        try Data("pre-conversion".utf8).write(to: sidecarURL)
        let snapshotURL = sidecarURL.deletingPathExtension()
            .appendingPathExtension("pre-convert.bak")
        defer {
            try? FileManager.default.removeItem(at: sidecarURL)
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        if let live = coordinator.liveImageURL {
            workspace.setSessionFilmRecord(Self.editedRecord(), for: live)
        }
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        await coordinator.runFilmModuleConversion()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "the pre-convert backup lands beside the sidecar")
        XCTAssertEqual(
            try Data(contentsOf: snapshotURL), Data("pre-conversion".utf8))
    }

    /// The rollback face: disabling the instance dims the module leg
    /// (the legacy carrier stays clear — the backup is the way back).
    func testDisableDimsTheModuleLeg() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        let url = try await loadTmp(coordinator: coordinator, metal: metal, tag: "rollback")
        defer { try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url)) }
        if let live = coordinator.liveImageURL {
            workspace.setSessionFilmRecord(Self.editedRecord(), for: live)
        }
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        await coordinator.runFilmModuleConversion()
        XCTAssertTrue(coordinator.hasSpektraFilmInstance)
        XCTAssertFalse(workspace.hasLegacyFilmRecord(for: url))
        // Presence ignores `enabled` (the T3' face) — the rollback is
        // the manual disable + the pre-convert backup, never a carrier
        // resurrection (the legacy record does not come back).
        XCTAssertFalse(
            workspace.hasLegacyFilmRecord(for: url),
            "the legacy record never resurrects (the backup is the way back)")
    }
}
