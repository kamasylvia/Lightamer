// rawspeed_shim.h — C ABI over rawspeed for Swift (issue #24 spike).
// One opaque handle per decoded image. No C++ type crosses this boundary.
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rs_image rs_image;

typedef struct rs_error {
    int32_t code;        // 0 = ok; 1 = file/read; 2 = rawspeed; 3 = std; 4 = unsupported
    char message[512];
} rs_error;

typedef struct rs_image_info {
    int32_t width;                  // cropped (active) width
    int32_t height;
    int32_t uncropped_width;
    int32_t uncropped_height;
    int32_t crop_left, crop_top, crop_right, crop_bottom;
    int32_t pitch_elems;             // row pitch of rs_mosaic(), in uint16 elements
    int32_t cpp;
    int32_t bpp;
    int32_t is_cfa;
    int32_t is_xtrans;
    uint32_t cfa_dcraw_filter;
    int32_t cfa_pattern[4];         // [r0c0, r0c1, r1c0, r1c1] colour at each cell
    int32_t black_level;
    int32_t black_level_separate[4];
    int32_t white_level;            // 0 = unknown
    float wb_coeffs[3];             // as-shot R/G/B (rawspeed wbCoeffs, G normalised to 1)
    float color_matrix[9];          // rawspeed `metadata.colorMatrix` VERBATIM (XYZ->camera, D65); identity if absent
    char make[64];
    char model[64];
    int32_t has_color_matrix;
    int32_t has_wb;
} rs_image_info;

// Decode `path`. `cameras_xml` may be NULL to use the compiled-in default path.
rs_image *rs_open(const char *path, const char *cameras_xml, rs_error *err);

// Metadata + mosaic geometry. Pixels live until rs_free.
int32_t rs_fill_info(const rs_image *img, rs_image_info *out, rs_error *err);

// Build an uncompressed CFA DNG from the decoded mosaic, in memory (P1 seam).
// `downsample`: 0 = full, 1 = 1/4 area, 2 = 1/16 area (same-colour box binning).
// Returns 0 on success; `*out_bytes` is malloc'd and must be released with
// rs_free_bytes. The DNG carries rawspeed's colour matrix VERBATIM as
// ColorMatrix1 (see dngwriter.h: the inverse over-exposes by ~3 stops).
int32_t rs_build_dng(const rs_image *img, int32_t downsample,
                     uint8_t **out_bytes, size_t *out_len, rs_error *err);
void rs_free_bytes(uint8_t *bytes);

// Cropped mosaic plane, row-major uint16 samples. Rows are `pitch_elems` apart
// (rawspeed keeps an uncropped pitch); `width` samples per row are valid.
const uint16_t *rs_mosaic(const rs_image *img);

// FNV-1a 64 over the cropped plane, little-endian byte order (cross-decoder anchor).
uint64_t rs_mosaic_hash(const rs_image *img);

void rs_free(rs_image *img);

#ifdef __cplusplus
}
#endif
