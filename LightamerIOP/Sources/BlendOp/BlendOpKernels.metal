#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// BlendOp kernels (Plan 06-02 T2/T3/T4) — the mask × blend × opacity
// composite triple, ONE kernel per pixel: mask/gopacity fold first (dt
// blend.c:458 CLIP + :530 mask × CLIP(opacity) — the mask plane value IS
// the effective opacity, so the kernel contract reads it directly), then
// the mode formula takes (a, b, effectiveOpacity) exactly like
// dt_develop_blend_process (blend.c:458).
//
// DISPATCHER: `compositeLayer`. The 6-1 degenerate `layer_composite_normal`
// pass is RETIRED by this file (plan T2.3) — the driver dispatches
// "compositeLayer" via MetalContext function lookup (the IOP metallib is
// registered by the app + tests).
//
// L006: full float math — no half anywhere.
//
// MODE TABLE (the uint slots = Lightamer BlendMode rawValues = the dt enum
// slots of the D-06-CONTEXT-2 mapping table — see BlendMode.swift; the
// Swift formula source of truth is BlendOpReference.swift, parity <1e-5
// rel per BlendOpParityTests):
//
//   0x01 normal      → NORMAL2 modern formula (NO legacy clamping)
//   0x02/0x03 lighten/darken (NEW cases, T4 — dt 0x02/0x03 RGB shape)
//   0x04 multiply, 0x07 linearBurn (SUBTRACT a+b−1), 0x09 screen,
//   0x0a overlay, 0x0b softlight, 0x0c hardlight — linear Rec2020,
//      unbounded (unit-domain formula constants, no output clamp except
//      linearBurn's lmin = 0, mirroring dt's clamp in every kernel family)
//   0x10..0x13 luminosity/saturation/hue/color + 0x16 colorAdjust —
//      JzCzhz-domain perceptual modes (plan T3; constants same-source as
//      the filmic/cb chain — see the JZ constants block below)
//   0x17 difference (DIFFERENCE2 scene shape |a−b|)
//   0x2a/0x2b psColorDodge/psColorBurn (NEW raw values, T4 — W3C
//      Compositing-1; outside dt's enum entirely)
//   default → normal (dt's own fallback semantics)
//
// ALPHA: dt overwrites o.w with the effective opacity; Lightamer blends
// alpha as data (opaque-imagery invariant, alpha = 1 preserved) — recorded
// in 06-02-DECISIONS.
// ─────────────────────────────────────────────────────────────────────────

constant uint BLEND_NORMAL      = 0x01;
constant uint BLEND_LIGHTEN     = 0x02;
constant uint BLEND_DARKEN      = 0x03;
constant uint BLEND_MULTIPLY    = 0x04;
constant uint BLEND_LINEARBURN  = 0x07;
constant uint BLEND_SCREEN      = 0x09;
constant uint BLEND_OVERLAY     = 0x0a;
constant uint BLEND_SOFTLIGHT   = 0x0b;
constant uint BLEND_HARDLIGHT   = 0x0c;
constant uint BLEND_LUMINOSITY  = 0x10;
constant uint BLEND_SATURATION  = 0x11;
constant uint BLEND_HUE         = 0x12;
constant uint BLEND_COLOR       = 0x13;
constant uint BLEND_COLORADJUST = 0x16;
constant uint BLEND_DIFFERENCE  = 0x17;
constant uint BLEND_PSDODGE     = 0x2a;
constant uint BLEND_PSBURN      = 0x2b;

/// Swift mirror: `BlendCompositeUniforms` (LayerCompositeDriver.swift) and
/// `BlendOpDispatchUniforms` (BlendOpEngine.swift) — 32-byte constant layout.
/// `rowBegin/rowEnd` gate the write band — the tiling-identity seam (a
/// pointwise kernel must produce byte-identical output split into row-band
/// dispatches or whole; plan 06-02 T5.3 pins this against future
/// neighborhood semantics).
struct BlendOpUniforms {
    float opacity;      // gopacity in [0,1] — the effective opacity source when hasMask == 0
    uint  blendMode;    // BlendMode rawValue (dt slot + no flag bits)
    uint  reverse;      // DEVELOP_BLEND_REVERSE consumption (0/1)
    uint  hasMask;      // 1 = mask plane carries the per-pixel effective opacity
    float blendParam;   // exp2(dt blend_parameter) — the p of multiply (blend.c:1301)
    uint  rowBegin;     // write band [rowBegin, rowEnd) — 0/UINT32_MAX = whole plane
    uint  rowEnd;
    uint  _pad0;
};

// ── Arithmetic modes (linear Rec2020, per channel — BlendOpReference) ──

