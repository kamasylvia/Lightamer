gboolean dt_image_is_raw(const dt_image_t *img)
{
  return (img->flags & DT_IMAGE_RAW) == DT_IMAGE_RAW;
}
gboolean dt_image_is_mono_sraw(const dt_image_t *img)
{
  const uint32_t test = DT_IMAGE_MONOCHROME | DT_IMAGE_S_RAW;
  return ((img->flags & test) == test);
}
gboolean dt_image_is_rawprepare_supported(const dt_image_t *img)
{
  return img->flags & (DT_IMAGE_RAW | DT_IMAGE_S_RAW) ? TRUE : FALSE;
}
