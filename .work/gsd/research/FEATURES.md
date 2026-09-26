# Project Research — Features (Lightamer)

> Dimension: **FEATURES**. Companion to STACK.md (Core Image RAW 9 / Metal boundary), ARCH.md (pipeline),
> and UX.md (Darkroom/Lighttable patterns). This doc enumerates *what* to build and how to triage it.

## Summary

The pro RAW-editor feature landscape splits cleanly into three piles for Lightamer. **Table stakes** are
solved problems every editor has (RAW decode, exposure/WB/curves, non-destructive history, rating, export) —
Lightamer differentiates here only on *speed* (Metal at 100MP), not on feature existence. **Differentiators**
are the unique-to-Lightamer combinations: Capture One Session workflow + Darktable-grade iop depth + integrated
yiyin border/watermark + Darktable preset/LUT interop, all native macOS — no incumbent offers this combo.
**Anti-features** are things Lightamer deliberately refuses (Lightroom catalog, cloud, AI auto-tagging, mobile,
Windows/Linux) because they either conflict with the Session philosophy or dilute the native-Metal value prop.

Darktable's full iop set is **91 registered modules** (verified against `src/iop/CMakeLists.txt`), grouped
below into 9 functional categories. Core Image RAW 9 (CIRAW 9, WWDC26 Session 305) directly covers only a
thin slice (~8-10 modules: demosaic, exposure, WB, luminance NR, sharpen, contrast, lens geometry, baseline
curves/levels) — the remaining ~80 must be Metal compute shaders ported from Darktable's C/C++. yiyin exposes
~20 border/watermark parameters that become the spec for Lightamer's internal panel.

---

## Darktable iop Module Inventory

Source: `/Volumes/UNITEK/Documents/Development/darktable/src/iop/` (build `nightly-496-gdc58cf0ba1`).
91 modules registered in `CMakeLists.txt` via `add_iop(...)`. Descriptions extracted from each module's
`dt_iop_set_description(self, _("..."), ...)` call. **CIRAW 9 covers?** is a best-effort guess — the Stack
research owns the definitive boundary.

Legend — Complexity: L=low (matrix/threshold/curve), M=medium (convolution/histogram op), H=high
(iterative/ML/multi-pass/geometry-solve). CIRAW: ✓=direct, ~=partial/needs Metal assist, ✗=must self-implement.

### Tone / Exposure / Display Transform

| Module | What it does | Complexity | CIRAW 9 |
|---|---|---|---|
| `exposure` | Exposure (EV), black level, highlight rolloff | L | ✓ |
| `tonecurve` | Per-channel (L/a/b) tone curve | L | ~ (CIRAW has curves, not Lab) |
| `rgbcurve` | Per-channel RGB tone curve | L | ~ |
| `levels` | Black/white/mid-gray points (Lab) | L | ~ |
| `rgblevels` | Black/white/mid-gray points (RGB) | L | ~ |
| `toneequal` | Exposure by lightness bin (relight scene) | M | ✗ |
| `colisa` | Contrast/brightness/saturation (legacy simple) | L | ✓ (contrast) |
| `basicadj` | "Usual adjustments" — 6 basic sliders | L | ✓ |
| `shadhi` | Shadows/highlights separate | M | ✗ |
| `graduatednd` | Graduated neutral density filter | L | ✗ |
| `relight` | Relight via tone curve + edge mask | M | ✗ |
| `zonesystem` | Zone-system (Ansel Adams) exposure mapper | L | ✗ |
| `bilateral` | Local/global contrast split (bilateral filter) | M | ✗ |
| `bilat` | Local contrast (Clarity) — bilateral | M | ✗ |
| `clahe` | CLAHE local contrast | M | ✗ |
| `globaltonemap` | Global tone mapping (Reinhard etc.) | M | ✗ |
| `tonemap` | Tone mapping (Durand-Dorsey bilateral) | M | ✗ |
| `sigmoid` | Display-referred sigmoidal transform | M | ✗ |

### Filmic / Scene-Referred Pipeline (the modern DT core)

| Module | What it does | Complexity | CIRAW 9 |
|---|---|---|---|
| `filmicrgb` | Scene-referred filmic curve — *the* DT tone mapper | H | ✗ |
| `filmic` | Legacy single-channel filmic | M | ✗ |
| `agx` | AgX display transform (industry-standard look) | H | ✗ |
| `basecurve` | Display-referred base curve (legacy/Auto-Magic) | M | ✗ |
| `sigmoid` (also above) | RGB scene-referred sigmoid | M | ✗ |

