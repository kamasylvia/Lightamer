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
// UNIFORMS (all scalars — no vector/matrix packing ambiguity between
// MSL and Swift; `hinv` is dt row-major `float[3][3]`, `math.h` order):
//   hinv[9]  — row-major inverse 3×3 (Double on CPU, float here)
//   oroiX/Y  — roiOut.xy (the output window origin in the full frame)
//   clipX/Y  — the cl/ct clip offset in output pixels (dt `:3668-3669`)
//   iroiX/Y  — roiIn.xy (the input window origin in the input frame)
//   inW/H    — input plane dims (bounds for the outside test)
//
// SAMPLING (04-03-DECISIONS D4 — Intentional divergence from dt's
// interpolation dispatch, pinned by the Swift↔Python synthesized pair):
// sample centers use texel-center convention (c + 0.5): a center inside
// [0, w) × [0, h) samples with clamped-to-edge taps (dt edge pixels are
// replicated by its border handling); a center outside writes
// (0,0,0,0) — linear Rec2020 black + alpha 0, the pipe's FIRST
// alpha-carrying semantic (FOUND-02 premultiplied; downstream gamma/blit
// pass it through — AshiftParityTests nails the bgra8 black-corner leg).
//
// L006: float32 math only on the sampling path.
// L018: no read_write textures, no in-place passes — pure per-pixel read.

struct AshiftWarpUniforms {
    float hinv[9];
    int oroiX;
    int oroiY;
    float clipX;
    float clipY;
    int iroiX;
    int iroiY;
    int inW;
    int inH;
};

static inline float4 ashift_sample_clamped(
    texture2d<float, access::read> inTex,
    float sx, float sy)
{
    const int w = int(inTex.get_width());
    const int h = int(inTex.get_height());
    const float fx = clamp(sx - 0.5f, 0.0f, float(w - 1));
    const float fy = clamp(sy - 0.5f, 0.0f, float(h - 1));
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
    const float ox = float(int(gid.x) + u.oroiX) + u.clipX;
    const float oy = float(int(gid.y) + u.oroiY) + u.clipY;

    // Inverse homography, dt row-major (math.h `mat3mulv` order) +
    // homogeneous divide (dt `:3550-3554`).
    const float x = u.hinv[0] * ox + u.hinv[1] * oy + u.hinv[2];
    const float y = u.hinv[3] * ox + u.hinv[4] * oy + u.hinv[5];
    const float w = u.hinv[6] * ox + u.hinv[7] * oy + u.hinv[8];
    const float ix = x / w;
    const float iy = y / w;

    // Input-plane coords (dt `:3555-3558`: × scale − roi_in.xy;
    // scale folds to 1 — both ROIs share the run scale, Homography.swift).
    const float sx = ix - float(u.iroiX);
    const float sy = iy - float(u.iroiY);

    // Outside (texel-center convention) → transparent black.
    if (sx < -0.5f || sy < -0.5f
        || sx >= float(u.inW) - 0.5f || sy >= float(u.inH) - 0.5f) {
        out.write(float4(0.0f, 0.0f, 0.0f, 0.0f), gid);
        return;
    }
    out.write(ashift_sample_clamped(in, sx, sy), gid);
}
