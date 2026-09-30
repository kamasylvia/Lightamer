// ─────────────────────────────────────────────────────────────────────────
// ACESccConvert.metal (Plan M2-5-1 T2, KD-2) — the two envelope kernels.
// The grade domain's ONLY entry/exit: acesccIn converts the layer sub-run
// input from linear Rec2020 into ACEScc (Rec2020→AP1 matrix + log encode);
// acesccOut converts the graded plane back (log decode + AP1→Rec2020).
// Both are per-pixel ROI-identity operators (dscIn = dscOut — the L021
// layer assertions are untouched by the envelope).
// Constants ride ACESccMath.metal (the single constant source — red line).
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
#include "ACESccMath.metal"
using namespace metal;

kernel void grade_acescc_in(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    float3 ap1 = rec2020_to_ap1(c.rgb);
    out.write(float4(acescc_encode(ap1.x), acescc_encode(ap1.y), acescc_encode(ap1.z), c.a), gid);
}

kernel void grade_acescc_out(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    float3 ap1 = float3(acescc_decode(c.x), acescc_decode(c.y), acescc_decode(c.z));
    out.write(float4(ap1_to_rec2020(ap1), c.a), gid);
}
