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
/// File-scope alias: the nested `Layer` struct shadows the module-scope
/// `Layer` PROTOCOL inside the snapshot scope — this alias reaches it.
public typealias LayerProtocol = Layer

public struct LayerStackSnapshot: Codable, Sendable, Equatable {

    /// One layer's snapshot (bottom-to-top order preserved by `layers`).
    public struct Layer: Codable, Sendable, Equatable {

        public var id: UUID
        /// 06-07 additive optional — the LayerKind spelling ("adjustment";
        /// "retouch" since 06-07). nil decodes as adjustment (pre-06-07
        /// snapshots carried no other kind).
        public var kind: String?
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
        /// 06-07 additive optional — the retouch stroke list (the retouch
        /// kind's whole edit; chain/mask stay empty/nil for it).
        public var strokes: [RetouchStroke]?

        public init(
            id: UUID, name: String, isVisible: Bool, opacity: Float,
            blendMode: Int, blendOptions: UInt32, enabled: Bool,
            chain: [ModuleInstance], mask: MaskSpec?,
            kind: String? = nil, strokes: [RetouchStroke]? = nil
        ) {
            self.id = id
            self.kind = kind
            self.name = name
            self.isVisible = isVisible
            self.enabled = enabled
            self.opacity = opacity
            self.blendMode = blendMode
            self.blendOptions = blendOptions
            self.chain = chain
            self.mask = mask
            self.strokes = strokes
        }

        /// Capture from a live layer.
        public init(_ layer: AdjustmentLayer) {
            self.init(
                id: layer.id, name: layer.name,
                isVisible: layer.isVisible, opacity: layer.opacity,
                blendMode: layer.blendMode.rawValue,
                blendOptions: layer.blendOptions.rawValue,
                enabled: layer.enabled,
                chain: layer.chain, mask: layer.mask,
                kind: "adjustment")
        }

        /// Capture the retouch kind (D-06-CONTEXT-4).
        public init(_ layer: RetouchLayer) {
            self.init(
                id: layer.id, name: layer.name,
                isVisible: layer.isVisible, opacity: layer.opacity,
                blendMode: layer.blendMode.rawValue,
                blendOptions: layer.blendOptions.rawValue,
                enabled: layer.enabled,
                chain: [], mask: nil,
                kind: "retouch", strokes: layer.strokes)
        }

        /// Capture any non-base layer by kind.
        public init(_ layer: LayerProtocol) {
            switch layer {
            case let retouch as RetouchLayer: self.init(retouch)
            case let adjustment as AdjustmentLayer: self.init(adjustment)
            default: self.init(AdjustmentLayer(
                id: layer.id, name: layer.name, isVisible: layer.isVisible,
                opacity: layer.opacity, enabled: layer.enabled))
            }
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

        /// Kind-dispatched rebuild (retouch snapshots restore as
        /// `RetouchLayer`; pre-06-07 entries stay adjustment).
        public func makeAnyLayer() -> any LayerProtocol {
            guard kind == "retouch" else { return makeLayer() }
            return RetouchLayer(
                id: id, name: name, isVisible: isVisible,
                opacity: opacity, blendMode: BlendMode(rawValue: blendMode) ?? .normal,
                blendOptions: BlendOptions(rawValue: blendOptions),
                enabled: enabled,
                strokes: strokes ?? [])
        }
    }

    /// Non-base layers, bottom-to-top composite order (the base layer is
    /// NOT part of a snapshot — it is always present by LAYER-01).
    public var layers: [Layer]

    public init(layers: [Layer]) {
        self.layers = layers
    }

    /// Capture from a live stack (all non-base kinds since 06-07).
    public init(_ stack: LayerStack) {
        self.layers = stack.adjustmentLayers.map(Layer.init)
    }

    /// Rebuild the layers (bottom-to-top, kind-dispatched).
    public func makeLayers() -> [any LayerProtocol] {
        layers.map { $0.makeAnyLayer() }
    }
}
