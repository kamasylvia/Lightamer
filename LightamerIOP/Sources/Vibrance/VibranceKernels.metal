#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// Vibrance iop kernel (Plan 05-04-T1) — port of Darktable's
// `extended.cl vibrance` (itself the CL spelling of vibrance.c:111-127)
// with the Lab domain conversion FUSED in (Plan 03-03 Goal: dt's
// pixelpipe hands the module Lab pixels; Lightamer's working space is
// linear Rec2020, so LabMath.h brackets the operation).
//
//   sw = hypot(a,b)/256; ls = 1 − amt·sw·0.25; ss = 1 + amt·sw
//   out = {L·ls, a·ss, b·ss}
// (amt = amount·0.01 is pre-scaled on the CPU — vibrance.c:111/:142).
// L006 float32.

struct VibranceUniforms {
    float amount;
    float pad0;
    float pad1;
    float pad2;
};

kernel void vibrance_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant VibranceUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    float3 lab = la_rec2020_to_lab(px.xyz);
    float sw = length(lab.yz) / 256.0f;
    float ls = 1.0f - u.amount * sw * 0.25f;
    float ss = 1.0f + u.amount * sw;
    float3 outLab = float3(lab.x * ls, lab.y * ss, lab.z * ss);
    float3 rgb = la_lab_to_rec2020(outLab);
    out.write(float4(rgb, px.w), gid);
}
