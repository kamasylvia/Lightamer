import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// FilmicRGBModule (Plan 03-06-T2..T5, IOP-FILM-01) — the scene-referred
// filmic view transform, dt's hardest single port (~2000 lines), realized
// as the D-T1 sub-stage chain:
//
//   F0 CPU derivation   → FilmicSpline.swift (spline M1..M5, output
//                         power, norm bounds — unit-tested vectors)
//   F1 1D curve         → log encode → filmic_spline → clamp → pow
//                         (three-way: CPU LUT vs Metal vs dt flat probes)
//   F2 V5 dual-path     → max-RGB norm path ⊕ naive per-channel path,
//                         mixed by ±saturation (filmicrgb_v5 kernel)
//   F3 Yrg gamut map    → YrgGamut.swift + the kernel's Ych leg
//                         (out-of-Rec2020 spectral fixture parity)
//   F4 full module      → torture fixture set parity + auto three keys
//                         + Inspector panel
//
// SCOPE (T0 checkpoint, 03-06-DECISIONS.md):
//   1. colorscience = V5 ONLY (`filmic_chroma_v5` semantics, dt default);
//      the params enum keeps all five values, non-V5 values degrade to
//      V5 math (recorded divergence #5).
//   2. Highlight reconstruction EXCLUDED (F5 TODO, Phase 8+): the params
//      and the `filmic_mask_clipped_pixels` mask kernel exist; the
//      à-trous wavelet rebuild does not (enableHighlightReconstruction
//      stays FALSE — dt's default — and no rebuild runs when true).
//   3. preserve_color norm family fully implemented (MAX_RGB / LUMINANCE
//      / POWER_NORM / EUCLIDEAN_V1/V2 / NONE); V5 pins MAX_RGB for its
//      norm leg regardless (dt's filmic_chroma_v5 hardcodes it).
//
// DIVERGENCES (recorded):
//   #1 auto_hardness: dt mutates `output_power` in the GUI callbacks +
//      reload_defaults; Lightamer re-derives it at commit when
//      `autoHardness == true` (invariant-equivalent, GUI-free).
//   #2 exposure-driven reload_defaults (dt's scene-referred 0.7EV
//      auto-enable) NOT ported — Lightamer loads are post-CIRAW
//      displayed-domain (the 03-04 sigmoid caveat applies verbatim).
//   #3 processed_maximum pipeline state not tracked (Phase 3-wide).
//   #4 use_output_profile gamut leg fixed OFF (dt's export-profile
//      bypass is an export-pipe concern; Lightamer maps against the
//      work profile always).
//   #5 non-V5 colorscience enum values run V5 math (T0 decision 1).
//   #6 V5 has NO ratio sanitization (the plan text's "减 min_ratios" is
//      the v1 path — 03-06-DECISIONS.md erratum).
//
// REFERENCE: src/iop/filmicrgb.c + data/kernels/filmic.cl (dc58cf0ba1).
// GOLDEN: synthesized float64 references (L017 route — the dt-cli float
// export host finding) + dt-side XMP adoption + uniform-flat PFM probes.
// L006: float32 only. INPUT SEMANTICS: linear Rec2020 scene RGB.
// ─────────────────────────────────────────────────────────────────────────

public enum FilmicRGBKernel {
    public static let v5Function = "filmicrgb_v5"
    public static let maskFunction = "filmic_mask_clipped_pixels"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// dt `dt_iop_filmicrgb_methods_type_t` (filmicrgb.c:98-107) — the
/// preserve_color norm family.
public enum FilmicRGBNorm: Int, Codable, Hashable, Sendable {
    case none = 0
    case maxRGB = 1
    case luminance = 2
    case powerNorm = 3
    case euclideanV1 = 4
    case euclideanV2 = 5
}

/// dt `dt_iop_filmicrgb_colorscience_type_t` (filmicrgb.c:112-119).
/// Only `.v5` runs V5 math (T0 decision 1 — divergence #5).
public enum FilmicRGBColorscience: Int, Codable, Hashable, Sendable {
    case v1 = 0
    case v2 = 1
    case v3 = 2
    case v4 = 3
    case v5 = 4
}

/// The scene-referred filmic tone mapper (dt default parameters).
public final class FilmicRGBModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {

