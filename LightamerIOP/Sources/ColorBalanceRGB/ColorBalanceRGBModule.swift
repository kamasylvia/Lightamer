import Foundation
import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// ColorBalanceRGBModule (Plan 05-02-T1/T2, IOP-COLOR-01) — dt's
// `colorbalancergb` (v50 41.5, scene-referred RGB color grading with
// global/shadows/midtones/highlights 4-way masks), transliterated from
//   - src/iop/colorbalancergb.c (params v5 :60-110 = 132B; commit
//     :1087-1242; process :579-944; opacity_masks :551-577)
//   - data/kernels/extended.cl:752-1042 (the single-pass CL kernel)
//   - data/kernels/colorspace.h (Yrg/Ych/JzAzBz/UCS helpers)
//   - src/common/darktable_ucs_22_helpers.h (gamut LUT build + lookup)
// (tree dc58cf0ba1).
// COMMIT-PRECOMPUTE ARCHITECTURE (filmicrgb-isomorphic: heavy math on CPU
// at commit, single-pass GPU evaluation): commit_params derives the four
// grading vectors (global/shadows/highlights/midtones in Filmlight grading
// RGB), the 4 opacity weight scalars, the hue rotation, white/midtones
// fulcrums, L_white and the 512-entry gamut LUT → one 576-float uniforms
// buffer (64 scalars + LUT). The kernel is pointwise.
//   - matrix_in = XYZ65→LMS2006 · Rec2020→XYZ(D65) (D65-NATIVE — C-harness
//     cb_verify proof; 05-02-DECISIONS D2). YrgGamut.matrixIn/Out carry
//     filmic V5's CAT16/Bradford D50-detour chain and MUST NOT be reused
//     here (reusing them injects a ~2x neutral shift — harness nailed).
//     Shared constants (CAT16/LMS2006/Kirk grading/Yrg white point) still
//     come from YrgGamut (row refs in code below).
//   - matrix_out = XYZ(D65)→Rec2020 direct (dt :899-901 D50-detour
//     collapses D65-natively — same harness proof).
//   - mask_display checkerboard NOT ported (Phase 6 masking domain).
// NOT re-multiply by scale). tileHalo = 0 (no tiling; dt's ALLOW_TILING
// flag covers only neighborhood-free pointwise execution here).
//
// DIVERGENCES (recorded):
//   #1 alpha: dt's CPU leg processes alpha through the grading math
//      (for_four_channels); the CL leg restores `w = pix_in.w`. We follow
//      the CL leg (the pipe's premultiplied-alpha contract).
//   #2 grey_fulcrum default = 0.1845 (the $DEFAULT annotation,
//      :99); the legacy_params `default_v5` filler array carries 0.0 —
//      migration-only filler, never instantiated as real params.
//   #3 saturation_formula default = .dtUCS (the $DEFAULT `:103` = 1,
//      "darktable UCS (2022)"); JzAzBz is the opt-in legacy formula.
//   #4 fast-math: dt CL uses native_powr (undefined for negative bases);
//      all pow call sites take non-negative args by construction
//      (sanitized Y, fulcrums, |vibrance| exponent); MSL uses pow().
//   #5 white_fulcrum EV ∈ [-16,16] → linear via exp2 at commit (:1164);
//      contrast stored as 1+p.contrast (:1106).
// ─────────────────────────────────────────────────────────────────────────

public enum ColorBalanceRGBKernel {
    public static let functionName = "colorbalancergb"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// dt `dt_iop_colorbalancrgb_saturation_t` (:54-58) — raw values for XMP
/// fidelity. Default = .dtUCS ($DEFAULT 1, :103).
public enum ColorBalanceRGBSaturationFormula: Int, Codable, Hashable, Sendable {
    case jzazbz = 0
    case dtUCS = 1
}

public final class ColorBalanceRGBModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        // v1: 4-way Y (luminance ∈ [-1,1]) / C (chroma ∈ [0,1]) /
        // H (hue ∈ [0,360] conventional degrees, ANGLE_SHIFT -30° folded
        // at commit) + fall-off weights + fulcrums + chroma/saturation.
        public var shadowsY: Float
        public var shadowsC: Float
        public var shadowsH: Float
        public var midtonesY: Float
        public var midtonesC: Float
        public var midtonesH: Float
        public var highlightsY: Float
        public var highlightsC: Float
        public var highlightsH: Float
        public var globalY: Float
        public var globalC: Float
        public var globalH: Float
        public var shadowsWeight: Float
        public var whiteFulcrum: Float
        public var highlightsWeight: Float
        public var chromaShadows: Float
        public var chromaHighlights: Float
        public var chromaGlobal: Float
        public var chromaMidtones: Float
        public var saturationGlobal: Float
        public var saturationHighlights: Float
        public var saturationMidtones: Float
        public var saturationShadows: Float
        public var hueAngle: Float
        // v2: brilliance.
        public var brillianceGlobal: Float
        public var brillianceHighlights: Float
        public var brillianceMidtones: Float
        public var brillianceShadows: Float
        // v3: mask middle-gray fulcrum.
        public var maskGreyFulcrum: Float
        // v4: vibrance / contrast gray fulcrum / contrast.
        public var vibrance: Float
        public var greyFulcrum: Float
        public var contrast: Float
        // v5: saturation formula.
        public var saturationFormula: ColorBalanceRGBSaturationFormula

