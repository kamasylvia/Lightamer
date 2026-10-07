// ─────────────────────────────────────────────────────────────────────────
// Cat02WB.metal (Plan M2-5-1 T3, KD-4) — the CAT02 creative white balance
// kernel (Alcedo primary_grade behavior 0): ACEScc decode → row-major
// CAT02 adaptation in linear AP1 → ACEScc re-encode. The uniforms carry
// the CPU-resolved adaptation rows (Cat02WBModule.commitParams); flag 0 =
// the identity early exit (the AP1-white default — byte-identical copy).
// Constants ride ACESccMath.metal (the single constant source — red line).
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
#include "../ACEScc/ACESccMath.metal"
using namespace metal;

struct Cat02WBUniforms {
    float flag;     // 0 = identity early exit, 1 = apply the adaptation
    float m00; float m01; float m02;
    float m10; float m11; float m12;
    float m20; float m21; float m22;
    float pad0; float pad1; float pad2;
    float pad3; float pad4; float pad5;
};

kernel void grade_cat02_wb(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    constant Cat02WBUniforms&         u   [[buffer(0)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flag < 0.5f) {
        out.write(c, gid);
        return;
    }
    float3 lin = float3(acescc_decode(c.x), acescc_decode(c.y), acescc_decode(c.z));
    float3 adapted = float3(
        u.m00 * lin.x + u.m01 * lin.y + u.m02 * lin.z,
        u.m10 * lin.x + u.m11 * lin.y + u.m12 * lin.z,
        u.m20 * lin.x + u.m21 * lin.y + u.m22 * lin.z);
    out.write(
        float4(acescc_encode(adapted.x), acescc_encode(adapted.y), acescc_encode(adapted.z), c.a),
        gid);
}
