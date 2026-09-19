import CoreGraphics
import Foundation

/// D-C3 PREVIEW quantization: the interactive pipe's target long edge is
/// `min(drawableLongEdge × pixelScale, 2560)` snapped DOWN to a coarse
/// 360px-step ladder. A window resize whose target stays inside one ladder
/// step produces the SAME bucket → the coordinator skips the re-render
/// entirely (the anti-jitter guard against render storms during edge
/// drags); only a CROSS-step resize re-renders, and the previous bucket's
/// planes stay in `PipeCache` so jittering back across the boundary is a
/// cache hit, not a re-render (02-RESEARCH §2.3).
///
/// Ladder (descending): 2560 / 2200 / 1840 / 1480 / 1120 / 760 / 360.
/// The top step is also the hard cap (D-C3: 2560px long edge).
///
/// **5K/6K soft-display note (02-RESEARCH Risk #4):** a fullscreen 5K/6K
/// panel has a ~2560pt-long edge → ×2 = 5120px request, capped at 2560px —
/// fullscreen viewing upscales the PREVIEW plane ≈2× (soft). Accepted for
/// now (the D-C3 cap bounds the per-plane cache footprint); revisit with
/// Phase 4 zoom, where a真 100% ROI path supersedes whole-image fit.
///
/// Pure function by contract: no Metal, no `MachineState`, no I/O — the
/// ONLY inputs are the parameters, so `PreviewBucketTests` can sweep the
/// boundaries without a GPU.
public enum PreviewBucket {

    /// Hard cap on the PREVIEW long edge (D-C3). 2560px float32 RGBA
    /// ≈ 70MB/plane — the number every cache-footprint statement quotes.
    public static let cap: Int = 2560

    /// The quantization ladder, DESCENDING. All steps are multiples of 360
    /// (the THUMBNAIL long edge) minus none — 2560 is the D-C3 cap, the
    /// rest descend in ~360-380px steps down to the 360px floor.
    public static let ladder: [Int] = [2560, 2200, 1840, 1480, 1120, 760, 360]

    /// Quantize a drawable long edge (in DEVICE PIXELS after `pixelScale`)
    /// to its ladder bucket.
    ///
    /// - Parameters:
    ///   - drawableLongEdge: the viewport's long edge; callers pass the
    ///     POINT size and let `pixelScale` (default 2.0 — Retina) convert.
    ///   - pixelScale: backing-scale factor; override to 1.0 to treat the
    ///     input as an already-pixel target (tests do this for the raw
    ///     boundary table).
    /// - Returns: the largest ladder value ≤ `min(drawable × scale, cap)`;
    ///     below-ladder targets (and zero/negative/zero-scale inputs,
    ///     defensively) quantize to the 360px floor.
    public static func longEdge(
        forDrawable drawableLongEdge: Int,
        pixelScale: CGFloat = 2.0
    ) -> Int {
        let floor = ladder[ladder.count - 1] // 360
        guard drawableLongEdge > 0, pixelScale > 0 else { return floor }
        let target = min(Int((CGFloat(drawableLongEdge) * pixelScale).rounded()), cap)
        // Ladder is DESCENDING: first entry ≤ target is the snap-DOWN bucket.
        return ladder.first { $0 <= target } ?? floor
    }
}
