import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AIPatchAssembly (Plan M6-4-02 T1, KD-1) — the hi-res detail-patch PURE
// assembly face: the planner (where to re-analyze) and the composer (how a
// hi-res patch plane lands back into the session's live plane).
//
// LightCraft's "delayed hi-res detail patch" semantics (docs/ai-masks.md,
// MIT OR Apache-2.0 — SEMANTICS only, zero code copied): about a second
// after the last interaction the region around the selection is analyzed
// again zoomed-in, kept as a high-resolution patch (AT MOST 4 per
// selection, the earliest replaced FIFO), so small objects get far finer
// edges than one full-frame pass gives. Our native assembly:
//
//   AIPatchPlanner  — mask-coverage bbox (≥0.5) → pad 25% of the bbox's
//                     short side → image-bounds clamp. SKIP GATES (registered
//                     rules, each test-pinned): empty mask → no patch;
//                     bbox > 60% of the frame → no patch (the full frame is
//                     already accurate-pass output — a patch has no gain);
//                     patch min side < 32 px → no patch (noise domain).
//   AIPatchComposer — the patch plane lands INSIDE its rect (bilinear
//                     resampled to the rect's pixel size — the layer-B ROI
//                     output resolution is a runtime fact, the composer
//                     absorbs it); the rect's rim is a LINEAR ramp feather
//                     (band = 5% of the patch short side, clamped 2...16 px);
//                     outside the rect the base plane passes through
//                     BYTE-IDENTICAL. Cap ≤ 4 patches per selection — the
//                     earliest is replaced (FIFO, deterministic).
//
// ZERO-KERNEL RED LINE: everything here is CPU pure functions over
// AIMaskPlane floats — no .metal, no Vision, no Metal context. The inference
// leg lives in AIMaskService.segmentPatch (the segmentSubject thin wrapper).
//
// Coordinates: a patch rect is in BASE-PLANE pixel space, row 0 = image TOP
// (the AIMaskPlane contract). The view-normalized conversion goes through
// `normalized(imageWidth:imageHeight:)` → AIMaskRect, whose `visionRect` is
// the SINGLE Y-flip seam (07-1 AIMaskTypes) — the patch never flips a buffer.
// ─────────────────────────────────────────────────────────────────────────────

/// A pixel-space rectangle over a row-major plane (row 0 = image TOP).
public struct AIPatchRect: Equatable, Sendable, Hashable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        precondition(x >= 0 && y >= 0 && width > 0 && height > 0,
                     "AIPatchRect must be a non-empty positive rect")
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }

    /// The view-normalized form (TOP-left origin, y down — the AIMaskRect
    /// convention). The Vision Y-flip happens ONLY in `AIMaskRect.visionRect`.
    public func normalized(imageWidth: Int, imageHeight: Int) -> AIMaskRect {
        precondition(imageWidth > 0 && imageHeight > 0)
        return AIMaskRect(
            x: Float(x) / Float(imageWidth),
            y: Float(y) / Float(imageHeight),
            width: Float(width) / Float(imageWidth),
            height: Float(height) / Float(imageHeight))
    }

    /// The pixel-space round-trip of a view-normalized rect (tests + any
    /// normalized-coordinate consumer; floor the min corner, ceil the extent).
    public static func from(
        normalized: AIMaskRect, imageWidth: Int, imageHeight: Int
    ) -> AIPatchRect {
        let x = Int(normalized.x * Float(imageWidth)).clamped(to: 0...(imageWidth - 1))
        let y = Int(normalized.y * Float(imageHeight)).clamped(to: 0...(imageHeight - 1))
        let w = Int(normalized.width * Float(imageWidth)).clamped(to: 1...(imageWidth - x))
        let h = Int(normalized.height * Float(imageHeight)).clamped(to: 1...(imageHeight - y))
        return AIPatchRect(x: x, y: y, width: w, height: h)
    }
}

/// The patch-placement planner (KD-1; every gate is a named constant and a
/// test-pinned rule — no "looks reasonable" thresholds).
public enum AIPatchPlanner {

    /// A mask pixel ≥ this enters the coverage bbox.
    public static let coverageThreshold: Float = 0.5

    /// SKIP GATE: bbox area above this fraction of the frame → no patch
    /// (the whole frame is already the accurate pass's output).
    public static let maxBBoxFrameFraction: Float = 0.6

    /// The rect grows by this fraction of the bbox's SHORT side per side.
    public static let padFraction: Float = 0.25

    /// SKIP GATE: a patch whose min side falls below this is noise-domain.
    public static let minPatchSide = 32

    /// Plan the patch rect for a base mask plane. nil = skip (empty mask /
    /// oversized bbox / min-side floor — the caller keeps the base plane
    /// untouched; a skip is NEVER an error).
    public static func planPatch(plane: AIMaskPlane) -> AIPatchRect? {
        let w = plane.width, h = plane.height
        guard w > 0, h > 0 else { return nil }

        // Coverage bbox (threshold ≥ 0.5).
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where plane.floats[row + x] >= coverageThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil } // empty mask gate

