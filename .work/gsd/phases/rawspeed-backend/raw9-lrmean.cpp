// lrmean — independent LibRaw channel-mean reference (linear sRGB, camera WB).
#include <libraw/libraw.h>
#include <cstdio>
#include <cmath>
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    LibRaw r;
    if (r.open_file(argv[1]) != LIBRAW_SUCCESS) { std::fprintf(stderr, "open fail\n"); return 3; }
    if (r.unpack() != LIBRAW_SUCCESS) { std::fprintf(stderr, "unpack fail\n"); return 4; }
    auto &p = r.imgdata.params;
    p.output_bps = 16;
    p.output_color = 1;          // sRGB primaries
    p.use_camera_wb = 1;
    p.no_auto_bright = 1;
    p.gamm[0] = 1.0; p.gamm[1] = 1.0;  // linear
    p.user_qual = 3;             // AHD
    p.highlight = 0;             // clip
    if (r.dcraw_process() != LIBRAW_SUCCESS) { std::fprintf(stderr, "process fail\n"); return 5; }
    libraw_processed_image_t *img = r.dcraw_make_mem_image();
    if (!img) { std::fprintf(stderr, "mem image fail\n"); return 6; }
    double s[3] = {0, 0, 0};
    const unsigned short *d = (const unsigned short *)img->data;
    const size_t n = size_t(img->width) * img->height;
    for (size_t i = 0; i < n; ++i) for (int c = 0; c < 3; ++c) s[c] += d[i * 3 + c] / 65535.0;
    std::printf("w=%d h=%d R=%.6f G=%.6f B=%.6f GoverR=%.4f BoverR=%.4f\n",
                img->width, img->height, s[0] / n, s[1] / n, s[2] / n,
                (s[1] / s[0]), (s[2] / s[0]));
    LibRaw::dcraw_clear_mem(img);
    return 0;
}
