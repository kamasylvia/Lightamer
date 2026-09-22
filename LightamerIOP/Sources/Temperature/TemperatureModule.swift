import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// TEMPERATURE / white balance — the second real tone iop (Phase 3 Plan
// 03-02, IOP-TONE-02) and the first D-T6 consumer of the eyedropper
// plumbing.
//
// Darktable reference: `src/iop/temperature.c` (tree dc58cf0ba1, 2026-08-02)
//   - params v4      :66-75  (red/green/blue/various ∈ [0,8] + preset)
//   - Kelvin→XYZ     :287-473 (Planck blackbody < 4000K / CIE D-series ≥
//                              4000K SPD → CMF integral → max-normalize;
//                              tint = Y-division hack :435-441;
//                              K↔XYZ binary search :396-432)
//   - eyedropper     :1933-1955 (gains = clamp(1/picked, 0, 8), green-
//                               normalized)
//   - kernel         `data/kernels/basic.cl:229-239 whitebalance_4f`
//                     (per-pixel rgb × coeffs[3], alpha untouched)
//
// INTENTIONAL DIVERGENCES from Darktable (RESEARCH §1.2/§5 — all recorded
// here as the plan's Must-have):
//
// 1. **post-CIRAW correction layer, NOT sensor-domain gains.** dt's
//    Kelvin→gain model converts XYZ through a per-camera `XYZ_to_CAM`
//    matrix (sensor domain, temperature.c:1370-1420 `adobe_XYZ_to_CAM`).
//    Lightamer's pipe input is CIRAW's *displayed domain* — already
//    white-balanced by the decoder — so Lightamer's temperature is a
//    post-hoc channel-gain correction in the WORKING SPACE (linear
//    Rec2020). **v50 slot 3.0 is retained verbatim** (zero table change,
//    RESEARCH Open Question #2 resolution) — the slot semantics are
//    documented as divergent: the module runs at that position in
//    Lightamer's pipe (before colorin), which for the working-space
//    identity colorin is pixel-equivalent to any pre-colorout position.
// 2. **Kelvin→gains is Rec2020-native** (RESEARCH §5): target-illuminant
//    SPD→XYZ (the dt-shared math above) → expressed in Rec2020 →
//    `gains = W / T` with W = the D65 anchor through the SAME conversion
//    path, so `gains(D65) ≡ (1, 1, 1)` exactly. dt instead converts via
//    the camera matrix and normalizes implicitly through it. The eyedropper
//    path (divergence 4) is domain-independent and stays dt-isomorphic.
// 3. **`various` (4th/CYGM channel) NOT ported.** dt carries a 4th gain
//    for CYGM sensors; Lightamer's pipe is RGB float32. The params layout
//    keeps only r/g/b + preset; golden blobs pin dt's `various = 1.0`.
// 4. **Eyedropper = dt-isomorphic.** `gainsFromPicked` is a verbatim port
//    of `color_picker_apply` (temperature.c:1933-1955): channel ratios are
//    domain-independent, so the Rec2020 pick neutralizes exactly like dt's
//    sensor-domain pick (RESEARCH §5).
// 5. **K↔gains inversion tightens dt's binary search** from a 1.0K bracket
//    to 1e-4K (same algorithm shape, `_XYZ_to_temperature` :396-432) — the
//    plan's round-trip gate is <1e-3 K.
// ─────────────────────────────────────────────────────────────────────────

/// The Kelvin/tint ⇄ Rec2020 channel-gains math (Plan 03-02-T1). Double
/// precision throughout — the CMF/SPD integral and the bisection live
/// entirely in commit-path/UI code, never per-pixel.
///
/// Reference vectors for every stage are pinned in
/// `CPUDerivationTests` (WB section) against the C harness
/// `.work/plans/03-02/wb_reference.c`, which computes the dt-side values from
/// darktable's own table file + lcms2.
public enum WhiteBalanceMath {

    // MARK: Domain constants (dt temperature.c:45-51 verbatim)

    /// dt `INITIALBLACKBODYTEMPERATURE` (temperature.c:45): below this the
    /// SPD model switches from CIE D-series daylight to Planck blackbody.
    public static let blackbodyThresholdKelvin: Double = 4000

    /// dt `DT_IOP_LOWEST_TEMPERATURE` / `DT_IOP_HIGHEST_TEMPERATURE`.
    public static let lowestKelvin: Double = 1901
    public static let highestKelvin: Double = 25000

    /// dt `DT_IOP_LOWEST_TINT` / `DT_IOP_HIGHEST_TINT`.
    public static let lowestTint: Double = 0.135
    public static let highestTint: Double = 2.326

