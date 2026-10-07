import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────
// DehazeReference (Plan 08-5 T1) — the CPU float64 twin of the dehaze chain
// (the golden authority) AND the module's CPU-side ambient-light routine.
//
// Darktable reference (tree dc58cf0ba1): `src/iop/hazeremoval.c` —
//   - windows      :576-583  w1 = 2 + ⌈4·wscale⌉, w2 = 3 + ⌈6·wscale⌉,
//                            wscale = adaptive ? roi.scale/iscale : 1
//   - ambient      :~400-544  `_ambient_light`: dark channel (min-RGB +
//                            box min w1), the 0.95 haze quantile, the 0.95
//                            bright quantile among the hazy pixels, the
//                            mean of the brightest hazy pixels = A0,
//                            distance_max = −1.125·ln(crit_haze_level)
//   - transition   :338-352   t = 1 − min_c(p_c/A0_c)·strength, box max w1
//   - refine       :657       box min w1
//   - smoothing    :659       dt guided_filter(w2, ε=√0.025) — REPLACED by
//                            the box mean (w2) per the FROZEN planner
//                            ruling (the reference is the SAME box form,
//                            so parity is unaffected; visual delta is a
//                            Manual-Only item)
//   - restore      :678-692   t_min = clamp(exp(−d·dmax), 1/1024, 1);
//                            out = (in − A0)/max(t, t_min) + A0
//
// COMPATIBILITY MODE (`compatibility_mode`) is deliberately NOT ported: it
// only selects between dt's fixed and legacy-broken quickselect pivot
// strategies — a CPU-ordering artifact with zero mathematical effect (the
// quantile ORDER STATISTICS are identical). Recorded in 08-5-DECISIONS.
// ─────────────────────────────────────────────────────────────────────────

public enum DehazeReference {

    /// The ambient-grid long edge (the module's decimated statistics plane;
    /// bounded readback + scale-consistent A0 — the dt gui_data sync-pit
    /// answer, D-08-5-T1-2).
    public static let ambientLongEdge = 1024

    // MARK: - Geometry (ONE source of truth — module, kernel uniforms, tests)

    /// hazeremoval.c:576-583, verbatim.
    public static func windowSizes(
        adaptive: Bool, roiScale: Double, iscale: Double
    ) -> (w1: Int, w2: Int) {
        let wscale = adaptive ? min(max(roiScale / max(iscale, 1e-9), 0), 1) : 1.0
        let w1 = 2 + Int(ceil(4.0 * wscale))
        let w2 = 3 + Int(ceil(6.0 * wscale))
        return (w1, w2)
    }

    /// The decimated ambient-grid dims + block size (each grid texel is the
    /// mean of one `block` rectangle of the input). The LONG edge scales to
    /// `ambientLongEdge` (aspect kept); inputs at or below the bound are
    /// identity (block 1×1).
    public static func ambientGridDimensions(
        width: Int, height: Int
    ) -> (gridW: Int, gridH: Int, blockW: Int, blockH: Int) {
        let long = max(width, height)
        let scale = min(1.0, Double(ambientLongEdge) / Double(max(long, 1)))
        let gridW = max(1, Int((Double(width) * scale).rounded()))
        let gridH = max(1, Int((Double(height) * scale).rounded()))
        let blockW = max(1, Int((Double(width) / Double(gridW)).rounded()))
        let blockH = max(1, Int((Double(height) / Double(gridH)).rounded()))
        return (gridW, gridH, blockW, blockH)
    }

    // MARK: - Separable window ops (the box family — float64)

    /// Windowed min, radius `w`, along ONE axis of a single-channel field.
    static func boxMin(_ src: [Double], width: Int, height: Int, w: Int, horizontal: Bool)
        -> [Double] {
        let n = horizontal ? width : height
        let lines = horizontal ? height : width
        var dst = [Double](repeating: 0, count: src.count)
        for line in 0..<lines {
            for i in 0..<n {
                let lo = max(i - w, 0)
                let hi = min(i + w, n - 1)
                var m = Double.infinity
                for k in lo...hi {
                    let v = horizontal ? src[line * width + k] : src[k * width + line]
                    m = min(m, v)
                }
                dst[horizontal ? line * width + i : i * width + line] = m
            }
        }
        return dst
    }

    /// Windowed max, radius `w`, along ONE axis.
    static func boxMax(_ src: [Double], width: Int, height: Int, w: Int, horizontal: Bool)
        -> [Double] {
        let n = horizontal ? width : height
        let lines = horizontal ? height : width
        var dst = [Double](repeating: 0, count: src.count)
        for line in 0..<lines {
            for i in 0..<n {
                let lo = max(i - w, 0)
                let hi = min(i + w, n - 1)
                var m = -Double.infinity
                for k in lo...hi {
                    let v = horizontal ? src[line * width + k] : src[k * width + line]
                    m = max(m, v)
                }
                dst[horizontal ? line * width + i : i * width + line] = m
            }
        }
        return dst
    }

    /// Windowed mean, radius `w`, along ONE axis (the guided-filter
    /// replacement — the frozen planner ruling's box form).
    static func boxMean(_ src: [Double], width: Int, height: Int, w: Int, horizontal: Bool)
        -> [Double] {
        let n = horizontal ? width : height
        let lines = horizontal ? height : width
        var dst = [Double](repeating: 0, count: src.count)
        for line in 0..<lines {
            for i in 0..<n {
                let lo = max(i - w, 0)
                let hi = min(i + w, n - 1)
                var sum = 0.0
                for k in lo...hi {
                    sum += horizontal ? src[line * width + k] : src[k * width + line]
                }
                dst[horizontal ? line * width + i : i * width + line] = sum / Double(hi - lo + 1)
            }
        }
        return dst
    }

