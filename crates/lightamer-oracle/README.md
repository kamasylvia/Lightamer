# lightamer-oracle — verbatim upstream runner (test-only)

Runs darktable module code **byte-for-byte** as extracted from the pinned
tag, behind stub interfaces and a small chain runner, so Rust
transcriptions compare pixels against the real thing instead of a
re-implementation. Links into test binaries only (`cargo xtask layers`
refuses it as a normal dependency).

## Layout

- `upstream/*.inc` — verbatim fragments, one concern each. Provenance per
  file in `upstream/MANIFEST.md`; re-extracted by `tools/extract.sh`.
- `stubs/dt_shim.h` — minimal darktable interface: only the types, macros,
  and declarations the fragments touch. Struct layouts are oracle-local
  (behavior comes from verbatim logic, not ABI); enumerator *values* copy
  upstream with a citation each.
- `stubs/stubs.c` — pure-interface stand-ins (cache, log, GUI, glib list).
  No upstream logic; behavior differences (if any) are in the table below.
- `csrc/chain.c` — the mini pipe: one module table, build phase (init +
  `reload_defaults` + `commit_params` against the image snapshot, with the
  pipe type set from the caller's render kind), geometry phase
  (`modify_roi_out` threading), process phase (in chain order,
  `dt_dev_prepare_piece_cfa` then `process` per stage, `pipe->dsc`
  evolving). ABI in `csrc/oracle_abi.h`.
- `csrc/*_tu.c(pp)` — translation units: shim + fragments in dependency
  order. Upstream callback names collide across modules (every iop defines
  `process`), so each TU after the first macro-renames them
  (`hotpixels_process`, …) before the verbatim includes; the `.inc` bytes
  stay untouched. `*_glue.c` holds the scalar params fill/read pair so
  Rust never mirrors the C struct layout. Test-only conversions that call
  file-static upstream functions (temperature's temp/tint legs) live as a
  marked section at the end of their TU, since no other TU can see them.
- `src/lib.rs` — the only `unsafe` boundary: `#[repr(C)]` mirrors (sizes
  asserted both sides), length checks before every call, owned results out.
  Thread-safe by construction: the one cross-call pointer
  (`oracle_active_image`) is thread-local and every call otherwise touches
  only its own stack, so parallel test threads share nothing. The bundled
  `shiftDcrawFilter` is a weak definition: binaries that also link decode's
  rawspeed (same pinned source) use the strong one with no duplicate-symbol
  complaint.

## Behavior stubs

Every stub that can differ observably from upstream, and why it cannot be
observed in this oracle's runs:

| Stub | Upstream behavior | Oracle behavior | Unobservable because |
|---|---|---|---|
| `dt_image_cache_get` / `write_release` | cache lookup + DB write of `p_width`/`p_height` | returns the chain's working image; release is a no-op | the DB has no reader here; the in-memory write lands identically (reported in `StateOut`) |
| `DT_CONTROL_SIGNAL_RAISE` | GUI metadata-update signal | no-op | no GUI, no signal bus |
| `dt_print`, `dt_iop_set_module_trouble_message` | log + GUI badge | silent | tests use valid params; trouble paths stay silent but pixels/state still compare |
| `dt_dev_write_scharr_mask` | detail mask write | `abort()` | chain pins `want_detail_mask = 0`; `process` is the only caller |
| `gtk_stack_set_visible_child_name` | panel switch | `abort()` | widget is always NULL behind `if(self->widget)` |
| `g_list_length`, `g_list_nth_data` | glib list walk | same walk, NULL-safe | identical semantics incl. NULL input |
| `MIN`/`MAX`/`CLAMP` | glib statement expressions | plain ternaries | every extracted call site passes side-effect-free arguments |
| `DT_OMP_FOR(SIMD)` | OpenMP parallel loops | serial | matches a no-OpenMP upstream build; pixel math identical |
| `dng_gain_maps = NULL` | DNG opcodes from EXIF | always empty | ARW carries none; flat-field stays off in every run |
| `dt_iop_image_copy_by_size` | copy, parallel past a threshold | serial `memcpy` | bytes out equal bytes in either way |
| hotpixels roi pair | inherited identity defaults | identity glue | byte-equal to `_iop_modify_roi_out/in` (`imageop.c`) |
| temperature roi pair + `reload_defaults` | inherited identity defaults; heavy GUI/dev/history defaults | identity glue + empty default-fill | byte-equal roi; callers always pass explicit params, so defaults never run |
| module colorspace callbacks | per-module `input/default_colorspace` | always `IOP_CS_RAW` | hotpixels answers RAW on both upstream; rawprepare never reads piece CFA (no reference in its fragments); temperature's CFA read goes through the derived piece table either way |
| `dt_wb_presets_count` / `dt_wb_preset` | rows in the WB preset store | count 0; lookup `abort()`s | the store is GUI menu data; the one extracted caller (`_find_coeffs`) loops under the count, so the preset leg is empty and falls through to the hardcoded fallback, compared exactly |
| `d65_color_matrix` invalid | DNG-embedded 3x3 when present | always invalid | ARW carries none; the matrix legs take the adobe branch on both sides |
| `camera_maker/model`, `filename`, `load_status` | EXIF strings + load result | constants (`""`, `"oracle.arw"`, OK) | only read through log gates (silent stubs) and the zero-count preset loop |
| `dt_control_log` | GUI toast | silent | like `dt_print` |
| `g_str_has_suffix` | glib suffix check | same semantics, NULL-safe | identical truth table; only `_ignore_missing_wb` calls it |
| `DT_OMP_DECLARE_SIMD` | OpenMP SIMD hint | empty | matches a no-OpenMP upstream build, like `DT_OMP_FOR` |
| lcms2 | system library | same system library (`/opt/homebrew/opt/lcms2`) | the Rust side links it dynamically too, so `cmsWhitePointFromTemp` computes identically |
| disabled stage (chain behavior, not a stub) | piece skipped whole (pixels + geometry pass through) | float tiles pass through incl. nonzero crop; `rc=2` refuses u16 input | float runs match upstream exactly (tested); u16 passthrough is inexpressible in the f32-only ABI, so it errors loudly instead of diverging |

## Adding another module

1. Append its manifest lines to `tools/extract.sh` (`repo|rev|path|blob|
   ranges|dest`), run it, confirm `upstream/` gains the fragments.
2. Declare its callbacks in `csrc/chain.c`, add one `MODULES` row plus its
   `output_dsc` hook (channels/datatype it leaves behind).
3. Add `csrc/<module>_glue.c`: scalar params fill/read + params-size
   helper, same shape as `rawprepare_glue.c`.
4. Add a `csrc/<module>_tu.c` including shim + fragments in dependency
   order, macro-renaming the colliding callback names first (see
   `hotpixels_tu.c`); list every new file in `build.rs` (`GLUE_SOURCES` /
   `VERBATIM_TUS` / `UPSTREAM_SOURCES` / rerun guards). Glue compiles
   with warnings on, verbatim TUs with `-w`.
5. Extend `src/lib.rs`: one `run_<module>` (+ chain entries as needed)
   reusing the same `Facts`/`Roi`/`StateOut`/`PipeType` vocabulary
   (`Facts` stays frozen once tests construct it — temperature's extras
   ride the separate `TempFacts`, see `oracle_run_temp`).
6. Extend `upstream/MANIFEST.md` and this README's tables; run
   `tools/extract.sh <module> --check`.

## Re-extract and verify

```sh
LIGHTAMER_DT_REF=/path/to/refs/dt-master tools/extract.sh rawprepare [--check]
```

Without the variable (or without `external/rawspeed`), the script skips
with a message and exits 0: the committed copies are the build input,
extraction is only provenance. `--check` re-extracts to a temp dir and
fails on the first byte difference. The manifest blob hashes guard
against tag drift before a single line is read.

## License

Verbatim fragments stay under their upstream licenses (darktable
GPL-3.0-or-later; rawspeed `shiftDcrawFilter` LGPL-2.1-or-later),
distributed as part of this GPL-3.0-or-later whole; see `NOTICE` and
`docs/LICENSE-AUDIT.md`. Glue, stubs, and Rust are Lightamer
GPL-3.0-or-later.
