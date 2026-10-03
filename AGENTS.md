<!-- GSD:project-start source:PROJECT.md -->

## Phase 执行模型（2026-09-20 用户指令，强制）

Phase **execute** 阶段的执行分工固定为两级：

1. **执行 = omp**（无头 CLI）：每个 plan 由 `omp -p --auto-approve --thinking max "<执行 prompt>"` 在项目根目录无头执行。单测标准命令（2026-09-22 起）= `Scripts/test-direct.sh`（直启宿主，绕开 testmanagerd——根治 enrollment 弹窗，见 LESSONS L019b）；`xcodebuild build` 照常构建（不触发弹窗）；`xcodebuild test` 保留给 UITests/xcresult 需求。执行 prompt 指向 plan 文件，要求按任务序推进（read_first → action → 验收标准逐条核验）、每任务独立提交（Conventional Commits，只 add 相关文件）、构建用 `caffeinate -dis` 包裹。产出 SUMMARY.md 后收工。
2. **验收 = ZCode subagents**：omp 完成后，派 general-purpose subagent 独立验收——按 plan 验收标准逐条核对、跑全套测试、抽查实现与 AC 一致性。发现 issue 回注 omp 修复或验收方直接修（小改动）。

**规则**：
- omp 运行期间保活巡检**不得重复启动**同一 plan（检查 `.work/GSD-PROGRESS.log` 尾部 + git log 判断）。
- omp 的提交即执行产出；subagent 验收发现的问题修复提交以 `fix(...)` 标注并可引用 omp 产物。
- 人工只处理 GOAL-STATE「阻塞（需人工）」章节登记的事项。

## 资源监控（2026-09-29 用户指令，强制）

开发过程中**持续监控 Lightamer 相关进程**（GUI app 与 test-direct.sh 直启测试宿主在活动监视器里同名，都叫 Lightamer——按命令行/父进程区分，处置线不同，见下）：

- **GUI app 触发线（不变）**：内存占用 >3G，或 CPU 占用持续异常偏高（非构建态 >50% 持续分钟级）→ **立刻介入**：`sample <pid> 3` 采栈定位 + 向 orchestrator/用户上报处置，不得放任。
- **测试宿主口径（M2-4-0 落地 + SPIKE 门修订，2026-09-30）**：全套回归经 `Scripts/test-direct.sh --all` 分 7 个域 bundle 跑（一条命令，逐 bundle 独立宿主进程），峰值 RSS 由脚本按 `/usr/bin/time -l` ru_maxrss（内核精确口径）机检 MEMFAIL，**运行门 = 8G**（`RSS_LIMIT_MB=8192`）。原 <3G 门经 SPIKE（commit `70e09e5`）**证伪为错定门槛**：by-design GB 级重测（100MP golden/parity 族，验证对象 = 100MP float32 平面）单类自峰 TilingOverlap 7865 / HDR 5913 / QuickLook 4589MB + ~1.4G 框架分页一次性地板，<3G 数学不可达、与 bundle 划分无关，真实跨测残留仅 0.18-2.4MB/test（证据正本 = `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-SPIKE.md`）。**全套 `--all` 轮仍须 orchestrator 批准 + 运行中保持监视**（现另有 MEMFAIL 机检兜底，>8G 或内存压力转红仍立即 kill）；定向单 bundle 轮（`--bundle <name>`）可常跑，机检兜底；贴线 bundle（IOP 7654 / IOPParity 5788）连续 MEMFAIL 先查重测顺序漂移（±3% 方差，SPIKE 注记）。旧单宿主 2165 连跑已废（历史事件：10.4G 未响应 / 7.5G 用户强杀）。
- 巡检 cron 每次运行附带查一眼 Lightamer 进程资源（`ps aux | grep -i lightamer`）。

## 暂停机制（2026-09-24 用户指令，Phase 7 起强制）

**`.work/config.toml [gsd]` 开关**（2026-09-24 起替代旧 PAUSE 文件）——两个字段，消费方每任务边界与派发前必读：

- **`paused = true`**：全链路停——巡检不推进、subagent worker 任务边界干净停（在制品已 commit、报告断点）、不派新验收。
- **`auto = false`**：自动流转关——worker 完成当前波后停等用户「继续」（计划性门控）。
- **omp（若使用）**：启动前检查；运行中无法优雅停（用户可杀，commit-per-task 保证已完成任务不丢，重拉从断点续）。
- **恢复** = 用户把字段改回并示意继续。

**C 档门控（关键节点停下等用户确认才继续；PAUSE 文件兜底随时可停）**：
1. Phase research 定稿后停——用户过目裁决点（Open Questions）再 plan。
2. 每个 plan 执行+验收闭环后停——汇报该 plan 战果 + 下一 plan 摘要，等用户确认。
3. Phase 签核（VALIDATION）前停——verify-work 结论给用户过目。

## Project

**Lightamer**

