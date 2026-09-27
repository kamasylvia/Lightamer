import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// HDR merge math (Plan 08-1 T3; RESEARCH §1) — the CPU PURE-FUNCTION golden
// source for the Robertson-family linear weighted merge.
//
// Weight terminal form (§1.1 — the P2 insensitivity verdict):
//   w(p) = 0                                   if p ≥ clipGate (0.995)
//                                              or p ≤ floorGate (0.001)
//   w(p) = exp(−(p − 0.5)² / (2σ²))            otherwise; σ default 0.2
//   L̂    = Σᵢ wᵢ · (pᵢ / tᵢ) / Σᵢ wᵢ
// The clip gates double as the HOLE detector: Σw == 0 ⇒ the pixel is
// outside the bracket's coverage ⇒ output 0.0 (black) + a weight-map zero.
// `weightNoiseFloor` is the ADDITIVE knob kept OFF by default (research
// §17.4 — the P2 shape-insensitivity verdict).
//
// Ghost rejection (§4.1): the residual is computed in the LINEAR LUMA's
// normalized domain — NOT the weight domain (hat-edge gradients bend a
// weight-domain threshold):
//   rᵢ   = |pᵢ/tᵢ − L̂| / max(L̂, ε)
//   σ̂(L̂) = noiseFloor + shotCoefficient / √L̂   (5% floor + the shot-noise
//           model — the coefficients are the D-08-1 execution decision)
//   rᵢ > k·σ̂ (k = 3) ⇒ that source's weight is ZEROED at that pixel and
//   the pixel enters the ghost bitmap.
//
// Weights are PER CHANNEL (the Robertson convention — a clipped red channel
// zeroes only red), and the weight-map records the MINIMUM of the three
// channel sums (a hole in any channel makes the pixel a HOLE — the
// conservative coverage semantics, D-08-1).
// ─────────────────────────────────────────────────────────────────────────────

public enum HDRMergeMath {

    // MARK: - Algorithm constants (execution decisions — D-08-1)

    /// The ghost rejection multiple (research P2: k=3 with the 5% floor
    /// effectively rejects a 0.6-magnitude non-clipping ghost).
    public static let ghostK: Float = 3.0

    /// The relative noise floor σ̂'s constant term (research §4.1: 5%).
    public static let ghostNoiseFloor: Float = 0.05

    /// The shot-noise model coefficient: σ̂(L̂) = floor + c/√L̂. A 2%
    /// relative term at L̂=1 tapering into the shadows is the physically
    /// sensible order for a modern sensor at base ISO (D-08-1).
    public static let ghostShotCoefficient: Float = 0.02

    /// The residual epsilon (the L̂→0 guard).
    public static let residualEpsilon: Float = 1e-6

    // MARK: - The weight terminal form (§1.1)

    /// `w(p)` — the dual-gated Gaussian. Monotone in the gates; w(0.5) = 1
    /// for every σ (the σ-parameterization identity).
    @inline(__always)
    public static func weight(
        _ p: Float, sigma: Float, clipGate: Float, floorGate: Float,
        weightNoiseFloor: Bool = false
    ) -> Float {
        if p >= clipGate || p <= floorGate {
            return 0
        }
        let gaussian = exp(-(p - 0.5) * (p - 0.5) / (2 * sigma * sigma))
        if weightNoiseFloor {
            // The additive noise-cap knob (OFF by default): a 1/p²-flavored
            // term normalized to 1 at p = 0.5 — kept for the
            // Reversibility clause, never load-bearing in v1.
            let cap = 0.25 / (p * p)
            return gaussian + min(cap, 1)
        }
        return gaussian
    }

    /// σ̂(L̂) — the relative noise scale for the ghost residual.
    @inline(__always)
    public static func sigmaHat(_ lHat: Float) -> Float {
        ghostNoiseFloor + ghostShotCoefficient / (lHat + residualEpsilon).squareRoot()
    }

    /// rᵢ — the normalized residual in the linear domain.
    @inline(__always)
    public static func residual(
        _ p: Float, exposure: Float, lHat: Float
    ) -> Float {
        let normalized = p / exposure
        return abs(normalized - lHat) / max(lHat, residualEpsilon)
    }

    // MARK: - Band aggregation

    /// One source's band payload: RGBA float32 interleaved rows + the frame
    /// exposure ratio `t` relative to the reference (reference = 1; a
    /// +2EV frame has t = 4 — its pixel values are 4× a reference's of the
    /// same scene point).
    public struct SourceBand: Sendable {
        public let pixels: [Float]
        public let width: Int
        public let height: Int
        public let exposure: Float

