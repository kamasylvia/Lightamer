import Metal

/// Buffer geometry descriptor for a pipe piece (Darktable
/// `dt_iop_buffer_dsc_t`-analog, reduced to the Phase 1 invariants:
/// FOUND-02 fixes the pipeline to float32 RGBA everywhere, so channels are
/// declared but the pipe asserts 4).
public struct IOPBufferDesc: Sendable {

    public var width: Int
    public var height: Int

    /// Always 4 in the FOUND-02 pipeline (float32 RGBA); declared for the
    /// descriptor's completeness and future non-RGBA aux buffers.
    public var channels: Int

    public init(width: Int = 0, height: Int = 0, channels: Int = 4) {
        self.width = width
        self.height = height
        self.channels = channels
    }
}

/// Per-instance pipe piece state — the port of Darktable's `dt_iop_piece_t`
/// (`pixelpipe_hb.h:161`). One `IOPiece` exists per (module instance × pipe
/// run): `commitParams` writes it, `process` reads it.
///
/// Not `Sendable` (it can carry a uniforms `MTLBuffer`): a piece lives
/// inside its pipe run's isolation region, same contract as the dispatch
/// buffers (see `MetalContext` isolation notes).
public struct IOPiece {

    /// Hash of the committed params — the pipe cache keys module output
    /// identity on this (cache hit = same params + same input). UInt64
    /// (02-02 checkpoint lock #2) so the SAME atom feeds `PipeCacheKey
    /// .upstreamHash` and the 02-05 history identity (D-H4).
    /// **`StableHash` is the only legal generator** (FNV-1a 64 over the
    /// JSON-encoded params; Swift `Hasher` is per-process seeded and banned
    /// across persistence boundaries — 02-RESEARCH Risk #2). Modules compute
    /// it in `commitParams`.
    public var paramsHash: UInt64

    /// Input buffer geometry for this piece.
    public var dscIn: IOPBufferDesc

    /// Output buffer geometry for this piece.
    public var dscOut: IOPBufferDesc

    /// Module-private piece data (Darktable `piece->data`, iop_api.h:188) —
    /// typically a uniforms buffer written by `commitParams`.
    public var data: (any MTLBuffer)?

    public init(
        paramsHash: UInt64 = 0,
        dscIn: IOPBufferDesc = IOPBufferDesc(),
        dscOut: IOPBufferDesc = IOPBufferDesc(),
        data: (any MTLBuffer)? = nil
    ) {
        self.paramsHash = paramsHash
        self.dscIn = dscIn
        self.dscOut = dscOut
        self.data = data
    }
}
