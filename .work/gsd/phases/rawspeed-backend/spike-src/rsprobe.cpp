// rsprobe — T1 acceptance probe: decode a RAW via rawspeed and print the technical set.
//
// usage: rsprobe <cameras.xml> <file> [--bench N]
//
// Fields: decoder class, make/model/canonical, dims/crop, cpp/bpp, CFA, black
// levels, white point, as-shot WB, colour matrix, plus the cropped-plane hash
// (FNV-1a 64 over little-endian uint16, the cross-decoder anchor) and timings.

#include "RawSpeed-API.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <typeinfo>

using namespace rawspeed;

static double msSince(std::chrono::steady_clock::time_point t0) {
  return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: %s <cameras.xml> <file> [--bench N]\n", argv[0]);
    return 2;
  }
  int benchN = 1;
  for (int i = 3; i < argc; ++i)
    if (!std::strcmp(argv[i], "--bench") && i + 1 < argc) benchN = std::atoi(argv[++i]);

  try {
    CameraMetaData meta(argv[1]);
    FileReader f(argv[2]);
    auto t0 = std::chrono::steady_clock::now();
    auto [storage, buf] = f.readFile();
    const double readMs = msSince(t0);

    double decodeMs = 0;
    uint64_t hash = 0;
    for (int it = 0; it < benchN; ++it) {
      RawParser parser(buf);
      auto decoder = parser.getDecoder(&meta);
      if (!decoder) { std::fprintf(stderr, "no decoder\n"); return 1; }
      decoder->failOnUnknown = true;
      decoder->checkSupport(&meta);
      t0 = std::chrono::steady_clock::now();
      decoder->decodeRaw();
      decodeMs = msSince(t0);
      decoder->decodeMetaData(&meta);
      RawImage raw = decoder->mRaw;
      RawImageData* r = raw.get();

      if (it == 0) {
        const auto plane = r->getU16DataAsCroppedArray2DRef();
        uint64_t h = 0xcbf29ce484222325ULL;
        for (int y = 0; y < plane.croppedHeight; ++y)
          for (int x = 0; x < plane.croppedWidth; ++x) {
            const uint16_t v = plane(y, x);
            h ^= uint64_t(v & 0xFF); h *= 0x100000001b3ULL;
            h ^= uint64_t(v >> 8);   h *= 0x100000001b3ULL;
          }
        hash = h;

        const auto& md = r->metadata;
        std::printf("decoder_class: %s\n", typeid(*decoder).name());
        std::printf("make: %s\nmodel: %s\n", md.make.c_str(), md.model.c_str());
        std::printf("canonical_make: %s\ncanonical_model: %s\ncanonical_alias: %s\n",
                    md.canonical_make.c_str(), md.canonical_model.c_str(), md.canonical_alias.c_str());
        std::printf("mode: %s\n", md.mode.c_str());
        const auto un = r->getUncroppedDim();
        const auto off = r->getCropOffset();
        std::printf("dim_uncropped: %dx%d\n", un.x, un.y);
        std::printf("dim_cropped: %dx%d\n", r->dim.x, r->dim.y);
        std::printf("crop_offset: %d,%d\n", off.x, off.y);
        std::printf("crop_right_bottom: %d,%d\n", un.x - r->dim.x - off.x, un.y - r->dim.y - off.y);
        std::printf("pitch_bytes: %d\n", r->pitch);
        std::printf("cpp: %u\nbpp: %u\ndata_type: %s\n", r->getCpp(), r->getBpp(),
                    r->getDataType() == RawImageType::UINT16 ? "UINT16" : "F32");
        std::printf("is_cfa: %d\n", r->isCFA ? 1 : 0);
        std::printf("cfa_dcraw_filter: %u (0x%x)\n", r->cfa.getDcrawFilter(), r->cfa.getDcrawFilter());
        std::printf("cfa_pattern_2x2: %d%d%d%d\n", int(r->cfa.getColorAt(0, 0)),
                    int(r->cfa.getColorAt(1, 0)), int(r->cfa.getColorAt(0, 1)),
                    int(r->cfa.getColorAt(1, 1)));
        std::printf("black_level: %d\n", r->blackLevel);
        if (r->blackLevelSeparate) {
          const auto b = *r->blackLevelSeparate;
          std::printf("black_level_separate: 2x2 %d %d %d %d\n", b(0, 0), b(0, 1), b(1, 0), b(1, 1));
        }
        if (r->whitePoint) std::printf("white_point: %d\n", *r->whitePoint);
        if (md.wbCoeffs) {
          const auto& w = *md.wbCoeffs;
          std::printf("wb_coeffs: %f %f %f %f\n", w[0], w[1], w[2], w[3]);
        }
        std::printf("color_matrix_entries: %zu\n", md.colorMatrix.size());
        for (int row = 0; row < 3 && md.colorMatrix.size() == 9; ++row)
          std::printf("color_matrix_row%d: %d/%d %d/%d %d/%d\n", row,
                      md.colorMatrix[row * 3].num, md.colorMatrix[row * 3].den,
                      md.colorMatrix[row * 3 + 1].num, md.colorMatrix[row * 3 + 1].den,
                      md.colorMatrix[row * 3 + 2].num, md.colorMatrix[row * 3 + 2].den);
        std::printf("mosaic_first8:");
        for (int x = 0; x < 8; ++x) std::printf(" %u", plane(0, x));
        std::printf("\n");
        std::printf("mosaic_fnv1a64_cropped: 0x%016llx\n", (unsigned long long)hash);
      }
    }
    std::printf("pass_read_ms: %.3f\npass_decode_ms: %.3f\n", readMs, decodeMs);
    return 0;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "ERROR: %s\n", e.what());
    return 1;
  }
}
