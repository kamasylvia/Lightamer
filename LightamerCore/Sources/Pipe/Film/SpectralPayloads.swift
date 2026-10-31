import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// SpectralPayloads — the sf_sim_gpu_t-shaped GPU table carrier of the
// spectral film core (Plan M8-1b T2; the consumption wiring — the
// FilmMethodBox instance lifetime and the nil-payload blit-identity
// degrade — belongs to M8-2; this face ONLY constructs / holds / releases).
//
// CONTENT (the RESEARCH §1.6 carrier list, fed by the M8-1a Float64 build
// engine's SpectralFilmTables):
//   • tc_lut        — the 192² integrated film-exposure table as a
//                     rgba32Float TEXTURE (alpha padded: Metal has no float3
//                     pixel format, review m9); the gather addresses the
//                     ALREADY-COMPRESSED domain (the remap is pre-folded);
//   • two 33³ PCHIP sets (print + scan: lut + per-axis slopes + cmin/cmax)
//     as device float buffers — built once at build time, READ-ONLY at
//     run time (the no-runtime-table-writes discipline);
//   • the film/print develop curves on the shared 256-point axis;
//   • the OkLCh output C_max(L, h) table (64 × 720 — the Float64 bisection
//     port of the upstream build_cmax_table; the engine's table face does
//     not carry it, so the payload builds it — the engine stays zero-diff);
//   • the 93-float constant block (the upstream SF_M_* layout: m_in /
//     m_out / couplers / output rgb2xyz+xyz2rgb / OkLab M1/M2 + inverses /
//     the Langmuir donor+receiver faces) and the uniforms face — every
//     reciprocal in the block is the HOST-double-single-rounding value the
//     engine stored (X5 nail ②: the device never re-derives one);
//   • the corr arm's blur weights (host-normalized separable Gaussian taps).
//
// THE SHARED LOG/EXP POLYNOMIAL (X5 nail ③): `SpectralLogMath` is the
// Swift twin of the kernel's sf_log2f/sf_exp2f/sf_exp2i (the grain.h
// family port) — SAME bare-rounding form, SAME constants, so the host
// float path and the device agree bit-for-bit by construction. The M8-1a
// engine predates this face (its Float64 runtime uses libm on the Double
// side — the golden anchor), which is why the polynomial lives here: the
// plan's "host 侧常量面" for nail ③ lands with the carrier it drives.
//
// RUN-SCOPED LIFETIME: the payload is a per-sim immutable value holder
// (class only because it owns MTLResources); the frame geometry (width /
// height / corr grid) rides `updateFrameGeometry` so M8-2's FilmMethodBox
// instance carrier can rewrite ONE small buffer per run instead of
// rebuilding the tables. `nil` payloads keep the established nil =
// blit-identity degrade semantics (M8-2 consumes; nothing to build here).
// ─────────────────────────────────────────────────────────────────────────────

/// The shared log2/exp2 polynomial pair — the Swift twin of the kernel's
/// sf_log2f/sf_exp2f/sf_exp2i (nail ③; see the kernel file header for the
/// upstream record of WHY: platform built-ins are spec'd to ≤3 ULP and the
/// segment boundaries of the curve lookups amplify that into whole-value
/// differences). The Horner chains are fma-pinned on BOTH sides — the
/// first device run measured the bare spelling diverging (Metal contracts
/// a handful of forms), and the pin restores the by-construction
/// agreement.
public enum SpectralLogMath {

    /// 2^k by writing k into the binary32 exponent field — exact bit
    /// manipulation, no rounding.
    public static func exp2i(_ k: Int) -> Float {
        Float(bitPattern: (UInt32(k + 127)) << 23)
    }

    /// x = k + r, k integer and |r| ≤ 0.5, so 2^x = 2^k·e^(r·ln2) with the
    /// exponential over |t| ≤ 0.347 by a degree-7 Taylor polynomial in
    /// Horner form (fma-pinned — the twin of the kernel's spelling; the
    /// first device run showed Metal contracts some bare forms, so both
    /// sides pin) and 2^k injected exactly.
    public static func exp2f(_ x: Float) -> Float {
        let k = Int(floor(x + 0.5))
        let t = (x - Float(k)) * 0.6931471824645996 /* ln(2) */
        var p: Float = 0.000198412700 /* 1/5040 */
        p = fmaf(p, t, 0.00138888892) /* 1/720 */
        p = fmaf(p, t, 0.00833333377) /* 1/120 */
        p = fmaf(p, t, 0.0416666679) /* 1/24 */
        p = fmaf(p, t, 0.166666672) /* 1/6 */
        p = fmaf(p, t, 0.5)
        p = fmaf(p, t, 1.0)
        p = fmaf(p, t, 1.0)
        return p * exp2i(k)
    }

