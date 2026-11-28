// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal darktable interface for the oracle: only what the verbatim
// fragments touch. Struct layouts are oracle-local (behavior comes from the
// verbatim logic, not from ABI); enumerator VALUES copy upstream with a
// citation each, since predicates compare against them.
#pragma once

#include <assert.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// --- glib vocabulary (values match glib; only these are used) ---
typedef int gboolean;
#define TRUE 1
#define FALSE 0
// Simple MIN/MAX/CLAMP: every extracted call site passes side-effect-free
// arguments, so these evaluate identically to glib's statement-expression
// forms (upstream src/common/darktable.h relies on glib.h).
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define CLAMP(x, low, high) (((x) > (high)) ? (high) : (((x) < (low)) ? (low) : (x)))

typedef struct _GList GList;
struct _GList
{
  void *data;
  GList *next;
  GList *prev;
};

// --- gettext no-ops (oracle runs the C locale) ---
#define _(String) (String)
#define C_(Context, String) (String)

// --- OpenMP off: matches a no-OpenMP upstream build, where
// DT_OMP_PRAGMA is empty (src/common/darktable.h). Pixel math identical,
// single-threaded.
#define DT_OMP_FOR(clauses)
#define DT_OMP_FOR_SIMD(clauses)
// Matches a no-OpenMP upstream build too (`src/common/darktable.h`): the
// SIMD-hint macro expands to nothing, like the loop macros above.
#define DT_OMP_DECLARE_SIMD(...)

// --- gtk vocabulary: widget is always NULL, guarded by `if(self->widget)` ---
typedef void GtkWidget;
typedef void GtkToggleButton;
typedef void GtkLabel;

// Opaque upstream struct, value field of the temperature gui-data type:
// oracle-local size (never read here; only the matrix fields beside it are).
typedef struct
{
  char _opaque[8];
} dt_gui_collapsible_section_t;
#define GTK_STACK(x) ((GtkWidget *)(x))

// --- opaque upstream enums: single dummy values, never inspected ---
typedef enum
{
  DT_DEBUG_ALWAYS = 0
} dt_debug_dummy_t;
typedef enum
{
  DT_IMAGE_CACHE_RELAXED = 0
} dt_cache_dummy_t;
typedef enum
{
  DT_SIGNAL_METADATA_UPDATE = 0
} dt_signal_dummy_t;
#define DT_CONTROL_SIGNAL_RAISE(signal) ((void)0)

// --- image flags (values from src/common/image.h dt_image_flags_t) ---
typedef enum
{
  DT_IMAGE_RAW = 64,
  DT_IMAGE_HDR = 128,
  DT_IMAGE_4BAYER = 16384,
  DT_IMAGE_MONOCHROME = 32768,
  DT_IMAGE_S_RAW = 1 << 17,
  DT_IMAGE_MONOCHROME_BAYER = 1 << 19,
} dt_image_flags_subset_t;

// --- colorspace tag (value from src/common/colorspaces.h:45) ---
typedef enum
{
  IOP_CS_RAW = 0,
} dt_colorspace_subset_t;

// --- buffer types (order from src/develop/format.h dt_iop_buffer_type_t) ---
typedef enum
{
  TYPE_UNKNOWN,
  TYPE_FLOAT,
  TYPE_UINT16,
} dt_iop_buffer_type_t;

typedef float dt_aligned_pixel_t[4]; // src/common/dttypes.h:60

// --- region of interest (shape from src/develop/pixelpipe.h) ---
typedef struct dt_iop_roi_t
{
  int x, y, width, height;
  float scale;
} dt_iop_roi_t;

// --- chain state (shape from src/develop/format.h:35-64) ---
typedef struct dt_iop_buffer_dsc_t
{
  unsigned int channels;
  dt_iop_buffer_type_t datatype;
  uint32_t filters;
  uint8_t xtrans[6][6];

  struct
  {
    uint16_t raw_black_level;
    uint16_t raw_white_point;
  } rawprepare;

  struct
  {
    gboolean enabled;
    dt_aligned_pixel_t coeffs;
  } temperature;

  dt_aligned_pixel_t processed_maximum;

  int cst;
} dt_iop_buffer_dsc_t;

typedef int32_t dt_imgid_t; // src/common/darktable.h:165
typedef void dt_iop_params_t; // src/develop/pixelpipe.h:120

// --- image facts (subset of dt_image_t, src/common/image.h): exactly the
// fields the extracted fragments read or write ---
typedef struct dt_image_t
{
  int32_t width, height;
  int32_t p_width, p_height;
  int32_t crop_x, crop_y;
  int32_t crop_right, crop_bottom;
  int32_t flags;
  dt_imgid_t id;
  dt_iop_buffer_dsc_t buf_dsc;
  uint16_t raw_black_level_separate[4];
  uint32_t raw_white_point;
  GList *dng_gain_maps;
  dt_aligned_pixel_t wb_coeffs; // as-shot white balance (temperature)
  float adobe_XYZ_to_CAM[4][3]; // rawspeed color matrix, row 3 zero (temperature)
  float d65_color_matrix[9]; // DNG-embedded 3x3, always invalid here (temperature)
  char camera_maker[64]; // always "" here; the preset loop never runs (temperature)
  char camera_model[64]; // same
  char camera_makermodel[128]; // same (`_ignore_missing_wb` only gates logs)
  char filename[256]; // oracle-local size; always "oracle.arw" (log text only)
  int load_status; // always DT_IMAGEIO_OK (log gate only)
  gboolean camera_missing_sample; // always FALSE (log gate only)
} dt_image_t;

