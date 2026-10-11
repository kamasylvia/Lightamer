import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MertensFusion (Plan M5-2-01 T1; KD-1/KD-2/KD-3) — Mertens exposure fusion
// (Mertens-Kaus-Mey-Seidel 2007, "Exposure Fusion") as PURE CPU functions on
// RGBA float32 planes. Behavior anchor = OpenCV `createMergeMertens(1.,1.,1.)`
// defaults (wc = ws = we = 1.0, σ = 0.2 — the constants Lumen passes at
// merge.py:167). OpenCV itself NEVER enters this repository (zero new SPM).
//
// MIT ATTRIBUTION (CONVENTIONS 参考项目节): Portions derived from Lumen RAW
// (lumen-raw, MIT) — the deghost tier table, the 33-point quantile brightness
// mapping, the usable-gate clipping semantics, and the fuse-before-substitute
// reference replacement (lumen/merge.py:120-169). Swift rewrite; the tier
// constants and gate bounds are Lumen's measured values, transplanted verbatim.
//
// DOMAIN (KD-1 / OQ-6): the fusion works entirely in the sRGB piecewise
// DISPLAY code domain [0,1] — `DrtEotfMath.srgbPiecewiseEncode` (the Core-side
// seam; IOP's LutEncodingCatalog is unreachable from Core, the module DAG runs
// IOP → Core only). The encode function clamps its input to [0,1], so the
// display-domain clamp convention (superwhite clips, negatives floor) holds
// by construction. Callers feed linear Rec2020 float32 planes through
// `displayEncodePlane` first.
//
// WEIGHTS (research §1): W = C^wc · S^ws · E^we per pixel,
//   C = |Laplacian(gray)|   — 4-neighbor kernel (OpenCV Laplacian ksize=1),
//   S = population std(R,G,B) (÷N — the OpenCV saturation convention),
//   E = ∏_c exp(−(I_c − 0.5)²/(2σ²)), σ = 0.2.
// Unpinned constants pinned HERE (checker minor-2): gray = Rec709 luma
// (0.2126/0.7152/0.0722 — the plan's binding KD-3 value; OpenCV's
// COLOR_RGB2GRAY uses BT.601, the deghost thresholds are coarse to the
// coefficient choice), saturation = population (÷3) std.
//
// FUSION SHAPE (KD-2): per source — a Gaussian pyramid of its weight map ×
// Laplacian pyramids of its RGB channels; per level the N-independent
// accumulators fold Σ G(Wᵢ)·Lᵢ (numerator) and Σ G(Wᵢ) (denominator); the
// blend normalizes PER LEVEL against max(den, ε) with ε =
// FocusStackMerge.weightEpsilon, then collapses Rₖ = BLₖ + expand(Rₖ₊₁).
// This is the FocusStackMerge.fuseStrip accumulator structure (the 08-3
// accepted fusion face) — the reduce/expand kernel pair (binomial
// [1,4,6,4,1]/16 + linear 2×, DC-consistent, telescoping exact) is REUSED
// internal-static,
// zero-copy. The per-level-ε reading of "Σ G(Ŵ)·L" is recorded in
// M5-2-01-DECISIONS.
//
// DEGHOST (KD-3, merge.py:120-169): tiers low(.20,2) / medium(.12,5) /
// high(.065,9) = (residual threshold, base dilate radius); per frame a
// 33-point quantile brightness mapping onto the reference gray, σ1.2 blur,
// absolute difference, threshold, the (0.015, 0.985) open-interval usable
// gate on BOTH frames' grays, resolution-scaled dilate, Gaussian feather —
// a [0,1] soft motion mask. The static-sample fallback of merge.py:146
// (`static.sum() < 64 → treat the WHOLE grid as static`, checker minor-1)
// is transplanted into `substituteLUTs`. Substitution
// `prepared = original·(1−α) + LUT(ref)·α` runs BEFORE the pyramid fusion —
// pasting the reference after fusion would leave a bright rectangle around
// moving objects (merge.py:153-155's own comment).
//
// THREADING: everything here is sequential and deterministic (G1's
// bit-identity anchor). NaN inputs are a caller contract violation — the
// M5-2-02 streaming leg sanitizes staged strips (the FocusStackMerge
// provider posture); this file does not branch on NaN.
// ─────────────────────────────────────────────────────────────────────────────

public enum MertensFusion {

    // MARK: - Constants (KD-4: file constants, NOT parameters)

    /// The well-exposedness σ (the OpenCV/Lumen default).
    public static let weightSigma: Float = 0.2
    /// The three weight exponents (OpenCV `createMergeMertens(1.,1.,1.)`).
    public static let weightContrastExponent: Float = 1.0
    public static let weightSaturationExponent: Float = 1.0
    public static let weightExposureExponent: Float = 1.0

    /// Rec709 luma (the KD-3 gray convention — see the header note).
    public static let grayCoefficients = (r: Float(0.2126), g: Float(0.7152), b: Float(0.0722))