    // MARK: - The ambient light (hazeremoval.c `_ambient_light` mirror)

    public struct Ambient: Equatable, Sendable {
        public var a0: SIMD3<Double>
        public var distanceMax: Double

        public init(a0: SIMD3<Double>, distanceMax: Double) {
            self.a0 = a0
            self.distanceMax = distanceMax
        }
    }

    /// The diffusive ambient light + the maximal image depth, from an RGBA
    /// (float64) plane — the `_ambient_light` order-statistics mirror. The
    /// module calls THIS (converting its Float grid) so the golden and the
    /// production share one implementation.
    ///
    /// `planeW`/`planeH` are the PLANE the statistics run on (the module's
    /// decimated grid); `w1` is the dark-channel window already scaled to
    /// that plane by the caller.
    public static func ambientLight(
        _ plane: [Double], planeW: Int, planeH: Int, w1: Int
    ) -> Ambient {
        let size = planeW * planeH
        guard size > 0 else {
            return Ambient(a0: SIMD3(1, 1, 1), distanceMax: 0)
        }
        // Dark channel: per-pixel min over RGB, then box min w1.
        var dark = [Double](repeating: 0, count: size)
        var sums = [Double](repeating: 0, count: size)
        for i in 0..<size {
            let r = plane[i * 4], g = plane[i * 4 + 1], b = plane[i * 4 + 2]
            dark[i] = min(r, min(g, b))
            sums[i] = r + g + b
        }
        dark = boxMin(dark, width: planeW, height: planeH, w: w1, horizontal: true)
        dark = boxMin(dark, width: planeW, height: planeH, w: w1, horizontal: false)

        // Quantile 0.95 of the dark channel (the `(size_t)(size*0.95)` order
        // statistic — quickselect in dt, a sort here: identical value).
        let darkSorted = dark.sorted()
        let hazeIndex = min(Int(Double(size) * 0.95), size - 1)
        let critHazeLevel = darkSorted[hazeIndex]

        // The brightest (sum-RGB) pixels among the most hazy: quantile 0.95.
        var hazy: [Double] = []
        hazy.reserveCapacity(size)
        for i in 0..<size where dark[i] >= critHazeLevel {
            hazy.append(sums[i])
        }
        var critBrightness = Double.infinity
        if !hazy.isEmpty {
            let hazySorted = hazy.sorted()
            let brightIndex = min(Int(Double(hazy.count) * 0.95), hazy.count - 1)
            critBrightness = hazySorted[brightIndex]
        }

        // Mean over the bright hazy pixels = A0.
        var a0 = SIMD3<Double>(0, 0, 0)
        var count = 0
        for i in 0..<size {
            if dark[i] >= critHazeLevel && sums[i] >= critBrightness {
                a0.x += plane[i * 4]
                a0.y += plane[i * 4 + 1]
                a0.z += plane[i * 4 + 2]
                count += 1
            }
        }
        if count > 0 {
            a0 /= Double(count)
        } else {
            a0 = SIMD3(1, 1, 1)
        }

        // The maximal depth (hazeremoval.c:539-544): −1.125·ln(crit); the
        // haze-free degenerate case returns half of ln(FLT_MAX).
        let distanceMax: Double = critHazeLevel > 0
            ? -1.125 * Foundation.log(critHazeLevel)
            : Foundation.log(Double(Float.greatestFiniteMagnitude)) / 2
        return Ambient(a0: a0, distanceMax: distanceMax)
    }

    // MARK: - The full chain (the float64 golden, box-approximation form)

    /// The complete dehaze on an RGBA float64 plane: transition → box max w1
    /// → box min w1 → box mean w2 (the guided replacement) → restore. The
    /// SAME chain the module drives on the GPU, so the parity loop is closed.
    public static func fullChain(
        _ input: [Double], width: Int, height: Int,
        strength: Double, distance: Double,
        ambient: Ambient, w1: Int, w2: Int
    ) -> [Double] {
        let size = width * height
        // Transition map (t = 1 − min_c(p_c/A0_c)·strength).
        var t = [Double](repeating: 0, count: size)
        for i in 0..<size {
            let r = input[i * 4] / ambient.a0.x
            let g = input[i * 4 + 1] / ambient.a0.y
            let b = input[i * 4 + 2] / ambient.a0.z
            t[i] = 1.0 - min(r, min(g, b)) * strength
        }
        // dt order: box MAX w1 (inside `_transition_map`), then box MIN w1
        // (the refine), then the w2 smoothing (guided → box mean here).
        t = boxMax(t, width: width, height: height, w: w1, horizontal: true)
        t = boxMax(t, width: width, height: height, w: w1, horizontal: false)
        t = boxMin(t, width: width, height: height, w: w1, horizontal: true)
        t = boxMin(t, width: width, height: height, w: w1, horizontal: false)
        t = boxMean(t, width: width, height: height, w: w2, horizontal: true)
        t = boxMean(t, width: width, height: height, w: w2, horizontal: false)
        // Restore.
        let tMin = min(max(Foundation.exp(-distance * ambient.distanceMax), 1.0 / 1024.0), 1.0)
        var output = [Double](repeating: 0, count: size * 4)
        for i in 0..<size {
            let tt = max(t[i], tMin)
            output[i * 4] = (input[i * 4] - ambient.a0.x) / tt + ambient.a0.x
            output[i * 4 + 1] = (input[i * 4 + 1] - ambient.a0.y) / tt + ambient.a0.y
            output[i * 4 + 2] = (input[i * 4 + 2] - ambient.a0.z) / tt + ambient.a0.z
            output[i * 4 + 3] = input[i * 4 + 3]
        }
        return output
    }
}
