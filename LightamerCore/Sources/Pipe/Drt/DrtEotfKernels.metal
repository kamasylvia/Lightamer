#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// DrtEotfKernels — the seven-function EOTF encoding core, GPU face
// (Plan M2-6-1 T2, KD-2). Lives in LightamerCore so the DRT tail and the
// tests run with zero IOP dependency (the TerminalKernels placement rule).
//
// CONSTANT SINGLE SOURCE: the constants below are a FLOAT RE-STATEMENT of
// the canonical fractions defined in `DrtEotf.swift` (DrtEotfMath) — that
// file is the authority; this file must never invent a value. The
// `drt_eotf_constants_probe` kernel exists SOLELY so the tests can read
// these constants back and pin the parity (≤1e-6).
//
// SEMANTICS mirror DrtEotfMath exactly (see that header for the terminal
// forms): input = peak-normalized display linear; st2084 ÷10000, hlg ÷1000;
// the SDR family clamps [0,1]; linear = identity unclamped; the HLG OOTF
// scaling uses the safePow guard (x<=0 → x) so black stays NaN-free.
//
// L006: full float math everywhere — no half on the transfer-function path.
// ─────────────────────────────────────────────────────────────────────────────

// BT.2100 ST 2084 (PQ) — canonical ITU fractions evaluated in float.
constant float kSt2084M1 = 2610.0 / 16384.0;
constant float kSt2084M2 = 2523.0 / 32.0;
constant float kSt2084C1 = 107.0 / 128.0;
constant float kSt2084C2 = 2413.0 / 128.0;
constant float kSt2084C3 = 2392.0 / 128.0;

// HLG reference OOTF + inverse-OETF constants (BT.2100 reference γ=1.2).
constant float kHlgGamma    = 1.2;
constant float kHlgRefPeak  = 1000.0;
constant float kSt2084Peak  = 10000.0;
constant float kHlgA = 0.17883277;
constant float kHlgB = 0.28466892;
constant float kHlgC = 0.55991073;

// The safe-power guard (the Float64 `safePow` mirror).
static inline float drtSafePow(float x, float p) {
    return x <= 0.0f ? x : pow(x, p);
}

// ST 2084 encode/decode on the normalized linear luminance.
static inline float drtSt2084EncodeY(float y, float peak) {
    float ynits = clamp(y, 0.0f, 1.0f) * peak / kSt2084Peak;
    float yp = pow(ynits, kSt2084M1);
    return pow((kSt2084C1 + kSt2084C2 * yp) / (1.0f + kSt2084C3 * yp), kSt2084M2);
}

static inline float drtSt2084DecodeY(float code, float peak) {
    float ep = pow(clamp(code, 0.0f, 1.0f), 1.0f / kSt2084M2);
    float fraction = (ep - kSt2084C1) / (kSt2084C2 - kSt2084C3 * ep);
    // spowf guard: codes below the PQ black floor are outside the domain —
    // finite negative, never NaN (the Swift twin carries the same guard).
    float ynits = drtSafePow(fraction, 1.0f / kSt2084M1);
    return ynits * kSt2084Peak / peak;
}

// HLG inverse OETF / OETF per channel.
static inline float drtHlgOETFInverse(float scene) {
    return scene <= 1.0f / 12.0f
        ? sqrt(3.0f * scene)
        : kHlgA * log(12.0f * scene - kHlgB) + kHlgC;
}

static inline float drtHlgOETF(float signal) {
    return signal <= 0.5f
        ? signal * signal / 3.0f
        : (exp((signal - kHlgC) / kHlgA) + kHlgB) / 12.0f;
}

// HLG encode/decode on RGB (reference OOTF γ=1.2). The OOTF runs in the
// ABSOLUTE 1000-nit domain — both sides hop the peak/1000 domain at the
// boundary so the round-trip is exact for ANY peak (the Swift twin carries
// the derivation).
static inline float3 drtHlgEncode(float3 rgb, float peak) {
    float3 absolute = clamp(rgb, 0.0f, 1.0f) * (peak / kHlgRefPeak);
    float yd = 0.2627f * absolute.x + 0.6780f * absolute.y + 0.0593f * absolute.z;
    absolute *= drtSafePow(yd, (1.0f - kHlgGamma) / kHlgGamma);
    return float3(drtHlgOETFInverse(absolute.x), drtHlgOETFInverse(absolute.y),
                  drtHlgOETFInverse(absolute.z));
}

static inline float3 drtHlgDecode(float3 rgb, float peak) {
    float3 scene = float3(drtHlgOETF(rgb.x), drtHlgOETF(rgb.y), drtHlgOETF(rgb.z));
    float ys = 0.2627f * scene.x + 0.6780f * scene.y + 0.0593f * scene.z;
    return scene * drtSafePow(ys, kHlgGamma - 1.0f) * (kHlgRefPeak / peak);
}

// The uniform bridge (mirrors DrtEotfUniforms in Swift — uint + float).
struct DrtEotfUniforms {
    uint eotf;
    float peak;
};

