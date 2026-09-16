import Foundation

/// A single layer in the layer stack (D-03a skeleton — RESEARCH §5b).
///
/// Lightamer uses the **Capture One model** (REQUIREMENTS LAYER-01..07):
/// a base layer carrying the global iop chain plus named adjustment layers,
/// each with its own iop parameters + mask + blend mode. This skeleton puts
/// the TYPES in place from Phase 1 so the Phase 2 pixelpipe is layer-aware
/// from its first line (L005: bolting layers onto a finished pipe is a
/// rewrite). Phase 1 defines identity/state only; the pipeline semantics
/// arrive later:
///
/// - **Phase 2** — the pixelpipe traverses `LayerStack.baseLayer` (a flat
///   v50-ordered chain, identical to Darktable's single-pipe model).
/// - **Phase 6** — multi-layer composite + mask rasterization
///   (`blendop` Metal kernel, ported from Darktable `blendop.cl`).
///
/// Deliberately NOT declared in Phase 1 (RESEARCH §5b gotcha — an
/// `iopChain` property would require `any IOPModule`, whose associatedtype
/// makes the existential unusable; the per-layer chain container is
/// designed in Phase 6):
/// - `var mask: MaskRef?` — LAYER-03 per-layer mask (Phase 6)
/// - `var iopChain: …` — base carries the global chain, adjustment layers
///   carry per-layer chains (Phase 6)
public protocol Layer: Sendable, Identifiable {

    /// Stable layer identity (NDE-1): history entries and sidecars reference
    /// layers by UUID, never by array index, so reorder/refactor keeps
    /// history valid.
    var id: UUID { get }

    /// Display name ("Background", user-named adjustment layers).
    var name: String { get set }

    /// Visibility toggle (LAYER-04). Invisible layers are skipped by the
    /// Phase 6 composite; the base layer's visibility gates the whole image.
    var isVisible: Bool { get set }

    /// Layer opacity in [0, 1] (LAYER-04); composite weight in Phase 6.
    var opacity: Float { get set }

    /// PS-style blend mode (LAYER-05); consumed by the Phase 6 blendop.
    var blendMode: BlendMode { get set }

    /// Enable flag — distinct from `isVisible`: disabled layers are removed
    /// from processing entirely (like Darktable's per-module enable),
    /// invisible ones are still processed but skipped at composite.
    var enabled: Bool { get set }

    /// Base vs adjustment discriminator (LAYER-01).
    var kind: LayerKind { get }
}
