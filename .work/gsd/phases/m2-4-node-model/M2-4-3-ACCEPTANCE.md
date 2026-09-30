# M2-4-3-ACCEPTANCE — 节点面板 UI + phase 收口 独立验收报告

> 验收批：2026-09-30（独立验收 subagent）。对象 = plan `M2-4-3-PLAN.md`
> （checker 修正版 `c94aa3c`）+ 执行批四 commits（T1 `b4ea439` / T2
> `e245b46` / T3 `34de49a` / T4 `cc9d0f3`）+ 验收批修复 1 commit
> （`a90efa0`）。验收方式 = 逐 AC 机检核对 + 五重点抽查（file:line）+
> 定向独立复跑（`--bundle App` / `--bundle Layers` / zh-audit 双模式亲跑）
> + BUNDLE-MAP 求和交叉对账（全套 `--all` 不重跑——批准门纪律）。

## 结论

**PASS / 0 error + 1 minor（本批已修）+ 2 observation**

- 执行批四 commits 全部按 plan 交付，AC 11/11 独立复核全绿。
- 全套终跑声明（TOTAL|2240/14/0|725s EXIT=0）经三路独立交叉核对闭合：
  BUNDLE-MAP 逐行求和 = 2240 精确、`--bundle App` 复跑 332/0/0、
  `--bundle Layers` 复跑 174/2/0（与声明逐值一致）。
- phase（M2-4）三 plan 执行+验收面全闭环；签核 VALIDATION 归
  verify-work 独立步（C 档门控第 3 条，输入 = `M2-4-ACCEPTANCE.md`）。

## AC 逐条复核（plan 11 条）

| # | AC | 复核结果 |
|---|---|---|
| 1 | 几何正本纯函数 | ✅ `NodeCanvasGeometry.swift` 零 UI 依赖（仅 CoreGraphics/Foundation/LightamerCore）；NodeCanvasGeometryTests 9/9：layout 单调+居中+间距+insets、0/1/N 面、edges=N-1 邻接中心、insertionIndex 阈值矩阵（2/3 grade + 0/1 grade 退化面）、指示线镜像、fitScale 三界（不超高=1/超高精确比/零负容器=1） |
| 2 | 模型投影/选中/路由/锁定 | ✅ NodesPanelModelTests 14/14（真 EditorState 实例驱动）：投影跟随 stack 变更、grade→UUID / develop·drt·nil→nil、apply 恰一条 structure item、锁矩阵（端点锁/grade/未知 id 不锁） |
| 3 | 渲染帧几何 = Layout + Fit 边界 | ✅ 机检 = NodeCardFramesKey preference 读回（D-M2-4-3-5）：真面板 NSHostingView 实装、逐卡 minX/minY/w/h 与 Layout 断言相等（accuracy 0.01）——经真实 SwiftUI layout 系统测量非源码镜像；30 节点 BENCH 观察行 0.0081 ms/round 落 SUMMARY |
| 4 | 交互四件 | ✅ availableActions 表断言（grade 四项含 Delete、锁定端点空——穷举零 default）+ 拖拽序→reconnect 参数断言（insertionIndex 注入 + 移动后 id 序 `[ids[2],ids[0],ids[1]]`）+ locked 拒发（零 item/零 stack 移动/零 toast）+ mix live 零 item / commit 恰一条且 label 同键 `history_graph_mix` |
| 5 | 锁定三件套 + 泛化签名 | ✅ `NodeLockedBadge.marker`="editor.nodes.locked" + 卡 marker 穷举测试；签名 `.nodeLocked(_ locked: Bool, hint: @escaping () -> Void) -> some View` 零节点语义（M2-7 可消费；语义冻结 D-M2-4-3-6）；锁定 toast 文案断言（develop/drt hint、grade/未知不 hint） |
| 6 | Rail 仅 .nodes + Core 零 diff + 裸 hex | ✅ `git diff 3eec061..cc9d0f3` EditorToolRailView = @Environment 声明 1 行 + case 体 1 处（history/versions 面 diff 零）；LightamerCore/ 全 range 零 diff；`git grep -En '#[0-9A-Fa-f]{6}'` Nodes/ 零命中 |
| 7 | zh 对账 exit 0 | ✅ 亲跑 `Scripts/zh-audit.py --check` PASS exit 0（1185 source / 1397 catalog / zh complete）+ `--self-test` PASS exit 0；键族实拍：history_graph_* 7 键 / nodes_* 10 键 / node_lock_* 2 键 / editor_node_* 8 键 / editor_nodes_* 2 键全带 zh 值；退役键 `editor_nodes_placeholder` 已删（无孤儿） |
| 8 | 全套 0 fail、计数带 | ✅ 声明 2240/14/0（2217+23）；三路独立闭合见下节。+23 略超 12..18 预估带——SUMMARY 已解释（T1 一次建齐 20 跨任务累积），带为「≈」预估非门，接受 |
| 9 | REQUIREMENTS 翻账边界 | ✅ cc9d0f3 仅动 M2NODE 族两行（M2NODE-06 翻账 + M2NODE-04 注记④闭环）；他族零 diff 亲核 |
| 10 | diff 边界 + 收口四件 | ✅ 四 commits 逐 `git show --stat` 核对 = 申报文件集；SUMMARY/DECISIONS/ACCEPTANCE/GOAL-STATE 同批在册 |
| 11 | 测试登记闭环 | ✅ Project.swift L661/663 双文件在 LightamerTestsApp sources；BUNDLE-MAP 两行（APP 9 / APP 14）+ 8→9 终值勘误注记在案 |

