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
- **Darktable**（`/Volumes/UNITEK/Documents/Development/darktable`）：iop 算法、OpenCL kernel（`data/kernels/*.cl` → Metal 移植）、pixelpipe 架构、色彩管理的源码参考。**GPL-3.0——只读参考算法思路，代码不复制入库（本项目 MIT）。**（**2026-10-13 登记**：上游 master `18cf557fbd..37d514c78c` 共 118 commit 中 **spektrafilm iop 族 16 commit**（CPU/GPU divergence 闭合〔grain 采样器 `3b1a26a7c7` + 乘加定序 `1ce6ad6a93`〕/ 宽递归模糊级联化 `9ef307dad8` / print diffusion 跑 linear exposure `6d92ef5814` / highlight boost 封顶 `8b5b4321bc` / GUI 默认=渲染真相 `1be930d162` 等）= **M3 FSIM 族后续质量参考**——M3 已收官不重开，未来 FSIM 质量轮（grain/diffusion/divergence 门）取用；本地仓 master 未 ff，commit 已 fetch 到 `github/master` 可查；FSIM research 正本 = `.work/gsd/phases/m3-2-fsim-research/RESEARCH-NOTES.md`）
- **yiyin / 壹印**（`/Volumes/UNITEK/Documents/Development/yiyin`）：边框/水印面板的功能对齐参考（重写为 Swift，yiyin 项目独立维护）。本地仓 = **自维护分叉** `kamasylvia/yiyin`（Electron+Svelte，v1.7.x 起，较上游更优——**参考以此为准**）；上游原仓 = `ggchivalrous/yiyin`（仅追溯用）。
- **Alcedo Studio**（`/Volumes/UNITEK/Documents/Development/AlcedoStudio`，2026-09-27 引入）：开源（GPL-3.0）C++20 RAW 编辑器 + 图库，Windows（CUDA/OpenCL）+ macOS（Metal）双平台，150MP 流畅编辑。（**本地仓 2026-10-16 已更新至 v0.3.3+主干 6024386**——上游新增 CLI/MCP/共享会话自动化面〔`alcedo-cli` 随包、named-command JSON-RPC、headless 宿主、agent GUI turn-taking、editor.catalog 参数目录、versions/export/search 命令族；整体 = 我方 Phase 14 MCP + M6-1 单写者的同构追认，唯一新立项候选 EXPORT-PRESET-01 导出命名预设，逐项判定正本 `.work/gsd/research/ALCEDO-PARITY-2026-10.md`〕，见特性图增量节与 parity 评估正本；2026-10-16 增量批入队 2 小件〔预览层挂导出同款 ICC profile、FAIL 档原子不覆盖〕到 `research/UPSTREAM-QUEUE.md`）参考点：GPU demosaic 算子（`alcedo_studio/src/decoders/processor/operators/gpu/metal_shader/` 下 `debayer_rcd.metal` / `xtrans_interpolate.metal` / `demosaicnet_io.metal`——DemosaicNet 蒸馏神经去马赛克，X-Trans 默认走它）、inpaint-opposed 高光重建、ACES 2.0 / OpenDRT 显示渲染变换（目标色彩空间/传递函数/峰值亮度可选，HDR 直出）、节点式调色图（Develop → 多个 Color Grade 节点 → Display Transform，每节点独立调整+蒙版，与本项目 adjustment layers 模型同构）、大图瓦片式按需渲染 + 多级缓存设计。同 GPL-3.0——只读参考，代码不复制入库。**功能对标正本：Lightamer 的 UI 与功能面完全模仿 Alcedo（2026-09-27 项目重定义）——相关功能规划/实现时去本地源码参考对应实现**（UI/QML 面 `alcedo_studio/src/ui/`、解码算子 `alcedo_studio/src/decoders/`、节点图与渲染 `alcedo_studio/src/`，实机对照 `/Applications/AlcedoStudio.app`）。
- **Lumen RAW**（`/Volumes/UNITEK/Documents/Development/lumen-raw`，2026-10-01 引入）：开源（**MIT**）Windows RAW 编辑器（Python 3.12 + PySide6 + LibRaw + ONNX Runtime）。**借鉴裁决（2026-10-01 用户：5 采纳 / DNG 导出不采纳）**：①MiDaS 单目深度 → IOP-MASK-07 Depth 蒙版数据面 ②Mertens 曝光融合 → IOP-HDR-06 ③全景合成（SIFT/球面投影/分块羽化）→ IOP-PANO-01 ④AI 超分/降噪「可编辑副本」UX → M2AI-09 ⑤AI 推理 worker 进程隔离 crash-safe → M2AI-10。相关功能规划/实现时**去本地源码参考对应实现**（单目深度/自动蒙版 `lumen/auto_masks.py`、AI 增强对话框 `lumen/enhance_dialog.py`、推理 worker 隔离 `lumen/ai_worker.py` + `lumen/host.py`、HDR/全景合并 `lumen/merge.py`、任务调度 `lumen/scheduler.py`）。MIT 许可——可参考算法与模式；如成段移植代码须保留 MIT 归属注记。调研正本 = `.work/gsd/research/LUMEN-RAW-NOTES.md`。
- **SpektraLab**（`/Volumes/UNITEK/Documents/Development/SpektraLab`，2026-10-02 引入）：开源（GPL-3.0 代码；胶片/相纸配置与放大 LUT = CC BY-SA 4.0）macOS 胶片+放大相纸模拟器（81 波长光谱物理建模、28 款实测配置、45MP <1s）。参考点：模拟链阶段分离语义（场景置位→胶片→配光→印相）、宽容度面板+场景置位 UX、CLI+MCP 同会话三前门（与我方 Phase 14 同构）、导出软打样纪律、性能标杆。相关功能（胶片模拟升维/宽容度 UX/MCP 契约）去本地源码与 `rfc/` 参考对应实现；调研正本 = `.work/gsd/research/SPEKTRALAB-NOTES.md`。GPL 代码零复制；CC BY-SA 资产如引入须独立归属。
- **LightCraft**（`/Volumes/UNITEK/Documents/Development/lightcraft`，2026-10-13 引入；本地仓 2026-10-16 同步至主干 `0da998f2`——batch 39/40 整合，滑杆双击重置/横扫 scrub + 软打样 1:1 zoom window 候选入 `research/UPSTREAM-QUEUE.md`，增量登记 = LIGHTCRAFT-NOTES §七）：开源（MIT OR Apache-2.0，代码级移植合法须 NOTICE 归属）**Adobe Lightroom 的 clean-room 纯 Rust 复刻**（10.7k 星，照片图库 + RAW 显影 + 非破坏性编辑 + MCP server 内置，macOS/Win/Linux/WASM 四端）。参考点：**MCP 单写者锁 + `--connect` 转发**（M2-9-A 并发双写现成答案）、**ISO 21496-1 gain map（UltraHDR）JPEG 导出纯 Rust 实现**（ALCE-03 挂账正主）、**per-photo process version**（改观感=新 process 号 + 旧号冻结，根治 iop 调参老 `.lra` 渲染漂移）、**量化对标方法论**（gaps.md 排名 + parity-checklist 逐条 ID + CI 门）、**AI 模型可选安装器纪律**（SHA256 + 合成自检 + 断点续传）、SAM 3 语义分割蒙版、work_gate 分类内存闸、stacks/auto-stack/smart albums/挑片视图/watched folders 图库包、gamut mapping/单调样条/OkLCh 三小件、never-crash lint。调研正本 = `.work/gsd/research/LIGHTCRAFT-NOTES.md`（九面对照 + 借鉴候选 + 裁决点 OQ-LC-1..6）。

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
- **UserDefaults 键登记**：`library.import.mode` / `library.import.rememberMode` / `library.import.rawExtensions`（ImportDefaults，全量替换语义 + reset）+ `library.recentProjects`（LibraryProjectController，dedupe-move-front 上限 10 + 死路径清扫）+ `lut.library.root`（M2-5-3，LutLibraryStore.libraryRootKey 单源拼写；IOP init 直读 `.standard`，AppPreferences 只承载登记/reset 面——空/缺 = 默认根 `~/Library/Application Support/Lightamer/LUTs/`）+ **导出记忆键族六键（M2-9-04/05）**：`export.lastDirectory`（OQ-3 落点跨会话记忆；picker 即时写回 + run 写回 + 首用回落首图目录）+ `export.jpegQuality` / `export.heicQuality` / `export.avifQuality` / `export.webpQuality`（OQ-10 四格式各一键，Double 0...1，typed 读 + isFinite + qualityRange 域校验，0.0 = 真记忆非未存）+ `export.namingTemplates`（OQ-9 命名模板预设 JSON 数组，NamingTemplateStore 注入式 defaults，三内置不入库）+ **yiyin sheet 比例两键（M3-1-02）**：`yiyin.sheet.widthRatio` / `yiyin.sheet.heightRatio`（Double 0...1，YiyinSheetMetrics 注入式 defaults——body 零直读；typed 容错域外/异型 = 键视为缺席回落现状 420×560；仅拖拽松手写入，quantize3 三位小数）。

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
- **Follow Edges V2 已换锚（M4-2-01 批，2026-10-10；T5 真图门 FAIL → 缺省维持 `.snap`）**：`.streamline` 臂实现已换锚为 RidgeGraph 消费者（`RidgeExtract.graph(from:high:)` 六段流水线：轻高斯 σ0.9 → 中心差分 → **结构张量取向**〔幅值脊自身梯度脊顶恒零，逐像素梯度读法退化——NMS/质心方向 = ±2 窗外积平滑主取向〕→ NMS 非对称 tie〔严格侧 = 沿取向 +e〕→ 滞回 r0.4〔**门读 raw 场值**——平滑在细脊损失 ~33% 幅值〕→ 行主序链接 + B3 桥接〔pairBridges 纯函数，桥接对齐门 0.5 = 提取期内部常量〕→ ±2 质心 clamp1.5〔**junction 像素免细化**〕）；V1 walker（lookahead/动量/环梯度回退）已删除，`stepPixels`/`maxPoints` params 字段双撤出（fuse 256 = walker 内部常量）。内部常量登记（单一源）：σ0.9/r0.4/B3/桥接门 0.5〔E1 处方甲〕/取向窗 ±2/s0.75-4.0/θ45°/附着 8px/再附图 8px〔M2〕/fuse 256〔M1〕/质心 ±2/clamp1.5/ε1e-6。`EdgeMapField.ridges: RidgeGraph?` additive（注入 carrier = `PipeCoordinator.FollowEdgesRidgeCache`，折键 prefixHash⊕thresholdBits LRU 8；surface 缺省阈值 0.25——非缺省阈值走 lazy 路径，`RidgeGraph.high` 戳拒绝旧 carrier）。合成 golden 九景全绿（真值 ≤0.75px/覆盖 ≥80%/双跑逐字节）；**真图门 FAIL 0/8**（`m4-2-01/probe/`：碎片网 junction 汤，V2 优于 V1〔22px vs ≤4px〕但未过 ≥6/8；mle=1024 诊断 24 点/81px 达功能级）→ **M4-2-02（P2 512→1024）armed**；正本 = `phases/m4-2-follow-edges/M4-2-01-{SUMMARY,DECISIONS}.md`。
- **Follow Edges 升级口 1024 实测裁决（M4-2-02 批，2026-10-10；门 FAIL 2/8 → 停止上报，缺省维持 `.snap`）**：产线唯一改动 = `PipeCoordinator.edgeMapField` 调用点 `readEdgeMap(plane, maxLongEdge: 1024, metal: metal)`（`633378b`；`readEdgeMap` 签名/缺省 512/函数体零改——红线机检 md5 同值在案；同缝邻注诚实化 4 行）。预算阶梯落位第一档（门不变）：预提取 @1024 = 39.3ms x10 median / 40.8 first-shot（≤50ms 门内、81% 贴线——再升 2048 必越门，GPU NMS OQ-2-B 论据加强）；COLD GPU+读回 8.3ms（512: 6.3）；行走 0.007ms。**真图门 FAIL 2/8**（`m4-2-02/probe/` 双跑逐行一致：t0.25 B3 12pts/34px = 首功能景；t0.15 A3 13/39 + B3 34/83；0/8→2/8 真实改善远未过 ≥6/8；骑行分数 0.38→0.62 = junction 门掉链仍是主导瓶颈，分辨率杠杆已尽）→ **按 plan「1024 仍 <6/8：停」**：T3 默认回翻不执行、不三改（无 2048/无 GPU NMS kernel 化），**三选一上报 orchestrator**（research 复审 / 接受降级 / GPU NMS 立项）；1024 改动保留在位（全指标严格优于 512 + 默认 `.snap` 无用户可见面；回退属「接受降级」子选项）。注记：`edgeMapField` 为 follow-edges 两臂共同入口——1024 域同时改变 **snap 臂真图搜索密度**（合成 snap 门不受扰已绿；真图无门无走查，保留 1024 则入 GUI 走查清单）。回归 +2（1024 路径维度/最近邻 box 序 + 缺省 512 不变断言；纯函数域冻结 M4-2-01 值负测——`maxLongEdge` 不可达纯函数域），Layers **422/3/0** / App **708/0/0**；全套预期 3367/16/1（--all 未跑，orchestrator 批准制）。正本 = `phases/m4-2-follow-edges/M4-2-02-{SUMMARY,DECISIONS}.md`。
- **Follow Edges V2 删除挂待定（2026-10-10 用户终裁，覆盖上两条 V2 注记——彼两条保留为历史记录）**：V2 代码面全撤 = 逆 M4-2-01/02 代码提交（删 `RidgeExtract.swift` + `RidgeExtractTests.swift` 21 法 + `FollowEdgesRidgeCacheTests.swift` 4 法；`FollowEdges.swift`/`FollowEdgesTests.swift`/`PipeCoordinator.swift` 逐字节回落 M4-2 前内容——`EdgeMapField.ridges` 缝/carrier/计数器/surface.edgeThreshold/1024 升域全撤，`readEdgeMap` 回缺省 512；`Project.swift` 两登记行 + BUNDLE-MAP 两行退役；V1 walker/`stepPixels`/`maxPoints` params 面随恢复回归在位，上文 M2-7 熔断注记重新生效）。代码回落 M2-7 熔断基线（`.snap` 默认，`.streamline` 分支与模式选择器保留）；验证 = Layers **394/3/0** + App **704/0/0** 逐位 = M4-1 基线；grep 机检 RidgeExtract/RidgeGraph/withRidges/followEdgesRidge/maxLongEdge:1024 全仓零命中。IOP-MASK-06 **parked**（重启条件 = 可靠开源参考实现〔边缘跟随笔刷类〕；正本 = REQUIREMENTS parked 行 + `phases/m4-2-follow-edges/M4-2-03-CONTEXT.md` 终裁注记）。
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

