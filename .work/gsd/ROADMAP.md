# Roadmap: Lightamer

**Created:** 2026-08-03
**Phases:** 13
**Granularity:** fine
**Mode:** standard (Horizontal Layers)

A macOS-native (Swift 6 + SwiftUI + Metal 3 + Core Image RAW) **Alcedo Studio clone, macOS-exclusive, RAW 9 decoding** (**2026-09-27 project redefinition, user directive** — supersedes both the Darktable full-iop baseline and the C1 Session workflow). UI and feature surface fully mimic Alcedo Studio; dt-exclusive delivered features stay in code but are disabled by default (feature flags). Phases below (Milestone 2 draft) are ordered by dependency; Milestone 1 (Phases 1-16) is retained below as historical record of delivered assets.

## Milestone 2: Alcedo V1 — 2026-09-27 重定义【M2-0 细化完成 2026-09-27，待用户签核开工】

> 规格正本 = `.work/gsd/research/ALCEDO-FEATURE-MAP.md`（301 行，HEAD `34241d0b`：UI 逐屏/18 项调整封闭目录含 JSON key 与默认值/节点图命令级语义/蒙版参数/DRT 45 参数/项目文件全 DDL/导出 recipe/AI 侧车）。已交付资产延续：pixelpipe/39 iop/Layers/sidecar/Presets/LUT/Export 队列/MCP server/测试基线（1881/11skip/0fail）。

### M2 签核决定点（✅ 已签核：2026-09-27 用户「M2 全按推荐走」——D1-D6 全按推荐生效）

- **D1 tone mapping 归属**：Alcedo 把 filmic/sigmoid 的职能整体移到终端 DRT 节点（用户不可编辑 tone spline，只露预设）。Lightamer 的 filmicrgb/sigmoid/agx 三个 iop **v1 禁用**（进 M2-1 矩阵），parity 后评估以「DRT method 扩展」身份回归。**推荐 = 是**。
- **D2 降噪归属**：Alcedo 零降噪（封闭目录 18 项无 NR）。dt 降噪三件（denoiseprofile/nlmeans/bilateral）**v1 禁用**，降噪由 **RAW 9 解码层承担**（CIRAW 融合降噪 = kCIInputNoiseReductionAmount 族参数，best-in-class）；bilateral/highpass 收进 Detail 分组作 Lightamer 增强。**推荐 = 是**。
- **D3 图库存储**：**SQLite 单项目文件**复用（`.lalb` 类单文件包 = db + manifest，语义照抄 Alcedo：Sleeve/Folder/Filter 相册骨架 + Image 物化搜索列 + mini-git EditCommit/VersionRef + 材质化缓存），不引入 DuckDB（新依赖违约束；SC#3 已实证 SQLite 1M 行 p95 12ms）。**推荐 = 是**。
- **D4 调色域**：Alcedo Grade 在 **ACEScc** 域调色（LGG/curve 语义锚定）。Lightamer 管线 = linear Rec2020 float32；Grade 节点内部做 AP1/ACEScc 色适应往返（Develop 输出→ACEScc 调色→DRT 输入），含 CAT02 创意白平衡（默认 ≈6000K = identity）。**推荐 = 跟随 Alcedo**（保证语义与默认值一致）。
- **D5 蒙版面**：Alcedo 出货只有 Radial + LinearGradient（Brush 已实现未出货）；Nitro 集 = Brush/Linear/Radial/Luminance/Color Range/AI Subject + Follow Edges。**v1 蒙版集 = Alcedo 出货面 + Brush + Nitro 的 Luminance/Color Range/AI Subject/Follow Edges**（内核复用 Phase 6 既有 kernel，UI 按 Alcedo Mask Groups 呈现）；dt 式 JzCzhz 参数化 UI 不单独暴露（内核可作 color-range 实现）。**推荐 = 是**。
- **D6 独有增强收纳**：Lightamer 独有项（降噪增强/channelmixer 系/velvia/monochrome/liquify/retouch/ashift/hazeremoval/yiyin/MCP）全部保留，UI 归入七页签的对应分组（Detail/高级），不破坏 Alcedo IA。**推荐 = 是**。

### M2 Phase 表

| # | Phase | 内容（测绘锚点） | 依赖 |
|---|---|---|---|
| M2-0 | 测绘与规格 | ✅ 闭环（ALCEDO-FEATURE-MAP.md + 本表 + REQUIREMENTS M2 族登记 + D1-D6 用户签核全按推荐） | — |
| M2-1 | dt 面 feature-flag 禁用 | 39 iop 审计→启用/禁用矩阵（D1/D2/D6 裁决落地）；ModuleRegistry flag 默认面收窄；预设/MCP 默认面收窄；回归全绿 | M2-0 |
| M2-2 | 图库与项目模型（Alcedo 方式） | SQLite 单项目文件包（D3）；相册骨架 Sleeve/Folder/Filter（智能相册）；文件夹导入引用式 + RAW-only 过滤；Image 物化搜索列 + EXIF 词法检索（`iso800`/`f2.8`/`35mm` AND 组合，~20ms@2万张 对标）；Sessions/Catalogs UI 剥离 | M2-0 |
| M2-3 | UI 壳重设计（Alcedo 克隆） | 双工作区（Library/Editor）；图库 = 网格 + Album Inspector（四分组 + Activity view + Overview 卡）+ 全局搜索三合一（EXIF/CLIP/全文）；编辑器 = 左工具轨（History/Versions/Nodes）+ 中视口（FIT/缩放读出/双级 busy）+ 胶片条 + 右示波器（直方图/波形）+ 七页签调整栈（Tone/Look/LUT/Display Transform/Geometry/RAW Decode/Mask）；设置页族；**视觉验收 = computer-use 开 `/Applications/AlcedoStudio.app` 真机对照截图（2026-09-27 用户授权，UAT 自答先例同款）** | M2-2 |
| M2-4 | 节点编辑模型 | PipelineDocument 线性链（Develop→Grade×N→DRT）；命令集 AddClean/Remove+Bridge/Reconnect/Rename/SetEnabled/SetMix/InsertFromJson（undo 可复原）；每节点有序调整列表+enabled+mix+删除锁（grade.primary 锁）；蒙版 Grade-owned 绑定；sidecar/项目 schema 扩展；节点面板 UI（SwiftUI/Metal 自绘替代 QuickQanava） | M2-1, M2-3 |
| M2-5 | Color Grade 控件集 | 18 项封闭目录参数对齐（CAT02 WB identity 5999.99K / exposure ±16 / contrast 中灰邻域语义新图默认 +15 / White/Black/Shadows/Highlights ±100 / curve 单位方形 / HLS 8-bin+range 45° / saturation 0-4 / vibrance ±100 / LGG 三轮 disc-strength-color_offset-luma_offset / LMT CUBE / tint ±100）；LGG trackball UI（新）；产品默认 look（+1.5EV/+15/1.3）与 identity 语义；D4 ACEScc 调色域落地；LUT 目录语义 = 递归扫描 + 子目录树显示 + 设置可配根目录（M2GRADE-05/06，2026-09-27 用户指令，改进超 Alcedo 平铺单层） | M2-4 |
| M2-6 | DRT：ACES 2.0 + OpenDRT | DRT 节点（scene 终点，Post 四件套 Clarity/Sharpen/Halation/FilmGrain 在 DRT 后全图一次）；OpenDRT 预设三件套（Look 7 + Tonescale 15 + Creative White 6；45 detailed 参数 editor-owned 序列化）；ACES 2.0（Limiting Space 七选 + reference gamut compression）；Encoding Space/EOTF 联动（Rec709→BT.1886/G2.2、P3-D65→G2.2/PQ、Rec2020→PQ/HLG…）+ Peak 100-1000 nits；HDR 判定（EOTF∈{ST2084,HLG}）驱动 EDR 预览与导出；filmic/sigmoid/agx 按 D1 禁用 | M2-4 |
| M2-7 | 蒙版体系（Alcedo + Nitro） | Radial（center/radii/rotation/feather）+ LinearGradient（origin/normal/transition 0.2/start 1→end 0）+ Brush；mask 级 invert/opacity/enabled/锁删 + 应用序 feather→invert→opacity→clamp；图上绘制 + 手柄 overlay + Mask Groups 面板（组序=grade 序、蒙版缩略图 GPU 管线、Default Behavior 三选）；Nitro：Follow Edges（IOP-MASK-06）+ Luminance/Color Range/AI Subject（D5）；蒙版修订单调 revision + 乐观并发 | M2-4 |
| M2-8 | 版本与历史（mini-git） | EditCommit 不可变 commit 图（双亲=分支/合并）；VersionRef 命名版本（从原始态新建 + branch from current + fork from root + rename/remove）；ImageEditState 材质化缓存；永久 undo/redo + 历史事务行（操作名+参数 delta+时间）+ 崩溃恢复条 + 自动保存；Copy Adjustments 三层面板（Node/Item/Version 勾选 → Paste 新 Version；排除 RAW decode/lens/crop） | M2-2, M2-4 |
| M2-9 | 导出选项 Alcedo 化 | 格式保留原 6 格式矩阵（用户终裁；EXR/UltraHDR 维持 V2=ALCE-02/03）；尺寸四模式（Original/Long Edge/Bounds/Print+in-cm-mm+DPI+upscale cap+maximum_edge_pixels）；元数据剥离策略（location/serials/editing history 默认剥离 + 档位）；文件名模板（字段 12 种+补零序号+冲突 FAIL/REPLACE+子文件夹）；输出 ICC = 本图 DRT 编码强制联动；导出队列 UI（检查器内、四态、质量跨会话记忆）；yiyin 印框/水印终步保留适配 | M2-3 |
| M2-10 | AI 图库功能 | 本地语义：CLIP 嵌入（CoreML 档；MobileCLIP2-512/SigLIP2/Jina-768 级可选）+ ANN 检索（SQLite 向量方案执行时定）+ 自动打标（中英 label query 原型余弦 + score/margin/confident + 导入询问 Remember-choice）；远程评片：OpenAI/Anthropic 兼容（1-5 星+理由、rating=0 reasons-only、严格度/语言、prompt profile 护栏）+ AI 描述（caption+tags+scene+confidence+全文检索文档）；Keychain 存 key（zeroize）+ 强制 HTTPS；后台任务系统（对话框+栏+取消注册表）；MCP server 保留互补 | M2-2 |
| M2-11 | Performance 专项 + closeout | 原 Phase 15 PERF-01..07 按新架构重校（60fps@100MP 决战/零卡顿/RAW9 解码 500ms/懒加载/批量 apply/内存 3GB/Instruments profile）+ 全 M2 SC 终验 | M2-1..M2-10 |

