// SPDX-License-Identifier: GPL-3.0-or-later
// Glue: scalar fill for hotpixels params, so Rust never mirrors the C
// struct layout; plus the roi pair upstream modules inherit when they do
// not implement their own (imageop.c `_iop_modify_roi_out/in`: identity).
#include "dt_shim.h"

#include "hotpixels_types.inc"

void oracle_hotpixels_fill(void *out, float strength, float threshold, int markfixed,
                           int permissive)
{
  dt_iop_hotpixels_params_t *p = (dt_iop_hotpixels_params_t *)out;
  p->strength = strength;
  p->threshold = threshold;
  p->markfixed = markfixed;
  p->permissive = permissive;
}

size_t oracle_hotpixels_params_size(void)
{
  return sizeof(dt_iop_hotpixels_params_t);
}

void hotpixels_modify_roi_out(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece,
                              dt_iop_roi_t *roi_out, const dt_iop_roi_t *const roi_in)
{
  (void)self;
  (void)piece;
  *roi_out = *roi_in;
}

void hotpixels_modify_roi_in(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece,
                             const dt_iop_roi_t *const roi_out, dt_iop_roi_t *roi_in)
{
  (void)self;
  (void)piece;
  *roi_in = *roi_out;
}
