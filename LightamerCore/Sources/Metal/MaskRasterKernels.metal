#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// Mask raster kernels (Plan 06-03 T4/T5 + T7; 06-RESEARCH §3.2).
//
// Three stages of a drawn mask plane (r32Float, the composite window):
//
//   1. `mask_raster_analytic` — ellipse / path / gradient, PER-PIXEL
//      closed-form evaluation (no accumulation, windowed rendering is
//      naturally exact). The content-anchor leg (D-06-CONTEXT-7) is the
//      inverse projective map `rows0..2` (composite_n → pre-lens_n, built
//      CPU-side from the GeometryPointMapper) + the radial lens leg.
//   2. `mask_stamp_vertex/fragment` — brush stamps accumulate through the
//      FIXED-FUNCTION additive blender into an r32Float target (the T1
//      spike decision D-06-03-T1-1; L018's RMW red line never touched).
//      The falloff is evaluated in IMAGE-space coordinates (per-vertex
//      interpolated) so stamps stay content-anchored under the mapper.
//   3. `mask_fold` — saturate the accumulator to [0,1] (additive stamps
//      may overshoot; eraser stamps are NEGATIVE flow) and premultiply
//      the layer gopacity (the 06-02 mask plane contract D-06-02-T5-3:
//      red channel = the effective per-pixel opacity).
//
// Plus the display leg (T7): `mask_overlay_display` tints the display
// plane yellow where the mask plane is set (dt `blendop_display_channel`
// semantics, blendop.cl:1474+).
//
// Formulas (the float64 Swift references in DrawnMaskRasterTests mirror
// these EXACTLY — the <1e-6 analytic gates compare GPU vs float64):
// - ellipse: quadratic feather on the elliptical radius — the
//   REFORMULATED dt `_fill_mask` shape (ellipse.c:1550-1620; same
//   quadratic falloff, same outer = radius·(1+border)) in a numerically
//   stable form: f = clamp((k−e)/border), value = f², e = the rotated
//   elliptical radius; border = 0 is the guarded hard edge. Divergences
//   (06-03-DECISIONS): dt interpolates a grid, we evaluate per-pixel;
//   the ray-projection algebra is re-expressed to avoid 0/0 at border 0
//   and the float32 cancellation of (total²−radius²).
// - gradient: dt gradient.c:1176-1232 verbatim (rotation sign −, the
//   parabolic curvature term, the linear vs erff profile, distances in
//   diagonal-normalized units). The sigmoidal erff is the
//   Abramowitz-Stegun 7.1.26 rational approximation (max abs err 1.5e-7,
//   inside the 1e-6 gate); dt interpolates the same closed form from a
//   LUT+grid.
// - path: polygon (flattened bézier loop, CPU-subdivided) SDF + ray
//   parity, feather = smoothstep across the border band inward.
//   Self-defined analytic shape (dt's border walk is a grid+UI artifact).
//
// L006: full float math throughout; no half.
// ─────────────────────────────────────────────────────────────────────────────

/// Swift mirror: `MaskRasterUniforms` (DrawnMaskRasterizer.swift) — 11×16B
/// constant chunks (the ashift float3-packing postmortem pattern: every
/// member is a 16-byte SIMD4 on both sides).
struct MaskRasterUniforms {
    float4 rows0;   // projective inverse row 0 (mid_n → pre-lens decode_n)
    float4 rows1;   // row 1
    float4 rows2;   // row 2
    float4 lens;    // k1, k2, hasLens, aspect (frameH/frameW)
    float4 frame;   // frameW, frameH, winOriginX, winOriginY (px)
    float4 window;  // winW, winH, outW, outH (the COMPOSITE frame)
    float4 form0;   // ellipse/gradient: center.x, center.y (width units) | rx, ry
    float4 form1;   // rotationDeg, border, compression, curvature
    float4 misc;    // formType (0 ellipse, 1 path, 2 gradient), gradState, 0, 0
    uint4  bands;   // rowBegin, rowEnd, 0, 0
    // Plan 06-06-T3 staged decomposition (liquify sits between flip and
    // crop, so its inverse legs between two projective stages):
    float4 post0;   // crop⁻¹ stage row 0 (composite_n → mid_n; identity when
    float4 post1;   //   no liquify — the historical single-matrix fold lives
    float4 post2;   //   in rows0..2 unchanged)
    float4 liq0;    // liquify grid: originX, originY (mid px), gridW, gridH
    float4 liq1;    // hasLiquify, midW, midH, 0
};

