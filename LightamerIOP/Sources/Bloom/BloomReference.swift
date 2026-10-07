import Foundation

// ─────────────────────────────────────────────────────────────────────────
// BloomReference — Plan 08-2 T3 golden authority (the CPU float64 twin of
// the whole bloom chain; the 12-5 遗留#5 double-write doctrine).
//
// Mirrors, line by line:
//   - stage ①: bloom.cl:22-38 + the linear-domain mapping (research §9.2:
//     L_lin = luma/4.0 · scale(strength), thr_lin = (threshold/100)³);
//   - stage ②: the cascade — ÷8 box downsample (clamped borders) + the
//     small-σ separable truncated gaussian (r = ⌈2σ⌉, normalized weights,
//     clamped borders) at 1/8 resolution;
//   - stage ③: the hand-written bilinear upsample (the kernel's exact
//     center-preserving mapping (p+0.5)/8 − 0.5 and clamped 4-tap shape)
//     + the linear screen blend 1 − (1−a)(1−b).
//
// Cross-implementation comparison runs at 1e-5 ABSOLUTE on the final
// pixels: the chain stacks box averaging, two gaussian passes, a bilinear
// fetch and a screen blend — the float32 accumulation floor lands at
// ~1e-5 for 8-bit-scale glow values (D-08-2-B5; bitwise equality is
// kernel-vs-kernel determinism, not cross-implementation).
// ─────────────────────────────────────────────────────────────────────────

public enum BloomReference {

    // MARK: - stage ① threshold (the kernel's bloom_threshold twin)

    /// The Rec2020 linear luma (the kernel's coefficients).
    static func luma(_ rgb: SIMD3<Double>) -> Double {
        0.2627 * rgb.x + 0.6780 * rgb.y + 0.0593 * rgb.z
    }

    /// Stage ① for one pixel — the thresholded glow magnitude. The domain
    /// mapping: luma / 4.0 (filmic white anchor, research §9.2) · scale.
    public static func thresholdPixel(
        _ rgb: SIMD3<Double>, scale: Double, thrLin: Double
    ) -> Double {
        let l = luma(rgb) * (1.0 / 4.0) * scale
        return l > thrLin ? l : 0.0
    }

    // MARK: - stage ②a the ÷8 box downsample

    /// `smallW×smallH` geometry from the full resolution (`ceil(/8)` — the
    /// kernel covers the tail block with clamped reads).
    public static func smallSize(fullW: Int, fullH: Int) -> (w: Int, h: Int) {
        (w: (fullW + 7) / 8, h: (fullH + 7) / 8)
    }

    /// The box-downsampled glow plane at 1/8 resolution (clamped borders —
    /// the kernel's clamp shape). `glow[y][x]` indexed [row][col].
    public static func boxDownsample(
        _ glow: [[Double]], fullW: Int, fullH: Int
    ) -> [[Double]] {
        let small = smallSize(fullW: fullW, fullH: fullH)
        var out = Array(
            repeating: Array(repeating: 0.0, count: small.w), count: small.h)
        for sy in 0..<small.h {
            for sx in 0..<small.w {
                var acc = 0.0
                for dy in 0..<8 {
                    let y = min(max(sy * 8 + dy, 0), fullH - 1)
                    for dx in 0..<8 {
                        let x = min(max(sx * 8 + dx, 0), fullW - 1)
                        acc += glow[y][x]
                    }
                }
                out[sy][sx] = acc / 64.0
            }
        }
        return out
    }

    // MARK: - stage ②b the small-σ separable gaussian