// Load result (values from `dt_imageio_retval_t`, `src/common/image.h:31-41`):
// only the two success values are ever compared here.
typedef enum
{
  DT_IMAGEIO_OK = 0,
  DT_IMAGEIO_CACHE_FULL = 8,
} dt_imageio_retval_subset_t;

// White-balance preset row (`src/common/wb_presets.h`): the store lookup,
// not the table (the table is GUI menu data and stays out).
typedef struct
{
  const char *make;
  const char *model;
  const char *name;
  int tuning;
  double channels[4];
} dt_wb_data;

// --- pipe, piece, module, dev: fields the fragments touch ---
typedef struct dt_dev_pixelpipe_t
{
  dt_image_t image;
  dt_iop_buffer_dsc_t dsc;
  gboolean want_detail_mask;
  int type; // dt_dev_pixelpipe_type_t bits (pipe_type_enum.inc, included by its readers)
} dt_dev_pixelpipe_t;

typedef struct dt_dev_pixelpipe_iop_t
{
  void *data;
  struct dt_dev_pixelpipe_t *pipe;
  struct dt_iop_module_t *module;
  gboolean enabled;
  float iscale;
  int colors;
  dt_iop_roi_t buf_in;
  gboolean process_tiling_ready;
  dt_iop_buffer_dsc_t dsc_in;
  uint32_t filters; // per-piece CFA, derived by dt_dev_prepare_piece_cfa
  uint8_t xtrans[6][6]; // same, X-Trans table
  gboolean process_cl_ready; // cleared for 4Bayer (temperature commit)
} dt_dev_pixelpipe_iop_t;

// White-balance summary (`src/develop/develop.h:154-163`): only the fields
// temperature's commit and processing write (the D65/as-shot doubles live
// in `reload_defaults`, which the oracle never runs).
typedef struct dt_dev_chroma_t
{
  struct dt_iop_module_t *temperature;
  dt_aligned_pixel_t wb_coeffs;
  gboolean late_correction;
} dt_dev_chroma_t;

typedef struct dt_develop_t
{
  dt_image_t image_storage;
  gboolean gui_attached; // always FALSE here; hotpixels short-circuits on NULL gui_data first
  dt_dev_chroma_t chroma; // temperature's commit/processing write here
} dt_develop_t;

typedef struct dt_iop_module_t
{
  struct dt_develop_t *dev;
  void *default_params;
  gboolean hide_enable_button;
  gboolean default_enabled;
  void *widget;
  void *gui_data; // always NULL here; process skips its GUI branch
  int (*input_colorspace)(struct dt_iop_module_t *, struct dt_dev_pixelpipe_t *,
                          struct dt_dev_pixelpipe_iop_t *);
  int (*default_colorspace)(struct dt_iop_module_t *, struct dt_dev_pixelpipe_t *,
                           struct dt_dev_pixelpipe_iop_t *);
} dt_iop_module_t;

// --- verbatim-logic functions, defined in their own translation units ---
gboolean dt_image_is_raw(const dt_image_t *img);
gboolean dt_image_is_mono_sraw(const dt_image_t *img);
gboolean dt_image_is_rawprepare_supported(const dt_image_t *img);
gboolean dt_image_is_matrix_correction_supported(const dt_image_t *img);
uint32_t dt_rawspeed_crop_dcraw_filters(uint32_t filters, uint32_t crop_x, uint32_t crop_y);
void dt_dev_prepare_piece_cfa(dt_dev_pixelpipe_iop_t *piece, const dt_iop_roi_t *roi);
void dt_iop_image_copy_by_size(float *const out, const float *const in, const size_t width,
                               const size_t height, const size_t ch);
extern _Thread_local dt_image_t *oracle_active_image; // registered by the chain before commit
// --- stubs (stubs/stubs.c): pure interfaces, zero upstream logic ---
dt_image_t *dt_image_cache_get(dt_imgid_t imgid, int mode);
void dt_image_cache_write_release(dt_image_t *img, int mode);
void dt_print(int level, const char *fmt, ...);
void dt_control_log(const char *msg, ...);
int dt_wb_presets_count(void);
dt_wb_data *dt_wb_preset(const int k);
int g_str_has_suffix(const char *str, const char *suffix);
void dt_iop_set_module_trouble_message(dt_iop_module_t *self, const char *msg,
                                       const char *tooltip, const char *name);
int dt_dev_write_scharr_mask(dt_dev_pixelpipe_iop_t *piece, float *out,
                             const dt_iop_roi_t *roi_out, gboolean detail);
unsigned int g_list_length(GList *list);
void *g_list_nth_data(GList *list, unsigned int n);
void gtk_stack_set_visible_child_name(void *stack, const char *name);
