// SPDX-License-Identifier: GPL-3.0-or-later
// The mini pipe: builds one dt stack per run and walks the module table in
// upstream order — init_pipe, reload_defaults, commit_params (reading the
// image snapshot), then process per stage with pipe->dsc evolving like
// pixelpipe_hb.c. Adding a module = one table row + its params fill/read
// helpers (see rawprepare_glue.c); the loop below stays untouched.
#include "oracle_abi.h"

#include "dt_shim.h"
#include "pipe_type_enum.inc"

#include <stdlib.h>
#include <string.h>

typedef struct oracle_vtab
{
  const char *name;
  size_t (*params_size)(void);
  void (*init_pipe)(dt_iop_module_t *, dt_dev_pixelpipe_t *, dt_dev_pixelpipe_iop_t *);
  void (*cleanup_pipe)(dt_iop_module_t *, dt_dev_pixelpipe_t *, dt_dev_pixelpipe_iop_t *);
  void (*reload_defaults)(dt_iop_module_t *);
  void (*commit)(dt_iop_module_t *, dt_iop_params_t *, dt_dev_pixelpipe_t *,
                 dt_dev_pixelpipe_iop_t *);
  void (*process)(dt_iop_module_t *, dt_dev_pixelpipe_iop_t *, const void *, void *,
                  const dt_iop_roi_t *, const dt_iop_roi_t *);
  void (*modify_roi_out)(dt_iop_module_t *, dt_dev_pixelpipe_iop_t *, dt_iop_roi_t *,
                         const dt_iop_roi_t *);
  void (*modify_roi_in)(dt_iop_module_t *, dt_dev_pixelpipe_iop_t *, const dt_iop_roi_t *,
                        dt_iop_roi_t *);
  // Output descriptor this module leaves behind (channels/datatype only;
  // filters/xtrans/maxima evolve inside process like upstream).
  void (*output_dsc)(unsigned int *, dt_iop_buffer_type_t *);
} oracle_vtab_t;

// --- rawprepare row (verbatim functions, declared here, defined in the .inc TUs) ---
void init_pipe(dt_iop_module_t *self, dt_dev_pixelpipe_t *pipe, dt_dev_pixelpipe_iop_t *piece);
void cleanup_pipe(dt_iop_module_t *self, dt_dev_pixelpipe_t *pipe,
                  dt_dev_pixelpipe_iop_t *piece);
void reload_defaults(dt_iop_module_t *self);
void commit_params(dt_iop_module_t *self, dt_iop_params_t *params, dt_dev_pixelpipe_t *pipe,
                   dt_dev_pixelpipe_iop_t *piece);
void process(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece, const void *const ivoid,
             void *const ovoid, const dt_iop_roi_t *const roi_in,
             const dt_iop_roi_t *const roi_out);
void modify_roi_out(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece, dt_iop_roi_t *roi_out,
                    const dt_iop_roi_t *const roi_in);
void modify_roi_in(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece,
                   const dt_iop_roi_t *const roi_out, dt_iop_roi_t *roi_in);
size_t oracle_rawprepare_params_size(void);

// --- hotpixels row (renamed in hotpixels_tu.c: upstream callback names
// collide across modules, so the TU macro-renames them before the verbatim
// includes; the roi pair is glue — hotpixels implements none and inherits
// upstream's identity defaults) ---
void hotpixels_init_pipe(dt_iop_module_t *self, dt_dev_pixelpipe_t *pipe,
                         dt_dev_pixelpipe_iop_t *piece);
void hotpixels_cleanup_pipe(dt_iop_module_t *self, dt_dev_pixelpipe_t *pipe,
                            dt_dev_pixelpipe_iop_t *piece);
void hotpixels_reload_defaults(dt_iop_module_t *self);
void hotpixels_commit_params(dt_iop_module_t *self, dt_iop_params_t *params,
                             dt_dev_pixelpipe_t *pipe, dt_dev_pixelpipe_iop_t *piece);
void hotpixels_process(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece,
                       const void *const ivoid, void *const ovoid,
                       const dt_iop_roi_t *const roi_in, const dt_iop_roi_t *const roi_out);
void hotpixels_modify_roi_out(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece,
                              dt_iop_roi_t *roi_out, const dt_iop_roi_t *const roi_in);
void hotpixels_modify_roi_in(dt_iop_module_t *self, dt_dev_pixelpipe_iop_t *piece,
                             const dt_iop_roi_t *const roi_out, dt_iop_roi_t *roi_in);
size_t oracle_hotpixels_params_size(void);

// rawprepare always emits mono float (the u16 leg converts on the way out).
static void rawprepare_output_dsc(unsigned int *channels, dt_iop_buffer_type_t *datatype)
{
  *channels = 1;
  *datatype = TYPE_FLOAT;
}

