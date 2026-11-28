// SPDX-License-Identifier: GPL-3.0-or-later
// Glue: scalar fill for temperature params, so Rust never mirrors the C
// struct layout; plus the roi pair upstream modules inherit when they do
// not implement their own (imageop.c `_iop_modify_roi_out/in`: identity),
// plus an empty reload_defaults (upstream's needs the GUI/dev/history, so
// the oracle never runs it — callers always pass explicit params).
#include "dt_shim.h"

#include "temperature_types.inc"

void oracle_temperature_fill(void *out, float red, float green, float blue,
                             float various, int preset)
{
  dt_iop_temperature_params_t *p = (dt_iop_temperature_params_t *)out;
  p->red = red;
  p->green = green;
  p->blue = blue;
  p->various = various;
  p->preset = preset;
}

size_t oracle_temperature_params_size(void)
{
  return sizeof(dt_iop_temperature_params_t);
}

void temperature_reload_defaults(dt_iop_module_t *self)
{
  (void)self;
}

void temperature_modify_roi_out(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece,
                                dt_iop_roi_t *roi_out, const dt_iop_roi_t *const roi_in)
{
  (void)self;
  (void)piece;
  *roi_out = *roi_in;
}

void temperature_modify_roi_in(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece,
                               const dt_iop_roi_t *const roi_out, dt_iop_roi_t *roi_in)
{
  (void)self;
  (void)piece;
  *roi_in = *roi_out;
}
