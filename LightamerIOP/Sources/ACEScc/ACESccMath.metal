// ─────────────────────────────────────────────────────────────────────────
// ACESccMath.metal (Plan M2-5-1 T2, KD-2) — THE single constant/function
// source for the ACEScc grade domain.
//
// RED LINE: every ACEScc-domain kernel (the acesccIn/acesccOut envelope
// pair AND the in-domain grade kernels: cat02WhiteBalance, contrast,
// white/black, saturation, tint, colorWheels, hls) includes THIS file and
// uses THESE functions/constants — a domain kernel MUST NOT carry its own
// matrix or encode/decode constants (the golden tests pin one derivation;
// a private copy would fork the domain).
//
// Contents:
//   1. The linear Rec2020 → AP1 chromatic-adaptation matrix (and its
//      inverse) — CAT02 cone adaptation from D65 to the ACES white
//      (0.32168, 0.33767), derived in Float64 and frozen as float32 rows.
//   2. The ACEScc log encode/decode (the S-2014-003分段式 — the exact
//      constants the Alcedo grade shaders ride: A 9.72 / B 17.52 /
//      offset 2^-16 / transition 2^-15; the below-floor leg extends
//      linearly instead of clamping, matching ACEScc's negative-value
//      extension).
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
using namespace metal;

// Linear Rec2020 → linear AP1 (D65 → ACES white via CAT02; Float64
// derivation, float32 constants).
static inline float3 rec2020_to_ap1(float3 c) {
    return float3(
        0.9746957094f * c.x + 0.0216339018f * c.y + 0.0036703892f * c.z,
        0.0016784990f * c.x + 0.9977360501f * c.y + 0.0005854509f * c.z,
        0.0048862547f * c.x + 0.0211319325f * c.y + 0.9739818127f * c.z);
}

// Linear AP1 → linear Rec2020 (the inverse of the float32 rows above, so
// the encode∘decode round trip folds to ~float32 epsilon, not worse).
static inline float3 ap1_to_rec2020(float3 c) {
    return float3(
        1.0260187362f * c.x - 0.0221655466f * c.y - 0.0038531637f * c.z,
        -0.0017230808f * c.x + 1.0023190849f * c.y - 0.0005959909f * c.z,
        -0.0051099280f * c.x - 0.0216355511f * c.y + 1.0267454940f * c.z);
}

// ACEScc encode (linear AP1 → ACEScc log; S-2014-003分段式 with the
// linear negative extension).
static inline float acescc_encode(float value) {
    const float kA = 9.72f;
    const float kB = 17.52f;
    const float kOffset = 0.0000152587890625f;    // 2^-16
    const float kTransition = 0.000030517578125f; // 2^-15
    const float kFloor = (-16.0f + kA) / kB;
    if (value < 0.0f) {
        return kFloor + value;
    }
    if (value < kTransition) {
        return (log2(kOffset + value * 0.5f) + kA) / kB;
    }
    return (log2(value) + kA) / kB;
}

// ACEScc decode (ACEScc log → linear AP1; the exact inverse).
static inline float acescc_decode(float value) {
    const float kA = 9.72f;
    const float kB = 17.52f;
    const float kOffset = 0.0000152587890625f;
    const float kFloor = (-16.0f + kA) / kB;
    const float kThreshold = (-15.0f + kA) / kB;
    if (value < kFloor) {
        return value - kFloor;
    }
    if (value <= kThreshold) {
        return (exp2(value * kB - kA) - kOffset) * 2.0f;
    }
    return exp2(value * kB - kA);
}
