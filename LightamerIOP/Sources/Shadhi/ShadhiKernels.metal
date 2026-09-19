#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// shadhi (shadows & highlights) kernels — Plan 03-04-T2, IOP-TONE-04.
//
// Darktable reference: src/iop/shadhi.c (tree dc58cf0ba1) — the gaussian
// leg (shadhi_algo = SHADHI_ALGO_GAUSSIAN; the bilateral leg is deferred
// to Phase 5 with IOP-DENOISE-03's dt_bilateral port, plan checkpoint
// decision recorded on the module).
//
// Pipeline (dt's CL leg, shadhi.c:530-575, with the Lab domain fused):
//   1. `shadhi_prep`      Rec2020 → Lab (the dt pixelpipe hands the module
//                         IOP_CS_LAB pixels; Lightamer converts in-kernel —
//                         the shared LabMath.h, Plan 03-03-T1).
//   2. GaussianBlur.blur  the Deriche IIR over the RAW Lab buffer (L in
//                         0..100, a/b ±128, alpha 0..1) with dt's bounds
//                         clamp (shadhi.c:372-379) — `Common/GaussianBlur`.
//   3. `shadhi_mix`       the overlay math (shadhi.c:399-490 CPU form,
//                         cross-checked against gaussian.cl:480-523
//                         `overlay()` + :536-573 `shadows_highlights_mix`):
//                         invert+desaturate the blur, white-point, the
//                         highlights/shadows overlay loops (>1 strength
//                         applies the chunk twice), chroma factor, and the
//                         Lab → Rec2020 return.
//
// dt QUIRKS transliterated verbatim (inert at the default flags = 127 but
// pinned for XMP fidelity):
//   - shadhi.c:462 — the SHADOWS loop clamps `la` under the UNBOUND_
//     HIGHLIGHTS_L bit (highlight bits in the shadow loop);
//   - shadhi.c:486 — the shadow b-channel clamp uses max_B (== max_A
//     numerically, 1.0).
//
// L006: float32 only. L008: endEncoding precedes commit (dispatch helpers).
// ─────────────────────────────────────────────────────────────────────────

// dt UNBOUND_* flag bits (shadhi.c:43-51).
constant uint SH_UNBOUND_SHADOWS_L  = 1u;
constant uint SH_UNBOUND_SHADOWS_A  = 2u;
constant uint SH_UNBOUND_SHADOWS_B  = 4u;
constant uint SH_UNBOUND_HIGHLIGHTS_L = 8u;
constant uint SH_UNBOUND_HIGHLIGHTS_A = 16u;
constant uint SH_UNBOUND_HIGHLIGHTS_B = 32u;

struct ShadhiMixUniforms {
    float shadows;            // ±2 (2 × clamped strength, shadhi.c:356)
    float highlights;         // ±2 (shadhi.c:357)
    float compress;           // [0, 0.99] (shadhi.c:359)
    float whitepoint;         // ≥ 0.01 (shadhi.c:358)
    float shadowsCCorrect;    // shadhi.c:361-362 (sign-folded)
    float highlightsCCorrect; // shadhi.c:363-364 (sign-folded)
    float lowApproximation;   // shadhi.c:368
    int unboundMask;          // shadhi.c:366-367 (gaussian & UNBOUND_GAUSSIAN)
    uint flags;               // raw dt flags word
    float radius;             // clamped radius — sigma = radius × roi.scale
                              // (derived at process time; unused in-kernel,
                              // kept for Swift/MSL layout parity)
};

inline float sh_sign(const float x) {
    return x < 0.0f ? -1.0f : 1.0f;
}