### Color / White Balance / Grading

| Module | What it does | Complexity | CIRAW 9 |
|---|---|---|---|
| `temperature` | White balance (raw RGB channel scale) | L | ✓ |
| `colorcorrection` | Legacy WB for blacks/whites | L | ~ |
| `colorbalance` | Color shift by luminance range (shadows/mid/high) | M | ✗ |
| `colorbalancergb` | Modern color balancer (6-way + chroma) | H | ✗ |
| `colorequal` | Per-hue color equalizer | H | ✗ |
| `colorharmonizer` | Harmonize colors toward a palette | M | ✗ |
| `colorzones` | Hue/chroma/lightness by hue zone | M | ✗ |
| `channelmixer` | RGB channel mixer | L | ✗ |
| `channelmixerrgb` | Modern color-calibrated channel mixer | H | ✗ |
| `primaries` | RGB primaries adjustment (color grading) | M | ✗ |
| `velvia` | Velvia/film saturation boost | L | ✗ |
| `vibrance` | Vibrance (smart saturation) | L | ✗ |
| `colorcontrast` | Saturation contrast (a/b spread) | L | ✗ |
| `colorize` | Solid color overlay | L | ✗ |
| `monochrome` | B&W conversion with color filter | M | ✗ |
| `colormapping` | Map colors from a source image | H | ✗ |
| `colortransfer` | Transfer color palette between images | H | ✗ |
| `colorchecker` | X-Rite ColorChecker calibration | H | ✗ |
| `colorin` | Input color profile (ICC) — *mandatory* | M | ✗ (needs ICC pipeline) |
| `colorout` | Output color profile (ICC) — *mandatory* | M | ✗ |
| `profile_gamma` | Correct non-linear input profiles | M | ✗ |

### Detail / Sharpen / Local Contrast

| Module | What it does | Complexity | CIRAW 9 |
|---|---|---|---|
| `sharpen` | UnSharp Mask sharpen | L | ✓ |
| `atrous` | À trous wavelet local contrast/sharpness | M | ✗ |
| `highpass` | High-pass filter (isolate high freq) | M | ✗ |
| `lowpass` | Low-pass filter (isolate low freq) | M | ✗ |
| `equalizer` | Wavelet edge-aware equalizer | H | ✗ |
| `diffuse` | Anisotropic diffusion (sharpen/denoise blend) | H | ✗ |

### Denoise / Reconstruction

| Module | What it does | Complexity | CIRAW 9 |
|---|---|---|---|
| `denoiseprofile` | Profiled denoise (sensor noise profile) | H | ~ (CIRAW has luma NR only) |
| `rawdenoise` | Legacy raw denoise | M | ✗ |
| `nlmeans` | Non-local means denoise | M | ✗ |
| `highlights` | Highlight reconstruction (clipped recovery) | M-H | ✗ |
| `colorreconstruct` | Recover clipped highlight colors | M | ✗ |
| `hotpixels` | Hot/stuck pixel removal | L | ✗ |
| `rawprepare` | Raw prep (black/sub/scale) — *mandatory* | L | ✓ (internal) |
| `demosaic` | Demosaic dispatcher (AMaze/PPG/VNG/etc.) | H | ✓ (Core ML on ANE) |

### Geometry / Lens / Perspective

| Module | What it does | Complexity | CIRAW 9 |
|---|---|---|---|
| `lens` | Lens correction (Lensfun distortion/vignette/CA) | M | ~ (lens geometry only) |
| `cacorrect` | Chromatic aberration (Bayer) | M | ✗ |
| `cacorrectrgb` | Chromatic aberration (RGB, post-demosaic) | M | ✗ |
| `defringe` | Edge-desaturate CA fringe | L | ✗ |
| `clipping` | Crop + perspective (keystone) reframe | M | ~ (crop only) |
| `crop` | Simple crop | L | ~ |
| `enlargecanvas` | Canvas enlargement (add margin) | L | ✗ |
| `flip` | Flip/rotate 90° | L | ✓ |
| `ashift` | Auto straighten / vanishing-point perspective | H | ✗ |
| `rotatepixels` | Rotate arbitrary angle | L | ✗ |
| `scalepixels` | Scale image | L | ✗ |
| `liquify` | Liquify/warp (point-based mesh distortion) | H | ✗ |
| `finalscale` | Final pipeline scale to output | L | ✓ (internal) |

