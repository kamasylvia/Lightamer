#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// Mask post-processing kernels (Plan 06-04 T2; IOP-MASK-02/03) — the
// single-channel blur/feather legs of dt's mask post chain
// (blend.c:664-720: blur sigma = blur_radius, bounds [0,1]; the tone-curve
// leg lives in ParametricMaskKernels.metal).
//
// STRUCTURE = the GaussianBlur engineering discipline (plan 03-04-T1, the
// L018 red line): a Deriche/Young-van-Vliet RECURSIVE IIR over device
// BUFFER planes, never a read_write texture (the 03-04 finding: the
// backward pass's in-thread read of the forward's write returns ZERO on
// read_write textures on M4/macOS 27), and the row pass reads one plane
// and writes ANOTHER (an in-place row pass feeds the backward filter the
// forward's OUTPUT — the DC-gain collapse measured 03-04):
//   1. mask_blur_col   r32 texture → plane half 0 (one thread per column)
//   2. mask_blur_row   plane 0 → plane 1        (one thread per row)
//   3. mask_blur_store plane 1 → r32 texture
//
// DEVIATION (v1, recorded in 06-04-DECISIONS): dt's feather is a GUIDED
// filter (guided_filter with the image as guide, blend.c:385-405). v1
// ships the plan-directed single-channel Gaussian parameterized by
// featherRadius — the guided-filter leg is a later upgrade seam.
//
// Coefficients come from the SAME-SOURCE derivation as
// GaussianBlur.coeffs (gaussian.c:41-100); the Core-side mirror is pinned
// equal by a test (MaskPostProcessCoeffsPin in ParametricMaskParityTests).
// Input samples clamp to [0,1] at every read (dt gaussian bounds —
// blend.c:708-710 passes mmin=0/mmax=1 for masks).
// ─────────────────────────────────────────────────────────────────────────

struct MaskBlurUniforms {
    float a0, a1, a2, a3, b1, b2, coefp, coefn;
    uint width;
    uint height;
    uint rowEnd;   // write band end (whole plane = UINT_MAX)
    uint _pad;
};

// Pass 1 (columns): one thread per column — forward store + backward
// accumulate into the device plane (gaussian.cl:124-161 float1 shape).
kernel void mask_blur_col(
    texture2d<float, access::read> in   [[texture(0)]],
    device float *plane                 [[buffer(1)]],
    constant MaskBlurUniforms &u        [[buffer(0)]],
    uint gx [[thread_position_in_grid]])
{
    if (gx >= u.width) return;
    const uint height = u.height;

    float xp = clamp(in.read(uint2(gx, 0u)).r, 0.0f, 1.0f);
    float yb = xp * u.coefp;
    float yp = yb;
    for (uint y = 0; y < height; ++y) {
        const float xc = clamp(in.read(uint2(gx, y)).r, 0.0f, 1.0f);
        const float yc = u.a0 * xc + u.a1 * xp - u.b1 * yp - u.b2 * yb;
        xp = xc; yb = yp; yp = yc;
        plane[y * u.width + gx] = yc;
    }

    float xn = clamp(in.read(uint2(gx, height - 1u)).r, 0.0f, 1.0f);
    float xa = xn;
    float yn = xn * u.coefn;
    float ya = yn;
    for (uint k = 0; k < height; ++k) {
        const uint y = height - 1u - k;
        const float xc = clamp(in.read(uint2(gx, y)).r, 0.0f, 1.0f);
        const float yc = u.a2 * xn + u.a3 * xa - u.b1 * yn - u.b2 * ya;
        xa = xn; xn = xc; ya = yn; yn = yc;
        plane[y * u.width + gx] += yc;
    }
}

// Pass 2 (rows): one thread per row — reads the column plane, writes the
// SECOND plane half (two-plane discipline, no aliasing).
kernel void mask_blur_row(
    device const float *colPlane        [[buffer(0)]],
    device float *outPlane              [[buffer(1)]],
    constant MaskBlurUniforms &u        [[buffer(2)]],
    uint gy [[thread_position_in_grid]])
{
    if (gy >= u.height) return;
    const uint width = u.width;
    const uint base = gy * width;

    float xp = clamp(colPlane[base], 0.0f, 1.0f);
    float yb = xp * u.coefp;
    float yp = yb;
    for (uint x = 0; x < width; ++x) {
        const float xc = clamp(colPlane[base + x], 0.0f, 1.0f);
        const float yc = u.a0 * xc + u.a1 * xp - u.b1 * yp - u.b2 * yb;
        xp = xc; yb = yp; yp = yc;
        outPlane[base + x] = yc;
    }

    float xn = clamp(colPlane[base + width - 1u], 0.0f, 1.0f);
    float xa = xn;
    float yn = xn * u.coefn;
    float ya = yn;
    for (uint k = 0; k < width; ++k) {
        const uint x = width - 1u - k;
        const float xc = clamp(colPlane[base + x], 0.0f, 1.0f);
        const float yc = u.a2 * xn + u.a3 * xa - u.b1 * yn - u.b2 * ya;
        xa = xn; xn = xc; ya = yn; yn = yc;
        outPlane[base + x] += yc;
    }
}

// Pass 3 — the row plane half → output texture.
kernel void mask_blur_store(
    device const float *plane           [[buffer(0)]],
    constant MaskBlurUniforms &u        [[buffer(1)]],
    texture2d<float, access::write> out [[texture(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.width || gid.y >= u.height) return;
    if (gid.y >= u.rowEnd) return;
    out.write(plane[gid.y * u.width + gid.x], gid);
}