**里程碑 1（Phases 1-16）= 历史记录**：交付资产延续，其 ROADMAP 文本保留在下作考古。Phase 14（MCP）已全执行完毕待 14-4 验收——验收照常派（交付面不受重定义影响），Phase 15 并入 M2-11。

Phases are ordered by dependency: foundation →
pixelpipe core → iop clusters → layers/masking → native AI masking/retouching →
session/export → yiyin/metadata → system/distribution. Every v1 requirement maps to
exactly one phase.

## Phase Overview

| # | Phase | Goal | Requirements | Success Criteria |
|---|-------|------|--------------|------------------|
| 1 | Foundation, App Skeleton & Capability Spikes | Stand up the macOS 27 app, Metal dispatch, CIRAW 9 decode, IOPModule protocol + v50_order, MTKView viewport; resolve the CIRAW 9 / 100MP Metal capability boundary | FOUND-01, FOUND-02, FOUND-03, FOUND-05, FOUND-06, FOUND-07, RAW-01, RAW-02, RAW-04, RAW-05, RAW-06 | 5 |
| 2 | Pixelpipe Core, Color Management & History Stack | The load-bearing architectural phase: per-module per-ROI cache, multi-resolution pipes, terminal trio (colorin/colorout/gamma), linear Rec2020 color pipeline, history stack + hash, Lightamer-format sidecar | FOUND-04, COLOR-01, COLOR-04, HIST-01, HIST-02, HIST-03, HIST-04, RAW-03 | 5 |
| 3 | Tone & Filmic iops | Daily-workflow tone modules + the filmicrgb scene-referred tone mapper (hardest single port — spike-validated) | IOP-TONE-01, IOP-TONE-02, IOP-TONE-03, IOP-TONE-04, IOP-TONE-05, IOP-TONE-06, IOP-TONE-07, IOP-FILM-01, IOP-FILM-02, IOP-FILM-03 | 4 |
| 4 | Geometry, Lens & Detail iops | Crop/rotate/flip/lens correction + sharpen/local-contrast/highpass/equalizer; prove ROI negotiation end-to-end | IOP-GEO-01, IOP-GEO-02, IOP-GEO-03, IOP-GEO-04, IOP-DETAIL-01, IOP-DETAIL-02, IOP-DETAIL-03, IOP-DETAIL-04 | 4 |
| 5 | Color & Denoise iops | Advanced color modules + profiled/NLMeans/bilateral denoise (raw denoise spike — second-hardest port) | IOP-COLOR-01, IOP-COLOR-02, IOP-COLOR-03, IOP-COLOR-04, IOP-COLOR-05, IOP-COLOR-06, IOP-COLOR-07, IOP-COLOR-09, IOP-DENOISE-01, IOP-DENOISE-02, IOP-DENOISE-03, IOP-DENOISE-04 | 4 |
| 6 | Layers & Masking System | Capture One adjustment layers (base + named layers, per-layer iop + mask + blend) interdependent with drawn/parametric/raster masks; liquify + retouch depend on the mask framework | LAYER-01, LAYER-02, LAYER-03, LAYER-04, LAYER-05, LAYER-06, LAYER-07, IOP-MASK-01, IOP-MASK-02, IOP-MASK-03, IOP-MASK-04, IOP-MASK-05, IOP-GEO-05, IOP-GEO-06 | 5 |
| 7 | AI Modules (Native Vision Masking & Retouching) | Native Apple Vision subject-isolation masking + frequency-separation skin retouching (no custom Core ML models), feeding AI masks into the Phase 6 layer/mask system as editable inputs | AI-01, AI-05, AI-06, AI-07 | 4 |
| 8 | HDR/Stacking & Effects iops | HDR merge, focus/average/median stacking, 32-bit float HDR pipeline, EDR display output, creative effects (vignette/grain/bloom/dehaze/watermark iop) | IOP-HDR-01, IOP-HDR-02, IOP-HDR-03, IOP-HDR-04, IOP-HDR-05, IOP-FX-01, IOP-FX-02, IOP-FX-03, IOP-FX-04, IOP-FX-05 | 4 |
| 9 | Capture One Session Management | Folder-as-session model, Capture/Crop/Output three-tier dirs, FSEvents watcher, multi-session, browse modes, copy/paste + before/after compare | SESS-01, SESS-02, SESS-03, SESS-04, SESS-05, SESS-06, HIST-05, HIST-06 | 5 |
| 10 | yiyin Border/Watermark Panel | Port yiyin (white border/EXIF overlay/date/logo/custom fonts/model-map) to native Core Image/CoreText as borders+watermark iop modules + SwiftUI panel | YIYIN-01, YIYIN-02, YIYIN-03, YIYIN-04, YIYIN-05, YIYIN-06, YIYIN-07, YIYIN-08 | 5 |
| 11 | Export Pipeline & Batch Queue | EXPORT pixelpipe, all 6 formats, multi-spec recipes, background queue with yiyin application as final step | EXP-01, EXP-02, EXP-03, EXP-04, EXP-05, EXP-06, EXP-07, EXP-08 | 5 |
| 12 | Metadata, Rating, Presets & LUT | Rating/labels/keywords, filtering/smart albums, native preset system, .cube LUT (1D/3D) as IOP-COLOR-08 module | META-01, META-02, META-03, META-04, META-05, META-06, PRES-01, PRES-02, PRES-03, PRES-04, IOP-COLOR-08 | 4 |
| 13 | System Integration & Distribution | Quick Look + Spotlight, soft proofing + multi-display ICC, gestures + drag-drop + i18n, GitHub open source + signed/notarized DMG + CI | SYS-01, SYS-02, SYS-03, SYS-04, SYS-05, DIST-01, DIST-02, DIST-03, DIST-04, COLOR-02, COLOR-03 | 4 |

