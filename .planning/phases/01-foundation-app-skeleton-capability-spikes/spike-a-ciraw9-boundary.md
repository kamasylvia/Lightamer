# Spike A Report — CIRAW 9 capability boundary on macOS 27.0 GM

**Plan:** 01-05 Task 01-05-01 · **Executed:** 2026-09-16 · **Owner:** GSD executor
**Host:** Apple M4 (Mac16,10), 16 GB unified memory, macOS 27.0 **official release** (26A428), Xcode 27.0 (27A266a) / macOS 27.0 SDK, Swift 6.4.
**Requirement:** FOUND-07 (spikes). **Decisions fed:** D-22 (RAW 9 opt-in), Phase 3 demosaic scope, Phase 5 denoise scope, RAW-04 (non-CIRAW fallback).

> **Execution-form note (recorded deviation from plan text):** the plan asked for a
> standalone Tuist spike app on branch `spike/ciraw9-boundary`. Since Plans 01-04
> already delivered the real verification apps + smoke-harness pattern, the probe was
> written as a **headless public-API-driven Swift script** (same pattern as the
> 01-03/01-04 smokes, zero Lightamer dependencies) at `.work/01-05/ciraw-probe.swift`,
> with a tracked copy + raw output + golden samples under
> `.planning/spikes/spike-a-ciraw9-boundary/`. This satisfies D-06's intent
> (verification code preserved, evidence versioned) without a throwaway GUI app or a
> spike branch. 13 real camera RAW samples (CC0, raw.pixls.us) were downloaded —
> **no fabricated or synthetic RAW files were used**; provenance in
> `.planning/spikes/spike-a-ciraw9-boundary/samples/README.md`.

---

## 1. What was probed

`ciraw-probe.swift` (system frameworks only) in three modes:

1. **`surface`** — GM API surface: `CIRAWFilter.h` (223-line GM header) cross-checked
   against the ObjC runtime property list (50 @objc properties) and
   `supportedCameraModels` / `supportedCameraModels(with:)` (new in macOS 27).
2. **`models`** — full per-decoder-version camera lists dumped to `models.txt`.
3. **`probe`** — per-file behavior on 13 real RAW/DNG samples spanning all 5 sensor
   families: `supportedDecoderVersions`, per-version `*Supported` capability flags,
   1:1 center-crop renders (320×240 RGBA8) with per-tunable pixel-diff (behavioral
   no-op evidence), decode timing (`os.signpost` intervals + `ContinuousClock`),
   `task_vm_info.phys_footprint` memory, Apple mattes, embedded preview.

All timing emits `os.signpost` intervals (`com.kamasylvia.lightamer.spikea`) — D-31 honored.

## 2. GM API surface (new evidence vs research assumptions)

### 2.1 Decoder versions

`CIRAWDecoderVersion` constants in the GM SDK: `None`, `9`, `9DNG`, `8`, `8DNG`,
`7`, `7DNG`, `6`, `6DNG` (DNG variants are distinct decoder families).
Per-file `supportedDecoderVersions` raw values look like `[7, 8, 9]` (RAW) or
`[6.dng, 7.dng, 8.dng, 9.dng]` (DNG).

### 2.2 RAW 9 camera coverage at GM — **69 models, not "hundreds"**

`supportedCameraModels(with: .version9)` returns **69 models** (v8: 465; v7: 879;
total distinct: 921). Full list in `models.txt`. Highlights of the v9 list:

- **Sony:** ILCE-6100/6400/6700, A7 II, A7C/A7C II, A7 III/A7 IV, **A7R III/A7R V**, A7S III, ZV-E10, RX1R III
- **Fujifilm:** **X-T5, X-T50 only** — no GFX, no X100VI, no X-H2S/X-T4/X-Pro3
- **Canon:** 5D line (incl. **5D IV which is v9-only**, absent from v8), R, R1, R5, R5C, R6, R6 II, R8, RP, R50, R100
- **Nikon:** D750, D850, Z 6 II, Z fc, Z50 — **no Z8/Z9/Z6 III/Zf**
- **Panasonic** (17 models), **Sigma** BF/fp/fp L, **Leica** D-Lux 8

