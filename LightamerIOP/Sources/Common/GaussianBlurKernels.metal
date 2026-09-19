#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// GaussianBlur kernels (Plan 03-04-T1) — the shared domain blur primitive
// for the Lab-domain iops (shadhi's gaussian leg first; toneequal's box
// mean uses its own reduction).
//
// SOURCE (verbatim port): Darktable's gaussian is a Deriche/Young-van-
// Vliet RECURSIVE IIR filter, NOT a truncated FIR:
//   - coefficients: src/common/gaussian.c:41-100 `_compute_gauss_params`
//     (alpha = 1.695/sigma; the ZERO-order branch is shadhi's default
//     DT_IOP_GAUSSIAN_ZERO)
//   - recursion   : gaussian.c:195-262 (`dt_gaussian_blur` column pass)
//     and data/kernels/gaussian.cl:104-162 (`gaussian_column_4c`):
//     forward pass  yc = a0·xc + a1·xp − b1·yp − b2·yb
//     backward pass yc = a2·xn + a3·xa − b1·yn − b2·ya, ADDED to forward
//     with the INPUT clamped to [boundsMin, boundsMax] at every sample in
//     both directions (dt's Labmin/Labmax box).
//
// PLANE = device BUFFER, not a read_write texture (03-04 finding, L014
// sibling): dt's OpenCL hands the passes a `__global float4 *` plane for
// exactly this reason (gaussian.cl:104 `__global float4 *out` + the
// backward `out[loc] += ...`). The first Metal draft used a
// texture2d<float, access::read_write> and the backward's in-thread
// `out.read` after the forward's `out.write` RETURNED ZERO on M4/macOS 27
// (write→read coherence inside one dispatch is not honored for
// read_write textures) — the blur silently degenerated to the backward
// half. device-memory stores/loads by the SAME thread are program-ordered,
// so the dt buffer shape is the faithful and correct port:
//   1. `gaussian_pass_col`  texture in  → plane (fwd store, bwd +=)
//   2. `gaussian_pass_row`  plane → plane in place (one thread per row;
//      a row is touched by exactly one thread, so the in-place fwd
//      overwrite + bwd RMW never crosses threads)
//   3. `gaussian_store`     plane → output texture
//
// DEVIATION (plan-source erratum, recorded on the Swift side too): plan
// T1 described a truncated FIR ("sigma → tap 数/权重 buffer"). dt's actual
// algorithm is the recursive IIR above; we follow the SOURCE so shadhi's
// blurred base layer matches dt's algorithm. Consequence: the impulse
// response approximates (not equals) the analytic gaussian at the Deriche
// approximation error; GaussianBlurTests pins that envelope instead of
// the FIR-exact <1e-6. Structure: dt CPU runs columns first then rows —
// kept. L006: float32 only.
// ─────────────────────────────────────────────────────────────────────────

struct GaussianUniforms {
    float a0, a1, a2, a3, b1, b2, coefp, coefn;
    float4 boundsMin;
    float4 boundsMax;
    uint width;
    uint height;
};

// sigma <= 0 identity shortcut (the IIR coefficients degenerate to NaN at
// sigma == 0; dt never reaches sigma 0 through shadhi's radius clamp, the
// copy keeps the shared primitive total for other consumers).
kernel void gaussian_copy(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    out.write(in.read(gid), gid);
}

// Pass 1 (columns): one thread per column x — forward store + backward
// accumulate into the device plane (dt gaussian.c:195-230 shape).
kernel void gaussian_pass_col(
    texture2d<float, access::read>   in    [[texture(0)]],
    device float4 *plane                  [[buffer(1)]],
    constant GaussianUniforms &u          [[buffer(0)]],
    uint gx [[thread_position_in_grid]])
{
    if (gx >= u.width) return;
    const float4 lo = u.boundsMin;
    const float4 hi = u.boundsMax;

    // forward filter (gaussian.cl:124-140)
    float4 xp = clamp(in.read(uint2(gx, 0u)), lo, hi);
    float4 yb = xp * u.coefp;
    float4 yp = yb;
    for (uint y = 0; y < u.height; ++y) {
        const float4 xc = clamp(in.read(uint2(gx, y)), lo, hi);
        const float4 yc = u.a0 * xc + u.a1 * xp - u.b1 * yp - u.b2 * yb;
        xp = xc; yb = yp; yp = yc;
        plane[y * u.width + gx] = yc;
    }

    // backward filter, accumulated (gaussian.cl:142-161) — same-thread
    // device-memory RMW, program-ordered (the reason this is a buffer).
    float4 xn = clamp(in.read(uint2(gx, u.height - 1u)), lo, hi);
    float4 xa = xn;
    float4 yn = xn * u.coefn;
    float4 ya = yn;
    for (uint k = 0; k < u.height; ++k) {
        const uint y = u.height - 1u - k;
        const float4 xc = clamp(in.read(uint2(gx, y)), lo, hi);
        const float4 yc = u.a2 * xn + u.a3 * xa - u.b1 * yn - u.b2 * ya;
        xa = xn; xn = xc; ya = yn; yn = yc;
        plane[y * u.width + gx] += yc;
    }
}

// Pass 2 (rows): one thread per row y — the same recursion along x, from
// the column plane INTO the second plane half (dt gaussian.c:230-262
// shape: the horizontal pass READS the column result and WRITES the output
// buffer — an IN-PLACE row pass would feed the backward filter the
// forward's OUTPUT as its input signal, collapsing the DC gain to
// cp·(1+cn) — measured 03-04). Two planes, no aliasing.
kernel void gaussian_pass_row(
    device const float4 *colPlane         [[buffer(0)]],
    device float4 *outPlane               [[buffer(1)]],
    constant GaussianUniforms &u          [[buffer(2)]],
    uint gy [[thread_position_in_grid]])
{
    if (gy >= u.height) return;
    const uint base = gy * u.width;
    const float4 lo = u.boundsMin;
    const float4 hi = u.boundsMax;

    // forward filter
    float4 xp = clamp(colPlane[base], lo, hi);
    float4 yb = xp * u.coefp;
    float4 yp = yb;
    for (uint x = 0; x < u.width; ++x) {
        const float4 xc = clamp(colPlane[base + x], lo, hi);
        const float4 yc = u.a0 * xc + u.a1 * xp - u.b1 * yp - u.b2 * yb;
        xp = xc; yb = yp; yp = yc;
        outPlane[base + x] = yc;
    }

    // backward filter, accumulated
    float4 xn = clamp(colPlane[base + u.width - 1u], lo, hi);
    float4 xa = xn;
    float4 yn = xn * u.coefn;
    float4 ya = yn;
    for (uint k = 0; k < u.width; ++k) {
        const uint x = u.width - 1u - k;
        const float4 xc = clamp(colPlane[base + x], lo, hi);
        const float4 yc = u.a2 * xn + u.a3 * xa - u.b1 * yn - u.b2 * ya;
        xa = xn; xn = xc; ya = yn; yn = yc;
        outPlane[base + x] += yc;
    }
}

// Pass 3 — the row plane half → output texture.
kernel void gaussian_store(
    device const float4 *plane            [[buffer(0)]],
    constant GaussianUniforms &u          [[buffer(1)]],
    texture2d<float, access::write> out   [[texture(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.width || gid.y >= u.height) return;
    out.write(plane[gid.y * u.width + gid.x], gid);
}
