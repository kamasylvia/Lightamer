---
phase: 7
plan: "07-3"
title: "AI-06/07 集成精修 + Phase 7 终签核：MaskToolbar AI 组（层 A 一键 + 层 B 入口三态）+ instance 勾选浮层 + tap-to-segment 视口第 4 编辑模式（Y 翻转 + 点计数 + scribble 升级缝）+ skinSmooth 面板（定位皮肤按钮）+ AI 蒙版五条覆盖路径 E2E + GUI 验收轮（overlay ΔR 量化 + 磨皮 Manual-Only）+ 07-VALIDATION 签核 + Phase 8 移交清单"
wave: 3
depends_on: ["07-1", "07-2"]
autonomous: true
requirements: [AI-01, AI-05, AI-06, AI-07]
files_modified:
  - App/Sources/Lightamer/UI/Inspector/MaskToolbarView.swift     # AI 组：「主体蒙版」（层 A）+「点击选取」（层 B）入口 + 生成中 spinner
  - App/Sources/Lightamer/UI/Overlay/InstancePickerOverlay.swift # 新建：层 A 多主体 instance 勾选浮层（checkbox + 预览高亮 + 确认 bake）
  - App/Sources/Lightamer/UI/Overlay/SegmentEditingOverlayHost.swift # 新建：tap-to-segment 视口交互（第 4 编辑模式）
  - App/Sources/Lightamer/UI/EditorState 或等价状态层             # LayerEditingState 第 4 编辑模式（种子枚举 + 互斥路由扩展）——具体挂点执行期决策
  - App/Sources/Lightamer/UI/Inspector/SkinSmoothPanelView.swift # 新建：三滑块 + 「定位皮肤」+ 保护区显示 toggle（IOPPanelProvider 注册）
  - App/Sources/Lightamer/UI/Inspector/IOPPanelProvider 注册面    # skinSmooth 面板注册（第 25 面板）
  - App/Sources/Lightamer/Resources/Localizable.xcstrings        # AI 组/浮层/面板 zh(en) 键（zh 标签——L025）
  - Tests/LightamerTests/PanelWiringTests.swift                  # skinSmooth 面板 + AI 入口 wiring 扩展
  - Tests/LightamerTests/LayerUIWiringTests.swift                # 第 4 编辑模式互斥路由 + 生成蒙版 ⌘Z 恰 1 commit 扩展
  - Tests/LightamerTests/AIMaskEditPathsTests.swift              # 新建：五条覆盖路径 E2E（drawn/parametric/invert/羽化重 bake/refine 重生成）
  - .work/gui-acceptance/FINDINGS.md                             # GUI 验收轮登记（overlay ΔR 量化 + 截图）
  - .planning/phases/07-ai-modules/07-VALIDATION.md              # 新建（体例对齐 04/05/06-VALIDATION）
  - .planning/phases/07-ai-modules/07-DISCUSSION-LOG.md          # 新建或扩展：SC#1-5 终核对节 + Phase 8 移交清单
  - .planning/REQUIREMENTS.md                                    # AI-01/05/06/07 翻账
  - input/golden/manifest.md                                     # Phase 7 总账节（如需收口）
  - TODO.md
  - AGENTS.md                                                    # Phase 7 审计段（如踩坑）
  - LESSONS.md                                                   # 新教训（如 L026+）
  - .planning/phases/07-ai-modules/07-3-SUMMARY.md
  - .planning/phases/07-ai-modules/07-3-DECISIONS.md
---

# Plan 07-3 — AI-06/07 集成精修 + Phase 7 终签核

