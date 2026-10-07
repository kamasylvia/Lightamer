#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// Vignette kernel — Plan 08-2 T1 (op "vignette", v50 slot 68.0).
//
// Darktable reference (tree dc58cf0ba1):
//   - `data/kernels/extended.cl:308-349` — the PORT MASTER. The OpenCL
//     form is taken VERBATIM: the cosine weight smoothing is UNCONDITIONAL
//     (extended.cl:332). dt's CPU leg only applies the cosine inside the
//     dither branch (vignette.c:790-795) — an internal dt CPU/OpenCL
//     divergence; research §17.3 rules we follow the OpenCL shape (the
//     smoothing has no downside and dithering is NOT ported at all —
//     D-08-CONTEXT-5 ③: an 8-bit-output-domain patch; the float32 chain
//     has the dither iop as the terminal-domain owner of that job).
//   - `src/iop/vignette.c:719-786` — the CPU-side scale setup that feeds
//     the uniforms (xscale/yscale, roi_center_scaled, exp1/exp2, dscale,
//     fscale). The module computes those in Swift (see VignetteModule
//     .uniforms) — the kernel is the per-pixel leg only.
//
// Math (per pixel):
//   pv    = |gid·(xscale,yscale) − roi_center_scaled|   (cplen power
//          distance, shape exponent exp1 = 2/shape, exp2 = shape/2)
//   cplen = pow(pow(pv.x, exp1) + pow(pv.y, exp1), exp2)
//   weight: cplen ≥ dscale → (cplen−dscale)/fscale, then the cosine
//          smoothing 0.5 − cos(π·w)/2 on (0,1), clamped at both ends.
//   brightness < 0 → multiplicative: rgb·(1 + weight·brightness)
//   brightness ≥ 0 → additive:      rgb + weight·brightness
//   unbound==0 → clamp [0,1] (after brightness AND after saturation)
//   saturation: mv = mean(rgb); rgb −= (mv − rgb)·weight·saturation
//          (negative saturation desaturates toward the mean — the dt
//          sign convention verbatim).
//
// HDR NOTE: unbound defaults TRUE → the vignette NEVER clamps; values
// beyond 1.0 keep flowing down the scene-referred pipe (the bloom/veto
// zero-special-casing discipline of this plan, vignette flavor).
//
// L006: float32 only. dt CL guard `if(x >= width || y >= height) return;`
// kept verbatim (dispatchThreads rounds the grid up to threadgroup
// multiples — overshoot threads must exit).
// ─────────────────────────────────────────────────────────────────────────

struct VignetteUniforms {
    float xscale;
    float yscale;
    float roiCenterScaledX;
    float roiCenterScaledY;
    float exp1;          // 2 / shape
    float exp2;          // shape / 2
    float dscale;        // scale / 100 (fall-off start)
    float fscale;        // max(falloff_scale, min_falloff) / 100
    float brightness;    // [-1, 1]
    float saturation;    // [-1, 1]
    float unbound;       // 1.0 = no clamping
    float pad0;
};

kernel void vignette_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant VignetteUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;

    // extended.cl:326 — abs distance from the vignette center, per axis,
    // in the normalized (largest-dimension-fraction) domain.
    const float2 pv = fabs((float2)(gid) * float2(u.xscale, u.yscale)
                           - float2(u.roiCenterScaledX, u.roiCenterScaledY));

    // extended.cl:328 — the cplen power distance (shape exponent).
    const float cplen = pow(pow(pv.x, u.exp1) + pow(pv.y, u.exp1), u.exp2);

    // extended.cl:330-337 — the falloff weight; the cosine smoothing is
    // UNCONDITIONAL (the OpenCL form — see the header note). No dither.
    float weight = 0.0f;
    if (cplen >= u.dscale) {
        weight = ((cplen - u.dscale) / u.fscale);
        weight = weight >= 1.0f ? 1.0f
               : (weight <= 0.0f ? 0.0f : 0.5f - cos(M_PI_F * weight) / 2.0f);
    }

    const float4 pixel = in.read(gid);

    if (weight > 0.0f) {
        float3 rgb = pixel.xyz;
        // brightness leg — the ± branch fork (vignette.c:799-806).
        const float falloff = u.brightness < 0.0f
            ? (1.0f + (weight * u.brightness))
            : (weight * u.brightness);
        rgb = u.brightness < 0.0f ? rgb * falloff : rgb + falloff;
        if (u.unbound < 0.5f) rgb = clamp(rgb, 0.0f, 1.0f);

        // saturation leg — mean-desaturation (vignette.c:809-815).
        const float mv = (rgb.x + rgb.y + rgb.z) / 3.0f;
        const float wss = weight * u.saturation;
        rgb = rgb - (float3(mv) - rgb) * wss;
        if (u.unbound < 0.5f) rgb = clamp(rgb, 0.0f, 1.0f);

        out.write(float4(rgb, pixel.w), gid);
        return;
    }

    out.write(pixel, gid);
}
