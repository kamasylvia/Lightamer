#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// RasterInputKernels — the TIFF raster input leg, GPU face (Plan M4-1-01 T7,
// KD-6). TWO entries:
//
//   raster_input_display      — linearize (the source TRC) fused with the
//                               ACES 2.0 inverse [i7'..i0'] — ONE pass, no
//                               float32 intermediate plane (the fusion
//                               saves a ≈1.6 GB 100MP intermediate). The
//                               displayReferred branch INCLUDING the
//                               iccLutConverted CI-converted planes (their
//                               TRC is linear → the linearize identity).
//   raster_input_scene_linear — the sceneLinear branch (no-ICC float32 and
//                               linear-ICC float32, the ②/①′ halves): one
//                               3×3 matrix (source primaries+white CAT02 →
//                               Rec2020), negatives clamped, the TOP OPEN
//                               (the >1.0 HDR probe values must survive —
//                               the DRT tail's AP1 clamp takes over later).
//
// SELF-CONTAINED (the red line): Aces2Kernels.metal is the FORWARD's frozen
// face — zero diff. This file restates the shared CAM16/gamut primitives
// under the `ri` prefix (a re-statement, never a second authority — the
// Float64 authority is Aces2InverseReference and the T8 parity golden pins
// this mirror to it).
//
// CONSTANT DISCIPLINE: same as the forward mirror — constants below are
// FLOAT RE-STATEMENTS of the Swift authorities (Aces2Reference/DrtEotfMath);
// the T8 parity test is the pin. L006: full float math on transfer paths.
// ─────────────────────────────────────────────────────────────────────────────

// ── the uniform ABI (the Swift single source packs this plane) ──

struct RasterInputUniforms {
    // head0 = (peak, refLuminance, transferKind, gammaValue)
    // head1 = (paramType, p_g, p_a, p_b)
    // head2 = (p_c, p_d, p_e, p_f)
    // head3 = (sampledCount, ·, ·, ·)
    float4 head0, head1, head2, head3;
    // ts0 = (n, nR, g, t1); ts1 = (cT, s2, u2, m2);
    // ts2 = (forwardLimit, logPeak, rangeLo, rangeHi)
    float4 ts0, ts1, ts2;
    // input (AP0) JMhParams — the same 14-float4 shape as the forward.
    float4 in_scal0, in_scal1;
    float4 in_rgbToCam16C0, in_rgbToCam16C1, in_rgbToCam16C2;
    float4 in_cam16CToRgb0, in_cam16CToRgb1, in_cam16CToRgb2;
    float4 in_coneResponseToAab0, in_coneResponseToAab1, in_coneResponseToAab2;
    float4 in_aabToConeResponse0, in_aabToConeResponse1, in_aabToConeResponse2;
    // limit (limiting-space = the SOURCE primaries, OQ-2) JMhParams.
    float4 lim_scal0, lim_scal1;
    float4 lim_rgbToCam16C0, lim_rgbToCam16C1, lim_rgbToCam16C2;
    float4 lim_cam16CToRgb0, lim_cam16CToRgb1, lim_cam16CToRgb2;
    float4 lim_coneResponseToAab0, lim_coneResponseToAab1, lim_coneResponseToAab2;
    float4 lim_aabToConeResponse0, lim_aabToConeResponse1, lim_aabToConeResponse2;
    // gam0 = (limitJMax, modelGammaInv, sat, satThr);
    // gam1 = (compr, chromaCompressScale, midJ, focusDist);
    // gam2 = (lowerHullGammaInv, peak, ·, ·)
    float4 gam0, gam1, gam2;
    // [i0'] the working-space exit: AP0 → linear Rec2020.
    float4 mAp0ToRec2020_0, mAp0ToRec2020_1, mAp0ToRec2020_2;
    // the scene-linear branch matrix: source primaries+white → Rec2020.
    float4 mSceneToRec2020_0, mSceneToRec2020_1, mSceneToRec2020_2;
    // tables (362 floats → 91 float4; cusps 362×3 → 272 float4).
    float4 tableReachM[91];
    float4 tableHues[91];
    float4 tableCusps[272];
    float4 tableUpperHullGamma[91];
    // the sampled TRC (4096 floats → 1024 float4; head3.x entries used).
    float4 sampledTRC[1024];
};