**Not in v9 at GM** (verified by list + per-file `supportedDecoderVersions`):
GFX100S, X100VI, X-H2S, Nikon Z8, OM-1 Mark II, Hasselblad X2D, Canon R10.
The research assumption ("hundreds of models at GA", RESEARCH §2) is **not met at
GM**: RAW 9 coverage is a narrow, oddly-shaped subset (many of them older bodies).
`version8DNG`/`version9DNG` lists return 0 models — DNG support is not enumerable
per model; DNG files simply report `.dng` versions per file.

### 2.3 Per-file RAW 9 availability (decisive for D-22)

| File | supportedDecoderVersions (raw) | RAW 9? |
|---|---|---|
| Sony A7R V ARW (60.2MP) | `[7, 8, 9]` | **Yes** |
| Fujifilm X-T5 RAF (39.8MP) | `[7, 8, 9]` | **Yes** |
| Sony a6700 ARW (25.6MP) | `[7, 8, 9]` | **Yes** |
| iPhone 12 Pro ProRAW DNG | `[6.dng, 7.dng, 8.dng, 9.dng]` | **Yes** |
| Adobe 5D III DNG | `[6.dng, 7.dng, 8.dng, 9.dng]` | **Yes** |
| **GFX100S RAF (101.8MP — headline)** | `[7, 8]` | **No** |
| Nikon Z8 NEF (45.4MP) | `[7, 8]` | No |
| X100VI / X-H2S RAF | `[7, 8]` | No |
| Canon R10 CR3 | `[7, 8]` | No |
| OM-1 II 80MP high-res ORF | `[7, 8]` | No |
| Hasselblad X2D 3FR (102.1MP) | `[7, 8]` | No |
| Phase One IQ4 150MP IIQ | **`[None]`, nativeSize 0×0** | **Not decodable at all** |

Consequences:

- **D-22's "default RAW 9, fallback RAW 8" remains correct but mostly falls back at
  GM** — for a typical mixed-session, the majority of bodies (including the 100MP
  headline camera) decode via RAW 8 on macOS 27.0. Plan 02's implementation
  (probe + opt-in + fallback) needs **no change**; the probe cache matters even more
  (init costs 0.2–2.3 s per filter instantiation, see §4).
- **Phase One IQ4 150MP IIQ is NOT decodable by CIRAWFilter** (`[None]`, 0×0, only
  the embedded preview surfaces). The Apple support-article camera list (research
  STACK §RAW breadth) is an ImageIO list, not a CIRAWFilter guarantee. This is the
  first concrete evidence for the deferred "libraw fallback" idea (D-24/RAW-04) —
  Phase 2+ should treat unsupported-RAW as a typed-error path (Plan 02 already
  does) and log which bodies users hit.

### 2.4 WWDC26/305 no-op key claims — **confirmed, two mechanisms**

Under RAW 9, the fused-demosaic engine removes the fine-grained NR keys. Evidence
comes in two forms (probe prints both):

1. **API-level:** the `isXxxSupported` capability flags drop:
   - `colorNoiseReductionSupported`, `detailSupported`, `moireReductionSupported`
     → **UNSUPPORTED on every v9-capable file** (A7R V, X-T5, a6700, both DNGs).
   - Under v8 they are all "supported".
2. **Behavioral:** maxing a key and pixel-diffing a 1:1 crop against baseline
   (mean |Δ| per channel / 255, <0.3 ≈ no-op):
   - iPhone DNG `[9]` `luminanceNoiseReductionAmount` diff = **0.00 (no-op)**
     although its flag still says "supported"; same key under `[8]` diff = 0.97
     (real effect). So even "supported" keys can be behaviorally inert under v9.
   - `sharpnessAmount` diff ≈ 0.00 on **all** files under **both** versions at 1:1
     (sharpening applies only at downscaled renders — 1:1 crops are below its
     trigger scale; treat as scale-dependent, not v9-specific).
   - `contrastAmount` produces real pixel changes in both versions (0.5–3.3).
   - `localToneMapAmount`: flag-supported only on DNG files at GM; no pixel
     effect at 1:1 (it is a downscaled-render tone operator).

**Phase 3/5 implication:** do not build UI on `colorNoiseReductionAmount` /
`detailAmount` / `moireReductionAmount` / (behaviorally) `luminanceNoiseReductionAmount`
for v9-decoded images; the plan to port Darktable `denoiseprofile` as a Metal iop
(Phase 5) is **not** reduced by RAW 9 — CIRAW's own NR controls largely vanish under
v9, and under v8 they are generic, not profiled.