### M3-1 架构增量（2026-10-08，M3-1-01..03 执行批——W1 前置批约定正本）
- **LUT 编码维（M3-1-01）**：`LutEncodingCatalog`（17 条 scene log + display 行表驱动，传递曲线 Float64 正逆族双落笔——公式自公开标准/厂白皮书，Alcedo 只对表行集与字段形）+ `Params` additive 编码对（input/outputEncoding optional；**hash 零漂移专测钉死**：默认 params 编码逐字节 == 旧两键 JSON）+ 宿主复合表重烘焙（`Lut3dModule.Compose`：Float64 + LRU 16 + bakeCount + stateLock；快路径 = 默认对恒 verbatim 直通——**偏离 Alcedo HasUnitDomain**，逐字节保持裁定）；**三层读取序** = 文档 params 显式 > 库记忆对（`InstalledLut.rememberedEncodings` 原子对）> 默认对；内置 40 张 seeder 补标 `{arri_logc4_awg4, rec709_bt1886}`（adoption 路径盖章；观感变化 = 修偏差交付注记）；`Lut3dKernels.metal` 零 diff（零新 kernel 红线传承）。
- **yiyin sheet 拖拽（M3-1-02）**：`YiyinSheetSizing` 纯数学（px 界 ∩ 比例域双钳 + quantize3 + 首用 420×560 锚）+ `YiyinSheetDragSession` 拖拽窗口值类型（live tick 纯态/end() 产量化 ratio——**AC 可机检缝范式：交互纪律断言不靠 UI 驱动**）+ `YiyinSheetMetrics` 注入式 defaults 两键（`yiyin.sheet.widthRatio/heightRatio`）；sheet 右/下缘 8pt invisible handle + `.global` 锚定（sheet 自运动耦合残余 = D6 挂账）。
- **denoise 拖动降档旁路（M3-1-03 KD-3 正本）**：`EditorState.previewDenoiseBypass: [UUID: Bool]`（实例身份键控非 opName；值 = arm 时先验 enabled，disarm verbatim 复原）三道防线 = ①upsert 投影强制（tick 快照 enabled 压回 false，面板 tick 不复活旁路）②commit 自愈（`recordChange` 对被提交实例强制 disarm——commit 即真相）③重建清扫（`resetHistoryForNewImage` + `rebuildInstances` 清表）。**旁路永不进 liveEdited/params/history**——拖动窗外 FULL 判定面逐字节不变；窗内并发 FULL 缺 denoise = 已登记风险（M4 coordinator 串行化余量）。面板 disarm 先于 endEditing（D9 顺序裁定）。nlmeans 默认 Alcedo IA 不可达（M2-1 禁用集 + tab shell 无席位）——实机走查归 legacy 修复批顺路（配方 = `.work/gui-acceptance/m3-1/MANIFEST.md` 附录）。
- **冲突档选择器（M3-1-03，M2-9 挂账#4 关闭）**：`ExportM2PanelModel.collisionPolicy` 会话态（**作用域 = Export 页视图寿命**，与 pattern/metadataOn 同层——页关即复位 Increment；非持久 = KD-1 裁定，跨会话记忆属新挂账）；run face 装配 = `makeRunAssembly` 纯缝（`RunAssembly` 值类型——**「装配参数束提模型纯函数」范式：picker→queue 路径状态层可机检**，视图只留 I/O）；引擎/`ExportState` 形参零 diff。
- **peak-ICC 说明面**：`drtReadout` HDR 档（`isHdrEncoding` Core 单源）追加 `export_drt_peak_note` caption——ICC 只承 space+TRC、peak 在 EotfBox record/`ExportVariant.validate` 闸门、真容器 UltraHDR = ALCE-02 M4（`M2-9-02-DECISIONS` 边界正本不动）；SDR 档渲染零变化。
- **zh 提取器硬化（V15 正本）**：`zh-audit.py` form 1c = `localized:` 行尾 + 键字面量次行开头（`PENDING_LOCALIZED_RE` + `LEAD_LITERAL_RE` 行对状态机；注释行保持 pending）；self-test golden 负测两样例（静态键/插值前缀 continuation）。**硬化首轮即抓 search_{exif,clip}_placeholder 真缺口**（catalog 从未在册 = 运行时 zh 缺失）——提取器硬化后必须实跑 `--check` 对账一轮再收工。V14 形态：动态键位一律显式 switch 返回静态键（11 键在册非补键）；`String.LocalizationValue("prefix_\(x)")` 禁令维持。
- **M3-1 键族登记**：`export_collision_label/increment/fail/replace` + `export_drt_peak_note` + `panel_nlmeans_preview_downgrade` + `project_face_import_folder/no_project/no_project_hint/open_hint` + `search_exif_placeholder/search_clip_placeholder`（xcstrings 尾块纯插入；UserDefaults 零新增——冲突档会话态裁定）。

### M3-3 架构增量（2026-10-09，M3-3-01..03 执行批——FSIM 阶段模型约定正本）

- **FilmRecord/持久化面（01）**：document 级 `FilmRecord` 七字段（film_stock/paper_stock 开放 id + y/m_filter_shift CC 0-100 + content_adaptive_shift + strength + exposure_ev；DrtRecord 同构 tolerant decode + stableHash + pristine 门）+ sidecar v9（`filmRecord` 字段 + HistoryItem.filmRecord 镜像；默认 record 不入 map 不写 sidecar）+ `commitFilm`/`effectiveFilmRecord`/HistoryHash 尾位折叠（film 排 drt 后；`driftDetected` 双投影喂入、正反 tamper 钉死）。**成对写入义务**：makeSidecarDocument 的 film item + 文档字段同批写（锚一致性）。FilmRecord.PresetNames = 空命名空间（预设面悬置——无注册即无拼写）。
- **光谱不可达架构注记（FSIM-01c 收口，用户可见措辞 =「物理流程建模，非光谱重放」）**：CIRAW 解码后 RGB 起步，81 波长光谱重放架构性不可达（光谱信息解码即折叠，同 demosaic 菜单不可达之理）；可行核 = RGB 密度域染料近似（密度曲线 + 三点投影底色 + 恒等串扰起步 + 滤色通道增益 s_m=0.0085/s_y=0.017（2:1 dichroic 标定）+ 相纸曲线 + session 系统反演）。资产 = spektrafilm CC BY-SA 28 profile 原样五件套（`Resources/FilmProfiles/`，与 MIT LUTs 物理隔离；densitometer 域矩阵：负片 status_M、相纸/反转 status_A、kodak_2383/2393 例外 = status_A print 路）。
- **film sub-run 缝（02）**：`runTerminalTails` 共享序（film → DRT tail → display replay）；3×2 交互矩阵（.sdrGamma 全驻留集降出 v50 序重放 / .edrLinear 仅 colorout、gamma 恒不重放 / .drt 零改；DRT 交接 = 数源替换，`DrtTailAssembly.seed` 签名零改）；seed = `fnv(recordHash ⊕ "lightamer.film.subrun.v1" ⊕ solvedPackHash ⊕ upstream)`；fused kernel `film_subrun` 单 pass（查表→base→滤色→65³ 四面体→log 域强度混，零中间平面）；GPU 载体 run-scoped（`FilmMethodBox.runContext` set/clear 单写者窗）。印相段 bake = per-pair 65³ Float64 + LRU 16 + **K 标定（session 操作点）** + session 系统反演（中灰灰阶误差恰 0——RFC-028 我方域验收形态）。
- **FilmSolveCache 键控（02/03 钉死）**：AUTO core 缓存键 = `fnv(materialPairHash ⊕ statsHash ⊕ modeTag)`（小端字节序 FNV-1a、折叠序 FilmDeterminismTests 精确值钉死）；record 层手动 Y/M + exposureEv 走 recordHash 消费叠加**不入缓存键**；统计 = 256-bin 整数秩（禁浮点插值）；**stats 项 = 原始计数直方图（非比例不变——窗口渲染各自成键）而解值按比例不变**；mode tag 无 ROI 项 + film box 恒不入 tile 驱动 = per-ROI 红线结构面。`invalidateAll()` = 面板 Solve 按钮的失效缝。
- **置位 op（02）**：`filmPlacement` V50 20.8 add-only（19 行 grade 目录 + E7 闭合 + add-face 枚举 13）；RFC-023 delta 形 bit-exact + 简化臂膝点（拨入深度 t=C∓N；m=1 闭式 **两侧异号 K=t±√((t−a)(t−c))**——阴影侧符号为 M3-3-03 golden 批修正 + 回归钉死；m≥2 守护牛顿+二分）。**已登记缺陷分析（M3-3-03 DECISIONS）**：m≥2 落地方程根深远离 t（K_h 可低于 K_s，违反核内「至多一支活跃」构造注释）——零用户可见面（面板恒等占位 + 默认 0/0/2），M3-4 descriptor 臂换锚时消解。golden 面 = 单侧臂渐近线 + 单调 + 落地精确。
- **golden 门（03，E5 两级分解）**：fused kernel 逐像素两级（1a kernel vs 同表 CPU 四面体采样双写——平滑域筛选后实测 8.7e-5、钉 1e-4：**dt-verbatim rtne 晶格映射外推 ±0.5 格放大 f32 坐标噪声**，真实 kernel 缺陷 ≥1e-2；1b 烘焙表 vs 理想连续模型——凸性门（插值不越单元值域 1.5×）+ 平面元线性带实测 **6.2e-3**（先例带 1e-3..1e-2 中值））；bake 体素级 ≤1e-5（LCG 常量种子）；中性闭合 = 中灰面过全链通道散 ≤2e-3（实测 1.4e-3 = 插值色度地板）。**平滑域筛选结构**：反演轴端 clamp 平台面（黑场 10^axisLo/ Clear 10^axisHi）切片式穿过 cell，邻域 LUT + 内带着陆 + |d|≤0.25 三重筛（DECISIONS 登记）。**比较空间纪律（L048）**：一律 decode 回 linear + f32 产线常数 `Double(Float(x))` 升维。
- **Film 面板最小面（03）**：FilmPanelModel = DrtPanelModel 孪生（live → history → carrier 三级读；单 discrete commit；D-H1 三件套走 coordinator begin/setFilmLive/commitFilmEdit）；启用 = 一次 commit 默认材料对（无 stock 默认 record 在 filmTailPolicy 门 off——默认对才是诚实启用）；readout = 产线 solve 直读（手动叠加可见）+ Solve 按钮；**无宽容度面板/直方图/descriptor（FSIM-02 = M3-4）**；filmPlacement = 可加不可编恒等占位。挂载 = InspectorView 整列分支（exportPageActive 孪生；inactive 面逐字节现状）。
- **节点图只读 Film 卡（03）**：App 侧投影物（`NodeCanvasGeometry.filmCardID` 编译期常量；layout `includesFilmCard` additive 默认参 = 既有调用零改；卡位 = grades 与 DRT 之间 = sub-run 物理座位）；**NodeKind 零新增、命令面零触**（M2-4 语义零改动红线，FilmCardTests 钉死）；卡点击 = 导航（openFilmPage）非编辑；inspectorState 注入式 optional（裸宿主测试面不 crash——@Environment 缺对象即 fatal 的教训）。
- **键族登记**：`history_film_enable/material/param/shift` + `film_*` 面板族 15 键 + `editor_node_film/_hint/_inactive` 卡族 3 键（共 22 静态键；xcstrings 尾块纯插入；UserDefaults 零新增）；FilmRecord.PresetNames 悬置。
- **封存面清单（03 收口登记）**：`DrtPanelModel/DrtPanelView/DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels.metal/DrtEotf/ExportQueueContract/六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）/NodeGraphCommand/sidecar schema（LightamerSidecar）/HistoryStack/HistoryHash/PipelineDocument（Core）/V50Order/GradeCatalog（NodeOwnershipCatalog）/Registry/ModuleInstance`——`2fee806..c5f5dce` 全批零 diff（03 验收真路径亲证）。film 面两个恒态：**thumbnail 恒 legacy**（`filmTailPolicy(for:)` 对 thumbnail 恒 nil，同 DRT 先例）；**导出恒装配** = `ExportQueue.filmTail` per-job 载体 + `$jobFilmTail` TaskLocal（02 E1 三编辑点，drd 外 film 内嵌套序；M2 页未暴露 film 开关 = 跟随文档 record）。

### L057 面板呈现约定（2026-10-08，fix(l057) 批——面板/文件对话框呈现约定正本）
- **`runModal` 族禁入产线**：一切 `NSOpenPanel/NSSavePanel` 呈现走唯一缝 `PanelPresentation.present(_:) async -> URL?`（`begin(withCompletionHandler:)` 非阻塞形态，AppKit 在安全点自行调度面板 modal loop，**从不嵌套进 SwiftUI 动作 callout 栈**）；机检 gate = `grep -rn "\.runModal(" App/Sources` 零命中。调用点纪律 = 菜单命令/按钮/contextMenu 项一律 `Task { await … }` hop。
- **判别式（Task hop 何时不够）**：main queue drain 挂 CFRunLoop common modes（含 event-tracking mode）——`Task {}`/`DispatchQueue.main.async` 只拆动作帧、不保证脱离菜单追踪/AX simulated-open 态，modal 嵌套可幸存（.ips 085205 = Task 包裹菜单路实证）。充分模式 = begin 缝（结构性消除嵌套）。正本 = `.work/gsd/phases/l057-panel-family/L057-DECISIONS.md` D1R/D2。
- **机制现状（L057 二分）**：在案三份 .ips 全为主线程栈边界故障（stack guard），且 140155 实例零面板仍崩——面板取消非全部实例必要条件，AX 自动化压力（AXManualAccessibility + 深度 AX 遍历）为共同因子 = **L057-B 专项（queue 行在案）**；LUT 检查器页 HEAD 空白（D8-2）疑同根。嵌套 modal 假说降级为未证实假说之一，begin 缝作为文档禁忌形态卫生修复保留。
- **账面勘误（对 M3-1-02-ACCEPTANCE §三）**：`FileOpenHelper.swift` 的类型名是 **FileOpener**（非死代码——File→Open ⌘O 无条件可见，5 调用点）；`PresetFilePanels.importPanel` = 真死代码已删（导入面早已换 `.fileImporter`）。排查面板族时**按类型名 grep，勿按文件名**。

<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

### M7-3 架构增量（2026-10-17，M7-3-01 执行批——MCP O2 反馈回路 + O3 项目与版本约定正本）

