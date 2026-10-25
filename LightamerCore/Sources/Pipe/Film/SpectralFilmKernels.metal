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
*/

/* SpectralFilmKernels.metal — the FSIM spectral film core's GPU face
 * (Plan M8-1b T1).
 *
 * PORTED from darktable's spektrafilm.cl (data/kernels/spektrafilm.cl,
 * GPL-3.0, Copyright (C) 2026 darktable developers — the per-pixel
 * colour-science kernels of the native spektrafilm iop, themselves a
 * validated port of spektrafilm 0.3.x). Modified by Lightamer (2026):
 * the port to Metal Shading Language and the fused-dispatch restructuring
 * documented below; the upstream copyright is preserved per GPL-3.0
 * same-license incorporation (NOTICE item 3).
 * The marked modifications:
 *   - OpenCL C translated to Metal Shading Language (image2d_t read/write
 *     → texture2d<float, access::read/write>; __global float4 planes →
 *     textures; readpixel/write_ipixel → texture.read/.write);
 *   - the SEVEN per-pixel stage functions are exposed as named functions
 *     (spectral_stage_expose/lograw/develop_corr/develop/print_expose/
 *     print_develop/scan) and composed into TWO fused dispatch kernels
 *     (spectral_film_stage_a / spectral_film_stage_b) instead of upstream's
 *     one-dispatch-per-stage plane chain — the M8-1b fused A/B form
 *     (RESEARCH §4.2 ①, X3): dispatch A fuses expose + lograw +
 *     develop_corr and writes the coupler-correction field DIRECTLY at
 *     the decimated grid (each thread box-averages its ds×ds source
 *     block — no full-resolution corr plane ever exists, the H-M2
 *     memory posture); dispatch B re-derives expose + lograw per pixel
 *     (compute-for-memory trade) and fuses develop + print_expose +
 *     print_develop + scan, sampling the blurred corr field bilinearly
 *     (the fused upsample arm);
 *   - the intermediate blur is this file's own minimal separable-Gaussian
 *     pair (spectral_film_blur_row/col — the upstream
 *     spektrafilm_gauss_row_4c/col_4c shape ported verbatim); NOT an
 *     import of the shared blur infrastructure;
 *   - the tables come from the M8-1a Float64 build engine through
 *     SpectralPayloads (T2): the tc LUT is a rgba32Float texture (alpha
 *     padded — Metal has no float3 pixel format, review m9), the PCHIP
 *     sets / curves / the 93-float constant block are device buffers;
 *   - the exposure EV rides the solve-gain consumption layer (D-M8-8):
 *     ev_scale arrives ≡ 1.0;
 *   - the input gamut compression remap is PRE-FOLDED into the tc LUT at
 *     build time (review M1) — the kernel face has no remap code, the
 *     gather addresses the already-compressed domain.
 *   (M8-2 addition) spectral_film_strength_mix — the RFC-025 strength
 *     blend the film leg dispatches AFTER stage B when the document's
 *     strength < 1; the seven-stage fused family above is untouched.
 *
 * NOT PORTED (upstream spatial-effect family, M8 v1 scope decision,
 * CONTEXT D-M8-4): grain, halation, diffusion, highlight boost, glare,
 * the yvv recursive-Gaussian bank, ACES-RGC compress mode (mode 2),
 * scanner black/white-point (the engine's typed placeholder is
 * fail-closed), output luminance boost (engine emits no boost face).
 *
 * BIT-EXACT DISCIPLINE (X5, the three nails — upstream spektrafilm.cl
 * lines 47-103 are the record of the three REAL CPU/GPU divergence
 * cases that shaped them):
 *   1. every matrix multiply and Mitchell weight is an EXPLICIT fma()
 *      pin, same nesting as the host twins (mat3_mulv_f /
 *      mitchell_weight_f in spektra_sim.c) — FP_CONTRACT pragmas do not
 *      settle the host/device contract difference, an explicit fma does;
 *   2. every reciprocal in the table face (inv_le_step, enl_inv_range,
 *      scan_inv_range) was computed ONCE on the host in double and
 *      rounded to float (SpectralPayloads carries the engine's stored
 *      values) — the device NEVER re-derives one;
 *   3. log10/pow10 go through the SHARED log2/exp2 polynomial pair
 *      (sf_log2f/sf_exp2f here, the port of grain.h's grain_log2f/
 *      grain_exp2f — the same polynomial the host compiles), NOT the
 *      platform built-ins whose ≤3 ULP slack the segment boundaries of
 *      the curve lookups amplify.
 */

#include <metal_stdlib>
using namespace metal;

/* ---------------------------------------------------------------- */
/* constant-block layout (93 floats — the upstream sf_sim_gpu_t
   sf_sim_gpu_export offsets, spektrafilm.cl lines 78-89)            */
/* ---------------------------------------------------------------- */

#define SF_M_IN 0        /* 9: work RGB -> XYZ(film ref), CAT16 included */
#define SF_M_OUT 9       /* 9: XYZ(view) -> work RGB, CAT02 included */
#define SF_M_COUPLERS 18 /* 9: DIR coupler matrix, amount-scaled */
#define SF_M_RGB2XYZ 27  /* 9: output RGB -> XYZ (plain, for OkLab) */
#define SF_M_XYZ2RGB 36  /* 9 */
#define SF_M_OK1 45      /* 9: OkLab M1 */
#define SF_M_OK2 54      /* 9: OkLab M2 */
#define SF_M_OK1I 63     /* 9: inv(M1) */
#define SF_M_OK2I 72     /* 9: inv(M2) */
#define SF_M_LM_DONOR 81 /* 6: langmuir donor K[3] + D_ref[3] (K=1e30 = linear) */
#define SF_M_LM_RECV 87  /* 6: langmuir receiver Kr[3] + c_ref[3] */
#define SF_M_TOTAL 93

/* uniform slots (one float array; integer-valued slots are float
   encoded and cast at the use site — no Swift/Metal struct ABI to
   keep in sync) */
