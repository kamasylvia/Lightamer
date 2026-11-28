// SPDX-License-Identifier: GPL-3.0-or-later
// Glue: includes the shim plus the verbatim hotpixels fragments in
// dependency order (leaf statics before their callers). Upstream callback
// names collide across modules (every iop defines `process`), so the
// common names are macro-renamed to hotpixels_* before the verbatim
// includes; the .inc bytes stay untouched.
#include "dt_shim.h"

#include "pipe_type_enum.inc"
#include "pipe_predicates.inc"
#include "hotpixels_fcn.inc"
#include "hotpixels_types.inc"

#define process hotpixels_process
#define commit_params hotpixels_commit_params
#define reload_defaults hotpixels_reload_defaults
#define init_pipe hotpixels_init_pipe
#define cleanup_pipe hotpixels_cleanup_pipe
#include "hotpixels_bayer.inc"
#include "hotpixels_mono.inc"
#include "hotpixels_xtrans.inc"
#include "hotpixels_process.inc"
#include "hotpixels_commit.inc"
#include "hotpixels_pipe.inc"
#include "hotpixels_defaults.inc"
#undef process
#undef commit_params
#undef reload_defaults
#undef init_pipe
#undef cleanup_pipe

#include "piece_cfa.inc"
