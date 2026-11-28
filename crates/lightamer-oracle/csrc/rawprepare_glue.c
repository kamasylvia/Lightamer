// SPDX-License-Identifier: GPL-3.0-or-later
// Glue: scalar fill/read helpers for rawprepare params, so Rust never
// mirrors the C struct layout. Second module = second glue file, same shape.
#include "dt_shim.h"
#include "dng_gainmap_struct.inc"
 #include "rawprepare_types.inc"

void oracle_rawprepare_fill(void *out, int32_t left, int32_t top, int32_t right, int32_t bottom,
                            const uint16_t black[4], uint16_t white, int flat_field)
{
  dt_iop_rawprepare_params_t *p = (dt_iop_rawprepare_params_t *)out;
  p->left = left;
  p->top = top;
  p->right = right;
  p->bottom = bottom;
  for(int i = 0; i < 4; i++) p->raw_black_level_separate[i] = black[i];
  p->raw_white_point = white;
  p->flat_field = flat_field ? FLAT_FIELD_EMBEDDED : FLAT_FIELD_OFF;
}

void oracle_rawprepare_read(const void *in, int32_t crop[4], uint16_t black[4], uint16_t *white,
                            int *flat_field)
{
  const dt_iop_rawprepare_params_t *p = (const dt_iop_rawprepare_params_t *)in;
  crop[0] = p->left;
  crop[1] = p->top;
  crop[2] = p->right;
  crop[3] = p->bottom;
  for(int i = 0; i < 4; i++) black[i] = p->raw_black_level_separate[i];
  *white = p->raw_white_point;
  *flat_field = (p->flat_field == FLAT_FIELD_EMBEDDED) ? 1 : 0;
}

size_t oracle_rawprepare_params_size(void)
{
  return sizeof(dt_iop_rawprepare_params_t);
}
