#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// ToneEqualKernels (Plan 03-05-T2/T3/T4) — the tone equalizer GPU graph.
// Darktable has NO OpenCL for this iop (toneequal.c:313 TODO); every kernel
// here is a formula-by-formula transcription of the CPU sources:
//
//   toneeq_luma_estimate   luminance_mask.h:60-200 — the SEVEN estimators
//                          (plan erratum: "9 estimators"; the enum is
//                          DT_TONEEQ_LAST = 7 — the 9 refers to the user
//                          BANDS) + linear_contrast (:52-56) with dt
//                          toneequal.c:132's fulcrum exp2(−4).
//   toneeq_bilinear_1c     fast_guided_filter.h interpolate_bilinear (ch=1).
//   toneeq_quantize        fast_guided_filter.h quantize — log2 posterize.
//   toneeq_pack4           eigf.h eigf_variance_analysis packing:
//                          (guide, guide², mask, guide·mask) into a float4
//                          plane for the 4-channel gaussian.
//   toneeq_box_mean_x/_y   box_filters.cc _blur_horizontal/_blur_vertical
//                          shape (separable, boundary-truncated window —
//                          sums divide by the VALID window size), the
//                          guided leg's box mean. The OpenCL analogue is
//                          guided_filter.cl box_mean_x/y; the CPU box mean
//                          is the parity source (dt toneequal never runs
//                          OpenCL).
//   toneeq_guided_ab       fast_guided_filter.h variance_analyse blend
//                          segment (:238-243): d = max(var+feathering,
//                          1e-15); a = cov/d; b = mean_m − a·mean_g.
//   toneeq_blend           eigf.h eigf_blending[_no_mask] (the EIGF solve+
//                          blend, exposure-weighted variance ratio) and
//                          fast_guided_filter.h apply_linear_blending
//                          [_w_geomean] (the guided a/b apply) — selected
//                          by a uniform mode flag; bilinear av/ab
//                          up-sampling is INLINED here (dt upsamples to a
//                          full plane first, then blends per-pixel with
//                          the same 4-neighbour weights — inline sampling
//                          is point-identical and saves a full float4
//                          plane, the D-C1 tiling rationale).
//   toneeq_apply           toneequal.c:771-803 — LUT gain apply; dt's
//                          `for_each_channel` multiplies ALL FOUR channels
//                          (alpha included) — verbatim quirk, kept for the
//                          golden compare.
//
// METHOD DISPATCH (plan T2 decision, recorded): the luma estimator is a
// UNIFORM branch, not a [[function_constant]] PSO specialization — seven
// method variants would multiply every other PSO dimension against the
// 256-entry LRU budget (METAL-5) for a ~1-cycle predictable branch. The
// PSO budget wins.
//
// PRECISION: float32 throughout (L006 — no half on tone paths). The EIGF
// gaussian leg REUSES Common/GaussianBlur (03-04's dt_gaussian port; the
// Deriche IIR coefficients live there) — eigf.h's blur IS dt_gaussian
// with per-channel data min/max bounds, and dt's CLAMPF applies to the
// INPUT SAMPLES against those bounds (gaussian.c:283+), i.e. it can never
// fire on finite data — the constant (MIN_FLOAT, FLT_MAX) bounds used here
// are point-identical on valid luma planes.
// ─────────────────────────────────────────────────────────────────────────

// exp2(−16) — luminance_mask.h MIN_FLOAT.
#define TE_MIN_FLOAT 1.52587890625e-05f
// dt CONTRAST_FULCRUM (toneequal.c:131).
#define TE_CONTRAST_FULCRUM 0.0625f

struct ToneEqualLumaUniforms {
    int method;           // dt_iop_luminance_mask_method_t raw value
    float exposureBoost;  // d->exposure_boost (exp2 of the EV param)
    float fulcrum;        // 0.0 (unboosted modes) or CONTRAST_FULCRUM
    float contrastBoost;  // 1.0 (unboosted modes) or d->contrast_boost
};

// luminance_mask.h linear_contrast (:52-58).
static inline float te_linear_contrast(float pixel, float fulcrum, float contrast) {
    return max((pixel - fulcrum) * contrast + fulcrum, TE_MIN_FLOAT);
}