static float3 blendop_arithmetic(uint mode, float3 a, float3 b, float op, float p) {
    switch (mode) {
    case BLEND_MULTIPLY:
        // dt scene _blend_multiply (blendif_rgb_jzczhz.c:427; blendop.cl:1344)
        return a * (1.0f - op) + a * b * p * op;
    case BLEND_LIGHTEN:
        return a * (1.0f - op) + max(a, b) * op;
    case BLEND_DARKEN:
        return a * (1.0f - op) + min(a, b) * op;
    case BLEND_LINEARBURN:
        // dt SUBTRACT Lab shape a+b−1 (blendop.cl:637-639), lmin = 0 clamp
        return max(a * (1.0f - op) + (a + b - 1.0f) * op, 0.0f);
    case BLEND_SCREEN:
        // blendop.cl:612-615 shape with lmax = 1, unbounded generalization
        return a * (1.0f - op) + (1.0f - (1.0f - a) * (1.0f - b)) * op;
    case BLEND_OVERLAY: {
        // blendop.cl:618-621 (keyed on la, opacity²)
        float op2 = op * op;
        float3 f = select(2.0f * a * b, 1.0f - 2.0f * (1.0f - a) * (1.0f - b), a > 0.5f);
        return a * (1.0f - op2) + f * op2;
    }
    case BLEND_SOFTLIGHT: {
        // blendop.cl:633-636 (keyed on lb, opacity²)
        float op2 = op * op;
        float3 f = select(a * (b + 0.5f), 1.0f - (1.0f - a) * (1.5f - b), b > 0.5f);
        return a * (1.0f - op2) + f * op2;
    }
    case BLEND_HARDLIGHT: {
        // blendop.cl:648-651 (overlay shape keyed on lb, opacity²)
        float op2 = op * op;
        float3 f = select(2.0f * a * b, 1.0f - 2.0f * (1.0f - a) * (1.0f - b), b > 0.5f);
        return a * (1.0f - op2) + f * op2;
    }
    case BLEND_DIFFERENCE:
        // DIFFERENCE2 scene shape (blendif_rgb_jzczhz.c:503)
        return a * (1.0f - op) + abs(a - b) * op;
    case BLEND_PSDODGE: {
        // W3C Compositing-1 color-dodge, per channel
        float3 f;
        for (uint c = 0u; c < 3u; ++c) {
            float cb = a[c], cs = b[c];
            f[c] = (cb == 0.0f) ? 0.0f : (cs >= 1.0f) ? 1.0f : min(1.0f, cb / (1.0f - cs));
        }
        return a * (1.0f - op) + f * op;
    }
    case BLEND_PSBURN: {
        // W3C Compositing-1 color-burn, per channel
        float3 f;
        for (uint c = 0u; c < 3u; ++c) {
            float cb = a[c], cs = b[c];
            f[c] = (cb >= 1.0f) ? 1.0f : (cs <= 0.0f) ? 0.0f : 1.0f - min(1.0f, (1.0f - cb) / cs);
        }
        return a * (1.0f - op) + f * op;
    }
    default:
        // NORMAL2 modern formula + dt's unknown-mode fallback
        return a * (1.0f - op) + b * op;
    }
}

// ── Perceptual modes (JzCzhz domain — plan T3; constants block below) ──

// SAME-SOURCE constants (BlendOpReference.swift header / JzCzhz.swift):
// Rec2020 D65 → XYZ is the project-wide LabRoundTrip.rec2020ToXYZ; the Jz
// matrices are ColorBalanceRGBMath's (dt colorspaces_inline_conversions.h
// :849-975). The effective INVERSE of the 7-digit forward pair used here is
// dt's own 16-digit AI/MI pair — the round-trip asymmetry (~3e-5 rel) is
// dt-inherited and pinned by BlendOpParityTests (matrix/polar legs <1e-6,
// full chain 1e-4 — see the T3 test batch).
constant float3x3 JZ_RGB2XYZ = float3x3(
    float3(0.636958, 0.144617, 0.168881),
    float3(0.262700, 0.678009, 0.059291),
    float3(0.000000, 0.028073, 1.060806));   // rows = matrix rows

constant float3x3 JZ_XYZ2RGB = float3x3(
    float3(1.7166477996, -0.3556625397, -0.2534126027),
    float3(-0.6666717255, 1.6164518040, 0.0157871880),
    float3(0.0176426937, -0.0427775215, 0.9422616447)); // rows = inverse matrix rows

constant float3x3 JZ_M = float3x3(   // X'Y'Z → LMS (dt M_transposed rows)
    float3(0.41478972, 0.579999, 0.0146480),
    float3(-0.2015100, 1.1206490, 0.0531008),
    float3(-0.0166008, 0.264800, 0.6684799));

