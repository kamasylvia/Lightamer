import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// AIMaskGeometry (Plan M9-1 T3, D-M9A-6) — the Path tool's stroke-sampling
// pure functions. The stroke is resampled at EQUAL ARC LENGTH intervals
// (24 px in the ANALYSIS-image pixel domain — the upstream
// kAiMaskStrokePromptSpacingItemPx behavior alignment; the numeric
// constants are public parameter facts, zero code copied), the sample
// count = min(16, the point budget's remaining headroom) (the upstream
// 16-point stroke ceiling folded into OUR 13/11 Vision budget — the
// declared降级, the UI counter carries it).
//
// The output feeds the EXISTING refine-point vector
// (buildLayerBRequest's addIncludedPoint path — zero second assembly
// route). Pure math, no Vision dependency, unit-testable in isolation.
// ─────────────────────────────────────────────────────────────────────────────

public enum AIMaskPathSampling {

    /// The equal-arc-length sampling interval, ANALYSIS-image pixels (the
    /// upstream kAiMaskStrokePromptSpacingItemPx = 24.0 behavior fact).
    public static let spacingPx: Float = 24.0

    /// The stroke-sample ceiling (the upstream
    /// kAiMaskMaximumStrokePromptPoints = 16 behavior fact) — folded with
    /// the budget headroom by `sampleCount(budgetHeadroom:)`.
    public static let maxStrokePoints = 16

    /// The effective sample count: min(16, the budget's remaining
    /// headroom). With our 13/11 budgets: a point-seeded session keeps
    /// 12 samples for the stroke (12 + the seed = 13 = the full budget);
    /// a box-seeded session keeps 11.
    public static func sampleCount(budgetHeadroom: Int) -> Int {
        max(0, min(maxStrokePoints, budgetHeadroom))
    }

    /// Resample a stroke (a polyline in ANALYSIS-image pixel coordinates,
     /// row-0-top) into at most `count` view-normalized points spaced
    /// `spacing` pixels of arc length apart, START point included; the
    /// tail beyond the last full interval is dropped (an equal-interval
    /// resample, not an endpoint-forcing one — a short stroke under one
    /// spacing yields exactly ONE point, the start).
    ///
    /// The polyline is walked segment by segment accumulating arc length;
    /// each crossing of a multiple of `spacing` emits the interpolated
    /// point (deterministic order: stroke order).
    public static func sampleStroke(
        stroke: [SIMD2<Float>],
        spacing: Float = AIMaskPathSampling.spacingPx,
        count: Int,
        imageWidth: Int,
        imageHeight: Int
    ) -> [AIMaskPoint] {
        precondition(spacing > 0, "spacing must be positive")
        precondition(imageWidth > 0 && imageHeight > 0, "image size must be positive")
        guard count > 0, stroke.count > 0 else { return [] }

        var samples = [SIMD2<Float>]()
        samples.reserveCapacity(count)
        if count >= 1 { samples.append(stroke[0]) }
        guard count > 1, stroke.count > 1 else {
            return samples.map { pixelToNormalized($0, width: imageWidth, height: imageHeight) }
        }

        var emitted = 1
        var nextArc = spacing
        var accumulated: Float = 0
        for index in 1..<stroke.count {
            let a = stroke[index - 1]
            let b = stroke[index]
            let segment = b - a
            let length = simd_length(segment)
            guard length > 0 else { continue }
            // Emit every spacing crossing inside this segment.
            while nextArc <= accumulated + length, emitted < count {
                let t = (nextArc - accumulated) / length
                samples.append(a + segment * t)
                emitted += 1
                nextArc += spacing
            }
            accumulated += length
            if emitted >= count { break }
        }
        return samples.map { pixelToNormalized($0, width: imageWidth, height: imageHeight) }
    }

    /// Analysis-image pixel → view-normalized (top-left) point.
    private static func pixelToNormalized(
        _ pixel: SIMD2<Float>, width: Int, height: Int
    ) -> AIMaskPoint {
        AIMaskPoint(
            x: min(max(pixel.x / Float(width), 0), 1),
            y: min(max(pixel.y / Float(height), 0), 1))
    }
}
