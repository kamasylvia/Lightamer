static gboolean _image_set_rawcrops(dt_iop_module_t *self,
                                    const dt_imgid_t imgid,
                                    const int left,
                                    const int right,
                                    const int top,
                                    const int bottom)
{
  dt_image_t *img = &self->dev->image_storage;

  const gboolean cropvalid = (left >= 0) && (right >= 0) && (top >= 0) && (bottom >= 0)
    && (left+right < img->width / 2) && (top + bottom < img->height /2);

  const gboolean testdim =
      (img->p_width == img->width - left - right)
   && (img->p_height == img->height - top - bottom);

  if(testdim && cropvalid) return FALSE;

  if(!cropvalid)
  {
    dt_print
      (DT_DEBUG_ALWAYS,
       "[rawprepare] got wrong crop parameters left=%i, right=%i, top=%i, bottom=%i for size=%ix%i\n",
       left, right, top, bottom, img->width, img->height);
    dt_iop_set_module_trouble_message(self,
     _("invalid crop parameters"),
     _("please reset to defaults, update your preset or set to something correct"),
       "invalid crop parameters");
  }
  else
    dt_iop_set_module_trouble_message(self, NULL, NULL, NULL);

  // we update p_width & height both in the image_storage for fast access within the pipeline
  // and the database so we can access that also via dt_image_cache_get()
  dt_image_t *image = dt_image_cache_get(imgid, 'w');
  image->p_width = img->p_width = img->width - (cropvalid ? left + right : 0);
  image->p_height = img->p_height = img->height - (cropvalid ? top + bottom : 0);
  dt_image_cache_write_release(image, DT_IMAGE_CACHE_RELAXED);

  return TRUE;
}