- **MCP 工具面 23→27（第四域 ProjectToolset + list_luts 入 editing 6→7）**：`project_open`/`project_create`（requiresWriter:true；先检后开 Alcedo 同构；create 拒已存在 + 包名最小黑名单 sanitize）/`list_versions`（writer 缺省 + readOnlyHint；**sidecar `readDocument` 单源——version-reference 投影零消费**〔token 在 ProjectToolset 零命中〕；includeItems 复用 historyKind/historyItemCap 500 保新端逐版本 truncated 旗标；pristine = 诚实空面非错误臂）。`ProjectOpenOutcome` = `{url, name, readOnly, heldByOther}` 四键无 photo_count（D-M7-3-6）；name = `url.deletingPathExtension().lastPathComponent` stem 单源（L3）。错误码零新增（McpToolRegistry.swift 零 diff；McpTimeouts 零新档——project 族 apply/list 既有档，compare 双臂 renderAndCrop 30s 单窗）。
- **current-project 盒（`McpServerController.HeadlessProjectBox`）**：锁保护 `{store, url, readOnly}` 三元替换 M6-1 启动捕获静态载体——**一切无头 search/state seam（library/semanticStore/fulltext/liveState）per-call 盒读**；盒空 = bare-context null 面逐字节；**library projectDirectory 锚随盒（H2——运行时 A→B 切换后 PathKind 0 解析锚同指 B，fix `20997721` 同族第二实例关闭）**。`makeHeadlessSearchState` 签名 = `(mode:projectWriteProbe:)`（projectURL/isWriter 参数退役）；盒与 `eofArmDone` 旗标 internal 化（进程全局态的测试序前复位纪律——box 敏感测试以 `headlessProjectBox.set(.init())` 复位）。
- **运行时开项目缝（无头臂）**：`makeHeadlessProjectContext(mode:)` Core 直开/直建 provider——**先关后开**（close checkpoint 内置；失败中间态 = 盒清空诚实态禁半开）；heldByOther → typed `projectReadOnly(holderSummary)`；migrate 照常（OQ-10，失败 = internalError 携 detail）。**EOF watcher 抽取 `armStdioEOFReleaseOnce(mode:)`**：once guard + `mode == .stdio` 内部自守卫（M1 双保险——http daemon 不自噬）；恰两调用点（启动路径行为逐字节不变 + `parkRuntimeStore` open/create 共享尾）；watcher 体 HUP 时点读盒 close+exit(0)。**http 运行时开项目 = 进程退出 kernel 地板（checkpoint 优雅面仅 stdio——D-M7-3-7 偏离面钉全）**。
- **GUI 内嵌臂 provider（LightamerApp 装配段）**：library/sessionPair 闭包变量提共享同形赋两 context（OQ-8 零复制）；openProject provider = **held 目标 `probeLockAvailable` 预检（openProject 之前——held 不触 openProject 一次 agent 调用不掀用户正开项目）+ before/after `pendingConflict` 差分**（before==nil ∧ after!=nil ∧ store 未变化 → typed projectReadOnly；stale conflict 反向误报由 before==null clause 消）。**controller 文件零 diff**（FIX2③ 维持 M7-4）；promoteRecent 随 controller 既有语义 = GUI 臂入 recent / 无头天然不入（D-M7-3-9 不对称申报）。生产调用点五处（runHeadless :254/:263 + runHeadlessArbitrated :378/:390/:410 段）全传 provider——裸 `McpSearchStateContext()` controller 内零命中（H3 tools never disappear）。
- **render_preview 扩展（MCP2-04）**：`region` = 归一化 0..1 {x,y,w,h} 相对**渲染输出画面**（orientation 已归一），渲染后 `CGImage.cropping`，rect × 平面尺寸 **round+clamp**；w≤0∨h≤0 → invalidParams、越界 → roiOutOfBounds 既有码、交后零面积 → invalidParams 携归一化值（合法入参禁落 cropping-nil renderFailed 静默面）。`compare` = enum none|root **默认 root**（D-M7-3-3）：同一 boundedWait 窗两遍 renderedPlane（pristine 臂 `pristineOnly: true` 各自 decode——零共享零新 render 代码，OQ-5）；内容序 [current, root, text] + summary JSON；载荷预算句入 description（双臂 ≈3MB@1024/q85，无自动降档）。**Core 唯一新触点 = `renderedPlane` 签名尾部 `pristineOnly: Bool = false` + :236 条件化**（true 跳 readDocument = 同一无 sidecar 空链分支；全消费方 9 调用点/5 文件零 diff，两 byte-equal 恒等负测在 QuickLookRendererTests）。两工具分界句（get_detail_crop=源细节原生分辨率 / render_preview region=渲染观感 ROI）入 description。
- **list_luts（MCP2-05）**：editing 域注册（readOnlyHint + McpTimeouts.list 包裹 + LutLibraryStore.shared 直读）；出参 {libraryRoot, total, luts[]}（key = resolvedRelativePath 根相对 POSIX = **lut3d params lutName 新写入寻址键**——KD-1 句入 description；libraryGroups 不入 v1）；golden = seeded 内容正断言 + installedNames/entry 恒等式双腿（L4 防同义反复）。
- **M3 寻址单源**：`SearchStateToolset.resolveImageURL` 抽 internal 共享 helper（`(image, libraryProvider, sessionPairProvider)` 签名）——SearchState 传 context 两 seam、ProjectToolset 传自携同形两 seam；**match_color provider 禁顺手动**（锚病在案 M7-4 路由）。
- **M7-2 挂账六项收口**：F-AC-1（FilterSQLTests `testLibraryDomainSnapshots` 六断言 + keywords eq 第二法——`+i.` 前缀 + `(1=1)` baseline 钉现字节）/ F-AC-2（probe 透传 + get_state.control.lock 双臂真值断言）/ N2-1（pristine payload 12→13 键 truncated:false + golden 同 commit）/ N2-3（fulltext 闭包 typed `notSessionMember` 抛 + nil 载体负测）/ N2-4（requestFailed 臂 F-3 四案闭合）/ ⑥ cursor 边界承接句 + F-AC-4 注释非易碎形。FIX2③ 维持 M7-4。
- **MCP 测试面纪律**：union `McpFinalSnapshotTests` 27 全点位显式改（改动权本波行使完毕，**移交下一波 M7-5**——串行禁并行编排注记延续）；两层 consciously change together（editing 层 McpRegistrySnapshotTests 同批）；union 外五计数钉（:194/:270/:243/:696/:200）显式改 20→21；残漏 grep（`count, 20`/`count == 20`/`all23` MCP 测试面零命中）。McpProjectToolsetTests = suite 级 @MainActor + 进程全局盒前置复位 + **STDIN_FILENO dup2 /dev/null 安全化**（stdio 运行时 open 腿在测试进程 arm 真 EOF watcher——dup2 使 poll 永不 HUP 套件不自噬；真实 HUP e2e 由 McpProjectArbitrationTests 跨进程承载）。键族：`mcp_tool_desc_list_luts/_project_open/_project_create/_list_versions` 尾块纯插入 + `mcp_tool_desc_render_preview` 原位值改；UserDefaults 零新键。
- **全套终值**：`TOTAL|3905/35/0|` exit 0 零 MEMFAIL（3877+ΔN 28 对账精确：App +24 / Library +2 / Export +2；skip 35 零漂移；七 bundle 峰 IOPParity 7786MB 门内）。正本 = `phases/m7-3-mcp-o2o3/M7-3-01-{SUMMARY,DECISIONS}.md`；执行链 `c6019122..7694e7b1`（6 commits 含 T6 docs）。**验收正本 = `M7-3-01-ACCEPTANCE{,-2ND}.md`（双路 PASS / 0E 零实质分歧）；签核正本 = `M7-3-VALIDATION.md`。**

- **M7-3 closed（双路验收 VALIDATION signed 2026-10-17）**：签核正本 = `phases/m7-3-mcp-o2o3/M7-3-VALIDATION.md`（`status: validated` + `nyquist_compliant: true`；夜间授权先例晨审可推翻）；执行链 `c6019122..7694e7b1`（6 commits）。**双路独立验收 PASS / 0 error 零实质分歧**（omp 制度路由双 zcode 独立眼替代——第一路 `M7-3-01-ACCEPTANCE.md` pristineOnly 深审 + 仲裁 fixture 对账 + 真 stdio 端到端；第二路 `M7-3-01-ACCEPTANCE-2ND.md` 五面审计 + 真产线二进制 E2E 三轮 + S1 三层独立复现 + S2 冷延迟量化；S1 = **M6-1 `1f981f9b` 潜伏缺陷**〔stdio EOF watcher `poll(events:0)` macOS 管道永不因写端关闭醒——先前性双路 `git log -S` 同指钉死，M7-3 红线忠实兑现非本波违例〕+ S2 = `list_luts` 冷首调 50.2s plan 盲区〔`LutLibraryStore.shared` dispatch_once 全库解析超 10s 声明窗〕+ S3 = GUI 差分谓词正臂零覆盖 minor——全数非阻断移交 M7-4）；**三路全套同值 `TOTAL|3905/35/0|`**（exit 0 零 MEMFAIL 七 bundle 8G 门内；3877 + ΔN 28 精确，超带 +8 如实申报正当）；端到端证据面 = 真 MCP stdio 27 工具 + project_create 四键无 photo_count + A→B 自持切换锚随盒进程级亲证。**挂账单一清单六项** = VALIDATION §挂账（①S1 → M7-4 修复批首项〔poll POLLIN + revents 分流 + 双路探针脚本复用回归；勿顺手修〕②S2 → M7-4 裁决三选一〔预热/协作化/文案〕③S3 → M7-4 顺路正臂补一腿④第二路事故自我申报登记〔M2-7-3 parentage 纪律再提醒——同类条目已在案（本文件 M2-7 节「测试宿主进程清理教训」），指针化不另立 LESSONS〕⑤M7-2 顺路件六项清偿确认〔F-AC-1/2 + N2-1/3/4 + ⑥ 句〕⑥EOF http-absence 偏离 + 双臂不对称如实化〔DECISIONS 已钉〕）；next = M7-4（MCP O4 跨图批量 + note 归属 + UQ-A2，MCP2-08..09）。

### M7-1 执行批批注（2026-10-16 夜，停手批——D-6 阈值理论证伪 + 探针协议硬化正本）

- **D-6 "threshold form" 修法理论证伪（停手主因）**：FIX2 C1/C2 饿死读数在今日 HEAD 复现失败——六形态（HEAD 座位/case-B/A+B/C1 纯摘/C2 纯摘/基线）+ 编辑器面 C3 重组全部环活（空载 28-35% 带、编辑器 96%；环符号同族在场 = 决定性判读，CPU 非判读载体）。正本 = `phases/m7-1-shell/M7-1-01-DECISIONS.md` + `gui-acceptance/m7-1/t1-scratch-matrix/MATRIX.md`。零产线 commit、零新 UserDefaults 键；下一步 = 用户晨审定向（硬化协议重跑 FIX2 scratch → 不饿死则脱离树形域）。
- **探针读数协议（正本，后续批次强制）**：①**可见窗门控**——一切 CPU/sample/transcript 读数前 `set frontmost` 先行；遮挡态读数 ~0%（FIX2 观察#1；FIX2 时代 "CPU 归零" 饿死读数与遮态同形 = 归因候选#1）。②**环符号判读优先于 CPU**——CPU ~29-35% 可为 AppKit 骨架残环；makeMainMenu/updateMainMenu/prependValue/mangled-name 计数才是环存活判据。③带参启动进程（`-la_editor_probe …`）的 pgrep 禁用 `$` 锚尾。④挂账⑥三轮复测配方产出：churn 在场态 3/3 全净（6/6 行、DB=6、0 迟到）= 「churn→grid 迟到」因果的反向旁证（D-FIX2-4 口径维持）。
- **测试宿主 AX 桥限制（座移类改造必读）**：in-process AX 走查只物化 safeAreaInset 内容；普通 VStack 行内容不物化（含 topBar 等既有行 id——先在行为非回归）。`AXEnhancedUserInterface`/`AXManualAccessibility` priming、NSHostingController/HStack 包裹挂载形均无效。涉 AX 断言的座位迁移需先解断言面适配（详 `.work/gsd/phases/m7-1-shell/M7-1-01-DECISIONS.md` D-M7-1-01-2）。
- **SPM 解析代理坑**：本机 proxy daemon 未跑时 xcodebuild 包解析（libwebp 子模块 clone）失败——git 全局代理未设而 env proxy 指向 127.0.0.1:10809；配方 = `env -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY -u ALL_PROXY xcodebuild …`（直连可通）。

### M3-4 架构增量（2026-10-10，M3-4-01 执行批——FSIM-02 宽容度面板约定正本）

- **精确锚落点（01 T1，obs-6 硬序兑现）**：`solveKnee` exact 形 t = a∓N（M3-3 简化臂 t=C∓N 退役；scene/medium 常数降格 no-film fallback，锚由 resolver 注入）+ optional 化 typed 域守卫（`landingRoomFloor` 1e-3，nil = invalidDemand）+ m≥2 **深膝 bracket 确定性几何扩张**（exact 形 F 严格递增、F'(K*) 有正下界 0.0447..0.3493——旧「F 递减/切点」注释为简化臂病理，已改正；m=8/N=8 根 ≈−60 案例在册）。**§6.4 四行 8 值公开参考向量** = golden 反向钉死正本（文件内独立 solver，产线 ≤1e-8；K_s<K_h 排序门 + 第五行交叉 typed 拒绝 + 域守卫负测）。**简化臂缺陷措辞定版**：m=2 多项式 bracketing 不可行之机理 = 自然域端点同号（fq(0)=+0.90/fq(50)=+6.1e6）+ 增外根 v≈0.125 截胡（真根两侧正常变号）——产线从不解多项式。
- **Placement Params v2（RFC-023 §8.3 wire 纪律）**：resolved knees（k/h × shadow/highlight）= additive optionals 随 params 走 wire（换纸不静默改既有编辑）；v1 零档字节零漂移、**非零 v1 = typed degrade 到默认 identity**（真实面为零）；`commitParams` 直包 uniforms（solve 移出 GPU commit 路径，FilmMethodBox solved-pack 同构）；`clamped()` 膝点穿透（wire state 非 clamped 输入——首轮三红根因）；`validateCoreOrder` = 联合规则②单源。
- **descriptor 运行时（01 T2）**：`ProfileLatitudeDescriptor` + ISO 6846 归约（**E1 修正判据式**：highlight = 首个 `Y ≥ Y_black+0.9(Y_white−Y_black)`；shadow = 升序最后一个 `D ≥ 0.9·D_black`——「Dmin+0.04」字面为常函数退化弃用）+ `FilmDescriptorCache`（fnv(pairHash⊕probeTag)，LRU 4）。**probe = 真链 + scan seam**：1024×1 ramp 过 `PixelPipe.assembleFilmLeg`（产线 factory，film 腿测试零改 = 零行为门）；**响应列 = print reflectance**——腿输出为 scene-referred 10^e，须过链自身前向 `FilmPrintBake.systemDensity`（同会话项单源）回映射，scene 面直接归约与上游实测表全盘失配。本引擎实测（portra×endura）：pair 5.9148 stop（带 [4.0,7.5]，上游 ISO 锚 5.66）/ reference_ev +0.068（mid 锚读法）。T(E) 单调门 = highlight 边界下 band 2e-3（65³ 地板 reflectance 域表达）+ plateau 豁免。
- **宽容度面板（01 T3）**：直方图轴 = **原生跨度 [−6.5578,+2.4394]**（256 bins×[0,1] 过 binEV；±12 为 ramp 域不混用）；占比 = 整 bin 分类（跨界归内侧 ≤1 bin）；有效性三规则终形 = ①滑杆动态最小值 `max(0,(a−C)+0.25)` ②K_s<K_h typed 拒绝点名滑杆+回弹（禁静默钳制）③H_min=3.0 = **Fit 建议面守卫**（推荐 room<3.0 → 收回+橙提示；手动不拒不钳——§6.1 型场景 Fit 恒拒 = 注册行为）；Fit = margin 0.25 + a≤C 侧 off + m≥3 交叉 λ 比例分摊（λ→0 = 双侧 off 简并；m=3 交叉例 −0.602/−0.293 亲证）；三 readouts（核宽/落点/端点斜率 g'_Δ——§6.4 发布值 0.0648/0.0820 逐位）。
- **stats/descriptor 投递（m5 机制 (b)+(c)）**：(b) Registry 直方图适配器保留 LastValue 快照（`FilmStatsSnapshot.last`，IOP 侧）；(c) coordinator PREVIEW 完成点镜像 `filmStatsSnapshot` @Observable 面 + `filmDescriptor` cache-first——面板唯一数据源零第二真相；PixelPipe 唯一增量 = factory 抽取（预申报零行为门）。
- **页面挂载（01 T4 结构修复）**：InspectorView（export/film 页宿主）在 gate-false 面只挂于 ContentView `.inspector(isPresented:)`——binding = **`exportPageActive || filmPageActive`**（dismiss 双关；**present 侧 no-op**——SwiftUI 呈现回声不得盖写活动页）。编辑器右列常态 = 调整栈，InspectorView 非常态挂载。
- **Film 页入口**：View 菜单「显示胶片面板」无门静态项（零 MenuCommandID/零快捷键——三电路零触）+ 画布卡 tap 双入口；DEBUG 探针缝 `-la_film_probe`（合成输入环境的走查通道）。菜单/画布/步进器合成激活环境级全惰（三路对照实验在案）——GUI 走查 Manual-Only 行配方 = `.work/gui-acceptance/m3-4/MANIFEST.md`。

### M4-1 架构增量（2026-10-10，M4-1-01/02 两执行批——TIFF 栅格开发链约定正本）

