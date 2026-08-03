# Lightamer

## What This Is

Lightamer 是一个 macOS 原生（Swift + SwiftUI + Metal 直渲）的 RAW 编辑器与图片管理器，目标是对标 Darktable 的全量图像处理（iop）能力，同时采用 Capture One 的 Session 工作流（文件夹即会话，而非 Lightroom 的中央库）来组织照片。它面向摄影作者，把"调整 → 评分 → 批量导出 → 印框/水印出图"压缩成一个原生丝滑的工作流，并内置壹印（yiyin）的印框/水印能力作为一等公民面板。

## Core Value

在 macOS 上用 Metal 加速提供 100MP+ 大图下零延迟的 RAW 调整体验，并让 Capture One Session 工作流与 Darktable 级调整深度在同一原生 app 中共存——这是目前市面没有的组合。

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] 读取主流相机 RAW（CR3/NEF/ARW/RAF/RW2/ORF 等）、DNG、HDR/堆栈源文件，以及 JPEG/HEIC/PNG/WebP/TIFF 等非 RAW 格式
- [ ] Capture One Session 模式：文件夹即会话，自动维护 Capture/Crop/Output 三级子目录，sidecar（.XMP/.RAW）调整文件随原片存放，多 Session 切换 + 最近会话列表
- [ ] Darktable 级 iop（图像操作模块）能力，按 Darktable 全量对标，Core Image RAW 9 覆盖的直接用，缺口用 Metal compute shader 自实现（具体能力边界由研究阶段确定）
- [ ] Metal 直渲（MTKView/MTLTexture）主编辑视图，100MP+ 高分辨率下交互 60fps
- [ ] 批量导出队列 + 多规格同导（同一原片一次性输出多种尺寸/格式/水印组合）
- [ ] 导出格式：JPG、PNG、TIFF、HEIF/HEIC、WebP、AVIF
- [ ] 内置 yiyin（壹印）印框/水印面板：白边/日期/EXIF 叠加/Logo 水印/自定义字体；与 yiyin 项目双轨维护
- [ ] 调整同步/复制粘贴（一张图的调整参数复制到其他图）
- [ ] 前后对比预览（before/after 分屏、快照点对比）
- [ ] 预设系统：与 Darktable 互通（含 .cube LUT 作为 iop 模块，与 Darktable 的 LUT 模块互通）
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
- **Darktable**（`/Volumes/UNITEK/Documents/Development/darktable`）：唯一可源码参考的同类项目。C/C++ 实现，OpenCL 加速。Lightamer 的 iop 算法、模块顺序、色彩管理流程应大量参考其实现（移植到 Metal compute shader）。Darktable 的 sidecar（.xmp）格式、预设（.dtstyle）、LUT 模块是互通目标。
- **yiyin / 壹印**（`/Volumes/UNITEK/Documents/Development/yiyin`）：Electron + Svelte + sharp + fluent-ffmpeg + exif-parser/exifreader 的照片印框/水印工具。其印框布局算法、EXIF 提取、字体管理、输出参数需移植为 Swift/Core Image/Core Text 实现。yiyin 项目继续独立维护，Lightamer 内置面板为重写但功能对齐。
- **Lightroom / Capture One**：仅作为 UX 与功能对标参考，无源码。

**关键技术依赖：**
- Core Image RAW 9（CIRAW 9）：RAW 解码的候选底层。其在 2025 macOS（14/15）上的实际能力边界（demosaic、noise profile、镜头校正、裁切等）由研究阶段澄清，决定哪些 iop 由 CIRAW 直接覆盖、哪些需 Metal 自实现。
- Metal：主编辑区直渲（MTKView）+ compute shader 实现 CIRAW 不覆盖的算法。
- SwiftUI：UI 层（侧边栏/面板/对话框），与 Metal 视图通过 NSViewRepresentable 桥接。

**目标用户：**摄影作者（项目作者本人优先），重视工作流效率与原生体验，已习惯 Capture One Session + Darktable 调整，希望在一个原生 app 内完成全部流程。

**性能目标：**100MP+ 中画幅 RAW（Fuji GFX100S、Sony A7R V、Phase One 等）下交互流畅。

## Constraints

- **平台**：macOS 专属（Swift）— 依赖 Metal / Core Image / SwiftUI，最低 macOS 版本由研究阶段确定（倾向 macOS 14+，平衡 Metal 3 / SwiftUI 成熟度与覆盖机型）
- **语言/运行时**：Swift + SwiftUI + Metal + Core Image RAW 9 — 不引入跨平台框架（Electron/Qt/Flutter 等）
- **渲染架构**：Metal 直渲（MTKView/MTLTexture）作为主编辑视图 — 从第一天就按此架构，避免后期重写
- **照片管理**：Capture One Session 模式 — 文件夹即会话，三级子目录（Capture/Crop/Output）+ sidecar 调整文件，不做中央库
- **分发**：开源免费、独立分发（Developer ID 签名 + 公证，不做沙盒）— GitHub 开源
- **功能对标**：对标 Darktable 全量（100+ iop 模块）— 长期工程，v1 先工作流闭环，iop 分阶段逼近
- **互通性**：sidecar（.XMP/.RAW）与 Darktable 二进制兼容为目标；预设与 Darktable（.dtstyle / .cube LUT）互通
- **依赖最小化**：能用 Apple 原生框架（Core Image / Metal / Core Text / ImageIO / AVFoundation）实现的不引入第三方库

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift + SwiftUI + Metal + Core Image RAW 9 | macOS 原生体验，Metal 加速满足 100MP+ 性能，与 Apple 生态深度集成 | — Pending |
| Capture One Session 模式（非 Lightroom catalog） | 个人工作流偏好，文件夹即会话便于备份/迁移/版本控制 | — Pending |
| Metal 直渲（MTKView）作为主编辑视图 | 大图零延迟交互是 Core Value，必须从第一天按此架构 | — Pending |
| 对标 Darktable 全量（长期工程，v1 先闭环） | 全功能 RAW 编辑器是产品存在的理由，但接受分阶段交付 | — Pending |
| yiyin 双轨（Lightamer 内置面板 + yiyin 独立维护） | yiyin 已有用户基础，Lightamer 内置为重写但功能对齐 | — Pending |
| 开源免费 + 独立签名公证（非 Mac App Store） | 沙盒限制与 Session 文件访问冲突；开源路线与 yiyin/Darktable 一致 | — Pending |
| Core Image RAW 9 定位"先调研再说" | CIRAW 9 实际能力边界（覆盖哪些 iop）是关键技术风险，研究阶段必须澄清 | — Pending |
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
*Last updated: 2026-08-03 after initialization*
