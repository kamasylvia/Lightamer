// SPDX-License-Identifier: GPL-3.0-or-later
// rs-oracle: independent reference that drives rawspeed's C++ API directly
// (RawParser/RawDecoder, no shim). The Rust parity tests run this binary on
// the same fixtures and compare width/height/black/white/WB/mosaic-hash.
//
// Output: `key=value` lines on stdout, exit 0. On any failure prints
// `error_class=<rawspeed|std|unknown>` + `error_msg=<what()>` and exits 1.
// Floats print with %.9g; hashes print lowercase hex without 0x.

#include "RawSpeed-API.h"

#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>

using namespace rawspeed;

namespace {

void printEscaped(const char* key, const std::string& v) {
  std::printf("%s=", key);
  for (char c : v) {
    if (c == '\n' || c == '\r' || c == '=')
      std::printf("%%%02X", static_cast<unsigned>(static_cast<unsigned char>(c)));
    else
      std::putchar(c);
  }
  std::putchar('\n');
}

uint64_t fnv1aCropped(RawImageData* r) {
  uint64_t h = 14695981039346656037ULL;
  const int w = r->dim.x;
  const int hgt = r->dim.y;
  if (r->getDataType() == RawImageType::UINT16) {
    auto view = r->getU16DataAsCroppedArray2DRef();
    const int pitch = view.getAsArray2DRef().pitch();
    for (int y = 0; y < hgt; ++y) {
      const auto* row = view[y].begin();
      for (int x = 0; x < w; ++x) {
        uint16_t v = row[x];
        h ^= static_cast<uint64_t>(v & 0xFF);
        h *= 1099511628211ULL;
        h ^= static_cast<uint64_t>((v >> 8) & 0xFF);
        h *= 1099511628211ULL;
      }
      (void)pitch;
    }
  } else {
    auto view = r->getF32DataAsCroppedArray2DRef();
    for (int y = 0; y < hgt; ++y) {
      const auto* row = view[y].begin();
      for (int x = 0; x < w; ++x) {
        uint32_t u;
        std::memcpy(&u, &row[x], sizeof(u));
        for (int b = 0; b < 4; ++b) {
          h ^= static_cast<uint64_t>((u >> (8 * b)) & 0xFF);
          h *= 1099511628211ULL;
        }
      }
    }
  }
  return h;
}

int run(const char* path, const char* camerasXml) {
  auto meta = std::make_unique<CameraMetaData>(camerasXml);
  FileReader f(path);
  auto [storage, buf] = f.readFile();
  auto parser = std::make_unique<RawParser>(buf);
  auto decoder = parser->getDecoder(meta.get());
  if (!decoder) {
    std::printf("error_class=rawspeed\nerror_msg=no decoder for file\n");
    return 1;
  }
  decoder->failOnUnknown = true;
  decoder->checkSupport(meta.get());
  decoder->decodeRaw();
  decoder->decodeMetaData(meta.get());
  RawImageData* r = decoder->mRaw.get();

  const RawDecoder& decRef = *decoder;
  printEscaped("decoder", typeid(decRef).name());
  printEscaped("make", r->metadata.make);
  printEscaped("model", r->metadata.model);
  printEscaped("canonical_make", r->metadata.canonical_make);
  printEscaped("canonical_model", r->metadata.canonical_model);
  printEscaped("mode", r->metadata.mode);
  std::printf("width=%d\nheight=%d\n", r->dim.x, r->dim.y);
  const iPoint2D un = r->getUncroppedDim();
  const iPoint2D off = r->getCropOffset();
  std::printf("uncropped_width=%d\nuncropped_height=%d\n", un.x, un.y);
  std::printf("crop_left=%d\ncrop_top=%d\n", off.x, off.y);
  std::printf("crop_right=%d\ncrop_bottom=%d\n", un.x - r->dim.x - off.x,
              un.y - r->dim.y - off.y);
  const bool isU16 = r->getDataType() == RawImageType::UINT16;
  int pitch = 0;
  if (isU16)
    pitch = r->getU16DataAsCroppedArray2DRef().getAsArray2DRef().pitch();
  else
    pitch = r->getF32DataAsCroppedArray2DRef().getAsArray2DRef().pitch();
  std::printf("data_type=%s\n", isU16 ? "u16" : "f32");
  std::printf("pitch_elems=%d\n", pitch);
  std::printf("cpp=%u\nbpp=%u\n", r->getCpp(), r->getBpp());
  std::printf("is_cfa=%d\n", r->isCFA ? 1 : 0);
  const iPoint2D cfaSize = r->cfa.getSize();
  std::printf("cfa_w=%d\ncfa_h=%d\n", cfaSize.x, cfaSize.y);
  std::printf("is_xtrans=%d\n", (cfaSize.x == 6 && cfaSize.y == 6) ? 1 : 0);
  std::printf("dcraw_filter=0x%08X\n", r->cfa.getDcrawFilter());
  std::printf("cfa_pattern=");
  for (int y = 0; y < cfaSize.y; ++y) {
    for (int x = 0; x < cfaSize.x; ++x) {
      if (x + y > 0)
        std::putchar(',');
      std::printf("%d", static_cast<int>(r->cfa.getColorAt(x, y)));
    }
  }
  std::putchar('\n');
  std::printf("black=%d\n", r->blackLevel);
  if (r->blackLevelSeparate) {
    const auto bl = *r->blackLevelSeparate;
    std::printf("black_sep=%d,%d,%d,%d\n", bl[0](0), bl[0](1), bl[1](0),
                bl[1](1));
  } else {
    std::printf("black_sep=none\n");
  }
  if (r->whitePoint)
    std::printf("white=%d\n", *r->whitePoint);
  else
    std::printf("white=none\n");
  if (r->metadata.wbCoeffs) {
    const auto& wb = *r->metadata.wbCoeffs;
    std::printf("wb=%.9g,%.9g,%.9g,%.9g\n", static_cast<double>(wb[0]),
                static_cast<double>(wb[1]), static_cast<double>(wb[2]),
                static_cast<double>(wb[3]));
  } else {
    std::printf("wb=none\n");
  }
  if (r->metadata.colorMatrix.size() == 9) {
    std::printf("matrix=");
    for (int i = 0; i < 9; ++i) {
      if (i > 0)
        std::putchar(',');
      const auto& q = r->metadata.colorMatrix[i];
      double v = q.den ? static_cast<double>(q.num) / static_cast<double>(q.den)
                       : 0.0;
      std::printf("%.9g", v);
    }
    std::putchar('\n');
  } else {
    std::printf("matrix=none\n");
  }
  std::printf("iso=%d\n", r->metadata.isoSpeed);
  std::printf("subsampling=%d,%d\n", r->metadata.subsampling.x,
              r->metadata.subsampling.y);
  std::printf("pixel_aspect=%.9g\n", r->metadata.pixelAspectRatio);
  std::printf("mosaic_hash=%016" PRIx64 "\n", fnv1aCropped(r));
  std::printf("mosaic_bytes=%lld\n",
              static_cast<long long>(r->dim.x) * r->dim.y *
                  (isU16 ? 2 : 4) * static_cast<long long>(r->getCpp()));
  return 0;
}

} // namespace

int main(int argc, char** argv) {
  if (argc != 3) {
    std::fprintf(stderr, "usage: rs-oracle <cameras.xml> <raw-file>\n");
    return 2;
  }
  try {
    return run(argv[2], argv[1]);
  } catch (const RawspeedException& e) {
    std::printf("error_class=rawspeed\nerror_msg=%s\n", e.what());
  } catch (const std::exception& e) {
    std::printf("error_class=std\nerror_msg=%s\n", e.what());
  } catch (...) {
    std::printf("error_class=unknown\nerror_msg=unknown C++ exception\n");
  }
  return 1;
}
