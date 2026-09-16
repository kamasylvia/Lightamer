import LightamerCore
import XCTest

/// D-03a structure tests for the Layer skeleton (RESEARCH §5b).
///
/// Phase 1: stubs — bodies are filled by Plan 06.
final class LayerSkeletonTests: XCTestCase {

    /// D-03a: `LayerStack(baseLayer: BackgroundLayer())` produces a valid
    /// stack — base layer present, zero adjustment layers, own UUID.
    func testLayerStackConstructsWithBaseLayer() {
        // Plan 06
    }

    /// The BlendMode raw values are FROZEN (sidecar stability, LAYER-07):
    /// `normal` must be 0x01, and the PS-canonical subset must keep the
    /// Darktable blend.h values (multiply 0x04 … difference 0x17).
    func testBlendModeNormalRawValueIs1() {
        // Plan 06
    }

    /// D-03a: `BackgroundLayer` satisfies the full `Layer` requirement
    /// surface (identity/name/visibility/opacity/blend/enabled/kind) with
    /// its LAYER-01 defaults, and carries NO iopChain/mask (Phase 6 fills).
    func testBackgroundLayerConformsToLayer() {
        // Plan 06
    }
}
