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
        XCTAssertEqual(BlendMode.colorDodge.rawValue, 0x16)
        XCTAssertEqual(BlendMode.difference.rawValue, 0x17)
        // Sidecar-ready: raw values survive a Codable round-trip.
        let data = try! JSONEncoder().encode(BlendMode.normal)
        let decoded = try! JSONDecoder().decode(BlendMode.self, from: data)
        XCTAssertEqual(decoded, .normal)
        XCTAssertEqual(decoded.rawValue, 0x01)
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
