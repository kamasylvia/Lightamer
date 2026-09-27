# Lightamer

A native macOS RAW editor and photo manager — Metal 3 direct render,
Capture One-style Sessions, Darktable-grade processing, and first-class
border/watermark output tools.

**Status: work in progress.** Lightamer is developed phase by phase; the
processing core (16-bit scene-referred Metal pixelpipe, ~40 Darktable-
parity iops, layers & masking, AI-assisted masks, sessions, export
pipeline, metadata/presets/LUTs, catalogs mode) is in place, while UI
polish and remaining iops continue to land. Watch the repo for releases.

## Highlights

- **Metal 3 direct-render editing viewport** — 100 MP RAW files stay
  fluid (zoom/pan/rotate, 60 fps editing budget)
- **Scene-referred pipeline** — linear Rec2020 float32 internals, module
  order and math ported 1:1 from Darktable's v50 order (exposure,
  temperature, filmic rgb, agx, sigmoid, tone equalizer, color balance
  rgb, denoise (profiled NL-Means), bilateral, lens correction (Lensfun
  data), crop/flip, liquify, retouch, sharpen, LUT 3D, and more)
- **Adjustment layers** — per-layer iop stacks with blend modes,
  parametric/drawn/raster masks, and AI-assisted subject/skin masks
  (Vision framework, on-device)
- **Capture One-style Sessions** — a folder is a session
  (Capture/Selects/Output + `.lightamer/` index); everything else is
  non-destructive sidecars (`.lra`), never touching your originals
- **Catalogs mode (optional)** — an SQLite-backed central catalog for
  cross-session browsing, tags, and smart albums
- **Non-destructive everything** — history stack with per-step undo,
  copy/paste of adjustments, presets, batch apply
- **Export** — JPEG/PNG/TIFF/HEIF/WebP (+AVIF on macOS 26+), 8/10/16/32
  -bit, per-format quantization, export queue with progress/retry
- **印框/水印 (borders & watermarks)** — canvas borders with blurred or
  solid backdrops, rounded corners, shadows, and EXIF watermark rows
  with camera-brand logos
- **Quick Look & Spotlight** — edited-state previews and metadata
  search (rating/keywords/EXIF) straight from Finder
- **Soft proofing** — printer-profile soft proof with gamut-check
  (out-of-gamut black clipping), multi-display ICC with per-window
  profiles

## Requirements

- **Run:** macOS 27 or later (Apple Silicon)
- **Build:** macOS 27 SDK (Xcode 27), [Tuist](https://tuist.dev) 4.2x

## Building

```bash
tuist generate          # produces Lightamer.xcworkspace
open Lightamer.xcworkspace
# or headless:
xcodebuild build -workspace Lightamer.xcworkspace -scheme Lightamer \
  -destination 'platform=macOS'
```

The only Swift Package dependency is
[Swift-WebP](https://github.com/ainame/Swift-WebP) (WebP encode; macOS
has no native WebP writer). Everything else is Apple frameworks:
Core Image (CIRAW decode), Metal, ImageIO, ColorSync, Vision, CoreText.

## Testing

```bash
xcodebuild build-for-testing -workspace Lightamer.xcworkspace \
  -scheme Lightamer -destination 'platform=macOS'
Scripts/test-direct.sh            # full unit suite (bypasses testmanagerd)
Scripts/test-direct.sh 'HistoryStackTests'   # one class
```

Tests that need full-size RAW camera samples (~1.2 GB, not distributed
— see *Sample images*) skip automatically when the samples are absent.
Golden-reference regeneration against a local darktable build:
`DT=/path/to/darktable-cli bash input/golden/regenerate.sh`.

## Sample images

Camera-sample RAW files used during development (manufacturer press
samples and the author's personal photos) are **not** part of this
repository and are not distributed. All committed test fixtures are
synthetic or derived from the author's own material.

## Provenance & acknowledgements

- [darktable](https://github.com/darktable-org/darktable) — module
  order, iop math, and OpenCL kernels that the processing core ports
  from; golden outputs for parity tests come from a local darktable
  build
- [yiyin](https://github.com/kamasylvia/yiyin) — the border/watermark
  composition pipeline is a 1:1 port of its layout engine
- [Lensfun](https://github.com/lensfun/lensfun) — lens correction data
  (XML), licensed CC-BY-SA 3.0
- [Swift-WebP](https://github.com/ainame/Swift-WebP) — WebP encoding

## Trademarks & embedded brand logos

The 印框/水印 feature ships a set of camera-brand logos
(`LightamerIOP/Resources/Logos/*.pdf`, 13 brands × light/dark) so a photo's
watermark can display the manufacturer mark, matching the upstream yiyin
project's behavior:

| Logo | Owner |
|---|---|
| Canon | Canon Inc. |
| DJI | SZ DJI Technology Co., Ltd. |
| FUJIFILM | FUJIFILM Holdings Corporation |
| Hasselblad | Hasselblad AB |
| Leica | Leica Camera AG |
| Nikon | Nikon Corporation |
| Olympus | OM Digital Solutions Corporation (OM SYSTEM) |
| Panasonic | Panasonic Holdings Corporation |
| PENTAX | Ricoh Imaging Company, Ltd. |
| RICOH | Ricoh Company, Ltd. |
| SIGMA | Sigma Corporation |
| Songdian（松典） | Shenzhen Songdian Technology Co., Ltd. |
| SONY | Sony Group Corporation |

All names and logos are **trademarks of their respective owners**, used
here solely for the nominative purpose of identifying the manufacturer of
the equipment depicted in a photograph. Their inclusion does not imply any
affiliation with, sponsorship, or endorsement by these owners. Lightamer is
an independent open-source project; the logos are converted from the
[GPL-3.0-licensed yiyin](https://github.com/kamasylvia/yiyin) project's
brand SVG assets (the same author's work), and each artwork itself remains
the property of its trademark holder. Rights holders who object to
inclusion may open an issue and the asset will be removed.

### Fonts

The watermark renderer uses **system-provided fonts only** (PingFang SC
cascade via CoreText, plus user-imported `.ttf`/`.otf` files) — no third
party font is embedded with this application.

## License

MIT — see [LICENSE](LICENSE).
