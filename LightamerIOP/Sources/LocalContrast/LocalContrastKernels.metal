#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// local contrast (clarity) kernels — Plan 04-05-T2, IOP-DETAIL-02
// (op "bilat", v50 slot 54.0).
//
// D-G3: the base layer is the 03-05 EIGF/guided detail-preserving
// decomposition (NOT dt bilateral / local-laplacian — DECISIONS D6).
// The kernels below are the thin luma-domain add-ons around the SHARED
// toneequal passes (`toneeq_*` — the ds downsample + pack4 + gaussian +
// blend path, dispatched from Swift):
//   1. `localcontrast_prep` Rec2020 → raw Lab (dt's pixelpipe hands the
//      module IOP_CS_LAB pixels; Lightamer converts in-kernel — the
//      shared LabMath.h, Plan 03-03-T1).
//   2. (Swift) the EIGF no-mask leg over the L plane (toneequal kernels).
//   3. `localcontrast_apply` out = luma + detail·(luma − base),
//      chroma straight through, Lab → Rec2020 return.
//
// dt REFERENCE (not ported — D-G3): `src/iop/bilat.c` — bilateral grid /
// local-laplacian dual mode, params sigma_r/sigma_s/detail(−1..4,
// DEFAULT 0.25)/midtone, `sigma_s` iscale/roi.scale compensation
// (`bilat.c:341-344`). The parity target is the SYNTHESIZED EIGF formula
// (gen_fixtures detail section), never dt-cli.
//
// L006: float32 only. L008: endEncoding precedes commit (dispatch helpers).
// ─────────────────────────────────────────────────────────────────────────

// Step 1 — Rec2020 → raw Lab (L 0..100, a/b ±128; alpha carried for the
// 4-channel blur exactly as shadhi carries it).
kernel void localcontrast_prep(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float4 px = in.read(gid);
    const float3 lab = la_rec2020_to_lab(px.rgb);
    out.write(float4(lab, px.a), gid);
}

struct LocalContrastApplyUniforms {
    float detail;       // dt `detail` (−1..4; 0 = identity)
    float pad0;
    int2 srcOffset;     // roiOut.xy − roiIn.xy (0 under tiling)
};

// Step 3 — the clarity apply: out = luma + detail·(luma − base) on L,
// a/b straight through (dt's local-laplacian enhances the L channel;
// the bilateral slice blends RGB — v1 follows the L form, the module
// header records the choice).
kernel void localcontrast_apply(
    texture2d<float, access::read>  in      [[texture(0)]],
    texture2d<float, access::read>  base    [[texture(1)]],
    texture2d<float, access::write> out     [[texture(2)]],
    constant LocalContrastApplyUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const uint2 src = uint2(int2(gid) + u.srcOffset);
    const float4 io = in.read(src);
    const float b = base.read(src).r;

    const float3 lab = la_rec2020_to_lab(io.rgb);
    const float outL = lab.x + u.detail * (lab.x - b);
    out.write(float4(la_lab_to_rec2020(float3(outL, lab.y, lab.z)), io.a), gid);
}
