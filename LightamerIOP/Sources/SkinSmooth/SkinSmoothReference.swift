import Foundation

// ─────────────────────────────────────────────────────────────────────────
// SkinSmoothReference (Plan 07-2 T4) — the float64 parity reference for
// the frequency-separation skin smoothing. SELF-SYNTHESIZED track (L017):
// skinSmooth has NO Darktable counterpart (dt has no AI skin-smoothing
// module), so the golden face is this Double transliteration of the GPU
// math — the same discipline as GaussianBlurTests' reference recursion
// (coefficient source quantized to the float32 grid the GPU receives,
// recursion in Double).
//
// MIRRORED MATH (SkinSmoothKernels.metal `skin_smooth_mix` +
// Common/GaussianBlurKernels.metal, formula-identical):
//   1. low  = Deriche IIR (order ZERO) column-then-row at σ(radius) —
//      UNBOUNDED clamp (±FLT_MAX equivalent);
//   2. high = in − low (per channel);
//   3. mag  = max(|high_R|, |high_G|, |high_B|) — the SHARED window
//      factor (per-channel windows would shift hue);
//   4. g(mag) = raised-cosine soft window centered on t (w = softness):
//      mag ≤ t(1−w) → 1; mag ≥ t(1+w) → 0; between →
//      0.5·(1+cos(π·(mag−t(1−w))/(2wt)));
//   5. out_c = low_c + high_c·(1 − a·m·g),  m = mask ?? 1.
//
// The σ chain mirrors SkinSmoothModule.sigma (highpass.c:140 citation):
// r = max(1, ceil(radius·scale)); σ = √((r(r+1)·8+2)/3).
// ─────────────────────────────────────────────────────────────────────────

public enum SkinSmoothReference {

    /// The module's σ chain in Double (mirrors SkinSmoothModule.sigma).
    public static func sigma(radius: Double, scale: Double = 1.0) -> Double {
        let scaled = max(1, Int((max(1, radius) * max(scale, 0)).rounded(.up)))
        let r = Double(scaled)
        return ((r * (r + 1) * 8 + 2) / 3).squareRoot()
    }

    /// The raised-cosine window factor g(mag) — the k_soft form
    /// (D-07-2-T2-1: smooth transition, NOT a hard |h| ≤ t cut).
    public static func windowFactor(mag: Double, threshold: Double, softness: Double) -> Double {
        let lo = threshold * (1.0 - softness)
        let hi = threshold * (1.0 + softness)
        if mag <= lo { return 1.0 }
        if mag >= hi { return 0.0 }
        return 0.5 * (1.0 + cos(Double.pi * (mag - lo) / (2.0 * softness * threshold)))
    }

    /// The low band alone (the Deriche IIR in Double) — exposed for
    /// diagnostics and future consumers; `process` runs it + the mix.
    public static func lowBand(
        pixels: [Float], width: Int, height: Int, radius: Double
    ) -> [Double] {
        precondition(pixels.count == width * height * 4)
        let sigmaF = Float(sigma(radius: radius))
        let c = GaussianBlurLike.coeffs(sigma: sigmaF)
        let n = width * height
        var low = [Double](repeating: 0, count: n * 4)
        var plane = [Double](repeating: 0, count: n * 4)

        for x in 0..<width {
            var xp = read4(pixels, x, 0, width)
            var yb = xp * c.coefp
            var yp = yb
            for y in 0..<height {
                let xc = read4(pixels, x, y, width)
                let yc = xc * c.a0 + xp * c.a1 - yp * c.b1 - yb * c.b2
                xp = xc; yb = yp; yp = yc
                store4(&plane, y, x, width, yc)
            }
            var xn = read4(pixels, x, height - 1, width)
            var xa = xn
            var yn = xn * c.coefn
            var ya = yn
            for k in 0..<height {
                let y = height - 1 - k
                let xc = read4(pixels, x, y, width)
                let yc = xn * c.a2 + xa * c.a3 - yn * c.b1 - ya * c.b2
                xa = xn; xn = xc; ya = yn; yn = yc
                accumulate4(&plane, y, x, width, yc)
            }
        }

        for y in 0..<height {
            let base = y
            var xp = read4(plane, base, 0, width, offset: 0)
            var yb = xp * c.coefp
            var yp = yb
            for x in 0..<width {
                let xc = read4(plane, base, x, width, offset: 0)
                let yc = xc * c.a0 + xp * c.a1 - yp * c.b1 - yb * c.b2
                xp = xc; yb = yp; yp = yc
                store4(&low, base, x, width, yc)
            }
            var xn = read4(plane, base, width - 1, width, offset: 0)
            var xa = xn
            var yn = xn * c.coefn
            var ya = yn
            for k in 0..<width {
                let x = width - 1 - k
                let xc = read4(plane, base, x, width, offset: 0)
                let yc = xn * c.a2 + xa * c.a3 - yn * c.b1 - ya * c.b2
                xa = xn; xn = xc; ya = yn; yn = yc
                accumulate4(&low, base, x, width, yc)
            }
        }
        return low
    }

