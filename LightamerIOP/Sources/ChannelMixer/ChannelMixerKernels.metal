#include <metal_stdlib>
using namespace metal;

// ChannelMixer legacy iop kernel (Plan 05-03-T3) — port of Darktable's
// `data/kernels/extended.cl:140 channelmixer` verbatim (4-mode switch),
// with dt's colorspace.h RGB_2_HSL/HSL_2_RGB inlined (colorspaces.h
// rgb2hsl/hsl2rgb — the CL spellings; CPU Double mirrors live on
// ChannelMixerModule for parity).
//
// Mode-dependent output clamps reproduce the C/CL divergence exactly:
// v1 RGB leg clamps [0,1]; v2/gray/RGB legs clamp [0,∞) (header #2).
// v1 HSL mix clamps only the first product per row; v2 clamps the full
// dot (header #3). L006 float32.

struct ChannelMixerUniforms {
    float hsl[9];
    float rgb[9];
    float mode;
    float pad;
};

inline float cm_clip(float x) { return clamp(x, 0.0f, 1.0f); }

inline float3 cm_rgb_to_hsl(float3 rgb) {
    float pmax = max(rgb.x, max(rgb.y, rgb.z));
    float pmin = min(rgb.x, min(rgb.y, rgb.z));
    float delta = pmax - pmin;
    float h = 0.0f, s = 0.0f;
    float l = (pmin + pmax) / 2.0f;
    if (delta != 0.0f) {
        s = (l < 0.5f) ? delta / max(pmax + pmin, 1.52587890625e-05f)
                       : delta / max(2.0f - pmax - pmin, 1.52587890625e-05f);
        if (pmax == rgb.x) h = (rgb.y - rgb.z) / delta;
        else if (pmax == rgb.y) h = 2.0f + (rgb.z - rgb.x) / delta;
        else h = 4.0f + (rgb.x - rgb.y) / delta;
        h /= 6.0f;
        if (h < 0.0f) h += 1.0f;
        else if (h > 1.0f) h -= 1.0f;
    }
    return float3(h, s, l);
}

inline float cm_hue_to_rgb(float m1, float m2, float hue) {
    if (hue < 1.0f) return m1 + (m2 - m1) * hue;
    else if (hue < 3.0f) return m2;
    else return (hue < 4.0f) ? m1 + (m2 - m1) * (4.0f - hue) : m1;
}

inline float3 cm_hsl_to_rgb(float3 hsl) {
    if (hsl.y == 0.0f) return float3(hsl.z);
    float m2 = (hsl.z < 0.5f) ? hsl.z * (1.0f + hsl.y)
                              : hsl.z + hsl.y - hsl.z * hsl.y;
    float m1 = 2.0f * hsl.z - m2;
    float h = hsl.x * 6.0f;
    return float3(
        cm_hue_to_rgb(m1, m2, h < 4.0f ? h + 2.0f : h - 4.0f),
        cm_hue_to_rgb(m1, m2, h),
        cm_hue_to_rgb(m1, m2, h > 2.0f ? h - 2.0f : h + 4.0f));
}

kernel void channelmixer_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ChannelMixerUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 pixel = in.read(gid);
    float4 opixel = float4(0.0f, 0.0f, 0.0f, pixel.w);
    int mode = (int)u.mode;

    if (mode == 0) {
        // OPERATION_MODE_RGB (extended.cl RGB leg): fmax(·,0).
        opixel.x = max(pixel.x * u.rgb[0] + pixel.y * u.rgb[1] + pixel.z * u.rgb[2], 0.0f);
        opixel.y = max(pixel.x * u.rgb[3] + pixel.y * u.rgb[4] + pixel.z * u.rgb[5], 0.0f);
        opixel.z = max(pixel.x * u.rgb[6] + pixel.y * u.rgb[7] + pixel.z * u.rgb[8], 0.0f);
    } else if (mode == 1) {
        // OPERATION_MODE_GRAY.
        float g = max(pixel.x * u.rgb[0] + pixel.y * u.rgb[1] + pixel.z * u.rgb[2], 0.0f);
        opixel = float4(g, g, g, pixel.w);
    } else if (mode == 2) {
        // OPERATION_MODE_HSL_V1: first-product-only clamp + clipf RGB out.
        float hmix = cm_clip(pixel.x * u.hsl[0]) + pixel.y * u.hsl[1] + pixel.z * u.hsl[2];
        float smix = cm_clip(pixel.x * u.hsl[3]) + pixel.y * u.hsl[4] + pixel.z * u.hsl[5];
        float lmix = cm_clip(pixel.x * u.hsl[6]) + pixel.y * u.hsl[7] + pixel.z * u.hsl[8];
        float3 rgb = pixel.xyz;
        if (hmix != 0.0f || smix != 0.0f || lmix != 0.0f) {
            float3 hsl = cm_rgb_to_hsl(pixel.xyz);
            hsl.x = (hmix != 0.0f) ? hmix : hsl.x;
            hsl.y = (smix != 0.0f) ? smix : hsl.y;
            hsl.z = (lmix != 0.0f) ? lmix : hsl.z;
            rgb = cm_hsl_to_rgb(hsl);
        }
        opixel.x = cm_clip(rgb.x * u.rgb[0] + rgb.y * u.rgb[1] + rgb.z * u.rgb[2]);
        opixel.y = cm_clip(rgb.x * u.rgb[3] + rgb.y * u.rgb[4] + rgb.z * u.rgb[5]);
        opixel.z = cm_clip(rgb.x * u.rgb[6] + rgb.y * u.rgb[7] + rgb.z * u.rgb[8]);
    } else {
        // OPERATION_MODE_HSL_V2: full-dot clamp + fmax RGB out.
        float hmix = cm_clip(pixel.x * u.hsl[0] + pixel.y * u.hsl[1] + pixel.z * u.hsl[2]);
        float smix = cm_clip(pixel.x * u.hsl[3] + pixel.y * u.hsl[4] + pixel.z * u.hsl[5]);
        float lmix = cm_clip(pixel.x * u.hsl[6] + pixel.y * u.hsl[7] + pixel.z * u.hsl[8]);
        float3 rgb = pixel.xyz;
        if (hmix != 0.0f || smix != 0.0f || lmix != 0.0f) {
            rgb = clamp(rgb, 0.0f, 1.0f);
            float3 hsl = cm_rgb_to_hsl(rgb);
            hsl.x = (hmix != 0.0f) ? hmix : hsl.x;
            hsl.y = (smix != 0.0f) ? smix : hsl.y;
            hsl.z = (lmix != 0.0f) ? lmix : hsl.z;
            rgb = cm_hsl_to_rgb(hsl);
        }
        opixel.x = max(rgb.x * u.rgb[0] + rgb.y * u.rgb[1] + rgb.z * u.rgb[2], 0.0f);
        opixel.y = max(rgb.x * u.rgb[3] + rgb.y * u.rgb[4] + rgb.z * u.rgb[5], 0.0f);
        opixel.z = max(rgb.x * u.rgb[6] + rgb.y * u.rgb[7] + rgb.z * u.rgb[8], 0.0f);
    }
    out.write(opixel, gid);
}
