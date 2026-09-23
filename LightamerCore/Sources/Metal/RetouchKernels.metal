#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// RetouchKernels (Plan 06-07 T2/T3; IOP-GEO-06; 06-RESEARCH §5.2).
//
// The retouch layer's per-stroke legs. dt shape: each stroke processes a
// PATCH (the stroke's shape bbox), producing an alternate content that the
// stroke mask then blends over the evolving image (`rt_copy_image_masked`,
// retouch.c). The four algorithms:
//
//   clone — sample the evolving image at the source offset (dt
//           `_retouch_clone`: img_src = in copied at (dx,dy), masked paste)
//   blur  — Gaussian-blur a CROP of the stroke bbox (dt `_retouch_blur`:
//           dt_gaussian_blur_4c over roi_mask_scaled; the crop keeps the
//           FULL-fit working set O(patch) instead of O(plane))
//   fill  — constant color (dt `_retouch_fill` color mode)
//   heal  — iterative Laplacian (dt_heal, heal.c:354; T3 below)
//
// The mask plane per stroke is the PREMULTIPLIED effective opacity
// (clamp[0,1] × stroke opacity — the 06-02 composite contract), rasterized
// by the 06-03 drawn-mask rasterizer from the stroke's MaskForm shape
// (content-anchored through the GeometryPointMapper).
//
// Blend formula (masked paste): out = below·(1−m) + alternate·m.
// ─────────────────────────────────────────────────────────────────────────────

/// Swift mirror: `RetouchApplyUniforms` (16-byte-chunk packing, the
/// packing-postmortem pattern).
struct RetouchApplyUniforms {
    float4 fillColor;      // mode 1: the constant (linear Rec2020 rgb)
    float2 sampleOffsetPx; // mode 0: sample offset in the ALT frame (clone)
    float2 altOriginPx;    // alt-texture origin in the below/window frame
                           // (blur/heal crops; (0,0) for clone)
    uint mode;             // 0 = sample alternate texture, 1 = fill constant
    uint altIsWindow;      // 1 = alt IS the below plane itself (clone: clamp
                           // sampling against the window extents)
    uint2 _pad;
};

