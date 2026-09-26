#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// Lut3d kernels (Plan 12-5 T2, IOP-COLOR-08).
//
// Darktable reference: data/kernels/lut3d.cl:29-60 (tetrahedral verbatim —
// the three delta comparisons split the sampling hexahedron into one of six
// tetrahedra with barycentric weights; output weight sum is exactly 1.0).
//
// Port deltas (RESEARCH §6.2, all three are capability/parity-preserving):
// 1. CLUT is a `texture3d<float, access::read>` rgba16Float (dt: a __global
//    float buffer indexed r + g*L + b*L²). read(uint3) with INTEGER lattice
//    coordinates is the exact same data access — no sampler, no hardware
//    filtering (float-class textures are not filterable in Metal anyway);
//    the eight corners are fetched manually exactly like dt's eight
//    clut[iXXX] loads.
// 2. The DOMAIN remap folds into the index math BEFORE scaling (RESEARCH
//    §6.3): v' = (clamp(v, domMin, domMax) - domMin) / (domMax - domMin).
//    dt hard-rejects non-0..1 domains (lut3d.c:782-791) — this is the
//    Lightamer capability extension (F4). With the default 0..1 domain the
//    formula degenerates to dt's clip4 + scale exactly.
// 3. The application color space matrix is FUSED as uniforms (working
//    linear-Rec2020 → LUT domain before the table, inverse after) — dt does
//    the conversion in separate iop passes; one fused pass keeps the 100MP
//    budget. Identity matrices (the T2 default) = dt's no-transform path.
// ─────────────────────────────────────────────────────────────────────────

struct Lut3dUniforms {
    uint width;
    uint height;
    uint level;
    float domainMinX;
    float domainMinY;
    float domainMinZ;
    float domainMaxX;
    float domainMaxY;
    float domainMaxZ;
    float fwd[9];   // working → LUT domain, row-major (T4 fills; T2 identity)
    float inv[9];   // LUT domain → working
};

float3 lut3dApplyRowMajor(constant float *m, float3 v) {
    return float3(
        m[0] * v.x + m[1] * v.y + m[2] * v.z,
        m[3] * v.x + m[4] * v.y + m[5] * v.z,
        m[6] * v.x + m[7] * v.y + m[8] * v.z);
}

// The shared tetrahedral/trilinear prologue: working → domain matrix, then
// the dt lattice mapping (`rgbd = input * (level-1)`; `rgbi = clamp(
// convert_int(rgbd), 0, level-2)`; fractions = rgbd - rgbi). convert_int
// default rounding is rtne in BOTH OpenCL and Metal — verbatim parity.
float3 lut3dLattice(float3 rgb, constant Lut3dUniforms &u, thread int3 &rgbi) {
    float3 lo(u.domainMinX, u.domainMinY, u.domainMinZ);
    float3 hi(u.domainMaxX, u.domainMaxY, u.domainMaxZ);
    float3 v = lut3dApplyRowMajor(u.fwd, rgb);
    v = (clamp(v, lo, hi) - lo) / (hi - lo);
    float3 scaled = v * (float)(u.level - 1);
    // rint = round-to-nearest-even — the OpenCL convert_int default dt
    // relies on (a bare int3(scaled) TRUNCATES: 2.6 → 2 instead of 3, which
    // shifts every non-lattice sample into the wrong tetrahedron; caught by
    // the CPU-float64 parity gate, T2 debugging note).
    rgbi = min(max(int3(rint(scaled)), int3(0)), int3((int)u.level - 2));
    return scaled - float3(rgbi);
}

