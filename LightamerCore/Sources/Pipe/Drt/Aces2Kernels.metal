#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// Aces2Kernels — the ACES 2.0 per-pixel compute kernel (Plan M2-6-2 T4,
// KD-5 / OQ-10-A). Lives in LightamerCore next to the pixelpipe (the
// TerminalKernels placement rule — zero IOP dependency for tests/golden).
//
// PROVENANCE: Portions Copyright Contributors to the ACES Project
// (aces-core v2.0 main, 069b0bc3; Apache-2.0 — see NOTICE); ported via the
// Float64 authority below, formulas re-derived in the math form.
//
// STRUCTURE: a stage-for-stage mirror of `Aces2Reference.swift` ([0]..[7]
// below reference that file's structure map) — the Float64 file is the
// algorithm authority. ONE kernel, ONE PSO, parameters ride ONE MTLBuffer
// (Aces2Uniforms — a flat float4 plane, 588 float4 = 9408 bytes; zero
// function constants, a param drag re-uploads and recompiles NOTHING —
// the M2-6-1 KD-4 shape). The per-point CAM16/tonescale/gamut TABLES are
// CPU-built (Float64, deterministic) and ride the buffer.
//
// CONSTANT RESTATEMENTS (the M2-6-1 KD-2 discipline): the only in-file
// constants are the upstream-fixed viewing/environment scalars (27.13,
// 400, 100) and the RGC parameter table (1.147/1.264/1.312, 0.815/0.803/
// 0.880, 1.2 — the v1.3 LMT table) plus the four gamut-shape scalars
// (0.12 smooth_cusps, 1.3 cusp_mid_blend, 0.3 focus_gain_blend, 0.75
// compression_threshold). Every per-params number rides the buffer from
// the Swift single source. The golden tests pin the whole chain against
// the Float64 reference (≤1e-5 p99.9 band), so a restatement drift
// cannot survive.
//
// OUTPUT CONTRACT: peak-normalized display-linear limiting-space RGB
// (1.0 = peak nits) — the EotfBox encodes (KD-4 separation, stage [7]).
//
// L006: full float math everywhere — no half on the DRT path.
// ─────────────────────────────────────────────────────────────────────────────

// The uniform ABI (mirrors Aces2Uniforms in Aces2Reference.swift — a flat
// plane of float4, 588 entries; the layout ORDER is the contract and the
// size-probe kernel pins the byte count).
struct Aces2Uniforms {
    // TSParams: ts0 = (n, nR, g, t1); ts1 = (cT, s2, u2, m2);
    //           ts2 = (forwardLimit, logPeak, rangeLo, rangeHi)
    float4 ts0, ts1, ts2;
    // input (AP0) JMhParams: scal0 = (fLn, cz, invCz, awJ);
    // scal1 = (invAwJ, ·, ·, ·); then the four 3-row matrices.
    float4 in_scal0, in_scal1;
    float4 in_rgbToCam16C0, in_rgbToCam16C1, in_rgbToCam16C2;
    float4 in_cam16CToRgb0, in_cam16CToRgb1, in_cam16CToRgb2;
    float4 in_coneResponseToAab0, in_coneResponseToAab1, in_coneResponseToAab2;
    float4 in_aabToConeResponse0, in_aabToConeResponse1, in_aabToConeResponse2;
    // limit (limiting-space) JMhParams — same shape.
    float4 lim_scal0, lim_scal1;
    float4 lim_rgbToCam16C0, lim_rgbToCam16C1, lim_rgbToCam16C2;
    float4 lim_cam16CToRgb0, lim_cam16CToRgb1, lim_cam16CToRgb2;
    float4 lim_coneResponseToAab0, lim_coneResponseToAab1, lim_coneResponseToAab2;
    float4 lim_aabToConeResponse0, lim_aabToConeResponse1, lim_aabToConeResponse2;
    // gam0 = (limitJMax, modelGammaInv, sat, satThr);
    // gam1 = (compr, chromaCompressScale, midJ, focusDist);
    // gam2 = (lowerHullGammaInv, peak, rgcOn, ·)
    float4 gam0, gam1, gam2;
    // fixed-space matrices: ap0ToAP1, ap1ToAP0 (the RGC legs), rec2020ToAP0
    // (stage [0]).
    float4 mAp0ToAP10, mAp0ToAP11, mAp0ToAP12;
    float4 mAp1ToAP00, mAp1ToAP01, mAp1ToAP02;
    float4 mRec2020ToAP00, mRec2020ToAP01, mRec2020ToAP02;
    // tables (362 floats each → 91 float4 with 2 pad slots; cusps 362×3 →
    // 272 float4 with 2 pad slots).
    float4 tableReachM[91];
    float4 tableHues[91];
    float4 tableCusps[272];
    float4 tableUpperHullGamma[91];
};