> 背景：Phase 7 尾部 plan = **把 07-1/07-2 的服务与 iop 接进用户可打的 UI，并以阶段
> 签核收口**。AI-06 = AI mask 作为层蒙版输入（v1 唯一通道 raster 烘焙，D-07-CONTEXT-3）；
> AI-07 = 非黑箱（AI-RESEARCH §4：可解释/可调/可覆盖三面——**生成即 bake，产物进入与
> 手画蒙版完全相同的编辑/合成/持久化世界**，五条覆盖路径全复用 Phase 6 机制，Phase 7
> 零新蒙版原语除羽化外）。交互面：MaskToolbar AI 组（层 A 一键「主体蒙版」+ 层 B
> 「点击选取」——assetStatus 三态门控 + 下载引导，07-1 状态模型消费）+ tap-to-segment
> 视口**第 4 编辑模式**（单击 seedPoint/含点、⌥·右键排点、⇧拖 box；**scribble/lasso
> 留 v1 后**——D-07-CONTEXT-4 升级缝：种子枚举预留）+ 层 A 多主体 instance 勾选浮层 +
> skinSmooth 面板（「定位皮肤」按钮 = 07-2 SkinRegionLocator 接线）。尾部 = **Phase 7
> 终签核**（SC#1-5 + 07-VALIDATION + REQUIREMENTS 翻账 + Phase 8 移交清单）——
> **C 档门控第 3 停（签核前停）在本 plan 内触发**。

## read_first

1. `.planning/phases/07-ai-modules/07-RESEARCH.md` §3（三条通道对位表）、§4（非黑箱三面表 + 五条覆盖路径）、§8（UI 面/编辑模式/instance 勾选/下载态）、§6（GUI 验收轮行）、§Plan 07-3 行
2. `.planning/phases/07-ai-modules/07-CONTEXT.md` D-07-CONTEXT-1（下载三态/回落）/3（raster 唯一通道）/4（tap+box 范围 + 升级缝）+ 继承定案节（AI 生成参数不进 sidecar / stackSnapshot 语义）+ 验证红线节
3. `.planning/phases/07-ai-modules/07-1-SUMMARY.md` + `07-2-SUMMARY.md`（服务/iop 交付面与 API 实形——接线以实形为准，偏差回注 DECISIONS）
4. `LightamerCore/Sources/Layers/LayerStack.swift:91-184` + `Pipe/LayerCompositeDriver.swift`（层栈写入面）+ `Layers/Masks/MaskSpec.swift:239-299`（三 payload——覆盖路径消费面）+ 07-1 交付的 `AIAssetStatus`/`AIMaskService` 接口
5. App 侧：`MaskToolbarView` + `LayerEditingState`（互斥状态机 mask>liquify>retouch>crop）+ `RetouchOverlayHost`（视口交互 overlay 范本）+ `IOPPanelProvider`（24 面板注册面）+ `LayersPanelView`（mask chip）
6. `.planning/phases/06-layers-masking/06-VALIDATION.md`（VALIDATION 体例正本 + Manual-Only 表模式）+ `06-07-PLAN.md` T6（终签核任务体例）+ `.work/gui-acceptance/PLAYBOOK.md` §0-§6
7. `LESSONS.md` L010（identifier）/L011（Manual-Only）/L021（GUI 验收红线）/L022（omp 零写入）/L025（zh 标签）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 相关文件）；`caffeinate -dis`；单测 `Scripts/test-direct.sh`；**LayerEditingState/路由改动后 LayerUIWiring 全量回归**。
- **每任务边界检查 `.work/PAUSE`**（任务收尾 commit 后、下一任务开工前；AGENTS.md 2026-09-24 暂停机制）。
- **C 档门控**：**Phase 签核（VALIDATION 落笔）前停**——T5 开工即先汇报 verify 结论等用户确认（AGENTS.md 三点停第 3 停）。
- **面板四件套**：L010 identifier（`ai.mask.subject` / `ai.mask.tap` / `ai.skin.locate` 等，执行期定稿入 DECISIONS）+ zh/en catalog（**zh 标签**，L025——首屏截图必查中文渲染）+ 280pt Inspector 约束 + D-H1 三件套（滑块拖动实时 → 松手恰 1 commit）。
- **GUI 复验红线（L021）**：真实 RAW 端到端 + PLAYBOOK §0-§6 + overlay 截图量化（06-03 ΔR 口径——FINDINGS 落数字非目检）；磨皮质感 + tap 手感 = Manual-Only 表登记（L011，数据腿已由 07-1/07-2 钉住）。
- **防空转**：E2E 断言内容级（overlay ΔR 数字、⌘Z 恰 1 commit 计数、mask chip 平面差异），禁"按钮存在/无崩溃即过"。
- **AI 参数不进 sidecar**（继承定案）：生成参数（qualityLevel/seeds/refine 点）留 UI 状态；蒙版像素（raster ref）才是编辑语义——sidecar schema **零升级**（回归钉住）。
- **L022**：omp/subagent 运行期 orchestrator 零工作区写入。
- UI 挂点（SegmentEditingOverlayHost 的 overlay 宿主形态/浮层承载/按钮 id 定稿）标注**执行期决策**入 `07-3-DECISIONS.md`，不臆造。

