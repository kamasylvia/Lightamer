import Accelerate
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AIMaskMorphology (Plan M9-1 T2, D-M9A-9) — the Expand operator: |px| steps
// of 3×3 binary morphology over the bake-seam FLOAT plane (PlanarF domain),
// dilate for px > 0 / erode for px < 0 / identity at 0.
//
// KERNEL CADENCE (the upstream behavior alignment, RESEARCH §1.6 — public
// morphology math, GPL-zero-copy): odd steps run the SQUARE kernel (the
// full 3×3), even steps run the CROSS kernel (the + stencil); the
// alternation approximates a round structural element. The upstream
// sources describe the cadence and the clamp-replicate edge policy —
// both are public-domain morphology facts, no code is copied.
//
// CPU vImage IS THE PRODUCTION LEG (D-M9A-9 — the zero-new-kernel red
// line wins over the "GPU operator" wording in REQUIREMENTS M9AIM-03 /
// ROADMAP M9-1; a legal deviation declared in M9-1-DECISIONS). The bake
// seam is asynchronous, so the CPU pass rides it without a render jank
// face.
//
// GPU UPGRADE SEAM (a follow-up optimization batch may kernel-ize this
// through the M8 new-kernel declaration process — this batch touches
// ZERO .metal files).
//
// HOST REFERENCE (`expandHost`) — the pure-Swift max/min scan. It is the
// GOLDEN TEST EVIDENCE, never a runtime substitute (the upstream
// `MakeAiMaskCoverageTexture` host-reference form): the tests pit it
// against both the vImage leg and an independent BFS ground truth.
//
// EDGE POLICY: clamp-replicate (vImage `kvImageEdgeExtend` == the host's
// clamped index read). Erode under this policy can pull border values
// inward — the same face the upstream margin form documents.
// ─────────────────────────────────────────────────────────────────────────────

public enum AIMaskMorphology {

    /// The feather/expand pixel ceiling (the upstream panel domain —
    /// feather_px ∈ [0,50], expand_px ∈ [−50,50]).
    public static let maxExpandPx = 50

    /// The 3×3 SQUARE kernel stencil offsets (odd steps): the full
    /// eight-neighborhood + center.
    static let squareOffsets: [(Int, Int)] = [
        (-1, -1), (0, -1), (1, -1),
        (-1, 0), (0, 0), (1, 0),
        (-1, 1), (0, 1), (1, 1),
    ]

    /// The 3×3 CROSS kernel stencil offsets (even steps): the + stencil.
    static let crossOffsets: [(Int, Int)] = [
        (0, -1), (-1, 0), (0, 0), (1, 0), (0, 1),
    ]

    /// The step cadence: step 1 (odd) = square, step 2 (even) = cross,
    /// alternating (the near-disk approximation).
    static func offsets(forStep step: Int) -> [(Int, Int)] {
        step % 2 == 1 ? squareOffsets : crossOffsets
    }

    // MARK: - The vImage production leg

