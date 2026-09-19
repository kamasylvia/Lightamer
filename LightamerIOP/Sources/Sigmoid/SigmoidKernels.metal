#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// sigmoid kernels (Plan 03-04-T4, IOP-FILM-02) — verbatim MSL port of
// data/kernels/sigmoid.cl (tree dc58cf0ba1):
//   - sigmoid_loglogistic_per_channel :172-223
//   - sigmoid_loglogistic_rgb_ratio   :225-297
//   - _generalized_loglogistic_sigmoid (stable form) :91-107
//   - _desaturate_negative_values :82-89
//   - _pixel_channel_order :29-80
//   - _preserve_hue_and_energy :134-174
//
// The three primaries matrices (pipe_to_base / base_to_rendering /
// rendering_to_pipe) are computed on the CPU at commit time
// (SigmoidModule.swift — the dt `_calculate_adjusted_primaries`
// semantics with the matrix-direction chain documented there) and
// packed row-major into ONE device buffer:
//   [0..6]   white_target, black_target, paper_exposure, film_fog,
//            film_power, paper_power, hue_preservation
//   [7..15]  pipe_to_base
//   [16..24] base_to_rendering
//   [25..33] rendering_to_pipe
//
// Scene-referred module: input is linear Rec2020 scene RGB (values may
// exceed 1.0 and go negative — the desaturation step defines negatives).
// D-T2 baseline: this module carries the scene-referred tone-mapping
// golden/panel/cache template for filmicrgb (plan 03-06).
// L006: float32 only.
// ─────────────────────────────────────────────────────────────────────────

// sigmoid.cl:91-107 — stable-at-zero film+paper response.
inline float sg_loglogistic(
    const float value, const float magnitude, const float paper_exp,
    const float film_fog, const float film_power, const float paper_power)
{
    const float clamped_value = fmax(value, 0.0f);
    const float film_response = pow(film_fog + clamped_value, film_power);
    const float paper_response = magnitude * pow(film_response / (paper_exp + film_response), paper_power);
    return isnan(paper_response) ? magnitude : paper_response;
}

inline float3 sg_loglogistic3(
    const float3 v, const float magnitude, const float paper_exp,
    const float film_fog, const float film_power, const float paper_power)
{
    return float3(
        sg_loglogistic(v.x, magnitude, paper_exp, film_fog, film_power, paper_power),
        sg_loglogistic(v.y, magnitude, paper_exp, film_fog, film_power, paper_power),
        sg_loglogistic(v.z, magnitude, paper_exp, film_fog, film_power, paper_power));
}

// sigmoid.cl:82-89.
inline float3 sg_desaturate_negative(const float3 v)
{
    const float pixel_average = fmax((v.x + v.y + v.z) / 3.0f, 0.0f);
    const float min_value = fmin(fmin(v.x, v.y), v.z);
    const float saturation_factor = min_value < 0.0f ? -pixel_average / (min_value - pixel_average) : 1.0f;
    return pixel_average + saturation_factor * (v - pixel_average);
}

// sigmoid.cl:29-80 — returns (min_index, mid_index, max_index) via the
// dt case table verbatim (the equal-channel case keeps mid = 1).
inline int3 sg_pixel_channel_order(const float3 v)
{
    if (v.x >= v.y) {
        if (v.y > v.z) {        // Case 1: r >= g > b
            return int3(2, 1, 0);
        } else if (v.z > v.x) { // Case 2: b > r >= g
            return int3(1, 0, 2);
        } else if (v.z > v.y) { // Case 3: r >= b > g
            return int3(1, 2, 0);
        } else {                // Case 4: r == g == b
            return int3(2, 1, 0);
        }
    } else {
        if (v.x >= v.z) {       // Case 5: g > r >= b
            return int3(2, 0, 1);
        } else if (v.z > v.y) { // Case 6: b > g > r
            return int3(0, 1, 2);
        } else {                // Case 7: g >= b > r
            return int3(0, 2, 1);
        }
    }
}

// sigmoid.cl:134-174 — hue interpolation constrained to the per-channel
// energy. `pix` is modified in place (dt's pix_io).
inline void sg_preserve_hue_and_energy(
    thread float3 &pix,
    const float3 per_channel,
    const int3 order,
    const float hue_preservation)
{
    const int omin = order.x, omid = order.y, omax = order.z;
    const float pixMin = pix[omin], pixMid = pix[omid], pixMax = pix[omax];
    const float perMin = per_channel[omin], perMid = per_channel[omid], perMax = per_channel[omax];

    // Naive hue correction of the middle channel
    const float chroma = pixMax - pixMin;
    const float midscale = chroma != 0.0f ? (pixMid - pixMin) / chroma : 0.0f;
    const float full_hue_correction = perMin + (perMax - perMin) * midscale;
    const float naive_hue_mid = (1.0f - hue_preservation) * perMid + hue_preservation * full_hue_correction;

    const float per_channel_energy = per_channel.x + per_channel.y + per_channel.z;
    const float naive_hue_energy = perMin + naive_hue_mid + perMax;
    const float pix_in_min_plus_mid = pixMin + pixMid;
    const float blend_factor = pix_in_min_plus_mid != 0.0f ? 2.0f * pixMin / pix_in_min_plus_mid : 0.0f;
    const float energy_target = blend_factor * per_channel_energy + (1.0f - blend_factor) * naive_hue_energy;

    if (naive_hue_mid <= perMid) {
        const float corrected_mid =
            ((1.0f - hue_preservation) * perMid
             + hue_preservation
                 * (midscale * perMax + (1.0f - midscale) * (energy_target - perMax)))
            / (1.0f + hue_preservation * (1.0f - midscale));
        pix[omin] = energy_target - perMax - corrected_mid;
        pix[omid] = corrected_mid;
        pix[omax] = perMax;
    } else {
        const float corrected_mid =
            ((1.0f - hue_preservation) * perMid
             + hue_preservation
                 * (perMin * (1.0f - midscale) + midscale * (energy_target - perMin)))
            / (1.0f + hue_preservation * midscale);
        pix[omin] = perMin;
        pix[omid] = corrected_mid;
        pix[omax] = energy_target - perMin - corrected_mid;
    }
}

