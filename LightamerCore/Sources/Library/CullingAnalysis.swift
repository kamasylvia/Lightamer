import Accelerate
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// CullingAnalysis (Plan LUMEN-A T3, X3) — the sharpness score + 16×16 scene
// signature behind the library culling analysis (LU2/LU1 foundation).
//
// ATTRIBUTION (NOTICE entry Q, Lumen RAW): the algorithm ideas and constant
// calibrations derive from LUMEN RAW (https://github.com/LeisureLinux/lumen,
// MIT License, Copyright (c) 2026 LUMEN RAW contributors) — `lumen/culling.py`
// `sharpness()`/`signature()` and the SHARPNESS_EDGE/kernel/quantile
// constants are transliterated here (D-LU-10: literal port, NO
// recalibration). The implementation is independent Swift/Accelerate —
// no OpenCV, no upstream code copied.
//
// Formula (the review B-1 spelling — log2 applied PER DIRECTION first,
// min over the four levels, THEN the linear map; the reversed reading
// `log2((min+4)/5.5)` is a DIFFERENT function):
//
//   gray (float 0-1) → downscale to ≤1600 long edge (exact area average,
//   INTER_AREA semantics; scale ≥ 1 is a no-op) → 5-tap Gaussian σ0.5
//   (JPEG blocks and noise are not detail) → per direction d ∈
//   {0°,45°,90°,135°}: 32-px tile means of (first-derivative response)²
//   and (second-derivative response)² under the fixed 3×3 correlation
//   kernels → structure tiles = first ≥ P75(first) AND first > 2e-5 →
//   level_d = log2(P90 over (second/first) on the structure tiles) →
//   score = clamp((min_d level_d + 4) / 5.5 × 100, 0, 100).
//
// Branch transcription (review B-1): no structure tiles → 0.0;
// min(width, height) < 64 after the resize → nil (un-scoreable).
//
// Calibration (Lumen's, on a 1600-px view): a 1.2-px Gaussian blur scores
// ≈ 55, 2 px ≈ 30. The score is contrast-independent (a misty landscape is
// not called soft) and min-of-4 makes one-direction motion blur detectable.
//
// `Signature16` is the 16×16 greyscale (256-byte) scene signature that
// feeds burst grouping (LU1): same scene stays close under
// `BurstAnnotator.signatureDifference`, another scene does not.
// ─────────────────────────────────────────────────────────────────────────────

public enum SharpnessAnalyzer {

    /// Long edge of the greyscale copy sharpness is measured on
    /// (Lumen `SHARPNESS_EDGE`).
    public static let sharpnessEdge = 1600
    /// The tile edge (Lumen `_tiles` default `size=32`).
    static let tileEdge = 32
    /// Structure quantile on the first-derivative tile energies (P75).
    static let structureQuantile = 0.75
    /// Structure floor on the first-derivative energy (Lumen `2e-5`).
    static let structureFloor: Float = 2e-5
    /// The ratio quantile on the structure tiles (P90).
    static let ratioQuantile = 0.90
    /// The linear map constants (Lumen `(min+4)/5.5*100`).
    static let scaleOffset: Float = 4
    static let scaleDivisor: Float = 5.5

