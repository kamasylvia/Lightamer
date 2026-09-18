# Phase 2: Pixelpipe Core, Color Management & History Stack - Context

**Gathered:** 2026-09-18
**Status:** Ready for planning — 决策由保活巡检以最佳判断定稿（YOLO 模式 + 用户全自动授权；用户可审阅推翻，决策均可逆）

<domain>
## Phase Boundary

承重架构阶段：Darktable 递归 pixelpipe 移植（per-module per-ROI cache + hash 命中快路径）、多分辨率管线（FULL/PREVIEW/THUMBNAIL/EXPORT）、终端三件套（colorin/colorout/gamma）正确显示色彩、history stack（稳定身份元组 + history hash）、Lightamer 自有格式 sidecar 持久化。

**Phase 2 不做**：具体 iop 算法（Phase 3+，本阶段只有 pass-through + 终端三件套）、软打样/多显示器 ICC（Phase 13）、HDR/EDR（Phase 8）、蒙版（Phase 6）、tiling 完整实现（仅脚手架）。

</domain>

<decisions>
## Implementation Decisions

### Sidecar 格式与命名
- **D-S1:** 格式 = **JSON（Codable，pretty-printed，带 schemaVersion 字段）**。理由：人类可读可调试（sidecar 是"用户的调色数据"，可读性=可信任感）；Swift Codable 原生；git diff 友好。性能不是问题——单文件 <100KB，读写频率低（参数变更时节流写入）。 — **Reversibility:** costly — 一旦用户数据以 JSON 存在，换二进制需迁移器；但 schemaVersion 字段从第一天就预留演进空间。
- **D-S2:** 命名 = **`<原文件完整名>.lra`**（如 `DSC09991.ARW.lra`），与原片同目录（Capture/ 惯例）。理由：按完整名追加避免与同名不同扩展的文件混淆；`.lra` 后缀一眼识别 Lightamer sidecar。**与 .xmp 共存策略：完全忽略 .xmp**（用户 NAS 会话里的 C1 .xmp 不读不写不删）——Phase 9 Session 管理时若需要 C1 互通再议。 — **Reversibility:** reversible — 命名是文件系统层，迁移=改名。
- **D-S3:** 写入时机 = 参数变更后**节流 2 秒**合并写入（拖动滑块不产生磁盘风暴）；app 退出/切图强制 flush。原子写（临时文件+rename）防止半写损坏。

### History 栈交互语义
- **D-H1:** 撤销粒度 = **一次拖动（drag-end）算一步**——滑块拖动期间实时预览但只在松手时提交一条 history 项；离散控件（按钮/下拉）每次点击一步。与 C1/LR 习惯一致。 — **Reversibility:** costly — history 语义是 sidecar schema 的一部分（D-S1 关联），改粒度需迁移。
- **D-H2:** 历史上限 = **不设上限**（sidecar 记录全量；JSON 每项 <1KB，100 步 ≈ 100KB，可忽略）。内存中 history 项持有参数引用不持有纹理，无内存压力。Phase 6 图层加入后单条 history 项携带 layer-scope 字段（schema 预留）。
- **D-H3:** 快照点（snapshot）**延后**——Phase 2 的 history 支持跳转到任意历史点（栈回溯 + 重放），具名快照（named snapshot）等 Phase 6 图层系统一起做（快照的价值在图层栈场景才完整）。
- **D-H4:** History hash = 参数内容哈希（每模块 paramsHash + 管线级组合 hash），用于 (a) 缓存失效判定 (b) sidecar 漂移检测。见 ROADMAP 成功标准 2/5。

### 缓存内存策略
- **D-C1:** 自动 clearCaches 触发：**会话管线内存 > 3GB**（D-32 预算 4GB 留 1GB 余量）时，加载新图前自动清理——保留当前图 FULL+PREVIEW、最近 1 张历史图的 PREVIEW，清除其余 THUMBNAIL/EXPORT/历史图 FULL。无用户提示阻塞，状态栏 toast 告知（D-26 分级提示）。 — **Reversibility:** reversible — 阈值常量可调。
- **D-C2:** 触发检查时机 = **每次 load(url:) 入口**（新图加载前清理旧图），加每 60 秒定时检查兜底（长会话同一张图反复调参也可能累积 PREVIEW 尺寸版本）。Phase 1 spike 证实：跨解码累积 4.3-5.4GB 会破预算。
- **D-C3:** PREVIEW 分辨率 = **min(drawableSize×2, 2560px 长边)**，量化到 360px 档位（2560/2200/1840/1480/1120…）避免窗口微调导致的重渲染风暴；窗口变化跨档才重渲染。FULL 管线仅在导出/100% 查看时触发。THUMBNAIL 固定 360px。

### 色彩管理与验收
- **D-COL1:** 正确性验收 = **known-neutral 目标照片**（X-Rite ColorChecker 类，含 50% 中性灰块）作为 golden 基准：terminal trio 后灰块 RGB 三通道差 <2/255。进 Phase 2 golden-image harness（VALIDATION 已规划 torture set）。
- **D-COL2:** 显示色彩 = 跟随 `NSScreen.colorSpace` 当前 ICC profile（FOUND 成功标准 1）；不做显示配置文件的手动选择 UI（Phase 13 COLOR-03）。多显示器：跟随窗口所在屏。
- **D-COL3:** 软打样**不在本阶段**（COLOR-02 归 Phase 13），但 terminal trio 的 colorout 抽象预留 output-profile 参数位（Phase 13 注入打印机 profile 即插即用）。
- **D-COL4:** EDR/HDR 预留：drawable 像素格式本阶段维持 `.bgra8Unorm`（Phase 1 已定），但 pixelpipe 输出端保持 float32 linear Rec2020 不截断——Phase 8 切 EDR 时只换 drawable 格式与 colorout 映射，管线不动。