// hotpixels leaves the descriptor alone (its process never writes dsc).
static void hotpixels_output_dsc(unsigned int *channels, dt_iop_buffer_type_t *datatype)
{
  (void)channels;
  (void)datatype;
}

// Colorspace gate for dt_dev_prepare_piece_cfa: hotpixels answers RAW on
// both callbacks upstream (default_colorspace returns IOP_CS_RAW, input
// falls back to it), so the per-piece CFA always derives there; rawprepare
// reads neither piece->filters nor piece->xtrans (verified: no reference in
// its fragments), so deriving for it too is unobservable.
static int oracle_raw_colorspace(dt_iop_module_t *self, dt_dev_pixelpipe_t *pipe,
                                 dt_dev_pixelpipe_iop_t *piece)
{
  (void)self;
  (void)pipe;
  (void)piece;
  return IOP_CS_RAW;
}

static const oracle_vtab_t MODULES[] = {
  { "rawprepare", oracle_rawprepare_params_size, init_pipe, cleanup_pipe, reload_defaults,
    commit_params, process, modify_roi_out, modify_roi_in, rawprepare_output_dsc },
  { "hotpixels", oracle_hotpixels_params_size, hotpixels_init_pipe, hotpixels_cleanup_pipe,
    hotpixels_reload_defaults, hotpixels_commit_params, hotpixels_process,
    hotpixels_modify_roi_out, hotpixels_modify_roi_in, hotpixels_output_dsc },
  { NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL },
};

static const oracle_vtab_t *find_module(const char *name)
{
  for(const oracle_vtab_t *m = MODULES; m->name; m++)
    if(!strcmp(m->name, name)) return m;
  return NULL;
}

// ABI layout guard: the Rust side asserts the same three sizes.
_Static_assert(sizeof(oracle_facts) == 100, "oracle_facts size");
_Static_assert(sizeof(oracle_roi) == 20, "oracle_roi size");
_Static_assert(sizeof(oracle_state_out) == 68, "oracle_state_out size");

static void fill_image(dt_image_t *img, const oracle_facts *facts)
{
  memset(img, 0, sizeof(*img));
  img->width = facts->width;
  img->height = facts->height;
  img->p_width = facts->p_width;
  img->p_height = facts->p_height;
  img->crop_x = facts->crop_x;
  img->crop_y = facts->crop_y;
  img->crop_right = facts->crop_right;
  img->crop_bottom = facts->crop_bottom;
  img->flags = facts->flags;
  img->id = facts->id;
  img->buf_dsc.channels = facts->buf_channels;
  img->buf_dsc.datatype = (dt_iop_buffer_type_t)facts->buf_datatype;
  img->buf_dsc.filters = facts->filters;
  memcpy(img->buf_dsc.xtrans, facts->xtrans, sizeof(img->buf_dsc.xtrans));
  memcpy(img->raw_black_level_separate, facts->black_separate,
         sizeof(img->raw_black_level_separate));
  img->raw_white_point = facts->white_point;
  img->dng_gain_maps = NULL; // ARW carries none; DNG gain maps not transcribed
}

static void fill_roi(dt_iop_roi_t *dst, const oracle_roi *src)
{
  dst->x = src->x;
  dst->y = src->y;
  dst->width = src->width;
  dst->height = src->height;
  dst->scale = src->scale;
}

static int roi_equal(const dt_iop_roi_t *a, const oracle_roi *b)
{
  return a->x == b->x && a->y == b->y && a->width == b->width && a->height == b->height
         && a->scale == b->scale;
}

// One dt stack for the single-module helpers below: dev + module + pipe +
// piece, wired like a single-node pipe.
typedef struct oracle_stack
{
  dt_develop_t dev;
  dt_iop_module_t module;
  dt_dev_pixelpipe_t pipe;
  dt_dev_pixelpipe_iop_t piece;
  void *default_params;
} oracle_stack_t;

