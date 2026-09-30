// ─────────────────────────────────────────────────────────────────────────
// Hls.metal (Plan M2-5-1 T7, KD-7) — the Alcedo `hls` 8-bin selective
// color op (primary_grade behavior 8, ApplyHls — read-only semantics):
//   hue/chroma from the ACEScc texel (HSV-style); chroma <= 1e-6 → copy;
//   per-bin weight = 2^(-d²/w²)  (d = circular hue distance to the bin
//                                center; w = max(h_range_table[i], 1))
//   adj = the weight-normalized average of the bin rows;
//   all |adj| <= 1e-6 → copy (the default table is the exact identity);
//   hue rotation = adj_h·2.25° (YIQ chroma rotation),
//   chroma scale = 2^(adj_s·2.25·(adj_s ≥ 0 ? 4.5 : 3.25)),
//   luma        += adj_l·1.125 (AP1 luma weights).
// NOTE: the window is a GAUSSIAN in hue distance — the plan's
// raised-cosine guess loses to the source (KD-7's 以 Alcedo 为准; signed
// in M2-5-1-DECISIONS).
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
using namespace metal;

constant float kHlsLumaR = 0.272229f;
constant float kHlsLumaG = 0.674082f;
constant float kHlsLumaB = 0.053689f;

struct HlsUniforms {
    float flag;          // 0 = all-zero table (byte-identical copy)
    float values[48];    // [0..7] hue bins, [8..31] adj rows, [32..39] ranges
    float pad0; float pad1; float pad2;
};

static inline float hls_luma(float3 c) {
    return kHlsLumaR * c.x + kHlsLumaG * c.y + kHlsLumaB * c.z;
}

kernel void grade_hls(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    constant HlsUniforms&             u   [[buffer(0)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flag < 0.5f) {
        out.write(c, gid);
        return;
    }
    float3 rgb = c.rgb;
    const float maximum = max(rgb.x, max(rgb.y, rgb.z));
    const float minimum = min(rgb.x, min(rgb.y, rgb.z));
    const float chroma = maximum - minimum;
    if (chroma <= 1.0e-6f) {
        out.write(c, gid);
        return;
    }
    float hue;
    if (maximum == rgb.x) {
        hue = 60.0f * fmod((rgb.y - rgb.z) / chroma, 6.0f);
    } else if (maximum == rgb.y) {
        hue = 60.0f * ((rgb.z - rgb.x) / chroma + 2.0f);
    } else {
        hue = 60.0f * ((rgb.x - rgb.y) / chroma + 4.0f);
    }
    if (hue < 0.0f) {
        hue += 360.0f;
    }
    float sumH = 0.0f, sumL = 0.0f, sumS = 0.0f, sumWeight = 0.0f;
    for (int i = 0; i < 8; ++i) {
        const float difference = abs(hue - u.values[i]);
        const float distance = min(difference, 360.0f - difference);
        const float width = max(u.values[32 + i], 1.0f);
        const float weight = exp2(-distance * distance / (width * width));
        sumH += u.values[8 + i * 3] * weight;
        sumL += u.values[8 + i * 3 + 1] * weight;
        sumS += u.values[8 + i * 3 + 2] * weight;
        sumWeight += weight;
    }
    if (sumWeight <= 1.0e-6f) {
        out.write(c, gid);
        return;
    }
    const float invWeight = 1.0f / sumWeight;
    const float adjH = sumH * invWeight;
    const float adjL = sumL * invWeight;
    const float adjS = sumS * invWeight;
    if (abs(adjH) <= 1.0e-6f && abs(adjL) <= 1.0e-6f && abs(adjS) <= 1.0e-6f) {
        out.write(c, gid);
        return;
    }
    const float angle = adjH * 2.25f * 0.017453292519943295f;
    const float scale = exp2(adjS * 2.25f * (adjS >= 0.0f ? 4.5f : 3.25f));
    const float luma = hls_luma(rgb) + adjL * 1.125f;
    const float iComp = 0.596f * rgb.x - 0.274f * rgb.y - 0.322f * rgb.z;
    const float qComp = 0.211f * rgb.x - 0.523f * rgb.y + 0.312f * rgb.z;
    const float rotatedI = (iComp * cos(angle) - qComp * sin(angle)) * scale;
    const float rotatedQ = (iComp * sin(angle) + qComp * cos(angle)) * scale;
    out.write(float4(
        luma + 0.956f * rotatedI + 0.621f * rotatedQ,
        luma - 0.272f * rotatedI - 0.647f * rotatedQ,
        luma - 1.106f * rotatedI + 1.703f * rotatedQ, c.a), gid);
}