        public init(
            shadowsY: Float = 0, shadowsC: Float = 0, shadowsH: Float = 0,
            midtonesY: Float = 0, midtonesC: Float = 0, midtonesH: Float = 0,
            highlightsY: Float = 0, highlightsC: Float = 0, highlightsH: Float = 0,
            globalY: Float = 0, globalC: Float = 0, globalH: Float = 0,
            shadowsWeight: Float = 1, whiteFulcrum: Float = 0, highlightsWeight: Float = 1,
            chromaShadows: Float = 0, chromaHighlights: Float = 0,
            chromaGlobal: Float = 0, chromaMidtones: Float = 0,
            saturationGlobal: Float = 0, saturationHighlights: Float = 0,
            saturationMidtones: Float = 0, saturationShadows: Float = 0,
            hueAngle: Float = 0,
            brillianceGlobal: Float = 0, brillianceHighlights: Float = 0,
            brillianceMidtones: Float = 0, brillianceShadows: Float = 0,
            maskGreyFulcrum: Float = 0.1845,
            vibrance: Float = 0, greyFulcrum: Float = 0.1845, contrast: Float = 0,
            saturationFormula: ColorBalanceRGBSaturationFormula = .dtUCS
        ) {
            self.shadowsY = shadowsY
            self.shadowsC = shadowsC
            self.shadowsH = shadowsH
            self.midtonesY = midtonesY
            self.midtonesC = midtonesC
            self.midtonesH = midtonesH
            self.highlightsY = highlightsY
            self.highlightsC = highlightsC
            self.highlightsH = highlightsH
            self.globalY = globalY
            self.globalC = globalC
            self.globalH = globalH
            self.shadowsWeight = shadowsWeight
            self.whiteFulcrum = whiteFulcrum
            self.highlightsWeight = highlightsWeight
            self.chromaShadows = chromaShadows
            self.chromaHighlights = chromaHighlights
            self.chromaGlobal = chromaGlobal
            self.chromaMidtones = chromaMidtones
            self.saturationGlobal = saturationGlobal
            self.saturationHighlights = saturationHighlights
            self.saturationMidtones = saturationMidtones
            self.saturationShadows = saturationShadows
            self.hueAngle = hueAngle
            self.brillianceGlobal = brillianceGlobal
            self.brillianceHighlights = brillianceHighlights
            self.brillianceMidtones = brillianceMidtones
            self.brillianceShadows = brillianceShadows
            self.maskGreyFulcrum = maskGreyFulcrum
            self.vibrance = vibrance
            self.greyFulcrum = greyFulcrum
            self.contrast = contrast
            self.saturationFormula = saturationFormula
        }
    }

    public static let opName = "colorbalancergb"

    /// Darktable v50 order slot 41.5 — scene-referred color manipulation
    /// (`iop_order.c` verbatim; V50Order table).
    public static let iopOrder: Float = 41.5

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    // Piece buffer layout (floats) — 64 uniforms + 512 gamut LUT:
    //   0..3    global (grading RGB offset, w = 0 lane)
    //   4..7    shadows (slope, neutral = 1)
    //   8..11   highlights (slope, neutral = 1)
    //   12..15  midtones (reciprocal slope, neutral = 1)
    //   16..19  chroma (shadows/midtones/highlights + 0 lane)
    //   20..23  saturation (shadows/midtones/highlights + 0 lane)
    //   24..27  brilliance (shadows/midtones/highlights + 0 lane)
    //   28      chroma_global  29 saturation_global  30 brilliance_global
    //   31      vibrance  32 contrast (= 1+p)  33 grey_fulcrum
    //   34..37  hue rotation (cos, -sin, sin, cos)
    //   38      shadows_weight (= 2+2p)  39 highlights_weight
    //   40      midtones_weight (derived)  41 mask_grey_fulcrum (^0.41)
    //   42      white_fulcrum (= exp2)  43 midtones_Y (= 1/(1+p))
    //   44      L_white (UCS lightness of white)  45 saturation formula
    //   46..54  matrix_in (row-major 3x3, ColorBalanceRGBMatrices.matrixIn —
    //           D65-native, NOT YrgGamut.matrixIn; see D2 above)
    //   55..63  matrix_out (row-major 3x3, ColorBalanceRGBMatrices.matrixOut —
    //           XYZ D65 → Rec2020 direct)
    static let uniformsCount = 64
    static let lutCount = 512
    static let gamutLUTOffset = 64

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var lutBuffer: (any MTLBuffer)?
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
        resolvedDevice = resolved

        if pieceBuffer == nil || lutBuffer == nil || committed != params {
            let derived = ColorBalanceRGBCommit.derive(params)
            let lut = ColorBalanceRGBCommit.buildGamutLUT(formula: params.saturationFormula)
            var floats = [Float](repeating: 0, count: Self.uniformsCount)
            floats[0] = derived.global.x
            floats[1] = derived.global.y
            floats[2] = derived.global.z
            floats[3] = derived.global.w
            floats[4] = derived.shadows.x
            floats[5] = derived.shadows.y
            floats[6] = derived.shadows.z
            floats[7] = derived.shadows.w
            floats[8] = derived.highlights.x
            floats[9] = derived.highlights.y
            floats[10] = derived.highlights.z
            floats[11] = derived.highlights.w
            floats[12] = derived.midtones.x
            floats[13] = derived.midtones.y
            floats[14] = derived.midtones.z
            floats[15] = derived.midtones.w
            floats[16] = derived.chroma.x
            floats[17] = derived.chroma.y
            floats[18] = derived.chroma.z
            floats[19] = derived.chroma.w
            floats[20] = derived.saturation.x
            floats[21] = derived.saturation.y
            floats[22] = derived.saturation.z
            floats[23] = derived.saturation.w
            floats[24] = derived.brilliance.x
            floats[25] = derived.brilliance.y
            floats[26] = derived.brilliance.z
            floats[27] = derived.brilliance.w
            floats[28] = derived.chromaGlobal
            floats[29] = derived.saturationGlobal
            floats[30] = derived.brillianceGlobal
            floats[31] = derived.vibrance
            floats[32] = derived.contrast
            floats[33] = derived.greyFulcrum
            floats[34] = derived.hueRotCos
            floats[35] = -derived.hueRotSin
            floats[36] = derived.hueRotSin
            floats[37] = derived.hueRotCos
            floats[38] = derived.shadowsWeight
            floats[39] = derived.highlightsWeight
            floats[40] = derived.midtonesWeight
            floats[41] = derived.maskGreyFulcrum
            floats[42] = derived.whiteFulcrum
            floats[43] = derived.midtonesY
            floats[44] = derived.lWhite
            floats[45] = Float(params.saturationFormula.rawValue)
            floats.replaceSubrange(46..<55, with: YrgGamut.flatten(ColorBalanceRGBMatrices.matrixIn))
            floats.replaceSubrange(55..<64, with: YrgGamut.flatten(ColorBalanceRGBMatrices.matrixOut))
            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: Self.uniformsCount * MemoryLayout<Float>.size,
                    options: .storageModeShared
                )
            }
            if lutBuffer == nil {
                lutBuffer = resolved.makeBuffer(
                    length: Self.lutCount * MemoryLayout<Float>.size,
                    options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                floats.withUnsafeBytes {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: Self.uniformsCount * MemoryLayout<Float>.size
                    )
                }
            }
            if let buffer = lutBuffer {
                lut.withUnsafeBytes {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: Self.lutCount * MemoryLayout<Float>.size
                    )
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }
    // MARK: - ROI (L020/L021 — pointwise identity; dscIn already carries
    // the entry scaling, no re-multiplication by scale anywhere here)

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    // MARK: - Process (single dispatch; mask_display checker NOT ported)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let buffer = piece.data else { return }
        // The gamut LUT rides a SEPARATE buffer object (MSL device pointer
        // arithmetic on a sub-offset is illegal — L018 family; the Soften
        // postmortem: same-buffer offset bindings fault the address
        // space). Commit keeps the canonical copy in `lutBuffer`.
        guard let lut = lutBuffer else { return }
        try await metal.dispatch2DTexture(
            functionName: ColorBalanceRGBKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
            encoder.setBuffer(lut, offset: 0, index: 1)
        }
    }
}

