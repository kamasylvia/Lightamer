import CoreGraphics
import LightamerCore
import LightamerIOP
import SwiftUI
import XCTest
import AppKit

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// NodeCanvasGeometryTests (Plan M2-4-3 T1/T2, AC1) — the pure-function
// geometry source of the node panel:
//
//   • layout: monotonic y, horizontal centering, 0/1/N node faces, the
//     endpoint/grade height split, insets
//   • edges: exactly N-1 segments connecting ADJACENT card centers
//   • insertionIndex: the threshold matrix (between cards / on a card /
//     out-of-range clamps; the 0/1-grade degenerate faces)
//   • insertionLineY: indicator positions mirror the index space
//   • fitScale: fits → 1, tall → the exact ratio, zero container → 1
//   • the 30-node layout BENCH (an OBSERVATION line, not a gate — plan T2)
//
// App-target file (the geometry serves the App panel) but zero view
// dependencies — every test is a pure value check.
// ─────────────────────────────────────────────────────────────────────────────

final class NodeCanvasGeometryTests: XCTestCase {

    // MARK: - Fixtures

    /// A document with `gradeCount` grades: develop → grades → drt.
    private func document(gradeCount: Int) -> PipelineDocument {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        for index in 0..<gradeCount {
            stack.addAdjustment(AdjustmentLayer(name: "G\(index)"))
        }
        return PipelineDocument(stack)
    }

    // MARK: - Layout (monotonic + centered + faces)

    func testLayoutIsMonotonicAndCentered() {
        let width: CGFloat = 248
        let layout = NodeCanvasGeometry.layout(
            for: document(gradeCount: 3).nodes, width: width)

        // Monotonic y: each frame strictly below the previous one.
        let ys = layout.order.compactMap { layout.frames[$0]?.minY }
        XCTAssertEqual(ys.count, 5)
        for (a, b) in zip(ys, ys.dropFirst()) {
            XCTAssertLessThan(a, b, "frames must stack top-to-bottom")
        }

        // Horizontally centered: every frame's midpoint is the canvas
        // midpoint; every frame has the shared card width.
        for id in layout.order {
            let frame = layout.frames[id]
            XCTAssertNotNil(frame)
            XCTAssertEqual(frame?.midX ?? -1, width / 2, accuracy: 0.001)
            XCTAssertEqual(frame?.width ?? -1, NodeCanvasGeometry.cardWidth)
        }

        // Height split: endpoints are shorter than grade cards.
        XCTAssertEqual(
            layout.frames[layout.order.first!]?.height,
            NodeCanvasGeometry.endpointHeight)
        XCTAssertEqual(
            layout.frames[layout.order.last!]?.height,
            NodeCanvasGeometry.endpointHeight)
        for gradeID in layout.order.dropFirst().dropLast() {
            XCTAssertEqual(
                layout.frames[gradeID]?.height, NodeCanvasGeometry.cardHeight)
        }

        // Spacing: the gap between consecutive frames is verticalSpacing.
        let frames = layout.order.compactMap { layout.frames[$0] }
        for (a, b) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(
                b.minY - a.maxY, NodeCanvasGeometry.verticalSpacing, accuracy: 0.001)
        }

