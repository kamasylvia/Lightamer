#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// Colisa iop kernel (Plan 03-03-T2) — port of Darktable's
// `basic.cl:3553 colisa` with the Lab domain conversion FUSED in
// (dt's pixelpipe hands the module Lab pixels; Lightamer's working space
// is linear Rec2020, so the shared LabMath.h conversion brackets the
// operation — Plan 03-03 Goal, RESEARCH Open#3).
//
// LUT semantics = dt CPU process (colisa.c:167-171) + CL kernel
// (CLK_FILTER_NEAREST, common.h:23): NEAREST truncation
// `lut[min(uint(x*0x10000), 0xffff)]` below 1.0, power-law extrapolation
// above (dt_iop_eval_exp). The ctable/ltable device buffers carry
// float32 tables built by ColisaModule.commitParams (dt colisa.c:190-234
// verbatim; brightness gamma per the SOURCE — see the module header's
// recorded deviation).
//
// L006: float32 only. L008: endEncoding precedes commit (dispatch2DTexture).

struct ColisaUniforms {
    float saturation;
    float c0, c1, c2; // contrast extrapolation fit (dt_iop_estimate_exp)
    float l0, l1, l2; // brightness extrapolation fit
};

inline float colisa_lookup(
    device const float* lut, const float x, const float a0,
    const float a1, const float a2)
{
    if (x < 1.0f) {
        // Rounded index (see module header deviation #2): dt truncates,
        // but neutral pixels sit EXACTLY on truncation boundaries
        // (a=0 → a_in=0.5 → 32768.0) where the float32 chroma noise
        // flips the index ±1; rounding makes the index stable.
        const uint idx = min((uint)max(x * 65536.0f + 0.5f, 0.0f), 65535u);
        return lut[idx];
    }
    return a1 * powr(x * a0, a2);
}

kernel void colisa_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float*             ctable [[buffer(0)]],
    device const float*             ltable [[buffer(1)]],
    constant ColisaUniforms&        u      [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    const float3 lab = la_rec2020_to_lab(px.rgb);

    // contrast on L (x = L/100), then brightness on the RESULT (colisa.c
    // process :167-171 — the second lookup evaluates the FIRST's output).
    const float x = lab.x / 100.0f;
    float L = colisa_lookup(ctable, x, u.c0, u.c1, u.c2);
    const float xn = L / 100.0f;
    L = colisa_lookup(ltable, xn, u.l0, u.l1, u.l2);

    // saturation scales a/b directly (colisa.c:172-173; gain = p + 1).
    const float3 outlab = float3(L, lab.y * u.saturation, lab.z * u.saturation);
    out.write(float4(la_lab_to_rec2020(outlab), px.a), gid);
}
