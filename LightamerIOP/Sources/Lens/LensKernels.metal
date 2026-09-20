#include <metal_stdlib>
using namespace metal;

// lens correction warp kernel (Plan 04-04-T1, IOP-GEO-03, v50 slot 13.0).
//
// Darktable reference: `src/iop/lens.cc` (tree dc58cf0ba1)
//   - vignette applied BEFORE geometric resampling (`:1194-1206`: the
//     INPUT buffer is devignetted, then the warp samples it) — the fused
//     kernel below evaluates V at the POST-distortion radius, which is
//     algebraically the same order (V(distorted(x)) on the input field).
//   - ROI: `_modify_roi_in_lf` (`:1697-1790`) forward-maps border points
//     through the correct-modifier and takes the 6-coord (RGB) AABB +
//     interpolation margin — the Swift `modifyROIIn` mirrors it without
//     the Newton inverse solve (dt uses the same forward map).
//   - CL sampling leg (`:1214-1270`): per-output-pixel
//     `ApplySubpixelGeometryDistortion` backward coords, taps clamped
//     (`fmaxf/fminf` to roi bounds), NaN → 0.
//
// NORMALIZED-RADIUS CONVENTION (04-04-T0 decision 2 — lensfun GitHub
// `modifier.cpp` header + `mod-coord.cpp` / `mod-color.cpp`
// `rescale_polynomial_coefficients`, nailed 2026-09-20):
// lensfun's internal normalized coords are in units of real focal with
//   NormScale = hypot(36,24)/Crop/hypot(W+1,H+1)/RealFocal.
// Hugin distortion/TCA models (poly3/poly5/ptlens/linear) use r = 1 at
// HALF HEIGHT (landscape half-height; rescale denominator carries
// `hypot(aspect,1)/2`). The vignetting pa model uses r = 1 at the IMAGE
// CORNER (rescale denominator `/2`, no aspect term).
// The Swift resolve layer (LensfunMatch) pre-scales every XML coefficient
// into THIS kernel's radius unit `u = (p − c)/halfW` (halfW = input-plane
// half width, optical center = frame center — see CENTER below), so the
// kernel itself only evaluates one radius polynomial pair:
//   Rd = Ru·(1 + dc1·Ru + dc2·Ru² + dc3·Ru³ + dc4·Ru⁴)   (distortion)
//   polyC = vr + cr·Ru + br·Ru²  (per channel; TCA linear = vr-only)
//   V = 1 / (1 + vk1·Ru² + vk2·Ru⁴ + vk3·Ru⁶)            (devignette)
// The (NS·HW) pre-scale is resolution-free (`21.633/Crop·(HW/diag)/F`),
// so preview/full renders agree with identical params.
//
// MODEL MAPPING (exact, `mod-coord.cpp` / `mod-color.cpp`):
//   poly3  Rd = Ru·(1 + k1·Ru²)            → dc2 = k1'     (d-factor folded)
//   poly5  Rd = Ru·(1 + k1·Ru² + k2·Ru⁴)    → dc2/dc4
//   ptlens Rd = Ru·(a·Ru³ + b·Ru² + c·Ru + 1) → dc3/dc2/dc1 (a'/b'/c')
//   TCA linear  R/B radii × (kr/kb)         → vr=kr, vb=kb
//   TCA poly3   Rd = Ru·(b·Ru² + c·Ru + v)  → (vr,cr,br)/(vb,cb,bb)
//   vig pa      multiplier 1/(1+k1r²+k2r⁴+k3r⁶)
// where primed values carry the d-factor rescale
// (poly3: d = 1−k1, k1' = k1/d³; ptlens: d = 1−a−b−c,
// a' = a/d⁴, b' = b/d³, c' = c/d² — `mod-coord.cpp` header note).
//
// EVALUATION ORDER (D3): distortion D first, then TCA evaluated at the
// POST-distortion radius (lensfun callback chain: distortion 750 → TCA
// 500 in `ApplySubpixelGeometryDistortion`, sequential on one buffer).
// Vignette first (dt `:1194-1206`), at the post-distortion radius.
//
// CENTER: frame center (dscIn/2). The lensfun `<center>` element is
// absent from the shipped v1 subset (and rare upstream); LensfunDB parses
// it when present and the resolve layer folds it into `center` — the
// uniform defaults to the frame center.
//
// BORDER (D4): out-of-domain coords sample with clamped taps (lens edge
// stretch, NOT black corners — cf. ashift's transparent outside). NaN
// (non-convergent Newton upstream / degenerate poly) → (0,0,0,1)? No —
// NaN can only arrive via degenerate uniforms; the module guards those
// to the blit path, so the kernel treats every coord as finite.
//
// ALPHA: rides the sampled pixel untouched (like flip; unlike ashift the
// warp never creates transparent regions).
//
// L006: float32 math only on the sampling path.
// L018: no read_write textures, no in-place passes — pure per-pixel read.

