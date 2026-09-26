# Project Research — Architecture (Lightamer)

## Summary

Lightamer is a **direct-render, non-destructive RAW editor** organized around three
orthogonal axes: (1) a **Capture One Session** folder model for photo organization,
(2) a **Darktable-style pixelpipe** — a multi-resolution, cache-backed DAG of image
operation (iop) modules dispatched to Metal compute shaders — for pixel processing,
and (3) a **SwiftUI shell** hosting an `MTKView` editor viewport bridged via
`NSViewRepresentable`. The central architectural insight borrowed from Darktable is
that interactive performance on 100MP+ images is achieved not by any single trick
but by the *composition* of: a small preview pixelpipe (low-res, always-current),
a full pixelpipe (region-of-interest at zoom level), per-module per-ROI result
caching keyed on a param hash, tiling fallback when a buffer exceeds GPU memory,
and a fast-path "drag = preview-pipe-only" mode. Mapping this to Swift/Metal means
the OpenCL `process_cl`/`dt_opencl_enqueue_kernel_2d` pattern becomes a Metal
`MTLComputeCommandEncoder` dispatch, the `dt_dev_pixelpipe_t` struct becomes a Swift
`PixelPipe` actor, and the `dt_iop_module_t` plugin API becomes a Swift protocol
with associated `Params: Codable & Hashable`.

---

## Darktable Reference Architecture

The following is distilled from a deep read of the Darktable C source at
`/Volumes/UNITEK/Documents/Development/darktable`. File/line references are given
as `src/...:line`. The goal is to faithfully port the *architecture* (not the C
code) to Swift/Metal.

### Pixelpipe (multi-resolution)

A "pixelpipe" is Darktable's central abstraction: an ordered chain of iop module
*instances* through which a buffer flows, producing processed pixels.
`src/develop/pixelpipe.h:41-62` defines **five pipe types** via a bitmask enum:

| Pipe type | Purpose | Resolution | When used |
|-----------|---------|-----------|-----------|
| `FULL` | Darkroom main view | ROI at current zoom (1:1 near pixel when zoomed in) | Interactive editing |
| `PREVIEW` | Always-current low-res thumbnail + histogram/scopes | ~1080px long edge | Dragging sliders (fast feedback) |
| `PREVIEW2` | Second window / pinned image | as preview | Color assessment 2nd display |
| `THUMBNAIL` | Lighttable grid + export thumbnails | fixed sizes | Folder browsing, export |
| `EXPORT` | Final full-res output | full image | Export to file |

Critically, `FULL | PREVIEW | PREVIEW2` are grouped as `DT_DEV_PIXELPIPE_SCREEN`
(`pixelpipe.h:49`) — the pipes that feed the screen — and the bitmask lets a module
declare "I only run on screen pipes" or "export only" via `operation_tags_filter`.

The pipe struct (`pixelpipe_hb.h:161-265`) holds: input buffer + dimensions, the
`GList *nodes` (one `dt_dev_pixelpipe_iop_t` per active module instance), a
`dt_dev_pixelpipe_cache_t cache`, color profile info (input/work/output/export),
a `backbuf` (the final output back-buffer with a hash for change detection), a
`shutdown` atomic stopper (`pixelpipe_hb.h:138-146`), and `devid` (the OpenCL
device locked for this pipe).

**How it achieves interactive rates** — the recursive core is
`_dev_pixelpipe_process_rec()` (`pixelpipe_hb.c:1838`). It walks modules *backwards*
from the last to the first, and for each module:

1. **Hash-check the cache first** (`pixelpipe_hb.c:1893-1921`): computes
   `dt_dev_pixelpipe_cache_hash(roi_out, pipe, pos)` and if a cacheline matches,
   returns the cached buffer immediately — skipping all upstream reprocessing.
   The hash incorporates imgid, pipe type, the module's params hash, ROI, and
   color profile state (`pixelpipe_cache.c:99-120`).
2. **Early-exit on shutdown** (`pixelpipe_hb.c:1924`): if the user dragged a slider
   mid-render, the atomic `shutdown` stopper (`STOP_NODES`/`STOP_DATA`/`STOP_ZOOM`)
   aborts the stale render.
3. **Recurse** to get the module's input, then dispatch to CPU `process()`,
   OpenCL `process_cl()`, or tiled variants (see tiling section).

The key consequence: when you drag exposure, only modules *after* exposure in the
chain are invalidated; everything upstream (rawprepare, demosaic, lens...) is a
cache HIT and runs in microseconds. The preview pipe (low-res) re-runs near-instantly;
the full pipe (zoomed ROI) follows. This dual-pipe + per-module-cache design is the
foundation of 60fps dragging and is the single most important pattern to replicate.

### iop Module System

Each iop (image operation) module is a dynamically-loaded plugin implementing the
contract in `src/iop/iop_api.h`. The `dt_iop_module_t` struct
(`imageop.h:170-303`) carries: `op` (string id), `iop_order` (float position in the
chain), `instance`/`multi_priority` (for multi-instance), `params`/`default_params`
(the `Codable & Hashable` equivalent), `blend_params`, and the loaded `so` (shared
object). The API surface that matters for Lightamer:

