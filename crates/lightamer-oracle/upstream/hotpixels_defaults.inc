void reload_defaults(dt_iop_module_t *self)
{
  const dt_image_t *img = &self->dev->image_storage;

  const gboolean monoraw = (img->flags & DT_IMAGE_S_RAW) && (img->flags & DT_IMAGE_MONOCHROME);
  const gboolean supported = dt_image_is_raw(img) || monoraw;
  // can't be switched on for non-raw images:
  self->hide_enable_button = !supported;
}
