import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// ChannelMixerRGBModule (Plan 05-03-T2, IOP-COLOR-02) — dt's
// `channelmixerrgb` ("color calibration", v50 28.5, scene-linear RGB),
// transliterated from
//   - src/iop/channelmixerrgb.c (params v3 :88-113 = 160B; commit
//     :3047-3150; _loop_switch :771-1000; _gamut_mapping :648-705;
//     _luma_chroma :706-769)
//   - data/kernels/channelmixer.cl:106-685 (5 path kernels)
//   - src/common/chromatic_adaptation.h + illuminants.h (see
//     ChannelMixerCommon.swift)
// (tree dc58cf0ba1).
//
// COMMIT-PRECOMPUTE ARCHITECTURE (filmicrgb/cb-isomorphic): commit derives
// the illuminant LMS white, the Bradford exponent p, the MIX rows and the
// four per-path matrix pairs → one 64-float uniforms buffer; the kernel is
// pointwise with a runtime adaptation switch (dt unswitches into 5 CL
// kernels for OpenCL; the math per path is identical — one MSL kernel with
// a branch keeps the 5 matrix paths testable without 5× PSO entries).
//
// D65-NATIVE (05-02-DECISIONS D2 applies unchanged): RGB⇄XYZ is
// LabRoundTrip.rec2020ToXYZ/xyzToRec2020 DIRECT (the kernel hardcodes the
// same pair via LabMath.h) — no D50 ICC detour. The middle leg adapts
// toward dt's FIXED D50 LMS anchors (Bradford/CAT16/XYZ target whites
// verbatim); the leg is illuminant-relative, wrapped symmetrically by the
// pipe matrices, so the anchors stay valid in a D65 pipe. `p` keeps dt's
// D50-blue reference 0.818155 verbatim (:3146).
//
// NOT PORTED (05-CONTEXT D-05-CONTEXT-5 — zero lines):
//   - color-checker subtree (_extract_color_checker/run_profile/
//     run_validation, colorchecker.h);
//   - AI WB detection (#ifdef AI_ACTIVATED, DETECT_* illuminants);
//   - _check_if_close_to_daylight (daylight-GUI ergonomics switch — our
//     panel always shows the temperature slider, no consumer).
// DIVERGENCES (recorded):
//   #1 camera illuminant: dt resolves it at process time from RAW EXIF WB
//      coeffs (find_temperature_from_raw_coeffs); commit has no pipe WB
//      access, so `.camera` falls back to the daylight model at the params
//      temperature (D → BB → custom chain, illuminant_to_xy fallthrough
//      semantics). Panel注记.
//   #2 alpha: the CL leg restores w = pix_in.w (followed; CPU leg drags
//      alpha through the math).
//   #3 pow: MSL pow() matches dt powf() incl. NaN-on-negative-base;
//      bradford B-power keeps dt's t.z > 0 guard.
//   #4 normalize sums have no NORM_MIN guard in dt commit_params (:3057 —
//      the guarded form lives only in the GUI spot path :4200); verbatim,
//      panel ranges match dt so exposure is identical.
//
// ROI (L020/L021): pointwise identity — dscIn already carries the entry
// scaling, no re-multiplication by scale anywhere; tileHalo = 0.
// SEED: DISABLED — default params (D illuminant @5003K, identity mix) apply
// a real chromatic adaptation, so no zero-param identity exists
// (colorbalancergb D1 same disposition; dt default_enabled = FALSE :3886).
// ─────────────────────────────────────────────────────────────────────────

