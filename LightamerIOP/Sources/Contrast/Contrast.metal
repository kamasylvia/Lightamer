// ─────────────────────────────────────────────────────────────────────────
// Contrast.metal (Plan M2-5-1 T4, KD-5) — the Alcedo `contrast` op
// (primary_grade.metal behavior 2, ApplyOkLabContrast): an S curve on
// OkLab lightness of scene-linear AP1 around the 18%-grey pivot, chroma
// scaled so HUE never drifts:
//   slope       = 2^(contrast/100)
//   shape       = tanh(3 · log2(L / cbrt(0.18)) / 2.5)   (L ≤ 0 → −1)
//   gain        = 2^((slope − 1) · 2.5 · shape / 3)
//   chromaScale = √slope · min(gain, 1)
//   L'a'b'      = (L·gain, a·chromaScale, b·chromaScale)
// precise:: guards keep fast-math from drifting the curve (the Alcedo
// shaders' documented reason). ACEScc decode/encode ride ACESccMath.metal
// (the single constant source — red line). flag 0 = the contrast-0 early
// exit (byte-identical copy, pixel tolerance 0).
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
#include "../ACEScc/ACESccMath.metal"
using namespace metal;

struct ContrastUniforms {
    float flag;      // 0 = identity early exit, 1 = apply the curve
    float contrast;  // ±100
    float pad0;
    float pad1;
};

static inline float3 linear_ap1_to_oklab(float3 c) {
    const float l  = 0.6341104672f * c.x + 0.3489495087f * c.y + 0.0169400240f * c.z;
    const float m  = 0.2754060131f * c.x + 0.6327713632f * c.y + 0.0918226237f * c.z;
    const float s  = 0.1056775254f * c.x + 0.1971481306f * c.y + 0.6971743440f * c.z;
    const float l_ = precise::pow(fabs(l), 1.0f / 3.0f) * sign(l);
    const float m_ = precise::pow(fabs(m), 1.0f / 3.0f) * sign(m);
    const float s_ = precise::pow(fabs(s), 1.0f / 3.0f) * sign(s);
    return float3(
        0.2104542553f * l_ + 0.7936177850f * m_ - 0.0040720468f * s_,
        1.9779984951f * l_ - 2.4285922050f * m_ + 0.4505937099f * s_,
        0.0259040371f * l_ + 0.7827717662f * m_ - 0.8086757660f * s_);
}

static inline float3 oklab_to_linear_ap1(float3 lab) {
    const float l_ = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
    const float m_ = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
    const float s_ = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;
    const float l  = l_ * l_ * l_;
    const float m  = m_ * m_ * m_;
    const float s  = s_ * s_ * s_;
    return float3(
        2.0693822907f * l - 1.1736821545f * m + 0.1042998638f * s,
        -0.8917480677f * l + 2.1537429245f * m - 0.2619948569f * s,
        -0.0615064732f * l - 0.4311325686f * m + 1.4926390418f * s);
}

kernel void grade_contrast(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    constant ContrastUniforms&        u   [[buffer(0)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flag < 0.5f) {
        out.write(c, gid);
        return;
    }
    float3 lin = float3(acescc_decode(c.x), acescc_decode(c.y), acescc_decode(c.z));
    float3 lab = linear_ap1_to_oklab(lin);
    const float slope = precise::exp2(u.contrast * 0.01f);
    const float shape =
        lab.x > 0.0f
        ? precise::tanh(3.0f * precise::log2(lab.x / 0.5646216f) / 2.5f)
        : -1.0f;
    const float gain = precise::exp2((slope - 1.0f) * 2.5f * shape / 3.0f);
    const float chromaScale = precise::sqrt(slope) * min(gain, 1.0f);
    lab = float3(lab.x * gain, lab.y * chromaScale, lab.z * chromaScale);
    float3 adapted = oklab_to_linear_ap1(lab);
    out.write(
        float4(acescc_encode(adapted.x), acescc_encode(adapted.y), acescc_encode(adapted.z), c.a),
        gid);
}
