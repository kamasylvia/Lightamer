#include <metal_stdlib>
using namespace metal;

// Velvia iop kernel (Plan 05-04-T1) — port of Darktable's
// `extended.cl velvia` verbatim (itself the CL spelling of
// velvia.c:162-197). RGB linear domain; NO colorspace conversion.
//
// Per-channel output (velvia.c:190-193 — the trailing clamp is the
// FORMULA, reproduced exactly; see the module header):
//   pmax/pmin/plum → psat (HSL saturation formula, 1e-5 guard)
//   → pweight (low-saturation + black/white ends weighting, bias controls
//      the mid-tone bias) → saturation = strength·pweight
//   → out[c] = clamp(c + saturation·(c − 0.5·othersum), 0, 1)
// where othersum[c] = the sum of the OTHER two channels. Alpha passes
// through untouched. L006 float32.
//
// strength arrives pre-scaled (/100 — velvia.c:213); bias verbatim.

struct VelviaUniforms {
    float strength;
    float bias;
    float pad0;
    float pad1;
};

kernel void velvia_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant VelviaUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);

    // dt velvia.c:160 — strength <= 0 short-circuits to an unclamped copy
    // (the trailing clamp below is the FORMULA at strength > 0; clamping
    // HDR >1 inputs at neutral/strength-0 would diverge from dt). 05-04
    // acceptance finding #4.
    if (u.strength <= 0.0f) {
        out.write(px, gid);
        return;
    }

    float pmax = max(px.x, max(px.y, px.z));
    float pmin = min(px.x, min(px.y, px.z));
    float plum = (pmax + pmin) / 2.0f;
    float psat = (plum <= 0.5f) ? (pmax - pmin) / (1e-5f + pmax + pmin)
                                : (pmax - pmin) / (1e-5f + max(0.0f, 2.0f - pmax - pmin));

    float pweight = clamp(((1.0f - (1.5f * psat))
                           + ((1.0f + (fabs(plum - 0.5f) * 2.0f)) * (1.0f - u.bias)))
                              / (1.0f + (1.0f - u.bias)),
                          0.0f, 1.0f);
    float saturation = u.strength * pweight;

    float3 rgb = float3(
        clamp(px.x + saturation * (px.x - 0.5f * (px.y + px.z)), 0.0f, 1.0f),
        clamp(px.y + saturation * (px.y - 0.5f * (px.z + px.x)), 0.0f, 1.0f),
        clamp(px.z + saturation * (px.z - 0.5f * (px.x + px.y)), 0.0f, 1.0f));
    out.write(float4(rgb, px.w), gid);
}
