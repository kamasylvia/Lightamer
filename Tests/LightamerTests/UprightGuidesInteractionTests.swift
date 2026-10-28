@testable import LightamerCore
@testable import LightamerIOP
@testable import Lightamer
import Metal
import XCTest

/// UprightGuidesInteractionTests (Plan M9-3-T4) — the Guided Upright guides'
/// interaction state machine + the coordinate channel, in the upstream
/// tests_guided_guides semantics (5+5 faces in-process):
///   ① press-drag STARTS a guide at the press point (zero-length press is
///      not a guide);
///   ② an endpoint drag moves THAT end (1e-3-scale follow) while the other
///      end and the other guides stay untouched;
///   ③ a click near a line selects (UI-only); a click on blank clears;
///   ④ Delete with no selection is a NO-OP (no guide, no item);
///   ⑤ the 5th guide is refused.
/// Plus the persistence faces: one history item per edit step (undo walks
/// the guides back stepwise), the selection never enters params/sidecar,
/// and the mapper round-trip stays under 1 px (the ONLY coordinate channel).
@MainActor
final class UprightGuidesInteractionTests: XCTestCase {

    // MARK: - ①② the draw + endpoint-drag faces

    func testDrawAndEndpointDragSemantics() {
        var m = UprightGuidesModel()

        // ① press-drag draws: the guide STARTS at the press point
        XCTAssertTrue(m.press(at: SIMD2(0.2, 0.3)), "a draw press is accepted")
        XCTAssertNotNil(m.pending, "the pending guide exists from the press")
        XCTAssertEqual(m.pending?.ax ?? -1, 0.2, accuracy: 1e-12, "starts at the press point")
        XCTAssertEqual(m.pending?.ay ?? -1, 0.3, accuracy: 1e-12)
        m.dragTick(at: SIMD2(0.8, 0.3))
        m.release()
        XCTAssertEqual(m.guides.count, 1)
        XCTAssertEqual(m.guides[0].bx, 0.8, accuracy: 1e-12)
        // a zero-length press (down-up, no drag) is NOT a guide
        XCTAssertTrue(m.press(at: SIMD2(0.4, 0.5)))
        m.release()
        XCTAssertEqual(m.guides.count, 1, "the zero-length press landed no guide")

        // ② the endpoint drag: near-end follows at 1e-3 granularity, the
        // far end and the other guides untouched
        XCTAssertTrue(m.press(at: SIMD2(0.8, 0.3)), "the endpoint press grabs the drag")
        XCTAssertNotNil(m.dragging, "an endpoint drag is armed")
        XCTAssertEqual(m.dragging?.index, 0)
        XCTAssertEqual(m.dragging?.end, 1, "the B end (the one we pressed near)")
        m.dragTick(at: SIMD2(0.85, 0.35))
        m.release()
        XCTAssertEqual(m.guides[0].bx, 0.85, accuracy: 1e-3, "the near end follows")
        XCTAssertEqual(m.guides[0].by, 0.35, accuracy: 1e-3)
        XCTAssertEqual(m.guides[0].ax, 0.2, accuracy: 1e-12, "the far end does NOT move")
        XCTAssertEqual(m.guides[0].ay, 0.3, accuracy: 1e-12)
    }

    // MARK: - ③④⑤ the selection + delete + cap faces

    func testSelectionDeleteAndCap() {
        var m = UprightGuidesModel()
        for (a, b) in [((0.1, 0.1), (0.9, 0.1)), ((0.1, 0.5), (0.9, 0.5)), ((0.1, 0.9), (0.9, 0.9))] {
            XCTAssertTrue(m.press(at: SIMD2(a.0, a.1)))
            m.dragTick(at: SIMD2(b.0, b.1))
            m.release()
        }
        XCTAssertEqual(m.guides.count, 3)

        // ③ a click near a line selects (the line body, not an endpoint)
        let hit = m.lineHit(at: SIMD2(0.5, 0.505))
        XCTAssertEqual(hit, 1, "the click 0.005 above line 1 selects it")
        m.selected = hit
        // a click on blank clears
        XCTAssertNil(m.lineHit(at: SIMD2(0.5, 0.3)), "the midpoint between lines is blank")
        m.selected = nil

        // ④ Delete with no selection: a NO-OP (no guide, no change)
        let before = m.guides
        XCTAssertFalse(m.deleteSelected(), "no selection → no action")
        XCTAssertEqual(m.guides, before, "the guides are untouched")

        // ④' Delete WITH a selection removes exactly the selected one
        m.selected = 1
        XCTAssertTrue(m.deleteSelected())
        XCTAssertEqual(m.guides.count, 2)
        XCTAssertNil(m.selected, "nothing stays selected afterwards")
        // the survivor is the FIRST guide (the second one's endpoints gone)
        XCTAssertEqual(m.guides[0].ay, 0.1, accuracy: 1e-9, "the first guide survived")

        // ⑤ the 5th guide is refused (the draw coordinates avoid every
        // existing endpoint — the press (0.2, 0.2) would grab the first
        // survivor's a-end instead of drawing)
        XCTAssertTrue(m.press(at: SIMD2(0.2, 0.7)))
        m.dragTick(at: SIMD2(0.8, 0.7))
        m.release()
        XCTAssertTrue(m.press(at: SIMD2(0.15, 0.78)))
        m.dragTick(at: SIMD2(0.85, 0.78))
        m.release()
        XCTAssertEqual(m.guides.count, 4, "four guides in place")
        XCTAssertFalse(m.press(at: SIMD2(0.5, 0.99)), "the 5th draw press is refused")
        XCTAssertNil(m.pending, "no pending guide leaked")
    }