struct LensWarpUniforms {
    float4 dist;    // dc1, dc2, dc3, dc4 (radial distortion coeffs in u units)
    float4 tcaR;    // vr, cr, br, pad (red-channel radius polynomial)
    float4 tcaB;    // vb, cb, bb, pad (blue-channel radius polynomial)
    float4 vig;     // vk1, vk2, vk3, pad (devignette denominator coeffs)
    float2 center;  // optical center in input-plane pixels (frame center default)
    float2 halfW;   // (halfW, halfW) — radius unit; y component pads to 8 bytes
    float2 oroi;    // roiOut.xy (output window origin in the full frame)
    float2 iroi;    // roiIn.xy (input window origin in the input frame)
    int2   inSize;  // input plane dims (bounds for the outside test)
};

static inline float4 lens_sample_clamped(
    texture2d<float, access::read> inTex,
    float sx, float sy)
{
    // Pixel-center bilinear with clamped taps (ashift D4 convention:
    // identity maps integer→integer exactly).
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

kernel void lens_manual_warp(
    texture2d<float, access::read>    in     [[texture(0)]],
    texture2d<float, access::write>   out    [[texture(1)]],
    constant LensWarpUniforms&        u      [[buffer(0)]],
    uint2 gid                                        [[thread_position_in_grid]])
{
    // Output-frame coords re-based into the input plane (L020: planes are
    // origin-to-origin; geometry lives in oroi/iroi).
    const float ox = float(int(gid.x) + int(u.oroi.x));
    const float oy = float(int(gid.y) + int(u.oroi.y));
    const float ix0 = ox - u.iroi.x;
    const float iy0 = oy - u.iroi.y;

    // Normalized radius around the optical center (u units).
    const float dx = ix0 - (u.center.x - u.iroi.x);
    const float dy = iy0 - (u.center.y - u.iroi.y);
    const float ru = length(float2(dx, dy)) / u.halfW.x;

    // Distortion: Rd = Ru·(1 + dc1·Ru + dc2·Ru² + dc3·Ru³ + dc4·Ru⁴).
    const float ru2 = ru * ru;
    const float dpoly = 1.0f + u.dist.x * ru + u.dist.y * ru2
        + u.dist.z * ru2 * ru + u.dist.w * ru2 * ru2;
    const float rd = ru * dpoly;

    // TCA at the post-distortion radius (D3): per-channel radius scale.
    const float rd2 = rd * rd;
    const float sR = u.tcaR.x + u.tcaR.y * rd + u.tcaR.z * rd2;
    const float sB = u.tcaB.x + u.tcaB.y * rd + u.tcaB.z * rd2;
    // Green rides the distortion radius (lensfun leaves G unscaled).

    // Sample coords per channel (center-relative, scaled, re-based).
    const float2 dc = float2(dx, dy);
    const float2 pr = dc * (rd * sR / max(ru, 1e-12f));
    const float2 pg = dc * (rd / max(ru, 1e-12f));
    const float2 pb = dc * (rd * sB / max(ru, 1e-12f));
    const float2 cc = u.center - u.iroi;
    const float srx = cc.x + pr.x, sry = cc.y + pr.y;
    const float sgx = cc.x + pg.x, sgy = cc.y + pg.y;
    const float sbx = cc.x + pb.x, sby = cc.y + pb.y;

    // Devignette at the post-distortion radius (dt :1194-1206 order):
    // multiplier 1/(1 + vk1·rd² + vk2·rd⁴ + vk3·rd⁶).
    const float rd4 = rd2 * rd2;
    const float vpoly = 1.0f + u.vig.x * rd2 + u.vig.y * rd4 + u.vig.z * rd4 * rd2;
    const float vmul = 1.0f / vpoly;

    float4 pr4 = lens_sample_clamped(in, srx, sry);
    float4 pg4 = lens_sample_clamped(in, sgx, sgy);
    float4 pb4 = lens_sample_clamped(in, sbx, sby);
    float4 result = float4(pr4.x * vmul, pg4.y * vmul, pb4.z * vmul, pg4.w);
    out.write(result, gid);
}
