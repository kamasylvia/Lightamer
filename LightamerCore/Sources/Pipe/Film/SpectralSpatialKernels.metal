/*
    This file is part of Lightamer,
    Copyright (C) 2026 the Lightamer authors.

    Lightamer is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Lightamer is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Lightamer.  If not, see <http://www.gnu.org/licenses/>.

    The grain math below is transcribed from darktable's grain.h and
    spektrafilm.cl (Copyright (C) 2026 darktable developers, GPL-3.0) —
    see the per-section source notes.
*/

/* SpectralSpatialKernels.metal (Plan M8-3+ T4/T5) — the spectral film
   core's SPATIAL kernel family (the M8-1b fused chain is all per-pixel;
   these kernels do the neighborhood work the upstream call side owns):

     T4: the grain five (the upstream spektrafilm.cl grain group's port —
         dt spektrafilm `4d1fb6a95b:data/kernels/spektrafilm.cl:510-660`,
         GPL-3.0, (C) darktable developers):
       • spectral_film_grain_gen_raw_sl  (per-sub-layer Poisson draw)
       • spectral_film_grain_accumulate  (sub-layer sum, reset-or-add)
       • spectral_film_grain_finalize    (floor/density subtract + scale)
       • spectral_film_grain_add         (delta onto the CMY density)
       • spectral_film_grain_usm         (multiplicative acutance recovery;
         pow() rides the SHARED polynomial — OQ-M83-5, NOT the platform
         pow the upstream NOTE flags at 16 ULP)
     T4: the dye-cloud + clump separable pair (the blur the grain group
         rides — exact-kernel separable Gaussian, host-built weights):
       • spectral_film_spatial_blur_row / _col
     T5: the wide-blur抽稀 pair + halation/diffusion (appended by T5).

   BIT-EXACT DISCIPLINE (the grain.h inheritance — the accept/reject loop
   turns one-ULP disagreement into whole-integer grain-count differences):
   every multiply-add is an explicit fma(), plain sqrt() never
   native_sqrt, exp(-lam) rides the grain_exp_neg polynomial (NEVER the
   platform exp), and the log10/pow10 pair rides the SHARED sf_log10f/
   sf_pow10f (the SpectralFilmKernels.metal twins, spelled identically —
   Metal compiles each .metal file separately, so the twins live here
   verbatim, not by include). */

#include <metal_stdlib>
using namespace metal;

/* ---- the grain.h math twin (dt `4d1fb6a95b:data/kernels/grain.h`,
   GPL-3.0, (C) darktable developers — transcribed, Metal dialect) ---- */

#define SFG_POISSON_EXACT_MAX 12.0f

static inline uint sfg_hash(uint x)
{
  x ^= x >> 16;
  x *= 0x7feb352dU;
  x ^= x >> 15;
  x *= 0x846ca68bU;
  x ^= x >> 16;
  return x;
}

static inline float sfg_uniform(uint s)
{
  return (float)(sfg_hash(s) & 0xffffffU) / (float)0x1000000U;
}

static inline float sfg_normal(uint s)
{
  const float u = sfg_uniform(s) + sfg_uniform(s * 2654435761U + 1U)
      + sfg_uniform(s * 2246822519U + 2U) + sfg_uniform(s * 3266489917U + 3U);
  return (u - 2.0f) * 1.7320508f; /* sqrt(3) */
}

/* Teschner spatial hash — ABSOLUTE image coordinates (pan/zoom stable). */
static inline uint sfg_pixel_seed(uint xi, uint yi, uint chan)
{
  return xi * 73856093U ^ yi * 19349663U ^ chan * 83492791U;
}

static inline float sfg_exp2i(int k)
{
  return as_type<float>((uint)(k + 127) << 23);
}

static inline float sfg_exp_neg(float lam)
{
  const float t = -lam;
  const int k = (int)floor(fma(t, 1.4426950216293335f, 0.5f)); /* log2(e) */
  const float r = fma(-(float)k, 0.6931471824645996f, t);      /* ln(2) */
  float p = 0.00138888892f;                                    /* 1/720 */
  p = fma(p, r, 0.00833333377f);                               /* 1/120 */
  p = fma(p, r, 0.0416666679f);                                /* 1/24 */
  p = fma(p, r, 0.166666672f);                                 /* 1/6 */
  p = fma(p, r, 0.5f);
  p = fma(p, r, 1.0f);
  p = fma(p, r, 1.0f);
  return p * sfg_exp2i(k);
}