## Phase Details

### Phase 1: Foundation, App Skeleton & Capability Spikes
**Goal:** Stand up the macOS 27 native app with the Metal dispatch framework, CIRAW 9
RAW decode, the `IOPModule` protocol + `v50_order` table, and an MTKView viewport
blitting a decoded RAW. Resolve the CIRAW 9 capability boundary and 100MP Metal
performance vertebra here — these determine v1 iop scope.
**Success Criteria**:
1. App launches on macOS 27 and opens a CR3/NEF/ARW RAW via CIRAW 9 (`decoderVersion = .version9`, gated behind `#available`), displaying the decoded image (unprocessed) in the MTKView viewport.
2. A trivial Metal compute pass-through kernel executes end-to-end (buffer in → buffer out), proving the `MetalContext` dispatch framework (device, library, `dispatch2D`, PSO caching, function-constants).
3. The `IOPModule` protocol and `v50_order` order table (`iop_order.swift`) compile, and a no-op pixelpipe chain (single pass-through piece) runs without error through the `EditorMTKView` NSViewRepresentable bridge.
4. CIRAW 9 capability spike documented (which demosaic/denoise/lens features it covers natively vs. which need Metal), and a 100MP GFX100S RAF decodes + displays without jetsman/memory failure (the architectural vertebra).
5. EXIF/IPTC/XMP (camera, lens, focal length, aperture, shutter, ISO, GPS, capture time) reads correctly via ImageIO; non-RAW formats (JPEG/HEIC/PNG/WebP/TIFF/PSD-flat) and Adobe DNG also decode.
**Requirements:** FOUND-01, FOUND-02, FOUND-03, FOUND-05, FOUND-06, FOUND-07, RAW-01, RAW-02, RAW-04, RAW-05, RAW-06
**Notes:** This is the architectural vertebra — every later phase plugs into this skeleton. Foundation decisions are expensive to reverse and are locked here (per research): macOS 27 floor, linear Rec2020 scene-referred working space, float32 RGBA premultiplied-alpha pipe buffers, `v50_order` module ordering, Metal-first pipe with CIRAW strictly as decoder. **Spikes (research-flagged, run in this phase):** (a) CIRAW 9 vs RAW 8 capability boundary — determines whether the demosaic-algorithm menu is a v1 hard requirement (large Metal port) or can defer to Apple-default; (b) 100MP Metal performance — confirm 60fps target is feasible at zoom/pan on a GFX100S file before committing the iop list; (c) preliminary filmicrgb port feasibility (full validation in Phase 3); (d) preliminary raw denoise profiling (full validation in Phase 5). Stand up the golden-image color harness scaffolding here (full harness lands in Phase 2 before any algorithm port). Risks: CIRAW-1/2/3, METAL-3/4, SOLO-1.

### Phase 2: Pixelpipe Core, Color Management & History Stack
**Goal:** The load-bearing architectural phase. Port the Darktable recursive pixelpipe
with per-module per-ROI cache + hash-hit fast path, multi-resolution pipes
(FULL/PREVIEW/THUMBNAIL/EXPORT), the terminal trio (colorin/colorout/gamma) for correct
display color, the history stack with stable identity tuple + history hash, and
Lightamer-format sidecar persistence.
**Success Criteria**:
1. Opening a RAW displays correct color on screen: camera RGB → linear Rec2020 working → display profile (from `NSScreen.colorSpace`) via the colorin/colorout/gamma terminal trio, verified against a known-neutral target.
2. Dragging a parameter invalidates only modules at or after the changed module's `iop_order`; upstream modules (rawprepare/demosaic/lens) hit the per-module per-ROI cache — verifiable via cache-hit logging (the 60fps mechanism).
3. History stack persists to a Lightamer-own-format sidecar (NOT Darktable-binary-compatible) and round-trips: write → close → reopen → identical params and rendered image.
4. Multi-resolution pixelpipe instantiated (FULL at zoom ROI, PREVIEW at ~1080px always-current, THUMBNAIL, EXPORT); tiling fallback scaffolding in place for buffers exceeding GPU working set.
5. History hash detects drift between in-memory and on-disk sidecar; the golden-image color harness (torture images: deep-shadow Bayer, saturated LED, X-Trans RAF, 100MP GFX, HDR stack) is live and gating before any Phase 3+ algorithm port.
**Requirements:** FOUND-04, COLOR-01, COLOR-04, HIST-01, HIST-02, HIST-03, HIST-04, RAW-03
**Notes:** The hardest pure-architecture phase. The recursive `processRec` + cache-hit fast path is the single most important pattern (Darktable `pixelpipe_hb.c:1838/1893`). Mirror Darktable's stable history identity `(op, multi_priority, multi_name, iop_order, blendop_version)` + per-module `version` int + mask-form versioning by id — getting this subtly wrong causes silent mask invalidation later (NDE-1/2/3/6). Lock `Codable & Hashable` params encoding strategy before writing the second module. CIRAW is strictly the decode layer here — never the engine. Risks: CIRAW-4/5, METAL-1/2/4/5/7, NDE-1..4/6, COLOR-1/2, PERF-1/2, SOLO-2/3/5.

### Phase 3: Tone & Filmic iops
**Goal:** Deliver the daily-workflow tone modules (exposure, white balance, tonecurve,
shadow/highlight, contrast, levels, tone equalizer) plus the filmicrgb scene-referred
tone mapper — the hardest single Darktable port (~2000 lines of scene-linear math) —
and its variants (sigmoid, other filmic). These close the core daily editing loop.
**Success Criteria**:
1. Exposure, white balance (with eyedropper sampling), tonecurve (per-channel RGB), levels, contrast, shadow/highlight recovery, and tone equalizer all render correctly against Darktable golden-image references at pinned params.
2. filmicrgb Metal port matches Darktable reference output within perceptual tolerance on the torture-image set (spike-validated — this is the decisive scene-referred port).
3. Slider drag on any tone module holds 60fps on a 100MP image at viewport resolution through the preview pipe (per-module cache + debounce working).
4. sigmoid and other filmic variants produce correct scene-referred tone mapping without highlight clipping; modules declare correct input/output colorspaces for auto-inserted conversions.
**Requirements:** IOP-TONE-01, IOP-TONE-02, IOP-TONE-03, IOP-TONE-04, IOP-TONE-05, IOP-TONE-06, IOP-TONE-07, IOP-FILM-01, IOP-FILM-02, IOP-FILM-03
**Notes:** filmicrgb is research's flagged "hardest single port" — the early spike (Phase 1 preliminary, full validation here) decides whether it lands in v1. Every module ships a `.swift` + `.metal` file pair and passes its golden test before merge (SOLO-2). All modules operate in linear Rec2020 scene-referred (COLOR-1). Risks: METAL-6/7, NDE-3, COLOR-1/2, PERF-5.

