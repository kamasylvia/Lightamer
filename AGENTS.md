<!-- GSD:project-start source:PROJECT.md -->

## Phase 执行模型（2026-10-21 瘦身批改写；制度变更史见 git log 与各专节）

- **执行**：general-purpose subagent executor——按 plan 文件任务序推进（read_first → action → 验收标准逐条核验）、每任务独立提交（Conventional Commits，只 add 相关文件）、重活 `caffeinate -dis` 包裹；测试标准命令 = `Scripts/test-direct.sh`（直启宿主；全套 `--all` 须 orchestrator 预批 + machine-guard）。
- **验收**：双路 zcode 独立验收（串行，机器级单重活制）→ **omp 二次验收**（严格串行独占，computer-use）——详见「全阶段 omp 复审」与「机器级并发上限」两节。
- **编排**：omp/巡检运行期不重复启动同一 plan；暂停与门控见「暂停机制」节；人工只处理 GOAL-STATE「阻塞（需人工）」章节登记的事项。
- （史注：2026-09-20 版「执行 = omp」制度自 2026-10-16 起 omp 配额阻塞由 zcode subagent 替代；2026-10-19 起 omp 转任全阶段复审眼。）

## 全阶段 omp 复审（2026-10-19 用户指令，强制）

每个 GSD 阶段产物定稿后，由 omp 做一轮**独立复审**（config.toml [gsd] `stage_review_by_omp = true`）：research 定稿后（assumptions/覆盖面/证据抽查）→ plan 定稿后（可执行性/坐标/红线；即 `plan_review_by_omp` 的全阶段化）→ execute 闭环后（omp 二次验收 = `dual_acceptance` 原制度，zcode PASS 后**严格串行**）→ validate/VALIDATION 后（复核）。复审形态分三档（2026-10-19 用户纠偏）：research/plan = **纯文本读评**（明令禁启 computer-use；需 GUI 验证的内容让渡 execute/validate 道），可并行；execute 二次验收 = computer-use 形态，严格串行（原 dual_acceptance 硬约束不变）；validate 复核 = **computer-use 类**（实机抽验职责），串行且持 GUI 互斥——与一切 GUI 驱动活动（其它 omp 实例/executor 探针窗/验收走查）互斥排程，两个并发 = 禁止。复审调 omp -p --thinking max，key = Infisical `OPENCODE_GO_KEY` + 代理 env 10809，nohup+disown；结论落 `<产物名>-REVIEW-OMP.md` / `-ACCEPTANCE-OMP.md`，blocking 级回注该阶段修复轮。omp 用后 `px --stop`。

## 资源监控（2026-09-29 用户指令，强制）

开发过程中**持续监控 Lightamer 相关进程**（GUI app 与 test-direct.sh 直启测试宿主在活动监视器里同名，都叫 Lightamer——按命令行/父进程区分，处置线不同，见下）：

- **GUI app 触发线（不变）**：内存占用 >3G，或 CPU 占用持续异常偏高（非构建态 >50% 持续分钟级）→ **立刻介入**：`sample <pid> 3` 采栈定位 + 向 orchestrator/用户上报处置，不得放任。
- **测试宿主口径（M2-4-0 落地 + SPIKE 门修订，2026-09-30）**：全套回归经 `Scripts/test-direct.sh --all` 分 7 个域 bundle 跑（一条命令，逐 bundle 独立宿主进程），峰值 RSS 由脚本按 `/usr/bin/time -l` ru_maxrss（内核精确口径）机检 MEMFAIL，**运行门 = 8G**（`RSS_LIMIT_MB=8192`）。原 <3G 门经 SPIKE（commit `70e09e5`）**证伪为错定门槛**：by-design GB 级重测（100MP golden/parity 族，验证对象 = 100MP float32 平面）单类自峰 TilingOverlap 7865 / HDR 5913 / QuickLook 4589MB + ~1.4G 框架分页一次性地板，<3G 数学不可达、与 bundle 划分无关，真实跨测残留仅 0.18-2.4MB/test（证据正本 = `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-SPIKE.md`）。**全套 `--all` 轮仍须 orchestrator 批准 + 运行中保持监视**（现另有 MEMFAIL 机检兜底，>8G 或内存压力转红仍立即 kill）；定向单 bundle 轮（`--bundle <name>`）可常跑，机检兜底；贴线 bundle（IOP 7654 / IOPParity 5788）连续 MEMFAIL 先查重测顺序漂移（±3% 方差，SPIKE 注记）。旧单宿主 2165 连跑已废（历史事件：10.4G 未响应 / 7.5G 用户强杀）。
- 巡检 cron 每次运行附带查一眼 Lightamer 进程资源（`ps aux | grep -i lightamer`）。

