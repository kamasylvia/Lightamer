# Lightamer

## What This Is

Lightamer 是一个 macOS 原生（Swift 6 + SwiftUI + Metal 3 直渲 + Core Image RAW）的 RAW 编辑器与图片管理器，功能深度对标 **Alcedo Studio**（开源 RAW 编辑器；**2026-09-27 用户指令翻转**：原基准为 Darktable 全量 91 iop 模块，因 dt 功能面过大且 raw 域功能在 CIRAW 路线下不可达，改为以 Alcedo 功能面为准），同时采用 Capture One 的 Session 工作流（文件夹即会话）+ Capture One 风格的调整图层（adjustment layers）来组织照片与局部调整。它面向摄影作者，把"调整 → 评分 → 批量导出 → 印框/水印出图"压缩成一个原生丝滑的工作流，并内置壹印（yiyin）的印框/水印能力作为一等公民面板。

## Core Value

在 macOS 上用 Metal 加速提供 100MP+ 大图下零延迟的 RAW 调整体验，并让 Capture One Session 工作流与 Alcedo Studio 级调整深度（节点式调色：影调/色彩、色调曲线、LGG 色轮、可选颜色、细节、局部色调映射、胶片 LUT/颗粒/光晕）在同一原生 app 中共存——这是目前市面没有的组合。

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] 读取主流相机 RAW（CR3/NEF/ARW/RAF/RW2/ORF 等）、DNG、HDR/堆栈源文件，以及 JPEG/HEIC/PNG/WebP/TIFF 等非 RAW 格式
- [ ] Capture One Session 模式：文件夹即会话，自动维护 Capture/Crop/Output 三级子目录，sidecar 调整文件（Lightamer 自有格式，不与 Darktable 二进制兼容）随原片存放，多 Session 切换 + 最近会话列表
- [ ] Alcedo Studio 级 iop（图像操作模块）能力【**2026-09-27 用户指令翻转**：基准由 Darktable 全量 91 模块改为 Alcedo 功能面；已交付的 dt 派生 iop（filmicrgb/sigmoid/toneequal/denoiseprofile 等 39 模块）全部保留为管线资产；与 Alcedo 的真实缺口登记为 REQUIREMENTS ALCE 族（V2）】；Core Image RAW（macOS 27 起原生 RAW 9 Neural Engine demosaic+denoise）覆盖的直接用，缺口用 Metal compute shader 自实现
- [ ] Capture One 风格 adjustment layers（每层独立 iop + 每层蒙版 + 层管理 + 混合模式）作为局部调整的核心组织机制
- [ ] AI 能力：v1 仅含 Apple 原生框架（Vision/Core Image）可直接实现的——主体检测蒙版（`VNGenerateForegroundInstanceMaskRequest`）+ 频率分离 AI 磨皮；需自定义 Core ML 模型的（天空分离/人像部位/通用语义分割/追色/评分）留 v2
- [ ] Metal 直渲（MTKView/MTLTexture）主编辑视图，100MP+ 高分辨率下交互 60fps
- [ ] 批量导出队列 + 多规格同导（同一原片一次性输出多种尺寸/格式/水印组合）
- [ ] 导出格式：JPG、PNG、TIFF、HEIF/HEIC、WebP、AVIF
- [ ] 内置 yiyin（壹印）印框/水印面板：白边/日期/EXIF 叠加/Logo 水印/自定义字体；与 yiyin 项目双轨维护
- [ ] 调整同步/复制粘贴（一张图的调整参数复制到其他图）
- [ ] 前后对比预览（before/after 分屏、快照点对比）
- [ ] 预设系统：原生预设系统（保存完整调整堆栈为 Lightamer 预设）+ .cube LUT 作为 iop 模块（不与 Darktable/Lightroom 预设互通）
- [ ] 元数据/评分/颜色标签/关键字，与 sidecar 同步
- [ ] Spotlight / Quick Look 集成（Quick Look 扩展、Spotlight 索引）
- [ ] 多语言跟随系统（String Catalog，zh/en/…）

### Out of Scope

- Lightroom catalog 模式（中央库）— 与 Session 理念冲突
- iOS / iPadOS 版本 — 项目定位为 macOS 专属
- Windows / Linux 跨平台 — 依赖 Metal / Core Image / SwiftUI
- Mac App Store 沙盒分发 — 开源免费 + 独立签名公证路线，沙盒限制文件访问与 Session 模式冲突
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
- **照片管理**：Capture One Session 模式 — 文件夹即会话，三级子目录（Capture/Crop/Output）+ sidecar 调整文件（Lightamer 自有格式），不做中央库。**（2026-09-27 用户指令修订）**：增设可选第二组织模式 **Catalogs 模式**（对标 C1 Catalogs；2026-09-27 终裁 v1 后端 = 本地 SQLite，零新依赖；远程 pg 降为 v2 评估项）——Sessions 恒默认零依赖，目录库为可重建聚合视图、sidecar 恒真身原则不变；详见 REQUIREMENTS CATALOG 族 / ROADMAP Phase 16
- **局部调整**：Capture One 风格 adjustment layers（每层独立 iop + 蒙版 + 混合模式）— 与 Darktable 全局 pixelpipe+per-iop-mask 架构不同，需在 pixelpipe 设计时纳入
- **分发**：开源免费、独立分发（Developer ID 签名 + 公证，不做沙盒）— GitHub 开源
- **功能对标**：对标 Darktable 全量（91 个 iop 模块）— 长期工程，Fine 粒度分阶段交付，v1 不设上限但分阶段逼近
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