#define SF_U_WIDTH 0
#define SF_U_HEIGHT 1
#define SF_U_TC_SIDE 2
#define SF_U_STEPS 3
#define SF_U_CURVE_COUNT 4
#define SF_U_LE0 5
#define SF_U_INV_LE_STEP 6
#define SF_U_EV_SCALE 7
#define SF_U_LOG10_PRINT_EXPOSURE 8
#define SF_U_OUT_SCALE 9
#define SF_U_DMAX 10            /* 3: film dmax (silver polarity face) */
#define SF_U_ENL_LO 13          /* 3 */
#define SF_U_ENL_INV_RANGE 16   /* 3 (host double, rounded once) */
#define SF_U_SCAN_LO 19         /* 3 */
#define SF_U_SCAN_INV_RANGE 22  /* 3 (host double, rounded once) */
#define SF_U_POSITIVE 25        /* 0/1 — silver polarity */
#define SF_U_USE_CORR 26        /* 0/1 — coupler correction enable */
#define SF_U_DONOR_LM 27        /* 0/1 — langmuir donor gate */
#define SF_U_RECV_LM 28         /* 0/1 — langmuir receiver gate */
#define SF_U_COMPRESS_MODE 29   /* 1 = OkLCh (the only v1 mode) */
#define SF_U_CORR_W 30          /* corr plane width (small grid) */
#define SF_U_CORR_H 31
#define SF_U_CORR_DS 32         /* decimation factor (4 or 8, probe ③) */
#define SF_U_BLUR_RADIUS 33     /* corr blur half-width (taps = 2r+1) */
#define SF_U_TOTAL 34

#define SF_LOG_EPS 1e-10f

/* ---------------------------------------------------------------- */
/* the shared log2/exp2 polynomial pair — the port of grain.h's
   grain_log2f/grain_exp2f/grain_exp2i (GPL-3.0, (C) darktable
   developers). The Horner chains are FMA-PINNED: the first device run
   showed the Metal compiler contracts a handful of the bare forms (the
   T3 bit-identity battery measured 41/384 divergent samples on the
   bare spelling), so the pin replaces "both sides bare" with "both
   sides pinned" — the same by-construction agreement, one compiler
   mood shorter (the M8-1B-DECISIONS nail-③ note).                    */
/* ---------------------------------------------------------------- */

static inline float sf_exp2i(int k)
{
  /* 2^k by writing k into the binary32 exponent field — exact
     bit manipulation, no rounding (the grain.h form). */
  return as_type<float>((uint)(k + 127) << 23);
}

static inline float sf_exp2f(float x)
{
  /* x = k + r, k integer and |r| <= 0.5, so 2^x = 2^k * e^(r ln2) with
     the exponential over |t| <= 0.347 by a degree-7 Taylor polynomial
     in Horner form and 2^k injected exactly. */
  const int k = (int)floor(x + 0.5f);
  const float t = (x - (float)k) * 0.6931471824645996f; /* ln(2) */
  float p = 0.000198412700f;                            /* 1/5040 */
  p = fma(p, t, 0.00138888892f);                        /* 1/720 */
  p = fma(p, t, 0.00833333377f);                        /* 1/120 */
  p = fma(p, t, 0.0416666679f);                         /* 1/24 */
  p = fma(p, t, 0.166666672f);                          /* 1/6 */
  p = fma(p, t, 0.5f);
  p = fma(p, t, 1.0f);
  p = fma(p, t, 1.0f);
  return p * sf_exp2i(k);
}

static inline float sf_log2f(float x)
{
  /* Take the binary exponent off by hand, then fold the mantissa into
     [1/sqrt2, sqrt2]. The series itself is DIVISION-FREE: a degree-13
     fma-Horner fit of ln(1+q) over q = m-1 in [-0.293, 0.414] (max
     measured error 3.2e-8 in ln units). The upstream grain.h form used
     s = (m-1)/(m+1) with the host and the OpenCL device BOTH rounding
     the division correctly; this device divides differently (the first
     T3 run measured 13/384 samples one-two ULP off, all near the
     cancellation zone), so the fit removes the division from the shared
     face — determinism by construction, the same remedy class as the
     fma pins. The exponent peel + fold steps stay the upstream form
     (exact bit manipulation). */
  const uint xu = as_type<uint>(x);
  int e = (int)((xu >> 23) & 0xffu) - 127;
  float m = as_type<float>((xu & 0x007fffffu) | 0x3f800000u);
  if (m > 1.41421356f) { m *= 0.5f; e += 1; }
  const float q = m - 1.0f;
  float p = 0.05207313597202301f;
  p = fma(p, q, -0.09844003617763519f);
  p = fma(p, q, 0.10096900165081024f);
  p = fma(p, q, -0.09942647814750671f);
  p = fma(p, q, 0.10994011908769608f);
  p = fma(p, q, -0.12494739145040512f);
  p = fma(p, q, 0.14291955530643463f);
  p = fma(p, q, -0.16667121648788452f);
  p = fma(p, q, 0.1999983936548233f);
  p = fma(p, q, -0.24999989569187164f);
  p = fma(p, q, 0.3333333432674408f);
  p = fma(p, q, -0.5f);
  p = fma(p, q, 1.0f);
  return fma(p * q, 1.4426950216293335f, (float)e); /* log2(e) */
}

/* base-10 <-> base-2, matching the host twins (the upstream spektrafilm.cl
   lines 250-275 record: the host does NOT call log10f()/exp10f() — it
   defines SF_LOG10F/SF_POW10F over the shared polynomial, so calling the
   platform log10()/exp10() here would be a DIFFERENT computation, not a
   more-or-less accurate version of the same one). */
static inline float sf_log10f(float x)
{
  return sf_log2f(x) * 0.3010299956639812f;
}

static inline float sf_pow10f(float x)
{
  return sf_exp2f(x * 3.321928094887362f);
}

/* ---------------------------------------------------------------- */
/* [su] Mitchell-Netravali cubic on the tc_n×tc_n spectral LUT
   (texture form — the rgba32Float alpha-padded carrier)              */
/* ---------------------------------------------------------------- */

static inline float sf_mitchell(float t)
{
  const float B = 1.0f / 3.0f, C = 1.0f / 3.0f;
  const float x = fabs(t);
  /* fma-pinned, matching mitchell_weight_f() in spektra_sim.c term for
     term (the nail ① discipline) */
  if (x < 1.0f)
    return (1.0f / 6.0f)
           * fma((12.0f - 9.0f * B - 6.0f * C) * x * x, x,
                 fma((-18.0f + 12.0f * B + 6.0f * C) * x, x, (6.0f - 2.0f * B)));
  else if (x < 2.0f)
    return (1.0f / 6.0f)
           * fma((-B - 6.0f * C) * x * x, x,
                 fma((6.0f * B + 30.0f * C) * x, x,
                     fma((-12.0f * B - 48.0f * C), x, (8.0f * B + 24.0f * C))));
  return 0.0f;
}

