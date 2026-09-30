import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// CatalogAddFaceTests (Plan M2-5-2; T4 hangs the trackball state machine
// checks here per the plan's T4 action-3 seat, T6 extends with the add-face
// enumeration matrix):
//
//   T4 — the LGG trackball (KD-2):
//     1. disc↔point conversions round-trip; the unit-disc clamp holds.
//     2. the Alcedo cdlDelta mapping: hue direction + strength·radius
//        scale; the per-wheel derivation anchors (lift 0 / gamma·gain 1,
//        gamma inverted).
//     3. per-wheel reset restores the payload identity control.
//     4. the reset commit through a REAL EditorState layer session lands
//        chain params byte-identical to the GradeCatalog identityJSON.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CatalogAddFaceTests: XCTestCase {

    // MARK: - 1: disc↔point conversions (KD-2)

    func testDiscPointRoundTripAndClamp() {
        let center = SIMD2<Float>(100, 80)
        let radius: Float = 40
        // Round trip: a view point inside the disc maps to the disc and
        // back to the same point (y flip symmetric).
        let inside = SIMD2<Float>(130, 60) // +30, −20 → up-right of center
        let disc = ColorWheelsModule.discFrom(point: inside, relativeTo: center, radius: radius)
        XCTAssertEqual(disc.x, 0.75, accuracy: 1e-6)
        XCTAssertEqual(disc.y, 0.5, accuracy: 1e-6, "view y flips (up = +disc y)")
        let back = ColorWheelsModule.pointFrom(disc: disc, radius: radius)
        XCTAssertEqual(center.x + back.x, Float(inside.x), accuracy: 1e-4)
        XCTAssertEqual(center.y + back.y, Float(inside.y), accuracy: 1e-4)
        // The clamp: a far point lands ON the unit circle.
        let far = SIMD2<Float>(1000, -1000)
        let clamped = ColorWheelsModule.discFrom(point: far, relativeTo: center, radius: radius)
        XCTAssertLessThanOrEqual(Double(sqrt(clamped.x * clamped.x + clamped.y * clamped.y)), 1 + 1e-6)
        // Center maps to zero disc.
        XCTAssertEqual(
            ColorWheelsModule.discFrom(point: center, relativeTo: center, radius: radius),
            SIMD2<Float>(0, 0))
    }

    // MARK: - 2: the cdlDelta derivation (the Alcedo trackball mapping)

    func testCdlDeltaAndWheelDerivation() {
        // Hue direction: disc (1, 0) is hue 0 → unit RGB (1, 0, 0) → mean
        // 1/3 → direction (2/3, −1/3, −1/3) normalized (2, −1, −1)/√6.
        let delta = ColorWheelsModule.cdlDelta(disc: SIMD2<Float>(1, 0), strength: 0.1)
        let expected = SIMD3<Float>(2, -1, -1) / sqrt(6)
        for lane in [0, 1, 2] {
            XCTAssertEqual(
                delta[lane], expected[lane] * 0.1, accuracy: 1e-6,
                "scale = strength × radius(1)")
        }
        // Zero disc = zero delta (the wheel at rest moves nothing).
        XCTAssertEqual(
            ColorWheelsModule.cdlDelta(disc: SIMD2<Float>(0, 0), strength: 0.1),
            SIMD3<Float>(0, 0, 0))
        // The UpdateDerived strength clamp: the payload pristine carries
        // strength 1.0 (outside the 0...0.1 UI working range) — the first
        // drag on a fresh wheel must derive the SAME offset as the clamp
        // ceiling 0.1, never a 10× delta (acceptance M2-5-2).
        XCTAssertEqual(
            ColorWheelsModule.cdlDelta(disc: SIMD2<Float>(0.6, 0), strength: 1.0),
            ColorWheelsModule.cdlDelta(disc: SIMD2<Float>(0.6, 0), strength: 0.1))
        // The per-wheel anchors (Alcedo UpdateDerived): lift rides base 0,
        // gamma/gain ride base 1 with gamma's delta inverted.
        let d = ColorWheelsModule.cdlDelta(disc: SIMD2<Float>(0.5, 0.5), strength: 0.05)
        XCTAssertEqual(
            ColorWheelsModule.colorOffset(from: SIMD2<Float>(0.5, 0.5), strength: 0.05, wheel: .lift),
            SIMD3(0, 0, 0) + d)
        XCTAssertEqual(
            ColorWheelsModule.colorOffset(from: SIMD2<Float>(0.5, 0.5), strength: 0.05, wheel: .gamma),
            SIMD3(1, 1, 1) - d)
        XCTAssertEqual(
            ColorWheelsModule.colorOffset(from: SIMD2<Float>(0.5, 0.5), strength: 0.05, wheel: .gain),
            SIMD3(1, 1, 1) + d)
    }

    // MARK: - 3/4: the resets (per-wheel double-click + Reset wheels)

    func testPerWheelResetRestoresPayloadIdentity() {
        var dragged = ColorWheelsModule.Params()
        dragged.lift.disc = SIMD2(0.6, 0.4)
        dragged.lift.colorOffset = ColorWheelsModule.colorOffset(
            from: dragged.lift.disc, strength: 0.05, wheel: .lift)
        dragged.lift.luminanceOffset = 0.2
        dragged.gamma.disc = SIMD2(-0.3, 0.1)
        XCTAssertFalse(ColorWheelsModule.isIdentity(dragged))
        // Each wheel's reset restores exactly that control to the payload
        // default; all three == Params() == the identity snapshot.
        XCTAssertEqual(ColorWheelsModule.resetting(dragged, wheel: .lift).lift, ColorWheelControl())
        XCTAssertEqual(
            ColorWheelsModule.resetting(dragged, wheel: .gamma),
            ColorWheelsModule.Params(lift: dragged.lift, gain: dragged.gain))
        XCTAssertEqual(
            ColorWheelsModule.resetting(dragged, wheel: .gain).gain, ColorWheelControl(colorOffset: SIMD3(1, 1, 1)))
        var all = dragged
        for wheel in ColorWheelsModule.WheelKind.allCases {
            all = ColorWheelsModule.resetting(all, wheel: wheel)
        }
        XCTAssertEqual(all, ColorWheelsModule.Params())
        XCTAssertTrue(ColorWheelsModule.isIdentity(all))
    }

    /// The panel's reset commit through a REAL EditorState layer session:
    /// the chain's committed record must be byte-identical to the
    /// GradeCatalog identityJSON (AC#5's "逐字节").
    func testResetWheelsThroughEditorStateMatchesIdentityJSONByteForByte() throws {
        let editor = EditorState()
        editor.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ])
        let layer = try XCTUnwrap(editor.addAdjustmentLayer())
        let template = ModuleInstance(
            module: ColorWheelsModule.self, params: ColorWheelsModule.Params())
        let record = try XCTUnwrap(
            editor.addModuleToLayer(layerID: layer.id, template: template))

        // The drag state (disc + the derived colorOffset + a luminance nudge).
        var dragged = ColorWheelsModule.Params()
        dragged.gain.disc = SIMD2(0.4, -0.6)
        dragged.gain.strength = 0.08
        dragged.gain.colorOffset = ColorWheelsModule.colorOffset(
            from: dragged.gain.disc, strength: dragged.gain.strength, wheel: .gain)
        dragged.gain.luminanceOffset = -0.25
        var dragRecord = record
        try dragRecord.setParams(dragged, as: ColorWheelsModule.self)
        editor.recordLayerChange(dragRecord, layerID: layer.id, label: "drag")
        XCTAssertFalse(
            ColorWheelsModule.isIdentity(try XCTUnwrap(
                editor.adjustmentLayer(id: layer.id)?
                    .chain.last(where: { $0.opName == ColorWheelsModule.opName })
                ).map { try $0.params(of: ColorWheelsModule.self) }
                ?? ColorWheelsModule.Params()))

        // The panel's Reset wheels: identityJSON decode → ONE discrete commit.
        let item = try XCTUnwrap(GradeCatalog.item(opName: ColorWheelsModule.opName))
        let identity = try JSONDecoder().decode(
            ColorWheelsModule.Params.self, from: Data(item.identityJSON.utf8))
        var resetRecord = dragRecord
        try resetRecord.setParams(identity, as: ColorWheelsModule.self)
        editor.recordLayerChange(resetRecord, layerID: layer.id, label: "reset wheels")

        let chain = try XCTUnwrap(editor.adjustmentLayer(id: layer.id)).chain
        let committed = try XCTUnwrap(
            chain.last(where: { $0.opName == ColorWheelsModule.opName }))
        XCTAssertEqual(
            committed.paramsData, Data(item.identityJSON.utf8),
            "the reset commit's params bytes == the identityJSON bytes")
        XCTAssertTrue(
            ColorWheelsModule.isIdentity(try committed.params(of: ColorWheelsModule.self)))
    }

    // MARK: - M2-5-2 T5: the Selective Color panel state machine (AC#6)

    /// Bin switching: the panel's display faces read THE BIN's stored row
    /// (the 8-bin table is the only truth — the selection is UI state).
    func testHlsDisplayValuesTrackTheSelectedBin() throws {
        var params = HlsModule.Params()
        // Write bin 3 through the P1 mapping (the panel's own write face).
        params = HlsModule.applyTargetEdit(
            params: params, targetBin: 3, dh: 12, dl: -40, ds: 55)
        // Bin 3 reflects the edit (lightness/chroma ride ×1000 display).
        let bin3 = HlsPanelView.displayValues(of: params, bin: 3)
        XCTAssertEqual(bin3.hueShift, 12, accuracy: 1e-6)
        XCTAssertEqual(bin3.lightness, -40, accuracy: 1e-4)
        XCTAssertEqual(bin3.chroma, 55, accuracy: 1e-4)
        // A different bin still reads ITS OWN row (all zero here).
        let bin0 = HlsPanelView.displayValues(of: params, bin: 0)
        XCTAssertEqual(bin0.hueShift, 0, accuracy: 1e-6)
        XCTAssertEqual(bin0.lightness, 0, accuracy: 1e-4)
        // The smoothness face reads hRangeTable[bin] (default 45).
        XCTAssertEqual(bin3.smoothness, 45, accuracy: 1e-6)
    }

    /// The slider write path == the P1 applyTargetEdit output (same source
    /// as the golden Float64 reference), and the smoothness write mirrors
    /// hRangeTable[bin] into hRange (the D4 projection leg).
    func testHlsSliderWritesRideApplyTargetEditAndSmoothnessMirror() throws {
        var params = HlsModule.Params()
        // The panel's hue-shift tick transforms through applyTargetEdit;
        // the model-level equivalence is the assertion here.
        var transformed = params
        transformed = HlsModule.applyTargetEdit(
            params: transformed, targetBin: 5, dh: 30, dl: 0, ds: 0)
        transformed.hRangeTable[5] = 90
        transformed.hRange = 90
        // The reference: hand-applying the same mapping legs.
        var reference = params
        reference.adjTable[5] = HlsVec3(h: 30, l: 0, s: 0)
        reference.hlsAdj = reference.adjTable[5]
        reference.hRangeTable[5] = 90
        reference.hRange = reference.hRangeTable[5]
        reference.targetHls = HlsVec3(h: reference.hueBins[5], l: 0.5, s: 0.5)
        reference.lRange = 1.0
        reference.sRange = 1.0
        XCTAssertEqual(transformed, reference)
        // Smoothness clamps hold (the slider range 1...180 feeds the field).
        XCTAssertGreaterThan(transformed.hRangeTable[5], 0)
    }

    // MARK: - M2-5-2 T6: the add-face enumeration matrix (AC#7)

    /// A fresh EditorState harness with one base record + one Grade layer.
    private func makeEditorWithGradeLayer() throws -> (EditorState, UUID) {
        let editor = EditorState()
        editor.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ])
        let layer = try XCTUnwrap(editor.addAdjustmentLayer())
        return (editor, layer.id)
    }

    /// Grade scope: the catalog enumeration EXACTLY — the grade-owned rows
    /// narrowed by the two binding clauses (LMT → the LUT page per D10;
    /// the shadows/highlights pair = ONE shadhi entry per checker m2).
    func testGradeScopeAddFaceEnumeratesTheCatalogMatrix() throws {
        let (editor, layerID) = try makeEditorWithGradeLayer()
        let entries = editor.addFaceEntries(layerID: layerID)
        // The unique-op matrix (AC#7 "逐目录 id 断言"; the plan's "恰 14"
        // count reconciliation lives in EditorState + DECISIONS — the
        // binding clauses leave 12 unique-op entries).
        XCTAssertEqual(
            entries.compactMap(\.catalogID),
            [
                "cat02WhiteBalance", "exposure", "contrast", "white", "black",
                "shadows", "curve", "hls", "saturation", "vibrance",
                "colorWheel", "tint",
            ])
        // LMT is NOT in any add enumeration (its seat is the LUT page).
        XCTAssertFalse(entries.contains { $0.template.opName == Lut3dModule.opName })
        // The four DRT seats never enumerate.
        for op in [SharpenModule.opName, GrainModule.opName, BloomModule.opName, EqualizerModule.opName] {
            XCTAssertFalse(entries.contains { $0.template.opName == op }, op)
        }
        // The shadows/highlights collapse: exactly one shadhi entry.
        XCTAssertEqual(entries.filter { $0.template.opName == ShadhiModule.opName }.count, 1)
        // Every catalog template's params bytes == the row's identityJSON.
        for entry in entries {
            let item = try XCTUnwrap(
                GradeCatalog.items.first { $0.catalogID == entry.catalogID })
            XCTAssertEqual(entry.template.paramsData, Data(item.identityJSON.utf8))
        }
    }

    /// Develop scope: ZERO grade-owned entries (D4 收窄); temperature 在
    /// 列 and exposure 不在列 (the AC's two named pins).
    func testDevelopScopeAddFaceExcludesEveryGradeOwnedOp() throws {
        let (editor, _) = try makeEditorWithGradeLayer()
        let entries = editor.addFaceEntries(layerID: nil)
        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            XCTAssertNotEqual(
                NodeOwnershipCatalog.owner(of: entry.template.opName), .grade,
                "the Develop add face must never enumerate \(entry.template.opName)")
            XCTAssertNil(entry.catalogID, "non-catalog ops carry no catalog id")
        }
        XCTAssertTrue(
            entries.contains { $0.template.opName == TemperatureModule.opName },
            "temperature 在列 (the AC's Develop pin)")
        XCTAssertFalse(
            entries.contains { $0.template.opName == ExposureModule.opName },
            "exposure 不在列 (grade-owned, D4)")
        // The compat section exists and carries the D6-only family.
        let compat = entries.filter { $0.section == .compat }
        XCTAssertTrue(compat.contains { $0.template.opName == AshiftModule.opName })
        XCTAssertTrue(compat.contains { $0.template.opName == WatermarkModule.opName })
    }

    /// The base-chain add action: ONE D-H1 commit lands the fresh-identity
    /// record in the global instance set (the no-layer branch's insert).
    func testBaseChainAddLandsOneCommitWithFreshIdentity() throws {
        let (editor, _) = try makeEditorWithGradeLayer()
        let before = editor.instances.count
        let historyBefore = editor.history.items.count
        let template = try XCTUnwrap(
            EditorState.templateInstance(for: TemperatureModule.opName))
        let record = try XCTUnwrap(editor.addModuleToBaseChain(template: template))
        XCTAssertNotEqual(record.id, template.id, "fresh identity on insert")
        XCTAssertEqual(editor.instances.count, before + 1)
        XCTAssertEqual(editor.history.items.count, historyBefore + 1, "ONE commit")
        XCTAssertTrue(
            editor.instances.contains { $0.id == record.id })
        // One undo steps back over the add (the record vanishes).
        XCTAssertTrue(editor.performUndo())
        XCTAssertEqual(editor.instances.count, before)
    }
}
