#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// equalizer (clarity/detail-enhancement) kernels — Plan 04-05-T4,
// IOP-DETAIL-04 (op "equalizer", v50 slot 27.0).
//
// D-G4: gaussian half-octave pyramid (σ doubling 1/2/4/8/16) → per-band
// residuals → per-band gains → recombine. The architecture mirrors
// toneequal's CorrectionLUT "parameters → per-band values → apply"
// (band→gain→recombine), with UNIFORM gains in v1 (no 80001-entry LUT —
// the LUT exists to serve a CURVE; six sliders need six uniforms,
// DECISIONS D-04-05-T0-3 / D8).
//
// dt REFERENCE (not ported): `src/iop/equalizer.c` (DEPRECATED legacy
// equalizer — 3-channel × 6-point curves over a lifting-scheme wavelet)
// and the contrast-equalizer `equalizer_eaw.h` edge-aware wavelet
// (`gweight` edge weights). v1 uses PURE gaussian bands (no edge-aware
// weights); the deviation is recorded on the module header.
//
// Pipeline:
//   1. `equalizer_prep`  Rec2020 → raw Lab (dt's pipe hands IOP_CS_LAB;
//                         Lightamer converts in-kernel — LabMath.h).
//   2. (Swift) GaussianBlur at σ = 1/2/4/8/16 over the Lab plane
//      (UNBOUNDED — same discipline as sharpen).
//   3. `equalizer_recombine` L = g5·B5 + Σ gᵢ·(B(i−1) − Bᵢ) with
//      B0 = L; a/b straight through; Lab → Rec2020 return.
//
// IDENTITY: all multipliers 1 ⇒ L = B5 + Σ(B(i−1) − Bᵢ) = B0 = L
// telescopically (float rounding only — the synthesized reference pins
// <1e-5; the ALL-ZERO-delta fast path is the bit-exact gate).
//
// L006: float32 only. L008: endEncoding precedes commit.
// ─────────────────────────────────────────────────────────────────────────

// Step 1 — Rec2020 → raw Lab (L 0..100; alpha carried for the
// 4-channel blur exactly as sharpen carries it).
kernel void equalizer_prep(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float4 px = in.read(gid);
    const float3 lab = la_rec2020_to_lab(px.rgb);
    out.write(float4(lab, px.a), gid);
}

// Six scalar multipliers + padding (NO constant float array — the
// ashift `float hinv[9]` packing postmortem: scalar floats are 4-byte
// aligned on both sides, arrays may stride 16 on the MSL side).
struct EqualizerRecombineUniforms {
    float g0;
    float g1;
    float g2;
    float g3;
    float g4;
    float g5;
    int2 srcOffset;     // roiOut.xy − roiIn.xy (0 under tiling)
};

// Step 3 — the pyramid recombine (residuals against the BLURRED planes;
// B0 is the prep plane itself).
kernel void equalizer_recombine(
    texture2d<float, access::read>  prep    [[texture(0)]],
    texture2d<float, access::read>  b1      [[texture(1)]],
    texture2d<float, access::read>  b2      [[texture(2)]],
    texture2d<float, access::read>  b3      [[texture(3)]],
    texture2d<float, access::read>  b4      [[texture(4)]],
    texture2d<float, access::read>  b5      [[texture(5)]],
    texture2d<float, access::read>  orig    [[texture(6)]],
    texture2d<float, access::write> out     [[texture(7)]],
    constant EqualizerRecombineUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint2 src = uint2(int2(gid) + u.srcOffset);
    const float b0 = prep.read(src).x;
    const float v1 = b1.read(src).x;
    const float v2 = b2.read(src).x;
    const float v3 = b3.read(src).x;
    const float v4 = b4.read(src).x;
    const float v5 = b5.read(src).x;
    const float outL = u.g0 * (b0 - v1)
                     + u.g1 * (v1 - v2)
                     + u.g2 * (v2 - v3)
                     + u.g3 * (v3 - v4)
                     + u.g4 * (v4 - v5)
                     + u.g5 * v5;

    const float4 io = orig.read(src);
    const float3 lab = la_rec2020_to_lab(io.rgb);
    out.write(float4(la_lab_to_rec2020(float3(outL, lab.y, lab.z)), io.a), gid);
}