        public init(pixels: [Float], width: Int, height: Int, exposure: Float) {
            self.pixels = pixels
            self.width = width
            self.height = height
            self.exposure = exposure
        }
    }

    /// The per-band aggregation kernel. Phase 1 (the base merge): accumulate
    /// Σw and Σw·p/t per channel. Phase 2 (de-ghost): the same, but weights
    /// whose residual (against `lHatBand`, the phase-1 consensus) exceeds
    /// k·σ̂ are zeroed and the pixel is marked in `ghostUnion`.
    ///
    /// This is the GOLDEN source — the streaming driver (BandStreamer) is a
    /// mechanical decomposition of exactly this math.
    ///
    /// - Parameters:
    ///   - sumW/sumWP: the accumulator band slices (RGB, 3 floats/px),
    ///     mutated IN PLACE.
    ///   - lHatBand: the phase-1 consensus for this band (nil = phase 1).
    ///   - ghostUnion: a 0/1 byte per pixel (mutated in place when non-nil).
    /// - Returns: the in-band HOLE count (pixels whose min-channel Σw
    ///   stayed 0 after aggregation).
    @discardableResult
    public static func accumulateBand(
        bands: [SourceBand],
        params: StackMergeService.MergeParams,
        lHatBand: [Float]?,
        ghostUnion: inout [UInt8]?,
        sumW: inout [Float],
        sumWP: inout [Float]
    ) -> Int {
        let pixelCount = bands[0].width * bands[0].height
        var holes = 0
        for index in 0..<pixelCount {
            var weightSum: (Float, Float, Float) = (0, 0, 0)
            var weighted: (Float, Float, Float) = (0, 0, 0)
            for band in bands {
                let base = index * 4
                let t = band.exposure
                let r = band.pixels[base]
                let g = band.pixels[base + 1]
                let b = band.pixels[base + 2]
                // Per-channel weights (clipping is per channel).
                let wr = weight(r, sigma: params.sigma,
                    clipGate: params.clipGate, floorGate: params.floorGate,
                    weightNoiseFloor: params.weightNoiseFloor)
                let wg = weight(g, sigma: params.sigma,
                    clipGate: params.clipGate, floorGate: params.floorGate,
                    weightNoiseFloor: params.weightNoiseFloor)
                let wb = weight(b, sigma: params.sigma,
                    clipGate: params.clipGate, floorGate: params.floorGate,
                    weightNoiseFloor: params.weightNoiseFloor)
                if wr == 0 && wg == 0 && wb == 0 { continue }

                // The ghost rejection (phase 2 only): ANY channel's residual
                // beyond k·σ̂ zeroes the WHOLE frame's weight at this pixel
                // (a moved object is moved in all channels — the P2 shape).
                if let lHatBand, ghostUnion != nil {
                    let lHatR = lHatBand[index * 3]
                    let lHatG = lHatBand[index * 3 + 1]
                    let lHatB = lHatBand[index * 3 + 2]
                    let sigmaR = sigmaHat(lHatR)
                    let sigmaG = sigmaHat(lHatG)
                    let sigmaB = sigmaHat(lHatB)
                    let reject = residual(r, exposure: t, lHat: lHatR) > ghostK * sigmaR
                        || residual(g, exposure: t, lHat: lHatG) > ghostK * sigmaG
                        || residual(b, exposure: t, lHat: lHatB) > ghostK * sigmaB
                    if reject {
                        // In-place mutation through the optional (no COW
                        // copy — the caller owns the only reference).
                        ghostUnion?[index] = 1
                        continue
                    }
                }

                let tr = r / t
                let tg = g / t
                let tb = b / t
                weightSum.0 += wr
                weightSum.1 += wg
                weightSum.2 += wb
                weighted.0 += wr * tr
                weighted.1 += wg * tg
                weighted.2 += wb * tb
            }
            let minSum = min(weightSum.0, weightSum.1, weightSum.2)
            if minSum == 0 {
                holes += 1
                // HOLE semantics: output 0.0 (the accumulator is already
                // zero-initialized — nothing to write).
            } else {
                sumW[index * 3] += weightSum.0
                sumW[index * 3 + 1] += weightSum.1
                sumW[index * 3 + 2] += weightSum.2
                sumWP[index * 3] += weighted.0
                sumWP[index * 3 + 1] += weighted.1
                sumWP[index * 3 + 2] += weighted.2
            }
        }
        return holes
    }

