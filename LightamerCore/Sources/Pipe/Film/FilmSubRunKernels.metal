// ─────────────────────────────────────────────────────────────────────────────
// FilmSubRunKernels.metal (Plan M3-3-02 T2, KD-1/KD-3) — the FILM SUB-RUN's
// fused single-pass kernel: negative segment (log10 → density-curve lookup →
// base) → filter pack (density form) → print-segment 65³ baked LUT
// tetrahedral sample → log-domain strength mix. ONE kernel per pixel — no
// intermediate density plane ever reaches memory (the 100MP discipline).
//
// MATH CONVENTIONS (M3-3-02-DECISIONS is the record):
//   • the exposure-normalization + manual trim ride ONE linear gain
//     (exposureGain) applied to the working-linear input;
//   • the negative segment reads the 256×3 density curves (channel-major
//     device buffer) with linear interpolation over the log10-exposure axis;
//   • the filter pack acts as a density SUBTRACTION (d′ = d − k with
//     k_M = M_total·s_m on GREEN, k_Y = Y_total·s_y on BLUE — the E3
//     vector mapping, algebraically identical to the solver's
//     x = −d + k print-exposure form);
//   • the print LUT input = the normalized density cube (per-pair
//     calibrated bounds ride the uniforms); the tetrahedral branch table
//     is the lut3d.cl:51-77 shape (the Lut3dKernels mechanism);
//   • strength (RFC-025) mixes in the DENSITY domain — log10 of linear —
//     out = in^(1−k)·film^k exactly (the geometric blend; k=1 → the film,
//     k=0 → the input);
//   • every stage is a per-pixel pure function — no barriers, no tile
//     dependencies (the FSIM-01b determinism face; the box is never
//     tile-eligible, so the exposure statistics are ONE full-plane pass
//     per run — the per-ROI red line).
// ─────────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
using namespace metal;

struct FilmSubRunUniforms {
    float exposureGain;   // the linear gain (auto normalization × 2^ev)
    float kM;             // the Magenta dial's density subtraction (G)
    float kY;             // the Yellow dial's density subtraction (B)
    float strength;       // RFC-025 density-domain mix [0, 1]
    float baseR;          // the E2 three-point base projection
    float baseG;
    float baseB;
    float axisLo;         // the curves' log10-exposure axis bounds
    float axisHi;
    float curveCountF;    // 256 (float for the interpolation math)
    float domainLoX;      // the print LUT's calibrated cube bounds
    float domainLoY;
    float domainLoZ;
    float domainHiX;
    float domainHiY;
    float domainHiZ;
    float width;
    float height;
};

/// Linear interpolation over the channel-major 256-point density table.
static inline float curveLookup(
    device const float* curves,   // [channel][index] — 3 × 256
    int channelBase,              // channel * curveCount (precomputed)
    float count,                  // 256
    float axisLo, float axisHi,
    float e)
{
    float t = clamp((e - axisLo) / (axisHi - axisLo), 0.0f, 1.0f) * (count - 1.0f);
    int i0 = (int)floor(t);
    i0 = min(max(i0, 0), (int)count - 2);
    float frac = t - (float)i0;
    float a = curves[channelBase + i0];
    float b = curves[channelBase + i0 + 1];
    return a + frac * (b - a);
}