constant int kA2TableSize = 360;
constant int kA2TotalTableSize = 362;

static inline float3 a2Mul(float4 r0, float4 r1, float4 r2, float3 v) {
    return float3(dot(r0.xyz, v), dot(r1.xyz, v), dot(r2.xyz, v));
}

// ── CAM16 core (the Cam16.swift twins; fixed viewing scalars restated) ──

constant float kA2CamNlOffset = 27.13;   // 0.2713·100
constant float kA2CamNlScale  = 400.0;   // 4·100
constant float kA2JScale      = 100.0;
constant float kA2RefLuminance = 100.0;

static inline float a2PrcFwd(float v) {
    float f = pow(abs(v), 0.42);
    return copysign(f / (kA2CamNlOffset + f), v);
}

static inline float a2PrcInv(float v) {
    float raLim = min(abs(v), 0.99);
    float fLY = (kA2CamNlOffset * raLim) / (1.0 - raLim);
    return copysign(pow(fLY, 1.0 / 0.42), v);
}

static inline float a2AchromaticToJ(float a, float cz) {
    return kA2JScale * pow(a, cz);
}

static inline float a2JToAchromatic(float j, float invCz) {
    return pow(j / kA2JScale, invCz);
}

static inline float3 a2RgbToAab(float3 rgb, float4 scal0,
                                float4 cm0, float4 cm1, float4 cm2,
                                float4 am0, float4 am1, float4 am2) {
    float3 rgbM = a2Mul(cm0, cm1, cm2, rgb);
    float3 rgbA = float3(a2PrcFwd(rgbM.x), a2PrcFwd(rgbM.y), a2PrcFwd(rgbM.z));
    return a2Mul(am0, am1, am2, rgbA);
}

static inline float3 a2AabToJMh(float3 aab, float cz) {
    if (aab.x <= 0.0) return float3(0.0);
    float j = a2AchromaticToJ(aab.x, cz);
    float m = sqrt(aab.y * aab.y + aab.z * aab.z);
    float h = fmod(atan2(aab.z, aab.y) * (180.0 / M_PI_F) + 360.0, 360.0);
    return float3(j, m, h);
}

static inline float3 a2JmhToAab(float3 jmh, float invCz) {
    float a = a2JToAchromatic(jmh.x, invCz);
    float hr = jmh.z * (M_PI_F / 180.0);
    return float3(a, jmh.y * cos(hr), jmh.y * sin(hr));
}

static inline float3 a2AabToRgb(float3 aab, float4 scal0, float4 scal1,
                                float4 am0, float4 am1, float4 am2,
                                float4 cm0, float4 cm1, float4 cm2) {
    float3 rgbA = a2Mul(am0, am1, am2, aab);
    float3 rgbM = float3(a2PrcInv(rgbA.x), a2PrcInv(rgbA.y), a2PrcInv(rgbA.z));
    return a2Mul(cm0, cm1, cm2, rgbM);
}

// ── tonescale (the Tonescale.ctl twins) ──

static inline float a2TonescaleFwd(float x, constant Aces2Uniforms& u) {
    float f = u.ts1.w * pow(max(0.0, x) / (x + u.ts1.y), u.ts0.z);
    float h = max(0.0, f * f / (f + u.ts0.w));
    return h * u.ts0.y;
}

// ── chroma compression (the OutputTransform.ctl :440-524 twins) ──

