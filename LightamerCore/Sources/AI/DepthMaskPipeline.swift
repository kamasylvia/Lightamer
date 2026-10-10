import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// DepthMaskPipeline (M4-3-01 KD-4, D-3) — the depth-plane → near-mask
// four-stage PURE function core.
//
//   ① percentile normalize   low = p10, high = p95 (numpy 'linear'
//                            interpolation: rank = q/100·(n−1) + lerp), then
//                            relative = clamp((d−low)/max(high−low, 1e−6), 0, 1)
//                            — Lumen selection.py:71-72 verbatim (MIT read-only
//                            reference; the 1e−6 denominator floor is kept for
//                            byte parity with the reference formula even though
//                            guard (a) below throws first — checker o3's dead-
//                            code note).
//   ② near window            clamp((relative−0.48)/0.22, 0, 1) — selection.py:73
//                            (≥0.48 starts foreground, ≥0.70 is full foreground).
//   ③ smoothstep             p·p·(3−2p) — selection.py:74.
//   ④ alpha plane out.
//
// FIXED v1 PARAMETERS (OQ-4-A: zero UI exposure — the named constants are the
// only face; the function parameters exist so a later tunable edition is a
// zero-rework seam and the golden tests can scan them).
//
// VALIDITY GUARDS (D-2, both throw `noDepthStructure`, NOTHING lands):
//   (a) degenerate domain  high−low ≤ max(1e−6, 1e−4·max(|low|,|high|)) —
//                          the flat-wall face.
//   (b) near coverage      mean(α > 0.5) < 3e−4 — Lumen auto_masks.py:77-79's
//                          0.03% floor.
//   NaN inputs propagate percentile → α=NaN → every (α>0.5) comparison is
//   false → guard (b) throws. The pipeline never returns an all-ones (or
//   all-NaN) plane; the WORKER additionally gates NaN at the source with
//   `inferenceFailed` (m3) so the attribution stays honest — the two faces
//   are orthogonal.
//
// L048 COMPARISON DISCIPLINE: all inputs/outputs are raw F32 planes; the
// golden tests compare through `Double(Float(x))` widening with tolerances
// derived from the smoothstep slope bound (dα/dp ≤ 1.5·span⁻¹) + F32
// rounding — see DepthMaskPipelineTests' header note.
// ─────────────────────────────────────────────────────────────────────────────

public enum DepthMaskPipeline {

    /// The v1 fixed face (OQ-4-A). Lumen selection.py:71-74 same values.
    public static let percentileLow: Float = 10
    public static let percentileHigh: Float = 95
    public static let windowStart: Float = 0.48
    public static let windowSpan: Float = 0.22
    /// The near-coverage floor (0.03%, auto_masks.py:77's 0.0003).
    public static let coverageFloor: Float = 3e-4

    /// numpy-default ('linear') percentile of ONE float array: virtual rank
    /// `r = q/100·(n−1)` into the ascending sort, `lo`/`hi` neighbors
    /// linearly interpolated. `nil` = empty input. The test suite pins this
    /// against uv/numpy-computed reference values (independent derivation —
    /// never re-typed from this body).
    public static func percentile(_ values: [Float], _ q: Float) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Double(q) / 100.0 * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        if lo == hi { return sorted[lo] }
        let fraction = Float(rank - Double(lo))
        return sorted[lo] * (1 - fraction) + sorted[hi] * fraction
    }

    /// The four-stage core: relative-inverse-depth plane → NEAR-mask α
    /// plane (same dimensions). Throws `noDepthStructure` (guard a/b) and
    /// `invalidInput` (empty plane) — never returns a degenerate mask.
    /// Parameters default to the v1 fixed face; the golden scan exercises
    /// the seam (zero UI exposure).
    public static func nearMask(
        depth: AIMaskPlane,
        percentileLow: Float = DepthMaskPipeline.percentileLow,
        percentileHigh: Float = DepthMaskPipeline.percentileHigh,
        windowStart: Float = DepthMaskPipeline.windowStart,
        windowSpan: Float = DepthMaskPipeline.windowSpan,
        coverageFloor: Float = DepthMaskPipeline.coverageFloor
    ) throws -> AIMaskPlane {
        guard !depth.floats.isEmpty else {
            throw AIMaskError.invalidInput("empty depth plane")
        }
        // ① percentile normalize (numpy 'linear' semantics).
        guard let low = percentile(depth.floats, percentileLow),
              let high = percentile(depth.floats, percentileHigh)
        else {
            throw AIMaskError.invalidInput("empty depth plane")
        }
        // Guard (a): the degenerate-domain face (flat depth carries no
        // layering). NaN inputs slip the comparison (NaN <= x is false) and
        // land on guard (b) — documented above.
        if high - low <= max(Float(1e-6), Float(1e-4) * max(abs(low), abs(high))) {
            throw AIMaskError.noDepthStructure("degenerate depth range")
        }
        let range = max(high - low, 1e-6)  // Lumen :72 byte parity (dead floor)
        let divisor = Float(range)
        // ②③④ window + smoothstep, one fused pass.
        var alpha = [Float](repeating: 0, count: depth.floats.count)
        var nearCount = 0
        for index in depth.floats.indices {
            let relative = (depth.floats[index] - low) / divisor
            let clamped = min(max(relative, 0), 1)
            let windowed = min(max((clamped - windowStart) / windowSpan, 0), 1)
            let smooth = windowed * windowed * (3 - 2 * windowed)
            alpha[index] = smooth
            if smooth > 0.5 { nearCount += 1 }
        }
        // Guard (b): the near-coverage face (0.03% floor).
        let coverage = Float(nearCount) / Float(alpha.count)
        if coverage < coverageFloor {
            throw AIMaskError.noDepthStructure(
                "near mask covers < 0.03%")
        }
        return AIMaskPlane(width: depth.width, height: depth.height, floats: alpha)
    }
}
