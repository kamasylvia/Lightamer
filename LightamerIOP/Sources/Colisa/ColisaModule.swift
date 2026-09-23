import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// COLISA — contrast / brightness / saturation (Phase 3 Plan 03-03-T2,
// IOP-TONE-05). The thinnest Lab-domain module and the first consumer of
// the shared `LabRoundTrip` component (T1).
//
// Darktable reference: `src/iop/colisa.c` (tree dc58cf0ba1, 285 lines)
//   - params v1     :43-48   contrast/brightness/saturation ∈ [-1,1], 0
//   - commit_params :179-235  rescales (contrast+1 / brightness×2 /
//                             saturation+1), builds ctable (contrast:
//                             linear ≤ 1, soft sigmoid above — :194-207)
//                             and ltable (brightness gamma — :220-226),
//                             plus the power-law extrapolation fits
//                             (dt_iop_estimate_exp, :211-234)
//   - process       :153-176  L = ctable[L/100] → L = ltable[L/100],
//                             a,b × saturation (unbounded LUT lookups)
//   - kernel        `basic.cl:3553 colisa` (identical semantics)
//
// LAB DOMAIN (Plan 03-03 Goal — RESEARCH Open#3 resolution): dt works in
// IOP_CS_LAB; Lightamer fuses the shared Rec2020→Lab→Rec2020 conversion
// (Common/LabMath.h) around the L/a/b operation in ONE kernel. dt's
// pixelpipe does the equivalent conversion around the module.
//
// RECORDED DEVIATION (plan erratum): the plan text cites
// `gamma = 10^(−brightness)` for the brightness LUT; the actual dt source
// (colisa.c:220) computes `gamma = brightness ≥ 0 ? 1/(1+brightness)
// : (1−brightness)` on the RESCALED brightness (p×2 ∈ [-2,2]). This
// module follows the source verbatim — the plan's formula does not exist
// in the referenced tree.
//
// LUT lookup semantics = dt's NEAREST LUT (`lut[int(x × 0x10000)]`,
// basic.cl common.h:23 CLK_FILTER_NEAREST + colisa.c:168 CPU `(int)` cast)
// implemented as direct device-buffer indexing, with ONE recorded
// deviation: the index ROUNDS to nearest instead of truncating. dt's
// truncation puts neutral pixels EXACTLY on a boundary (a=0 → a_in=0.5 →
// index 32768.0), where the float32 chroma noise flips the index ±1
// systematically; rounding keeps the ≤1-LSB semantic difference while
// making the index stable under noise. LUT VALUES are stored float32 (dt
// quantizes its tables to 1/65536 integer samples through curve_tools —
// a ≤1 LSB difference that removes the quantization cliff from the table
// side; recorded deviation).
//
// The dt golden references are SYNTHESIZED from this documented semantic
// (gen_fixtures.py `refs` mode) with dt pinned via uniform-flat PFM
// probes — LESSONS L017 protocol (dt-cli float export corrupts
// spatially-varying images on this host).
// ─────────────────────────────────────────────────────────────────────────

public enum ColisaKernel {
    public static let functionName = "colisa_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// The contrast/brightness/saturation iop — dt `dt_iop_colisa_params_t`
/// v1 verbatim (colisa.c:43-48).
public final class ColisaModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// ∈ [-1, 1], default 0. > 0: soft S-curve; < 0: linear around 50.
        public var contrast: Float
        /// ∈ [-1, 1], default 0 (rescaled ×2 on commit, colisa.c:186).
        public var brightness: Float
        /// ∈ [-1, 1], default 0 (rescaled +1 on commit — 0 means no
        /// saturation change, NOT b&w).
        public var saturation: Float

