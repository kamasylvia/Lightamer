static gboolean _calculate_bogus_daylight_wb(dt_iop_module_t *self, double bwb[4])
{
  if(!dt_image_is_matrix_correction_supported(&self->dev->image_storage))
  {
    bwb[0] = 1.0;
    bwb[2] = 1.0;
    bwb[1] = 1.0;
    bwb[3] = 1.0;

    return FALSE;
  }

  double mul[4];
  if(dt_colorspaces_conversion_matrices_rgb
     (self->dev->image_storage.adobe_XYZ_to_CAM,
      NULL, NULL,
      self->dev->image_storage.d65_color_matrix, mul))
  {
    // normalize green:
    bwb[0] = mul[0] / mul[1];
    bwb[2] = mul[2] / mul[1];
    bwb[1] = 1.0;
    bwb[3] = mul[3] / mul[1];

    return FALSE;
  }

  return TRUE;
}

static void _prepare_matrices(dt_iop_module_t *self)
{
  dt_iop_temperature_gui_data_t *g = self->gui_data;

  // sRGB D65
  const double RGB_to_XYZ[3][4] = { { 0.4124564, 0.3575761, 0.1804375, 0 },
                                    { 0.2126729, 0.7151522, 0.0721750, 0 },
                                    { 0.0193339, 0.1191920, 0.9503041, 0 } };

  // sRGB D65
  const double XYZ_to_RGB[4][3] = { { 3.2404542, -1.5371385, -0.4985314 },
                                    { -0.9692660, 1.8760108, 0.0415560 },
                                    { 0.0556434, -0.2040259, 1.0572252 },
                                    { 0, 0, 0 } };

  if(!dt_image_is_raw(&self->dev->image_storage))
  {
    // let's just assume for now(TM) that if it is not raw, it is sRGB
    memcpy(g->XYZ_to_CAM, XYZ_to_RGB, sizeof(g->XYZ_to_CAM));
    memcpy(g->CAM_to_XYZ, RGB_to_XYZ, sizeof(g->CAM_to_XYZ));
    return;
  }

  if(!dt_colorspaces_conversion_matrices_xyz(self->dev->image_storage.adobe_XYZ_to_CAM,
                                              self->dev->image_storage.d65_color_matrix,
                                              g->XYZ_to_CAM, g->CAM_to_XYZ))
  {
    if(self->dev->image_storage.load_status == DT_IMAGEIO_OK)  // suppress spurious error messages
    {
      char *camera = self->dev->image_storage.camera_makermodel;
      dt_print(DT_DEBUG_ALWAYS, "[temperature] `%s' color matrix not found for image", camera);
      dt_control_log(_("`%s' color matrix not found for image"), camera);
    }
  }
}

static void _find_coeffs(dt_iop_module_t *self, double coeffs[4])
{
  const dt_image_t *img = &self->dev->image_storage;

  // the raw should provide wb coeffs:
  gboolean ok = TRUE;
  // Only check the first three values, the fourth is usually NAN for RGB
  const int num_coeffs = (img->flags & DT_IMAGE_4BAYER) ? 4 : 3;
  for(int k = 0; ok && k < num_coeffs; k++)
  {
    if(!dt_isnormal(img->wb_coeffs[k]) || img->wb_coeffs[k] == 0.0f)
      ok = FALSE;
  }
  if(ok)
  {
    for_four_channels(k)
      coeffs[k] = img->wb_coeffs[k];
    return;
  }

  double bwb[4];
  if(!_calculate_bogus_daylight_wb(self, bwb))
  {
    // found camera matrix and used it to calculate bogus daylight wb
    for_four_channels(c)
      coeffs[c] = bwb[c];
    return;
  }

  // no cam matrix??? try presets:
  for(int i = 0; i < dt_wb_presets_count(); i++)
  {
    const dt_wb_data *wbp = dt_wb_preset(i);

    if(!strcmp(wbp->make, img->camera_maker)
       && !strcmp(wbp->model, img->camera_model))
    {
      // just take the first preset we find for this camera
      for(int k = 0; k < 3; k++)
        coeffs[k] = wbp->channels[k];
      return;
    }
  }

  // did not find preset either?
  if(!_ignore_missing_wb(&(self->dev->image_storage)))
  {
    //  only display this if we have a sample, otherwise it is better to keep
    //  on screen the more important message about missing sample and the way
    //  to contribute.
    if(!img->camera_missing_sample)
      dt_control_log(_("failed to read camera white balance information from `%s'!"),
                     img->filename);
    dt_print(DT_DEBUG_ALWAYS,
             "[temperature] failed to read camera white balance information from `%s'!",
             img->filename);
  }

  // final security net: hardcoded default that fits most cams.
  coeffs[0] = 2.0;
  coeffs[1] = 1.0;
  coeffs[2] = 1.5;
  coeffs[3] = 1.0;
}
