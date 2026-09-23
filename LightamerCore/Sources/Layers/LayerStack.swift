import Foundation

/// The layer stack — the organizing data structure for local adjustments
/// (D-03a skeleton, RESEARCH §5b; mutation API Plan 06-01 T2). Holds the
/// always-present base layer plus zero or more adjustment layers in
/// bottom-to-top composite order.
///
/// Traversal responsibilities by phase:
/// - **Phase 1**: types only — `LayerStack(baseLayer:)` is constructible
///   and `EditorState` owns one per loaded image.
/// - **Phase 2-5**: the pixelpipe processes `baseLayer`'s global iop chain
///   as a flat v50-ordered chain; `adjustmentLayers` are ignored.
/// - **Phase 6** (this phase): `LayerCompositeDriver` composites
///   1 + N + 1 sub-runs — base chain → per-layer sub-run + degenerate
///   blend → terminal segment (colorout→gamma).
///
/// The `any Layer` existentials are intentional: the 6-7 retouch layers
/// (D-06-CONTEXT-4 — stroke-list "chain") are a second concrete kind that
/// must coexist with `AdjustmentLayer` in the same container. Consumers
/// needing the chain surface narrow via `compositeLayers`.
///
/// **Identity (NDE-1):** layers are referenced BY UUID everywhere (history
/// `layerScope`, `PipeCacheKey.layerID`, sidecar records) — never by index,
/// so reorder keeps every anchor valid. `duplicate` mints fresh identities;
/// `reorder`/`remove` preserve the survivors' identities untouched.
public struct LayerStack: Sendable, Identifiable {

    public let id: UUID = UUID()

    /// The base layer (LAYER-01) — always present; carries the global iop
    /// chain. Its `isVisible`/`enabled` gate the whole composite.
    public private(set) var baseLayer: any Layer

    /// Named adjustment layers, bottom-to-top composite order (LAYER-01).
    public private(set) var adjustmentLayers: [any Layer] = []

    public init(baseLayer: any Layer) {
        self.baseLayer = baseLayer
    }

    /// The composite-ready narrowing: adjustment layers capable of carrying
    /// an iop chain, bottom-to-top. Retouch layers (06-07) are skipped by
    /// this narrowing — the composite driver consumes them through the
    /// retouch stroke leg instead of a chain sub-run.
    public var compositeLayers: [AdjustmentLayer] {
        adjustmentLayers.compactMap { $0 as? AdjustmentLayer }
    }
}

// MARK: - Mutation API (Plan 06-01 T2 — the only writers of adjustmentLayers)

public extension LayerStack {

    /// 06-05 helper: swap one adjustment layer in place (by id) — the
    /// live-leg writer of property/mask edits (the LayersPanel's D-H1
    /// live ticks + the commit reinstall). Bottom-to-top order kept.
    mutating func replace(_ layer: AdjustmentLayer) {
        guard let index = adjustmentLayers.firstIndex(where: { $0.id == layer.id }) else {
            return
        }
        adjustmentLayers[index] = layer
    }

    /// 06-07 helper: swap ANY layer (either kind) in place by id — the
    /// live-leg writer for retouch stroke edits (the adjustment twin is
    /// `replace(_:)`). Bottom-to-top order kept.
    mutating func replaceAny(_ layer: any Layer) {
        guard let index = adjustmentLayers.firstIndex(where: { $0.id == layer.id }) else {
            return
        }
        adjustmentLayers[index] = layer
    }

    /// Outcome of a `mergeDown` (data-face only in 6-1; the composite
    /// semantics wire up in 6-5).
    enum MergeDownOutcome: Equatable, Sendable {

        /// Merged into the adjustment layer directly below — `LayerStack`
        /// mutated the lower layer's chain in place.
        case mergedIntoLayer(lowerID: UUID)

        /// The merged layer sat directly ON the base — the combined chain
        /// must be applied to the GLOBAL instance set by the caller
        /// (LayerStack does not own it; the base chain lives in
        /// `EditorState.instances`). Returning the records keeps this a
        /// pure data-plane operation.
        case mergedIntoBase(chain: [ModuleInstance])
    }

