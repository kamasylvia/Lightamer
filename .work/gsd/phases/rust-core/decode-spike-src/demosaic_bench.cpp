// demosaic_bench — C3 spike: rawspeed decode + baseline demosaic timing.
//
// usage: demosaic_bench <cameras.xml> <file> [--iters N]
// Decodes once via rawspeed, then runs two baseline Bayer demosaic
// implementations (bilinear 3x3, Malvar-He-Cutler 5x5) over the full
// cropped mosaic, reporting per-iteration wall ms (OpenMP parallel,
// default thread count) and a checksum to prevent dead-code elimination.
//
// Rationale: rawspeed ships NO Bayer/X-Trans demosaic (only the Canon
// sRAW YCbCr interpolator in interpolators/Cr2sRawInterpolator.cpp), so
// "each rawspeed demosaic algorithm" is the empty set. These two baselines
// calibrate the timing scale a ported algorithm (RCD/AMaZE from
// darktable src/iop/demosaic.c) must beat.

#include "RawSpeed-API.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <numeric>
#include <vector>

using namespace rawspeed;
using clk = std::chrono::steady_clock;

static double msSince(clk::time_point t0) {
  return std::chrono::duration<double, std::milli>(clk::now() - t0).count();
}

// CFA color ids from rawspeed: 0=R 1=G 2=B (getColorAt). Map cell->color.
static inline int cfaColor(const int cfa[4], int y, int x) {
  return cfa[(y & 1) * 2 + (x & 1)];
}

// --- bilinear 3x3 demosaic, uint16 in -> float RGB out (normalized by white-black)
static void demosaicBilinear(const uint16_t* __restrict__ m, int w, int h, int pitch,
                             const int cfa[4], float black, float scale,
                             float* __restrict__ out) {
  auto P = [&](int y, int x) -> float {
    y = std::clamp(y, 0, h - 1);
    x = std::clamp(x, 0, w - 1);
    return (float(m[size_t(y) * pitch + x]) - black) * scale;
  };
#pragma omp parallel for schedule(static)
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const int c = cfaColor(cfa, y, x);
      float r, g, b;
      if (c == 0) {  // R site
        r = P(y, x);
        g = 0.25f * (P(y - 1, x) + P(y + 1, x) + P(y, x - 1) + P(y, x + 1));
        b = 0.25f * (P(y - 1, x - 1) + P(y - 1, x + 1) + P(y + 1, x - 1) + P(y + 1, x + 1));
      } else if (c == 2) {  // B site
        b = P(y, x);
        g = 0.25f * (P(y - 1, x) + P(y + 1, x) + P(y, x - 1) + P(y, x + 1));
        r = 0.25f * (P(y - 1, x - 1) + P(y - 1, x + 1) + P(y + 1, x - 1) + P(y + 1, x + 1));
      } else {  // G site: neighbors decide R/B orientation via 2x2 pattern
        g = P(y, x);
        const int cLeft = cfaColor(cfa, y, x - 1), cUp = cfaColor(cfa, y - 1, x);
        if (cLeft == 0) {  // R row: R left/right, B up/down
          r = 0.5f * (P(y, x - 1) + P(y, x + 1));
          b = 0.5f * (P(y - 1, x) + P(y + 1, x));
        } else {  // B row
          b = 0.5f * (P(y, x - 1) + P(y, x + 1));
          r = 0.5f * (P(y - 1, x) + P(y + 1, x));
        }
        (void)cUp;
      }
      float* o = out + (size_t(y) * w + x) * 3;
      o[0] = r; o[1] = g; o[2] = b;
    }
  }
}

// --- Malvar-He-Cutler 5x5 gradient-corrected bilinear (G at R/B + R/B at G/R/B)
static void demosaicMHC(const uint16_t* __restrict__ m, int w, int h, int pitch,
                        const int cfa[4], float black, float scale,
                        float* __restrict__ out) {
  auto P = [&](int y, int x) -> float {
    y = std::clamp(y, 0, h - 1);
    x = std::clamp(x, 0, w - 1);
    return (float(m[size_t(y) * pitch + x]) - black) * scale;
  };
#pragma omp parallel for schedule(static)
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const int c = cfaColor(cfa, y, x);
      float r, g, b;
      if (c == 1) {
        g = P(y, x);
        const int cLeft = cfaColor(cfa, y, x - 1);
        // R/B at G: adjacent pair + 2nd-order cross correction
        const float adj_h = 0.5f * (P(y, x - 1) + P(y, x + 1));
        const float adj_v = 0.5f * (P(y - 1, x) + P(y + 1, x));
        const float corr_h = 0.125f * (2 * P(y, x) - P(y, x - 2) - P(y, x + 2));
        const float corr_v = 0.125f * (2 * P(y, x) - P(y - 2, x) - P(y + 2, x));
        if (cLeft == 0) { r = adj_h + corr_h; b = adj_v + corr_v; }
        else { b = adj_h + corr_h; r = adj_v + corr_v; }
      } else {
        // G at R/B site
        const float cross = 0.25f * (P(y - 1, x) + P(y + 1, x) + P(y, x - 1) + P(y, x + 1));
        const float corr = 0.125f * (4 * P(y, x) - P(y - 2, x) - P(y + 2, x) - P(y, x - 2) - P(y, x + 2));
        g = cross + 0.5f * corr;
        // R at B / B at R: diagonal + correction
        const float diag = 0.25f * (P(y - 1, x - 1) + P(y - 1, x + 1) + P(y + 1, x - 1) + P(y + 1, x + 1));
        const float corr2 = 0.125f * (4 * P(y, x)
          - 0.5f * (P(y - 2, x - 2) + P(y - 2, x + 2) + P(y + 2, x - 2) + P(y + 2, x + 2)));
        if (c == 0) { r = P(y, x); b = diag + corr2; }
        else { b = P(y, x); r = diag + corr2; }
      }
      float* o = out + (size_t(y) * w + x) * 3;
      o[0] = r; o[1] = g; o[2] = b;
    }
  }
}

