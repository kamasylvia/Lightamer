import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// ChannelMixerModule (Plan 05-03-T3, IOP-COLOR-04) — dt's legacy
// `channelmixer` (v50 39.0), transliterated from
//   - src/iop/channelmixer.c (params v2 :81-96 = 88B = 3×7 floats +
//     algorithm int, CHANNEL_SIZE=7 :55-72, introspection v2 :53;
//     commit :499-560; process_rgb/gray/hsl_v1/hsl_v2 :229-420)
//   - data/kernels/extended.cl:140 `channelmixer` (single kernel, 4-mode
//     switch — the MSL port below)
//   - src/common/colorspaces.h:296-352 (rgb2hsl/hsl2rgb verbatim)
// (tree dc58cf0ba1).
//
// dt DEPRECATED this module (deprecated_msg :126 — "please use the color
// calibration module instead"); delivered per IOP-COLOR-04 with this head
// note as the record.
//
// COMMIT-PRECOMPUTE: commit folds the 7-channel params (hue/sat/lightness
// + red/green/blue + gray) into hsl_matrix[9] + rgb_matrix[9] + the
// operation mode (:499-560 verbatim) → 20-float uniforms; the kernel is
// pointwise with a runtime mode switch.
// DIVERGENCES (recorded):
//   #1 alpha: the CPU legs leave alpha untouched (only 3 channels
//      written); the CL leg restores w = pixel.w. Followed: the CL leg.
//   #2 v1 RGB-output clamp is clamp_simd [0,1] while v2/gray/RGB legs use
//      fmax(...,0) (channelmixer.c:266 vs :323/:347/:371 + extended.cl
//      verbatim) — reproduced exactly, mode-dependent.
//   #3 v1 HSL mix clamps ONLY the first product per row
//      (`clamp_simd(in*r)*m0 + in*g*m1 + in*b*m2`, :245-247) while v2
//      clamps the full dot (:296-298) — reproduced exactly.
//
// ROI (L020/L021): pointwise identity — dscIn already carries the entry
// scaling, no re-multiplication by scale anywhere; tileHalo = 0.
// SEED: ENABLED-neutral — defaults (identity RGB + v2, no HSL/gray mix)
// select OPERATION_MODE_RGB with identity matrix ⇒ in == out on
// non-negative content (exposure-0EV style).
// ─────────────────────────────────────────────────────────────────────────

public enum ChannelMixerKernel {
    public static let functionName = "channelmixer_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// dt `_channelmixer_output_t` (channelmixer.c:57-73) — the 7 destination
/// channels (raw values for XMP fidelity).
public enum ChannelMixerOutputChannel: Int, Codable, Hashable, Sendable, CaseIterable {
    case hue = 0
    case saturation = 1
    case lightness = 2
    case red = 3
    case green = 4
    case blue = 5
    case gray = 6
}

/// dt `_channelmixer_algorithm_t` (channelmixer.c:75-78).
public enum ChannelMixerAlgorithm: Int, Codable, Hashable, Sendable {
    case v1 = 0
    case v2 = 1
}

/// dt `_channelmixer_operation_mode_t` (channelmixer.c:100-105).
public enum ChannelMixerOperationMode: Int, Codable, Hashable, Sendable {
    case rgb = 0
    case gray = 1
    case hslV1 = 2
    case hslV2 = 3
}

public final class ChannelMixerModule: IOPModule {

    /// dt `dt_iop_channelmixer_params_t` v2 verbatim: three 7-vectors
    /// (hue/sat/lightness/red/green/blue/gray rows) + algorithm.
    public struct Params: Codable, Hashable, Sendable {
        public var red: [Float]
        public var green: [Float]
        public var blue: [Float]
        public var algorithm: ChannelMixerAlgorithm

        public init(
            red: [Float] = [0, 0, 0, 1, 0, 0, 0],
            green: [Float] = [0, 0, 0, 0, 1, 0, 0],
            blue: [Float] = [0, 0, 0, 0, 0, 1, 0],
            algorithm: ChannelMixerAlgorithm = .v2
        ) {
            precondition(red.count == 7 && green.count == 7 && blue.count == 7)
            self.red = red; self.green = green; self.blue = blue
            self.algorithm = algorithm
        }
    }

    public static let opName = "channelmixer"