    /// Append an adjustment layer on top (the end of `adjustmentLayers`).
    mutating func addAdjustment(_ layer: any Layer) {
        adjustmentLayers.append(layer)
    }

    /// Remove by UUID. The base layer is NOT removable (LAYER-01 invariant
    /// — always present). nil = no such layer.
    @discardableResult
    mutating func remove(id: UUID) -> (any Layer)? {
        guard let index = adjustmentLayers.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return adjustmentLayers.remove(at: index)
    }

    /// Move the layer with `id` to `targetIndex` in the bottom-to-top
    /// ordering (clamped into `0 ... count-1`). Identities untouched —
    /// reorder only changes composite order, which is why every layer chain
    /// output plane survives a reorder in the cache (`PipeCacheKey` carries
    /// the layer's UUID, not its index).
    mutating func reorder(id: UUID, to targetIndex: Int) {
        guard let from = adjustmentLayers.firstIndex(where: { $0.id == id }) else {
            return
        }
        let layer = adjustmentLayers.remove(at: from)
        let clamped = min(max(targetIndex, 0), adjustmentLayers.count)
        adjustmentLayers.insert(layer, at: clamped)
    }

    /// Duplicate the layer with `id`: deep copy with fresh identities (new
    /// layer UUID + new chain-record/stroke UUIDs — `AdjustmentLayer` /
    /// `RetouchLayer` duplicated()), inserted directly ABOVE the original.
    /// nil = no such layer or the entry carries no duplicable surface.
    @discardableResult
    mutating func duplicate(id: UUID) -> (any Layer)? {
        guard let index = adjustmentLayers.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let copy: (any Layer)?
        switch adjustmentLayers[index] {
        case let adjustment as AdjustmentLayer:
            copy = adjustment.duplicated()
        case let retouch as RetouchLayer:
            copy = retouch.duplicated()
        default:
            copy = nil
        }
        guard let copy else { return nil }
        adjustmentLayers.insert(copy, at: index + 1)
        return copy
    }

    /// Merge the layer with `id` DOWN into the layer below it (data face).
    /// The merged chain = lower.chain ⊕ merged.chain, concatenated and
    /// v50-sorted (`(iopOrder, multiPriority, opName)` — the same effective
    /// ordering the pipe walk applies); the merged layer is removed.
    ///
    /// Merging into the BASE (the merged layer is the bottommost
    /// adjustment) returns `.mergedIntoBase(chain:)` for the caller to fold
    /// into the global instance set. nil = no such layer, or nothing below
    /// (impossible — the base always underlies the adjustments).
    @discardableResult
    mutating func mergeDown(id: UUID) -> MergeDownOutcome? {
        guard let index = adjustmentLayers.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let merged = adjustmentLayers.remove(at: index)
        // 06-07: a retouch layer has no chain to fold (its edit IS the
        // stroke list) — the merge is refused and the layer restored
        // intact (the caller surfaces the no-op).
        guard let mergedAdjustment = merged as? AdjustmentLayer else {
            adjustmentLayers.insert(merged, at: index)
            return nil
        }
        let mergedChain = mergedAdjustment.chain
        if index == 0 {
            // Bottommost adjustment — the layer below is the base.
            let combined = (mergedChain).sorted {
                ($0.iopOrder, $0.multiPriority, $0.opName)
                    < ($1.iopOrder, $1.multiPriority, $1.opName)
            }
            return .mergedIntoBase(chain: combined)
        }
        guard let lower = adjustmentLayers[index - 1] as? AdjustmentLayer else {
            // Non-chain layer below (future kinds): keep the data-face
            // contract total by refusing the merge (caller decides).
            adjustmentLayers.insert(merged, at: index)
            return nil
        }
        lower.chain = (lower.chain + mergedChain).sorted {
            ($0.iopOrder, $0.multiPriority, $0.opName)
                < ($1.iopOrder, $1.multiPriority, $1.opName)
        }
        return .mergedIntoLayer(lowerID: lower.id)
    }
}
