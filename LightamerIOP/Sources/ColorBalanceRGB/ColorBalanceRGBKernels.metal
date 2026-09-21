#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// colorbalancergb kernel (Plan 05-02-T2, IOP-COLOR-01) — verbatim MSL port
// of data/kernels/extended.cl:752-1042 (tree dc58cf0ba1), `mask_display`
// checkerboard branch EXCLUDED (Phase 6 masking domain — module header
// records the cut).
//
// Buffer 0 (device float*, ColorBalanceRGBModule.commitParams — 64
// uniforms, row-major 3×3 matrices):
//   [0..3]   global (grading RGB offset, w lane 0)
//   [4..7]   shadows (slope, neutral 1)
//   [8..11]  highlights (slope, neutral 1)
//   [12..15] midtones (reciprocal slope, neutral 1)
//   [16..19] chroma (shadows/midtones/highlights + 0 lane)
//   [20..23] saturation (shadows/midtones/highlights + 0 lane)
//   [24..27] brilliance (shadows/midtones/highlights + 0 lane)
//   [28] chroma_global  [29] saturation_global  [30] brilliance_global
//   [31] vibrance  [32] contrast (= 1+p)  [33] grey_fulcrum
//   [34..37] hue rotation (cos, -sin, sin, cos — process :654-657)
//   [38] shadows_weight (= 2+2p)  [39] highlights_weight
//   [40] midtones_weight (derived)  [41] mask_grey_fulcrum (^0.41)
//   [42] white_fulcrum (= exp2)  [43] midtones_Y (= 1/(1+p))
//   [44] L_white  [45] saturation formula (0 JzAzBz / 1 DTUCS)
//   [46..54] matrix_in   [55..63] matrix_out (row-major 3×3)
// Buffer 1 (device float*, 512-entry gamut LUT).
//
// INPUT: linear Rec2020 scene RGB float32 (L006: no half). Negative
// pipeline RGB clipped on read (extended.cl:773); alpha restored from
// input (the CL leg semantics — CPU leg's for_four_channels divergence
// recorded on the module).
// ─────────────────────────────────────────────────────────────────────────

inline float4 cb_mul9(device const float *m, const float4 v)
{
    return float4(
        m[0] * v.x + m[1] * v.y + m[2] * v.z,
        m[3] * v.x + m[4] * v.y + m[5] * v.z,
        m[6] * v.x + m[7] * v.y + m[8] * v.z,
        v.w);
}

// NOTE (05-02 D2): row-major kernel form = dt-exact (apply_transposed
// with _trans storage + C-harness cb_verify proof; M*L = I verified).
inline float4 cb_grading_to_lms(const float4 rgb)
{
    return float4(
        0.95f * rgb.x + 0.38f * rgb.y,
        0.05f * rgb.x + 0.62f * rgb.y + 0.03f * rgb.z,
        0.97f * rgb.z,
        rgb.w);
}

inline float4 cb_lms_to_grading(const float4 lms)
{
    return float4(
        1.0877193f * lms.x - 0.66666667f * lms.y + 0.02061856f * lms.z,
        -0.0877193f * lms.x + 1.66666667f * lms.y - 0.05154639f * lms.z,
        1.03092784f * lms.z,
        lms.w);
}

// colorspace.h:509-543.
inline float4 cb_lms_to_yrg(const float4 lms)
{
    const float y = 0.68990272f * lms.x + 0.34832189f * lms.y;
    const float a = lms.x + lms.y + lms.z;
    const float4 nlms = (a == 0.0f) ? float4(0.0f) : lms / a;
    const float4 rgb = cb_lms_to_grading(nlms);
    return float4(y, rgb.x, rgb.y, lms.w);
}

inline float4 cb_yrg_to_lms(const float4 yrg)
{
    const float y = yrg.x;
    const float r = yrg.y;
    const float g = yrg.z;
    const float b = 1.0f - r - g;
    const float4 lms = cb_grading_to_lms(float4(r, g, b, 0.0f));
    const float denom = 0.68990272f * lms.x + 0.34832189f * lms.y;
    const float a = (denom == 0.0f) ? 0.0f : y / denom;
    return lms * a;
}

