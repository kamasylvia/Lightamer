// ─────────────────────────────────────────────────────────────────────────
// ColorMatchKernels.metal (Plan M5-1-01 T6, KD-6) — the colormatch linear
// arm: one single-pass pointwise kernel, working float32 RGBA linear
// Rec2020 in/out (the application domain IS the working space, OQ-M5-1-2 —
// no encoding semantics on the linear arm).
//
// CHAIN (per pixel):
//   lab      = M2 · cbrt₃(M1C · rgb)                    — Oklab (Float32)
//   out_lab  = lab + α·((M−I)·lab + c)                  — the strength lerp
//   out_rgb  = M1C⁻¹ · (M2⁻¹·out_lab)³                  — back to working
//
// CONSTANT SINGLE SOURCE: the four matrices mirror LightamerCore's
// OklabMath.swift — the SAME Float32 literals (M1C = M1·M(2020→709)
// pre-merged, Ottosson M2/M2⁻¹ published constants; the derivation and
// provenance live in that header — this file points there, never re-derives).
// All matrices ROW-MAJOR 9-tuples and applied with the SAME scalar
// row-multiply as the Swift side (the G2 parity mirror).
//
// SIGN-PRESERVING cube root (checker 回注 m1): negative LMS is legal
// (Rec2020 gamut corners, pipeline negatives) — sign(lms)·|lms|^(1/3); a
// bare pow(x, 1/3) would NaN. The G2 drive set carries negative-LMS probes.
//
// FULL DOMAIN: zero clamps anywhere (the matrix-arm ruling) — HDR and
// negative values pass through.
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
using namespace metal;

// Row-major 9-tuples — the OklabMath literals verbatim (single source).
constant float kM1c[9] = {
    0.6167557872, 0.36019839939, 0.023045813408,
    0.26513306398, 0.63583936408, 0.099027571839,
    0.10010263423, 0.2039065194, 0.69599084637,
};
constant float kM2[9] = {
    0.2104542553, 0.7936177850, -0.0040720468,
    1.9779984951, -2.4285922050, 0.4505937099,
    0.0259040371, 0.7827717662, -0.8086757660,
};
constant float kM2Inv[9] = {
    0.99999999845051981432, 0.39633779217376785678, 0.21580375730991364839,
    1.00000000888176035663, -0.10556134232365634970, -0.06385417477170590340,
    1.00000005467241091770, -0.08948418209496575968, -1.29148553786409173990,
};
constant float kM1cInv[9] = {
    2.139906736, -1.2463895092, 0.1064827732,
    -0.88473586287, 2.1632309824, -0.27849511958,
    -0.04857375783, -0.45450314311, 1.5030769009,
};
// ONE third — the exact Float32 quotient (Swift's `Float(1.0)/Float(3.0)`
// mirror; the same spelling feeds both signed cbrts).
constant float kOneThird = 1.0f / 3.0f;

static inline float3 mulRowMajor9(constant float* m, float3 v) {
    return float3(
        m[0] * v.x + m[1] * v.y + m[2] * v.z,
        m[3] * v.x + m[4] * v.y + m[5] * v.z,
        m[6] * v.x + m[7] * v.y + m[8] * v.z);
}

static inline float signedCbrt(float x) {
    // precise:: — the MSL default compiles fast-math (the plain pow is the
    // approximate form; the FilmPlacement kernel precedent) and the parity
    // gate measures against the precise CPU face.
    return x >= 0.0f ? precise::pow(x, kOneThird) : -precise::pow(-x, kOneThird);
}

static inline float3 signedCbrt3(float3 v) {
    return float3(signedCbrt(v.x), signedCbrt(v.y), signedCbrt(v.z));
}

// The flat uniform ABI (ColorMatchUniforms.swift — field-for-field; 13
// floats, 52 bytes, no padding, zero function constants).
struct ColormatchUniforms {
    float mi0; float mi1; float mi2;
    float mi3; float mi4; float mi5;
    float mi6; float mi7; float mi8;
    float c0; float c1; float c2;
    float strength;
};

kernel void colormatch_linear(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ColormatchUniforms& u     [[buffer(0)]],
    uint2 gid                          [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    // Working linear Rec2020 → Oklab.
    float3 lab = mulRowMajor9(kM2, signedCbrt3(mulRowMajor9(kM1c, px.rgb)));
    // The strength lerp in the α-invariant expansion: x + α·((M−I)·x + c).
    float3 mapped = float3(
        u.mi0 * lab.x + u.mi1 * lab.y + u.mi2 * lab.z,
        u.mi3 * lab.x + u.mi4 * lab.y + u.mi5 * lab.z,
        u.mi6 * lab.x + u.mi7 * lab.y + u.mi8 * lab.z)
        + float3(u.c0, u.c1, u.c2);
    float3 outLab = lab + u.strength * mapped;
    // Oklab → working linear Rec2020 (the cube as a plain triple product).
    float3 lmsP = mulRowMajor9(kM2Inv, outLab);
    float3 lms = lmsP * lmsP * lmsP;
    float3 rgb = mulRowMajor9(kM1cInv, lms);
    out.write(float4(rgb, px.a), gid);
}
