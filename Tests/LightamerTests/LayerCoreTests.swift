@testable import LightamerCore
import LightamerIOP
import XCTest

/// Plan 06-01 T2 — the adjustment-layer core: concrete type, LayerStack
/// mutation API semantics (add/remove/reorder/duplicate/mergeDown), the
/// layer-chain effective projection, and the `layerScope` history wiring.
/// Identity assertions are NDE-1 anchors (UUID, never index).
final class LayerCoreTests: XCTestCase {

    // ── Fixtures ──

    private func gainRecord(gain: Float, order: Float = 50.5, priority: Int = 0) -> ModuleInstance {
        ModuleInstance(module: TestGainModule.self, multiPriority: priority, params: TestGainModule.Params(gain: gain))
    }

    private func passRecord(order: Float = 50.5, priority: Int = 9) -> ModuleInstance {
        ModuleInstance(module: PassthroughModule.self, multiPriority: priority, params: PassthroughModule.Params())
    }

    private func layer(
        name: String,
        chain: [ModuleInstance] = [],
        opacity: Float = 1.0
    ) -> AdjustmentLayer {
        let layer = AdjustmentLayer(name: name, opacity: opacity, chain: chain)
        return layer
    }

    // ── 1. AdjustmentLayer surface ──

    func testAdjustmentLayerDefaultsAndKind() {
        let layer = AdjustmentLayer(name: "Dodge")
        XCTAssertFalse(layer.id.uuidString.isEmpty, "NDE-1: UUID identity")
        XCTAssertEqual(layer.name, "Dodge")
        XCTAssertTrue(layer.isVisible)
        XCTAssertEqual(layer.opacity, 1.0)
        XCTAssertEqual(layer.blendMode, .normal)
        XCTAssertEqual(layer.blendOptions, [])
        XCTAssertTrue(layer.enabled)
        XCTAssertEqual(layer.kind, .adjustment)
        XCTAssertTrue(layer.chain.isEmpty)
        XCTAssertNil(layer.mask, "mask shell absent by default (6-3/6-4 payload)")
    }

    /// NDE-1 duplicate semantics: the copy carries a NEW layer UUID and NEW
    /// chain-record UUIDs, with params bytes + hashes byte-identical.
    func testDuplicateMintsFreshIdentitiesWithVerbatimParams() throws {
        let g1 = gainRecord(gain: 1.4, priority: 0)
        let g2 = gainRecord(gain: 0.7, priority: 1)
        let original = layer(name: "Original", chain: [g1, g2], opacity: 0.6)
        original.blendMode = .multiply
        original.mask = MaskSpec()

        let copy = original.duplicated()
        XCTAssertNotEqual(copy.id, original.id, "duplicate = new layer identity")
        XCTAssertEqual(copy.name, "Original")
        XCTAssertEqual(copy.chain.count, 2)
        for (a, b) in zip(original.chain, copy.chain) {
            XCTAssertNotEqual(b.id, a.id, "chain records clone with fresh UUIDs")
            XCTAssertEqual(b.opName, a.opName)
            XCTAssertEqual(b.paramsData, a.paramsData, "params bytes verbatim")
            XCTAssertEqual(b.paramsHash, a.paramsHash, "D-H4 atom byte-stable across duplicate")
            XCTAssertEqual(b.multiPriority, a.multiPriority)
        }
        XCTAssertEqual(copy.opacity, 0.6)
        XCTAssertEqual(copy.blendMode, .multiply)
        XCTAssertEqual(copy.mask, MaskSpec())
    }

    // ── 2. LayerStack mutation API ──

