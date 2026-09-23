import Foundation

/// The concrete adjustment layer (LAYER-01/02, Plan 06-01 T2) — a named
/// stack entry carrying its own iop chain + blend/opacity + (future) mask.
///
/// `@unchecked Sendable`: the same single-owner contract as
/// `BackgroundLayer` — mutable value-type fields owned by one isolation
/// domain at a time (the app's `@MainActor` `EditorState` in production;
/// test scopes in the suites). All stored fields are Sendable value types.
///
/// **Chain shape:** `chain: [ModuleInstance]` — instance RECORDS, the exact
/// same shape as `EditorState`'s global set (the 02-05 frozen spelling).
/// Runtime `ModuleBox` materialization happens per SUB-RUN lifecycle in the
/// `LayerCompositeDriver` (an `any IOPModule` existential cannot be formed
/// — `associatedtype Params`; Phase 1 gotcha). The driver's sub-run is a
/// full `PixelPipe` walk: v50 sort, hash chain, ROI negotiation, cache —
/// the layer chain gets all of it for free (mixed model (c), 06-RESEARCH §1).
///
/// **Identity (NDE-1):** the layer UUID is the anchor history/sidecars/
/// caches reference (`PipeCacheKey.layerID` namespaces every sub-run plane;
/// `HistoryItem.layerScope` scopes history entries; the sidecar layer
/// record persists the UUID). `duplicate` mints a NEW layer UUID AND new
/// chain-record UUIDs (deep copy) — two layers never share identities.
///
/// **Mask:** `mask` is the 6-1 record shell (`MaskSpec`, version only);
/// rasterization + the composite mask leg arrive in 6-3/6-4.
public final class AdjustmentLayer: Layer, @unchecked Sendable {

    public let id: UUID

    public var name: String

    public var isVisible: Bool = true

    public var opacity: Float = 1.0

    public var blendMode: BlendMode = .normal

    /// dt `DEVELOP_BLEND_REVERSE` and future flag bits ride BESIDE the mode
    /// (D-06-CONTEXT-2 — the enum stays a clean slot table).
    public var blendOptions: BlendOptions = []

    public var enabled: Bool = true

    public let kind: LayerKind = .adjustment

    /// The layer's own iop chain (record form; boxes per sub-run).
    public var chain: [ModuleInstance]

    /// Mask record shell (payload freezes 6-3/6-4; nil = no mask = the
    /// constant-1 passthrough of the degenerate triple).
    public var mask: MaskSpec?

    public init(
        id: UUID = UUID(),
        name: String = "Adjustment",
        isVisible: Bool = true,
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal,
        blendOptions: BlendOptions = [],
        enabled: Bool = true,
        chain: [ModuleInstance] = [],
        mask: MaskSpec? = nil
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.opacity = opacity
        self.blendMode = blendMode
        self.blendOptions = blendOptions
        self.enabled = enabled
        self.chain = chain
        self.mask = mask
    }

    /// Deep copy with fresh identity (duplicate semantics, NDE-1): NEW layer
    /// UUID + NEW chain-record UUIDs; params bytes/hashes adopted verbatim
    /// (the byte payload IS the user's edit — identity, not content, is what
    /// duplicates). The copy lands directly above the original via
    /// `LayerStack.duplicate(id:)`.
    public func duplicated(name: String? = nil) -> AdjustmentLayer {
        AdjustmentLayer(
            id: UUID(),
            name: name ?? self.name,
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blendMode,
            blendOptions: blendOptions,
            enabled: enabled,
            chain: chain.map { $0.clonedWithFreshIdentity() },
            mask: mask
        )
    }
}

extension ModuleInstance {

    /// 6-1 duplicate support: clone the record with a FRESH instance UUID;
    /// `paramsData`/`paramsHash` adopted VERBATIM via the persistence
    /// restore init (no re-encode, no re-hash — the D-H4 atom must stay
    /// byte-stable across a duplicate).
    /// 06-05: public — the App layer's「添加模块到层」menu clones global
    /// records into a layer chain through this (Core owns the identity
    /// mint; App never touches the internal identity-restoring init).
    public func clonedWithFreshIdentity() -> ModuleInstance {
        ModuleInstance(
            id: UUID(),
            opName: opName,
            multiPriority: multiPriority,
            multiName: multiName,
            iopOrder: iopOrder,
            version: version,
            enabled: enabled,
            paramsData: paramsData,
            paramsHash: paramsHash
        )
    }
}
