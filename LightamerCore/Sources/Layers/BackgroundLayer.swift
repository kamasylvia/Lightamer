import Foundation

/// The concrete base layer (LAYER-01) — the always-present bottom of every
/// `LayerStack`, carrying the global iop chain from Phase 2 on.
///
/// `@unchecked Sendable`: the protocol requires `Sendable`, but the layer
/// fields are mutable value types (name/visibility/opacity/blend/enable).
/// Contract: instances are owned by one isolation domain at a time — in
/// Phase 1 that is the app's `@MainActor` `EditorState` (D-03b); the Phase 6
/// editing model keeps single-owner mutation (the same documented ownership
/// contract as `MetalContext.ComputeEncoderSession`). All stored fields are
/// Sendable value types, so no data race is possible on the fields
/// themselves; the unchecked conformance covers only the class wrapper.
public final class BackgroundLayer: Layer, @unchecked Sendable {

    public let id: UUID = UUID()

    public var name: String = "Background"

    public var isVisible: Bool = true

    public var opacity: Float = 1.0

    public var blendMode: BlendMode = .normal

    public var enabled: Bool = true

    public let kind: LayerKind = .background

    public init() {}
}