### Local / Masking (region-restricted edits — applies to most of the above)

| Module | What it does | Complexity | CIRAW 9 |
|---|---|---|---|
| `mask_manager` | Mask container (drawn/parametric/raster) | M | ✗ (framework) |
| `rasterfile` | Load PFM/PNG as raster mask | L | ✗ |
| `retouch` | Healing/cloning/blur brush (wavelet) | H | ✗ |
| `spots` | Sensor-dust spot removal | L-M | ✗ |

### Effects / Creative

| Module | What it does | Complexity | CIRAW 9 |
|---|---|---|---|
| `borders` | Add solid borders/margins | L | ✗ (Lightamer: yiyin covers this) |
| `vignette` | Lens fall-off / vignette | L | ✗ |
| `grain` | Film grain simulation | M | ✗ |
| `bloom` | Orton effect (dreamy glow) | M | ✗ |
| `soften` | Soft focus (Orton variant) | M | ✗ |
| `splittoning` | Split toning (shadow/highlight tint) | L | ✗ |
| `lowlight` | Night-vision (grain + tint) | M | ✗ |
| `hazeremoval` | Dehaze | M | ✗ |
| `watermark` | SVG watermark overlay | M | ✗ (Lightamer: yiyin covers this) |
| `overlay` | Composite another processed image | M | ✗ |
| `invert` | Invert (positive→negative) | L | ✗ |
| `negadoctor` | Film negative invert + paper sim | H | ✗ |
| `dither` | Dithering (posterize/banding fix) | L | ✗ |
| `lut3d` | Apply 3D LUT (.cube etc.) | M | ✗ (Lightamer: interop target) |
| `censorize` | Blur/censor faces & license plates | M | ✗ |

### Pipeline Internal / Diagnostic (not user-facing features)

| Module | What it does | Complexity | Notes |
|---|---|---|---|
| `gamma` | sRGB display gamma — *mandatory* | L | Internal |
| `overexposed` | Highlight overexposure overlay | L | Diagnostic only |
| `rawoverexposed` | Raw-clipping overlay | L | Diagnostic only |
| `useless` | Placeholder/test module | L | Skip |
| `blurs` | Internal blur kernels | M | Library, not standalone |
| `hlreconstruct/*`, `demosaicing/*` | Algorithm subfolders consumed by `highlights`/`demosaic` | — | Not standalone iops |

**Module count by category:** Tone 17 · Filmic 5 · Color 21 · Detail 6 · Denoise 8 · Geometry 13 · Local 4 · Effects 16 · Internal 6 = **96** (some modules counted in two categories; 91 distinct registered iops).

---

## Darktable Non-iop Features

Source: `src/views/` (6 views), `src/libs/` (40+ lib panels). These are the workflow/organizational layer
around the iop engine.

### Views (`src/views/`)
- **lighttable** — culling, rating, tagging, filtering, collections (no edit). Filesystem/folder-based browsing.
- **darkroom** — single-image editor; iop module stack on right, history on left, image center.
- **tethering** — live tethered capture from camera (gphoto2 backend).
- **map** — GPS map view; geotag images on OpenStreetMap tiles.
- **slideshow** — fullscreen slideshow of selected images.
- **print** — print to physical printer with color-managed soft-proof.

### Lighttable / Organization libs (`src/libs/`)
- **collect** — collections by folder/date/tag/camera/etc.
- **filtering** — query/filter bar (rating, color label, text).
- **image** — thumbnail size/sort controls.
- **select** — select/culling helpers (group, similar, recently-used).
- **import** — from camera/card/folder; import metadata presets.
- **metadata** / **metadata_view** — editable IPTC/XMP metadata (title/desc/creator/rights).
- **tagging** — hierarchical tags, XMP-dct:subject, auto-tag from dict.
- **geotagging** — GPX track → image GPS; location search.
- **recentcollect** — recent collections list.
- **duplicate** — create/edit virtual duplicates (variants sharing the same source).
- **copy_history** — copy/paste full or partial history stack between images (Lightamer: adjustment sync).
- **history** — per-image history stack (every iop op, undo/redo, compress).
- **snapshots** — snapshot points for before/after compare (Lightamer: before/after compare).
- **styles** — apply/save named style = preset history stack (`.dtstyle`).
- **export** — export queue with format/size/metadata presets; export to file/flickr/etc.
- **export_metadata** — control which metadata written on export.
- **session** — tethering session config (capture folder naming, next-capture counter).

