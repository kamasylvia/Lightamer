# upstream/ MANIFEST — verbatim fragment provenance

Each file below is byte-for-byte lines from the pinned source, extracted by
`../tools/extract.sh` (`<module> [--check]`). Ranges are 1-based inclusive
source lines; concatenated ranges join at line boundaries.

Darktable tag: `release-5.7.0` (repo via `LIGHTAMER_DT_REF`).
rawspeed rev: `0c16fee7772594e98897bded01fc31bc3409b4cb` (workspace
`external/rawspeed` submodule).

## rawprepare

| File | Upstream path | Blob | Ranges |
|---|---|---|---|
| `rawprepare_types.inc` | `src/iop/rawprepare.c` | `b344b027` | 40-55 (flat-field enum + params struct), 65-82 (commit data struct) |
| `rawprepare_crop.inc` | `src/iop/rawprepare.c` | `b344b027` | 195-201 (`_compute_proper_crop`) |
| `rawprepare_roi.inc` | `src/iop/rawprepare.c` | `b344b027` | 253-286 (`modify_roi_out`/`modify_roi_in`) |
| `rawprepare_cfa.inc` | `src/iop/rawprepare.c` | `b344b027` | 301-320 (`_adjust_xtrans_filters`, `_BL`) |
| `rawprepare_process.inc` | `src/iop/rawprepare.c` | `b344b027` | 322-448 (`process`, CPU path) |
| `rawprepare_normalized.inc` | `src/iop/rawprepare.c` | `b344b027` | 569-580 (`_image_is_normalized`) |
| `rawprepare_rawcrops.inc` | `src/iop/rawprepare.c` | `b344b027` | 582-622 (`_image_set_rawcrops`) |
| `rawprepare_gainmaps.inc` | `src/iop/rawprepare.c` | `b344b027` | 624-678 (`_check_gain_maps`) |
| `rawprepare_commit.inc` | `src/iop/rawprepare.c` | `b344b027` | 680-740 (`commit_params`) |
| `rawprepare_pipe.inc` | `src/iop/rawprepare.c` | `b344b027` | 742-751 (`init_pipe`/`cleanup_pipe`) |
| `rawprepare_defaults.inc` | `src/iop/rawprepare.c` | `b344b027` | 753-777 (`reload_defaults`) |
| `image_predicates.inc` | `src/common/image.c` | `05605921` | 170-173 (`dt_image_is_raw`), 180-184 (`dt_image_is_mono_sraw`), 259-262 (`dt_image_is_rawprepare_supported`) |
| `rawspeed_crop.inc` | `src/imageio/imageio_rawspeed.cc` | `7f7dabe7` | 119-127 (`dt_rawspeed_crop_dcraw_filters`) |
| `dng_gainmap_struct.inc` | `src/common/dng_opcode.h` | `a57d2c85` | 26-44 (`dt_dng_gain_map_t`, complete type for `_check_gain_maps`) |
| `shift_dcraw.inc` | `src/librawspeed/metadata/ColorFilterArray.cpp` | `f349c81a` | 143-170 (`ColorFilterArray::shiftDcrawFilter`) |

Deliberately not extracted: GUI functions and state (`gui_data`,
`gui_init`/`gui_update`/…), the OpenCL path (`process_cl`,
`init_global`/`cleanup_global`), `legacy_params` (v1 migration; this pipe
starts at v2 semantics), `distort_transform`/`distort_backtransform` (no
Rust counterpart in this wave), `output_format` (its `dsc.rawprepare`
write has no reader in the RAW head), `init_presets`/`description`/`name`/
`operation_tags`/`flags`/`default_group`/`default_colorspace` (metadata,
not pixels).

## hotpixels

| File | Upstream path | Blob | Ranges |
|---|---|---|---|
| `hotpixels_types.inc` | `src/iop/hotpixels.c` | `ca687dd1` | 35-41 (params struct), 43-50 (gui-data struct, type only: `process` names it), 52-61 (commit data struct) |
| `hotpixels_bayer.inc` | `src/iop/hotpixels.c` | `ca687dd1` | 105-158 (`_process_bayer`) |
| `hotpixels_mono.inc` | `src/iop/hotpixels.c` | `ca687dd1` | 161-216 (`_process_monochrome`) |
| `hotpixels_xtrans.inc` | `src/iop/hotpixels.c` | `ca687dd1` | 219-325 (`_process_xtrans`) |
| `hotpixels_process.inc` | `src/iop/hotpixels.c` | `ca687dd1` | 327-356 (`process`) |
| `hotpixels_defaults.inc` | `src/iop/hotpixels.c` | `ca687dd1` | 358-366 (`reload_defaults`) |
| `hotpixels_commit.inc` | `src/iop/hotpixels.c` | `ca687dd1` | 368-385 (`commit_params`) |
| `hotpixels_pipe.inc` | `src/iop/hotpixels.c` | `ca687dd1` | 387-398 (`init_pipe`/`cleanup_pipe`) |
| `hotpixels_fcn.inc` | `src/develop/imageop_math.h` | `8bc306cc` | 195-207 (`FCNxtrans`) |

