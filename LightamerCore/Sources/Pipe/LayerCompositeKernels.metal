#include <metal_stdlib>
using namespace metal;

// Layer-composite kernels (Plan 06-01 T4) — Core's own default.metallib,
// pipeline INFRASTRUCTURE like TerminalKernels.metal (the composite engine
// is the pipe's, not any iop's; 6-2 owns the FULL blendop mode table —
// this file carries only the degenerate-normal pass the 6-1 driver uses).
//
// L006: full float math — no half anywhere.
//
// Formula authority (D-06-CONTEXT-2): the NORMAL2 modern formula,
//   o = a·(1−op) + b·op
// with a = the below-composite plane, b = this layer's output, op = the
// layer opacity in [0,1]. dt blend.c:458 a/b semantics; the legacy clamping
// of the 0x01 slot is NOT applied. REVERSE (blend.h:89) swaps a/b.

struct LayerCompositeUniforms {
    float opacity;
    uint  reverse;   // 0 = a/b as-is, 1 = DEVELOP_BLEND_REVERSE (swap)
    uint  _pad0;
    uint  _pad1;
};

kernel void layer_composite_normal(
    texture2d<float, access::read>  below   [[texture(0)]],
    texture2d<float, access::read>  layerIn [[texture(1)]],
    texture2d<float, access::write> out     [[texture(2)]],
    constant LayerCompositeUniforms& u      [[buffer(0)]],
    uint2 gid                               [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    float4 a = below.read(gid);
    float4 b = layerIn.read(gid);
    float t = (u.reverse != 0u) ? (1.0f - u.opacity) : u.opacity;
    out.write(a * (1.0f - t) + b * t, gid);
}
