// ─────────────────────────────────────────────────────────────────────────
// ColorWheels.metal (Plan M2-5-1 T6, KD-6) — the LGG three-wheel op
// (primary_grade behavior 11), applied on the ACEScc texels:
//   gammaLeg = max(gamma.color + gamma.luma, 1e-4)          (per channel)
//   out      = sign(c) · |c + lift.color + lift.luma|^(1/gammaLeg)
//              · gain.color                                  (per channel)
// The runtime packing (Alcedo adjustment_runtime.cpp behavior-11) carries
// ONLY colorOffset + luminanceOffset — the trackball's disc/strength are
// UI state and do not reach the pixels. gain.luminanceOffset is packed by
// Alcedo but UNUSED by the kernel (faithful). Identity
// (lift 0 / gamma (1,1,1) / gain (1,1,1)) takes the CPU's early-exit flag
// for a byte-identical copy.
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
using namespace metal;

struct ColorWheelsUniforms {
    float flag;       // 0 = identity early exit, 1 = apply
    float liftX; float liftY; float liftZ;
    float liftLuma;
    float gammaX; float gammaY; float gammaZ;
    float gammaLuma;
    float gainX; float gainY; float gainZ;
    float gainLuma;   // packed, unused (the Alcedo kernel ignores it)
    float pad0;
};

kernel void grade_color_wheels(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    constant ColorWheelsUniforms&     u   [[buffer(0)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flag < 0.5f) {
        out.write(c, gid);
        return;
    }
    const float gammaLegX = max(u.gammaX + u.gammaLuma, 1.0e-4f);
    const float gammaLegY = max(u.gammaY + u.gammaLuma, 1.0e-4f);
    const float gammaLegZ = max(u.gammaZ + u.gammaLuma, 1.0e-4f);
    float3 r;
    r.x = copysign(
        precise::pow(abs(c.x + u.liftX + u.liftLuma), 1.0f / gammaLegX), c.x) * u.gainX;
    r.y = copysign(
        precise::pow(abs(c.y + u.liftY + u.liftLuma), 1.0f / gammaLegY), c.y) * u.gainY;
    r.z = copysign(
        precise::pow(abs(c.z + u.liftZ + u.liftLuma), 1.0f / gammaLegZ), c.z) * u.gainZ;
    out.write(float4(r, c.a), gid);
}
