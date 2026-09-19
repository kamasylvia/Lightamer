import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// EXPOSURE — the first real tone iop (Phase 3 Plan 03-01, IOP-TONE-01) and
// the golden-parity tracer: the simplest possible math that proves the whole
// dt-cli golden chain (fixture → XMP-pinned darktable-cli reference →
// Lightamer pipe → per-pixel compare).
//
// Darktable reference: `src/iop/exposure.c` (tree dc58cf0ba1, 2026-08-02)
//   - params v7      :66-78
//   - scale math     :479-521  (`white = exp2(−exposure)`, exposure2white)
//   - process        :552-577  (`out = (in − black) × scale`)
//   - kernel         `data/kernels/basic.cl:240-251` (uniform: black, scale)
//
// INTENTIONAL DIVERGENCES from Darktable (RESEARCH §1.1 + Risk #6 — all
// recorded here as the plan's Must-have):
// 1. **Default 0 EV, not dt's 0.7 EV.** dt's `reload_defaults` seeds the
//    first exposure instance of a scene-referred RAW with exposure=0.7,
//    black=−0.00024414, compensate_exposure_bias=TRUE (`exposure.c:346-370`).
//    Lightamer's pipe input is CIRAW's *displayed domain* — the baseline
//    exposure is already baked into the decode (02-RESEARCH §3.1) — so a
//    0.7EV seed would double-apply it. Defaults here are the NEUTRAL
//    identity: exposure=0, black=0.
// 2. **Deflicker NOT implemented.** dt's EXPOSURE_MODE_DEFLICKER derives the
//    exposure from a histogram percentile (time-lapse defense) — histogram
//    statistics are out of Phase 3 scope. The `mode` PARAM BIT is preserved
//    in `Params` (v7 layout stays dt-compatible for sidecar semantics), but
//    a non-manual mode falls back to manual math (documented in
//    `commitParams`).
// 3. **`processed_maximum` NOT tracked.** dt multiplies
//    `pipe->dsc.processed_maximum[3]` by the scale (`exposure.c:545,577`) —
//    a pipe-level state Lightamer does not carry. Zero effect on single-
//    module pixel output; auto-exposure-style features (Phase 8+) would need
//    it (RESEARCH Risk #6).
// 4. **exif exposure-bias compensation NOT applied.** dt's
//    `commit_params` folds `_get_exposure_bias` into the scale
//    (`exposure.c:614-660`) when `compensate_exposure_bias` is TRUE. The
//    parameter round-trips in `Params`, but the bias source (RAW EXIF
//    metadata plumbing, RAW-06) is not wired — treated as FALSE. Golden
//    fixtures always pin `compensateExposureBias=false` so both sides agree.
// ─────────────────────────────────────────────────────────────────────────

public enum ExposureKernel {

    /// MSL function name of the exposure kernel (`ExposureKernels.metal`).
    public static let functionName = "exposure_apply"

    /// The LightamerIOP framework bundle — the `registerDefaultLibrary(in:)`
    /// anchor (the IOP metallib lives in the FRAMEWORK bundle, never
    /// `Bundle.main`).
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// The exposure iop — `dt_iop_exposure_params_t` v7 mirror. See the file
/// header for the reference line numbers and the four recorded divergences.
public final class ExposureModule: IOPModule {

    /// Exposure algorithm mode (dt `dt_iop_exposure_mode_t`).
    /// The bit exists for dt-params-layout parity; DEFLICKER falls back to
    /// manual (divergence #2).
    public enum Mode: Int, Codable, Hashable, Sendable {
        case manual = 0
        case deflicker = 1
    }