- **`name()` / `default_group()` / `flags()`** — identity & metadata. Flags
  (`imageop.h:84-110`) include `SUPPORTS_BLENDING`, `ALLOW_TILING`,
  `TILING_FULL_ROI`, `ONE_INSTANCE`, `FENCE` (can't be reordered past),
  `WRITE_DETAILS` (emits a scharr detail mask), `ALLOW_FAST_PIPE`.
- **`default_colorspace()` / `input_colorspace()` / `output_colorspace()` /
  `blend_colorspace()`** (`iop_api.h:108-138`) — each module declares the color
  space it operates in; the pipe auto-inserts colorspace conversions between
  mismatched modules (see Color Management below).
- **`init()`** (must set `params_size`), **`reload_defaults()`** (after RAW loaded,
  e.g. to read camera WB or noise profile from EXIF), **`commit_params()`** (copies
  GUI params into the pipe piece under mutex — this is the params→pipe bridge).
- **`modify_roi_out()` / `modify_roi_in()`** (`iop_api.h:209-227`) — the ROI
  negotiation. `modify_roi_out` is a forward pass (input→output size, e.g. crop
  shrinks, lens expands); `modify_roi_in` is the backward pass (given desired
  output ROI, what input ROI is needed? — e.g. a blur needs a wider input).
  This is how the pipe computes the minimal region to process.
- **`process()`** (REQUIRED, CPU), **`process_cl()`** (OPTIONAL, OpenCL), and
  **`process_tiling()` / `process_tiling_cl()`** (auto-generated defaults unless
  overridden). Plus **`distort_transform()` / `distort_backtransform()`** for
  geometric modules (so masks and pickers can be mapped back through the chain).

**Module ordering** is defined in `src/common/iop_order.c`. The canonical current
order is `v50_order` (`iop_order.c:298-415`), a fixed sequence with float positions.
The skeleton (abbreviated):

```
1.0  rawprepare      → 2.0 invert → 3.0 temperature → 4.0 highlights
5.0  cacorrect       → 6.0 hotpixels → 7.0 rawdenoise
8.0  demosaic        ← boundary: RAW Bayer/X-Trans → RGB
9.0  denoiseprofile  → ... → 13.0 lens → 14.0 hazeremoval → 15.0 ashift
16.0 flip            → 17.0 clipping → 18.0 liquify → 19-20 spots/retouch
21.0 exposure        → 23-24 tonemap/toneequal → 24.5 crop
26.0 profile_gamma   → 27.0 equalizer
28.0 colorin         ← boundary: camera RGB → working RGB (scene-referred)
28.5 channelmixerrgb/diffuse/negadoctor/primaries → 29 nlmeans → 30 colorchecker
32-35 atrous/lowpass/highpass/sharpen (frequential)
39-46 channelmixer/basicadj/colorbalance*/rgb curve/levels/basecurve/filmic*/sigmoid/agx
47-58 colisa/tonecurve/levels/shadhi/zonesystem/.../velvia/vibrance
60-69 colorzones/bloom/.../grain/splittoning/vignette/colorreconstruct
70.0 colorout        ← boundary: working RGB → display/export RGB
76.0 borders         → 77.0 watermark → 78.0 gamma ← final display gamma
```

This order is **load-bearing**: the comments in `iop_order.c` explain *why* each
module sits where it does (e.g. `demosaic` must come before any RGB op;
`colorin` must precede anything interpreting color; `nlmeans` wants the most
scene-referred signal possible; `colorout` and `gamma` are terminal). Lightamer
should adopt this exact ordering verbatim — it encodes decades of hard-won
domain knowledge and is required for Darktable sidecar round-tripping.

**History stack** (`develop.h:34-49`): a `dt_dev_history_item_t` is a snapshot of
{module, enabled, params blob, blend_params blob, op_name, iop_order,
multi_priority, multi_name, forms (mask snapshot), num}. The history is an
ordered `GList`; `history_end` is a cursor into it (so you can undo by moving the
cursor). Each parameter change either *merges* into the top item (if same module,
within a focus window — `gui_previous_time`/`focus_hash` in `develop.h:172-176`)
or *pushes* a new item. This is the non-destructive edit log. The whole stack is
what gets serialized to the sidecar (see XMP section).

### Tile/Chunk Processing

For images too large to fit in GPU (or even host) memory at full resolution,
Darktable falls back to **tiling** (`src/develop/tiling.c` + `tiling.h`). Each
module declares its memory footprint via the `tiling_callback`:

```c
typedef struct dt_develop_tiling_t {
  float factor;       // host mem as multiple of input buffer size
  float factor_cl;    // GPU mem as multiple of input buffer size
  float maxbuf;       // max temp buffer as multiple of input size (host)
  float maxbuf_cl;    // ... (GPU)
  unsigned overhead;  // fixed extra bytes (independent of buffer)
  unsigned overlap;   // pixels of overlap needed between tiles
  unsigned align;     // tile position alignment requirement
} dt_develop_tiling_t;
```

The dispatcher (`tiling.c` `default_process_tiling_cl` / `process_tiling`) computes
a tile grid: given the available GPU/host memory budget and the module's
`factor_cl`, it solves for tile dimensions such that `tile_w * tile_h * bpp *
factor_cl + overhead ≤ available_mem`, with `overlap` added to each tile (and
`align` honored). Each tile is processed independently via the module's `process_cl`,
with results written into the correct region of the output. The `_maximum_number_tiles()`
ceiling (`tiling.c:81-84`, 10000 normally, ~1 billion in "unrestricted" resource
mode) prevents pathological blowups.

The decision of *whether* to tile happens in `_dev_pixelpipe_process_rec`
(`pixelpipe_hb.c:2628`): if the full-res buffer doesn't fit on GPU
(`dt_tiling_piece_fits_host_memory` returns false) AND the module is
`process_tiling_ready`, the tiled path is taken; otherwise it falls back to CPU
`process()`. This graceful three-tier fallback (GPU direct → GPU tiled → CPU) is
essential for 100MP+ images and must be preserved in the Metal mapping.

### OpenCL → Metal Mapping

Darktable's OpenCL integration (`src/common/opencl.c`, ~4300 lines) follows a clean
pattern that maps almost 1:1 to Metal compute:

1. **Per-module global init** (`init_global`): each module compiles its kernel(s)
   once via `dt_opencl_create_kernel(program, "kernel_name")`
   (`exposure.c:755`) and stores the handle in `global_data`.
   In Metal this becomes a precompiled `library.makeFunction("exposure")` returning
   an `MTLFunction`, cached in the module's `GlobalState`.
2. **Per-pipe-piece data** (`init_pipe` / `commit_params`): the module allocates a
   `piece->data` struct holding *derived* values computed from params (e.g. exposure
   precomputes `scale = powf(2, exposure)` and `black` in `_process_common_setup`).
   This is the "params → uniform buffer" step. In Metal, `piece->data` becomes an
   `MTLBuffer` (shared/private) bound as a kernel argument.
3. **Dispatch** (`process_cl`): the canonical shape is
   (`exposure.c:540`):
   ```c
   err = dt_opencl_enqueue_kernel_2d_args(devid, gd->kernel_exposure, width, height,
       CLARG(dev_in), CLARG(dev_out), CLARG(width), CLARG(height),
       CLARG(d->black), CLARG(d->scale));
   ```
   This is literally a Metal `dispatchThreadgroups:threadsPerThreadgroup:` with
   the args set via `encoder.setBuffer(...)`. The `dt_opencl_enqueue_kernel_2d`
   helper (`opencl.c:2803`) computes a 2D grid sized to `width×height` with a
   default local size (typically 16×16 or device-tuned) — directly analogous to
   Metal's threadgroup size.
4. **Synchronization** (`dt_opencl_finish_sync_pipe`, `opencl.c:1749`): after a
   module's kernels finish, the pipe flushes the command queue so the next module
   can read the output. In Metal this is the `endEncoding()` + optional
   `commit` on a blit barrier between dependent encoders within a single
   `MTLCommandBuffer`.
5. **Kernel source**: `.cl` files live in `data/kernels/` (e.g. `basic.cl`), built
   at runtime with on-disk binary caching keyed on an MD5 of source + device
   (`opencl.c:2433 _opencl_build_program`). For Metal, kernels are `.metal` files
   compiled at **build time** into the default Metal library (no runtime compile
   needed) — this is simpler and faster than Darktable's runtime build.

**Concrete translation table:**

| Darktable (OpenCL) | Lightamer (Metal) |
|---|---|
| `dt_opencl_create_kernel(prog, "name")` | `library.makeFunction("name")` (cached) |
| `cl_mem dev_in/dev_out` | `MTLBuffer` or `MTLTexture` (`.storageMode = .private` for GPU-local) |
| `piece->data` (derived params) | `MTLBuffer` (`.storageMode = .shared`) bound per-dispatch |
| `dt_opencl_enqueue_kernel_2d_args` | `encoder.dispatchThreadgroups(_:threadsPerThreadgroup:)` |
| `dt_opencl_finish_sync_pipe` | `encoder.endEncoding()` + barrier / new encoder |
| `data/kernels/foo.cl` | `Sources/foo.metal` in app bundle |
| `factor_cl` tiling budget | same algorithm vs `device.maxBufferLength` / `recommendedMaxWorkingSetSize` |

### Color Management Pipeline

Darktable's color pipeline is explicit and module-gated (not a single global
conversion). The flow (`colorin.c` / `colorout.c`, `common/colorspaces.c`):

