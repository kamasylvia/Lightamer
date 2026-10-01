import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// VersionSwapTests (Plan M2-8-1 T2, KD-2/KD-4/KD-6; AC#3/4/5 — APP bundle,
// the DrtPersistenceTests real-chain precedent) — the version orchestration
// end-to-end over a REAL EditorState + PipeCoordinator + VersionCoordinator
// assembly (checker E1: no storage backdoors — every swap rides
// `installVersionChain`, every file assertion rides the real SidecarStore
// write path):
//
//   1. MATERIALIZE-ON-FIRST-CREATE: the first create command materializes
//      the implicit chain as Version 1 and lands the new version as the
//      ACTIVE Version 2 (KD-2; the implicit state stays key-less before).
//   2. BRANCH SNAPSHOT TIMING: branching from a jumped-back point copies
//      items[0...position] — the redo tail STAYS in the source version.
//   3. SWITCH ROUND-TRIP BYTE FIDELITY: edit → away → back → the chain's
//      items + position are EXACTLY the original (value-copy identity).
//   4/5. REMOVE EDGES: removing the ACTIVE version activates the list's
//      first slot; removing the LAST version returns to the implicit
//      single-version state with the current chain kept (no edit loss).
//   6. DANGLING activeVersionID: the typed degrade drops the structure
//      (slots empty) and keeps the history (KD-2; the decode-layer input
//      face is SidecarV7Tests').
//   7. CROSS-IMAGE POLLUTION (checker E4): A (multi-version) → B (no
//      version keys) clears the slots to the implicit state, and B's
//      first create starts counting at 「版本 1」 — never 「版本 3」.
//   8. PRISTINE NARROWING (KD-6 ①): an empty-chain version creation
//      births the .lra with position == -1 and 2 slots (zero edits +
//      version structure coexist).
//   9. SWITCH PERSISTS: the flushed file reflects the post-swap state
//      (versions keys + the active id + the swapped-in history).
//   10. DRT CARRIER RE-SYNC: the session carrier re-derives from the
//      post-swap history (the M2-6-3 restore-leg shape).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class VersionSwapTests: XCTestCase {

    private static let decoder = JSONDecoder()

    // MARK: - Assembly (the DrtPersistenceTests production-minus-window shape)

    private func makeAssembly() async throws -> (
        editorState: EditorState, coordinator: PipeCoordinator,
        versionCoordinator: VersionCoordinator, workspace: WorkspaceModel,
        metal: MetalContext
    ) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        let versionCoordinator = VersionCoordinator()
        let workspace = WorkspaceModel()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        versionCoordinator.attach(
            editorState: editorState, pipeCoordinator: coordinator)
        editorState.attach(versionCoordinator: versionCoordinator)
        coordinator.attach(versionCoordinator: versionCoordinator)
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry, defaultFace: false)
        return (editorState, coordinator, versionCoordinator, workspace, metal)
    }

    private nonisolated static func decodedGradient(size: Int = 160) -> DecodedImage {
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

    private func load(
        _ url: URL, into coordinator: PipeCoordinator, metal: MetalContext
    ) async throws {
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
    }

    /// One committed exposure edit at `ev` (the discrete commit face).
    private func commitEdit(
        _ editorState: EditorState, ev: Float, label: String
    ) {
        var params = ExposureModule.Params()
        params.exposure = ev
        editorState.recordChange(
            ModuleInstance(module: ExposureModule.self, params: params), label: label)
    }

    /// Bounded flush-until-persisted (the DrtPersistenceTests shape).
    private func flushUntilPersisted(
        _ sidecarURL: URL, _ coordinator: PipeCoordinator, timeout: TimeInterval = 10
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if FileManager.default.fileExists(atPath: sidecarURL.path) {
                try await Task.sleep(for: .milliseconds(100))
                return
            }
            try await Task.sleep(for: .milliseconds(100))
            await coordinator.flushSidecar()
        }
        XCTFail("the sidecar file never appeared: \(sidecarURL.lastPathComponent)")
    }

    /// Let the coordinator notification Task settle (the 200ms beat).
    private func settleNotifications() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func tempURL(_ prefix: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).tif")
    }

    // MARK: - 1: materialize-on-first-create

    func testFirstCreateMaterializesImplicitChainAndActivatesNewVersion() throws {
        let editorState = EditorState()
        let versions = VersionCoordinator()
        versions.attach(
            editorState: editorState,
            pipeCoordinator: PipeCoordinator())

        // The implicit state: no slots, no active id.
        XCTAssertFalse(versions.hasVersionStructure)
        XCTAssertNil(versions.activeVersionID)

        // First create: the implicit chain materializes as Version 1
        // (captured — its empty chain rides the slot from now on) and the
        // new EMPTY version activates as Version 2.
        versions.createFromScratch()
        XCTAssertEqual(versions.slots.count, 2)
        XCTAssertEqual(versions.slots[0].name, "Version 1")
        XCTAssertEqual(versions.slots[0].chain?.items.count, 0,
                       "the materialized slot captured the implicit (empty) chain")
        XCTAssertNotNil(versions.activeVersionID)
        XCTAssertEqual(versions.activeVersionID, versions.slots[1].id)
        XCTAssertEqual(versions.slots[1].name, "Version 2")
        // 创建即激活: the editor now renders the NEW empty chain.
        XCTAssertEqual(editorState.history.position, -1)
        XCTAssertTrue(editorState.history.items.isEmpty)

        // A second create appends (Version 3) and activates.
        versions.createFromScratch()
        XCTAssertEqual(versions.slots.count, 3)
        XCTAssertEqual(versions.slots[2].name, "Version 3")
        XCTAssertNotNil(versions.slots[1].chain, "the previous active captured its chain")
    }

    // MARK: - 2: the branch snapshot timing

    func testBranchFromJumpedBackPointLeavesRedoTailInSource() async throws {
        let (editorState, _, versions, _, _) = try await makeAssembly()
        commitEdit(editorState, ev: 0.5, label: "e1")
        commitEdit(editorState, ev: 1.0, label: "e2")
        commitEdit(editorState, ev: 1.5, label: "e3")
        XCTAssertEqual(editorState.history.items.count, 3)

        // Jump back to item 1 (the redo tail = items 2..3), then branch.
        editorState.performJump(to: 1)
        versions.branchFromCurrent()

        // The branch carries items[0...1] with position at the copy tail.
        XCTAssertEqual(versions.slots.count, 2)
        let branchID = try XCTUnwrap(versions.activeVersionID)
        XCTAssertEqual(branchID, versions.slots[1].id)
        XCTAssertEqual(editorState.history.items.count, 2)
        XCTAssertEqual(editorState.history.position, 1)

        // The SOURCE version keeps the whole chain AND its jump position —
        // the redo tail (items 2..3) is still there when the user returns,
        // pointer where they branched (the KD-2 snapshot-timing letter).
        let source = try XCTUnwrap(versions.slots[0].chain)
        XCTAssertEqual(source.items.count, 3, "the redo tail stays in the source")
        XCTAssertEqual(source.position, 1, "the source keeps the jump point")
        XCTAssertEqual(source.items.map(\.label), ["e1", "e2", "e3"])
    }

    // MARK: - 3: the switch round-trip (byte fidelity)

    func testSwitchAwayAndBackRestoresTheChainByteFaithful() async throws {
        let (editorState, coordinator, versions, _, metal) = try await makeAssembly()
        let url = tempURL("ver-swap")
        defer { try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url)) }
        try await load(url, into: coordinator, metal: metal)

        // Version 1 (implicit) carries two distinct edits.
        commitEdit(editorState, ev: 0.5, label: "e1")
        commitEdit(editorState, ev: 1.25, label: "e2")
        let original = editorState.history
        XCTAssertEqual(original.position, 1)

        // Branch → edit the branch → switch back to Version 1.
        versions.branchFromCurrent()
        commitEdit(editorState, ev: -2.0, label: "branch-edit")
        XCTAssertEqual(editorState.history.items.count, 3)

        versions.switchTo(try XCTUnwrap(versions.slots[0].id))
        XCTAssertEqual(editorState.history.items.map(\.label), ["e1", "e2"])
        XCTAssertEqual(editorState.history.position, original.position)
        XCTAssertEqual(editorState.history.items, original.items,
                       "the round-trip restores the chain EXACTLY")
        // The instance projection re-derived from the restored chain: the
        // rebuild dedups to exactly ONE record per (opName, priority)
        // tuple — the committed exposure replaces the seed/default one.
        XCTAssertEqual(
            editorState.instances.filter { $0.opName == ExposureModule.opName }.count,
            1,
            "the rebuild dedups the live projection to the committed tuple")

        // And forward again: the branch's edit returns byte-faithful.
        versions.switchTo(try XCTUnwrap(versions.slots[1].id))
        XCTAssertEqual(editorState.history.items.map(\.label),
                       ["e1", "e2", "branch-edit"])
        XCTAssertEqual(editorState.history.position, 2)
    }

    // MARK: - 4/5: the remove edges

    func testRemoveActiveActivatesTheFirstSlot() async throws {
        let editorState = EditorState()
        let versions = VersionCoordinator()
        versions.attach(editorState: editorState, pipeCoordinator: PipeCoordinator())

        versions.createFromScratch() // v1 materialized + v2 active
        versions.createFromScratch() // v3 active
        XCTAssertEqual(versions.slots.count, 3)
        let v1 = versions.slots[0].id
        let v3 = try XCTUnwrap(versions.activeVersionID)

        // Give the active chain a distinguishing edit, then remove it.
        commitEdit(editorState, ev: 2.0, label: "v3-edit")
        versions.remove(v3)
        XCTAssertEqual(versions.activeVersionID, v1,
                       "removing the ACTIVE version activates the list's first")
        XCTAssertEqual(editorState.history.items.count, 0,
                       "v1's stored (empty) chain is installed")
        XCTAssertNil(versions.slots.first { $0.id == v3 })
    }

    func testRemoveLastVersionReturnsToImplicitAndKeepsTheChain() async throws {
        let (editorState, coordinator, versions, _, metal) = try await makeAssembly()
        let url = tempURL("ver-rm")
        defer { try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url)) }
        try await load(url, into: coordinator, metal: metal)

        commitEdit(editorState, ev: 0.5, label: "e1")
        versions.createFromScratch() // v1 (with e1) + v2 active
        XCTAssertEqual(versions.slots.count, 2)

        // Remove v2 (active) → v1 activates; remove v1 (last) → implicit.
        versions.remove(try XCTUnwrap(versions.slots[1].id))
        versions.remove(try XCTUnwrap(versions.slots[0].id))
        XCTAssertFalse(versions.hasVersionStructure)
        XCTAssertNil(versions.activeVersionID)
        // The CURRENT chain stays — the version structure disappears, the
        // edits do not (KD-2's remove-the-last semantics).
        XCTAssertEqual(editorState.history.items.map(\.label), ["e1"])
        XCTAssertEqual(editorState.history.position, 0)
    }

    // MARK: - 6: the dangling activeVersionID typed degrade

    func testDanglingActiveVersionIDDegradesToImplicitAndKeepsHistory() async throws {
        let editorState = EditorState()
        let versions = VersionCoordinator()
        versions.attach(editorState: editorState, pipeCoordinator: PipeCoordinator())

        commitEdit(editorState, ev: 0.7, label: "kept")
        let historyBefore = editorState.history

        // A hand-made document whose activeVersionID matches NO slot.
        versions.hydrate(
            versions: [
                SidecarVersionRecord(
                    id: UUID(), name: "Version 1",
                    createdAt: Date(), updatedAt: Date(), chain: HistoryStack()),
            ],
            activeVersionID: UUID().uuidString)

        // The structure drops WHOLE; the history is untouched.
        XCTAssertFalse(versions.hasVersionStructure)
        XCTAssertNil(versions.activeVersionID)
        XCTAssertEqual(editorState.history, historyBefore)

        // The nil-versions arm (v6 document) resets the same way.
        versions.hydrate(versions: nil, activeVersionID: nil)
        XCTAssertFalse(versions.hasVersionStructure)
    }

    // MARK: - 7: cross-image pollution (checker E4)

    func testSwitchingImagesWithoutVersionKeysResetsToImplicit() async throws {
        let (editorState, coordinator, versions, _, metal) = try await makeAssembly()
        let urlA = tempURL("ver-a")
        let urlB = tempURL("ver-b")
        defer {
            for url in [urlA, urlB] {
                try? FileManager.default.removeItem(
                    at: LightamerSidecar.sidecarURL(for: url))
            }
        }

        // A: load, branch twice → three slots (A's own edits included).
        try await load(urlA, into: coordinator, metal: metal)
        commitEdit(editorState, ev: 0.5, label: "a1")
        versions.branchFromCurrent()
        versions.createFromScratch()
        XCTAssertEqual(versions.slots.count, 3)
        // Let the version-command write Tasks land, then flush A's .lra.
        await settleNotifications()
        await coordinator.flushSidecar()

        // B: a version-less image (no .lra at all) — the load must clear
        // A's slots (the pristine branch's reset leg).
        try await load(urlB, into: coordinator, metal: metal)
        XCTAssertFalse(versions.hasVersionStructure,
                       "A's slots must not leak into B")
        XCTAssertNil(versions.activeVersionID)

        // B's first create starts counting at Version 1 — never Version 4.
        versions.createFromScratch()
        XCTAssertEqual(versions.slots.count, 2)
        XCTAssertEqual(versions.slots[0].name, "Version 1",
                       "the implicit materialize restarts the naming")
        XCTAssertEqual(versions.slots[1].name, "Version 2")
        XCTAssertEqual(versions.activeVersionID, versions.slots[1].id)

        // Switching BACK to A rehydrates A's three slots from the .lra.
        try await load(urlA, into: coordinator, metal: metal)
        try await settleNotifications()
        XCTAssertEqual(versions.slots.count, 3,
                       "A's version structure restores from its .lra")
        if let first = versions.slots.first {
            XCTAssertEqual(first.chain?.items.map(\.label), ["a1"])
        }
    }

    // MARK: - 8: the pristine narrowing (KD-6 ①)

    func testEmptyChainVersionCreationBirthsTheSidecarAtPositionMinusOne() async throws {
        let (editorState, coordinator, versions, _, metal) = try await makeAssembly()
        let url = tempURL("ver-pristine")
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        try await load(url, into: coordinator, metal: metal)

        // ZERO edits — only version commands.
        versions.createFromScratch()
        try await flushUntilPersisted(sidecarURL, coordinator)

        // The .lra exists with ZERO edits AND the version structure.
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
        let document = try Self.decoder.decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(document.history.position, -1)
        XCTAssertTrue(document.history.items.isEmpty)
        XCTAssertEqual(document.versions?.count, 2)
        XCTAssertEqual(document.activeVersionID, versions.slots[1].id.uuidString)
        XCTAssertFalse(document.driftDetected)
    }

    // MARK: - 9: the switch persists (post-swap file state)

    func testSwitchSchedulesWriteAndFileReflectsPostSwapState() async throws {
        let (editorState, coordinator, versions, _, metal) = try await makeAssembly()
        let url = tempURL("ver-persist")
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        try await load(url, into: coordinator, metal: metal)

        commitEdit(editorState, ev: 0.5, label: "e1")
        versions.branchFromCurrent()
        commitEdit(editorState, ev: 1.0, label: "b1")
        let branchID = try XCTUnwrap(versions.slots[1].id)
        try await flushUntilPersisted(sidecarURL, coordinator)

        // Switch BACK to Version 1 → the flush carries the post-swap state.
        versions.switchTo(try XCTUnwrap(versions.slots[0].id))
        await settleNotifications()
        try await coordinator.flushSidecar()
        try await Task.sleep(for: .milliseconds(150))
        await coordinator.flushSidecar()

        let document = try Self.decoder.decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(document.activeVersionID, versions.slots[0].id.uuidString)
        XCTAssertEqual(document.history.items.map(\.label), ["e1"],
                       "the file carries the ACTIVE (switched-to) chain")
        XCTAssertEqual(document.versions?.count, 2)
        let branchRecord = try XCTUnwrap(document.versions?.first {
            $0.id == branchID
        })
        XCTAssertEqual(branchRecord.chainStack?.items.map(\.label),
                       ["e1", "b1"], "the branch chain is parked in versions[]")
        XCTAssertNil(
            document.versions?.first { $0.id == versions.slots[0].id }?.chainStack,
            "the active slot carries no chain (items never double-write)")
        XCTAssertFalse(document.driftDetected)
    }

    // MARK: - 10: the DRT carrier re-syncs across a swap

    func testDrtCarrierResyncsAfterVersionSwap() async throws {
        let (editorState, coordinator, versions, workspace, metal) = try await makeAssembly()
        let url = tempURL("ver-drt")
        defer { try? FileManager.default.removeItem(
            at: LightamerSidecar.sidecarURL(for: url)) }
        try await load(url, into: coordinator, metal: metal)

        // A DRT edit lands on the implicit chain (one item, drtRecord).
        var record = DrtRecord()
        record.peakLuminance = 480
        editorState.recordDrtChange(record, label: "history_drt_param")
        await settleNotifications()
        XCTAssertEqual(workspace.drtRecord(for: url), record)

        // Undo the DRT commit on the implicit chain (the redo tail with the
        // DRT item stays in live history), then branch: the branch copies
        // items[0...-1] = EMPTY (branch-timing behavior — the DRT redo tail
        // stays in the SOURCE version's slot).
        await coordinator.undo()
        XCTAssertFalse(workspace.hasDrtRecord(for: url),
                       "the undo leg re-derived the carrier")
        versions.branchFromCurrent()
        // Give the branch a plain edit so the chains differ.
        commitEdit(editorState, ev: 0.25, label: "branch-plain")
        await settleNotifications()

        // Switch to the source version and REDO there: the DRT item
        // replays and the carrier follows the post-swap history.
        versions.switchTo(try XCTUnwrap(versions.slots[0].id))
        await coordinator.redo() // the DRT item replays
        await settleNotifications()
        XCTAssertEqual(workspace.drtRecord(for: url), record,
                       "the source version carries the DRT record again")

        // Swap to the branch: the carrier re-derives from the branch
        // history — NO DRT item → the carrier clears (drtTailActive off).
        versions.switchTo(try XCTUnwrap(versions.slots[1].id))
        await settleNotifications()
        XCTAssertFalse(workspace.hasDrtRecord(for: url),
                       "the swap re-derived the carrier from the branch chain")
        XCTAssertFalse(coordinator.drtTailActive)

        // And back: the record returns.
        versions.switchTo(try XCTUnwrap(versions.slots[0].id))
        await settleNotifications()
        XCTAssertEqual(workspace.drtRecord(for: url), record)
        XCTAssertTrue(coordinator.drtTailActive)
    }
}