    // MARK: - the persistence faces

    func testGuidesPersistenceAndUndoStepwise() throws {
        let editorState = EditorState()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: UprightModule.self, params: UprightModule.Params()),
        ])
        let record = try XCTUnwrap(
            editorState.instances.first { $0.opName == UprightModule.opName })

        // each edit step lands exactly ONE history item; undo walks the
        // guides back stepwise (the upstream undo granularity)
        func commit(guides: [UprightModule.Guide]) throws {
            var snapshot = record
            var params = try record.params(of: UprightModule.self)
            params.guides = guides
            try snapshot.setParams(params, as: UprightModule.self)
            editorState.recordChange(snapshot, label: "history_upright_guides")
        }
        let g1 = UprightModule.Guide(ax: 0.2, ay: 0.2, bx: 0.8, by: 0.2)
        let g2 = UprightModule.Guide(ax: 0.2, ay: 0.8, bx: 0.8, by: 0.8)
        try commit(guides: [g1])
        try commit(guides: [g1, g2])
        XCTAssertEqual(editorState.history.items.count, 2, "one item per edit step")
        let live = try XCTUnwrap(
            editorState.instances.first { $0.opName == UprightModule.opName })
        XCTAssertEqual(try live.params(of: UprightModule.self).guides.count, 2)
        XCTAssertTrue(editorState.performUndo())
        let afterUndo = try XCTUnwrap(
            editorState.instances.first { $0.opName == UprightModule.opName })
        XCTAssertEqual(try afterUndo.params(of: UprightModule.self).guides.count, 1,
            "undo walks the guides back one step")
        XCTAssertTrue(editorState.performUndo())
        let afterTwoUndos = try XCTUnwrap(
            editorState.instances.first { $0.opName == UprightModule.opName })
        XCTAssertEqual(try afterTwoUndos.params(of: UprightModule.self).guides.count, 0)

        // the selection is UI-ONLY: it never enters the params bytes
        // (the serde-skip face — the params JSON contains no selection key)
        try commit(guides: [g1])
        let current = try XCTUnwrap(
            editorState.instances.first { $0.opName == UprightModule.opName })
        let json = String(data: current.paramsData, encoding: .utf8) ?? ""
        XCTAssertFalse(json.lowercased().contains("select"),
            "the params carry no selection state")
    }

    // MARK: - the mapper round-trip (the ONLY coordinate channel)

    func testMapperRoundTripUnder1px() throws {
        // the pre-upright chain (an ashift rotation, the lens/flip/crop
        // face the tool actually draws over) composed against a frame; the
        // viewport → upright-input-frame → viewport round trip stays <1 px.
        let ashiftBox = ModuleBox(module: AshiftModule(), instanceID: UUID())
        ashiftBox.setParams(AshiftModule.Params(rotation: 8))
        let width = 720.0, height = 480.0
        let mapper = GeometryPointMapper.compose(
            boxes: [ashiftBox], frameSize: SIMD2(width, height))
        var worst = 0.0
        for qy in stride(from: 40.0, to: height - 40, by: 80) {
            for qx in stride(from: 40.0, to: width - 40, by: 90) {
                let q = SIMD2(qx, qy)
                let back = mapper.forward(normalized: mapper.inverse(normalized: q))
                let dx = back.x - q.x
                let dy = back.y - q.y
                worst = max(worst, (dx * dx + dy * dy).squareRoot())
            }
        }
        XCTAssertLessThan(worst, 1.0, "the mapper round-trip stays under 1 px")
    }

    // MARK: - the live face (D-H1)

    func testLiveWindowLandsOneItemPerCommit() throws {
        let editorState = EditorState()
        editorState.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: UprightModule.self, params: UprightModule.Params()),
        ])
        let record = try XCTUnwrap(
            editorState.instances.first { $0.opName == UprightModule.opName })

        // live ticks (applyLiveInstance) accumulate ZERO history items —
        // the D-H1 drag face
        var live = record
        var params = try record.params(of: UprightModule.self)
        params.guides = [UprightModule.Guide(ax: 0.1, ay: 0.1, bx: 0.9, by: 0.1)]
        try live.setParams(params, as: UprightModule.self)
        editorState.applyLiveInstance(live)
        XCTAssertEqual(editorState.history.items.count, 0, "live ticks land no item")
        // the live instance set carries the preview
        let projected = try XCTUnwrap(
            editorState.instances.first { $0.opName == UprightModule.opName })
        XCTAssertEqual(try projected.params(of: UprightModule.self).guides.count, 1)
        // the release commit lands exactly ONE item
        editorState.recordChange(live, label: "history_upright_guides")
        XCTAssertEqual(editorState.history.items.count, 1)
    }
}
