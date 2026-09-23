import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// DenoiseProfileModule (Plan 05-07, IOP-DENOISE-01) — dt `denoiseprofile`
// ("denoise (profiled)", v50 slot 9.0), ported from
//   - src/iop/denoiseprofile.c (tree dc58cf0ba1): params v12 :99-129
//     (416B blob — RESEARCH §1.1 "244B" was an arithmetic erratum, 05-01
//     archived the correction); default_colorspace RGB :837-843 (POST-
//     demosaic linear RGB, NOT raw — RESEARCH §1.2); process dispatch
//     :2598-2616; process_wavelets :1423-1658; Bayesshrink :1345-1421;
//     process_nlmeans :1772-1824; nlmeans_norm :1614-1629; scattering
//     :1631-1657; infer_* :2618-2636; reload_defaults :2667-2739;
//     auto profile :2802-2886; highlight-pres ISO shift :2653-2665;
//     commit_params :2890-2957; tiling_callback :850-908
//   - data/kernels/denoiseprofile.cl (the VST trio, inverse trio, eaw
//     decompose/synthesize, two-pass reduce, vert variant, finish pair)
//   - src/common/eaw.c:226-363 (edge-aware decompose + soft-threshold
//     accumulate) + curve_tools.c (CATMULL-ROM force curves) + draw.h
//     (CurveDataSample uint16 quantization).
//
// v1 SCOPE (D-05-CONTEXT-3): WAVELETS + NLMEANS manual modes + AUTO =
// the infer_* profile-derived parameter family (解析式直译). VARIANCE
// (process_variance local-variance auto strength) is DEFERRED — the mode
// enum bit is kept (sidecar compat), the panel disables the entry.
//
// Compat bools (wb_adaptive_anscombe / fix_anscombe_and_nlmeans_norm /
// use_new_vst): params bits retained verbatim, all DEFAULT TRUE, and the
// LEGACY paths they gate are PORTED in the kernels (dn_precondition/
// dn_backtransform/dn_finish) but the deprecated wb = weights·
// processed_maximum branch of compute_wb_factors (:1240-1244) is NOT —
// dt's processed_maximum has no Lightamer equivalent at slot 9.0.
//
// wb policy (D-05-07-T2-1): dt reads pipe->dsc.temperature.coeffs (the
// temperature module's channel gains). Lightamer's pipe has no dsc state
// and CIRAW does not expose the decoder's internal WB gains, so v1 runs
// compute_wb_factors' coeffs==0 branch — wb ≡ (1,1,1) — with the full
// derivation kept parameterized (wbCoeffs: SIMD3<Float>?) so a future
// pipe-level stamp plugs in without formula changes. Known divergence,
// documented in 05-07-DECISIONS.
//
// PROFILE wiring (NoiseProfileStore consumer): reloadDefaults resolves
// EXIF maker/model/ISO → store match + bracket interpolation (dt auto
// profile :2802-2886) → concrete a/b into params; autodetected sets the
// dt a[0] = −1 sentinel so commit re-resolves (dt :2696-2700 + :2910-
// 2922). Manual ISO override = Lightamer extension field `isoOverride`
// (NOT in the v12 blob — feeds the auto resolution, nil = EXIF).
// highlight-preservation: the whole-EV ISO shift formula is ported and
// unit-tested (:2653-2665) but the `exif_highlight_preservation` metadata
// source does not exist in CaptureMetadata yet → shift is 0 in v1.
//
// ROI (L020/L021): identity (dt has no modify_roi overrides — space
// support is purely tiling_callback :850-908). dscIn is THIS RUN's plane
// pixels; radius/scale compensation uses ONLY the scalars
// `fmin(roi.scale/iscale, 1)` (wavelets in_scale :1439) and
// `fmin(fmin(roi.scale,2)/fmax(iscale,1), 1)` (nlmeans scale :1794) —
// NEVER dscIn × scale. max_scale derives from the RUN-LEVEL dscIn dims
// (20% support rule :1441-1444) so band counts are tile-stable.
//
// SEED (D-05-07-T2-2): DISABLED — dt ships denoiseprofile enabled-by-
// default via the auto profile, but there is NO zero-param identity:
// force 0.5 ⇒ thrs > 0 ⇒ soft-thresholding moves noisy pixels even at
// defaults, and the auto profile makes defaults image-dependent. Identity
// holds only via the disabled piece (colorbalancergb D1 disposition).
// ─────────────────────────────────────────────────────────────────────────

public final class DenoiseProfileModule: IOPModule {

    // MARK: - Params (dt v12 mirror)

    /// dt `dt_iop_denoiseprofile_mode_t` (denoiseprofile.c:68-75) — raw
    /// values are the sidecar/dt-blob identity.
    public enum Mode: Int, Codable, Hashable, Sendable, CaseIterable {
        case nlmeans = 0
        case wavelets = 1
        /// v1 划出（D-05-CONTEXT-3）——enum 位保留，UI 禁用。
        case variance = 2
        case nlmeansAuto = 3
        case waveletsAuto = 4
    }

    /// dt `dt_iop_denoiseprofile_wavelet_mode_t` (:77-81).
    public enum WaveletColorMode: Int, Codable, Hashable, Sendable {
        case rgb = 0
        case y0u0v0 = 1
    }