    /// The usable-gate open interval (merge.py:134 — clipped exposures carry
    /// no motion evidence).
    public static let usableGateLow: Float = 0.015
    public static let usableGateHigh: Float = 0.985

    /// The σ1.2 blur the residual path runs before differencing (merge.py:123).
    static let residualBlurSigma: Float = 1.2

    // MARK: - Display encoding (KD-1 — the DrtEotf seam)

    /// linear Rec2020 float32 plane → sRGB piecewise display codes. The
    /// curve clamps to [0,1] (DrtEotf's own convention — the KD-1 clamp
    /// holds by construction).
    public static func displayEncodePlane(_ linear: [Float]) -> [Float] {
        linear.map { Float(DrtEotfMath.srgbPiecewiseEncode(Double($0))) }
    }

    /// The exact inverse (tests / diagnostics).
    public static func displayDecodePlane(_ code: [Float]) -> [Float] {
        code.map { Float(DrtEotfMath.srgbPiecewiseDecode(Double($0))) }
    }

    // MARK: - The three weight factors

    /// Rec709 luma of an RGBA plane.
    public static func grayPlane(
        _ rgba: [Float], width: Int, height: Int
    ) -> [Float] {
        precondition(rgba.count == width * height * 4, "mertens gray: plane size mismatch")
        var gray = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            gray[index] = grayCoefficients.r * rgba[base]
                + grayCoefficients.g * rgba[base + 1]
                + grayCoefficients.b * rgba[base + 2]
        }
        return gray
    }

    /// |Laplacian| with the 4-neighbor kernel, clamped edges (the OpenCV
    /// ksize=1 contrast factor).
    public static func contrastPlane(
        _ gray: [Float], width: Int, height: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let center = gray[y * width + x]
                let up = gray[max(0, y - 1) * width + x]
                let down = gray[min(height - 1, y + 1) * width + x]
                let left = gray[y * width + max(0, x - 1)]
                let right = gray[y * width + min(width - 1, x + 1)]
                out[y * width + x] = abs(up + down + left + right - 4 * center)
            }
        }
        return out
    }

    /// Per-pixel population std over RGB (÷3 — the OpenCV convention).
    public static func saturationPlane(
        _ rgba: [Float], width: Int, height: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            let mean = (rgba[base] + rgba[base + 1] + rgba[base + 2]) / 3
            let dr = rgba[base] - mean
            let dg = rgba[base + 1] - mean
            let db = rgba[base + 2] - mean
            out[index] = ((dr * dr + dg * dg + db * db) / 3).squareRoot()
        }
        return out
    }

    /// Per-pixel ∏_c exp(−(I_c − 0.5)²/(2σ²)) (the well-exposedness factor).
    public static func exposureFitPlane(
        _ rgba: [Float], width: Int, height: Int, sigma: Float = MertensFusion.weightSigma
    ) -> [Float] {
        let denominator = 2 * sigma * sigma
        var out = [Float](repeating: 1, count: width * height)
        for index in 0..<(width * height) {
            var product: Float = 1
            for channel in 0..<3 {
                let deviation = rgba[index * 4 + channel] - 0.5
                product *= Foundation.exp(-deviation * deviation / denominator)
            }
            out[index] = product
        }
        return out
    }

    /// The fused weight map W = C^wc · S^ws · E^we (exponents = 1.0 — the
    /// OpenCV defaults; KD-4 keeps them unparameterized).
    public static func weightPlane(
        _ rgba: [Float], width: Int, height: Int
    ) -> [Float] {
        let gray = grayPlane(rgba, width: width, height: height)
        let contrast = contrastPlane(gray, width: width, height: height)
        let saturation = saturationPlane(rgba, width: width, height: height)
        let exposure = exposureFitPlane(rgba, width: width, height: height)
        var out = [Float](repeating: 0, count: width * height)
        for index in out.indices {
            out[index] = Foundation.pow(contrast[index], weightContrastExponent)
                * Foundation.pow(saturation[index], weightSaturationExponent)
                * Foundation.pow(exposure[index], weightExposureExponent)
        }
        return out
    }

    // MARK: - Quantile machinery (the merge.py percentile idioms)

    /// numpy's 'linear' percentile over an ASCENDING sample array.
    static func percentileOfSorted(_ sorted: [Float], _ q: Double) -> Float {
        precondition(!sorted.isEmpty, "mertens percentile: empty sample set")
        guard sorted.count > 1 else { return sorted[0] }
        let rank = q / 100 * Double(sorted.count - 1)
        let lower = min(Int(rank.rounded(.down)), sorted.count - 1)
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = Float(rank - Double(lower))
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    /// The strided decimation grid values (`plane[::step, ::step]`).
    static func stridedSamples(
        _ plane: [Float], width: Int, height: Int, step: Int
    ) -> [Float] {
        var out: [Float] = []
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                out.append(plane[y * width + x])
                x += step
            }
            y += step
        }
        return out
    }

    /// `max(1, ceil(max(dim)/1000))` — the merge.py decimation step.
    static func decimationStep(width: Int, height: Int) -> Int {
        max(1, (max(width, height) + 999) / 1000)
    }

    /// numpy linspace.
    static func linspace(_ a: Double, _ b: Double, _ count: Int) -> [Double] {
        precondition(count >= 2, "mertens linspace: degenerate count")
        let step = (b - a) / Double(count - 1)
        return (0..<count).map { a + step * Double($0) }
    }

    /// np.unique(values, return_index=True) over a NON-DECREASING array —
    /// distinct values ascending + each value's FIRST index.
    static func uniqueWithFirstPositions(_ values: [Float]) -> (values: [Float], positions: [Int]) {
        var unique: [Float] = []
        var positions: [Int] = []
        for (index, value) in values.enumerated() {
            if index == 0 || value != values[index - 1] {
                unique.append(value)
                positions.append(index)
            }
        }
        return (unique, positions)
    }

    /// np.interp with clamped ends over strictly increasing xs.
    public static func interp(_ x: Float, xs: [Float], ys: [Float]) -> Float {
        precondition(xs.count == ys.count && !xs.isEmpty, "mertens interp: table mismatch")
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var low = 0
        var high = xs.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if xs[mid] <= x { low = mid } else { high = mid }
        }
        let span = xs[high] - xs[low]
        guard span > 0 else { return ys[low] }
        let fraction = (x - xs[low]) / span
        return ys[low] * (1 - fraction) + ys[high] * fraction
    }

    /// The 33-point quantile brightness mapping (merge.py:123-131): the
    /// frame's gray percentiles (2%..98%) as xs, the reference's percentiles
    /// at the first-occurrence positions as ys — mapping the frame's gray
    /// INTO the reference's gray domain.
    public static func brightnessMapping(
        frameGray: [Float], referenceGray: [Float], width: Int, height: Int
    ) -> (xs: [Float], ys: [Float]) {
        let step = decimationStep(width: width, height: height)
        let frameSamples = stridedSamples(frameGray, width: width, height: height, step: step)
            .sorted()
        let referenceSamples = stridedSamples(referenceGray, width: width, height: height, step: step)
            .sorted()
        let quantiles = linspace(2, 98, 33)
        let values = quantiles.map { percentileOfSorted(frameSamples, $0) }
        let target = quantiles.map { percentileOfSorted(referenceSamples, $0) }
        let (unique, positions) = uniqueWithFirstPositions(values)
        return (unique, positions.map { target[$0] })
    }

    // MARK: - The deghost motion mask (KD-3, merge.py:120-138)

    /// The soft motion mask ([0,1], w·h). `nil` for `.off` (the whole
    /// deghost segment skips — no mask, no substitution).
    public static func ghostMask(
        frames: [[Float]], reference: Int, level: DeghostLevel,
        width: Int, height: Int
    ) -> [Float]? {
        guard level != .off else { return nil }
        precondition(frames.indices.contains(reference), "mertens ghostMask: bad reference")
        let referenceGray = grayPlane(frames[reference], width: width, height: height)
        let referenceBlur = gaussianBlurGray(
            referenceGray, width: width, height: height, sigma: residualBlurSigma)
        let step = decimationStep(width: width, height: height)
        let referenceSamples = stridedSamples(
            referenceGray, width: width, height: height, step: step).sorted()
        let quantiles = linspace(2, 98, 33)
        let target = quantiles.map { percentileOfSorted(referenceSamples, $0) }

        var motion = [Float](repeating: 0, count: width * height)
        for (index, frame) in frames.enumerated() where index != reference {
            let luma = grayPlane(frame, width: width, height: height)
            let samples = stridedSamples(luma, width: width, height: height, step: step).sorted()
            let values = quantiles.map { percentileOfSorted(samples, $0) }
            let (unique, positions) = uniqueWithFirstPositions(values)
            let mappedTargets = positions.map { target[$0] }
            var mapped = [Float](repeating: 0, count: width * height)
            for pixel in mapped.indices {
                mapped[pixel] = interp(luma[pixel], xs: unique, ys: mappedTargets)
            }
            let mappedBlur = gaussianBlurGray(
                mapped, width: width, height: height, sigma: residualBlurSigma)
            for pixel in motion.indices {
                let usable = luma[pixel] > usableGateLow && luma[pixel] < usableGateHigh
                    && referenceGray[pixel] > usableGateLow
                    && referenceGray[pixel] < usableGateHigh
                if abs(mappedBlur[pixel] - referenceBlur[pixel]) > level.residualThreshold,
                   usable {
                    motion[pixel] = 1
                }
            }
        }
        let radius = max(1, Int(
            (Float(level.baseDilateRadius) * Float(max(width, height)) / 1800).rounded()))
        var dilated = dilate(motion, radius: radius, width: width, height: height)
        dilated = gaussianBlurGray(
            dilated, width: width, height: height, sigma: max(1, Float(radius) / 2))
        for pixel in dilated.indices {
            dilated[pixel] = min(max(dilated[pixel], 0), 1)
        }
        return dilated
    }

    // MARK: - The pre-fusion reference substitution (KD-3, merge.py:141-169)

    /// One channel's quantile LUT (129-point numpy-percentile pairs; xs
    /// strictly increasing).
    public struct ChannelLUT: Sendable, Equatable {
        public let xs: [Float]
        public let ys: [Float]
    }

    /// The static sample mask over the decimated grid (merge.py:144-146).
    /// `true` = a static cell. The merge.py:146 fallback (checker minor-1):
    /// fewer than 64 static cells (the all-motion degenerate) → the WHOLE
    /// grid counts as static so the LUT estimation never runs on an empty
    /// sample set.
    public static func staticSampleMask(
        motion: [Float], width: Int, height: Int
    ) -> (grid: [Bool], gridWidth: Int, gridHeight: Int, fellBack: Bool) {
        let step = decimationStep(width: width, height: height)
        let gridWidth = (width + step - 1) / step
        let gridHeight = (height + step - 1) / step
        var grid = [Bool](repeating: false, count: gridWidth * gridHeight)
        var staticCount = 0
        var gy = 0
        var y = 0
        while y < height {
            var gx = 0
            var x = 0
            while x < width {
                let isStatic = motion[y * width + x] < 0.01
                grid[gy * gridWidth + gx] = isStatic
                if isStatic { staticCount += 1 }
                gx += 1
                x += step
            }
            gy += 1
            y += step
        }
        if staticCount < 64 {
            for index in grid.indices { grid[index] = true }
            return (grid, gridWidth, gridHeight, true)
        }
        return (grid, gridWidth, gridHeight, false)
    }

    /// The per-channel 129-point quantile LUTs mapping REFERENCE content
    /// into `frame`'s tone domain, estimated over the static cells
    /// (merge.py:147-150,159).
    public static func substituteLUTs(
        reference: [Float], frame: [Float], motion: [Float],
        width: Int, height: Int
    ) -> [ChannelLUT] {
        let step = decimationStep(width: width, height: height)
        let (grid, gridWidth, _, _) = staticSampleMask(
            motion: motion, width: width, height: height)
        let quantiles = linspace(0, 100, 129)
        var luts: [ChannelLUT] = []
        for channel in 0..<3 {
            var referenceSamples: [Float] = []
            var frameSamples: [Float] = []
            referenceSamples.reserveCapacity(grid.count)
            frameSamples.reserveCapacity(grid.count)
            var gy = 0
            var y = 0
            while y < height {
                var gx = 0
                var x = 0
                while x < width {
                    if grid[gy * gridWidth + gx] {
                        referenceSamples.append(reference[(y * width + x) * 4 + channel])
                        frameSamples.append(frame[(y * width + x) * 4 + channel])
                    }
                    gx += 1
                    x += step
                }
                gy += 1
                y += step
            }
            let sortedReference = referenceSamples.sorted()
            let sortedFrame = frameSamples.sorted()
            let values = quantiles.map { percentileOfSorted(sortedReference, $0) }
            let target = quantiles.map { percentileOfSorted(sortedFrame, $0) }
            let (unique, positions) = uniqueWithFirstPositions(values)
            luts.append(ChannelLUT(xs: unique, ys: positions.map { target[$0] }))
        }
        return luts
    }

    /// `prepared = original·(1−α) + LUT(ref)·α` per channel (merge.py:157-165)
    /// — RGBA in, RGBA out (alpha rides through).
    public static func applySubstitution(
        original: [Float], reference: [Float], motion: [Float],
        luts: [ChannelLUT], width: Int, height: Int
    ) -> [Float] {
        precondition(luts.count == 3, "mertens substitution: need 3 channel LUTs")
        var prepared = original
        for index in 0..<(width * height) {
            let base = index * 4
            let alpha = motion[index]
            for channel in 0..<3 {
                let replacement = interp(
                    reference[base + channel], xs: luts[channel].xs, ys: luts[channel].ys)
                prepared[base + channel] =
                    original[base + channel] * (1 - alpha) + replacement * alpha
            }
        }
        return prepared
    }

    // MARK: - The blur / morphology kernels (the deghost plumbing)

    /// Separable Gaussian blur over a single-channel plane, clamp edges.
    /// Kernel radius = round(3σ) (the OpenCV `ksize = round(6σ+1)|1`
    /// equivalent), taps `exp(−x²/(2σ²))` normalized.
    static func gaussianBlurGray(
        _ plane: [Float], width: Int, height: Int, sigma: Float
    ) -> [Float] {
        precondition(plane.count == width * height, "mertens blur: plane size mismatch")
        let radius = Swift.max(1, Int((sigma * 3).rounded()))
        var kernel = [Float](repeating: 0, count: radius * 2 + 1)
        var total: Float = 0
        for index in kernel.indices {
            let offset = Float(index - radius)
            kernel[index] = Foundation.exp(-offset * offset / (2 * sigma * sigma))
            total += kernel[index]
        }
        for index in kernel.indices { kernel[index] /= total }
        var horizontal = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for tap in kernel.indices {
                    let sx = Swift.max(0, Swift.min(x + tap - radius, width - 1))
                    sum += plane[y * width + sx] * kernel[tap]
                }
                horizontal[y * width + x] = sum
            }
        }
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for tap in kernel.indices {
                    let sy = Swift.max(0, Swift.min(y + tap - radius, height - 1))
                    sum += horizontal[sy * width + x] * kernel[tap]
                }
                out[y * width + x] = sum
            }
        }
        return out
    }

    /// Square-kernel max filter (the cv2.dilate `ones((2r+1, 2r+1))` form).
    static func dilate(
        _ plane: [Float], radius: Int, width: Int, height: Int
    ) -> [Float] {
        precondition(plane.count == width * height, "mertens dilate: plane size mismatch")
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var maximum: Float = 0
                for dy in -radius...radius {
                    let sy = Swift.max(0, Swift.min(y + dy, height - 1))
                    for dx in -radius...radius {
                        let sx = Swift.max(0, Swift.min(x + dx, width - 1))
                        maximum = Swift.max(maximum, plane[sy * width + sx])
                    }
                }
                out[y * width + x] = maximum
            }
        }
        return out
    }

    // MARK: - Level/halo formulas (KD-2)

    /// `clamp(1 + floor(log2(minEdge/32)), 1, 12)` — the OQ-6 adaptive
    /// depth (the top level's minimum edge ≥ 32 px, capped at 12).
    public static func adaptiveLevels(minEdge: Int) -> Int {
        guard minEdge >= 1 else { return 1 }
        let raw = 1 + Int(Foundation.log2(Double(minEdge) / 32).rounded(.down))
        return min(12, max(1, raw))
    }

    /// `max(32, 2^levels)` — the strip halo. L=5 lands EXACTLY on
    /// FocusStackMerge.defaultHaloRows (the precedent anchor).
    public static func haloRows(levels: Int) -> Int {
        max(32, 1 << max(1, levels))
    }

    // MARK: - The strip fusion (Float32 production face)

    /// Fuse ONE strip of `sources` display-encoded RGBA planes
    /// (strip-local coordinates; w·h·4 in, w·h·3 out). The provider is
    /// called ONCE per source index, sequentially — one source's pyramids
    /// are resident at a time. Same accumulator shape as
    /// FocusStackMerge.fuseStrip; the weight map is the Mertens C·S·E.
    public static func fuseStrip(
        width: Int, height: Int, sources: Int, levels: Int,
        provider: (_ sourceIndex: Int) -> [Float]
    ) -> [Float] {
        precondition(sources >= 1, "mertens fuseStrip: need ≥ 1 source")
        let levelCount = max(1, levels)
        let pixelCount = width * height

        func weightPyramid(_ rgba: [Float]) -> [FocusStackMerge.Plane] {
            let weight = weightPlane(rgba, width: width, height: height)
            return FocusStackMerge.gaussianPyramid(
                FocusStackMerge.Plane(pixels: weight, width: width, height: height),
                levels: levelCount)
        }

        // Source 0 pins the level geometry (identical for every source —
        // the strips share the band shape).
        let first = provider(0)
        let firstWeights = weightPyramid(first)
        let sizes = firstWeights.map { (w: $0.width, h: $0.height) }
        var numerators: [[[Float]]] = (0..<sizes.count).map { level in
            (0..<3).map { _ in [Float](repeating: 0, count: sizes[level].w * sizes[level].h) }
        }
        var denominators: [[Float]] = sizes.map { [Float](repeating: 0, count: $0.w * $0.h) }

        func fold(_ rgba: [Float], _ weights: [FocusStackMerge.Plane]) {
            for channel in 0..<3 {
                var plane = [Float](repeating: 0, count: pixelCount)
                for index in 0..<pixelCount {
                    plane[index] = rgba[index * 4 + channel]
                }
                let laplacians = FocusStackMerge.laplacianPyramid(
                    FocusStackMerge.Plane(pixels: plane, width: width, height: height),
                    levels: levelCount)
                for level in sizes.indices {
                    let weight = weights[level].pixels
                    let detail = laplacians[level].pixels
                    for index in detail.indices {
                        numerators[level][channel][index] += weight[index] * detail[index]
                    }
                }
            }
            for level in sizes.indices {
                let weight = weights[level].pixels
                for index in weight.indices {
                    denominators[level][index] += weight[index]
                }
            }
        }

        fold(first, firstWeights)
        for source in 1..<sources {
            let next = provider(source)
            fold(next, weightPyramid(next))
        }

        // Blend per level (den ε-guard — the FocusStackMerge weightless
        // posture) + reconstruct downward (Rₖ = BLₖ + expand(Rₖ₊₁)); each
        // step mints the FINE-level plane (writing through the coarse plane
        // would alias level geometries).
        var reconstruction: [FocusStackMerge.Plane] = (0..<3).map { channel in
            let level = sizes.count - 1
            var plane = FocusStackMerge.Plane(
                pixels: numerators[level][channel], width: sizes[level].w,
                height: sizes[level].h)
            for index in plane.pixels.indices {
                plane.pixels[index] /= max(denominators[level][index], FocusStackMerge.weightEpsilon)
            }
            return plane
        }
        for level in stride(from: sizes.count - 2, through: 0, by: -1) {
            for channel in 0..<3 {
                let fineSize = sizes[level]
                let up = FocusStackMerge.expand(
                    reconstruction[channel], toWidth: fineSize.w, toHeight: fineSize.h)
                let numerator = numerators[level][channel]
                let denominator = denominators[level]
                var blended = [Float](repeating: 0, count: fineSize.w * fineSize.h)
                for index in blended.indices {
                    blended[index] =
                        numerator[index] / max(denominator[index], FocusStackMerge.weightEpsilon)
                        + up.pixels[index]
                }
                reconstruction[channel] = FocusStackMerge.Plane(
                    pixels: blended, width: fineSize.w, height: fineSize.h)
            }
        }
        var output = [Float](repeating: 0, count: pixelCount * 3)
        for index in 0..<pixelCount {
            output[index * 3] = reconstruction[0].pixels[index]
            output[index * 3 + 1] = reconstruction[1].pixels[index]
            output[index * 3 + 2] = reconstruction[2].pixels[index]
        }
        return output
    }

    // MARK: - The whole-frame reference fusion (the golden anchor face)

    /// Deghost (mask + per-frame reference substitution) → whole-frame
    /// pyramid fusion. Small-face synthesis only — the production driver is
    /// the M5-2-02 band-outer streaming leg consuming `fuseStrip` directly.
    /// - Parameters:
    ///   - frames: display-encoded ([0,1]) RGBA planes, reference first.
    ///   - levels: nil = `adaptiveLevels(minEdge:)`.
    public static func fuse(
        frames: [[Float]], width: Int, height: Int,
        deghost: DeghostLevel = .off, levels: Int? = nil, reference: Int = 0
    ) -> [Float] {
        precondition(frames.count >= 2, "mertens fuse: need ≥ 2 frames")
        precondition(frames.indices.contains(reference), "mertens fuse: bad reference")
        var prepared = frames
        if deghost != .off, let mask = ghostMask(
            frames: frames, reference: reference, level: deghost,
            width: width, height: height) {
            for index in frames.indices where index != reference {
                let luts = substituteLUTs(
                    reference: frames[reference], frame: frames[index], motion: mask,
                    width: width, height: height)
                prepared[index] = applySubstitution(
                    original: frames[index], reference: frames[reference], motion: mask,
                    luts: luts, width: width, height: height)
            }
        }
        let level = levels ?? adaptiveLevels(minEdge: min(width, height))
        return fuseStrip(width: width, height: height, sources: frames.count, levels: level) {
            prepared[$0]
        }
    }
}