```
RAW sensor data (camera-native RGB, after demosaic)
   │  [colorin module, iop_order 28.0]
   │   reads input ICC profile (embedded or from camera matrix in colormatrices.c),
   │   converts camera RGB → working profile (default: linear Rec2020 RGB, scene-referred)
   ▼
Working RGB (linear, scene-referred)  ← all "RGB" modules operate here
   │  [all the creative/tone/color iops: exposure, filmic, colorbalance, ...]
   │  (Lab modules auto-convert RGB↔Lab via the pipe's colorspace negotiation)
   ▼
[colorout module, iop_order 70.0]
   │   converts working RGB → output profile:
   │     - darkroom: display profile (from ColorSync in our case)
   │     - export: chosen export profile (sRGB/AdobeRGB/Display-P3/...)
   │     - preview2: 2nd-display profile
   ▼
Display/export RGB (gamma-encoded)
   │  [gamma module, iop_order 78.0]  — final sRGB-ish gamma for screen
   ▼
8-bit pixel data → MTLTexture / file
```

The pipe carries four `dt_iop_order_iccprofile_info_t` slots
(`pixelpipe_hb.h:182-188`): `input_profile_info`, `work_profile_info`,
`output_profile_info`, `export_profile_info`. Each module's
`input_colorspace()`/`output_colorspace()` declares its expectation, and
`dt_ioppr_transform_image_colorspace` (`iop_order.c`) auto-inserts conversions
when adjacent modules disagree — e.g. a Lab module sandwiched between RGB modules
gets automatic RGB→Lab→RGB wraps. The conversion uses either a precomputed matrix
(fast path, `matrix_in`/`matrix_out` in the iccprofile_info) or falls back to
LittleCMS2 (`force_lcms2` path in `colorout.c:559,711`) for soft-proofing or
non-matrixable profiles.

**For Lightamer:** Core Image's `CIColorSpace` and `CGColorSpace` + the system
ColorSync profile database replace Darktable's bundled `colormatrices.c` + lcms2.
The working space should be linear Rec2020 RGB (matching Darktable's modern
default for round-trip compatibility). Display profile comes from
`NSScreen.colorSpace` automatically. Soft-proofing maps to
`CGColorConversionInfo` with a proofing intent.

### Sidecar (.xmp) Format

Darktable stores **all** non-destructive edit data in an XMP sidecar
(`<rawname>.<ext>.xmp`) sitting beside the original, plus a SQLite DB mirror for
fast queries. The XMP is written by `src/common/exif.cc` (via Exiv2). The
structure (from `_set_xmp_dt_history`, `exif.cc:4796`, and the key list at
`exif.cc:418-433`):

```xml
<xmpMM:.../>                       <!-- standard XMP MM: DocumentID, InstanceID -->
<exif:EXIF.../>                    <!-- round-tripped EXIF -->
<xmp:.../>                         <!-- standard XMP: dc, iptc -->
<darktable:xmp_metadata>           <!-- DT version, raw params, aspect ratio -->
<darktable:masks_history>          <!-- RDF Seq of mask forms (drawn masks) -->
  <rdf:Seq><rdf:li>
    darktable:mask_num, mask_id, mask_type, mask_name, mask_version,
    mask_points (base64), mask_nb, mask_src (base64)
  </rdf:li></rdf:Seq>
<darktable:history>                <!-- THE edit history stack -->
  <rdf:Seq><rdf:li>
    darktable:num                  <!-- position in stack -->
    darktable:operation            <!-- e.g. "exposure" -->
    darktable:enabled              <!-- 0/1 -->
    darktable:modversion           <!-- params struct version (for legacy_params) -->
    darktable:params               <!-- BASE64 of the raw params struct blob -->
    darktable:multi_name           <!-- user instance name -->
    darktable:multi_name_hand_edited
    darktable:multi_priority       <!-- multi-instance ordering -->
    darktable:blendop_version
    darktable:blendop_params       <!-- BASE64 of blend params blob -->
  </rdf:li></rdf:Seq>
<darktable:history_end>            <!-- cursor: how many of the seq are "active" -->
<darktable:iop_order_version>      <!-- v30 / v50 / etc -->
<darktable:iop_order_list>         <!-- serialized module ordering -->
<darktable:colorlabels>            <!-- star rating + color tags -->
<darktable:history_basic_hash>     <!-- hash for change detection -->
<darktable:import/change/export_timestamp>
<crs:RawFileName, crs:...>         <!-- Adobe CRW-style keys, for LR interop -->
```

**Critical detail:** the `darktable:params` value is a **base64 encoding of the raw
in-memory C struct** (`dt_exif_xmp_encode` of `sqlite3_column_blob(op_params)`).
This is binary, versioned via `modversion`, and upgraded via each module's
`legacy_params()` on read (`iop_api.h:228`). For Lightamer to round-trip with
Darktable, the sidecar writer must emit the *same binary layout* for each shared
module's params. This is the single hardest interop constraint and the reason the
iop params structs should mirror Darktable's field order/size where
round-tripping is a goal (v1 can target read-only or a subset).

Rating/metadata: `darktable:xmp_metadata` + `xmp:xmpRating` + `darktable:colorlabels`.
The sidecar is also where masks live (`masks_history`) — each mask "form"
(circle/brush/path/gradient) is a blob of control points.

### Mipmap/Thumbnail Cache

`src/common/mipmap_cache.c` + `mipmap_cache.h`. Darktable maintains a **multi-tier
image cache** so the lighttable grid and the darkroom preview never re-decode RAWs:

- **`DT_MIPMAP_0` … `DT_MIPMAP_10`** (`mipmap_cache.h:28-49`): 8-bit RGB,
  progressively larger thumbnail sizes (0 = smallest ~25px, 10 = full-res 8-bit).
  These feed the lighttable grid at any zoom level.
- **`DT_MIPMAP_F`**: float, downsampled (~preview resolution), feeds the preview
  pixelpipe input.
- **`DT_MIPMAP_FULL`**: float, full resolution, feeds the full/export pixelpipe.

Each tier is a separate `dt_cache_t` (`mipmap_cache.h:99-113`) with its own LRU
eviction and a backing disk cache (sha1-named files in `cachedir`). The getter
(`dt_mipmap_cache_get`, flags in `mipmap_cache.h:52-70`) supports best-effort
(return smaller mip if exact missing), prefetch (background job),
prefetch-disk (only if on disk), blocking, and testlock modes. On a cache miss, a
background worker decodes the RAW (via `imageio_rawspeed` / `imageio_libraw`) and
optionitionally runs the thumbnail pixelpipe to apply the edit history at small
size, caching the result.

