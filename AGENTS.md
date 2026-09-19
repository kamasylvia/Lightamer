<!-- GSD:project-start source:PROJECT.md -->

## Project

**Lightamer**

Lightamer 是一个 macOS 原生（Swift 6 + SwiftUI + Metal 3 直渲 + Core Image RAW）的 RAW 编辑器与图片管理器，目标是对标 Darktable 的全量图像处理（iop）能力，同时采用 Capture One 的 Session 工作流（文件夹即会话）+ Capture One 风格的调整图层（adjustment layers）来组织照片与局部调整。它面向摄影作者，把"调整 → 评分 → 批量导出 → 印框/水印出图"压缩成一个原生丝滑的工作流，并内置壹印（yiyin）的印框/水印能力作为一等公民面板。

**Core Value:** 在 macOS 上用 Metal 加速提供 100MP+ 大图下零延迟的 RAW 调整体验，并让 Capture One Session 工作流与 Darktable 级调整深度在同一原生 app 中共存——这是目前市面没有的组合。

### Constraints

- **平台**：macOS 专属（Swift 6）— 最低版本 **macOS 27**（Lock-early 决策，研究阶段确认）。理由：原生 CIRAW 9 Neural Engine demosaic+denoise、原生 AVIF 写入、最新 SwiftUI/Metal 3 成熟度。代价：覆盖机型窄，但开源项目且个人自用可接受
- **语言/运行时**：Swift 6 + SwiftUI + Metal 3 + Core Image（CIRAW，macOS 27 起原生 RAW 9）+ ImageIO + ColorSync/EDR — 不引入跨平台框架（Electron/Qt/Flutter 等）
- **渲染架构**：Metal 直渲（MTKView/MTLTexture）作为主编辑视图 — 从第一天就按此架构，避免后期重写
- **色彩管线**：working space = linear Rec2020 scene-referred；pixelpipe 数据类型 = float32 RGBA（Lock-early，与 Darktable modern pipeline 对齐，便于移植 filmicrgb 等 iop）
- **照片管理**：Capture One Session 模式 — 文件夹即会话，三级子目录（Capture/Crop/Output）+ sidecar 调整文件（Lightamer 自有格式），不做中央库
- **局部调整**：Capture One 风格 adjustment layers（每层独立 iop + 蒙版 + 混合模式）— 与 Darktable 全局 pixelpipe+per-iop-mask 架构不同，需在 pixelpipe 设计时纳入
- **分发**：开源免费、独立分发（Developer ID 签名 + 公证，不做沙盒）— GitHub 开源
- **功能对标**：对标 Darktable 全量（91 个 iop 模块）— 长期工程，Fine 粒度分阶段交付，v1 不设上限但分阶段逼近
- **互通性（决策）**：sidecar 与 Darktable **不互通、不兼容**（研究确认二进制兼容做不到）；预设与 Darktable/Lightroom **不互通**；标准 EXIF/IPTC/XMP 元数据仍读写（与其他工具兼容）
- **依赖最小化**：能用 Apple 原生框架（Core Image / Metal / Core Text / ImageIO / AVFoundation / ColorSync）实现的不引入第三方库；v1 预期仅 libwebp、libavif 两个 SPM 依赖（WebP 写入 macOS 仍无原生；AVIF macOS 27 起原生但保留 libavif 作为兜底）

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Summary

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

## Core Image RAW 9 Capability Boundary

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

### Darktable iop coverage reference

## RAW Format Support Breadth

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

## Export Format Encoder Matrix

| Format | Native path | Library needed | Notes |
|---|---|---|---|
| **JPEG** | `CGImageDestination` (UTI `public.jpeg`) | None | Always available. Use `kCGImageDestinationLossyCompressionQuality` for quality. |
| **PNG** | `CGImageDestination` (UTI `public.png`) | None | Always available. 8/16-bit. |
| **TIFF** | `CGImageDestination` (UTI `public.tiff`) | None | Always available. 8/16/32-bit float, compression options via `kCGImagePropertyTIFFDictionary`. |
| **HEIF / HEIC** | `CGImageDestination` (UTI `public.heic` / `org.heif`) | None (decode+encode native) | Decode since macOS 13; **encode native since macOS 13** (Safari/media) and exposed via `CGImageDestination` on macOS 13+. HEIC 10-bit, alpha supported. |
| **WebP** | `CGImageSource` decode only (macOS 11+); **no native `CGImageDestination` encode** even on macOS 26 | **Yes — always** | Confirmed by community: macOS Tahoe added AVIF to `CGImageDestinationCopyTypeIdentifiers()` but **WebP write is still missing**. Ship a Swift Package: **`WebP.swift`** / **`swift-libwebp`** (libwebp binding). |
| **AVIF** | `CGImageDestination` (UTI `public.avif`) — **macOS 26 (Tahoe)+ only** | **Yes, below macOS 26** | Native AVIF *write* via `CGImageDestination` landed in macOS Tahoe. On macOS 14/15 floor, ship **`avif.swift`** / **`swift-libavif`** (libavif binding, supports 8/10/12-bit, AV1 encode). Decode is native everywhere (macOS 13+). |