constant int kRiTableSize = 360;
constant int kRiTotalTableSize = 362;
constant float kRiRefLuminance = 100.0;
constant float kRiSmoothCusps = 0.12;
constant float kRiCuspMidBlend = 1.3;
constant float kRiFocusGainBlend = 0.3;
constant float kRiCompressionThreshold = 0.75;

// The transfer-kind ordinals (the Swift enum order — RasterTransfer).
constant int kRiTrcLinear = 0;
constant int kRiTrcSrgb = 1;
constant int kRiTrcGamma = 2;
constant int kRiTrcIccParametric = 3;
constant int kRiTrcIccSampled = 4;
constant int kRiTrcSt2084 = 5;
constant int kRiTrcHlg = 6;
constant int kRiTrcBt1886 = 7;

// ── small math ──

static inline float3 riMul(float4 r0, float4 r1, float4 r2, float3 v) {
    return float3(
        r0.x * v.x + r0.y * v.y + r0.z * v.z,
        r1.x * v.x + r1.y * v.y + r1.z * v.z,
        r2.x * v.x + r2.y * v.y + r2.z * v.z);
}

constant float kRiCamNlOffset = 27.13;
constant float kRiJScale = 100.0;

static inline float riPrcFwd(float v) {
    float f = pow(abs(v), 0.42);
    return copysign(f / (kRiCamNlOffset + f), v);
}

static inline float riPrcInv(float v) {
    float raLim = min(abs(v), 0.99);
    float fLY = (kRiCamNlOffset * raLim) / (1.0 - raLim);
    return copysign(pow(fLY, 1.0 / 0.42), v);
}

static inline float riAchromaticToJ(float a, float cz) {
    return kRiJScale * pow(a, cz);
}

static inline float riJToAchromatic(float j, float invCz) {
    return pow(j / kRiJScale, invCz);
}

static inline float3 riRgbToAab(float3 rgb, float4 scal0,
                                float4 cm0, float4 cm1, float4 cm2,
                                float4 c0, float4 c1, float4 c2) {
    float3 rgbM = riMul(cm0, cm1, cm2, rgb);
    float3 rgbA = float3(riPrcFwd(rgbM.x), riPrcFwd(rgbM.y), riPrcFwd(rgbM.z));
    return riMul(c0, c1, c2, rgbA);
}

static inline float3 riAabToJMh(float3 aab, float cz) {
    if (aab.x <= 0.0) return float3(0.0);
    float j = riAchromaticToJ(aab.x, cz);
    float m = sqrt(aab.y * aab.y + aab.z * aab.z);
    float h = fmod(atan2(aab.z, aab.y) * (180.0 / M_PI_F) + 360.0, 360.0);
    return float3(j, m, h);
}

static inline float3 riJmhToAab(float3 jmh, float invCz) {
    float a = riJToAchromatic(jmh.x, invCz);
    float hr = jmh.z * (M_PI_F / 180.0);
    return float3(a, jmh.y * cos(hr), jmh.y * sin(hr));
}

static inline float3 riAabToRgb(float3 aab, float4 scal0, float4 scal1,
                                float4 am0, float4 am1, float4 am2,
                                float4 c0, float4 c1, float4 c2) {
    float3 rgbA = riMul(am0, am1, am2, aab);
    float3 rgbM = float3(riPrcInv(rgbA.x), riPrcInv(rgbA.y), riPrcInv(rgbA.z));
    return riMul(c0, c1, c2, rgbM);
}

// ── the tonescale inverse (Tonescale.ctl :88-97) ──

static inline float riTonescaleInv(float y, constant RasterInputUniforms& u) {
    float z = clamp(y, 0.0, u.ts0.x / (u.ts1.z * u.ts0.y));
    float h = (z + sqrt(z * (4.0 * u.ts0.w + z))) / 2.0;
    return u.ts1.y / (pow(u.ts1.w / h, 1.0 / u.ts0.z) - 1.0);
}

// ── the J/Y bridges (the input-params scalars) ──

static inline float riJToY(float j, constant RasterInputUniforms& u) {
    float a = riJToAchromatic(abs(j), u.in_scal0.z);
    float ra = u.in_scal0.w * a;
    return riPrcInv(ra) / u.in_scal0.x;
}

static inline float riYToJ(float y, constant RasterInputUniforms& u) {
    float ra = riPrcFwd(abs(y) * u.in_scal0.x);
    return riAchromaticToJ(ra * u.in_scal1.x, u.in_scal0.y);
}

// ── tables ──

static inline float riReadTable(constant float4* table, int i) {
    return table[i / 4][i % 4];
}

