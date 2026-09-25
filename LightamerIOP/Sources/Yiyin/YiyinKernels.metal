#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// YiyinKernels (Plan 08-01; yiyin 印框 render legs) — LightamerIOP's
// metallib; function names resolved via the registered-library lookup.
//
// yiyin_composite — the ONE canvas-composition dispatch (T3): the borders
//   output plane = background band (solid fill; blur proxy sampling wires
//   in T5) + the optional brightness overlay (T5) + the shadow (T4, a
//   pre-blurred SDF plane) + the main image clipped by the rounded-rect
//   SDF. Replaces yiyin's mask-PNG two-process round trip (the mask PNG is
//   yiyin's Electron renderer boundary artifact — RESEARCH §1.2; the Metal
//   face composes in one pass, D-08-CONTEXT 继承定案 渲染分工).
//
// yiyin_shadow_sdf (T4) — stamps the rounded-rect SDF alpha for the
//   shadow plane (GaussianBlur consumes it).
//
// yiyin_box_downsample (T5) — box-average downsample (blur proxy +
//   brightness probe).
//
// Coordinate conventions (L020/L021): everything is in THIS RUN's plane
// pixels — the module passes output-plane-relative geometry; `dscIn` is
// never re-scaled. The main-image lookup is EXACT 1:1 (yiyin never
// rescales the main image — it grows the canvas instead): output pixel p
// samples input at p − mainOffset with a bounds check.
// ─────────────────────────────────────────────────────────────────────────

/// Mirror of Swift `YiyinCompositeUniforms` (BordersModule).
struct YiyinCompositeUniforms {
    int32_t hasBlurTex;   // blur proxy bound (1) / solid fill (0)
    int32_t hasOverlay;   // brightness overlay active (blur mode only)
    int32_t hasShadow;    // shadow plane bound
    int32_t pad;
    float4 fillColor;     // display-domain linear RGB, a = 1
    float4 overlayColor;  // linear RGB + alpha (0.2)
    float2 mainOffset;    // output px → input px: u = p − mainOffset
    float2 mainSize;      // input plane dims (bounds check)
    float2 sdfCenter;     // main rect center in OUTPUT px
    float2 sdfHalf;       // main rect half extents
    float radius;         // corner radius px (0 = square)
    float blurSigmaNorm;  // reserved
    float2 outputSize;    // canvas dims
    float2 blurTexSize;   // proxy dims (T5)
    float2 pad0;
};

// Signed distance to a rounded rect (yiyin arcTo path semantics, web
// image-tool/index.ts:65-90 — the classic arcTo rounded rectangle IS this
// SDF's boundary).
static inline float sdRoundedRect(
    float2 p, float2 center, float2 halfExt, float radius) {
    float2 q = abs(p - center) - halfExt + float2(radius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Inside coverage with a 1px antialias band (tests sample ≥2px inside/out
// — the T4 alpha profile pins inside=1 / outside=0 away from the band).
static inline float rectCoverage(
    float2 p, float2 center, float2 halfExt, float radius) {
    float sd = sdRoundedRect(p, center, halfExt, radius);
    return 1.0 - smoothstep(-0.5, 0.5, sd);
}

kernel void yiyin_composite(
    texture2d<float, access::read> mainTex [[texture(0)]],
    texture2d<float, access::sample> blurTex [[texture(1)]],  // proxy (T5) / dummy
    texture2d<float, access::read> shadowTex [[texture(2)]],  // shadow (T4) / dummy
    texture2d<float, access::write> output [[texture(3)]],
    constant YiyinCompositeUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= (uint)u.outputSize.x || gid.y >= (uint)u.outputSize.y) { return; }
    float2 p = float2(gid) + 0.5;

    // 1. Background band: solid fill, or the blurred proxy sampled with
    //    NORMALIZED coords (the proxy is aspect-preserving from the main
    //    image — the canvas stretch is the yiyin genBlurImg resize shape).
    float4 out = u.fillColor;
    if (u.hasBlurTex) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        out = blurTex.sample(s, p / u.outputSize);
    }
    if (u.hasOverlay) {
        // yiyin fillRect rgba(g,g,g,0.2) over the backdrop (linear-domain
        // composite — the encoded-domain algebra delta is a recorded
        // L017 容差带 item, 08-1-DECISIONS).
        out.rgb = mix(out.rgb, u.overlayColor.rgb, u.overlayColor.a);
    }

    // 2. Shadow (T4): the pre-blurred SDF alpha darkens beneath the main
    //    image (yiyin shadowColor rgba(0,0,0,1) — full-strength black).
    if (u.hasShadow) {
        float a = shadowTex.read(gid).r;
        out.rgb = mix(out.rgb, float3(0.0), clamp(a, 0.0, 1.0));
    }

    // 3. Main image, 1:1, rounded-rect clipped (radius 0 = the square
    //    path — coverage is the full rect minus a 1px AA edge).
    float2 su = p - u.mainOffset;
    if (su.x >= 0.0 && su.y >= 0.0 && su.x < u.mainSize.x && su.y < u.mainSize.y) {
        float4 m = mainTex.read(uint2(su));
        float cover = rectCoverage(p, u.sdfCenter, u.sdfHalf, u.radius);
        out.rgb = mix(out.rgb, m.rgb, cover);
    }

    out.a = 1.0; // the canvas is opaque (premultiplied convention: a=1)
    output.write(out, gid);
}

kernel void yiyin_shadow_sdf(
    texture2d<float, access::write> output [[texture(0)]],
    constant YiyinCompositeUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= (uint)u.outputSize.x || gid.y >= (uint)u.outputSize.y) { return; }
    float2 p = float2(gid) + 0.5;
    float a = rectCoverage(p, u.sdfCenter, u.sdfHalf, u.radius);
    // Replicated across RGBA — GaussianBlur operates on float4 planes and
    // the composite reads .r.
    output.write(float4(a, a, a, 1.0), gid);
}