### Phase 4: Geometry, Lens & Detail iops
**Goal:** Geometry (crop, rotate/perspective, lens correction, flip/orientation) and
detail (sharpen, local contrast, highpass/soften, equalizer/detail enhancement) modules.
These prove the ROI negotiation (`modifyROIOut`/`modifyROIIn`) end-to-end and cover the
remaining daily-workflow table-stakes.
**Success Criteria**:
1. Crop with aspect-ratio lock + rotation micro-adjust, rotate/perspective correction (with auto-detect), and flip/orientation all behave correctly with live preview.
2. Lens correction (geometric distortion, lateral CA, vignette) applies via embedded DNG opcodes + manual sliders; CIRAW coverage gaps are filled by a Metal warp shader (Lensfun-XML-data-read-only or self-profile — open decision resolved in this phase).
3. Sharpen (USM + Gaussian/Laplacian variants), local contrast (clarity equivalent), highpass/soften, and equalizer/detail enhancement render against golden-image references.
4. ROI negotiation correctly handles crop's output shrink (forward pass) and sharpen/blur's wider input requirement (backward pass) — the minimal-region processing works.
**Requirements:** IOP-GEO-01, IOP-GEO-02, IOP-GEO-03, IOP-GEO-04, IOP-DETAIL-01, IOP-DETAIL-02, IOP-DETAIL-03, IOP-DETAIL-04
**Notes:** Lens-correction scope (Lensfun C++ link vs XML-data-only + Metal warp) is an open decision resolved here — affects v1 dependency surface (research recommends XML-data-only for v1). liquify (IOP-GEO-05) and retouch (IOP-GEO-06) are deferred to Phase 6 — they depend on the mask framework. Risks: CIRAW-3 (lens coverage holes), METAL-6/7, PERF-5.

### Phase 5: Color & Denoise iops
**Goal:** Advanced color modules (colorbalancergb, color calibration, channel mixer,
color zones, monochrome/B&W, vibrance, velvia, color contrast/curves) and the denoise
family (profiled raw denoise — the second-hardest port — NLMeans, bilateral/surface
blur, hot pixels/dark frame/chromatic noise).
**Success Criteria**:
1. colorbalancergb, color calibration (channel-mixer successor), channel mixer, color zones (per-hue/sat/lum zones), monochrome/B&W (with color-filter emulation), velvia, vibrance, and color contrast/correction curves all match Darktable references.
2. Profiled raw denoise (Metal port of Darktable `denoise (profiled)`, `denoiseprofile.cl`) matches Darktable reference within tolerance; per-camera noise profile is loaded from EXIF/metadata (spike validates the profiling approach — second-hardest port).
3. NLMeans, bilateral/surface blur, and hot-pixel/dark-frame/chromatic-noise reduction all reduce noise without detail loss on the torture images (deep-shadow Bayer, X-Trans RAF, 100MP GFX).
4. All color and denoise modules maintain 60fps drag on the preview pipe; tiling fallback engages when a denoise module's working set exceeds GPU memory on 100MP.
**Requirements:** IOP-COLOR-01, IOP-COLOR-02, IOP-COLOR-03, IOP-COLOR-04, IOP-COLOR-05, IOP-COLOR-06, IOP-COLOR-07, IOP-COLOR-09, IOP-DENOISE-01, IOP-DENOISE-02, IOP-DENOISE-03, IOP-DENOISE-04
**Notes:** IOP-COLOR-08 (.cube LUT) is grouped with the Presets phase (Phase 12) since it is the same feature as PRES-03. Raw denoise profiling is research's flagged spike (Phase 1 preliminary, full validation here) — decides whether per-camera noise profiles land in v1 or defer. Tiling fallback becomes load-bearing here (NLMeans/denoise on 100MP). Risks: METAL-1/6/7, NDE-3, COLOR-1/2/6, PERF-1/5.

### Phase 6: Layers & Masking System
**Goal:** The Capture One adjustment-layer architecture — the fundamental differentiator
from Darktable's per-iop masks. Base layer + named adjustment layers, each carrying
independent iop params + a mask + blend mode, coexisting with global iops in the same
pixelpipe. Masking (drawn/parametric/raster + combine ops) is interdependent with layers
and ships together. liquify and retouch depend on the mask framework and land here.
**Success Criteria**:
1. Background base layer + multiple named adjustment layers operate independently — each layer's exposure/color/sharpen iops apply only within that layer's scope (same iop can have different params per layer).
2. Drawn mask (brush, polygon, ellipse, path, bezier), parametric mask (luminance/color range with feather/invert/blur), raster mask (baked from other masks), and mask-combining operations (union/difference/intersection, mask groups) all functional and applicable to any adjustment layer.
3. PS-style blend modes (normal, multiply, screen, overlay, soft light, hard light, color dodge, burn, difference, hue, saturation, color, luminosity) composite correctly with per-layer opacity.
4. liquify (portrait distortion) and retouch (heal/clone brush) modules work — both architecturally depend on the mask/distortion framework.
5. Full layer stack (layers + per-layer iop params + masks + blend modes + opacity + visibility/reorder/duplicate/merge/group) persists to sidecar and round-trips; the architecture cleanly coexists global-iop and per-layer adjustments in one pixelpipe.
**Requirements:** LAYER-01, LAYER-02, LAYER-03, LAYER-04, LAYER-05, LAYER-06, LAYER-07, IOP-MASK-01, IOP-MASK-02, IOP-MASK-03, IOP-MASK-04, IOP-MASK-05, IOP-GEO-05, IOP-GEO-06
**Notes:** The largest architectural phase. Layers + masking are interdependent (research key finding) and must be designed into the pixelpipe from Phase 2 — they cannot be bolted on. This is the fundamental departure from Darktable's global-pipe + per-iop-mask model: the layer stack is the organizing mechanism for local adjustments. Mask versioning by stable id (not ordinal) and the history identity tuple from Phase 2 are what make this survive reorder/refactor (NDE-1). Risks: NDE-1/3, METAL-8, PERF-2.

### Phase 7: AI Modules (Native Vision Masking & Retouching)【追色已移出至 V2，2026-09-22 用户指令】
**Goal:** Ship the subset of AI masking/retouching that Apple's **native** Vision/Core
Image frameworks implement directly — with no custom-trained Core ML models. That means
subject isolation via `VNGenerateForegroundInstanceMaskRequest` (AI-01) and frequency-
separation skin retouching built from Vision face/segmentation landmarks + Core Image
filters (AI-05) — with every AI mask feeding into the Phase 6 layer/mask system as an
editable input (AI-06) rather than as a black box (AI-07). All detection runs natively
on the Apple Silicon Neural Engine — no third-party ML models, no network calls.
**Success Criteria**:
1. Subject lifting (people/animals/food/generic objects, class-agnostic) via `VNGenerateForegroundInstanceMaskRequest` generates a correct mask on any demosaiced RAW image (not limited to iPhone ProRAW), and the macOS 27 WWDC26 enhancements (iterative tap/scribble/lasso refinement) are usable interactively.
2. AI frequency-separation retouching (high-pass/low-pass decomposition on the skin region located by Vision face landmarks + person segmentation, blurred via Core Image) produces natural-looking skin that preserves pores/edges — no plastic look; implemented purely from public Vision/Core Image APIs, no custom model.
3. AI masks integrate as layer/parametric mask inputs — an AI-generated mask can be baked to a raster mask (IOP-MASK-03) or applied directly as a parametric mask (IOP-MASK-02) on any Phase 6 adjustment layer (AI-06).
4. AI masks are editable, not black-box — manual edge refinement, feather, invert, and combine with other masks (IOP-MASK-04 operations) all work on a baked AI mask (AI-07).
5. Layer A subject masking and all skin-retouch Vision requests run locally on the Neural Engine (offline, no network); layer B (GenerateIterativeSegmentationRequest, tap-to-segment refinement) requires a one-time model download on first use, gated by assetStatus UI with layer A as the always-available fallback (D-07-CONTEXT-1); latency on a 100MP image is acceptable for interactive use (cache result so re-edit does not re-run Vision).
**Requirements:** AI-01, AI-05, AI-06, AI-07
**Notes:** Depends on Phase 6 (Layers & Masking) — AI masks are consumed by the layer/mask system, so this phase ships after it. **Native-only scope decision:** research confirmed Apple's native AI capability boundary on macOS 27 — `VNGenerateForegroundInstanceMaskRequest` (subject) and Vision landmarks + Core Image filters (frequency-separation skin) are the only capabilities achievable without a custom-trained Core ML model. AI-02 (sky), AI-03 (portrait body-parts), AI-04 (generic semantic seg) were dropped from v1 because they have no public native multi-class API: `CIRAWFilter.semanticSegmentationSkyMatteImage` and `AVSemanticSegmentationMatte` only read iPhone-captured/ProRAW embedded mattes, and arbitrary-RAW versions would each need a custom DeepLab/face-parsing model — those now ship as AIV2-03/04/05 in the v2 section. AI-01 is implemented via `VNGenerateForegroundInstanceMaskRequest` (available macOS 14+, enhanced in macOS 27); AI-05 uses `VNFaceLandmarks2D` + `VNGeneratePersonSegmentationRequest` for skin-region location and a Metal/Core Image compute pass for the frequency separation. AI masks are NOT black-box — on generation they bake to an editable raster mask (Phase 6 IOP-MASK-03) and from there inherit all Phase 6 mask-edit affordances (AI-07); the baked mask is what is versioned in the history hash (NDE-1). Keep a pluggable segmentation interface so a higher-fidelity custom-model backend can be swapped in later (v2 AIV2 items) without rewriting AI-06/07 integration. Risks: PERF-1 (Neural Engine scheduling vs. Metal pipe), NDE-1/3.

