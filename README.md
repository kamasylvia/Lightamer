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
- **Burst grouping & best-of-burst** — same-body ≤2 s + 16×16 signature
  auto-grouping, open-eyes-then-sharpest best selection, one-tap collapse
- **Sharpness & closed-eye batch hints** — library-wide background
  analysis feeds smart-album conditions (`eyes:closed`, `sharp`, `burst`)
- **Fast culling view** — full-screen review on camera embedded previews
  (zero RAW decode), ±3 prefetch, C side-by-side compare with synced zoom
- **Smart preview cache** — 1600 px linear float16 persistent LRU;
  reopen in ~50 ms, shared across GUI / CLI / MCP
- **AI mask edge refinement** — sampling-based matting refines fast
  masks to 4096 px on the original decode (no extra model); MCP
  `refine_masks` included

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

Swift Package dependencies (kept minimal, explicitly enumerated):
[Swift-WebP](https://github.com/ainame/Swift-WebP) (WebP encode; macOS has
no native WebP writer) and the official
[MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (the
Phase 14 MCP server; its HTTP transport layer is built on
[swift-nio](https://github.com/apple/swift-nio), which Lightamer's HTTP
host adapter links directly). Everything else is Apple frameworks:
Core Image (CIRAW decode), Metal, ImageIO, ColorSync, Vision, CoreText.

## MCP server

Lightamer embeds an MCP (Model Context Protocol) server so a local AI
agent can screen and edit the photos of the currently open session.

- **Enable it** in Settings → MCP Server. The server binds `127.0.0.1` on
  a random port and writes a discovery file
  (`<AppSupport>/Lightamer/mcp/mcp-endpoint.json`) with `host`, `port`
  and `auth`. Exposing the server beyond the loopback interface is a
  separate, explicit toggle — it binds `0.0.0.0` and REQUIRES the Bearer
  token (auto-generated, stored in the keychain).
- **Connect an agent** by reading `host`/`port` from the discovery file
  and configuring `http://<host>:<port>/mcp` as a Streamable HTTP server.
  The Origin check requires a PORT in the origin (e.g.
  `http://localhost:51234`; a portless origin is rejected).
- **Tool face** (33 tools, closed set): 5 editing tools (load_image,
  apply_params, render_preview, list_iops, export_image), 14 culling
  tools (list_photos, get_thumbnails, get_contact_sheet, get_detail_crop,
  list_bursts, get_face_regions, set_rating, set_flag, set_color_label,
  append_note, set_keywords, list_presets, apply_preset, diff_presets),
  spectral film tools, mask refinement (`refine_masks`), search & state
  (search_photos, get_history, get_state), and agent control (acquire /
  release / get) with turn-taking. Writes go through the same
  single-source services the GUI uses and land in the sidecar truth +
  the session index.
- **Honesty clauses**: `render_preview` returns the SAVED edit state as
  an sRGB-encoded JPEG — no yiyin frame/watermark (that is export-time)
  and it is NOT aligned with the GUI's EDR display domain. Same
  sidecar + same parameters → the same pixels as a local export render.
- **Launcher** (Edit menu → MCP Agent Launcher…): runs YOUR OWN agent
  command template via `/bin/zsh -c` with the `{{LIGHTAMER_MCP}}`
  (discovery file path) and `{{PROMPT}}` placeholders, shows the agent's
  output, and can stop the agent. Lightamer itself contains no AI code.
- **Headless**: the same binary serves MCP over stdio
  (`Lightamer.app/Contents/MacOS/Lightamer --mcp-stdio`) or HTTP
  (`--mcp-http`).
- **Agent docs**: `skills/lightamer-mcp/` is the agent-facing skill
  (session start, turn-taking, domain boundaries, error codes, preview
  semantics) — start there when wiring an agent to Lightamer.

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

## Architecture note

The app runs under a **manual NSApplication lifecycle** (not the SwiftUI
`App` scene lifecycle). The SwiftUI views are hosted inside an
`NSHostingView` on a hand-rolled `NSWindow`/`NSApplicationDelegate`.
This eliminates the macOS 27 SwiftUI scene-lifecycle idle-CPU churn
(editor idles at 0.0% vs upstream's ~96%) at the cost of manually
re-creating the menu bar and window management that `App` used to provide
for free.

## Known issues

- **Window-level toolbar attachment differs from standard macOS apps.**
  The editor toolbar renders inside the content face rather than
  attaching to the window title bar in the unified style. Every toolbar
  control works; this is purely a chrome difference introduced by the
  manual NSApplication lifecycle (the churn-elimination shell handover).
  A native NSToolbar re-creation is a candidate follow-up.

- **The former "high CPU after reopening a project" issue no longer
  reproduces in this app.** The upstream SwiftUI scene-lifecycle churn
  (macOS 27) that used to pin the editor at ~96% idle CPU was eliminated
  here by hosting the app under a manual NSApplication lifecycle; the
  editor now idles at 0.0% CPU. The upstream framework defect itself is
  unchanged — a Feedback report remains prepared for submission — and
  other SwiftUI-lifecycle apps may still exhibit it.

## Development artifacts

Internal planning documents live under `.work/` (roadmap, requirements,
state, per-phase plans and decision records). The evidence chain — GUI
walkthrough captures (`.work/gui-acceptance/`) and per-phase evidence
bundles (`.work/gsd/phases/*/evidence/`) — is **not tracked in this
repository**: it is mirrored to a separate private Azure DevOps
repository, `kamasylvia/Evidence/lightamer-evidence` (snapshot
2026-10-08, pack policy B). The files remain on disk locally,
gitignored; per-phase `perf.md` performance ledgers stay tracked here.

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

**GPL-3.0** — see [LICENSE](LICENSE). The project was MIT-licensed through
v0.8-era builds; it was relicensed to GPL-3.0 by the sole copyright holder on
2026-10-20 (historical MIT text archived at `research/LICENSE-MIT-2026-archive.txt`
in the development history). Third-party provenance and notices: see [NOTICE](NOTICE).
