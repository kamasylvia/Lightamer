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

// ─────────────────────────────────────────────────────────────────────────
// Per-channel RGB min/max reduce (Plan 03-06-T5) — the filmic auto
// black/white keys' full-image statistics (dt's picked_color_min/max
// whole-preview semantics). Two passes mirroring the histogram pair:
//
//   norm_minmax_partial — one 16×16 threadgroup per block; each thread
//     contributes its pixel to the threadgroup's per-channel min/max
//     via the monotonic uint coding of float (atomic_min/max on
//     atomic_uint — MSL has no float atomics), then the group writes
//     float4(min.xyz, 0) / float4(max.xyz, 0) partials.
//   norm_minmax_total   — 4 threads fold the partials (3 channels + pad).
//
// NaN policy: the monotonic uint coding maps NaN above +inf (dt's
// fixtures carry no NaN; the coding keeps atomic_min from picking one).
// ─────────────────────────────────────────────────────────────────────────

inline uint mm_code(float f) {
    uint u = as_type<uint>(f);
    return u ^ ((as_type<int>(f) >> 31) | 0x80000000u);
}

inline float mm_decode(uint u) {
    return as_type<float>(u ^ (((u >> 31) - 1u) | 0x80000000u));
}

kernel void norm_minmax_partial(
    texture2d<float, access::read> in [[texture(0)]],
    device float*                  partialsMin [[buffer(0)]],
    device float*                  partialsMax [[buffer(1)]],
    uint2 tgPos [[threadgroup_position_in_grid]],
    uint2 tpid [[thread_position_in_threadgroup]])
{
    threadgroup atomic_uint localMin[3];
    threadgroup atomic_uint localMax[3];

    const uint linear = tpid.y * 16 + tpid.x;
    if (linear < 3) {
        atomic_store_explicit(&localMin[linear], mm_code(FLT_MAX), memory_order_relaxed);
        atomic_store_explicit(&localMax[linear], mm_code(-FLT_MAX), memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const uint2 pixel = tgPos * 16 + tpid;
    if (pixel.x < in.get_width() && pixel.y < in.get_height()) {
        const float3 px = in.read(pixel).rgb;
        for (uint c = 0; c < 3; c++) {
            atomic_fetch_min_explicit(&localMin[c], mm_code(px[c]), memory_order_relaxed);
            atomic_fetch_max_explicit(&localMax[c], mm_code(px[c]), memory_order_relaxed);
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const uint tgLinear = tgPos.y * ((in.get_width() + 15) / 16) + tgPos.x;
    if (linear < 3) {
        partialsMin[tgLinear * 4 + linear] =
            mm_decode(atomic_load_explicit(&localMin[linear], memory_order_relaxed));
        partialsMax[tgLinear * 4 + linear] =
            mm_decode(atomic_load_explicit(&localMax[linear], memory_order_relaxed));
    }
}

kernel void norm_minmax_total(
    device const float* partialsMin [[buffer(0)]],
    device const float* partialsMax [[buffer(1)]],
    device float*       result      [[buffer(2)]],
    constant uint&      nPartials   [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= 3) return;
    float mn = FLT_MAX;
    float mx = -FLT_MAX;
    for (uint p = 0; p < nPartials; p++) {
        mn = fmin(mn, partialsMin[p * 4 + tid]);
        mx = fmax(mx, partialsMax[p * 4 + tid]);
    }
    result[tid] = mn;
    result[3 + tid] = mx;
}