        public init(contrast: Float = 0, brightness: Float = 0, saturation: Float = 0) {
            self.contrast = contrast
            self.brightness = brightness
            self.saturation = saturation
        }
    }

    public static let opName = "colisa"
    public static let iopOrder: Float = 47.0
    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    /// LUT resolution (dt `0x10000`, colisa.c:62).
    public static let lutResolution = 0x10000

    private let device: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    // MARK: CPU LUT derivation (dt commit_params :179-235 verbatim)

    /// The contrast curve table (colisa.c:190-208). Exposed for unit tests
    /// and the parity reference; the module packs these into the piece
    /// buffer.
    public static func contrastTable(_ params: Params) -> [Float] {
        let contrast = params.contrast + 1.0 // rescale [-1,1] → [0,2]
        var table = [Float](repeating: 0, count: lutResolution)
        if contrast <= 1.0 {
            // linear curve for contrast below 1 (colisa.c:194)
            for k in 0..<lutResolution {
                table[k] = contrast * (100.0 * Float(k) / Float(lutResolution) - 50.0) + 50.0
            }
        } else {
            // sigmoidal curve for contrast above 1 (colisa.c:199-207)
            let boost: Float = 20.0
            let contrastm1sq = boost * (contrast - 1.0) * (contrast - 1.0)
            let contrastscale = Foundation.sqrt(1.0 + contrastm1sq)
            for k in 0..<lutResolution {
                let kx2m1 = 2.0 * Float(k) / Float(lutResolution) - 1.0
                table[k] = 50.0 * (contrastscale * kx2m1
                    / Foundation.sqrt(1.0 + contrastm1sq * kx2m1 * kx2m1) + 1.0)
            }
        }
        return table
    }

    /// The brightness gamma table (colisa.c:220-226). Deviation note: the
    /// gamma form follows the SOURCE (`1/(1+b)` / `(1−b)` on the rescaled
    /// brightness), not the plan text's `10^(−brightness)`.
    public static func brightnessTable(_ params: Params) -> [Float] {
        let brightness = params.brightness * 2.0 // rescale [-1,1] → [-2,2]
        let gamma: Float = brightness >= 0
            ? 1.0 / (1.0 + brightness)
            : (1.0 - brightness)
        var table = [Float](repeating: 0, count: lutResolution)
        for k in 0..<lutResolution {
            table[k] = 100.0 * Foundation.pow(Float(k) / Float(lutResolution), gamma)
        }
        return table
    }

    /// The saturation multiplier (colisa.c:187): params 0 → exactly 1.
    public static func saturationGain(_ params: Params) -> Float {
        params.saturation + 1.0
    }

    // MARK: Buffer layout (single MTLBuffer, 16-byte-aligned sections)

    static let ctableOffset = 0
    static let ltableOffset = lutResolution * MemoryLayout<Float>.size // 262144, 16-aligned
    static let uniformOffset = ltableOffset + lutResolution * MemoryLayout<Float>.size
    static let uniformLength = 32 // 7 floats + padding, 16-aligned

    /// MSL mirror of the trailing uniform section.
    struct ColisaUniforms {
        var saturation: Float
        var c0: Float, c1: Float, c2: Float
        var l0: Float, l1: Float, l2: Float
        private var _pad: Float = 0

        init(saturation: Float, c: [Float], l: [Float]) {
            self.saturation = saturation
            self.c0 = c[0]; self.c1 = c[1]; self.c2 = c[2]
            self.l0 = l[0]; self.l1 = l[1]; self.l2 = l[2]
        }
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolvedDevice = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }

        let ctable = Self.contrastTable(params)
        let ltable = Self.brightnessTable(params)
        // Extrapolation fits over x = 0.7..1.0 (colisa.c:211-234).
        let xs: [Float] = [0.7, 0.8, 0.9, 1.0]
        // rounded sampling (matches the kernel's rounded lookup + the
        // gen_fixtures lut_index)
        func sample(_ t: [Float], _ x: Float) -> Float {
            t[min(Int(x * Float(Self.lutResolution) + 0.5), Self.lutResolution - 1)]
        }
        let ccoeffs = IOPExpFit.estimate(xs, xs.map { sample(ctable, $0) })
        let lcoeffs = IOPExpFit.estimate(xs, xs.map { sample(ltable, $0) })

        if pieceBuffer == nil || committed != params {
            var uniforms = ColisaUniforms(
                saturation: Self.saturationGain(params), c: ccoeffs, l: lcoeffs
            )
            let length = Self.uniformOffset + Self.uniformLength
            if pieceBuffer == nil {
                pieceBuffer = resolvedDevice.makeBuffer(
                    length: length, options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                ctable.withUnsafeBytes {
                    buffer.contents().advanced(by: Self.ctableOffset)
                        .copyMemory(from: $0.baseAddress!, byteCount: Self.ltableOffset)
                }
                ltable.withUnsafeBytes {
                    buffer.contents().advanced(by: Self.ltableOffset)
                        .copyMemory(from: $0.baseAddress!, byteCount: Self.ltableOffset)
                }
                withUnsafeBytes(of: &uniforms) {
                    buffer.contents().advanced(by: Self.uniformOffset)
                        .copyMemory(from: $0.baseAddress!, byteCount: Self.uniformLength)
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

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
        let buffer = piece.data
        try await metal.dispatch2DTexture(
            functionName: ColisaKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            if let buffer {
                encoder.setBuffer(
                    buffer, offset: Self.ctableOffset, index: 0
                )
                encoder.setBuffer(
                    buffer, offset: Self.ltableOffset, index: 1
                )
                encoder.setBuffer(
                    buffer, offset: Self.uniformOffset, index: 2
                )
            }
        }
    }
}
