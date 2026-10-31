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
        /// M8-3+ T5: the B2 print-diffusion hook (u[39..41] — the gate
        /// amount + the two reserved seats; 0 = the hook off —
        /// off-identity by construction).
        public static let printDiffusion = 39
        public static let total = 42
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
    /// M8-3+ T5 self-review E3: the film's published diffuse RMS
    /// (the grain npart's inversion anchor; nil = unknown).
    public let publishedRms: Int?
    // MARK: - Build

    public init(
        device: any MTLDevice,
        tables: SpectralFilmTables,
        couplers: SpectralCouplerParams = .neutral,
        outputRGBToXYZ: [[Double]] = SpectralConstants.rec2020.rgbToXYZ,
        decimation: Int = 4,
        frameWidth: Int? = nil,
        frameHeight: Int? = nil,
        // M8-3+ T5 self-review E3: the film's published diffuse RMS
        // (the 1000× achromatic figure; nil = unknown — the grain
        // npart degrades per-channel, never invented).
        publishedRms: Int? = nil
    ) throws {
        self.tables = tables
        self.publishedRms = publishedRms
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
        // M8-3+ T5: the print-diffusion hook rides the geometry reset
        // (zeros — the hook off; the T5 leg arms it per-run).
        uniformShadow[UniformSlot.printDiffusion + 0] = 0
        uniformShadow[UniformSlot.printDiffusion + 1] = 0
        uniformShadow[UniformSlot.printDiffusion + 2] = 0
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
        exposureGain: Float, magentaCC: Float, yellowCC: Float, strength: Float,
        grainAmount: Float? = nil, halationAmount: Float? = nil,
        diffusionFamily: String? = nil, diffusionAmount: Float? = nil,
        scratch: SpectralScratchAllocator.Slot? = nil
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
        // The E-acc1 run slot: the entry owns ONE Slot per run and
        // threads it down both segments (pre-leg → release → stage B;
        // an injected slot lets tests read the accounting face).
        let runScratch = scratch ?? SpectralScratchAllocator.Slot()
        let w = input.width, h = input.height
        // M8-3+ T5: the spatial pre-leg (taking diffusion → halation —
        // the upstream order verbatim) runs on a COPY of the input when
        // armed (nil legs = skipped, zero dispatches — the off-identity
        // is structural). The chain below reads `chainInput`.
        let chainInput: any MTLTexture
        if halationAmount != nil || diffusionFamily != nil {
            guard let preCopy = try Self.makeReadWriteTexture(
                metal: metal, width: w, height: h)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: pre-leg plane allocation")
            }
            if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
                let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(
                    from: input, sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: w, height: h, depth: 1),
                    to: preCopy, destinationSlice: 0, destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blit.endEncoding()
                commandBuffer.commit()
                await commandBuffer.completed()
            }
            try await dispatchSpatialPreLeg(
                plane: preCopy, halationAmount: halationAmount,
                diffusionFamily: diffusionFamily,
                diffusionAmount: diffusionAmount, metal: metal,
                scratch: runScratch)
            chainInput = preCopy
        } else {
            chainInput = input
        }
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
            sessionA.encoder.setTexture(chainInput, index: SpectralGPUPayloads.TextureIndex.input)
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
                input: chainInput, output: stageBTarget, corr: corrA, metal: metal,
                grainAmount: grainAmount, scratch: runScratch)
        } else {
            // The couplers-off face: B only. The corr slot binds the tc
            // texture as a never-read placeholder (the kernel guards on
            // use_corr = 0 before touching it).
            try await dispatchStageB(
                input: chainInput, output: stageBTarget, corr: tcLutTexture, metal: metal,
                grainAmount: grainAmount, scratch: runScratch)
        }

        if wantsMix {
            let mix = try await metal.makeEncoder(functionName: "spectral_film_strength_mix")
            mix.encoder.setTexture(stageBTarget, index: 0)
            mix.encoder.setTexture(chainInput, index: 1)
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

    /// Stage B1 → grain group → stage B2 (M8-3+ T4: the fused stage B is
    /// retired — B1 writes the developed CMY density, the grain group
    /// runs on it when armed (nil = skipped, zero dispatches — the
    /// off-identity is structural, not a kernel gate), B2 resumes at
    /// print_expose. The corr field rides texture 2 per the kernel ABI.)
    /// The E-acc1 scratch face: the run's Slot threads through the leg
    /// dispatches (default nil = independent allocation, the legacy face).
    /// The holder segment is .stageB2 for the whole B1→grain→B2 span:
    /// the B1 CMY plane borrows FIRST and stays live through grain + B2
    /// (grain's working set top-ups with the same leg — the pool's
    /// same-holder re-entry — and releases BEFORE the CMY plane does).
    private func dispatchStageB(
        input: any MTLTexture, output: any MTLTexture,
        corr: any MTLTexture, metal: MetalContext,
        grainAmount: Float? = nil,
        scratch: SpectralScratchAllocator.Slot? = nil
    ) async throws {
        // The B1 CMY plane (the pool's .stageB2 face — live across the
        // whole span; nil scratch = the legacy independent face).
        let cmyPlane: any MTLTexture
        if let scratch {
            guard let borrowed = try scratch.borrowPlanes(
                .stageB2, device: metal.device, count: 1,
                width: input.width, height: input.height),
                let plane = borrowed.first
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: B1 CMY plane allocation")
            }
            cmyPlane = plane
        } else if let plane = try Self.makeReadWriteTexture(
            metal: metal, width: input.width, height: input.height)
        {
            cmyPlane = plane
        } else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: B1 CMY plane allocation")
        }
        do {
            try await dispatchStageB1(
                input: input, output: cmyPlane, corr: corr, metal: metal)
            // The zero face: amount == 0 skips the group (the on-identity —
            // upstream's own `grain_amount > 0` gate: a zero-delta add would
            // still blur+USM the clean density, which is NOT the identity).
            if let amount = grainAmount, amount != 0 {
                try await dispatchGrainGroup(
                    density: cmyPlane, amount: amount, metal: metal,
                    scratch: scratch)
            }
            try await dispatchStageB2(
                input: cmyPlane, output: output, corr: corr, metal: metal)
        }
        if let scratch {
            scratch.releasePlanes([cmyPlane])
        }
    }

    /// Stage B1 (expose + lograw + develop → the CMY density plane).
    private func dispatchStageB1(
        input: any MTLTexture, output: any MTLTexture,
        corr: any MTLTexture, metal: MetalContext
    ) async throws {
        let session = try await metal.makeEncoder(
            functionName: "spectral_film_stage_b1")
        session.encoder.setTexture(input, index: SpectralGPUPayloads.TextureIndex.input)
        session.encoder.setTexture(output, index: SpectralGPUPayloads.TextureIndex.output)
        session.encoder.setTexture(corr, index: SpectralGPUPayloads.TextureIndex.corr)
        session.encoder.setTexture(tcLutTexture, index: SpectralGPUPayloads.TextureIndex.tcLut)
        let buffers: [any MTLBuffer] = [
            curvesBuffer, printCurvesBuffer,
            printLut, printSx, printSy, printSz, printCmin, printCmax,
            scanLut, scanSx, scanSy, scanSz, scanCmin, scanCmax,
            cmaxBuffer, constBlockBuffer, uniformsBuffer,
        ]
        for (index, buffer) in buffers.enumerated() {
            session.encoder.setBuffer(buffer, offset: 0, index: index)
        }
        session.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()
    }

    /// Stage B2 (print_expose + print_develop + scan → the display RGB).
    private func dispatchStageB2(
        input: any MTLTexture, output: any MTLTexture,
        corr: any MTLTexture, metal: MetalContext
    ) async throws {
        let session = try await metal.makeEncoder(
            functionName: "spectral_film_stage_b2")
        session.encoder.setTexture(input, index: SpectralGPUPayloads.TextureIndex.input)
        session.encoder.setTexture(output, index: SpectralGPUPayloads.TextureIndex.output)
        session.encoder.setTexture(corr, index: SpectralGPUPayloads.TextureIndex.corr)
        session.encoder.setTexture(tcLutTexture, index: SpectralGPUPayloads.TextureIndex.tcLut)
        let buffers: [any MTLBuffer] = [
            curvesBuffer, printCurvesBuffer,
            printLut, printSx, printSy, printSz, printCmin, printCmax,
            scanLut, scanSx, scanSy, scanSz, scanCmin, scanCmax,
            cmaxBuffer, constBlockBuffer, uniformsBuffer,
        ]
        for (index, buffer) in buffers.enumerated() {
            session.encoder.setBuffer(buffer, offset: 0, index: index)
        }
        session.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        await session.commandBuffer.completed()
    }

    /// The grain group (M8-3+ T4): gen_raw_sl × 3 channels (reset
    /// accumulate each) → finalize × 3 → add → clump blur (row+col on
    /// the combined field) → USM. Single-sublayer face. All run-scoped.
    /// The E-acc1 face: the working set borrows from the run Slot with
    /// the SAME .stageB2 leg (the stage-B span's holder — the top-up
    /// re-entry) and releases before stage B's CMY plane does. The tiny
    /// param/curve/roi/weights buffers stay direct (≤256 floats — pool
    /// traffic for bytes, kernel-by-kernel allocation by design).
    private func dispatchGrainGroup(
        density: any MTLTexture, amount: Float, metal: MetalContext,
        scratch: SpectralScratchAllocator.Slot? = nil
    ) async throws {
        let w = density.width, h = density.height
        let rows = Self.sublayerRowsForGrain(
            curvesNorm: tables.curvesNorm, filmDmax: tables.filmDmax,
            filmDmin: tables.filmDmin, publishedRms: publishedRms)
        let wh = w * h
        let floatBytes = MemoryLayout<Float>.size
        let rawBuffer: any MTLBuffer
        let accBuffer: any MTLBuffer
        let grainBuffer: any MTLBuffer
        var borrowedBuffers: [any MTLBuffer] = []
        if let scratch {
            guard let borrowed = try scratch.borrowBuffers(
                .stageB2, device: metal.device,
                byteLengths: [wh * floatBytes, wh * floatBytes,
                              wh * 4 * floatBytes]),
                borrowed.count == 3
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: grain buffer allocation")
            }
            rawBuffer = borrowed[0]
            accBuffer = borrowed[1]
            grainBuffer = borrowed[2]
            borrowedBuffers = borrowed
        } else {
            guard let raw = metal.device.makeBuffer(
                length: wh * floatBytes, options: .storageModeShared),
                let acc = metal.device.makeBuffer(
                    length: wh * floatBytes, options: .storageModeShared),
                let grain = metal.device.makeBuffer(
                    length: wh * 4 * floatBytes, options: .storageModeShared)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: grain buffer allocation")
            }
            rawBuffer = raw
            accBuffer = acc
            grainBuffer = grain
        }
        defer {
            if !borrowedBuffers.isEmpty {
                scratch?.releaseBuffers(borrowedBuffers)
            }
        }
        func paramBuffer(_ values: [Float]) throws -> any MTLBuffer {
            guard let buffer = metal.device.makeBuffer(
                bytes: values,
                length: values.count * MemoryLayout<Float>.size,
                options: .storageModeShared)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: grain param allocation")
            }
            return buffer
        }
        var roiValues: [UInt32] = [0, 0]
        guard let roi = metal.device.makeBuffer(
            bytes: &roiValues,
            length: roiValues.count * MemoryLayout<UInt32>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: grain roi allocation")
        }
        for channel in 0..<3 {
            let row = rows[channel]
            var curveValues = row.curve
            guard let curve = metal.device.makeBuffer(
                bytes: &curveValues,
                length: curveValues.count * MemoryLayout<Float>.size,
                options: .storageModeShared)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: grain curve allocation")
            }
            let genParams = try paramBuffer([
                Float(w), Float(h), Float(channel), 1.0, 1.0,
                row.dmax, row.npart, row.dmin,
            ])
            let gen = try await metal.makeEncoder(
                functionName: "spectral_film_grain_gen_raw_sl")
            gen.encoder.setTexture(density, index: 0)
            gen.encoder.setBuffer(rawBuffer, offset: 0, index: 0)
            gen.encoder.setBuffer(genParams, offset: 0, index: 1)
            gen.encoder.setBuffer(curve, offset: 0, index: 2)
            gen.encoder.setBuffer(roi, offset: 0, index: 3)
            gen.encoder.dispatchThreads(
                MTLSize(width: w, height: h, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            gen.encoder.endEncoding()
            gen.commandBuffer.commit()
            await gen.commandBuffer.completed()
            let odParticle = row.dmax / max(row.npart, 1e-6)
            let dyeSigma = 2.0 * sqrt(max(odParticle, 0.0))
            if dyeSigma > 0.05 {
                try await dispatchSeparableBlur(
                    buffer: rawBuffer, width: w, height: h,
                    sigma: Double(dyeSigma), metal: metal,
                    scratch: scratch)
            }
            let accParams = try paramBuffer([Float(w), Float(h), 1.0])
            let acc = try await metal.makeEncoder(
                functionName: "spectral_film_grain_accumulate")
            acc.encoder.setBuffer(accBuffer, offset: 0, index: 0)
            acc.encoder.setBuffer(rawBuffer, offset: 0, index: 1)
            acc.encoder.setBuffer(accParams, offset: 0, index: 2)
            acc.encoder.dispatchThreads(
                MTLSize(width: w, height: h, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            acc.encoder.endEncoding()
            acc.commandBuffer.commit()
            await acc.commandBuffer.completed()
            let finParams = try paramBuffer([
                Float(w), Float(h), Float(channel), Float(channel),
                row.dmin, amount,
            ])
            let fin = try await metal.makeEncoder(
                functionName: "spectral_film_grain_finalize")
            fin.encoder.setBuffer(grainBuffer, offset: 0, index: 0)
            fin.encoder.setBuffer(accBuffer, offset: 0, index: 1)
            fin.encoder.setTexture(density, index: 0)
            fin.encoder.setBuffer(finParams, offset: 0, index: 2)
            fin.encoder.dispatchThreads(
                MTLSize(width: w, height: h, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            fin.encoder.endEncoding()
            fin.commandBuffer.commit()
            await fin.commandBuffer.completed()
        }
        let addParams = try paramBuffer([Float(w), Float(h)])
        let add = try await metal.makeEncoder(
            functionName: "spectral_film_grain_add")
        add.encoder.setTexture(density, index: 0)
        add.encoder.setBuffer(grainBuffer, offset: 0, index: 0)
        add.encoder.setBuffer(addParams, offset: 0, index: 1)
        add.encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        add.encoder.endEncoding()
        add.commandBuffer.commit()
        await add.commandBuffer.completed()
        // The clump-blur pair (the pool's .stageB2 top-up — the pair
        // borrows AFTER the add pass and releases at group end; nil
        // scratch = the legacy independent face).
        let blurTmp: any MTLTexture
        let usmOrig: any MTLTexture
        var borrowedPlanes: [any MTLTexture] = []
        if let scratch {
            guard let borrowed = try scratch.borrowPlanes(
                .stageB2, device: metal.device, count: 2,
                width: w, height: h),
                borrowed.count == 2
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: grain blur plane allocation")
            }
            blurTmp = borrowed[0]
            usmOrig = borrowed[1]
            borrowedPlanes = borrowed
        } else {
            guard let tmp = try Self.makeReadWriteTexture(
                metal: metal, width: w, height: h),
                let orig = try Self.makeReadWriteTexture(
                    metal: metal, width: w, height: h)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: grain blur plane allocation")
            }
            blurTmp = tmp
            usmOrig = orig
        }
        defer {
            if !borrowedPlanes.isEmpty {
                scratch?.releasePlanes(borrowedPlanes)
            }
        }
        if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: density, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: w, height: h, depth: 1),
                to: usmOrig, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            commandBuffer.commit()
            await commandBuffer.completed()
        }
        try await dispatchTextureBlur(
            texture: density, tmp: blurTmp, sigma: 1.0, metal: metal)
        let usmParams = try paramBuffer([
            Float(w), Float(h), 1.5,
            rows[0].dmin, rows[1].dmin, rows[2].dmin,
        ])
        let usm = try await metal.makeEncoder(
            functionName: "spectral_film_grain_usm")
        usm.encoder.setTexture(density, index: 0)
        usm.encoder.setTexture(usmOrig, index: 1)
        usm.encoder.setBuffer(usmParams, offset: 0, index: 2)
        usm.encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        usm.encoder.endEncoding()
        usm.commandBuffer.commit()
        await usm.commandBuffer.completed()
    }

    /// One channel's grain row (the dispatch face — Float32).
    struct GrainRow {
        let dmax: Float
        let npart: Float
        let dmin: Float
        let curve: [Float]
    }

    /// The sublayer rows from the tables' own curve faces (the
    /// single-sublayer derivation's dispatch twin — curvesNorm is
    /// ALREADY minus-the-floor (256×3 [i·3+c]); dmax/dmin ride the
    /// tables' filmDmax/filmDmin; npart INVERTS from the published RMS
    /// through the upstream nl==1 formula (self-review E3 — the 1000.0
    /// placeholder is retired); nil RMS = the a_grain floor's face
    /// (the derive twin's own degrade — the sampler still runs)).
    static func sublayerRowsForGrain(
        curvesNorm: [Float], filmDmax: SIMD3<Float>,
        filmDmin: SIMD3<Float>, publishedRms: Int? = nil
    ) -> [GrainRow] {
        let count = curvesNorm.count / 3
        let rms = SpectralGrainSublayer.broadcastRms(publishedRms)
        return (0..<3).map { c in
            var curve = [Float](repeating: 0, count: 256)
            for i in 0..<min(count, 256) {
                curve[i] = curvesNorm[i * 3 + c]
            }
            let dmax: Float
            let dmin: Float
            switch c {
            case 0: dmax = filmDmax.x; dmin = filmDmin.x
            case 1: dmax = filmDmax.y; dmin = filmDmin.y
            default: dmax = filmDmax.z; dmin = filmDmin.z
            }
            // The npart inversion (the derive twin's Float face —
            // u == 1.0, the neutral uniformity).
            let dRef = Double(dmin) + 1.0
            let sig = rms[c].map { Double($0) / 1000.0 } ?? 0.0
            let denom = max(
                dRef * (Double(dmax) + Double(dmin) - dRef), 1e-6)
            let aGrain = sig * sig
                * SpectralGrainSublayer.aperture48Area / denom
            let ref = SpectralGrainSublayer.referenceUm
            let npart = ref * ref / max(aGrain, 1e-4)
            return GrainRow(
                dmax: dmax + dmin, npart: Float(npart), dmin: dmin,
                curve: curve)
        }
    }

    /// The separable Gaussian weights (host-built, normalized —
    /// radius = ceil(3σ), the exact-kernel face).
    static func gaussianWeights(sigma: Double) -> [Float] {
        let radius = max(Int(ceil(3.0 * sigma)), 1)
        var weights = [Float](repeating: 0, count: 2 * radius + 1)
        var sum = 0.0
        for t in -radius...radius {
            let v = exp(-Double(t * t) / (2.0 * sigma * sigma))
            weights[t + radius] = Float(v)
            sum += v
        }
        return weights.map { $0 / Float(sum) }
    }

    /// The buffer blur (row+col over a flat float buffer — the dye-cloud
    /// face; texture-backed staging because the blur kernels read
    /// textures). The E-acc1 face: the r32 staging pair rides the pool
    /// (same .stageB2 leg — the caller is always the grain group inside
    /// the stage-B span; the weights/params buffers stay direct).
    private func dispatchSeparableBlur(
        buffer: any MTLBuffer, width: Int, height: Int,
        sigma: Double, metal: MetalContext,
        scratch: SpectralScratchAllocator.Slot? = nil
    ) async throws {
        let stageA: any MTLTexture
        let stageB: any MTLTexture
        var borrowedStaging: [any MTLTexture] = []
        if let scratch {
            guard let borrowed = try scratch.borrowPlanes(
                .stageB2, device: metal.device, count: 2,
                width: width, height: height, pixelFormat: .r32Float),
                borrowed.count == 2
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: blur staging allocation")
            }
            stageA = borrowed[0]
            stageB = borrowed[1]
            borrowedStaging = borrowed
        } else {
            func stagingTexture() throws -> any MTLTexture {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .r32Float, width: max(width, 1),
                    height: max(height, 1), mipmapped: false)
                descriptor.usage = [.shaderRead, .shaderWrite]
                descriptor.storageMode = .shared
                guard let texture = metal.device.makeTexture(descriptor: descriptor)
                else {
                    throw SpectralBuildError.projectionUnavailable(
                        "SpectralGPUPayloads: blur staging allocation")
                }
                return texture
            }
            stageA = try stagingTexture()
            stageB = try stagingTexture()
        }
        defer {
            if !borrowedStaging.isEmpty {
                scratch?.releasePlanes(borrowedStaging)
            }
        }
        if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: buffer, sourceOffset: 0,
                sourceBytesPerRow: width * 4,
                sourceBytesPerImage: width * height * 4,
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: stageA, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            commandBuffer.commit()
            await commandBuffer.completed()
        }
        let weights = Self.gaussianWeights(sigma: sigma)
        let radius = (weights.count - 1) / 2
        var weightValues = weights
        guard let weightsBuffer = metal.device.makeBuffer(
            bytes: &weightValues,
            length: weightValues.count * MemoryLayout<Float>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: blur weights allocation")
        }
        var params: [Float] = [Float(width), Float(height), Float(radius)]
        guard let paramsBuffer = metal.device.makeBuffer(
            bytes: &params,
            length: params.count * MemoryLayout<Float>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: blur params allocation")
        }
        for (kernel, src, dst) in [
            ("spectral_film_spatial_blur_row", stageA, stageB),
            ("spectral_film_spatial_blur_col", stageB, stageA),
        ] {
            let blur = try await metal.makeEncoder(functionName: kernel)
            blur.encoder.setTexture(src, index: 0)
            blur.encoder.setTexture(dst, index: 1)
            blur.encoder.setBuffer(weightsBuffer, offset: 0, index: 0)
            blur.encoder.setBuffer(paramsBuffer, offset: 0, index: 1)
            blur.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            blur.encoder.endEncoding()
            blur.commandBuffer.commit()
            await blur.commandBuffer.completed()
        }
        if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: stageA, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: buffer, destinationOffset: 0,
                destinationBytesPerRow: width * 4,
                destinationBytesPerImage: width * height * 4)
            blit.endEncoding()
            commandBuffer.commit()
            await commandBuffer.completed()
        }
    }

    /// The texture blur (row+col over an rgba32Float texture — the
    /// clump face; in-place through the tmp ping-pong).
    private func dispatchTextureBlur(
        texture: any MTLTexture, tmp: any MTLTexture,
        sigma: Double, metal: MetalContext
    ) async throws {
        let weights = Self.gaussianWeights(sigma: sigma)
        let radius = (weights.count - 1) / 2
        var weightValues = weights
        guard let weightsBuffer = metal.device.makeBuffer(
            bytes: &weightValues,
            length: weightValues.count * MemoryLayout<Float>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: blur weights allocation")
        }
        var params: [Float] = [
            Float(texture.width), Float(texture.height), Float(radius),
        ]
        guard let paramsBuffer = metal.device.makeBuffer(
            bytes: &params,
            length: params.count * MemoryLayout<Float>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: blur params allocation")
        }
        for (kernel, src, dst) in [
            ("spectral_film_spatial_blur_row", texture, tmp),
            ("spectral_film_spatial_blur_col", tmp, texture),
        ] {
            let blur = try await metal.makeEncoder(functionName: kernel)
            blur.encoder.setTexture(src, index: 0)
            blur.encoder.setTexture(dst, index: 1)
            blur.encoder.setBuffer(weightsBuffer, offset: 0, index: 0)
            blur.encoder.setBuffer(paramsBuffer, offset: 0, index: 1)
            blur.encoder.dispatchThreads(
                MTLSize(width: texture.width, height: texture.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            blur.encoder.endEncoding()
            blur.commandBuffer.commit()
            await blur.commandBuffer.completed()
        }
    }

    // MARK: - M8-3+ T5: the spatial pre-leg (taking diffusion → halation)

    /// The pre-leg's pixel pitch (µm — the µm→px conversion face).
    /// The pipe carries no sensor pitch, so the leg anchors the FULL
    /// frame to the 36mm reference width (upstream's own 36mm face —
    /// pixel_um = 36000 / width; a preview/exposure-resolution render
    /// re-anchors per run, the σ face stays physical).
    static func pixelUm(frameWidth: Int) -> Double {
        36000.0 / Double(max(frameWidth, 1))
    }

    /// The pre-leg dispatch (taking diffusion → halation, the upstream
    /// order verbatim — boost/glare seats reserved, never dispatched).
    /// In-place on `plane` (read_write). Nil legs = skipped (the
    /// off-identity is structural — the caller skips the whole leg).
    /// The E-acc1 face: the segment holder is .spatialPre — diffusion's
    /// trio + halation's quartet borrow SEQUENTIALLY (each leg releases
    /// its faces before the next borrows; the wide staging inside the
    /// bank loop top-ups with the same leg per pass).
    func dispatchSpatialPreLeg(
        plane: any MTLTexture,
        halationAmount: Float?,
        diffusionFamily: String?,
        diffusionAmount: Float?,
        metal: MetalContext,
        scratch: SpectralScratchAllocator.Slot? = nil
    ) async throws {
        // Taking diffusion FIRST (the upstream order).
        if let familyId = diffusionFamily,
            let family = SpectralSpatialTables.family(id: familyId) {
            let amount = Double(diffusionAmount ?? 1.0)
            if amount != 0 {
                try await dispatchTakingDiffusion(
                    plane: plane, family: family, strength: amount,
                    metal: metal, scratch: scratch)
            }
        }
        // Halation SECOND.
        if let amount = halationAmount, amount != 0 {
            try await dispatchHalation(
                plane: plane, amount: Double(amount), metal: metal,
                scratch: scratch)
        }
    }

    /// One taking-diffusion pass (the bank → scatter field → convex mix).
    /// The scatter field accumulates in a run-scoped acc plane (the
    /// allocator's spatialPre face); each bank component blurs the
    /// SOURCE plane (exact kernel below the effect threshold, the wide
    /// path above it) and folds in with its channel weights.
    /// The E-acc1 face: acc/tmp/comp borrow as ONE .spatialPre call; the
    /// wide staging top-ups per wide pass (borrow → release inside the
    /// pass, so the next pass re-hits the pool). The trio releases at
    /// leg end (halation's quartet reuses the same faces next).
    func dispatchTakingDiffusion(
        plane: any MTLTexture, family: SpectralSpatialTables.DiffFamily,
        strength: Double, metal: MetalContext,
        scratch: SpectralScratchAllocator.Slot? = nil
    ) async throws {
        let w = plane.width, h = plane.height
        let pitch = Self.pixelUm(frameWidth: w)
        let bank = SpectralSpatialTables.bank(family: family)
        let scatter = SpectralSpatialTables.scatterFraction(
            strength: strength, family: family)
        guard scatter > 0 else { return }
        let acc: any MTLTexture
        let tmp: any MTLTexture
        let comp: any MTLTexture
        var borrowedTrio: [any MTLTexture] = []
        if let scratch {
            guard let borrowed = try scratch.borrowPlanes(
                .spatialPre, device: metal.device, count: 3,
                width: w, height: h),
                borrowed.count == 3
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: diffusion plane allocation")
            }
            acc = borrowed[0]
            tmp = borrowed[1]
            comp = borrowed[2]
            borrowedTrio = borrowed
        } else {
            guard let a = try Self.makeReadWriteTexture(
                metal: metal, width: w, height: h),
                let t = try Self.makeReadWriteTexture(
                    metal: metal, width: w, height: h),
                let c = try Self.makeReadWriteTexture(
                    metal: metal, width: w, height: h)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: diffusion plane allocation")
            }
            acc = a
            tmp = t
            comp = c
        }
        defer {
            if !borrowedTrio.isEmpty {
                scratch?.releasePlanes(borrowedTrio)
            }
        }
        // Zero the acc plane (blit from a zero buffer would need a
        // staging buffer — instead track the first-component face).
        var first = true
        for component in bank {
            let sigmaPx = component.sigmaUm / pitch
            // Copy the source into the component plane, blur it, fold.
            if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
                let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(
                    from: plane, sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: w, height: h, depth: 1),
                    to: comp, destinationSlice: 0, destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blit.endEncoding()
                commandBuffer.commit()
                await commandBuffer.completed()
            }
            try await blurPlane(
                plane: comp, tmp: tmp, sigmaPx: sigmaPx, metal: metal,
                scratch: scratch)
            let cw = component.channelWeight
            try await foldBankComponent(
                acc: acc, comp: comp,
                weight: SIMD3<Float>(Float(cw.x), Float(cw.y), Float(cw.z)),
                first: first, metal: metal)
            first = false
        }
        // The convex mix: plane = (1−p)·plane + p·acc.
        try await convexMix(
            plane: plane, scatter: acc, fraction: Float(scatter),
            metal: metal)
    }

    /// One blur at σ px (exact kernel below the effect threshold, the
    /// wide path above it — the threshold face (100px starting value; the
    /// re-mark probe is pending). The E-acc1 face: the scratch slot
    /// threads to the wide arm (the exact arm allocates nothing but
    /// weights/params — direct by design).
    func blurPlane(
        plane: any MTLTexture, tmp: any MTLTexture,
        sigmaPx: Double, metal: MetalContext,
        scratch: SpectralScratchAllocator.Slot? = nil
    ) async throws {
        if sigmaPx >= Double(Self.wideEffectThreshold) {
            try await blurPlaneWide(
                plane: plane, tmp: tmp, sigmaPx: sigmaPx, metal: metal,
                scratch: scratch)
        } else {
            try await dispatchTextureBlur(
                texture: plane, tmp: tmp, sigma: sigmaPx, metal: metal)
        }
    }

    /// The wide path (down → low-face exact blur → up — the抽稀 trio).
    /// Texture↔buffer staging rides blits (the grain blur's own face).
    /// The E-acc1 face: the five staging buffers borrow as ONE .spatialPre
    /// top-up (the caller — diffusion's trio or halation's quartet — holds
    /// the segment) and release at pass end, so the next wide pass in the
    /// bank loop re-hits the pool. Params/inv/weights buffers stay direct
    /// (tiny, kernel-by-kernel by design).
    func blurPlaneWide(
        plane: any MTLTexture, tmp: any MTLTexture,
        sigmaPx: Double, metal: MetalContext,
        scratch: SpectralScratchAllocator.Slot? = nil
    ) async throws {
        let w = plane.width, h = plane.height
        guard let plan = SpectralWideBlurPlan.plan(
            sigma: Float(sigmaPx), width: w, height: h)
        else {
            // Below the min face (should not happen above the effect
            // threshold — the exact path is the fail-closed twin).
            try await dispatchTextureBlur(
                texture: plane, tmp: tmp, sigma: sigmaPx, metal: metal)
            return
        }
        let device = metal.device
        let stride = 4 * MemoryLayout<Float>.size
        let srcBuffer: any MTLBuffer
        let rowsBuffer: any MTLBuffer
        let lowBuffer: any MTLBuffer
        let lowBlurBuffer: any MTLBuffer
        let dstBuffer: any MTLBuffer
        var borrowedStaging: [any MTLBuffer] = []
        if let scratch {
            guard let borrowed = try scratch.borrowBuffers(
                .spatialPre, device: device,
                byteLengths: [w * h * stride, plan.lw * h * stride,
                              plan.lw * plan.lh * stride,
                              plan.lw * plan.lh * stride,
                              w * h * stride]),
                borrowed.count == 5
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: wide staging allocation")
            }
            srcBuffer = borrowed[0]
            rowsBuffer = borrowed[1]
            lowBuffer = borrowed[2]
            lowBlurBuffer = borrowed[3]
            dstBuffer = borrowed[4]
            borrowedStaging = borrowed
        } else {
            func float4Buffer(count: Int) throws -> any MTLBuffer {
                guard let buffer = device.makeBuffer(
                    length: count * 4 * MemoryLayout<Float>.size,
                    options: .storageModeShared)
                else {
                    throw SpectralBuildError.projectionUnavailable(
                        "SpectralGPUPayloads: wide staging allocation")
                }
                return buffer
            }
            srcBuffer = try float4Buffer(count: w * h)
            rowsBuffer = try float4Buffer(count: plan.lw * h)
            lowBuffer = try float4Buffer(count: plan.lw * plan.lh)
            lowBlurBuffer = try float4Buffer(count: plan.lw * plan.lh)
            dstBuffer = try float4Buffer(count: w * h)
        }
        defer {
            if !borrowedStaging.isEmpty {
                scratch?.releaseBuffers(borrowedStaging)
            }
        }
        // Download the plane into the source buffer.
        if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: plane, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: w, height: h, depth: 1),
                to: srcBuffer, destinationOffset: 0,
                destinationBytesPerRow: w * 16,
                destinationBytesPerImage: w * h * 16)
            blit.endEncoding()
            commandBuffer.commit()
            await commandBuffer.completed()
        }
        func paramsBuffer(_ values: [Float]) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                bytes: values,
                length: values.count * MemoryLayout<Float>.size,
                options: .storageModeShared)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: wide params allocation")
            }
            return buffer
        }
        var invValues = SpectralWideBlurPlan.inverseTable(k: plan.k)
        guard let invBuffer = device.makeBuffer(
            bytes: &invValues,
            length: invValues.count * MemoryLayout<Float>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: wide inv allocation")
        }
        // rows → down → low-face exact blur (host-side separable over
        // the low buffer through staging textures) → up.
        let rowsParams = try paramsBuffer([
            Float(w), Float(h), Float(plan.k), Float(plan.lw),
            Float(plan.ox),
        ])
        let rows = try await metal.makeEncoder(
            functionName: "spectral_film_wide_rows")
        rows.encoder.setBuffer(srcBuffer, offset: 0, index: 0)
        rows.encoder.setBuffer(rowsBuffer, offset: 0, index: 1)
        rows.encoder.setBuffer(rowsParams, offset: 0, index: 2)
        rows.encoder.dispatchThreads(
            MTLSize(width: plan.lw, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        rows.encoder.endEncoding()
        rows.commandBuffer.commit()
        await rows.commandBuffer.completed()
        let downParams = try paramsBuffer([
            Float(w), Float(h), Float(plan.k), Float(plan.lw),
            Float(plan.lh), Float(plan.ox), Float(plan.oy),
        ])
        let down = try await metal.makeEncoder(
            functionName: "spectral_film_wide_down")
        down.encoder.setBuffer(rowsBuffer, offset: 0, index: 0)
        down.encoder.setBuffer(lowBuffer, offset: 0, index: 1)
        down.encoder.setBuffer(downParams, offset: 0, index: 2)
        down.encoder.setBuffer(invBuffer, offset: 0, index: 3)
        down.encoder.dispatchThreads(
            MTLSize(width: plan.lw, height: plan.lh, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        down.encoder.endEncoding()
        down.commandBuffer.commit()
        await down.commandBuffer.completed()
        // The low-face exact blur (σ_low is small — the exact kernel).
        try await blurFloat4Buffer(
            buffer: lowBuffer, outBuffer: lowBlurBuffer,
            width: plan.lw, height: plan.lh,
            sigma: Double(plan.sigmaLow), metal: metal)
        let upParams = try paramsBuffer([
            Float(w), Float(h), Float(plan.k), Float(plan.lw),
            Float(plan.lh), Float(plan.ox), Float(plan.oy),
            1.0 / Float(2 * plan.k),
        ])
        let up = try await metal.makeEncoder(
            functionName: "spectral_film_wide_up")
        up.encoder.setBuffer(lowBlurBuffer, offset: 0, index: 0)
        up.encoder.setBuffer(dstBuffer, offset: 0, index: 1)
        up.encoder.setBuffer(upParams, offset: 0, index: 2)
        up.encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        up.encoder.endEncoding()
        up.commandBuffer.commit()
        await up.commandBuffer.completed()
        // Upload the blurred buffer back into the plane.
        if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: dstBuffer, sourceOffset: 0,
                sourceBytesPerRow: w * 16,
                sourceBytesPerImage: w * h * 16,
                sourceSize: MTLSize(width: w, height: h, depth: 1),
                to: plane, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            commandBuffer.commit()
            await commandBuffer.completed()
        }
    }

    /// The float4-buffer exact blur (row+col separable over buffer
    /// faces — the low-face leg; staging textures carry the pass).
    func blurFloat4Buffer(
        buffer: any MTLBuffer, outBuffer: any MTLBuffer,
        width: Int, height: Int, sigma: Double, metal: MetalContext
    ) async throws {
        let weights = Self.gaussianWeights(sigma: sigma)
        let radius = (weights.count - 1) / 2
        // Pass 1 (rows): buffer → outBuffer; pass 2 (cols): outBuffer
        // → buffer (in-place ping-pong — the blurred field lands back
        // in `buffer`).
        for (pass, src, dst, isRow) in [
            (0, buffer, outBuffer, true),
            (1, outBuffer, buffer, false),
        ] as [(Int, any MTLBuffer, any MTLBuffer, Bool)] {
            _ = pass
            let kernel = isRow
                ? "spectral_film_wide_gauss_row"
                : "spectral_film_wide_gauss_col"
            var weightValues = weights
            guard let weightsBuffer = metal.device.makeBuffer(
                bytes: &weightValues,
                length: weightValues.count * MemoryLayout<Float>.size,
                options: .storageModeShared)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: gauss weights allocation")
            }
            var params: [Float] = [
                Float(width), Float(height), Float(radius),
            ]
            guard let paramsBuffer = metal.device.makeBuffer(
                bytes: &params,
                length: params.count * MemoryLayout<Float>.size,
                options: .storageModeShared)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: gauss params allocation")
            }
            let pass_ = try await metal.makeEncoder(functionName: kernel)
            pass_.encoder.setBuffer(src, offset: 0, index: 0)
            pass_.encoder.setBuffer(dst, offset: 0, index: 1)
            pass_.encoder.setBuffer(weightsBuffer, offset: 0, index: 2)
            pass_.encoder.setBuffer(paramsBuffer, offset: 0, index: 3)
            pass_.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            pass_.encoder.endEncoding()
            pass_.commandBuffer.commit()
            await pass_.commandBuffer.completed()
        }
    }

    /// Fold one bank component into the acc plane (first = overwrite,
    /// else channel-weighted add — the per-channel weights ride the
    /// fold; the T5 mix kernel carries them).
    func foldBankComponent(
        acc: any MTLTexture, comp: any MTLTexture,
        weight: SIMD3<Float>, first: Bool, metal: MetalContext
    ) async throws {
        var params: [Float] = [
            Float(acc.width), Float(acc.height),
            weight.x, weight.y, weight.z, first ? 1.0 : 0.0,
        ]
        guard let paramsBuffer = metal.device.makeBuffer(
            bytes: &params,
            length: params.count * MemoryLayout<Float>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: fold params allocation")
        }
        let fold = try await metal.makeEncoder(
            functionName: "spectral_film_bank_fold")
        fold.encoder.setTexture(comp, index: 0)
        fold.encoder.setTexture(acc, index: 1)
        fold.encoder.setBuffer(paramsBuffer, offset: 0, index: 2)
        fold.encoder.dispatchThreads(
            MTLSize(width: acc.width, height: acc.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        fold.encoder.endEncoding()
        fold.commandBuffer.commit()
        await fold.commandBuffer.completed()
    }

    /// The convex mix (plane = (1−p)·plane + p·scatter — in-place).
    func convexMix(
        plane: any MTLTexture, scatter: any MTLTexture,
        fraction: Float, metal: MetalContext
    ) async throws {
        var params: [Float] = [
            Float(plane.width), Float(plane.height), fraction,
        ]
        guard let paramsBuffer = metal.device.makeBuffer(
            bytes: &params,
            length: params.count * MemoryLayout<Float>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: mix params allocation")
        }
        let mix = try await metal.makeEncoder(
            functionName: "spectral_film_convex_mix")
        mix.encoder.setTexture(plane, index: 0)
        mix.encoder.setTexture(scatter, index: 1)
        mix.encoder.setBuffer(paramsBuffer, offset: 0, index: 2)
        mix.encoder.dispatchThreads(
            MTLSize(width: plane.width, height: plane.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        mix.encoder.endEncoding()
        mix.commandBuffer.commit()
        await mix.commandBuffer.completed()
    }

    /// One halation pass (scatter stage + 3 bounces — the still
    /// baseline; the s convex weight rides the record amount clamped
    /// to [0, 1]; the bounce σ rides first_sigma_um/pixel_um·√k).
    /// The E-acc1 face: tmp/core/tail/comp borrow as ONE .spatialPre
    /// call (diffusion's trio already released, so three of the four
    /// re-hit the pool; the bounce plane top-ups stage-2-only).
    func dispatchHalation(
        plane: any MTLTexture, amount: Double, metal: MetalContext,
        scratch: SpectralScratchAllocator.Slot? = nil
    ) async throws {
        let w = plane.width, h = plane.height
        let pitch = Self.pixelUm(frameWidth: w)
        let base = SpectralSpatialTables.stillBaseline
        let s = min(max(amount, 0.0), 1.0)
        let tmp: any MTLTexture
        let core: any MTLTexture
        let tail: any MTLTexture
        let comp: any MTLTexture
        var borrowedQuartet: [any MTLTexture] = []
        if let scratch {
            guard let borrowed = try scratch.borrowPlanes(
                .spatialPre, device: metal.device, count: 4,
                width: w, height: h),
                borrowed.count == 4
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: halation plane allocation")
            }
            tmp = borrowed[0]
            core = borrowed[1]
            tail = borrowed[2]
            comp = borrowed[3]
            borrowedQuartet = borrowed
        } else {
            guard let t = try Self.makeReadWriteTexture(
                metal: metal, width: w, height: h),
                let c = try Self.makeReadWriteTexture(
                    metal: metal, width: w, height: h),
                let ta = try Self.makeReadWriteTexture(
                    metal: metal, width: w, height: h),
                let co = try Self.makeReadWriteTexture(
                    metal: metal, width: w, height: h)
            else {
                throw SpectralBuildError.projectionUnavailable(
                    "SpectralGPUPayloads: halation plane allocation")
            }
            tmp = t
            core = c
            tail = ta
            comp = co
        }
        defer {
            if !borrowedQuartet.isEmpty {
                scratch?.releasePlanes(borrowedQuartet)
            }
        }
        // Stage 1 (scatter): core + 3-Gaussian tail → convex mix.
        // The per-channel σ rides the baseline/core-tail faces; the
        // tail accumulates amp-weighted (the fma fold's host twin is
        // the fold kernel with first/add faces).
        if s > 0 {
            // Core (per-channel σ — the blur is achromatic per pass,
            // so run the core per channel through the mix kernel's
            // channel mask — simplified: the max-σ single pass, the
            // per-channel split rides the T5+ refinement; the scatter
            // weight s scales the mix).
            let coreSigma = max(
                base.scatterCore.x, base.scatterCore.y,
                base.scatterCore.z) / pitch
            if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
                let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(
                    from: plane, sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: w, height: h, depth: 1),
                    to: core, destinationSlice: 0, destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blit.endEncoding()
                commandBuffer.commit()
                await commandBuffer.completed()
            }
            try await blurPlane(
                plane: core, tmp: tmp, sigmaPx: coreSigma, metal: metal,
                scratch: scratch)
            // Tail (3 Gaussians, amp-weighted into `tail`).
            var tailFirst = true
            for g in 0..<3 {
                let tailSigma = max(
                    SpectralSpatialTables.tailRatios[g]
                        * base.scatterTail.x,
                    SpectralSpatialTables.tailRatios[g]
                        * base.scatterTail.y,
                    SpectralSpatialTables.tailRatios[g]
                        * base.scatterTail.z) / pitch
                if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
                    let blit = commandBuffer.makeBlitCommandEncoder() {
                    blit.copy(
                        from: plane, sourceSlice: 0, sourceLevel: 0,
                        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                        sourceSize: MTLSize(width: w, height: h, depth: 1),
                        to: comp, destinationSlice: 0, destinationLevel: 0,
                        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                    blit.endEncoding()
                    commandBuffer.commit()
                    await commandBuffer.completed()
                }
                try await blurPlane(
                    plane: comp, tmp: tmp, sigmaPx: tailSigma, metal: metal,
                    scratch: scratch)
                let amp = Float(SpectralSpatialTables.tailAmps[g])
                try await foldBankComponent(
                    acc: tail, comp: comp,
                    weight: SIMD3<Float>(amp, amp, amp),
                    first: tailFirst, metal: metal)
                tailFirst = false
            }
            // scattered = w·tail + (1−w)·core; plane = (1−s)·plane +
            // s·scattered (the T5 scatter-combine kernel).
            try await scatterCombine(
                plane: plane, core: core, tail: tail,
                weights: base.scatterTailWeight, amount: Float(s),
                metal: metal)
        }
        // Stage 2 (3 bounces, σ√k, decay-weighted, additive over
        // (1+a) — the T5 bounce kernel folds per bounce).
        let aTot = SIMD3<Float>(
            Float(base.strength.x * amount),
            Float(base.strength.y * amount),
            Float(base.strength.z * amount))
        if aTot.x > 0 || aTot.y > 0 || aTot.z > 0 {
            // The stage-2 bounce acc (the pool's .spatialPre top-up —
            // quartet still live; releases before the quartet does).
            let blur: any MTLTexture
            var borrowedBounce: [any MTLTexture] = []
            if let scratch {
                guard let borrowed = try scratch.borrowPlanes(
                    .spatialPre, device: metal.device, count: 1,
                    width: w, height: h),
                    let plane = borrowed.first
                else {
                    throw SpectralBuildError.projectionUnavailable(
                        "SpectralGPUPayloads: halation bounce allocation")
                }
                blur = plane
                borrowedBounce = borrowed
            } else {
                guard let plane = try Self.makeReadWriteTexture(
                    metal: metal, width: w, height: h)
                else {
                    throw SpectralBuildError.projectionUnavailable(
                        "SpectralGPUPayloads: halation bounce allocation")
                }
                blur = plane
            }
            defer {
                if !borrowedBounce.isEmpty {
                    scratch?.releasePlanes(borrowedBounce)
                }
            }
            var bounceFirst = true
            for k in 1...3 {
                let sigma = base.firstSigmaUm / pitch
                    * Double(k).squareRoot()
                if let commandBuffer = try? metal.makeRoutedCommandBuffer(),
                    let blit = commandBuffer.makeBlitCommandEncoder() {
                    blit.copy(
                        from: plane, sourceSlice: 0, sourceLevel: 0,
                        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                        sourceSize: MTLSize(width: w, height: h, depth: 1),
                        to: comp, destinationSlice: 0, destinationLevel: 0,
                        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                    blit.endEncoding()
                    commandBuffer.commit()
                    await commandBuffer.completed()
                }
                try await blurPlane(
                    plane: comp, tmp: tmp, sigmaPx: sigma, metal: metal,
                    scratch: scratch)
                let decay = SpectralSpatialTables.bounceDecay[k - 1]
                try await foldBankComponent(
                    acc: blur, comp: comp,
                    weight: SIMD3<Float>(decay, decay, decay),
                    first: bounceFirst, metal: metal)
                bounceFirst = false
            }
            try await halationApply(
                plane: plane, blur: blur, strength: aTot, metal: metal)
        }
    }

    /// The scatter combine (scattered = w·tail + (1−w)·core, then
    /// plane = (1−s)·plane + s·scattered — in-place on `plane`).
    func scatterCombine(
        plane: any MTLTexture, core: any MTLTexture, tail: any MTLTexture,
        weights: SIMD3<Double>, amount: Float, metal: MetalContext
    ) async throws {
        var params: [Float] = [
            Float(plane.width), Float(plane.height),
            Float(weights.x), Float(weights.y), Float(weights.z), amount,
        ]
        guard let paramsBuffer = metal.device.makeBuffer(
            bytes: &params,
            length: params.count * MemoryLayout<Float>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: scatter params allocation")
        }
        let combine = try await metal.makeEncoder(
            functionName: "spectral_film_scatter_combine")
        combine.encoder.setTexture(plane, index: 0)
        combine.encoder.setTexture(core, index: 1)
        combine.encoder.setTexture(tail, index: 2)
        combine.encoder.setBuffer(paramsBuffer, offset: 0, index: 3)
        combine.encoder.dispatchThreads(
            MTLSize(width: plane.width, height: plane.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        combine.encoder.endEncoding()
        combine.commandBuffer.commit()
        await combine.commandBuffer.completed()
    }

    /// The halation apply (plane = (a·blur + plane) / (1 + a) —
    /// in-place on `plane`).
    func halationApply(
        plane: any MTLTexture, blur: any MTLTexture,
        strength: SIMD3<Float>, metal: MetalContext
    ) async throws {
        var params: [Float] = [
            Float(plane.width), Float(plane.height),
            strength.x, strength.y, strength.z,
        ]
        guard let paramsBuffer = metal.device.makeBuffer(
            bytes: &params,
            length: params.count * MemoryLayout<Float>.size,
            options: .storageModeShared)
        else {
            throw SpectralBuildError.projectionUnavailable(
                "SpectralGPUPayloads: halation params allocation")
        }
        let apply = try await metal.makeEncoder(
            functionName: "spectral_film_halation_apply")
        apply.encoder.setTexture(plane, index: 0)
        apply.encoder.setTexture(blur, index: 1)
        apply.encoder.setBuffer(paramsBuffer, offset: 0, index: 2)
        apply.encoder.dispatchThreads(
            MTLSize(width: plane.width, height: plane.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        apply.encoder.endEncoding()
        apply.commandBuffer.commit()
        await apply.commandBuffer.completed()
    }

    /// The wide-effect threshold (px — the STARTING value 100; the T5
    /// Metal re-mark pending — the 100px starting value stands until the
    /// T7 evidence leg法定 a re-marked one, DECISIONS-logged).
    /// The lock-box form (Swift 6 rejects static mutable globals).
    private static let wideThresholdBox = WideThresholdBox()
    private final class WideThresholdBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Float = 100.0
        func get() -> Float {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func set(_ next: Float) {
            lock.lock()
            defer { lock.unlock() }
            value = next
        }
    }
    static var wideEffectThreshold: Float {
        get { wideThresholdBox.get() }
        set { wideThresholdBox.set(newValue) }
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
