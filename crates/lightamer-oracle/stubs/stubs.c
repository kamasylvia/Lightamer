// SPDX-License-Identifier: GPL-3.0-or-later
// Stubs for pure interfaces the verbatim fragments call: allocation-free,
// logic-free. Each states what upstream symbol it stands in for. Behavior
// differences (if any) are listed in README.md "Behavior stubs".
#include "dt_shim.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

// Thread-local: parallel test threads run the chain concurrently, and each
// call only ever touches its own stack image.
_Thread_local dt_image_t *oracle_active_image = NULL;

// Upstream dt_image_cache_get: returns the image from the mipmap cache.
// Oracle: the chain registers its working image; the returned pointer lets
// _image_set_rawcrops land p_width/p_height on it, like upstream's
// image_storage fast path. The database write has no observer here.
dt_image_t *dt_image_cache_get(dt_imgid_t imgid, int mode)
{
  (void)imgid;
  (void)mode;
  return oracle_active_image;
}

// Upstream dt_image_cache_write_release: unlocks + schedules a DB write.
// Oracle: nothing to unlock, nowhere to write.
void dt_image_cache_write_release(dt_image_t *img, int mode)
{
  (void)img;
  (void)mode;
}

// Upstream dt_print: leveled log. Oracle: silent (tests use valid params;
// trouble paths would abort visibly elsewhere first).
void dt_print(int level, const char *fmt, ...)
{
  (void)level;
  (void)fmt;
}

// Upstream dt_iop_set_module_trouble_message: GUI warning badge. Oracle: no GUI.
void dt_iop_set_module_trouble_message(dt_iop_module_t *self, const char *msg,
                                       const char *tooltip, const char *name)
{
  (void)self;
  (void)msg;
  (void)tooltip;
  (void)name;
}

// Upstream dt_dev_write_scharr_mask: detail mask for masked modules.
// Oracle: unreachable by construction (the chain pins want_detail_mask = 0,
// and process is the only caller).
int dt_dev_write_scharr_mask(dt_dev_pixelpipe_iop_t *piece, float *out,
                             const dt_iop_roi_t *roi_out, gboolean detail)
{
  (void)piece;
  (void)out;
  (void)roi_out;
  (void)detail;
  fprintf(stderr, "oracle: scharr mask requested, want_detail_mask must be 0\n");
  abort();
}

// glib g_list_length: NULL walks zero steps, matching glib.
unsigned int g_list_length(GList *list)
{
  unsigned int n = 0;
  while(list)
  {
    n++;
    list = list->next;
  }
  return n;
}

// glib g_list_nth_data: NULL/out-of-range yields NULL, matching glib.
void *g_list_nth_data(GList *list, unsigned int n)
{
  while(list && n--)
    list = list->next;
  return list ? list->data : NULL;
}

// gtk gtk_stack_set_visible_child_name: unreachable (widget is always NULL,
// guarded by `if(self->widget)` in reload_defaults).
void gtk_stack_set_visible_child_name(void *stack, const char *name)
{
  (void)stack;
  (void)name;
  fprintf(stderr, "oracle: gtk reached, widget must be NULL\n");
  abort();
}

// Upstream dt_iop_image_copy_by_size (imagebuf.h:89-99): documents a copy
// and parallelizes it past a threshold; bytes out equal bytes in either
// way. Oracle: the same copy, serial (no OpenMP here, like DT_OMP_FOR).
void dt_iop_image_copy_by_size(float *const out, const float *const in, const size_t width,
                               const size_t height, const size_t ch)
{
  memcpy(out, in, width * height * ch * sizeof(float));
}

// Upstream dt_control_log: GUI toast. Oracle: silent, like dt_print.
void dt_control_log(const char *msg, ...)
{
  (void)msg;
}

// Upstream dt_wb_presets_count: rows in the preset store. Oracle: the store
// (GUI menu data) stays out, so zero; `_find_coeffs` skips straight to the
// hardcoded fallback, which is exactly the camera-less path compared.
int dt_wb_presets_count(void)
{
  return 0;
}

// Upstream dt_wb_preset: k-th store row. Oracle: unreachable (the count
// above is zero, and both callers loop under it).
dt_wb_data *dt_wb_preset(const int k)
{
  (void)k;
  fprintf(stderr, "oracle: wb preset requested, count must be 0\n");
  abort();
}

// glib g_str_has_suffix: same semantics (NULL-safe FALSE, empty suffix
// TRUE), so `_ignore_missing_wb` reads what upstream reads.
int g_str_has_suffix(const char *str, const char *suffix)
{
  if(!str || !suffix) return FALSE;
  const size_t str_len = strlen(str);
  const size_t suffix_len = strlen(suffix);
  if(suffix_len > str_len) return FALSE;
  return strcmp(str + str_len - suffix_len, suffix) == 0 ? TRUE : FALSE;
}
