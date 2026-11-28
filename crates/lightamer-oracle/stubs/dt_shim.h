// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal darktable interface for the oracle: only what the verbatim
// fragments touch. Struct layouts are oracle-local (behavior comes from the
// verbatim logic, not from ABI); enumerator VALUES copy upstream with a
// citation each, since predicates compare against them.
#pragma once

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

// --- gtk vocabulary: widget is always NULL, guarded by `if(self->widget)` ---
typedef void GtkWidget;
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
} dt_image_flags_subset_t;

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
} dt_image_t;

// --- pipe, piece, module, dev: fields the fragments touch ---
typedef struct dt_dev_pixelpipe_t
{
  dt_image_t image;
  dt_iop_buffer_dsc_t dsc;
  gboolean want_detail_mask;
} dt_dev_pixelpipe_t;

typedef struct dt_dev_pixelpipe_iop_t
{
  void *data;
  struct dt_dev_pixelpipe_t *pipe;
  gboolean enabled;
  float iscale;
  int colors;
  dt_iop_roi_t buf_in;
  gboolean process_tiling_ready;
  dt_iop_buffer_dsc_t dsc_in;
} dt_dev_pixelpipe_iop_t;

typedef struct dt_develop_t
{
  dt_image_t image_storage;
} dt_develop_t;

typedef struct dt_iop_module_t
{
  struct dt_develop_t *dev;
  void *default_params;
  gboolean hide_enable_button;
  gboolean default_enabled;
  void *widget;
} dt_iop_module_t;

// --- verbatim-logic functions, defined in their own translation units ---
gboolean dt_image_is_raw(const dt_image_t *img);
gboolean dt_image_is_mono_sraw(const dt_image_t *img);
gboolean dt_image_is_rawprepare_supported(const dt_image_t *img);
uint32_t dt_rawspeed_crop_dcraw_filters(uint32_t filters, uint32_t crop_x, uint32_t crop_y);
extern _Thread_local dt_image_t *oracle_active_image; // registered by the chain before commit
// --- stubs (stubs/stubs.c): pure interfaces, zero upstream logic ---
dt_image_t *dt_image_cache_get(dt_imgid_t imgid, int mode);
void dt_image_cache_write_release(dt_image_t *img, int mode);
void dt_print(int level, const char *fmt, ...);
void dt_iop_set_module_trouble_message(dt_iop_module_t *self, const char *msg,
                                       const char *tooltip, const char *name);
int dt_dev_write_scharr_mask(dt_dev_pixelpipe_iop_t *piece, float *out,
                             const dt_iop_roi_t *roi_out, gboolean detail);
unsigned int g_list_length(GList *list);
void *g_list_nth_data(GList *list, unsigned int n);
void gtk_stack_set_visible_child_name(void *stack, const char *name);
