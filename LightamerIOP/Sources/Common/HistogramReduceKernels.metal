#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// Histogram reduction kernels (Plan 03-03-T5) — the shared full-image
// reduce used by the levels AUTOMATIC mode (and later by the filmic auto
// black/white keys, 03-06). Two passes (RESEARCH Open#6 selection: the
// hand-written reduce is the default; MPS histogram remains a swappable
// alternative with the same interface):
//
//   1. histogram_partial — one 16×16 threadgroup per 16×16 pixel block;
//      each thread computes the pixel's Lab L INLINE (la_rec2020_to_lab)
//      and bins it into a threadgroup-local 256-bin histogram (atomic
//      adds), then the group writes its partial row.
//   2. histogram_total  — 256 threads, one per bin, sum the partials.
//
// Binning: bin = uint(L × 256/100) clamped to [0,255] (L ∈ [0,100] Lab;
// negatives clamp to 0). 256 bins per the plan mandate (dt uses 16384 —
// recorded divergence on LevelsModule).
//
// L006 float32; the reduce runs on ITS OWN command buffer and the
// caller fences before readback (L014).

kernel void histogram_partial(
    texture2d<float, access::read> in [[texture(0)]],
    device uint*                   partials [[buffer(0)]],
    uint2 tgPos [[threadgroup_position_in_grid]],
    uint2 tpid [[thread_position_in_threadgroup]])
{
    threadgroup atomic_uint localHist[256];

    // zero the local histogram (16×16 threads = exactly 256 slots)
    const uint linear = tpid.y * 16 + tpid.x;
    atomic_store_explicit(&localHist[linear], 0u, memory_order_relaxed);
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // one pixel per thread, bounds-checked
    const uint2 pixel = tgPos * 16 + tpid;
    if (pixel.x < in.get_width() && pixel.y < in.get_height()) {
        const float4 px = in.read(pixel);
        const float3 lab = la_rec2020_to_lab(px.rgb);
        const float binF = lab.x * (256.0f / 100.0f);
        const uint bin = min((uint)max(binF, 0.0f), 255u);
        atomic_fetch_add_explicit(&localHist[bin], 1u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const uint tgLinear = tgPos.y * ((in.get_width() + 15) / 16) + tgPos.x;
    partials[tgLinear * 256 + linear] = atomic_load_explicit(&localHist[linear], memory_order_relaxed);
}

kernel void histogram_total(
    device const uint* partials [[buffer(0)]],
    device uint*       total    [[buffer(1)]],
    constant uint&     nPartials [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= 256) return;
    uint sum = 0;
    for (uint p = 0; p < nPartials; p++) {
        sum += partials[p * 256 + tid];
    }
    total[tid] = sum;
}