## 机器级并发上限（2026-10-20 用户指令，强制——三次 watchdog 重启根因修复）

**根因**（2026-10-18 16:53 / 10-19 13:38 / 10-20 20:48 三次重启 + 10-20 15:34 WindowServer watchdog 杀 GUI 会话）：16GB 机器上并行重活（双路验收各自构建 + 独立 DerivedData〔21 容器 22GB〕+ 测试宿主 8GB 峰 + GUI 实例 + zg 索引/omp）→ 内存耗尽、交换落在 90% 满的 Data 卷 → 系统守护饥饿（configd IPMonitorQueue 60s 无响应 = watchdog 终止原因）→ 用户态 watchdog 杀 WindowServer / 内核 watchdog 硬重启（无 panic 文件、日志零持久化为其签名）。**规则**：全机同时至多一个重活进程族；双路验收**串行**；一切重活前过 `Scripts/machine-guard.sh`（G1-G4 四门，`--wait` 轮询）；**构建产物交接**（executor 构建一次 → `BUILD-HANDOFF.txt` → lane 消费，禁重建）——撤回「每 lane 独立 DerivedData」处方；lane 收口清自建容器/worktree；DerivedData >8GB 巡检告警；px 代理每 omp 会话一开一关禁反复切换。config.toml [gsd] `machine_single_heavy = true`。

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

### 提交与 Issue（继承全局规则；2026-10-20 用户裁「点头」补口径）
- **产品面提交**（App/、LightamerCore/、LightamerIOP/、Tests/、Scripts/、Resources/、docs/ 等源码/构建/文档产物）：提交前确保有对应 GitHub issue，commit message 末尾用 `fixes #NN` / `closes #NN` / `refs #NN` 关联；已推送的 commit 在 issue 描述里反向引用。
- **内部规划/账本提交免关联**：`.work/gsd/**`（规划/研究/账本/验收文档）、`.work/audits/**`、`research/*-NOTES.md` 调研笔记、`.work/config.toml` 等 orchestrator 面提交**不带 issue ref**——它们是流水线内部工作产物，非产品变更。
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

### 参考项目（2026-10-21 瘦身：条目 = 路径/许可/定位/正本指针；增量细节在各 NOTES 正本）

