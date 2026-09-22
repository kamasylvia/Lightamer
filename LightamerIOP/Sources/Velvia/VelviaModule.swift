import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// VelviaModule (Plan 05-04-T1, IOP-COLOR-07) — dt's `velvia` (v50 57.0,
// RGB linear-domain pointwise), transliterated from
//   - src/iop/velvia.c (params v2 = strength/bias = 8B; commit passthrough;
//     process :162-197; process_cl :201-213 — CL leg receives
//     strength/100, extended.cl `velvia` same math)
// (tree dc58cf0ba1).
//
// CLAMP IS THE FORMULA (not a guard): dt's per-channel output is
//   out[c] = clamp(chan[c] + saturation·(chan[c] − 0.5·othersum[c]), 0, 1)
// (:190-193) where othersum = the other two channels (rotate1+rotate2,
// RGB only — alpha is FOR loop-excluded via for_each_channel over
// DT_PIXEL_SIMD_CHANNELS=3 and restored from w). Values > 1 (HDR
// scene-referred content) are TRUNCATED by design — reproduced exactly;
// the parity suite nails the behavior so a future "fix" cannot silently
// break dt parity.
//
// SCENE-REFERRED LIMITATION (recorded): dt's own description marks this
// display-referred-leaning ("resaturate giving more weight to blacks,
// whites and low-saturation pixels"); the clamp discards >1 highlights.
// Kept verbatim for parity; users needing HDR-safe saturation use
// colorbalancergb.
//
// DIVERGENCE (recorded): default strength = 0 (neutral identity), not
// dt's $DEFAULT 25 — the editing seed must be cache-neutral
// (exposure-0EV style, sharpen D2 same disposition).
//
// ROI (L020/L021): pointwise identity — dscIn already carries the entry
// scaling, no re-multiplication by scale anywhere; tileHalo = 0.
// SEED: ENABLED-neutral — Params() (strength 0) ⇒ saturation 0 ⇒
// in == out (exposure-0EV style).
// ─────────────────────────────────────────────────────────────────────────

public enum VelviaKernel {
    public static let functionName = "velvia_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class VelviaModule: IOPModule {

    /// dt `dt_iop_velvia_params_t` v2 verbatim (velvia.c:41-45).
    public struct Params: Codable, Hashable, Sendable {
        /// dt `strength` ∈ [0, 100] ($DEFAULT 25; neutral 0 here).
        public var strength: Float
        /// dt `bias` ∈ [0, 1] ($DEFAULT 1.0, "mid-tones bias").
        public var bias: Float

        public init(strength: Float = 0, bias: Float = 1.0) {
            self.strength = strength
            self.bias = bias
        }
    }

    public static let opName = "velvia"

    /// Darktable v50 order slot 57.0.
    public static let iopOrder: Float = 57.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Uniforms buffer layout (floats, 4): strength01 (= strength/100,
    /// velvia.c:213/:158) + bias + pad.
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
            floats[0] = params.strength / 100.0
            floats[1] = params.bias
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
            functionName: VelviaKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }


    // MARK: - CPU reference (Double mirror for parity tests)

    /// dt process (:165-194) in Double on linear RGB. `strength01` is the
    /// committed uniform (params.strength/100).
    public static func reference(
        rgb: SIMD3<Double>, strength01: Double, bias: Double
    ) -> SIMD3<Double> {
        // dt velvia.c:160 — strength <= 0 short-circuits to an unclamped
        // copy (mirrors the kernel guard; HDR >1 passes through).
        if strength01 <= 0 {
            return rgb
        }
        let pmax = max(rgb.x, max(rgb.y, rgb.z))
        let pmin = min(rgb.x, min(rgb.y, rgb.z))
        let plum = (pmax + pmin) / 2.0
        let psat: Double
        if plum <= 0.5 {
            psat = (pmax - pmin) / (1e-5 + pmax + pmin)
        } else {
            psat = (pmax - pmin) / (1e-5 + max(0.0, 2.0 - pmax - pmin))
        }
        let pweight = min(max(
            ((1.0 - 1.5 * psat) + (1.0 + abs(plum - 0.5) * 2.0) * (1.0 - bias))
                / (1.0 + (1.0 - bias)), 0.0), 1.0)
        let saturation = strength01 * pweight
        // othersum[c] = sum of the OTHER two channels (rotate1+rotate2).
        let r = min(max(rgb.x + saturation * (rgb.x - 0.5 * (rgb.y + rgb.z)), 0.0), 1.0)
        let g = min(max(rgb.y + saturation * (rgb.y - 0.5 * (rgb.z + rgb.x)), 0.0), 1.0)
        let b = min(max(rgb.z + saturation * (rgb.z - 0.5 * (rgb.x + rgb.y)), 0.0), 1.0)
        return SIMD3(r, g, b)
    }
}