- Build an `ExportEncoder` protocol with one implementation per format.
- JPG/PNG/TIFF/HEIF → straight `CGImageDestination`.
- WebP → `WebP.swift` always.
- AVIF → if `#available(macOS 26, *)` use `CGImageDestination` with `public.avif`; else `avif.swift`.
- This keeps the dependency tree to **2 SPM packages** (libwebp binding, libavif binding), satisfying the minimal-dependency constraint.

## Recommended macOS Floor

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

## Open Questions for Downstream Phases

## Sources

### Apple developer documentation

- Core Image — `CIRAWFilter`: https://developer.apple.com/documentation/coreimage/cirawfilter
- `CIRAWFilterOption` keys: https://developer.apple.com/documentation/coreimage/cirawfilteroption
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

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

### 语言与沟通
- 用户面向输出（问题、解释、状态总结）使用中文；代码、API 名称、文件路径、技术术语保持英文。
- 每轮对话完成后，如有需要，更新 TODO.md 和 AGENTS.md（继承自全局指南）。

### 提交与 Issue（继承全局规则）
- 提交代码前确保有对应 GitHub issue。commit message 末尾用 `fixes #NN` / `closes #NN` / `refs #NN` 关联 issue；已推送的 commit 在 issue 描述里反向引用。
- 若仓库 issues 被禁用，先询问用户是否启用；不启用则跳过此规则并说明原因。

### Swift / macOS 工程约定
- **最低部署目标**：macOS 27（`@available(macOS 27, *)` 用于 RAW 9 等独占能力；不向下兼容到 macOS 26 及以下）。
- **UI**：SwiftUI 优先；Metal 视图通过 `NSViewRepresentable` 包装 `MTKView` 桥接。不引入 AppKit-only 的 UI 模式除非 SwiftUI 无法满足。
- **色彩管线**：working space = linear Rec2020 scene-referred；pixelpipe 内部一律 float32 RGBA premultiplied-alpha。不混用半精度（half）于阴影敏感路径。
- **iop 模块**：每个 iop 一个 `.swift`（参数 + `IOPModule` 协议实现）+ `.metal`（compute kernel）文件对；模块顺序遵循 Darktable `v50_order`。
- **RAW 解码**：一律走 `CIRAWFilter`（macOS 27 起 opt-in RAW 9）。不引入 libraw/dcraw 作为主解码路径。
- **依赖最小化**：能用 Apple 原生框架（Core Image / Metal / Core Text / ImageIO / AVFoundation / ColorSync / Vision）实现的不引入第三方库。预期仅 libwebp、libavif 两个 SPM 依赖。
- **非破坏性**：所有调整存为参数序列（history stack）+ Lightamer 自有 sidecar 格式；原文件永不被修改。sidecar 不与 Darktable 二进制兼容。
- **测试**：iop 算法移植必须有 golden-image 测试（对照 Darktable 参考输出）；性能有 60fps@100MP 预算。

### 参考项目
- **Darktable**（`/Volumes/UNITEK/Documents/Development/darktable`）：iop 算法、OpenCL kernel（`data/kernels/*.cl` → Metal 移植）、pixelpipe 架构、色彩管理的源码参考。
- **yiyin / 壹印**（`/Volumes/UNITEK/Documents/Development/yiyin`）：边框/水印面板的功能对齐参考（重写为 Swift，yiyin 项目独立维护）。

### Phase 2 架构增量（2026-09-19，Plan 02-06 签核批）
- **Sidecar（`.lra`）**：JSON schemaVersion 1，`<原文件完整名>.lra` 与原片同目录，`.xmp` 永不读写删。**所有入盘 UInt64 哈希一律 decimal String**（`UInt64String` wrapper；FNV-1a 64 超 2^53，JSON number 会被非 Swift 工具降精度）——ONE-WAY 格式锁，后续持久化文档（Phase 6 layer、Phase 11 export manifest）沿用同规则。`paramsData` 保持 Data→base64（字节精确 > 可读性）。
- **持久化身份哈希一律 `StableHash`（FNV-1a 64）**；Swift `Hasher` 与未排序 JSON 字节禁止进入任何跨进程身份（L013）。
- **SidecarStore**：per-image actor，2s debounce 合并写 + 同目录 tmp 原子晋升（L009：禁止 /tmp 跨卷 rename）；`flushNow()` 在切图与 `applicationWillTerminate`（AppDelegate 同步回调 + 5s 有界等待）强制。
- **clearCaches 分层**：`PipeCache.enforceBudget(keeping:)` 纯策略执行器（阈值可注入）+ `MetalContext.clearCICaches()`（CI/RawCamera 内部态）+ PSO 缓存永不清；触发 = load 入口 + 60s Task sweep（Timer 只做调用者）。>500MB 释放才 toast（D-26）。
- **GPU 读回纪律（L014）**：`getBytes` 不等 in-flight encoder——测试/探针读回前必须 fence（`drain()` 模式）；CI 腿（convertTexture）读纹理前已有 fence 固化在源。
- **目录惯例**：`LightamerCore/Sources/{Pipe,Sidecar,Metal,Decode,Foundation,Layers}`；sidecar 读写器放 Core（App 不可 import 进单测——02-05/02-06 连续以"Core 级孪生 + 构建走查 + 进程内探针"验证 App 层）。
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `$gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `$gsd-debug` for investigation and bug fixing
- `$gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `$gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
