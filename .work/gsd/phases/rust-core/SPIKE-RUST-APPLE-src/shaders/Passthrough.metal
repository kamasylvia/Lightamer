#include <metal_stdlib>
using namespace metal;

// Phase 1 success criterion #2 — the trivial pass-through kernel proving the
// MetalContext dispatch end-to-end (FOUND-06).
//
// D-17: function-constants fold branches into PSO variants. NOTE: no MSL
// defaults are declared — Swift MUST set both constants via
// MetalContext.makeConstants/setConstant before specializing (RESEARCH §3
// gotcha: makeFunction(name:constantValues:) requires ALL constants).
//
// L006: float/float3 math only — no half on shadow-sensitive paths.
constant bool useSrgbGamma [[function_constant(0)]];
constant float exposureEV  [[function_constant(1)]];

kernel void pass_through(
    texture2d<float, access::read>    in     [[texture(0)]],
    texture2d<float, access::write>   out    [[texture(1)]],
    uint2 gid                                 [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (useSrgbGamma) { c = float4(pow(c.rgb, float3(1.0/2.2)), c.a); }
    c.rgb *= pow(2.0, exposureEV);
    out.write(c, gid);
}