static inline float a2ChromaCompressNorm(float h, float scale) {
    float hr = h * (M_PI_F / 180.0);
    float a = cos(hr);
    float b = sin(hr);
    float cosHr2 = a * a - b * b;
    float sinHr2 = 2.0 * a * b;
    float cosHr3 = 4.0 * a * a * a - 3.0 * a;
    float sinHr3 = 3.0 * b - 4.0 * b * b * b;
    float m = 11.34072 * a + 16.46899 * cosHr2 + 7.88380 * cosHr3
        + 14.66441 * b - 6.37224 * sinHr2 + 9.19364 * sinHr3 + 77.12896;
    return m * scale;
}

// float4-packed table readers (entry i → table[i/4][i%4]).
static inline float a2ReadTable(constant float4* table, int i) {
    return table[i / 4][i % 4];
}

static inline float a2ReachMFromTable(float h, constant Aces2Uniforms& u) {
    int base = min(int(h / 360.0 * kA2TableSize), kA2TableSize - 1);
    float t = h - float(base);
    int iLo = base + 1;
    int iHi = iLo + 1;
    return a2ReadTable(u.tableReachM, iLo)
        + t * (a2ReadTable(u.tableReachM, iHi) - a2ReadTable(u.tableReachM, iLo));
}

static inline float a2Toe(float x, float limit, float k1In, float k2In, bool invert) {
    if (x > limit) return x;
    float k2 = max(k2In, 0.001);
    float k1 = sqrt(k1In * k1In + k2 * k2);
    float k3 = (limit + k1) / (limit + k2);
    if (invert) {
        return (x * x + k1 * x) / (k3 * (x + k2));
    }
    float minusB = k3 * x - k1;
    float minusC = k2 * k3 * x;
    return 0.5 * (minusB + sqrt(minusB * minusB + 4.0 * minusC));
}

static inline float3 a2ChromaCompressFwd(float3 jmh, float tonemappedJ,
                                         constant Aces2Uniforms& u) {
    float j = jmh.x, m = jmh.y, h = jmh.z;
    float mCompr = m;
    if (m != 0.0) {
        float nJ = tonemappedJ / u.gam0.x;
        float snJ = max(0.0, 1.0 - nJ);
        float mNorm = a2ChromaCompressNorm(h, u.gam1.y);
        float limit = pow(nJ, u.gam0.y) * a2ReachMFromTable(h, u) / mNorm;
        float toeLimit = limit - 0.001;
        float toeSnJSat = snJ * u.gam0.z;
        float toeSqrtNJSatThr = sqrt(nJ * nJ + u.gam0.w);
        float toeNJCompr = nJ * u.gam1.x;
        mCompr = m * pow(tonemappedJ / j, u.gam0.y);
        mCompr = mCompr / mNorm;
        mCompr = limit - a2Toe(limit - mCompr, toeLimit, toeSnJSat, toeSqrtNJSatThr, false);
        mCompr = a2Toe(mCompr, limit, toeNJCompr, snJ, false);
        mCompr = mCompr * mNorm;
    }
    return float3(tonemappedJ, mCompr, h);
}

static inline float3 a2TonemapAndCompressFwd(float3 jmh, constant Aces2Uniforms& u) {
    // J → Y (the input-params bridge; J_to_Y :236-242).
    float a = a2JToAchromatic(abs(jmh.x), u.in_scal0.z);
    float ra = u.in_scal0.w * a;
    float y = a2PrcInv(ra) / u.in_scal0.x;
    float linear = y / kA2RefLuminance;
    float tonemappedY = a2TonescaleFwd(linear, u);
    // Y → J (Y_to_J :244-252).
    float ra2 = a2PrcFwd(abs(tonemappedY) * u.in_scal0.x);
    float jTs = a2AchromaticToJ(ra2 * u.in_scal1.x, u.in_scal0.y);
    return a2ChromaCompressFwd(jmh, jTs, u);
}

// ── gamut compression (the :562-918 twins) ──

constant float kA2SmoothCusps = 0.12;
constant float kA2CuspMidBlend = 1.3;
constant float kA2FocusGainBlend = 0.3;
constant float kA2CompressionThreshold = 0.75;