// MARK: - D65-native matrices (05-02-DECISIONS D2)

/// Pipeline RGB ⇄ CIE LMS 2006 D65 WITHOUT dt's D50 ICC detour.
/// dt's work profile is D50-based (matrix_in = RGB→XYZ D50, then CAT16 to
/// D65); Lightamer's working space is linear Rec2020 D65-native
/// (LabRoundTrip.rec2020ToXYZ), so the CAT16/Bradford round trip cancels
/// identically — the C-harness cb_verify proof (out == in to 1e-7 with
/// these matrices; ~2x shift with YrgGamut's CAT chain).
/// Shared constants: YrgGamut.xyzD65toLMS2006 (colorspace.h:453-465, via
/// YrgGamut.swift:50-56) × LabRoundTrip.rec2020ToXYZ.
public enum ColorBalanceRGBMatrices {
    /// RGB → LMS2006 D65 = xyzD65toLMS2006 · rec2020ToXYZ.
    public static let matrixIn: [[Double]] = YrgGamut.matMul(
        YrgGamut.xyzD65toLMS2006, LabRoundTrip.rec2020ToXYZ)

    /// XYZ D65 → RGB = xyzToRec2020 direct (the kernel applies it to
    /// XYZ D65 out of its INTERNAL cb_lms_to_xyz leg
    /// (= YrgGamut.lms2006toXYZD65, colorspace.h:468-476 — folded in MSL,
    /// NOT in the uniforms). The true neutral round trip is therefore
    /// matrixOut · L2X · matrixIn ≈ I (max dev ~4e-9; the parity test pins
    /// this, NOT the naive mo·mi = xyzD65toLMS2006 ≠ I by construction).
    /// Bisect note: folding lms2006toXYZD65 in HERE double-applies
    /// LMS→XYZ — commit readback gave 2.9156606 = (X2R·M)[0][0] instead
    /// of X2R[0][0] = 1.7166478 (kept as regression evidence).
    public static let matrixOut: [[Double]] = LabRoundTrip.xyzToRec2020
}
// MARK: - Commit derivation (colorbalancergb.c:1105-1241 in Double)