    /// The binary exponent peeled by hand, the mantissa folded into
    /// [1/√2, √2], then a DIVISION-FREE degree-13 fma-Horner fit of
    /// ln(1+q) over q = m−1 (max measured error 3.2e-8 in ln units; the
    /// kernel twin is the same polynomial — the device division rounds
    /// differently from the host's, and the fit removes the shared face's
    /// only non-deterministic op). The fold steps are exact bit work.
    public static func log2f(_ x: Float) -> Float {
        let xu = x.bitPattern
        var e = Int((xu >> 23) & 0xff) - 127
        var m = Float(bitPattern: (xu & 0x007fffff) | 0x3f800000)
        if m > 1.41421356 { m *= 0.5; e += 1 }
        let q = m - 1.0
        var p: Float = 0.05207313597202301
        p = fmaf(p, q, -0.09844003617763519)
        p = fmaf(p, q, 0.10096900165081024)
        p = fmaf(p, q, -0.09942647814750671)
        p = fmaf(p, q, 0.10994011908769608)
        p = fmaf(p, q, -0.12494739145040512)
        p = fmaf(p, q, 0.14291955530643463)
        p = fmaf(p, q, -0.16667121648788452)
        p = fmaf(p, q, 0.1999983936548233)
        p = fmaf(p, q, -0.24999989569187164)
        p = fmaf(p, q, 0.3333333432674408)
        p = fmaf(p, q, -0.5)
        p = fmaf(p, q, 1.0)
        return fmaf(p * q, 1.4426950216293335, Float(e)) /* log2(e) */
    }

    /// The host's SF_LOG10F form: log2(x) · log10(2) — the scaling
    /// multiply carries its own rounding, which is exactly what makes it
    /// the SAME computation on both sides (the platform log10f would be a
    /// different one).
    public static func log10f(_ x: Float) -> Float {
        log2f(x) * 0.3010299956639812
    }

    /// The host's SF_POW10F form: exp2(x · log2(10)).
    public static func pow10f(_ x: Float) -> Float {
        exp2f(x * 3.321928094887362)
    }

    /// Metal ships no cbrt — the OkLab cube root rides the shared pair:
    /// sign · 2^(log2|x|/3). The sign path keeps the helper total.
    public static func cbrt(_ x: Float) -> Float {
        if x == 0.0 { return x }
        let s: Float = x < 0.0 ? -1.0 : 1.0
        return s * exp2f(log2f(abs(x)) * (Float(1.0) / Float(3.0)))
    }
}

/// The DIR coupler face the corr arm consumes (the upstream
/// sf_sim_t coupler fields, assembled by M8-2's solve face; the neutral
/// default is the couplers-off density chain — corr ≡ 0, both Langmuir
/// gates off).
public struct SpectralCouplerParams: Sendable, Equatable {
    /// The coupler-correction enable (the kernel's SF_U_USE_CORR).
    public var active: Bool
    /// The amount-scaled 3×3 matrix, row donor → column receiver
    /// (the upstream couplers_M layout, row-major 9 floats).
    public var matrix: [Float]
    /// The silver polarity (positive stocks: dmax − d).
    public var positive: Bool
    /// The Langmuir DONOR saturation gate (negative stocks) — the gate is
    /// load-bearing (the K=1e30 sentinel does NOT degenerate to linear in
    /// float; upstream spektrafilm.cl lines 389-404 are the record).
    public var donorLM: Bool
    public var donorK: SIMD3<Float>
    public var donorDref: SIMD3<Float>
    /// The Langmuir RECEIVER saturation gate (positive stocks, applied
    /// AFTER the diffusion blur — the upstream order discipline).
    public var recvLM: Bool
    public var recvKr: SIMD3<Float>
    public var recvCref: SIMD3<Float>
    /// The corr field's separable-Gaussian half-width in corr-grid pixels
    /// (taps = 2·radius+1) and its sigma (same unit) — M8-2 wires the
    /// physical 20 µm face; v1's neutral default is the minimal 1-radius
    /// identity-shaped kernel.
    public var blurRadius: Int
    public var blurSigma: Float

    public init(
        active: Bool = false,
        matrix: [Float] = [Float](repeating: 0, count: 9),
        positive: Bool = false,
        donorLM: Bool = false,
        donorK: SIMD3<Float> = .one,
        donorDref: SIMD3<Float> = .zero,
        recvLM: Bool = false,
        recvKr: SIMD3<Float> = .one,
        recvCref: SIMD3<Float> = .zero,
        blurRadius: Int = 1,
        blurSigma: Float = 1.0
    ) {
        self.active = active
        self.matrix = matrix
        self.positive = positive
        self.donorLM = donorLM
        self.donorK = donorK
        self.donorDref = donorDref
        self.recvLM = recvLM
        self.recvKr = recvKr
        self.recvCref = recvCref
        self.blurRadius = blurRadius
        self.blurSigma = blurSigma
    }

    /// The couplers-off default (the v1 arm until M8-2 wires the solve).
    public static let neutral = SpectralCouplerParams()
}

/// The GPU table carrier (see the file header). Construct once per sim
/// from the build engine's tables; the frame geometry rides
/// `updateFrameGeometry` per run.
public final class SpectralGPUPayloads {

    // MARK: - The ABI faces (the kernel's SF_M_* / SF_U_* mirrors)

