# Phase 3: Tone & Filmic iops - Context

**Gathered:** 2026-09-19
**Status:** Ready for planning — 决策由保活巡检以最佳判断定稿（YOLO 授权延续；用户可审阅推翻）

<domain>
## Phase Boundary

日常调色闭环：exposure、white balance（含吸管）、tonecurve（per-channel RGB）、shadow & highlight recovery、contrast、levels、tone equalizer + filmicrgb（scene-referred tone mapping，最难单移植）+ sigmoid 及其他 filmic 变体。10 项需求。

**Phase 3 不做**：蒙版（Phase 6——toneequal 仅全局 5-band）、色彩校准/通道混合器（Phase 5）、色彩管理变更（Phase 2 terminal trio 已就位）、UI 主题变更（UI-SPEC 已定）。

</domain>

<decisions>
## Implementation Decisions

### filmicrgb 移植策略
- **D-T1:** filmicrgb = **Darktable 完整移植**（scene-referred 数学逐段 verbatim：spectral → saturation → contrast/laters 子阶段各自独立 Metal kernel + golden 测试），不做简化版。理由：parity 是产品存在理由（LOCKED，ROADMAP 目标）；分解子阶段后每段可独立 golden 验证，整体复杂度可控。sigmoid 作为第二实现（较简单，先落作为 filmicrgb 的风险缓冲——若 filmicrgb 移植受阻 sigmoid 先撑 scene-referred 需求）。 — **Reversibility:** costly — scene-referred 数学是显示输出的语义基座。
- **D-T2:** 移植顺序 = **sigmoid 先行 → filmicrgb**（sigmoid 数学简单数倍，先建立 scene-referred tone mapping 的测试基线与 UI 面板，再攻 filmicrgb）。filmicrgb spike 结论（Phase 1 预研可行）由本阶段 golden 验证兑现。

### tone equalizer 交互模型
- **D-T3:** toneequal = **全局 5-band（无蒙版依赖）**进 Phase 3——Darktable 默认模式即为全局多频段（guidance/locallaplacian 分解），蒙版集成是 Phase 6 的事（蒙版系统就位后补 per-region）。guided filter Metal 移植为本阶段最难子项（大核 kernel 性能需 tiling 或分档降采样——TilingPlan 脚手架在此首次实战）。 — **Reversibility:** costly — 分解算法选型影响输出语义。

### 白平衡吸管
- **D-T4:** WB 吸管 = **viewport 点击采样**——EditorMTKView 点击 → 命中 PREVIEW 纹理坐标 → 读 linear Rec2020 值 → 中性色解（fin 常数色温/色调计算）→ 更新 WB 模块参数。Phase 3 UI 最小化：吸管按钮 + 光标十字（UI-SPEC 交互规范内）。

### Golden 参考输出（验收基建）
- **D-T5:** golden 参考 = **使用已构建的 darktable-cli**（`/Volumes/UNITEK/Documents/Development/darktable/build/bin/darktable-cli`，版本 1263552fab——与移植参考同源码树，已验证可执行）。流程：固定参数（XMP preset 或 CLI 参数）→ 对 torture set（Phase 1 采集的 18 份样本）生成参考 PNG → 存 `input/golden/`（gitignored，可由脚本再生成：`input/golden/regenerate.sh` 记录命令与参数）。Phase 3 各 iop 的 golden 测试对照这些参考。 — **Reversibility:** reversible — 参考可随时重生成。
- **D-T6:** Inspector 参数面板框架 = **Phase 3 建立首个真实 iop 参数面板**（UI-SPEC slider/section token 体系，每模块一面板，ModuleRegistry 驱动面板生成）。这是 D-03b InspectorState 的首个实际消费者。

### the agent's Discretion
- 各 iop 的 Metal kernel 分解策略、试验参数默认值、UI 面板内控件排布细节——按 Darktable 参考实现 + UI-SPEC 由 planner/executor 决定。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/PROJECT.md` / `.planning/REQUIREMENTS.md`（IOP-TONE-01..07、IOP-FILM-01..03）
- `.planning/ROADMAP.md` §Phase 3（成功标准 4 条 + 风险 METAL-6/7、NDE-3、COLOR-1/2、PERF-5）
- `.planning/phases/02-pixelpipe-core-color-management-history-stack/` — 02-CONTEXT/RESEARCH/SUMMARY（Phase 2 管线/缓存/history 全部产出）
- `.planning/phases/02-pixelpipe-core-color-management-history-stack/02-VALIDATION.md` — golden 双判据 harness（Phase 3 各 iop 复用）
- `.planning/phases/01-foundation-app-skeleton-capability-spikes/spike-b-100mp-perf.md`（性能基线）
- Darktable 源码（移植参考）：`src/iop/filmicrgb.c`（~2000 行 scene-referred）、`src/iop/sigmoid.c`、`src/iop/toneequal.c` + `src/iop/guidedfilter.c`、`src/iop/exposure.c`、`src/iop/temperature.c`、`src/iop/tonecurve.c`、`src/iop/shadhi.c`、`src/iop/levels.c`、`src/iop/contrast.c` + `data/kernels/` 对应 OpenCL
- `/Volumes/UNITEK/Documents/Development/darktable/build/bin/darktable-cli`（已构建，golden 参考生成工具）
- `LESSONS.md`（L006 sRGB gamma、L013 ParamsCoding、L010/L011）
- `AGENTS.md`（.swift+.metal 文件对约定、golden 测试硬约定）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `IOPModule`（Texture process）+ `ModuleBox` + `ModuleRegistry` + `PipeCoordinator` seams — 新 iop 的注册/接线全就位
- `PipeCache`（hash 链失效）+ `ParamsCoding`（sortedKeys 参数序列化）— 新模块参数即插即用
- `HistoryStack` + D-H1 drag-end 三件套 — 滑块拖动→history 提交链路现成
- `StableHash`、`TilingPlan` 脚手架（toneequal/guidedfilter 首个实战场景）
- golden 双判据 harness（Phase 2）— Phase 3 各 iop golden 复用扩展
- 真机样本：input/RAW/ + .work/plans/01-05/samples/（18 份）

### Established Patterns
- `.swift + .metal` 文件对（AGENTS 约定）、MetalContext dispatch、os.signpost 探针
- darktable-cli golden 参考（本阶段新建）

### Integration Points
- 新 iop → ModuleRegistry 注册 → v50_order 插入 → PipeCoordinator 面板生成
- Inspector 参数面板 → D-H1 drag-end → history commit → 缓存失效链

</code_context>

<specifics>
## Specific Ideas

- filmicrgb 是 ROADMAP 标注的最难单移植（~2000 行 scene-linear 数学）——分解为子阶段逐段 golden 是成败关键。
- sigmoid 先行策略降低 scene-referred 一次性风险。
- toneequal 的 guided filter 需要 TilingPlan 首次实战（大核 kernel 内存压力）。
- 60fps 拖动预算：Phase 1 spike 15.6ms@102MP 余量 <1ms——tone 模块 kernel 需在 PREVIEW 管线内保持轻量（PREVIEW 2560px 桶）。

</specifics>

<deferred>
## Deferred Ideas

- 蒙版集成（toneequal per-region）— Phase 6
- 色彩校准/通道混合器/色彩 zones — Phase 5
- 显示配置文件手动选择 — Phase 13
- camera-neutral 默认自动化（auto-WB）— 按需评估

</deferred>

---

*Phase: 3-Tone & Filmic iops*
*Context gathered: 2026-09-19（保活巡检自主定稿，YOLO 授权延续）*
