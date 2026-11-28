static inline gboolean dt_pipe_is_preview(const dt_dev_pixelpipe_t *pipe)
{
  return (pipe->type & DT_DEV_PIXELPIPE_PREVIEW);
}