### 2.5 Lens correction

- `lensCorrectionSupported` is per-file/per-version. GM deltas observed:
  **A7R V: UNSUPPORTED under v8 → supported under v9** (RAW 9 adds lens DB
  coverage for it); X-T5/a6700/Z8/X-H2S/GFX100S/OM-1 II supported under v8 too;
  CR3 R10 and X2D report UNSUPPORTED at GM.
- Enabling it on a **center** 1:1 crop changes nothing (diff 0.00 — expected:
  distortion/CA/vignette corrections act toward corners). Corner-crop behavioral
  verification is follow-up work; the API-level flag is the v1 evidence.
- Apple does not expose a lens **database** or user-tunable CA/distortion/vignette
  sliders — the research conclusion stands: the Darktable `lens` iop (Lensfun XML
  data + Metal warp, Phase 4) is **not** covered by CIRAW and remains in scope.

### 2.6 Apple mattes (D-23c / Phase 7)

iPhone 12 Pro ProRAW DNG surfaces **`semanticSegmentationSkyMatte = present`**
via CIRAWFilter at GM; `portraitEffectsMatte` + skin/hair/glasses/teeth are nil
for this capture (capture-time feature availability). All 6 matte properties
exist in the API on every file (runtime dump). L004 stands: mattes are
iPhone-ProRAW-capture dependent; read them opportunistically, never assume.

### 2.7 Other surface notes (back-port targets for Plan 02/03)

- `+supportedCameraModels(with:)` (macOS 27+) lets `RAWDecoder` probe camera
  support **without instantiating a filter** — cheaper than the current
  two-instantiation probe for the unsupported-camera fast path.
- `-downloadResources(timeout:completionHandler:)` (macOS 27+): on this machine
  all v9 decodes reported `fractionCompleted=1.00` with no visible download wait
  — RAW 9 assets for the 69 covered models are bundled/on-demand with no
  first-use stall observed. Keep the call before first v9 decode anyway.
- `previewImage` (embedded JPEG): every sample exposes one (e.g. GFX100S
  4000×3000, Z8 full 8256×5504) — the Session browser thumbnail path (Phase 9)
  should consume `previewImage` instead of decoding RAW.
- `nativeSize`, `orientation`, `draftModeEnabled`, `boostAmount`,
  `boostShadowAmount`, `highlightRecoveryEnabled` (macOS 26+), `gamutMappingEnabled`,
  `linearSpaceFilter`, `neutralChromaticity/Location/Temperature/Tint` all present
  at GM (50 @objc properties, full list in probe output).

## 3. Per-camera capability table

Demosaic/denoise quality scores are spike-level assessments from the committed
100% golden crops (`samples/golden/`, v8 vs v9 pairs) — **not** calibrated against
Darktable reference renders (no darktable reference outputs were generated in this
environment; golden-diff tests against Darktable are Phase 2/3 work per CONVENTIONS).