    /// The D65 anchor temperature: the CIE D-series SPD at 6504K has
    /// chromaticity (0.31270, 0.32901) — the Rec2020/ITU white point to
    /// within table quantization (verified by the reference harness).
    public static let d65Kelvin: Double = 6504

    /// Bisection bracket width for the gains→Kelvin inversion (divergence
    /// #5: dt uses 1.0K; the plan's <1e-3 K round-trip gate needs tighter).
    private static let kelvinBisectionEpsilon: Double = 1e-4

    // MARK: Linear Rec2020 ⇄ XYZ (D65-anchored standard matrix pair)

    /// Linear Rec2020 → XYZ (D65) — the ITU BT.2020 primaries with the D65
    /// white point (same constants as the golden fixture generator's
    /// `REC2020_TO_XYZ`).
    public static let rec2020ToXYZ: [[Double]] = [
        [0.636958, 0.144617, 0.168881],
        [0.262700, 0.678009, 0.059291],
        [0.000000, 0.028073, 1.060806],
    ]

    /// XYZ → linear Rec2020 — computed once from the forward matrix so the
    /// pair is exactly consistent (roundtrip residual ~1e-16).
    public static let xyzToRec2020: [[Double]] = invert(rec2020ToXYZ)

    // MARK: SPD → XYZ (dt temperature.c:287-432 verbatim, double precision)

    /// Bruce Lindbloom's blackbody SPD (temperature.c:293-311). Planck's
    /// constants as committed in dt (long-double literals folded to
    /// Double — the difference is <1e-12 relative, far inside the 1e-4
    /// cross-check gate).
    private static func spdBlackbody(wavelengthNM: Int, kelvin: Double) -> Double {
        let lambda = Double(wavelengthNM) * 1e-9
        let c1 = 3.7417715246641281639549488324352159753e-16
        let c2 = 0.014387769599838156481252937624049081933
        return c1 / (pow(lambda, 5) * (exp(c2 / (lambda * kelvin)) - 1.0))
    }

    /// LittleCMS `cmsWhitePointFromTemp` (the function dt's daylight SPD
    /// calls through lcms2) — ported verbatim from lcms2 `cmswtpnt.c`
    /// (commit-matched: the cubic fits for 4000–7000K and 7000–25000K,
    /// y = −3x² + 2.87x − 0.275).
    static func lcmsWhitePointFromTemp(_ kelvin: Double) -> (x: Double, y: Double)? {
        let t = kelvin
        let t2 = t * t
        let t3 = t2 * t
        let x: Double
        if t >= 4000.0, t <= 7000.0 {
            x = -4.6070 * (1e9 / t3) + 2.9678 * (1e6 / t2) + 0.09911 * (1e3 / t) + 0.244063
        } else if t > 7000.0, t <= 25000.0 {
            x = -2.0064 * (1e9 / t3) + 1.9018 * (1e6 / t2) + 0.24748 * (1e3 / t) + 0.237040
        } else {
            return nil // lcms signals an out-of-domain error; dt's callers
                       // only reach here for K ≥ 4000 (divergence-free)
        }
        let y = -3.000 * x * x + 2.870 * x - 0.275
        return (x, y)
    }

    /// Bruce Lindbloom's CIE D-illuminant SPD (temperature.c:314-343):
    /// `S(λ) = S0 + m1·S1 + m2·S2` with the daylite factors from the lcms
    /// white point of `kelvin`.
    private static func spdDaylight(wavelengthNM: Int, kelvin: Double) -> Double {
        guard let wp = lcmsWhitePointFromTemp(kelvin) else { return 0 }
        let m = 0.0241 + 0.2562 * wp.x - 0.7341 * wp.y
        let m1 = (-1.3515 - 1.7703 * wp.x + 5.9114 * wp.y) / m
        let m2 = (0.0300 - 31.4424 * wp.x + 30.0717 * wp.y) / m
        let j = (wavelengthNM - CIEData.daylightFirstWavelength)
            / CIEData.daylightWavelengthStep
        let s = CIEData.daylightComponents[j]
        return s.s0 + m1 * s.s1 + m2 * s.s2
    }

