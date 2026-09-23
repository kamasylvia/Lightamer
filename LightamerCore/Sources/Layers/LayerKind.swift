/// Base vs adjustment discriminator (LAYER-01, RESEARCH §5b).
public enum LayerKind: Sendable {

    /// The base layer — always present, carries the global iop chain
    /// (the v50-ordered chain Phase 3+ creative iops live in by default).
    case background

    /// A named adjustment layer — per-layer iop parameters + mask + blend
    /// mode (LAYER-02/03/05); processed by the Phase 6 composite.
    case adjustment

    /// A retouch layer (Plan 06-07; IOP-GEO-06; D-06-CONTEXT-4) — its
    /// "iop chain" is the STROKE list (clone/heal/blur/fill), each stroke's
    /// shape acting as the layer's own mask (dt `NO_MASKS` semantics).
    /// Consumed by the composite's retouch sub-run leg.
    case retouch

    // A baked RASTER layer kind stays deferred (the 06-01 slot comment):
    // no consumer in v1; retouch went to its own kind (D-06-07-T1-1).
}
