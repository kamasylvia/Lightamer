// SPDX-License-Identifier: GPL-3.0-or-later
// rawspeed_shim.h — thin C ABI over rawspeed for lightamer-decode (B2-a).
//
// One opaque handle per decoded image. No C++ type crosses this boundary and
// no C++ exception escapes it: every entry point catches everything and
// reports a stable error code plus a one-line detail message.
//
// The camera database (`cameras.xml`) is parsed once per process: passing
// NULL for `cameras_xml` uses the process-wide singleton built from the
// baked-in default path (see RS_CAMERAS_XML_DEFAULT, set by build.rs).
// A non-NULL path parses a private copy on every call (tests only).
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rs_image rs_image;

// Stable error codes. Mirrored by lightamer_decode::ErrorCode; do not renumber.
enum {
  RS_OK = 0,
  RS_ERR_NOT_FOUND = 1,   // file missing or unreadable
  RS_ERR_NOT_RAW = 2,     // no RAW decoder accepts this file
  RS_ERR_UNKNOWN_CAMERA = 3,
  RS_ERR_TRUNCATED = 4,   // empty, cut short, or out-of-bounds read
  RS_ERR_DECOMPRESS = 5,  // decoder/decompressor failed on readable input
  RS_ERR_NOMEM = 6,
  RS_ERR_UNSUPPORTED_COMPRESSION = 7,
  RS_ERR_THUMB_UNAVAILABLE = 8, // embedded thumbnail absent (Rust layer)
  RS_ERR_INTERNAL = 9           // null handle, misuse, meta-db failure, unknown
};

typedef struct rs_error {
  int32_t code; // RS_OK on success
  char message[512];
} rs_error;

// Mosaic sample type in rs_image_info.data_type.
enum {
  RS_MOSAIC_U16 = 0,
  RS_MOSAIC_F32 = 1,
};

#define RS_CFA_PATTERN_MAX 36 // X-Trans 6x6 is the largest known CFA

typedef struct rs_image_info {
  int32_t data_type; // RS_MOSAIC_U16 or RS_MOSAIC_F32
  int32_t width;     // cropped (active) width
  int32_t height;
  int32_t uncropped_width;
  int32_t uncropped_height;
  int32_t crop_left;
  int32_t crop_top;
  int32_t crop_right;
  int32_t crop_bottom;
  // Row pitch of the cropped plane in SAMPLES of data_type (cpp included).
  // rawspeed keeps the uncropped pitch, so pitch_elems >= width * cpp.
  int32_t pitch_elems;
  int32_t cpp;
  int32_t bpp;
  int32_t is_cfa;
  int32_t is_xtrans; // 6x6 CFA
  int32_t cfa_w;
  int32_t cfa_h;
  // Row-major CFA colors (rawspeed CFAColor values), cfa_valid entries.
  int32_t cfa_pattern[RS_CFA_PATTERN_MAX];
  int32_t cfa_valid; // min(cfa_w * cfa_h, RS_CFA_PATTERN_MAX)
  uint32_t cfa_dcraw_filter;
  int32_t black_level;
  int32_t black_level_separate[4]; // row-major 2x2, valid if has_black_sep
  int32_t has_black_sep;
  int32_t white_level; // valid if has_white
  int32_t has_white;
  float wb_coeffs[4]; // as-shot R/G1/B/G2, valid if has_wb
  int32_t has_wb;
  // rawspeed metadata.colorMatrix VERBATIM: XYZ -> camera-native, D65.
  float color_matrix[9];
  int32_t has_color_matrix;
  int32_t iso_speed; // 0 = unknown
  int32_t subsampling_x;
  int32_t subsampling_y;
  double pixel_aspect_ratio;
  char make[64];
  char model[64];
  char canonical_make[64];
  char canonical_model[64];
  char mode[32];
  char decoder[64]; // demangled decoder class, e.g. "ArwDecoder"
  uint64_t mosaic_bytes; // cropped plane: width*height*cpp*sample_size
} rs_image_info;

// Parse the file, select a decoder, run checkSupport. Pixels are NOT decoded
// yet; call rs_decode next. `cameras_xml` NULL = process singleton.
// Returns NULL on failure with *err set (err may be NULL to ignore detail).
rs_image* rs_open(const char* path, const char* cameras_xml, rs_error* err);

// Run decodeRaw + decodeMetaData. Idempotent: a second call is a no-op
// success. Returns 0 on success, -1 on failure with *err set.
int32_t rs_decode(rs_image* img, rs_error* err);

// Fill metadata + mosaic geometry. Requires a decoded image.
// Returns 0 on success, -1 on failure with *err set.
int32_t rs_fill_info(const rs_image* img, rs_image_info* out, rs_error* err);

// Cropped mosaic plane base. Rows are pitch_elems samples apart; width*cpp
// samples per row are valid. NULL unless decoded with the matching type.
// The pointer borrows from the handle: valid until rs_free, not thread-safe
// to share without external synchronization.
const uint16_t* rs_mosaic_u16(const rs_image* img);
const float* rs_mosaic_f32(const rs_image* img);

// FNV-1a 64 over the cropped plane, little-endian byte order, both types.
// Used as the cross-implementation anchor (oracle vs shim).
uint64_t rs_mosaic_hash(const rs_image* img, rs_error* err);

// Embedded thumbnails (B2-b) live in pure Rust (`thumbnail.rs`): rawspeed at
// the pinned commit exposes no thumbnail API, so the B2-a `rs_thumb` /
// `rs_free_bytes` placeholder pair is removed rather than filled.

void rs_free(rs_image* img); // NULL-safe

// Parse the singleton camera database now (no-op once parsed). Lets callers
// separate meta-parse time from first-decode time. Returns 0/-1 with *err.
int32_t rs_ensure_meta(rs_error* err);

// How many times cameras.xml has been parsed in this process (probe for the
// singleton test: NULL-path opens must not increase it past 1).
uint64_t rs_meta_parse_count(void);

// sizeof(rs_image_info); the Rust side asserts its mirror matches.
size_t rs_info_size(void);

// sizeof(rs_error); same pin for the error slot (M3).
size_t rs_error_size(void);

// Exposed for mapping tests: classify a rawspeed message as rs_open (stage 0)
// or rs_decode (stage 1) would. stage other than 0/1, or NULL msg, yields
// RS_ERR_INTERNAL.
int32_t rs_classify_for_test(int32_t stage, const char* msg);

#ifdef __cplusplus
}
#endif
