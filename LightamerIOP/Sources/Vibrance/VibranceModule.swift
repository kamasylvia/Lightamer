import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// VibranceModule (Plan 05-04-T1, IOP-COLOR-03) — dt's `vibrance` (v50 58.0,
// Lab single-parameter pointwise), transliterated from
//   - src/iop/vibrance.c (params v2 :37-40 = 1 float = 4B; commit :167-173
//     passthrough; process :100-128; process_cl :132-146 — CL leg receives
//     amount*0.01, extended.cl `vibrance` same math)
// (tree dc58cf0ba1).
//
// dt DEPRECATED this module (deprecated_msg — "please use the vibrance
// slider in the color balance rgb module instead"). Delivered as an
// independent module per D-05-CONTEXT-8: the two formulas are DIFFERENT
// FAMILIES — this one is Lab-domain
//   sw = hypot(a,b)/256; out = {L·(1−0.25·amt·sw), a·(1+amt·sw),
//                                b·(1+amt·sw)}
// (vibrance.c:117-120) while colorbalancergb's slider is Ych-domain
//   vib·(1−chroma^|vib|)  (extended.cl:807).
//
// LAB DOMAIN (03-03 Goal pattern): fused Rec2020→Lab→Rec2020 via
// Common/LabMath.h in ONE kernel.
//
// DIVERGENCE (recorded): default amount = 0 (neutral identity), not dt's
// $DEFAULT 25 — the editing seed must be cache-neutral (exposure-0EV
// style, sharpen D2 same disposition); the dt default lives in the panel
// reset row, not in Params().
//
// ROI (L020/L021): pointwise identity — dscIn already carries the entry
// scaling, no re-multiplication by scale anywhere; tileHalo = 0.
// SEED: ENABLED-neutral — Params() (amount 0) ⇒ ls=ss=1 ⇒ in == out
// (exposure-0EV style).
// ─────────────────────────────────────────────────────────────────────────

public enum VibranceKernel {
    public static let functionName = "vibrance_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class VibranceModule: IOPModule {

    /// dt `dt_iop_vibrance_params_t` v2 verbatim (vibrance.c:37-40).
    public struct Params: Codable, Hashable, Sendable {
        /// dt `amount` ∈ [0, 100] ($DEFAULT 25; neutral 0 here).
        public var amount: Float

        public init(amount: Float = 0) {
            self.amount = amount
        }
    }

    public static let opName = "vibrance"

    /// Darktable v50 order slot 58.0.
    public static let iopOrder: Float = 58.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    /// Uniforms buffer layout (floats, 4): amount01 (= amount·0.01,
    /// vibrance.c:111/:142) + pad.
    static let uniformsCount = 4

    private let device: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        if pieceBuffer == nil || committed != params {
            var floats = [Float](repeating: 0, count: Self.uniformsCount)
            floats[0] = params.amount * 0.01
            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: Self.uniformsCount * MemoryLayout<Float>.size,
                    options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                floats.withUnsafeBytes {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!,
                        byteCount: Self.uniformsCount * MemoryLayout<Float>.size
                    )
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    // MARK: - ROI (L020/L021 — pointwise identity)

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    // MARK: - Process (single dispatch)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let buffer = piece.data else { return }
        try await metal.dispatch2DTexture(
            functionName: VibranceKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    // MARK: - CPU reference (Double mirror for parity tests)

    /// dt process (:111-127) in Double on Lab values. `amount01` is the
    /// committed uniform (params.amount·0.01).
    public static func reference(
        lab: SIMD3<Double>, amount01: Double
    ) -> SIMD3<Double> {
        let sw = (lab.y * lab.y + lab.z * lab.z).squareRoot() / 256.0
        let ls = 1.0 - amount01 * sw * 0.25
        let ss = 1.0 + amount01 * sw
        return SIMD3(lab.x * ls, lab.y * ss, lab.z * ss)
    }
}
