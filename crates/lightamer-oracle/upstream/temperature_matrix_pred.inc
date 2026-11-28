gboolean dt_image_is_matrix_correction_supported(const dt_image_t *img)
{
  return (img->flags & (DT_IMAGE_RAW | DT_IMAGE_S_RAW ))
          && !(img->flags & DT_IMAGE_MONOCHROME);
}
