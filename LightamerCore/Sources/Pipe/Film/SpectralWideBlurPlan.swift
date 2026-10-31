import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SpectralWideBlurPlan (Plan M8-3+ T5) — the host wide-blur plan (the
// upstream `sf_wide_blur_plan`'s port — dt spektrafilm
// `4d1fb6a95b:src/common/spektra_core.c:391-422`, GPL-3.0, (C) darktable
// developers; the variance TARGET differs — R-M83P-5 ②):
//
//   k         = ⌊σ / 8⌋ (SF_WIDE_BLUR_LOW_SIGMA)
//   σ_low     = √(σ² − (k²−1)/12 − k²/6) / k — the TRUE-σ target (our
//               blur path is the exact-kernel separable Gaussian — NO
//               recursive legacy, so the `_yvv_ref_variance` closed form
//               is NOT ported; the subtracted terms are the box mean's
//               (k²−1)/12 + the bilinear interpolation's k²/6 ONLY)
//   ox/oy     = the block grid's absolute-coordinate anchor
//               (((roi % k) + k) % k — tile-consistent)
//   lw/lh     = the low-face dimensions ((o + w − 1) / k + 1)
//
// The plan FAILS (nil) below SF_WIDE_BLUR_MIN_SIGMA (16px) — the
// caller falls back to the exact-kernel path (the upstream
// `sf_blur_plane3_wide` shape).
// ─────────────────────────────────────────────────────────────────────────────

public enum SpectralWideBlurPlan {

    /// Upstream's three thresholds (verbatim — the EFFECT threshold is
    /// the STARTING value held (the T5 re-mark probe is pending — the 100px
    /// value stands until the T7 evidence leg法定 a re-marked one,
    /// DECISIONS-logged).
    public static let minSigma: Float = 16.0
    public static let lowSigma: Float = 8.0
    public static let effectSigmaStart: Float = 100.0

    /// One wide-blur plan (all Ints exact, σ_low Float32).
    public struct Plan: Sendable, Equatable {
        public let k: Int
        public let sigmaLow: Float
        public let lw: Int
        public let lh: Int
        public let ox: Int
        public let oy: Int
    }

    /// The plan (nil = below the min face — the caller runs the
    /// exact-kernel path instead).
    public static func plan(
        sigma: Float, width: Int, height: Int, roiX: Int = 0, roiY: Int = 0
    ) -> Plan? {
        guard sigma >= minSigma, width >= 1, height >= 1 else { return nil }
        let k = Int(sigma / lowSigma)
        guard k >= 1 else { return nil }
        // The TRUE-σ variance target (R-M83P-5 ② — Double intermediates,
        // the host's own rounding face).
        let target = Double(sigma) * Double(sigma)
        let box = (Double(k * k) - 1.0) / 12.0
        let interp = Double(k * k) / 6.0
        let sigmaLow = Float(sqrt(max(target - box - interp, 0.0)) / Double(k))
        let ox = ((roiX % k) + k) % k
        let oy = ((roiY % k) + k) % k
        let lw = (ox + width - 1) / k + 1
        let lh = (oy + height - 1) / k + 1
        return Plan(k: k, sigmaLow: sigmaLow, lw: lw, lh: lh, ox: ox, oy: oy)
    }

    /// The host reciprocal table (upstream's `sf_wide_blur_inv_table` —
    /// inv[0] = 0, inv[i] = 1/i — the device never re-derives it).
    public static func inverseTable(k: Int) -> [Float] {
        var inv = [Float](repeating: 0, count: k + 1)
        for i in 1...k {
            inv[i] = 1.0 / Float(i)
        }
        return inv
    }

    /// The low-face blur σ the plan targets (the TRUE-σ face's audit
    /// companion: σ_low · k → σ within the deducted variances).
    public static func effectiveSigma(_ plan: Plan) -> Double {
        let k = Double(plan.k)
        let low = Double(plan.sigmaLow) * k
        return sqrt(
            low * low + (k * k - 1.0) / 12.0 + k * k / 6.0)
    }
}
