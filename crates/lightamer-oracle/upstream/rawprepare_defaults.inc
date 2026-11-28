void reload_defaults(dt_iop_module_t *self)
{
  dt_iop_rawprepare_params_t *d = self->default_params;
  const dt_image_t *const image = &(self->dev->image_storage);

  // if there are embedded GainMaps, they should be applied by default to avoid uneven color cast
  const gboolean has_gainmaps = _check_gain_maps(self, NULL);

  *d = (dt_iop_rawprepare_params_t){.left = image->crop_x,
                                    .top = image->crop_y,
                                    .right = image->crop_right,
                                    .bottom = image->crop_bottom,
                                    .raw_black_level_separate[0] = image->raw_black_level_separate[0],
                                    .raw_black_level_separate[1] = image->raw_black_level_separate[1],
                                    .raw_black_level_separate[2] = image->raw_black_level_separate[2],
                                    .raw_black_level_separate[3] = image->raw_black_level_separate[3],
                                    .raw_white_point = image->raw_white_point,
                                    .flat_field = has_gainmaps ? FLAT_FIELD_EMBEDDED : FLAT_FIELD_OFF };

  self->hide_enable_button = TRUE;
  self->default_enabled = dt_image_is_rawprepare_supported(image) && !_image_is_normalized(image);

  if(self->widget)
    gtk_stack_set_visible_child_name(GTK_STACK(self->widget), self->default_enabled ? "raw" : "non_raw");
}
