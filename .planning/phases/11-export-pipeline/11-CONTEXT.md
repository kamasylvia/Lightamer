# Phase 11: Export Pipeline & Batch Queue - Context

**Gathered:** 2026-09-26（夜间自动 discuss；用户睡前指令「从下一 phase 开始全自动推进」）
**Status:** Ready for planning — 8 项 Open Questions 按**推荐项自动裁决**（D-11-CONTEXT-1..8，
**标注〔晨审追认〕**：用户晨间可推翻任一项，推翻项回注 planner 重开受影响面）；Phase 9
移交清单四条已逐条对位（09-DISCUSSION-LOG 终节 ↔ 本文件 decisions/research 输入面）

<domain>
## Phase Boundary

把「会话工作流」闭环到出片：EXP-01..08，核心架构事实：

1. **EXPORT pixelpipe 变体已存在**（Phase 2 FOUND-04 四管线 FULL/PREVIEW/THUMBNAIL/EXPORT）
   ——本 Phase 物化导出路径：全幅渲染（无缓存语义）→ 色彩空间出口转换 → 编码落盘。
   渲染腿复用 `renderCurrentChain` 全幅材料化（08-3 生产联合上下文注入已在链上——
   yiyin band 预留即为此刻而设，D-08-3-T3-2 义务闭环）。
2. **Phase 9 移交四条直接消费**：`SessionLayout.outputDirectory(for:)` 落点常量；
   批量队列复用面（`SessionBatchApplier` actor 模式 + 9-3 generation cancel +
   可见优先调度思想）；`thumb_state` stale 再生不涉及（导出不产缩略图）。
3. **编码 = CGImageDestination 为主 + libwebp 单点**——JPEG/PNG/TIFF/HEIC/AVIF 全原生
   （macOS 27 地板使 AVIF `public.avif` 恒可用）；WebP Apple 不暴露写，libwebp SPM
   是全项目**唯一新增 SPM 依赖**。
4. **色彩出口单一路径**：linear Rec2020 float32 working → 目标 ICC（sRGB/P3/AdobeRGB/
   ProPhoto/Rec2020）经 CIContext/Metal 出口一次转换，随后按格式量化 8/16-bit。
   软打样不在此（COLOR-02 = Phase 13）。
5. **队列与编辑互不阻塞**：独立 MTLCommandQueue（低优先级）+ 有界并发 + 进度/取消/重试
   （EXP-06）；渲染懒执行——每个 job 出队时才渲染（导出本身是渲染管线，不在 PERF-07
   零渲染约束域）。

**Phase 11 不做**：

- **预设系统**（PRES-01..04 = Phase 12）——recipe 的保存/管理走 Phase 12；v1 recipe
  在导出面板内联构造（session 生命周期），不持久化
- **软打样/输出 gamut 警告**（COLOR-02 = Phase 13）
- **.cube LUT 导出链**（IOP-COLOR-08/PRES-03 = Phase 12）
- **Import/备份/云**——出片到 Session/Output/ 或用户指定目录即止
- **打印**（PRINT = v2）
- **HDR/EDR 编码输出**（IOP-HDR-05 = Phase 8 后的独立面；本 Phase 输出域 = SDR 色彩空间）

</domain>

<decisions>
## Implementation Decisions

> 8 项 = Phase 11 discuss 阶段识别的 Open Questions，**按推荐项自动裁决〔晨审追认〕**
> （2026-09-26 用户睡前授权全自动推进；每条附理由 + 可逆性，晨间推翻任一项 → 回注
> planner 重开受影响面）。

### D-11-CONTEXT-1: AVIF = macOS 27 原生 `public.avif` 单路径；libavif SPM 不进 v1 构建〔晨审追认〕
- **裁决**：AVIF 编码走 `CGImageDestination` 原生 UTI（macOS 27 地板下恒可用）；`libavif`
  SPM 兜底**不引入**（PROJECT.md「保留作为兜底」的地板前提已成立）。v1 新增 SPM 依赖
  仅 **libwebp 一个**（破「预期两个」——是少于，非多于）。
- **理由**：兜底依赖的触发条件（macOS < 26）在 macOS 27 地板下不存在；少一个 C 依赖 =
  少一份构建/签名/公证面。
- **Reversibility**: 高——research 验证 `CGImageDestinationCopyTypeIdentifiers()` 含
  `public.avif` 即钉；若实测缺失（意外），fallback = 引入 libavif（预留接口位
  `AVIFEncoder` 协议双实现缝）。

### D-11-CONTEXT-2: 队列 = 独立 actor + 专用低优先级 MTLCommandQueue + 并发 1〔晨审追认〕
- **裁决**：`ExportQueue` actor（App/Session 层，模式对齐 9-3 缩略图队列：generation
  token 取消 + 有界并发 + 进度快照）；渲染 job 用**专用** `MTLCommandQueue`（低优先级，
  `queue.priority = .low`），并发 = **1**（导出是吞吐非交互场景，并发 1 保证内存足迹
  可预算：全幅 float32 工作平面 ≈ 800MB@100MP，双并发即破 3GB 红线边缘）。
- **理由**：SC#2「不阻塞编辑」由独立 queue + 低优先级满足；并发 1 是内存红线推导，
  不是偷懒。
- **Reversibility**: 高——并发数是常量参数；Phase 15 性能专项可实测调优。

