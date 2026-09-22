#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// ColorZones iop kernel (Plan 05-04-T2) — port of Darktable's
// `basic.cl:3131-3185 colorzones_v3` with the Lab domain conversion FUSED
// in (Plan 03-03 Goal: dt's pixelpipe hands the module Lab pixels;
// Lightamer's working space is linear Rec2020, so LabMath.h brackets the
// operation).
//
// Per-pixel (colorzones.c process_v3 :526-570):
//   h = fmod(atan2(b,a) + 2π, 2π)/2π; C = hypot(b,a)
//   select = L/100 | C/128 | h (by channel); hue mode adds the low-
//     saturation blend = (1 − C/128)²
//   Lm = (blend·0.5 + (1−blend)·LUT_L(select)) − 0.5
//   hm = (blend·0.5 + (1−blend)·LUT_H(select)) − 0.5; blend² for C
//   Cm = 2·LUT_C(select)
//   L' = L·2^(4·Lm); a'/b' = Cm·C rotated by (h + hm).
//
// LUT LOOKUP (module header divergence): dt's CPU leg LERPs adjacent
// entries; dt's CL leg — and this kernel — use NEAREST truncation
// (color_conversion.h:70-75). The dual gate's envelope absorbs the gap.
//
// L006 float32. MSL has no fmod(float,float) overload issue — fmod() is
// used directly; atan2(y,x) matches dt's atan2f(b,a) argument order.

struct ColorZonesUniforms {
    int channel; // 0 L / 1 C / 2 h (dt raw values)
    int pad0;
    float pad1;
    float pad2;
};

inline float cz_lookup(device const float* lut, const float x) {
    // dt CL lookup (color_conversion.h:70-75): truncation, clamped.
    const uint xi = min((uint)max(x * 65536.0f, 0.0f), 65535u);
    return lut[xi];
}

kernel void colorzones_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float*             tableL [[buffer(0)]],
    device const float*             tableC [[buffer(1)]],
    device const float*             tableH [[buffer(2)]],
    constant ColorZonesUniforms&    u [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    float3 lab = la_rec2020_to_lab(px.xyz);
    float a = lab.y, b = lab.z;
    float h = fmod(atan2(b, a) + 6.283185307179586f, 6.283185307179586f) / 6.283185307179586f;
    float C = length(float2(a, b));

    float select = 0.0f;
    float blend = 0.0f;
    if (u.channel == 0) {
        select = min(1.0f, lab.x / 100.0f);
    } else if (u.channel == 1) {
        select = min(1.0f, C / 128.0f);
    } else {
        select = h;
        blend = (1.0f - C / 128.0f) * (1.0f - C / 128.0f);
    }

    float Lm = (blend * 0.5f + (1.0f - blend) * cz_lookup(tableL, select)) - 0.5f;
    float hm = (blend * 0.5f + (1.0f - blend) * cz_lookup(tableH, select)) - 0.5f;
    blend *= blend;
    float Cm = 2.0f * cz_lookup(tableC, select);
    float L = lab.x * pow(2.0f, 4.0f * Lm);
    float ang = 6.283185307179586f * (h + hm);
    float3 outLab = float3(L, cos(ang) * Cm * C, sin(ang) * Cm * C);
    float3 rgb = la_lab_to_rec2020(outLab);
    out.write(float4(rgb, px.w), gid);
}
