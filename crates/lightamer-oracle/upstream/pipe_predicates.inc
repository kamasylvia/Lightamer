static inline gboolean dt_pipe_is_full(const dt_dev_pixelpipe_t *pipe)
{
  return (pipe->type & DT_DEV_PIXELPIPE_FULL);
}
static inline gboolean dt_pipe_is_thumb(const dt_dev_pixelpipe_t *pipe)
{
  return (pipe->type & DT_DEV_PIXELPIPE_THUMBNAIL);
}
static inline gboolean dt_pipe_is_export(const dt_dev_pixelpipe_t *pipe)
{
  return (pipe->type & DT_DEV_PIXELPIPE_EXPORT);
}
