// SPDX-License-Identifier: GPL-3.0-or-later
// C ABI of the oracle chain: plain-old-data structs the Rust side mirrors
// with #[repr(C)]. Sizes are asserted on both sides (100/20/68).
#pragma once

#include <stddef.h>
#include <stdint.h>

// Image facts the caller fills (subset of dt_image_t the chain transcribes).
typedef struct oracle_facts
{
  int32_t width, height, p_width, p_height;
  int32_t crop_x, crop_y, crop_right, crop_bottom;
  uint16_t black_separate[4];
  uint32_t white_point;
  uint32_t filters;
  uint8_t xtrans[36]; // row-major 6x6
  int32_t flags; // DT_IMAGE_* bits
  uint32_t buf_channels; // buf_dsc.channels (1 = mono)
  int32_t buf_datatype; // buf_dsc.datatype (TYPE_* value)
  int32_t id;
} oracle_facts;

// Region of interest, same five fields as dt_iop_roi_t.
typedef struct oracle_roi
{
  int32_t x, y, width, height;
  float scale;
} oracle_roi;

// Post-run state: what the Rust transcription must reproduce.
typedef struct oracle_state_out
{
  int32_t enabled;
  uint32_t filters;
  uint8_t xtrans[36]; // row-major 6x6
  float processed_maximum[4];
  int32_t p_width, p_height;
} oracle_state_out;

// Runs `count` modules in chain order: every stage builds and commits
// against the image snapshot first, then stages process in order with
// pipe->dsc evolving. `pipe_type` carries the render kind as
// dt_dev_pixelpipe_type_t bits (pipe_type_enum.inc); `planes` is floats
// per pixel on every buffer (1, or 4 for a mono small-RAW hotpixels run).
// 0 = ok; 1 = unknown module or bad count; 2 = disabled-stage shape or
// input mismatch; 3 = final roi differs from the caller's rout;
// 4 = intermediate allocation failure.
int oracle_run(const char **names, const void **params_list, int count,
               const oracle_facts *facts, const void *input, int input_is_u16,
               const oracle_roi *rin, void *output, const oracle_roi *rout,
               oracle_state_out *state, int pipe_type, int planes);
int oracle_roi_map(int want_out, const char *name, const oracle_facts *facts,
               const void *params, const oracle_roi *in, oracle_roi *out);
int oracle_defaults(const char *name, const oracle_facts *facts, void *params_out);
int oracle_params_size(const char *name);
