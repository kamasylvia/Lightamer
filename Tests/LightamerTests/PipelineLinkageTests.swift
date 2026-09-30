@testable import LightamerCore
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PipelineLinkageTests (Plan M2-4-2 T2, AC4/AC5) — the graph document's
// M2-7 data face + the selection mapping:
//
//   maskGroups 组序    — one group per grade in GRADE order (D-M2-4-CONTEXT-9:
//                        组序 = grade 序 = 层序), every grade projecting even
//                        when maskless (empty masks).
//   reorder 跟随       — after `LayerStack.reorder` a RE-PROJECTED document
//                        carries the new order — the pure-derivation proof
//                        that M2-7's drag-to-reorder can ride the Reconnect
//                        command with ZERO sync points (no double-write to
//                        test, the projection cannot drift).
//   item 摘要 parity   — MaskItemSummary ≡ MaskSpec.maskItems field by field
//                        (id/name/enabled/opacity/inverted, order kept).
//   node(for:) 全分支  — nil → nil; develop id; grade UUID; drt constant id;
//                        unknown id (retouch/foreign) → nil.
//   displayTitle 四分支 — unselected = the "Color Grade" constant face
//                        (byte-identical M2-3-3 contract); develop;
//                        grade → the layer name; drt.
//
// Core-level suite (checker E2 → LightamerTestsLayers): pure Core types
// only, no App-target imports.
// ─────────────────────────────────────────────────────────────────────────────

final class PipelineLinkageTests: XCTestCase {

    // MARK: - Fixtures

    private func makeStack(layers: [AdjustmentLayer] = []) -> LayerStack {
        var stack = LayerStack(baseLayer: BackgroundLayer())
        for layer in layers { stack.addAdjustment(layer) }
        return stack
    }

    private func grade(
        name: String, mask: MaskSpec? = nil
    ) -> AdjustmentLayer {
        AdjustmentLayer(name: name, mask: mask)
    }