// cn = the pixel in COMPOSITE-FRAME normalized units ((winOrigin+px)/outSize)
static float2 mask_inverse_content(float2 cn, constant MaskRasterUniforms &u,
                                   const device float2 *liqGrid) {
    // Stage POST (crop⁻¹): composite_n → mid_n (mid = the liquify stage's
    // frame). Identity rows when no liquify segment exists.
    float3 va = float3(cn, 1.0);
    float3 ra = float3(dot(u.post0.xyz, va), dot(u.post1.xyz, va), dot(u.post2.xyz, va));
    float2 midn = ra.xy / ra.z;
    // Liquify leg (Plan 06-06): p = q + F(q) — the warp kernel's sampling
    // map, bilinear over the displacement grid (zero outside its extent).
    // Grid coords are MID pixels (the liquify stage's plane pixels — the
    // L020 same-domain contract with LiquifyDistortionField).
    if (u.liq1.x != 0.0) {
        float2 ppx = midn * u.liq1.yz;
        float2 g = ppx - u.liq0.xy;
        float2 base = floor(g);
        float2 frac = g - base;
        float2 f = float2(0.0);
        for (int j = 0; j <= 1; ++j) {
            for (int i = 0; i <= 1; ++i) {
                float2 cell = base + float2((float)i, (float)j);
                bool inb = (cell.x >= 0.0 && cell.y >= 0.0
                    && cell.x < u.liq0.z && cell.y < u.liq0.w);
                float2 v = inb ? liqGrid[(int)cell.y * (int)u.liq0.z + (int)cell.x]
                               : float2(0.0);
                float w = (i == 0 ? (1.0 - frac.x) : frac.x)
                        * (j == 0 ? (1.0 - frac.y) : frac.y);
                f += v * w;
            }
        }
        ppx += f;
        midn = ppx / u.liq1.yz;
    }
    // Stage PRE (flip/ashift⁻¹): mid_n → pre-lens decode normalized.
    float3 vb = float3(midn, 1.0);
    float3 r = float3(dot(u.rows0.xyz, vb), dot(u.rows1.xyz, vb), dot(u.rows2.xyz, vb));
    float2 pre = r.xy / r.z;
    // radial lens leg (the warp kernel's sampling map): q → c + dir·Rd(u)
    if (u.lens.z != 0.0) {
        float2 d = pre - 0.5;
        float2 da = float2(d.x, d.y * u.lens.w);            // width units
        float u_rad = length(da) * 2.0;                     // halfW units (halfW = W/2 → ×2)
        if (u_rad > 1e-12) {
            float rd = u_rad * (1.0 + u.lens.x * u_rad * u_rad
                                    + u.lens.y * u_rad * u_rad * u_rad * u_rad);
            pre = 0.5 + (d / u_rad) * rd;
        }
    }
    return pre;
}

