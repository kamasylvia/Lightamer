#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// highpass kernels — Plan 04-05-T3, IOP-DETAIL-03 (op "highpass",
// v50 slot 34.0).
//
// Darktable reference: `src/iop/highpass.c` (tree dc58cf0ba1) +
// `data/kernels/highpass.cl` — Lab-domain inverted highpass, CL leg
// (`process_cl:120-231` + kernels):
//   1. `highpass_invert`  pixel.x = clamp(100 − L)
//   2. h/v gaussian blur  (dt: `dt_box_mean` 8 iterations; WE use the
//                          shared Deriche IIR at dt's σ correlation —
//                          DECISIONS D4, see the module header)
//   3. `highpass_mix`     o.x = 50 + ((0.5·a + 0.5·b) − 50)·contrast_scale,
//                          a/b → 0, clamp to (0..100, ±128)
//
// where a = original L, b = blurred inverted L, contrast_scale =
// (contrast/100)·7.5 (`highpass.cl:155` — the CL leg is authoritative;
// the CPU leg's `:289` ×0.5 is its packed-L double-traversal bookkeeping,
// DECISIONS D3).
//
// (The CPU leg's remaining 1/16th tail `:294-301` is the same formula —
// the CL single-pass mix covers all pixels.)
//
// L006: float32 only. L008: endEncoding precedes commit (dispatch helpers).
// ─────────────────────────────────────────────────────────────────────────

// Step 1 — Rec2020 → inverted L (100 − L, clamped — `highpass.cl:33`;
// the a/b channels ride the ORIGINAL texture into the mix, so the prep
// only needs to carry L; alpha rides for the blur's 4-channel shape).
kernel void highpass_prep(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float4 px = in.read(gid);
    const float3 lab = la_rec2020_to_lab(px.rgb);
    out.write(float4(clamp(100.0f - lab.x, 0.0f, 100.0f), 0.0f, 0.0f, px.a), gid);
}

struct HighpassMixUniforms {
    float contrastScale; // (contrast/100)·7.5 (highpass.cl:155)
    float pad0;
    int2 srcOffset;     // roiOut.xy − roiIn.xy (0 under tiling)
};

// Step 3 — the CL mix (`highpass.cl:152-163` verbatim shape).
kernel void highpass_mix(
    texture2d<float, access::read>  in      [[texture(0)]],
    texture2d<float, access::read>  blurred [[texture(1)]],
    texture2d<float, access::write> out     [[texture(2)]],
    constant HighpassMixUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint2 src = uint2(int2(gid) + u.srcOffset);
    const float4 io = in.read(src);
    const float4 b4 = blurred.read(src);

    const float3 lab = la_rec2020_to_lab(io.rgb);
    const float ox = 50.0f + ((0.5f * lab.x + 0.5f * b4.x) - 50.0f) * u.contrastScale;
    const float3 outLab = float3(clamp(ox, 0.0f, 100.0f), 0.0f, 0.0f);
    out.write(float4(la_lab_to_rec2020(outLab), io.a), gid);
}