static inline int sf_reflect(int idx, int L)
{
  if (idx < 0) return -idx;
  if (idx >= L) return 2 * (L - 1) - idx;
  return idx;
}

/* The base index + fraction with the NaN-to-low ordering — the port of
   the HOST twin cubic_base_fraction_f (spektra_sim.c: the ordered form so
   a non-finite coordinate lands on the low branch; a NaN fails every
   comparison, so an ordinary clamp would pass it through and
   (int)floor(NaN) is undefined). The upstream .cl's grain_clampf-based
   sf_base_frac is NOT the NaN-hardened form; the host's hardened float
   twin is, and that is what this port carries (the M8-1b plan's NaN
   hardening clause). */
static inline void sf_base_frac(float coord, int L,
                                thread int *base, thread float *frac)
{
  if (!(coord > 0.0f)) { *base = 0; *frac = 0.0f; return; }
  if (coord >= (float)(L - 1)) { *base = L - 2; *frac = 1.0f; return; }
  *base = (int)floor(coord);
  *frac = coord - (float)(*base);
}

static inline float3 sf_cubic2d(texture2d<float, access::read> lut, int L,
                                float x, float y)
{
  int xb, yb;
  float xf, yf;
  sf_base_frac(x, L, &xb, &xf);
  sf_base_frac(y, L, &yb, &yf);
  float wx[4], wy[4];
  for (int i = 0; i < 4; i++)
  {
    wx[i] = sf_mitchell(xf + 1.0f - (float)i);
    wy[i] = sf_mitchell(yf + 1.0f - (float)i);
  }
  float3 acc = float3(0.0f);
  float wsum = 0.0f;
  for (int i = 0; i < 4; i++)
  {
    const int xi = sf_reflect(xb - 1 + i, L);
    for (int j = 0; j < 4; j++)
    {
      const int yj = sf_reflect(yb - 1 + j, L);
      const float w = wx[i] * wy[j];
      wsum += w;
      const float4 px = lut.read(uint2((uint)xi, (uint)yj));
      /* fma, matching cubic_interp_2d_f()'s accumulator (the nail ①) */
      acc = float3(fma(w, px.x, acc.x), fma(w, px.y, acc.y),
                     fma(w, px.z, acc.z));
    }
  }
  return (wsum != 0.0f) ? acc / wsum : acc;
}

/* ---------------------------------------------------------------- */
/* explicit-fma mat3 (the nail ① — the sf_mat3 port, same nesting as
   mat3_mulv_f in spektra_sim.c)                                      */
/* ---------------------------------------------------------------- */

static inline float3 sf_mat3(constant const float *m, float3 v)
{
  return float3(fma(m[0], v.x, fma(m[1], v.y, m[2] * v.z)),
                  fma(m[3], v.x, fma(m[4], v.y, m[5] * v.z)),
                  fma(m[6], v.x, fma(m[7], v.y, m[8] * v.z)));
}

/* ---------------------------------------------------------------- */
/* [dc] density curve interpolation over the uniform log-exposure
   grid — the sf_curve port. inv_le_step is the HOST's stored
   reciprocal (1/le_step rounded once from double) — NOT recomputed
   on-device, and not a divide (the nail ②; upstream spektrafilm.cl
   lines 177-185 are the record of the real divergence).              */
/* ---------------------------------------------------------------- */

static inline float sf_curve(device const float *curves, float x,
                             float le0, float inv_le_step, int count, int c)
{
  const float t = (x - le0) * inv_le_step;
  if (t <= 0.0f) return curves[c];
  if (t >= (float)(count - 1)) return curves[(count - 1) * 3 + c];
  const int i = (int)t;
  const float f = t - (float)i;
  /* fma pin — the same compiler-mood argument as the Horner chains */
  return fma(f, curves[(i + 1) * 3 + c] - curves[i * 3 + c], curves[i * 3 + c]);
}

/* ---------------------------------------------------------------- */
/* [fi] monotone-PCHIP 3D LUT (values + per-axis slopes + cell
   clamp) — the sf_pchip3d port                                       */
/* ---------------------------------------------------------------- */

static inline float sf_hermite(float y0, float y1, float m0, float m1, float t)
{
  /* the same cubic in Horner form, fma-pinned: t^3*A + t^2*B + t*m0 + y0
     with A = 2y0 + m0 - 2y1 + m1, B = 3y1 - 3y0 - 2m0 - m1 (the bare
     spelling contracted differently on the device — the same first-run
     finding as the polynomial chains) */
  /* even the COEFFICIENT spellings are pinned: every mul+add pattern is
     an explicit fma (the bare `2*y0 + m0` contracted on the device —
     the second-run finding) */
  float a = fma(2.0f, y0, m0);
  a = fma(-2.0f, y1, a);
  a = a + m1;
  float b = 3.0f * y1;
  b = fma(-3.0f, y0, b);
  b = fma(-2.0f, m0, b);
  b = b - m1;
  float r = fma(t, a, b);
  r = fma(t, r, m0);
  return fma(t, r, y0);
}