    /// A two-item drawn mask group over two ellipse forms (the summary
    /// parity carrier: one enabled named item + one default item).
    private func twoItemMask() -> MaskSpec {
        func circle(_ cx: Float, _ r: Float) -> MaskForm {
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: cx, y: 0.5), radiusX: r, radiusY: r,
                rotationDegrees: 0, border: 0)))
        }
        let forms = [circle(0.38, 0.2), circle(0.62, 0.16)]
        var spec = MaskSpec(drawn: DrawnMaskSpec(
            forms: forms,
            group: MaskGroupSpec(items: [
                MaskGroupItem(
                    formID: forms[0].id, op: .union, inverted: false, opacity: 1,
                    enabled: false, displayName: "Sky"),
                MaskGroupItem(
                    formID: forms[1].id, op: .intersect, inverted: true, opacity: 0.6),
            ])))
        spec.deletionProtected = false
        return spec
    }

    // MARK: - 1: the group order == the grade order (AC4)

    func testMaskGroupsProjectInGradeOrder() {
        let masked = twoItemMask()
        let stack = makeStack(layers: [
            grade(name: "Bottom"),
            grade(name: "Middle", mask: masked),
            grade(name: "Top"),
        ])
        let document = PipelineDocument(stack)

        // One group per grade — maskless grades project too (empty masks).
        XCTAssertEqual(document.maskGroups.count, 3)
        XCTAssertEqual(
            document.maskGroups.map(\.gradeNode.id),
            stack.compositeLayers.map(\.id),
            "组序 = grade 序 (D-M2-4-CONTEXT-9)")
        XCTAssertEqual(
            document.maskGroups.map { $0.gradeNode.name },
            ["Bottom", "Middle", "Top"])
        XCTAssertTrue(document.maskGroups[0].masks.isEmpty)
        XCTAssertTrue(document.maskGroups[2].masks.isEmpty)

        // The masked grade carries its two items in group order.
        let middle = document.maskGroups[1]
        XCTAssertEqual(middle.masks.count, 2)
        XCTAssertEqual(middle.masks[0].id, masked.drawn?.group?.items[0].formID)
        XCTAssertEqual(middle.masks[0].name, "Sky")
        XCTAssertFalse(middle.masks[0].isEnabled, "the v5 gate folds through")
        XCTAssertTrue(middle.masks[1].isInverted)
        XCTAssertEqual(middle.masks[1].opacity, 0.6)

        // Purity: a second projection from the same stack is Equal (the
        // groups ride the same per-read rebuild as the node segments).
        XCTAssertEqual(document.maskGroups, PipelineDocument(stack).maskGroups)
    }

    // MARK: - 2: reorder → the projection follows (the D9 proof)

    func testMaskGroupsFollowReorderWithoutAnySyncPoint() {
        let masked = twoItemMask()
        let bottom = grade(name: "Masked", mask: masked)
        let top = grade(name: "Plain")
        var stack = makeStack(layers: [bottom, top])

        let before = PipelineDocument(stack)
        XCTAssertEqual(
            before.maskGroups.map { $0.gradeNode.name }, ["Masked", "Plain"])

        // The Reconnect landing face: `LayerStack.reorder` — identities
        // untouched, order flipped. NO document object is mutated (value
        // semantics): a re-init IS the sync (KD-3's zero-sync-point proof).
        stack.reorder(id: bottom.id, to: 1)
        let after = PipelineDocument(stack)

        XCTAssertEqual(
            after.maskGroups.map { $0.gradeNode.name }, ["Plain", "Masked"],
            "the group order followed the grade order after the reorder")
        XCTAssertEqual(
            after.maskGroups[1].gradeNode.id, bottom.id,
            "the layer UUID (the M2-7 row anchor) survived the reorder")
        XCTAssertEqual(
            after.maskGroups[1].masks.count, 2,
            "the masked group still carries its items at the new position")
        // …and the pre-reorder projection is untouched (pure derivation).
        XCTAssertEqual(
            before.maskGroups.map { $0.gradeNode.name }, ["Masked", "Plain"])
    }

    // MARK: - 3: the item summary parity with MaskSpec.maskItems (AC4)

    func testMaskItemSummaryParityWithTheSpecReadView() throws {
        let masked = twoItemMask()
        let stack = makeStack(layers: [grade(name: "G", mask: masked)])
        let document = PipelineDocument(stack)

        let summaries = document.maskGroups[0].masks
        let readView = try XCTUnwrap(stack.compositeLayers[0].mask).maskItems
        XCTAssertEqual(summaries.count, readView.count)
        for (summary, item) in zip(summaries, readView) {
            XCTAssertEqual(summary.id, item.id)
            XCTAssertEqual(summary.name, item.name)
            XCTAssertEqual(summary.isEnabled, item.enabled)
            XCTAssertEqual(summary.opacity, item.opacity)
            XCTAssertEqual(summary.isInverted, item.inverted)
        }
        // The maskless grade projects no items.
        let bare = PipelineDocument(makeStack(layers: [grade(name: "Bare")]))
        XCTAssertTrue(bare.maskGroups[0].masks.isEmpty)
    }

    // MARK: - 4: node(for:) — every branch (AC5)

    func testNodeForIDCoversAllBranches() {
        var stack = makeStack(layers: [grade(name: "G1"), grade(name: "G2")])
        stack.addAdjustment(RetouchLayer(name: "Heal")) // off-graph kind
        let document = PipelineDocument(stack)

        // nil = unselected.
        XCTAssertNil(document.node(for: nil))
        // The develop endpoint.
        XCTAssertEqual(document.node(for: document.develop.id)?.kind, .develop)
        // A grade UUID → its own node.
        let gradeNode = document.grades.first { $0.name == "G2" }
        XCTAssertEqual(gradeNode?.name, "G2")
        XCTAssertEqual(document.node(for: gradeNode?.id)?.id, gradeNode?.id)
        // The drt constant id.
        XCTAssertEqual(
            document.node(for: PipelineDocument.displayTransformNodeID)?.kind,
            .displayTransform)
        // Unknown ids: a retouch layer (a REAL layer, off-graph) and a
        // foreign UUID both resolve nil.
        let retouchID = stack.adjustmentLayers.first { $0 is RetouchLayer }?.id
        XCTAssertNotNil(retouchID)
        XCTAssertNil(document.node(for: retouchID), "retouch never enters the graph")
        XCTAssertNil(document.node(for: UUID()))
    }

    // MARK: - 5: displayTitle — the four branches (AC5)

    func testDisplayTitleCoversAllBranches() throws {
        let stack = makeStack(layers: [grade(name: "My Grade")])
        let document = PipelineDocument(stack)
        let gradeID = document.grades[0].id

        // Unselected = the M2-3-3 constant face. The contract is KEY
        // identity, not the English literal: the header renders
        // `String(localized: "editor_node_name", ...)`, so on a zh-locale
        // host the resolved value is the catalog's 「调色」 — assert against
        // the SAME resolution (byte-identical render, any locale).
        let constantFace = String(localized: "editor_node_name", defaultValue: "Color Grade")
        XCTAssertEqual(document.displayTitle(for: nil), constantFace)
        // Unknown/retouch ids degrade to the same constant face (the view
        // cannot tell them apart from "nothing selected" — by design).
        XCTAssertEqual(document.displayTitle(for: UUID()), constantFace)
        // The develop endpoint. KEY identity, not the English literal (the
        // M2-4-2 acceptance finding 3: the catalog now carries zh values,
        // so a zh-locale host resolves them — assert the SAME resolution).
        XCTAssertEqual(
            document.displayTitle(for: document.develop.id),
            String(localized: "editor_node_develop", defaultValue: "Develop"))
        // A grade → the LAYER NAME (user data, not a kind label).
        XCTAssertEqual(document.displayTitle(for: gradeID), "My Grade")
        // The drt endpoint (the same KEY-identity contract).
        XCTAssertEqual(
            document.displayTitle(for: PipelineDocument.displayTransformNodeID),
            String(localized: "editor_node_drt", defaultValue: "Display Transform"))

        // The rename command flows through the projection (Reconnect-style
        // pure derivation: re-init after the mutation).
        let renamed = try NodeGraphCommand.renameGrade(id: gradeID, to: "Teal")
            .apply(to: stack)
        XCTAssertEqual(
            PipelineDocument(renamed).displayTitle(for: gradeID), "Teal")
    }
}