    /// Channel rows of the 6×7 force tables (denoiseprofile.c:84-93).
    public enum ForceChannel: Int, Sendable {
        case all = 0, r = 1, g = 2, b = 3, y0 = 4, u0v0 = 5
        static let count = 6
    }

    public struct Params: Codable, Hashable, Sendable {
        /// dt $MIN 0 $MAX 12 $DEFAULT 1 ("patch size").
        public var radius: Float
        /// dt $MIN 1 $MAX 30 $DEFAULT 7 ("search radius").
        public var nbhood: Float
        /// dt $MIN 0.001 $MAX 1000 $DEFAULT 1.
        public var strength: Float
        /// dt $MIN 0 $MAX 1.8 $DEFAULT 1 ("preserve shadows").
        public var shadows: Float
        /// dt $MIN −1000 $MAX 100 $DEFAULT 0 ("bias correction").
        public var bias: Float
        /// dt $MIN 0 $MAX 20 $DEFAULT 0.
        public var scattering: Float
        /// dt $MIN 0 $MAX 10 $DEFAULT 0.1.
        public var centralPixelWeight: Float
        /// dt $MIN 0.001 $MAX 1000 $DEFAULT 1 ("adjust autoset").
        public var overshooting: Float
        /// Poissonian-Gaussian fit a[3] (auto sentinel a[0] == −1).
        public var a: SIMD3<Float>
        /// Gaussian base b[3].
        public var b: SIMD3<Float>
        public var mode: Mode
        /// Force curve knot x tables [6][7] (defaults k/6, init :2638-2651).
        public var x: [[Float]]
        /// Force curve knot y tables [6][7] (defaults 0.5).
        public var y: [[Float]]
        /// Compat bools — all DEFAULT TRUE (:123-125); legacy kernels are
        /// ported, the processed_maximum wb branch is not (header note).
        public var wbAdaptiveAnscombe: Bool
        public var fixAnscombeAndNlmeansNorm: Bool
        public var useNewVST: Bool
        public var waveletColorMode: WaveletColorMode
        public var compensateHilitePres: Bool
        /// LIGHTAMER EXTENSION (not in the v12 416B blob): manual ISO for
        /// the auto-profile resolution; nil = EXIF ISO (plan profile 行).
        public var isoOverride: Double?

        public init(
            radius: Float = 1, nbhood: Float = 7, strength: Float = 1,
            shadows: Float = 1, bias: Float = 0, scattering: Float = 0,
            centralPixelWeight: Float = 0.1, overshooting: Float = 1,
            a: SIMD3<Float> = SIMD3(repeating: 1e-4),
            b: SIMD3<Float> = SIMD3(repeating: 0),
            mode: Mode = .wavelets,
            x: [[Float]]? = nil, y: [[Float]]? = nil,
            wbAdaptiveAnscombe: Bool = true,
            fixAnscombeAndNlmeansNorm: Bool = true,
            useNewVST: Bool = true,
            waveletColorMode: WaveletColorMode = .y0u0v0,
            compensateHilitePres: Bool = true,
            isoOverride: Double? = nil
        ) {
            self.radius = radius
            self.nbhood = nbhood
            self.strength = strength
            self.shadows = shadows
            self.bias = bias
            self.scattering = scattering
            self.centralPixelWeight = centralPixelWeight
            self.overshooting = overshooting
            self.a = a
            self.b = b
            self.mode = mode
            self.x = x ?? Self.defaultX
            self.y = y ?? Self.defaultY
            self.wbAdaptiveAnscombe = wbAdaptiveAnscombe
            self.fixAnscombeAndNlmeansNorm = fixAnscombeAndNlmeansNorm
            self.useNewVST = useNewVST
            self.waveletColorMode = waveletColorMode
            self.compensateHilitePres = compensateHilitePres
            self.isoOverride = isoOverride
        }

        /// dt init() :2638-2651 + $DEFAULT 0.5 — x = k/6 grid, y = 0.5.
        public static let defaultX: [[Float]] = {
            (0..<ForceChannel.count).map { _ in
                (0..<DenoiseProfileConsts.bands).map {
                    Float($0) / Float(DenoiseProfileConsts.bands - 1)
                }
            }
        }()
        public static let defaultY: [[Float]] =
            Array(repeating: Array(repeating: 0.5, count: DenoiseProfileConsts.bands),
                  count: ForceChannel.count)

        /// dt auto sentinel (reload_defaults :2698-2700): a[0] == −1 ⇒
        /// commit re-resolves the EXIF profile.
        public static func autoDetected(
            a: SIMD3<Float>, b: SIMD3<Float>, isoOverride: Double? = nil
        ) -> Params {
            var p = Params(a: a, b: b, isoOverride: isoOverride)
            p.a.x = -1
            return p
        }
    }

    /// Shared compile-time constants (bands/fulcrum — mirrors the C macros).
    enum DenoiseProfileConsts {
        static let bands = 7 // DT_IOP_DENOISE_PROFILE_BANDS
        static let pFulcrum: Float = 0.05 // :66
    }

    public static let opName = "denoiseprofile"
    public static let iopOrder: Float = 9.0
    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    // MARK: - Pure derivations (internal for the derivation tests)