    func testAddRemoveReorderPreserveIdentity() {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let l1 = layer(name: "One")
        let l2 = layer(name: "Two")
        let l3 = layer(name: "Three")
        stack.addAdjustment(l1)
        stack.addAdjustment(l2)
        stack.addAdjustment(l3)
        XCTAssertEqual(stack.adjustmentLayers.map(\.id), [l1.id, l2.id, l3.id], "append = on top")

        // reorder: Three to the bottom — all three UUIDs survive untouched.
        stack.reorder(id: l3.id, to: 0)
        XCTAssertEqual(stack.adjustmentLayers.map(\.id), [l3.id, l1.id, l2.id])
        XCTAssertTrue(stack.adjustmentLayers[0].id == l3.id && l3.id == l3.id)

        // remove: Two leaves, the others keep their identity + order.
        let removed = stack.remove(id: l2.id)
        XCTAssertEqual(removed?.id, l2.id)
        XCTAssertEqual(stack.adjustmentLayers.map(\.id), [l3.id, l1.id])
        XCTAssertNil(stack.remove(id: UUID()), "unknown id = no-op")
    }

    func testDuplicateInsertsDirectlyAbove() {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let l1 = layer(name: "One", chain: [gainRecord(gain: 1.2)])
        let l2 = layer(name: "Two")
        stack.addAdjustment(l1)
        stack.addAdjustment(l2)

        let copy = stack.duplicate(id: l1.id)
        let copyID = copy?.id
        XCTAssertNotNil(copy)
        XCTAssertNotEqual(copyID, l1.id)
        XCTAssertEqual(
            stack.adjustmentLayers.map(\.id),
            [l1.id, copyID!, l2.id],
            "the copy lands directly above the original")
        XCTAssertNil(stack.duplicate(id: UUID()), "unknown id = no copy")
    }

    func testMergeDownIntoAdjustmentLayerSortsV50() throws {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        // lower: a passthrough at 50.5/priority 9; upper: two gains at
        // 50.5/priorities 0,1 + a colorin record at 28.0 (must sort first).
        let lower = layer(name: "Lower", chain: [passRecord(priority: 9)])
        let upper = layer(name: "Upper", chain: [
            gainRecord(gain: 2.0, priority: 1),
            ModuleInstance(module: ColorInModule.self, params: ColorInModule.Params()),
            gainRecord(gain: 1.5, priority: 0),
        ])
        stack.addAdjustment(lower)
        stack.addAdjustment(upper)

        let outcome = stack.mergeDown(id: upper.id)
        XCTAssertEqual(outcome, .mergedIntoLayer(lowerID: lower.id))
        XCTAssertEqual(stack.adjustmentLayers.map(\.id), [lower.id],
                       "the merged layer is removed; the lower layer carries the combined chain")
        let merged = lower.chain
        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(merged.first?.opName, "colorin", "v50 order: 28.0 sorts below 50.5")
        // Within the shared 50.5 slot: (multiPriority, opName) ascend — the
        // two gains (priority 0/1) precede the passthrough (priority 9).
        XCTAssertEqual(merged.map(\.opName),
                       ["colorin", "testgain", "testgain", "passthrough_spike"])
        XCTAssertEqual(merged.map(\.multiPriority), [0, 0, 1, 9])
        // Passthrough record survives at the tail of the 50.5 cluster.
        XCTAssertEqual(merged.last?.opName, "passthrough_spike")
    }

    func testMergeDownBottomLayerReturnsBaseChain() throws {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        let bottom = layer(name: "Bottom", chain: [gainRecord(gain: 1.3)])
        let top = layer(name: "Top", chain: [passRecord()])
        stack.addAdjustment(bottom)
        stack.addAdjustment(top)

        let outcome = stack.mergeDown(id: bottom.id)
        XCTAssertEqual(outcome, .mergedIntoBase(chain: bottom.chain.sorted {
            ($0.iopOrder, $0.multiPriority, $0.opName) < ($1.iopOrder, $1.multiPriority, $1.opName)
        }), "merging into the base hands the combined chain to the caller")
        XCTAssertEqual(stack.adjustmentLayers.map(\.id), [top.id], "only the top layer remains")
    }

    // ── 3. Chain effective projection ──

