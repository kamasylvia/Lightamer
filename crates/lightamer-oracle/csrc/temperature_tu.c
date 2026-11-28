// SPDX-License-Identifier: GPL-3.0-or-later
// Glue: includes the shim plus the verbatim temperature fragments in
// dependency order (leaf statics before their callers). Upstream callback
// names collide across modules (every iop defines `process`), so the
// common names are macro-renamed to temperature_* before the verbatim
// includes; the .inc bytes stay untouched. `dt_dev_prepare_piece_cfa` is
// NOT included here (the hotpixels TU already defines it once).
#include "dt_shim.h"

#include <lcms2.h>

#include "temperature_simd.inc"
#include "temperature_colormatrix.inc"
#include "temperature_isnormal.inc"
#include "temperature_fcn.inc"
#include "temperature_d65.inc"
#include "temperature_cie_tables.inc"
#include "pipe_type_enum.inc"
#include "temperature_preview_pred.inc"
#include "temperature_defs.inc"
#include "temperature_types.inc"
#include "temperature_array.inc"
#include "temperature_matrices.inc"
#include "temperature_matrix_pred.inc"

#define process temperature_process
#define commit_params temperature_commit_params
#define init_pipe temperature_init_pipe
#define cleanup_pipe temperature_cleanup_pipe
#include "temperature_spectrum.inc"
#include "temperature_convert.inc"
#include "temperature_process.inc"
#include "temperature_commit.inc"
#include "temperature_pipe.inc"
#include "temperature_ignore.inc"
#include "temperature_coeffs.inc"
#undef process
#undef commit_params
#undef init_pipe
#undef cleanup_pipe

// --- test entries (glue, in-TU because they call file-static upstream
// functions): a minimal module+dev from facts, then one conversion each ---
#include "oracle_abi.h"

static void fill_test_image(dt_image_t *img, const oracle_temp_facts *facts)
{
  memset(img, 0, sizeof(*img));
  img->flags = facts->base.flags;
  img->id = facts->base.id;
  memcpy(img->wb_coeffs, facts->wb, sizeof(img->wb_coeffs));
  for(int k = 0; k < 9; k++) img->d65_color_matrix[k] = (float)NAN;
  if(facts->has_xyz)
  {
    for(int k = 0; k < 3; k++)
      for(int i = 0; i < 3; i++) img->adobe_XYZ_to_CAM[k][i] = facts->xyz_to_cam[k * 3 + i];
  }
  else
  {
    img->adobe_XYZ_to_CAM[0][0] = (float)NAN;
  }
  }

static void free_gui(dt_iop_temperature_gui_data_t *gui)
{
  free(gui);
}

int oracle_temperature_find_coeffs(const oracle_temp_facts *facts, double coeffs_out[4])
{
  dt_develop_t dev;
  dt_iop_module_t module;
  memset(&dev, 0, sizeof(dev));
  memset(&module, 0, sizeof(module));
  fill_test_image(&dev.image_storage, facts);
  module.dev = &dev;
  _find_coeffs(&module, coeffs_out);
  return 0;
}

int oracle_temperature_bogus(const oracle_temp_facts *facts, double bwb_out[4])
{
  dt_develop_t dev;
  dt_iop_module_t module;
  memset(&dev, 0, sizeof(dev));
  memset(&module, 0, sizeof(module));
  fill_test_image(&dev.image_storage, facts);
  module.dev = &dev;
  // Upstream polarity: FALSE (0) = matrix found and used, TRUE = unsupported.
  return (int)_calculate_bogus_daylight_wb(&module, bwb_out);
}

static dt_iop_temperature_gui_data_t *make_gui(dt_develop_t *dev, dt_iop_module_t *module,
                                               const oracle_temp_facts *facts)
{
  memset(dev, 0, sizeof(*dev));
  memset(module, 0, sizeof(*module));
  fill_test_image(&dev->image_storage, facts);
  module->dev = dev;
  dt_iop_temperature_gui_data_t *gui = calloc(1, sizeof(*gui));
  if(gui)
  {
    module->gui_data = gui;
    _prepare_matrices(module);
  }
  return gui;
}

int oracle_temperature_temp2mul(const oracle_temp_facts *facts, double temp, double tint,
                                double mul_out[4])
{
  dt_develop_t dev;
  dt_iop_module_t module;
  dt_iop_temperature_gui_data_t *gui = make_gui(&dev, &module, facts);
  if(!gui) return 4;
  _temp2mul(&module, temp, tint, mul_out);
  free_gui(gui);
  return 0;
}

int oracle_temperature_mul2temp(const oracle_temp_facts *facts, float red, float green,
                                float blue, float various, float *temp_out, float *tint_out)
{
  dt_develop_t dev;
  dt_iop_module_t module;
  dt_iop_temperature_gui_data_t *gui = make_gui(&dev, &module, facts);
  if(!gui) return 4;
  dt_iop_temperature_params_t params;
  params.red = red;
  params.green = green;
  params.blue = blue;
  params.various = various;
  params.preset = DT_IOP_TEMP_UNKNOWN;
  _mul2temp(&module, &params, temp_out, tint_out);
  free_gui(gui);
  return 0;
}

int oracle_temperature_tint_xyz(double temp, double tint, double xyz_out[3])
{
  cmsCIEXYZ xyz = _temperature_tint_to_XYZ(temp, tint);
  xyz_out[0] = xyz.X;
  xyz_out[1] = xyz.Y;
  xyz_out[2] = xyz.Z;
  return 0;
}