For Lightamer: this maps to an actor-backed `ThumbnailStore` with the same three
tiers. The 8-bit tiers can leverage Core Image's `CICachedKernel` /
`CIContext.thumbnailImage` for generation; the float tiers hold the CIRAW decoder
output. Disk cache should live under `~/Library/Caches/Lightamer/` keyed on a
content hash of the source file + history hash.

---

## Proposed Lightamer Architecture

### Component Diagram (ASCII)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SwiftUI App Shell                                   │
│  NavigationSplitView: Session sidebar │ Lighttable grid │ Darkroom/editor   │
│  Inspector panels (right) │ Toolbar (top) │ Filmstrip (bottom)              │
└───────────────┬──────────────────────────────────────┬──────────────────────┘
                │ @Observable view models                │ NSViewRepresentable
                ▼                                       ▼
┌──────────────────────────────┐        ┌─────────────────────────────────────┐
│   UI Layer (SwiftUI)         │        │  Viewport Bridge (AppKit/Metal)      │
│  ┌────────────────────────┐  │        │  EditorMTKView: NSViewRepresentable  │
│  │ SessionBrowser         │  │        │   ├─ MTKView (MTLDevice default)     │
│  │ LighttableGrid (grid)  │  │        │   ├─ render callback ← EditorRenderer│
│  │ InspectorPanel (iops)  │  │        │   └─ input events → EditorController │
│  │ HistogramView          │  │        │  BorderWatermarkPanel (yiyin)        │
│  │ HistoryPanel           │  │        └──────────────┬──────────────────────┘
│  │ ExportPanel            │  │                       │
│  └───────────┬────────────┘  │                       │ final MTLTexture
└──────────────┼───────────────┘                       │ (display-profile)
               │ params (Codable)                       │
               ▼                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Application / Domain Layer                            │
│  EditorController (actor): the darkroom orchestrator                         │
│    ├─ owns Develop (history stack, image ref, current iop state)             │
│    ├─ owns 3 PixelPipes: previewPipe, fullPipe, exportPipe                   │
│    ├─ throttled reprocess on param change (debounce → preview first)        │
│    └─ coordinates SessionManager ↔ Develop ↔ Renderer                        │
│  SessionManager: folder watch, Capture/Crop/Output orchestration             │
│  ExportQueue (actor): batch export, multi-spec                               │
└───────────────┬──────────────────────────────────────┬──────────────────────┘
                │                                       │
       ┌────────┴─────────┐                     ┌───────┴────────┐
       ▼                  ▼                     ▼                ▼
┌─────────────┐   ┌────────────────┐   ┌──────────────┐  ┌──────────────┐
│ Session     │   │  PixelPipe     │   │ RAW Decode   │  │ Metal Kernel │
│ Subsystem   │   │  (actor/struct)│   │ Layer        │  │ Dispatch     │
│             │   │                │   │ (CIRAW 9)    │  │ (MTLDevice)  │
│ FolderWatch │   │  nodes:[IOPiece]│  │ CIImage→     │  │ library,     │
│ SidecarIO   │   │  cache:        │   │  float buffer│  │ pipelines,   │
│  (.xmp r/w) │   │   PipeCache    │   │  / MTLBuffer │  │ encoder      │
│ Capture/    │   │  roi negotiate │   │              │  │ factory      │
│  Crop/      │   │  tiling fallback│  │ EXIF/metadata│  │              │
│  Output mgr │   └───────┬────────┘   └──────┬───────┘  └──────┬───────┘
│ Thumbnail/  │           │ chain dispatch     │ raw float       │ kernels
│  MipmapCache│           └────────────────────┼─────────────────┘
└─────────────┘                                │
       │                                       │
       ▼                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     iop Module System (plugins)                              │
│  protocol IOPModule { associatedtype Params: Codable, Hashable               │
│    func process(input: MTLBuffer/Texture, output:, piece:, roi:)             │
│    func modifyROIOut / modifyROIIn / commitParams / reloadDefaults ... }      │
│  Instances: rawprepare, demosaic, temperature, exposure, colorin, colorout,  │
│    filmicrgb, colorbalancergb, ..., borders, watermark, gamma                │
│  Each ships a .metal kernel file; registered in a ModuleRegistry             │
└─────────────────────────────────────────────────────────────────────────────┘
        │                  │                  │                 │
        ▼                  ▼                  ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌────────────────┐  ┌──────────────┐