constant float3x3 JZ_A = float3x3(   // L'M'S' → IzAzBz (dt A_transposed rows)
    float3(0.5, 0.5, 0.0),
    float3(3.524000, -4.066708, 0.542708),
    float3(0.199076, 1.096799, -1.295875));

constant float3x3 JZ_AI = float3x3(  // IzAzBz → L'M'S' (dt AI_trans rows)
    float3(1.0, 0.1386050432715393, 0.0580473161561189),
    float3(1.0, -0.1386050432715393, -0.0580473161561189),
    float3(1.0, -0.0960192420263190, -0.8118918960560390));

constant float3x3 JZ_MI = float3x3(  // LMS → X'Y'Z (dt MI_trans rows)
    float3(1.9242264357876067, -1.0047923125953657, 0.0376514040306180),
    float3(0.3503167620949991, 0.7264811939316552, -0.0653844229480850),
    float3(-0.0909828109828475, -0.3127282905230739, 1.5227665613052603));

static float3 jz_matvec(float3x3 m, float3 v) {
    return float3(dot(m[0], v), dot(m[1], v), dot(m[2], v));
}

static float3 jz_xyz2jab(float3 xyz) {
    // X'Y'Z fold (b = 1.15, g = 0.66)
    float3 t = float3(1.15f * xyz.x - 0.15f * xyz.z,
                      0.66f * xyz.y + 0.34f * xyz.x,
                      xyz.z);
    float3 lms = jz_matvec(JZ_M, t);
    const float n = 0.159301758f, p = 134.034375f;
    const float c1 = 0.8359375f, c2 = 18.8515625f, c3 = 18.6875f;
    for (uint i = 0u; i < 3u; ++i) {
        float x = powr(max(lms[i] / 10000.0f, 0.0f), n);
        lms[i] = powr((c1 + c2 * x) / (1.0f + c3 * x), p);
    }
    float3 jab = jz_matvec(JZ_A, lms);
    const float d = -0.56f, d0 = 1.6295499532821566e-11f;
    jab.x = fmax(((1.0f + d) * jab.x) / (1.0f + d * jab.x) - d0, 0.0f);
    return jab;
}

static float3 jz_jab2xyz(float3 jab) {
    const float d = -0.56f, d0 = 1.6295499532821566e-11f;
    float3 iz = jab;
    iz.x += d0;
    iz.x = fmax(iz.x / (1.0f + d - d * iz.x), 0.0f);
    float3 lms = jz_matvec(JZ_AI, iz);
    const float p_inv = 1.0f / 134.034375f, n_inv = 1.0f / 0.159301758f;
    const float c1 = 0.8359375f, c2 = 18.8515625f, c3 = 18.6875f;
    for (uint i = 0u; i < 3u; ++i) {
        lms[i] = powr(max(lms[i], 0.0f), p_inv);
        lms[i] = 10000.0f * powr(max((c1 - lms[i]) / (c3 * lms[i] - c2), 0.0f), n_inv);
    }
    float3 xyz = jz_matvec(JZ_MI, lms);
    float x = (xyz.x + 0.15f * xyz.z) / 1.15f;
    float y = (xyz.y - 0.34f * x) / 0.66f;
    return float3(x, y, xyz.z);
}

/// Linear Rec2020 → JzCzhz (hz in [0,1) turns; dt_JzAzBz_2_JzCzhz shape).
static float3 jz_rgb2jch(float3 rgb) {
    float3 jab = jz_xyz2jab(jz_matvec(JZ_RGB2XYZ, rgb));
    float h = atan2(jab.z, jab.y) / (2.0f * M_PI_F);
    h = h >= 0.0f ? h : 1.0f + h;
    return float3(jab.x, sqrt(jab.y * jab.y + jab.z * jab.z), h);
}

/// JzCzhz → linear Rec2020 (dt_JzCzhz_2_JzAzBz + inverse chain).
static float3 jz_jch2rgb(float3 jch) {
    float ang = 2.0f * M_PI_F * jch.z;
    float3 jab = float3(jch.x, cos(ang) * jch.y, sin(ang) * jch.y);
    return jz_matvec(JZ_XYZ2RGB, jz_jab2xyz(jab));
}

/// dt hue shortest-path mix (blendop.cl:713-733), hz in turns.
static float jz_mixed_hue(float ha, float hb, float op) {
    float d = fabs(ha - hb);
    float s = d > 0.5f ? -op * (1.0f - d) / d : op;
    float v = (ha * (1.0f - s)) + (hb * s) + 1.0f;
    return v - floor(v); // fmod positive: v ≥ 1 > 0
}

