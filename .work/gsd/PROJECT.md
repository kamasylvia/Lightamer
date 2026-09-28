# Lightamer

## What This Is

Lightamer 是一个 **macOS 独占的 Alcedo Studio 克隆**（**2026-09-27 用户项目重定义**，覆盖此前「对标 Darktable 全量」与「C1 Session 工作流」两条旧定位）：Swift 6 + SwiftUI + Metal 3 直渲 + **Core Image RAW 9 解码**（Apple Neural Engine demosaic+denoise，不写 RAW 解码器），**UI 与功能面完全模仿 Alcedo Studio**（节点式调色：Develop → Color Grade×N → Display Transform；图库/相册/项目文件；蒙版；DRT；导出选项）。darktable 独有的已交付功能**代码暂时保留但默认不启用**（feature flag 门控）。壹印（yiyin）印框/水印面板保留为一等公民。

## Core Value

在 macOS 上把 Alcedo 的编辑体验（节点式调色 + 图库 + DRT + AI 图库功能）用 Swift/Metal/RAW 9 原生重做一遍：100MP+ 大图零延迟、RAW 9 Neural Engine 解码、原生 EDR——比 Alcedo（C++/Qt，自养 LibRaw 解码器，无降噪）更快的解码与降噪、更全的导出格式（保留原 6 格式矩阵），外加 yiyin 印框/水印。

## Requirements

### Validated

(None yet — ship to validate)

### Active（Alcedo V1 重定义，2026-09-27；细节以 .work/gsd/research/ALCEDO-FEATURE-MAP.md 测绘 + 用户签核后的新 ROADMAP 为准）

- [ ] **UI 完全模仿 Alcedo**：图库网格 + 相册检查器、编辑器布局（调整面板/胶片条/节点编辑器/蒙版编辑器/显示变换面板/导出面板）
- [ ] **图片管理 Alcedo 方式**：图库 + 相册 + 项目文件承载相册结构与编辑历史；**原 Sessions/Catalogs 方案剥离**（代码保留、UI 不暴露、默认不启用）
- [ ] **节点式编辑模型**：Develop → Color Grade×N → Display Transform，每节点独立调整 + 独立蒙版；既有 adjustment layers 基础设施作为底座复用
- [ ] **Color Grade 控件集**（Alcedo 对齐）：影调/色彩控制、色调曲线、LGG 三向色轮、可选颜色、细节工具、阴影/高光局部色调映射；胶片 CUBE LUT、胶片颗粒、光晕
- [ ] **DRT**：ACES 2.0 输出变换 + OpenDRT，目标色彩空间/传递函数/峰值亮度可选，SDR/广色域/HDR 输出与 EDR 预览（现有 filmic/sigmoid/agx 属 dt 体系，禁用）
- [ ] **蒙版**：Alcedo 蒙版体系 + Nitro Photo 方案（Follow Edges 边缘感知笔刷等）；**不采用 dt 蒙版方案**
- [ ] **版本与历史**：每片多命名版本、从历史任意步分叉（git-like）、Look 复制到其他照片
- [ ] **导出**：格式保留原矩阵（JPG/PNG/TIFF/HEIF/WebP/AVIF，比 Alcedo 全）；可选项按 Alcedo——长边/像素/打印尺寸、ICC 嵌入、文件名模板、导出预设、剥离定位/序列号/编辑历史
- [ ] **AI 图库功能（Alcedo 方案）**：本地 CLIP 自然语言搜索 + 自动打标签；AI 评片（1-5 星 + 理由）与图片描述（OpenAI/Anthropic 兼容接口，钥匙串存 key，后台跑）
- [ ] **dt 独有已交付功能禁用**：39 个 dt 派生 iop 逐一审计，Alcedo 无对应者 feature-flag 门控默认关闭（代码+测试保留全绿）；启用/禁用矩阵落盘
- [ ] **RAW 9 解码**：CIRAW decoder version 9 opt-in，无自写解码器；新机型空窗期接受（v2+ 评估 libraw 兜底）
- [ ] 内置 yiyin（壹印）印框/水印面板：白边/日期/EXIF 叠加/Logo 水印/自定义字体（保留，适配新 UI 壳）
- [ ] Metal 直渲（MTKView/MTLTexture）主编辑视图，100MP+ 高分辨率下交互 60fps
- [ ] 多语言跟随系统（String Catalog，zh/en/…）
- [ ] MCP server（Phase 14 已交付资产）：非 dt 独有，保留；与 in-app AI 功能互补

### Out of Scope