static inline float sfg_poisson(float lam, uint seed)
{
  if (lam <= 0.0f) { return 0.0f; }
  if (lam < SFG_POISSON_EXACT_MAX)
  {
    const float limit = sfg_exp_neg(lam);
    float prod = 1.0f;
    int k = 0;
    do
    {
      prod *= sfg_uniform(seed + (uint)k * 0x9e3779b9U);
      k++;
    } while (prod > limit && k < 64);
    return (float)(k - 1);
  }
  /* Plain sqrt(), never native_sqrt (the grain.h verbatim discipline). */
  return fma(sqrt(lam), sfg_normal(seed), lam);
}

static inline float sfg_clampf(float x, float lo, float hi)
{
  return fmin(fmax(x, lo), hi);
}

static inline float sfg_layer_particle(float density, float dmax, float npart,
                                       float unif, uint seed)
{
  const float p = sfg_clampf(density / dmax, 1e-6f, 1.0f - 1e-6f);
  const float od = dmax / fmax(npart, 1e-9f);
  const float sat = fma(-(p * unif), 1.0f - 1e-6f, 1.0f);
  return sfg_poisson(npart * p / sat, seed * 0x9e3779b9U + 1U) * od * sat;
}

/* ---- the shared log10/pow10 twin (the SpectralFilmKernels.metal
   sf_log10f/sf_pow10f spelling, verbatim — the OQ-M83-5 face) ---- */

static inline float sfg_exp2f(float x)
{
  const int k = (int)floor(x + 0.5f);
  const float t = (x - (float)k) * 0.6931471824645996f;
  float p = 0.000198412700f;
  p = fma(p, t, 0.00138888892f);
  p = fma(p, t, 0.00833333377f);
  p = fma(p, t, 0.0416666679f);
  p = fma(p, t, 0.166666672f);
  p = fma(p, t, 0.5f);
  p = fma(p, t, 1.0f);
  p = fma(p, t, 1.0f);
  return p * sfg_exp2i(k);
}

static inline float sfg_log2f(float x)
{
  const uint xu = as_type<uint>(x);
  int e = (int)((xu >> 23) & 0xffU) - 127;
  float m = as_type<float>((xu & 0x007fffffU) | 0x3f800000U);
  if (m > 1.41421356f) { m *= 0.5f; e += 1; }
  const float s = (m - 1.0f) / (m + 1.0f);
  const float s2 = s * s;
  float p = 0.222222224f;
  p = fma(p, s2, 0.285714298f);
  p = fma(p, s2, 0.400000006f);
  p = fma(p, s2, 0.666666687f);
  p = fma(p, s2, 2.0f);
  return fma(p * s, 1.4426950216293335f, (float)e);
}

static inline float sfg_log10f(float x)
{
  return sfg_log2f(x) * 0.3010299956639812f;
}

static inline float sfg_pow10f(float x)
{
  return sfg_exp2f(x * 3.321928094887362f);
}

/* ratio^amount through the shared pair (the USM pow face — OQ-M83-5:
   exp2(amount * log2(ratio)); ratio is pre-clamped to [1/4, 4], amount
   is the small USM strength — both inside the polynomials' domain). */
static inline float sfg_pow_poly(float ratio, float amount)
{
  return sfg_exp2f(amount * sfg_log2f(ratio));
}

/* ---- the grain five ---- */

/* Per-sub-layer Poisson draw (the gen_raw_sl port — single-sublayer
   face: sl_idx/nle/max_sub collapse; the curve ride is the 256-point
   normalized develop curve + dmin; the inverse lookup is the host's
   Float64-twin-compatible bisection over the monotonic curve).

   ABI: dens = the developed CMY density plane (float4, w = carried);
   raw_out = the flat w*h raw draw buffer; params = [w, h, channel_idx,
   unif_ch, npart_scale, dmax, npart, dmin] (float-encoded, int-cast at
   the use site); curve = the 256-point normalized curve; roi = the
   absolute-origin offset (uint2 — pan/zoom-stable seeding). */