static inline float3 sf_pchip3d(device const float *lut, device const float *sx,
                                device const float *sy, device const float *sz,
                                device const float *cmin, device const float *cmax,
                                const int n, float r, float g, float b)
{
  const int m = n - 1;
  int i, j, k;
  float tr, tg, tb;
  sf_base_frac(r, n, &i, &tr);
  sf_base_frac(g, n, &j, &tg);
  sf_base_frac(b, n, &k, &tb);
  float out[3];
#define SF_AT(arr, ii, jj, kk, c) \
  arr[((((size_t)(ii)) * n + (jj)) * n + (kk)) * 3 + (c)]
  for (int c = 0; c < 3; c++)
  {
    const float v000 = sf_hermite(SF_AT(lut, i, j, k, c), SF_AT(lut, i + 1, j, k, c),
                                  SF_AT(sx, i, j, k, c), SF_AT(sx, i + 1, j, k, c), tr);
    const float v010 = sf_hermite(SF_AT(lut, i, j + 1, k, c), SF_AT(lut, i + 1, j + 1, k, c),
                                  SF_AT(sx, i, j + 1, k, c), SF_AT(sx, i + 1, j + 1, k, c), tr);
    const float v001 = sf_hermite(SF_AT(lut, i, j, k + 1, c), SF_AT(lut, i + 1, j, k + 1, c),
                                  SF_AT(sx, i, j, k + 1, c), SF_AT(sx, i + 1, j, k + 1, c), tr);
    const float v011 = sf_hermite(SF_AT(lut, i, j + 1, k + 1, c), SF_AT(lut, i + 1, j + 1, k + 1, c),
                                  SF_AT(sx, i, j + 1, k + 1, c), SF_AT(sx, i + 1, j + 1, k + 1, c), tr);
    /* the mixes spell the explicit x*(1−t) + y*t form with the SECOND
       product fma-fused (NOT the mix() intrinsic — the OpenCL and MSL
       specs state DIFFERENT roundings for it; and the bare spelling
       contracted differently on the device — the first-run finding — so
       the pin is the only form both sides agree on by construction) */
    const float sy00 = fma(SF_AT(sy, i + 1, j, k, c), tr, SF_AT(sy, i, j, k, c) * (1.0f - tr));
    const float sy10 = fma(SF_AT(sy, i + 1, j + 1, k, c), tr, SF_AT(sy, i, j + 1, k, c) * (1.0f - tr));
    const float sy01 = fma(SF_AT(sy, i + 1, j, k + 1, c), tr, SF_AT(sy, i, j, k + 1, c) * (1.0f - tr));
    const float sy11 = fma(SF_AT(sy, i + 1, j + 1, k + 1, c), tr, SF_AT(sy, i, j + 1, k + 1, c) * (1.0f - tr));
    const float vz0 = sf_hermite(v000, v010, sy00, sy10, tg);
    const float vz1 = sf_hermite(v001, v011, sy01, sy11, tg);
    const float sz0 = fma(fma(SF_AT(sz, i + 1, j + 1, k, c), tr, SF_AT(sz, i, j + 1, k, c) * (1.0f - tr)),
                          tg, fma(SF_AT(sz, i + 1, j, k, c), tr, SF_AT(sz, i, j, k, c) * (1.0f - tr)) * (1.0f - tg));
    const float sz1 = fma(fma(SF_AT(sz, i + 1, j + 1, k + 1, c), tr, SF_AT(sz, i, j + 1, k + 1, c) * (1.0f - tr)),
                          tg, fma(SF_AT(sz, i + 1, j, k + 1, c), tr, SF_AT(sz, i, j, k + 1, c) * (1.0f - tr)) * (1.0f - tg));
    float v = sf_hermite(vz0, vz1, sz0, sz1, tb);
    const size_t ci = ((((size_t)i) * m + j) * m + k) * 3 + c;
    v = fmin(fmax(v, cmin[ci]), cmax[ci]);
    out[c] = v;
  }
#undef SF_AT
  return float3(out[0], out[1], out[2]);
}

/* ---------------------------------------------------------------- */
/* [gc] Reinhard knee + OkLCh output gamut compression — the
   sf_knee / sf_xyz_to_oklab / sf_oklab_to_xyz / sf_cmax_lookup ports */
/* ---------------------------------------------------------------- */

/* pow over the SHARED pair (nail ③'s own remedy extended to the knee:
   Metal's pow is spec'd to a few ULP against the host's correctly-rounded
   powf — the same class of gap the grain.h polynomial exists for; riding
   the shared pair makes both sides agree by construction). Domain: x > 0
   (the knee only computes above its threshold). */
static inline float sf_powf_shared(float x, float p)
{
  return sf_exp2f(p * sf_log2f(x));
}

static inline float sf_knee(float d, float threshold, float limit, float power)
{
  if (d <= threshold) return d;
  const float scale = limit - threshold;
  const float x = (d - threshold) / scale;
  const float y = x / sf_powf_shared(1.0f + sf_powf_shared(x, power), 1.0f / power);
  return fma(scale, y, threshold);
}

/* Metal ships no cbrt — the cube root rides the SHARED polynomial pair
   (exp2f(log2f(x)/3), nail ③'s own remedy: both sides agree bit-for-bit
   by construction instead of trusting the platform built-ins). The
   domain carries the sign (OkLab LMS is non-negative for physically
   positive XYZ; the sign path keeps the helper total). */
static inline float sf_cbrt(float x)
{
  if (x == 0.0f) return x;
  const float s = x < 0.0f ? -1.0f : 1.0f;
  return s * sf_exp2f(sf_log2f(fabs(x)) * (1.0f / 3.0f));
}

static inline float3 sf_xyz_to_oklab(constant const float *mats, float3 xyz)
{
  float3 lms = sf_mat3(mats + SF_M_OK1, xyz);
  lms = float3(sf_cbrt(lms.x), sf_cbrt(lms.y), sf_cbrt(lms.z));
  return sf_mat3(mats + SF_M_OK2, lms);
}

static inline float3 sf_oklab_to_xyz(constant const float *mats, float3 lab)
{
  float3 lms = sf_mat3(mats + SF_M_OK2I, lab);
  lms = lms * lms * lms;
  return sf_mat3(mats + SF_M_OK1I, lms);
}

static float sf_cmax_lookup(device const float *table, const int nl, const int nh,
                            float L, float h)
{
  const float L_lo_v = 0.02f, L_hi_v = 1.0f;
  L = fmin(fmax(L, L_lo_v), L_hi_v);
  const float h_step = 2.0f * M_PI_F / (float)nh;
  const float h_idx = (h + M_PI_F) / h_step;
  const float h_floor = floor(h_idx);
  int h_lo = ((int)h_floor) % nh;
  if (h_lo < 0) h_lo += nh;
  const int h_hi = (h_lo + 1) % nh;
  const float h_frac = h_idx - h_floor;
  const float L_idx = (L - L_lo_v) / (L_hi_v - L_lo_v) * (float)(nl - 1);
  int L_lo = (int)floor(L_idx);
  L_lo = clamp(L_lo, 0, nl - 2);
  const float L_frac = L_idx - (float)L_lo;
  const float v00 = table[(size_t)L_lo * nh + h_lo];
  const float v01 = table[(size_t)L_lo * nh + h_hi];
  const float v10 = table[(size_t)(L_lo + 1) * nh + h_lo];
  const float v11 = table[(size_t)(L_lo + 1) * nh + h_hi];
  /* the four-tap bilinear in a pinned accumulation order (v00 base,
     fma folds toward it) — the bare spelling contracted on the device */
  const float w00 = (1 - L_frac) * (1 - h_frac);
  const float w01 = (1 - L_frac) * h_frac;
  const float w10 = L_frac * (1 - h_frac);
  const float w11 = L_frac * h_frac;
  float acc = v00 * w00;
  acc = fma(v01, w01, acc);
  acc = fma(v10, w10, acc);
  return fma(v11, w11, acc);
}