    /// Darktable v50 order slot 39.0 — "does exactly the same thing as
    /// colorin, aka RGB to RGB matrix conversion, but coefs are
    /// user-defined" (V50Order table comment verbatim).
    public static let iopOrder: Float = 39.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Uniforms buffer layout (floats, 20):
    ///   0..8 hsl_matrix (row-major 3x3)  9..17 rgb_matrix  18 mode  19 pad.
    static let uniformsCount = 20

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
            let d = Self.derive(params)
            var floats = [Float](repeating: 0, count: Self.uniformsCount)
            floats.replaceSubrange(0..<9, with: d.hslMatrix)
            floats.replaceSubrange(9..<18, with: d.rgbMatrix)
            floats[18] = Float(d.mode.rawValue)
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
            functionName: ChannelMixerKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }
}

// MARK: - Commit derivation (channelmixer.c:499-560 in Double)

public struct ChannelMixerDerived {
    public var hslMatrix: [Float]
    public var rgbMatrix: [Float]
    public var mode: ChannelMixerOperationMode
}

extension ChannelMixerModule {

    /// dt `commit_params` verbatim. HSL mixer rows = hue/sat/lightness
    /// outs; RGB matrix = red/green/blue outs; gray mix folds into every
    /// RGB row when any gray coeff is nonzero.
    public static func derive(_ p: Params) -> ChannelMixerDerived {
        var hsl = [Float](repeating: 0, count: 9)
        var hslMix = false
        // Rows for hue/saturation/lightness outputs (channels 0..2).
        for row in 0..<3 {
            hsl[row * 3] = p.red[row]
            hsl[row * 3 + 1] = p.green[row]
            hsl[row * 3 + 2] = p.blue[row]
            hslMix = hslMix || p.red[row] != 0 || p.green[row] != 0 || p.blue[row] != 0
        }
        // RGB matrix rows for red/green/blue outputs (channels 3..5).
        var rgb = [Float](repeating: 0, count: 9)
        for row in 0..<3 {
            rgb[row * 3] = p.red[row + 3]
            rgb[row * 3 + 1] = p.green[row + 3]
            rgb[row * 3 + 2] = p.blue[row + 3]
        }
        let gray = (p.red[6], p.green[6], p.blue[6])
        let grayMix = gray.0 != 0 || gray.1 != 0 || gray.2 != 0
        if grayMix {
            // mixed_gray[j] = gray.r*rgb_row_j... (dt :536-545: row-major
            // fold — every output row becomes the gray-mixed row).
            var mixed = [Float](repeating: 0, count: 3)
            for j in 0..<3 {
                mixed[j] = gray.0 * rgb[j] + gray.1 * rgb[3 + j] + gray.2 * rgb[6 + j]
            }
            for row in 0..<3 {
                rgb[row * 3] = mixed[0]
                rgb[row * 3 + 1] = mixed[1]
                rgb[row * 3 + 2] = mixed[2]
            }
        }
        let mode: ChannelMixerOperationMode
        if p.algorithm == .v1 {
            mode = .hslV1
        } else if hslMix {
            mode = .hslV2
        } else if grayMix {
            mode = .gray
        } else {
            mode = .rgb
        }
        return ChannelMixerDerived(hslMatrix: hsl, rgbMatrix: rgb, mode: mode)
    }

    // MARK: - CPU reference (Double mirrors for parity tests)

    /// dt `rgb2hsl` (colorspaces.h:296-331) in Double.
    public static func rgbToHSL(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let pmax = max(r, max(g, b))
        let pmin = min(r, min(g, b))
        let delta = pmax - pmin
        var h = 0.0, s = 0.0
        let l = (pmin + pmax) / 2.0
        if delta != 0 {
            s = l < 0.5 ? delta / max(pmax + pmin, 1.52587890625e-05)
                        : delta / max(2.0 - pmax - pmin, 1.52587890625e-05)
            if pmax == r { h = (g - b) / delta }
            else if pmax == g { h = 2.0 + (b - r) / delta }
            else { h = 4.0 + (r - g) / delta }
            h /= 6.0
            if h < 0 { h += 1.0 } else if h > 1 { h -= 1.0 }
        }
        return (h, s, l)
    }