- **Darktable**（`/Volumes/UNITEK/Documents/Development/darktable`；GPL-3.0，同许可复制可用）— iop 算法 / OpenCL kernel→Metal 移植 / pixelpipe / 色彩管理源码参考。上游增量登记（2026-10-13 spektrafilm 族 16 commits = M8 FSIM 质量参考）见 `.work/gsd/phases/m3-2-fsim-research/RESEARCH-NOTES.md`。
- **Alcedo Studio**（`/Volumes/UNITEK/Documents/Development/AlcedoStudio`；GPL-3.0，同许可复制可用）— **功能对标正本**（UI/QML `alcedo_studio/src/ui/`、解码算子 `src/decoders/`、实机对照 `/Applications/AlcedoStudio.app`）。parity 正本 = `.work/gsd/research/ALCEDO-PARITY-2026-10.md`。
- **yiyin / 壹印**（`/Volumes/UNITEK/Documents/Development/yiyin`；GPL-3.0，自维护分叉 > 上游 ggchivalrous）— 印框/水印面板功能对齐参考。
- **Lumen RAW**（`/Volumes/UNITEK/Documents/Development/lumen-raw`；MIT，可复制带归属）— 五采纳先例（深度/Mertens/全景/超分 UX/推理隔离）；1.7.0/2.0.x 增量 + UQ-LU1..LU5 正本 = `.work/gsd/research/LUMEN-RAW-NOTES.md`。
- **SpektraLab**（`/Volumes/UNITEK/Documents/Development/SpektraLab`；GPL-3.0 代码 + CC BY-SA 4.0 资产）— 胶片模拟/宽容度 UX/CLI+MCP 三前门参考（M3/M8 基建来源）。正本 = `.work/gsd/research/SPEKTRALAB-NOTES.md`。
- **LightCraft**（`/Volumes/UNITEK/Documents/Development/lightcraft`；MIT OR Apache-2.0）— LR clean-room Rust 复刻：MCP 单写者锁/UltraHDR 纯 Rust/量化对标方法论。正本 = `.work/gsd/research/LIGHTCRAFT-NOTES.md`。
- **RawLab**（`/Volumes/UNITEK/Documents/Development/RawLab`；GPL-3.0，同许可复制可用）— 跨四平台 C++ 核 RAW 显影器（AI 辅助高频迭代）。UQ-R1..R6 正本 = `research/RAWLAB-NOTES.md`。

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
- **UserDefaults 键登记**：`library.import.mode` / `library.import.rememberMode` / `library.import.rawExtensions`（ImportDefaults，全量替换语义 + reset）+ `library.recentProjects`（LibraryProjectController，dedupe-move-front 上限 10 + 死路径清扫）+ `lut.library.root`（M2-5-3，LutLibraryStore.libraryRootKey 单源拼写；IOP init 直读 `.standard`，AppPreferences 只承载登记/reset 面——空/缺 = 默认根 `~/Library/Application Support/Lightamer/LUTs/`）+ **导出记忆键族六键（M2-9-04/05）**：`export.lastDirectory`（OQ-3 落点跨会话记忆；picker 即时写回 + run 写回 + 首用回落首图目录）+ `export.jpegQuality` / `export.heicQuality` / `export.avifQuality` / `export.webpQuality`（OQ-10 四格式各一键，Double 0...1，typed 读 + isFinite + qualityRange 域校验，0.0 = 真记忆非未存）+ `export.namingTemplates`（OQ-9 命名模板预设 JSON 数组，NamingTemplateStore 注入式 defaults，三内置不入库）+ **yiyin sheet 比例两键（M3-1-02）**：`yiyin.sheet.widthRatio` / `yiyin.sheet.heightRatio`（Double 0...1，YiyinSheetMetrics 注入式 defaults——body 零直读；typed 容错域外/异型 = 键视为缺席回落现状 420×560；仅拖拽松手写入，quantize3 三位小数）+ **`lensfun.autoApply`（LENS-02 T2，Bool 默认 false；LensAutoApplySetting 单源拼写 + typed 缺席=false；读法注入式 LensModule.autoApplyReader 恰一消费点——面板/设置 body 零直读；LENS 批唯一新应用级键）**。

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

## 架构不变量索引（2026-10-21 瘦身批：正本 = `.work/ARCHITECTURE-ARCHIVE.md`，逐字存档）

> **用法**：触达特定子系统前，先查 ARCHIVE 对应小节（每节 = 该批「约定正本」：不变量/键族/封存面/红线）。
> 本索引只列**跨批不变量速查**与里程碑一页表。

### 跨批不变量速查（违者即错，细节见 ARCHIVE 对应节）

- **FIX2③**：`LibraryProjectController.swift` 零 diff（连续六波亲证）。
- **封存面清单**（M7-6 收口登记，全批零 diff 义务）：DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal / DrtEotf / ExportQueueContract / 六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）/ NodeGraphCommand / sidecar schema（LightamerSidecar）/ HistoryStack / HistoryHash / PipelineDocument（Core）/ V50Order / GradeCatalog（NodeOwnershipCatalog）。
- **D-H1**：滑杆 begin/setLive/end 三段提交语义（live 值不进 discrete commit；end 才提交）。
- **process version**（M6-2）：改观感 = 新 process 号 + 旧号冻结；per-photo 载体，RenderProcess 单源。
- **L013**：跨进程身份哈希一律 StableHash（FNV-1a 64，decimal string 入 JSON）；Swift Hasher 与未排序 JSON 禁入。
- **L057**：面板/对话框呈现禁 `runModal` 族，唯一缝 = PanelPresentation.present。
- **disable-not-unmount**：agent 控制期/隐藏态 UI 用 `.disabled` 不条件卸载（M7-5 三纪律）。
- **机器级单重活**：重活前必过 `Scripts/machine-guard.sh`；双路验收串行；构建产物交接不重建（`9ca2f326`）。
- **全阶段 omp 复审**：research/plan/execute/validate 产物定稿后各过一轮 omp 独立复审（并发三档：文本并行 / execute 串行 / validate computer-use 独占）。
- **V50Order add-only**；sidecar schema 现行 **v11**（schemaVersionCurrent 单源）；UserDefaults 键族登记制。
- **GPL-3.0 同许可复制纪律**（2026-10-20 切换）：GPL 上游可移植——保留原版权声明 + 许可证文本 + 标注修改；NOTICE 同步。
- **新代码禁形**：`String.LocalizationValue("prefix_\(x)")` 插值构键；`String(localized:)` 动态键须显式 switch 返回静态键（V14/L058）。

