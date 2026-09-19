#include <metal_stdlib>
using namespace metal;

// Exposure iop kernel (Phase 3 Plan 03-01, IOP-TONE-01).
//
// Verbatim port of Darktable's `basic.cl:240-251` exposure kernel (tree
// dc58cf0ba1): `out = (in − black) × scale` per pixel, uniform two floats.
// The CPU side derives scale = 1 / (exp2(−EV) − black) (exposure.c:479-521,
// mirrored in ExposureModule.commitParams — see that file's header for the
// four recorded dt divergences).
//
// L006: float32 math only — scene-linear domain, half precision would band
// deep shadows. Alpha passes through untouched.

struct ExposureUniforms {
    float black;
    float scale;
};

kernel void exposure_apply(
    texture2d<float, access::read>    in     [[texture(0)]],
    texture2d<float, access::write>   out    [[texture(1)]],
    constant ExposureUniforms&        u      [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    out.write(float4((px.rgb - u.black) * u.scale, px.a), gid);
}
