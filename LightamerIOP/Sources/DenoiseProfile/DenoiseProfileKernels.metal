#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// DenoiseProfile kernel group (Plan 05-07, IOP-DENOISE-01) — verbatim port
// of darktable `data/kernels/denoiseprofile.cl` (tree dc58cf0ba1), the
// second-hardest iop transplant of the project. dt `denoiseprofile` runs
// POST-DEMOSAIC in linear RGB (default_colorspace IOP_CS_RGB,
// denoiseprofile.c:837-843 — RESEARCH §1.2 erratum: NOT a raw-domain op).
//
// STRUCTURE (dt ships these as program 11, denoiseprofile.cl):
//   - VST trio: precondition / precondition_v2 / precondition_Y0U0V0
//     (generalized Anscombe, :31-114) — variance-stabilizing transform
//   - inverse trio: backtransform / backtransform_v2 /
//     backtransform_Y0U0V0 (:327-433) — v2 = the low-bias inverse
//     (2nd-order Taylor with the user `bias` inside delta,
//     denoiseprofile.c:1025-1084)
//   - eaw wavelets: decompose (5×5 B3 a-trous + edge-aware weight,
//     :449-482) + synthesize (soft threshold, :485-501) + the two-pass
//     sum-of-squares reduce (:504-577) feeding Bayesshrink
//     (variance_stabilizing_xform, denoiseprofile.c:1345-1421)
//   - NLMeans leg: vert (:197-252 — the denoiseprofile VARIANT with the
//     single-pixel distance boost + central_pixel_weight + `norm − 2`
//     offset) + finish/finish_v2 (normalize + fused backtransform,
//     :302-350). dist/horiz/accu are the nlmeans kernels REUSED VERBATIM
//     (norm2 = (1,1,1): nlmeans_dist with nL2=nC2=1; nlmeans_horiz;
//     nlmeans_accu — zero-copy consumption of the 05-06 group, matching
//     dt's own program sharing of the Goossens structure).
//
// L018 DISCIPLINE: every intermediate is either a read→write texture PAIR
// (decompose/synthesize/backtransform never read what they write) or a
// device float4 buffer with program-order RMW (the band accumulator, dt
// CPU `out += softthresh` shape). NO read_write texture anywhere — the
// band accumulation path is the header red line for this plan.
//
// fast_mexp2f is the BIT-EXACT port (dt common.h:181-191 float-value
// space construction — see NLMeansKernels.metal for the derivation notes).
//
// Domain note (RESEARCH §1.2 divergence, D-05-07-T2-1): Lightamer's pipe
// data at slot 9.0 is CIRAW-displayed linear Rec2020; dt works on WB-
// multiplied camera RGB. The wb factors arrive as uniforms (v1 neutral
// 1,1,1 — compute_wb_factors' coeffs==0 branch), keeping every formula
// exact relative to the inputs it receives.
// ─────────────────────────────────────────────────────────────────────────

// dt common.h:181-191 (bit-exact — nlmeans group carries the notes).
inline float dn_fast_mexp2f(const float x) {
    const float i1 = 1065353216.0f; // (float)0x3f800000u
    const float i2 = 1056964608.0f; // (float)0x3f000000u
    const float k0 = i1 + x * (i2 - i1);
    return (k0 >= 8388608.0f) ? as_type<float>((uint)k0) : 0.0f;
}

// Clamp-to-edge plane read (dt reads through the clamp sampler —
// common.h:23 CLK_ADDRESS_CLAMP_TO_EDGE).
inline float4 dn_read(texture2d<float, access::read> plane, int x, int y) {
    const int cx = clamp(x, 0, (int)plane.get_width() - 1);
    const int cy = clamp(y, 0, (int)plane.get_height() - 1);
    return plane.read(uint2(cx, cy));
}