│ Color Mgmt   │  │ Mask System  │  │ Blend System   │  │ System Integ │
│ (ColorSync + │  │ (drawn forms,│  │ (blend modes,  │  │ Spotlight,   │
│  CGColorSpace│  │  raster,     │  │  opacity,      │  │ Quick Look,  │
│  + working   │  │  detail)     │  │  parametric    │  │ EDR/HDR,     │
│  Rec2020)    │  │              │  │  mask)         │  │ ColorSync    │
└──────────────┘  └──────────────┘  └────────────────┘  └──────────────┘
```

**Data flow arrows (top→bottom = high→low level):**
- User drags slider → SwiftUI binding → `EditorController.paramChanged(module, params)`
- Controller debounces (≈16ms) → sets `previewPipe` dirty → preview pipe re-runs
  (low-res, ~10ms) → new preview texture → histogram + viewport update (60fps)
- Controller schedules `fullPipe` re-run (ROI at zoom) → after preview settles
- On release/major change → `SidecarManager.write(history)` (debounced autosave)

### Component Boundaries

**1. RAW Decode Layer** (`Sources/RAW/`)
- *Responsibility:* Given a file URL, produce a float RGB(A) buffer in camera-native
  color space, plus metadata (EXIF, CFA pattern, camera make/model, black/white
  levels, color matrix, lens profile, noise profile).
- *Implementation:* Thin wrapper over Core Image RAW 9 (`CIFilter.filter(withName: "CIRAWFilter")`
  / `CIImage(contentsOf: url, options: [.applyOrientationProperty: true])` +
  `CIRAWFilter` properties). Where CIRAW 9 is insufficient (some demosaic
  algorithms, advanced denoise profiles), fall back to a Metal compute path fed by
  the raw Bayer buffer (accessible via `CIRAWFilter`'s `RAWImage`/`linearSpaceFilter`
  or by reading the raw bytes via `ImageIO`/`CGImageSource` for unsupported sensors).
- *Interfaces:* `protocol RAWDecoder { func decode(_ url: URL) async throws -> RAWImage }`
  where `RAWImage` holds the float buffer (or `CIImage` lazy), dimensions, Bayer
  pattern, color matrix, and EXIF dict.
- *Boundary note:* This is the **highest-risk** component (CIRAW 9 capability
  boundaries). It must expose both the high-level "decode to RGB" *and* the
  low-level "give me the raw mosaic + metadata" so the demosaic iop can choose.

**2. PixelPipe** (`Sources/Pipeline/`)
- *Responsibility:* Hold the ordered chain of iop instances for one image; given a
  target ROI and scale, produce the processed output buffer by recursively walking
  modules, consulting the per-module cache, and dispatching to Metal.
- *Core types:*
  - `PixelPipe` (Swift `actor` or class with internal locks): owns `nodes: [IOPiece]`,
    `cache: PipeCache`, `input: PixelBuffer`, profile slots, `backbuf`.
  - `IOPiece`: per-instance state — `module: any IOPModule`, `enabled`,
    `paramsHash`, `processedROIIn/Out`, derived `data` (MTLBuffer uniforms),
    `dscIn/dscOut` (buffer format/colors), histogram.
  - `PipeCache`: array of cachelines keyed on `(imgid, pipeType, position, roi, hash)`.
- *Interfaces:* `func process(roi: ROI, scale: Float) async -> PixelBuffer`;
  `func invalidate(fromOrder: Float)`; `func setNodes(_ history: [HistoryItem])`.
- *Critical:* the recursive `processRec` + hash-cache-hit-fast-path must be ported
  faithfully — this is where the 60fps comes from.

**3. iop Module System** (`Sources/IOP/`)
- *Responsibility:* Define the plugin protocol and host all module implementations.
- *Protocol:*
  ```swift
  protocol IOPModule {
      associatedtype Params: Codable, Hashable
      static var opName: String { get }
      static var iopOrder: Float { get }          // from v50_order table
      static var flags: IOPFlags { get }
      static var defaultColorspace: ColorSpace { get }

      func reloadDefaults(image: RAWImage) async -> Params
      func commitParams(_ params: Params, into piece: inout IOPiece)
      func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPPiece)
      func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece)
      func process(input: PixelBuffer, output: PixelBuffer,
                   roiIn: ROI, roiOut: ROI, piece: IOPiece, device: MTLDevice) async throws
      // optional:
      func processTiling(...)                      // if ALLOW_TILING
      func distortTransform / distortBacktransform // if geometric
  }
  ```
- *Registry:* a compile-time (or launch-time) `ModuleRegistry` maps `opName →
  IOPModule.Type`, used to instantiate from history/sidecar. The order table is a
  single source of truth (`iop_order.swift` mirroring `v50_order`).
- *Each module* lives in its own file (`Exposure.swift` + `Exposure.metal`) and
  owns its Metal function lookup.

**4. Metal Kernel Dispatch** (`Sources/Metal/`)
- *Responsibility:* Own the `MTLDevice`, the default `MTLLibrary`, a pool of
  `MTLCommandQueue`s, and provide ergonomic dispatch helpers.
- *Interfaces:*
  ```swift
  actor MetalContext {
      func function(_ name: String) -> MTLFunction
      func makeBuffer<T>(_ value: T) -> MTLBuffer          // uniforms
      func dispatch2D(function:, inputs:, threads: width×height)
  }
  ```
- *Mapping:* replaces `dt_opencl_*` entirely. Kernels are `.metal` files compiled
  at build time. Buffers prefer `.private` storage for intermediates, `.shared`
  for uniforms and final readback.

**5. Session Subsystem** (`Sources/Session/`)
- *Responsibility:* Implement the Capture One Session model: a folder is a session;
  auto-maintain `Capture/` (ingest), `Crop/` (working copies / sidecars), `Output/`
  (exports). Watch the folder for new files. Manage sidecar `.xmp` read/write.
- *Components:*
  - `SessionStore`: list of sessions, recent sessions, current session.
  - `FolderWatcher` (`DispatchSource.makeFileSystemObjectSource` / FSEvents): new
    RAW in `Capture/` → import → queue thumbnail generation + sidecar init.
  - `SidecarManager`: serialize/deserialize `darktable:history` to/from `.xmp`.
    Must produce byte-compatible `params` blobs for round-tripping (hard goal, v1
    can subset).
  - `MipmapCache` / `ThumbnailStore`: three tiers as in Darktable.
- *Boundary:* Session is orthogonal to the pixelpipe — it just feeds image refs
  and persists params. The darkroom never touches the filesystem directly except
  through SidecarManager.

**6. Viewport Bridge** (`Sources/Viewport/`)
- *Responsibility:* The single AppKit/Metal touchpoint in an otherwise SwiftUI app.
- *Components:*
  - `EditorMTKView: NSViewRepresentable` wrapping `MTKView`.
  - `EditorRenderer: NSObject, MTKViewDelegate` — on `draw(in:)`: blit the pipe's
    `backbuf` MTLTexture into the view's drawable, apply zoom/pan transform,
    draw overlays (crop guides, masks) via a Metal render pipeline or Core
    Graphics overlay.
  - Input routing: mouse/scroll/magnify → `EditorController` for zoom/pan/mask
    editing.
- *Boundary:* This is the *only* place `MTKView` lives. Everything else is SwiftUI.
  Keep it thin — no business logic.

**7. Border/Watermark (yiyin) Subsystem** (`Sources/BorderWatermark/`)
- *Responsibility:* The internalized yiyin panel — white borders, date/EXIF
  overlays, logo watermark, custom fonts. Implemented as *two terminal iop modules*
  (`borders` at order 76, `watermark` at order 77, matching Darktable) plus a
  SwiftUI panel.
- *Port from yiyin:* layout algorithm (Swift), EXIF extraction (`ImageIO` /
  `exiftool`-free `CGImageSource` properties), font management (`CoreText`),
  compositing (Metal compute or Core Image). Output parameters align with yiyin's
  for feature parity; the yiyin repo stays independent.

**8. Export Subsystem** (`Sources/Export/`)
- *Responsibility:* Render to final files. Uses the `EXPORT` pixelpipe (full res,
  chosen output profile, no caches needed). Batch queue with multi-spec
  (one source → many size/format/watermark combos).
- *Encoders:* JPEG/PNG/TIFF/HEIF/WebP/AVIF via `CGImageDestination` (ImageIO) +
  AVIF via system codec where available.
- *Queue:* actor-based, serial or bounded-parallel, cancellable, progress reporting.

**9. System Integration** (`Sources/System/`)
- *Spotlight:* a Spotlight importer extension indexing session photos (rating,
  keywords, EXIF) via `CSSearchableItem`.
- *Quick Look:* a `QLPreviewProvider` extension rendering edited thumbnails
  (runs a thumbnail pixelpipe).
- *ColorSync/HDR:* honor `NSScreen.colorSpace`, support EDR
  (`NSScreen.maximumExtendedDynamicRangeColorComponentValue`) for HDR displays
  when the working/display profile allows.
- *Color management bridge:* `CGColorSpace` ↔ internal `ColorSpace` enum; the
  `colorout` module reads `NSScreen.colorSpace` directly.

---

## Data Flow

### A pixel's journey: RAW file → displayed MTLTexture

```
[1] RAW file on disk (e.g. _DSC0001.ARW in Session/Capture/)
     │
     │ FolderWatcher detects new file (or user opens session)
     ▼
