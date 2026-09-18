/// Base vs adjustment discriminator (LAYER-01, RESEARCH §5b).
public enum LayerKind: Sendable {

    /// The base layer — always present, carries the global iop chain
    /// (the v50-ordered chain Phase 3+ creative iops live in by default).
    case background

    /// A named adjustment layer — per-layer iop parameters + mask + blend
    /// mode (LAYER-02/03/05); processed by the Phase 6 composite.
    case adjustment

    // Phase 6 may add: case raster (baked raster layer for retouch/clone).
}