        /// ∈ [0, 100], default 18.45 (%).
        public var greyPointSource: Float
        /// ∈ [-16, -0.1], default -8.0 (EV).
        public var blackPointSource: Float
        /// ∈ [0.1, 16], default 4.0 (EV).
        public var whitePointSource: Float
        // Highlight-reconstruction params (params slots only — F5 TODO):
        public var reconstructThreshold: Float
        public var reconstructFeather: Float
        public var reconstructBloomVsDetails: Float
        public var reconstructGreyVsColor: Float
        public var reconstructStructureVsTexture: Float
        /// ∈ [-50, 200], default 0 (dynamic range scaling).
        public var securityFactor: Float
        /// ∈ [1, 50], default 18.45 (%).
        public var greyPointTarget: Float
        /// ∈ [0, 20], default 0.01517634 (%).
        public var blackPointTarget: Float
        /// ∈ [0, 1600], default 100 (%).
        public var whitePointTarget: Float
        /// ∈ [1, 10], default 4.0 (auto with autoHardness — divergence #1).
        public var outputPower: Float
        /// ∈ [0.01, 99], default 0.01 (linear region %).
        public var latitude: Float
        /// ∈ [0, 5], default 1.0.
        public var contrast: Float
        /// ∈ [-200, 200], default 0 (extreme-luminance saturation).
        public var saturation: Float
        /// ∈ [-50, 50], default 0 (shadows ↔ highlights balance).
        public var balance: Float
        public var noiseLevel: Float
        /// preserve chrominance norm (T0 decision 3).
        public var preserveColor: FilmicRGBNorm
        /// colorscience version (T0 decision 1 — only V5 math).
        public var version: FilmicRGBColorscience
        /// auto output power (divergence #1).
        public var autoHardness: Bool
        public var customGrey: Bool
        /// F5 param slot (no rebuild behind it — T0 decision 2).
        public var highQualityReconstruction: Int
        public var enableHighlightReconstruction: Bool
        /// toe curve type (shadows).
        public var shadows: FilmicSpline.CurveType
        /// shoulder curve type (highlights).
        public var highlights: FilmicSpline.CurveType
        public var compensateIccBlack: Bool
        /// spline handling version (runtime pins the derive branch; all
        /// three branches implemented + tested).
        public var splineVersion: FilmicSpline.SplineVersion

        public init(
            greyPointSource: Float = 18.45,
            blackPointSource: Float = -8.0,
            whitePointSource: Float = 4.0,
            reconstructThreshold: Float = 0.0,
            reconstructFeather: Float = 3.0,
            reconstructBloomVsDetails: Float = 100.0,
            reconstructGreyVsColor: Float = 100.0,
            reconstructStructureVsTexture: Float = 0.0,
            securityFactor: Float = 0,
            greyPointTarget: Float = 18.45,
            blackPointTarget: Float = 0.01517634,
            whitePointTarget: Float = 100,
            outputPower: Float = 4.0,
            latitude: Float = 0.01,
            contrast: Float = 1.0,
            saturation: Float = 0,
            balance: Float = 0.0,
            noiseLevel: Float = 0.2,
            preserveColor: FilmicRGBNorm = .powerNorm,
            version: FilmicRGBColorscience = .v5,
            autoHardness: Bool = true,
            customGrey: Bool = false,
            highQualityReconstruction: Int = 1,
            enableHighlightReconstruction: Bool = false,
            shadows: FilmicSpline.CurveType = .poly4,
            highlights: FilmicSpline.CurveType = .poly4,
            compensateIccBlack: Bool = false,
            splineVersion: FilmicSpline.SplineVersion = .v3
        ) {
            self.greyPointSource = greyPointSource
            self.blackPointSource = blackPointSource
            self.whitePointSource = whitePointSource
            self.reconstructThreshold = reconstructThreshold
            self.reconstructFeather = reconstructFeather
            self.reconstructBloomVsDetails = reconstructBloomVsDetails
            self.reconstructGreyVsColor = reconstructGreyVsColor
            self.reconstructStructureVsTexture = reconstructStructureVsTexture
            self.securityFactor = securityFactor
            self.greyPointTarget = greyPointTarget
            self.blackPointTarget = blackPointTarget
            self.whitePointTarget = whitePointTarget
            self.outputPower = outputPower
            self.latitude = latitude
            self.contrast = contrast
            self.saturation = saturation
            self.balance = balance
            self.noiseLevel = noiseLevel
            self.preserveColor = preserveColor
            self.version = version
            self.autoHardness = autoHardness
            self.customGrey = customGrey
            self.highQualityReconstruction = highQualityReconstruction
            self.enableHighlightReconstruction = enableHighlightReconstruction
            self.shadows = shadows
            self.highlights = highlights
            self.compensateIccBlack = compensateIccBlack
            self.splineVersion = splineVersion
        }
    }