// Kernel uniform structs (scalar kernel arguments cannot carry [[buffer]]
// attributes in MSL — one constant struct per kernel; Swift mirrors the
// layouts field-for-field; float4 members align to 16 with explicit pads).
struct DNPreconditionParams {
    uint width;
    uint height;
    float2 align_pad;
    float4 a;
    float4 sigma2;
};
struct DNPreconditionV2Params {
    uint width;
    uint height;
    float2 align_pad;
    float4 a;
    float4 p;
    float4 b;
    float4 wb;
};
struct DNBacktransformParams {
    uint width;
    uint height;
    float2 align_pad;
    float4 a;
    float4 sigma2;
};
struct DNBacktransformV2Params {
    uint width;
    uint height;
    float2 align_pad;
    float4 a;
    float4 p;
    float4 b;
    float bias;
    // three explicit scalars (NOT float3 — MSL float3 aligns to 16 and
    // would push wb to offset 96 vs the Swift mirror's 80).
    float align_pad2a;
    float align_pad2b;
    float align_pad2c;
    float4 wb;
};
struct DNDecomposeParams {
    uint width;
    uint height;
    uint scale;
    float inv_sigma2;
};
struct DNSynthesizeParams {
    uint width;
    uint height;
    float2 align_pad;
    float4 threshold;
    float4 boost;
};
struct DNReduceFirstParams {
    uint width;
    uint height;
};
struct DNVertParams {
    uint width;
    uint height;
    int P;
    float norm;
    float central_pixel_weight;
    float2 align_pad;
};
struct DNFinishParams {
    uint width;
    uint height;
    float2 align_pad;
    float4 a;
    float4 sigma2;
};
struct DNFinishV2Params {
    uint width;
    uint height;
    float2 align_pad;
    float4 a;
    float4 p;
    float4 b;
    float bias;
    // three explicit scalars (NOT float3 — MSL float3 aligns to 16 and
    // would push wb to offset 96 vs the Swift mirror's 80).
    float align_pad2a;
    float align_pad2b;
    float align_pad2c;
    float4 wb;
};

// ─────────────────────────────────────────────────────────────────────────
// VST trio (precondition) — dt denoiseprofile.cl:31-114.
// ─────────────────────────────────────────────────────────────────────────

// :31-54 — generalized Anscombe: t = 2·sqrt(max(in/a + (b/a)² + 3/8, 0)).
kernel void dn_precondition(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DNPreconditionParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    const float4 pixel = dn_read(in, x, y);
    const float alpha = pixel.w;
    const float4 t = fmax(pixel / params.a, 0.0f);
    const float4 d = fmax(float4(0.0f), t + 0.375f + params.sigma2);
    float4 s = 2.0f * sqrt(d);
    s.w = alpha;
    out.write(s, gid);
}

// :56-79 — general power VST: t = 2·(max(in/wb + b, 0))^(1−p/2) /
// ((2−p)·sqrt(a)). `a` arrives pre-multiplied by compensate_p (commit).
kernel void dn_precondition_v2(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DNPreconditionV2Params& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    const float4 pixel = dn_read(in, x, y);
    const float alpha = pixel.w;
    float4 t = fmax(
        2.0f * pow(fmax(float4(0.0f), pixel / params.wb + params.b),
                   1.0f - params.p / 2.0f)
        / ((-params.p + 2.0f) * sqrt(params.a)),
        0.0f);
    t.w = alpha;
    out.write(t, gid);
}