// The SDR power family — per channel (the float3(float) constructor trap:
// a scalar result must NOT be splatted over an untouched input vector).
static inline float3 drtPowerEncode(float3 c, float gamma) {
    return float3(pow(clamp(c.x, 0.0f, 1.0f), 1.0f / gamma),
                  pow(clamp(c.y, 0.0f, 1.0f), 1.0f / gamma),
                  pow(clamp(c.z, 0.0f, 1.0f), 1.0f / gamma));
}

static inline float3 drtPowerDecode(float3 c, float gamma) {
    return float3(pow(clamp(c.x, 0.0f, 1.0f), gamma),
                  pow(clamp(c.y, 0.0f, 1.0f), gamma),
                  pow(clamp(c.z, 0.0f, 1.0f), gamma));
}

// The sRGB piecewise (IEC 61966-2-1) — the M4-1-01 KD-8 eighth ordinal.
static inline float drtSrgbPiecewiseDecode(float c) {
    float v = clamp(c, 0.0f, 1.0f);
    return v <= 0.04045f ? v / 12.92f : pow((v + 0.055f) / 1.055f, 2.4f);
}

static inline float drtSrgbPiecewiseEncode(float v) {
    float x = clamp(v, 0.0f, 1.0f);
    return x <= 0.0031308f ? x * 12.92f : 1.055f * pow(x, 1.0f / 2.4f) - 0.055f;
}

// Encode dispatch — exhaustive over the kernel ordinals, NO default
// arm (a new DrtEotf case must extend this switch at compile time).
static inline float3 drtEotfEncode(float3 rgb, uint eotf, float peak) {
    switch (eotf) {
        case 0:  // linear — identity, unclamped (the EDR linear leg).
            return rgb;
        case 1:  // st2084
            return float3(drtSt2084EncodeY(rgb.x, peak),
                          drtSt2084EncodeY(rgb.y, peak),
                          drtSt2084EncodeY(rgb.z, peak));
        case 2:  // hlg
            return drtHlgEncode(rgb, peak);
        case 3:  // gamma 2.6
            return drtPowerEncode(rgb, 2.6f);
        case 4:  // bt1886 (terminal form Lb=0 → pure 2.4)
            return drtPowerEncode(rgb, 2.4f);
        case 5:  // gamma 2.2
            return drtPowerEncode(rgb, 2.2f);
        case 6:  // gamma 1.8
            return drtPowerEncode(rgb, 1.8f);
        case 7:  // srgb piecewise (IEC 61966-2-1; KD-8)
            return float3(drtSrgbPiecewiseEncode(rgb.x),
                          drtSrgbPiecewiseEncode(rgb.y),
                          drtSrgbPiecewiseEncode(rgb.z));
    }
    return rgb;
}

static inline float3 drtEotfDecode(float3 rgb, uint eotf, float peak) {
    switch (eotf) {
        case 0:  // linear
            return rgb;
        case 1:  // st2084
            return float3(drtSt2084DecodeY(rgb.x, peak),
                          drtSt2084DecodeY(rgb.y, peak),
                          drtSt2084DecodeY(rgb.z, peak));
        case 2:  // hlg
            return drtHlgDecode(rgb, peak);
        case 3:
            return drtPowerDecode(rgb, 2.6f);
        case 4:
            return drtPowerDecode(rgb, 2.4f);
        case 5:
            return drtPowerDecode(rgb, 2.2f);
        case 6:
            return drtPowerDecode(rgb, 1.8f);
        case 7:
            return float3(drtSrgbPiecewiseDecode(rgb.x),
                          drtSrgbPiecewiseDecode(rgb.y),
                          drtSrgbPiecewiseDecode(rgb.z));
    }
    return rgb;
}

// ── the per-pixel kernels (buffer-driven — zero function constants, the
// OQ-10-A discipline carries to the EOTF box too: one PSO per direction). ──

kernel void drt_eotf_encode(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DrtEotfUniforms&       u   [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    out.write(float4(drtEotfEncode(px.rgb, u.eotf, u.peak), px.a), gid);
}

kernel void drt_eotf_decode(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DrtEotfUniforms&       u   [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    out.write(float4(drtEotfDecode(px.rgb, u.eotf, u.peak), px.a), gid);
}

// Constants-parity probe (tests only): writes the float restatements for
// the Swift side to compare against DrtEotfMath's Double constants.
// layout: [0]=m1 [1]=m2 [2]=c1 [3]=c2 [4]=c3 [5]=hlgGamma [6]=hlgA
//         [7]=hlgB [8]=hlgC [9]=2.4 [10]=2.2 [11]=2.6 [12]=1.8
kernel void drt_eotf_constants_probe(
    device float4* out [[buffer(0)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid > 0) return;
    out[0] = float4(kSt2084M1, kSt2084M2, kSt2084C1, kSt2084C2);
    out[1] = float4(kSt2084C3, kHlgGamma, kHlgA, kHlgB);
    out[2] = float4(kHlgC, 2.4f, 2.2f, 2.6f);
    out[3] = float4(1.8f, kHlgRefPeak, kSt2084Peak, 0.0f);
}
