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

/// The persisted mask record — the 06-01 shell + the 06-03 DRAWN payload +
/// the 06-04 PARAMETRIC/RASTER payloads (optional additive fields,
/// non-destructive decodeIfPresent: documents written before 06-03/06-04
/// decode with nil for the absent payloads). The mask identity hash is
/// DERIVED (`MaskSpec.stableHash()`), never persisted; the RASTER
/// reference's own `maskHash` (PNG integrity) IS persisted as a
/// decimal String (the UInt64 lock #2).
public struct SidecarMaskSpec: Codable, Sendable, Equatable {

    public var version: Int

    /// 06-03 additive optional — the drawn forms + group shell
    /// (frozen spelling: `MaskSpec`'s drawn payload verbatim).
    public var drawn: DrawnMaskSpec?

    /// 06-04 additive optional — the parametric (blendif) payload
    /// (frozen spelling: `ParametricMask` verbatim).
    public var parametric: ParametricMask?

    /// 06-04 additive optional — the raster PNG reference (pixels never
    /// enter this JSON, 06-RESEARCH §6).
    public var raster: RasterMaskRef?

    public init(
        version: Int = 1,
        drawn: DrawnMaskSpec? = nil,
        parametric: ParametricMask? = nil,
        raster: RasterMaskRef? = nil
    ) {
        self.version = version
        self.drawn = drawn
        self.parametric = parametric
        self.raster = raster
    }

    /// Capture from the runtime record (identity verbatim).
    public init(_ spec: MaskSpec) {
        version = spec.version
        drawn = spec.drawn
        parametric = spec.parametric
        raster = spec.raster
    }

    /// Restore the runtime record.
    var spec: MaskSpec {
        MaskSpec(version: version, drawn: drawn, parametric: parametric, raster: raster)
    }
}

/// One adjustment layer's on-disk record (the frozen 06-01 spelling; the
/// 06-07 retouch kind arrives as an OPTIONAL additive field + the `kind`
/// spelling "retouch" — v1/v2 documents stay mutually readable).
public struct SidecarLayerRecord: Codable, Sendable, Equatable {

    private enum Keys: String, CodingKey {
        case id, kind, name, isVisible, enabled, opacity, blendMode
        case blendOptions, chain, mask
        case strokes // 06-07 additive optional (retouch kind payload)
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
    /// 06-07 additive optional — the retouch stroke list (D-06-CONTEXT-4;
    /// frozen spelling: `RetouchStroke` verbatim, shape = the 06-03
    /// `MaskForm` spellings). nil for adjustment records.
    var strokes: [RetouchStroke]?

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
        mask = layer.mask.map(SidecarMaskSpec.init)
        strokes = nil
    }

    /// The retouch record (D-06-07-T1-2 spelling freeze): `chain`/`mask`
    /// stay empty/nil (retouch carries NO iop chain and is dt NO_MASKS);
    /// the strokes ARE the edit.
    public init(_ layer: RetouchLayer) {
        id = layer.id
        kind = "retouch"
        name = layer.name
        isVisible = layer.isVisible
        enabled = layer.enabled
        opacity = layer.opacity
        blendMode = layer.blendMode.rawValue
        blendOptions = layer.blendOptions.rawValue
        chain = []
        mask = nil
        strokes = layer.strokes
    }

    /// Capture any non-base layer by kind (the single write face used by
    /// `SidecarLayerStackRecord`).
    public static func record(for layer: any Layer) -> SidecarLayerRecord {
        switch layer {
        case let retouch as RetouchLayer: return SidecarLayerRecord(retouch)
        case let adjustment as AdjustmentLayer: return SidecarLayerRecord(adjustment)
        default:
            // Unknown future kind: keep identity + container state, drop
            // nothing the reader can't decode (chain/mask/strokes empty).
            var record = SidecarLayerRecord(AdjustmentLayer(
                id: layer.id, name: layer.name, isVisible: layer.isVisible,
                opacity: layer.opacity, enabled: layer.enabled))
            record.kind = "adjustment"
            record.enabled = false
            return record
        }
    }

    /// The runtime layer (identity + params verbatim — the record IS the
    /// user's edit; nothing is re-encoded or re-hashed). Kind-dispatched:
    /// "retouch" rebuilds a `RetouchLayer`, anything else an
    /// `AdjustmentLayer` (the 06-01 documents' only kind).
    var layer: AdjustmentLayer {
        AdjustmentLayer(
            id: id, name: name, isVisible: isVisible,
            opacity: opacity,
            blendMode: BlendMode(rawValue: blendMode) ?? .normal,
            blendOptions: BlendOptions(rawValue: blendOptions),
            enabled: enabled,
            chain: chain.map(\.instance),
            mask: mask.map(\.spec))
    }

    var anyLayer: any Layer {
        guard kind == "retouch" else { return layer }
        return RetouchLayer(
            id: id, name: name, isVisible: isVisible,
            opacity: opacity,
            blendMode: BlendMode(rawValue: blendMode) ?? .normal,
            blendOptions: BlendOptions(rawValue: blendOptions),
            enabled: enabled,
            strokes: strokes ?? [])
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
        // 06-07 additive: absent on pre-06-07 documents.
        strokes = try container.decodeIfPresent([RetouchStroke].self, forKey: .strokes)
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
        try container.encodeIfPresent(strokes, forKey: .strokes)
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

    /// Capture a live stack (all non-base layers bottom-to-top —
    /// adjustment AND retouch kinds since 06-07; the base layer is never
    /// serialized — LAYER-01).
    public init(_ stack: LayerStack) {
        self.layers = stack.adjustmentLayers.map(SidecarLayerRecord.record(for:))
    }

    /// Capture a history snapshot (the same shape both places — one frozen
    /// spelling, D-06-01-T6-1).
    public init(_ snapshot: LayerStackSnapshot) {
        self.layers = snapshot.layers.map { snapshotLayer in
            SidecarLayerRecord.record(for: snapshotLayer.makeAnyLayer())
        }
    }

    /// The runtime layers (bottom-to-top; identity + params verbatim —
    /// adjustment and retouch kinds alike since 06-07).
    public var runtimeLayers: [any Layer] {
        layers.map(\.anyLayer)
    }

    /// The adjustment layers only (06-01 spelling; retouch records decode
    /// as empty-chain adjustment layers here — callers wanting the retouch
    /// kind use `runtimeLayers`).
    public var adjustmentLayers: [AdjustmentLayer] {
        layers.map(\.layer)
    }

    /// The history-snapshot projection (kind-dispatched — retouch records
    /// rebuild their RetouchLayer; 06-07).
    public var snapshot: LayerStackSnapshot {
        LayerStackSnapshot(layers: layers.map(\.anyLayer).map(LayerStackSnapshot.Layer.init))
    }

    // Codable: synthesized is fine — both members are Codable and the key
    // spelling (`layers`) is the frozen shape.
}