// colorspace.h:555-585.
inline float4 cb_yrg_to_ych(const float4 yrg)
{
    const float r = yrg.y - 0.21902143f;
    const float g = yrg.z - 0.54371398f;
    const float c = sqrt(g * g + r * r);
    return float4(yrg.x, c, c != 0.0f ? r / c : 1.0f, c != 0.0f ? g / c : 0.0f);
}

inline float4 cb_ych_to_yrg(const float4 ych)
{
    return float4(ych.x, ych.y * ych.z + 0.21902143f, ych.y * ych.w + 0.54371398f, 0.0f);
}

// colorspace.h:747-780.
inline float4 cb_gamut_check_yrg(float4 ych)
{
    const float4 yrg = cb_ych_to_yrg(ych);
    float max_c = ych.y;
    if (yrg.y < 0.0f) max_c = fmin(-0.21902143f / ych.z, max_c);
    if (yrg.z < 0.0f) max_c = fmin(-0.54371398f / ych.w, max_c);
    if (yrg.y + yrg.z > 1.0f)
        max_c = fmin((1.0f - 0.21902143f - 0.54371398f) / (ych.z + ych.w), max_c);
    ych.y = max_c;
    return ych;
}

// extended.cl:725-744.
inline float4 cb_opacity_masks(
    const float x, const float sw, const float hw, const float mw, const float fulcrum)
{
    const float x_off = x - fulcrum;
    const float x_norm = x_off / fulcrum;
    const float alpha = 1.0f / (1.0f + exp(x_norm * sw));
    const float beta = 1.0f / (1.0f + exp(-x_norm * hw));
    const float gamma = exp(-x_off * x_off * mw / 4.0f)
        * (1.0f - alpha) * (1.0f - alpha) * (1.0f - beta) * (1.0f - beta) * 8.0f;
    return float4(alpha, gamma, beta, 0.0f);
}

// colorspace.h:945-975 (soft_clip + lookup_gamut; LUT_ELEM = 512,
// math.h:26).
inline float cb_soft_clip(const float x, const float soft, const float hard)
{
    const float norm = hard - soft;
    return (x > soft) ? soft + (1.0f - exp(-(x - soft) / norm)) * norm : x;
}

inline float cb_lookup_gamut(device const float *lut, const float h)
{
    const float pi = 3.141592653589793f;
    const float x_test = 512.0f * (h + pi) / (2.0f * pi);
    const float x_prev = floor(x_test);
    const float x_next = ceil(x_test);
    const int xi = ((int)x_prev) & 511;
    const int xii = ((int)x_next) & 511;
    const float y_prev = lut[xi];
    return y_prev + ((xi != xii) ? (x_test - x_prev) * (lut[xii] - y_prev) : 0.0f);
}

// colorspace.h:342-433 — JzAzBz ⇄ XYZ D65.
inline float4 cb_xyz_to_jzazbz(float4 xyz)
{
    float4 t1 = float4(
        1.15f * xyz.x - 0.15f * xyz.z,
        0.66f * xyz.y + 0.34f * xyz.x,
        xyz.z, 0.0f);
    float4 t2 = float4(
        0.41478972f * t1.x + 0.579999f * t1.y + 0.0146480f * t1.z,
        -0.2015100f * t1.x + 1.120649f * t1.y + 0.0531008f * t1.z,
        -0.0166008f * t1.x + 0.264800f * t1.y + 0.6684799f * t1.z,
        0.0f);
    t2.xyz = pow(max(t2.xyz / 10000.0f, 0.0f), 0.159301758f);
    t2.xyz = pow(
        (0.8359375f + 18.8515625f * t2.xyz) / (1.0f + 18.6875f * t2.xyz),
        134.034375f);
    t1 = float4(
        0.5f * t2.x + 0.5f * t2.y,
        3.524000f * t2.x - 4.066708f * t2.y + 0.542708f * t2.z,
        0.199076f * t2.x + 1.096799f * t2.y - 1.295875f * t2.z,
        0.0f);
    t1.x = max(0.44f * t1.x / (1.0f - 0.56f * t1.x) - 1.6295499532821566e-11f, 0.0f);
    return t1;
}