## 计数对账独立复核（重点⑤）

1. **BUNDLE-MAP 逐行求和**（awk 独立计算）：IOPP 308 + IOP 457 + APP 332 +
   EXPORT 260 + LAYERS 174 + LIB 430 + SESS 279 = **2240 精确** = 声明 TOTAL。
2. **`--bundle App` 亲跑**：`BUNDLE|App|332/0/0|peakRSS=1468MB|78s` —— 与声明
   332/0/0 逐值一致（309 基线 + 23 新增）。
3. **`--bundle Layers` 亲跑**：`BUNDLE|Layers|174/2/0|peakRSS=944MB|20s` —— 与
   M2-4-2 收口值一致不变（本 plan LAYERS 零新增，唯一 LAYERS 触碰 =
   PipelineLinkageTests 断言改写不增方法数，与 BUNDLE-MAP 行 5 不变吻合）。
4. **23 = 9 + 14 精确**（NodeCanvasGeometryTests 8 T1 + 1 T2 读回；NodesPanelModelTests
   12 T1 + 2 T3）；**23 vs 22 笔误勘误处置核销**：D-M2-4-3-7 在案 + BUNDLE-MAP
   几何行 8→9 随收口修正 + 勘误注记落 map 头部——三处一致性亲核。

## 五重点核查结论（file:line）

1. **Canvas 红线** ✅：`EditorNodesPanelView.swift:195-207` edgesCanvas 仅
   `Canvas` 画线 + `.allowsHitTesting(false)`；`:216-234` 卡片层 = 真视图
   `.position` 布局（`:232`），按钮/菜单/滑杆/手势全原生命中；全目录零手写
   hit-test（无任何 point-in-rect 自算）；插入指示线 `:159` 同样
   allowsHitTesting(false)。拖卡重连 = `NodeCanvasGeometry.insertionIndex`
   纯函数（`:127-146`），测试覆盖 = 阈值矩阵 + 退化面 + 拖拽序参数断言。
   渲染红线四文件（LayerCompositeDriver/PixelPipe/PipeCacheKey/legacyBody）
   全 range `git diff -S` 零命中亲核。
2. **锁定三件套 M2-7 复用形态** ✅：`EditorNodesPanelView.swift:532-541`
   泛化签名零节点语义；三件 = NodeLockedBadge（marker 稳定）+ 内容
   hit-test 拦截 + hint 回调；选中/navigation 在 trio 外挂（`:264-266`）=
   锁定可导航不可编辑（D-M2-4-3-6 语义冻结在案，M2-7 演化 = additive 参数）。
3. **mix 滑杆 live/commit 腿** ✅：`NodesPanelModel.swift:129-144` live =
   applyLiveLayer 零 history、commit = commitLayerEdit 恰一条 + 同键 label；
   视图草稿缓冲（`EditorNodesPanelView.swift:41,421-436`）防快拖陈旧值；
   防刷屏测试双钉（零 item + 恰一条）。**断言引 M2-4-1 AC2 正确**：plan
   KD-2 E4 闭环引文与 `M2-4-1-PLAN.md:453`「setGradeMix(0) 后 composite 输出
   与该层 enabled=false bypass 输出逐像素相等——容差 0，-0/+0 视相等」逐字吻合。
