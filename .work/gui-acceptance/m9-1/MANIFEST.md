# M9-1 GUI 走查配方（MANIFEST）

> 形态 = m3-1/lumen-b 同款：走查项清单 + AX 驱动配方 + 证据落点。
> AXPress 纪律（R6 批 omp obs-3 教训）：AX id 因本批改动浮出缺失 → 顺路
> 补，不留死账。**验收样例口径（§12.3 铁律）**：走查面以我方 AI-06 语
> 义断言，不照抄上游断言（合法偏离清单 11 条为验收边界正本）。
> 证据落点 = `.work/gui-acceptance/m9-1/<item>.png`（视口截图，非全页
> 长截图——§3.2 截图纪律）。

## 走查项

### ① 任务面板四 icon（M9AIM-01）
- 入口：任一图层选中 → 底部 MaskToolbar AI 组。
- 断言：Subject（`ai.mask.task.subject`）/ Background
  （`ai.mask.task.background`）/ People（`ai.mask.task.people`）可点；
  **Sky（`ai.mask.task.sky`）恒 disabled + tooltip**
  （`ai_task_sky_disabled_hint`）——AX 查 `.disabled` 态 + 点击零动作。
- 证据：四 icon 面板截图（Sky disabled 灰态可见）+ Sky tooltip 截图。

### ② tap-to-segment 逐点即解（M9AIM-02 主件）
- 前置：Layer B 模型 ready（首启冷加载 ~5.5s 一次性；spinner 文案
  `ai_candidate_solving` 承接）。
- 步骤：
  1. `ai.mask.tap` 进入模式 → 视口 tap 加 seed 点（绿 + disc）。
  2. 等候选解出（~100ms warm + 300ms debounce）→ **淡红候选 tint**
     （`MaskOverlayStyle.candidateTint` 固定色）覆盖视口 + 状态文案
     `ai_candidate_ready`。
  3. ⌥-tap 加 excluded 点（红 − disc）→ debounce 后候选重解，**推理
     期间旧候选保持显示**（不清屏）。
  4. **点击现有点（≤12px 命中）= 删除** → 预算计数器回落 + 候选重解。
  5. Confirm（`segment.confirm`）→ 候选 tint **消失**、普通蒙版编辑
     tint（0.85）接管、⌘Z 恰退一条（恰 1 条 stackSnapshot）。
- 延迟观察（R-1 门）：逐步 tap 间隔候选更新 ≤500ms（P95 感觉门）；
  超门记录（DECISIONS D14 预案面）。
- AXPress 配方：`ai.mask.tap` → 视口坐标 tap（AXPress 驱动真视口）；
  点视觉 = 绿/红 disc 色值截图比对（D8 单源常量）。
- 证据：seed 后/候选 ready/加 excluded/删点/commit 后五帧。

### ③ Path 笔触采样（M9AIM-02）
- 步骤：无修饰键拖一笔（≥24px）→ 释放 → 计数器跳增（等弧长 24px 采
  样点数 = min(16, 预算余量)）；拖动中 4px 绿色 stroke 预览可见。
- AXPress 配方：视口 drag 序列（AX 驱动）；点计数 = `segment.counter`
  的 AX value 读数。
- 证据：拖动中（stroke 预览）/释放后（采样点列）两帧。

### ④ Feather/Expand slider（M9AIM-03，D-M9A-7）
- 前置：segment 模式激活（`ai.mask.feather`/`ai.mask.expand` 面板面）。
- 断言：两 slider 值域 px（Feather 0..50 / Expand −50..50 整数步）、
  值显示 `Npx`；**拖动中零 history 写入**（⌘Z 栈不动 = D-H1）；松手
  后下一次生成/patch bake 消费（expand 负值 = 边缘收缩可见）。
- 证据：Expand=−20 后 confirm 的蒙版边缘收缩对照（前一帧/后一帧）。

### ⑤ paste 排除名单（M9AIM-03，D-M9A-8）
- 步骤：图 A 带一个 AI 蒙版层 + 一个手绘蒙版层 → Copy Adjustments →
  粘到图 B → **toast「已排除 1 个 AI 蒙版」**（`transfer_ai_masks_
  excluded %lld`）→ 图 B 该层无 AI raster、手绘蒙版照常粘贴。
- AXPress 配方：transfer 对话框（AX id 在册）+ toast 截图。
- 证据：toast 帧 + 图 B 蒙版列表面（AI 件缺席 + 手绘件在位）。

### ⑥ cancel 丢弃（M9AIM-03）
- 步骤：segment 模式 → 加点解出候选 → Done/Escape → 候选 tint 消失、
  层蒙版零变化、⌘Z 栈零新增。
- 证据：cancel 前后两帧（候选 tint 消失）+ 蒙版面板不变帧。

## M9AIM-02 承载映射（m-3，SUMMARY 对账行同源）

验收形态「合成事件 → AX 驱动真视口 tap → 蒙版更新 → coverage 消长 +
交互不改参数真相」↔ 三层链：
1. **状态机级单测（机检）**：AIMaskIterativeSessionTests 八法（debounce
   合并/候选保留/AI-06 sidecar 零写入/picker 白名单/commit·cancel 双
   清除）。
2. **走查项②③（AXPress 配方驱动真视口）**：本 MANIFEST。
3. **omp computer-use 二次验收**：验收轮实机抽验。

## 顺路登记

- Sky tooltip 文案、`ai_candidate_solving/ready`、`transfer_ai_masks_
  excluded` 为本批新键（zh-audit 在册）。
- 旧 AX id（`ai.mask.subject`/`ai.mask.subject.inverted`/`ai.mask.
  person`）随 T1 任务面板化退役，新 id = `ai.mask.task.*` 族——走查
  若见引用旧 id 的既有配方，按新 id 改写。
