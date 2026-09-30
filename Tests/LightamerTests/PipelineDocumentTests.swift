@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PipelineDocumentTests (Plan M2-4-1 T1, AC1) — the read-only graph facade:
//
//   1. PROJECTION PARITY: grades == compositeLayers order/id/name/enabled/
//      mix item by item (the graph IS the stack's view — nothing else).
//   2. RETOUCH EXCLUSION: retouch layers never enter the graph (the
//      D-M2-4-CONTEXT-7-④ structural guarantee via the narrowing).
//   3. EMPTY STACK: the three segments still project (develop + [] + drt),
//      endpoints deletion-locked with unit mix.
//   4. PURE-FUNCTION PROOF: two inits from the same stack are Equal —
//      there is no hidden state (KD-1's "drift structurally impossible").
//
// Core-level suite (checker E2 → LightamerTestsLayers): pure Core types
// only, no App-target imports.
// ─────────────────────────────────────────────────────────────────────────────

final class PipelineDocumentTests: XCTestCase {

    private func makeStack(layers: [AdjustmentLayer] = []) -> LayerStack {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        for layer in layers { stack.addAdjustment(layer) }
        return stack
    }

    private func layer(
        name: String, enabled: Bool = true, opacity: Float = 1.0
    ) -> AdjustmentLayer {
        AdjustmentLayer(name: name, opacity: opacity, enabled: enabled)
    }

    // MARK: - 1: projection parity

    func testProjectionParityMatchesTheStack() {
        let stack = makeStack(layers: [
            layer(name: "Bottom", opacity: 0.5),
            layer(name: "Middle", enabled: false, opacity: 0.25),
            layer(name: "Top"),
        ])
        let document = PipelineDocument(stack)

        // Order: the grades segment == compositeLayers bottom-to-top, and
        // the full chain is develop → grades → drt.
        XCTAssertEqual(
            document.grades.map(\.id),
            stack.compositeLayers.map(\.id),
            "grade order == compositeLayers order (bottom-to-top = graph order)")
        XCTAssertEqual(document.nodes.count, 5)
        XCTAssertEqual(document.nodes.first?.kind, .develop)
        XCTAssertEqual(document.nodes.last?.kind, .displayTransform)

        // Field parity item by item (id/name/enabled/mix).
        for (node, layer) in zip(document.grades, stack.compositeLayers) {
            XCTAssertEqual(node.id, layer.id, "grade id == layer UUID (NDE-1)")
            XCTAssertEqual(node.layerID, layer.id)
            XCTAssertEqual(node.kind, .grade)
            XCTAssertEqual(node.name, layer.name)
            XCTAssertEqual(node.isEnabled, layer.enabled)
            XCTAssertEqual(node.mix, layer.opacity, "mix == opacity projection (OQ-6-A)")
            XCTAssertFalse(node.isDeletionLocked, "grades are deletable")
        }
        // The develop projection carries the base layer's face.
        XCTAssertEqual(document.develop.id, stack.baseLayer.id)
        XCTAssertEqual(document.develop.name, stack.baseLayer.name)
        XCTAssertEqual(document.develop.isEnabled, stack.baseLayer.enabled)
        XCTAssertNil(document.develop.layerID)
    }

    // MARK: - 2: retouch exclusion

    func testRetouchLayersAreExcludedFromTheGraph() {
        var stack = makeStack(layers: [layer(name: "Grade")])
        stack.addAdjustment(RetouchLayer(name: "Heal"))

        // The stack carries both kinds...
        XCTAssertEqual(stack.adjustmentLayers.count, 2)
        // ...but the graph narrowing shows only the adjustment kind.
        XCTAssertEqual(
            PipelineDocument(stack).grades.map(\.name), ["Grade"],
            "retouch layers never enter the node graph (OQ-7-④)")
    }

    // MARK: - 3: the empty-stack three segments + endpoint locks

    func testEmptyStackProjectsThreeSegments() {
        let document = PipelineDocument(makeStack())

        XCTAssertEqual(document.grades.count, 0)
        XCTAssertEqual(document.nodes.map(\.kind), [.develop, .displayTransform])
        // The drt endpoint is the fixed constant node (never re-minted).
        XCTAssertEqual(document.displayTransform.id, PipelineDocument.displayTransformNodeID)
        XCTAssertEqual(document.displayTransform.name, "Display Transform")
        // Endpoint locks + unit mix (D-M2-4-CONTEXT-6/7).
        for endpoint in [document.develop, document.displayTransform] {
            XCTAssertTrue(endpoint.isDeletionLocked, "endpoints are structurally locked")
            XCTAssertEqual(endpoint.mix, 1, "endpoint mix is constant 1")
            XCTAssertNil(endpoint.layerID, "endpoints route to no layer")
        }
    }

    // MARK: - 4: the pure-function proof (KD-1)

    func testSameStackProjectsEqualDocuments() {
        let stack = makeStack(layers: [layer(name: "A"), layer(name: "B", opacity: 0.3)])
        // Two reads of the same stack are Equal — no hidden state, no sync
        // point (the drift-proof face of the read-only facade).
        XCTAssertEqual(PipelineDocument(stack), PipelineDocument(stack))
        // ...and the stack itself is untouched by projection (value type).
        XCTAssertEqual(stack.compositeLayers.count, 2)
    }

    func testDifferentStacksProjectUnequalDocuments() {
        let a = PipelineDocument(makeStack(layers: [layer(name: "A")]))
        let b = PipelineDocument(makeStack(layers: [layer(name: "B")]))
        XCTAssertNotEqual(a, b, "projection equality tracks the stack content")
        let renamed = makeStack(layers: [layer(name: "A", opacity: 0.9)])
        XCTAssertNotEqual(
            a, PipelineDocument(renamed),
            "mix changes flow through the projection")
    }
}