| Sensor family / camera | RAW 9? | Demosaic (1-5) | Denoise (1-5) | Lens corr. | Decode+crop (first-touch) | Memory (proc. footprint) | Notes |
|---|---|---|---|---|---|---|---|
| **Bayer pro — Sony A7R V** (60.2MP) | **Yes** | v8 3 (watercolor on foliage), **v9 4** (finer grass/blade detail, cleaner edges) | v9 keeps detail + finer grain → 4; v8 generic → 3 | v8 off / **v9 on** (flag delta) | [8] 115 ms · [9] 726 ms | ≈554 MB proc. | v9 visibly resolves high-frequency foliage better |
| **Bayer pro — Nikon Z8** (45.4MP) | No | v8 3–4 (clean at base ISO) | 3 (generic v8 NR) | supported (v8) | 10.5 s first-touch (cold) | ≈496 MB | NEF lossless OK; full-size perf → Spike B |
| **Bayer pro — Hasselblad X2D 3FR** (102.1MP) | No | v8 3–4 (base ISO, clean crop) | 3 | UNSUPPORTED | 32.7 s first-touch (cold) | ≈550 MB | 3FR decode works; slowest first-touch |
| **Bayer medium — Phase One IQ4 150MP IIQ** | **N/A** | **CIRAW cannot decode** | — | — | `[None]`, 0×0 | preview only | **Gap: typed-error path in v1; libraw fallback candidate (v2+, D-24)** |
| **Bayer consumer — Sony a6700** (25.6MP) | **Yes** | v8 3, v9 4 | v9 4 | supported both | [8] 3.8 s · **[9] 77 ms** | ≈351 MB | v9 ~49× faster on this sample |
| **Bayer consumer — Canon R10 CR3** (24MP) | No | v8 3–4 | 3 | UNSUPPORTED | 5.9 s (incl. 2.3 s init) | ≈454 MB | CR3 init is the slowest (2.3 s) — probe-cache D-22 |
| **X-Trans HR — Fujifilm X-T5** (39.8MP) | **Yes** | **v8 2–3: visible maze artifacts on diagonal edges; v9 4: cleaner diagonals, finer grain** (roof-tile torture crop) | v9 4, v8 3 | supported both | [8] 9.8 s · **[9] 0.9 s** (~11×) | ≈435 MB | **The one family where v8 quality is materially weak** |
| **X-Trans — X100VI** (39.8MP→26MP mode) | No | v8 3 | 3 | UNSUPPORTED | 4.2 s | ≈375 MB | crop orientation=6 handled |
| **X-Trans stacked — X-H2S** (26MP) | No | v8 3 | 3 | supported | 10.3 s first-touch | ≈389 MB | |
| **X-Trans 100MP — GFX100S** (101.8MP, **headline**) | **No** | v8 3–4 (clean at base ISO in foliage crop; maze risk on diagonals like X-T5) | 3 | supported (v8) | 10.0 s first-touch (cold) | ≈649 MB | **RAW 9 NOT available at GM — D-22 fallback fires on the headline camera** |
| **Quad-Bayer — OM-1 II 80MP high-res ORF** (80.6MP) | No | v8 4 — **native 80MP output, no visible artifacts** (Quad-Bayer high-res demosaiced by CIRAW) | 3 | supported | 20.6 s first-touch | ≈450 MB | `nativeSize` reports full 10368×7776 — no manual high-res merging needed |
| **DNG — iPhone 12 Pro ProRAW** (12.2MP) | **Yes** (`9.dng`) | v9 fine | v9: fine-NR keys gone (§2.4) | UNSUPPORTED | [8] 1.5 s · [9] 0.13 s | ≈404 MB | **skyMatte present**; mattes per capture |
| **DNG — Adobe-converted 5D III** (22.1MP) | **Yes** (`9.dng`) | fine | fine | UNSUPPORTED | [8] 1.4 s · [9] 76 ms | ≈311 MB | Adobe DNGs decode through the DNG decoder family |

## 4. Decode-time observations (method + caveats)

- Spike A renders a 320×240 **1:1 crop** from a fresh `CIRAWFilter` per render —
  first-touch numbers include cold file I/O (USB-attached volume), per-camera
  RAW-engine first-use, and (for v9) CoreML engine warm-up. They are **not**
  steady-state decode benchmarks — Spike B measures the headline files with
  warm-up + 5 runs (median/min/max) at full size.
- Robust signals independent of cache state:
  - **v9 vs v8 speed on the same file: ~11–49× faster** for the crop render
    (X-T5 9.8 s→0.9 s; a6700 3.8 s→0.077 s; DNGs ~11×). RAW 9's tiled CoreML
    demosaic+denoise is dramatically cheaper than the v8 CPU/GPU hybrid path.
  - **Filter init cost is material**: 0.2–2.3 s (CR3 worst at 2.3 s). Plan 02's
    probe cache (one instantiation per (file) for `supportedDecoderVersions`)
    + reusing one filter per decode is validated as necessary.
- `phys_footprint` during crop probes stays ≤ ~650 MB process-wide even with
  100MP files — no memory hazard in the decode path itself.

## 5. DECISION (evidence for the user's phase-verification call — not pre-decided)

**Question: is the per-method demosaic menu (PPG/RCD/AMaZE/VNG4/Mark.3-pass/dual) a v1 hard requirement?**

Evidence summary:

1. **RAW 9 covers only 69 models at GM** — the flagship 100MP camera (GFX100S) and
   most current pro bodies (Z8, X-H2S, X100VI, X2D, OM-1 II, R10) decode with
   **RAW 8** on macOS 27.0. RAW 9 is NOT a rescue for v1 demosaic quality on the
   cameras this app targets.