    /// One normalized 1-D pass (X or Y) of the truncated gaussian over the
    /// small plane. Mirrors `bloom_gauss_pass` exactly: in-kernel weight
    /// `exp(−k²/2σ²)`, normalized by the running weight sum, clamped index.
    public static func gaussPass(
        _ plane: [[Double]], sigma: Double, radius: Int, horizontal: Bool
    ) -> [[Double]] {
        let h = plane.count, w = h > 0 ? plane[0].count : 0
        var out = Array(repeating: Array(repeating: 0.0, count: w), count: h)
        for y in 0..<h {
            for x in 0..<w {
                var acc = 0.0
                var wsum = 0.0
                for k in -radius...radius {
                    let weight = Foundation.exp(
                        -(Double(k) * Double(k)) / (2.0 * sigma * sigma))
                    let cx = horizontal ? min(max(x + k, 0), w - 1) : x
                    let cy = horizontal ? y : min(max(y + k, 0), h - 1)
                    acc += weight * plane[cy][cx]
                    wsum += weight
                }
                out[y][x] = acc / wsum
            }
        }
        return out
    }

    // MARK: - stage ③ bilinear upsample + screen

    /// The kernel's bilinear fetch (clamped 4-tap, the exact same index
    /// and weight arithmetic).
    static func sampleBilinear(
        _ plane: [[Double]], sx: Double, sy: Double
    ) -> Double {
        let h = plane.count, w = h > 0 ? plane[0].count : 0
        let x0 = Int(Foundation.floor(sx)), y0 = Int(Foundation.floor(sy))
        let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
        let cx0 = min(max(x0, 0), w - 1), cy0 = min(max(y0, 0), h - 1)
        let tx = sx - Double(x0), ty = sy - Double(y0)
        let g00 = plane[cy0][cx0]
        let g10 = plane[cy0][x1]
        let g01 = plane[y1][cx0]
        let g11 = plane[y1][x1]
        return (1 - tx) * (1 - ty) * g00 + tx * (1 - ty) * g10
             + (1 - tx) * ty * g01 + tx * ty * g11
    }

    /// Stage ③ for one pixel — the linear screen blend with the upsampled
    /// glow (`1 − (1−a)(1−b)` per channel; alpha untouched by the caller).
    public static func screenPixel(
        _ rgb: SIMD3<Double>, glow: [[Double]], px: Int, py: Int
    ) -> SIMD3<Double> {
        let sx = (Double(px) + 0.5) / 8.0 - 0.5
        let sy = (Double(py) + 0.5) / 8.0 - 0.5
        let b = sampleBilinear(glow, sx: sx, sy: sy)
        return SIMD3<Double>(
            repeating: 1.0) - (SIMD3<Double>(repeating: 1.0) - rgb) * (1.0 - b)
    }

    // MARK: - the whole chain (test-side helper)

    /// The full three-stage chain over a float64 image (row-major RGBA).
    /// `geometry` is the module's `Geometry` (one source of truth).
    /// `internal` — the golden consumers are the @testable tests.
    static func chain(
        _ rgba: [Float], width: Int, height: Int, geometry: BloomModule.Geometry
    ) -> [Double] {
        // ① threshold
        var glow = Array(
            repeating: Array(repeating: 0.0, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                let k = (y * width + x) * 4
                let rgb = SIMD3<Double>(
                    Double(rgba[k]), Double(rgba[k + 1]), Double(rgba[k + 2]))
                glow[y][x] = thresholdPixel(
                    rgb, scale: geometry.scale, thrLin: geometry.thrLin)
            }
        }
        // ② cascade (box ÷8 → gauss X → gauss Y)
        var small = boxDownsample(glow, fullW: width, fullH: height)
        small = gaussPass(small, sigma: geometry.sigmaSmall,
                          radius: geometry.gaussRadiusSmall, horizontal: true)
        small = gaussPass(small, sigma: geometry.sigmaSmall,
                          radius: geometry.gaussRadiusSmall, horizontal: false)
        // ③ screen (alpha passthrough)
        var out = [Double](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let k = (y * width + x) * 4
                let rgb = SIMD3<Double>(
                    Double(rgba[k]), Double(rgba[k + 1]), Double(rgba[k + 2]))
                let screened = screenPixel(rgb, glow: small, px: x, py: y)
                out[k] = screened.x
                out[k + 1] = screened.y
                out[k + 2] = screened.z
                out[k + 3] = Double(rgba[k + 3])
            }
        }
        return out
    }
}