    /// SPD → XYZ integral against the CIE 1931 2° observer, max-
    /// normalized (dt `_spectrum_to_XYZ`, temperature.c:345-386 — the
    /// normalization is part of the dt-shared semantics).
    private static func spectrumToXYZ(kelvin: Double, spd: (Int, Double) -> Double) -> SIMD3<Double> {
        var xyz = SIMD3<Double>.zero
        let count = CIEData.observer1931.count
        for i in 0..<count {
            let lambda = CIEData.observerFirstWavelength
                + CIEData.observerWavelengthStep * i
            let p = spd(lambda, kelvin)
            let cmf = CIEData.observer1931[i]
            xyz += SIMD3(p * cmf.x, p * cmf.y, p * cmf.z)
        }
        let maxComponent = max(xyz.x, max(xyz.y, xyz.z))
        return xyz / maxComponent
    }

    /// dt `_temperature_to_XYZ` (temperature.c:389-401): blackbody below
    /// 4000K, CIE daylight at/above; Kelvin clamped to the dt domain.
    static func temperatureToXYZ(_ kelvinIn: Double) -> SIMD3<Double> {
        let kelvin = min(max(kelvinIn, lowestKelvin), highestKelvin)
        if kelvin < blackbodyThresholdKelvin {
            return spectrumToXYZ(kelvin: kelvin, spd: spdBlackbody)
        } else {
            return spectrumToXYZ(kelvin: kelvin, spd: spdDaylight)
        }
    }

    // MARK: Kelvin/tint → gains (Rec2020-native, RESEARCH §5)

    /// The D65 anchor expressed in Rec2020 through the SAME conversion path
    /// as any other temperature — `kelvinTintToGains(d65Kelvin, 1.0)` is
    /// therefore EXACTLY (1, 1, 1) regardless of table quantization
    /// (W/T with W computed identically to T). The anchor's chromaticity
    /// matches the Rec2020 white to ~1e-5 (harness-verified).
    private static let d65WhiteRec2020: SIMD3<Double> = rec2020White(
        ofXYZ: temperatureToXYZ(d65Kelvin)
    )

    /// Express a (max-normalized) illuminant XYZ in Rec2020, anchored to
    /// Y=1: the scale-invariant form whose D65 value is (1, 1, 1) by
    /// matrix construction (the matrix rows sum to the D65 white).
    private static func rec2020White(ofXYZ xyz: SIMD3<Double>) -> SIMD3<Double> {
        let sum = xyz.x + xyz.y + xyz.z
        let yNormalized = SIMD3<Double>(xyz.x / sum, xyz.y / sum, xyz.z / sum)
        return mulMatrix(xyzToRec2020, yNormalized)
    }

    /// Kelvin/tint → per-channel gains in linear Rec2020.
    ///
    /// Chain (RESEARCH §5, divergences #1/#2):
    /// 1. illuminant SPD → XYZ (dt-shared math, max-normalized);
    /// 2. dt's tint Y-hack (`xyz.Y /= tint`, temperature.c:435-441 — the
    ///    source's own TODO acknowledges it is not orthogonal to the
    ///    Planckian locus; reproduced for semantic parity);
    /// 3. the tinted white expressed in Rec2020 (Y-normalized);
    /// 4. `gains = W / T` with W = the D65 anchor (exact identity above).
    ///
    /// Raising Kelvin lowers the blue gain and raises the red gain
    /// (cooler light ⇒ stronger blue cut is inverted here: to RENDER a
    /// cooler scene on a D65 display you boost red — the direction
    /// assertion is pinned in CPUDerivationTests).
    public static func kelvinTintToGains(kelvin: Double, tint: Double) -> SIMD3<Double> {
        var xyz = temperatureToXYZ(kelvin)
        xyz.y /= max(tint, 1e-9) // dt Y-hack (temperature.c:436)
        let t = rec2020White(ofXYZ: xyz)
        return d65WhiteRec2020 / t
    }

    // MARK: gains → Kelvin/tint (dt `_mul2temp` isomorphic)