- **路由单源（02 T1 翻转，OQ-6 生效值）**：`RAWDecoder.decode()` 三分派 = RAW（`isRAWUTI`）→ **TIFF 族**（`isTIFFUTI` = `public.tiff` conform，含 .tif/.tiff）→ 其余 raster（`decodeRaster`，**退役保留**——「快速浏览模式」复活路径，退役臂快照测试钉住）。`decodeTIFF` 两臂：LUT-ICC（A2B0 无 matrix-shaper）→ `iccLutConverted` CI 臂（ColorSync 全管理，KD-1 唯一 LUT 面）；其余 → 原生字节腿 + `RasterColorDescription`。CMYK typed 拒、16-bit gray typed 拒（01 缺口待供件）、多页取 0——**这些拒现在于 open 时上浮 decode 错误 alert（翻转后行为变化，登记）**。
- **E1 ①′ 自洽（路由翻转的位基线承载）**：linear-ICC ∧ float32 ∧ displayReferred → `sceneLinear` → `raster_input_scene_linear` 矩阵支（上限不钳）——BandStreamer 栈/HDR 产品的回流面；IOP 562/1/0 + IOPParity 427/3/0（含 HDRPipelineMatrixTests torture/merge 产品）= 逐位基线 × 翻转自洽终证。
- **PixelPipe 输入分派（02 T2，封存面解封②兑现）**：`renderInputPlane` 三 return 之前按 `rasterColor != nil` 分派 `renderRasterInputPlane`——原生子形经 `RasterDecoder.windowedPayload`（negotiation 窗口 box 重采样，**top-first** = 输入平面约定〔RAW03 钉值证；Fixtures 的 row0-bottom 注记只描述终末 gamma/显示腿采样面〕，LE 字节序，≤1px 源边取整登记）+ `RasterInputStage.run`；LUT-ICC 子形经 CI 转换平面 + `RasterInputStage.runDisplayInverse`（TRC=linear 恒等）。`inputPlaneDedupeKey` 折叠描述指纹显式字段（nil = 旧两元折叠逐字节）。bucket-uniform：full/preview/thumbnail 共享核，分辨率经 payload。
- **raster 默认 record 装配（02 T3，OQ-1 落点）**：`WorkspaceModel.seedRasterDrtRecord` 三支（非 raster 零动作 / restore·幂等先 / carrier-only derive——`method aces20` 恒非默认故 carrier 必持有；**sidecar 零写直到编辑**）。**raster pristine 例外**：has_edits 判定面不变（history items/position）；渲染面 = carrier 有 derive → `terminalTailPolicy` 自动 `.drt`；**undo 到顶 = derive 重铺替换 stale carrier（渲染恒 DRT）**——与 RAW「undo 到顶无尾」的显式偏离（Alcedo「DRT 恒在」）。defaultLook mint 对 raster skip（上游 D2）。RawDecodePanelView：raster 文档隐藏 NR/decoder/boost 三节 + 输入色 readout 四行（profile/origin/transfer/peak）。
- **HDR 视口（02 T4，OQ-4 落点）**：PQ/HLG fixture → derive（rec2020, st2084/hlg）→ M2-6 DRT-HDR 视口臂（16F+EDR+itur_2100_PQ/HLG）零新渲染代码；peak 描述→record→EotfBox 贯通；`ExportVariant.validate` 峰值门零扰动；手动 EDR 互斥（followGate）零改。
- **导入类别掩码（02 T5，OQ-5/7 生效值）**：`ImportCategory`（raw=1/tiff=2）+ `library.import.categories`（缺键/域外 = 双开；与 `rawExtensions` 两键正交——`LibrarySchema.tiffRasterExtensions` 硬编码 {"tif","tiff"} 永不入 RAW 白名单）；ImportFilter ③ = 族掩码（①hidden ②sidecar 不动且优先）；`Reason.excludedType` + `ImportProgress.excludedType` 分账；ImportModeDialog 类型选择器（checkbox×2 + 不可勾其他计数 + 扫描完成&&允许数>0 门 + 选择即写；扫描复用 `ImportService.recursiveFiles` public 面——**App 模块有 Session 域同名 `ImportService` 枚举，Core 面调用须模块限定**）；「tif 旧被拒→今被受」翻转 AC 恰一处（ImportFilterTests :79-87 原位改名）。
- **srgbPiecewise 注册（01 T9）**：`DrtEotf.srgbPiecewise`（serde `"srgb_piecewise"` / kernelIndex 7 / kernel 镜像 case 7 / legalEOTFs rec709 链首 + p3d65 / `isHdrEncoding` false / 导出 rec709·p3d65 curv 1024 采样表〔非 para，L053 守住〕/ DrtPanelView + 新键）；② 号无-ICC float32 默认 = **scene-linear Rec.2020**（omp-minor-1 字面勘误五处已订正——行为自洽：无 ICC 色域未知时 limiting 取最大包络）。
- **RGC-off 政策（01 T10）**：`RasterDefaultRecord.rgcOn(rasterColor:)` = 单源（raster 文档 aces20 臂双向 RGC OFF；DrtRecord 零字段零 hash 面——渲染侧政策非持久字段）；`derive(from:contentProbeMax:)` 联合规则 = 两表分离（limiting 七值源域 / encoding 六值显示域）+ legalEOTFs 复核 + γ pinned fits + linear 特例 + sceneLinear 探针 HDR 分支（→ rec2020/st2084）。
- **SC#1 收口事实（02 T7）**：HDR TIFF 导出落地 16-bit PQ，系统名 ICC 经 ColorSync 序列化**呈现 LUT 型** → 重导入走 `iccLutConverted` CI 臂（KD-1 唯一 LUT 面，PQ 语义在 ColorSync 管理内幸存）；γ 行重解析落 u8Fixed8 网格（2.2→2.19921875）；inverse→forward 带 8e-3 相对门；编辑重放 = D-H1 生产提交面（setLiveParams+commitContinuousEdit，**plain recordChange 不调度 D-S3 写**——测试缝教训）。
- **测试基建纪要**：NeutralTarget **容器 = PNG**（16-bit 像素恒等转换；禁回转 TIFF——会走新腿重钉 ~10 套件）；BUNDLE-MAP 已按 omp-obs-1/-2 勘误 + 七新行登记。键族：`rawdecode_raster_*` 18 + `import_type_*`/`import_dialog_types` 7（xcstrings 尾块纯插入；UserDefaults 新增 `library.import.categories` 一键）。

### M5-2 架构增量（2026-10-14，M5-2-01/02 执行批——Mertens 生产腿约定正本）

- **runMertensLeg 流式腿形（02 KD-1 终形）**：EV-free 预检（verdicts 只记 provenance 不消费）→ MTB 对齐（`runMTBAlignment` 行为保持抽取——KD-3，stack 严格预检留在 `runStackPrecheckAndAlignment`，Mertens 直调 helper `withNCC: false`）→ 阶段（每源一渲染 + **原位 sRGB 编码**〔平面指针逐元素 `DrtEotfMath.srgbPiecewiseEncode`，RGB 三通道，与 `displayEncodePlane` 逐位同〕+ staged 像素）→ **共享 union 掩码单通道**（merge.py 并集语义：union 跨源 max 累积 → 全帧**一次** dilate + **一次** feather → 单 `mask.u8`；per-source 全流水 = 近似非正本——dilate max 可分配、feather 不可分配）→ staged 网格行读回估 129 点置换 LUT（static 格定义在最终掩码上；等价测试钉整帧 `substituteLUTs`）→ **对齐带 band-outer**（`mertensAlignedBands`：起点整除 2^(L−1)、band 高同倍数取整——01 DECISIONS §6 约束兑现；halo = max(32,2^L) 恒为对齐模倍数故 stripFirst 保持对齐；带内行 vs 整帧逐位有驱动级测试）+ 置换 in-pass（provider 内 `applySubstitution`；NaN→0 = E³≈8.5e-5 自然近零权）→ `landStackProduct` 单一路径。进度恒式 4N+3 两档（tier off 同值）。
- **StagedSet 面**：嵌套类型 private→internal（01 KD-2 访问先例）+ `writeMask`/`readMaskBand`（共享掩码无 shift——α 在参考/输出帧坐标，不随 MTB shift）+ `readPixelRow`（LUT 网格行）。
- **分离式 dilate**：`mertensSeparableDilate` = max filter 轴分解，与 golden naive `MertensFusion.dilate` **逐位恒等**（测试钉死）；生产半径 32-58（tier 缩放）下 O(r²) naive 为分钟级、分离式秒级；golden 面零触碰。
- **域判别（KD-2 正本）**：`writeFloatTIFF` additive `colorSpace`（缺省 working space 零漂移负测钉字节相等）；Mertens 产物 sRGB-tagged 32f → 重导入 `.srgbPiecewise`/`.displayReferred`（Primé 不触发）；两域两门互证测试在册（Robertson02 产物 = Primé → sceneLinear 对照臂）。无 ICC float32 = scene-linear ② 规则回归钉在册。
- **landStackProduct additive 四臂**：`exposureEVs`/`ghostUnion`/`implementationVersion`/`productColorSpace` 全 default-nil、nil = 既有字节零漂移（既有 kind 快照负测）；ghostUnion 含 1 → runHDRLeg 尾形（dilate + Ghost Suppression layer stack），掩码语义 = 置换掩码。
- **UI 面（KD-5）**：`SessionBrowserView.onHDRMertens`（≥2 多选 gate + 简形 sheet：标题/body/开始零档位控件）→ `ContentView` 穿线 → `SessionCoordinator.mertensMergeHandler` → LightamerApp `enqueue(.hdrMertens, MergeParams(deGhost: false, tag: nil, mertensDeghost: "medium"))` + `toast_hdr_mertens_queued`——tier 恒显式、deGhost 为 Robertson02 旋钮恒 off、tag nil = mertens 缺省。
- **键族登记**：`browser_menu_hdr_mertens`/`hdr_mertens_dialog_title`/`hdr_mertens_dialog_body`/`hdr_mertens_dialog_start`/`toast_hdr_mertens_queued` 五键（xcstrings 尾块纯插入）；UserDefaults 零新增。
- **探针/预算惯例（正本 = `phases/m5-2-mertens/perf.md`）**：`MertensFusionPerfProbeTests`（EXPORT，`LIGHTAMER_PERF_PROBE=1` 门）；PERF 行走 **stderr 无缓冲**（stdout 块缓冲在异常退出丢行）；staged 写后 `synchronizeFile`（GB 级脏页计入 phys_footprint 会引发系统性压力杀进程——ru_maxrss 本身达标也会死）；**被杀进程 defer 不跑 → `$TMPDIR` 残留，探针/基准轮前后清扫**（LESSONS L077）；16GB 机器 100MP×5 全路径磁盘轮系统性边缘——CPU 数值面走 `swiftc -O` 脚手架（genbench 无盘模式），staged-IO 段独立出数；Release 直启 WebP 包 framework 动态链接不对称（Debug 静态/Release 动态且未 embed）= 环境债在册（perf.md §事故 4；D-09-04-D9 重签+entitlements 配方不达——根因 framework 未产出）。

### M5-3 架构增量（2026-10-16，M5-3-01..03 执行批——全景合成约定正本）