    static func hueToRGB(m1: Double, m2: Double, hue: Double) -> Double {
        if hue < 1.0 { return m1 + (m2 - m1) * hue }
        else if hue < 3.0 { return m2 }
        else { return hue < 4.0 ? m1 + (m2 - m1) * (4.0 - hue) : m1 }
    }

    /// dt `hsl2rgb` (colorspaces.h:334-352) in Double.
    public static func hslToRGB(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
        if s == 0 { return (l, l, l) }
        let m2 = l < 0.5 ? l * (1.0 + s) : l + s - l * s
        let m1 = 2.0 * l - m2
        let hh = h * 6.0
        return (
            hueToRGB(m1: m1, m2: m2, hue: hh < 4.0 ? hh + 2.0 : hh - 4.0),
            hueToRGB(m1: m1, m2: m2, hue: hh),
            hueToRGB(m1: m1, m2: m2, hue: hh > 2.0 ? hh - 2.0 : hh + 4.0)
        )
    }

    static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// Full per-pixel CPU reference (all 4 modes) in Double — the T3/T4
    /// reference chain.
    public static func reference(
        _ rgb: SIMD3<Double>, derived d: ChannelMixerDerived
    ) -> SIMD3<Double> {
        switch d.mode {
        case .rgb:
            let m = d.rgbMatrix.map(Double.init)
            return SIMD3(
                max(m[0] * rgb.x + m[1] * rgb.y + m[2] * rgb.z, 0),
                max(m[3] * rgb.x + m[4] * rgb.y + m[5] * rgb.z, 0),
                max(m[6] * rgb.x + m[7] * rgb.y + m[8] * rgb.z, 0))
        case .gray:
            let m = d.rgbMatrix.map(Double.init)
            let g = max(m[0] * rgb.x + m[1] * rgb.y + m[2] * rgb.z, 0)
            return SIMD3(g, g, g)
        case .hslV1:
            let m = d.hslMatrix.map(Double.init)
            // Divergence #3: v1 clamps only the first product per row.
            let hmix = clamp01(rgb.x * Double(m[0])) + rgb.y * Double(m[1]) + rgb.z * Double(m[2])
            let smix = clamp01(rgb.x * Double(m[3])) + rgb.y * Double(m[4]) + rgb.z * Double(m[5])
            let lmix = clamp01(rgb.x * Double(m[6])) + rgb.y * Double(m[7]) + rgb.z * Double(m[8])
            var r = rgb.x, g = rgb.y, b = rgb.z
            if hmix != 0 || smix != 0 || lmix != 0 {
                var (h, s, l) = rgbToHSL(r, g, b)
                if hmix != 0 { h = hmix }
                if smix != 0 { s = smix }
                if lmix != 0 { l = lmix }
                (r, g, b) = hslToRGB(h: h, s: s, l: l)
            }
            let n = d.rgbMatrix.map(Double.init)
            return SIMD3(
                clamp01(n[0] * r + n[1] * g + n[2] * b),
                clamp01(n[3] * r + n[4] * g + n[5] * b),
                clamp01(n[6] * r + n[7] * g + n[8] * b))
        case .hslV2:
            let m = d.hslMatrix.map(Double.init)
            let hmix = clamp01(m[0] * rgb.x + m[1] * rgb.y + m[2] * rgb.z)
            let smix = clamp01(m[3] * rgb.x + m[4] * rgb.y + m[5] * rgb.z)
            let lmix = clamp01(m[6] * rgb.x + m[7] * rgb.y + m[8] * rgb.z)
            var r = rgb.x, g = rgb.y, b = rgb.z
            if hmix != 0 || smix != 0 || lmix != 0 {
                r = clamp01(r); g = clamp01(g); b = clamp01(b)
                var hsl = [0.0, 0.0, 0.0]
                (hsl[0], hsl[1], hsl[2]) = rgbToHSL(r, g, b)
                let mix = [hmix, smix, lmix]
                for i in 0..<3 { if mix[i] != 0 { hsl[i] = mix[i] } }
                (r, g, b) = hslToRGB(h: hsl[0], s: hsl[1], l: hsl[2])
            }
            let n = d.rgbMatrix.map(Double.init)
            return SIMD3(
                max(n[0] * r + n[1] * g + n[2] * b, 0),
                max(n[3] * r + n[4] * g + n[5] * b, 0),
                max(n[6] * r + n[7] * g + n[8] * b, 0))
        }
    }
}
