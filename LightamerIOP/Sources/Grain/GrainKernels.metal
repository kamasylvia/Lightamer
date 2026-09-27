#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────
// Grain kernel — Plan 08-2 T2 (op "grain", v50 slot 65.0).
//
// Darktable reference (tree dc58cf0ba1): `src/iop/grain.c` (CPU-only iop —
// process_cl does not exist; this Metal kernel is the self-port the plan
// mandates):
//   - the 3D SIMPLEX gradient noise :120-327 VERBATIM (grad3[12],
//     permutation[256], the F3/G3 skew tree, t = 0.6 − r², t⁴·dot,
//     the final ×32 scale into [-1,1]);
//   - the 3-octave spectrum parametrization :292-327 VERBATIM:
//     f = {0.4910, 0.9441, 1.7280}, a = {0.2340, 0.7850, 1.2150}, the
//     octave index rides the noise's third dimension (z = octave);
//   - the domain chain :447-507: x,y normalized to the SHORTER side of
//     the ORIGINAL image, frequency division by zoom =
//     (1 + 8·scale/100)/800 (:450), dt's filename-hash offset replaced by
//     the Lightamer deterministic seed offset (research §8.1 — the seed
//     IS the StableHash(params ⊕ image identity); the % (width·0.3)
//     filename quantum is replaced by a fixed 4096 quantum for
//     resolution independence, DECISIONS D-08-2-3);
//   - the rank-1 lattice downsampling :492-503 verbatim (fib2 = 21 taps,
//     fib1 = 34, golden-ratio jitter, filtermul = iscale/(roi.scale·wd));
//   - GRAIN_LIGHTNESS_STRENGTH_SCALE = 0.15 (:43).
//
// DOMAIN ADAPTATION (research §8.4): dt injects on Lab L through the
// paper_resp 128² LUT; Lightamer injects on the LINEAR Rec2020 luma
// (0.2627/0.6780/0.0593) with the ANALYTIC paper-response envelope
// (DECISIONS D-08-2-2 — the LUT stores a Lab-L delta for a fixed ±0.5
// exposure probe, which does not translate; the analytic envelope is the
// same sigmoid's slope = "the greater the bias, the more pronounced the
// fall off of the grain in shadows and highlights", grain.c:552):
//   δ(mb) = 2.0·exp((mb/100)·ln 1e-4)          (:331-345 constants)
//   u(l)  = −ln((1+2δ)/(l+δ) − 1)·(1+2δ)/(4γ) + 0.5   (paper_resp_inverse)
//   resp(l) = 4γ·eᶻ/(1+eᶻ)²,  z = 4γ(0.5−u)/(1+2δ)    (paper_resp')
//   out.rgb = in.rgb + noise·(strength/100)·0.15·resp(luma)
// Equal delta on R,G,B — luminance grain, zero chroma noise (dt's
// out[0]-only injection :494 is the same contract in Lab).
//
// DETERMINISM: the noise field is a pure function of (coords, seed) —
// no RNG state, no atomics; same input bytes → same output bytes (the
// cache-key double assertion's hard premise).
// ─────────────────────────────────────────────────────────────────────────

// grain.c:123-136 — the 12 simplex gradient directions.
static constant int grad3[12][3] = {
    { 1, 1, 0 },  { -1, 1, 0 },  { 1, -1, 0 },  { -1, -1, 0 },
    { 1, 0, 1 },  { -1, 0, 1 },  { 1, 0, -1 },  { -1, 0, -1 },
    { 0, 1, 1 },  { 0, -1, 1 },  { 0, 1, -1 },  { 0, -1, -1 }
};

// grain.c:139-166 — the Bernstein permutation table (Gustavson simplex).
static constant int grain_permutation[256] = {
    151, 160, 137, 91,  90,  15,  131, 13,  201, 95,  96,  53,  194, 233, 7,   225,
    140, 36,  103, 30,  69,  142, 8,   99,  37,  240, 21,  10,  23,  190, 6,   148,
    247, 120, 234, 75,  0,   26,  197, 62,  94,  252, 219, 203, 117, 35,  11,  32,
    57,  177, 33,  88,  237, 149, 56,  87,  174, 20,  125, 136, 171, 168, 68,  175,
    74,  165, 71,  134, 139, 48,  27,  166, 77,  146, 158, 231, 83,  111, 229, 122,
    60,  211, 133, 230, 220, 105, 92,  41,  55,  46,  245, 40,  244, 102, 143, 54,
    65,  25,  63,  161, 1,   216, 80,  73,  209, 76,  132, 187, 208, 89,  18,  169,
    200, 196, 135, 130, 116, 188, 159, 86,  164, 100, 109, 198, 173, 186, 3,   64,
    52,  217, 226, 250, 124, 123, 5,   202, 38,  147, 118, 126, 255, 82,  85,  212,
    207, 206, 59,  227, 47,  16,  58,  17,  182, 189, 28,  42,  223, 183, 170, 213,
    119, 248, 152, 2,   44,  154, 163, 70,  221, 153, 101, 155, 167, 43,  172, 9,
    129, 22,  39,  253, 19,  98,  108, 110, 79,  113, 224, 232, 178, 185, 112, 104,
    218, 246, 97,  228, 251, 34,  242, 193, 238, 210, 144, 12,  191, 179, 162, 241,
    81,  51,  145, 235, 249, 14,  239, 107, 49,  192, 214, 31,  181, 199, 106, 157,
    184, 84,  204, 176, 115, 121, 50,  45,  127, 4,   150, 254, 138, 236, 205, 93,
    222, 114, 67,  29,  24,  72,  243, 141, 128, 195, 78,  66,  215, 61,  156, 180
};

