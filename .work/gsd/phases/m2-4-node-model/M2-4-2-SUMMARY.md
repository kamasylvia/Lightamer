# M2-4-2-SUMMARY — 蒙版语义面 + 页签联动收口（plan M2-4-2，P2 三任务）

> 收口时间：2026-09-30（夜间授权执行批，coordinator 批准全套终跑）。
> plan 正本 = 同目录 `M2-4-2-PLAN.md`（checker 修正版 `c94aa3c`，E3 双腿 +
> E2 登记纪律版）。配套 = `M2-4-2-DECISIONS.md`（KD 确认 + 写入点审计表 +
> D-M2-4-2-1..6）。**未 push**（验收批同守）。

## 任务与提交

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `42e2f95` | `feat(core): honor mask item enabled and deletion lock semantics` — MaskCombiner enabled 恒等元过滤（装配前 CPU 侧，kernel/公式零改动）+ MaskSpec maskItems/setItemEnabled/setItemDisplayName 访问面 + LayerEditingState `.clear`/`.fill` 双腿 deletionProtected 拦截（toast + 零 history item）+ MaskItemSemanticsTests 9（LightamerTestsApp）+ Project.swift/BUNDLE-MAP 登记 + tuist generate |
| T2 | `9a3e906` | `feat(app): node selection mapping and dynamic node header title` — PipelineDocument maskGroups/MaskItemSummary（组序 = grade 序，init 内与 grades 同批派生）+ node(for:)/displayTitle(for:) 全分支 + EditorNodeHeaderView 动态名 + kind 副标题（未选中逐字节不变）+ PipelineLinkageTests 5（LightamerTestsLayers）+ 登记闭环 |
| T3 | 本提交 | SUMMARY/DECISIONS + GOAL-STATE 续接点（收口批） |

## 全套回归终值（coordinator 批准后实跑）

**`Scripts/test-direct.sh --all` = TOTAL|2217/14/0|723s，EXIT=0**
（2026-09-30 实跑；对照基线 2203/14skip/0fail @ M2-4-1 收口）：

- 计数对账：2203 基线 + **14 新增**（MaskItemSemanticsTests 9
  【App 300→309】+ PipelineLinkageTests 5【Layers 169→174】）= **2217
  精确**（AC7 预估带 2213..2217 上沿命中）；skip 14 精确不变；0 fail；
  全程 723s（< 1135s 预算，与 P1 终跑同值）。
- 逐 bundle：IOP 457/1/0 peakRSS=6793MB · IOPParity 308/2/0 5985MB ·
  Layers 174/2/0 942MB · Library 430/4/0 294MB · Sessions 279/4/0
  1635MB · Export 260/1/0 6733MB · App 309/0/0 1470MB。MEMFAIL（8G
  口径）零触发；host RSS 巡视（2 分钟间隔）全程峰值 3.6G，kill 条款
  未动用。
- 在案 flaky（LayerE2E SIGTRAP 负载型）：本轮未触发（Layers 18s 全绿
  一遍过）。
- 资源监控按批准条款执行：脚本 8G MEMFAIL 机检为准 + 2 分钟巡视。

## AC 总表核验（9 条全绿）

| # | AC | 结果 |
|---|---|---|
| 1 | disabled item 恒等元语义：5 op × 位置矩阵 + 空 enabled = 恒 1 | ✅ 逐像素 Double 参考矩阵（5 op × 首/中/末，真实 plane 值折叠，<1e-6）+ 双圆闭式面积锚（首/末 × 5 op）+ 全 disabled 逐字节 0.7 + 单项 disabled 同通道 + 组单形不受语义污染（testDisabledItemMatrix… / testDisabledPositionAnalyticAreaAnchors / testAllDisabledGroupIsTheConstantOnePassthrough / testGrouplessDrawnIgnoresItemSemantics） |
| 2 | deletionProtected 拦截**双腿**（checker E3）：protected clear/fill 均拒绝且零 history item；非 protected 不变 | ✅ testDeletionProtectedRejectsClear / testDeletionProtectedRejectsFill（mask 保持 + history 不动 + toast 在）+ testUnprotectedClearAndFillBehaviorUnchanged（各恰一条 item + 无 toast）；既有 MaskCommandTests 11/11 零改动全绿 |
| 3 | 蒙版写入点审计表完整 | ✅ DECISIONS 审计表 8 触点逐个定性（2 清空腿拦截 + 6 合法），`git grep` 复跑闭合 |
| 4 | maskGroups 组序 = grade 序；reorder 跟随（Reconnect 复用证明）；item 摘要 parity | ✅ testMaskGroupsProjectInGradeOrder / testMaskGroupsFollowReorderWithoutAnySyncPoint（投影跟随 + 旧投影不动 = 纯派生零双写证明）/ testMaskItemSummaryParityWithTheSpecReadView |
| 5 | node(for:)/displayTitle 全分支；未选中 = 现值逐字节 | ✅ testNodeForIDCoversAllBranches（nil/develop/grade/drt/retouch/未知）+ testDisplayTitleCoversAllBranches（**KEY 恒等断言**——zh catalog 实测 `editor_node_name`→「调色」，契约 = 同键同解析，见 DECISIONS D-M2-4-2-2 勘误）+ header diff 评审 m7（D-M2-4-2-6） |
| 6 | kernel/Metal 零 diff；MaskCombiner 五式公式行零语义改动；面板族零 diff | ✅ 全 plan `git diff --name-only` = 申报集（MaskSpec/MaskCombiner/PipelineDocument/LayerEditingState/EditorNodeHeaderView/Project.swift/两测试/BUNDLE-MAP，无 Metal 文件、无 EditorAdjustmentStackView/InspectorEditSession/面板文件）；MaskCombiner 唯一改动 = drawnGroupPlane 循环顶部一行 continue + 注记 |
| 7 | 全套回归 0 fail，计数 ≈ P1 收口值 + 10..14 | ✅ 2217/14/0（+14 精确，带上沿），对账口径见上 |
| 8 | diff 边界 == 申报文件集 | ✅ T1/T2 各自 `git show --stat` 核：只 add 申报文件；front-matter 集合全覆盖（LESSONS 未触发——无新踩坑） |
| 9 | 新测试文件登记闭环（checker E2） | ✅ MaskItemSemanticsTests.swift 在 Project.swift LightamerTestsApp sources + BUNDLE-MAP `APP 9` 行；PipelineLinkageTests.swift 在 LightamerTestsLayers sources + BUNDLE-MAP `LAYERS 5` 行；各自同 commit tuist generate（T1 `42e2f95` / T2 `9a3e906`） |

## KD 确认与执行期裁定

- KD-1..4 全部按 plan 落地（逐条确认见 DECISIONS「KD 执行确认」；恒等元
  语义、空 enabled 集通道路径名「dt no-form fill-1 leg」在册）。
- 执行期裁定 6 处（D-M2-4-2-1..6）全部在 DECISIONS 备案：测试类两班拆分
  （Swift 6 区域隔离）/ displayTitle 的 Core 本地化豁免 + 未选中契约
  = KEY 恒等勘误 / maskGroups stored let 形态 / maskItems 门面窄实现 /
  MaskOverlayHost payload 重建观察（挂 M2-7 + M2MASK-04）/ m7 域勘误。
  均无行为越界；晨审可推翻（各条附翻转代价）。
- REQUIREMENTS 翻账按派发指令留验收批。