Lightamer 是一个 **macOS 独占的 Alcedo Studio 克隆**（**2026-09-27 用户项目重定义**，覆盖此前「对标 Darktable 全量」与「C1 Session 工作流」两条旧定位）：Swift 6 + SwiftUI + Metal 3 直渲 + **Core Image RAW 9 解码**（Apple Neural Engine demosaic+denoise，不写 RAW 解码器），**UI 与功能面完全模仿 Alcedo Studio**（节点式调色：Develop → Color Grade×N → Display Transform；图库/相册/项目文件；蒙版；DRT；导出选项）。darktable 独有的已交付功能**代码暂时保留但默认不启用**（feature flag 门控）。壹印（yiyin）印框/水印面板保留为一等公民。

**Core Value:** 在 macOS 上把 Alcedo 的编辑体验（节点式调色 + 图库 + DRT + AI 图库功能）用 Swift/Metal/RAW 9 原生重做一遍：100MP+ 大图零延迟、RAW 9 Neural Engine 解码、原生 EDR——比 Alcedo（C++/Qt，自养 LibRaw 解码器，无降噪）更快的解码与降噪、更全的导出格式（保留原 6 格式矩阵），外加 yiyin 印框/水印。

### Constraints

- **平台**：macOS 专属（Swift 6）— 最低版本 **macOS 27**（Lock-early 决策，研究阶段确认）。理由：原生 CIRAW 9 Neural Engine demosaic+denoise、原生 AVIF 写入、最新 SwiftUI/Metal 3 成熟度。代价：覆盖机型窄，但开源项目且个人自用可接受
- **语言/运行时**：Swift 6 + SwiftUI + Metal 3 + Core Image（CIRAW，macOS 27 起原生 RAW 9）+ ImageIO + ColorSync/EDR — 不引入跨平台框架（Electron/Qt/Flutter 等）
- **渲染架构**：Metal 直渲（MTKView/MTLTexture）作为主编辑视图 — 从第一天就按此架构，避免后期重写
- **色彩管线**：working space = linear Rec2020 scene-referred；pixelpipe 数据类型 = float32 RGBA（Lock-early，与 Darktable modern pipeline 对齐，便于移植 filmicrgb 等 iop）
- **照片管理**：**（2026-09-27 项目重定义）Alcedo 方式**——图库 + 相册 + 项目文件承载相册结构与编辑历史；原 Capture One Session / Catalogs 两方案剥离（代码保留、UI 不暴露、默认不启用），存储后端由 Alcedo 测绘研究定
- **局部调整**：**（2026-09-27 项目重定义）Alcedo 节点模型**——Develop → Color Grade×N → Display Transform，每节点独立调整 + 独立蒙版；Nitro Photo 蒙版方案并入；dt per-iop-mask 方案不采用；既有 adjustment layers 基础设施作为底座复用
- **分发**：开源免费 — GitHub 独立分发（2026-09-27 终裁：砍苹果渠道/签名公证，unsigned DMG/zip）
- **功能对标**：**UI 与功能面完全模仿 Alcedo Studio**（2026-09-27 项目重定义）；dt 独有已交付功能代码保留但默认禁用（feature flag）；raw 域 Alcedo 能力（demosaic 算法菜单/高光重建）在 CIRAW 路线下不可达，不入对标范围（STACK.md Decoder 策略对比节）。Core Image RAW 9（macOS 27 Neural Engine demosaic+denoise）覆盖的直接用，缺口用 Metal compute shader 自实现
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

- `/Volumes/external volume/Documents/Development/darktable/src/iop/` — 96 iop modules (counted). Key files for Metal porting: `demosaic.c`, `denoiseprofile.c`, `filmicrgb.c`, `sigmoid.c`, `colorbalancergb.c`, `colorzones.c`, `channelmixerrgb.c`, `toneequal.c`, `diffuse.c`, `lens.cc`, `cacorrect.c`, `cacorrectrgb.c`, `sharpen.c`, `rgbcurve.c`, `rgblevels.c`, `retouch.c`, `liquify.c`, `lut3d.c`.
- `/Volumes/external volume/Documents/Development/darktable/data/kernels/` — OpenCL `.cl` kernels that port line-by-line to Metal Shading Language: `demosaic_rcd.cl`, `demosaic_ppg.cl`, `demosaic_markesteijn.cl`, `demosaic_vng.cl`, `denoiseprofile.cl`, `nlmeans.cl`, `filmic.cl`, `sigmoid.cl`, `colorbalancergb.cl` (in `extended.cl`), `locallaplacian.cl`, `guided_filter.cl`, `diffuse.cl`, `sharpen.cl`, `lut3d.cl`, `basic.cl` (CA, hot pixels), `atrous.cl`, `gaussian.cl`, `blendop.cl`.
- `/Volumes/external volume/Documents/Development/darktable/src/common/colorspaces.c` — reference for ICC profile matrices (ProPhoto, Rec2020, Rec709 primaries) and ColorSync-equivalent conversions.
- `/Volumes/external volume/Documents/Development/darktable/src/develop/pixelpipe.c` — reference for the iop pipeline order and cache/tile architecture (maps to a Metal command-buffer pipeline).

### Project context

- `/Volumes/external volume/Documents/Development/Lightamer/.work/gsd/PROJECT.md`

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

