# Phase 6: Layers & Masking System - Context

**Gathered:** 2026-09-22
**Status:** Ready for planning — 8 项 Open Questions 全部裁决（采纳 06-RESEARCH 推荐；既定授权模式：推荐可逆且已论证，可审阅推翻）

<domain>
## Phase Boundary

全项目最大架构阶段：14 项需求（LAYER-01..07 + IOP-MASK-01..05 + IOP-GEO-05/06）。架构裁决（06-RESEARCH §1）= **混合模型 (c)：C1 层栈为用户/数据模型，dt blendop 数学为合成引擎**——每层 = 一条独立 iop 子链（复用 `IOPModule`/`ModuleBox`/`PixelPipe` 全套机制，子链即一个 pixel run），层合成 = dt `dt_develop_blend_process`（blend.c:458 的 a=下层合成/b=本层输出）直译的 `LayerCompositeDriver`；**Phase 2-5 的 pipe walk / 缓存 / ROI / tiling 零改动**——层维度活在 walk 之上。合成 seam = base 链末端（colorout 显示尾之前）的 working space 平面；run 结构 = base 子 run → 逐层（自下而上）「本层子 run → blendop 三元组合成」→ 终端段（colorout→gamma）子 run。

**Phase 6 不做**：

- 层内几何模块（D-06-CONTEXT-5——lens 13/ashift 15/flip 16/clipping 17 仅 base 层）
- 层编组文件夹（D-06-CONTEXT-6 defer v2；蒙版组由 MaskGroup 内嵌套 form 承载）
- parametric mask 双域 UI（D-06-CONTEXT-3——v1 单 kernel：luma + JzCzhz）
- per-module 独立蒙版（模型裁决 (b) 已双重否决——05-08 移交项 1 的 colorbalancergb mask_display 棋盘预览以「选中层蒙版 overlay 显示」承接，6-3 交付）
- AI mask 生成（Phase 7 消费本 Phase 的 raster 烘焙/parametric 输入接口——AI-06/07）
- PS gamma 编码域混合变体（v1 钉 dt 线性域语义，parity 可验证；观感调优后续选项，06-RESEARCH §4.2 头注记录）
- .xmp 读写（永不做——Conventions ONE-WAY）
- rgbcurve/rgblevels stretch（42.0/43.0 槽位在表，维持 D-05-CONTEXT-1「Phase 6+ 可选补齐」口径，非本 Phase 承诺）
</domain>

<decisions>
## Implementation Decisions

> 全部采纳 06-RESEARCH 推荐。授权依据：既定授权模式——推荐可逆且 RESEARCH 已逐项论证（dt 源码 file:line 实证 + 既有件现码对照）；本节逐条记录裁决 + 理由 + 可逆性。**D-06-CONTEXT-2 为 6-1 动工前必拍板项，本轮定案。**

### D-06-CONTEXT-1: liquify/retouch 不正式拆 Phase 6.5；heal 可降级
- **裁决**：liquify 与 retouch **保持 Phase 6 尾部独立 plan（6-6/6-7）**，不另立 6.5 里程碑。retouch 的 **heal 迭代核可降级**：6-7 交付 retouch 层 kind + stroke 框架 + clone/blur/fill 三腿；heal 若 plan 期基准实测超交互预算（100MP 窗口化 patch 场景），拆 6.5b 独立后续 plan，判定落 DECISIONS + 用户确认。
- **理由**：① mask/变形框架就位后两者独立可签核，不阻塞层核主线；② dt 3774+4891 行中 UI/交互占大头，计算核心已定位（liquify ~500 行 / heal ~800 行），单 plan 体量可控；③ heal 是 retouch 四算法中唯一有迭代收敛不确定性的（max_heal_iter 2000 + early-exit 读回），降级路径清晰且 clone/blur/fill 已覆盖主工作流。
- **Reversibility**: reversible——降级只影响 6-7 内一个任务边界，框架先行不返工。