// One overlay loop pass group (shadhi.c:428-454 highlights / :460-487
// shadows; gaussian.cl:480-523 `overlay()`). `strength2` is opacity², the
// while-loop applies strength-weighted CHUNKS (>1 strength runs twice).
inline void sh_overlay(
    thread float3 &ta,
    const float3 tb,
    const float opacity,
    const float xform,
    const float ccorrect,
    const uint laBit,
    const uint outLBit,
    const uint outABit,
    const uint outBBit,
    const int unbound,
    const float lowApproximation,
    const uint flags)
{
    const float lmin = 0.0f;
    const float lmax = 1.0f;
    const float halfmax = 0.5f;
    const float doublemax = 2.0f;

    float strength2 = opacity * opacity;
    while (strength2 > 0.0f) {
        const float la = (flags & laBit) ? ta.x : clamp(ta.x, lmin, lmax);
        float lb = (tb.x - halfmax) * sh_sign(opacity) * sh_sign(lmax - la) + halfmax;
        lb = (unbound != 0) ? lb : clamp(lb, lmin, lmax);
        const float lref = copysign(
            fabs(la) > lowApproximation ? 1.0f / fabs(la) : 1.0f / lowApproximation, la);
        const float href = copysign(
            fabs(1.0f - la) > lowApproximation ? 1.0f / fabs(1.0f - la) : 1.0f / lowApproximation,
            1.0f - la);

        const float chunk = strength2 > 1.0f ? 1.0f : strength2;
        const float optrans = chunk * xform;
        strength2 -= 1.0f;

        ta.x = la * (1.0f - optrans)
            + (la > halfmax
                   ? lmax - (lmax - doublemax * (la - halfmax)) * (lmax - lb)
                   : doublemax * la * lb)
                  * optrans;
        ta.x = (flags & outLBit) ? ta.x : clamp(ta.x, lmin, lmax);

        const float chromaFactor = ta.x * lref * ccorrect + (1.0f - ta.x) * href * (1.0f - ccorrect);
        ta.y = ta.y * (1.0f - optrans) + (ta.y + tb.y) * chromaFactor * optrans;
        ta.y = (flags & outABit) ? ta.y : clamp(ta.y, -1.0f, 1.0f);

        ta.z = ta.z * (1.0f - optrans) + (ta.z + tb.z) * chromaFactor * optrans;
        ta.z = (flags & outBBit) ? ta.z : clamp(ta.z, -1.0f, 1.0f);
    }
}

// Step 1 — Rec2020 → raw Lab (L 0..100, a/b ±128; alpha carried for the
// 4-channel blur exactly as dt blurs the 4c Lab buffer).
kernel void shadhi_prep(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float4 px = in.read(gid);
    const float3 lab = la_rec2020_to_lab(px.rgb);
    out.write(float4(lab, px.a), gid);
}

// Step 3 — the overlay mix (see the pipeline comment).
kernel void shadhi_mix(
    texture2d<float, access::read>  in   [[texture(0)]],
    texture2d<float, access::read>  mask [[texture(1)]],
    texture2d<float, access::write> out  [[texture(2)]],
    constant ShadhiMixUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float4 io = in.read(gid);
    const float4 m4 = mask.read(gid);

    // ta: original Lab scaled (shadhi.c:414 _Lab_scale)
    const float3 lab = la_rec2020_to_lab(io.rgb);
    float3 ta = float3(lab.x / 100.0f, lab.y / 128.0f, lab.z / 128.0f);

    // tb: blurred, inverted, desaturated (shadhi.c:416-419), scaled —
    // the a/b channels are zeroed by dt's desaturation step.
    float3 tb = float3((100.0f - m4.x) / 100.0f, 0.0f, 0.0f);

    // white point adjustment (shadhi.c:421-422)
    ta.x = ta.x > 0.0f ? ta.x / u.whitepoint : ta.x;
    tb.x = tb.x > 0.0f ? tb.x / u.whitepoint : tb.x;

    // overlay highlights (shadhi.c:424-454): opacity = −highlights,
    // ccorrect = 1 − highlights_ccorrect (the CL call form,
    // gaussian.cl:565 — algebraically identical to the CPU chroma factor).
    const float highlightsXform = clamp(1.0f - tb.x / (1.0f - u.compress), 0.0f, 1.0f);
    sh_overlay(
        ta, tb, -u.highlights, highlightsXform, 1.0f - u.highlightsCCorrect,
        SH_UNBOUND_HIGHLIGHTS_L, SH_UNBOUND_HIGHLIGHTS_L,
        SH_UNBOUND_HIGHLIGHTS_A, SH_UNBOUND_HIGHLIGHTS_B,
        u.unboundMask, u.lowApproximation, u.flags);

    // overlay shadows (shadhi.c:456-487): opacity = shadows,
    // ccorrect = shadows_ccorrect; la clamp under the HIGHLIGHTS_L bit —
    // the dt source quirk (shadhi.c:462), transliterated.
    const float shadowsXform = clamp(
        tb.x / (1.0f - u.compress) - u.compress / (1.0f - u.compress), 0.0f, 1.0f);
    sh_overlay(
        ta, tb, u.shadows, shadowsXform, u.shadowsCCorrect,
        SH_UNBOUND_HIGHLIGHTS_L, SH_UNBOUND_SHADOWS_L,
        SH_UNBOUND_SHADOWS_A, SH_UNBOUND_SHADOWS_B,
        u.unboundMask, u.lowApproximation, u.flags);

    // rescale (shadhi.c:489 _Lab_rescale) and back to the working space
    const float3 outLab = float3(ta.x * 100.0f, ta.y * 128.0f, ta.z * 128.0f);
    out.write(float4(la_lab_to_rec2020(outLab), io.a), gid);
}
