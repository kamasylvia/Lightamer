// xcheck — rawspeed vs LibRaw mosaic cross-check (issue #24 T4 correctness leg).
//
// Both decoders produce the sensor-domain mosaic (no black-level subtraction,
// no white balance). We compare the same physical region and report
// max / mean absolute difference and the fraction of differing samples, plus a
// small alignment search so a one-pixel origin mismatch is detected, not
// misread as a decode disagreement.
//
// usage: xcheck <cameras.xml> <file> [--size N]

#include "RawSpeed-API.h"

#include <libraw/libraw.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: %s <cameras.xml> <file> [--size N]\n", argv[0]);
    return 2;
  }
  int size = 512;
  for (int i = 3; i < argc; ++i)
    if (!std::strcmp(argv[i], "--size") && i + 1 < argc) size = std::atoi(argv[++i]);

  // --- rawspeed ---
  int rsW = 0, rsH = 0, rsOffX = 0, rsOffY = 0;
  std::vector<uint16_t> rs;
  try {
    rawspeed::CameraMetaData meta(argv[1]);
    rawspeed::FileReader f(argv[2]);
    auto [storage, buf] = f.readFile();
    rawspeed::RawParser parser(buf);
    auto dec = parser.getDecoder(&meta);
    if (!dec) { std::fprintf(stderr, "rawspeed: no decoder\n"); return 1; }
    dec->failOnUnknown = true;
    dec->checkSupport(&meta);
    dec->decodeRaw();
    dec->decodeMetaData(&meta);
    rawspeed::RawImage raw = dec->mRaw;
    rawspeed::RawImageData* r = raw.get();
    const auto plane = r->getU16DataAsCroppedArray2DRef();
    rsW = plane.croppedWidth;
    rsH = plane.croppedHeight;
    rsOffX = r->getCropOffset().x;
    rsOffY = r->getCropOffset().y;
    rs.resize(size_t(rsW) * rsH);
    for (int y = 0; y < rsH; ++y)
      for (int x = 0; x < rsW; ++x) rs[size_t(y) * rsW + x] = plane(y, x);
  } catch (const std::exception& e) {
    std::fprintf(stderr, "rawspeed: %s\n", e.what());
    return 1;
  }

  // --- LibRaw ---
  LibRaw lr;
  if (lr.open_file(argv[2]) != LIBRAW_SUCCESS || lr.unpack() != LIBRAW_SUCCESS) {
    std::fprintf(stderr, "libraw: open/unpack failed\n");
    return 1;
  }
  const auto& sizes = lr.imgdata.sizes;
  const int lrW = int(sizes.raw_width), lrH = int(sizes.raw_height);
  const uint16_t* lrPix = lr.imgdata.rawdata.raw_image;
  if (!lrPix) { std::fprintf(stderr, "libraw: no raw_image\n"); return 1; }
  const int lrPitch = int(sizes.raw_pitch / 2);

  std::printf("rawspeed: cropped %dx%d offset %d,%d\n", rsW, rsH, rsOffX, rsOffY);
  std::printf("libraw:   raw %dx%d pitch_elems %d\n", lrW, lrH, lrPitch);

  // region in LibRaw coordinates: rawspeed's cropped origin + a centred window
  const int baseX = rsOffX + (rsW - size) / 2;
  const int baseY = rsOffY + (rsH - size) / 2;
  if (baseX < 0 || baseY < 0 || baseX + size > lrW || baseY + size > lrH) {
    std::fprintf(stderr, "region out of range\n");
    return 1;
  }

  auto diffFor = [&](int dx, int dy, double& mean, double& mx, double& frac) {
    long long sum = 0; int m2 = 0; long long n2 = 0;
    for (int y = 0; y < size; ++y)
      for (int x = 0; x < size; ++x) {
        const uint16_t a = rs[size_t(baseY - rsOffY + y) * rsW + (baseX - rsOffX + x)];
        const uint16_t b = lrPix[(baseY + y + dy) * lrPitch + (baseX + x + dx)];
        const int d = std::abs(int(a) - int(b));
        sum += d; if (d > m2) m2 = d; if (d) ++n2;
      }
    mean = double(sum) / double(size) / double(size);
    mx = m2;
    frac = double(n2) / double(size) / double(size);
  };

  double bestMean = 1e18; int bestDx = 0, bestDy = 0;
  for (int dy = -2; dy <= 2; ++dy)
    for (int dx = -2; dx <= 2; ++dx) {
      double mean, mx, frac;
      diffFor(dx, dy, mean, mx, frac);
      if (mean < bestMean) { bestMean = mean; bestDx = dx; bestDy = dy; }
    }
  double mean, mx, frac;
  diffFor(bestDx, bestDy, mean, mx, frac);
  std::printf("region %dx%d at libraw (%d,%d) best_offset %d,%d\n", size, size, baseX, baseY, bestDx, bestDy);
  std::printf("max_abs_diff %.0f\nmean_abs_diff %.4f\nmismatch_fraction %.6f\n", mx, mean, frac);
  return 0;
}