### 里程碑一页表（正本 = ARCHIVE 对应节）

| 批 | 约定要义（关键词） |
|---|---|
| Phase 2 增量 | Library 目录惯例 / .lalb 形态 / 真身边界 / 剥离门 / UserDefaults 键族登记制 |
| M2-2 | LibrarySchema/ProjectFileStore/LibraryStore/.lalb WAL/剥离门/LibraryLegacyGate/UserDefaults 键族 |
| M2-5 | Grade 件族/LUT 库键升级（根相对）/shared holder/可配根/内置集 seeder/性能探针惯例 |
| M2-6 | DrtRecord/DRT 尾段策略/尾平面格式/DRT 持久化四件/DRT 面板/HDR 视口四态/Post 四件/键族 |
| M2-7 | Follow Edges 熔断/V2 换锚史/探针方法论/xcstrings 批次追加/测试宿主清理教训 |
| M2-8 | sidecar v7 双键/version_ref DDL/swap 单路径/Copy Adjustments/走查双缺陷（sheet 注入/Toast） |
| M2-9 | ExportVariant 载体面/.drt 重放缝/EXIF Software 座位/命名模板/尺寸解析单源/DrtOutputColorSpace/M2 检查器 |
| M3-1 | LUT 编码维/yiyin sheet 拖拽/denoise 拖动降档/冲突档选择器/peak-ICC/zh 提取器 V15 硬化 |
| M3-3 | FilmRecord/光谱不可达注记/film sub-run 缝/FilmSolveCache/置位 op/golden 门/Film 面板/Film 卡/键族 |
| M3-4 | 精确锚/Placement v2/descriptor 运行时/宽容度面板/InspectorView 挂载 |
| M4-1 | RAW/TIFF 路由单源/PixelPipe 输入分派/raster 默认 record/HDR 视口/导入类别掩码/srgbPiecewise/RGC-off |
| M5-2 | runMertensLeg 流式腿/StagedSet/分离式 dilate/域判别 |
| M5-3 | PANO 全景合成约定正本 |
| M6-2 | per-photo process version（sidecar v10） |
| M6-3 | ALCE-03 UltraHDR（CI `.hdrImage` 全服务路） |
| M6-4 | 图库 stacks + AI 分割蒙版（Vision 三能力/logit-gain 换锚） |
| M6-5 | 挂账清算 40 项 |
| M6-6 | FEATURE-MAP parity 门（parity-checklist 136 行 + parity-audit.py） |
| V2-Maintenance | V2M 波次约定正本 |
| M7-1 | D-6 停手批（可见性门控 churn 定罪）+ 探针协议硬化正本 |
| M7-2 | MCP O1 三工具（search_photos/get_history/get_state） |
| M7-4 | MCP O4 + note 归属（sidecar v11）+ requiresControl |
| M7-5 | turn-taking（AgentControlCoordinator/活动卡/Stop-resume） |
| M7-6 | MCP O2/O3 + 封存面清单 + M7 站收口 |
| L057 | 面板呈现约定（runModal 禁入产线正本） |
| F0'-prod | 壳交接翻转（NSApplicationDelegate + NSHostingView）/SwiftUI 壳退役/机器级单重活/D-6 根除（正本 `.work/gsd/phases/f0prime-prod/` + ARCHIVE F0/F0' spike 节） |
| LENS-01 | Lensfun 收口（三态互斥探测/系数快照/投影四型/数据钉版/isNeutral 含 lensfun 态/reloadDefaults 三缝接线）（正本 `.work/gsd/phases/lens-01-lensfun/`） |
| R12 | 修复批（M-1 CullingView pair 切换 pane 装载/.task id 身份；标记链 write face；F2-4 Settings repoint；R2 卫生 43 处）（正本 `.work/gsd/phases/r12-repairs/`） |

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