## Tasks

### T1 MaskToolbar AI 组 + instance 勾选浮层 + 下载三态接线

- **action**
  1. `MaskToolbarView` 增 AI 组：「主体蒙版」（层 A 一键——选中层 mask 槽写入 bake 产物 + `stackSnapshot` 结构项）+「点击选取」（层 B 入口——消费 07-1 `AIAssetStatus` 三态：未下载置灰引导下载/下载中进度（Subprogress）/就绪进入编辑模式）；生成中 spinner（后台 Task——07-1 服务 async 面）。
  2. `InstancePickerOverlay`：层 A 多主体 → checkbox 列表 + 预览高亮（instance mask 着色 overlay）+ 确认 bake（`generateMask(forInstances:)` 子集 → 07-1 上整形 → bake → 挂层）。
  3. 首启预下载提示接线（07-1 `AIDownloadPrompt` 状态模型 → 实际弹窗呈现；拒绝则层 B 置灰、层 A 可用——D-07-CONTEXT-1）。
  4. 生成完成 → 蒙版进选中层 mask 槽（LayersPanel mask chip 更新）+ 蒙版工具条自动激活该层蒙版编辑模式（AI-06 交互形态：用户看到的是普通 raster 蒙版）。
- **证据**：`LayerUIWiringTests` 扩展（生成蒙版 = ⌘Z 恰 1 commit stackSnapshot、undo 还原 mask 槽空态；层 B 三态按钮态跃迁）+ L010 identifier 全量 + zh/en catalog（zh 标签）。

### T2 tap-to-segment 视口第 4 编辑模式

- **action**
  1. `LayerEditingState` 第 4 编辑模式（互斥路由序扩展 mask>liquify>retouch>**segment**>crop——精确插位执行期决策）：单击 = seedPoint（首发）/ addIncludedPoint（精修）；⌥ 点击或右键 = addExcludedPoint；⇧ 拖 = seedBox。**scribble/lasso v1 不接**——种子枚举预留 scribble case + 头注升级缝（D-07-CONTEXT-4）。
  2. **Y 翻转换算经 07-1 `AIMaskTypes`**（视口 y 向下 → Vision 左下原点；换算已单测，本任务只接线）；**点计数器 UI**（13/11 上限——满即禁点 + 提示，`addIncludedPoint` throws 超限错误呈现不崩不静默）。
  3. `SegmentEditingOverlayHost`：交互视觉（点标记：含点/排点双色、box 框、计数器浮标）+ 光标形态；与 crop/mask 绘制/liquify/retouch 互斥（LayerUIWiring 同款断言扩展）。
  4. 精修流：已有层 B 蒙版的层再进编辑模式 → 后续点**重跑同一 request** 精修 → 同 maskID 覆盖重 bake（D-07-CONTEXT-5）→ 每次确认 = 一条 stackSnapshot（⌘Z 逐级回退）。
- **证据**：`LayerUIWiringTests`（第 4 模式互斥穷举 + 精修每次恰 1 commit + ⌘Z 链逐级还原 hash）+ Y 翻转接线断言（合成点击 → 服务收到的 Vision 坐标向量核对）+ 满禁点状态断言。

### T3 skinSmooth 面板 + 「定位皮肤」接线