- iOS / iPadOS / Windows / Linux — macOS 独占
- Lightroom catalog 模式 — 已被 Alcedo 项目文件方式取代
- dt 独有功能**启用**（filmic/sigmoid/agx/toneequal/denoiseprofile/velvia/monochrome/equalizer/bilat/hazeremoval/liquify/retouch 等 dt 体系模块）— 代码保留、默认禁用，v1 不暴露
- dt/Alcedo 互通（sidecar/预设/项目文件均不互通）
- 商业化 / 账号体系 / 订阅 — 开源免费

## Context

**参考源码：**
- **Alcedo Studio**（`/Volumes/UNITEK/Documents/Development/AlcedoStudio`，2026-09-27 引入）：**功能对标基准**（GPL-3.0 C++20，Windows CUDA/OpenCL + macOS Metal）。节点式调色图（Develop → Color Grade×N → Display Transform，每节点独立调整+蒙版）与本项目 adjustment layers 同构；其 GPU demosaic 算子（RCD/DemosaicNet 蒸馏 NN）、inpaint-opposed 高光重建、ACES 2.0/OpenDRT DRT、图库（DuckDB + CLIP 自然语言搜索 + AI 评片）、导出（OpenEXR/Ultra HDR JPEG）为增量功能参考。同 GPL-3.0——只读参考算法思路，代码不复制入库（本项目 MIT）。
- **Darktable**（`/Volumes/UNITEK/Documents/Development/darktable`）：**历史算法资产**（2026-09-27 起不再是功能对标基准）。Phase 3/4/5 已按其模块簇交付 39 个 iop（filmicrgb/sigmoid/agx/toneequal/denoiseprofile/colorzones 等），OpenCL kernel（`data/kernels/*.cl`）仍是缺口算法的参考源。sidecar（.xmp）与预设（.dtstyle）**不互通**（Lock-early 决策，见 Constraints）。
- **yiyin / 壹印**（`/Volumes/UNITEK/Documents/Development/yiyin`）：Electron + Svelte + sharp + fluent-ffmpeg + exif-parser/exifreader 的照片印框/水印工具。其印框布局算法、EXIF 提取、字体管理、输出参数需移植为 Swift/Core Image/Core Text 实现。yiyin 项目继续独立维护，Lightamer 内置面板为重写但功能对齐。
- **Lightroom / Capture One**：仅作为 UX 与功能对标参考，无源码。

**关键技术依赖：**
- Core Image RAW 9（CIRAW 9）：RAW 解码的候选底层。其在 2025 macOS（14/15）上的实际能力边界（demosaic、noise profile、镜头校正、裁切等）由研究阶段澄清，决定哪些 iop 由 CIRAW 直接覆盖、哪些需 Metal 自实现。
- Metal：主编辑区直渲（MTKView）+ compute shader 实现 CIRAW 不覆盖的算法。
- SwiftUI：UI 层（侧边栏/面板/对话框），与 Metal 视图通过 NSViewRepresentable 桥接。

**目标用户：**摄影作者（项目作者本人优先），重视工作流效率与原生体验，已习惯 Capture One Session 工作流与深度 RAW 调整，希望在一个原生 app 内完成全部流程。

**性能目标：**100MP+ 中画幅 RAW（Fuji GFX100S、Sony A7R V、Phase One 等）下交互流畅。

## Constraints