### Phase 8: HDR/Stacking & Effects iops
**Goal:** HDR merge (bracketed exposures, alignment, de-ghosting), focus stacking,
average/median stacking for noise reduction, 32-bit float HDR pipeline continuation in
linear Rec2020, HDR/EDR display output, and the creative effects cluster (vignette,
grain, bloom/glow, dehaze, watermark/text overlay as an iop layer distinct from the
yiyin final-output watermark).
**Success Criteria**:
1. HDR merge of bracketed exposures produces an aligned, de-ghosted 32-bit float HDR image in linear Rec2020 that can continue through the normal edit pipeline.
2. Focus stacking and average/median stacking produce clean combined output with correct alignment.
3. HDR/EDR display output renders real high dynamic range on EDR-capable displays (`CAMetalLayer.wantsExtendedDynamicRangeContent`, headroom above 1.0 treated correctly — not as a different color space).
4. vignette, grain, bloom/glow, dehaze, and watermark/text-overlay iops render correctly and match references; watermark iop (order 77) is distinct from the yiyin final-export watermark.
**Requirements:** IOP-HDR-01, IOP-HDR-02, IOP-HDR-03, IOP-HDR-04, IOP-HDR-05, IOP-FX-01, IOP-FX-02, IOP-FX-03, IOP-FX-04, IOP-FX-05
**Notes:** 32-bit float TIFF/EXR/HIF source reading is already enabled by RAW-03 (Phase 2). EDR display work carries COLOR-4 risk (calibration, tone curve headroom) — test on both XDR and external HDR. HDR export depth (HEIC 10-bit gain map / AVIF 10/12-bit PQ/HLG) is an open decision; EDR preview ships here, full HDR export can lean on Phase 11. Risks: COLOR-4/5, METAL-1.

### Phase 9: Capture One Session Management
**Goal:** The Capture One Session workflow — folder-as-session, automatic
Capture/Crop/Output three-tier subdirectories, sidecar co-location, multi-session
switching with recent list, FSEvents folder watching with resilient out-of-band
handling, and browse modes (grid/single/culling). Adjustment copy/paste and before/after
compare (the remaining history-stack workflow features) land here.
**Success Criteria**:
1. Selecting a folder makes it a Session; Capture (originals + sidecars)/Crop (working copies)/Output (exports) subdirectories are auto-created and maintained (Capture One convention).
2. FSEvents watcher detects Finder add/move/delete and syncs the session view; orphaned sidecars (`.xmp` with no original) and original-orphaned sidecars are handled gracefully with a reconcile action — never a hard fail.
3. Multi-session switching with a recent-sessions list works with no state leakage between sessions (explicit session-scope teardown of pixelpipe + caches).
4. Browse modes functional: thumbnail grid, single large image, culling compare (multi-image side-by-side).
5. Adjustment copy/paste (full or partial params, batch apply across multi-select) and before/after compare (split, snapshot point, temporary-hold-to-view-original) work.
6. Session-level index database (rebuildable derived cache, `.cosessiondb`-isomorphic): indexes sidecars (params hash / rating / layer-stack summary) + thumbnails. Source of truth stays the sidecars — deleting the DB is lossless and triggers a rebuild. Batch apply (SESS-05/HIST-05) runs as ONE index transaction + a bulk sidecar write queue — the lazy-rendering foundation for PERF-07 (万张 apply ≤5s).
**Requirements:** SESS-01, SESS-02, SESS-03, SESS-04, SESS-05, SESS-06, SESS-07, HIST-05, HIST-06
**Notes:** Do NOT rely solely on FSEvents (coalescing, 4096-path limit, rename loss — Watchexec publicly called choosing FSEvents "a mistake"); use it as a hint and reconcile with a directory scan on focus. Treat the session folder as mutable and untrusted — re-derive state on access; the same principle makes the index DB rebuildable-from-sidecars (never authoritative). HIST-05 (copy/paste) and HIST-06 (before/after) are workflow features layered on the Phase 2 history stack. Risks: SESS-1..5, NDE-5, PERF-2/3, UI-1/3.

### Phase 10: yiyin Border/Watermark Panel
**Goal:** Port the yiyin (壹印) border/watermark capability to a first-class native panel,
implemented as two terminal iop modules (borders at order 76, watermark at order 77,
matching Darktable) plus a SwiftUI panel. Feature parity with the standalone yiyin
project (which continues independent maintenance). Layout algorithm, EXIF extraction,
font management, and model-map normalization ported from Electron/Svelte/sharp to
Swift/Core Image/Core Text.
**Success Criteria**:
1. White border/frame generation (margin, ratio, color, aspect-ratio expansion, portrait↔landscape transform) produces output matching yiyin parity.
2. EXIF overlay (camera/lens/focal length/aperture/shutter/ISO/capture time — configurable fields and formats), date text (configurable font/size/color/position/rotation), and logo watermark (PNG/transparent, configurable position/size/opacity) render correctly.
3. Custom font management (.ttf/.otf upload, local-only, no network) works via CoreText; text-template system (preset + user-custom template strings) functional.
4. Make/Model brand normalization (Sony ILCE→α, Nikon Z→ℤ, etc.) ported from yiyin's model-map.
5. Output size/resolution config (DPI, long/short edge pixels, preserve original) drives both the in-editor preview and the export-time application.
**Requirements:** YIYIN-01, YIYIN-02, YIYIN-03, YIYIN-04, YIYIN-05, YIYIN-06, YIYIN-07, YIYIN-08
**Notes:** yiyin is a first-class panel, not a plugin. The yiyin repo stays independent; the Lightamer panel is a native rewrite with feature alignment. Implemented as terminal iop modules so the same config is shared between editor preview and export (EXP-05 in Phase 11 depends on this). Risks: none domain-specific beyond color-management correctness (COLOR-2).

### Phase 11: Export Pipeline & Batch Queue
**Goal:** The EXPORT pixelpipe variant (full-res, chosen output profile, no caches) with
all six formats, resize/DPI/color-space config, multi-spec simultaneous export recipes,
a background queue with progress/cancel/retry, yiyin border/watermark application as the
final step, and post-export actions.
**Success Criteria**:
1. All six formats export correctly: JPEG (quality), PNG (8/16-bit), TIFF (8/16/32-bit float + compression), HEIF/HEIC (quality, 10-bit), WebP (libwebp SPM, lossy/lossless), AVIF (native macOS 27 `CGImageDestination`, libavif SPM fallback, 8/10/12-bit).
2. Export queue runs in the background with progress reporting, cancellation, and failure retry; does not block editing (separate MTLCommandQueue, lower priority, bounded concurrency).
3. Multi-spec simultaneous export works: one source → many size/format/watermark combos (export recipes) in one queue action.
4. Export applies yiyin border/watermark as the final step (sharing config with the Phase 10 panel); output color space (sRGB/Display P3/Adobe RGB/ProPhoto/Rec2020) selectable with embedded ICC profile.
5. Post-export actions (run shell script, open folder in Finder) execute; files land in Session/Output/.
**Requirements:** EXP-01, EXP-02, EXP-03, EXP-04, EXP-05, EXP-06, EXP-07, EXP-08
**Notes:** Ordered after Phase 10 (yiyin) because EXP-05 applies the yiyin border/watermark. AVIF uses native macOS 27 encode (the macOS 27 floor removes the libavif dependency that SUMMARY.md flagged for older OS); libavif retained as a fallback SPM dep. WebP always needs the libwebp SPM dep (Apple does not expose WebP write). EXIF + XMP packet embedded in output (round-tripped + edited metadata). Risks: PERF-4, INTEROP-1.

