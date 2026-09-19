import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// GaussianBlur (Plan 03-04-T1) — the shared domain blur primitive behind
// shadhi's gaussian leg (and the Phase 5 denoise reuse). CPU half: the
// Deriche/Young-van-Vliet IIR coefficient derivation + the two-pass
// dispatch; Metal half: `Common/GaussianBlurKernels.metal`.
//
// SOURCE (verbatim): Darktable `src/common/gaussian.c:41-100`
// `_compute_gauss_params` — alpha = 1.695/sigma, ema/exp(−2α), and the
// per-order a/b branches. Order ZERO (`DT_IOP_GAUSSIAN_ZERO`) is shadhi's
// default; the enum keeps the other two dt orders for downstream reuse.
//
// DEVIATION (plan-source erratum, recorded): plan T1 specified a truncated
// FIR ("sigma → tap 数/pass 结构，CPU 侧算权重 buffer"). The dt source is a
// recursive IIR (see the kernel header for the recursion); we follow the
// source because shadhi's parity target IS dt's blurred base layer. The
// T1 acceptance "delta 脉冲响应 == 解析 gaussian（<1e-6）" is realized as
// the Deriche-approximation envelope pinned in GaussianBlurTests (impulse
// response vs analytic gaussian: normalized-energy 1 ± 1e-3, symmetric,
// max |Δ| < 0.02 measured) + GPU vs float64 recursion < 1e-6 (the load-
// bearing gate) + sigma=0 identity + flat-field edge conservation ±1%.
//
// Bounds: dt clamps the blur INPUT to [Labmin, Labmax] per channel at
// every sample (gaussian.c CLAMPF / gaussian.cl clamp) — shadhi passes
// the Lab box (0/100, ±128, 0/1) or ±FLT_MAX when unbound.
// ─────────────────────────────────────────────────────────────────────────

/// dt `dt_gaussian_order_t` (gaussian.h) — the derivation branch.
public enum GaussianOrder: Sendable {
    case zero
    case one
    case two
}

/// The eight IIR coefficients (`dt_gaussian_t` derivation output).
public struct GaussianCoeffs: Sendable, Equatable {
    public var a0: Float
    public var a1: Float
    public var a2: Float
    public var a3: Float
    public var b1: Float
    public var b2: Float
    public var coefp: Float
    public var coefn: Float

    public init(
        a0: Float, a1: Float, a2: Float, a3: Float,
        b1: Float, b2: Float, coefp: Float, coefn: Float
    ) {
        self.a0 = a0
        self.a1 = a1
        self.a2 = a2
        self.a3 = a3
        self.b1 = b1
        self.b2 = b2
        self.coefp = coefp
        self.coefn = coefn
    }
}

public enum GaussianBlur {

    public static let passColFunction = "gaussian_pass_col"
    public static let passRowFunction = "gaussian_pass_row"
    public static let storeFunction = "gaussian_store"
    public static let copyFunction = "gaussian_copy"

    /// dt `_compute_gauss_params` (gaussian.c:41-100) — derivation in
    /// Double, published Float. DEVIATION (recorded): dt derives through
    /// `expf` (float32 throughout); this port derives through Double `exp`
    /// so the published coefficients are the float32 grid points of the
    /// float64 formula — the same values the golden reference recursion
    /// (gen_fixtures `dt_gauss_coeffs` + GaussianBlurTests
    /// `referenceCoeffs`) consumes. The expf-vs-exp difference is ~1 ulp
    /// per coefficient; with the IIR pole near 1 at large sigma (shadhi
    /// radius 100) that ulp amplifies to ~1e-4 output error and breaks the
    /// <1e-4 parity gate, so the float64 derivation is the honest choice.
    public static func coeffs(sigma: Float, order: GaussianOrder = .zero) -> GaussianCoeffs {
        let alpha = Double(1.695) / Double(sigma)
        let ema = Foundation.exp(-alpha)
        let ema2 = Foundation.exp(-2.0 * alpha)
        let b1 = -2.0 * ema
        let b2 = ema2

        var a0: Double = 0
        var a1: Double = 0
        var a2: Double = 0
        var a3: Double = 0

        switch order {
        case .zero:
            // DT_IOP_GAUSSIAN_ZERO (gaussian.c:57-67)
            let k = (1.0 - ema) * (1.0 - ema) / (1.0 + (2.0 * alpha * ema) - ema2)
            a0 = k
            a1 = k * (alpha - 1.0) * ema
            a2 = k * (alpha + 1.0) * ema
            a3 = -k * ema2
        case .one:
            // DT_IOP_GAUSSIAN_ONE (gaussian.c:69-74)
            a0 = (1.0 - ema) * (1.0 - ema)
            a1 = 0.0
            a2 = -a0
            a3 = 0.0
        case .two:
            // DT_IOP_GAUSSIAN_TWO (gaussian.c:76-92)
            let k = -(ema2 - 1.0) / (2.0 * alpha * ema)
            var kn = -2.0 * (-1.0 + (3.0 * ema) - (3.0 * ema * ema) + (ema * ema * ema))
            kn /= ((3.0 * ema) + 1.0 + (3.0 * ema * ema) + (ema * ema * ema))
            a0 = kn
            a1 = -kn * (1.0 + (k * alpha)) * ema
            a2 = kn * (1.0 - (k * alpha)) * ema
            a3 = -kn * ema2
        }

        let coefp = (a0 + a1) / (1.0 + b1 + b2)
        let coefn = (a2 + a3) / (1.0 + b1 + b2)
        return GaussianCoeffs(
            a0: Float(a0), a1: Float(a1), a2: Float(a2), a3: Float(a3),
            b1: Float(b1), b2: Float(b2), coefp: Float(coefp), coefn: Float(coefn)
        )
    }

