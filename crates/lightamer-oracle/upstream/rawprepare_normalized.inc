static int _image_is_normalized(const dt_image_t *const image)
{
  // if raw with floating-point data, if not 1 or legacy magic whitelevel, then it needs normalization
  if((image->flags & DT_IMAGE_HDR) == DT_IMAGE_HDR)
  {
    // dng spec is somewhat ambiguous here.
    return image->raw_white_point == 1 || image->raw_white_point == 0x3F800000U;
  }

  // else, assume normalized
  return image->buf_dsc.channels == 1 && image->buf_dsc.datatype == TYPE_FLOAT;
}
