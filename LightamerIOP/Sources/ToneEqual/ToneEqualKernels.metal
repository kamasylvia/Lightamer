#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// ToneEqualKernels (Plan 03-05-T2/T3/T4) — the tone equalizer GPU graph.
// Darktable has NO OpenCL for this iop (toneequal.c:313 TODO); every kernel
// here is a formula-by-formula transcription of the CPU sources:
//
//   toneeq_luma_estimate   luminance_mask.h:60-200 — the SEVEN estimators
//                          (plan erratum: "9 estimators"; the enum is
//                          DT_TONEEQ_LAST = 7 — the 9 refers to the user
//                          BANDS) + linear_contrast (:52-56) with dt
//                          toneequal.c:132's fulcrum exp2(−4).
//   toneeq_bilinear_1c     fast_guided_filter.h interpolate_bilinear (ch=1).
//   toneeq_quantize        fast_guided_filter.h quantize — log2 posterize.
//   toneeq_pack4           eigf.h eigf_variance_analysis packing:
//                          (guide, guide², mask, guide·mask) into a float4
//                          plane for the 4-channel gaussian.
//   toneeq_box_mean_x/_y   box_filters.cc _blur_horizontal/_blur_vertical
//                          shape (separable, boundary-truncated window —
//                          sums divide by the VALID window size), the
//                          guided leg's box mean. The OpenCL analogue is
//                          guided_filter.cl box_mean_x/y; the CPU box mean
//                          is the parity source (dt toneequal never runs
//                          OpenCL).
//   toneeq_guided_ab       fast_guided_filter.h variance_analyse blend
//                          segment (:238-243): d = max(var+feathering,
//                          1e-15); a = cov/d; b = mean_m − a·mean_g.
//   toneeq_blend           eigf.h eigf_blending[_no_mask] (the EIGF solve+
//                          blend, exposure-weighted variance ratio) and
//                          fast_guided_filter.h apply_linear_blending
//                          [_w_geomean] (the guided a/b apply) — selected
//                          by a uniform mode flag; bilinear av/ab
//                          up-sampling is INLINED here (dt upsamples to a
//                          full plane first, then blends per-pixel with
//                          the same 4-neighbour weights — inline sampling
//                          is point-identical and saves a full float4
//                          plane, the D-C1 tiling rationale).
//   toneeq_apply           toneequal.c:771-803 — LUT gain apply; dt's
//                          `for_each_channel` multiplies ALL FOUR channels
//                          (alpha included) — verbatim quirk, kept for the
//                          golden compare.
//
// METHOD DISPATCH (plan T2 decision, recorded): the luma estimator is a
// UNIFORM branch, not a [[function_constant]] PSO specialization — seven
// method variants would multiply every other PSO dimension against the
// 256-entry LRU budget (METAL-5) for a ~1-cycle predictable branch. The
// PSO budget wins.
//
// PRECISION: float32 throughout (L006 — no half on tone paths). The EIGF
// gaussian leg REUSES Common/GaussianBlur (03-04's dt_gaussian port; the
// Deriche IIR coefficients live there) — eigf.h's blur IS dt_gaussian
// with per-channel data min/max bounds, and dt's CLAMPF applies to the
// INPUT SAMPLES against those bounds (gaussian.c:283+), i.e. it can never
// fire on finite data — the constant (MIN_FLOAT, FLT_MAX) bounds used here
// are point-identical on valid luma planes.
// ─────────────────────────────────────────────────────────────────────────

// exp2(−16) — luminance_mask.h MIN_FLOAT.
#define TE_MIN_FLOAT 1.52587890625e-05f
// dt CONTRAST_FULCRUM (toneequal.c:131).
#define TE_CONTRAST_FULCRUM 0.0625f

struct ToneEqualLumaUniforms {
    int method;           // dt_iop_luminance_mask_method_t raw value
    float exposureBoost;  // d->exposure_boost (exp2 of the EV param)
    float fulcrum;        // 0.0 (unboosted modes) or CONTRAST_FULCRUM
    float contrastBoost;  // 1.0 (unboosted modes) or d->contrast_boost
};

// luminance_mask.h linear_contrast (:52-58).
static inline float te_linear_contrast(float pixel, float fulcrum, float contrast) {
    return max((pixel - fulcrum) * contrast + fulcrum, TE_MIN_FLOAT);
}

kernel void toneeq_luma_estimate(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ToneEqualLumaUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;
    const float4 p = in.read(gid);
    float lum = 0.0f;
    switch (u.method) {
        case 0: { // DT_TONEEQ_MEAN — RGB average
            lum = u.exposureBoost * (p.r + p.g + p.b) / 3.0f;
            break;
        }
        case 1: { // DT_TONEEQ_LIGHTNESS — HSL lightness
            const float mx = max(max(p.r, p.g), p.b);
            const float mn = min(min(p.r, p.g), p.b);
            lum = u.exposureBoost * (mx + mn) / 2.0f;
            break;
        }
        case 2: { // DT_TONEEQ_VALUE — HSV value / RGB max
            lum = u.exposureBoost * max(max(p.r, p.g), p.b);
            break;
        }
        case 3: { // DT_TONEEQ_NORM_1 — RGB sum
            lum = u.exposureBoost * (fabs(p.r) + fabs(p.g) + fabs(p.b));
            break;
        }
        case 4: { // DT_TONEEQ_NORM_2 — RGB euclidean norm (dt default)
            lum = u.exposureBoost * sqrt(p.r * p.r + p.g * p.g + p.b * p.b);
            break;
        }
        case 5: { // DT_TONEEQ_NORM_POWER — the perceptual power norm
            const float ar = fabs(p.r), ag = fabs(p.g), ab = fabs(p.b);
            const float num = ar*ar*ar + ag*ag*ag + ab*ab*ab;
            const float den = ar*ar + ag*ag + ab*ab;
            lum = u.exposureBoost * num / den;
            break;
        }
        case 6: { // DT_TONEEQ_GEOMEAN — geometric mean
            lum = u.exposureBoost * pow(fabs(p.r) * fabs(p.g) * fabs(p.b), 1.0f / 3.0f);
            break;
        }
        default:
            lum = u.exposureBoost * (p.r + p.g + p.b) / 3.0f;
            break;
    }
    const float v = te_linear_contrast(lum, u.fulcrum, u.contrastBoost);
    out.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}