static void stack_init(oracle_stack_t *s, const oracle_vtab_t *vtab, const oracle_facts *facts,
                       unsigned int in_channels, dt_iop_buffer_type_t in_datatype)
{
  memset(s, 0, sizeof(*s));
  fill_image(&s->dev.image_storage, facts);
  s->pipe.image = s->dev.image_storage; // upstream copies the image into the pipe
  s->pipe.want_detail_mask = FALSE;
  // Snapshot commit reads (B3-1a §1: static at synch time): input descriptor
  // plus image CFA, unit maxima, unpublished temperature.
  s->pipe.dsc.channels = in_channels;
  s->pipe.dsc.datatype = in_datatype;
  s->pipe.dsc.filters = facts->filters;
  memcpy(s->pipe.dsc.xtrans, facts->xtrans, sizeof(s->pipe.dsc.xtrans));
  for(int k = 0; k < 4; k++) s->pipe.dsc.processed_maximum[k] = 1.0f;
  s->module.dev = &s->dev;
  s->module.widget = NULL;
  s->default_params = calloc(1, vtab->params_size());
  s->module.default_params = s->default_params;
  s->piece.pipe = &s->pipe;
  s->piece.enabled = TRUE;
  s->piece.iscale = 1.0f; // oracle buffers are full-resolution
  s->piece.colors = (int)in_channels;
  s->piece.process_tiling_ready = TRUE;
  s->piece.dsc_in = s->pipe.dsc;
  oracle_active_image = &s->dev.image_storage;
}

static void stack_free(oracle_stack_t *s, const oracle_vtab_t *vtab)
{
  vtab->cleanup_pipe(&s->module, &s->pipe, &s->piece);
  free(s->default_params);
  s->default_params = NULL;
  oracle_active_image = NULL;
}

int oracle_params_size(const char *name)
{
  const oracle_vtab_t *v = find_module(name);
  return (int)(v ? v->params_size() : 0);
}

int oracle_defaults(const char *name, const oracle_facts *facts, void *params_out)
{
  const oracle_vtab_t *v = find_module(name);
  if(!v) return 1;
  oracle_stack_t s;
  stack_init(&s, v, facts, facts->buf_channels, (dt_iop_buffer_type_t)facts->buf_datatype);
  v->init_pipe(&s.module, &s.pipe, &s.piece);
  v->reload_defaults(&s.module);
  memcpy(params_out, s.default_params, v->params_size());
  stack_free(&s, v);
  return 0;
}

int oracle_roi_map(int want_out, const char *name, const oracle_facts *facts, const void *params,
               const oracle_roi *in, oracle_roi *out)
{
  const oracle_vtab_t *v = find_module(name);
  if(!v) return 1;
  oracle_stack_t s;
  stack_init(&s, v, facts, facts->buf_channels, (dt_iop_buffer_type_t)facts->buf_datatype);
  v->init_pipe(&s.module, &s.pipe, &s.piece);
  v->reload_defaults(&s.module);
  // modify_roi reads commit data, so commit runs first (params still explicit).
  v->commit(&s.module, (dt_iop_params_t *)params, &s.pipe, &s.piece);
  dt_iop_roi_t cin, cout;
  fill_roi(&cin, in);
  if(want_out)
    v->modify_roi_out(&s.module, &s.piece, &cout, &cin);
  else
  {
    cout = cin;
    v->modify_roi_in(&s.module, &s.piece, &cin, &cout);
  }
  out->x = cout.x;
  out->y = cout.y;
  out->width = cout.width;
  out->height = cout.height;
  out->scale = cout.scale;
  stack_free(&s, v);
  return 0;
}

// One chain stage: its module + piece share the chain's dev and pipe.
typedef struct oracle_stage
{
  const oracle_vtab_t *vtab;
  const void *params;
  dt_iop_module_t module;
  dt_dev_pixelpipe_iop_t piece;
  void *default_params;
  dt_iop_roi_t rin, rout;
} oracle_stage_t;

