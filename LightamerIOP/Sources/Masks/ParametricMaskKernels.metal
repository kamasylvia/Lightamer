#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// Parametric (blendif) mask kernels (Plan 06-04 T1/T2; IOP-MASK-02).
//
// SOURCE: darktable data/kernels/blendop.cl —
//   `mask_blendif`     = `blendop_mask_rgb_jzczhz` (blendop.cl:1096-1131)
//                        + `blendif_factor_rgb_jzczhz` (:329-408) — the
//                        SINGLE-KERNEL decision D-06-CONTEXT-3: the body
//                        covers the gray/luma family (profile luminance
//                        row) AND the JzCzhz family; the channel bitmask
//                        decides participation. Domain-agnostic.
//   `mask_tone_curve`  = `blendop_mask_tone_curve` (blendop.cl:1309-1449)
//                        — the contrast/brightness mask post op.
//
// The mask planes are r32Float; the RED channel is the PREMULTIPLIED
// effective opacity (the 06-02 composite contract D-06-02-T5-3).
//
// Jz CHAIN — SAME-SOURCE constants (BlendOpKernels.metal / JzAzBz.swift /
// ColorBalanceRGBMath): Rec2020 D65 → XYZ + dt's Jz matrices. The working
// space is linear Rec2020, so rgb_to_JzCzhz's profile leg IS JZ_RGB2XYZ
// (dt rgb_matrix_to_xyz with matrix_out = the D65 work-profile matrix).
// The MSL statics are per-file, hence the duplicated block (drift is
// caught by ParametricMaskParityTests, which pins this kernel against the
// float64 chain in JzAzBz.swift).
// ─────────────────────────────────────────────────────────────────────────

constant float3x3 PM_JZ_RGB2XYZ = float3x3(
    float3(0.636958, 0.144617, 0.168881),
    float3(0.262700, 0.678009, 0.059291),
    float3(0.000000, 0.028073, 1.060806));   // rows = matrix rows

static float3 pm_matvec(float3x3 m, float3 v) {
    return float3(dot(m[0], v), dot(m[1], v), dot(m[2], v));
}

static float3 pm_xyz2jab(float3 xyz) {
    float3 t = float3(1.15f * xyz.x - 0.15f * xyz.z,
                      0.66f * xyz.y + 0.34f * xyz.x,
                      xyz.z);
    const float3x3 M = float3x3(
        float3(0.41478972, 0.579999, 0.0146480),
        float3(-0.2015100, 1.1206490, 0.0531008),
        float3(-0.0166008, 0.264800, 0.6684799));
    float3 lms = pm_matvec(M, t);
    const float n = 0.159301758f, p = 134.034375f;
    const float c1 = 0.8359375f, c2 = 18.8515625f, c3 = 18.6875f;
    for (uint i = 0u; i < 3u; ++i) {
        float x = powr(max(lms[i] / 10000.0f, 0.0f), n);
        lms[i] = powr((c1 + c2 * x) / (1.0f + c3 * x), p);
    }
    const float3x3 A = float3x3(
        float3(0.5, 0.5, 0.0),
        float3(3.524000, -4.066708, 0.542708),
        float3(0.199076, 1.096799, -1.295875));
    float3 jab = pm_matvec(A, lms);
    const float d = -0.56f, d0 = 1.6295499532821566e-11f;
    jab.x = fmax(((1.0f + d) * jab.x) / (1.0f + d * jab.x) - d0, 0.0f);
    return jab;
}

// Linear Rec2020 → JzCzhz (hz in [0,1) turns; dt_JzAzBz_2_JzCzhz shape).
static float3 pm_rgb2jch(float3 rgb) {
    float3 jab = pm_xyz2jab(pm_matvec(PM_JZ_RGB2XYZ, rgb));
    float h = atan2(jab.z, jab.y) / (2.0f * M_PI_F);
    if (h < 0.0f) h += 1.0f;
    return float3(jab.x, sqrt(jab.y * jab.y + jab.z * jab.z), h);
}