// grain.c:168-178 — perm[512] collapses to `grain_permutation[i & 255]`
// (the 512-entry table is the double-range indexing trick; the & 255
// spelling below is value-identical for every index the noise visits).

// grain.c:186-189 — FASTFLOOR (truncation, NOT floor for negatives).
static inline int grainFastFloor(float x) {
    return x > 0.0f ? (int)x : (int)x - 1;
}

static inline float grainDot(int gi, float x, float y, float z) {
    return (float)grad3[gi][0] * x + (float)grad3[gi][1] * y + (float)grad3[gi][2] * z;
}

// grain.c:191-327 — the 3D simplex noise, VERBATIM (float spelling).
static inline float grainSimplexNoise(float xin, float yin, float zin) {
    const float F3 = 1.0f / 3.0f;
    const float G3 = 1.0f / 6.0f;
    const float s = (xin + yin + zin) * F3;
    const int i = grainFastFloor(xin + s);
    const int j = grainFastFloor(yin + s);
    const int k = grainFastFloor(zin + s);
    const float t = (float)(i + j + k) * G3;
    const float X0 = (float)i - t;
    const float Y0 = (float)j - t;
    const float Z0 = (float)k - t;
    const float x0 = xin - X0;
    const float y0 = yin - Y0;
    const float z0 = zin - Z0;

    int i1, j1, k1, i2, j2, k2;
    if (x0 >= y0) {
        if (y0 >= z0) {
            i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0; // X Y Z order
        } else if (x0 >= z0) {
            i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1; // X Z Y order
        } else {
            i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1; // Z X Y order
        }
    } else {
        if (y0 < z0) {
            i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1; // Z Y X order
        } else if (x0 < z0) {
            i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1; // Y Z X order
        } else {
            i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0; // Y X Z order
        }
    }

    const float x1 = x0 - (float)i1 + G3;
    const float y1 = y0 - (float)j1 + G3;
    const float z1 = z0 - (float)k1 + G3;
    const float x2 = x0 - (float)i2 + 2.0f * G3;
    const float y2 = y0 - (float)j2 + 2.0f * G3;
    const float z2 = z0 - (float)k2 + 2.0f * G3;
    const float x3 = x0 - 1.0f + 3.0f * G3;
    const float y3 = y0 - 1.0f + 3.0f * G3;
    const float z3 = z0 - 1.0f + 3.0f * G3;

    // The perm_mod[ii + …] lookups with & 255 (value-identical to the
    // 512-entry tables — see the note above).
    const int ii = i & 255;
    const int jj = j & 255;
    const int kk = k & 255;
    const int gi0 = grain_permutation[(ii + grain_permutation[(jj + grain_permutation[kk]) & 255]) & 255] % 12;
    const int gi1 = grain_permutation[(ii + i1 + grain_permutation[(jj + j1 + grain_permutation[(kk + k1) & 255]) & 255]) & 255] % 12;
    const int gi2 = grain_permutation[(ii + i2 + grain_permutation[(jj + j2 + grain_permutation[(kk + k2) & 255]) & 255]) & 255] % 12;
    const int gi3 = grain_permutation[(ii + 1 + grain_permutation[(jj + 1 + grain_permutation[(kk + 1) & 255]) & 255]) & 255] % 12;

    float n0 = 0.0f, n1 = 0.0f, n2 = 0.0f, n3 = 0.0f;
    float t0 = 0.6f - x0 * x0 - y0 * y0 - z0 * z0;
    if (t0 > 0.0f) { t0 *= t0; n0 = t0 * t0 * grainDot(gi0, x0, y0, z0); }
    float t1 = 0.6f - x1 * x1 - y1 * y1 - z1 * z1;
    if (t1 > 0.0f) { t1 *= t1; n1 = t1 * t1 * grainDot(gi1, x1, y1, z1); }
    float t2 = 0.6f - x2 * x2 - y2 * y2 - z2 * z2;
    if (t2 > 0.0f) { t2 *= t2; n2 = t2 * t2 * grainDot(gi2, x2, y2, z2); }
    float t3 = 0.6f - x3 * x3 - y3 * y3 - z3 * z3;
    if (t3 > 0.0f) { t3 *= t3; n3 = t3 * t3 * grainDot(gi3, x3, y3, z3); }

    // :312 — "scaled to stay just inside [-1,1]".
    return 32.0f * (n0 + n1 + n2 + n3);
}