    /// The dedup tuple `(opName, multiPriority)` — the LATER array entry
    /// wins — with the v50 sort. Identical semantics to the global history
    /// projection (array order = chronological).
    func testEffectiveChainDedupAndSort() {
        let colorin = ModuleInstance(module: ColorInModule.self, params: ColorInModule.Params())
        let gainEarlier = gainRecord(gain: 1.0, priority: 0)
        let gainLater = gainRecord(gain: 2.0, priority: 0) // same tuple, later → wins
        let pass = passRecord(priority: 9)

        let chain = HistoryStack.effectiveChain([gainEarlier, pass, colorin, gainLater])
        XCTAssertEqual(chain.map(\.opName), ["colorin", "testgain", "passthrough_spike"], "v50 ascending")
        XCTAssertEqual(chain.first { $0.opName == "testgain" }?.paramsHash, gainLater.paramsHash, "the LATER record of a tuple wins")
        XCTAssertEqual(chain.count, 3, "dedup collapsed the second testgain")
    }

    /// `ModuleRegistry.effectiveInstances(layer:)` — the layer path into
    /// the shared rule.
    func testRegistryEffectiveInstancesForLayer() async {
        let registry = ModuleRegistry.makeDefault()
        let gainEarlier = gainRecord(gain: 1.0, priority: 1)
        let gainLater = gainRecord(gain: 3.0, priority: 1)
        let layer = layer(name: "L", chain: [gainEarlier, passRecord(priority: 0), gainLater])
        let effective = await registry.effectiveInstances(layer: layer)
        XCTAssertEqual(effective.map(\.opName), ["passthrough_spike", "testgain"])
        XCTAssertEqual(effective.last?.paramsHash, gainLater.paramsHash, "later-wins on the shared tuple")
    }

    /// The sub-run materialization seam: records → applied boxes, identity
    /// preserved; unknown ops are skipped and reported (02-06 degrade shape).
    func testMaterializeBoxesAppliesRecordsAndSkipsUnknown() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let gain = gainRecord(gain: 1.7, priority: 0)
        let unknown = ModuleInstance(
            id: UUID(), opName: "op_from_the_future", multiPriority: 0,
            multiName: "", iopOrder: 50.6, version: 1, enabled: true,
            paramsData: Data("{}".utf8), paramsHash: 42)

        let (boxes, unknownOps) = await registry.materializeBoxes(for: [gain, unknown])
        XCTAssertEqual(boxes.count, 1)
        XCTAssertEqual(boxes[0].instanceID, gain.id, "identity-restoring materialization")
        XCTAssertEqual(boxes[0].paramsHash, gain.paramsHash, "record params committed into the box")
        XCTAssertEqual(unknownOps, ["op_from_the_future"], "unknown op reported for the toast path")
    }

    // ── 4. layerScope history wiring ──

    /// Layer-scoped commits live beside global ones; the GLOBAL projection
    /// filters them out and the layer-scope projection keeps exactly its own.
    func testLayerScopePartitionsEffectiveInstances() {
        var stack = HistoryStack()
        let globalGain = gainRecord(gain: 1.0, priority: 0)
        stack.commit(globalGain, label: "global gain")

        let layerA = UUID().uuidString
        let layerGain = gainRecord(gain: 2.0, priority: 0) // same tuple, different scope
        stack.commit(layerGain, label: "layer A gain", layerScope: layerA)

        let global = stack.effectiveInstances()
        XCTAssertEqual(global.map(\.paramsHash), [globalGain.paramsHash],
                       "layer-scoped entries must NOT leak into the global projection")

        let scoped = stack.effectiveInstances(layerScope: layerA)
        XCTAssertEqual(scoped.map(\.paramsHash), [layerGain.paramsHash],
                       "the layer scope sees exactly its own latest edit")

        XCTAssertTrue(stack.effectiveInstances(layerScope: UUID().uuidString).isEmpty)
    }

    /// The 02-05 frozen HistoryItem spelling survives the scope payload
    /// through a Codable round-trip (sidecar shape unaffected — v1 documents
    /// decode with nil scopes).
    func testLayerScopeSurvivesCodableRoundTrip() throws {
        var stack = HistoryStack()
        let layerID = UUID().uuidString
        stack.commit(gainRecord(gain: 1.1), label: "edit", layerScope: layerID)

        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(HistoryStack.self, from: data)
        XCTAssertEqual(decoded, stack)
        XCTAssertEqual(decoded.items[0].layerScope, layerID)
        XCTAssertEqual(decoded.effectiveInstances(layerScope: layerID).count, 1)
    }
}
