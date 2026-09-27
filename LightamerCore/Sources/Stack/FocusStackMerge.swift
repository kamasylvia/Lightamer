import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FocusStackMerge (Plan 08-3 T2; RESEARCH §5) — the enfuse-style
// quality-weighted Laplacian-pyramid fusion MATH + the NCC scale-drift
// self-check, as PURE functions on row strips. The streaming driver lives
// in the StackMergeService focus leg: staged sources are consumed BAND BY
// BAND, so no N×full-frame plane and no N×full quality map is ever
// resident — the R3 hard constraint (research §5.4/§6).
//
// Per band (with halo rows each side, D-08-3-T2-1):
//   1. per source: the quality strip is softened (5×5 box — P5's
//      soft-weight PASS shape), a Gaussian pyramid of the quality and
//      Laplacian pyramids of the RGB channels are built IN THE STRIP,
//   2. the source's levels are folded into N-INDEPENDENT accumulators
//      (numerator Σᵢ wₖ,ᵢ·Lₖ,ᵢ + denominator Σᵢ wₖ,ᵢ per level) and its
//      pyramids are FREED — sources never co-reside,
//   3. blend per level: BLₖ = numₖ / max(denₖ, ε),
//   4. reconstruct: Rₖ = BLₖ + expand(Rₖ₊₁); the band's rows of R₀ are
//      the fused output — EXACT for band rows, because the halo (32 rows)
//      covers the whole pyramid receptive field (≈30 rows) and the
//      strip-edge clamps only contaminate rows outside the band.
//
// Pyramid kernel pair (D-08-3-T2-2): REDUCE = separable binomial
// [1,4,6,4,1]/16 + decimate-by-2 (odd edge dropped); EXPAND = the LINEAR
// 2× partner (even output = the source sample, odd = the neighbour mean).
// The pair is DC-consistent (a constant field is a fixed point of both —
// the zero-stuff/4·h adjoint has DC gain 4 and was REJECTED for exactly
// that: it made the reconstruction explode on high-frequency fixtures),
// and the consistency is what keeps the Laplacian telescoping exact.
//
// NCC (research §5.3): after MTB alignment, the decimated luma overlap is
// correlated; NCC < 0.9 ⇒ a magnification-drift WARNING — the merge
// PROCEEDS (soft weights tolerate small depth-bound misregistration
// natively; homography/optical-flow refinement is the v2 seam).
// ─────────────────────────────────────────────────────────────────────────────

public enum FocusStackMerge {

    /// Default pyramid depth (research §5.2 — 5 levels ≈ the 1024 px
    /// boundary-transition empirical value; the additive knob).
    public static let defaultPyramidLevels = 5

    /// The band halo (rows each side) — covers the 5-level pyramid's
    /// receptive field (≈ 2·(2⁰+2¹+2²+2³) = 30 rows) with margin
    /// (D-08-3-T2-1).
    public static let defaultHaloRows = 32

    /// The level-blend denominator guard (all sources weightless → black).
    public static let weightEpsilon: Float = 1e-8

    // MARK: - Memory accounting (the R3 regression lock's formula)

    /// The focus fusion's per-band resident working set, INDEPENDENT of the
    /// image height: N sources × strip rows × width × (4ch float pixels +
    /// 1ch float quality) + the accumulator planes (one N-independent set:
    /// 5 levels × 4ch × the geometric series ≈ 5.33·w·b·4B) + the strip
    /// pyramid transient (one source at a time ≈ 5.33·w·b·4B). The R3 red
    /// line: O(band), never O(height) — the test pins this formula and its
    /// band/floor ratio.
    public static func bandWorkingSetBytes(
        width: Int, bandHeight: Int, halo: Int = FocusStackMerge.defaultHaloRows,
        sources: Int, levels: Int = FocusStackMerge.defaultPyramidLevels
    ) -> Int {
        let stripRows = bandHeight + 2 * halo
        let stripBytes = sources * stripRows * width * 5 * MemoryLayout<Float>.size
        // Geometric series of the level planes (ratio ¼ per level, levels
        // capped by the strip's 1×1 clamp): ≈ Σ 4ch·(1/4)ᵏ ≈ 5.33 planes.
        var planeCount = 0.0
        var fraction = 1.0
        for _ in 0..<max(1, levels) {
            planeCount += 4 * fraction // 3ch numerator + 1ch denominator
            fraction /= 4
        }
        planeCount += 4 * planeCount / Double(max(1, levels)) // + one source transient
        let accumulatorBytes = Int(planeCount * Double(width * stripRows))
            * MemoryLayout<Float>.size
        return stripBytes + accumulatorBytes
    }