// MARK: - Deghost tiers (KD-3 — the Lumen MIT tier table)

public extension MertensFusion {

    /// The deghost vocabulary (OQ-3: off/low/medium/high, default medium).
    enum DeghostLevel: String, Sendable, CaseIterable {
        case off
        case low
        case medium
        case high

        /// The residual threshold (merge.py:122 — smaller = more sensitive).
        public var residualThreshold: Float {
            switch self {
            case .off: return 0
            case .low: return 0.20
            case .medium: return 0.12
            case .high: return 0.065
            }
        }

        /// The base dilate radius before resolution scaling (merge.py:122).
        public var baseDilateRadius: Int {
            switch self {
            case .off: return 0
            case .low: return 2
            case .medium: return 5
            case .high: return 9
            }
        }

        /// The leg-layer resolution of the `MergeParams.mertensDeghost`
        /// string: nil (unspecified) and any out-of-vocabulary value fall
        /// back to `.medium` (OQ-3's default; the UI always passes an
        /// explicit tier, the leg owns the default).
        public static func resolved(from raw: String?) -> DeghostLevel {
            guard let raw else { return .medium }
            return DeghostLevel(rawValue: raw) ?? .medium
        }
    }
}

// MARK: - Float64 golden twin (G2 — the M5-1 OklabMath form)