inline float3 sg_mul9(device const float* m, const float3 v)
{
    return float3(
        m[0] * v.x + m[1] * v.y + m[2] * v.z,
        m[3] * v.x + m[4] * v.y + m[5] * v.z,
        m[6] * v.x + m[7] * v.y + m[8] * v.z);
}

// sigmoid.cl:176-223 — per-channel path with hue+energy preservation and
// the primaries matrices (identity unless inset/rotation/base != work).
kernel void sigmoid_per_channel(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float *u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float white_target = u[0];
    const float paper_exp = u[2];
    const float film_fog = u[3];
    const float film_power = u[4];
    const float paper_power = u[5];
    const float hue_preservation = u[6];

    float4 i = in.read(gid);
    const float alpha = i.w;

    // Convert to "base primaries" (identity when base == work profile).
    i.rgb = sg_mul9(u + 7, i.rgb);

    // Force negative values to zero (dt's desaturation).
    i.rgb = sg_desaturate_negative(i.rgb);

    // Convert to rendering primaries.
    i.rgb = sg_mul9(u + 16, i.rgb);
    float3 pix = i.rgb;
    const float3 per_channel = sg_loglogistic3(
        pix, white_target, paper_exp, film_fog, film_power, paper_power);

    // Hue correction by scaling the middle value relative to max/min.
    const int3 order = sg_pixel_channel_order(pix);
    sg_preserve_hue_and_energy(pix, per_channel, order, hue_preservation);

    const float3 result = sg_mul9(u + 25, pix);
    out.write(float4(result, alpha), gid);
}

// sigmoid.cl:225-297 — luma-driven path with the hyperbolic gamut
// compression toward the display border.
kernel void sigmoid_rgb_ratio(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float *u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float white_target = u[0];
    const float black_target = u[1];
    const float paper_exp = u[2];
    const float film_fog = u[3];
    const float film_power = u[4];
    const float paper_power = u[5];

    float4 i = in.read(gid);
    const float alpha = i.w;

    // Force negative values to zero.
    float3 v = sg_desaturate_negative(i.rgb);

    // Preserve color ratios: curve on a luma estimate, scale uniformly.
    const float luma = (v.x + v.y + v.z) / 3.0f;
    const float mapped_luma = sg_loglogistic(
        luma, white_target, paper_exp, film_fog, film_power, paper_power);

    float3 pre;
    if (luma > 1e-9f) {
        pre = (mapped_luma / luma) * v;
    } else {
        pre = float3(mapped_luma);
    }

    const float pixel_min = fmin(fmin(pre.x, pre.y), pre.z);
    const float pixel_max = fmax(fmax(pre.x, pre.y), pre.z);

    // Chroma relative display gamut and scene "mapping" gamut.
    const float epsilon = 1e-6f;
    // "Distance" to max channel = white_target
    const float display_border_vs_chroma_white =
        (white_target - mapped_luma) / (pixel_max - mapped_luma + epsilon);
    // "Distance" to min channel = black_target
    const float display_border_vs_chroma_black =
        (black_target - mapped_luma) / (pixel_min - mapped_luma - epsilon);
    const float display_border_vs_chroma =
        fmin(display_border_vs_chroma_white, display_border_vs_chroma_black);
    // "Distance" to min channel = 0.0
    const float chroma_vs_mapping_border =
        (mapped_luma - pixel_min) / (mapped_luma + epsilon);

    // Hyperbolic gamut compression: near-neutral colors preserved, large
    // chroma compressed.
    const float pixel_chroma_adjustment =
        1.0f / (chroma_vs_mapping_border * display_border_vs_chroma + epsilon);
    const float hyperbolic_chroma =
        2.0f * chroma_vs_mapping_border
        / (1.0f - chroma_vs_mapping_border * chroma_vs_mapping_border + epsilon)
        * pixel_chroma_adjustment;

    const float hyperbolic_z = sqrt(hyperbolic_chroma * hyperbolic_chroma + 1.0f);
    const float chroma_factor =
        hyperbolic_chroma / (1.0f + hyperbolic_z) * display_border_vs_chroma;

    const float3 result = mapped_luma + chroma_factor * (pre - mapped_luma);
    out.write(float4(result, alpha), gid);
}
