#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// ColorContrast iop kernel (Plan 05-03-T3) — port of Darktable's
// `extended.cl colorcontrast` with the Lab domain conversion FUSED in
// (dt's pixelpipe hands the module Lab pixels; Lightamer's working space
// is linear Rec2020, so the shared LabMath.h conversion brackets the
// operation — Plan 03-03 Goal, RESEARCH Open#3).
//
// a' = a·a_steepness + a_offset, b' = b·b_steepness + b_offset
// (colorcontrast.c:189-220); unbound skips the ±128 clamp. L006 float32.

struct ColorContrastUniforms {
    float a_steepness;
    float a_offset;
    float b_steepness;
    float b_offset;
    float unbound;
    float pad0;
    float pad1;
    float pad2;
};

kernel void colorcontrast_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ColorContrastUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    float3 lab = la_rec2020_to_lab(px.xyz);
    float a = lab.y * u.a_steepness + u.a_offset;
    float b = lab.z * u.b_steepness + u.b_offset;
    if (u.unbound == 0.0f) {
        a = clamp(a, -128.0f, 128.0f);
        b = clamp(b, -128.0f, 128.0f);
    }
    float3 outLab = float3(lab.x, a, b);
    float3 rgb = la_lab_to_rec2020(outLab);
    out.write(float4(rgb, px.w), gid);
}