int oracle_run(const char **names, const void **params_list, int count,
               const oracle_facts *facts, const void *input, int input_is_u16,
               const oracle_roi *rin, void *output, const oracle_roi *rout,
               oracle_state_out *state, int pipe_type, int planes)
{
  if(count <= 0) return 1;
  oracle_stage_t *stages = calloc((size_t)count, sizeof(*stages));
  if(!stages) return 4;
  for(int i = 0; i < count; i++)
  {
    stages[i].vtab = find_module(names[i]);
    stages[i].params = params_list[i];
    if(!stages[i].vtab)
    {
      free(stages);
      return 1;
    }
  }

  // Shared dev + pipe; the snapshot below is what every commit reads.
  dt_develop_t dev;
  dt_dev_pixelpipe_t pipe;
  memset(&dev, 0, sizeof(dev));
  memset(&pipe, 0, sizeof(pipe));
  fill_image(&dev.image_storage, facts);
  pipe.image = dev.image_storage;
  pipe.want_detail_mask = FALSE;
  pipe.type = pipe_type; // render kind as dt_dev_pixelpipe_type_t bits
  pipe.dsc.channels = 1;
  pipe.dsc.datatype = input_is_u16 ? TYPE_UINT16 : TYPE_FLOAT;
  pipe.dsc.filters = facts->filters;
  memcpy(pipe.dsc.xtrans, facts->xtrans, sizeof(pipe.dsc.xtrans));
  for(int k = 0; k < 4; k++) pipe.dsc.processed_maximum[k] = 1.0f;
  oracle_active_image = &dev.image_storage;

  // Build phase: every stage inits and commits against the snapshot above.
  for(int i = 0; i < count; i++)
  {
    oracle_stage_t *st = &stages[i];
    st->module.dev = &dev;
    st->module.widget = NULL;
    st->module.input_colorspace = oracle_raw_colorspace;
    st->module.default_colorspace = oracle_raw_colorspace;
    st->piece.module = &st->module;
    st->default_params = calloc(1, st->vtab->params_size());
    st->module.default_params = st->default_params;
    st->piece.pipe = &pipe;
    st->piece.enabled = TRUE;
    st->piece.iscale = 1.0f;
    st->piece.colors = 1;
    st->piece.process_tiling_ready = TRUE;
    st->vtab->init_pipe(&st->module, &pipe, &st->piece);
    st->vtab->reload_defaults(&st->module);
    st->vtab->commit(&st->module, (dt_iop_params_t *)st->params, &pipe, &st->piece);
  }

  // Geometry phase: thread rois forward; disabled stages pass geometry
  // through untouched (upstream skips a disabled piece whole).
  dt_iop_roi_t cur;
  fill_roi(&cur, rin);
  for(int i = 0; i < count; i++)
  {
    stages[i].rin = cur;
    if(!stages[i].piece.enabled)
      stages[i].rout = cur;
    else
      stages[i].vtab->modify_roi_out(&stages[i].module, &stages[i].piece, &stages[i].rout,
                                     &cur);
    cur = stages[i].rout;
  }

  int rc = 0;
  float **bufs = NULL;
  if(!roi_equal(&cur, rout))
    rc = 3;
  else
  {
    // Stage buffers: caller input in, caller output out, float middles.
    // Every buffer holds `planes` floats per pixel (hotpixels runs 4-wide
    // on a mono small-RAW, 1-wide otherwise).
    bufs = calloc((size_t)count + 1, sizeof(*bufs));
    if(!bufs)
      rc = 4;
    else
    {
      bufs[0] = (float *)input;
      bufs[count] = (float *)output;
      for(int i = 1; i < count && !rc; i++)
      {
        size_t n = (size_t)stages[i - 1].rout.width * (size_t)stages[i - 1].rout.height
                   * (size_t)planes;
        bufs[i] = malloc(n * sizeof(float));
        if(!bufs[i]) rc = 4;
      }
    }
  }

  // Process phase: in chain order, pipe->dsc evolving stage by stage.
  int all_enabled = 1;
  if(!rc)
  {
    for(int i = 0; i < count && !rc; i++)
    {
      oracle_stage_t *st = &stages[i];
      st->piece.dsc_in = pipe.dsc;
      st->piece.buf_in = st->rin;
      all_enabled = all_enabled && st->piece.enabled;
      if(!st->piece.enabled)
      {
        // Upstream skips a disabled piece: downstream sees the input untouched.
        if((i == 0 && input_is_u16) || st->rin.width != st->rout.width
           || st->rin.height != st->rout.height)
          rc = 2;
        else
          memcpy(bufs[i + 1], bufs[i],
                 (size_t)st->rout.width * (size_t)st->rout.height * (size_t)planes
                     * sizeof(float));
      }
      else
      {
        // Per-piece CFA from the current dsc, like upstream ahead of every
        // process call (pixelpipe_hb.c:1391, roi_in).
        dt_dev_prepare_piece_cfa(&st->piece, &st->rin);
        st->vtab->process(&st->module, &st->piece, bufs[i], bufs[i + 1], &st->rin, &st->rout);
        st->vtab->output_dsc(&pipe.dsc.channels, &pipe.dsc.datatype);
      }
    }
  }

  state->enabled = all_enabled;
  state->filters = pipe.dsc.filters;
  memcpy(state->xtrans, pipe.dsc.xtrans, sizeof(pipe.dsc.xtrans));
  memcpy(state->processed_maximum, pipe.dsc.processed_maximum,
         sizeof(pipe.dsc.processed_maximum));
  // Commit may rewrite these even for a disabled piece (rawcrops leg).
  state->p_width = dev.image_storage.p_width;
  state->p_height = dev.image_storage.p_height;

  if(bufs)
  {
    for(int i = 1; i < count; i++) free(bufs[i]);
    free(bufs);
  }
  for(int i = 0; i < count; i++)
  {
    stages[i].vtab->cleanup_pipe(&stages[i].module, &pipe, &stages[i].piece);
    free(stages[i].default_params);
  }
  free(stages);
  oracle_active_image = NULL;
  return rc;
}
