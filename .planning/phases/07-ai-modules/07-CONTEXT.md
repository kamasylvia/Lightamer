# Phase 7: AI Modules (Native Vision Masking & Retouching) - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning — 6 项 Open Questions 全部经用户裁决（2026-09-24 确认，D-07-CONTEXT-1..6）；Phase 6 移交清单四条已逐条对位（06-DISCUSSION-LOG 终节 ↔ 07-RESEARCH §3）

<domain>
## Phase Boundary

全项目最小功能阶段：4 项需求（AI-01/05/06/07），却是**第一个消费 Apple ML 推理的阶段**——与 Phase 2-6 的"纯确定性像素数学"范式分界（验证策略随之从 dt parity 轨切换为 L017 分流的 AI 变体：确定性门 + 合成语义门 + 自研 float64 parity，见 07-RESEARCH §6）。核心架构事实：

1. **AI 是蒙版/定位的生成器，不是编辑语义**——生成瞬间 bake 为 raster PNG（`.lra.masks/<maskID>.png`），之后进入与手画蒙版完全相同的 Phase 6 编辑/合成/持久化世界；AI 生成参数（qualityLevel/seeds/refine 点）**不持久化进 sidecar**（避免 schema 再升级 + 架构裁决一致）。
2. **Phase 6 移交面零改动承接**：`RasterMaskStore.bake`（`RasterMaskStore.swift:74`）本就接受任意 r32Float 平面；版本化（同 maskID 重 bake → `maskHash`/`stableHash()` 翻转 → 缓存链自动失效）无需新机制；不新增缓存类（推理产物以 maskPlane/layerPlane 级进入既有缓存）。
3. **Phase 7 唯一新蒙版原语 = raster 腿羽化**（bake 管线内单通道 mask blur，`MaskPostProcessKernels.metal` 已有同款 kernel 接到 bake 入口）；skinSmooth 唯一新 iop（V50Order 66.5 非 dt 首例行）。

**Phase 7 不做**：

- **parametric 语义曲线预设**（landmarks → 肤色 hz 4 点曲线，dt `channelmixerrgb.c:1796-1797` hue 角参考）— D-07-CONTEXT-3，v2（REQUIREMENTS AI-06 注记）
- **scribble/lasso 手势**（tap-to-segment v1 只做 tap 含/排点 + box）— D-07-CONTEXT-4，v1 后（plan 内注记升级缝：`seedScribbleBuffer` init 与数据腿 v1 不接）
- **多尺度小波磨皮 / bilateral 边缘感知变体**— D-07-CONTEXT-6，v2（SkinSmooth 参数 enum 位预留）
- **`VNGeneratePersonInstanceMaskRequest` 人像 per-instance 后端**— 层 A 已覆盖人（instance 区分够用），v1 不接（07-RESEARCH §1.1）
- **AI-02 天空 / AI-03 人像部位 / AI-04 通用语义分割**— L004 边界，v2 AIV2（需自定义 Core ML 模型）；保持 pluggable segmentation 接口形态，v2 高保真后端可换（ROADMAP Notes 口径）
- **AI 生成参数进 sidecar / AI mask 黑盒引用形态**— 永不（AI-07 红线：生成即 bake）
- **推理结果跨 device（ANE vs CPU）逐字节恒等承诺**— 只承诺同 device 恒等（07-RESEARCH Risks 8）
- **.xmp 读写 / dt parity 轨 A 对 AI 输出**— 永不（模型输出不可逐字节 golden；dt 无 AI 磨皮对照）
</domain>

<decisions>
## Implementation Decisions

> 6 项 = 07-RESEARCH Open Questions 全部经用户裁决（2026-09-24 确认，均采纳推荐项）。本节逐条记录裁决 + 理由 + 可逆性；SC#5 措辞修订与 REQUIREMENTS AI-06 注记已随本批同部落定。

