#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// skinSmooth kernels — Plan 07-2, AI-05 (op "skinSmooth", v50 slot 66.5 —
// the FIRST Lightamer-native row in the otherwise dt-verbatim table).
//
// NO DARKTABLE COUNTERPART (07-RESEARCH §2: dt has no AI skin-smoothing
// module; `grep -rn "skin" src/iop/` hits only preset/hue weights). The
// math is the classic Photoshop frequency separation, self-synthesized —
// the parity reference is `SkinSmoothReference.swift` (float64), NOT a
// dt-cli golden (L017 route: self-synthesized + identity triple).
//
// PIPELINE (one kernel here; the low band is the SHARED Deriche IIR in
// Common/GaussianBlurKernels.metal, reused verbatim — zero rewrite):
//   low  = gaussian(I, σ)                 [shared kernel]
//   high = I − low                        [below, per channel]
//   out  = low + high·(1 − a·m·g(mag))    [skin_smooth_mix]
//
// THRESHOLD ATTENUATION (D-07-CONTEXT-6, the anti-plastic key): the
// window factor g(mag) is a RAISED-COSINE soft threshold centered on t
// (DECISIONS D-07-2-T2-1 — smooth transition, not a hard |h| ≤ t cut:
// a hard step bands at the segmentation boundary):
//   mag = max(|high_R|, |high_G|, |high_B|)   shared across channels —
//                                             per-channel windows would
//                                             shift hue mid-transition
//   g(mag): mag ≤ t·(1−w) → 1 (attenuate zone — blemishes/noise)
//           mag ≥ t·(1+w) → 0 (preserve zone — pores/hair/contours)
//           between: 0.5·(1+cos(π·(mag−t(1−w))/(2wt)))
//
// t = 0 degenerates cleanly: lo = hi = 0 ⇒ mag ≥ hi ⇒ g = 0 ⇒ out = in
// (full detail preservation — no division: the cosine branch is only
// reachable when t > 0).
//
// MASK SEAM: `mask` (texture 2) is the OPTIONAL direct-drive skin plane
// (single-channel, r ≈ [0,1]). Absent ⇒ m ≡ 1 — bit-identical to an
// all-ones texture (identity triple #2). The PIPE never binds it
// (production spatial limiting = the layer mask at the blendop — Phase 6
// model unchanged); parity tests + the future base-chain API drive it.
// Mask samples at the OUTPUT gid (the direct-drive plane is output-sized).
//
// DOMAIN: linear Rec2020 RGB, per-channel split, attenuation on amplitude
// only (SoftenModule same-domain precedent). UNBOUNDED low leg — clamping
// would corrupt high = I − low.
//
// L006: float32 only. L008: endEncoding precedes commit (dispatch helpers).
// ─────────────────────────────────────────────────────────────────────────

struct SkinSmoothMixUniforms {
    float strength;     // a ∈ [0,1]
    float threshold;    // t (linear Rec2020 |high| amplitude)
    float softness;     // w — transition half-width ratio (0.25)
    int hasMask;        // 1 = texture(2) bound
    int2 srcOffset;     // roiOut.xy − roiIn.xy (0 under tiling)
};

kernel void skin_smooth_mix(
    texture2d<float, access::read>  in   [[texture(0)]],
    texture2d<float, access::read>  low  [[texture(1)]],
    texture2d<float, access::read>  mask [[texture(2)]],
    texture2d<float, access::write> out  [[texture(3)]],
    constant SkinSmoothMixUniforms &u    [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint2 src = uint2(int2(gid) + u.srcOffset);
    const float4 orig = in.read(src);
    const float4 lowpx = low.read(src);

    // The split (per channel, independent).
    const float3 high = orig.rgb - lowpx.rgb;

    // Shared-amplitude soft window (anti-plastic threshold).
    const float mag = max(max(fabs(high.r), fabs(high.g)), fabs(high.b));
    const float lo = u.threshold * (1.0f - u.softness);
    const float hi = u.threshold * (1.0f + u.softness);
    float g;
    if (mag <= lo) {
        g = 1.0f;
    } else if (mag >= hi) {
        g = 0.0f;
    } else {
        g = 0.5f * (1.0f + cos(M_PI_F * (mag - lo) / (2.0f * u.softness * u.threshold)));
    }

    // The mask seam: absent ⇒ m ≡ 1 (identity triple #2 — bit-identical
    // to an all-ones texture; the uniform gate picks the branch).
    const float m = (u.hasMask != 0) ? mask.read(gid).r : 1.0f;

    out.write(float4(lowpx.rgb + high * (1.0f - u.strength * m * g), orig.a), gid);
}
