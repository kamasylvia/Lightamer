#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// Mask combine kernels (Plan 06-04 T3; IOP-MASK-04) — the dt group combine
// formulas transcribed verbatim from masks/group.c:487-630
// (_combine_masks_{union,intersect,difference,sum,exclusion}, each with the
// INVERSE branch — masks.h:52-68 state bits), plus the seed/invert helpers.
//
// Ping-pong contract (L018): `mask_combine_pair` READS dest_in and src,
// WRITES dest_out — the reduce never accumulates in place and never uses a
// read_write texture; the Swift side swaps planes between dispatches.
//
// Op codes follow the dt state-bit order (masks.h:55-64):
//   0 UNION  1 INTERSECTION  2 DIFFERENCE  3 SUM  4 EXCLUSION
// Semantics (group.c:487-630, m = opacity · (inverted ? 1−s : s)):
//   union      dest = max(dest, m)
//   intersect  dest = min(max(dest,0), max(m,0))
//   difference dest = both_positive ? dest·(1−m) : dest
//   sum        dest = min(1, dest + m)
//   exclusion  pos = both_positive; dest = pos·max((1−dest)m, dest(1−m))
//                              + (1−pos)·max(dest, m)
// ─────────────────────────────────────────────────────────────────────────

struct MaskCombineUniforms {
    uint op;        // 0..4 (the order above)
    uint inverted;  // the item's INVERSE state bit
    uint rowEnd;    // write band end (whole plane = UINT_MAX)
    uint _pad;
    float opacity;  // the per-item opacity
    float _p1;
    float _p2;
    float _p3;
};

static inline bool mc_both_positive(float a, float b) {
    return a > 0.0f && b > 0.0f;
}

kernel void mask_combine_pair(
    texture2d<float, access::read>  dest_in  [[texture(0)]],
    texture2d<float, access::read>  src      [[texture(1)]],
    texture2d<float, access::write> dest_out [[texture(2)]],
    constant MaskCombineUniforms   &u        [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dest_in.get_width() || gid.y >= dest_in.get_height()) return;
    if (gid.y >= u.rowEnd) return;

    const float d = dest_in.read(gid).r;
    const float s = src.read(gid).r;
    const float m = u.opacity * (u.inverted ? 1.0f - s : s);
    float o;
    switch (u.op) {
        case 0u:  // UNION
            o = fmax(d, m);
            break;
        case 1u:  // INTERSECTION
            o = fmin(fmax(d, 0.0f), fmax(m, 0.0f));
            break;
        case 2u:  // DIFFERENCE
            o = mc_both_positive(d, m) ? d * (1.0f - m) : d;
            break;
        case 3u:  // SUM
            o = fmin(1.0f, d + m);
            break;
        case 4u:  // EXCLUSION
        default: {
            const float pos = mc_both_positive(d, m) ? 1.0f : 0.0f;
            o = pos * fmax((1.0f - d) * m, d * (1.0f - m)) + (1.0f - pos) * fmax(d, m);
            break;
        }
    }
    dest_out.write(float4(o), gid);
}

// The mask-level invert (dt raster_mask_invert leg, blend.c:567-572).
kernel void mask_invert(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= in.get_width() || gid.y >= in.get_height()) return;
    out.write(float4(1.0f - in.read(gid).r), gid);
}

// The seed plane (dt's zeroed dest buffer — group.c `_group_get_mask_roi`
// allocates a zeroed intermediate). value 0 = the combine seed, 1 = the
// no-form fill (blend.c:612-616).
kernel void mask_fill(
    texture2d<float, access::write> out   [[texture(0)]],
    constant float &value                 [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    out.write(float4(value), gid);
}

// The raster-mask resample (the dt_dev_get_raster_mask per-scale
// regeneration analog, blend.c:552-571): a baked PNG at one resolution
// consumed at a different window resolution — NEAREST gather (a mask is
// a shape field; v1 pins nearest, bilinear is the later upgrade seam).
kernel void mask_resample(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant uint2 &outSize             [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outSize.x || gid.y >= outSize.y) return;
    const uint2 inSize = uint2(in.get_width(), in.get_height());
    // Center-sample mapping: (2·dst+1)/(2·src) — the symmetric nearest.
    const uint sx = min(uint((2.0f * float(gid.x) + 1.0f) * float(inSize.x) / (2.0f * float(outSize.x))), inSize.x - 1u);
    const uint sy = min(uint((2.0f * float(gid.y) + 1.0f) * float(inSize.y) / (2.0f * float(outSize.y))), inSize.y - 1u);
    out.write(float4(in.read(uint2(sx, sy)).r), gid);
}