inline float4 cb_jzazbz_to_xyz(const float4 jab)
{
    const float d = -0.56f;
    const float d0 = 1.6295499532821566e-11f;
    float4 iz = jab;
    iz.x += d0;
    iz.x = max(iz.x / (1.0f + d - d * iz.x), 0.0f);
    float4 lms = float4(
        iz.x + 0.1386050432715393f * iz.y + 0.0580473161561189f * iz.z,
        iz.x - 0.1386050432715393f * iz.y - 0.0580473161561189f * iz.z,
        iz.x - 0.0960192420263190f * iz.y - 0.8118918960560390f * iz.z,
        0.0f);
    lms.xyz = pow(max(lms.xyz, 0.0f), 1.0f / 134.034375f);
    lms.xyz = 10000.0f * pow(max((0.8359375f - lms.xyz) / (18.6875f * lms.xyz - 18.8515625f), 0.0f), 1.0f / 0.159301758f);
    float4 xyz = float4(
        1.9242264357876067f * lms.x - 1.0047923125953657f * lms.y + 0.0376514040306180f * lms.z,
        0.3503167620949991f * lms.x + 0.7264811939316552f * lms.y - 0.0653844229480850f * lms.z,
        -0.0909828109828475f * lms.x - 0.3127282905230739f * lms.y + 1.5227665613052603f * lms.z,
        0.0f);
    float4 out;
    out.x = (xyz.x + 0.15f * xyz.z) / 1.15f;
    // dt: Y = (Y' + (g−1)·X)/g, g−1 = −0.34 (bisect 2026-09-21 — plus
    // here broke the JzAzBz round trip, Y 0.99 vs 0.5).
    out.y = (xyz.y - 0.34f * out.x) / 0.66f;
    out.z = xyz.z;
    out.w = jab.w;
    return out;
}

// colorspace.h:618-660 — XYZ D65 ⇄ xyY.
inline float4 cb_xyz_to_xyy(float4 xyz)
{
    xyz = max(xyz, 0.0f);
    const float sum = xyz.x + xyz.y + xyz.z;
    float4 xyY;
    xyY.x = (sum > 0.0f) ? xyz.x / sum : 0.31271f;
    xyY.y = (sum > 0.0f) ? xyz.y / sum : 0.32902f;
    xyY.z = xyz.y;
    xyY.w = xyz.w;
    return xyY;
}

inline float4 cb_xyy_to_xyz(const float4 xyy)
{
    float4 xyz = float4(0.0f);
    if (xyy.y != 0.0f) {
        xyz.x = xyy.z * xyy.x / xyy.y;
        xyz.y = xyy.z;
        xyz.z = xyy.z * (1.0f - xyy.x - xyy.y) / xyy.y;
    }
    xyz.w = xyy.w;
    return xyz;
}

// colorspace.h:791-849 — UCS L_star + xyY → JCH.
inline float cb_y_to_lstar(const float y)
{
    const float y_hat = pow(y, 0.631651345306265f);
    return 2.098883786377f * y_hat / (y_hat + 1.12426773749357f);
}

inline float cb_lstar_to_y(const float l)
{
    return pow((1.12426773749357f * l / (2.098883786377f - l)), 1.5831518565279648f);
}

inline float4 cb_xyy_to_jch(const float4 xyy, const float l_white)
{
    const float4 xf = float4(-0.783941002840055f, 0.745273540913283f, 0.318707282433486f, 0.0f);
    const float4 yf = float4(0.277512987809202f, -0.205375866083878f, 2.16743692732158f, 0.0f);
    const float4 off = float4(0.153836578598858f, -0.165478376301988f, 0.291320554395942f, 0.0f);
    float4 uvd = xf * xyy.x + yf * xyy.y + off;
    const float div = (uvd.z >= 0.0f) ? max(FLT_MIN, uvd.z) : min(-FLT_MIN, uvd.z);
    uvd.xy /= div;
    const float2 uv_star = float2(
        1.39656225667f * uvd.x / (fabs(uvd.x) + 1.49217352929f),
        1.4513954287f * uvd.y / (fabs(uvd.y) + 1.52488637914f));
    const float2 p = float2(
        -1.124983854323892f * uv_star.x - 0.980483721769325f * uv_star.y,
        1.86323315098672f * uv_star.x + 1.971853092390862f * uv_star.y);
    const float m2 = p.x * p.x + p.y * p.y;
    const float l_star = cb_y_to_lstar(clamp(xyy.z, 0.0f, 1e8f));
    return float4(
        l_star / l_white,
        15.932993652962535f * pow(l_star, 0.6523997524738018f) * pow(m2, 0.6007557017508491f) / l_white,
        atan2(p.y, p.x), 0.0f);
}