### Darkroom libs / Scopes (`src/libs/scopes/`)
- **histogram** — RGB/Lab histogram.
- **waveform** — waveform/parade scope.
- **vectorscope** — chroma vectorscope.
- **split** — split preview overlay (before/after).

### Masks (`src/libs/masks.c` + `src/develop/masks/`)
Three mask types, composable per-iop:
- **drawn** — brush (radius/opacity/hardness/spacing), circle, ellipse, path, gradient, Bezier.
- **parametric** — pixel-wise mask from iop params (e.g. "luminance > X AND hue in Y").
- **raster** — grayscale image mask (PNG/PFM via `rasterfile` iop); user-painted group.
Masks form groups with boolean ops (union/intersection/difference/inversion).

### Pipeline / Workflow architecture
- **Scene-referred workflow** (filmicrgb/colorbalancergb) vs **display-referred workflow** (basecurve).
- **Filmic RGB pipeline** — scene-linear working space, filmic curve at end → display.
- **History stack** — ordered list of (iop, params, mask, enabled) ops; full non-destructive.
- **iop order** — user-reorderable; presets can pin order (`ioporder` lib).
- **module groups** — iops grouped in UI (Basic/Tone/Color/Correct/Effect).

---

## Capture One Session Mode Features

Sources: Capture One official blog "Sessions 101" + support docs. **Session = folder-as-project, not a
central library.** This is Lightamer's chosen model (per PROJECT.md).

### Folder structure (default, user-renameable, all OS-relative)
```
<SessionName>/                ← top project folder (the "session")
├── Captures/                 ← tethered shots land here; default import target
├── Selects/                  ← user-moved keepers (optional)
├── Output/                   ← processed/exported files land here
├── Trash/                    ← session-local trash (deletes stay in project)
└── <SessionName>.cosessiondb ← cache + tracking DB (NOT the source of truth)
```
Each subfolder is **assignable**: right-click any folder → "Set as Capture/Output/Trash folder".
Settings/adjustments are stored **per-image as sidecar files in the Capture subfolder** (`.cos` for C1).
A folder of RAWs + sidecars is fully portable — viewable on any machine **without** the session DB
(the DB is only a cache for search/thumbnails).

### Session vs Catalog (why Session is distinct)
| | Session | Catalog |
|---|---|---|
| Source of truth | **Filesystem folders** + per-image sidecars | **Central SQLite DB** (managed library) |
| Import required | No — click a folder, thumbnails auto-generate | Yes — must import through gatekeeper |
| Settings storage | Sidecar files alongside RAW (modular, portable, backup-friendly) | Inside the catalog DB |
| Best for | Tethered shoots, project-by-project, per-shoot folders | Large growing libraries, cross-shoot search |
| Portability | Copy the folder — works anywhere | Tied to the catalog file |

### Tethered shooting
- Set "Capture folder" → tethered shots stream in immediately on shutter.
- Next-capture naming template (counters, date, session name tokens).
- "Next capture" naming preview + auto-increment.

### Color editing & layers (C1 differentiators Lightamer should absorb)
- **Color Editor** — 3-way (basic/advanced/skin tone) selective color; pick a color, shift hue/sat/lightness.
- **Layers** — local adjustments on masks/layers (brush/gradient + opacity), per-layer adjustments.
- **Export Recipes** — named presets binding (format + size + color space + watermark + output folder);
  multiple recipes export the same source simultaneously.

---

## yiyin (壹印) Feature Inventory

Sources: `/Volumes/UNITEK/Documents/Development/yiyin/` — `README.md`, `package.json`,
`electron/src/interface.ts`, `electron/src/config.ts`, `common/const/def-fields.ts`,
`common/const/def-temps.ts`, `electron/src/modules/image-tool/interface.ts`, `web/util/model-map.ts`.
This is the **complete spec** for Lightamer's internal yiyin panel.