/* ---------------------------------------------------------------- */
/* ================================================================= */
/* THE SEVEN PER-PIXEL STAGE FUNCTIONS (the plan's seven-stage face —
   each one a named pure function over the payload faces, composed by
   the fused kernels below)                                           */
/* ================================================================= */
/* ---------------------------------------------------------------- */

/* stage 1 — expose: work RGB -> linear film raw exposure
   (upstream spektrafilm_expose / sf_sim_expose). The input gamut
   compression remap is PRE-FOLDED into the tc LUT (review M1) — no
   remap step here. ev_scale arrives ≡ 1 (D-M8-8). */
static inline float3 spectral_stage_expose(
    float3 rgb,
    constant const float *consts,
    texture2d<float, access::read> tcLut,
    int tcSide, float evScale)
{
  float3 xyz = sf_mat3(consts + SF_M_IN, rgb);
  const float b = xyz.x + xyz.y + xyz.z;
  /* one reciprocal then two multiplies, not two divides — the upstream
     expose_pixel_f form (two divides each carry their own rounding and
     the difference is enough to move the tc index across a cell
     boundary) */
  const float inv = 1.0f / fmax(b, 1e-10f);
  const float xx = xyz.x * inv, yy = xyz.y * inv;
  /* [su] tri2quad — fmin/fmax so NaN maps to the low bound */
  const float tcx = fmin(fmax((1.0f - xx) * (1.0f - xx), 0.0f), 1.0f);
  const float tcy = fmin(fmax(yy / fmax(1.0f - xx, 1e-10f), 0.0f), 1.0f);
  const float scale = (float)(tcSide - 1);
  float3 raw = sf_cubic2d(tcLut, tcSide, tcx * scale, tcy * scale);
  /* NaN hardening: a non-finite luminance contributes NOTHING
     (upstream: the bb = isfinite(b) ? b : 0 guard; the gather itself
     stays finite because sf_base_frac maps NaN to index 0) */
  const float bb = isfinite(b) ? b : 0.0f;
  raw *= bb * evScale;
  return raw;
}

/* stage 2 — lograw: linear raw -> log10 exposure (the shared
   polynomial, nail ③) */
static inline float3 spectral_stage_lograw(float3 raw)
{
  return float3(sf_log10f(fmax(raw.x, 0.0f) + SF_LOG_EPS),
                  sf_log10f(fmax(raw.y, 0.0f) + SF_LOG_EPS),
                  sf_log10f(fmax(raw.z, 0.0f) + SF_LOG_EPS));
}

/* stage 3 — develop_corr: log raw -> DIR coupler correction field
   (upstream spektrafilm_develop_corr / sf_sim_develop_corr). Silver =
   the develop curve lookup (positive stocks: dmax − d); the Langmuir
   DONOR saturation rides the donor_lm gate — the gate is load-bearing
   (upstream: running it unconditionally and relying on the K=1e30
   sentinel to degenerate to linear does not work, x*y/y is not x in
   float); the coupler matrix multiply is fma-pinned (the nail ① per
   the M8-1b plan, against upstream's bare form here). */
static inline float3 spectral_stage_develop_corr(
    float3 lograw,
    device const float *curves,
    constant const float *consts,
    constant const float *u,
    int curveCount)
{
  const float le0 = u[SF_U_LE0];
  const float invLeStep = u[SF_U_INV_LE_STEP];
  const int positive = (int)u[SF_U_POSITIVE];
  const int donorLM = (int)u[SF_U_DONOR_LM];
  const float dmx[3] = { u[SF_U_DMAX + 0], u[SF_U_DMAX + 1], u[SF_U_DMAX + 2] };
  const float lgv[3] = { lograw.x, lograw.y, lograw.z };
  float silver[3];
  for (int c = 0; c < 3; c++)
  {
    const float d = sf_curve(curves, lgv[c], le0, invLeStep, curveCount, c);
    silver[c] = positive ? dmx[c] - d : d;
    if (donorLM)
    {
      const float K = consts[SF_M_LM_DONOR + c];
      const float Dref = consts[SF_M_LM_DONOR + 3 + c];
      silver[c] = silver[c] * (K + Dref) / (K + silver[c]);
    }
  }
  constant const float *M = consts + SF_M_COUPLERS; /* row donor -> col receiver */
  /* fma-pinned, matching the host twin (nail ①) */
  return float3(
      fma(silver[0], M[0 * 3 + 0], fma(silver[1], M[1 * 3 + 0], silver[2] * M[2 * 3 + 0])),
      fma(silver[0], M[0 * 3 + 1], fma(silver[1], M[1 * 3 + 1], silver[2] * M[2 * 3 + 1])),
      fma(silver[0], M[0 * 3 + 2], fma(silver[1], M[1 * 3 + 2], silver[2] * M[2 * 3 + 2])));
}

/* stage 4 — develop: (log raw − arrived corr) -> CMY film density
   (upstream spektrafilm_develop / sf_sim_develop). The receiver-side
   Langmuir acts on the ARRIVED (post-diffusion) inhibitor, gated on
   useCorr && recvLM. */
static inline float3 spectral_stage_develop(
    float3 lograw,
    float3 corrArrived,
    device const float *curves,
    constant const float *consts,
    constant const float *u,
    int curveCount)
{
  const float le0 = u[SF_U_LE0];
  const float invLeStep = u[SF_U_INV_LE_STEP];
  const int useCorr = (int)u[SF_U_USE_CORR];
  const int recvLM = (int)u[SF_U_RECV_LM];
  float crv[3] = { corrArrived.x, corrArrived.y, corrArrived.z };
  if (useCorr && recvLM)
  {
    for (int c = 0; c < 3; c++)
    {
      const float Kr = consts[SF_M_LM_RECV + c];
      const float cref = consts[SF_M_LM_RECV + 3 + c];
      crv[c] = crv[c] * (Kr + cref) / (Kr + crv[c]);
    }
  }
  const float lgv[3] = { lograw.x - crv[0], lograw.y - crv[1], lograw.z - crv[2] };
  return float3(
      sf_curve(curves, lgv[0], le0, invLeStep, curveCount, 0),
      sf_curve(curves, lgv[1], le0, invLeStep, curveCount, 1),
      sf_curve(curves, lgv[2], le0, invLeStep, curveCount, 2));
}

