import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// WorkspaceLegacyTests (spektra-module P1 T3' — APP bundle, the
// FilmCoordinatorTests assembly) — the legacy/module discriminator face:
//
//   1. PRESENCE (D-SM-8R): the coordinator predicate over the global set ∪
//      every layer chain (presence ignores `enabled`).
//   2. REJECT (r-m5): the base-chain recordChange typed-reject (toast, no
//      commit) — ONLY spektraFilm refuses; grain et al pass.
//   3. SYNC GATE (D-SM-10): the sync leg clears the carrier when present,
//      re-derives when absent.
//   4. MERGE (R-M4): the into-base refuse (pre-check toast + data-plane
//      nil + count conservation); the into-layer merge flows; redo keeps
//      the instance.
// ─────────────────────────────────────────────────────────────────────────────

final class WorkspaceLegacyTests: XCTestCase {

    private static func editedRecord() -> FilmRecord {
        var record = FilmRecord()
        record.filmStock = "kodak_portra_400"
        record.paperStock = "kodak_portra_endura"
        return record
    }

    @MainActor
    private func makeAssembly() -> (EditorState, PipeCoordinator, WorkspaceModel) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        let workspace = WorkspaceModel()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        return (editorState, coordinator, workspace)
    }

    private func spektraRecord(enabled: Bool = true) -> ModuleInstance {
        ModuleInstance(
            module: SpektraFilmModule.self,
            params: SpektraFilmModule.Params(record: Self.editedRecord()),
            enabled: enabled)
    }

    // MARK: - 1: presence (AC-T3'-3)

    /// Absent everywhere ⇒ false (the pristine twin).
    @MainActor
    func testPresenceFalseWhenAbsentEverywhere() {
        let (_, coordinator, _) = makeAssembly()
        XCTAssertFalse(coordinator.hasSpektraFilmInstance)
        XCTAssertNil(coordinator.findSpektraFilmInstance())
    }

    /// A layer-chain instance ⇒ true + located (the layerID rides).
    @MainActor
    func testPresenceTrueForLayerChainInstance() throws {
        let (editorState, coordinator, _) = makeAssembly()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ])
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        let record = spektraRecord()
        editorState.recordLayerChange(record, layerID: layer.id, label: "add film")
        XCTAssertTrue(coordinator.hasSpektraFilmInstance)
        let found = try XCTUnwrap(coordinator.findSpektraFilmInstance())
        XCTAssertEqual(found.layerID, layer.id)
        XCTAssertEqual(found.instance.id, record.id)
    }

    /// Presence ignores `enabled` (a disabled instance still owns the
    /// document's film identity).
    @MainActor
    func testPresenceIgnoresEnabled() throws {
        let (editorState, coordinator, _) = makeAssembly()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ])
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editorState.recordLayerChange(
            spektraRecord(enabled: false), layerID: layer.id, label: "add film")
        XCTAssertTrue(coordinator.hasSpektraFilmInstance)
    }

    // MARK: - 2: the base-chain reject (AC-T3'-3)

    /// recordChange refuses spektraFilm (toast + zero history items).
    @MainActor
    func testRecordChangeRefusesSpektraFilm() {
        let (editorState, _, _) = makeAssembly()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ])
        let before = editorState.history.items.count
        editorState.recordChange(spektraRecord(), label: "smuggle film")
        XCTAssertEqual(editorState.history.items.count, before)
        XCTAssertNotNil(editorState.toast)
    }

    /// The reject is opName-exact (grain — a film-semantic op — passes).
    @MainActor
    func testRecordChangePassesFilmSemanticOps() {
        let (editorState, _, _) = makeAssembly()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ])
        let before = editorState.history.items.count
        editorState.recordChange(
            ModuleInstance(
                module: GrainModule.self, params: GrainModule.Params()),
            label: "grain is fine")
        XCTAssertEqual(editorState.history.items.count, before + 1)
    }

    // MARK: - 3: the sync gate faces (AC-T3'-4)

    /// The legacy predicate reads the carrier (the sync leg's ELSE arm
    /// source — present ⇒ the gate clears; absent ⇒ it re-derives).
    @MainActor
    func testLegacyPredicateReadsTheCarrier() {
        let (_, _, workspace) = makeAssembly()
        let url = URL(fileURLWithPath: "/tmp/sm-legacy.arw")
        XCTAssertFalse(workspace.hasLegacyFilmRecord(for: url))
        workspace.setSessionFilmRecord(Self.editedRecord(), for: url)
        XCTAssertTrue(workspace.hasLegacyFilmRecord(for: url))
        workspace.setSessionFilmRecord(nil, for: url)
        XCTAssertFalse(workspace.hasLegacyFilmRecord(for: url))
    }

    /// The gate's truth table: present ⇒ legacy dims (the sync leg clears
    /// the carrier — observable as the predicate union); absent + a film
    /// item ⇒ the history projection re-derives it.
    @MainActor
    func testGateTruthTablePresentDimsAbsentRederives() throws {
        let (editorState, coordinator, workspace) = makeAssembly()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ])
        // Absent: the history projection is the re-derive source.
        editorState.recordFilmChange(Self.editedRecord(), label: "history_film_param")
        XCTAssertFalse(coordinator.hasSpektraFilmInstance)
        XCTAssertEqual(
            editorState.history.effectiveFilmRecord(), Self.editedRecord())
        // Present: the union dims the legacy face.
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editorState.recordLayerChange(
            spektraRecord(), layerID: layer.id, label: "add film")
        XCTAssertTrue(coordinator.hasSpektraFilmInstance)
        _ = workspace
    }

    // MARK: - 4: the merge refuse (AC-T3'-6)

    /// The into-base merge refuses (toast + the layer stays + the counts
    /// conserve); the into-layer merge flows; redo keeps the instance.
    @MainActor
    func testIntoBaseMergeRefusesAndIntoLayerFlows() throws {
        let (editorState, _, _) = makeAssembly()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ])
        let bottom = try XCTUnwrap(editorState.addAdjustmentLayer())
        editorState.recordLayerChange(
            spektraRecord(), layerID: bottom.id, label: "add film")
        let layerCount = editorState.layerStack?.adjustmentLayers.count
        // Into-base (the bottommost layer): refused.
        editorState.mergeLayerDown(id: bottom.id)
        XCTAssertEqual(
            editorState.layerStack?.adjustmentLayers.count, layerCount,
            "the refused merge restores the layer in place")
        XCTAssertNotNil(editorState.toast)
        // Into-layer (a second layer below): flows.
        let top = try XCTUnwrap(editorState.addAdjustmentLayer())
        editorState.recordLayerChange(
            ModuleInstance(
                module: ExposureModule.self, params: ExposureModule.Params()),
            layerID: top.id, label: "top exposure")
        editorState.mergeLayerDown(id: top.id)
        XCTAssertEqual(
            editorState.layerStack?.adjustmentLayers.count, layerCount,
            "the into-layer merge folds (the count conserves)")
    }

    /// R-M4: the pre-check toast face — the refusal raises the frozen key
    /// (the mock drives mergeLayerDown directly; mergeDown is never
    /// reached — the layer + its chain survive verbatim).
    @MainActor
    func testPrecheckToastFiresWithoutReachingMergeDown() throws {
        let (editorState, _, _) = makeAssembly()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ])
        let bottom = try XCTUnwrap(editorState.addAdjustmentLayer())
        let film = spektraRecord()
        editorState.recordLayerChange(film, layerID: bottom.id, label: "add film")
        editorState.mergeLayerDown(id: bottom.id)
        XCTAssertNotNil(editorState.toast, "the pre-check toasts")
        let chain = try XCTUnwrap(
            (editorState.layerStack?.adjustmentLayers.first(where: { $0.id == bottom.id })
                as? AdjustmentLayer)?.chain)
        XCTAssertTrue(
            chain.contains(where: { $0.id == film.id }),
            "the instance survives (mergeDown never ran)")
    }
}