/// The CPU half: dt `commit_params` verbatim in Double, factored pure for
/// unit tests and the float64 reference chain. Matrix constants come from
/// YrgGamut (YrgGamut.swift — the filmicrgb F2-F4 chain); the Yrg white
/// point via YrgGamut.yrgWhiteR/G.
public enum ColorBalanceRGBCommit {

    /// GUI degrees → Yrg radians (colorbalancergb.c:48-49 — Filmlight Yrg
    /// puts red at 330°, the GUI shifts by ANGLE_SHIFT -30°).
    public static func conventionalDegToYrgRad(_ deg: Double) -> Double {
        (deg - 30.0) * Double.pi / 180.0
    }


    public struct Derived: Sendable {
        public var global: SIMD4<Float>
        public var shadows: SIMD4<Float>
        public var highlights: SIMD4<Float>
        public var midtones: SIMD4<Float>
        public var chroma: SIMD4<Float>
        public var saturation: SIMD4<Float>
        public var brilliance: SIMD4<Float>
        public var chromaGlobal: Float
        public var saturationGlobal: Float
        public var brillianceGlobal: Float
        public var vibrance: Float
        public var contrast: Float
        public var greyFulcrum: Float
        public var hueRotCos: Float
        public var hueRotSin: Float
        public var shadowsWeight: Float
        public var highlightsWeight: Float
        public var midtonesWeight: Float
        public var maskGreyFulcrum: Float
        public var whiteFulcrum: Float
        public var midtonesY: Float
        public var lWhite: Float
    }

    /// dt `make_Ych` (colorspaces_inline_conversions.h:1136) in Double.
    static func makeYch(y: Double, c: Double, hRad: Double) -> SIMD4<Double> {
        SIMD4<Double>(y, c, cos(hRad), sin(hRad))
    }

    /// dt `Ych_to_gradingRGB` (:1155) in Double: Ych → Yrg → LMS →
    /// Filmlight grading RGB (absolute: denormalized by Y/denom).
    /// Uses YrgGamut's public white point + filmic grading constants
    /// (YrgGamut.swift:106-123 — same Kirk/Filmlight numbers as dt's
    /// colorspace.h:484-507).
    static func ychToGradingRGB(_ ych: SIMD4<Double>) -> SIMD3<Double> {
        let (y, r, g) = YrgGamut.ychToYrg(ych)
        let b = 1.0 - r - g
        // gradingRGB_to_LMS (colorspace.h:484-492, row-major):
        //   lms = M * rgb with M rows (0.95,0.38,0) / (0.05,0.62,0.03) /
        //   (0,0,0.97).
        let lmsX = 0.95 * r + 0.38 * g
        let lmsY = 0.05 * r + 0.62 * g + 0.03 * b
        let lmsZ = 0.97 * b
        let denom = 0.68990272 * lmsX + 0.34832189 * lmsY
        let a = denom == 0 ? 0.0 : y / denom
        return SIMD3<Double>(a * r, a * g, a * b)
    }

    /// dt `commit_params` (:1105-1168) in Double.
    public static func derive(_ p: ColorBalanceRGBModule.Params) -> Derived {
        let norm = ychToGradingRGB(makeYch(y: 1, c: 0, hRad: 0))

        func grading(_ c: Double, _ hDeg: Double) -> SIMD3<Double> {
            ychToGradingRGB(makeYch(y: 1, c: c, hRad: conventionalDegToYrgRad(hDeg)))
        }

        // global: offset (:1136-1140).
        let gg = grading(Double(p.globalC), Double(p.globalH))
        let global = SIMD4<Float>(
            Float((gg.x - norm.x) + norm.x * Double(p.globalY)),
            Float((gg.y - norm.y) + norm.y * Double(p.globalY)),
            Float((gg.z - norm.z) + norm.z * Double(p.globalY)),
            0)

        // shadows: slope (:1143-1148).
        let sg = grading(Double(p.shadowsC), Double(p.shadowsH))
        let shadows = SIMD4<Float>(
            Float(1 + (sg.x - norm.x) + Double(p.shadowsY)),
            Float(1 + (sg.y - norm.y) + Double(p.shadowsY)),
            Float(1 + (sg.z - norm.z) + Double(p.shadowsY)),
            1)
        let shadowsWeight = 2 + Double(p.shadowsWeight) * 2

        // highlights: slope (:1151-1156).
        let hg = grading(Double(p.highlightsC), Double(p.highlightsH))
        let highlights = SIMD4<Float>(
            Float(1 + (hg.x - norm.x) + Double(p.highlightsY)),
            Float(1 + (hg.y - norm.y) + Double(p.highlightsY)),
            Float(1 + (hg.z - norm.z) + Double(p.highlightsY)),
            1)
        let highlightsWeight = 2 + Double(p.highlightsWeight) * 2

        // midtones: reciprocal slope + Y power + fulcrums (:1159-1168).
        let mg = grading(Double(p.midtonesC), Double(p.midtonesH))
        let midtones = SIMD4<Float>(
            Float(1 / (1 + (mg.x - norm.x))),
            Float(1 / (1 + (mg.y - norm.y))),
            Float(1 / (1 + (mg.z - norm.z))),
            1)
        let midtonesY = Float(1 / (1 + Double(p.midtonesY)))
        let whiteFulcrum = Float(exp2(Double(p.whiteFulcrum)))
        let midtonesWeight = Float(
            shadowsWeight * shadowsWeight * highlightsWeight * highlightsWeight
                / (shadowsWeight * shadowsWeight + highlightsWeight * highlightsWeight))
        let maskGreyFulcrum = Float(pow(Double(p.maskGreyFulcrum), 0.4101205819200422))

        // Hue rotation (:1127, :654-657).
        let hueRad = Double(p.hueAngle) * Double.pi / 180.0

        // UCS lightness of white (:652, :1036).
        let lWhite = Float(ColorBalanceRGBMath.yToLStar(Double(whiteFulcrum)))

        return Derived(
            global: global, shadows: shadows, highlights: highlights,
            midtones: midtones,
            chroma: SIMD4<Float>(
                p.chromaShadows, p.chromaMidtones, p.chromaHighlights, 0),
            saturation: SIMD4<Float>(
                p.saturationShadows, p.saturationMidtones, p.saturationHighlights, 0),
            brilliance: SIMD4<Float>(
                p.brillianceShadows, p.brillianceMidtones, p.brillianceHighlights, 0),
            chromaGlobal: p.chromaGlobal,
            saturationGlobal: p.saturationGlobal,
            brillianceGlobal: p.brillianceGlobal,
            vibrance: p.vibrance,
            contrast: 1 + p.contrast,
            greyFulcrum: p.greyFulcrum,
            hueRotCos: Float(cos(hueRad)), hueRotSin: Float(sin(hueRad)),
            shadowsWeight: Float(shadowsWeight),
            highlightsWeight: Float(highlightsWeight),
            midtonesWeight: midtonesWeight,
            maskGreyFulcrum: maskGreyFulcrum,
            whiteFulcrum: whiteFulcrum,
            midtonesY: midtonesY,
            lWhite: lWhite
        )
    }

