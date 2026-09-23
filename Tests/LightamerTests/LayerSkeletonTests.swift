import LightamerCore
import XCTest

/// D-03a structure tests for the Layer skeleton (RESEARCH §5b). Public
/// surface only.
final class LayerSkeletonTests: XCTestCase {

    /// D-03a: `LayerStack(baseLayer: BackgroundLayer())` produces a valid
    /// stack — base layer present (background kind), zero adjustment
    /// layers, its own UUID.
    func testLayerStackConstructsWithBaseLayer() {
        let stack = LayerStack(baseLayer: BackgroundLayer())
        XCTAssertEqual(stack.baseLayer.kind, .background)
        XCTAssertTrue(stack.adjustmentLayers.isEmpty, "Phase 1: base layer only")
        XCTAssertFalse(stack.id.uuidString.isEmpty)
    }

    /// The BlendMode raw values are FROZEN (sidecar stability, LAYER-07):
    /// `normal` must be 0x01, and the PS-canonical subset keeps the
    /// Darktable blend.h values. Renumbering any case would break every
    /// previously written sidecar once Phase 2 ships them.
    ///
    /// D-06-CONTEXT-2 (06-01 T1): values stay frozen; SEMANTICS follow the
    /// dt MODERN formulas (0x01 implements NORMAL2, 0x16 implements
    /// COLORADJUST) — the three-way mapping table lives in BlendMode.swift.
    /// `colorDodge` was renamed `colorAdjust` (the 0x16 slot is dt
    /// COLORADJUST, not a PS color dodge); the rawValue here is the
    /// regression anchor — decode of the integer 22 must yield `.colorAdjust`.
    func testBlendModeNormalRawValueIs1() {
        XCTAssertEqual(BlendMode.normal.rawValue, 0x01)
        XCTAssertEqual(BlendMode.multiply.rawValue, 0x04)
        XCTAssertEqual(BlendMode.linearBurn.rawValue, 0x07)
        XCTAssertEqual(BlendMode.screen.rawValue, 0x09)
        XCTAssertEqual(BlendMode.overlay.rawValue, 0x0A)
        XCTAssertEqual(BlendMode.softLight.rawValue, 0x0B)
        XCTAssertEqual(BlendMode.hardLight.rawValue, 0x0C)
        XCTAssertEqual(BlendMode.luminosity.rawValue, 0x10)
        XCTAssertEqual(BlendMode.saturation.rawValue, 0x11)
        XCTAssertEqual(BlendMode.hue.rawValue, 0x12)
        XCTAssertEqual(BlendMode.color.rawValue, 0x13)
        XCTAssertEqual(BlendMode.colorAdjust.rawValue, 0x16)
        XCTAssertEqual(BlendMode.difference.rawValue, 0x17)
        // Sidecar-ready: raw values survive a Codable round-trip.
        let data = try! JSONEncoder().encode(BlendMode.normal)
        let decoded = try! JSONDecoder().decode(BlendMode.self, from: data)
        XCTAssertEqual(decoded, .normal)
        XCTAssertEqual(decoded.rawValue, 0x01)
    }

    /// T1 regression (D-06-CONTEXT-2): the case rename `colorDodge` →
    /// `colorAdjust` must NOT disturb the sidecar encoding — Codable emits
    /// the rawValue INTEGER (case names never reach the disk). A sidecar
    /// JSON carrying `22` decodes to `.colorAdjust` with rawValue 0x16.
    func testColorAdjustRenameKeepsRawValueEncoding() throws {
        // The exact bytes a pre-rename sidecar carries for the 0x16 slot.
        let json = Data("22".utf8)
        let decoded = try JSONDecoder().decode(BlendMode.self, from: json)
        XCTAssertEqual(decoded, .colorAdjust)
        XCTAssertEqual(decoded.rawValue, 0x16)

        // The rename is encoding-neutral: encode emits the bare integer.
        let encoded = try JSONEncoder().encode(BlendMode.colorAdjust)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "22")

        // And every other mode survives the same integer round-trip.
        for mode in BlendMode.allCases {
            let back = try JSONDecoder().decode(
                BlendMode.self, from: JSONEncoder().encode(mode))
            XCTAssertEqual(back, mode)
            XCTAssertEqual(back.rawValue, mode.rawValue)
        }
    }

    /// T1: `BlendOptions.reverse` carries dt's `DEVELOP_BLEND_REVERSE`
    /// flag bit (blend.h:89) — 0x80000000, disjoint from every mode slot
    /// (`DEVELOP_BLEND_MODE_MASK = 0xFF`).
    func testBlendOptionsReverseFlagValue() {
        XCTAssertEqual(BlendOptions.reverse.rawValue, 0x8000_0000)
        // Mode slots never overlap the REVERSE bit.
        for mode in BlendMode.allCases {
            XCTAssertEqual(mode.dtModeSlot, mode.dtPackedValue & 0xFF)
            XCTAssertEqual(
                mode.dtPackedValue & BlendOptions.reverse.rawValue, 0,
                "mode raw values must stay below the REVERSE flag bit")
        }
    }

    /// D-03a: `BackgroundLayer` satisfies the full `Layer` requirement
    /// surface with its LAYER-01 defaults — "Background", visible, opacity
    /// 1.0, normal blend, enabled, kind .background, stable UUID identity.
    func testBackgroundLayerConformsToLayer() {
        let layer: any Layer = BackgroundLayer()
        XCTAssertFalse(layer.id.uuidString.isEmpty, "Identifiable: UUID identity")
        XCTAssertEqual(layer.name, "Background")
        XCTAssertTrue(layer.isVisible)
        XCTAssertEqual(layer.opacity, 1.0)
        XCTAssertEqual(layer.blendMode, .normal)
        XCTAssertTrue(layer.enabled)
        XCTAssertEqual(layer.kind, .background)
    }
}