kernel void film_subrun(
    texture2d<float, access::read>   in      [[texture(0)]],
    texture2d<float, access::write>  out     [[texture(1)]],
    texture3d<float, access::read>   printLut [[texture(2)]],
    device const float*              curves  [[buffer(0)]],
    constant FilmSubRunUniforms&     u       [[buffer(1)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    if (gid.x >= (uint)u.width || gid.y >= (uint)u.height) { return; }
    float4 c = in.read(gid);
    float3 lin = c.rgb * u.exposureGain;

    // ── the negative segment (per channel: log10 → curve → +base) ───────
    float count = u.curveCountF;
    float3 e = clamp(log10(max(lin, float3(1e-6f))), u.axisLo, u.axisHi);
    float dR = curveLookup(curves, 0, count, u.axisLo, u.axisHi, e.r) + u.baseR;
    float dG = curveLookup(curves, (int)count, count, u.axisLo, u.axisHi, e.g) + u.baseG;
    float dB = curveLookup(curves, (int)count * 2, count, u.axisLo, u.axisHi, e.b) + u.baseB;
    float3 density = float3(dR, dG, dB);

    // ── the filter pack (density subtraction; the E3 channel mapping) ───
    density.g -= u.kM;
    density.b -= u.kY;

    // ── the print LUT (normalized cube → tetrahedral, lut3d.cl:51-77) ───
    float3 lo(u.domainLoX, u.domainLoY, u.domainLoZ);
    float3 hi(u.domainHiX, u.domainHiY, u.domainHiZ);
    float3 v = clamp((density - lo) / (hi - lo), 0.0f, 1.0f);
    int level = (int)printLut.get_width();
    float3 scaled = v * (float)(level - 1);
    // rint (round-to-nearest-even) — the convert_int default the Lut3d
    // lattice mapping relies on (a bare cast truncates into the wrong
    // tetrahedron, the T2 debugging note's trap).
    int3 rgbi = min(max(int3(rint(scaled)), int3(0)), int3(level - 2));
    float3 d = scaled - float3(rgbi);
    const int L = level;
    float3 c000 = printLut.read(uint3(rgbi.x + 0, rgbi.y + 0, rgbi.z + 0)).rgb;
    float3 c100 = printLut.read(uint3(rgbi.x + 1, rgbi.y + 0, rgbi.z + 0)).rgb;
    float3 c010 = printLut.read(uint3(rgbi.x + 0, rgbi.y + 1, rgbi.z + 0)).rgb;
    float3 c110 = printLut.read(uint3(rgbi.x + 1, rgbi.y + 1, rgbi.z + 0)).rgb;
    float3 c001 = printLut.read(uint3(rgbi.x + 0, rgbi.y + 0, rgbi.z + 1)).rgb;
    float3 c101 = printLut.read(uint3(rgbi.x + 1, rgbi.y + 0, rgbi.z + 1)).rgb;
    float3 c011 = printLut.read(uint3(rgbi.x + 0, rgbi.y + 1, rgbi.z + 1)).rgb;
    float3 c111 = printLut.read(uint3(rgbi.x + 1, rgbi.y + 1, rgbi.z + 1)).rgb;
    float3 film;
    if (d.x > d.y) {
        if (d.y > d.z) {
            film = (1.0f - d.x) * c000 + (d.x - d.y) * c100 + (d.y - d.z) * c110 + d.z * c111;
        } else if (d.x > d.z) {
            film = (1.0f - d.x) * c000 + (d.x - d.z) * c100 + (d.z - d.y) * c101 + d.y * c111;
        } else {
            film = (1.0f - d.z) * c000 + (d.z - d.x) * c001 + (d.x - d.y) * c101 + d.y * c111;
        }
    } else {
        if (d.z > d.y) {
            film = (1.0f - d.z) * c000 + (d.z - d.y) * c001 + (d.y - d.x) * c011 + d.x * c111;
        } else if (d.z > d.x) {
            film = (1.0f - d.y) * c000 + (d.y - d.z) * c010 + (d.z - d.x) * c011 + d.x * c111;
        } else {
            film = (1.0f - d.y) * c000 + (d.y - d.x) * c010 + (d.x - d.z) * c110 + d.z * c111;
        }
    }

    // ── the strength mix (RFC-025, density domain = log10 of linear) ────
    float3 inLog = log10(max(lin, float3(1e-6f)));
    float3 filmLog = log10(max(film, float3(1e-6f)));
    float3 outLog = mix(inLog, filmLog, u.strength);
    float3 result = exp10(outLog);
    out.write(float4(result, c.a), gid);
}