### 语言与沟通
- 用户面向输出（问题、解释、状态总结）使用中文；代码、API 名称、文件路径、技术术语保持英文。
- 每轮对话完成后，如有需要，更新 `.work/TODO.md` 和 AGENTS.md（继承自全局指南；TODO/LESSONS 真身在 `.work/` 下，**根目录不留垫片**——2026-09-28 用户裁决，引用一律写 `.work/` 真路径）。

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
- **测试**：iop 算法移植必须有 golden-image 测试（对照 Darktable 参考输出）；性能有 60fps@100MP 预算。**新测试文件落域规则（M2-4-0 E2）**：按 `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt` 的域模式归入唯一 target，同批更新 `Project.swift` 对应数组（显式清单无 glob）+ `tuist generate` 恒为该批最后一个动作（L041）；跑法走 `Scripts/test-direct.sh --bundle <域>`。

### 参考项目
- **Darktable**（`/Volumes/UNITEK/Documents/Development/darktable`）：iop 算法、OpenCL kernel（`data/kernels/*.cl` → Metal 移植）、pixelpipe 架构、色彩管理的源码参考。**GPL-3.0——只读参考算法思路，代码不复制入库（本项目 MIT）。**
- **yiyin / 壹印**（`/Volumes/UNITEK/Documents/Development/yiyin`）：边框/水印面板的功能对齐参考（重写为 Swift，yiyin 项目独立维护）。本地仓 = **自维护分叉** `kamasylvia/yiyin`（Electron+Svelte，v1.7.x 起，较上游更优——**参考以此为准**）；上游原仓 = `ggchivalrous/yiyin`（仅追溯用）。
- **Alcedo Studio**（`/Volumes/UNITEK/Documents/Development/AlcedoStudio`，2026-09-27 引入）：开源（GPL-3.0）C++20 RAW 编辑器 + 图库，Windows（CUDA/OpenCL）+ macOS（Metal）双平台，150MP 流畅编辑。参考点：GPU demosaic 算子（`alcedo_studio/src/decoders/processor/operators/gpu/metal_shader/` 下 `debayer_rcd.metal` / `xtrans_interpolate.metal` / `demosaicnet_io.metal`——DemosaicNet 蒸馏神经去马赛克，X-Trans 默认走它）、inpaint-opposed 高光重建、ACES 2.0 / OpenDRT 显示渲染变换（目标色彩空间/传递函数/峰值亮度可选，HDR 直出）、节点式调色图（Develop → 多个 Color Grade 节点 → Display Transform，每节点独立调整+蒙版，与本项目 adjustment layers 模型同构）、大图瓦片式按需渲染 + 多级缓存设计。同 GPL-3.0——只读参考，代码不复制入库。**功能对标正本：Lightamer 的 UI 与功能面完全模仿 Alcedo（2026-09-27 项目重定义）——相关功能规划/实现时去本地源码参考对应实现**（UI/QML 面 `alcedo_studio/src/ui/`、解码算子 `alcedo_studio/src/decoders/`、节点图与渲染 `alcedo_studio/src/`，实机对照 `/Applications/AlcedoStudio.app`）。
- **Lumen RAW**（`/Volumes/UNITEK/Documents/Development/lumen-raw`，2026-10-01 引入）：开源（**MIT**）Windows RAW 编辑器（Python 3.12 + PySide6 + LibRaw + ONNX Runtime）。**借鉴裁决（2026-10-01 用户：5 采纳 / DNG 导出不采纳）**：①MiDaS 单目深度 → IOP-MASK-07 Depth 蒙版数据面 ②Mertens 曝光融合 → IOP-HDR-06 ③全景合成（SIFT/球面投影/分块羽化）→ IOP-PANO-01 ④AI 超分/降噪「可编辑副本」UX → M2AI-09 ⑤AI 推理 worker 进程隔离 crash-safe → M2AI-10。相关功能规划/实现时**去本地源码参考对应实现**（单目深度/自动蒙版 `lumen/auto_masks.py`、AI 增强对话框 `lumen/enhance_dialog.py`、推理 worker 隔离 `lumen/ai_worker.py` + `lumen/host.py`、HDR/全景合并 `lumen/merge.py`、任务调度 `lumen/scheduler.py`）。MIT 许可——可参考算法与模式；如成段移植代码须保留 MIT 归属注记。调研正本 = `.work/gsd/research/LUMEN-RAW-NOTES.md`。
- **SpektraLab**（`/Volumes/UNITEK/Documents/Development/SpektraLab`，2026-10-02 引入）：开源（GPL-3.0 代码；胶片/相纸配置与放大 LUT = CC BY-SA 4.0）macOS 胶片+放大相纸模拟器（81 波长光谱物理建模、28 款实测配置、45MP <1s）。参考点：模拟链阶段分离语义（场景置位→胶片→配光→印相）、宽容度面板+场景置位 UX、CLI+MCP 同会话三前门（与我方 Phase 14 同构）、导出软打样纪律、性能标杆。相关功能（胶片模拟升维/宽容度 UX/MCP 契约）去本地源码与 `rfc/` 参考对应实现；调研正本 = `.work/gsd/research/SPEKTRALAB-NOTES.md`。GPL 代码零复制；CC BY-SA 资产如引入须独立归属。