### D-06-CONTEXT-2: BlendMode 值错位处置——值不重编 + 语义按 dt MODERN + 头注映射表（6-1 前必拍板，本轮定案）
- **裁决**：Phase 1 骨架 `BlendMode.swift` 的 13 个冻结 raw 值**不重编**。语义按 dt MODERN 现代公式实现：`normal = 0x01`（实为 dt `NORMAL_OBSOLETE` 槽位，blend.h:47）**实现 NORMAL2 现代公式**（`o = a·(1−op) + blend(a,b)·op`，无 clamp 旧版行为）；`colorDodge = 0x16`（实为 dt `COLORADJUST`「只混入调整色」模式）**实现 COLORADJUST 公式**，case 更名 `colorAdjust`；真 PS color dodge/burn 另开**新 raw 值**增补（W3C Compositing-1 公式，6-2 交付）。`BlendMode.swift` 头注更新为三方映射表：**raw 值 ↔ dt 枚举槽位 ↔ 实际实现语义**。
- **为何不重编（四条）**：
  1. **sidecar ONE-WAY 格式锁**（Phase 2 约定 + AGENTS.md Conventions）：raw 值自 Phase 2 起进每一个 `.lra`，重编 = 破坏全部已写文档的解码，需迁移器——违背「ONE-WAY 格式锁」本意（格式只进不退，值语义在读写两端解释）。
  2. **Phase 1 冻结承诺在案**：`BlendMode.swift:5-9` 头注明言 FROZEN、never renumber—— planner 层面推翻冻结的成本（信任 + 全量回归）大于收益。
  3. **dt 自身先例**：dt 枚举槽位跨版本换公式是常态（NORMAL→NORMAL2 演进 + `DEVELOP_BLEND_VERSION=14` 版本化机制 blend.h:31 的存在理由）——「槽位 ≠ 公式」本就是 dt 语义，存储值只标识用户意图槽位，行为由实现版本定义。
  4. **用户预期无损**：需要真 PS color dodge 语义的场景由新 raw 值满足（增补永不重编，`BlendMode.swift:43-46` 既有纪律）；`normal` 的 NORMAL2 公式正是现代 PS normal 的等价物，无行为损失。
- **case 更名安全性**：`BlendMode: Int, Codable` 编码走 rawValue 整数，case 名不进盘——更名 sidecar 安全（执行期核 decoded JSON 逐字节不变回归钉住）。REVERSE 位 `0x80000000`（blend.h:89）按 `BlendMode.swift:11-13` 预告采纳 OptionSet 位。
- **任务落位**：头注映射表 + 更名 + REVERSE 位 = 6-1（T1）；全部公式（NORMAL2/COLORADJUST/新 dodge/burn）= 6-2。
- **Reversibility**: reversible——若未来确需与 dt raw 值逐 case 严格同义，可走「弃用 0x01/0x16 + 新值 + sidecar 迁移器」，但本项目不采用（上述四条）。

### D-06-CONTEXT-3: parametric mask v1 单域（luma + JzCzhz 单 kernel）
- **裁决**：v1 parametric mask 域 = **luma + JzCzhz 两通道族、单 kernel**（`blendop_mask_rgb_jzczhz` blendop.cl:1096-1309 直译 + luma 腿）；不做 dt 双域 UI（Lab + RGB 各一套曲线面板）。
- **理由**：① 一个 kernel 覆盖 LAYER-03/IOP-MASK-02 的「亮度/颜色范围选择」语义；② JzCzhz 常量与 filmic/cb 链同源（YrgGamut/JzAzBz 既有矩阵），无新增色度面；③ dt 双域 UI 是历史包袱（Lab 域先于 RGB scene 域存在），对 Lightamer 单工作域架构无收益。
- **Reversibility**: reversible——域枚举留扩展位，双域 UI 后续独立补。

