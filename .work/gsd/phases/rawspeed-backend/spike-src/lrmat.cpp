// lrmat — independent colour-matrix direction check for issue #24 (rerun).
//
// The spike writes rawspeed's `metadata.colorMatrix` VERBATIM as DNG
// ColorMatrix1 and calls that value "XYZ->camera". This probe cross-checks the
// direction WITHOUT trusting CIRAW's rendering response:
//
//   LibRaw exposes `cam_xyz` (dcraw convention: XYZ -> camera) and `rgb_cam`
//   (camera -> linear sRGB). If rgb_cam * cam_xyz equals the published
//   XYZ(D65) -> linear sRGB matrix, cam_xyz is XYZ->camera by construction.
//   Comparing cam_xyz with rawspeed's matrix then settles the direction.
//
// Build: c++ -std=c++20 -O2 -arch arm64 -I/opt/homebrew/include lrmat.cpp \
//          -o bin/lrmat -L/opt/homebrew/lib -lraw
// Run:   bin/lrmat samples/7RM5-LosslessCompressedLarge.ARW
#include <libraw/libraw.h>

#include <cmath>
#include <cstdio>

int main(int argc, char **argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: lrmat <raw>\n");
        return 2;
    }
    LibRaw raw;
    if (raw.open_file(argv[1]) != LIBRAW_SUCCESS) {
        std::fprintf(stderr, "open_file failed\n");
        return 3;
    }
    if (raw.unpack() != LIBRAW_SUCCESS) {
        std::fprintf(stderr, "unpack failed\n");
        return 4;
    }
    const auto &c = raw.imgdata.color;
    std::printf("make=%s model=%s\n", raw.imgdata.idata.make, raw.imgdata.idata.model);
    std::printf("libraw cam_xyz (dcraw: XYZ->camera):\n");
    for (int i = 0; i < 3; ++i)
        std::printf("  %.6f %.6f %.6f\n", c.cam_xyz[i][0], c.cam_xyz[i][1], c.cam_xyz[i][2]);
    std::printf("libraw rgb_cam (camera->linear sRGB):\n");
    for (int i = 0; i < 3; ++i)
        std::printf("  %.6f %.6f %.6f (4th %.6f)\n", c.rgb_cam[i][0], c.rgb_cam[i][1],
                    c.rgb_cam[i][2], c.rgb_cam[i][3]);

    // Direction proof (LibRaw cam_xyz_coeff shape): cam_xyz is XYZ->camera
    // (rows camera, cols XYZ). Compose it with the sRGB->XYZ matrix
    // (rgb2xyz, rows XYZ, cols RGB), normalise each row so the camera's
    // response to white RGB is 1, invert -> camera->linear sRGB. That must
    // equal LibRaw's own rgb_cam; it only can if cam_xyz is XYZ->camera.
    const double rgb2xyz[3][3] = {{0.4124564, 0.3575761, 0.1804375},
                                  {0.2126729, 0.7151522, 0.0721750},
                                  {0.0193339, 0.1191920, 0.9503041}};
    double cam_rgb[3][3];
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j) {
            cam_rgb[i][j] = 0;
            for (int k = 0; k < 3; ++k)
                cam_rgb[i][j] += double(c.cam_xyz[i][k]) * rgb2xyz[k][j];
        }
    for (int i = 0; i < 3; ++i) {
        const double rowSum = cam_rgb[i][0] + cam_rgb[i][1] + cam_rgb[i][2];
        for (int j = 0; j < 3; ++j) cam_rgb[i][j] /= rowSum;
    }
    double cam_to_rgb[3][3];
    {
        const double(*m)[3] = cam_rgb;
        const double det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
                           m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
                           m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
        cam_to_rgb[0][0] = (m[1][1] * m[2][2] - m[1][2] * m[2][1]) / det;
        cam_to_rgb[0][1] = (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / det;
        cam_to_rgb[0][2] = (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / det;
        cam_to_rgb[1][0] = (m[1][2] * m[2][0] - m[1][0] * m[2][2]) / det;
        cam_to_rgb[1][1] = (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / det;
        cam_to_rgb[1][2] = (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / det;
        cam_to_rgb[2][0] = (m[1][0] * m[2][1] - m[1][1] * m[2][0]) / det;
        cam_to_rgb[2][1] = (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / det;
        cam_to_rgb[2][2] = (m[0][0] * m[1][1] - m[0][1] * m[1][0]) / det;
    }
    double rgbCamDiff = 0;
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j)
            rgbCamDiff = std::fmax(rgbCamDiff,
                                   std::fabs(cam_to_rgb[i][j] - double(c.rgb_cam[i][j])));
    std::printf("check cam_xyz @ rgb2xyz (normalised, inverted) == rgb_cam: max_abs_diff=%.7f\n",
                rgbCamDiff);
    std::printf("=> cam_xyz is XYZ->camera iff the check above converges\n");

    // rawspeed's matrix, verbatim from evidence/t1-a7r5-meta.txt.
    const double rs[3][3] = {{0.82, -0.2976, -0.0719},
                             {-0.4296, 1.2053, 0.2532},
                             {-0.0429, 0.1282, 0.5774}};
    std::printf("rawspeed metadata.colorMatrix vs libraw cam_xyz:\n");
    double rsMax = 0;
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j)
            rsMax = std::fmax(rsMax, std::fabs(rs[i][j] - double(c.cam_xyz[i][j])));
    std::printf("max_abs_diff_rawspeed_vs_cam_xyz=%.6f\n", rsMax);

    // Inverse hypothesis: if rawspeed were camera->XYZ, the DNG verbatim write
    // would be wrong. Compare rawspeed against the inverse of cam_xyz instead.
    double inv[3][3];
    {
        double m[3][3];
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j) m[i][j] = double(c.cam_xyz[i][j]);
        const double det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
                           m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
                           m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
        if (std::fabs(det) > 1e-12) {
            inv[0][0] = (m[1][1] * m[2][2] - m[1][2] * m[2][1]) / det;
            inv[0][1] = (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / det;
            inv[0][2] = (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / det;
            inv[1][0] = (m[1][2] * m[2][0] - m[1][0] * m[2][2]) / det;
            inv[1][1] = (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / det;
            inv[1][2] = (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / det;
            inv[2][0] = (m[1][0] * m[2][1] - m[1][1] * m[2][0]) / det;
            inv[2][1] = (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / det;
            inv[2][2] = (m[0][0] * m[1][1] - m[0][1] * m[1][0]) / det;
            double invMax = 0;
            for (int i = 0; i < 3; ++i)
                for (int j = 0; j < 3; ++j)
                    invMax = std::fmax(invMax, std::fabs(rs[i][j] - inv[i][j]));
            std::printf("max_abs_diff_rawspeed_vs_inverse_cam_xyz=%.6f\n", invMax);
        }
    }
    return 0;
}