// dt blend.h:120-172 (the RGB_SCENE slot numbering) + :176 RGB_MASK.
constant uint PM_BLENDIF_GRAY_in  = 0u;
constant uint PM_BLENDIF_RED_in   = 1u;
constant uint PM_BLENDIF_GREEN_in = 2u;
constant uint PM_BLENDIF_BLUE_in  = 3u;
constant uint PM_BLENDIF_GRAY_out = 4u;
constant uint PM_BLENDIF_RED_out  = 5u;
constant uint PM_BLENDIF_GREEN_out= 6u;
constant uint PM_BLENDIF_BLUE_out = 7u;
constant uint PM_BLENDIF_Jz_in    = 8u;
constant uint PM_BLENDIF_Cz_in    = 9u;
constant uint PM_BLENDIF_hz_in    = 10u;
constant uint PM_BLENDIF_Jz_out   = 12u;
constant uint PM_BLENDIF_Cz_out   = 13u;
constant uint PM_BLENDIF_hz_out   = 14u;
constant uint PM_BLENDIF_MAX      = 14u;
constant uint PM_BLENDIF_RGB_MASK = 0x77FFu;

// DEVELOP_COMBINE flags (blend.h:77-88).
constant uint PM_COMBINE_INV  = 0x01u;
constant uint PM_COMBINE_INCL = 0x02u;

// The uniform block (the Swift mirror `MaskBlendifFlags` is the byte
// contract — 48 bytes, every member a 4-byte scalar; tests pin it).
struct MaskBlendifFlags {
    uint blendif;       // enabled (low 16) | inverted (high 16)
    uint combineFlags;  // PM_COMBINE_INV / PM_COMBINE_INCL
    uint hasForm;       // 1 = mask_in carries the drawn/form plane
    uint rowEnd;        // write band end (whole plane = UINT_MAX)
    float gopacity;     // the CLIP'd layer opacity ceiling
    float spare0;
    float spare1;
    float spare2;
};

// The inline trapezoid of `blendif_factor_rgb_jzczhz` (blendop.cl:386-412)
// — NO inversion inside: the OpenCL body applies the channel invert ONCE
// at the `result *=` line (the CPU `_blendif_compute_factor` folds it
// internally; porting both would double-invert).
static inline float pm_factor(float value, device const float *p) {
    float factor;
    if (value <= p[0]) {
        factor = 0.0f;
    } else if (value < p[1]) {
        factor = (value - p[0]) * p[4];
    } else if (value <= p[2]) {
        factor = 1.0f;
    } else if (value < p[3]) {
        factor = 1.0f - (value - p[2]) * p[5];
    } else {
        factor = 0.0f;
    }
    return factor;
}

// `blendif_factor_rgb_jzczhz` (blendop.cl:329-408) — pointwise body.
static inline float pm_blendif_factor(
    float3 a, float3 b, uint blendif, uint combineFlags,
    device const float *parameters)
{
    float scaled[15];

    // dt get_rgb_matrix_luminance with the work profile = the Rec2020 Y
    // row (the SAME-SOURCE luminance row of PM_JZ_RGB2XYZ).
    const float3 lumaRow = float3(0.262700f, 0.678009f, 0.059291f);
    scaled[PM_BLENDIF_GRAY_in]  = dot(lumaRow, a);
    scaled[PM_BLENDIF_GRAY_out] = dot(lumaRow, b);

    scaled[PM_BLENDIF_RED_in]   = a.x;
    scaled[PM_BLENDIF_GREEN_in] = a.y;
    scaled[PM_BLENDIF_BLUE_in]  = a.z;
    scaled[PM_BLENDIF_RED_out]  = b.x;
    scaled[PM_BLENDIF_GREEN_out]= b.y;
    scaled[PM_BLENDIF_BLUE_out] = b.z;

    if ((blendif & 0x7f00u) != 0u)  // do we need to consider JzCzhz?
    {
        float3 jchIn  = pm_rgb2jch(a);
        float3 jchOut = pm_rgb2jch(b);
        scaled[PM_BLENDIF_Jz_in]  = jchIn.x;
        scaled[PM_BLENDIF_Cz_in]  = jchIn.y;
        scaled[PM_BLENDIF_hz_in]  = jchIn.z;
        scaled[PM_BLENDIF_Jz_out] = jchOut.x;
        scaled[PM_BLENDIF_Cz_out] = jchOut.y;
        scaled[PM_BLENDIF_hz_out] = jchOut.z;
    }

    const uint invert_mask =
        (blendif >> 16u) ^ ((combineFlags & PM_COMBINE_INCL) ? PM_BLENDIF_RGB_MASK : 0u);

    float result = 1.0f;
    for (uint ch = 0u; ch <= PM_BLENDIF_MAX; ch++) {
        if ((PM_BLENDIF_RGB_MASK & (1u << ch)) == 0u) continue; // skip unused slots
        float factor;
        if ((blendif & (1u << ch)) == 0u) {
            factor = 1.0f;                       // sliders span the range
        } else if (result <= 0.000001f) {
            break;                               // already at zero
        } else {
            factor = pm_factor(scaled[ch], parameters + 6u * ch);
        }
        result *= (invert_mask & (1u << ch)) ? 1.0f - factor : factor;
    }

    return (combineFlags & PM_COMBINE_INCL) ? 1.0f - result : result;
}