static inline float a2CompressionVectorSlope(float intersectJ, float focusJ,
                                             float limitJMax, float slopeGain) {
    float directionScalar = intersectJ < focusJ ? intersectJ : limitJMax - intersectJ;
    return directionScalar * (intersectJ - focusJ) / (focusJ * slopeGain);
}

static inline float a2SolveJIntersect(float j, float m, float focusJ,
                                      float maxJ, float slopeGain) {
    float mScaled = m / slopeGain;
    float a = mScaled / focusJ;
    if (j < focusJ) {
        float b = 1.0 - mScaled;
        float c = -j;
        float det = b * b - 4.0 * a * c;
        return -2.0 * c / (b + sqrt(det));
    }
    float b = -(1.0 + mScaled + maxJ * a);
    float c = maxJ * mScaled + j;
    float det = b * b - 4.0 * a * c;
    return -2.0 * c / (b - sqrt(det));
}

static inline float a2SminScaled(float a, float b, float scaleReference) {
    float sScaled = kA2SmoothCusps * scaleReference;
    float h = max(sScaled - abs(a - b), 0.0) / sScaled;
    return min(a, b) - h * h * h * sScaled * (1.0 / 6.0);
}

static inline float a2EstimateLineAndBoundaryIntersectionM(
        float jAxisIntersect, float slope, float invGamma, float jMax,
        float mMax, float jIntersectionReference) {
    float normalisedJ = jAxisIntersect / jIntersectionReference;
    float shifted = jIntersectionReference * pow(normalisedJ, invGamma);
    return shifted * mMax / (jMax - slope * mMax);
}

static inline float a2FindGamutBoundaryIntersection(
        float2 jmCusp, float jMax, float gammaTopInv, float gammaBottomInv,
        float jIntersectSource, float slope, float jIntersectCusp) {
    float mLower = a2EstimateLineAndBoundaryIntersectionM(
        jIntersectSource, slope, gammaBottomInv, jmCusp.x, jmCusp.y, jIntersectCusp);
    float fCusp = jMax - jIntersectCusp;
    float fSource = jMax - jIntersectSource;
    float fCuspJ = jMax - jmCusp.x;
    float mUpper = a2EstimateLineAndBoundaryIntersectionM(
        fSource, -slope, gammaTopInv, fCuspJ, jmCusp.y, fCusp);
    return a2SminScaled(mLower, mUpper, jmCusp.y);
}

static inline float a2GetFocusGain(float j, float analyticalThreshold,
                                   float limitJMax, float focusDist) {
    float gain = limitJMax * focusDist;
    if (j > analyticalThreshold) {
        float adj = log10((limitJMax - analyticalThreshold)
            / max(0.0001, limitJMax - j));
        gain = gain * (adj * adj + 1.0);
    }
    return gain;
}

static inline float a2RemapM(float m, float gamutBoundaryM, float reachBoundaryM) {
    float boundaryRatio = gamutBoundaryM / reachBoundaryM;
    float proportion = max(boundaryRatio, kA2CompressionThreshold);
    float threshold = proportion * gamutBoundaryM;
    if (m <= threshold || proportion >= 1.0) return m;
    float mOffset = m - threshold;
    float gamutOffset = gamutBoundaryM - threshold;
    float reachOffset = reachBoundaryM - threshold;
    float scale = reachOffset / ((reachOffset / gamutOffset) - 1.0);
    float nd = mOffset / scale;
    // reinhard_remap — forward arm only (invert never requested fwd).
    return threshold + scale * nd / (1.0 + nd);
}

static inline float a2ComputeFocusJ(float cuspJ, float midJ, float limitJMax) {
    float t = min(1.0, kA2CuspMidBlend - cuspJ / limitJMax);
    return cuspJ + t * (midJ - cuspJ);
}

// The cusp table's (J, M, hue) triples stride 3 across the float4 plane.
static inline float a2CuspFlat(constant Aces2Uniforms& u, int entry, int component) {
    int flat = entry * 3 + component;
    return u.tableCusps[flat / 4][flat % 4];
}

