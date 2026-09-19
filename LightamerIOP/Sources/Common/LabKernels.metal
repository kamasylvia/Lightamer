#include <metal_stdlib>
#include "LabMath.h"
using namespace metal;

// Lab round-trip kernels (Plan 03-03-T1) — the standalone full-plane
// forward/inverse passes over the shared LabMath.h conversion.
//
// Purpose: (1) the LabRoundTripTests GPU leg pins the Metal float32
// conversion against the CPU Double reference (known vectors + round-trip
// identity); (2) the track-B dual criterion renders the default chain with
// a Lab forward+inverse pair inserted (identity in, output unchanged
// within float32 rounding). The production Lab iops (colisa/tonecurve/
// levels/shadhi) fuse the same inline functions into their single-pass
// kernels instead of paying two extra full-plane passes.
//
// L006: float32 only. L008: dispatch2DTexture endEncoding-before-commit.

kernel void lab_roundtrip_forward(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    float3 lab = la_rec2020_to_lab(px.rgb);
    out.write(float4(lab, px.a), gid);
}

kernel void lab_roundtrip_inverse(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    float3 rgb = la_lab_to_rec2020(px.rgb);
    out.write(float4(rgb, px.a), gid);
}