    /// Full pipeline over an RGBA float32 input (the GPU texture's exact
    /// values), returning RGBA float32. `mask` = per-pixel single-channel
    /// [0,1] (nil ⇒ m ≡ 1 — the identity-triple #2 leg).
    public static func process(
        pixels: [Float], width: Int, height: Int,
        radius: Double, strength: Double, detailPreserve: Double,
        softness: Double = 0.25,
        mask: [Float]? = nil
    ) -> [Float] {
        precondition(pixels.count == width * height * 4)
        if let mask { precondition(mask.count == width * height) }
        let low = lowBand(pixels: pixels, width: width, height: height, radius: radius)

        // ── Steps 2-5: the split + shared-magnitude soft window + mix.
        let n = width * height
        var out = [Float](repeating: 0, count: n * 4)
        for i in 0..<n {
            let i4 = i * 4
            var high = SIMD4<Double>(
                Double(pixels[i4]) - low[i4],
                Double(pixels[i4 + 1]) - low[i4 + 1],
                Double(pixels[i4 + 2]) - low[i4 + 2], 0)
            let mag = max(abs(high.x), abs(high.y), abs(high.z))
            let g = windowFactor(mag: mag, threshold: detailPreserve, softness: softness)
            let m = mask.map { Double($0[i]) } ?? 1.0
            let factor = 1.0 - strength * m * g
            out[i4] = Float(low[i4] + high.x * factor)
            out[i4 + 1] = Float(low[i4 + 1] + high.y * factor)
            out[i4 + 2] = Float(low[i4 + 2] + high.z * factor)
            out[i4 + 3] = pixels[i4 + 3] // alpha rides the original
            high.w = 0
        }
        return out
    }

    // MARK: - SIMD4 plane accessors (row-major, 4 floats per pixel)

    @inline(__always)
    private static func read4(
        _ src: [Float], _ x: Int, _ y: Int, _ width: Int, offset: Int = 0
    ) -> SIMD4<Double> {
        let i = (y * width + x) * 4
        return SIMD4<Double>(Double(src[i]), Double(src[i + 1]), Double(src[i + 2]), Double(src[i + 3]))
    }

    @inline(__always)
    private static func read4(
        _ src: [Double], _ row: Int, _ x: Int, _ width: Int, offset: Int
    ) -> SIMD4<Double> {
        let i = (row * width + x) * 4
        return SIMD4<Double>(src[i], src[i + 1], src[i + 2], src[i + 3])
    }

    @inline(__always)
    private static func store4(
        _ dst: inout [Double], _ row: Int, _ x: Int, _ width: Int, _ v: SIMD4<Double>
    ) {
        let i = (row * width + x) * 4
        dst[i] = v.x; dst[i + 1] = v.y; dst[i + 2] = v.z; dst[i + 3] = v.w
    }

    @inline(__always)
    private static func accumulate4(
        _ dst: inout [Double], _ row: Int, _ x: Int, _ width: Int, _ v: SIMD4<Double>
    ) {
        let i = (row * width + x) * 4
        dst[i] += v.x; dst[i + 1] += v.y; dst[i + 2] += v.z; dst[i + 3] += v.w
    }
}

/// The IIR coefficient bundle — GaussianBlur.coeffs (the float32 grid the
/// GPU uniform carries) widened to Double for the recursion. Kept local so
/// the reference owns no mutable state and imports nothing from Metal.
enum GaussianBlurLike {
    struct Coeffs {
        var a0: Double, a1: Double, a2: Double, a3: Double
        var b1: Double, b2: Double, coefp: Double, coefn: Double
    }

    /// dt `_compute_gauss_params` ZERO-order branch (gaussian.c:57-67),
    /// derived in Double then quantized to the float32 grid — the EXACT
    /// values GaussianBlur.coeffs publishes (mirrors the production CPU
    /// half; the float32 quantization is what makes the reference match
    /// the GPU's uniform-fed recursion).
    static func coeffs(sigma: Float) -> Coeffs {
        let alpha = 1.695 / Double(sigma)
        let ema = Foundation.exp(-alpha)
        let ema2 = Foundation.exp(-2.0 * alpha)
        let b1 = -2.0 * ema
        let b2 = ema2
        let k = (1.0 - ema) * (1.0 - ema) / (1.0 + (2.0 * alpha * ema) - ema2)
        let a0 = k
        let a1 = k * (alpha - 1.0) * ema
        let a2 = k * (alpha + 1.0) * ema
        let a3 = -k * ema2
        let coefp = (a0 + a1) / (1.0 + b1 + b2)
        let coefn = (a2 + a3) / (1.0 + b1 + b2)
        func f32(_ v: Double) -> Double { Double(Float(v)) }
        return Coeffs(
            a0: f32(a0), a1: f32(a1), a2: f32(a2), a3: f32(a3),
            b1: f32(b1), b2: f32(b2), coefp: f32(coefp), coefn: f32(coefn))
    }
}