/// Abramowitz-Stegun 7.1.26 — max abs error 1.5e-7 (the analytic gate's
/// error budget: 1.5e-7 approximation + ~6e-8 float32 ≈ 2.2e-7 < 1e-6).
static float mask_erf(float x) {
    const float p = 0.3275911;
    const float a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741;
    const float a4 = -1.453152027, a5 = 1.061405429;
    float s = x < 0.0 ? -1.0 : 1.0;
    float ax = fabs(x);
    float t = 1.0 / (1.0 + p * ax);
    float y = 1.0 - (((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t) * exp(-ax * ax);
    return s * y;
}

static float mask_eval_form(float2 p, constant MaskRasterUniforms &u,
                            constant float2 *polyline, constant uint &polylineCount) {
    const float aspect = u.lens.w;
    const uint formType = (uint)u.misc.x;

    if (formType == 0u) {
        // ── ellipse: quadratic feather on the elliptical radius ──
        // form0.xy = center NORMALIZED (record domain; kernel converts).
        float2 center = float2(u.form0.x, u.form0.y * aspect);
        float2 d = float2(p.x, p.y * aspect) - center;
        float alpha = u.form1.x * (M_PI_F / 180.0);
        float ca = cos(alpha), sa = sin(alpha);
        // rotate by −rotation into the ellipse frame (dt's x_rot/y_rot)
        float dx = d.x * ca + d.y * sa;
        float dy = -d.x * sa + d.y * ca;
        float rx = u.form0.z, ry = u.form0.w;
        // linear in the SQUARED elliptical radius (no sqrt — the float32
        // precision of the e-domain form leaked ~2e-6 into the band)
        float q = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry);
        float border = u.form1.y;
        float f;
        if (border <= 1e-6) {
            f = q <= 1.0 ? 1.0 : 0.0;                       // guarded hard edge
        } else {
            float k2 = (1.0 + border) * (1.0 + border);
            f = clamp((k2 - q) / (k2 - 1.0), 0.0, 1.0);
        }
        return f * f;
    }

    if (formType == 1u) {
        // ── path: polyline SDF + ray parity, smoothstep border band ──
        float2 pu = float2(p.x, p.y * aspect);              // width units
        float minD = 1e30;
        uint crossings = 0u;
        for (uint i = 0u; i < polylineCount; ++i) {
            float2 a = polyline[i];
            float2 b = polyline[(i + 1u) % polylineCount];
            float2 ab = b - a;
            float2 ap = pu - a;
            float tt = clamp(dot(ap, ab) / max(dot(ab, ab), 1e-20), 0.0, 1.0);
            float2 q = a + tt * ab;
            minD = min(minD, length(pu - q));
            if ((a.y > pu.y) != (b.y > pu.y)) {
                float xint = a.x + (pu.y - a.y) * (b.x - a.x) / (b.y - a.y);
                if (xint > pu.x) { crossings++; }
            }
        }
        bool inside = (crossings & 1u) == 1u;
        float sd = inside ? -minD : minD;                   // −: inside
        float band = u.form1.y;
        if (band <= 1e-6) {
            return sd <= 0.0 ? 1.0 : 0.0;
        }
        float t = clamp(-sd / band, 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }

    // ── gradient (dt gradient.c:1176-1232 verbatim) ──
    float px = p.x * u.frame.x;
    float py = p.y * u.frame.y;
    float wd = u.frame.x, ht = u.frame.y;
    float hwscale = 1.0 / sqrt(wd * wd + ht * ht);
    float vdeg = -u.form1.x * (M_PI_F / 180.0);
    float sinv = sin(vdeg), cosv = cos(vdeg);
    // anchor rides form0 NORMALIZED (dt evaluates anchor·wd / anchor·ht
    // on full-frame pixels)
    float xoff = cosv * u.form0.x * wd + sinv * u.form0.y * ht;
    float yoff = sinv * u.form0.x * wd - cosv * u.form0.y * ht;
    float compression = max(u.form1.z, 0.001);
    float normf = 1.0 / compression;
    float x0 = (cosv * px + sinv * py - xoff) * hwscale;
    float y0 = (sinv * px - cosv * py - yoff) * hwscale;
    float distance = y0 - u.form1.w * x0 * x0;
    float value;
    if ((uint)u.misc.y == 0u) {
        value = 0.5 + 0.5 * (normf * distance);             // linear
    } else {
        value = 0.5 + 0.5 * mask_erf(distance / compression); // sigmoidal
    }
    return clamp(value, 0.0, 1.0);
}

kernel void mask_raster_analytic(
    texture2d<float, access::write> out [[texture(0)]],
    constant MaskRasterUniforms &u [[buffer(0)]],
    constant float2 *polyline [[buffer(1)]],
    constant uint &polylineCount [[buffer(2)]],
    const device float2 *liqGrid [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)u.window.x || gid.y >= (uint)u.window.y) { return; }
    if (gid.y < u.bands.x || gid.y >= u.bands.y) { return; }

    float2 wn = (float2(gid) + 0.5) / u.window.xy;
    float2 cn = (wn * u.window.xy + u.frame.zw) / u.window.zw;
    float2 p = mask_inverse_content(cn, u, liqGrid);
    float v = mask_eval_form(p, u, polyline, polylineCount);
    out.write(float4(v, 0.0, 0.0, 1.0), gid);
}

// ── brush stamps (render-pipeline additive — D-06-03-T1-1) ──

// The vertex output carries the per-instance profile/weight as FLAT
// varyings (all 4 vertices identical — constant across the instance), and
// the fragment RECONSTRUCTS the image-domain point from [[position]]
// through the same inverse-content chain the analytic kernel uses. The
// historical interpolated-attribute variant drifted ~3e-5 (the fixed-
// point rasterizer's sub-pixel snap amplified by the attribute gradient)
// — the reconstruction is exact (06-03-DECISIONS).
struct StampVertex {
    float2 windowPos;   // px in the window
};

struct StampVertOut {
    float4 position [[position]];
    float4 profile  [[flat]];   // cx, cy, radius, hardness (image domain)
    float4 weight   [[flat]];   // flow, aspect, 0, 0
};

vertex StampVertOut mask_stamp_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant StampVertex *verts [[buffer(0)]],
    constant float2 &winSize [[buffer(1)]],
    constant float4 *profiles [[buffer(2)]],
    constant float4 &weight [[buffer(3)]])
{
    StampVertex v = verts[iid * 4u + vid];
    StampVertOut o;
    o.position = float4(2.0 * v.windowPos.x / winSize.x - 1.0,
                        2.0 * v.windowPos.y / winSize.y - 1.0, 0.0, 1.0);
    o.profile = profiles[iid];
    o.weight = weight;
    return o;
}