public enum ChannelMixerRGBKernel {
    public static let functionName = "channelmixerrgb_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class ChannelMixerRGBModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        public var red: SIMD4<Float>
        public var green: SIMD4<Float>
        public var blue: SIMD4<Float>
        public var saturation: SIMD4<Float>
        public var lightness: SIMD4<Float>
        public var grey: SIMD4<Float>
        public var normalizeR: Bool
        public var normalizeG: Bool
        public var normalizeB: Bool
        public var normalizeSat: Bool
        public var normalizeLight: Bool
        public var normalizeGrey: Bool
        public var illuminant: ChannelMixerIlluminant
        public var illumFluo: ChannelMixerFluo
        public var illumLED: ChannelMixerLED
        public var adaptation: ChannelMixerAdaptation
        public var x: Float
        public var y: Float
        public var temperature: Float
        public var gamut: Float
        public var clip: Bool
        public var version: ChannelMixerVersion

        public init(
            red: SIMD4<Float> = SIMD4(1, 0, 0, 0),
            green: SIMD4<Float> = SIMD4(0, 1, 0, 0),
            blue: SIMD4<Float> = SIMD4(0, 0, 1, 0),
            saturation: SIMD4<Float> = .zero,
            lightness: SIMD4<Float> = .zero,
            grey: SIMD4<Float> = .zero,
            normalizeR: Bool = false, normalizeG: Bool = false,
            normalizeB: Bool = false, normalizeSat: Bool = false,
            normalizeLight: Bool = false, normalizeGrey: Bool = false,
            illuminant: ChannelMixerIlluminant = .d,
            illumFluo: ChannelMixerFluo = .f3,
            illumLED: ChannelMixerLED = .b5,
            adaptation: ChannelMixerAdaptation = .cat16,
            x: Float = 0.333, y: Float = 0.333,
            temperature: Float = 5003, gamut: Float = 1,
            clip: Bool = true, version: ChannelMixerVersion = .v3
        ) {
            self.red = red; self.green = green; self.blue = blue
            self.saturation = saturation; self.lightness = lightness
            self.grey = grey
            self.normalizeR = normalizeR; self.normalizeG = normalizeG
            self.normalizeB = normalizeB; self.normalizeSat = normalizeSat
            self.normalizeLight = normalizeLight
            self.normalizeGrey = normalizeGrey
            self.illuminant = illuminant; self.illumFluo = illumFluo
            self.illumLED = illumLED; self.adaptation = adaptation
            self.x = x; self.y = y
            self.temperature = temperature; self.gamut = gamut
            self.clip = clip; self.version = version
        }
    }

    public static let opName = "channelmixerrgb"

    /// Darktable v50 order slot 28.5 — immediately after colorin (28.0);
    /// the shared 28.5 cluster (diffuse/censorize/negadoctor/blurs/
    /// primaries) tie-breaks via effectiveInstances (02-05 mechanism).
    public static let iopOrder: Float = 28.5

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    /// Uniforms buffer layout (floats, 64):
    ///   0..8    rgbToLMS (pipe RGB → adapted LMS/XYZ forward)
    ///   9..17   mixToXYZ (mixed LMS → XYZ, MIX folded in)
    ///   18..26  xyzToLMS (XYZ → LMS/pipe-RGB after gamut)
    ///   27..35  lmsToXYZ (back to XYZ after luma_chroma)
    ///   36..38  illuminant (LMS/XYZ white, commit-computed)
    ///   39 p  40 gamut (1/g or 0)  41 clip  42 applyGrey  43 version
    ///   44 adaptation  45..47 saturation  48..50 lightness  51..53 grey
    ///   54..63 pad. RGB⇄XYZ pipe matrices are NOT carried — the kernel
    ///   hardcodes LabRoundTrip's pair via LabMath.h (L023 half-contract
    ///   lesson: tests pin the FULL round trip, not the carried half).
    static let uniformsCount = 64

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
            floats.replaceSubrange(0..<9, with: flatten(d.rgbToLMS))
            floats.replaceSubrange(9..<18, with: flatten(d.mixToXYZ))
            floats.replaceSubrange(18..<27, with: flatten(d.xyzToLMS))
            floats.replaceSubrange(27..<36, with: flatten(d.lmsToXYZ))
            floats[36] = Float(d.illuminant.x)
            floats[37] = Float(d.illuminant.y)
            floats[38] = Float(d.illuminant.z)
            floats[39] = Float(d.p)
            floats[40] = Float(d.gamut)
            floats[41] = params.clip ? 1 : 0
            floats[42] = d.applyGrey ? 1 : 0
            floats[43] = Float(params.version.rawValue)
            floats[44] = Float(params.adaptation.rawValue)
            floats[45] = Float(d.saturation.x)
            floats[46] = Float(d.saturation.y)
            floats[47] = Float(d.saturation.z)
            floats[48] = Float(d.lightness.x)
            floats[49] = Float(d.lightness.y)
            floats[50] = Float(d.lightness.z)
            floats[51] = Float(d.grey.x)
            floats[52] = Float(d.grey.y)
            floats[53] = Float(d.grey.z)
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
            functionName: ChannelMixerRGBKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }
}