### D-07-CONTEXT-1: 主体蒙版双层共存（层 A 离线 + 层 B 交互精修 + 模型下载门控）
- **裁决**：层 A = `VNGenerateForegroundInstanceMaskRequest`（macOS 14+，OS 内置模型、无下载前置、完全离线）承担**离线兜底 + 一键全自动**；层 B = `GenerateIterativeSegmentationRequest`（macOS 27，WWDC26/237 tap-to-segment）承担**tap/box 交互精修**，遵守 `DownloadableAssetsRequest`——**首次使用需一次性模型下载**。落地三件：①首启预下载提示（用户同意后后台 `downloadAssets`，拒绝则层 B 按钮置灰引导、层 A 全程可用）；②双后端自动回落（层 B assetStatus 未就绪时层 B 入口禁用，层 A 不受影响）；③**ROADMAP §Phase 7 SC#5 措辞同步修订**为「层 A 离线可用，层 B 首次使用需模型下载」（随本批已改）。
- **理由**：弃层 B = 放弃 SC#1 "iterative refinement usable interactively" 半句（macOS 27 floor 的核心增益之一）；弃层 A = 首次必联网且无全自动兜底；双后端共存是唯一同时满足离线声明主体 + 交互精修的形态。层 A/personSeg/faceLandmarks 均 OS 内置，离线主体声明保持真。
- **Reversibility**: reversible——两层各自独立封装于 AIMaskService，弃一层不影响另一层。

### D-07-CONTEXT-2: skinSmooth 落位独立 iop @ V50Order 66.5 新行（dt verbatim 表插非 dt 行 = 项目首例）
- **裁决**：`skinSmooth` 为独立 iop，V50Order 新行 **66.5**（soften 66.0 与 splittoning 67.0 之间，模糊/creative 族邻域、RGB 段）；**V50Order 表头注释标记「非 dt 行（Phase 7 skinSmooth）」**，沿用 dt 不可重排/唯一性纪律（新行只增不改，sidecar order 自 Phase 2 携带，向后兼容）。
- **理由**：备选「AI 面板组合预设」（soften+highpass 双层凑）频率分离数学凑不齐、阈值衰减防塑料感做不了（衰减是单 kernel 内按 |high| 分段，跨两层组合无法表达）；备选「层 kind（retouch 同款）」磨皮不是 stroke 系统不符；「hack 复用 soften 槽」混淆语义（否决）。磨皮层形态两态皆合法（base 链配 raster skin mask / 调整层 chain 配层 mask，`ModuleInstance` 同构），**默认推荐 = 调整层**（C1 语义：磨皮是可整层开关的局部修复步骤）。
- **Reversibility**: reversible——槽位是表内一行 + 模块注册，不破坏既有行。

### D-07-CONTEXT-3: AI-06 v1 只走 raster 烘焙通道；parametric 预设留 v2
- **裁决**：v1 AI mask 消费**唯一通道 = raster 烘焙**（`AIMaskService` 产 r32Float 平面 → `RasterMaskStore.bake` → `MaskSpec.raster`，继承 Phase 6 全部蒙版编辑/版本化/round-trip 能力）。REQUIREMENTS AI-06 行注记「像素 mask 走 raster 烘焙；parametric 语义曲线预设留 v2」（随本批已加）。
- **理由**：Vision mask 是**像素**不是参数曲线——"直接作为 parametric mask"（REQUIREMENTS 原措辞）的工程忠实通道只有 raster；parametric 腿的 AI 用途只能是从地标拟合的语义曲线预设（肤色 hz 4 点曲线），属可选增强非忠实投影，不与像素 mask 混通道交付。
- **Reversibility**: reversible——parametric `MaskSpec.parametric` 输入面 Phase 6 已就绪（06-04 交付），v2 预设生成器直接挂。

### D-07-CONTEXT-4: tap-to-segment v1 范围 = tap 含/排点 + box；scribble/lasso 后置
- **裁决**：v1 交互 = **单击 seedPoint / addIncludedPoint + ⌥·右键 addExcludedPoint + ⇧拖 box（seedBox）**；scribble（`seedScribbleBuffer`）与 lasso 手势留 v1 后。plan 内注记**升级缝**：LayerEditingState 第 4 编辑模式的种子类型枚举预留 scribble case（数据腿/手势 v1 不接），后续交付免状态机重构。
- **理由**：点击是修图主力交互（点选/排点覆盖 SC#1 "usable interactively" 主体）；scribble buffer 构造 + lasso 线宽 UI（WWDC26/237：线宽 ≥ 图宽 1%）成本 +1T 且属锦上添花。
- **Reversibility**: reversible——升级缝即扩展点。

