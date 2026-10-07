// ─────────────────────────────────────────────────────────────────────────
// WhiteBlack.metal (Plan M2-5-1 T4, KD-5) — the Alcedo `white` and `black`
// endpoint calibrations (primary_grade behaviors 3/4), ONE kernel shape
// per direction (KD-5's "一枚 kernel 双方向" — the endpoint math is a
// channel-uniform scalar ride in the ACEScc grade domain):
//   white: gain   = 1 + max(value, 0) · 0.005   (channels multiplied)
//   black: offset = value · 0.001               (channels shifted)
// Both are exact identities at (or below, for white) 0 — the CPU packs a
// flag and the kernel early-exits for a byte-identical copy. ACEScc
// decode/encode ride ACESccMath.metal (the single constant source).
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
#include "../ACEScc/ACESccMath.metal"
using namespace metal;

struct EndpointUniforms {
    float flag;     // 0 = identity early exit, 1 = apply
    float amount;   // white: the gain; black: the offset
    float pad0;
    float pad1;
};

kernel void grade_white(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    constant EndpointUniforms&        u   [[buffer(0)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flag < 0.5f) {
        out.write(c, gid);
        return;
    }
    out.write(float4(c.x * u.amount, c.y * u.amount, c.z * u.amount, c.a), gid);
}

kernel void grade_black(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    constant EndpointUniforms&        u   [[buffer(0)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flag < 0.5f) {
        out.write(c, gid);
        return;
    }
    out.write(float4(c.x + u.amount, c.y + u.amount, c.z + u.amount, c.a), gid);
}
