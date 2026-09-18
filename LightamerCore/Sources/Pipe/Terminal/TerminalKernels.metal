#include <metal_stdlib>
using namespace metal;

// Terminal-trio kernels (Plan 02-04) — Core's own default.metallib. These
// kernels are pipeline INFRASTRUCTURE (they live in LightamerCore next to
// the pixelpipe, not in LightamerIOP), so tests and the golden harness run
// the full display chain with ZERO LightamerIOP dependency (02-04 plan,
// research Open Question #2 resolution).
//
// L006: full float math on every shadow-sensitive path — no half anywhere.

// ── terminal_copy ────────────────────────────────────────────────────────
// Bit-identical float4 copy. The pipe's currency contract (02-02 lock #1)
// makes a copy (not aliasing) the safest identity: cached planes are
// write-once-then-readonly, so an "identity" module must still produce its
// OWN output plane — the pipe allocates distinct input/output planes, and
// this kernel fills them.
//
// Consumers: `ColorInModule.process` (the colorin identity — see the
// architecture note there) and the colorout ColorSync fallback leg (the
// off-line converted plane is blitted into the pipe's output allocation).
kernel void terminal_copy(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid                           [[thread_position_in_grid]])
{
    out.write(in.read(gid), gid);
}

// ── colorout_matrix ──────────────────────────────────────────────────────
// Linear Rec2020 → linear display gamut (gamut matrix ONLY — the TRC
// encode is gamma_encode's job; D-COL4 keeps this stage float32 unclamped).
//
// D-17: the `isP3` function constant folds into one of two PSO variants at
// index 0 (Swift side: ColorOutModule.constants(forP3:metal:)). NO MSL
// default is declared — Swift MUST set the constant (RESEARCH §3 gotcha).
//
// Matrix derivation (row-major, out_i = Σ_j M[i][j]·in_j) — primaries and
// white point, and the generator script, are cited at the top of
// ColorOutModule.swift:
//   P3   = [ 1.343930183, -0.282585998, -0.061344185 ]
//          [-0.066855841,  1.077337009, -0.010481169 ]
//          [ 0.003750840, -0.019626716,  1.015875875 ]
//   sRGB = [ 1.661272640, -0.588487320, -0.072785321 ]
//          [-0.126189204,  1.134531230, -0.008342025 ]
//          [-0.017014775, -0.100723728,  1.117738502 ]
// Both map D65 → (1,1,1) and gray → gray EXACTLY (the D-COL1 neutrality
// precondition). MSL float3x3(col0, col1, col2) takes COLUMNS; the columns
// below are the transposed rows of the row-major matrices above, so
// `M * c` computes out_i = Σ_j M[i][j]·c_j.
constant bool isP3 [[function_constant(0)]];

kernel void colorout_matrix(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid                           [[thread_position_in_grid]])
{
    float3 c = in.read(gid).rgb;
    float3x3 m = isP3
        ? float3x3(float3( 1.343930183, -0.066855841,  0.003750840),
                   float3(-0.282585998,  1.077337009, -0.019626716),
                   float3(-0.061344185, -0.010481169,  1.015875875))
        : float3x3(float3( 1.661272640, -0.126189204, -0.017014775),
                   float3(-0.588487320,  1.134531230, -0.100723728),
                   float3(-0.072785321, -0.008342025,  1.117738502));
    float4 px = in.read(gid);
    out.write(float4(m * c, px.a), gid);
}

// ── gamma_encode ─────────────────────────────────────────────────────────
// The ONLY place display encoding happens (research §3.3 — Darktable
// `gamma.c` analog): the exact sRGB segmented TRC ENCODE
//   c <= 0.04045 ? c/12.92 : 1.055*pow(c, 1.0/2.4) - 0.055
// per channel (the INVERSE — pow((c+0.055)/1.055, 2.4) — is the DECODE
// direction; the exponent is 1/2.4 here), in FULL FLOAT precision (L006 —
// no half on the TRC math), clamped to [0,1] (D-COL4: clamping happens
// HERE only — pipe interior stays float32 unclamped; EDR headroom is
// Phase 8) and written to the `.bgra8Unorm` display plane. Metal converts
// float→unorm on write; BGRA byte order is transparent for compute write
// (rgba vector semantics).
//
// P3 and sRGB share this TRC, so ONE kernel serves both fast-path gamuts
// and the ColorSync workalike.
kernel void gamma_encode(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid                           [[thread_position_in_grid]])
{
    float4 px = in.read(gid);
    float3 c = clamp(px.rgb, 0.0, 1.0);
    c = select(c / 12.92,
               1.055 * pow(c, float3(1.0 / 2.4)) - 0.055,
               c > 0.04045);
    out.write(float4(c, 1.0), gid);
}
