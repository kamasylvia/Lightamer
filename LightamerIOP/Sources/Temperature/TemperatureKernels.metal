#include <metal_stdlib>
using namespace metal;

// Temperature iop kernel (Phase 3 Plan 03-02, IOP-TONE-02).
//
// Verbatim port of Darktable's `basic.cl:229-239 whitebalance_4f` kernel
// (tree dc58cf0ba1): `out = rgb × coeffs[3]` per pixel, alpha untouched.
// The CPU side clamps gains to the dt widget domain [0, 8] and uploads
// them as uniforms (TemperatureModule.commitParams — see that file's
// header for the five recorded dt divergences; the Rec2020-native
// Kelvin→gains conversion is CPU-side and never reaches the kernel).
//
// L006: float32 math only — scene-linear domain, half precision would
// band deep shadows. L008: dispatch2DTexture endEncoding-precedes-commit.

struct TemperatureUniforms {
    float red;
    float green;
    float blue;
};

kernel void temperature_apply(
    texture2d<float, access::read>    in     [[texture(0)]],
    texture2d<float, access::write>   out    [[texture(1)]],
    constant TemperatureUniforms&     u      [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    out.write(float4(px.rgb * float3(u.red, u.green, u.blue), px.a), gid);
}
