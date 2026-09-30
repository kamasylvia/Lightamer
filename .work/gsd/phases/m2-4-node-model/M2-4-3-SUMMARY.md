# M2-4-3-SUMMARY — 节点面板 UI + phase 收口（plan M2-4-3，P3 四任务）

> 收口时间：2026-09-30（夜间授权执行批，coordinator 批准全套终跑）。
> plan 正本 = 同目录 `M2-4-3-PLAN.md`（checker 修正版 `c94aa3c`，E4 编号闭环 +
> E2 登记纪律版）。配套 = `M2-4-3-DECISIONS.md`（KD 确认 + D-M2-4-3-1..8）+
> `M2-4-ACCEPTANCE.md`（phase 级 AC 汇总，verify-work 输入正本）。**未 push**。

## 任务与提交

| 任务 | commit | 内容 |
|---|---|---|
| T1 | `b4ea439` | `feat(ui): nodes panel model with canvas geometry core` — NodeCanvasGeometry 纯函数几何正本（layout/edges/insertionIndex/insertionLineY/fitScale，零 UI 依赖）+ NodesPanelModel（投影订阅 + 选中写 `selectedLayerID` + 命令路由 + 锁定判定 + mix 双腿）+ EditorNodesPanelView 骨架（Canvas 连线层 + 三类真视图卡 + 点选）+ EditorToolRailView `.nodes` 空态替换 + 两测试文件 20 tests + Project.swift/BUNDLE-MAP 登记 + tuist generate |
| T2 | `e245b46` | `feat(ui): linear chain canvas rendering with fit` — 恒定 auto-Fit（scaleEffect + 内容帧同步收缩）+ Fit 按钮（scroll 回链头）+ 插入指示线渲染位 + DRT 灰态占位文案（`editor_node_drt_placeholder`）+ NodeCardFramesKey 读回面 + 渲染几何回归测试（NSHostingView 实测帧 = Layout，AC3 机检） |
| T3 | `34de49a` | `feat(ui): node card interactions with drag reconnect and lock modifier` — 上下文菜单四项（availableActions 纯函数穷举）+ 工具栏「+」+ Rename alert + 拖卡重连手势（6pt 阈值 + scrollDisabled 双保险 + 指示线 + 松手 reconnectGrade，自槽 no-op）+ `.nodeLocked(_:hint:)` 泛化三件套 modifier（NodeLockedBadge + 拦截 + 提示）+ mix 滑杆（live/commit 腿 + 草稿缓冲） |
| T4 | 本提交 | zh 对账（29 键 zh/en 落盘 + 退役键删除 + PipelineLinkageTests 断言 KEY 化联动）+ 全套终跑 + REQUIREMENTS M2NODE-06 翻账 + SUMMARY/DECISIONS/ACCEPTANCE/GOAL-STATE + BUNDLE-MAP 行终值勘误 |

## 全套回归终值（coordinator 批准后实跑）

**`Scripts/test-direct.sh --all` = TOTAL|2240/14/0|725s，EXIT=0**
（2026-09-30 实跑；对照基线 2217/14skip/0fail @ M2-4-2 收口）：

- 计数对账：2217 基线 + **23 新增**（NodeCanvasGeometryTests 9
  【8 T1 几何 + 1 T2 渲染读回】+ NodesPanelModelTests 14【12 T1 + 2 T3】）
  = **2240 精确**（App 309→332 逐值吻合）。⚠️ 报备口径笔误在案：申请时按
  22/2239 申报，实际 T2 已给几何文件 +1 例——以实跑为准；BUNDLE-MAP
  行内计数 8→9 勘误随收口 commit 修正（登记纪律闭环）。
- 逐 bundle：IOP 457/1/0 peakRSS=6817MB · IOPParity 308/2/0 5987MB ·
  Layers 174/2/0 1013MB · Library 430/4/0 295MB · Sessions 279/4/0
  1633MB · Export 260/1/0 6790MB · App 332/0/0 1473MB。**MEMFAIL（8G
  口径）零触发**（全 bundle ru_maxrss < 8192MB，脚本机检为准）；host RSS
  巡视（2 分钟间隔，7 轮）= 整机含系统进程 4.6-9.4GB 波动，测试宿主
  侧以脚本 ru_maxrss 判据为准（批准条款双轨，机检未触发即不杀）。
- 在案 flaky（LayerE2E SIGTRAP 负载型）：本轮未触发（Layers 19s 全绿
  一遍过）。

## AC 总表核验（plan 11 条全绿）