/// The perceptual JzCzhz-mode family (BlendOpReference luminosity /
/// saturation / hue / color / colorAdjust).
static float3 blendop_perceptual(uint mode, float3 a, float3 b, float op) {
    float3 ja = jz_rgb2jch(a);
    float3 jb = jz_rgb2jch(b);
    float3 o;
    switch (mode) {
    case BLEND_LUMINOSITY:   // Jz mixes, Cz/hz ride a ("L 分量直接换")
        o = float3(ja.x * (1.0f - op) + jb.x * op, ja.y, ja.z);
        break;
    case BLEND_SATURATION:   // Cz mixes, Jz/hz ride a
        o = float3(ja.x, ja.y * (1.0f - op) + jb.y * op, ja.z);
        break;
    case BLEND_HUE:          // shortest-path hz mix, Jz/Cz ride a
        o = float3(ja.x, ja.y, jz_mixed_hue(ja.z, jb.z, op));
        break;
    case BLEND_COLOR:        // Cz mixes + hz mix, Jz rides a
        o = float3(ja.x, ja.y * (1.0f - op) + jb.y * op, jz_mixed_hue(ja.z, jb.z, op));
        break;
    case BLEND_COLORADJUST:  // to.x = tb.x UNMIXED (blendop.cl:736) + mixes
        o = float3(jb.x, ja.y * (1.0f - op) + jb.y * op, jz_mixed_hue(ja.z, jb.z, op));
        break;
    default:
        o = ja;
        break;
    }
    return jz_jch2rgb(o);
}

// ── The composite triple kernel ──

// ── L023 probe kernels (plan 06-02 T3) — the EXACT legs of the JzCzhz
// round trip, probed in-shader at float32:
//   mode 0 (matrix legs): rgb → XYZ → rgb (the Rec2020⇄XYZ pair product
//      identity — mo·M·mi ≈ I evaluated, gate <1e-6);
//   mode 1 (polar legs): JzCzhz → JzAzBz → JzCzhz (the cartesian/polar
//      round trip — Jz/Cz/hz 恒等, gate <1e-6 turns).
// The pow-chain legs are pinned by the full-chain round-trip + hue sweep
// against BlendOpReference (measured float32 floor, see the test batch).
kernel void blendop_jz_probe(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant uint& probeMode            [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    float3 v = in.read(gid).rgb;
    float3 r;
    if (probeMode == 0u) {
        r = jz_matvec(JZ_XYZ2RGB, jz_matvec(JZ_RGB2XYZ, v));
    } else {
        float ang = 2.0f * M_PI_F * v.z;
        float3 jab = float3(v.x, cos(ang) * v.y, sin(ang) * v.y);
        float h = atan2(jab.z, jab.y) / (2.0f * M_PI_F);
        h = h >= 0.0f ? h : 1.0f + h;
        r = float3(jab.x, sqrt(jab.y * jab.y + jab.z * jab.z), h);
    }
    out.write(float4(r, 1.0f), gid);
}

kernel void compositeLayer(
    texture2d<float, access::read>  below   [[texture(0)]],
    texture2d<float, access::read>  layerIn [[texture(1)]],
    texture2d<float, access::read>  mask    [[texture(2)]],
    texture2d<float, access::write> out     [[texture(3)]],
    constant BlendOpUniforms&       u       [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    if (gid.y < u.rowBegin || gid.y >= u.rowEnd) { return; }

    float4 A = below.read(gid);
    float4 B = layerIn.read(gid);

    // Effective opacity: the uniform value, or the mask plane's — which
    // dt already folded as gopacity × form (blend.c:458 CLIP + :530), so
    // the kernel consumes it directly (no double multiply).
    float op = (u.hasMask != 0u) ? mask.read(gid).r : u.opacity;

    float3 a = A.rgb;
    float3 b = B.rgb;
    if (u.reverse != 0u) {
        // DEVELOP_BLEND_REVERSE (blend.h:89): swap a/b BEFORE the mode —
        // the dt blend.c pointer-swap semantics.
        float3 t = a;
        a = b;
        b = t;
    }

    float3 rgb;
    switch (u.blendMode) {
    case BLEND_LUMINOSITY:
    case BLEND_SATURATION:
    case BLEND_HUE:
    case BLEND_COLOR:
    case BLEND_COLORADJUST:
        rgb = blendop_perceptual(u.blendMode, a, b, op);
        break;
    default:
        rgb = blendop_arithmetic(u.blendMode, a, b, op, u.blendParam);
        break;
    }

    // Alpha rides the normal mix (opaque-imagery invariant — NOT dt's
    // o.w = opacity overwrite; see file header).
    float alpha = A.w * (1.0f - op) + B.w * op;
    out.write(float4(rgb, alpha), gid);
}