[2] RAW Decode Layer: CIRAWFilter produces CIImage (lazy) + metadata.
     On demand (cache miss): render to float buffer in camera-RGB.
     │  ┌─ CACHED: MipmapCache tier MIPMAP_FULL (float, full-res)
     │  │           and MIPMAP_F (float, preview-res)
     │  └─ DISK CACHE: ~/Library/Caches/Lightamer/<sha1>
     ▼
[3] Develop loads history from sidecar (.xmp) → [HistoryItem] list.
     History applied: each item instantiates an IOPModule + Params.
     │
     ▼
[4] PixelPipe.buildNodes(history) → ordered [IOPiece] per v50_order.
     │  ┌─ For PREVIEW pipe: input = MIPMAP_F buffer (downsampled)
     │  └─ For FULL pipe: input = MIPMAP_FULL buffer, ROI = visible zoom region
     ▼
[5] User drags Exposure slider.
     │  EditorController.paramChanged → previewPipe.invalidate(fromOrder: 21.0)
     ▼
[6] previewPipe.process(roi, scale):
     recurse backwards through nodes:
       for each module: hash = (imgid, pipeType, pos, paramsHash, roi)
         ├─ CACHE HIT  → return cached buffer (upstream skipped)
         └─ MISS       → recurse for input, then:
              commitParams → uniforms MTLBuffer
              dispatch module.process() → Metal compute kernel
              ├─ if fits GPU:       direct process_cl equivalent
              ├─ if too big:        processTiling (grid of tiles)
              └─ if GPU fails:      fallback CPU process()
              write result into PipeCache cacheline
     output = final float buffer in working RGB
     │
     ▼
