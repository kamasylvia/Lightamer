// ─────────────────────────────────────────────────────────────────────────
// Tint.metal (Plan M2-5-1 T5, KD-5) — the Alcedo `tint` op (primary_grade
// behavior 14): an independent ±100 scalar, a gentle luma-pivot chroma
// scale on the ACEScc texels:
//   scale = 1 + value · 0.0025;  c = luma + (c − luma) · scale
// (deliberately SEPARATE from the CAT02 WB's embedded tint — the catalog
// carries both, 照抄目录). Value 0 takes the CPU's early-exit flag
// (byte-identical copy, pixel tolerance 0).
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
using namespace metal;

struct TintUniforms {
    float flag;      // 0 = identity early exit, 1 = apply
    float scale;     // 1 + value · 0.0025
    float pad0;
    float pad1;
};

static inline float tint_luma(float3 c) {
    return 0.272229f * c.x + 0.674082f * c.y + 0.053689f * c.z;
}

kernel void grade_tint(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    constant TintUniforms&            u   [[buffer(0)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flag < 0.5f) {
        out.write(c, gid);
        return;
    }
    const float l = tint_luma(c.rgb);
    out.write(float4(
        l + (c.x - l) * u.scale,
        l + (c.y - l) * u.scale,
        l + (c.z - l) * u.scale, c.a), gid);
}
