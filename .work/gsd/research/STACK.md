# Project Research — Stack (Lightamer)

> Research dimension: STACK · Date: 2026-08-03 · Current Apple releases: **macOS 26 (Tahoe)** is the shipping OS; macOS 27 (with Core Image **RAW 9**) is in beta for fall 2026 release.

## Summary

The prescriptive 2026/2027 stack for a macOS-native RAW editor is **Swift 6 + SwiftUI + Metal 3 (MTKView) + Core Image (`CIRAWFilter`)** for the editor core, **ImageIO / `CGImageDestination`** for JPG/PNG/TIFF/HEIF encode, **ColorSync + EDR** for color/HDR, and a **thin layer of Metal compute kernels** (ported from Darktable's OpenCL `.cl` kernels) to cover every iop that Core Image does not. Two hard facts reshape the project's assumptions: (1) **"CIRAW 9" is not macOS 14/15** — RAW 9 is Apple's ML-fused demosaic+denoise engine shipping in **macOS 27 / iOS 27** (WWDC26 Session 305); macOS 26 (Tahoe) and earlier ship **RAW 8**, which is the realistic floor for at least the first 12 months. (2) **AVIF *writing* via `CGImageDestination` is native only on macOS 26 (Tahoe)+**, and **WebP *writing* is still not natively exposed** through `CGImageDestination` as of macOS 26 — both need a Swift Package (libavif/libwebp binding) if the floor is below Tahoe or if WebP export is required at all.

**Recommended macOS floor: macOS 14 (Sonoma)**, with a hard runtime target of **macOS 26 (Tahoe)** to unlock (a) native AVIF encode, (b) the mature SwiftUI/Metal 3 surface, and (c) a clean upgrade path to RAW 9 when macOS 27 ships. Rationale in the *Recommended macOS Floor* section.

---

## Core Technology Stack

### Core Image (`CIRAWFilter`, RAW 8 / RAW 9)
- **What it is:** Apple's framework for processing RAW sensor data into a `CIImage`. The public entry points are `CIRAWFilter` (class, modern) and `CIRAWFilterOption` keys (legacy dictionary). Decoder version is selectable via `kCIInputDecoderVersionKey` / `supportedDecoderVersions`.
- **Why this choice:** It is the *only* first-party, Apple-Silicon-accelerated, camera-broad RAW decoder on macOS. Reimplementing RAW decode (DNG/CR3/NEF/ARW/RAF demosaic + black-level + WB + lens metadata) from scratch is out of scope for a single-developer open-source project. Core Image also integrates directly with Metal (`CIContext(MTLDevice)`) and ColorSync.
- **Version/availability:** RAW 8 ships in macOS 13/14/15/26 (Tahoe). **RAW 9 ships in macOS 27 / iOS 27** (fall 2026); it is a tiled CoreML model that **fuses demosaic + denoise** in one pass and is **opt-in** per-image via the decoder version key. As of the macOS 27 beta, RAW 9 supports a limited subset of cameras (e.g., Fuji X-T5/X-T50) and expands over the OS lifecycle.
- **Confidence: High** for the choice; **Med** for RAW 9 details (beta, camera list and behavior still changing).

### Metal 3 (MTKView + Metal Shading Language compute kernels)
- **What it is:** Apple's low-overhead GPU API. Two surfaces matter here: (1) `MTKView`/`CAMetalLayer` for the direct-render editor viewport; (2) `MTLComputeCommandEncoder` + MSL kernels for the iop pipeline that Core Image does not cover.
- **Why this choice:** Mandatory for the 100MP+ 60fps Core Value. Metal 3 on Apple Silicon exposes **unified memory** (no PCIe texture copy), **tile-based deferred rendering (TBDR)** with **programmable blending** and **tile shaders** (load/store actions keep intermediates in tile memory), **rasterization order groups (Tier 2)**, **half-precision (`half`) FP** throughput, and **build-time shader compilation**. This is the direct Apple analog of Darktable's OpenCL pipeline.
- **Version/availability:** Metal 3 = macOS 13+ (Sonoma/Sequoia/Tahoe all support the full Apple-GPU feature set on Apple Silicon). Mesh shaders (not needed for 2D photo work) and ROG are available but the load-bearing features for an image editor are compute kernels + tile memory + `half`.
- **Confidence: High.**

### SwiftUI (with `NSViewRepresentable` bridge to MTKView)
- **What it is:** Declarative UI. The right primitives for this app are `NavigationSplitView` (3-column sidebar/list/detail, the Session browser), `Table` (metadata grid), `Inspector`/`Form` (iop panels), and `String Catalog` (zh/en localization).
- **Why this choice:** Native macOS chrome, free accessibility, system color/HDR awareness, and a clean bridge to the Metal viewport via `NSViewRepresentable`. `NavigationSplitView` has been production-stable since macOS 14 (Sonoma) — the bugs that marred its macOS 13 debut are resolved.
- **Version/availability:** `NavigationSplitView`/`NavigationStack` = macOS 13+; `String Catalog` = macOS 14+; `Observable` macro = macOS 14+. **macOS 14 is the realistic SwiftUI-stability floor.**
- **Confidence: High.**

### ImageIO / `CGImageDestination`
- **What it is:** The first-party encode/decode framework. `CGImageSource` reads RAW + raster; `CGImageDestination` writes raster. The supported output UTI set is queryable via `CGImageDestinationCopyTypeIdentifiers()`.
- **Why this choice:** Native, ColorSync-aware, zero-dependency encode for JPG/PNG/TIFF/HEIF. The catch (see Export Matrix): **AVIF write is new in macOS 26**, **WebP write is still not exposed**.
- **Version/availability:** Always available; AVIF write gated to macOS 26+.
- **Confidence: High** for JPG/PNG/TIFF/HEIF; **High** that WebP write needs a library on every target OS; **High** that AVIF write needs a library below macOS 26.

### ColorSync + EDR (Extended Dynamic Range)
- **What it is:** macOS's ICC-based color management (ColorSync) plus the EDR pipeline for HDR display: `NSScreen.maximumExtendedDynamicRangeColorComponentValue`, `CAMetalLayer.wantsExtendedDynamicRangeContent = true`, `.rgba16Float` (or `.rgba16Unorm`-sRGB-extended) pixel format, and `CIContext` EDR rendering.
- **Why this choice:** Soft proofing, Display P3 / ProPhoto / Rec2020 / ACES workflows, and true HDR photo viewing (highlights above 1.0 SDR white) all flow through these APIs. WWDC21 *"Explore HDR rendering with EDR"* and WWDC22 *"Display EDR content with Core Image, Metal, and SwiftUI"* are the canonical references.
- **Version/availability:** EDR APIs = macOS 10.15+ but practically mature on macOS 12+; `CIContext` EDR integration mature on macOS 13+.
- **Confidence: High.**

### Metal Performance Shaders (MPS) — selective use only
- **What it is:** Apple's prebuilt Metal image/vision kernels (`MPSImageGaussianBlur`, `MPSImageLaplacian`, `MPSImageBilateral`, `MPSImageConvolution`, etc.).
- **Why this choice (selective):** Use MPS only where its kernel beats a hand-written one for *generic* ops (e.g., separable Gaussian for `lowpass`/`shadhi`, Sobel for edge detection). For Darktable-equivalent iop with specific math (filmic, colorbalancergb, denoiseprofile), write custom MSL — MPS is not a substitute for the full iop pipeline.
- **Confidence: Med** (use case-by-case; do not architect around MPS).

### Swift Package Manager dependencies (minimal)
- **`swift-libavif`** / **`avif.swift`** (or a vendored libavif via SPM) — AVIF encode/decode below macOS 26 and for guaranteed-quality control. Confidence: High that one is needed.
- **`swift-libwebp`** / **`WebP.swift`** — WebP encode, always (Apple does not expose WebP write through `CGImageDestination` even on Tahoe). Confidence: High.
- **No libraw / no OpenCV / no Qt / no lensfun C++ binding** in v1 — see *What NOT to Use*.

---

## Core Image RAW 9 Capability Boundary

This is the critical unknown called out in `PROJECT.md`. The table below is explicit about what Core Image (RAW 8 on macOS ≤ 26, RAW 9 on macOS 27+) covers today, so the gaps can be planned as Metal work.

**How to read:** "CIRAW covers?" = whether `CIRAWFilter` produces that stage natively. "Notes" gives the gap.

| Capability | CIRAW covers? | Notes / Gap |
|---|---|---|
| **RAW decode (unpack sensor + black level + WB scales)** | **Yes** | ImageIO + Core Image decode CR3/NEF/ARW/RAF/RW2/ORF/DNG/IIQ/etc. natively (see Apple support article 120534 for the macOS 15 list). This is the *base layer* — never reimplement. |
| **Demosaic — Bayer** | **Yes (RAW 8)** | Algorithm is Apple-internal (not selectable). Quality is acceptable but not RCD/AMaZE-class. RAW 9 fuses demosaic+denoise via CoreML with materially better output. |
| **Demosaic — X-Trans** | **Yes (RAW 8) / Better (RAW 9)** | RAW 8 demosaics X-Trans acceptably; RAW 9 explicitly targets "non-traditional sensor layouts" (X-Trans, Quad-Bayer) per Apple. |
| **Demosaic algorithm choice (PPG / RCD / AMaZE / VNG / Markesteijn / LMMSE / dual)** | **No** | `kCIRAWDemosaicMethod` exists but the selectable methods are Apple-internal; you **cannot** expose Darktable's per-method menu via CIRAW. → Reimplement in Metal if the user-facing algorithm menu is a requirement (Darktable's `data/kernels/demosaic_rcd.cl`, `demosaic_ppg.cl`, `demosaic_markesteijn.cl`, `demosaic_vng.cl` are direct port sources). |
| **Noise reduction — basic (luminance + chroma)** | **Yes** | `kCIInputNoiseReductionAmount` (0.0–1.0), plus `luminanceNoiseReductionAmount`, `colorNoiseReductionAmount`, `noiseReductionSharpnessAmount`, `noiseReductionContrastAmount`, `noiseReductionDetailAmount`, and `progressiveChromaticNoiseTracking` (ISO-based). RAW 8 NR is decent; RAW 9 NR is best-in-class (fused with demosaic). |
| **Noise reduction — profiled NLMeans / wavelet (Darktable `denoiseprofile`)** | **No** | CIRAW NR is generic, not per-camera-profiled. Darktable's `denoiseprofile` (7-band wavelet / NLMeans with per-camera noise profiles) must be a custom Metal iop (port `data/kernels/denoiseprofile.cl`, `nlmeans.cl`). |
| **Lens correction — geometric distortion, lateral CA, vignetting** | **Partial** | CIRAW applies *embedded* lens-correcting metadata (DNG OpcodeList / manufacturer opcodes) and exposes `lensCorrectionOptimalImageFromImageCenter` / `lensCorrectionOptimalScale`. It does **not** ship a lens *database* (Lensfun/LCP) and does **not** expose user-tunable CA/distortion/vignette sliders derived from a profile. → Either ship Lensfun data (read-only XML) + a Metal warp, or accept embedded-only correction in v1. |
| **Chromatic aberration — manual / fine** | **No** | Darktable's `cacorrect` / `cacorrectrgb` are not in CIRAW. → Metal port of `basic.cl` CA kernel. |
| **Sharpening (input capture sharpening)** | **Yes** | `kCIRAWSharpnessKey` + the NR-detail-sharpness keys cover input sharpening. |
| **Sharpening (creative / output, e.g., RL deconvolution)** | **Partial** | `CISharpen` / `CIUnsharpMask` exist in Core Image (not CIRAW-specific). Use these for generic; port Darktable `sharpen.cl` for RL. |
| **Exposure / baseline exposure / black level / white level** | **Yes** | `baselineExposure`, `blackLevel`, `whiteLevel`, `boost`, `boostFactor`. |
| **White balance (temperature/tint via neutral chromaticity)** | **Yes** | `neutralChromaticity` (x/y). No direct Kelvin slider — convert K/tint → xy in Swift. |
| **Color management — input profile (camera → XYZ)** | **Yes (embedded / DNG)** | CIRAW uses the embedded camera matrix or DNG profile. It does **not** accept external DCP files. |
| **Color management — DCP (DNG Camera Profile) loading** | **No** | If shipping DCP-style profiles is a requirement (Adobe/DxO interop), implement a DCP reader + Metal LUT/matrix application in the working space. Otherwise rely on embedded matrices. |
| **Working/output color spaces (ProPhoto, Display P3, Rec2020, ACES, linear)** | **Yes (via `CIContext` / `kCIOutputColorSpace`)** | Core Image renders into any ICC space via ColorSync. ProPhoto, Display P3, Rec2020, linear-rec709 are all supported. ACES (ACEScg/ACES2065-1) requires shipping the ACES ICC profile and passing it to `CIContext`. |
| **Tone curve / filmic / sigmoid / colorbalancergb** | **No (CIRAW-specific)** | These are creative iop. Core Image has generic `CIToneCurve`, `CIColorControls`, `CIHighlightShadowAdjust`, but Darktable's filmic/sigmoid/colorbalancergb are bespoke. → Metal ports of `filmic.cl`, `sigmoid.cl`, `colorbalancergb.cl`, `colorbalance.cl`. |
| **Local adjustments (drawn + parametric masks, toneequal, diffuse/sharpen)** | **No** | Entirely custom. The mask rasterizer + toneequal/diffuse iop are major Metal+Swift work (`toneeq` ≈ `data/kernels/locallaplacian.cl` / `guided_filter.cl`; `diffuse.cl` is the diffuse/sharpen engine). |
| **HDR / EDR output (render scene-referred linear into EDR)** | **Yes (via Metal/CIContext EDR)** | Set `CAMetalLayer.wantsExtendedDynamicRangeContent`, `.rgba16Float` pixel format, and a linear/extended color space; CIContext renders scene-referred floats >1.0 directly. No CIRAW change needed. |
| **Lensfun / LCP profile loading as a *system*** | **No** | No first-party equivalent. See *What NOT to Use* / Open Questions. |
| **RAW file breadth — see separate matrix below** | **Yes (broad)** | Apple support article 120534 (macOS 15) / 122870 (macOS 26) lists ~600+ cameras. Gaps noted in RAW Format Support section. |