    /// dt v7 params, field-for-field (`exposure.c:66-78`):
    /// `mode(int) black(f) exposure(f) deflicker_percentile(f)
    ///  deflicker_target_level(f) compensate_exposure_bias(int)
    ///  compensate_hilite_pres(int)`.
    public struct Params: Codable, Hashable, Sendable {
        public var mode: Mode
        /// Black-level correction ∈ [−1, 1], default 0.
        public var black: Float
        /// Exposure shift in EV ∈ [−18, 18], default 0 (divergence #1).
        public var exposure: Float
        /// Deflicker histogram percentile ∈ [0, 100], default 50.
        public var deflickerPercentile: Float
        /// Deflicker target level ∈ [−18, 18] EV, default −4.
        public var deflickerTargetLevel: Float
        /// Compensate the RAW's EXIF exposure bias (divergence #4: reserved,
        /// treated FALSE until the RAW-06 metadata plumbing lands).
        public var compensateExposureBias: Bool
        /// Compensate highlight preservation (dt default TRUE).
        public var compensateHilitePres: Bool

        public init(
            mode: Mode = .manual,
            black: Float = 0.0,
            exposure: Float = 0.0,
            deflickerPercentile: Float = 50.0,
            deflickerTargetLevel: Float = -4.0,
            compensateExposureBias: Bool = false,
            compensateHilitePres: Bool = true
        ) {
            self.mode = mode
            self.black = black
            self.exposure = exposure
            self.deflickerPercentile = deflickerPercentile
            self.deflickerTargetLevel = deflickerTargetLevel
            self.compensateExposureBias = compensateExposureBias
            self.compensateHilitePres = compensateHilitePres
        }
    }

    public static let opName = "exposure"

    /// Darktable v50 order slot 21.0 (`iop_order.c` verbatim; V50Order table).
    public static let iopOrder: Float = 21.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling, .allowFastPipe]

    public static let defaultColorspace: IOPColorspace = .RGB

    /// Device for the uniforms `MTLBuffer` allocation in `commitParams`
    /// (TestGain precedent; production default nil → lazy system default).
    private let device: (any MTLDevice)?

    /// Cached uniforms buffer, reallocated when (black, scale) change.
    private var uniformsBuffer: (any MTLBuffer)?
    private var uniformsBlack: Float = .nan
    private var uniformsScale: Float = .nan

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    /// Neutral identity defaults (divergence #1 — see file header).
    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// dt `commit_params` math (`exposure.c:479-521`): `white = exp2(−EV)`,
    /// `scale = 1 / (white − black)`. Zero EV / zero black ⇒ white=1,
    /// scale=1 → the identity passthrough the pipe cache relies on.
    ///
    /// `piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))`
    /// (L013: ParamsCoding.sortedKeys is the ONLY legal hash payload).
    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        // Deflicker falls back to manual (divergence #2): the histogram
        // percentile pass is Phase 3 out-of-scope; params bit preserved.
        let ev = params.exposure
        let black = max(-1.0, min(1.0, params.black)) // dt clamps black ∈ [−1,1]
        let white = exp2(-ev)
        let scale = 1.0 / (white - black)

        guard let resolvedDevice = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        if uniformsScale != scale || uniformsBlack != black || uniformsBuffer == nil {
            var uniforms = ExposureUniforms(black: black, scale: scale)
            uniformsBuffer = resolvedDevice.makeBuffer(
                bytes: &uniforms,
                length: MemoryLayout<ExposureUniforms>.stride,
                options: .storageModeShared
            )
            uniformsBlack = black
            uniformsScale = scale
        }
        piece.data = uniformsBuffer
    }

    /// Identity ROI: exposure does not resample.
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// Identity ROI: exposure needs exactly the output ROI as input.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        let uniforms = piece.data // local copy — closures cannot capture inout
        try await metal.dispatch2DTexture(
            functionName: ExposureKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            if let uniforms {
                encoder.setBuffer(uniforms, offset: 0, index: 0)
            }
        }
    }
}

/// Swift mirror of the MSL `ExposureUniforms` struct — 16-byte stride
/// (two floats + padding) so the buffer length satisfies
/// constant-addressable alignment. Mirrors `basic.cl:240-251`'s two
/// uniforms (`black`, `scale`).
struct ExposureUniforms {
    var black: Float
    var scale: Float
    private var _pad: (Float, Float) = (0, 0)

    init(black: Float, scale: Float) {
        self.black = black
        self.scale = scale
    }
}
