import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AdjustmentTransferTests (Plan M2-8-2 T3, KD-3/KD-4/KD-5; AC#4..7 — APP
// bundle, the VersionSwapTests real-chain precedent) — the Copy Adjustments
// transfer end-to-end:
//
//   1. THE EXCLUSION ENUMERATION (KD-3, checker M1's final table): the
//      develop 15 (the catalog table VERBATIM), the drtPost 4, and the
//      terminal trio (colorin/colorout/gamma — the explicit exclusion set,
//      they answer .grade through the default arm) are ALL non-transferable;
//      the .grade side samples TRUE.
//   2. THE SOURCE ENUMERATION through the REAL KD-5 projection: the
//      current-image chain and EXTERNAL .lra fixtures (v7 multi-version +
//      v6 single-chain) enumerate nodes/items — and a corrupt file lands
//      the typed error.
//   3. THE PASTE LANDING (KD-4): the epoch item shape (pasteSet /
//      stackSnapshot / pasteEpochScope), the DRT second item, the mask
//      contentRevision NIL reset, activation + the .lra write, and the
//      implicit-target materialize edge.
//   4. THE SINGLE-SOURCE PROJECTION (KD-5): `LayerStackProjection.rebuild`
//      and `EditorState.rebuildLayerStack` agree byte-for-byte on the same
//      chain (the delegation is zero-diff by construction).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class AdjustmentTransferTests: XCTestCase {

    // MARK: - Record fixtures (the internal raw-field init — @testable)

    private func record(
        _ opName: String, multiPriority: Int = 0
    ) -> ModuleInstance {
        ModuleInstance(
            id: UUID(), opName: opName, multiPriority: multiPriority,
            multiName: "", iopOrder: 50, version: 1, enabled: true,
            paramsData: Data("{}".utf8), paramsHash: 0)
    }

    private func typedRecord<M: IOPModule>(
        _ module: M.Type, params: M.Params
    ) -> ModuleInstance {
        ModuleInstance(module: module, params: params)
    }

    // MARK: - 1: the exclusion enumeration (KD-3 终表)

    func testExclusionFaceEnumeratesComplete() {
        // The develop 15 — the catalog table VERBATIM (a module rename
        // fails compilation there; this loop cannot drift from it).
        for opName in NodeOwnershipCatalog.developOpNames {
            XCTAssertFalse(
                isAdjustmentTransferable(record(opName)),
                "\(opName) must NOT be transferable (develop)")
        }
        XCTAssertEqual(NodeOwnershipCatalog.developOpNames.count, 15)

        // The drtPost 4 — rides the DRT checkbox, never the chain copy.
        for opName in NodeOwnershipCatalog.drtPostOpNames {
            XCTAssertFalse(
                isAdjustmentTransferable(record(opName)),
                "\(opName) must NOT be transferable (drtPost)")
        }
        XCTAssertEqual(NodeOwnershipCatalog.drtPostOpNames.count, 4)

        // The terminal trio — the EXPLICIT exclusion set (they answer
        // .grade through the catalog default arm; the predicate pins them
        // off by name constants, never literals).
        XCTAssertEqual(
            AdjustmentTransferTerminalTrio.opNames,
            [ColorInModule.opName, ColorOutModule.opName, GammaModule.opName])
        for opName in AdjustmentTransferTerminalTrio.opNames {
            XCTAssertEqual(
                NodeOwnershipCatalog.owner(of: opName), .grade,
                "the final-table premise: \(opName) answers .grade by default")
            XCTAssertFalse(
                isAdjustmentTransferable(record(opName)),
                "\(opName) must NOT be transferable (terminal trio)")
        }

        // The .grade side samples TRUE (typed construction — catalog rows).
        XCTAssertTrue(isAdjustmentTransferable(
            typedRecord(ExposureModule.self, params: ExposureModule.Params())))
        XCTAssertTrue(isAdjustmentTransferable(
            typedRecord(SaturationModule.self, params: SaturationModule.Params())))
        XCTAssertTrue(isAdjustmentTransferable(
            typedRecord(HlsModule.self, params: HlsModule.Params())))
        XCTAssertTrue(isAdjustmentTransferable(
            typedRecord(ColorWheelsModule.self, params: ColorWheelsModule.Params())))
        XCTAssertTrue(isAdjustmentTransferable(
            typedRecord(ToneCurveModule.self, params: ToneCurveModule.Params())))
    }

    // MARK: - Source chain fixtures (the real .lra files)

    /// A source chain: one structure item (a grade layer carrying an
    /// exposure + a develop-owned instance + a terminal-trio instance in
    /// its chain) + one layer param item + one DRT item.
    private func sourceChain() throws -> (HistoryStack, UUID) {
        let layerID = UUID()
        var layer = AdjustmentLayer(id: layerID, name: "Warm")
        layer.chain = [
            typedRecord(ExposureModule.self, params: ExposureModule.Params(exposure: 0.5)),
            record(TemperatureModule.opName),
            record(GammaModule.opName),
        ]
        layer.mask = MaskSpec(
            drawn: DrawnMaskSpec(forms: [], group: nil), contentRevision: 7)

        let snapshot = LayerStackSnapshot(layers: [.init(layer)])
        var stack = HistoryStack()
        let seed = typedRecord(ExposureModule.self, params: ExposureModule.Params())
        stack.commit(
            seed, label: "structure", layerScope: EditorStructureScope.marker,
            stackSnapshot: snapshot)
        var params = ExposureModule.Params()
        params.exposure = 0.75
        stack.commit(
            ModuleInstance(module: ExposureModule.self, params: params),
            label: "warm", layerScope: layerID.uuidString)
        stack.commitDrt(
            record: DrtRecord(), placeholder: seed, label: "drt")
        return (stack, layerID)
    }

    private func writeFixture(
        _ chain: HistoryStack, versions: [SidecarVersionRecord]?,
        activeVersionID: String?, to url: URL
    ) throws {
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 0,
            instances: [], history: chain, historyHash: 0,
            versions: versions, activeVersionID: activeVersionID)
        let data = try JSONEncoder().encode(document)
        try data.write(to: url)
    }

    /// The flat decode fixture (the HistoryRowJumpTests shape).
    private nonisolated static func decodedFlat(size: Int = 96) -> DecodedImage {
        let image = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: image,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8,
            contentDedupeID: 0)
    }

    // MARK: - 2: the source enumeration (current + external v7/v6)

    func testCurrentImageSourceEnumeratesThroughTheProjection() throws {
        let editorState = EditorState()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())

        let model = AdjustmentTransferModel()
        model.loadCurrentImage(editorState: editorState)

        // One Grade node; the implicit source version row.
        XCTAssertEqual(model.sourceVersions.count, 1)
        XCTAssertEqual(model.nodes.count, 1)
        XCTAssertEqual(model.nodes.first?.id, layer.id)
        // The DRT row is absent (no DRT item in the chain).
        XCTAssertNil(model.drtRecord)

        // The Item pane: the layer chain is empty (the structure item only
        // carried the snapshot) — nothing checkable, payload nil.
        XCTAssertEqual(model.selectedNodeItems.count, 0)
        XCTAssertNil(model.pastePayload())
    }

    func testExternalV7MultiVersionSourceListsAndSwitches() throws {
        let (chain, layerID) = try sourceChain()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transfer-v7-\(UUID().uuidString).lra")
        defer { try? FileManager.default.removeItem(at: url) }

        let second = HistoryStack.copyingPrefixOf(chain, upTo: 1)
        let activeID = UUID()
        let secondID = UUID()
        try writeFixture(
            chain,
            versions: [
                SidecarVersionRecord(
                    id: activeID, name: "v-one", createdAt: Date(),
                    updatedAt: Date(),
                    chain: nil), // the ACTIVE slot (chain = the history key)
                SidecarVersionRecord(
                    id: secondID, name: "v-two", createdAt: Date(),
                    updatedAt: Date(),
                    chain: second),
            ],
            activeVersionID: activeID.uuidString, to: url)

        let model = AdjustmentTransferModel()
        model.loadExternalFile(at: url)

        // Two version rows; the FIRST is picked (the active chain).
        XCTAssertEqual(model.sourceVersions.map(\.name), ["v-one", "v-two"])
        XCTAssertEqual(
            model.selectedVersionID, model.sourceVersions.first?.id)
        // The active chain carries the DRT item → the DRT row appears.
        XCTAssertNotNil(model.drtRecord)
        XCTAssertTrue(model.drtChecked)

        // The Node pane: one Grade, its chain = the snapshot's 3 records;
        // exactly ONE of them is transferable (exposure; temperature =
        // develop, gamma = terminal trio).
        XCTAssertEqual(model.nodes.count, 1)
        let node = try XCTUnwrap(model.nodes.first)
        XCTAssertEqual(node.chainCount, 3)
        XCTAssertEqual(node.transferableCount, 1)

        // The Item pane shape: checked = the transferable one; the other
        // two greyed (checked == false).
        let items = model.selectedNodeItems
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.filter(\.checked).map(\.instance.opName),
                       [ExposureModule.opName])
        XCTAssertEqual(
            items.filter { !$0.transferable }.map(\.instance.opName).sorted(),
            [GammaModule.opName, TemperatureModule.opName].sorted())

        // The layer id rides the snapshot (the enumeration IS the
        // projection).
        XCTAssertEqual(model.layerSnapshots.first?.id, layerID)

        // Switch to v-two (the prefix copy — no DRT item below position 1).
        model.selectVersion(id: model.sourceVersions[1].id)
        XCTAssertNil(model.drtRecord, "the prefix copy carries no DRT item")
        XCTAssertFalse(model.drtChecked)
        XCTAssertEqual(model.nodes.count, 1)
    }

    func testExternalV6SingleChainSourceLoads() throws {
        let (chain, _) = try sourceChain()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transfer-v6-\(UUID().uuidString).lra")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeFixture(chain, versions: nil, activeVersionID: nil, to: url)

        let model = AdjustmentTransferModel()
        model.loadExternalFile(at: url)

        // ONE row (the active chain sentinel); the enumeration is identical
        // to the v7 active pick.
        XCTAssertEqual(model.sourceVersions.count, 1)
        XCTAssertEqual(
            model.sourceVersions.first?.id, TransferSourceVersion.activeChainID)
        XCTAssertEqual(model.nodes.count, 1)
        XCTAssertNotNil(model.drtRecord)
    }

    func testCorruptExternalFileLandsTheTypedError() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transfer-bad-\(UUID().uuidString).lra")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a sidecar".utf8).write(to: url)

        let model = AdjustmentTransferModel()
        model.loadExternalFile(at: url)

        // The typed failure (the .unreadable case renders the decode
        // detail) empties the panes — no crash, no silent swallow.
        guard case .unreadable = model.loadError else {
            return XCTFail("expected .unreadable, got \(String(describing: model.loadError))")
        }
        XCTAssertFalse(model.loadError?.localizedCopy.isEmpty ?? true)
        XCTAssertTrue(model.nodes.isEmpty)
        XCTAssertTrue(model.sourceVersions.isEmpty)
    }

    // MARK: - 3: the paste landing (KD-4)

    private func makeAssembly() async throws -> (
        editorState: EditorState, coordinator: PipeCoordinator,
        versionCoordinator: VersionCoordinator, metal: MetalContext
    ) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        let versionCoordinator = VersionCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
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
        return (editorState, coordinator, versionCoordinator, metal)
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
            try await Task.sleep(for: .milliseconds(100))
            await coordinator.flushSidecar()
        }
        XCTFail("the sidecar file never appeared: \(sidecarURL.lastPathComponent)")
    }

    func testPasteChainLandsEpochVersionWithDrtSecondItem() async throws {
        let (editorState, coordinator, versions, metal) = try await makeAssembly()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transfer-paste-\(UUID().uuidString).tif")
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        defer { try? FileManager.default.removeItem(at: sidecarURL) }
        try await coordinator.load(
            url: url, decoded: Self.decodedFlat(), instances: [], metal: metal)

        // The TARGET carries its own edit (the implicit single version).
        var params = ExposureModule.Params()
        params.exposure = 1.0
        editorState.recordChange(
            ModuleInstance(module: ExposureModule.self, params: params), label: "t1")

        // THE REAL DIALOG PATH: the source chain restores into an
        // EditorState; the model enumerates it (loadCurrentImage — the
        // same-image degenerate entry) and materializes the checked
        // payload (the mask reset happens HERE, in the model).
        let (chain, _) = try sourceChain()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.restoreFromSidecar(history: chain, persistedInstances: [seed])
        let model = AdjustmentTransferModel()
        model.loadCurrentImage(editorState: editorState)
        XCTAssertEqual(model.nodes.first?.name, "Warm")
        let payload = try XCTUnwrap(model.pastePayload())
        XCTAssertEqual(payload.records.map(\.opName), [ExposureModule.opName])
        XCTAssertEqual(payload.snapshot?.layers.count, 1)

        // IMPLICIT-TARGET MATERIALIZATION (KD-4): the paste materializes
        // 「版本 1」 then lands the pasted version.
        versions.pasteChain(
            records: payload.records,
            layerSnapshot: payload.snapshot,
            drtRecord: payload.drtRecord,
            name: "Pasted adjustments")

        XCTAssertEqual(versions.slots.count, 2)
        XCTAssertEqual(
            versions.slots[0].name,
            String(localized: "versions_default_name", defaultValue: "Version 1"))
        XCTAssertEqual(versions.activeVersionID, versions.slots[1].id)
        XCTAssertEqual(versions.slots[1].name, "Pasted adjustments")

        // THE CHAIN SHAPE: item ① = the OVERWRITE-paste epoch (pasteSet =
        // the checked set, stackSnapshot = the layer payload, scope =
        // pasteEpochScope, snapshot slot = the first record placeholder);
        // item ② = the DRT item (drtDocumentScope + the drtRecord payload).
        let pasted = editorState.history
        XCTAssertEqual(pasted.items.count, 2)
        let epoch = pasted.items[0]
        XCTAssertTrue(epoch.isOverwritePaste)
        XCTAssertEqual(epoch.layerScope, HistoryStack.pasteEpochScope)
        XCTAssertEqual(epoch.pasteSet?.map(\.opName), payload.records.map(\.opName))
        XCTAssertEqual(epoch.snapshot.id, payload.records[0].id)
        XCTAssertEqual(epoch.stackSnapshot?.layers.first?.name, "Warm")
        let drtItem = pasted.items[1]
        XCTAssertEqual(drtItem.layerScope, HistoryStack.drtDocumentScope)
        XCTAssertNotNil(drtItem.drtRecord)
        XCTAssertNil(drtItem.pasteSet)

        // THE MASK RESET (KD-3): the pasted layer's mask contentRevision
        // is NIL (the source carried 7 — the new epoch restarts the guard).
        let pastedLayer = try XCTUnwrap(
            editorState.layerStack?.compositeLayers.first)
        XCTAssertEqual(pastedLayer.name, "Warm")
        XCTAssertNil(pastedLayer.mask?.contentRevision)

        // THE PROJECTION (zero new semantics): the live layer chain holds
        // the checked record; the DRT projection is effective.
        XCTAssertEqual(
            pastedLayer.chain.filter { $0.opName == ExposureModule.opName }.count, 1)
        XCTAssertNotNil(pasted.effectiveDrtRecord())

        // THE WRITE: the version command tail scheduled the write.
        try await flushUntilPersisted(sidecarURL, coordinator)
        let document = try JSONDecoder().decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(document.versions?.count, 2)
        XCTAssertEqual(document.activeVersionID, versions.slots[1].id.uuidString)
        XCTAssertEqual(document.history.items.count, 2)
    }

    func testPasteChainRefusesEmptyAndHandlesDrtOnly() async throws {
        let (editorState, _, versions, _) = try await makeAssembly()

        // Empty payload → refused (no slots, nothing lands).
        versions.pasteChain(
            records: [], layerSnapshot: nil, drtRecord: nil, name: "x")
        XCTAssertTrue(versions.slots.isEmpty)

        // DRT-only → ONE item (the drtDocumentScope item).
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        versions.pasteChain(
            records: [], layerSnapshot: nil, drtRecord: DrtRecord(), name: "drt-only")
        XCTAssertEqual(versions.slots.count, 2)
        XCTAssertEqual(editorState.history.items.count, 1)
        XCTAssertEqual(
            editorState.history.items[0].layerScope, HistoryStack.drtDocumentScope)
        XCTAssertNotNil(editorState.history.effectiveDrtRecord())
    }

    // MARK: - 4: the single-source projection (KD-5)

    func testLayerStackProjectionMatchesEditorStateRebuild() throws {
        let (chain, layerID) = try sourceChain()

        // The Core function (the extraction's face).
        let projected = LayerStackProjection.rebuild(
            history: chain, baseLayer: BackgroundLayer())

        // The App path: restore the same chain into a real EditorState —
        // its rebuild delegates to the SAME function.
        let editorState = EditorState()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        editorState.restoreFromSidecar(history: chain, persistedInstances: [seed])
        // restoreFromSidecar rebuilds the INSTANCE set only — the layer
        // stack rebuild rides the navigation faces (performJump).
        editorState.performJump(to: chain.position)

        let projectedLayers = projected.compositeLayers
        let restoredLayers = try XCTUnwrap(editorState.layerStack).compositeLayers
        XCTAssertEqual(projectedLayers.count, restoredLayers.count)
        XCTAssertEqual(projectedLayers.first?.id, layerID)
        XCTAssertEqual(projectedLayers.map(\.id), restoredLayers.map(\.id))
        XCTAssertEqual(projectedLayers.first?.chain, restoredLayers.first?.chain)
        XCTAssertEqual(
            projectedLayers.first?.mask?.contentRevision,
            restoredLayers.first?.mask?.contentRevision)

        // The pristine chain → no layers.
        let pristine = LayerStackProjection.rebuild(
            history: HistoryStack(), baseLayer: BackgroundLayer())
        XCTAssertTrue(pristine.adjustmentLayers.isEmpty)
    }
}