### D-11-CONTEXT-3: Recipe 模型 = `ExportRecipe` 值类型（variants 数组），v1 不持久化〔晨审追认〕
- **裁决**：`ExportRecipe = [ExportVariant]`，variant = (resize/DPI, format+quality,
  colorspace, yiyin on/off + YiyinExportSettings)。一次队列动作 = N variants → N jobs
  （EXP-07）。**v1 recipe 不落盘**：面板内联编辑、session 生命周期内有效；保存为预设 =
  Phase 12 PRES 面。
- **理由**：预设系统未在位，持久化格式会提前冻结 Phase 12 的 schema；值类型 + Codable
  使 Phase 12 挂载成本趋零。
- **Reversibility**: 高——Phase 12 直接把 Codable 类型挂 preset 存储即完成升级。

### D-11-CONTEXT-4: 输出命名与冲突 = `<stem>[_<variant-tag>].<ext>` + 递增后缀，恒落 Session/Output/〔晨审追认〕
- **裁决**：单 variant 默认 `<stem>.<ext>`（同名冲突 → `-1/-2` 递增）；多 variant 加
  语义 tag（尺寸或格式派生，如 `_1200`/`_webp`）。用户可选自定义目录（安全作用域内），
  默认 `SessionLayout.outputDirectory(for:)`（9-1 移交常量）。
- **理由**：C1 惯例 = 出片进 Output/；tag 保证多规格同导不互相覆盖。
- **Reversibility**: 高——纯命名函数。

### D-11-CONTEXT-5: 元数据 = EXIF round-trip + XMP packet 嵌入（ImageIO metadata 面板）〔晨审追认〕
- **裁决**：导出嵌入源片 EXIF（round-trip：`CGImageSource` 读 → `kCGImageDestinationMetadata`
  写）+ 编辑摘要 XMP packet（CreatorTool=Lightamer + rating/flag 同步 META 面语义预留
  Phase 12）。不重排不清洗。
- **理由**：ROADMAP Notes 明示「EXIF + XMP packet embedded in output」；互通性决策
  （标准元数据读写与其他工具兼容）。
- **Reversibility**: 高。

### D-11-CONTEXT-6: EXP-08 post-export actions = 显式配置脚本路径（非 inline 命令）+ NSWorkspace open〔晨审追认〕
- **裁决**：shell 动作 = 用户显式选择一个可执行脚本文件路径（安全作用域书签），导出
  完成后以输出路径为 `$1` 调用；**不支持 inline 任意命令字符串**（shell 注入面收窄）。
  Finder 动作 = `NSWorkspace.activateFileViewerSelecting`。文档明示脚本以用户权限执行。
- **理由**：与 MCP-10 同款安全哲学（用户显式配置 + 文档明示）；inline 命令是注入面。
- **Reversibility**: 中——若用户强需 inline，Phase 14 research 一并裁（届时 MCP 面
  `run_script` 工具位同题）。

### D-11-CONTEXT-7: 色彩出口实现 = 单出口转换 + 有损域量化分层〔晨审追认〕
- **裁决**：渲染输出（linear Rec2020 float32）→ 目标色彩空间一次转换（CI 腿
  `CIContext` colorSpace 参数 / Metal 腿 COLOR-2 矩阵族）→ 格式位深量化
  （8-bit: sRGB EOTF 后 UInt8；16-bit: UInt16 线性或显示域按格式惯例；TIFF 32-float
  保线性）。HDR 裁剪策略：SC 门 = 广色域目标（P3/Rec2020/ProPhoto）不裁 chroma，
  SDR 白以上亮度钳位（EDR 输出 v2）。
- **理由**：与 08-2 yiyin COLOR-2 矩阵同族复用；量化域按文件格式惯例（PNG 16 显示域、
  TIFF float 线性）对齐行业互操作。
- **Reversibility**: 中——量化策略测试 golden 化后改动 = 重冻结。

### D-11-CONTEXT-8: 崩溃恢复 = v1 无 queue journal，重启丢队列〔晨审追认〕
- **裁决**：导出队列状态 in-memory；app 终止即丢（已落盘文件不回滚、不清理半成品
  ——编码走 tmp 原子晋升，半成品恒在 tmp，L009 纪律）。queue journal defer v2。
- **理由**：导出是幂等可重试操作，journal 复杂度（崩溃点追踪/半成品清理）vs 收益
  不成立；9-4 批量 apply 的 journal 是因为它改真身 sidecar，导出只写新文件。
- **Reversibility**: 高。

</decisions>

<open_questions>
## 晨审追认清单（全部按推荐自动裁决，可逐条推翻）

| # | 决策 | 推荐项（已选） | 推翻代价 |
|---|---|---|---|
| 1 | AVIF 依赖 | native-only，libavif 不进 v1 | 低（协议缝预留） |
| 2 | 队列并发 | 1（内存红线推导） | 低（常量） |
| 3 | Recipe 持久化 | v1 不落盘 | 低（Phase 12 挂载） |
| 4 | 输出命名 | stem+tag+递增后缀 | 低 |
| 5 | 元数据 | EXIF round-trip + XMP packet | 低 |
| 6 | EXP-08 脚本 | 路径制非 inline | 中（Phase 14 同题联裁） |
| 7 | 量化域 | 格式惯例分层 | 中（golden 重冻结） |
| 8 | 崩溃恢复 | 无 journal | 高（后补要重构队列） |

</open_questions>