kernel void toneeq_luma_estimate(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ToneEqualLumaUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;
    const float4 p = in.read(gid);
    float lum = 0.0f;
    switch (u.method) {
        case 0: { // DT_TONEEQ_MEAN — RGB average
            lum = u.exposureBoost * (p.r + p.g + p.b) / 3.0f;
            break;
        }
        case 1: { // DT_TONEEQ_LIGHTNESS — HSL lightness
            const float mx = max(max(p.r, p.g), p.b);
            const float mn = min(min(p.r, p.g), p.b);
            lum = u.exposureBoost * (mx + mn) / 2.0f;
            break;
        }
        case 2: { // DT_TONEEQ_VALUE — HSV value / RGB max
            lum = u.exposureBoost * max(max(p.r, p.g), p.b);
            break;
        }
        case 3: { // DT_TONEEQ_NORM_1 — RGB sum
            lum = u.exposureBoost * (fabs(p.r) + fabs(p.g) + fabs(p.b));
            break;
        }
        case 4: { // DT_TONEEQ_NORM_2 — RGB euclidean norm (dt default)
            lum = u.exposureBoost * sqrt(p.r * p.r + p.g * p.g + p.b * p.b);
            break;
        }
        case 5: { // DT_TONEEQ_NORM_POWER — the perceptual power norm
            const float ar = fabs(p.r), ag = fabs(p.g), ab = fabs(p.b);
            const float num = ar*ar*ar + ag*ag*ag + ab*ab*ab;
            const float den = ar*ar + ag*ag + ab*ab;
            lum = u.exposureBoost * num / den;
            break;
        }
        case 6: { // DT_TONEEQ_GEOMEAN — geometric mean
            lum = u.exposureBoost * pow(fabs(p.r) * fabs(p.g) * fabs(p.b), 1.0f / 3.0f);
            break;
        }
        default:
            lum = u.exposureBoost * (p.r + p.g + p.b) / 3.0f;
            break;
    }
    const float v = te_linear_contrast(lum, u.fulcrum, u.contrastBoost);
    out.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}

// ─────────────────────────────────────────────────────────────────────────
// Detail-preserving filter stage (T3). Two legs:
//
//   EIGF (dt default)  ds bilinear → [quantize] → pack4 → GaussianBlur
//                      (Common/GaussianBlur, σ = ds_sigma) → toneeq_blend
//                      per iteration, blend ALWAYS at full res
//                      (eigf.h fast_eigf_surface_blur shape).
//   guided             ds bilinear (scaling fixed 4) → per iteration:
//                      quantize (on ds) → pack4 → box_mean x/y →
//                      toneeq_guided_ab → box_mean x/y on ab → ds blend;
//                      final iteration upsamples ab and blends at full res
//                      (fast_guided_filter.h fast_surface_blur shape).
//   none               mask passes straight to the apply kernel.
// ─────────────────────────────────────────────────────────────────────────

struct ToneEqualBilinearUniforms {
    uint srcWidth;
    uint srcHeight;
    uint dstWidth;
    uint dstHeight;
};

// fast_guided_filter.h interpolate_bilinear — dt's exact corner
// convention (x_out = j/width_out, NOT a half-pixel-center grid).
// dt's bilinear for a generic (x, y) in output pixels.
static inline float te_interpolate_bilinear(
    texture2d<float, access::read> src, uint dstX, uint dstY,
    uint srcW, uint srcH, uint dstW, uint dstH)
{
    const float xOut = float(dstX);
    const float yOut = float(dstY);
    const float xIn = xOut / float(dstW) * float(srcW);
    const float yIn = yOut / float(dstH) * float(srcH);

    uint xPrev = uint(floor(xIn));
    uint xNext = xPrev + 1;
    uint yPrev = uint(floor(yIn));
    uint yNext = yPrev + 1;
    xPrev = min(xPrev, srcW - 1);
    xNext = min(xNext, srcW - 1);
    yPrev = min(yPrev, srcH - 1);
    yNext = min(yNext, srcH - 1);

    const float nw = src.read(uint2(xPrev, yPrev)).r;
    const float ne = src.read(uint2(xNext, yPrev)).r;
    const float sw = src.read(uint2(xPrev, yNext)).r;
    const float se = src.read(uint2(xNext, yNext)).r;

    const float dyNext = float(yNext) - yIn;   // dt: (float)y_next − y_in
    const float dyPrev = 1.0f - dyNext;
    const float dxNext = float(xNext) - xIn;
    const float dxPrev = 1.0f - dxNext;

    return dyPrev * (sw * dxNext + se * dxPrev)
         + dyNext * (nw * dxNext + ne * dxPrev);
}

// Same, reading all four channels of an rgba plane (the ab/av upsample).
static inline float4 te_interpolate_bilinear4(
    texture2d<float, access::read> src, uint dstX, uint dstY,
    uint srcW, uint srcH, uint dstW, uint dstH)
{
    const float xIn = float(dstX) / float(dstW) * float(srcW);
    const float yIn = float(dstY) / float(dstH) * float(srcH);

    uint xPrev = uint(floor(xIn));
    uint xNext = xPrev + 1;
    uint yPrev = uint(floor(yIn));
    uint yNext = yPrev + 1;
    xPrev = min(xPrev, srcW - 1);
    xNext = min(xNext, srcW - 1);
    yPrev = min(yPrev, srcH - 1);
    yNext = min(yNext, srcH - 1);

    const float4 nw = src.read(uint2(xPrev, yPrev));
    const float4 ne = src.read(uint2(xNext, yPrev));
    const float4 sw = src.read(uint2(xPrev, yNext));
    const float4 se = src.read(uint2(xNext, yNext));

    const float dyNext = float(yNext) - yIn;
    const float dyPrev = 1.0f - dyNext;
    const float dxNext = float(xNext) - xIn;
    const float dxPrev = 1.0f - dxNext;

    return dyPrev * (sw * dxNext + se * dxPrev)
         + dyNext * (nw * dxNext + ne * dxPrev);
}

