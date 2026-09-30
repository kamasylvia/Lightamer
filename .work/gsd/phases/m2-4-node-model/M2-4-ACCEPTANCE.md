# M2-4-ACCEPTANCE — phase 级 AC 汇总（M2-4 节点编辑模型，三 plan 全景）

> 汇总批：2026-09-30（M2-4-3 执行 worker 收口产出）。**verify-work 的输入
> 正本**——本文件是三 plan 执行+验收结论的合并对照，签核 VALIDATION 归
> verify-work 独立步（C 档门控第 3 条）。三 plan 各自的独立验收报告 =
> `M2-4-1-ACCEPTANCE.md`（PASS）/ `M2-4-2-ACCEPTANCE.md`（PASS）/ 本 plan
> 验收批待派。

## Phase 交付全景（三 plan × 任务 × commit）

| Plan | 任务 | commit | 交付 |
|---|---|---|---|
| M2-4-1 模型核 | T1 | `22e3b32` | PipelineDocument 只读门面（Graph/ 新目录，纯派生零同步点） |
| | T2 | `02a2835` | 图命令集 7 条（Core 纯 apply + EditorState.apply 唯一入口 + `history_graph_*` 键族） |
| | T3 | `52cf75e` | 所有权框架三层（NodeOwnership + Catalog 零字面量 + addModuleToLayer typed 缝，宽限执行） |
| | T4 | `b7d7acd` | sidecar v4→v5 additive（蒙版三字段 + rawOverrides，hash-isolation 双向机检） |
| | T5 | `48e2b7d` | RAW overrides 持久化接线（恢复腿 re-decode + 写腿透传 + attach 双向缝） |
| | T6 | `d103b9e..` | SUMMARY/DECISIONS/GOAL-STATE/LESSONS L046 |
| M2-4-2 蒙版语义面 + 页签联动 | T1 | `42e2f95` | MaskCombiner enabled 恒等元过滤（kernel 零 diff）+ MaskSpec 访问面 + deletionProtected clear/fill 双腿拦截 |
| | T2 | `9a3e906` | PipelineDocument maskGroups/MaskItemSummary + node(for:)/displayTitle 全分支 + EditorNodeHeaderView 动态名 |
| | T3 | `cda10e7` | SUMMARY/DECISIONS/GOAL-STATE |
| M2-4-3 节点面板 UI + 收口 | T1 | `b4ea439` | NodeCanvasGeometry 纯函数几何 + NodesPanelModel + 面板骨架 + Rail `.nodes` 挂接 |
| | T2 | `e245b46` | Canvas 渲染 + 恒定 Fit + 插入指示线渲染位 + preference 读回机检面 |
| | T3 | `34de49a` | 菜单四项 + 拖卡重连 + `.nodeLocked` 泛化三件套 + mix 滑杆 |
| | T4 | 本提交 | zh 对账 + 全套终跑 + REQUIREMENTS 翻账 + phase 收口三件 |

## M2NODE 全族翻账状态（REQUIREMENTS 对账正本）

