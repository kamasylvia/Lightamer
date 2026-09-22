#include <metal_stdlib>
#include "../Common/LabMath.h"
using namespace metal;

// Kernel uniform structs (scalar kernel arguments cannot carry [[buffer]]
// attributes in MSL — each kernel takes ONE constant struct; the Swift
// side mirrors the layouts field-for-field, all scalars 4-byte).
struct NLMeansDistParams {
    uint width;
    uint height;
    int qx;
    int qy;
    float nL2;
    float nC2;
};
struct NLMeansBoxParams {
    uint width;
    uint height;
    int P;
};
struct NLMeansVertParams {
    uint width;
    uint height;
    int P;
    float sharpness;
};
struct NLMeansAccuParams {
    uint width;
    uint height;
    int qx;
    int qy;
};
struct NLMeansFinishParams {
    uint width;
    uint height;
    float2 align_pad; // float4 member aligns to 16 — pad the gap explicitly
    float4 weight;
};

// ─────────────────────────────────────────────────────────────────────────
// NLMeans kernel group (Plan 05-06-T1, IOP-DENOISE-02) — verbatim port of
// darktable `data/kernels/nlmeans.cl:26-253` (tree dc58cf0ba1), the
// Goossens et al. 2010 sliding-window scheme ("A GPU-Accelerated Real-Time
// NLMeans Algorithm for Denoising Color Video Sequences", ACIVS 2010):
// the O(N·(2P+1)²) patch distance decomposes into a per-offset distance map
// + two separable box accumulations (horiz → vert) so each search offset
// costs exactly 4 kernels (dist/horiz/vert/accu) + one final finish.
//
// DOMAIN: the input texture is already CIE Lab (the module runs ONE
// nlmeans_lab_forward pass first — dt gets Lab from the pipeline around
// IOP_CS_LAB modules; we convert in-module, same per-pixel math via the
// shared LabMath.h). norm2 = (nL², nC², nC²) with nL = 1/120, nC = 1/512
// (nlmeans.c:176-179,362-365).
//
// L018 DISCIPLINE (03-04/05-07 lessons, plan T1 mandate): every
// intermediate lives in `device float*` / `device float4*` BUFFER planes —
// NEVER a read_write texture (same-thread RMW reads 0 on M4/macOS 27).
// The accu kernel is a read-modify-write on a device buffer (program order
// is guaranteed — dt nlmeans.cl:229 `U2[gidx] += accu` same shape); U2 is
// zero-filled ONCE per run by the host (nlmeans.c:262 fill). The 4
// single-channel distance buckets rotate host-side (dt buckets
// NUM_BUCKETS=4, nlmeans.c:229-310) so no pass reads what the previous
// pass of the SAME offset writes... except dist→horiz which is a
// producer→consumer pair across dispatches (FIFO command buffers, dt
// relies on the same in-order queue semantics).
//
// fast_mexp2f (dt common.h:181-191) is ported BIT-EXACT: the dt trick
// builds the exponent field arithmetically in FLOAT-VALUE space (i1/i2 are
// the bit patterns of 1.0/0.5 reinterpreted as integer VALUES — 1065353216
// / 1056964608, both exactly representable in float32) and truncates to an
// integer whose bits ARE the result float. w = gh(dist, sharpness)
// ≈ 2^(−dist·sharpness) — monotone decay, NOT libm exp; the Python golden
// reference mirrors the same bit trick.
// ─────────────────────────────────────────────────────────────────────────

// dt common.h:181-191 verbatim (float-value-space bit construction).
inline float nlmeans_fast_mexp2f(const float x) {
    const float i1 = 1065353216.0f; // (float)0x3f800000u — bits of 1.0
    const float i2 = 1056964608.0f; // (float)0x3f000000u — bits of 0.5
    const float k0 = i1 + x * (i2 - i1);
    // dt: k.i = (k0 >= (float)0x800000u) ? k0 : 0 — the threshold is the
    // VALUE 8388608 (= 2^23, the smallest normal's bit pattern as int
    // value); the float→uint conversion truncates k0's integer value and
    // stores it as the RESULT's bit pattern.
    return (k0 >= 8388608.0f) ? as_type<float>((uint)k0) : 0.0f;
}

// dt nlmeans.cl:26-30 — "make sharpness bigger: less smoothing".
inline float nlmeans_gh(const float f, const float sharpness) {
    return nlmeans_fast_mexp2f(f * sharpness);
}

// dt nlmeans.cl:32-35 — Kronecker delta for the symmetric accumulation.
inline float nlmeans_ddirac(const int qx, const int qy) {
    return ((qx != 0) || (qy != 0)) ? 1.0f : 0.0f;
}