    /// The 93-float constant-block offsets (the upstream sf_sim_gpu_t
    /// layout, spektrafilm.cl lines 78-89).
    public enum ConstBlockOffset {
        public static let mIn = 0
        public static let mOut = 9
        public static let couplers = 18
        public static let rgb2xyz = 27
        public static let xyz2rgb = 36
        public static let ok1 = 45
        public static let ok2 = 54
        public static let ok1i = 63
        public static let ok2i = 72
        public static let lmDonor = 81
        public static let lmRecv = 87
        public static let total = 93
    }

    /// The uniforms slots (float-encoded; integer-valued slots are cast at
    /// the use site — no Swift/Metal struct ABI to keep in sync). Slots
    /// 34/35 are the M8-2 EXTENDED face (the frozen kernel family's
    /// SF_U_TOTAL = 34 define belongs to the seven-stage kernels; the
    /// strength-mix kernel reads the additions by literal index).
    public enum UniformSlot {
        public static let width = 0
        public static let height = 1
        public static let tcSide = 2
        public static let steps = 3
        public static let curveCount = 4
        public static let le0 = 5
        public static let invLeStep = 6
        public static let evScale = 7
        public static let log10PrintExposure = 8
        public static let outScale = 9
        public static let dmax = 10
        public static let enlLo = 13
        public static let enlInvRange = 16
        public static let scanLo = 19
        public static let scanInvRange = 22
        public static let positive = 25
        public static let useCorr = 26
        public static let donorLM = 27
        public static let recvLM = 28
        public static let compressMode = 29
        public static let corrW = 30
        public static let corrH = 31
        public static let corrDS = 32
        public static let blurRadius = 33
        /// The M8-2 strength-mix face (the kernel reads u[34]/u[35]).
        public static let mixStrength = 34
        public static let mixGain = 35
        /// M8-3+ T2: the conservation fallback's channel-affine gain
        /// (u[36..38] — the T2 kernels read by literal index; safe
        /// pairs ride ones — the uniform face's identity member).
        public static let midgrayChannelGain = 36
        public static let total = 39
    }

    /// The kernel argument layout (the tests' and M8-2's binding map).
    public enum TextureIndex {
        public static let input = 0
        public static let output = 1
        public static let corr = 2
        public static let tcLut = 3
    }

    public enum BufferIndex {
        public static let curves = 0
        public static let printCurves = 1
        public static let printLut = 2
        public static let printSx = 3
        public static let printSy = 4
        public static let printSz = 5
        public static let printCmin = 6
        public static let printCmax = 7
        public static let scanLut = 8
        public static let scanSx = 9
        public static let scanSy = 10
        public static let scanSz = 11
        public static let scanCmin = 12
        public static let scanCmax = 13
        public static let cmaxTable = 14
        public static let consts = 15
        public static let uniforms = 16
        public static let mode = 17
        public static let blurWeights = 0  // blur kernels' own slot
    }

    /// The OkLCh C_max lattice (the upstream SF_CMAX_NL/NH/NBISECT).
    public enum CmaxTable {
        public static let nL = 64
        public static let nH = 720
        public static let nBisect = 18
        public static let lLo = 0.02
        public static let lHi = 1.0
        public static let count = nL * nH
    }

    // MARK: - The owned GPU resources

    /// The integrated film-exposure table — rgba32Float, side×side,
    /// alpha padded 0 (review m9).
    public let tcLutTexture: any MTLTexture
    public let curvesBuffer: any MTLBuffer
    public let printCurvesBuffer: any MTLBuffer
    public let printLut: any MTLBuffer
    public let printSx: any MTLBuffer
    public let printSy: any MTLBuffer
    public let printSz: any MTLBuffer
    public let printCmin: any MTLBuffer
    public let printCmax: any MTLBuffer
    public let scanLut: any MTLBuffer
    public let scanSx: any MTLBuffer
    public let scanSy: any MTLBuffer
    public let scanSz: any MTLBuffer
    public let scanCmin: any MTLBuffer
    public let scanCmax: any MTLBuffer
    public let cmaxBuffer: any MTLBuffer
    public let constBlockBuffer: any MTLBuffer
    public let uniformsBuffer: any MTLBuffer
    public let blurWeightsBuffer: any MTLBuffer

    /// The corr grid this payload currently targets (0×0 until the frame
    /// geometry arrives — the corr arm is off).
    public private(set) var corrWidth: Int
    public private(set) var corrHeight: Int
    /// The decimation factor the corr grid was derived with.
    public let decimation: Int
    /// The corr blur half-width the weights buffer was built with.
    public let blurRadius: Int
    /// The coupler face this payload was built with (the uniform flags
    /// derive from it; the matrix/Langmuir values ride the const block).
    public let couplers: SpectralCouplerParams
    /// The source tables (the identity face M8-2's cache keys fold).
    public let tables: SpectralFilmTables

    // MARK: - Build

    public init(
        device: any MTLDevice,
        tables: SpectralFilmTables,
        couplers: SpectralCouplerParams = .neutral,
        outputRGBToXYZ: [[Double]] = SpectralConstants.rec2020.rgbToXYZ,
        decimation: Int = 4,
        frameWidth: Int? = nil,
        frameHeight: Int? = nil
    ) throws {
        self.tables = tables
        self.decimation = max(decimation, 1)

        func buffer(_ values: [Float]) throws -> any MTLBuffer {
            guard let b = device.makeBuffer(
                length: values.count * MemoryLayout<Float>.size,
                options: .storageModeShared) else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: buffer allocation")
            }
            values.withUnsafeBytes {
                b.contents().copyMemory(
                    from: $0.baseAddress!, byteCount: $0.count)
            }
            return b
        }
        self.blurRadius = couplers.blurRadius
        self.couplers = couplers