// colorspace.h:845-890 — UCS JCH → xyY.
inline float4 cb_jch_to_xyy(const float4 jch, const float l_white)
{
    const float l_star = clamp(jch.x * l_white, 0.0f, 2.09885f);
    const float m = (l_star != 0.0f)
        ? pow(jch.y * l_white / (15.932993652962535f * pow(l_star, 0.6523997524738018f)), 0.8322850678616855f)
        : 0.0f;
    const float up = m * cos(jch.z);
    const float vp = m * sin(jch.z);
    const float2 uv_star = float2(
        -5.037522385190711f * up - 2.504856328185843f * vp,
        4.760029407436461f * up + 2.874012963239247f * vp);
    const float2 uv = float2(
        -1.49217352929f * uv_star.x / (fabs(uv_star.x) - 1.39656225667f),
        -1.52488637914f * uv_star.y / (fabs(uv_star.y) - 1.4513954287f));
    const float4 xyD = float4(
        0.167171472114775f * uv.x + 0.141299802443708f * uv.y - 0.00801531300850582f,
        -0.150959086409163f * uv.x - 0.155185060382272f * uv.y - 0.00843312433578007f,
        0.940254742367256f * uv.x + 1.000000000000000f * uv.y - 0.0256325967652889f,
        0.0f);
    const float div = (xyD.z >= 0.0f) ? max(FLT_MIN, xyD.z) : min(-FLT_MIN, xyD.z);
    return float4(xyD.x / div, xyD.y / div, cb_lstar_to_y(l_star), 0.0f);
}

// colorspace.h:890-929 — JCH ⇄ HSB/HCB.
inline float4 cb_jch_to_hsb(const float4 jch)
{
    const float b = jch.x * (pow(jch.y, 1.33654221029386f) + 1.0f);
    return float4(jch.z, b > 0.0f ? jch.y / b : 0.0f, b, 0.0f);
}

inline float4 cb_hsb_to_jch(const float4 hsb)
{
    const float c = hsb.y * hsb.z;
    return float4(hsb.z / (pow(c, 1.33654221029386f) + 1.0f), c, hsb.x, 0.0f);
}

inline float4 cb_jch_to_hcb(const float4 jch)
{
    return float4(jch.z, jch.y, jch.x * (pow(jch.y, 1.33654221029386f) + 1.0f), 0.0f);
}

inline float4 cb_hcb_to_jch(const float4 hcb)
{
    return float4(hcb.z / (pow(hcb.y, 1.33654221029386f) + 1.0f), hcb.y, hcb.x, 0.0f);
}

// LMS 2006 ⇄ XYZ D65 (colorspace.h:454-481).
inline float4 cb_lms_to_xyz(const float4 lms)
{
    return float4(
        1.80794659f * lms.x - 1.29971660f * lms.y + 0.34785879f * lms.z,
        0.61783960f * lms.x + 0.39595453f * lms.y - 0.04104687f * lms.z,
        -0.12546960f * lms.x + 0.20478038f * lms.y + 1.74274183f * lms.z,
        lms.w);
}