// grain.c:292-307 — the 3-octave spectrum (f/a tables VERBATIM; the
// octave index rides the noise's z; frequency division by zoom). The seed
// offset rides POST-scale in lattice-cell units (DECISIONS D-08-2-3: dt
// adds its filename hash pre-scale, which at float32 would push the noise
// coordinate to ~1e6 — ulp 0.06 lattice cells destroys the fractional
// split; the post-scale spelling bounds the coordinate at ~4e3 — ulp
// 2.4e-4 — with an identical re-roll purpose and spectrum).
static inline float grainSimplex2D(float x, float y, float zoom, float offset) {
    const float f[3] = { 0.4910f, 0.9441f, 1.7280f };
    const float a[3] = { 0.2340f, 0.7850f, 1.2150f };
    float total = 0.0f;
    for (int octave = 0; octave < 3; octave++) {
        total += grainSimplexNoise(x * f[octave] / zoom + offset, y * f[octave] / zoom, (float)octave) * a[octave];
    }
    return total;
}

// The analytic paper-response envelope (see the header; constants
// GRAIN_LUT_DELTA_MAX 2.0 / DELTA_MIN 0.0001 / PAPER_GAMMA 1.0, :43-46).
static inline float grainRespCurve(float luma, float midtonesBias, float gamma) {
    const float delta = 2.0f * exp((midtonesBias / 100.0f) * log(0.0001f));
    // Domain guard: paper_resp_inverse needs (1+2δ)/(l+δ) − 1 > 0, i.e.
    // l < 1+δ. HDR luma beyond the paper domain saturates the envelope at
    // the white-edge value (DECISIONS D-08-2-2).
    const float l = clamp(luma, 1.0e-6f, (1.0f + delta) * (1.0f - 1.0e-6f));
    const float u = -log((1.0f + 2.0f * delta) / (l + delta) - 1.0f) * (1.0f + 2.0f * delta) / (4.0f * gamma) + 0.5f;
    const float z = 4.0f * gamma * (0.5f - u) / (1.0f + 2.0f * delta);
    const float e = exp(z);
    return 4.0f * gamma * e / ((1.0f + e) * (1.0f + e));
}

struct GrainUniforms {
    float zoom;        // (1 + 8·scale/100)/800 (grain.c:450)
    float strength;    // strength/100 (grain.c:477)
    float midtonesBias;
    float gamma;       // GRAIN_LUT_PAPER_GAMMA (1.0)
    float offset;      // the seed-derived pattern offset (replaces :444 hash)
    float invScaleWd;  // 1/(roi.scale·wd) — x = (roi.x+gid)·invScaleWd
    float filtermul;   // iscale/(roi.scale·wd) (grain.c:487)
    float pad0;
    int filter;        // |roi.scale − 1| > 0.01 (grain.c:484)
    int roiX;
    int roiY;
    int pad1;
};

kernel void grain_apply(
    texture2d<float, access::read>  in  [[texture(0)]],
    texture2d<float, access::write> out [[texture(1)]],
    constant GrainUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)out.get_width() || gid.y >= (uint)out.get_height()) return;

    // grain.c:489-506 — resolution-independent coordinates (shorter side
    // normalized).
    const float x = (float)((int)gid.x + u.roiX) * u.invScaleWd;
    const float y = (float)((int)gid.y + u.roiY) * u.invScaleWd;

    float noise;
    if (u.filter != 0) {
        // grain.c:492-503 — the rank-1 lattice downsampling (21 taps).
        const float fib1div2 = 34.0f / 21.0f;
        const float fib2inv = 1.0f / 21.0f;
        noise = 0.0f;
        for (int l = 0; l < 21; l++) {
            const float px = (float)l / 21.0f;
            float py = (float)l * fib1div2;
            py -= (float)(int)py;
            noise += fib2inv * grainSimplex2D(x + px * u.filtermul, y + py * u.filtermul, u.zoom, u.offset);
        }
    } else {
        noise = grainSimplex2D(x, y, u.zoom, u.offset);
    }

    const float4 pixel = in.read(gid);
    // Rec2020 linear luma (the plan's domain adaptation — research §8.4).
    const float luma = 0.2627f * pixel.x + 0.6780f * pixel.y + 0.0593f * pixel.z;
    const float delta = noise * u.strength * 0.15f * grainRespCurve(luma, u.midtonesBias, u.gamma);
    // Equal delta on R,G,B — luminance grain (the out[0]-only contract).
    out.write(float4(pixel.xyz + delta, pixel.w), gid);
}
