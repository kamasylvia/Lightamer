import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// ContrastModule (Plan M2-5-1 T4; KD-5) — the Alcedo `contrast` catalog op,
// 0.3.0 semantics: an S curve on OkLab lightness of scene-linear AP1
// around the 18%-grey pivot, chroma scaled so HUE NEVER DRIFTS — a
// different family from colisa's display-referred RGB scaling (colisa
// stays its own D6 module). Params key照抄 scalar_operator_model.hpp
// ContrastTraits ("contrast", default 0, ±100; the +15 new-image default
// is defaultLook's business, not Params').
//
// Pixel math (Alcedo ApplyOkLabContrast, primary_grade.metal behavior 2 —
// read-only semantics, GPL code NOT copied):
//   slope = 2^(contrast/100); shape = tanh(3·log2(L/cbrt 0.18)/2.5);
//   gain = 2^((slope−1)·2.5·shape/3); chroma = √slope·min(gain, 1);
//   (L, a, b) ← (L·gain, a·chroma, b·chroma).
// Contrast 0 commits the early-exit flag (Alcedo skips `value == 0` too)
// — identity at pixel tolerance 0.
// ─────────────────────────────────────────────────────────────────────────

public enum ContrastKernel {
    /// MSL function name (`Contrast.metal`).
    public static let functionName = "grade_contrast"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class ContrastModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// Alcedo ContrastTraits: default 0, clamp ±100.
        public var contrast: Float

        public init(contrast: Float = 0) {
            self.contrast = contrast
        }
    }

    public static let contrastRange: ClosedRange<Float> = (-100.0...100.0)

    public static let opName = "contrast"

    /// LIGHTAMER V50Order row 41.6 (after colorbalancergb 41.5).
    public static let iopOrder: Float = 41.6

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Alcedo ScalarOperatorModel.SetValue clamp.
    public static func clamped(_ params: Params) -> Params {
        Params(contrast: min(max(params.contrast, contrastRange.lowerBound), contrastRange.upperBound))
    }

    private let device: (any MTLDevice)?
    private var uniformsBuffer: (any MTLBuffer)?
    private var committedFlag: Float = -1

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        let clamped = Self.clamped(params)
        // Uniforms: [flag, contrast, pad, pad] — 16 bytes ×4.
        var floats: [Float] = [0, clamped.contrast, 0, 0]
        if clamped.contrast != 0 {
            floats[0] = 1
        }
        if uniformsBuffer == nil || committedFlag != floats[0] {
            let resolved = device ?? MTLCreateSystemDefaultDevice()
            uniformsBuffer = resolved?.makeBuffer(
                length: 4 * MemoryLayout<Float>.stride, options: .storageModeShared)
            committedFlag = floats[0]
        }
        guard let buffer = uniformsBuffer else {
            piece.data = nil
            return
        }
        floats.withUnsafeBytes {
            buffer.contents().copyMemory(
                from: $0.baseAddress!, byteCount: 4 * MemoryLayout<Float>.stride)
        }
        piece.data = buffer
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
            functionName: ContrastKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    // MARK: - CPU reference (KD-8 — the golden test's Float64 mirror)

    /// The OkLab AP1 matrices (Alcedo LinearAp1ToOkLab / OkLabToLinearAp1
    /// — the standard OkLab AP1 constants).
    public static func linearAp1ToOkLab(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let l = 0.6341104672 * c.x + 0.3489495087 * c.y + 0.0169400240 * c.z
        let m = 0.2754060131 * c.x + 0.6327713632 * c.y + 0.0918226237 * c.z
        let s = 0.1056775254 * c.x + 0.1971481306 * c.y + 0.6971743440 * c.z
        let l_ = cbrt(l)
        let m_ = cbrt(m)
        let s_ = cbrt(s)
        return SIMD3(
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    public static func okLabToLinearAp1(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_
        return SIMD3(
            2.0693822907 * l - 1.1736821545 * m + 0.1042998638 * s,
            -0.8917480677 * l + 2.1537429245 * m - 0.2619948569 * s,
            -0.0615064732 * l - 0.4311325686 * m + 1.4926390418 * s)
    }

    /// The Float64 reference: ACEScc decode → OkLab S curve → encode.
    /// Contrast 0 short-circuits (the kernel's flag path).
    public static func reference(acescc: SIMD3<Double>, contrast: Double) -> SIMD3<Double> {
        if contrast == 0 { return acescc }
        let lin = SIMD3(
            Cat02WBMath.acesccDecode(acescc.x),
            Cat02WBMath.acesccDecode(acescc.y),
            Cat02WBMath.acesccDecode(acescc.z))
        var lab = linearAp1ToOkLab(lin)
        let slope = exp2(contrast * 0.01)
        let pivot = 0.5646216  // cbrt(0.18)
        let width = 2.5
        let shape = lab.x > 0 ? tanh(3.0 * log2(lab.x / pivot) / width) : -1.0
        let gain = exp2((slope - 1.0) * width * shape / 3.0)
        let chromaScale = (slope).squareRoot() * min(gain, 1.0)
        lab = SIMD3(lab.x * gain, lab.y * chromaScale, lab.z * chromaScale)
        let adapted = okLabToLinearAp1(lab)
        return SIMD3(
            Cat02WBMath.acesccEncode(adapted.x),
            Cat02WBMath.acesccEncode(adapted.y),
            Cat02WBMath.acesccEncode(adapted.z))
    }
}