### Global output options (`OutputOption`, `electron/src/config.ts`)
| Param | Type | Default | Meaning |
|---|---|---|---|
| `iot` | bool | false | Output immediately (no queue) |
| `landscape` | bool | false | Force landscape output (portrait→landscape transform) |
| `origin_wh_output` | bool | false | Output at original W×H |
| `solid_bg` | bool | false | Use solid color background (vs blurred-image bg) |
| `solid_color` | string | `#fff` | Solid background color |
| `bg_rate` | {w,h} | {0,0} | Background aspect ratio override (0,0 = auto from main image) |
| `bg_rate_show` | bool | false | Show the bg-ratio control |
| `bg_blur` | number | 100 | Background blur amount (for blurred-image bg) |
| `radius` | number | 2.1 | Main-image corner radius |
| `radius_show` | bool | true | Show corner-radius control |
| `shadow` | number | 6 | Main-image drop-shadow strength |
| `shadow_show` | bool | true | Show shadow control |
| `font` | string | `PingFang SC` | Default font for all text |
| `main_img_w_rate` | number | 90 | Main image width as % of background width |
| `text_margin` | number | 0.4 | Text vertical margin (spacing) |
| `mini_top_bottom_margin` | number | 0 | Minimum top/bottom margin |
| `quality` | number | 100 | Output quality (1-100) |
| `output_format` | `'jpeg' \| 'webp'` | `'jpeg'` | Output format |
| `preview_show` | bool | false | Show preview overlay |

### EXIF fields (`tempFields`, `common/const/def-fields.ts`) — each toggled on/off
| Key | Display | Note |
|---|---|---|
| `PersonalSign` | 个性签名 (personal signature) | Free text |
| `Make` | Logo (brand logo/image) | Often rendered as logo image, not text |
| `Model` | 型号 (camera model) | |
| `LensMake` | 镜头Logo (lens brand logo) | |
| `LensModel` | 镜头型号 (lens model) | |
| `ExposureTime` | 快门 (shutter) | |
| `FNumber` | 光圈 (aperture) | |
| `ISO` | ISO | |
| `FocalLength` | 焦距 (focal length) | |
| `FocalLengthIn35mmFormat` | 等效焦距 (35mm-equiv) | |
| `ExposureProgram` | 档位 (exposure program) | |
| `DateTimeOriginal` | 拍摄日期 (capture date) | |
| `ExposureCompensation` | 曝光补偿 | |
| `MeteringMode` | 测光模式 | |
| `WhiteBalance` | 白平衡 | |

Each field carries a `font: IFontParam` (bold/italic/size/font/caseType/color) + `type: 'text'|'img'` +
light/dark logo images (`bImg`/`wImg`) for `Make`/`LensMake`.

### Templates (`temps`, `common/const/def-temps.ts`)
Template strings with `{Field}` placeholders, e.g.:
- `{Make} {Model}` — logo + model line
- `{FocalLengthIn35mmFormat}mm f/{FNumber} {ExposureTime}s ISO{ISO}` — exif params line
- `{FocalLength}mm f/{FNumber} {ExposureTime}s ISO{ISO}` — original-focal variant

Each template: `key`, `name`, `temp` (string), `use` (bool), `type: 'system'|'custom'`,
`verticalAlign: 'center'|'baseline'`, per-template `font: IFont`, per-template `position: IPosition`.

### Per-font style (`IFont`)
`bold`, `italic`, `size` (relative, e.g. 3 / 2.2), `font` (font name/path), `caseType` (`'lowcase'|'upcase'|'default'`), `color`.

### Per-position (`IPosition`)
`top`, `bottom`, `left`, `right` (null = auto).

### Custom fonts
User uploads `.ttf`/`.otf` → stored in user dir (`font.dir`), tracked in `font.map`. No network.

### Brand/model normalization (`web/util/model-map.ts`)
Per-brand filters that transform raw EXIF Make/Model into display strings:
- Sony `ILCE-7M4` → `α 7m4` (lowercase, α replacement)
- Nikon `Z_6_II` → `ℤ 6 II` (Z→ℤ, Roman numerals)
- Generic: first-letter-cap + rest-lowercase
These normalization rules must be ported to Swift for the Lightamer panel.

### Output pipeline (port spec for Swift/Core Image/Core Text)
1. Decode source (sharp/ImageIO) → get EXIF (exiftool/exifreader).
2. Compute canvas: background size from `bg_rate` (or main-image aspect), apply `bg_blur` or `solid_bg`.
3. Place main image: scaled to `main_img_w_rate`, with `radius` corners + `shadow`.
4. Render each enabled template field as Core Text, positioned per `position`/`verticalAlign`.
5. Apply `landscape` flip if needed; output at `quality`/`output_format`.