    /// Per-channel gains → (Kelvin, tint) for UI display — the Rec2020
    /// analog of dt `_mul2temp` (temperature.c:473-486): the gains define a
    /// neutralized white; its chromaticity is inverted through the same
    /// binary search dt uses on Z/X (`_XYZ_to_temperature`, :396-432), then
    /// tint comes from the Y/X ratio (dt's formula verbatim).
    ///
    /// The round trip `kelvinTintToGains → gainsToKelvinTint` closes to
    /// <1e-3 K (plan gate; bisection epsilon 1e-4 K, divergence #5).
    public static func gainsToKelvinTint(gains: SIMD3<Double>) -> (kelvin: Double, tint: Double) {
        // Defensive domain clamp: gains are UI-bounded [0,8]; the inversion
        // needs strictly positive channels.
        let g = SIMD3<Double>(
            gains.x > 1e-6 ? gains.x : 1e-6,
            gains.y > 1e-6 ? gains.y : 1e-6,
            gains.z > 1e-6 ? gains.z : 1e-6
        )
        // The white these gains neutralize, back through the same path.
        let t = d65WhiteRec2020 / g
        let targetXYZ = mulMatrix(rec2020ToXYZ, t)
        let targetZX = targetXYZ.z / targetXYZ.x
        let targetYX = targetXYZ.y / targetXYZ.x

        // dt's binary search shape (temperature.c:396-423), tightened.
        var maxtemp = highestKelvin
        var mintemp = lowestKelvin
        var kelvin = (maxtemp + mintemp) / 2.0
        while (maxtemp - mintemp) > kelvinBisectionEpsilon {
            let probe = temperatureToXYZ(kelvin)
            if probe.z / probe.x > targetZX {
                maxtemp = kelvin
            } else {
                mintemp = kelvin
            }
            kelvin = (maxtemp + mintemp) / 2.0
        }
        // dt's tint formula (temperature.c:425-429) evaluated at the final
        // midpoint (dt reads the last PROBED point — a ≤1K-stale artifact
        // of its loop shape; at the 1e-4K bracket the final midpoint is the
        // faithful evaluation point and keeps the round trip at 1e-9 tint).
        let lastXYZ = temperatureToXYZ(kelvin)
        var tint = (lastXYZ.y / lastXYZ.x) / targetYX

        kelvin = min(max(kelvin, lowestKelvin), highestKelvin)
        tint = min(max(tint, lowestTint), highestTint)
        return (kelvin, tint)
    }

    // MARK: Eyedropper (dt temperature.c:1933-1955 verbatim)

    /// Neutral-solve a picked linear color: `gains = clamp(1/picked, 0, 8)`
    /// green-normalized (`gain[g] = 1.0`). Ported verbatim from dt's
    /// `color_picker_apply` — channel ratios are domain-independent, so the
    /// Rec2020 pick neutralizes exactly like dt's sensor-domain pick
    /// (divergence #4).
    ///
    /// Picked values are the AREA-averaged linear Rec2020 of the viewport
    /// sample (`PipeCoordinator.samplePreview`, dt's AREA picker semantics).
    public static func gainsFromPicked(_ picked: SIMD3<Float>) -> SIMD3<Float> {
        let p = SIMD3<Double>(picked)
        let gnormal = p.y > 0.001 ? 1.0 / p.y : 1.0
        func channel(_ v: Double) -> Double {
            let raw = v > 0.001 ? (1.0 / v) / gnormal : 1.0
            return min(max(raw, 0.0), 8.0)
        }
        var gains = SIMD3<Double>(channel(p.x), channel(p.y), channel(p.z))
        gains.y = 1.0 // dt sets the green gain unconditionally
        return SIMD3<Float>(gains)
    }

    // MARK: Small matrix helpers

    static func mulMatrix(_ m: [[Double]], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
            m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
            m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z
        )
    }

    static func invert(_ m: [[Double]]) -> [[Double]] {
        let a = m[0], b = m[1], c = m[2]
        let det = a[0] * (b[1] * c[2] - b[2] * c[1])
            - a[1] * (b[0] * c[2] - b[2] * c[0])
            + a[2] * (b[0] * c[1] - b[1] * c[0])
        return [
            [
                (b[1] * c[2] - b[2] * c[1]) / det,
                (a[2] * c[1] - a[1] * c[2]) / det,
                (a[1] * b[2] - a[2] * b[1]) / det,
            ],
            [
                (b[2] * c[0] - b[0] * c[2]) / det,
                (a[0] * c[2] - a[2] * c[0]) / det,
                (a[2] * b[0] - a[0] * b[2]) / det,
            ],
            [
                (b[0] * c[1] - b[1] * c[0]) / det,
                (a[1] * c[0] - a[0] * c[1]) / det,
                (a[0] * b[1] - a[1] * b[0]) / det,
            ],
        ]
    }
}

// ─────────────────────────────────────────────────────────────────────────

public enum TemperatureKernel {

    /// MSL function name of the WB kernel (`TemperatureKernels.metal`).
    public static let functionName = "temperature_apply"

    /// The LightamerIOP framework bundle — the `registerDefaultLibrary(in:)`
    /// anchor (the IOP metallib lives in the FRAMEWORK bundle, never
    /// `Bundle.main`).
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// The temperature iop — `dt_iop_temperature_params_t` v4 mirror minus the
/// `various` CYGM channel (divergence #3). See the file header for the
/// reference line numbers and the five recorded divergences.
public final class TemperatureModule: IOPModule {

