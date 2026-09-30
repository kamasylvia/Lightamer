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
}
