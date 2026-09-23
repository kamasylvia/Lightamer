import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// ColorContrastModule (Plan 05-03-T3, IOP-COLOR-09) — dt's `colorcontrast`
// (v50 56.0, Lab a/b linear slope + offset), transliterated from
//   - src/iop/colorcontrast.c (params v2 :36-43 = 20B; process :166-221)
//   - data/kernels/extended.cl `colorcontrast` (same math)
// (tree dc58cf0ba1).
//
// Lab DOMAIN (03-03 Goal pattern): dt works in IOP_CS_LAB; Lightamer fuses
// the shared Rec2020→Lab→Rec2020 conversion (Common/LabMath.h) around the
// a/b operation in ONE kernel. unbound=1 skips the ±128 clamp (:189-201);
// otherwise a/b clamp to [-128,128] (:203-220, clamped_scaling).
// D-05-CONTEXT-1: rgbcurve/rgblevels are NOT part of this delivery.
//
// ROI (L020/L021): pointwise identity — dscIn already carries the entry
// scaling, no re-multiplication by scale anywhere; tileHalo = 0.
// SEED: ENABLED-neutral — defaults (steepness 1, offset 0) ⇒ identity
// (exposure-0EV style).
// ─────────────────────────────────────────────────────────────────────────

public enum ColorContrastKernel {
    public static let functionName = "colorcontrast_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class ColorContrastModule: IOPModule {

    /// dt `dt_iop_colorcontrast_params_t` v2 verbatim
    /// (colorcontrast.c:36-43).
    public struct Params: Codable, Hashable, Sendable {
        public var aSteepness: Float
        public var aOffset: Float
        public var bSteepness: Float
        public var bOffset: Float
        public var unbound: Bool

        public init(
            aSteepness: Float = 1, aOffset: Float = 0,
            bSteepness: Float = 1, bOffset: Float = 0,
            unbound: Bool = true
        ) {
            self.aSteepness = aSteepness; self.aOffset = aOffset
            self.bSteepness = bSteepness; self.bOffset = bOffset
            self.unbound = unbound
        }
    }

    public static let opName = "colorcontrast"

    /// Darktable v50 order slot 56.0 — "adjust chrominance globally"
    /// (V50Order table comment verbatim).
    public static let iopOrder: Float = 56.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    /// Uniforms buffer layout (floats, 8): a_steep/a_off/b_steep/b_off +
    /// unbound + pad.
    static let uniformsCount = 8

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
            floats[0] = params.aSteepness
            floats[1] = params.aOffset
            floats[2] = params.bSteepness
            floats[3] = params.bOffset
            floats[4] = params.unbound ? 1 : 0
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
            functionName: ColorContrastKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    // MARK: - CPU reference (Double mirror for parity tests)

    /// dt process (:189-220) in Double on Lab values.
    public static func reference(
        lab: SIMD3<Double>, params: Params
    ) -> SIMD3<Double> {
        let a = lab.y * Double(params.aSteepness) + Double(params.aOffset)
        let b = lab.z * Double(params.bSteepness) + Double(params.bOffset)
        if params.unbound {
            return SIMD3(lab.x, a, b)
        }
        return SIMD3(
            lab.x,
            min(max(a, -128), 128),
            min(max(b, -128), 128))
    }
}