    public static let opName = "filmicrgb"
    public static let iopOrder: Float = 46.0
    public static let flags: IOPFlags = [.supportsBlending]
    public static let defaultColorspace: IOPColorspace = .RGB

    // Piece buffer layout (floats):
    //   0..10   scalars (dynamic_range, black_source, grey_source,
    //           output_power, saturation, norm_min, norm_max,
    //           latitude_min, latitude_max, black_display, white_display)
    //   11..30  M1..M5 (4 lanes each: toe, shoulder, linear, unused)
    //   31..32  curve types (toe, shoulder)
    //   33..41  matrix_in (row-major 3×3, pipeline RGB → LMS 2006)
    //   42..50  matrix_out (row-major 3×3, LMS 2006 → pipeline RGB)
    static let bufferFloatCount = 51
    static let m1Offset = 11
    static let typesOffset = 31
    static let matrixInOffset = 33
    static let matrixOutOffset = 42

    private let device: (any MTLDevice)?
    private var resolvedDevice: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        // Divergence #2: no exposure-driven auto-enable (post-CIRAW load).
        Params()
    }

    // MARK: - Commit (filmicrgb.c commit_params :3049-3135 + auto hardness)

    /// The commit-time effective params: dt's auto_hardness is GUI-enforced
    /// (divergence #1) — here it derives `output_power` once, shared by the
    /// module commit AND the derivation tests.
    public static func effectiveParams(_ params: Params) -> Params {
        var effective = params
        if effective.autoHardness {
            effective.outputPower = Float(FilmicSpline.computeOutputPower(
                greyPointTarget: Double(effective.greyPointTarget),
                blackPointSource: Double(effective.blackPointSource),
                whitePointSource: Double(effective.whitePointSource)
            ))
        }
        return effective
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        let effective = Self.effectiveParams(params)

        let encoded = ParamsCoding.encode(effective)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        resolvedDevice = resolved

        if pieceBuffer == nil || committed != effective {
            let (spline, _) = FilmicSpline.derive(params: effective)
            let greySource: Double = effective.customGrey
                ? Double(effective.greyPointSource) / 100.0
                : 0.1845
            let dynamicRange = Double(effective.whitePointSource - effective.blackPointSource)
            let blackSource = Double(effective.blackPointSource)
            let bounds = FilmicSpline.normBounds(
                greySource: greySource, blackSource: blackSource, dynamicRange: dynamicRange
            )
            // V5 saturation folding (commit_params :3116-3119, V4+ branch).
            let saturation = Double(effective.saturation) / 100.0
            // display black/white as consumed by the kernel: the spline
            // nodes raised to output_power (process_cl :2547-2549).
            let outputPower = Double(effective.outputPower)
            let blackDisplay = pow(Double(spline.y[0]), outputPower)
            let whiteDisplay = pow(Double(spline.y[4]), outputPower)

            var floats = [Float](repeating: 0, count: Self.bufferFloatCount)
            floats[0] = Float(dynamicRange)
            floats[1] = Float(blackSource)
            floats[2] = Float(greySource)
            floats[3] = effective.outputPower
            floats[4] = Float(saturation)
            floats[5] = Float(bounds.min)
            floats[6] = Float(bounds.max)
            floats[7] = spline.latitudeMin
            floats[8] = spline.latitudeMax
            floats[9] = Float(blackDisplay)
            floats[10] = Float(whiteDisplay)
            let m: [FilmicSpline.Spline.Lane] = [
                spline.M1, spline.M2, spline.M3, spline.M4, spline.M5,
            ]
            for (i, lane) in m.enumerated() {
                floats[Self.m1Offset + i * 4 + 0] = lane.toe
                floats[Self.m1Offset + i * 4 + 1] = lane.shoulder
                floats[Self.m1Offset + i * 4 + 2] = lane.linear
                floats[Self.m1Offset + i * 4 + 3] = 0
            }
            floats[Self.typesOffset] = Float(effective.shadows.rawValue)
            floats[Self.typesOffset + 1] = Float(effective.highlights.rawValue)
            floats.replaceSubrange(
                Self.matrixInOffset..<Self.matrixInOffset + 9, with: YrgGamut.flatten(YrgGamut.matrixIn)
            )
            floats.replaceSubrange(
                Self.matrixOutOffset..<Self.matrixOutOffset + 9, with: YrgGamut.flatten(YrgGamut.matrixOut)
            )

            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: Self.bufferFloatCount * MemoryLayout<Float>.size,
                    options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                floats.withUnsafeBytes {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!, byteCount: Self.bufferFloatCount * MemoryLayout<Float>.size
                    )
                }
            }
            committed = effective
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
        guard let buffer = piece.data else { return }
        // T0 decision 2: the F5 mask/rebuild never runs in the pipe; the
        // mask kernel exists for tests only (FilmicRGBTests).
        try await metal.dispatch2DTexture(
            functionName: FilmicRGBKernel.v5Function,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    // MARK: - auto three keys (filmicrgb.c:2583-2660 — CPU 直译)

    /// The auto-key math, factored pure for unit tests. dt reads
    /// `self->picked_color*` (the picker plumbing) — the callers pass the
    /// sampled values.
    public enum AutoKey {

        /// `apply_auto_grey` (:2583-2608): picked norm / 2 → the grey
        /// source, symmetric K-shift of black/white, output power refresh.
        public static func autoGrey(
            params: inout Params, picked: simd_float3
        ) {
            let norm = FilmicRGBMath.pixelNorm(
                SIMD3<Double>(picked), variant: params.preserveColor
            ) / 2.0
            let prevGrey = params.greyPointSource
            params.greyPointSource = Float(Swift.min(Swift.max(100.0 * norm, 0.001), 100.0))
            let greyVar = log2(Double(prevGrey) / Double(params.greyPointSource))
            params.blackPointSource = Float(Double(params.blackPointSource) - greyVar)
            params.whitePointSource = Float(Double(params.whitePointSource) + greyVar)
            refreshOutputPower(&params)
        }

        /// `apply_auto_black` (:2610-2635): `picked_color_min` through the
        /// MAX_RGB norm. `minNorm` = max3(min-RGB over the image).
        public static func autoBlack(params: inout Params, minMaxRGB: Float) {
            var evMin = Swift.min(
                Swift.max(
                    log2(Double(minMaxRGB) / (Double(params.greyPointSource) / 100.0)), -16.0
                ), -1.0
            )
            evMin *= 1.0 + Double(params.securityFactor) / 100.0
            params.blackPointSource = Float(Swift.max(evMin, -16.0))
            refreshOutputPower(&params)
        }

        /// `apply_auto_white_point_source` (:2637-2660).
        public static func autoWhite(params: inout Params, maxMaxRGB: Float) {
            var evMax = Swift.min(
                Swift.max(
                    log2(Double(maxMaxRGB) / (Double(params.greyPointSource) / 100.0)), 1.0
                ), 16.0
            )
            evMax *= 1.0 + Double(params.securityFactor) / 100.0
            params.whitePointSource = Float(evMax)
            refreshOutputPower(&params)
        }

        static func refreshOutputPower(_ params: inout Params) {
            if params.autoHardness {
                params.outputPower = Float(FilmicSpline.computeOutputPower(
                    greyPointTarget: Double(params.greyPointTarget),
                    blackPointSource: Double(params.blackPointSource),
                    whitePointSource: Double(params.whitePointSource)
                ))
            }
        }
    }
}