### What CIRAW explicitly does NOT do (must be reimplemented in Metal)
1. **Algorithm-selectable demosaic** (PPG/RCD/AMaZE/VNG4/Mark.3-pass/dual). CIRAW gives you one Apple-internal algorithm.
2. **Profiled denoise** (`denoiseprofile`-equivalent per-camera noise model).
3. **A lens-correction database** (Lensfun/LCP) with user-tunable CA/distortion/vignette.
4. **All creative tone/color iop** beyond generic Core Image filters: filmic, sigmoid, colorbalancergb, colorzones, channelmixerrgb, toneequal, diffuse/sharpen, rgbcurve, rgblevels.
5. **Local/parametric mask engine** and the mask-bound iop (tonequal, diffuse, retouch, liquify).
6. **DCP profile loading** (Adobe-style camera profiles).
7. **Spot/heal/liquify/retouch** geometry tools.
8. **LUT3D** as a Darktable-style iop (Core Image has `CIColorCubicMixed` — usable, but Darktable `.cube` interop is custom).

### Decoder 策略对比：Alcedo Studio vs CIRAW RAW 9（2026-09-27 登记）

背景：参考项目 Alcedo Studio（GPL-3.0，`/Volumes/UNITEK/Documents/Development/AlcedoStudio`）自维护 LibRaw 分支 + 自研 GPU 解码管线，是「自己养解码器」路线的活样本；与本项目「让 Apple 养解码器」（CIRAW RAW 9）路线逐维对比结论如下。