### D-07-CONTEXT-5: 迭代精修版本策略 = 同 maskID 覆盖重 bake
- **裁决**：每次生成/精修 = 同 `<maskID>.png` 覆盖重 bake（`RasterMaskRef.maskHash` 随 PNG 字节变 → `MaskSpec.stableHash()` 派生哈希变 → mask plane 缓存与前缀链正确失效，Phase 6 机制自动接管）；**不做**版本递增多文件保留。
- **理由**：无孤儿文件、无清理逻辑；精修历史可考古性由 history 的 `stackSnapshot` 结构项承载（每次精修一条，点列/引用非像素、体积可忽略）。
- **Reversibility**: reversible——如需考古多版本，改 fileName 生成规则即可。

### D-07-CONTEXT-6: 磨皮数学 v1 = 两频高斯分离 + 阈值式高频衰减；多尺度小波留 v2
- **裁决**：`low = GaussianBlur(I, σ_spatial)`（既有件 Deriche IIR 直接复用作低频腿）+ `high = I − low` + 阈值式衰减 `attenuate(h) = |h| ≤ t ? h·(1−m·a)·k_soft : h`（低幅高频=色斑/噪点强衰减、高幅高频=毛孔边缘/发丝保留——**防塑料感的关键**）+ skin mask 空间限定。分解域 = linear Rec2020 RGB 三通道独立（与 soften 同域先例）。多尺度小波（dt diffuse 式）与 bilateral 边缘感知变体留 v2，**参数面预留 enum 变体位**。
- **理由**：两频是 Photoshop 对标基线（参数面 3 滑块：radius/strength/detail-preserve）；多频参数面复杂 +1T 且 v1 无对照验证需求。
- **Reversibility**: reversible——kernel 结构按变体 enum 分派预留。

### 继承定案（非 OQ，RESEARCH 已论证、下游不得重开）

- **推理输入 = 解码帧（demosaic 后、无编辑）**：mask 语义内容锚定（贴"照片里的主体"非"调整后的主体"），与 Phase 6 内容锚定坐标系（`MaskSpec.swift:7-11`）同构；构造走 IOSurface-backed `MTLTexture` → `CVPixelBuffer` → `CIImage`/`perform(on:)` 零拷贝路径，跨队列先 fence（**L014 红线**）。
- **推理走后台 Task + ANE 优先**（`setComputeDevice(MLComputeDevice?, for:)` + `supportedComputeStageDevices` 运行时枚举），与 Metal pipe 无帧内耦合（PERF-1 对策：推理是"生成蒙版"一次性动作，非拖动热路径）；**测试 pin CPU device 保跨机器确定性**。
- **生成失败 ≠ load 失败**：推理失败/nil observation/模型未下载 → UI 报错 + 不落 mask（不是降级全一平面——那会静默毁蒙版语义；全一平面是 load 三失败腿的既有语义，两者严格区分）。
- **mask 上整形**：`generateScaledMaskForImage` 直接产原分辨率（层 A 首选）；层 B 分辨率由 `qualityLevel` 决定（`.accurate` 起步），仍低于解码帧则 bake 入口独立**双线性**上采样（**不用 nearest**——`RasterMaskStore.load:129-132` 的 per-scale resample 是已 bake 高分辨率 PNG 的跨 scale 缩小口径，不变；低清 AI mask 直接 nearest 会块状化）；羽化 = bake 管线内单通道 Gaussian（半径 = 面板滑块）。
- **坐标红线**：Vision 归一化坐标**原点左下**——交互传点 Y 翻转（`y_vision = 1 − y_view_norm`）单测常驻；mask buffer 与输入像素对齐（行 0 = 图顶）无需翻转，上采样对齐断言兜底。
- **点数上限 13/11**（point/scribble 种子 13、box 种子 11）：UI 计数器 + 满禁点；`addIncludedPoint` throws 超限接错误呈现（不崩不静默）。
- **AI-01 不占 iop 槽**（mask 生成器服务，产出 raster 资产非像素变换）。
- **执行纪律增量（AGENTS.md 2026-09-24，Phase 7 起强制）**：`.work/PAUSE` 暂停机制（subagent worker **每任务边界检查**——任务收尾 commit 后、下一任务开工前）+ C 档门控三点停（研究定稿停【已过】/ 每 plan 闭环停 / 签核前停）；omp 执行模型照旧（L019b 直启单测 + L022 零写入）。