    /// compute_wb_factors (:1211-1246) with the fix_norm=TRUE branches.
    /// `wbCoeffs` = dt dsc.temperature.coeffs — v1 nil ⇒ neutral (1,1,1)
    /// (the coeffs==0 fallback :1230-1236); D-05-07-T2-1.
    static func wbFactors(
        coeffs: SIMD3<Float>?, wbAdaptive: Bool, strength: Float,
        compensateStrength: Float, inScale: Float
    ) -> SIMD3<Float> {
        var wb = coeffs ?? SIMD3<Float>(repeating: 0)
        let mean = (wb.x + wb.y + wb.z) / 3
        wb = SIMD3(repeating: mean)
        if mean != 0 && wbAdaptive, let coeffs {
            wb = coeffs
        } else if mean == 0 {
            wb = SIMD3(repeating: 1)
        }
        // :1513-1517,1526-1527 — the strength·compensate_strength·in_scale
        // fold happens AFTER p/matrix derivation (callers sequence it).
        return wb * (strength * compensateStrength * inScale)
    }

    /// Wavelets in_scale = fmin(roi.scale / iscale, 1) (:1439).
    static func waveletsScale(roiScale: Float, iscale: Float) -> Float {
        min(roiScale / iscale, 1)
    }

    /// NLMeans scale = fmin(fmin(roi.scale, 2)/fmax(iscale, 1), 1) (:1794).
    static func nlMeansScale(roiScale: Float, iscale: Float) -> Float {
        min(min(roiScale, 2) / max(iscale, 1), 1)
    }

    /// The 20% support-domain max_scale (:1436-1456) — from the RUN-level
    /// dscIn dims × iscale (dt buf_in·iscale), tile-stable (L021).
    static func maxScale(width: Int, height: Int, iscale: Float, inScale: Float) -> Int {
        var maxScale = 0
        let supp0 = min(
            Float(2 * (2 << (DenoiseProfileConsts.bands - 1)) + 1),
            max(Float(height) * iscale, Float(width) * iscale) * 0.2)
        let i0 = log2f((supp0 - 1) * 0.5)
        while maxScale < DenoiseProfileConsts.bands {
            let supp = Float(2 * (2 << maxScale) + 1)
            let suppIn = supp * (1.0 / inScale)
            let iIn = log2f((suppIn - 1) * 0.5) - 1.0
            if 1.0 - (iIn + 0.5) / i0 < 0 { break }
            maxScale += 1
        }
        return maxScale
    }

    /// nlmeans_norm (:1614-1629): 0.045/(2P+1)², legacy 0.015/(2P+1).
    static func nlMeansNorm(P: Int, fixNorm: Bool) -> Float {
        fixNorm
            ? 0.045 / Float((2 * P + 1) * (2 * P + 1))
            : 0.015 / Float(2 * P + 1)
    }

    /// nlmeans_scattering (:1631-1657) — FULL/canvas legs; the preview
    /// clamp mirrors dt (K → 3, scattering re-derived from the ORIGINAL
    /// maxk over the clamped K cube). Returns the adjusted (K, scattering).
    static func adjustScattering(
        nbhood: Int, scattering: Float, pipeType: PipeResolution
    ) -> (K: Int, scattering: Float) {
        var k = nbhood
        var sc = scattering
        let maxk = (Float(k * k * k) + 7.0 * Float(k) * sqrt(Float(k)))
            * sc / 6.0 + Float(k)
        switch pipeType {
        case .preview, .thumbnail:
            k = min(3, k)
            let denom = Float(k * k * k) + 7.0 * Float(k) * sqrt(Float(k))
            sc = denom == 0 ? 0 : (maxk - Float(k)) * 6.0 / denom
        case .full, .export:
            break
        }
        return (k, sc)
    }

    /// The scattered half-plane enumeration (nlmeans_core.c:84-120 +
    /// denoiseprofile old-CL :2088-2106): j ∈ [−K..0], i ∈ [−K..K]; each
    /// offset pushed through the cube-root scatter (identity at 0).
    static func scatterOffset(_ index: Int, _ other: Int, _ scale: Float, _ scattering: Float) -> Int {
        let a1 = abs(index)
        let a2 = abs(other)
        let sign: Float = index > 0 ? 1 : (index < 0 ? -1 : 0)
        let cube = Float(a1 * a1 * a1)
        let cross = 7.0 * Float(a1) * (Float(a2)).squareRoot()
        let v = scale * ((cube + cross) * sign * scattering / 6.0 + Float(index))
        // dt `const int` cast = truncation toward zero (NOT round)
        return Int(v)
    }

    static func scatteredOffsets(K: Int, scattering: Float) -> [(qx: Int, qy: Int)] {
        var out: [(Int, Int)] = []
        for j in -K...0 {
            for i in -K...K {
                out.append((
                    scatterOffset(i, j, 1.0, scattering),
                    scatterOffset(j, i, 1.0, scattering)))
            }
        }
        return out
    }

    /// tiling halo for the NLMeans leg (tiling_callback :862-874):
    /// K_scattered = ceil(scattering·(K³+7K√K)/6) + K.
    static func kScattered(nbhood: Int, scattering: Float) -> Int {
        let extra = scattering * (Float(nbhood * nbhood * nbhood)
            + 7.0 * Float(nbhood) * sqrt(Float(nbhood))) / 6.0
        return Int(extra.rounded(.up)) + nbhood
    }