/* stage 5 — print_expose: CMY film density -> print log exposure via
   the monotone PCHIP 3D table + the log-domain print-exposure add.
   enlLo/enlInvRange are the HOST's stored values (the nail ② —
   upstream spektrafilm.cl lines 646-657: re-subtracting hi/lo on
   device is the catastrophic-cancellation hazard whenever a channel's
   density range is narrow; the precomputed reciprocal makes the device
   path identical to the CPU by construction). The print exposure rides
   as the exact identity log10(10^l1 * pe) == l1 + log10(pe) — one add,
   no library calls, the same −30 guard the CPU uses (upstream lines
   662-670). */
static inline float3 spectral_stage_print_expose(
    float3 cmy,
    device const float *lut, device const float *sx, device const float *sy,
    device const float *sz, device const float *cmin, device const float *cmax,
    constant const float *u,
    int steps)
{
  const float scale = (float)(steps - 1);
  const float r = (cmy.x - u[SF_U_ENL_LO + 0]) * u[SF_U_ENL_INV_RANGE + 0] * scale;
  const float g = (cmy.y - u[SF_U_ENL_LO + 1]) * u[SF_U_ENL_INV_RANGE + 1] * scale;
  const float b = (cmy.z - u[SF_U_ENL_LO + 2]) * u[SF_U_ENL_INV_RANGE + 2] * scale;
  float3 l1 = sf_pchip3d(lut, sx, sy, sz, cmin, cmax, steps, r, g, b);
  const float pe = u[SF_U_LOG10_PRINT_EXPOSURE];
  return float3(fmax(l1.x + pe, -30.0f), fmax(l1.y + pe, -30.0f),
                  fmax(l1.z + pe, -30.0f));
}

/* stage 6 — print_develop: print log exposure -> print CMY density
   (three 1D curve lookups over the shared 256-point axis — the paper
   axis coincides with the film axis for the whole vendored set,
   measured 28/28) */
static inline float3 spectral_stage_print_develop(
    float3 loge,
    device const float *printCurves,
    constant const float *u,
    int curveCount)
{
  const float le0 = u[SF_U_LE0];
  const float invLeStep = u[SF_U_INV_LE_STEP];
  const float lgv[3] = { loge.x, loge.y, loge.z };
  return float3(
      sf_curve(printCurves, lgv[0], le0, invLeStep, curveCount, 0),
      sf_curve(printCurves, lgv[1], le0, invLeStep, curveCount, 1),
      sf_curve(printCurves, lgv[2], le0, invLeStep, curveCount, 2));
}

/* stage 7 — scan: CMY print density -> work RGB (PCHIP 3D -> pow10 via
   the shared polynomial -> CAT02'd matrix -> OkLCh gamut compression:
   the LIGHTNESS knee (0.7, 1, 2.2) FIRST so C_max is looked up at the
   corrected L, the CHROMA knee (C/C_max; 0, 1, 6) AFTER — the upstream
   order discipline — then out_scale). scanLo/scanInvRange are the
   HOST's stored values (the nail ②). */
static inline float3 spectral_stage_scan(
    float3 cmy,
    device const float *lut, device const float *sx, device const float *sy,
    device const float *sz, device const float *cmin, device const float *cmax,
    device const float *cmaxTable, int cmaxNL, int cmaxNH,
    constant const float *consts,
    constant const float *u,
    int steps)
{
  const float scale = (float)(steps - 1);
  const float r = (cmy.x - u[SF_U_SCAN_LO + 0]) * u[SF_U_SCAN_INV_RANGE + 0] * scale;
  const float g = (cmy.y - u[SF_U_SCAN_LO + 1]) * u[SF_U_SCAN_INV_RANGE + 1] * scale;
  const float b = (cmy.z - u[SF_U_SCAN_LO + 2]) * u[SF_U_SCAN_INV_RANGE + 2] * scale;
  float3 lx = sf_pchip3d(lut, sx, sy, sz, cmin, cmax, steps, r, g, b);
  float3 xyz = float3(sf_pow10f(lx.x), sf_pow10f(lx.y), sf_pow10f(lx.z));
  float3 rgb = sf_mat3(consts + SF_M_OUT, xyz);

  const int compressMode = (int)u[SF_U_COMPRESS_MODE];
  if (compressMode == 1) /* OkLCh chroma + lightness compression */
  {
    float3 lab = sf_xyz_to_oklab(consts, sf_mat3(consts + SF_M_RGB2XYZ, rgb));
    float L = sf_knee(lab.x, 0.7f, 1.0f, 2.2f); /* lightness first */
    const float C = sqrt(fma(lab.z, lab.z, lab.y * lab.y));
    const float hh = atan2(lab.z, lab.y);
    const float C_max = fmax(sf_cmax_lookup(cmaxTable, cmaxNL, cmaxNH, L, hh), 1e-9f);
    const float d = sf_knee(C / C_max, 0.0f, 1.0f, 6.0f);
    const float C_new = d * C_max;
    /* the hue reconstruction rides the RATIO form (cos(h) = a/C exactly)
       — no trig in the reconstruction, and the C = 0 degenerate pixel
       (pure black) lands on 0, not 0/0 */
    const float ratioX = C > 0.0f ? lab.y / C : 0.0f;
    const float ratioY = C > 0.0f ? lab.z / C : 0.0f;
    float3 lab_new = float3(L, C_new * ratioX, C_new * ratioY);
    rgb = sf_mat3(consts + SF_M_XYZ2RGB, sf_oklab_to_xyz(consts, lab_new));
  }

  /* after the compressor, mirroring sf_sim_scan() */
  const float outScale = u[SF_U_OUT_SCALE];
  if (outScale != 1.0f) rgb *= outScale;
  return rgb;
}

/* ---------------------------------------------------------------- */
/* ================================================================= */
/* THE FUSED DISPATCH KERNELS (X3 — two main dispatches + one small
   intermediate plane + the blur pair)                                */
/* ================================================================= */
/* ---------------------------------------------------------------- */

/* dispatch A — expose + lograw + develop_corr FUSED, writing the
   coupler-correction field DIRECTLY at the decimated grid: each thread
   owns one corr cell, walks its ds×ds source block of the INPUT
   texture (edge-clamped), runs the full expose → lograw → silver →
   donor-Langmuir → coupler-matrix chain per source pixel, and
   box-averages. No full-resolution corr plane ever exists (H-M2);
   the downsample is the write pattern itself. Alpha rides as 0 (the
   corr field carries no alpha). */