    /// The 512-entry gamut LUT (commit :1186-1241). JzAzBz leg = the
    /// 92³ gym sampling (:1194-1235); DTUCS leg (the default) =
    /// `dt_UCS_22_build_gamut_LUT` (darktable_ucs_22_helpers.h:18-117).
    /// Cached per formula by the caller (commit rebuilds only when params
    /// change; the build is ~ms for DTUCS, ~100ms for JzAzBz).
    public static func buildGamutLUT(
        formula: ColorBalanceRGBSaturationFormula
    ) -> [Float] {
        switch formula {
        case .jzazbz:
            ColorBalanceRGBMath.buildJzAzBzGamutLUT()
        case .dtUCS:
            ColorBalanceRGBMath.buildUCSGamutLUT()
        }
    }
}

// MARK: - Color-space math (Double mirrors of the dt helpers)

/// Double-precision mirrors of the dt UCS/JzAzBz helpers used by commit
/// (LUT build) and the float64 reference chain. Row refs to dt sources.
public enum ColorBalanceRGBMath {

    public static let lutElem = 512

    // MARK: UCS L_star (colorspaces_inline_conversions.h:1274-1284)

    public static func yToLStar(_ y: Double) -> Double {
        let yHat = pow(y, 0.631651345306265)
        return 2.098883786377 * yHat / (yHat + 1.12426773749357)
    }

    public static func lStarToY(_ lStar: Double) -> Double {
        pow(1.12426773749357 * lStar / (2.098883786377 - lStar), 1.5831518565279648)
    }

    // MARK: XYZ ⇄ xyY (dt_D65_XYZ_to_xyY / dt_xyY_to_XYZ, :246-281)

    /// D65 white xy (D65xyY — colorspaces.h).
    public static let d65xy = (x: 0.31271, y: 0.32902)

    public static func xyzToXyy(_ xyz: SIMD3<Double>) -> SIMD3<Double> {
        let c = SIMD3<Double>(max(xyz.x, 0), max(xyz.y, 0), max(xyz.z, 0))
        let sum = c.x + c.y + c.z
        guard sum > 0 else { return SIMD3<Double>(d65xy.x, d65xy.y, c.y) }
        return SIMD3<Double>(c.x / sum, c.y / sum, c.y)
    }

    public static func xyyToXYZ(_ xyy: SIMD3<Double>) -> SIMD3<Double> {
        guard xyy.y != 0 else { return .zero }
        return SIMD3<Double>(
            xyy.z * xyy.x / xyy.y, xyy.z, xyy.z * (1 - xyy.x - xyy.y) / xyy.y)
    }

    // MARK: xyY → UCS JCH (xyY_to_dt_UCS_UV + dt_UCS_LUV_to_JCH)