    /// infer_* (:2618-2636) — the AUTO parameter family.
    static func inferRadius(fromProfile a: Float) -> Int {
        min(Int(1.0 + a * 15000.0 + a * a * 300000.0), 8)
    }
    static func inferScattering(fromProfile a: Float) -> Float {
        min(3000.0 * a, 1.0)
    }
    static func inferShadows(fromProfile a: Float) -> Float {
        min(max(0.1 - 0.1 * logf(a), 0.7), 1.8)
    }
    static func inferBias(fromProfile a: Float) -> Float {
        -max(5.0 + 0.5 * logf(a), 0.0)
    }

    /// The whole-EV highlight-preservation ISO shift (:2653-2665) —
    /// `floor(hilight_pres)`, ≤0 → 0. v1: metadata source absent → the
    /// caller passes nil → 0 (header note).
    static func isoHighlightShift(highlightPreservation: Double?) -> Int {
        guard let hilight = highlightPreservation else { return 0 }
        let shift = Int(Foundation.floor(hilight))
        return shift <= 0 ? 0 : shift
    }

    // MARK: - Force curves (commit_params :2940-2952 + CurveDataSample)

    /// Catmull-Rom tangents (curve_tools.c:467-499) — CurveTools twin
    /// (Float64 there; this is the float-path mirror used for commit).
    static func catmullRomTangents(x: [Float], y: [Float]) -> [Float]? {
        let n = x.count
        guard n >= 2 else { return nil }
        for i in 0..<(n - 1) where x[i + 1] <= x[i] { return nil }
        var m = [Float](repeating: 0, count: n)
        m[0] = (y[1] - y[0]) / (x[1] - x[0])
        for i in 1..<(n - 1) {
            m[i] = (y[i + 1] - y[i - 1]) / (x[i + 1] - x[i - 1])
        }
        m[n - 1] = (y[n - 1] - y[n - 2]) / (x[n - 1] - x[n - 2])
        return m
    }

    /// catmull_rom_val (curve_tools.c:524-558).
    static func catmullRomVal(x: [Float], y: [Float], tangents: [Float], xval: Float) -> Float {
        let n = x.count
        var ival = n - 2
        for i in 0..<(n - 2) where xval < x[i + 1] {
            ival = i
            break
        }
        let m0 = tangents[ival], m1 = tangents[ival + 1]
        let h = x[ival + 1] - x[ival]
        let dx = (xval - x[ival]) / h
        let dx2 = dx * dx
        let dx3 = dx2 * dx
        let h00 = 2.0 * dx3 - 3.0 * dx2 + 1.0
        let h10 = dx3 - 2.0 * dx2 + dx
        let h01 = -2.0 * dx3 + 3.0 * dx2
        let h11 = dx3 - dx2
        return h00 * y[ival] + h10 * h * m0 + h01 * y[ival + 1] + h11 * h * m1
    }

    /// One force row: the 7 anchors (k/6, y[k]) — commit_params' extra
    /// set_point writes are DEAD (set_point never grows m_numAnchors;
    /// init_pipe added exactly BANDS) — sampled at i/(bands−1), uint16
    /// quantized `val·65535+0.5`, force[k] = q/65536 (draw.h).
    public static func forceRow(_ yRow: [Float]) -> [Float] {
        let bands = DenoiseProfileConsts.bands
        let xs = (0..<bands).map { Float($0) / Float(bands - 1) }
        let ys = Array(yRow.prefix(bands))
        guard let tangents = catmullRomTangents(x: xs, y: ys) else {
            return Array(repeating: 0.5, count: bands)
        }
        return (0..<bands).map { i in
            let v = catmullRomVal(x: xs, y: ys, tangents: tangents, xval: Float(i) / Float(bands - 1))
            let q = max(0, min(65535, Int(v * 65535.0 + 0.5)))
            return Float(q) / 65536.0
        }
    }

    /// All 6×7 force values (commit :2940-2952).
    static func forceCurves(x: [[Float]], y: [[Float]]) -> [[Float]] {
        let bands = DenoiseProfileConsts.bands
        _ = x // knots' x ride the k/6 grid (defaults); the curve consumes y
        return (0..<ForceChannel.count).map { ch in
            forceRow(Array(y[ch].prefix(bands)))
        }
    }

    /// Display sampler for the panel Canvas (CorrectionLUT 同源模式): the
    /// SAME Catmull-Rom the force curve uses, evaluated at `samples`
    /// uniform x positions over [0,1] — the quantized anchors the kernel
    /// consumes are the 7 endpoint values of this family.
    public static func forceCurveSamples(
        yRow: [Float], samples: Int = 64
    ) -> [(x: Float, y: Float)] {
        let bands = DenoiseProfileConsts.bands
        let xs = (0..<bands).map { Float($0) / Float(bands - 1) }
        let ys = Array(yRow.prefix(bands))
        guard samples >= 2, let tangents = catmullRomTangents(x: xs, y: ys) else {
            return (0..<max(samples, 2)).map { (Float($0) / Float(max(samples, 2) - 1), 0.5) }
        }
        return (0..<samples).map { i in
            let xval = Float(i) / Float(samples - 1)
            return (xval, catmullRomVal(x: xs, y: ys, tangents: tangents, xval: xval))
        }
    }

