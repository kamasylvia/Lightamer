import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FilmCoordinatorTests (Plan M3-3-02 T5, KD-6 — APP bundle, the
// DrtPersistenceTests harness) — the film persistence four-piece:
//
//   1. CARRIER: per-url isolation, default-absence (缺键 pristine), the
//      editor-close KEEP (R6 — the M8-FIX-1 sister exemption) + the
//      real render-gate inversion (filmTailPolicy resolvable after close).
//   2. COMMIT/UNDO: recordFilmChange lands EXACTLY ONE item; the carrier
//      re-syncs on undo (the syncFilmCarrierWithHistory face).
//   3. RESTORE LEG: a flushed document's filmRecord primes a FRESH
//      assembly's carrier (the field + the item agree); the switch-back
//      skip; the pristine twin.
//   4. RUN PASS-THROUGH: a non-pristine carrier + a live store → the
//      policy; THUMBNAIL恒 nil; an unknown stock = the typed degrade
//      (nil, no crash); no store = nil.
//   5. STORE DEGRADE: a bad directory throws TYPED (no crash) — the
//      assembly's catch keeps the app alive.
// ─────────────────────────────────────────────────────────────────────────────

final class FilmCoordinatorTests: XCTestCase {

    private static func editedRecord(strength: Float = 0.5) -> FilmRecord {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        record.strength = strength
        return record
    }

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    // MARK: - 1: the session carrier

    @MainActor
    func testCarrierPerUrlIsolationAndDefaultAbsence() {
        let workspace = WorkspaceModel()
        let urlA = URL(fileURLWithPath: "/tmp/film-a.arw")
        let urlB = URL(fileURLWithPath: "/tmp/film-b.arw")

        XCTAssertEqual(workspace.filmRecord(for: urlA), FilmRecord())
        XCTAssertFalse(workspace.hasFilmRecord(for: urlA))

        // A DEFAULT record never occupies the map (缺键 pristine).
        workspace.setSessionFilmRecord(FilmRecord(), for: urlA)
        XCTAssertFalse(
            workspace.hasFilmRecord(for: urlA),
            "a default record must not occupy the carrier")

        workspace.setSessionFilmRecord(Self.editedRecord(strength: 0.3), for: urlA)
        workspace.setSessionFilmRecord(Self.editedRecord(strength: 0.8), for: urlB)
        XCTAssertEqual(workspace.filmRecord(for: urlA).strength, 0.3)
        XCTAssertEqual(workspace.filmRecord(for: urlB).strength, 0.8)

        // Undoing back to pristine through the carrier face drops the key.
        workspace.setSessionFilmRecord(nil, for: urlA)
        XCTAssertFalse(workspace.hasFilmRecord(for: urlA))
        XCTAssertTrue(workspace.hasFilmRecord(for: urlB), "the sibling url is untouched")

        // R6: the editor close KEEPS the carrier (the M8-FIX-1 process
        // deviation extended to the film sister — the registered §1.6
        // gap). The disease chain: a same-image reopen runs NO load leg
        // (both guards skip), so a close-time drop left `filmTailPolicy`
        // reading an empty carrier — the film leg silently off until the
        // next film commit/navigation re-synced, the panel reading the
        // history projection and masking the loss.
        workspace.setSessionFilmRecord(Self.editedRecord(strength: 0.7), for: urlA)
        XCTAssertTrue(workspace.hasFilmRecord(for: urlA))
        workspace.closeEditor()
        XCTAssertTrue(
            workspace.hasFilmRecord(for: urlA),
            "close must keep the film carrier — the reopen runs no load leg")
        XCTAssertEqual(
            workspace.filmRecord(for: urlA).strength, 0.7,
            "the render gate's record read must answer the retained record")
    }

    /// R6's disease-chain inversion through the REAL render gate: after
    /// the editor close the film tail policy must still resolve (the
    /// carrier feeds it) — before the fix the close emptied the carrier
    /// and every post-reopen render skipped the film leg.
    @MainActor
    func testCloseKeepsTheFilmTailPolicyResolvable() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("film-close-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url)) }
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
        coordinator.attachFilmStore(try FilmMaterialStore(
            profilesDirectory: profilesDirectory()))

        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(
            coordinator.filmTailPolicy(for: .preview),
            "precondition: the film tail resolves with the carrier primed")

        workspace.closeEditor()
        XCTAssertNotNil(
            coordinator.filmTailPolicy(for: .preview),
            "the close must not starve the film tail — the reopen runs no "
                + "load leg, so the retained carrier is the only re-prime")
    }

    // MARK: - 2: commit once + the undo carrier sync

    @MainActor
    func testRecordFilmChangeCommitsOnceAndUndoSyncsCarrier() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("film-commit-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url)) }
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
        // Seed the store so the run-pass face can resolve.
        coordinator.attachFilmStore(try FilmMaterialStore(
            profilesDirectory: profilesDirectory()))

        let before = editorState.history.items.count
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        XCTAssertEqual(
            editorState.history.items.count, before + 1,
            "EXACTLY ONE item per commit")
        XCTAssertEqual(
            editorState.history.effectiveFilmRecord()?.strength, 0.5)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(workspace.hasFilmRecord(for: url), "the carrier synced")

        // Undo: the carrier re-derives from the HISTORY truth → pristine.
        await coordinator.undo()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(editorState.history.effectiveFilmRecord())
        XCTAssertFalse(
            workspace.hasFilmRecord(for: url),
            "the undo carrier sync drops the key (the DRT twin's face)")
        _ = coordinator
    }

    // MARK: - 3: the restore leg

    @MainActor
    func testRestoreLegPrimesCarrierFromTheDocument() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("film-restore-\(UUID().uuidString).tif")
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        defer { try? FileManager.default.removeItem(at: sidecarURL) }

        // Forge a drift-free document through the REAL write path.
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        try await flushUntilPersisted(sidecarURL, coordinator)
        XCTAssertTrue(workspace.hasFilmRecord(for: url))

        // A FRESH assembly loads the file → the restore leg primes.
        let (editorState2, coordinator2, workspace2, metal2) = try await makeAssembly()
        try await coordinator2.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal2)
        XCTAssertEqual(
            workspace2.filmRecord(for: url).strength, 0.5,
            "the restore leg primed the session carrier")
        XCTAssertEqual(
            editorState2.history.effectiveFilmRecord()?.strength, 0.5,
            "the history item replay carries the same record")
        // The switch-back skip: a second load keeps the record.
        try await coordinator2.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal2)
        XCTAssertEqual(workspace2.filmRecord(for: url).strength, 0.5)
    }

    // MARK: - 4: the run pass-through (thumbnail gate + typed degrades)

    @MainActor
    func testFilmTailPolicyThumbnailAlwaysNilAndDegradesTyped() async throws {
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("film-policy-\(UUID().uuidString).tif")
        _ = editorState
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)

        // No carrier: nil at every resolution.
        XCTAssertNil(coordinator.filmTailPolicy(for: .preview))
        XCTAssertNil(coordinator.filmTailPolicy(for: .thumbnail))

        // A live store + a non-pristine carrier: the policy at PREVIEW,
        // NIL at THUMBNAIL (the KD-4 gate).
        let store = try FilmMaterialStore(profilesDirectory: profilesDirectory())
        coordinator.attachFilmStore(store)
        workspace.setSessionFilmRecord(Self.editedRecord(), for: url)
        let preview = coordinator.filmTailPolicy(for: .preview)
        XCTAssertNotNil(preview)
        XCTAssertEqual(preview?.record.strength, 0.5)
        XCTAssertEqual(preview?.filmProfile?.info.stock, "kodak_portra_400")
        XCTAssertNil(
            coordinator.filmTailPolicy(for: .thumbnail),
            "THUMBNAIL keeps the legacy face in every branch")

        // An unknown stock: the typed degrade (nil — the leg disabled),
        // never a crash.
        var unknown = Self.editedRecord()
        unknown.filmStock = "no_such_stock"
        workspace.setSessionFilmRecord(unknown, for: url)
        XCTAssertNil(coordinator.filmTailPolicy(for: .preview))

        // No store: nil (the face dark).
        coordinator.attachFilmStore(nil)
        workspace.setSessionFilmRecord(Self.editedRecord(), for: url)
        XCTAssertNil(coordinator.filmTailPolicy(for: .preview))
    }

    // MARK: - 5: the store degrade (typed, no crash)

    func testBadStoreDirectoryThrowsTypedAndNeverCrashes() {
        XCTAssertThrowsError(
            try FilmMaterialStore(
                profilesDirectory: URL(fileURLWithPath: "/nonexistent/film/profiles"))
        ) { error in
            XCTAssertEqual(
                error as? FilmMaterialStoreError, .directoryUnreadable,
                "the typed degrade (the assembly's catch keeps the app alive)")
        }
    }

    // MARK: - the harness (DrtPersistenceTests' shape)

    @MainActor
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

    @MainActor
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
}