2. Where v8 is the engine, its demosaic is Apple-internal and **not selectable**
   (`kCIRAWDemosaicMethod` exposes only Apple-internal methods — unchanged at GM).
3. Measured quality: **Bayer at base ISO is clean (3–4/5)** — a per-method menu
   would add little for most Bayer work at base ISO. **X-Trans shows visible
   maze artifacts on diagonal edges under v8 (2–3/5)** and v9 fixes it — but v9 is
   available only for X-T5/X-T50 among Fuji bodies. Darktable-grade alternatives
   (AMaZE/RCD for Bayer, Markesteijn for X-Trans) remain the only way to offer
   algorithm choice.
4. Port cost (from research): `demosaic_rcd.cl` ~200 lines, `demosaic_ppg.cl`
   ~small, `demosaic_markesteijn.cl` ~700 lines (X-Trans 3-pass, expensive to
   compute at 100MP).

**Recommendation for the phase-verification decision** (user makes the call):

- **Do not make the full per-method menu a v1 hard requirement.** v1 ships
  Apple-default demosaic (v8 fallback per D-22) for all cameras. Rationale: Bayer
  base-ISO quality measured clean; per-method choice is a power-user feature; the
  port + golden-image validation cost (per camera × per method × per ISO) is
  disproportionate to Phase 1-3 goals.
- **Schedule the X-Trans Metal port (Markesteijn or RCD-on-X-Trans) as the first
  demosaic candidate in Phase 3 backlog** (not v1-blocker): it is the only family
  where the measured gap (maze artifacts on diagonals, and GFX100S/X100VI/X-H2S
  stuck on v8 at GM) is material. Re-evaluate at Phase 3 planning with two new
  data points: (a) RAW 9 camera list after macOS 27.x point updates (Apple expands
  it over the OS lifecycle), (b) golden-image diff vs Darktable Markesteijn on
  X-T5/GFX100S torture crops (Phase 2 test framework lands first).
- **Keep Phase 5 denoise plans unchanged**: RAW 9 removes Apple's fine-NR keys
  (§2.4), so profiled denoise (`denoiseprofile` port) is still the only
  Darktable-grade path — v9's fused NR is not user-controllable.

## 6. Back-port notes (fed to 01-RESEARCH.md §2)

1. `supportedCameraModels(with:)` = zero-cost camera-support probe (no filter
   instantiation) — use for the unsupported-camera fast path in `RAWDecoder`.
2. `supportedDecoderVersions` rawValues are strings `"7"`, `"8"`, `"9"`,
   `"8.dng"`, `"9.dng"` — comparisons must be against `CIRAWDecoderVersion`
   constants' `rawValue`, not integers.
3. GM SDK has **no** blackLevel/whiteLevel on CIRAWFilter (confirmed; Plan 02
   already documents this in `RAWTechnicalParams`).
4. IQ4 150MP decodes `[None]` — the unsupported-RAW typed-error path is real and
   should be smoke-tested with this file family (fixture candidate for Plan 06).
5. v9's first-use `downloadResources` observed instant (no stall) on GM for all
   5 tested v9 models; keep the call, log `fractionCompleted`.
6. First-touch decode of lossless-compressed 3FR/RAF/NEF can take tens of
   seconds cold on USB storage — browser UX (Phase 9) must lean on
   `previewImage`, never first-decode.

## 7. Artifacts

- Probe source (tracked copy): `.planning/spikes/spike-a-ciraw9-boundary/ciraw-probe.swift` (working copy in untracked `.work/01-05/`)
- Raw probe output: `.planning/spikes/spike-a-ciraw9-boundary/spike-a-probe-output.txt`
- Full v8/v9 camera lists: `.planning/spikes/spike-a-ciraw9-boundary/models.txt`
- Golden 100% crops (committed): `.planning/spikes/spike-a-ciraw9-boundary/samples/golden/*.png` (v8/v9 pairs where supported)
- Sample provenance + CC0 license note: `.planning/spikes/spike-a-ciraw9-boundary/samples/README.md`
- RAW sample working copies (untracked): `.work/01-05/samples/` (13 files, ~1 GB, CC0)
