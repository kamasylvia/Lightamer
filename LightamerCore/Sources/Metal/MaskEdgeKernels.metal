#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// Mask edge kernels (Plan M2-7-1 T6, KD-6; D-M2-7-CONTEXT-4) — the
// Follow-Edges edge map: ONE precomputed Sobel pass over the layer's below
// composite plane, cached at the reserved `edgeMapPosition` (-4) keyed on
// (imageID ⊕ pipeType ⊕ upstreamHash ⊕ roi ⊕ algorithm version) — the map
// belongs to the below-composite CONTENT, never to a layer or the sidecar.
//
// Single PSO, zero function constants (the checker-recognized shape): the
// threshold is NOT applied here — the kernel emits the NORMALIZED magnitude
// (÷ 4·√2, the 3×3 Sobel's theoretical max for [0,1] inputs) and the
// walker's `edgeThreshold` does the gating (threshold BEFORE normalizing
// would pin the parameter to one plane's dynamic range).
//
// L006: full float math; no half.
// ─────────────────────────────────────────────────────────────────────────────

static inline float mask_luma(float3 rgb) {
    // Rec.709 luma weights (KD-6①: the plan-pinned 0.2126/0.7152/0.0722).
    return dot(rgb, float3(0.2126, 0.7152, 0.0722));
}

kernel void mask_edge_map(
    texture2d<float, access::read> below [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    const int2 size = int2(below.get_width(), below.get_height());

    // 3×3 neighborhood, edge-clamped (no sampler — explicit clamped reads).
    float l[9];
    int k = 0;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            int2 p = int2(gid) + int2(i, j);
            p = min(max(p, int2(0)), size - 1);
            l[k++] = mask_luma(below.read(uint2(p)).rgb);
        }
    }
    // Sobel (the | −1 0 +1 | × [1 2 1] separable kernels).
    const float gx = (l[2] + 2.0 * l[5] + l[8]) - (l[0] + 2.0 * l[3] + l[6]);
    const float gy = (l[6] + 2.0 * l[7] + l[8]) - (l[0] + 2.0 * l[1] + l[2]);
    // Threshold-pre normalization: mag ∈ [0, 4·√2] for [0,1] inputs.
    const float mag = sqrt(gx * gx + gy * gy) / 5.656854249492381;
    out.write(float4(clamp(mag, 0.0, 1.0), 0.0, 0.0, 1.0), gid);
}