/// The Float64 twin of the fusion CORE (weights + pyramids + blend +
/// collapse). The deghost/quantile path is deliberately NOT twinned: its
/// numerics are threshold/dilation-dominated (integer comparisons and mask
/// morphology), while the Float32 sensitivity lives in the pyramid
/// arithmetic — the twin exists to measure exactly that (M5-2-01-DECISIONS
/// records the scope).
///
/// Constants are the Float32 production literals elevated via
/// `Double(Float(x))` (L048 ②: the reference mirrors the production
/// constant set, so constant-rounding systematic differences never bake
/// into the parity band).
public enum MertensFusion64 {

    struct Plane {
        var pixels: [Double]
        var width: Int
        var height: Int
    }

    // MARK: weights (Float64 mirrors)

    static func grayPlane(_ rgba: [Double], width: Int, height: Int) -> [Double] {
        let c = MertensFusion.grayCoefficients
        let cr = Double(c.r), cg = Double(c.g), cb = Double(c.b)
        var gray = [Double](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            gray[index] = cr * rgba[base] + cg * rgba[base + 1] + cb * rgba[base + 2]
        }
        return gray
    }

    static func contrastPlane(_ gray: [Double], width: Int, height: Int) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let center = gray[y * width + x]
                let up = gray[max(0, y - 1) * width + x]
                let down = gray[min(height - 1, y + 1) * width + x]
                let left = gray[y * width + max(0, x - 1)]
                let right = gray[y * width + min(width - 1, x + 1)]
                out[y * width + x] = abs(up + down + left + right - 4 * center)
            }
        }
        return out
    }

    static func saturationPlane(_ rgba: [Double], width: Int, height: Int) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            let mean = (rgba[base] + rgba[base + 1] + rgba[base + 2]) / 3
            let dr = rgba[base] - mean
            let dg = rgba[base + 1] - mean
            let db = rgba[base + 2] - mean
            out[index] = ((dr * dr + dg * dg + db * db) / 3).squareRoot()
        }
        return out
    }

    static func exposureFitPlane(
        _ rgba: [Double], width: Int, height: Int, sigma: Double
    ) -> [Double] {
        let denominator = 2 * sigma * sigma
        var out = [Double](repeating: 1, count: width * height)
        for index in 0..<(width * height) {
            var product = 1.0
            for channel in 0..<3 {
                let deviation = rgba[index * 4 + channel] - 0.5
                product *= Foundation.exp(-deviation * deviation / denominator)
            }
            out[index] = product
        }
        return out
    }

    static func weightPlane(_ rgba: [Double], width: Int, height: Int) -> [Double] {
        let gray = grayPlane(rgba, width: width, height: height)
        let contrast = contrastPlane(gray, width: width, height: height)
        let saturation = saturationPlane(rgba, width: width, height: height)
        let exposure = exposureFitPlane(
            rgba, width: width, height: height, sigma: Double(MertensFusion.weightSigma))
        var out = [Double](repeating: 0, count: width * height)
        for index in out.indices {
            out[index] = Foundation.pow(contrast[index], Double(MertensFusion.weightContrastExponent))
                * Foundation.pow(saturation[index], Double(MertensFusion.weightSaturationExponent))
                * Foundation.pow(exposure[index], Double(MertensFusion.weightExposureExponent))
        }
        return out
    }

    // MARK: pyramid pair (the binomial/linear kernel, Float64)

    static func sample(_ plane: Plane, x: Int, y: Int) -> Double {
        let cx = max(0, min(x, plane.width - 1))
        let cy = max(0, min(y, plane.height - 1))
        return plane.pixels[cy * plane.width + cx]
    }

    static func reduce(_ plane: Plane) -> Plane {
        let width = plane.width, height = plane.height
        let nextWidth = width >> 1
        let nextHeight = height >> 1
        guard nextWidth >= 1, nextHeight >= 1 else { return plane }
        var horizontal = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let m2 = sample(plane, x: x - 2, y: y)
                let m1 = sample(plane, x: x - 1, y: y)
                let c = plane.pixels[y * width + x]
                let p1 = sample(plane, x: x + 1, y: y)
                let p2 = sample(plane, x: x + 2, y: y)
                horizontal[y * width + x] = (m2 + 4 * m1 + 6 * c + 4 * p1 + p2) / 16
            }
        }
        var result = [Double](repeating: 0, count: nextWidth * nextHeight)
        let h = Plane(pixels: horizontal, width: width, height: height)
        for y in 0..<nextHeight {
            let sy = y * 2
            for x in 0..<nextWidth {
                let sx = x * 2
                let m2 = sample(h, x: sx, y: sy - 2)
                let m1 = sample(h, x: sx, y: sy - 1)
                let c = horizontal[sy * width + sx]
                let p1 = sample(h, x: sx, y: sy + 1)
                let p2 = sample(h, x: sx, y: sy + 2)
                result[y * nextWidth + x] = (m2 + 4 * m1 + 6 * c + 4 * p1 + p2) / 16
            }
        }
        return Plane(pixels: result, width: nextWidth, height: nextHeight)
    }

    static func expand1D(
        _ pixels: [Double], sourceStride: Int, sourceCount: Int, base: Int,
        phase: Int, scale: Int
    ) -> Double {
        func at(_ index: Int) -> Double {
            pixels[base + max(0, min(index, sourceCount - 1)) * scale]
        }
        if phase & 1 == 0 {
            return at(phase >> 1)
        }
        let i = (phase - 1) >> 1
        return (at(i) + at(i + 1)) / 2
    }

    static func expand(_ plane: Plane, toWidth: Int, toHeight: Int) -> Plane {
        let midWidth = max(1, toWidth)
        var mid = [Double](repeating: 0, count: midWidth * plane.height)
        for y in 0..<plane.height {
            for x in 0..<midWidth {
                mid[y * midWidth + x] = expand1D(
                    plane.pixels, sourceStride: plane.width, sourceCount: plane.width,
                    base: y * plane.width, phase: x, scale: 1)
            }
        }
        let midPlane = Plane(pixels: mid, width: midWidth, height: plane.height)
        let outHeight = max(1, toHeight)
        var out = [Double](repeating: 0, count: midWidth * outHeight)
        for y in 0..<outHeight {
            for x in 0..<midWidth {
                out[y * midWidth + x] = expand1D(
                    midPlane.pixels, sourceStride: midWidth,
                    sourceCount: plane.height, base: x, phase: y, scale: midWidth)
            }
        }
        return Plane(pixels: out, width: midWidth, height: outHeight)
    }

    static func gaussianPyramid(_ plane: Plane, levels: Int) -> [Plane] {
        var result = [plane]
        for _ in 1..<max(1, levels) {
            result.append(reduce(result.last!))
        }
        return result
    }

    static func laplacianPyramid(_ plane: Plane, levels: Int) -> [Plane] {
        let gaussians = gaussianPyramid(plane, levels: levels)
        var result: [Plane] = []
        for index in 0..<(gaussians.count - 1) {
            let fine = gaussians[index]
            let coarse = gaussians[index + 1]
            let expanded = expand(coarse, toWidth: fine.width, toHeight: fine.height)
            var detail = [Double](repeating: 0, count: fine.width * fine.height)
            for index2 in detail.indices {
                detail[index2] = fine.pixels[index2] - expanded.pixels[index2]
            }
            result.append(Plane(pixels: detail, width: fine.width, height: fine.height))
        }
        result.append(gaussians.last!)
        return result
    }

    // MARK: the whole-frame twin

    /// The Float64 whole-frame fusion (no deghost — the core-numerics twin;
    /// RGBA Float32 frames in, elevated per L048; RGB Double out).
    public static func fuse(
        frames: [[Float]], width: Int, height: Int, levels: Int
    ) -> [Double] {
        precondition(frames.count >= 2, "mertens64 fuse: need ≥ 2 frames")
        let elevated = frames.map { frame in
            frame.map { Double($0) }
        }
        let levelCount = max(1, levels)
        let pixelCount = width * height
        let epsilon = Double(FocusStackMerge.weightEpsilon)

        func weightPyramid(_ rgba: [Double]) -> [Plane] {
            let weight = weightPlane(rgba, width: width, height: height)
            return gaussianPyramid(
                Plane(pixels: weight, width: width, height: height), levels: levelCount)
        }

        let first = elevated[0]
        let firstWeights = weightPyramid(first)
        let sizes = firstWeights.map { (w: $0.width, h: $0.height) }
        var numerators: [[[Double]]] = (0..<sizes.count).map { level in
            (0..<3).map { _ in [Double](repeating: 0, count: sizes[level].w * sizes[level].h) }
        }
        var denominators: [[Double]] = sizes.map { [Double](repeating: 0, count: $0.w * $0.h) }

        func fold(_ rgba: [Double], _ weights: [Plane]) {
            for channel in 0..<3 {
                var plane = [Double](repeating: 0, count: pixelCount)
                for index in 0..<pixelCount {
                    plane[index] = rgba[index * 4 + channel]
                }
                let laplacians = laplacianPyramid(
                    Plane(pixels: plane, width: width, height: height), levels: levelCount)
                for level in sizes.indices {
                    let weight = weights[level].pixels
                    let detail = laplacians[level].pixels
                    for index in detail.indices {
                        numerators[level][channel][index] += weight[index] * detail[index]
                    }
                }
            }
            for level in sizes.indices {
                let weight = weights[level].pixels
                for index in weight.indices {
                    denominators[level][index] += weight[index]
                }
            }
        }

        fold(first, firstWeights)
        for source in 1..<elevated.count {
            let next = elevated[source]
            fold(next, weightPyramid(next))
        }

        var reconstruction: [Plane] = (0..<3).map { channel in
            let level = sizes.count - 1
            var plane = Plane(
                pixels: numerators[level][channel], width: sizes[level].w,
                height: sizes[level].h)
            for index in plane.pixels.indices {
                plane.pixels[index] /= max(denominators[level][index], epsilon)
            }
            return plane
        }
        for level in stride(from: sizes.count - 2, through: 0, by: -1) {
            for channel in 0..<3 {
                let fineSize = sizes[level]
                let up = expand(reconstruction[channel], toWidth: fineSize.w, toHeight: fineSize.h)
                let numerator = numerators[level][channel]
                let denominator = denominators[level]
                var blended = [Double](repeating: 0, count: fineSize.w * fineSize.h)
                for index in blended.indices {
                    blended[index] =
                        numerator[index] / max(denominator[index], epsilon)
                        + up.pixels[index]
                }
                reconstruction[channel] = Plane(
                    pixels: blended, width: fineSize.w, height: fineSize.h)
            }
        }
        var output = [Double](repeating: 0, count: pixelCount * 3)
        for index in 0..<pixelCount {
            output[index * 3] = reconstruction[0].pixels[index]
            output[index * 3 + 1] = reconstruction[1].pixels[index]
            output[index * 3 + 2] = reconstruction[2].pixels[index]
        }
        return output
    }
}