/// The norm family (filmic.cl:153-196 + rgb_norms.h semantics) in Double —
/// shared by the auto keys and the CPU reference tests.
public enum FilmicRGBMath {

    /// dt `get_pixel_norm` — note NONE/LUMINANCE both fall to the matrix
    /// luminance (the work profile is Rec2020 → fixed coefficients).
    public static func pixelNorm(
        _ pixel: SIMD3<Double>, variant: FilmicRGBNorm
    ) -> Double {
        switch variant {
        case .maxRGB:
            return Swift.max(Swift.max(pixel.x, pixel.y), pixel.z)
        case .luminance, .none:
            let c = YrgGamut.rec2020Luminance
            return c.x * pixel.x + c.y * pixel.y + c.z * pixel.z
        case .powerNorm:
            var numerator = 0.0
            var denominator = 0.0
            for c in 0..<3 {
                let value = abs(pixel[c])
                let square = value * value
                numerator += square * value
                denominator += square
            }
            return numerator / Swift.max(denominator, 1e-12)
        case .euclideanV1:
            return (pixel.x * pixel.x + pixel.y * pixel.y + pixel.z * pixel.z).squareRoot()
        case .euclideanV2:
            return (pixel.x * pixel.x + pixel.y * pixel.y + pixel.z * pixel.z).squareRoot()
                * 0.5773502691896258 // INVERSE_SQRT_3
        }
    }
}