### Phase 12: Metadata, Rating, Presets & LUT
**Goal:** Metadata/organization (star rating, color labels, hierarchical keywords,
standard EXIF/IPTC/XMP read-write, filtering/sorting, smart albums), the native preset
system (save full adjustment stacks as `.lightamer-preset`), preset manager, and `.cube`
LUT import + application as the IOP-COLOR-08 module (1D/3D, DOMAIN_MIN/MAX, tetrahedral
interpolation).
**Success Criteria**:
1. Star rating (0-5), C1-style color labels, and hierarchical keywords are editable and synced to both the Lightamer sidecar and standard EXIF/IPTC/XMP (interop with other tools).
2. Filter and sort by rating/label/keyword/camera/lens/date/ISO/focal length; smart albums (rule-based virtual groupings, no file copies) work.
3. Native preset system saves/loads complete adjustment stacks as `.lightamer-preset` (JSON/Codable); preset manager supports create/edit/delete/import/export/categorize; presets apply to single or batch.
4. `.cube` LUT (1D or 3D, honoring DOMAIN_MIN/MAX for float/HDR, tetrahedral interpolation as default) imports and applies as the IOP-COLOR-08 module with an explicit application color space selector (Darktable lut3d equivalent).
**Requirements:** META-01, META-02, META-03, META-04, META-05, META-06, PRES-01, PRES-02, PRES-03, PRES-04, IOP-COLOR-08
**Notes:** Presets are NOT interoperable with Darktable/Lightroom (locked decision) — `.lightamer-preset` is the own format; `.cube` LUT is the standard interop point. IOP-COLOR-08 and PRES-03 are the same feature (the `.cube` LUT module) and ship together here. `.cube` carries an explicit application color space to avoid the "LUT authored for sRGB applied in Rec2020" bug (INTEROP-2/3). Risks: INTEROP-2/3, NDE-6.

### Phase 13: System Integration & Distribution
**Goal:** macOS system integration (Quick Look extension with edited-preview rendering,
Spotlight indexing of rating/labels/keywords/EXIF, trackpad/mouse gestures, drag-drop
import, system-language localization via String Catalog) plus color-management
completeness (soft proofing, multi-display ICC auto-switch) and the release pipeline
(GitHub open source, Developer ID signing + notarization, DMG/zip, CI).
**Success Criteria**:
1. Quick Look extension previews RAW files from Finder (with edits applied, not just original thumbnails); Spotlight importer indexes rating/labels/keywords/EXIF so session photos are searchable system-wide.
2. Soft proofing (printer/output device gamut simulation with out-of-gamut warning, relative-colorimetric + BPC, applied as the last transform before display — never baked into the edit) and multi-display ICC profile auto-switch work.
3. Trackpad/mouse gestures (two-finger zoom, pinch, rotate, two-finger pan), drag-drop import (Finder → session or editor), and system-language localization (zh/en via String Catalog, structure prepared for more) all functional.
4. GitHub repository public (MIT or similar permissive license); Developer ID signed + notarized DMG/zip distribution (non-sandbox); CI (GitHub Actions) builds, tests, signs, notarizes, and publishes on tag.
**Requirements:** SYS-01, SYS-02, SYS-03, SYS-04, SYS-05, DIST-01, DIST-02, DIST-03, DIST-04, COLOR-02, COLOR-03
**Notes:** Spotlight importers and Quick Look extensions are separate processes with their own entitlements — keep them decoupled from the main (non-sandboxed) app so the non-sandbox decision holds (DIST-3). Deep-sign every embedded binary before notarizing; treat notarytool warnings as errors (Gatekeeper enforces what notarization only warns — DIST-1). Resolve all resource paths from `Bundle.main` (Gatekeeper translocation — DIST-2). COLOR-02 (soft proof) and COLOR-03 (multi-display ICC) complete the color-management pipeline started in Phase 2. Risks: CIRAW-2 (per-OS CI matrix), DIST-1..5, SOLO-4/5, UI-4, COLOR-3/4. **（2026-09-26 登记）蒙版命令面 UI 打磨批入本 phase**：蒙版 Duplicate / Duplicate-and-Invert / Fill / Clear / Reset Edits 菜单命令 + overlay 三态切换（On-Black / Rubylith / 半透明）+ 蒙版列表 enable 勾选——内核语义 Phase 6 全在（combine inverted/装配/overlay 显示），缺 UI 装配；对标 Nitro Photo，UI 级非算法缺口。

## Coverage
- Total v1 requirements: 140
- Mapped: 140 (100%)
- Unmapped: 0 ✓

### Per-phase counts
| Phase | Requirements |
|-------|--------------|
| 1 — Foundation, App Skeleton & Spikes | 11 |
| 2 — Pixelpipe Core, Color Mgmt & History | 8 |
| 3 — Tone & Filmic iops | 10 |
| 4 — Geometry, Lens & Detail iops | 8 |
| 5 — Color & Denoise iops | 12 |
| 6 — Layers & Masking System | 14 |
| 7 — AI Modules (Native Vision Masking & Retouching) | 4 |
| 8 — HDR/Stacking & Effects iops | 10 |
| 9 — Capture One Session Management | 9 |
| 10 — yiyin Border/Watermark Panel | 8 |
| 11 — Export Pipeline & Batch Queue | 8 |
| 12 — Metadata, Rating, Presets & LUT | 11 |
| 13 — System Integration & Distribution | 11 |
| 14 — MCP Server (远程 AI 修图 + 自动筛选) | 10 |
| 15 — Performance 专项（60fps 决战 + 全链路性能） | 7 |
| 16 — Catalogs Mode | 6 |
| **Total** | **140** |

### Spike summary (research-flagged)
| Spike | Phase (preliminary) | Phase (full validation) |
|-------|---------------------|-------------------------|
| CIRAW 9 vs RAW 8 capability boundary (determines demosaic-menu v1 scope) | 1 | — (decision) |
| 100MP Metal performance vertebra (60fps feasibility on GFX100S) | 1 | 2 (cache fast path) |
| filmicrgb Metal port validation vs Darktable reference (~2000 lines) | 1 | 3 |
| Raw denoise profiling feasibility (per-camera noise profiles) | 1 | 5 |
| Darktable XMP import round-trip (validate import-tolerant parser) | — | 2 (sidecar) |

