import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The sidecar v2 layer spelling (Plan 06-01 T6; 06-RESEARCH §6) — the FROZEN
// on-disk shape of the adjustment-layer stack. ONE-WAY format lock applies:
// renames after 06-01 ship are migrations; new payload arrives ONLY as
// optional decodeIfPresent fields (the mask payload freezes in 6-3/6-4 the
// same way — v1/v2 documents stay mutually readable).
//
// Spelling (checkpoint 06-01; D-06-01-T6-1):
//
//   layerStack : { "layers" : [SidecarLayerRecord…] }   // bottom-to-top
//   SidecarLayerRecord {
//     id, kind, name, isVisible, enabled, opacity, blendMode,
//     blendOptions,   // OPTIONAL (06-01 additive; dt REVERSE flag bits)
//     chain : [ModuleInstance-spelling…],   // the frozen 02-05 instance
//                                           // shape, paramsHash as a
//                                           // decimal String (lock #2)
//     mask : SidecarMaskSpec?               // { version } — payload 6-3/6-4
//   }
//
// `kind` is the LayerKind string spelling ("adjustment"; the base layer is
// never serialized — LAYER-01 keeps it always-present by construction).
// ─────────────────────────────────────────────────────────────────────────────

/// The persisted mask record SHELL — version only for 06-01 (NDE-3 form
/// version). Drawn forms (6-3) and parametric/raster/combine payloads (6-4)
/// freeze as optional fields on this record, never as renames.
public struct SidecarMaskSpec: Codable, Sendable, Equatable {

    public var version: Int

    public init(version: Int = 1) {
        self.version = version
    }
}

/// One adjustment layer's on-disk record (the frozen 06-01 spelling).
public struct SidecarLayerRecord: Codable, Sendable, Equatable {

    private enum Keys: String, CodingKey {
        case id, kind, name, isVisible, enabled, opacity, blendMode
        case blendOptions, chain, mask
    }

    var id: UUID
    var kind: String
    var name: String
    var isVisible: Bool
    var enabled: Bool
    var opacity: Float
    var blendMode: Int
    /// 06-01 additive optional — decode tolerates its absence (documents
    /// written by the first 06-01 binaries omit nothing; hand-edited or
    /// future-minimized writers may).
    var blendOptions: UInt32
    var chain: [SidecarInstanceRecord]
    var mask: SidecarMaskSpec?

    public init(_ layer: AdjustmentLayer) {
        id = layer.id
        kind = "adjustment"
        name = layer.name
        isVisible = layer.isVisible
        enabled = layer.enabled
        opacity = layer.opacity
        blendMode = layer.blendMode.rawValue
        blendOptions = layer.blendOptions.rawValue
        chain = layer.chain.map(SidecarInstanceRecord.init)
        mask = layer.mask.map { SidecarMaskSpec(version: $0.version) }
    }

    /// The runtime layer (identity + params verbatim — the record IS the
    /// user's edit; nothing is re-encoded or re-hashed).
    var layer: AdjustmentLayer {
        AdjustmentLayer(
            id: id, name: name, isVisible: isVisible,
            opacity: opacity,
            blendMode: BlendMode(rawValue: blendMode) ?? .normal,
            blendOptions: BlendOptions(rawValue: blendOptions),
            enabled: enabled,
            chain: chain.map(\.instance),
            mask: mask.map { MaskSpec(version: $0.version) })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        opacity = try container.decode(Float.self, forKey: .opacity)
        blendMode = try container.decode(Int.self, forKey: .blendMode)
        blendOptions = try container.decodeIfPresent(UInt32.self, forKey: .blendOptions) ?? 0
        chain = try container.decode([SidecarInstanceRecord].self, forKey: .chain)
        mask = try container.decodeIfPresent(SidecarMaskSpec.self, forKey: .mask)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(blendMode, forKey: .blendMode)
        try container.encode(blendOptions, forKey: .blendOptions)
        try container.encode(chain, forKey: .chain)
        try container.encodeIfPresent(mask, forKey: .mask)
    }

    /// Degrade copy (02-06 unknown-op shape, layer dimension): the same
    /// record with `enabled = false` — params kept verbatim, user data
    /// never dropped.
    func degraded() -> SidecarLayerRecord {
        var copy = self
        copy.enabled = false
        return copy
    }
}

/// The persisted layer-stack record — `{layers: […]}` bottom-to-top.
public struct SidecarLayerStackRecord: Codable, Sendable, Equatable {

    public var layers: [SidecarLayerRecord]

    public init(layers: [SidecarLayerRecord]) {
        self.layers = layers
    }

    /// Capture a live stack (adjustment layers bottom-to-top; the base
    /// layer is never serialized — LAYER-01).
    public init(_ stack: LayerStack) {
        self.layers = stack.compositeLayers.map(SidecarLayerRecord.init)
    }

    /// Capture a history snapshot (the same shape both places — one frozen
    /// spelling, D-06-01-T6-1).
    public init(_ snapshot: LayerStackSnapshot) {
        self.layers = snapshot.layers.map { snapshotLayer in
            SidecarLayerRecord(snapshotLayer.makeLayer())
        }
    }

    /// The runtime adjustment layers (bottom-to-top; identity + params
    /// verbatim).
    public var adjustmentLayers: [AdjustmentLayer] {
        layers.map(\.layer)
    }

    /// The history-snapshot projection.
    public var snapshot: LayerStackSnapshot {
        LayerStackSnapshot(layers: layers.map(\.layer).map(LayerStackSnapshot.Layer.init))
    }

    // Codable: synthesized is fine — both members are Codable and the key
    // spelling (`layers`) is the frozen shape.
}
