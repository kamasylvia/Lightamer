#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;
// ─────────────────────────────────────────────────────────────────────────
// sharpen (USM) kernels — Plan 04-05-T1, IOP-DETAIL-01 (op "sharpen",
// v50 slot 35.0).
//
// Darktable reference: `src/iop/sharpen.c` (tree dc58cf0ba1) +
// `data/kernels/sharpen.cl:145-160` (`sharpen_mix`):
//   delta = L − blurL
//   out = L + amount·copysign(max(0, |delta| − threshold), delta)
//
// Pipeline (dt's CL leg, sharpen.c:126-231, with the Lab domain fused):
//   1. `sharpen_prep`    Rec2020 → raw Lab (dt's pixelpipe hands the
//                        module IOP_CS_LAB pixels; Lightamer converts
//                        in-kernel — the shared LabMath.h, Plan 03-03-T1).
//   2. GaussianBlur.blur the Deriche IIR over the Lab plane (Common/
//                        GaussianBlur — DIVERGENCE D1, see the module
//                        header: dt blurs with a truncated FIR, we reuse
//                        the shared IIR; the blur is UNBOUNDED —
//                        sharpen.c applies no Lab box to the FIR input).
//   3. `sharpen_mix`     the soft-threshold USM on L, a/b straight
//                        through, Lab → Rec2020 return. Reads re-base by
//                        srcOffset (roiOut − roiIn; 0 under tiling — the
//                        tile driver re-bases itself); dispatches span the
//                        OUTPUT plane (flip precedent — the SWAP_XY lesson:
//                        never assume input/output extents coincide).
//
// BORDER (D12 intentional divergence): dt's CPU leg copies the outer
// `rad` rows/cols through unsharpened (`sharpen.c:295-304,340-341,361` —
// "skip the top/bottom rows, kernel would extend beyond the edge") and
// the CL leg gates the mix on the same rad frame (`sharpen.cl:161`).
// The IIR blur clamps at the edge instead, so blurL ≈ L there and
// delta ≈ 0 — the border self-neutralizes without a branch. The first
// and last `rad` rows/cols are therefore approximate (delta small but
// nonzero), not bit-identical, to dt. Parity pins the interior <1e-4.
//
// L006: float32 only. L008: endEncoding precedes commit (dispatch helpers).
// L018: no read_write textures, no in-place passes — prep/blur/mix are
// three separate planes (the GaussianBlur buffer discipline).
// ─────────────────────────────────────────────────────────────────────────

// Step 1 — Rec2020 → raw Lab (L 0..100, a/b ±128; alpha carried for the
// 4-channel blur exactly as shadhi carries it).
kernel void sharpen_prep(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float4 px = in.read(gid);
    const float3 lab = la_rec2020_to_lab(px.rgb);
    out.write(float4(lab, px.a), gid);
}

struct SharpenMixUniforms {
    float amount;       // dt `sharpen` (d->amount, commit verbatim)
    float threshold;    // dt `thrs` (d->threshold, commit verbatim)
    int2 srcOffset;     // roiOut.xy − roiIn.xy (the sub-window re-base;
                        // 0 under tiling — the tile driver re-bases itself)
};

// Step 3 — the soft-threshold mix (sharpen.cl:165-167 verbatim shape:
// `amount = sharpen·copysign(fmax(0, |delta|−thrs), delta)`; the CPU
// leg's `:356` ternary is the same predicate — `mag > 0` here).
kernel void sharpen_mix(
    texture2d<float, access::read>  in      [[texture(0)]],
    texture2d<float, access::read>  blurred [[texture(1)]],
    texture2d<float, access::write> out     [[texture(2)]],
    constant SharpenMixUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint2 src = uint2(int2(gid) + u.srcOffset);
    const float4 io = in.read(src);
    const float4 b4 = blurred.read(src);

    const float3 lab = la_rec2020_to_lab(io.rgb);
    const float delta = lab.x - b4.x;
    const float mag = fabs(delta) - u.threshold;
    const float detail = (mag > 0.0f) ? copysign(mag, delta) : 0.0f;

    const float3 outLab = float3(lab.x + u.amount * detail, lab.y, lab.z);
    out.write(float4(la_lab_to_rec2020(outLab), io.a), gid);
}
