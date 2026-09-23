#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// Liquify warp kernel (Plan 06-06 T2, IOP-GEO-05) — the transcription of
// darktable's `warp_kernel` (data/kernels/liquify.cl:73-131), plus its kernel
// table producer semantics (liquify.c:1470-1497: kdesc resolution 100, size =
// interpolation half-width).
//
// SEMANTICS (L020 — same domain as the CPU field): for each OUTPUT pixel the
// kernel reads the per-pixel displacement F at that pixel (grid coords ==
// plane pixel coords, DisplacementField.Grid) and resamples the input at
// `pos + F` with a discrete-convolution kernel (lanczos3/bicubic/bilinear
// table, mixed per kmix). Zero-displacement cells pass the input pixel
// through verbatim (dt pre-copies the whole roi and only warps inside the
// extent — liquify.c process :1400-1403 + warp_kernel early-out :97-104;
// same result, one pass).
//
// MSL vs CL coordinate note: dt's CL `read_imagef(sampleri, coord)` anchors
// pixel centers at INTEGER coordinates; MSL `coord::pixel` anchors centers
// at +0.5 — every sample coordinates gets the +0.5 here. `sampleri` is
// CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_NEAREST — mirrored in the constexpr
// sampler (dt common.h).
// ─────────────────────────────────────────────────────────────────────────────

struct LiquifyRois {
    int4 roiIn;    // x, y, w, h — the INPUT plane region (plane pixels)
    int4 roiOut;   // x, y, w, h — the OUTPUT region this dispatch covers
    int4 extent;   // the displacement grid's frame-coords rect (x, y, w, h)
    int2 kdesc;    // (size = half kernel width a, resolution = table steps)
};

// liquify.cl kmix (:47-53): the table holds the kernel sampled every
// 1/resolution; linear blend between adjacent samples. The i+1 pair index
// is clamped to the table end (t == size exactly — e.g. fx == 0 with the
// outermost lanczos3 tap — reads k[size·res] with weight 1.0; dt's buffer
// had no clamp and OOB-read its last allocation page, a latent latent bug
// not worth reproducing).
static inline float la_kmix(const device float* k, int resolution,
                            int tableEnd, float t) {
    t = fabs(t * (float)resolution);
    float flor = floor(t);
    int i = min((int)flor, tableEnd - 1);
    return mix(k[i], k[i + 1], t - flor);
}

kernel void liquify_warp(
    texture2d<float, access::sample> in   [[texture(0)]],
    texture2d<float, access::write>  out  [[texture(1)]],
    constant LiquifyRois&            rois [[buffer(0)]],
    const device float2*             map  [[buffer(1)]],
    const device float*              ktab [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    // Stop surplus workers in the last threadgroup.
    if (gid.x >= (uint)rois.roiOut[2] || gid.y >= (uint)rois.roiOut[3]) {
        return;
    }
    constexpr sampler smp(coord::pixel, address::clamp_to_edge, filter::nearest);

    const int2 framePos = int2(gid) + rois.roiOut.xy;

    // Displacement at this output pixel (zero outside the grid extent).
    const int2 cell = framePos - rois.extent.xy;
    float2 warp = float2(0.0f, 0.0f);
    if (cell.x >= 0 && cell.y >= 0 && cell.x < rois.extent[2] && cell.y < rois.extent[3]) {
        warp = map[cell.y * rois.extent[2] + cell.x];
    }

    const int2 inCell = framePos - rois.roiIn.xy;
    if (warp.x == 0.0f && warp.y == 0.0f) {
        // Passthrough (dt's copy leg): byte-identical pixel.
        out.write(in.sample(smp, float2(inCell) + 0.5f), gid);
        return;
    }

    const float2 inPos = float2(inCell) + warp;
    const int a = rois.kdesc[0];

    // Kernel weights: 2·a taps at offsets 1−a … a (liquify.cl :106-114).
    float2 lkernel[6];                       // 2 × the biggest a (lanczos3)
    thread float2* lk = lkernel + a - 1;
    float2 norm = float2(0.0f);
    const float fx = inPos.x - floor(inPos.x);
    const float fy = inPos.y - floor(inPos.y);
    const int tableEnd = a * rois.kdesc[1];
    for (int i = 1 - a; i <= a; ++i) {
        lk[i].x = la_kmix(ktab, rois.kdesc[1], tableEnd, fx - (float)i);
        lk[i].y = la_kmix(ktab, rois.kdesc[1], tableEnd, fy - (float)i);
        norm += lk[i];
    }

    // Support-region convolution (:121-128) — 6×6 taps for lanczos3.
    const float2 base = floor(inPos);
    float4 acc = float4(0.0f);
    for (int sy = 1 - a; sy <= a; ++sy) {
        for (int sx = 1 - a; sx <= a; ++sx) {
            acc += in.sample(smp, base + float2((float)sx, (float)sy) + 0.5f)
                * lk[sx].x * lk[sy].y;
        }
    }
    out.write(acc / (norm.x * norm.y), gid);
}