4. **zh-audit 亲跑 + PipelineLinkageTests KEY 化** ✅：--check/--self-test 双
   exit 0 亲跑；`PipelineLinkageTests.swift:198-215` 两处英文字面量断言改
   同键 `String(localized:)` 对照（locale 无关、同解析更强契约）——M2-4-2
   验收 finding③（原报告 L158）核销。
5. **计数勘误处置** ✅：见上节（对账三路 + D-M2-4-3-7 + map 修正三处一致）。

## Findings

- **F1（minor，本批已修 `a90efa0`）**：`Scripts/test-direct.sh` 头注第 9 行
  「拆为六个域 bundle」陈旧（实为七个——checker M3 遗留，M2-4-0 legacy，
  执行批顺手修未落）。注释单行、零行为；验收批 ≤20 行权限内闭环。
- **O1（observation，不修）**：`NodeCanvasGeometryTests.swift:178` 注释
  「well below the last grade → the top slot」措辞反直觉但语义正确（拖到
  链尾以下 = 追加到 grade 序末 = 合成序最顶槽位；与模型测试「the top grade
  moved to the bottom」的序语义自洽）。不改。
- **O2（observation，转记账面）**：M2-3-4 验收 F1（ProjectWorkspaceFace 4 处
  verbatim zh 缺口，挂「M2-4 队列」）在本 phase 三 plan 中均未被任何 plan
  scope 承接（M2-4 zh 对账 scope = 节点键族），`ContentView.swift:668-690`
  4 处 verbatim 现存实核——挂账延续（建议归 M2-5 或专项 zh sweep，非缺陷）。

## 派发指令裁决记录：M2NODE-03 不补勾

派发指令含「M2NODE-03 补勾（页签联动 M2-4-2 已交付）」并要求核对现文后处置。
核对结论：**不补勾**。M2NODE-03 现文 = 「节点内有序调整列表 + 18 项目录所有权
校验（Grade 内插入 = typed error）」——与「页签联动」（D-M2-4-CONTEXT-9，随
M2NODE-06 面板交付）非同一需求面；该行严格面的处置已有 M2-4-1 验收裁决在案
（`M2-4-1-ACCEPTANCE.md` 翻账清单：「所有权框架 + 宽限执行已交付，严格面激活
归 M2-5，不勾」），phase 级 `M2-4-ACCEPTANCE.md` M2NODE 全族表同口径。补勾将
推翻已签核的先前验收裁决，且严格面（18 目录收窄激活）确实未实现。处置 =
REQUIREMENTS M2NODE-03 行加 phase 终态注记（框架交付 + 宽限执行 + 严格面归
M2-5），维持不勾。

## 翻账清单（本批）

- 新增本报告 `phases/m2-4-node-model/M2-4-3-ACCEPTANCE.md`。
- `REQUIREMENTS.md`：M2NODE-06 行补验收锚（PASS `M2-4-3-ACCEPTANCE.md`）+
  M2NODE-03 行补 phase 终态注记（不勾，依据见上节）——仅 M2NODE 族两行。
- `M2-4-ACCEPTANCE.md`（phase 级）：M2NODE-06 行「验收批待派」→ PASS 终态 +
  文件头验收状态更新；挂账清单复核后维持（F1 zh 缺口延续见 O2）。
- `GOAL-STATE.md`：追加验收批续接点（M2-4 三 plan 执行+验收全闭环 → 下一步 =
  C 档 verify-work 签核）。
- `TODO.md`：Milestone 2 行 + M2-4 起航挂账行同步 M2-4 执行+验收终态。
- 修复 commit：`a90efa0`（F1 test-direct.sh 头注）。

## 验证方式与覆盖声明

- 逐 AC 核对全部完成（机检方式 = 表列测试 + git 亲核 + 目录 grep 实拍）。
- 独立复跑 = `--bundle App`（332/0/0，78s）+ `--bundle Layers`（174/2/0，
  20s）+ zh-audit 双模式——均亲跑 exit 0；全套 `--all` 未重跑（批准门纪律），
  以 BUNDLE-MAP 求和 = 2240 精确 + 两 bundle 实跑与声明逐值一致交叉闭合。
- 未核面声明：Manual-Only 走查观察项 5 条（拖动流畅度/拖卡手感/滑杆手感/
  30 节点滚动 Fit/滚动共存）不在 subagent 机检能力内——已在 phase
  `M2-4-ACCEPTANCE.md` 观察项清单挂 verify-work/真机走查批核销。