// Bounds-clamped Lab-plane read (the dt kernels read through a
// clamp-to-edge sampler via readpixel(); every USE in nlmeans.cl either
// pre-zeros out-of-bounds contributions (dist :52-65, accu :201-219) or
// clamps the index first (accu :222) — a clamped read reproduces both
// shapes with the same arithmetic).
inline float4 nl_read(texture2d<float, access::read> plane, int x, int y) {
    const int cx = clamp(x, 0, (int)plane.get_width() - 1);
    const int cy = clamp(y, 0, (int)plane.get_height() - 1);
    return plane.read(uint2(cx, cy));
}

// Pass 0 — linear Rec2020 → CIE Lab (the module-domain entry; dt's
// pipeline provides Lab around IOP_CS_LAB modules, we pay ONE pass).
kernel void nlmeans_lab_forward(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const float4 px = in.read(gid);
    out.write(float4(la_rec2020_to_lab(px.rgb), px.a), gid);
}

// dt nlmeans.cl:37-68 — single-offset squared distance map:
// |I(p) − I(p+q)|² · norm2 → one channel of U4; out-of-bounds p+q → 0.
kernel void nlmeans_dist(
    texture2d<float, access::read> in [[texture(0)]],
    device float* U4 [[buffer(0)]],
    constant NLMeansDistParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int width = (int)params.width;
    const int height = (int)params.height;
    const int qx = params.qx;
    const int qy = params.qy;
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= width || y >= height) { return; }
    const int gidx = y * width + x;

    // dt :52-57: out-of-bounds indexes clamp to 0 (then dist is zeroed
    // below — the clamped read's value is multiplied away).
    const int xpq = ((x + qx) >= 0 && (x + qx) < (int)width)  ? (x + qx) : 0;
    const int ypq = ((y + qy) >= 0 && (y + qy) < (int)height) ? (y + qy) : 0;

    const float4 norm2 = float4(params.nL2, params.nC2, params.nC2, 1.0f);
    const float4 p1 = nl_read(in, x, y);
    const float4 p2 = nl_read(in, xpq, ypq);
    const float4 tmp = (p1 - p2) * (p1 - p2) * norm2;
    float dist = tmp.x + tmp.y + tmp.z;

    // dt :64-65 — exact zero for out-of-bounds neighbours.
    const bool inBounds =
        (x + qx) >= 0 && (x + qx) < width &&
        (y + qy) >= 0 && (y + qy) < height;
    dist = inBounds ? dist : 0.0f;

    U4[gidx] = dist;
}

