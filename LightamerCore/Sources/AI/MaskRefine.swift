import Accelerate
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MaskRefine (Plan LUMEN-C T1, X8) — sample-based matting refinement of an AI
// quick mask on a larger developed guide image, for hair, fur, branches and
// other fine edges.
//
// ATTRIBUTION (NOTICE entry Q, Lumen RAW): the algorithm ideas and constant
// calibrations derive from LUMEN RAW (https://github.com/LeisureLinux/lumen,
// MIT License, Copyright (c) 2026 LUMEN RAW contributors) — `lumen/selection.py`
// `fine()`/`_spread()`/`_guided()`/`_blur()`/`fine_size()` at tag v2.0.1 are
// transliterated here (five-step literal port: the band/erode unknown band,
// the multi-scale normalised-convolution spread, the projection + confidence
// core, the steep/detail gate, the smoothstep blend + grow/shrink clamp).
// The implementation is independent Swift/Accelerate — no OpenCV, no upstream
// code copied.
//
// TWO-STAGE FORM: the quick pass (AIMaskService, zero-diff consumer here)
// produces `alpha`; this file refines it on the developed display-domain
// guide (≤ fineEdge long edge — `fineSize` is the transliterated limiter the
// coordinator applies, and `fine` re-asserts the clamp defensively).
//
// FIVE STEPS (the constants are the transliterated calibrations — DO NOT
// retune: band 0.75, σ ladder {.5, 2, 8, 32}, support .08, separation
// .08², residual .25·|d| + .02, gate slope .15, detail normalization,
// eps 1e-4/1e-3):
//   1. Coarse alpha bilinear-upsampled to guide size; band = 0.75 network
//      pixels (min 3); the CERTAIN regions erode out of
//      (α≥.99)/(α≤.01) leaving the unknown band between them.
//   2. `_spread`: the known regions' colours carry into the band by
//      multi-scale normalised convolution (σ = band·{.5,2,8,32}), each
//      scale filling only where the finer ones lacked support.
//   3. Projection alpha = clamp(⟨guide−bg, d⟩/|d|²) (sampling-based
//      matting) + confidence from separation and residual.
//   4. Gate: confidence × clip(max(edge steepness, photo detail), 0, 1)² —
//      where the mask is a broad ramp over smooth tones (haze, depth) the
//      colours do not say what belongs, so the quick pass stays.
//   5. Blend the guided quick alpha with the sampled alpha by confidence,
//      smoothstep into the known regions over one band, then the
//      grow/shrink clamp (the colours may overrule the network only
//      inside its allowed band).
//
// IMPLEMENTATION DOMAIN (red line): Accelerate/vDSP on the CPU — ZERO new
// Metal kernels (the Metal framework is deliberately NOT imported here).
// The cv2 primitives map
// as: boxFilter → exact prefix-sum box (reflect-101 padding = cv2
// BORDER_REFLECT), GaussianBlur → analytic separable kernel with Lumen's
// reduced-copy trick at large σ, erode/dilate → chamfer-distance /
// running-max formulations (±1 px band-boundary class vs cv2's ellipse
// rasterisation — registered in LUMEN-C-DECISIONS), distanceTransform →
// two-pass chamfer (DIST_L2 mask-3 weights 1/√2).
// ─────────────────────────────────────────────────────────────────────────────