    /// WB preset (dt `DT_IOP_TEMP_*`, temperature.c:56-62 raw values;
    /// UNKNOWN kept so legacy/foreign values decode instead of throwing).
    public enum Preset: Int, Codable, Hashable, Sendable {
        case unknown = -1
        case asShot = 0
        case spot = 1
        case user = 2
        case d65 = 3
        case d65Late = 4
    }

    /// dt v4 params, field-for-field minus `various` (divergence #3,
    /// temperature.c:66-75): `red/green/blue(f ∈[0,8]) preset(int)`.
    /// Kelvin/tint are DERIVED display values (dt `_mul2temp` semantics —
    /// the gains are the persisted truth); the panel derives them through
    /// `WhiteBalanceMath.gainsToKelvinTint`.
    public struct Params: Codable, Hashable, Sendable {
        /// Red channel gain ∈ [0, 8], default 1.
        public var red: Float
        /// Green channel gain ∈ [0, 8], default 1.
        public var green: Float
        /// Blue channel gain ∈ [0, 8], default 1.
        public var blue: Float
        /// WB preset bit (dt raw values). Pixel-neutral in Lightamer —
        /// the panel uses it for UI state (dt uses it for the D65-late
        /// CAT deferral, which is channelmixerrgb territory here).
        public var preset: Preset

        public init(
            red: Float = 1.0,
            green: Float = 1.0,
            blue: Float = 1.0,
            preset: Preset = .user
        ) {
            self.red = red
            self.green = green
            self.blue = blue
            self.preset = preset
        }

        /// The gains as a vector (r, g, b).
        public var gains: SIMD3<Float> { SIMD3(red, green, blue) }

        /// Build params from a gains vector (clamped to the dt domain).
        public init(gains: SIMD3<Float>, preset: Preset = .spot) {
            let c = simd_clamp(gains, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 8))
            self.init(red: c.x, green: c.y, blue: c.z, preset: preset)
        }
    }

    public static let opName = "temperature"

    /// Darktable v50 order slot 3.0 (`iop_order.c` verbatim; V50Order
    /// table). Slot semantics diverge — see file header divergence #1.
    public static let iopOrder: Float = 3.0

    public static let flags: IOPFlags = [.allowTiling, .oneInstance]

    public static let defaultColorspace: IOPColorspace = .RGB

    /// Device for the uniforms `MTLBuffer` allocation in `commitParams`
    /// (TestGain/Exposure precedent; production default nil → lazy system
    /// default).
    private let device: (any MTLDevice)?

    /// Cached uniforms buffer, reallocated when the gains change.
    private var uniformsBuffer: (any MTLBuffer)?
    private var uniformsGains: SIMD3<Float> = SIMD3(repeating: .nan)

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    /// Neutral identity defaults (gains 1.0 — the pipe-cache identity).
    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// dt `commit_params` (temperature.c:687-716): coeffs = params
    /// verbatim (clamped to the [0,8] widget domain).
    ///
    /// `piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))`
    /// (L013: ParamsCoding.sortedKeys is the ONLY legal hash payload).
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        let gains = simd_clamp(
            params.gains, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 8)
        )
        guard let resolvedDevice = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        if uniformsBuffer == nil || anyComponent(uniformsGains, differsFrom: gains) {
            var uniforms = TemperatureUniforms(red: gains.x, green: gains.y, blue: gains.z)
            uniformsBuffer = resolvedDevice.makeBuffer(
                bytes: &uniforms,
                length: MemoryLayout<TemperatureUniforms>.stride,
                options: .storageModeShared
            )
            uniformsGains = gains
        }
        piece.data = uniformsBuffer
    }

    private func anyComponent(_ a: SIMD3<Float>, differsFrom b: SIMD3<Float>) -> Bool {
        a.x != b.x || a.y != b.y || a.z != b.z
    }

    /// Identity ROI: WB does not resample.
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// Identity ROI: WB needs exactly the output ROI as input.
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
            functionName: TemperatureKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            if let uniforms {
                encoder.setBuffer(uniforms, offset: 0, index: 0)
            }
        }
    }
}

/// Swift mirror of the MSL `TemperatureUniforms` struct — 16-byte stride
/// (three floats + padding) so the buffer length satisfies constant-
/// addressable alignment. Mirrors `basic.cl:229-239`'s coeffs[3].
struct TemperatureUniforms {
    var red: Float
    var green: Float
    var blue: Float
    private var _pad: Float = 0

    init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}