// dt nlmeans.cl:70-123 — horizontal (2P+1) box sum via threadgroup
// sliding window: each workgroup covers `blockSize` columns of ONE row;
// the P-wide wings are co-operatively filled from global memory (clamped
// at the plane borders — dt reads through the clamp sampler; the wing
// loads here clamp xx to [0, width−1], dt :94-107 same shape via xx
// clamp). threadgroup memory holds (blockSize + 2P) floats.
kernel void nlmeans_horiz(
    device const float* U4_in [[buffer(0)]],
    device float* U4_out [[buffer(1)]],
    constant NLMeansBoxParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 lsz [[threads_per_threadgroup]],
    uint2 gpg [[threadgroup_position_in_grid]],
    threadgroup float* buffer [[threadgroup(0)]])
{
    const int width = (int)params.width;
    const int height = (int)params.height;
    const int P = params.P;
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    const int lsz0 = (int)lsz.x;
    const int lid0 = (int)lid.x;
    const int gidx =
        min(y, height - 1) * width + min(x, width - 1);

    if (y < height) {
        // center (dt :87)
        buffer[P + lid0] = U4_in[gidx];

        // left wing (dt :90-97)
        for (int n = 0; n <= P / lsz0; n++) {
            const int l = n * lsz0 + lid0 + 1;
            if (l > P) { continue; }
            int xx = (int)gpg.x * lsz0 - l;
            xx = max(xx, 0);
            buffer[P - l] = U4_in[y * width + xx];
        }
        // right wing (dt :100-107)
        for (int n = 0; n <= P / lsz0; n++) {
            const int r = n * lsz0 + lsz0 - lid0;
            if (r > P) { continue; }
            int xx = (int)gpg.x * lsz0 + lsz0 - 1 + r;
            xx = min(xx, width - 1);
            buffer[P + lsz0 - 1 + r] = U4_in[y * width + xx];
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (x >= width || y >= height) { return; }

    // dt :114-122 — the sliding box sum.
    float distacc = 0.0f;
    for (int pi = -P; pi <= P; pi++) {
        distacc += buffer[P + lid0 + pi];
    }
    U4_out[gidx] = distacc;
}

// dt nlmeans.cl:125-181 — vertical (2P+1) box sum (same sliding window
// along y) + IMMEDIATE weight application: g = gh(dist, sharpness)
// (dt :178 — the vert output is already the weight map).
kernel void nlmeans_vert(
    device const float* U4_in [[buffer(0)]],
    device float* U4_out [[buffer(1)]],
    constant NLMeansVertParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 lsz [[threads_per_threadgroup]],
    uint2 gpg [[threadgroup_position_in_grid]],
    threadgroup float* buffer [[threadgroup(0)]])
{
    const int width = (int)params.width;
    const int height = (int)params.height;
    const int P = params.P;
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    const int lsz1 = (int)lsz.y;
    const int lid1 = (int)lid.y;
    const int gidx =
        min(y, height - 1) * width + min(x, width - 1);

    if (x < width) {
        // center (dt :143)
        buffer[P + lid1] = U4_in[gidx];

        // left wing (dt :146-153)
        for (int n = 0; n <= P / lsz1; n++) {
            const int l = n * lsz1 + lid1 + 1;
            if (l > P) { continue; }
            int yy = (int)gpg.y * lsz1 - l;
            yy = max(yy, 0);
            buffer[P - l] = U4_in[yy * width + x];
        }
        // right wing (dt :156-163)
        for (int n = 0; n <= P / lsz1; n++) {
            const int r = n * lsz1 + lsz1 - lid1;
            if (r > P) { continue; }
            int yy = (int)gpg.y * lsz1 + lsz1 - 1 + r;
            yy = min(yy, height - 1);
            buffer[P + lsz1 - 1 + r] = U4_in[yy * width + x];
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (x >= width || y >= height) { return; }

    float distacc = 0.0f;
    for (int pj = -P; pj <= P; pj++) {
        distacc += buffer[P + lid1 + pj];
    }
    distacc = nlmeans_gh(distacc, params.sharpness);
    U4_out[gidx] = distacc;
}

// dt nlmeans.cl:183-230 — symmetric accumulation over the half-plane
// offset q: U2 += w(p,q)·I(p+q) + w(p,−q)·I(p−q) (weights from the CURRENT
// weight map read at p and the mirrored p−q; out-of-bounds neighbours
// contribute zero; U3 = U2.w counts the weights). Device-buffer RMW (L018:
// program order holds on device memory; dt :229 same statement).
kernel void nlmeans_accu(
    texture2d<float, access::read> in [[texture(0)]],
    device float4* U2 [[buffer(0)]],
    device const float* U4 [[buffer(1)]],
    constant NLMeansAccuParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int width = (int)params.width;
    const int height = (int)params.height;
    const int qx = params.qx;
    const int qy = params.qy;
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= width || y >= height) { return; }
    const int gidx = y * width + x;

    // dt :201-216 — in-bounds flags for ±q neighbours.
    int wpq = 1, wmq = 1;
    wpq *= ((x + qx) < width)  ? 1 : 0;
    wmq *= ((x - qx) < width)  ? 1 : 0;
    wpq *= ((x + qx) >= 0) ? 1 : 0;
    wmq *= ((x - qx) >= 0) ? 1 : 0;
    wpq *= ((y + qy) >= 0) ? 1 : 0;
    wmq *= ((y - qy) >= 0) ? 1 : 0;
    wpq *= ((y + qy) < height) ? 1 : 0;
    wmq *= ((y - qy) < height) ? 1 : 0;

    const float4 u1_pq = wpq ? nl_read(in, x + qx, y + qy) : float4(0.0f);
    const float4 u1_mq = wmq ? nl_read(in, x - qx, y - qy) : float4(0.0f);

    const float u4 = U4[gidx];
    const float u4_mq = U4[clamp(y - qy, 0, height - 1) * width
                           + clamp(x - qx, 0, width - 1)];
    const float u4_mq_dd = u4_mq * nlmeans_ddirac(qx, qy);

    float4 accu = (u4 * u1_pq) + (u4_mq_dd * u1_mq);
    accu.w = (float)(wpq * u4 + wmq * u4_mq_dd);

    U2[gidx] += accu;
}

// dt nlmeans.cl:233-253 — normalize + blend + domain exit:
// out = in·(1−weight) + (U2/U3)·weight in Lab, then Lab → linear Rec2020
// (dt's pipeline converts after the module; same per-pixel math).
// weight = (luma, chroma, chroma, 1) (nlmeans.c:213,223).
kernel void nlmeans_finish(
    texture2d<float, access::read> in [[texture(0)]],
    device const float4* U2 [[buffer(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant NLMeansFinishParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int width = (int)params.width;
    const int height = (int)params.height;
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= width || y >= height) { return; }

    const float4 i  = nl_read(in, x, y);
    const float4 u2 = U2[y * width + x];
    const float  u3 = u2.w;

    float4 o = i * (1.0f - params.weight) + (u2 / u3) * params.weight;
    o.w = i.a;

    out.write(float4(la_lab_to_rec2020(o.rgb), o.w), gid);
}