**yiyin in Lightamer = re-implement the above in Swift (Core Image for composit, Core Text for text,
ImageIO/AVFoundation for EXIF), UI as a SwiftUI panel. Dual-maintain with the standalone yiyin app.**

---

## Feature Categorization

### Table Stakes (must have — users leave without these)
*Anything every pro RAW editor already does. Lightamer competes on speed/native here, not feature novelty.*

- **RAW decode** for major formats (CR3/NEF/ARW/RAF/RW2/ORF/DNG) + JPEG/HEIC/PNG/WebP/TIFF
- **Non-destructive editing** — ordered history stack, sidecar (.XMP) persistence, never writes source RAW
- **Core tone/color iops**: exposure, white balance, curves, levels, contrast, vibrance — the ~15 modules pros use daily
- **Crop/rotate/flip** + aspect-ratio presets
- **Lens correction** (distortion/CA/vignette) — Lensfun-style database or per-lens
- **Sharpening** + basic **denoise**
- **Highlight/shadow recovery** + highlight reconstruction
- **Histogram** + clipping warnings
- **Before/after compare** (split / snapshot) — *user-confirmed for v1*
- **Rating + color labels + flags** synced to sidecar/XMP — *user-confirmed for v1*
- **Metadata** (IPTC/XMP title/desc/keywords) + **keyword tagging** — *user-confirmed for v1*
- **Export** to JPG/PNG/TIFF/HEIF/WebP/AVIF with resize/quality/color-space — *user-confirmed for v1*
- **Batch export queue** + **multi-spec simultaneous export** — *user-confirmed for v1*
- **Adjustment copy/paste sync** across images — *user-confirmed for v1*
- **Presets/styles** (save/load named adjustment stacks)
- **Spotlight + Quick Look integration** — *user-confirmed for v1*
- **Undo/redo**
- **Color management** (ICC profiles, soft-proof)

### Differentiators (competitive advantage for Lightamer)
*The things no incumbent combines into one native macOS app.*

- **Metal-native at 100MP** — MTKView direct-render, 60fps on GFX100S/A7R V/Phase One. Incumbents (DT) struggle here.
- **Capture One Session workflow** in a native app — folder-as-session, Capture/Crop/Output/Trash, per-image sidecars,
  multi-session switching, recent-sessions list. *No Mac RAW editor offers DT-grade edits in a C1-Session model.*
- **Darktable iop depth** (scene-referred filmic, colorbalancergb, denoiseprofile, wavelet detail, liquify, retouch,
  negadoctor) — matching DT's full ~91-module set as a long-term goal, but v1 ships the daily-15.
- **Integrated yiyin border/watermark panel** — first-class, not a plugin. White border / date / EXIF overlay /
  logo watermark / custom fonts / portrait↔landscape transform, all native Core Image/Core Text.
- **Darktable preset interop** — read/write `.dtstyle`, treat `.cube` LUT as an iop module (DT LUT-module interop).
- **Darktable sidecar interop** — round-trip `.XMP` adjustments with Darktable.
- **Multi-spec simultaneous export** — one source → many (size/format/watermark) outputs in one queue action.
- **Native macOS UX** — SwiftUI panels, gestures, Spotlight/Quick Look, no Electron/Qt/JNI overhead.
- **Open-source + native** — DT is open but C/GTK; C1/Lr are closed. Lightamer fills the open-native gap.

### Anti-features (deliberately exclude — and why)
| Anti-feature | Why excluded |
|---|---|
| **Lightroom-style central catalog** | Conflicts with Session philosophy (folder-as-truth). Per PROJECT.md Out-of-Scope. |
| **Cloud sync / cloud storage** | Personal-use, local-first; adds accounts/infra, conflicts with portable-folder model. |
| **AI auto-tagging / AI scene detection** | Battery/privacy cost; personal-use users tag manually; not core to RAW editing. |
| **iOS / iPadOS companion** | macOS-only (Metal/Core Image/SwiftUI dependency). Out-of-Scope. |
| **Windows / Linux ports** | Depends on Metal/Core Image — fundamental. Out-of-Scope. |
| **Mac App Store / sandbox** | Sandbox blocks arbitrary folder access needed for Session mode. Out-of-Scope. |
| **Account system / subscriptions / login** | Open-source, free, personal-use. Out-of-Scope. |
| **Social sharing / community features** | Not a sharing app; export is the deliverable. |
| **Mobile-camera capture / phone-as-camera** | Tethering targets real cameras; phone workflow is different. |
| **Video editing** | Stills-only RAW editor; yiyin's ffmpeg dep is out-of-scope for Lightamer. |
| **NFT / blockchain / content credentials (C2PA)** | Not requested; scope creep. |