struct YiyinDownsampleUniforms {
    float2 srcSize;  // source dims
    float2 dstSize;  // output dims
};

// ─────────────────────────────────────────────────────────────────────────
// yiyin_watermark_row (Plan 08-2 T4; alpha factor fixed 08-3 T0) — one
// text-row composite: the 8-bit sRGB-ENCODED premultiplied row bitmap
// blends OVER the linear display-domain plane. The bitmap stores
// rgb = a × encode(color) (CG 8-bit sRGB premultipliedLast — probe-proven:
// white glyph edges r == a), so the kernel UN-premultiplies in the
// ENCODED domain first, then applies the sRGB EOTF ONCE to the recovered
// color, and scales by the LINEAR coverage. The primaries conversion
// rides the UNIFORM matrix M(sRGB-linear → display-linear) — COLOR-2's
// ColorOutModule-source chain (YiyinColor on the CPU side). Logo opacity
// is already baked into the bitmap alpha (the renderer's global-alpha
// draw). (08-2's first cut re-ran the EOTF over the premultiplied rgb
// AND over the coverage factor — AA edges lost coverage 0.5 → 0.214.)
// ─────────────────────────────────────────────────────────────────────────

struct YiyinRowUniforms {
    int32_t rowW;
    int32_t rowH;
    int32_t destX;    // row top-left on the output plane (plane px)
    int32_t destY;
    int32_t planeW;
    int32_t planeH;
    float pad0;
    float pad1;
    float cm[9];      // M(sRGB-linear → display-linear), ROW-major (COLOR-2)
};

static inline float srgbDecode(float c) {
    // The YiyinColor.linearizeSRGB face (IEC 61966-2-1).
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

kernel void yiyin_watermark_row(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::read> rowTex [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant YiyinRowUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= (uint)u.rowW || gid.y >= (uint)u.rowH) { return; }
    int2 dest = int2(u.destX, u.destY) + int2(gid);
    if (dest.x < 0 || dest.y < 0 || dest.x >= u.planeW || dest.y >= u.planeH) { return; }
    float4 plane = input.read(uint2(dest));
    float4 row = rowTex.read(gid);  // UNORM read = the encoded byte / 255
    float a = clamp(row.a, 0.0, 1.0);
    if (a > 0.0) {
        // Encoded-domain un-premultiply → ONE EOTF pass over the recovered
        // color → linear-coverage alpha factor:
        //   out = a · M·srgbDecode(row.rgb / a) + (1 − a) · plane
        // (coverage `a` is a LINEAR-domain quantity — decoding it through
        // the EOTF again shaved AA edges 0.5 → 0.214; 08-3 T0 fix).
        float3 encColor = clamp(row.rgb / a, 0.0, 1.0);
        float3 linColor = float3(
            srgbDecode(encColor.r), srgbDecode(encColor.g), srgbDecode(encColor.b));
        float3 rowLin = float3(
            dot(float3(u.cm[0], u.cm[1], u.cm[2]), linColor),
            dot(float3(u.cm[3], u.cm[4], u.cm[5]), linColor),
            dot(float3(u.cm[6], u.cm[7], u.cm[8]), linColor));
        plane.rgb = a * rowLin + (1.0 - a) * plane.rgb;
    }
    output.write(plane, uint2(dest));
}

kernel void yiyin_box_downsample(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant YiyinDownsampleUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= (uint)u.dstSize.x || gid.y >= (uint)u.dstSize.y) { return; }
    // Box-average the source rect mapped to this output pixel (clamped —
    // the source may be any size; the rect edges are float-derived).
    uint x0 = (uint)floor(float(gid.x) * u.srcSize.x / u.dstSize.x);
    uint y0 = (uint)floor(float(gid.y) * u.srcSize.y / u.dstSize.y);
    uint x1 = (uint)ceil(float(gid.x + 1) * u.srcSize.x / u.dstSize.x);
    uint y1 = (uint)ceil(float(gid.y + 1) * u.srcSize.y / u.dstSize.y);
    x1 = min(x1, (uint)u.srcSize.x);
    y1 = min(y1, (uint)u.srcSize.y);
    x0 = min(x0, x1 - 1);
    y0 = min(y0, y1 - 1);
    float4 acc = 0.0;
    for (uint y = y0; y < y1; ++y) {
        for (uint x = x0; x < x1; ++x) {
            acc += input.read(uint2(x, y));
        }
    }
    float count = float((x1 - x0) * (y1 - y0));
    output.write(acc / count, gid);
}