### Phase 14: MCP Server（远程 AI 修图 + 自动筛选接口）【v1 扩展，2026-09-22 用户指令；2026-09-26 扩充筛选能力面】
**Goal:** Lightamer 内嵌 MCP（Model Context Protocol）server，使远程 AI 能通过 MCP 协议对本机照片执行 RAW 修图并取回预览图；**并支持外部 AI 自动筛选（culling）——外部 AI 读会话照片（缩略图/联系表/原尺寸 ROI 细节）后把星级/旗标/色标写回，照片留在 Lightamer 工作流内**（2026-09-26 用户指令；对标 lightroom-mcp 实践：缩略图阵列 → 联系表对比 → 原尺寸脸部细节检查 → 星级写回，vault 文章《我让AI接入Lightroom，帮我做筛选100张RAW》）。双入口：GUI 偏好开关（开启即启动 server）与 CLI 无头拉起（不开 GUI 直接启动同一 server）。
**Success Criteria**:
1. MCP 工具集可用：load_image（打开 Session/RAW 路径）、apply_params（设置 iop 参数面/图层栈）、render_preview（渲染并返回预览图，分辨率/格式参数化）、iop 清单与参数 schema 元数据。
2. 双入口：GUI 开关开启即启动（绑定地址/传输可配置，默认 localhost），关闭即停；CLI 无头启动同一 server（无 GUI 进程）。
3. 端到端：远程 MCP client 载入 DSC00012.ARW → 施加 ≥3 个 iop 参数 → 取回预览图，内容与本地渲染量化一致。
4. 安全面：默认仅绑定回环地址；非回环暴露必须带鉴权 token；文档明示风险。
5. 筛选端到端（2026-09-26）：外部 MCP client 列出会话照片（索引查询含 EXIF/rating/flag）→ 批量取缩略图/联系表/原尺寸 ROI 细节裁剪 → 写回星级/旗标/色标（sidecar 为真 + GUI 缩略图与索引同步可见），全程不碰像素与文件删除。
6. culling 方法论支撑（2026-09-26）：burst 分组查询（连拍聚类）+ 脸部区域定位（复用 Phase 7 Vision faceLandmarks）可供 AI 组合出「全图阵列 → 相似组联系表 → 脸部细节」筛片流。
7. GUI launcher 端到端（2026-09-26 登记，MCP-10）：偏好配置 agent CLI 命令模板（如 pi/omp）→ 点「一键 AI 筛图/修图」→ app 拉起 agent 进程挂自身 MCP server → 写回经 server 落 sidecar，GUI 缩略图 stale 再生同步可见；输出日志面板显示 agent 文字流。外部任意 MCP client 直连与 launcher 双入口并存。
**Requirements:** MCP-01, MCP-02, MCP-03, MCP-04, MCP-05, MCP-06, MCP-07, MCP-08, MCP-09, MCP-10
**Notes:** 依赖 Phase 2 无头 pipe（已具备）、Phase 9 Session（索引 DB + 双档缩略图 + 批量管线三段——筛选读写直接复用）、Phase 11 渲染导出、Phase 12 rating/flag 字段真身、Phase 5/8 iop 集、Phase 7 Vision 基建。Swift MCP SDK 选型入研究。筛选图像传输走联系表拼图与缓存缩略图（token 效率——100 张全尺寸原图不可行，文章方法论同款）。**MCP-09 组**（2026-09-26 登记）：preset 三件套（上游 PRES-01..04）+ export_image（Phase 11 EXP 面复用）+ set_keywords（上游 META-04）+ 三研究项（A = GUI/无头同会话并发 sidecar 双写对策；B = 多版本参数组/历史快照 MCP 语义；C = `match_color` 工具位——agent 编排皮，签名预留依赖 V2 TRACK colormatch iop）。**MCP-10 launcher = V1**（2026-09-26 用户裁决）：agent provider 配置归 agent 自身体系，app 零 AI 代码；执行用户配置命令的 shell 注入面需文档明示；B 路（GUI 内嵌 AI 面）不做、v2 再议。

### Phase 15: Performance 专项（60fps 决战 + 全链路性能）【v1 扩展，2026-09-22 用户指令；同日扩充范围】
**Goal:** 系统性性能专项，覆盖六大战场：①预览管线 ②交互流畅性 ③RAW 解码 ④懒加载 ⑤批量修图吞吐 ⑥内存足迹——把全链打进 60fps@100MP 预算并清算 PERF-5 全部挂账。
**Success Criteria**:
1. 预览管线：PREVIEW 全链（满 iop 集 enabled）warm median ≤16.6ms；
2. 交互零卡顿：滑块拖动/缩放/平移的 hitch（>50ms 帧间隙）= 0，主线程长任务清零（MainActor 阻塞审计）；
3. RAW 解码：100MP 首渲可交互时间 ≤500ms（后台解码 + 渐进显示），CIRAW 9/8 双档计量在案；
4. 懒加载：万张级 Session 浏览器滚动 60fps，缩略图按需解码，缩略图内存 LRU 预算生效；
5. 批量修图（懒渲染语义，dt 对标）：apply = 纯元数据操作（sidecar/history 写入），**禁止触发任何像素渲染**——万张 apply ≤5s（dt paste-history = 中央 sqlite 事务实测秒级；Lightamer sidecar-per-image 需批量写策略：合并/顺序/异步队列，USB 卷小文件 FS 开销是主要风险，设计约束进 Phase 9/11；可选混合 = C1 .cosessiondb 同构的会话级缓存索引 DB（可重建派生物非真身，真身恒为 sidecar——不做 dt 式中央库，PROJECT.md 立项约束））；缩略图标记 stale 由后台按需再生（THUMBNAIL lazy 已有）；export 排除在外（Phase 11 范围）；
6. 内存：100MP FULL 单帧 + N 层图层栈足迹 ≤3GB（TilingPlan 窗口化兑现）；
7. Instruments 系统级 profile 报告落账（GPU 趟数/热点/内存分布），杠杆兑现记录在案（dispatch 批合并、Lab 往返共享应急预案裁决）。
**Requirements:** PERF-01..08（PERF-5 债务在此清账）
**Notes:** 依赖全功能集完成后 profile 才有意义；05-08 的 PERF 复估数字是本 phase 的输入基线。解码/懒加载/批量的基线计量在对应功能阶段（9/11）建立。

### Phase 16: Catalogs Mode【2026-09-27 用户指令新立；同日终裁 v1 后端 = 本地 SQLite】
**Goal:** 对标 Capture One 双模式组织——在既有 Sessions 模式（恒默认）之外，提供可选的 Catalogs 模式（Lightroom Collections/Categories 同类）：设置中启用后获得跨会话的 catalogs 组织树、虚拟集合与全库浏览过滤；Sessions 模式零依赖完整可用，目录库可由会话面全量重建（sidecar 恒真身）。**后端 = 本地 SQLite**（复用 Phase 9 libsqlite3 面 + 12-2 FilterSQL 谓词层——零新依赖、零部署；用户 2026-09-27 终裁，pg 可行性预研降为 v2 评估项）。
**Success Criteria**:
1. 双模式共存：Sessions 恒默认零依赖；Catalogs 模式设置中启用；脱库降级零功能损失。
2. 目录库 = 本地 SQLite 跨会话元数据单向投影（会话→目录）+ catalogs 组织树（C1 Categories 语义）+ 虚拟集合；可全量重建（mutable and untrusted 延续）；**标签物化表**（(image_id, tag) 拆行 + 层级展开）支撑百万级层级关键字查询。
3. **基准门（最终实证裁决）**：1M 行参考库 + 真实查询集，网格分页 p95 < 50ms（SQLite 口径实测）。
4. catalogs 组织树编辑（CRUD/拖拽）+ 图片归类含批量。
5. Catalogs 模式下跨会话浏览/过滤/智能相册（复用 Phase 12 谓词层，求值域扩全库）。
**Requirements:** CATALOG-01..06
**Notes:** 本 phase 推翻 2026-08-03 的「不做中央库」整族排除（用户 2026-09-27 指令；Out of Scope 表已修订留痕）——修订语义 = 中央库从「禁止」变为「可选第二模式、默认关闭」；Sessions 哲学与 sidecar 真身原则不变。**v1 零新依赖零部署**（首个 SPM 新增仍只有 Swift-WebP）。时序 = Phase 12 收口后 discuss/research 独立成环（12-1..12-3 已交付的 session 面在双模式下均为复用底座，无返工）。
**v2 评估项存档（2026-09-27 预研，届时重启裁决）**：①远程后端——用户现成 LAN pg 实例（~0.2-1ms/往返可接受 vs 50ms 预算；可用性绑 NAS 为代价）；pg 可行性预研三边界仍有效（元数据查询面 pg 强 / 预览吞吐是管线问题 / 禁远程网络库主路径）；部署形态 = macOS 宿主直装优先（Docker Desktop VM 边界税，`synchronous_commit=off` 可卸投影 fsync）。②驱动选型 PostgresNIO vs libpq。③基准任务：宿主直装 vs Docker named-volume 双跑。原预研全文保留于下，均为 v2 输入：