// The parametric mask kernel — `blendop_mask_rgb_jzczhz` transcribed.
// in_a = the below/composite plane (dt's offset leg is not needed: the
// Lightamer composite legs are window-aligned, 06-01), in_b = the layer
// plane, mask_in = the drawn/form plane (hasForm gate), mask = r32Float.
kernel void mask_blendif(
    texture2d<float, access::read>  in_a    [[texture(0)]],
    texture2d<float, access::read>  in_b    [[texture(1)]],
    texture2d<float, access::read>  mask_in [[texture(2)]],
    texture2d<float, access::write> mask    [[texture(3)]],
    constant MaskBlendifFlags      &flags   [[buffer(0)]],
    device const float             *parameters [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= in_a.get_width() || gid.y >= in_a.get_height()) return;
    if (gid.y >= flags.rowEnd) return;

    float4 a = in_a.read(gid);
    float4 b = in_b.read(gid);
    float form = flags.hasForm ? mask_in.read(gid).r : 1.0f;

    float conditional = pm_blendif_factor(
        a.xyz, b.xyz, flags.blendif, flags.combineFlags, parameters);

    float opacity = (flags.combineFlags & PM_COMBINE_INCL)
        ? 1.0f - (1.0f - form) * (1.0f - conditional)
        : form * conditional;
    opacity = (flags.combineFlags & PM_COMBINE_INV) ? 1.0f - opacity : opacity;

    mask.write(float4(flags.gopacity * opacity), gid);
}

// ── The tone-curve mask post op (blendop.cl:1309-1449, verbatim) ──

struct MaskToneCurveUniforms {
    float e;            // exp(3·contrast) — host-computed (dt blend.c:415)
    float brightness;   // −1..1
    float gopacity;     // the mask's premultiplied ceiling
    float rowEnd;       // write band end
};

kernel void mask_tone_curve(
    texture2d<float, access::read>  mask_in  [[texture(0)]],
    texture2d<float, access::write> mask_out [[texture(1)]],
    constant MaskToneCurveUniforms &u        [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= mask_in.get_width() || gid.y >= mask_in.get_height()) return;
    if (gid.y >= u.rowEnd) return;

    const float mask_epsilon = 16.0f * FLT_EPSILON; // dt's transparency gate

    float opacity = mask_in.read(gid).r;
    float scaled_opacity = 2.0f * opacity / u.gopacity - 1.0f;
    if (1.0f - u.brightness <= 0.0f)
        scaled_opacity = opacity <= mask_epsilon ? -1.0f : 1.0f;
    else if (1.0f + u.brightness <= 0.0f)
        scaled_opacity = opacity >= 1.0f - mask_epsilon ? 1.0f : -1.0f;
    else if (u.brightness > 0.0f)
    {
        scaled_opacity = (scaled_opacity + u.brightness) / (1.0f - u.brightness);
        scaled_opacity = fmin(scaled_opacity, 1.0f);
    }
    else
    {
        scaled_opacity = (scaled_opacity + u.brightness) / (1.0f + u.brightness);
        scaled_opacity = fmax(scaled_opacity, -1.0f);
    }
    opacity = 0.5f * (scaled_opacity * u.e / (1.0f + (u.e - 1.0f) * fabs(scaled_opacity))) + 0.5f;
    opacity = clamp(opacity > 1e-6 ? opacity : 0.0f, 0.0f, 1.0f) * u.gopacity;
    mask_out.write(float4(opacity), gid);
}