    // MARK: - Bayesshrink (variance_stabilizing_xform :1345-1421)

    static func bayesshrink(
        sumY2: SIMD3<Float>, npixels: Int, scale: Int, maxScale: Int,
        force: [[Float]], modeRGB: Bool
    ) -> SIMD3<Float> {
        // 05-07 note-2 closeout: exact expression — matches WaveletEngine
        // :159 (single-source authority); the 0.5229 rounded literal made
        // the two bayesshrink sources disagree in the last ULPs.
        let varf: Float = (Float(70)).squareRoot() / 16 // sqrt(70)/16 ≈ 0.5229 — sqrt(2+2·16+36)/16
        let sb2 = pow(varf, Float(scale))
        let sb2sq = sb2 * sb2
        let n = Float(max(npixels - 1, 1))
        let varY = SIMD3(sumY2.x / n, sumY2.y / n, sumY2.z / n)
        let stdX = SIMD3(
            sqrt(max(1e-6, varY.x - sb2sq)),
            sqrt(max(1e-6, varY.y - sb2sq)),
            sqrt(max(1e-6, varY.z - sb2sq)))
        let offsetScale = DenoiseProfileConsts.bands - maxScale
        let bandIndex = DenoiseProfileConsts.bands - (scale + offsetScale + 1)
        func f(_ ch: Int) -> Float { force[ch][bandIndex] * force[ch][bandIndex] * 4 }
        var adjt = SIMD3<Float>(repeating: 8.0)
        if modeRGB {
            let all = f(ForceChannel.all.rawValue)
            adjt *= all
            adjt.x *= f(ForceChannel.r.rawValue)
            adjt.y *= f(ForceChannel.g.rawValue)
            adjt.z *= f(ForceChannel.b.rawValue)
        } else {
            adjt.x *= f(ForceChannel.y0.rawValue)
            let uv = f(ForceChannel.u0v0.rawValue)
            adjt.y *= uv
            adjt.z *= uv
        }
        return SIMD3(
            adjt.x * sb2sq / stdX.x, adjt.y * sb2sq / stdX.y, adjt.z * sb2sq / stdX.z)
    }

    // MARK: - Y0U0V0 matrices (set_up_conversion_matrices :1288-1343)

    static func setUpConversionMatrices(wb: SIMD3<Float>)
        -> (fwd: [[Float]], inv: [[Float]]) {
        var m = [
            [Float(1.0 / 3.0), Float(1.0 / 3.0), Float(1.0 / 3.0)],
            [Float(0.5), Float(0), Float(-0.5)],
            [Float(0.25), Float(-0.5), Float(0.25)],
        ]
        var sumInvWb = 1.0 / Double(wb.x) + 1.0 / Double(wb.y) + 1.0 / Double(wb.z)
        sumInvWb *= 3.0.squareRoot()
        m[0][0] = Float(sumInvWb / Double(wb.x))
        m[0][1] = Float(sumInvWb / Double(wb.y))
        m[0][2] = Float(sumInvWb / Double(wb.z))
        let stddevU0 = (0.25 * wb.x * wb.x + 0.25 * wb.z * wb.z).squareRoot()
        let stddevV0 = (0.0625 * wb.x * wb.x + 0.25 * wb.y * wb.y
            + 0.0625 * wb.z * wb.z).squareRoot()
        for c in 0..<3 {
            m[1][c] /= stddevU0
            m[2][c] /= stddevV0
        }
        // invert_matrix (:1250-1284).
        let bigA = m[1][1] * m[2][2] - m[1][2] * m[2][1]
        let bigB = -m[1][0] * m[2][2] + m[1][2] * m[2][0]
        let bigC = m[1][0] * m[2][1] - m[1][1] * m[2][0]
        let bigD = -m[0][1] * m[2][2] + m[0][2] * m[2][1]
        let bigE = m[0][0] * m[2][2] - m[0][2] * m[2][0]
        let bigF = -m[0][0] * m[2][1] + m[0][1] * m[2][0]
        let bigG = m[0][1] * m[1][2] - m[0][2] * m[1][1]
        let bigH = -m[0][0] * m[1][2] + m[0][2] * m[1][0]
        let bigI = m[0][0] * m[1][1] - m[0][1] * m[1][0]
        var det = m[0][0] * bigA + m[0][1] * bigB + m[0][2] * bigC
        if det == 0 {
            // dt fallback :1333-1342 — recompute row 0 with the equal-variance
            // stddev and invert again.
            let stddevY0 = ((wb.x * wb.x + wb.y * wb.y + wb.z * wb.z) / 9).squareRoot()
            m[0] = [1 / (3 * stddevY0), 1 / (3 * stddevY0), 1 / (3 * stddevY0)]
            let a2 = m[1][1] * m[2][2] - m[1][2] * m[2][1]
            let b2 = -m[1][0] * m[2][2] + m[1][2] * m[2][0]
            let c2 = m[1][0] * m[2][1] - m[1][1] * m[2][0]
            let d2 = -m[0][1] * m[2][2] + m[0][2] * m[2][1]
            let e2 = m[0][0] * m[2][2] - m[0][2] * m[2][0]
            let f2 = -m[0][0] * m[2][1] + m[0][1] * m[2][0]
            let g2 = m[0][1] * m[1][2] - m[0][2] * m[1][1]
            let h2 = -m[0][0] * m[1][2] + m[0][2] * m[1][0]
            let i2 = m[0][0] * m[1][1] - m[0][1] * m[1][0]
            det = m[0][0] * a2 + m[0][1] * b2 + m[0][2] * c2
            let inv2 = [
                [1 / det * a2, 1 / det * d2, 1 / det * g2],
                [1 / det * b2, 1 / det * e2, 1 / det * h2],
                [1 / det * c2, 1 / det * f2, 1 / det * i2],
            ]
            return (m, inv2)
        }
        let inv = [
            [1 / det * bigA, 1 / det * bigD, 1 / det * bigG],
            [1 / det * bigB, 1 / det * bigE, 1 / det * bigH],
            [1 / det * bigC, 1 / det * bigF, 1 / det * bigI],
        ]
        return (m, inv)
    }

