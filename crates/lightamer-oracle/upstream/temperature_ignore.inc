static gboolean _ignore_missing_wb(dt_image_t *img)
{
  // Ignore files that end with "-hdr.dng" since these are broken files we
  // generated without any proper WB tagged
  if(g_str_has_suffix(img->filename,"-hdr.dng"))
    return TRUE;

  // If we failed to read the image correctly, don't complain about WB
  if(img->load_status != DT_IMAGEIO_OK && img->load_status != DT_IMAGEIO_CACHE_FULL)
    return TRUE;

  static const char *const ignored_cameras[] = {
    "Canon PowerShot A610",
    "Canon PowerShot S3 IS",
    "Canon PowerShot A620",
    "Canon PowerShot A720 IS",
    "Canon PowerShot A630",
    "Canon PowerShot A640",
    "Canon PowerShot A650",
    "Canon PowerShot SX110 IS",
    "Mamiya ZD",
    "Canon EOS D2000C",
    "Kodak EOS DCS 1",
    "Kodak DCS560C",
    "Kodak DCS460D",
    "Nikon E5700",
    "Sony DSC-F828",
    "GITUP GIT2",
  };

  for(int i=0; i < sizeof(ignored_cameras)/sizeof(ignored_cameras[1]); i++)
    if(!strcmp(img->camera_makermodel, ignored_cameras[i]))
      return TRUE;

  return FALSE;
}
