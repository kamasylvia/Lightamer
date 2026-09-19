#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// Tonecurve iop kernel (Plan 03-03-T3) — port of Darktable's
// `basic.cl:1426-1490 tonecurve` with the Lab conversion FUSED in (dt's
// pixelpipe hands the module Lab pixels; Lightamer's working space is
// linear Rec2020 — Plan 03-03 Goal).
//
// LUT semantics = dt's NEAREST truncation (color_conversion.h:77-93
// lookup_unbounded + basic.cl:1264 lookup_unbounded_twosided): lut[int(x
// × 0x10000)] below 1.0, power-law extrapolation above / mirrored-left
// for the a/b curves when unbound_ab is set.
//
// The RGB-linked branch works in the Rec2020 working space (dt: ProPhoto)
// and the norm family uses the Rec2020 Y row for LUMINANCE — recorded
// divergences on ToneCurveModule. L006 float32; L008 endEncoding-first.

struct ToneCurveUniforms {
    int   autoscaleAb;     // 0 manual / 1 Lab / 2 XYZ / 3 RGB (dt raw values)
    int   unboundAb;       // 0 clamped a/b LUT, 1 two-sided extrapolation
    int   preserveColors;  // dt_iop_rgb_norms_t raw values
    float lowApproximation; // table_L[0.01 × 0x10000]
};

// coefficient groups: {1/x0, y0, g} per fit
struct TCCoeffs {
    float l0, l1, l2;       // L right
    float ar0, ar1, ar2;    // a right
    float al0, al1, al2;    // a left (mirrored)
    float br0, br1, br2;    // b right
    float bl0, bl1, bl2;    // b left (mirrored)
};

inline float tc_lookup(device const float* lut, const float x) {
    // Rounded index (module header deviation #2) — see colisa_lookup:
    // neutral a_in = 0.5 sits exactly on dt's truncation boundary.
    const uint idx = min((uint)max(x * 65536.0f + 0.5f, 0.0f), 65535u);
    return lut[idx];
}

inline float tc_lookup_unbounded(device const float* lut, const float x,
                                 const float a0, const float a1, const float a2) {
    if (x < 1.0f) return tc_lookup(lut, x);
    return a1 * powr(x * a0, a2);
}

// dt lookup_unbounded_twosided (basic.cl:1264-1289)
inline float tc_lookup_twosided(device const float* lut, const float x,
                                const float r0, const float r1, const float r2,
                                const float l0, const float l1, const float l2) {
    const float xm_r = 1.0f / r0;
    const float xm_l = 1.0f - 1.0f / l0;
    if (x < xm_r && x >= xm_l) return tc_lookup(lut, x);
    if (x >= xm_r) return r1 * powr(x * r0, r2);
    return l1 * powr((1.0f - x) * l0, l2);
}

// dt_rgb_norm (rgb_norms.h) over the working domain; LUMINANCE = the
// Rec2020 Y row (divergence #1).
inline float tc_rgb_norm(const float3 rgb, const int norm) {
    if (norm == 1) {
        return rgb.x * 0.262700f + rgb.y * 0.678009f + rgb.z * 0.059291f;
    } else if (norm == 2) {
        return max(rgb.x, max(rgb.y, rgb.z));
    } else if (norm == 4) {
        return rgb.x + rgb.y + rgb.z;
    } else if (norm == 5) {
        return sqrt(rgb.x * rgb.x + rgb.y * rgb.y + rgb.z * rgb.z);
    } else if (norm == 6) {
        const float r = rgb.x * rgb.x, g = rgb.y * rgb.y, b = rgb.z * rgb.z;
        return (rgb.x * r + rgb.y * g + rgb.z * b) / (r + g + b);
    }
    return (rgb.x + rgb.y + rgb.z) / 3.0f; // average (and the fallback)
}

kernel void tonecurve_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float*             tableL [[buffer(0)]],
    device const float*             tableA [[buffer(1)]],
    device const float*             tableB [[buffer(2)]],
    constant TCCoeffs&              c      [[buffer(3)]],
    constant ToneCurveUniforms&     u      [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    float3 lab = la_rec2020_to_lab(px.rgb);

    const float L_in = lab.x / 100.0f;
    const float L = tc_lookup_unbounded(tableL, L_in, c.l0, c.l1, c.l2);

    if (u.autoscaleAb == 0) {
        // manual a/b curves (tonecurve.c:418-441)
        const float a_in = (lab.y + 128.0f) / 256.0f;
        const float b_in = (lab.z + 128.0f) / 256.0f;
        if (u.unboundAb == 0) {
            lab.y = tc_lookup(tableA, a_in);
            lab.z = tc_lookup(tableB, b_in);
        } else {
            lab.y = tc_lookup_twosided(tableA, a_in, c.ar0, c.ar1, c.ar2, c.al0, c.al1, c.al2);
            lab.z = tc_lookup_twosided(tableB, b_in, c.br0, c.br1, c.br2, c.bl0, c.bl1, c.bl2);
        }
        lab.x = L;
    } else if (u.autoscaleAb == 1) {
        // Lab-linked: correct chroma for the compressed Luminance (:443-455)
        if (L_in > 0.01f) {
            lab.y *= L / lab.x;
            lab.z *= L / lab.x;
        } else {
            lab.y *= u.lowApproximation;
            lab.z *= u.lowApproximation;
        }
        lab.x = L;
    } else if (u.autoscaleAb == 2) {
        // XYZ-linked: the L table re-derived as Y→Y, applied to all three
        // XYZ channels (:457-466)
        float3 xyz = la_lab_to_xyz(lab);
        xyz.x = tc_lookup_unbounded(tableL, xyz.x, c.l0, c.l1, c.l2);
        xyz.y = tc_lookup_unbounded(tableL, xyz.y, c.l0, c.l1, c.l2);
        xyz.z = tc_lookup_unbounded(tableL, xyz.z, c.l0, c.l1, c.l2);
        lab = la_xyz_to_lab(xyz);
    } else if (u.autoscaleAb == 3) {
        // RGB-linked over the WORKING space (dt: ProPhoto — divergence #1)
        float3 rgb = la_lab_to_rec2020(lab);
        if (u.preserveColors == 0) {
            // DT_RGB_NORM_NONE: curve each channel directly (:471-479)
            rgb.x = tc_lookup_unbounded(tableL, rgb.x, c.l0, c.l1, c.l2);
            rgb.y = tc_lookup_unbounded(tableL, rgb.y, c.l0, c.l1, c.l2);
            rgb.z = tc_lookup_unbounded(tableL, rgb.z, c.l0, c.l1, c.l2);
        } else {
            // preserve the norm: scale by curve_lum(norm)/norm (:481-495)
            float ratio = 1.0f;
            const float lum = tc_rgb_norm(rgb, u.preserveColors);
            if (lum > 0.0f) {
                const float curve_lum = tc_lookup_unbounded(tableL, lum, c.l0, c.l1, c.l2);
                ratio = curve_lum / lum;
            }
            rgb *= ratio;
        }
        lab = la_rec2020_to_lab(rgb);
    }

    out.write(float4(la_lab_to_rec2020(lab), px.a), gid);
}
