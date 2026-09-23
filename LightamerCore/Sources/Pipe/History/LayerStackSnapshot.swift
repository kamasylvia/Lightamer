import Foundation

/// A lightweight whole-layer-stack snapshot (Plan 06-01 T6) — the payload
/// of `HistoryItem.stackSnapshot` for STRUCTURE edits (layer add/remove/
/// reorder/duplicate/mergeDown/property changes). Value data only: the
/// chain is param BYTES (`ModuleInstance` records, `paramsData` verbatim —
/// no boxes, no uniforms buffers) and the mask is the record shell — no
/// textures. Restoring a snapshot rebuilds the stack and the driver
/// re-materializes boxes from the records.
///
/// Runtime surface note: this type's Codable path is the IN-MEMORY shape
/// (chain `paramsHash` would encode as a JSON number); the SIDECAR never
/// uses it directly — `SidecarHistoryItemRecord` /
/// `SidecarLayerStackRecord` project it through the decimal-String hash
/// spelling (the ONE-WAY format lock, checkpoint 02-06-01 lock #2).
public struct LayerStackSnapshot: Codable, Sendable, Equatable {

    /// One layer's snapshot (bottom-to-top order preserved by `layers`).
    public struct Layer: Codable, Sendable, Equatable {

        public var id: UUID
        public var name: String
        public var isVisible: Bool
        public var enabled: Bool
        public var opacity: Float
        /// The frozen BlendMode raw value (the value space never renumbers
        /// — D-06-CONTEXT-2) + the option flag bits beside the mode.
        public var blendMode: Int
        public var blendOptions: UInt32
        /// The layer's chain records (param bytes + D-H4 hashes verbatim).
        public var chain: [ModuleInstance]
        /// Mask record shell (payload freezes 6-3/6-4 as optional fields).
        public var mask: MaskSpec?

        public init(
            id: UUID, name: String, isVisible: Bool, opacity: Float,
            blendMode: Int, blendOptions: UInt32, enabled: Bool,
            chain: [ModuleInstance], mask: MaskSpec?
        ) {
            self.id = id
            self.name = name
            self.isVisible = isVisible
            self.enabled = enabled
            self.opacity = opacity
            self.blendMode = blendMode
            self.blendOptions = blendOptions
            self.chain = chain
            self.mask = mask
        }

        /// Capture from a live layer.
        public init(_ layer: AdjustmentLayer) {
            self.init(
                id: layer.id, name: layer.name,
                isVisible: layer.isVisible, opacity: layer.opacity,
                blendMode: layer.blendMode.rawValue,
                blendOptions: layer.blendOptions.rawValue,
                enabled: layer.enabled,
                chain: layer.chain, mask: layer.mask)
        }

        /// Rebuild a live layer (identity + params verbatim).
        public func makeLayer() -> AdjustmentLayer {
            AdjustmentLayer(
                id: id, name: name, isVisible: isVisible,
                opacity: opacity, blendMode: BlendMode(rawValue: blendMode) ?? .normal,
                blendOptions: BlendOptions(rawValue: blendOptions),
                enabled: enabled,
                chain: chain, mask: mask)
        }
    }

    /// Adjustment layers, bottom-to-top composite order (the base layer is
    /// NOT part of a snapshot — it is always present by LAYER-01).
    public var layers: [Layer]

    public init(layers: [Layer]) {
        self.layers = layers
    }

    /// Capture from a live stack.
    public init(_ stack: LayerStack) {
        self.layers = stack.compositeLayers.map(Layer.init)
    }

    /// Rebuild the adjustment layers (bottom-to-top).
    public func makeLayers() -> [AdjustmentLayer] {
        layers.map { $0.makeLayer() }
    }
}