kernel void spectral_film_stage_a(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> corr [[texture(1)]],
    texture2d<float, access::read> tcLut [[texture(2)]],
    device const float *curves [[buffer(0)]],
    constant const float *consts [[buffer(1)]],
    constant const float *u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int cw = (int)u[SF_U_CORR_W], ch = (int)u[SF_U_CORR_H];
  if ((int)gid.x >= cw || (int)gid.y >= ch) { return; }
  const int ds = (int)u[SF_U_CORR_DS];
  const int curveCount = (int)u[SF_U_CURVE_COUNT];
  const int iw = (int)u[SF_U_WIDTH], ih = (int)u[SF_U_HEIGHT];
  const int tcSide = (int)u[SF_U_TC_SIDE];
  const float evScale = u[SF_U_EV_SCALE];

  float3 acc = float3(0.0f);
  for (int dy = 0; dy < ds; dy++)
  {
    for (int dx = 0; dx < ds; dx++)
    {
      /* edge-clamped source address (the tail cells repeat their edge
         pixel — the box mean stays unbiased there) */
      int sx = (int)gid.x * ds + dx;
      int sy = (int)gid.y * ds + dy;
      sx = sx < iw ? sx : iw - 1;
      sy = sy < ih ? sy : ih - 1;
      const float4 px = in.read(uint2((uint)sx, (uint)sy));
      const float3 raw = spectral_stage_expose(px.xyz, consts, tcLut, tcSide, evScale);
      const float3 lg = spectral_stage_lograw(raw);
      acc += spectral_stage_develop_corr(lg, curves, consts, u, curveCount);
    }
  }
  const float invN = 1.0f / (float)(ds * ds);
  corr.write(float4(acc * invN, 0.0f), gid);
}

/* the corr arm's separable blur pair — this file's own minimal
   Gaussian (the upstream spektrafilm_gauss_row_4c/col_4c shape, ported
   verbatim; NOT an import of the shared blur infrastructure).
   weights = 2*radius+1 host-normalized taps, clamp-to-edge boundary. */
kernel void spectral_film_blur_row(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    device const float *weights [[buffer(0)]],
    constant const float *u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)u[SF_U_CORR_W], h = (int)u[SF_U_CORR_H];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int radius = (int)u[SF_U_BLUR_RADIUS];
  float4 acc = float4(0.0f);
  for (int k = -radius; k <= radius; k++)
  {
    int xx = (int)gid.x + k;
    xx = xx < 0 ? 0 : (xx >= w ? w - 1 : xx);
    acc += weights[k + radius] * src.read(uint2((uint)xx, gid.y));
  }
  dst.write(acc, gid);
}

kernel void spectral_film_blur_col(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    device const float *weights [[buffer(0)]],
    constant const float *u [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)u[SF_U_CORR_W], h = (int)u[SF_U_CORR_H];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int radius = (int)u[SF_U_BLUR_RADIUS];
  float4 acc = float4(0.0f);
  for (int k = -radius; k <= radius; k++)
  {
    int yy = (int)gid.y + k;
    yy = yy < 0 ? 0 : (yy >= h ? h - 1 : yy);
    acc += weights[k + radius] * src.read(uint2(gid.x, (uint)yy));
  }
  dst.write(acc, gid);
}

/* The bilinear corr upsample (the fused arm of X3's 上采样 step): the
   blurred field is sampled bilinearly at the pixel's small-grid
   position — the host twin mirrors this arithmetic term for term.
   fma-pinned accumulation. */
static inline float3 sf_corr_sample(
    texture2d<float, access::read> corr, int cw, int ch, float x, float y)
{
  /* x, y in FULL-grid pixels; map to the small grid and bilinearly
     interpolate with edge clamping */
  const float gx = fmin(fmax(x, 0.0f), (float)(cw - 1));
  const float gy = fmin(fmax(y, 0.0f), (float)(ch - 1));
  const int x0 = (int)floor(gx);
  const int y0 = (int)floor(gy);
  const int x1 = min(x0 + 1, cw - 1);
  const int y1 = min(y0 + 1, ch - 1);
  const float fx = gx - (float)x0;
  const float fy = gy - (float)y0;
  const float4 c00 = corr.read(uint2((uint)x0, (uint)y0));
  const float4 c10 = corr.read(uint2((uint)x1, (uint)y0));
  const float4 c01 = corr.read(uint2((uint)x0, (uint)y1));
  const float4 c11 = corr.read(uint2((uint)x1, (uint)y1));
  const float w00 = (1.0f - fx) * (1.0f - fy);
  const float w10 = fx * (1.0f - fy);
  const float w01 = (1.0f - fx) * fy;
  const float w11 = fx * fy;
  return float3(
      fma(c00.x, w00, fma(c10.x, w10, fma(c01.x, w01, c11.x * w11))),
      fma(c00.y, w00, fma(c10.y, w10, fma(c01.y, w01, c11.y * w11))),
      fma(c00.z, w00, fma(c10.z, w10, fma(c01.z, w01, c11.z * w11))));
}

/* dispatch B — the fused tail: expose + lograw re-derived per pixel
   (compute-for-memory: the lograw plane never exists), develop
   (the blurred corr field sampled bilinearly = the fused upsample),
   print_expose, print_develop, scan — one write, alpha carried from
   the input pixel (the upstream crop_out convention). */
