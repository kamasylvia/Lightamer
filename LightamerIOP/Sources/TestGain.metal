#include <metal_stdlib>
using namespace metal;

// Dev-only SC#2 vehicle (Plan 02-02, DEBUG builds only — TestGainModule is
// #if DEBUG in Swift; this kernel ships in the metallib but nothing
// references it in Release). A one-parameter gain: the demo load for the
// pixelpipe cache tests (change gain -> upstream hit / downstream miss).
//
// Uniform layout: `float gain` at offset 0 (the Swift side uploads a
// 16-byte-padded struct; Metal reads the leading float).
//
// L006: float math only — linear-domain multiply, no half anywhere.
struct TestGainUniforms {
    float gain;
};

kernel void test_gain(
    texture2d<float, access::read>    in     [[texture(0)]],
    texture2d<float, access::write>   out    [[texture(1)]],
    constant TestGainUniforms&        u      [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    out.write(float4(px.rgb * u.gain, px.a), gid);
}

// 04-01 ROI negotiation probe: windowed gain — samples input at the
// output pixel's negotiated coords: in[gid + (roiIn.xy − roiOut.xy)].
// Lets an e2e harness prove a downstream module consumed a negotiated
// window while reusing the same kernel binary as `test_gain`.
struct ROIGainUniforms {
    float gain;
    int2 inOffset;
};

kernel void test_gain_windowed(
    texture2d<float, access::read>    in     [[texture(0)]],
    texture2d<float, access::write>   out    [[texture(1)]],
    constant ROIGainUniforms&         u      [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    float4 px = in.read(gid + uint2(u.inOffset));
    out.write(float4(px.rgb * u.gain, px.a), gid);
}