        // Insets: the column starts at topInset and ends at height minus
        // the bottom inset.
        XCTAssertEqual(frames.first?.minY, NodeCanvasGeometry.topInset)
        XCTAssertEqual(
            layout.height, frames.last!.maxY + NodeCanvasGeometry.bottomInset)
    }

    func testLayoutZeroOneAndManyNodes() {
        let empty = NodeCanvasGeometry.layout(for: [], width: 248)
        XCTAssertTrue(empty.frames.isEmpty)
        XCTAssertTrue(empty.order.isEmpty)
        XCTAssertEqual(empty.height, 0)
        XCTAssertTrue(empty.edges().isEmpty)

        let single = NodeCanvasGeometry.layout(
            for: document(gradeCount: 0).nodes, width: 248)
        XCTAssertEqual(single.order.count, 2, "develop + drt")
        XCTAssertTrue(single.grades.isEmpty, "no grade segment")

        let many = NodeCanvasGeometry.layout(
            for: document(gradeCount: 8).nodes, width: 248)
        XCTAssertEqual(many.order.count, 10)
        XCTAssertEqual(many.grades.count, 8)
    }

    // MARK: - Edges (adjacent centers)

    func testEdgesConnectAdjacentCentersExactlyOnce() {
        let doc = document(gradeCount: 3)
        let layout = NodeCanvasGeometry.layout(for: doc.nodes, width: 248)
        let edges = layout.edges()

        // A linear chain of 5 nodes has EXACTLY 4 segments.
        XCTAssertEqual(edges.count, 4)

        // Each segment connects the ADJACENT pair's centers; its id is the
        // LOWER node's id.
        for (upper, lower) in zip(doc.nodes, doc.nodes.dropFirst()) {
            let edge = edges.first { $0.nodeID == lower.id }
            XCTAssertNotNil(edge, "the pair (upper, lower) has one segment")
            XCTAssertEqual(edge?.start, layout.center(of: upper.id))
            XCTAssertEqual(edge?.end, layout.center(of: lower.id))
        }
    }

    // MARK: - insertionIndex (the threshold matrix)

    func testInsertionIndexThresholdMatrix() {
        let doc = document(gradeCount: 2)
        let layout = NodeCanvasGeometry.layout(for: doc.nodes, width: 248)
        let g0 = layout.center(of: layout.grades[0]).y
        let g1 = layout.center(of: layout.grades[1]).y
        let drt = layout.center(of: PipelineDocument.displayTransformNodeID).y
        let bottomBoundary = (g1 + drt) / 2

        // On/around the boundaries: above (incl. the boundary itself) keeps
        // the upper zone; a drag ON a card resolves to that card's OWN
        // index (its slot = the no-op position); the zone below the last
        // boundary (toward the DRT endpoint) = grades.count.
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: g0 - 40, in: layout), 0,
            "well above the grades clamps to 0")
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: g0, in: layout), 0,
            "on the first card → its own slot")
        let midpoint = (g0 + g1) / 2
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: midpoint, in: layout), 0,
            "the boundary itself belongs to the upper zone")
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: midpoint + 0.5, in: layout), 1)
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: g1, in: layout), 1,
            "on the second card → its own slot")
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: bottomBoundary, in: layout), 1)
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: bottomBoundary + 0.5, in: layout),
            2, "below the last boundary → grades.count")
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: g1 + 80, in: layout), 2,
            "below the DRT boundary clamps to grades.count")

        // Three grades: three boundaries (two internal + the DRT one), four zones.
        let three = NodeCanvasGeometry.layout(for: document(gradeCount: 3).nodes, width: 248)
        let c = three.grades.map { three.frames[$0]!.midY }
        XCTAssertEqual(NodeCanvasGeometry.insertionIndex(dragY: c[0] - 10, in: three), 0)
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: (c[0] + c[1]) / 2 + 1, in: three), 1)
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: (c[1] + c[2]) / 2 + 1, in: three), 2)
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: c[2] + 5, in: three), 2,
            "on the last card → its own slot")
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: c[2] + 100, in: three), 3,
            "well below the last grade → the top slot")
    }

    func testInsertionIndexDegenerateFaces() {
        // No grades: nowhere to insert (always 0).
        let none = NodeCanvasGeometry.layout(
            for: document(gradeCount: 0).nodes, width: 248)
        XCTAssertEqual(NodeCanvasGeometry.insertionIndex(dragY: 0, in: none), 0)
        XCTAssertEqual(NodeCanvasGeometry.insertionIndex(dragY: 999, in: none), 0)

        // One grade: on-card = its own slot (0); below the card's bottom
        // edge (toward the DRT midpoint) = 1.
        let one = NodeCanvasGeometry.layout(
            for: document(gradeCount: 1).nodes, width: 248)
        let frame = one.frames[one.grades[0]]!
        XCTAssertEqual(NodeCanvasGeometry.insertionIndex(dragY: frame.midY - 1, in: one), 0)
        XCTAssertEqual(NodeCanvasGeometry.insertionIndex(dragY: frame.midY + 1, in: one), 0)
        XCTAssertEqual(
            NodeCanvasGeometry.insertionIndex(dragY: frame.maxY + 12, in: one), 1)
    }

    func testInsertionLineYMirrorsTheIndexSpace() {
        let layout = NodeCanvasGeometry.layout(
            for: document(gradeCount: 2).nodes, width: 248)
        let g0 = layout.frames[layout.grades[0]]!
        let g1 = layout.frames[layout.grades[1]]!

        XCTAssertEqual(
            NodeCanvasGeometry.insertionLineY(index: 0, in: layout),
            g0.minY - NodeCanvasGeometry.verticalSpacing / 2)
        XCTAssertEqual(
            NodeCanvasGeometry.insertionLineY(index: 1, in: layout),
            (g0.midY + g1.midY) / 2)
        XCTAssertEqual(
            NodeCanvasGeometry.insertionLineY(index: 2, in: layout),
            g1.maxY + NodeCanvasGeometry.verticalSpacing / 2)
        XCTAssertNil(
            NodeCanvasGeometry.insertionLineY(index: 0, in: NodeCanvasGeometry.layout(
                for: document(gradeCount: 0).nodes, width: 248)),
            "no grades → no indicator")
    }

    // MARK: - fitScale (the boundary face)

    func testFitScaleBoundaries() {
        // Content that fits → 1 (no scaling, no scroll needed).
        XCTAssertEqual(
            NodeCanvasGeometry.fitScale(contentHeight: 300, containerHeight: 600), 1)
        XCTAssertEqual(
            NodeCanvasGeometry.fitScale(contentHeight: 600, containerHeight: 600), 1)

        // Taller content → the exact shrink ratio.
        XCTAssertEqual(
            NodeCanvasGeometry.fitScale(contentHeight: 1200, containerHeight: 600),
            0.5, accuracy: 0.0001)

        // The zero/negative container never divides (returns 1).
        XCTAssertEqual(
            NodeCanvasGeometry.fitScale(contentHeight: 1200, containerHeight: 0), 1)
        XCTAssertEqual(
            NodeCanvasGeometry.fitScale(contentHeight: 1200, containerHeight: -10), 1)
    }

    // MARK: - T2: the render-geometry readback (AC3 — the machine check)

    /// The preference sink (a class box — onPreferenceChange escapes to the
    /// main actor across transaction commits).
    @MainActor
    private final class FrameBox {
        var frames: [UUID: CGRect] = [:]
    }

    /// The REAL panel (EditorState + LayerEditingState instances — the
    /// checker E2 App-level registration) hosted in a windowless
    /// NSHostingView; the card frames flow back through the
    /// `NodeCardFramesKey` preference.
    @MainActor
    func testRenderedCardFramesMatchTheLayout() throws {
        let editorState = EditorState()
        let seed = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params())
        editorState.resetHistoryForNewImage(defaultInstances: [seed])
        _ = editorState.addAdjustmentLayer()
        _ = editorState.addAdjustmentLayer()
        let doc = try XCTUnwrap(editorState.layerStack.map(PipelineDocument.init))
        XCTAssertEqual(doc.nodes.count, 4)

        let containerWidth: CGFloat = 248
        let containerHeight: CGFloat = 900 // the content fits → scale 1
        let expected = NodeCanvasGeometry.layout(for: doc.nodes, width: containerWidth)

        let box = FrameBox()
        let panel = EditorNodesPanelView(
            editorState: editorState, editingState: LayerEditingState())
            .onPreferenceChange(NodeCardFramesKey.self) { box.frames = $0 }
        let host = NSHostingView(rootView: panel)
        host.frame = NSRect(
            x: 0, y: 0, width: containerWidth, height: containerHeight)

        // A window-less host lays out on demand; pump the main run loop so
        // the SwiftUI transaction commits and the preference delivers.
        let deadline = Date().addingTimeInterval(3)
        host.layoutSubtreeIfNeeded()
        while box.frames.count < doc.nodes.count && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(
            box.frames.count, doc.nodes.count,
            "every card reported its rendered frame through the preference")

        // The RENDERED frames equal the pure-function layout, card for
        // card (the render face derives from NOTHING else — the AC3
        // machine check; recorded in DECISIONS as the 机检方式).
        for node in doc.nodes {
            let rendered = try XCTUnwrap(
                box.frames[node.id], "missing frame for \(node.kind)")
            let laid = try XCTUnwrap(expected.frames[node.id])
            XCTAssertEqual(rendered.minX, laid.minX, accuracy: 0.01, "\(node.kind) x")
            XCTAssertEqual(rendered.minY, laid.minY, accuracy: 0.01, "\(node.kind) y")
            XCTAssertEqual(rendered.width, laid.width, accuracy: 0.01, "\(node.kind) w")
            XCTAssertEqual(rendered.height, laid.height, accuracy: 0.01, "\(node.kind) h")
        }
    }

    // MARK: - The 30-node BENCH (an observation line, NOT a gate — plan T2)

    func testThirtyNodeLayoutBenchObservation() {
        let nodes = document(gradeCount: 28).nodes
        XCTAssertEqual(nodes.count, 30)

        // Warm up, then time the layout (the D-M2-4-CONTEXT-5 claim: a
        // tens-of-nodes layout is free — quantified here per round).
        _ = NodeCanvasGeometry.layout(for: nodes, width: 248)
        let clock = ContinuousClock()
        let rounds = 1000
        var totalMS: Double = 0
        for _ in 0..<rounds {
            let start = clock.now
            _ = NodeCanvasGeometry.layout(for: nodes, width: 248)
            let elapsed = clock.now - start
            totalMS += Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15  // attos → ms
        }
        let avgMS = totalMS / Double(rounds)
        print(
            "BENCH| NodeCanvasGeometry.layout 30 nodes x\(rounds) rounds " +
                "avg=\(String(format: "%.4f", avgMS)) ms/round")
        // A non-gate sanity ceiling only (D-M2-4-CONTEXT-5: "帧成本可忽略").
        XCTAssertLessThan(avgMS, 1.0, "a 30-node layout must stay sub-millisecond")
    }
}