    public static func xyyToUCSJCH(_ xyy: SIMD3<Double>, lWhite: Double) -> SIMD3<Double> {
        let xF = (-0.783941002840055, 0.745273540913283, 0.318707282433486)
        let yF = (0.277512987809202, -0.205375866083878, 2.16743692732158)
        let off = (0.153836578598858, -0.165478376301988, 0.291320554395942)
        var uvd = (
            xF.0 * xyy.x + yF.0 * xyy.y + off.0,
            xF.1 * xyy.x + yF.1 * xyy.y + off.1,
            xF.2 * xyy.x + yF.2 * xyy.y + off.2)
        let div = uvd.2 >= 0 ? max(Double.leastNonzeroMagnitude, uvd.2) : min(-Double.leastNonzeroMagnitude, uvd.2)
        uvd.0 /= div
        uvd.1 /= div
        let factors = (1.39656225667, 1.4513954287)
        let halves = (1.49217352929, 1.52488637914)
        let us0 = factors.0 * uvd.0 / (abs(uvd.0) + halves.0)
        let us1 = factors.1 * uvd.1 / (abs(uvd.1) + halves.1)
        let p0 = -1.124983854323892 * us0 - 0.980483721769325 * us1
        let p1 = 1.86323315098672 * us0 + 1.971853092390862 * us1
        let m2 = p0 * p0 + p1 * p1
        let lStar = yToLStar(xyy.z)
        let j = lStar / lWhite
        let c = 15.932993652962535 * pow(lStar, 0.6523997524738018) * pow(m2, 0.6007557017508491) / lWhite
        return SIMD3<Double>(j, c, atan2(p1, p0))
    }

    // MARK: UCS JCH ⇄ xyY inverse (dt_UCS_JCH_to_xyY, :1343-1386)

    public static func ucsJCHToXyy(_ jch: SIMD3<Double>, lWhite: Double) -> SIMD3<Double> {
        let lStar = min(max(jch.x * lWhite, 0), 2.09885)
        let m = lStar != 0
            ? pow(jch.y * lWhite / (15.932993652962535 * pow(lStar, 0.6523997524738018)), 0.8322850678616855)
            : 0
        let up = m * cos(jch.z)
        let vp = m * sin(jch.z)
        var uvStar = (
            -5.037522385190711 * up - 2.504856328185843 * vp,
            4.760029407436461 * up + 2.874012963239247 * vp)
        let factors = (1.39656225667, 1.4513954287)
        let halves = (1.49217352929, 1.52488637914)
        var uv = (
            -halves.0 * uvStar.0 / (abs(uvStar.0) - factors.0),
            -halves.1 * uvStar.1 / (abs(uvStar.1) - factors.1))
        let uF = (0.167171472114775, -0.150959086409163, 0.940254742367256)
        let vF = (0.141299802443708, -0.155185060382272, 1.0)
        let off = (-0.00801531300850582, -0.00843312433578007, -0.0256325967652889)
        var xyD = (
            uF.0 * uv.0 + vF.0 * uv.1 + off.0,
            uF.1 * uv.0 + vF.1 * uv.1 + off.1,
            uF.2 * uv.0 + vF.2 * uv.1 + off.2)
        let div = xyD.2 >= 0 ? max(Double.leastNonzeroMagnitude, xyD.2) : min(-Double.leastNonzeroMagnitude, xyD.2)
        return SIMD3<Double>(xyD.0 / div, xyD.1 / div, lStarToY(lStar))
    }

    // MARK: JCH ⇄ HSB / HCB (dt_UCS_*_to_*, :1389-1425)

    public static func jchToHSB(_ jch: SIMD3<Double>) -> SIMD3<Double> {
        let b = jch.x * (pow(jch.y, 1.33654221029386) + 1)
        return SIMD3<Double>(jch.z, b > 0 ? jch.y / b : 0, b)
    }

    public static func hsbToJCH(_ hsb: SIMD3<Double>) -> SIMD3<Double> {
        let c = hsb.y * hsb.z
        return SIMD3<Double>(hsb.z / (pow(c, 1.33654221029386) + 1), c, hsb.x)
    }

    public static func jchToHCB(_ jch: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(jch.z, jch.y, jch.x * (pow(jch.y, 1.33654221029386) + 1))
    }