- **action**
  1. `SkinSmoothPanelView`（IOPPanelProvider 注册，第 25 面板）：strength / radius / detail-preserve 三滑块（D-H1 三件套）+ variant Picker（v1 单 case，v2 位展示策略执行期决策）+ 「定位皮肤」按钮（调 07-2 `SkinRegionLocator` → skin mask bake 挂该层蒙版槽——与 T1 同通道）+ 保护区显示 toggle（overlay 呈现 hull−protect 区域）。
  2. 侧脸/多人脸 yaw 门提示接线（07-2 typed warning → toast/面板提示，不静默）；空 landmarks → 报错腿呈现。
  3. 面板四件套 + catalog（zh 标签 + `ls *.lproj` smoke——L025）。
- **证据**：`PanelWiringTests` 扩展（三滑块拖动 = 恰 1 commit layerScope 参数项 + 归零还原 hash + 定位皮肤按钮 = mask 槽写入 1 commit）+ 磨皮模块启用态链回归（07-2 轨 B 已钉中性；本任务钉启用态内容差异 >0 方向断言）。

### T4 五条覆盖路径 E2E + GUI 验收轮

- **action**
  1. `AIMaskEditPathsTests`（AI-07 覆盖路径 E2E，Core 级 + App 状态级）：生成蒙版后 (a) drawn 笔画 union/difference 修补（`MaskGroupItem` combine 既有）(b) parametric ⊓ 收紧（三 payload ⊗ 装配）(c) invert（`RasterMaskRef.invert`）(d) 羽化重 bake（07-1 bake 羽化半径）(e) refine 点重生成（同 maskID 覆盖）——每条 = 内容级断言（mask 平面方向变化 + 缓存失效记账 + sidecar round-trip 后蒙版存活）。
  2. **GUI 验收轮**（PLAYBOOK §0-§6，真实 RAW）：①主体蒙版生成 → overlay 开/关截图 ΔR 量化（06-03 口径，FINDINGS 落数字）+ ⌘Z 恰 1 commit；②人像 RAW 磨皮前后对比（「定位皮肤」→ 三滑块 → pore-level 目检 **Manual-Only 登记**）+ before/after toggle（按住空格看原图）；③tap-to-segment 手感（点选/排点/box + 点计数 **Manual-Only 登记**）；④层 B 下载三态真机走查（未下载置灰 → 下载 → 就绪）。截图归档 FINDINGS。
  3. sidecar schema 零升级回归（AI 参数不落盘断言——`.lra` 字节对比：AI 生成前后 schema 字段集不变，仅 mask ref 增加）。
- **证据**：E2E 测试计数 + FINDINGS（ΔR 数字 + 截图 + Manual-Only 行）+ sidecar 零升级断言。

### T5 Phase 7 终签核（**C 档门控第 3 停前置**）+ Phase 8 移交

- **action**
  1. **停点**：T1-T4 战果 + verify 结论汇报用户，确认后进入签核落笔（AGENTS.md C 档门控第 3 停）。
  2. **SC#1-5 逐条核对**（06-07 T6 模式）：证据指针（测试名/文件/FINDINGS 行/manifest）落 `07-DISCUSSION-LOG.md`——SC#1 主体隔离双层可用交互（07-1 层 A/B + 07-3 交互）、SC#2 磨皮保细节不塑料（07-2 parity + Manual-Only）、SC#3 AI mask 接入调整层（07-1 bake + 07-3 T1）、SC#4 可编辑非黑箱（07-3 T4 五路径）、SC#5 层 A 离线 + 层 B 一次性下载 + ≤1s 门 + 缓存不重跑（07-1 benchmark + bake 持久化天然满足）；缺口当任务回补，零静默。
  3. `07-VALIDATION.md`（体例对齐 04/05/06）：Per-Task Verification Map 全行 ✅（带测试名）+ Manual-Only 表（磨皮质感/tap 手感/下载真机——L011 口径汇总）+ frontmatter `status: validated` + `nyquist_compliant: true` + 需求注记行（AI-06 raster 口径 D-07-CONTEXT-3 / scribble v1 后 D-07-CONTEXT-4 / 多频 v2 D-07-CONTEXT-6）+ Sign-Off checklist。
  4. REQUIREMENTS AI-01/05/06/07 翻账（AI-06 注记已在 planner 批落定——签核只勾选 + 引用）；manifest Phase 7 总账节（如需）；`.work/07/perf.md` 收口（SC#5 门终值 + bake 峰值内存 Instrument 记账复核）。
  5. **Phase 8 移交清单**（06-DISCUSSION-LOG 终节模式）：HDR/Effects 接口面——AI mask 资产形态（raster PNG 旁挂约定对 stacking 对齐无依赖）、skinSmooth 66.5 槽位登记（Phase 8 watermark 77.0/78.0 邻域核对）、AIMaskService 复用面（Effects 阶段如需语义分割 v2 后端插拔）、Vision 推理基建（未来 AI 评分/追色 v2 共用）。
  6. 文档收口：TODO（Phase 7 完成态 + Manual-Only 挂账）；LESSONS（新教训评估）；AGENTS.md 审计段（如踩坑）；全量 `Scripts/test-direct.sh` 终轮绿后宣布签核。
