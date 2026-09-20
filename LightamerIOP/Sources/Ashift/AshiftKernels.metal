#include <metal_stdlib>
using namespace metal;

// ashift warp kernel (Plan 04-03-T2, IOP-GEO-02).
//
// Backward single-homography warp shared by rotation AND perspective
// (dt `process_cl:3659-3703` bilinear leg, tree dc58cf0ba1): per OUTPUT
// pixel `gid`, re-base into the full-output frame (`oroi + clip`),
// apply the INVERSE homography, re-base into the input plane
// (`− iroi`), and bilinear-sample.
//
// The re-basing IS the frame convention (L020): the pipe hands
// roi-sized planes rendered origin-to-origin, so the planes themselves
// carry no offsets — all geometry lives in these uniform scalars
// (the crop double-offset postmortem is why this comment exists).
//
// UNIFORMS (three float4 rows + int2/float2/int2/int2 — every member
// 4/8/16-byte aligned on both sides; the inverse 3×3 rides dt row-major
// `math.h` order in xyz, w pads each row):
//   hrow0/1/2 — inverse matrix rows (Double on CPU, float here)
//   oroi     — roiOut.xy (the output window origin in the full frame)
//   clip     — the cl/ct clip offset in output pixels (dt `:3668-3669`)
//   iroi     — roiIn.xy (the input window origin in the input frame)
//   inSize   — input plane dims (bounds for the outside test)
//
// SAMPLING (04-03-DECISIONS D4 — Intentional divergence from dt's
// interpolation dispatch, pinned by the Swift↔Python synthesized pair):
// coords are PIXEL-CENTER (integer = texel center — dt's interpolation
// convention, so the identity maps integer→integer exactly; a half-texel
// shift here showed up as a 0.5/63 systematic on the ramp neutral gate).
// A coord inside [−0.5, w−0.5) × [−0.5, h−0.5) samples with
// clamped-to-edge taps (dt edge pixels are replicated by its border
// handling); outside writes (0,0,0,0) — linear Rec2020 black + alpha 0,
// the pipe's FIRST alpha-carrying semantic (FOUND-02 premultiplied;
// downstream gamma/blit pass it through — AshiftParityTests pins the
// RGBA leg and testRotatedBlackCornersSurviveGammaTail the bgra8
// display-tail leg).
//
// L006: float32 math only on the sampling path.
// L018: no read_write textures, no in-place passes — pure per-pixel read.

struct AshiftWarpUniforms {
    // Inverse 3×3 as three float4 ROWS (dt row-major `math.h` order in
    // xyz; w pads each row to 16 bytes — the Metal constant layout with
    // zero packing ambiguity, verified against the Swift mirror below).
    float4 hrow0;
    float4 hrow1;
    float4 hrow2;
    int2 oroi;
    float2 clip;
    int2 iroi;
    int2 inSize;
};
static inline float4 ashift_sample_clamped(
    texture2d<float, access::read> inTex,
    float sx, float sy)
{
    // `sx/sy` are PIXEL-CENTER coords (integer = texel center — dt's
    // interpolation convention: identity maps integer→integer exactly).
    const int w = int(inTex.get_width());
    const int h = int(inTex.get_height());
    const float fx = clamp(sx, 0.0f, float(w - 1));
    const float fy = clamp(sy, 0.0f, float(h - 1));
    const int x0 = int(floor(fx));
    const int y0 = int(floor(fy));
    const int x1 = min(x0 + 1, w - 1);
    const int y1 = min(y0 + 1, h - 1);
    const float tx = fx - float(x0);
    const float ty = fy - float(y0);
    const float4 p00 = inTex.read(uint2(uint(x0), uint(y0)));
    const float4 p10 = inTex.read(uint2(uint(x1), uint(y0)));
    const float4 p01 = inTex.read(uint2(uint(x0), uint(y1)));
    const float4 p11 = inTex.read(uint2(uint(x1), uint(y1)));
    const float4 top = mix(p00, p10, tx);
    const float4 bot = mix(p01, p11, tx);
    return mix(top, bot, ty);
}

kernel void ashift_warp(
    texture2d<float, access::read>    in     [[texture(0)]],
    texture2d<float, access::write>   out    [[texture(1)]],
    constant AshiftWarpUniforms&      u      [[buffer(0)]],
    uint2 gid                                        [[thread_position_in_grid]])
{
    // Full-output-frame coords (dt `:3543-3546` + clip `:3668-3669`).
    const float ox = float(int(gid.x) + u.oroi.x) + u.clip.x;
    const float oy = float(int(gid.y) + u.oroi.y) + u.clip.y;

    // Inverse homography, dt row-major (math.h `mat3mulv` order) +
    // homogeneous divide (dt `:3550-3554`).
    const float x = dot(u.hrow0.xyz, float3(ox, oy, 1.0f));
    const float y = dot(u.hrow1.xyz, float3(ox, oy, 1.0f));
    const float w = dot(u.hrow2.xyz, float3(ox, oy, 1.0f));
    const float ix = x / w;
    const float iy = y / w;

    // Input-plane coords (dt `:3555-3558`: × scale − roi_in.xy;
    // scale folds to 1 — both ROIs share the run scale, Homography.swift).
    const float sx = ix - float(u.iroi.x);
    const float sy = iy - float(u.iroi.y);

    // Outside (pixel-center convention) → transparent black.
    if (sx < -0.5f || sy < -0.5f
        || sx >= float(u.inSize.x) - 0.5f || sy >= float(u.inSize.y) - 0.5f) {
        out.write(float4(0.0f, 0.0f, 0.0f, 0.0f), gid);
        return;
    }
    out.write(ashift_sample_clamped(in, sx, sy), gid);
}