    /// Flatten + strength-divide/multiply the matrices (:1513-1518) into
    /// the row-major 9-float kernel layout.
    static func kernelMatrices(
        fwd: [[Float]], inv: [[Float]], strength: Float,
        compensateStrength: Float, inScale: Float
    ) -> (fwd9: [Float], inv9: [Float]) {
        var m = fwd, r = inv
        let s = strength * compensateStrength * inScale
        for k in 0..<3 {
            for c in 0..<3 {
                m[k][c] /= s
                r[k][c] *= s
            }
        }
        return (
            m.flatMap { $0 },
            r.flatMap { $0 }
        )
    }

    // MARK: - VST uniforms (process_wavelets :1482-1548 / nlmeans_precondition_cl)

    /// `compensateStrength`: the wavelets leg folds 2.5 in Y0U0V0 mode
    /// (process_wavelets :1511); the NLMeans leg folds NOTHING (dt CPU
    /// nlmeans_precondition :1682-1688 — wb *= strength·scale only). The
    /// dt CPU/CL paths diverge here (the old inline CL path folds 2.5);
    /// the golden authority is the CPU path (dt-cli has no OpenCL).
    static func makeVSTUniforms(
        params: Params, inScale: Float, wbCoeffs: SIMD3<Float>?,
        compensateStrength: Float
    ) -> VSTUniforms {
        let modeRGB = params.waveletColorMode == .rgb
        let compensateP = DenoiseProfileConsts.pFulcrum
            / pow(DenoiseProfileConsts.pFulcrum, params.shadows)
        // Raw wb (pre-strength-fold) for p + matrix derivation.
        var rawWb = wbCoeffs ?? SIMD3<Float>(repeating: 0)
        let mean = (rawWb.x + rawWb.y + rawWb.z) / 3
        rawWb = params.wbAdaptiveAnscombe && mean != 0
            ? (wbCoeffs ?? SIMD3<Float>(repeating: 1))
            : (mean == 0 ? SIMD3<Float>(repeating: 1) : SIMD3(repeating: mean))
        let p = SIMD4<Float>(
            max(params.shadows + 0.1 * logf(inScale / rawWb.x), 0),
            max(params.shadows + 0.1 * logf(inScale / rawWb.y), 0),
            max(params.shadows + 0.1 * logf(inScale / rawWb.z), 0), 0)
        let wbScaled3 = rawWb * (params.strength * compensateStrength * inScale)
        let wbScaled = SIMD4<Float>(wbScaled3.x, wbScaled3.y, wbScaled3.z, 0)
        let aScalar = SIMD4<Float>(repeating: params.a.y * compensateP)
        let bScalar = SIMD4<Float>(repeating: params.b.y)
        let aaLegacy = SIMD4<Float>(params.a.y * wbScaled3.x, params.a.y * wbScaled3.y,
                                    params.a.y * wbScaled3.z, 0)
        let bbLegacy = SIMD4<Float>(params.b.y * wbScaled3.x, params.b.y * wbScaled3.y,
                                    params.b.y * wbScaled3.z, 0)
        let sigma2Legacy = SIMD4<Float>(
            (bbLegacy.x / aaLegacy.x) * (bbLegacy.x / aaLegacy.x),
            (bbLegacy.y / aaLegacy.y) * (bbLegacy.y / aaLegacy.y),
            (bbLegacy.z / aaLegacy.z) * (bbLegacy.z / aaLegacy.z), 0)

        var mFwd9: [Float]?
        var mInv9: [Float]?
        if !modeRGB {
            let (fwd, inv) = setUpConversionMatrices(wb: rawWb)
            (mFwd9, mInv9) = kernelMatrices(
                fwd: fwd, inv: inv, strength: params.strength,
                compensateStrength: compensateStrength, inScale: inScale)
        }
        _ = wbScaled3
        return VSTUniforms(
            aScalar: aScalar, bScalar: bScalar, p: p, wbScaled: wbScaled,
            aaLegacy: aaLegacy, bbLegacy: bbLegacy, sigma2Legacy: sigma2Legacy,
            bias: Double(params.bias), inScale: inScale,
            matrixY0U0V0: mFwd9, matrixToRGB: mInv9)
    }