### Phase 2 架构增量（2026-09-19，Plan 02-06 签核批）
- **Sidecar（`.lra`）**：JSON schemaVersion 1，`<原文件完整名>.lra` 与原片同目录，`.xmp` 永不读写删。**所有入盘 UInt64 哈希一律 decimal String**（`UInt64String` wrapper；FNV-1a 64 超 2^53，JSON number 会被非 Swift 工具降精度）——ONE-WAY 格式锁，后续持久化文档（Phase 6 layer、Phase 11 export manifest）沿用同规则。`paramsData` 保持 Data→base64（字节精确 > 可读性）。
- **持久化身份哈希一律 `StableHash`（FNV-1a 64）**；Swift `Hasher` 与未排序 JSON 字节禁止进入任何跨进程身份（L013）。
- **SidecarStore**：per-image actor，2s debounce 合并写 + 同目录 tmp 原子晋升（L009：禁止 /tmp 跨卷 rename）；`flushNow()` 在切图与 `applicationWillTerminate`（AppDelegate 同步回调 + 5s 有界等待）强制。
- **clearCaches 分层**：`PipeCache.enforceBudget(keeping:)` 纯策略执行器（阈值可注入）+ `MetalContext.clearCICaches()`（CI/RawCamera 内部态）+ PSO 缓存永不清；触发 = load 入口 + 60s Task sweep（Timer 只做调用者）。>500MB 释放才 toast（D-26）。
- **GPU 读回纪律（L014）**：`getBytes` 不等 in-flight encoder——测试/探针读回前必须 fence（`drain()` 模式）；CI 腿（convertTexture）读纹理前已有 fence 固化在源。
- **目录惯例**：`LightamerCore/Sources/{Pipe,Sidecar,Metal,Decode,Foundation,Layers}`；sidecar 读写器放 Core（App 不可 import 进单测——02-05/02-06 连续以"Core 级孪生 + 构建走查 + 进程内探针"验证 App 层）。

### M2-2 架构增量（2026-09-29，M2-2-1..4 执行批）
- **Library 目录惯例**：`LightamerCore/Sources/Library/`（LibrarySchema / ProjectFileStore / LibraryStore / ImportFilter / ImageLinker / ImportService / ExifFold / ExifSearchIndexer / ExifSearchParser / LibraryQueries），Core 级可单测（sidecar 读写器放 Core 原则推广）；App 侧 `App/Sources/Lightamer/Library/`（LibraryProjectController / LibraryPanels / LibraryWelcomeView / ImportModeDialog / ImportProgressView / LibraryPreferences）。
- **`.lalb` 包形态**：单个 SQLite 文件（`<stem>.lalb`）+ `project_meta` 表 manifest + `PRAGMA user_version` 双写；journal = WAL + synchronous=NORMAL + 写批节流 checkpoint（≥2s 或 ≥64 批 OR 语义）+ close 强制 TRUNCATE（close 后 `-wal`==0）；**备份唯一钦定路径 = `ProjectFileStore.backup(to:)`（sqlite3_backup 在线一致性拷）**，裸拷主文件在 WAL 未 checkpoint 时丢尾部事务；移动 = 整项目目录搬移（`Media/` 随行、`.<stem>.lathumbs/` 派生物可弃）；mini-git 四表 / 语义 AI 表 = 注释占位（M2-8/M2-10 激活）。
- **真身边界（OQ-3）**：`.lra` 恒编辑态真相；项目库 = 相册组织 + 检索投影 + 引用（`Image.image_path` 引用式 PathKind 0 项目相对 / 1 卷相对+UUID / 2 绝对+UUID）；`exif_search_*` / 缩略图缓存（`.<stem>.lathumbs/`）全部可重建派生物；一切入包 UInt64 哈希 = DECIMAL TEXT（L013 延续）。
- **剥离门（M2LIB-06/OQ-8）**：`LibraryLegacyGate.isLegacyLibraryRequested(environment:)` = 唯一 env 读点（纯函数可注入）；**`LIGHTAMER_LEGACY_LIBRARY=1`** = QA/回归回切通道（回切后 Sidebar/Settings/ContentView 与 M2-2 前逐字节同构）；默认 false = Sessions/Catalogs 双区 + 模式切换器 + Settings Catalogs 双节全隐，启动面 = 项目工作区最小容器（`ProjectWorkspaceFace`；无项目 → P2 Welcome sheet）；**Settings 页无开关**（防双库并存心智）；求值只在 LightamerApp 组装点一次，视图 body 零 ProcessInfo（M2-1 D-EXEC-1 注入式同款）。File 菜单 Session 项暂未门控（inert 死路由；菜单 IA 收纳归 M2-3）。
- **UserDefaults 键登记**：`library.import.mode` / `library.import.rememberMode` / `library.import.rawExtensions`（ImportDefaults，全量替换语义 + reset）+ `library.recentProjects`（LibraryProjectController，dedupe-move-front 上限 10 + 死路径清扫）+ `lut.library.root`（M2-5-3，LutLibraryStore.libraryRootKey 单源拼写；IOP init 直读 `.standard`，AppPreferences 只承载登记/reset 面——空/缺 = 默认根 `~/Library/Application Support/Lightamer/LUTs/`）+ **导出记忆键族六键（M2-9-04/05）**：`export.lastDirectory`（OQ-3 落点跨会话记忆；picker 即时写回 + run 写回 + 首用回落首图目录）+ `export.jpegQuality` / `export.heicQuality` / `export.avifQuality` / `export.webpQuality`（OQ-10 四格式各一键，Double 0...1，typed 读 + isFinite + qualityRange 域校验，0.0 = 真记忆非未存）+ `export.namingTemplates`（OQ-9 命名模板预设 JSON 数组，NamingTemplateStore 注入式 defaults，三内置不入库）。

