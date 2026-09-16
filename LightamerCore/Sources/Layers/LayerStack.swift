import Foundation

/// The layer stack — the organizing data structure for local adjustments
/// (D-03a skeleton, RESEARCH §5b). Holds the always-present base layer plus
/// zero or more adjustment layers.
///
/// Traversal responsibilities by phase:
/// - **Phase 1** (this plan): types only — `LayerStack(baseLayer:)` is
///   constructible and `EditorState` owns one per loaded image.
/// - **Phase 2**: the pixelpipe processes `baseLayer`'s global iop chain as
///   a flat v50-ordered chain (identical to Darktable's single-pipe model);
///   `adjustmentLayers` are ignored.
/// - **Phase 6**: full traversal — per-layer chain processing, mask
///   rasterization, and the composite loop
///   (`for layer in stack: render(layer.chain) → blend onto accumulator
///   with layer.blendMode × layer.mask × layer.opacity`).
///
/// The `any Layer` existentials are intentional (RESEARCH §5b): boxing
/// overhead is irrelevant for the Phase 1 skeleton (no hot traversal);
/// whether Phase 6's composite loop keeps the existential or switches to a
/// concrete `AdjustmentLayer` struct is a Phase 6 perf decision.
///
/// Phase 6 mutation API (`addAdjustment` / `remove` / `reorder` / `merge`)
/// is deliberately NOT declared in Phase 1 — the surface stays minimal
/// until the real semantics (mask refs, layer types, sidecar round-trip)
/// are designed.
public struct LayerStack: Sendable, Identifiable {

    public let id: UUID = UUID()

    /// The base layer (LAYER-01) — always present; carries the global iop
    /// chain. Its `isVisible`/`enabled` gate the whole composite.
    public private(set) var baseLayer: any Layer

    /// Named adjustment layers, bottom-to-top composite order (LAYER-01).
    /// Empty until Phase 6 introduces the adjustment-layer creation UI.
    public private(set) var adjustmentLayers: [any Layer] = []

    public init(baseLayer: any Layer) {
        self.baseLayer = baseLayer
    }
}
