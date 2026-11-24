// rs2dng — rawspeed mosaic -> uncompressed CFA DNG (CLI around dngwriter.h).
//
// usage: rs2dng <cameras.xml> <input> <out.dng> [--downsample N] [--invert-matrix] [--time]
//   --time : build in memory only, print the decode/serialize split (no file write)

#include "RawSpeed-API.h"
#include "dngwriter.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

using namespace rawspeed;

int main(int argc, char** argv) {
  if (argc < 4) {
    std::fprintf(stderr, "usage: %s <cameras.xml> <input> <out.dng> [--downsample N] [--invert-matrix] [--time]\n", argv[0]);
    return 2;
  }
  const char* camfile = argv[1];
  const char* inPath = argv[2];
  const char* outPath = argv[3];
  int downsample = 0;
  bool timeOnly = false, invert = false;
  for (int i = 4; i < argc; ++i) {
    if (!std::strcmp(argv[i], "--downsample") && i + 1 < argc) downsample = std::atoi(argv[++i]);
    else if (!std::strcmp(argv[i], "--time")) timeOnly = true;
    else if (!std::strcmp(argv[i], "--invert-matrix")) invert = true;
  }

  try {
    using clk = std::chrono::steady_clock;
    CameraMetaData meta(camfile);
    FileReader f(inPath);
    auto [storage, buf] = f.readFile();
    RawParser parser(buf);
    auto decoder = parser.getDecoder(&meta);
    if (!decoder) { std::fprintf(stderr, "no decoder\n"); return 1; }
    decoder->failOnUnknown = true;
    decoder->checkSupport(&meta);
    const auto tDec0 = clk::now();
    decoder->decodeRaw();
    const double decodeMs = std::chrono::duration<double, std::milli>(clk::now() - tDec0).count();
    decoder->decodeMetaData(&meta);
    RawImageData* plane = decoder->mRaw.get();

    const auto tSer0 = clk::now();
    rsdng::Result res = rsdng::build(plane, downsample, invert);
    const double serializeMs = std::chrono::duration<double, std::milli>(clk::now() - tSer0).count();

    if (timeOnly) {
      std::printf("time_only: decode_ms=%.2f serialize_ms=%.2f total_ms=%.2f bytes=%zu\n",
                  decodeMs, serializeMs, decodeMs + serializeMs, res.bytes.size());
      return 0;
    }

    FILE* fp = std::fopen(outPath, "wb");
    if (!fp) { std::fprintf(stderr, "cannot open %s\n", outPath); return 1; }
    std::fwrite(res.bytes.data(), 1, res.bytes.size(), fp);
    std::fclose(fp);
    std::printf("wrote %s dim=%dx%d cfa=%d%d%d%d black=%d,%d,%d,%d white=%d bytes=%zu mosaic_fnv=0x%016llx\n",
                outPath, res.width, res.height, res.cfa[0], res.cfa[1], res.cfa[2], res.cfa[3],
                res.black[0], res.black[1], res.black[2], res.black[3], res.white,
                res.bytes.size(), (unsigned long long)res.mosaicFnv);
    return 0;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "ERROR: %s\n", e.what());
  }
  return 1;
}