        // ---- the tc texture (rgba32Float, alpha pad — review m9) ----
        let side = tables.tcSide
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: side, height: side, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tcTexture = device.makeTexture(descriptor: desc) else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: tc texture allocation")
        }
        // the upload TRANSPOSES: the engine array is u-major
        // (index = u·side + v) while the kernel's gather addresses texels
        // as (x = u, y = v) — texel(u, v) = array[u·side + v] requires the
        // v-major write order below (the T3 bit-identity battery caught
        // the original linear upload as a transposed gather).
        var tcData = [Float](repeating: 0, count: side * side * 4)
        for u in 0..<side {
            for v in 0..<side {
                let c = tables.tcLut[u * side + v]
                let o = (v * side + u) * 4
                tcData[o + 0] = c.x
                tcData[o + 1] = c.y
                tcData[o + 2] = c.z
                tcData[o + 3] = 0  // the alpha pad
            }
        }
        tcData.withUnsafeBytes {
            tcTexture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(), size: MTLSize(width: side, height: side, depth: 1)),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: side * 4 * MemoryLayout<Float>.size)
        }
        self.tcLutTexture = tcTexture

        // ---- the curve + PCHIP faces (verbatim engine values) ----
        self.curvesBuffer = try buffer(tables.curvesNorm)
        self.printCurvesBuffer = try buffer(tables.printCurves)
        self.printLut = try buffer(tables.print.lut)
        self.printSx = try buffer(tables.print.sx)
        self.printSy = try buffer(tables.print.sy)
        self.printSz = try buffer(tables.print.sz)
        self.printCmin = try buffer(tables.print.cmin)
        self.printCmax = try buffer(tables.print.cmax)
        self.scanLut = try buffer(tables.scan.lut)
        self.scanSx = try buffer(tables.scan.sx)
        self.scanSy = try buffer(tables.scan.sy)
        self.scanSz = try buffer(tables.scan.sz)
        self.scanCmin = try buffer(tables.scan.cmin)
        self.scanCmax = try buffer(tables.scan.cmax)

        // ---- the OkLCh C_max table (the payload-side Float64 builder) ----
        self.cmaxBuffer = try buffer(Self.buildCmaxTable(outputRGBToXYZ: outputRGBToXYZ))

        // ---- the constant block + uniforms ----
        self.constBlockBuffer = try buffer(Self.makeConstBlock(
            tables: tables, couplers: couplers, outputRGBToXYZ: outputRGBToXYZ))
        self.uniformsBuffer = try buffer([Float](repeating: 0, count: UniformSlot.total))
        self.blurWeightsBuffer = try buffer(
            Self.blurWeights(radius: couplers.blurRadius, sigma: couplers.blurSigma))

        // ---- the frame geometry ----
        let w = frameWidth ?? 0, h = frameHeight ?? 0
        self.corrWidth = Self.corrDimension(width: w, decimation: self.decimation)
        self.corrHeight = Self.corrDimension(width: h, decimation: self.decimation)
        self.updateFrameGeometry(width: w, height: h)
    }

    deinit {
        // The MTLResources are ARC'd — the explicit face documents the
        // release semantics (the "载体失效面" the plan names): dropping the
        // payload releases every table; M8-2's per-run carrier just lets
        // the instance go.
    }

    /// The corr grid dimension = ceil(width / decimation).
    public static func corrDimension(width: Int, decimation: Int) -> Int {
        guard width > 0, decimation > 0 else { return 0 }
        return (width + decimation - 1) / decimation
    }

    /// Rewrite the per-run frame geometry into the uniforms buffer (the
    /// M8-2 instance-carrier face: one small shared-storage write, the
    /// tables untouched — the read-only-table discipline holds). The
    /// session tuning slots are RESET here — `applySessionTuning` re-applies
    /// them after this when a run carries one.
    public func updateFrameGeometry(width: Int, height: Int) {
        let newW = Self.corrDimension(width: width, decimation: decimation)
        let newH = Self.corrDimension(width: height, decimation: decimation)
        uniformShadow = [Float](repeating: 0, count: UniformSlot.total)
        uniformShadow[UniformSlot.width] = Float(width)
        uniformShadow[UniformSlot.height] = Float(height)
        uniformShadow[UniformSlot.tcSide] = Float(tables.tcSide)
        uniformShadow[UniformSlot.steps] = Float(SpectralFilmPchipSet.steps)
        uniformShadow[UniformSlot.curveCount] = Float(tables.curvesNorm.count / 3)
        uniformShadow[UniformSlot.le0] = tables.le0
        uniformShadow[UniformSlot.invLeStep] = tables.invLeStep  // nail ②: the stored value
        uniformShadow[UniformSlot.evScale] = tables.evScale      // ≡ 1 (D-M8-8)
        uniformShadow[UniformSlot.log10PrintExposure] = tables.log10PrintExposure
        uniformShadow[UniformSlot.outScale] = 1.0
        uniformShadow[UniformSlot.dmax + 0] = tables.filmDmax.x
        uniformShadow[UniformSlot.dmax + 1] = tables.filmDmax.y
        uniformShadow[UniformSlot.dmax + 2] = tables.filmDmax.z
        uniformShadow[UniformSlot.enlLo + 0] = tables.enlLo.x
        uniformShadow[UniformSlot.enlLo + 1] = tables.enlLo.y
        uniformShadow[UniformSlot.enlLo + 2] = tables.enlLo.z
        uniformShadow[UniformSlot.enlInvRange + 0] = tables.enlInvRange.x  // nail ②
        uniformShadow[UniformSlot.enlInvRange + 1] = tables.enlInvRange.y
        uniformShadow[UniformSlot.enlInvRange + 2] = tables.enlInvRange.z
        uniformShadow[UniformSlot.scanLo + 0] = tables.scanLo.x
        uniformShadow[UniformSlot.scanLo + 1] = tables.scanLo.y
        uniformShadow[UniformSlot.scanLo + 2] = tables.scanLo.z
        uniformShadow[UniformSlot.scanInvRange + 0] = tables.scanInvRange.x  // nail ②
        uniformShadow[UniformSlot.scanInvRange + 1] = tables.scanInvRange.y
        uniformShadow[UniformSlot.scanInvRange + 2] = tables.scanInvRange.z
        uniformShadow[UniformSlot.positive] = couplers.positive ? 1 : 0
        uniformShadow[UniformSlot.useCorr] = (couplers.active && newW > 0) ? 1 : 0
        uniformShadow[UniformSlot.donorLM] = couplers.donorLM ? 1 : 0
        uniformShadow[UniformSlot.recvLM] = couplers.recvLM ? 1 : 0
        uniformShadow[UniformSlot.compressMode] = 1  // OkLCh (the only v1 mode)
        uniformShadow[UniformSlot.corrW] = Float(newW)
        uniformShadow[UniformSlot.corrH] = Float(newH)
        uniformShadow[UniformSlot.corrDS] = Float(decimation)
        uniformShadow[UniformSlot.blurRadius] = Float(blurRadius)
        // M8-3+ T2: the fallback gain rides the geometry reset (safe
        // pairs = ones — the reset's own identity member).
        uniformShadow[UniformSlot.midgrayChannelGain + 0] = tables.midgrayChannelGain.x
        uniformShadow[UniformSlot.midgrayChannelGain + 1] = tables.midgrayChannelGain.y
        uniformShadow[UniformSlot.midgrayChannelGain + 2] = tables.midgrayChannelGain.z
        uploadUniforms()
        self.corrWidth = newW
        self.corrHeight = newH
    }

    /// The Swift-side uniform mirror (the single upload source —
    /// `updateFrameGeometry` rewrites it wholesale, `applySessionTuning`
    /// mutates the session slots in place and re-uploads once).
    private var uniformShadow: [Float] = []

    private func uploadUniforms() {
        uniformShadow.withUnsafeBytes {
            uniformsBuffer.contents().copyMemory(
                from: $0.baseAddress!, byteCount: UniformSlot.total * MemoryLayout<Float>.stride)
        }
    }

    /// Per-run session tuning (M8-2, the film leg's spectral arm) — written
    /// AFTER `updateFrameGeometry`:
    ///
    ///   • the solved session gain (the auto normalization × 2^exposureEv —
    ///     D-M8-8's solve-gain consumption layer) rides the PRINT-exposure
    ///     slot: `log10_print_exposure += log10(gain)` lands in the
    ///     kernel's `l1 + pe` add (the 印相曝光归一 face — the expose chain
    ///     head's ev_scale stays ≡ 1 by construction);
    ///   • the manual + content-adaptive CC deltas ride the E3
    ///     filter-vector form: `enl_lo[1] += kM`, `enl_lo[2] += kY` — the
    ///     print-table INPUT-coordinate density shift, the exact algebraic
    ///     twin of the frozen density kernel's `density.g -= kM` before
    ///     its print LUT (the E3 channel mapping: Magenta → GREEN,
    ///     Yellow → BLUE; the build's own neutral CC rides the tables via
    ///     the solved dichroic light, so only the deltas shift here);
    ///   • the strength-mix slots (34/35) carry the mix kernel's face.
    ///
    /// All values arrive in float (the caller's conversion face — the
    /// Float64 solve values rounded once at the Params face).
    public func applySessionTuning(
        exposureGain: Float, kM: Float, kY: Float, strength: Float
    ) {
        uniformShadow[UniformSlot.log10PrintExposure] +=
            Float(Foundation.log10(Double(max(exposureGain, 1e-6))))
        uniformShadow[UniformSlot.enlLo + 1] += kM
        uniformShadow[UniformSlot.enlLo + 2] += kY
        uniformShadow[UniformSlot.mixStrength] = strength
        uniformShadow[UniformSlot.mixGain] = exposureGain
        uploadUniforms()
    }

    // MARK: - The M8-2 production dispatch chain (the film leg's spectral arm)

    /// The full spectral film chain for ONE run (X3's dispatch form):
    /// stage A (expose + lograw + develop_corr at the decimated grid) →
    /// the separable blur pair (ping-pong) → stage B (develop + print +
    /// scan, sampling the blurred corr bilinearly) → the strength mix when
    /// the document's strength < 1 (the RFC-025 density-domain blend — at
    /// strength >= 1 stage B writes the OUTPUT directly, so the default
    /// face is the bitwise-raw chain). The corr arm leg runs ONLY when the
    /// coupler face is active (`use_corr`) — the neutral couplers-off face
    /// skips A + blur entirely (the corr field would be identically zero:
    /// zero matrix → develop_corr ≡ 0 → develop subtracts nothing; the
    /// skip is value-identical and holds the H-M2 memory posture).
    ///
    /// The per-run corr planes are allocated here (run-scoped — never
    /// cached beyond the call); the tables stay read-only throughout.
    ///
    /// The CC face (the T5 golden's catch): `magentaCC`/`yellowCC` are the
    /// SOLVED session totals (the density arm's Solution shape), but the
    /// spectral tables ALREADY carry the build's own neutral CC (the solved
    /// dichroic light baked into the print leg), so the runtime shift is
    /// the DELTA against the build's operating point (`tables
    /// .solvedPrintCC`) — the density arm folds the whole pack into its
    /// LUT's inverted coordinate system (the kernel subtracts the TOTAL),
    /// the spectral arm folds it into the light (the runtime shifts only
    /// the deltas); double-applying the neutral pair was the first
    /// integration's real defect (the T5 ramp golden caught it).
    public func dispatchFilmChain(
        input: any MTLTexture, output: any MTLTexture, metal: MetalContext,
        exposureGain: Float, magentaCC: Float, yellowCC: Float, strength: Float
    ) async throws {
        precondition(
            input.width == output.width && input.height == output.height,
            "the film chain writes a same-shape plane")
        let kM = (Double(magentaCC) - Double(tables.solvedPrintCC.y))
            * FilmFilterPackSolver.magentaExposurePerCC
        let kY = (Double(yellowCC) - Double(tables.solvedPrintCC.z))
            * FilmFilterPackSolver.yellowExposurePerCC
        updateFrameGeometry(width: input.width, height: input.height)
        applySessionTuning(exposureGain: exposureGain, kM: Float(kM), kY: Float(kY),
                           strength: strength)
        let w = input.width, h = input.height
        let useCorr = couplers.active && corrWidth > 0 && corrHeight > 0
        // The strength<1 path needs stage B's raw output as a MIX SOURCE —
        // stage B then targets an intermediate and the mix kernel blends
        // against the original input. At strength >= 1 B targets the
        // output directly (no intermediate ever exists — the default
        // face's memory posture).
        let wantsMix = strength < 1.0
        let stageBTarget: any MTLTexture
        if wantsMix {
            guard let intermediate = try Self.makeReadWriteTexture(
                metal: metal, width: w, height: h)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: mix intermediate allocation")
            }
            stageBTarget = intermediate
        } else {
            stageBTarget = output
        }

        if useCorr {
            let cw = corrWidth, ch = corrHeight
            guard let corrA = try Self.makeReadWriteTexture(metal: metal, width: cw, height: ch),
                let corrB = try Self.makeReadWriteTexture(metal: metal, width: cw, height: ch)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: corr plane allocation")
            }
            // A: the decimated-grid corr generation (box-averages its ds×ds
            // source block — the downsample IS the write pattern).
            let sessionA = try await metal.makeEncoder(functionName: "spectral_film_stage_a")
            sessionA.encoder.setTexture(input, index: SpectralGPUPayloads.TextureIndex.input)
            sessionA.encoder.setTexture(corrA, index: 1)
            sessionA.encoder.setTexture(tcLutTexture, index: 2)  // the A-face tc slot
            sessionA.encoder.setBuffer(curvesBuffer, offset: 0, index: 0)
            sessionA.encoder.setBuffer(constBlockBuffer, offset: 0, index: 1)
            sessionA.encoder.setBuffer(uniformsBuffer, offset: 0, index: 2)
            sessionA.encoder.dispatchThreads(
                MTLSize(width: cw, height: ch, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            sessionA.encoder.endEncoding()
            sessionA.commandBuffer.commit()
            await sessionA.commandBuffer.completed()
            // The separable blur pair, ping-pong (row → col; the blurred
            // field lands back in corrA).
            for (kernel, src, dst) in [
                ("spectral_film_blur_row", corrA, corrB),
                ("spectral_film_blur_col", corrB, corrA),
            ] {
                let blur = try await metal.makeEncoder(functionName: kernel)
                blur.encoder.setTexture(src, index: 0)
                blur.encoder.setTexture(dst, index: 1)
                blur.encoder.setBuffer(blurWeightsBuffer, offset: 0, index: 0)
                blur.encoder.setBuffer(uniformsBuffer, offset: 0, index: 2)
                blur.encoder.dispatchThreads(
                    MTLSize(width: cw, height: ch, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                blur.encoder.endEncoding()
                blur.commandBuffer.commit()
                await blur.commandBuffer.completed()
            }
            try await dispatchStageB(
                input: input, output: stageBTarget, corr: corrA, metal: metal)
        } else {
            // The couplers-off face: B only. The corr slot binds the tc
            // texture as a never-read placeholder (the kernel guards on
            // use_corr = 0 before touching it).
            try await dispatchStageB(
                input: input, output: stageBTarget, corr: tcLutTexture, metal: metal)
        }

        if wantsMix {
            let mix = try await metal.makeEncoder(functionName: "spectral_film_strength_mix")
            mix.encoder.setTexture(stageBTarget, index: 0)
            mix.encoder.setTexture(input, index: 1)
            mix.encoder.setTexture(output, index: 2)
            mix.encoder.setBuffer(uniformsBuffer, offset: 0, index: 0)
            mix.encoder.dispatchThreads(
                MTLSize(width: w, height: h, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            mix.encoder.endEncoding()
            mix.commandBuffer.commit()
            await mix.commandBuffer.completed()
        }
    }

    /// Stage B (the fused tail: develop + print_expose + print_develop +
    /// scan; the corr field rides texture 2 per the kernel ABI).
    private func dispatchStageB(
        input: any MTLTexture, output: any MTLTexture,
        corr: any MTLTexture, metal: MetalContext
    ) async throws {
        let sessionB = try await metal.makeEncoder(functionName: "spectral_film_stage_b")
        sessionB.encoder.setTexture(input, index: SpectralGPUPayloads.TextureIndex.input)
        sessionB.encoder.setTexture(output, index: SpectralGPUPayloads.TextureIndex.output)
        sessionB.encoder.setTexture(corr, index: SpectralGPUPayloads.TextureIndex.corr)
        sessionB.encoder.setTexture(tcLutTexture, index: SpectralGPUPayloads.TextureIndex.tcLut)
        let buffers: [any MTLBuffer] = [
            curvesBuffer, printCurvesBuffer,
            printLut, printSx, printSy, printSz, printCmin, printCmax,
            scanLut, scanSx, scanSy, scanSz, scanCmin, scanCmax,
            cmaxBuffer, constBlockBuffer, uniformsBuffer,
        ]
        for (index, buffer) in buffers.enumerated() {
            sessionB.encoder.setBuffer(buffer, offset: 0, index: index)
        }
        sessionB.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        sessionB.encoder.endEncoding()
        sessionB.commandBuffer.commit()
        await sessionB.commandBuffer.completed()
    }

    /// A read/write rgba32Float plane (the run-scoped corr + mix faces).
    private static func makeReadWriteTexture(
        metal: MetalContext, width: Int, height: Int
    ) throws -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: max(width, 1), height: max(height, 1),
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        return metal.device.makeTexture(descriptor: descriptor)
    }

    // MARK: - The host-side block builders (the T3 upload/round-trip faces)

    /// The 93-float constant block. Every reciprocal in it is a
    /// host-double-single-rounding value (nail ②); the plain output
    /// RGB↔XYZ pair and the OkLab inverses are payload-side Float64
    /// derivations (the engine's table face does not carry them — the
    /// engine stays zero-diff).
    public static func makeConstBlock(
        tables: SpectralFilmTables,
        couplers: SpectralCouplerParams,
        outputRGBToXYZ: [[Double]]
    ) -> [Float] {
        var c = [Float](repeating: 0, count: ConstBlockOffset.total)
        func put(_ offset: Int, _ m: [[Float]]) {
            for r in 0..<3 { for k in 0..<3 { c[offset + r * 3 + k] = m[r][k] } }
        }
        func putD(_ offset: Int, _ m: [[Double]]) {
            for r in 0..<3 { for k in 0..<3 { c[offset + r * 3 + k] = Float(m[r][k]) } }
        }
        put(ConstBlockOffset.mIn, tables.mIn)
        put(ConstBlockOffset.mOut, tables.mOut)
        for i in 0..<9 { c[ConstBlockOffset.couplers + i] = couplers.matrix[i] }
        putD(ConstBlockOffset.rgb2xyz, outputRGBToXYZ)
        putD(ConstBlockOffset.xyz2rgb, SpectralConstants.inverse3(outputRGBToXYZ))
        putD(ConstBlockOffset.ok1, SpectralConstants.oklabM1)
        putD(ConstBlockOffset.ok2, SpectralConstants.oklabM2)
        putD(ConstBlockOffset.ok1i, SpectralConstants.inverse3(SpectralConstants.oklabM1))
        putD(ConstBlockOffset.ok2i, SpectralConstants.inverse3(SpectralConstants.oklabM2))
        // the Langmuir faces with the ZERO sentinel (the upstream build
        // rule: a zero K/Kr — an all-zero matrix column, or a pack
        // shipping langmuir_*_k_rgb == 0 — would evaluate c*(K+cref)/
        // (K+c) as 0*0/0 for every pixel and NaN through the table; the
        // linear sentinel passes the inhibitor through unchanged):
        // K == 0 → 1e30 at the BLOCK face, so the kernel never sees the
        // degenerate denominator (X3's NaN defense).
        func sentinel(_ v: Float) -> Float { v == 0 ? 1e30 : v }
        c[ConstBlockOffset.lmDonor + 0] = sentinel(couplers.donorK.x)
        c[ConstBlockOffset.lmDonor + 1] = sentinel(couplers.donorK.y)
        c[ConstBlockOffset.lmDonor + 2] = sentinel(couplers.donorK.z)
        c[ConstBlockOffset.lmDonor + 3] = couplers.donorDref.x
        c[ConstBlockOffset.lmDonor + 4] = couplers.donorDref.y
        c[ConstBlockOffset.lmDonor + 5] = couplers.donorDref.z
        c[ConstBlockOffset.lmRecv + 0] = sentinel(couplers.recvKr.x)
        c[ConstBlockOffset.lmRecv + 1] = sentinel(couplers.recvKr.y)
        c[ConstBlockOffset.lmRecv + 2] = sentinel(couplers.recvKr.z)
        c[ConstBlockOffset.lmRecv + 3] = couplers.recvCref.x
        c[ConstBlockOffset.lmRecv + 4] = couplers.recvCref.y
        c[ConstBlockOffset.lmRecv + 5] = couplers.recvCref.z
        return c
    }

    /// The OkLCh C_max(L, h) table — the Float64 bisection port of the
    /// upstream build_cmax_table (18 iterations per cell, the in-cube test
    /// with the ±1e-6 tolerance, L clamped [0.02, 1], h wrapped over
    /// [−π, π)). Runs once per payload build.
    public static func buildCmaxTable(outputRGBToXYZ: [[Double]]) -> [Float] {
        let nl = CmaxTable.nL, nh = CmaxTable.nH
        let xyz2rgb = SpectralConstants.inverse3(outputRGBToXYZ)
        let m1 = SpectralConstants.oklabM1
        let m2 = SpectralConstants.oklabM2
        let m1i = SpectralConstants.inverse3(m1)
        let m2i = SpectralConstants.inverse3(m2)
        var table = [Float](repeating: 0, count: nl * nh)
        for i in 0..<nl {
            let l = CmaxTable.lLo
                + (CmaxTable.lHi - CmaxTable.lLo) * Double(i) / Double(nl - 1)
            for j in 0..<nh {
                let h = -Double.pi + 2.0 * Double.pi * Double(j) / Double(nh)
                let ch = cos(h), sh = sin(h)
                var lo = 0.0, hi = 0.5
                for _ in 0..<CmaxTable.nBisect {
                    let mid = 0.5 * (lo + hi)
                    let lab = SIMD3<Double>(l, mid * ch, mid * sh)
                    var lms = m2i.multiplyVector(lab)
                    lms = lms * lms * lms
                    let xyz = m1i.multiplyVector(lms)
                    let rgb = xyz2rgb.multiplyVector(xyz)
                    let inGamut = rgb.x >= -1e-6 && rgb.x <= 1.0 + 1e-6
                        && rgb.y >= -1e-6 && rgb.y <= 1.0 + 1e-6
                        && rgb.z >= -1e-6 && rgb.z <= 1.0 + 1e-6
                    if inGamut { lo = mid } else { hi = mid }
                }
                table[i * nh + j] = Float(lo)
            }
        }
        return table
    }

    /// The host-normalized separable Gaussian taps (2·radius+1, sum = 1 —
    /// the exact-Gaussian convention the CPU blur shares).
    public static func blurWeights(radius: Int, sigma: Float) -> [Float] {
        let r = max(radius, 0)
        var weights = (0..<(2 * r + 1)).map { i -> Double in
            let x = Double(i - r)
            let s = Double(max(sigma, 1e-6))
            return exp(-x * x / (2.0 * s * s))
        }
        let sum = weights.reduce(0, +)
        weights = weights.map { $0 / sum }
        return weights.map(Float.init)
    }

    // MARK: - The structural volume face (the RESEARCH §4.1 order)

    /// The carrier's own byte volume (the tables' packed face + the cmax
    /// lattice + the constant/uniform/weights faces).
    public var carrierByteCount: Int {
        let float4Bytes = tables.tcLut.count * 4 * MemoryLayout<Float>.size
        let pchipBytes = { (set: SpectralFilmPchipSet) -> Int in
            (set.lut.count + set.sx.count + set.sy.count + set.sz.count
                + set.cmin.count + set.cmax.count) * MemoryLayout<Float>.size
        }
        return float4Bytes
            + pchipBytes(tables.print) + pchipBytes(tables.scan)
            + (tables.curvesNorm.count + tables.printCurves.count)
                * MemoryLayout<Float>.size
            + CmaxTable.count * MemoryLayout<Float>.size
            + ConstBlockOffset.total * MemoryLayout<Float>.size
            + UniformSlot.total * MemoryLayout<Float>.size
            + blurWeightsLength * MemoryLayout<Float>.size
    }

    /// The blur tap count the weights buffer was built with.
    public var blurWeightsLength: Int {
        let bytes = blurWeightsBuffer.length
        return bytes / MemoryLayout<Float>.size
    }
}