### M2-5 架构增量（2026-10-01，M2-5-1..3 执行批）
- **Grade 件族**：GradeCatalog（NodeOwnershipCatalog 同文件 18 目录五元组注册表 + defaultLook 单源）+ ACEScc envelope（LayerCompositeSeam 缝，Core 持有器 IOP 注入；含 ≥1 目录 op 的层子 run 才包夹）+ 七新件（colorWheels/cat02WhiteBalance/contrast/white/black/saturation/tint/hls，v50 RGB 段空位）。V50Order add-only 纪律维持。
- **LUT 库键升级（M2-5-3 KD-1）**：`LutLibraryStore` 的 `installed`/`parsed` 键 = **根相对 POSIX 路径**（`BuiltIn/Foo.cube`；根下文件退化为文件名 = 旧行语义）；`lut3d` params `lutName` 新写入恒存 key，旧档裸文件名引用经**唯一尾段 fallback** resolution 兼容（歧义 = nil = blit identity + toast），**旧档字节零改写**。`InstalledLut.relativePath/subdirectory` = additive optional（synthesized decode 宽容 + init 迁移幂等）。
- **shared holder（checker m6 形）**：`LutLibraryStore.shared` = `private static var sharedInstance` + NSLock（getter 锁内读 + `replaceShared(_:)` 原子换）；`SharedForwardingResolver` = module box 的长寿命转发面（Registry 注册行走 `sharedResolver`）——切根后已建模块恒解析活实例，Lut3dModule 零 diff。
- **可配根（KD-3）**：`lut.library.root`（键拼写单源 = store 公开常量）；切根 = validateRoot（isDirectory + 写探针，L009：不建 bookmark）→ 持久化 → 重造 store → replaceShared；坏根 = 不持久化 + Settings 橙色错误行。
- **内置集 seeder（KD-4）**：bundle `LUTs/` 夹（folder reference——Tuist 4.208 裸目录字符串静默忽略，必须 `Resource.folderReference(path:)`）→ 默认根分支 init 拷入 `BuiltIn/`；哨兵 = 存在且字节数相等跳过（漂移重拷）；可配根零自动拷贝。
- **vendored 胶片集来源纪律**：`Resources/LUTs/` 40 张 = 上游 `JanLohse/spectral_film_lut` v0.18.2（MIT）无头重生成（offscreen GUI 应用默认参数 + 65³ + BW 配 Kodak 2302）；**零字节来自 Alcedo（GPL）**，LICENSE/NOTICE 随包；证据正本 = `.work/gsd/phases/m2-5-color-grade/evidence/spectral-film-lut-license.md`。
- **性能探针惯例**：环境门控 `LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless（默认套件 skip）；探针读钟前必须 queue fence（L014）——无 fence 的 GPU 计时是假数（首版 base 0.3ms 假数即此）。

### M2-6 架构增量（2026-10-01，M2-6-1..3 执行批）
- **DrtRecord（`LightamerCore/Sources/Graph/DrtRecord.swift`）**：document 级 DRT 参数 record（12 顶层 + 53 detailed 浮点，键名 = Alcedo hpp snake_case 终式）+ 四枚举（DrtMethod/DrtEncodingSpace/DrtEotf/DrtLimitingSpace）+ **联动/HDR 判定单源**（`legalEOTFs(for:)` / `isHdrEncoding` / `isDrtRecordDefault`）+ `stableHash()`（FNV-1a over sorted-keys JSON，L013）。预设三件套 = `DrtPresets`（数值事实转录，jedypod GPLv3 只读 + aces-core Apache-2.0 移植；NOTICE 署名）。
- **DRT 尾段策略（`TerminalTailPolicy`）**：`.sdrGamma` / `.edrLinear` / `.drt(DrtTailParams)` 三臂收敛——`.drt` 时 colorout/gamma/borders/watermark + **注入的 Post 四件集**（`DrtTailParams.postOpNames`，App 侧从 `NodeOwnershipCatalog.drtPostOpNames` 算入，Core 不 import IOP）整体降出主链，尾段 sub-run 重放 `[DrtMethodBox 74 → TailOrderedBox 槽 74.1+（Post 四件，原 box 转发仅移序）→ EotfBox 75 → borders 76 → watermark 77]`。尾平面键 = `seed = fnv(recordHash ⊕ policyTag ⊕ postSet(非空才折) ⊕ levelHash[top])`；Post 参数变更只重跑该 box 及之后的尾平面。**pristine 档 = `.sdrGamma` 直通**（「DRT 恒在」是面板概念，渲染面 pristine = 无 DRT 段——与 Alcedo 恒启用语义的显式偏离，KD-1 双保护裁定；晨审若翻 = 传点一处改 `.drt`）。
- **尾平面格式**：EOTF box 起的平面 = 显示格式（SDR 幂/BT.1886 → bgra8、st2084/hlg → 16F、linear → float32）；**EOTF 之前的尾平面（method + Post 四件）恒 working float32**（display-referred 线性，8-bit 线性中间面会断色带）；主链顶面（尾段输入）在 .drt 下同样 float32（P1 的 display-format-input 是质量缺陷，T5 退休）。
- **DRT 持久化四件（rawOverrides 同构）**：WorkspaceModel per-url carrier（缺键 = pristine，**默认 record 不入 map 不写 sidecar**）→ `updateDrtRecord` 写腿（2s debounce）→ `restoreDrtRecordLeg` 恢复腿（nil 零动作/同值跳过/异值回注）→ `terminalTailPolicy(for:)` run 传点（非 pristine → `.drt`，thumbnail 恒 legacy）。document 编辑走 **document 级 history item**（`HistoryItem.drtRecord` additive + `HistoryStack.drtDocumentScope` 忽略面 + `commitDrt`），键族 `history_drt_param/preset/method/encoding`；historyHash 折叠 = `HistoryHash.hash(stack:decodeParamsHash:layerSnapshot:drtRecord:)`（**末位含 drtRecord 的 item 的 stableHash 折入**——无 drt item 的档逐位不变；`driftDetected` 同式重算）。undo/redo/jump 后 carrier 从 history 真相同步（`syncDrtCarrierWithHistory`）。
- **DRT 面板**：`DrtPanelModel`（@Observable；读 = liveRecord → history 投影 → carrier 三级，写 = `EditorState.recordDrtChange` 单 discrete commit）+ `DrtPanelView`（Method 恒展开置顶 + Color & Encoding 默认展开 + aces20 限色组 / opendrt 预设三件套随 method 切换）；EOTF picker 数据源 = `legalEOTFs` 单源（**空间切换吸附同 commit 原子**）；Peak slider = D-H1 三件（live 零 item，松手一 commit）；Peak 钳制 100-1000 在面板（Core 纯函数不钳）。`displayTransformPlaceholder` 枚举 case 保留为槽标记（渲染臂已换 `DrtPanelView`，占位壳文字/accessibility id 零残留）。
- **HDR 视口四态**：legacy SDR-gamma / 手动 EDR-linear / **DRT-SDR（bgra8 + 编码空间 calibrated colorspace）/ DRT-HDR（16F + EDR content + PQ/HLG colorspace）**。colorspace 终式：`itur_2100_PQ/HLG`（**SDK 无 extendedITUR_2100 变体**——PQ/HLG 绝对编码无需扩展）、P3 编码走 `displayP3_PQ/HLG`、SDR 幂 = 编码空间原色 + EOTF gamma 的 calibrated RGB（XYZ 降级 Rec709 近似）、linear = extendedLinearSRGB。**D-COL2 follow gate 扩展 = `!edrActive && !drtTailActive`**（`followGateActive` 纯函数——DRT encoding-space 挂载不被每帧 screen colorspace 覆盖，E3）。手动 EDR 开关与 DRT 尾互斥（coordinator guard 旁路 + 控件置灰）。非 DRT 文档视口逐字节不变（nil drtTail = 08-4 现行为）。
- **Post 四件域（M2DRT-05）**：equalizer/sharpen/bloom/grain 在 DRT 后 display-referred 全图一次（Look 页行原地保留，pre-DRT 注记摘除）；kernel/reference 字节零改（零新 kernel 红线），display 域强度走查观察项挂 gui-acceptance；`panel_note_pre_drt` 键 retired。
- **键族登记**：`history_drt_*` 四键 + `drt_*` 面板键族（技术专名——预设/空间/EOTF 名 zh=英文原文）+ UserDefaults 无新增。
- **method 注册口（M2DRT-06）**：`DrtMethod` 枚举 = [aces20, opendrt]；预留 case 不入枚举（新 method = 加 case，编译期破所有穷举 switch）；`defaultFaceDisabledOpNames` 零 diff（filmic/sigmoid/agx 原地保留）；「parity 后评估回归」挂账面 = 本节注记。
### M2-7 架构增量（2026-10-01，M2-7-3 收口批沉淀）

- **Follow Edges 熔断态（OQ-4-C 行使，可逆）**：UI 默认 mode = `.snap`（`LayerEditingState.followEdgesParams` 单点；Core `FollowEdgesParams.init` 缺省仍 `.streamline`——改默认改 App 消费点不动 Core，FollowEdgesTests 不受扰）。walker 对真实照片脊型失稳已实测（`phases/m2-7-masks/evidence/m2-7-3/probe/probe.log`：8 景盒 × 2 阈值 ≤3 点链、场分辨率/步长扫频 0/3 功能链——非降采样假说），V2 修复方向 = 脊线预提取/亚像素质心/自适应步长；`.streamline` 分支与模式选择器保留，复活零重写。
- **进程内真链探针方法论（GUI pointer 不可达环境的走查通道先例）**：仓库源原文 `swiftc` 直编——单文件级 Core 源（FollowEdges.swift 全文 + MaskPoint verbatim sed 抽取）+ 脚手架 shim（`makeEncoder`/`maskLikeShape` 机械复制，PSO 同步版）+ `.metal` 原文运行时 `makeLibrary(source:)`。全 framework import 路线不可行（swiftinterface 拉 libwebp 模块闭包）。探针源与 log 随 evidence 入库（`phases/m2-7-masks/evidence/m2-7-3/probe/`）。
- **xcstrings 批次追加惯例**：新键块 append 至 `"strings"` 尾部（历史键字节与顺序零触碰，diff = 纯插入）；`zh-audit --check` 的 MISSING 仅覆盖 scanner 可见的静态键——**动态族（Core 映射 label / labelKey stem / switch 返回常量 / 多行 String(localized:)）scanner 不可见**，phase 尾对账须以 SUMMARY 键清单并集核对（M2-7 实例：39 MISSING + 13 动态 = 52 全族）。
- **测试宿主进程清理教训（M2-7-3 执行事故，验收批补登记）**：全套 `--all` 运行中清理 GUI 进程时误杀 IOPParity 测试宿主（`test-direct.sh` 的 HOST_BIN 与 `open` 启动的 GUI 实例路径仅一斜杠之差，截断该 bundle 16/362）——**进程清理前先核 parentage（`ps -o ppid`：测试宿主 parent = 脚本进程树，GUI 实例 parent = launchd）**；处置 = 留证（`evidence/m2-7-3/all_run_incident.log`）后干净重跑全套、终值取净轮，其余六 bundle 两轮逐值一致佐证无连带影响。

### M2-8 架构增量（2026-10-02，M2-8-1..3 执行批——版本面约定正本）
- **sidecar v7 双键拼写冻结**：`versions:[SidecarVersionRecord]?`（id/name/createdAt/updatedAt + 非活跃链复用 FROZEN `{items,position}` 拼写）+ `activeVersionID`（UUID string）；**active 链续住 `history` 键、items 不双写**（全文档 items 计数==1 由 SidecarV7Tests 钉死）；nil 双键 = v6 逐字节零漂移（decodeIfPresent/encodeIfPresent 惯例）；版本结构**不进 historyHash 折叠**（负测钉死——版本元数据非像素语义）。schemaVersionCurrent = 7。
- **`.lalb` version_ref reduced DDL**：v2→v3 迁移激活（5 列：element_id/display_name/created_at_unix/updated_at_unix 系；`head_commit_hash` 不激活）；reservedTableNames 收窄三名（edit_commit/image_edit_state/pipeline_root 维持注释预留）；`replaceVersionRefs` = 单事务整表 reconcile 幂等投影；**投影 sink 注入惯例**（`VersionProjectionSink`，ShellView sink 装配先于 load，KD-5 单源）——后续投影通道立项应复用注入形态，不开第二同步点。pre-migrate `sqlite3_backup` 快照轮换（`pre-migrate.N-M.bak`）= 迁移缝标准形。
- **版本 swap 单路径纪律**：切版本 = 原链写回槽 + 目标链装入 `history` + `rebuildLayerStack()`（param 投影重放单路径，同图零重解码）；swap 零 await MainActor 单转移 + post-swap 快照一次落盘；版本三命令（create/branch/paste）name 参数化、默认名归 UI 层（`versions_default_name` 隐式槽 / `versions_panel_default` 面板面）；materialize-on-first-create；dangling activeVersionID typed degrade 整体落结构保历史。pristine 收窄语义：「.lra 缺席 = 观感 pristine」——一切编辑判定面按 items/position（`has_edits = history.position >= 0`），版本结构不翻转判定（M2-8-3 端到端差分复核在案）。
- **Copy Adjustments 排除面单源**：`isAdjustmentTransferable` 单谓词（owner==.grade + terminal trio 显式排除集写死）；粘贴 = OVERWRITE-paste epoch 复用（`pasteEpochScope` 既有投影语义）+ DRT 第二 item + 蒙版 `contentRevision` 置 nil（新身份新纪元）。
- **走查发现两 error 级缺陷——已修闭环（2026-10-02 M2-8-3 验收批；登记正本 = `phases/m2-8-versions/M2-8-3-DECISIONS.md` §3 + 证据 `.work/gui-acceptance/m2-8/` m2-8-09..15 + `M2-8-3-ACCEPTANCE.md` §二..五）**：①**Copy Adjustments 对话框开即崩**（机制落实：app-root `.sheet` 闭包挂链在 `.environment(...)` 写入**之外**——sheet 内容环境快照缺两 Observable；修复 `e9c03af` = `AdjustmentTransferSheetContent` 内容面显式重注入 + `SheetEnvironmentInjectionTests` 真 `.sheet` 挂载回归【负腿实测：掏空注入 = 同 fatal 签名硬失败】；**后续约定：app-root 级 sheet 闭包禁止裸 `@Environment` 跨界，内容面重注入或 init 参数注入二选一**）；②**D-26 toast 通道默认 shell 零渲染点**（`StatusBar` 只挂 `legacyBody`；修复 `4e7fc58` = `ToastBarView` 零 chrome 面挂 `WorkspaceHostView` 底部 safeAreaInset + `ToastFaceTests` 3 法【含 AX 树 wiring 断言】；真机复验哨兵 toast 默认面可见 + 4s auto-clear）。两处屏上面均已复验可达。

### M2-9 架构增量（2026-10-03，M2-9-01..05 执行批——导出 Alcedo 化约定正本）
- **ExportVariant 载体面**：`sizing`（YiyinExportSettings 原地扩四模式：original/longEdge/bounds/physical + `allowUpscale`/`maximumEdgePixels`）× `format`（六格式矩阵零改动红线：ExportFormatSpec/ImageIOEncoders/WebPEncoder 不触）× `metadataPolicy`（ExportMetadataPolicy mode{standard,none}+6 bool；STANDARD 剥离 location/serials/editingHistory）× `embedICC` × `drtOutput`（OQ-7 强制联动：`enqueueExportM2` 恒 `assembled.drtOutput = drtRecord`）× `yiyin`（M2 页恒 false——yiyin 是 legacy 面/sheet 超集能力）。recipe 未持久化 → 字段替换零迁移。
- **`.drt` 导出重放缝**：导出链不走 11 先例「剔 gamma + 覆写 colorout」，改 `.drt` 尾段 sub-run 重放——`Request.drtTail` + **`ExportRenderer.jobDrtTail` @TaskLocal**（Contract 文件级零 diff 红线下的 per-job 递缝形态，02 定式）+ `enqueue(drtTails:)` per-image 索引载体；`tailFormatFloatOverride` 缝 = 导出尾平面恒 float32（quantizer 拥有钳位与位深分档）。同款 TaskLocal 递缝还有 `$jobNamingCarrier`（sequence 入队盖章批内序）与 `$jobExifSoftware`（App→encode 的 Software 载体）——**Contract 零 diff 约束下的递缝三件套范式，后续 App→queue 传值照此**。
- **元数据座位事实（L054 正本）**：EXIF Software 唯一可序列化座位 = `{TIFF}` dict（`kCGImagePropertyTIFFSoftware`；{Exif} 全容器被弃）；JPEG readback 不回显 {TIFF} → 断言走 byte-scan；已知空间（sRGB）零 profile payload → 「未嵌 ICC」断言 = payload 签名缺席非 profileName。`ExportICCStrip` = post-encode 剥离（JPEG APP2/PNG iCCP/TIFF tag 34675 原位压缩 + 孤儿清零；HEIC/AVIF/WebP typed 不可达档，UI 出说明文案）。
- **命名模板引擎边界**：`ExportFileNameTemplate` 11 token parse/render 分离（Alcedo `{token:arg}` 全量移植 + shutter `1-500` 形态 + sanitize 200 帽 + fallback "image"）；冲突三档 `ExportCollisionPolicy`（increment 默认逐字节 = 旧行为，FAIL/REPLACE 显式档；**M2 页未暴露档位选择器——enqueueExportM2 固定 .increment，档位 UI 缺口挂账**）；step 9 逐 job 求值（decoded.capture + 盘上 rating + carrier sequence）；`landingDirectory` 单源 join（子目录 typed 创建）。
- **尺寸解析单源**：`resolveExportResolution`（fit-inside + upscale 钳 + cap 全模式尾段 + **DPI 宽度比修正**——Alcedo cpp:31-80/287-325 同构；llround 取整）；renderStage sizing 腿直切 + `StageOutput.dpi` 修正值达产物元数据。
- **DrtOutputColorSpace（输出 ICC 解析器）**：space×eotf 穷举无 default、accept-set==legalEOTFs==Alcedo cpp 三方镜像；SDR 幂臂**自建 ICC v4 字节**（Bradford D50 + chad + curv-1；L053：macOS 27 CalibratedRGB 坏/para 误解析/嵌入重序列化三坑），HDR 臂系统名 ITUR_2100_PQ/HLG（出片实证实测 CICP 9/16）+ `ExportVariant.validate` peak 闸门（finite 正数，nil 不触发）。
- **M2 检查器 Export 页 + 记忆键族**：`exportPageActive` 会话开关（InspectorState，非持久）挂 Inspector 列顶部分支（inactive 渲染面逐字节冻结）；五节 = 输出位置/文件命名（ExportNamingEditor：3 内置+用户+Custom/11 token 尾追/typed 红错/live 预览）/元数据与色彩（单开关 + ICC EMBED-OMIT + OMIT 不可达说明 + DRT readout）/SDR 导出（六格式四质量+位深+四模式+高级折叠区）/导出队列（四态+36 帽+进度+retry）；`ExportState` 注入式 defaults 面（KD-4：body 零 UserDefaults 直读）；`enqueueExportM2` per-image `instancesOverrides`（open 图=活投影，其余 nil 盘真相）+ count 失配 typed 拒绝先行；`rebuildQueueForProject` 挂项目打开事件。六键见「UserDefaults 键登记」。**M2 页无 yiyin 节/冲突档选择器（挂账）**。
- **走查批（M2-9-05）补录**：真机十项证据 = `.work/gui-acceptance/m2-9/`（MANIFEST 逐项）；新发现 Import 面板取消即崩（F-1，M2-3 时代面，另案）+ 格式 Picker 裸键（F-2，LocalizationValue 插值字面量查表键陷阱——**新代码禁 `String.LocalizationValue("prefix_\(x)")` 形态**，动态查表键 scanner 不可见且运行时回退裸键观感）。

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