- **MergeKind.pano additive 第七 case（01 KD-6/01 裁决）**：rawValue `"pano-merge"`；四处穷举 switch 补臂（provenanceKind 镜像 `panoMerge` / `stepTotal(.pano) = 3N+6`〔decode N + 特征 N + 融合 N tile-paced bump + 6〕/ `defaultTag(.pano) = "pano"` → **`_pano` 分账名** / dispatch 腿路由）；`MergeParams` additive 三 optional（panoCanvas/panoGains/panoCrop，synthesized encodeIfPresent 旧档零漂移）；**enqueue 32 门 = kind 条件式**（六既有 kind 路径字节不变）；`ProvenanceReplay.Kind.panoMerge` 镜像 + 双常量。
- **P1 数学核心六新文件（全 `LightamerCore/Sources/Stack/` 纯函数；MIT 语义移植注记在文件头注，Lumen `merge.py` 正本；darktable GPL 零复制）**：PanoFeature（SIFT 语义 DoG：σ0 1.6/intervals 3/contrast 0.04/edge 10/128 维定向描述子 root L2/6000 帽/预览 ≤1200/≥10 每图；**预览灰度双缝** `preparePreviewGray` rgbaLinear/rgbaEncoded——checker minor-2，encoded 缝跳过再编码）→ PanoMatch（bf knn best-of-2 + Lowe 0.3 + RANSAC 3px/3000/0.999 自适应 + 置信 `inliers/(8+0.3m)`〔**OpenCV 原形**——plan 文本 `1−` 形为转写笔误，验收批两路复算勘误〕+ 边门 conf>0.6 ∧ inliers≥10 + BFS 连通门）→ PanoCamera（focal-from-homography 闭式 + median 锚 + **LM BA 3N+1** refinement f+R + 横向 wave correct；残差世界侧 `Rᵀ·u`、居中坐标契约、数据相对成功判据——三条探针教训在 01-DECISIONS）→ PanoWarp（sphericalMap 直译 z>1e-6 无效 = −1、角度 Double/结果 Float32；boundedCanvas ×0.998 ≤8 轮 200MP 帽）→ PanoGain（≤900 采样/≥80 样本/(0.04,0.9) 门/锚权重 10/**dgelsd 最小范数**〔checker O2：正规方程不连通奇异——非等价自由度〕/clip ±0.5）→ PanoCrop（min-pool ≤1024 格 + 直方图栈最大有效矩形 + naive 参照逐位）。
- **PanoRNG 种子纪律**：LCG（MMIX 族常数）**种子 121** 单流——RANSAC 采样 + 自适应迭代唯一熵源；tie-break = 最早达到（RNG 序）/索引序，确定性全自握；**禁系统随机源 grep 门 = hardened 形**（`SystemRandomNumberGenerator|srand|arc4random|\.random\(`——minor-4 处方含 `\.random\(` 底层形态）。
- **typed 三态词汇（跨 plan 契约链）**：canonical 前缀钉 P1（`PanoMatch.FailurePrefix`：`"panorama alignment failed: "` / `"panorama images disconnected: "` / `"panorama canvas invalid: "`，载体 `AppError.invalidParameter`）；App 侧消费 = `PanoFailureCopy`（`failureKey` 纯函数前缀表 → `pano_error_*` 三键 + `failureMessage` 消费面——**显式 switch 返回静态键**〔V14 纪律，零运行时键 LocalizationValue〕；命中 = 换文案 + 保留 typed detail + 剥样板头；非前缀逐字节透传）；挂载 = `mergeService.setFailureHook` 显示层（Mertens FAIL 同路）。
- **生产腿（02 换腿体，`runPanoLeg`）**：**双 pass 几何/融合分离**（pass1 = `panoValidMask` 纯几何 UInt8 1B/px 零 staged 读 + PanoCrop 先解析裁切界——valid = weight>0 为纯几何量的依据落 DECISIONS §4；pass2 = `panoFuseRows` 逐带）+ **band×源一次联合 span 读**（64×64 strided 采样 + ±128 pad、grown-once 条带缓冲——读体量 84× 降的探针事故产线修复，perf.md §事故）+ landStackProduct **rowProvider additive 臂**（`((_ firstRow: Int, _ rowCount: Int) async throws -> [Float])?`，nil = 既有路径字节零漂移负测钉死；融合 bump 每 band 递减预算）+ **FloatTIFFWriter 手写 classic strip TIFF**（头 8B + float32 行逐带直写 + finish() IFD/ICC〔`CGColorSpace.copyICCData`〕回填 + 同目录原子晋升；ImageIO one-shot finalize 需全平面驻留触红线——checker minor-3 容器策略定夺；ROWS-per-strip 契约 = 首 strip 行数仅末 strip 可短）。extent 门故意缺席（异视点合法，KD-10）——与 Mertens/HDR 分界腿头注申报。
- **产物面**：sRGB-tagged 32f strip TIFF → M4-1 raster ingest（REAL 域判别 `.srgbPiecewise`）+ alpha 恒 1 + provenance details 三字段（panoCanvas/panoGains/panoCrop）+ alignment 标签（`reference / inliers=<n>` 确定性字符串）；恒 inner_crop 无 alpha（OQ-5）。
- **预算探针（正本 = `phases/m5-3-pano/perf.md`；NO GATE——越门 GPU 另立项，OQ-6）**：`PanoFusionPerfProbeTests` 2 法（EXPORT，env 门；主探针 + footprint 诊断三臂）；196MP 画布 × 8 源：几何 ~185s / 融合+流写 1630.9/1634.1s（8/8 源，±0.2%）/ ru_maxrss 5033/5653MB 8G 门内；**参与门 PERF 行 `pano-participation|<n>/8`**（E-omp-1 教训：band-span X 守卫漏 originX 致 5/8 源静默丢失——几何守卫回归法必须非对称）；遗留观察 = freed-but-resident footprint 爬升 +388MB/band（RSS 健康，挂 perf.md）。
- **UI 面（03 KD-1/KD-2）**：legacy face merge 菜单第三项「全景合成」（`onPano` nil = 隐藏 gate 形）+ **简形 sheet 零控件**（标题/正文/取消/开始；正文单键承载四生效值：同视点/重叠 ≥30%/2 亿像素帽超限等比缩小/恒自动裁边）→ `ContentView` 穿线第四段 → `SessionCoordinator.panoMergeHandler` → LightamerApp `enqueue(.pano, MergeParams(deGhost: false, tag: nil))`（deGhost 腿不消费恒显式 false）+ `toast_pano_queued`。
- **键族登记（8 键）**：`browser_menu_pano`/`pano_dialog_title`/`pano_dialog_body`/`pano_dialog_start`/`toast_pano_queued`/`pano_error_alignment`/`pano_error_disconnected`/`pano_error_canvas`（xcstrings 尾块纯插入 136/0；zh-audit 1651/1890 PASS）；UserDefaults 零新增。
- **封存面零解封申报**：`2fee806..c5f5dce` 清单外新增面 = Pano 六新文件 + FloatTIFFWriter + `StagedSet.readRows(+into)` + MergeKind.pano 臂族 + landStackProduct rowProvider 参 + zh 8 键——**全 additive 申报**；封存清单内面零 diff（`g5-redline-checks.txt` 十一项电池亲证：LightamerIOP//LightamerCore//`*.metal` 全域零 diff、dependencies 块零 diff、schemaVersion 零触、runModal 零、LocalizationValue 插值禁形代码零）。
- **G4 结构对照形态（03 KD-5，非门值）**：仓外 uv + opencv-python-headless 一次性（政策 B 磁盘路径 `evidence/opencv-structural-compare/`，零主仓 commit、零入仓代码）；opencv 5.0 绑定面收缩（Stitcher 组件 getter 移除）→ 结构证据走 **Lumen 腿 OpenCV 段活体实跑**（六 API 5.0 全可用）；`BestOf2NearestMatcher.apply2` 返回 = 2×2 展平 tuple（非 ndarray 二维寻址——记录供后用）。

### M6-2 架构增量（2026-10-16，M6-2-01 执行批——per-photo process version 约定正本）

- **process 账本（正本 = `LightamerCore/Sources/Pipe/RenderProcess.swift` case doc-comment，本节 = 磁盘镜像；两源随每次 bump 同批改）**：
  - **号 0 = legacy**（pre-process 冻结档——`.lra` 无 `process` 键 ⇔ 键 ABSENT ⇔ 语义 legacy；渲染语义恒冻结，永不被动升级——零漂移承诺本体）；**号 1 = M6-2 时代基线**（`v1`——mint 盖章的「本代」，与 0 渲染逐位恒等，尚无语义分叉）。
  - **bump 纪律三层**（改观感的 iop 语义变更 = 唯一 bump 触发；性能/内部重构不 bump；crash/NaN/黑图/decoder 错修复 = 原地修非 look）：①`RenderProcess` 追加 case（编译器逐点指向所有分叉处）+ `all` 尾插 + `RenderProcessVersion.current` 升号 ②新旧号各钉渲染 golden 随批交付（冻结 golden 常青）③AGENTS 本账本行 + 枚举 case doc-comment 同批登记（每号一行：号 / 落地 batch / 改了什么观感 / 冻结分支位置）。**M6 批内 iop 调参类 plan 的 AC 模板行**：「若本 plan 改 iop 观感：bump process + 冻结分支 + 新旧号 golden 三件套随批交付」。
- **sidecar v10**：`process: Int?`（拼写冻结 LightCraft 同名）+ schemaVersionCurrent 9→10。canonical 规则一句话：**nil ⇔ 键 ABSENT ⇔ 语义 legacy**（encodeIfPresent——legacy 档 re-encode 键恒 ABSENT）。**lenient decode 双门口径（M1）**：值类型域门 `RenderProcessVersion.init?(rawValue:)` = `0...0xFFFF_FFFF`（含 0 = legacy 哨兵）；sidecar 存储值 decode 域门 = `1...0xFFFF_FFFF`——stored-0/null/损坏（负/非整浮点/字符串/数组/2^32）→ nil 归一 ABSENT（损坏不保留、不毁档其余字段）；整值浮点 `2.0`→2；**前向大号原值保留**（存回不降级）+ 渲染钳 `RenderProcess.resolving`（≤0→最老 case / >current→current）。「入册 ≠ 升级」：9→10 仅键族入册，无联动迁移语义。
- **hash isolation**：process 不折 `HistoryHash.hash` / `driftDetected`、零 history item（undo/redo/jump/版本 swap 零触——文档级键跨编辑历史恒定）；**与 modversion 正交**（`ModuleInstance.version` = params 形状迁移且折 HistoryHash——禁把 process 折入任一，零 diff 红线机检兜底）。**缓存键分叉点折键契约（KD-6）**：M6-2 零分叉 = `PipeCacheKey` 零改；未来某 stage 真按 process 分叉时该 stage 键折 process 值，折形 = **非 legacy 才折**（`rawValue > 0` 折值；0/缺键不折——legacy 档键字节与今日恒等；`edgeMapAlgorithmVersion` 先例形）。契约三处登记 = RenderProcess.swift 头注 + 本节 + DECISIONS。
- **管线读缝（armed，零行为）**：`PixelPipe.renderProcess` run-scoped 属性（terminalTail/filmTail 同位）+ `process`/`processComposite` additive 参数（缺省 `.legacy` = 既有调用点字节零变化）+ IOPiece `renderProcess` run 常量 stamp（forwardWalk 一次性，iscale/pipeType 同族；**不入 paramsHash**）+ 派生 sub-run pipe 继承（DRT tail/film/replay/LayerCompositeDriver base/layer/terminal 六处；no-op throwaway 豁免注记在位）。**M6-2 无生产消费点**（KD-5）——文档值 → pipe 的生产传值接线 + 分叉 iop 消费 `RenderProcess.resolving(piece.renderProcess)` = **首个真实分叉批的挂账件**（与 OQ-5 迁移 UX 挂账同批触发）。G2 冻结语义 golden = RenderProcessSeamTests 三式（legacy 跨模拟分叉逐位不变 / 分叉可见 / 缺键=legacy 臂 sidecar→pipe 贯通）。
- **App 面**：WorkspaceModel `processVersions` 载体（四件族同形；**ABSENT 键 = .legacy**——与 drt/film「缺省=pristine」极性相反，legacy 是合法常态值）+ restore 面无写回回声 + 关图丢弃；PipeCoordinator load 腿双分支 prime（有档 = `document.process ?? .legacy`；pristine = **mint `.current`**「盘上无 sidecar，imageID mint 同批」）+ `makeSidecarDocument` 唯一写缝（`rawValue == 0 ? nil : carrier`——legacy 永不被动升级、前向大号不降级）。
- **出生点盖章五面**（全部首次建档点）：①coordinator pristine 载体 ②ImportService AI 副本 ③④StackMergeService HDR/Mertens+Pano 两 writer ⑤a SessionBatchApplier **分支条件盖章**（E1：该臂非 round-trip——字段挑选重建全新档，process 须显式携带 per-arm 提升 `processStamp`，禁跨臂 `?? .current`）⑤b MetadataService pristine 臂（既有档臂 = 真 inout round-trip 零改自动保全）。**E1 双登记**：pre-M6-2 SessionBatchApplier 既有档臂静默丢弃全部文档级 additive 字段（provenance/rawOverrides/displayTransform/versions/activeVersionID/aiProvenance/filmRecord）= 数据保真缺口，M6-2 不修挂观察项待 fix batch；process 在本臂的携带 = 显式新增面非自动保全。
- **传输零携带**：Copy Adjustments（`isAdjustmentTransferable` 谓词 + payload = records+snapshot+drtRecord，process 结构性在传输集外）/ 预设 apply / LightamerPreset 容器——三负测钉死。**范围边界**：零 MCP 工具面 / 零 UI 面 / 零格式矩阵触碰 / 零新 SPM / 零 `.metal` / 零 xcstrings-UserDefaults 新键（全部机检在案）。
- **键族登记**：sidecar `process` 一键（JSON 拼写冻结）；xcstrings/UserDefaults 零新增。测试落账 = SidecarV10Tests（LIB 15）/ RenderProcessSeamTests（LAYERS 8）/ ProcessVersionCarrierTests（APP 8）+ additive 5 法（StackMerge 2 / Import 1 / SessionBatch 1 / Metadata 1），全套预期 **3725/24/0**（基线 3689 亲核 M6-1-VALIDATION）。

### M6-3 架构增量（2026-10-14，M6-3-01 执行批——ALCE-03 UltraHDR gain map 导出约定正本）

- **编码路线（charter 演进正本）**：research 三臂实测证 ImageIO aux 两键死路（`CGImageDestinationAddAuxiliaryDataInfo`+`kCGImageAuxiliaryDataTypeISOGainMap` 七种 payload 形态全拒〔disparity 对照臂同拒〕/ `kCGImageDestinationEncodeGenerateGainMapWithBaseImage` 被 AddImage 静默忽略 + JPEG destination `count=2` 构造即 nil）→ **正解 = Core Image 全服务写** `CIContext.writeJPEGRepresentation(of:to:colorSpace:options:[.hdrImage:…])`（macOS 15+）——CI 自算 gain map 写出**完整 ISO 21496-1 容器**（MPF APP2 索引 + ISO APP2 URN + 尾部 gain map 副图 + Apple HDRToneMap）；**PQ/HLG 码值直喂 = gain 语义错误，必须喂线性光**（E4 实证）。LightCraft Rust 移植臂（C 路）降兜底封存——零代码零 NOTICE，激活条件 = 老 Android/Chrome 副图内嵌 hdrgm XMP 裁硬需求（届时与 EXIF 注入器批同评，~400+ 行手工容器装配为成本大头）。
- **validate 六门（`ExportVariant.gainMapHDR` additive 字段的 typed 拒集）**：①format == .jpeg ②drtOutput != nil ③peak ≥ 203 finite（headroom = peak/203 ≥ 1）④!embedICC（**ExportICCStrip×MPF 雷**——`stripJPEGICC` 删 APP2 段使 MPF 副图绝对偏移失效，gain map 档 embedICC=false = typed 不可达）⑤!isHdrEncoding（st2084/hlg 编码 base 拒——增补裁决 D-M6-3-7，UltraHDR 语义要求 base = SDR rendition、E4 物理约束的 base 侧投影；planner 权限外收窄由 orchestrator 裁准，晨审推翻 = 三处回退 + 豁免显式登记）⑥!yiyin（borders/watermark 在 EotfBox 后回放致 capture 面与出口位图尺寸分叉；validate-only——M2 页 makeVariant 恒不设 yiyin 结构性不可达）。**双锁尺寸分叉防护** = 门⑥ + encoder 内第二道硬守卫（`ExportGainMapEncoder.encode` 尺寸 guard typed 拒——直接 Request 绕过 validate 仍 fail-loud）。
- **capture 窄缝（`PixelPipe.linearGainCapture`，9-hunk 解封申报正本 = DECISIONS §2）**：PixelPipe 恰 7 hunk（:154 属性〔tailFormatFloatOverride 同位〕/:1098 tailPipe 继承/:1595 processRec uncached 臂 EotfBox 位回调〔**唯一捕获点**——export 恒冷缓存走 uncached 臂，cached 臂不可达〕/:2080+:2093 process 双 hunk/:2142+:2154 processComposite 双 hunk）+ LayerCompositeDriver 恰 2（:204 参数/:568 terminalPipe 赋值——composite 导出 capture 活性承载）；捕获判定 = **`box is ModuleBox<EotfBox>`**（pieces 持 `any ModuleBoxing`，裸类型判定恒假死代码；TailOrderedBox 直 conform `ModuleBoxing` 非 ModuleBox 子类 → 无假阳；EotfBox 全仓唯一构造点 = 尾段 assembly `:1791` 裸加入链，恒不被 TailOrderedBox 包裹）；capture 面 = EOTF-box 输入平面（entry plane 语义，sizing 在 entry 施加）+ working float32（M2-6「EOTF 之前的尾平面恒 working float32」正本）；owned-copy blit 提交于 routed queue（renderStage 全程 `$routesToExportQueue.withValue(true)`）→ **同队 FIFO** 保证 copy 读到 pre-EOTF 态，CIContext 建在同一条 queue（跨队竞态结构性消除）。
- **queue 级载体（`ExportQueue.ExportGainMapPlaneBox` actor 常驻属性）**：stash（render 腿，key = snapshot.seq）/ consume+clear（encode 腿 gain-map 才取）/ clear（finish / finishCancelled / retry 入队前——幂等；fresh-seq 禁覆盖写）；注入腿永不 stash = 箱恒空零行为语义等价；`gainMapBoxForTesting` 泄漏探针（`inFlightCountForTesting` 同位）+ failed/cancelled 双路终态箱空负测；`ExportQueueContract` 封存面零 diff（M2-9-02 KD-4 递缝范式同族——Contract 文件级零 diff 红线下的 queue 级载体形态）。
- **`ExportGainMapEncoder`（CI 全服务路约定正本）**：aux 字典（纯字符串键——SDK 无对应 CFString 常量）+ **'L008' 单通道**（`hdrGainMapAsRGB` 不开——RGB 档读回侧 Data 键被 reader 扣留）→ `.hdrImage` 写出 → **同目录同卷 tmp + defer 双清扫 + moveItem 原子晋升**（L009；晋升语义 = 目标已存在 typed 失败 vs plain 路 ImageIO 截断覆盖——namer 冲突解析下正常流等价，外部同名竞争保守失败方向可取）→ **`CGImageDestinationCopyImageSource` rewrap** 补 primary XMP（`hdrgm:Version` 兼容档 + `xmp:CreatorTool` Software 座位；`.none` 档跳过 XMP 但容器仍 UltraHDR）。**AddImageFromSource MPF 雷**：该 API 重编码主图并丢弃 MPF 副图（1268B vs 15723B 探针实测）——凡 gain map 容器后处理一律 CopyImageSource。**EXIF 降级（OQ-2②）**：`{TIFF}/Software` 被 `CGImageMetadataSetValueWithPath` 拒（**L054 的 {TIFF} 座位是 ImageIO 编码路事实，不适用于 CI 编码路本档**；exif:Software XMP 命名空间值不可读回 APP1）→ **v1 无 EXIF**（六格式矩阵唯一 additive 档偏离，预授权登记）；EXIF APP1 注入器 → 挂账 v2 批（段级注入与 MPF 偏移互斥，与 C 路同评）。
- **encodeStage 后处理双旁路（MPF 绝对偏移雷消解）**：gain-map 臂 arm 首行 guard typed 拒 + 产物路径显式 return——`stripICC`/`mountXMP` 结构性不可达（删段/改段均破坏 MPF 内部偏移）；非 gain-map 路逐字节不变（负测钉死）；M4 fail-loud guard（armed 无 plane → typed 拒 + 落盘零残）。
- **203 单源三消费点**：`ExportGainMapEncoder.sdrReferenceWhite`（=203）单拼写——validate 门③（ExportRecipe）/ UI 门（ExportInspectorView）/ headroom 计算——零双源；peak<203 = checkbox 默认灰 +「低于 SDR 参考白无 HDR 余量」诚实文案（gain map 是 DRT Peak 拉高后的选项，非缺陷态）。
- **M2 页五维门 + 复位三入口**：SDR 导出节 checkbox 可用门五维 = format/noRecord/peak/embedICC/encoding（门⑥ yiyin = validate-only）；UI↔validate 子集对表无残口（peak 维 NaN 比较语义等价 validate isFinite 拒；单值贯穿——`currentEffectiveRecord` ≡ `makeRunAssembly` ≡ `enqueueExportM2` 同一 record 实例）；复位三入口闭 = embedICC setter + format setter（页内）+ run-face 复核（`makeRunAssembly` 复位先于 `makeVariant`，`RunAssembly.gainMapAutoReset` 携带 blocked 维度 + V14 显式 switch 静态键 toast）；enqueue 联动 = OQ-7 强制 `assembled.drtOutput = drtRecord`（UI noRecord 拦旗标 ≡ 门②不可达）。
- **键族登记**：`export_gainmap_label` / `export_gainmap_hint` / `export_gainmap_unavailable_format` / `export_gainmap_unavailable_peak` / `export_gainmap_unavailable_encoding` 5 键（xcstrings 尾块纯插入 85/0）；UserDefaults 零新增。测试落账 = ExportGainMapTests（EXPORT 25）/ ExportGainMapPanelTests（APP 9），全套预期 **3759/24/0**（基线 3725 亲核 M6-2-VALIDATION）。

### M6-4 架构增量（2026-10-14/15，M6-4-01/02 执行批——图库 stacks + AI 分割蒙版约定正本）

- **LibrarySchema v5（两新表 join 形态，D-M6-4-1）**：`stacks` + `stack_content`（WITHOUT ROWID，PK (stack_id,image_id)，双 CASCADE）+ UNIQUE 索引 `idx_stack_content_image`（**一图一栈 = DB 级不变量** + stack_of 反查）；`images` 29 列冻结清单零触碰；**封面 = position 0 成员单真相**（不设 cover 列）；迁移槽 `from <= 4 && to >= 5` 三条 `CREATE IF NOT EXISTS` 幂等 + 快照轮换 `pre-migrate.4-5.bak`；`stacksColumns`/`stackContentColumns` 冻结面新立、`indexNames` 恰一行追加。
- **CRUD op 族（KD-2/KD-3）**：LibraryStore 全 op 族单事务（withWriteBatch）——createStack/group/stackWith/setTop/moveInStack/splitStack（delete-all + prefix 复用原栈 id + suffix 新栈）/ungroup/removeFromStacks/setCollapsed/setAllCollapsed；removeImage 解散清扫与删除同事务（<2 成员 CASCADE 余栈整栈解散）；**group/stackWith 新栈恒 collapsed**；split 尾栈继承 flag（D-03）；无 undo（D-04——图库域无 undo 基建）。
- **auto-stack 聚类（KD-4，LightCraft 全套语义）**：StackClustering 纯函数（capture ASC + tie id ASC 稳定排序 → 相邻 ≤gap 归簇 → **runs≥2 才成栈** → nil-capture/已堆叠双 skip）+ `defaultGapSeconds = 60`；store autoStack = preview 零写（整包 clean-close 字节恒等钉死）+ commit 落 collapsed + per-cluster re-check（写腿 contended 重查）+ **空池守卫**（`IN ()` 防御，`984e0256` 补）；不存 auto 出处（撤销面 = 手动解栈）。
- **分页×堆叠（D-M6-4-3 + D-01 语义收敛）**：收起态 = runPage 装配处恰一行 conjunct 的 **flag-aware JOIN**（`NOT IN (SELECT sc.image_id FROM stack_content sc JOIN stacks s … WHERE s.collapsed != 0 AND sc.position > 0)`——KD-5 字面无 JOIN 式会隐藏展开栈成员，D-01 收敛非越权；裁决本体〔纯 WHERE/keyset 零改动/唯一 diff 位〕逐项保持）；`.flat` 缺省参 = SQL 字节恒等（行级恒等测试 + 生产调用点 7 处清单，D-12 勘误版）；展开态 = App 侧页内 adjacency fixup（前拉 + displayed-set 去重 + **forward-only** D-05）+ union golden 跨页 fixture 钉无丢失；单栈展开 = 成员现 keyset 位不聚拢（D-02 v1）；收起态无首可见成员顶替 + overviewCount/groupCounts 口径分裂（D-06，V2 候选单一挂账）。
- **导入缝 merge→stack（KD-6/E1 + D-07 版本化条款）**：ImportService 白名单恰三值（`hdr-merge`/`hdr-merge-mertens`/`pano-merge`）；四步匹配 = 后缀主式（批内 map 优先 → 全库 `LIKE '%' || ? ESCAPE '\'`，**转义序先 `\` 后 `%`/`_`**）→ 多命中 folderName 消歧 → 零命中 folderName/stem 兜底 → **整组 typed skip 零半栈**；link 模式不自动成栈（`Media/` 前缀门）；`mergeStacksCreated/Skipped` additive 双计数零 UI；ESCAPE 三转义回归钉在册（`%`/`_`/字面反斜杠，`984e0256`）。
- **Grid 显示态 + UI（KD-7/KD-8）**：LibraryGridModel stackMode（.flat/.collapsed）+ toggleCollapse + expandAll/collapseAll（同时切模式与 flag）+ `stackAdjacencyFixup` 静态函数（App 侧，零 Core fixup 文件）+ reloadShrinkingSelection 不保滚动位（D-14）；徽章 overlay + contextMenu 五项条件可见性 + AutoStackDialog（gap 2..600 步 2 初值 60 + preview 零写）+ View 菜单两命令经 `pendingStackCommand` 载体 no-op 守卫（pendingAIEnhance 既有命令路由模式复用——WorkspaceHostView/WorkspaceModel 两范围外文件 D-13 补登记先例）；**范围外机械依赖补登记 = M-b 先例**（additive 命令路由载体零既有行为面变更）。
- **面 A 键族登记**：13 键（`library_stack_*` + View 菜单族，两格式键 `%lld` = focus_stack 先例同形）；schema 测试机械代际前滚 D-09 九处（零语义变更零断言放松）；xcstrings 尾块纯插入 221/0。
- **AIPatchAssembly（KD-1）**：Planner 三 skip 门（空掩码/bbox>60% 全帧 Float64/min 侧 <32px）+ pad 25% 短边 + 图界 clamp；Composer 接缝线性 ramp（带宽 5% 短边 clamp 2..16）+ **≤4 FIFO 帽** + 界外逐字节恒等；KD-4 行 2 数值门（0.6× 过渡宽 + ≤1px 缝错位）落断言字面（`74a4709d`，双分辨率解析圆 fixture，D-08 并入不加方法——SC 分账恒定先例）。
- **segmentPatch = 恰一个委托表达式**：恒走 segmentSubject + `regionOfInterest` 传 patch 归一 rect + quality 钉 `.accurate`——零第二条装配（S6' 结构面断言 1e-9）；patch 调度缝 = `commitRasterMask` 的 .segment 成功臂捕获（**生成提交即交互终点**，host 零触——SegmentEditingOverlayHost diff 0）+ `patchRebake: true` 双门跳过捕获与重调度零自环 + 1s debounce 末者胜（D-02）。
- **AIMaskFeather（D-01 换锚正本，本 phase 最重裁决行使）**：sigma = \|p\|/100×0.02×longEdge（LightCraft 同式，正腿走既有 GPU `featherRadius` 缝——**零新 kernel**）；**负腿 = 平面域 logit-gain 重映射** `x' = x^g/(x^g+(1−x)^g)`，g = 1−7·(percent/100)——plan 草案 `1 − blur(1−x)` 经线性恒等式证伪（核和 1 ⇒ `1−L(1−x) ≡ L(x)` 逐点恒等 = 与正腿同义不可能收缩），KD-3「以 LightCraft 原文为准 + DECISIONS 申报」条款生效（`masks.rs` `gain = 1 − 7e` 施加于 logits，g 上限 8 = 原文 8×；双路独立数学推导 ACCEPT）；0.5 轮廓逐点不动 + 10-90 过渡宽 ≈g 倍收窄 + 端点精确。**双羽化防（D-09）**：resolveFeather 三臂（正 → (plane, σ) / 负 → (CPU 面, 0) / 0 → (plane, fallback)）；`featherRadius` 显式参数仅 percent==0 穿透——两臂互斥数据流上不可达；非零调用点唯一双源 = `AIMaskEditing:197`（bakeRadius 穿线）+ `MaskCombiner:628`（parametric 存量）；wire 字节级双写钉死（正腿文件 == bake(σ) / 负腿 == bake(CPU 面, 0) / 0 == plain path 字节恒等）。
- **人物实例（D-05）**：`AIMaskSource.person`（"ai-person-" 前缀族，与 segment 重入门判别 disjoint）+ `detectPersonInstances` 直返 AIInstanceCatalog（零新类型，InstancePickerOverlay 零改复用）+ 提取恒标签合成（`labelComposite` 形参 = **CVReadOnlyPixelBuffer**——swiftinterface 事实 D-03；`init(unsafeBuffer:)` 桥是 `sending`——桥前必须 unlock）+ unionSelection 并集 + typed noSubject（零观察/空选中，零 all-ones 兜底）；素场幻觉实况登记（white/gray128 → 1 实例，black/noise → nil——D-06，**GUI「无人像」判定须真照片**）；`generateScaledMask` 默认腿禁用（新增调用点 0——27.0b 双损坏绕行注记）。
- **livePlane 生命周期（D-13）**：`SegmentSession.livePlane` = decode-frame 分辨率 float32 单通道（accurate 100MP ≈400MB 会话驻留，AGENTS GUI >3G 触发线同域）；释放点 = 模式退出/armSegmentSession 替换/新 seed/新生成覆写/**切层·切图身份比对**（`patchImageURL/patchLayerID` stamp 盖于 schedule 缝 + fire 缝 `releaseIfIdentityChanged` 先于 hasSeed/livePlane 门 + schedule 缝前置同判——切图后旧 stamp 即释放携带面再重捕获，patches 随释清空；`b49215bb` 兑现，**负验证先例 = 撤守卫恰两新法红**）；D-13 残差两笔登记 = 末次 pass 后切图无 pending debounce 驻留至其余释放点 + confirm 在飞切图（O-1 同族）。
- **面 B 键族登记**：`ai_mask_feather_label/ai_mask_feather_reset/ai_mask_patch_refining/ai_mask_person_instance/ai_mask_person_none` 5 键（xcstrings 尾块纯插入 86/0）；**UserDefaults 全 phase 零新增**；**格式键插值形态机检盲区在册**（01 N-3：`String(localized: "key \(x)")` 先例同形语义合规但红线 grep 不覆盖——机检硬化候选挂 M6-5）。测试落账 = LibrarySchemaV5Tests 8 / LibraryStackStoreTests 16 / AutoStackClusteringTests 9（含修批空池负测）/ StackPaginationTests 9 / ImportMergeStackTests 6（含修批 ESCAPE 钉）/ LibraryGridStackTests 10（LIB 671→729）+ AIPatchAssemblyTests 9 / AIMaskFeatherTests 6 / PersonInstanceMaskTests 5（LAYERS 474→494）/ AIMaskPatchFlowTests 6（APP 810→816）；全套终验实测 **3841/24/0**（02 双路亲跑同值）+ 修批后推算 **3843/24/0**（带 3840..3844，下一 phase 验收全套轮确认）；正本 = `phases/m6-4-gallery-stacks/M6-4-VALIDATION.md`。

### M6-5 架构增量（2026-10-16，M6-5-01 执行批——挂账清算批约定正本）

- **zh-audit V16 断言 5（格式键插值目录分诊门，01 F1/E-3 正本）**：`String(localized: "K \(…)"` 是 xcstrings **格式键合法惯例**（构建期提取为 `K %@`/`K %lld` 变体键——「禁形」定性作废，单行 grep 27 命中皆合法），门语义 = **目录占位符变体 PRESENT/ABSENT 分诊**：V16 提取 `localized_interp_keys`（同行 regex + form-1c 续行插值延拓，键→路径表），断言 5 = 每个插值键 K 目录必须存在 `K %`-前缀格式变体（`any(ck.startswith(K + " "))`；**裸静态键 K 不计**），计入 total + 报告 [5] 节逐键 PRESENT/ABSENT + 路径；spec 深检（%lld/%@ 形态错配）留人工走查非本门。self-test golden：BAD fixture 增无变体插值键（红）+ `selftest_family`/`selftest_family_cont` 补目录变体（绿）+ 1c 续行插值 twin。**后续批红线电池引用 = `zh-audit --check` ABSENT 零命中**（现树 30 调用点/30 键全 PRESENT；**覆盖限定，2026-10-16 闭环批加注（N-2）**：本门只覆盖 `String(localized:` 同行 + form-1c 续行两形态——SwiftUI `Text("K \(x)")` 族与 `String(` 跨行族**不设防**〔树内活体 = `McpLauncherPanelView.swift:225/:242/:246` 三键 zh 回退，清偿候选挂下一清算批；LCR 三跨行键变体恰在册 = 潜伏非活体〕；门扩展（Text 族 + 跨行族提取）= **V17 候选**，勘误正本 = `phases/m6-5-ledger-clearing/M6-5-VALIDATION.md` §挂账单一清单②③）。
- **三活体键清偿（01 E-3）**：`edr_headroom_label %@` / `settings_displays_overridden %@` / `softproof_active_label %@` 三格式变体键尾块纯插入（51/0，en+zh 值与既有裸键值同文；裸键经 interp 前缀族覆盖留目录）——清偿前 ABSENT 3 键 = M2-9 F-2 家族活体（运行时回退裸键观感）；调用点代码零改。UserDefaults 零新增。
- **T1 孤儿 fixture 根治（M4-1 #6 终局）**：App bundle repo 路径写腿全集 = **restore + undo 两法**（归因勘误：M5-1「defer 输给迟到 write-behind」错位——真残写源 = undo 法 post-test 2s debounce 写，M6-2 VALIDATION :60 排除项直证 undo 到顶照写）；`RasterEditFaceTests` 双法改 `tempFixtureCopy`（DepthMaskEditingTests verbatim 同款 helper + UUID tempDirectory）+ `loadRaster(at:)` URL 孪生；repo fixture 路径只读 + 一行防御性孤儿清扫；全套轮毕 `find Tests/Fixtures -name "*.lra"` 零命中为常态门。
- **T2 batch apply 12 字段携带（M6-2 挂账 #2 终局）**：`SessionBatchApplier` 既有档臂捕获 **12 文档级 optional 全带**（七 additive `provenance`/`rawOverrides`/`displayTransform`/`versions`/`activeVersionID`/`aiProvenance`/`filmRecord` + 五元数据 `rating`/`flag`/`colorLabel`/`keywords`/`note`——原挂账清单漏列五元数据，产线写腿 = MetadataService 五 set* 点）；pristine 臂缺省 nil 零漂移；process 分支条件盖章纪律零触（禁 `?? .current` 维持）。
- **全套 `--all` 确认轮终值**：**3848/24/0**（exit 0 + 0 MEMFAIL + 七 bundle 全 8G 门内 2099s；对账 = 3841 M6-4 实测 + 2 修批 + 5 本批〔T2 +4 / T4 +1〕精确；贴线族 IOP 7560 / IOPParity 7242 门内）；轮毕孤儿复扫零命中（T1 终证）；正本 = `phases/m6-5-ledger-clearing/M6-5-01-{SUMMARY,DECISIONS}.md`（40 项终局对表在 SUMMARY §五）+ `evidence/t9-all-run.log`。**执行批事故登记（I-1，LESSONS 候选）**：test-direct.sh 前置 = `xcodebuild build-for-testing`（脚本不含构建步）——漏步 = 陈旧二进制假绿（类计数差/方法过滤 0/0/0 为暴露信号）；测试命令序列 = build-for-testing → test-direct.sh。

### M6-6 架构增量（2026-10-16，M6-6-01 执行批——FEATURE-MAP parity 门约定正本；M6 milestone closed）

- **parity 门形态（裁决⑥兑现）**：`Scripts/parity-audit.py`（stdlib-only，zh-audit 同型 CLI）六断言 = A1 行结构（6 列 + id 形 `FEAT-(SHELL|LIB|EDT|ADJ|DEV|GEO|NODE|MASK|DRT|EXP|AI|OWN)-\d{2}` + 12 域节标题在位）/ A2 id 唯一（只取 id 单元格）/ A3 词表（Source 三词 ∧ Status 六词精确匹配）+ D2 状态证据规则机检半边（Delivered 带 ≥1 指针 / Missing 带 note / V2·Parked·OOS 带 doc: 锚——锚内容人工走查）/ A4 证据存在性（`src:` 无条件 + `:line` 界核验〔仅当去线号后路径存在才按行号解读〕；`doc:` 条件机检 = `.work/` 根存在才检；`gui-acceptance/` 与 `phases/*/evidence/` 恒 format-only）/ A5 引用链接性（扫 `.work/gsd/REQUIREMENTS.md` + `.work/gsd/ROADMAP.md` + `AGENTS.md` 的 `FEAT-` id 须在册；文件缺席 = 显式 skip 注记）/ A6 生成块新鲜度两态（空占位只检 marker；填充后须与内存重算逐字节一致）。模式 = `--check/--report/--write/--self-test` + `--checklist`/`--tree-root` 注入缝（公开树分支确定性可测——self-test 红绿 golden 含 `.work/` 缺席例）。ci.yml `parity` job（ubuntu-latest / 5min / 裸 python3）纯追加。**本地 red-line battery 引用形 = `uv run python3 Scripts/parity-audit.py --check` exit 0**。
- **checklist 双正本分工**：对账正本 = **repo 树 `docs/parity-checklist.md`**（CI 可见、全英文公开树纪律、134 rows / 12 域 / 六状态词表 Delivered·Partial·Missing·V2·Parked·OOS〔EXR 归 V2 不入 OOS——F2 勘误〕）；研究正本 = `.work/gsd/research/ALCEDO-FEATURE-MAP.md`（330 行正文零改写，头注指针段）。**`FEAT-` id 唯一 mint 点在 checklist**，id 稳定不重编号；维护纪律 = 「whoever lands a feature updates its row in the same commit」（LightCraft 同款）；状态判定 = 账面优先序（REQUIREMENTS → STATE → VALIDATION → AGENTS，不重跑验收）；证据指针两级（`src:` 机检 / `doc:` 公开树 format-only——路径字符串公开、内容不公开的知情申报在 checklist 头注）。
- **生成块（A6 载体）**：`<!-- parity:summary -->`（12 域×6 态矩阵）+ `<!-- parity:gaps -->`（Missing→V2→Parked→OOS→Partial 序、域码字母序；**首轮 17 行 ≥10 一次性 AC 已过，常驻门不检行数**——全绿后可合法缩到 0 行）；手改行后忘 `--write` = A6 stale 红门。
- **N-1 三键登记（M6-5 挂账②提前清偿，偏差登记 = VALIDATION §四.2 晨审可翻）**：`mcp_launcher_done_writes %lld` / `mcp_launcher_exit_code %lld` / `mcp_launcher_status_running %lld` 尾块纯插入（51+/0-）；`zh-audit --check` PASS 前后恒定 + catalog 1926→1929；断言 5 键集 30→30（三新键经 `INTERP_PREFIX_RE` 动态族覆盖，V16 限定口径不变——V17 候选〔M6-5 挂账③〕移交注记随之指向机检硬化批）。
- **终值**：全套 `--all` **`TOTAL|3848/24/0|` 2131s exit 0**（ΔN = 0 精确；0 MEMFAIL；七 bundle 全 8G 门内，峰值 IOP 7456 / IOPParity 7254 皆 ±3% 带内；段和 = TOTAL 机核通过）；transcript = `phases/m6-6-feature-parity/all-run-m66-01.log`。执行期事件 = appex 残留 "Lightamer Dev" CMS 签名与 ad-hoc 父不匹配（环境签名债，盘上强签后增量 build-for-testing 绿；LESSONS L081）。
- **M6 milestone closed**：M6-0..M6-6 七 phase 全闭环；收口正本 = `phases/m6-6-feature-parity/M6-6-VALIDATION.md`（`milestone_closeout: M6`；六 phase 终态汇编 + 六裁决兑现表 + 编排偏差登记〔裁决⑥「第一个 plan」→ 互操作先行 + N-1 提前清偿〕+ LightCraft 方法论铭谢〔零代码移植零 NOTICE〕+ 挂账单一清单六项移交：Manual-Only 19 行 → GUI 批 / V17 → 机检硬化批 / V2 九项+留置五项 → V2 站 / charter 挂账〔smart albums、挑片、watched folders、SAM CoreML、ALCE-02〕/ 编排偏差 / 瘦身手术触发确认——主会话专属）。

### V2-Maintenance 架构增量（2026-10-16 起，V2M 波次执行批约定正本）

- **D-1 快照修法范式（V2M-01 T1）**：面板 binding get **禁穿热观察读取**——`snapshotParams`/`snapshotRecord` 存储属性快照 + `updateInstance` 钩子兑现 + 四刷新点（init / view 级 `.onChange(of: instance)` seam〔挂 `content(_ model:)` 非 nil 作用域〕/ solve 回填 `refreshSnapshotFromChain` / `commitStrengthDrag` 尾 **live 值臂**〔竞争窗读面连续，onChange 终态兜底〕）； Film/Drt 孪生三分裁定 = 「健康」不改（`effectiveFilm/DrtRecord` = 已物化数组尾扫零 JSONDecoder，与 ColorMatch「每读线性扫 + 每读解码」不同构——**无实测证据不预防性重写**）。
- **D-2 RAW 9 automatic 收紧裁定（V2M-01 T2，`5567b56c`）**：视口绿染根因 = **CI 色管理转换 × v9 CoreML 输出**（unmanaged v9≈v8 平衡、working-space 转换后 v9 G/R≈3.87 毒 vs v8 1.065 净——bisect transcript = `evidence/V2M-01/d2-bisect/`）；裁定 = `resolveDecoderVersion` `.automatic` 臂**恒 v8**（纯函数缝零 `.metal`；switch 自家 `DecoderRequest` 枚举非 CIRAW 穷举——RAW 10 零编译破缺），v9 只经显式 `.forceV9` 可达；三面回归钉 = 供件级 spread<0.5（`input/RAW/GREENCAST-7RM5.ARW` untracked 域，缺席 XCTSkip）+ `testResolveDecoderVersionMatrix`（automatic 三臂全 v8，零供件依赖恒执行）+ `testRAW9OptIn` 重钉。**遗留面（用户显式行为，不改）**：forceV9 显式档仍产出毒化平面（面板有 readout/downgrade 提示）；**X-Trans/Quad-Bayer 机身的 v9 demosaic+denoise 质量面随收紧一并退场**（STACK.md 载 X-Trans 恰是 RAW 9 ML 引擎收益最大处——富士机身当前实际无可用 v9 路径）；重入口条件 = 探针 WS 腿对 v9 能力机身转中性后恢复 opt-in（TRANSCRIPT 重启条件节）；既往 automatic 文档重载后 decodeParamsHash 一次性漂移（重渲非数据损失）。
- **D-5 toast 数值键先例（V2M-01 T5）**：调用点 `Int((x * 100).rounded())` 对齐在册 `%lld` 变体（xcstrings 零改动；「补 %lf 变体」翻案不行使——`%lf` 渲染「12.340000%」反劣化）；半分界 = Foundation `.rounded()` 远离零舍入。D-3 单一换图通道 `switchCurrent(to:)` + `loadCurrentImage` pre-write await 后 `Task.isCancelled` 检查点（竞态结构性封闭）+ D-4 `.sheet(item:)` payload（arm 点构造计数随 item 进闭包，结构性排除呈现快照陈旧读）同批在册。
- **波 1 终值（V2M-01）**：全套 `--all` **`TOTAL|3851/35/0|`** 三路同值（2047s/2045s/2053s）；ΔN₁ = +3（T1 +2 / T2 +1）；skip 35 = 基线 24 + 真 RAW 供件域漂移 11（先于批 5.5h 环境漂移非静默跳过——供件备料后收敛）；GrainTests 定向轮单 flake = GPU 状态序漂移（M2-7-3 先例族，净轮取值）。
- **zh-audit V17 门（V2M-02 T1）**：`Scripts/zh-audit.py` 断言 6 = specifier 深检——插值键（`String(localized:)` 族 + **Text 族**〔`Text("K \(…)"` 单行 + `Text(` 行尾续行形〕）的实参静态类型逐参有序比对目录变体 spec 序（长度不等或任一位错配 = MISMATCH；映射表 = 全 Int 族→`%lld` / Float|Double→`%lf` / String→`%@`；`%@` 须显式入 spec 正则字符类）。供给面收窄禁误报：带注解 let/var + func/init 参数 + 字面量 + `Int(…)` 包装形 + 深度 0 算式传播；成员链/闭包参数/跨文件/泛型 = EXEMPT 报告不判。self-test golden 八例（spec 错配红 / Text 无变体红 / 跨行绿 / 豁免例 / 位置错配红 / Int32 绿 / Float=Double 绿 / 注释免疫）。**后续批红线电池引用形 = `uv run python3 Scripts/zh-audit.py --check` PASS（ABSENT/MISMATCH 零命中）+ `--self-test` PASS**。活体清偿：`catalog_session_remove_confirm_body %@` 尾块纯插入（SidebarView.swift:262 裸键运行时 face 根治，调用点零改）；首跑分诊红面 = 1 ABSENT（该键）+ 0 MISMATCH，D-5 键 `toast_hdr_merge_done` 绿例亲证（函数参数→`Int(…rounded())`→`%lld`）。
- **PATCH-LIVEPLANE 收口（V2M-02 T3）**：E5 两残差实修——①eager 释放 = `LayerEditingState.select`（异值切层）+ `EditorAreaView.onChange(of: loadedImageURL)` 双释放点（`releaseLivePatchState` 对空 face no-op）；②在飞竞态 = `commitRasterMask` 函数头捕获 `armedImageURL` + segment 腿**装载门**（当下 image/layer ≠ armed → 不装 face 不调度，mask 腿照落捕获身份——换栈后 `commitLayerEdit` 安全 no-op）+ stamp 恒取 armed（杜绝「stamp 用切换后 URL」污染）。App +2（`testLayerSelectReleasesHeldPatchFace` / `testMidFlightImageSwitchLeavesNoSessionFace`〔6000² upsample 放宽 bake await 窗保切换确定性落窗内〕）。
- **EXPORT-PRESET-01 预设层（V2M-02 T5）**：`ExportPresetStore`（NamingTemplateStore 同款纪律——注入式 defaults / 全量替换写回 / 三内置不入库 / 坏 JSON 降空库）+ **捕获面 = REQUIREMENTS :401 清单精确**（格式/质量/位深/sizing/metadataOn/embedICC/命名模板），`collisionPolicy` 与 `gainMapHDR` **结构性不入捕获面**（`ExportPresetPanelFace` 值面不带——M-5/M3-1-03 KD-1 会话态裁定编译期钉死）；套用投影 = 纯函数 `ExportPresetProjector.project`（悬挂模板引用 → `NamingTemplateStore.builtIns[0].pattern` 回落；variant validate 失败 → 整面回落 defaultFace 禁半落地）。**UserDefaults 新键 = `export.presets`（本批唯一新键；既有 `export.*` 六键零触）**；zh 键族 `export_preset_*` 七键尾块纯插入。App +4（`ExportPresetTests`，Project.swift + BUNDLE-MAP 同批登记 + tuist generate 恒末位）。
- **RELEASE-DIRECT-INJECT 防御脚本（V2M-02 T4）**：`Scripts/make-release-direct-launchable.sh`（零产线 diff）——embed PackageProduct frameworks + ad-hoc 内层先签 + 直启探针（进程存活 + 主窗）。**余量盘点定案：当前依赖图债形态已消**（新 Release 构建无 PackageFrameworks 目录——WebP 静态内联进 LightamerCore（nm 零 webp 未定义符号），探针零修复 PASS）；脚本 = SPM/Tuist 链接代际回摆时的自愈通道 + make-dmg 先行跑则分发产物自足。
- **V2M-02 终值**：全套 `--all` **`TOTAL|3857/35/0|` 2047s exit 0**（对账链 3851〔波 1〕+ ΔN₂ 6 = 3857 精确；ΔN₂ = T3 +2 + T5 +4，App bundle 818→824；0 fail / 0 MEMFAIL / 七 bundle 8G 门内，IOPParity 8111 贴线带内；段和闭合）；skip 35 = 波 1 同值（供件域未变）。**批内新缺陷登记（D-6/D-7/D-8，只登记不修）**：D-6 = 重开项目态编辑器不可用 + 主线程 SwiftUI layout churn spin（error 级候选，修复批入口，证据 = `gui-acceptance/v2m/` t2 证据族）；D-7 = 导入停滞复现（M2-9 F-1 家族疑似）；D-8 = legacy 会话建立通道不可达。T2 走查批通道受阻收兵（四 V2M 行 Blocked-Channel 保持，D-4「快照上移」返工预案不触发——通道不可达 ≠ 复验见 0，返工裁定上报 orchestrator）。**两波合并 red_lines 总核对 PASS**（`git diff 7b252db1..HEAD`：metal/IOP/sidecar/封存面零 diff；xcstrings 136+/0- 纯插入；runModal 零；LocalizationValue 插值禁形代码行零命中〔:2069 注释豁免锚〕；UserDefaults 唯一新键 `export.presets`）。
- **V2/Maintenance phase closed（VALIDATION signed 2026-10-16）**：签核正本 = `phases/v2-maintenance/V2M-VALIDATION.md`（`status: validated` + `nyquist_compliant: true`；夜间授权先例 D-07-3-T5-1 晨审可推翻）；双波双路独立验收 PASS / 0 error + 0 minor 零实质分歧，**终态全套 `TOTAL|3857/35/0|`**（对账链 3848+3+6 = 3857 精确）；执行链 = 波 1 `54124c7e..bb16f8c4` + 波 2 `2ba1d1fe..08f9ebc4`；挂账单一清单六项移交（D-6〔error 级候选，重开项目态编辑器 AttributeGraph spin，修复批首项〕/D-7/D-8 → 下一修复批；波 1 屏面四项 + D-4 复验 → D-6 修复后走查批硬义务；forceV9/X-Trans 登记面〔上两行已落〕；RAW 供件 11 skip 用户侧备料收敛；flake 两笔〔GrainTests / ProcessVersionCarrierTests〕台账延续；V17 位置参数变体键名假红安全方向 + N5〔`String(localized:defaultValue:)` 位置占位断言盲区〕/N6〔孤儿 bake 文件缝〕备查）；make-dmg.sh embed 缺口翻账建议 = 分发批并入 `make-release-direct-launchable.sh` 或前置调用。
- **FIX2-01 修复批 II（2026-10-16 夜间执行批；正本 = `phases/fix2-defects/FIX2-01-{SUMMARY,DECISIONS}.md`）**：**终值全套 `--all` = `TOTAL|3860/35/0|`（2070s exit 0 零 MEMFAIL；ΔN=+3 = T2 合流测试，T1/T3 零码；skip 35 口径维持）**。①**D-6 探针定罪范式（H1 写点假说三连证伪 → H2 框架共犯坐实）**：判别探针两段形（View 面 `_printChanges` + App/Scene 面手动桩打 stderr）实测 28k+ 重估零属性变更、深层七视图仅挂载一次——环 = macOS 27 SwiftUI 菜单/焦点更新自持环（`makeMainMenu ↔ updateMainMenu ↔ invalidateProperties ↔ updatePreferences`，焦点 store `PropertyList.prependValue` 逐 pass 无去重）；**持续条件 = threshold 形**（空载面摘 `.inspector`/双 safeAreaInset 任一饿死；编辑器面三段内容任摘一段饿死；焦点写点摘除/`List→LazyVStack`/动画摘除全不饿死）；**修法不可落地上报**（无 app 写点；`.inspector` 改形 C1 实测换不来编辑器面 spin 消失，行使收益零）——D-6 BLOCKED 三选一上报（降级+立项/research 复审/回退 macOS 27）；**范式沉淀：churn 类缺陷先探针定罪写点再动手，`@self`-only 重估流 = 无写点信号（勿盲改修饰符）**。②**D-7 合流范式（`ImportProgressCoalescer`）**：进度类 actor→main 投递一律「单槽 latest-wins + fire-and-forget drain 调度、handler 零 await」（O(file) 主队列风暴 = 主线程 churn 下的饥饿源）+ 终态 bypass-supersede（ swallowed terminal = 进度条永挂换形）+ main actor 单飞保序；完成尾 watchdog os Logger 一行惯例。③**D-8 翻案核销（零码）**：legacy 会话真腿 = 打开会话… ⌘⇧O / Open Recent（配方正本 = `gui-acceptance/v2m/MANIFEST.md` FIX2-01 节；会话双击进编辑器须 `cliclick dc:`——System Events 双 `click at` 不成双击）；核销口径 = 翻案（走查错腿 + inert-by-design）非「已修复」。④**新观察**：导入零行间歇（11 轮 3 中，per-file insert 静默失败〔勘误 2026-10-16 FIX2 双路验收：机理标签错误——DB 法证坐实行恒落库，真实失效面 = **grid 页刷新迟到**（fresh reload 自愈）；正本 = `FIX2-VALIDATION.md` §勘误〕、lastError=nil、completion 照常——独立待研）+ IOP NLMeans 窗外 crash flake（隔离重跑绿，台账延续）。⑤红线族全 PASS（029f84bc..HEAD：metal/IOP/sidecar/封存面零 diff；xcstrings 零；UserDefaults 零新键；Project.swift 恰 T2 测试一行）。
- **FIX2 修复批 II closed（VALIDATION signed 2026-10-16）**：签核正本 = `phases/fix2-defects/FIX2-VALIDATION.md`（`status: validated` + `nyquist_compliant: true`；夜间授权先例 D-07-3-T5-1 晨审可推翻）；**双路 zcode 独立验收 PASS / 0 error 产物缺陷零实质分歧，终态全套 `TOTAL|3860/35/0|` 三路同值**（执行方 2070s + 双路 2079s/2059s；对账链 3857+3 = 3860 精确）；执行链 = `da99ea2f..2427670e`（4 commits）。**裁定终态**：T2 D-7 = 合流+watchdog 交付（Coalescer 先例即上 ② 行）；T1 D-6 = 探针定罪（H2 = macOS 27 SwiftUI 菜单/焦点更新机制在特定树形〔重树 + `.inspector` 分栏宿主 + 三段内容〕下不收敛——框架缺陷面与 app 树形合谋，非任意树触发）+ 修法不可落地 BLOCKED，**双路同判三选一 = ①接受降级 + gate=false 壳减树/窗口内容拆分专项立项**（③回退与 Lock-early 冲突；②research 复审并入专项首步）；T3 D-8 = 零码翻案核销（即上 ③ 行）；T5 = 四波走查收口（可走行全走 + Blocked 族三源如实登记）。**批内勘误落账（D-FIX2-4）**：「导入零行间歇 = per-file insert 静默失败」被双路 DB 法证证伪——真实失效面 = **grid 页刷新迟到**（行恒落库、WAL 在案、fresh reload 自愈），六处标签勘误随 VALIDATION 批落（TODO/AGENTS④/MANIFEST×2/DECISIONS/GOAL-STATE）；**D-6 workaround 已补记用户可及文档**（README Known Issues 节：窗口遮挡/最小化即断环〔CPU 归零〕，一次点击即恢复编辑）。挂账单一清单六项 = `FIX2-VALIDATION.md` §挂账（D-6 专项 charter / T2 窄边界 `cancelAndClear()` + flushTerminal-vs-tail 竞态 / 点击表型双输入通道对照 / 探针缝 `exit(0)` 兜底 / 导入零行间歇〔grid 刷新迟到族〕备查——后三类下批顺手/备查）。
- **M7-1 D-6 壳专项 closed（定罪批，VALIDATION signed 2026-10-16）**：签核正本 = `phases/m7-1-shell/M7-1-VALIDATION.md`（`status: validated` + `nyquist_compliant: true` + `batch_form: conviction`；夜间授权先例晨审可推翻）；**本 phase 交付 = D-6 终局定性（零产线 ΔN=0，基线 3860/35/0 逐值维持）**。执行批停手（`5323df67`）+ 零共享上下文独立复核（`bddaba6b`，`M7-1-HALT-REVIEW.md` 234 行）双眼定案：**FIX2 全部饿死证据证据级 dissolved**——C1×3+C2×4+E×3 十轮 transcript 全落遮挡/发射静默窗伪象；E 系三连「编辑器面摘段饿死」从未进编辑器面（transcript `phase=library` 全程，AX 腿未生效）；FIX2 自留样本 c2-long 263/789/1850 恰为满速活环被记作「28% 残底噪」（静默相陷阱正本）。**终局行为模型 = 可见性门控开关 × 振幅随面重**（遮 0% / 置前 ≤1s 点火**无需点击** / 显期间自持；图库 ~30% / 编辑器 80-100% / legacy 0.1%；⌘H 全覆盖，遮挡对编辑器 spin 同样压 0）。**缓解裁定 = upstream-only 为主**（FB 稿补强三点已落：遮挡门控确定性复现 / C1/C2 三独立复现树形证伪 / 跨日稳定 spin 配方；提交动作 = 用户手动 + 27.1 release notes 监测入巡检；E 系证据无效一事不入 FB）+ README workaround 语义勘正（置前即恢复 ≤1s 无需点击，替换「一次点击」测量伪象表述）；**SHELL 族翻账**：SHELL-01/03 不行使（价值证伪，parked）；SHELL-02 窗拆挂条件账（触发 = E 系硬化复测复活，半日级必做前置含 phase=editor transcript 机检）；SHELL-04 in-flight；SHELL-05 复走行集改挂「功能态常驻」走查批（churn 在场判读口径）；挂账⑥降级待研（三轮全净 = 因果假说反向旁证）；T3 不行使 + AX 桥限制留档（D-M7-1-01-2）。**测量纪律新条（LESSONS L082，后续 churn/探针类批次强制）**：churn 读数必须 **frontmost + 环符号双验，遮态读数无效**（可见窗语境 CPU ≈ 0.0% 即伪象哨兵——活态带 26-36%/80-100% 与 0.0% 完全分离，读数后即时对带复核）；sample 符号一律记**总量**（跨行求和）禁最大单支，「N hits」区分 grep 行数 vs 计数总和；编辑器面探针必须 transcript `phase=editor` 机检后采数；静默相哨兵（2 tick 发射 → 长静默 → 复燃沿 = 遮挡双相签名，勿把复燃沿当「残底噪」）。next = M7-2（MCP O1 检索与状态读）。

### M7-2 架构增量（2026-10-16，M7-2-01 执行批——MCP O1 检索/状态读约定正本）

- **三工具面（MCP2-01..03）**：`search_photos`（EXIF 两段 keyset / CLIP top-K 256 / 全文 bm25 top-K 500）+ `get_history`（sidecar 只读投影）+ `get_state`（六字段组一次性快照），全 `readOnlyHint:true` + 注册缺省 writer 要求（SearchStateToolset.swift grep 机检 `requiresWriter` 零命中）。registry 封闭集 20→**23**（union 快照显式改已用讫——M7-3/M7-5 接棒继续显式改 `McpFinalSnapshotTests.swift`，串行禁并行）。
- **`McpSearchStateContext`（D-M7-2-9 终形）**：全 provider closure optional 缺省 nil（既有构造零 diff + typed 诚实臂）；`library` = **ProjectFileStore 直携 + projectDirectory（E-1）**——锚 = **包所在目录**（`deletingLastPathComponent()`，ImageLinker `.projectRelative` 追加语义；fix `20997721`：沿 match_color provider 的文件 URL 直传是错的，match_color 未爆仅因其行走 absolute kind）；`LibraryStore` 需要处用公开 `init(store:)` 现场派生（零 Core diff）。**F-6 结构纪律**：SearchStateToolset 源对 WorkspaceModel/PipeCoordinator/ExportState/LibraryProjectController 零直接引用（grep 门）——@Observable 态全部经 liveState 闭包内 MainActor.run hop（测试 fixture 内 `dispatchPrecondition` 可执行判定钉死）。
- **EXIF 两段走法（E-2 终形）**：`searchPage`（主段，锚定 seek 对 NULL-key 行永假）→ `searchNullTail`（NULL tier，`image_path` seek）；cursor payload = PhotoProjection 同形 `{k,d,p,v}` + **`s` segment 字段**（缺失 = typed invalidParams——list_photos token 跨工具拒，R-3）；尾段续页 anchor 手搭 `.int(nil)+imagePath`（R-2，advanceTail 同款）；翻段规则六条落 `advanceMain` 头注（翻段完全可从页形推导——锚定主段页永不看见 NULL 行）。窄投影九字段全有列支撑（images.id/image_path/filename/dir/capture_date/rating/flag/color_label/has_edits），「无列支撑缺席」条款零行使。
- **`McpToolError.modelUnavailable` 15→16**（D-M7-2-6）：`SemanticSearchError.modelUnavailable`/`dimensionMismatch` 双映射（message 区分 missing/mismatched）+ **`AIWorkerClientError` 四案同归该族**（F-3——message 携 worker 案名与细节；internalError 会把资产/进程缺席误导成我方 bug）；16 值穷举测试钉死。
- **get_history**：双地址制（digits → LibraryStore 现场派生 + ImageLinker / relPath → sessionPair membership 校验）；`ExportRenderer.readDocument` 零新读法；五臂 kind 纯函数（paste→drt→film→structure→param 优先序——双载荷项判 paste，N-5）；versions meta only（`chainStack == nil` = active；chain 归 M7-3 `list_versions`）；**F-5 截断语义** = `min(全量, 500)` 保留最新端 + position/itemCount 恒真值 + 显式 `truncated` 旗标；author 恒 null（M7-4 MCP2-09 前向占位）；无 sidecar = pristine 诚实面（position −1，非错误）。
- **get_state**：`McpSearchStateLiveSnapshot`{project, workspace, editor, tasks, server}（project 也走 liveState 缝——plan T3 action 3）；control = probe verdict（**读作 DATA**——search/get_history 零 probe 触，get_state 恰一读）+ writeCallCount（headless/只读 face = null 诚实面，F-4②）；tasks = ExportQueue 六态计数；server hostMode/readOnly = 宿主派生事实。**已知边界**：GUI workspace face 的 filter/selectedIDs 恒 null（per-window LibraryPhaseState 自 app 级装配点不可达——DECISIONS §2.8 申报；真值须新汇集缝）。
- **只读臂（T4）**：heldByOther 臂 emitConnectGuidance 后 `openReadOnly()`（锁免/schema `stored==current` 守卫/写断路器原样）→ `headlessProjectStore` 同载体；失败 = nil seam + log 禁 exit；stdio EOF `try? close()` 自然覆盖（N-7 checkpointTruncate typed 失败被吞 = 既有语义）。**F-2 甲判据通道**：DEBUG + `LIGHTAMER_MCP_ENDPOINT_DIR` 域内只读 http face 写独立 `mcp-endpoint-readonly.json`（Release 零触；writer 文件零触碰）——两进程测试过线亲调工具（SC「照常服务」机器可判）。
- **`McpEndpointFile` additive 六面**：write/read/remove ↔ writeReadOnly/readReadOnly/removeReadOnly（共享 writePayload/readPayload 私有体——R-1：discovery 逻辑禁二写）；`McpEndpointPaths.readonlyJsonURL` 单源拼写。
- **EmbeddedState 第五缝（F-4①）**：searchState 随 box 存取——`startEmbeddedIfPreferenceEnabled` 存 / `startEmbeddedServer` on-leg 读出透传；缺此缝 = GUI off→on toggle 三工具静默缺席。宿主装配点对账 = 六调用点/四缝 + EmbeddedState 内部缝。
- **键族登记**：`mcp_tool_desc_search_photos`/`_get_history`/`_get_state` 三键（xcstrings 尾块纯插入 zh-only 形；zh-audit 双 PASS）；UserDefaults 零新增。
- **测试**：`McpSearchStateToolsetTests` 17 法（APP 域，BUNDLE-MAP 一行）：parity golden 三臂（EXIF 双向 + NULL 行翻段可达 / CLIP mock / 全文直调恒等）+ cursor 机制负测族 + 错误臂五件 + worker 族映射 + get_history golden（五 kind + 双载荷 + 截断方向 + pristine）+ get_state 双判据 + 16 值穷举 + 只读豁免面 + 两进程只读臂过线。union 快照显式改全点位 = DECISIONS §1。
- **ΔN 终值 = +17**（全套 `3877/35/0`——3860 基线 + 17；skip 35 口径维持）。
- **M7-2 closed（双路验收 VALIDATION signed 2026-10-17）**：签核正本 = `phases/m7-2-mcp-o1/M7-2-VALIDATION.md`（`status: validated` + `nyquist_compliant: true`；夜间授权先例晨审可推翻）；执行链 `9f69775b..8f12ffcc`（7 commits 含 fix `20997721` projectDirectory 目录锚——T5 golden 抓获回注闭环）。**双路独立验收 PASS / 0 error + 2 minor 零实质分歧**（omp 制度路由双 zcode 独立眼替代——第一路重 parity 深审 + stdio 端到端 `M7-2-01-ACCEPTANCE.md`，第二路重五面语义审计 + HTTP 两进程复现 `M7-2-01-ACCEPTANCE-2ND.md`；2 minor = F-AC-1 FilterSQL 快照未交付未申报 + F-AC-2 headless probe 未透传，双路独立确认属实，登记缺口级）；**三路全套同值 `TOTAL|3877/35/0|`**（exit 0 零 MEMFAIL 七 bundle 8G 门内）；端到端证据面 = 真 MCP stdio 23 工具 + HTTP 两进程三证 + EXIF 翻段链 ≡ 独立 SQL 参照（两路独立）。**挂账单一清单六项** = VALIDATION §挂账（①F-AC-1 → M7-3 补快照或追记申报 ②F-AC-2 → M7-3 一行透传或追记 ③N2-1 pristine 补 `truncated` 键 + N2-3 fulltext 窄竞态 typed 抛 + N2-4 requestFailed 显式测试 → M7-3 顺路；N2-2 project 字段不对称 → M7-6 文档句 ④CLIP 10s 贴线待万级库实测 ⑤match_color provider projectDirectory 同病 → M7-4 顺路勘正 ⑥auto 分类器后置 + cursor 跨调用稳定性边界）；next = M7-3（MCP O2+O3，MCP2-04..07）。

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