// :81-114 — the Y0U0V0 variant: VST WITHOUT the wb division (the wb lives
// in the matrix row normalization, set_up_conversion_matrices
// denoiseprofile.c:1288-1343), then the Y0U0V0 row-vector application.
// `mat` = the 9-float strength-divided toY0U0V0 (row-major).
kernel void dn_precondition_Y0U0V0(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DNPreconditionV2Params& params [[buffer(0)]],
    device const float* mat [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    const float4 pixel = dn_read(in, x, y);
    const float alpha = pixel.w;
    const float4 t = fmax(
        2.0f * pow(fmax(float4(0.0f), pixel + params.b), 1.0f - params.p / 2.0f)
        / ((-params.p + 2.0f) * sqrt(params.a)),
        0.0f);
    float4 outpx = float4(0.0f);
    outpx.x += mat[0] * t.x;
    outpx.x += mat[1] * t.y;
    outpx.x += mat[2] * t.z;
    outpx.y += mat[3] * t.x;
    outpx.y += mat[4] * t.y;
    outpx.y += mat[5] * t.z;
    outpx.z += mat[6] * t.x;
    outpx.z += mat[7] * t.y;
    outpx.z += mat[8] * t.z;
    outpx.w = alpha;
    out.write(outpx, gid);
}

// ─────────────────────────────────────────────────────────────────────────
// Inverse trio (backtransform) — dt denoiseprofile.cl:327-433.
// ─────────────────────────────────────────────────────────────────────────

// :354-374 — closed-form unbiased inverse of the generalized Anscombe.
kernel void dn_backtransform(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DNBacktransformParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    float4 px = dn_read(in, x, y);
    const float alpha = px.w;
    // CL vector ternary → MSL select(falseVal, trueVal, cond).
    px = select(
        0.25f * px * px + 0.25f * sqrt(1.5f) / px
            - 1.375f / (px * px) + 0.625f * sqrt(1.5f) / (px * px * px)
            - 0.125f - params.sigma2,
        float4(0.0f),
        px < float4(0.5f));
    px *= params.a;
    px.w = alpha;
    out.write(px, gid);
}

// :377-399 — the v2 low-bias inverse: z1 = (x + sqrt(x² + bias))·sqrt(a)·
// (2−p)/4; out = max(z1^(1/(1−p/2)) − b, 0)·wb.
kernel void dn_backtransform_v2(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DNBacktransformV2Params& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    float4 px = dn_read(in, x, y);
    const float alpha = px.w;
    px = fmax(float4(0.0f), px);
    const float4 delta = px * px + float4(params.bias);
    const float4 denominator = 4.0f / (sqrt(params.a) * (2.0f - params.p));
    const float4 z1 = (px + sqrt(fmax(float4(0.0f), delta))) / denominator;
    px = fmax(pow(z1, 1.0f / (1.0f - params.p / 2.0f)) - params.b, 0.0f);
    px = px * params.wb;
    px.w = alpha;
    out.write(px, gid);
}

// :401-433 — Y0U0V0 inverse: toRGB matrix first, then the v2 inverse with
// bias·wb inside delta.
kernel void dn_backtransform_Y0U0V0(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DNBacktransformV2Params& params [[buffer(0)]],
    device const float* toRGB [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    const float4 t = dn_read(in, x, y);
    const float alpha = t.w;
    float4 px = float4(0.0f);
    px.x += toRGB[0] * t.x;
    px.x += toRGB[1] * t.y;
    px.x += toRGB[2] * t.z;
    px.y += toRGB[3] * t.x;
    px.y += toRGB[4] * t.y;
    px.y += toRGB[5] * t.z;
    px.z += toRGB[6] * t.x;
    px.z += toRGB[7] * t.y;
    px.z += toRGB[8] * t.z;
    px = fmax(float4(0.0f), px);
    const float4 delta = px * px + float4(params.bias) * params.wb;
    const float4 denominator = 4.0f / (sqrt(params.a) * (2.0f - params.p));
    const float4 z1 = (px + sqrt(fmax(float4(0.0f), delta))) / denominator;
    px = fmax(pow(z1, 1.0f / (1.0f - params.p / 2.0f)) - params.b, 0.0f);
    px.w = alpha;
    out.write(px, gid);
}

// ─────────────────────────────────────────────────────────────────────────
// eaw wavelets (decompose / synthesize / reduce) — dt :436-577.
// ─────────────────────────────────────────────────────────────────────────

// :436-446 — edge-aware weight: exp2(−max(0, |c1−c2|²·inv_sigma2·0.02−9)).
inline float4 dn_weight(const float4 c1, const float4 c2, const float inv_sigma2) {
    const float4 sqr = (c1 - c2) * (c1 - c2);
    const float dt = (sqr.x + sqr.y + sqr.z) * inv_sigma2;
    const float var = 0.02f;
    const float off2 = 9.0f;
    return float4(dn_fast_mexp2f(fmax(0.0f, dt * var - off2)));
}

// :449-482 — 5×5 B3 a-trous (stride 2^scale) with the edge-aware weights;
// writes coarse AND detail = pixel − coarse (Bayesshrink consumes the
// UN-thresholded detail, eaw.c:264).
kernel void dn_decompose(
    texture2d<float, access::read>  in     [[texture(0)]],
    texture2d<float, access::write> coarse [[texture(1)]],
    texture2d<float, access::write> detail [[texture(2)]],
    constant DNDecomposeParams& params [[buffer(0)]],
    device const float* filter [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    const int mult = 1 << params.scale;
    const float4 pixel = dn_read(in, x, y);
    float4 sum = 0.0f;
    float4 wgt = 0.0f;
    for (int j = 0; j < 5; j++) {
        for (int i = 0; i < 5; i++) {
            const int xx = mult * (i - 2) + x;
            const int yy = mult * (j - 2) + y;
            const int k = j * 5 + i;
            const float4 px = dn_read(in, xx, yy);
            const float4 w = filter[k] * dn_weight(pixel, px, params.inv_sigma2);
            sum += w * px;
            wgt += w;
        }
    }
    sum /= wgt;
    sum.w = pixel.w;
    detail.write(pixel - sum, gid);
    coarse.write(sum, gid);
}

// :485-501 reshaped for the CPU-form band accumulation (process_wavelets
// :1556-1577 — out is ZEROED once, then `out += boost·softthresh(detail)`
// per band; the L018-legal RMW lives on a device float4 BUFFER):
// accu[gidx] += boost·copysign(max(0,|d|−thrs), d).
kernel void dn_synthesize_accum(
    texture2d<float, access::read> detail [[texture(0)]],
    device float4* accu [[buffer(0)]],
    constant DNSynthesizeParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    const float4 d = detail.read(gid);
    const float4 amount = copysign(fmax(float4(0.0f), abs(d) - params.threshold), d);
    accu[y * params.width + x] += params.boost * amount;
}

// :504-541 — threadgroup partial sum of squares (float4 per pixel), one
// 16×16 group per block (dt flocopt {sizex:16, sizey:16}).
kernel void dn_reduce_first(
    texture2d<float, access::read> in [[texture(0)]],
    device float4* accu [[buffer(0)]],
    constant DNReduceFirstParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 lsz [[threads_per_threadgroup]],
    uint2 gpg [[threadgroup_position_in_grid]],
    threadgroup float4* buffer [[threadgroup(0)]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    const int l = (int)(lid.y * lsz.x + lid.x);
    const bool inImage = x < (int)params.width && y < (int)params.height;
    float4 pixel = 0.0f;
    if (inImage) { pixel = in.read(gid); }
    buffer[l] = inImage ? pixel * pixel : float4(0.0f);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const int lsz1 = (int)(lsz.x * lsz.y);
    for (int offset = lsz1 / 2; offset > 0; offset /= 2) {
        if (l < offset) { buffer[l] += buffer[l + offset]; }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (l == 0) {
        const int m = (int)(gpg.y * ((params.width + 15) / 16) + gpg.x);
        accu[m] = buffer[0];
    }
}

// :544-577 — single-workgroup grid-stride fold of the partials into
// result[0] (float4). Dispatch with ONE 256-thread group; `count` = the
// NUMBER OF PARTIALS (dt CLARG(bufsize) = group count), NOT the pixel
// count — iterating the pixel count would read past the partials buffer.
struct DNReduceSecondParams {
    uint count;
};
kernel void dn_reduce_second(
    device const float4* input [[buffer(0)]],
    device float4* result [[buffer(1)]],
    constant DNReduceSecondParams& params [[buffer(2)]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 lsz [[threads_per_threadgroup]],
    threadgroup float4* buffer [[threadgroup(0)]])
{
    const int n = (int)params.count;
    const int stride = (int)(lsz.x * lsz.y);
    const int tid = (int)(lid.y * lsz.x + lid.x);
    float4 sum = float4(0.0f);
    for (int idx = tid; idx < n; idx += stride) {
        sum += input[idx];
    }
    buffer[tid] = sum;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (int offset = stride / 2; offset > 0; offset /= 2) {
        if (tid < offset) {
            buffer[tid] += buffer[tid + offset];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        result[0] = buffer[0];
    }
}

// Final residue fold (CPU form :1579-1582): out = accu + buf1 (coarsest),
// written to a texture so the backtransform trio can consume it unchanged.
kernel void dn_add_residue(
    device const float4* accu [[buffer(0)]],
    texture2d<float, access::read> coarse [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DNReduceFirstParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    const float4 c = dn_read(coarse, x, y);
    const float4 a = accu[y * params.width + x];
    out.write(a + c, gid);
}

// ─────────────────────────────────────────────────────────────────────────
// NLMeans leg (the denoiseprofile vert VARIANT + fused finish) — dt
// :197-350. dist/horiz/accu are the nlmeans kernels reused verbatim.
// ─────────────────────────────────────────────────────────────────────────

// :197-252 — vertical (2P+1) box sum (threadgroup sliding window) with the
// denoiseprofile additions: `+= U4_single·(2P+1)²·central_pixel_weight`
// (the RAW dist map of the CURRENT offset — dt passes dev_U4), `/= (1+
// central_pixel_weight)`, then the weight `fast_mexp2f(max(0, d·norm−2))`
// (norm = 0.045/(2P+1)², nlmeans_norm :1614-1629).
kernel void dn_vert(
    device const float* U4_in [[buffer(0)]],
    device const float* U4_single [[buffer(1)]],
    device float* U4_out [[buffer(2)]],
    constant DNVertParams& params [[buffer(3)]],
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
    const int gidx = min(y, height - 1) * width + min(x, width - 1);

    if (x < width) {
        buffer[P + lid1] = U4_in[gidx];
        for (int n = 0; n <= P / lsz1; n++) {
            const int l = n * lsz1 + lid1 + 1;
            if (l > P) { continue; }
            int yy = (int)gpg.y * lsz1 - l;
            yy = max(yy, 0);
            buffer[P - l] = U4_in[yy * width + x];
        }
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
    distacc += U4_single[gidx] * (2 * P + 1) * (2 * P + 1)
               * params.central_pixel_weight;
    distacc /= (1.0f + params.central_pixel_weight);
    distacc = dn_fast_mexp2f(fmax(0.0f, distacc * params.norm - 2.0f));
    U4_out[gidx] = distacc;
}

// :302-324 — legacy finish: normalize U2 then the Anscombe inverse.
kernel void dn_finish(
    texture2d<float, access::read> in [[texture(0)]],
    device const float4* U2 [[buffer(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DNFinishParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    const float4 u2 = U2[y * params.width + x];
    const float alpha = dn_read(in, x, y).w;
    float4 px = (u2.w > 0.0f ? u2 / u2.w : float4(0.0f));
    px = select(
        0.25f * px * px + 0.25f * sqrt(1.5f) / px - 1.375f / (px * px)
            + 0.625f * sqrt(1.5f) / (px * px * px) - 0.125f - params.sigma2,
        float4(0.0f),
        px < float4(0.5f));
    px *= params.a;
    px.w = alpha;
    out.write(px, gid);
}

// :327-350 — v2 finish: normalize U2 then the low-bias inverse (bias =
// d.bias − 0.5·log(scale), commit-computed).
kernel void dn_finish_v2(
    texture2d<float, access::read> in [[texture(0)]],
    device const float4* U2 [[buffer(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant DNFinishV2Params& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    const int x = (int)gid.x;
    const int y = (int)gid.y;
    if (x >= (int)params.width || y >= (int)params.height) { return; }
    const float4 u2 = U2[y * params.width + x];
    const float alpha = dn_read(in, x, y).w;
    float4 px = (u2.w > 0.0f ? u2 / u2.w : float4(0.0f));
    const float4 delta = px * px + float4(params.bias);
    const float4 denominator = 4.0f / (sqrt(params.a) * (2.0f - params.p));
    const float4 z1 = (px + sqrt(fmax(float4(0.0f), delta))) / denominator;
    px = fmax(pow(z1, 1.0f / (1.0f - params.p / 2.0f)) - params.b, 0.0f);
    px = px * params.wb;
    px.w = alpha;
    out.write(px, gid);
}
