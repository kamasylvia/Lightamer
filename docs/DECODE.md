# DECODE — RAW decoding over rawspeed (B2-a)

> Owner: `lightamer-decode` (L1). CLI probe: `lightamer-cli decode --dump`.
> Pinned source: `external/rawspeed` @ `0c16fee7772594e98897bded01fc31bc3409b4cb`
> (= darktable `679d594f5d`'s gitlink). License: LGPL-2.1-or-later, statically
> linked, distributed as part of the whole under GPL-3.0-or-later — see
> `docs/LICENSE-AUDIT.md` §3 and §B2-a.

## 1. Source and build

- **Submodule**: `external/rawspeed`, SSH URL
  (`git@github.com:darktable-org/rawspeed.git`), checked out at the pin above
  (detached HEAD; the recorded branch is `develop`, same as darktable's
  `.gitmodules`). Verify: `git ls-tree HEAD external/rawspeed`.
- **Build**: `crates/lightamer-decode/build.rs` drives `cmake` (Release,
  static, `arm64`, OpenMP on) plus `cc` for the shim. System inputs are
  Homebrew `pugixml` + `libjpeg-turbo` + `libomp` (dynamic) and SDK `zlib`.
  Everything lands under `OUT_DIR` (inside `target/`); nothing is installed
  outside the repository.
- **`cameras.xml` ships as a copy**: `build.rs` copies
  `external/rawspeed/data/cameras.xml` to `$OUT_DIR/cameras.xml` and bakes
  that path in as `RS_CAMERAS_XML_DEFAULT` (C++) /
  `env!("RAWSPEED_CAMERAS_XML")` (Rust). It is **not** embedded in the
  binary. After re-pinning the submodule, `touch
  crates/lightamer-decode/build.rs` to force a rebuild.
- **New crates**: `cmake 0.1.58` (new in `Cargo.lock`, MIT OR Apache-2.0);
  `cc 1.11.3` was already locked (B12 rusqlite) and is reused.

## 2. C ABI (`csrc/rawspeed_shim.{h,cpp}`)

| Function | Contract |
|---|---|
| `rs_open(path, cameras_xml, err)` | Parse + select decoder + `checkSupport`. `cameras_xml == NULL` uses the process singleton. No pixels yet. |
| `rs_decode(img, err)` | `decodeRaw` + `decodeMetaData`. Idempotent. |
| `rs_fill_info(img, out, err)` | Metadata + geometry into `rs_image_info`. |
| `rs_mosaic_u16` / `rs_mosaic_f32` | Cropped plane base (rows `pitch_elems` apart); NULL on type mismatch. Borrows the handle. |
| `rs_mosaic_hash(img, err)` | FNV-1a 64 over the cropped plane (u16 and f32). |
| `rs_thumb(...)` | **B2-a placeholder**: always `RS_ERR_THUMB_UNAVAILABLE` — rawspeed at the pin exposes no thumbnail API. B2-b parses EXIF thumbnails. |
| `rs_free` / `rs_free_bytes` | Release (NULL-safe). |
| `rs_ensure_meta(err)` | Parse the singleton database now (timing seam). |
| `rs_meta_parse_count()` | Process parse count (singleton probe). |
| `rs_info_size()` / `rs_error_size()` / `rs_classify_for_test(s, m)` | Test seams: struct-size pins, error-mapping pin. |

**Exception discipline** (three classes): `rs_open`/`rs_decode` catch
`bad_alloc` (→6) + `std::exception` (→`classify`) + `...` (→9);
`rs_fill_info`/`rs_mosaic_hash`/`rs_ensure_meta` catch `std::exception`/`...`
→ `INTERNAL` (their `bad_alloc` lands on INTERNAL, undistinguished);
`rs_mosaic_u16`/`rs_mosaic_f32` degrade any throw to NULL; the rest
(`rs_thumb`/`rs_free`/`rs_free_bytes`/`rs_meta_parse_count`/`rs_info_size`/
`rs_error_size`/`rs_classify_for_test`) need no `try` (pure getters over
`noexcept` accessors). Nothing C++ crosses the boundary; corrupt input is a
code, never an abort. The handle owns the file bytes, so the spike's
`RawDecoder` buffer-lifetime caveat does not apply.

**OpenMP waits**: the shim defaults `OMP_WAIT_POLICY` to `passive` (blocking
waits) unless the user set it — libomp's default spin makes bursty decode
latency swing with machine load (measured 68–186 ms active vs 65–105 ms
passive on the 61 MP gate file; see `B2a-REPORT.md` §timing). Set in
`getMeta`, the choke point before any OpenMP region.

## 3. Rust wrapper (`lightamer-decode`)

- `RawImage::open` → `decode` → `metadata()` / `mosaic()` /
  `mosaic_hash()`; `decode_file` does all four. `unsafe` lives only in
  `ffi` (declarations) plus one `SAFETY`-commented block per extern call in
  `image`; handles are `Send` but not `Sync`.
- `Mosaic::U16(Vec<u16>)` / `F32(Vec<f32>)`: owned cropped planes, pitch
  removed. `RawMetadata` carries every field below; absent-from-rawspeed
  fields are `None` by construction (see §5).
## 4. Error codes

| Code | Name | Human sentence | Typical trigger |
|---|---|---|---|
| 1 | `NotFound` | file missing or unreadable | bad path |
| 2 | `NotRaw` | not a supported RAW file | random bytes, JPEG-as-ARW |
| 3 | `UnknownCamera` | camera unknown to the camera database | unsupported body (mapping-tested; no fixture) |
| 4 | `Truncated` | file is truncated or empty | empty / cut / header-only |
| 5 | `DecompressFailed` | RAW decompression failed | corrupt payload |
| 6 | `OutOfMemory` | out of memory | `bad_alloc` |
| 7 | `UnsupportedCompression` | compression not supported | unknown codec tag (mapping-tested) |
| 8 | `ThumbnailUnavailable` | embedded thumbnail not available in B2-a | `rs_thumb` |
| 9 | `Internal` | internal decode error | null handle, broken DB, unknown |

Mapping rule (`classify`, both stages): truncation strings → 4; "No decoder
found" → 2; camera strings → 3; compression+support strings → 7; decompress
strings → 5; other support strings and anything unknown → stage default
(open → 2, decode → 5). The exact observed wordings are pinned by
`error_mapping_covers_observed_messages`.

## 5. Field provenance

| Field | Source |
|---|---|
| decoder, make/model (+canonical), mode | rawspeed `ImageMetaData` / demangled `typeid` |
| width/height/uncropped/crop/pitch/cpp/bpp | `RawImageData` geometry |
| CFA pattern/filter, `is_xtrans` | `ColorFilterArray` (6x6 ⇒ X-Trans) |
| black (+2x2), white | `blackLevel` / `blackLevelSeparate` / `whitePoint` (`-1` = rawspeed's unset sentinel, passed through verbatim) |
| WB multipliers (R/G1/B/G2) | `wbCoeffs` (4th often 0) |
| color matrix XYZ→cam | `colorMatrix` verbatim; cam→XYZ is the `f64` inverse (`None` if singular) |
| ISO | `isoSpeed` (0 ⇒ `None`) |
| subsampling, pixel aspect | `ImageMetaData` |
| WB kelvin/tint, exposure, aperture, focal, lens | **Always `None`: rawspeed exposes no such fields** |

## 6. CLI probe

```sh
cargo run -p lightamer-cli -- decode --dump <file> [--thumb] [--repeat N]
```

Prints one `key: value` line per field plus `meta_ms`, `decode_ms_cold`
(first decode, meta pre-loaded), `decode_ms_hot` (last of `--repeat N`),
and `meta_parse_count`. `--thumb` prints the B2-b placeholder line.
Developer tool only: it never touches the engine. Exit 2 with the typed
message on decode failure.

## 7. Tests

- `tests/parity.rs`: 3 fixtures vs `rs-oracle` (direct rawspeed API, same
  static lib, built into `OUT_DIR`): width/height/black/white/WB/mosaic-hash
  plus decoder containment.
- `tests/robustness.rs`: 5 corrupt inputs in one process → their codes, then
  a valid decode proves survival.
- `tests/cache.rs`: double-run bit identity; parse count stable across three
  decodes; 20× decode RSS growth < 32 MiB (`ps` sampling).
- Unit: error display/round-trip, mapping table, 3x3 inverse, FFI size pin,
  bundled-XML existence, `Send` pin.
- CLI: `apps/lightamer-cli/tests/decode_dump.rs` — fields, `--thumb`,
  `--repeat`, corrupt exit 2, flag validation.
