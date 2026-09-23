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
    /// ROI 帧约定（L020/L021）：本 run 平面像素（PixelPipe.run 按 bufInROI
    /// 逐级 stamp，已含 entry 缩放）——模块 ROI 钩子禁止再 ×scale。
    public var dscIn: IOPBufferDesc

    /// Output buffer geometry for this piece.
    public var dscOut: IOPBufferDesc

    /// Entry scale of this run (dt `piece->iscale`, `pixelpipe_hb.c:505`
    /// mirror) — the run-level constant stamped ONCE by `PixelPipe.run`
    /// alongside dscIn, from the same entry-ROI source. Radius compensation
    /// for denoise consumers = `roi.scale ÷ iscale` (dt
    /// `fmin(roi.scale,2)/fmax(iscale,1)` 同构；soften.c:141 先行同式).
    /// TILE 驱动不得改写（tile 内 piece.iscale == 整幅执行值）.
    /// `commitParams` never touches it (default 1.0 = full-res identity).
    public var iscale: Float

    /// The pipe this run executes on (dt `piece->pipe->type` mirror —
    /// Plan 05-06): the preview-downgrade lever for denoise iops (nlmeans
    /// clamps its search radius and decimates offsets on PREVIEW/THUMBNAIL,
    /// denoiseprofile.c:1626-1631 / nlmeans.c:367-368 同构). Stamped ONCE
    /// by `PixelPipe.run` alongside iscale — a run-level constant the TILE
    /// drivers must not rewrite. Default `.full` (tests / direct drives).
    public var pipeType: PipeResolution

    /// 04-01 negotiation stamps (dt `processed_roi_in/out`,
    /// `pixelpipe_hb.c:2095-2096` mirror): the exact ROIs this piece's
    /// execution consumed. Stamped by `processRec` (post-negotiation) —
    /// modules and probes read them; `commitParams` never touches them.
    public var processedROIIn: ROI
    public var processedROIOut: ROI

    /// Module-private piece data (Darktable `piece->data`, iop_api.h:188) —
    /// typically a uniforms buffer written by `commitParams`.
    public var data: (any MTLBuffer)?

    public init(
        paramsHash: UInt64 = 0,
        dscIn: IOPBufferDesc = IOPBufferDesc(),
        dscOut: IOPBufferDesc = IOPBufferDesc(),
        iscale: Float = 1.0,
        pipeType: PipeResolution = .full,
        processedROIIn: ROI = ROI(),
        processedROIOut: ROI = ROI(),
        data: (any MTLBuffer)? = nil
    ) {
        self.paramsHash = paramsHash
        self.dscIn = dscIn
        self.dscOut = dscOut
        self.iscale = iscale
        self.pipeType = pipeType
        self.processedROIIn = processedROIIn
        self.processedROIOut = processedROIOut
        self.data = data
    }
}