### D-06-CONTEXT-4: retouch 落位独立图层 kind（非 base 链模块）
- **裁决**：retouch = **独立层 kind（`LayerKind` 扩展）**，其「iop 链」= stroke 列表（单一参数体），复用层容器全套（可见性/蒙版/混合免费获得）；不走 dt base 链模块原样（retouch.c 的 iop_order 20.0 槽位保留在 V50Order 表作参考，不消费）。
- **理由**：① C1 语义（heal/clone 是独立「修复层」，可整体隐藏/删除/重排）；② 多层修复栈是常见工作流；③ stroke 形状即该层自带 mask（dt `NO_MASKS` 同语义，retouch.c:221），v1 不再叠加 parametric mask（后续可加）。
- **Reversibility**: reversible——层 kind 与模块化实现数据同构，迁移成本可控。

### D-06-CONTEXT-5: 层内几何模块 v1 禁用
- **裁决**：v1 调整层只许恒等 ROI 模块；lens 13/ashift 15/flip 16/clipping 17 等几何模块**仅 base 层**可启用（UI 对层内几何隐藏或只读）。
- **理由**：① 层内几何使跨层 ROI 协商复杂度陡增（每层帧变换不同，L020/L021 教训放大 N 倍）；② C1 同口径（adjustment layer 不承载几何）；③ 蒙版内容锚定的映射器（§2.3）假设「几何只在 base 链」——放开即推翻 6-3 的映射器设计前提。
- **Reversibility**: costly——放开需重做跨层 ROI 协商 + 映射器泛化，v2 论证。

### D-06-CONTEXT-6: 层编组（文件夹）defer v2
- **裁决**：LAYER-04 的「编组」v1 不做层文件夹；蒙版组由 MaskGroup 内嵌套 form 承载（IOP-MASK-04），层编组 defer v2。
- **理由**：层文件夹是纯 UX 组织，不产生新管线语义；merge 向下（破坏性、history 可退）v1 交付已覆盖 LAYER-04 主体；MaskGroup 已覆盖「组」的操作语义需求。
- **记账**：REQUIREMENTS LAYER-04 行签核时注记「编组=v2、合并向下=v1 交付」。
- **Reversibility**: reversible——层记录可加 parentID 字段（optional 非破坏）。

### D-06-CONTEXT-7: 蒙版坐标内容锚定（dt 模型），映射器精度不足时降级需用户认可
- **裁决**：蒙版点列以**全解码帧归一化坐标**存储（dt 同口径），合成时光栅化经 `GeometryPointMapper`（base 链几何段逆序复合 + liquify 位移场逆采样）换算——**内容锚定**（crop/rotate 后蒙版跟随图像内容）。若 plan 期（6-3）实测 lens/ashift 逆向点映射精度不足，降级方案 = 蒙版钉「合成平面坐标」（所见即所得，crop 后蒙版随帧不随内容）——**语义降级必须经用户认可，不静默切换**。
- **理由**：dt/C1 都是内容锚定；合成平面锚定在 crop 变更后产生「蒙版漂移」的可感缺陷。映射器的五个几何模块点映射均为 Swift 侧已有矩阵/系数的增量 API（04-03/04-04 已核），风险可控。
- **Reversibility**: reversible（降级方向）／costly（回内容锚定需补映射器）——先难后易。

### D-06-CONTEXT-8: FULL 冷层缓存政策——窗口化 + 冷层不缓存，benchmark 后回退
- **裁决**：100MP FULL = **窗口化 O(视窗)**（roiHint 子域渲染对每层子 run 生效）+ **冷层链输出不缓存**（只缓存当前编辑热层链输出 + 前缀；合成即弃、仅缓存最终）；PREVIEW/THUMBNAIL 照旧缓存全层。若 6-5 benchmark 实测 fit 视图（无窗口）N 层全幅重渲超预算，**回退「FULL 也缓存层输出」**并把 FULL 平面预算入 `PipeCache.enforceBudget` 分档——数据驱动决策，结论落 DECISIONS + `.work/06/perf.md`。
- **理由**：fit 视图 FULL 每层链输出 1.63GB，全缓存即 2N 平面必然破预算；窗口化后每平面 ~几十 MB 且交互场景（缩放查看）天然带视窗。回退路径成本 = 一个 policy 常量 + enforceBudget 分档（6-1 已建骨架）。
- **Reversibility**: reversible——缓存政策是运行时常量，非结构。