// MARK: - Commit derivation (channelmixerrgb.c:3047-3150 in Double)

/// The CPU half, factored pure for unit tests and the float64 reference
/// chain (filmicrgb F1 three-party-gate pattern).
public struct ChannelMixerRGBDerived {
    public var rgbToLMS: [[Double]]
    public var mixToXYZ: [[Double]]
    public var xyzToLMS: [[Double]]
    public var lmsToXYZ: [[Double]]
    public var illuminant: SIMD3<Double>
    public var p: Double
    public var gamut: Double
    public var saturation: SIMD3<Double>
    public var lightness: SIMD3<Double>
    public var grey: SIMD3<Double>
    public var applyGrey: Bool
}

extension ChannelMixerRGBModule {

    /// dt `commit_params` (:3055-3150) verbatim in Double. `mix` selects
    /// the per-path matrix pairs of `_loop_switch` (:777-810).
    public static func derive(_ p: Params) -> ChannelMixerRGBDerived {
        let red = SIMD3<Double>(Double(p.red.x), Double(p.red.y), Double(p.red.z))
        let green = SIMD3<Double>(Double(p.green.x), Double(p.green.y), Double(p.green.z))
        let blue = SIMD3<Double>(Double(p.blue.x), Double(p.blue.y), Double(p.blue.z))
        let sat = SIMD3<Double>(Double(p.saturation.x), Double(p.saturation.y), Double(p.saturation.z))
        let light = SIMD3<Double>(Double(p.lightness.x), Double(p.lightness.y), Double(p.lightness.z))
        let greyV = SIMD3<Double>(Double(p.grey.x), Double(p.grey.y), Double(p.grey.z))

        // MIX rows + normalize (commit :3055-3065; no NORM_MIN guard — see
        // header divergence #4).
        let normR = p.normalizeR ? red.x + red.y + red.z : 1.0
        let normG = p.normalizeG ? green.x + green.y + green.z : 1.0
        let normB = p.normalizeB ? blue.x + blue.y + blue.z : 1.0
        let normSat = p.normalizeSat ? (sat.x + sat.y + sat.z) / 3.0 : 0.0
        let normLight = p.normalizeLight ? (light.x + light.y + light.z) / 3.0 : 0.0
        var normGrey = greyV.x + greyV.y + greyV.z
        let applyGrey = p.grey.x != 0 || p.grey.y != 0 || p.grey.z != 0
        if !p.normalizeGrey || normGrey == 0 { normGrey = 1.0 }

        let mix: [[Double]] = [
            [red.x / normR, red.y / normR, red.z / normR],
            [green.x / normG, green.y / normG, green.z / normG],
            [blue.x / normB, blue.y / normB, blue.z / normB],
        ]
        var saturation = SIMD3(-sat.x + normSat, -sat.y + normSat, -sat.z + normSat)
        if p.version == .v1 {
            // v1 saturation algo: R and B coeffs reversed (:3084-3088).
            saturation = SIMD3(-Double(p.saturation.z) + normSat, saturation.y,
                               -Double(p.saturation.x) + normSat)
        }
        let lightness = SIMD3(light.x - normLight, light.y - normLight, light.z - normLight)
        let grey = SIMD3(greyV.x / normGrey, greyV.y / normGrey, greyV.z / normGrey)

        // Illuminant → LMS white (commit :3104-3132). Camera falls back to
        // the daylight model at params temperature (header divergence #1).
        let xy: (x: Double, y: Double)
        if p.illuminant == .camera {
            let (dx, dy) = ChannelMixerMath.cctToXYDaylight(Double(p.temperature))
            if dx != 0, dy != 0 {
                xy = (dx, dy)
            } else {
                let (bx, by) = ChannelMixerMath.cctToXYBlackbody(Double(p.temperature))
                xy = (bx != 0 && by != 0) ? (bx, by)
                    : (Double(p.x), Double(p.y))
            }
        } else {
            xy = ChannelMixerMath.illuminantToXY(
                p.illuminant, fluo: p.illumFluo, led: p.illumLED,
                temperature: Double(p.temperature),
                customX: Double(p.x), customY: Double(p.y))!
        }
        let whiteXYZ = ChannelMixerMath.xyToXYZ(x: xy.x, y: xy.y)
        let illuminant = ChannelMixerMath.xyzToLMS(whiteXYZ, adaptation: p.adaptation)

        // Bradford blue compensation (:3146-3150).
        let pp = pow(0.818155 / illuminant.z, 0.0834)

        let gamut = p.gamut == 0 ? 0.0 : 1.0 / Double(p.gamut)

        // Per-path matrix pairs (_loop_switch :777-810). R2X/X2R are the
        // D65-native pipe matrices (D2 — NOT a D50-detour product).
        let R2X = LabRoundTrip.rec2020ToXYZ
        let X2R = LabRoundTrip.xyzToRec2020
        let B = ChannelMixerMath.xyzToBradfordLMS
        let Bi = ChannelMixerMath.bradfordLMSToXYZ
        let C = ChannelMixerMath.xyzToCAT16LMS
        let Ci = ChannelMixerMath.cat16LMSToXYZ
        let I: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

        let rgbToLMS: [[Double]]
        let mixToXYZ: [[Double]]
        let xyzToLMS: [[Double]]
        let lmsToXYZ: [[Double]]
        switch p.adaptation {
        case .linearBradford, .fullBradford:
            rgbToLMS = ChannelMixerMath.mul(B, R2X)
            mixToXYZ = ChannelMixerMath.mul(Bi, mix)
            xyzToLMS = B
            lmsToXYZ = Bi
        case .cat16:
            rgbToLMS = ChannelMixerMath.mul(C, R2X)
            mixToXYZ = ChannelMixerMath.mul(Ci, mix)
            xyzToLMS = C
            lmsToXYZ = Ci
        case .xyz:
            rgbToLMS = R2X
            mixToXYZ = mix
            xyzToLMS = I
            lmsToXYZ = I
        case .rgb:
            rgbToLMS = I
            mixToXYZ = ChannelMixerMath.mul(R2X, mix)
            xyzToLMS = X2R
            lmsToXYZ = R2X
        }

        return ChannelMixerRGBDerived(
            rgbToLMS: rgbToLMS, mixToXYZ: mixToXYZ,
            xyzToLMS: xyzToLMS, lmsToXYZ: lmsToXYZ,
            illuminant: illuminant, p: pp, gamut: gamut,
            saturation: saturation, lightness: lightness,
            grey: grey, applyGrey: applyGrey
        )
    }
}

private func flatten(_ m: [[Double]]) -> [Float] {
    [Float(m[0][0]), Float(m[0][1]), Float(m[0][2]),
     Float(m[1][0]), Float(m[1][1]), Float(m[1][2]),
     Float(m[2][0]), Float(m[2][1]), Float(m[2][2])]
}