    /// Sharpness 0-100 of a row-major float 0-1 greyscale plane, or nil
    /// when the (resized) plane is under 64 px on the short edge.
    /// Lumen `sharpness()` transliterated — the parameters above are
    /// frozen calibration, never to be re-tuned (D-LU-10).
    public static func analyze(
        gray: [Float], width: Int, height: Int
    ) -> Double? {
        precondition(gray.count == width * height, "plane/shape mismatch")
        var plane = gray
        var w = width
        var h = height

        // _resize: downscale only (scale >= 1 is a no-op); target =
        // (round(w*scale), round(h*scale)), INTER_AREA semantics.
        let scale = Double(sharpnessEdge) / Double(max(w, h))
        if scale < 1 {
            let newW = max(1, Int((Double(w) * scale).rounded()))
            let newH = max(1, Int((Double(h) * scale).rounded()))
            plane = AreaResize.resize(plane, width: w, height: h, toWidth: newW, toHeight: newH)
            w = newW
            h = newH
        }
        if min(w, h) < 64 { return nil }

        gaussianBlurSigmaHalf(&plane, width: w, height: h)

        // The four fixed 3×3 correlation kernels (Lumen `_FIRST`/`_SECOND`
        // — filter2D correlates, it does not flip). Stored per direction
        // as (dy, dx, weight) triples.
        let sqrt2: Float = 1.4142135623730951
        let directions: [([(Int, Int, Float)], [(Int, Int, Float)])] = [
            // 0°: horizontal.
            ([(0, -1, -0.5), (0, 1, 0.5)], [(0, -1, 1), (0, 0, -2), (0, 1, 1)]),
            // 45°: up-right / down-left diagonal.
            ([( -1, 1, 0.5 / sqrt2), (1, -1, -0.5 / sqrt2)],
             [(-1, 1, 0.5), (0, 0, -2), (1, -1, 0.5)].map { ($0.0, $0.1, $0.2 / 2) }),
            // 90°: vertical.
            ([(-1, 0, -0.5), (1, 0, 0.5)], [(-1, 0, 1), (0, 0, -2), (1, 0, 1)]),
            // 135°: down-right / up-left diagonal.
            ([(-1, -1, -0.5 / sqrt2), (1, 1, 0.5 / sqrt2)],
             [(-1, -1, 0.5), (0, 0, -2), (1, 1, 0.5)].map { ($0.0, $0.1, $0.2 / 2) }),
        ]

        let tilesW = w / tileEdge
        let tilesH = h / tileEdge
        var levels: [Float] = []

        for (firstKernel, secondKernel) in directions {
            var firstTiles = [Float](repeating: 0, count: tilesW * tilesH)
            var secondTiles = [Float](repeating: 0, count: tilesW * tilesH)
            let block = tileEdge * tileEdge
            for ty in 0..<tilesH {
                let yStart = ty * tileEdge
                for tx in 0..<tilesW {
                    let xStart = tx * tileEdge
                    var firstSum: Float = 0
                    var secondSum: Float = 0
                    for y in yStart..<(yStart + tileEdge) {
                        // Reflect-101 clamps (cv2 BORDER_REFLECT_101).
                        let ym = reflect101(y - 1, h)
                        let yp = reflect101(y + 1, h)
                        let rowM = ym * w
                        let row0 = y * w
                        let rowP = yp * w
                        for x in xStart..<(xStart + tileEdge) {
                            let xm = reflect101(x - 1, w)
                            let xp = reflect101(x + 1, w)
                            var first: Float = 0
                            var second: Float = 0
                            for sample in firstKernel {
                                let dy = sample.0, dx = sample.1
                                let row = dy == -1 ? rowM : (dy == 1 ? rowP : row0)
                                let col = dx == -1 ? xm : (dx == 1 ? xp : x)
                                first += sample.2 * plane[row + col]
                            }
                            for sample in secondKernel {
                                let dy = sample.0, dx = sample.1
                                let row = dy == -1 ? rowM : (dy == 1 ? rowP : row0)
                                let col = dx == -1 ? xm : (dx == 1 ? xp : x)
                                second += sample.2 * plane[row + col]
                            }
                            firstSum += first * first
                            secondSum += second * second
                        }
                    }
                    firstTiles[ty * tilesW + tx] = firstSum / Float(block)
                    secondTiles[ty * tilesW + tx] = secondSum / Float(block)
                }
            }

            // Structure tiles: first >= P75(first) AND first > 2e-5.
            let p75 = percentile(firstTiles, quantile: structureQuantile)
            var ratios: [Float] = []
            ratios.reserveCapacity(firstTiles.count / 4)
            var anyStrong = false
            for index in 0..<firstTiles.count {
                let value = firstTiles[index]
                if value >= p75 && value > structureFloor {
                    anyStrong = true
                    ratios.append(secondTiles[index] / value)
                }
            }
            // Branch (review B-1): no structure → 0.0 (Lumen :83).
            guard anyStrong else { return 0 }

            // Per-direction log2 FIRST (review B-1 ordering).
            let p90 = percentile(ratios, quantile: ratioQuantile)
            levels.append(log2(p90))
        }

        // min over the four levels, THEN the linear map, clamped.
        let minLevel = levels.min() ?? 0
        let score = (minLevel + scaleOffset) / scaleDivisor * 100
        return Double(min(max(score, 0), 100))
    }

    /// Reflect-101 index clamp (cv2 BORDER_DEFAULT) — index space only.
    private static func reflect101(_ index: Int, _ extent: Int) -> Int {
        var i = index
        if i < 0 { i = -i }
        if i >= extent { i = 2 * (extent - 1) - i }
        return max(0, min(i, extent - 1))
    }

