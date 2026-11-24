// lrbench — LibRaw end-to-end timing, used as the P2 CPU-demosaic stand-in.
//
// usage: lrbench <file> [--qual N] [--half] [--iters N] [--json]
//   --qual N : LibRaw user_qual (0 = linear, 11 = AMaZE). Default 0.
//   --half   : LibRaw half_size decode (the preview-resolution mode).
//
// Steps are timed separately (open / unpack / dcraw_process) — explanation
// column only; the conclusion metrics come from the Swift harness.

#include <libraw/libraw.h>

#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>

static double msSince(std::chrono::steady_clock::time_point t0) {
  return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <file> [--qual N] [--half] [--iters N] [--json]\n", argv[0]);
    return 2;
  }
  const char* path = argv[1];
  int qual = 0, iters = 1;
  bool half = false;
  for (int i = 2; i < argc; ++i) {
    if (!std::strcmp(argv[i], "--qual") && i + 1 < argc) qual = std::atoi(argv[++i]);
    else if (!std::strcmp(argv[i], "--half")) half = true;
    else if (!std::strcmp(argv[i], "--iters") && i + 1 < argc) iters = std::atoi(argv[++i]);
  }

  for (int it = 0; it < iters; ++it) {
    auto t0 = std::chrono::steady_clock::now();
    LibRaw raw;
    int rc = raw.open_file(path);
    double tOpen = msSince(t0);
    if (rc != LIBRAW_SUCCESS) {
      std::fprintf(stderr, "open failed: %s\n", libraw_strerror(rc));
      return 1;
    }
    t0 = std::chrono::steady_clock::now();
    rc = raw.unpack();
    double tUnpack = msSince(t0);
    if (rc != LIBRAW_SUCCESS) {
      std::fprintf(stderr, "unpack failed: %s\n", libraw_strerror(rc));
      return 1;
    }
    const int w0 = raw.imgdata.sizes.width, h0 = raw.imgdata.sizes.height;
    raw.imgdata.params.user_qual = qual;
    raw.imgdata.params.half_size = half ? 1 : 0;
    raw.imgdata.params.output_bps = 16;
    raw.imgdata.params.no_auto_bright = 1;
    raw.imgdata.params.use_camera_wb = 1;
    raw.imgdata.params.output_color = 1;  // sRGB
    t0 = std::chrono::steady_clock::now();
    rc = raw.dcraw_process();
    double tProcess = msSince(t0);
    if (rc != LIBRAW_SUCCESS) {
      std::fprintf(stderr, "process failed: %s\n", libraw_strerror(rc));
      return 1;
    }
    int err = 0;
    libraw_processed_image_t* img = raw.dcraw_make_mem_image(&err);
    if (!img) {
      std::fprintf(stderr, "make_mem_image failed\n");
      return 1;
    }
    // cheap checksum so a cached/empty buffer can never pass
    uint64_t h = 0xcbf29ce484222325ULL;
    const unsigned char* p = img->data;
    const size_t n = size_t(img->data_size);
    for (size_t i = 0; i < n; i += 97) { h ^= p[i]; h *= 0x100000001b3ULL; }
    std::printf("lr path=%s qual=%d half=%d raw=%dx%d out=%ux%u open_ms=%.2f unpack_ms=%.2f process_ms=%.2f total_ms=%.2f hash=0x%016llx\n",
                path, qual, half ? 1 : 0, w0, h0, img->width, img->height, tOpen, tUnpack,
                tProcess, tOpen + tUnpack + tProcess, (unsigned long long)h);
    LibRaw::dcraw_clear_mem(img);
    raw.recycle();
  }
  return 0;
}
