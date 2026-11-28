# DECODE — RAW + raster decoding (B2)

> Owner: `lightamer-decode` (L1). CLI probe: `lightamer-cli decode --dump`.
> Pinned source: `external/rawspeed` @ `0c16fee7772594e98897bded01fc31bc3409b4cb`
> (= darktable `679d594f5d`'s gitlink). License: LGPL-2.1-or-later, statically
> linked, distributed as part of the whole under GPL-3.0-or-later — see
> `docs/LICENSE-AUDIT.md` §3 and §B2-a.
>
> B2-b adds pure-Rust raster decoding, EXIF optics, and embedded thumbnails.
> B2-a history (build recipe, parity numbers, timing gate) lives in
> `.work/gsd/phases/rust-core/waves/B2a-REPORT.md`.

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
- **Rust crates**: `cmake 0.1.58` + `cc 1.11.3` (build, B2-a);
  `kamadak-exif 0.6.2` (+ `mutate_once`, EXIF, B2-b); `png 0.18.1`,
  `tiff 0.11.3`, `zune-jpeg 0.5.15` (raster, B2-b, reused from the lock —
  see `docs/LICENSE-AUDIT.md` §B2-b). Test-only: `jpeg-encoder 0.7.1`
  (fixture synthesis), `flate2` (PNG iCCP fixtures).

## 2. C ABI (`csrc/rawspeed_shim.{h,cpp}`)

| Function | Contract |
|---|---|
| `rs_open(path, cameras_xml, err)` | Parse + select decoder + `checkSupport`. `cameras_xml == NULL` uses the process singleton. No pixels yet. |
| `rs_decode(img, err)` | `decodeRaw` + `decodeMetaData`. Idempotent. |
| `rs_probe(img, out, err)` | `decodeMetaData` on tag-sized dims + ARW crop, no pixels (B3-0b; compression 1/7 only, else fall back to `rs_decode`). Sets the probed flag (decode-after-probe is an error). |
| `rs_probe_supported(img)` | Pure 1/0 shape check for `rs_probe`; any anomaly degrades to 0 (fall back). |
| `rs_fill_info(img, out, err)` | Metadata + geometry into `rs_image_info`. |
| `rs_mosaic_u16` / `rs_mosaic_f32` | Cropped plane base (rows `pitch_elems` apart); NULL on type mismatch. Borrows the handle. |
| `rs_mosaic_hash(img, err)` | FNV-1a 64 over the cropped plane (u16 and f32). |
| `rs_free` | Release (NULL-safe). |
| `rs_ensure_meta(err)` | Parse the singleton database now (timing seam). |
| `rs_meta_parse_count()` | Process parse count (singleton probe). |
| `rs_decode_count()` / `rs_probe_count()` | Successful pixel decodes / fast probes in this process (B3-0b; engine whole-path pins +1/+1). |
| `rs_info_size()` / `rs_error_size()` / `rs_classify_for_test(s, m)` | Test seams: struct-size pins, error-mapping pin. |

The B2-a `rs_thumb` / `rs_free_bytes` placeholder pair is **removed** in
B2-b (header, shim, and FFI declarations): rawspeed at the pinned commit
exposes no thumbnail API at all (verified: no `thumbnail`,
`ThumbDataType`, or `decodeThumbnail` anywhere under
`external/rawspeed/src/`), so thumbnails live in pure Rust (§8) and a C
entry would only ferry file bytes nowhere.

**Exception discipline** (three classes): `rs_open`/`rs_decode` catch
`bad_alloc` (→6) + `std::exception` (→`classify`) + `...` (→9);
`rs_fill_info`/`rs_mosaic_hash`/`rs_ensure_meta` catch `std::exception`/`...`
→ `INTERNAL` (their `bad_alloc` lands on INTERNAL, undistinguished);
`rs_mosaic_u16`/`rs_mosaic_f32` degrade any throw to NULL; the rest
(`rs_free`/`rs_meta_parse_count`/`rs_decode_count`/`rs_probe_count`/
`rs_info_size`/`rs_error_size`/`rs_classify_for_test`) need no `try` (pure
getters over `noexcept` accessors). `rs_probe` catches like `rs_decode`
(same stage mapping) plus `INTERNAL` for its shape/crop guards;
`rs_probe_supported` catches everything to 0 (fall back). Nothing C++
crosses the boundary; corrupt input is a code, never an abort. The handle
owns the file bytes, so the spike's `RawDecoder` buffer-lifetime caveat
does not apply.

**OpenMP waits**: the shim defaults `OMP_WAIT_POLICY` to `passive` (blocking
waits) unless the user set it — libomp's default spin makes bursty decode
latency swing with machine load (measured 68–186 ms active vs 65–105 ms
passive on the 61 MP gate file; see `B2a-REPORT.md` §timing). Set in
`getMeta`, the choke point before any OpenMP region.

## 3. Rust wrapper (`lightamer-decode`)

- `RawImage::open` → `decode` → `metadata()` / `mosaic()` /
  `mosaic_hash()`; `decode_file` does all four. `unsafe` lives only in
  `ffi` (declarations) plus one documented `unsafe` block per extern call in
  `image`; handles are `Send` but not `Sync`.
- `RawImage::probe_metadata` (B3-0b) answers the same [`RawMetadata`]
  without pixels on ARW shapes and falls back to `decode` + `metadata`
  elsewhere; `pipe_image` / `DecodedImage::pipe_input` (`pipe.rs`) turn it
  into pipe facts / the mono float frame (`input_space = Raw`).
- `Mosaic::U16(Vec<u16>)` / `F32(Vec<f32>)`: owned cropped planes, pitch
  removed. `RawMetadata` carries every field below; absent fields are `None`
  by construction (see §5).
- `RawImage` keeps the source path so `metadata()` can merge EXIF optics
  (B2-b; rawspeed exposes none). Optics are best-effort: absent or corrupt
  EXIF leaves the fields `None` and never fails the call.

## 4. Error codes

| Code | Name | Human sentence | Typical trigger |
|---|---|---|---|
| 1 | `NotFound` | file missing or unreadable | bad path |
| 2 | `NotRaw` | not a supported RAW file | random bytes, CR3 (no decoder at pin) |
| 3 | `UnknownCamera` | camera unknown to the camera database | unsupported body (mapping-tested; no fixture) |
| 4 | `Truncated` | file is truncated or empty | empty / cut / header-only |
| 5 | `DecompressFailed` | RAW decompression failed | corrupt payload |
| 6 | `OutOfMemory` | out of memory | `bad_alloc` |
| 7 | `UnsupportedCompression` | compression not supported | unknown codec tag (mapping-tested) |
| 8 | `ThumbnailUnavailable` | embedded thumbnail not available | thumb-less file (Rust layer) |
| 9 | `Internal` | internal decode error | null handle, broken DB, unknown |
| 10 | `UnsupportedFormat` | unsupported file format | non-raster bytes or camera RAW in the raster path, CMYK/palette/sub-8-bit (Rust layer; the C ABI never emits it) |

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
| exposure, aperture, focal, lens, capture time, orientation | EXIF via `kamadak-exif` (TIFF/JPEG direct, RAF through its embedded preview's APP1); `None` when absent (§7) |
| WB kelvin/tint | **Always `None`**: no standard EXIF tag carries them (vendor makernotes do; out of scope) |

## 6. CLI probe

```sh
cargo run -p lightamer-cli -- decode --dump <file> [--thumb <out>] [--repeat N]
```

Prints one `key: value` line per field plus `meta_ms`, `decode_ms_cold`
(first decode, meta pre-loaded), `decode_ms_hot` (last of `--repeat N`),
and `meta_parse_count`. Raster files print the raster block (`kind`,
`width`, `height`, `bit_depth`, `components`, `icc`) plus the same EXIF
optics lines. Routing is by magic bytes, never by extension: JPEG/PNG
magic goes raster-only, TIFF magic tries rawspeed first and falls back to
raster, anything else goes RAW-only (CR3 lands on `NotRaw`).
Developer tool only: it never touches the engine. Exit 2 with the typed
message on decode failure.

`--thumb OUT` writes the embedded thumbnail bytes to `OUT` and reports
`thumbnail_format` (jpeg/raw), `thumbnail_bytes`, `thumbnail_decodable`,
`thumbnail_dims`, and `thumbnail_written`. Files without a supported
thumbnail print `thumbnail: unavailable (<typed message>)` and still
exit 0 (the dump itself succeeded). B15's embedded fast path uses this
as its probe.

## 7. EXIF optics (`exif.rs`)

`read_exif(path)` reads shutter, aperture, focal length, lens model,
capture time (`DateTimeOriginal`, verbatim), and orientation. TIFF-based
files and JPEGs parse directly; RAF parses through its embedded preview
(bytes 84/88, big-endian offset/length, SOI-verified); anything else
yields empty fields. Only a file that cannot be opened errors
(`NotFound`); absent or corrupt EXIF is empty fields, never an error.
Body/lens serial numbers are deliberately not read (no consumer yet).

## 8. Embedded thumbnails (`thumbnail.rs`)

`read_thumbnail(path)` returns `Thumbnail::Jpeg { bytes }` (verbatim file
bytes, SOI-verified) or `Thumbnail::Raw { width, height, components,
bits_per_sample, pixels }` (uncompressed strips concatenated). TIFF
selection: smallest SOI-verified JPEG (`513`/`514`) across the main IFD
chain wins; otherwise the first small uncompressed RGB/gray image marked
reduced (`NewSubfileType` 254 == 1) wins — the marker keeps a plain small
raster from mispassing as its own thumbnail. RAF returns its embedded
preview. `jpeg_dimensions` proves JPEG decodability (headers only).
Observed fixtures: ARW 9405 B 160x120, NEF 10807 B 160x120, RAF 4016595 B
4416x2944, DNG raw 256x171 RGB8.

## 9. Raster decoding (`raster.rs`)

`decode_raster(path)` sniffs JPEG/PNG/TIFF by magic and lands every raster
in `RasterImage` (width, height, components 1/2/3/4, bit depth 8/16,
chunky pixels, ICC profile when present). JPEG is 8-bit gray/RGB
(`zune-jpeg` normalizes to RGB unless asked, so gray takes a second
Luma-output pass); PNG/TIFF cover 8/16-bit gray/gray-alpha/RGB/RGBA.
ICC comes from JPEG APP2, PNG iCCP, and TIFF tag 34675. Only the first
TIFF IFD is read. Camera RAWs never decode here: TIFFs with DNG markers
(50706/50708/50721), old-JPEG compression (6), or CFA photometric are
rejected with `UnsupportedFormat` on the EXIF parse, ahead of the `tiff`
decoder (camera IFDs fail `tiff::Decoder::new` outright — ARW/NEF IFD0
carries no width/height tags — so the check cannot live behind it).

## 10. Known unsupported

- **CR3**: this rawspeed pin ships no CR3 decoder (`decoders/` has no
  `Cr3Decoder`), so Canon-mirrorless RAW fails cleanly with `NotRaw` on
  the main path. Out of B2 scope; re-pinning or a fallback path is a
  later decision.
- **JPEG APP1 thumbnails**: supported by no path (offsets need TIFF-base
  adjustment the EXIF crate does not expose); JPEG files report
  `ThumbnailUnavailable`.
- **Sub-8-bit / palette / CMYK rasters**: rejected with
  `UnsupportedFormat` (typed, documented, tested at the PNG-palette arm).
- **Floating-point TIFFs**: rejected with `UnsupportedFormat`.
- **WB kelvin/tint**: always `None` (§5).

## 11. Tests

- `tests/parity.rs`: 3 fixtures vs `rs-oracle` (direct rawspeed API, same
  static lib, built into `OUT_DIR`): width/height/black/white/WB/mosaic-hash
  plus decoder containment.
- `tests/robustness.rs`: 5 corrupt inputs in one process → their codes, then
  a valid decode proves survival.
- `tests/cache.rs`: double-run bit identity; parse count stable across three
  decodes; 20× decode RSS growth < 32 MiB (`ps` sampling).
- `tests/exif.rs` (B2-b): ARW/NEF/RAF optics vs independent `mdls` values;
  EXIF-less file yields empty optics without error; corrupt inputs never
  abort; `decode_file` fills the B2-a-empty fields.
- `tests/thumbnail.rs` (B2-b): ARW/NEF/RAF JPEG thumbs vs independently
  probed offsets/lengths/dims; DNG uncompressed pixels (bytes equal the
  file range at the probed strip offset); plain PNG/TIFF absence is typed;
  corrupt inputs never abort.
- `tests/raster.rs` (B2-b): synthesized PNG/TIFF round-trips pixel-exact
  (8/16-bit gray/RGB/RGBA); synthesized JPEGs decode with right geometry
  (lossy: bounded, not exact); ICC round-trips on all three containers;
  CC0 previews match `sips` dims; truncated rasters report `Truncated`;
  camera RAWs (ARW/NEF/RAF/DNG/CR3) are rejected from the raster path.
- Unit: error display/round-trip, mapping table, 3x3 inverse, FFI size pin,
  bundled-XML existence, `Send` pin.
- CLI: `apps/lightamer-cli/tests/decode_dump.rs` — fields, `--thumb OUT`,
  `--repeat`, corrupt exit 2, raster dump, raster thumb absence, CR3,
  flag validation.