    /// L̂ from the accumulator slices: `Σwp / Σw` per channel (NaN-safe —
    /// a zero Σw pixel stays 0, the HOLE output).
    public static func finalizeBand(
        sumW: [Float], sumWP: [Float]
    ) -> [Float] {
        var lHat = [Float](repeating: 0, count: sumW.count)
        for index in stride(from: 0, to: sumW.count, by: 3) {
            let w = sumW[index]
            guard w > 0 else { continue }
            lHat[index] = sumWP[index] / w
            lHat[index + 1] = sumWP[index + 1] / sumW[index + 1]
            lHat[index + 2] = sumWP[index + 2] / sumW[index + 2]
        }
        return lHat
    }

    // MARK: - Full-merge convenience (the test face; the service streams)

    /// The whole-bracket merge over a stack of FULL frames (all sources
    /// resident — tests only; the service path streams by bands). Runs
    /// phase 1 (+ phase 2 when deGhost) and returns the final linear RGB
    /// planes + the weight map + the ghost union + the hole fraction.
    public static func mergeFrames(
        frames: [SourceBand],
        params: StackMergeService.MergeParams,
        width: Int, height: Int
    ) -> (
        rgb: [Float], weightMap: [Float], ghostUnion: [UInt8]?,
        holeFraction: Float
    ) {
        let pixelCount = width * height
        var ghostUnion: [UInt8]? = params.deGhost
            ? [UInt8](repeating: 0, count: pixelCount) : nil
        var holes = 0
        var lHat: [Float]
        var weightMap: [Float]

        // Phase 1: the base merge. The accumulator pair lives ONLY in this
        // scope — with deGhost ON it is finalized into L̂0 and RELEASED
        // before phase 2 mints its own pair (the 41 B/px peak contract,
        // `BandStreamer.accumulatorBytes`).
        if params.deGhost {
            var sumW = [Float](repeating: 0, count: pixelCount * 3)
            var sumWP = [Float](repeating: 0, count: pixelCount * 3)
            _ = accumulateBand(
                bands: frames, params: params, lHatBand: nil,
                ghostUnion: &ghostUnion, sumW: &sumW, sumWP: &sumWP)
            lHat = finalizeBand(sumW: sumW, sumWP: sumWP)
            weightMap = [Float]()
        } else {
            var sumW = [Float](repeating: 0, count: pixelCount * 3)
            var sumWP = [Float](repeating: 0, count: pixelCount * 3)
            holes = accumulateBand(
                bands: frames, params: params, lHatBand: nil,
                ghostUnion: &ghostUnion, sumW: &sumW, sumWP: &sumWP)
            lHat = finalizeBand(sumW: sumW, sumWP: sumWP)
            weightMap = weightFromSum(sumW, width: width, height: height)
        }

        // Phase 2: the de-ghost re-aggregation.
        if params.deGhost {
            var ghostSumW = [Float](repeating: 0, count: pixelCount * 3)
            var ghostSumWP = [Float](repeating: 0, count: pixelCount * 3)
            holes = accumulateBand(
                bands: frames, params: params, lHatBand: lHat,
                ghostUnion: &ghostUnion, sumW: &ghostSumW, sumWP: &ghostSumWP)
            lHat = finalizeBand(sumW: ghostSumW, sumWP: ghostSumWP)
            weightMap = weightFromSum(ghostSumW, width: width, height: height)
        }

        // Interleave L̂ into RGBA (alpha = 1) for the product plane.
        var rgba = [Float](repeating: 0, count: pixelCount * 4)
        for index in 0..<pixelCount {
            rgba[index * 4] = lHat[index * 3]
            rgba[index * 4 + 1] = lHat[index * 3 + 1]
            rgba[index * 4 + 2] = lHat[index * 3 + 2]
            rgba[index * 4 + 3] = 1
        }
        let fraction = pixelCount > 0
            ? Float(holes) / Float(pixelCount) : 0
        return (rgba, weightMap, ghostUnion, fraction)
    }

    /// The weight map = min-channel Σw per pixel (the coverage/HOLE face).
    public static func weightFromSum(
        _ sumW: [Float], width: Int, height: Int
    ) -> [Float] {
        let pixelCount = width * height
        var map = [Float](repeating: 0, count: pixelCount)
        for index in 0..<pixelCount {
            map[index] = min(
                sumW[index * 3], sumW[index * 3 + 1], sumW[index * 3 + 2])
        }
        return map
    }
}
