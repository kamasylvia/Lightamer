#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// soften (Orton) kernels — Plan 04-05-T3, IOP-DETAIL-03 (op "soften",
// v50 slot 66.0).
//
// Darktable reference: `src/iop/soften.c` (tree dc58cf0ba1) +
// `data/kernels/soften.cl` — RGB LINEAR-domain Orton effect:
//   1. `soften_overexposed` RGB→HSL, s × saturation, l × brightness
//      (colorspaces.h rgb2hsl/hsl2rgb, s/l clipped to [0,1],
//      brightness factor = 1/2^(−brightness) = 2^brightness)
//   2. h/v gaussian blur  (dt: `dt_box_mean` 8 iterations; WE use the
//                          shared Deriche IIR at dt's σ correlation —
//                          DECISIONS D4, see the module header)
//   3. `soften_mix`       out = in·(1−amt) + clip(blurred)·amt, alpha
//                          rides the original (`soften.cl:164-165`)
//
// where amt = amount/100. clip4 = clamp to [0,1] (`common.h:226`).
//
// FLAT-FIELD IDENTITY (D5): saturation 100% (×1) + brightness 0 EV (×1)
// ⇒ overexposed is identity ⇒ blur of a flat is the flat ⇒ the mix is
// the flat at ANY amount. The T3 acceptance's soften-flat probe pins it.
//
// L006: float32 only. L008: endEncoding precedes commit (dispatch helpers).
// ─────────────────────────────────────────────────────────────────────────

// colorspaces.h rgb2hsl (dt verbatim, float path).
static inline void soften_rgb2hsl(float3 rgb, thread float &h, thread float &s, thread float &l) {
    const float pmax = max(max(rgb.r, rgb.g), rgb.b);
    const float pmin = min(min(rgb.r, rgb.g), rgb.b);
    const float delta = pmax - pmin;
    float hv = 0.0f, sv = 0.0f;
    const float lv = (pmin + pmax) * 0.5f;
    if (delta != 0.0f) {
        sv = lv < 0.5f ? delta / max(pmax + pmin, 1.52587890625e-05f)
                       : delta / max(2.0f - pmax - pmin, 1.52587890625e-05f);
        if (pmax == rgb.r) hv = (rgb.g - rgb.b) / delta;
        else if (pmax == rgb.g) hv = 2.0f + (rgb.b - rgb.r) / delta;
        else hv = 4.0f + (rgb.r - rgb.g) / delta;
        hv /= 6.0f;
        if (hv < 0.0f) hv += 1.0f;
        else if (hv > 1.0f) hv -= 1.0f;
    }
    h = hv; s = sv; l = lv;
}

// colorspaces.h hue2rgb + hsl2rgb (dt verbatim).
static inline float soften_hue2rgb(float m1, float m2, float hue) {
    if (hue < 1.0f) return m1 + (m2 - m1) * hue;
    else if (hue < 3.0f) return m2;
    else return hue < 4.0f ? (m1 + (m2 - m1) * (4.0f - hue)) : m1;
}

static inline float3 soften_hsl2rgb(float h, float s, float l) {
    if (s == 0.0f) return float3(l, l, l);
    const float m2 = l < 0.5f ? l * (1.0f + s) : l + s - l * s;
    const float m1 = 2.0f * l - m2;
    const float hh = h * 6.0f;
    return float3(
        soften_hue2rgb(m1, m2, hh < 4.0f ? hh + 2.0f : hh - 4.0f),
        soften_hue2rgb(m1, m2, hh),
        soften_hue2rgb(m1, m2, hh > 2.0f ? hh - 2.0f : hh + 4.0f));
}

struct SoftenOverUniforms {
    float saturation;   // d->saturation / 100
    float brightness;   // 2^d->brightness (soften.c:120 — 1/exp2(−b))
    float pad0;
    float pad1;
};

// Step 1 — the overexposed image (`soften.cl:35-40` verbatim shape:
// RGB→HSL, clip(s·sat), clip(l·bri), HSL→RGB).
kernel void soften_overexposed(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant SoftenOverUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float4 px = in.read(gid);
    float h, s, l;
    soften_rgb2hsl(px.rgb, h, s, l);
    s = clamp(s * u.saturation, 0.0f, 1.0f);
    l = clamp(l * u.brightness, 0.0f, 1.0f);
    out.write(float4(soften_hsl2rgb(h, s, l), px.a), gid);
}

struct SoftenMixUniforms {
    float amount;       // d->amount / 100
    float pad0;
    int2 srcOffset;     // roiOut.xy − roiIn.xy (0 under tiling)
    // NOTE: NO pad2 — struct is 4+4+8 = 16 bytes both sides (Swift drops
    // it too; the ashift float-array packing postmortem).
};

// Step 3 — the mix (`soften.cl:164-165` verbatim:
// `original·(1−a) + clip(processed)·a`, alpha rides the original).
kernel void soften_mix(
    texture2d<float, access::read>  in      [[texture(0)]],
    texture2d<float, access::read>  blurred [[texture(1)]],
    texture2d<float, access::write> out     [[texture(2)]],
    constant SoftenMixUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint2 src = uint2(int2(gid) + u.srcOffset);
    const float4 orig = in.read(src);
    const float4 proc = blurred.read(src);
    const float3 clipped = clamp(proc.rgb, 0.0f, 1.0f);
    out.write(float4(orig.rgb * (1.0f - u.amount) + clipped * u.amount, orig.a), gid);
}