    public static func hcbToJCH(_ hcb: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            hcb.z / (pow(hcb.y, 1.33654221029386) + 1), hcb.y, hcb.x)
    }

    // MARK: lookup_gamut + soft_clip (darktable_ucs_22_helpers.h:132-164)

    public static func lookupGamut(_ lut: [Float], hue: Double) -> Double {
        let xTest = Double(lutElem) * (hue + Double.pi) / (2 * Double.pi)
        let xPrev = floor(xTest)
        let xNext = ceil(xTest)
        let xi = Int(xPrev) & (lutElem - 1)
        let xii = Int(xNext) & (lutElem - 1)
        let yPrev = Double(lut[xi])
        return yPrev + ((xi != xii) ? (xTest - xPrev) * (Double(lut[xii]) - yPrev) : 0)
    }

    public static func softClip(_ x: Double, soft: Double, hard: Double) -> Double {
        let norm = hard - soft
        return x > soft ? soft + (1 - exp(-(x - soft) / norm)) * norm : x
    }

    // MARK: XYZ ⇄ JzAzBz (colorspaces_inline_conversions.h:849-975)

    private static let jzM: [[Double]] = [
        [0.41478972, 0.579999, 0.0146480],
        [-0.2015100, 1.1206490, 0.0531008],
        [-0.0166008, 0.264800, 0.6684799],
    ]
    private static let jzA: [[Double]] = [
        [0.5, 0.5, 0.0],
        [3.524000, -4.066708, 0.542708],
        [0.199076, 1.096799, -1.295875],
    ]
    // NOTE: dt stores AI/MI as _trans and applies via tapply (= T^T·in);
    // mul3 is row-major, so these rows are the EFFECTIVE base (= T^T),
    // matching the kernel matrix_dot form (Python bisect 2026-09-21).
    private static let jzAI: [[Double]] = [
        [1.0, 0.1386050432715393, 0.0580473161561189],
        [1.0, -0.1386050432715393, -0.0580473161561189],
        [1.0, -0.0960192420263190, -0.8118918960560390],
    ]
    private static let jzMI: [[Double]] = [
        [1.9242264357876067, -1.0047923125953657, 0.0376514040306180],
        [0.3503167620949991, 0.7264811939316552, -0.0653844229480850],
        [-0.0909828109828475, -0.3127282905230739, 1.5227665613052603],
    ]

    static func mul3(_ m: [[Double]], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
            m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
            m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)
    }

    public static func xyzToJzAzBz(_ xyz: SIMD3<Double>) -> SIMD3<Double> {
        // XYZ -> X'Y'Z.
        let t = SIMD3<Double>(
            1.15 * xyz.x - 0.15 * xyz.z,
            0.66 * xyz.y + 0.34 * xyz.x,
            xyz.z)
        // X'Y'Z -> LMS -> L'M'S' (PQ).
        let lms = mul3(jzM, t)
        var lp = SIMD3<Double>.zero
        for c in 0..<3 {
            let n = pow(max(lms[c] / 10000, 0), 0.159301758)
            lp[c] = pow((0.8359375 + 18.8515625 * n) / (1 + 18.6875 * n), 134.034375)
        }
        var jab = mul3(jzA, lp)
        // Iz -> Jz: (1+d)·Iz/(1+d·Iz) - d0, d = -0.56.
        jab.x = max((1 - 0.56) * jab.x / (1 - 0.56 * jab.x) - 1.6295499532821566e-11, 0)
        return jab
    }

    public static func jzAzBzToXYZ(_ jab: SIMD3<Double>) -> SIMD3<Double> {
        let d = -0.56
        let d0 = 1.6295499532821566e-11
        // Jz -> Iz.
        var iz = jab
        iz.x += d0
        iz.x = max(iz.x / (1 + d - d * iz.x), 0)
        // IzAzBz -> L'M'S'.
        var lms = mul3(jzAI, iz)
        // L'M'S' -> LMS.
        for c in 0..<3 {
            lms[c] = pow(max(lms[c], 0), 1 / 134.034375)
            lms[c] = 10000 * pow(max((0.8359375 - lms[c]) / (18.6875 * lms[c] - 18.8515625), 0), 1 / 0.159301758)
        }
        // LMS -> X'Y'Z -> XYZ_D65.
        let xyz = mul3(jzMI, lms)
        let x = (xyz.x + 0.15 * xyz.z) / 1.15
        // dt: Y = (Y' + (g−1)·X)/g, g−1 = −0.34.
        let y = (xyz.y - 0.34 * x) / 0.66
        return SIMD3<Double>(x, y, xyz.z)
    }

    /// dt `dt_UCS_22_build_gamut_LUT` in Double (the default leg).
    /// input = pipeline RGB → XYZ D65 (Rec2020: LabRoundTrip.rec2020ToXYZ).
    public static func buildUCSGamutLUT() -> [Float] {
        let input = LabRoundTrip.rec2020ToXYZ
        func dot(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
            ColorBalanceRGBMath.mul3(input, rgb)
        }
        let xyzR = dot(SIMD3<Double>(1, 0, 0))
        let xyzG = dot(SIMD3<Double>(0, 1, 0))
        let xyzB = dot(SIMD3<Double>(0, 0, 1))
        let xyR = xyzToXyy(xyzR)
        let xyG = xyzToXyy(xyzG)
        let xyB = xyzToXyy(xyzB)
        let hR = atan2(xyR.y - d65xy.y, xyR.x - d65xy.x)
        let hG = atan2(xyG.y - d65xy.y, xyG.x - d65xy.x)
        let hB = atan2(xyB.y - d65xy.y, xyB.x - d65xy.x)
        func deltaH(_ a: Double, _ b: Double) -> Double {
            var d = a - b
            if d < -Double.pi { d += 2 * Double.pi }
            if d > Double.pi { d -= 2 * Double.pi }
            return d
        }
        func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
        var gamut = [Double](repeating: 0, count: lutElem)
        var sampler = [Double](repeating: 0, count: lutElem)
        for i in 0..<(50 * lutElem) {
            let angle = -Double.pi + Double(i) / Double(50 * lutElem) * 2 * Double.pi
            let tanA = tan(angle)
            let t1 = deltaH(angle, hB) / deltaH(hR, hB)
            let t2 = deltaH(angle, hR) / deltaH(hG, hR)
            let t3 = deltaH(angle, hG) / deltaH(hB, hG)
            var xt = 0.0
            var yt = 0.0
            if t1 == clamp01(t1) {
                // dt branch 1: blue→red edge (t vs xyY_red/xyY_blue).
                let t = (d65xy.y - xyB.y + tanA * (xyB.x - d65xy.x))
                    / (xyR.y - xyB.y + tanA * (xyB.x - xyR.x))
                xt = xyB.x + t * (xyR.x - xyB.x)
                yt = xyB.y + t * (xyR.y - xyB.y)
            } else if t2 == clamp01(t2) {
                // dt branch 2: red→green edge.
                let t = (d65xy.y - xyR.y + tanA * (xyR.x - d65xy.x))
                    / (xyG.y - xyR.y + tanA * (xyR.x - xyG.x))
                xt = xyR.x + t * (xyG.x - xyR.x)
                yt = xyR.y + t * (xyG.y - xyR.y)
            } else if t3 == clamp01(t3) {
                // dt branch 3: green→blue edge.
                let t = (d65xy.y - xyG.y + tanA * (xyG.x - d65xy.x))
                    / (xyB.y - xyG.y + tanA * (xyG.x - xyB.x))
                xt = xyG.x + t * (xyB.x - xyG.x)
                yt = xyG.y + t * (xyB.y - xyG.y)
            }
            // xyY → UCS UV → hue → accumulate M² (colorfulness squared).
            let xF = (-0.783941002840055, 0.745273540913283, 0.318707282433486)
            let yF = (0.277512987809202, -0.205375866083878, 2.16743692732158)
            let off = (0.153836578598858, -0.165478376301988, 0.291320554395942)
            var uvd = (
                xF.0 * xt + yF.0 * yt + off.0,
                xF.1 * xt + yF.1 * yt + off.1,
                xF.2 * xt + yF.2 * yt + off.2)
            let div = uvd.2 >= 0 ? max(Double.leastNonzeroMagnitude, uvd.2) : min(-Double.leastNonzeroMagnitude, uvd.2)
            uvd.0 /= div
            uvd.1 /= div
            let us0 = 1.39656225667 * uvd.0 / (abs(uvd.0) + 1.49217352929)
            let us1 = 1.4513954287 * uvd.1 / (abs(uvd.1) + 1.52488637914)
            let p0 = -1.124983854323892 * us0 - 0.980483721769325 * us1
            let p1 = 1.86323315098672 * us0 + 1.971853092390862 * us1
            let hue = atan2(p1, p0)
            var index = Int((Double(lutElem - 1) * (hue + Double.pi) / (2 * Double.pi)).rounded())
            if index < 0 { index += lutElem }
            if index >= lutElem { index -= lutElem }
            gamut[index] += p0 * p0 + p1 * p1
            sampler[index] += 1
        }
        return (0..<lutElem).map { k in
            Float(gamut[k] / max(1, sampler[k]))
        }
    }

    /// The JzAzBz gamut LUT (commit :1194-1235): 92³ RGB gym →
    /// D65 XYZ → JzAzBz → per-hue max saturation, 5-tap box smoothed.
    /// input = pipeline RGB → XYZ D65 (D65-native LAB_R2X equivalent;
    /// JzAzBz is a D65 space — no CAT/Bradford detour. Python bisect
    /// 2026-09-21: CAT input built the wrong boundary).
    public static func buildJzAzBzGamutLUT() -> [Float] {
        let input = LabRoundTrip.rec2020ToXYZ
        let steps = 92
        var sampler = [Double](repeating: 0, count: lutElem)
        for r in 0..<steps {
            for g in 0..<steps {
                for b in 0..<steps {
                    let rgb = SIMD3<Double>(
                        Double(r) / Double(steps - 1),
                        Double(g) / Double(steps - 1),
                        Double(b) / Double(steps - 1))
                    let xyz = mul3(input, rgb)
                    let jab = xyzToJzAzBz(xyz)
                    let jch0 = jab.x
                    let jch1 = (jab.y * jab.y + jab.z * jab.z).squareRoot()
                    let hue = atan2(jab.z, jab.y)
                    let sat = jch0 > 0 ? jch1 / jch0 : 0
                    var index = Int((Double(lutElem - 1) * (hue + Double.pi) / (2 * Double.pi)).rounded())
                    if index < 0 { index += lutElem }
                    if index >= lutElem { index -= lutElem }
                    sampler[index] = max(sampler[index], sat)
                }
            }
        }
        var lut = [Double](repeating: 0, count: lutElem)
        for k in 2..<(lutElem - 2) {
            lut[k] = (sampler[k - 2] + sampler[k - 1] + sampler[k] + sampler[k + 1] + sampler[k + 2]) / 5
        }
        lut[0] = (sampler[lutElem - 2] + sampler[lutElem - 1] + sampler[0] + sampler[1] + sampler[2]) / 5
        lut[1] = (sampler[lutElem - 1] + sampler[0] + sampler[1] + sampler[2] + sampler[3]) / 5
        lut[lutElem - 1] = (sampler[lutElem - 3] + sampler[lutElem - 2] + sampler[lutElem - 1] + sampler[0] + sampler[1]) / 5
        lut[lutElem - 2] = (sampler[lutElem - 4] + sampler[lutElem - 3] + sampler[lutElem - 2] + sampler[lutElem - 1] + sampler[0]) / 5
        return lut.map { Float($0) }
    }
}