| 维度 | Lightamer（CIRAW RAW 9） | Alcedo（LibRaw fork + 自研 GPU 管线） |
|---|---|---|
| 解码广度 | Apple 维护 ~600+ 机型，DNG 万能兜底 | 自维护 LibRaw 分支，自行实现 Nikon HE/HE* per-precinct 解码（Z8/Z9/Z6III/Z50II） |
| 新机型时效 | 靠系统更新，滞后数月（固有风险） | 自己补 LibRaw，可当周支持 |
| 去马赛克 | 黑盒不可选；RAW 9 ANE CoreML 融合 demosaic+denoise，质量第一梯队，X-Trans 明确受益 | RCD（Bayer 默认，改编 LuisSR/RCD-Demosaicing）+ DemosaicNet 蒸馏 NN（跑 GPU，非 ANE；X-Trans 默认、Bayer 可选） |
| 降噪 | 融合在解码里，best-in-class | **源码无任何降噪实现**（2026-09-27 grep 核实）——高 ISO 实短板 |
| 高光重建 | 无用户可控项；CIRAW 出图时高光已裁剪 | inpaint-opposed（darktable/RawTherapee 方法改进），作用于 demosaic 前原始通道数据 |
| 镜头/色彩配置 | 只应用内嵌 opcode，无镜头库、不收 DCP | Lensfun 配置文件 + DNG 内嵌 profile |
| 功耗/集成 | Apple ANE 推理，ColorSync/EDR/CIContext 零成本集成 | NN 跑 Metal GPU（其 "Neural Engine" 为自起名）；CUDA/OpenCL/Metal 三后端全自养 |
| 维护成本 | ≈0（系统更新即得） | 养 C++ 解码器工程 + 三套 GPU 后端 + 上游跟进 |

