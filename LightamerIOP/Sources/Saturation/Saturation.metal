// ─────────────────────────────────────────────────────────────────────────
// Saturation.metal (Plan M2-5-1 T5, KD-5) — the Alcedo `saturation` op
// (primary_grade behavior 9): multiplicative saturation 0..4 on the ACEScc
// texels themselves, pivoted on the AP1 luma (0.272229/0.674082/0.053689)
// with the peak-raise limiter (a single operation may add less than two
// stops of new log-domain peak — engages only for pathological channel
// separation):
//   scale = value
//   if scale > 1.5 && (peak − luma)·(scale − 1) > 0.1:
//       scale = 1 + 0.1 / max(peak − luma, 1e-6)
//   c = luma + (c − luma) · scale
// scale 1.0 takes the CPU's early-exit flag (byte-identical copy, pixel
// tolerance 0).
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
#include "../ACEScc/ACESccMath.metal"
using namespace metal;

struct SaturationUniforms {
    float flag;       // 0 = identity early exit, 1 = apply
    float scale;      // 0..4
    float pad0;
    float pad1;
};

static inline float grade_luma(float3 c) {
    return 0.272229f * c.x + 0.674082f * c.y + 0.053689f * c.z;
}

kernel void grade_saturation(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    constant SaturationUniforms&      u   [[buffer(0)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flag < 0.5f) {
        out.write(c, gid);
        return;
    }
    float scale = u.scale;
    const float l = grade_luma(c.rgb);
    if (scale > 1.5f) {
        const float peak = max(c.x, max(c.y, c.z));
        const float peakRaise = (peak - l) * (scale - 1.0f);
        if (peakRaise > 0.1f) {
            scale = 1.0f + 0.1f / max(peak - l, 1.0e-6f);
        }
    }
    out.write(float4(
        l + (c.x - l) * scale,
        l + (c.y - l) * scale,
        l + (c.z - l) * scale, c.a), gid);
}