[7] colorout module: working RGB → display profile (from NSScreen.colorSpace)
     gamma module: → 8-bit sRGB-ish for screen
     │  ┌─ CACHED: backbuf hash (so static view doesn't re-run)
     ▼
[8] EditorRenderer.draw(in: view.currentDrawable):
     blit backbuf MTLTexture → drawable, apply zoom/pan (vertex transform),
     draw overlays (crop frame, mask preview, guides).
     │
     ▼
[9] MTKView presents drawable (60fps).
```

### A pixel's journey: → exported file

```
[1] User: Export → chooses specs (JPEG sRGB 2048px + watermark, TIFF AdobeRGB full).
     ▼
[2] ExportQueue.enqueue(image, specs[]).
     ▼
[3] For each spec (parallel, bounded):
     exportPipe = PixelPipe(type: .export, width/height per spec)
       input = MIPMAP_FULL (or re-decode if needed)
       nodes = history up to history_end (or chosen subset)
       output profile = spec.profile (sRGB/AdobeRGB/...)
     │
     ▼
[4] exportPipe.process(fullImageROI, scale: spec.scale):
     same recursion as display pipe, but:
       - no backbuf cache needed (single pass)
       - colorout → spec.outputProfile (not display)
       - borders + watermark modules active (terminal, before gamma)
     │
     ▼
[5] CGImageDestination writes encoded bytes (JPEG/TIFF/HEIF/...).
     EXIF + XMP packet embedded (round-tripped + edited metadata).
     ▼
[6] File lands in Session/Output/<spec.name>/.
     Sidecar updated with export_timestamp.
```

### Where non-destructive params live

- **Source of truth:** the in-memory `Develop.history: [HistoryItem]` array,
  owned by `EditorController` (actor-isolated).
- **Persisted mirror:** the `.xmp` sidecar beside the RAW (written by
  `SidecarManager` on debounce, ≈1s after last change, and on image switch).
- **Runtime bridge:** `commitParams` copies each module's `Params` into the
  corresponding `IOPiece.data` (uniforms). The pipe never mutates `Develop.history`;
  the GUI never touches `IOPiece.data` directly.

### Cache points (in priority order)

1. **PipeCache (per-module, per-pipe):** the big one — avoids re-running upstream
   modules when only a late module changed. Keyed on params hash.
2. **backbuf (per-pipe final):** avoids re-running the whole pipe on a pure
   zoom/pan with no param change.
3. **MipmapCache (per-image, cross-pipe):** avoids re-decoding RAWs. Tiers F and
   FULL feed the pipes.
4. **Disk thumbnail cache:** survives app restarts.
5. **Color matrix cache:** input/work/output ICC profile matrices precomputed once.

---

## Concurrency Model

Darktable uses a fixed thread pool (`dt_control_t.thread_res`, `control.h:193-195`)
with reserved "worker resources" (`DT_CTL_WORKER_RESERVED`, e.g. one for the full
pipe, one for preview, one for export) plus a general job queue, and a signal bus
(`DT_CONTROL_SIGNAL_RAISE`) for cross-component notification. For Lightamer, use
**Swift Concurrency** (actors + structured tasks) which maps cleanly:

```
┌─────────────────────────────────────────────────────────────┐
│ Main Actor (SwiftUI)                                        │
│   - all @Observable view models, bindings, view updates     │
│   - never blocks on rendering                               │
└──────────────────────────┬──────────────────────────────────┘
                           │ await (isolated hops)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ EditorController (actor)                                    │
│   - owns Develop (history)                                  │
│   - single source of truth for "current image + params"     │
│   - throttles reprocess requests (debounce 16ms)            │
│   - coordinates preview vs full pipe priority               │
└───────┬───────────────────────┬──────────────────┬──────────┘
        │                       │                  │
        ▼ Task                  ▼ Task             ▼ Task
┌─────────────────┐   ┌──────────────────┐  ┌────────────────┐
│ previewPipe     │   │ fullPipe         │  │ exportQueue    │
│ (serial actor)  │   │ (serial actor)   │  │ (actor,        │
│  low-res, fast  │   │  zoom ROI, heavy │  │  bounded N)    │
│  ~10ms target   │   │  ~50-200ms       │  │                │
└────────┬────────┘   └────────┬─────────┘  └────────┬───────┘
         │ dispatches          │ dispatches          │ dispatches
         ▼                     ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│ MetalContext (actor)                                        │
│   - owns MTLDevice, MTLCommandQueue pool                    │
│   - serializes command buffer submission per device         │
│   - separate command buffers per pipe (parallel-safe)       │
└─────────────────────────────────────────────────────────────┘

Background (detached Tasks, low priority):
  - ThumbnailStore generation (MipmapCache misses)
  - SidecarManager disk writes (debounced)
  - FolderWatcher (DispatchSource / FSEvents callback → Task)
  - Spotlight/QuickLook indexing
```

**Key patterns:**

1. **PixelPipe as serial actor:** each pipe processes one render at a time. If a
   new param change arrives mid-render, the controller raises the pipe's
   `shutdown` flag (atomic, like Darktable's) and the current render aborts at the
   next module boundary; a fresh render starts immediately. This is the
   "cancel-and-restart" pattern critical for 60fps dragging.
2. **Coalescing param changes:** the `EditorController` debounces slider input —
   during an active drag, only the preview pipe re-runs (cheap); the full pipe is
   deferred until the drag ends (or a longer idle timer). Mirrors Darktable's
   `DT_DEV_PIXELPIPE_FAST` flag + `gui_previous_time` merge logic.
3. **Pipe invalidation granularity:** `invalidate(fromOrder:)` only dirties
   cachelines at or after the changed module's `iopOrder` — upstream modules stay
   valid. This is the direct port of `cache_obsolete_order`
   (`pixelpipe_hb.h:165`, used in `develop.c:2804-2822`).
4. **Metal command buffer isolation:** each pipe gets its own `MTLCommandBuffer`
   per frame so GPU work is parallelizable across pipes; the `MetalContext` actor
   serializes only the enqueue, not the execution.
5. **Export queue:** an actor with a semaphore-bounded worker set (default
   `ProcessInfo.processInfo.activeProcessorCount`). Each export runs its own
   ephemeral `PixelPipe(type: .export)` — fully independent of the editor pipes.
6. **No locks on the GUI thread:** SwiftUI reads `@Observable` snapshots; the
   controller publishes immutable snapshot structs (history, current params) that
   the GUI renders without awaiting the actor.

---

## Suggested Build Order

The order below is dependency-driven: each phase unblocks the next. Skipping ahead
(e.g. building UI before the pipe renders) creates throwaway work.

### Phase 0 — Foundation Skeleton (weeks)
- Xcode project, macOS 14+ target, Swift 6 concurrency.
- `MetalContext` actor: device + library + dispatch2D helper. A trivial
  pass-through kernel that copies a buffer (proves the Metal path end-to-end).
- `RAWImage` + `RAWDecoder` protocol; CIRAW 9 wrapper that decodes a CR3/NEF/ARW
  to a float `CIImage` / `MTLBuffer`. **Resolve the CIRAW 9 capability question
  here** (which demosaics, noise profiles, lens corrections it covers) — this
  determines the v1 iop scope.
- `PixelPipe` skeleton: `nodes: [IOPiece]`, recursive `processRec` with a
  no-op pass-through, *no cache yet* (just prove the chain runs).
- `EditorMTKView` (NSViewRepresentable) + `EditorRenderer` that blits a static
  texture to screen. SwiftUI shell with a single "open image" button.
- **Exit:** Open a RAW, see it on screen (unprocessed, but via Metal). This is
  the architectural vertebra — every later phase plugs into this skeleton.

### Phase 1 — Pixelpipe Core (the hard part)
- `PipeCache`: cachelines + hash function (`(imgid, pipeType, pos, roi, paramsHash)`).
- The recursive `processRec` with cache-hit fast path and ROI negotiation
  (`modifyROIOut`/`modifyROIIn` forward/backward passes to compute dimensions).
- `IOPModule` protocol finalized; `ModuleRegistry`.
- The **terminal trio**: `colorout` (working→display via `NSScreen.colorSpace`),
  `gamma` (display gamma), and a minimal `rawprepare` (black level subtract +
  white balance scale) as the head. These three + a passthrough demosaic prove
  the full chain with caching.
- **Exit:** Open a RAW, get correct color on screen; re-opening is instant (cache).

### Phase 2 — First Real iops + Preview Pipe
- Split into `previewPipe` (low-res) + `fullPipe` (zoom ROI). Wire the
  debounce/coalesce logic in `EditorController`.
- Implement the foundational iops with Metal kernels (these cover ~80% of user
  value): `exposure`, `temperature` (white balance), `clipping`/`crop`,
  `flip`, `tonecurve`, `levels`, `sharpen`, `colorbalance` (or `basicadj` as a
  v1 stand-in), `denoiseprofile` (even a simple version).
- `HistoryStack` + undo/redo + the merge-vs-push focus logic.
- Histogram (read from preview pipe `gamma` input).
- **Exit:** A usable basic editor — open, adjust exposure/WB/crop/tone, see
  60fps dragging, undo/redo works.

### Phase 3 — Session Model + Sidecar
- `SessionStore`, `FolderWatcher`, Capture/Crop/Output directory management.
- `SidecarManager`: write/read `.xmp`. **Decision point:** how much Darktable
  binary-blob compatibility to target in v1 (recommend: emit readable XMP
  structure, but params as a Lightamer-native `Codable` JSON-in-base64 first;
  add Darktable-binary-blob compat as a later milestone once params structs
  stabilize).
- Rating, color labels, keywords (metadata panel).
- Lighttable grid view (SwiftUI `ScrollView`/`Grid`) fed by `ThumbnailStore`.
- `MipmapCache` three-tier thumbnail store + background generation.
- **Exit:** Full Capture-One-style session workflow with persistent non-destructive
  edits across launches.

### Phase 4 — Export
- `EXPORT` pixelpipe variant.
- `ExportQueue` actor + multi-spec.
- Format encoders via `CGImageDestination` (JPEG/PNG/TIFF/HEIF/WebP); AVIF if
  system codec available.
- Watermark/border application during export (even before the full panel exists,
  a basic version).
- **Exit:** Batch export works, files land in `Output/`.

### Phase 5 — Advanced iops (long arc)
- The full Darktable parity set, prioritized by user value:
  `filmicrgb`, `colorbalancergb`, `sigmoid`/`agx` (tone mappers);
  `lens` (lensfun-equivalent — may need a lens DB; v1 can lean on CIRAW's lens
  correction); `ashift`; `cacorrect`; `hazeremoval`; `nlmeans`/`bilateral`;
  `retouch`/`spots`; `liquify`; `colorchecker`; `channelmixerrgb`; `colorequal`;
  LUT3d (`.cube` import — required for Darktable preset interop); masks (drawn +
  raster + detail/scharr); blend modes + parametric masks.
- Tiling fallback path (only needed once modules exceed GPU memory — likely
  triggered by 100MP + heavy modules like nlmeans).
- **This phase is open-ended** — it's the "long-term Darktable parity" goal.

### Phase 6 — Border/Watermark (yiyin) Panel
- Port yiyin's layout algorithm + EXIF overlay + font management to Swift/CoreText.
- Implement as `borders` (iop order 76) + `watermark` (iop order 77) modules.
- SwiftUI panel matching yiyin's UX; output parity with yiyin CLI.

### Phase 7 — System Integration & Polish
- Spotlight importer extension.
- Quick Look preview extension (runs thumbnail pixelpipe).
- EDR/HDR display support.
- Soft-proofing (ColorSync proofing intent in `colorout`).
- Localization (String Catalog, zh/en).
- Before/after split, snapshots, preset system (`.dtstyle` + `.cube` interop),
  copy/paste edits across images.

---

## Key Architectural Decisions to Lock Early

These are expensive to change later (they thread through every component):

1. **Working color space = linear Rec2020 RGB (scene-referred).** Matches
   Darktable's modern default, enables round-tripping, and is the mathematically
   correct scene-referred space. Locking this early avoids re-tuning every iop's
   math. (Decision: Linear Rec2020, NOT Lab, as the primary working space — Lab
   is used only inside specific modules via auto-conversion.)

2. **Pipe buffer format = float32 RGBA, premultiplied alpha, in working space.**
   Decide once whether modules see 3-channel (RGB) or 4-channel (RGBA) and at
   what precision. Darktable uses float, 3 or 4 channels depending on stage;
   Lightamer should standardize on **float32 RGBA** throughout the pipe (simpler,
   Metal-native, supports masks in alpha). Changing this post-hoc rewrites every
   kernel.

3. **iop module ordering = Darktable v50_order, verbatim.** Adopt the exact float
   positions so (a) sidecar round-tripping works, (b) the decades of ordering
   rationale apply, (c) multi-instance `multi_priority` semantics match. Lock the
   `iop_order.swift` table in Phase 0.

4. **iop params = `Codable & Hashable` Swift structs, but with a stable binary
   layout for sidecar compat.** The `Hashable` conformance feeds the PipeCache
   hash (required for cache correctness). The binary layout (field order, sizes)
   must mirror Darktable's params struct for any module targeting XMP round-trip.
   Use a custom `BinaryCodable` protocol for those modules; pure-Swift modules
   can use default `Codable`. Decide the params encoding strategy before writing
   the second module.

5. **Metal, not Core Image, for the pipe core.** CIRAW is the *decode* layer and
   may supply *some* iops (lens correction, basic demosaic), but the pixelpipe's
   per-module chain must be Metal compute for the caching/tiling/dispatch model
   to work. Core Image's own DAG doesn't expose the per-node caching and ROI
   control Darktable's design relies on. Lock: pipe = Metal; CIRAW = decoder +
   optional individual iop implementations.

6. **EditorViewport is the only `NSViewRepresentable`.** All other UI is pure
   SwiftUI. This contains the AppKit boundary to one file and lets the rest of
   the app use SwiftUI idioms (bindings, `@Observable`, animations).

7. **`EditorController` is an actor and the single mutation authority for
   history.** No other component mutates the history stack directly. This
   prevents the race conditions that plague interactive editors. The GUI talks
   to it via `await` and renders immutable snapshots.

8. **Sidecar = `.xmp` beside the RAW, autosaved (debounced), AND no central
   catalog DB in v1.** The Capture One Session model means the folder *is* the
   source of truth. A DB (for fast queries/filtering) can be a *derived* cache
   later, but must never be authoritative — otherwise backup/migration/git
   semantics break. Lock: sidecar-primary, DB-optional-derived.

9. **Minimum macOS version = macOS 14 (Sonoma).** Justified by: Metal 3
   (`MTLEvent`, untracked resources, mesh shaders), SwiftUI maturity
   (`NavigationSplitView`, `@Observable`), CIRAW 9 availability. macOS 15 adds
   HDR/EDR conveniences but isn't required. Revisit if telemetry shows the
   target machine runs older.

10. **Module flags protocol = port Darktable's `IOP_FLAGS_*` bitfield.** The
    flags (`SUPPORTS_BLENDING`, `ALLOW_TILING`, `FENCE`, `WRITE_DETAILS`, etc.)
    drive generic pipe behavior (auto-insert blend, tiling fallback, ordering
    fences, detail mask generation). Inventing a different taxonomy will break
    the 1:1 module mapping. Lock the flag set in Phase 0.

---

## Sources

### Darktable source (read in depth)
- `src/develop/pixelpipe.h` — pixelpipe types (`DT_DEV_PIXELPIPE_*`), `dt_iop_roi_t`, display-mask enum.
- `src/develop/pixelpipe_hb.h` — `dt_dev_pixelpipe_t`, `dt_dev_pixelpipe_iop_t` (piece), shutdown stopper enum, status/change enums.
- `src/develop/pixelpipe_hb.c` — `_dev_pixelpipe_process_rec` (recursive core, line 1838), cache-hit fast path (1893), OpenCL/tiling/CPU dispatch (2550-2750), early-exit (1924).
- `src/develop/develop.h` — `dt_develop_t`, `dt_dev_history_item_t`, viewports, chroma tracking, distort-transform API.
- `src/develop/develop.c` — `dt_dev_process_image_job` (606), reprocess/invalidation (2784-2825), history add/pop, average-delay throttling.
- `src/develop/imageop.h` — `dt_iop_module_t` (170), `dt_iop_module_so_t` (141), `dt_iop_flags_t` (84).
- `src/iop/iop_api.h` — full module API contract (`process`, `process_cl`, `tiling_callback`, `modify_roi_*`, `commit_params`, `distort_*`, `legacy_params`).
- `src/develop/tiling.h` / `tiling.c` — `dt_develop_tiling_t` (factor/factor_cl/maxbuf/overlap/align), `default_process_tiling_cl`, tile-grid solver.
- `src/develop/pixelpipe_cache.c` — `dt_dev_pixelpipe_cache_init`, basichash composition (99-120), cacheline LRU.
- `src/common/iop_order.c` — `v50_order` canonical module ordering (298-415), JPEG variant, order-version upgrade paths.
- `src/iop/exposure.c` — reference `process_cl` (523) + `init_global` kernel compile (750) + CPU `process` (552); the cleanest example of the CPU/GPU dual path.
- `src/iop/colorin.c` / `colorout.c` — color pipeline boundaries, input/work/output profile resolution, lcms2 fallback, `process_cl`.
- `src/common/opencl.c` — `dt_opencl_create_kernel`, `dt_opencl_enqueue_kernel_2d` (2803), `dt_opencl_finish_sync_pipe` (1749), `_opencl_build_program` (2433).
- `src/common/exif.cc` — `_set_xmp_dt_history` (4796), XMP key list (418-433), `dt_exif_xmp_encode` base64 blob, history read `_read_history_v1` (3559).
- `src/common/mipmap_cache.h` / `.c` — `dt_mipmap_size_t` tiers (0-10, F, FULL), `dt_mipmap_cache_t`, get-flags (best-effort/prefetch/blocking).
- `src/imageio/imageio.c` — `dt_imageio_export_with_flags` (1045): EXPORT pixelpipe init, style application, format/storage dispatch.
- `src/control/control.h` / `jobs.c` — worker thread pool, reserved resources, job queue.
- `data/kernels/basic.cl` — OpenCL kernel source pattern (`kernel void ...`).

### Apple framework references (to consult during implementation)
- Core Image RAW (`CIFilter` `CIRAWFilter`, `CIImage(contentsOf:options:)`) — RAW decode capability boundary.
- Metal (`MTLDevice`, `MTLComputeCommandEncoder`, `MTKView`, `MTLLibrary`) — compute + viewport.
- SwiftUI (`NavigationSplitView`, `@Observable`, `NSViewRepresentable`) — shell + bridge.
- ColorSync (`CGColorSpace`, `CGColorConversionInfo`, `NSScreen.colorSpace`) — color management.
- ImageIO (`CGImageSource`, `CGImageDestination`) — encode/decode + EXIF.
- CoreText — font management for border/watermark.

### Project context
- `/Volumes/UNITEK/Documents/Development/Lightamer/.planning/PROJECT.md` — requirements, constraints, key decisions.