kernel void spectral_film_grain_gen_raw_sl(
    texture2d<float, access::read> dens [[texture(0)]],
    device float *raw_out [[buffer(0)]],
    constant const float *params [[buffer(1)]],
    device const float *curve [[buffer(2)]],
    constant const uint *roi [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int channel_idx = (int)params[2];
  const float unif_ch = params[3];
  const float npart_scale = params[4];
  const float dmax = params[5], npart = params[6], dmin = params[7];
  const float4 d4 = dens.read(gid);
  const float density = channel_idx == 0 ? d4.x : (channel_idx == 1 ? d4.y : d4.z);
  /* The inverse lookup: bisection over the monotonic 256-point curve
     (the sf_cl_grain_curve_inverse twin, stride-1 face). */
  int lo = 0, hi = 255;
  for (int it = 0; it < 8; it++)
  {
    const int mid = (lo + hi) / 2;
    if (curve[mid] <= density) { lo = mid; }
    else { hi = mid; }
  }
  const float v0 = curve[lo], v1 = curve[hi];
  const float denom = v1 - v0;
  float frac = (fabs(denom) > 1e-9f) ? (density - v0) / denom : 0.0f;
  frac = clamp(frac, 0.0f, 1.0f);
  const float pos = (float)lo + frac;
  /* The forward sample at the continuous index (stride-1 twin). */
  int i0 = (int)pos;
  i0 = clamp(i0, 0, 254);
  const float fr = pos - (float)i0;
  const float raw = fma(curve[i0 + 1], fr, curve[i0] * (1.0f - fr));
  const float d_abs = raw + dmin;
  const uint seed = sfg_pixel_seed(
      (uint)((int)gid.x + (int)roi[0]), (uint)((int)gid.y + (int)roi[1]),
      (uint)channel_idx);
  raw_out[(size_t)gid.y * (size_t)w + (size_t)gid.x] =
      sfg_layer_particle(d_abs, dmax, npart * npart_scale, unif_ch, seed);
}

/* Sub-layer accumulate (reset=1 initializes, else adds — the host runs
   the dye-cloud blur on each raw buffer between sampling and combining;
   single-sublayer = one reset call). */
kernel void spectral_film_grain_accumulate(
    device float *acc [[buffer(0)]],
    device const float *src [[buffer(1)]],
    constant const float *params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const size_t k = (size_t)gid.y * (size_t)w + (size_t)gid.x;
  if ((int)params[2] != 0) { acc[k] = src[k]; }
  else { acc[k] += src[k]; }
}

/* Channel finalize: subtract the floor + the clean density, scale by
   the grain amount, write the out_ch component (mono broadcasts —
   out_ch = 3 selects the broadcast face). */
kernel void spectral_film_grain_finalize(
    device float4 *grain_buf [[buffer(0)]],
    device const float *acc [[buffer(1)]],
    texture2d<float, access::read> dens [[texture(0)]],
    constant const float *params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int channel_idx = (int)params[2], out_ch = (int)params[3];
  const float dmin_ch = params[4], amount = params[5];
  const size_t k = (size_t)gid.y * (size_t)w + (size_t)gid.x;
  const float4 d4 = dens.read(gid);
  const float density = channel_idx == 0 ? d4.x : (channel_idx == 1 ? d4.y : d4.z);
  const float g = acc[k] - dmin_ch;
  const float delta = (g - density) * amount;
  float4 gv = (out_ch == 3 || out_ch == 0) ? float4(0.0f) : grain_buf[k];
  if (out_ch == 3) { gv = float4(delta, delta, delta, 0.0f); }
  else if (out_ch == 0) { gv.x = delta; }
  else if (out_ch == 1) { gv.y = delta; }
  else { gv.z = delta; }
  grain_buf[k] = gv;
}

/* Add the unblurred delta onto the CMY density (the clump blur runs
   AFTER, on the combined field — the upstream verbatim order). */
kernel void spectral_film_grain_add(
    texture2d<float, access::read_write> dens [[texture(0)]],
    device const float4 *grain_buf [[buffer(0)]],
    constant const float *params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const float4 d = dens.read(gid);
  const float4 g = grain_buf[(size_t)gid.y * (size_t)w + (size_t)gid.x];
  dens.write(float4(d.x + g.x, d.y + g.y, d.z + g.z, d.w), gid);
}

/* Multiplicative USM: cmy = D * (D/blur(D))^amount − dmin, the ratio
   clamped to [1/4, 4], the power through the SHARED polynomial
   (OQ-M83-5 — the upstream 16-ULP NOTE does not carry over). Runs on
   the ABSOLUTE density (the floor back in before the ratio, out after).
   ABI: cmy = the blurred plane (read_write, blurred in place by the
   caller); orig = the saved pre-blur plane; params = [w, h, amount,
   dmin0, dmin1, dmin2]. */
kernel void spectral_film_grain_usm(
    texture2d<float, access::read_write> cmy [[texture(0)]],
    texture2d<float, access::read> orig [[texture(1)]],
    constant const float *params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const float amount = params[2];
  const float4 dmin = float4(params[3], params[4], params[5], 0.0f);
  const float4 D = fmax(orig.read(gid) + dmin, 0.0f);
  const float4 blur = cmy.read(gid) + dmin;
  const float eps = 1e-6f;
  const float ratmax = 4.0f, ratmin = 1.0f / ratmax;
  float4 out;
  out.x = fmax(
      fma(D.x, sfg_pow_poly(fmax(fmin(D.x / fmax(blur.x, eps), ratmax), ratmin),
                            amount),
          -dmin.x),
      0.0f);
  out.y = fmax(
      fma(D.y, sfg_pow_poly(fmax(fmin(D.y / fmax(blur.y, eps), ratmax), ratmin),
                            amount),
          -dmin.y),
      0.0f);
  out.z = fmax(
      fma(D.z, sfg_pow_poly(fmax(fmin(D.z / fmax(blur.z, eps), ratmax), ratmin),
                            amount),
          -dmin.z),
      0.0f);
  out.w = 0.0f;
  cmy.write(out, gid);
}

/* ---- the separable blur pair (exact-kernel Gaussian, host weights) ---- */

/* One row pass: out[y][x] = Σ_t weights[t] * in[y][x + t − radius]
   (clamped bounds — the dye-cloud/clump discipline: no variance
   restoration, matching upstream). ABI: params = [w, h, radius]. */
kernel void spectral_film_spatial_blur_row(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float *weights [[buffer(0)]],
    constant const float *params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int radius = (int)params[2];
  float4 acc = float4(0.0f);
  for (int t = -radius; t <= radius; t++)
  {
    const int xx = clamp((int)gid.x + t, 0, w - 1);
    acc += in.read(uint2((uint)xx, gid.y)) * weights[t + radius];
  }
  out.write(acc, gid);
}

kernel void spectral_film_spatial_blur_col(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    device const float *weights [[buffer(0)]],
    constant const float *params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int radius = (int)params[2];
  float4 acc = float4(0.0f);
  for (int t = -radius; t <= radius; t++)
  {
    const int yy = clamp((int)gid.y + t, 0, h - 1);
    acc += in.read(uint2(gid.x, (uint)yy)) * weights[t + radius];
  }
  out.write(acc, gid);
}

/* ---- T5: the wide-blur抽稀 trio (dt `4d1fb6a95b:data/kernels/
   spektrafilm.cl:1013-1068`, GPL-3.0, (C) darktable developers —
   transcribed, Metal dialect; buffer-backed (float4 planes), matching
   the upstream __global float4 * faces operation for operation) ---- */

/* Per-block-row sums (one item per (block column, image row)).
   ABI: params = [w, h, k, lw, ox]. */
kernel void spectral_film_wide_rows(
    device const float4 *in [[buffer(0)]],
    device float4 *rows [[buffer(1)]],
    constant const float *params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  const int k = (int)params[2], lw = (int)params[3];
  const int ox = (int)params[4];
  const int X = (int)gid.x, y = (int)gid.y;
  if (X >= lw || y >= h) { return; }
  const int x0 = max(X * k - ox, 0), x1 = min((X + 1) * k - ox, w);
  float4 rs = float4(0.0f);
  for (int x = x0; x < x1; x++) { rs += in[(size_t)y * (size_t)w + (size_t)x]; }
  rows[(size_t)y * (size_t)lw + (size_t)X] = rs;
}

/* Fold the row sums into block means (one item per block).
   ABI: params = [w, h, k, lw, lh, ox, oy]; inv = the host table. */
kernel void spectral_film_wide_down(
    device const float4 *rows [[buffer(0)]],
    device float4 *low [[buffer(1)]],
    constant const float *params [[buffer(2)]],
    device const float *inv [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  const int k = (int)params[2], lw = (int)params[3], lh = (int)params[4];
  const int ox = (int)params[5], oy = (int)params[6];
  const int X = (int)gid.x, Y = (int)gid.y;
  if (X >= lw || Y >= lh) { return; }
  const int x0 = max(X * k - ox, 0), x1 = min((X + 1) * k - ox, w);
  const int y0 = max(Y * k - oy, 0), y1 = min((Y + 1) * k - oy, h);
  const float ix = inv[x1 - x0];
  float4 lo = float4(0.0f);
  for (int y = y0; y < y1; y++)
  {
    lo = fma(rows[(size_t)y * (size_t)lw + (size_t)X], float4(ix), lo);
  }
  low[(size_t)Y * (size_t)lw + (size_t)X] = lo * inv[y1 - y0];
}

/* Bilinear interpolation of the low field back to w x h at block
   centres (clamped to the outermost centres).
   ABI: params = [w, h, k, lw, lh, ox, oy, inv2k]. */
kernel void spectral_film_wide_up(
    device const float4 *low [[buffer(0)]],
    device float4 *out [[buffer(1)]],
    constant const float *params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  const int k = (int)params[2], lw = (int)params[3], lh = (int)params[4];
  const int ox = (int)params[5], oy = (int)params[6];
  const float inv2k = params[7];
  const int x = (int)gid.x, y = (int)gid.y;
  if (x >= w || y >= h) { return; }
  const float v = (float)(2 * (y + oy) + 1 - k) * inv2k;
  int j0 = (int)floor(v), j1;
  float fy;
  if (j0 < 0) { j0 = j1 = 0; fy = 0.0f; }
  else if (j0 >= lh - 1) { j0 = j1 = lh - 1; fy = 0.0f; }
  else { j1 = j0 + 1; fy = v - (float)j0; }
  const float u = (float)(2 * (x + ox) + 1 - k) * inv2k;
  int i0 = (int)floor(u), i1;
  float fx;
  if (i0 < 0) { i0 = i1 = 0; fx = 0.0f; }
  else if (i0 >= lw - 1) { i0 = i1 = lw - 1; fx = 0.0f; }
  else { i1 = i0 + 1; fx = u - (float)i0; }
  const float4 p00 = low[(size_t)j0 * (size_t)lw + (size_t)i0];
  const float4 p01 = low[(size_t)j0 * (size_t)lw + (size_t)i1];
  const float4 p10 = low[(size_t)j1 * (size_t)lw + (size_t)i0];
  const float4 p11 = low[(size_t)j1 * (size_t)lw + (size_t)i1];
  const float4 top = fma(float4(fx), p01 - p00, p00);
  const float4 bot = fma(float4(fx), p11 - p10, p10);
  out[(size_t)y * (size_t)w + (size_t)x] = fma(float4(fy), bot - top, top);
}

/* ---- T5: the bank/mix/combine/apply packet + the buffer gauss pair ----
   (the T5 leg's splice faces — the upstream fma-pinned combines,
   transcribed from spektra_core.c's sf_halation/sf_diffusion_filter
   combine loops + spektrafilm.cl's spektrafilm_gauss_row/col_4c) */

/* Fold one blurred component into the acc plane (first = overwrite,
   else channel-weighted add). ABI: params = [w, h, w0, w1, w2, first]. */
kernel void spectral_film_bank_fold(
    texture2d<float, access::read> comp [[texture(0)]],
    texture2d<float, access::read_write> acc [[texture(1)]],
    constant const float *params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const float4 c = comp.read(gid);
  const float3 cw = float3(params[2], params[3], params[4]);
  const float4 add = float4(c.x * cw.x, c.y * cw.y, c.z * cw.z, 0.0f);
  if (params[5] != 0.0f) { acc.write(add, gid); }
  else { acc.write(acc.read(gid) + add, gid); }
}

/* The convex mix (plane = (1−p)·plane + p·scatter — in-place).
   ABI: params = [w, h, p]. */
kernel void spectral_film_convex_mix(
    texture2d<float, access::read_write> plane [[texture(0)]],
    texture2d<float, access::read> scatter [[texture(1)]],
    constant const float *params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const float p = params[2];
  const float4 cur = plane.read(gid);
  const float4 sct = scatter.read(gid);
  plane.write(fma(float4(p), sct - cur, cur), gid);
}

/* The scatter combine (scattered = w·tail + (1−w)·core, then plane =
   (1−s)·plane + s·scattered — in-place on plane).
   ABI: params = [w, h, w0, w1, w2, s]. */
kernel void spectral_film_scatter_combine(
    texture2d<float, access::read_write> plane [[texture(0)]],
    texture2d<float, access::read> core [[texture(1)]],
    texture2d<float, access::read> tail [[texture(2)]],
    constant const float *params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const float3 ws = float3(params[2], params[3], params[4]);
  const float s = params[5];
  const float4 cur = plane.read(gid);
  const float4 co = core.read(gid);
  const float4 ta = tail.read(gid);
  const float3 scattered = fma(ws, ta.xyz, (1.0f - ws) * co.xyz);
  plane.write(float4(fma(float3(s), scattered - cur.xyz, cur.xyz), cur.w), gid);
}

/* The halation apply (plane = (a·blur + plane) / (1 + a) — in-place).
   ABI: params = [w, h, a0, a1, a2]. */
kernel void spectral_film_halation_apply(
    texture2d<float, access::read_write> plane [[texture(0)]],
    texture2d<float, access::read> blur [[texture(1)]],
    constant const float *params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const float3 a = float3(params[2], params[3], params[4]);
  const float4 cur = plane.read(gid);
  const float4 bl = blur.read(gid);
  plane.write(
      float4(fma(a, bl.xyz, cur.xyz) / (1.0f + a), cur.w), gid);
}

/* The buffer-backed separable gauss pair (the low-face leg — float4
   buffer faces, fma-pinned accumulators, clamped bounds).
   ABI: params = [w, h, radius]. */
kernel void spectral_film_wide_gauss_row(
    device const float4 *src [[buffer(0)]],
    device float4 *dst [[buffer(1)]],
    device const float *weights [[buffer(2)]],
    constant const float *params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int radius = (int)params[2];
  float4 acc = float4(0.0f);
  for (int k = -radius; k <= radius; k++)
  {
    int xx = (int)gid.x + k;
    xx = xx < 0 ? 0 : (xx >= w ? w - 1 : xx);
    acc = fma(float4(weights[k + radius]),
              src[(size_t)gid.y * (size_t)w + (size_t)xx], acc);
  }
  dst[(size_t)gid.y * (size_t)w + (size_t)gid.x] = acc;
}

kernel void spectral_film_wide_gauss_col(
    device const float4 *src [[buffer(0)]],
    device float4 *dst [[buffer(1)]],
    device const float *weights [[buffer(2)]],
    constant const float *params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)params[0], h = (int)params[1];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int radius = (int)params[2];
  float4 acc = float4(0.0f);
  for (int k = -radius; k <= radius; k++)
  {
    int yy = (int)gid.y + k;
    yy = yy < 0 ? 0 : (yy >= h ? h - 1 : yy);
    acc = fma(float4(weights[k + radius]),
              src[(size_t)yy * (size_t)w + (size_t)gid.x], acc);
  }
  dst[(size_t)gid.y * (size_t)w + (size_t)gid.x] = acc;
}
