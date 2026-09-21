import Metal

/// The iop module contract (FOUND-03) — the Swift port of Darktable's plugin
/// API (`dt_iop_module_t`, `src/iop/iop_api.h`). Every image-operation module
/// in Lightamer (Phase 3+: exposure, WB, filmic, …) conforms to this protocol;
/// the pixelpipe (`PixelPipe`, Phase 2) drives a v50-ordered chain of them.
///
/// Design locks (RESEARCH §5a + Plan 02-02 checkpoint):
/// - **`Params: Codable & Hashable`** is MANDATORY — the encoded params bytes
///   feed `piece.paramsHash` (via `StableHash`, the ONLY legal generator),
///   which keys both the Phase 2 pipe cache (`PipeCacheKey.upstreamHash`) and
///   the sidecar history identity (D-H4). Structs with all-Codable fields
///   synthesize both for free; never use a class for params.
/// - **Textures are the pipe's currency (02-02 checkpoint lock #1):** `process`
///   reads and writes `MTLTexture` (float32 RGBA linear Rec2020, FOUND-02).
///   Cached planes, `displayTexture`, and every PREVIEW/FULL plane are
///   textures; `MTLBuffer` appears ONLY as `IOPiece.data` uniforms. The
///   Phase 1 buffer signature was a spike artifact (its buffer↔texture
///   staging bridge is deleted).
/// - **`opName`** mirrors Darktable's module `op` string wherever the module
///   corresponds to one (sidecar compatibility); internal-only spike modules
///   may use a custom name (documented at the conformance).
/// - **`iopOrder`** is the module's position in the `V50Order` table — the
///   load-bearing module order (ARCHITECTURE.md Decision 3, ported verbatim
///   from Darktable `iop_order.c:298-415`).
/// - **`defaultColorspace`** is mandatory (iop_api.h:97 makes it REQUIRED in
///   Darktable): the colorspace the module's process step expects its input
///   in. Phase 2's terminal trio (`colorin`/`colorout`/`gamma`) converts
///   around the raw↔RGB boundary.
///
/// Concurrency: `process` is `async throws` and dispatches GPU work through
/// the passed `MetalContext` (D-18 typed errors, D-19 two-layer dispatch).
/// The `associatedtype Params` means `any IOPModule` cannot be formed — the
/// Phase 2 pipe drives modules through the type-erased `ModuleBox<M>`/`ModuleBoxing`
/// surface (checkpoint lock #6), and `ModuleRegistry` (02-04) works with
/// metatypes (`IOPModule.Type`) and generics (RESEARCH §5 gotcha).
public protocol IOPModule {

    /// The module's parameter record — the unit of sidecar persistence
    /// (Phase 2) and pipe-cache identity (Phase 2).
    associatedtype Params: Codable & Hashable

    /// Darktable-style op string (e.g. `"exposure"`); V50Order key.
    static var opName: String { get }

    /// Module position in the v50 order (rawprepare 1.0 → gamma 78.0).
    static var iopOrder: Float { get }

    /// Capability flags (Darktable `IOP_FLAGS_*`, imageop.h:84-110 port).
    static var flags: IOPFlags { get }

    /// The colorspace this module expects its input in (iop_api.h:97 —
    /// REQUIRED in Darktable; mandatory here for the same reason).
    static var defaultColorspace: IOPColorspace { get }

    /// Produce the module's default parameters for a freshly decoded image
    /// (Darktable's `default_params` + `reload_defaults` pair — e.g. exposure
    /// defaults from the RAW's baseline exposure).
    func reloadDefaults(image: DecodedImage) async -> Params

    /// Commit `params` into the per-instance pipe piece (Darktable
    /// `commit_params`): recompute derived piece state — uniform buffers in
    /// `piece.data`, and `piece.paramsHash` (UInt64) which MUST be computed
    /// as `StableHash.hash(ParamsCoding.encode(params))` — `StableHash` is
    /// the only legal generator (D-H4: cache identity == history identity).
    func commitParams(_ params: Params, into piece: inout IOPiece) async

    /// Let the module expand/contract the output ROI it can produce from
    /// `input` (Darktable `modify_roi_out` — e.g. crop/clipping shrink it,
    /// enlargecanvas grows it). Default identity: `roi = input`.
    ///
    /// Phase 4 onward this hook is CONSUMED by the pipe's forward pass
    /// (`PixelPipe.run` pre-computation, dt `get_dimensions` mirror):
    /// `run()` walks it per piece to size every downstream plane. Modules
    /// that resample must override; pointwise modules keep identity.
    func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece)

    /// Let the module request the input ROI it needs to produce `roi`
    /// (Darktable `modify_roi_in` — e.g. lens correction samples wider).
    /// Default identity: `input = roi`.
    ///
    /// Phase 4 onward this hook is CONSUMED by the pipe's backward pass
    /// (`processRec` miss closure, dt `:2085-2096` mirror): the closure
    /// negotiates `roiIn` then recurses upstream with it. dt's contract
    /// applies — `process` may receive an input region different from the
    /// one requested (the pipe clamps to the upstream plane); modules fill
    /// it best-effort.
    func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece)

    /// Process `input` → `output` over the given ROIs on the GPU. Called by
    /// the pixelpipe in v50 order with float32 RGBA linear-Rec2020 TEXTURES
    /// (FOUND-02; 02-02 checkpoint lock #1 — the pipe's currency). `piece`
    /// carries the per-instance state committed by `commitParams` (inout: a
    /// module may stamp derived per-run state, e.g. processed ROI geometry);
    /// `metal` is the app-owned dispatch context (D-19). Same-queue FIFO
    /// ordering makes chained dispatches correct without awaiting completion.
    func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws
}

// MARK: - Tile-driving seam (Plan 03-05-T6 — the D-20 scaffold's first
// consumer; TilingPlan.tiles graduates from placeholder overlap to the
// module-reported halo)

public extension IOPModule {

    /// The HALO, in pixels, this module needs BEYOND its output rect at
    /// the given plane ROI: the tile driver executes the module on the
    /// halo-widened read rect so the tile's output matches whole-plane
    /// execution. 0 = the module never needs tiling (the default — every
    /// Phase 1-3 module except toneequal is untouched).
    ///
    /// The radius semantics are the module's own; toneequal keys its
    /// smoothing radius on `piece.dscIn` (the PIPE-LEVEL plane geometry,
    /// dt's `piece->iwidth`) — deliberately NOT the tile rect, so the
    /// whole-image radius survives tiling (the halo exists precisely to
    /// preserve that semantics).
    func tileHalo(roi: ROI, piece: IOPiece) -> Int { 0 }

    /// The module's AUXILIARY working set in bytes per OUTPUT pixel
    /// (mask planes, downsampled intermediates, blur scratch — the tile
    /// budget input; the input/output planes themselves are the pipe's
    /// accounting). 0 = never tiled.
    func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int { 0 }
}

// MARK: - ROI negotiation defaults (04-01: pass-through-era identity;
// Phase 4's forward/backward passes consume these per piece)

public extension IOPModule {
    /// Default identity: the module produces exactly the input ROI.
    func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// Default identity: the module needs exactly the output ROI as input.
    func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }
}