---

## Feature Dependencies

Dependency graph — build bottom-up. A → B means "B depends on A being built first".

```
RAW decode (CIRAW 9 / ImageIO) ─┬─► exposure/WB/curves/levels (table-stakes tone)
                                ├─► demosaic (CIRAW 9 Core ML) ──► all color iops
                                └─► history stack ──┬─► sidecar (.XMP) persistence
                                                    ├─► presets/styles (.dtstyle)
                                                    ├─► adjustment copy/paste sync
                                                    └─► before/after compare (snapshots)

Session model ─┬─► folder watch (Capture/Crop/Output/Trash)
               ├─► sidecar storage (per-image, in-session)
               ├─► multi-session switching + recent list
               └─► export queue ─► multi-spec simultaneous export
                                  └─► output encoders (JPG/PNG/TIFF/HEIF/WebP/AVIF)

Geometry (crop/lens/flip) ──► masking framework (masks operate in image space after geometry)
                            │   └─► drawn masks (brush/path/gradient)
                            │   └─► parametric masks
                            │   └─► raster masks
                            └─► local adjustments (per-iop mask binding)

Lens correction DB ──► CA correction ──► defringe
                   └─► vignette correction

Denoise (denoiseprofile / CIRAW luma NR) ──► sharpen (order matters: denoise before sharpen)

Highlight reconstruction ──► exposure/filmic (must recover before tone-map)

Scene-referred pipeline: demosaic → WB → exposure → colorin(ICC) → [color iops] → filmicrgb → colorout(ICC) → display
                          (each stage depends on the prior; mask framework wraps any stage)

yiyin panel ─► Core Text rendering ─► EXIF extraction (ImageIO)
           ─► Core Image composit ─► output encoders
           ─► font management (custom .ttf/.otf)
           ─► brand/model normalization rules

Export recipes ─► output encoders ─► watermark (yiyin) — recipes bind a yiyin config per recipe

HDR/stacking ─► image alignment ─► blending ─► tonemap (HDR is a cluster of 3 deps before tonemap)

Tethering ─► camera SDK / gphoto-equivalent ─► Session capture folder ─► next-capture naming

Spotlight/Quick Look ─► sidecar (XMP) reader ─► thumbnailer (export-encoder reuse)

LUT iop (.cube) ─► LUT parser ─► Metal 3D-LUT sampler ─► Darktable LUT-module interop
```

**Critical path for v1:** RAW decode → history/sidecar → core tone/color iops → geometry/crop → export
encoders → Session model → yiyin panel → batch queue → rating/metadata → Spotlight/Quick Look.
**Masking can ship in v1.1** — it's a framework that unlocks many iops but v1 ships global-adjustment-only.

---

## Complexity Notes

Hardest clusters (need early spikes / prototypes):

1. **Scene-referred filmic pipeline** (filmicrgb + colorbalancergb + colorin/colorout ICC) — *H*.
   The single hardest port. DT's filmic is ~2000 lines of carefully-ordered scene-linear math.
   Spike: port filmicrgb to a Metal compute shader + validate against DT output on a test image.
2. **Denoise profiling** (denoiseprofile) — *H*. Requires per-sensor noise profiles (variance vs ISO).
   CIRAW 9's Core ML demosaic+denoise may absorb the *demosaic* half, but profiled NR on top is still needed.
   Spike: check if CIRAW 9's `luminanceNoiseReductionAmount` is sufficient for v1, defer DT-equivalent profiling.
3. **Highlight reconstruction** — *M-H*. DT's `highlights` iop has 5+ algorithms (inpaint/laplacian/lch/opposed/segbased).
   v1: ship one (opposed or laplacian). Defer the rest.
4. **Masking framework** — *M* but wide. Drawn/parametric/raster + boolean ops + per-iop binding is a lot of UI.
   v1: ship global adjustments only; v1.1 add drawn brush masks; v1.2 parametric.