    /// Expand (dilate, px > 0) or contract (erode, px < 0) the plane by
    /// |px| alternating 3×3 morphology steps. px == 0 returns the input
    /// plane unchanged (byte-identical — the neutral default the bake
    /// seam relies on).
    public static func expand(plane: AIMaskPlane, px: Int) -> AIMaskPlane {
        guard px != 0, plane.width > 0, plane.height > 0 else { return plane }
        let steps = min(abs(px), maxExpandPx)
        precondition(steps > 0, "expand needs a non-zero pixel radius")
        var floats = plane.floats
        var scratch = [Float](repeating: 0, count: plane.width * plane.height)
        let width = vImagePixelCount(plane.width)
        let height = vImagePixelCount(plane.height)
        let rowBytes = plane.width * MemoryLayout<Float>.stride
        // vImage ARGUMENT ORDER (the C native form the Swift overlay
        // imports): (src, dest, srcOffsetToROI_X, srcOffsetToROI_Y,
        // kernel, kernel_height, kernel_width, flags). The kernel is a
        // GRAYSCALE morphology BIAS — empirically (Morphology.h text +
        // the standalone probe) BOTH dilate and erode fold the kernel as
        // `src − k`: dilate = MAX(src−k) − k[center], erode =
        // MIN(src−k) + k[center]. The SHAPE trick therefore needs a
        // DIRECTIONAL excluded-cell bias (an excluded cell must LOSE the
        // max/min): +1e30 for dilate (src−1e30 never wins a MAX) and
        // −1e30 for erode (src+1e30 never wins a MIN) — every arithmetic
        // path stays FINITE (no ±∞ NaN poisoning). Participating cells
        // bias = epsilon (1e-9): the ±ε round-trip vanishes below the
        // uint16 bake grid (≤50 steps × 2ε = 1e-7 ≪ one LSB 1.5e-5) —
        // the operation is EXACT in the quantized domain (the R8
        // argument the tests pin).
        let dilate = px > 0
        let excluded = dilate ? Float(1e30) : -Float(1e30)
        let epsilon = Float(1e-9)
        let squareKernel: [Float] = [
            epsilon, epsilon, epsilon,
            epsilon, epsilon, epsilon,
            epsilon, epsilon, epsilon,
        ]
        let crossKernel: [Float] = [
            excluded, epsilon, excluded,
            epsilon, epsilon, epsilon,
            excluded, epsilon, excluded,
        ]
        for step in 1...steps {
            let kernel = step % 2 == 1 ? squareKernel : crossKernel
            var source = vImage_Buffer(
                data: &floats, height: height, width: width, rowBytes: rowBytes)
            var destination = vImage_Buffer(
                data: &scratch, height: height, width: width, rowBytes: rowBytes)
            if px > 0 {
                kernel.withUnsafeBufferPointer { pointer in
                    _ = vImageDilate_PlanarF(
                        &source, &destination,
                        0, 0, pointer.baseAddress!, 3, 3,
                        vImage_Flags(kvImageEdgeExtend))
                }
            } else {
                kernel.withUnsafeBufferPointer { pointer in
                    _ = vImageErode_PlanarF(
                        &source, &destination,
                        0, 0, pointer.baseAddress!, 3, 3,
                        vImage_Flags(kvImageEdgeExtend))
                }
            }
            swap(&floats, &scratch)
        }
        return AIMaskPlane(width: plane.width, height: plane.height, floats: floats)
    }

    // MARK: - The host reference (golden evidence, NOT a runtime substitute)

    /// The pure-Swift reference: the same |px|-step alternating kernels,
    /// the same clamp-replicate edge policy, a direct max/min scan. The
    /// golden tests pit this against the vImage leg and an independent
    /// BFS ground truth; production NEVER calls it.
    public static func expandHost(plane: AIMaskPlane, px: Int) -> AIMaskPlane {
        guard px != 0, plane.width > 0, plane.height > 0 else { return plane }
        let w = plane.width, h = plane.height
        let steps = min(abs(px), maxExpandPx)
        var floats = plane.floats
        var buffer = [Float](repeating: 0, count: w * h)
        let dilate = px > 0
        for step in 1...steps {
            let stencil = offsets(forStep: step)
            for y in 0..<h {
                for x in 0..<w {
                    var accumulator = dilate ? -Float.infinity : Float.infinity
                    for (dx, dy) in stencil {
                        // clamp-replicate: out-of-window reads clamp to the
                        // border pixel (the kvImageEdgeExtend face).
                        let sx = min(max(x + dx, 0), w - 1)
                        let sy = min(max(y + dy, 0), h - 1)
                        let sample = floats[sy * w + sx]
                        accumulator = dilate
                            ? max(accumulator, sample)
                            : min(accumulator, sample)
                    }
                    buffer[y * w + x] = accumulator
                }
            }
            swap(&floats, &buffer)
        }
        return AIMaskPlane(width: w, height: h, floats: floats)
    }
}