- **证据**：DISCUSSION-LOG SC#1-5 节 + VALIDATION frontmatter + REQUIREMENTS 翻账 + 移交清单 + 终轮计数。

## Verification

| SC | 本 plan Task | 判据 | 命令 |
|---|---|---|---|
| SC#1 双层主体隔离 | T1/T2 + 07-1 | 层 A/B 可用交互 + 确定性/语义门 | DISCUSSION-LOG 指针 + 全套 |
| SC#2 磨皮保细节 | T3/T4 + 07-2 | parity + 恒等三元组 + Manual-Only 目检 | SkinSmoothParity + FINDINGS |
| SC#3 AI mask 接入层 | T1 + 07-1 T4 | raster bake 挂层 + round-trip | AIMaskEditPaths + RasterMaskRoundTrip |
| SC#4 可编辑非黑箱 | T4 | 五路径内容级断言 | AIMaskEditPathsTests |
| SC#5 离线/延迟/缓存 | T1 + 07-1 T1 | 三态门控 + perf.md 门 + bake 持久化 | perf.md + LayerUIWiring |
| GUI 红线 | T4 | overlay ΔR 量化 + Manual-Only + PLAYBOOK | FINDINGS |

## 验收标准（Acceptance）

- [ ] MaskToolbar AI 组 + instance 勾选浮层 + 下载三态（未下载置灰引导/下载中/就绪）+ 首启预下载提示；生成 = ⌘Z 恰 1 commit stackSnapshot
- [ ] tap-to-segment 第 4 编辑模式：tap 含/排点 + ⇧box + Y 翻转接线 + 13/11 满禁点 + 互斥路由穷举 + scribble 升级缝注记；精修 = 同 maskID 覆盖重 bake + 逐级 ⌘Z
- [ ] skinSmooth 面板四件套 + PanelWiring（三滑块恰 1 commit + 定位皮肤 = mask 槽 1 commit）+ yaw 门提示不静默 + zh 标签（`ls *.lproj` smoke）
- [ ] 五条覆盖路径 E2E 内容级断言（drawn/parametric/invert/羽化重 bake/refine）+ sidecar schema 零升级（AI 参数不落盘）
- [ ] GUI 验收轮：overlay ΔR 量化落 FINDINGS + Manual-Only 表（磨皮质感/tap 手感/下载真机）+ PLAYBOOK §0-§6 + 截图归档
- [ ] **C 档第 3 停执行记录**（签核前汇报确认）；SC#1-5 证据指针落 DISCUSSION-LOG；`07-VALIDATION.md` `status: validated` + `nyquist_compliant: true` + 需求注记行；REQUIREMENTS 翻账 + manifest 收口 + Phase 8 移交清单
- [ ] 全量 suite 0 fail；无 /tmp 过程产物入工作区；无常驻 app 实例残留；决策入 `07-3-DECISIONS.md`；SUMMARY 落盘