### 验证与 GUI 红线（全 plan 写死，执行期不得放宽）

- **防空转**：AI 语义门必须带**方向断言**（合成图 IoU ≥ 0.9 / 背景区 ≤ 0.1 / excludedPoint 后主体内 mask 下降），禁"存在输出即过"（06-VERIFICATION 内容级抽查口径）；确定性门 = 同输入同 device 两次推理 mask 逐字节恒等（进程内 + 跨进程）。
- **确定性门前提**：Vision 测试一律 `setComputeDevice` pin CPU（`supportedComputeStageDevices` 枚举断言含 CPU）——跨机器 golden 稳定前提；运行时不做跨 device 恒等承诺。
- **频率分离数学**：float64 Swift 参考 parity <1e-5（03/06 定式）+ **恒等三元组**（a=0 逐字节恒等 / mask 空 no-op / 平场恒等——任何 DC-1 blur L017-proof）。
- **hull 几何 = 纯 Swift 解析，不跑模型即可单测**（合成点列恒等断言：hull 内=1 / 保护区=0 / 羽化带 Gaussian 剖面）。
- **GUI 红线**：蒙版生成可视化 = overlay 截图量化（06-03 ΔR 口径，FINDINGS 落账）；磨皮质感与 tap 手感 = Manual-Only 表登记（L011）；全部 AI 按钮 L010 identifier 全量；面板四件套（L010 + zh/en catalog【zh 标签，L025】+ 280pt Inspector 约束 + D-H1 三件套）+ `PanelWiringTests` 扩展。
- **GUI 复验**（AGENTS.md 硬性项）：真实 RAW 端到端（生成蒙版 → 编辑蒙版 → 磨皮 → ⌘Z 回退链）+ PLAYBOOK 量化 + Manual-Only 表。
- **缓存/ROI 红线**：推理腿不新增缓存类（maskPlane 级产物进既有缓存）；L021 层维度 stamp 断言不受影响（AI mask 只改 MaskSpec 不改 walk）。
- **性能**：Vision benchmark 基线落 `.work/07/perf.md`（07-1 首任务钉基线，只记录不设门；SC#5 门 = 单次生成 ≤1s plan 期按实测分布定）；bake 100MP 内存峰值 Instrument 记账，超预算分块读回。
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/07-ai-modules/07-RESEARCH.md`（正本：§1 双层 API + 烘焙管线、§2 频率分离数学 + hull 几何、§3 消费通道对位、§4 非黑箱三面、§5 性能、§6 golden 表、§7 v50 槽位、§8 UI、Risks 1-10）
- `.planning/phases/06-layers-masking/06-DISCUSSION-LOG.md` 终节（Phase 7 移交清单四条：raster 烘焙入口 / 层栈 API 面 / mask 版本化 / pipe 缓存面）+ `06-VERIFICATION.md`（14/14 交付基线 + Manual-Only 5 项挂账）+ `06-07-SUMMARY.md`
- `.planning/ROADMAP.md` §Phase 7（SC#1-5——**SC#5 已按 D-07-CONTEXT-1 修订**；PERF-1/NDE-1/NDE-3 风险）；`.planning/REQUIREMENTS.md` AI 节（AI-01/05/06/07 正本——**AI-06 已注记 raster 口径**）
- 本机 macOS 27 SDK：`.../MacOSX27.0.sdk/.../Vision.swiftmodule/arm64e-apple-macos.swiftinterface`（`GenerateIterativeSegmentationRequest` `:1700-1766` 快照——**07-1 动工前复核一遍**，beta 期 API 漂移风险）+ Apple 文档（07-RESEARCH Sources 节 URL 全表）
- `LESSONS.md` L004（AI 原生边界）/L009（卷慢态）/L010（identifier）/L011（Manual-Only）/L013（折叠哈希）/L014（跨队列 fence）/L017（golden 分流）/L018（IIR RMW）/L020（内容级断言）/L021（GUI 验收红线）/L022（omp 零写入）/L023（半边契约）/L025（String Catalog zh 标签）
- `AGENTS.md`（Phase 执行模型 + **暂停机制（2026-09-24：PAUSE 文件 + 任务边界检查 + C 档门控）** + Conventions）
- `.work/gui-acceptance/PLAYBOOK.md`（GUI 验收操作口径 §0-§6）；`TODO.md`（Phase 6 挂账 + Phase 7 计划行）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets（07-RESEARCH §Sources 现码 file:line 核过）

- **蒙版消费端（Phase 6 交付，零改动承接）**：`LightamerCore/Sources/Layers/Masks/MaskSpec.swift:239-299`（三 payload + `stableHash()`）+ `RasterMaskRef.swift:20-37`（fileName/maskHash decimal-String lock/invert）+ `Sidecar/RasterMaskStore.swift:46-101`（masksDirectory/bake——接受任意 r32Float 平面）/`:104-147`（load 三失败腿 + per-scale nearest resample）+ `MaskCombiner.swift`（effectivePlane 三 payload ⊗ 装配）。
- **层栈 API 面**：`LayerStack.swift:91-184`（mutation 全套）+ `LayerCompositeDriver.swift:69-98`（1+N+1 编排 + kind 分派）+ history 双轨（layerScope / `__layerStack__`）——AI 生成蒙版 = 一次 stackSnapshot 结构写，⌘Z 可退（LayerUIWiring 同款语义）。
- **频率分离基座**：`LightamerIOP/Sources/Common/GaussianBlur.swift` + `GaussianBlurKernels.metal`（Deriche IIR 双 pass + 双缓冲，L018 合规——skinSmooth 低频腿直接复用）；`Highpass/HighpassModule.swift:19-21,134-149`（σ/halo 公式 + 分解→mix 结构参照）；`Soften/SoftenModule.swift:24-30`（RGB linear mix 先例）；`Bilateral/` + `Common/BilateralGrid3D.swift`（v2 边缘感知变体扩展位）。
- **羽化增件参照**：`LightamerIOP/Sources/Masks/MaskPostProcessKernels.metal`（单通道 mask blur/feather kernel——bake 入口羽化直接接）。
- **注册/槽位面**：`LightamerCore/Sources/Foundation/V50Order.swift:1-15`（dt verbatim 表头纪律 + soften 66.0/splittoning 67.0 邻域）+ `LightamerIOP/Sources/Registry.swift`（模块注册 + seed enabled-neutral 先例 `:412-416` liquify）。
- **UI 面**：`MaskToolbarView`（AI 组挂点）+ `LayerEditingState`（编辑模式互斥状态机——mask>liquify>retouch>crop，第 4 模式插位）+ `IOPPanelProvider`（24 面板注册面）+ `InspectorState.swift` 工厂分发。
- **测试基建**：`ParityGate` 双闸、`PanelWiringTests`、`RasterMaskRoundTripTests`（bake→load 恒等同款扩展）、`DrawnMaskRasterTests`（羽化剖面断言模式）、`LayerE2ERoundTripTests`（真 RAW 渲染逐字节）、轨 B 全链（Phase 3+4+5+6 全模块零增量基线）。

### Integration Points（Phase 6 移交四条落位）

| 移交面 | Phase 7 落位 |
|---|---|
| ① AI mask 消费端接口 | 07-1 T4（bake 接线——raster 主通道唯一） |
| ② 层栈 API 面 | 07-3 T1/T4（生成蒙版挂选中层 mask 槽 + stackSnapshot 回退链） |
| ③ mask 版本化机制 | 07-1 T4（同 maskID 覆盖重 bake，D-07-CONTEXT-5）+ 07-3 T4（refine 重生成验证） |
| ④ pipe 缓存面 | 全程不新增缓存类；07-2 轨 B（skinSmooth 中性插链零增量）+ 07-3 T4（编辑互不扩散回归） |

</code_context>

<specifics>
## Specific Ideas

- **执行顺序刚性**：07-1（基建 + AI-01，benchmark 首任务钉基线）→ 07-2（skinSmooth，依赖 07-1 的 AIMaskService 皮肤腿）→ 07-3（集成精修 + GUI + 终签核）。纯串行（parametric 预设并行项已裁决 v2 消失）。总量 ~15-16 T。
- **C 档门控**：每 plan 执行+验收闭环后停（汇报战果 + 下一 plan 摘要，等用户确认）；Phase 7 签核前停（verify-work 结论过目）。subagent worker 每任务边界查 `.work/PAUSE`。
- **07-1 首任务 = SDK 复核 + benchmark**（RESEARCH §5 定为首任务）：动工前用本机 swiftinterface 复核 `:1700-1766` 快照（beta 漂移）；100MP GFX RAF + 24MP 常规帧 × 层 A/层 B/personSeg/faceLandmarks × fast/balanced/accurate × ANE vs CPU 实测落 `.work/07/perf.md`——SC#5 单次生成 ≤1s 的门按实测分布定（执行期决策，落 DECISIONS）。
- **AIMaskService = Core 级新 `AI/` 目录**（`LightamerCore/Sources/AI/`——服务不依赖 UI，可进单测；App 层只挂按钮/进度）。层 A/B/皮肤腿共用 handler 封装 + fence + 后台 Task 骨架。
- **skinSmooth 的 mask 来源 = 该层 mask 槽的 raster 腿**（AI 生成 skin mask bake 挂层，与 §4 非黑箱同机制）——module 参数面只有 radius/strength/detail-preserve 三滑块 + 变体 enum 预留位，mask 不进 iop 参数（mask 本就是层属性，Phase 6 模型）。
- **AI 按钮三态门控统一走 assetStatus 状态模型**（07-1 交付状态机 + 首启预下载提示，07-3 挂 MaskToolbar 消费）。
- **历史项边界**：AI 生成蒙版 = stackSnapshot 结构项（一次生成一条）；skinSmooth 参数编辑 = layerScope 参数项（D-H1 三件套）——与 Phase 6 双轨同构，不发明新 history 形态。

</specifics>

<deferred>
## Deferred Ideas

- **parametric 语义曲线预设**（肤色 hz 4 点曲线 + luma 范围，dt hue 1.0 rad 参考）— D-07-CONTEXT-3，v2
- **scribble/lasso 手势**（seedScribbleBuffer + lasso 线宽 ≥1% 图宽 UI）— D-07-CONTEXT-4，v1 后（升级缝：种子类型枚举预留）
- **多尺度小波磨皮 + bilateral 边缘感知低频腿**— D-07-CONTEXT-6，v2（enum 位预留）
- **`VNGeneratePersonInstanceMaskRequest` 人像 per-instance 后端**— v1 不接（层 A 覆盖）
- **层 B 模型预下载的静默后台化**（首启提示 vs 完全静默策略）— v1 = 提示制（D-07-CONTEXT-1），静默化 v2 按用户反馈
- **AI-02/03/04 + 高保真自定义模型后端**（pluggable segmentation 接口保持，v2 AIV2）
- **推理中间态缓存**（重生成 = 用户主动，无缓存需求）— 不做

</deferred>

---

*Phase: 7-AI Modules (Native Vision Masking & Retouching)*
*Context gathered: 2026-09-24（planner 裁决定稿；6 项 Open Questions 用户已确认——D-07-CONTEXT-1..6 全部落定，SC#5/REQUIREMENTS 注记同批同步）*