**选 RAW 9 永久让渡的三样（架构性不可逆）**：
1. **去马赛克算法选择权**——Apple 不暴露 demosaic 前原始 Bayer/X-Trans 数据，算法菜单是**架构上做不了**（非"未移植"），除非整条解码链换掉。
2. **raw 域高光重建**——inpaint-opposed 必须在 demosaic 前操作原始通道数据；CIRAW 交付的已是开发完图像，过曝已裁死。本项目最多做后处理近似（修复笔刷/邻域填充级），做不了数学重建。
3. **新机身空窗期**——只能等 Apple 名单更新；缓解 = v2 预留 libraw 兜底解码（仅限特定不支持机型，本文 What NOT to Use 节已登记）。

**RAW 9 反赢的三样**：融合降噪（Alcedo 目前为零）、ANE 功耗、解码器零维护。解码速度对交互影响有限（每图解一次，视口走缓存，ANE 快慢只体现在开图首屏延迟）。

**结论（LESSONS 级）**：**CIRAW 边界即产品边界**——凡需要 raw 域数据的功能（demosaic 算法菜单、真 inpaint-opposed 高光重建）在 CIRAW 路线下应尽早从路线图明确降级或标记 v2+（libraw 兜底路径），后续 phase 规划不再重复撞这堵墙。另注：本文与 AGENTS.md 中 darktable `.cl` kernel「line-by-line port」表述受 GPL-3.0（darktable/Alcedo）vs MIT（本项目）许可约束，实际应为「算法参考、独立实现」——表述修订留晨审裁决。