    /// MSL mirror of `GaussianUniforms` (GaussianBlurKernels.metal).
    struct Uniforms {
        var a0: Float, a1: Float, a2: Float, a3: Float
        var b1: Float, b2: Float, coefp: Float, coefn: Float
        var boundsMin: SIMD4<Float>
        var boundsMax: SIMD4<Float>
        var width: UInt32
        var height: UInt32

        init(coeffs: GaussianCoeffs, boundsMin: SIMD4<Float>, boundsMax: SIMD4<Float>, width: Int, height: Int) {
            self.a0 = coeffs.a0
            self.a1 = coeffs.a1
            self.a2 = coeffs.a2
            self.a3 = coeffs.a3
            self.b1 = coeffs.b1
            self.b2 = coeffs.b2
            self.coefp = coeffs.coefp
            self.coefn = coeffs.coefn
            self.boundsMin = boundsMin
            self.boundsMax = boundsMax
            self.width = UInt32(width)
            self.height = UInt32(height)
        }
    }

    /// Blur `input` into `output` (both float32 RGBA, same size): column
    /// pass then row pass (dt CPU order) over the device-memory `planes`
    /// buffer (dt gaussian.cl's `__global float4 *` shape — MANDATORY, see
    /// the kernel header: an access::read_write TEXTURE loses the backward
    /// pass's in-thread read of the forward's write on M4/macOS 27, and an
    /// IN-PLACE row pass feeds the backward filter the forward's output —
    /// both silently corrupt the blur), then `gaussian_store` into
    /// `output`. `planes` needs 2 × width×height×16 bytes (.shared storage
    /// — see the kernel header for the read_write-texture finding and
    /// L018 for the private-storage/CI interaction; owners cache it per
    /// size, ShadhiModule pattern).
    /// sigma ≤ 0 = identity texture copy (the IIR coefficients degenerate
    /// to NaN at sigma 0; dt never reaches it through shadhi's radius
    /// clamp — the guard keeps this shared primitive total).
    public static func blur(
        input: any MTLTexture,
        output: any MTLTexture,
        planes: any MTLBuffer,
        sigma: Float,
        order: GaussianOrder = .zero,
        boundsMin: SIMD4<Float> = SIMD4(repeating: -Float.greatestFiniteMagnitude),
        boundsMax: SIMD4<Float> = SIMD4(repeating: Float.greatestFiniteMagnitude),
        metal: MetalContext
    ) async throws {
        let width = input.width
        let height = input.height

        if sigma <= 0 {
            let session = try await metal.makeEncoder(functionName: Self.copyFunction)
            session.encoder.setTexture(input, index: 0)
            session.encoder.setTexture(output, index: 1)
            session.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
            )
            session.encoder.endEncoding()
            session.commandBuffer.commit()
            return
        }

        let planeBytes = width * height * MemoryLayout<Float>.stride * 4
        assert(
            planes.length >= planeBytes * 2,
            "GaussianBlur.blur: planes buffer too small (\(planes.length) < \(planeBytes * 2))")

        let uniforms = Uniforms(
            coeffs: coeffs(sigma: sigma, order: order),
            boundsMin: boundsMin, boundsMax: boundsMax,
            width: width, height: height
        )
        let uniformStride = MemoryLayout<Uniforms>.stride

        // Pass 1 — columns (one thread per column): texture → plane half 0.
        let col = try await metal.makeEncoder(functionName: Self.passColFunction)
        col.encoder.setTexture(input, index: 0)
        var colUniforms = uniforms
        col.encoder.setBytes(&colUniforms, length: uniformStride, index: 0)
        col.encoder.setBuffer(planes, offset: 0, index: 1)
        col.encoder.dispatchThreads(
            MTLSize(width: width, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(256, col.pipelineState.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        )
        col.encoder.endEncoding()
        col.commandBuffer.commit()

        // Pass 2 — rows over the column plane, INTO the second plane half
        // (dt gaussian.c:230-262 shape — the horizontal pass reads one
        // buffer and writes another; an in-place row pass feeds the
        // backward filter the forward's OUTPUT and collapses the DC gain
        // to cp·(1+cn), measured 03-04). FIFO order on the same queue
        // guarantees the column writes are complete for the row reads.
        let row = try await metal.makeEncoder(functionName: Self.passRowFunction)
        var rowUniforms = uniforms
        row.encoder.setBuffer(planes, offset: 0, index: 0)
        row.encoder.setBuffer(planes, offset: planeBytes, index: 1)
        row.encoder.setBytes(&rowUniforms, length: uniformStride, index: 2)
        row.encoder.dispatchThreads(
            MTLSize(width: height, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(256, row.pipelineState.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        )
        row.encoder.endEncoding()
        row.commandBuffer.commit()

        // Pass 3 — row plane → output texture.
        let store = try await metal.makeEncoder(functionName: Self.storeFunction)
        store.encoder.setBuffer(planes, offset: planeBytes, index: 0)
        var storeUniforms = uniforms
        store.encoder.setBytes(&storeUniforms, length: uniformStride, index: 1)
        store.encoder.setTexture(output, index: 0)
        store.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        store.encoder.endEncoding()
        store.commandBuffer.commit()
    }
}