kernel void lut3d_tetrahedral(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    texture3d<float, access::read> clut [[texture(2)]],
    constant Lut3dUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.width || gid.y >= u.height) return;
    float4 input = in.read(gid);

    int3 rgbi;
    float3 d = lut3dLattice(input.rgb, u, rgbi);
    const int L = (int)u.level;

    // The eight lattice corners (dt clut000…clut111, lut3d.cl:40-48).
    float3 c000 = clut.read(uint3(rgbi.x + 0, rgbi.y + 0, rgbi.z + 0)).rgb;
    float3 c100 = clut.read(uint3(rgbi.x + 1, rgbi.y + 0, rgbi.z + 0)).rgb;
    float3 c010 = clut.read(uint3(rgbi.x + 0, rgbi.y + 1, rgbi.z + 0)).rgb;
    float3 c110 = clut.read(uint3(rgbi.x + 1, rgbi.y + 1, rgbi.z + 0)).rgb;
    float3 c001 = clut.read(uint3(rgbi.x + 0, rgbi.y + 0, rgbi.z + 1)).rgb;
    float3 c101 = clut.read(uint3(rgbi.x + 1, rgbi.y + 0, rgbi.z + 1)).rgb;
    float3 c011 = clut.read(uint3(rgbi.x + 0, rgbi.y + 1, rgbi.z + 1)).rgb;
    float3 c111 = clut.read(uint3(rgbi.x + 1, rgbi.y + 1, rgbi.z + 1)).rgb;

    // lut3d.cl:51-77 verbatim — the three-way delta comparison selects the
    // containing tetrahedron; weights are its barycentric coordinates.
    float3 output;
    if (d.x > d.y) {
        if (d.y > d.z) {
            output = (1.0f - d.x) * c000 + (d.x - d.y) * c100 + (d.y - d.z) * c110 + d.z * c111;
        } else if (d.x > d.z) {
            output = (1.0f - d.x) * c000 + (d.x - d.z) * c100 + (d.z - d.y) * c101 + d.y * c111;
        } else {
            output = (1.0f - d.z) * c000 + (d.z - d.x) * c001 + (d.x - d.y) * c101 + d.y * c111;
        }
    } else {
        if (d.z > d.y) {
            output = (1.0f - d.z) * c000 + (d.z - d.y) * c001 + (d.y - d.x) * c011 + d.x * c111;
        } else if (d.z > d.x) {
            output = (1.0f - d.y) * c000 + (d.y - d.z) * c010 + (d.z - d.x) * c011 + d.x * c111;
        } else {
            output = (1.0f - d.y) * c000 + (d.y - d.x) * c010 + (d.x - d.z) * c110 + d.z * c111;
        }
    }

    // LUT domain → working matrix (identity through T2).
    float3 mapped = lut3dApplyRowMajor(u.inv, output);
    out.write(float4(mapped, input.w), gid);
}

// The trilinear second state (dt DT_IOP_TRILINEAR, lut3d.c:1020) — eight
// corners, axis weights (the ~15-line sibling the golden comparison uses).
kernel void lut3d_trilinear(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    texture3d<float, access::read> clut [[texture(2)]],
    constant Lut3dUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.width || gid.y >= u.height) return;
    float4 input = in.read(gid);

    int3 rgbi;
    float3 d = lut3dLattice(input.rgb, u, rgbi);

    float3 c000 = clut.read(uint3(rgbi.x + 0, rgbi.y + 0, rgbi.z + 0)).rgb;
    float3 c100 = clut.read(uint3(rgbi.x + 1, rgbi.y + 0, rgbi.z + 0)).rgb;
    float3 c010 = clut.read(uint3(rgbi.x + 0, rgbi.y + 1, rgbi.z + 0)).rgb;
    float3 c110 = clut.read(uint3(rgbi.x + 1, rgbi.y + 1, rgbi.z + 0)).rgb;
    float3 c001 = clut.read(uint3(rgbi.x + 0, rgbi.y + 0, rgbi.z + 1)).rgb;
    float3 c101 = clut.read(uint3(rgbi.x + 1, rgbi.y + 0, rgbi.z + 1)).rgb;
    float3 c011 = clut.read(uint3(rgbi.x + 0, rgbi.y + 1, rgbi.z + 1)).rgb;
    float3 c111 = clut.read(uint3(rgbi.x + 1, rgbi.y + 1, rgbi.z + 1)).rgb;

    float3 output = mix(
        mix(mix(c000, c100, d.x), mix(c010, c110, d.x), d.y),
        mix(mix(c001, c101, d.x), mix(c011, c111, d.x), d.y),
        d.z);

    float3 mapped = lut3dApplyRowMajor(u.inv, output);
    out.write(float4(mapped, input.w), gid);
}