### Darktable iop coverage reference
Darktable ships **96 iop source files** in `src/iop/` (counted). Of these, ~10–15 are covered by Core Image natively (exposure, baseline, WB, basic NR, basic sharpen, flip, crop, lens-embedded). The remaining ~80 are Metal-port work, phased over v1→vN. The OpenCL kernels in `data/kernels/*.cl` are **direct line-by-line port sources** for the Metal shaders — this is the project's single biggest algorithmic asset.

---

## RAW Format Support Breadth

Apple's system-level RAW decode (via ImageIO, consumed by Core Image) is **broad and the only practical choice for a single-developer project**. Per Apple support article **120534** (macOS Sequoia, current July 2025) and **122870** (macOS 26 Tahoe):

| Format | Apple-native decode | Notes |
|---|---|---|
| **DNG** (all) | **Yes** | "Basic support for RAW files in DNG format, even when captured by cameras not listed" — Apple's universal fallback. |
| **Canon CR2 / CR3** | **Yes** | CR3 from EOS R1/R3/R5/R5 II/R6 II/R7/R8/R10/R50/R100 all listed. Note: macOS 15.4 had a CR3 preview regression (community reports). |
| **Nikon NEF** | **Yes** | Including Z9, Z8, Z6III, Zf, D6, D850, etc. (lossless RAW only on newest bodies — see footnotes in 120534). |
| **Sony ARW** | **Yes** | Including A1, A1M2, A7R V, A7 IV, A9 III, FX3, etc. |
| **Fuji RAF** (X-Trans + Bayer) | **Yes** | X-T5, X100VI, X-H2, X-H2S, GFX100 II, GFX100S II, etc. (Note: X-Trans demosaic quality is exactly where RAW 9's ML engine pays off.) |
| **Panasonic RW2** | **Yes** | GH5/GH6/GH7, S5II, etc. |
| **Olympus / OM System ORF** | **Yes** | OM-1, OM-1 II, OM-5. (Some High-Res Shot modes excluded — see footnotes.) |
| **Pentax PEF** | **Yes** | K-3 III, K-1, etc. |
| **Leica DNG/RWL** | **Yes** | M11, Q3, SL2, S2, etc. |
| **Phase One IIQ** | **Yes** | IQ1 100MP, IQ3 100M listed. |
| **Hasselblad 3FR** | **Yes** | X2D-100C, H6D-100c, X1D-50c, CFV-50c. |
| **Sigma X3F (Foveon)** | **Partial** | Only Sigma BF listed in 120534 — Foveon support is thin. |
| **Newly announced bodies (last ~6 months)** | **Often lagging** | Apple's list lags camera launches by months; e.g., EOS R5 M2 CR3 and OM-1 II ORF had multi-month gaps. This is an **inherent risk** of the CIRAW-only path. |

**Gap assessment:** For the target user (Fuji GFX100S/Sony A7R V/Phase One 100MP medium-format), Apple's decode is complete. The risk is *new* camera bodies launching after Lightamer's release — mitigation is to recommend users update macOS (Apple adds cameras via OS updates), not to ship a libraw fallback in v1.

**libraw / dcraw fallback:** Defer. Adding libraw (C++) breaks the "minimal native dependency" constraint and adds a second decode path to maintain. Revisit only if a specific user-critical camera is unsupported by Apple for >12 months.

---

## Export Format Encoder Matrix

| Format | Native path | Library needed | Notes |
|---|---|---|---|
| **JPEG** | `CGImageDestination` (UTI `public.jpeg`) | None | Always available. Use `kCGImageDestinationLossyCompressionQuality` for quality. |
| **PNG** | `CGImageDestination` (UTI `public.png`) | None | Always available. 8/16-bit. |
| **TIFF** | `CGImageDestination` (UTI `public.tiff`) | None | Always available. 8/16/32-bit float, compression options via `kCGImagePropertyTIFFDictionary`. |
| **HEIF / HEIC** | `CGImageDestination` (UTI `public.heic` / `org.heif`) | None (decode+encode native) | Decode since macOS 13; **encode native since macOS 13** (Safari/media) and exposed via `CGImageDestination` on macOS 13+. HEIC 10-bit, alpha supported. |
| **WebP** | `CGImageSource` decode only (macOS 11+); **no native `CGImageDestination` encode** even on macOS 26 | **Yes — always** | Confirmed by community: macOS Tahoe added AVIF to `CGImageDestinationCopyTypeIdentifiers()` but **WebP write is still missing**. Ship a Swift Package: **`WebP.swift`** / **`swift-libwebp`** (libwebp binding). |
| **AVIF** | `CGImageDestination` (UTI `public.avif`) — **macOS 26 (Tahoe)+ only** | **Yes, below macOS 26** | Native AVIF *write* via `CGImageDestination` landed in macOS Tahoe. On macOS 14/15 floor, ship **`avif.swift`** / **`swift-libavif`** (libavif binding, supports 8/10/12-bit, AV1 encode). Decode is native everywhere (macOS 13+). |

**Practical export architecture:**
- Build an `ExportEncoder` protocol with one implementation per format.
- JPG/PNG/TIFF/HEIF → straight `CGImageDestination`.
- WebP → `WebP.swift` always.
- AVIF → if `#available(macOS 26, *)` use `CGImageDestination` with `public.avif`; else `avif.swift`.
- This keeps the dependency tree to **2 SPM packages** (libwebp binding, libavif binding), satisfying the minimal-dependency constraint.

---

## Recommended macOS Floor

**Recommendation: deployment target macOS 14 (Sonoma), with macOS 26 (Tahoe) strongly recommended as the *practical* runtime for the full feature set.**

Rationale, by factor:

1. **SwiftUI maturity — macOS 14 is the realistic floor.** `NavigationSplitView`/`NavigationStack` debuted in macOS 13 (Ventura) with significant bugs; macOS 14 (Sonoma) is where they stabilized, and macOS 14 also gives you `Observable`, `String Catalog` (zh/en localization), and the modern `SwiftData` option for the session/recent-list metadata. Going below 14 buys almost no users and costs real SwiftUI pain.

2. **Metal 3 features — available from macOS 13.** All the load-bearing Metal features for an image editor (compute kernels, tile memory, programmable blending, rasterization order groups Tier 2, `half` throughput, build-time shader compilation) ship in macOS 13+. Mesh shaders (not needed for 2D photo work) are also macOS 13+. So Metal does not force the floor above 13.

3. **Core Image RAW 8 vs RAW 9 — RAW 8 is the floor for the first ~12 months.** RAW 9 (the CoreML-fused demosaic+denoise) ships in **macOS 27 (fall 2026)** and is opt-in with a limited camera list at launch. macOS 26 (Tahoe) is the current OS and ships RAW 8. **You cannot require macOS 27 at launch** — its install base will be near-zero in late 2026. Plan to *opt in* to RAW 9 when available (`if #available(macOS 27, *)`) and fall back to RAW 8 otherwise.

4. **AVIF native encode — gated to macOS 26.** If you target macOS 14/15, you must ship `libavif` for AVIF out. This is fine (small SPM dep) but is the single biggest "Tahoe would remove a dependency" lever.

5. **Install base (August 2026):** macOS 26 (Tahoe) is the shipping current OS; macOS 15 (Sequoia) sits around ~20%; macOS 14 (Sonoma) around ~4%; macOS 13 negligible. (TelemetryDeck / BusinessStats mid-2026 figures.) Targeting **macOS 14** captures ~100% of the addressable base; targeting **macOS 15** loses ~4% but gains little concrete; targeting **macOS 26** loses the ~24% on Sequoia but removes the AVIF dependency and aligns with where pro photo users actually are (they upgrade fast).

**Final prescriptive call: set `MACOSX_DEPLOYMENT_TARGET = 14.0`**, gate Tahoe-only features (native AVIF encode, any RAW 9 adoption later) behind `#available`, and document macOS 26 as the recommended runtime in the README. Re-evaluate the floor upward to macOS 26 once Tahoe adoption crosses ~70% (likely mid-2027).

---

## What NOT to Use

| Do NOT use | Why |
|---|---|
| **OpenCV** | A general-purpose computer-vision library, not a photo-iop pipeline. Its image ops are CPU-bound, bring a large C++ dependency, and duplicate what Metal compute + MPS already do on-GPU. The iop algorithms you need (filmic, denoiseprofile, toneequal) are not in OpenCV anyway — they are in Darktable's `.cl` kernels, which port directly to MSL. |
| **Electron / Qt / Flutter** | Directly violates the macOS-native + Metal-direct-render + SwiftUI constraints in `PROJECT.md`. Electron/Qt also cannot render into `CAMetalLayer` EDR or interop with `CIRAWFilter`/ColorSync cleanly. yiyin (Electron+Svelte) is being *replaced* by a native Swift panel, not supplemented. |
| **libraw / dcraw as a primary decode path** | Apple's ImageIO/Core Image already decodes ~600+ cameras natively with Apple-Silicon GPU acceleration and tight ColorSync integration. Adding libraw doubles the decode surface, adds C++, and fights the minimal-dependency constraint. Use **only** as a fallback for specific unsupported cameras, and only if a real user need appears (defer to v2+). |
| **SDL / GLFW / GLKit for the viewport** | These are OpenGL-era or cross-platform windowing layers. macOS deprecated OpenGL years ago; the direct-render viewport must be `MTKView`/`CAMetalLayer` (via `NSViewRepresentable`) to get Metal 3, EDR, and zero-copy `CIContext` interop. GLKit is iOS-only and deprecated. |
| **Lensfun (C++) as a hard dependency in v1** | Lensfun is excellent but is C++ with a data-update burden. For v1, prefer (a) relying on DNG-embedded lens opcodes (CIRAW applies them), and (b) shipping Lensfun's XML *data* (read-only) + a Metal warp shader for the user-tunable lens iop, rather than linking the C++ lib. Revisit linking Lensfun proper only if the data-only approach proves insufficient. |
| **A custom RAW decoder** | Out of scope for a single-developer project. Apple's decoder is good and getting materially better (RAW 9). Spend the effort on the Metal iop pipeline instead. |
| **JPEG/WebP/AVIF via ImageMagick** | Massive C dependency, wrong tool. Use `CGImageDestination` + two tiny SPM bindings (libwebp, libavif). |
| **Cross-platform color libs (Little-CMS standalone, skia)** | ColorSync is the macOS-native ICC engine and is already wired into Core Image/`CIContext`. Little-CMS is what Darktable uses cross-platform; on macOS you get its equivalent for free via ColorSync. |

---

## Open Questions for Downstream Phases

1. **RAW 9 adoption timing.** When macOS 27 ships (fall 2026), which cameras does RAW 9 actually support at GA? (Beta = X-T5/X-T50 only.) Decision: opt-in to RAW 9 per-image when `decoderVersion "9"` is in `supportedDecoderVersions`, else RAW 8. Needs a spike on macOS 27 GM.
2. **Demosaic algorithm menu — ship or not?** If the Darktable-equivalent per-method demosaic menu (RCD/AMaZE/VNG/Mark.3-pass/dual) is a hard requirement, that is a large Metal port (`demosaic_rcd.cl` is ~200 lines, `demosaic_markesteijn.cl` is ~700). Decide whether v1 ships Apple-internal demosaic only.
3. **Lens correction scope.** Confirm whether embedded DNG opcodes + a manual distortion/CA/vignette slider set is acceptable for v1, or whether Lensfun-database-driven correction is a launch requirement. Affects whether to link Lensfun C++ or stay data-only.
4. **DCP support.** Do target users need Adobe DCP camera profile loading? If yes, scope a DCP reader + Metal application; if no, rely on embedded matrices.
5. **ACES working space.** Is ACEScg/ACES2065-1 a v1 requirement (needs shipping the ACES ICC) or a v2 feature? Display P3 + ProPhoto cover most photographers.
6. **EDR/HDR soft proofing depth.** Full EDR preview (scene-referred floats >1.0 on an HDR display) is well-supported; confirm the target HDR displays (XDR, OLED Pro) and whether HDR *export* (HEIC 10-bit gain map, AVIF 10/12-bit) is in scope.
7. **yiyin port surface.** Confirm the exact yiyin border/watermark layout algorithms to port to Core Graphics/Core Text (separate research dimension).
8. **Sidecar XMP binary compatibility with Darktable.** The XMP schema must round-trip; needs a dedicated spec spike (separate research dimension).

---

## Sources

### Apple developer documentation
- Core Image — `CIRAWFilter`: https://developer.apple.com/documentation/coreimage/cirawfilter
- `CIRAWFilterOption` keys: https://developer.apple.com/documentation/coreimage/cirawfilteroption
  - `decoderVersion`: https://developer.apple.com/documentation/coreimage/cirawfilteroption/decoderversion
  - `supportedDecoderVersions`: https://developer.apple.com/documentation/coreimage/cirawfilteroption/supporteddecoderversions
  - `noiseReductionAmount`: https://developer.apple.com/documentation/coreimage/cirawfilteroption/noisereductionamount
- RAW Image Options: https://developer.apple.com/documentation/coreimage/raw-image-options
- `CGImageDestination`: https://developer.apple.com/documentation/imageio/cgimagedestination
- `CGImageDestinationCreateWithURL`: https://developer.apple.com/documentation/imageio/cgimagedestinationcreatewithurl(_:_:_:_:)
- Metal — Tailor your apps for Apple GPUs and tile-based deferred rendering: https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering
- Metal — HDR content: https://developer.apple.com/documentation/metal/hdr-content
- SwiftUI — `NavigationSplitView`: https://developer.apple.com/documentation/swiftui/navigationsplitview
- Metal 3 — mesh shaders: https://developer.apple.com/documentation/metal/adjusting-the-level-of-detail-using-metal-mesh-shaders

### WWDC sessions
- WWDC26/305 — Enhance RAW image processing with Core Image (RAW 9): https://developer.apple.com/videos/play/wwdc2026/305/
- WWDC22/10054 — The SwiftUI Cookbook for Navigation (`NavigationSplitView`/`NavigationStack`)
- WWDC22/10114 — Display EDR content with Core Image, Metal, and SwiftUI
- WWDC21/10161 — Explore HDR rendering with EDR
- WWDC21/10160 — Capture and process ProRAW images
- WWDC20/10602 — Harness Apple GPUs with Metal (programmable blending)
- WWDC20/10632 — Optimize Metal Performance for Apple silicon Macs
- Tech Talks 604 — Metal 2 tile shading; Tech Talks 605 — raster order groups

### Apple support / news
- Digital camera RAW formats supported by iOS 18 / macOS Sequoia (120534): https://support.apple.com/en-us/120534
- Digital camera RAW formats supported by iOS 26 / macOS 26 (122870): https://support.apple.com/en-us/122870
- Reddit (r/MacOSBeta) — Tahoe brings native AVIF writing via `CGImageDestination`: https://www.reddit.com/r/MacOSBeta/comments/1lb4ayr/tahoe_brings_support_for_writing_avif_files/

### RAW 9 / news analysis (August 2026)
- PetaPixel — Apple's RAW Processing is Finally Evolving After a Decade: https://petapixel.com/2026/06/10/apples-raw-processing-is-finally-evolving-after-a-decade-and-its-a-big-deal/
- 9to5Mac — iOS 27's new RAW 9 engine: https://9to5mac.com/2026/07/06/apple-overhauls-raw-photo-processing-with-ios-27-showcases-impressive-results/
- DPReview forums — Apple Raw Engine v9 hands-on (macOS 27 beta, camera list): https://www.dpreview.com/forums/threads/apple-raw-engine-v9-new-noise-reduction-king.4838453/
- DPReview — Apple Core Image RAW 9 processing: https://www.dpreview.com/articles/6744459009/apple-core-image-raw-9-processing/
- RedSharkNews — Apple RAW 9 CoreML denoising: https://www.redsharknews.com/apple-raw-9-core-image-machine-learning-denoising

### macOS install-base statistics
- TelemetryDeck — macOS versions market share 2026: https://telemetrydeck.com/survey/apple/macOS/versions/
- BusinessStats — worldwide macOS version market share: https://businesstats.com/worldwide-macos-version-market-share/

### Swift Package options for non-native formats
- `avif.swift` (libavif binding): https://github.com/awxkee/avif.swift

### Darktable reference sources inspected (local)
- `/Volumes/UNITEK/Documents/Development/darktable/src/iop/` — 96 iop modules (counted). Key files for Metal porting: `demosaic.c`, `denoiseprofile.c`, `filmicrgb.c`, `sigmoid.c`, `colorbalancergb.c`, `colorzones.c`, `channelmixerrgb.c`, `toneequal.c`, `diffuse.c`, `lens.cc`, `cacorrect.c`, `cacorrectrgb.c`, `sharpen.c`, `rgbcurve.c`, `rgblevels.c`, `retouch.c`, `liquify.c`, `lut3d.c`.
- `/Volumes/UNITEK/Documents/Development/darktable/data/kernels/` — OpenCL `.cl` kernels that port line-by-line to Metal Shading Language: `demosaic_rcd.cl`, `demosaic_ppg.cl`, `demosaic_markesteijn.cl`, `demosaic_vng.cl`, `denoiseprofile.cl`, `nlmeans.cl`, `filmic.cl`, `sigmoid.cl`, `colorbalancergb.cl` (in `extended.cl`), `locallaplacian.cl`, `guided_filter.cl`, `diffuse.cl`, `sharpen.cl`, `lut3d.cl`, `basic.cl` (CA, hot pixels), `atrous.cl`, `gaussian.cl`, `blendop.cl`.
- `/Volumes/UNITEK/Documents/Development/darktable/src/common/colorspaces.c` — reference for ICC profile matrices (ProPhoto, Rec2020, Rec709 primaries) and ColorSync-equivalent conversions.
- `/Volumes/UNITEK/Documents/Development/darktable/src/develop/pixelpipe.c` — reference for the iop pipeline order and cache/tile architecture (maps to a Metal command-buffer pipeline).

### Project context
- `/Volumes/UNITEK/Documents/Development/Lightamer/.planning/PROJECT.md`
