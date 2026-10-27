import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AIMaskFeather (Plan M6-4-02 T2, KD-3) — the Edge feather ±100 mapping plus
// the NEGATIVE leg's CPU face. POSITIVE leg: ZERO CPU code here — it rides
// the EXISTING GPU bake seam (`RasterMaskStore.bake(featherRadius:)` →
// `MaskCombiner.blur` Deriche IIR), fed by `sigma(percent:longEdgePixels:)`.
//
// SYMBOL SEMANTICS (KD-3's LightCraft-原文 audit — the authoritative
// tiebreaker this file implements):
//   docs/ai-masks.md: "Edge (per selection, −100…100): below 0 a crisper
//   border, above 0 a feathered one (up to 2% of the long edge)".
//   crates/pipeline/src/masks.rs (MaskShape::Object): e > 0 → Gaussian blur
//   sigma = e · 0.02 · frame_px (our GPU bake seam, same radius formula);
//   e < 0 → LOGIT GAIN, gain = 1 − 7e (e ∈ [−1,0) → gain up to 8) applied to
//   the segmentation logits — a STEEPER transition around the same 0.5
//   contour. No erosion, no complement blur.
//
//   (Plan-text deviation, registered for M6-4-02 DECISIONS: the drafted
//   negative-leg formula "1 − blur(1−x)" is a morphological-duality shape
//   that only erodes under a NONLINEAR primitive — under the plan's own
//   linear Gaussian it algebraically equals blur(x) (kernel sums to 1 ⇒
//   blur(1−x) = 1 − blur(x)), i.e. the SAME feather as the positive leg —
//   the opposite of "收缩". LightCraft's原文 (the plan's designated
//   authority) sharpens logits instead; our plane-domain equivalent is the
//   logit-gain remap below, which keeps the 0.5 contour and narrows the
//   transition — the honest "crisper border".)
//
// THE DOUBLE-FEATHER PIN (KD-3/M5 red line): the legs are MUTUALLY
// EXCLUSIVE — percent > 0 → GPU bake radius = sigma (zero CPU work);
// percent < 0 → the CPU remap here AND the bake radius is forced to 0 by
// the caller (App resolveFeather); percent == 0 → both legs inert (the bake
// default 0 is byte-identical, the CPU face returns the input plane
// unchanged). One feather, exactly one primitive, ever.
// ─────────────────────────────────────────────────────────────────────────────

public enum AIMaskFeather {

    /// The radius ceiling fraction of the long edge (LightCraft's "up to
    /// 2% of the long edge").
    public static let maxRadiusFraction: Float = 0.02

    /// The negative leg's logit gain slope (LightCraft masks.rs: `gain =
    /// 1 − 7e` — at percent −100 the transition is 8× steeper).
    public static let negativeGainSlope: Float = 7.0

    /// percent ∈ −100...100 (clamped) × long-edge pixels → the Gaussian
    /// sigma for the GPU bake seam. `MaskCombiner.blur` takes sigma =
    /// blur_radius directly (the dt blend.c convention) — the returned value
    /// passes through `commitRasterMask(featherRadius:)` UNCHANGED. The
    /// long edge makes the radius resolution-relative (LightCraft's "so
    /// previews and exports match").
    ///   percent ±100, longEdge 1000 → 20; longEdge 4000 → 80.
    public static func sigma(percent: Float, longEdgePixels: Int) -> Float {
        precondition(longEdgePixels > 0, "long edge must be positive")
        let p = max(-100, min(100, percent))
        return abs(p) / 100 * maxRadiusFraction * Float(longEdgePixels)
    }

    // MARK: - The absolute-px face (M9-1 T2, D-M9A-7)

    /// The feather pixel ceiling (the upstream panel domain — feather_px
    /// ∈ [0,50], the ANALYSIS-image pixel domain; the bake plane is the
    /// decode frame, the analysis-image equivalent).
    public static let maxFeatherPx: Float = 50

    /// Absolute px → σ (the M9AIM-03 panel face): px ∈ [0,50] clamped,
    /// folded through the percent leg — the SINGLE conversion source (the
    /// panel slider never re-derives the math). At the bake plane's
    /// long edge ≥ 2500 px the fold is exact (σ == px); below that the
    /// percent leg's own ±100 clamp caps σ at 2% of the long edge (the
    /// pre-existing red-line behavior, kept — small synthetic planes are
    /// the only residents there).
    public static func sigmaFromPx(px: Float, longEdgePixels: Int) -> Float {
        precondition(longEdgePixels > 0, "long edge must be positive")
        let clamped = max(0, min(maxFeatherPx, px))
        let percent = clamped * 100 / (maxRadiusFraction * Float(longEdgePixels))
        return sigma(percent: percent, longEdgePixels: longEdgePixels)
    }

    /// The reverse fold (the M6-4-02 slider-face migration's read-back):
    /// the stored percent → the panel's px value. Only the POSITIVE
    /// domain maps (the negative leg is the logit-gain superset, which
    /// has no absolute-px expression — the panel keeps 0 there).
    public static func pxFromPercent(percent: Float, longEdgePixels: Int) -> Float {
        precondition(longEdgePixels > 0, "long edge must be positive")
        guard percent > 0 else { return 0 }
        return sigma(percent: percent, longEdgePixels: longEdgePixels)
    }

    /// The NEGATIVE leg (percent < 0): the plane-domain logit gain —
    /// `x' = x^g / (x^g + (1−x)^g)` with `g = 1 − 7·(percent/100)` ∈ (1, 8].
    /// Limits are exact (0 → 0, 1 → 1, 0.5 → 0.5): the 0.5 contour is
    /// INVARIANT and the 10-90% transition narrows ≈ g-fold — the "crisper
    /// border" without moving the border.
    ///
    /// percent >= 0 → the input plane returned UNCHANGED (the defensive
    /// short-circuit: the CPU face never feathers — the positive leg is the
    /// GPU bake seam's alone).
    public static func applyFeatherNegative(
        plane: AIMaskPlane, percent: Float
    ) -> AIMaskPlane {
        guard percent < 0 else { return plane }
        let e = max(-100, min(100, percent)) / 100 // ∈ [−1, 0)
        let g = 1 - negativeGainSlope * e          // ∈ (1, 8]
        let floats = plane.floats.map { sharpen($0, gain: g) }
        return AIMaskPlane(width: plane.width, height: plane.height, floats: floats)
    }

    /// One pixel's logit-gain remap (the (0,1) open interval via the pow
    /// form; the exact endpoints short-circuit).
    private static func sharpen(_ x: Float, gain g: Float) -> Float {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        if x == 0.5 { return 0.5 }
        let a = powf(x, g)
        let b = powf(1 - x, g)
        return a / (a + b)
    }
}