/// One masked-paste pass. Threads span the WINDOW (out) extents.
///
/// Textures:
///   0 below    — the evolving composite plane (previous strokes applied)
///   1 alt      — clone: `below` itself; blur: the blurred crop; heal: the
///                healed patch (bound at 2 in that leg)
///   2 mask     — r32Float premultiplied stroke mask (window-sized)
///   3 out      — the new evolving plane
kernel void retouch_apply(
    texture2d<float, access::read> below  [[texture(0)]],
    texture2d<float, access::read> alt    [[texture(1)]],
    texture2d<float, access::read> mask   [[texture(2)]],
    texture2d<float, access::write> out   [[texture(3)]],
    constant RetouchApplyUniforms &u      [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    const float4 d = below.read(gid);
    const float m = mask.read(gid).r;
    if (m <= 0.0f) { out.write(d, gid); return; }

    float4 replacement = d;
    if (u.mode == 1) {
        replacement = u.fillColor;
    } else {
        // ALT-frame sample position: window pixel − alt origin + offset,
        // clamped into the alt extents (out-of-crop reads clamp to the
        // edge — the ROI extension guarantees real pixels inside the
        // window; the clamp only guards the outermost feather fringe).
        const float2 p = float2(gid) - u.altOriginPx + u.sampleOffsetPx;
        const float2 limit = (u.altIsWindow != 0u)
            ? float2(below.get_width() - 1, below.get_height() - 1)
            : float2(alt.get_width() - 1, alt.get_height() - 1);
        const uint2 q = uint2(clamp(p, float2(0.0f), limit) + float2(0.5f));
        replacement = alt.read(q);
    }
    out.write(d * (1.0f - m) + replacement * m, gid);
}

// ─────────────────────────────────────────────────────────────────────────────
// The RGBA Deriche blur (the retouch `blur` algorithm's engine). Same 3-pass
// structure as the mask blur (MaskPostProcessKernels mask_blur_col/row/store,
// the dt `dt_gaussian_blur_4c` shape) but over rgba32Float WITHOUT the [0,1]
// clamp (image data — the LightamerIOP GaussianBlur's infinite-bounds
// behavior). Coefficients come from the SAME-SOURCE Deriche derivation
// (MaskCombiner.maskGaussCoeffs, pinned against IOP by a cross-check test).
// Layout mirror of IOP's MSL MaskBlurUniforms (48 bytes — this file compiles
// into CORE's metallib and cannot see the IOP definition).
// ─────────────────────────────────────────────────────────────────────────────

struct RetouchBlurUniforms {
    float a0, a1, a2, a3;
    float b1, b2, coefp, coefn;
    uint width;
    uint height;
    uint rowEnd;
    uint _pad;
};

kernel void retouch_blur_col(
    texture2d<float, access::read> in   [[texture(0)]],
    device float4 *plane                [[buffer(1)]],
    constant RetouchBlurUniforms &u        [[buffer(0)]],
    uint gx [[thread_position_in_grid]])
{
    if (gx >= u.width) return;
    const uint height = u.height;

    float4 xp = in.read(uint2(gx, 0u));
    float4 yb = xp * u.coefp;
    float4 yp = yb;
    for (uint y = 0; y < height; ++y) {
        const float4 xc = in.read(uint2(gx, y));
        const float4 yc = u.a0 * xc + u.a1 * xp - u.b1 * yp - u.b2 * yb;
        xp = xc; yb = yp; yp = yc;
        plane[y * u.width + gx] = yc;
    }

    float4 xn = in.read(uint2(gx, height - 1u));
    float4 xa = xn;
    float4 yn = xn * u.coefn;
    float4 ya = yn;
    for (uint k = 0; k < height; ++k) {
        const uint y = height - 1u - k;
        const float4 xc = in.read(uint2(gx, y));
        const float4 yc = u.a2 * xn + u.a3 * xa - u.b1 * yn - u.b2 * ya;
        xa = xn; xn = xc; ya = yn; yn = yc;
        plane[y * u.width + gx] += yc;
    }
}

kernel void retouch_blur_row(
    device const float4 *colPlane       [[buffer(0)]],
    device float4 *outPlane             [[buffer(1)]],
    constant RetouchBlurUniforms &u        [[buffer(2)]],
    uint gy [[thread_position_in_grid]])
{
    if (gy >= u.height) return;
    const uint width = u.width;
    const uint base = gy * width;

    float4 xp = colPlane[base];
    float4 yb = xp * u.coefp;
    float4 yp = yb;
    for (uint x = 0; x < width; ++x) {
        const float4 xc = colPlane[base + x];
        const float4 yc = u.a0 * xc + u.a1 * xp - u.b1 * yp - u.b2 * yb;
        xp = xc; yb = yp; yp = yc;
        outPlane[base + x] = yc;
    }

    float4 xn = colPlane[base + width - 1u];
    float4 xa = xn;
    float4 yn = xn * u.coefn;
    float4 ya = yn;
    for (uint k = 0; k < width; ++k) {
        const uint x = width - 1u - k;
        const float4 xc = colPlane[base + x];
        const float4 yc = u.a2 * xn + u.a3 * xa - u.b1 * yn - u.b2 * ya;
        xa = xn; xn = xc; ya = yn; yn = yc;
        outPlane[base + x] += yc;
    }
}

kernel void retouch_blur_store(
    device const float4 *plane          [[buffer(0)]],
    constant RetouchBlurUniforms &u        [[buffer(1)]],
    texture2d<float, access::write> out [[texture(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.width || gid.y >= u.height) return;
    out.write(plane[gid.y * u.width + gid.x], gid);
}

// ─────────────────────────────────────────────────────────────────────────────
// heal patch legs (dt `_heal_sub` / `_heal_add`, heal.c:96-153): the SOLVER
// input pattern = target patch − source patch; the final add-back writes
// result = source patch + solved pattern. Outside the mask the pattern is
// the untouched Dirichlet boundary (heal.c:141-144 zero-pad rows).
// ─────────────────────────────────────────────────────────────────────────────

kernel void heal_subtract(
    texture2d<float, access::read> top    [[texture(0)]],   // target patch
    texture2d<float, access::read> bottom [[texture(1)]],   // source patch
    texture2d<float, access::write> out   [[texture(2)]],   // pattern
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    out.write(top.read(gid) - bottom.read(gid), gid);
}

kernel void heal_add(
    texture2d<float, access::read> solution [[texture(0)]], // solved pattern
    texture2d<float, access::read> base     [[texture(1)]], // source patch
    texture2d<float, access::write> out     [[texture(2)]], // healed patch
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    out.write(solution.read(gid) + base.read(gid), gid);
}

// ─────────────────────────────────────────────────────────────────────────────
// heal (Plan 06-07 T3) — dt `_heal_laplace_loop` (heal.c:354-422) as a
// red-black Gauss-Seidel with successive over-relaxation, ONE COLOR
// HALF-SWEEP per dispatch:
//
// dt splits the patch pixels into red/black checkerboard cells and runs
// `_heal_laplace_iteration` per color per iteration — within one color the
// updates are independent (every neighbor is the opposite color), so a
// parallel color sweep IS dt's sequential sweep, value-for-value. The CPU
// loop in `RetouchEngine` dispatches red/black alternately between two
// ping-pong planes and folds the accumulated error for the early exit
// (`err < err_exit`, heal.c:392-396).
//
// Notation (heal.c:318-330, transcribed):
//   active r(i)(j): a = 4 (minus 1 at the padding-row edges);
//   left/right neighbors sit in the opposite color's half of the checker
//   layout — on the GPU the ping-pong plane stays in FULL patch layout
//   (no checker split), so the four neighbors are plain ±1 offsets and
//   the boundary weight drops the out-of-patch sides (Dirichlet boundary:
//   outside = the border rows dt zero-pads, heal.c:141-144).
//
// The SOLVER input (pattern = source patch − target patch) and the final
// add-back run in `RetouchEngine` (Swift) — only the iteration is a kernel.
// ─────────────────────────────────────────────────────────────────────────────

/// Swift mirror: `HealStepUniforms`.
struct HealStepUniforms {
    float w;          // the SOR factor (heal.c:380 formula, Swift side)
    float _pad0;
    float _pad1;
    float _pad2;
    uint2 size;       // patch extents (px)
    uint parity;      // 0 = red cells ((x+y) even), 1 = black (odd)
    uint _pad3;
};

/// One red/black half-sweep of the SOR Laplacian over the patch.
///   0 in       — the current solution plane (pattern buffer, rgba32Float)
///   1 mask     — r32Float premultiplied stroke mask (patch-sized, the
///                Dirichlet region; values > 0 = active cells)
///   2 out      — the next solution plane (ping-pong)
///   buffer 1   — device atomic<float> [1]: the Σ diff[c]² residual
///                accumulator (heal.c:313 err reduction over RGB; reset to
///                0 by the CPU before each half-sweep via a blit fill).
///                Order-nondeterministic — it gates the EARLY EXIT only,
///                never a pixel value.
kernel void heal_laplace_step(
    texture2d<float, access::read> in    [[texture(0)]],
    texture2d<float, access::read> mask  [[texture(1)]],
    texture2d<float, access::write> out  [[texture(2)]],
    constant HealStepUniforms &u         [[buffer(0)]],
    device atomic_float *errAccumulator  [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.size.x || gid.y >= u.size.y) return;
    const float4 v = in.read(gid);
    out.write(v, gid);
    if (mask.read(gid).r <= 0.0f) return;
    if (((gid.x + gid.y) & 1u) != u.parity) return;

    float a = 4.0f;
    float4 left = v, right = v, up = v, down = v;
    if (gid.x == 0u)             { a -= 1.0f; } else { left  = in.read(gid - uint2(1, 0)); }
    if (gid.x == u.size.x - 1u)  { a -= 1.0f; } else { right = in.read(gid + uint2(1, 0)); }
    if (gid.y == 0u)             { a -= 1.0f; } else { up    = in.read(gid - uint2(0, 1)); }
    if (gid.y == u.size.y - 1u)  { a -= 1.0f; } else { down  = in.read(gid + uint2(0, 1)); }

    // One SOR update of the Gauss-Seidel form (heal.c:341-345):
    //   diff = w·(a·v − (left+right+up+down)); v ← v − diff.
    // (dt's checker-split neighbor indexing collapses to plain ±1 offsets
    // in the full-layout ping-pong plane.)
    const float4 diff = u.w * (a * v - (left + right + up + down));
    out.write(v - diff, gid);
    const float e = diff.x * diff.x + diff.y * diff.y + diff.z * diff.z;
    atomic_fetch_add_explicit(&errAccumulator[0], e, memory_order_relaxed);
}