| 需求 | 状态 | 交付锚 | 验收 |
|---|---|---|---|
| M2NODE-01 线性链语义 | ✅ Delivered | `22e3b32` | M2-4-1-ACCEPTANCE PASS |
| M2NODE-02 图命令集（undo/redo 保 NodeId） | ✅ Delivered | `02a2835` | M2-4-1-ACCEPTANCE PASS |
| M2NODE-03 有序调整列表 + 18 目录所有权 | **☐ 不勾（框架宽限交付）** | `52cf75e` | M2-4-1-ACCEPTANCE 裁决：目录框架 + typed 校验面 + 宽限执行已交付；**严格面激活归 M2-5**（18 目录收窄时激活，加载/undo/复原零校验维持） |
| M2NODE-04 蒙版 Grade-owned 绑定 | ✅ Delivered（数据/绑定面） | `42e2f95`/`9a3e906` | M2-4-2-ACCEPTANCE PASS；挂账四条在册（stroke payload 复核归 M2-7/M2MASK-04、feather 应用序归 M2MASK-04、面板 UI 归 M2-7、~~zh 滞后~~→P3 收口已闭环 `29 键`） |
| M2NODE-05 sidecar/项目 schema 扩展 | ✅ Delivered（sidecar 腿） | `b7d7acd`/`48e2b7d` | M2-4-1-ACCEPTANCE PASS；`.lalb` 四表零触碰（项目文件腿归 M2-8）；deletionProtected 文件载体挂 M2MASK-04 |
| M2NODE-06 节点面板 UI | ✅ Delivered（本批翻账） | `b4ea439`/`e245b46`/`34de49a` | 本 plan AC 11 条全绿（M2-4-3-SUMMARY 逐条机检）；独立验收批待派 |

## 终态测试计数（对账链）

| 收口点 | 全套 | 增量 | 备注 |
|---|---|---|---|
| M2-4-0 收尾（基线） | 2165/14skip/0fail | — | 七 bundle 拆分 + 8G 门（SPIKE `70e09e5`） |
| M2-4-1 收口 | 2203/14/0（723s） | +38（5+17+6+10） | orchestrator 批准实跑 |
| M2-4-2 收口 | 2217/14/0（723s） | +14（9+5） | coordinator 批准实跑 |
| **M2-4-3 收口（phase 终态）** | **2240/14/0（725s）EXIT=0** | **+23（9+14）** | coordinator 批准实跑；MEMFAIL 零触发（峰值 IOP 6817MB < 8192）；LayerE2E flaky 未触发 |

测试文件登记闭环（checker E2 纪律）：phase 期间 8 个新测试文件逐一在
`Project.swift` 对应 bundle sources + `M2-4-0-BUNDLE-MAP.txt` 行在册
（M2-4-1 四 + M2-4-2 两 + M2-4-3 两，行内计数终值 = 9/14，勘误注记在案）。

## 观察项清单（Manual-Only 走查，非门——verify-work/真机走查批核销）

1. **多层链拖动流畅度**（D-M2-4-CONTEXT-10）：多层链参数拖动 → 级联重算
   目测流畅；不达标后备 = Layout 按 stack hash memo（零语义风险）。
2. **拖卡重连手感**：6pt 阈值起步 + 拖动中滚动锁定（scrollDisabled）+
   指示线回声——触控板/鼠标双输入走查；不达标调阈值常数。
3. **mix 滑杆卡内手感**：Slider（controlSize .mini）与卡拖动手势并行识别；
   live 腿实时渲染、松手恰一条 history。
4. **30 节点 BENCH**：layout 单轮 0.0081ms（BENCH| 观察行，非门量化注记）；
   30 节点面板滚动/Fit 无卡顿为走查确认项。
5. **滚动共存**：拖卡与 ScrollView 滚动的双保险（阈值 + scrollDisabled）
   在触控板惯性滚动下的表现。

## Phase 边界遗留（后续 phase 队列，非缺陷）

- **M2-5**：M2NODE-03 严格面激活（18 目录收窄）+ Develop「调整列表」长期
  归属另裁（CONTEXT Deferred）。
- **M2-6**：DRT 功能体（灰态占位卡文案「DRT arrives with M2-6」退役随行）。
- **M2-7**：Mask Groups 面板（消费 `maskGroups` 投影 + `.nodeLocked` modifier
  + Reconnect 拖组复用）；首组锁三件套消费；stroke 腿 payload 复核
  （D-M2-4-2-5）。
- **M2-8**：`.lalb` mini-git 四表激活（M2-4 已钉数据面）。
- **M2MASK-04**：deletionProtected `.lra` 文件载体 + feather 应用序。
- **自由平移/缩放**：CONTEXT Deferred（节点溢出现实化再议）。