    /// Linear-interpolation percentile (numpy.percentile's default
    /// 'linear' method): rank = q*(n-1), interpolate between neighbors.
    static func percentile(_ values: [Float], quantile: Double) -> Float {
        precondition(!values.isEmpty)
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let rank = quantile * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        guard lower != upper else { return sorted[lower] }
        let fraction = Float(rank - Double(lower))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// Separable 5-tap Gaussian σ0.5, reflect-101 borders (cv2.GaussianBlur
    /// (0,0) σ0.5 → ksize 5 computed from sigma; weights = the normalized
    /// exp form — identical values to OpenCV's kernel).
    static func gaussianBlurSigmaHalf(_ plane: inout [Float], width: Int, height: Int) {
        let sigma: Float = 0.5
        var kernel = (0...2).map { radius -> Float in
            exp(-Float(radius * radius) / (2 * sigma * sigma))
        }
        // The array is CENTER-FIRST (kernel[0] = exp(0)): the 5-tap sum is
        // the center once plus both rings twice.
        let sum = kernel[0] + 2 * kernel[1] + 2 * kernel[2]
        for index in 0..<3 { kernel[index] /= sum }
        let k0 = kernel[0], k1 = kernel[1], k2 = kernel[2]

        var horizontal = [Float](repeating: 0, count: plane.count)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let xm = plane[row + reflect101(x - 1, width)]
                let xp = plane[row + reflect101(x + 1, width)]
                // kernel = [k0, k1, k2, k1, k0] DESCENDING — k0 IS the
                // center weight, k1 the two neighbors.
                horizontal[row + x] = k0 * plane[row + x] + k1 * (xm + xp)
            }
        }
        for y in 0..<height {
            let ym = reflect101(y - 1, height) * width
            let y0 = y * width
            let yp = reflect101(y + 1, height) * width
            for x in 0..<width {
                plane[y0 + x] =
                    k0 * horizontal[y0 + x] + k1 * (horizontal[ym + x] + horizontal[yp + x])
            }
        }
    }
}

/// The 16×16 greyscale scene signature (Lumen `signature()` transliterated):
/// INTER_AREA-equivalent downscale to 16×16, scale to 0-255, truncate to
/// UInt8 (numpy's `.astype(uint8)` truncates toward zero), 256 bytes
/// row-major.
public enum Signature16 {

    /// The signature side (16×16, 256 bytes).
    public static let side = 16

    public static func bytes(gray: [Float], width: Int, height: Int) -> [UInt8] {
        precondition(gray.count == width * height, "plane/shape mismatch")
        let small = AreaResize.resize(
            gray, width: width, height: height, toWidth: side, toHeight: side)
        var out = [UInt8](repeating: 0, count: side * side)
        for index in 0..<out.count {
            let scaled = min(max(small[index] * 255, 0), 255)
            out[index] = UInt8(clamping: Int(scaled))
        }
        return out
    }
}

/// Exact area-average resampling (the INTER_AREA downscale semantics:
/// each destination pixel averages its source rectangle, fractional edge
/// weights included). Separable — the 2D area average factors into two 1D
/// box passes with fractional edge weights.
enum AreaResize {

    /// Per-destination-axis fragments: (source index, weight) pairs whose
    /// weights are normalized to sum 1 (the destination pixel = the WEIGHTED
    /// AVERAGE of its source interval — INTER_AREA semantics).
    static func fragments(source: Int, destination: Int) -> [[(Int, Float)]] {
        var result: [[(Int, Float)]] = []
        result.reserveCapacity(destination)
        let ratio = Double(source) / Double(destination)
        for target in 0..<destination {
            let start = Double(target) * ratio
            let end = Double(target + 1) * ratio
            var row: [(Int, Float)] = []
            var cursor = start
            while cursor < end {
                let index = Int(cursor.rounded(.down))
                let boundary = min(Double(index + 1), end)
                let weight = Float(boundary - cursor) / Float(ratio)
                if weight > 0 { row.append((index, weight)) }
                cursor = boundary
            }
            result.append(row)
        }
        return result
    }

    static func resize(
        _ plane: [Float], width: Int, height: Int,
        toWidth newW: Int, toHeight newH: Int
    ) -> [Float] {
        let xFrags = fragments(source: width, destination: newW)
        let yFrags = fragments(source: height, destination: newH)
        // Horizontal pass: h×newW.
        var horizontal = [Float](repeating: 0, count: height * newW)
        for y in 0..<height {
            let srcRow = y * width
            let dstRow = y * newW
            for (targetX, frag) in xFrags.enumerated() {
                var sum: Float = 0
                for (index, weight) in frag {
                    sum += plane[srcRow + index] * weight
                }
                horizontal[dstRow + targetX] = sum
            }
        }
        // Vertical pass: newH×newW.
        var output = [Float](repeating: 0, count: newH * newW)
        for (targetY, frag) in yFrags.enumerated() {
            let dstRow = targetY * newW
            for (index, weight) in frag {
                let srcRow = index * newW
                for x in 0..<newW {
                    output[dstRow + x] += horizontal[srcRow + x] * weight
                }
            }
        }
        return output
    }
}