    // MARK: - Module state

    private let device: (any MTLDevice)?
    private let profiles: NoiseProfileStore
    private var scratch: (WaveletEngine.Scratch, Int, Int)?
    private var committed: Params?
    private var pieceBuffer: (any MTLBuffer)?
    /// The auto-resolved profile from reloadDefaults (dt gui_data.interpolated
    /// mirror) — commit re-resolves via this when the a[0] == −1 sentinel
    /// is present (dt keeps self->dev->image_storage; we keep the resolved
    /// value — commit has no image access in the Lightamer contract).
    private var autoProfile: NoiseProfile?
    private var lastImage: DecodedImage?

    public init(device: (any MTLDevice)? = nil, profiles: NoiseProfileStore = NoiseProfileStore()) {
        self.device = device
        self.profiles = profiles
    }

    // MARK: - Profile resolution (reload_defaults :2667-2739 + :2802-2886)

    /// dt auto profile: exact ISO match → bracket interpolation, with the
    /// whole-EV highlight-pres shift applied to the ISO; miss → generic.
    func resolveAutoProfile(image: DecodedImage, isoOverride: Double?, compensate: Bool) async -> NoiseProfile {
        let exifISO = Double(isoOverride ?? Double(image.capture.iso ?? 0))
        let shift = Self.isoHighlightShift(highlightPreservation: nil) // v1: no metadata source
        let iso = compensate ? exifISO / Double(1 << max(shift, 0)) : exifISO
        let profiles = (try? await self.profiles.matchingProfiles(
            maker: image.capture.cameraMake, model: image.capture.cameraModel)) ?? []
        if profiles.isEmpty { return .generic }
        // Exact match first (dt :2837-2857).
        for p in profiles where p.iso == iso {
            return p
        }
        // Bracket interpolation (dt :2858-2878).
        var last: NoiseProfile?
        for current in profiles {
            if let last, last.iso < iso, current.iso > iso {
                return NoiseProfile.interpolate(last, current, iso: iso)
            }
            last = current
        }
        // Outside the range — dt keeps generic in that case (interpolated
        // initialized to generic; no bracket hit → generic).
        if iso <= profiles.first!.iso { return profiles.first! }
        if iso >= profiles.last!.iso { return profiles.last! }
        return .generic
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        // dt :2691-2700 — autodetected == a profile MATCH exists (dt
        // get_auto_profile flips the flag on an exact/bracket hit); an
        // EXIF maker/model with no table entry resolves generic concrete.
        let matched = (try? await profiles.matchingProfiles(
            maker: image.capture.cameraMake, model: image.capture.cameraModel)) ?? []
        let profile = await resolveAutoProfile(
            image: image, isoOverride: nil, compensate: true)
        autoProfile = profile
        lastImage = image
        let aF = SIMD3<Float>(profile.a)
        let bF = SIMD3<Float>(profile.b)
        if !matched.isEmpty {
            // dt :2698-2700 — the a[0] == −1 sentinel keeps the concrete
            // a1/a2/b alongside; commit re-resolves.
            var p = Params(a: aF, b: bF)
            p.a.x = -1
            return p
        }
        var p = Params()
        p.a = aF
        p.b = bF
        return p
    }

    /// dt `autodetected` = a matching (maker, model) profile list exists.
    /// (Reload path uses the matched list directly — see reloadDefaults.)
    private func isAutoUsable(image: DecodedImage) -> Bool {
        guard let maker = image.capture.cameraMake,
              let model = image.capture.cameraModel else { return false }
        return !maker.isEmpty && !model.isEmpty
    }

    // MARK: - Commit

    /// The commit-effective a/b after the sentinel resolution (commit
    /// :2910-2922). Profiles store Double (JSON authority); the params
    /// domain is Float (dt blob) — convert at this boundary only.
    func resolvedProfile(_ params: Params) -> SIMD3Pair {
        if params.a.x == -1, let auto = autoProfile {
            return SIMD3Pair(a: SIMD3<Float>(auto.a), b: SIMD3<Float>(auto.b))
        }
        return SIMD3Pair(a: params.a, b: params.b)
    }

    public struct SIMD3Pair: Equatable, Sendable {
        public var a: SIMD3<Float>
        public var b: SIMD3<Float>
    }

    /// The commit-effective parameters (AUTO infer + profile resolution) —
    /// the single source both `commitParams` and the tiling seam consume.
    /// AUTO infer runs on the RESOLVED a[1] (dt :2910-2931 — the sentinel
    /// re-resolution lands in d->a BEFORE the infer block).
    func effectiveParams(_ params: Params) -> Params {
        var resolved = params
        let pair = resolvedProfile(params)
        resolved.a = pair.a
        resolved.b = pair.b
        if params.mode == .nlmeansAuto || params.mode == .waveletsAuto {
            let gain = pair.a.y * params.overshooting
            resolved.radius = Float(Self.inferRadius(fromProfile: gain))
            resolved.scattering = Self.inferScattering(fromProfile: gain)
            resolved.shadows = Self.inferShadows(fromProfile: gain)
            resolved.bias = Self.inferBias(fromProfile: gain)
        }
        return resolved
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
        committed = params
        let effective = effectiveParams(params)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        // Uniforms are re-derived per RUN from the committed params (the
        // VST bundle needs roi.scale ÷ iscale — run-level stamps). The
        // piece carries the committed PARAMS snapshot in a small buffer so
        // process can rebuild the uniforms per dispatch.
        if pieceBuffer == nil {
            pieceBuffer = resolved.makeBuffer(
                length: MemoryLayout<Float>.size * 8, options: .storageModeShared)
        }
        if let buffer = pieceBuffer {
            var floats: [Float] = [
                effective.radius, effective.nbhood, effective.strength,
                effective.shadows, effective.bias, effective.scattering,
                effective.centralPixelWeight, effective.overshooting,
            ]
            floats.withUnsafeBytes {
                buffer.contents().copyMemory(
                    from: $0.baseAddress!, byteCount: 8 * MemoryLayout<Float>.size)
            }
        }
        piece.data = pieceBuffer
    }