**可行性预研结论（2026-09-27，orchestrator 外部调研）——pg 方案判定可行，附三个边界**：
①**尺度分层**：C1/LR 的 Catalogs 性能痛点 = 元数据查询面（过滤/排序/集合聚合在 10k+ 后劣化，C1 社区实证「10,000 张以上 endless problems」）+ 目录文件损坏/膨胀/备份（C1 verify/restore 流程即为此设）。pg 对前者是降维打击（复合索引分页查询 1M 行 = 毫秒级；`ltree`+GiST 原生解层级关键字树查询——恰是 LR 关键字树痛点；`pg_trgm`/`tsvector` 解模糊与全文；分区表应对亿级）。对后者（预览生成吞吐）pg **无帮助**——那是管线问题，Lightamer 已有 Phase 9 双档缩略图+LRU+stale 再生方案，两不相干。
②**直接先例**：digiKam 官方文档明确 MySQL/MariaDB 后端为大库推荐（「10 万张以上没理由用 SQLite」社区共识；官方对比列「Better performance」）；Immich（Postgres 后端）10 万级资产可用。反向证据亦在案：SQLite 本盘读可快于网络 MySQL（4.9x 读基准）→ **远程网络库不作主路径**（延迟预算入 research）；MariaDB 11.7.2 类版本兼容坑 → 版本钉死策略。
③**运维边界**：pg 实例用户自管（已由「手动配置」门控接受）；备份 = pg_dump/basebackup 标准件（优于 C1 单文件 verify/restore）。
**引擎归因调研（2026-09-27 第二轮）——LR/C1 劣化与 SQLite 的关系已拆清**：LR `.lrcat` = SQLite（lightroomqueen 连接串实证）；C1 `.cocatalogdb` = SQLite 3.x（C1 官方论坛原文）——两家都在 SQLite 上变慢，归因必须落到用法层。三拆（可修、Lightamer 已规避）：a. 目录膨胀/碎片（LR history 逐步快照 → 巨大化；官方修复 = Optimize Catalog 即 VACUUM+重建＝维护动作非引擎更换；Lightamer = append+position + 可重建）b. 预览管线（与引擎无关，Phase 9 方案已有）c. 部署反模式（网络共享/慢盘；Lightamer 本地文件）。SQLite 本体规模证据：10 亿行插入 <60s（avi.im/sqlite.org 论坛）、9000 万行 SO 案例、1 亿行 HN 生产案例、TB 级 whentouse 在册——1M-100M 行域引擎非瓶颈。残余风险如实：schema 纪律（已对）+ 标签物化表（已立项）+ checkpoint 调优（基准覆盖）由 Lightamer 自担。LR/C1 是「SQLite 被用出问题」案例，非「SQLite 到顶」案例。
**术语勘误**：模式名 = **Catalogs**（用户勘误 category→catalogs）；组织树沿用 C1 **Categories** 语义。
**部署形态预研（2026-09-27）**：macOS Docker Desktop VM 边界双损耗（TCP 回环穿 NAT ~0.2-1ms/往返 vs unix socket ~50µs；数据卷 fsync 经虚拟化层，bind mount 最差）——v2 若远程/容器部署时适用；`synchronous_commit=off`（可重建投影合法免 durability）为容器化纪律之一。
**引擎归因调研（2026-09-27，orchestrator 第二轮外部调研）——LR/C1 劣化与 SQLite 的关系已拆清**：
①**双引擎实证**：LR `.lrcat` = SQLite（lightroomqueen 给出过连接串 `SQLite:dbname=...lrcat`；多个独立来源一致）；C1 `.cocatalogdb` = SQLite 3.x（C1 官方论坛原文）。即 LR/C1 都跑在 SQLite 上——故「劣化与 SQLite 无关」不能整句断言，**归因必须落到用法层**。
②**归因三拆（可修、且 Lightamer 已规避）**：
   a. 目录膨胀/碎片——LR history 逐步快照 → .lrcat 巨大化；官方修复 = File > Optimize Catalog（即 VACUUM+重建）＝**维护动作而非引擎更换**，说明引擎有余量、烂在上层。Lightamer history = append+position（无逐步快照膨胀）+ Catalogs 库可全量重建。
   b. 预览管线——LR 主要等待源 = 预览生成/缓存（官方优化建议大头：RAW 缓存/预览尺寸/禁 face lookup）。管线问题，与引擎无关；Lightamer 有 Phase 9 双档缩略图。
   c. 部署反模式——目录放网络共享/外置慢盘（C1 官方建议内置快盘；speich.net 2026 案例 = LR 目录跑网络共享被迫自建 VFS）。文件型库上网络文件系统 = 锁+延迟地狱。Lightamer：Sessions 本地、Catalogs 库本地文件、远程仅 v2 可选镜像。
③**SQLite 本体规模证据**：10 亿行插入 <60s（avi.im/sqlite.org 论坛实测）；SO 经典案例 9000 万行索引下正常；HN 生产案例 1 亿行；sqlite.org whentouse 在册 = TB 级支持。1M-100M 行域引擎非瓶颈。
④**残余风险如实**：SQLite 需要自做的事 = schema 纪律（防膨胀——已对）、查询模式（标签物化表——已立项）、checkpoint 调优（research 基准覆盖）。LR/C1 是「SQLite 被用出问题」的案例，不是「SQLite 到顶」的案例。
⑤**结论维持**：本地 SQLite 判定可行；1M 行基准门（p95<50ms）作最终实证裁决。

---
*Last updated: 2026-08-03 — Phase 7 rescoped to native-only AI (4 reqs); AI-02/03/04 moved to v2*

## V2 待办（v1 之后；2026-09-22 用户确认）

- **Alcedo 对标缺口（ALCE-01..07；2026-09-27 功能基准翻转 Alcedo Studio 后登记）**：LGG 三向色轮 / OpenEXR 32-bit float 导出 / Ultra HDR JPEG 导出 / DRT 扩容（ACES 2.0 输出变换 + OpenDRT，现有 filmic/sigmoid/agx 之外）/ 每片命名版本（从历史任意步分叉）/ in-app 自然语言搜索（本地 CLIP）+ 自动打标签 / in-app AI 评片与描述（OpenAI/Anthropic 兼容 API）。需求定义见 REQUIREMENTS.md「Alcedo Parity (ALCE)」节。CIRAW 边界排除项（demosaic 算法菜单、raw 域高光重建）不入 ALCE——架构上不可达，见 STACK.md Decoder 策略对比节。
- **追色（Color Transfer，TRACK-01..05）**：参考图（单/多张）色彩分布 → 色彩变换求解（Reinhard/CDF/最优传输族择一）→ `colormatch` 模块（内嵌 3D LUT + tetrahedral kernel）非破坏落位。需求定义见 `.planning/REQUIREMENTS.md` TRACK 节（V2）；CIRAW 9 无此能力（2026-09-22 查证），需自研经典色彩迁移数学。与 Phase 12 .cube LUT 格式协同。**（2026-09-26 再确认）计算核 native 不可外包**——agent vision 迭代不满足 TRACK-05 确定性门与 TRACK-02 多参考统计；MCP+agent 作编排皮（MCP-09 研究项 C `match_color` 工具位）。
- **蒙版扩展（2026-09-26 对标 Nitro Photo 登记）**：IOP-MASK-06 Follow Edges 边缘感知笔刷（Metal edge-aware/contour-following，Nitro 独门，算法级，可插队 v1 后期 UI 打磨轮）；IOP-MASK-07 Depth 深度蒙版（AVDepthData/ProRAW embedded matte，桌面 RAW 深度源稀缺，数据面依赖）。需求定义见 `.planning/REQUIREMENTS.md`「Masking Extensions (v2)」节。AI Background 类型入口 = subject+invert UI sugar（任意 UI 轮捎带，不立需求）；蒙版命令面 UI（Duplicate/Fill/Clear/overlay 三态/enable 勾选）挂 Phase 13。