    // MARK: - The 5×5 box quality soften (P5's soft-weight shape)

    /// Separable 5-wide box mean (5 horizontal × 5 vertical), clamp edges.
    /// Applied per quality strip BEFORE the pyramid — the strip's halo ≥ 2
    /// rows makes band rows' softened values IDENTICAL to whole-map
    /// softening (no seam).
    public static func softenQuality(
        _ quality: [Float], width: Int, height: Int
    ) -> [Float] {
        precondition(quality.count == width * height, "quality strip size mismatch")
        let radius = 2
        var horizontal = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                var count: Float = 0
                for dx in -radius...radius {
                    let sx = x + dx
                    guard sx >= 0, sx < width else { continue }
                    sum += quality[y * width + sx]
                    count += 1
                }
                horizontal[y * width + x] = sum / count
            }
        }
        var result = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                var count: Float = 0
                for dy in -radius...radius {
                    let sy = y + dy
                    guard sy >= 0, sy < height else { continue }
                    sum += horizontal[sy * width + x]
                    count += 1
                }
                result[y * width + x] = sum / count
            }
        }
        return result
    }

    // MARK: - The Burt-Adelson pair (D-08-3-T2-2)

    struct Plane {
        var pixels: [Float]
        var width: Int
        var height: Int
    }

    /// REDUCE: separable binomial blur + decimate-by-2 (odd edge dropped —
    /// the MTB pyramid's convention).
    static func reduce(_ plane: Plane) -> Plane {
        let width = plane.width, height = plane.height
        let nextWidth = width >> 1
        let nextHeight = height >> 1
        guard nextWidth >= 1, nextHeight >= 1 else { return plane }
        // Horizontal 5-tap into a full-size intermediate, then the vertical
        // 5-tap sampled at even rows (fused with the decimation).
        var horizontal = [Float](repeating: 0, count: width * height)
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
        var result = [Float](repeating: 0, count: nextWidth * nextHeight)
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

    /// EXPAND: the reduce adjoint — zero-stuff ×2 then convolve 4·h, in the
    /// closed per-phase form (see the header table), edges clamped. The
    /// closed form extends to ANY target size (taps clamp at the source
    /// edge), which keeps odd-size chains (reduce drops the odd column)
    /// well-defined.
    static func expand(_ plane: Plane, toWidth: Int, toHeight: Int) -> Plane {
        // Horizontal phase: width w → the requested width.
        let midWidth = max(1, toWidth)
        var mid = [Float](repeating: 0, count: midWidth * plane.height)
        for y in 0..<plane.height {
            for x in 0..<midWidth {
                mid[y * midWidth + x] = expand1D(
                    plane.pixels, sourceStride: plane.width, sourceCount: plane.width,
                    base: y * plane.width, phase: x, scale: 1)
            }
        }
        // Vertical phase: height h → the requested height.
        let midPlane = Plane(pixels: mid, width: midWidth, height: plane.height)
        let outHeight = max(1, toHeight)
        var out = [Float](repeating: 0, count: midWidth * outHeight)
        for y in 0..<outHeight {
            for x in 0..<midWidth {
                out[y * midWidth + x] = expand1D(
                    midPlane.pixels, sourceStride: midWidth,
                    sourceCount: plane.height, base: x, phase: y, scale: midWidth)
            }
        }
        return Plane(pixels: out, width: midWidth, height: outHeight)
    }

    /// One axis of the linear EXPAND: even output = the source sample,
    /// odd output = the two-neighbour average (DC gain exactly 1 — the
    /// constant field is a fixed point of the whole pyramid pair).
    private static func expand1D(
        _ pixels: [Float], sourceStride: Int, sourceCount: Int, base: Int,
        phase: Int, scale: Int
    ) -> Float {
        func at(_ index: Int) -> Float {
            pixels[base + max(0, min(index, sourceCount - 1)) * scale]
        }
        if phase & 1 == 0 {
            return at(phase >> 1)
        }
        let i = (phase - 1) >> 1
        return (at(i) + at(i + 1)) / 2
    }

    private static func sample(_ plane: Plane, x: Int, y: Int) -> Float {
        let cx = max(0, min(x, plane.width - 1))
        let cy = max(0, min(y, plane.height - 1))
        return plane.pixels[cy * plane.width + cx]
    }

    /// The Gaussian pyramid (level 0 = the input plane).
    static func gaussianPyramid(_ plane: Plane, levels: Int) -> [Plane] {
        var result = [plane]
        for _ in 1..<max(1, levels) {
            result.append(reduce(result.last!))
        }
        return result
    }

    /// The Laplacian pyramid: Lₖ = Gₖ − expand(Gₖ₊₁); the last level IS
    /// G_levels−1 (the low-residual remainder).
    static func laplacianPyramid(_ plane: Plane, levels: Int) -> [Plane] {
        var gaussians = gaussianPyramid(plane, levels: levels)
        var result: [Plane] = []
        for index in 0..<(gaussians.count - 1) {
            let fine = gaussians[index]
            let coarse = gaussians[index + 1]
            let expanded = expand(coarse, toWidth: fine.width, toHeight: fine.height)
            var detail = [Float](repeating: 0, count: fine.width * fine.height)
            for index2 in detail.indices {
                detail[index2] = fine.pixels[index2] - expanded.pixels[index2]
            }
            result.append(Plane(pixels: detail, width: fine.width, height: fine.height))
        }
        result.append(gaussians.last!)
        return result
    }

    // MARK: - The strip fusion (the band driver's math core)

    /// Fuse ONE strip (all sources' rows in strip-local coordinates).
    ///
    /// - Parameters:
    ///   - sources: the source count; the provider is called ONCE per
    ///     source index, sequentially — only ONE source's pyramids are
    ///     resident at a time (the accumulator set is N-independent).
    ///   - provider: `(sourceIndex) -> (rgb, quality)` — the RGB strip is
    ///     interleaved RGBA float (w·h·4; alpha ignored), the quality strip
    ///     is w·h single channel. NaN (out-of-alignment-overlap) pixels
    ///     must arrive with quality 0.
    /// - Returns: the fused strip as interleaved RGB float (w·h·3).
    public static func fuseStrip(
        width: Int, height: Int, sources: Int,
        levels: Int = FocusStackMerge.defaultPyramidLevels,
        provider: (_ sourceIndex: Int) -> (rgb: [Float], quality: [Float])
    ) -> [Float] {
        let pixelCount = width * height
        let levelCount = max(1, levels)

        func qualityChain(_ quality: [Float]) -> [Plane] {
            var chain = [Plane(
                pixels: softenQuality(quality, width: width, height: height),
                width: width, height: height)]
            for _ in 1..<levelCount { chain.append(reduce(chain.last!)) }
            return chain
        }
        func fold(
            _ rgb: [Float], _ quality: [Plane],
            into numerators: inout [[[Float]]], _ denominators: inout [[Float]],
            sizes: [(w: Int, h: Int)]
        ) {
            for channel in 0..<3 {
                var plane = [Float](repeating: 0, count: pixelCount)
                for index in 0..<pixelCount {
                    plane[index] = rgb[index * 4 + channel]
                }
                let laplacians = laplacianPyramid(
                    Plane(pixels: plane, width: width, height: height),
                    levels: levelCount)
                for level in sizes.indices {
                    let weight = quality[level].pixels
                    let detail = laplacians[level].pixels
                    for index in detail.indices {
                        numerators[level][channel][index] +=
                            weight[index] * detail[index]
                    }
                }
            }
            for level in sizes.indices {
                let weight = quality[level].pixels
                for index in weight.indices {
                    denominators[level][index] += weight[index]
                }
            }
        }

        // Source 0 pins the level geometry (identical for every source —
        // the strips share the band shape).
        let first = provider(0)
        let firstChain = qualityChain(first.quality)
        let sizes = firstChain.map { (w: $0.width, h: $0.height) }
        var numerators: [[[Float]]] = (0..<sizes.count).map { level in
            (0..<3).map { _ in [Float](repeating: 0, count: sizes[level].w * sizes[level].h) }
        }
        var denominators: [[Float]] = sizes.map {
            (0..<$0.w * $0.h).map { _ in 0 }
        }
        fold(first.rgb, firstChain, into: &numerators, &denominators, sizes: sizes)

        for source in 1..<sources {
            let next = provider(source)
            fold(
                next.rgb, qualityChain(next.quality),
                into: &numerators, &denominators, sizes: sizes)
        }

        // Blend per level + reconstruct (Rₖ = BLₖ + expand(Rₖ₊₁)); each
        // step mints the FINE-level plane (the coarse plane is consumed by
        // the expand — writing through it would alias level geometries).
        var reconstruction: [Plane] = (0..<3).map { channel in
            let level = sizes.count - 1
            var plane = Plane(
                pixels: numerators[level][channel], width: sizes[level].w,
                height: sizes[level].h)
            for index in plane.pixels.indices {
                plane.pixels[index] /=
                    max(denominators[level][index], weightEpsilon)
            }
            return plane
        }
        for level in stride(from: sizes.count - 2, through: 0, by: -1) {
            for channel in 0..<3 {
                let fineSize = sizes[level]
                let up = expand(
                    reconstruction[channel], toWidth: fineSize.w, toHeight: fineSize.h)
                let numerator = numerators[level][channel]
                let denominator = denominators[level]
                var blended = [Float](repeating: 0, count: fineSize.w * fineSize.h)
                for index in blended.indices {
                    blended[index] =
                        numerator[index] / max(denominator[index], weightEpsilon)
                        + up.pixels[index]
                }
                reconstruction[channel] = Plane(
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

    // MARK: - The NCC scale-drift self-check (research §5.3)

    /// The NCC threshold (a magnification-drift warning below this).
    public static let nccWarnThreshold = 0.9

    /// Normalized cross-correlation of the two DECIMATED luma surfaces over
    /// the intersection window under the MTB shift convention
    /// (`cmp(x, y) == ref(x − dx, y − dy)`) — 1.0 = perfect correlation,
    /// ≈0 = decorrelated (a scale drift misregisters the overlap).
    public static func normalizedCrossCorrelation(
        reference: AlignmentFrame.RatioLuma, candidate: AlignmentFrame.RatioLuma,
        dx: Int, dy: Int
    ) -> Double {
        let width = min(reference.width, candidate.width)
        let height = min(reference.height, candidate.height)
        // The intersection in CANDIDATE coordinates (the same contraction
        // the MTB XOR window uses).
        let x0 = max(0, dx), x1 = min(width, reference.width + dx)
        let y0 = max(0, dy), y1 = min(height, reference.height + dy)
        guard x1 - x0 >= 8, y1 - y0 >= 8 else { return 0 }
        var sumA = 0.0, sumB = 0.0, sumAA = 0.0, sumBB = 0.0, sumAB = 0.0
        var count = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let a = Double(reference.pixels[y * reference.width + x])
                let b = Double(candidate.pixels[(y - dy) * candidate.width + (x - dx)])
                sumA += a; sumB += b
                sumAA += a * a; sumBB += b * b; sumAB += a * b
                count += 1
            }
        }
        guard count >= 64 else { return 0 }
        let meanA = sumA / count, meanB = sumB / count
        let varianceA = sumAA - count * meanA * meanA
        let varianceB = sumBB - count * meanB * meanB
        guard varianceA > 0, varianceB > 0 else { return 0 }
        return (sumAB - count * meanA * meanB) / (varianceA.squareRoot() * varianceB.squareRoot())
    }
}