    // MARK: - Tile seam (tiling_callback :850-908)

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        let params = committed ?? Params()
        let effective = effectiveParams(params)
        switch effective.mode {
        case .nlmeans, .nlmeansAuto:
            // tiling_callback :862-874 verbatim — P and K from the run
            // scale; K_scattered from the RAW scattering.
            let scale = Self.nlMeansScale(roiScale: roi.scale, iscale: piece.iscale)
            let p = Int((effective.radius * scale).rounded(.up))
            let kTile = Int((effective.nbhood * scale).rounded(.up))
            let kScattered = Self.kScattered(
                nbhood: kTile, scattering: effective.scattering)
            return p + kScattered
        default:
            let inScale = Self.waveletsScale(roiScale: roi.scale, iscale: piece.iscale)
            let ms = Self.maxScale(
                width: piece.dscIn.width, height: piece.dscIn.height,
                iscale: piece.iscale, inScale: inScale)
            return 1 << ms
        }
    }

    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        let params = committed ?? Params()
        let effective = effectiveParams(params)
        switch effective.mode {
        case .nlmeans, .nlmeansAuto:
            return 80 // factor_cl 5.0 × 16 (nlmeans group + module VST plane)
        default:
            let inScale = Self.waveletsScale(
                roiScale: piece.processedROIIn.scale, iscale: piece.iscale)
            let ms = Self.maxScale(
                width: piece.dscIn.width, height: piece.dscIn.height,
                iscale: piece.iscale, inScale: inScale)
            return Int((3.5 + Float(ms)) * 16)
        }
    }

    // MARK: - Process

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard piece.data != nil else { return }
        let raw = committed ?? Params()
        let params = effectiveParams(raw)
        let owned = try acquireScratch(width: input.width, height: input.height, metal: metal)
        let npixels = input.width * input.height

        switch params.mode {
        case .wavelets, .waveletsAuto:
            let inScale = Self.waveletsScale(roiScale: roiIn.scale, iscale: piece.iscale)
            let ms = Self.maxScale(
                width: piece.dscIn.width, height: piece.dscIn.height,
                iscale: piece.iscale, inScale: inScale)
            let vst = Self.makeVSTUniforms(
                params: params, inScale: inScale, wbCoeffs: nil,
                compensateStrength: params.waveletColorMode == .rgb ? 1 : 2.5)
            if npixels < 2 {
                try await metal.dispatch2DTexture(
                    functionName: PassthroughKernel.functionName, input: input, output: output)
                return
            }
            let force = Self.forceCurves(x: params.x, y: params.y)
            try await WaveletEngine.wavelets(
                input: input, output: output, maxScale: ms,
                useNewVST: params.useNewVST,
                colorModeRGB: params.waveletColorMode == .rgb,
                vst: vst, force: force, npixels: npixels,
                metal: metal, scratch: owned)
        case .nlmeans, .nlmeansAuto:
            let scale = Self.nlMeansScale(roiScale: roiIn.scale, iscale: piece.iscale)
            let p = Int((params.radius * scale).rounded(.up))
            let vst = Self.makeVSTUniforms(
                params: params, inScale: scale, wbCoeffs: nil,
                compensateStrength: 1)
            let (k, sc) = Self.adjustScattering(
                nbhood: Int(params.nbhood), scattering: params.scattering,
                pipeType: piece.pipeType)
            let norm = Self.nlMeansNorm(P: p, fixNorm: params.fixAnscombeAndNlmeansNorm)
            try await WaveletEngine.nlMeansLeg(
                input: input, output: output,
                useNewVST: params.useNewVST, vst: vst,
                P: p, K: k, scattering: sc, norm: norm,
                centralPixelWeight: params.centralPixelWeight * scale,
                metal: metal, scratch: owned)
        case .variance:
            // D-05-CONTEXT-3: v1 划出 — pass through (UI disables the entry).
            try await metal.dispatch2DTexture(
                functionName: PassthroughKernel.functionName, input: input, output: output)
        }
    }

    private func acquireScratch(
        width: Int, height: Int, metal: MetalContext
    ) throws -> WaveletEngine.Scratch {
        if let (cached, w, h) = scratch, w == width, h == height {
            return cached
        }
        let made = try WaveletEngine.makeScratch(width: width, height: height, metal: metal)
        scratch = (made, width, height)
        return made
    }
}