| # | AC | 结果 |
|---|---|---|
| 1 | 几何正本：layout 单调/居中 + edges 连接 + insertionIndex 阈值 + fitScale 边界 | ✅ NodeCanvasGeometryTests 9/9（单调+居中+间距+insets / 0-1-N 面 / edges=N-1 邻接中心 / 阈值矩阵含 DRT 末边界与自槽语义 / 退化面 / 指示线镜像 / fitScale 三界） |
| 2 | 模型：投影重建 + 选中写 selectedLayerID 分支 + apply 路由 + isLocked | ✅ NodesPanelModelTests 14/14（投影跟随 / grade→UUID、develop/drt/nil→nil / 真壳路由恰一条 item / 锁矩阵） |
| 3 | 三段链渲染帧几何 = Layout + Fit 边界 | ✅ 机检方式 = **NodeCardFramesKey preference 读回**（DECISIONS D-M2-4-3-5）：真面板 NSHostingView 实装、逐卡帧与 Layout 逐项相等（minX/minY/w/h accuracy 0.01）——经真实 SwiftUI layout 系统测量，非源码镜像；fitScale 边界（不超高=1/超高<1/零容器=1）几何测试钉 |
| 4 | 交互：菜单四项路由 + 拖卡 → reconnect 参数 + locked 拒发 + mix 恰一条 history | ✅ availableActions 表断言（grade 四项含 delete、端点空）+ 拖拽序→reconnect 参数断言（insertionIndex 注入 + 移动后 id 序断言）+ locked 拒发（零 item/零 stack 移动/零 toast）+ mix live 零 item、commit 恰一条且 label 同键 |
| 5 | 锁定三件套 + modifier 泛化签名（M2-7 可消费） | ✅ `NodeLockedBadge.marker` 稳定断言 + 卡 marker 穷举测试；泛化签名 `.nodeLocked(_ locked: Bool, hint: @escaping () -> Void) -> some View`（零节点语义，DECISIONS D-M2-4-3-6 记录语义冻结面） |
| 6 | Rail 改造仅 .nodes case；`LightamerCore/` 零 diff；裸 hex 仅 ThemeTokens | ✅ `git diff EditorToolRailView.swift` = 环境声明 1 行 + case 体 1 处（history/versions 面 diff 零，逐 hunk 评审）；`git diff --name-only b4ea439^..34de49a` 无 LightamerCore 文件；`git grep -En '#[0-9A-Fa-f]{6}'` Nodes/ 目录零命中 |
| 7 | zh 对账 exit 0；nodes/graph 键族 zh 值全在 | ✅ `Scripts/zh-audit.py --check` **PASS**（1185 source keys / 1397 catalog keys / zh complete / locale = {en,zh}）；语义级对账：kept=1368 零改写 + added=29 + removed=1（退役 `editor_nodes_placeholder`，孤儿防 sentinel） |
| 8 | 全套回归 0 fail，计数 ≈ P2 收口值 + 12..18 | ✅ 2240/14/0 = 2217 + 23（23 略超 12..18 预估带：几何 8+模型 12 在 T1 一次建齐 20 + T2 读回 1 + T3 补组 2，带因测试文件的增量跨任务累积；对账口径见上，逐 bundle 双读闭合） |
| 9 | REQUIREMENTS M2NODE-01..06 翻账在册；他族零 diff | ✅ M2NODE-06 Delivered 落账（01/02/04/05 验收批已翻）；M2NODE-03 维持不勾（严格面激活归 M2-5，M2-4-1 验收裁决）；M2NODE-04 注记④ zh 滞后挂账同批闭环注记；`git diff .work/gsd/REQUIREMENTS.md` 仅 M2NODE 族三处 |
| 10 | diff 边界 == 申报文件集；收口四件同批落盘 | ✅ 三代码 commit 逐 `git show --stat` 核对 = 申报集（3 新 Nodes/ 文件 + Rail + 2 测试 + Project.swift + BUNDLE-MAP；T2/T3 无新文件不触 Project.swift）；收口批 = catalog + PipelineLinkageTests 联动（finding③ 钦定）+ BUNDLE-MAP 勘误 + 四 md + REQUIREMENTS |
| 11 | 新测试文件登记闭环（checker E2） | ✅ 两文件在 Project.swift LightamerTestsApp sources（字母序）+ BUNDLE-MAP 两行（终值 9/14，勘误注记在案）+ T1 同 commit `tuist generate`（T2/T3 零新文件未重复跑） |

## 30 节点 BENCH 观察行（plan T2 AC，非门）

`BENCH| NodeCanvasGeometry.layout 30 nodes x1000 rounds avg=0.0081 ms/round`
——纯函数 layout 单轮亚毫秒（D-M2-4-CONTEXT-5「帧成本可忽略」量化注记）；
真机拖动流畅度 = Manual-Only 走查观察项（D-M2-4-CONTEXT-10，非门，挂
ACCEPTANCE 观察清单）。

## 偏差与登记

- 执行期裁定 8 处（D-M2-4-3-1..8）全部在 DECISIONS 备案，无行为越界；
  晨审可推翻（各条附翻转代价）。要点：computed 投影替代 stored 重建、
  insertionIndex 边界集含 DRT 末边界（自槽 = no-op 语义）、Fit 按钮 v1
  语义 = scroll 重置、BENCH 提前随 T1 落盘、报备计数笔误勘误。
- REQUIREMENTS 翻账：M2NODE-06 本批翻账；签核 VALIDATION 留 verify-work
  （C 档门控第 3 条）。
