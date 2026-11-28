void commit_params(dt_iop_module_t *self,
                   dt_iop_params_t *p1,
                   dt_dev_pixelpipe_t *pipe,
                   dt_dev_pixelpipe_iop_t *piece)
{
  dt_iop_temperature_params_t *p = (dt_iop_temperature_params_t *)p1;
  dt_iop_temperature_data_t *d = piece->data;
  float *tcoeffs = (float *)p;

  if(self->hide_enable_button)
    piece->enabled = FALSE;

  dt_dev_chroma_t *chr = &self->dev->chroma;

  if(self->hide_enable_button)
  {
    for_four_channels(k)
      chr->wb_coeffs[k] = 1.0f;
    return;
  }

  for_four_channels(k)
  {
    d->coeffs[k] = tcoeffs[k];
    chr->wb_coeffs[k] = piece->enabled ? d->coeffs[k] : 1.0f;
  }

  // 4Bayer images not implemented in OpenCL yet
  if(self->dev->image_storage.flags & DT_IMAGE_4BAYER)
    piece->process_cl_ready = FALSE;

  d->preset = p->preset;

  /* Make sure the chroma information stuff is valid
     If piece is disabled we always clear the trouble message and
     make sure chroma does know there is no temperature module.
  */
  chr->late_correction = p->preset == DT_IOP_TEMP_D65_LATE;
  chr->temperature = piece->enabled ? self : NULL;
  if(dt_pipe_is_preview(pipe) && !piece->enabled)
    dt_iop_set_module_trouble_message(self, NULL, NULL, NULL);
}