kernel void toneeq_bilinear_1c(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ToneEqualBilinearUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;
    const float v = te_interpolate_bilinear(
        in, gid.x, gid.y, u.srcWidth, u.srcHeight, u.dstWidth, u.dstHeight);
    out.write(float4(v, 0.0f, 0.0f, 0.0f), gid);
}

struct ToneEqualQuantizeUniforms {
    float sampling;   // 0 = copy; 1 = fast track; else log2 step
    float clipMin;    // dt passes exp2(−14)
    float clipMax;    // dt passes 4
};

// fast_guided_filter.h quantize — log2-space posterization.
kernel void toneeq_quantize(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ToneEqualQuantizeUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;
    const float v = in.read(gid).r;
    float q;
    if (u.sampling == 0.0f) {
        q = v;
    } else if (u.sampling == 1.0f) {
        q = exp2(floor(log2(v)));
    } else {
        q = exp2(floor(log2(v) / u.sampling) * u.sampling);
    }
    q = min(max(q, u.clipMin), u.clipMax);
    out.write(float4(q, 0.0f, 0.0f, 0.0f), gid);
}

// eigf.h eigf_variance_analysis packing: (guide, guide², mask, guide·mask)
// into the float4 plane the 4-channel gaussian blurs. The no-mask path
// passes the SAME texture as guide and mask (channels 2/3 are then
// duplicates — eigf's 2-channel variant keeps only the first two, and the
// blend kernel reads only those; the blur is per-channel independent so
// the values are identical).
kernel void toneeq_pack4(
    texture2d<float, access::read> guide [[texture(0)]],
    texture2d<float, access::read> mask [[texture(1)]],
    texture2d<float, access::write> out [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;
    const float g = guide.read(gid).r;
    const float m = mask.read(gid).r;
    out.write(float4(g, g * g, m, g * m), gid);
}

// box_filters.cc _blur_horizontal shape: separable moving average with a
// boundary-TRUNCATED window (the sum divides by the valid window size).
// One thread per row; O(1) sliding sums per channel (the guided_filter.cl
// box_mean_x topology; the CPU non-Kahan float path is the parity source —
// toneequal never runs OpenCL in dt).
kernel void toneeq_box_mean_x(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant uint &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint w = in.get_width();
    if (gid.y >= in.get_height() || w == 0) return;
    const int r = int(radius);
    float4 sum = 0.0f;
    int hits = 0;
    const int iR = min(r, int(w) - 1);
    for (int x = 0; x <= iR; x++) {
        sum += in.read(uint2(x, gid.y));
        hits++;
    }
    float4 acc = sum;
    int accHits = hits;
    for (int x = 0; x < int(w); x++) {
        out.write(acc / float(accHits), uint2(x, gid.y));
        const int add = x + r + 1;
        const int rem = x - r;
        if (add < int(w)) { acc += in.read(uint2(add, gid.y)); accHits++; }
        if (rem >= 0) { acc -= in.read(uint2(rem, gid.y)); accHits--; }
    }
}

// box_filters.cc _blur_vertical — one thread per column.
kernel void toneeq_box_mean_y(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant uint &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint h = in.get_height();
    if (gid.x >= in.get_width() || h == 0) return;
    const int r = int(radius);
    float4 sum = 0.0f;
    int hits = 0;
    const int iR = min(r, int(h) - 1);
    for (int y = 0; y <= iR; y++) {
        sum += in.read(uint2(gid.x, y));
        hits++;
    }
    float4 acc = sum;
    int accHits = hits;
    for (int y = 0; y < int(h); y++) {
        out.write(acc / float(accHits), uint2(gid.x, y));
        const int add = y + r + 1;
        const int rem = y - r;
        if (add < int(h)) { acc += in.read(uint2(gid.x, add)); accHits++; }
        if (rem >= 0) { acc -= in.read(uint2(gid.x, rem)); accHits--; }
    }
}

struct ToneEqualABUniforms {
    float feathering; // d->feathering = 1 / UI value
};

// fast_guided_filter.h variance_analyse blend segment (:238-243), reading
// the blurred pack plane (r=ḡ, g²̄, m̄, ḡm̄ in the pack4 channel order):
//   d = max(g²̄ − ḡ² + feathering, 1e-15);  a = (ḡm̄ − ḡ·m̄)/d;  b = m̄ − a·ḡ
kernel void toneeq_guided_ab(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ToneEqualABUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;
    const float4 v = in.read(gid);
    const float gMean = v.r;
    const float mMean = v.b;
    const float d = fmax((v.g - v.r * v.r) + u.feathering, 1e-15f);
    const float a = (v.a - v.r * v.b) / d;
    const float b = mMean - a * gMean;
    out.write(float4(a, b, 0.0f, 0.0f), gid);
}

// ─────────────────────────────────────────────────────────────────────────
// Correction apply (T4) — toneequal.c:771-803 apply_toneequalizer (the
// LUT version dt ships with): exposure = clamp(log2(luma), −8, 0), LUT
// index = round((exposure + 8) × 10000), out = correction × in on ALL
// FOUR channels (dt's `for_each_channel` = 4 — alpha rides along; kept
// verbatim for the golden compare).
// ─────────────────────────────────────────────────────────────────────────

kernel void toneeq_apply(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::read> luma [[texture(1)]],
    texture2d<float, access::write> out [[texture(2)]],
    device const float *lut [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;
    const float lum = luma.read(gid).r;
    const float exposure = clamp(log2(lum), -8.0f, 0.0f);
    const uint idx = (uint)round((exposure + 8.0f) * 10000.0f);
    const float correction = lut[idx];
    out.write(in.read(gid) * correction, gid);
}

struct ToneEqualBlendUniforms {
    int mode;         // 0 = EIGF no-mask, 1 = EIGF mask, 2 = guided a/b
    int upsample;     // 1 = bilinear-sample av/ab at full-res coords
    int geomean;      // dt GF blending: 0 linear, 1 geometric mean
    float feathering; // EIGF eps (d->feathering)
    uint auxWidth;    // the av/ab plane dims
    uint auxHeight;
    uint srcWidth;    // the CURRENT-mask plane dims (== output dims)
    uint srcHeight;
};

// The solve+blend epilogue:
//   EIGF (eigf.h eigf_blending[_no_mask], the exposure-weighted variance
//        RATIO — EIGF's whole point): normalized_var = var / max(ā·I, 1e-6),
//        a = nvar/(nvar + feathering) [no-mask], or the covariant pair with
//        √(norm_g·norm_m) [mask]; b = ā − a·ā (NO final spatial averaging —
//        eigf.h's documented divergence from the plain guided filter).
//   guided (apply_linear_blending): out = I·a + b with the box-smoothed a/b.
// The full-res path INLINES the bilinear av/ab upsample (dt upsamples into
// a plane first, then blends per-pixel with the same 4-neighbour weights —
// point-identical, one less full plane).
kernel void toneeq_blend(
    texture2d<float, access::read> image [[texture(0)]],      // the mask being filtered
    texture2d<float, access::read> mask [[texture(1)]],       // the quantized mask (mode 1); == image otherwise
    texture2d<float, access::read> aux [[texture(2)]],        // av (modes 0/1) or ab (mode 2)
    texture2d<float, access::write> out [[texture(3)]],
    constant ToneEqualBlendUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;
    const float img = image.read(gid).r;

    float4 av;
    if (u.upsample != 0) {
        av = te_interpolate_bilinear4(
            aux, gid.x, gid.y, u.auxWidth, u.auxHeight, u.srcWidth, u.srcHeight);
    } else {
        av = aux.read(gid);
    }

    float a;
    float b;
    if (u.mode == 2) {
        a = av.r;
        b = av.g;
    } else if (u.mode == 0) {
        // EIGF, guide == mask (eigf_blending_no_mask)
        const float avg = av.r;
        const float var = av.g - avg * avg;
        const float norm = fmax(avg * img, 1e-6f);
        const float nvar = var / norm;
        a = nvar / (nvar + u.feathering);
        b = avg - a * avg;
    } else {
        // EIGF with a quantized mask (eigf_blending)
        const float avgG = av.r;
        const float varG = av.g - avgG * avgG;
        const float avgM = av.b;
        const float cov = av.a - avgG * avgM;
        const float mPix = mask.read(gid).r;
        const float normG = fmax(avgG * img, 1e-6f);
        const float normM = fmax(avgM * mPix, 1e-6f);
        const float nvar = varG / normG;
        const float ncov = cov / sqrt(normG * normM);
        a = ncov / (nvar + u.feathering);
        b = avgM - a * avgG;
    }

    float outV;
    if (u.geomean != 0) {
        // apply_linear_blending_w_geomean / the geomean branch
        outV = sqrt(img * fmax(img * a + b, TE_MIN_FLOAT));
    } else {
        outV = fmax(img * a + b, TE_MIN_FLOAT);
    }
    out.write(float4(outV, 0.0f, 0.0f, 0.0f), gid);
}