static inline float2 a2CuspFromTable(float h, constant Aces2Uniforms& u) {
    int lowI = 0;
    int highI = 1 + kA2TableSize;
    int i = int(h / 360.0 * kA2TableSize) + 1;
    while (lowI + 1 < highI) {
        if (h > a2CuspFlat(u, i, 2)) {
            lowI = i;
        } else {
            highI = i;
        }
        i = (lowI + highI) / 2;
    }
    int lo = highI - 1;
    int hi = highI;
    float loHue = a2CuspFlat(u, lo, 2);
    float hiHue = a2CuspFlat(u, hi, 2);
    float t = (h - loHue) / (hiHue - loHue);
    float cuspJ = a2CuspFlat(u, lo, 0)
        + t * (a2CuspFlat(u, hi, 0) - a2CuspFlat(u, lo, 0));
    float cuspM = a2CuspFlat(u, lo, 1)
        + t * (a2CuspFlat(u, hi, 1) - a2CuspFlat(u, lo, 1));
    return float2(cuspJ, cuspM);
}

static inline int a2LookupHueInterval(float h, constant Aces2Uniforms& u,
                                      int2 range) {
    int i = 1 + int(h / 360.0 * kA2TotalTableSize);
    int iLo = max(1, i + range.x);
    int iHi = min(1 + kA2TableSize, i + range.y);
    while (iLo + 1 < iHi) {
        if (h > u.tableHues[i / 4][i % 4]) {
            iLo = i;
        } else {
            iHi = i;
        }
        i = (iLo + iHi) / 2;
    }
    return max(1, iHi);
}

static inline float3 a2CompressGamut(float3 jmh, float jx,
                                     constant Aces2Uniforms& u,
                                     float2 jmCusp, float gammaTopInv,
                                     float gammaBottomInv, float focusJ,
                                     float analyticalThreshold) {
    float j = jmh.x, m = jmh.y, h = jmh.z;
    float slopeGain = a2GetFocusGain(jx, analyticalThreshold, u.gam0.x, u.gam1.w);
    float jIntersectSource = a2SolveJIntersect(j, m, focusJ, u.gam0.x, slopeGain);
    float gamutSlope = a2CompressionVectorSlope(
        jIntersectSource, focusJ, u.gam0.x, slopeGain);
    float jIntersectCusp = a2SolveJIntersect(
        jmCusp.x, jmCusp.y, focusJ, u.gam0.x, slopeGain);
    float gamutBoundaryM = a2FindGamutBoundaryIntersection(
        jmCusp, u.gam0.x, gammaTopInv, gammaBottomInv,
        jIntersectSource, gamutSlope, jIntersectCusp);
    if (gamutBoundaryM <= 0.0) {
        return float3(j, 0.0, h);
    }
    float reachMaxM = a2ReachMFromTable(h, u);
    float reachBoundaryM = a2EstimateLineAndBoundaryIntersectionM(
        jIntersectSource, gamutSlope, u.gam0.y, u.gam0.x, reachMaxM, u.gam0.x);
    float remappedM = a2RemapM(m, gamutBoundaryM, reachBoundaryM);
    return float3(jIntersectSource + remappedM * gamutSlope, remappedM, h);
}

static inline float3 a2GamutCompressFwd(float3 jmh, constant Aces2Uniforms& u) {
    float j = jmh.x, m = jmh.y, h = jmh.z;
    if (j <= 0.0) return float3(0.0, 0.0, h);
    if (m < 0.0 || j > u.gam0.x) return float3(j, 0.0, h);
    int2 range = int2(u.ts2.zw);   // hue_linearity_search_range
    int iHi = a2LookupHueInterval(h, u, range);
    float t = h - u.tableHues[(iHi - 1) / 4][(iHi - 1) % 4];
    float2 jmCusp = a2CuspFromTable(h, u);
    float gLo = u.tableUpperHullGamma[(iHi - 1) / 4][(iHi - 1) % 4];
    float gHi = u.tableUpperHullGamma[iHi / 4][iHi % 4];
    float gammaTopInv = gLo + t * (gHi - gLo);
    float focusJ = a2ComputeFocusJ(jmCusp.x, u.gam1.z, u.gam0.x);
    float analyticalThreshold = jmCusp.x
        + kA2FocusGainBlend * (u.gam0.x - jmCusp.x);
    return a2CompressGamut(jmh, j, u, jmCusp, gammaTopInv, u.gam2.x,
        focusJ, analyticalThreshold);
}