// flow = density (NEGATIVE = the eraser); the falloff evaluates in the
// IMAGE domain reconstructed from the pixel center — content-anchored
// exactly like the analytic kernel.
fragment float mask_stamp_fragment(
    StampVertOut in [[stage_in]],
    constant MaskRasterUniforms &u [[buffer(0)]],
    const device float2 *liqGrid [[buffer(1)]])
{
    // [[position]] = the pixel center in the render target (= window) px.
    float2 wn = in.position.xy / u.window.xy;
    float2 cn = (wn * u.window.xy + u.frame.zw) / u.window.zw;
    float2 p = mask_inverse_content(cn, u, liqGrid);

    float dxu = p.x - in.profile.x;
    float dyu = (p.y - in.profile.y) * in.weight.y;
    float d = sqrt(dxu * dxu + dyu * dyu);
    float r = in.profile.z;
    if (d >= r) { return 0.0; }
    float hardness = in.profile.w;
    float w;
    if (hardness >= 0.999) {
        w = 1.0;                                            // solid disc
    } else {
        float core = hardness * r;
        w = d <= core ? 1.0 : 1.0 - (d - core) / (r - core);
    }
    return in.weight.x * w;
}

// ── fold: saturate + premultiply gopacity (D-06-02-T5-3) ──

kernel void mask_fold(
    texture2d<float, access::read> acc [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant float4 &params [[buffer(0)]],   // opacity, rowBegin, rowEnd, 0
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) { return; }
    if (gid.y < (uint)params.y || gid.y >= (uint)params.z) { return; }
    float v = acc.read(gid).r;
    out.write(float4(clamp(v, 0.0, 1.0) * params.x, 0.0, 0.0, 1.0), gid);
}

// ── display leg (T7): yellow tint where the mask plane is set ──

kernel void mask_overlay_display(
    texture2d<float, access::read> display [[texture(0)]],
    texture2d<float, access::read> mask [[texture(1)]],
    texture2d<float, access::write> out [[texture(2)]],
    constant float4 &params [[buffer(0)]],   // strength, tint.r, tint.g, tint.b
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) { return; }
    float4 c = display.read(gid);
    float m = clamp(mask.read(gid).r, 0.0, 1.0) * params.x;
    c.rgb = mix(c.rgb, params.yzw, m);
    out.write(c, gid);
}
