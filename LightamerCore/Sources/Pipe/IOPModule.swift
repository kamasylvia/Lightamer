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
    func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece)

    /// Let the module request the input ROI it needs to produce `roi`
    /// (Darktable `modify_roi_in` — e.g. lens correction samples wider).
    /// Default identity: `input = roi`.
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