## Shared pipe infrastructure (first used by hotpixels)

| File | Upstream path | Blob | Ranges |
|---|---|---|---|
| `piece_cfa.inc` | `src/develop/pixelpipe_hb.c` | `d6f1d1bb` | 1289-1304 (`dt_dev_prepare_piece_cfa`) |
| `pipe_predicates.inc` | `src/develop/pixelpipe_hb.h` | `0c0acea0` | 272-283 (`dt_pipe_is_full/thumb/export`) |
| `pipe_type_enum.inc` | `src/develop/pixelpipe.h` | `e0dce537` | 41-57 (`dt_dev_pixelpipe_type_t`) |

Deliberately not extracted for hotpixels: GUI functions (`gui_init`/
`gui_update`/`draw`), `name`/`description`/`default_group`/`flags`/
`default_colorspace` (metadata, not pixels; the chain's colorspace gate
covers what `dt_dev_prepare_piece_cfa` needs).

## temperature

| File | Upstream path | Blob | Ranges |
|---|---|---|---|
| `temperature_defs.inc` | `src/iop/temperature.c` | `eee5d23a` | 48-64 (temp/tint limits, preset tags) |
| `temperature_types.inc` | `src/iop/temperature.c` | `eee5d23a` | 68-75 (params struct), 77-99 (gui-data struct, type only: conversions name it), 101-105 (commit data struct) |
| `temperature_array.inc` | `src/iop/temperature.c` | `eee5d23a` | 185-199 (params/array helpers) |
| `temperature_ignore.inc` | `src/iop/temperature.c` | `eee5d23a` | 201-236 (`_ignore_missing_wb`) |
| `temperature_spectrum.inc` | `src/iop/temperature.c` | `eee5d23a` | 281-403 (`spd` typedef, blackbody/daylight spectra, temp-to-XYZ) |
| `temperature_convert.inc` | `src/iop/temperature.c` | `eee5d23a` | 406-502 (XYZ-temp search, xyz/temp/mul conversions) |
| `temperature_process.inc` | `src/iop/temperature.c` | `eee5d23a` | 504-639 (`scaled_copy_4wide`, `_publish_chroma`, `process`) |
| `temperature_commit.inc` | `src/iop/temperature.c` | `eee5d23a` | 687-728 (`commit_params`) |
| `temperature_pipe.inc` | `src/iop/temperature.c` | `eee5d23a` | 730-743 (`init_pipe`/`cleanup_pipe`) |
| `temperature_coeffs.inc` | `src/iop/temperature.c` | `eee5d23a` | 1382-1511 (bogus daylight, matrix prep, `_find_coeffs`) |
| `temperature_fcn.inc` | `src/develop/imageop_math.h` | `8bc306cc` | 154-157 (`FC`), 195-207 (`FCNxtrans`) |
| `temperature_simd.inc` | `src/common/dttypes.h` | `f875f6a6` | 57 (`DT_ALIGNED_PIXEL`), 68-72 (SIMD lanes), 94-114 (channel loops) |
| `temperature_colormatrix.inc` | `src/common/dttypes.h` | `f875f6a6` | 231-259 (colormatrix validity) |
| `temperature_isnormal.inc` | `src/common/math.h` | `689dc106` | 114-117 (`dt_isnormal`) |
| `temperature_d65.inc` | `src/common/colorspaces.h` | `9b01c350` | 37-38 (`D65xyY`) |
| `temperature_matrices.inc` | `src/common/colorspaces.c` | `c3fc7d6d` | 2311-2456 (pseudoinverse, conversion matrices) |
| `temperature_matrix_pred.inc` | `src/common/image.c` | `05605921` | 253-257 (`dt_image_is_matrix_correction_supported`) |
| `temperature_preview_pred.inc` | `src/develop/pixelpipe_hb.h` | `0c0acea0` | 292-295 (`dt_pipe_is_preview`) |
| `temperature_cie_tables.inc` | `src/external/cie_colorimetric_tables.c` | `051340d0` | 1-230 (full data tables) |

Deliberately not extracted for temperature: GUI functions and state,
`reload_defaults` (needs GUI/dev/history; callers pass explicit params and
the glue default-fill is empty), `process_cl`/`init_global`, `legacy_params`,
`name`/`description`/`default_group`/`flags`/`default_colorspace` (metadata,
not pixels), the `wb_presets` table (GUI menu data; the count stub reads 0).
`src/common/colorspaces_inline_conversions.h` contributes no referenced
symbol to the extracted functions (verified by grep: the spectrum legs use
only `D65xyY`, taken above), so it stays out as a whole rather than dragging
its SSE header chain in.
