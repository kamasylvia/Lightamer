#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// Levels iop kernel (Plan 03-03-T4) — port of Darktable's CPU process
// (levels.c:412-434) with the Lab conversion FUSED in. The dt CL kernel
// (basic.cl:3074) differs in the low-L chroma branch; this port follows
// the CPU form (recorded divergence #2 on LevelsModule).
//
// LUT semantics: nearest lookup with the ROUNDED index (deviation #3).
// L006 float32; L008 endEncoding precedes commit.

struct LevelsUniforms {
    float levelBlack;  // levels[0] (normalized)
    float levelRange;  // levels[2] − levels[0]
    float invGamma;    // 10^((l1−mid)/delta)
};

inline float levels_lut_lookup(device const float* lut, const float percentage) {
    const uint idx = min((uint)max(percentage * 65536.0f + 0.5f, 0.0f), 65535u);
    return lut[idx];
}

kernel void levels_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float*             lut [[buffer(0)]],
    constant LevelsUniforms&        u   [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    const float3 lab = la_rec2020_to_lab(px.rgb);

    const float L_in = lab.x / 100.0f;
    float l_out;
    if (L_in <= u.levelBlack) {
        // below the black point clips to zero (levels.c:417-421)
        l_out = 0.0f;
    } else {
        const float percentage = (L_in - u.levelBlack) / u.levelRange;
        if (percentage < 1.0f) {
            l_out = levels_lut_lookup(lut, percentage);
        } else {
            // beyond white the power law continues UNBOUNDED (levels.c:426)
            l_out = 100.0f * powr(percentage, u.invGamma);
        }
    }

    // chroma preservation (CPU form :430-433): a,b × L_out/max(L_in, 0.01)
    const float denom = max(lab.x, 0.01f);
    const float3 outLab = float3(l_out, lab.y * l_out / denom, lab.z * l_out / denom);
    out.write(float4(la_lab_to_rec2020(outLab), px.a), gid);
}