        let bboxW = maxX - minX + 1
        let bboxH = maxY - minY + 1
        // Oversized-bbox gate (Float64 — the fraction compare must not lose
        // precision on 100MP products).
        if Double(bboxW) * Double(bboxH)
            > Double(maxBBoxFrameFraction) * Double(w) * Double(h) {
            return nil
        }

        // Pad 25% of the bbox short side, clamped to the image bounds.
        let pad = Int((Float(min(bboxW, bboxH)) * padFraction).rounded())
        let rx = max(0, minX - pad)
        let ry = max(0, minY - pad)
        let rw = min(w, maxX + pad + 1) - rx
        let rh = min(h, maxY + pad + 1) - ry

        // Min-side floor gate.
        guard min(rw, rh) >= minPatchSide else { return nil }
        return AIPatchRect(x: rx, y: ry, width: rw, height: rh)
    }
}

/// One hi-res detail patch: the rect it covers (base-plane pixel coords) and
/// its plane at ANY resolution (the composer resamples to the rect's pixel
/// size — the layer-B ROI output resolution is a runtime fact, never assumed).
public struct AIPatch: Equatable, Sendable {
    public let rect: AIPatchRect
    public let plane: AIMaskPlane

    public init(rect: AIPatchRect, plane: AIMaskPlane) {
        self.rect = rect
        self.plane = plane
    }
}

/// The patch → live-plane composer (KD-1). Pure, deterministic, FIFO-capped.
public enum AIPatchComposer {

    /// ≤ 4 patches per selection (LightCraft's same value) — the FIFTH patch
    /// replaces the EARLIEST (FIFO, deterministic).
    public static let maxPatchesPerSelection = 4

    /// The seam ramp band = this fraction of the patch's short side…
    public static let seamFraction: Float = 0.05
    /// …clamped to this pixel range (a band of 1 px would ring; >16 px eats
    /// small patches).
    public static let seamBandRange: ClosedRange<Int> = 2...16

    /// The FIFO cap: keep the LAST `maxPatchesPerSelection` patches in order
    /// (the earliest are the replaced ones). Below the cap this is identity.
    public static func capped(_ patches: [AIPatch]) -> [AIPatch] {
        guard patches.count > maxPatchesPerSelection else { return patches }
        return Array(patches.suffix(maxPatchesPerSelection))
    }

    /// Compose the patches onto the base plane. Later patches land over
    /// earlier ones; INSIDE a rect (deeper than the seam band) the value is
    /// the patch's exactly; OUTSIDE every rect the base floats pass through
    /// byte-identical; the rect rim blends linearly over the seam band.
    public static func compose(base: AIMaskPlane, patches: [AIPatch]) -> AIMaskPlane {
        var out = base.floats
        let w = base.width, h = base.height
        for patch in patches {
            // Clamp the rect to the base plane (an out-of-bounds patch is a
            // caller bug elsewhere — here it degrades to the intersection).
            let x0 = max(0, patch.rect.x), y0 = max(0, patch.rect.y)
            let x1 = min(w, patch.rect.maxX), y1 = min(h, patch.rect.maxY)
            guard x1 > x0, y1 > y0 else { continue }
            let rw = x1 - x0, rh = y1 - y0
            // The layer-B ROI plane may arrive at any resolution — bilinear
            // to the rect's pixel size (the same reshape contract as bake).
            let src = AIMaskResample.bilinear(
                patch.plane, toWidth: rw, toHeight: rh)
            let band = seamBand(for: patch.rect)
            for y in y0..<y1 {
                let dyEdge = min(y - y0, y1 - 1 - y) // 0 at the outermost row
                let wy = min(1.0, Float(dyEdge + 1) / Float(band))
                let srcRow = (y - y0) * rw - x0
                let outRow = y * w
                for x in x0..<x1 {
                    let dxEdge = min(x - x0, x1 - 1 - x)
                    let wx = min(1.0, Float(dxEdge + 1) / Float(band))
                    let blend = min(wx, wy)
                    let i = outRow + x
                    out[i] = out[i] * (1 - blend) + src.floats[srcRow + x] * blend
                }
            }
        }
        return AIMaskPlane(width: w, height: h, floats: out)
    }

    /// The seam band for a rect (5% of the short side, clamped 2...16).
    public static func seamBand(for rect: AIPatchRect) -> Int {
        let band = Int(Float(min(rect.width, rect.height)) * seamFraction)
        return min(max(band, seamBandRange.lowerBound), seamBandRange.upperBound)
    }
}

private extension Int {
    /// (Int.max's static `max` shadows the free function inside an Int
    /// extension — the branchy form sidesteps the ambiguity.)
    func clamped(to range: ClosedRange<Int>) -> Int {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}