### 交互与面板（继承 Phase 3/4/5 定案，不重开）
- 全部新 UI（LayersPanelView / MaskToolbarView / Liquify / Retouch 面板）走既有定案：**面板四件套** = L010 accessibilityIdentifier（稳定 id 非索引）+ zh/en String Catalog + 280pt Inspector 约束（不撑宽、视口 ≥50%）+ D-H1 三件套（拖动实时 → 松手恰 1 commit）；`PanelWiringTests` 逐面板扩展。
- 层内 iop 面板 = `IOPPanelProvider` 逐层实例化，**24 个既有面板零改动**（6-5 核验 + 回归断言）。
- 蒙版绘制/liquify/retouch 交互手感全挂 **Manual-Only register**（L011/L021 红线：笔刷延迟/落点精度/光标环单测不可达）；GUI 验收轮按 PLAYBOOK §0-§6 真实 RAW + 截图量化。
- 蒙版绘制手势与既有 crop overlay 手势**互斥路由**（编辑模式状态机，D-H1 归口）；工具条浮于视口下缘不撑 Inspector。

### golden 与 ROI 红线（全 plan 写死，执行期不得放宽）
- **防空转**：所有 parity/解析/记账测试必须真实比较循环 + `compared > 0` 断言（04-02 恒真空转教训）；「分块==整幅」「合成恒等三元组」必须**逐字节/数值级**——纯记账测试对坐标错位免疫（L020 对策③，Phase 4 教训直接复用）。
- **跨层 ROI 红线（L021 层维度）**：每层子 run 独立 stamp 自己的 `bufInROI`/`dscIn`/`iscale`；**禁止任何「拿 base 的 dscIn 给层用」的抄近路**（层与 base 入口 ROI 因 base 链几何而不同）；常驻断言「每层 entry dscIn == 该子 run bufInROI 首元素」+ 内容级 golden 兜底。
- **L018 mask 累积红线**：brush stamps 累加禁 read_write 纹理同线程 RMW——render-pipeline additive blending 主案（6-3 T1 spike 定稿）+ compute atomic 备选；combine 多平面 reduce 走 kernel 参数数组非原地累积。
- **L023 往返式先行**：JzCzhz 感知模式与 parametric mask 的 uniforms 矩阵对是半边契约——parity 测试先写全往返恒等式（mo·M·mi ≈ I <1e-6）再钉断言；矩阵定义变更与断言同批提交。
- **L014 fence**：一切测试/探针读回纹理前 drain；E2E round-trip 渲染逐字节恒等断言同纪律。
- **golden 主轨**（L017 约束下全可行）：blend = float64 逐式复刻 <1e-5 + dt-cli 平场 probe 三证据（XMP 携 `blendop_params` blob、L015 hex 配方、`DEVELOP_BLEND_VERSION=14`）；mask 光栅化 = 解析断言（径向/gradient/SDF/combine 公式逐式）；序列化 = round-trip 渲染逐字节；dt-cli 不可达对象（mask/liquify/retouch）不适用轨 A dt 证据，解析参考替代。
- **容差档**：blend 点态 <1e-5 rel；Jz 往返 <1e-6；mask 解析/combine <1e-6；tile 缝 <1e-6；恒等/极限门逐字节。
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/06-layers-masking/06-RESEARCH.md`（正本：§1 混合模型裁决、§2 合成管线/缓存/ROI、§3 mask 体系、§4 blend modes、§5 liquify/retouch、§6 sidecar v2、§7 性能、§8 UI、§9 golden 表、§10 plan 拆分骨架）
- `.planning/ROADMAP.md` §Phase 6（SC#1-5 原文 + NDE-1/3、METAL-8、PERF-2 风险标注 + §Phase 7 AI mask 消费端注记）；`.planning/REQUIREMENTS.md` LAYER-01..07 / IOP-MASK-01..05 / IOP-GEO-05/06 条目 + 映射表
- `/Volumes/UNITEK/Documents/Development/darktable/src/develop/blend.{h,c}` + `masks.h` + `masks/{group,gradient,brush,ellipse,path,circle}.c` + `data/kernels/{blendop,liquify}.cl` + `src/iop/{liquify,retouch}.c` + `src/common/heal.c`（06-RESEARCH Sources 节 file:line 全实证）
- `LESSONS.md` L005/L013/L014/L017/L018/L020/L021/L022/L023/L024
- `AGENTS.md`（Conventions + Phase 执行模型：omp 执行 + ZCode subagent 验收两级 + Phase 2 架构增量 sidecar ONE-WAY）
- `.planning/phases/05-color-denoise-iops/05-08-SUMMARY.md`（Phase 6 移交清单 8 项）+ `05-VERIFICATION.md`（Phase 5 收口状态：609/3skip/0fail、轨 B 全链基线）
- `.work/gui-acceptance/PLAYBOOK.md`（GUI 验收操作口径 §0-§6）
- `TODO.md`（Phase 5 遗留挂账 + Phase 6 执行计划行）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets（现码核过，06-RESEARCH §1.3/§Sources）
- `LightamerCore/Sources/Layers/`（Phase 1 骨架五件）：`Layer.swift:25-52` 协议（id/name/isVisible/opacity/blendMode/enabled/kind；iopChain/mask 显式留给 Phase 6）+ `LayerStack.swift:27-42`（baseLayer + adjustmentLayers 自下而上）+ `BackgroundLayer.swift`（@unchecked Sendable 单 owner 契约 = AdjustmentLayer 同款范本）+ `LayerKind.swift`（`case raster` 预留注释）+ `BlendMode.swift`（13 冻结值 + 值错位记录 + REVERSE 位预告）
- `LightamerCore/Sources/Pipe/PixelPipe.swift`：`layerStack` 字段（:59）、pieces 排序/hash 链/roiHint（:493-500）、forward walk + iscale stamp（:508-538）、子域渲染（:610-663）、缓存键（:677-683）、FULL 政策（:702）、display tail 按 gamma 识别（:173-187）、ROI precondition（:719-722）——LayerCompositeDriver 的全部依赖 seam
- `PipeCacheKey.swift:15-38` 五字段（加 layerID 一字段即层维度）；`PipeCache.enforceBudget` 分档扩展点
- `HistoryStack.swift:66` `HistoryItem.layerScope` Phase 6 预留位；`ModuleRegistry.effectiveInstances` 扩展点（28.5 共槽 dedup 机制现成）
- `LightamerSidecar.swift:98,138` schemaVersion=1 + `layerStack: String?` 预留位（decodeIfPresent 已是兼容读形态）
- `V50Order.swift:37-50` 几何槽位（lens 13→clipping 17）+ liquify 18.0/retouch 20.0 在表；colorin 28.0 / colorout 70.0 / gamma 78.0 终端段识别条件
- `LightamerIOP/Sources/Common/GaussianBlur`（L018 双平面工程纪律——mask feather/blur 复用）+ `LabRoundTrip` + `FilmicRGB/YrgGamut`（JzCzhz 常量同源面）
- App 侧：`Inspector/IOPPanelProvider` + 24 面板复用面 + `CurveEditorView`；`Overlay/CropOverlayHost`（蒙版 overlay 交互模式范本）；`PipeCoordinator/EditorState`（layerStack 安装 :280-281）
- 测试基建：`ParityGate` 双闸、`ROINegotiationTests`、`PanelWiringTests`、`MemoryBudgetTests`、`PreviewChainPerfTests`、`GeometryGoldenTests` 轨 B 全链（Phase 3+4+5 全模块 = Phase 6 零增量基线，05-08 移交项 6）

### Integration Points（Phase 5 移交项落位）
- **移交项 1**（mask_display 挂点）→ 6-3 T7（选中层蒙版 overlay，per-module mask 不做——模型裁决 (b) 否决）
- **移交项 2**（`.supportsBlending` flags）→ 混合模型下 blend 腿在 composite 不在模块——**无需改任何模块**，flags 保留作语义声明
- **移交项 8**（UInt64 decimal String / StableHash 唯一生成器 / D-H1 / apply 同步契约）→ sidecar v2 与 history 全粒度直接沿用
- **PERF-5 遗留**（denoise 拖动 85.7ms）→ 正杠杆 = 更深预览降载；层维度缓存（单层失效不扩散）是叠加利好，6-5/6-7 记录实际效应不设门

</code_context>

<specifics>
## Specific Ideas

- **执行顺序刚性**：6-1 层核全绿（退化合成 + 缓存/ROI 断言）→ 6-2 blend 引擎（blend parity 是一切局部效果的基座）→ 6-3 → 6-4 → 6-5（UI/前半签核）；6-6 只依赖 6-1/6-3（映射器框架），与 6-4 并行排期；6-7 收尾（retouch + 终签核）。回退安全性：若 6-2 前发现 blendop 直译结构性障碍（预期不会——纯点态），合成引擎可先只做 normal + opacity（三条公式），层栈语义不受影响。
- **层核先行三步走**（06-RESEARCH §1.4）：6-1 交付后「同 iop 不同参数」（LAYER-02）已可用（只是全帧）；6-2 后三元组生效（LAYER-05 完成但仍全帧）；6-3/6-4 mask 接入后局部性完成。
- **层身份 = UUID（NDE-1 铁律）**：重排只改合成顺序——层链输出 key 不含顺序，重排后链缓存全存活、只重 blend（该设计的免费红利，6-1 常驻断言）。
- **maskVersion 与 chain hash 独立折叠**进前缀 key——蒙版编辑不触发链重算（METAL-8 拖动失效风暴的双保险，6-3 断言）。
- **parametric/raster mask 的 sidecar payload 拼写冻结节奏**：6-1 冻结层记录壳 + `mask: SidecarMaskSpec?` 字段（optional decodeIfPresent 非破坏）；6-3 冻结 drawn form payload、6-4 冻结 parametric/raster payload——每步均为 optional 字段追加，v1/v2 文档互容。
- **denoise 族层内 TilingPlan 复用**是 TilingPlan 首次多消费者跨层场景——6-1 先行回归网加固（轨 B 全链 + 强制分块），重模块进层后再验分块==整幅。
- **omp 执行期间本研究外零工作区写入**（L022）；编排侧记录走 /tmp。

</specifics>

<deferred>
## Deferred Ideas

- **层编组文件夹** — D-06-CONTEXT-6，v2（parentID optional 字段扩展点）
- **层内几何模块** — D-06-CONTEXT-5，v2（跨层 ROI 协商 + 映射器泛化论证后）
- **parametric mask 双域 UI（Lab+RGB 双面板）** — D-06-CONTEXT-3，v1 后按需
- **PS gamma 编码域混合变体**（overlay/soft light 观感调优）— 后续选项，v1 钉 dt 线性域 parity
- **retouch 层叠加 parametric mask** — v1 stroke 形状即 mask（dt NO_MASKS 同语义），后续可加
- **rgbcurve/rgblevels（42.0/43.0）** — D-05-CONTEXT-1 stretch 口径不变
- **vivid/linear/pin light 等其余 dt blend 模式全表**（blend.h:59-88）— 按需追加新 raw 值，枚举扩展永不重编
- ** liquify 节点上限 UI 化**（MAX_NODES=100 dt 硬限）— v1 沿用常量

</deferred>

---

*Phase: 6-Layers & Masking System*
*Context gathered: 2026-09-22（planner 裁决定稿；8 项 Open Questions 全部采纳 RESEARCH 推荐并注明理由——既定授权模式）*