### issue #1 修复纳入（Phase 2 前置）
- **D-X1:** JPEG 黑屏（多窗口呈现竞争 + renderDisplayTexture 时序）修复作为 Phase 2 第一个任务——它就在 pixelpipe 显示链路上，且修复涉及 renderDisplayTexture 与 .task(id:) 时序重构（load() 内已有渲染路径，EditorAreaView 的 .task 冗余渲染应移除，统一由 load() 的 decodeTask 渲染 + displayTexture 推送）。
- **D-X2:** drawable 回读探针、RENDER/DRAW/UPDATE 探针保留至修复验证后移除。

### the agent's Discretion
- pixelpipe 递归结构、ROI 协商 API 细节、缓存 hash 算法选型、terminal trio 的 Metal 实现细节——全部按 ARCHITECTURE.md 与 Phase 1 已验证模式（MetalContext 两层 dispatch）由 planner/executor 决定。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/PROJECT.md` — 锁定约束（linear Rec2020 float32 RGBA、v50_order、CIRAW=decoder、sidecar 自有格式）
- `.planning/REQUIREMENTS.md` — Phase 2 需求：FOUND-04、COLOR-01/04、HIST-01..04、RAW-03
- `.planning/ROADMAP.md` §Phase 2 — 成功标准 5 条 + 风险（CIRAW-4/5、METAL-1/2/4/5/7、NDE-1..4/6、COLOR-1/2、PERF-1/2）
- `.planning/phases/02-pixelpipe-core-color-management-history-stack/02-RESEARCH.md`（research 阶段产出后）
- `.planning/phases/01-foundation-app-skeleton-capability-spikes/01-CONTEXT.md` — Phase 1 全部决策（模块边界/签名/状态隔离继承）
- `.planning/phases/01-foundation-app-skeleton-capability-spikes/01-RESEARCH.md` — MetalContext 模式、CIContextPool bitmap 路径（render-to-texture 本机异常的绕行——Phase 2 需复查）
- `.planning/phases/01-foundation-app-skeleton-capability-spikes/spike-b-100mp-perf.md` — 缓存累积证据、clearCaches 硬需求、15.6ms 帧基线
- `/Volumes/UNITEK/Documents/Development/darktable/src/develop/pixelpipe_hb.c` (L1838/1893) — 递归 processRec + cache-hit 模式
- `/Volumes/UNITEK/Documents/Development/darktable/src/common/history.c` + `src/develop/blend.h` — history 身份元组
- `LESSONS.md` — L005（layers 从 pixelpipe 设计之初）、L008（encoder endEncoding 顺序）、L009（USB 卷 I/O）
- `AGENTS.md` — Swift/macOS 工程约定

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MetalContext`（public actor，两层 dispatch + PSO 缓存）— pixelpipe 的 dispatch 底座
- `CIContextPool`（internal actor，bitmap+replace 渲染路径）— Phase 2 需复查 render-to-texture 本机异常
- `PixelPipe` 骨架 + `RenderPipeline` public 桥（Plan 04）— 本阶段的核心扩展点
- `LayerStack`/`BackgroundLayer` 骨架 — pixelpipe 遍历入口已 layer-aware
- `RAWDecoder`/`DecodedImage` — pixelpipe 输入（含 decoderVersionUsed 戳）
- `V50Order`（93 条）— iop 排序表
- `PassthroughModule`（LightamerIOP）— pixelpipe 测试用 no-op
- 真机 RAW 样本：`input/RAW/`（2×Sony ARW + JPEG）、`.work/01-05/samples/`（13 份全制式）

### Established Patterns
- MetalContext 两层 dispatch（高层 dispatch2D / 低层 encoder session）
- bitmap+replace 渲染绕行（CIContext render-to-texture 本机写空——Phase 2 需复查直渲）
- 公共表面 headless 冒烟模式（.work/*/smoke.swift）
- os.signpost + Logger(subsystem com.kamasylvia.lightamer) 探针

### Integration Points
- `EditorState.load` → decodeTask 内嵌渲染（Phase 2 重构点：渲染路径统一，见 D-X1）
- `EditorMTKView` ← `displayTexture` Binding（issue #1 黑屏相关）
- sidecar 读写挂载点：`EditorState` history 栈 ↔ `Capture/` 目录 `.lra` 文件

</code_context>

<specifics>
## Specific Ideas

- 用户 NAS 上有真实 C1 Session（扫街/2025-08-25 淮海路，Capture/ 下 Sony ARW + .xmp）——Phase 2 验收可 Copy 样例到 input/RAW/（已建，gitignored），**绝不写 NAS 原目录**。
- JPEG 黑屏（issue #1）的教训直接塑造 Phase 2：渲染路径必须单一（load() 内），UI 层不冗余触发。
- Phase 1 spike 证明本机 CIContext.render-to-MTLTexture 写空（6/6 复现）——Phase 2 的多分辨率管线若需直渲，必须先攻破此问题或在 bitmap 路径上建多分辨率。

</specifics>

<deferred>
## Deferred Ideas

- 具名快照（named snapshot）— Phase 6（图层系统就位后）
- 软打样 UI — Phase 13（COLOR-02）
- 显示配置文件手动选择 — Phase 13（COLOR-03）
- .xmp 互通 — Phase 9 时按需评估
- tiling 完整实现 — 本阶段仅脚手架 + 档位量化
- render-to-MTLTexture 直渲复查 — Phase 2 内首个 spike 任务（D-X1 关联）

</deferred>

---

*Phase: 2-Pixelpipe Core, Color Management & History Stack*
*Context gathered: 2026-09-18（保活巡检以最佳判断定稿，YOLO 授权；用户可审阅推翻）*