- **平台**：macOS 专属（Swift 6）— 最低版本 **macOS 27**（Lock-early 决策，研究阶段确认）。理由：原生 CIRAW 9 Neural Engine demosaic+denoise、原生 AVIF 写入、最新 SwiftUI/Metal 3 成熟度。代价：覆盖机型窄，但开源项目且个人自用可接受
- **语言/运行时**：Swift 6 + SwiftUI + Metal 3 + Core Image（CIRAW，macOS 27 起原生 RAW 9）+ ImageIO + ColorSync/EDR — 不引入跨平台框架（Electron/Qt/Flutter 等）
- **渲染架构**：Metal 直渲（MTKView/MTLTexture）作为主编辑视图 — 从第一天就按此架构，避免后期重写
- **色彩管线**：working space = linear Rec2020 scene-referred；pixelpipe 数据类型 = float32 RGBA（Lock-early，与 Darktable modern pipeline 对齐，便于移植 filmicrgb 等 iop）
- **照片管理**：**（2026-09-27 项目重定义）Alcedo 方式**——图库 + 相册 + 项目文件承载相册结构与编辑历史；原 Capture One Session / Catalogs 两方案**剥离**（代码保留、UI 不暴露、默认不启用），存储后端（SQLite/单文件等）由 Alcedo 测绘研究定
- **局部调整**：**（2026-09-27 项目重定义）Alcedo 节点模型**——Develop → Color Grade×N → Display Transform，每节点独立调整 + 独立蒙版；Nitro Photo 蒙版方案（Follow Edges 等）并入；dt per-iop-mask 方案不采用。既有 adjustment layers 基础设施作为节点模型底座复用
- **分发**：开源免费 — GitHub 独立分发（2026-09-27 终裁：砍苹果渠道/签名公证，unsigned DMG/zip）
- **功能对标**：**UI 与功能面完全模仿 Alcedo Studio**（2026-09-27 项目重定义）；dt 独有已交付功能代码保留但默认禁用（feature flag）；启用/禁用矩阵以 Alcedo 测绘（`ALCEDO-FEATURE-MAP.md`）为准
- **互通性（决策）**：sidecar 与 Darktable **不互通、不兼容**（研究确认二进制兼容做不到）；预设与 Darktable/Lightroom **不互通**；标准 EXIF/IPTC/XMP 元数据仍读写（与其他工具兼容）
- **依赖最小化**：能用 Apple 原生框架（Core Image / Metal / Core Text / ImageIO / AVFoundation / ColorSync）实现的不引入第三方库。**（2026-09-28 Phase 14 收口修订，16 期漂移修正先例同款）**：SPM 依赖现状 = 显式枚举三项——① **Swift-WebP**（WebP 写入 macOS 仍无原生，EXP-02 引入）；② **官方 swift-sdk 0.12.1**（MCP server，Phase 14 引入；传递依赖 swift-nio / swift-log / swift-system / eventsource）；③ **swift-nio / swift-system 产品级直引**（App target 的 HTTP 适配腿真实编译依赖，D-14-1-T4-1）。libavif 已砍除（原生 AVIF 写入随 macOS 27 兑现，无需兜底库）。

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift 6 + SwiftUI + Metal 3 + Core Image + ImageIO | macOS 原生体验，Metal 加速满足 100MP+ 性能，与 Apple 生态深度集成 | — Pending |
| macOS 27 最低版本 | 获得 CIRAW 9 Neural Engine demosaic+denoise、原生 AVIF 写入、最新 SwiftUI/Metal 3；代价是覆盖机型窄 | — Pending（研究后锁定） |
| 工作色彩空间 = linear Rec2020 scene-referred | 与 Darktable modern pipeline 对齐，便于移植 filmicrgb 等场景参照算法；scene-referred 比 display-referred 更适合 HDR | — Pending（研究后锁定） |
| pixelpipe 数据类型 = float32 RGBA | 精度足够避免阴影 banding；半精度会在阴影出错（研究 Pitfalls 确认） | — Pending |
| iop 模块顺序采用 Darktable v50_order | 与 Darktable 算法移植路径一致；固定位置便于色彩管理 | — Pending |
| Capture One 风格 adjustment layers（非 Darktable per-iop 蒙版） | 个人工作流偏好；图层是 C1 局部调整的核心，体验更直观；架构需在 pixelpipe 设计时纳入图层栈 | — Pending |
| Capture One Session 模式（非 Lightroom catalog） | 个人工作流偏好，文件夹即会话便于备份/迁移/版本控制 | — Pending |
| sidecar 自有格式，不与 Darktable 互通 | 研究确认 Darktable base64 二进制 blob + modversion 跨实现兼容做不到；自有格式可最大化参数能力 | — Pending（研究后调整原 PROJECT.md 的互通意图） |
| Metal 直渲（MTKView）作为主编辑视图 | 大图零延迟交互是 Core Value，必须从第一天按此架构 | — Pending |
| 对标 Darktable 全量（长期工程，Fine 粒度分阶段） | 全功能 RAW 编辑器是产品存在的理由；接受分阶段交付，v1 不设上限 | — Pending |
| yiyin 双轨（Lightamer 内置面板 + yiyin 独立维护） | yiyin 已有用户基础，Lightamer 内置为重写但功能对齐 | — Pending |
| 开源免费 + 独立签名公证（非 Mac App Store） | 沙盒限制与 Session 文件访问冲突；开源路线与 yiyin/Darktable 一致 | — Pending |
| 多语言跟随系统（String Catalog） | 开源项目便于外部贡献者，与 Darktable/yiyin 国际化路线一致 | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-03 after research findings + requirements definition（macOS 27 floor、linear Rec2020、Capture One adjustment layers、sidecar 不互通等决策锁定）*
