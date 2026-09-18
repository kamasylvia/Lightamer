#include <metal_stdlib>
using namespace metal;

// Editor viewport blit (Phase 1, D-13 display-only).
//
// One fullscreen triangle, aspect-fit letterboxed by per-draw uniforms.
// TWO source regimes since Plan 02-04 (terminal trio):
// - `display_ready == false` (function constant, index 0): the Phase 1
//   path — source is a float32 LINEAR Rec2020 texture (WorkingSpace /
//   FOUND-02, produced by Core's CIContextPool) and this shader performs
//   the interim Rec2020→sRGB conversion inline.
// - `display_ready == true`: source is the pixelpipe's gamma-tail
//   `.bgra8Unorm` plane (colorout gamut matrix + gamma sRGB TRC already
//   applied IN the pipe — SC#1's correct color). The blit is a pure
//   passthrough; performing the Phase 1 conversion again would double-
//   encode. Swift builds one PSO per regime and selects on
//   `texture.pixelFormat`.
//
// The drawable stays `.bgra8Unorm` (non-_srgb; D-COL4); the CAMetalLayer
// carries the resolved display colorspace so the compositor interprets
// the gamma-encoded bytes without re-matching.
//
// L006: full float math throughout — no half on the shadow-sensitive path.

struct BlitUniforms {
    float2 scale;   // aspect-fit scale, NDC space
    float2 offset;  // centering offset (0 for Phase 1)
};

struct BlitOut {
    float4 position [[position]];
    float2 uv;
};

vertex BlitOut editor_blit_vertex(
    uint vid [[vertex_id]],
    constant BlitUniforms &uniforms [[buffer(0)]])
{
    float2 quad[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 ndc = quad[vid] * uniforms.scale + uniforms.offset;
    BlitOut out;
    out.position = float4(ndc, 0.0, 1.0);
    // Orientation chain (verified by .work/01-03/smoke against the fixture):
    // CIContext renders the image BOTTOM-UP (texture row 0 = image bottom,
    // CI's lower-left origin), while the drawable's row 0 displays at the
    // TOP of the view. uv.y is therefore flipped so the image shows upright.
    out.uv = float2(ndc.x * 0.5 + 0.5, 1.0 - (ndc.y * 0.5 + 0.5));
    return out;
}

// D-17: no MSL default — Swift sets the constant for BOTH specializations.
constant bool display_ready [[function_constant(0)]];

fragment float4 editor_blit_fragment(
    BlitOut in [[stage_in]],
    texture2d<float> source [[texture(0)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 c = source.sample(s, in.uv);

    if (display_ready) {
        // 02-04 terminal trio output: gamut + TRC applied in the pipe.
        return float4(c.rgb, 1.0);
    }

    // Legacy Phase 1 path: Linear Rec.2020 → linear Rec.709/sRGB primaries.
    float3 rgb = float3(
        1.6605f * c.r - 0.5876f * c.g - 0.0728f * c.b,
       -0.1246f * c.r + 1.1329f * c.g - 0.0083f * c.b,
       -0.0182f * c.r - 0.1006f * c.g + 1.1187f * c.b);
    rgb = clamp(rgb, 0.0f, 1.0f);

    // Linear → sRGB transfer function (piecewise, per IEC 61966-2-1).
    float3 srgb = select(12.92f * rgb, 1.055f * pow(rgb, 1.0f / 2.4f) - 0.055f, rgb > 0.0031308f);
    return float4(srgb, 1.0);
}