// ─────────────────────────────────────────────────────────────────────────
// The single-pass pixel chain (extended.cl:769-1009, mask_display leg
// removed — RGB.w restored from input).
// ─────────────────────────────────────────────────────────────────────────
kernel void colorbalancergb(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float *u [[buffer(0)]],
    device const float *gamut_lut [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    device const float *matrix_in = u + 46;
    device const float *matrix_out = u + 55;

    float4 pix_in = fmax(0.0f, in.read(gid));

    float4 rgb = pix_in;

    // CIE 2006 LMS D65 → Filmlight Yrg → Ych.
    float4 lms = cb_mul9(matrix_in, rgb);
    float4 yrg = cb_lms_to_yrg(lms);
    float4 ych = cb_yrg_to_ych(yrg);

    // No negative luminance.
    ych.x = max(ych.x, 0.0f);
    float4 opacities = cb_opacity_masks(
        pow(ych.x, 0.4101205819200422f),
        u[38], u[39], u[40], u[41]);
    float4 opacities_comp = 1.0f - opacities;

    // Hue shift at output hue (rotation matrix :654-657).
    const float cos_h = ych.z;
    const float sin_h = ych.w;
    ych.z = u[34] * cos_h + u[35] * sin_h;
    ych.w = u[36] * cos_h + u[37] * sin_h;

    // Chroma boost + vibrance (extended.cl:807). Guard pow(0,0) at
    // vibrance == 0 (dt CPU powf(0,0) = 1 → vib = 0; native powr
    // undefined there).
    const float chroma_boost = u[28] + dot(opacities, float4(u[16], u[17], u[18], u[19]));
    const float vib = (u[31] == 0.0f) ? 0.0f : u[31] * (1.0f - pow(ych.y, fabs(u[31])));
    const float chroma_factor = max(1.0f + chroma_boost + vib, 0.0f);
    ych.y *= chroma_factor;

    // Constant-Y/hue chroma clip.
    ych = cb_gamut_check_yrg(ych);

    // Back through Yrg/LMS to grading RGB.
    yrg = cb_ych_to_yrg(ych);
    lms = cb_yrg_to_lms(yrg);
    rgb = cb_lms_to_grading(lms);

    // Color balance: global offset.
    rgb += float4(u[0], u[1], u[2], u[3]);

    // Shadows/highlights dual-slope mask (:829).
    rgb *= opacities_comp.z * (opacities_comp.x + opacities.x * float4(u[4], u[5], u[6], u[7]))
        + opacities.z * float4(u[8], u[9], u[10], u[11]);

    // Midtones power with sign preservation.
    rgb = sign(rgb) * pow(fabs(rgb) / u[42], float4(u[12], u[13], u[14], u[15])) * u[42];

    // Non-linear ops need Yrg again (RGB doesn't preserve color).
    lms = cb_grading_to_lms(rgb);
    yrg = cb_lms_to_yrg(lms);

    // Y midtones power + Y fulcrumed contrast.
    yrg.x = pow(max(yrg.x / u[42], 0.0f), u[43]) * u[42];
    yrg.x = u[33] * pow(yrg.x / u[33], u[32]);

    lms = cb_yrg_to_lms(yrg);
    float4 xyz = cb_lms_to_xyz(lms);

    // Perceptual saturation/brilliance + gamut mapping.
    if (u[45] == 0.0f) {
        float4 jab = cb_xyz_to_jzazbz(xyz);
        float jc[2] = { jab.x, length(jab.yz) };
        const float h = atan2(jab.z, jab.y);

        const float ang = atan2(jc[1], jc[0]);
        const float sin_t = sin(ang);
        const float cos_t = cos(ang);
        float so[2];
        const float boosts[2] = {
            1.0f + u[30] + dot(opacities, float4(u[24], u[25], u[26], u[27])),
            u[29] + dot(opacities, float4(u[20], u[21], u[22], u[23])),
        };
        so[0] = jc[0] * cos_t + jc[1] * sin_t;
        so[1] = so[0] * clamp(ang * boosts[1], -ang, 1.5707963267948966f - ang);
        so[0] = max(so[0] * boosts[0], 0.0f);

        // M_rot_inv rows (:785-786): [cos,-sin] / [sin,cos].
        jc[0] = max(so[0] * cos_t - so[1] * sin_t, 0.0f);
        jc[1] = max(so[0] * sin_t + so[1] * cos_t, 0.0f);

        const float out_max_sat_h = cb_lookup_gamut(gamut_lut, h);
        const float sat = (jc[0] > 0.0f)
            ? cb_soft_clip(jc[1] / jc[0], 0.8f * out_max_sat_h, out_max_sat_h)
            : out_max_sat_h;
        const float max_c_at_sat = jc[0] * sat;
        const float max_j_at_sat = (sat > 0.0f) ? jc[1] / sat : jc[0];
        jc[0] = (jc[0] + max_j_at_sat) / 2.0f;
        jc[1] = (jc[1] + max_c_at_sat) / 2.0f;

        const float cos_h2 = cos(h);
        const float sin_h2 = sin(h);
        const float d0 = 1.6295499532821566e-11f;
        const float d = -0.56f;
        float iz = jc[0] + d0;
        iz /= (1.0f + d - d * iz);
        iz = max(iz, 0.0f);

        const float3 ai0 = float3(1.0f, 0.1386050432715393f, 0.0580473161561189f);
        const float3 ai1 = float3(1.0f, -0.1386050432715393f, -0.0580473161561189f);
        const float3 ai2 = float3(1.0f, -0.0960192420263190f, -0.8118918960560390f);
        float3 test_lms = float3(
            dot(ai0, float3(iz, jc[1] * cos_h2, jc[1] * sin_h2)),
            dot(ai1, float3(iz, jc[1] * cos_h2, jc[1] * sin_h2)),
            dot(ai2, float3(iz, jc[1] * cos_h2, jc[1] * sin_h2)));

        float max_c = jc[1];
        if (test_lms.x < 0.0f)
            max_c = min(-iz / (ai0.y * cos_h2 + ai0.z * sin_h2), max_c);
        if (test_lms.y < 0.0f)
            max_c = min(-iz / (ai1.y * cos_h2 + ai1.z * sin_h2), max_c);
        if (test_lms.z < 0.0f)
            max_c = min(-iz / (ai2.y * cos_h2 + ai2.z * sin_h2), max_c);

        jab.x = jc[0];
        jab.y = max_c * cos_h2;
        jab.z = max_c * sin_h2;
        xyz = cb_jzazbz_to_xyz(jab);
    } else {
        float4 xyy = cb_xyz_to_xyy(xyz);
        float4 jch = cb_xyy_to_jch(xyy, u[44]);
        float4 hcb = cb_jch_to_hcb(jch);

        const float radius = length(hcb.yz);
        const float sin_t = (radius > 0.0f) ? hcb.y / radius : 0.0f;
        const float cos_t = (radius > 0.0f) ? hcb.z / radius : 0.0f;

        const float p = max(FLT_MIN, hcb.y);
        const float w = sin_t * hcb.y + cos_t * hcb.z;

        float a = max(1.0f + u[29] + dot(opacities, float4(u[20], u[21], u[22], u[23])), 0.0f);
        const float b = max(1.0f + u[30] + dot(opacities, float4(u[24], u[25], u[26], u[27])), 0.0f);

        const float max_a = length(float2(p, w)) / p;
        a = cb_soft_clip(a, 0.5f * max_a, max_a);

        const float p_prime = (a - 1.0f) * p;
        const float w_prime = sqrt(p * p * (1.0f - a * a) + w * w) * b;

        hcb.y = max(cos_t * p_prime + sin_t * w_prime, 0.0f);
        hcb.z = max(-sin_t * p_prime + cos_t * w_prime, 0.0f);

        jch = cb_hcb_to_jch(hcb);

        const float max_colorfulness = cb_lookup_gamut(gamut_lut, jch.z);
        const float max_chroma = 15.932993652962535f * pow(jch.x * u[44], 0.6523997524738018f)
            * pow(max_colorfulness, 0.6007557017508491f) / u[44];
        float4 boundary = float4(jch.x, max_chroma, jch.z, 0.0f);
        float4 hsb_boundary = cb_jch_to_hsb(boundary);

        float4 hsb = float4(hcb.x, (hcb.z > 0.0f) ? hcb.y / hcb.z : 0.0f, hcb.z, 0.0f);
        hsb.y = cb_soft_clip(hsb.y, 0.8f * hsb_boundary.y, hsb_boundary.y);

        jch = cb_hsb_to_jch(hsb);
        xyy = cb_jch_to_xyy(jch, u[44]);
        xyz = cb_xyy_to_xyz(xyy);
    }

    // Back to pipeline RGB.
    rgb = cb_mul9(matrix_out, xyz);
    rgb = max(rgb, 0.0f);
    rgb.w = pix_in.w;

    out.write(rgb, gid);
}
