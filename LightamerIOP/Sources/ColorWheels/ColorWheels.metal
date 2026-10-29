// ─────────────────────────────────────────────────────────────────────────
// ColorWheels.metal (Plan M2-5-1 T6, KD-6) — the LGG three-wheel op
// (primary_grade behavior 11), applied on the ACEScc texels:
//   gammaLeg = max(gamma.color + gamma.luma, 1e-4)          (per channel)
//   out      = sign(c) · |c + lift.color + lift.luma|^(1/gammaLeg)
//              · gain.color                                  (per channel)
// The runtime packing (Alcedo adjustment_runtime.cpp behavior-11) carries
// ONLY colorOffset + luminanceOffset — the trackball's disc/strength are
// UI state and do not reach the pixels. gain.luminanceOffset is packed by
// Alcedo but UNUSED by the kernel (faithful). Identity
// (lift 0 / gamma (1,1,1) / gain (1,1,1)) takes the CPU's early-exit flag
// for a byte-identical copy.
// ─────────────────────────────────────────────────────────────────────────
#include <metal_stdlib>
using namespace metal;

struct ColorWheelsUniforms {
    float flag;       // 0 = identity early exit, 1 = apply
    float liftX; float liftY; float liftZ;
    float liftLuma;
    float gammaX; float gammaY; float gammaZ;
    float gammaLuma;
    float gainX; float gainY; float gainZ;
    float gainLuma;   // packed, unused (the Alcedo kernel ignores it)
    float pad0;
};

kernel void grade_color_wheels(
    texture2d<float, access::read>    in  [[texture(0)]],
    texture2d<float, access::write>   out [[texture(1)]],
    constant ColorWheelsUniforms&     u   [[buffer(0)]],
    uint2 gid                             [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    if (u.flag < 0.5f) {
        out.write(c, gid);
        return;
    }
    const float gammaLegX = max(u.gammaX + u.gammaLuma, 1.0e-4f);
    const float gammaLegY = max(u.gammaY + u.gammaLuma, 1.0e-4f);
    const float gammaLegZ = max(u.gammaZ + u.gammaLuma, 1.0e-4f);
    float3 r;
    r.x = copysign(
        precise::pow(abs(c.x + u.liftX + u.liftLuma), 1.0f / gammaLegX), c.x) * u.gainX;
    r.y = copysign(
        precise::pow(abs(c.y + u.liftY + u.liftLuma), 1.0f / gammaLegY), c.y) * u.gainY;
    r.z = copysign(
        precise::pow(abs(c.z + u.liftZ + u.liftLuma), 1.0f / gammaLegZ), c.z) * u.gainZ;
    out.write(float4(r, c.a), gid);
}

// ─────────────────────────────────────────────────────────────────────────
// v3 tone wheels (Plan M9-4 T1, X1 — the upstream color_wheel_tone.hpp/.cpp
// ApplyToneWheels transliteration at commit e1effd8, GPL-3.0-only +
// section 7 additional permission; see ColorWheelsLegacyConvert.swift for
// the preserved header). The four wheels (Offset/Lift/Gamma/Gain) run in
// that order on the ACEScc texel through the normalized tone coordinate
// t = (acescc − black)/range:
//   Offset: ev' = ev + K                       (all tones, applied first)
//   Lift:   t' = t + (K/R)·clamp(1 − t, 0, 1)
//   Gamma:  t' = t^p, p = ln(max(0.5+K/R,0.05))/ln(0.5), only 0 < t < 1
//   Gain:   t' = t + (K/R)·max(t, 0)
// The existing grade_color_wheels above is the FROZEN v1 arm
// (D-M9SP-1 — byte-intact); this v3 kernel is THE ONLY new kernel of the
// batch (D-M9SP-9 申报面清单).
// ─────────────────────────────────────────────────────────────────────────

struct ToneWheelUniforms {
    float offsetR; float offsetG; float offsetB;   // ACEScc increment per channel
    float liftR; float liftG; float liftB;         // K / R
    float gammaR; float gammaG; float gammaB;      // exponent p
    float gainR; float gainG; float gainB;         // K / R
    float toneBlack;                               // ACEScc at t = 0
    float toneRange;                               // ACEScc width t = 0..1
};  // 14 floats

/// One channel of the upstream ApplyToneWheels (scalar branch form — the
/// direct transliteration; the neutral early exit stays bit-exact: neutral
/// Lift/Gamma/Gain leaves the value exact, only the Offset applies).
static float toneWheelChannel(
    float acescc, float offset, float lift, float p, float gain,
    float black, float range)
{
    float v = acescc + offset;
    if (lift == 0.0f && p == 1.0f && gain == 0.0f) {
        return v;
    }
    float t = (v - black) / range;
    t += lift * clamp(1.0f - t, 0.0f, 1.0f);
    if (t > 0.0f && t < 1.0f) {
        t = precise::pow(t, p);
    }
    t += gain * max(t, 0.0f);
    return black + t * range;
}

kernel void grade_color_wheels_v3(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant ToneWheelUniforms&     u   [[buffer(0)]],
    uint2 gid                           [[thread_position_in_grid]])
{
    float4 c = in.read(gid);
    // Offset → Lift → Gamma → Gain, per channel (upstream order).
    float r = toneWheelChannel(c.x, u.offsetR, u.liftR, u.gammaR, u.gainR, u.toneBlack, u.toneRange);
    float g = toneWheelChannel(c.y, u.offsetG, u.liftG, u.gammaG, u.gainG, u.toneBlack, u.toneRange);
    float b = toneWheelChannel(c.z, u.offsetB, u.liftB, u.gammaB, u.gainB, u.toneBlack, u.toneRange);
    out.write(float4(r, g, b, c.a), gid);
}