/// The developed display-domain guide image the fine pass looks at:
/// interleaved RGBA floats in [0, 1], row 0 = image TOP (the AIMaskPlane
/// buffer orientation — the two are pixel-aligned by construction).
public struct MaskRefineGuide: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major RGBA, `width * height * 4` floats, display values 0-1.
    public let rgba: [Float]

    public init(width: Int, height: Int, rgba: [Float]) {
        precondition(rgba.count == width * height * 4, "MaskRefineGuide count mismatch")
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public enum MaskRefine {

    /// Long edge of a fine mask (the FINE_EDGE transliteration): the guide
    /// is refined at most at this size. The file's single clamp constant.
    public static let fineEdge = 4096

    /// Size of the guide a fine mask is refined on: the original, at most
    /// `fineEdge` long (`fine_size` transliteration — the coordinator's
    /// decode leg uses this BEFORE rendering the guide).
    public static func fineSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let ratio = min(1.0, Double(fineEdge) / Double(max(width, height)))
        return (
            max(1, Int((Double(width) * ratio).rounded())),
            max(1, Int((Double(height) * ratio).rounded()))
        )
    }

    /// The five-step fine pass. `alpha` is the quick mask (any resolution —
    /// it is bilinearly upsampled to the guide); `guide` is the developed
    /// display image (clamped to `fineEdge` internally); `networkPx` is the
    /// quick pass' characteristic resolution (the transliterated default
    /// 320); `grow`/`shrink` bound how far the colours may overrule the
    /// quick mask (Lumen `fine()` defaults .05/.05; its sky calibration is
    /// .3/.02). Returns the refined plane at the CLAMPED guide size.
    public static func fine(
        alpha: AIMaskPlane,
        guide: MaskRefineGuide,
        networkPx: Int,
        grow: Double,
        shrink: Double
    ) -> AIMaskPlane {
        // Defensive clamp (the coordinator applies `fineSize` upstream).
        let (w, h) = fineSize(width: guide.width, height: guide.height)
        let guideRGBA = (w == guide.width && h == guide.height)
            ? guide.rgba
            : resizeAreaRGBA(guide.rgba, sw: guide.width, sh: guide.height, dw: w, dh: h)
        let r = deinterleave(guideRGBA, channel: 0, count: w * h)
        let g = deinterleave(guideRGBA, channel: 1, count: w * h)
        let b = deinterleave(guideRGBA, channel: 2, count: w * h)

        // ── Step 1: the uncertain band ──────────────────────────────────
        let coarse = resizeBilinear(
            alpha.floats, sw: alpha.width, sh: alpha.height, dw: w, dh: h)
        let pixel = Float(max(h, w)) / Float(max(networkPx, 1))
        let band = max(3, Int((pixel * 0.75).rounded()))
        let certainIn = coarse.map { $0 >= 0.99 }
        let certainOut = coarse.map { $0 <= 0.01 }
        // Erode by the (2·band+1) disc ≈ keep pixels ≥ band from the
        // complement (the chamfer formulation of cv2's ellipse erosion).
        let inside = erode(certainIn, width: w, height: h, radius: Float(band))
        let outside = erode(certainOut, width: w, height: h, radius: Float(band))
        var unknown = [Bool](repeating: false, count: w * h)
        var unknownCount = 0
        var insideCount = 0
        var outsideCount = 0
        for i in 0..<(w * h) {
            unknown[i] = !inside[i] && !outside[i]
            if unknown[i] { unknownCount += 1 }
            if inside[i] { insideCount += 1 }
            if outside[i] { outsideCount += 1 }
        }
        // Nothing to refine (no band / no certainty on one side) → the
        // quick mask passes through unchanged (Lumen's early return).
        if unknownCount == 0 || insideCount == 0 || outsideCount == 0 {
            return AIMaskPlane(width: w, height: h, floats: coarse)
        }
        if ProcessInfo.processInfo.environment["MR_DEBUG"] == "1" {
            fputs("MR: stage1 ok unknown=\(unknownCount) in=\(insideCount) out=\(outsideCount) band=\(band)\n", stderr)
        }

        // ── Step 2: spread the known colours into the band ──────────────
        let guideChannels = [r, g, b]
        let fgChannels = guideChannels.enumerated().map { (_, channel) in
            spread(channel, known: inside, width: w, height: h, band: band)
        }
        let bgChannels = guideChannels.enumerated().map { (_, channel) in
            spread(channel, known: outside, width: w, height: h, band: band)
        }

        // ── Step 3: projection alpha + confidence ───────────────────────
        let n = w * h
        var d0 = [Float](repeating: 0, count: n)
        var d1 = [Float](repeating: 0, count: n)
        var d2 = [Float](repeating: 0, count: n)
        var separation = [Float](repeating: 0, count: n)
        var projected = [Float](repeating: 0, count: n)
        var residual = [Float](repeating: 0, count: n)
        let gr = guideChannels[0], gg = guideChannels[1], gb = guideChannels[2]
        let f0 = fgChannels[0], f1 = fgChannels[1], f2 = fgChannels[2]
        let b0 = bgChannels[0], b1 = bgChannels[1], b2 = bgChannels[2]
        for i in 0..<n {
            let e0 = f0[i] - b0[i], e1 = f1[i] - b1[i], e2 = f2[i] - b2[i]
            d0[i] = e0; d1[i] = e1; d2[i] = e2
            let sep = e0 * e0 + e1 * e1 + e2 * e2
            separation[i] = sep
            let p0 = gr[i] - b0[i], p1 = gg[i] - b1[i], p2 = gb[i] - b2[i]
            let dot = p0 * e0 + p1 * e1 + p2 * e2
            projected[i] = min(max(dot / (sep + 1e-4), 0), 1)
            let t = projected[i]
            let q0 = p0 - e0 * t, q1 = p1 - e1 * t, q2 = p2 - e2 * t
            residual[i] = (q0 * q0 + q1 * q1 + q2 * q2).squareRoot()
        }
        var confidence = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let sep = separation[i]
            let ratio = residual[i] / (0.25 * sep.squareRoot() + 0.02)
            let decay = (ratio * ratio).exponentiating() // exp(−ratio²)
            confidence[i] = sep / (sep + 0.08 * 0.08) * decay
        }

        // ── Step 4: the steep/detail gate ───────────────────────────────
        let blurredCoarse = blur(coarse, width: w, height: h, sigma: Float(band) * 0.5)
        var steepSource = gradientMagnitude(blurredCoarse, width: w, height: h)
        for i in 0..<n { steepSource[i] *= Float(4 * band) }
        let steep = dilate(steepSource, width: w, height: h, radius: band)
        let detail = detailEnergy(guideChannels, width: w, height: h, sigma: Float(band) * 0.5)
        for i in 0..<n {
            // The photo-detail arm is normalised by the separation slope
            // (the transliterated .15·√sep + .01) BEFORE the max.
            let detailNorm = detail[i] / (0.15 * separation[i].squareRoot() + 0.01)
            var gateValue = max(steep[i], detailNorm)
            gateValue = min(max(gateValue, 0), 1)
            confidence[i] *= gateValue * gateValue
        }

        // ── Step 5: blend, smoothstep into the known, grow/shrink clamp ─
        let smoothGuided = guidedFilter(
            guideLuma: luma(gr, gg, gb), p: coarse, width: w, height: h,
            radius: max(2, band / 2), eps: 1e-3)
        var mixedInput = [Float](repeating: 0, count: n)
        for i in 0..<n {
            mixedInput[i] = confidence[i] * projected[i] + (1 - confidence[i]) * smoothGuided[i]
        }
        let mixed = guidedFilter(
            guideLuma: luma(gr, gg, gb), p: mixedInput, width: w, height: h,
            radius: 1, eps: 1e-4)
        // Distance of every unknown pixel to the nearest known one (the
        // two-pass chamfer, DIST_L2 mask-3 weights).
        var knownMap = unknown
        for i in 0..<n { knownMap[i] = !unknown[i] }
        let distance = chamferDistance(toZeroOf: knownMap, width: w, height: h)
        var result = [Float](repeating: 0, count: n)
        let growF = Float(max(grow, 1e-3))
        let shrinkF = Float(max(shrink, 1e-3))
        for i in 0..<n {
            let t = min(max(distance[i] / Float(band), 0), 1)
            let wgt = t * t * (3 - 2 * t)
            var value = mixed[i] * (1 - wgt) + (inside[i] ? 1 : 0) * wgt
            value = min(max(value, 0), 1)
            // The colours may raise a pixel the network gave at least
            // `grow`, and lower one at most 1 − `shrink`.
            if value > coarse[i] {
                let up = min(max(coarse[i] / growF, 0), 1)
                value = coarse[i] + (value - coarse[i]) * up
            } else if value < coarse[i] {
                let down = min(max((1 - coarse[i]) / shrinkF, 0), 1)
                value = coarse[i] - (coarse[i] - value) * down
            }
            result[i] = min(max(value, 0), 1)
        }
        return AIMaskPlane(width: w, height: h, floats: result)
    }

    // MARK: - _spread (multi-scale normalised convolution)

    /// Colours of the `known` pixels carried into their surroundings:
    /// normalised convolution at increasing scales, each filling only where
    /// the finer ones had too little support (`_spread` transliteration).
    private static func spread(
        _ image: [Float], known: [Bool], width: Int, height: Int, band: Int
    ) -> [Float] {
        let n = width * height
        var result = [Float](repeating: 0, count: n)
        var filled = [Float](repeating: 0, count: n)
        var weight = [Float](repeating: 0, count: n)
        var weighted = [Float](repeating: 0, count: n)
        var knownSum: Float = 0
        for i in 0..<n where known[i] {
            weight[i] = 1
            weighted[i] = image[i]
            knownSum += 1
        }
        for scale in [0.5, 2.0, 8.0, 32.0] {
            let sigma = Float(band) * Float(scale)
            let support = blur(weight, width: width, height: height, sigma: sigma)
            let blurredWeighted = blur(weighted, width: width, height: height, sigma: sigma)
            for i in 0..<n {
                let s = max(support[i], 1e-6)
                let colour = blurredWeighted[i] / s
                let take = min(max(support[i] / 0.08, 0), 1) * (1 - filled[i])
                result[i] += colour * take
                filled[i] += take
            }
        }
        // Global-mean fallback where every scale lacked support.
        var mean: Float = 0
        if knownSum > 0 {
            var acc: Float = 0
            for i in 0..<n where known[i] { acc += image[i] }
            mean = acc / knownSum
        }
        for i in 0..<n {
            let rest = 1 - filled[i]
            if rest > 0 { result[i] += mean * rest }
        }
        return result
    }

    // MARK: - _guided (grey guided filter, He et al.)

    private static func luma(_ r: [Float], _ g: [Float], _ b: [Float]) -> [Float] {
        // cv2.COLOR_RGB2GRAY weights.
        var out = [Float](repeating: 0, count: r.count)
        for i in 0..<r.count { out[i] = 0.299 * r[i] + 0.587 * g[i] + 0.114 * b[i] }
        return out
    }

    /// Grey guided filter of `p` with the guide luminance (`_guided`
    /// transliteration; radius r → box window (2r+1)).
    private static func guidedFilter(
        guideLuma i: [Float], p: [Float], width: Int, height: Int,
        radius: Int, eps: Float
    ) -> [Float] {
        let n = width * height
        let meanI = boxFilter(i, width: width, height: height, radius: radius)
        let meanP = boxFilter(p, width: width, height: height, radius: radius)
        var ip = [Float](repeating: 0, count: n)
        var ii = [Float](repeating: 0, count: n)
        for k in 0..<n { ip[k] = i[k] * p[k]; ii[k] = i[k] * i[k] }
        let meanIP = boxFilter(ip, width: width, height: height, radius: radius)
        let meanII = boxFilter(ii, width: width, height: height, radius: radius)
        var a = [Float](repeating: 0, count: n)
        var bMean = [Float](repeating: 0, count: n)
        for k in 0..<n {
            let cov = meanIP[k] - meanI[k] * meanP[k]
            let varI = meanII[k] - meanI[k] * meanI[k] + eps
            a[k] = cov / varI
            bMean[k] = meanP[k] - a[k] * meanI[k]
        }
        let meanA = boxFilter(a, width: width, height: height, radius: radius)
        let meanB = boxFilter(bMean, width: width, height: height, radius: radius)
        var out = [Float](repeating: 0, count: n)
        for k in 0..<n { out[k] = meanA[k] * i[k] + meanB[k] }
        return out
    }

    // MARK: - _blur (large-σ Gaussian through a reduced copy)

    /// Gaussian blur of `x` with a large σ through a reduced copy (the
    /// `_blur` transliteration — cheap at any σ; reflect-101 borders).
    private static func blur(
        _ x: [Float], width: Int, height: Int, sigma: Float
    ) -> [Float] {
        let factor = max(1.0, sigma / 3)
        if factor <= 1.5 {
            return gaussianDirect(x, width: width, height: height, sigma: sigma)
        }
        let dw = max(1, Int((Float(width) / factor).rounded()))
        let dh = max(1, Int((Float(height) / factor).rounded()))
        let small = resizeArea(x, sw: width, sh: height, dw: dw, dh: dh)
        let blurred = gaussianDirect(small, width: dw, height: dh, sigma: sigma / factor)
        return resizeBilinear(blurred, sw: dw, sh: dh, dw: width, dh: height)
    }

    /// Separable analytic Gaussian (radius 3σ), reflect-101 borders.
    private static func gaussianDirect(
        _ x: [Float], width: Int, height: Int, sigma: Float
    ) -> [Float] {
        let radius = max(1, Int((sigma * 3).rounded(.up)))
        var kernel = [Float](repeating: 0, count: 2 * radius + 1)
        var sum: Float = 0
        for k in -radius...radius {
            let v = exp(-Float(k * k) / (2 * sigma * sigma))
            kernel[k + radius] = v
            sum += v
        }
        for k in kernel.indices { kernel[k] /= sum }
        var temp = [Float](repeating: 0, count: width * height)
        // Horizontal pass.
        for y in 0..<height {
            let row = y * width
            for xx in 0..<width {
                var acc: Float = 0
                for k in -radius...radius {
                    acc += x[row + reflect101(xx + k, width)] * kernel[k + radius]
                }
                temp[row + xx] = acc
            }
        }
        var out = [Float](repeating: 0, count: width * height)
        // Vertical pass.
        for y in 0..<height {
            for xx in 0..<width {
                var acc: Float = 0
                for k in -radius...radius {
                    acc += temp[reflect101(y + k, height) * width + xx] * kernel[k + radius]
                }
                out[y * width + xx] = acc
            }
        }
        return out
    }

    /// cv2 BORDER_REFLECT (reflect-101: the edge sample is not repeated)
    /// for ANY distance — modular folding handles radius > dimension.
    private static func reflect101(_ v: Int, _ limit: Int) -> Int {
        guard limit > 1 else { return 0 }
        var s = abs(v) % (2 * limit - 2)
        if s >= limit { s = 2 * limit - 2 - s }
        return s
    }

    // MARK: - Exact box filter (reflect-101) via prefix sums

    /// cv2.boxFilter(normalize: true, BORDER_REFLECT) — reflect-101 padding
    /// + prefix-sum window means (exact, O(n)).
    private static func boxFilter(
        _ x: [Float], width: Int, height: Int, radius: Int
    ) -> [Float] {
        let pw = width + 2 * radius
        let ph = height + 2 * radius
        var padded = [Float](repeating: 0, count: pw * ph)
        for py in 0..<ph {
            let sy = reflect101(py - radius, height)
            let srcRow = sy * width
            let dstRow = py * pw
            for pxx in 0..<pw {
                padded[dstRow + pxx] = x[srcRow + reflect101(pxx - radius, width)]
            }
        }
        // Prefix sums over the padded plane.
        var integral = [Double](repeating: 0, count: (pw + 1) * (ph + 1))
        for py in 0..<ph {
            var rowAcc: Double = 0
            for pxx in 0..<pw {
                rowAcc += Double(padded[py * pw + pxx])
                integral[(py + 1) * (pw + 1) + (pxx + 1)] =
                    integral[py * (pw + 1) + (pxx + 1)] + rowAcc
            }
        }
        let size = Double((2 * radius + 1) * (2 * radius + 1))
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for xx in 0..<width {
                let x0 = xx, y0 = y
                let x1 = xx + 2 * radius + 1, y1 = y + 2 * radius + 1
                let s = integral[y1 * (pw + 1) + x1] - integral[y0 * (pw + 1) + x1]
                    - integral[y1 * (pw + 1) + x0] + integral[y0 * (pw + 1) + x0]
                out[y * width + xx] = Float(s / size)
            }
        }
        return out
    }

    // MARK: - Erode / dilate

    /// Binary erosion by the (2·radius+1) disc ≈ the chamfer formulation:
    /// a pixel survives when its distance to the complement ≥ radius.
    private static func erode(
        _ binary: [Bool], width: Int, height: Int, radius: Float
    ) -> [Bool] {
        let distance = chamferDistance(toZeroOf: binary, width: width, height: height)
        var out = [Bool](repeating: false, count: binary.count)
        for i in 0..<binary.count { out[i] = binary[i] && distance[i] >= radius }
        return out
    }

    /// Running max filter over a (2·radius+1)² window — separable two-pass
    /// (van Herk); O(n). The rect-vs-ellipse boundary class is registered.
    private static func dilate(
        _ x: [Float], width: Int, height: Int, radius: Int
    ) -> [Float] {
        var temp = [Float](repeating: 0, count: width * height)
        // Horizontal pass.
        for y in 0..<height {
            let row = y * width
            for xx in 0..<width {
                let lo = max(0, xx - radius), hi = min(width - 1, xx + radius)
                var m = x[row + lo]
                for sx in (lo + 1)...hi where x[row + sx] > m { m = x[row + sx] }
                temp[row + xx] = m
            }
        }
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let lo = max(0, y - radius), hi = min(height - 1, y + radius)
            for xx in 0..<width {
                var m = temp[lo * width + xx]
                for sy in (lo + 1)...hi where temp[sy * width + xx] > m {
                    m = temp[sy * width + xx]
                }
                out[y * width + xx] = m
            }
        }
        return out
    }

    /// Two-pass chamfer distance transform: for every pixel of `binary`,
    /// the approximate Euclidean distance (1 / √2 weights — cv2 DIST_L2
    /// mask 3) to the nearest ZERO pixel of `binary`.
    private static func chamferDistance(
        toZeroOf binary: [Bool], width: Int, height: Int
    ) -> [Float] {
        let inf = Float(1e9)
        let sqrt2 = Float(2.0).squareRoot()
        var d = [Float](repeating: inf, count: width * height)
        for i in 0..<d.count where !binary[i] { d[i] = 0 }
        // Forward pass (top-left → bottom-right).
        for y in 0..<height {
            for xx in 0..<width {
                let i = y * width + xx
                var v = d[i]
                if y > 0 { v = min(v, d[i - width] + 1) }
                if xx > 0 { v = min(v, d[i - 1] + 1) }
                if y > 0 && xx > 0 { v = min(v, d[i - width - 1] + sqrt2) }
                if y > 0 && xx < width - 1 { v = min(v, d[i - width + 1] + sqrt2) }
                d[i] = v
            }
        }
        // Backward pass.
        for y in stride(from: height - 1, through: 0, by: -1) {
            for xx in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + xx
                var v = d[i]
                if y < height - 1 { v = min(v, d[i + width] + 1) }
                if xx < width - 1 { v = min(v, d[i + 1] + 1) }
                if y < height - 1 && xx < width - 1 { v = min(v, d[i + width + 1] + sqrt2) }
                if y < height - 1 && xx > 0 { v = min(v, d[i + width - 1] + sqrt2) }
                d[i] = v
            }
        }
        return d
    }

    // MARK: - Gradients / detail energy

    /// np.gradient semantics: interior central differences, one-sided at
    /// the borders; magnitude of (gx, gy).
    private static func gradientMagnitude(
        _ x: [Float], width: Int, height: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for xx in 0..<width {
                let i = y * width + xx
                let xm = xx > 0 ? x[i - 1] : x[i]
                let xp = xx < width - 1 ? x[i + 1] : x[i]
                let ym = y > 0 ? x[i - width] : x[i]
                let yp = y < height - 1 ? x[i + width] : x[i]
                let gx = xx == 0 || xx == width - 1 ? (xp - xm) : (xp - xm) / 2
                let gy = y == 0 || y == height - 1 ? (yp - ym) : (yp - ym) / 2
                out[i] = (gx * gx + gy * gy).squareRoot()
            }
        }
        return out
    }

    /// ‖guide − Gaussian(guide, σ)‖ over the channels, normalised by the
    /// separation slope (.15·√sep + .01 folds into the caller's gate — the
    /// detail arm of the step-4 gate).
    private static func detailEnergy(
        _ channels: [[Float]], width: Int, height: Int, sigma: Float
    ) -> [Float] {
        let n = width * height
        var out = [Float](repeating: 0, count: n)
        for channel in channels {
            let blurred = blur(channel, width: width, height: height, sigma: sigma)
            for i in 0..<n {
                let e = channel[i] - blurred[i]
                out[i] += e * e
            }
        }
        for i in 0..<n { out[i] = out[i].squareRoot() }
        return out
    }

    // MARK: - Resampling (INTER_AREA / INTER_LINEAR semantics)

    /// Generalized area-average downscale (cv2 INTER_AREA semantics:
    /// fractional-coverage box per destination pixel).
    static func resizeArea(
        _ x: [Float], sw: Int, sh: Int, dw: Int, dh: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: dw * dh)
        let sxScale = Float(sw) / Float(dw)
        let syScale = Float(sh) / Float(dh)
        for dy in 0..<dh {
            let y0 = Float(dy) * syScale
            let y1 = Float(dy + 1) * syScale
            for dxx in 0..<dw {
                let x0 = Float(dxx) * sxScale
                let x1 = Float(dxx + 1) * sxScale
                out[dy * dw + dxx] = areaSample(
                    x, sw: sw, sh: sh, x0: x0, x1: x1, y0: y0, y1: y1)
            }
        }
        return out
    }

    static func resizeAreaRGBA(
        _ x: [Float], sw: Int, sh: Int, dw: Int, dh: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: dw * dh * 4)
        let sxScale = Float(sw) / Float(dw)
        let syScale = Float(sh) / Float(dh)
        for dy in 0..<dh {
            let y0 = Float(dy) * syScale
            let y1 = Float(dy + 1) * syScale
            for dxx in 0..<dw {
                let x0 = Float(dxx) * sxScale
                let x1 = Float(dxx + 1) * sxScale
                let dst = (dy * dw + dxx) * 4
                for c in 0..<4 {
                    var acc: Float = 0
                    let iy0 = max(0, Int(y0)), iy1 = min(sh, Int(y1.rounded(.up)))
                    let ix0 = max(0, Int(x0)), ix1 = min(sw, Int(x1.rounded(.up)))
                    for sy in iy0..<iy1 {
                        let wy = overlap(y0, y1, Float(sy), Float(sy + 1))
                        if wy == 0 { continue }
                        for sx in ix0..<ix1 {
                            let wx = overlap(x0, x1, Float(sx), Float(sx + 1))
                            if wx == 0 { continue }
                            acc += x[(sy * sw + sx) * 4 + c] * wx * wy
                        }
                    }
                    out[dst + c] = acc / ((x1 - x0) * (y1 - y0))
                }
            }
        }
        return out
    }

    private static func overlap(_ a0: Float, _ a1: Float, _ b0: Float, _ b1: Float) -> Float {
        max(0, min(a1, b1) - max(a0, b0))
    }

    private static func areaSample(
        _ x: [Float], sw: Int, sh: Int, x0: Float, x1: Float, y0: Float, y1: Float
    ) -> Float {
        var acc: Float = 0
        let iy0 = max(0, Int(y0)), iy1 = min(sh, Int(y1.rounded(.up)))
        let ix0 = max(0, Int(x0)), ix1 = min(sw, Int(x1.rounded(.up)))
        for sy in iy0..<iy1 {
            let wy = overlap(y0, y1, Float(sy), Float(sy + 1))
            if wy == 0 { continue }
            for sx in ix0..<ix1 {
                let wx = overlap(x0, x1, Float(sx), Float(sx + 1))
                if wx == 0 { continue }
                acc += x[sy * sw + sx] * wx * wy
            }
        }
        return acc / ((x1 - x0) * (y1 - y0))
    }

    /// Bilinear resample (cv2 INTER_LINEAR semantics: dest centers mapped
    /// by (d + 0.5)·scale − 0.5).
    static func resizeBilinear(
        _ x: [Float], sw: Int, sh: Int, dw: Int, dh: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: dw * dh)
        let sxScale = Float(sw) / Float(dw)
        let syScale = Float(sh) / Float(dh)
        for dy in 0..<dh {
            let fy = (Float(dy) + 0.5) * syScale - 0.5
            let y0 = Int(fy.rounded(.down))
            let wy = fy - Float(y0)
            let yc0 = min(max(y0, 0), sh - 1)
            let yc1 = min(max(y0 + 1, 0), sh - 1)
            for dxx in 0..<dw {
                let fxx = (Float(dxx) + 0.5) * sxScale - 0.5
                let x0 = Int(fxx.rounded(.down))
                let wx = fxx - Float(x0)
                let xc0 = min(max(x0, 0), sw - 1)
                let xc1 = min(max(x0 + 1, 0), sw - 1)
                let v00 = x[yc0 * sw + xc0], v10 = x[yc0 * sw + xc1]
                let v01 = x[yc1 * sw + xc0], v11 = x[yc1 * sw + xc1]
                out[dy * dw + dxx] =
                    v00 * (1 - wx) * (1 - wy) + v10 * wx * (1 - wy)
                    + v01 * (1 - wx) * wy + v11 * wx * wy
            }
        }
        return out
    }

    // MARK: - Small helpers

    private static func deinterleave(
        _ rgba: [Float], channel: Int, count: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count { out[i] = rgba[i * 4 + channel] }
        return out
    }
}

private extension Float {
    /// exp(−x²) (named for the confidence form's readability).
    func exponentiating() -> Float { exp(-self) }
}