// ── the RGC前置 (the v1.3 LMT twins) ──

constant float kA2RgcPwr = 1.2;

static inline float a2RgcShaper(float dist, float lim, float thr) {
    if (dist < thr) return dist;
    float scl = (lim - thr)
        / pow(pow((1.0 - thr) / (lim - thr), -kA2RgcPwr) - 1.0, 1.0 / kA2RgcPwr);
    float nd = (dist - thr) / scl;
    float p = pow(nd, kA2RgcPwr);
    return thr + scl * nd / pow(1.0 + p, 1.0 / kA2RgcPwr);
}

static inline float3 a2RgcCompress(float3 aces, constant Aces2Uniforms& u) {
    float3 linAP1 = a2Mul(u.mAp0ToAP10, u.mAp0ToAP11, u.mAp0ToAP12, aces);
    float ach = max(linAP1.x, max(linAP1.y, linAP1.z));
    float mag = abs(ach);
    float3 dist = (mag == 0.0)
        ? float3(0.0)
        : (ach - linAP1) / mag;
    float3 comprDist = float3(
        a2RgcShaper(dist.x, 1.147, 0.815),
        a2RgcShaper(dist.y, 1.264, 0.803),
        a2RgcShaper(dist.z, 1.312, 0.880));
    float3 comprLinAP1 = ach - comprDist * mag;
    return a2Mul(u.mAp1ToAP00, u.mAp1ToAP01, u.mAp1ToAP02, comprLinAP1);
}

// ── the kernel (stages [0]..[7]) ──

kernel void drt_aces2(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant Aces2Uniforms&         u   [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float3 rgb = in.read(gid).rgb;

    // [0] working space → AP0.
    float3 aces = a2Mul(u.mRec2020ToAP00, u.mRec2020ToAP01, u.mRec2020ToAP02, rgb);

    // [1] the RGC前置 (default ON; the OpenDRT path never runs it — KD-3).
    if (u.gam2.z > 0.5) {
        aces = a2RgcCompress(aces, u);
    }

    // [2] clamp AP0 through AP1 at the tonescale's forward limit.
    float3 ap1 = a2Mul(u.mAp0ToAP10, u.mAp0ToAP11, u.mAp0ToAP12, aces);
    ap1 = clamp(ap1, 0.0, u.ts2.x);
    aces = a2Mul(u.mAp1ToAP00, u.mAp1ToAP01, u.mAp1ToAP02, ap1);

    // [3] AP0 → JMh.
    float3 aab = a2RgbToAab(aces, u.in_scal0,
        u.in_rgbToCam16C0, u.in_rgbToCam16C1, u.in_rgbToCam16C2,
        u.in_coneResponseToAab0, u.in_coneResponseToAab1, u.in_coneResponseToAab2);
    float3 jmh = a2AabToJMh(aab, u.in_scal0.y);

    // [4] tonescale + chroma compression.
    float3 tonemapped = a2TonemapAndCompressFwd(jmh, u);

    // [5] gamut compression against the limiting gamut.
    float3 compressed = a2GamutCompressFwd(tonemapped, u);

    // [6] JMh → limiting-space RGB (the JMh→Aab hop rides the limit
    // params' scalars, then the Aab→cone→RGB chain).
    float3 aabLimit = a2JmhToAab(compressed, u.lim_scal0.z);
    float3 outRgb = a2AabToRgb(aabLimit, u.lim_scal0, u.lim_scal1,
        u.lim_aabToConeResponse0, u.lim_aabToConeResponse1, u.lim_aabToConeResponse2,
        u.lim_cam16CToRgb0, u.lim_cam16CToRgb1, u.lim_cam16CToRgb2);

    // [7] peak normalization (1.0 = peak nits — the EotfBox contract).
    outRgb *= kA2RefLuminance / u.gam2.y;

    out.write(float4(outRgb, in.read(gid).a), gid);
}

// Layout pin: the test compares this against the Swift builder's count.
kernel void drt_aces2_uniforms_size_probe(
    device uint* out [[buffer(0)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid > 0) return;
    out[0] = uint(sizeof(Aces2Uniforms));
}