kernel void spectral_film_stage_b(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    texture2d<float, access::read> corr [[texture(2)]],
    texture2d<float, access::read> tcLut [[texture(3)]],
    device const float *curves [[buffer(0)]],
    device const float *printCurves [[buffer(1)]],
    device const float *printLut [[buffer(2)]],
    device const float *printSx [[buffer(3)]],
    device const float *printSy [[buffer(4)]],
    device const float *printSz [[buffer(5)]],
    device const float *printCmin [[buffer(6)]],
    device const float *printCmax [[buffer(7)]],
    device const float *scanLut [[buffer(8)]],
    device const float *scanSx [[buffer(9)]],
    device const float *scanSy [[buffer(10)]],
    device const float *scanSz [[buffer(11)]],
    device const float *scanCmin [[buffer(12)]],
    device const float *scanCmax [[buffer(13)]],
    device const float *cmaxTable [[buffer(14)]],
    constant const float *consts [[buffer(15)]],
    constant const float *u [[buffer(16)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)u[SF_U_WIDTH], h = (int)u[SF_U_HEIGHT];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int tcSide = (int)u[SF_U_TC_SIDE];
  const int steps = (int)u[SF_U_STEPS];
  const int curveCount = (int)u[SF_U_CURVE_COUNT];
  const int cw = (int)u[SF_U_CORR_W], ch = (int)u[SF_U_CORR_H];
  const float evScale = u[SF_U_EV_SCALE];

  const float4 px = in.read(gid);
  const float3 raw = spectral_stage_expose(px.xyz, consts, tcLut, tcSide, evScale);
  const float3 lg = spectral_stage_lograw(raw);
  const float3 arrived = ((int)u[SF_U_USE_CORR] && cw > 0 && ch > 0)
      ? sf_corr_sample(corr, cw, ch, (float)gid.x, (float)gid.y)
      : float3(0.0f);
  const float3 cmy = spectral_stage_develop(lg, arrived, curves, consts, u, curveCount);
  const float3 loge = spectral_stage_print_expose(
      cmy, printLut, printSx, printSy, printSz, printCmin, printCmax, u, steps);
  const float3 printCmy =
      spectral_stage_print_develop(loge, printCurves, u, curveCount);
  const float3 rgb = spectral_stage_scan(
      printCmy, scanLut, scanSx, scanSy, scanSz, scanCmin, scanCmax,
      cmaxTable, 64, 720, consts, u, steps);
  out.write(float4(rgb, px.w), gid);
}

/* ---------------------------------------------------------------- */
/* the per-stage probe kernel (the T3 stage-level bit-exact driver):
   one kernel, `mode` selects WHICH single stage runs per pixel — the
   test harness feeds the right plane in and reads the stage out.
   modes: 0 expose / 1 lograw / 2 develop_corr / 3 develop /
   4 print_expose / 5 print_develop / 6 scan.                         */
kernel void spectral_film_stage_probe(
    texture2d<float, access::read> in [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    texture2d<float, access::read> corr [[texture(2)]],
    texture2d<float, access::read> tcLut [[texture(3)]],
    device const float *curves [[buffer(0)]],
    device const float *printCurves [[buffer(1)]],
    device const float *printLut [[buffer(2)]],
    device const float *printSx [[buffer(3)]],
    device const float *printSy [[buffer(4)]],
    device const float *printSz [[buffer(5)]],
    device const float *printCmin [[buffer(6)]],
    device const float *printCmax [[buffer(7)]],
    device const float *scanLut [[buffer(8)]],
    device const float *scanSx [[buffer(9)]],
    device const float *scanSy [[buffer(10)]],
    device const float *scanSz [[buffer(11)]],
    device const float *scanCmin [[buffer(12)]],
    device const float *scanCmax [[buffer(13)]],
    device const float *cmaxTable [[buffer(14)]],
    constant const float *consts [[buffer(15)]],
    constant const float *u [[buffer(16)]],
    constant const int *mode [[buffer(17)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)u[SF_U_WIDTH], h = (int)u[SF_U_HEIGHT];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const int tcSide = (int)u[SF_U_TC_SIDE];
  const int steps = (int)u[SF_U_STEPS];
  const int curveCount = (int)u[SF_U_CURVE_COUNT];
  const float evScale = u[SF_U_EV_SCALE];

  const float4 px = in.read(gid);
  float4 result = px;
  switch (*mode)
  {
    case 0:
      result = float4(spectral_stage_expose(px.xyz, consts, tcLut, tcSide, evScale), px.w);
      break;
    case 1:
      result = float4(spectral_stage_lograw(px.xyz), px.w);
      break;
    case 2:
      result = float4(
          spectral_stage_develop_corr(px.xyz, curves, consts, u, curveCount), 0.0f);
      break;
    case 3:
      result = float4(
          spectral_stage_develop(px.xyz, corr.read(gid).xyz, curves, consts, u,
                                 curveCount),
          px.w);
      break;
    case 4:
      result = float4(
          spectral_stage_print_expose(px.xyz, printLut, printSx, printSy, printSz,
                                      printCmin, printCmax, u, steps),
          px.w);
      break;
    case 5:
      result = float4(
          spectral_stage_print_develop(px.xyz, printCurves, u, curveCount), px.w);
      break;
    case 6:
      result = float4(
          spectral_stage_scan(px.xyz, scanLut, scanSx, scanSy, scanSz, scanCmin,
                              scanCmax, cmaxTable, 64, 720, consts, u, steps),
          0.0f);
      break;
  }
  out.write(result, gid);
}

/* ---------------------------------------------------------------- */
/* The RFC-025 strength mix (M8-2 production face) — the film leg's
   spectral arm dispatches this AFTER stage B when the document's
   strength < 1: the DENSITY-domain geometric blend
   out = in^(1-k) · film^k (the frozen film_subrun kernel's own
   convention) with the solved session exposure gain folded into the
   input leg's log face (the density arm applies the same gain before
   the mix — one consumption-layer shape). At strength >= 1 the leg
   dispatches B straight into the output and this kernel never runs
   (the bitwise-raw-chain face — the ramp golden's anchor).

   u slots 34/35 are the EXTENDED uniform face (this file's frozen
   SF_U_TOTAL = 34 define belongs to the seven-stage family above, so
   the additions read by literal index): 34 = strength, 35 = gain.
   The log/exp faces are the SHARED polynomial pair (nail 3), the same
   sf_log10f/sf_pow10f the seven stages use — NOT the platform
   built-ins the frozen density kernel uses. Alpha rides the film leg's
   own output (the crop_out convention — the mix never invents alpha). */
kernel void spectral_film_strength_mix(
    texture2d<float, access::read> film [[texture(0)]],
    texture2d<float, access::read> orig [[texture(1)]],
    texture2d<float, access::write> out [[texture(2)]],
    constant const float *u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
  const int w = (int)u[SF_U_WIDTH], h = (int)u[SF_U_HEIGHT];
  if ((int)gid.x >= w || (int)gid.y >= h) { return; }
  const float strength = u[34];
  const float gain = u[35];
  const float4 f = film.read(gid);
  const float4 o = orig.read(gid);
  const float3 lin = o.rgb * gain;
  const float3 inLog = float3(
      sf_log10f(fmax(lin.x, 1e-6f)),
      sf_log10f(fmax(lin.y, 1e-6f)),
      sf_log10f(fmax(lin.z, 1e-6f)));
  const float3 filmLog = float3(
      sf_log10f(fmax(f.x, 1e-6f)),
      sf_log10f(fmax(f.y, 1e-6f)),
      sf_log10f(fmax(f.z, 1e-6f)));
  const float3 outLog = mix(inLog, filmLog, strength);
  out.write(float4(sf_pow10f(outLog.x), sf_pow10f(outLog.y), sf_pow10f(outLog.z), f.w), gid);
}