static inline float riReachMFromTable(float h, constant RasterInputUniforms& u) {
    int base = int(h / 360.0 * kRiTableSize);
    float t = h - float(base);
    int iLo = base + 1;
    return riReadTable(u.tableReachM, iLo)
        + t * (riReadTable(u.tableReachM, iLo + 1) - riReadTable(u.tableReachM, iLo));
}

static inline float riChromaCompressNorm(float h, float scale) {
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

static inline float riToe(float x, float limit, float k1In, float k2In,
                          bool invert) {
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

// ── chroma compression inverse (OutputTransform.ctl :492-532) ──

static inline float3 riChromaCompressInv(float3 jmhTc, float j,
                                         constant RasterInputUniforms& u) {
    float tonemappedJ = jmhTc.x;
    float mCompr = jmhTc.y;
    float h = jmhTc.z;
    float m = mCompr;
    if (mCompr != 0.0) {
        float nJ = tonemappedJ / u.gam0.x;
        float snJ = max(0.0, 1.0 - nJ);
        float mNorm = riChromaCompressNorm(h, u.gam1.y);
        float limit = pow(nJ, u.gam0.y) * riReachMFromTable(h, u) / mNorm;
        float toeLimit = limit - 0.001;
        float toeSnJSat = snJ * u.gam0.z;
        float toeSqrtNJSatThr = sqrt(nJ * nJ + u.gam0.w);
        float toeNJCompr = nJ * u.gam1.x;
        m = mCompr / mNorm;
        m = riToe(m, limit, toeNJCompr, snJ, true);
        m = limit - riToe(limit - m, toeLimit, toeSnJSat, toeSqrtNJSatThr, true);
        m = m * mNorm;
        m = m * pow(tonemappedJ / j, -u.gam0.y);
    }
    return float3(j, m, h);
}

// tonemap_and_compress_inv (:544-560) — the inverse tonescale FIRST
// (restores the original J), then the chroma inverse consumes it (the
// data-dependency order — KD-3/E3).
static inline float3 riTonemapAndCompressInv(float3 jmhTc,
                                             constant RasterInputUniforms& u) {
    float luminance = riJToY(jmhTc.x, u);
    float linear = riTonescaleInv(luminance / kRiRefLuminance, u);
    float j = riYToJ(linear * kRiRefLuminance, u);
    return riChromaCompressInv(jmhTc, j, u);
}

// ── the gamut compression inverse (:890-917, ≤2 estimates) ──

static inline float riCompressionVectorSlope(float intersectJ, float focusJ,
                                             float limitJMax, float slopeGain) {
    float directionScalar = intersectJ < focusJ ? intersectJ : limitJMax - intersectJ;
    return directionScalar * (intersectJ - focusJ) / (focusJ * slopeGain);
}

static inline float riSolveJIntersect(float j, float m, float focusJ,
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

static inline float riSminScaled(float a, float b, float scaleReference) {
    float sScaled = kRiSmoothCusps * scaleReference;
    float h = max(sScaled - abs(a - b), 0.0) / sScaled;
    return min(a, b) - h * h * h * sScaled * (1.0 / 6.0);
}

static inline float riEstimateLineAndBoundaryIntersectionM(
        float jAxisIntersect, float slope, float invGamma, float jMax,
        float mMax, float jIntersectionReference) {
    float normalisedJ = jAxisIntersect / jIntersectionReference;
    float shifted = jIntersectionReference * pow(normalisedJ, invGamma);
    return shifted * mMax / (jMax - slope * mMax);
}

static inline float riFindGamutBoundaryIntersection(
        float2 jmCusp, float jMax, float gammaTopInv, float gammaBottomInv,
        float jIntersectSource, float slope, float jIntersectCusp) {
    float mLower = riEstimateLineAndBoundaryIntersectionM(
        jIntersectSource, slope, gammaBottomInv, jmCusp.x, jmCusp.y, jIntersectCusp);
    float fCusp = jMax - jIntersectCusp;
    float fSource = jMax - jIntersectSource;
    float fCuspJ = jMax - jmCusp.x;
    float mUpper = riEstimateLineAndBoundaryIntersectionM(
        fSource, -slope, gammaTopInv, fCuspJ, jmCusp.y, fCusp);
    return riSminScaled(mLower, mUpper, jmCusp.y);
}

static inline float riGetFocusGain(float j, float analyticalThreshold,
                                   float limitJMax, float focusDist) {
    float gain = limitJMax * focusDist;
    if (j > analyticalThreshold) {
        float adj = log10((limitJMax - analyticalThreshold)
            / max(0.0001, limitJMax - j));
        gain = gain * (adj * adj + 1.0);
    }
    return gain;
}

static inline float riRemapM(float m, float gamutBoundaryM, float reachBoundaryM,
                             bool invert) {
    float boundaryRatio = gamutBoundaryM / reachBoundaryM;
    float proportion = max(boundaryRatio, kRiCompressionThreshold);
    float threshold = proportion * gamutBoundaryM;
    if (m <= threshold || proportion >= 1.0) return m;
    float mOffset = m - threshold;
    float gamutOffset = gamutBoundaryM - threshold;
    float reachOffset = reachBoundaryM - threshold;
    float scale = reachOffset / ((reachOffset / gamutOffset) - 1.0);
    float nd = mOffset / scale;
    if (invert) {
        // reinhard_remap inverse (the closed form).
        return threshold + (nd >= 1.0 ? scale : -scale * nd / (nd - 1.0));
    }
    return threshold + scale * nd / (1.0 + nd);
}

static inline float riComputeFocusJ(float cuspJ, float midJ, float limitJMax) {
    float t = min(1.0, kRiCuspMidBlend - cuspJ / limitJMax);
    return cuspJ + t * (midJ - cuspJ);
}

static inline float riCuspFlat(constant RasterInputUniforms& u, int entry,
                               int component) {
    int flat = entry * 3 + component;
    return u.tableCusps[flat / 4][flat % 4];
}

static inline float2 riCuspFromTable(float h, constant RasterInputUniforms& u) {
    int lowI = 0;
    int highI = 1 + kRiTableSize;
    int i = int(h / 360.0 * kRiTableSize) + 1;
    while (lowI + 1 < highI) {
        if (h > riCuspFlat(u, i, 2)) {
            lowI = i;
        } else {
            highI = i;
        }
        i = (lowI + highI) / 2;
    }
    int lo = highI - 1;
    int hi = highI;
    float loHue = riCuspFlat(u, lo, 2);
    float hiHue = riCuspFlat(u, hi, 2);
    float t = (h - loHue) / (hiHue - loHue);
    float cuspJ = riCuspFlat(u, lo, 0)
        + t * (riCuspFlat(u, hi, 0) - riCuspFlat(u, lo, 0));
    float cuspM = riCuspFlat(u, lo, 1)
        + t * (riCuspFlat(u, hi, 1) - riCuspFlat(u, lo, 1));
    return float2(cuspJ, cuspM);
}

static inline int riLookupHueInterval(float h, constant RasterInputUniforms& u,
                                      int2 range) {
    int i = 1 + int(h / 360.0 * kRiTotalTableSize);
    int iLo = max(1, i + range.x);
    int iHi = min(1 + kRiTableSize, i + range.y);
    while (iLo + 1 < iHi) {
        if (h > riReadTable(u.tableHues, i)) {
            iLo = i;
        } else {
            iHi = i;
        }
        i = (iLo + iHi) / 2;
    }
    return max(1, iHi);
}

static inline float3 riCompressGamutInv(float3 jmh, float jx,
                                        constant RasterInputUniforms& u,
                                        float2 jmCusp, float gammaTopInv,
                                        float gammaBottomInv, float focusJ,
                                        float analyticalThreshold) {
    float j = jmh.x, m = jmh.y, h = jmh.z;
    float slopeGain = riGetFocusGain(jx, analyticalThreshold, u.gam0.x, u.gam1.w);
    float jIntersectSource = riSolveJIntersect(j, m, focusJ, u.gam0.x, slopeGain);
    float gamutSlope = riCompressionVectorSlope(
        jIntersectSource, focusJ, u.gam0.x, slopeGain);
    float jIntersectCusp = riSolveJIntersect(
        jmCusp.x, jmCusp.y, focusJ, u.gam0.x, slopeGain);
    float gamutBoundaryM = riFindGamutBoundaryIntersection(
        jmCusp, u.gam0.x, gammaTopInv, gammaBottomInv,
        jIntersectSource, gamutSlope, jIntersectCusp);
    if (gamutBoundaryM <= 0.0) {
        return float3(j, 0.0, h);
    }
    float reachMaxM = riReachMFromTable(h, u);
    float reachBoundaryM = riEstimateLineAndBoundaryIntersectionM(
        jIntersectSource, gamutSlope, u.gam0.y, u.gam0.x, reachMaxM, u.gam0.x);
    float remappedM = riRemapM(m, gamutBoundaryM, reachBoundaryM, true);
    return float3(jIntersectSource + remappedM * gamutSlope, remappedM, h);
}

static inline float3 riGamutCompressInv(float3 jmh,
                                        constant RasterInputUniforms& u) {
    float j = jmh.x, m = jmh.y, h = jmh.z;
    if (j <= 0.0) return float3(0.0, 0.0, h);
    if (m < 0.0 || j > u.gam0.x) return float3(j, 0.0, h);
    int2 range = int2(u.ts2.zw);
    int iHi = riLookupHueInterval(h, u, range);
    float t = h - riReadTable(u.tableHues, iHi - 1);
    float2 jmCusp = riCuspFromTable(h, u);
    float gLo = riReadTable(u.tableUpperHullGamma, iHi - 1);
    float gHi = riReadTable(u.tableUpperHullGamma, iHi);
    float gammaTopInv = gLo + t * (gHi - gLo);
    float focusJ = riComputeFocusJ(jmCusp.x, u.gam1.z, u.gam0.x);
    float analyticalThreshold = jmCusp.x
        + kRiFocusGainBlend * (u.gam0.x - jmCusp.x);
    float jx = j;
    if (jx > analyticalThreshold) {
        jx = riCompressGamutInv(jmh, jx, u, jmCusp, gammaTopInv,
                                u.gam2.x, focusJ, analyticalThreshold).x;
    }
    return riCompressGamutInv(jmh, jx, u, jmCusp, gammaTopInv,
                              u.gam2.x, focusJ, analyticalThreshold);
}

// ── the TRC family (kernel-self-held; the Core host twins live in
//    RasterTRC / DrtEotfMath — the T8 parity pins the mirror) ──

static inline float riSrgbPiecewiseDecode(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

static inline float riPqDecodeRelative(float c) {
    float const m1 = 2610.0 / 16384.0;
    float const m2 = 2523.0 / 32.0;
    float const c1 = 107.0 / 128.0;
    float const c2 = 2413.0 / 128.0;
    float const c3 = 2392.0 / 128.0;
    float e = pow(clamp(c, 0.0, 1.0), 1.0 / m2);
    float f = (e - c1) / (c2 - c3 * e);
    return f <= 0.0 ? 0.0 : pow(f, 1.0 / m1);
}

static inline float riHlgOETF(float s) {
    return s <= 0.5 ? s * s / 3.0
                    : (exp((s - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
}

static inline float riHlgDisplayDecode(float c) {
    // The 1000-nit reference display curve (OOTF γ=1.2 of the OETF).
    float scene = riHlgOETF(clamp(c, 0.0, 1.0));
    return scene <= 0.0 ? 0.0 : pow(scene, 1.2);
}

static inline float riParametricDecode(float c, constant RasterInputUniforms& u) {
    int type = int(u.head1.x + 0.5);
    float g = u.head1.y, a = u.head1.z, b = u.head1.w;
    float cc = u.head2.x, d = u.head2.y, e = u.head2.z, f = u.head2.w;
    switch (type) {
        case 0: return c <= 0.0 ? c : pow(c, g);
        case 1: return c >= -b / a ? pow(c * a + b, g) : 0.0;
        case 2: return c >= -b / a ? pow(c * a + b, g) + cc : cc;
        case 3: return c >= d ? pow(c * a + b, g) : cc * c;
        case 4: return c >= d ? pow(c * a + b, g) + e : cc * c + f;
        default: return c;
    }
}

static inline float riSampledDecode(float c, constant RasterInputUniforms& u) {
    int count = int(u.head3.x + 0.5);
    if (count < 2) return clamp(c, 0.0, 1.0);
    float t = clamp(c, 0.0, 1.0) * float(count - 1);
    int i0 = min(int(t), count - 2);
    float f = t - float(i0);
    float v0 = u.sampledTRC[i0 / 4][i0 % 4];
    float v1 = u.sampledTRC[(i0 + 1) / 4][(i0 + 1) % 4];
    return v0 * (1.0 - f) + v1 * f;
}

static inline float riTrcDecode(float code, constant RasterInputUniforms& u) {
    int kind = int(u.head0.z + 0.5);
    float c = clamp(code, 0.0, 1.0);
    switch (kind) {
        case kRiTrcLinear: return code;           // identity, unclamped
        case kRiTrcSrgb: return riSrgbPiecewiseDecode(c);
        case kRiTrcGamma: return pow(c, u.head0.w);
        case kRiTrcIccParametric: return riParametricDecode(c, u);
        case kRiTrcIccSampled: return riSampledDecode(c, u);
        case kRiTrcSt2084: return riPqDecodeRelative(c);
        case kRiTrcHlg: return riHlgDisplayDecode(c);
        case kRiTrcBt1886: return pow(c, 2.4);
        default: return c;
    }
}

// Linearize → peak-normalized display linear (the [i7'] input contract):
// SDR curves live in [0,1] at the 100-nit reference (peak 100 → normalized);
// PQ/HLG decode on their relative domains and scale to the description peak.
static inline float3 riLinearize(float3 code, constant RasterInputUniforms& u) {
    int kind = int(u.head0.z + 0.5);
    float3 lin = float3(
        riTrcDecode(code.x, u), riTrcDecode(code.y, u), riTrcDecode(code.z, u));
    if (kind == kRiTrcSt2084) {
        lin *= 10000.0 / u.gam2.y;
    } else if (kind == kRiTrcHlg) {
        lin *= 1000.0 / u.gam2.y;
    }
    return lin;
}

// ── the kernels ──

// raster_input_display: linearize → [i7'] EotfBox contract inverse →
// [i6'] RGB→JMh (limit = source primaries) → [i5'] gamut compress inverse →
// [i4'] tonescale inverse then chroma inverse (the data-dependency order) →
// [i3'] JMh→AP0 → [i0'] AP0 → linear Rec2020. ONE pass, no intermediate.
kernel void raster_input_display(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant RasterInputUniforms&   u   [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float3 code = in.read(gid).rgb;

    // linearize → peak-normalized display linear.
    float3 displayLin = riLinearize(code, u);
    // [i7'] the EotfBox contract inverse: 1.0 = peak nits → 1.0 = 100 nits.
    float3 rgb = displayLin * (u.gam2.y / kRiRefLuminance);

    // [i6'] display RGB → JMh against the limiting (source) gamut.
    float3 aabLim = riRgbToAab(rgb, u.lim_scal0,
        u.lim_rgbToCam16C0, u.lim_rgbToCam16C1, u.lim_rgbToCam16C2,
        u.lim_coneResponseToAab0, u.lim_coneResponseToAab1, u.lim_coneResponseToAab2);
    float3 compressedJMh = riAabToJMh(aabLim, u.lim_scal0.y);

    // [i5'] the gamut-compression inverse.
    float3 tonemappedJMh = riGamutCompressInv(compressedJMh, u);

    // [i4'] the tonescale inverse restores J, then the chroma inverse.
    float3 jmh = riTonemapAndCompressInv(tonemappedJMh, u);

    // [i3'] JMh → AP0 scene-linear.
    float3 aabIn = riJmhToAab(jmh, u.in_scal0.z);
    float3 aces = riAabToRgb(aabIn, u.in_scal0, u.in_scal1,
        u.in_aabToConeResponse0, u.in_aabToConeResponse1, u.in_aabToConeResponse2,
        u.in_cam16CToRgb0, u.in_cam16CToRgb1, u.in_cam16CToRgb2);

    // [i0'] AP0 → linear Rec2020 (the working space).
    float3 rec2020 = riMul(u.mAp0ToRec2020_0, u.mAp0ToRec2020_1,
        u.mAp0ToRec2020_2, aces);

    out.write(float4(rec2020, in.read(gid).a), gid);
}

// raster_input_scene_linear: the ②/①′ matrix branch — source
// primaries+white → Rec2020, negatives clamped, the TOP OPEN (>1.0
// survives — the HDR content the probe and the DRT tail consume).
kernel void raster_input_scene_linear(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant RasterInputUniforms&   u   [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float3 value = in.read(gid).rgb;
    float3 rec2020 = riMul(u.mSceneToRec2020_0, u.mSceneToRec2020_1,
        u.mSceneToRec2020_2, value);
    out.write(float4(max(rec2020, 0.0), in.read(gid).a), gid);
}

// Layout pin: the test compares this against the Swift builder's count.
kernel void raster_input_uniforms_size_probe(
    device uint* out [[buffer(0)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid > 0) return;
    out[0] = uint(sizeof(RasterInputUniforms));
}