static double median(std::vector<double> v) {
  std::sort(v.begin(), v.end());
  return v[v.size() / 2];
}

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: %s <cameras.xml> <file> [--iters N]\n", argv[0]);
    return 2;
  }
  int iters = 5;
  const char* dumpPath = nullptr;
  for (int i = 3; i < argc; ++i)
    if (!std::strcmp(argv[i], "--iters") && i + 1 < argc) iters = std::atoi(argv[++i]);
    else if (!std::strcmp(argv[i], "--dump") && i + 1 < argc) dumpPath = argv[++i];

  try {
    CameraMetaData meta(argv[1]);
    FileReader f(argv[2]);
    auto t0 = clk::now();
    auto [storage, buf] = f.readFile();
    const double readMs = msSince(t0);
    RawParser parser(buf);
    auto decoder = parser.getDecoder(&meta);
    if (!decoder) { std::fprintf(stderr, "no decoder\n"); return 1; }
    decoder->failOnUnknown = true;
    decoder->checkSupport(&meta);
    t0 = clk::now();
    decoder->decodeRaw();
    const double decodeMs = msSince(t0);
    decoder->decodeMetaData(&meta);
    RawImageData* r = decoder->mRaw.get();
    const int w = r->dim.x, h = r->dim.y;
    const int cfa[4] = {int(r->cfa.getColorAt(0, 0)), int(r->cfa.getColorAt(1, 0)),
                        int(r->cfa.getColorAt(0, 1)), int(r->cfa.getColorAt(1, 1))};
    const float black = float(r->blackLevel);
    const uint32_t white = r->whitePoint.value_or(16383);
    const float scale = 1.0f / float(white - r->blackLevel);
    // contiguous copy of cropped plane (pitch may exceed width)
    std::vector<uint16_t> mosaic(size_t(w) * h);
    {
      const auto plane = r->getU16DataAsCroppedArray2DRef();
      for (int y = 0; y < h; ++y)
        std::memcpy(&mosaic[size_t(y) * w], &plane(y, 0), size_t(w) * 2);
    }
    std::printf("mosaic: %dx%d cfa=%d%d%d%d black=%d white=%u\n", w, h,
                cfa[0], cfa[1], cfa[2], cfa[3], r->blackLevel, white);
    std::printf("read_ms=%.1f decode_ms=%.1f\n", readMs, decodeMs);
    if (r->metadata.wbCoeffs) {
      const auto& wbv = *r->metadata.wbCoeffs;
      std::printf("wb: %.4f %.4f %.4f\n", wbv[0], wbv[1], wbv[2]);
    } else { std::printf("wb: (none)\n"); }
    if (r->metadata.colorMatrix.size() == 9) {
      std::printf("matrix:");
      for (int i = 0; i < 9; ++i) {
        const auto& q = r->metadata.colorMatrix[i];
        std::printf(" %.6f", q.den ? double(q.num) / double(q.den) : 0.0);
      }
      std::printf("\n");
    } else { std::printf("matrix: (none)\n"); }
#ifdef _OPENMP
    std::printf("openmp: yes max_threads=%d\n", omp_get_max_threads());
#else
    std::printf("openmp: no\n");
#endif
    std::vector<float> out(size_t(w) * h * 3);
    std::vector<double> tB, tM;
    double sumB = 0, sumM = 0;
    for (int i = 0; i < iters; ++i) {
      t0 = clk::now();
      demosaicBilinear(mosaic.data(), w, h, w, cfa, black, scale, out.data());
      tB.push_back(msSince(t0));
    }
    for (size_t i = 0; i < out.size(); i += 4096) sumB += out[i];
    for (int i = 0; i < iters; ++i) {
      t0 = clk::now();
      demosaicMHC(mosaic.data(), w, h, w, cfa, black, scale, out.data());
      tM.push_back(msSince(t0));
    }
    for (size_t i = 0; i < out.size(); i += 4096) sumM += out[i];
    std::printf("bilinear_ms:");
    for (double v : tB) std::printf(" %.1f", v);
    std::printf(" median=%.1f checksum=%.6f\n", median(tB), sumB);
    std::printf("mhc5x5_ms:");
    for (double v : tM) std::printf(" %.1f", v);
    std::printf(" median=%.1f checksum=%.6f\n", median(tM), sumM);
    if (dumpPath) {
      FILE* fp = std::fopen(dumpPath, "wb");
      if (!fp) { std::fprintf(stderr, "cannot open dump %s\n", dumpPath); return 1; }
      std::fwrite(out.data(), sizeof(float), out.size(), fp);
      std::fclose(fp);
      std::printf("dump: %s bytes=%zu (float32 RGB, MHC, black-sub+wht-normalized)\n",
                  dumpPath, out.size() * sizeof(float));
    }
    return 0;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
  }
}