5. **Darktable XMP/.dtstyle interop** — *M*. Requires parsing DT's XMP blob and mapping to Lightamer's iop params.
   High value (differentiator) but binary-compat is a moving target. Spike: round-trip a simple history (exposure+WB).
6. **100MP Metal performance** — *H*. MTKView direct-render + tiled GPU pipeline + async preview vs full-res.
   This is the core value prop — must spike early (M1: can we hold 60fps on a 100MP GFX100S file at zoom/pan?).
7. **Liquify + retouch** — *H* each. Mesh warp and wavelet healing are large standalone efforts. Defer to v2+.
8. **yiyin port** — *M*. Core Image compos + Core Text are well-trodden; the layout algorithm and brand
   normalization are the only non-trivial parts. Lower risk than the iop ports.

**Easy wins (ship first):** exposure, WB, curves, levels, crop, flip, sharpen, vignette, basic export,
rating/labels, yiyin panel (white border + EXIF text). These cover most daily-use and all are *L* complexity.

---

## Sources

**Darktable source** (local, `/Volumes/UNITEK/Documents/Development/darktable/`):
- `src/iop/CMakeLists.txt` — 91 registered iop modules (authoritative count).
- `src/iop/*.c` / `*.cc` — per-module `dt_iop_set_description(self, _("..."), ...)` for descriptions.
- `src/iop/demosaicing/` — 10 demosaic algorithms (amaze/ppg/vng/rcd/lmmse/dual/xtrans/etc.).
- `src/iop/hlreconstruct/` — 5 highlight-reconstruction algorithms.
- `src/common/iop_group.h`, `src/libs/ioporder.c`, `src/libs/modulegroups.c` — iop grouping/ordering.
- `src/views/{lighttable,darkroom,tethering,map,slideshow,print}.c` — 6 views.
- `src/libs/` — 40+ lib panels (collect, history, snapshots, styles, export, masks, geotagging, etc.).
- `src/libs/scopes/{histogram,waveform,vectorscope,split}.c` — scopes.
- Build version: `nightly-496-gdc58cf0ba1`.

**yiyin source** (local, `/Volumes/UNITEK/Documents/Development/yiyin/`):
- `README.md`, `package.json` (v1.7.1) — overview, Electron+Svelte+sharp+fluent-ffmpeg+exifreader.
- `electron/src/interface.ts` — `IConfig`, `IFont`, `IPosition`, `IFieldInfoItem` types.
- `electron/src/config.ts` — `DefaultConfig.options` (19 output params).
- `common/const/def-fields.ts` — 15 EXIF fields.
- `common/const/def-temps.ts` — system templates + per-template font/position.
- `electron/src/modules/image-tool/interface.ts` — `OutputOption` (the canonical 19-param spec).
- `web/util/model-map.ts` — per-brand Make/Model normalization rules.

**Lightamer project** (local, `/Volumes/UNITEK/Documents/Development/Lightamer/.planning/PROJECT.md`):
- Validated requirements, Out-of-Scope list, Key Decisions.

**Capture One Session docs** (web):
- [Sessions 101: Discussing the Concept](https://www.captureone.com/blog/sessions-101-discussing-the-concept) — folder structure (Captures/Selects/Output/Trash + .cosessiondb), per-image sidecar settings, Session vs Catalog.
- [The Complete Guide to Sessions](https://support.captureone.com/hc/en-us/articles/360003115137) — Capture/Output/Trash folder assignment.
- [Sessions 102: Power Users](https://www.captureone.com/blog/sessions-101-discussing-the-concept) (linked) — multi-directory sessions.

**Core Image RAW 9** (web):
- [Enhance RAW image processing with Core Image — WWDC26 Session 305](https://developer.apple.com/videos/play/wwdc2026/305/) — RAW v9: Core ML demosaic+denoise on Neural Engine, 20 calibrated CIRAWFilter properties (exposure/luminanceNR/sharpness/contrast + automated color NR/detail/moire), 784 camera models, DNG native, opt-in via `decoderVersion = .version9`, `scaleFactor` for hi-res interactivity, HEIF/JPEG export.
- [Core Image — Apple Developer Documentation](https://developer.apple.com/documentation/coreimage) — CIRAWFilter, CIImageProcessor.

*Note: CIRAW 9 boundary in the iop table is best-effort; the STACK research dimension owns the definitive mapping.*
